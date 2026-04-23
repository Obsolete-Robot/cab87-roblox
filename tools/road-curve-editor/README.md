# Road Curve Editor

Static browser tool for authoring top-down road splines that match the Roblox road editor's Catmull-Rom sampling preview.

## Run

Windows:

```bat
run.bat
```

If Python is available, that starts a local static server at `http://127.0.0.1:8000/index.html`. Otherwise it opens `index.html` directly.

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
5. Use `New`, `Prev`, `Next`, `Delete`, `Road Width`, `Closed loop`, and `Roblox Mesh Preview` to manage splines and preview the authored-road mesh footprint/wireframe.
6. Export `cab87-road-curves.json` to save the full editor session, including camera state and the trace image data/transform.
7. Use `Import Session JSON` in the browser tool to resume where you left off.
8. In Roblox Studio, use the road editor plugin's `Import Curve JSON (Append)` or `Import Curve JSON (Replace)` action on that same JSON file.

## JSON Format

The exported payload stays shaped for the Studio plugin importer and adds an `editorState` block for resumable browser sessions:

```json
{
  "version": 1,
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
