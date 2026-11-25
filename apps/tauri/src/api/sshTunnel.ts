import { invoke } from "@tauri-apps/api/core";

export type SshAuthType = "password" | "privateKey";

/** Non-secret + session secrets for the New Connection SSH section. */
export type SshTunnelForm = {
  enabled: boolean;
  host: string;
  port: number;
  username: string;
  authType: SshAuthType;
  password: string;
  privateKeyPath: string;
  passphrase: string;
};

export type SshTunnelOpenRequest = {
  bastionHost: string;
  bastionPort: number;
  username: string;
  password?: string | null;
  privateKeyPem?: string | null;
  privateKeyPath?: string | null;
  privateKeyPassphrase?: string | null;
  remoteHost: string;
  remotePort: number;
};

export type SshTunnelInfo = {
  id: string;
  localHost: string;
  localPort: number;
  remoteHost: string;
  remotePort: number;
};

export function emptySshTunnelForm(): SshTunnelForm {
  return {
    enabled: false,
    host: "",
    port: 22,
    username: "",
    authType: "password",
    password: "",
    privateKeyPath: "",
    passphrase: "",
  };
}

export function sshFormIsValid(form: SshTunnelForm): boolean {
  if (!form.enabled) return true;
  const port = Number(form.port);
  return (
    form.host.trim().length > 0 &&
    form.username.trim().length > 0 &&
    Number.isFinite(port) &&
    port > 0 &&
    port <= 65535 &&
    (form.authType === "password"
      ? form.password.length > 0
      : form.privateKeyPath.trim().length > 0)
  );
}

export function toOpenRequest(
  form: SshTunnelForm,
  remoteHost: string,
  remotePort: number,
): SshTunnelOpenRequest {
  return {
    bastionHost: form.host.trim(),
    bastionPort: Number(form.port) || 22,
    username: form.username.trim(),
    password:
      form.authType === "password" ? form.password || null : null,
    privateKeyPath:
      form.authType === "privateKey"
        ? form.privateKeyPath.trim() || null
        : null,
    privateKeyPassphrase:
      form.authType === "privateKey"
        ? form.passphrase || null
        : null,
    remoteHost,
    remotePort,
  };
}

export async function sshTunnelOpen(
  request: SshTunnelOpenRequest,
): Promise<SshTunnelInfo> {
  return invoke<SshTunnelInfo>("ssh_tunnel_open", { request });
}

export async function sshTunnelClose(id: string): Promise<boolean> {
  return invoke<boolean>("ssh_tunnel_close", { id });
}

export async function sshTunnelList(): Promise<SshTunnelInfo[]> {
  return invoke<SshTunnelInfo[]>("ssh_tunnel_list");
}

/** Open then close — verifies bastion auth + forward path. */
export async function sshTunnelTest(
  form: SshTunnelForm,
  remoteHost: string,
  remotePort: number,
): Promise<SshTunnelInfo> {
  const info = await sshTunnelOpen(toOpenRequest(form, remoteHost, remotePort));
  await sshTunnelClose(info.id).catch(() => undefined);
  return info;
}
