// SPDX-License-Identifier: GPL-3.0-only
#pragma once

#include <qcolor.h>
#include <qobject.h>
#include <qqmlintegration.h>
#include <qvariant.h>

namespace caelestia::services {

class PaletteManager : public QObject {
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

    Q_PROPERTY(QVariantMap tPalette READ tPalette NOTIFY tPaletteChanged)

public:
    explicit PaletteManager(QObject* parent = nullptr);

    [[nodiscard]] QVariantMap tPalette() const;

    Q_INVOKABLE void update(const QVariantMap& palette, bool light, bool transpEnabled, double transpBase,
        double transpLayers, double wallLuminance);

signals:
    void tPaletteChanged();

private:
    QColor applyLayer(const QColor& c, bool light, bool transpEnabled, double transpBase, double transpLayers,
        double wallLuminance, int layer) const;

    double getLuminance(const QColor& c) const;

    QVariantMap m_tPalette;
};

} // namespace caelestia::services
