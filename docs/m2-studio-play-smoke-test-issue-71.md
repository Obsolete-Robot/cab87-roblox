# M2 Studio Play smoke test report (Issue #71)

Date: 2026-04-22
Branch: `fix/issue-71`
Base: `origin/main` @ `94d3b29ecd9bd0612c7691513f771acb84130fe0`

## Summary

This report captures the final-validation smoke-test checklist and current execution status.

Current environment limitation: Roblox toolchain is not installed in this runner (`rokit` and `rojo` commands are unavailable), and Roblox Studio Play cannot be launched from this headless environment. Because of that, Studio Play runtime checks are documented as blocked here for manual execution in a Studio-capable machine.

## Tooling check

- [ ] `rojo build default.project.json --output cab87.rbxlx`
  - Blocked in this environment (`rojo: command not found`)

## Studio Play smoke test checklist

- [ ] New player spawns at the cab company and is oriented toward a readable prep/cab route.
- [ ] Cab company home base objects, landmarks, pickup zone, garage/shop zone, and free refuel zone are present and named in Studio.
- [ ] Player can claim a starter cab from the cab company and enter/drive it.
- [ ] Repeated claim requests do not duplicate active taxis for the player.
- [ ] Player can recover/reset cab from the company and receive a usable cab.
- [ ] Shift loop still starts/runs while cab company systems exist.
- [ ] Fuel drains while driving and low/out-of-gas HUD states appear.
- [ ] Out-of-gas slowdown happens and refuel restores drivability.
- [ ] Paid gas station refuel charges bank money exactly once on successful completion.
- [ ] Paid gas station cancellation/failure leaves bank and fuel consistent.
- [ ] Free cab-company refuel is available at the actual cab company and takes longer than paid gas station refuel.
- [ ] Fuel HUD prompt/progress/status updates correctly for paid, free, cancel, complete, low fuel, and out-of-gas states.
- [ ] Garage/shop UI opens only from the cab company service area.
- [ ] Shop shows owned/equipped/locked/affordable states and clear failure feedback.
- [ ] Purchasing/equipping a taxi uses persistent bank money, not shift money.
- [ ] Equipped taxi affects next spawn/recovery.
- [ ] Starter and `metro_taxi` fuel capacities display and behave according to catalog data after #70 lands.
- [ ] Studio Output has no Luau errors, DataStore/profile crashes, or replication warnings during the test.

## Notes on issue dependencies

- #70 has already landed in `main` (`94d3b29` includes fuel-capacity fix via PR #72).
- No additional runtime bugs were filed from this run because Studio Play could not be executed from this environment.

## Next action (manual)

Run this checklist in Roblox Studio on a machine with Rojo + Studio access, then update this report with pass/fail outcomes and file/link any runtime bugs discovered.
