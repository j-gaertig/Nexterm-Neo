const { transformScript, getScriptCommands, processNextermLine, checkSudoPrompt, findNextermCommand, stripAnsi } = require("../utils/scriptUtils");
const SessionManager = require("./SessionManager");
const logger = require("../utils/logger");
const { createDecodedTextStream } = require("../utils/terminalStream");

const SCRIPT_MAGIC = "\x1F";
const MSG = {
    SCRIPT_START: "script_start", STEP: "step", PROMPT: "prompt", WARNING: "warning",
    INFO: "info", SUCCESS: "success", CONFIRM: "confirm", PROGRESS: "progress",
    SUMMARY: "summary", TABLE: "table", MSGBOX: "msgbox", SCRIPT_END: "script_end",
    INPUT_RESPONSE: "input_response", INPUT_CANCELLED: "input_cancelled"
};

const DIALOG_TYPES = new Set([MSG.PROMPT, MSG.CONFIRM, MSG.SUMMARY, MSG.TABLE, MSG.MSGBOX]);
const INFORMATIONAL_DIALOG_TYPES = new Set([MSG.SUMMARY, MSG.TABLE, MSG.MSGBOX]);
const MAX_REPLAY_EVENTS = 500;
const CANCEL_END_GRACE_MS = 3000;

class ScriptLayer {
    constructor(stream, ws, script, sessionId) {
        this.stream = stream;
        this.sessionId = sessionId;
        this.script = script;
        this.step = 1;
        this.pending = null;
        this.pendingDialog = null;
        this.buffer = "";
        this.running = false;
        this.handlers = new Set();
        this.events = [];
        this.commandQueue = [];
        this.commandIndex = 0;
        this.writeTimer = null;
        this.cancelEndTimer = null;
        this.uploadCancelled = false;
        this.suppressOutput = true;
        this.ending = false;
        this.decoder = createDecodedTextStream((text) => this.processOutput(text));
        this.onData = this.onData.bind(this);
        this.onClose = this.onClose.bind(this);
    }

    rememberEvent(type, payload = {}) {
        const msg = SCRIPT_MAGIC + JSON.stringify({ ...payload, type });
        this.events.push(msg);
        if (this.events.length > MAX_REPLAY_EVENTS) {
            this.events.splice(0, this.events.length - MAX_REPLAY_EVENTS);
        }
    }

    broadcast(type, payload = {}) {
        const msg = SCRIPT_MAGIC + JSON.stringify({ ...payload, type });
        if (!DIALOG_TYPES.has(type)) this.rememberEvent(type, payload);
        const session = SessionManager.get(this.sessionId);
        if (session) for (const ws of session.connectedWs) ws.readyState === ws.OPEN && ws.send(msg);
    }

    replayEvents(ws) {
        for (const msg of this.events) ws.readyState === ws.OPEN && ws.send(msg);
        if (this.pendingDialog) {
            const { type, payload } = this.pendingDialog;
            const msg = SCRIPT_MAGIC + JSON.stringify({ ...payload, type });
            ws.readyState === ws.OPEN && ws.send(msg);
        }
    }

    start() {
        this.running = true;
        logger.info("Script starting", { sessionId: this.sessionId, name: this.script.name });
        this.broadcast(MSG.SCRIPT_START, { name: this.script.name });
        
        let osFilter = this.script.osFilter;
        if (typeof osFilter === "string") {
            try { osFilter = JSON.parse(osFilter); } catch { osFilter = []; }
        }
        const platform = Array.isArray(osFilter) && osFilter.some(os => typeof os === "string" && os.toLowerCase().includes("windows")) ? "windows" : "linux";
        const { b64 } = transformScript(this.script.content, platform);
        this.commandQueue = getScriptCommands(b64, platform);
        this.commandIndex = 0;
        
        this.stream.on("data", this.onData);
        this.stream.on("close", this.onClose);

        this.writeNextCommand();
    }

    writeNextCommand() {
        if (!this.running || this.uploadCancelled) return;
        if (this.commandIndex < this.commandQueue.length) {
            const cmd = this.commandQueue[this.commandIndex++];
            this.stream.write(cmd + "\r");
            
            if (this.commandIndex < this.commandQueue.length) {
                this.writeTimer = setTimeout(() => {
                    this.writeTimer = null;
                    this.writeNextCommand();
                }, 50);
            }
        }
    }

    clearWriteTimer() {
        if (this.writeTimer) {
            clearTimeout(this.writeTimer);
            this.writeTimer = null;
        }
    }

    onData(data) {
        if (this.running) this.decoder.write(data);
    }

    processOutput(output) {
        if (!this.running) return;
        this.buffer += output;
        const lines = this.buffer.split("\n");
        this.buffer = lines.pop() || "";

        for (const line of lines) {
            if (!this.running) {
                this.buffer = "";
                return;
            }
            if (!this.suppressOutput) {
                // Protocol lines may legitimately contain words like
                // "password:"; never classify them as sudo prompts.
                const command = processNextermLine(line);
                if (command) {
                    this.handleCommand(command);
                    continue;
                }
                const sudo = checkSudoPrompt(line);
                if (sudo) {
                    this.showSudoPrompt(sudo);
                    return;
                }
            }
            this.processLine(line);
        }

        if (!this.running) {
            this.buffer = "";
            return;
        }
        if (!this.suppressOutput && !findNextermCommand(this.buffer)) {
            // A partial NEXTERM directive may be split across chunks. Wait for
            // its newline instead of mistaking "Password:" for a sudo prompt.
            const sudo = checkSudoPrompt(this.buffer);
            if (sudo) this.showSudoPrompt(sudo);
        }
    }

    showSudoPrompt(sudo) {
        const payload = { inputType: "password", ...sudo };
        this.pending = payload;
        this.pendingDialog = { type: MSG.PROMPT, payload };
        this.buffer = "";
        this.broadcast(MSG.PROMPT, payload);
    }

    processLine(line) {
        if (this.suppressOutput) {
            if (stripAnsi(line).trim() === "NEXTERM_READY") {
                this.suppressOutput = false;
                return;
            }
            const hidden = processNextermLine(line);
            if (hidden?.type === "end") this.handleEnd(hidden.exitCode);
            return;
        }
        const cmd = processNextermLine(line);
        if (cmd) this.handleCommand(cmd);
    }

    handleCommand(cmd) {
        switch (cmd.type) {
            case "input": case "select":
                this.pending = cmd;
                this.pendingDialog = {
                    type: MSG.PROMPT,
                    payload: { inputType: cmd.type, variable: cmd.variable, prompt: cmd.prompt, default: cmd.default, options: cmd.options },
                };
                this.broadcast(MSG.PROMPT, this.pendingDialog.payload);
                break;
            case "step": this.broadcast(MSG.STEP, { number: this.step++, description: cmd.description }); break;
            case "warning": this.broadcast(MSG.WARNING, { message: cmd.message }); break;
            case "info": this.broadcast(MSG.INFO, { message: cmd.message }); break;
            case "success": this.broadcast(MSG.SUCCESS, { message: cmd.message }); break;
            case "confirm":
                this.pending = { variable: "NEXTERM_CONFIRM_RESULT", prompt: cmd.message, inputType: "confirm" };
                this.pendingDialog = { type: MSG.CONFIRM, payload: this.pending };
                this.broadcast(MSG.CONFIRM, this.pending);
                break;
            case "progress": this.broadcast(MSG.PROGRESS, { percentage: cmd.percentage, message: cmd.message || "" }); break;
            case "summary":
                this.pending = { variable: "NEXTERM_SUMMARY_RESULT", inputType: "summary" };
                this.pendingDialog = { type: MSG.SUMMARY, payload: { title: cmd.title, data: cmd.data } };
                this.broadcast(MSG.SUMMARY, this.pendingDialog.payload);
                break;
            case "table":
                this.pending = { variable: "NEXTERM_TABLE_RESULT", inputType: "table" };
                this.pendingDialog = { type: MSG.TABLE, payload: { title: cmd.title, data: cmd.data } };
                this.broadcast(MSG.TABLE, this.pendingDialog.payload);
                break;
            case "msgbox":
                this.pending = { variable: "NEXTERM_MSGBOX_RESULT", inputType: "msgbox" };
                this.pendingDialog = { type: MSG.MSGBOX, payload: { title: cmd.title, message: cmd.message } };
                this.broadcast(MSG.MSGBOX, this.pendingDialog.payload);
                break;
            case "end": this.handleEnd(cmd.exitCode); break;
        }
    }

    createMessageHandler(ws, canWrite = () => true) {
        const handler = (msg) => {
            if (!this.running || !canWrite()) return;
            const str = msg.toString();
            if (!str.startsWith(SCRIPT_MAGIC)) return;
            try {
                const data = JSON.parse(str.slice(1));
                if (data.type === MSG.INPUT_RESPONSE && this.pending) {
                    this.stream.write((data.value || this.pending.default || "") + "\r");
                    this.pending = null;
                    this.pendingDialog = null;
                } else if (data.type === MSG.INPUT_CANCELLED) {
                    const uploadIncomplete = this.commandIndex < this.commandQueue.length;
                    this.uploadCancelled = true;
                    this.clearWriteTimer();
                    this.pending = null;
                    this.pendingDialog = null;
                    this.stream.write("\x03");
                    if (this.suppressOutput || uploadIncomplete) {
                        // The script never reached READY, so the remote wrapper
                        // cannot emit a reliable end marker.
                        this.handleEnd(130);
                    } else {
                        // Give the remote wrapper a chance to report its real
                        // exit code, but never leave the UI stuck if Ctrl-C is
                        // ignored or the shell discards the pending line.
                        if (this.cancelEndTimer) clearTimeout(this.cancelEndTimer);
                        this.cancelEndTimer = setTimeout(
                            () => this.handleEnd(130),
                            CANCEL_END_GRACE_MS,
                        );
                    }
                }
            } catch (e) {}
        };
        ws.on("message", handler);
        this.handlers.add({ ws, handler });
        this.replayEvents(ws);
        return handler;
    }

    removeMessageHandler(ws) {
        for (const entry of this.handlers) {
            if (entry.ws === ws) { ws.removeListener("message", entry.handler); this.handlers.delete(entry); break; }
        }
    }

    handleEnd(exitCode, { flushBuffer = false } = {}) {
        if (!this.running || this.ending) return;
        this.ending = true;
        this.decoder.end();
        this.running = false;
        this.clearWriteTimer();
        if (this.cancelEndTimer) {
            clearTimeout(this.cancelEndTimer);
            this.cancelEndTimer = null;
        }
        if (flushBuffer && this.buffer.trim()) {
            const finalCommand = processNextermLine(this.buffer);
            if (finalCommand?.type === "end") exitCode = finalCommand.exitCode;
            else this.processLine(this.buffer);
        }
        // A final summary/table/msgbox is informational and remains readable.
        // Remember it before the end marker so a reconnect can replay the
        // result in the same order the live client saw it.
        if (INFORMATIONAL_DIALOG_TYPES.has(this.pendingDialog?.type)) {
            this.rememberEvent(this.pendingDialog.type, this.pendingDialog.payload);
        }
        this.buffer = "";
        this.pending = null;
        this.pendingDialog = null;
        this.broadcast(MSG.SCRIPT_END, { exitCode, success: exitCode === 0 });
        logger.info("Script completed", { sessionId: this.sessionId, exitCode });
        this.stream.removeListener("data", this.onData);
        this.stream.removeListener("close", this.onClose);
    }

    onClose(code) { this.handleEnd(code, { flushBuffer: true }); }

    destroy() {
        this.clearWriteTimer();
        if (this.cancelEndTimer) {
            clearTimeout(this.cancelEndTimer);
            this.cancelEndTimer = null;
        }
        this.stream.removeListener("data", this.onData);
        this.stream.removeListener("close", this.onClose);
        for (const { ws, handler } of this.handlers) ws.removeListener("message", handler);
        this.handlers.clear();
        this.running = false;
        this.pending = null;
        this.pendingDialog = null;
    }
}

module.exports = { ScriptLayer, SCRIPT_MAGIC, MSG };
