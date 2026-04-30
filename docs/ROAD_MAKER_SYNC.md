# Road-Maker Sync

`tools/intersection-visualizer` is maintained as Cab87's Roblox-facing integration of
the upstream Road-Maker editor:

```sh
git remote add road-maker https://github.com/dbokser/Road-Maker.git
git fetch road-maker main
```

Use a review branch for every upstream sync:

```sh
git checkout main
git pull --ff-only
git checkout -b sync/road-maker-YYYYMMDD
git fetch road-maker main
git merge -s subtree -Xsubtree=tools/intersection-visualizer --allow-unrelated-histories --no-commit road-maker/main
```

Resolve conflicts in favor of Cab87-specific integration where needed:

- keep the `cab87-road-network` export schema, `version`, and Studio import settings;
- keep Roblox-facing settings such as `chamferAngleDeg` and `meshResolution`;
- keep local workflow fixes that do not exist upstream, such as merge-mode behavior;
- do not commit generated `dist`, `node_modules`, `.rbxl`, `.rbxlx`, or temporary Studio artifacts.

After resolving conflicts, run:

```sh
cd tools/intersection-visualizer
npm run lint
npm run build
cd ../..
rojo build default.project.json --output cab87.rbxlx
```

Review the diff before committing. Upstream Road-Maker is the source for editor mesh
math improvements; Cab87 remains the source for Roblox export/import and runtime bake
behavior.
