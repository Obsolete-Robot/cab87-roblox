# Road Curve Editor

Static browser tool for authoring top-down road splines that match the Roblox road editor's Catmull-Rom sampling preview.

## Run

Windows:

```bat
run.bat
```

macOS:

```sh
./run.command
```

You can also double-click `run.command` in Finder.

If Python is available, these scripts start a local static server at `http://127.0.0.1:8000/index.html`. Otherwise they open `index.html` directly.

Manual:

- Open `index.html` in a browser, or
- Serve the folder with any static file server.

## Workflow

1. Import a trace image if you want a background reference.
2. The active spline is always in edit mode.
3. Drag an existing control point to refine it.
4. Click near the active curve to add points:
   - Near the start inserts at the beginning.
   - Near the end appends to the end.
   - Between existing points inserts in the middle.
   - Clicking away from the curve on an open spline extends whichever end is closer.
   - New points enter drag immediately on creation.
5. Use `Split Curve` after selecting an interior point on an open curve to split it into two curves sharing that split point.
6. Use `New`, `Prev`, `Next`, `Delete`, `Road Width`, `Closed loop`, and `Roblox Mesh Preview` to manage splines and preview the authored-road mesh footprint/wireframe.
7. Use `Junction Mode` to click an existing curve point and create a junction from real road geometry. Dragging a junction center moves only the junction; dragging the radius ring changes where incoming roads get clipped into the junction. Use `Auto Junction` on a selected junction to recenter it from the sampled road entrances inside that radius. The final junction polygon is built from those clipped road entrances plus the authored center. Roundabouts should be authored as a closed loop with one junction at each entry/exit on the loop.
8. The browser autosaves the editor session locally and restores it after refresh, including incomplete curves. Large trace images may exceed browser storage quota; in that case the curve data still autosaves without the image data.
9. Export `cab87-road-curves.json` to save the full editor session, including camera state and the trace image data/transform.
10. Use `Import Session JSON` in the browser tool to resume where you left off.
11. In Roblox Studio, use the road editor plugin's `Import Curve JSON (Append)` or `Import Curve JSON (Replace)` action on that same JSON file.

## JSON Format

The exported payload stays shaped for the Studio plugin importer and adds an `editorState` block for resumable browser sessions:

```json
{
  "version": 2,
  "sampleStepStuds": 8,
  "coordinateSpace": {
    "upAxis": "Y",
    "planarAxes": ["X", "Z"],
    "units": "studs"
  },
  "splines": [
    {
      "name": "Spline001",
      "closed": false,
      "width": 28,
      "points": [
        { "x": 0, "y": 0, "z": 0 },
        { "x": 64, "y": 0, "z": 32 }
      ]
    }
  ],
  "junctions": [
    { "id": "Junction001", "x": 64, "y": 0, "z": 32, "radius": 22, "subdivisions": 0 }
  ],
  "editorState": {
    "camera": { "x": 12, "z": 48, "zoom": 1.35 },
    "activeSplineIndex": 0,
    "selectedPoint": { "splineIndex": 0, "pointIndex": 1 },
    "image": {
      "fileName": "trace.png",
      "mimeType": "image/png",
      "width": 2048,
      "height": 2048,
      "dataUrl": "data:image/png;base64,...",
      "offsetX": 0,
      "offsetZ": 0,
      "scale": 1,
      "opacity": 55
    }
  }
}
```
