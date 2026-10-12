const test = require("node:test");
const assert = require("node:assert/strict");

const match = require("../utils/accessPolicyMatch");

test("CIDR rules match contained IPv4 addresses only", () => {
    assert.equal(match.ruleMatchesTarget("10.0.0.0/24", "10.0.0.5"), true);
    assert.equal(match.ruleMatchesTarget("10.0.0.0/24", "10.0.1.5"), false);
    assert.equal(match.ruleMatchesTarget("10.0.0.5/32", "10.0.0.5"), true);
    assert.equal(match.ruleMatchesTarget("0.0.0.0/0", "192.168.1.1"), true);
});

test("exact and wildcard rules match case-insensitively", () => {
    assert.equal(match.ruleMatchesTarget("192.168.1.1", "192.168.1.1"), true);
    assert.equal(match.ruleMatchesTarget("192.168.1.1", "192.168.1.2"), false);
    assert.equal(match.ruleMatchesTarget("DB.Example.COM", "db.example.com"), true);
    assert.equal(match.ruleMatchesTarget("192.168.*", "192.168.5.5"), true);
    assert.equal(match.ruleMatchesTarget("db-*.example.com", "db-01.example.com"), true);
    assert.equal(match.ruleMatchesTarget("db-*.example.com", "web-01.example.com"), false);
});

test("rule validation rejects CIDR and character abuse", () => {
    assert.equal(match.isValidRule("10.0.0.0/24"), true);
    assert.equal(match.isValidRule("10.0.0.0/33"), false);
    assert.equal(match.isValidRule("*.example.com"), true);
    assert.equal(match.isValidRule("10.0.0.1; rm -rf"), false);
    assert.equal(match.isValidRule(""), false);
});

test("empty whitelist denies everything, blacklist allows the rest", () => {
    assert.equal(match.isIpAllowedByPolicy({ ipMode: "whitelist", ipRules: [] }, "1.2.3.4"), false);
    assert.equal(match.isIpAllowedByPolicy({ ipMode: "whitelist", ipRules: ["10.0.0.0/24"] }, "10.0.0.7"), true);
    assert.equal(match.isIpAllowedByPolicy({ ipMode: "whitelist", ipRules: ["10.0.0.0/24"] }, "10.0.1.7"), false);
    assert.equal(match.isIpAllowedByPolicy({ ipMode: "blacklist", ipRules: ["10.0.0.5"] }, "10.0.0.5"), false);
    assert.equal(match.isIpAllowedByPolicy({ ipMode: "blacklist", ipRules: ["10.0.0.5"] }, "10.0.0.6"), true);
    assert.equal(match.isIpAllowedByPolicy({ ipMode: "disabled", ipRules: ["10.0.0.5"] }, "10.0.0.5"), true);
});

test("engine whitelist/blacklist honour the default (null) engine", () => {
    assert.equal(match.isEngineAllowedByPolicy({ engineMode: "whitelist", engineIds: [2] }, 2), true);
    assert.equal(match.isEngineAllowedByPolicy({ engineMode: "whitelist", engineIds: [2] }, 3), false);
    assert.equal(match.isEngineAllowedByPolicy({ engineMode: "blacklist", engineIds: [2] }, 2), false);
    assert.equal(match.isEngineAllowedByPolicy({ engineMode: "blacklist", engineIds: [2] }, 3), true);
    assert.equal(match.isEngineAllowedByPolicy({ engineMode: "whitelist", engineIds: [null] }, null), true);
    assert.equal(match.isEngineAllowedByPolicy({ engineMode: "whitelist", engineIds: [2] }, null), false);
});

test("entry verdict combines IP and engine checks", () => {
    const blocked = match.checkEntryAgainstPolicy(
        { ipMode: "blacklist", ipRules: ["10.0.0.1"], engineMode: "disabled", engineIds: [] },
        { config: { ip: "10.0.0.1", engineId: 1 } });
    assert.equal(blocked.allowed, false);
    assert.equal(blocked.reason, "ip");

    const engineBlocked = match.checkEntryAgainstPolicy(
        { ipMode: "disabled", ipRules: [], engineMode: "whitelist", engineIds: [2] },
        { config: { ip: "10.0.0.9", engineId: 3 } });
    assert.equal(engineBlocked.allowed, false);
    assert.equal(engineBlocked.reason, "engine");

    const allowed = match.checkEntryAgainstPolicy(
        { ipMode: "whitelist", ipRules: ["10.0.0.0/24"], engineMode: "disabled", engineIds: [] },
        { config: { ip: "10.0.0.9", engineId: 3 } });
    assert.equal(allowed.allowed, true);
});

test("entry list filtering keeps only allowed entries", () => {
    const kept = match.filterEntriesByPolicy(
        { ipMode: "whitelist", ipRules: ["10.0.0.1"], engineMode: "disabled", engineIds: [] },
        [{ id: 1, config: { ip: "10.0.0.1" } }, { id: 2, config: { ip: "10.0.0.2" } }]);
    assert.deepEqual(kept.map((e) => e.id), [1]);
});

test("policy input validation reports bad modes and rules", () => {
    assert.equal(match.validatePolicyInput({ ipMode: "sometimes" }) !== null, true);
    assert.equal(match.validatePolicyInput({ ipRules: ["@@@"] }) !== null, true);
    assert.equal(match.validatePolicyInput({ engineIds: ["abc"] }) !== null, true);
    assert.equal(match.validatePolicyInput({ ipMode: "whitelist", ipRules: ["10.0.0.0/24"] }), null);
});

test("multiple policies combine: every policy must allow", () => {
    const entry = { config: { ip: "10.0.0.5", engineId: 1 } };
    const open = { ipMode: "disabled", ipRules: [], engineMode: "disabled", engineIds: [] };
    const ipBlacklist = { ipMode: "blacklist", ipRules: ["10.0.0.5"], engineMode: "disabled", engineIds: [] };
    const engineWhitelist = { ipMode: "disabled", ipRules: [], engineMode: "whitelist", engineIds: [1] };

    assert.equal(match.checkPoliciesAgainstEntry([], entry).allowed, true);
    assert.equal(match.checkPoliciesAgainstEntry([open, open], entry).allowed, true);
    assert.equal(match.checkPoliciesAgainstEntry([open, engineWhitelist], entry).allowed, true);

    const deniedByIp = match.checkPoliciesAgainstEntry([open, engineWhitelist, ipBlacklist], entry);
    assert.equal(deniedByIp.allowed, false);
    assert.equal(deniedByIp.reason, "ip");

    const deniedByEngine = match.checkPoliciesAgainstEntry(
        [open, { ipMode: "disabled", ipRules: [], engineMode: "whitelist", engineIds: [2] }], entry);
    assert.equal(deniedByEngine.allowed, false);
    assert.equal(deniedByEngine.reason, "engine");
});
