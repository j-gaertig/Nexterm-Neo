/* eslint-disable no-control-regex -- the tests parse terminal control sequences */
import assert from "node:assert/strict";
import { Buffer } from "node:buffer";
import test from "node:test";

import {
    KITTY_CHUNK_SIZE,
    TerminalGraphicsResolver,
    detectImageFormat,
    formatKittyTransmission,
    stripGraphicsSequences,
} from "./terminalGraphics.js";

const ST = "\x1b\\";
const AVATAR_PATH = "/home/user/.config/fastfetch/avatar.png";

// The resolver only needs the magic bytes to select a Kitty format. Real PNG
// decoding is covered by the browser/mobile tests; using synthetic data keeps
// this test fast and independent of an image library.
const makePng = (size = 10000) => {
    const bytes = new Uint8Array(size);
    bytes.set([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
    for (let i = 8; i < bytes.length; i++) bytes[i] = i & 0xff;
    return bytes;
};

const base64 = (value) => Buffer.from(value).toString("base64");

const splitEvery = (value, size) => {
    const parts = [];
    for (let offset = 0; offset < value.length; offset += size) {
        parts.push(value.slice(offset, offset + size));
    }
    return parts;
};

const pushAll = async (resolver, chunks) => {
    let output = "";
    for (const chunk of chunks) output += await resolver.push(chunk);
    return output;
};

const kittyChunks = (value) => [
    ...value.matchAll(/\x1b_G([^;]*);([^\x1b]*)\x1b\\/g),
].map((match) => ({ control: match[1], payload: match[2] }));

test("rewrites the exact fastfetch avatar sequence through one SFTP fetch", async () => {
    const png = makePng();
    const calls = [];
    const resolver = new TerminalGraphicsResolver({
        fetchImage: async (path) => {
            calls.push(path);
            return png;
        },
    });

    const sequence = `\x1b_Ga=T,f=100,t=f,q=2,C=1,c=6,r=3;${base64(AVATAR_PATH)}${ST}`;
    const output = await pushAll(resolver, splitEvery(`before${sequence}\x1b[8Cname`, 7));

    assert.deepEqual(calls, [AVATAR_PATH]);
    assert.ok(output.startsWith("before"));
    assert.ok(output.endsWith("\x1b[8Cname"));
    assert.ok(!output.includes("t=f"));
    assert.ok(!output.includes(AVATAR_PATH));

    const chunks = kittyChunks(output);
    assert.ok(chunks.length > 1);
    assert.equal(chunks[0].control.includes("a=T"), true);
    assert.equal(chunks[0].control.includes("f=100"), true);
    assert.equal(chunks[0].control.includes("t=d"), true);
    assert.equal(chunks[0].control.includes("q=2"), true);
    assert.equal(chunks[0].control.includes("C=1"), true);
    assert.equal(chunks[0].control.includes("c=6"), true);
    assert.equal(chunks[0].control.includes("r=3"), true);
    assert.equal(chunks[0].control.includes("m=1"), true);

    const payload = chunks.map((chunk) => chunk.payload).join("");
    assert.deepEqual(Buffer.from(payload, "base64"), Buffer.from(png));
    assert.equal(chunks.slice(1, -1).every((chunk) => chunk.control === "m=1"), true);
    assert.equal(chunks.at(-1).control, "m=0");
    assert.equal(chunks.length, Math.ceil(payload.length / KITTY_CHUNK_SIZE));
});

test("coalesces chunked t=f transmissions and fetches once", async () => {
    const png = makePng(6000);
    const calls = [];
    const resolver = new TerminalGraphicsResolver({
        fetchImage: async (path) => {
            calls.push(path);
            return png;
        },
    });

    const pathPayload = base64(AVATAR_PATH);
    const first = pathPayload.slice(0, 12);
    const second = pathPayload.slice(12);
    const output = await pushAll(resolver, [
        `\x1b_Ga=T,f=100,t=f,m=1,q=2,C=1,c=4,r=2;${first}${ST}`,
        `\x1b_Gm=1;${second}${ST}`,
        `\x1b_Gm=0;${ST}`,
        "after",
    ]);

    assert.deepEqual(calls, [AVATAR_PATH]);
    assert.ok(output.endsWith("after"));
    assert.equal(kittyChunks(output).map((chunk) => chunk.payload).join("").length > 0, true);
});

test("passes direct-data transmissions through and drops t=s", async () => {
    const resolver = new TerminalGraphicsResolver();
    const direct = `\x1b_Ga=T,f=100,t=d,C=1,c=2,r=1;QUJD${ST}`;

    const output = await resolver.push(`A${direct}B\x1b_Ga=t,t=s;c2hhcmVk${ST}C`);

    assert.equal(output, `A${direct}BC`);
});

test("drops a failed fetch without leaking image bytes or following text", async () => {
    const errors = [];
    const resolver = new TerminalGraphicsResolver({
        fetchImage: async () => {
            throw new Error("offline");
        },
        onError: (error) => errors.push(error),
    });

    const sequence = `\x1b_Ga=T,f=100,t=f,C=1,c=6,r=3;${base64(AVATAR_PATH)}${ST}`;
    const output = await resolver.push(`left${sequence}right`);

    assert.equal(output, "leftright");
    assert.equal(errors.length, 1);
    assert.match(errors[0].message, /offline/);
});

test("rejects NUL and oversized remote image paths without fetching", async () => {
    let fetched = 0;
    const errors = [];
    const resolver = new TerminalGraphicsResolver({
        fetchImage: async () => {
            fetched++;
            return makePng(64);
        },
        onError: (error) => errors.push(error),
    });
    const withNul = "\x1b_Ga=T,f=100,t=f,C=1,c=1,r=1;"
        + `${base64(`${AVATAR_PATH}\0suffix`)}${ST}`;
    const tooLong = "\x1b_Ga=T,f=100,t=f,C=1,c=1,r=1;"
        + `${base64(`/${"a".repeat(8192)}`)}${ST}`;

    const output = await resolver.push(`a${withNul}b${tooLong}c`);

    assert.equal(output, "abc");
    assert.equal(fetched, 0);
    assert.equal(errors.length, 2);
    assert.match(errors[0].message, /invalid path/);
});

test("serializes pushes so a slow image cannot reorder output", async () => {
    let release;
    const gate = new Promise((resolve) => {
        release = resolve;
    });
    const resolver = new TerminalGraphicsResolver({
        fetchImage: async () => {
            await gate;
            return makePng(64);
        },
    });

    const first = resolver.push(`\x1b_Ga=T,f=100,t=f,C=1,c=1,r=1;${base64(AVATAR_PATH)}${ST}`);
    const second = resolver.push("after");
    await new Promise((resolve) => setTimeout(resolve, 5));
    release();

    assert.ok((await first).includes("t=d"));
    assert.equal(await second, "after");
});

test("detects supported image formats", () => {
    assert.equal(detectImageFormat(makePng()).format, "100");
    assert.equal(detectImageFormat(new Uint8Array([0xff, 0xd8, 0xff, 0x00])).format, "98");
    assert.equal(detectImageFormat(new Uint8Array([0x47, 0x49, 0x46, 0x38])).format, "50");
    assert.equal(detectImageFormat(new Uint8Array([1, 2, 3, 4])), null);
});

test("formats small and chunked transmissions", () => {
    assert.equal(
        formatKittyTransmission("a=T,f=100,t=d", "QUJD"),
        `\x1b_Ga=T,f=100,t=d,m=0;QUJD${ST}`,
    );

    const payload = "A".repeat(KITTY_CHUNK_SIZE + 1);
    const chunks = kittyChunks(formatKittyTransmission("a=T,f=100,t=d", payload));
    assert.equal(chunks.length, 2);
    assert.equal(chunks[0].control, "a=T,f=100,t=d,m=1");
    assert.equal(chunks[1].control, "m=0");
    assert.equal(chunks.map((chunk) => chunk.payload).join(""), payload);
});

test("strips image payloads from replay text but preserves terminal output", () => {
    const pngPayload = base64(makePng(256));
    const text = [
        "a",
        `\x1b_Ga=T,f=100,t=d;${pngPayload}${ST}`,
        "b",
        `\x1b]1337;File=inline=1;width=4:${pngPayload}\x07`,
        "c",
        `\x1bPq#0;2;0;0;0#0~~${ST}`,
        "d",
        `\x1b]1337;File=inline=1;width=4:${pngPayload}${ST}`,
        "e",
        "\x1bP$q544e\x1b\\",
    ].join("");

    assert.equal(stripGraphicsSequences(text), "abcde\x1bP$q544e\x1b\\");
});

test("strips an incomplete trailing graphics sequence", () => {
    assert.equal(
        stripGraphicsSequences(`text\x1b_Ga=T,f=100,t=d;${"A".repeat(100)}`),
        "text",
    );
    assert.equal(
        stripGraphicsSequences(`text\x1b]1337;File=inline=1;width=4:${"A".repeat(100)}`),
        "text",
    );
    assert.equal(stripGraphicsSequences("plain"), "plain");
    assert.equal(stripGraphicsSequences(undefined), "");
});

test("holds only a genuine partial marker between pushes", async () => {
    const resolver = new TerminalGraphicsResolver();
    assert.equal(await resolver.push("text\x1b"), "text");
    assert.equal(await resolver.push("_"), "");
    assert.equal(await resolver.push("and more"), "\x1b_and more");
});
