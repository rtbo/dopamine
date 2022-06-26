const host = import.meta.env.VITE_API_HOST || "https://localhost:3500";
const prefix = import.meta.env.VITE_API_PREFIX || "/api";

export function resource(path: string): string {
    return `${host}${prefix}${path || ""}`;
}
