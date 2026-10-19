use crate::process;

const ASK: [&str; 3] = ["org.kde.Shutdown", "/Shutdown", "org.kde.Shutdown.logout"];

pub fn now() -> Result<(), String> {
    let asked = ["qdbus6", "qdbus"]
        .into_iter()
        .filter(|program| process::available(program))
        .any(|program| process::succeeds(program, &ASK, None));
    if asked {
        Ok(())
    } else {
        Err(
            "Could not ask the session to log out. Log out from the desktop's own menu."
                .to_string(),
        )
    }
}
