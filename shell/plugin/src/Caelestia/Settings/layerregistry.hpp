#pragma once

#include <qdir.h>
#include <qfile.h>
#include <qhash.h>
#include <qobject.h>
#include <qstringlist.h>
#include <qstringview.h>

#include "node.hpp"
#include "rootnode.hpp"

namespace caelestia::settings {

// Derived from RootNode and has ctor(path, fallback, parent). RootNode rather
// than Node: forgetting a layer reloads it from (the now missing) file, which
// only roots can do.
template <typename T>
concept LayerType = std::derived_from<T, RootNode> && std::constructible_from<T, const QString&, T*, QObject*>;

template <LayerType T> class LayerRegistry {
public:
    explicit LayerRegistry(const QString& prefix, const QString& suffix, QObject* parent);

    [[nodiscard]] QString pathFor(const QString& name) const;
    [[nodiscard]] QString nameFor(T* layer) const;
    [[nodiscard]] T* get(const QString& name, T* fallback, bool* created = nullptr); // Created on demand
    [[nodiscard]] QStringList names() const; // Screens with a layer file on disk, connected or not
    bool forget(const QString& name); // Delete the layer file and reset the layer, if any

private:
    const QString m_prefix;
    const QString m_suffix;
    QObject* const m_parent;
    QHash<QString, T*> m_layers;
};

namespace detail {

inline QString stripTrailingSlashes(QStringView str) {
    while (str.endsWith(QLatin1Char('/')))
        str = str.left(str.length() - 1);
    return str.toString();
}

inline QString stripLeadingSlashes(QStringView str) {
    while (str.startsWith(QLatin1Char('/')))
        str = str.mid(1);
    return str.toString();
}

} // namespace detail

template <LayerType T>
LayerRegistry<T>::LayerRegistry(const QString& prefix, const QString& suffix, QObject* parent)
    : m_prefix(detail::stripTrailingSlashes(prefix))
    , m_suffix(detail::stripLeadingSlashes(suffix))
    , m_parent(parent) {}

template <LayerType T> QString LayerRegistry<T>::pathFor(const QString& name) const {
    return m_prefix + QLatin1Char('/') + name + QLatin1Char('/') + m_suffix;
}

template <LayerType T> QString LayerRegistry<T>::nameFor(T* layer) const {
    return m_layers.key(layer);
}

template <LayerType T> T* LayerRegistry<T>::get(const QString& name, T* fallback, bool* created) {
    if (auto* const layer = m_layers.value(name)) {
        if (created)
            *created = false;
        return layer;
    }

    if (created)
        *created = true;

    auto* const layer = new T(pathFor(name), fallback, m_parent);
    m_layers.insert(name, layer);
    return layer;
}

template <LayerType T> QStringList LayerRegistry<T>::names() const {
    QStringList names;
    const QDir dir(m_prefix);
    if (!dir.exists())
        return names;

    // Layers are created on demand, so the in-memory registry misses screens
    // that were never connected this session; the directory is the source of
    // truth for which screens have settings on disk.
    const auto entries = dir.entryList(QDir::Dirs | QDir::NoDotAndDotDot);
    for (const auto& name : entries) {
        if (QFile::exists(pathFor(name)))
            names.push_back(name);
    }
    return names;
}

template <LayerType T> bool LayerRegistry<T>::forget(const QString& name) {
    // The name comes from QML; never let it escape the layer directory.
    if (name.isEmpty() || name.contains(QLatin1Char('/')) || name == u"." || name == u"..")
        return false;

    QFile::remove(pathFor(name));
    // Only removes the directory when it is empty; another singleton may still
    // have a file next to this one's (shell.json, shell-tokens.json).
    QDir(m_prefix).rmdir(name);

    if (auto* const layer = m_layers.value(name))
        layer->load(); // The missing file reads back as "no overrides"
    return true;
}

} // namespace caelestia::settings
