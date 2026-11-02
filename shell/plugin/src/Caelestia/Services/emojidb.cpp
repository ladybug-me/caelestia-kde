// SPDX-License-Identifier: GPL-3.0-only
#include "emojidb.hpp"

#include <qdatastream.h>
#include <qdir.h>
#include <qfile.h>
#include <qjsondocument.h>
#include <qjsonobject.h>
#include <qlocale.h>
#include <qloggingcategory.h>
#include <qset.h>
#include <qstandardpaths.h>
#include <qtextstream.h>

#include <algorithm>

#include "../Config/common.hpp"

Q_LOGGING_CATEGORY(lcEmojiDb, "caelestia.services.emojidb", QtInfoMsg)

namespace caelestia::services {

EmojiDb::EmojiDb(QObject* parent)
    : QObject(parent) {
    m_freqPath = caelestia::config::configFile(QStringLiteral("emoji-frequencies.json"));

    loadEmojis();
    loadFrequencies();
}

bool EmojiDb::loaded() const {
    return m_loaded;
}

int EmojiDb::count() const {
    return static_cast<int>(m_emojis.size());
}

bool EmojiDb::loadKdeDict(const QString& path, QHash<QString, int>& charMap) {
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly))
        return false;

    auto buffer = file.readAll();
    buffer = qUncompress(buffer);
    if (buffer.isEmpty())
        return false;

    QDataStream stream(&buffer, QIODevice::ReadOnly);
    stream.setVersion(QDataStream::Qt_5_15);
    stream.setByteOrder(QDataStream::LittleEndian);

    quint32 count = 0;
    stream >> count;

    const qsizetype initialSize = m_emojis.size();
    m_emojis.reserve(initialSize + static_cast<qsizetype>(count));

    for (quint32 i = 0; i < count; ++i) {
        QByteArray contentBuf;
        QByteArray descBuf;
        qint32 category = 0;
        QList<QByteArray> annotationBuffers;

        stream >> contentBuf >> descBuf >> category >> annotationBuffers;

        if (contentBuf.isEmpty())
            continue;

        EmojiEntry entry;
        entry.ch = QString::fromUtf8(contentBuf);
        entry.name = QString::fromUtf8(descBuf);

        QStringList tags;
        tags.reserve(annotationBuffers.size());
        for (const auto& a : annotationBuffers) {
            tags.append(QString::fromUtf8(a));
        }

        entry.nameLower = (entry.name + u' ' + tags.join(u' ')).toLower();

        auto it = charMap.find(entry.ch);
        if (it != charMap.end()) {
            m_emojis[*it] = std::move(entry);
        } else {
            charMap.insert(entry.ch, static_cast<int>(m_emojis.size()));
            m_emojis.append(std::move(entry));
        }
    }

    return m_emojis.size() > initialSize || count > 0;
}

bool EmojiDb::loadTextFile(const QString& path, QHash<QString, int>& charMap) {
    QFile f(path);
    if (!f.open(QIODevice::ReadOnly | QIODevice::Text))
        return false;

    QTextStream in(&f);
    const qsizetype initialSize = m_emojis.size();

    while (!in.atEnd()) {
        const auto line = in.readLine();
        if (line.isEmpty())
            continue;

        const auto spaceIdx = line.indexOf(u' ');
        if (spaceIdx < 0)
            continue;

        const QString ch = line.left(spaceIdx);
        if (charMap.contains(ch))
            continue;

        EmojiEntry entry;
        entry.ch = ch;
        entry.name = line.mid(spaceIdx + 1).trimmed();
        entry.nameLower = entry.name.toLower();
        charMap.insert(ch, static_cast<int>(m_emojis.size()));
        m_emojis.append(std::move(entry));
    }

    return m_emojis.size() > initialSize;
}

void EmojiDb::loadEmojis() {
    m_emojis.clear();
    QHash<QString, int> charMap;

    const QString kdeDir = QStringLiteral("/usr/share/plasma/emoji");
    if (QDir(kdeDir).exists()) {
        const QString localeName = QLocale::system().name();
        const QString lang = localeName.section(u'_', 0, 0);

        QStringList kdeLoadOrder = {
            kdeDir + QStringLiteral("/en.dict"),
        };

        if (lang != QStringLiteral("en")) {
            const QString langDict = kdeDir + u'/' + lang + QStringLiteral(".dict");
            if (!kdeLoadOrder.contains(langDict))
                kdeLoadOrder.append(langDict);
        }

        if (localeName != lang && localeName != QStringLiteral("en")) {
            const QString localeDict = kdeDir + u'/' + localeName + QStringLiteral(".dict");
            if (!kdeLoadOrder.contains(localeDict))
                kdeLoadOrder.append(localeDict);
        }

        for (const auto& path : kdeLoadOrder) {
            if (QFile::exists(path) && loadKdeDict(path, charMap)) {
                m_loaded = true;
                qCInfo(lcEmojiDb) << "Loaded" << m_emojis.size() << "emojis after KDE dictionary:" << path;
            }
        }
    }

    // 2. Also check for emojis.txt to support custom kaomojis or fallback lists
    const QString shellConfig = qEnvironmentVariable("CAELESTIA_SHELL_CONFIG");
    const QString configDir = qEnvironmentVariable("XDG_CONFIG_HOME", QDir::homePath() + QStringLiteral("/.config"));
    const QString dataHome = qEnvironmentVariable("XDG_DATA_HOME", QDir::homePath() + QStringLiteral("/.local/share"));

    const QStringList textCandidates = {
        shellConfig.isEmpty() ? QString()
                              : QFileInfo(shellConfig).absoluteDir().filePath(QStringLiteral("assets/emojis.txt")),
        configDir + QStringLiteral("/quickshell/caelestia/assets/emojis.txt"),
        QDir::homePath() + QStringLiteral("/caelestia-kde/shell/assets/emojis.txt"),
        dataHome + QStringLiteral("/caelestia/assets/emojis.txt"),
        QStringLiteral("/usr/share/caelestia/assets/emojis.txt"),
    };

    for (const auto& path : textCandidates) {
        if (!path.isEmpty() && QFile::exists(path)) {
            if (loadTextFile(path, charMap)) {
                m_loaded = true;
                qCInfo(lcEmojiDb) << "Loaded extra emojis from text file:" << path;
            }
            break;
        }
    }

    if (!m_loaded) {
        qCWarning(lcEmojiDb) << "No KDE emoji dictionary or emojis.txt found. Emoji picker will be empty.";
        return;
    }

    buildTrigramIndex();
    emit loadedChanged();
}

void EmojiDb::buildTrigramIndex() {
    m_trigramIndex.clear();
    m_trigramIndex.reserve(m_emojis.size() * 8);
    for (int i = 0; i < m_emojis.size(); ++i) {
        const QString& name = m_emojis[i].nameLower;
        const int len = name.size();
        for (int j = 0; j + 2 < len; ++j) {
            const QString trigram = name.mid(j, 3);
            m_trigramIndex[trigram].append(i);
        }
    }
    qCInfo(lcEmojiDb) << "Trigram index built:" << m_trigramIndex.size() << "unique trigrams for" << m_emojis.size()
                      << "emojis.";
}

void EmojiDb::loadFrequencies() {
    QFile f(m_freqPath);
    if (!f.exists())
        return;

    if (!f.open(QIODevice::ReadOnly)) {
        qCWarning(lcEmojiDb) << "Failed to open frequency file:" << m_freqPath;
        return;
    }

    const auto doc = QJsonDocument::fromJson(f.readAll());
    if (!doc.isObject())
        return;

    const auto obj = doc.object();
    m_frequencies.clear();
    m_frequencies.reserve(obj.size());
    for (auto it = obj.begin(); it != obj.end(); ++it) {
        m_frequencies.insert(it.key(), it.value().toInt());
    }
}

void EmojiDb::saveFrequencies() {
    QJsonObject obj;
    for (auto it = m_frequencies.begin(); it != m_frequencies.end(); ++it) {
        obj.insert(it.key(), it.value());
    }

    const auto path = m_freqPath;
    QDir dir(QFileInfo(path).absolutePath());
    if (!dir.exists())
        dir.mkpath(QStringLiteral("."));

    QFile f(path);
    if (!f.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
        qCWarning(lcEmojiDb) << "Failed to write frequency file:" << path;
        return;
    }
    f.write(QJsonDocument(obj).toJson(QJsonDocument::Compact));
}

void EmojiDb::recordUsage(const QString& ch) {
    m_frequencies[ch] = m_frequencies.value(ch, 0) + 1;
    saveFrequencies();
}

int EmojiDb::getFrequency(const QString& ch) const {
    return m_frequencies.value(ch, 0);
}

QVariantList EmojiDb::getSortedItems(const QStringList& favourites, int limit) const {
    if (m_emojis.isEmpty())
        return {};

    const QSet<QString> favSet(favourites.begin(), favourites.end());

    QVector<int> indices(m_emojis.size());
    std::iota(indices.begin(), indices.end(), 0);

    std::stable_sort(indices.begin(), indices.end(), [&](int a, int b) {
        const bool aFav = favSet.contains(m_emojis[a].ch);
        const bool bFav = favSet.contains(m_emojis[b].ch);
        if (aFav != bFav)
            return aFav;
        const int freqA = m_frequencies.value(m_emojis[a].ch, 0);
        const int freqB = m_frequencies.value(m_emojis[b].ch, 0);
        return freqA > freqB;
    });

    QVariantList result;
    const int actualLimit =
        (limit <= 0) ? static_cast<int>(m_emojis.size()) : std::min(limit, static_cast<int>(m_emojis.size()));
    result.reserve(actualLimit);
    for (int i = 0; i < actualLimit; ++i) {
        const auto& e = m_emojis[indices[i]];
        result.append(QVariantMap{
            { QStringLiteral("ch"), e.ch },
            { QStringLiteral("name"), e.name },
            { QStringLiteral("nameLower"), e.nameLower },
        });
    }
    return result;
}

namespace {

int emojiMatchScore(const EmojiEntry& e, const QString& lower) {
    if (e.name.compare(lower, Qt::CaseInsensitive) == 0)
        return 0;
    if (e.name.startsWith(lower, Qt::CaseInsensitive))
        return 1;
    if (e.name.contains(QLatin1Char(' ') + lower, Qt::CaseInsensitive) ||
        e.name.contains(QLatin1Char('-') + lower, Qt::CaseInsensitive))
        return 2;
    if (e.name.contains(lower, Qt::CaseInsensitive))
        return 3;
    return 4;
}

struct ScoredCandidate {
    int index;
    int score;
    bool isFav;
    int freq;
    int nameLen;
};

} // namespace

QVariantList EmojiDb::search(const QString& text, int limit, const QStringList& favourites) const {
    if (m_emojis.isEmpty())
        return {};
    if (text.isEmpty())
        return getSortedItems(favourites, limit);

    const QString lower = text.toLower();
    const int queryLen = lower.size();

    QVector<int> matchedIndices;

    if (queryLen < 3 || m_trigramIndex.isEmpty()) {
        matchedIndices.reserve(m_emojis.size());
        for (int i = 0; i < m_emojis.size(); ++i) {
            if (m_emojis[i].nameLower.contains(lower)) {
                matchedIndices.append(i);
            }
        }
    } else {
        QSet<int> candidates;
        bool first = true;
        for (int i = 0; i + 2 < queryLen; ++i) {
            const QString trigram = lower.mid(i, 3);
            const auto it = m_trigramIndex.constFind(trigram);
            if (it == m_trigramIndex.constEnd()) {
                return {};
            }
            const QVector<int>& postings = it.value();
            if (first) {
                candidates = QSet<int>(postings.begin(), postings.end());
                first = false;
            } else {
                QSet<int> posting_set(postings.begin(), postings.end());
                candidates.intersect(posting_set);
                if (candidates.isEmpty())
                    return {};
            }
        }

        matchedIndices.reserve(candidates.size());
        for (int idx : std::as_const(candidates)) {
            if (m_emojis[idx].nameLower.contains(lower)) {
                matchedIndices.append(idx);
            }
        }
    }

    if (matchedIndices.isEmpty())
        return {};

    const QSet<QString> favSet(favourites.begin(), favourites.end());

    // Score each candidate once — avoid re-evaluating inside the comparator.
    QVector<ScoredCandidate> scored;
    scored.reserve(matchedIndices.size());
    for (int idx : std::as_const(matchedIndices)) {
        const auto& e = m_emojis[idx];
        scored.append({
            idx,
            emojiMatchScore(e, lower),
            favSet.contains(e.ch),
            m_frequencies.value(e.ch, 0),
            static_cast<int>(e.name.size()),
        });
    }

    const int actualLimit =
        (limit <= 0) ? static_cast<int>(scored.size()) : std::min(limit, static_cast<int>(scored.size()));

    // partial_sort: only the top `actualLimit` items reach their final position.
    auto cmp = [](const ScoredCandidate& a, const ScoredCandidate& b) {
        if (a.score != b.score)
            return a.score < b.score;
        if (a.isFav != b.isFav)
            return a.isFav;
        if (a.freq != b.freq)
            return a.freq > b.freq;
        if (a.nameLen != b.nameLen)
            return a.nameLen < b.nameLen;
        return a.index < b.index;
    };
    std::partial_sort(scored.begin(), scored.begin() + actualLimit, scored.end(), cmp);

    QVariantList result;
    result.reserve(actualLimit);
    for (int i = 0; i < actualLimit; ++i) {
        const auto& e = m_emojis[scored[i].index];
        result.append(QVariantMap{
            { QStringLiteral("ch"), e.ch },
            { QStringLiteral("name"), e.name },
            { QStringLiteral("nameLower"), e.nameLower },
        });
    }
    return result;
}

} // namespace caelestia::services
