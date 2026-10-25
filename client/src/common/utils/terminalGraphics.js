/**
 * Streaming Kitty graphics resolver for web terminals.
 *
 * xterm.js' image addon implements direct-data transmissions (`t=d`) but not
 * the file (`t=f`) or temporary-file (`t=t`) transports. fastfetch and other
 * terminal tools commonly emit `t=f` with a path on the *remote* host, so the
 * browser cannot resolve it. This resolver rewrites those sequences into
 * chunked `t=d` transmissions after fetching the file through Nexterm's
 * authenticated SFTP endpoint.
 *
 * Everything is streaming: graphics sequences may be split across WebSocket
 * frames, and file transmissions may themselves use Kitty's `m=1` chunking.
 */

export const KITTY_CHUNK_SIZE = 4096;
export const MAX_GRAPHICS_IMAGE_BYTES = 12 * 1024 * 1024;
const MAX_SEQUENCE_BYTES = 48 * 1024 * 1024;
const MAX_IMAGE_PATH_LENGTH = 8192;

const APC_INTRO = "\x1b_G";
const APC_INTRO_8BIT = "\u009dG";
const ST = "\x1b\\";
const ST_8BIT = "\u009c";

const MARKERS = [
    { marker: APC_INTRO, type: "kitty", introLength: APC_INTRO.length },
    { marker: APC_INTRO_8BIT, type: "kitty", introLength: APC_INTRO_8BIT.length },
];

const findTerminator = (value, from = 0) => {
    for (let i = from; i < value.length; i++) {
        if (value[i] === "\x1b" && value[i + 1] === "\\") {
            return { index: i, length: 2 };
        }
        if (value[i] === ST_8BIT) {
            return { index: i, length: 1 };
        }
    }
    return null;
};

const parseControl = (control) => {
    const args = new Map();
    if (!control) return args;
    for (const part of control.split(",")) {
        if (!part) continue;
        const equals = part.indexOf("=");
        if (equals < 0) {
            args.set(part, "");
        } else {
            args.set(part.slice(0, equals), part.slice(equals + 1));
        }
    }
    return args;
};

const serializeControl = (control, { remove = [], set = [] } = {}) => {
    const removed = new Set(remove);
    const parts = [];
    for (const part of control.split(",")) {
        if (!part) continue;
        const equals = part.indexOf("=");
        const key = equals < 0 ? part : part.slice(0, equals);
        if (removed.has(key)) continue;
        parts.push(part);
    }
    for (const [key, value] of set) {
        parts.push(`${key}=${value}`);
    }
    return parts.join(",");
};

const decodeBase64 = (payload) => {
    const normalized = payload.replace(/\s+/g, "");
    const binary = atob(normalized);
    const bytes = new Uint8Array(binary.length);
    for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
    return bytes;
};

const encodeBase64 = (bytes) => {
    let binary = "";
    const step = 0x8000;
    for (let i = 0; i < bytes.length; i += step) {
        binary += String.fromCharCode.apply(null, bytes.subarray(i, i + step));
    }
    return btoa(binary);
};

const decodeUtf8 = (bytes) => new TextDecoder().decode(bytes);

export const detectImageFormat = (bytes) => {
    if (!bytes || bytes.length < 4) return null;
    if (bytes[0] === 0x89 && bytes[1] === 0x50 && bytes[2] === 0x4e && bytes[3] === 0x47) {
        return { format: "100", mime: "image/png" };
    }
    if (bytes[0] === 0xff && bytes[1] === 0xd8 && bytes[2] === 0xff) {
        return { format: "98", mime: "image/jpeg" };
    }
    if (bytes[0] === 0x47 && bytes[1] === 0x49 && bytes[2] === 0x46) {
        return { format: "50", mime: "image/gif" };
    }
    return null;
};

/**
 * Split a base64 payload into spec-sized Kitty APC chunks.
 * The first chunk carries the full control data and `m=1` while more data
 * follows; continuations only carry the `m` key.
 */
export const formatKittyTransmission = (control, payload, chunkSize = KITTY_CHUNK_SIZE) => {
    if (!payload) return "";
    const baseControl = serializeControl(control, { remove: ["m"] });
    if (payload.length <= chunkSize) {
        return `${APC_INTRO}${baseControl},m=0;${payload}${ST}`;
    }

    const chunks = [];
    for (let offset = 0; offset < payload.length; offset += chunkSize) {
        const part = payload.slice(offset, offset + chunkSize);
        const more = offset + chunkSize < payload.length;
        if (offset === 0) {
            chunks.push(`${APC_INTRO}${baseControl},m=${more ? 1 : 0};${part}${ST}`);
        } else {
            chunks.push(`${APC_INTRO}m=${more ? 1 : 0};${part}${ST}`);
        }
    }
    return chunks.join("");
};

const trailingMarkerLength = (value) => {
    let hold = 0;
    for (const { marker } of MARKERS) {
        const max = Math.min(marker.length - 1, value.length);
        for (let len = 1; len <= max; len++) {
            if (value.endsWith(marker.slice(0, len))) {
                hold = Math.max(hold, len);
            }
        }
    }
    return hold;
};

export class TerminalGraphicsResolver {
    constructor({ fetchImage = null, onError = null, maxImageBytes = MAX_GRAPHICS_IMAGE_BYTES } = {}) {
        this._fetchImage = fetchImage;
        this._onError = onError;
        this._maxImageBytes = maxImageBytes;
        this._pending = "";
        this._fileGroup = null;
        this._chain = Promise.resolve();
        this._disposed = false;
    }

    /**
     * Feed one WebSocket text frame. The returned promise resolves to text that
     * is safe to write to xterm. Promises are serialized so image fetches can
     * never reorder subsequent terminal output.
     */
    push(chunk) {
        const run = this._chain.then(() => this._process(chunk));
        this._chain = run.then(() => undefined, () => undefined);
        return run;
    }

    dispose() {
        this._disposed = true;
        this._pending = "";
        this._fileGroup = null;
    }

    async _process(chunk) {
        if (this._disposed) return "";
        this._pending += chunk;
        let output = "";

        while (this._pending) {
            const start = this._findStart(this._pending);
            if (!start) {
                const hold = trailingMarkerLength(this._pending);
                const emitLength = this._pending.length - hold;
                output += this._pending.slice(0, emitLength);
                this._pending = this._pending.slice(emitLength);
                break;
            }

            if (start.index > 0) {
                output += this._pending.slice(0, start.index);
                this._pending = this._pending.slice(start.index);
            }

            if (this._pending.length > MAX_SEQUENCE_BYTES) {
                this._dropPendingGroup();
                this._pending = "";
                this._report(new Error("Terminal graphics sequence exceeded the safety limit"));
                break;
            }

            const terminator = findTerminator(this._pending, start.introLength);
            if (!terminator) break;

            const end = terminator.index + terminator.length;
            const sequence = this._pending.slice(0, end);
            this._pending = this._pending.slice(end);

            try {
                output += await this._handleKitty(sequence, start.introLength, terminator.length);
            } catch (error) {
                this._dropPendingGroup();
                this._report(error);
            }
        }

        return output;
    }

    _findStart(value) {
        let earliest = null;
        for (const entry of MARKERS) {
            const index = value.indexOf(entry.marker);
            if (index < 0) continue;
            if (!earliest || index < earliest.index) {
                earliest = { ...entry, index };
            }
        }
        return earliest;
    }

    async _handleKitty(sequence, introLength, terminatorLength) {
        const body = sequence.slice(introLength, sequence.length - terminatorLength);
        const semicolon = body.indexOf(";");
        const control = semicolon < 0 ? body : body.slice(0, semicolon);
        const payload = semicolon < 0 ? "" : body.slice(semicolon + 1);
        const args = parseControl(control);

        // Continuation chunks of a file transmission. Per the Kitty protocol
        // these may omit all keys except `m`, so they cannot be interpreted on
        // their own.
        if (this._fileGroup) {
            if (this._fileGroup.dropped) {
                if (args.get("m") !== "1") this._fileGroup = null;
                return "";
            }
            this._fileGroup.payload += payload;
            if (this._fileGroup.payload.length > MAX_SEQUENCE_BYTES) {
                this._dropPendingGroup();
                return "";
            }
            if (args.get("m") === "1") return "";

            const group = this._fileGroup;
            this._fileGroup = null;
            return this._rewriteFileTransmission(group.control, group.payload);
        }

        const transport = args.get("t");
        if (transport !== "f" && transport !== "t") {
            // `t=s` (shared memory) cannot be resolved by a browser. Drop it
            // instead of letting the addon log a decode error for the path.
            if (transport === "s") return "";
            return sequence;
        }

        if (args.get("m") === "1") {
            this._fileGroup = { control, payload, dropped: false };
            return "";
        }

        return this._rewriteFileTransmission(control, payload);
    }

    async _rewriteFileTransmission(control, payload) {
        if (!this._fetchImage) {
            throw new Error("Remote terminal images are unavailable for this session");
        }
        const path = decodeUtf8(decodeBase64(payload));
        if (!path) throw new Error("Kitty file transmission did not contain a path");
        if (path.length > MAX_IMAGE_PATH_LENGTH || path.includes("\0")) {
            throw new Error("Kitty file transmission contains an invalid path");
        }

        const bytes = await this._fetchImage(path);
        if (!bytes || bytes.length === 0) {
            throw new Error(`Remote terminal image is empty: ${path}`);
        }
        if (bytes.length > this._maxImageBytes) {
            throw new Error(`Remote terminal image exceeds ${this._maxImageBytes} bytes: ${path}`);
        }

        const args = parseControl(control);
        const requestedFormat = args.get("f");
        const detected = detectImageFormat(bytes);
        let format = detected?.format;
        if (requestedFormat === "24" || requestedFormat === "32") {
            // Raw RGB/RGBA payloads have no magic bytes. The requested format
            // and s/v dimensions in the original control data remain valid.
            format = requestedFormat;
        }
        if (!format) {
            throw new Error(`Unsupported remote terminal image format: ${path}`);
        }

        const rewrittenControl = serializeControl(control, {
            remove: ["t", "m", "f"],
            set: [
                ["f", format],
                ["t", "d"],
            ],
        });
        return formatKittyTransmission(rewrittenControl, encodeBase64(bytes));
    }

    _dropPendingGroup() {
        if (!this._fileGroup) return;
        // Swallow the rest of a malformed/chunked file transmission rather
        // than accidentally writing base64 image data to the terminal.
        this._fileGroup = { control: "", payload: "", dropped: true };
    }

    _report(error) {
        if (this._onError) this._onError(error);
    }
}

export const createTerminalGraphicsResolver = (options) => new TerminalGraphicsResolver(options);

/**
 * Remove inline-image payloads before persisting terminal output in React
 * state. Replay should restore the text, not megabytes of base64 image data.
 */
/* eslint-disable no-control-regex -- ANSI/APC/OSC introducers are control characters */
export const stripGraphicsSequences = (text) => {
    if (typeof text !== "string" || !text) return "";
    return text
        .replace(/(?:\x1b_G|\u009dG)[\s\S]*?(?:\x1b\\|\u009c)/g, "")
        .replace(/(?:\x1bP|\u009dP)[0-9;]*q[\s\S]*?(?:\x1b\\|\u009c)/g, "")
        .replace(/(?:\x1b\]|\u009d)1337;File=[^\x07\x1b\u009c]*(?:\x07|\x1b\\|\u009c)/g, "")
        .replace(/(?:\x1b_G|\u009dG)[\s\S]*$/, "")
        .replace(/(?:\x1bP|\u009dP)[0-9;]*q[\s\S]*$/, "")
        .replace(/(?:\x1b\]|\u009d)1337;File=[\s\S]*$/, "");
};
