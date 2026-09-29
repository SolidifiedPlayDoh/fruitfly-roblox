# TypeSafe Jev vs a Fruit Fly Brain in a Roblox Maze

Two players race the same Roblox maze to an apple.

Video: https://youtu.be/0zY_yzrcF9c

**Fruit fly.** [MaleCNS v1.0](https://www.virtualflybrain.org), the published connectome of a male fruit fly: 166,700 neurons and 25.6 million connections, from Janelia / Cambridge / Google, loaded through [flybrain](https://pypi.org/project/flybrain/). The wiring stays frozen. Roblox raycasts drive the fly's own feature-detector cells, and a small readout turns spikes into walk and turn. Descending neurons do the moving: DNg100 walks, DNa02 steers, MDN reverses, DNp01 jumps.

**Jev.** [TypeSafe](https://typesafe.ai) System One, model `typesafe/jev-1.13`, through the OpenRouter Decisions API. Jev does not see the screen. Each call gets a ring of distances, the smell of the apple, and a faint trail of where that character already walked, then it picks a direction and how far to step.

The connectome weights are not in this repo. `flybrain` downloads them into `~/fly-data` on first launch (~260 MB). They stay under their own terms.

## Run the fruit fly

```bash
uv venv --python 3.12
uv pip install -e .
uv run fruitfly-roblox
```

Listens on `http://127.0.0.1:8765`. Wait until it prints `MaleCNS listening`. The first start compiles the simulator.

## Run Jev

Jev bills the OpenRouter account in `OPENROUTER_API_KEY`. Copy `.env.example` to `.env` and put your own key there. `.env` is not part of this repo. Money is spent only while Roblox is in Play and this process is answering.

```bash
uv run jev-roblox
```

Listens on `http://127.0.0.1:8766`.

## Roblox

The Studio place file is not in this repo. The scripts that drive the race are in `studio/`.

- `studio/FlyBrainServer.server.lua` drives the fruit fly (`Rig`).
- `studio/JevPilot.server.lua` drives Jev.
- Client scripts in `studio/` run the camera, wallet, leaderboard, and finish popup.

HttpService has to be enabled. The fruit fly character is the brown rig. Jev is the other character. Both stop when they reach the apple. Jev also stops calling the model then.

OBS browser sources, if you want the same overlays as the video:

- `http://127.0.0.1:8765/obs`
- `http://127.0.0.1:8765/obs/brain`
- `http://127.0.0.1:8766/obs/inputs`

## License

MIT. See [LICENSE](LICENSE).
