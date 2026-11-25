<script setup lang="ts">
import { computed, ref } from "vue";
import { open as pickFile } from "@tauri-apps/plugin-dialog";
import {
  sshFormIsValid,
  sshTunnelTest,
  type SshTunnelForm,
} from "../api/sshTunnel";
import QueryaButton from "./QueryaButton.vue";

const form = defineModel<SshTunnelForm>({ required: true });

const props = defineProps<{
  /** Target DB host as typed in the connection form. */
  targetHost: string;
  targetPort: number | string;
}>();

const testing = ref(false);
const testMessage = ref<string | null>(null);
const testOk = ref(false);

const canTest = computed(() => {
  if (!form.value.enabled) return false;
  const remotePort = Number(props.targetPort);
  return (
    sshFormIsValid(form.value) &&
    props.targetHost.trim().length > 0 &&
    Number.isFinite(remotePort) &&
    remotePort > 0
  );
});

async function pickKey() {
  try {
    const selected = await pickFile({
      multiple: false,
      directory: false,
      title: "SSH private key",
    });
    if (!selected || Array.isArray(selected)) return;
    form.value.privateKeyPath = selected;
  } catch {
    /* cancelled */
  }
}

async function onTest() {
  testMessage.value = null;
  testOk.value = false;
  if (!canTest.value) {
    testMessage.value = "Fill bastion and target host/port first.";
    return;
  }
  testing.value = true;
  try {
    const info = await sshTunnelTest(
      form.value,
      props.targetHost.trim(),
      Number(props.targetPort),
    );
    testOk.value = true;
    testMessage.value = `Tunnel OK · local ${info.localHost}:${info.localPort}`;
  } catch (err) {
    testOk.value = false;
    testMessage.value =
      err && typeof err === "object" && "message" in err
        ? String((err as { message: unknown }).message)
        : String(err);
  } finally {
    testing.value = false;
  }
}
</script>

<template>
  <section class="ssh" data-testid="ssh-tunnel-section">
    <label class="toggle">
      <input v-model="form.enabled" type="checkbox" />
      <span>Connect via SSH bastion</span>
    </label>

    <template v-if="form.enabled">
      <div class="row2">
        <label class="field grow">
          <span>Bastion host</span>
          <input
            v-model="form.host"
            type="text"
            spellcheck="false"
            placeholder="bastion.example.com"
            autocomplete="off"
          />
        </label>
        <label class="field port">
          <span>Port</span>
          <input v-model.number="form.port" type="number" min="1" max="65535" />
        </label>
      </div>

      <label class="field">
        <span>SSH user</span>
        <input
          v-model="form.username"
          type="text"
          spellcheck="false"
          autocomplete="username"
        />
      </label>

      <div class="auth-tabs" role="group" aria-label="SSH auth method">
        <button
          type="button"
          class="tab"
          :class="{ active: form.authType === 'password' }"
          @click="form.authType = 'password'"
        >
          Password
        </button>
        <button
          type="button"
          class="tab"
          :class="{ active: form.authType === 'privateKey' }"
          @click="form.authType = 'privateKey'"
        >
          Private key
        </button>
      </div>

      <label v-if="form.authType === 'password'" class="field">
        <span>SSH password</span>
        <input
          v-model="form.password"
          type="password"
          autocomplete="current-password"
        />
      </label>

      <template v-else>
        <label class="field">
          <span>Private key path</span>
          <div class="key-row">
            <input
              v-model="form.privateKeyPath"
              type="text"
              spellcheck="false"
              placeholder="~/.ssh/id_ed25519"
            />
            <QueryaButton variant="secondary" size="sm" @click="pickKey">
              Browse…
            </QueryaButton>
          </div>
        </label>
        <label class="field">
          <span>Key passphrase (optional)</span>
          <input
            v-model="form.passphrase"
            type="password"
            autocomplete="off"
          />
        </label>
      </template>

      <div class="test-row">
        <QueryaButton
          variant="secondary"
          size="sm"
          :disabled="!canTest || testing"
          :loading="testing"
          @click="onTest"
        >
          Test tunnel
        </QueryaButton>
        <p
          v-if="testMessage"
          class="test-msg"
          :class="{ ok: testOk, err: !testOk }"
          data-testid="ssh-test-message"
        >
          {{ testMessage }}
        </p>
      </div>
    </template>
  </section>
</template>

<style scoped>
.ssh {
  display: flex;
  flex-direction: column;
  gap: 10px;
  margin-top: 4px;
  padding-top: 10px;
  border-top: 1px solid color-mix(in srgb, var(--q-border) 70%, transparent);
}

.toggle {
  display: flex;
  align-items: center;
  gap: 8px;
  font-size: 12px;
  color: var(--q-foreground);
  cursor: pointer;
}

.toggle input {
  margin: 0;
}

.field {
  display: flex;
  flex-direction: column;
  gap: 4px;
  font-size: 11px;
  color: var(--q-muted-foreground);
}

.field input {
  height: 32px;
  border-radius: 6px;
  border: 1px solid color-mix(in srgb, var(--q-border) 70%, transparent);
  background: var(--q-surface);
  color: var(--q-foreground);
  padding: 0 8px;
  font: inherit;
  font-size: 13px;
}

.row2 {
  display: flex;
  gap: 10px;
}

.grow {
  flex: 1;
  min-width: 0;
}

.port {
  width: 88px;
  flex: none;
}

.auth-tabs {
  display: flex;
  gap: 4px;
}

.tab {
  flex: 1;
  height: 28px;
  border-radius: 6px;
  border: 1px solid color-mix(in srgb, var(--q-border) 70%, transparent);
  background: transparent;
  color: var(--q-muted-foreground);
  font: inherit;
  font-size: 12px;
  cursor: pointer;
}

.tab.active {
  background: color-mix(in srgb, var(--q-accent, #2bbbad) 18%, transparent);
  color: var(--q-foreground);
  border-color: color-mix(in srgb, var(--q-accent, #2bbbad) 45%, transparent);
}

.key-row {
  display: flex;
  gap: 8px;
  align-items: center;
}

.key-row input {
  flex: 1;
  min-width: 0;
}

.test-row {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: 10px;
}

.test-msg {
  margin: 0;
  font-size: 11px;
  flex: 1;
  min-width: 140px;
}

.test-msg.ok {
  color: var(--q-success, #3d9a6a);
}

.test-msg.err {
  color: var(--q-destructive, #e35d6a);
}
</style>
