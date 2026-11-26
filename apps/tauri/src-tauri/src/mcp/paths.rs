//! Resolve the `querya-mcp` stdio shim next to the desktop binary.

use std::env;
use std::path::PathBuf;

const NAME: &str = if cfg!(windows) {
    "querya-mcp.exe"
} else {
    "querya-mcp"
};

/// Absolute path when the shim sits beside the running executable.
pub fn mcp_shim_executable() -> Result<PathBuf, String> {
    if let Ok(raw) = env::var("QUERYA_MCP_SHIM") {
        let path = PathBuf::from(raw.trim());
        if path.is_file() {
            return Ok(path);
        }
        return Err(format!(
            "QUERYA_MCP_SHIM is set but not a file: {}",
            path.display()
        ));
    }

    let mut exe = env::current_exe().map_err(|e| format!("current_exe: {e}"))?;
    exe.pop();
    let sibling = exe.join(NAME);
    if sibling.is_file() {
        return Ok(sibling);
    }
    if exe.ends_with("deps") {
        exe.pop();
        let candidate = exe.join(NAME);
        if candidate.is_file() {
            return Ok(candidate);
        }
    }
    Err(format!(
        "{NAME} not found next to the app (build --bin querya-mcp or set QUERYA_MCP_SHIM)"
    ))
}
