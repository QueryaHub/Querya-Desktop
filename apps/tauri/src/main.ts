import { createApp } from "vue";
import { createPinia } from "pinia";
import App from "./App.vue";
import "./styles/base.css";
import { initTheme } from "./theme/queryaTheme";
import {
  applyPlatformDataset,
  detectPlatformFromUa,
  resolvePlatform,
} from "./ui/platform";

// Sync UA hint immediately; Rust `host_platform` corrects it before paint settles.
applyPlatformDataset(detectPlatformFromUa());
void resolvePlatform().then(applyPlatformDataset);
initTheme();

const app = createApp(App);
app.use(createPinia());
app.mount("#app");
