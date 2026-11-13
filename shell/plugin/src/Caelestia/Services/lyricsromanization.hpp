#pragma once

#include <QString>
#include <memory>

#ifdef CAELESTIA_HAVE_ICU
#include <unicode/translit.h>
#include <unicode/unistr.h>
#endif

namespace caelestia::services::lyricsromanization {

inline bool available() {
#ifdef CAELESTIA_HAVE_ICU
    return true;
#else
    return false;
#endif
}

// Transform only the requested South Asian scripts, preserving all other text.
inline QString romanize(const QString& text) {
#ifdef CAELESTIA_HAVE_ICU
    thread_local std::unique_ptr<icu::Transliterator> devanagari;
    thread_local std::unique_ptr<icu::Transliterator> ascii;
    auto create = [](const char* id, std::unique_ptr<icu::Transliterator>& transliterator) {
        if (!transliterator) {
            UErrorCode status = U_ZERO_ERROR;
            transliterator.reset(icu::Transliterator::createInstance(id, UTRANS_FORWARD, status));
            if (U_FAILURE(status))
                transliterator.reset();
        }
        return bool(transliterator);
    };
    QString result;
    result.reserve(text.size());
    for (qsizetype i = 0; i < text.size();) {
        const auto script = text.at(i).script();
        if (script != QChar::Script_Devanagari) {
            result += text.at(i++);
            continue;
        }
        const qsizetype start = i++;
        while (i < text.size() &&
               text.at(i).script() == script)
            ++i;
        QString word = text.mid(start, i - start);
        auto& transliterator = devanagari;
        const char* id = "Devanagari-Latin";
        if (!create(id, transliterator) || !create("Latin-ASCII", ascii)) {
            result += word;
            continue;
        }
        auto converted = icu::UnicodeString::fromUTF8(word.toStdString());
        transliterator->transliterate(converted);
        std::string utf8;
        converted.toUTF8String(utf8);
        word = QString::fromStdString(utf8);
        // Suppress only a final inherent schwa, before stripping diacritics so
        // an explicitly written long vowel (ā) is not removed.
        if (word.size() > 1 && word.endsWith(QLatin1Char('a')))
            word.chop(1);
        word.replace(QStringLiteral("c"), QStringLiteral("ch"));
        word.replace(QChar(0x015b), QStringLiteral("sh"));
        word.replace(QChar(0x1e63), QStringLiteral("sh"));
        word.replace(QChar(0x1e41), QStringLiteral("n"));
        converted = icu::UnicodeString::fromUTF8(word.toStdString());
        ascii->transliterate(converted);
        utf8.clear();
        converted.toUTF8String(utf8);
        QString roman = QString::fromStdString(utf8);
        result += roman;
    }
    return result;
#else
    return text;
#endif
}

} // namespace caelestia::services::lyricsromanization
