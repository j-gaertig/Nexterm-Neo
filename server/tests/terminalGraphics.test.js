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

test("removes Kitty, iTerm2 and SIXEL payloads from recorded output", () => {
    const sanitizer = new TerminalOutputSanitizer();
    const image = Buffer.from("not-a-real-png").toString("base64");
    const text = [
        "logo line 1\r\n",
        FASTFETCH_AVATAR,
        "\x1b[8Cuser\r\n",
        `\x1b]1337;File=inline=1;width=4:${image}\x07`,
        "after iTerm\r\n",
        `\x1bPq#0;2;0;0;0#0~~${ST}`,
        "after sixel\r\n",
    ].join("");

    const output = sanitizer.push(text);

    assert.equal(output, "logo line 1\r\n\x1b[8Cuser\r\nafter iTerm\r\nafter sixel\r\n");
    assert.equal(output.includes("avatar.png"), false);
    assert.equal(output.includes(image), false);
    assert.equal(output.includes("\x1b_G"), false);
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
