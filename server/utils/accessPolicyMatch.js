// Pure, dependency-free helpers for account access policies (IP + engine matching).
// Kept separate so the logic is unit-testable without database/sequelize.

const MODES = ["disabled", "blacklist", "whitelist"];
const MAX_RULES = 200;
const MAX_ENGINES = 100;

const isIPv4 = (value) => {
    if (typeof value !== "string") return false;
    const parts = value.trim().split(".");
    if (parts.length !== 4) return false;
    return parts.every((p) => /^\d{1,3}$/.test(p) && Number(p) >= 0 && Number(p) <= 255);
};

const ipv4ToInt = (ip) => {
    const parts = ip.trim().split(".").map(Number);
    return ((parts[0] * 256 + parts[1]) * 256 + parts[2]) * 256 + parts[3];
};

const parseCidr = (rule) => {
    const idx = rule.lastIndexOf("/");
    if (idx === -1) return null;
    const base = rule.slice(0, idx).trim();
    const bits = Number(rule.slice(idx + 1).trim());
    if (!isIPv4(base) || !Number.isInteger(bits) || bits < 0 || bits > 32) return null;
    return { base: ipv4ToInt(base), bits };
};

const cidrMatches = (cidr, ip) => {
    if (!isIPv4(ip)) return false;
    if (cidr.bits === 0) return true;
    const shift = 32 - cidr.bits;
    return (ipv4ToInt(ip) >>> shift) === (cidr.base >>> shift);
};

const wildcardToRegExp = (rule) => {
    const escaped = rule.trim().split("*").map((p) => p.replace(/[.+?^${}()|[\]\\]/g, "\\$&")).join(".*");
    return new RegExp(`^${escaped}$`, "i");
};

const ruleMatchesTarget = (rule, target) => {
    if (!rule || !target) return false;
    const r = String(rule).trim();
    const t = String(target).trim();
    if (!r || !t) return false;
    if (r.includes("/")) {
        const cidr = parseCidr(r);
        return cidr ? cidrMatches(cidr, t) : false;
    }
    if (r.includes("*")) {
        try {
            return wildcardToRegExp(r).test(t);
        } catch {
            return false;
        }
    }
    return r.toLowerCase() === t.toLowerCase();
};

const isValidRule = (rule) => {
    if (typeof rule !== "string") return false;
    const r = rule.trim();
    if (!r || r.length > 253) return false;
    if (!/^[A-Za-z0-9.*:/_-]+$/.test(r)) return false;
    if (r.includes("/")) return parseCidr(r) !== null;
    return true;
};

const normalizePolicyInput = (input = {}) => {
    const ipMode = MODES.includes(input.ipMode) ? input.ipMode : "disabled";
    const engineMode = MODES.includes(input.engineMode) ? input.engineMode : "disabled";

    let ipRules = Array.isArray(input.ipRules) ? input.ipRules : [];
    ipRules = [...new Set(ipRules.map((r) => String(r ?? "").trim()).filter(Boolean))].slice(0, MAX_RULES);

    let engineIds = Array.isArray(input.engineIds) ? input.engineIds : [];
    engineIds = [...new Set(engineIds.map((v) => (v === null ? null : Number(v))).filter((v) => v === null || (Number.isInteger(v) && v > 0)))].slice(0, MAX_ENGINES);

    if (ipMode === "disabled") ipRules = [];
    if (engineMode === "disabled") engineIds = [];

    return { ipMode, ipRules, engineMode, engineIds };
};

const validatePolicyInput = (input = {}) => {
    if (input.ipMode !== undefined && !MODES.includes(input.ipMode))
        return 'ipMode must be one of "disabled", "blacklist" or "whitelist"';
    if (input.engineMode !== undefined && !MODES.includes(input.engineMode))
        return 'engineMode must be one of "disabled", "blacklist" or "whitelist"';
    if (input.ipRules !== undefined) {
        if (!Array.isArray(input.ipRules)) return "ipRules must be an array of strings";
        if (input.ipRules.length > MAX_RULES) return `ipRules must not exceed ${MAX_RULES} entries`;
        for (const rule of input.ipRules) {
            if (!isValidRule(rule)) return `Invalid IP rule: "${rule}". Use plain IPs/hostnames, "*" wildcards or IPv4 CIDR (e.g. 10.0.0.0/24).`;
        }
    }
    if (input.engineIds !== undefined) {
        if (!Array.isArray(input.engineIds)) return "engineIds must be an array";
        if (input.engineIds.length > MAX_ENGINES) return `engineIds must not exceed ${MAX_ENGINES} entries`;
        for (const id of input.engineIds) {
            if (id !== null && !(Number.isInteger(Number(id)) && Number(id) > 0))
                return "engineIds must contain engine ids or null (default engine)";
        }
    }
    return null;
};

const isPolicyInactive = (policy) =>
    !policy || (policy.ipMode === "disabled" && policy.engineMode === "disabled");

const isIpAllowedByPolicy = (policy, targetIp) => {
    if (!policy || policy.ipMode === "disabled") return true;
    const rules = Array.isArray(policy.ipRules) ? policy.ipRules : [];
    if (policy.ipMode === "whitelist") {
        if (!rules.length) return false;
        if (!targetIp) return false;
        return rules.some((rule) => ruleMatchesTarget(rule, targetIp));
    }
    if (!rules.length || !targetIp) return true;
    return !rules.some((rule) => ruleMatchesTarget(rule, targetIp));
};

const normalizeEngineId = (engineId) => (engineId === undefined ? null : engineId);

const isEngineAllowedByPolicy = (policy, engineId) => {
    if (!policy || policy.engineMode === "disabled") return true;
    const ids = Array.isArray(policy.engineIds) ? policy.engineIds : [];
    const current = normalizeEngineId(engineId);
    const listed = ids.some((id) => (id === null ? current === null : Number(id) === Number(current)));
    if (policy.engineMode === "whitelist") return listed;
    return !listed;
};

const getEntryTarget = (entry, integration = null) => {
    const ip = entry?.config?.ip || integration?.config?.ip || null;
    const engineId = normalizeEngineId(entry?.config?.engineId ?? null);
    return { ip, engineId };
};

const checkEntryAgainstPolicy = (policy, entry, integration = null) => {
    if (isPolicyInactive(policy)) return { allowed: true, reason: null };
    const { ip, engineId } = getEntryTarget(entry, integration);
    if (!isIpAllowedByPolicy(policy, ip)) return { allowed: false, reason: "ip", ip, engineId };
    if (!isEngineAllowedByPolicy(policy, engineId)) return { allowed: false, reason: "engine", ip, engineId };
    return { allowed: true, reason: null, ip, engineId };
};

const filterEntriesByPolicy = (policy, entries, integrationsById = new Map()) => {
    if (isPolicyInactive(policy)) return entries;
    return entries.filter((entry) => {
        const integration = entry?.integrationId ? integrationsById.get(entry.integrationId) || null : null;
        return checkEntryAgainstPolicy(policy, entry, integration).allowed;
    });
};

module.exports = {
    MODES,
    MAX_RULES,
    MAX_ENGINES,
    isIPv4,
    ipv4ToInt,
    parseCidr,
    ruleMatchesTarget,
    isValidRule,
    normalizePolicyInput,
    validatePolicyInput,
    isPolicyInactive,
    isIpAllowedByPolicy,
    isEngineAllowedByPolicy,
    normalizeEngineId,
    getEntryTarget,
    checkEntryAgainstPolicy,
    filterEntriesByPolicy,
};
