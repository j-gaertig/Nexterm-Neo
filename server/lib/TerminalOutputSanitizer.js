const ST = "\x1b\\";
const ST_8BIT = "\x9c";
const BEL = "\x07";

// Logs, recordings, and replay buffers must never contain inline-image
// payloads. They are large, useless in a text log, and would otherwise grow
// the 200 KiB replay buffer by megabytes per fastfetch invocation. Live
// WebSocket output intentionally bypasses this filter.
//
// Kitty file transmissions (`t=f`/`t=t`) are the exception: their payload is
// only the remote path of the image. Keeping the original sequence lets a
// reconnecting terminal resolve the image again through SFTP instead of
// losing every fastfetch logo after a hibernation or page reload.
const MARKERS = [
    { value: "\x1b_G", type: "kitty" },
    { value: "\u009dG", type: "kitty" },
    { value: "\x1b]1337;File=", type: "iterm" },
    { value: "\u009d1337;File=", type: "iterm" },
    { value: "\x1bP", type: "dcs" },
    { value: "\u009dP", type: "dcs" },
];

const MAX_PENDING_SIZE = 48 * 1024 * 1024;
// A remote image path is tiny compared to the image itself. The limit counts
// the whole retained sequence (control data, payload and APC framing) so a
// malformed transmission cannot bypass it with oversized control blocks or an
// endless stream of empty continuations. It covers the client's 8 KiB decoded
// path limit plus base64 and control overhead.
const MAX_FILE_TRANSMISSION_BYTES = Math.ceil(8192 / 3) * 4 + 1024;
const CONTINUATION_KEYS = new Set(["m", "q"]);
const GRAPHICS_INTROS = ["\x1b_G", "\u009dG", "\x1b]1337;File=", "\u009d1337;File="];

// Continuation chunks of a Kitty transmission may only repeat `m`, optionally
// `q`, and `a=f` for animation frames. Anything else means the previous
// sequence was truncated or a new transmission started.
const isContinuation = (args) =>
    [...args.entries()].every(([key, value]) =>
        CONTINUATION_KEYS.has(key) || (key === "a" && value === "f"),
    );

const parseControl = (control) => {
    const args = new Map();
    for (const part of control.split(",")) {
        if (!part) continue;
        const equals = part.indexOf("=");
        if (equals < 0) args.set(part, "");
        else args.set(part.slice(0, equals), part.slice(equals + 1));
    }
    return args;
};

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

const findTerminator = (value, from, allowBel = false) => {
    for (let i = from; i < value.length; i++) {
        if (value[i] === "\x1b" && value[i + 1] === "\\") {
            return { index: i, length: 2 };
        }
        if (value[i] === ST_8BIT) return { index: i, length: 1 };
        if (allowBel && value[i] === BEL) return { index: i, length: 1 };
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
        this._kittyGroup = null;
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
                this._kittyGroup = null;
                this._pending = "";
                break;
            }

            const introLength = marker.value.length;
            const terminator = findTerminator(this._pending, introLength, marker.type !== "dcs");
            if (!terminator) break;

            const end = terminator.index + terminator.length;
            const sequence = this._pending.slice(0, end);
            this._pending = this._pending.slice(end);

            if (marker.type === "kitty") {
                output += this._handleKitty(sequence, introLength, terminator.length);
            } else if (marker.type === "dcs") {
                // Sixel is image data. A non-image DCS (for example a tmux
                // passthrough carrying normal output) is preserved, unless it
                // wraps an inline image.
                const wrapsGraphics = GRAPHICS_INTROS.some((intro) => sequence.includes(intro));
                if (!isSixel(sequence, introLength, terminator.length) && !wrapsGraphics) {
                    output += sequence;
                }
            }
            // iTerm2 and sixel sequences are intentionally dropped, together
            // with Kitty direct-data transmissions.
        }

        return output;
    }

    _handleKitty(sequence, introLength, terminatorLength) {
        // Kitty APC is terminated by ST, not BEL. Accept BEL only long enough
        // to consume the invalid sequence; preserving it would make the web
        // client wait for an ST that never comes and swallow following text.
        if (terminatorLength === 1 && sequence.endsWith(BEL)) {
            this._kittyGroup = null;
            return "";
        }

        const body = sequence.slice(introLength, sequence.length - terminatorLength);
        const semicolon = body.indexOf(";");
        const control = semicolon < 0 ? body : body.slice(0, semicolon);
        const args = parseControl(control);
        const transport = args.get("t");
        const more = args.get("m") === "1";
        const isFile = transport === "f" || transport === "t";

        const group = this._kittyGroup;
        if (group) {
            // Continuation chunks may only carry `m`/`q`, plus `a=f` for
            // animation frames; any other key means the previous group was
            // truncated and this starts a new transmission. Abandon the stale
            // group instead of swallowing a valid file reference or mixing
            // direct-data into it.
            if (isContinuation(args)) {
                group.bytes += sequence.length;
                if (group.keep) {
                    group.sequences.push(sequence);
                    if (group.bytes > MAX_FILE_TRANSMISSION_BYTES) {
                        group.keep = false;
                        group.sequences = [];
                    }
                }

                if (more) return "";

                this._kittyGroup = null;
                return group.keep ? group.sequences.join("") : "";
            }

            this._kittyGroup = null;
        }

        if (!more) {
            return isFile && sequence.length <= MAX_FILE_TRANSMISSION_BYTES ? sequence : "";
        }

        // The first chunk of a transmission. Keep file references so replay
        // can re-fetch them, but swallow direct-data chunks completely.
        const keep = isFile && sequence.length <= MAX_FILE_TRANSMISSION_BYTES;
        this._kittyGroup = {
            keep,
            bytes: sequence.length,
            sequences: keep ? [sequence] : [],
        };
        return "";
    }

    clear() {
        this._pending = "";
        this._kittyGroup = null;
    }
}

module.exports = TerminalOutputSanitizer;
module.exports.TerminalOutputSanitizer = TerminalOutputSanitizer;
