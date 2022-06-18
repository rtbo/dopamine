import Home from "./pages/Home.vue";
import Login from "./pages/Login.vue";
import { createRouter, createWebHistory, RouteRecordRaw, RouterOptions } from "vue-router";

const routes: RouteRecordRaw[] = [
    { path: "/", component: Home },
    { path: "/login", component: Login },
];

const options: RouterOptions = {
    history: createWebHistory(),
    routes,
}

export default createRouter(options)
