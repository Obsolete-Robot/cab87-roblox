# Cab87 Milestone Roadmap

Last updated: 2026-04-20

This roadmap tracks the major systems still needed to turn Cab87 from a drivable prototype into a complete arcade taxi loop. Tasks are grouped as GitHub-friendly milestones so each section can become a milestone, epic issue, or checklist.

Implementation should follow the [architecture plan](ARCHITECTURE_PLAN.md) so new systems stay encapsulated, restartable, and split across focused server services and client controllers.

## Resolved Design Decisions

These decisions are also repeated inside the relevant milestone sections so future GitHub issues keep the product context when split out.

- Shift money and persistent money are separate values. Shift money is tallied during each shift, then the end-of-shift UI animates the payout breakdown before the cab company takes a significant percentage-based medallion fee. The remaining net earnings go into the player's persistent bank for unlockables.
- The medallion fee should be percentage-based, start at 20% for the first playtest, and stay tunable from config based on playtesting.
- Failed fares do not cost money. They only lose the potential payout from that fare.
- Crash damage resets per passenger/fare.
- Traffic laws affect traffic behavior only. Running lights should not directly affect score, fare payout, or passenger rating.
- Free cab-company gas is always available when the player drives back to the cab company. It should take longer than paid gas.
- Powerups should all be available in both solo and multiplayer for the first playable pass, then culled or weighted by mode later based on tuning.
- Purchased taxis should persist across sessions from the start.
- Bank money and purchased taxis should use Roblox DataStores in the first economy pass.

## Milestone 1: Core Shift Loop

Goal: make a playable taxi shift with time pressure, fares, scoring, and clear HUD feedback.

Design decisions for this milestone:

- Shift money is a per-shift gross value and is separate from persistent bank money.
- End-of-shift results should animate the payout breakdown: gross shift money, fare totals, bonuses, damage penalties, 20% starting medallion fee, and net bank deposit.
- Failed fares do not cost money; they only lose the unpaid potential payout.
- Crash damage resets per passenger/fare when the passenger exits or the fare fails.

- [ ] Add a server-authoritative shift state machine.
  - [ ] Support configurable shift length, starting at 3 minutes.
  - [ ] Broadcast shift start, remaining time, overtime/end, and inter-shift states to clients.
  - [ ] Keep taxi driving available outside active shifts.
  - [ ] Store per-player shift totals separately from persistent bank money.
- [ ] Implement fare pricing.
  - [ ] Calculate base fare from pickup-to-dropoff distance.
  - [ ] Add time-based bonuses or penalties.
  - [ ] Add delivery speed bonus rules that reward fast but readable driving.
  - [ ] Add minimum fare and max payout caps in config.
  - [ ] Surface fare estimate, active fare value, and final payout in the HUD.
- [ ] Implement passenger fare lifecycle.
  - [ ] Pick up passenger.
  - [ ] Assign destination.
  - [ ] Track active route and delivery progress.
  - [ ] Complete fare and award money.
  - [ ] Expire or fail fare when shift ends, losing only the unpaid potential payout.
- [ ] Add crash and damage tracking during active fares.
  - [ ] Track collision count and collision severity while a passenger is in the cab.
  - [ ] Convert crash damage into fare penalties.
  - [ ] Show active fare damage in the HUD.
  - [ ] Reset fare damage cleanly when the passenger exits or the fare fails.
  - [ ] Add config tuning for damage thresholds, penalty scaling, and forgiveness windows.
- [ ] Add end-of-shift payout UI.
  - [ ] Animate the shift gross earnings tally.
  - [ ] Show fare totals, bonuses, and damage penalties.
  - [ ] Show the cab company medallion fee deduction.
  - [ ] Deposit net earnings into the player's persistent bank.
  - [ ] Keep shift money and bank money visually distinct.
- [ ] Update HUD for core loop.
  - [ ] Shift timer.
  - [ ] Current shift money.
  - [ ] Active fare payout.
  - [ ] Destination indicator.
  - [ ] Fare damage indicator.
  - [ ] Completed fares count.

Definition of done:

- A player can start a shift, complete multiple fares, see money update, and receive final shift results without Studio Output errors.
- The shift length can be changed from config without touching gameplay code.

## Milestone 2: Cab Company, Gas, And Vehicle Access

Goal: add the home base loop where players get a cab, refuel, buy upgrades, and prepare for the next shift.

Design decisions for this milestone:

- Free cab-company gas is always available when the player drives back to the cab company.
- Free cab-company refuel should take longer than paid gas station refuel.
- Paid gas stations spend player bank money and should be faster than the free cab-company option.

- [ ] Build the starting cab company area.
  - [ ] Add a clear spawn point and player orientation.
  - [ ] Add cab pickup or selection zone.
  - [ ] Add garage/refuel/service points.
  - [ ] Add visual landmarks that make the company recognizable from the road.
  - [ ] Keep generated objects grouped under named containers.
- [ ] Add taxi acquisition flow.
  - [ ] Let players claim or spawn a cab from the company.
  - [ ] Prevent duplicate active taxis per player unless intentionally supported.
  - [ ] Reset or recover a player cab from the company.
  - [ ] Preserve ownership data for multiplayer.
- [ ] Implement gas mechanics.
  - [ ] Add max fuel, current fuel, burn rate, and idle/driving cost tuning.
  - [ ] Slow the taxi significantly when out of gas.
  - [ ] Add gas stations to the map.
  - [ ] Refuel at paid stations using player money.
  - [ ] Allow free cab-company refuel whenever the player drives back to the cab company.
  - [ ] Make free cab-company refuel take longer than paid station refuel.
  - [ ] Prevent refuel abuse with clear start/cancel/complete states.
- [ ] Add gas HUD.
  - [ ] Fuel gauge.
  - [ ] Out-of-gas warning.
  - [ ] Refueling progress.
  - [ ] Refuel price prompt.
- [ ] Create vehicle config data.
  - [ ] Define taxi model id/name, speed, acceleration, handling, fuel capacity, and unlock price.
  - [ ] Support future taxi variants without large conditionals.

Definition of done:

- A new player can spawn at the cab company, get a taxi, drive a shift, run low on gas, refuel at paid stations or slower free cab-company service, and continue into the next shift.

## Milestone 3: Vehicle And Character Content

Goal: replace prototype geometry with readable arcade assets.

- [ ] Implement first production taxi model.
  - [ ] Model body, wheels, lights, roof sign, and readable silhouette.
  - [ ] Define attachment points for VFX, passengers, and hit reactions.
  - [ ] Keep model structure consistent for future taxi variants.
  - [ ] Add fallback behavior if a required part is missing.
- [ ] Implement additional car models.
  - [ ] Civilian compact.
  - [ ] Civilian sedan.
  - [ ] Van or truck.
  - [ ] Sporty car.
  - [ ] Service/emergency vehicle placeholder if useful.
- [ ] Implement real character art.
  - [ ] Passenger visual variants.
  - [ ] Driver-visible character or avatar integration rules.
  - [ ] Pickup/dropoff animations.
  - [ ] Passenger panic or reaction poses for crashes.
- [ ] Add asset organization.
  - [ ] Decide which templates live in Rojo-mapped source versus Studio-authored assets.
  - [ ] Keep shared previewable assets in ReplicatedStorage.
  - [ ] Keep server-only templates in ServerStorage if introduced.

Definition of done:

- The default taxi, traffic vehicles, and passengers are visually distinct at driving speed.

## Milestone 4: Traffic And Road Rules

Goal: add ambient traffic that makes the city feel active and creates arcade driving pressure.

Design decisions for this milestone:

- Traffic laws affect AI traffic behavior only.
- Running red lights should not directly affect score, fare payout, passenger rating, or bank money.
- Traffic-light HUD feedback, if added, should be for readability/navigation rather than punishment.

- [ ] Implement traffic system foundation.
  - [ ] Build road graph lanes or waypoint routes from generated/authored roads.
  - [ ] Spawn civilian cars near active players.
  - [ ] Despawn cars that are far away or stuck.
  - [ ] Keep traffic count capped by config.
  - [ ] Avoid heavy per-frame Workspace scans.
- [ ] Add traffic driving behavior.
  - [ ] Follow lanes or route waypoints.
  - [ ] Slow for turns.
  - [ ] Avoid simple rear-end collisions.
  - [ ] Recover from stuck states.
  - [ ] React to player taxis enough to feel fair.
- [ ] Add traffic lights.
  - [ ] Detect or author intersections.
  - [ ] Place named traffic light models at intersections.
  - [ ] Cycle right of way between road directions.
  - [ ] Expose traffic light state for traffic cars.
  - [ ] Add light timing config.
  - [ ] Keep client visuals synchronized with server state.
- [ ] Keep traffic laws gameplay-neutral.
  - [ ] Use traffic lights to control AI traffic right of way.
  - [ ] Do not penalize score, fare payout, or passenger rating for player red-light behavior.
  - [ ] Optional HUD warning is allowed only as navigation/readability feedback.

Definition of done:

- Traffic cars spawn, drive, obey basic traffic lights, and clean themselves up without tanking performance.

## Milestone 5: Level Layout Blocking

Goal: shape the game space around fast taxi readability and repeatable routes.

- [ ] Block out major city districts.
  - [ ] Cab company district.
  - [ ] Downtown/high fare district.
  - [ ] Residential pickup district.
  - [ ] Industrial or dock district.
  - [ ] Airport/train/bus landmark district.
- [ ] Add authored route landmarks.
  - [ ] Big turns and intersections that are readable at high speed.
  - [ ] Shortcut opportunities.
  - [ ] Jump or stunt opportunities if they fit the handling.
  - [ ] Gas station placement.
  - [ ] Powerup box placement.
- [ ] Improve pickup and dropoff placement.
  - [ ] Keep stops visible from the road.
  - [ ] Avoid dropoffs that require awkward U-turns unless intentional.
  - [ ] Balance short, medium, and long fares.
  - [ ] Add config support for district-weighted passenger spawning.
- [ ] Add map validation/debug tools.
  - [ ] Show road graph.
  - [ ] Show passenger stop candidates.
  - [ ] Show traffic lanes.
  - [ ] Show gas stations and powerup spawn points.

Definition of done:

- A playtest route through the level has clear landmarks, enough pickups, refuel options, and traffic pressure.

## Milestone 6: Multiplayer Shift Competition

Goal: support multiple players competing for the most money per shift while sharing the same city.

Design decisions for this milestone:

- Multiplayer competition ranks players by current shift money, not lifetime bank money.
- End-of-shift results should still show the medallion fee and net bank deposit for each player.
- Players keep driving between shifts and get a preparation window to refuel or change vehicles before the next shift.

- [ ] Refactor gameplay state for multiple players.
  - [ ] Per-player cab ownership.
  - [ ] Per-player input, speed, fuel, damage, fare, and money state.
  - [ ] Player cleanup on leave.
  - [ ] Cab cleanup or reassignment rules.
- [ ] Add multiplayer shift orchestration.
  - [ ] Shared shift timer.
  - [ ] Join current shift if active.
  - [ ] Let players drive between shifts.
  - [ ] Add pre-shift preparation window for gas and vehicle selection.
  - [ ] Continue shifts automatically.
- [ ] Add leaderboard.
  - [ ] Live in-shift leaderboard HUD.
  - [ ] End-of-shift results UI with animated money breakdown.
  - [ ] Rank by shift money.
  - [ ] Resolve ties consistently.
  - [ ] Show completed fares, damage penalties, bonuses, medallion fee, net bank deposit, and final rank.
- [ ] Award multiplayer bonuses.
  - [ ] Bonus money for top finishers.
  - [ ] Participation reward.
  - [ ] Optional comeback or streak bonus.
  - [ ] Make reward values configurable.
- [ ] Add multiplayer validation.
  - [ ] Server validates fare completion.
  - [ ] Server validates money and purchases.
  - [ ] Server validates powerup use.
  - [ ] Rate-limit player input and action remotes where needed.

Definition of done:

- Two or more players can complete continuous shifts, see live rankings, receive end-of-shift results, and keep playing into the next shift.

## Milestone 7: Unlockables And Economy

Goal: give players reasons to keep earning money beyond one shift.

Design decisions for this milestone:

- Persistent bank money is separate from shift money.
- Shift gross earnings become persistent bank deposits only after the percentage-based medallion fee is deducted.
- The first-playtest medallion fee starts at 20% and remains config-tunable.
- Bank money and purchased taxis should use Roblox DataStores in the first economy pass.
- Purchased taxis persist across sessions from the start.

- [ ] Add persistent economy rules.
  - [ ] Persist the player's bank money across sessions.
  - [ ] Track lifetime/bank money separately from current shift money.
  - [ ] Convert shift gross earnings into persistent bank deposits after medallion fee deductions.
  - [ ] Make the percentage-based medallion fee configurable, with a first-playtest default of 20%.
  - [ ] Save and load bank money using Roblox DataStores.
  - [ ] Save and load purchased taxis using Roblox DataStores.
  - [ ] Add basic DataStore retry, failure logging, schema versioning, and graceful fallback behavior.
  - [ ] Keep purchase validation server-authoritative.
- [ ] Add taxi unlocks.
  - [ ] Purchase additional taxis at the cab company.
  - [ ] Preview taxi stats before purchase.
  - [ ] Equip purchased taxis.
  - [ ] Persist purchased taxis across sessions.
  - [ ] Prevent unequipped taxi state from breaking active cab ownership.
- [ ] Add consumable powerup purchases.
  - [ ] Buy consumables from cab company.
  - [ ] Store inventory counts.
  - [ ] Use consumables during or before shifts based on rules.
- [ ] Add music unlocks.
  - [ ] Purchase additional music tracks.
  - [ ] Select active track or playlist.
  - [ ] Keep audio presentation client-owned.
- [ ] Add shop UI.
  - [ ] Taxi tab.
  - [ ] Powerups tab.
  - [ ] Music tab.
  - [ ] Purchase confirmation.
  - [ ] Clear insufficient-funds state.

Definition of done:

- A player can earn money, buy a taxi or music track, equip it, and keep the game loop intact.

## Milestone 8: Powerups And Combat Driving

Goal: add arcade disruption tools that create multiplayer moments without overwhelming taxi delivery.

Design decisions for this milestone:

- All powerups should be available in both solo and multiplayer for the first tuning pass.
- Keep config hooks for later mode-specific culling or spawn weighting after playtesting shows which powerups are not useful in solo mode.

- [ ] Add powerup box system.
  - [ ] Place boxes throughout the course.
  - [ ] Respawn boxes after pickup.
  - [ ] Give random or weighted powerups.
  - [ ] Make all powerups available in both solo and multiplayer for the first tuning pass.
  - [ ] Leave config hooks for future mode-specific culling and spawn weights.
  - [ ] Prevent the same player from instantly re-picking a box.
  - [ ] Add pickup VFX and sound hooks.
- [ ] Add inventory and activation flow.
  - [ ] One held powerup slot to start.
  - [ ] HUD icon for held powerup.
  - [ ] Server-authoritative activation.
  - [ ] Cooldowns and invalid-use feedback.
- [ ] Implement gas boost.
  - [ ] Fills tank by configured amount.
  - [ ] Can be picked up or bought as consumable.
  - [ ] Optional short speed boost if balanced.
- [ ] Implement banana peel.
  - [ ] Drops behind taxi.
  - [ ] Other taxis spin out on contact.
  - [ ] Cleans up after timeout or hit.
  - [ ] Does not punish the owner immediately unless intended.
- [ ] Implement green missile.
  - [ ] Fires straight ahead.
  - [ ] Stops or heavily slows another player on hit.
  - [ ] Adds clear warning/readability VFX.
  - [ ] Cleans up on timeout or collision.
- [ ] Implement red missile.
  - [ ] Locks onto a target.
  - [ ] Homes with fair turn-rate limits.
  - [ ] Gives target warning.
  - [ ] Stops or launches target on hit.
- [ ] Implement double fare.
  - [ ] Doubles payout for current or next fare.
  - [ ] Defines expiry rules.
  - [ ] Shows multiplier in HUD.
- [ ] Add additional powerups.
  - [ ] Shield.
  - [ ] Repair kit.
  - [ ] Fare magnet or passenger call-in.
  - [ ] Traffic jammer.
  - [ ] Route reveal or shortcut marker.
- [ ] Add combat car mechanics.
  - [ ] Missile hit launches car into the air.
  - [ ] Car spins in the air after missile hit.
  - [ ] Banana peel spinout preserves arcade control after a short penalty.
  - [ ] Damage and passenger reaction rules connect to fare penalties.
  - [ ] Recovery is fast enough to stay fun.

Definition of done:

- Players can collect boxes, use powerups, disrupt each other, recover quickly, and still complete fares.

## Cross-Cutting Technical Tasks

- [ ] Split large runtime code into focused server modules.
  - [ ] CityBuilder or MapRuntime.
  - [ ] TaxiController.
  - [ ] FareService.
  - [ ] ShiftService.
  - [ ] FuelService.
  - [ ] TrafficService.
  - [ ] PowerupService.
  - [ ] EconomyService.
- [ ] Add client presentation controllers.
  - [ ] HudController.
  - [ ] RouteArrowController.
  - [ ] VehicleEffectsController.
  - [ ] AudioController.
  - [ ] LeaderboardController.
- [ ] Centralize remote names and payload contracts.
  - [ ] Define request/action remotes.
  - [ ] Define server-to-client state update remotes.
  - [ ] Document payload shapes.
  - [ ] Validate all client input on the server.
- [ ] Add cleanup/restart paths.
  - [ ] Destroy generated worlds cleanly.
  - [ ] Disconnect per-player connections.
  - [ ] Reset shift systems without rejoining.
  - [ ] Reset traffic and powerups between map rebuilds.
- [ ] Add tuning config.
  - [ ] Shift timing.
  - [ ] Fare payout formula.
  - [ ] Damage penalty formula.
  - [ ] Fuel burn/refuel rates.
  - [ ] Traffic spawn counts.
  - [ ] Powerup spawn weights.
  - [ ] Multiplayer rewards.
- [ ] Add validation checks.
  - [ ] Rojo build check.
  - [ ] Play Solo smoke test.
  - [ ] Local server multiplayer smoke test after networking changes.
  - [ ] Studio Output check for Luau errors and replication warnings.

## Suggested Build Order

1. Core shift loop, fare payout, and damage HUD.
2. Cab company, taxi spawning, and gas/refuel loop.
3. Vehicle model structure and first production taxi.
4. Level blocking pass with gas stations and stop placement.
5. Traffic routes and traffic lights.
6. Multiplayer state refactor and leaderboard.
7. Economy, unlocks, and shop UI.
8. Powerup boxes, held powerups, and combat reactions.

## Open Design Questions

- After powerup playtesting, which powerups should be culled or weighted differently by mode?
