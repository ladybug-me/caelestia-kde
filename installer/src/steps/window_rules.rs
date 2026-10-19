use std::fs;
use std::path::{Path, PathBuf};

use crate::output;
use crate::paths;
use crate::process;
use crate::steps::{Context, Failure};

const RULES_FILE: &str = "kwinrulesrc";
const OWN_GROUPS: [&str; 3] = ["caelestia-opacity", "caelestia-dialogs", "caelestia-pip"];

enum Outcome {
    Written,
    Unchanged,
    Failed,
}

#[derive(Default)]
struct Tally {
    written: u32,
    failed: u32,
}

pub fn run(context: &Context) -> Result<(), Failure> {
    println!();
    println!();
    output::info("Applying KWin window rules");
    println!();

    if !context.flag("APPLY_WINDOW_RULES", true) {
        output::skip("Skipping window rules");
        return Ok(());
    }

    if !process::available("kwriteconfig6") {
        output::warn("kwriteconfig6 not found - skipping window rules.");
        return Ok(());
    }

    let opacity = context
        .variable("WINDOW_OPACITY")
        .unwrap_or_else(|| "95".to_string());
    let mut tally = Tally::default();

    let opacity_keys = [
        ("Description", "Caelestia: window opacity"),
        ("types", "33"),
        ("opacityinactive", opacity.as_str()),
        ("opacityinactiverule", "2"),
    ];
    apply_group(
        "caelestia-opacity",
        "window opacity",
        &opacity_keys,
        &mut tally,
    );

    let dialog_keys = [
        ("Description", "Caelestia: center dialogs"),
        ("types", "32"),
        ("placement", "5"),
        ("placementrule", "2"),
    ];
    apply_group(
        "caelestia-dialogs",
        "dialog centering",
        &dialog_keys,
        &mut tally,
    );

    let pin_keys = [
        ("Description", "Caelestia: pin picture-in-picture"),
        ("title", "Picture(-| )in(-| )[Pp]icture"),
        ("titlematch", "3"),
        ("above", "true"),
        ("aboverule", "2"),
    ];
    apply_group(
        "caelestia-pip",
        "picture-in-picture pin",
        &pin_keys,
        &mut tally,
    );

    let current = read_key("General", "rules");
    let groups = list_rule_groups(&rules_path());
    let (index, count) = build_rule_index(&current, &groups);
    let count_text = count.to_string();
    let index_keys = [("rules", index.as_str()), ("count", count_text.as_str())];
    apply_group("General", "the rule index", &index_keys, &mut tally);

    if process::available("qdbus6") {
        let _ = process::succeeds("qdbus6", &["org.kde.KWin", "/KWin", "reconfigure"], None);
    } else {
        output::warn("qdbus6 not found - KWin picks the rules up on its next restart.");
    }

    if tally.failed > 0 {
        output::warn(&format!(
            "Window rules not fully applied: {} key(s) rejected, {} written.",
            tally.failed, tally.written
        ));
    } else if tally.written > 0 {
        output::ok("Window rules applied.");
    } else {
        output::skip("Window rules already in place.");
    }
    output::info(&format!("Rule index names {count} group(s)."));
    Ok(())
}

fn rules_path() -> PathBuf {
    let config = std::env::var_os("XDG_CONFIG_HOME")
        .map(PathBuf::from)
        .filter(|path| !path.as_os_str().is_empty())
        .unwrap_or_else(|| paths::home().join(".config"));
    config.join(RULES_FILE)
}

fn read_key(group: &str, key: &str) -> String {
    process::capture(
        "kreadconfig6",
        &["--file", RULES_FILE, "--group", group, "--key", key],
    )
    .unwrap_or_default()
}

fn set_key(group: &str, key: &str, value: &str) -> Outcome {
    if read_key(group, key) == value {
        return Outcome::Unchanged;
    }

    let _ = process::succeeds(
        "kwriteconfig6",
        &["--file", RULES_FILE, "--group", group, "--key", key, value],
        None,
    );

    if read_key(group, key) == value {
        Outcome::Written
    } else {
        Outcome::Failed
    }
}

fn apply_group(group: &str, label: &str, keys: &[(&str, &str)], tally: &mut Tally) {
    let mut written = 0;
    let mut failed = 0;
    for (key, value) in keys {
        match set_key(group, key, value) {
            Outcome::Written => written += 1,
            Outcome::Failed => failed += 1,
            Outcome::Unchanged => {}
        }
    }

    tally.written += written;
    tally.failed += failed;

    if failed > 0 {
        output::warn(&format!(
            "{failed} of {} key(s) for {label} could not be written.",
            written + failed
        ));
    } else if written > 0 {
        output::ok(&format!("Applied {label}."));
    } else {
        output::skip(&format!("{label} already in place."));
    }
}

fn list_rule_groups(path: &Path) -> Vec<String> {
    let Ok(text) = fs::read_to_string(path) else {
        return Vec::new();
    };

    text.lines()
        .filter_map(|line| {
            let name = line.trim().strip_prefix('[')?;
            let name = name.split(']').next()?.trim();
            if name.is_empty() || name == "General" || name.starts_with('$') {
                return None;
            }
            Some(name.to_string())
        })
        .collect()
}

fn add_to_index(names: &mut Vec<String>, name: &str) {
    let name = name.trim();
    if name.is_empty() || names.iter().any(|existing| existing == name) {
        return;
    }
    names.push(name.to_string());
}

fn build_rule_index(current: &str, groups: &[String]) -> (String, usize) {
    let mut names: Vec<String> = Vec::new();

    for name in current.split(',') {
        add_to_index(&mut names, name);
    }
    for group in groups {
        add_to_index(&mut names, group);
    }
    for group in OWN_GROUPS {
        add_to_index(&mut names, group);
    }

    (names.join(","), names.len())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::tmp::TempDir;

    #[test]
    fn the_index_is_a_union_in_the_order_names_were_first_seen() {
        let groups = vec!["caelestia-opacity".to_string(), "user-rule".to_string()];
        let (index, count) = build_rule_index("user-rule,caelestia-pip", &groups);

        assert_eq!(
            index,
            "user-rule,caelestia-pip,caelestia-opacity,caelestia-dialogs"
        );
        assert_eq!(count, 4);
    }

    #[test]
    fn a_name_already_in_the_index_is_not_added_twice() {
        let groups: Vec<String> = Vec::new();
        let (index, count) = build_rule_index("caelestia-opacity,,caelestia-opacity", &groups);

        assert_eq!(index, "caelestia-opacity,caelestia-dialogs,caelestia-pip");
        assert_eq!(count, 3);
    }

    #[test]
    fn the_names_the_index_carries_keep_the_users_spelling() {
        let groups: Vec<String> = Vec::new();
        let (index, _) = build_rule_index(" my-rule ,other", &groups);

        assert!(index.starts_with("my-rule,other,"), "{index}");
    }

    #[test]
    fn only_the_files_own_groups_are_listed() {
        let work = TempDir::new("caelestia-window-rules-test").expect("a temporary directory");
        let file = work.path().join(RULES_FILE);
        fs::write(
            &file,
            "\
[General]
rules=user-rule

[ user-rule ]
wmclass=keepme

[$Version]
update_info=kwinrules.upd:fix-rule-order

[caelestia-pip]
above=true
",
        )
        .expect("a rules file");

        assert_eq!(list_rule_groups(&file), ["user-rule", "caelestia-pip"]);
    }

    #[test]
    fn a_file_that_is_not_there_has_no_groups() {
        let work = TempDir::new("caelestia-window-rules-test").expect("a temporary directory");
        assert!(list_rule_groups(&work.path().join("missing")).is_empty());
    }
}
