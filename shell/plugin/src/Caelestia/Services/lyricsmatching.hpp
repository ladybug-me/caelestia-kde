#pragma once

#include <QRegularExpression>
#include <QSet>
#include <QString>
#include <algorithm>
#include <cmath>

namespace caelestia::services::lyricsmatching {

// Remove presentation labels, but preserve editions such as live, remix and acoustic.
inline QString title(QString value) {
    static const QRegularExpression labels(
        QStringLiteral(
            R"(\s*[\[(]\s*(?:(?:official\s+)?(?:music\s+video|video|audio|lyric\s+video|lyrics)|official|hd|4k)\s*[\])])"),
        QRegularExpression::CaseInsensitiveOption);
    return value.remove(labels).simplified();
}

inline QString artist(QString value) {
    static const QRegularExpression topic(
        QStringLiteral(R"(\s*-\s*Topic\s*$)"), QRegularExpression::CaseInsensitiveOption);
    return value.remove(topic).simplified();
}

inline QString comparable(QString value) {
    static const QRegularExpression punctuation(QStringLiteral(R"([^\p{L}\p{N}]+)"));
    return value.normalized(QString::NormalizationForm_KC)
        .toCaseFolded()
        .replace(punctuation, QStringLiteral(" "))
        .simplified();
}

// A negative score rejects a candidate, rather than guessing a different recording.
inline double score(const QString& trackTitle, const QString& trackArtist, double duration,
    const QString& candidateTitle, const QString& candidateArtist, double candidateDuration) {
    const QString wantedTitle = comparable(title(trackTitle));
    const QString wantedArtist = comparable(artist(trackArtist));
    const QString foundArtist = comparable(artist(candidateArtist));
    if (wantedTitle.isEmpty() || wantedArtist.isEmpty() || wantedTitle != comparable(title(candidateTitle)) ||
        foundArtist.isEmpty())
        return -1;

    const auto wantedWords = wantedArtist.split(QLatin1Char(' '));
    const auto foundWords = foundArtist.split(QLatin1Char(' '));
    const QSet<QString> wanted(wantedWords.begin(), wantedWords.end());
    const QSet<QString> found(foundWords.begin(), foundWords.end());
    const double overlap = double((wanted & found).size()) / double((wanted | found).size());
    if (overlap < 0.5)
        return -1;

    if (duration <= 0 || candidateDuration <= 0 || std::isnan(duration) || std::isnan(candidateDuration))
        return wantedArtist == foundArtist ? 2.0 : -1.0;
    const double tolerance = std::clamp(duration * 0.04, 5.0, 15.0);
    const double difference = std::abs(duration - candidateDuration);
    if (difference > tolerance)
        return -1;
    return 2.0 + overlap + (1.0 - difference / tolerance);
}

} // namespace caelestia::services::lyricsmatching
