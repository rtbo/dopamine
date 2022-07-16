import {
    createRouter,
    createWebHistory,
    RouteRecordRaw,
    RouterOptions,
} from "vue-router";
import "vue-router";
import Home from "./pages/Home.vue";
import Login from "./pages/Login.vue";
import CliTokens from "./pages/CliTokens.vue";

declare module "vue-router" {
    interface RouteMeta {
        // see App.vue for the handling of authorized routes
        requiresAuth?: boolean;
        title?: string;
    }
}

const routes: RouteRecordRaw[] = [
    { path: "/", component: Home },
    { path: "/login", component: Login },
    {
        path: "/cli-tokens",
        component: CliTokens,
        meta: { requiresAuth: true },
    },
];

const options: RouterOptions = {
    history: createWebHistory(),
    routes,
};

export default createRouter(options);
