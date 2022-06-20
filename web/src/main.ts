import { createApp } from "vue";
import '@iconify/iconify'

import App from "./App.vue";
import router from "./router";
import "./index.css";
import { provideOAuth } from "./model/oauth";

const app = createApp(App);
app.use(router);
provideOAuth(app);
app.mount("#app");
