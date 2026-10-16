// The visual language: roles rather than colors, and a palette per terminal capability. Every
// role used for text clears 4.5:1 against its own surface; the tests hold that line.

use ratatui::style::{Color, Modifier, Style};

use crate::env::Env;
use crate::steps::Status;

pub const NAME: &str = "caelestia";
pub const TAGLINE: &str = "A Material You desktop for KDE Plasma 6";
pub const AUTHOR: &str = "By @ladybug-me";
pub const CO_AUTHOR: &str = "Co-maintainer: 0xSolanaceae";

/// The brand mark, drawn only where the whole of it fits. Full-cell blocks and box characters,
/// not the `_`, `|` and `/` of line art, which leave gaps wherever a font does not join them.
pub const SPLASH: [&str; 6] = [
    " ██████╗  █████╗  ███████╗ ██╗      ███████╗ ███████╗ ████████╗ ██╗  █████╗ ",
    "██╔════╝ ██╔══██╗ ██╔════╝ ██║      ██╔════╝ ██╔════╝ ╚══██╔══╝ ██║ ██╔══██╗",
    "██║      ███████║ █████╗   ██║      █████╗   ███████╗    ██║    ██║ ███████║",
    "██║      ██╔══██║ ██╔══╝   ██║      ██╔══╝   ╚════██║    ██║    ██║ ██╔══██║",
    "╚██████╗ ██║  ██║ ███████╗ ███████╗ ███████╗ ███████║    ██║    ██║ ██║  ██║",
    " ╚═════╝ ╚═╝  ╚═╝ ╚══════╝ ╚══════╝ ╚══════╝ ╚══════╝    ╚═╝    ╚═╝ ╚═╝  ╚═╝",
];

#[derive(Copy, Clone, Debug, PartialEq, Eq)]
pub enum Mode {
    Dark,
    Light,
}

impl Mode {
    pub fn parse(value: &str) -> Option<Self> {
        match value.trim().to_ascii_lowercase().as_str() {
            "dark" => Some(Mode::Dark),
            "light" => Some(Mode::Light),
            _ => None,
        }
    }

    pub fn other(self) -> Self {
        match self {
            Mode::Dark => Mode::Light,
            Mode::Light => Mode::Dark,
        }
    }

    pub fn name(self) -> &'static str {
        match self {
            Mode::Dark => "dark",
            Mode::Light => "light",
        }
    }
}

/// What the terminal can actually render.
#[derive(Copy, Clone, Debug, PartialEq, Eq)]
pub enum Depth {
    True,
    Indexed,
    Ansi,
    Mono,
}

#[derive(Copy, Clone, Debug, PartialEq, Eq)]
pub enum Role {
    Surface,
    /// A block that stands off the surface, so a group of rows reads as one thing.
    Panel,
    /// Text drawn on a filled accent: the footer bar, and the row the cursor is on.
    OnAccent,
    Foreground,
    Muted,
    Rule,
    Accent,
    Ok,
    Warn,
    Error,
    Ignored,
    Skipped,
}

#[derive(Copy, Clone, Debug, PartialEq, Eq)]
struct Rgb(u8, u8, u8);

#[derive(Copy, Clone, Debug, PartialEq, Eq)]
struct Roles {
    surface: Rgb,
    panel: Rgb,
    on_accent: Rgb,
    foreground: Rgb,
    muted: Rgb,
    rule: Rgb,
    accent: Rgb,
    ok: Rgb,
    warn: Rgb,
    error: Rgb,
    ignored: Rgb,
    skipped: Rgb,
}

impl Roles {
    fn get(&self, role: Role) -> Rgb {
        match role {
            Role::Surface => self.surface,
            Role::Panel => self.panel,
            Role::OnAccent => self.on_accent,
            Role::Foreground => self.foreground,
            Role::Muted => self.muted,
            Role::Rule => self.rule,
            Role::Accent => self.accent,
            Role::Ok => self.ok,
            Role::Warn => self.warn,
            Role::Error => self.error,
            Role::Ignored => self.ignored,
            Role::Skipped => self.skipped,
        }
    }
}

const DARK: Roles = Roles {
    surface: Rgb(0x0d, 0x11, 0x17),
    panel: Rgb(0x16, 0x1b, 0x22),
    on_accent: Rgb(0x0d, 0x11, 0x17),
    foreground: Rgb(0xc9, 0xd1, 0xd9),
    muted: Rgb(0x8b, 0x94, 0x9e),
    rule: Rgb(0x6e, 0x76, 0x81),
    accent: Rgb(0x58, 0xa6, 0xff),
    ok: Rgb(0x3f, 0xb9, 0x50),
    warn: Rgb(0xd2, 0x99, 0x22),
    error: Rgb(0xf8, 0x51, 0x49),
    ignored: Rgb(0xdb, 0x6d, 0x28),
    skipped: Rgb(0x7d, 0x85, 0x90),
};

const LIGHT: Roles = Roles {
    surface: Rgb(0xff, 0xff, 0xff),
    panel: Rgb(0xf6, 0xf8, 0xfa),
    on_accent: Rgb(0xff, 0xff, 0xff),
    foreground: Rgb(0x1f, 0x23, 0x28),
    muted: Rgb(0x59, 0x63, 0x6e),
    rule: Rgb(0x8c, 0x95, 0x9f),
    accent: Rgb(0x09, 0x69, 0xda),
    ok: Rgb(0x1a, 0x7f, 0x37),
    warn: Rgb(0x9a, 0x67, 0x00),
    error: Rgb(0xcf, 0x22, 0x2e),
    ignored: Rgb(0xbc, 0x4c, 0x00),
    skipped: Rgb(0x6e, 0x77, 0x81),
};

#[derive(Copy, Clone, Debug, PartialEq, Eq)]
pub struct Theme {
    pub mode: Mode,
    pub depth: Depth,
    roles: Roles,
}

impl Theme {
    pub fn resolve(env: &Env) -> Self {
        let mode = mode(env);
        Self {
            mode,
            depth: depth(env),
            roles: roles(mode),
        }
    }

    /// The `t` key: the same terminal, the other mode.
    pub fn cycle(&mut self) {
        self.mode = self.mode.other();
        self.roles = roles(self.mode);
    }

    pub fn color(&self, role: Role) -> Color {
        match self.depth {
            Depth::True => {
                let Rgb(r, g, b) = self.roles.get(role);
                Color::Rgb(r, g, b)
            }
            Depth::Indexed => Color::Indexed(indexed(self.roles.get(role))),
            Depth::Ansi => ansi(role, self.mode),
            Depth::Mono => Color::Reset,
        }
    }

    pub fn style(&self, role: Role) -> Style {
        Style::default()
            .fg(self.color(role))
            .add_modifier(modifier(role, self.depth))
    }

    /// The surface itself, so every screen starts from the brand background rather than from
    /// whatever the terminal was showing.
    pub fn surface(&self) -> Style {
        Style::default().bg(self.color(Role::Surface))
    }

    /// A raised block: the background a group of rows sits on where a border would cost two lines
    /// to say the same thing.
    pub fn panel(&self) -> Style {
        Style::default().bg(self.color(Role::Panel))
    }

    /// The one filled surface in the program: the footer bar, and the row the cursor is on. Text
    /// on it uses `OnAccent`, which swaps with the accent, so the fill carries its own text in
    /// either theme. A terminal with no color gets weight instead of a fill it cannot draw.
    pub fn bar(&self) -> Style {
        if self.depth == Depth::Mono {
            return Style::default().add_modifier(Modifier::BOLD);
        }
        Style::default()
            .bg(self.color(Role::Accent))
            .fg(self.color(Role::OnAccent))
    }

    /// The text on the filled bar, for everything that is not a key name.
    pub fn on_bar(&self) -> Style {
        if self.depth == Depth::Mono {
            return Style::default();
        }
        self.style(Role::OnAccent)
    }

    /// A key name on the filled bar: the bold half of it.
    pub fn bar_key(&self) -> Style {
        self.on_bar().add_modifier(Modifier::BOLD)
    }

    /// The frame around the whole screen, in the accent.
    pub fn frame(&self) -> Style {
        self.style(Role::Accent)
    }

    pub fn status(&self, status: Status) -> Style {
        self.style(role_of(status))
    }

    pub fn title(&self) -> Style {
        self.style(Role::Accent).add_modifier(Modifier::BOLD)
    }

    pub fn heading(&self) -> Style {
        self.style(Role::Foreground).add_modifier(Modifier::BOLD)
    }

    pub fn body(&self) -> Style {
        self.style(Role::Foreground)
    }

    pub fn muted(&self) -> Style {
        self.style(Role::Muted)
    }

    pub fn rule(&self) -> Style {
        self.style(Role::Rule)
    }

    pub fn accent(&self) -> Style {
        self.style(Role::Accent)
    }

    pub fn selected(&self) -> Style {
        self.style(Role::Accent).add_modifier(Modifier::BOLD)
    }

    pub fn error_text(&self) -> Style {
        self.style(Role::Error)
    }

    pub fn warn_text(&self) -> Style {
        self.style(Role::Warn)
    }

    pub fn ok_text(&self) -> Style {
        self.style(Role::Ok)
    }

    /// A failure the user chose to move past: still a failure, visibly quieter.
    pub fn ignored_text(&self) -> Style {
        self.style(Role::Ignored)
    }
}

fn roles(mode: Mode) -> Roles {
    match mode {
        Mode::Dark => DARK,
        Mode::Light => LIGHT,
    }
}

fn role_of(status: Status) -> Role {
    match status {
        Status::Pending => Role::Muted,
        Status::Running => Role::Accent,
        Status::Ok => Role::Ok,
        Status::Warn => Role::Warn,
        Status::Failed => Role::Error,
        Status::Skipped => Role::Skipped,
        Status::Ignored => Role::Ignored,
    }
}

/// A terminal with no color falls back to weight: loud things bold, quiet things dim.
fn modifier(role: Role, depth: Depth) -> Modifier {
    if depth != Depth::Mono {
        return Modifier::empty();
    }
    match role {
        Role::Accent | Role::Ok | Role::Warn | Role::Error | Role::Ignored | Role::OnAccent => {
            Modifier::BOLD
        }
        Role::Muted | Role::Rule | Role::Skipped => Modifier::DIM,
        Role::Surface | Role::Panel | Role::Foreground => Modifier::empty(),
    }
}

fn ansi(role: Role, mode: Mode) -> Color {
    match (mode, role) {
        // Neither a fill nor a raised panel survives a basic sixteen, so both borrow the
        // terminal's own background and the frame carries the structure instead.
        (_, Role::Surface | Role::Panel) => Color::Reset,
        // The accent is the bright blue in the dark theme and the dark one in the light, so the
        // text on it has to swap with it.
        (Mode::Dark, Role::OnAccent) => Color::Black,
        (Mode::Light, Role::OnAccent) => Color::White,
        (Mode::Dark, Role::Foreground | Role::Muted) => Color::Reset,
        (Mode::Dark, Role::Rule | Role::Skipped) => Color::DarkGray,
        (Mode::Dark, Role::Accent) => Color::Cyan,
        (Mode::Dark, Role::Ok) => Color::Green,
        (Mode::Dark, Role::Warn) => Color::Yellow,
        (Mode::Dark, Role::Error | Role::Ignored) => Color::Red,
        (Mode::Light, Role::Foreground | Role::Muted) => Color::Black,
        (Mode::Light, Role::Rule | Role::Skipped) => Color::DarkGray,
        (Mode::Light, Role::Accent) => Color::Blue,
        (Mode::Light, Role::Ok) => Color::Green,
        (Mode::Light, Role::Warn) => Color::Yellow,
        (Mode::Light, Role::Error | Role::Ignored) => Color::Red,
    }
}

/// The nearest of the 256-color palette, over the cube and the gray ramp but not the sixteen:
/// those belong to the user's theme.
fn indexed(rgb: Rgb) -> u8 {
    let Rgb(r, g, b) = rgb;
    let cube = (16 + 36 * cube_level(r) + 6 * cube_level(g) + cube_level(b)) as u8;
    let average = (u16::from(r) + u16::from(g) + u16::from(b)) / 3;
    // The ramp is 8, 18, 28, ...: the nearest step, not the one below.
    let gray_step = (average.saturating_sub(8) + 5) / 10;
    let gray = 232 + gray_step.min(23) as u8;

    if distance(rgb, from_index(cube)) <= distance(rgb, from_index(gray)) {
        cube
    } else {
        gray
    }
}

/// The cube is six levels per channel, not a linear ramp.
fn cube_level(value: u8) -> usize {
    const LEVELS: [u8; 6] = [0, 95, 135, 175, 215, 255];
    let mut best = 0;
    let mut best_distance = u8::MAX;
    for (index, level) in LEVELS.iter().enumerate() {
        let distance = value.abs_diff(*level);
        if distance < best_distance {
            best_distance = distance;
            best = index;
        }
    }
    best
}

fn from_index(index: u8) -> Rgb {
    const LEVELS: [u8; 6] = [0, 95, 135, 175, 215, 255];
    if index >= 232 {
        let level = 8 + 10 * (index - 232);
        return Rgb(level, level, level);
    }
    let cube = index - 16;
    Rgb(
        LEVELS[(cube / 36) as usize],
        LEVELS[((cube % 36) / 6) as usize],
        LEVELS[(cube % 6) as usize],
    )
}

fn distance(left: Rgb, right: Rgb) -> u32 {
    let channel = |a: u8, b: u8| {
        let difference = u32::from(a.abs_diff(b));
        difference * difference
    };
    channel(left.0, right.0) + channel(left.1, right.1) + channel(left.2, right.2)
}

fn mode(env: &Env) -> Mode {
    if let Some(explicit) = env.theme.as_deref().and_then(Mode::parse) {
        return explicit;
    }
    // `COLORFGBG` is written as foreground;background, so a bright background index is a light
    // terminal. Without it, and without being told, a dark terminal is the safe assumption.
    match env.background_index() {
        Some(index) if index >= 8 => Mode::Light,
        _ => Mode::Dark,
    }
}

fn depth(env: &Env) -> Depth {
    if env.is_dumb() || env.no_color {
        return Depth::Mono;
    }
    if env.has_truecolor() {
        Depth::True
    } else if env.has_256_colors() {
        Depth::Indexed
    } else {
        Depth::Ansi
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn env(term: &str, colorterm: Option<&str>) -> Env {
        Env {
            term: Some(term.to_string()),
            colorterm: colorterm.map(str::to_string),
            ..Env::default()
        }
    }

    fn ratio(left: Rgb, right: Rgb) -> f64 {
        fn linear(value: u8) -> f64 {
            let value = f64::from(value) / 255.0;
            if value > 0.04045 {
                ((value + 0.055) / 1.055).powf(2.4)
            } else {
                value / 12.92
            }
        }
        let luminance =
            |rgb: Rgb| 0.2126 * linear(rgb.0) + 0.7152 * linear(rgb.1) + 0.0722 * linear(rgb.2);
        let (left, right) = (luminance(left), luminance(right));
        let (high, low) = if left > right {
            (left, right)
        } else {
            (right, left)
        };
        (high + 0.05) / (low + 0.05)
    }

    #[test]
    fn text_roles_clear_four_and_a_half_to_one_in_both_modes() {
        for mode in [Mode::Dark, Mode::Light] {
            let roles = roles(mode);
            for role in [
                Role::Foreground,
                Role::Muted,
                Role::Accent,
                Role::Ok,
                Role::Warn,
                Role::Error,
                Role::Ignored,
                Role::Skipped,
            ] {
                let contrast = ratio(roles.get(role), roles.surface);
                assert!(
                    contrast >= 4.5,
                    "{mode:?} {role:?} is {contrast:.2}:1 against its surface"
                );
            }
        }
    }

    #[test]
    fn the_rule_clears_three_to_one_because_it_carries_the_structure() {
        for mode in [Mode::Dark, Mode::Light] {
            let roles = roles(mode);
            let contrast = ratio(roles.get(Role::Rule), roles.surface);
            assert!(contrast >= 3.0, "{mode:?} rule is {contrast:.2}:1");
        }
    }

    #[test]
    fn the_filled_bar_carries_its_own_text() {
        // The footer is drawn *on* the accent, so its text is measured against the accent rather
        // than against the surface the rest of the program is read on.
        for mode in [Mode::Dark, Mode::Light] {
            let roles = roles(mode);
            let contrast = ratio(roles.on_accent, roles.accent);
            assert!(
                contrast >= 4.5,
                "{mode:?} on-accent is {contrast:.2}:1 on the accent"
            );
        }
    }

    #[test]
    fn a_raised_panel_is_a_different_tone_that_still_carries_text() {
        for mode in [Mode::Dark, Mode::Light] {
            let roles = roles(mode);
            assert_ne!(roles.panel, roles.surface, "{mode:?} panel is invisible");
            for role in [Role::Foreground, Role::Muted] {
                let contrast = ratio(roles.get(role), roles.panel);
                assert!(
                    contrast >= 4.5,
                    "{mode:?} {role:?} is {contrast:.2}:1 on a panel"
                );
            }
        }
    }

    #[test]
    fn the_palette_is_plain_and_reserves_colour_for_what_it_means() {
        // Not the desktop's own scheme and not a decorative one: an installer is read next to
        // an administrator's other tools, so the tones stay neutral and only the accent and the
        // status roles carry any color at all.
        assert_eq!(roles(Mode::Dark).accent, Rgb(0x58, 0xa6, 0xff));
        assert_eq!(roles(Mode::Dark).surface, Rgb(0x0d, 0x11, 0x17));
        assert_eq!(roles(Mode::Light).accent, Rgb(0x09, 0x69, 0xda));
        assert_eq!(roles(Mode::Light).surface, Rgb(0xff, 0xff, 0xff));
    }

    #[test]
    fn the_splash_is_square_so_it_can_be_dropped_whole() {
        let width = SPLASH[0].chars().count();
        for line in SPLASH {
            assert_eq!(line.chars().count(), width, "{line}");
        }
    }

    #[test]
    fn the_depth_follows_the_terminal_and_the_users_wishes() {
        let truecolor = Env {
            colorterm: Some("truecolor".to_string()),
            ..env("xterm-256color", None)
        };
        assert_eq!(Theme::resolve(&truecolor).depth, Depth::True);
        assert_eq!(
            Theme::resolve(&env("xterm-256color", None)).depth,
            Depth::Indexed
        );
        assert_eq!(Theme::resolve(&env("xterm", None)).depth, Depth::Ansi);
        assert_eq!(Theme::resolve(&env("dumb", None)).depth, Depth::Mono);

        let no_colour = Env {
            no_color: true,
            colorterm: Some("truecolor".to_string()),
            ..env("xterm-256color", None)
        };
        assert_eq!(Theme::resolve(&no_colour).depth, Depth::Mono);
    }

    #[test]
    fn the_mode_is_chosen_by_the_user_then_by_the_terminal() {
        let asked = Env {
            theme: Some("LIGHT".to_string()),
            colorfgbg: Some("15;0".to_string()),
            ..Env::default()
        };
        assert_eq!(Theme::resolve(&asked).mode, Mode::Light);

        let light_terminal = Env {
            colorfgbg: Some("0;15".to_string()),
            ..Env::default()
        };
        assert_eq!(Theme::resolve(&light_terminal).mode, Mode::Light);

        let dark_terminal = Env {
            colorfgbg: Some("15;0".to_string()),
            ..Env::default()
        };
        assert_eq!(Theme::resolve(&dark_terminal).mode, Mode::Dark);

        assert_eq!(Theme::resolve(&Env::default()).mode, Mode::Dark);
    }

    #[test]
    fn cycling_swaps_the_mode_and_keeps_the_terminal() {
        let mut subject = Theme::resolve(&Env {
            colorterm: Some("truecolor".to_string()),
            ..Env::default()
        });
        assert_eq!(subject.mode, Mode::Dark);
        subject.cycle();
        assert_eq!(subject.mode, Mode::Light);
        assert_eq!(subject.depth, Depth::True);
        assert_eq!(subject.color(Role::Accent), Color::Rgb(0x09, 0x69, 0xda));
        subject.cycle();
        assert_eq!(subject.mode, Mode::Dark);
    }

    #[test]
    fn a_terminal_without_colour_falls_back_to_weight() {
        let theme = Theme::resolve(&env("dumb", None));
        assert_eq!(theme.color(Role::Error), Color::Reset);
        assert!(
            theme
                .status(Status::Failed)
                .add_modifier
                .contains(Modifier::BOLD)
        );
        assert!(theme.muted().add_modifier.contains(Modifier::DIM));
        assert_eq!(theme.status(Status::Warn).add_modifier, Modifier::BOLD);
    }

    #[test]
    fn every_state_has_its_own_colour_where_the_terminal_has_the_colours() {
        let theme = Theme::resolve(&Env {
            colorterm: Some("truecolor".to_string()),
            ..Env::default()
        });
        assert_eq!(theme.depth, Depth::True);
        let mut seen = std::collections::BTreeSet::new();
        for status in Status::ALL {
            let color = theme.status(status).fg;
            assert!(
                seen.insert(format!("{color:?}")),
                "{status:?} borrows another state's color"
            );
        }
    }

    #[test]
    fn sixteen_colour_terminals_share_hues_deliberately() {
        // There is no soft red in the basic sixteen, so `Ignored` borrows `Error`'s and leans on
        // its own glyph and its own label to stay apart.
        let theme = Theme::resolve(&env("xterm", None));
        assert_eq!(theme.depth, Depth::Ansi);
        assert_eq!(
            theme.status(Status::Ignored).fg,
            theme.status(Status::Failed).fg
        );
        assert_ne!(theme.color(Role::Error), theme.color(Role::Accent));
        assert_ne!(theme.color(Role::Ok), theme.color(Role::Warn));
    }

    #[test]
    fn the_indexed_palette_picks_a_nearest_neighbour() {
        // Exhaustive against the palette the function is allowed to choose from.
        for probe in [
            Rgb(0x0a, 0x0f, 0x0f),
            Rgb(0x9b, 0xd0, 0xcc),
            Rgb(0xfa, 0x74, 0x6f),
            Rgb(0xe8, 0xc8, 0x7a),
            Rgb(0xf6, 0xfa, 0xf9),
            Rgb(0x56, 0x61, 0x60),
        ] {
            let chosen = distance(probe, from_index(indexed(probe)));
            for index in 16..=255u8 {
                let alternative = distance(probe, from_index(index));
                assert!(
                    chosen <= alternative,
                    "{probe:?} picked {} which is worse than {index}",
                    indexed(probe)
                );
            }
        }
    }

    #[test]
    fn the_indexed_cube_and_ramp_are_laid_out_the_way_the_palette_is() {
        assert_eq!(from_index(16), Rgb(0, 0, 0));
        assert_eq!(from_index(231), Rgb(255, 255, 255));
        assert_eq!(from_index(232), Rgb(8, 8, 8));
        assert_eq!(from_index(255), Rgb(238, 238, 238));
    }
}
