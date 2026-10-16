// The glyph vocabulary: one set for terminals that can be trusted with Unicode, one for the
// rest. Everything the TUI draws comes from here, so a fallback terminal loses the decoration
// but never a meaning, and a glyph can never be changed in one screen only.
//
// Every glyph that sits in a column has a fixed cell width, declared next to the set and
// checked by the tests, so swapping a glyph cannot silently break the grid.

use ratatui::symbols::border;

use crate::env::Env;
use crate::steps::Status;

#[derive(Copy, Clone, Debug, PartialEq, Eq)]
pub enum Set {
    Unicode,
    Ascii,
}

/// One column of status glyphs, wide enough for the widest of them.
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

    /// The width every status glyph occupies, so names line up whatever the state is.
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

    /// The glyph that marks the step being worked on, one frame at a time.
    pub fn spinner(self, frame: usize) -> &'static str {
        // The frames the reference installer uses (charmbracelet's `Dot`): eight braille cells,
        // which carry far more ink than a quarter-circle and read as motion from across a desk
        // rather than as a punctuation mark.
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
            Set::Unicode => "❯",
            Set::Ascii => ">",
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

    pub fn mark(self) -> &'static str {
        match self.set {
            Set::Unicode => "·",
            Set::Ascii => "-",
        }
    }

    /// What a secret looks like: never the secret.
    pub fn mask(self) -> &'static str {
        match self.set {
            Set::Unicode => "•",
            Set::Ascii => "*",
        }
    }

    /// The marker a clipped string ends with.
    pub fn ellipsis(self) -> &'static str {
        match self.set {
            Set::Unicode => "…",
            Set::Ascii => "..",
        }
    }

    pub fn rule(self) -> char {
        match self.set {
            Set::Unicode => '─',
            Set::Ascii => '-',
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

    /// The border the screen frame is drawn with: rounded where the terminal has the corners.
    pub fn frame_border(self) -> border::Set<'static> {
        match self.set {
            Set::Unicode => border::ROUNDED,
            Set::Ascii => self.border(),
        }
    }

    // Key names, which are words rather than symbols: they are only abbreviated when the
    // terminal can draw the abbreviation.

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

/// The state, spelled out. Color is the third channel, the label is the one that always works.
pub fn status_label(status: Status) -> &'static str {
    match status {
        Status::Pending => "PENDING",
        Status::Running => "RUNNING",
        Status::Ok => "OK",
        Status::Warn => "WARNING",
        Status::Failed => "FAILED",
        Status::Skipped => "SKIPPED",
        Status::Ignored => "IGNORED",
    }
}

/// The width the widest label needs, so labels sit in a column of their own.
pub const LABEL_CELL: usize = 7;

fn pick(env: &Env) -> Set {
    match env.glyphs.as_deref() {
        Some("ascii") | Some("plain") | Some("ansi") => Set::Ascii,
        Some("unicode") | Some("utf8") | Some("utf-8") => Set::Unicode,
        _ => detect(env),
    }
}

// A terminal that cannot be trusted with Unicode: it said so, or its locale is not UTF-8 and
// something did say what it is.
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

    /// The cursor is the quickest way to ask a `Glyphs` which set it resolved to.
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
        assert_eq!(cursor_of(&utf8), "❯");
    }

    #[test]
    fn an_explicit_choice_beats_the_detection() {
        let forced_unicode = Env {
            term: Some("dumb".to_string()),
            glyphs: Some("unicode".to_string()),
            ..Env::default()
        };
        assert_eq!(cursor_of(&forced_unicode), "❯");

        let forced_ascii = Env {
            term: Some("xterm-kitty".to_string()),
            locale: Some("en_GB.UTF-8".to_string()),
            glyphs: Some("ascii".to_string()),
            ..Env::default()
        };
        assert_eq!(cursor_of(&forced_ascii), ">");
    }

    #[test]
    fn every_status_has_a_glyph_and_a_label() {
        for status in Status::ALL {
            assert!(!unicode().status(status).is_empty());
            assert!(!ascii().status(status).is_empty());
            assert!(!status_label(status).is_empty());
            assert!(
                status_label(status).len() <= LABEL_CELL,
                "{status:?} does not fit its column"
            );
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
                glyphs.mark(),
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
