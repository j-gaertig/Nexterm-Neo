const logoutWithDependencies = async (token, dependencies) => {
    const session = await dependencies.findSession(token);

    if (session === null)
        return { code: 204, message: "Your session token is invalid" };

    dependencies.logLogout(session.accountId);

    await dependencies.destroySession(token);

    const teardown = await Promise.allSettled([
        Promise.resolve().then(() => dependencies.removeSessionTerminals(session.id)),
        Promise.resolve().then(() => dependencies.broadcastLogout(session.id)),
        Promise.resolve().then(() => dependencies.disconnectSessionViewers?.(session.id)),
    ]);

    dependencies.forgetSessionActivity?.(session.id);

    for (const result of teardown) {
        if (result.status === "rejected") {
            dependencies.warnSessionTeardown?.(session.id, result.reason);
        }
    }

    let logoutUrl = null;
    if (session.oidcProviderId) {
        try {
            logoutUrl = await dependencies.createOIDCLogoutUrl(session);
        } catch (_) {
            dependencies.warnOIDCLogout(session.oidcProviderId);
        }
    }

    return {
        message: "Your session got deleted successfully",
        ...(logoutUrl ? { logoutUrl } : {}),
    };
};

module.exports = { logoutWithDependencies };
