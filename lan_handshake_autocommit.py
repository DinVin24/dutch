#!/usr/bin/env python3
"""
Run a lightweight host/client LAN handshake using Godot debug args.
If the handshake succeeds, stage/commit/push changes.
"""

from __future__ import annotations

import argparse
import subprocess
import sys
import threading
import time
from pathlib import Path
from queue import Queue


SUCCESS_MARKERS = (
    "NetworkManager: Successfully connected to server.",
    "NetworkManager: Player ",
)


def _stream_reader(stream, output_queue: Queue, prefix: str) -> None:
    try:
        for line in iter(stream.readline, ""):
            if not line:
                break
            text = line.rstrip("\n")
            output_queue.put(f"{prefix}{text}")
    finally:
        stream.close()


def _start_process(cmd: list[str], cwd: Path) -> tuple[subprocess.Popen, Queue]:
    proc = subprocess.Popen(
        cmd,
        cwd=str(cwd),
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        bufsize=1,
    )
    output_queue: Queue = Queue()
    reader = threading.Thread(
        target=_stream_reader,
        args=(proc.stdout, output_queue, ""),
        daemon=True,
    )
    reader.start()
    return proc, output_queue


def _drain_queue(output_queue: Queue, sink: list[str]) -> None:
    while True:
        try:
            sink.append(output_queue.get_nowait())
        except Exception:
            break


def _run_git(cmd: list[str], cwd: Path) -> int:
    print(f"[git] Running: {' '.join(cmd)}")
    result = subprocess.run(cmd, cwd=str(cwd), check=False)
    return result.returncode


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Run LAN handshake, then git add/commit/push if it passes."
    )
    parser.add_argument(
        "--godot-cmd",
        default="godot4",
        help="Godot executable/command (default: godot4).",
    )
    parser.add_argument(
        "--host-ip",
        default="127.0.0.1",
        help="Host IP for client connect target (default: 127.0.0.1).",
    )
    parser.add_argument(
        "--timeout-seconds",
        type=int,
        default=15,
        help="Max seconds to wait for handshake success.",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Run handshake only; skip git add/commit/push.",
    )
    args = parser.parse_args()

    repo_root = Path(__file__).resolve().parent

    host_cmd = [args.godot_cmd, "--path", ".", "--", "--host"]
    client_cmd = [
        args.godot_cmd,
        "--path",
        ".",
        "--",
        "--client",
        "--connect-to",
        args.host_ip,
    ]

    print("[handshake] Starting host:", " ".join(host_cmd))
    host_proc, host_out = _start_process(host_cmd, repo_root)
    time.sleep(2.0)

    print("[handshake] Starting client:", " ".join(client_cmd))
    client_proc, client_out = _start_process(client_cmd, repo_root)

    host_lines: list[str] = []
    client_lines: list[str] = []
    success = False
    deadline = time.time() + max(5, args.timeout_seconds)

    try:
        while time.time() < deadline and not success:
            _drain_queue(host_out, host_lines)
            _drain_queue(client_out, client_lines)

            all_output = "\n".join(host_lines + client_lines)
            success = any(marker in all_output for marker in SUCCESS_MARKERS)
            if success:
                break
            if host_proc.poll() is not None and client_proc.poll() is not None:
                break
            time.sleep(0.25)
    finally:
        for proc in (client_proc, host_proc):
            if proc.poll() is None:
                proc.terminate()
        for proc in (client_proc, host_proc):
            try:
                proc.wait(timeout=5)
            except subprocess.TimeoutExpired:
                proc.kill()

        _drain_queue(host_out, host_lines)
        _drain_queue(client_out, client_lines)

    if not success:
        print("[handshake] FAILED. No git changes were committed or pushed.")
        print("[handshake] Host output (tail):")
        for line in host_lines[-20:]:
            print("  " + line)
        print("[handshake] Client output (tail):")
        for line in client_lines[-20:]:
            print("  " + line)
        return 1

    print("[handshake] PASSED.")
    if args.dry_run:
        print("[handshake] Dry run enabled; skipping git add/commit/push.")
        return 0

    if _run_git(["git", "add", "."], repo_root) != 0:
        return 2
    if (
        _run_git(
            ["git", "commit", "-m", "Fix: LAN connectivity and networking handshake"],
            repo_root,
        )
        != 0
    ):
        return 3
    if _run_git(["git", "push"], repo_root) != 0:
        return 4

    print("[handshake] Git add/commit/push completed.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
