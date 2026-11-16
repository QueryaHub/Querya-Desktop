//! MongoDB driver via the official `mongodb` crate (connect + list + find).

use super::error::{ConnectionError, ConnectionResult};
use super::id::{ConnectionId, DriverKind};
use super::manager::ConnectionSession;
use super::runtime;
use futures_util::TryStreamExt;
use mongodb::bson::{doc, Document};
use mongodb::options::{ClientOptions, FindOptions};
use mongodb::Client;
use serde::{Deserialize, Serialize};
use serde_json::Value as JsonValue;
use std::sync::{Arc, Mutex};
use std::time::Duration;

/// Flutter `kMongoDefaultFindLimit` parity.
pub const DEFAULT_FIND_LIMIT: i64 = 1000;

pub struct MongoSession {
    id: ConnectionId,
    host: String,
    port: u16,
    database: String,
    client: Arc<Mutex<Option<Client>>>,
}

impl MongoSession {
    pub fn host(&self) -> &str {
        &self.host
    }

    pub fn port(&self) -> u16 {
        self.port
    }

    pub fn database(&self) -> &str {
        &self.database
    }

    pub fn clone_handle(&self) -> Self {
        Self {
            id: self.id.clone(),
            host: self.host.clone(),
            port: self.port,
            database: self.database.clone(),
            client: Arc::clone(&self.client),
        }
    }

    fn with_client<T>(
        &self,
        f: impl FnOnce(&Client) -> ConnectionResult<T>,
    ) -> ConnectionResult<T> {
        let guard = self
            .client
            .lock()
            .map_err(|_| ConnectionError::io("mongo client lock poisoned"))?;
        let client = guard
            .as_ref()
            .ok_or_else(|| ConnectionError::Disconnected {
                id: self.id.clone(),
            })?;
        f(client)
    }

    pub fn ping(&self) -> ConnectionResult<String> {
        self.with_client(|client| {
            runtime::block_on(async {
                client
                    .database("admin")
                    .run_command(doc! { "ping": 1 })
                    .await
                    .map_err(|e| ConnectionError::driver(DriverKind::Mongo, e.to_string()))?;
                Ok("ok".into())
            })
        })
    }

    pub fn list_databases(&self) -> ConnectionResult<Vec<String>> {
        self.with_client(|client| {
            runtime::block_on(async {
                client
                    .list_database_names()
                    .await
                    .map_err(|e| ConnectionError::driver(DriverKind::Mongo, e.to_string()))
            })
        })
    }

    pub fn list_collections(&self, database: &str) -> ConnectionResult<Vec<String>> {
        let db = database.trim();
        if db.is_empty() {
            return Err(ConnectionError::invalid_config("mongo database is empty"));
        }
        self.with_client(|client| {
            runtime::block_on(async {
                client
                    .database(db)
                    .list_collection_names()
                    .await
                    .map_err(|e| ConnectionError::driver(DriverKind::Mongo, e.to_string()))
            })
        })
    }

    pub fn find(
        &self,
        database: &str,
        collection: &str,
        filter_json: Option<&str>,
        limit: Option<i64>,
    ) -> ConnectionResult<MongoFindResult> {
        let db = database.trim();
        let coll = collection.trim();
        if db.is_empty() || coll.is_empty() {
            return Err(ConnectionError::invalid_config(
                "mongo database and collection are required",
            ));
        }
        let limit = limit
            .unwrap_or(DEFAULT_FIND_LIMIT)
            .clamp(1, DEFAULT_FIND_LIMIT);

        let filter = match filter_json.map(str::trim).filter(|s| !s.is_empty()) {
            Some(raw) => {
                let v: JsonValue = serde_json::from_str(raw).map_err(|e| {
                    ConnectionError::invalid_config(format!("invalid mongo filter JSON: {e}"))
                })?;
                mongodb::bson::to_document(&v).map_err(|e| {
                    ConnectionError::invalid_config(format!("mongo filter must be an object: {e}"))
                })?
            }
            None => Document::new(),
        };

        self.with_client(|client| {
            runtime::block_on(async {
                let options = FindOptions::builder().limit(limit).build();
                let mut cursor = client
                    .database(db)
                    .collection::<Document>(coll)
                    .find(filter)
                    .with_options(options)
                    .await
                    .map_err(|e| ConnectionError::driver(DriverKind::Mongo, e.to_string()))?;

                let mut documents = Vec::new();
                while let Some(doc) = cursor
                    .try_next()
                    .await
                    .map_err(|e| ConnectionError::driver(DriverKind::Mongo, e.to_string()))?
                {
                    let json = bson_document_to_json(doc)?;
                    documents.push(json);
                }
                let truncated = documents.len() as i64 >= limit;
                Ok(MongoFindResult {
                    documents,
                    truncated,
                })
            })
        })
    }
}

impl ConnectionSession for MongoSession {
    fn id(&self) -> &ConnectionId {
        &self.id
    }

    fn driver(&self) -> DriverKind {
        DriverKind::Mongo
    }

    fn disconnect(&self) -> ConnectionResult<()> {
        let mut guard = self
            .client
            .lock()
            .map_err(|_| ConnectionError::io("mongo client lock poisoned"))?;
        *guard = None;
        Ok(())
    }

    fn as_any(&self) -> &dyn std::any::Any {
        self
    }
}

#[derive(Debug, Clone)]
pub struct MongoConnectParams {
    pub host: String,
    pub port: u16,
    pub database: String,
    pub username: Option<String>,
    pub password: Option<String>,
    pub auth_source: Option<String>,
    pub id: Option<ConnectionId>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct MongoFindResult {
    pub documents: Vec<JsonValue>,
    pub truncated: bool,
}

/// Open a Mongo client and smoke with ping.
pub fn open_mongo(params: MongoConnectParams) -> ConnectionResult<MongoSession> {
    let host = params.host.trim();
    let database = params.database.trim();
    if host.is_empty() {
        return Err(ConnectionError::invalid_config("mongo host is empty"));
    }
    if params.port == 0 {
        return Err(ConnectionError::invalid_config("mongo port is 0"));
    }
    let database = if database.is_empty() {
        "querya".to_owned()
    } else {
        database.to_owned()
    };

    let uri = if host.contains("://") {
        host.to_owned()
    } else {
        build_uri(
            host,
            params.port,
            &database,
            params.username.as_deref(),
            params.password.as_deref(),
            params.auth_source.as_deref(),
        )
    };

    let client = runtime::block_on(async {
        let mut opts = ClientOptions::parse(&uri)
            .await
            .map_err(|e| ConnectionError::invalid_config(format!("invalid mongo uri: {e}")))?;
        opts.server_selection_timeout = Some(Duration::from_secs(8));
        opts.connect_timeout = Some(Duration::from_secs(8));
        Client::with_options(opts)
            .map_err(|e| ConnectionError::driver(DriverKind::Mongo, e.to_string()))
    })?;

    runtime::block_on(async {
        client
            .database("admin")
            .run_command(doc! { "ping": 1 })
            .await
            .map_err(|e| ConnectionError::driver(DriverKind::Mongo, e.to_string()))
    })?;

    let id = params
        .id
        .filter(|i| !i.as_str().trim().is_empty())
        .unwrap_or_default();

    Ok(MongoSession {
        id,
        host: host.to_owned(),
        port: params.port,
        database,
        client: Arc::new(Mutex::new(Some(client))),
    })
}

fn build_uri(
    host: &str,
    port: u16,
    database: &str,
    username: Option<&str>,
    password: Option<&str>,
    auth_source: Option<&str>,
) -> String {
    let auth_db = auth_source.unwrap_or("admin");
    match (username.filter(|s| !s.is_empty()), password) {
        (Some(user), Some(pw)) if !pw.is_empty() => {
            format!(
                "mongodb://{}:{}@{}:{}/{}?authSource={}",
                urlencoding_user(user),
                urlencoding_user(pw),
                host,
                port,
                database,
                auth_db
            )
        }
        (Some(user), _) => format!(
            "mongodb://{}@{}:{}/{}?authSource={}",
            urlencoding_user(user),
            host,
            port,
            database,
            auth_db
        ),
        _ => format!("mongodb://{host}:{port}/{database}"),
    }
}

fn urlencoding_user(s: &str) -> String {
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

fn bson_document_to_json(doc: Document) -> ConnectionResult<JsonValue> {
    serde_json::to_value(doc)
        .map_err(|e| ConnectionError::driver(DriverKind::Mongo, e.to_string()))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn skip_live() -> bool {
        if std::env::var_os("QUERYA_SKIP_MONGO").is_some() {
            eprintln!("skip mongo live test (QUERYA_SKIP_MONGO)");
            return true;
        }
        false
    }

    fn live_params() -> MongoConnectParams {
        let uri = std::env::var("QUERYA_MONGO_URI").unwrap_or_else(|_| {
            "mongodb://querya:querya@127.0.0.1:27017/querya?authSource=admin".into()
        });
        MongoConnectParams {
            host: uri,
            port: 27017,
            database: "querya".into(),
            username: None,
            password: None,
            auth_source: None,
            id: None,
        }
    }

    #[test]
    fn open_rejects_empty_host() {
        let result = open_mongo(MongoConnectParams {
            host: "  ".into(),
            port: 27017,
            database: "querya".into(),
            username: None,
            password: None,
            auth_source: None,
            id: None,
        });
        assert!(matches!(result, Err(ConnectionError::InvalidConfig { .. })));
    }

    #[test]
    fn live_ping_list_find() {
        if skip_live() {
            return;
        }
        let session = match open_mongo(live_params()) {
            Ok(s) => s,
            Err(e) => {
                eprintln!("skip mongo live test (connect failed: {e})");
                return;
            }
        };
        assert_eq!(session.ping().unwrap(), "ok");
        let dbs = session.list_databases().unwrap();
        assert!(dbs.iter().any(|d| d == "querya"), "{dbs:?}");
        let cols = session.list_collections("querya").unwrap();
        assert!(
            cols.iter().any(|c| c == "users"),
            "expected users in {cols:?}"
        );
        let found = session.find("querya", "users", None, Some(5)).unwrap();
        assert!(!found.documents.is_empty(), "users should have docs");
        session.disconnect().unwrap();
    }
}
