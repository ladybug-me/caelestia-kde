#!/usr/bin/env bash
if [[ -z "${CAELESTIA_PANELS_SOURCED:-}" ]]; then
CAELESTIA_PANELS_SOURCED=1

stock_panel_script() {
    cat <<'JS'
if (panels().length === 0) {
    var panel = new Panel;
    panel.alignment = 'center';
    panel.location = 'bottom';
    panel.hiding = 'dodgewindows';
    panel.height = 48;
    panel.addWidget('org.kde.plasma.kickoff');
    panel.addWidget('org.kde.plasma.icontasks');
    panel.addWidget('org.kde.plasma.systemtray');
    panel.addWidget('org.kde.plasma.digitalclock');
}
JS
}
fi
