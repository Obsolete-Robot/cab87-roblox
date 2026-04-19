# AGENTS.md

Guidance for coding agents working on this Rojo-based Roblox prototype.

## Project Shape

This repository is the source of truth for a code-first arcade taxi game prototype. Roblox Studio should be treated as the runtime/editor target, not the place where source changes live.

Current Rojo mapping:

- `src/shared` -> `ReplicatedStorage.Shared`
- `src/server` -> `ServerScriptService.cab87`
- `src/client` -> `StarterPlayer.StarterPlayerScripts`

Important files:

- `default.project.json`: Rojo DataModel mapping.
- `rokit.toml`: Roblox tool versions. Rojo is pinned here.
- `wally.toml`: Wally package manifest. Dependencies are currently empty.
- `src/shared/Config.lua`: gameplay and world tuning values.
- `src/server/Main.server.lua`: city generation and taxi simulation.
- `src/client/Hud.client.lua`: player HUD/client presentation.

## Tooling Workflow

Use the repo tools before assuming global installs:

```sh
rokit install
rojo serve
```

Then connect from the Rojo plugin in Roblox Studio and press Play.

Useful checks:

```sh
rojo build default.project.json --output cab87.rbxlx
```

Only run `wally install` after adding dependencies to `wally.toml`. If Wally packages are introduced, make sure the generated package path is mapped intentionally in `default.project.json`.

## Rojo Best Practices

- Keep filesystem files as the canonical source. Do not make important Studio-only changes unless they are reproduced in this repo.
- Update `default.project.json` whenever adding a new top-level service folder or changing where code should sync.
- Prefer clear service boundaries:
  - Shared constants, pure helpers, and shared types belong under `src/shared`.
  - Server-owned gameplay, world generation, authoritative scoring, spawning, and NPC/passenger logic belong under `src/server`.
  - Player input, HUD, camera, audio presentation, and local effects belong under `src/client`.
- Avoid relying on object names created manually in Studio unless Rojo also creates or maps those objects.
- Keep generated runtime instances under named containers such as `Cab87World` so Play sessions can cleanly replace them.
- Do not commit generated `.rbxl`, `.rbxlx`, package output, or temporary Studio artifacts unless the repo intentionally starts tracking those assets.

## Gameplay Architecture

This game should feel like an arcade taxi game: fast, readable, forgiving, and tuned for flow over realism.

- Keep the server authoritative for gameplay state that matters: taxi position, passengers, fares, timer, collisions that affect scoring, and progression.
- Let the client own presentation: HUD animation, camera feel, input affordances, route arrows, local sound, particles, and screen effects.
- Put tuning in `src/shared/Config.lua` or small dedicated config modules rather than scattering magic numbers through gameplay code.
- Make arcade-driving changes by tuning acceleration, braking, drag, turn rate, reverse speed, and grip-like behavior deliberately. Preserve responsive controls over physical realism.
- Keep taxi movement stable across frame rates. Use `dt`, clamp extreme values if needed, and avoid logic that depends on a specific Heartbeat rate.
- For future multiplayer, avoid direct single-player assumptions in server code. Store per-player/per-cab state explicitly instead of global `speed`, `position`, or `seat` variables.
- Keep systems small and replaceable. Suggested future split:
  - `CityBuilder` for roads, buildings, spawn points, and cleanup.
  - `TaxiController` for movement and seat/input interpretation.
  - `PassengerService` for pickup/dropoff flow.
  - `FareService` for timers, score, streaks, and rewards.
  - `HudController` for client UI updates.

## Game Architecture Best Practices

Design systems so each module has one clear reason to change.

- Separate domain logic from Roblox instance creation where practical. For example, fare timing and scoring should be testable without needing to create UI labels or Workspace parts.
- Keep orchestration thin. Entry scripts such as `Main.server.lua` should wire services together, create top-level containers, and start systems; they should not accumulate all gameplay logic.
- Prefer module APIs that expose intent instead of internal state. Use functions such as `TaxiController.spawnCab(config, parent)` or `FareService.startFare(player, pickup, dropoff)` rather than requiring callers to mutate tables directly.
- Encapsulate mutable state inside the owning module. Other modules should ask for state through functions or events instead of reaching into private tables.
- Make dependencies explicit. Pass config, folders, remotes, and services into constructors or setup functions instead of having every module discover everything globally.
- Keep data shapes stable. When sharing structured state between server and client, define clear fields and avoid sending loosely assembled tables with inconsistent keys.
- Use small domain events or callbacks for cross-system communication. A passenger pickup should notify fare/scoring/HUD systems without those systems needing to know every detail of the passenger model.
- Avoid circular module dependencies. If two modules need each other, extract shared data or coordination into a third module.
- Prefer composition over inheritance-style patterns. Roblox gameplay usually stays simpler when systems own focused components that can be combined.
- Keep gameplay systems restartable. A round reset should be able to destroy runtime objects, disconnect events, clear state, and start again without rejoining the place.

Apply SOLID principles pragmatically:

- Single Responsibility: `CityBuilder` builds the city, `TaxiController` moves taxis, `FareService` owns fare rules, and `HudController` displays state.
- Open/Closed: add new passenger types, scoring bonuses, or vehicle tunings through config tables or small strategy modules instead of editing a giant conditional block.
- Liskov Substitution: if multiple taxi or passenger modules share an interface, make sure callers can use any implementation without special-case checks.
- Interface Segregation: expose small APIs. A HUD module should not receive an entire fare service if it only needs fare amount, timer, and destination updates.
- Dependency Inversion: high-level game flow should depend on module contracts, not concrete Workspace paths or raw Instances when a simple interface will do.

Keep DRY without hiding intent:

- Extract repeated Roblox instance setup into helper functions or factory modules when the repetition includes real rules, such as common part defaults, tags, collision groups, or cleanup behavior.
- Do not over-abstract one-off gameplay code before the pattern is clear.
- Centralize constants, colors, collision group names, remote names, and tuning values.
- Prefer descriptive helper names over generic helpers. `createRoadPart` is better than a broad `makeThing` if the function encodes road-specific defaults.
- Share pure math and formatting helpers from `src/shared` when both server and client need the same behavior.

## World And Level Generation

- Keep road dimensions, city size, building bounds, and spawn locations configurable.
- Avoid creating excessive parts per session. If the city grows, consider chunking, meshes, or pooled/reused instances.
- Use deterministic generation when debugging layout-sensitive behavior. Add a seed to config before relying on random city layouts in tests or demos.
- Keep roads wide, intersections readable, and landmarks visually distinct so high-speed navigation is possible.
- Leave enough drivable space around spawn points, passenger pickups, and dropoffs.

## Editor-Friendly Creation

Code-created content should still be understandable in Roblox Studio.

- Give every important Instance a clear `Name`. Avoid anonymous `Part`, `Model`, `Folder`, or `ScreenGui` objects in generated hierarchies.
- Group runtime objects under predictable containers such as `Cab87World`, `Taxis`, `Roads`, `Buildings`, `Passengers`, `Pickups`, `Dropoffs`, `Remotes`, and `RuntimeGui`.
- Set `PrimaryPart`, useful pivots, and consistent model structure for generated models so they are easy to inspect, move, and debug in Studio.
- Use Attributes for editor-visible metadata such as `PassengerId`, `FareValue`, `PickupZone`, `DropoffZone`, `RoadType`, or `GeneratedBy`.
- Use `CollectionService` tags for categories that designers or debugging tools may need to query.
- Prefer named folders and model containers over dumping generated objects directly into `Workspace`.
- Keep generated geometry dimensions and positions rounded or config-driven where possible so values are readable in Studio properties.
- Assign materials, colors, transparency, collision settings, and anchoring intentionally during creation. Do not rely on engine defaults for important gameplay objects.
- Set `CanCollide`, `CanTouch`, `CanQuery`, `Massless`, and `Anchored` explicitly for gameplay parts where the behavior matters.
- If designers will tune something in Studio later, create a clear place for it: config modules, Attributes, tagged templates, or Rojo-mapped folders.
- For reusable visual objects, consider Studio-authored templates synced through Rojo and cloned by code instead of constructing every detail procedurally.
- Keep runtime cleanup simple by making each system own a root folder/model it can destroy.

## Roblox/Luau Style

- Use Luau idioms already present in the repo: local services at the top, small local helper functions, and explicit config access.
- Prefer typed Luau annotations when adding larger modules or public function surfaces.
- Use `WaitForChild` only at trust boundaries where replication timing matters. Avoid burying yield-prone calls inside hot paths.
- Avoid long-running work in `Heartbeat` callbacks. Cache instance lists and config values outside per-frame loops where practical.
- Disconnect events and destroy runtime objects when replacing generated worlds, rounds, or player-owned systems.
- Use `CollectionService` tags when systems need to discover categories of objects instead of walking the whole Workspace repeatedly.
- Keep comments sparse and useful. Explain non-obvious gameplay math or Roblox engine constraints, not simple assignments.

## Roblox Engine Best Practices

- Use server scripts for authority and client scripts for responsiveness. Do not let LocalScripts decide permanent score, cash, completed fares, or unlocks.
- Respect replication boundaries. Objects needed by both server and client belong in replicated containers; server-only logic and secrets belong in `ServerScriptService` or `ServerStorage`.
- Prefer `ReplicatedStorage` for shared modules, remote definitions, and read-only shared assets. Avoid putting server-only modules there.
- Use `ServerStorage` for templates that clients do not need to see. Use `ReplicatedStorage` for templates the client must preview or animate locally.
- Use `Workspace` only for objects that need to exist in the 3D world. Keep service folders and non-world state elsewhere.
- Avoid expensive yields during startup. Create required containers deterministically and fail clearly if a required dependency is missing.
- Treat physics ownership deliberately if unanchored vehicles are introduced. Server-owned movement is authoritative; client ownership can improve feel but needs validation.
- Avoid memory leaks from event connections, spawned threads, and per-player state. Give each service a cleanup path for player removal and round reset.
- Use collision groups once the city has taxis, pedestrians, pickups, and triggers. Do not solve all collision problems with scattered `CanCollide` toggles.
- Keep RemoteEvent and RemoteFunction names centralized. Version or replace remotes carefully when payload contracts change.
- Use `task.wait`, `task.spawn`, and `task.defer` instead of legacy wait/spawn/delay APIs.
- Avoid doing heavy work in `PlayerAdded`, `CharacterAdded`, or `Heartbeat` without bounds. Defer noncritical setup and cache repeated lookups.
- Use `Debris` only for simple timed cleanup. For gameplay-owned objects, prefer explicit ownership and destruction.

## Networking

When adding RemoteEvents or RemoteFunctions:

- Create them from the server in a predictable replicated location, usually `ReplicatedStorage`.
- Validate all client input on the server. Never trust client-reported money, score, destinations, or completed fares.
- Keep remote payloads small and explicit. Send state changes and UI data, not whole instance trees.
- Rate-limit or debounce input remotes that could be fired rapidly.
- Prefer server-to-client events for fare updates, destination changes, and round state; prefer local client logic for purely visual feedback.

## UI And Controls

- HUD should prioritize speed, fare, destination, timer, combo/streak, and a readable pickup/dropoff indicator as the game grows.
- Keep mobile/controller support in mind when adding controls. Keyboard-only is fine for the current prototype, but input code should not make future device support harder.
- Avoid blocking the driving view with large panels. Taxi games need road visibility first.
- Use client scripts for camera feel, route arrows, and local visual polish; keep scoring and objective truth on the server.

## Performance

- Minimize per-frame allocation in driving and HUD loops.
- Do not repeatedly call `GetDescendants()` or scan `Workspace` every frame.
- Batch world creation where possible and keep generated part counts reasonable.
- Use anchored/scripted movement only when it matches the design. If switching to physics constraints later, isolate that change inside a taxi controller module.
- Test with Play Solo and, after adding networking/multiplayer behavior, a local server with multiple clients.

## Validation Checklist

Before handing off gameplay changes:

- Run a Rojo build check:

```sh
rojo build default.project.json --output cab87.rbxlx
```

- Start `rojo serve`, connect Studio, and run Play if the change affects runtime behavior.
- Verify the city regenerates cleanly without duplicate old worlds.
- Verify the taxi can accelerate, brake/reverse, steer, and remain upright.
- Verify HUD/client scripts do not error on spawn or respawn.
- Check Studio Output for Luau errors and replication warnings.
- If config values changed, sanity-check spawn position, road width, and max speed together.

## Git Hygiene

- Keep changes scoped to the requested gameplay/tooling area.
- Do not revert unrelated user edits in this repo.
- Avoid committing generated build files unless explicitly requested.
- Mention any validation that required Studio but could not be run from the terminal.
