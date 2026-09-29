from __future__ import annotations

import argparse

from fruitfly_roblox.chat import FlyTalk
from fruitfly_roblox.malecns import MaleCNSFly
from fruitfly_roblox.server import BrainHttp


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Run the MaleCNS fruit-fly brain and let it drive the Roblox Rig."
    )
    parser.add_argument("--port", type=int, default=8765)
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    fly = MaleCNSFly()
    talk = FlyTalk()
    BrainHttp(fly.see, chat=talk.reply, port=args.port, preview=fly).start()


if __name__ == "__main__":
    main()
