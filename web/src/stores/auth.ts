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
        loggedIn: (state) => !!state.idToken,
        idTokenValid: (state) => state.idTokenExp > Date.now(),
        refreshTokenValid: (state) => state.refreshTokenExp > Date.now(),
    },
    actions: {
        async connect(oauth: OAuthResult) {
            try {
                this.loading = true;
                const res = await postOAuth(oauth);
                const { idToken, refreshToken, refreshTokenExp } = res;
                const idPayload = jwtDecode<JwtPayload>(idToken);
                this.$state = {
                    email: idPayload.email,
                    name: idPayload.name,
                    avatarUrl: idPayload.avatarUrl,
                    idToken,
                    idTokenExp: idPayload.exp,
                    refreshToken,
                    refreshTokenExp,
                    loading: false,
                    error: "",
                };
                // refresh 30 secs before expiration
                const refreshIn = idPayload.exp - Date.now() - 30000;
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
        },
        async refresh() {
            if (!this.refreshToken || !this.refreshTokenValid) {
                this.$reset();
                return;
            }
            try {
                this.loading = true;
                const { idToken, refreshToken, refreshTokenExp } = await postAuthToken({
                    refreshToken: this.refreshToken,
                });

                const idPayload = jwtDecode<JwtPayload>(idToken);
                this.$state = {
                    email: idPayload.email,
                    name: idPayload.name,
                    avatarUrl: idPayload.avatarUrl,
                    idToken,
                    idTokenExp: idPayload.exp,
                    refreshToken,
                    refreshTokenExp,
                    loading: false,
                    error: "",
                };
                // refresh 30 secs before expiration
                const refreshIn = idPayload.exp - Date.now() - 30000;
                setTimeout(() => this.refresh(), refreshIn);
            } catch (ex: any) {
                console.error(ex);
                this.$reset();
                this.error = ex.message;
            }
        },
    },
});
