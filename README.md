# cab87-roblox

Code-first Roblox starter for a **Crazy Taxi style** prototype using **Rojo + Luau + Git**.

## What is in this repo

- Procedural-ish city grid (roads + buildings)
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

## Controls

- Accelerate: `W` / `Up`
- Brake/Reverse: `S` / `Down`
- Steer: `A` / `D` or `Left` / `Right`

## Project structure

- `src/server/Main.server.lua` - world generation + cab simulation
- `src/client/Hud.client.lua` - basic on-screen controls hint
- `src/shared/Config.lua` - tuning values

## Notes

- This uses a scripted arcade controller (not Roblox default vehicle physics).
- Tune values in `src/shared/Config.lua`.
