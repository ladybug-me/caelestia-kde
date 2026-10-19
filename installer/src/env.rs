use std::env;

#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct Env {
    pub term: Option<String>,
    pub colorterm: Option<String>,
    pub no_color: bool,
    pub colorfgbg: Option<String>,
    pub locale: Option<String>,
    pub theme: Option<String>,
    pub glyphs: Option<String>,
    pub no_animation: bool,
}

impl Env {
    pub fn capture() -> Self {
        Self {
            term: variable("TERM"),
            colorterm: variable("COLORTERM"),
            no_color: variable("NO_COLOR").is_some(),
            colorfgbg: variable("COLORFGBG"),
            locale: variable("LC_ALL")
                .or_else(|| variable("LC_CTYPE"))
                .or_else(|| variable("LANG")),
            theme: variable("CAELESTIA_TUI_THEME"),
            glyphs: variable("CAELESTIA_TUI_GLYPHS"),
            no_animation: flag("CAELESTIA_TUI_NO_ANIMATION"),
        }
    }

    pub fn is_dumb(&self) -> bool {
        matches!(self.term.as_deref(), Some("dumb"))
    }

    pub fn is_console(&self) -> bool {
        matches!(self.term.as_deref(), Some("linux"))
    }

    pub fn has_truecolor(&self) -> bool {
        self.colorterm.as_deref().is_some_and(|value| {
            value.eq_ignore_ascii_case("truecolor") || value.eq_ignore_ascii_case("24bit")
        })
    }

    pub fn has_256_colors(&self) -> bool {
        self.term
            .as_deref()
            .is_some_and(|value| value.contains("256"))
    }

    pub fn background_index(&self) -> Option<u8> {
        self.colorfgbg
            .as_deref()?
            .rsplit(';')
            .next()?
            .trim()
            .parse()
            .ok()
    }

    pub fn animates(&self) -> bool {
        !self.no_animation && !self.is_dumb() && !self.no_color
    }
}

fn variable(name: &str) -> Option<String> {
    env::var(name)
        .ok()
        .map(|value| value.trim().to_string())
        .filter(|value| !value.is_empty())
}

fn flag(name: &str) -> bool {
    variable(name).is_some_and(|value| value != "0")
}

#[cfg(test)]
mod tests {
    use super::*;

    fn env(term: &str) -> Env {
        Env {
            term: Some(term.to_string()),
            ..Env::default()
        }
    }

    #[test]
    fn a_dumb_terminal_and_a_console_are_recognised() {
        assert!(env("dumb").is_dumb());
        assert!(!env("dumb").is_console());
        assert!(env("linux").is_console());
        assert!(!env("xterm-256color").is_dumb());
    }

    #[test]
    fn truecolor_is_read_from_colorterm_not_from_hope() {
        let mut subject = env("xterm-256color");
        assert!(!subject.has_truecolor());
        assert!(subject.has_256_colors());

        subject.colorterm = Some("24BIT".to_string());
        assert!(subject.has_truecolor());
    }

    #[test]
    fn the_background_index_survives_a_malformed_colorfgbg() {
        let mut subject = env("xterm");
        subject.colorfgbg = Some("0;15".to_string());
        assert_eq!(subject.background_index(), Some(15));

        subject.colorfgbg = Some("15;0".to_string());
        assert_eq!(subject.background_index(), Some(0));

        subject.colorfgbg = Some("nonsense".to_string());
        assert_eq!(subject.background_index(), None);

        subject.colorfgbg = None;
        assert_eq!(subject.background_index(), None);
    }

    #[test]
    fn motion_is_off_where_it_cannot_be_seen_or_is_not_wanted() {
        let mut subject = env("xterm-kitty");
        subject.colorterm = Some("truecolor".to_string());
        assert!(subject.animates());

        subject.no_color = true;
        assert!(!subject.animates());

        let mut still = env("xterm-kitty");
        still.no_animation = true;
        assert!(!still.animates());

        assert!(!env("dumb").animates());
    }
}
