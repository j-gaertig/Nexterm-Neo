const AccountAccessPolicy = require("../models/AccountAccessPolicy");
const logger = require("./logger");
const match = require("./accessPolicyMatch");

const DEFAULT_POLICY = Object.freeze({
    ipMode: "disabled",
    ipRules: [],
    engineMode: "disabled",
    engineIds: [],
});

const getAccessPolicy = async (accountId) => {
    try {
        const row = await AccountAccessPolicy.findOne({ where: { accountId } });
        if (!row) return { ...DEFAULT_POLICY };
        return {
            ipMode: match.MODES.includes(row.ipMode) ? row.ipMode : "disabled",
            ipRules: Array.isArray(row.ipRules) ? row.ipRules : [],
            engineMode: match.MODES.includes(row.engineMode) ? row.engineMode : "disabled",
            engineIds: Array.isArray(row.engineIds) ? row.engineIds : [],
        };
    } catch (error) {
        logger.error("Failed to load account access policy", { accountId, error: error.message });
        return { ...DEFAULT_POLICY };
    }
};

const setAccessPolicy = async (accountId, input) => {
    const validationError = match.validatePolicyInput(input);
    if (validationError) return { code: 400, message: validationError };
    const normalized = match.normalizePolicyInput(input);
    const [row, created] = await AccountAccessPolicy.findOrCreate({
        where: { accountId },
        defaults: { accountId, ...normalized },
    });
    if (!created) await AccountAccessPolicy.update(normalized, { where: { accountId } });
    return { ...normalized };
};

const checkEntryAccessPolicy = async (accountId, entry, integration = null) => {
    const policy = await getAccessPolicy(accountId);
    return { ...match.checkEntryAgainstPolicy(policy, entry, integration), policy };
};

module.exports = {
    MODES: match.MODES,
    DEFAULT_POLICY,
    ...match,
    getAccessPolicy,
    setAccessPolicy,
    checkEntryAccessPolicy,
};
