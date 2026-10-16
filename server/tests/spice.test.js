const test = require("node:test");
const assert = require("node:assert/strict");
const net = require("node:net");

const {
    SPICE_DEFAULT_PORT,
    isSpiceMissingPluginError,
    classifySpiceFailure,
    checkSpiceTcpReachable,
    normalizeSpicePort,
} = require("../lib/spiceUtils.js");

const translations = {
    "common.errors.connection.rdpSessionConflict": "rdp conflict",
    "common.errors.connection.hostUnreachable": "host unreachable",
    "common.errors.connection.refused": "refused",
    "common.errors.connection.timeout": "timeout",
    "common.errors.connection.authenticationFailed": "auth failed",
    "common.errors.connection.failed": "failed",
    "common.errors.connection.spiceUnavailable": "spice unavailable",
};
const t = (key) => translations[key] || key;

let connectionErrorUtil;

test.before(async () => {
    connectionErrorUtil = await import("../../client/src/common/utils/ConnectionErrorUtil.js");
});

test("SPICE default port matches QEMU convention (5930)", () => {
    assert.equal(SPICE_DEFAULT_PORT, 5930);
    assert.equal(normalizeSpicePort(undefined), 5930);
    assert.equal(normalizeSpicePort(""), 5930);
    assert.equal(normalizeSpicePort("5930"), 5930);
    assert.equal(normalizeSpicePort("5900"), 5900);
    assert.equal(normalizeSpicePort("notaport"), 5930);
});

test("missing plugin is detected only for SPICE", () => {
    assert.equal(isSpiceMissingPluginError("Failed to load protocol plugin 'spice': libguac-client-spice.so missing"), true);
    assert.equal(isSpiceMissingPluginError("Failed to load protocol plugin 'vnc': foo"), false);
    assert.equal(isSpiceMissingPluginError("SPICE authentication failed"), false);
    assert.equal(classifySpiceFailure("Failed to load protocol plugin 'spice': xxx"), "missing-plugin");
});

test("SPICE auth vs unreachable classification", () => {
    assert.equal(classifySpiceFailure("SPICE authentication failed. Verify the configured password (ticket)."), "auth");
    assert.equal(classifySpiceFailure("anything", 0x0301), "auth");
    assert.equal(classifySpiceFailure("Unable to connect to SPICE server."), "unreachable");
    assert.equal(classifySpiceFailure("Unable to initiate connection to SPICE server."), "unreachable");
    assert.equal(classifySpiceFailure("SPICE backend unreachable at 192.168.178.108:5930 (ECONNREFUSED)"), "unreachable");
    assert.equal(classifySpiceFailure("anything", 0x0207), "unreachable");
    assert.equal(classifySpiceFailure("Connection to SPICE server failed or was lost."), "lost");
    assert.equal(classifySpiceFailure("some random vnc error"), "unknown");
});

test("SPICE TCP preflight succeeds for open ports and fails distinctively when closed", async () => {
    const server = net.createServer(() => {});
    await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
    const port = server.address().port;
    await checkSpiceTcpReachable("127.0.0.1", port, 2000);
    await new Promise((resolve) => server.close(resolve));
    await assert.rejects(
        () => checkSpiceTcpReachable("127.0.0.1", port, 500),
        (err) => {
            assert.match(err.message, /SPICE backend unreachable/);
            return true;
        }
    );
    await assert.rejects(() => checkSpiceTcpReachable("", 5930, 200), /Missing SPICE host/);
    await assert.rejects(() => checkSpiceTcpReachable("127.0.0.1", "bogus", 200), /Invalid SPICE port/);
});

test("UI maps SPICE wrong-password distinctly from unreachable backend", () => {
    const { classifyConnectionError } = connectionErrorUtil;

    assert.deepEqual(classifyConnectionError({
        rawMessage: "Master connection failed: error: SPICE authentication failed. Verify the configured password (ticket).",
        protocol: "spice",
        t,
    }), { message: "auth failed", autoReconnect: false });

    assert.deepEqual(classifyConnectionError({
        rawMessage: "Master connection failed: error: Unable to connect to SPICE server.",
        protocol: "spice",
        t,
    }), { message: "host unreachable", autoReconnect: true });

    assert.deepEqual(classifyConnectionError({
        rawMessage: "SPICE backend unreachable at 192.168.178.108:5930 (ECONNREFUSED)",
        protocol: "spice",
        t,
    }), { message: "host unreachable", autoReconnect: true });
});

test("UI maps missing SPICE plugin distinctly and disables auto-reconnect", () => {
    const { classifyConnectionError } = connectionErrorUtil;
    assert.deepEqual(classifyConnectionError({
        rawMessage: "Failed to load protocol plugin 'spice': libguac-client-spice.so cannot open shared object file (SPICE support not built into this engine build; rebuild with spice-gtk/spice-client-glib available)",
        protocol: "spice",
        t,
    }), { message: "spice unavailable", autoReconnect: false });
});

test("SPICE status codes map without message text", () => {
    const { classifyConnectionError } = connectionErrorUtil;
    assert.equal(classifyConnectionError({ rawMessage: "Unauthorized", statusCode: 0x0301, protocol: "spice", t }).message, "auth failed");
    assert.equal(classifyConnectionError({ rawMessage: "Not found", statusCode: 0x0207, protocol: "spice", t }).message, "host unreachable");
});

test("SSH/VNC/RDP error mapping has no regression", () => {
    const { classifyConnectionError } = connectionErrorUtil;
    assert.equal(classifyConnectionError({ rawMessage: "Connection refused", protocol: "vnc", t }).message, "refused");
    assert.equal(classifyConnectionError({ rawMessage: "No route to host", protocol: "rdp", statusCode: 0x0207, t }).message, "host unreachable");
    assert.equal(classifyConnectionError({ rawMessage: "Authentication failed", protocol: "ssh", t }).message, "auth failed");
});
