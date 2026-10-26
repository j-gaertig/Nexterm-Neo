/// Pure authorization decisions shared by the session controller. Keeping the
/// checks free of Sequelize/SessionManager makes the security-sensitive cases
/// directly testable without booting the database.
const getSessionAccessError = (session, accountId) => {
    if (!session) return { code: 404, message: "Session not found" };
    if (session.accountId !== accountId) {
        return { code: 403, message: "Access denied" };
    }
    return null;
};

const getSessionShareError = (session) => {
    if (session?.configuration?.scriptId) {
        return { code: 400, message: "Script sessions cannot be shared" };
    }
    return null;
};

const getScriptConnectionError = (entry, type, scriptId) => {
    if (!scriptId) return null;
    const protocol = entry?.type === "server"
        ? entry.config?.protocol
        : entry?.type;
    if (type || protocol !== "ssh") {
        return { code: 400, message: "Scripts can only be executed on SSH connections" };
    }
    return null;
};

module.exports = {
    getSessionAccessError,
    getSessionShareError,
    getScriptConnectionError,
};
