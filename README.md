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
- [Road-Maker sync and mesher parity](docs/ROAD_MAKER_SYNC.md)

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
- `studio-plugin/Cab87ManagerTools.plugin.lua`

Fast install on Windows:
- Run `install-studio-plugin.bat` from repo root.

Manual install (if needed):
- Copy the plugin files to `%LOCALAPPDATA%\\Roblox\\Plugins`.

Then restart Studio. You will get these tools:

- **cab87** toolbar
  - **Generate Map**
  - **Clear Map**
- **Cab87** toolbar
  - **Add Manager**
  - **Add Cab Spawn**, **Add Refuel**, **Add Service**, **Add Player Spawn**
- **cab87 roads** toolbar
  - **Road Graph Builder** (supported graph JSON importer/mesh builder)

Road Graph Builder panel actions:
- Clear All Road Data to empty `Cab87RoadEditor` before importing a fresh road.
- Import Graph JSON exported from `tools/intersection-visualizer`.
- Rebuild Preview Mesh from `Cab87RoadEditor/RoadGraph`.
- Bake Runtime Geometry to create persistent road, sidewalk, crosswalk, and collision geometry for the current map.
- Fork As New Map to clear baked output before baking a new level from the same graph.
- Set/select cab spawn, refuel, service, and player spawn markers.

Use **Cab87 -> Add Manager** to create `Workspace.Cab87Manager`. The manager panel can toggle passengers, shift mode, UI panels, cab visual style, **Road Source**, and **Procedural World**. Turn **Procedural World** off when you want Play mode to use authored road graph or legacy curve-editor geometry without falling back to the generated city.

Set **Road Source** to choose which authored road data is real in Play:
- **Auto**: use a valid `RoadGraph` first, then fall back to legacy curve roads.
- **RoadGraph**: use only baked graph-road geometry from `Cab87RoadEditor/RoadGraph`.
- **LegacyCurve**: compatibility path for older legacy curve-editor maps.

The legacy Road Editor plugin is no longer installed by `install-studio-plugin.bat`.
Use **Clear All Road Data** first when you want to remove old graph, legacy, baked, marker, and preview data before importing a fresh curve JSON.

When you click **Generate Map**, check Studio Output for seed + generator version.

### Fast graph-road workflow

1. Run the graph visualizer:
   - `cd tools/intersection-visualizer`
   - `npm ci`
   - `npm run dev`
2. Open `http://localhost:3000`, author the road graph, then export both:
   - **Export JSON** for lightweight graph/gameplay data.
   - **Roblox** for `cab87-road-mesh.glb` plus `cab87-road-mesh.manifest.json`.
3. In Studio, open **Road Graph Builder**.
4. Set **Import Y** for the Roblox plane height.
5. Set **Map ID** to a stable level id such as `downtown_v1`.
6. Click **Import Graph JSON**.
   - The plugin imports to `Cab87RoadEditor/RoadGraph`.
   - It does not run the Luau mesher automatically.
7. Import `cab87-road-mesh.glb` with Studio's 3D Importer.
8. Select the imported model or imported MeshParts.
9. Click **Adopt Imported GLB Mesh** and choose `cab87-road-mesh.manifest.json`.
   - The plugin moves the imported chunks into `Cab87RoadEditor/RoadGraphBakedRuntime`.
   - It configures visual, collision, and minimap MeshParts from the manifest.
   - Play mode uses these imported MeshParts instead of runtime `EditableMesh` generation.
10. Press Play and test traversal.

**Bake Runtime Geometry** remains available as the older Studio-generated mesh path. Prefer the GLB + manifest workflow for large maps so the TypeScript visualizer remains the source of truth for meshing.

For an update to the same map, keep the same **Map ID**, re-export JSON + Roblox GLB/manifest, import the new GLB, and run **Adopt Imported GLB Mesh** again. For a new level, click **Fork As New Map** or set a new **Map ID** before adopting so the new map gets separate baked output.

### Dialogue timing workflow

Use `tools/dialogue-timing-tool` when you need word-level dialogue timing for kinetic text or captions:

1. Start the local web tool:
   - `cd tools/dialogue-timing-tool`
   - `OPENAI_API_KEY=sk-... npm run dev`
2. Open `http://127.0.0.1:8011`.
3. Upload an audio or video clip.
4. Transcribe with Whisper word timestamps.
5. Review/nudge timing against the waveform and export kinetic JSON, CSV, VTT, or SRT.

The tool keeps the API key on the local Node server and uses OpenAI Whisper's verbose JSON word timestamps because the newer GPT transcription models do not currently expose word-level timestamp granularities.

### Blender video plane workflow

Use `tools/blender-video-plane` when you need to place reference footage or rendered video in Blender:

1. Run `tools/blender-video-plane/package.bat`.
2. Install the generated `cab87_video_plane_tool_vX.Y.Z.zip` in Blender.
3. Open `3D Viewport > Sidebar > Cab87 > Video Plane`.
4. Click `Load Video Plane` and choose a supported movie file.

The add-on creates a UV-mapped plane matching the movie aspect ratio and assigns a movie texture material with auto-refresh enabled for playback.

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

### Legacy Web Curve Authoring Workflow

This flow is kept only for older maps that still have legacy curve-editor data. New authored maps should use the graph-road workflow above.

1. Open `tools/road-curve-editor/index.html`, or run `tools/road-curve-editor/run.bat`.
2. Import a trace image and lay out one or more splines in the browser tool.
   - Open **Soft Select** or press **S** to drag broad regions of spline points and junctions with radius falloff.
3. Export `cab87-road-curves.json` to save the full browser session, including the trace image and its transform.
4. Reopen that same file in the browser tool with **Import Session JSON** if you want to resume editing later.
5. In Studio, set **Import Plane Y** in the legacy Road Editor if it is installed manually.
6. Click **Import Curve JSON (Append)** to add to the current spline set, or **Import Curve JSON (Replace)** to replace the current authored splines while keeping markers such as `CabCompanyNode`, `CabRefuelPoint`, `CabServicePoint`, and `PlayerSpawnPoint`.
7. The plugin imports the control points into `Cab87RoadEditor/Splines` and rebuilds the road network from the imported data.

### Cab depot markers

For authored-road maps, use the Cab87 Road Graph Builder toolbar or panel buttons to place individual marker parts under `Cab87RoadEditor/Markers`:

- `CabCompanyNode` is the cab spawn marker. It is required when using the authored cab depot marker flow.
- `CabRefuelPoint` is the free cab-depot refuel marker. If omitted, free refuel falls back to `CabCompanyNode`.
- `CabServicePoint` is the recover/shop service marker. If omitted, runtime generation creates one from `cabCompanyServiceOffset`.
- `PlayerSpawnPoint` is optional. Set `playerUseCabCompanySpawn = true` in `src/shared/MapConfig.lua` only if you want the server to force characters to this marker.

The runtime cab depot is marker-only. It no longer generates the old lot, building, garage, beacon, refuel island, or service-zone geometry.

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
