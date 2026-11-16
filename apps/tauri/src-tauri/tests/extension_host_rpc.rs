//! Echo extension round-trip against the NDJSON JSON-RPC host (#1903).

use querya_desktop_tauri_lib::ExtensionHost;
use serde_json::json;
use std::path::PathBuf;

fn echo_bin() -> PathBuf {
    PathBuf::from(env!("CARGO_BIN_EXE_querya-ext-echo"))
}

#[tokio::test]
async fn echo_extension_handshake_ping_roundtrip_shutdown() {
    let host = ExtensionHost::new();
    let info = host
        .start(
            "echo-1".into(),
            echo_bin(),
            vec![],
            json!({
                "queryaVersion": "0.1.0",
                "pluginId": "querya.echo",
            }),
        )
        .await
        .expect("start");

    assert_eq!(info.extension_id, "querya.echo");
    assert_eq!(info.protocol_version, json!(1));

    let pong = host.ping("echo-1").await.expect("ping");
    assert_eq!(pong, json!("pong"));

    let echoed = host
        .call(
            "echo-1",
            "echo.echo",
            Some(json!({ "message": "hello-from-host" })),
        )
        .await
        .expect("echo");
    assert_eq!(echoed, json!({ "message": "hello-from-host" }));

    host.stop("echo-1").await.expect("stop");
    assert!(host.list().await.is_empty());
}
