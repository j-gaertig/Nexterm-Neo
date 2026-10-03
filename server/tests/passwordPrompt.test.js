const test = require("node:test");
const assert = require("node:assert/strict");
const { checkSudoPrompt } = require("../utils/scriptUtils.js");
const { preferencesValidation } = require("../validations/preferences.js");

let passwordPrompt;

test.before(async () => {
    passwordPrompt = await import("../../client/src/common/utils/passwordPrompt.js");
});

test("detects English sudo and password prompts", () => {
    assert.equal(passwordPrompt.isPasswordPrompt("[sudo] password for alice:"), true);
    assert.equal(passwordPrompt.isPasswordPrompt("Password:"), true);
    assert.equal(passwordPrompt.isPasswordPrompt("Enter passphrase for key '/home/u/.ssh/id_rsa':"), true);
});

test("detects German CachyOS sudo prompt", () => {
    assert.equal(passwordPrompt.isPasswordPrompt("[sudo] Passwort für geekom:"), true);
    assert.equal(passwordPrompt.isPasswordPrompt("Passwort:"), true);
    assert.equal(passwordPrompt.isPasswordPrompt("Neues Passwort:"), true);
    assert.equal(passwordPrompt.isPasswordPrompt("Kennwort:"), true);
});

test("detects additional locales", () => {
    assert.equal(passwordPrompt.isPasswordPrompt("Contraseña:"), true);
    assert.equal(passwordPrompt.isPasswordPrompt("Mot de passe :"), true);
    assert.equal(passwordPrompt.isPasswordPrompt("Senha:"), true);
    assert.equal(passwordPrompt.isPasswordPrompt("Wachtwoord:"), true);
});

test("rejects non-password lines", () => {
    assert.equal(passwordPrompt.isPasswordPrompt("Last login: Tue Sep 30"), false);
    assert.equal(passwordPrompt.isPasswordPrompt("Enter command:"), false);
    assert.equal(passwordPrompt.isPasswordPrompt(""), false);
    assert.equal(passwordPrompt.isPasswordPrompt("$ echo password"), false);
});

test("strips ANSI noise and handles chunked prompts", () => {
    assert.equal(passwordPrompt.isPasswordPrompt("\x1b[38;2;255;0;0m[sudo] Passwort für geekom:\x1b[0m"), true);
    assert.equal(passwordPrompt.isPasswordPrompt("\x1b]8;;https://example.com\x1b\\Password:\x1b]8;;\x1b\\"), true);
    const first = passwordPrompt.updatePromptLine("", "[sudo] Passw");
    const full = passwordPrompt.updatePromptLine(first, "ort für geekom:");
    assert.equal(passwordPrompt.isPasswordPrompt(full), true);
});

test("reads prompt from xterm buffer when available", () => {
    const term = {
        buffer: {
            active: {
                baseY: 100,
                cursorY: 5,
                length: 106,
                getLine: (y) => {
                    if (y === 105) return { isWrapped: false, translateToString: () => "[sudo] Passwort für geekom:" };
                    return { isWrapped: false, translateToString: () => "" };
                },
            },
        },
    };
    assert.equal(passwordPrompt.readTerminalPromptLine(term), "[sudo] Passwort für geekom:");
    assert.equal(passwordPrompt.isPasswordPrompt(passwordPrompt.readTerminalPromptLine(term)), true);
});

test("handles multiline input", () => {
    assert.equal(passwordPrompt.isPasswordPrompt("Last login: Tue\nPassword:"), true);
    assert.equal(passwordPrompt.isPasswordPrompt("Last login: Tue\nBitte Geheimcode eingeben!", ["geheimcode"]), true);
    assert.equal(passwordPrompt.isPasswordPrompt("Bitte Geheimcode eingeben!\nLast login: Tue", ["geheimcode"]), false);
});

test("supports custom phrases in addition to built-in detection", () => {
    assert.equal(passwordPrompt.isPasswordPrompt("Bitte Geheimcode eingeben!", ["Geheimcode"]), true);
    assert.equal(passwordPrompt.isPasswordPrompt("BITTE GEHEIMCODE EINGEBEN!", ["geheimcode"]), true);
    assert.equal(passwordPrompt.isPasswordPrompt("Password:", ["Geheimcode"]), true);
    assert.equal(passwordPrompt.isPasswordPrompt("Password:", []), true);
    assert.equal(passwordPrompt.isPasswordPrompt("hello world", ["Geheimcode"]), false);
    assert.equal(passwordPrompt.isPasswordPrompt("hello world", []), false);
    assert.equal(passwordPrompt.isPasswordPrompt("hello world", ["  "]), false);
    assert.equal(passwordPrompt.isPasswordPrompt("hello world", ["x".repeat(101)]), false);
    assert.equal(passwordPrompt.isPasswordPrompt("a", ["a"]), false);
});

test("matches phrases case-insensitively after NFKC normalization", () => {
    assert.equal(passwordPrompt.isPasswordPrompt("Ｂｉｔｔｅ Ｇｅｈｅｉｍｃｏｄｅ eingeben!", ["geheimcode"]), true);
    assert.equal(passwordPrompt.isPasswordPrompt("Bitte Geheimcode eingeben!", ["Ｇｅｈｅｉｍｃｏｄｅ"]), true);
});

test("only searches the last 256 characters", () => {
    assert.equal(passwordPrompt.isPasswordPrompt(`Geheimcode${"x".repeat(300)}`, ["geheimcode"]), false);
    assert.equal(passwordPrompt.isPasswordPrompt(`${"x".repeat(300)}Geheimcode`, ["geheimcode"]), true);
});

test("supports precompiled phrase lists", () => {
    const compiled = passwordPrompt.compilePasswordPhrases(["Geheimcode"]);
    assert.deepEqual(compiled, ["geheimcode"]);
    assert.equal(passwordPrompt.isPasswordPromptWithCompiled("Bitte Geheimcode eingeben!", compiled), true);
    assert.equal(passwordPrompt.isPasswordPromptWithCompiled("hello world", compiled), false);
    assert.equal(passwordPrompt.isPasswordPromptWithCompiled("Password:", []), true);
    assert.equal(passwordPrompt.isPasswordPromptWithCompiled("hello world", []), false);
});

test("normalizes phrase lists", () => {
    assert.deepEqual(passwordPrompt.normalizePasswordPhrases(["  Geheimcode  ", "geheimcode", "", "a", 42, "x".repeat(101), "\u200b\u200b"]), ["Geheimcode"]);
    assert.deepEqual(passwordPrompt.normalizePasswordPhrases("Geheimcode"), []);
    assert.deepEqual(passwordPrompt.compilePasswordPhrases(["Geheimcode"]), ["geheimcode"]);
    const many = Array.from({ length: 10001 }, (_, i) => `phrase-${i}`);
    assert.equal(passwordPrompt.normalizePasswordPhrases(many).length, 10000);
});

test("validates password phrases preference", () => {
    const ok = preferencesValidation.validate({ terminal: { passwordPromptPhrases: ["Geheimcode", "otp-code"] } });
    assert.equal(ok.error, undefined);
    const duplicate = preferencesValidation.validate({ terminal: { passwordPromptPhrases: ["Geheimcode", "geheimcode"] } });
    assert.ok(duplicate.error);
    const tooShort = preferencesValidation.validate({ terminal: { passwordPromptPhrases: ["a"] } });
    assert.ok(tooShort.error);
    const tooLong = preferencesValidation.validate({ terminal: { passwordPromptPhrases: ["x".repeat(101)] } });
    assert.ok(tooLong.error);
    const legacy = preferencesValidation.validate({ terminal: { passwordPromptPattern: "Passwort.*:" } });
    assert.equal(legacy.error, undefined);
    assert.equal(legacy.value.terminal.passwordPromptPattern, undefined);
});

test("server sudo check covers German prompts", () => {
    assert.ok(checkSudoPrompt("[sudo] Passwort für geekom:"));
    assert.equal(checkSudoPrompt("[sudo] Passwort für geekom:").variable, "SUDO_PASSWORD");
    assert.ok(checkSudoPrompt("[sudo] password for alice:"));
    assert.ok(checkSudoPrompt("Password:"));
    assert.ok(checkSudoPrompt("Passwort:"));
    assert.ok(checkSudoPrompt("Password："));
    assert.ok(checkSudoPrompt("Passwort :"));
    assert.ok(checkSudoPrompt("sudo: a password is required"));
    assert.equal(checkSudoPrompt("hello world"), null);
});
