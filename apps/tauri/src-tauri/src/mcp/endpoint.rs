//! Endpoint file shared with `querya-mcp` (Flutter-compatible shape).

use serde::{Deserialize, Serialize};
use std::fs;
use std::io;
use std::path::{Path, PathBuf};

/// Overrides the endpoint file location (tests, several app instances).
pub const ENV_OVERRIDE: &str = "QUERYA_MCP_ENDPOINT";

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct McpEndpoint {
    pub port: u16,
    pub token: String,
    pub pid: u32,
    pub version: String,
}

impl McpEndpoint {
    /// `$XDG_RUNTIME_DIR/querya/mcp-endpoint.json` on Linux (falls back to
    /// `~/.cache/querya`), `~/Library/Caches/Querya` on macOS,
    /// `%LOCALAPPDATA%\Querya` on Windows.
    pub fn default_path() -> PathBuf {
        if let Ok(override_path) = std::env::var(ENV_OVERRIDE) {
            let trimmed = override_path.trim();
            if !trimmed.is_empty() {
                return PathBuf::from(trimmed);
            }
        }
        #[cfg(target_os = "windows")]
        {
            let base = std::env::var("LOCALAPPDATA")
                .or_else(|_| {
                    std::env::var("USERPROFILE").map(|h| {
                        format!("{h}\\AppData\\Local")
                    })
                })
                .unwrap_or_else(|_| ".".into());
            return PathBuf::from(base).join("Querya").join("mcp-endpoint.json");
        }
        #[cfg(target_os = "macos")]
        {
            let home = std::env::var("HOME").unwrap_or_else(|_| ".".into());
            return PathBuf::from(home)
                .join("Library")
                .join("Caches")
                .join("Querya")
                .join("mcp-endpoint.json");
        }
        #[cfg(not(any(target_os = "windows", target_os = "macos")))]
        {
            if let Ok(runtime) = std::env::var("XDG_RUNTIME_DIR") {
                if !runtime.trim().is_empty() {
                    return PathBuf::from(runtime)
                        .join("querya")
                        .join("mcp-endpoint.json");
                }
            }
            let home = std::env::var("HOME").unwrap_or_else(|_| ".".into());
            PathBuf::from(home)
                .join(".cache")
                .join("querya")
                .join("mcp-endpoint.json")
        }
    }

    /// 32 random bytes as hex (Flutter `McpEndpoint.newToken` parity).
    pub fn new_token() -> String {
        use rand::Rng;
        let mut bytes = [0u8; 32];
        rand::rng().fill_bytes(&mut bytes);
        bytes.iter().map(|b| format!("{b:02x}")).collect()
    }

    /// Constant-time comparison for the handshake token.
    pub fn tokens_equal(a: &str, b: &str) -> bool {
        let x = a.as_bytes();
        let y = b.as_bytes();
        let mut diff = x.len() ^ y.len();
        let n = x.len().min(y.len());
        for i in 0..n {
            diff |= usize::from(x[i] ^ y[i]);
        }
        diff == 0
    }

    pub fn write(&self, path: &Path) -> io::Result<()> {
        if let Some(parent) = path.parent() {
            fs::create_dir_all(parent)?;
            #[cfg(unix)]
            {
                use std::os::unix::fs::PermissionsExt;
                let _ = fs::set_permissions(parent, fs::Permissions::from_mode(0o700));
            }
        }
        let tmp = path.with_extension("json.tmp");
        fs::write(&tmp, "")?;
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            let _ = fs::set_permissions(&tmp, fs::Permissions::from_mode(0o600));
        }
        fs::write(&tmp, serde_json::to_vec(self).expect("endpoint json"))?;
        fs::rename(&tmp, path)?;
        Ok(())
    }

    pub fn read(path: &Path) -> io::Result<Option<Self>> {
        match fs::read_to_string(path) {
            Ok(raw) => Ok(serde_json::from_str(&raw).ok()),
            Err(e) if e.kind() == io::ErrorKind::NotFound => Ok(None),
            Err(e) => Err(e),
        }
    }

    pub fn clear(path: &Path) -> io::Result<()> {
        match fs::remove_file(path) {
            Ok(()) => Ok(()),
            Err(e) if e.kind() == io::ErrorKind::NotFound => Ok(()),
            Err(e) => Err(e),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn tokens_equal_rejects_mismatch() {
        assert!(McpEndpoint::tokens_equal("abc", "abc"));
        assert!(!McpEndpoint::tokens_equal("abc", "abd"));
        assert!(!McpEndpoint::tokens_equal("abc", "ab"));
    }

    #[test]
    fn write_read_round_trip() {
        let dir = std::env::temp_dir().join(format!("querya-mcp-ep-{}", std::process::id()));
        let path = dir.join("mcp-endpoint.json");
        let ep = McpEndpoint {
            port: 12345,
            token: "deadbeef".into(),
            pid: 42,
            version: "0.1.0".into(),
        };
        ep.write(&path).unwrap();
        let back = McpEndpoint::read(&path).unwrap().unwrap();
        assert_eq!(back, ep);
        McpEndpoint::clear(&path).unwrap();
        let _ = fs::remove_dir_all(&dir);
    }
}
