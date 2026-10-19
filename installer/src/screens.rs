use ratatui::Frame;
use ratatui::layout::{Alignment, Constraint, Layout, Rect};
use ratatui::style::Style;
use ratatui::text::{Line, Span};
use ratatui::widgets::{Block, Paragraph};

use crate::app::{Action, App, AuthMethod, Confirm, FailureCard, Overlay, Stage};
use crate::glyphs::Glyphs;
use crate::logline::{Kind, LogLine};
use crate::menu::{self, Entry};
use crate::steps::{STEPS, Status};
use crate::theme::{self, Role, Theme};
use crate::ui;

const VALUE_COLUMN: usize = 12;

const NAME_CELL: usize = 52;

const LABEL_COLUMN: usize = 8;

const LOGOUT_BUTTON: &str = "Log out and apply Caelestia";

pub fn draw(frame: &mut Frame, app: &mut App) {
    app.area = frame.area();
    let header = app.header();
    let counter = app.counter();
    let keys = app.keys();
    let Some(chrome) = ui::chrome(
        frame,
        &app.theme,
        app.glyphs,
        &header,
        &keys,
        counter.as_deref(),
    ) else {
        return;
    };
    let body = chrome.body;

    match app.stage {
        Stage::Home => home(frame, app, body),
        Stage::Detect => detect(frame, app, body),
        Stage::Privilege => privilege(frame, app, body),
        Stage::Auth => auth(frame, app, body),
        Stage::Options => options(frame, app, body),
        Stage::Run => run(frame, app),
        Stage::Done => done(frame, app, body),
    }

    match app.overlay {
        Some(Overlay::Keys) => keys_overlay(frame, app),
        Some(Overlay::Log) => log_overlay(frame, app),
        Some(Overlay::Failure) => failure_overlay(frame, app),
        Some(Overlay::Confirm) => confirm_overlay(frame, app),
        None => {}
    }
}

fn home(frame: &mut Frame, app: &App, body: Rect) {
    let theme = &app.theme;
    let mark = banner(body);
    let named = mark.is_none();
    let credits = credits(app);
    let rest = notice(app);

    let identity_lines = identity(app, named);
    let gap = column_gap(body.width);
    let panel_width = ui::panel_width(actions_width(app), body.width);
    let mark_rows = if named {
        0
    } else {
        theme::SPLASH.len() as u16 + 1
    };
    let mark_width = theme::SPLASH[0].chars().count() as u16;
    let text_width = identity_lines
        .iter()
        .chain(credits.iter())
        .map(|line| line.width() as u16)
        .max()
        .unwrap_or(0);
    let left_width = if body.width >= mark_width + gap + panel_width {
        HOME_LEFT.max(mark_width)
    } else {
        text_width
    };
    let two_columns = body.width >= left_width + gap + panel_width;
    let left_rows = identity_lines.len() + 2 + credits.len();

    let (width, height) = if two_columns {
        (
            left_width + gap + panel_width,
            mark_rows + left_rows.max(ACTIONS_PANEL as usize + rest.len()) as u16,
        )
    } else {
        (
            ui::PROSE_WIDTH.min(body.width),
            mark_rows
                + identity_lines.len() as u16
                + Action::ALL.len() as u16
                + rest.len() as u16
                + credits.len() as u16
                + 3,
        )
    };
    let block = ui::middle(body, width, height);

    let below = match mark {
        Some(area) => {
            ui::prose(
                frame,
                Rect {
                    height: area.height,
                    ..block
                },
                mark_lines(app),
                theme.accent(),
            );
            Rect {
                y: block.y + mark_rows,
                height: block.height.saturating_sub(mark_rows),
                ..block
            }
        }
        None => block,
    };

    if two_columns {
        let left = Rect {
            width: left_width.min(below.width),
            ..below
        };
        let right = Rect {
            x: below.x + left.width + gap,
            width: below.width.saturating_sub(left.width + gap),
            ..below
        };
        let mut lines = identity_lines.clone();
        lines.push(blank());
        lines.extend(credits.clone());
        ui::prose(frame, left, lines, theme.body());
        actions_panel(frame, app, right);
        return;
    }

    let mut lines = identity_lines;
    lines.extend(actions(app, below.width));
    lines.extend(rest);
    lines.push(blank());
    lines.extend(credits);
    ui::prose(frame, below, lines, theme.body());
}

const HOME_LEFT: u16 = 54;
const HOME_GAP: u16 = 4;

fn column_gap(width: u16) -> u16 {
    HOME_GAP.max((width / 20).min(12))
}

fn actions_panel(frame: &mut Frame, app: &App, area: Rect) {
    let theme = &app.theme;
    let width = ui::panel_width(actions_width(app), area.width);
    let inner = ui::section(
        frame,
        ui::panel_rect(area, width, Action::ALL.len() as u16),
        theme,
        app.glyphs,
        None,
        Role::Rule,
    );
    ui::prose(frame, inner, actions(app, inner.width), theme.body());
    let rest = notice(app);
    if !rest.is_empty() {
        ui::prose(
            frame,
            ui::dropped(area, ACTIONS_PANEL + 1),
            rest,
            theme.body(),
        );
    }
}

const ACTIONS_PANEL: u16 = 5;

const MARK_MIN_HEIGHT: u16 = 22;

fn banner(body: Rect) -> Option<Rect> {
    let width = theme::SPLASH[0].chars().count() as u16;
    if body.width < width || body.height < MARK_MIN_HEIGHT {
        return None;
    }
    Some(Rect {
        height: theme::SPLASH.len() as u16,
        ..body
    })
}

fn mark_lines(app: &App) -> Vec<Line<'static>> {
    theme::SPLASH
        .iter()
        .map(|row| Line::from(Span::styled(row.to_string(), app.theme.accent())))
        .collect()
}

fn identity(app: &App, named: bool) -> Vec<Line<'static>> {
    let theme = &app.theme;
    let mut lines: Vec<Line<'static>> = Vec::new();
    if named {
        lines.push(Line::from(Span::styled(
            theme::NAME.to_string(),
            theme.title(),
        )));
    }
    lines.push(Line::from(Span::styled(
        theme::TAGLINE.to_string(),
        theme.muted(),
    )));
    lines.push(blank());
    lines.push(state_line(app));
    lines.extend(finish_line(app));
    lines
}

fn state_line(app: &App) -> Line<'static> {
    let theme = &app.theme;
    if !app.installed() {
        return Line::from(Span::styled("nothing installed yet", theme.muted()));
    }
    if !app.unfinished.is_empty() {
        return Line::from(Span::styled(
            "Caelestia is installed, but the last run did not finish",
            theme.warn_text(),
        ));
    }
    Line::from(Span::styled("Caelestia is installed", theme.body()))
}

fn finish_line(app: &App) -> Option<Line<'static>> {
    let (step, _) = app.unfinished.last()?;
    Some(Line::from(Span::styled(
        format!("stopped at {step} \u{00b7} install again to finish it"),
        app.theme.muted(),
    )))
}

fn actions(app: &App, width: u16) -> Vec<Line<'static>> {
    let theme = &app.theme;
    let glyphs = app.glyphs;
    let column = name_column();
    Action::ALL
        .iter()
        .enumerate()
        .map(|(index, action)| {
            let enabled = app.action_enabled(*action);
            let name = format!("{:<column$}", action.title(), column = column);
            if !enabled {
                return Line::from(vec![
                    Span::styled("  ", theme.muted()),
                    Span::styled(name, theme.muted()),
                    Span::styled(format!("  {}", Action::unavailable(*action)), theme.muted()),
                ]);
            }
            if index == app.home {
                return ui::cursor_row(
                    theme,
                    glyphs,
                    &format!("{} {name}", glyphs.cursor()),
                    width,
                );
            }
            Line::from(vec![
                Span::styled("  ", theme.body()),
                Span::styled(name, theme.body()),
            ])
        })
        .collect()
}

fn name_column() -> usize {
    Action::ALL
        .iter()
        .map(|action| action.title().len())
        .max()
        .unwrap_or(0)
}

fn actions_width(app: &App) -> u16 {
    let column = name_column();
    Action::ALL
        .iter()
        .map(|action| {
            if app.action_enabled(*action) {
                2 + column
            } else {
                2 + column + 2 + Action::unavailable(*action).chars().count()
            }
        })
        .max()
        .unwrap_or(0) as u16
}

fn credits(app: &App) -> Vec<Line<'static>> {
    let theme = &app.theme;
    vec![
        Line::from(Span::styled(theme::AUTHOR.to_string(), theme.muted())),
        Line::from(Span::styled(theme::CO_AUTHOR.to_string(), theme.muted())),
    ]
}

fn privilege(frame: &mut Frame, app: &App, body: Rect) {
    let theme = &app.theme;
    let glyphs = app.glyphs;
    const MEASURE: u16 = 56;
    let mut lines = if app.auth == Some(AuthMethod::Fingerprint) {
        fingerprint_card(app)
    } else {
        password_card(app)
    };

    lines.push(blank());
    if app.checking.is_some() {
        let waiting = if app.auth == Some(AuthMethod::Fingerprint) {
            "Waiting for your finger..."
        } else {
            "Checking your password..."
        };
        lines.push(Line::from(vec![
            Span::styled(format!("{} ", ui::running_glyph(app)), theme.accent()),
            Span::styled(waiting.to_string(), theme.muted()),
        ]));
    } else if let Some(problem) = &app.problem {
        for line in wrap(problem, MEASURE as usize) {
            lines.push(Line::from(Span::styled(line, theme.error_text())));
        }
    }
    if app.attempts > 0 {
        lines.push(Line::from(Span::styled(
            format!("attempt {}", app.attempts + 1),
            theme.warn_text(),
        )));
    }

    ui::card(
        frame,
        body,
        theme,
        glyphs,
        Some("root privileges"),
        MEASURE,
        lines,
    );
}

fn fingerprint_card(app: &App) -> Vec<Line<'static>> {
    vec![Line::from(Span::styled(
        AuthMethod::Fingerprint.title().to_string(),
        app.theme.body(),
    ))]
}

fn password_card(app: &App) -> Vec<Line<'static>> {
    let theme = &app.theme;
    let glyphs = app.glyphs;
    const MEASURE: u16 = 56;

    let mut field = vec![
        Span::styled(format!("{:<10}", "password"), theme.muted()),
        Span::styled(
            glyphs
                .mask()
                .repeat(app.password.chars().count().min(MEASURE as usize)),
            theme.body(),
        ),
    ];
    if app.password.is_empty() {
        field.push(Span::styled("(type, then ".to_string(), theme.muted()));
        field.push(Span::styled(glyphs.enter().to_string(), theme.accent()));
        field.push(Span::styled(")".to_string(), theme.muted()));
    }
    vec![Line::from(field)]
}

fn detect(frame: &mut Frame, app: &App, body: Rect) {
    let theme = &app.theme;

    if ui::rail(body, 44).is_some() {
        let rows = findings(app);
        let label_width = label_column(&rows);
        let left_width = ui::panel_width(finding_width(&rows, label_width), body.width / 2);

        let right_width = ui::panel_width(ui::PROSE_WIDTH, body.width / 2);
        let mut narrative = verdict_body(app, right_width.saturating_sub(2));
        narrative.push(blank());
        narrative.push(ui::cursor_row(
            theme,
            app.glyphs,
            &format!("{} continue", app.glyphs.cursor()),
            right_width.saturating_sub(2),
        ));

        const GAP: u16 = 4;
        let total = left_width + GAP + right_width;
        let x = body.x + body.width.saturating_sub(total) / 2;
        let left_height = rows.len() as u16 + 2;
        let right_height = narrative.len() as u16 + 2;
        let height = left_height.max(right_height);
        let y = body.y + body.height.saturating_sub(height) / 2;

        let inner = ui::section(
            frame,
            Rect {
                x,
                y,
                width: left_width,
                height: left_height,
            },
            theme,
            app.glyphs,
            Some("this machine"),
            Role::Rule,
        );
        ui::prose(
            frame,
            inner,
            finding_lines(&rows, label_width, theme),
            theme.body(),
        );

        let border = verdict(app);
        let inner = ui::section(
            frame,
            Rect {
                x: x + left_width + GAP,
                y,
                width: right_width,
                height: right_height,
            },
            theme,
            app.glyphs,
            None,
            border,
        );
        ui::prose(frame, inner, narrative, theme.body());
        return;
    }

    let rows = findings(app);
    let label_width = label_column(&rows);
    let headline = headline(app);
    let tail = reasons(app, body.width);
    let explanation = installed_explanation(app, body.width);

    let mut lines: Vec<Line<'static>> = vec![
        Line::from(Span::styled("This machine".to_string(), theme.heading())),
        blank(),
    ];

    let mut room = (body.height as usize)
        .saturating_sub(lines.len() + 1 + tail.len())
        .saturating_sub(explanation.len());
    let row_count = rows.len();
    let show_rows = row_count < room;
    if show_rows {
        room = room.saturating_sub(row_count + 1);
    }
    let show_explanation = !explanation.is_empty() && explanation.len() <= room;

    if show_rows {
        lines.extend(finding_lines(&rows, label_width, theme));
    }
    lines.push(headline);
    if show_explanation {
        for line in explanation {
            lines.push(Line::from(Span::styled(format!(" {line}"), theme.muted())));
        }
    }
    lines.extend(tail);

    lines.extend(notice(app));
    lines.push(blank());
    lines.push(ui::cursor_row(
        &app.theme,
        app.glyphs,
        &format!("{} continue", app.glyphs.cursor()),
        body.width.min(ui::PROSE_WIDTH),
    ));
    ui::prose_middle(frame, body, lines, theme.body());
}

fn findings(app: &App) -> Vec<(&'static str, String, bool)> {
    let found = &app.detection;
    vec![
        (
            "distribution",
            found.distro_label().to_string(),
            found.distro != crate::distro::Distro::Unknown,
        ),
        (
            "install layout",
            format!("{} install", found.kind_label()),
            true,
        ),
        (
            "package manager",
            found
                .package_manager
                .map(str::to_string)
                .unwrap_or_else(|| "not found".to_string()),
            found.package_manager.is_some(),
        ),
        (
            "quickshell",
            if found.quickshell {
                "found".to_string()
            } else {
                "not installed yet".to_string()
            },
            true,
        ),
        (
            "git",
            if found.git {
                "found".to_string()
            } else {
                "missing".to_string()
            },
            found.git,
        ),
    ]
}

fn label_column(rows: &[(&'static str, String, bool)]) -> usize {
    rows.iter()
        .map(|(label, _, _)| label.chars().count())
        .max()
        .unwrap_or(0)
}

fn finding_lines(
    rows: &[(&'static str, String, bool)],
    label_width: usize,
    theme: &Theme,
) -> Vec<Line<'static>> {
    rows.iter()
        .map(|(label, value, ok)| {
            let value_style = if *ok { theme.body() } else { theme.warn_text() };
            Line::from(vec![
                Span::styled(
                    format!(" {label:<label_width$}  "),
                    if *ok {
                        theme.muted()
                    } else {
                        theme.warn_text()
                    },
                ),
                Span::styled(value.clone(), value_style),
            ])
        })
        .collect()
}

fn finding_width(rows: &[(&'static str, String, bool)], label_width: usize) -> u16 {
    rows.iter()
        .map(|(_, value, _)| label_width + value.chars().count() + 3)
        .max()
        .unwrap_or(0) as u16
}

fn headline(app: &App) -> Line<'static> {
    let theme = &app.theme;
    let glyphs = app.glyphs;
    let (mark, role, text) = if app.detection.installed && !app.unfinished.is_empty() {
        (
            Status::Warn,
            theme.warn_text(),
            "The last install did not finish.",
        )
    } else if app.detection.installed {
        (
            Status::Failed,
            theme.error_text(),
            "Caelestia is already installed.",
        )
    } else {
        (
            Status::Ok,
            theme.status(Status::Ok),
            "Nothing is in the way.",
        )
    };
    Line::from(vec![
        Span::styled(format!("{} ", glyphs.status(mark)), role),
        Span::styled(text.to_string(), role),
    ])
}

fn reasons(app: &App, width: u16) -> Vec<Line<'static>> {
    let theme = &app.theme;
    let glyphs = app.glyphs;
    let mut lines: Vec<Line<'static>> = Vec::new();
    for blocker in app.detection.blockers() {
        lines.push(blank());
        lines.push(Line::from(vec![
            Span::styled(
                format!("{} ", glyphs.status(Status::Failed)),
                theme.error_text(),
            ),
            Span::styled(blocker.to_string(), theme.error_text()),
        ]));
    }
    if let Some(problem) = &app.problem {
        lines.push(blank());
        for line in wrap(problem, (width as usize).saturating_sub(4)) {
            lines.push(Line::from(Span::styled(
                format!(" {line}"),
                theme.error_text(),
            )));
        }
    }
    lines
}

fn installed_explanation(app: &App, width: u16) -> Vec<String> {
    if !app.detection.installed {
        return Vec::new();
    }
    let measure = (width as usize).saturating_sub(4);
    if let Some((step, _)) = app.unfinished.last() {
        return wrap(
            &format!(
                "It stopped at {step}. What finished is kept, so continuing carries on from \
                 there, and your own configs are backed up first."
            ),
            measure,
        );
    }
    wrap(
        "Continuing installs over it: the shell configuration and the deployed files are \
         replaced. Your own configs are backed up first.",
        measure,
    )
}

fn verdict_body(app: &App, width: u16) -> Vec<Line<'static>> {
    let theme = &app.theme;
    let mut lines = vec![headline(app)];
    let explanation = installed_explanation(app, width);
    if !explanation.is_empty() {
        lines.push(blank());
        lines.extend(
            explanation
                .into_iter()
                .map(|line| Line::from(Span::styled(format!(" {line}"), theme.muted()))),
        );
    }
    lines.extend(reasons(app, width));
    lines
}

fn verdict(app: &App) -> Role {
    let found = &app.detection;
    if !found.blockers().is_empty() {
        Role::Error
    } else if found.installed {
        Role::Warn
    } else {
        Role::Rule
    }
}

fn auth(frame: &mut Frame, app: &App, body: Rect) {
    let theme = &app.theme;
    let glyphs = app.glyphs;
    const MEASURE: u16 = 68;
    let mut lines: Vec<Line<'static>> = Vec::new();

    for (index, method) in app.auth_methods().iter().enumerate() {
        let chosen = index == app.cursor;
        if chosen {
            lines.push(ui::cursor_row(
                theme,
                glyphs,
                &format!("{} {}", glyphs.cursor(), method.title()),
                MEASURE,
            ));
        } else {
            lines.push(Line::from(vec![
                Span::styled("   ".to_string(), theme.body()),
                Span::styled(method.title().to_string(), theme.body()),
            ]));
        }
    }

    if let Some(problem) = &app.problem {
        lines.push(blank());
        for line in wrap(problem, MEASURE as usize) {
            lines.push(Line::from(Span::styled(line, theme.error_text())));
        }
    }
    lines.extend(notice(app));

    ui::card(
        frame,
        body,
        theme,
        glyphs,
        Some("root privileges"),
        MEASURE,
        lines,
    );
}

fn options(frame: &mut Frame, app: &App, body: Rect) {
    let theme = &app.theme;

    let rail_width = ui::panel_width(question_rail_width(), body.width);
    let gap = column_gap(body.width);
    let pane_width = PANE_WIDTH.min(body.width.saturating_sub(rail_width + gap));
    if pane_width >= PANE_MIN {
        let listed = option_rows(app, pane_width).len() as u16 + 2;
        let width = rail_width + gap + pane_width;
        let height = (listed + HELP_ROWS + 2).max(question_rail(app).len() as u16 + 2);
        let block = ui::middle(body, width, height);

        let rail = question_rail(app);
        let left = Rect {
            width: rail_width,
            ..block
        };
        let inner = ui::section(
            frame,
            ui::panel_rect(left, rail_width, rail.len() as u16),
            theme,
            app.glyphs,
            None,
            Role::Rule,
        );
        ui::prose(frame, inner, rail, theme.body());

        let right = Rect {
            x: block.x + rail_width + gap,
            width: pane_width,
            ..block
        };
        question_pane(frame, app, right);
        return;
    }

    question_pane(
        frame,
        app,
        ui::middle(body, body.width.min(PANE_WIDE), body.height),
    );
}

const PANE_WIDTH: u16 = 74;
const PANE_WIDE: u16 = 96;
const PANE_MIN: u16 = 44;
const HELP_ROWS: u16 = 2;

fn question_rail(app: &App) -> Vec<Line<'static>> {
    let theme = &app.theme;
    let glyphs = app.glyphs;
    let mut lines: Vec<Line<'static>> = Vec::new();
    for index in 0..menu::question_count() {
        let title = menu::question(index);
        let here = index == app.question;
        let name_style = if here { theme.selected() } else { theme.body() };
        let changed = if app.question_changed(index) {
            format!("  {}", glyphs.changed())
        } else {
            String::new()
        };
        lines.push(Line::from(vec![
            Span::styled(
                if here { "  · " } else { "    " },
                if here { theme.accent() } else { theme.muted() },
            ),
            Span::styled(title.to_string(), name_style),
            Span::styled(changed, theme.accent()),
        ]));
    }
    lines
}

fn question_rail_width() -> u16 {
    let mut width = 0;
    for index in 0..menu::question_count() {
        let title = menu::question(index);
        width = width.max(2 + title.len() + 2 + 2);
    }
    width as u16
}

fn question_pane(frame: &mut Frame, app: &App, area: Rect) {
    let theme = &app.theme;
    let mut listed = option_rows(app, area.width);
    listed.push(blank());
    listed.push(continue_row(app));
    let rows = Layout::vertical([
        Constraint::Length(2),
        Constraint::Length(listed.len() as u16),
        Constraint::Min(0),
    ])
    .areas::<3>(area);

    let mut heading_spans = vec![Span::styled(
        menu::question(app.question).to_string(),
        theme.heading(),
    )];
    if app.question_changed(app.question) {
        heading_spans.push(Span::styled(
            format!("  {} changed", app.glyphs.changed()),
            theme.accent(),
        ));
    }
    ui::prose(
        frame,
        rows[0],
        vec![Line::from(heading_spans)],
        theme.body(),
    );

    ui::prose(frame, rows[1], listed, theme.body());

    let mut help_lines: Vec<Line<'static>> = Vec::new();
    if let Some(text) = app.selected().and_then(Entry::help) {
        for line in wrap(text, (rows[2].width as usize).saturating_sub(2)) {
            help_lines.push(Line::from(Span::styled(line, theme.muted())));
        }
    }
    help_lines.extend(notice(app));
    ui::prose(frame, rows[2], help_lines, theme.body());
}

fn continue_row(app: &App) -> Line<'static> {
    let theme = &app.theme;
    let chosen = app.on_continue();
    let style = if chosen {
        theme.selected()
    } else {
        theme.body()
    };
    Line::from(vec![
        Span::styled(
            format!(" {} ", if chosen { app.glyphs.cursor() } else { " " }),
            style,
        ),
        Span::styled("  continue".to_string(), style),
    ])
}

pub(crate) fn option_rows(app: &App, width: u16) -> Vec<Line<'static>> {
    let theme = &app.theme;
    let glyphs = app.glyphs;
    let name_width = (width as usize)
        .saturating_sub(VALUE_COLUMN + 5)
        .clamp(8, NAME_CELL);
    let entries = app.current_entries();
    if entries.is_empty() {
        return vec![Line::from(Span::styled(
            "Nothing on this machine to theme.".to_string(),
            theme.muted(),
        ))];
    }
    entries
        .into_iter()
        .enumerate()
        .map(|(index, entry)| {
            let chosen = index == app.cursor;
            let changed = if app.is_changed(entry) {
                format!("{} ", glyphs.changed())
            } else {
                "  ".to_string()
            };
            let room = name_width;
            let name = format!(
                "{:<room$}",
                ui::fit(entry.title(), room, glyphs.ellipsis()),
                room = room
            );
            let (value, value_style) = value_cell(entry, app);
            let value = format!("{:>width$}", value, width = VALUE_COLUMN);
            let pointer = format!(" {} ", if chosen { glyphs.cursor() } else { " " });
            let label = if chosen {
                theme.selected()
            } else {
                theme.body()
            };

            Line::from(vec![
                Span::styled(
                    pointer,
                    if chosen {
                        theme.selected()
                    } else {
                        theme.body()
                    },
                ),
                Span::styled(changed, theme.accent()),
                Span::styled(name, label),
                Span::styled(value, value_style),
            ])
        })
        .collect()
}

fn value_cell(entry: &'static Entry, app: &App) -> (String, Style) {
    let glyphs = app.glyphs;
    let theme = &app.theme;
    match entry {
        Entry::Preset { .. } => (String::new(), theme.muted()),
        Entry::Toggle { id, .. } => {
            let on = menu::value(entry, &app.answers) == Some("true");
            if !on {
                return (format!("{} skip", glyphs.cross()), theme.muted());
            }
            if app.apps.has(id) {
                (
                    format!("{} installed", glyphs.tick()),
                    theme.status(Status::Ok),
                )
            } else if app.apps.is_app_row(id) {
                (
                    format!("{} will install", glyphs.circle()),
                    theme.status(Status::Warn),
                )
            } else {
                (format!("{} on", glyphs.tick()), theme.status(Status::Ok))
            }
        }
        Entry::Choice { .. } => (
            format!(
                "{} {} {}",
                glyphs.open(),
                menu::value(entry, &app.answers).unwrap_or_default(),
                glyphs.close()
            ),
            theme.muted(),
        ),
        Entry::Submenu { .. } => (glyphs.submenu().to_string(), theme.muted()),
    }
}

fn run(frame: &mut Frame, app: &App) {
    let theme = &app.theme;
    let layout = app.run_layout();

    ui::prose(frame, layout.step, vec![step_line(app)], theme.body());
    ui::prose(
        frame,
        layout.bar,
        vec![bar_line(app, layout.bar.width)],
        theme.body(),
    );
    ui::prose(frame, layout.note, vec![note_line(app)], theme.body());
    log_pane(frame, app, layout.log, app.log_rows());
}

fn step_line(app: &App) -> Line<'static> {
    let theme = &app.theme;
    let running = app.running_step();
    let index = running.or_else(|| app.next_step());
    let Some(index) = index else {
        return Line::from(Span::styled(
            format!("{} Finishing up", app.glyphs.status(Status::Ok)),
            theme.status(Status::Ok),
        ));
    };
    let style = if running.is_some() {
        theme.selected()
    } else {
        theme.body()
    };
    let glyph = if running.is_some() {
        ui::running_glyph(app)
    } else {
        app.glyphs.status(Status::Pending)
    };
    Line::from(vec![
        ui::gutter(glyph, style, app.glyphs),
        Span::styled(STEPS[index].name.to_string(), style),
    ])
}

fn bar_line(app: &App, width: u16) -> Line<'static> {
    let done = app.finished();
    let total = STEPS.len();
    let percent = done
        .saturating_mul(100)
        .checked_div(total)
        .unwrap_or_default();
    let elapsed = app.total_elapsed().as_secs();
    let caption = if elapsed == 0 {
        format!("{percent:>3}%")
    } else {
        format!("{percent:>3}%   {}", ui::elapsed(elapsed))
    };
    ui::progress(done, total, width, &caption, &app.theme, app.glyphs)
}

fn note_line(app: &App) -> Line<'static> {
    let theme = &app.theme;
    let glyphs = app.glyphs;
    let counts = app.tally();
    let mut spans: Vec<Span<'static>> = Vec::new();
    for (count, status, one, many) in [
        (counts.failed, Status::Failed, "failure", "failures"),
        (counts.warn, Status::Warn, "warning", "warnings"),
        (counts.ignored, Status::Ignored, "ignored", "ignored"),
    ] {
        if count == 0 {
            continue;
        }
        if !spans.is_empty() {
            spans.push(Span::styled("   ".to_string(), theme.muted()));
        }
        spans.push(ui::gutter(
            glyphs.status(status),
            theme.status(status),
            glyphs,
        ));
        spans.push(Span::styled(
            ui::plural(count, one, many),
            theme.status(status),
        ));
    }
    Line::from(spans)
}

fn log_pane(frame: &mut Frame, app: &App, area: Rect, rows: usize) {
    let theme = &app.theme;
    let glyphs = app.glyphs;
    if area.height < 2 || area.width < 4 {
        return;
    }

    let heading = Rect { height: 1, ..area };
    let body = Rect {
        y: area.y + 1,
        height: area.height - 1,
        ..area
    };
    frame.render_widget(Block::default().style(theme.panel()), area);
    let (start, rows) = app.log_window_for(rows);
    let total = app.visible_log().len();
    let overflowing = total > rows;

    let mut badge = vec![Span::styled(" install log".to_string(), theme.muted())];
    badge.push(Span::styled("  ·  ".to_string(), theme.muted()));
    badge.push(Span::styled(
        if overflowing {
            format!("{}-{} of {total}", start + 1, (start + rows).min(total))
        } else {
            ui::plural(total, "line", "lines")
        },
        theme.muted(),
    ));
    if app.log_loud_only {
        badge.push(Span::styled("  ·  ".to_string(), theme.muted()));
        badge.push(Span::styled(
            "warnings and errors only".to_string(),
            theme.warn_text(),
        ));
    }
    let problems = app.problem_rows().len();
    if problems > 0 {
        badge.push(Span::styled("  ·  ".to_string(), theme.muted()));
        badge.push(Span::styled(
            format!("{} to jump to", ui::plural(problems, "problem", "problems")),
            theme.warn_text(),
        ));
    }
    ui::prose(frame, heading, vec![Line::from(badge)], theme.body());

    let follow_width = 7.min(area.width);
    let follow = Rect {
        x: area.x + area.width - follow_width,
        width: follow_width,
        ..heading
    };
    frame.render_widget(
        Paragraph::new(Line::from(Span::styled(
            if app.log_follow { "FOLLOW" } else { "PAUSED" }.to_string(),
            if app.log_follow {
                theme.selected()
            } else {
                theme.warn_text()
            },
        )))
        .alignment(Alignment::Right),
        follow,
    );

    let (text_area, bar_area) = if overflowing {
        (
            Rect {
                width: body.width - 1,
                ..body
            },
            Some(Rect {
                x: body.x + body.width - 1,
                width: 1,
                ..body
            }),
        )
    } else {
        (body, None)
    };
    let mut lines: Vec<Line<'static>> = Vec::new();
    for line in app.visible_log().into_iter().skip(start).take(rows) {
        lines.push(log_line(line, theme, glyphs));
    }
    ui::prose(frame, text_area, lines, theme.body());
    if let Some(bar_area) = bar_area {
        let marks: Vec<(usize, ratatui::style::Style)> = app
            .visible_log()
            .iter()
            .enumerate()
            .filter(|(_, line)| line.is_loud())
            .map(|(row, line)| (row, line.style(theme)))
            .collect();
        ui::scrollbar(frame, bar_area, start, total, theme, glyphs, &marks);
    }
}

fn log_line(line: &LogLine, theme: &Theme, glyphs: Glyphs) -> Line<'static> {
    let style = line.style(theme);
    let gutter = match line.glyph(glyphs) {
        Some(glyph) => ui::gutter(
            glyph,
            if line.kind == Kind::Heading {
                theme.rule()
            } else {
                style
            },
            glyphs,
        ),
        None => Span::styled(" ".repeat(glyphs.status_cell() + 2), theme.body()),
    };
    Line::from(vec![
        gutter,
        Span::styled(
            format!("{}{}", " ".repeat(usize::from(line.depth) * 2), line.text),
            style,
        ),
    ])
}

fn steps_with(app: &App, status: Status) -> Vec<usize> {
    app.statuses
        .iter()
        .enumerate()
        .filter(|(_, each)| **each == status)
        .map(|(index, _)| index)
        .collect()
}

fn done(frame: &mut Frame, app: &App, body: Rect) {
    let theme = &app.theme;
    let glyphs = app.glyphs;
    let tally = app.tally();

    let (status, ending, style) = if tally.failed > 0 {
        (
            Status::Failed,
            format!(
                "finished with {}",
                ui::plural(tally.failed, "failed step", "failed steps")
            ),
            theme.error_text(),
        )
    } else if tally.ignored > 0 {
        (
            Status::Ignored,
            format!(
                "finished with {}",
                ui::plural(tally.ignored, "ignored step", "ignored steps")
            ),
            theme.ignored_text(),
        )
    } else if tally.warn > 0 {
        (
            Status::Warn,
            format!(
                "finished with {}",
                ui::plural(tally.warn, "warning", "warnings")
            ),
            theme.warn_text(),
        )
    } else {
        (Status::Ok, "finished".to_string(), theme.ok_text())
    };

    let mut lines: Vec<Line<'static>> = vec![Line::from(vec![
        Span::styled(format!(" {} ", glyphs.status(status)), style),
        Span::styled("The install ".to_string(), theme.body()),
        Span::styled(ending, theme.title()),
        Span::styled(".".to_string(), theme.body()),
    ])];
    lines.extend(notice(app));

    let failed = steps_with(app, Status::Failed);
    let ignored = steps_with(app, Status::Ignored);
    let mut trouble: Vec<Line<'static>> = Vec::new();
    for index in steps_with(app, Status::Warn) {
        trouble.push(ui::labeled(
            "warned",
            STEPS[index].name.to_string(),
            theme,
            LABEL_COLUMN,
        ));
    }
    for (label, indexes) in [("failed", &failed), ("ignored", &ignored)] {
        for index in indexes {
            trouble.push(ui::labeled(
                label,
                format!(
                    "{}  ·  caelestia-install step {}",
                    STEPS[*index].name, STEPS[*index].id
                ),
                theme,
                LABEL_COLUMN,
            ));
        }
    }
    if !failed.is_empty() || !ignored.is_empty() {
        trouble.push(ui::labeled(
            "retry",
            "r here, or that command in a terminal".to_string(),
            theme,
            LABEL_COLUMN,
        ));
    }
    if !trouble.is_empty() {
        lines.push(blank());
        lines.extend(trouble);
    }

    lines.push(blank());
    if let Some(landed) = &app.landed {
        if let Some(version) = &landed.version {
            lines.push(ui::labeled(
                "version",
                version_line(version, landed),
                theme,
                LABEL_COLUMN,
            ));
        }
        lines.push(ui::labeled(
            "shell",
            crate::paths::shorten(&landed.shell),
            theme,
            LABEL_COLUMN,
        ));
        lines.push(ui::labeled(
            "settings",
            crate::paths::shorten(&landed.configs),
            theme,
            LABEL_COLUMN,
        ));
        if let Some(backup) = &landed.backup {
            lines.push(ui::labeled(
                "backup",
                crate::paths::shorten(backup),
                theme,
                LABEL_COLUMN,
            ));
        }
    }
    lines.push(ui::labeled(
        "log",
        crate::paths::shorten(&app.log_path),
        theme,
        LABEL_COLUMN,
    ));

    lines.push(blank());
    if tally.unresolved() > 0 {
        lines.push(ui::labeled(
            "kept",
            "nothing was rolled back, so the steps that finished are still installed".to_string(),
            theme,
            LABEL_COLUMN,
        ));
    } else {
        lines.push(ui::labeled(
            "next",
            "log out and back in so the new session settings apply".to_string(),
            theme,
            LABEL_COLUMN,
        ));
        lines.push(blank());
        lines.push(Line::from(Span::styled(
            format!("  {} (o) ", LOGOUT_BUTTON),
            theme.bar(),
        )));
        lines.push(blank());
    }
    lines.push(ui::labeled(
        "update",
        "caelestia-install --update".to_string(),
        theme,
        LABEL_COLUMN,
    ));
    lines.push(ui::labeled(
        "remove",
        "caelestia-install --uninstall".to_string(),
        theme,
        LABEL_COLUMN,
    ));

    ui::prose_middle(frame, body, lines, theme.body());
}

fn version_line(version: &str, landed: &crate::app::Landed) -> String {
    let mut value = version.to_string();
    if let Some(commit) = &landed.commit {
        let short: String = commit.chars().take(7).collect();
        value.push_str(&format!(" \u{00b7} {short}"));
    }
    if let Some(branch) = &landed.branch {
        value.push_str(&format!(" \u{00b7} {branch}"));
    }
    value
}

fn keys_overlay(frame: &mut Frame, app: &App) {
    let theme = &app.theme;
    let glyphs = app.glyphs;
    let entries: [(&str, &str); 12] = [
        ("\u{2191}\u{2193} / j k", "move"),
        ("\u{2190}\u{2192} / h l", "change a value"),
        (glyphs.enter(), "continue, or open"),
        (glyphs.escape(), "back one step"),
        ("q", "quit"),
        ("ctrl+c", "stop and quit"),
        ("t", "dark or light"),
        ("f", "follow the log"),
        ("w", "warnings and errors only"),
        ("l", "the whole log, full screen"),
        ("r / R", "reset one option, or all of them"),
        ("?", "this list"),
    ];
    let inner = ui::panel(
        frame,
        frame.area(),
        theme,
        glyphs,
        Some("KEYS"),
        (62, entries.len() as u16 + 5),
        Role::Rule,
    );
    let mut lines: Vec<Line<'static>> = Vec::new();
    for (keys, what) in entries {
        lines.push(Line::from(vec![
            Span::styled(format!("  {keys:<12}"), theme.accent()),
            Span::styled(what.to_string(), theme.body()),
        ]));
    }
    ui::prose(frame, inner, lines, theme.body());
}

fn log_overlay(frame: &mut Frame, app: &App) {
    let theme = &app.theme;
    let glyphs = app.glyphs;
    let area = frame.area();
    let inner = ui::frame_panel(
        frame,
        ui::log_overlay_rect(area),
        theme,
        glyphs,
        Some("INSTALL LOG"),
        Role::Rule,
    );
    let rows = inner.height.saturating_sub(1).max(1) as usize;
    log_pane(frame, app, inner, rows);
}

fn failure_overlay(frame: &mut Frame, app: &App) {
    let theme = &app.theme;
    let glyphs = app.glyphs;
    let Some(card) = &app.failure else {
        return;
    };
    let height = card.detail.len() as u16 + FailureCard::CHOICES.len() as u16 + 10;
    let inner = ui::panel(
        frame,
        frame.area(),
        theme,
        glyphs,
        None,
        (78, height),
        Role::Error,
    );

    let mut lines: Vec<Line<'static>> = vec![
        Line::from(vec![
            Span::styled(
                format!(" {} ", glyphs.status(Status::Failed)),
                theme.error_text(),
            ),
            Span::styled(card.step.to_string(), theme.heading()),
            Span::styled(" did not finish".to_string(), theme.muted()),
        ]),
        blank(),
    ];
    if card.detail.is_empty() {
        lines.push(Line::from(Span::styled(
            "the step printed nothing".to_string(),
            theme.muted(),
        )));
    }
    for line in &card.detail {
        lines.push(log_line(line, theme, glyphs));
    }
    lines.push(blank());
    lines.push(ui::labeled(
        "log",
        app.log_path.display().to_string(),
        theme,
        LABEL_COLUMN,
    ));
    lines.push(ui::labeled(
        "reproduce",
        card.reproduction(),
        theme,
        LABEL_COLUMN,
    ));
    lines.push(blank());
    for (index, choice) in FailureCard::CHOICES.iter().enumerate() {
        let chosen = index == card.choice;
        let pointer = format!(" {} ", if chosen { glyphs.cursor() } else { " " });
        let label = format!("{} {:<8}", choice.key, choice.label);
        if chosen {
            let mut spans = vec![Span::raw(pointer), Span::raw(label)];
            if !choice.help.is_empty() {
                spans.push(Span::raw(choice.help.to_string()));
            }
            lines.push(ui::cursor_spans(theme, spans, inner.width));
        } else {
            let mut spans = vec![
                Span::styled(pointer, theme.muted()),
                Span::styled(label, theme.body()),
            ];
            if !choice.help.is_empty() {
                spans.push(Span::styled(choice.help.to_string(), theme.muted()));
            }
            lines.push(Line::from(spans));
        }
    }
    lines.push(blank());
    lines.push(Line::from(Span::styled(
        format!(
            "{} closes this without deciding, and leaves the run paused",
            glyphs.escape()
        ),
        theme.muted(),
    )));
    ui::prose(frame, inner, lines, theme.body());
}

fn confirm_overlay(frame: &mut Frame, app: &App) {
    let theme = &app.theme;
    let glyphs = app.glyphs;
    let asked = app.confirm.unwrap_or(Confirm::Install);
    let (subject, question, border) = match app.confirm {
        Some(Confirm::Handoff(action)) => (
            action.title(),
            "The installer closes and hands the terminal over.".to_string(),
            Role::Accent,
        ),
        Some(Confirm::Install) => (
            "Install Caelestia now?",
            "Packages are installed, the configuration is deployed and the shell is built."
                .to_string(),
            Role::Accent,
        ),
        Some(Confirm::Quit) | None => (
            "Stop the install here?",
            "A step that is running is stopped first. Work already done stays done.".to_string(),
            Role::Warn,
        ),
        Some(Confirm::LogOut) => (
            "Log out now?",
            "Everything open is closed and the next session starts with Caelestia. Save what you \
             are working on first."
                .to_string(),
            Role::Accent,
        ),
    };

    let width = 70u16.min(frame.area().width.saturating_sub(2)).max(8);
    let measure = width.saturating_sub(4) as usize;
    let mut lines = vec![
        Line::from(Span::styled(subject.to_string(), theme.heading())),
        blank(),
    ];
    for line in wrap(&question, measure) {
        lines.push(Line::from(Span::styled(line, theme.muted())));
    }
    if app.confirm == Some(Confirm::Install) {
        let changed = app.changed_answers();
        lines.push(blank());
        lines.push(Line::from(Span::styled(
            "Your settings are backed up first.".to_string(),
            theme.muted(),
        )));
        if changed > 0 {
            lines.push(Line::from(Span::styled(
                format!(
                    "{} changed from the defaults.",
                    ui::plural(changed, "option", "options")
                ),
                theme.accent(),
            )));
        }
    }
    lines.push(blank());
    for (index, label) in asked.buttons().iter().enumerate() {
        let chosen = index == app.confirm_focus;
        let pointer = format!(" {} ", if chosen { glyphs.cursor() } else { " " });
        let letter = if index == 0 { "y" } else { "n" };
        if chosen {
            let spans = vec![Span::raw(pointer), Span::raw(format!("{label} ({letter})"))];
            lines.push(ui::cursor_spans(theme, spans, width - 2));
        } else {
            lines.push(Line::from(vec![
                Span::styled(pointer, theme.muted()),
                Span::styled(format!("{label} "), theme.body()),
                Span::styled(format!("({letter})"), theme.muted()),
            ]));
        }
    }
    let height = lines.len() as u16 + 2;
    let inner = ui::panel(
        frame,
        frame.area(),
        theme,
        glyphs,
        None,
        (width, height),
        border,
    );
    ui::prose(frame, inner, lines, theme.body());
}

fn blank() -> Line<'static> {
    Line::from("")
}

fn notice(app: &App) -> Vec<Line<'static>> {
    match &app.notice {
        Some(text) => vec![Line::from(Span::styled(text.clone(), app.theme.accent()))],
        None => Vec::new(),
    }
}

fn wrap(text: &str, width: usize) -> Vec<String> {
    crate::ui::wrap(text, width, 20)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::app::{AuthMethod, Flow, Overlay, Stage};
    use crate::env::Env;
    use crossterm::event::{KeyCode, KeyEvent, KeyModifiers};
    use std::path::PathBuf;

    fn on(env: Env) -> App {
        let mut app = App::new(
            PathBuf::from("/tmp/caelestia"),
            PathBuf::from("/tmp/install.log"),
            env,
        );
        app.pretend = true;
        app.detection.installed = false;
        app.unfinished.clear();
        app.needs_password = true;
        app
    }

    fn app() -> App {
        on(Env::default())
    }

    fn color_app() -> App {
        on(Env {
            term: Some("xterm-256color".to_string()),
            colorterm: Some("truecolor".to_string()),
            ..Env::default()
        })
    }

    fn app_that_has_a_reader() -> App {
        app().with_fingerprint(true)
    }

    fn app_that_stopped_at(step: &str) -> App {
        let mut app = app();
        app.detection.installed = true;
        app.unfinished = vec![(step.to_string(), crate::steps::Status::Failed)];
        app
    }

    fn cells(app: &mut App, width: u16, height: u16) -> ratatui::buffer::Buffer {
        let backend = ratatui::backend::TestBackend::new(width, height);
        let mut terminal = ratatui::Terminal::new(backend).expect("a test terminal");
        terminal
            .draw(|frame| draw(frame, app))
            .expect("a drawn frame");
        terminal.backend().buffer().clone()
    }

    fn row_of(buffer: &ratatui::buffer::Buffer, needle: &str) -> u16 {
        (0..buffer.area.height)
            .find(|y| {
                let mut text = String::new();
                for x in 0..buffer.area.width {
                    text.push_str(buffer[(x, *y)].symbol());
                }
                text.contains(needle)
            })
            .unwrap_or_else(|| panic!("no row holds {needle:?}"))
    }

    #[test]
    fn the_footer_is_filled_right_across_the_terminal() {
        let mut app = color_app();
        let accent = app.theme.color(Role::Accent);
        let buffer = cells(&mut app, 100, 30);
        let bar = buffer.area.height - 2;
        for x in 1..buffer.area.width - 1 {
            assert_eq!(buffer[(x, bar)].bg, accent, "the bar stops at column {x}");
        }
        assert_ne!(
            buffer[(0, bar)].bg,
            accent,
            "the bar covers the frame's edge"
        );
        assert_ne!(
            buffer[(1, bar - 1)].bg,
            accent,
            "the body above it is filled"
        );
    }

    #[test]
    fn the_row_the_cursor_is_on_is_the_only_filled_row_of_the_list() {
        let mut app = color_app();
        let accent = app.theme.color(Role::Accent);
        let buffer = cells(&mut app, 100, 30);
        let chosen = row_of(&buffer, "Install Caelestia");
        let other = row_of(&buffer, "Uninstall Caelestia");
        let filled = |row: u16| (0..buffer.area.width).any(|x| buffer[(x, row)].bg == accent);
        assert!(filled(chosen), "the cursor's row is not filled");
        assert!(!filled(other), "a row the cursor is not on is filled");
    }

    fn left_margin(line: &str) -> usize {
        let inside: String = line.chars().skip(1).collect();
        inside.chars().count() - inside.trim_start().chars().count()
    }

    #[test]
    fn a_wide_frame_puts_the_home_composition_in_the_middle() {
        let width = 236u16;
        let height = 60u16;
        let mut app = app();
        let text = render(&mut app, width, height);
        let lines: Vec<&str> = text.lines().collect();

        let mark_row = lines
            .iter()
            .position(|line| line.contains('\u{2588}'))
            .unwrap_or_else(|| panic!("the mark is on screen:\n{text}"));
        let panel_bottom = lines
            .iter()
            .position(|line| line.contains('\u{2514}'))
            .expect("the action panel is on screen");

        let left = left_margin(lines[mark_row]);
        let corner = lines[panel_bottom]
            .chars()
            .collect::<Vec<char>>()
            .iter()
            .rposition(|cell| *cell == '\u{2518}')
            .expect("a panel corner");
        let right = width as usize - corner - 2;
        assert!(
            left > 20,
            "the composition is against the left edge: {left} columns of air"
        );
        assert!(
            (left as isize - right as isize).abs() <= 4,
            "the block is off centre: {left} columns on the left, {right} on the right"
        );

        let below = height as usize - 1 - panel_bottom;
        assert!(
            (mark_row as isize - below as isize).abs() <= 4,
            "the block is off centre: {mark_row} rows above, {below} below"
        );
    }

    #[test]
    fn a_wide_frame_puts_the_questions_in_the_middle() {
        let width = 236u16;
        let mut app = app();
        app.stage = Stage::Options;
        let text = render(&mut app, width, 60);
        let lines: Vec<&str> = text.lines().collect();
        let rail_top = lines
            .iter()
            .position(|line| line.contains('\u{250c}') && line.contains("Appearance"))
            .expect("the map is on screen");
        let left = left_margin(lines[rail_top]);
        assert!(left > 20, "the map is against the left edge: {left}");
        assert!(
            left < (width / 2) as usize,
            "the block is past the middle, not in it: {left}"
        );

        assert!(
            lines[rail_top].contains('\u{250c}'),
            "the map's corner is on the heading row:\n{text}"
        );
    }

    #[test]
    fn the_password_is_asked_for_rather_than_chosen_from_a_list() {
        let mut app = app();
        app.pretend = true;
        app.detection = crate::app::Detection {
            distro: crate::distro::Distro::Arch,
            kind: crate::install_kind::Kind::Source,
            installed: false,
            package_manager: Some("pacman"),
            quickshell: true,
            git: true,
        };
        app.stage = Stage::Options;
        app.question = crate::menu::question_count() - 1;
        app.cursor = app.current_entries().len();
        app.key(KeyEvent::new(KeyCode::Enter, KeyModifiers::NONE));
        assert_eq!(
            app.overlay,
            Some(Overlay::Confirm),
            "the last answer asks before it acts"
        );
        app.key(KeyEvent::new(KeyCode::Char('y'), KeyModifiers::NONE));

        assert_eq!(
            app.stage,
            Stage::Privilege,
            "blockers: {:?}, problem: {:?}",
            app.detection.blockers(),
            app.problem
        );
        let text = render(&mut app, 120, 40);
        assert!(
            text.contains("root privileges"),
            "the question is up: {text}"
        );
        assert!(text.contains("password"), "and the field is on it: {text}");
        assert!(
            !text.contains("Type your password here"),
            "the list of routes is not between them: {text}"
        );

        let mut with_reader = app_that_has_a_reader();
        with_reader.pretend = true;
        with_reader.detection = app.detection.clone();
        with_reader.stage = Stage::Options;
        with_reader.question = crate::menu::question_count() - 1;
        with_reader.cursor = with_reader.current_entries().len();
        with_reader.key(KeyEvent::new(KeyCode::Enter, KeyModifiers::NONE));
        with_reader.key(KeyEvent::new(KeyCode::Char('y'), KeyModifiers::NONE));
        assert_eq!(with_reader.stage, Stage::Auth);
        let text = render(&mut with_reader, 120, 40);
        assert!(text.contains("Type your password here"), "{text}");
        assert!(text.contains("Touch the fingerprint reader"), "{text}");
    }

    #[test]
    fn a_half_finished_install_is_not_called_installed() {
        let mut half = app_that_stopped_at("08-build-shell");
        let text = render(&mut half, 120, 40);
        assert!(
            text.contains("the last run did not finish"),
            "the state says what happened: {text}"
        );
        assert!(
            text.contains("08-build-shell"),
            "and names the step it stopped at: {text}"
        );

        let mut done = app();
        done.detection.installed = true;
        let text = render(&mut done, 120, 40);
        assert!(text.contains("Caelestia is installed"), "{text}");
        assert!(!text.contains("did not finish"), "{text}");
    }

    #[test]
    fn the_detection_screen_says_where_the_last_install_stopped() {
        let mut app = app_that_stopped_at("08-build-shell");
        app.stage = Stage::Detect;
        let text = render(&mut app, 120, 40);
        assert!(
            text.contains("The last install did not finish"),
            "the headline is the half install, not a refusal: {text}"
        );
        assert!(
            !text.contains("already installed"),
            "and not the cross that greets a finished one: {text}"
        );
        assert!(
            text.contains("stopped at 08-build-shell"),
            "the screen explains the half install: {text}"
        );
        assert!(
            text.contains("carries on"),
            "and what continuing does about it: {text}"
        );
    }

    #[test]
    fn a_middling_terminal_still_puts_the_actions_beside_the_words() {
        let mut app = app();
        let text = render(&mut app, 120, 40);
        let lines: Vec<&str> = text.lines().collect();

        let panel_row = lines
            .iter()
            .position(|line| line.contains("\u{25b6} Install Caelestia"))
            .expect("the actions are on screen");
        let panel_col = lines[panel_row - 1]
            .chars()
            .collect::<Vec<char>>()
            .iter()
            .position(|cell| *cell == '\u{250c}')
            .expect("the actions have a panel around them");
        assert!(
            panel_col > 20,
            "the panel is not beside anything: {panel_col}"
        );
        assert!(
            panel_col < 60,
            "the panel belongs beside the words, not out past them: {panel_col}"
        );
    }

    #[test]
    fn a_wide_terminal_spends_its_width_on_a_second_column() {
        let mut wide = app();
        wide.stage = Stage::Options;
        wide.action = crate::app::Action::Install;
        let text = render(&mut wide, 235, 58);
        assert!(text.contains("Advanced"), "no map:\n{text}");

        let mut narrow = app();
        narrow.stage = Stage::Options;
        narrow.action = crate::app::Action::Install;
        let text = render(&mut narrow, 62, 24);
        assert!(!text.contains("Advanced"), "a map in one column:\n{text}");
        assert!(
            text.contains("Appearance"),
            "and the question left:\n{text}"
        );
    }

    #[test]
    fn a_wide_detection_screen_says_what_it_found_and_what_it_means() {
        let mut app = app();
        app.stage = Stage::Detect;
        app.detection = crate::app::Detection {
            distro: crate::distro::Distro::Arch,
            kind: crate::install_kind::Kind::Source,
            installed: true,
            package_manager: Some("pacman"),
            quickshell: true,
            git: true,
        };
        let text = render(&mut app, 235, 58);
        assert!(text.contains("this machine"), "{text}");
        assert!(text.contains("already installed"), "no verdict: {text}");
        assert!(text.contains("Arch-based Linux"), "{text}");
    }

    #[test]
    fn the_detection_screen_lists_what_it_found_about_this_machine() {
        let mut app = app();
        app.stage = Stage::Detect;
        app.detection = crate::app::Detection {
            distro: crate::distro::Distro::Arch,
            kind: crate::install_kind::Kind::Source,
            installed: false,
            package_manager: Some("pacman"),
            quickshell: true,
            git: true,
        };
        let text = render(&mut app, 100, 30);
        assert!(text.contains("This machine"), "{text}");
        for row in [
            "distribution",
            "Arch-based Linux",
            "package manager",
            "pacman",
            "git",
            "found",
        ] {
            assert!(text.contains(row), "{row} is missing from:\n{text}");
        }
        assert!(
            text.contains("Nothing is in the way"),
            "an install with a clear field says so: {text}"
        );
        assert!(
            text.contains("continue"),
            "the way off this screen is on it: {text}"
        );
    }

    #[test]
    fn the_detection_screen_is_centred_rather_than_pinned_to_the_left_edge() {
        let mut app = app();
        app.stage = Stage::Detect;
        app.detection = crate::app::Detection {
            distro: crate::distro::Distro::Arch,
            kind: crate::install_kind::Kind::Source,
            installed: false,
            package_manager: Some("pacman"),
            quickshell: true,
            git: true,
        };

        let wide = render(&mut app, 164, 46);
        let first = wide
            .lines()
            .find(|line| line.contains("this machine"))
            .unwrap_or_else(|| panic!("no findings panel in:\n{wide}"));
        let indent = first.chars().take_while(|c| *c == ' ' || *c == '│').count();
        assert!(indent > 20, "the panel starts at column {indent}:\n{wide}");
    }

    #[test]
    fn the_detection_screen_warns_before_an_install_is_overwritten() {
        let mut app = app();
        app.stage = Stage::Detect;
        app.detection = crate::app::Detection {
            distro: crate::distro::Distro::Arch,
            kind: crate::install_kind::Kind::Source,
            installed: true,
            package_manager: Some("pacman"),
            quickshell: true,
            git: true,
        };
        app.detection.installed = true;
        let text = render(&mut app, 100, 30);
        assert!(
            text.contains("already installed"),
            "the one fact that changes the decision: {text}"
        );
        assert!(
            text.contains("replaced"),
            "and what continuing does: {text}"
        );
        assert!(
            text.contains("update instead"),
            "and the cheaper route, on the footer: {text}"
        );
    }

    #[test]
    fn the_detection_screen_names_what_would_stop_the_install() {
        let mut unknown = app();
        unknown.stage = Stage::Detect;
        unknown.detection = crate::app::Detection {
            distro: crate::distro::Distro::Unknown,
            kind: crate::install_kind::Kind::Source,
            installed: false,
            package_manager: None,
            quickshell: false,
            git: false,
        };
        let text = render(&mut unknown, 100, 30);
        assert!(
            text.contains("not one the installer knows"),
            "a distribution it cannot help with is said plainly: {text}"
        );
        assert_eq!(
            unknown.detection.blockers().len(),
            1,
            "and said once: {:?}",
            unknown.detection.blockers()
        );

        let mut known = app();
        known.stage = Stage::Detect;
        known.detection = crate::app::Detection {
            distro: crate::distro::Distro::Arch,
            kind: crate::install_kind::Kind::Source,
            installed: false,
            package_manager: None,
            quickshell: false,
            git: false,
        };
        let text = render(&mut known, 100, 30);
        assert!(text.contains("No supported package manager"), "{text}");
        assert!(text.contains("git is missing"), "{text}");

        let mut overlay = app();
        overlay.overlay = Some(Overlay::Keys);
        let text = render(&mut overlay, 100, 34);
        for line in ["dark or light", "this list"] {
            assert!(text.contains(line), "{line} is missing from:\n{text}");
        }
        assert_eq!(
            text.matches("reset").count(),
            1,
            "a key is described once, in the list: {text}"
        );
    }

    #[test]
    fn the_reason_a_screen_is_blocking_survives_a_short_terminal() {
        let problem = "Sort out the above first.";
        let worst = crate::app::Detection {
            distro: crate::distro::Distro::Unknown,
            kind: crate::install_kind::Kind::Source,
            installed: true,
            package_manager: None,
            quickshell: false,
            git: false,
        };

        let mut roomy = app();
        roomy.stage = Stage::Detect;
        roomy.detection = crate::app::Detection {
            distro: crate::distro::Distro::Arch,
            ..worst.clone()
        };
        assert!(render(&mut roomy, 100, 30).contains("Your own configs are backed up first"));

        let mut tight = app();
        tight.stage = Stage::Detect;
        tight.detection = worst;
        tight.problem = Some(problem.to_string());
        let text = render(&mut tight, 60, 20);
        assert!(
            text.contains("not one the installer knows"),
            "the reason survives: {text}"
        );
        assert!(
            text.contains("already installed"),
            "and what it means for the decision: {text}"
        );
        assert!(
            text.contains("Sort out the above first"),
            "and the answer to the key: {text}"
        );
        assert!(
            !text.contains("Your own configs are backed up first"),
            "at the cost of the explanation: {text}"
        );
        let headline = text.find("already installed").expect("the headline");
        let explanation = text.find("Continuing installs over it");
        assert!(
            explanation.is_none_or(|at| at > headline),
            "the explanation follows the thing it explains: {text}"
        );
    }

    #[test]
    fn the_privilege_routes_are_offered_by_name() {
        let mut app = app();
        app.stage = Stage::Auth;
        let text = render(&mut app, 100, 30);
        for phrase in ["root privileges", "Type your password here"] {
            assert!(text.contains(phrase), "{phrase} is missing from:\n{text}");
        }
        assert!(
            !text.contains("sudo -v"),
            "the command appears with the route that needs it, not before: {text}"
        );
        assert!(
            !text.contains("For when it cannot ask"),
            "and nothing is said twice: {text}"
        );
    }

    #[test]
    fn a_reader_is_offered_by_name_and_asked_by_touching_it() {
        let mut app = app().with_fingerprint(true);
        app.stage = Stage::Auth;
        let text = render(&mut app, 100, 30);
        assert!(
            text.contains("Touch the fingerprint reader"),
            "the route is named on the list: {text}"
        );

        app.auth = Some(AuthMethod::Fingerprint);
        app.stage = Stage::Privilege;
        let (sender, receiver) = std::sync::mpsc::channel();
        sender.send(true).expect("the answer fits");
        app.checking = Some(receiver);
        let waiting = render(&mut app, 100, 30);
        assert!(
            waiting.contains("Touch the fingerprint reader"),
            "{waiting}"
        );
        assert!(
            !waiting.contains("password"),
            "a reader is not typed into: {waiting}"
        );
        assert!(
            waiting.contains("Waiting for your finger"),
            "and the wait says what it is waiting for: {waiting}"
        );

        app.checking = None;
        app.problem = Some("No finger was recognized.".to_string());
        let refused = render(&mut app, 100, 30);
        assert!(refused.contains("No finger was recognized."), "{refused}");
        assert!(
            !refused.contains("password"),
            "and still asks for no password: {refused}"
        );
    }

    #[test]
    fn the_detection_screen_says_why_a_guard_sent_the_user_back() {
        let mut app = app();
        app.stage = Stage::Detect;
        app.detection = crate::app::Detection {
            distro: crate::distro::Distro::Arch,
            kind: crate::install_kind::Kind::Source,
            installed: true,
            package_manager: Some("pacman"),
            quickshell: true,
            git: true,
        };
        app.installed_when_started = false;
        app.problem = Some("Caelestia was installed while the wizard was open.".to_string());

        let text = render(&mut app, 100, 30);
        assert!(
            text.contains("while the wizard was open"),
            "an explained block, not a screen that changed its mind: {text}"
        );
        assert!(text.contains("already installed"), "{text}");
    }

    #[test]
    fn a_question_screen_names_the_question_and_says_where_it_is() {
        let mut app = app();
        app.stage = Stage::Options;
        app.question = 0;
        let text = render(&mut app, 100, 30);
        assert!(text.contains(menu::question(0)), "{text}");
        assert_eq!(
            menu::question(0),
            "Appearance",
            "and the heading is the whole of it"
        );
        assert!(
            text.contains(&format!("question 1/{}", menu::question_count())),
            "and how far along it is: {text}"
        );

        app.question = menu::question_count() - 1;
        let last = render(&mut app, 100, 30);
        assert!(
            last.contains(&format!(
                "question {}/{}",
                menu::question_count(),
                menu::question_count()
            )),
            "{last}"
        );
    }

    #[test]
    fn a_question_that_was_answered_says_so_above_its_rows() {
        let mut app = app();
        app.stage = Stage::Options;
        app.question = 0;
        assert!(!render(&mut app, 100, 30).contains("changed"));

        char_key(&mut app, ' ');
        assert!(
            render(&mut app, 100, 30).contains("changed"),
            "stepping back to a screen that was edited should say so"
        );
    }

    #[test]
    fn the_confirmation_states_what_saying_yes_starts() {
        let mut app = app();
        app.confirm = Some(Confirm::Install);
        app.overlay = Some(Overlay::Confirm);
        let text = render(&mut app, 100, 30);
        assert!(text.contains("Install Caelestia now?"), "{text}");
        assert!(
            text.contains("Install (y)"),
            "the answer is a button: {text}"
        );
        assert!(text.contains("Cancel (n)"), "and so is the other: {text}");
        assert!(text.contains("backed up"), "{text}");
        assert!(
            !text.contains("steps"),
            "the step count is the installer's business: {text}"
        );
    }

    fn char_key(app: &mut App, character: char) -> Flow {
        app.key(KeyEvent::new(KeyCode::Char(character), KeyModifiers::NONE))
    }

    fn render(app: &mut App, width: u16, height: u16) -> String {
        let backend = ratatui::backend::TestBackend::new(width, height);
        let mut terminal = ratatui::Terminal::new(backend).expect("a test terminal");
        terminal
            .draw(|frame| draw(frame, app))
            .expect("a drawn frame");
        let buffer = terminal.backend().buffer();
        let mut text = String::new();
        for y in 0..buffer.area.height {
            for x in 0..buffer.area.width {
                text.push_str(buffer[(x, y)].symbol());
            }
            text.push('\n');
        }
        text
    }

    fn rows_with(text: &str, needle: &str) -> Vec<String> {
        text.lines()
            .filter(|row| row.contains(needle))
            .map(str::to_string)
            .collect()
    }

    fn running(statuses: &[Status], log: &[&str]) -> App {
        let mut app = app();
        app.stage = Stage::Run;
        for (index, status) in statuses.iter().enumerate() {
            app.statuses[index] = *status;
        }
        app.log = log.iter().map(|line| LogLine::parse(line)).collect();
        app
    }

    #[test]
    fn a_wide_run_screen_gives_the_log_the_whole_width() {
        let mut app = running(&[Status::Ok, Status::Running], &["* fetching packages"]);
        let long = format!("{}END", "x".repeat(120));
        app.log = (0..30)
            .map(|index| LogLine::parse(&format!("  [INFO]  {index} {long}")))
            .collect();
        let text = render(&mut app, 200, 40);
        let log = rows_with(&text, "install log")
            .first()
            .expect("no log heading")
            .clone();
        assert!(
            log.find("install log").expect("a log heading") < 20,
            "the log was pushed into a column:\n{text}"
        );
        assert!(
            text.contains("END"),
            "the log is clipped to a column:\n{text}"
        );
    }

    #[test]
    fn the_home_screen_offers_the_three_actions_and_says_what_they_do() {
        let text = render(&mut app(), 100, 30);
        assert!(text.contains("Install Caelestia"), "{text}");
        assert!(text.contains("Update this install"), "{text}");
        assert!(text.contains("Uninstall Caelestia"), "{text}");
        assert!(text.contains(theme::TAGLINE), "{text}");
        assert!(
            text.contains("██████╗"),
            "the mark is drawn where it fits: {text}"
        );
        assert!(text.contains(theme::AUTHOR), "{text}");
    }

    #[test]
    fn the_mark_is_dropped_rather_than_clipped_when_there_is_no_room_for_it() {
        let text = render(&mut app(), 62, 22);
        assert!(!text.contains("██████╗"), "{text}");
        assert!(text.contains(theme::NAME), "the name stands in: {text}");
        assert!(
            text.contains("Install Caelestia"),
            "and the launcher stays: {text}"
        );
    }

    #[test]
    fn a_terminal_too_small_says_so_instead_of_drawing_a_broken_frame() {
        let text = render(&mut app(), 40, 10);
        assert!(text.contains("terminal too small"), "{text}");
        assert!(text.contains("60x20"), "{text}");
        assert!(!text.contains("Install Caelestia"), "{text}");
    }

    #[test]
    fn the_chrome_shows_where_the_user_is_and_how_the_install_went() {
        let mut app = app();
        app.stage = Stage::Options;
        app.action = crate::app::Action::Install;
        let text = render(&mut app, 100, 30);
        assert!(text.contains("caelestia · install"), "{text}");
        assert!(text.contains("↑↓ move"), "the real keymap: {text}");
    }

    #[test]
    fn the_privilege_screen_never_shows_the_password() {
        let mut app = app();
        app.stage = Stage::Privilege;
        app.password = "hunter2".to_string();
        let problem = app.problem.clone();
        assert_eq!(problem, None);
        let text = render(&mut app, 80, 24);
        assert!(!text.contains("hunter2"), "{text}");
        assert!(
            text.contains("•••••••"),
            "and shows that something was typed: {text}"
        );
    }

    #[test]
    fn a_wrong_password_is_shown_as_a_problem_with_what_to_do_about_it() {
        let mut app = app();
        app.stage = Stage::Privilege;
        app.attempts = 3;
        app.problem = Some("Not accepted. A wrong entry now locks the account.".to_string());
        let text = render(&mut app, 100, 30);
        assert!(text.contains("Not accepted"), "{text}");
        assert!(text.contains("locks the account"), "{text}");
        assert!(text.contains("attempt 4"), "{text}");
    }

    #[test]
    fn the_wait_for_sudo_is_shown_where_the_answer_will_appear() {
        let mut app = app();
        app.stage = Stage::Privilege;
        app.password = "hunter2".to_string();
        let (sender, receiver) = std::sync::mpsc::channel();
        app.checking = Some(receiver);
        let text = render(&mut app, 100, 30);
        assert!(text.contains("Checking your password"), "{text}");
        assert!(!text.contains("hunter2"), "{text}");

        sender.send(false).expect("the answer fits");
        app.tick();
        let text = render(&mut app, 100, 30);
        assert!(text.contains("accepted"), "{text}");
        assert!(!text.contains("Checking your password"), "{text}");
    }

    #[test]
    fn every_question_ends_with_a_row_that_goes_on() {
        let mut app = app();
        app.stage = Stage::Options;
        for question in 0..menu::question_count() {
            app.question = question;
            app.cursor = 0;
            let text = render(&mut app, 100, 30);
            assert!(
                text.contains("continue"),
                "question {question} has no row to go on with:\n{text}"
            );
        }
    }

    #[test]
    fn the_longest_question_shows_its_last_row_and_the_way_on_at_the_smallest_size() {
        let mut app = app();
        app.stage = Stage::Options;
        app.question = (0..menu::question_count())
            .find(|index| {
                menu::items_of(*index)
                    .iter()
                    .any(|entry| entry.id() == menu::PRESET_THEME_APPS)
            })
            .expect("the app question is in the tree");
        let text = render(&mut app, 60, 20);
        assert!(text.contains("Firefox"), "the last row was clipped: {text}");
        assert!(text.contains("continue"), "and the way on: {text}");
    }

    #[test]
    fn the_app_question_offers_every_app_even_on_a_machine_that_has_none() {
        let mut app = app().with_apps(crate::apps::Apps::default());
        app.stage = Stage::Options;
        app.question = (0..menu::question_count())
            .find(|index| {
                menu::items_of(*index)
                    .iter()
                    .any(|entry| entry.id() == menu::PRESET_THEME_APPS)
            })
            .expect("the app question is in the tree");

        let text = render(&mut app, 100, 30);
        for id in crate::apps::Apps::IDS {
            let entry = menu::every_entry()
                .into_iter()
                .find(|entry| entry.id() == id)
                .expect("every app id is a row");
            assert!(
                text.contains(entry.title()),
                "{} is missing: {text}",
                entry.title()
            );
        }
        assert!(text.contains("All of them"), "{text}");
        assert!(text.contains("None of them"), "{text}");
    }

    #[test]
    fn every_option_row_starts_at_the_same_column() {
        let mut app = app();
        app.stage = Stage::Options;
        app.question = 0;
        let rows = option_rows(&app, 96);
        let titles: Vec<&'static str> = app
            .current_entries()
            .iter()
            .map(|entry| entry.title())
            .collect();
        let columns: Vec<usize> = rows
            .iter()
            .zip(titles)
            .map(|(row, title)| {
                let text: String = row.spans.iter().map(|span| span.content.as_ref()).collect();
                let bytes = text.find(title).expect("the title is on its row");
                text[..bytes].chars().count()
            })
            .collect();
        assert!(
            columns.windows(2).all(|pair| pair[0] == pair[1]),
            "the rows start at different columns: {columns:?}"
        );
    }

    #[test]
    fn the_options_screen_puts_values_in_a_column() {
        let mut app = app();
        app.stage = Stage::Options;
        let rows = option_rows(&app, 96);
        assert_eq!(rows.len(), app.current_entries().len());

        let widths: Vec<usize> = rows.iter().map(Line::width).collect();
        assert!(
            widths.windows(2).all(|pair| pair[0] == pair[1]),
            "the rows are not a grid: {widths:?}"
        );

        let text = render(&mut app, 100, 30);
        for entry in app.current_entries() {
            assert!(text.contains(entry.title()), "{}", entry.title());
        }
    }

    #[test]
    fn a_value_that_is_too_long_for_its_column_is_marked_rather_than_silently_cut() {
        let mut app = app();
        app.stage = Stage::Options;
        let narrow = option_rows(&app, 24);
        let drawn: Vec<String> = narrow.iter().map(|row| row.to_string()).collect();
        assert!(
            drawn.iter().any(|row| row.contains('…')),
            "a clipped name says so: {drawn:?}"
        );
        let widths: Vec<usize> = narrow.iter().map(Line::width).collect();
        assert!(
            widths.windows(2).all(|pair| pair[0] == pair[1]),
            "{widths:?}"
        );
    }

    #[test]
    fn the_options_screen_marks_what_was_changed_and_shows_the_help() {
        let mut app = app();
        app.stage = Stage::Options;
        app.question = 0;
        app.cursor = 0;
        let before = render(&mut app, 100, 30);
        assert!(!before.contains("•"), "{before}");
        assert!(
            !before.contains("Replace the login screen"),
            "a row's label is not repeated as its help: {before}"
        );

        app.cursor = 0;
        let shot = render(&mut app, 100, 30);
        assert!(
            shot.contains("Login screen colours"),
            "the first row is the login screen: {shot}"
        );
        assert!(
            shot.contains("Plasma Login draws its own screen"),
            "the row's own help is on screen:\n{shot}"
        );
        app.cursor = 1;
        assert!(
            !render(&mut app, 100, 30).contains("Plasma Login draws its own screen"),
            "and it goes with the cursor"
        );

        app.key(KeyEvent::new(KeyCode::Char(' '), KeyModifiers::NONE));
        let after = render(&mut app, 100, 30);
        assert!(after.contains("•"), "the change is marked: {after}");
        assert!(
            after.contains("changed"),
            "and the question says so: {after}"
        );
        assert!(after.contains(menu::question(0)), "{after}");
    }
    #[test]
    fn the_run_screen_names_the_step_it_is_on_and_how_far_along_it_is() {
        let mut app = running(
            &[Status::Ok, Status::Warn, Status::Running],
            &["  [INFO]  syncing databases", "  [WARN]  slow mirror"],
        );
        let text = render(&mut app, 100, 30);
        let step = STEPS[2].name;
        assert!(text.contains(step), "the step it is on: {text}");
        assert!(text.contains('%'), "how far along: {text}");
        assert!(
            text.contains("1 warning"),
            "what did not go cleanly: {text}"
        );
        assert!(
            !text.contains("PENDING") && !text.contains("RUNNING"),
            "the states are no longer spelled out: {text}"
        );
    }

    #[test]
    fn the_run_screen_gives_the_log_the_room_it_never_had() {
        let mut app = running(&[Status::Running], &["  [INFO]  one", "  [INFO]  two"]);
        app.log = (0..40)
            .map(|index| LogLine::parse(&format!("  [INFO]  line {index}")))
            .collect();
        let text = render(&mut app, 80, 24);
        let shown = (0..40)
            .filter(|index| text.contains(&format!("line {index}")))
            .count();
        assert!(
            shown >= 6,
            "only {shown} lines of log made it onto the screen: {text}"
        );
    }

    #[test]
    fn the_log_pane_says_where_it_is_and_whether_it_follows() {
        let mut app = running(&[Status::Running], &[]);
        app.log = (0..60)
            .map(|index| LogLine::parse(&format!("  [INFO]  line {index}")))
            .collect();
        let following = render(&mut app, 100, 30);
        assert!(following.contains("FOLLOW"), "{following}");
        assert!(
            following.contains(" of 60"),
            "the position is shown: {following}"
        );

        app.log_follow = false;
        app.log_scroll = 4;
        let paused = render(&mut app, 100, 30);
        assert!(paused.contains("PAUSED"), "{paused}");
    }

    #[test]
    fn the_log_is_classified_so_a_failure_does_not_look_like_chatter() {
        let mut app = running(
            &[Status::Running],
            &[
                "  [INFO]  reading packages",
                "  [WARN]  slow mirror",
                "  [ERR]   package not found",
            ],
        );
        let text = render(&mut app, 100, 30);

        let warning = rows_with(&text, "slow mirror");
        assert!(
            warning.iter().any(|row| row.contains('!')),
            "the warning has its own glyph: {warning:?}"
        );
        let failure = rows_with(&text, "package not found");
        assert!(
            failure.iter().any(|row| row.contains('✗')),
            "and the failure its own: {failure:?}"
        );
        let chatter = rows_with(&text, "reading packages");
        assert!(
            chatter
                .iter()
                .all(|row| !row.contains('!') && !row.contains('✗')),
            "and chatter stays plain: {chatter:?}"
        );
    }

    #[test]
    fn the_log_counts_what_went_wrong_and_offers_to_walk_it() {
        let mut app = running(
            &[Status::Running],
            &[
                "  [INFO]  chatter",
                "  [WARN]  a slow mirror",
                "  [ERR]   a package failed",
            ],
        );
        let text = render(&mut app, 166, 48);
        assert!(text.contains("2 problems to jump to"), "{text}");
        assert!(text.contains("n next problem"), "{text}");
        assert!(text.contains("p previous"), "{text}");
    }

    #[test]
    fn a_long_log_marks_the_lines_that_went_wrong_on_its_scrollbar() {
        let mut app = running(&[Status::Running], &["  [INFO]  chatter"]);
        app.log = (0..300)
            .map(|line| {
                if line == 150 {
                    LogLine::parse("  [ERR]   a package failed")
                } else {
                    LogLine::parse(&format!("  [INFO]  line {line}"))
                }
            })
            .collect();
        let text = render(&mut app, 100, 40);
        let layout = ui::run_layout(ui::body(app.area));
        let column = (layout.log.x + layout.log.width - 1) as usize;
        let bar: String = text
            .lines()
            .filter_map(|row| row.chars().nth(column))
            .collect();
        assert!(bar.contains('•'), "the failure is marked: {bar:?}");
        assert!(bar.contains('█'), "and the window is still drawn: {bar:?}");
    }

    #[test]
    fn the_log_can_be_narrowed_to_the_lines_that_matter() {
        let mut app = running(
            &[Status::Running],
            &["  [INFO]  chatter", "  [ERR]   a package failed"],
        );
        app.log_loud_only = true;
        let text = render(&mut app, 100, 30);
        assert!(text.contains("a package failed"), "{text}");
        assert!(text.contains("warnings and errors only"), "{text}");
        assert!(!text.contains("chatter"), "{text}");
    }

    #[test]
    fn the_failure_card_says_what_to_do_and_what_each_answer_costs() {
        let mut app = app();
        app.stage = Stage::Run;
        app.statuses[0] = Status::Failed;
        app.failure = Some(crate::app::FailureCard::new(
            &STEPS[0],
            &[LogLine::parse("  [ERR]   the mirror is unreachable")],
        ));
        app.overlay = Some(Overlay::Failure);
        let text = render(&mut app, 100, 32);
        assert!(text.contains("did not finish"), "{text}");
        assert!(text.contains("Update system"), "{text}");
        assert!(text.contains("the mirror is unreachable"), "{text}");
        assert!(
            text.contains("caelestia-install step 00a-system-update"),
            "{text}"
        );
        for choice in crate::app::FailureCard::CHOICES {
            assert!(text.contains(choice.label), "{}", choice.label);
        }
        assert!(text.contains("leaves the run paused"), "{text}");
    }

    fn landed() -> crate::app::Landed {
        crate::app::Landed {
            version: Some("v2.6.3".to_string()),
            commit: Some("9f2a1cb1234567890".to_string()),
            branch: Some("main".to_string()),
            shell: PathBuf::from("/home/tester/.config/quickshell/caelestia"),
            configs: PathBuf::from("/home/tester/.config/caelestia"),
            backup: Some(PathBuf::from(
                "/home/tester/caelestia/backups/20240101_120000",
            )),
        }
    }

    #[test]
    fn the_summary_says_what_is_installed_and_what_to_do_with_it() {
        let mut app = app();
        app.stage = Stage::Done;
        app.statuses = vec![Status::Ok; STEPS.len()];
        app.landed = Some(landed());
        let text = render(&mut app, 110, 32);

        assert!(text.contains("The install finished."), "{text}");
        assert!(
            text.contains("v2.6.3 \u{00b7} 9f2a1cb \u{00b7} main"),
            "the version, the revision and the channel: {text}"
        );
        assert!(text.contains("quickshell/caelestia"), "{text}");
        assert!(text.contains("caelestia/backups/20240101_120000"), "{text}");
        assert!(text.contains("/tmp/install.log"), "{text}");
        assert!(text.contains("log out and back in"), "{text}");
        assert!(text.contains("caelestia-install --update"), "{text}");
        assert!(text.contains("caelestia-install --uninstall"), "{text}");
        assert!(!text.contains("warning"), "nothing to warn about: {text}");
    }

    #[test]
    fn the_summary_is_not_a_score_of_the_run() {
        let mut app = app();
        app.stage = Stage::Done;
        app.statuses = vec![Status::Ok; STEPS.len()];
        app.landed = Some(landed());
        let text = render(&mut app, 110, 32);

        assert!(!text.contains("steps finished"), "{text}");
        assert!(!text.contains(&format!("of {}", STEPS.len())), "{text}");
    }

    #[test]
    fn the_summary_does_not_offer_a_retry_it_cannot_do() {
        let mut app = app();
        app.stage = Stage::Done;
        app.statuses = vec![Status::Ok; STEPS.len()];
        app.landed = Some(landed());
        let text = render(&mut app, 110, 32);
        assert!(!text.contains("retry"), "nothing to retry: {text}");

        app.statuses[3] = Status::Ignored;
        let text = render(&mut app, 110, 32);
        assert!(
            text.contains("r retry failed"),
            "the way out of an unfinished run: {text}"
        );
    }

    #[test]
    fn the_summary_offers_to_log_out_for_the_reader() {
        let mut app = app();
        app.stage = Stage::Done;
        app.statuses = vec![Status::Ok; STEPS.len()];
        app.landed = Some(landed());
        let text = render(&mut app, 110, 32);

        assert!(
            text.contains("Log out and apply Caelestia (o)"),
            "the way to apply it is a button with its key in it: {text}"
        );
        assert!(!text.contains("o log out"), "{text}");
        assert!(text.contains("log out and back in"), "{text}");
    }

    #[test]
    fn the_logout_button_is_filled_like_every_other_button() {
        let mut app = color_app();
        app.stage = Stage::Done;
        app.statuses = vec![Status::Ok; STEPS.len()];
        app.landed = Some(landed());
        let accent = app.theme.color(Role::Accent);
        let buffer = cells(&mut app, 110, 32);
        let row = row_of(&buffer, LOGOUT_BUTTON);
        let text: String = (0..buffer.area.width)
            .map(|x| buffer[(x, row)].symbol())
            .collect();
        let start = text.find(LOGOUT_BUTTON).expect("the label is on its row") as u16;
        for x in start..start + LOGOUT_BUTTON.chars().count() as u16 {
            assert_eq!(
                buffer[(x, row)].bg,
                accent,
                "column {x} of the button is not filled: {text}"
            );
        }
    }

    #[test]
    fn the_summary_does_not_offer_a_logout_it_will_not_do() {
        let mut app = app();
        app.stage = Stage::Done;
        app.statuses = vec![Status::Ok; STEPS.len()];
        app.statuses[4] = Status::Failed;
        app.landed = Some(landed());
        let text = render(&mut app, 110, 32);

        assert!(!text.contains("Log out and apply Caelestia"), "{text}");
        assert!(!text.contains("o log out"), "{text}");
    }

    #[test]
    fn the_logout_card_says_what_ending_the_session_does() {
        let mut app = app();
        app.stage = Stage::Done;
        app.statuses = vec![Status::Ok; STEPS.len()];
        app.ask(crate::app::Confirm::LogOut);
        let text = render(&mut app, 100, 30);

        assert!(text.contains("Log out now?"), "{text}");
        assert!(
            text.contains("Save what you") && text.contains("working on first"),
            "the reader is told what it costs them: {text}"
        );
        assert!(text.contains("Log out (y)"), "{text}");
        assert!(text.contains("Not now (n)"), "{text}");
    }

    #[test]
    fn the_summary_does_not_read_as_a_success_when_it_was_not() {
        let mut app = app();
        app.stage = Stage::Done;
        app.statuses = vec![Status::Ok; STEPS.len()];
        app.statuses[2] = Status::Failed;
        app.statuses[5] = Status::Ignored;
        app.landed = Some(landed());
        let text = render(&mut app, 110, 32);
        assert!(text.contains("1 failed step"), "{text}");
        assert!(
            text.contains("caelestia-install step"),
            "the way to retry: {text}"
        );
        assert!(text.contains(STEPS[2].name), "{text}");
        assert!(text.contains(STEPS[5].name), "{text}");
        assert!(text.contains("nothing was rolled back"), "{text}");
        assert!(
            !text.contains("log out and back in"),
            "a run that did not finish is not one to log out of: {text}"
        );
    }

    #[test]
    fn the_summary_counts_read_like_english() {
        let mut app = app();
        app.stage = Stage::Done;
        app.statuses = vec![Status::Ok; STEPS.len()];
        app.statuses[1] = Status::Warn;
        let text = render(&mut app, 110, 32);
        assert!(text.contains("finished with 1 warning."), "{text}");
        assert!(!text.contains("1 steps"), "no plurals of one: {text}");
        assert!(!text.contains("1 warnings"), "{text}");
    }

    #[test]
    fn the_summary_says_a_warning_once_and_names_the_step_that_raised_it() {
        let mut app = app();
        app.stage = Stage::Done;
        app.statuses = vec![Status::Ok; STEPS.len()];
        app.statuses[1] = Status::Warn;
        let text = render(&mut app, 110, 32);

        assert_eq!(
            text.matches("1 warning").count(),
            1,
            "one statement of the count, not three: {text}"
        );
        assert!(
            text.lines()
                .any(|line| line.contains("warned") && line.contains(STEPS[1].name)),
            "the step that warned is the useful part: {text}"
        );
    }

    #[test]
    fn the_confirm_card_says_what_will_happen_to_a_running_step() {
        let mut app = app();
        app.stage = Stage::Run;
        app.statuses[0] = Status::Running;
        app.ask(crate::app::Confirm::Quit);
        let text = render(&mut app, 100, 30);
        assert!(text.contains("Stop the install here?"), "{text}");
        assert!(
            text.contains("A step that is running") && text.contains("stopped first"),
            "true whether or not a step happens to be running: {text}"
        );
        assert!(text.contains("Stop (y)"), "the answer is a button: {text}");
        assert!(
            text.contains("Keep going (n)"),
            "and so is the one that keeps it, with the letter that picks it: {text}"
        );
        assert_eq!(app.confirm_focus, 1);
    }

    #[test]
    fn the_confirm_card_names_the_action_it_hands_over_to() {
        let mut app = app();
        app.confirm = Some(crate::app::Confirm::Handoff(crate::app::Action::Uninstall));
        app.overlay = Some(Overlay::Confirm);
        let text = render(&mut app, 100, 30);
        assert!(text.contains("Uninstall Caelestia"), "{text}");
        assert!(text.contains("hands the terminal over"), "{text}");
    }

    #[test]
    fn the_keymap_overlay_lists_the_keys_the_screens_answer_to() {
        let mut app = app();
        app.overlay = Some(Overlay::Keys);
        let text = render(&mut app, 100, 30);
        assert!(text.contains("KEYS"), "{text}");
        for key in ["ctrl+c", "?", "w", "l", "r / R"] {
            assert!(text.contains(key), "{key} is missing from {text}");
        }
    }

    #[test]
    fn the_full_screen_log_leaves_the_run_screen_behind() {
        let mut app = running(&[Status::Running], &[]);
        app.log = (0..100)
            .map(|index| LogLine::parse(&format!("  [INFO]  line {index}")))
            .collect();
        app.overlay = Some(Overlay::Log);
        let text = render(&mut app, 100, 34);
        assert!(text.contains("INSTALL LOG"), "{text}");
        let shown = (0..100)
            .filter(|index| text.contains(&format!("line {index}")))
            .count();
        assert!(shown > 20, "the overlay is the whole screen: {shown}");
    }

    #[test]
    fn every_screen_draws_something_at_the_smallest_size_it_accepts() {
        let stages = [
            Stage::Home,
            Stage::Privilege,
            Stage::Options,
            Stage::Auth,
            Stage::Run,
            Stage::Done,
        ];
        for stage in stages {
            let mut app = app();
            app.stage = stage;
            app.statuses[0] = Status::Running;
            let text = render(&mut app, ui::MIN_WIDTH, ui::MIN_HEIGHT);
            assert!(!text.trim().is_empty(), "{stage:?} drew nothing");
            assert!(
                text.contains("caelestia"),
                "{stage:?} lost its header: {text}"
            );
        }
    }

    #[test]
    fn the_frame_never_spills_out_of_the_terminal() {
        for (width, height) in [(60u16, 20u16), (80, 24), (100, 30), (200, 50)] {
            let mut app = app();
            app.stage = Stage::Run;
            app.statuses = vec![Status::Ok; STEPS.len()];
            app.failure = Some(crate::app::FailureCard::new(&STEPS[0], &[]));
            app.overlay = Some(Overlay::Failure);
            let text = render(&mut app, width, height);
            for row in text.lines() {
                assert!(
                    row.chars().count() <= width as usize,
                    "a row is wider than the terminal: {row:?}"
                );
            }
            assert_eq!(text.lines().count(), height as usize);
        }
    }

    #[test]
    fn the_keymap_the_screen_shows_is_the_keymap_it_answers_to() {
        let mut app = app();
        app.stage = Stage::Home;
        app.home = 1;
        let text = render(&mut app, 100, 30);
        assert!(text.contains("choose"), "{text}");
        assert!(text.contains("quit"), "{text}");

        let before = app.theme.mode;
        assert_eq!(
            app.key(crossterm::event::KeyEvent::new(
                crossterm::event::KeyCode::Char('t'),
                crossterm::event::KeyModifiers::NONE,
            )),
            Flow::Continue
        );
        assert_ne!(app.theme.mode, before, "'t theme' did not do what it says");
    }
}
