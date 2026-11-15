//! Redis driver via the official `redis` crate (connect + SCAN / GET / SET).

use super::error::{ConnectionError, ConnectionResult};
use super::id::{ConnectionId, DriverKind};
use super::manager::ConnectionSession;
use redis::{Client, Commands, Connection};
use serde::{Deserialize, Serialize};
use std::sync::{Arc, Mutex};

pub struct RedisSession {
    id: ConnectionId,
    host: String,
    port: u16,
    db: u8,
    conn: Arc<Mutex<Option<Connection>>>,
}

impl RedisSession {
    pub fn host(&self) -> &str {
        &self.host
    }

    pub fn port(&self) -> u16 {
        self.port
    }

    pub fn db(&self) -> u8 {
        self.db
    }

    pub fn clone_handle(&self) -> Self {
        Self {
            id: self.id.clone(),
            host: self.host.clone(),
            port: self.port,
            db: self.db,
            conn: Arc::clone(&self.conn),
        }
    }

    pub fn with_connection<T>(
        &self,
        f: impl FnOnce(&mut Connection) -> ConnectionResult<T>,
    ) -> ConnectionResult<T> {
        let mut guard = self
            .conn
            .lock()
            .map_err(|_| ConnectionError::io("redis connection lock poisoned"))?;
        let conn = guard
            .as_mut()
            .ok_or_else(|| ConnectionError::Disconnected {
                id: self.id.clone(),
            })?;
        f(conn)
    }

    pub fn ping(&self) -> ConnectionResult<String> {
        self.with_connection(|c| {
            redis::cmd("PING")
                .query::<String>(c)
                .map_err(|e| ConnectionError::driver(DriverKind::Redis, e.to_string()))
        })
    }

    /// SCAN subset — returns next cursor + key page (Flutter `scan` parity).
    pub fn scan(
        &self,
        cursor: u64,
        pattern: Option<&str>,
        count: Option<usize>,
    ) -> ConnectionResult<RedisScanPage> {
        self.with_connection(|c| {
            let mut cmd = redis::cmd("SCAN");
            cmd.arg(cursor);
            if let Some(pat) = pattern {
                if !pat.is_empty() {
                    cmd.arg("MATCH").arg(pat);
                }
            }
            if let Some(n) = count {
                if n > 0 {
                    cmd.arg("COUNT").arg(n);
                }
            }
            let (next_cursor, keys): (u64, Vec<String>) = cmd
                .query(c)
                .map_err(|e| ConnectionError::driver(DriverKind::Redis, e.to_string()))?;
            Ok(RedisScanPage { next_cursor, keys })
        })
    }

    pub fn get(&self, key: &str) -> ConnectionResult<Option<String>> {
        self.with_connection(|c| {
            c.get(key)
                .map_err(|e| ConnectionError::driver(DriverKind::Redis, e.to_string()))
        })
    }

    pub fn set(&self, key: &str, value: &str) -> ConnectionResult<()> {
        self.with_connection(|c| {
            c.set::<_, _, ()>(key, value)
                .map_err(|e| ConnectionError::driver(DriverKind::Redis, e.to_string()))
        })
    }

    pub fn key_type(&self, key: &str) -> ConnectionResult<String> {
        self.with_connection(|c| {
            redis::cmd("TYPE")
                .arg(key)
                .query::<String>(c)
                .map_err(|e| ConnectionError::driver(DriverKind::Redis, e.to_string()))
        })
    }

    pub fn ttl(&self, key: &str) -> ConnectionResult<i64> {
        self.with_connection(|c| {
            redis::cmd("TTL")
                .arg(key)
                .query::<i64>(c)
                .map_err(|e| ConnectionError::driver(DriverKind::Redis, e.to_string()))
        })
    }

    /// Flutter `typesAndTtls` subset — TYPE (+ TTL) for a key page.
    pub fn types_and_ttls(&self, keys: &[String]) -> ConnectionResult<Vec<RedisKeyMeta>> {
        self.with_connection(|c| {
            let mut out = Vec::with_capacity(keys.len());
            for key in keys {
                let key_type: String = redis::cmd("TYPE")
                    .arg(key)
                    .query(c)
                    .map_err(|e| ConnectionError::driver(DriverKind::Redis, e.to_string()))?;
                let ttl: i64 = redis::cmd("TTL")
                    .arg(key)
                    .query(c)
                    .map_err(|e| ConnectionError::driver(DriverKind::Redis, e.to_string()))?;
                out.push(RedisKeyMeta {
                    key: key.clone(),
                    key_type,
                    ttl,
                });
            }
            Ok(out)
        })
    }

    /// Load key contents by TYPE (Flutter `RedisKeyEditor._load` parity).
    pub fn read_key(&self, key: &str) -> ConnectionResult<RedisKeyView> {
        let key_type = self.key_type(key)?;
        let ttl = self.ttl(key)?;
        match key_type.as_str() {
            "none" => Ok(RedisKeyView {
                key: key.to_owned(),
                key_type,
                ttl,
                string_value: None,
                hash_fields: vec![],
                list_values: vec![],
                set_members: vec![],
                zset_members: vec![],
            }),
            "string" => {
                let string_value = self.get(key)?;
                Ok(RedisKeyView {
                    key: key.to_owned(),
                    key_type,
                    ttl,
                    string_value,
                    hash_fields: vec![],
                    list_values: vec![],
                    set_members: vec![],
                    zset_members: vec![],
                })
            }
            "hash" => self.with_connection(|c| {
                let map: std::collections::HashMap<String, String> = redis::cmd("HGETALL")
                    .arg(key)
                    .query(c)
                    .map_err(|e| ConnectionError::driver(DriverKind::Redis, e.to_string()))?;
                let mut hash_fields: Vec<RedisHashField> = map
                    .into_iter()
                    .map(|(field, value)| RedisHashField { field, value })
                    .collect();
                hash_fields.sort_by(|a, b| a.field.cmp(&b.field));
                Ok(RedisKeyView {
                    key: key.to_owned(),
                    key_type,
                    ttl,
                    string_value: None,
                    hash_fields,
                    list_values: vec![],
                    set_members: vec![],
                    zset_members: vec![],
                })
            }),
            "list" => self.with_connection(|c| {
                let list_values: Vec<String> = redis::cmd("LRANGE")
                    .arg(key)
                    .arg(0)
                    .arg(199)
                    .query(c)
                    .map_err(|e| ConnectionError::driver(DriverKind::Redis, e.to_string()))?;
                Ok(RedisKeyView {
                    key: key.to_owned(),
                    key_type,
                    ttl,
                    string_value: None,
                    hash_fields: vec![],
                    list_values,
                    set_members: vec![],
                    zset_members: vec![],
                })
            }),
            "set" => self.with_connection(|c| {
                let mut set_members: Vec<String> = redis::cmd("SMEMBERS")
                    .arg(key)
                    .query(c)
                    .map_err(|e| ConnectionError::driver(DriverKind::Redis, e.to_string()))?;
                set_members.sort();
                Ok(RedisKeyView {
                    key: key.to_owned(),
                    key_type,
                    ttl,
                    string_value: None,
                    hash_fields: vec![],
                    list_values: vec![],
                    set_members,
                    zset_members: vec![],
                })
            }),
            "zset" => self.with_connection(|c| {
                let raw: Vec<(String, f64)> = redis::cmd("ZRANGE")
                    .arg(key)
                    .arg(0)
                    .arg(199)
                    .arg("WITHSCORES")
                    .query(c)
                    .map_err(|e| ConnectionError::driver(DriverKind::Redis, e.to_string()))?;
                let zset_members = raw
                    .into_iter()
                    .map(|(member, score)| RedisZsetMember { member, score })
                    .collect();
                Ok(RedisKeyView {
                    key: key.to_owned(),
                    key_type,
                    ttl,
                    string_value: None,
                    hash_fields: vec![],
                    list_values: vec![],
                    set_members: vec![],
                    zset_members,
                })
            }),
            other => Ok(RedisKeyView {
                key: key.to_owned(),
                key_type: other.to_owned(),
                ttl,
                string_value: None,
                hash_fields: vec![],
                list_values: vec![],
                set_members: vec![],
                zset_members: vec![],
            }),
        }
    }
}

impl ConnectionSession for RedisSession {
    fn id(&self) -> &ConnectionId {
        &self.id
    }

    fn driver(&self) -> DriverKind {
        DriverKind::Redis
    }

    fn disconnect(&self) -> ConnectionResult<()> {
        let mut guard = self
            .conn
            .lock()
            .map_err(|_| ConnectionError::io("redis connection lock poisoned"))?;
        *guard = None;
        Ok(())
    }

    fn as_any(&self) -> &dyn std::any::Any {
        self
    }
}

#[derive(Debug, Clone)]
pub struct RedisConnectParams {
    pub host: String,
    pub port: u16,
    pub password: Option<String>,
    pub username: Option<String>,
    pub db: Option<u8>,
    pub id: Option<ConnectionId>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct RedisScanPage {
    pub next_cursor: u64,
    pub keys: Vec<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct RedisKeyMeta {
    pub key: String,
    pub key_type: String,
    pub ttl: i64,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct RedisHashField {
    pub field: String,
    pub value: String,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct RedisZsetMember {
    pub member: String,
    pub score: f64,
}

/// Typed key payload for the browser (Flutter `RedisKeyEditor` load).
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct RedisKeyView {
    pub key: String,
    pub key_type: String,
    pub ttl: i64,
    pub string_value: Option<String>,
    pub hash_fields: Vec<RedisHashField>,
    pub list_values: Vec<String>,
    pub set_members: Vec<String>,
    pub zset_members: Vec<RedisZsetMember>,
}

/// Open a Redis TCP session and smoke with PING.
pub fn open_redis(params: RedisConnectParams) -> ConnectionResult<RedisSession> {
    let host = params.host.trim();
    if host.is_empty() {
        return Err(ConnectionError::invalid_config("redis host is empty"));
    }
    if params.port == 0 {
        return Err(ConnectionError::invalid_config("redis port is 0"));
    }
    let db = params.db.unwrap_or(0);

    let mut url = if let Some(pw) = params.password.as_deref().filter(|s| !s.is_empty()) {
        let user = params
            .username
            .as_deref()
            .filter(|s| !s.is_empty())
            .unwrap_or("default");
        // redis://user:password@host:port/db
        format!(
            "redis://{}:{}@{}:{}/{}",
            urlencoding_user(user),
            urlencoding_user(pw),
            host,
            params.port,
            db
        )
    } else {
        format!("redis://{}:{}/{}", host, params.port, db)
    };

    // Allow full redis:// URLs in host (advanced paste).
    if host.contains("://") {
        url = host.to_owned();
    }

    let client = Client::open(url.as_str())
        .map_err(|e| ConnectionError::invalid_config(format!("invalid redis url: {e}")))?;

    let mut conn = client
        .get_connection()
        .map_err(|e| ConnectionError::driver(DriverKind::Redis, e.to_string()))?;

    let pong: String = redis::cmd("PING")
        .query(&mut conn)
        .map_err(|e| ConnectionError::driver(DriverKind::Redis, e.to_string()))?;
    if !pong.eq_ignore_ascii_case("PONG") {
        return Err(ConnectionError::driver(
            DriverKind::Redis,
            format!("unexpected PING reply: {pong}"),
        ));
    }

    let id = params
        .id
        .filter(|i| !i.as_str().trim().is_empty())
        .unwrap_or_default();

    Ok(RedisSession {
        id,
        host: host.to_owned(),
        port: params.port,
        db,
        conn: Arc::new(Mutex::new(Some(conn))),
    })
}

fn urlencoding_user(s: &str) -> String {
    // Minimal encode for password special chars in redis URL.
    let mut out = String::with_capacity(s.len());
    for b in s.bytes() {
        match b {
            b'A'..=b'Z' | b'a'..=b'z' | b'0'..=b'9' | b'-' | b'_' | b'.' | b'~' => {
                out.push(b as char);
            }
            _ => out.push_str(&format!("%{b:02X}")),
        }
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    fn skip_live() -> bool {
        if std::env::var_os("QUERYA_SKIP_REDIS").is_some() {
            eprintln!("skip redis live test (QUERYA_SKIP_REDIS)");
            return true;
        }
        false
    }

    fn live_params() -> RedisConnectParams {
        let url = std::env::var("QUERYA_REDIS_URL").unwrap_or_else(|_| {
            "redis://127.0.0.1:6379/15".into()
        });
        // Parse host/port/db loosely from URL for open_redis host-url path.
        RedisConnectParams {
            host: url,
            port: 6379,
            password: None,
            username: None,
            db: Some(15),
            id: None,
        }
    }

    #[test]
    fn open_rejects_empty_host() {
        let result = open_redis(RedisConnectParams {
            host: "  ".into(),
            port: 6379,
            password: None,
            username: None,
            db: None,
            id: None,
        });
        assert!(matches!(result, Err(ConnectionError::InvalidConfig { .. })));
    }

    #[test]
    fn live_ping_set_get_scan() {
        if skip_live() {
            return;
        }
        let session = match open_redis(live_params()) {
            Ok(s) => s,
            Err(e) => {
                eprintln!("skip redis live test (connect failed: {e})");
                return;
            }
        };
        assert_eq!(session.ping().unwrap().to_uppercase(), "PONG");

        let key = format!("querya:test:{}", uuid::Uuid::new_v4());
        session.set(&key, "hello").unwrap();
        assert_eq!(session.get(&key).unwrap().as_deref(), Some("hello"));

        let mut cursor = 0u64;
        let mut found = false;
        for _ in 0..32 {
            let page = session
                .scan(cursor, Some("querya:test:*"), Some(50))
                .unwrap();
            if page.keys.iter().any(|k| k == &key) {
                found = true;
                break;
            }
            if page.next_cursor == 0 {
                break;
            }
            cursor = page.next_cursor;
        }
        assert!(found, "SCAN did not return {key}");

        // Cleanup
        let _ = session.with_connection(|c| {
            let _: () = redis::cmd("DEL")
                .arg(&key)
                .query(c)
                .map_err(|e| ConnectionError::driver(DriverKind::Redis, e.to_string()))?;
            Ok(())
        });

        let hash_key = format!("querya:test:hash:{}", uuid::Uuid::new_v4());
        session
            .with_connection(|c| {
                let _: () = redis::cmd("HSET")
                    .arg(&hash_key)
                    .arg("name")
                    .arg("Ada")
                    .arg("role")
                    .arg("admin")
                    .query(c)
                    .map_err(|e| ConnectionError::driver(DriverKind::Redis, e.to_string()))?;
                Ok(())
            })
            .unwrap();
        let view = session.read_key(&hash_key).unwrap();
        assert_eq!(view.key_type, "hash");
        assert!(view.hash_fields.iter().any(|f| f.field == "name" && f.value == "Ada"));
        let _ = session.with_connection(|c| {
            let _: () = redis::cmd("DEL")
                .arg(&hash_key)
                .query(c)
                .map_err(|e| ConnectionError::driver(DriverKind::Redis, e.to_string()))?;
            Ok(())
        });

        session.disconnect().unwrap();
    }
}
