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

Q_LOGGING_CATEGORY(lcEmojiDb, "caelestia.services.emojidb", QtInfoMsg)

namespace caelestia::services {

EmojiDb::EmojiDb(QObject* parent)
    : QObject(parent) {
    const auto configDir = qEnvironmentVariable("XDG_CONFIG_HOME", QDir::homePath() + QStringLiteral("/.config"));
    m_freqPath = configDir + QStringLiteral("/caelestia/emoji-frequencies.json");

    loadEmojis();
    loadFrequencies();
}

bool EmojiDb::loaded() const {
    return m_loaded;
}

int EmojiDb::count() const {
    return static_cast<int>(m_emojis.size());
}

bool EmojiDb::loadKdeDict(const QString& path) {
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
        m_emojis.append(std::move(entry));
    }

    return m_emojis.size() > initialSize;
}

bool EmojiDb::loadTextFile(const QString& path) {
    QFile f(path);
    if (!f.open(QIODevice::ReadOnly | QIODevice::Text))
        return false;

    QTextStream in(&f);
    const qsizetype initialSize = m_emojis.size();
    QSet<QString> existingChars;
    existingChars.reserve(m_emojis.size());
    for (const auto& e : m_emojis) {
        existingChars.insert(e.ch);
    }

    while (!in.atEnd()) {
        const auto line = in.readLine();
        if (line.isEmpty())
            continue;

        const auto spaceIdx = line.indexOf(u' ');
        if (spaceIdx < 0)
            continue;

        const QString ch = line.left(spaceIdx);
        if (existingChars.contains(ch))
            continue;

        EmojiEntry entry;
        entry.ch = ch;
        entry.name = line.mid(spaceIdx + 1).trimmed();
        entry.nameLower = entry.name.toLower();
        m_emojis.append(std::move(entry));
        existingChars.insert(ch);
    }

    return m_emojis.size() > initialSize;
}

void EmojiDb::loadEmojis() {
    m_emojis.clear();

    const QString kdeDir = QStringLiteral("/usr/share/plasma/emoji");
    if (QDir(kdeDir).exists()) {
        const QString localeName = QLocale::system().name();
        const QString lang = localeName.section(u'_', 0, 0);

        const QStringList kdeCandidates = {
            kdeDir + u'/' + localeName + QStringLiteral(".dict"),
            kdeDir + u'/' + lang + QStringLiteral(".dict"),
            kdeDir + QStringLiteral("/en.dict"),
        };

        for (const auto& path : kdeCandidates) {
            if (QFile::exists(path) && loadKdeDict(path)) {
                m_loaded = true;
                qCInfo(lcEmojiDb) << "Loaded" << m_emojis.size() << "emojis from KDE dictionary:" << path;
                break;
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
            if (loadTextFile(path)) {
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

    emit loadedChanged();
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

QVariantList EmojiDb::search(const QString& text, int limit) const {
    if (m_emojis.isEmpty())
        return {};
    if (text.isEmpty())
        return getSortedItems({});

    const auto lower = text.toLower();
    QVariantList result;
    result.reserve(std::min(limit, static_cast<int>(m_emojis.size())));

    for (const auto& e : m_emojis) {
        if (e.nameLower.contains(lower)) {
            result.append(QVariantMap{
                { QStringLiteral("ch"), e.ch },
                { QStringLiteral("name"), e.name },
                { QStringLiteral("nameLower"), e.nameLower },
            });
            if (result.size() >= limit)
                break;
        }
    }
    return result;
}

} // namespace caelestia::services
