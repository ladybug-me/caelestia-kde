#include "audiodevicebackend.hpp"

#include <PulseAudioQt/Card>
#include <PulseAudioQt/Context>
#include <PulseAudioQt/Device>
#include <PulseAudioQt/Models>
#include <PulseAudioQt/Port>
#include <PulseAudioQt/Profile>
#include <PulseAudioQt/Sink>
#include <PulseAudioQt/Source>

using namespace PulseAudioQt;

AudioDeviceFilterModel::AudioDeviceFilterModel(QObject* parent)
    : QSortFilterProxyModel(parent) {}

static bool isDeviceInactive(PulseAudioQt::Device* device) {
    if (!device) {
        return false;
    }
    const auto ports = device->ports();
    if (ports.isEmpty()) {
        return false;
    }

    auto activeIdx = device->activePortIndex();
    if (activeIdx < static_cast<quint32>(ports.size())) {
        auto activePort = ports.at(static_cast<qsizetype>(activeIdx));
        if (activePort && activePort->availability() == PulseAudioQt::Port::Unavailable) {
            return true;
        }
        return false;
    }

    for (auto port : ports) {
        if (port && port->availability() != PulseAudioQt::Port::Unavailable) {
            return false;
        }
    }
    return true;
}

bool AudioDeviceFilterModel::showInactiveDevices() const {
    return m_showInactiveDevices;
}

void AudioDeviceFilterModel::setShowInactiveDevices(bool show) {
    if (m_showInactiveDevices != show) {
        m_showInactiveDevices = show;
        Q_EMIT showInactiveDevicesChanged();
        invalidate();
    }
}

bool AudioDeviceFilterModel::filterAcceptsRow(int source_row, const QModelIndex& source_parent) const {
    if (m_showInactiveDevices) {
        return true;
    }

    QModelIndex index = sourceModel()->index(source_row, 0, source_parent);
    QVariant data = sourceModel()->data(index, AbstractModel::PulseObjectRole);
    if (Device* device = qobject_cast<Device*>(data.value<QObject*>())) {
        if (isDeviceInactive(device)) {
            return false;
        }
    }
    return true;
}

static QString getCardFriendlyName(PulseAudioQt::Card* card) {
    if (!card) {
        return QString();
    }

    for (auto sink : card->sinks()) {
        if (!isDeviceInactive(sink)) {
            const auto props = sink->pulseProperties();
            QString nick = props.value(QStringLiteral("node.nick")).toString();
            if (!nick.isEmpty()) {
                return nick;
            }
            QString profDesc = props.value(QStringLiteral("device.profile.description")).toString();
            if (!profDesc.isEmpty()) {
                return profDesc;
            }
            auto activePortIdx = sink->activePortIndex();
            const auto ports = sink->ports();
            if (activePortIdx < static_cast<quint32>(ports.size())) {
                auto port = ports.at(static_cast<qsizetype>(activePortIdx));
                if (port && !port->description().isEmpty()) {
                    return port->description();
                }
            }
        }
    }

    for (auto port : card->ports()) {
        if (port && port->availability() != PulseAudioQt::Port::Unavailable) {
            if (!port->name().startsWith(QLatin1String("Mic"), Qt::CaseInsensitive) &&
                !port->name().startsWith(QLatin1String("[In]"), Qt::CaseInsensitive)) {
                if (!port->description().isEmpty()) {
                    return port->description();
                }
            }
        }
    }

    for (auto source : card->sources()) {
        if (!isDeviceInactive(source)) {
            const auto props = source->pulseProperties();
            QString nick = props.value(QStringLiteral("node.nick")).toString();
            if (!nick.isEmpty()) {
                return nick;
            }
            QString profDesc = props.value(QStringLiteral("device.profile.description")).toString();
            if (!profDesc.isEmpty()) {
                return profDesc;
            }
            auto activePortIdx = source->activePortIndex();
            const auto ports = source->ports();
            if (activePortIdx < static_cast<quint32>(ports.size())) {
                auto port = ports.at(static_cast<qsizetype>(activePortIdx));
                if (port && !port->description().isEmpty()) {
                    return port->description();
                }
            }
        }
    }

    // 4. Fallback to card's device.description
    const auto cardProps = card->properties();
    if (cardProps.contains(QStringLiteral("device.description"))) {
        QString desc = cardProps.value(QStringLiteral("device.description")).toString();
        if (!desc.isEmpty()) {
            return desc;
        }
    }
    if (cardProps.contains(QStringLiteral("alsa.card_name"))) {
        QString name = cardProps.value(QStringLiteral("alsa.card_name")).toString();
        if (!name.isEmpty()) {
            return name;
        }
    }

    return card->name();
}

CardFilterModel::CardFilterModel(QObject* parent)
    : QSortFilterProxyModel(parent) {}

QHash<int, QByteArray> CardFilterModel::roleNames() const {
    QHash<int, QByteArray> roles = QSortFilterProxyModel::roleNames();
    roles[DescriptionRole] = "description";
    return roles;
}

QVariant CardFilterModel::data(const QModelIndex& index, int role) const {
    if (role == DescriptionRole || role == Qt::DisplayRole) {
        QModelIndex sourceIndex = mapToSource(index);
        QVariant poVar = sourceModel()->data(sourceIndex, PulseAudioQt::AbstractModel::PulseObjectRole);
        if (auto card = qobject_cast<PulseAudioQt::Card*>(poVar.value<QObject*>())) {
            return getCardFriendlyName(card);
        }
    }
    return QSortFilterProxyModel::data(index, role);
}

AudioBackend::AudioBackend(QObject* parent)
    : QObject(parent) {
    Context* context = Context::instance();

    m_sinksFilter = new AudioDeviceFilterModel(this);
    m_sinksFilter->setSourceModel(new SinkModel(this));

    m_sourcesFilter = new AudioDeviceFilterModel(this);
    m_sourcesFilter->setSourceModel(new SourceModel(this));

    m_cardModel = new CardFilterModel(this);
    m_cardModel->setSourceModel(new CardModel(this));

    connect(context, &Context::sinkAdded, this, [this](Sink* sink) {
        registerSink(sink);
        m_sinksFilter->invalidate();
        Q_EMIT devicesChanged();
    });
    connect(context, &Context::sinkRemoved, this, [this](Sink*) {
        m_sinksFilter->invalidate();
        Q_EMIT devicesChanged();
    });

    connect(context, &Context::sourceAdded, this, [this](Source* source) {
        registerSource(source);
        m_sourcesFilter->invalidate();
        Q_EMIT devicesChanged();
    });
    connect(context, &Context::sourceRemoved, this, [this](Source*) {
        m_sourcesFilter->invalidate();
        Q_EMIT devicesChanged();
    });

    connect(context, &Context::cardAdded, this, [this](Card* card) {
        registerCard(card);
        m_cardModel->invalidate();
        Q_EMIT devicesChanged();
    });
    connect(context, &Context::cardRemoved, this, [this](Card*) {
        m_cardModel->invalidate();
        Q_EMIT devicesChanged();
    });

    connect(context, &Context::stateChanged, this, [this]() {
        m_sinksFilter->invalidate();
        m_sourcesFilter->invalidate();
        m_cardModel->invalidate();
        Q_EMIT devicesChanged();
    });

    for (auto sink : context->sinks()) {
        registerSink(sink);
    }
    for (auto source : context->sources()) {
        registerSource(source);
    }
    for (auto card : context->cards()) {
        registerCard(card);
    }
}

AudioBackend::~AudioBackend() {}

void AudioBackend::onSinkChanged() {
    m_sinksFilter->invalidate();
    Q_EMIT devicesChanged();
}

void AudioBackend::onSourceChanged() {
    m_sourcesFilter->invalidate();
    Q_EMIT devicesChanged();
}

void AudioBackend::onCardChanged() {
    m_sinksFilter->invalidate();
    m_sourcesFilter->invalidate();
    m_cardModel->invalidate();
    Q_EMIT devicesChanged();
}

void AudioBackend::registerSink(QObject* sinkObj) {
    if (auto sink = qobject_cast<Sink*>(sinkObj)) {
        connect(sink, &Device::portsChanged, this, &AudioBackend::onSinkChanged, Qt::UniqueConnection);
        connect(sink, &Device::activePortIndexChanged, this, &AudioBackend::onSinkChanged, Qt::UniqueConnection);
        connect(sink, &Device::stateChanged, this, &AudioBackend::onSinkChanged, Qt::UniqueConnection);
    }
}

void AudioBackend::registerSource(QObject* sourceObj) {
    if (auto source = qobject_cast<Source*>(sourceObj)) {
        connect(source, &Device::portsChanged, this, &AudioBackend::onSourceChanged, Qt::UniqueConnection);
        connect(source, &Device::activePortIndexChanged, this, &AudioBackend::onSourceChanged, Qt::UniqueConnection);
        connect(source, &Device::stateChanged, this, &AudioBackend::onSourceChanged, Qt::UniqueConnection);
    }
}

void AudioBackend::registerCard(QObject* cardObj) {
    if (auto card = qobject_cast<Card*>(cardObj)) {
        connect(card, &Card::activeProfileIndexChanged, this, &AudioBackend::onCardChanged, Qt::UniqueConnection);
        connect(card, &Card::profilesChanged, this, &AudioBackend::onCardChanged, Qt::UniqueConnection);
        connect(card, &Card::portsChanged, this, &AudioBackend::onCardChanged, Qt::UniqueConnection);
    }
}

bool AudioBackend::showInactiveDevices() const {
    return m_showInactiveDevices;
}

void AudioBackend::setShowInactiveDevices(bool show) {
    if (m_showInactiveDevices != show) {
        m_showInactiveDevices = show;
        m_sinksFilter->setShowInactiveDevices(show);
        m_sourcesFilter->setShowInactiveDevices(show);
        Q_EMIT showInactiveDevicesChanged();
        Q_EMIT devicesChanged();
    }
}

QAbstractItemModel* AudioBackend::sinks() const {
    return m_sinksFilter;
}

QAbstractItemModel* AudioBackend::sources() const {
    return m_sourcesFilter;
}

QAbstractItemModel* AudioBackend::cards() const {
    return m_cardModel;
}

bool AudioBackend::isSinkInactive(const QString& name) {
    bool found = false;
    for (auto sink : Context::instance()->sinks()) {
        if (sink->name() == name || sink->description() == name) {
            found = true;
            if (!isDeviceInactive(sink)) {
                return false;
            }
        }
    }
    return found;
}

bool AudioBackend::isSourceInactive(const QString& name) {
    bool found = false;
    for (auto source : Context::instance()->sources()) {
        if (source->name() == name || source->description() == name) {
            found = true;
            if (!isDeviceInactive(source)) {
                return false;
            }
        }
    }
    return found;
}

QString AudioBackend::cardDescription(QObject* cardObj) const {
    if (auto card = qobject_cast<PulseAudioQt::Card*>(cardObj)) {
        return getCardFriendlyName(card);
    }
    return QString();
}
