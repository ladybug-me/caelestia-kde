#include "tokensattached.hpp"

#include <qhash.h>
#include <qpointer.h>
#include <qqmlengine.h>
#include <qquickitem.h>

#include "anim.hpp"
#include "appearanceconfig.hpp"
#include "font.hpp"
#include "rootnodes.hpp"
#include "tokens.hpp"

namespace caelestia::config {

namespace {

const AppearanceConfig* resolveAppearance(ConfigRoot* config, bool complete, const char* prop, QObject* parent) {
    if (config)
        return config->appearance();
    if ((complete || !qobject_cast<QQuickItem*>(parent)) && parent)
        qCWarning(lcConfig, "Tokens.%s accessed without a screen set on %s", prop, parent->metaObject()->className());
    return ConfigSingleton::instance()->appearance();
}

// Every item that reads Tokens gets its own attached object, so the font and
// animation tokens are shared: building them per item (fonts, easing curves and
// their connections) made creating delegates slow.
AnimTokens* sharedAnimTokens() {
    static AnimTokens* const s_anim = [] {
        auto* const tokens = new AnimTokens;
        QQmlEngine::setObjectOwnership(tokens, QQmlEngine::CppOwnership);
        auto* const anim = ConfigSingleton::instance()->appearance()->anim();
        tokens->bindDurations(anim->durations());
        tokens->bindAnim(anim);
        tokens->bindCurves(TokensSingleton::instance()->appearance()->curves());
        return tokens;
    }();
    return s_anim;
}

FontTokens* sharedFontTokens(AppearanceFont* font, AppearanceTokens* appearanceTokens) {
    static QHash<std::pair<AppearanceFont*, AppearanceTokens*>, QPointer<FontTokens>> s_fonts;
    auto& tokens = s_fonts[{ font, appearanceTokens }];
    if (!tokens) {
        // Owned by the config node it reads, so it goes away with that screen's config.
        tokens = new FontTokens(font);
        tokens->bindFont(font);
        tokens->bindTokens(appearanceTokens);
    }
    return tokens;
}

} // namespace

Tokens::Tokens(QObject* parent)
    : QQuickAttachedPropertyPropagator(parent)
    , m_anim(sharedAnimTokens()) {
    bindFont();
    initialize();
}

void Tokens::classBegin() {}

void Tokens::componentComplete() {
    m_complete = true;
}

QString Tokens::screen() const {
    return m_screen;
}

void Tokens::inheritScreen(const QString& screen) {
    if (screen == m_screen)
        return;

    m_screen = screen;

    if (m_screen.isEmpty()) {
        m_config = nullptr;
        m_tokens = nullptr;
    } else {
        m_config = ConfigSingleton::instance()->forScreen(m_screen);
        m_tokens = TokensSingleton::instance()->forScreen(m_screen);
    }

    bindFont();
    propagateScreen();
    emit sourceChanged();
}

void Tokens::propagateScreen() {
    const auto children = attachedChildren();
    for (auto* const child : children) {
        auto* const tokens = qobject_cast<Tokens*>(child);
        if (tokens)
            tokens->inheritScreen(m_screen);
    }
}

void Tokens::attachedParentChange(
    QQuickAttachedPropertyPropagator* newParent, QQuickAttachedPropertyPropagator* oldParent) {
    Q_UNUSED(oldParent);
    auto* const tokens = qobject_cast<Tokens*>(newParent);
    if (tokens)
        inheritScreen(tokens->screen());
}

void Tokens::bindFont() {
    auto* appearance = m_config ? m_config->appearance() : ConfigSingleton::instance()->appearance();
    auto* tokens = m_tokens ? m_tokens->appearance() : TokensSingleton::instance()->appearance();
    m_font = sharedFontTokens(appearance->font(), tokens);
}

#define TOKENS_ATTACHED_GETTER(Type, name)                                                                             \
    const Type* Tokens::name() const {                                                                                 \
        auto* a = resolveAppearance(m_config, m_complete, #name, parent());                                            \
        return a ? a->name() : nullptr;                                                                                \
    }

TOKENS_ATTACHED_GETTER(AppearanceRounding, rounding)
TOKENS_ATTACHED_GETTER(AppearanceSpacing, spacing)
TOKENS_ATTACHED_GETTER(AppearancePadding, padding)

#undef TOKENS_ATTACHED_GETTER

const AppearanceTransparency* Tokens::transparency() const {
    return ConfigSingleton::instance()->appearance()->transparency();
}

const SizeTokens* Tokens::sizes() const {
    if (m_tokens)
        return m_tokens->sizes();
    if ((m_complete || !qobject_cast<QQuickItem*>(parent())) && parent())
        qCWarning(lcConfig, "Tokens.sizes accessed without a screen set on %s", parent()->metaObject()->className());
    return TokensSingleton::instance()->sizes();
}

const FontTokens* Tokens::font() const {
    return m_font;
}

const AnimTokens* Tokens::anim() const {
    return m_anim;
}

TokensRoot* Tokens::forScreen(const QString& screen) {
    return TokensSingleton::instance()->forScreen(screen);
}

Tokens* Tokens::qmlAttachedProperties(QObject* object) {
    return new Tokens(object);
}

} // namespace caelestia::config
