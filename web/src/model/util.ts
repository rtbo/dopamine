
export type QueryObj = Record<string, string | number | boolean>;

export function encodeQuery(query: QueryObj): string {
    const res = [];
    for (const k in query) {
        if (typeof query[k] === "boolean" && query[k]) res.push(encodeURIComponent(k));
        else res.push(`${encodeURIComponent(k)}=${encodeURIComponent(query[k])}`);
    }
    return res.join("&");
}

export function encodeUrlQuery(url: string, query: QueryObj): string {
    const u = encodeURI(url);
    const q = encodeQuery(query);
    if (q.length) {
        return `${u}?${q}`;
    }
    return u;
}

export function parseQueryString(str: string): QueryObj {
    const obj: QueryObj = {};

    str = str || "";

    str.split("&").forEach((param) => {
        const keyVal = param.split("=");
        const key = decodeURIComponent(keyVal[0]);
        const val = keyVal[1] ?? decodeURIComponent(keyVal[1]);
        const num = +val;
        if (!isNaN(num)) {
            obj[key] = num;
        } else if (val) {
            obj[key] = val;
        } else {
            obj[key] = true;
        }
    });

    return obj;
}

/**
 * Get full path based on current location
 *
 * @author Sahat Yalkabov <https://github.com/sahat>
 * @copyright Method taken from https://github.com/sahat/satellizer
 *
 * @param  {Location | HTMLAnchorElement} location
 * @return {String}
 */
export function getFullUrlPath(location: Location | HTMLAnchorElement) {
    const isHttps = location.protocol === "https:";
    return (
        location.protocol +
        "//" +
        location.hostname +
        ":" +
        (location.port || (isHttps ? "443" : "80")) +
        (/^\//.test(location.pathname) ? location.pathname : "/" + location.pathname)
    );
}

// bytesToBase64 is nearly unmodified version of base64ArrayBuffer
// from https://gist.github.com/jonleighton/958841 with following license and copyright
//
// MIT LICENSE
// Copyright 2011 Jon Leighton
// Permission is hereby granted, free of charge, to any person obtaining a copy of this software
// and associated documentation files (the "Software"), to deal in the Software without restriction,
// including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense,
// and/or sell copies of the Software, and to permit persons to whom the Software is furnished
// to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all copies
// or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT
// LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
// IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
// WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
// SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
export function bytesToBase64(bytes: Uint8Array): string {
    const encodings = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    let base64 = "";

    const byteLength = bytes.byteLength;
    const byteRemainder = byteLength % 3;
    const mainLength = byteLength - byteRemainder;

    // Main loop deals with bytes in chunks of 3
    for (let i = 0; i < mainLength; i = i + 3) {
        // Combine the three bytes into a single integer
        const chunk = (bytes[i] << 16) | (bytes[i + 1] << 8) | bytes[i + 2];

        // Use bitmasks to extract 6-bit segments from the triplet
        const a = (chunk & 16515072) >> 18; // 16515072 = (2^6 - 1) << 18
        const b = (chunk & 258048) >> 12; // 258048   = (2^6 - 1) << 12
        const c = (chunk & 4032) >> 6; // 4032     = (2^6 - 1) << 6
        const d = chunk & 63; // 63       = 2^6 - 1

        // Convert the raw binary segments to the appropriate ASCII encoding
        base64 += encodings[a] + encodings[b] + encodings[c] + encodings[d];
    }

    // Deal with the remaining bytes and padding
    if (byteRemainder == 1) {
        const chunk = bytes[mainLength];

        const a = (chunk & 252) >> 2; // 252 = (2^6 - 1) << 2

        // Set the 4 least significant bits to zero
        const b = (chunk & 3) << 4; // 3   = 2^2 - 1

        base64 += encodings[a] + encodings[b] + "==";
    } else if (byteRemainder == 2) {
        const chunk = (bytes[mainLength] << 8) | bytes[mainLength + 1];

        const a = (chunk & 64512) >> 10; // 64512 = (2^6 - 1) << 10
        const b = (chunk & 1008) >> 4; // 1008  = (2^6 - 1) << 4

        // Set the 2 least significant bits to zero
        const c = (chunk & 15) << 2; // 15    = 2^4 - 1

        base64 += encodings[a] + encodings[b] + encodings[c] + "=";
    }

    return base64;
}