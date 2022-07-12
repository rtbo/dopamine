import { useFetch, UseFetchReturn, createFetch, MaybeRef } from "@vueuse/core";
import axios from "axios";
import { ref, Ref, unref, withCtx } from "vue";
import { Provider, OAuthResult } from "./oauth";

const hostUrl = import.meta.env.VITE_API_HOST || "http://localhost:3500";
const prefix = import.meta.env.VITE_API_PREFIX || "/api";

export const host = hostUrl.replace("http://", "").replace("https://", "")

export function resource(path?: string): string {
    return `${hostUrl}${prefix}${path || ""}`;
}

export function authHeader(idToken: string) {
    return {
        Authorization: `Bearer ${idToken}`,
    };
}

export const api = axios.create({
    baseURL: resource("/"),
});

const useApiReq = createFetch({
    baseUrl: resource(),
    fetchOptions: {
        mode: "cors",
    },
});

function useAuthApiReq<T>(url: MaybeRef<string>, idToken: MaybeRef<string>) {
    return useApiReq<T>(url, {
        beforeFetch({ options }) {
            (options.headers as Record<string, string>).Authorization = `Bearer ${unref(idToken)}`;
            return { options };
        },
    });
}

export interface OAuthRequest {
    provider: Provider;
}

export function postOAuth(data: OAuthResult): Promise<AuthResponse> {
    return api.post("auth", data).then((resp) => resp.data);
}

export interface AuthResponse {
    idToken: string;
    refreshToken: string;
    refreshTokenExpJs: number;
}

export function postAuthToken(data: { refreshToken: string }): Promise<AuthResponse> {
    return api.post("auth/token", data).then((resp) => resp.data);
}

export interface ElidedCliToken {
    name: string;
    elidedToken: string;
    expJs?: number;
}

export interface CliToken {
    token: string,
    name?: string,
    expJs?: string,
}

export function getAuthCliTokens(idToken: string): Promise<ElidedCliToken[]> {
    return api
        .get("auth/cli-tokens", {
            headers: authHeader(idToken),
        })
        .then((resp) => resp.data);
}

export function postAuthCliTokens(idToken: string, name: string, expDays?: number): Promise<CliToken> {
    return api
        .post(
            `auth/cli-tokens`,
            {
                name,
                expDays,
            },
            {
                headers: authHeader(idToken),
            }
        )
        .then((resp) => resp.data);
}

export function delAuthCliTokens(idToken: string, elidedToken: string): Promise<ElidedCliToken[]> {
    return api
        .delete(
            `auth/cli-tokens/${encodeURIComponent(elidedToken)}`,
            {
                headers: authHeader(idToken),
            }
        )
        .then((resp) => resp.data);
}

export function useAuthCliTokens(idToken: MaybeRef<string>): UseFetchReturn<ElidedCliToken[]> {
    return useAuthApiReq<ElidedCliToken[]>("auth/cli-tokens", idToken);
}
