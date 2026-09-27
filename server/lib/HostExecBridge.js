const net = require("node:net");

const SOCKET_PATH = process.env.NEXTERM_HOST_EXEC_SOCKET || "/run/nexterm-host-exec/host-exec.sock";
const COMMAND_MAX = 2000;
const OUTPUT_MAX = 64 * 1024;
const TIMEOUT_MS = 120000;
const RESPONSE_MAX = OUTPUT_MAX * 12 + 4096;
const createAbortError = () => Object.assign(new Error("Host command was cancelled"), { code: "ABORT_ERR" });
const createUnavailableError = (cause) => Object.assign(new Error("Docker-host command bridge is unavailable"), { code: "HOST_BRIDGE_UNAVAILABLE", cause });

const connect = (signal = null) => new Promise((resolve, reject) => {
    const socket = net.createConnection(SOCKET_PATH);
    let settled = false;
    const finish = (callback, value) => {
        if (settled) return;
        settled = true;
        signal?.removeEventListener("abort", onAbort);
        callback(value);
    };
    const onAbort = () => {
        socket.destroy();
        finish(reject, createAbortError());
    };
    socket.once("connect", () => finish(resolve, socket));
    socket.once("error", (err) => finish(reject, err));
    signal?.addEventListener("abort", onAbort, { once: true });
    if (signal?.aborted) onAbort();
});

const isAvailable = async () => {
    try {
        const socket = await connect();
        return await new Promise((resolve) => {
            let response = "";
            const timer = setTimeout(() => {
                socket.destroy();
                resolve(false);
            }, 1000);
            socket.on("data", (chunk) => {
                response += chunk.toString("utf8");
                const newline = response.indexOf("\n");
                if (newline < 0) return;
                clearTimeout(timer);
                socket.destroy();
                try {
                    resolve(JSON.parse(response.slice(0, newline)).available === true);
                } catch {
                    resolve(false);
                }
            });
            socket.once("error", () => {
                clearTimeout(timer);
                resolve(false);
            });
            socket.write('{"health":true}\n');
        });
    } catch {
        return false;
    }
};

const exec = async (command, timeoutMs = TIMEOUT_MS, signal = null) => {
    if (typeof command !== "string" || !command.trim()) throw new Error("Host command is empty");
    if (command.length > COMMAND_MAX) throw new Error("Host command exceeds 2000 characters");
    if (!Number.isFinite(timeoutMs) || timeoutMs < 1) throw new Error("Invalid host command timeout");
    if (signal?.aborted) throw createAbortError();

    let socket;
    try {
        socket = await connect(signal);
    } catch (err) {
        if (err.code === "ABORT_ERR") throw err;
        throw createUnavailableError(err);
    }
    const request = JSON.stringify({ command, timeoutMs: Math.min(Math.max(timeoutMs, 1), TIMEOUT_MS) });
    return new Promise((resolve, reject) => {
        let response = "";
        let settled = false;
        const settle = (callback, value) => {
            if (settled) return;
            settled = true;
            signal?.removeEventListener("abort", onAbort);
            socket.destroy();
            callback(value);
        };
        const onAbort = () => settle(reject, createAbortError());
        signal?.addEventListener("abort", onAbort, { once: true });
        if (signal?.aborted) {
            onAbort();
            return;
        }

        socket.setTimeout(TIMEOUT_MS + 5000, () => settle(reject, new Error("Host command bridge timed out")));
        socket.on("data", (chunk) => {
            response += chunk.toString("utf8");
            if (Buffer.byteLength(response, "utf8") > RESPONSE_MAX) {
                settle(reject, createUnavailableError(new Error("Host command bridge response exceeded its limit")));
                return;
            }
            const newline = response.indexOf("\n");
            if (newline < 0) return;
            try {
                const result = JSON.parse(response.slice(0, newline));
                settle(resolve, result);
            } catch (err) {
                settle(reject, createUnavailableError(err));
            }
        });
        socket.once("error", (err) => settle(reject, createUnavailableError(err)));
        socket.once("end", () => {
            if (!settled) settle(reject, createUnavailableError(new Error("Host command bridge closed without a result")));
        });
        socket.write(`${request}\n`, "utf8", (err) => {
            if (err) settle(reject, createUnavailableError(err));
        });
    });
};

module.exports = { exec, isAvailable, SOCKET_PATH, COMMAND_MAX, OUTPUT_MAX, TIMEOUT_MS };
