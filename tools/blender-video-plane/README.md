# Cab87 Blender Video Plane Tool

Blender add-on for quickly loading a video file as a correctly proportioned plane with a movie texture material. It can also import DaVinci Resolve / Final Cut Pro 7 `xmeml` exports as a grid of cut planes with an optional camera animated across the edit.

## Install

1. In Blender, open `Edit > Preferences > Add-ons`.
2. Click `Install...`.
3. Run `package.bat` and select the generated `cab87_video_plane_tool_vX.Y.Z.zip`, or copy the `cab87_video_plane_tool` folder into Blender's scripts/addons directory.
4. Enable `Import-Export: Cab87 Video Plane Tool`.

The panel appears in `3D Viewport > Sidebar > Cab87 > Video Plane`. Creation/import controls live under the collapsible `Create` section, and keying/fade tools live under `Edit`.

## Workflow

### Single Video

1. Open the `Cab87 > Video Plane` panel.
2. Click `Load Video Plane` and choose a movie file.
3. The add-on creates:
   - a `Cab87VideoPlanes` collection.
   - a mesh plane sized to the movie aspect ratio.
   - UVs that fill the plane.
   - a material with a movie image texture wired into either an Emission or Principled shader.

By default, the plane is created at the 3D cursor, sized by width, and uses an Emission material so the video is easy to preview without scene lighting.

### Opacity Fades

1. Select one plane created by this tool.
2. In `Cab87 > Video Plane > Edit > Opacity`, click `Load Selected Plane`.
3. Move the `Opacity` slider to preview the fade on that loaded target.
4. Click `Key Opacity` at the current timeline frame.
5. Move to another frame, set a different opacity, and click `Key Opacity` again.

`Live Slider` applies slider edits immediately to the loaded target plane. If no target is loaded, the opacity tools will use exactly one selected Cab87 video plane; selecting multiple Cab87 video planes is treated as an error. Opacity keyframes are stored on each plane material's `Cab87 Video Opacity` shader value node, so XML timing and movie texture offsets stay independent from fade animation.

### Resolve / FCP XML Grid

1. Export an XML timeline from Resolve using the Final Cut Pro 7 / `xmeml` format.
2. In `Cab87 > Video Plane > Resolve/FCP XML`, click `Import XML Video Grid`.
3. Choose the XML file.
4. The add-on creates one plane per enabled video clip, laid out in a grid in timeline order.
5. Each plane stores the clip metadata as custom properties and sets the movie texture to start at the clip's source in-frame on the clip's timeline start frame.
6. Resolve Time Remap speed/keyframe data is converted into Blender movie texture offset keyframes so sped-up clips advance through the source video at the imported speed.
7. `Handle Frames` runs each movie texture before and after the cut so edits can be adjusted in Blender with source handles available.
8. When `Animate Camera` is enabled, the add-on creates or reuses `Cab87 XML Cut Camera`, parents it under `Cab87 XML Cut Camera Panner`, parents that under the cut-animated pivot at the active grid cell, and makes it the active scene camera. Animate the panner for local pans while the pivot continues to follow the edit.

If the XML points to media paths that do not exist on the current machine, set `Media Root Override` to the folder containing the video files. The importer resolves those clips by filename.

## Options

- `Fit By` and `Fit Size` choose whether the target size controls plane width or height.
- `Fallback Width` and `Fallback Height` are used when Blender cannot read dimensions from the movie file.
- `Placement` can use the 3D cursor or place the plane in front of the active camera.
- `Use Alpha` blends the material with the movie alpha channel when the video format includes one.
- `Auto Refresh` keeps the movie texture updating during playback.
- `Opacity` fades the loaded or single selected Cab87 video plane and can be keyed for transitions.
- `Set Scene Frame Range` sets the scene range to the detected movie duration when Blender exposes it.
- `Grid Columns` controls XML grid layout. Use `0` for automatic columns.
- `Clear Previous XML Import` removes objects previously created by the XML importer before importing again.
- `Add Cut Markers` creates timeline markers at each imported clip start.
- `Handle Frames` adds pre/post roll to each imported movie texture without moving the actual camera cut frames.
- `Camera Interpolation` defaults to hard cuts so the camera matches the edit, with linear and smooth move options for animatic passes.

## Validation

```sh
python3 -m py_compile tools/blender-video-plane/cab87_video_plane_tool/__init__.py
```

If Blender is available on PATH, enable the add-on and load a short test movie to verify the generated plane, UVs, material, and timeline range.
