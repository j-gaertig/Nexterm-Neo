const { StringDecoder } = require("node:string_decoder");

/**
 * Decode a terminal byte stream incrementally.
 *
 * A single UTF-8 code point (and every emoji/box-drawing glyph) can straddle
 * two socket chunks. Calling `Buffer.toString()` on each chunk corrupts those
 * characters; `StringDecoder` keeps the incomplete tail until the next chunk.
 * This matters doubly for inline images, whose base64/path payloads are split
 * at arbitrary byte boundaries.
 */
const createDecodedTextStream = (onText) => {
    const decoder = new StringDecoder("utf8");

    const emit = (text) => {
        if (text) onText(text);
    };

    return {
        write(data) {
            if (data === undefined || data === null) return;
            if (typeof data === "string") {
                emit(data);
                return;
            }
            const buffer = Buffer.isBuffer(data)
                ? data
                : data instanceof Uint8Array
                    ? Buffer.from(data.buffer, data.byteOffset, data.byteLength)
                    : Buffer.from(data);
            emit(decoder.write(buffer));
        },
        end() {
            emit(decoder.end());
        },
    };
};

module.exports = { createDecodedTextStream };
