import fs from 'fs';
let code = fs.readFileSync('src/lib/meshing.ts', 'utf8');

code = code.replace(
`  const nodeOuterCorners = new Map<string, Map<string, Point[]>>();

  // 1. Build Hubs`,
`  const nodeOuterCorners = new Map<string, Map<string, Point[]>>();

  const roadNodes = nodes.filter(n => !n.ignoreMeshing);
  const roadEdges = edges.filter(e => {
    const s = nodes.find(n => n.id === e.source);
    const t = nodes.find(n => n.id === e.target);
    return !(s?.ignoreMeshing || t?.ignoreMeshing);
  });

  // 1. Build Hubs`
);

let lines = code.split('\n');
let newLines = [];
let inHubsOrRoads = false;
for (let i = 0; i < lines.length; i++) {
  let line = lines[i];
  if (line.includes('// 1. Build Hubs')) inHubsOrRoads = true;
  if (line.includes('// 3. Build Polygon Fills')) inHubsOrRoads = false;
  
  if (inHubsOrRoads) {
    line = line.replace(/for \(const node of nodes\) \{/g, "for (const node of roadNodes) {");
    line = line.replace(/for \(const edge of edges\) \{/g, "for (const edge of roadEdges) {");
    line = line.replace(/getIncidentConnections\(node\.id, edges\)/g, "getIncidentConnections(node.id, roadEdges)");
    line = line.replace(/hasCrosswalk\((.*?), nodes, edges\)/g, "hasCrosswalk($1, nodes, roadEdges)");
    line = line.replace(/isTrueJunction\((.*?), nodes, edges\)/g, "isTrueJunction($1, nodes, roadEdges)");
  }
  newLines.push(line);
}
fs.writeFileSync('src/lib/meshing.ts', newLines.join('\n'));
