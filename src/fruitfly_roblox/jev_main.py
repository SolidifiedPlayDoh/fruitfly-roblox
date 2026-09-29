from __future__ import annotations

import argparse

from fruitfly_roblox.jev_pilot import DEFAULT_MODEL, JevPilot, api_key_from_env, serve


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Let Jev play as the grey Jev character. The fruit fly is a different process."
    )
    parser.add_argument("--port", type=int, default=8766)
    parser.add_argument("--hz", type=float, default=1.25, help="Max Jev decisions per second")
    parser.add_argument("--model", default=DEFAULT_MODEL)
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    pilot = JevPilot(api_key_from_env(), model=args.model, hz=args.hz)
    serve(pilot, port=args.port)


if __name__ == "__main__":
    main()
