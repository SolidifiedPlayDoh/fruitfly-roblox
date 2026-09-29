# Restore the fruit-fly place

The fly game lived in an **unsaved** Studio session (`Place1`). Reinstalling Studio launched a fresh app, so that in-memory place is gone. Scripts are saved here.

Python brain is still at `~/projects/fruitfly-roblox` (`uv run fruitfly-roblox`).

## In Studio

1. File → New → Baseplate
2. Avatar → Rig Builder → R6 dummy
3. Rename the dummy to **Rig**
4. Tell the agent the place is open (or paste the two scripts below)

- Server: `studio/FlyBrainServer.server.lua` → ServerScriptService
- Client: `studio/FlyBrainCamera.client.lua` → StarterPlayer.StarterPlayerScripts

Save the place to disk (`File → Save`) so this does not happen again.
