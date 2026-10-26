const test = require("node:test");
const assert = require("node:assert/strict");
const { EventEmitter } = require("node:events");

const stubModule = (request, exports) => {
    const filename = require.resolve(request);
    require.cache[filename] = {
        id: filename,
        filename,
        loaded: true,
        exports,
        children: [],
        paths: [],
    };
    return exports;
};

const logger = stubModule("../utils/logger", {
    info() {},
    warn() {},
    error() {},
    debug() {},
});
const SessionManager = stubModule("../lib/SessionManager", {
    get: () => null,
});

const { ScriptLayer, SCRIPT_MAGIC, MSG } = require("../lib/ScriptLayer");

const parse = (message) => JSON.parse(message.slice(SCRIPT_MAGIC.length));

class FakeWs extends EventEmitter {
    constructor() {
        super();
        this.OPEN = 1;
        this.readyState = 1;
        this.sent = [];
    }

    send(message) {
        this.sent.push(message);
    }
}

const makeStream = () => {
    const stream = new EventEmitter();
    stream.written = [];
    stream.write = (data) => {
        stream.written.push(data);
        return true;
    };
    return stream;
};

const createHarness = (t) => {
    const stream = makeStream();
    const ws = new FakeWs();
    const session = { connectedWs: new Set([ws]) };
    const originalGet = SessionManager.get;
    SessionManager.get = (sessionId) => (sessionId === "test-session" ? session : null);

    const layer = new ScriptLayer(
        stream,
        ws,
        { name: "Test script", content: "echo test", osFilter: [] },
        "test-session",
    );

    t.after(() => {
        layer.destroy();
        SessionManager.get = originalGet;
    });

    return { layer, stream, ws, session };
};

test("replays buffered events without recording or replaying dialogs twice", (t) => {
    const { layer, ws } = createHarness(t);
    layer.suppressOutput = false;

    layer.broadcast(MSG.SCRIPT_START, { name: "Test script" });
    layer.processLine("NEXTERM_STEP:Installing packages");
    layer.processLine('NEXTERM_SUMMARY:Deployment:"Server" "web-01"');

    assert.equal(layer.events.length, 2);
    assert.deepEqual(
        layer.events.map((message) => parse(message).type),
        [MSG.SCRIPT_START, MSG.STEP],
    );
    assert.equal(layer.pendingDialog.type, MSG.SUMMARY);
    assert.deepEqual(layer.pendingDialog.payload, {
        title: "Deployment",
        data: ["Server", "web-01"],
    });

    ws.sent = [];
    layer.createMessageHandler(ws);

    assert.deepEqual(
        ws.sent.map((message) => parse(message).type),
        [MSG.SCRIPT_START, MSG.STEP, MSG.SUMMARY],
    );
    assert.deepEqual(parse(ws.sent[2]), {
        type: MSG.SUMMARY,
        title: "Deployment",
        data: ["Server", "web-01"],
    });
});

test("replays every dialog type with its original payload", (t) => {
    const payloads = {
        [MSG.PROMPT]: {
            inputType: "password",
            variable: "PASSWORD",
            prompt: "Password required",
        },
        [MSG.CONFIRM]: {
            variable: "NEXTERM_CONFIRM_RESULT",
            prompt: "Continue?",
            inputType: "confirm",
        },
        [MSG.SUMMARY]: { title: "Summary", data: ["Key", "Value"] },
        [MSG.TABLE]: { title: "Table", data: ["Name,Status", "web-01,ok"] },
        [MSG.MSGBOX]: { title: "Notice", message: "Reboot required" },
    };

    const { layer, ws } = createHarness(t);

    for (const [type, payload] of Object.entries(payloads)) {
        layer.pendingDialog = { type, payload };
        ws.sent = [];

        layer.replayEvents(ws);

        assert.equal(ws.sent.length, 1);
        assert.deepEqual(parse(ws.sent[0]), { type, ...payload });
    }
});

test("routes responses to the PTY and clears the pending dialog", (t) => {
    const { layer, stream, ws } = createHarness(t);
    layer.running = true;
    layer.pending = {
        inputType: "confirm",
        variable: "NEXTERM_CONFIRM_RESULT",
        prompt: "Continue?",
    };
    layer.pendingDialog = {
        type: MSG.CONFIRM,
        payload: layer.pending,
    };
    layer.createMessageHandler(ws);

    ws.emit(
        "message",
        Buffer.from(
            SCRIPT_MAGIC +
                JSON.stringify({ type: MSG.INPUT_RESPONSE, value: "Yes" }),
        ),
    );
    assert.deepEqual(stream.written, ["Yes\r"]);
    assert.equal(layer.pending, null);
    assert.equal(layer.pendingDialog, null);
});

test("uses the prompt default and Ctrl-C cancellation", (t) => {
    const { layer, stream, ws } = createHarness(t);
    layer.running = true;
    layer.pending = { default: "fallback" };
    layer.pendingDialog = { type: MSG.PROMPT, payload: {} };
    layer.createMessageHandler(ws);

    ws.emit(
        "message",
        SCRIPT_MAGIC + JSON.stringify({ type: MSG.INPUT_RESPONSE }),
    );
    assert.deepEqual(stream.written, ["fallback\r"]);

    layer.pending = { default: "other" };
    layer.pendingDialog = { type: MSG.PROMPT, payload: {} };
    ws.emit(
        "message",
        SCRIPT_MAGIC + JSON.stringify({ type: MSG.INPUT_CANCELLED }),
    );

    assert.deepEqual(stream.written, ["fallback\r", "\x03"]);
    assert.equal(layer.pending, null);
    assert.equal(layer.pendingDialog, null);
});

test("ignores malformed and unsolicited responses but still cancels", (t) => {
    const { layer, stream, ws } = createHarness(t);
    layer.running = true;
    const handler = layer.createMessageHandler(ws);

    ws.emit("message", "plain text");
    ws.emit("message", SCRIPT_MAGIC + "not-json");
    ws.emit(
        "message",
        SCRIPT_MAGIC + JSON.stringify({ type: MSG.INPUT_RESPONSE, value: "x" }),
    );
    ws.emit(
        "message",
        SCRIPT_MAGIC + JSON.stringify({ type: MSG.INPUT_CANCELLED }),
    );

    assert.deepEqual(stream.written, ["\x03"]);
    assert.equal(handler instanceof Function, true);
    assert.equal(layer.handlers.size, 1);
});

test("keeps the replay buffer bounded to the newest 500 events", (t) => {
    const { layer, ws } = createHarness(t);
    layer.suppressOutput = false;

    for (let index = 0; index < 510; index++) {
        layer.processLine(`NEXTERM_INFO:message-${index}`);
    }

    assert.equal(layer.events.length, 500);
    assert.equal(parse(layer.events[0]).message, "message-10");
    assert.equal(parse(layer.events.at(-1)).message, "message-509");
    assert.equal(ws.sent.length, 510);
});

test("processes the final buffered dialog before ending the script", (t) => {
    const { layer, stream, ws } = createHarness(t);
    layer.running = true;
    layer.suppressOutput = false;
    layer.buffer = 'NEXTERM_SUMMARY:Final report:"Status" "success"';
    stream.on("data", layer.onData);
    stream.on("close", layer.onClose);

    layer.handleEnd(7, { flushBuffer: true });

    const messages = ws.sent.map(parse);
    assert.deepEqual(
        messages.map((message) => message.type),
        [MSG.SUMMARY, MSG.SCRIPT_END],
    );
    assert.deepEqual(messages[0], {
        type: MSG.SUMMARY,
        title: "Final report",
        data: ["Status", "success"],
    });
    assert.deepEqual(messages[1], {
        type: MSG.SCRIPT_END,
        exitCode: 7,
        success: false,
    });

    assert.equal(layer.running, false);
    assert.equal(layer.pending, null);
    assert.equal(layer.pendingDialog, null);
    assert.equal(layer.buffer, "");
    assert.deepEqual(
        layer.events.map((message) => parse(message).type),
        [MSG.SUMMARY, MSG.SCRIPT_END],
    );
    assert.equal(stream.listenerCount("data"), 0);

    const reconnected = new FakeWs();
    layer.replayEvents(reconnected);
    assert.deepEqual(
        reconnected.sent.map((message) => parse(message).type),
        [MSG.SUMMARY, MSG.SCRIPT_END],
    );
    assert.deepEqual(parse(reconnected.sent[0]), {
        type: MSG.SUMMARY,
        title: "Final report",
        data: ["Status", "success"],
    });
});

test("a closed stream ends the script only once and cleans up", (t) => {
    const { layer, ws } = createHarness(t);
    layer.running = true;
    layer.pending = { default: "x" };
    layer.pendingDialog = { type: MSG.PROMPT, payload: {} };

    layer.onClose(1);
    layer.onClose(2);

    assert.equal(layer.running, false);
    assert.equal(layer.pending, null);
    assert.equal(layer.pendingDialog, null);
    assert.deepEqual(
        ws.sent.map(parse).map((message) => message.type),
        [MSG.SCRIPT_END],
    );
});

test("does not process output after the script has ended", (t) => {
    const { layer, ws } = createHarness(t);
    layer.running = true;
    layer.onData("NEXTERM_INFO:before\n");
    layer.handleEnd(0);

    const count = ws.sent.length;
    layer.onData("NEXTERM_INFO:after\n");

    assert.equal(ws.sent.length, count);
});

test("suppresses host output until the script signals readiness", (t) => {
    const { layer, ws } = createHarness(t);
    layer.suppressOutput = true;

    layer.processLine("NEXTERM_INFO:hidden");
    assert.equal(ws.sent.length, 0);

    layer.processLine("\x1b[32mNEXTERM_READY\x1b[0m");
    layer.processLine("NEXTERM_INFO:visible");

    assert.deepEqual(ws.sent.map(parse), [
        { type: MSG.INFO, message: "visible" },
    ]);
});

test("honours a setup failure end marker before readiness", (t) => {
    const { layer, ws } = createHarness(t);
    layer.running = true;
    layer.suppressOutput = true;

    layer.processLine("NEXTERM_END:1");

    assert.equal(layer.running, false);
    assert.deepEqual(ws.sent.map(parse), [
        { type: MSG.SCRIPT_END, exitCode: 1, success: false },
    ]);
    assert.equal(layer.suppressOutput, true);
});

test("ignores lines after an end marker in the same chunk", (t) => {
    const { layer, ws } = createHarness(t);
    layer.running = true;
    layer.suppressOutput = false;

    layer.processOutput(
        "NEXTERM_INFO:before\nNEXTERM_END:0\nNEXTERM_INFO:after\n",
    );

    assert.deepEqual(
        ws.sent.map(parse).map((message) => message.type),
        [MSG.INFO, MSG.SCRIPT_END],
    );
    assert.equal(layer.running, false);
});

test("detects a sudo prompt in the same chunk as the readiness marker", (t) => {
    const { layer, ws } = createHarness(t);
    layer.running = true;
    layer.suppressOutput = true;

    layer.processOutput("host banner\nNEXTERM_READY\n[sudo] password for deploy: ");

    assert.equal(ws.sent.length, 1);
    const prompt = parse(ws.sent[0]);
    assert.equal(prompt.type, MSG.PROMPT);
    assert.equal(prompt.inputType, "password");
    assert.equal(prompt.variable, "SUDO_PASSWORD");
    assert.equal(prompt.isSudoPassword, true);
    assert.equal(layer.suppressOutput, false);
    assert.deepEqual(layer.pending, {
        default: "",
        inputType: "password",
        isSudoPassword: true,
        prompt: "Enter sudo password for deploy",
        variable: "SUDO_PASSWORD",
    });
});

test("uses an end marker in the final close buffer", (t) => {
    const { layer, ws } = createHarness(t);
    layer.running = true;
    layer.buffer = "NEXTERM_END:42";

    layer.onClose(1);

    assert.deepEqual(ws.sent.map(parse), [
        { type: MSG.SCRIPT_END, exitCode: 42, success: false },
    ]);
});

test("does not mistake protocol prompts containing a password word for sudo", (t) => {
    const { layer, ws } = createHarness(t);
    layer.running = true;
    layer.suppressOutput = false;

    layer.processOutput('NEXTERM_INPUT:PASSWORD:Enter password\\x3A\n');
    layer.processOutput('NEXTERM_SUMMARY:Password:"Status" "ok"\n');

    assert.deepEqual(ws.sent.map(parse), [
        {
            type: MSG.PROMPT,
            inputType: "input",
            variable: "PASSWORD",
            prompt: "Enter password:",
            default: "",
        },
        {
            type: MSG.SUMMARY,
            title: "Password",
            data: ["Status", "ok"],
        },
    ]);
    assert.equal(layer.pending.isSudoPassword, undefined);
});

test("waits for a split protocol line before detecting a sudo prompt", (t) => {
    const { layer, ws } = createHarness(t);
    layer.running = true;
    layer.suppressOutput = false;

    layer.processOutput("NEXTERM_INPUT:PASSWORD:Enter password:");
    assert.equal(ws.sent.length, 0);
    assert.equal(layer.pending, null);

    layer.processOutput("\n");
    const prompt = parse(ws.sent[0]);
    assert.equal(prompt.type, MSG.PROMPT);
    assert.equal(prompt.variable, "PASSWORD");
    assert.equal(prompt.isSudoPassword, undefined);
});

test("ends a cancellation before readiness even after the last upload command", (t) => {
    const { layer, stream, ws } = createHarness(t);
    layer.running = true;
    layer.suppressOutput = true;
    layer.commandQueue = ["chunk-one"];
    layer.commandIndex = 1;
    layer.createMessageHandler(ws);

    ws.emit(
        "message",
        SCRIPT_MAGIC + JSON.stringify({ type: MSG.INPUT_CANCELLED }),
    );

    assert.deepEqual(stream.written, ["\x03"]);
    assert.equal(layer.running, false);
    assert.equal(layer.cancelEndTimer, null);
    assert.deepEqual(ws.sent.map(parse), [
        { type: MSG.SCRIPT_END, exitCode: 130, success: false },
    ]);
});

test("synthesizes an end if a running script ignores cancellation", (t) => {
    t.mock.timers.enable({ apis: ["setTimeout"] });
    const { layer, stream, ws } = createHarness(t);
    layer.running = true;
    layer.suppressOutput = false;
    layer.createMessageHandler(ws);

    ws.emit(
        "message",
        SCRIPT_MAGIC + JSON.stringify({ type: MSG.INPUT_CANCELLED }),
    );

    assert.deepEqual(stream.written, ["\x03"]);
    assert.equal(layer.running, true);
    assert.notEqual(layer.cancelEndTimer, null);

    t.mock.timers.tick(3000);

    assert.equal(layer.running, false);
    assert.equal(layer.cancelEndTimer, null);
    assert.deepEqual(ws.sent.map(parse).at(-1), {
        type: MSG.SCRIPT_END,
        exitCode: 130,
        success: false,
    });
});

test("stops the upload queue when the user cancels", async (t) => {
    const { layer, stream, ws } = createHarness(t);
    layer.running = true;
    layer.commandQueue = ["chunk-one", "chunk-two", "chunk-three"];
    layer.commandIndex = 0;
    layer.writeNextCommand();
    layer.createMessageHandler(ws);

    ws.emit(
        "message",
        SCRIPT_MAGIC + JSON.stringify({ type: MSG.INPUT_CANCELLED }),
    );

    assert.deepEqual(stream.written, ["chunk-one\r", "\x03"]);
    assert.equal(layer.writeTimer, null);
    assert.equal(layer.running, false);
    assert.deepEqual(
        ws.sent.map(parse).map((message) => message.type),
        [MSG.SCRIPT_END],
    );

    await new Promise((resolve) => setTimeout(resolve, 90));
    assert.deepEqual(stream.written, ["chunk-one\r", "\x03"]);
});

test("rejects control messages from a read-only participant", (t) => {
    const { layer, stream, ws } = createHarness(t);
    layer.running = true;
    layer.pending = { variable: "VALUE" };
    layer.pendingDialog = { type: MSG.PROMPT, payload: {} };
    layer.createMessageHandler(ws, () => false);

    ws.emit(
        "message",
        SCRIPT_MAGIC + JSON.stringify({ type: MSG.INPUT_RESPONSE, value: "x" }),
    );
    ws.emit(
        "message",
        SCRIPT_MAGIC + JSON.stringify({ type: MSG.INPUT_CANCELLED }),
    );

    assert.deepEqual(stream.written, []);
    assert.notEqual(layer.pending, null);
});
