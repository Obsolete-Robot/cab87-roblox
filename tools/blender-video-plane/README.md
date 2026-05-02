# Cab87 Blender Video Plane Tool

Blender add-on for quickly loading a video file as a correctly proportioned plane with a movie texture material.

## Install

1. In Blender, open `Edit > Preferences > Add-ons`.
2. Click `Install...`.
3. Run `package.bat` and select the generated `cab87_video_plane_tool_vX.Y.Z.zip`, or copy the `cab87_video_plane_tool` folder into Blender's scripts/addons directory.
4. Enable `Import-Export: Cab87 Video Plane Tool`.

The panel appears in `3D Viewport > Sidebar > Cab87 > Video Plane`.

## Workflow

1. Open the `Cab87 > Video Plane` panel.
2. Click `Load Video Plane` and choose a movie file.
3. The add-on creates:
   - a `Cab87VideoPlanes` collection.
   - a mesh plane sized to the movie aspect ratio.
   - UVs that fill the plane.
   - a material with a movie image texture wired into either an Emission or Principled shader.

By default, the plane is created at the 3D cursor, sized by width, and uses an Emission material so the video is easy to preview without scene lighting.

## Options

- `Fit By` and `Fit Size` choose whether the target size controls plane width or height.
- `Fallback Width` and `Fallback Height` are used when Blender cannot read dimensions from the movie file.
- `Placement` can use the 3D cursor or place the plane in front of the active camera.
- `Use Alpha` blends the material with the movie alpha channel when the video format includes one.
- `Auto Refresh` keeps the movie texture updating during playback.
- `Set Scene Frame Range` sets the scene range to the detected movie duration when Blender exposes it.

## Validation

```sh
python3 -m py_compile tools/blender-video-plane/cab87_video_plane_tool/__init__.py
```

If Blender is available on PATH, enable the add-on and load a short test movie to verify the generated plane, UVs, material, and timeline range.
