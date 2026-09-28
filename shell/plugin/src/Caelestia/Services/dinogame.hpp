// SPDX-License-Identifier: GPL-3.0-only
#pragma once

#include <QObject>
#include <QQmlEngine>
#include <QTimer>
#include <QVariantList>
#include <QVariantMap>

namespace caelestia::services {

class DinoGameBackend : public QObject {
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

    Q_PROPERTY(bool isPlaying READ isPlaying NOTIFY isPlayingChanged)
    Q_PROPERTY(bool isGameOver READ isGameOver NOTIFY isGameOverChanged)
    Q_PROPERTY(bool isDucking READ isDucking WRITE setIsDucking NOTIFY isDuckingChanged)
    Q_PROPERTY(bool isInverted READ isInverted NOTIFY isInvertedChanged)

    Q_PROPERTY(qreal score READ score NOTIFY scoreChanged)
    Q_PROPERTY(qreal highScore READ highScore NOTIFY highScoreChanged)
    Q_PROPERTY(qreal dinoY READ dinoY NOTIFY dinoYChanged)
    Q_PROPERTY(qreal groundX READ groundX NOTIFY groundXChanged)
    Q_PROPERTY(int frameCount READ frameCount NOTIFY frameCountChanged)

    Q_PROPERTY(QVariantList obstacles READ obstacles NOTIFY obstaclesChanged)
    Q_PROPERTY(QVariantList clouds READ clouds NOTIFY cloudsChanged)

    Q_PROPERTY(qreal width READ width WRITE setWidth NOTIFY widthChanged)

public:
    explicit DinoGameBackend(QObject* parent = nullptr);

    bool isPlaying() const { return m_isPlaying; }

    bool isGameOver() const { return m_isGameOver; }

    bool isDucking() const { return m_isDucking; }

    bool isInverted() const { return m_isInverted; }

    qreal score() const { return m_score; }

    qreal highScore() const { return m_highScore; }

    qreal dinoY() const { return m_dinoY; }

    qreal groundX() const { return m_groundX; }

    int frameCount() const { return m_frameCount; }

    QVariantList obstacles() const { return m_obstacles; }

    QVariantList clouds() const { return m_clouds; }

    qreal width() const { return m_width; }

    void setIsDucking(bool val);
    void setWidth(qreal val);

    Q_INVOKABLE void startGame();
    Q_INVOKABLE void gameOver();
    Q_INVOKABLE void jump();

signals:
    void isPlayingChanged();
    void isGameOverChanged();
    void isDuckingChanged();
    void isInvertedChanged();
    void scoreChanged();
    void highScoreChanged();
    void dinoYChanged();
    void groundXChanged();
    void frameCountChanged();
    void obstaclesChanged();
    void cloudsChanged();
    void widthChanged();

    void gameStarted();
    void gameDied();

private slots:
    void tick();

private:
    void readHighScore();
    void writeHighScore();

    QTimer* m_timer;

    bool m_isPlaying = false;
    bool m_isGameOver = false;
    bool m_isDucking = false;
    bool m_isInverted = false;

    qreal m_score = 0;
    qreal m_highScore = 0;
    qreal m_dinoY = 0;
    qreal m_dinoVelocityY = 0;
    qreal m_groundX = 0;
    qreal m_gameSpeed = 6.0;
    int m_frameCount = 0;
    qreal m_width = 250;

    int m_cloudTimer = 0;
    int m_obstacleTimer = 0;

    const qreal m_gravity = 0.8;
    const qreal m_duckGravity = 1.5;
    const qreal m_jumpForce = -13.0;

    QVariantList m_obstacles;
    QVariantList m_clouds;
};

} // namespace caelestia::services
