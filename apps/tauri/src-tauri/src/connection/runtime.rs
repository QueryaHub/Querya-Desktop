//! Shared Tokio runtime for sync driver entry points (sqlx Postgres/MySQL).

use std::sync::OnceLock;
use tokio::runtime::Runtime;

static RUNTIME: OnceLock<Runtime> = OnceLock::new();

pub fn block_on<F: std::future::Future>(fut: F) -> F::Output {
    RUNTIME
        .get_or_init(|| {
            tokio::runtime::Builder::new_multi_thread()
                .enable_all()
                .thread_name("querya-sqlx")
                .worker_threads(2)
                .build()
                .expect("querya tokio runtime")
        })
        .block_on(fut)
}
