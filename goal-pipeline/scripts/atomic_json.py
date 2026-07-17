#!/usr/bin/env python3
"""Atomic JSON write (temp + os.replace) and optional state-dir flock."""
from __future__ import annotations

import json
import os
import sys
import tempfile
from contextlib import contextmanager
from typing import Any, Iterator


def write_json_atomic(path: str, data: Any, *, indent: int = 2, ensure_ascii: bool = False) -> None:
    """Write JSON atomically via temp file in the same directory + os.replace."""
    parent = os.path.dirname(os.path.abspath(path)) or "."
    os.makedirs(parent, exist_ok=True)
    fd, tmp = tempfile.mkstemp(prefix=".atomic-", suffix=".json", dir=parent)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            json.dump(data, f, indent=indent, ensure_ascii=ensure_ascii)
            f.write("\n")
            f.flush()
            os.fsync(f.fileno())
        os.replace(tmp, path)
    except Exception:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise


@contextmanager
def state_lock(state_dir: str, timeout_sec: float = 30.0) -> Iterator[None]:
    """Minimal flock on <state_dir>/.lock. No-op if flock unavailable."""
    os.makedirs(state_dir, exist_ok=True)
    lock_path = os.path.join(state_dir, ".lock")
    try:
        import fcntl  # Unix
    except ImportError:
        yield
        return

    import time

    fh = open(lock_path, "a+", encoding="utf-8")
    deadline = time.time() + timeout_sec
    while True:
        try:
            fcntl.flock(fh.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
            break
        except BlockingIOError:
            if time.time() >= deadline:
                fh.close()
                raise TimeoutError(f"state lock timeout: {lock_path}")
            time.sleep(0.05)
    try:
        fh.seek(0)
        fh.truncate()
        fh.write(f"pid={os.getpid()}\n")
        fh.flush()
        yield
    finally:
        try:
            fcntl.flock(fh.fileno(), fcntl.LOCK_UN)
        except OSError:
            pass
        fh.close()


def write_state_atomic(state_path: str, state: dict[str, Any]) -> None:
    """Lock state dir (if possible) and atomically rewrite state.json."""
    state_dir = os.path.dirname(os.path.abspath(state_path)) or "."
    with state_lock(state_dir):
        write_json_atomic(state_path, state)


def main() -> int:
    # CLI: atomic_json.py write <path> <json-string-or-->
    if len(sys.argv) < 3 or sys.argv[1] != "write":
        print("Usage: atomic_json.py write <path> '<json>'", file=sys.stderr)
        return 2
    path = sys.argv[2]
    raw = sys.argv[3] if len(sys.argv) > 3 else sys.stdin.read()
    data = json.loads(raw)
    if path.endswith("state.json"):
        write_state_atomic(path, data)
    else:
        write_json_atomic(path, data)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
