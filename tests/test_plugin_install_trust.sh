#!/usr/bin/env bash
# suite: fast
#
# A plugin is unsandboxed QML running inside the shell, installed from an index this
# project does not sign. What is checked here is everything the store can still decide on
# its own: which names reach a command line, and whether the plugin that lands is the one
# the user was shown.

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STORE="$REPO_ROOT/shell/services/PluginStore.qml"
PAGE="$REPO_ROOT/shell/modules/nexus/pages/PluginsPage.qml"
NODE="$(command -v node || true)"

require_node() {
    [[ -n "$NODE" ]] && return 0
    skip_test "node is not installed"
    return 1
}

# Calls one of the store's validators out of the shipped source, with the `storeRoot` it
# reads, so the thing under test is the code that ships rather than a copy of it.
run_validator() {
    local name="$1" argument="$2"

    "$NODE" -e '
        const fs = require("fs");
        const source = fs.readFileSync(process.argv[1], "utf8");

        function block(name) {
            const start = source.indexOf("function " + name + "(");
            if (start < 0)
                throw new Error("no such function: " + name);
            let depth = 0;
            let i = source.indexOf("{", start);
            for (; i < source.length; i++) {
                if (source[i] === "{")
                    depth++;
                else if (source[i] === "}" && --depth === 0) {
                    i++;
                    break;
                }
            }
            return source.slice(start, i);
        }

        const fn = eval("(" + block(process.argv[2]).replace(/^function\s+\w+/, "function") + ")");
        process.stdout.write(String(fn(process.argv[3])));
    ' "$STORE" "$name" "$argument"
}

test_a_branch_from_the_index_has_to_be_a_branch() {
    require_node || return 0

    local ref
    for ref in main dev feature/plugin-rows "release-1.2"; do
        assert_eq "true" "$(run_validator isValidRef "$ref")" "'$ref' is a ref git publishes"
    done
    for ref in "--upload-pack=/bin/sh" "-oProxyCommand=id" "main..dev" "../main" ""; do
        assert_eq "false" "$(run_validator isValidRef "$ref")" "'$ref' must not reach the git command line"
    done
}

test_a_repository_url_is_one_of_two_transports() {
    require_node || return 0

    assert_eq "true" "$(run_validator isValidGitUrl 'https://github.com/owner/plugin.git')" "an https clone is what the field is for"
    assert_eq "true" "$(run_validator isValidGitUrl 'git@github.com:owner/plugin.git')" "and the ssh form it already accepted"
    assert_eq "false" "$(run_validator isValidGitUrl 'ext::sh -c whoami')" "a transport helper is a command, not a repository"
    assert_eq "false" "$(run_validator isValidGitUrl '--upload-pack=/bin/sh https://x/y')" "and an option is not a URL"
    assert_eq "false" "$(run_validator isValidGitUrl 'https://x/y z')" "whitespace has no place in a URL here"
}

test_the_installed_plugin_is_the_one_the_row_named() {
    assert_file_contains "$STORE" 'echo "metadata.json names' \
        "a plugin whose metadata claims another id would load under an identity nobody approved"
    assert_file_contains "$STORE" 'isValidRef(branch) ? branch : "main"' \
        "the index's branch is checked before it is handed to git"
    assert_file_contains "$STORE" 'if (!isValidGitUrl(url))' \
        "and a typed URL is checked before it is cloned"
}

test_the_person_installing_is_told_what_a_plugin_is() {
    assert_file_contains "$PAGE" 'A plugin runs inside the shell, so it can do anything this session can.' \
        "the index is not signed, so the trust has to be visible where the choice is made"
}

run_tests
