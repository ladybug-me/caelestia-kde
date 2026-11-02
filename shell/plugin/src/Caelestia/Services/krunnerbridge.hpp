// SPDX-License-Identifier: GPL-3.0-only
#pragma once

#include <qobject.h>
#include <qqmlintegration.h>
#include <qvariantlist.h>

namespace KRunner {

class RunnerManager;

}

namespace caelestia::services {

/// Bridges KDE's KRunner into the launcher, so shell search reaches whatever the
/// system's runners provide rather than only the shell's own sources: files
/// (Baloo), recent documents, places, bookmarks, web shortcuts, the dictionary,
/// unit and currency conversion, settings modules and applications.
///
/// KRunner's D-Bus service only exposes UI-control methods, so results have to
/// come from the library. On a system without libKF6Runner this object still
/// exists but reports `available == false`, which is why the QML side can import
/// it unconditionally.
class KRunnerBridge : public QObject {
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

    Q_PROPERTY(bool available READ available CONSTANT)
    Q_PROPERTY(QVariantList results READ results NOTIFY resultsChanged)

public:
    explicit KRunnerBridge(QObject* parent = nullptr);
    ~KRunnerBridge() override;

    [[nodiscard]] bool available() const;
    [[nodiscard]] QVariantList results() const;

    /// Starts a query. Runners answer in batches, so `results` is re-published as
    /// each one reports.
    Q_INVOKABLE void search(const QString& text);
    Q_INVOKABLE void clear();
    /// Activates the result with this KRunner match id, through `actionId` when it
    /// names one of that result's secondary actions and its default action otherwise.
    Q_INVOKABLE void run(const QString& id, const QString& actionId);
    /// Re-reads the runner configuration, for KDE settings the shell writes while it
    /// is running: runners cache what they read when they were created.
    Q_INVOKABLE void reloadConfiguration();

signals:
    void resultsChanged();

private:
    void publishResults();

    /// Null when built without KF6Runner: every use sits behind the guard below.
    KRunner::RunnerManager* m_manager = nullptr;
    QVariantList m_results;
};

} // namespace caelestia::services
