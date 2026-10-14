"""CLI wrapper so desktop Dart can call yt_bridge.py via subprocess.

Usage: python cli.py <method> '<json-args>'
  method: getStream | search | artist | album
  Prints the JSON string result to stdout (errors -> non-zero exit).
Keep yt_bridge.py in this same directory (keep in sync with
android/app/src/main/python/yt_bridge.py).
"""
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from yt_bridge import call as bridge_call


def main():
    if len(sys.argv) < 2:
        sys.stderr.write("usage: cli.py <method> '<json-args>'\n")
        return 2
    method = sys.argv[1]
    try:
        args = json.loads(sys.argv[2]) if len(sys.argv) > 2 else {}
    except Exception as e:
        sys.stderr.write(f"bad args json: {e}\n")
        return 2
    try:
        out = bridge_call(method,
                          args.get("query", ""),
                          args.get("videoId", ""))
    except Exception as e:  # never let tracebacks hit stdout
        sys.stderr.write(f"bridge error: {e}\n")
        return 1
    sys.stdout.write(out if isinstance(out, str) else json.dumps(out))
    return 0


if __name__ == "__main__":
    sys.exit(main())
