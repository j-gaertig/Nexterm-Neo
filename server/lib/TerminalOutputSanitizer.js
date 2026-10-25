const ST = "\x1b\\";
const ST_8BIT = "\x9c";
const BEL = "\x07";

// Logs, recordings, and replay buffers must never contain inline-image
// payloads. They are large, useless in a text log, and would otherwise grow
// the 200 KiB replay buffer by megabytes per fastfetch invocation. Live
// WebSocket output intentionally bypasses this filter.
const MARKERS = [
    { value: "\x1b_G", type: "kitty" },
    { value: "\u009dG", type: "kitty" },
    { value: "\x1b]1337;File=", type: "iterm" },
    { value: "\u009d1337;File=", type: "iterm" },
    { value: "\x1bP", type: "dcs" },
    { value: "\u009dP", type: "dcs" },
];

const MAX_PENDING_SIZE = 48 * 1024 * 1024;
const GRAPHICS_INTROS = ["\x1b_G", "\u009dG", "\x1b]1337;File=", "\u009d1337;File="];

const findMarker = (value) => {
    let earliest = null;
    for (const marker of MARKERS) {
        const index = value.indexOf(marker.value);
        if (index < 0) continue;
        if (!earliest || index < earliest.index) {
            earliest = { ...marker, index };
        }
    }
    return earliest;
};

const findTerminator = (value, from) => {
    for (let i = from; i < value.length; i++) {
        if (value[i] === "\x1b" && value[i + 1] === "\\") {
            return { index: i, length: 2 };
        }
        if (value[i] === ST_8BIT) return { index: i, length: 1 };
        if (value[i] === BEL) return { index: i, length: 1 };
    }
    return null;
};

const trailingPrefixLength = (value) => {
    let hold = 0;
    for (const { value: marker } of MARKERS) {
        const max = Math.min(marker.length - 1, value.length);
        for (let length = 1; length <= max; length++) {
            if (value.endsWith(marker.slice(0, length))) {
                hold = Math.max(hold, length);
            }
        }
    }
    return hold;
};

const isSixel = (sequence, introLength, terminatorLength) => {
    const body = sequence.slice(introLength, sequence.length - terminatorLength);
    return /^[0-9;]*q/.test(body);
};

class TerminalOutputSanitizer {
    constructor() {
        this._pending = "";
    }

    push(text) {
        if (text === undefined || text === null || text === "") return "";
        this._pending += typeof text === "string" ? text : String(text);
        let output = "";

        while (this._pending.length > 0) {
            const marker = findMarker(this._pending);
            if (!marker) {
                const hold = trailingPrefixLength(this._pending);
                const emitLength = this._pending.length - hold;
                output += this._pending.slice(0, emitLength);
                this._pending = this._pending.slice(emitLength);
                break;
            }

            if (marker.index > 0) {
                output += this._pending.slice(0, marker.index);
                this._pending = this._pending.slice(marker.index);
            }

            if (this._pending.length > MAX_PENDING_SIZE) {
                // Never retain an unbounded sequence. Dropping a truncated
                // image is preferable to unbounded log-buffer growth.
                this._pending = "";
                break;
            }

            const introLength = marker.value.length;
            const terminator = findTerminator(this._pending, introLength);
            if (!terminator) break;

            const end = terminator.index + terminator.length;
            const sequence = this._pending.slice(0, end);
            this._pending = this._pending.slice(end);

            if (marker.type === "dcs") {
                // Sixel is image data. A non-image DCS (for example a tmux
                // passthrough carrying normal output) is preserved, unless it
                // wraps an inline image.
                const wrapsGraphics = GRAPHICS_INTROS.some((intro) => sequence.includes(intro));
                if (!isSixel(sequence, introLength, terminator.length) && !wrapsGraphics) {
                    output += sequence;
                }
            }
            // kitty, iTerm2, and sixel sequences are intentionally dropped.
        }

        return output;
    }

    clear() {
        this._pending = "";
    }
}

module.exports = TerminalOutputSanitizer;
module.exports.TerminalOutputSanitizer = TerminalOutputSanitizer;
