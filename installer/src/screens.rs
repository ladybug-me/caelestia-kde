// The screens. Each draws into the box the chrome hands out.

use ratatui::Frame;
use ratatui::layout::{Alignment, Constraint, Layout, Rect};
use ratatui::text::{Line, Span, Text};
use ratatui::widgets::{Block, Paragraph};

use crate::app::{Action, App, AuthMethod, Confirm, FailureCard, Overlay, Stage};
use crate::glyphs::Glyphs;
use crate::logline::{Kind, LogLine};
use crate::menu::{self, Entry};
use crate::steps::{Phase, STEPS, Status};
use crate::theme::{self, Role, Theme};
use crate::ui;

/// The width of the value column on the options screen.
const VALUE_COLUMN: usize = 12;

/// How wide the name column ever gets.
const NAME_CELL: usize = 52;

/// The label column of the failure card and the summary.
const LABEL_COLUMN: usize = 8;

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
        Stage::Review => review(frame, app, body),
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

// Home ------------------------------------------------------------------------------

fn home(frame: &mut Frame, app: &App, body: Rect) {
    let theme = &app.theme;
    let mark = banner(body);
    let named = mark.is_none();
    let mut head = identity(app, named);
    let credits = credits(app);

    // One composition, so the mark and the columns under it are placed together.
    let two_columns = ui::rail(body, 54).is_some();
    let mark_rows = if named {
        0
    } else {
        theme::SPLASH.len() as u16 + 1
    };
    let mut actions_lines = head.len() + 1;
    if two_columns {
        actions_lines = actions_lines.max(ACTIONS_PANEL as usize);
    } else {
        actions_lines += Action::ALL.len() + 1 + notice(app).len() + 1 + credits.len();
    }
    // A row of air under the frame, so the mark does not read as clipped.
    let pad = ui::slack(body, mark_rows + actions_lines as u16).max(1);

    let mut y = body.y + pad;
    if let Some(area) = mark {
        ui::prose(
            frame,
            Rect {
                y,
                height: area.height,
                ..body
            },
            mark_lines(app),
            theme.accent(),
        );
        y += mark_rows;
    }
    let below = Rect {
        y,
        height: body.height.saturating_sub(y - body.y),
        ..body
    };

    // Two columns where there is room: what the program is on the left, what it can do on the
    // right.
    if two_columns {
        let (left, right) = ui::rail(below, 54).expect("the width it was measured at");
        head.push(blank());
        head.extend(credits);
        ui::prose(frame, left, head, theme.body());
        actions_panel(frame, app, right);
        return;
    }

    // One column: the same content, in the order it is read.
    let column = ui::measure(below);
    head.push(blank());
    head.extend(actions(app, column.width));
    head.extend(notice(app));
    head.push(blank());
    head.extend(credits);
    ui::prose(frame, column, head, theme.body());
}

/// The action list in its panel, with anything the machine has to say under it.
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

/// The action panel: three rows and its borders.
const ACTIONS_PANEL: u16 = 5;

/// Below this the screen would be the mark and nothing else, so it is dropped rather than clipped.
const MARK_MIN_HEIGHT: u16 = 22;

/// Where the mark goes, or `None` where it does not fit whole.
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

/// The mark, one row per line.
fn mark_lines(app: &App) -> Vec<Line<'static>> {
    theme::SPLASH
        .iter()
        .map(|row| Line::from(Span::styled(row.to_string(), app.theme.accent())))
        .collect()
}

/// The name, where the mark has not already said it, and what this machine turned out to be.
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
    lines
}

/// What was found, in the line the actions beside it depend on.
fn state_line(app: &App) -> Line<'static> {
    let theme = &app.theme;
    let installed = app.installed();
    Line::from(Span::styled(
        if installed {
            "Caelestia is installed"
        } else {
            "nothing installed yet"
        },
        if installed {
            theme.body()
        } else {
            theme.muted()
        },
    ))
}

/// The three actions, each with its description on the same row, the way the installer this is
/// modeled on lists its options. The row the cursor is on is filled.
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
            let detail = if enabled {
                action.help()
            } else {
                "Caelestia is not installed"
            };
            if index == app.home && enabled {
                return ui::cursor_row(
                    theme,
                    glyphs,
                    &format!("{} {name}  {detail}", glyphs.cursor()),
                    width,
                );
            }
            let name_style = if enabled { theme.body() } else { theme.muted() };
            Line::from(vec![
                Span::styled("  ", name_style),
                Span::styled(name, name_style),
                Span::styled(format!("  {detail}"), theme.muted()),
            ])
        })
        .collect()
}

/// The column the action names are padded to, so every description starts in the same place.
fn name_column() -> usize {
    Action::ALL
        .iter()
        .map(|action| action.title().len())
        .max()
        .unwrap_or(0)
}

/// How wide the action list has to be.
fn actions_width(app: &App) -> u16 {
    let column = name_column();
    Action::ALL
        .iter()
        .map(|action| {
            let detail = if app.action_enabled(*action) {
                action.help()
            } else {
                "Caelestia is not installed"
            };
            2 + column + 2 + detail.chars().count()
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

// Privilege -------------------------------------------------------------------------

fn privilege(frame: &mut Frame, app: &App, body: Rect) {
    let theme = &app.theme;
    let glyphs = app.glyphs;
    // One measure for the whole card.
    const MEASURE: u16 = 56;
    let mut lines = vec![
        // Short enough to survive the narrowest terminal the installer draws in.
        Line::from(Span::styled(
            "Your password is sent to sudo and is not saved.".to_string(),
            theme.muted(),
        )),
        blank(),
    ];

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
    lines.push(Line::from(field));
    lines.push(blank());

    // The wait belongs where the answer will appear, so it reads as work rather than as a freeze.
    if app.checking.is_some() {
        lines.push(Line::from(vec![
            Span::styled(format!("{} ", ui::running_glyph(app)), theme.accent()),
            Span::styled("Checking your password...".to_string(), theme.muted()),
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

// This machine -----------------------------------------------------------------------

/// What was found before anything is decided.
fn detect(frame: &mut Frame, app: &App, body: Rect) {
    let theme = &app.theme;

    // Two columns where there is room: the findings on the left, what they mean on the right.
    if let Some((left, right)) = ui::rail(body, 44) {
        let pad = ui::slack(body, 9);
        let left = ui::dropped(left, pad);
        let right = ui::dropped(right, pad);

        let rows = findings(app);
        let label_width = label_column(&rows);
        let width = ui::panel_width(finding_width(&rows, label_width), left.width);
        let inner = ui::section(
            frame,
            ui::panel_rect(left, width, rows.len() as u16),
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

        // The verdict is prose, so it reads in a measure. Its border carries the answer, so the
        // panel needs no title: the headline inside says it.
        let border = verdict(app);
        let narrative = verdict_body(app, right.width.min(ui::PROSE_WIDTH));
        let width = ui::panel_width(
            narrative.iter().map(|line| line.width()).max().unwrap_or(0) as u16,
            right.width,
        );
        let inner = ui::section(
            frame,
            ui::panel_rect(right, width, narrative.len() as u16),
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

    // Reading order, budgeted by importance: the fact that changes the decision and the reason it
    // cannot go on survive a short terminal; the rows and the explanation give way.
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
    ui::prose_middle(frame, body, lines, theme.body());
}

/// The findings: what was looked for, what was found, and whether the install depends on it.
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

/// The label column is as wide as the labels in it.
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

/// How wide the findings panel has to be to hold its longest row.
fn finding_width(rows: &[(&'static str, String, bool)], label_width: usize) -> u16 {
    rows.iter()
        .map(|(_, value, _)| label_width + value.chars().count() + 3)
        .max()
        .unwrap_or(0) as u16
}

/// The fact this screen turns on, in one line.
fn headline(app: &App) -> Line<'static> {
    let theme = &app.theme;
    let glyphs = app.glyphs;
    if app.detection.installed {
        Line::from(vec![
            Span::styled(
                format!("{} ", glyphs.status(Status::Failed)),
                theme.error_text(),
            ),
            Span::styled("Caelestia is already installed.", theme.error_text()),
        ])
    } else {
        Line::from(vec![
            Span::styled(
                format!("{} ", glyphs.status(Status::Ok)),
                theme.status(Status::Ok),
            ),
            Span::styled("Nothing is installed in the way.", theme.body()),
        ])
    }
}

/// Why the screen will not go on: a missing precondition, or the reason a guard sent the user back.
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

/// What an existing install means for what happens next.
fn installed_explanation(app: &App, width: u16) -> Vec<String> {
    if !app.detection.installed {
        return Vec::new();
    }
    wrap(
        "Continuing will install over it: the shell configuration and the deployed files are \
         replaced. Your own configs are backed up first, and Update is the cheaper way to bring \
         an existing install up to date.",
        (width as usize).saturating_sub(4),
    )
}

/// Everything the verdict panel says: the fact, what it means, and why the screen will not go on.
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

/// What the findings mean, as the role the verdict's border carries. Ordinary "ready" stays
/// neutral, since color is spent on what is wrong.
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

// Auth -------------------------------------------------------------------------------

fn auth(frame: &mut Frame, app: &App, body: Rect) {
    let theme = &app.theme;
    let glyphs = app.glyphs;
    // One measure for the whole card, so the prose and the rows under it break in the same place.
    const MEASURE: u16 = 68;
    let mut lines: Vec<Line<'static>> = Vec::new();

    for line in wrap(
        "Installing needs root. The installer uses it only to run the steps.",
        MEASURE as usize,
    ) {
        lines.push(Line::from(Span::styled(line, theme.muted())));
    }
    lines.push(blank());

    if app.auth == Some(AuthMethod::External) {
        lines.push(Line::from(Span::styled(
            "Run this in another terminal:".to_string(),
            theme.body(),
        )));
        lines.push(Line::from(Span::styled(
            " sudo -v".to_string(),
            theme.accent(),
        )));
        lines.push(blank());
        lines.push(Line::from(Span::styled(
            "Then come back here and confirm.".to_string(),
            theme.muted(),
        )));
    } else {
        for (index, method) in app.auth_methods().iter().enumerate() {
            let chosen = index == app.cursor;
            let name_style = if chosen {
                theme.selected()
            } else {
                theme.body()
            };
            lines.push(Line::from(vec![
                Span::styled(
                    format!(" {} ", if chosen { glyphs.cursor() } else { " " }),
                    name_style,
                ),
                Span::styled(method.title().to_string(), name_style),
            ]));
            if let Some(note) = method.help() {
                for line in wrap(note, MEASURE as usize) {
                    lines.push(Line::from(Span::styled(
                        format!("      {line}"),
                        theme.muted(),
                    )));
                }
            }
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

// Options ---------------------------------------------------------------------------

fn options(frame: &mut Frame, app: &App, body: Rect) {
    let theme = &app.theme;

    // Two columns: the questions down the left as a map of the setup, the question on the right.
    if let Some((left, right)) = ui::rail(body, 30) {
        let pad = ui::slack(body, 11);
        let left = ui::dropped(left, pad);
        let right = ui::dropped(right, pad);

        let rail = question_rail(app);
        let width = ui::panel_width(question_rail_width(), left.width);
        let inner = ui::section(
            frame,
            ui::panel_rect(left, width, rail.len() as u16),
            theme,
            app.glyphs,
            None,
            Role::Rule,
        );
        ui::prose(frame, inner, rail, theme.body());

        question_pane(frame, app, right);
        return;
    }

    question_pane(frame, app, body);
}

/// The map of the setup: every question, and which one is on screen. How far along the wizard is,
/// is on the bar at the bottom of the frame, where it is for every screen.
fn question_rail(app: &App) -> Vec<Line<'static>> {
    let theme = &app.theme;
    let glyphs = app.glyphs;
    let mut lines: Vec<Line<'static>> = Vec::new();
    for index in 0..menu::question_count() {
        let (title, _) = menu::question(index);
        let here = index == app.question;
        let name_style = if here { theme.selected() } else { theme.body() };
        let changed = if app.question_changed(index) {
            format!("  {}", glyphs.changed())
        } else {
            String::new()
        };
        lines.push(Line::from(vec![
            Span::styled(
                format!(" {} ", if here { glyphs.cursor() } else { " " }),
                name_style,
            ),
            Span::styled(title.to_string(), name_style),
            Span::styled(changed, theme.accent()),
        ]));
    }
    lines
}

/// How wide the map has to be for its longest name plus its change marker.
fn question_rail_width() -> u16 {
    let mut width = 0;
    for index in 0..menu::question_count() {
        let (title, _) = menu::question(index);
        width = width.max(2 + title.len() + 2 + 2);
    }
    width as u16
}

/// One question and its answers.
fn question_pane(frame: &mut Frame, app: &App, area: Rect) {
    let theme = &app.theme;
    let rows = Layout::vertical([
        Constraint::Length(2),
        Constraint::Min(4),
        Constraint::Length(1),
        Constraint::Min(2),
    ])
    .areas::<4>(area);

    // What is being asked, and what the answer is for, on the one line: a caption under a heading
    // is one line of the screen spent saying what the heading already says.
    let (title, help) = menu::question(app.question);
    let mut heading_spans = vec![Span::styled(title.to_string(), theme.heading())];
    if !help.is_empty() {
        heading_spans.push(Span::styled(format!("  {help}"), theme.muted()));
    }
    if app.question_changed(app.question) {
        // A screen that has been edited says so before its rows are read.
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

    ui::prose(
        frame,
        rows[1],
        option_rows(app, rows[1].width),
        theme.body(),
    );

    let mut help_lines: Vec<Line<'static>> = Vec::new();
    let text = app.selected().map(Entry::help).unwrap_or_default();
    if !text.is_empty() {
        for line in wrap(text, (rows[3].width as usize).saturating_sub(2)) {
            help_lines.push(Line::from(Span::styled(line, theme.muted())));
        }
    }
    help_lines.extend(notice(app));
    ui::prose(frame, rows[3], help_lines, theme.body());
}

/// One row per option: cursor, changed marker, name, then the value in its own column.
pub(crate) fn option_rows(app: &App, width: u16) -> Vec<Line<'static>> {
    let theme = &app.theme;
    let glyphs = app.glyphs;
    // The name column takes what is left, up to a point; past that it is margin.
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
            Line::from(vec![
                Span::styled(
                    format!(" {} ", if chosen { glyphs.cursor() } else { " " }),
                    if chosen {
                        theme.selected()
                    } else {
                        theme.body()
                    },
                ),
                Span::styled(
                    if app.is_changed(entry) {
                        format!("{} ", glyphs.changed())
                    } else {
                        "  ".to_string()
                    },
                    theme.accent(),
                ),
                Span::styled(
                    format!(
                        "{:<width$}",
                        ui::fit(entry.title(), name_width, glyphs.ellipsis()),
                        width = name_width
                    ),
                    if chosen {
                        theme.selected()
                    } else {
                        theme.body()
                    },
                ),
                Span::styled(
                    format!("{:>width$}", value_of(entry, app), width = VALUE_COLUMN),
                    if chosen {
                        theme.selected()
                    } else {
                        theme.muted()
                    },
                ),
            ])
        })
        .collect()
}

/// The right-hand value column: one shape per kind of answer.
fn value_of(entry: &'static Entry, app: &App) -> String {
    let glyphs = app.glyphs;
    match entry {
        Entry::Toggle { .. } => on_off(menu::value(entry, &app.answers) == Some("true"), glyphs),
        Entry::Preset { .. } => on_off(app.preset_on(entry), glyphs),
        Entry::Choice { .. } => format!(
            "{} {} {}",
            glyphs.open(),
            menu::value(entry, &app.answers).unwrap_or_default(),
            glyphs.close()
        ),
        Entry::Submenu { .. } => glyphs.submenu().to_string(),
    }
}

fn on_off(on: bool, glyphs: Glyphs) -> String {
    if on {
        format!("{} on", glyphs.status(Status::Ok))
    } else {
        format!("{} off", glyphs.mark())
    }
}

// Review ----------------------------------------------------------------------------

fn review(frame: &mut Frame, app: &App, body: Rect) {
    let theme = &app.theme;
    let glyphs = app.glyphs;
    let (summary, list) = ui::review_layout(body);

    let will_run = STEPS
        .iter()
        .filter(|step| !crate::steps::is_skipped(step, &app.answers))
        .count();
    let changed = count_changed(app);
    ui::prose(
        frame,
        summary,
        vec![Line::from(vec![
            Span::styled(
                format!(
                    "{} of {} will run",
                    will_run,
                    ui::plural(STEPS.len(), "step", "steps")
                ),
                theme.body(),
            ),
            Span::styled(" · ", theme.muted()),
            Span::styled(
                if changed == 0 {
                    "every option is at its default".to_string()
                } else {
                    ui::plural(changed, "option changed", "options changed")
                },
                if changed == 0 {
                    theme.muted()
                } else {
                    theme.accent()
                },
            ),
        ])],
        theme.body(),
    );

    let (left, right) = review_columns(app);
    let total = left.len().max(right.as_ref().map_or(0, Vec::len));
    let rows = list.height.max(1) as usize;
    let offset = app.review_scroll.min(total.saturating_sub(rows)) as u16;

    let (left_area, right_area) = ui::columns(list);
    render_list(frame, left_area, left, offset);
    if let (Some(right_lines), Some(area)) = (right, right_area) {
        render_list(frame, area, right_lines, offset);
    }
    if total > rows {
        let bar = Rect {
            x: list.x + list.width.saturating_sub(1),
            width: 1,
            ..list
        };
        ui::scrollbar(frame, bar, app.review_scroll, total, theme, glyphs);
    }
}

fn render_list(frame: &mut Frame, area: Rect, lines: Vec<Line<'static>>, offset: u16) {
    frame.render_widget(Paragraph::new(Text::from(lines)).scroll((offset, 0)), area);
}

/// Every phase with its steps, as one block per phase.
fn review_sections(app: &App) -> Vec<Vec<Line<'static>>> {
    let theme = &app.theme;
    let glyphs = app.glyphs;
    let mut sections = Vec::new();
    for phase in Phase::ALL {
        let mut section: Vec<Line<'static>> = vec![Line::from(vec![
            Span::styled(phase.title().to_uppercase(), theme.title()),
            Span::styled(
                format!(
                    " · {} of {}",
                    STEPS.iter().filter(|step| step.phase == phase).count(),
                    ui::plural(STEPS.len(), "step", "steps")
                ),
                theme.muted(),
            ),
        ])];
        for step in STEPS.iter().filter(|step| step.phase == phase) {
            let skipped = crate::steps::is_skipped(step, &app.answers);
            let status = if skipped {
                Status::Skipped
            } else {
                Status::Pending
            };
            section.push(Line::from(vec![
                Span::styled(" ".to_string(), theme.body()),
                ui::gutter(glyphs.status(status), theme.status(status), glyphs),
                Span::styled(
                    ui::fit(step.name, 52, glyphs.ellipsis()),
                    if skipped { theme.muted() } else { theme.body() },
                ),
            ]));
        }
        section.push(blank());
        sections.push(section);
    }
    sections
}

/// The review list split into two columns where there is room, balanced by line count.
fn review_columns(app: &App) -> (Vec<Line<'static>>, Option<Vec<Line<'static>>>) {
    let sections = review_sections(app);
    let (_, list) = ui::review_layout(ui::body(app.area));
    if ui::columns(list).1.is_none() {
        return (sections.concat(), None);
    }

    let heights: Vec<usize> = sections.iter().map(Vec::len).collect();
    let total: usize = heights.iter().sum();
    let mut running = 0;
    let mut split = 0;
    for (index, height) in heights.iter().enumerate() {
        if running + height > total / 2 {
            break;
        }
        running += height;
        split = index + 1;
    }
    let mut left = Vec::new();
    let mut right = Vec::new();
    for (index, section) in sections.into_iter().enumerate() {
        if index < split {
            left.extend(section);
        } else {
            right.extend(section);
        }
    }
    (left, Some(right))
}

/// How many lines the review list holds: what the page keys clamp against.
pub fn review_total(app: &App) -> usize {
    let (left, right) = review_columns(app);
    left.len().max(right.as_ref().map_or(0, Vec::len))
}

fn count_changed(app: &App) -> usize {
    app.changed_answers()
}

// Run -------------------------------------------------------------------------------

fn run(frame: &mut Frame, app: &App) {
    let theme = &app.theme;
    let layout = app.run_layout();

    ui::prose(frame, layout.checklist, checklist(app), theme.body());
    ui::rule(frame, layout.rule, theme, app.glyphs);
    ui::prose(
        frame,
        layout.progress,
        vec![ui::progress(
            app.finished(),
            STEPS.len(),
            layout.progress.width,
            &format!(
                "{}/{} · {}",
                app.finished(),
                STEPS.len(),
                ui::elapsed(app.total_elapsed().as_secs())
            ),
            theme,
            app.glyphs,
        )],
        theme.body(),
    );
    log_pane(frame, app, layout.log, app.log_rows());
}

/// The checklist, one line per phase.
pub(crate) fn checklist(app: &App) -> Vec<Line<'static>> {
    let theme = &app.theme;
    let glyphs = app.glyphs;
    let mut lines = Vec::new();

    for phase in Phase::ALL {
        let status = app.phase_status(phase);
        let (done, total) = app.phase_progress(phase);
        let running = STEPS
            .iter()
            .enumerate()
            .any(|(index, step)| step.phase == phase && app.statuses[index] == Status::Running);
        let glyph = if running {
            ui::running_glyph(app)
        } else {
            glyphs.status(status)
        };
        let style = if running {
            theme.selected()
        } else {
            theme.status(status)
        };

        let mut spans = vec![
            ui::gutter(glyph, style, glyphs),
            Span::styled(
                phase.title().to_string(),
                if running {
                    theme.selected()
                } else {
                    theme.body()
                },
            ),
        ];
        if running {
            spans.push(Span::styled(
                format!(" · {done} of {total} steps"),
                theme.muted(),
            ));
        } else {
            spans.push(Span::styled(
                format!(" · {}", ui::plural(total, "step", "steps")),
                theme.muted(),
            ));
            let elapsed = app.phase_elapsed(phase);
            if elapsed.as_secs() > 0 {
                spans.push(Span::styled(
                    format!(" · {}", ui::elapsed(elapsed.as_secs())),
                    theme.muted(),
                ));
            }
            spans.extend(phase_notes(app, phase));
        }
        lines.push(Line::from(spans));

        if let Some(index) = phase_detail(app, phase) {
            lines.push(detail_line(app, index));
        }
    }
    lines
}

/// What did not go cleanly in a phase that has finished.
fn phase_notes(app: &App, phase: Phase) -> Vec<Span<'static>> {
    let theme = &app.theme;
    let count = |status: Status| {
        STEPS
            .iter()
            .enumerate()
            .filter(|(index, step)| step.phase == phase && app.statuses[*index] == status)
            .count()
    };
    let mut spans = Vec::new();
    for (count, one, many, style) in [
        (
            count(Status::Failed),
            "failure",
            "failures",
            theme.error_text(),
        ),
        (
            count(Status::Ignored),
            "ignored",
            "ignored",
            theme.ignored_text(),
        ),
        (
            count(Status::Warn),
            "warning",
            "warnings",
            theme.warn_text(),
        ),
        (count(Status::Skipped), "skipped", "skipped", theme.muted()),
    ] {
        if count > 0 {
            spans.push(Span::styled(
                format!(" · {}", ui::plural(count, one, many)),
                style,
            ));
        }
    }
    spans
}

/// The step of a phase that deserves a line of its own.
fn phase_detail(app: &App, phase: Phase) -> Option<usize> {
    let running = STEPS
        .iter()
        .enumerate()
        .find(|(index, step)| step.phase == phase && app.statuses[*index] == Status::Running);
    if let Some((index, _)) = running {
        return Some(index);
    }
    if !app.paused {
        return None;
    }
    STEPS
        .iter()
        .enumerate()
        .find(|(index, step)| step.phase == phase && app.statuses[*index].is_failure())
        .map(|(index, _)| index)
}

fn detail_line(app: &App, index: usize) -> Line<'static> {
    let theme = &app.theme;
    let glyphs = app.glyphs;
    let status = app.statuses[index];
    let running = status == Status::Running;
    let glyph = if running {
        ui::running_glyph(app)
    } else {
        glyphs.status(status)
    };
    let mut spans = vec![
        Span::styled("  ".to_string(), theme.body()),
        ui::gutter(
            glyph,
            if running {
                theme.selected()
            } else {
                theme.status(status)
            },
            glyphs,
        ),
        Span::styled(
            STEPS[index].name.to_string(),
            if running {
                theme.selected()
            } else {
                theme.body()
            },
        ),
        Span::raw("  "),
        ui::label_cell(status, theme),
    ];
    if let Some(elapsed) = app.step_elapsed(index) {
        spans.push(Span::styled(
            format!("  {}", ui::elapsed(elapsed.as_secs())),
            theme.muted(),
        ));
    }
    Line::from(spans)
}

/// How many rows the checklist needs, capped so the log is never squeezed out.
pub fn checklist_rows(app: &App) -> u16 {
    let lines = checklist(app).len() as u16;
    lines.min(ui::checklist_budget(ui::body(app.area))).max(1)
}

/// A log pane: a heading row, the lines, then a scrollbar. The run screen and the full-screen log
/// draw the same thing at different sizes.
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
    // The log sits on a raised block of its own.
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

    // The scrollbar column is only spent when there is something to scroll.
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
        ui::scrollbar(frame, bar_area, start, total, theme, glyphs);
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

// Done ------------------------------------------------------------------------------

fn done(frame: &mut Frame, app: &App, body: Rect) {
    let theme = &app.theme;
    let glyphs = app.glyphs;
    let tally = app.tally();
    let rows = Layout::vertical([Constraint::Min(6), Constraint::Length(2)]).areas::<2>(body);

    let (glyph, title, style) = if tally.failed > 0 {
        (
            glyphs.status(Status::Failed),
            format!(
                "finished with {}",
                ui::plural(tally.failed, "failed step", "failed steps")
            ),
            theme.error_text(),
        )
    } else if tally.ignored > 0 {
        (
            glyphs.status(Status::Ignored),
            format!(
                "finished with {}",
                ui::plural(tally.ignored, "ignored step", "ignored steps")
            ),
            theme.ignored_text(),
        )
    } else if tally.warn > 0 {
        (
            glyphs.status(Status::Warn),
            format!(
                "complete, with {}",
                ui::plural(tally.warn, "warning", "warnings")
            ),
            theme.warn_text(),
        )
    } else {
        (
            glyphs.status(Status::Ok),
            "complete".to_string(),
            theme.ok_text(),
        )
    };

    let mut lines: Vec<Line<'static>> = vec![
        Line::from(vec![
            Span::styled(format!(" {glyph} "), style),
            Span::styled("The install ".to_string(), theme.body()),
            Span::styled(title, theme.title()),
        ]),
        blank(),
        Line::from(Span::styled(
            format!("{} of {} finished", tally.ran(), tally.total),
            theme.body(),
        )),
    ];
    if tally.warn > 0 {
        lines.push(Line::from(Span::styled(
            format!(
                "{} reported warnings",
                ui::plural(tally.warn, "step", "steps")
            ),
            theme.warn_text(),
        )));
    }
    if tally.unresolved() > 0 {
        lines.push(Line::from(Span::styled(
            ui::plural(
                tally.unresolved(),
                "step needs your attention",
                "steps need your attention",
            ),
            theme.error_text(),
        )));
    }
    if tally.skipped > 0 {
        lines.push(Line::from(Span::styled(
            ui::plural(
                tally.skipped,
                "step was switched off",
                "steps were switched off",
            ),
            theme.muted(),
        )));
    }

    let unresolved: Vec<usize> = STEPS
        .iter()
        .enumerate()
        .filter(|(index, _)| matches!(app.statuses[*index], Status::Failed | Status::Ignored))
        .map(|(index, _)| index)
        .collect();
    if !unresolved.is_empty() {
        lines.push(blank());
        for index in unresolved {
            lines.push(ui::labeled(
                if app.statuses[index] == Status::Ignored {
                    "ignored"
                } else {
                    "failed"
                },
                format!(
                    "{}  ·  caelestia-install step {}",
                    STEPS[index].name, STEPS[index].id
                ),
                theme,
                LABEL_COLUMN,
            ));
        }
        lines.push(ui::labeled(
            "retry",
            "r here, or that command in a terminal".to_string(),
            theme,
            LABEL_COLUMN,
        ));
    }
    lines.push(ui::labeled(
        "log",
        app.log_path.display().to_string(),
        theme,
        LABEL_COLUMN,
    ));
    lines.extend(notice(app));

    let closing: Vec<Line<'static>> = if tally.unresolved() > 0 {
        vec![Line::from(Span::styled(
            "Nothing was rolled back: the steps that finished are still installed.".to_string(),
            theme.muted(),
        ))]
    } else {
        vec![Line::from(Span::styled(
            "Log out and back in so the new session settings apply.".to_string(),
            theme.muted(),
        ))]
    };
    ui::prose(frame, rows[0], lines, theme.body());
    ui::prose(frame, rows[1], closing, theme.body());
}

// Overlays --------------------------------------------------------------------------

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
        (62, entries.len() as u16 + 7),
        Role::Rule,
    );
    let mut lines: Vec<Line<'static>> = Vec::new();
    for (keys, what) in entries {
        lines.push(Line::from(vec![
            Span::styled(format!("  {keys:<12}"), theme.accent()),
            Span::styled(what.to_string(), theme.body()),
        ]));
    }
    lines.push(blank());
    // Two of these act on one screen rather than everywhere.
    for note in [
        "r and R reset answers, on the configure screens",
        "l, f and w work the log, on the run screen",
    ] {
        lines.push(Line::from(Span::styled(format!("  {note}"), theme.muted())));
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
        lines.push(Line::from(vec![
            Span::styled(
                format!(" {} ", if chosen { glyphs.cursor() } else { " " }),
                if chosen {
                    theme.selected()
                } else {
                    theme.muted()
                },
            ),
            Span::styled(
                format!("{} {:<8}", choice.key, choice.label),
                if chosen {
                    theme.selected()
                } else {
                    theme.body()
                },
            ),
            Span::styled(choice.help.to_string(), theme.muted()),
        ]));
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
    let (subject, question, border) = match app.confirm {
        Some(Confirm::Handoff(action)) => (
            action.title(),
            format!(
                "{} The installer closes and hands the terminal over.",
                action.help()
            ),
            Role::Accent,
        ),
        Some(Confirm::Install) => (
            "Install Caelestia now?",
            "Packages are installed, the configuration is deployed and the shell is built. This \
             is the last thing you are asked before that starts."
                .to_string(),
            Role::Accent,
        ),
        Some(Confirm::Quit) | None => (
            "Stop the install here?",
            "The installer stops and does not carry on. A step that is running is stopped first, so \
             nothing is left working in the background; work already done stays done."
                .to_string(),
            Role::Warn,
        ),
    };

    let inner = ui::panel(frame, frame.area(), theme, glyphs, None, (70, 12), border);
    let mut lines = vec![
        Line::from(Span::styled(subject.to_string(), theme.heading())),
        blank(),
    ];
    for line in wrap(&question, (inner.width as usize).saturating_sub(2)) {
        lines.push(Line::from(Span::styled(line, theme.muted())));
    }
    // What the yes actually starts, counted from the answers rather than asserted.
    if app.confirm == Some(Confirm::Install) {
        let will_run = STEPS
            .iter()
            .filter(|step| !crate::steps::is_skipped(step, &app.answers))
            .count();
        let skipped = STEPS.len() - will_run;
        let changed = count_changed(app);
        lines.push(blank());
        lines.push(Line::from(vec![
            Span::styled(
                format!(
                    " {} of {}",
                    will_run,
                    ui::plural(STEPS.len(), "step", "steps")
                ),
                theme.body(),
            ),
            Span::styled(
                if skipped == 0 {
                    " · nothing switched off".to_string()
                } else {
                    format!(" · {skipped} switched off")
                },
                theme.muted(),
            ),
        ]));
        lines.push(Line::from(Span::styled(
            if changed == 0 {
                " every option is at its default".to_string()
            } else {
                format!(" {} changed", ui::plural(changed, "option", "options"))
            },
            if changed == 0 {
                theme.muted()
            } else {
                theme.accent()
            },
        )));
    }
    lines.push(blank());
    ui::prose(frame, inner, lines, theme.body());
}

// Small shared pieces ----------------------------------------------------------------

fn blank() -> Line<'static> {
    Line::from("")
}

/// The transient answer to the last key, shown until the next one.
fn notice(app: &App) -> Vec<Line<'static>> {
    match &app.notice {
        Some(text) => vec![Line::from(Span::styled(text.clone(), app.theme.accent()))],
        None => Vec::new(),
    }
}

/// Wrap prose to a column without a `Paragraph`, for the places that lay lines out by hand.
fn wrap(text: &str, width: usize) -> Vec<String> {
    let width = width.max(20);
    let mut lines: Vec<String> = Vec::new();
    let mut current = String::new();
    for word in text.split_whitespace() {
        if current.is_empty() {
            current.push_str(word);
        } else if current.chars().count() + 1 + word.chars().count() <= width {
            current.push(' ');
            current.push_str(word);
        } else {
            lines.push(std::mem::take(&mut current));
            current.push_str(word);
        }
    }
    if !current.is_empty() {
        lines.push(current);
    }
    lines
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::app::{AuthMethod, Flow, Overlay, Stage};
    use crate::env::Env;
    use crossterm::event::{KeyCode, KeyEvent, KeyModifiers};
    use std::path::PathBuf;

    fn app() -> App {
        App::new(
            PathBuf::from("/tmp/caelestia"),
            PathBuf::from("/tmp/install.log"),
            Env::default(),
        )
    }

    /// The same, on a terminal that can draw a fill and a border.
    fn color_app() -> App {
        App::new(
            PathBuf::from("/tmp/caelestia"),
            PathBuf::from("/tmp/install.log"),
            Env {
                term: Some("xterm-256color".to_string()),
                colorterm: Some("truecolor".to_string()),
                ..Env::default()
            },
        )
    }

    /// The frame as cells rather than as text.
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
        // Inside the frame, and not over it.
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
        assert_eq!(
            buffer[(6, chosen)].bg,
            accent,
            "the cursor's row is not filled"
        );
        assert_ne!(buffer[(6, other)].bg, accent, "every row is filled");
    }

    #[test]
    fn a_wide_terminal_spends_its_width_on_a_second_column() {
        let mut wide = app();
        wide.stage = Stage::Options;
        wide.action = crate::app::Action::Install;
        let text = render(&mut wide, 235, 58);
        // The rail names every question; the pane names only the one being asked.
        assert!(text.contains("The install"), "no map:\n{text}");

        let mut narrow = app();
        narrow.stage = Stage::Options;
        narrow.action = crate::app::Action::Install;
        let text = render(&mut narrow, 80, 30);
        assert!(
            !text.contains("The install"),
            "a map in one column:\n{text}"
        );
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
            text.contains("Nothing is installed in the way"),
            "an install with a clear field says so: {text}"
        );
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
        // One cause, said once.
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

        // On a distribution it does know, the things it is missing are named.
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

        // The keymap overlay is a panel of a fixed size: every line of it has to fit inside.
        let mut overlay = app();
        overlay.overlay = Some(Overlay::Keys);
        let text = render(&mut overlay, 100, 34);
        for line in [
            "reset answers, on the configure screens",
            "work the log, on the run screen",
            "dark or light",
            "this list",
        ] {
            assert!(text.contains(line), "{line} is missing from:\n{text}");
        }
    }

    #[test]
    fn the_reason_a_screen_is_blocking_survives_a_short_terminal() {
        let problem = "The installer cannot go on until the above is sorted out.";
        // The worst case: an existing install, one blocker, and a guard that sent the user back,
        // at the smallest terminal the installer draws in.
        let worst = crate::app::Detection {
            distro: crate::distro::Distro::Unknown,
            kind: crate::install_kind::Kind::Source,
            installed: true,
            package_manager: None,
            quickshell: false,
            git: false,
        };

        // With room, the screen explains what continuing would do.
        let mut roomy = app();
        roomy.stage = Stage::Detect;
        roomy.detection = crate::app::Detection {
            distro: crate::distro::Distro::Arch,
            ..worst.clone()
        };
        assert!(render(&mut roomy, 100, 30).contains("cheaper way"));

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
            text.contains("cannot go on"),
            "and the answer to the key: {text}"
        );
        assert!(
            !text.contains("cheaper way"),
            "at the cost of the explanation: {text}"
        );
        // And the reading order holds: the fact comes before what continuing would do about it.
        let headline = text.find("already installed").expect("the headline");
        let explanation = text.find("Continuing will install over it");
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
        for phrase in [
            "root privileges",
            "Type your password here",
            "Authorize in another terminal",
        ] {
            assert!(text.contains(phrase), "{phrase} is missing from:\n{text}");
        }
        // Only the route that needs explaining carries a caption: what happens to a typed password
        // is said on the screen that asks for it, not twice.
        assert!(!text.contains("does not save it"), "{text}");
        assert!(
            text.contains("sudo -v"),
            "the other route says what to run: {text}"
        );
    }

    #[test]
    fn the_do_it_yourself_route_says_exactly_what_to_run() {
        let mut app = app();
        app.stage = Stage::Auth;
        app.auth = Some(AuthMethod::External);
        let text = render(&mut app, 100, 30);
        assert!(text.contains("sudo -v"), "{text}");
        assert!(text.contains("another terminal"), "{text}");
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
        assert!(text.contains("Appearance"), "{text}");
        assert!(
            !rows_with(&text, "packages it is made of").is_empty(),
            "the question's own help, on its heading: {text}"
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
        app.stage = Stage::Review;
        app.confirm = Some(Confirm::Install);
        app.overlay = Some(Overlay::Confirm);
        let text = render(&mut app, 100, 30);
        assert!(text.contains("Install Caelestia now?"), "{text}");
        assert!(
            text.contains(&format!("of {} steps", STEPS.len())),
            "the work is counted rather than asserted: {text}"
        );
        assert!(text.contains("every option is at its default"), "{text}");
    }

    fn char_key(app: &mut App, character: char) -> Flow {
        app.key(KeyEvent::new(KeyCode::Char(character), KeyModifiers::NONE))
    }

    /// The frame as text, so a test can read what a user would see.
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

    /// The rows that mention a phrase.
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
    fn a_wide_run_screen_draws_the_log_in_a_column_of_its_own() {
        let mut app = running(&[Status::Ok, Status::Running], &["* fetching packages"]);
        let text = render(&mut app, 200, 40);
        let phases = rows_with(&text, "Prepare");
        let log = rows_with(&text, "install log");
        let (phases, log) = (
            phases.first().expect("no phases"),
            log.first().expect("no log heading"),
        );
        // The phases and the log are in different columns, in the same rows.
        assert!(
            phases.find("Prepare").expect("a phase name") < 40,
            "the phases moved:\n{text}"
        );
        assert!(
            log.find("install log").expect("a log heading") > 40,
            "the log is not beside the phases:\n{text}"
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
        assert!(text.contains("not saved"), "{text}");
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
        // A password in flight used to leave the frame looking frozen, so people typed it again.
        let mut app = app();
        app.stage = Stage::Privilege;
        app.password = "hunter2".to_string();
        let (sender, receiver) = std::sync::mpsc::channel();
        app.checking = Some(receiver);
        let text = render(&mut app, 100, 30);
        assert!(text.contains("Checking your password"), "{text}");
        assert!(!text.contains("hunter2"), "{text}");

        // The answer arrives, and the line gives way to it.
        sender.send(false).expect("the answer fits");
        app.tick();
        let text = render(&mut app, 100, 30);
        assert!(text.contains("accepted"), "{text}");
        assert!(!text.contains("Checking your password"), "{text}");
    }

    #[test]
    fn an_app_question_with_nothing_left_to_ask_says_so_rather_than_going_blank() {
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
        assert!(text.contains("Nothing on this machine"), "{text}");
        assert!(
            text.contains("Applications"),
            "and it is still the question being asked: {text}"
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

        // And what is drawn agrees with what was built.
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
        // And a clipped row is still the same width as its neighbors.
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

        app.key(KeyEvent::new(KeyCode::Char(' '), KeyModifiers::NONE));
        let after = render(&mut app, 100, 30);
        assert!(after.contains("•"), "the change is marked: {after}");
        assert!(
            after.contains(app.selected().expect("a row").help()),
            "and the row's own help is on screen: {after}"
        );
        assert!(
            after.contains(menu::question(0).0),
            "the question being asked is named: {after}"
        );
    }
    #[test]
    fn the_review_screen_lists_every_phase_and_marks_what_is_switched_off() {
        let mut app = app();
        app.stage = Stage::Review;
        app.answers.insert("SKIP_SYSTEM_UPDATE", "true".to_string());
        let text = render(&mut app, 80, 40);
        assert!(text.contains("PREPARE"), "{text}");
        assert!(text.contains("FINALIZE"), "{text}");
        assert!(text.contains("Update system"), "{text}");
        assert!(
            text.contains("will run"),
            "the summary answers the question: {text}"
        );
        assert!(
            text.contains("– "),
            "and a switched-off step is marked: {text}"
        );
    }

    #[test]
    fn the_review_screen_scrolls_rather_than_cutting_the_list_off() {
        let mut app = app();
        app.stage = Stage::Review;
        let narrow = render(&mut app, 80, 24);
        assert!(narrow.contains("PREPARE"), "{narrow}");
        assert!(
            !narrow.contains("FINALIZE"),
            "the end of the list is below the fold: {narrow}"
        );

        app.review_scroll = app.review_limit();
        let scrolled = render(&mut app, 80, 24);
        assert!(scrolled.contains("FINALIZE"), "{scrolled}");
    }

    #[test]
    fn the_review_screen_uses_two_columns_where_there_is_room() {
        let mut app = app();
        app.stage = Stage::Review;
        let wide = render(&mut app, 140, 30);
        // Both the first phase and the last are on screen at once, which one column could not do.
        assert!(wide.contains("PREPARE"), "{wide}");
        assert!(wide.contains("FINALIZE"), "{wide}");
    }

    #[test]
    fn the_run_screen_shows_the_worst_of_each_phase_on_one_line() {
        let mut app = running(
            &[
                Status::Ok,
                Status::Warn,
                Status::Ok,
                Status::Ok,
                Status::Running,
            ],
            &["  [INFO]  syncing databases", "  [WARN]  slow mirror"],
        );
        let text = render(&mut app, 100, 30);
        assert!(text.contains("Prepare"), "{text}");
        assert!(
            text.contains("1 warning"),
            "the phase says what happened: {text}"
        );
        assert!(text.contains("Packages"), "{text}");
        assert!(
            text.contains("1 of 2 steps"),
            "and how far along it is: {text}"
        );
        assert!(text.contains("RUNNING"), "the state is spelled out: {text}");
        assert!(
            !text.contains("Update submodules"),
            "past steps are collapsed: {text}"
        );
    }

    #[test]
    fn the_run_screen_gives_the_log_the_room_it_never_had() {
        let mut app = running(&[Status::Running], &["  [INFO]  one", "  [INFO]  two"]);
        app.log = (0..40)
            .map(|index| LogLine::parse(&format!("  [INFO]  line {index}")))
            .collect();
        let text = render(&mut app, 80, 24);
        // On a 24-row terminal the old screen showed two lines of log; this one shows a pane.
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

    #[test]
    fn the_summary_reads_as_a_success_when_it_was_one() {
        let mut app = app();
        app.stage = Stage::Done;
        app.statuses = vec![Status::Ok; STEPS.len()];
        let text = render(&mut app, 100, 30);
        assert!(
            text.contains("Install complete") || text.contains("complete"),
            "{text}"
        );
        assert!(text.contains("17 of 17 finished"), "{text}");
        assert!(text.contains("Log out and back in"), "{text}");
    }

    #[test]
    fn the_summary_does_not_read_as_a_success_when_it_was_not() {
        let mut app = app();
        app.stage = Stage::Done;
        app.statuses = vec![Status::Ok; STEPS.len()];
        app.statuses[2] = Status::Failed;
        app.statuses[5] = Status::Ignored;
        let text = render(&mut app, 110, 32);
        assert!(text.contains("1 failed step"), "{text}");
        assert!(text.contains("2 steps need your attention"), "{text}");
        assert!(
            text.contains("caelestia-install step"),
            "the way to retry: {text}"
        );
        assert!(text.contains("Nothing was rolled back"), "{text}");
    }

    #[test]
    fn the_summary_counts_read_like_english() {
        let mut app = app();
        app.stage = Stage::Done;
        app.statuses = vec![Status::Ok; STEPS.len()];
        app.statuses[1] = Status::Warn;
        let text = render(&mut app, 110, 32);
        assert!(text.contains("1 step"), "{text}");
        assert!(text.contains("1 warning"), "{text}");
        assert!(!text.contains("1 steps"), "no plurals of one: {text}");
        assert!(!text.contains("1 warnings"), "{text}");
    }

    #[test]
    fn the_confirm_card_says_what_will_happen_to_a_running_step() {
        let mut app = app();
        app.stage = Stage::Run;
        app.statuses[0] = Status::Running;
        app.confirm = Some(crate::app::Confirm::Quit);
        app.overlay = Some(Overlay::Confirm);
        let text = render(&mut app, 100, 30);
        assert!(text.contains("Stop the install here?"), "{text}");
        assert!(
            text.contains("A step that is running") && text.contains("stopped first"),
            "true whether or not a step happens to be running: {text}"
        );
        assert!(text.contains("y yes"), "{text}");
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
            Stage::Review,
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

        // And the handler agrees with the hint it printed.
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
