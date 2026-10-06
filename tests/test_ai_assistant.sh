#!/usr/bin/env bash

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SIDEBAR="$REPO_ROOT/shell/modules/sidebar"

# The assistant's logic that does not need Qt lives in .pragma library files
# (shell/modules/sidebar/ai/*.js). run_js loads them as ClaudeCode, Sessions
# and Attachments, runs the given script with node's assert, and prints "ok"
# when every assertion held.
JS_PRELUDE='
const fs = require("fs");
const assert = require("assert");
function load(file) {
    const src = fs.readFileSync(process.env.AI_DIR + "/" + file, "utf8").replace(/^\.pragma library$/m, "");
    const names = [...src.matchAll(/^(?:function|var) (\w+)/gm)].map(m => m[1]);
    return new Function(src + "\nreturn {" + names.join(",") + "};")();
}
const ClaudeCode = load("claudecode.js");
const Sessions = load("chatsessions.js");
const Attachments = load("attachments.js");
// Feeds stream-json events to a fresh reply and collects the updates.
function stream(events) {
    const st = ClaudeCode.createState();
    const updates = [];
    for (const e of events)
        updates.push(...ClaudeCode.handleLine(st, JSON.stringify(e)));
    return { st, updates, of: type => updates.filter(u => u.type === type) };
}
const delta = text => ({ type: "stream_event", event: { type: "content_block_delta", delta: { type: "text_delta", text } } });
const messageStart = { type: "stream_event", event: { type: "message_start" } };
'

run_js() {
    AI_DIR="$SIDEBAR/ai" node -e "$JS_PRELUDE"$'\n'"$1"$'\n''console.log("ok");' 2>&1
}

check_js() {
    local message="$1" script="$2" out
    out="$(run_js "$script")"
    [[ "$out" == "ok" ]] || fail_with_output "$message" "$out"
}

have_node() {
    command -v node >/dev/null 2>&1
}

test_text_around_a_tool_call_stays_in_separate_paragraphs() {
    have_node || { skip_test "node is not installed"; return 0; }
    check_js "text before and after a tool call should not run together, and the card sits between them" '
const r = stream([
    { type: "system", subtype: "init", session_id: "S1" },
    messageStart,
    delta("Let me look."),
    { type: "stream_event", event: { type: "content_block_start", content_block: { type: "tool_use", id: "t1", name: "Read" } } },
    { type: "assistant", message: { content: [{ type: "text", text: "Let me look." }, { type: "tool_use", id: "t1", name: "Read", input: { file_path: "/home/u/README.md" } }] } },
    { type: "user", message: { content: [{ type: "tool_result", tool_use_id: "t1", content: "hello" }] } },
    messageStart,
    delta("Found it."),
    { type: "result", result: "Found it.", num_turns: 2 }
]);
const reply = r.of("finished")[0].reply;
assert.strictEqual(reply.text, "Let me look.\n\nFound it.");
assert.strictEqual(reply.sessionId, "S1");
assert.strictEqual(reply.tools.length, 1);
assert.strictEqual(reply.tools[0].at, "Let me look.".length);
assert.strictEqual(reply.tools[0].summary, "/home/u/README.md");
assert.strictEqual(reply.tools[0].result, "hello");
assert.strictEqual(reply.tools[0].done, true);
assert.deepStrictEqual(r.of("toolStarted").map(u => u.name), ["Read", "Read"]);
assert.strictEqual(r.of("toolsDone").length, 1);
'
}

test_a_backgrounded_subagent_is_waited_for() {
    have_node || { skip_test "node is not installed"; return 0; }
    check_js "a backgrounded subagent should finish the reply only after its notification" '
const r = stream([
    { type: "assistant", message: { content: [{ type: "tool_use", id: "a1", name: "Agent", input: { description: "Find the config" } }] } },
    { type: "user", message: { content: [{ type: "tool_result", tool_use_id: "a1", content: "started" }] }, tool_use_result: { isAsync: true } },
    { type: "result", result: "", num_turns: 1, usage: { input_tokens: 10, output_tokens: 1 }, total_cost_usd: 0.01 }
]);
assert.strictEqual(r.of("finished").length, 0, "the first result must not finish the reply");
const card = r.st.tools[0];
assert.strictEqual(card.async, true);
assert.strictEqual(card.result, "", "the placeholder answer is not the report");

const more = [
    { type: "system", subtype: "task_notification", tool_use_id: "a1", status: "completed", summary: "It is in Config.qml" },
    messageStart,
    delta("Done."),
    { type: "result", result: "Done.", num_turns: 1, usage: { input_tokens: 5, output_tokens: 2 }, total_cost_usd: 0.03 },
    { type: "result", result: "", num_turns: 1, usage: { input_tokens: 1, output_tokens: 1 }, total_cost_usd: 0.04 }
];
const updates = [];
for (const e of more)
    updates.push(...ClaudeCode.handleLine(r.st, JSON.stringify(e)));
const finished = updates.filter(u => u.type === "finished");
assert.strictEqual(finished.length, 1);
assert.strictEqual(finished[0].reply.tools[0].result, "It is in Config.qml");
assert.strictEqual(finished[0].reply.usage, "2 turns · 15 in / 3 out · $0.030");
const usage = updates.filter(u => u.type === "usage");
assert.strictEqual(usage.length, 1, "a result after the reply finished only updates the usage line");
assert.strictEqual(usage[0].text, "3 turns · 16 in / 4 out · $0.040");
'
}

test_subagent_steps_are_listed_on_its_card() {
    have_node || { skip_test "node is not installed"; return 0; }
    check_js "a subagent tool call should become a step on the subagent card" '
const r = stream([
    { type: "assistant", message: { content: [{ type: "tool_use", id: "a1", name: "Task", input: { description: "Look around" } }] } },
    { type: "assistant", parent_tool_use_id: "a1", message: { content: [{ type: "tool_use", id: "s1", name: "Grep", input: { pattern: "width" } }] } },
    { type: "user", parent_tool_use_id: "a1", message: { content: [{ type: "tool_result", tool_use_id: "s1", is_error: true }] } },
    { type: "system", subtype: "task_progress", tool_use_id: "a1", description: "Reading files" }
]);
const card = r.st.tools[0];
assert.strictEqual(r.st.acc, "", "subagent events stay out of the reply text");
assert.deepStrictEqual(card.steps.map(s => [s.name, s.summary, s.done, s.isError]), [["Grep", "width", true, true]]);
assert.strictEqual(r.of("progress").pop().text, "Reading files");
'
}

test_failures_become_a_readable_reply() {
    have_node || { skip_test "node is not installed"; return 0; }
    check_js "auth problems and crashes should explain themselves" '
const auth = stream([{ type: "result", is_error: true, result: "Invalid API key · Please run /login" }]);
assert.strictEqual(auth.of("finished")[0].reply.text, ClaudeCode.authHint);

const st = ClaudeCode.createState();
st.errAcc = "error: simulated CLI failure\n";
assert.strictEqual(ClaudeCode.handleExit(st, 1, false).text,
    "⚠️ Claude Code exited with code 1.\n\n```\nerror: simulated CLI failure\n```");
assert.strictEqual(ClaudeCode.handleExit(st, 1, false), null, "a finished reply is not finished again");

const stopped = ClaudeCode.createState();
assert.strictEqual(ClaudeCode.handleExit(stopped, 143, true).text, "", "a stopped reply gets no error text");
'
}

test_the_command_line_follows_the_chat_settings() {
    have_node || { skip_test "node is not installed"; return 0; }
    check_js "permission mode, model, effort, attachments and resume should map to CLI flags" '
const base = { bin: "claude", prompt: "hi", allowedTools: ["Bash", "Read"] };
const cmd = ClaudeCode.replyCommand(Object.assign({}, base, {
    attachments: ["/tmp/a/x.png", "/tmp/a/y.txt"],
    permissionMode: "acceptEdits", model: "claude-opus-4-5", effort: "high", sessionId: "S1"
}));
assert.deepStrictEqual(cmd, ["claude", "-p", "hi", "--add-dir", "/tmp/a",
    "--output-format", "stream-json", "--verbose", "--include-partial-messages",
    "--permission-mode", "acceptEdits", "--allowedTools", "Bash,Read",
    "--model", "claude-opus-4-5", "--effort", "high", "--resume", "S1"]);

const noBypass = ClaudeCode.replyCommand(Object.assign({}, base, { permissionMode: "bypassPermissions", bypassAllowed: false }));
assert.ok(noBypass.indexOf("--dangerously-skip-permissions") === -1, "bypass needs to be allowed in the settings");
const bypass = ClaudeCode.replyCommand(Object.assign({}, base, { permissionMode: "bypassPermissions", bypassAllowed: true }));
assert.ok(bypass.indexOf("--dangerously-skip-permissions") !== -1);

const haiku = ClaudeCode.replyCommand(Object.assign({}, base, { model: "claude-haiku-4-5", effort: "high" }));
assert.ok(haiku.indexOf("--effort") === -1, "a model without effort levels gets no --effort");
'
}

test_a_fresh_session_is_seeded_with_the_conversation() {
    have_node || { skip_test "node is not installed"; return 0; }
    check_js "the transcript should carry over earlier messages and attachments" '
const one = [Sessions.newMessage({ isUser: true, text: "hello" })];
assert.strictEqual(ClaudeCode.transcript(one), "", "a first message needs no transcript");
const msgs = [
    Sessions.newMessage({ isUser: true, text: "Remember pineapple", attachments: "/tmp/a.png" }),
    Sessions.newMessage({ text: "OK" }),
    Sessions.newMessage({ text: "", isFinished: false }),
    Sessions.newMessage({ isUser: true, text: "What word?" })
];
const t = ClaudeCode.transcript(msgs);
assert.ok(t.indexOf("User: Remember pineapple\n\nAttached files (use the Read tool to view them):\n- /tmp/a.png") !== -1);
assert.ok(t.indexOf("Assistant: OK\n\nUser: What word?") !== -1, "an unfinished reply is left out");
'
}

test_stored_chats_load_finished_and_save_without_view_state() {
    have_node || { skip_test "node is not installed"; return 0; }
    check_js "loading and saving chats should keep ids and drop what only the view needs" '
const loaded = Sessions.parseStored(JSON.stringify([
    { id: "chat_1", title: "x", claudeCodeCwd: "/tmp", messages: [
        { isUser: true, text: "a" },
        { isUser: false, text: "", isFinished: false },
        { isUser: false, text: "b", isFinished: false }
    ] },
    null,
    { title: "no id" }
]));
assert.strictEqual(loaded.length, 1);
const msgs = loaded[0].messages;
assert.strictEqual(msgs.length, 2, "an empty reply placeholder is dropped");
assert.ok(msgs.every(m => m.isFinished), "nothing is still running after a restart");
assert.ok(msgs[0].msgId && msgs[0].msgId !== msgs[1].msgId, "every message gets its own id");
assert.strictEqual(loaded[0].claudeCodeCwd, "/tmp");

msgs[1].isNew = true;
msgs[1].expandedTools = "t1";
loaded.push({ id: "chat_2", title: "New Chat", messages: [] });
loaded[0].messages.push(Sessions.newMessage({ text: "", isFinished: false }));
const saved = JSON.parse(Sessions.serialize(loaded));
assert.deepStrictEqual(saved.map(s => s.id), ["chat_1"], "a chat without messages is not stored");
assert.strictEqual(saved[0].messages.length, 2, "a reply that has nothing yet is not stored");
assert.ok(!("isNew" in saved[0].messages[1]) && !("expandedTools" in saved[0].messages[1]));
assert.strictEqual(saved[0].messages[1].msgId, msgs[1].msgId);

assert.strictEqual(Sessions.withoutChats(JSON.stringify(saved), ["chat_9"]), null);
assert.strictEqual(Sessions.withoutChats(JSON.stringify(saved), ["chat_1"]), "[]");
'
}

test_the_open_chat_view_follows_its_session() {
    have_node || { skip_test "node is not installed"; return 0; }
    check_js "every message edit should reach the session and the same row of the open chat's view" '
// Stands in for the ListModel: append copies a message into a row, set
// changes only the given roles.
function fakeView() {
    const rows = [];
    return {
        rows,
        append: m => rows.push(Object.assign({}, m)),
        set: (i, patch) => Object.assign(rows[i], patch),
        remove: i => rows.splice(i, 1),
        clear: () => rows.splice(0)
    };
}
const agree = (s, view) => assert.deepStrictEqual(view.rows, s.messages.map(m => Object.assign({}, m)));

const open = { id: "a", messages: [] };
const other = { id: "b", messages: [] };
const view = fakeView();
const ids = ["x", "y", "z"].map(t => Sessions.editMessage(open, view, "append", "", Sessions.newMessage({ text: t, isFinished: false })).msgId);
agree(open, view);

Sessions.editMessage(open, view, "update", ids[1], { text: "y2", isFinished: true });
assert.strictEqual(open.messages[1].text, "y2");
agree(open, view);

assert.strictEqual(Sessions.editMessage(open, view, "remove", ids[0]).msgId, ids[0]);
assert.deepStrictEqual(open.messages.map(m => m.text), ["y2", "z"]);
agree(open, view);

assert.strictEqual(Sessions.editMessage(open, view, "update", "missing", { text: "no" }), null);
agree(open, view);

// A chat that is not open has no view; only its session changes.
const r = Sessions.editMessage(other, null, "append", "", Sessions.newMessage({ text: "bg", isFinished: false, isNew: true }));
Sessions.editMessage(other, null, "update", r.msgId, { text: "bg done" });
assert.strictEqual(other.messages[0].text, "bg done");
agree(open, view);

// Opening it shows what it has, with nothing left to pop in.
Sessions.showMessages(other, view);
assert.strictEqual(other.messages[0].isNew, false);
agree(other, view);
'
}

test_only_the_chat_sessions_module_writes_the_open_chat_view() {
    local writers
    writers="$(grep -rlE '\b(messages|view)\.(append|insert|set|setProperty|remove|clear|move)\(' "$SIDEBAR" | sed "s|$SIDEBAR/||" | sort)"
    assert_eq "ai/chatsessions.js" "$writers" "the open chat's view should be written only by editMessage() and showMessages()"
}

test_attachment_paths() {
    have_node || { skip_test "node is not installed"; return 0; }
    check_js "dropped URLs should become local paths" '
assert.strictEqual(Attachments.localPath("file:///home/u/My%20Shot.png"), "/home/u/My Shot.png");
assert.strictEqual(Attachments.isImagePath("/a/b.JPEG"), true);
assert.strictEqual(Attachments.isImagePath("/a/b.txt"), false);
assert.strictEqual(Attachments.fileName("/a/b.txt"), "b.txt");
'
}

test_only_the_chat_store_writes_chat_history() {
    local writers
    writers="$(grep -rl 'ollamaHistoryJson *=' "$SIDEBAR" | sed "s|$SIDEBAR/||" | sort)"
    assert_eq "ai/ChatStore.qml" "$writers" "chat history should be written only by ChatStore"

    local store
    store="$(cat "$SIDEBAR/ai/ChatStore.qml")"
    assert_contains "$store" $'if (GlobalConfig.ai.saveChatHistory)\n            GlobalConfig.ai.ollamaHistoryJson = Sessions.serialize(sessions);' \
        "persist() should write only with history saving enabled"
}

test_the_chat_is_laid_out_in_full() {
    local assistant
    assistant="$(cat "$SIDEBAR/AiAssistant.qml")"
    assert_not_contains "$assistant" "cacheBuffer" "the chat should not rely on a ListView cache to keep its layout"
    assert_contains "$assistant" $'Repeater {\n                                 model: chatStore.messages\n\n                                 ChatMessage {' \
        "messages should be drawn by ChatMessage from the store's view"
    assert_not_contains "$assistant" "\"claudeCodeProc\"" "Claude Code should run through ClaudeCodeSession"
}

test_switching_chats_does_not_stop_claude_code() {
    local assistant leave
    assistant="$(cat "$SIDEBAR/AiAssistant.qml")"
    leave="$(printf '%s\n' "$assistant" | sed -n '/^    function leaveChat() {/,/^    }/p')"
    assert_ne "" "$leave" "leaveChat() should exist"
    assert_not_contains "$leave" "stopClaudeCode" "leaving a chat should leave its Claude Code reply running"
    assert_contains "$assistant" "readonly property var currentClaudeCodeProc: claudeCodeRuns[currentChatId] ?? null" \
        "the status line should follow the run of the open chat"
}

test_the_sidebar_lifetime_does_not_depend_on_assistant_dialogs() {
    local content
    content="$(cat "$SIDEBAR/Content.qml")"
    assert_not_contains "$content" "dialogOpen" "Content should not know which dialogs the assistant has"
    assert_contains "$content" "Visibilities.openDialogs > 0" "any open shell dialog should keep the sidebar loaded"
}

run_tests
