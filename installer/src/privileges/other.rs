use std::path::Path;

pub struct Credential;

impl Credential {
    pub fn install(_secret: &str, _exe: &Path) -> Result<Self, String> {
        Err("privilege escalation needs Linux".to_string())
    }

    pub fn environment(&self) -> Vec<(&'static str, String)> {
        Vec::new()
    }
}

pub fn accepts(_secret: &str) -> bool {
    false
}

pub fn locked_out() -> bool {
    false
}

pub fn on_the_last_entry() -> bool {
    false
}

pub struct Inhibitor;

impl Inhibitor {
    pub fn acquire() -> Self {
        Inhibitor
    }
}

pub fn read_secret(_pipe: &Path) -> Result<String, String> {
    Err("the askpass helper needs Linux".to_string())
}

pub fn is_root() -> bool {
    false
}

pub fn sudo_cached() -> bool {
    false
}

pub fn elevated(_program: &str, _args: &[&str], _directory: Option<&Path>) -> Result<i32, String> {
    Err("privilege escalation needs Linux".to_string())
}

pub fn quiet(_program: &str, _args: &[&str], _directory: Option<&Path>) -> Result<i32, String> {
    Err("privilege escalation needs Linux".to_string())
}

pub fn elevated_quietly(
    _program: &str,
    _args: &[&str],
    _directory: Option<&Path>,
) -> Result<i32, String> {
    Err("privilege escalation needs Linux".to_string())
}
