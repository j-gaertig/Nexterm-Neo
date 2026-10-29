const test = require("node:test");
const assert = require("node:assert/strict");

const { buildOIDCLogoutUrl, getPostLogoutRedirectUri, normalizeProviderData } = require("../utils/oidcLogout");
const { createOIDCSessionContext } = require("../utils/oidcSession");
const { logoutWithDependencies } = require("../utils/sessionLogout");
const { oidcProviderUpdateValidation } = require("../validations/oidc");

const provider = {
    id: 7,
    issuer: "https://idp.example.com/application/o/nexterm/",
    clientId: "nexterm-client",
    clientSecret: "secret",
    redirectUri: "https://nexterm.example.com/api/auth/oidc/callback",
};

test("normalizes blank endpoint overrides to null", () => {
    assert.equal(normalizeProviderData({ endSessionEndpoint: "   " }).endSessionEndpoint, null);
    assert.equal(
        normalizeProviderData({ endSessionEndpoint: "  https://idp.example.com/logout  " }).endSessionEndpoint,
        "https://idp.example.com/logout",
    );
});

test("provider validation only accepts HTTP end-session endpoint overrides", () => {
    assert.equal(
        oidcProviderUpdateValidation.validate({ endSessionEndpoint: "https://idp.example.com/logout" }).error,
        undefined,
    );
    assert.match(
        oidcProviderUpdateValidation.validate({ endSessionEndpoint: "javascript:alert(document.domain)" }).error.message,
        /scheme matching/,
    );
});

test("derives the post-logout callback from the configured login callback", () => {
    assert.equal(
        getPostLogoutRedirectUri(provider.redirectUri),
        "https://nexterm.example.com/api/auth/oidc/logout/callback",
    );
});

test("derives the post-logout callback when the login callback has a trailing slash", () => {
    assert.equal(
        getPostLogoutRedirectUri("https://nexterm.example.com/api/auth/oidc/callback///"),
        "https://nexterm.example.com/api/auth/oidc/logout/callback",
    );
});

test("preserves a reverse-proxy path prefix in the post-logout callback", () => {
    assert.equal(
        getPostLogoutRedirectUri("https://example.com/nexterm/api/auth/oidc/callback"),
        "https://example.com/nexterm/api/auth/oidc/logout/callback",
    );
});

test("rejects non-HTTP callback URLs", () => {
    assert.throws(
        () => getPostLogoutRedirectUri("javascript:alert(document.domain)"),
        /must use HTTP or HTTPS/,
    );
});

test("uses the administrator endpoint override without discovery", async () => {
    let discoveryCalled = false;
    const url = new URL(await buildOIDCLogoutUrl(
        { ...provider, endSessionEndpoint: "https://idp.example.com/logout?source=nexterm" },
        "id-token",
        {
            discovery: async () => {
                discoveryCalled = true;
                throw new Error("discovery should not run");
            },
        },
    ));

    assert.equal(discoveryCalled, false);
    assert.equal(url.origin + url.pathname, "https://idp.example.com/logout");
    assert.equal(url.searchParams.get("source"), "nexterm");
    assert.equal(url.searchParams.get("client_id"), provider.clientId);
    assert.equal(url.searchParams.get("id_token_hint"), "id-token");
    assert.equal(
        url.searchParams.get("post_logout_redirect_uri"),
        "https://nexterm.example.com/api/auth/oidc/logout/callback",
    );
});

test("rejects a non-HTTP administrator endpoint override", async () => {
    await assert.rejects(
        buildOIDCLogoutUrl(
            { ...provider, endSessionEndpoint: "javascript:alert(document.domain)//" },
            "id-token",
        ),
        /must use HTTP or HTTPS/,
    );
});

test("uses the discovered end-session endpoint and passes logout parameters", async () => {
    let receivedParameters;
    const configuration = {
        serverMetadata: () => ({ end_session_endpoint: "https://idp.example.com/discovered-logout" }),
    };

    const logoutUrl = await buildOIDCLogoutUrl(provider, "id-token", {
        discovery: async (issuer, clientId, clientSecret) => {
            assert.equal(issuer.href, provider.issuer);
            assert.equal(clientId, provider.clientId);
            assert.equal(clientSecret, provider.clientSecret);
            return configuration;
        },
        buildEndSessionUrl: (config, parameters) => {
            assert.equal(config, configuration);
            receivedParameters = parameters;
            return new URL("https://idp.example.com/discovered-logout");
        },
    });

    assert.equal(logoutUrl, "https://idp.example.com/discovered-logout");
    assert.deepEqual(receivedParameters, {
        client_id: provider.clientId,
        id_token_hint: "id-token",
        post_logout_redirect_uri: "https://nexterm.example.com/api/auth/oidc/logout/callback",
    });
});

test("rejects a non-HTTP discovered end-session endpoint", async () => {
    const configuration = {
        serverMetadata: () => ({ end_session_endpoint: "javascript:alert(document.domain)//" }),
    };

    await assert.rejects(
        buildOIDCLogoutUrl(provider, "id-token", {
            discovery: async () => configuration,
            buildEndSessionUrl: () => new URL("javascript:alert(document.domain)//"),
        }),
        /must use HTTP or HTTPS/,
    );
});

test("reports a missing discovered endpoint to the sanitized fallback path", async () => {
    await assert.rejects(
        buildOIDCLogoutUrl(provider, "id-token", {
            discovery: async () => ({ serverMetadata: () => ({}) }),
            buildEndSessionUrl: () => {
                throw new Error("builder should not run");
            },
        }),
        /end-session endpoint/,
    );
});

test("builds encrypted OIDC session fields without exposing the ID token", () => {
    const context = createOIDCSessionContext(7, "plain-id-token", value => {
        assert.equal(value, "plain-id-token");
        return { encrypted: "ciphertext", iv: "iv", authTag: "tag" };
    });

    assert.deepEqual(context, {
        oidcProviderId: 7,
        oidcIdTokenEncrypted: "ciphertext",
        oidcIdTokenIV: "iv",
        oidcIdTokenAuthTag: "tag",
    });
    assert.equal(JSON.stringify(context).includes("plain-id-token"), false);
});

test("completes local session deletion before remote logout failure", async () => {
    const events = [];
    const result = await logoutWithDependencies("session-token", {
        findSession: async () => ({ id: 3, accountId: 4, oidcProviderId: 7 }),
        logLogout: () => events.push("log"),
        destroySession: async () => events.push("destroy"),
        removeSessionTerminals: () => events.push("disconnect"),
        broadcastLogout: () => events.push("broadcast"),
        createOIDCLogoutUrl: async () => {
            events.push("remote");
            throw new Error("sensitive provider failure");
        },
        warnOIDCLogout: providerId => events.push("warn:" + providerId),
    });

    assert.deepEqual(result, { message: "Your session got deleted successfully" });
    assert.deepEqual(events, ["log", "destroy", "disconnect", "broadcast", "remote", "warn:7"]);
});

test("closes the state socket before slow terminal teardown finishes", async () => {
    const events = [];
    let finishTeardown;
    let settled = false;

    const result = logoutWithDependencies("session-token", {
        findSession: async () => ({ id: 3, accountId: 4 }),
        logLogout: () => {},
        destroySession: async () => events.push("destroy"),
        removeSessionTerminals: () => new Promise(resolve => {
            finishTeardown = () => {
                events.push("disconnect");
                resolve();
            };
        }),
        broadcastLogout: () => events.push("broadcast"),
        createOIDCLogoutUrl: async () => null,
        warnOIDCLogout: () => {},
    });
    result.then(() => { settled = true; });

    await new Promise(resolve => setImmediate(resolve));
    assert.deepEqual(events, ["destroy", "broadcast"]);
    assert.equal(settled, false);

    finishTeardown();
    await result;
    assert.deepEqual(events, ["destroy", "broadcast", "disconnect"]);
});

test("completes logout when terminal teardown rejects", async () => {
    const warnings = [];
    const result = await logoutWithDependencies("session-token", {
        findSession: async () => ({ id: 3, accountId: 4 }),
        logLogout: () => {},
        destroySession: async () => {},
        removeSessionTerminals: async () => { throw new Error("teardown failed"); },
        warnSessionTeardown: (sessionId, error) => warnings.push([sessionId, error.message]),
        broadcastLogout: () => {},
        createOIDCLogoutUrl: async () => null,
        warnOIDCLogout: () => {},
    });

    assert.deepEqual(result, { message: "Your session got deleted successfully" });
    assert.deepEqual(warnings, [[3, "teardown failed"]]);
});

test("reports every failed logout teardown step", async () => {
    const warnings = [];
    const result = await logoutWithDependencies("session-token", {
        findSession: async () => ({ id: 3, accountId: 4 }),
        logLogout: () => {},
        destroySession: async () => {},
        removeSessionTerminals: async () => {},
        broadcastLogout: async () => { throw new Error("broadcast failed"); },
        warnSessionTeardown: (sessionId, error) => warnings.push([sessionId, error.message]),
        createOIDCLogoutUrl: async () => null,
        warnOIDCLogout: () => {},
    });

    assert.deepEqual(result, { message: "Your session got deleted successfully" });
    assert.deepEqual(warnings, [[3, "broadcast failed"]]);
});

test("disconnects joined organization viewers during logout", async () => {
    const events = [];
    const result = await logoutWithDependencies("session-token", {
        findSession: async () => ({ id: 3, accountId: 4 }),
        logLogout: () => {},
        destroySession: async () => {},
        removeSessionTerminals: async () => events.push("terminals"),
        broadcastLogout: async () => events.push("broadcast"),
        disconnectSessionViewers: async sessionId => events.push(["viewers", sessionId]),
        forgetSessionActivity: sessionId => events.push(["forget", sessionId]),
        createOIDCLogoutUrl: async () => null,
        warnOIDCLogout: () => {},
    });

    assert.deepEqual(result, { message: "Your session got deleted successfully" });
    assert.deepEqual(events, ["terminals", "broadcast", ["viewers", 3], ["forget", 3]]);
});

test("returns the remote logout URL after local cleanup", async () => {
    const result = await logoutWithDependencies("session-token", {
        findSession: async () => ({ id: 3, accountId: 4, oidcProviderId: 7 }),
        logLogout: () => {},
        destroySession: async () => {},
        removeSessionTerminals: () => {},
        broadcastLogout: () => {},
        createOIDCLogoutUrl: async () => "https://idp.example.com/logout",
        warnOIDCLogout: () => {},
    });

    assert.equal(result.logoutUrl, "https://idp.example.com/logout");
});
