use std::collections::BTreeMap;

pub type Answers = BTreeMap<&'static str, String>;

pub const PRESET_THEME_APPS: &str = "preset_theme_apps";
#[derive(Debug)]
pub enum Entry {
    Submenu {
        id: &'static str,
        title: &'static str,
        help: &'static str,
        items: &'static [Entry],
    },
    Toggle {
        id: &'static str,
        title: &'static str,
        help: &'static str,
        default: bool,
    },
    Choice {
        id: &'static str,
        title: &'static str,
        help: &'static str,
        default: &'static str,
        options: &'static [&'static str],
    },
    /// One row that stands for a group of toggles: the bulk answer, with the individual ones
    /// still available where they live.
    Preset {
        id: &'static str,
        title: &'static str,
        help: &'static str,
        members: &'static [&'static str],
    },
}

impl Entry {
    pub fn id(&self) -> &'static str {
        match self {
            Entry::Submenu { id, .. }
            | Entry::Toggle { id, .. }
            | Entry::Choice { id, .. }
            | Entry::Preset { id, .. } => id,
        }
    }

    pub fn title(&self) -> &'static str {
        match self {
            Entry::Submenu { title, .. }
            | Entry::Toggle { title, .. }
            | Entry::Choice { title, .. }
            | Entry::Preset { title, .. } => title,
        }
    }

    pub fn help(&self) -> &'static str {
        match self {
            Entry::Submenu { help, .. }
            | Entry::Toggle { help, .. }
            | Entry::Choice { help, .. }
            | Entry::Preset { help, .. } => help,
        }
    }

    #[cfg(test)]
    pub fn is_answerable(&self) -> bool {
        matches!(self, Entry::Toggle { .. } | Entry::Choice { .. })
    }

    pub fn members(&self) -> Option<&'static [&'static str]> {
        match self {
            Entry::Preset { members, .. } => Some(members),
            _ => None,
        }
    }
}

/// Whether a row holds an answer of its own, as opposed to being a view of answers that live
/// elsewhere. Counting, resetting and "changed" all mean the answers.
pub fn holds_an_answer(entry: &Entry) -> bool {
    matches!(entry, Entry::Toggle { .. } | Entry::Choice { .. })
}

/// The apps whose theming the bulk row turns on and off together.
const APP_THEMING: [&str; 6] = [
    "INSTALL_VSCODE",
    "INSTALL_ZED",
    "INSTALL_SPICETIFY",
    "INSTALL_DISCORD",
    "INSTALL_TODOIST",
    "INSTALL_FIREFOX_THEME",
];

/// The look, and the packages it is made of. The icon set, the theme and the Qt style the look is
/// built on are not offered one at a time: turning any of them off does not give a smaller
/// Caelestia, it gives a broken one that the configuration deployed later does not match.
const APPEARANCE: [Entry; 4] = [
    Entry::Toggle {
        id: "INSTALL_SDDM",
        title: "Login screen",
        help: "Replace the login screen with the Caelestia one.",
        default: true,
    },
    Entry::Choice {
        id: "SDDM_THEME_VARIANT",
        title: "Login screen style",
        help: "Full: clock, system info, quotes, avatar, blur effects. Mini: centered login card.",
        default: "full",
        options: &["full", "mini"],
    },
    Entry::Toggle {
        id: "APPLY_LOCKSCREEN",
        title: "Lock screen",
        help: "The Caelestia lock screen for KDE Plasma.",
        default: true,
    },
    Entry::Toggle {
        id: "APPLY_FONTS",
        title: "System fonts",
        help: "Apply Rubik and JetBrains Mono Nerd Font across the system.",
        default: true,
    },
];

const SHELL: [Entry; 1] = [Entry::Choice {
    id: "DEFAULT_SHELL",
    title: "Login shell",
    help: "Caelestia's shell configuration is deployed for the one you pick.",
    default: "fish",
    options: &["fish", "zsh", "bash"],
}];

const APPS: [Entry; 7] = [
    // The bulk answer sits at the top of the question it answers: this is where somebody who
    // wants all of it on looks, so the one row that does that belongs here rather than in a
    // menu of its own.
    Entry::Preset {
        id: PRESET_THEME_APPS,
        title: "Theme all of them",
        help: "Turn on every app below. Each one stays editable.",
        members: &APP_THEMING,
    },
    Entry::Toggle {
        id: "INSTALL_VSCODE",
        title: "VSCode / VSCodium",
        help: "Settings, keybindings, and the Caelestia theme.",
        default: false,
    },
    Entry::Toggle {
        id: "INSTALL_ZED",
        title: "Zed",
        help: "Zed keymap and settings.",
        default: false,
    },
    Entry::Toggle {
        id: "INSTALL_SPICETIFY",
        title: "Spicetify",
        help: "Spotify theming through Spicetify.",
        default: false,
    },
    Entry::Toggle {
        id: "INSTALL_DISCORD",
        title: "Discord / Equibop",
        help: "The Caelestia look for Discord or Equibop.",
        default: false,
    },
    Entry::Toggle {
        id: "INSTALL_TODOIST",
        title: "Todoist",
        help: "The Todoist AppImage.",
        default: false,
    },
    Entry::Toggle {
        id: "INSTALL_FIREFOX_THEME",
        title: "Firefox theming",
        help: "userChrome.css and user.js theming for Firefox.",
        default: false,
    },
];

const OPTIONS: [Entry; 2] = [
    Entry::Toggle {
        id: "REMOVE_CACHE",
        title: "Remove build cache after install",
        help: "Clear the Caelestia build cache when installation finishes.",
        default: false,
    },
    Entry::Toggle {
        id: "SKIP_SYSTEM_UPDATE",
        title: "Skip the full system update",
        help: "Skip the full system update (pacman -Syu / dnf upgrade / apt upgrade).",
        default: false,
    },
];

/// The wizard asks one question at a time, one screen each, in this order. Every entry here is a
/// group of answers that belong to the same decision, so a screen is never a list of unrelated
/// settings and never needs a second level of menus.
pub const QUESTIONS: [Entry; 4] = [
    Entry::Submenu {
        id: "menu_appearance",
        title: "Appearance",
        help: "The look, and the packages it is made of.",
        items: &APPEARANCE,
    },
    Entry::Submenu {
        id: "menu_shell",
        title: "Shell",
        help: "The shell Caelestia sets up.",
        items: &SHELL,
    },
    Entry::Submenu {
        id: "menu_apps",
        title: "Applications",
        help: "Theming for the apps this machine already has.",
        items: &APPS,
    },
    Entry::Submenu {
        id: "menu_behavior",
        title: "The install",
        help: "What it does to the machine before it starts.",
        items: &OPTIONS,
    },
];

/// How many questions there are: what the question counter counts to.
pub fn question_count() -> usize {
    QUESTIONS.len()
}

/// The entries belonging to one question, by position.
pub fn items_of(question: usize) -> &'static [Entry] {
    match QUESTIONS.get(question) {
        Some(Entry::Submenu { items, .. }) => items,
        _ => &[],
    }
}

/// The title and help of one question, by position.
pub fn question(question: usize) -> (&'static str, &'static str) {
    match QUESTIONS.get(question) {
        Some(entry) => (entry.title(), entry.help()),
        None => ("", ""),
    }
}

/// Whether a row belongs on screen. Two things make a row conditional: an app that is not here has
/// nothing to theme, and a login screen style only means something if the login screen is being
/// replaced. The bulk row goes with its members, so it can never switch on what nobody can see.
pub fn shows(entry: &Entry, answers: &Answers, apps: &crate::apps::Apps) -> bool {
    if !apps.has(entry.id()) {
        return false;
    }
    match entry.id() {
        PRESET_THEME_APPS => apps.any(),
        "SDDM_THEME_VARIANT" => answers.get("INSTALL_SDDM").map(String::as_str) != Some("false"),
        _ => true,
    }
}

/// The shell question owns whether Fish is installed. They used to be two rows on two screens,
/// which let somebody ask to log in to a shell that was never installed: one decision about the
/// shell cannot contradict itself.
fn fish_follows_the_shell(answers: &mut Answers) {
    let shell = answers
        .get("DEFAULT_SHELL")
        .map(String::as_str)
        .unwrap_or("fish");
    answers.insert("INSTALL_FISH", (shell == "fish").to_string());
}

/// Every answerable entry the wizard asks about, in the order it asks them: the question tree
/// flattened, which is what the change tally and the step-policy check walk.
pub fn every_entry() -> Vec<&'static Entry> {
    fn walk(entries: &'static [Entry], into: &mut Vec<&'static Entry>) {
        for entry in entries {
            match entry {
                Entry::Submenu { items, .. } => walk(items, into),
                other => into.push(other),
            }
        }
    }
    let mut all = Vec::new();
    walk(&QUESTIONS, &mut all);
    all
}

pub fn seed_answers(entries: &[Entry], answers: &mut Answers) {
    for entry in entries {
        match entry {
            Entry::Submenu { items, .. } => seed_answers(items, answers),
            Entry::Toggle { id, default, .. } => {
                answers.entry(id).or_insert_with(|| {
                    if *default {
                        "true".to_string()
                    } else {
                        "false".to_string()
                    }
                });
            }
            Entry::Choice {
                id,
                default,
                options,
                ..
            } => {
                let seed = if default.is_empty() {
                    options.first().copied().unwrap_or("")
                } else {
                    default
                };
                answers.entry(id).or_insert_with(|| seed.to_string());
            }
            // A preset holds no answer of its own: it is a view of the toggles it stands for.
            Entry::Preset { .. } => {}
        }
    }
    fish_follows_the_shell(answers);
}

pub fn value<'a>(entry: &Entry, answers: &'a Answers) -> Option<&'a str> {
    answers.get(entry.id()).map(String::as_str)
}

/// The answer the wizard started this row at on this machine. For everything the wizard decides
/// that is the value in the table; for the apps it is what was found. "Changed" and "reset" mean
/// the answers the wizard was seeded with, so the apps a machine already has do not read as six
/// things the user just switched on.
pub fn baseline_of<'a>(entry: &Entry, baseline: &'a Answers) -> Option<&'a str> {
    match entry {
        Entry::Toggle { .. } | Entry::Choice { .. } => baseline.get(entry.id()).map(String::as_str),
        Entry::Submenu { .. } | Entry::Preset { .. } => None,
    }
}

/// The members of a bulk row that are actually on screen: the apps this machine has. Turning the
/// bulk row on must not answer for an app that was never offered, or the step behind it would
/// install what nobody asked for.
pub fn members_here(entry: &Entry, apps: &crate::apps::Apps) -> Vec<&'static str> {
    entry
        .members()
        .unwrap_or_default()
        .iter()
        .copied()
        .filter(|id| apps.has(id))
        .collect()
}

pub fn is_changed(
    entry: &Entry,
    apps: &crate::apps::Apps,
    answers: &Answers,
    baseline: &Answers,
) -> bool {
    if entry.members().is_some() {
        return members_here(entry, apps)
            .iter()
            .any(|id| answers.get(id) != baseline.get(id));
    }
    match baseline_of(entry, baseline) {
        Some(start) => value(entry, answers) != Some(start),
        None => false,
    }
}

/// Put one row back to the answer this machine started with. A bulk row takes its members with
/// it: undoing one decision undoes all of it.
pub fn reset(
    entry: &Entry,
    apps: &crate::apps::Apps,
    answers: &mut Answers,
    baseline: &Answers,
) -> bool {
    if entry.members().is_some() {
        let members = members_here(entry, apps);
        for id in &members {
            let start = baseline
                .get(id)
                .cloned()
                .unwrap_or_else(|| "false".to_string());
            answers.insert(*id, start);
        }
        return !members.is_empty();
    }
    match baseline_of(entry, baseline) {
        Some(start) => {
            answers.insert(entry.id(), start.to_string());
            fish_follows_the_shell(answers);
            true
        }
        None => false,
    }
}

/// A bulk row is on when every app it stands for is on.
pub fn preset_on(entry: &Entry, apps: &crate::apps::Apps, answers: &Answers) -> bool {
    let members = members_here(entry, apps);
    !members.is_empty()
        && members
            .iter()
            .all(|id| answers.get(id).map(String::as_str) == Some("true"))
}

pub fn preset_set(
    entry: &Entry,
    apps: &crate::apps::Apps,
    answers: &mut Answers,
    on: bool,
) -> bool {
    let members = members_here(entry, apps);
    for id in &members {
        answers.insert(*id, on.to_string());
    }
    !members.is_empty()
}

pub fn toggle(entry: &Entry, answers: &mut Answers) -> bool {
    let Entry::Toggle { id, .. } = entry else {
        return false;
    };
    let next = if value(entry, answers) == Some("true") {
        "false"
    } else {
        "true"
    };
    answers.insert(id, next.to_string());
    true
}

pub fn cycle(entry: &Entry, answers: &mut Answers, forward: bool) -> bool {
    let Entry::Choice { id, options, .. } = entry else {
        return false;
    };
    if options.is_empty() {
        return false;
    }
    let current = value(entry, answers).unwrap_or_default();
    let at = options
        .iter()
        .position(|option| *option == current)
        .unwrap_or(0);
    let next = if forward {
        (at + 1) % options.len()
    } else if at == 0 {
        options.len() - 1
    } else {
        at - 1
    };
    answers.insert(id, options[next].to_string());
    true
}

/// Change the row under the cursor, whatever kind of row it is: a switch flips, a select steps
/// on, and a bulk row takes every member it stands for with it. One entry point, so the key that
/// means "change" does not quietly do nothing on some rows.
pub fn change(entry: &Entry, apps: &crate::apps::Apps, answers: &mut Answers) -> bool {
    let changed = match entry {
        Entry::Toggle { .. } => toggle(entry, answers),
        Entry::Choice { .. } => cycle(entry, answers, true),
        Entry::Preset { .. } => {
            let on = preset_on(entry, apps, answers);
            preset_set(entry, apps, answers, !on)
        }
        Entry::Submenu { .. } => false,
    };
    fish_follows_the_shell(answers);
    changed
}

/// Read one `ID=value` from the command line: the answer a script gives without walking the
/// wizard. Checked against the tables here, so a mistyped id or a value a row cannot hold is
/// refused before anything runs rather than quietly dropped half way through an install.
pub fn parse_set(setting: &str) -> Result<(&'static str, String), String> {
    let (id, value) = setting
        .split_once('=')
        .ok_or_else(|| format!("--set needs ID=value, not '{setting}'"))?;
    let entry = every_entry()
        .into_iter()
        .find(|entry| entry.id() == id)
        .ok_or_else(|| format!("--set: no option is called '{id}'"))?;
    match entry {
        Entry::Toggle { .. } => match value {
            "true" | "false" => Ok((entry.id(), value.to_string())),
            other => Err(format!(
                "--set {id}: a switch is true or false, not '{other}'"
            )),
        },
        Entry::Choice { options, .. } => {
            if options.contains(&value) {
                Ok((entry.id(), value.to_string()))
            } else {
                Err(format!(
                    "--set {id}: '{value}' is not one of {}",
                    options.join(", ")
                ))
            }
        }
        // A bulk row is a view of the switches it stands for, so setting it would be a way to
        // answer for rows the caller never named.
        Entry::Submenu { .. } | Entry::Preset { .. } => Err(format!(
            "--set: {id} has no value of its own; set the rows it stands for"
        )),
    }
}

/// Apply the answers a script gave, on top of the seeded ones. A script's answers are where the
/// wizard starts, so they are also the baseline a later change is measured against.
pub fn apply_set(settings: &[(&'static str, String)], answers: &mut Answers) {
    for (id, value) in settings {
        answers.insert(id, value.clone());
    }
    fish_follows_the_shell(answers);
}

#[cfg(test)]
mod tests {
    use super::*;

    fn every_entry() -> Vec<&'static Entry> {
        super::every_entry()
    }

    fn entry(id: &str) -> &'static Entry {
        every_entry()
            .into_iter()
            .find(|entry| entry.id() == id)
            .unwrap_or_else(|| panic!("{id} is in the tree"))
    }

    fn preset() -> &'static Entry {
        entry(PRESET_THEME_APPS)
    }

    /// A wizard on a machine that has every app, and the answers it started with. Most rows only
    /// mean something next to a baseline, and "the apps this machine has" is not something a test
    /// can arrange any other way.
    struct Wizard {
        apps: crate::apps::Apps,
        answers: Answers,
        baseline: Answers,
    }

    impl Wizard {
        fn new() -> Self {
            Self::on(crate::apps::Apps::all())
        }

        fn on(apps: crate::apps::Apps) -> Self {
            let mut answers = Answers::new();
            seed_answers(&QUESTIONS, &mut answers);
            for (id, answer) in apps.answers() {
                answers.insert(id, answer.to_string());
            }
            let baseline = answers.clone();
            Self {
                apps,
                answers,
                baseline,
            }
        }

        fn value(&self, id: &str) -> Option<&str> {
            self.answers.get(id).map(String::as_str)
        }

        fn changed(&self, id: &str) -> bool {
            is_changed(entry(id), &self.apps, &self.answers, &self.baseline)
        }

        fn change(&mut self, id: &str) -> bool {
            change(entry(id), &self.apps, &mut self.answers)
        }

        fn back(&mut self, id: &str) -> bool {
            reset(entry(id), &self.apps, &mut self.answers, &self.baseline)
        }

        fn bulk_is_on(&self) -> bool {
            preset_on(preset(), &self.apps, &self.answers)
        }

        fn set_bulk(&mut self, on: bool) -> bool {
            preset_set(preset(), &self.apps, &mut self.answers, on)
        }

        fn visible(&self, id: &str) -> bool {
            shows(entry(id), &self.answers, &self.apps)
        }
    }

    #[test]
    fn answers_scatter_without_duplicate_keys() {
        let mut seen = std::collections::BTreeSet::new();
        for entry in every_entry() {
            if entry.is_answerable() {
                assert!(
                    seen.insert(entry.id()),
                    "duplicate answer id {}",
                    entry.id()
                );
            }
        }
    }

    #[test]
    fn every_question_is_a_screen_worth_showing() {
        assert_eq!(question_count(), QUESTIONS.len());
        for index in 0..question_count() {
            let (title, help) = question(index);
            assert!(!title.is_empty(), "question {index} has no title");
            assert!(!help.is_empty(), "question {index} has no help");
            assert!(!items_of(index).is_empty(), "question {index} asks nothing");
        }
    }

    #[test]
    fn a_question_holds_answers_rather_than_navigation() {
        // Back and onward are the wizard's job now: a row that only navigates would sit in the
        // list looking like something that can be answered.
        for entry in every_entry() {
            assert!(
                matches!(
                    entry,
                    Entry::Toggle { .. } | Entry::Choice { .. } | Entry::Preset { .. }
                ),
                "{} is not an answer",
                entry.id()
            );
        }
    }

    #[test]
    fn the_bulk_answer_sits_in_the_question_it_answers() {
        let apps = (0..question_count())
            .find(|index| {
                items_of(*index)
                    .iter()
                    .any(|entry| entry.id() == PRESET_THEME_APPS)
            })
            .expect("the preset is in a question");
        assert_eq!(question(apps).0, "Applications");
        assert_eq!(
            items_of(apps)[0].id(),
            PRESET_THEME_APPS,
            "and it is the first thing on that screen"
        );
    }

    #[test]
    fn seeding_answers_fills_every_question_from_the_defaults() {
        let mut answers = Answers::new();
        seed_answers(&QUESTIONS, &mut answers);
        for entry in every_entry() {
            if entry.is_answerable() {
                assert!(
                    answers.contains_key(entry.id()),
                    "{} was not seeded",
                    entry.id()
                );
            }
        }
        assert_eq!(
            answers.get("INSTALL_FISH").map(String::as_str),
            Some("true")
        );
        assert_eq!(
            answers.get("INSTALL_ZED").map(String::as_str),
            Some("false")
        );
        assert_eq!(
            answers.get("DEFAULT_SHELL").map(String::as_str),
            Some("fish")
        );
    }

    #[test]
    fn seeding_never_overwrites_a_choice_the_user_made() {
        let mut answers = Answers::new();
        answers.insert("DEFAULT_SHELL", "zsh".to_string());
        seed_answers(&QUESTIONS, &mut answers);
        assert_eq!(
            answers.get("DEFAULT_SHELL").map(String::as_str),
            Some("zsh")
        );
        assert_eq!(
            answers.get("INSTALL_FISH").map(String::as_str),
            Some("false"),
            "and the shell that was kept still decides fish"
        );
    }

    #[test]
    fn the_login_shell_decides_whether_fish_is_installed() {
        let mut wizard = Wizard::new();
        assert_eq!(
            wizard.value("INSTALL_FISH"),
            Some("true"),
            "fish is the default shell, so it is installed"
        );

        assert!(wizard.change("DEFAULT_SHELL"));
        assert_eq!(wizard.value("DEFAULT_SHELL"), Some("zsh"));
        assert_eq!(
            wizard.value("INSTALL_FISH"),
            Some("false"),
            "asking to log in to zsh cannot leave a fish that was never installed"
        );

        wizard.change("DEFAULT_SHELL");
        wizard.change("DEFAULT_SHELL");
        assert_eq!(wizard.value("DEFAULT_SHELL"), Some("fish"));
        assert_eq!(wizard.value("INSTALL_FISH"), Some("true"));
    }

    #[test]
    fn toggles_flip_and_a_bulk_row_is_not_a_toggle() {
        let mut wizard = Wizard::new();
        let sddm = entry("INSTALL_SDDM");
        assert!(toggle(sddm, &mut wizard.answers));
        assert_eq!(value(sddm, &wizard.answers), Some("false"));

        assert!(
            !toggle(preset(), &mut wizard.answers),
            "a bulk row is set, not flipped"
        );
    }

    #[test]
    fn selects_wrap_in_both_directions() {
        let mut wizard = Wizard::new();
        let shell = entry("DEFAULT_SHELL");
        assert_eq!(value(shell, &wizard.answers), Some("fish"));

        assert!(cycle(shell, &mut wizard.answers, true));
        assert_eq!(value(shell, &wizard.answers), Some("zsh"));

        assert!(cycle(shell, &mut wizard.answers, false));
        assert_eq!(
            value(shell, &wizard.answers),
            Some("fish"),
            "the first option wraps to the last"
        );

        assert!(cycle(shell, &mut wizard.answers, false));
        assert_eq!(
            value(shell, &wizard.answers),
            Some("bash"),
            "the last option wraps to the first"
        );

        assert!(cycle(shell, &mut wizard.answers, true));
        assert_eq!(value(shell, &wizard.answers), Some("fish"));
        assert!(cycle(shell, &mut wizard.answers, true));
        assert_eq!(
            value(shell, &wizard.answers),
            Some("zsh"),
            "steps through the middle"
        );

        assert!(
            !cycle(preset(), &mut wizard.answers, true),
            "only selects cycle"
        );
    }

    #[test]
    fn every_question_the_step_policy_reads_is_in_the_tree() {
        let wizard = Wizard::new();
        for key in [
            "SKIP_SYSTEM_UPDATE",
            "INSTALL_SDDM",
            "INSTALL_VSCODE",
            "INSTALL_ZED",
            "INSTALL_SPICETIFY",
            "INSTALL_DISCORD",
            "INSTALL_TODOIST",
            "INSTALL_FIREFOX_THEME",
        ] {
            assert!(
                wizard.answers.contains_key(key),
                "the step policy reads {key}, the menu has no entry"
            );
        }
    }

    #[test]
    fn the_preset_stands_for_toggles_that_are_really_there() {
        let members = preset().members().expect("the preset has members");
        assert_eq!(members.len(), 6, "six apps, six switches");
        for id in members {
            let member = entry(id);
            assert!(
                matches!(member, Entry::Toggle { .. }),
                "{id} is not a toggle"
            );
        }
    }

    #[test]
    fn the_preset_is_a_view_of_its_members_rather_than_a_state_of_its_own() {
        let mut wizard = Wizard::new();
        assert!(
            wizard.bulk_is_on(),
            "the apps this machine has start on, and the row says so"
        );

        assert!(wizard.set_bulk(false));
        assert!(!wizard.bulk_is_on());
        for id in preset().members().expect("members") {
            assert_eq!(wizard.value(id), Some("false"));
        }

        // One app on its own is not the whole row.
        wizard.answers.insert("INSTALL_ZED", "true".to_string());
        assert!(!wizard.bulk_is_on());

        assert!(wizard.set_bulk(true));
        assert!(wizard.bulk_is_on());
    }

    #[test]
    fn the_bulk_row_answers_for_the_apps_that_are_on_screen_and_no_others() {
        // One app here, six in the table: the bulk row must not switch on what nobody was
        // offered, or the step behind it would install an editor for somebody who has one.
        let mut wizard = Wizard::on(crate::apps::Apps {
            zed: true,
            ..crate::apps::Apps::default()
        });

        assert!(wizard.set_bulk(true));
        assert_eq!(wizard.value("INSTALL_ZED"), Some("true"));
        assert_eq!(
            wizard.value("INSTALL_VSCODE"),
            Some("false"),
            "only the app on screen was answered for"
        );

        assert!(wizard.set_bulk(false));
        assert_eq!(wizard.value("INSTALL_ZED"), Some("false"));
    }

    #[test]
    fn a_row_knows_whether_it_was_changed_and_can_go_back() {
        let mut wizard = Wizard::new();

        assert!(!wizard.changed("INSTALL_SDDM"));
        assert!(!wizard.changed("DEFAULT_SHELL"));

        wizard.change("INSTALL_SDDM");
        wizard.change("DEFAULT_SHELL");
        assert!(wizard.changed("INSTALL_SDDM"));
        assert!(wizard.changed("DEFAULT_SHELL"));

        assert!(wizard.back("INSTALL_SDDM"));
        assert!(wizard.back("DEFAULT_SHELL"));
        assert_eq!(wizard.value("INSTALL_SDDM"), Some("true"));
        assert_eq!(wizard.value("DEFAULT_SHELL"), Some("fish"));
        assert!(!wizard.changed("INSTALL_SDDM"));
        assert!(!wizard.changed("DEFAULT_SHELL"));
    }

    #[test]
    fn a_question_reads_as_changed_from_its_rows_rather_than_its_own_state() {
        let mut wizard = Wizard::new();
        assert!(!wizard.changed("INSTALL_SPICETIFY"));

        wizard.change("INSTALL_SPICETIFY");
        assert!(wizard.changed("INSTALL_SPICETIFY"));
    }

    #[test]
    fn the_apps_a_machine_already_has_are_on_before_anyone_touches_them() {
        // The baseline is what this machine starts at, so a machine that has Zed does not read as
        // having changed anything, and going back does not turn it off.
        let mut wizard = Wizard::new();
        assert_eq!(wizard.value("INSTALL_ZED"), Some("true"));
        assert!(!wizard.changed("INSTALL_ZED"));

        wizard.change("INSTALL_ZED");
        assert_eq!(wizard.value("INSTALL_ZED"), Some("false"));
        assert!(wizard.changed("INSTALL_ZED"));

        assert!(wizard.back("INSTALL_ZED"));
        assert_eq!(wizard.value("INSTALL_ZED"), Some("true"));
        assert!(!wizard.changed("INSTALL_ZED"));
    }

    #[test]
    fn a_bulk_row_is_changed_as_a_whole() {
        let mut wizard = Wizard::new();
        assert!(
            !wizard.changed(PRESET_THEME_APPS),
            "the apps start at whatever was found"
        );

        wizard.set_bulk(false);
        assert!(wizard.changed(PRESET_THEME_APPS));

        // Reset on a bulk row puts the whole group back.
        assert!(wizard.back(PRESET_THEME_APPS));
        assert!(wizard.bulk_is_on());
        assert!(
            !wizard.changed(PRESET_THEME_APPS),
            "and it reads as untouched"
        );
    }

    #[test]
    fn one_change_key_changes_whatever_kind_of_row_it_is_given() {
        let mut wizard = Wizard::new();

        assert!(wizard.change("INSTALL_SDDM"), "a switch flips");
        assert_eq!(wizard.value("INSTALL_SDDM"), Some("false"));

        assert!(wizard.change("DEFAULT_SHELL"), "a select steps on");
        assert_eq!(wizard.value("DEFAULT_SHELL"), Some("zsh"));

        assert!(
            wizard.change(PRESET_THEME_APPS),
            "a bulk row takes its members with it"
        );
        assert!(!wizard.bulk_is_on(), "one decision, every app off");

        assert!(wizard.change(PRESET_THEME_APPS));
        assert!(wizard.bulk_is_on(), "and back on again");
    }

    #[test]
    fn a_login_screen_style_is_only_worth_showing_while_there_is_a_login_screen() {
        let mut wizard = Wizard::new();
        assert!(wizard.visible("SDDM_THEME_VARIANT"));
        assert!(wizard.visible("INSTALL_SDDM"));

        wizard.change("INSTALL_SDDM");
        assert!(!wizard.visible("SDDM_THEME_VARIANT"));
        assert!(wizard.visible("INSTALL_SDDM"), "the row that hid it stays");
    }

    #[test]
    fn an_app_that_is_not_here_is_not_a_row_to_answer() {
        assert!(!Wizard::on(crate::apps::Apps::default()).visible("INSTALL_ZED"));
        assert!(Wizard::new().visible("INSTALL_ZED"));
    }

    #[test]
    fn the_bulk_row_goes_with_the_rows_it_stands_for() {
        assert!(!Wizard::on(crate::apps::Apps::default()).visible(PRESET_THEME_APPS));
        assert!(Wizard::new().visible(PRESET_THEME_APPS));
    }

    #[test]
    fn a_row_that_is_never_offered_is_never_the_reason_a_step_runs() {
        // The answers a machine with nothing on it starts with: every app row is off, so the
        // step policy skips them all rather than going looking for something to install.
        let wizard = Wizard::on(crate::apps::Apps::default());
        for id in crate::apps::Apps::IDS {
            assert_eq!(
                wizard.value(id),
                Some("false"),
                "{id} was left on with no app to theme"
            );
        }
    }
}
