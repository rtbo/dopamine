import Home from "./pages/Home.vue";
import Login from "./pages/Login.vue";
import CliTokens from "./pages/CliTokens.vue";
import {
    createRouter,
    createWebHistory,
    RouteLocationNormalized,
    RouteLocationRaw,
    RouteRecordRaw,
    RouterOptions,
} from "vue-router";
import { useAuthStore } from "./stores/auth";

function checkAuth(to: RouteLocationNormalized): RouteLocationRaw | undefined {
    const store = useAuthStore();
    console.log(store.idToken);
    if (!store.loggedIn) return `/login?redirectTo=${to.path}`;
}

const routes: RouteRecordRaw[] = [
    { path: "/", component: Home },
    { path: "/login", component: Login },
    {
        path: "/cli-tokens",
        component: CliTokens,
        beforeEnter: [checkAuth],
    },
];

const options: RouterOptions = {
    history: createWebHistory(),
    routes,
};

export default createRouter(options);
