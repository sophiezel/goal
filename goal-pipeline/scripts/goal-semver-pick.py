"""Pick highest stable SemVer tag from stdin (one tag per line)."""
import re
import sys

PRERELEASE = re.compile(r"-(rc|beta|alpha|pre)(\.|$)", re.I)


def parse(tag: str):
    t = tag.strip()
    if t.endswith("^{}"):
        t = t[:-3]
    if t.startswith("refs/tags/"):
        t = t.rsplit("/", 1)[-1]
    if not t.startswith("v"):
        return None
    body = t[1:]
    if PRERELEASE.search(body):
        return None
    m = re.match(r"^(\d+)\.(\d+)\.(\d+)(.*)$", body)
    if not m:
        return None
    major, minor, patch = int(m.group(1)), int(m.group(2)), int(m.group(3))
    return (major, minor, patch, t)


def main() -> int:
    best = None
    best_name = None
    for line in sys.stdin:
        p = parse(line)
        if p is None:
            continue
        if best is None or p[:3] > best[:3]:
            best = p
            best_name = p[3]
    if best_name:
        print(best_name)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
