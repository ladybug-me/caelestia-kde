// One line of install output, classified once when it is read rather than on every frame.
//
// The steps already label their own output (`[INFO]`, `[OK]`, `[WARN]`, `[SKIP]`, `[ERR]`,
// `[FATAL]`), so the view does not have to guess what a line means - it only has to carry the
// meaning through to the screen as a glyph, a color and a readable body.

use ratatui::style::Style;

use crate::glyphs::Glyphs;
use crate::steps::Status;
use crate::theme::Theme;

/// The longest line kept for display. A step that prints a whole file has nothing to say in one
/// row, and the pane would truncate it anyway.
const MAX_LINE: usize = 4096;

#[derive(Copy, Clone, Debug, PartialEq, Eq)]
pub enum Kind {
    Info,
    Ok,
    Warn,
    Error,
    Skip,
    Heading,
    Plain,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct LogLine {
    pub kind: Kind,
    /// How far the line was indented where it was printed, so nested output keeps its shape.
    pub depth: u8,
    pub text: String,
}

impl LogLine {
    pub fn parse(raw: &str) -> Self {
        let cleaned = sanitise(raw);
        let depth = indent(&cleaned);
        let trimmed = cleaned.trim_start();

        if is_rule(trimmed) {
            return Self {
                kind: Kind::Heading,
                depth: 0,
                text: trimmed.to_string(),
            };
        }

        let (kind, text) = split_marker(trimmed);
        Self {
            kind,
            depth,
            text: cap(text.trim_end().to_string()),
        }
    }

    /// Worth interrupting for: warnings and errors are what a watching user is waiting to see.
    pub fn is_loud(&self) -> bool {
        matches!(self.kind, Kind::Warn | Kind::Error)
    }

    pub fn status(&self) -> Option<Status> {
        match self.kind {
            Kind::Ok => Some(Status::Ok),
            Kind::Warn => Some(Status::Warn),
            Kind::Error => Some(Status::Failed),
            Kind::Skip => Some(Status::Skipped),
            Kind::Info | Kind::Heading | Kind::Plain => None,
        }
    }

    pub fn glyph(&self, glyphs: Glyphs) -> Option<&'static str> {
        match self.status() {
            Some(status) => Some(glyphs.status(status)),
            None => None,
        }
    }

    pub fn style(&self, theme: &Theme) -> Style {
        match self.kind {
            Kind::Ok => theme.ok_text(),
            Kind::Warn => theme.warn_text(),
            Kind::Error => theme.error_text(),
            Kind::Skip | Kind::Info => theme.muted(),
            Kind::Heading => theme.rule(),
            Kind::Plain => theme.body(),
        }
    }
}

/// `  [WARN]  slow mirror` becomes `Warn` with `slow mirror` left to show. A line the steps did
/// not label keeps its text exactly as printed.
fn split_marker(line: &str) -> (Kind, &str) {
    let Some(rest) = line.strip_prefix('[') else {
        return (Kind::Plain, line);
    };
    let Some(end) = rest.find(']') else {
        return (Kind::Plain, line);
    };
    let kind = match rest[..end].trim().to_ascii_uppercase().as_str() {
        "INFO" => Kind::Info,
        "OK" => Kind::Ok,
        "WARN" | "WARNING" => Kind::Warn,
        "ERR" | "ERROR" | "FATAL" => Kind::Error,
        "SKIP" => Kind::Skip,
        _ => return (Kind::Plain, line),
    };
    (kind, rest[end + 1..].trim_start())
}

/// A line that is nothing but a rule, which the steps print to open a section.
fn is_rule(line: &str) -> bool {
    let mut characters = line.chars();
    let Some(first) = characters.next() else {
        return false;
    };
    matches!(first, '-' | '=' | '#' | '_')
        && line.chars().count() >= 3
        && characters.all(|character| character == first)
}

fn indent(line: &str) -> u8 {
    match line
        .chars()
        .take_while(|character| *character == ' ')
        .count()
    {
        0 => 0,
        1..=4 => 1,
        _ => 2,
    }
}

/// The log is a recording of what a program printed, some of which is not printable: control
/// characters would land in the middle of a row and shift everything after them.
fn sanitise(raw: &str) -> String {
    let mut out = String::with_capacity(raw.len());
    for character in raw.chars() {
        match character {
            '\t' => out.push(' '),
            control if control.is_control() => {}
            other => out.push(other),
        }
    }
    out
}

fn cap(text: String) -> String {
    if text.len() <= MAX_LINE {
        return text;
    }
    let mut end = MAX_LINE;
    while !text.is_char_boundary(end) {
        end -= 1;
    }
    text[..end].to_string()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_markers_the_steps_print_become_kinds() {
        for (raw, kind) in [
            ("  [INFO]  Deploying configs", Kind::Info),
            ("  [OK]    Config deployment complete.", Kind::Ok),
            ("  [WARN]  slow mirror", Kind::Warn),
            ("  [ERR]   Build failed.", Kind::Error),
            ("  [SKIP]  Thunar integration disabled", Kind::Skip),
            (" [WARN] Missing optional file: zed", Kind::Warn),
            ("[OK] KDE extra apps step complete.", Kind::Ok),
            ("  [FATAL] Line ending normalization failed.", Kind::Error),
        ] {
            let line = LogLine::parse(raw);
            assert_eq!(line.kind, kind, "{raw}");
        }
    }

    #[test]
    fn an_unlabelled_line_keeps_every_character_it_was_printed_with() {
        let line = LogLine::parse("   Setting up Zed...");
        assert_eq!(line.kind, Kind::Plain);
        assert_eq!(line.text, "Setting up Zed...");
        assert_eq!(line.depth, 1);

        let nested = LogLine::parse("      deep detail");
        assert_eq!(nested.depth, 2);

        let flush = LogLine::parse("no indent");
        assert_eq!(flush.depth, 0);
    }

    #[test]
    fn a_marker_is_removed_from_the_text_because_the_glyph_replaces_it() {
        let line = LogLine::parse("  [WARN]  slow mirror");
        assert_eq!(line.text, "slow mirror");
        assert_eq!(line.depth, 1);
    }

    #[test]
    fn a_bracket_the_steps_meant_literally_is_not_a_marker() {
        let line = LogLine::parse("  [0.5s] took a while");
        assert_eq!(line.kind, Kind::Plain);
        assert_eq!(line.text, "[0.5s] took a while");

        let unterminated = LogLine::parse("  [WARN slow mirror");
        assert_eq!(unterminated.kind, Kind::Plain);
    }

    #[test]
    fn a_rule_is_a_heading_rather_than_a_line_of_noise() {
        assert_eq!(
            LogLine::parse("-------------------------------------------------------------").kind,
            Kind::Heading
        );
        assert_eq!(LogLine::parse("=====").kind, Kind::Heading);
        assert_eq!(LogLine::parse("--").kind, Kind::Plain);
        assert_eq!(LogLine::parse("- item").kind, Kind::Plain);
    }

    #[test]
    fn control_characters_cannot_shift_a_row() {
        let line = LogLine::parse("  [INFO]\tprogress\u{7} done");
        assert_eq!(line.text, "progress done");
    }

    #[test]
    fn an_absurdly_long_line_is_capped_without_splitting_a_character() {
        let raw = "é".repeat(MAX_LINE);
        let line = LogLine::parse(&raw);
        assert!(line.text.len() <= MAX_LINE);
        assert!(line.text.chars().all(|character| character == 'é'));
    }

    #[test]
    fn only_warnings_and_errors_are_worth_interrupting_for() {
        assert!(LogLine::parse("  [WARN] x").is_loud());
        assert!(LogLine::parse("  [ERR] x").is_loud());
        assert!(!LogLine::parse("  [OK] x").is_loud());
        assert!(!LogLine::parse("  [INFO] x").is_loud());
        assert!(!LogLine::parse("plain").is_loud());
    }
}
