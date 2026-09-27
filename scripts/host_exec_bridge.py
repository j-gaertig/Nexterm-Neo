import asyncio
import json
import os
import signal
import sys

SOCKET_PATH = os.environ.get("NEXTERM_HOST_EXEC_SOCKET", "/run/nexterm-host-exec/host-exec.sock")
COMMAND_MAX = 2000
OUTPUT_MAX = 64 * 1024
TIMEOUT_MAX = 120000
WORKERS_MAX = 8
active = 0
active_lock = asyncio.Lock()


async def capture_stream(stream):
    captured = bytearray()
    truncated = False
    while True:
        chunk = await stream.read(8192)
        if not chunk:
            break
        room = OUTPUT_MAX - len(captured)
        if room > 0:
            captured.extend(chunk[:room])
        if len(chunk) > room:
            truncated = True
    return bytes(captured).decode("utf-8", errors="replace"), truncated


async def collect_process(process):
    stdout_task = asyncio.create_task(capture_stream(process.stdout))
    stderr_task = asyncio.create_task(capture_stream(process.stderr))
    await process.wait()
    stdout, stderr = await asyncio.gather(stdout_task, stderr_task)
    return stdout[0], stderr[0], stdout[1], stderr[1]


async def write_result(writer, result):
    writer.write((json.dumps(result, separators=(",", ":")) + "\n").encode("utf-8"))
    await writer.drain()


async def stop_process(process):
    try:
        os.killpg(process.pid, signal.SIGKILL)
    except ProcessLookupError:
        pass
    except PermissionError:
        if process.returncode is None:
            process.kill()
    if process.returncode is None:
        await process.wait()


async def collect_after_stop(process, task):
    try:
        return await asyncio.wait_for(asyncio.shield(task), timeout=2)
    except asyncio.TimeoutError:
        for descriptor in (1, 2):
            transport = process._transport.get_pipe_transport(descriptor)
            if transport is not None:
                transport.close()
        task.cancel()
        await asyncio.gather(task, return_exceptions=True)
        return "", "", True, True


async def handle_client(reader, writer):
    global active
    process = None
    communicate_task = None
    disconnect_task = None
    active_counted = False

    try:
        line = await asyncio.wait_for(reader.readline(), timeout=5)
        if not line or len(line) > COMMAND_MAX * 4 + 1024:
            raise ValueError("Invalid host command request")
        request = json.loads(line)
        if request.get("health") is True:
            await write_result(writer, {"available": True})
            return
        command = request.get("command")
        if not isinstance(command, str) or not command.strip() or len(command) > COMMAND_MAX:
            raise ValueError("Host command must contain 1 to 2000 characters")
        timeout_ms = request.get("timeoutMs", TIMEOUT_MAX)
        if not isinstance(timeout_ms, (int, float)) or isinstance(timeout_ms, bool):
            raise ValueError("Invalid host command timeout")
        timeout_ms = min(max(int(timeout_ms), 1), TIMEOUT_MAX)

        async with active_lock:
            busy = active >= WORKERS_MAX
            if not busy:
                active += 1
                active_counted = True
        if busy:
            await write_result(writer, {"success": False, "exitCode": -1, "errorMessage": "Host command bridge is busy", "stdout": "", "stderr": "", "truncated": False})
            return

        process = await asyncio.create_subprocess_shell(
            command,
            executable="/bin/sh",
            cwd=os.environ.get("NEXTERM_HOST_EXEC_CWD", os.getcwd()),
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
            start_new_session=True,
        )
        communicate_task = asyncio.create_task(collect_process(process))
        disconnect_task = asyncio.create_task(reader.read(1))
        done, _ = await asyncio.wait(
            {communicate_task, disconnect_task},
            timeout=timeout_ms / 1000,
            return_when=asyncio.FIRST_COMPLETED,
        )
        if disconnect_task in done and communicate_task not in done:
            await stop_process(process)
            await collect_after_stop(process, communicate_task)
            return
        if communicate_task not in done:
            await stop_process(process)
            out, err, out_truncated, err_truncated = await collect_after_stop(process, communicate_task)
            await write_result(writer, {"success": False, "exitCode": -1, "errorMessage": "Host command timed out", "stdout": out, "stderr": err, "truncated": out_truncated or err_truncated})
            return

        out, err, out_truncated, err_truncated = communicate_task.result()
        await write_result(writer, {
            "success": process.returncode == 0,
            "exitCode": process.returncode,
            "errorMessage": None,
            "stdout": out,
            "stderr": err,
            "truncated": out_truncated or err_truncated,
        })
    except Exception as err:
        if process is not None:
            await stop_process(process)
        try:
            await write_result(writer, {"success": False, "exitCode": -1, "errorMessage": str(err), "stdout": "", "stderr": "", "truncated": False})
        except (ConnectionError, BrokenPipeError):
            pass
    finally:
        for task in (communicate_task, disconnect_task):
            if task is not None and not task.done():
                task.cancel()
        if active_counted:
            async with active_lock:
                active -= 1
        writer.close()
        try:
            await writer.wait_closed()
        except (ConnectionError, BrokenPipeError):
            pass


async def main():
    os.makedirs(os.path.dirname(SOCKET_PATH), mode=0o700, exist_ok=True)
    try:
        os.unlink(SOCKET_PATH)
    except FileNotFoundError:
        pass
    old_umask = os.umask(0o177)
    try:
        server = await asyncio.start_unix_server(handle_client, path=SOCKET_PATH, backlog=WORKERS_MAX)
    finally:
        os.umask(old_umask)
    os.chmod(SOCKET_PATH, 0o600)
    async with server:
        await server.serve_forever()


if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        sys.exit(0)
