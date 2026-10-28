const test = require("node:test");
const assert = require("node:assert/strict");

const TerminalOutputSanitizer = require("../lib/TerminalOutputSanitizer");
const { createDecodedTextStream } = require("../utils/terminalStream");

const ST = "\x1b\\";
const FASTFETCH_AVATAR =
    "\x1b_Ga=T,f=100,t=f,q=2,C=1,c=6,r=3;" +
    Buffer.from("/home/user/.config/fastfetch/avatar.png").toString("base64") +
    ST;

const feedSplit = (sanitizer, text, size) => {
    let output = "";
    for (let offset = 0; offset < text.length; offset += size) {
        output += sanitizer.push(text.slice(offset, offset + size));
    }
    return output;
};

test("keeps Kitty file references but removes inline image payloads", () => {
    const sanitizer = new TerminalOutputSanitizer();
    const image = Buffer.from("not-a-real-png").toString("base64");
    const direct = `\x1b_Ga=T,f=100,t=d;${image}${ST}`;
    const text = [
        "logo line 1\r\n",
        direct,
        "\x1b[8Cuser\r\n",
        FASTFETCH_AVATAR,
        "after avatar\r\n",
        `\x1b]1337;File=inline=1;width=4:${image}\x07`,
        "after iTerm\r\n",
        `\x1bPq#0;2;0;0;0#0~~${ST}`,
        "after sixel\r\n",
    ].join("");

    const output = sanitizer.push(text);

    // The path-only fastfetch avatar must survive so a reconnecting terminal
    // can fetch it again; all real image payloads must not.
    assert.equal(output, `logo line 1\r\n\x1b[8Cuser\r\n${FASTFETCH_AVATAR}after avatar\r\nafter iTerm\r\nafter sixel\r\n`);
    assert.equal(output.includes("avatar.png"), false);
    assert.equal(output.includes(image), false);
    assert.equal(output.includes(direct), false);
});

test("keeps chunked Kitty file transmissions intact", () => {
    const payload = Buffer.from("/home/user/.config/fastfetch/avatar.png").toString("base64");
    const third = Math.ceil(payload.length / 3);
    const transmission = [
        `\x1b_Ga=T,f=100,t=f,m=1;${payload.slice(0, third)}${ST}`,
        `\x1b_Gm=1;${payload.slice(third, third * 2)}${ST}`,
        `\x1b_Gm=0;${payload.slice(third * 2)}${ST}`,
    ].join("");
    const text = `logo${transmission}modules\r\n`;

    assert.equal(feedSplit(new TerminalOutputSanitizer(), text, text.length), text);
    assert.equal(feedSplit(new TerminalOutputSanitizer(), text, 1), text);
    assert.equal(feedSplit(new TerminalOutputSanitizer(), text, 7), text);
});

test("keeps chunked Kitty animation frame file transmissions", () => {
    const payload = Buffer.from("/home/user/.config/fastfetch/avatar.png").toString("base64");
    const third = Math.ceil(payload.length / 3);
    const transmission = [
        `\x1b_Ga=f,i=1,f=100,t=f,m=1;${payload.slice(0, third)}${ST}`,
        `\x1b_Gm=1,a=f;${payload.slice(third, third * 2)}${ST}`,
        `\x1b_Gm=0,a=f;${payload.slice(third * 2)}${ST}`,
    ].join("");
    const text = `logo${transmission}modules\r\n`;

    assert.equal(feedSplit(new TerminalOutputSanitizer(), text, text.length), text);
    assert.equal(feedSplit(new TerminalOutputSanitizer(), text, 1), text);
    assert.equal(feedSplit(new TerminalOutputSanitizer(), text, 7), text);
});

test("keeps temporary-file Kitty references", () => {
    const payload = Buffer.from("/tmp/kitty-image.png").toString("base64");
    const transmission = `\x1b_Ga=T,f=100,t=t;${payload}${ST}`;

    assert.equal(new TerminalOutputSanitizer().push(`a${transmission}b`), `a${transmission}b`);
});

test("keeps 8-bit Kitty file references", () => {
    const payload = Buffer.from("/tmp/kitty-image.png").toString("base64");
    const transmission = `\u009dGa=T,f=100,t=f;${payload}\u009c`;

    assert.equal(new TerminalOutputSanitizer().push(`a${transmission}b`), `a${transmission}b`);
});

test("drops a file reference with oversized control data", () => {
    const payload = Buffer.from("/tmp/kitty-image.png").toString("base64");
    const transmission = `\x1b_Ga=T,f=100,t=f,${"X".repeat(20 * 1024)};${payload}${ST}`;

    assert.equal(new TerminalOutputSanitizer().push(`a${transmission}b`), "ab");
});

test("drops a chunked file reference that exceeds the replay limit", () => {
    const transmission = [
        `\x1b_Ga=T,f=100,t=f,m=1;${"A".repeat(6000)}${ST}`,
        `\x1b_Gm=1;${"B".repeat(6000)}${ST}`,
        `\x1b_Gm=0;${"C".repeat(100)}${ST}`,
    ].join("");

    assert.equal(new TerminalOutputSanitizer().push(`a${transmission}b`), "ab");
});

test("abandons an interrupted group instead of swallowing the next reference", () => {
    const sanitizer = new TerminalOutputSanitizer();

    assert.equal(sanitizer.push(`\x1b_Ga=T,f=100,t=d,m=1;QUJD${ST}`), "");
    assert.equal(sanitizer.push(`a${FASTFETCH_AVATAR}b`), `a${FASTFETCH_AVATAR}b`);
});

test("bounds a flood of empty file continuations", () => {
    const sanitizer = new TerminalOutputSanitizer();
    const first = `\x1b_Ga=T,f=100,t=f,m=1;${Buffer.from("/tmp/a.png").toString("base64")}${ST}`;

    assert.equal(sanitizer.push(first), "");
    for (let i = 0; i < 2000; i++) {
        assert.equal(sanitizer.push(`\x1b_Gm=1;${ST}`), "");
    }

    assert.equal(sanitizer._kittyGroup.keep, false);
    assert.deepEqual(sanitizer._kittyGroup.sequences, []);
    assert.equal(sanitizer.push(`\x1b_Gm=0;${ST}`), "");
});

test("never mixes direct-data sequences into a preserved file group", () => {
    const sanitizer = new TerminalOutputSanitizer();
    const direct = `\x1b_Ga=T,f=100,t=d;QUJD${ST}`;

    assert.equal(sanitizer.push(`\x1b_Ga=T,f=100,t=f,m=1;${Buffer.from("/tmp/a.png").toString("base64")}${ST}`), "");
    assert.equal(sanitizer.push(direct), "");
    assert.equal(sanitizer.push("after"), "after");
});

test("does not preserve BEL-terminated Kitty sequences", () => {
    const payload = Buffer.from("/tmp/kitty-image.png").toString("base64");
    const transmission = `\x1b_Ga=T,f=100,t=f;${payload}\x07`;

    assert.equal(new TerminalOutputSanitizer().push(`a${transmission}b`), "ab");
});

test("drops a file reference larger than the replay limit", () => {
    const payload = Buffer.from("x".repeat(20 * 1024)).toString("base64");
    const transmission = `\x1b_Ga=T,f=100,t=f;${payload}${ST}`;

    assert.equal(new TerminalOutputSanitizer().push(`a${transmission}b`), "ab");
});

test("drops chunked Kitty direct-data transmissions", () => {
    const image = Buffer.from("payload".repeat(200)).toString("base64");
    const transmission = [
        `\x1b_Ga=T,f=100,t=d,m=1;${image.slice(0, 100)}${ST}`,
        `\x1b_Gm=1;${image.slice(100, 200)}${ST}`,
        `\x1b_Gm=0;${image.slice(200)}${ST}`,
    ].join("");
    const text = `a${transmission}b`;

    assert.equal(feedSplit(new TerminalOutputSanitizer(), text, text.length), "ab");
    assert.equal(feedSplit(new TerminalOutputSanitizer(), text, 1), "ab");
    assert.equal(feedSplit(new TerminalOutputSanitizer(), text, 7), "ab");
});

test("sanitizes identical output regardless of chunk boundaries", () => {
    const image = Buffer.from("payload".repeat(200)).toString("base64");
    const text = `a\x1b_Ga=T,f=100,t=d;${image}${ST}b\x1b]1337;File=inline=1:${image}\x07c\x1bPq#0;2;0;0;0#0~~${ST}d`;
    const expected = "abcd";

    assert.equal(feedSplit(new TerminalOutputSanitizer(), text, text.length), expected);
    assert.equal(feedSplit(new TerminalOutputSanitizer(), text, 1), expected);
    assert.equal(feedSplit(new TerminalOutputSanitizer(), text, 7), expected);
    assert.equal(feedSplit(new TerminalOutputSanitizer(), text, 31), expected);
});

test("keeps ordinary DCS sequences and plain OSC output", () => {
    const sanitizer = new TerminalOutputSanitizer();
    const passthrough = "\x1bP$q544e\x1b\\";
    const response = "\x1b]11;rgb:0000/0000/0000\x07";
    const tmux = "\x1bPtmux;\x1b[31mred\x1b\\";
    const text = `a${passthrough}b${response}c${tmux}d`;

    assert.equal(sanitizer.push(text), text);
});

test("drops a DCS that wraps an inline image but keeps other DCS", () => {
    const sanitizer = new TerminalOutputSanitizer();
    const wrapped = `\x1bPtmux;prefix\x1b_Ga=T,f=100,t=d;QUJD${ST}`;

    assert.equal(sanitizer.push(`a${wrapped}b\x1bP$q544e\x1b\\c`), "ab\x1bP$q544e\x1b\\c");
});

test("drops a DCS that wraps an 8-bit Kitty or iTerm2 payload", () => {
    const sanitizer = new TerminalOutputSanitizer();
    const kitty = `\x1bPtmux;\u009dGa=T,f=100,t=d;QUJD\u009c`;
    const iterm = `\x1bPtmux;\u009d1337;File=inline=1:QUJD\u009c`;

    assert.equal(
        sanitizer.push(`a${kitty}b${iterm}c\x1bP$q544e\x1b\\d`),
        "abc\x1bP$q544e\x1b\\d",
    );
});

test("does not leak a partial image sequence when more text follows", () => {
    const sanitizer = new TerminalOutputSanitizer();

    assert.equal(sanitizer.push("a\x1b_Ga=T,f=100;QUJ"), "a");
    assert.equal(sanitizer.push("D"), "");
    assert.equal(sanitizer.push(ST), "");
    assert.equal(sanitizer.push("b"), "b");
});

test("clear() releases a pending unterminated sequence", () => {
    const sanitizer = new TerminalOutputSanitizer();

    assert.equal(sanitizer.push("a\x1b_Ga=T,f=100;QUJD"), "a");
    sanitizer.clear();
    assert.equal(sanitizer.push("b"), "b");
});

test("UTF-8 terminal chunks may split any code point without corruption", () => {
    const text = "╭─ fastfetch 你好 🚀 󰣇 日本語 \u001b[31mred\u001b[0m\r\n";
    const bytes = Buffer.from(text, "utf8");

    for (let split = 1; split < bytes.length; split += 3) {
        const chunks = [bytes.subarray(0, split), bytes.subarray(split)];
        let output = "";
        const stream = createDecodedTextStream((chunk) => {
            output += chunk;
        });
        for (const chunk of chunks) stream.write(chunk);
        stream.end();
        assert.equal(output, text);
    }
});

test("decodes one byte at a time and accepts strings and Uint8Arrays", () => {
    let output = "";
    const stream = createDecodedTextStream((chunk) => {
        output += chunk;
    });
    const bytes = Buffer.from("A😀B", "utf8");
    for (const byte of bytes) stream.write(new Uint8Array([byte]));
    stream.write("tail");
    stream.write(null);
    stream.end();
    stream.end();

    assert.equal(output, "A😀Btail");
});
