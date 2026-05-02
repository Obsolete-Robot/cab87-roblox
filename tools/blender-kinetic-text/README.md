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
- font file and font size.
- material color and alpha.
- bevel depth and resolution.
- extrusion.
- fill mode and curve resolution.
- word pop-in and section clear keyframes.

Words keep their timing data as custom properties on the generated Text objects. You can edit a Text object's body in Blender and then run `Apply Layout And Style To Group` to relayout with the edited text.

## Animation Behavior

Each word starts transparent and scaled down, then pops in at its word start time. Words stay visible inside their current section. When a new section begins, the previous section fades out over the configured clear frames.

Sections are determined only by `breakAfter` break points from the kinetic JSON.

Within each section, lines wrap by max characters per line.

## Validation

The layout code can be tested without Blender:

```sh
python3 -m unittest discover tools/blender-kinetic-text/tests
python3 -m py_compile tools/blender-kinetic-text/cab87_kinetic_text_importer/layout.py
```

If Blender is available on PATH, enable the add-on and import a sample JSON to verify text creation, parent Empty transforms, and style updates.
