#!/usr/bin/env bash

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AI="$REPO_ROOT/shell/modules/sidebar/AiAssistant.qml"
AI_SRC="$(cat "$AI")"
SVC="$REPO_ROOT/shell/services/AiToolCalls.qml"
SVC_SRC="$(cat "$SVC")"

# The protocol tags are assembled from pieces everywhere in this test, never
# written as one literal: a formatter once stripped the contiguous literals
# out of the assistant and the parsers froze the shell on every AI reply.

test_the_tags_are_named_constants_that_formatters_cannot_strip() {
    assert_contains "$SVC_SRC" 'readonly property string toolCallStart: "<" + "tool_call" + ">"' \
        "the start tag must be a named constant assembled from pieces"
    assert_contains "$SVC_SRC" 'readonly property string toolCallEnd: "</" + "tool_call" + ">"' \
        "the end tag must be a named constant assembled from pieces"
    assert_not_contains "$SVC_SRC" 'var startTag' "per-function tag vars must stay gone"
    assert_not_contains "$SVC_SRC" 'var endTag' "on both scanners"
    assert_not_contains "$AI_SRC" 'toolCallStart:' \
        "the assistant must not keep its own copy of the tag constant"
}

test_both_scanners_guard_against_empty_tags() {
    assert_contains "$SVC_SRC" 'if (!root.toolCallStart || !root.toolCallEnd)' \
        "an empty tag must disable the scan instead of spinning forever"
    assert_contains "$SVC_SRC" 'while (pos <= text.length)' \
        "the parser loop must be bounded by the text length"
    assert_not_contains "$AI_SRC" 'function parseTextToolCalls' \
        "the scanners must have exactly one definition, in the service"
    assert_not_contains "$AI_SRC" 'function stripToolCalls' \
        "not a second copy inside the assistant"
}

test_the_model_prompt_shows_the_real_tags() {
    assert_contains "$SVC_SRC" 'output a ${root.toolCallStart} block containing ONLY valid JSON' \
        "the prompt must show the model the tag via the constant"
    assert_contains "$SVC_SRC" 'multiple ${root.toolCallStart} blocks in one response' \
        "the rules must name the tag for multi-call replies"
    assert_contains "$SVC_SRC" 'return `' \
        "the prompt must be a template literal so the constants interpolate"
    assert_contains "$AI_SRC" 'sysPrompt += AiToolCalls.toolsPrompt();' \
        "the assistant must build its prompt from the one owned by the service"
}

test_unknown_tools_do_not_corrupt_the_tool_counter() {
    assert_not_contains "$AI_SRC" 'Unknown tool: " + toolName);
                                        runningToolsCount--' \
        "an unknown tool must not decrement a counter that was never incremented"
    assert_contains "$AI_SRC" 'unknown tool; nothing was executed' \
        "and must still feed the model an explicit result"
}

test_the_bookkeeping_has_one_owner() {
    assert_contains "$SVC_SRC" 'property int runningToolsCount: 0' \
        "the outstanding-tool count lives in the service"
    assert_not_contains "$AI_SRC" 'property int runningToolsCount' \
        "the assistant must not mirror the counter"
    assert_contains "$AI_SRC" 'AiToolCalls.reset()' \
        "each tool batch starts from a clean slate"
    assert_contains "$SVC_SRC" 'function checkToolsFinished' \
        "the finish transition belongs to the service next to the counter"
}

test_the_scanner_terminates_and_finds_calls() {
    if ! command -v node >/dev/null 2>&1; then
        skip_test "node is not available"
        return 0
    fi

    local harness
    harness="$(mktemp "${TMPDIR:-/tmp}/caelestia-toolcalls.XXXXXX.mjs")"
    cat > "$harness" <<'EOF'
import { readFileSync } from "node:fs";

const src = readFileSync(process.argv[2], "utf8");

function extract(name) {
    const marker = "function " + name + "(";
    const start = src.indexOf(marker);
    if (start === -1) throw new Error(name + " not found");
    let depth = 0, i = src.indexOf("{", start);
    for (let j = i; j < src.length; j++) {
        if (src[j] === "{") depth++;
        else if (src[j] === "}" && --depth === 0) return src.slice(start, j + 1);
    }
    throw new Error(name + " braces unbalanced");
}

const root = { toolCallStart: "<" + "tool_call" + ">", toolCallEnd: "</" + "tool_call" + ">" };
const Logger = { log() {} };
const bundle = extract("parseTextToolCalls") + "\n" + extract("stripToolCalls");
const api = new Function("root", "Logger", bundle + "\nreturn { parse: parseTextToolCalls, strip: stripToolCalls };")(root, Logger);

const T = root.toolCallStart, E = root.toolCallEnd;
const eq = (a, b, msg) => { if (JSON.stringify(a) !== JSON.stringify(b)) { console.error("FAIL:", msg); process.exit(1); } };

// tags are stripped from display text, prose around them survives
eq(api.strip("Sure! " + T + '{"name":"open_app","args":{"app_name":"dolphin"}}' + E + " Opening."), "Sure!  Opening.", "strip removes tagged blocks");

// unclosed tag: everything from the tag onward is dropped, no hang
eq(api.strip("hello " + T + '{"name":"web_search"'), "hello", "strip truncates an unclosed tag");

// two calls parsed, prose ignored, fence inside a call tolerated
const text = T + '```json\n{"name":"a","args":{}}\n```' + E + " mid " + T + '{"name":"b","args":{"x":1}}' + E;
eq(api.parse(text).map(c => c.name), ["a", "b"], "parse finds both calls");
eq(api.parse("no tags at all"), [], "parse on plain text");
eq(api.parse(T + '{"name":"x"' + E + T + '{"name":"y","args":{}}' + E).map(c => c.name), ["y"], "bad JSON is skipped, scanning continues");
eq(api.parse(T + T + E + E), [], "nested/empty tags terminate");
eq(api.strip(T + E + T + E), "", "adjacent empty tags terminate");

console.log("tool-call scanners: all harness cases passed");
EOF
    if timeout 15 node "$harness" "$SVC"; then
        rm -f "$harness"
    else
        rm -f "$harness"
        fail "the tool-call scanner harness failed (or timed out, which is the freeze regression)"
    fi
}

run_tests
