# Procedural Intersection Generator

This application procedurally generates and visualizes complex road intersections based on angular mathematics and 2D mesh generation.

## Cab87 Roblox Workflow

Run locally:

```sh
./run.sh
```

Open `http://localhost:3000`, author the graph, tune **Mesh Split Size** for distance-based mesh density, then export JSON. The export format is `schema: "cab87-road-network"` / `version: 2` and is imported by the `Cab87 Road Graph Builder` Studio plugin. You can also export the current generated mesh as OBJ or GLB from the header; GLB keeps material colors, while OBJ is mostly geometry/object names. Use **Roblox** export for the large-map workflow: it downloads `cab87-road-mesh.zip`, containing a chunked GLB plus `cab87-road-mesh.manifest.json`, with visual and collision objects split by tile, elevation band, and triangle budget. The Roblox dropdown can also download the chunked GLB and manifest as individual files. In Studio, import the JSON, unzip and import the GLB with the 3D Importer, select the imported model, then click **Adopt Imported GLB Mesh** in the plugin and choose the manifest.

Press **B** to toggle building mode. Left-click footprint vertices in the 2D view, then close the polygon by clicking the first vertex or pressing Enter. Building vertices can be dragged from the base in either view, the center handle moves the whole footprint in XY, and Shift-dragging the center/top handle in 3D adjusts height.

Use **Building Fill** after selecting road edges or junctions to generate buildings from the current sidewalk edges. Open road selections place frontage buildings on both sides of the road. Closed block selections use the inner sidewalk boundary and generate four-point strip buildings along road curves and junction corners without collapsing footprints into the block center. Building fill keeps generated footprints linked to the selected roads, so adjusting a road curve regenerates the linked buildings from the updated sidewalk edge. Moving a generated building or dragging one of its vertices turns that footprint into a manual building. Tune min/max frontage width and vertical height in **Global > Settings**.

Mesher changes must stay in parity with Roblox's Luau port in `src/shared/RoadGraphMesher.lua`.
See [`../../docs/ROAD_MAKER_SYNC.md`](../../docs/ROAD_MAKER_SYNC.md) before changing
`src/lib/meshing.ts`.

## Export Format

Exports use the `cab87-road-network` JSON schema with `version: 2`. The payload includes
`settings` for mesh-affecting editor options and the authored `nodes`, `edges`, and
`buildings` arrays. If a reference image is loaded in the Global tab, the exported
JSON also includes a self-contained `backgroundImage` object with its filename,
position, scale, opacity, and embedded image data:

```json
{
  "schema": "cab87-road-network",
  "version": 2,
  "settings": {
    "chamferAngleDeg": 70,
    "meshResolution": 20,
    "buildingFill": {
      "minWidth": 48,
      "maxWidth": 120,
      "minHeight": 50,
      "maxHeight": 160
    }
  },
  "nodes": [],
  "edges": [],
  "buildings": [
    {
      "id": "building-1",
      "name": "Building 1",
      "vertices": [{ "x": -80, "y": -60 }, { "x": -20, "y": -60 }, { "x": -20, "y": 20 }],
      "baseZ": 4,
      "height": 80,
      "color": "#64748b",
      "material": "Concrete"
    }
  ],
  "backgroundImage": {
    "filename": "reference-map.png",
    "position": { "x": -512, "y": -384 },
    "scale": 1,
    "opacity": 0.65,
    "dataUrl": "data:image/png;base64,..."
  }
}
```

Imports remain backwards compatible with earlier Road-Maker exports that only contain
`nodes` and `edges`.

## Technical Details: Intersection and Meshing

The architecture cleanly separates the mathematical logic from the view layer, providing an accurate, triangulated geometric representation of how multiple roads of varying widths interact at a central 2D point.

### 1. Data Structure & Angular Ordering (`src/lib/junction.ts`)
The initial state is a network of roads radiating from a single center node. 
The mathematical backbone begins by calculating the vector direction mapping for each road. Using the polar coordinate system (`Math.atan2`), the system sorts all roads sequentially around the center point. This strict ordering is required to accurately determine which roads are adjacent to each other.

### 2. Corner Resolution (`src/lib/math.ts` & `src/lib/junction.ts`)
Once adjacent roads are known, the system calculates the outer geometric shape (the "silhouette") of the junction.
- **Boundary Offsets:** It uses the perpendicular vector (the "normal") of each road's direction vector, scaled by `width / 2`, to find the left and right continuous boundary lines for every road.
- **Line Intersections:** It calculates the intersection point of the left boundary of one road with the right boundary of the adjacent road using 2D linear parametrization.
- **Edge Cases:** The intersection algorithm handles parallel tracks and extremely acute angles by capping projection bounds to ensure the physical corner isn't projected miles away.

### 3. Mesh Generation (`src/lib/mesher.ts`)
With corner vertices resolved, the intersection's visual surface must be "meshed"—divided into a set of standard triangles (`Triangle[]`) that can be used for solid-fill rendering, physics, or exported for 3D extrusion.
- **The Hub Silhouette:** The core junction shape is compiled by gathering the resolved corner intersection points into an ordered `hubPolygon`.
- **Hub Triangulation:** A classic triangle fan connects the intersection center coordinate to the sequential vertices of the `hubPolygon` boundaries.
- **Road Segments:** Standard road quads (and their component triangles) are created between the terminating edges of the new `hubPolygon` and the far endpoints of the respective lines. This establishes clean `roadPolygons` attached exactly to the limits of the hub.

### 4. Display Layer (`src/App.tsx`)
The view layer parses these mathematical constructs using the HTML5 Canvas API. By drawing the `vertices` array as a continuous polygon for the hub silhouette, then extending to the `roadPolygons` for the streets, the app creates perfectly un-overlapping filled tracks. It then leverages the exact hub/road boundary lines (`bL`, `bR`) to accurately plot localized street elements, such as crosswalks and solid road border strokes.
