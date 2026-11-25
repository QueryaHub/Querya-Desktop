import { describe, expect, it } from "vitest";
import {
  emptySshTunnelForm,
  sshFormIsValid,
  toOpenRequest,
} from "./sshTunnel";

describe("sshTunnel helpers", () => {
  it("treats disabled form as valid", () => {
    expect(sshFormIsValid(emptySshTunnelForm())).toBe(true);
  });

  it("requires password auth fields when enabled", () => {
    const form = emptySshTunnelForm();
    form.enabled = true;
    form.host = "bastion";
    form.username = "ubuntu";
    form.authType = "password";
    expect(sshFormIsValid(form)).toBe(false);
    form.password = "secret";
    expect(sshFormIsValid(form)).toBe(true);
  });

  it("maps form to open request", () => {
    const form = emptySshTunnelForm();
    form.enabled = true;
    form.host = "bastion";
    form.port = 2222;
    form.username = "ubuntu";
    form.authType = "privateKey";
    form.privateKeyPath = "/tmp/id_ed25519";
    form.passphrase = "x";
    expect(toOpenRequest(form, "10.0.0.5", 5432)).toEqual({
      bastionHost: "bastion",
      bastionPort: 2222,
      username: "ubuntu",
      password: null,
      privateKeyPath: "/tmp/id_ed25519",
      privateKeyPassphrase: "x",
      remoteHost: "10.0.0.5",
      remotePort: 5432,
    });
  });
});
