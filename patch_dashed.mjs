import fs from 'fs';
let code = fs.readFileSync('src/lib/meshing.ts', 'utf8');
code = code.replace(
    "if (divider.type === 'dashed') {\n                mesh.dashedLines.push(linePoints);\n                 let lengthSoFar = 0;",
    "if (divider.type === 'dashed') {\n                mesh.dashedLines.push({ points: linePoints, ignoreMeshing: skipRoadMeshing } as any);\n                if (!skipRoadMeshing) {\n                 let lengthSoFar = 0;"
);

// We still have the syntax error here, wait where exactly is it?
const fix1 = "lengthSoFar += dist;\n                }\n            }\n            } else {";
const to1 = "lengthSoFar += dist;\n                }\n               }\n            } else {";
code = code.replace(fix1, to1);

fs.writeFileSync('src/lib/meshing.ts', code);
