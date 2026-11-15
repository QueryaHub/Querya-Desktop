import { createApp } from "vue";
import { createPinia } from "pinia";
import App from "./App.vue";
import "./styles/base.css";
import { initTheme } from "./theme/queryaTheme";

initTheme();

const app = createApp(App);
app.use(createPinia());
app.mount("#app");
