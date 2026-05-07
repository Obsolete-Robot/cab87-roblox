import fs from 'fs';
let code = fs.readFileSync('src/lib/meshing.ts', 'utf8');

// Replace dashedLines.push
let changed = false;
let lines = code.split(/\r?\n/);
let newLines = [];

for (let i = 0; i < lines.length; i++) {
    if (lines[i].includes("mesh.dashedLines.push(linePoints);")) {
        newLines.push(lines[i].replace("mesh.dashedLines.push(linePoints);", "mesh.dashedLines.push({ points: linePoints, ignoreMeshing: skipRoadMeshing } as any);"));
        newLines.push("                if (!skipRoadMeshing) {");
        changed = true;
    } else if (lines[i].trim() === "} else {" && lines[i-1] && lines[i-1].trim() === "}") {
        // we have two closing braces instead of one
        if (lines[i-2] && lines[i-2].trim() === "}") {
            // " lengthSoFar += dist; \n } \n } \n } else {"
            // Wait, we WANT THREE braces to close the new `if (!skipRoadMeshing) {`
            // Let's just output `lines[i]`
            newLines.push(lines[i]);
        } else {
            // We just added `if (!skipRoadMeshing) {`
            // Wait...
            newLines.push("                }"); // close if (!skipRoadMeshing)
            newLines.push(lines[i]); // `} else {`
        }
    } else {
        newLines.push(lines[i]);
    }
}

fs.writeFileSync('src/lib/meshing.ts', newLines.join('\n'));
console.log("Replaced. Changed?", changed);
