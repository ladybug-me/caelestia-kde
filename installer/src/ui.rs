use ratatui::Frame;
use ratatui::layout::{Alignment, Constraint, Layout, Rect};
use ratatui::style::{Modifier, Style};
use ratatui::text::{Line, Span, Text};
use ratatui::widgets::{Block, Clear, Paragraph, Wrap};

use crate::app::App;
use crate::glyphs::Glyphs;
use crate::steps::Status;
use crate::theme::{NAME, Role, Theme};

pub const MIN_WIDTH: u16 = 60;
pub const MIN_HEIGHT: u16 = 20;

pub const PROSE_WIDTH: u16 = 96;

pub const INDENT: u16 = 2;

const LOG_HEADER_ROWS: u16 = 1;

pub struct Key {
    pub keys: &'static str,
    pub what: &'static str,
}

pub const fn key(keys: &'static str, what: &'static str) -> Key {
    Key { keys, what }
}

pub struct Header {
    pub left: String,
    pub right: String,
}

pub struct Chrome {
    pub body: Rect,
}

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

fn where_you_are(theme: &Theme, header: &Header) -> Line<'static> {
    Line::from(vec![
        Span::styled(" ".to_string(), theme.title()),
        Span::styled(NAME.to_string(), theme.title()),
        Span::styled(format!(" · {} ", header.left), theme.muted()),
    ])
}

fn what_this_is(theme: &Theme, header: &Header) -> Line<'static> {
    Line::from(Span::styled(format!(" {} ", header.right), theme.muted())).right_aligned()
}

pub fn body(area: Rect) -> Rect {
    content(rows(area).body)
}

pub fn content(area: Rect) -> Rect {
    let indent = INDENT.min(area.width / 2);
    Rect {
        x: area.x + indent,
        y: area.y,
        width: area.width.saturating_sub(indent * 2).max(1),
        height: area.height,
    }
}

pub fn dropped(area: Rect, rows: u16) -> Rect {
    let rows = rows.min(area.height.saturating_sub(1));
    Rect {
        y: area.y + rows,
        height: area.height - rows,
        ..area
    }
}

pub fn slack(area: Rect, height: u16) -> u16 {
    (area.height.saturating_sub(height) / 2).min(16)
}

pub fn middle(area: Rect, width: u16, height: u16) -> Rect {
    let width = width.min(area.width).max(1);
    let height = height.min(area.height).max(1);
    Rect {
        x: area.x + (area.width - width) / 2,
        y: area.y + (area.height - height) / 2,
        width,
        height,
    }
}

const RAIL_GAP: u16 = 4;
const PARTNER_MIN: u16 = 52;

const MIN_PANEL: u16 = 24;

pub fn panel_width(content: u16, room: u16) -> u16 {
    let cap = (PROSE_WIDTH + 2).min(room);
    (content + 2).clamp(MIN_PANEL.min(cap), cap)
}

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

pub fn panel_rect(area: Rect, width: u16, rows: u16) -> Rect {
    Rect {
        width,
        height: (rows + 2).min(area.height),
        ..area
    }
}

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

pub fn cursor_spans(theme: &Theme, spans: Vec<Span<'static>>, width: u16) -> Line<'static> {
    let used: usize = spans.iter().map(|span| span.content.chars().count()).sum();
    let mut styled: Vec<Span<'static>> = spans
        .into_iter()
        .map(|span| Span::styled(span.content.into_owned(), theme.bar()))
        .collect();
    let padding = (width as usize).saturating_sub(used);
    if padding > 0 {
        styled.push(Span::styled(" ".repeat(padding), theme.bar()));
    }
    Line::from(styled)
}

pub fn cursor_row(theme: &Theme, glyphs: Glyphs, text: &str, width: u16) -> Line<'static> {
    let text = fit(text, width as usize, glyphs.ellipsis());
    cursor_spans(theme, vec![Span::raw(text)], width)
}

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
    pub step: Rect,
    pub bar: Rect,
    pub note: Rect,
    pub log: Rect,
}

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

pub fn gutter(text: &str, style: Style, glyphs: Glyphs) -> Span<'static> {
    Span::styled(
        format!(" {:>width$} ", text, width = glyphs.status_cell()),
        style,
    )
}

pub fn running_glyph(app: &App) -> &'static str {
    if app.env.animates() {
        app.glyphs.spinner(app.spinner)
    } else {
        app.glyphs.status(Status::Running)
    }
}

pub fn labeled(label: &str, value: String, theme: &Theme, width: usize) -> Line<'static> {
    Line::from(vec![
        Span::styled(format!("  {label:<width$}  "), theme.muted()),
        Span::styled(value, theme.body()),
    ])
}

/// Prose broken into lines no wider than `width`, but never squeezed below `min`: a column too
/// narrow to hold a word reads better with the word spilling than with it split.
pub fn wrap(text: &str, width: usize, min: usize) -> Vec<String> {
    let width = width.max(min);
    let mut lines = Vec::new();
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

pub fn scrollbar(
    frame: &mut Frame,
    area: Rect,
    offset: usize,
    total: usize,
    theme: &Theme,
    glyphs: Glyphs,
    marks: &[(usize, Style)],
) {
    if area.height == 0 || area.width == 0 || total <= area.height as usize {
        return;
    }
    let viewport = area.height as usize;
    let (from, to) = thumb_range(offset, total, viewport);
    let mut marked: Vec<Option<Style>> = vec![None; viewport];
    for (row, style) in marks {
        let at = (row * viewport / total).min(viewport - 1);
        if at < from || at >= to {
            marked[at] = Some(*style);
        }
    }
    let lines: Vec<Line> = (0..viewport)
        .map(|row| {
            if let Some(style) = marked[row] {
                Line::from(Span::styled(glyphs.mark().to_string(), style))
            } else if row >= from && row < to {
                Line::from(Span::styled(glyphs.thumb().to_string(), theme.accent()))
            } else {
                Line::from(Span::styled(glyphs.track().to_string(), theme.rule()))
            }
        })
        .collect();
    frame.render_widget(Paragraph::new(Text::from(lines)), area);
}

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

pub fn log_rows(log: Rect) -> u16 {
    log.height.saturating_sub(LOG_HEADER_ROWS)
}

pub fn run_layout(body: Rect) -> RunLayout {
    let rows = Layout::vertical([
        Constraint::Length(1),
        Constraint::Length(1),
        Constraint::Length(1),
        Constraint::Length(1),
        Constraint::Min(3),
    ])
    .areas::<5>(body);
    RunLayout {
        step: rows[0],
        bar: rows[1],
        note: rows[2],
        log: rows[4],
    }
}

pub fn prose(frame: &mut Frame, area: Rect, lines: Vec<Line<'static>>, style: Style) {
    frame.render_widget(
        Paragraph::new(Text::from(lines))
            .style(style)
            .wrap(Wrap { trim: false }),
        area,
    );
}

pub fn prose_middle(frame: &mut Frame, area: Rect, lines: Vec<Line<'static>>, style: Style) {
    let pad = slack(area, lines.len() as u16);
    prose(frame, dropped(area, pad), lines, style);
}

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
    fn a_composition_is_placed_in_the_middle_of_the_frame() {
        let area = body(240, 60);
        let block = middle(area, 120, 20);
        assert_eq!(block.width, 120);
        assert_eq!(block.x, area.x + 60);
        assert_eq!(block.height, 20);
        assert_eq!(block.y, area.y + 20, "and not pinned to the top edge");

        let tight = middle(body(80, 20), 200, 40);
        assert_eq!((tight.width, tight.height), (80, 20));
        assert_eq!((tight.x, tight.y), (0, 0));
    }

    #[test]
    fn the_frame_leaves_the_body_a_box_inside_the_terminal() {
        for (width, height) in [(60, 20), (100, 30), (235, 58)] {
            let area = body(width, height);
            let chrome = content(rows(area).body);
            assert!(chrome.width > 0 && chrome.height > 0, "{width}x{height}");
            assert!(chrome.x + chrome.width <= width, "{width}x{height}");
            assert!(chrome.y + chrome.height <= height, "{width}x{height}");
            assert_eq!(rows(area).bar.y, height - 2, "{width}x{height}");
            assert_eq!(rows(area).body.height, height - 3, "{width}x{height}");
        }
    }

    #[test]
    fn the_log_keeps_its_rows_whatever_the_terminal_size() {
        for height in MIN_HEIGHT..=60 {
            let area = body(100, height);
            let layout = run_layout(area);
            assert!(
                log_rows(layout.log) >= 3,
                "{height} rows left the log {}",
                log_rows(layout.log)
            );
            assert!(
                layout.log.y + layout.log.height <= area.height,
                "{height} rows overflow"
            );
            assert_eq!(layout.step.y, 0);
            assert_eq!(layout.bar.y, 1);
            assert_eq!(layout.note.y, 2);
            assert!(layout.log.y > layout.note.y, "{height} rows");
        }
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
    fn the_run_screen_gives_the_log_the_whole_width_at_any_size() {
        for width in [100u16, 160, 240] {
            let area = body(width, 40);
            let layout = run_layout(area);
            assert_eq!(layout.log.x, area.x, "{width} wide");
            assert_eq!(layout.log.width, area.width, "{width} wide");
            assert_eq!(layout.bar.width, area.width, "{width} wide");
            assert!(log_rows(layout.log) >= 3, "{width} wide");
        }
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
