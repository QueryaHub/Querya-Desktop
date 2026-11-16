//! Live hello-panel extension: handshake → panel.get → shutdown (#1905).

use querya_desktop_tauri_lib::ExtensionHost;
use serde_json::json;
use std::path::PathBuf;

fn hello_bin() -> PathBuf {
    PathBuf::from(env!("CARGO_BIN_EXE_querya-ext-hello-panel"))
}

#[tokio::test]
async fn hello_panel_get_descriptor_roundtrip() {
    let host = ExtensionHost::new();
    let info = host
        .start(
            "hello-1".into(),
            hello_bin(),
            vec![],
            json!({
                "queryaVersion": "0.1.0",
                "pluginId": "querya.hello-panel",
            }),
        )
        .await
        .expect("start");

    assert_eq!(info.extension_id, "querya.hello-panel");

    let panel = host
        .call("hello-1", "panel.get", None)
        .await
        .expect("panel.get");

    assert_eq!(panel["type"], json!("panel"));
    assert_eq!(panel["id"], json!("querya.hello-panel"));
    assert_eq!(panel["title"], json!("Hello panel"));
    let children = panel["children"].as_array().expect("children");
    assert!(children.iter().any(|n| n["type"] == "text"));
    assert!(children.iter().any(|n| n["type"] == "stack"));

    host.stop("hello-1").await.expect("stop");
}
