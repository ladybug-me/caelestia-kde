#!/usr/bin/env bash

kwriteconfig6 --file kwinrc --group Plugins --key magiclampEnabled true 2>/dev/null || true
kwriteconfig6 --file kwinrc --group Plugins --key squashEnabled false 2>/dev/null || true
qdbus6 org.kde.KWin /Effects org.kde.kwin.Effects.unloadEffect "squash" 2>/dev/null || true
qdbus6 org.kde.KWin /Effects org.kde.kwin.Effects.loadEffect "magiclamp" 2>/dev/null || true

echo "StartupTasks: Initialized Magic Lamp default"
# Return 1 to indicate KWin reconfigure is needed
exit 1
