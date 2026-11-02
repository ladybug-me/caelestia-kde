// SPDX-License-Identifier: GPL-3.0-only
#include "pipewirestreamwatcher.hpp"

#include <pipewire/pipewire.h>
#include <spa/utils/result.h>

#include <QElapsedTimer>
#include <QLoggingCategory>
#include <QMetaObject>
#include <QMutex>
#include <QMutexLocker>
#include <QTimer>
#include <map>
#include <optional>

Q_LOGGING_CATEGORY(lcPipewireStreamWatcher, "caelestia.services.pipewirestreamwatcher", QtInfoMsg)

namespace caelestia::services {

using Qt::StringLiterals::operator""_s;

namespace {

constexpr qint64 kSharingGraceMs = 5000;

[[nodiscard]] bool isVideoNodeClass(const char* mediaClass) {
    return mediaClass && (strcmp(mediaClass, "Stream/Input/Video") == 0 || strcmp(mediaClass, "Video/Source") == 0);
}

[[nodiscard]] bool isConfirmedShare(qint64 sharingSinceMs, qint64 nowMs) {
    return sharingSinceMs != 0 && nowMs - sharingSinceMs >= kSharingGraceMs;
}

} // namespace

class PipewireStreamWatcherPrivate;

struct TrackedNode {
    QString mediaClass;
    QString nodeName;
    QString mediaName;
    QString mediaRole;

    qint64 sharingSinceMs = 0;

    pw_node* proxy = nullptr;
    spa_hook listener{};
    PipewireStreamWatcherPrivate* owner = nullptr;

    [[nodiscard]] bool looksLikeShare() const;
};

bool TrackedNode::looksLikeShare() const {
    if (mediaClass == u"Stream/Input/Video"_s) {
        if (mediaName.isEmpty()) {
            return false;
        }
        // Exclude internal quickshell / caelestia-shell previews and KDE screencast helpers
        if (nodeName == u"quickshell"_s || nodeName == u"caelestia-shell"_s) {
            return false;
        }
        return !mediaName.startsWith(u"plasma-screencast-"_s);
    }

    if (mediaClass == u"Video/Source"_s) {
        // Exclude hardware webcams and V4L2 devices
        return mediaRole != u"Camera"_s && !nodeName.startsWith(u"v4l2_input"_s);
    }

    return false;
}

class PipewireStreamWatcherPrivate {
public:
    explicit PipewireStreamWatcherPrivate(PipewireStreamWatcher* parent)
        : q(parent) {}

    PipewireStreamWatcher* q = nullptr;
    pw_thread_loop* threadLoop = nullptr;
    pw_context* context = nullptr;
    pw_core* core = nullptr;
    pw_registry* registry = nullptr;
    spa_hook registryListener{};
    spa_hook coreListener{};
    QTimer* reconnectTimer = nullptr;

    mutable QMutex mutex;
    std::map<uint32_t, TrackedNode> trackedNodes;
    QElapsedTimer clock;
    QTimer* confirmTimer = nullptr;

    bool m_streaming = false;
    int m_streamCount = 0;
    QStringList m_activeStreams;

    void init();
    void cleanup();
    void tryConnect();
    void scheduleReconnect();
    void notifyStateChangedFromThread();
    void updateState(bool streaming, int count, const QStringList& streams);

    void bindNode(uint32_t id, uint32_t version, const spa_dict* props);
    bool releaseNode(uint32_t id);
    void releaseNodes();
    void applyNodeProps(uint32_t id, const spa_dict* props);

    static void onNodeInfo(void* data, const pw_node_info* info);

    static void onGlobal(
        void* data, uint32_t id, uint32_t permissions, const char* type, uint32_t version, const spa_dict* props);
    static void onGlobalRemove(void* data, uint32_t id);
    static void onCoreError(void* data, uint32_t id, int seq, int res, const char* message);
};

void PipewireStreamWatcherPrivate::init() {
    pw_init(nullptr, nullptr);

    reconnectTimer = new QTimer(q);
    reconnectTimer->setInterval(3000);
    reconnectTimer->setSingleShot(true);
    QObject::connect(reconnectTimer, &QTimer::timeout, q, [this]() {
        tryConnect();
    });

    confirmTimer = new QTimer(q);
    confirmTimer->setSingleShot(true);
    QObject::connect(confirmTimer, &QTimer::timeout, q, [this]() {
        notifyStateChangedFromThread();
    });

    clock.start();
    tryConnect();
}

void PipewireStreamWatcherPrivate::cleanup() {
    if (reconnectTimer) {
        reconnectTimer->stop();
    }
    if (confirmTimer) {
        confirmTimer->stop();
    }

    if (threadLoop) {
        pw_thread_loop_stop(threadLoop);
        pw_thread_loop_lock(threadLoop);
    }

    releaseNodes();

    if (registry) {
        spa_hook_remove(&registryListener);
        pw_proxy_destroy(reinterpret_cast<pw_proxy*>(registry));
        registry = nullptr;
    }

    if (core) {
        spa_hook_remove(&coreListener);
        pw_core_disconnect(core);
        core = nullptr;
    }

    if (context) {
        pw_context_destroy(context);
        context = nullptr;
    }

    if (threadLoop) {
        pw_thread_loop_unlock(threadLoop);
        pw_thread_loop_destroy(threadLoop);
        threadLoop = nullptr;
    }

    pw_deinit();
}

void PipewireStreamWatcherPrivate::tryConnect() {
    if (threadLoop) {
        cleanup();
        pw_init(nullptr, nullptr);
    }

    threadLoop = pw_thread_loop_new("caelestia-stream-watcher", nullptr);
    if (!threadLoop) {
        qCWarning(lcPipewireStreamWatcher) << "Failed to create PipeWire thread loop";
        scheduleReconnect();
        return;
    }

    if (pw_thread_loop_start(threadLoop) < 0) {
        qCWarning(lcPipewireStreamWatcher) << "Failed to start PipeWire thread loop";
        pw_thread_loop_destroy(threadLoop);
        threadLoop = nullptr;
        scheduleReconnect();
        return;
    }

    pw_thread_loop_lock(threadLoop);

    context = pw_context_new(pw_thread_loop_get_loop(threadLoop), nullptr, 0);
    if (!context) {
        qCWarning(lcPipewireStreamWatcher) << "Failed to create PipeWire context";
        pw_thread_loop_unlock(threadLoop);
        scheduleReconnect();
        return;
    }

    core = pw_context_connect(context, nullptr, 0);
    if (!core) {
        qCWarning(lcPipewireStreamWatcher) << "Failed to connect to PipeWire core";
        pw_context_destroy(context);
        context = nullptr;
        pw_thread_loop_unlock(threadLoop);
        scheduleReconnect();
        return;
    }

    static const pw_core_events coreEvents = {
        .version = PW_VERSION_CORE_EVENTS,
        .error = onCoreError,
    };
    spa_zero(coreListener);
    pw_core_add_listener(core, &coreListener, &coreEvents, this);

    registry = pw_core_get_registry(core, PW_VERSION_REGISTRY, 0);
    if (!registry) {
        qCWarning(lcPipewireStreamWatcher) << "Failed to get PipeWire registry";
        pw_thread_loop_unlock(threadLoop);
        scheduleReconnect();
        return;
    }

    static const pw_registry_events registryEvents = {
        .version = PW_VERSION_REGISTRY_EVENTS,
        .global = onGlobal,
        .global_remove = onGlobalRemove,
    };
    spa_zero(registryListener);
    pw_registry_add_listener(registry, &registryListener, &registryEvents, this);

    pw_thread_loop_unlock(threadLoop);
    qCInfo(lcPipewireStreamWatcher) << "Connected to PipeWire registry";
}

void PipewireStreamWatcherPrivate::scheduleReconnect() {
    if (reconnectTimer && !reconnectTimer->isActive()) {
        reconnectTimer->start();
    }
}

void PipewireStreamWatcherPrivate::notifyStateChangedFromThread() {
    bool streaming = false;
    int count = 0;
    QStringList streams;
    std::optional<qint64> confirmAtMs;

    {
        QMutexLocker locker(&mutex);
        const qint64 nowMs = clock.elapsed();
        for (const auto& entry : trackedNodes) {
            const TrackedNode& node = entry.second;
            if (node.sharingSinceMs == 0) {
                continue;
            }
            if (!isConfirmedShare(node.sharingSinceMs, nowMs)) {
                const qint64 dueMs = node.sharingSinceMs + kSharingGraceMs;
                if (!confirmAtMs || dueMs < *confirmAtMs) {
                    confirmAtMs = dueMs;
                }
                continue;
            }
            ++count;
            streams.append(!node.mediaName.isEmpty() ? node.mediaName : node.nodeName);
        }
        streaming = (count > 0);
    }

    QMetaObject::invokeMethod(
        q,
        [this, streaming, count, streams, confirmAtMs]() {
            if (confirmAtMs) {
                const qint64 remainingMs = *confirmAtMs - clock.elapsed();
                confirmTimer->start(static_cast<int>(remainingMs > 0 ? remainingMs : 1));
            } else {
                confirmTimer->stop();
            }
            updateState(streaming, count, streams);
        },
        Qt::QueuedConnection);
}

void PipewireStreamWatcherPrivate::updateState(bool streaming, int count, const QStringList& streams) {
    const bool streamingChanged = (m_streaming != streaming);
    const bool countChanged = (m_streamCount != count);
    const bool streamsChanged = (m_activeStreams != streams);

    m_streaming = streaming;
    m_streamCount = count;
    m_activeStreams = streams;

    if (streamingChanged) {
        qCInfo(lcPipewireStreamWatcher) << "Streaming state changed to" << m_streaming
                                        << "(active count:" << m_streamCount << ")";
        emit q->streamingChanged(m_streaming);
    }
    if (countChanged) {
        emit q->streamCountChanged(m_streamCount);
    }
    if (streamsChanged) {
        emit q->activeStreamsChanged();
    }
}

void PipewireStreamWatcherPrivate::bindNode(uint32_t id, uint32_t version, const spa_dict* props) {
    if (!registry) {
        return;
    }

    releaseNode(id);

    const uint32_t bindVersion = version < PW_VERSION_NODE ? version : PW_VERSION_NODE;
    auto* proxy = static_cast<pw_node*>(pw_registry_bind(registry, id, PW_TYPE_INTERFACE_Node, bindVersion, 0));
    if (!proxy) {
        qCWarning(lcPipewireStreamWatcher) << "Failed to bind node" << id;
        return;
    }

    TrackedNode* node = nullptr;
    {
        QMutexLocker locker(&mutex);
        TrackedNode& tracked = trackedNodes[id];
        tracked.proxy = proxy;
        tracked.owner = this;
        node = &tracked;
    }

    static const pw_node_events nodeEvents = {
        .version = PW_VERSION_NODE_EVENTS,
        .info = onNodeInfo,
    };
    pw_node_add_listener(proxy, &node->listener, &nodeEvents, node);

    applyNodeProps(id, props);
}

bool PipewireStreamWatcherPrivate::releaseNode(uint32_t id) {
    QMutexLocker locker(&mutex);

    auto it = trackedNodes.find(id);
    if (it == trackedNodes.end()) {
        return false;
    }

    TrackedNode& node = it->second;
    spa_hook_remove(&node.listener);
    if (node.proxy) {
        pw_proxy_destroy(reinterpret_cast<pw_proxy*>(node.proxy));
    }

    const bool wasSharing = node.sharingSinceMs != 0;
    trackedNodes.erase(it);
    return wasSharing;
}

void PipewireStreamWatcherPrivate::releaseNodes() {
    QMutexLocker locker(&mutex);

    for (auto& entry : trackedNodes) {
        TrackedNode& node = entry.second;
        spa_hook_remove(&node.listener);
        if (node.proxy) {
            pw_proxy_destroy(reinterpret_cast<pw_proxy*>(node.proxy));
        }
    }
    trackedNodes.clear();
}

void PipewireStreamWatcherPrivate::applyNodeProps(uint32_t id, const spa_dict* props) {
    if (!props) {
        return;
    }

    bool wasSharing = false;
    bool sharing = false;
    QString label;
    {
        QMutexLocker locker(&mutex);
        auto it = trackedNodes.find(id);
        if (it == trackedNodes.end()) {
            return;
        }

        TrackedNode& node = it->second;
        wasSharing = node.sharingSinceMs != 0;

        if (const char* value = spa_dict_lookup(props, PW_KEY_MEDIA_CLASS)) {
            node.mediaClass = QString::fromUtf8(value);
        }
        if (const char* value = spa_dict_lookup(props, PW_KEY_NODE_NAME)) {
            node.nodeName = QString::fromUtf8(value);
        }
        if (const char* value = spa_dict_lookup(props, PW_KEY_MEDIA_NAME)) {
            node.mediaName = QString::fromUtf8(value);
        }
        if (const char* value = spa_dict_lookup(props, PW_KEY_MEDIA_ROLE)) {
            node.mediaRole = QString::fromUtf8(value);
        }

        sharing = node.looksLikeShare();
        if (sharing != wasSharing) {
            node.sharingSinceMs = sharing ? clock.elapsed() : 0;
        }
        label = !node.mediaName.isEmpty() ? node.mediaName : node.nodeName;
    }

    if (sharing == wasSharing) {
        return;
    }

    if (sharing) {
        qCInfo(lcPipewireStreamWatcher) << "Detected video streaming node:" << label << "id:" << id;
    } else {
        qCInfo(lcPipewireStreamWatcher) << "Video streaming node no longer streaming, id:" << id;
    }

    notifyStateChangedFromThread();
}

void PipewireStreamWatcherPrivate::onNodeInfo(void* data, const pw_node_info* info) {
    auto* node = static_cast<TrackedNode*>(data);
    if (!node || !node->owner || !info) {
        return;
    }

    node->owner->applyNodeProps(info->id, info->props);
}

void PipewireStreamWatcherPrivate::onGlobal(
    void* data, uint32_t id, uint32_t /*permissions*/, const char* type, uint32_t version, const spa_dict* props) {
    if (!type || strcmp(type, PW_TYPE_INTERFACE_Node) != 0 || !props) {
        return;
    }

    if (!isVideoNodeClass(spa_dict_lookup(props, PW_KEY_MEDIA_CLASS))) {
        return;
    }

    static_cast<PipewireStreamWatcherPrivate*>(data)->bindNode(id, version, props);
}

void PipewireStreamWatcherPrivate::onGlobalRemove(void* data, uint32_t id) {
    auto* d = static_cast<PipewireStreamWatcherPrivate*>(data);

    if (d->releaseNode(id)) {
        qCInfo(lcPipewireStreamWatcher) << "Video streaming node removed, id:" << id;
    }

    d->notifyStateChangedFromThread();
}

void PipewireStreamWatcherPrivate::onCoreError(void* data, uint32_t id, int seq, int res, const char* message) {
    auto* d = static_cast<PipewireStreamWatcherPrivate*>(data);
    qCWarning(lcPipewireStreamWatcher) << "PipeWire core error:" << message << "id:" << id << "seq:" << seq
                                       << "res:" << res;
    if (id == PW_ID_CORE) {
        QMetaObject::invokeMethod(
            d->q,
            [d]() {
                d->scheduleReconnect();
            },
            Qt::QueuedConnection);
    }
}

PipewireStreamWatcher::PipewireStreamWatcher(QObject* parent)
    : QObject(parent)
    , d(std::make_unique<PipewireStreamWatcherPrivate>(this)) {
    d->init();
}

PipewireStreamWatcher::~PipewireStreamWatcher() {
    d->cleanup();
}

bool PipewireStreamWatcher::isStreaming() const {
    return d->m_streaming;
}

int PipewireStreamWatcher::streamCount() const {
    return d->m_streamCount;
}

QStringList PipewireStreamWatcher::activeStreams() const {
    return d->m_activeStreams;
}

void PipewireStreamWatcher::rescan() {
    d->notifyStateChangedFromThread();
}

} // namespace caelestia::services
