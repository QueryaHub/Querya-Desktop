//! Live e2e: staging → generate → apply on Postgres / MySQL (#1992).
//!
//! Skips when `QUERYA_SKIP_PG` / `QUERYA_SKIP_MYSQL` is set, or when the
//! server is unreachable (same convention as query live tests).

#![cfg(test)]

use super::{
    apply_staging_mysql, apply_staging_postgres, ApplyError, StagingBuffer,
};
use crate::connection::manager::ConnectionSession;
use crate::connection::mysql::{open_mysql, MysqlConnectParams, MysqlSession, MySqlPool};
use crate::connection::postgres::{
    open_postgres, PgPool, PostgresConnectParams, PostgresSession,
};
use crate::connection::runtime;
use sqlx::Row;
use std::time::{SystemTime, UNIX_EPOCH};

fn unique_table(prefix: &str) -> String {
    let nanos = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_nanos();
    format!("{prefix}_{nanos}")
}

fn pg_params() -> Option<PostgresConnectParams> {
    if std::env::var_os("QUERYA_SKIP_PG").is_some() {
        return None;
    }
    let host = std::env::var("QUERYA_PG_HOST").unwrap_or_else(|_| "127.0.0.1".into());
    let port: u16 = std::env::var("QUERYA_PG_PORT")
        .ok()
        .and_then(|p| p.parse().ok())
        .unwrap_or(5432);
    let database = std::env::var("QUERYA_PG_DB").unwrap_or_else(|_| "querya".into());
    let user = std::env::var("QUERYA_PG_USER").unwrap_or_else(|_| "querya".into());
    let password = std::env::var("QUERYA_PG_PASSWORD").unwrap_or_else(|_| "querya".into());
    Some(PostgresConnectParams {
        host,
        port,
        database,
        user,
        password: Some(password),
        id: None,
    })
}

fn mysql_params() -> Option<MysqlConnectParams> {
    if std::env::var_os("QUERYA_SKIP_MYSQL").is_some() {
        return None;
    }
    let host = std::env::var("QUERYA_MYSQL_HOST").unwrap_or_else(|_| "127.0.0.1".into());
    let port: u16 = std::env::var("QUERYA_MYSQL_PORT")
        .ok()
        .and_then(|p| p.parse().ok())
        .unwrap_or(3306);
    let database = std::env::var("QUERYA_MYSQL_DB").unwrap_or_else(|_| "querya".into());
    let user = std::env::var("QUERYA_MYSQL_USER").unwrap_or_else(|_| "querya".into());
    let password = std::env::var("QUERYA_MYSQL_PASSWORD").unwrap_or_else(|_| "querya".into());
    Some(MysqlConnectParams {
        host,
        port,
        database,
        user,
        password: Some(password),
        id: None,
    })
}

struct PgHarness {
    session: PostgresSession,
    table: String,
}

impl PgHarness {
    fn try_new() -> Option<Self> {
        let params = pg_params()?;
        let session = match open_postgres(params) {
            Ok(s) => s,
            Err(e) => {
                eprintln!("skip postgres staging e2e: {e}");
                return None;
            }
        };
        let table = unique_table("querya_stg_pg");
        let stmts = [
            format!(
                "CREATE TABLE public.{table} (
              id INTEGER PRIMARY KEY,
              name TEXT NOT NULL,
              email TEXT
            )"
            ),
            format!(
                "INSERT INTO public.{table} (id, name, email) VALUES
              (1, 'Alice', 'alice@test.com'),
              (2, 'Bob', 'bob@test.com'),
              (3, 'Charlie', 'charlie@test.com')"
            ),
        ];
        if let Err(e) = session.with_pool(|pool| {
            runtime::block_on(async {
                for stmt in &stmts {
                    sqlx::query(stmt)
                        .execute(pool)
                        .await
                        .map_err(|e| {
                            crate::connection::ConnectionError::driver(
                                crate::connection::DriverKind::Postgres,
                                e.to_string(),
                            )
                        })?;
                }
                Ok(())
            })
        }) {
            eprintln!("skip postgres staging e2e (create): {e}");
            let _ = session.disconnect();
            return None;
        }
        Some(Self { session, table })
    }

    fn pool(&self) -> PgPool {
        self.session
            .with_pool(|p| Ok(p.clone()))
            .expect("pool")
    }

    fn load_buffer(&self) -> StagingBuffer {
        let sql = format!(
            "SELECT id, name, email FROM public.{} ORDER BY id",
            self.table
        );
        let pool = self.pool();
        let rows = runtime::block_on(async {
            let rows = sqlx::query(&sql).fetch_all(&pool).await.expect("select");
            rows.iter()
                .map(|r| {
                    vec![
                        r.get::<i32, _>(0).to_string(),
                        r.get::<String, _>(1),
                        r.try_get::<String, _>(2)
                            .unwrap_or_else(|_| "NULL".into()),
                    ]
                })
                .collect::<Vec<_>>()
        });
        StagingBuffer::new(["id", "name", "email"], rows, ["id"])
    }

    fn read_users(&self) -> Vec<(i32, String, Option<String>)> {
        let sql = format!(
            "SELECT id, name, email FROM public.{} ORDER BY id",
            self.table
        );
        let pool = self.pool();
        runtime::block_on(async {
            let rows = sqlx::query(&sql).fetch_all(&pool).await.expect("select");
            rows.iter()
                .map(|r| {
                    (
                        r.get::<i32, _>(0),
                        r.get::<String, _>(1),
                        r.try_get::<String, _>(2).ok(),
                    )
                })
                .collect()
        })
    }
}

impl Drop for PgHarness {
    fn drop(&mut self) {
        let drop = format!("DROP TABLE IF EXISTS public.{}", self.table);
        let _ = self.session.with_pool(|pool| {
            runtime::block_on(async {
                let _ = sqlx::query(&drop).execute(pool).await;
                Ok(())
            })
        });
        let _ = self.session.disconnect();
    }
}

struct MysqlHarness {
    session: MysqlSession,
    table: String,
}

impl MysqlHarness {
    fn try_new() -> Option<Self> {
        let params = mysql_params()?;
        let session = match open_mysql(params) {
            Ok(s) => s,
            Err(e) => {
                eprintln!("skip mysql staging e2e: {e}");
                return None;
            }
        };
        let table = unique_table("querya_stg_my");
        let create = format!(
            r#"
            CREATE TABLE `{table}` (
              id INT PRIMARY KEY,
              name VARCHAR(64) NOT NULL,
              email VARCHAR(128) NULL
            );
            INSERT INTO `{table}` (id, name, email) VALUES
              (1, 'Alice', 'alice@test.com'),
              (2, 'Bob', 'bob@test.com'),
              (3, 'Charlie', 'charlie@test.com');
            "#
        );
        if let Err(e) = session.with_pool(|pool| {
            runtime::block_on(async {
                // MySQL may need separate statements.
                for stmt in create.split(';').map(str::trim).filter(|s| !s.is_empty()) {
                    sqlx::query(stmt)
                        .execute(pool)
                        .await
                        .map_err(|e| crate::connection::ConnectionError::driver(
                            crate::connection::DriverKind::Mysql,
                            e.to_string(),
                        ))?;
                }
                Ok(())
            })
        }) {
            eprintln!("skip mysql staging e2e (create): {e}");
            let _ = session.disconnect();
            return None;
        }
        Some(Self { session, table })
    }

    fn pool(&self) -> MySqlPool {
        self.session
            .with_pool(|p| Ok(p.clone()))
            .expect("pool")
    }

    fn load_buffer(&self) -> StagingBuffer {
        let sql = format!(
            "SELECT id, name, email FROM `{}` ORDER BY id",
            self.table
        );
        let pool = self.pool();
        let rows = runtime::block_on(async {
            let rows = sqlx::query(&sql).fetch_all(&pool).await.expect("select");
            rows.iter()
                .map(|r| {
                    vec![
                        r.get::<i32, _>(0).to_string(),
                        r.get::<String, _>(1),
                        r.try_get::<String, _>(2)
                            .unwrap_or_else(|_| "NULL".into()),
                    ]
                })
                .collect::<Vec<_>>()
        });
        StagingBuffer::new(["id", "name", "email"], rows, ["id"])
    }

    fn read_users(&self) -> Vec<(i32, String, Option<String>)> {
        let sql = format!(
            "SELECT id, name, email FROM `{}` ORDER BY id",
            self.table
        );
        let pool = self.pool();
        runtime::block_on(async {
            let rows = sqlx::query(&sql).fetch_all(&pool).await.expect("select");
            rows.iter()
                .map(|r| {
                    (
                        r.get::<i32, _>(0),
                        r.get::<String, _>(1),
                        r.try_get::<String, _>(2).ok(),
                    )
                })
                .collect()
        })
    }
}

impl Drop for MysqlHarness {
    fn drop(&mut self) {
        let drop = format!("DROP TABLE IF EXISTS `{}`", self.table);
        let _ = self.session.with_pool(|pool| {
            runtime::block_on(async {
                let _ = sqlx::query(&drop).execute(pool).await;
                Ok(())
            })
        });
        let _ = self.session.disconnect();
    }
}

#[test]
fn e2e_postgres_stage_generate_apply_success() {
    let Some(h) = PgHarness::try_new() else {
        return;
    };
    let mut buf = h.load_buffer();
    buf.set_cell(0, 1, "Alice Cooper");
    buf.toggle_delete_row(1);
    buf.add_row(Some(vec![
        "4".into(),
        "Diana".into(),
        "diana@test.com".into(),
    ]));

    let result =
        apply_staging_postgres(&h.pool(), &mut buf, &h.table, Some("public")).unwrap();
    assert_eq!(result.statements_applied, 3);
    assert!(!buf.is_dirty());
    assert_eq!(
        h.read_users(),
        vec![
            (1, "Alice Cooper".into(), Some("alice@test.com".into())),
            (3, "Charlie".into(), Some("charlie@test.com".into())),
            (4, "Diana".into(), Some("diana@test.com".into())),
        ]
    );
}

#[test]
fn e2e_postgres_apply_failure_keeps_staging() {
    let Some(h) = PgHarness::try_new() else {
        return;
    };
    let mut buf = h.load_buffer();
    buf.set_cell(0, 1, "Alice Updated");
    buf.add_row(Some(vec![
        "1".into(),
        "Dup".into(),
        "dup@test.com".into(),
    ]));

    let err = apply_staging_postgres(&h.pool(), &mut buf, &h.table, Some("public")).unwrap_err();
    assert!(matches!(err, ApplyError::Execute { .. }), "{err:?}");
    assert!(buf.is_dirty());
    assert_eq!(buf.get_cell_value(0, 1), "Alice Updated");
    assert_eq!(
        h.read_users(),
        vec![
            (1, "Alice".into(), Some("alice@test.com".into())),
            (2, "Bob".into(), Some("bob@test.com".into())),
            (3, "Charlie".into(), Some("charlie@test.com".into())),
        ]
    );
}

#[test]
fn e2e_mysql_stage_generate_apply_success() {
    let Some(h) = MysqlHarness::try_new() else {
        return;
    };
    let mut buf = h.load_buffer();
    buf.set_cell(0, 1, "Alice Cooper");
    buf.toggle_delete_row(1);
    buf.add_row(Some(vec![
        "4".into(),
        "Diana".into(),
        "diana@test.com".into(),
    ]));

    let result = apply_staging_mysql(&h.pool(), &mut buf, &h.table, None).unwrap();
    assert_eq!(result.statements_applied, 3);
    assert!(!buf.is_dirty());
    assert_eq!(
        h.read_users(),
        vec![
            (1, "Alice Cooper".into(), Some("alice@test.com".into())),
            (3, "Charlie".into(), Some("charlie@test.com".into())),
            (4, "Diana".into(), Some("diana@test.com".into())),
        ]
    );
}

#[test]
fn e2e_mysql_apply_failure_keeps_staging() {
    let Some(h) = MysqlHarness::try_new() else {
        return;
    };
    let mut buf = h.load_buffer();
    buf.set_cell(0, 1, "Alice Updated");
    buf.add_row(Some(vec![
        "1".into(),
        "Dup".into(),
        "dup@test.com".into(),
    ]));

    let err = apply_staging_mysql(&h.pool(), &mut buf, &h.table, None).unwrap_err();
    assert!(matches!(err, ApplyError::Execute { .. }), "{err:?}");
    assert!(buf.is_dirty());
    assert_eq!(
        h.read_users(),
        vec![
            (1, "Alice".into(), Some("alice@test.com".into())),
            (2, "Bob".into(), Some("bob@test.com".into())),
            (3, "Charlie".into(), Some("charlie@test.com".into())),
        ]
    );
}
