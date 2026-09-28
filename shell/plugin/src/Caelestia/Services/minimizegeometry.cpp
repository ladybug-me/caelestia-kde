// SPDX-License-Identifier: GPL-3.0-only
#include "minimizegeometry.hpp"

#include <qpa/qplatformnativeinterface.h>

#include <QGuiApplication>
#include <QQuickWindow>
#include <QWindow>

#include "plasmawindows.hpp"

namespace caelestia::services {

namespace {

wl_surface* surfaceFor(QWindow* window) {
    if (!window || !window->handle()) {
        return nullptr;
    }

    auto* native = QGuiApplication::platformNativeInterface();
    if (!native) {
        return nullptr;
    }
    return static_cast<wl_surface*>(native->nativeResourceForWindow(QByteArrayLiteral("surface"), window));
}

} // namespace

MinimizeGeometry::MinimizeGeometry(QObject* parent)
    : QObject(parent) {
    connect(PlasmaWindows::instance(), &PlasmaWindows::handleLost, this, [this](const QString& uuid) {
        m_published.remove(uuid);
    });
}

void MinimizeGeometry::setGeometry(QQuickItem* anchor, const QString& uuid, int x, int y, int width, int height) {
    if (!anchor || uuid.isEmpty() || width <= 0 || height <= 0) {
        return;
    }

    auto* surface = surfaceFor(anchor->window());
    if (!surface) {
        return;
    }

    const auto key = PlasmaWindows::normaliseUuid(uuid);
    const QRect rect(x, y, width, height);
    // Key by surface too: two monitors with mirrored docks can compute the
    // same rect for the same window, and the dedupe must not drop the second
    // surface's publish.
    const quintptr surfaceKey = reinterpret_cast<quintptr>(surface);
    if (m_published.value(key).value(surfaceKey) == rect) {
        return;
    }

    auto* handle = PlasmaWindows::instance()->handleFor(key);
    if (!handle) {
        return;
    }

    handle->set_minimized_geometry(surface, static_cast<uint32_t>(std::max(0, rect.x())),
        static_cast<uint32_t>(std::max(0, rect.y())), static_cast<uint32_t>(rect.width()),
        static_cast<uint32_t>(rect.height()));
    m_published[key].insert(surfaceKey, rect);
}

void MinimizeGeometry::clearGeometry(QQuickItem* anchor, const QString& uuid) {
    if (uuid.isEmpty()) {
        return;
    }

    const auto key = PlasmaWindows::normaliseUuid(uuid);
    if (!m_published.contains(key)) {
        return;
    }

    if (auto* surface = anchor ? surfaceFor(anchor->window()) : nullptr) {
        if (auto* handle = PlasmaWindows::instance()->handleFor(key)) {
            handle->unset_minimized_geometry(surface);
        }
        m_published[key].remove(reinterpret_cast<quintptr>(surface));
        if (!m_published.value(key).isEmpty()) {
            return;
        }
    }
    m_published.remove(key);
}

} // namespace caelestia::services
