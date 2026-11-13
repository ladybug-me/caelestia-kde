pragma Singleton

import QtQuick
import Quickshell
import Caelestia.Config

Singleton {
    function familyForText(text: string, fallback: string): string {
        const selected = GlobalConfig.services.lyricsArabicFont;
        if (selected && /[\u0600-\u06ff\u0750-\u077f\u08a0-\u08ff\ufb50-\ufdff\ufe70-\ufeff]/.test(text))
            return selected;
        return fallback || Tokens.font.body.medium.family;
    }
}
