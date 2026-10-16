// The chrome and the grid everything else is built on: one frame round the terminal, one filled
// bar along its bottom, and the layout functions the screens and the key handlers share.

use ratatui::Frame;
use ratatui::layout::{Alignment, Constraint, Layout, Rect};
use ratatui::style::{Modifier, Style};
use ratatui::text::{Line, Span, Text};
use ratatui::widgets::{Block, Clear, Paragraph, Wrap};

use crate::app::App;
use crate::glyphs::{Glyphs, LABEL_CELL, status_label};
use crate::steps::Status;
use crate::theme::{NAME, Role, Theme};

/// Below this the TUI says so rather than drawing a broken frame.
pub const MIN_WIDTH: u16 = 60;
pub const MIN_HEIGHT: u16 = 20;

/// The widest a column of prose may get; the rest of the width goes to the frame and the panels.
pub const PROSE_WIDTH: u16 = 96;

/// The one left gutter every screen indents by.
pub const INDENT: u16 = 2;

/// The log pane's first row is a heading, not a line of log.
const LOG_HEADER_ROWS: u16 = 1;

/// One hint in the footer.
pub struct Key {
    pub keys: &'static str,
    pub what: &'static str,
}

pub const fn key(keys: &'static str, what: &'static str) -> Key {
    Key { keys, what }
}

/// What the frame says on its top edge.
pub struct Header {
    pub left: String,
    pub right: String,
}

/// What is left for a screen to draw in.
pub struct Chrome {
    pub body: Rect,
}

/// Where the frame puts the body and the bar; drawing and paging both come through here.
struct Rows {
    body: Rect,
    bar: Rect,
}

fn rows(area: Rect) -> Rows {
    let inner = Block::bordered().inner(area);
    let rows = Layout::vertical([Constraint::Min(1), Constraint::Length(1)]).areas::<2>(inner);
    Rows {
        body: rows[0],
        bar: rows[1],
    }
}

/// Draw the frame and the bar. `None` when the terminal is too small, having said so.
pub fn chrome(
    frame: &mut Frame,
    theme: &Theme,
    glyphs: Glyphs,
    header: &Header,
    keys: &[Key],
    counter: Option<&str>,
) -> Option<Chrome> {
    let area = frame.area();
    frame.render_widget(Block::default().style(theme.surface()), area);

    if area.width < MIN_WIDTH || area.height < MIN_HEIGHT {
        too_small(frame, area, theme, glyphs);
        return None;
    }

    let edge = Block::bordered()
        .border_set(glyphs.frame_border())
        .border_style(theme.frame())
        .title_top(where_you_are(theme, header))
        .title_top(what_this_is(theme, header));
    frame.render_widget(edge, area);

    let rows = rows(area);
    frame.render_widget(Block::default().style(theme.bar()), rows.bar);
    status_bar(frame, rows.bar, theme, keys, counter);

    Some(Chrome {
        body: content(rows.body),
    })
}

/// The frame's top-left corner.
fn where_you_are(theme: &Theme, header: &Header) -> Line<'static> {
    Line::from(vec![
        Span::styled(" ".to_string(), theme.title()),
        Span::styled(NAME.to_string(), theme.title()),
        Span::styled(format!(" · {} ", header.left), theme.muted()),
    ])
}

/// The machine context, in the frame's top-right corner.
fn what_this_is(theme: &Theme, header: &Header) -> Line<'static> {
    Line::from(Span::styled(format!(" {} ", header.right), theme.muted())).right_aligned()
}

/// The box a screen draws into; the key handlers ask for the same one.
pub fn body(area: Rect) -> Rect {
    content(rows(area).body)
}

/// A horizontal rule, the only separator the TUI uses.
pub fn rule(frame: &mut Frame, area: Rect, theme: &Theme, glyphs: Glyphs) {
    if area.height == 0 || area.width == 0 {
        return;
    }
    let line = Line::from(Span::styled(
        glyphs.rule().to_string().repeat(area.width as usize),
        theme.rule(),
    ));
    frame.render_widget(Paragraph::new(line), area);
}

/// The body's box: every column the frame gave it, indented by the gutter.
pub fn content(area: Rect) -> Rect {
    let indent = INDENT.min(area.width / 2);
    Rect {
        x: area.x + indent,
        y: area.y,
        width: area.width.saturating_sub(indent * 2).max(1),
        height: area.height,
    }
}

/// The column a screen of prose reads in.
pub fn measure(area: Rect) -> Rect {
    Rect {
        width: area.width.min(PROSE_WIDTH),
        ..area
    }
}

/// The same area, started `rows` further down.
pub fn dropped(area: Rect, rows: u16) -> Rect {
    let rows = rows.min(area.height.saturating_sub(1));
    Rect {
        y: area.y + rows,
        height: area.height - rows,
        ..area
    }
}

/// How far down a short block starts inside a tall area, so it is not pinned to the top edge.
pub fn slack(area: Rect, height: u16) -> u16 {
    (area.height.saturating_sub(height) / 2).min(16)
}

/// The gap between columns, and the least room the second one gets before a screen stays one.
const RAIL_GAP: u16 = 4;
const PARTNER_MIN: u16 = 52;

/// The narrowest a panel may be, so a panel around two short rows still reads as one.
const MIN_PANEL: u16 = 24;

/// The width a panel takes: as wide as its widest row, and never wider than the measure.
pub fn panel_width(content: u16, room: u16) -> u16 {
    let cap = (PROSE_WIDTH + 2).min(room);
    (content + 2).clamp(MIN_PANEL.min(cap), cap)
}

/// A narrow column on the left and the rest beside it, where there is room for both.
pub fn rail(area: Rect, width: u16) -> Option<(Rect, Rect)> {
    let width = width.min(area.width / 2);
    if area.width < width + RAIL_GAP + PARTNER_MIN {
        return None;
    }
    Some((
        Rect { width, ..area },
        Rect {
            x: area.x + width + RAIL_GAP,
            width: area.width - width - RAIL_GAP,
            ..area
        },
    ))
}

/// The rectangle a panel of `rows` content rows takes: its borders and nothing more.
pub fn panel_rect(area: Rect, width: u16, rows: u16) -> Rect {
    Rect {
        width,
        height: (rows + 2).min(area.height),
        ..area
    }
}

/// A panel inside a screen. The border carries the role, so a panel that *is* the message looks
/// like one before it is read. An untitled panel is a group of rows, not a section.
pub fn section(
    frame: &mut Frame,
    rect: Rect,
    theme: &Theme,
    glyphs: Glyphs,
    title: Option<&str>,
    border: Role,
) -> Rect {
    if rect.width < 4 || rect.height < 3 {
        return rect;
    }
    let edge = theme.style(border);
    let mut block = Block::bordered()
        .border_set(glyphs.border())
        .border_style(edge);
    if let Some(title) = title {
        let title_style = if border == Role::Rule {
            theme.heading()
        } else {
            edge.add_modifier(Modifier::BOLD)
        };
        block = block.title_top(Line::from(vec![
            Span::styled(" ".to_string(), edge),
            Span::styled(title.to_string(), title_style),
            Span::styled(" ".to_string(), edge),
        ]));
    }
    let inner = block.inner(rect);
    frame.render_widget(block, rect);
    inner
}

/// The row the cursor is on, filled right across its column.
pub fn cursor_row(theme: &Theme, glyphs: Glyphs, text: &str, width: u16) -> Line<'static> {
    let text = fit(text, width as usize, glyphs.ellipsis());
    let padding = (width as usize).saturating_sub(text.chars().count());
    Line::from(Span::styled(
        format!("{text}{}", " ".repeat(padding)),
        theme.bar().add_modifier(Modifier::BOLD),
    ))
}

/// A centered card of prose, sized to a measure. The caller wraps its lines to the same measure,
/// since a line that does not fit is one the card clips.
pub fn card(
    frame: &mut Frame,
    area: Rect,
    theme: &Theme,
    glyphs: Glyphs,
    title: Option<&str>,
    measure: u16,
    content: Vec<Line<'static>>,
) {
    let width = (measure + 4).min(area.width);
    let height = (content.len() as u16 + 2).min(area.height).max(3);
    let inner = section(
        frame,
        centered(area, width, height),
        theme,
        glyphs,
        title,
        Role::Rule,
    );
    prose(frame, inner, content, theme.body());
}

pub struct RunLayout {
    pub checklist: Rect,
    pub rule: Rect,
    pub progress: Rect,
    pub log: Rect,
}

/// A centered modal.
pub fn panel(
    frame: &mut Frame,
    area: Rect,
    theme: &Theme,
    glyphs: Glyphs,
    title: Option<&str>,
    size: (u16, u16),
    border: Role,
) -> Rect {
    let width = size.0.min(area.width.saturating_sub(2)).max(8);
    let height = size.1.min(area.height).max(3);
    frame_panel(
        frame,
        centered(area, width, height),
        theme,
        glyphs,
        title,
        border,
    )
}

/// The same modal, placed by the caller.
pub fn frame_panel(
    frame: &mut Frame,
    rect: Rect,
    theme: &Theme,
    glyphs: Glyphs,
    title: Option<&str>,
    border: Role,
) -> Rect {
    frame.render_widget(Clear, rect);
    let edge = theme.style(border);
    let mut block = Block::bordered()
        .border_set(glyphs.border())
        .border_style(edge);
    if let Some(title) = title {
        block = block.title(format!(" {title} ")).title_style(edge);
    }
    let inner = block.inner(rect);
    frame.render_widget(block, rect);
    inner
}

/// The gutter a status glyph sits in, so the names beside it never shift.
pub fn gutter(text: &str, style: Style, glyphs: Glyphs) -> Span<'static> {
    Span::styled(
        format!(" {:>width$} ", text, width = glyphs.status_cell()),
        style,
    )
}

/// The state, spelled out, padded to a column of its own.
pub fn label_cell(status: Status, theme: &Theme) -> Span<'static> {
    Span::styled(
        format!("{:>width$}", status_label(status), width = LABEL_CELL),
        theme.status(status),
    )
}

/// The spinner where the terminal can show one, the static glyph where it cannot.
pub fn running_glyph(app: &App) -> &'static str {
    if app.env.animates() {
        app.glyphs.spinner(app.spinner)
    } else {
        app.glyphs.status(Status::Running)
    }
}

/// `label   value`, with the label in a fixed column.
pub fn labeled(label: &str, value: String, theme: &Theme, width: usize) -> Line<'static> {
    Line::from(vec![
        Span::styled(format!("  {label:<width$}  "), theme.muted()),
        Span::styled(value, theme.body()),
    ])
}

/// A progress bar with its caption; the bar never grows past a readable length.
pub fn progress(
    filled: usize,
    total: usize,
    width: u16,
    caption: &str,
    theme: &Theme,
    glyphs: Glyphs,
) -> Line<'static> {
    const LONGEST_BAR: usize = 40;
    let suffix = format!(" {caption}");
    let room = (width as usize).saturating_sub(suffix.len());
    let bar = room.min(LONGEST_BAR);
    let done = if total == 0 {
        0
    } else {
        (filled * bar).div_ceil(total).min(bar)
    };
    let mut spans = vec![
        Span::styled(glyphs.bar_full().to_string().repeat(done), theme.accent()),
        Span::styled(
            glyphs.bar_empty().to_string().repeat(bar - done),
            theme.rule(),
        ),
    ];
    if room >= suffix.len() {
        spans.push(Span::styled(suffix, theme.muted()));
    }
    Line::from(spans)
}

/// A one-column scrollbar, drawn only where there is something to scroll.
pub fn scrollbar(
    frame: &mut Frame,
    area: Rect,
    offset: usize,
    total: usize,
    theme: &Theme,
    glyphs: Glyphs,
) {
    if area.height == 0 || area.width == 0 || total <= area.height as usize {
        return;
    }
    let viewport = area.height as usize;
    let (from, to) = thumb_range(offset, total, viewport);
    let lines: Vec<Line> = (0..viewport)
        .map(|row| {
            if row >= from && row < to {
                Line::from(Span::styled(glyphs.thumb().to_string(), theme.accent()))
            } else {
                Line::from(Span::styled(glyphs.track().to_string(), theme.rule()))
            }
        })
        .collect();
    frame.render_widget(Paragraph::new(Text::from(lines)), area);
}

/// Where the thumb sits, as a range of rows. A pane that fits its content gets no thumb.
pub fn thumb_range(offset: usize, total: usize, viewport: usize) -> (usize, usize) {
    if viewport == 0 {
        return (0, 0);
    }
    if total <= viewport {
        return (0, 0);
    }
    let thumb = (viewport * viewport / total).max(1).min(viewport);
    let furthest = total - viewport;
    let position = (offset.min(furthest) * (viewport - thumb))
        .checked_div(furthest)
        .unwrap_or(0);
    (position, position + thumb)
}

/// How many rows of log fit in the pane.
pub fn log_rows(log: Rect) -> u16 {
    log.height.saturating_sub(LOG_HEADER_ROWS)
}

/// The most rows the phase checklist may take, leaving the log the room to be read.
pub fn checklist_budget(body: Rect) -> u16 {
    body.height.saturating_sub(6).max(2)
}

/// The column the phase list takes where the run screen has room to put the log beside it.
const PHASE_COLUMN: u16 = 46;

/// Where the phases and the log go: side by side where there is room, stacked where there is not.
pub fn run_layout(body: Rect, checklist_rows: u16) -> RunLayout {
    if let Some((left, right)) = rail(body, PHASE_COLUMN) {
        let rows = Layout::vertical([
            Constraint::Length(checklist_rows),
            Constraint::Length(1),
            Constraint::Length(1),
            Constraint::Min(0),
        ])
        .areas::<4>(left);
        return RunLayout {
            checklist: rows[0],
            rule: rows[1],
            progress: rows[2],
            log: right,
        };
    }
    let rows = Layout::vertical([
        Constraint::Length(checklist_rows),
        Constraint::Length(1),
        Constraint::Length(1),
        Constraint::Min(3),
    ])
    .areas::<4>(body);
    RunLayout {
        checklist: rows[0],
        rule: rows[1],
        progress: rows[2],
        log: rows[3],
    }
}

/// The summary and the list of the review screen.
pub fn review_layout(body: Rect) -> (Rect, Rect) {
    let rows = Layout::vertical([
        Constraint::Length(1),
        Constraint::Length(1),
        Constraint::Length(1),
        Constraint::Min(3),
    ])
    .areas::<4>(body);
    (rows[1], rows[3])
}

/// Two columns of phases where there is room for them, one where there is not.
pub fn columns(list: Rect) -> (Rect, Option<Rect>) {
    if list.width < 90 {
        return (list, None);
    }
    let width = list.width.saturating_sub(4) / 2;
    let left = Rect { width, ..list };
    let right = Rect {
        x: list.x + width + 4,
        width,
        ..list
    };
    (left, Some(right))
}

/// Render prose into a box, wrapping rather than clipping it.
pub fn prose(frame: &mut Frame, area: Rect, lines: Vec<Line<'static>>, style: Style) {
    frame.render_widget(
        Paragraph::new(Text::from(lines))
            .style(style)
            .wrap(Wrap { trim: false }),
        area,
    );
}

/// The same text, started a third of the way down a taller area.
pub fn prose_middle(frame: &mut Frame, area: Rect, lines: Vec<Line<'static>>, style: Style) {
    let pad = slack(area, lines.len() as u16);
    prose(frame, dropped(area, pad), lines, style);
}

/// The full-screen log's own geometry; drawing and paging both ask for it here.
pub fn log_overlay_rect(area: Rect) -> Rect {
    let width = area.width.saturating_sub(8).max(10);
    let height = area.height.saturating_sub(4).max(6);
    centered(area, width, height)
}

pub fn log_overlay_inner(area: Rect) -> Rect {
    let rect = log_overlay_rect(area);
    Rect {
        x: rect.x + 1,
        y: rect.y + 1,
        width: rect.width.saturating_sub(2),
        height: rect.height.saturating_sub(2),
    }
}

pub fn log_overlay_rows(area: Rect) -> u16 {
    log_overlay_inner(area)
        .height
        .saturating_sub(LOG_HEADER_ROWS)
}

/// Text cut to a column, with a marker rather than a silent chop.
pub fn fit(text: &str, width: usize, ellipsis: &str) -> String {
    if text.chars().count() <= width {
        return text.to_string();
    }
    let keep = width.saturating_sub(ellipsis.chars().count());
    let mut out: String = text.chars().take(keep).collect();
    out.push_str(ellipsis);
    out
}

pub fn plural(count: usize, one: &str, many: &str) -> String {
    if count == 1 {
        format!("{count} {one}")
    } else {
        format!("{count} {many}")
    }
}

pub fn elapsed(seconds: u64) -> String {
    let (hours, minutes, seconds) = (seconds / 3600, (seconds % 3600) / 60, seconds % 60);
    if hours > 0 {
        format!("{hours}:{minutes:02}:{seconds:02}")
    } else {
        format!("{minutes}:{seconds:02}")
    }
}

/// The filled bar along the bottom: the keys, and where the user is in the flow.
fn status_bar(frame: &mut Frame, area: Rect, theme: &Theme, keys: &[Key], counter: Option<&str>) {
    if area.height == 0 {
        return;
    }
    let counter_width = counter.map_or(0, |text| text.chars().count() as u16 + 2);
    let available = area.width.saturating_sub(counter_width);

    frame.render_widget(Paragraph::new(hints(theme, keys, available)), area);
    if let Some(counter) = counter {
        let right = Rect {
            x: area.x + area.width - counter_width,
            width: counter_width,
            ..area
        };
        frame.render_widget(
            Paragraph::new(Line::from(Span::styled(
                format!("{counter} "),
                theme.on_bar(),
            )))
            .alignment(Alignment::Right),
            right,
        );
    }
}

/// The keymap for a screen, whole groups only, dropping the least important hint first: the caller
/// lists them in priority order.
fn hints(theme: &Theme, keys: &[Key], width: u16) -> Line<'static> {
    let mut spans: Vec<Span<'static>> = Vec::new();
    let mut used = 0usize;
    for (index, key) in keys.iter().enumerate() {
        let group = format!("{} {}", key.keys, key.what);
        let separator = if index == 0 { 1 } else { 3 };
        let cost = group.len() + separator;
        if index > 0 && used + cost > width as usize {
            break;
        }
        // On a fill, weight is the only channel left: keys bold, what they do plain.
        spans.push(Span::styled(
            if index == 0 {
                " ".to_string()
            } else {
                "   ".to_string()
            },
            theme.bar(),
        ));
        spans.push(Span::styled(key.keys.to_string(), theme.bar_key()));
        spans.push(Span::styled(format!(" {}", key.what), theme.on_bar()));
        used += cost;
    }
    Line::from(spans)
}

fn too_small(frame: &mut Frame, area: Rect, theme: &Theme, glyphs: Glyphs) {
    let lines = vec![
        Line::from(Span::styled(
            "terminal too small".to_string(),
            theme.title(),
        )),
        Line::from(""),
        Line::from(Span::styled(
            format!(
                "this needs {}x{}, and this one is {}x{}",
                MIN_WIDTH, MIN_HEIGHT, area.width, area.height
            ),
            theme.muted(),
        )),
    ];
    let height = lines.len() as u16 + 4;
    let inner = panel(
        frame,
        area,
        theme,
        glyphs,
        Some("RESIZE"),
        (56, height),
        Role::Rule,
    );
    prose(frame, inner, lines, theme.body());
}

fn centered(area: Rect, width: u16, height: u16) -> Rect {
    let width = width.min(area.width);
    let height = height.min(area.height);
    Rect {
        x: area.x + (area.width - width) / 2,
        y: area.y + area.height.saturating_sub(height) / 2,
        width,
        height,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn body(width: u16, height: u16) -> Rect {
        Rect {
            x: 0,
            y: 0,
            width,
            height,
        }
    }

    #[test]
    fn the_content_box_never_escapes_its_area() {
        for (width, height) in [(60, 20), (80, 24), (100, 30), (200, 60)] {
            let area = body(width, height);
            let inner = content(area);
            assert!(inner.x + inner.width <= area.width, "{width}x{height}");
            assert!(inner.width > 0, "{width}x{height}");
        }
    }

    #[test]
    fn a_wide_terminal_gives_its_width_to_the_content_box() {
        let inner = content(body(240, 60));
        assert_eq!(inner.width, 240 - INDENT * 2);
        assert_eq!(inner.x, INDENT);
    }

    #[test]
    fn a_column_of_prose_stops_at_the_measure() {
        let wide = measure(body(240, 20));
        assert_eq!(wide.width, PROSE_WIDTH);
        assert_eq!(wide.x, 0);
        assert_eq!(measure(body(80, 20)).width, 80);
    }

    #[test]
    fn the_frame_leaves_the_body_a_box_inside_the_terminal() {
        for (width, height) in [(60, 20), (100, 30), (235, 58)] {
            let area = body(width, height);
            let chrome = content(rows(area).body);
            assert!(chrome.width > 0 && chrome.height > 0, "{width}x{height}");
            assert!(chrome.x + chrome.width <= width, "{width}x{height}");
            assert!(chrome.y + chrome.height <= height, "{width}x{height}");
            // The bar is the last row inside the frame.
            assert_eq!(rows(area).bar.y, height - 2, "{width}x{height}");
            assert_eq!(rows(area).body.height, height - 3, "{width}x{height}");
        }
    }

    #[test]
    fn the_log_keeps_its_rows_whatever_the_terminal_size() {
        for height in MIN_HEIGHT..=60 {
            let area = body(100, height);
            let budget = checklist_budget(area);
            let layout = run_layout(area, budget);
            assert!(
                log_rows(layout.log) >= 3,
                "{height} rows left the log {}",
                log_rows(layout.log)
            );
            assert!(
                layout.log.y + layout.log.height <= area.height,
                "{height} rows overflow"
            );
            assert_eq!(layout.checklist.y, 0);
            assert_eq!(layout.progress.y, budget + 1);
        }
    }

    #[test]
    fn the_checklist_is_capped_so_the_log_is_never_squeezed_out() {
        assert_eq!(checklist_budget(body(100, MIN_HEIGHT)), MIN_HEIGHT - 6);
        assert!(checklist_budget(body(100, 4)) >= 2);
    }

    #[test]
    fn a_panel_is_only_as_tall_as_what_is_in_it() {
        let area = body(200, 40);
        assert_eq!(panel_rect(area, 60, 5).height, 7);
        assert_eq!(panel_rect(area, 60, 5).y, area.y);
        assert_eq!(panel_rect(area, 60, 5).width, 60);
        assert_eq!(panel_rect(area, 60, 100).height, 40);
    }

    #[test]
    fn a_rail_appears_only_where_both_columns_can_be_read() {
        assert!(rail(body(96, 30), 44).is_none(), "a narrow terminal split");
        let (left, right) = rail(body(235, 58), 44).expect("a wide one did not split");
        assert_eq!(left.width, 44);
        assert!(right.x >= left.width + RAIL_GAP);
        assert!(right.x + right.width <= 235);
        assert!(
            right.width >= PARTNER_MIN,
            "the second column is too narrow"
        );
        assert_eq!(left.height, 58);
    }

    #[test]
    fn a_panel_is_measured_from_its_contents_and_never_overruns_its_room() {
        assert_eq!(panel_width(0, 200), MIN_PANEL);
        assert_eq!(panel_width(30, 200), 32);
        assert_eq!(panel_width(200, 200), PROSE_WIDTH + 2);
        assert_eq!(panel_width(200, 60), 60);
        assert_eq!(panel_width(200, 4), 4);
    }

    #[test]
    fn a_wide_run_screen_puts_the_log_beside_the_phases() {
        let area = body(240, 40);
        let layout = run_layout(area, 8);
        assert_eq!(layout.log.x, layout.checklist.x + PHASE_COLUMN + RAIL_GAP);
        assert_eq!(layout.log.height, area.height, "the log is only half tall");
        assert!(layout.log.x + layout.log.width <= area.width);
        assert!(layout.progress.y > layout.checklist.y);
    }

    #[test]
    fn a_narrow_run_screen_stacks_the_log_under_the_phases() {
        let area = body(100, 30);
        let layout = run_layout(area, 8);
        assert_eq!(layout.log.x, area.x);
        assert_eq!(layout.log.y, layout.progress.y + 1);
        assert!(log_rows(layout.log) >= 3);
    }

    #[test]
    fn two_columns_only_appear_where_they_fit() {
        assert!(columns(body(60, 20)).1.is_none());
        assert!(columns(body(80, 20)).1.is_none());
        let (left, right) = columns(body(100, 20));
        let right = right.expect("a second column");
        assert!(left.width > 10);
        assert!(right.x > left.x + left.width);
        assert!(right.x + right.width <= 100);
    }
    #[test]
    fn a_scrollbar_thumb_stays_inside_the_pane() {
        for total in [1usize, 5, 20, 200] {
            for viewport in [1usize, 3, 10, 20] {
                for offset in [0usize, 1, 7, 100, 1000] {
                    let (from, to) = thumb_range(offset, total, viewport);
                    assert!(to <= viewport, "total={total} viewport={viewport}");
                    assert!(from <= to);
                }
            }
        }
    }

    #[test]
    fn a_pane_that_fits_its_content_shows_no_thumb() {
        assert_eq!(thumb_range(0, 5, 10), (0, 0));
        assert_eq!(thumb_range(0, 10, 10), (0, 0));
    }

    #[test]
    fn the_thumb_reaches_both_ends() {
        let (from, _) = thumb_range(0, 100, 10);
        assert_eq!(from, 0);
        let (from, to) = thumb_range(90, 100, 10);
        assert_eq!(to, 10);
        assert!(from > 0);
    }

    fn theme() -> Theme {
        Theme::resolve(&crate::env::Env::default())
    }

    #[test]
    fn the_progress_bar_spends_its_width_exactly() {
        let theme = theme();
        let glyphs = Glyphs::resolve(&crate::env::Env::default());
        for width in [20u16, 40, 60, 100] {
            let line = progress(3, 17, width, "3/17 · 1:12", &theme, glyphs);
            assert!(
                line.width() <= width as usize,
                "width {width} drew {}",
                line.width()
            );
        }
        assert!(progress(0, 0, 40, "0/0", &theme, glyphs).width() <= 40);
        assert!(progress(17, 17, 40, "17/17", &theme, glyphs).width() > 0);
    }

    #[test]
    fn hints_drop_from_the_end_rather_than_overflowing() {
        let theme = theme();
        let keys = [
            key("Enter", "continue"),
            key("Esc", "back"),
            key("?", "keys"),
            key("q", "quit"),
        ];
        let wide = hints(&theme, &keys, 200).width();
        assert!(hints(&theme, &keys, 80).width() <= 80);
        assert!(hints(&theme, &keys, 40).width() <= 40);
        assert!(hints(&theme, &keys, 40).width() < wide);
        let narrow = hints(&theme, &keys, 0);
        assert!(narrow.width() > 0);
        assert!(narrow.width() <= "Enter continue".len() + 2);
    }

    #[test]
    fn counts_read_like_english() {
        assert_eq!(plural(0, "step", "steps"), "0 steps");
        assert_eq!(plural(1, "step", "steps"), "1 step");
        assert_eq!(plural(2, "step", "steps"), "2 steps");
    }
    #[test]
    fn elapsed_time_grows_the_way_a_clock_does() {
        assert_eq!(elapsed(0), "0:00");
        assert_eq!(elapsed(9), "0:09");
        assert_eq!(elapsed(72), "1:12");
        assert_eq!(elapsed(3661), "1:01:01");
    }

    #[test]
    fn a_label_column_lines_up() {
        let theme = theme();
        let short = labeled("log", "x".to_string(), &theme, 7);
        let long = labeled("retry", "x".to_string(), &theme, 7);
        assert_eq!(short.width(), long.width());
    }
}
