// The host API of Rex / ForwardWidgets modules, over the TVBox prelude (which supplies timers and the console).
// A module is a plain script that sets `WidgetMetadata` and declares the functions it names. This build supplies
// `Widget.http` and `Widget.html.load` (cheerio, as the TVBox prelude uses it); `Widget.tmdb` is refused with a clear error
// until its mapping is done. `Widget.storage` is a session-only cache. See Rex.swift.
import * as cheerio from 'assets://js/lib/cheerio.min.js';
const host = globalThis.__host;
const requestTimeout = 15000;

function parseBody(text) {
    if (typeof text !== 'string') return text;
    const trimmed = text.trim();
    if (trimmed[0] === '{' || trimmed[0] === '[') { try { return JSON.parse(trimmed); } catch (error) { /* plain text */ } }
    return text;
}

function withParams(url, params) {
    if (!params || typeof params !== 'object') return String(url);
    const query = Object.keys(params).filter(key => params[key] != null)
        .map(key => encodeURIComponent(key) + '=' + encodeURIComponent(String(params[key]))).join('&');
    if (!query) return String(url);
    return String(url) + (String(url).includes('?') ? '&' : '?') + query;
}

function send(method, url, body, options) {
    options = options || {};
    const headers = Object.assign({}, options.headers || {});
    let text;
    if (body != null) {
        if (typeof body === 'string') text = body;
        else {
            text = JSON.stringify(body);
            if (!Object.keys(headers).some(name => name.toLowerCase() === 'content-type')) headers['Content-Type'] = 'application/json';
        }
    }
    const payload = { url: withParams(url, options.params), method, headers, body: text == null ? null : String(text),
        timeout: Math.min(Number(options.timeout) || requestTimeout, requestTimeout), encoding: 'utf-8' };
    return new Promise((resolve, reject) => {
        let id;
        try { id = host('httpStart', JSON.stringify(payload)); } catch (error) { reject(new Error(String(error && error.message || error))); return; }
        const poll = () => {
            const answer = host('httpPoll', id);
            if (answer == null) { setTimeout(poll, 10); return; }
            const result = JSON.parse(answer);
            const code = result.code || 0;
            if (result.failed || code === 0) { reject(new Error('Network error: ' + String(result.failed || 'no answer').slice(0, 120))); return; }
            if (code >= 400) { reject(new Error('HTTP ' + code)); return; }
            resolve({ data: parseBody(result.content == null ? '' : result.content), status: code, statusCode: code, headers: result.headers || {} });
        };
        setTimeout(poll, 0);
    });
}

const unsupported = what => () => { throw new Error('REX_UNSUPPORTED:' + what); };
// Widget.storage: a key-value cache that lives only as long as this module's runtime (one runtime per module, so modules
// never see each other's keys). It is NOT kept across app launches, and a runtime that is dropped to make room for another
// takes its cache with it. Values are copied in and out as JSON, so a stored object comes back as a fresh copy. A missing
// key reads as null. Both the get/set and the getItem/setItem spellings that modules use are answered synchronously.
const storageValues = new Map();
const copyValue = value => (value === undefined ? undefined : JSON.parse(JSON.stringify(value)));
const storage = {
    get: key => (storageValues.has(String(key)) ? copyValue(storageValues.get(String(key))) : null),
    set: (key, value) => { if (value === undefined) storageValues.delete(String(key)); else storageValues.set(String(key), copyValue(value)); },
    remove: key => { storageValues.delete(String(key)); },
    clear: () => { storageValues.clear(); },
};
storage.getItem = storage.get; storage.setItem = storage.set; storage.removeItem = storage.remove;

globalThis.Widget = {
    http: {
        get: (url, options) => send('GET', url, null, options),
        post: (url, body, options) => {
            if (body && typeof body === 'object' && options == null && ('body' in body || 'headers' in body || 'params' in body)) { options = body; body = options.body; }
            return send('POST', url, body, options);
        },
    },
    // Rex passes the page text and gets a synchronous jQuery-like function back.
    storage,
    html: { load: html => cheerio.load(typeof html === 'string' ? html : html == null ? '' : typeof html === 'object' ? JSON.stringify(html) : String(html)) },
    tmdb: { get: unsupported('Widget.tmdb.get') },
};

globalThis.__rex = {
    // Runs the module as a classic script and reads its WidgetMetadata. The lookup is appended to the same
    // script, so it also sees `const` and `let` declarations that a plain global would not.
    load() {
        const source = host('module', 'rex://module');
        (0, eval)(source + '\n;globalThis.__rexLookup = name => { try { return eval(name); } catch (error) { return undefined; } };');
        const meta = globalThis.__rexLookup('WidgetMetadata');
        if (!meta || typeof meta !== 'object') throw new Error('The module has no WidgetMetadata');
        return JSON.parse(JSON.stringify(meta));
    },
    async call(name, params) {
        try {
            const fn = globalThis.__rexLookup(String(name));
            if (typeof fn !== 'function') throw new Error('The module has no function ' + name);
            const result = await fn(params || {});
            const list = Array.isArray(result) ? result : (result && Array.isArray(result.items) ? result.items : []);
            return { items: JSON.parse(JSON.stringify(list)) };
        } catch (error) {
            return { error: String(error && error.message || error).slice(0, 300) };
        }
    },
};
