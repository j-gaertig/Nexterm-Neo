export const GUACAMOLE_STATUS = Object.freeze({
    UPSTREAM_TIMEOUT: 0x0202,
    UPSTREAM_ERROR: 0x0203,
    UPSTREAM_NOT_FOUND: 0x0207,
    UPSTREAM_UNAVAILABLE: 0x0208,
    SESSION_CONFLICT: 0x0209,
    SESSION_TIMEOUT: 0x020A,
    SESSION_CLOSED: 0x020B,
    CLIENT_UNAUTHORIZED: 0x0301,
});

const RDP_TERMINAL_STATUSES = new Set([
    GUACAMOLE_STATUS.SESSION_CONFLICT,
    GUACAMOLE_STATUS.SESSION_TIMEOUT,
    GUACAMOLE_STATUS.SESSION_CLOSED,
]);

const normalizeStatusCode = (statusCode) => {
    if (typeof statusCode === "number") return Number.isFinite(statusCode) ? statusCode : null;
    if (typeof statusCode !== "string" || !statusCode.trim()) return null;
    const parsed = Number(statusCode);
    return Number.isFinite(parsed) ? parsed : null;
};

const normalizeProtocol = (protocol) => String(protocol || "").trim().toLowerCase();

const isRdpServerDisconnectMessage = (message) => [
    "disconnected by other connection",
    "forcibly disconnected",
    "logged off",
    "session time limit exceeded",
    "manually disconnected",
    "manually logged off",
].some(fragment => message.includes(fragment));

export const shouldAutoReconnect = ({ protocol, statusCode, rawMessage }) => {
    const msg = String(rawMessage || "").toLowerCase();
    if (msg.includes("failed to load protocol plugin")) return false;
    if (normalizeProtocol(protocol) === "spice" || msg.includes("spice")) {
        const code = normalizeStatusCode(statusCode);
        if (code === GUACAMOLE_STATUS.CLIENT_UNAUTHORIZED) return false;
        if (msg.includes("spice authentication failed") || msg.includes("password (ticket)")) return false;
        if (msg.includes("authentication failed")) return false;
    }
    if (normalizeProtocol(protocol) !== "rdp") return true;

    const code = normalizeStatusCode(statusCode);
    if (RDP_TERMINAL_STATUSES.has(code)) return false;

    return !isRdpServerDisconnectMessage(String(rawMessage || "").toLowerCase());
};

export const mapConnectionError = (rawMessage, t, statusCode = null, protocol = null) => {
    const cleaned = String(rawMessage || "").replace(/^(error:\s*|master connection failed:\s*)+/i, "").trim();
    const msg = cleaned.toLowerCase();
    const code = normalizeStatusCode(statusCode);
    const isRdp = normalizeProtocol(protocol) === "rdp";
    const isSpice = normalizeProtocol(protocol) === "spice" || msg.includes("spice");

    if (isRdp && code === GUACAMOLE_STATUS.SESSION_CONFLICT) {
        return t("common.errors.connection.rdpSessionConflict");
    }
    if (isRdp && code === GUACAMOLE_STATUS.SESSION_TIMEOUT) {
        return t("common.errors.connection.rdpSessionTimeout");
    }
    if (isRdp && code === GUACAMOLE_STATUS.SESSION_CLOSED) {
        return t("common.errors.connection.rdpSessionClosed");
    }
    if (isRdp && msg.includes("disconnected by other connection")) {
        return t("common.errors.connection.rdpSessionConflict");
    }
    if (isRdp && (msg.includes("idle session time limit") || msg.includes("active session time limit"))) {
        return t("common.errors.connection.rdpSessionTimeout");
    }
    if (isRdp && isRdpServerDisconnectMessage(msg)) {
        return t("common.errors.connection.rdpSessionClosed");
    }
    if (!cleaned) return t("common.errors.connection.failed");
    if (msg.includes("failed to load protocol plugin")) {
        if (msg.includes("spice")) {
            try {
                const translated = t("common.errors.connection.spiceUnavailable");
                if (translated && translated !== "common.errors.connection.spiceUnavailable") return translated;
            } catch {}
            return "SPICE support is not available on the connected engine (missing libguac-client-spice). Rebuild the engine with SPICE support.";
        }
        return cleaned.replace(/\(see logs\)/gi, "").trim() || t("common.errors.connection.failed");
    }
    if (isSpice && (code === GUACAMOLE_STATUS.CLIENT_UNAUTHORIZED
        || msg.includes("spice authentication failed")
        || msg.includes("password (ticket)"))) {
        return t("common.errors.connection.authenticationFailed");
    }
    if (isSpice && (code === GUACAMOLE_STATUS.UPSTREAM_NOT_FOUND
        || code === GUACAMOLE_STATUS.UPSTREAM_UNAVAILABLE
        || code === GUACAMOLE_STATUS.UPSTREAM_TIMEOUT
        || msg.includes("unable to connect to spice")
        || msg.includes("unable to initiate connection to spice")
        || msg.includes("spice backend unreachable"))) {
        return t("common.errors.connection.hostUnreachable");
    }
    if (isSpice && (code === GUACAMOLE_STATUS.UPSTREAM_ERROR
        || msg.includes("connection to spice server failed")
        || msg.includes("tls error while connecting to spice"))) {
        return t("common.errors.connection.hostUnreachable");
    }
    if (msg.includes("server is disabled")) {
        return t("common.errors.connection.disabled");
    }
    if (msg.includes("connection not available") || msg.includes("not available")) {
        return t("common.errors.connection.hostUnreachable");
    }
    if (msg.includes("no route to host") || msg.includes("unreachable")) {
        return t("common.errors.connection.hostUnreachable");
    }
    if (msg.includes("connection refused") || msg.includes("refused")) {
        return t("common.errors.connection.refused");
    }
    if (msg.includes("timeout") || msg.includes("timed out")) {
        return t("common.errors.connection.timeout");
    }
    if (msg.includes("authentication") || msg.includes("auth")) {
        return t("common.errors.connection.authenticationFailed");
    }
    if (msg.includes("permission denied")) {
        return t("common.errors.connection.permissionDenied");
    }
    if (msg.includes("aborted") || msg.includes("see logs")) {
        return t("common.errors.connection.hostUnreachable");
    }

    return cleaned.replace(/\(see logs\)/gi, "").trim() || t("common.errors.connection.failed");
};

export const classifyConnectionError = ({ rawMessage, statusCode = null, protocol = null, t }) => ({
    message: mapConnectionError(rawMessage, t, statusCode, protocol),
    autoReconnect: shouldAutoReconnect({ protocol, statusCode, rawMessage }),
});
