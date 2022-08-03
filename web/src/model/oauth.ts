import { resource } from "./api";
import { encodeUrlQuery, getFullUrlPath, parseQueryString, QueryObj } from "./util";

import cryptoRandomString from "crypto-random-string";
import { inject, InjectionKey, provide, ref, Ref } from "vue";

export type Provider = "github" | "google";

export interface OAuthConfig {
    apiAuthUrl: string;
    providers: Record<Provider, ProviderConfig>;
}

interface ProviderConfig {
    clientId: string;
    requestUrl: string;
    redirectUrl: string;
    scope: string;
}

const config: OAuthConfig = {
    apiAuthUrl: resource("/auth"),
    providers: {
        github: {
            clientId: import.meta.env.VITE_GITHUB_CLIENT_ID || "3f2f6c2ce1e0bdf8ae6c",
            requestUrl: "https://github.com/login/oauth/authorize",
            redirectUrl: `${window.location.origin}/oauth/github`,
            scope: "read:user user:email",
        },
        google: {
            clientId:
                import.meta.env.VITE_GOOGLE_CLIENT_ID ||
                "241559404387-jf6rp461t5ikahsgrjop48jm5u97ur5t.apps.googleusercontent.com",
            requestUrl: "https://accounts.google.com/o/oauth2/v2/auth",
            redirectUrl: `${window.location.origin}/oauth/google`,
            scope: "profile email openid",
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

interface PopupQuery {
    client_id: string;
    redirect_uri: string;
    state: string;
    scope: string;
    response_type: string;
}

interface PopupResp {
    state: string;
    code: string;
}

export interface OAuthResult {
    provider: Provider;
    code: string;
    redirectUri: string;
}

export interface OAuth {
    popupOn: Ref<boolean>;
    authenticate(provider: Provider, popupOpts?: Partial<PopupOptions>): Promise<OAuthResult>;
}

const OAuthSymbol: InjectionKey<OAuth> = Symbol();

export function provideOAuth() {
    const popupOn = ref(false);

    async function authenticate(provider: Provider, popupOpts?: Partial<PopupOptions>): Promise<OAuthResult> {
        const conf = config.providers[provider];

        const state = cryptoRandomString({
            length: 16,
            type: "base64",
        });

        try {
            popupOn.value = true;
            const params = await doPopup(conf, state, popupOpts);

            if (params["state"] !== state) {
                throw new Error(`OAuth2 failure: wrong state`);
            }

            return {
                provider,
                code: params["code"],
                redirectUri: conf.redirectUrl,
            }
        } finally {
            popupOn.value = false;
        }
    }

    const oauth = {
        popupOn,
        authenticate,
    };

    provide(OAuthSymbol, oauth);
}

export function useOAuth(): OAuth {
    const oauth = inject(OAuthSymbol);
    if (!oauth) throw new Error("OAuth not provided yet");
    return oauth;
}

// open OAuth popup window of provider and return popup result
function doPopup(
    config: ProviderConfig,
    state: string,
    partialOpts?: Partial<PopupOptions>
): Promise<PopupResp> {
    const query: PopupQuery = {
        client_id: config.clientId,
        redirect_uri: config.redirectUrl,
        scope: config.scope,
        state,
        response_type: "code",
    };

    const opts: Record<string, string | number> = {
        ...defaultPopupOptions,
        ...partialOpts,
    };

    const popup = window.open(
        encodeUrlQuery(config.requestUrl, query as unknown as QueryObj),
        "Authentication",
        stringifyOptions(opts)
    );

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
