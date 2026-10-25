/**
 * Terminal font helpers.
 *
 * xterm measures the cell box while the terminal is opened. If the selected
 * webfont has not loaded yet, it keeps the fallback monospace metrics for the
 * lifetime of the terminal, which makes rows taller and leaves gaps around
 * block and box drawing glyphs. Callers should wait for this helper before
 * opening a terminal.
 */

export const DEFAULT_TERMINAL_FONT = "'JetBrains Mono', monospace";

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
 * The wait is bounded so a missing or blocked font never keeps a terminal from
 * opening. Failed loads are not cached, which allows a later retry after the
 * font stylesheet becomes available.
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
            fontLoads.delete(key);
        }
        return Array.isArray(faces) && faces.length > 0;
    } catch {
        return false;
    }
};

/** Start loading the default terminal font as soon as the app boots. */
export const preloadTerminalFonts = () => {
    void ensureTerminalFontsLoaded(DEFAULT_TERMINAL_FONT, 16);
};
