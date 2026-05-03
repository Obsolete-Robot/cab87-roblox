# Cab87 Blender Kinetic Text Importer

Blender add-on for importing `Kinetic JSON` exported from `tools/dialogue-timing-tool` and turning the word timing into animated Text objects.

## Install

1. In Blender, open `Edit > Preferences > Add-ons`.
2. Click `Install...`.
3. Run `package.bat` and select the generated `cab87_kinetic_text_importer_vX.Y.Z.zip`, or copy the `cab87_kinetic_text_importer` folder into Blender's scripts/addons directory.
4. Enable `Import-Export: Cab87 Kinetic Text Importer`.

The panel appears in `3D Viewport > Sidebar > Cab87 > Kinetic Text`.

## Package And Publish

Windows scripts mirror the BlenderPipeline workflow:

- `package.bat` creates a versioned add-on zip from `cab87_kinetic_text_importer`.
- `publish.bat` copies the add-on into every installed Blender version under `%APPDATA%\Blender Foundation\Blender`.

Version metadata lives in two places and must stay in sync:

- `cab87_kinetic_text_importer/__init__.py` -> `bl_info["version"]`.
- `cab87_kinetic_text_importer/blender_manifest.toml` -> `version`.

`package.bat` validates those versions match before creating the zip. The add-on also runs a BlenderPipeline-style version gate at registration time to disable older installed copies of the same add-on family.

## Workflow

1. Export `Kinetic JSON` from `tools/dialogue-timing-tool`.
2. In Blender, open the `Cab87 > Kinetic Text` panel.
3. Set layout, animation, and text style defaults.
4. Click `Import Kinetic Text JSON` and choose the exported timing file.

The add-on creates:

- a collection named `Cab87_KineticText_<file>`.
- a parent Empty named `Cab87KineticText_Group`.
- one animated Text object per timed word.

Move, rotate, or scale the parent Empty to reposition the whole word group without disturbing individual word timing.

## Editing After Import

Select the parent Empty, or any generated word, click `Load Group Settings`, adjust panel settings, then click `Apply Layout And Style To Group`.

The update pass reapplies:

- max characters per line.
- word and line spacing.
- horizontal and vertical alignment.
- font file and font size.
- material color and alpha.
- JSON default color, word color overrides, and color swatch remaps.
- bevel depth and resolution.
- extrusion.
- fill mode and curve resolution.
- start/end animation type, overshoot, and section clear keyframes.

Words keep their timing data as custom properties on the generated Text objects. You can edit a Text object's body in Blender and then run `Apply Layout And Style To Group` to relayout with the edited text.

## Animation Behavior

Each word uses the configured `Start Animation` mode when it reaches its word start time. Start animation can fade, scale, or scale and fade. Scale starts can overshoot above full scale, then settle back after the configured overshoot and settle frame counts.

Words stay visible inside their current section. When a new section begins, the previous section uses the configured `End Animation` mode over the clear frame range. End animation can fade, scale, or scale and fade.

When a new section begins entering after a break point, the previous section is cleared by that incoming intro frame. If an intro animation would overlap the clear range, the add-on suppresses intro keys at or after the end animation start frame so the end animation remains the final keyframe sequence.

Sections are determined only by `breakAfter` break points from the kinetic JSON.

Within each section, lines wrap by max characters per line.

## Color Remapping

When a kinetic JSON file includes `customColors`, `defaultColor`, or per-word color overrides, the add-on imports those swatches into the `Text Style` color section. Each source swatch gets a material color picker so the Blender scene can remap the JSON color breakouts without editing the timing file.

`Apply Layout And Style To Group` reapplies the current remaps to generated word materials and stores the remap table on the parent group.

The reapply pass clears generated word object, curve, material, and material node-tree animation before rebuilding keys so stale scale or alpha keys do not accumulate.

## Validation

The layout code can be tested without Blender:

```sh
python3 -m unittest discover tools/blender-kinetic-text/tests
python3 -m py_compile tools/blender-kinetic-text/cab87_kinetic_text_importer/layout.py
```

If Blender is available on PATH, enable the add-on and import a sample JSON to verify text creation, parent Empty transforms, and style updates.
