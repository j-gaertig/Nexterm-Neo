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
    assert.equal(passwordPrompt.isPasswordPrompt("hello world"), false);
});

test("strips legacy phrase preferences", () => {
    const legacy = preferencesValidation.validate({ terminal: { passwordPromptPhrases: ["Geheimcode"], passwordPromptPattern: "Passwort.*:" } });
    assert.equal(legacy.error, undefined);
    assert.equal(legacy.value.terminal.passwordPromptPhrases, undefined);
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
