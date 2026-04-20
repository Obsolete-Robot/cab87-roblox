# Cab87 Architecture Plan

Last updated: 2026-04-20

This document defines the target architecture for completing the milestone roadmap without turning gameplay scripts into large, tightly coupled files. The goal is not to rewrite everything at once. Each milestone should move the codebase closer to these boundaries while keeping the game playable.

## Architecture Goals

- Keep the server authoritative for gameplay truth: shifts, fares, money, fuel, cab ownership, damage, traffic, powerups, purchases, and persistence.
- Keep clients responsible for presentation: HUD, camera, input collection, local audio, local VFX, route presentation, payout animations, and shop screens.
- Make every system own one clear slice of mutable state.
- Keep entry scripts thin. `Main.server.lua` and client `.client.lua` files should wire modules together, not contain most gameplay logic.
- Prefer explicit dependencies over global discovery. Pass config, remotes, folders, services, and callbacks into constructors.
- Use small service APIs and domain events instead of letting modules mutate each other's tables.
- Keep runtime objects under named folders/models so reset and cleanup are straightforward.
- Centralize constants, remote names, payload shapes, item catalogs, vehicle tuning, and economy formulas.

## Current Pressure Points

These files are doing useful work today, but they should not absorb the rest of the roadmap:

- `src/server/Main.server.lua`: should become runtime bootstrap plus service wiring. Cab movement, cab creation, remotes, debug tuning, world setup, and player orchestration should move into focused modules over time.
- `src/server/PassengerService.lua`: should remain passenger/pickup/dropoff focused. Fare payout, shift scoring, and damage economics should move to `FareService`.
- `src/client/Hud.client.lua`: should become a client bootstrap that starts input and UI controllers. Debug tuning, driving input, speedometer, fare UI, fuel UI, leaderboard UI, and payout UI should split into focused controllers.
- `src/shared/Config.lua`: should remain a central tuning source, but large config groups can move into small shared catalog modules once they become stable.

## Target Source Layout

The exact folders can be added incrementally. Rojo will map nested folders under the current `src/server`, `src/client`, and `src/shared` roots.

```text
src/
  shared/
    Config.lua
    Remotes.lua
    Types.lua
    FareRules.lua
    EconomyRules.lua
    VehicleCatalog.lua
    PowerupCatalog.lua
    Formatters.lua
    Signal.lua

  server/
    Main.server.lua
    Runtime/
      RuntimeFolders.lua
      RemoteRegistry.lua
    Services/
      MapRuntime.lua
      RoadGraphService.lua
      PlayerStateService.lua
      TaxiService.lua
      ShiftService.lua
      FareService.lua
      PassengerService.lua
      FuelService.lua
      CabCompanyService.lua
      EconomyService.lua
      VehicleInventoryService.lua
      PersistenceService.lua
      TrafficService.lua
      TrafficLightService.lua
      PowerupService.lua
      LeaderboardService.lua
    Controllers/
      TaxiController.lua
      TrafficCarController.lua
      ProjectileController.lua

  client/
    Main.client.lua
    Controllers/
      InputController.lua
      HudController.lua
      SpeedometerController.lua
      FareHudController.lua
      FuelHudController.lua
      LeaderboardController.lua
      PayoutSummaryController.lua
      ShopController.lua
      CameraController.lua
      RouteGuideController.lua
      VehicleEffectsController.lua
      AudioController.lua
      PowerupHudController.lua
```

Do not create every file up front. Add modules when a milestone needs them or when extracting existing code removes real complexity.

## Service Lifecycle

Services should follow a predictable lifecycle:

```lua
local Service = {}
Service.__index = Service

function Service.new(deps)
	return setmetatable({
		config = deps.config,
		remotes = deps.remotes,
		connections = {},
	}, Service)
end

function Service:start()
end

function Service:stop()
	for _, connection in ipairs(self.connections) do
		connection:Disconnect()
	end
	table.clear(self.connections)
end

return Service
```

Rules:

- Requiring a module should not start gameplay.
- `new` stores dependencies and initializes private state.
- `start` connects events, creates runtime instances, and begins loops.
- `stop` disconnects events, clears state, and destroys owned runtime objects.
- One service owns one root folder/model when it creates world instances.
- If a service starts a `Heartbeat` loop, it owns and disconnects that connection.

## Runtime Bootstrap

`Main.server.lua` should eventually do only this:

- Load config and shared modules.
- Create runtime folders and remotes.
- Build or load the map.
- Construct services with explicit dependencies.
- Start services in dependency order.
- Stop/restart services cleanly when the world regenerates.

Example shape:

```lua
local context = RuntimeContext.new({
	config = Config,
	world = world,
	remotes = RemoteRegistry.ensure(Config),
})

local services = {
	playerState = PlayerStateService.new(context),
	persistence = PersistenceService.new(context),
	economy = EconomyService.new(context),
	taxi = TaxiService.new(context),
	shift = ShiftService.new(context),
	fare = FareService.new(context),
}

for _, service in pairs(services) do
	service:start()
end
```

## Data Ownership

Each writable piece of gameplay state should have one owner.

| State | Owner | Notes |
| --- | --- | --- |
| Current shift phase, timer, start/end | `ShiftService` | Emits shift lifecycle events. |
| Per-player shift gross money | `ShiftService` | Resets per shift; used for leaderboard. |
| Persistent bank money | `EconomyService` | Saved through `PersistenceService`. |
| Purchased taxis and equipped taxi | `VehicleInventoryService` | Saved through `PersistenceService`. |
| Cab instance ownership | `TaxiService` | One active cab per player unless rules change. |
| Cab movement state | `TaxiController` owned by `TaxiService` | Position, velocity, yaw, air state, crash contacts. |
| Fuel amount and refuel state | `FuelService` | Applies speed limits through `TaxiService` API. |
| Active fare and passenger-in-cab state | `FareService` | Coordinates with `PassengerService`. |
| Fare damage for current passenger | `FareService` | Resets when passenger exits or fare fails. |
| Waiting passenger world models | `PassengerService` | Does not calculate final economy payout. |
| Cab company zones and service points | `CabCompanyService` | Cab spawn, free refuel, shop entry. |
| Traffic cars and route following | `TrafficService` | Uses road graph and traffic lights. |
| Traffic light right of way | `TrafficLightService` | Affects traffic behavior only. |
| Held powerup and activation state | `PowerupService` | Server validates collection and use. |
| Live leaderboard snapshot | `LeaderboardService` | Reads shift state; does not own money. |
| DataStore reads/writes | `PersistenceService` | No other service should call DataStores directly. |

If a service needs state owned by another service, it should call a method, subscribe to an event, or receive a snapshot. It should not mutate another service's tables.

## Domain Events

Use small domain events to keep services decoupled. These can be implemented with `BindableEvent`, a small shared `Signal` module, or explicit callback registration.

Useful events:

- `PlayerReady(player, profile)`
- `CabSpawned(player, cabHandle)`
- `CabDestroyed(player, reason)`
- `FuelChanged(player, fuelState)`
- `RefuelStarted(player, stationId, mode)`
- `RefuelCompleted(player, cost)`
- `ShiftStarted(shiftId, durationSeconds)`
- `ShiftTick(shiftSnapshot)`
- `ShiftEnded(shiftResult)`
- `FareOffered(player, fareOffer)`
- `FareStarted(player, fareState)`
- `FareDamaged(player, damageState)`
- `FareCompleted(player, fareResult)`
- `FareFailed(player, reason)`
- `BankChanged(player, bankMoney)`
- `PurchaseCompleted(player, purchaseResult)`
- `TaxiUnlocked(player, taxiId)`
- `TaxiEquipped(player, taxiId)`
- `PowerupCollected(player, powerupId)`
- `PowerupUsed(player, powerupId, result)`

Events should pass stable data tables, not raw internal service tables.

## Server Services

### `PlayerStateService`

Owns session-level per-player records and cleanup.

- Creates a record when a player joins.
- Tracks references to active cab, active fare id, loaded profile status, and current shift eligibility.
- Cleans up all player-owned state when the player leaves.
- Does not own money formulas, vehicle movement, or fare logic.

### `PersistenceService`

The only module that talks to Roblox DataStores.

- Loads bank money and purchased taxis.
- Saves after purchases, shift deposits, and player leave.
- Uses a schema version in saved data.
- Handles DataStore failures with retry, logging, and a graceful in-session fallback.
- Exposes intent methods such as `loadProfile(player)`, `saveProfile(player, profile)`, and `updateProfile(player, updater)`.

DataStore drawback to design for: calls can fail or throttle. That does not block using Roblox DataStores for the first working solution, but gameplay should still handle a player whose profile is temporarily unavailable or running on fallback session data.

### `EconomyService`

Owns money and purchase rules.

- Converts gross shift earnings into net bank deposits.
- Applies the configurable percentage-based medallion fee, starting at 20% for the first playtest.
- Validates purchases server-side.
- Updates persistent bank money through `PersistenceService`.
- Exposes read-only economy snapshots to HUD/shop systems.

### `VehicleInventoryService`

Owns taxi unlock and equip state.

- Tracks purchased taxi ids and the equipped taxi id.
- Persists taxi unlocks and equipped taxi through `PersistenceService`.
- Grants taxis after `EconomyService` validates and completes a purchase.
- Exposes equip validation to `TaxiService` before spawning a selected taxi.
- Keeps vehicle ownership separate from cab movement and money accounting.

### `ShiftService`

Owns the repeated shift loop.

- Runs the configurable 3-minute default shift timer.
- Tracks shift phase: preparing, active, ending, intermission.
- Stores per-player shift gross totals and final placements.
- Emits end-of-shift results for leaderboard and payout UI.
- Allows players to keep driving between shifts.

### `TaxiService` And `TaxiController`

`TaxiService` owns cab creation, cab ownership, and controller lifetime. `TaxiController` owns movement for one cab.

- Spawns one cab per player from the cab company or recovery flow.
- Keeps the existing arcade controller isolated from shift, fare, fuel, and powerup logic.
- Exposes methods such as `spawnCab(player, taxiId, spawnPose)`, `getCab(player)`, `applySpeedModifier(player, source, modifier)`, and `applyImpulse(player, impulseSpec)`.
- Emits crash and hit events with severity so `FareService` and `PowerupService` can react.

### `FareService`

Owns active fare truth and payout calculation.

- Starts fares when `PassengerService` reports a valid pickup.
- Calculates fare value from distance, time, and damage penalties.
- Resets fare damage per passenger.
- Fails fares without charging the player when a fare expires or the shift ends.
- Emits fare result snapshots for HUD, shift scoring, and payout UI.

### `PassengerService`

Owns passenger stop generation and passenger world presentation on the server.

- Spawns waiting passengers.
- Manages pickup/dropoff markers and passenger model state.
- Reports pickup/dropoff intent to `FareService`.
- Avoids owning final payout, medallion fee, or shift totals.

### `FuelService`

Owns fuel state.

- Burns fuel based on driving state and tuning.
- Slows the taxi significantly when out of gas through `TaxiService`.
- Supports paid gas stations and slower free cab-company refuel.
- Emits fuel snapshots for HUD.

### `CabCompanyService`

Owns the home base.

- Creates cab company spawn, garage, shop, and free refuel zones.
- Coordinates cab claim/recovery with `TaxiService`.
- Coordinates free refuel with `FuelService`.
- Opens shop flows through server-validated remotes.

### `TrafficService` And `TrafficLightService`

Own traffic behavior.

- `TrafficService` spawns/despawns ambient cars and follows road graph routes.
- `TrafficLightService` owns intersection right-of-way state.
- Traffic laws affect traffic behavior only, not score or passenger rating.
- Traffic systems should be capped by config and avoid per-frame world scans.

### `PowerupService`

Owns powerup boxes, held powerups, and activation.

- All powerups are available in solo and multiplayer for the first tuning pass.
- Config should still support later mode-based culling or spawn weights.
- Validates pickup and activation server-side.
- Uses `TaxiService` for car reactions and `FareService` for fare-affecting modifiers.

## Client Controllers

Client `.client.lua` files should start controllers and connect them to remotes/local services.

Suggested responsibilities:

- `InputController`: collects keyboard/gamepad/mobile input and sends compact drive input to the server.
- `HudController`: owns root HUD layout and composes smaller HUD panels.
- `SpeedometerController`: speed and drift/boost presentation.
- `FareHudController`: fare status, destination, fare damage, active payout.
- `FuelHudController`: gas gauge, out-of-gas warning, refuel progress.
- `LeaderboardController`: live shift ranking and end-of-shift standings.
- `PayoutSummaryController`: animated gross earnings, bonuses, penalties, medallion fee, and net deposit.
- `ShopController`: taxi, powerup, and music purchase UI.
- `CameraController`: camera follow and camera effects.
- `RouteGuideController`: arrows, minimap route, destination markers.
- `VehicleEffectsController`: drift smoke, boost effects, hit reactions, local polish.
- `AudioController`: music selection and local sound presentation.
- `PowerupHudController`: held powerup slot, cooldowns, and use feedback.

Client controllers can cache replicated state for presentation, but they must not decide permanent money, fare completion, purchases, unlocks, or shift results.

## Remotes And Payloads

Remote names and payload contracts should be centralized in `src/shared/Remotes.lua`. The server should create remotes from `RemoteRegistry`; clients should wait for those named remotes.

Recommended client-to-server remotes:

- `DriveInput`: throttle, steer, drift, air control.
- `RequestCab`: cab spawn or recovery.
- `RequestRefuel`: station id and refuel mode.
- `RequestPurchase`: item type and id.
- `RequestEquipTaxi`: taxi id.
- `UsePowerup`: held slot or powerup id.
- `RequestShopState`: optional shop snapshot request.

Recommended server-to-client remotes:

- `PlayerStateSnapshot`
- `ShiftStateUpdated`
- `FareStateUpdated`
- `FuelStateUpdated`
- `LeaderboardUpdated`
- `PayoutSummary`
- `ShopStateUpdated`
- `PowerupStateUpdated`
- `CabFeedback`

Rules:

- Client requests describe intent, not results.
- Server validates player, cab ownership, distance to zone, money, cooldowns, and current phase.
- Server responses use small explicit payloads.
- Do not send whole instance trees or mutable internal service tables.
- Rate-limit remotes that can fire rapidly.

## Shared Types And Data Shapes

Use typed Luau annotations for public module APIs and remote payloads as systems grow. Keep these shapes stable.

Example save data:

```lua
export type PlayerSaveData = {
	version: number,
	bankMoney: number,
	purchasedTaxis: { [string]: boolean },
	equippedTaxiId: string,
	purchasedMusicTracks: { [string]: boolean },
}
```

Example shift result:

```lua
export type ShiftResult = {
	shiftId: number,
	playerUserId: number,
	grossMoney: number,
	bonusMoney: number,
	damagePenalty: number,
	medallionFeeRate: number,
	medallionFee: number,
	netDeposit: number,
	completedFares: number,
	failedFares: number,
	rank: number?,
}
```

Example fare state:

```lua
export type FareState = {
	fareId: string,
	playerUserId: number,
	passengerId: string,
	pickupStopId: string,
	dropoffStopId: string,
	startTime: number,
	distanceStuds: number,
	damageAmount: number,
	estimatedGross: number,
	status: "Offered" | "Active" | "Completed" | "Failed",
}
```

## Config And Catalogs

Use `Config.lua` for tuning that designers will adjust often. Split stable catalogs when config becomes too large.

Good candidates:

- `VehicleCatalog.lua`: taxi ids, model names, stats, fuel capacity, price, unlock rules.
- `PowerupCatalog.lua`: ids, weights, mode flags, cooldowns, effect tuning.
- `EconomyRules.lua`: medallion fee calculation, purchase prices, reward formulas.
- `FareRules.lua`: distance/time/damage payout formula.
- `Remotes.lua`: remote names and payload version constants.

Rule of thumb: if a table describes game content or formulas and is read by multiple systems, put it in shared. If it contains server-only secrets or anti-cheat thresholds, keep it server-side.

## Encapsulation Rules

- A service's table fields are private by convention. Other modules call methods.
- Public methods should use verbs that describe intent: `startFare`, `completeFare`, `depositShiftEarnings`, `requestRefuel`.
- Do not expose raw internal arrays for mutation.
- Do not make service modules require each other in circles. Pass dependencies from `Main.server.lua`.
- Do not let UI controllers directly inspect random Workspace objects every frame. Use remotes, attributes, tags, or explicit references.
- Use attributes for editor-visible state and lightweight replicated presentation state, not as the only source of important server truth.
- Keep generated runtime instances under system-owned folders.
- Every module that connects events or creates instances should have a cleanup path.

## Migration Plan

This is the recommended order for moving from the current prototype to the target architecture:

1. Add shared `Remotes.lua`, `Types.lua`, and a small `Signal.lua` if needed.
2. Add `RuntimeFolders.lua` and `RemoteRegistry.lua` so remotes/folders stop being created ad hoc.
3. Extract cab creation and movement from `Main.server.lua` into `TaxiService` and `TaxiController`.
4. Add `PlayerStateService` so per-player state exists before multiplayer systems land.
5. Add `ShiftService` and `FareService` for shift timer, fare scoring, damage, and payout results.
6. Move fare payout logic out of `PassengerService`; keep passenger spawning and markers there.
7. Split `Hud.client.lua` into input plus HUD controllers as new UI features are added.
8. Add `EconomyService`, `VehicleInventoryService`, and `PersistenceService` when medallion fee, unlockable bank deposits, and purchased taxis start.
9. Add `FuelService` and `CabCompanyService` for gas and cab company interactions.
10. Add `TrafficService`, `TrafficLightService`, and `RoadGraphService` after road graph needs are stable.
11. Add `PowerupService` and powerup controllers after taxi hit reactions have a clean API.

Each step should leave the game runnable. Avoid a large branch that moves every system at once.

## File Size And Complexity Guardrails

These are guidelines, not hard limits:

- Entry scripts should stay under roughly 150 lines.
- Service modules should usually stay under 400 to 600 lines.
- If a service grows because it has multiple reasons to change, split it.
- Large UI controllers should split by panel or workflow.
- Pure formula modules should stay small and easy to test.
- Avoid broad helper names. Prefer names like `createRoadPart`, `calculateFarePayout`, or `buildPayoutSummary`.

## Validation Expectations

For architecture-affecting changes:

- Run `rojo build default.project.json --output cab87.rbxlx`.
- Smoke test Play Solo when runtime behavior changes.
- Use a local server with multiple clients after multiplayer state changes.
- Check Studio Output for Luau errors and replication warnings.
- Confirm world reset does not duplicate old runtime folders.
- Confirm services stop and restart cleanly when applicable.
- Confirm DataStore failures are logged and do not crash the session.
