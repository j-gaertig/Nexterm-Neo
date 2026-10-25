/**
 * Terminal font helpers.
 *
 * All bundled terminal fonts are Nerd Font Mono variants. The default stack
 * deliberately starts with JetBrains Mono so every glyph used by fastfetch
 * (Powerline, Material Design icons, etc.) is available without relying on a
 * system font. Font metrics are monospace, therefore falling through to the
 * other bundled families only affects glyph coverage, not cell widths.
 */

export const NERD_FONT_STACK =
    "'JetBrains Mono', 'Fira Code', 'Hack', 'Source Code Pro', 'Inconsolata', 'Ubuntu Mono', 'Roboto Mono', monospace";

export const TERMINAL_FONT_OPTIONS = [
    { name: "JetBrains Mono", family: "JetBrains Mono" },
    { name: "Fira Code", family: "Fira Code" },
    { name: "Source Code Pro", family: "Source Code Pro" },
    { name: "Inconsolata", family: "Inconsolata" },
    { name: "Ubuntu Mono", family: "Ubuntu Mono" },
    { name: "Roboto Mono", family: "Roboto Mono" },
    { name: "Hack", family: "Hack" },
];

const fontLoads = new Map();

const firstFontFamily = (fontFamily) => {
    if (typeof fontFamily !== "string") return null;
    const first = fontFamily.split(",")[0]?.trim();
    if (!first) return null;
    const unquoted = first.replace(/^(['"])(.*)\1$/, "$2").trim();
    if (!unquoted) return null;
    if (["monospace", "serif", "sans-serif", "cursive", "fantasy", "system-ui", "ui-monospace"].includes(unquoted.toLowerCase())) {
        return null;
    }
    return unquoted;
};

const fontKey = (family, fontSize) => `${family}|${fontSize}`;

/**
 * Wait until the first family in a terminal font stack has loaded.
 *
 * xterm.js measures the cell box when the terminal is opened. Opening before
 * the font has loaded leaves every cell at the fallback metrics, which shifts
 * box-drawing characters and breaks cursor/password-hint positioning. Callers
 * that open a terminal should await this first.
 *
 * The wait is bounded: a missing/blocked font must never keep a session from
 * opening. `document.fonts` is unavailable in some test environments.
 */
export const ensureTerminalFontsLoaded = async (fontFamily, fontSize = 16) => {
    if (typeof document === "undefined" || !document.fonts?.load) return false;
    const family = firstFontFamily(fontFamily);
    if (!family) return false;

    const key = fontKey(family, fontSize);
    if (!fontLoads.has(key)) {
        const load = Promise.resolve()
            .then(() => document.fonts.load(`${fontSize}px "${family}"`, "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"))
            .catch(() => []);
        fontLoads.set(key, load);
    }

    const timeout = new Promise((resolve) => setTimeout(resolve, 4000));
    try {
        const faces = await Promise.race([fontLoads.get(key), timeout]);
        if (Array.isArray(faces) && faces.length === 0) {
            // A failed/unknown family still resolves; don't cache the negative
            // result forever so a later stylesheet load can succeed.
            fontLoads.delete(key);
        }
        return Array.isArray(faces) && faces.length > 0;
    } catch {
        return false;
    }
};

/** Start loading the default terminal font as soon as the app boots. */
export const preloadTerminalFonts = () => {
    void ensureTerminalFontsLoaded(NERD_FONT_STACK, 16);
};

export const getFirstTerminalFontFamily = firstFontFamily;
