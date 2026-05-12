import * as THREE from 'three';
import { GLTFExporter } from 'three/examples/jsm/exporters/GLTFExporter.js';
import { OBJExporter } from 'three/examples/jsm/exporters/OBJExporter.js';
import { MeshData, Point, Triangle } from './types';

type MeshLayer = {
  name: string;
  triangles: Triangle[];
  color: string;
  yOffset?: number;
  opacity?: number;
};

type RobloxChunkLayer = {
  layer: string;
  baseName: string;
  surfaceType: string;
  triangles: Triangle[];
  color: string;
  material: string;
  yOffset?: number;
  kind?: 'surface' | 'marking';
  includeCollision?: boolean;
  collisionBaseName?: string;
  driveSurface?: boolean;
  crashObstacle?: boolean;
  buildingId?: string;
};

type Bounds = {
  min: { x: number; y: number; z: number };
  max: { x: number; y: number; z: number };
  size: { x: number; y: number; z: number };
};

type TriangleBucket = {
  chunkX: number;
  chunkY?: number;
  chunkZ: number;
  triangles: Triangle[];
};

const ROBLOX_MANIFEST_SCHEMA = 'cab87-road-mesh-manifest';
const ROBLOX_MANIFEST_VERSION = 1;
const ROBLOX_CHUNK_SIZE = 768;
const ROBLOX_MAX_SURFACE_TRIANGLES = 6000;
const ROBLOX_MAX_COLLISION_INPUT_TRIANGLES = 900;
const ROBLOX_COLLISION_THICKNESS = 0.2;
const ROBLOX_COLLISION_VERTICAL_CHUNK_SIZE = 12;
const ROBLOX_PACKAGE_BASENAME = 'cab87-road-mesh';

export type RobloxRoadMeshExportMode = 'zip' | 'glb' | 'manifest' | 'files';

export function createTriangleGeometry(triangles: Point[][], yOffset = 0, defaultY = 4): THREE.BufferGeometry {
  const positions: number[] = [];
  const uvs: number[] = [];

  triangles.forEach((tri) => {
    if (tri.length !== 3) return;

    tri.forEach((point) => {
      positions.push(point.x, (point.z ?? defaultY) + yOffset, point.y);
      uvs.push(point.u ?? 0, point.v ?? 0);
    });
  });

  return createGeometryFromPositions(positions, uvs);
}

function createGeometryFromPositions(positions: number[], uvs?: number[]): THREE.BufferGeometry {
  const geometry = new THREE.BufferGeometry();
  geometry.setAttribute('position', new THREE.Float32BufferAttribute(positions, 3));

  if (uvs && uvs.length > 0) {
    geometry.setAttribute('uv', new THREE.Float32BufferAttribute(uvs, 2));
  }

  geometry.computeVertexNormals();
  geometry.computeBoundingBox();
  geometry.computeBoundingSphere();
  return geometry;
}

function addTrianglePositions(positions: number[], a: THREE.Vector3, b: THREE.Vector3, c: THREE.Vector3) {
  positions.push(a.x, a.y, a.z, b.x, b.y, b.z, c.x, c.y, c.z);
}

function addQuadPositions(positions: number[], a: THREE.Vector3, b: THREE.Vector3, c: THREE.Vector3, d: THREE.Vector3) {
  addTrianglePositions(positions, a, b, c);
  addTrianglePositions(positions, a, c, d);
}

function toVector(point: Point, yOffset = 0, defaultY = 4) {
  return new THREE.Vector3(point.x, (point.z ?? defaultY) + yOffset, point.y);
}

function createCollisionGeometry(
  triangles: Triangle[],
  yOffset = 0,
  thickness = ROBLOX_COLLISION_THICKNESS,
  defaultY = 4
) {
  const positions: number[] = [];
  const bottomOffset = new THREE.Vector3(0, -Math.max(thickness, 0.05), 0);

  triangles.forEach((triangle) => {
    const a = toVector(triangle[0], yOffset, defaultY);
    const b = toVector(triangle[1], yOffset, defaultY);
    const c = toVector(triangle[2], yOffset, defaultY);
    const ab = a.clone().add(bottomOffset);
    const bb = b.clone().add(bottomOffset);
    const cb = c.clone().add(bottomOffset);

    addTrianglePositions(positions, a, b, c);
    addTrianglePositions(positions, ab, cb, bb);
    addQuadPositions(positions, a, ab, bb, b);
    addQuadPositions(positions, b, bb, cb, c);
    addQuadPositions(positions, c, cb, ab, a);
  });

  return createGeometryFromPositions(positions);
}

function createMaterial(name: string, color: string, opacity = 1) {
  const material = new THREE.MeshStandardMaterial({
    color,
    side: THREE.DoubleSide,
    transparent: opacity < 1,
    opacity,
  });
  material.name = name;
  return material;
}

function computeBounds(geometry: THREE.BufferGeometry): Bounds {
  geometry.computeBoundingBox();
  const box = geometry.boundingBox ?? new THREE.Box3();
  const size = new THREE.Vector3();
  box.getSize(size);
  return {
    min: { x: box.min.x, y: box.min.y, z: box.min.z },
    max: { x: box.max.x, y: box.max.y, z: box.max.z },
    size: { x: size.x, y: size.y, z: size.z },
  };
}

function safeName(value: string) {
  return value.replace(/[^A-Za-z0-9_]/g, '_').replace(/_+/g, '_').replace(/^_|_$/g, '');
}

function chunkLabel(value: number) {
  return value < 0 ? `n${Math.abs(value)}` : `p${value}`;
}

function chunkName(baseName: string, bucket: TriangleBucket, batchIndex: number) {
  const yLabel = bucket.chunkY === undefined ? '' : `_y${chunkLabel(bucket.chunkY)}`;
  return safeName(
    `${baseName}_x${chunkLabel(bucket.chunkX)}${yLabel}_z${chunkLabel(bucket.chunkZ)}_${String(batchIndex + 1).padStart(2, '0')}`
  );
}

function triangleCenter(triangle: Triangle, yOffset = 0, defaultY = 0) {
  return {
    x: (triangle[0].x + triangle[1].x + triangle[2].x) / 3,
    y: ((triangle[0].z ?? defaultY) + (triangle[1].z ?? defaultY) + (triangle[2].z ?? defaultY)) / 3 + yOffset,
    z: (triangle[0].y + triangle[1].y + triangle[2].y) / 3,
  };
}

function bucketTrianglesByCenter(
  triangles: Triangle[],
  chunkSize: number,
  options: { verticalChunkSize?: number; yOffset?: number; defaultY?: number } = {}
) {
  const bucketsByKey = new Map<string, TriangleBucket>();
  const verticalChunkSize = options.verticalChunkSize && options.verticalChunkSize > 0
    ? options.verticalChunkSize
    : undefined;

  triangles.forEach((triangle) => {
    const center = triangleCenter(triangle, options.yOffset ?? 0, options.defaultY ?? 0);
    const chunkX = Math.floor(center.x / chunkSize);
    const chunkY = verticalChunkSize === undefined ? undefined : Math.floor(center.y / verticalChunkSize);
    const chunkZ = Math.floor(center.z / chunkSize);
    const key = chunkY === undefined ? `${chunkX}:${chunkZ}` : `${chunkX}:${chunkY}:${chunkZ}`;
    let bucket = bucketsByKey.get(key);
    if (!bucket) {
      bucket = { chunkX, chunkY, chunkZ, triangles: [] };
      bucketsByKey.set(key, bucket);
    }
    bucket.triangles.push(triangle);
  });

  return [...bucketsByKey.values()].sort((a, b) => {
    if (a.chunkX === b.chunkX) {
      const ay = a.chunkY ?? 0;
      const by = b.chunkY ?? 0;
      if (ay === by) return a.chunkZ - b.chunkZ;
      return ay - by;
    }
    return a.chunkX - b.chunkX;
  });
}

function triangleBatches(triangles: Triangle[], maxTriangles: number) {
  const batches: Triangle[][] = [];
  const limit = Math.max(Math.floor(maxTriangles), 1);
  for (let index = 0; index < triangles.length; index += limit) {
    batches.push(triangles.slice(index, index + limit));
  }
  return batches;
}

function createMeshFromGeometry(name: string, geometry: THREE.BufferGeometry, color: string, opacity = 1) {
  const mesh = new THREE.Mesh(geometry, createMaterial(name, color, opacity));
  mesh.name = name;
  return mesh;
}

function addLayer(group: THREE.Group, layer: MeshLayer) {
  if (layer.triangles.length === 0) return;

  const mesh = new THREE.Mesh(
    createTriangleGeometry(layer.triangles),
    createMaterial(layer.name, layer.color, layer.opacity)
  );
  mesh.name = layer.name;
  mesh.position.y = layer.yOffset ?? 0;
  group.add(mesh);
}

function getRobloxLayers(meshData: MeshData): RobloxChunkLayer[] {
  const layers: RobloxChunkLayer[] = [
    {
      layer: 'roads',
      baseName: 'RoadSurface',
      collisionBaseName: 'RoadCollision',
      surfaceType: 'road',
      triangles: meshData.roadTriangles,
      color: '#1e293b',
      material: 'Asphalt',
      includeCollision: true,
    },
    {
      layer: 'junctions',
      baseName: 'RoadJunctionSurface',
      collisionBaseName: 'RoadJunctionCollision',
      surfaceType: 'road',
      triangles: meshData.hubTriangles,
      color: '#1e293b',
      material: 'Asphalt',
      yOffset: 0.05,
      includeCollision: true,
    },
    {
      layer: 'sidewalks',
      baseName: 'SidewalkSurface',
      collisionBaseName: 'SidewalkCollision',
      surfaceType: 'sidewalk',
      triangles: meshData.sidewalkTriangles,
      color: '#94a3b8',
      material: 'Concrete',
      yOffset: 0.15,
      includeCollision: true,
    },
    {
      layer: 'crosswalks',
      baseName: 'CrosswalkSurface',
      collisionBaseName: 'CrosswalkCollision',
      surfaceType: 'crosswalk',
      triangles: meshData.crosswalkTriangles,
      color: '#334155',
      material: 'SmoothPlastic',
      yOffset: 0.1,
      includeCollision: true,
    },
    {
      layer: 'dashedLaneLines',
      baseName: 'DashedLaneLine',
      surfaceType: 'marking',
      triangles: meshData.dashedLineTriangles,
      color: '#ffffff',
      material: 'SmoothPlastic',
      kind: 'marking',
    },
    {
      layer: 'solidLaneLines',
      baseName: 'SolidLaneLine',
      surfaceType: 'marking',
      triangles: meshData.solidLineTriangles,
      color: '#eab308',
      material: 'SmoothPlastic',
      kind: 'marking',
    },
  ];

  meshData.polygonTriangles.forEach((polygonGroup, index) => {
    layers.push({
      layer: `polygonFill_${index + 1}`,
      baseName: `PolygonFillSurface_${index + 1}`,
      collisionBaseName: `PolygonFillCollision_${index + 1}`,
      surfaceType: 'polygonFill',
      triangles: polygonGroup.triangles,
      color: polygonGroup.color,
      material: 'SmoothPlastic',
      yOffset: -1.5,
      includeCollision: true,
    });
  });

  meshData.buildingMeshes.forEach((building, index) => {
    layers.push({
      layer: `building_${index + 1}`,
      baseName: `BuildingSurface_${index + 1}`,
      collisionBaseName: `BuildingCollision_${index + 1}`,
      surfaceType: 'building',
      triangles: building.triangles,
      color: building.color,
      material: building.material || 'Concrete',
      includeCollision: true,
      driveSurface: false,
      crashObstacle: true,
      buildingId: building.id,
    });
  });

  return layers;
}

export function createRoadMeshExportGroup(meshData: MeshData): THREE.Group {
  const group = new THREE.Group();
  group.name = 'Cab87RoadMesh';

  const layers: MeshLayer[] = [
    { name: 'Roads', triangles: meshData.roadTriangles, color: '#1e293b' },
    { name: 'Junctions', triangles: meshData.hubTriangles, color: '#1e293b', yOffset: 0.05 },
    { name: 'Crosswalks', triangles: meshData.crosswalkTriangles, color: '#334155', yOffset: 0.1 },
    { name: 'Sidewalks', triangles: meshData.sidewalkTriangles, color: '#94a3b8', yOffset: 0.15 },
    { name: 'DashedLaneLines', triangles: meshData.dashedLineTriangles, color: '#ffffff' },
    { name: 'SolidLaneLines', triangles: meshData.solidLineTriangles, color: '#eab308' },
  ];

  layers.forEach((layer) => addLayer(group, layer));

  meshData.polygonTriangles.forEach((polygonGroup, index) => {
    addLayer(group, {
      name: `PolygonFill_${index + 1}`,
      triangles: polygonGroup.triangles,
      color: polygonGroup.color,
      yOffset: -1.5,
      opacity: 0.7,
    });
  });

  meshData.buildingMeshes.forEach((building, index) => {
    addLayer(group, {
      name: building.name || `Building_${index + 1}`,
      triangles: building.triangles,
      color: building.color,
    });
  });

  group.updateMatrixWorld(true);
  return group;
}

export function createRobloxRoadMeshExport(meshData: MeshData) {
  const group = new THREE.Group();
  group.name = 'Cab87RobloxRoadMesh';
  const chunks: any[] = [];

  const addChunk = (
    layer: RobloxChunkLayer,
    bucket: TriangleBucket,
    batch: Triangle[],
    batchIndex: number,
    kind: 'surface' | 'collision' | 'marking'
  ) => {
    const isCollision = kind === 'collision';
    const name = chunkName(isCollision ? (layer.collisionBaseName ?? `${layer.baseName}Collision`) : layer.baseName, bucket, batchIndex);
    const yOffset = layer.yOffset ?? 0;
    const isDriveSurface = isCollision && (layer.driveSurface ?? true);
    const geometry = isCollision
      ? createCollisionGeometry(batch, yOffset, ROBLOX_COLLISION_THICKNESS, 0)
      : createTriangleGeometry(batch, yOffset, 0);
    const actualTriangleCount = Math.floor((geometry.getAttribute('position')?.count ?? 0) / 3);
    const mesh = createMeshFromGeometry(name, geometry, isCollision ? '#38bdf8' : layer.color, isCollision ? 0.18 : 1);
    group.add(mesh);

    chunks.push({
      name,
      kind,
      layer: layer.layer,
      surfaceType: layer.surfaceType,
      material: layer.material,
      color: layer.color,
      transparency: isCollision ? 1 : 0,
      canCollide: isCollision,
      canQuery: isCollision,
      canTouch: false,
      castShadow: false,
      driveSurface: isDriveSurface,
      crashObstacle: isCollision && layer.crashObstacle === true,
      collisionFidelity: isCollision ? 'PreciseConvexDecomposition' : 'Box',
      triangleCount: actualTriangleCount,
      inputTriangleCount: batch.length,
      buildingId: layer.buildingId,
      chunkKey: bucket.chunkY === undefined
        ? `${bucket.chunkX}:${bucket.chunkZ}`
        : `${bucket.chunkX}:${bucket.chunkY}:${bucket.chunkZ}`,
      chunkX: bucket.chunkX,
      chunkY: bucket.chunkY,
      chunkZ: bucket.chunkZ,
      batchIndex: batchIndex + 1,
      bounds: computeBounds(geometry),
    });
  };

  getRobloxLayers(meshData).forEach((layer) => {
    if (layer.triangles.length === 0) return;

    const surfaceMaxTriangles = layer.kind === 'marking'
      ? ROBLOX_MAX_SURFACE_TRIANGLES
      : ROBLOX_MAX_SURFACE_TRIANGLES;
    bucketTrianglesByCenter(layer.triangles, ROBLOX_CHUNK_SIZE).forEach((bucket) => {
      triangleBatches(bucket.triangles, surfaceMaxTriangles).forEach((batch, batchIndex) => {
        addChunk(layer, bucket, batch, batchIndex, layer.kind ?? 'surface');
      });
    });

    if (layer.includeCollision) {
      bucketTrianglesByCenter(layer.triangles, ROBLOX_CHUNK_SIZE, {
        verticalChunkSize: ROBLOX_COLLISION_VERTICAL_CHUNK_SIZE,
        yOffset: layer.yOffset ?? 0,
        defaultY: 0,
      }).forEach((collisionBucket) => {
        triangleBatches(collisionBucket.triangles, ROBLOX_MAX_COLLISION_INPUT_TRIANGLES).forEach((batch, batchIndex) => {
          addChunk(layer, collisionBucket, batch, batchIndex, 'collision');
        });
      });
    }
  });

  group.updateMatrixWorld(true);

  const manifest = {
    schema: ROBLOX_MANIFEST_SCHEMA,
    version: ROBLOX_MANIFEST_VERSION,
    settings: {
      chunkSize: ROBLOX_CHUNK_SIZE,
      maxSurfaceTriangles: ROBLOX_MAX_SURFACE_TRIANGLES,
      maxCollisionInputTriangles: ROBLOX_MAX_COLLISION_INPUT_TRIANGLES,
      collisionThickness: ROBLOX_COLLISION_THICKNESS,
      collisionVerticalChunkSize: ROBLOX_COLLISION_VERTICAL_CHUNK_SIZE,
    },
    counts: {
      chunks: chunks.length,
      surfaceChunks: chunks.filter((chunk) => chunk.kind === 'surface').length,
      collisionChunks: chunks.filter((chunk) => chunk.kind === 'collision').length,
      markingChunks: chunks.filter((chunk) => chunk.kind === 'marking').length,
      triangles: chunks.reduce((sum, chunk) => sum + chunk.triangleCount, 0),
    },
    chunks,
  };

  return { group, manifest };
}

function downloadBlob(blob: Blob, filename: string) {
  const url = URL.createObjectURL(blob);
  const anchor = document.createElement('a');
  anchor.href = url;
  anchor.download = filename;
  document.body.appendChild(anchor);
  anchor.click();
  anchor.remove();
  window.setTimeout(() => URL.revokeObjectURL(url), 0);
}

function createCrc32Table() {
  const table = new Uint32Array(256);
  for (let index = 0; index < table.length; index++) {
    let value = index;
    for (let bit = 0; bit < 8; bit++) {
      value = value & 1 ? 0xedb88320 ^ (value >>> 1) : value >>> 1;
    }
    table[index] = value >>> 0;
  }
  return table;
}

const CRC32_TABLE = createCrc32Table();

function crc32(bytes: Uint8Array) {
  let crc = 0xffffffff;
  for (const byte of bytes) {
    crc = CRC32_TABLE[(crc ^ byte) & 0xff] ^ (crc >>> 8);
  }
  return (crc ^ 0xffffffff) >>> 0;
}

function toDosDateTime(date = new Date()) {
  const year = Math.max(date.getFullYear(), 1980);
  return {
    date: ((year - 1980) << 9) | ((date.getMonth() + 1) << 5) | date.getDate(),
    time: (date.getHours() << 11) | (date.getMinutes() << 5) | Math.floor(date.getSeconds() / 2),
  };
}

function writeUint16(view: DataView, offset: number, value: number) {
  view.setUint16(offset, value, true);
}

function writeUint32(view: DataView, offset: number, value: number) {
  view.setUint32(offset, value >>> 0, true);
}

function createZipBlob(files: { name: string; data: Uint8Array }[]) {
  const encoder = new TextEncoder();
  const dosDateTime = toDosDateTime();
  const entries = files.map((file) => ({
    ...file,
    nameBytes: encoder.encode(file.name),
    crc: crc32(file.data),
    localHeaderOffset: 0,
  }));

  let localSize = 0;
  for (const entry of entries) {
    entry.localHeaderOffset = localSize;
    localSize += 30 + entry.nameBytes.length + entry.data.length;
  }

  let centralDirectorySize = 0;
  for (const entry of entries) {
    centralDirectorySize += 46 + entry.nameBytes.length;
  }

  const endOfCentralDirectorySize = 22;
  const zipBytes = new Uint8Array(localSize + centralDirectorySize + endOfCentralDirectorySize);
  const view = new DataView(zipBytes.buffer);
  let offset = 0;

  for (const entry of entries) {
    writeUint32(view, offset, 0x04034b50);
    writeUint16(view, offset + 4, 20);
    writeUint16(view, offset + 6, 0);
    writeUint16(view, offset + 8, 0);
    writeUint16(view, offset + 10, dosDateTime.time);
    writeUint16(view, offset + 12, dosDateTime.date);
    writeUint32(view, offset + 14, entry.crc);
    writeUint32(view, offset + 18, entry.data.length);
    writeUint32(view, offset + 22, entry.data.length);
    writeUint16(view, offset + 26, entry.nameBytes.length);
    writeUint16(view, offset + 28, 0);
    offset += 30;
    zipBytes.set(entry.nameBytes, offset);
    offset += entry.nameBytes.length;
    zipBytes.set(entry.data, offset);
    offset += entry.data.length;
  }

  const centralDirectoryOffset = offset;
  for (const entry of entries) {
    writeUint32(view, offset, 0x02014b50);
    writeUint16(view, offset + 4, 20);
    writeUint16(view, offset + 6, 20);
    writeUint16(view, offset + 8, 0);
    writeUint16(view, offset + 10, 0);
    writeUint16(view, offset + 12, dosDateTime.time);
    writeUint16(view, offset + 14, dosDateTime.date);
    writeUint32(view, offset + 16, entry.crc);
    writeUint32(view, offset + 20, entry.data.length);
    writeUint32(view, offset + 24, entry.data.length);
    writeUint16(view, offset + 28, entry.nameBytes.length);
    writeUint16(view, offset + 30, 0);
    writeUint16(view, offset + 32, 0);
    writeUint16(view, offset + 34, 0);
    writeUint16(view, offset + 36, 0);
    writeUint32(view, offset + 38, 0);
    writeUint32(view, offset + 42, entry.localHeaderOffset);
    offset += 46;
    zipBytes.set(entry.nameBytes, offset);
    offset += entry.nameBytes.length;
  }

  writeUint32(view, offset, 0x06054b50);
  writeUint16(view, offset + 4, 0);
  writeUint16(view, offset + 6, 0);
  writeUint16(view, offset + 8, entries.length);
  writeUint16(view, offset + 10, entries.length);
  writeUint32(view, offset + 12, centralDirectorySize);
  writeUint32(view, offset + 16, centralDirectoryOffset);
  writeUint16(view, offset + 20, 0);

  return new Blob([zipBytes], { type: 'application/zip' });
}

function disposeObject(root: THREE.Object3D) {
  root.traverse((object) => {
    if (!(object instanceof THREE.Mesh)) return;
    object.geometry.dispose();

    const materials = Array.isArray(object.material) ? object.material : [object.material];
    materials.forEach((material) => material.dispose());
  });
}

export function exportRoadMeshObj(meshData: MeshData, filename = 'cab87-road-mesh.obj') {
  const group = createRoadMeshExportGroup(meshData);
  const output = new OBJExporter().parse(group);
  downloadBlob(new Blob([output], { type: 'text/plain;charset=utf-8' }), filename);
  disposeObject(group);
}

export async function exportRoadMeshGlb(meshData: MeshData, filename = 'cab87-road-mesh.glb') {
  const group = createRoadMeshExportGroup(meshData);
  const result = await new GLTFExporter().parseAsync(group, {
    binary: true,
    onlyVisible: true,
    trs: false,
    forceIndices: true,
  });

  if (!(result instanceof ArrayBuffer)) {
    throw new Error('GLB export did not produce binary output.');
  }

  downloadBlob(new Blob([result], { type: 'model/gltf-binary' }), filename);
  disposeObject(group);
}

async function createRobloxRoadMeshPayload(meshData: MeshData) {
  const { group, manifest } = createRobloxRoadMeshExport(meshData);
  try {
    const result = await new GLTFExporter().parseAsync(group, {
      binary: true,
      onlyVisible: true,
      trs: false,
      forceIndices: true,
    });

    if (!(result instanceof ArrayBuffer)) {
      throw new Error('Roblox GLB export did not produce binary output.');
    }

    return { glb: result, manifest };
  } finally {
    disposeObject(group);
  }
}

function manifestJson(manifest: unknown) {
  return JSON.stringify(manifest, null, 2);
}

export async function exportRoadMeshRobloxPackage(
  meshData: MeshData,
  mode: RobloxRoadMeshExportMode = 'zip',
  basename = ROBLOX_PACKAGE_BASENAME
) {
  if (mode === 'manifest') {
    const { group, manifest } = createRobloxRoadMeshExport(meshData);
    downloadBlob(
      new Blob([manifestJson(manifest)], { type: 'application/json' }),
      `${basename}.manifest.json`
    );
    disposeObject(group);
    return;
  }

  const { glb, manifest } = await createRobloxRoadMeshPayload(meshData);
  const manifestText = manifestJson(manifest);

  if (mode === 'zip') {
    downloadBlob(
      createZipBlob([
        { name: `${basename}.glb`, data: new Uint8Array(glb) },
        { name: `${basename}.manifest.json`, data: new TextEncoder().encode(manifestText) },
      ]),
      `${basename}.zip`
    );
    return;
  }

  downloadBlob(new Blob([glb], { type: 'model/gltf-binary' }), `${basename}.glb`);

  if (mode === 'files') {
    downloadBlob(
      new Blob([manifestText], { type: 'application/json' }),
      `${basename}.manifest.json`
    );
  }
}
