# Procedural Intersection Generator

This application procedurally generates and visualizes complex road intersections based on angular mathematics and 2D mesh generation.

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
