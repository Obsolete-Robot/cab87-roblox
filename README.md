# cab87-roblox

Code-first Roblox starter for a **Crazy Taxi style** prototype using **Rojo + Luau + Git**.

## What is in this repo

- Procedural city generator (arterial-first roads + district-based buildings)
- Drivable arcade cab built from code
- Minimal HUD showing controls
- Rojo project mapping for Studio sync

## Requirements

- Roblox Studio
- Rojo plugin in Studio
- Rojo CLI installed (`rojo`)

## Run in Studio

1. Start Rojo server in this repo:
   - `rojo serve`
2. Open Roblox Studio.
3. Open or create a base place.
4. Connect via Rojo plugin to `default.project.json`.
5. Press Play.

You should spawn into a generated city and be able to drive the cab.

## Regenerate map in Studio (no Play required)

Open **View -> Command Bar** and run:

```lua
local g = require(game.ServerScriptService.cab87.MapGenerator)
g.Regenerate({
	seed = 12345,
	cityBlocks = 8,
	roadWidth = 34,
})
```

Use `g.Clear()` if you just want to remove the generated world.

### Optional: one-click Studio toolbar buttons (Generate/Clear)

This repo includes a plugin file at:
- `studio-plugin/Cab87MapTools.plugin.lua`

Fast install on Windows:
- Run `install-studio-plugin.bat` from repo root.

Manual install (if needed):
- Copy plugin to `%LOCALAPPDATA%\\Roblox\\Plugins\\Cab87MapTools.plugin.lua`

Then restart Studio. You will get these tools:

- **cab87** toolbar
  - **Generate Map**
  - **Clear Map**
- **cab87 roads** toolbar
  - **Road Editor** (opens a persistent docked panel)

Road Editor panel actions:
- New Spline
- Prev Spline
- Next Spline
- Curve Mode: Open/Closed (toggle)
- Add Point (Camera Hit)
- Add Point (From Selection)
- Select Nearest Point (Camera)
- Set Selected Y = Prev
- Set Selected Y = Next
- Set Selected Y = Avg
- Remove Selected Point
- Remove Last Point
- Snap Points To Terrain
- Rebuild Road (Mesh preferred, primitive fallback)
- Clear Road
- Auto Rebuild: On/Off (rebuilds as points move)

When you click **Generate Map**, check Studio Output for seed + generator version.

### Fast road-iteration workflow

1. Click **New Spline**.
   - This creates a new spline and keeps existing splines intact.
   - Use **Prev Spline** / **Next Spline** to switch active spline.
2. Use **Add Point** repeatedly to lay out a path.
3. Click **Snap Points** to drop points to terrain.
4. Click **Rebuild Road (Mesh)** to generate a smooth road ribbon (EditableMesh). If EditableMesh is unavailable, it falls back to primitive strips.
5. Press Play and test traversal.

## Controls

- Accelerate: `W` / `Up`
- Brake/Reverse: `S` / `Down`
- Steer: `A` / `D` or `Left` / `Right`

## Project structure

- `src/server/Main.server.lua` - runtime boot + cab simulation
- `src/server/MapGenerator.lua` - editor/runtime map generation module
- `src/client/Hud.client.lua` - basic on-screen controls hint
- `src/shared/Config.lua` - tuning values

## Notes

- This uses a scripted arcade controller (not Roblox default vehicle physics).
- Tune values in `src/shared/Config.lua`.
- V2 is being delivered in staged chunks. Current chunk adds arterial skeleton roads and Voronoi-style district zoning.
