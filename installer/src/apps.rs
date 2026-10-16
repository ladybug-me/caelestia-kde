// Which of the apps Caelestia can theme are already on this machine.
//
// The wizard asks about these and nothing else: a row for an app that is not installed would be an
// offer to install somebody else's editor, which is not what this program is for. The step behind
// each flag still installs the app when a script sets the flag, so nothing is lost to automation.

use std::sync::OnceLock;

use crate::process;

#[derive(Copy, Clone, Debug, Default, PartialEq, Eq)]
pub struct Apps {
    pub vscode: bool,
    pub zed: bool,
    pub spicetify: bool,
    pub discord: bool,
    pub todoist: bool,
    pub firefox: bool,
}

impl Apps {
    /// The ids of the rows that are about an app rather than about Caelestia itself.
    pub const IDS: [&'static str; 6] = [
        "INSTALL_VSCODE",
        "INSTALL_ZED",
        "INSTALL_SPICETIFY",
        "INSTALL_DISCORD",
        "INSTALL_TODOIST",
        "INSTALL_FIREFOX_THEME",
    ];

    /// The apps on this machine, probed once: the answer is a property of the machine, not of a
    /// screen, so a wizard that asked per screen would run the same probes over and over.
    pub fn here() -> Self {
        static APPS: OnceLock<Apps> = OnceLock::new();
        *APPS.get_or_init(Self::probe)
    }

    fn probe() -> Self {
        Self {
            vscode: process::available("code") || process::available("codium"),
            zed: process::available("zed"),
            spicetify: process::available("spicetify"),
            discord: process::available("discord") || process::available("equibop"),
            todoist: todoist_here(),
            firefox: process::available("firefox"),
        }
    }

    /// Whether the app this row is about is here. A row about something else is always relevant.
    pub fn has(&self, id: &str) -> bool {
        match id {
            "INSTALL_VSCODE" => self.vscode,
            "INSTALL_ZED" => self.zed,
            "INSTALL_SPICETIFY" => self.spicetify,
            "INSTALL_DISCORD" => self.discord,
            "INSTALL_TODOIST" => self.todoist,
            "INSTALL_FIREFOX_THEME" => self.firefox,
            _ => true,
        }
    }

    /// Whether any app at all is here: what the bulk row and the question itself are measured by.
    pub fn any(&self) -> bool {
        Self::IDS.iter().any(|id| self.has(id))
    }

    /// The answer for each app row. An app that is not here answers no, so a row nobody saw can
    /// never be the reason a step runs.
    pub fn answers(&self) -> impl Iterator<Item = (&'static str, &'static str)> {
        Self::IDS
            .iter()
            .map(|id| (*id, if self.has(id) { "true" } else { "false" }))
    }

    /// Every app present: what the row filter is reasoned about with, since which apps a machine
    /// happens to have is not something a test can arrange.
    #[cfg(test)]
    pub fn all() -> Self {
        Self {
            vscode: true,
            zed: true,
            spicetify: true,
            discord: true,
            todoist: true,
            firefox: true,
        }
    }
}

/// Whether the Todoist AppImage is already in place. The step behind the row downloads it to
/// `~/.local/bin/todoist.AppImage` rather than through the package manager, so asking PATH for
/// `todoist` would report it missing on every machine that has it.
fn todoist_here() -> bool {
    process::is_executable(&crate::paths::home().join(".local/bin/todoist.AppImage"))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn every_id_the_row_filter_names_is_an_app_of_this_struct() {
        for id in Apps::IDS {
            assert!(
                Apps::all().has(id),
                "{id} is an app but nothing here reads it"
            );
        }
        assert_eq!(Apps::all().answers().count(), Apps::IDS.len());
        assert!(Apps::all().any());
    }

    #[test]
    fn nothing_found_answers_no_to_every_app() {
        let none = Apps::default();
        for (id, answer) in none.answers() {
            assert_eq!(answer, "false", "{id} was left on");
        }
        assert!(!none.any());
        assert!(!none.has("INSTALL_VSCODE"));
    }

    #[test]
    fn a_row_about_something_other_than_an_app_is_never_hidden() {
        let none = Apps::default();
        for id in ["INSTALL_SDDM", "APPLY_FONTS", "DEFAULT_SHELL"] {
            assert!(none.has(id), "{id} is not an app row");
        }
    }
}
