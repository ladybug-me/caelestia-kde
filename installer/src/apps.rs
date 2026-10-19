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
    pub const IDS: [&'static str; 6] = [
        "INSTALL_VSCODE",
        "INSTALL_ZED",
        "INSTALL_SPICETIFY",
        "INSTALL_DISCORD",
        "INSTALL_TODOIST",
        "INSTALL_FIREFOX_THEME",
    ];

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

    pub fn is_app_row(&self, id: &str) -> bool {
        Self::IDS.contains(&id)
    }

    pub fn answers(&self) -> impl Iterator<Item = (&'static str, &'static str)> {
        Self::IDS
            .iter()
            .map(|id| (*id, if self.has(id) { "true" } else { "false" }))
    }

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
        assert!(Apps::IDS.iter().any(|id| Apps::all().has(id)));
    }

    #[test]
    fn nothing_found_answers_no_to_every_app() {
        let none = Apps::default();
        for (id, answer) in none.answers() {
            assert_eq!(answer, "false", "{id} was left on");
        }
        assert!(!none.answers().any(|(_, answer)| answer == "true"));
        assert!(!none.has("INSTALL_VSCODE"));
    }

    #[test]
    fn a_row_about_something_other_than_an_app_is_never_hidden() {
        let none = Apps::default();
        for id in ["SYNC_LOGIN_SCREEN", "APPLY_FONTS", "DEFAULT_SHELL"] {
            assert!(none.has(id), "{id} is not an app row");
        }
    }
}
