import QtQuick
import Caelestia.Config
import "chatsessions.js" as Sessions

// The assistant's chats: one list of sessions that every change goes through,
// plus `messages`, the ListModel view of the current chat. A message is
// addressed by chat id and message id, so a reply can keep writing to its own
// message while another chat is open.
//
// Storage is behind persist(): with history saving disabled nothing is written.
QtObject {
    id: root

    property var sessions: []
    property string currentChatId: ""
    // Bumped whenever a chat is added, removed, renamed or its settings change.
    property int revision: 0

    readonly property ListModel messages: ListModel {}
    // { id, title } of every chat with messages, newest first.
    readonly property ListModel chats: ListModel {}

    signal titleNeeded(string chatId, string firstMessage)

    function load(): void {
        sessions = Sessions.parseStored(GlobalConfig.ai.ollamaHistoryJson);
        refreshChats();
    }

    function persist(): void {
        if (GlobalConfig.ai.saveChatHistory)
            GlobalConfig.ai.ollamaHistoryJson = Sessions.serialize(sessions);
    }

    // With history saving disabled, chats saved earlier are still loaded on
    // startup; deleting one must remove it from storage too, without writing
    // anything else.
    function forgetStored(ids: var): void {
        if (GlobalConfig.ai.saveChatHistory)
            return;
        const json = Sessions.withoutChats(GlobalConfig.ai.ollamaHistoryJson, ids);
        if (json !== null)
            GlobalConfig.ai.ollamaHistoryJson = json;
    }

    function session(id: string): var {
        return Sessions.find(sessions, id);
    }

    function current(): var {
        return session(currentChatId);
    }

    // A setting of the current chat (working directory, permission mode, ...).
    function currentProp(key: string): var {
        revision;
        const s = current();
        return s ? s[key] : undefined;
    }

    // Starts an empty chat and makes it current. It is not stored or listed
    // until it has a message; an empty chat left behind is dropped.
    function newChat(props: var): string {
        dropIfEmpty(currentChatId);
        const s = {
            "id": "chat_" + Date.now(),
            "title": "New Chat",
            "messages": []
        };
        for (const k in props || {})
            s[k] = props[k];
        sessions = [s].concat(sessions);
        show(s.id);
        return s.id;
    }

    // Makes a chat current; false if there is no such chat.
    function open(id: string): bool {
        if (!session(id))
            return false;
        if (id !== currentChatId)
            dropIfEmpty(currentChatId);
        show(id);
        return true;
    }

    // Adds a message to a chat and returns its id.
    function append(chatId: string, fields: var): string {
        const s = session(chatId);
        if (!s)
            return "";
        const wasEmpty = s.messages.length === 0;
        const m = Sessions.newMessage(fields);
        m.isNew = true;
        Sessions.editMessage(s, viewOf(chatId), "append", m.msgId, m);
        if (wasEmpty)
            refreshChats();
        // Until a title has been set, each message from the user asks again.
        if (m.isUser && Sessions.isDefaultTitle(s.title))
            titleNeeded(chatId, Sessions.firstUserText(s));
        return m.msgId;
    }

    function message(chatId: string, msgId: string): var {
        return Sessions.findMessage(session(chatId), msgId);
    }

    // Changes fields of a message, in whichever chat it is.
    function update(chatId: string, msgId: string, patch: var): void {
        const s = session(chatId);
        if (s)
            Sessions.editMessage(s, viewOf(chatId), "update", msgId, patch);
    }

    function remove(chatId: string, msgId: string): void {
        const s = session(chatId);
        if (s)
            Sessions.editMessage(s, viewOf(chatId), "remove", msgId, null);
    }

    // Changes settings of a chat and stores them.
    function setChatProps(chatId: string, patch: var): void {
        const s = session(chatId);
        if (!s)
            return;
        for (const k in patch)
            s[k] = patch[k];
        persist();
        revision++;
    }

    function setTitle(chatId: string, title: string): void {
        const s = session(chatId);
        if (!s || !title)
            return;
        s.title = title;
        persist();
        refreshChats();
    }

    // Removes chats; returns whether the current chat was one of them.
    function removeChats(ids: var): bool {
        if (ids.length === 0)
            return false;
        sessions = sessions.filter(s => ids.indexOf(s.id) === -1);
        persist();
        forgetStored(ids);
        refreshChats();
        return ids.indexOf(currentChatId) !== -1;
    }

    function show(id: string): void {
        currentChatId = id;
        Sessions.showMessages(session(id), messages);
        revision++;
    }

    function dropIfEmpty(id: string): void {
        const s = session(id);
        if (s && s.messages.length === 0)
            sessions = sessions.filter(x => x !== s);
    }

    // `messages` is only written through Sessions.editMessage() and
    // Sessions.showMessages(), which keep it in step with the open chat.
    function viewOf(chatId: string): ListModel {
        return chatId === currentChatId ? messages : null;
    }

    function refreshChats(): void {
        chats.clear();
        for (let i = 0; i < sessions.length; i++)
            if (sessions[i].messages.length > 0)
                chats.append({
                    "id": String(sessions[i].id),
                    "title": sessions[i].title || "New Chat"
                });
        revision++;
    }
}
