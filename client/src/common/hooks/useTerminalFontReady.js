import { useEffect, useState } from "react";
import { ensureTerminalFontsLoaded } from "@/common/utils/terminalFonts.js";

/**
 * Tracks whether the terminal font for the current font settings is ready.
 * Terminal effects should wait for this before creating xterm.
 */
export const useTerminalFontReady = (fontFamily, fontSize) => {
    const key = `${fontFamily}|${fontSize}`;
    const [readyKey, setReadyKey] = useState(null);

    useEffect(() => {
        let cancelled = false;

        void ensureTerminalFontsLoaded(fontFamily, fontSize).then(() => {
            if (!cancelled) setReadyKey(key);
        });

        return () => {
            cancelled = true;
        };
    }, [fontFamily, fontSize, key]);

    return readyKey === key;
};
