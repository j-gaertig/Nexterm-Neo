const OSC52_SEQ_RE = /(?:\x1b\]|\x9d)52;[^\x07\x1b\x9c]*(?:\x07|\x1b\\|\x9c)/g;
const OSC52_TAIL_RE = /(?:\x1b\]|\x9d)52;[A-Za-z0-9+/=;: ]{0,4096}$/;

export const stripOsc52 = (text) => {
    try {
        if (typeof text !== "string" || !text) return text;
        if (text.indexOf("\x1b]52;") < 0 && text.indexOf("\x9d52;") < 0) return text;
        OSC52_SEQ_RE.lastIndex = 0;
        return text.replace(OSC52_SEQ_RE, "").replace(OSC52_TAIL_RE, "");
    } catch {
        return text;
    }
};

export const attachOsc52 = (term, enabled = true) => {
    if (!term || !enabled) return null;
    let disposed = false;
    let lastAttempt = 0;
    let lastWrite = 0;
    const fallbackCopy = (text) => {
        try {
            if (typeof document === "undefined" || !document.body) return;
            if (typeof document.hasFocus === "function" && !document.hasFocus()) return;
            if (typeof document.visibilityState !== "undefined" && document.visibilityState !== "visible") return;
            const area = document.createElement("textarea");
            area.value = text;
            area.style.position = "fixed";
            area.style.left = "-9999px";
            area.style.top = "-9999px";
            area.setAttribute("readonly", "");
            document.body.appendChild(area);
            try {
                area.focus();
            } catch {}
            try {
                area.select();
            } catch {}
            try {
                document.execCommand("copy");
            } catch {}
            document.body.removeChild(area);
        } catch {}
    };
    const writeClipboard = (text) => {
        if (disposed) return;
        try {
            if (typeof document !== "undefined") {
                if (typeof document.hasFocus === "function" && !document.hasFocus()) return;
                if (typeof document.visibilityState !== "undefined" && document.visibilityState !== "visible") return;
            }
            if (typeof navigator !== "undefined" && navigator.clipboard && navigator.clipboard.writeText) {
                navigator.clipboard.writeText(text).catch(() => fallbackCopy(text));
                return;
            }
        } catch {}
        fallbackCopy(text);
    };
    const handler = (data) => {
        try {
            if (disposed) return true;
            const now = Date.now();
            if (now - lastAttempt < 100) return true;
            lastAttempt = now;
            const parts = data.split(";");
            if (parts.length < 2) return false;
            const payload = parts[parts.length - 1];
            if (payload === "?" || payload === "") return true;
            const targets = parts.slice(0, -1).join(";").toLowerCase();
            if (targets && !targets.includes("c")) return true;
            if (payload.length > 500000) return true;
            if (now - lastWrite < 500) return true;
            let clean = "";
            try {
                clean = payload.replace(/\s/g, "");
            } catch {
                clean = payload;
            }
            if (!clean || clean.length > 500000) return true;
            let bin = "";
            try {
                bin = atob(clean);
            } catch {
                return true;
            }
            let text = "";
            try {
                const bytes = Uint8Array.from(bin, (c) => c.charCodeAt(0));
                text = new TextDecoder("utf-8", { fatal: true }).decode(bytes);
            } catch {
                return true;
            }
            if (!text || text.length > 375000) return true;
            lastWrite = now;
            writeClipboard(text);
            return true;
        } catch {
            return true;
        }
    };
    try {
        if (term.parser && term.parser.registerOscHandler) {
            const disposable = term.parser.registerOscHandler(52, handler);
            const originalDispose = disposable && disposable.dispose ? disposable.dispose.bind(disposable) : null;
            if (originalDispose) {
                return {
                    dispose: () => {
                        disposed = true;
                        try {
                            originalDispose();
                        } catch {}
                    },
                };
            }
            return disposable;
        }
    } catch {}
    return null;
};
