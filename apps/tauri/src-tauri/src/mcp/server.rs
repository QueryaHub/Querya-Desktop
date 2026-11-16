//! MCP tools: `list_connections` and `run_query` over the live ConnectionManager.

use crate::connection::{
    ConnectionId, ConnectionManager, ConnectionRegistry, DriverKind, QueryEvent,
};
use rmcp::handler::server::wrapper::Parameters;
use rmcp::handler::server::ServerHandler;
use rmcp::model::{
    CallToolResult, ContentBlock, Implementation, ServerCapabilities, ServerConfig,
};
use rmcp::{schemars, tool, tool_handler, tool_router};
use serde::{Deserialize, Serialize};
use serde_json::json;
use std::sync::Arc;

const MCP_MAX_ROWS: usize = 1000;

#[derive(Clone)]
pub struct QueryaMcpServer {
    registry: Arc<ConnectionRegistry>,
    tool_router: rmcp::handler::server::router::tool::ToolRouter<Self>,
}

impl QueryaMcpServer {
    pub fn new(registry: Arc<ConnectionRegistry>) -> Self {
        Self {
            registry,
            tool_router: Self::tool_router(),
        }
    }
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
struct RunQueryArgs {
    /// Connection id from `list_connections`.
    connection_id: String,
    /// Single read-only SQL statement.
    sql: String,
}

#[derive(Debug, Serialize)]
struct McpConnectionInfo {
    id: String,
    #[serde(rename = "type")]
    driver: String,
    name: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    database: Option<String>,
}

#[derive(Debug, Serialize)]
struct McpQueryResult {
    columns: Vec<String>,
    rows: Vec<Vec<serde_json::Value>>,
    row_count: u64,
    truncated: bool,
}

#[tool_router]
impl QueryaMcpServer {
    #[tool(
        description = "List live SQL connections currently open in Querya Desktop (id, type, name)."
    )]
    fn list_connections(&self) -> Result<CallToolResult, String> {
        let sessions = self
            .registry
            .list_sessions()
            .map_err(|e| e.to_string())?;
        let mut out = Vec::new();
        for (id, driver) in sessions {
            // Redis/Mongo are not exposed via SQL MCP tools yet.
            if matches!(driver, DriverKind::Redis | DriverKind::Mongo) {
                continue;
            }
            let (name, database) = connection_label(&self.registry, &id, driver);
            out.push(McpConnectionInfo {
                id: id.as_str().to_owned(),
                driver: driver.as_str().to_owned(),
                name,
                database,
            });
        }
        ok_json(&out)
    }

    #[tool(
        description = "Run a single read-only SQL statement on a live connection. Only SELECT / WITH / PRAGMA (schema) / EXPLAIN (no ANALYZE) / SHOW / DESCRIBE / VALUES."
    )]
    fn run_query(
        &self,
        Parameters(args): Parameters<RunQueryArgs>,
    ) -> Result<CallToolResult, String> {
        let id = ConnectionId::from(args.connection_id.trim());
        if !self.registry.is_connected(&id) {
            return Err(format!("connection not found or not connected: {id}"));
        }
        let driver = self
            .registry
            .driver_of(&id)
            .ok_or_else(|| format!("connection not found: {id}"))?;
        if matches!(driver, DriverKind::Redis | DriverKind::Mongo) {
            return Err(format!(
                "run_query does not support {} connections",
                driver.as_str()
            ));
        }

        let mut columns = Vec::new();
        let mut rows = Vec::new();
        let mut truncated = false;
        let mut row_count = 0u64;
        let mut error: Option<String> = None;

        self.registry
            .execute_query(&id, &args.sql, Some(MCP_MAX_ROWS), false, |ev| {
                match ev {
                    QueryEvent::Columns { names } => columns = names,
                    QueryEvent::Rows {
                        rows: chunk,
                        offset: _,
                    } => {
                        rows.extend(chunk);
                    }
                    QueryEvent::Done {
                        row_count: n,
                        truncated: t,
                        ..
                    } => {
                        row_count = n;
                        truncated = t;
                    }
                    QueryEvent::Error { message } => error = Some(message),
                }
                Ok(())
            })
            .map_err(|e| e.to_string())?;

        if let Some(message) = error {
            return Err(message);
        }

        ok_json(&McpQueryResult {
            columns,
            rows,
            row_count,
            truncated,
        })
    }
}

#[tool_handler(router = self.tool_router)]
impl ServerHandler for QueryaMcpServer {
    fn get_info(&self) -> ServerConfig {
        ServerConfig::new(ServerCapabilities::builder().enable_tools().build())
            .with_server_info(Implementation::new(
                "querya-desktop",
                env!("CARGO_PKG_VERSION"),
            ))
            .with_instructions(
                "Start with list_connections, then run_query for read-only SQL on a live connection.",
            )
    }
}

fn connection_label(
    registry: &ConnectionRegistry,
    id: &ConnectionId,
    driver: DriverKind,
) -> (String, Option<String>) {
    match driver {
        DriverKind::Sqlite => registry
            .with_sqlite(id, |s| Ok((s.path().to_owned(), Some(s.path().to_owned()))))
            .unwrap_or_else(|_| (id.as_str().to_owned(), None)),
        DriverKind::Postgres => registry
            .with_postgres(id, |s| {
                Ok((
                    format!("{}:{}/{}", s.host(), s.port(), s.database()),
                    Some(s.database().to_owned()),
                ))
            })
            .unwrap_or_else(|_| (id.as_str().to_owned(), None)),
        DriverKind::Mysql => registry
            .with_mysql(id, |s| {
                Ok((
                    format!("{}:{}/{}", s.host(), s.port(), s.database()),
                    Some(s.database().to_owned()),
                ))
            })
            .unwrap_or_else(|_| (id.as_str().to_owned(), None)),
        DriverKind::Redis | DriverKind::Mongo => (id.as_str().to_owned(), None),
    }
}

fn ok_json<T: Serialize>(value: &T) -> Result<CallToolResult, String> {
    let text = serde_json::to_string_pretty(value).map_err(|e| e.to_string())?;
    Ok(CallToolResult::success(vec![ContentBlock::text(text)]))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::connection::ConnectionConfig;
    use crate::mcp::endpoint::McpEndpoint;
    use crate::mcp::host::McpController;
    use std::time::Duration;
    use tokio::io::{AsyncBufReadExt, AsyncWriteExt, BufReader};
    use tokio::net::TcpStream;

    #[test]
    fn list_connections_and_run_query_on_sqlite() {
        if std::env::var_os("QUERYA_SKIP_MCP").is_some() {
            return;
        }

        let dir = std::env::temp_dir().join(format!(
            "querya-mcp-tools-{}-{}",
            std::process::id(),
            uuid::Uuid::new_v4()
        ));
        std::fs::create_dir_all(&dir).unwrap();
        let db_path = dir.join("fixture.db");
        let ep_path = dir.join("mcp-endpoint.json");

        {
            let conn = rusqlite::Connection::open(&db_path).unwrap();
            conn.execute_batch(
                "CREATE TABLE items (id INTEGER PRIMARY KEY, name TEXT);
                 INSERT INTO items (name) VALUES ('alpha'), ('beta');",
            )
            .unwrap();
        }

        let registry = Arc::new(ConnectionRegistry::new());
        let conn_id = registry
            .connect(ConnectionConfig::Sqlite {
                path: db_path.to_string_lossy().into_owned(),
                id: Some("fixture-sqlite".into()),
            })
            .unwrap();
        assert_eq!(conn_id.as_str(), "fixture-sqlite");

        crate::connection::runtime::block_on(async {
            let ctrl = McpController::new(Arc::clone(&registry));
            let status = ctrl
                .start_async(Some(ep_path.clone()))
                .await
                .expect("start");
            let port = status.port.unwrap();
            let endpoint = McpEndpoint::read(&ep_path).unwrap().unwrap();

            let mut stream = TcpStream::connect(("127.0.0.1", port)).await.unwrap();
            stream
                .write_all(format!("{}\n", endpoint.token).as_bytes())
                .await
                .unwrap();

            let init = r#"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-11-25","capabilities":{},"clientInfo":{"name":"querya-test","version":"0.0.1"}}}"#;
            stream
                .write_all(format!("{init}\n").as_bytes())
                .await
                .unwrap();
            let mut reader = BufReader::new(stream);
            let mut line = String::new();
            reader.read_line(&mut line).await.unwrap();
            reader
                .get_mut()
                .write_all(b"{\"jsonrpc\":\"2.0\",\"method\":\"notifications/initialized\"}\n")
                .await
                .unwrap();

            let list = r#"{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"list_connections","arguments":{}}}"#;
            reader
                .get_mut()
                .write_all(format!("{list}\n").as_bytes())
                .await
                .unwrap();
            line.clear();
            tokio::time::timeout(Duration::from_secs(3), reader.read_line(&mut line))
                .await
                .unwrap()
                .unwrap();
            let list_v: serde_json::Value = serde_json::from_str(line.trim()).unwrap();
            let text = list_v["result"]["content"][0]["text"].as_str().unwrap();
            assert!(
                text.contains("fixture-sqlite"),
                "list_connections missing fixture: {text}"
            );

            let query = json!({
                "jsonrpc": "2.0",
                "id": 3,
                "method": "tools/call",
                "params": {
                    "name": "run_query",
                    "arguments": {
                        "connection_id": "fixture-sqlite",
                        "sql": "SELECT name FROM items ORDER BY id"
                    }
                }
            });
            reader
                .get_mut()
                .write_all(format!("{query}\n").as_bytes())
                .await
                .unwrap();
            line.clear();
            tokio::time::timeout(Duration::from_secs(3), reader.read_line(&mut line))
                .await
                .unwrap()
                .unwrap();
            let qv: serde_json::Value = serde_json::from_str(line.trim()).unwrap();
            let qtext = qv["result"]["content"][0]["text"].as_str().unwrap();
            assert!(qtext.contains("alpha") && qtext.contains("beta"), "{qtext}");

            let _ = ctrl.stop_async().await;
        });

        let _ = std::fs::remove_dir_all(&dir);
    }
}
