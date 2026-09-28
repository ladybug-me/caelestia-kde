#include "gpu.hpp"

#include <qdir.h>
#include <qdiriterator.h>
#include <qfile.h>
#include <qregularexpression.h>

#include <QTimer>
#include <array>
#include <cmath>
#include <functional>

#include "../Config/rootnodes.hpp"
#include "../Config/serviceconfig.hpp"
#include "sensorslib.hpp"

namespace caelestia::services {

namespace {

// A card with a busy-percent node is a GPU we can read usage from without a vendor tool
QStringList gpuBusyFiles() {
    static const QRegularExpression cardRe(QStringLiteral("^card\\d+$"));

    QStringList files;
    QDirIterator it(QStringLiteral("/sys/class/drm"), QDir::Dirs | QDir::NoDotAndDotDot);
    while (it.hasNext()) {
        const QString path = it.next();
        if (!cardRe.match(it.fileName()).hasMatch()) {
            continue;
        }
        const QString busy = path + QStringLiteral("/device/gpu_busy_percent");
        if (QFile::exists(busy)) {
            files << busy;
        }
    }
    return files;
}

bool hasIntelGpu() {
    static const QRegularExpression cardRe(QStringLiteral("^card\\d+$"));

    QDirIterator it(QStringLiteral("/sys/class/drm"), QDir::Dirs | QDir::NoDotAndDotDot);
    while (it.hasNext()) {
        const QString path = it.next();
        if (!cardRe.match(it.fileName()).hasMatch()) {
            continue;
        }
        if (QFile::exists(path + QStringLiteral("/gt/gt0/rps_cur_freq_mhz"))) {
            return true;
        }
    }
    return false;
}

// Runtime power management state of a PCI device, straight from sysfs. The
// whole point of reading it: these nodes are plain device metadata, so the
// read never wakes a suspended card - unlike any vendor query tool, which
// initializes the driver and pulls the card out of sleep to ask it a question.
enum class PciPower {
    Active,
    Suspended,
    Unknown
};

PciPower pciPowerState(const QString& pciPath) {
    if (pciPath.isEmpty()) {
        return PciPower::Unknown;
    }

    // runtime_status: active/suspended/unknown/error, managed by runtime PM.
    QFile runtime(pciPath + QStringLiteral("/power/runtime_status"));
    if (runtime.open(QIODevice::ReadOnly | QIODevice::Text)) {
        const QString s = QString::fromUtf8(runtime.readAll()).trimmed().toLower();
        runtime.close();
        if (s == QStringLiteral("suspended")) {
            return PciPower::Suspended;
        }
        if (s == QStringLiteral("active")) {
            return PciPower::Active;
        }
        return PciPower::Unknown;
    }

    // power_state as a fallback on older kernels: d0 is on, anything deeper
    // is a sleeping device.
    QFile power(pciPath + QStringLiteral("/power_state"));
    if (power.open(QIODevice::ReadOnly | QIODevice::Text)) {
        const QString s = QString::fromUtf8(power.readAll()).trimmed().toLower();
        power.close();
        if (s == QStringLiteral("d0")) {
            return PciPower::Active;
        }
        if (s.startsWith(QStringLiteral("d"))) {
            return PciPower::Suspended;
        }
    }

    return PciPower::Unknown;
}

QString cleanName(QString s) {
    static const QRegularExpression noise(
        QStringLiteral("\\(R\\)|\\(TM\\)|Graphics"), QRegularExpression::CaseInsensitiveOption);
    static const QRegularExpression spaces(QStringLiteral("\\s+"));
    s.replace(noise, QString());
    s.replace(spaces, QStringLiteral(" "));
    return s.trimmed();
}

QString parseNvidiaName(const QByteArray& out) {
    const QString first = QString::fromUtf8(out).split(u'\n').value(0).trimmed();
    return first.isEmpty() ? QString() : cleanName(first);
}

QString parseGlxinfoName(const QByteArray& out) {
    const QStringList lines = QString::fromUtf8(out).split(u'\n');
    for (const QString& line : lines) {
        const qsizetype idx = line.indexOf(QStringLiteral("Device:"));
        if (idx < 0) {
            continue;
        }

        QString rest = line.mid(idx + 7);
        const qsizetype paren = rest.indexOf(u'(');
        if (paren >= 0) {
            rest = rest.left(paren);
        }

        const QString cleaned = cleanName(rest);
        if (!cleaned.isEmpty()) {
            return cleaned;
        }
    }

    return QString();
}

// A display-controller line from lspci: the bracketed card name, or the text
// after the class colon when the bracket form is missing. With -nn the line
// also carries id-shaped brackets - the class code ([0300]) and the vendor
// device id ([10de:2484]) - which are not names, so they are skipped.
QString parseLspciName(const QByteArray& out) {
    const QString line = QString::fromUtf8(out).trimmed();

    static const QRegularExpression bracketRe(QStringLiteral("\\[([^\\]]+)\\]"));
    static const QRegularExpression idRe(QStringLiteral("^[0-9a-fA-F]{4}(:[0-9a-fA-F]{4})?$"));
    QString name;
    for (auto it = bracketRe.globalMatch(line); it.hasNext();) {
        const auto match = it.next();
        if (!idRe.match(match.captured(1)).hasMatch()) {
            name = match.captured(1);
        }
    }
    if (!name.isEmpty()) {
        return cleanName(name);
    }

    static const QRegularExpression colonRe(QStringLiteral(":\\s+(.+)"));
    const auto colon = colonRe.match(line);
    if (colon.hasMatch()) {
        // Drop a trailing vendor id and/or revision that the colon form can carry.
        static const QRegularExpression tailRe(
            QStringLiteral("\\s*\\[[0-9a-fA-F]{4}(:[0-9a-fA-F]{4})?\\](\\s*\\(rev[^)]*\\))?\\s*$"));
        return cleanName(colon.captured(1).replace(tailRe, QString()));
    }

    return QString();
}

struct DisplayController {
    QString slot; // PCI slot as lspci -D prints it, e.g. "0000:01:00.0"
    QString name;
    bool nvidia = false;
};

QList<DisplayController> parseDisplayControllers(const QByteArray& out) {
    // -D always prefixes the domain, so the slot is the exact sysfs directory name.
    static const QRegularExpression slotRe(
        QStringLiteral("^([0-9a-fA-F]{4}:[0-9a-fA-F]{2}:[0-9a-fA-F]{2}\\.[0-9a-fA-F])\\s"));
    static const QRegularExpression classRe(
        QStringLiteral("vga|3d controller|display"), QRegularExpression::CaseInsensitiveOption);

    QList<DisplayController> controllers;
    const QStringList lines = QString::fromUtf8(out).split(u'\n');
    for (const QString& line : lines) {
        const auto slot = slotRe.match(line);
        if (!slot.hasMatch() || !classRe.match(line).hasMatch()) {
            continue;
        }
        DisplayController controller;
        controller.slot = slot.captured(1);
        // -nn prints vendor:device ids in brackets, so 10de is the reliable NVIDIA
        // signal; the name match only covers lspci builds that ignore -nn.
        controller.nvidia =
            line.contains(QStringLiteral("[10de:")) || line.contains(QStringLiteral("nvidia"), Qt::CaseInsensitive);
        controller.name = parseLspciName(line.toUtf8());
        controllers.append(controller);
    }
    return controllers;
}

// Maps an lspci -D slot to its sysfs device directory. With -D the slot is the
// full domain:bus:device.function name sysfs uses, so this is a direct lookup;
// the suffix scan only serves slots printed without a domain.
QString pciDevicePath(const QString& slot) {
    if (slot.isEmpty()) {
        return QString();
    }
    const QString direct = QStringLiteral("/sys/bus/pci/devices/") + slot;
    if (QFile::exists(direct)) {
        return direct;
    }
    QDirIterator it(QStringLiteral("/sys/bus/pci/devices"), QDir::Dirs | QDir::NoDotAndDotDot);
    while (it.hasNext()) {
        const QString path = it.next();
        if (it.fileName().endsWith(u':' + slot)) {
            return path;
        }
    }
    return QString();
}

struct NameSource {
    QString program;
    QStringList args;
    QString (*parse)(const QByteArray&);
};

// Fallback name probes, used when lspci itself is unavailable. The NVIDIA
// probe stays first: its result doubles as the type probe (see finishNameSource).
const std::array<NameSource, 2>& nameSources() {
    static const std::array<NameSource, 2> sources = { {
        { QStringLiteral("nvidia-smi"), { QStringLiteral("--query-gpu=name"), QStringLiteral("--format=csv,noheader") },
            &parseNvidiaName },
        { QStringLiteral("glxinfo"), { QStringLiteral("-B") }, &parseGlxinfoName },
    } };
    return sources;
}

constexpr int kNvidiaSource = 0;

} // namespace

Gpu::Gpu(QObject* parent)
    : TickingService(parent) {
    m_busyFiles = gpuBusyFiles();

    auto* svc = caelestia::config::ConfigSingleton::instance()->services();
    m_userType = parseType(svc->gpuType());
    QObject::connect(svc, &caelestia::config::ServiceConfig::gpuTypeChanged, this, [this, svc] {
        setUserType(parseType(svc->gpuType()));
    });

    QTimer::singleShot(5000, this, [this] {
        detectGpu();
    });
}

Gpu::Type Gpu::type() const {
    return m_userType == Auto ? m_autoType : m_userType;
}

Gpu::Type Gpu::userType() const {
    return m_userType;
}

Gpu::Type Gpu::autoType() const {
    return m_autoType;
}

QString Gpu::name() const {
    return m_name;
}

qreal Gpu::percentage() const {
    return m_percentage;
}

qreal Gpu::temperature() const {
    return m_temperature;
}

void Gpu::setUserType(Type value) {
    if (value == m_userType) {
        return;
    }
    const Type prevDerived = type();
    m_userType = value;
    Q_EMIT userTypeChanged();
    if (type() != prevDerived) {
        Q_EMIT typeChanged();
    }

    if (value == Auto) {
        detectGpu();
    }
}

void Gpu::setAutoType(Type value) {
    if (value == m_autoType) {
        return;
    }
    const Type prevDerived = type();
    m_autoType = value;
    Q_EMIT autoTypeChanged();
    if (type() != prevDerived) {
        Q_EMIT typeChanged();
    }
}

void Gpu::setName(QString value) {
    if (value == m_name) {
        return;
    }
    m_name = std::move(value);
    Q_EMIT nameChanged();
}

void Gpu::tick() {
    const Type t = type();
    if (t == Generic) {
        readGenericUsage();
        readGpuTemperature();
    } else if (t == Nvidia) {
        // Asking a sleeping card for its usage is what keeps it awake: every
        // nvidia-smi run initializes the driver and pulls the device to P0.
        // Reading the runtime power state from sysfs does not touch the card,
        // so a suspended dGPU stays suspended and reports zero, and the query
        // only runs when something else already woke the card (#588, #595).
        if (pciPowerState(m_nvidiaPciPath) == PciPower::Active) {
            startNvidiaUsage();
        } else {
            resetReadings();
        }
    } else {
        resetReadings();
    }
}

void Gpu::resetReadings() {
    if (std::abs(m_percentage) > 0.0001) {
        m_percentage = 0.0;
        Q_EMIT percentageChanged();
    }
    if (std::abs(m_temperature) > 0.05) {
        m_temperature = 0.0;
        Q_EMIT temperatureChanged();
    }
}

void Gpu::detectGpu() {
    if (m_detecting) {
        return;
    }
    m_detecting = true;

    // lspci reads PCI metadata from sysfs, so unlike the old probe chain it
    // never wakes a runtime-suspended dGPU just to learn what is installed.
    // -D keeps the PCI domain in the slot (exact sysfs names), -nn adds the
    // vendor:device ids (exact vendor match). The nvidia-smi probe runs later,
    // and only when the card is awake.
    runProcess(QStringLiteral("lspci"), { QStringLiteral("-Dnn") }, [this](const QByteArray& out) {
        finishLspciProbe(out);
    });
}

void Gpu::finishLspciProbe(const QByteArray& out) {
    if (out.trimmed().isEmpty()) {
        // lspci missing or failed: fall back to the old probe chain, which
        // derives type from nvidia-smi and the name from glxinfo.
        tryNameSource(0);
        return;
    }

    const QList<DisplayController> controllers = parseDisplayControllers(out);
    const DisplayController* nvidia = nullptr;
    const DisplayController* other = nullptr;
    for (const DisplayController& controller : controllers) {
        if (controller.nvidia && !nvidia) {
            nvidia = &controller;
        } else if (!controller.nvidia && !other) {
            other = &controller;
        }
    }

    if (!nvidia) {
        // No NVIDIA hardware, so the machines that the old chain probed with
        // nvidia-smi first never run that probe at all now.
        m_nvidiaPciPath.clear();
        setAutoType(!m_busyFiles.isEmpty() || hasIntelGpu() ? Generic : None);
        if (other && !other->name.isEmpty()) {
            setName(other->name);
        }
        m_detecting = false;
        return;
    }

    m_nvidiaPciPath = pciDevicePath(nvidia->slot);
    if (!nvidia->name.isEmpty()) {
        setName(nvidia->name);
    }

    // A suspended NVIDIA device is being power-managed by a bound driver;
    // its name came from lspci, so there is nothing left that justifies
    // waking the card here. nvidia-smi first runs from a tick that finds
    // the card awake, or immediately below when it already is.
    if (pciPowerState(m_nvidiaPciPath) == PciPower::Suspended) {
        setAutoType(Nvidia);
        m_detecting = false;
        return;
    }

    probeNvidiaCapability();
}

// Asks nvidia-smi once whether the proprietary driver answers. On the old
// chain this was the first probe every machine ran; now only machines with
// NVIDIA hardware that is already awake get here.
void Gpu::probeNvidiaCapability() {
    runProcess(QStringLiteral("nvidia-smi"),
        { QStringLiteral("--query-gpu=name"), QStringLiteral("--format=csv,noheader") }, [this](const QByteArray& out) {
            const QString name = parseNvidiaName(out);
            setAutoType(!name.isEmpty() ? Nvidia : (!m_busyFiles.isEmpty() || hasIntelGpu() ? Generic : None));
            if (!name.isEmpty()) {
                setName(std::move(name));
            }
            m_detecting = false;
        });
}

void Gpu::tryNameSource(int index) {
    const NameSource& src = nameSources().at(static_cast<std::size_t>(index));
    runProcess(src.program, src.args, [this, index, parse = src.parse](const QByteArray& out) {
        finishNameSource(index, parse(out));
    });
}

void Gpu::finishNameSource(int index, QString name) {
    if (index == kNvidiaSource) {
        setAutoType(!name.isEmpty() ? Nvidia : (m_busyFiles.isEmpty() && !hasIntelGpu() ? None : Generic));
    }

    if (!name.isEmpty()) {
        setName(std::move(name));
        m_detecting = false;
        return;
    }

    if (index + 1 < static_cast<int>(nameSources().size())) {
        tryNameSource(index + 1);
    } else {
        m_detecting = false;
    }
}

void Gpu::runProcess(const QString& program, const QStringList& args, std::function<void(const QByteArray&)> callback) {
    auto* proc = new QProcess(this);
    proc->setStandardErrorFile(QProcess::nullDevice());

    // Deliver the result exactly once, then tear the process down. A crash or a
    // missing binary yields empty output so the caller can fall through gracefully:
    // only FailedToStart skips finished(), and a crash reports CrashExit there.
    const auto finish = [proc, callback = std::move(callback)](const QByteArray& out) {
        callback(out);
        proc->deleteLater();
    };

    QObject::connect(proc, &QProcess::finished, this, [finish, proc](int, QProcess::ExitStatus status) {
        finish(status == QProcess::NormalExit ? proc->readAllStandardOutput() : QByteArray());
    });
    QObject::connect(proc, &QProcess::errorOccurred, this, [finish](QProcess::ProcessError err) {
        if (err == QProcess::FailedToStart) {
            finish(QByteArray());
        }
    });

    proc->start(program, args);
}

void Gpu::readGenericUsage() {
    const QStringList cards =
        QDir(QStringLiteral("/sys/class/drm"))
            .entryList(QStringList() << QStringLiteral("card*"), QDir::Dirs | QDir::NoDotAndDotDot);

    qreal maxPerc = -1.0;

    for (const QString& card : cards) {
        QFile f(QStringLiteral("/sys/class/drm/%1/device/gpu_busy_percent").arg(card));
        if (!f.open(QIODevice::ReadOnly | QIODevice::Text)) {
            continue;
        }
        bool ok = false;
        const qreal v = f.readAll().trimmed().toDouble(&ok);
        f.close();
        if (ok && v > maxPerc) {
            maxPerc = v;
        }
    }

    // Pass 2: Intel iGPUs have no busy-percent node. The i915 engines report
    // real per-engine busy percentages, which is what usage should mean; only
    // cards without an engines directory fall back to the clock ratio, which
    // reads far too high on an idle iGPU because an idle card does not
    // necessarily drop out of its high clock range (#588).
    for (const QString& card : cards) {
        if (QFile::exists(QStringLiteral("/sys/class/drm/%1/device/gpu_busy_percent").arg(card)))
            continue;

        qreal cardPerc = -1.0;

        QDirIterator engines(QStringLiteral("/sys/class/drm/%1/engines").arg(card), QDir::Dirs | QDir::NoDotAndDotDot);
        while (engines.hasNext()) {
            QFile busy(engines.next() + QStringLiteral("/busy_percent"));
            if (!busy.open(QIODevice::ReadOnly | QIODevice::Text)) {
                continue;
            }
            bool ok = false;
            const qreal v = busy.readAll().trimmed().toDouble(&ok);
            busy.close();
            if (ok && v > cardPerc) {
                cardPerc = v;
            }
        }

        if (cardPerc < 0.0) {
            QFile cur(QStringLiteral("/sys/class/drm/%1/gt/gt0/rps_cur_freq_mhz").arg(card));
            if (!cur.open(QIODevice::ReadOnly | QIODevice::Text)) {
                continue;
            }
            QFile max(QStringLiteral("/sys/class/drm/%1/gt/gt0/rps_max_freq_mhz").arg(card));
            if (!max.open(QIODevice::ReadOnly | QIODevice::Text)) {
                cur.close();
                continue;
            }
            bool curOk = false;
            bool maxOk = false;
            const qreal curV = cur.readAll().trimmed().toDouble(&curOk);
            const qreal maxV = max.readAll().trimmed().toDouble(&maxOk);
            cur.close();
            max.close();
            if (curOk && maxOk && maxV > 0.0) {
                qreal ratio = curV / maxV;
                if (ratio < 0.0) {
                    ratio = 0.0;
                }
                if (ratio > 1.0) {
                    ratio = 1.0;
                }
                cardPerc = ratio * 100.0;
            }
        }

        if (cardPerc > maxPerc) {
            maxPerc = cardPerc;
        }
    }

    const qreal newPerc = maxPerc >= 0.0 ? maxPerc / 100.0 : 0.0;
    if (std::abs(newPerc - m_percentage) > 0.0001) {
        m_percentage = newPerc;
        Q_EMIT percentageChanged();
    }
}

void Gpu::startNvidiaUsage() {
    if (m_nvidiaQuerying) {
        return;
    }
    m_nvidiaQuerying = true;
    runProcess(QStringLiteral("nvidia-smi"),
        { QStringLiteral("--query-gpu=utilization.gpu,temperature.gpu"),
            QStringLiteral("--format=csv,noheader,nounits") },
        [this](const QByteArray& out) {
            m_nvidiaQuerying = false;

            const QList<QByteArray> parts = out.trimmed().split(',');
            if (parts.size() < 2) {
                // The card was awake when the query started, so a dead query
                // points at an unusable driver rather than a sleeping card.
                // Two in a row demote an auto-detected Nvidia to the generic
                // readers, the way the old detection chain fell back; a user
                // pinned type is respected and keeps retrying.
                if (m_userType == Auto && ++m_nvidiaFailures >= 2) {
                    m_nvidiaFailures = 0;
                    setAutoType(!m_busyFiles.isEmpty() || hasIntelGpu() ? Generic : None);
                }
                return;
            }
            m_nvidiaFailures = 0;

            bool ok1 = false;
            bool ok2 = false;
            const qreal usage = parts.at(0).trimmed().toDouble(&ok1) / 100.0;
            const qreal temp = parts.at(1).trimmed().toDouble(&ok2);
            if (ok1 && std::abs(usage - m_percentage) > 0.0001) {
                m_percentage = usage;
                Q_EMIT percentageChanged();
            }
            if (ok2 && std::abs(temp - m_temperature) > 0.05) {
                m_temperature = temp;
                Q_EMIT temperatureChanged();
            }
        });
}

void Gpu::readGpuTemperature() {
    const auto t = sensorslib::gpuPciAverageTemp();
    const qreal newTemp = t.value_or(0.0);
    if (std::abs(newTemp - m_temperature) > 0.05) {
        m_temperature = newTemp;
        Q_EMIT temperatureChanged();
    }
}

Gpu::Type Gpu::parseType(const QString& s) {
    const QString u = s.trimmed().toUpper();
    if (u.isEmpty()) {
        return Auto;
    }
    if (u == QStringLiteral("NVIDIA")) {
        return Nvidia;
    }
    if (u == QStringLiteral("GENERIC")) {
        return Generic;
    }
    return None;
}

} // namespace caelestia::services
