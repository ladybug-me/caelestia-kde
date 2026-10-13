// SPDX-License-Identifier: GPL-3.0-only
#include "windowicon.hpp"

#include <qbuffer.h>
#include <qcryptographichash.h>
#include <qdir.h>
#include <qfile.h>
#include <qimage.h>
#include <qlist.h>
#include <qloggingcategory.h>
#include <qstandardpaths.h>

#include <X11/Xatom.h>
#include <X11/Xlib.h>
#include <X11/Xutil.h>

namespace caelestia::services {

namespace {

Q_LOGGING_CATEGORY(logWindowIcon, "caelestia.services.windowicon");

/// RAII for the X display, so every early return still closes it.
class XDisplay {
public:
    XDisplay()
        : m_dpy(XOpenDisplay(nullptr)) {}

    ~XDisplay() {
        if (m_dpy) {
            XCloseDisplay(m_dpy);
        }
    }

    XDisplay(const XDisplay&) = delete;
    XDisplay& operator=(const XDisplay&) = delete;

    operator Display*() const { return m_dpy; }

    bool isValid() const { return m_dpy != nullptr; }

private:
    Display* m_dpy;
};

unsigned char* fetchProperty(Display* dpy, Window win, Atom prop, Atom type, unsigned long* count) {
    Atom actualType;
    int actualFormat;
    unsigned long bytesAfter;
    unsigned char* data = nullptr;

    if (XGetWindowProperty(dpy, win, prop, 0, 0, False, type, &actualType, &actualFormat, count, &bytesAfter, &data) !=
        Success) {
        return nullptr;
    }
    if (data) {
        XFree(data);
        data = nullptr;
    }
    if (bytesAfter == 0) {
        return nullptr;
    }

    const long words = static_cast<long>((bytesAfter + 3) / 4);
    if (XGetWindowProperty(
            dpy, win, prop, 0, words, False, type, &actualType, &actualFormat, count, &bytesAfter, &data) != Success) {
        return nullptr;
    }
    return data;
}

QString windowTitle(Display* dpy, Window win) {
    const Atom netName = XInternAtom(dpy, "_NET_WM_NAME", True);
    if (netName != None) {
        unsigned long count = 0;
        if (auto* data = fetchProperty(dpy, win, netName, AnyPropertyType, &count)) {
            const auto title = QString::fromUtf8(reinterpret_cast<const char*>(data));
            XFree(data);
            if (!title.isEmpty()) {
                return title;
            }
        }
    }

    char* legacy = nullptr;
    if (XFetchName(dpy, win, &legacy) && legacy) {
        const auto title = QString::fromUtf8(legacy);
        XFree(legacy);
        return title;
    }
    return QString();
}

qint64 windowPid(Display* dpy, Window win) {
    const Atom netWmPid = XInternAtom(dpy, "_NET_WM_PID", True);
    if (netWmPid == None) {
        return -1;
    }

    unsigned long count = 0;
    auto* data = fetchProperty(dpy, win, netWmPid, XA_CARDINAL, &count);
    if (!data) {
        return -1;
    }
    const auto pid = static_cast<qint64>(*reinterpret_cast<const unsigned long*>(data) & 0xffffffff);
    XFree(data);
    return pid > 0 ? pid : -1;
}

bool matchesClass(Display* dpy, Window win, const QString& wmClass) {
    XClassHint hint{};
    if (!XGetClassHint(dpy, win, &hint)) {
        return false;
    }

    const auto name = QString::fromUtf8(hint.res_name ? hint.res_name : "");
    const auto cls = QString::fromUtf8(hint.res_class ? hint.res_class : "");
    if (hint.res_name) {
        XFree(hint.res_name);
    }
    if (hint.res_class) {
        XFree(hint.res_class);
    }
    return name.compare(wmClass, Qt::CaseInsensitive) == 0 || cls.compare(wmClass, Qt::CaseInsensitive) == 0;
}

bool matchesTitle(Display* dpy, Window win, const QString& wmClass, const QString& title) {
    // KWin often reports the title as the "class" for these windows (Minecraft
    // shows up as "Minecraft* 1.21.11"), so fall back to matching on it.
    const auto actual = windowTitle(dpy, win);
    if (actual.isEmpty()) {
        return false;
    }
    return actual == wmClass || (!title.isEmpty() && actual == title);
}

QImage decodeLargest(const unsigned long* data, unsigned long count) {
    QImage best;
    unsigned long i = 0;

    while (i + 2 <= count) {
        const auto w = static_cast<int>(data[i]);
        const auto h = static_cast<int>(data[i + 1]);
        i += 2;

        if (w <= 0 || h <= 0) {
            break;
        }
        const unsigned long pixels = static_cast<unsigned long>(w) * static_cast<unsigned long>(h);
        if (pixels > count - i) {
            break;
        }

        if (static_cast<qint64>(w) * h > static_cast<qint64>(best.width()) * best.height()) {
            QImage image(w, h, QImage::Format_ARGB32);
            for (int y = 0; y < h; ++y) {
                auto* line = reinterpret_cast<QRgb*>(image.scanLine(y));
                for (int x = 0; x < w; ++x) {
                    line[x] = static_cast<QRgb>(data[i + static_cast<unsigned long>(y) * w + x] & 0xffffffff);
                }
            }
            best = image;
        }

        i += pixels;
    }

    return best;
}

} // namespace

WindowIcon::WindowIcon(QObject* parent)
    : QObject(parent) {}

QString WindowIcon::extract(const QString& wmClass, const QString& title, qint64 pid) {
    if (wmClass.isEmpty() && pid <= 0) {
        return QString();
    }

    const QString key = pid > 0 ? QString::number(pid) : wmClass;

    XDisplay display;
    if (!display.isValid()) {
        qCDebug(logWindowIcon) << "no X display; only XWayland windows carry _NET_WM_ICON";
        return QString();
    }

    Display* dpy = display;
    const Atom netWmIcon = XInternAtom(dpy, "_NET_WM_ICON", True);
    const Atom clientList = XInternAtom(dpy, "_NET_CLIENT_LIST", True);
    if (netWmIcon == None || clientList == None) {
        return QString();
    }

    unsigned long windowCount = 0;
    auto* rawWindows = fetchProperty(dpy, DefaultRootWindow(dpy), clientList, XA_WINDOW, &windowCount);
    if (!rawWindows) {
        return QString();
    }
    const auto* windows = reinterpret_cast<const Window*>(rawWindows);

    QList<Window> candidates;
    bool havePidMatch = false;
    for (unsigned long i = 0; i < windowCount; ++i) {
        if (pid > 0 && windowPid(dpy, windows[i]) == pid) {
            if (!havePidMatch) {
                havePidMatch = true;
                candidates.clear();
            }
            candidates.append(windows[i]);
        } else if (!havePidMatch && !wmClass.isEmpty() &&
                   (matchesClass(dpy, windows[i], wmClass) || matchesTitle(dpy, windows[i], wmClass, title))) {
            candidates.append(windows[i]);
        }
    }
    XFree(rawWindows);

    QImage icon;
    for (const auto win : candidates) {
        unsigned long iconCount = 0;
        auto* rawIcon = fetchProperty(dpy, win, netWmIcon, XA_CARDINAL, &iconCount);
        if (!rawIcon) {
            continue;
        }

        icon = decodeLargest(reinterpret_cast<const unsigned long*>(rawIcon), iconCount);
        XFree(rawIcon);
        if (!icon.isNull()) {
            break;
        }
    }

    if (icon.isNull()) {
        return QString();
    }

    QByteArray png;
    QBuffer buffer(&png);
    buffer.open(QIODevice::WriteOnly);
    if (!icon.save(&buffer, "PNG")) {
        qCWarning(logWindowIcon) << "could not encode icon for" << key;
        return QString();
    }
    buffer.close();

    const auto cacheRoot =
        QStandardPaths::writableLocation(QStandardPaths::GenericCacheLocation) + QStringLiteral("/caelestia/winicons");
    const auto digest = QString::fromLatin1(QCryptographicHash::hash(png, QCryptographicHash::Sha256).toHex().left(16));
    const auto path = cacheRoot + QStringLiteral("/") + digest + QStringLiteral(".png");

    if (!QFile::exists(path)) {
        QFile file(path);
        if (!QDir().mkpath(cacheRoot) || !file.open(QIODevice::WriteOnly) || file.write(png) != png.size()) {
            qCWarning(logWindowIcon) << "could not write icon cache for" << key << "to" << path;
            return QString();
        }
    }

    emit extracted(key, path);
    return path;
}

} // namespace caelestia::services
