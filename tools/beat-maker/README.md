# Cab87 Beat Maker

Blender add-on that analyzes a drum audio stem, detects major bass drum/kick beats, and keyframes camera FOV or single-axis position pulses on those beat frames.

## Install

1. In Blender, open `Edit > Preferences > Add-ons`.
2. Click `Install...`.
3. Run `package.bat` and select the generated `cab87_beat_maker_vX.Y.Z.zip`, or copy the `cab87_beat_maker` folder into Blender's scripts/addons directory.
4. Enable `Animation: Cab87 Beat Maker`.

The panel appears in `3D Viewport > Sidebar > Cab87 > Beat Maker`.

## Workflow

1. Use a drum stem or kick-heavy audio file. For a full mixed song, create a drum stem first with a tool such as Demucs.
2. Open `Cab87 > Beat Maker`.
3. Click `Choose Drum Stem`.
4. Pick the target camera, or leave it empty to use the active scene camera.
5. Set:
   - `Animate FOV`: keyframe camera FOV pulses.
   - `Default FOV`: the normal camera FOV.
   - `Beat FOV`: the FOV on each detected beat frame.
   - `Animate Position`: keyframe one camera location axis with the same beat pulse timing.
   - `Position Axis`: the camera location axis to move.
   - `Default Pos`: the normal location value on that axis.
   - `Beat Pos`: the location value on that axis at each detected beat frame.
   - `Frames To Beat`: how many frames before each beat should key the default value.
   - `Settle Frames`: how many frames after each beat should return to the default value.
6. Click `Animate Beat Camera`.

For every detected major beat, the add-on creates this keyframe shape:

```text
beat frame - Frames To Beat: Default FOV / Default Pos
beat frame:                  Beat FOV / Beat Pos
beat frame + Settle Frames:  Default FOV / Default Pos
```

## Audio Formats

Direct built-in analysis supports PCM `.wav`, `.aif`, `.aiff`, and `.aifc` files.

For `.mp3`, `.flac`, `.ogg`, or `.m4a`, enable `Use FFmpeg For Non-WAV` and make sure the `ffmpeg` command is available, or set `FFmpeg Path` to the executable.

## Beat Detection

The detector is dependency-free and tuned for drum stems. It focuses on low-frequency energy, finds onset peaks, keeps only stronger candidates, then applies a minimum beat gap.

Useful tuning:

- Lower `Sensitivity` to detect more beats.
- Lower `Major Beat Percentile` to keep more kick hits.
- Raise `Min Beat Gap ms` if double hits are being detected.
- Adjust `Bass Cutoff` if the kick sits unusually low or high.

## Validation

```sh
python3 -m py_compile tools/beat-maker/cab87_beat_maker/__init__.py tools/beat-maker/cab87_beat_maker/audio_analysis.py
python3 -m unittest discover -s tools/beat-maker/tests
```

If Blender is available, install the add-on, choose a short drum stem, and verify that the camera data has `angle` keyframes and, when `Animate Position` is enabled, that the camera object has selected-axis `location` keyframes on the detected beat frames.
