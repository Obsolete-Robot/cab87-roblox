import fs from 'fs';
let code = fs.readFileSync('src/lib/meshing.ts', 'utf8');

// replace sidewalkPolygons for leftSidewalkPoly
code = code.replace(
    /mesh\.sidewalkPolygons\.push\(leftSidewalkPoly\);/,
    "mesh.sidewalkPolygons.push({ polygon: leftSidewalkPoly, ignoreMeshing: skipRoadMeshing });"
);

// replace sidewalkPolygons for rightSidewalkPoly
code = code.replace(
    /mesh\.sidewalkPolygons\.push\(rightSidewalkPoly\);/,
    "mesh.sidewalkPolygons.push({ polygon: rightSidewalkPoly, ignoreMeshing: skipRoadMeshing });"
);

code = code.replace(
    `            sidewalkWidth: edge.sidewalk ?? DEFAULTS.sidewalkWidth`,
    `            sidewalkWidth: edge.sidewalk ?? DEFAULTS.sidewalkWidth,\n            ignoreMeshing: skipRoadMeshing`
);

code = code.replace(
    /mesh\.laneArrows\.push\({ position: pos, dir: center.dir === 1 \? dir : { x: -dir\.x, y: -dir\.y } }\);/g,
    "mesh.laneArrows.push({ position: pos, dir: center.dir === 1 ? dir : { x: -dir.x, y: -dir.y }, ignoreMeshing: skipRoadMeshing });"
);

let lines = code.split('\n');
let newLines = [];
for (let i = 0; i < lines.length; i++) {
    if (lines[i].includes("for (let j = 0; j < leftPoints.length; j++) {")) {
        newLines.push("       if (!skipRoadMeshing) {");
        newLines.push(lines[i]);
    } else if (lines[i].includes("if (tbL && tbR && otbL && otbR) {")) {
        newLines.push("       }"); // close skipRoadMeshing over the for loop
        newLines.push("       if (!skipRoadMeshing && tbL && tbR && otbL && otbR) {");
    } else {
        newLines.push(lines[i]);
    }
}
fs.writeFileSync('src/lib/meshing.ts', newLines.join('\n'));

let render2d = fs.readFileSync('src/lib/render2d.ts', 'utf8');
render2d = render2d.replace(/mesh\.sidewalkPolygons\.forEach\(poly => \{/g, `mesh.sidewalkPolygons.forEach(pObj => {\n    const poly = pObj.polygon;\n    if (pObj.ignoreMeshing) return;`);
render2d = render2d.replace(/mesh\.roadPolygons\.forEach\(rp => \{/g, `mesh.roadPolygons.forEach(rp => {\n    if (rp.ignoreMeshing) return;`);
render2d = render2d.replace(/mesh\.dashedLines\.forEach\(line => \{/g, `mesh.dashedLines.forEach(lineObj => {\n    const line = lineObj.points;\n    if (lineObj.ignoreMeshing) return;`);
render2d = render2d.replace(/mesh\.solidYellowLines\.forEach\(line => \{/g, `mesh.solidYellowLines.forEach(lineObj => {\n    const line = lineObj.points;\n    if (lineObj.ignoreMeshing) return;`);

// What about laneArrows?
render2d = render2d.replace(/mesh\.laneArrows\.forEach\(arrow => \{/g, `mesh.laneArrows.forEach(arrow => {\n    if (arrow.ignoreMeshing) return;`);

fs.writeFileSync('src/lib/render2d.ts', render2d);
