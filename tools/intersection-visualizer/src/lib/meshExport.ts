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

export function createTriangleGeometry(triangles: Point[][]): THREE.BufferGeometry {
  const positions: number[] = [];
  const uvs: number[] = [];

  triangles.forEach((tri) => {
    if (tri.length !== 3) return;

    tri.forEach((point) => {
      positions.push(point.x, point.z ?? 4, point.y);
      uvs.push(point.u ?? 0, point.v ?? 0);
    });
  });

  const geometry = new THREE.BufferGeometry();
  geometry.setAttribute('position', new THREE.Float32BufferAttribute(positions, 3));

  if (uvs.length > 0) {
    geometry.setAttribute('uv', new THREE.Float32BufferAttribute(uvs, 2));
  }

  geometry.computeVertexNormals();
  geometry.computeBoundingBox();
  geometry.computeBoundingSphere();
  return geometry;
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

  group.updateMatrixWorld(true);
  return group;
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
