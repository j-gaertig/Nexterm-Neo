const AccountAccessPolicy = require("../models/AccountAccessPolicy");
const GroupAccessPolicy = require("../models/GroupAccessPolicy");
const GroupMember = require("../models/GroupMember");
const PermissionGroup = require("../models/PermissionGroup");
const logger = require("./logger");
const match = require("./accessPolicyMatch");

const DEFAULT_POLICY = Object.freeze({
    ipMode: "disabled",
    ipRules: [],
    engineMode: "disabled",
    engineIds: [],
});

const toPolicyView = (row) => ({
    ipMode: match.MODES.includes(row?.ipMode) ? row.ipMode : "disabled",
    ipRules: Array.isArray(row?.ipRules) ? row.ipRules : [],
    engineMode: match.MODES.includes(row?.engineMode) ? row.engineMode : "disabled",
    engineIds: Array.isArray(row?.engineIds) ? row.engineIds : [],
});

const getAccessPolicy = async (accountId) => {
    try {
        const row = await AccountAccessPolicy.findOne({ where: { accountId } });
        if (!row) return { ...DEFAULT_POLICY };
        return toPolicyView(row);
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

const getGroupAccessPolicy = async (groupId) => {
    try {
        const row = await GroupAccessPolicy.findOne({ where: { groupId } });
        if (!row) return { ...DEFAULT_POLICY };
        return toPolicyView(row);
    } catch (error) {
        logger.error("Failed to load group access policy", { groupId, error: error.message });
        return { ...DEFAULT_POLICY };
    }
};

const setGroupAccessPolicy = async (groupId, input) => {
    const validationError = match.validatePolicyInput(input);
    if (validationError) return { code: 400, message: validationError };
    const normalized = match.normalizePolicyInput(input);
    const [row, created] = await GroupAccessPolicy.findOrCreate({
        where: { groupId },
        defaults: { groupId, ...normalized },
    });
    if (!created) await GroupAccessPolicy.update(normalized, { where: { groupId } });
    return { ...normalized };
};

const getGroupsForAccount = async (accountId) => {
    const [memberships, groups] = await Promise.all([
        GroupMember.findAll({ where: { accountId } }),
        PermissionGroup.findAll(),
    ]);
    const memberGroupIds = new Set(memberships.map((m) => m.groupId));
    return groups.filter((g) => memberGroupIds.has(g.id) || g.isDefault);
};

// Personal policy first, then role policies (assigned + default groups).
// Enforcement requires every applicable policy to allow the entry.
const getEffectivePolicies = async (accountId) => {
    try {
        const [personal, groups] = await Promise.all([
            getAccessPolicy(accountId),
            getGroupsForAccount(accountId),
        ]);
        const policies = [personal];
        if (groups.length) {
            const { Op } = require("sequelize");
            const rows = await GroupAccessPolicy.findAll({
                where: { groupId: { [Op.in]: groups.map((g) => g.id) } },
            });
            const byGroupId = new Map(rows.map((r) => [r.groupId, toPolicyView(r)]));
            for (const group of groups) {
                const policy = byGroupId.get(group.id);
                if (policy && !match.isPolicyInactive(policy)) policies.push(policy);
            }
        }
        return policies;
    } catch (error) {
        logger.error("Failed to load effective access policies", { accountId, error: error.message });
        return [{ ...DEFAULT_POLICY }];
    }
};

const hasEffectiveRestrictions = async (accountId) => {
    const policies = await getEffectivePolicies(accountId);
    return policies.some((p) => !match.isPolicyInactive(p));
};

const checkEntryAccessPolicy = async (accountId, entry, integration = null) => {
    const policies = await getEffectivePolicies(accountId);
    return { ...match.checkPoliciesAgainstEntry(policies, entry, integration), policies };
};

module.exports = {
    MODES: match.MODES,
    DEFAULT_POLICY,
    ...match,
    getAccessPolicy,
    setAccessPolicy,
    getGroupAccessPolicy,
    setGroupAccessPolicy,
    getGroupsForAccount,
    getEffectivePolicies,
    hasEffectiveRestrictions,
    checkEntryAccessPolicy,
};
