#!/usr/bin/env python3
"""TCP bridge for cmux: socket proxy + tmux-compat command executor.

Port 19876: Relays JSON-RPC to cmux Unix socket (for direct API calls)
Port 19877: Executes tmux commands on the host (for tmux shim)
  - split-window: uses socket API directly (surface.split + surface.send_text)
  - other commands: forwarded to cmux __tmux-compat

Usage:
    python3 cmux-bridge.py [--port 19876] [--tmux-port 19877] [--project-dir .]
"""

import argparse
import json
import os
import re
import shutil
import socket
import subprocess
import threading
import time
import sys


def relay(src: socket.socket, dst: socket.socket):
    try:
        while True:
            data = src.recv(4096)
            if not data:
                break
            dst.sendall(data)
    except OSError:
        pass
    finally:
        try:
            dst.shutdown(socket.SHUT_WR)
        except OSError:
            pass


def handle_socket_client(client: socket.socket, unix_path: str):
    """Relay JSON-RPC to cmux Unix socket."""
    try:
        unix = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        unix.connect(unix_path)
        t1 = threading.Thread(target=relay, args=(client, unix), daemon=True)
        t2 = threading.Thread(target=relay, args=(unix, client), daemon=True)
        t1.start()
        t2.start()
        t1.join()
        t2.join()
    except OSError as e:
        print(f"bridge[socket]: error: {e}", file=sys.stderr)
    finally:
        client.close()
        try:
            unix.close()
        except Exception:
            pass


# Global config set by main()
_project_dir = "."
_socket_path = ""
_cmux_bin = ""


def cmux_socket_rpc(method: str, params: dict) -> dict:
    """Send a JSON-RPC request to cmux socket and return the response."""
    req = json.dumps({"id": f"bridge-{time.time()}", "method": method, "params": params})
    try:
        s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        s.settimeout(10)
        s.connect(_socket_path)
        s.sendall((req + "\n").encode("utf-8"))
        s.shutdown(socket.SHUT_WR)

        data = b""
        while True:
            chunk = s.recv(4096)
            if not chunk:
                break
            data += chunk
        s.close()
        return json.loads(data.decode("utf-8"))
    except Exception as e:
        print(f"bridge[rpc]: error: {e}", file=sys.stderr)
        return {"ok": False, "error": str(e)}


def rewrite_container_command(cmd_str: str) -> str:
    """Rewrite a container command string to run via cpod on the host.

    Input:  cd /workspace && env K=V K=V /usr/local/bin/claude --agent-id ...
    Output: cd /host/project && cpod run --teams -- --agent-id ...
    """
    cmd_str = cmd_str.replace("/workspace", _project_dir)

    cmd_str = re.sub(
        r"env\s+(?:\S+=\S+\s+)*/usr/local/bin/claude\b",
        "cpod run --teams --",
        cmd_str,
    )

    cmd_str = cmd_str.replace("/usr/local/bin/claude", "cpod run --teams --")

    return cmd_str


def rewrite_send_keys_args(args: list[str]) -> list[str]:
    """Rewrite container paths in send-keys text arguments.

    send-keys format: send-keys [-t target] text... [Enter]
    The text args after -t target contain the command to rewrite.
    """
    new_args = ["send-keys"]
    i = 1
    while i < len(args):
        if args[i] == "-t" and i + 1 < len(args):
            new_args.append(args[i])
            new_args.append(args[i + 1])
            i += 2
            continue
        # Rewrite remaining args (text content)
        new_args.append(rewrite_container_command(args[i]))
        i += 1

    print(f"bridge[send-keys]: rewritten args", file=sys.stderr)
    return new_args


def handle_split_window(args: list[str]) -> dict:
    """Handle split-window via cmux socket API (bypasses __tmux-compat)."""
    direction = "right"
    command_parts = []
    print_format = ""
    i = 0
    while i < len(args):
        arg = args[i]
        if arg == "-h":
            direction = "right"
        elif arg == "-v":
            direction = "down"
        elif arg == "-t":
            i += 1  # skip target
        elif arg == "-P":
            pass
        elif arg == "-F":
            i += 1
            if i < len(args):
                print_format = args[i]
        elif arg == "--":
            command_parts = args[i + 1:]
            break
        i += 1

    # Create split via socket API
    result = cmux_socket_rpc("surface.split", {"direction": direction})
    print(f"bridge[split]: surface.split({direction}) -> ok={result.get('ok')}", file=sys.stderr)

    if not result.get("ok"):
        return {
            "stdout": "",
            "stderr": f"Error: {result.get('error', 'split failed')}\n",
            "returncode": 1,
        }

    new_surface_id = result.get("result", {}).get("surface_id", "")
    new_pane_id = result.get("result", {}).get("pane_id", "")

    # If a command was provided, rewrite and send to the new pane
    if command_parts:
        raw_cmd = " ".join(command_parts)
        rewritten = rewrite_container_command(raw_cmd)
        print(f"bridge[split]: sending to new pane: {rewritten[:100]}...", file=sys.stderr)

        time.sleep(0.5)
        cmux_socket_rpc("surface.send_text", {
            "surface_id": new_surface_id,
            "text": rewritten + "\n",
        })

    # Return the new pane ID in tmux format
    stdout = ""
    if print_format:
        stdout = f"%{new_pane_id}\n"

    return {"stdout": stdout, "stderr": "", "returncode": 0}


def handle_tmux_client(client: socket.socket, cmux_bin: str):
    """Route tmux commands: split-window via socket API, rest via __tmux-compat."""
    try:
        data = b""
        while True:
            chunk = client.recv(4096)
            if not chunk:
                break
            data += chunk

        payload = data.decode("utf-8", errors="replace").strip()
        if not payload:
            client.sendall(b"")
            return

        try:
            msg = json.loads(payload)
            args = msg.get("args", [])
            extra_env = msg.get("env", {})
        except json.JSONDecodeError:
            args = payload.split()
            extra_env = {}

        # Route split-window to socket API (avoids "Surface not found")
        if args and args[0] == "split-window":
            print(f"bridge[tmux]: split-window -> using socket API", file=sys.stderr)
            response = json.dumps(handle_split_window(args[1:]))
            client.sendall(response.encode("utf-8"))
            return

        # Rewrite container paths in send-keys commands
        if args and args[0] == "send-keys":
            args = rewrite_send_keys_args(args)

        # All other commands go through __tmux-compat
        cmd = [cmux_bin, "__tmux-compat"] + args

        run_env = os.environ.copy()
        if extra_env:
            run_env.update(extra_env)

        print(f"bridge[tmux]: {' '.join(cmd)}", file=sys.stderr)

        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=30,
            env=run_env,
        )

        response = json.dumps({
            "stdout": result.stdout,
            "stderr": result.stderr,
            "returncode": result.returncode,
        })
        client.sendall(response.encode("utf-8"))

    except subprocess.TimeoutExpired:
        client.sendall(json.dumps({
            "stdout": "",
            "stderr": "timeout",
            "returncode": 124,
        }).encode("utf-8"))
    except OSError as e:
        print(f"bridge[tmux]: error: {e}", file=sys.stderr)
    finally:
        client.close()


def serve(port: int, handler, handler_arg, label: str):
    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server.bind(("127.0.0.1", port))
    server.listen(8)
    print(f"cmux-bridge[{label}]: listening on 127.0.0.1:{port}")

    try:
        while True:
            client, _ = server.accept()
            threading.Thread(
                target=handler,
                args=(client, handler_arg),
                daemon=True,
            ).start()
    except OSError:
        pass
    finally:
        server.close()


def main():
    global _project_dir, _socket_path, _cmux_bin

    default_sock = os.environ.get(
        "CMUX_SOCKET_PATH",
        os.path.expanduser("~/Library/Application Support/cmux/cmux.sock"),
    )

    default_cmux = os.environ.get(
        "CMUX_CLAUDE_TEAMS_CMUX_BIN",
        os.environ.get(
            "CMUX_BUNDLED_CLI_PATH",
            shutil.which("cmux") or "/Applications/cmux.app/Contents/Resources/bin/cmux",
        ),
    )

    parser = argparse.ArgumentParser(description="TCP bridge for cmux")
    parser.add_argument("--port", type=int, default=19876, help="Socket proxy port")
    parser.add_argument("--tmux-port", type=int, default=19877, help="tmux-compat port")
    parser.add_argument("--socket", default=default_sock)
    parser.add_argument("--cmux-bin", default=default_cmux)
    parser.add_argument("--project-dir", default=os.getcwd(),
                        help="Host project directory (replaces /workspace in commands)")
    args = parser.parse_args()

    _project_dir = os.path.abspath(args.project_dir)
    _socket_path = args.socket
    _cmux_bin = args.cmux_bin

    if not os.path.exists(args.socket):
        print(f"ERROR: socket not found: {args.socket}", file=sys.stderr)
        sys.exit(1)

    if not os.path.isfile(args.cmux_bin):
        print(f"ERROR: cmux binary not found: {args.cmux_bin}", file=sys.stderr)
        sys.exit(1)

    print(f"cmux-bridge: socket={args.socket}")
    print(f"cmux-bridge: cmux-bin={args.cmux_bin}")
    print(f"cmux-bridge: project-dir={_project_dir}")

    t_socket = threading.Thread(
        target=serve,
        args=(args.port, handle_socket_client, args.socket, "socket"),
        daemon=True,
    )
    t_socket.start()

    serve(args.tmux_port, handle_tmux_client, args.cmux_bin, "tmux-compat")


if __name__ == "__main__":
    main()
