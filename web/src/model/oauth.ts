import { resource } from "./api";
import { encodeUrlQuery, getFullUrlPath, parseQueryString } from "./util";

import axios from "axios";
import cryptoRandomString from "crypto-random-string";
import { App, inject, InjectionKey, provide, ref, Ref } from "vue";

type Provider = "github";

export interface OAuthConfig {
    apiAuthUrl: string;
    providers: Record<Provider, ProviderConfig>;
}

interface ProviderConfig {
    clientId: string;
    requestUrl: string;
    redirectUrl: string;
}

const config: OAuthConfig = {
    apiAuthUrl: resource("/v1/auth"),
    providers: {
        github: {
            clientId: import.meta.env.VITE_GITHUB_CLIENT_ID || "3f2f6c2ce1e0bdf8ae6c",
            requestUrl: "https://github.com/login/oauth/authorize",
            redirectUrl: `${window.location.origin}/auth/github`,
        },
    },
};

export interface PopupOptions {
    menubar: "yes" | "no";
    location: "yes" | "no";
    resizable: "yes" | "no";
    scrollbar: "yes" | "no";
    status: "yes" | "no";
    width: number;
    height: number;
}

const defaultPopupOptions: PopupOptions = {
    menubar: "no",
    location: "no",
    resizable: "no",
    scrollbar: "no",
    status: "no",
    width: 1020,
    height: 618,
};

interface PopupResp {
    state: string;
    code: string;
}

export type OAuthStatus = "" | "popup" | "api-auth" | "success" | "error";

export interface OAuthSuccess {
    success: true;
    token: string;
    name: string;
    email: string;
    avatarUrl: string;
}

export interface OAuthFailure {
    success: false;
    msg: string;
}

export type OAuthResult = OAuthSuccess | OAuthFailure;

export interface OAuth {
    status: Ref<OAuthStatus>;
    loading: Ref<boolean>;
    error: Ref<string>;
    result: Ref<OAuthResult | null>;
    authenticate(provider: Provider, popupOpts?: Partial<PopupOptions>): Promise<OAuthResult>;
}

const OAuthSymbol: InjectionKey<OAuth> = Symbol();

export function provideOAuth(app: App) {
    const status = ref("" as OAuthStatus);
    const loading = ref(false);
    const error = ref("");
    const result = ref(null);

    async function authenticate(provider: Provider, popupOpts?: Partial<PopupOptions>): Promise<OAuthResult> {
        try {
            const conf = config.providers[provider];

            const state = cryptoRandomString({
                length: 8,
                type: "ascii-printable",
            });

            status.value = "popup";
            loading.value = true;

            const params = await doPopup(conf, state, popupOpts);

            status.value = "api-auth";

            const apiUrl = "http://localhost:3500/api/v1/auth";

            const resp = await axios.post<OAuthResult>(apiUrl, {
                provider,
                code: params["code"],
                state: params["state"],
            });

            if (resp.status >= 400) {
                throw new Error(`POST ${apiUrl} returned ${resp.status}: ${resp.data}`);
            }
            return resp.data;
        } catch (e) {
            status.value = "error";
            return {
                success: false,
                msg: "could not log",
            };
        }
    }

    const oauth = {
        status,
        loading,
        error,
        result,
        authenticate,
    };

    app.provide(OAuthSymbol, oauth);
}

export function useOAuth(): OAuth {
    const oauth = inject(OAuthSymbol);
    if (!oauth) throw new Error("OAuth not provided yet");
    return oauth;
}

// open OAuth popup window of provider and return popup result
function doPopup(config: ProviderConfig, state: string, partialOpts?: Partial<PopupOptions>): Promise<PopupResp> {
    const query = {
        client_id: config.clientId,
        redirect_uri: config.redirectUrl,
        state,
    };

    const opts: Record<string, string | number> = {
        ...defaultPopupOptions,
        ...partialOpts,
    };

    const popup = window.open(encodeUrlQuery(config.requestUrl, query), "Authentication", stringifyOptions(opts));

    if (popup && popup.focus) popup.focus();

    return new Promise((resolve, reject) => {
        const anchor = document.createElement("a");
        anchor.href = config.redirectUrl;
        const path = getFullUrlPath(anchor);

        const poll = setInterval(() => {
            if (!popup || popup.closed || popup.closed === undefined) {
                clearInterval(poll);
                return reject(new Error("Auth popup window closed"));
            }

            try {
                const popupPath = getFullUrlPath(popup.location);
                if (popupPath === path) {
                    if (popup.location.search) {
                        const popupQuery = parseQueryString(popup.location.search.substring(1));
                        if (typeof popupQuery["code"] !== "string" || typeof popupQuery["state"] !== "string") {
                            reject(new Error("OAuth redirection is missing code or state"));
                        } else {
                            resolve(popupQuery as unknown as PopupResp);
                        }
                    } else {
                        reject(new Error("No query in the OAuth redirection"));
                    }
                    clearInterval(poll);
                    popup.close();
                }
            } catch (e) {}
        }, 400);
    });
}

function stringifyOptions(options: Record<string, string | number>): string {
    const arr = [];
    for (const k in options) {
        if (options[k] !== undefined) {
            arr.push(`${k}=${options[k]}`);
        }
    }
    return arr.join(",");
}
