// SPDX-License-Identifier: GPL-3.0-only
#include "dinogame.hpp"

#include <QDir>
#include <QFile>
#include <QRandomGenerator>
#include <QStandardPaths>
#include <algorithm>
#include <cmath>

namespace caelestia::services {

DinoGameBackend::DinoGameBackend(QObject* parent)
    : QObject(parent) {
    readHighScore();
}

void DinoGameBackend::setIsDucking(bool val) {
    if (m_isDucking != val) {
        m_isDucking = val;
        emit isDuckingChanged();
    }
}

void DinoGameBackend::setWidth(qreal val) {
    if (m_width != val) {
        m_width = val;
        emit widthChanged();
    }
}

void DinoGameBackend::startGame() {
    if (m_isGameOver) {
        m_score = 0;
        emit scoreChanged();
        m_obstacles.clear();
        emit obstaclesChanged();
        m_clouds.clear();
        emit cloudsChanged();
        m_groundX = 0;
        emit groundXChanged();
        m_gameSpeed = m_baseSpeed;
        m_frameCount = 0;
        m_frameTime = 0;
        emit frameCountChanged();
        m_isInverted = false;
        emit isInvertedChanged();
    }

    m_isPlaying = true;
    emit isPlayingChanged();
    m_isGameOver = false;
    emit isGameOverChanged();
    if (m_isPaused) {
        m_isPaused = false;
        emit isPausedChanged();
    }
    if (m_isNewHighScore) {
        m_isNewHighScore = false;
        emit isNewHighScoreChanged();
    }

    m_dinoY = 0;
    emit dinoYChanged();
    m_dinoVelocityY = 0;
    m_jumpBuffer = 0;

    emit gameStarted();
}

void DinoGameBackend::gameOver() {
    m_isPlaying = false;
    emit isPlayingChanged();
    m_isGameOver = true;
    emit isGameOverChanged();
    if (m_isPaused) {
        m_isPaused = false;
        emit isPausedChanged();
    }

    emit gameDied();

    if (m_score > m_highScore) {
        // Only a beaten record counts, not the first score on an empty one.
        if (m_highScore > 0) {
            m_isNewHighScore = true;
            emit isNewHighScoreChanged();
        }
        m_highScore = m_score;
        emit highScoreChanged();
        writeHighScore();
    }
}

void DinoGameBackend::jump() {
    if (!m_isPlaying) {
        startGame();
    } else if (m_isPaused) {
        m_isPaused = false;
        emit isPausedChanged();
    } else if (m_dinoY == 0) {
        m_dinoVelocityY = m_jumpForce;
    } else {
        // Pressed just before landing: jump on touchdown instead of dropping the press.
        m_jumpBuffer = 6;
    }
}

void DinoGameBackend::pause() {
    if (!m_isPlaying || m_isPaused)
        return;
    m_isPaused = true;
    emit isPausedChanged();
}

void DinoGameBackend::advance(qreal elapsedMs) {
    if (!m_isPlaying || m_isPaused)
        return;

    // Capped so a stalled frame cannot carry the dino through an obstacle.
    qreal frames = std::clamp(elapsedMs / (1000.0 / 60.0), 0.0, 4.0);
    const int prevFrameCount = m_frameCount;
    const bool prevInverted = m_isInverted;

    while (frames > 0 && m_isPlaying) {
        const qreal f = std::min(frames, 1.0);
        step(f);
        frames -= f;
    }

    emit dinoYChanged();
    if (m_frameCount != prevFrameCount)
        emit frameCountChanged();
    if (m_isInverted != prevInverted)
        emit isInvertedChanged();
    emit scoreChanged();
    emit groundXChanged();
    emit cloudsChanged();
    emit obstaclesChanged();
}

void DinoGameBackend::step(qreal f) {
    m_jumpBuffer = std::max(0.0, m_jumpBuffer - f);
    m_dinoVelocityY += (m_isDucking ? m_duckGravity : m_gravity) * f;
    m_dinoY += m_dinoVelocityY * f;
    if (m_dinoY > 0) {
        m_dinoY = 0;
        m_dinoVelocityY = 0;
        if (m_jumpBuffer > 0) {
            m_jumpBuffer = 0;
            m_dinoVelocityY = m_jumpForce;
        }
    }

    m_frameTime += f;
    m_frameCount = static_cast<int>(m_frameTime);

    m_score += 0.15 * f;
    // Continuous, at the rate the old per-100 bump really ran at: it added 0.05 on every
    // tick whose floored score was a multiple of 100, about 6.7 ticks each time.
    m_gameSpeed = m_baseSpeed + m_score / 300.0;

    m_groundX = std::fmod(m_groundX + m_gameSpeed * f, 2400.0);

    QVariantList newClouds;
    for (const QVariant& v : m_clouds) {
        QVariantMap cloud = v.toMap();
        cloud[QStringLiteral("x")] = cloud[QStringLiteral("x")].toDouble() - m_gameSpeed * 0.25 * f;
        if (cloud[QStringLiteral("x")].toDouble() + 92 > 0) {
            newClouds.append(cloud);
        }
    }
    m_clouds = newClouds;

    // Both spawns roll a fresh threshold per check, so they only check on whole 60 Hz
    // frames: rolling on every short step would spawn earlier on faster displays.
    const bool newCloudFrame = static_cast<int>(m_cloudTimer + f) != static_cast<int>(m_cloudTimer);
    m_cloudTimer += f;
    if (newCloudFrame && m_cloudTimer > 150 + QRandomGenerator::global()->generateDouble() * 200) {
        m_cloudTimer = 0;
        QVariantMap cloud;
        cloud[QStringLiteral("x")] = m_width;
        cloud[QStringLiteral("y")] = 10 + QRandomGenerator::global()->generateDouble() * 80;
        m_clouds.append(cloud);
    }

    m_isInverted = (static_cast<int>(m_score / 700) % 2) == 1;

    if (m_score >= 99999) {
        m_score = 99999;
        emit scoreChanged();
        gameOver();
        return;
    }

    QVariantList newObstacles;
    qreal dWidth = m_isDucking ? 59 : 44;
    qreal dHeight = m_isDucking ? 30 : 47;

    for (const QVariant& v : m_obstacles) {
        QVariantMap obs = v.toMap();
        obs[QStringLiteral("x")] = obs[QStringLiteral("x")].toDouble() - m_gameSpeed * f;

        qreal oX = obs[QStringLiteral("x")].toDouble() + 8;
        qreal oW = obs[QStringLiteral("width")].toDouble() - 16;
        qreal oYOffset = obs[QStringLiteral("yOffset")].toDouble();
        qreal oH = obs[QStringLiteral("height")].toDouble() - 16;

        qreal dX = 40;
        qreal dW = dWidth - 20;

        qreal dY = -30 - dHeight + m_dinoY + 10;
        qreal dH = dHeight - 15;
        qreal oY = -30 - obs[QStringLiteral("height")].toDouble() - oYOffset + 8;

        if (dX < oX + oW && dX + dW > oX && dY < oY + oH && dY + dH > oY) {
            gameOver();
            return;
        }

        if (obs[QStringLiteral("x")].toDouble() + obs[QStringLiteral("width")].toDouble() > 0) {
            newObstacles.append(obs);
        }
    }
    m_obstacles = newObstacles;

    const bool newObstacleFrame = static_cast<int>(m_obstacleTimer + f) != static_cast<int>(m_obstacleTimer);
    m_obstacleTimer += f;
    if (newObstacleFrame && m_obstacleTimer > 60 + QRandomGenerator::global()->generateDouble() * 80) {
        m_obstacleTimer = 0;
        bool canSpawnBird = m_score > 300;
        QString spawnType = (canSpawnBird && QRandomGenerator::global()->generateDouble() > 0.7)
                                ? QStringLiteral("bird")
                                : (QRandomGenerator::global()->generateDouble() > 0.5 ? QStringLiteral("small")
                                                                                      : QStringLiteral("large"));

        QVariantMap newObs;
        newObs[QStringLiteral("x")] = m_width;
        newObs[QStringLiteral("type")] = spawnType;
        if (spawnType == QStringLiteral("bird")) {
            newObs[QStringLiteral("width")] = 46;
            newObs[QStringLiteral("height")] = 40;
            double heights[] = { 10, 35, 60 };
            newObs[QStringLiteral("yOffset")] = heights[QRandomGenerator::global()->bounded(3)];
        } else if (spawnType == QStringLiteral("small")) {
            newObs[QStringLiteral("width")] = 34;
            newObs[QStringLiteral("height")] = 35;
            newObs[QStringLiteral("yOffset")] = 0;
        } else {
            newObs[QStringLiteral("width")] = 25;
            newObs[QStringLiteral("height")] = 50;
            newObs[QStringLiteral("yOffset")] = 0;
        }
        m_obstacles.append(newObs);
    }
}

void DinoGameBackend::readHighScore() {
    QString path = QStandardPaths::writableLocation(QStandardPaths::ConfigLocation) +
                   QStringLiteral("/caelestia/dino_highscore.txt");
    QFile f(path);
    if (f.open(QIODevice::ReadOnly)) {
        m_highScore = QString::fromUtf8(f.readAll()).trimmed().toDouble();
        emit highScoreChanged();
    }
}

void DinoGameBackend::writeHighScore() {
    QString dir = QStandardPaths::writableLocation(QStandardPaths::ConfigLocation) + QStringLiteral("/caelestia");
    QDir().mkpath(dir);
    QFile f(dir + QStringLiteral("/dino_highscore.txt"));
    if (f.open(QIODevice::WriteOnly)) {
        f.write(QString::number(std::floor(m_highScore)).toUtf8());
    }
}

} // namespace caelestia::services
