//! Resolve sample / packaged extension executables.

use std::env;
use std::path::PathBuf;

const HELLO_ENV: &str = "QUERYA_HELLO_PANEL_BIN";
const HELLO_NAME: &str = if cfg!(windows) {
    "querya-ext-hello-panel.exe"
} else {
    "querya-ext-hello-panel"
};

/// Absolute path to the hello-panel sample binary.
///
/// Order: `QUERYA_HELLO_PANEL_BIN` → sibling of current exe → Cargo target dir.
pub fn hello_panel_executable() -> Result<PathBuf, String> {
    if let Ok(raw) = env::var(HELLO_ENV) {
        let path = PathBuf::from(raw.trim());
        if path.is_file() {
            return Ok(path);
        }
        return Err(format!(
            "{HELLO_ENV} is set but not a file: {}",
            path.display()
        ));
    }

    if let Ok(mut exe) = env::current_exe() {
        exe.pop();
        let sibling = exe.join(HELLO_NAME);
        if sibling.is_file() {
            return Ok(sibling);
        }
        // `target/{debug,release}/deps/<test>` → parent target profile dir
        if exe.ends_with("deps") {
            exe.pop();
            let candidate = exe.join(HELLO_NAME);
            if candidate.is_file() {
                return Ok(candidate);
            }
        }
    }

    Err(format!(
        "hello-panel binary not found (set {HELLO_ENV} or build --bin querya-ext-hello-panel)"
    ))
}
