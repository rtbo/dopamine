import { createApp } from "vue";
import '@iconify/iconify'

import App from "./App.vue";
import router from "./router";
import "./index.css";

const app = createApp(App);
app.use(router);
app.mount("#app");
