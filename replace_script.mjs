import fs from 'fs';

let content = fs.readFileSync('src/lib/meshing.ts', 'utf8');
content = "import { DEFAULTS } from './constants';\n" + content;
content = content.replace(/\?\? 24/g, '?? DEFAULTS.sidewalkWidth');
fs.writeFileSync('src/lib/meshing.ts', content);
console.log('Updated meshing.ts');

let content2 = fs.readFileSync('src/lib/junctions.ts', 'utf8');
content2 = "import { DEFAULTS } from './constants';\n" + content2;
content2 = content2.replace(/\?\? 24/g, '?? DEFAULTS.sidewalkWidth');
fs.writeFileSync('src/lib/junctions.ts', content2);
console.log('Updated junctions.ts');
