#!/usr/bin/env bash
# suite: fast

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WEB_SEARCH="$REPO_ROOT/shell/services/WebSearch.qml"
SEARCH="$REPO_ROOT/shell/services/Search.qml"
BRIDGE_CPP="$REPO_ROOT/shell/plugin/src/Caelestia/Services/krunnerbridge.cpp"
APP_LIST="$REPO_ROOT/shell/modules/launcher/AppList.qml"
KRUNNER_ITEM="$REPO_ROOT/shell/modules/launcher/items/KRunnerItem.qml"
APPS_PAGE="$REPO_ROOT/shell/modules/nexus/pages/AppsPage.qml"

test_engine_is_stored_the_way_kio_reads_it() {
    local service
    service="$(cat "$WEB_SEARCH")"

    # kuriikwsfilter resolves DefaultWebShortcut with findByDesktopName, so the value
    # has to be the provider's file name — not one of the aliases users can type.
    assert_contains "$service" 'kwriteconfig6", "--file", "kuriikwsfilterrc"' \
        "the choice must land in the file KIO reads"
    assert_contains "$service" '"--key", "DefaultWebShortcut"' "the key is KDE's own"
    assert_contains "$service" 'path.slice(path.lastIndexOf("/") + 1, -".desktop".length)' \
        "a provider must be identified by its desktop file name"
    assert_not_contains "$service" 'Keys=' \
        "the typed aliases are not the identifier KIO stores"
    assert_contains "$service" 'readonly property string defaultId: "duckduckgo"' \
        "the fallback has to match the one kuriikwsfilter ships"
}

test_switching_engine_notifies_the_processes_that_cache_it() {
    local service
    service="$(cat "$WEB_SEARCH")"

    # KRunner and the other KIO clients keep the provider list in memory, so writing
    # the file alone is not enough; the settings module broadcasts this signal too.
    assert_contains "$service" 'org.kde.KUriFilterPlugin.configure' \
        "the choice must be announced on the bus"
    assert_contains "$service" 'Search.reloadConfiguration()' \
        "the in-process runner manager must be told to re-read its config"
    assert_contains "$(cat "$SEARCH")" 'function reloadConfiguration(): void' \
        "the runner bridge has to be reachable through the search service"
    assert_contains "$(cat "$BRIDGE_CPP")" 'm_manager->reloadConfiguration()' \
        "the bridge must forward the reload to KRunner"
}

test_startup_read_does_not_undo_a_choice() {
    local service
    service="$(cat "$WEB_SEARCH")"

    # The singleton is created the first time the launcher asks for a url, which can
    # be seconds after the shell started; an unguarded read raced that first write.
    assert_contains "$service" 'if (!root._userPicked)' \
        "the read must not overwrite an engine the user already picked"
    assert_contains "$service" 'root._userPicked = true' "picking must be recorded before writing"
}

test_query_is_substituted_into_the_provider_template() {
    local service
    service="$(cat "$WEB_SEARCH")"

    # Provider templates escape the placeholder, so the file holds \\{@} while KIO
    # substitutes {@}; both have to collapse to the encoded query.
    assert_contains "$service" 'provider.query.replace(/\\*\{@\}/, encodeURIComponent(query))' \
        "the placeholder must be replaced with an encoded query"
    assert_contains "$service" 'if (!provider || !query)' "an unknown provider must not build a url"
}

test_launcher_only_adds_a_web_row_when_krunner_has_none() {
    local list
    list="$(cat "$APP_LIST")"

    assert_contains "$list" 'Search.results.some(match => match.runner === "krunner_webshortcuts")' \
        "KRunner's own row must win where it exists, or the two rows double up"
    assert_contains "$list" 'const url = WebSearch.searchUrl(q);' "the row must carry the url to open"
    assert_contains "$list" 'if (!url ||' "an empty url (providers still loading) must not add a row"
    assert_contains "$list" 'WebSearch.currentName' "the row must name the engine chosen in Nexus"
    assert_contains "$(cat "$BRIDGE_CPP")" 'QStringLiteral("runner"), match.runner()' \
        "results must say which runner produced them"
}

test_web_row_opens_the_browser() {
    local item
    item="$(cat "$KRUNNER_ITEM")"

    assert_contains "$item" 'Qt.openUrlExternally(root.modelData.webSearchUrl)' \
        "the launcher's own row opens a url instead of running a match"
    assert_contains "$item" 'Search.run(root.modelData.id, "")' "KRunner matches still activate by id"
}

test_nexus_offers_the_engines_as_a_setting() {
    local page
    page="$(cat "$APPS_PAGE")"

    assert_contains "$page" 'label: qsTr("Web search engine")' "Nexus must expose the setting"
    assert_contains "$page" 'value: modelData.id' "each entry must select by desktop file name"
    assert_contains "$page" 'onSelected: item => WebSearch.setProvider(item.value)' \
        "selecting an entry must change the engine"
    # PageBase is a ColumnLayout, so anything that is not an Item has to be a property.
    assert_contains "$page" 'readonly property Variants webSearchOptions: Variants {' \
        "the menu items must not be children of the page"
}

run_tests
