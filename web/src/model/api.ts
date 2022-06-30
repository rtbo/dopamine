import axios from "axios";
import { Provider, OAuthResult } from "./oauth";

const host = import.meta.env.VITE_API_HOST || "http://localhost:3500";
const prefix = import.meta.env.VITE_API_PREFIX || "/api";

export function resource(path: string): string {
    return `${host}${prefix}${path || ""}`;
}

export interface OAuthRequest {
    provider: Provider;
}

export interface AuthResponse {
    idToken: string;
    refreshToken: string;
    refreshTokenExp: number;
}

export function postOAuth(data: OAuthResult): Promise<AuthResponse> {
    return axios.post(resource("/auth"), data).then(resp => resp.data);
}

export function postAuthToken(data: { refreshToken: string }): Promise<AuthResponse> {
    return axios.post(resource("/auth/token"), data).then(resp => resp.data);
}
