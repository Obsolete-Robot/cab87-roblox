# cab87-roblox

Code-first Roblox starter for a **Crazy Taxi style** prototype using **Rojo + Luau + Git**.

## What is in this repo

- Procedural city generator (arterial-first roads + district-based buildings)
- Drivable arcade cab built from code
- Minimal HUD showing controls
- Rojo project mapping for Studio sync

## Planning

- [Milestone roadmap](docs/MILESTONE_ROADMAP.md)
- [Architecture plan](docs/ARCHITECTURE_PLAN.md)

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
- `studio-plugin/Cab87RoadGraphBuilder.plugin.lua`
- `studio-plugin/Cab87RoadCurveTools.plugin.lua` (legacy spline editor/reference)

Fast install on Windows:
- Run `install-studio-plugin.bat` from repo root.

Manual install (if needed):
- Copy plugin to `%LOCALAPPDATA%\\Roblox\\Plugins\\Cab87MapTools.plugin.lua`

Then restart Studio. You will get these tools:

- **cab87** toolbar
  - **Generate Map**
  - **Clear Map**
- **cab87 roads** toolbar
  - **Road Graph Builder** (supported graph JSON importer/mesh builder)
  - **Road Editor** (legacy spline editor/reference)

Road Graph Builder panel actions:
- Import Graph JSON exported from `tools/intersection-visualizer`.
- Rebuild Preview Mesh from `Cab87RoadEditor/RoadGraph`.
- Bake Runtime Geometry to create persistent road, sidewalk, crosswalk, and collision geometry for the current map.
- Fork As New Map to clear baked output before baking a new level from the same graph.
- Set/select cab company and player spawn markers.

The legacy Road Editor still opens and can be used for reference, but new authored maps should use the graph workflow.

When you click **Generate Map**, check Studio Output for seed + generator version.

### Fast graph-road workflow

1. Run the graph visualizer:
   - `cd tools/intersection-visualizer`
   - `npm ci`
   - `npm run dev`
2. Open `http://localhost:3000`, author the road graph, and export JSON.
3. In Studio, open **Road Graph Builder**.
4. Set **Import Y** for the Roblox plane height.
5. Set **Map ID** to a stable level id such as `downtown_v1`.
6. Click **Import Graph JSON**.
   - The plugin imports to `Cab87RoadEditor/RoadGraph`.
   - It builds a disposable preview mesh for quick inspection.
7. Click **Bake Runtime Geometry**.
   - If Studio allows programmatic mesh uploads, the plugin uploads or updates permanent mesh assets and stores their IDs in `Cab87RoadEditor/RoadGraphAssets`.
   - If Studio reports that `CreateAssetAsync` is not available, the plugin builds persistent saved `WedgePart` geometry under `RoadGraphBakedRuntime` instead. This creates no package or mesh asset IDs, but it survives save/reopen and Play.
   - The bake clears disposable preview mesh folders so Play mode does not render overlapping preview/runtime geometry.
8. Press Play and test traversal.

For an update to the same map, keep the same **Map ID** and click **Bake Runtime Geometry** again. Asset-backed bakes update existing mesh asset versions when Roblox exposes that API; fallback bakes replace the saved `RoadGraphBakedRuntime` model in the place. For a new level, click **Fork As New Map** or set a new **Map ID** before baking so the new map gets separate baked output.

### Legacy spline workflow

1. Click **New Spline**.
   - This creates a new spline and keeps existing splines intact.
   - Use **Prev Spline** / **Next Spline** to switch active spline.
   - Set **Road Width** per spline before or after placing points.
2. Use **Add Point** repeatedly to lay out a path.
3. Click **Snap Points** to drop points to terrain.
4. Click **Rebuild Road (Mesh)** to generate roads from **all splines** as one unified network (EditableMesh preferred, primitive fallback).
   - Nearby spline endpoints are welded.
   - Crossings are inserted into both splines and meshed into the unified road surface.
   - Crossings only become intersections when the curves are close in 3D space, so raised overpasses can pass above lower roads.
   - Disconnected road layers are baked into separate MeshParts, so overpasses are not forced into the same collision mesh as lower roads.
   - Spline control points are the durable source of truth. The plugin rebuilds stale generated MeshParts on load; Play mode keeps server collision invisible and has each client rebuild the clean unified visual mesh from spline data.
   - **Wireframe Mesh** can be toggled on to inspect generated mesh edges.
5. Press Play and test traversal.

### Legacy web curve authoring workflow

Use the static browser tool in `tools/road-curve-editor` when you want to trace a 2D reference and import it into Studio:

1. Open `tools/road-curve-editor/index.html`, or run `tools/road-curve-editor/run.bat`.
2. Import a trace image and lay out one or more splines in the browser tool.
   - Open **Soft Select** or press **S** to drag broad regions of spline points and junctions with radius falloff.
3. Export `cab87-road-curves.json` to save the full browser session, including the trace image and its transform.
4. Reopen that same file in the browser tool with **Import Session JSON** if you want to resume editing later.
5. In Studio, set **Import Plane Y** in the Road Editor.
6. Click **Import Curve JSON (Append)** to add to the current spline set, or **Import Curve JSON (Replace)** to replace the current authored splines while keeping markers such as `CabCompanyNode`.
7. The plugin imports the control points into `Cab87RoadEditor/Splines` and rebuilds the road network from the imported data.

### Cab company and player spawn placement

For authored-road maps, use **Set Cab Company Node From Camera** in the Road Graph Builder to place `Cab87RoadEditor/Markers/CabCompanyNode`. At runtime, that marker becomes the cab company location and the starter cab spawns at that marker.

Player spawning is left to normal Roblox `SpawnLocation` parts by default, so you can manually place a spawn plate wherever the player should start. Set `playerUseCabCompanySpawn = true` in `src/shared/MapConfig.lua` only if you want the server to force characters to the generated cab-company spawn marker.

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
- V2 is being delivered in staged chunks. Current chunks include arterial skeleton roads, district zoning, and multi-spline road network meshing with intersections.
