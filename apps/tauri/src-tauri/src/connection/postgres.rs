//! Postgres driver via sqlx (connect + disconnect).

use super::error::{ConnectionError, ConnectionResult};
use super::id::{ConnectionId, DriverKind};
use super::manager::ConnectionSession;
use super::runtime;
use sqlx::postgres::{PgConnectOptions, PgPoolOptions, PgSslMode};
use sqlx::{Pool, Postgres};
use std::str::FromStr;
use std::sync::{Arc, Mutex};
use std::time::Duration;

pub type PgPool = Pool<Postgres>;

pub struct PostgresSession {
    id: ConnectionId,
    host: String,
    port: u16,
    database: String,
    user: String,
    pool: Arc<Mutex<Option<PgPool>>>,
}

impl PostgresSession {
    pub fn host(&self) -> &str {
        &self.host
    }

    pub fn port(&self) -> u16 {
        self.port
    }

    pub fn database(&self) -> &str {
        &self.database
    }

    pub fn user(&self) -> &str {
        &self.user
    }

    pub fn clone_handle(&self) -> Self {
        Self {
            id: self.id.clone(),
            host: self.host.clone(),
            port: self.port,
            database: self.database.clone(),
            user: self.user.clone(),
            pool: Arc::clone(&self.pool),
        }
    }

    pub fn with_pool<T>(
        &self,
        f: impl FnOnce(&PgPool) -> ConnectionResult<T>,
    ) -> ConnectionResult<T> {
        let guard = self
            .pool
            .lock()
            .map_err(|_| ConnectionError::io("postgres pool lock poisoned"))?;
        let pool = guard
            .as_ref()
            .ok_or_else(|| ConnectionError::Disconnected {
                id: self.id.clone(),
            })?;
        f(pool)
    }

    pub fn execute_streaming(
        &self,
        sql: &str,
        limit: Option<usize>,
        emit: impl FnMut(super::query::QueryEvent) -> ConnectionResult<()>,
    ) -> ConnectionResult<()> {
        self.with_pool(|pool| {
            super::postgres_query::execute_streaming(pool, sql, limit, None, emit)
        })
    }
}

impl ConnectionSession for PostgresSession {
    fn id(&self) -> &ConnectionId {
        &self.id
    }

    fn driver(&self) -> DriverKind {
        DriverKind::Postgres
    }

    fn disconnect(&self) -> ConnectionResult<()> {
        let pool = {
            let mut guard = self
                .pool
                .lock()
                .map_err(|_| ConnectionError::io("postgres pool lock poisoned"))?;
            guard.take()
        };
        if let Some(pool) = pool {
            runtime::block_on(pool.close());
        }
        Ok(())
    }

    fn as_any(&self) -> &dyn std::any::Any {
        self
    }
}

pub struct PostgresConnectParams {
    pub host: String,
    pub port: u16,
    pub database: String,
    pub user: String,
    pub password: Option<String>,
    pub id: Option<ConnectionId>,
}

/// Open a Postgres pool and return a live session.
pub fn open_postgres(params: PostgresConnectParams) -> ConnectionResult<PostgresSession> {
    let host = params.host.trim();
    let database = params.database.trim();
    let user = params.user.trim();
    if host.is_empty() {
        return Err(ConnectionError::invalid_config("postgres host is empty"));
    }
    if database.is_empty() {
        return Err(ConnectionError::invalid_config("postgres database is empty"));
    }
    if user.is_empty() {
        return Err(ConnectionError::invalid_config("postgres user is empty"));
    }
    if params.port == 0 {
        return Err(ConnectionError::invalid_config("postgres port is 0"));
    }

    // Also accept full URLs in host for power users (`postgres://…`).
    let opts = if host.contains("://") {
        PgConnectOptions::from_str(host).map_err(|e| {
            ConnectionError::invalid_config(format!("invalid postgres url: {e}"))
        })?
    } else {
        let mut opts = PgConnectOptions::new()
            .host(host)
            .port(params.port)
            .username(user)
            .database(database)
            // No TLS feature wired yet — Disable matches local docker compose.
            .ssl_mode(PgSslMode::Disable);
        if let Some(pw) = params.password.as_deref() {
            opts = opts.password(pw);
        }
        opts
    };

    let id = params
        .id
        .filter(|i| !i.as_str().trim().is_empty())
        .unwrap_or_default();

    let pool = runtime::block_on(async {
        PgPoolOptions::new()
            .max_connections(4)
            .acquire_timeout(Duration::from_secs(8))
            .connect_with(opts)
            .await
    })
    .map_err(|e| ConnectionError::driver(DriverKind::Postgres, e.to_string()))?;

    runtime::block_on(async {
        sqlx::query("SELECT 1")
            .execute(&pool)
            .await
            .map_err(|e| ConnectionError::driver(DriverKind::Postgres, e.to_string()))
    })?;

    Ok(PostgresSession {
        id,
        host: host.to_owned(),
        port: params.port,
        database: database.to_owned(),
        user: user.to_owned(),
        pool: Arc::new(Mutex::new(Some(pool))),
    })
}
