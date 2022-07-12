import { defineStore } from "pinia";
import jwtDecode from "jwt-decode";
import { OAuthResult } from "../model/oauth";
import { postAuthToken, postOAuth } from "../model/api";

interface JwtPayload {
    iss: string;
    sub: number;
    exp: number;
    email: string;
    name: string;
    avatarUrl: string;
}

interface PersistentAuthState {
    email: string;
    name: string;
    avatarUrl: string;
    refreshToken: string;
    refreshTokenExp: number;
}

export const useAuthStore = defineStore("auth", {
    state: () => {
        return {
            email: "",
            name: "",
            avatarUrl: "",
            idToken: "",
            idTokenExp: 0,
            refreshToken: "",
            refreshTokenExp: 0,
            loading: false,
            error: "",
        };
    },
    getters: {
        loggedIn: (state) => !!state.refreshToken,
        idTokenValid: (state) => state.idTokenExp > Date.now(),
        refreshTokenValid: (state) => state.refreshTokenExp > Date.now(),
    },
    actions: {
        initialize() {
            const persistentStateStr = localStorage.getItem("authState");
            if (!persistentStateStr) return;
            const persistentState: PersistentAuthState = JSON.parse(persistentStateStr);
            this.$patch(persistentState);
            return this.refresh();
        },
        async connect(oauth: OAuthResult) {
            try {
                this.loading = true;
                const { idToken, refreshToken, refreshTokenExpJs } = await postOAuth(oauth);
                const idPayload = jwtDecode<JwtPayload>(idToken);
                const persistentState = {
                    email: idPayload.email,
                    name: idPayload.name,
                    avatarUrl: idPayload.avatarUrl,
                    refreshToken,
                    refreshTokenExp: refreshTokenExpJs,
                };
                this.$state = {
                    idToken,
                    idTokenExp: idPayload.exp * 1000,
                    loading: false,
                    error: "",
                    ...persistentState,
                };
                localStorage.setItem("authState", JSON.stringify(persistentState));
                // refresh 30 secs before expiration
                const refreshIn = idPayload.exp * 1000 - Date.now() - 30000;
                if (refreshIn < 0) {
                    await this.refresh();
                } else {
                    setTimeout(() => this.refresh(), refreshIn);
                }
            } catch (ex: any) {
                console.error(ex);
                this.$reset();
                this.error = ex.message;
            }
        },
        disconnect() {
            this.$reset();
            localStorage.removeItem("authState");
        },
        async refresh() {
            if (!this.refreshToken || !this.refreshTokenValid) {
                console.log("will reset");
                this.$reset();
                return;
            }
            try {
                this.loading = true;
                const { idToken, refreshToken, refreshTokenExpJs } = await postAuthToken({
                    refreshToken: this.refreshToken,
                });

                const idPayload = jwtDecode<JwtPayload>(idToken);
                const persistentState = {
                    email: idPayload.email,
                    name: idPayload.name,
                    avatarUrl: idPayload.avatarUrl,
                    refreshToken,
                    refreshTokenExp: refreshTokenExpJs,
                };
                this.$state = {
                    idToken,
                    idTokenExp: idPayload.exp * 1000,
                    loading: false,
                    error: "",
                    ...persistentState,
                };
                localStorage.setItem("authState", JSON.stringify(persistentState));
                // refresh 30 secs before expiration
                const refreshIn = idPayload.exp * 1000 - Date.now() - 30000;
                setTimeout(() => this.refresh(), refreshIn);
            } catch (ex: any) {
                console.error(ex);
                this.$reset();
                this.error = ex.message;
            }
        },
    },
});
