const test = require("node:test");
const assert = require("node:assert/strict");

const {
    getSessionAccessError,
    getSessionShareError,
    getScriptConnectionError,
} = require("../lib/sessionAuthorization");

test("session ownership distinguishes missing, foreign and owned sessions", () => {
    assert.deepEqual(getSessionAccessError(null, 7), {
        code: 404,
        message: "Session not found",
    });
    assert.deepEqual(getSessionAccessError({ accountId: 8 }, 7), {
        code: 403,
        message: "Access denied",
    });
    assert.equal(getSessionAccessError({ accountId: 7 }, 7), null);
});

test("script sessions cannot be shared", () => {
    assert.deepEqual(
        getSessionShareError({ configuration: { scriptId: 12 } }),
        { code: 400, message: "Script sessions cannot be shared" },
    );
    assert.equal(getSessionShareError({ configuration: {} }), null);
    assert.equal(getSessionShareError(null), null);
});

test("scripts are accepted only for plain SSH connections", () => {
    const sshServer = { type: "server", config: { protocol: "ssh" } };
    assert.equal(getScriptConnectionError(sshServer, null, 3), null);
    assert.equal(
        getScriptConnectionError({ type: "ssh", config: {} }, null, 3),
        null,
    );

    const message = "Scripts can only be executed on SSH connections";
    assert.deepEqual(getScriptConnectionError(sshServer, "terminal", 3), {
        code: 400,
        message,
    });
    assert.deepEqual(getScriptConnectionError(sshServer, "sftp", 3), {
        code: 400,
        message,
    });
    assert.deepEqual(
        getScriptConnectionError(
            { type: "server", config: { protocol: "rdp" } },
            null,
            3,
        ),
        { code: 400, message },
    );
    assert.deepEqual(
        getScriptConnectionError({ type: "web", config: {} }, null, 3),
        { code: 400, message },
    );
});

test("non-script requests are unaffected by the SSH-only rule", () => {
    assert.equal(
        getScriptConnectionError(
            { type: "server", config: { protocol: "rdp" } },
            "terminal",
            null,
        ),
        null,
    );
});
