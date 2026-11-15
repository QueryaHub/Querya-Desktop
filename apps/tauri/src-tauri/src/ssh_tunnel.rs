//! Local SSH port forwarding via `russh` (`ssh -L` parity for SQL drivers).

use russh::client::{self, Config};
use russh::keys::{decode_secret_key, load_secret_key, PrivateKeyWithHashAlg, PublicKeyOrCertificate};
use russh::{ChannelMsg, Disconnect};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::path::Path;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex};
use std::time::Duration;
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::{TcpListener, TcpStream};
use tokio::task::JoinHandle;
use uuid::Uuid;

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SshTunnelOpenRequest {
    pub bastion_host: String,
    pub bastion_port: u16,
    pub username: String,
    #[serde(default)]
    pub password: Option<String>,
    /// PEM / OpenSSH private key contents (session-only).
    #[serde(default)]
    pub private_key_pem: Option<String>,
    /// Path to a private key file on disk.
    #[serde(default)]
    pub private_key_path: Option<String>,
    #[serde(default)]
    pub private_key_passphrase: Option<String>,
    /// Target host as seen from the bastion (often a private IP / `localhost`).
    pub remote_host: String,
    pub remote_port: u16,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SshTunnelInfo {
    pub id: String,
    pub local_host: String,
    pub local_port: u16,
    pub remote_host: String,
    pub remote_port: u16,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct SshTunnelError {
    pub message: String,
}

impl SshTunnelError {
    fn new(message: impl Into<String>) -> Self {
        Self {
            message: message.into(),
        }
    }
}

impl std::fmt::Display for SshTunnelError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(&self.message)
    }
}

impl std::error::Error for SshTunnelError {}

struct ClientHandler;

impl client::Handler for ClientHandler {
    type Error = russh::Error;

    async fn check_server_key(
        &mut self,
        _server_public_key: &PublicKeyOrCertificate,
    ) -> Result<bool, Self::Error> {
        // TOFU for the first Tauri slice — fingerprint pinning lands with secrets UX.
        Ok(true)
    }
}

struct LiveTunnel {
    info: SshTunnelInfo,
    stop: Arc<AtomicBool>,
    accept_task: JoinHandle<()>,
    session: Arc<client::Handle<ClientHandler>>,
}

/// In-memory tunnel registry managed by Tauri.
#[derive(Default)]
pub struct SshTunnelRegistry {
    inner: Mutex<HashMap<String, LiveTunnel>>,
}

impl SshTunnelRegistry {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn open(&self, request: SshTunnelOpenRequest) -> Result<SshTunnelInfo, SshTunnelError> {
        crate::connection::runtime::block_on(self.open_async(request))
    }

    async fn open_async(
        &self,
        request: SshTunnelOpenRequest,
    ) -> Result<SshTunnelInfo, SshTunnelError> {
        validate(&request)?;
        let (info, live) = open_tunnel(request).await?;
        let mut guard = self
            .inner
            .lock()
            .map_err(|_| SshTunnelError::new("ssh tunnel registry lock poisoned"))?;
        guard.insert(info.id.clone(), live);
        Ok(info)
    }

    pub fn close(&self, id: &str) -> Result<bool, SshTunnelError> {
        let mut guard = self
            .inner
            .lock()
            .map_err(|_| SshTunnelError::new("ssh tunnel registry lock poisoned"))?;
        let Some(live) = guard.remove(id) else {
            return Ok(false);
        };
        live.stop.store(true, Ordering::SeqCst);
        live.accept_task.abort();
        let session = live.session;
        // Disconnect off the caller's thread so `close` is safe from inside
        // `runtime::block_on` (nested block_on panics).
        std::thread::spawn(move || {
            crate::connection::runtime::block_on(async move {
                let _ = session
                    .disconnect(Disconnect::ByApplication, "tunnel closed", "en")
                    .await;
            });
        });
        Ok(true)
    }

    pub fn list(&self) -> Result<Vec<SshTunnelInfo>, SshTunnelError> {
        let guard = self
            .inner
            .lock()
            .map_err(|_| SshTunnelError::new("ssh tunnel registry lock poisoned"))?;
        Ok(guard.values().map(|t| t.info.clone()).collect())
    }
}

fn validate(req: &SshTunnelOpenRequest) -> Result<(), SshTunnelError> {
    if req.bastion_host.trim().is_empty() {
        return Err(SshTunnelError::new("bastion host is empty"));
    }
    if req.bastion_port == 0 {
        return Err(SshTunnelError::new("bastion port is 0"));
    }
    if req.username.trim().is_empty() {
        return Err(SshTunnelError::new("SSH username is empty"));
    }
    if req.remote_host.trim().is_empty() {
        return Err(SshTunnelError::new("remote host is empty"));
    }
    if req.remote_port == 0 {
        return Err(SshTunnelError::new("remote port is 0"));
    }
    let has_password = req
        .password
        .as_deref()
        .map(str::trim)
        .is_some_and(|s| !s.is_empty());
    let has_pem = req
        .private_key_pem
        .as_deref()
        .map(str::trim)
        .is_some_and(|s| !s.is_empty());
    let has_path = req
        .private_key_path
        .as_deref()
        .map(str::trim)
        .is_some_and(|s| !s.is_empty());
    if !has_password && !has_pem && !has_path {
        return Err(SshTunnelError::new(
            "SSH auth requires a password or private key",
        ));
    }
    Ok(())
}

async fn open_tunnel(
    request: SshTunnelOpenRequest,
) -> Result<(SshTunnelInfo, LiveTunnel), SshTunnelError> {
    let config = Arc::new(Config {
        nodelay: true,
        inactivity_timeout: Some(Duration::from_secs(300)),
        ..Default::default()
    });

    let addrs = (
        request.bastion_host.trim().to_owned(),
        request.bastion_port,
    );
    let mut session = client::connect(config, addrs, ClientHandler)
        .await
        .map_err(|e| SshTunnelError::new(format!("SSH connect failed: {e}")))?;

    authenticate(&mut session, &request).await?;

    let listener = TcpListener::bind(("127.0.0.1", 0))
        .await
        .map_err(|e| SshTunnelError::new(format!("bind local forward failed: {e}")))?;
    let local_addr = listener
        .local_addr()
        .map_err(|e| SshTunnelError::new(format!("local addr: {e}")))?;

    let id = Uuid::new_v4().to_string();
    let info = SshTunnelInfo {
        id: id.clone(),
        local_host: "127.0.0.1".into(),
        local_port: local_addr.port(),
        remote_host: request.remote_host.trim().to_owned(),
        remote_port: request.remote_port,
    };

    let stop = Arc::new(AtomicBool::new(false));
    let stop_flag = Arc::clone(&stop);
    let session = Arc::new(session);
    let handle = Arc::clone(&session);
    let remote_host = info.remote_host.clone();
    let remote_port = info.remote_port;

    let accept_task = tokio::spawn(async move {
        loop {
            if stop_flag.load(Ordering::SeqCst) {
                break;
            }
            let accept = tokio::time::timeout(Duration::from_millis(400), listener.accept()).await;
            match accept {
                Ok(Ok((socket, origin))) => {
                    let handle = Arc::clone(&handle);
                    let remote_host = remote_host.clone();
                    tokio::spawn(async move {
                        if let Err(e) =
                            relay_one(handle, socket, origin, &remote_host, remote_port).await
                        {
                            eprintln!("ssh tunnel relay error: {e}");
                        }
                    });
                }
                Ok(Err(_)) => break,
                Err(_) => continue, // accept timeout — recheck stop flag
            }
        }
    });

    let live = LiveTunnel {
        info: info.clone(),
        stop,
        accept_task,
        session,
    };
    Ok((info, live))
}

async fn authenticate(
    session: &mut client::Handle<ClientHandler>,
    request: &SshTunnelOpenRequest,
) -> Result<(), SshTunnelError> {
    let user = request.username.trim();

    if let Some(path) = request
        .private_key_path
        .as_deref()
        .map(str::trim)
        .filter(|s| !s.is_empty())
    {
        let key = load_secret_key(Path::new(path), request.private_key_passphrase.as_deref())
            .map_err(|e| SshTunnelError::new(format!("load private key: {e}")))?;
        return auth_publickey(session, user, key).await;
    }

    if let Some(pem) = request
        .private_key_pem
        .as_deref()
        .map(str::trim)
        .filter(|s| !s.is_empty())
    {
        let key = decode_secret_key(pem, request.private_key_passphrase.as_deref())
            .map_err(|e| SshTunnelError::new(format!("parse private key: {e}")))?;
        return auth_publickey(session, user, key).await;
    }

    let password = request
        .password
        .as_deref()
        .map(str::trim)
        .filter(|s| !s.is_empty())
        .ok_or_else(|| SshTunnelError::new("SSH password is empty"))?;

    let auth = session
        .authenticate_password(user, password)
        .await
        .map_err(|e| SshTunnelError::new(format!("SSH password auth failed: {e}")))?;
    if !auth.success() {
        return Err(SshTunnelError::new("SSH password authentication rejected"));
    }
    Ok(())
}

async fn auth_publickey(
    session: &mut client::Handle<ClientHandler>,
    user: &str,
    key: russh::keys::PrivateKey,
) -> Result<(), SshTunnelError> {
    let hash = session
        .best_supported_rsa_hash()
        .await
        .map_err(|e| SshTunnelError::new(format!("SSH key hash negotiate: {e}")))?
        .flatten();
    let auth = session
        .authenticate_publickey(
            user,
            PrivateKeyWithHashAlg::new(Arc::new(key), hash),
        )
        .await
        .map_err(|e| SshTunnelError::new(format!("SSH publickey auth failed: {e}")))?;
    if !auth.success() {
        return Err(SshTunnelError::new(
            "SSH public key authentication rejected",
        ));
    }
    Ok(())
}

async fn relay_one(
    session: Arc<client::Handle<ClientHandler>>,
    mut stream: TcpStream,
    origin: std::net::SocketAddr,
    remote_host: &str,
    remote_port: u16,
) -> Result<(), SshTunnelError> {
    let mut channel = session
        .channel_open_direct_tcpip(
            remote_host,
            u32::from(remote_port),
            origin.ip().to_string(),
            u32::from(origin.port()),
        )
        .await
        .map_err(|e| SshTunnelError::new(format!("direct-tcpip open failed: {e}")))?;

    let mut stream_closed = false;
    let mut buf = vec![0_u8; 65536];
    loop {
        tokio::select! {
            r = stream.read(&mut buf), if !stream_closed => {
                match r {
                    Ok(0) => {
                        stream_closed = true;
                        let _ = channel.eof().await;
                    }
                    Ok(n) => {
                        channel
                            .data(&buf[..n])
                            .await
                            .map_err(|e| SshTunnelError::new(format!("channel write: {e}")))?;
                    }
                    Err(e) => return Err(SshTunnelError::new(format!("local read: {e}"))),
                }
            }
            Some(msg) = channel.wait() => {
                match msg {
                    ChannelMsg::Data { ref data } => {
                        stream
                            .write_all(data)
                            .await
                            .map_err(|e| SshTunnelError::new(format!("local write: {e}")))?;
                    }
                    ChannelMsg::Eof => {
                        if !stream_closed {
                            let _ = channel.eof().await;
                        }
                        break;
                    }
                    ChannelMsg::WindowAdjusted { .. } => {}
                    ChannelMsg::Close => break,
                    _ => {}
                }
            }
            else => break,
        }
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use russh::server::{Auth, Handler as ServerHandler, Msg, Server as _, Session};
    use russh::{server, Channel, ChannelId};
    use tokio::io::AsyncWriteExt;

    #[test]
    fn validate_rejects_empty_host() {
        let err = validate(&SshTunnelOpenRequest {
            bastion_host: " ".into(),
            bastion_port: 22,
            username: "u".into(),
            password: Some("p".into()),
            private_key_pem: None,
            private_key_path: None,
            private_key_passphrase: None,
            remote_host: "db".into(),
            remote_port: 5432,
        })
        .unwrap_err();
        assert!(err.message.contains("bastion host"));
    }

    #[test]
    fn validate_requires_credentials() {
        let err = validate(&SshTunnelOpenRequest {
            bastion_host: "bastion".into(),
            bastion_port: 22,
            username: "u".into(),
            password: None,
            private_key_pem: None,
            private_key_path: None,
            private_key_passphrase: None,
            remote_host: "db".into(),
            remote_port: 5432,
        })
        .unwrap_err();
        assert!(err.message.contains("password or private key"));
    }

    #[derive(Clone)]
    struct ForwardServer;

    impl server::Server for ForwardServer {
        type Handler = Self;
        fn new_client(&mut self, _: Option<std::net::SocketAddr>) -> Self {
            self.clone()
        }
    }

    impl ServerHandler for ForwardServer {
        type Error = russh::Error;

        async fn auth_password(
            &mut self,
            user: &str,
            password: &str,
        ) -> Result<Auth, Self::Error> {
            if user == "querya" && password == "tunnel" {
                Ok(Auth::Accept)
            } else {
                Ok(Auth::reject())
            }
        }

        async fn channel_open_direct_tcpip(
            &mut self,
            channel: Channel<Msg>,
            host_to_connect: &str,
            port_to_connect: u32,
            _originator_address: &str,
            _originator_port: u32,
            reply: server::ChannelOpenHandle,
            _session: &mut Session,
        ) -> Result<(), Self::Error> {
            let target = format!("{host_to_connect}:{port_to_connect}");
            let mut remote = match TcpStream::connect(&target).await {
                Ok(s) => s,
                Err(e) => {
                    reply
                        .reject(russh::ChannelOpenFailure::ConnectFailed)
                        .await;
                    return Err(russh::Error::IO(std::io::Error::other(format!(
                        "forward connect {target}: {e}"
                    ))));
                }
            };
            reply.accept().await;
            let mut chan = channel.into_stream();
            tokio::spawn(async move {
                let _ = tokio::io::copy_bidirectional(&mut remote, &mut chan).await;
            });
            Ok(())
        }

        async fn channel_open_session(
            &mut self,
            _channel: Channel<Msg>,
            reply: server::ChannelOpenHandle,
            _session: &mut Session,
        ) -> Result<(), Self::Error> {
            reply.accept().await;
            Ok(())
        }

        async fn data(
            &mut self,
            _channel: ChannelId,
            _data: &[u8],
            _session: &mut Session,
        ) -> Result<(), Self::Error> {
            Ok(())
        }
    }

    async fn spawn_echo_backend() -> (u16, JoinHandle<()>) {
        let listener = TcpListener::bind(("127.0.0.1", 0)).await.unwrap();
        let port = listener.local_addr().unwrap().port();
        let task = tokio::spawn(async move {
            loop {
                let Ok((mut sock, _)) = listener.accept().await else {
                    break;
                };
                tokio::spawn(async move {
                    let mut buf = [0u8; 1024];
                    if let Ok(n) = sock.read(&mut buf).await {
                        if n > 0 {
                            let _ = sock.write_all(&buf[..n]).await;
                        }
                    }
                });
            }
        });
        (port, task)
    }

    async fn spawn_ssh_bastion() -> (u16, JoinHandle<()>) {
        let key =
            russh::keys::PrivateKey::random(&mut rand::rng(), russh::keys::Algorithm::Ed25519)
                .unwrap();
        let config = Arc::new(server::Config {
            keys: vec![key],
            auth_rejection_time: Duration::from_millis(10),
            auth_rejection_time_initial: Some(Duration::from_millis(0)),
            ..Default::default()
        });
        let socket = TcpListener::bind(("127.0.0.1", 0)).await.unwrap();
        let port = socket.local_addr().unwrap().port();
        let task = tokio::spawn(async move {
            let mut server = ForwardServer;
            let _ = server.run_on_socket(config, &socket).await;
        });
        // Give the accept loop a moment to start.
        tokio::time::sleep(Duration::from_millis(20)).await;
        (port, task)
    }

    #[test]
    fn live_password_forward_echo() {
        if std::env::var_os("QUERYA_SKIP_SSH").is_some() {
            eprintln!("skip ssh live test (QUERYA_SKIP_SSH)");
            return;
        }

        crate::connection::runtime::block_on(async {
            let (backend_port, backend_task) = spawn_echo_backend().await;
            let (bastion_port, bastion_task) = spawn_ssh_bastion().await;

            // Give the bastion a beat to accept.
            tokio::time::sleep(Duration::from_millis(50)).await;

            let registry = SshTunnelRegistry::new();
            let info = registry
                .open_async(SshTunnelOpenRequest {
                    bastion_host: "127.0.0.1".into(),
                    bastion_port,
                    username: "querya".into(),
                    password: Some("tunnel".into()),
                    private_key_pem: None,
                    private_key_path: None,
                    private_key_passphrase: None,
                    remote_host: "127.0.0.1".into(),
                    remote_port: backend_port,
                })
                .await
                .expect("open tunnel");

            let mut client = TcpStream::connect(("127.0.0.1", info.local_port))
                .await
                .expect("connect local forward");
            client.write_all(b"ping-via-ssh").await.unwrap();
            let mut buf = [0u8; 32];
            let n = tokio::time::timeout(Duration::from_secs(3), client.read(&mut buf))
                .await
                .expect("read timeout")
                .expect("read");
            assert_eq!(&buf[..n], b"ping-via-ssh");

            assert!(registry.close(&info.id).unwrap());
            backend_task.abort();
            bastion_task.abort();
        });
    }

    #[test]
    fn open_rejects_bad_password() {
        if std::env::var_os("QUERYA_SKIP_SSH").is_some() {
            return;
        }
        crate::connection::runtime::block_on(async {
            let (bastion_port, bastion_task) = spawn_ssh_bastion().await;
            tokio::time::sleep(Duration::from_millis(50)).await;
            let registry = SshTunnelRegistry::new();
            let err = registry
                .open_async(SshTunnelOpenRequest {
                    bastion_host: "127.0.0.1".into(),
                    bastion_port,
                    username: "querya".into(),
                    password: Some("wrong".into()),
                    private_key_pem: None,
                    private_key_path: None,
                    private_key_passphrase: None,
                    remote_host: "127.0.0.1".into(),
                    remote_port: 9,
                })
                .await
                .unwrap_err();
            assert!(
                err.message.contains("rejected") || err.message.contains("auth"),
                "{err}"
            );
            bastion_task.abort();
        });
    }
}
