#include <QtCore>
#include <QtTest>

#include "dinogame.hpp"

namespace caelestia::services {

class DinoGameTest : public QObject {
    Q_OBJECT

private:
    // Obstacles spawn at the right edge; far enough away, none reaches the dino here.
    static void startFarFromObstacles(DinoGameBackend& game) {
        game.setWidth(1e6);
        game.jump();
        QVERIFY(game.isPlaying());
    }

    static qreal apexAt(qreal hz) {
        DinoGameBackend game;
        startFarFromObstacles(game);
        game.jump();
        qreal apex = 0;
        for (int i = 0; i < hz * 2; ++i) {
            game.advance(1000.0 / hz);
            apex = std::min(apex, game.dinoY());
        }
        return apex;
    }

private slots:

    void initTestCase() { QStandardPaths::setTestModeEnabled(true); }

    void jumpHeightDoesNotDependOnRefreshRate() {
        const qreal at60 = apexAt(60);
        const qreal at144 = apexAt(144);
        QVERIFY(at60 < -50);
        QVERIFY2(std::abs(at144 - at60) / std::abs(at60) < 0.05,
            qPrintable(QStringLiteral("60 Hz apex %1, 144 Hz apex %2").arg(at60).arg(at144)));
    }

    void scoreFollowsTimeNotFrames() {
        DinoGameBackend at60;
        DinoGameBackend at144;
        startFarFromObstacles(at60);
        startFarFromObstacles(at144);
        for (int i = 0; i < 60; ++i)
            at60.advance(1000.0 / 60);
        for (int i = 0; i < 144; ++i)
            at144.advance(1000.0 / 144);
        QVERIFY(std::abs(at60.score() - 9.0) < 0.01);
        QVERIFY(std::abs(at144.score() - at60.score()) < 0.01);
    }

    void aStalledFrameIsCapped() {
        DinoGameBackend game;
        startFarFromObstacles(game);
        game.advance(5000);
        QVERIFY(std::abs(game.score() - 0.15 * 4) < 0.01);
    }

    void pauseStopsAndJumpResumesWithoutJumping() {
        DinoGameBackend game;
        startFarFromObstacles(game);
        game.advance(100);
        game.pause();
        QVERIFY(game.isPaused());
        const qreal score = game.score();
        game.advance(500);
        QCOMPARE(game.score(), score);

        game.jump();
        QVERIFY(!game.isPaused());
        game.advance(1000.0 / 60);
        QCOMPARE(game.dinoY(), 0.0);
    }

    void aJumpPressedJustBeforeLandingIsKept() {
        DinoGameBackend game;
        startFarFromObstacles(game);
        game.jump();
        // Run until the dino is falling and close to the ground.
        int frames = 0;
        while (game.dinoY() < -15 || frames < 5) {
            game.advance(1000.0 / 60);
            ++frames;
            QVERIFY(frames < 120);
        }
        QVERIFY2(game.dinoY() < 0, "the press has to land while still in the air");
        game.jump();
        for (int i = 0; i < 4; ++i)
            game.advance(1000.0 / 60);
        QVERIFY2(game.dinoY() < 0, "the buffered jump should lift off on touchdown");
    }

    void onlyABeatenRecordIsNew() {
        QFile::remove(QStandardPaths::writableLocation(QStandardPaths::ConfigLocation) +
                      QStringLiteral("/caelestia/dino_highscore.txt"));
        DinoGameBackend first;
        startFarFromObstacles(first);
        for (int i = 0; i < 60; ++i)
            first.advance(1000.0 / 60);
        first.gameOver();
        QVERIFY(!first.isNewHighScore());

        DinoGameBackend second;
        startFarFromObstacles(second);
        for (int i = 0; i < 120; ++i)
            second.advance(1000.0 / 60);
        second.gameOver();
        QVERIFY(second.isNewHighScore());

        second.jump();
        QVERIFY(!second.isNewHighScore());
    }
};

} // namespace caelestia::services

QTEST_GUILESS_MAIN(caelestia::services::DinoGameTest)
#include "dinogame-test.moc"
