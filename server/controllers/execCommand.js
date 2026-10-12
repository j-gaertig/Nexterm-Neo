const Entry = require("../models/Entry");
const { resolveIdentity } = require("../utils/identityResolver");
const { getIdentityCredentials } = require("./identity");
const { buildSSHParams, resolveJumpHosts } = require("../lib/ConnectionService");
const { validateEntryAccess } = require("./entry");
const { checkEntryAccessPolicy } = require("../utils/accessPolicy");
const Integration = require("../models/Integration");
const controlPlane = require("../lib/controlPlane/ControlPlaneServer");

const execCommand = async (accountId, entryId, identityId, command) => {
    const entry = await Entry.findByPk(entryId);
    if (!entry) {
        return { code: 404, message: "Entry not found" };
    }

    const accessResult = await validateEntryAccess(accountId, entry);
    if (!accessResult.valid) {
        return { code: 403, message: "Access denied" };
    }

    const integration = entry.integrationId ? await Integration.findByPk(entry.integrationId) : null;
    const policyCheck = await checkEntryAccessPolicy(accountId, entry, integration);
    if (!policyCheck.allowed) {
        return {
            code: 403,
            message: policyCheck.reason === "engine"
                ? "Access denied: this server must be reached through a different engine"
                : "Access denied: this server IP is not allowed for your account",
        };
    }

    if (entry.config?.protocol !== "ssh") {
        return { code: 400, message: "Command execution is only supported for SSH entries" };
    }

    if (!controlPlane.hasEngine()) {
        return { code: 503, message: "No engine connected" };
    }

    const result = await resolveIdentity(entry, identityId, null, accountId);
    const identity = result?.identity !== undefined ? result.identity : result;

    if (result.accessDenied) {
        return { code: 403, message: "You don't have access to this identity" };
    }

    if (!identity || !identity.id) {
        return { code: 400, message: "No identity available for this entry" };
    }

    const credentials = await getIdentityCredentials(identity.id);
    const params = buildSSHParams(identity, credentials);
    const host = entry.config?.ip;
    const port = entry.config?.port || 22;

    if (!host) {
        return { code: 400, message: "Missing host configuration" };
    }

    const jumpHosts = await resolveJumpHosts(entry);
    const execResult = await controlPlane.execCommand(host, port, params, command, jumpHosts);

    return {
        success: execResult.success,
        stdout: execResult.stdout || "",
        stderr: execResult.stderr || "",
        exitCode: execResult.exitCode ?? (execResult.success ? 0 : 1),
        errorMessage: execResult.errorMessage || null,
    };
};

module.exports = { execCommand };
