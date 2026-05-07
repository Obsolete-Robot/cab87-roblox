import fs from 'fs';
let code = fs.readFileSync('src/lib/meshing.ts', 'utf8');

let fixed = code.replace(
    /mesh\.dashedLines\.push\(linePoints\);\s+let lengthSoFar/g,
    `mesh.dashedLines.push({ points: linePoints, ignoreMeshing: skipRoadMeshing } as any);\n                if (!skipRoadMeshing) {\n                 let lengthSoFar`
);

fixed = fixed.replace(
    /lengthSoFar \+\= dist;\n\s+\}\n\s+\}\n\s+\} else \{/g,
    `lengthSoFar += dist;\n                 }\n                }\n            } else {`
);

fs.writeFileSync('src/lib/meshing.ts', fixed);
console.log("Done");
