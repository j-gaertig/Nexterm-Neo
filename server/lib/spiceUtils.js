const net = require("node:net");

const SPICE_DEFAULT_PORT = 5930;

const isSpiceMissingPluginError = (message) => {
    const msg = String(message || "");
    return /failed to load protocol plugin/i.test(msg) && /spice/i.test(msg);
};

const classifySpiceFailure = (rawMessage, statusCode = null) => {
    const msg = String(rawMessage || "").toLowerCase();
    const code = typeof statusCode === "number" && Number.isFinite(statusCode) ? statusCode : null;

    if (/failed to load protocol plugin/i.test(String(rawMessage || ""))) return "missing-plugin";
    if (code === 0x0301) return "auth";
    if (code === 0x0207 || code === 0x0208) return "unreachable";
    if (code === 0x0202) return "timeout";
    if (msg.includes("spice authentication failed") || msg.includes("password (ticket)")) return "auth";
    if (msg.includes("unable to connect to spice") || msg.includes("unable to initiate connection to spice")) return "unreachable";
    if (msg.includes("spice backend unreachable")) return "unreachable";
    if (msg.includes("connection to spice server failed") || msg.includes("was lost")) return "lost";
    if (msg.includes("tls error while connecting to spice")) return "unreachable";
    return "unknown";
};

const checkSpiceTcpReachable = (host, port, timeoutMs = 5000) => new Promise((resolve, reject) => {
    if (!host) {
        reject(new Error("Missing SPICE host"));
        return;
    }
    const numericPort = Number.parseInt(port, 10);
    if (!Number.isInteger(numericPort) || numericPort <= 0 || numericPort > 65535) {
        reject(new Error(`Invalid SPICE port: ${port}`));
        return;
    }
    const socket = new net.Socket();
    let settled = false;
    const cleanup = () => {
        try { socket.removeAllListeners(); } catch {}
        try { socket.destroy(); } catch {}
    };
    const fail = (err) => {
        if (settled) return;
        settled = true;
        cleanup();
        reject(err);
    };
    const succeed = () => {
        if (settled) return;
        settled = true;
        cleanup();
        resolve(true);
    };
    socket.setTimeout(timeoutMs);
    socket.once("timeout", () => fail(new Error(`SPICE backend unreachable at ${host}:${numericPort} (connection timed out after ${timeoutMs}ms)`)));
    socket.once("error", (err) => fail(new Error(`SPICE backend unreachable at ${host}:${numericPort} (${err.code || err.message})`)));
    socket.connect(numericPort, host, succeed);
});

const normalizeSpicePort = (port) => {
    const numeric = Number.parseInt(port, 10);
    if (Number.isInteger(numeric) && numeric > 0 && numeric <= 65535) return numeric;
    return SPICE_DEFAULT_PORT;
};

module.exports = {
    SPICE_DEFAULT_PORT,
    isSpiceMissingPluginError,
    classifySpiceFailure,
    checkSpiceTcpReachable,
    normalizeSpicePort,
};
