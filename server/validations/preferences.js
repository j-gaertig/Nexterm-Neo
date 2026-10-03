const Joi = require('joi');

const terminalSchema = Joi.object({
    fontFamily: Joi.string().max(200),
    fontSize: Joi.number().integer().min(10).max(32),
    cursorStyle: Joi.string().valid('block', 'underline', 'bar'),
    cursorBlink: Joi.boolean(),
    smartCopyPaste: Joi.boolean(),
    autoReconnect: Joi.boolean(),
    copyPasteBehavior: Joi.string().valid('none', 'smart', 'keyboard', 'mouse', 'mouseKeyboard'),
    passwordPromptDetection: Joi.boolean(),
    passwordPromptPhrases: Joi.array().items(Joi.string().trim().min(2).max(100)).max(10000).custom((value, helpers) => {
        const seen = new Set();
        for (const item of value || []) {
            if (Array.from(item).length > 100) return helpers.error("terminal.passwordPromptPhrases.tooLong");
            const key = typeof item.normalize === "function" ? item.normalize("NFKC").toLowerCase() : String(item).toLowerCase();
            if (seen.has(key)) return helpers.error("terminal.passwordPromptPhrases.duplicate");
            seen.add(key);
        }
        return value;
    }).messages({
        "terminal.passwordPromptPhrases.duplicate": "Duplicate phrases are not allowed.",
        "terminal.passwordPromptPhrases.tooLong": "Maximum 100 characters per phrase."
    }),
    passwordPromptPattern: Joi.any().strip(),
    theme: Joi.string().max(50),
}).unknown(false);

const themeSchema = Joi.object({
    mode: Joi.string().valid('light', 'dark', 'auto', 'oled'),
    accentColor: Joi.string().pattern(/^#[0-9A-Fa-f]{6}$/),
    uiScale: Joi.number().min(0.7).max(1.3),
}).unknown(false);

const filesSchema = Joi.object({
    showThumbnails: Joi.boolean(),
    defaultViewMode: Joi.string().valid('list', 'grid'),
    showHiddenFiles: Joi.boolean(),
    confirmBeforeDelete: Joi.boolean(),
    dragDropAction: Joi.string().valid('ask', 'copy', 'move'),
}).unknown(false);

const generalSchema = Joi.object({
    language: Joi.string().max(10),
    sidebarCollapsed: Joi.boolean(),
}).unknown(false);

module.exports.preferencesValidation = Joi.object({
    terminal: terminalSchema,
    theme: themeSchema,
    files: filesSchema,
    general: generalSchema,
}).unknown(false);
