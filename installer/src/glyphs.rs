use ratatui::symbols::border;

use crate::env::Env;
use crate::steps::Status;

#[derive(Copy, Clone, Debug, PartialEq, Eq)]
pub enum Set {
    Unicode,
    Ascii,
}

const UNICODE_CELL: usize = 1;
const ASCII_CELL: usize = 3;

#[derive(Copy, Clone, Debug, PartialEq, Eq)]
pub struct Glyphs {
    set: Set,
}

impl Glyphs {
    pub fn resolve(env: &Env) -> Self {
        Self { set: pick(env) }
    }

    pub fn is_unicode(self) -> bool {
        matches!(self.set, Set::Unicode)
    }

    pub fn status_cell(self) -> usize {
        match self.set {
            Set::Unicode => UNICODE_CELL,
            Set::Ascii => ASCII_CELL,
        }
    }

    pub fn status(self, status: Status) -> &'static str {
        match (self.set, status) {
            (Set::Unicode, Status::Pending) => "·",
            (Set::Unicode, Status::Running) => "◐",
            (Set::Unicode, Status::Ok) => "✓",
            (Set::Unicode, Status::Warn) => "!",
            (Set::Unicode, Status::Failed) => "✗",
            (Set::Unicode, Status::Skipped) => "–",
            (Set::Unicode, Status::Ignored) => "⊘",
            (Set::Ascii, Status::Pending) => "[ ]",
            (Set::Ascii, Status::Running) => "[>]",
            (Set::Ascii, Status::Ok) => "[+]",
            (Set::Ascii, Status::Warn) => "[!]",
            (Set::Ascii, Status::Failed) => "[X]",
            (Set::Ascii, Status::Skipped) => "[-]",
            (Set::Ascii, Status::Ignored) => "[i]",
        }
    }

    pub fn spinner(self, frame: usize) -> &'static str {
        const UNICODE: [&str; 8] = ["⣾", "⣽", "⣻", "⢿", "⡿", "⣟", "⣯", "⣷"];
        const ASCII: [&str; 4] = ["|", "/", "-", "\\"];
        let frames: &[&str] = match self.set {
            Set::Unicode => &UNICODE,
            Set::Ascii => &ASCII,
        };
        frames[frame % frames.len()]
    }

    pub fn cursor(self) -> &'static str {
        match self.set {
            Set::Unicode => "▶",
            Set::Ascii => ">",
        }
    }

    pub fn tick(self) -> &'static str {
        match self.set {
            Set::Unicode => "✓",
            Set::Ascii => "+",
        }
    }

    pub fn circle(self) -> &'static str {
        match self.set {
            Set::Unicode => "○",
            Set::Ascii => "o",
        }
    }

    pub fn cross(self) -> &'static str {
        match self.set {
            Set::Unicode => "✗",
            Set::Ascii => "x",
        }
    }

    pub fn submenu(self) -> &'static str {
        match self.set {
            Set::Unicode => "▸",
            Set::Ascii => "+",
        }
    }

    pub fn open(self) -> &'static str {
        match self.set {
            Set::Unicode => "‹",
            Set::Ascii => "<",
        }
    }

    pub fn close(self) -> &'static str {
        match self.set {
            Set::Unicode => "›",
            Set::Ascii => ">",
        }
    }

    pub fn changed(self) -> &'static str {
        match self.set {
            Set::Unicode => "•",
            Set::Ascii => "*",
        }
    }

    pub fn mask(self) -> &'static str {
        match self.set {
            Set::Unicode => "•",
            Set::Ascii => "*",
        }
    }

    pub fn ellipsis(self) -> &'static str {
        match self.set {
            Set::Unicode => "…",
            Set::Ascii => "..",
        }
    }

    pub fn bar_full(self) -> char {
        match self.set {
            Set::Unicode => '█',
            Set::Ascii => '#',
        }
    }

    pub fn bar_empty(self) -> char {
        match self.set {
            Set::Unicode => '░',
            Set::Ascii => '-',
        }
    }

    pub fn track(self) -> char {
        match self.set {
            Set::Unicode => '│',
            Set::Ascii => '|',
        }
    }

    pub fn thumb(self) -> char {
        match self.set {
            Set::Unicode => '█',
            Set::Ascii => '#',
        }
    }

    pub fn mark(self) -> char {
        match self.set {
            Set::Unicode => '•',
            Set::Ascii => 'o',
        }
    }

    pub fn border(self) -> border::Set<'static> {
        match self.set {
            Set::Unicode => border::PLAIN,
            Set::Ascii => border::Set {
                top_left: "+",
                top_right: "+",
                bottom_left: "+",
                bottom_right: "+",
                vertical_left: "|",
                vertical_right: "|",
                horizontal_top: "-",
                horizontal_bottom: "-",
            },
        }
    }

    pub fn frame_border(self) -> border::Set<'static> {
        match self.set {
            Set::Unicode => border::ROUNDED,
            Set::Ascii => self.border(),
        }
    }

    pub fn enter(self) -> &'static str {
        match self.set {
            Set::Unicode => "⏎",
            Set::Ascii => "Enter",
        }
    }

    pub fn escape(self) -> &'static str {
        match self.set {
            Set::Unicode => "esc",
            Set::Ascii => "Esc",
        }
    }

    pub fn up_down(self) -> &'static str {
        match self.set {
            Set::Unicode => "↑↓",
            Set::Ascii => "Up/Down",
        }
    }

    pub fn left_right(self) -> &'static str {
        match self.set {
            Set::Unicode => "←→",
            Set::Ascii => "Left/Right",
        }
    }
}

fn pick(env: &Env) -> Set {
    match env.glyphs.as_deref() {
        Some("ascii") | Some("plain") | Some("ansi") => Set::Ascii,
        Some("unicode") | Some("utf8") | Some("utf-8") => Set::Unicode,
        _ => detect(env),
    }
}

fn detect(env: &Env) -> Set {
    if env.is_dumb() || env.is_console() {
        return Set::Ascii;
    }
    match env.locale.as_deref() {
        Some(locale) if !locale.to_lowercase().contains("utf") => Set::Ascii,
        _ => Set::Unicode,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::env::Env;
    use ratatui::text::Span;

    fn with_glyphs(value: &str) -> Env {
        Env {
            term: Some("xterm-kitty".to_string()),
            glyphs: Some(value.to_string()),
            ..Env::default()
        }
    }

    fn ascii() -> Glyphs {
        Glyphs::resolve(&with_glyphs("ascii"))
    }

    fn unicode() -> Glyphs {
        Glyphs::resolve(&with_glyphs("unicode"))
    }

    fn cursor_of(env: &Env) -> &'static str {
        Glyphs::resolve(env).cursor()
    }

    #[test]
    fn a_dumb_terminal_a_console_and_a_c_locale_all_fall_back_to_ascii() {
        let dumb = Env {
            term: Some("dumb".to_string()),
            ..Env::default()
        };
        assert_eq!(cursor_of(&dumb), ">");

        let console = Env {
            term: Some("linux".to_string()),
            ..Env::default()
        };
        assert_eq!(cursor_of(&console), ">");

        let latin = Env {
            term: Some("xterm".to_string()),
            locale: Some("en_GB.ISO-8859-1".to_string()),
            ..Env::default()
        };
        assert_eq!(cursor_of(&latin), ">");

        let utf8 = Env {
            term: Some("xterm-256color".to_string()),
            locale: Some("en_GB.UTF-8".to_string()),
            ..Env::default()
        };
        assert_eq!(cursor_of(&utf8), "▶");
    }

    #[test]
    fn an_explicit_choice_beats_the_detection() {
        let forced_unicode = Env {
            term: Some("dumb".to_string()),
            glyphs: Some("unicode".to_string()),
            ..Env::default()
        };
        assert_eq!(cursor_of(&forced_unicode), "▶");

        let forced_ascii = Env {
            term: Some("xterm-kitty".to_string()),
            locale: Some("en_GB.UTF-8".to_string()),
            glyphs: Some("ascii".to_string()),
            ..Env::default()
        };
        assert_eq!(cursor_of(&forced_ascii), ">");
    }

    #[test]
    fn every_status_has_a_glyph() {
        for status in Status::ALL {
            assert!(!unicode().status(status).is_empty());
            assert!(!ascii().status(status).is_empty());
        }
    }

    #[test]
    fn distinct_states_never_share_a_glyph() {
        let mut seen = std::collections::BTreeSet::new();
        for status in Status::ALL {
            assert!(seen.insert(unicode().status(status)), "{status:?}");
            assert!(seen.insert(ascii().status(status)), "{status:?}");
        }
    }

    #[test]
    fn the_status_cell_matches_the_glyphs_it_holds() {
        for status in Status::ALL {
            assert_eq!(Span::from(unicode().status(status)).width(), UNICODE_CELL);
            assert_eq!(Span::from(ascii().status(status)).width(), ASCII_CELL);
        }
    }

    #[test]
    fn the_single_cell_glyphs_are_single_cell() {
        for glyphs in [unicode(), ascii()] {
            for glyph in [
                glyphs.cursor(),
                glyphs.submenu(),
                glyphs.open(),
                glyphs.close(),
                glyphs.changed(),
            ] {
                assert_eq!(Span::from(glyph).width(), 1, "{glyph:?}");
            }
            for frame in 0..4 {
                assert_eq!(Span::from(glyphs.spinner(frame)).width(), 1);
            }
        }
    }

    #[test]
    fn the_spinner_does_not_walk_off_the_end_of_its_frames() {
        for frame in [0, 3, 4, 7, 41] {
            assert!(!unicode().spinner(frame).is_empty());
            assert!(!ascii().spinner(frame).is_empty());
        }
    }
}
