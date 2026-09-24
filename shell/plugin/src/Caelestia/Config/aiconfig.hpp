#pragma once

#include "../Settings/objectnode.hpp"
#include "common.hpp"
#include <qstring.h>

namespace caelestia::config {

using Qt::StringLiterals::operator""_s;
using settings::vmap;

class AiConfig : public settings::ObjectNode {
    CONFIG_NODE(AiConfig, settings::ObjectNode)

    CONFIG_PROPERTY(QString, ollamaUrl, u"http://localhost:11434"_s)
    CONFIG_PROPERTY(QString, ollamaModel, u"llama3"_s)

    CONFIG_PROPERTY(bool, saveChatHistory, true)
    CONFIG_PROPERTY(QString, ollamaHistoryJson, u"[]"_s)

    CONFIG_PROPERTY(bool, snapToDefaultOllama, true)
    CONFIG_PROPERTY(QString, defaultOllamaModel, u"llama3"_s)

    CONFIG_PROPERTY(QString, defaultProvider, u"ollama"_s)
    CONFIG_PROPERTY(bool, enableOllama, true)
    CONFIG_PROPERTY(bool, enableCelestialMode, true)
    CONFIG_PROPERTY(bool, showNews, true)
    CONFIG_PROPERTY(bool, showCaelestiaMode, true)
    CONFIG_PROPERTY(QString, orionModel, u"qwen3.5:9b"_s)

    CONFIG_PROPERTY(QString, activeProvider, u"ollama"_s)
    CONFIG_PROPERTY(QString, activeOllamaModel, u"llama3"_s)

    // Master switch for the whole sidebar AI assistant (independent of which
    // providers are enabled). When false, the AI tab is hidden entirely.
    CONFIG_PROPERTY(bool, enableAiAssistant, true)

    // Claude Code provider: shells out to the `claude` CLI in headless mode, using
    // the user's existing subscription login (~/.claude) — no API key required.
    CONFIG_PROPERTY(bool, enableClaudeCode, true)
    CONFIG_PROPERTY(QString, claudeCodeBin, u"claude"_s)
    CONFIG_PROPERTY(QString, defaultClaudeCodeModel, u"default"_s)
    // Effort / thinking level passed to `claude --effort` ("default" = don't pass).
    CONFIG_PROPERTY(QString, claudeCodeEffort, u"default"_s)

    // Multiple Claude accounts, each backed by its own CLAUDE_CONFIG_DIR.
    // claudeAccountsJson: JSON array of {"id","name"} (the default ~/.claude login
    // is always available as an implicit "Default" entry, id ""). activeClaudeAccount
    // holds the selected account id ("" = default). loginTerminal is the terminal
    // emulator used for the interactive `claude` login.
    CONFIG_PROPERTY(QString, claudeAccountsJson, u"[]"_s)
    CONFIG_PROPERTY(QString, activeClaudeAccount, u""_s)
    CONFIG_PROPERTY(QString, loginTerminal, u"konsole"_s)

    // Anthropic (Claude) HTTP API provider (pay-per-token, API key).
    // Disabled by default; enable to expose it in the provider selector.
    // The API key is stored here in plaintext; the ANTHROPIC_API_KEY environment
    // variable takes precedence when set (see getApiKey() in AiAssistant.qml).
    CONFIG_PROPERTY(bool, enableClaude, false)
    CONFIG_PROPERTY(QString, anthropicApiKey, u""_s)
    CONFIG_PROPERTY(QString, anthropicUrl, u"https://api.anthropic.com"_s)
    CONFIG_PROPERTY(QString, defaultClaudeModel, u""_s)

    // OpenAI-compatible providers. All three speak the same /chat/completions and
    // /models API, so they share one code path in AiAssistant.qml and differ only
    // by base URL, key and model list. Each is off by default; the matching
    // environment variable takes precedence over the key stored here.
    // The model defaults are empty on purpose: the list is fetched from the
    // provider, and the first entry is selected until the user picks one, so no
    // model name has to be maintained here as vendors ship new ones.
    // OPENAI_API_KEY
    CONFIG_PROPERTY(bool, enableOpenai, false)
    CONFIG_PROPERTY(QString, openaiApiKey, u""_s)
    CONFIG_PROPERTY(QString, openaiUrl, u"https://api.openai.com/v1"_s)
    CONFIG_PROPERTY(QString, defaultOpenaiModel, u""_s)

    // GEMINI_API_KEY — Google's OpenAI-compatible endpoint, not the native one.
    CONFIG_PROPERTY(bool, enableGemini, false)
    CONFIG_PROPERTY(QString, geminiApiKey, u""_s)
    CONFIG_PROPERTY(QString, geminiUrl, u"https://generativelanguage.googleapis.com/v1beta/openai"_s)
    CONFIG_PROPERTY(QString, defaultGeminiModel, u""_s)

    // OPENROUTER_API_KEY — aggregator, model ids look like "vendor/model".
    CONFIG_PROPERTY(bool, enableOpenrouter, false)
    CONFIG_PROPERTY(QString, openrouterApiKey, u""_s)
    CONFIG_PROPERTY(QString, openrouterUrl, u"https://openrouter.ai/api/v1"_s)
    CONFIG_PROPERTY(QString, defaultOpenrouterModel, u""_s)

    // REQUESTY_API_KEY: aggregator like OpenRouter. The model list comes from its
    // managed policies (/models/managed), short ids such as "claude-sonnet-4-5".
    // Point requestyUrl at https://router.eu.requesty.ai/v1 to keep traffic in the EU.
    CONFIG_PROPERTY(bool, enableRequesty, false)
    CONFIG_PROPERTY(QString, requestyApiKey, u""_s)
    CONFIG_PROPERTY(QString, requestyUrl, u"https://router.requesty.ai/v1"_s)
    CONFIG_PROPERTY(QString, defaultRequestyModel, u""_s)

    // opencode zen and go (https://opencode.ai/docs/zen, https://opencode.ai/docs/go).
    // Two products behind one gateway and one account, so they share a single key
    // (OPENCODE_API_KEY) and are separate providers only because the base URL and
    // model catalogue differ. Neither is plain OpenAI-compatible: each serves some
    // models over /chat/completions and others over /messages, and zen additionally
    // serves GPT over /responses and Gemini over /models/[id], which the shell does
    // not speak. See opencodeWire() and opencodeSupports() in AiAssistant.qml.
    CONFIG_PROPERTY(bool, enableOpencode, false)
    CONFIG_PROPERTY(QString, opencodeApiKey, u""_s)
    CONFIG_PROPERTY(QString, opencodeUrl, u"https://opencode.ai/zen/v1"_s)
    CONFIG_PROPERTY(QString, defaultOpencodeModel, u""_s)

    CONFIG_PROPERTY(bool, enableOpencodeGo, false)
    CONFIG_PROPERTY(QString, opencodeGoUrl, u"https://opencode.ai/zen/go/v1"_s)
    CONFIG_PROPERTY(QString, defaultOpencodeGoModel, u""_s)

};

} // namespace caelestia::config
