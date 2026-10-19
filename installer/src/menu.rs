use std::collections::BTreeMap;

pub type Answers = BTreeMap<&'static str, String>;

pub const PRESET_THEME_APPS: &str = "preset_theme_apps";
pub const PRESET_NONE_APPS: &str = "preset_none_apps";
#[derive(Debug)]
pub enum Entry {
    Submenu {
        id: &'static str,
        title: &'static str,
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
    Preset {
        id: &'static str,
        title: &'static str,
        help: &'static str,
        members: &'static [&'static str],
        on: bool,
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

    pub fn help(&self) -> Option<&'static str> {
        let text = match self {
            Entry::Toggle { help, .. }
            | Entry::Choice { help, .. }
            | Entry::Preset { help, .. } => *help,
            Entry::Submenu { .. } => return None,
        };
        (!text.is_empty()).then_some(text)
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

pub fn holds_an_answer(entry: &Entry) -> bool {
    matches!(entry, Entry::Toggle { .. } | Entry::Choice { .. })
}

const APP_THEMING: [&str; 6] = crate::apps::Apps::IDS;

const APPEARANCE: [Entry; 4] = [
    Entry::Toggle {
        id: "SYNC_LOGIN_SCREEN",
        title: "Login screen colours",
        help: "Plasma Login draws its own screen; this keeps its wallpaper and colours in step.",
        default: true,
    },
    Entry::Toggle {
        id: "APPLY_LOCKSCREEN",
        title: "Lock screen",
        help: "",
        default: true,
    },
    Entry::Toggle {
        id: "APPLY_FONTS",
        title: "System fonts",
        help: "Rubik and JetBrains Mono Nerd Font, system-wide.",
        default: true,
    },
    Entry::Choice {
        id: "DEFAULT_SHELL",
        title: "Login shell",
        help: "",
        default: "fish",
        options: &["fish", "zsh", "bash"],
    },
];

const APPS: [Entry; 8] = [
    Entry::Preset {
        id: PRESET_THEME_APPS,
        title: "All of them",
        help: "",
        members: &APP_THEMING,
        on: true,
    },
    Entry::Preset {
        id: PRESET_NONE_APPS,
        title: "None of them",
        help: "",
        members: &APP_THEMING,
        on: false,
    },
    Entry::Toggle {
        id: "INSTALL_VSCODE",
        title: "VSCode / VSCodium",
        help: "",
        default: false,
    },
    Entry::Toggle {
        id: "INSTALL_ZED",
        title: "Zed",
        help: "",
        default: false,
    },
    Entry::Toggle {
        id: "INSTALL_SPICETIFY",
        title: "Spicetify",
        help: "",
        default: false,
    },
    Entry::Toggle {
        id: "INSTALL_DISCORD",
        title: "Discord / Equibop",
        help: "",
        default: false,
    },
    Entry::Toggle {
        id: "INSTALL_TODOIST",
        title: "Todoist",
        help: "",
        default: false,
    },
    Entry::Toggle {
        id: "INSTALL_FIREFOX_THEME",
        title: "Firefox",
        help: "",
        default: false,
    },
];

const OPTIONS: [Entry; 2] = [
    Entry::Toggle {
        id: "REMOVE_CACHE",
        title: "Remove build cache after install",
        help: "",
        default: false,
    },
    Entry::Toggle {
        id: "SKIP_SYSTEM_UPDATE",
        title: "Skip the full system update",
        help: "",
        default: false,
    },
];

pub const QUESTIONS: [Entry; 3] = [
    Entry::Submenu {
        id: "menu_appearance",
        title: "Appearance",
        items: &APPEARANCE,
    },
    Entry::Submenu {
        id: "menu_apps",
        title: "Applications",
        items: &APPS,
    },
    Entry::Submenu {
        id: "menu_behavior",
        title: "Advanced",
        items: &OPTIONS,
    },
];

pub fn question_count() -> usize {
    QUESTIONS.len()
}

pub fn items_of(question: usize) -> &'static [Entry] {
    match QUESTIONS.get(question) {
        Some(Entry::Submenu { items, .. }) => items,
        _ => &[],
    }
}

pub fn question(question: usize) -> &'static str {
    match QUESTIONS.get(question) {
        Some(entry) => entry.title(),
        None => "",
    }
}

fn fish_follows_the_shell(answers: &mut Answers) {
    let shell = answers
        .get("DEFAULT_SHELL")
        .map(String::as_str)
        .unwrap_or("fish");
    answers.insert("INSTALL_FISH", (shell == "fish").to_string());
}

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
            Entry::Preset { .. } => {}
        }
    }
    fish_follows_the_shell(answers);
}

pub fn value<'a>(entry: &Entry, answers: &'a Answers) -> Option<&'a str> {
    answers.get(entry.id()).map(String::as_str)
}

pub fn baseline_of<'a>(entry: &Entry, baseline: &'a Answers) -> Option<&'a str> {
    match entry {
        Entry::Toggle { .. } | Entry::Choice { .. } => baseline.get(entry.id()).map(String::as_str),
        Entry::Submenu { .. } | Entry::Preset { .. } => None,
    }
}

/// The answers a bulk row stands for. Every app is offered whether or not it is installed - the
/// installer is where it gets installed from - so nothing is filtered by what is present.
pub fn members_here(entry: &Entry) -> Vec<&'static str> {
    entry.members().unwrap_or_default().to_vec()
}

pub fn is_changed(entry: &Entry, answers: &Answers, baseline: &Answers) -> bool {
    if entry.members().is_some() {
        return members_here(entry)
            .iter()
            .any(|id| answers.get(id) != baseline.get(id));
    }
    match baseline_of(entry, baseline) {
        Some(start) => value(entry, answers) != Some(start),
        None => false,
    }
}

pub fn reset(entry: &Entry, answers: &mut Answers, baseline: &Answers) -> bool {
    if entry.members().is_some() {
        let members = members_here(entry);
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

pub fn preset_on(entry: &Entry, answers: &Answers) -> bool {
    let Entry::Preset { on, .. } = entry else {
        return false;
    };
    let wanted = if *on { "true" } else { "false" };
    let members = members_here(entry);
    !members.is_empty()
        && members
            .iter()
            .all(|id| answers.get(id).map(String::as_str) == Some(wanted))
}

pub fn preset_set(entry: &Entry, answers: &mut Answers, on: bool) -> bool {
    let members = members_here(entry);
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

pub fn change(entry: &Entry, answers: &mut Answers) -> bool {
    let changed = match entry {
        Entry::Toggle { .. } => toggle(entry, answers),
        Entry::Choice { .. } => cycle(entry, answers, true),
        Entry::Preset { .. } => {
            let on = preset_on(entry, answers);
            preset_set(entry, answers, !on)
        }
        Entry::Submenu { .. } => false,
    };
    fish_follows_the_shell(answers);
    changed
}

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
        Entry::Submenu { .. } | Entry::Preset { .. } => Err(format!(
            "--set: {id} has no value of its own; set the rows it stands for"
        )),
    }
}

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

    struct Wizard {
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
            Self { answers, baseline }
        }

        fn value(&self, id: &str) -> Option<&str> {
            self.answers.get(id).map(String::as_str)
        }

        fn changed(&self, id: &str) -> bool {
            is_changed(entry(id), &self.answers, &self.baseline)
        }

        fn change(&mut self, id: &str) -> bool {
            change(entry(id), &mut self.answers)
        }

        fn back(&mut self, id: &str) -> bool {
            reset(entry(id), &mut self.answers, &self.baseline)
        }

        fn bulk_is_on(&self) -> bool {
            preset_on(preset(), &self.answers)
        }

        fn set_bulk(&mut self, on: bool) -> bool {
            preset_set(preset(), &mut self.answers, on)
        }

        fn visible(&self, id: &str) -> bool {
            every_entry().iter().any(|entry| entry.id() == id)
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
            assert!(!question(index).is_empty(), "question {index} has no title");
            assert!(!items_of(index).is_empty(), "question {index} asks nothing");
        }
    }

    #[test]
    fn a_question_is_a_title_and_a_set_of_rows_and_nothing_else() {
        for entry in QUESTIONS.iter() {
            assert!(
                matches!(entry, Entry::Submenu { .. }),
                "{} is not a group",
                entry.id()
            );
            assert!(
                entry.help().is_none(),
                "{} carries a caption",
                entry.title()
            );
        }
    }

    #[test]
    fn a_rows_help_is_a_fact_the_row_cannot_show() {
        for entry in every_entry() {
            let Some(help) = entry.help() else {
                continue;
            };
            let label = entry.title().to_lowercase();
            assert!(
                !help.to_lowercase().contains(&label),
                "{} restates its own label: {help}",
                entry.id()
            );
            assert!(
                help.chars().count() <= 96,
                "{} is a paragraph, not a line: {} chars",
                entry.id(),
                help.chars().count()
            );
            assert!(
                !help.ends_with('.') || help.matches(". ").count() == 0,
                "{} is more than one sentence: {help}",
                entry.id()
            );
        }
    }

    #[test]
    fn most_rows_have_nothing_to_add_to_their_label() {
        let with_help = every_entry()
            .into_iter()
            .filter(|entry| entry.help().is_some())
            .count();
        assert!(with_help <= 3, "{with_help} rows carry a second line");
    }

    #[test]
    fn a_question_holds_answers_rather_than_navigation() {
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
        assert_eq!(question(apps), "Applications");
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
        let login = entry("SYNC_LOGIN_SCREEN");
        assert!(toggle(login, &mut wizard.answers));
        assert_eq!(value(login, &wizard.answers), Some("false"));

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
            "SYNC_LOGIN_SCREEN",
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

        wizard.answers.insert("INSTALL_ZED", "true".to_string());
        assert!(!wizard.bulk_is_on());

        assert!(wizard.set_bulk(true));
        assert!(wizard.bulk_is_on());
    }

    #[test]
    fn the_bulk_rows_answer_for_every_app_in_the_list() {
        let mut wizard = Wizard::on(crate::apps::Apps::default());

        assert!(wizard.set_bulk(true));
        for id in crate::apps::Apps::IDS {
            assert_eq!(wizard.value(id), Some("true"), "{id} was left out");
        }

        assert!(wizard.set_bulk(false));
        for id in crate::apps::Apps::IDS {
            assert_eq!(wizard.value(id), Some("false"), "{id} was left out");
        }
    }

    #[test]
    fn a_row_knows_whether_it_was_changed_and_can_go_back() {
        let mut wizard = Wizard::new();

        assert!(!wizard.changed("SYNC_LOGIN_SCREEN"));
        assert!(!wizard.changed("DEFAULT_SHELL"));

        wizard.change("SYNC_LOGIN_SCREEN");
        wizard.change("DEFAULT_SHELL");
        assert!(wizard.changed("SYNC_LOGIN_SCREEN"));
        assert!(wizard.changed("DEFAULT_SHELL"));

        assert!(wizard.back("SYNC_LOGIN_SCREEN"));
        assert!(wizard.back("DEFAULT_SHELL"));
        assert_eq!(wizard.value("SYNC_LOGIN_SCREEN"), Some("true"));
        assert_eq!(wizard.value("DEFAULT_SHELL"), Some("fish"));
        assert!(!wizard.changed("SYNC_LOGIN_SCREEN"));
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

        assert!(wizard.change("SYNC_LOGIN_SCREEN"), "a switch flips");
        assert_eq!(wizard.value("SYNC_LOGIN_SCREEN"), Some("false"));

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
    fn every_supported_app_is_a_row_whether_or_not_it_is_here() {
        let empty = Wizard::on(crate::apps::Apps::default());
        assert!(empty.visible("INSTALL_ZED"));
        assert!(empty.visible(PRESET_THEME_APPS));
        assert_eq!(empty.value("INSTALL_ZED"), Some("false"), "and starts off");

        let with_zed = Wizard::on(crate::apps::Apps {
            zed: true,
            ..crate::apps::Apps::default()
        });
        assert_eq!(
            with_zed.value("INSTALL_ZED"),
            Some("true"),
            "an app that is already there starts on"
        );
    }

    #[test]
    fn the_login_screen_row_survives_being_switched_off() {
        let mut wizard = Wizard::new();
        assert!(wizard.visible("SYNC_LOGIN_SCREEN"));
        wizard.change("SYNC_LOGIN_SCREEN");
        assert!(wizard.visible("SYNC_LOGIN_SCREEN"));
        assert_eq!(wizard.value("SYNC_LOGIN_SCREEN"), Some("false"));
    }

    #[test]
    fn a_row_that_is_never_offered_is_never_the_reason_a_step_runs() {
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
