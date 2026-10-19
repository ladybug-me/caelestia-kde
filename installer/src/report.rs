use ratatui::style::Color;

use crate::env::Env;
use crate::glyphs::Glyphs;
use crate::theme::{Depth, Role, Theme};

const MAX_WIDTH: usize = 96;
const MIN_WIDTH: usize = 48;

pub struct Report {
    theme: Theme,
    glyphs: Glyphs,
    width: usize,
}

impl Report {
    pub fn for_terminal() -> Self {
        let env = Env::capture();
        let width = crossterm::terminal::size()
            .map(|(columns, _)| columns as usize)
            .unwrap_or(80)
            .clamp(MIN_WIDTH, MAX_WIDTH);
        Self::with(Theme::resolve(&env), Glyphs::resolve(&env), width)
    }

    fn with(theme: Theme, glyphs: Glyphs, width: usize) -> Self {
        Self {
            theme,
            glyphs,
            width,
        }
    }

    pub fn panel(&self, title: &str, right: &str, rows: &[Row], notes: &[String]) {
        println!("{}", self.panel_text(title, right, rows, notes));
    }

    pub fn section(&self, title: &str) {
        println!();
        println!("{}", self.paint(Role::Rule, &self.rule()));
        println!("{}", self.paint(Role::Accent, &format!("  {title}")));
        println!("{}", self.paint(Role::Rule, &self.rule()));
    }

    fn panel_text(&self, title: &str, right: &str, rows: &[Row], notes: &[String]) -> String {
        let (top_left, top_right, bottom_left, bottom_right, horizontal, vertical) = self.corners();
        let inner = self.width.saturating_sub(2);
        let mut out = String::new();

        let left = format!(" caelestia · {title} ");
        let right = format!(" {right} ");
        let fill = inner.saturating_sub(left.chars().count() + right.chars().count());
        out.push_str(&self.paint(Role::Accent, top_left));
        out.push_str(&self.paint(Role::Accent, &left));
        out.push_str(&self.paint(Role::Rule, &horizontal.to_string().repeat(fill)));
        out.push_str(&self.paint(Role::Muted, &right));
        out.push_str(&self.paint(Role::Accent, top_right));
        out.push('\n');

        out.push_str(&self.blank_row(vertical, inner));

        let label_width = rows
            .iter()
            .map(|row| row.label.chars().count())
            .max()
            .unwrap_or(0)
            .min(14);
        for row in rows {
            let value_width = inner.saturating_sub(label_width + 3);
            let value = clip(&row.value, value_width);
            let padding = label_width.saturating_sub(row.label.chars().count());
            out.push_str(&self.row(
                vertical,
                inner,
                &format!(
                    " {}{}  {}",
                    self.paint(Role::Muted, &row.label),
                    " ".repeat(padding),
                    self.paint(row.role, &value)
                ),
            ));
        }

        if !notes.is_empty() {
            out.push_str(&self.blank_row(vertical, inner));
            for note in notes {
                for line in wrap(note, inner.saturating_sub(1)) {
                    out.push_str(&self.row(vertical, inner, &format!(" {}", line)));
                }
            }
        }

        out.push_str(&self.blank_row(vertical, inner));
        out.push_str(&self.paint(Role::Accent, bottom_left));
        out.push_str(&self.paint(Role::Rule, &horizontal.to_string().repeat(inner)));
        out.push_str(&self.paint(Role::Accent, bottom_right));
        out.push('\n');
        out
    }
}

pub struct Row {
    pub label: String,
    pub value: String,
    pub role: Role,
}

impl Row {
    pub fn new(label: impl Into<String>, value: impl Into<String>, role: Role) -> Self {
        Self {
            label: label.into(),
            value: value.into(),
            role,
        }
    }
}

impl Report {
    fn corners(
        &self,
    ) -> (
        &'static str,
        &'static str,
        &'static str,
        &'static str,
        char,
        char,
    ) {
        if self.glyphs.is_unicode() {
            (
                "\u{256d}", "\u{256e}", "\u{2570}", "\u{256f}", '\u{2500}', '\u{2502}',
            )
        } else {
            ("+", "+", "+", "+", '-', '|')
        }
    }

    fn rule(&self) -> String {
        let (_, _, _, _, horizontal, _) = self.corners();
        horizontal.to_string().repeat(self.width.saturating_sub(2))
    }

    fn row(&self, vertical: char, inner: usize, content: &str) -> String {
        let visible = visible_width(content);
        let padding = inner.saturating_sub(visible);
        format!(
            "{}{}{}{}\n",
            self.paint(Role::Accent, &vertical.to_string()),
            content,
            " ".repeat(padding),
            self.paint(Role::Accent, &format!("{vertical}"))
        )
    }

    fn blank_row(&self, vertical: char, inner: usize) -> String {
        self.row(vertical, inner, &" ".repeat(inner))
    }

    fn paint(&self, role: Role, text: &str) -> String {
        if self.theme.depth == Depth::Mono {
            return text.to_string();
        }
        let mut style = format!("\x1b[{}m", escape(self.theme.color(role)));
        if matches!(role, Role::Accent) {
            style.push_str("\x1b[1m");
        }
        format!("{style}{text}\x1b[0m")
    }
}

fn escape(color: Color) -> String {
    match color {
        Color::Reset => "39".to_string(),
        Color::Black => "30".to_string(),
        Color::Red => "31".to_string(),
        Color::Green => "32".to_string(),
        Color::Yellow => "33".to_string(),
        Color::Blue => "34".to_string(),
        Color::Magenta => "35".to_string(),
        Color::Cyan => "36".to_string(),
        Color::Gray => "37".to_string(),
        Color::DarkGray => "90".to_string(),
        Color::LightRed => "91".to_string(),
        Color::LightGreen => "92".to_string(),
        Color::LightYellow => "93".to_string(),
        Color::LightBlue => "94".to_string(),
        Color::LightMagenta => "95".to_string(),
        Color::LightCyan => "96".to_string(),
        Color::White => "97".to_string(),
        Color::Rgb(r, g, b) => format!("38;2;{r};{g};{b}"),
        Color::Indexed(index) => format!("38;5;{index}"),
    }
}

fn visible_width(text: &str) -> usize {
    let mut width = 0;
    let mut in_escape = false;
    for character in text.chars() {
        match character {
            '\x1b' => in_escape = true,
            'm' if in_escape => in_escape = false,
            _ if in_escape => {}
            _ => width += 1,
        }
    }
    width
}

fn clip(text: &str, width: usize) -> String {
    if text.chars().count() <= width {
        return text.to_string();
    }
    text.chars()
        .take(width.saturating_sub(1))
        .collect::<String>()
        + "…"
}

fn wrap(text: &str, width: usize) -> Vec<String> {
    crate::ui::wrap(text, width, 16)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::env::Env;
    use crate::theme::Theme;

    fn plain(width: usize) -> Report {
        Report::with(
            Theme::resolve(&Env::default()),
            Glyphs::resolve(&Env::default()),
            width,
        )
    }

    #[test]
    fn a_panel_says_what_it_is_about_and_what_it_found() {
        let report = plain(72);
        let text = report.panel_text(
            "update",
            "main",
            &[
                Row::new("installed", "v2.6.1  a1b2c3d", Role::Foreground),
                Row::new("available", "v2.7.0  d4e5f6a", Role::Ok),
            ],
            &["This replaces the deployed configuration and rebuilds the shell.".to_string()],
        );
        assert!(text.contains("caelestia · update"), "{text}");
        assert!(text.contains("installed"), "{text}");
        assert!(text.contains("v2.6.1"), "{text}");
        assert!(text.contains("v2.7.0"), "{text}");
        assert!(text.contains("rebuilds the shell"), "{text}");
    }

    #[test]
    fn every_row_of_a_panel_is_the_same_width() {
        let report = plain(72);
        let text = report.panel_text(
            "uninstall",
            "Arch-based Linux",
            &[Row::new(
                "shell",
                "~/.config/quickshell/caelestia",
                Role::Foreground,
            )],
            &[],
        );
        let widths: Vec<usize> = text.lines().map(visible_width).collect();
        assert!(
            widths.windows(2).all(|pair| pair[0] == pair[1]),
            "the frame is ragged: {widths:?}\n{text}"
        );
    }

    #[test]
    fn a_terminal_without_colour_is_given_none() {
        let env = Env {
            term: Some("dumb".to_string()),
            ..Env::default()
        };
        let report = Report::with(Theme::resolve(&env), Glyphs::resolve(&env), MIN_WIDTH);
        let text = report.panel_text(
            "update",
            "",
            &[Row::new("installed", "v1", Role::Foreground)],
            &[],
        );
        assert!(
            !text.contains('\x1b'),
            "a dumb terminal got escapes: {text}"
        );
        assert!(text.contains("installed"), "{text}");
    }
}
