// SPDX-License-Identifier: GPL-3.0-only
#include "krunnerbridge.hpp"

#ifdef CAELESTIA_HAVE_KRUNNER
#include <qvariantmap.h>

#include <KRunner/Action>
#include <KRunner/QueryMatch>
#include <KRunner/RunnerManager>
#endif

namespace caelestia::services {

KRunnerBridge::KRunnerBridge(QObject* parent)
    : QObject(parent) {
#ifdef CAELESTIA_HAVE_KRUNNER
    m_manager = new KRunner::RunnerManager(this);
    connect(m_manager, &KRunner::RunnerManager::matchesChanged, this, &KRunnerBridge::publishResults);
#endif
}

KRunnerBridge::~KRunnerBridge() = default;

bool KRunnerBridge::available() const {
#ifdef CAELESTIA_HAVE_KRUNNER
    return true;
#else
    return false;
#endif
}

QVariantList KRunnerBridge::results() const {
    return m_results;
}

void KRunnerBridge::search(const QString& text) {
#ifdef CAELESTIA_HAVE_KRUNNER
    const auto trimmed = text.trimmed();
    if (trimmed.isEmpty()) {
        clear();
        return;
    }

    m_manager->launchQuery(trimmed);
#else
    Q_UNUSED(text)
#endif
}

void KRunnerBridge::clear() {
#ifdef CAELESTIA_HAVE_KRUNNER
    m_manager->reset();
#endif

    if (m_results.isEmpty())
        return;

    m_results.clear();
    emit resultsChanged();
}

void KRunnerBridge::run(const QString& id, const QString& actionId) {
#ifdef CAELESTIA_HAVE_KRUNNER
    if (id.isEmpty())
        return;

    // Runners keep answering while the list is on screen, so a row is identified by
    // its match id and resolved against the current matches at activation time.
    for (const auto& match : m_manager->matches()) {
        if (match.id() != id)
            continue;

        KRunner::Action chosen;
        for (const auto& action : match.actions()) {
            if (action.id() == actionId) {
                chosen = action;
                break;
            }
        }

        m_manager->run(match, chosen);
        return;
    }
#else
    Q_UNUSED(id)
    Q_UNUSED(actionId)
#endif
}

void KRunnerBridge::reloadConfiguration() {
#ifdef CAELESTIA_HAVE_KRUNNER
    m_manager->reloadConfiguration();
#endif
}

/// Only connected in a build with KF6Runner, so without it this stays empty rather
/// than repeating what clear() already does.
void KRunnerBridge::publishResults() {
#ifdef CAELESTIA_HAVE_KRUNNER
    const auto matches = m_manager->matches();

    QVariantList next;
    next.reserve(matches.size());

    for (const auto& match : matches) {
        if (!match.isValid())
            continue;

        QVariantList actions;
        for (const auto& action : match.actions()) {
            if (action.id().isEmpty())
                continue;
            actions.append(QVariantMap{
                { QStringLiteral("id"), action.id() },
                { QStringLiteral("text"), action.text() },
            });
        }

        next.append(QVariantMap{
            { QStringLiteral("id"), match.id() },
            { QStringLiteral("runner"), match.runner() ? match.runner()->id() : QString() },
            { QStringLiteral("text"), match.text() },
            { QStringLiteral("subtext"), match.subtext() },
            { QStringLiteral("icon"), match.iconName() },
            { QStringLiteral("relevance"), match.relevance() },
            { QStringLiteral("actions"), actions },
        });
    }

    m_results = next;
    emit resultsChanged();
#endif
}

} // namespace caelestia::services
