#include <QtCore>
#include <QtNetwork>
#include <QtQml>
#include <QtTest>
#include <cmath>
#include <limits>

#include "../src/Caelestia/Config/rootnodes.hpp"
#include "lyrics.hpp"
#include "lyricsmatching.hpp"

namespace caelestia::services {

using namespace Qt::StringLiterals;

struct Response {
    QByteArray body = "{}"_ba;
    QNetworkReply::NetworkError error = QNetworkReply::NoError;
    int status = 200;
    int delay = 0;
};

class FakeReply : public QNetworkReply {
public:
    FakeReply(const QNetworkRequest& request, Response response, QObject* parent)
        : QNetworkReply(parent)
        , m_body(response.body) {
        setRequest(request);
        setUrl(request.url());
        setAttribute(QNetworkRequest::HttpStatusCodeAttribute, response.status);
        open(QIODevice::ReadOnly);
        QTimer::singleShot(response.delay, this, [this, response] {
            if (isFinished())
                return;
            if (response.error != NoError)
                setError(response.error, u"simulated network error"_s);
            setFinished(true);
            emit readyRead();
            emit finished();
        });
    }

    void abort() override {
        if (!isFinished()) {
            setError(OperationCanceledError, u"cancelled"_s);
            setFinished(true);
            emit finished();
        }
    }

    [[nodiscard]] qint64 bytesAvailable() const override { return m_body.size() + QNetworkReply::bytesAvailable(); }

protected:
    qint64 readData(char* data, qint64 maximum) override {
        if (m_body.isEmpty())
            return -1;
        const auto count = std::min<qint64>(maximum, m_body.size());
        memcpy(data, m_body.constData(), static_cast<size_t>(count));
        m_body.remove(0, count);
        return count;
    }

private:
    QByteArray m_body;
};

class FakeNetwork : public QNetworkAccessManager {
public:
    using QNetworkAccessManager::QNetworkAccessManager;
    QList<QUrl> requests;
    std::function<Response(const QUrl&)> respond;

protected:
    QNetworkReply* createRequest(Operation, const QNetworkRequest& request, QIODevice*) override {
        requests.append(request.url());
        return new FakeReply(request, respond ? respond(request.url()) : Response{}, this);
    }
};

static QByteArray track(int id = 42, const QString& title = u"Example"_s, double duration = 200) {
    return QJsonDocument(
        QJsonObject{ { u"id"_s, id }, { u"trackName"_s, title }, { u"artistName"_s, u"Artist"_s },
            { u"duration"_s, duration }, { u"syncedLyrics"_s, u"[00:00.00]First line\n[00:10.00]Second line"_s } })
        .toJson();
}

class LyricsTest : public QObject {
    Q_OBJECT
    QTemporaryDir m_dir;

    FakeNetwork* network(Lyrics& lyrics) {
        delete lyrics.m_nam;
        auto* fake = new FakeNetwork(&lyrics);
        lyrics.m_nam = fake;
        return fake;
    }

    void prepare(Lyrics& lyrics, const QString& title = u"Example"_s) {
        lyrics.m_artist = u"Artist"_s;
        lyrics.m_title = title;
        lyrics.m_duration = 200;
        lyrics.m_preferredBackend = LyricsBackend::LRCLIB;
    }

private slots:

    void initTestCase() {
        QVERIFY(m_dir.isValid());
        qputenv("XDG_CONFIG_HOME", (m_dir.path() + u"/config"_s).toUtf8());
        qputenv("XDG_STATE_HOME", (m_dir.path() + u"/state"_s).toUtf8());
        qputenv("XDG_CACHE_HOME", (m_dir.path() + u"/cache"_s).toUtf8());
        config::ConfigSingleton::instance()->paths()->set_lyricsDir(m_dir.path() + u"/local"_s);
    }

    void init() {
        QDir(m_dir.path() + u"/cache"_s).removeRecursively();
        QDir(m_dir.path() + u"/state"_s).removeRecursively();
    }

    void matchingPreservesRecordings() {
        using namespace lyricsmatching;
        QVERIFY(
            score(u"Example (Official Music Video)"_s, u"Artist - Topic"_s, 200, u"Example"_s, u"Artist"_s, 201) > 0);
        QVERIFY(score(u"Example"_s, u"Artist"_s, 200, u"Different"_s, u"Artist"_s, 200) < 0);
        QVERIFY(score(u"Example (Live)"_s, u"Artist"_s, 200, u"Example"_s, u"Artist"_s, 200) < 0);
        QVERIFY(score(u"Example (Remix)"_s, u"Artist"_s, 200, u"Example"_s, u"Artist"_s, 200) < 0);
        QVERIFY(score(u"Example"_s, u"Artist"_s, 200, u"Example"_s, u"Another Artist"_s, 290) < 0);
        QVERIFY(score(u"Example"_s, u"Artist"_s, 0, u"Example"_s, u"Artist"_s, 0) > 0);
        QVERIFY(score(u"Example"_s, u""_s, 200, u"Example"_s, u"Artist"_s, 200) < 0);
        QVERIFY(score(QString::fromUtf8("دل"), u"Artist"_s, 200, QString::fromUtf8("دل"), u"Artist"_s, 200) > 0);
    }

    void matchingHandlesNanAndPunctuation() {
        using namespace lyricsmatching;
        const double nanVal = std::numeric_limits<double>::quiet_NaN();
        // NaN duration should fall back safely without dividing by zero or crashing
        QVERIFY(score(u"Example"_s, u"Artist"_s, nanVal, u"Example"_s, u"Artist"_s, 200) > 0);
        QVERIFY(score(u"Example"_s, u"Artist"_s, 200, u"Example"_s, u"Artist"_s, nanVal) > 0);
        // Non-alphanumeric only strings reject safely
        QVERIFY(score(u"???"_s, u"Artist"_s, 200, u"???"_s, u"Artist"_s, 200) < 0);
        // Long repetitive input does not hang regex
        const QString repeated = u"[Official Music Video] "_s.repeated(100) + u"Song"_s;
        QCOMPARE(title(repeated), u"Song"_s);
    }

    void refreshRestoresTheSameCandidate() {
        Lyrics lyrics;
        auto* fake = network(lyrics);
        prepare(lyrics);
        fake->respond = [](const QUrl& url) {
            return Response{ url.path() == u"/api/get"_s ? track() : QByteArray("[]") };
        };
        lyrics.doLoad();
        QTRY_VERIFY(lyrics.hasLyrics());
        QCOMPARE(lyrics.selectedCandidate().id(), u"42"_s);
        lyrics.refresh();
        QTest::qWait(100);
        QTRY_VERIFY(!lyrics.loading());
        QVERIFY(lyrics.hasLyrics());
        QCOMPARE(lyrics.lyrics().size(), 2);
    }

    void ranksSearchAfterAnExactMiss() {
        Lyrics lyrics;
        auto* fake = network(lyrics);
        prepare(lyrics, u"Example (Official Video)"_s);
        fake->respond = [](const QUrl& url) {
            if (url.path() == u"/api/get"_s)
                return Response{ "{}"_ba, QNetworkReply::ContentNotFoundError, 404 };
            if (url.path() == u"/api/search"_s)
                return Response{ "[" + track(1, u"Example (Live)"_s) + "," + track(2, u"Example"_s, 201) + "]" };
            return Response{};
        };
        lyrics.doLoad();
        QTRY_VERIFY(!lyrics.loading());
        QVERIFY(lyrics.hasLyrics());
        QCOMPARE(lyrics.selectedCandidate().id(), u"2"_s);
    }

    void failedSavedCandidateFallsBack() {
        Lyrics lyrics;
        auto* fake = network(lyrics);
        prepare(lyrics);
        lyrics.m_lyricsMap.insert(
            lyrics.trackKey(), QJsonObject{ { u"backend"_s, u"LRCLIB"_s }, { u"id"_s, u"999"_s } });
        fake->respond = [](const QUrl& url) {
            if (url.path() == u"/api/get/999"_s)
                return Response{ "{}"_ba, QNetworkReply::ContentNotFoundError, 404 };
            return Response{ url.path() == u"/api/get"_s ? track() : QByteArray("[]") };
        };
        lyrics.doLoad();
        QTRY_VERIFY(!lyrics.loading());
        QVERIFY(lyrics.hasLyrics());
        QCOMPARE(lyrics.selectedCandidate().id(), u"42"_s);
    }

    void netEaseRejectsAnotherSongByTheSameArtist() {
        Lyrics lyrics;
        auto* fake = network(lyrics);
        prepare(lyrics);
        lyrics.m_preferredBackend = LyricsBackend::NetEase;
        fake->respond = [](const QUrl& url) {
            if (url.path() == u"/api/search/get"_s) {
                QJsonArray songs;
                for (int id : { 1, 2 }) {
                    songs.append(QJsonObject{ { u"id"_s, id }, { u"name"_s, id == 1 ? u"Different"_s : u"Example"_s },
                        { u"duration"_s, 200000 },
                        { u"artists"_s, QJsonArray{ QJsonObject{ { u"name"_s, u"Artist"_s } } } } });
                }
                return Response{
                    QJsonDocument(QJsonObject{ { u"result"_s, QJsonObject{ { u"songs"_s, songs } } } }).toJson()
                };
            }
            if (url.path() == u"/api/song/lyric"_s)
                return Response{ R"({"lrc":{"lyric":"[00:00.00]Correct song"}})"_ba };
            return Response{ "[]"_ba };
        };
        lyrics.doLoad();
        QTRY_VERIFY(!lyrics.loading());
        QVERIFY(lyrics.hasLyrics());
        QCOMPARE(lyrics.selectedCandidate().id(), u"2"_s);
    }

    void searchRejectsDifferentRecordings() {
        Lyrics lyrics;
        auto* fake = network(lyrics);
        prepare(lyrics);
        fake->respond = [](const QUrl& url) {
            if (url.path() == u"/api/get"_s)
                return Response{ "{}"_ba, QNetworkReply::ContentNotFoundError, 404 };
            if (url.path() == u"/api/search"_s)
                return Response{ "[" + track(1, u"Example (Live)"_s) + "," + track(2, u"Example"_s, 300) + "]" };
            return Response{ "[]"_ba };
        };
        lyrics.doLoad();
        QTRY_VERIFY(!lyrics.loading());
        QVERIFY(!lyrics.hasLyrics());
    }

    void transientFailureRetriesOnce() {
        Lyrics lyrics;
        auto* fake = network(lyrics);
        prepare(lyrics);
        int attempts = 0;
        fake->respond = [&attempts](const QUrl& url) {
            if (url.path() != u"/api/get"_s)
                return Response{ "[]"_ba };
            if (++attempts == 1)
                return Response{ "{}"_ba, QNetworkReply::TimeoutError };
            return Response{ track() };
        };
        lyrics.doLoad();
        QTRY_VERIFY(lyrics.hasLyrics());
        QCOMPARE(attempts, 2);
    }

    void nonTransientFailureDoesNotRetry() {
        Lyrics lyrics;
        auto* fake = network(lyrics);
        prepare(lyrics);
        int attempts = 0;
        fake->respond = [&attempts](const QUrl& url) {
            if (url.path() == u"/api/get"_s) {
                ++attempts;
                return Response{ "{}"_ba, QNetworkReply::ContentNotFoundError, 404 };
            }
            return Response{ "[]"_ba };
        };
        lyrics.doLoad();
        QTRY_VERIFY(!lyrics.loading());
        // 404 is permanent, so it must not retry
        QCOMPARE(attempts, 1);
        QVERIFY(!lyrics.hasLyrics());
    }

    void retriesAreBounded() {
        Lyrics lyrics;
        auto* fake = network(lyrics);
        prepare(lyrics);
        int attempts = 0;
        fake->respond = [&attempts](const QUrl& url) {
            if (url.path() == u"/api/get"_s) {
                ++attempts;
                return Response{ "{}"_ba, QNetworkReply::TimeoutError };
            }
            return Response{ "[]"_ba };
        };
        lyrics.doLoad();
        QTRY_VERIFY(!lyrics.loading());
        QCOMPARE(attempts, 2);
        QVERIFY(!lyrics.hasLyrics());
    }

    void clearingTrackCancelsPendingRetry() {
        Lyrics lyrics;
        auto* fake = network(lyrics);
        prepare(lyrics);
        fake->respond = [](const QUrl&) {
            return Response{ "{}"_ba, QNetworkReply::TimeoutError };
        };
        lyrics.doLoad();
        QTest::qWait(20);
        lyrics.clearTrack();
        const auto count = fake->requests.size();
        QTest::qWait(850);
        QCOMPARE(fake->requests.size(), count);
        QVERIFY(!lyrics.hasLyrics());
        QVERIFY(!lyrics.loading());
    }

    void lateMetadataReplacesPendingRequests() {
        Lyrics lyrics;
        auto* fake = network(lyrics);
        prepare(lyrics);
        fake->respond = [](const QUrl& url) {
            if (url.path() == u"/api/get"_s)
                return Response{ track(), QNetworkReply::NoError, 200, 200 };
            return Response{ "[]"_ba };
        };
        lyrics.doLoad();
        lyrics.setTrack(u"Artist"_s, u"Next"_s, u"Album"_s, 210);
        lyrics.clearTrack();
        QTest::qWait(300);
        QVERIFY(!lyrics.loading());
        QVERIFY(!lyrics.hasLyrics());
        // clearTrack must also stop the metadata debounce timer.
        QCOMPARE(fake->requests.size(), 3);
    }

    void rapidMetadataDebounce() {
        Lyrics lyrics;
        auto* fake = network(lyrics);
        fake->respond = [](const QUrl&) {
            return Response{ track() };
        };
        // Rapid sequential updates as Firefox MPRIS properties stream in
        lyrics.setTrack(u"Artist"_s, u""_s);
        QTest::qWait(10);
        lyrics.setTrack(u"Artist"_s, u"Title"_s);
        QTest::qWait(10);
        lyrics.setTrack(u"Artist"_s, u"Title"_s, u"Album"_s, 200);

        // Before debounce fires (50ms interval), no requests dispatched yet
        QCOMPARE(fake->requests.size(), 0);

        // Wait for debounce timer to fire
        QTRY_VERIFY(fake->requests.size() >= 1);
        QTRY_VERIFY(lyrics.hasLyrics());
        QCOMPARE(lyrics.trackTitle(), u"Title"_s);
    }

    void localCandidateFailureFallsBack() {
        Lyrics lyrics;
        network(lyrics);
        prepare(lyrics);
        // Set an invalid local candidate that cannot be opened
        LyricCandidate badLocal(LyricsBackend::Local, u"/nonexistent/path/to/song.lrc"_s, u"Example"_s, u"Artist"_s);
        lyrics.setSelectedCandidate(badLocal);
        // candidateFailed should handle failure without freezing in loading state
        QTRY_VERIFY(!lyrics.loading());
        QVERIFY(!lyrics.hasLyrics());
    }
};

} // namespace caelestia::services

QTEST_GUILESS_MAIN(caelestia::services::LyricsTest)
#include "lyrics-test.moc"
