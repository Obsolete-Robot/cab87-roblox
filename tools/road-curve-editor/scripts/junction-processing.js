// Junction topology processing, chain splitting, and automatic junction discovery.

function cloneJunctionForPreview(junction) {
	const radius = sanitizeJunctionRadius(junction.radius);
	return {
		id: junction.id,
		name: junction.name,
		center: makePoint(junction.x, junction.z, junction.y ?? 0),
		radius,
		blendRadius: radius,
		subdivisions: sanitizeJunctionSubdivisions(junction.subdivisions),
		portals: [],
		chains: new Set(),
	};
}

function junctionContainingPoint(point, junctions) {
	let best = null;
	let bestDistance = Infinity;
	for (const junction of junctions) {
		const distance = distanceXZ(point, junction.center);
		if (distance <= junction.radius - 1e-3 && distance < bestDistance) {
			best = junction;
			bestDistance = distance;
		}
	}
	return best;
}

function junctionTouchingPoint(point, junctions) {
	let best = null;
	let bestDistance = Infinity;
	for (const junction of junctions) {
		const distance = distanceXZ(point, junction.center);
		if (distance <= junction.radius + JUNCTION_VERTEX_EPSILON && distance < bestDistance) {
			best = junction;
			bestDistance = distance;
		}
	}
	return best;
}

function intervalOutsideJunctions(a, b, junctions) {
	const midpoint = lerpPoint(a, b, 0.5);
	return !junctionContainingPoint(midpoint, junctions);
}

function addPortalForChain(junction, chain, boundaryPoint, outsidePoint) {
	if (!junction || !chain || !outsidePoint) {
		return;
	}

	const tangent = horizontalUnit(subtract2D(outsidePoint, boundaryPoint))
		|| horizontalUnit(subtract2D(boundaryPoint, junction.center))
		|| { x: 0, z: 1 };
	const right = roadRightFromTangent(tangent);
	const halfWidth = sanitizeRoadWidth(chain.width) * 0.5;
	const portal = {
		junction,
		chain,
		boundaryPoint: clonePoint(boundaryPoint),
		outsidePoint: clonePoint(outsidePoint),
		point: clonePoint(boundaryPoint),
		tangent,
		halfWidth,
		left: makePoint(boundaryPoint.x - (right.x * halfWidth), boundaryPoint.z - (right.z * halfWidth), boundaryPoint.y ?? 0),
		right: makePoint(boundaryPoint.x + (right.x * halfWidth), boundaryPoint.z + (right.z * halfWidth), boundaryPoint.y ?? 0),
	};
	junction.portals.push(portal);
	junction.chains.add(chain);
}

function closestSampleIndex(samples, point) {
	let bestIndex = null;
	let bestDistance = Infinity;
	for (let index = 0; index < (samples?.length ?? 0); index += 1) {
		const distance = distanceXZ(samples[index], point);
		if (distance < bestDistance) {
			bestIndex = index;
			bestDistance = distance;
		}
	}
	return bestIndex;
}

function rememberPortalKey(portalKeys, chain, boundaryIndex, outsideIndex) {
	let chainKeys = portalKeys.get(chain);
	if (!chainKeys) {
		chainKeys = new Set();
		portalKeys.set(chain, chainKeys);
	}

	const key = `${boundaryIndex}:${outsideIndex}`;
	if (chainKeys.has(key)) {
		return false;
	}
	chainKeys.add(key);
	return true;
}

function addMemberPortalForSample(portalKeys, junction, chain, boundaryIndex, outsideIndex) {
	const boundaryPoint = chain?.samples?.[boundaryIndex];
	const outsidePoint = chain?.samples?.[outsideIndex];
	if (!boundaryPoint || !outsidePoint || distanceXZ(boundaryPoint, outsidePoint) <= 0.05) {
		return;
	}
	if (!rememberPortalKey(portalKeys, chain, boundaryIndex, outsideIndex)) {
		return;
	}
	addPortalForChain(junction, chain, boundaryPoint, outsidePoint);
}

function addMemberPortalsAroundSample(portalKeys, junction, chain, sampleIndex) {
	const samples = chain?.samples;
	if (!samples || samples.length < 2 || !Number.isInteger(sampleIndex)) {
		return;
	}

	const lastIndex = samples.length - 1;
	if (chain.closed && samples.length > 2 && (sampleIndex === 0 || sampleIndex === lastIndex)) {
		addMemberPortalForSample(portalKeys, junction, chain, 0, 1);
		addMemberPortalForSample(portalKeys, junction, chain, 0, lastIndex - 1);
	} else if (sampleIndex <= 0) {
		addMemberPortalForSample(portalKeys, junction, chain, 0, 1);
	} else if (sampleIndex >= lastIndex) {
		addMemberPortalForSample(portalKeys, junction, chain, lastIndex, lastIndex - 1);
	} else {
		addMemberPortalForSample(portalKeys, junction, chain, sampleIndex, sampleIndex - 1);
		addMemberPortalForSample(portalKeys, junction, chain, sampleIndex, sampleIndex + 1);
	}
}

function attachMemberJunctionPortals(junctions) {
	for (const junction of junctions ?? []) {
		junction.portals = [];
		junction.chains = junction.chains ?? new Set();
		const portalKeys = new Map();
		for (const member of junction.members ?? []) {
			const chain = member.chain;
			if (!chain?.samples) {
				continue;
			}
			junction.chains.add(chain);
			let sampleIndex = Number.isInteger(member.index)
				? member.index
				: closestSampleIndex(chain.samples, junction.center);
			if (
				Number.isInteger(sampleIndex)
				&& (!chain.samples[sampleIndex] || distanceXZ(chain.samples[sampleIndex], junction.center) > 0.1)
			) {
				sampleIndex = closestSampleIndex(chain.samples, junction.center);
			}
			addMemberPortalsAroundSample(portalKeys, junction, chain, sampleIndex);
		}
	}
}


function emitRoadRun(processedChains, sourceChain, runVertices) {
	const samples = runVertices.map((vertex) => clonePoint(vertex.point));
	if (samples.length < 2 || polylineLength(samples, false) <= 0.05) {
		return;
	}

	const chain = {
		...sourceChain,
		samples,
		closed: false,
		sections: null,
	};
	processedChains.push(chain);

	const first = runVertices[0];
	const second = runVertices[1];
	const last = runVertices[runVertices.length - 1];
	const beforeLast = runVertices[runVertices.length - 2];
	if (first.junction) {
		addPortalForChain(first.junction, chain, first.point, second.point);
	}
	if (last.junction) {
		addPortalForChain(last.junction, chain, last.point, beforeLast.point);
	}
}

function collectExplicitJunctionHits(paths, junctions) {
	const hitsByPath = new Map(paths.map((path) => [path, []]));
	for (const junction of junctions) {
		junction.hits = [];
		junction.portals = [];
		junction.chains = new Set();
		for (const path of paths) {
			const hit = closestPathHit(path, junction.center);
			if (hit && hit.distance <= junction.radius + JUNCTION_VERTEX_EPSILON) {
				hit.junction = junction;
				junction.hits.push(hit);
				hitsByPath.get(path).push(hit);
				junction.chains.add(path.chain);
			}
		}
	}
	return hitsByPath;
}

function computeExplicitJunctionCenter(junction) {
	const hits = junction.hits ?? [];
	if (hits.length === 0) {
		return junction.center;
	}

	const candidates = [];
	for (let i = 0; i < hits.length; i += 1) {
		for (let j = i + 1; j < hits.length; j += 1) {
			const a = hits[i];
			const b = hits[j];
			const intersection = lineIntersectionXZ(a.point, a.lineDir, b.point, b.lineDir);
			if (!intersection) {
				continue;
			}
			candidates.push(intersection);
		}
	}

	const source = candidates.length > 0 ? candidates : hits.map((hit) => hit.point);
	const summed = source.reduce((accumulator, point) => ({
		x: accumulator.x + point.x,
		z: accumulator.z + point.z,
		y: accumulator.y + (point.y ?? 0),
	}), { x: 0, z: 0, y: 0 });
	return makePoint(summed.x / source.length, summed.z / source.length, summed.y / source.length);
}

function finalizeExplicitJunctionCenters(junctions) {
	for (const junction of junctions) {
		junction.intersectionCenter = computeExplicitJunctionCenter(junction);
		for (const hit of junction.hits ?? []) {
			const refined = closestPathHit(hit.path, junction.intersectionCenter);
			if (refined) {
				hit.segment = refined.segment;
				hit.t = refined.t;
				hit.point = refined.point;
				hit.distance = refined.distance;
				hit.pathDistance = refined.pathDistance;
				hit.lineDir = refined.lineDir;
			}
		}
	}
}

function getJunctionCutDistanceFallback(hit) {
	return sanitizeRoadWidth(hit?.chain?.width ?? ROAD_WIDTH_DEFAULT) * 0.5 + 30;
}

function assignExplicitJunctionCutDistances(junction) {
	const roads = [];
	for (let index = 0; index < (junction.hits ?? []).length; index += 1) {
		const hit = junction.hits[index];
		const lineDir = horizontalUnit(hit.lineDir || { x: 0, z: 1 }) || { x: 0, z: 1 };
		hit.beforeRoadId = `${index}:before`;
		hit.afterRoadId = `${index}:after`;
		hit.hasBeforeRoad = Boolean(hit.path && (hit.path.closed || hit.pathDistance > 0.05));
		hit.hasAfterRoad = Boolean(hit.path && (hit.path.closed || hit.pathDistance < hit.path.totalLength - 0.05));

		if (hit.hasBeforeRoad) {
			roads.push({
				id: hit.beforeRoadId,
				direction: scale2D(lineDir, -1),
				width: hit.chain?.width ?? ROAD_WIDTH_DEFAULT,
			});
		}
		if (hit.hasAfterRoad) {
			roads.push({
				id: hit.afterRoadId,
				direction: lineDir,
				width: hit.chain?.width ?? ROAD_WIDTH_DEFAULT,
			});
		}
	}

	const geometry = calculateIntersectionGeometry(junction.intersectionCenter ?? junction.center, roads);
	junction.cutGeometry = geometry;
	for (const hit of junction.hits ?? []) {
		const fallback = getJunctionCutDistanceFallback(hit);
		hit.beforeCutDistance = hit.hasBeforeRoad ? (geometry.roadCutDistances.get(hit.beforeRoadId) ?? fallback) : 0;
		hit.afterCutDistance = hit.hasAfterRoad ? (geometry.roadCutDistances.get(hit.afterRoadId) ?? fallback) : 0;
	}
}

function splitChainByExplicitJunctions(chain, junctions, processedChains) {
	const closedLoop = chain.closed || sampleLoopIsClosed(chain.samples);
	const baseSamples = getUniqueRoadSamples(chain.samples, closedLoop);
	if (baseSamples.length < (closedLoop ? 3 : 2) || junctions.length === 0) {
		processedChains.push({ ...chain, samples: samplesWithClosedSeam(baseSamples, closedLoop), closed: closedLoop });
		return;
	}

	const vertices = [];
	const appendVertex = (vertex) => {
		const previous = vertices[vertices.length - 1];
		if (
			previous
			&& distanceXZ(previous.point, vertex.point) <= 0.01
			&& previous.junction === vertex.junction
		) {
			return;
		}
		vertices.push(vertex);
	};

	const segmentCount = closedLoop ? baseSamples.length : baseSamples.length - 1;
	appendVertex({ point: baseSamples[0], junction: junctionTouchingPoint(baseSamples[0], junctions) });
	for (let index = 0; index < segmentCount; index += 1) {
		const nextIndex = (index + 1) % baseSamples.length;
		const a = baseSamples[index];
		const b = baseSamples[nextIndex];
		const cuts = [];
		for (const junction of junctions) {
			for (const t of segmentCircleIntersections(a, b, junction.center, junction.radius)) {
				cuts.push({
					t,
					point: interpolateSegmentPoint(a, b, t),
					junction,
				});
			}
		}
		cuts.sort((left, right) => left.t - right.t);
		for (const cut of cuts) {
			const duplicate = vertices.some((vertex) => distanceXZ(vertex.point, cut.point) <= 0.01 && vertex.junction === cut.junction);
			if (!duplicate) {
				appendVertex({ point: cut.point, junction: cut.junction });
			}
		}
		if (!closedLoop || nextIndex !== 0) {
			appendVertex({ point: b, junction: junctionTouchingPoint(b, junctions) });
		}
	}

	if (vertices.length < 2) {
		return;
	}

	if (!closedLoop) {
		let run = [];
		for (let index = 0; index < vertices.length - 1; index += 1) {
			const outside = intervalOutsideJunctions(vertices[index].point, vertices[index + 1].point, junctions);
			if (outside) {
				if (run.length === 0) {
					run.push(vertices[index]);
				}
				run.push(vertices[index + 1]);
			} else if (run.length > 0) {
				emitRoadRun(processedChains, chain, run);
				run = [];
			}
		}
		if (run.length > 0) {
			emitRoadRun(processedChains, chain, run);
		}
		return;
	}

	const intervalCount = vertices.length;
	const outsideIntervals = [];
	for (let index = 0; index < intervalCount; index += 1) {
		const nextIndex = (index + 1) % intervalCount;
		outsideIntervals[index] = intervalOutsideJunctions(vertices[index].point, vertices[nextIndex].point, junctions);
	}

	if (outsideIntervals.every(Boolean)) {
		processedChains.push({ ...chain, samples: samplesWithClosedSeam(baseSamples, true), closed: true });
		return;
	}

	for (let start = 0; start < intervalCount; start += 1) {
		const previous = (start - 1 + intervalCount) % intervalCount;
		if (!outsideIntervals[start] || outsideIntervals[previous]) {
			continue;
		}

		const run = [vertices[start]];
		let index = start;
		while (outsideIntervals[index]) {
			const nextIndex = (index + 1) % intervalCount;
			run.push(vertices[nextIndex]);
			index = nextIndex;
			if (index === start) {
				break;
			}
		}
		emitRoadRun(processedChains, chain, run);
	}
}

function emitExplicitRoadRun(processedChains, sourceChain, samples, startPortal, endPortal) {
	if (samples.length < 2 || polylineLength(samples, false) <= 0.05) {
		return;
	}

	const chain = {
		...sourceChain,
		samples: samples.map(clonePoint),
		closed: false,
		sections: null,
	};
	processedChains.push(chain);

	if (startPortal) {
		addPortalForChain(startPortal.junction, chain, startPortal.point, chain.samples[1] ?? chain.samples[0]);
	}
	if (endPortal) {
		addPortalForChain(endPortal.junction, chain, endPortal.point, chain.samples[chain.samples.length - 2] ?? chain.samples[chain.samples.length - 1]);
	}
}

function portalRecordForHit(hit, distance) {
	return {
		junction: hit.junction,
		point: hit.point,
		distance,
	};
}

function splitOpenPathByExplicitHits(processedChains, path, hits) {
	hits.sort((a, b) => a.pathDistance - b.pathDistance);
	let cursor = 0;
	let startPortal = null;
	for (const hit of hits) {
		const beforeDistance = Math.max(0, hit.pathDistance - Math.max(hit.beforeCutDistance ?? 0, 0));
		const afterDistance = Math.min(path.totalLength, hit.pathDistance + Math.max(hit.afterCutDistance ?? 0, 0));
		if (beforeDistance > cursor + 0.05) {
			emitExplicitRoadRun(
				processedChains,
				path.chain,
				collectPathSamples(path, cursor, beforeDistance),
				startPortal,
				portalRecordForHit(hit, beforeDistance),
			);
		}
		cursor = Math.max(cursor, afterDistance);
		startPortal = cursor < path.totalLength - 0.05 ? portalRecordForHit(hit, cursor) : null;
	}

	if (cursor < path.totalLength - 0.05) {
		emitExplicitRoadRun(processedChains, path.chain, collectPathSamples(path, cursor, path.totalLength), startPortal, null);
	}
}

function splitClosedPathByExplicitHits(processedChains, path, hits) {
	hits.sort((a, b) => a.pathDistance - b.pathDistance);
	if (hits.length === 0) {
		processedChains.push({ ...path.chain, samples: samplesWithClosedSeam(path.samples, true), closed: true });
		return;
	}

	for (let index = 0; index < hits.length; index += 1) {
		const hit = hits[index];
		const nextHit = hits[(index + 1) % hits.length];
		const hitCutDistance = Math.max(hit.afterCutDistance ?? 0, 0);
		const nextCutDistance = Math.max(nextHit.beforeCutDistance ?? 0, 0);
		const startDistance = (hit.pathDistance + hitCutDistance) % path.totalLength;
		const endDistance = (nextHit.pathDistance - nextCutDistance + path.totalLength) % path.totalLength;
		let effectiveEnd = endDistance;
		if (effectiveEnd <= startDistance) {
			effectiveEnd += path.totalLength;
		}
		if (effectiveEnd > startDistance + 0.05) {
			emitExplicitRoadRun(
				processedChains,
				path.chain,
				collectPathSamples(path, startDistance, effectiveEnd),
				portalRecordForHit(hit, startDistance),
				portalRecordForHit(nextHit, effectiveEnd),
			);
		}
	}
}

function splitPathByExplicitJunctions(processedChains, path, hits) {
	if (!hits || hits.length === 0) {
		processedChains.push({ ...path.chain, samples: samplesWithClosedSeam(path.samples, path.closed), closed: path.closed });
		return;
	}

	if (path.closed) {
		splitClosedPathByExplicitHits(processedChains, path, hits);
	} else {
		splitOpenPathByExplicitHits(processedChains, path, hits);
	}
}

function applyExplicitJunctionsToChains(chains, junctions) {
	const processedChains = [];
	const paths = chains.map(buildChainPath).filter(Boolean);
	const hitsByPath = collectExplicitJunctionHits(paths, junctions);
	finalizeExplicitJunctionCenters(junctions);
	for (const junction of junctions) {
		assignExplicitJunctionCutDistances(junction);
	}
	for (const path of paths) {
		splitPathByExplicitJunctions(processedChains, path, hitsByPath.get(path));
	}
	finalizeJunctionPortals(junctions);
	return processedChains;
}

function maxRoadWidthForMembers(members) {
	let width = null;
	for (const member of members) {
		if (member.chain) {
			width = Math.max(width ?? 0, sanitizeRoadWidth(member.chain.width));
		}
	}
	return width ?? ROAD_WIDTH_DEFAULT;
}

function collectEndpointJunctions(chains) {
	const endpoints = [];
	for (const chain of chains) {
		if (!chain.closed && chain.samples.length >= 2) {
			endpoints.push({ chain, index: 0, pos: chain.samples[0] });
			endpoints.push({ chain, index: chain.samples.length - 1, pos: chain.samples[chain.samples.length - 1] });
		}
	}

	const clusters = [];
	for (const endpoint of endpoints) {
		let placed = false;
		const endpointWidth = sanitizeRoadWidth(endpoint.chain.width);
		for (const cluster of clusters) {
			const weldDistance = Math.max(ENDPOINT_WELD_DISTANCE, Math.max(cluster.width, endpointWidth) * 0.8);
			if (distanceXZ(cluster.center, endpoint.pos) <= weldDistance) {
				cluster.members.push(endpoint);
				cluster.width = Math.max(cluster.width, endpointWidth);
				const summed = cluster.members.reduce((accumulator, member) => ({
					x: accumulator.x + member.pos.x,
					z: accumulator.z + member.pos.z,
				}), { x: 0, z: 0 });
				cluster.center = makePoint(summed.x / cluster.members.length, summed.z / cluster.members.length);
				placed = true;
				break;
			}
		}
		if (!placed) {
			clusters.push({ center: clonePoint(endpoint.pos), members: [endpoint], width: endpointWidth });
		}
	}

	return clusters
		.filter((cluster) => cluster.members.length >= 2)
		.map((cluster) => ({
			center: cluster.center,
			members: cluster.members,
		}));
}

function segmentIntersection2D(a, b, c, d) {
	const cross2 = (u, v) => (u.x * v.z) - (u.z * v.x);
	const p = { x: a.x, z: a.z };
	const r = { x: b.x - a.x, z: b.z - a.z };
	const q = { x: c.x, z: c.z };
	const s = { x: d.x - c.x, z: d.z - c.z };
	const denom = cross2(r, s);
	if (Math.abs(denom) < 1e-6) {
		return null;
	}

	const qp = { x: q.x - p.x, z: q.z - p.z };
	let t = cross2(qp, s) / denom;
	let u = cross2(qp, r) / denom;
	const endpointEpsilon = 1e-4;
	if (t < -endpointEpsilon || t > (1 + endpointEpsilon) || u < -endpointEpsilon || u > (1 + endpointEpsilon)) {
		return null;
	}
	t = Math.min(1, Math.max(0, t));
	u = Math.min(1, Math.max(0, u));
	return {
		position: makePoint(p.x + (r.x * t), p.z + (r.z * t)),
		t,
		u,
	};
}

function collectCrossIntersections(chains) {
	const junctions = [];
	for (let chainIndex = 0; chainIndex < chains.length; chainIndex += 1) {
		const aChain = chains[chainIndex];
		for (let otherIndex = chainIndex + 1; otherIndex < chains.length; otherIndex += 1) {
			const bChain = chains[otherIndex];
			for (let aSegment = 0; aSegment < aChain.samples.length - 1; aSegment += 1) {
				const a1 = aChain.samples[aSegment];
				const a2 = aChain.samples[aSegment + 1];
				for (let bSegment = 0; bSegment < bChain.samples.length - 1; bSegment += 1) {
					const b1 = bChain.samples[bSegment];
					const b2 = bChain.samples[bSegment + 1];
					const hit = segmentIntersection2D(a1, a2, b1, b2);
					if (hit) {
						junctions.push({
							center: hit.position,
							members: [
								{ chain: aChain, segment: aSegment, t: hit.t, pos: hit.position },
								{ chain: bChain, segment: bSegment, t: hit.u, pos: hit.position },
							],
						});
					}
				}
			}
		}
	}
	return junctions;
}

function mergeJunctions(rawJunctions) {
	const clusters = [];
	for (const junction of rawJunctions) {
		let placed = false;
		const junctionWidth = maxRoadWidthForMembers(junction.members);
		for (const cluster of clusters) {
			const mergeDistance = Math.max(cluster.width, junctionWidth) * INTERSECTION_MERGE_SCALE;
			if (distanceXZ(cluster.center, junction.center) <= mergeDistance) {
				cluster.members.push(...junction.members);
				cluster.width = Math.max(cluster.width, junctionWidth);
				const summed = cluster.members.reduce((accumulator, member) => ({
					x: accumulator.x + (member.pos?.x ?? junction.center.x),
					z: accumulator.z + (member.pos?.z ?? junction.center.z),
				}), { x: 0, z: 0 });
				cluster.center = makePoint(summed.x / cluster.members.length, summed.z / cluster.members.length);
				placed = true;
				break;
			}
		}
		if (!placed) {
			clusters.push({
				center: clonePoint(junction.center),
				members: [...junction.members],
				width: junctionWidth,
			});
		}
	}

	return clusters.map((cluster) => ({
		center: cluster.center,
		members: cluster.members,
		chains: new Set(cluster.members.map((member) => member.chain).filter(Boolean)),
		width: cluster.width,
		radius: Math.max(cluster.width * INTERSECTION_RADIUS_SCALE, (ENDPOINT_WELD_DISTANCE * 0.5) + 1),
		blendRadius: Math.max(
			cluster.width * INTERSECTION_BLEND_SCALE,
			Math.max(cluster.width * INTERSECTION_RADIUS_SCALE, (ENDPOINT_WELD_DISTANCE * 0.5) + 1) + 0.05,
		),
	}));
}

function addInsertForChain(insertsByChain, chain, segment, t, pos) {
	const inserts = insertsByChain.get(chain) || [];
	inserts.push({ segment, t, pos });
	insertsByChain.set(chain, inserts);
}

function applyJunctionsToChains(chains, junctions) {
	const insertsByChain = new Map();

	for (const junction of junctions) {
		for (const member of junction.members) {
			if (Number.isInteger(member.index)) {
				member.chain.samples[member.index] = clonePoint(junction.center);
			} else if (Number.isInteger(member.segment) && Number.isFinite(member.t)) {
				addInsertForChain(insertsByChain, member.chain, member.segment, member.t, clonePoint(junction.center));
			}
		}
	}

	for (const [chain, inserts] of insertsByChain.entries()) {
		inserts.sort((a, b) => {
			if (a.segment === b.segment) {
				return b.t - a.t;
			}
			return b.segment - a.segment;
		});

		for (const insert of inserts) {
			const before = chain.samples[insert.segment];
			const after = chain.samples[insert.segment + 1];
			if (before && after && distanceXZ(before, insert.pos) > 0.05 && distanceXZ(after, insert.pos) > 0.05) {
				chain.samples.splice(insert.segment + 1, 0, clonePoint(insert.pos));
			}
		}
	}

	for (const chain of chains) {
		for (let index = 0; index < chain.samples.length; index += 1) {
			const sample = chain.samples[index];
			let bestJunction = null;
			let bestDistance = Infinity;
			for (const junction of junctions) {
				if (!junction.chains.has(chain)) {
					continue;
				}
				const distance = distanceXZ(sample, junction.center);
				const blendRadius = junction.blendRadius ?? (junction.radius + 0.05);
				if (distance <= blendRadius && distance < bestDistance) {
					bestDistance = distance;
					bestJunction = junction;
				}
			}

			if (bestJunction) {
				let alpha;
				if (bestDistance <= bestJunction.radius) {
					alpha = 1;
				} else {
					const blendRadius = bestJunction.blendRadius ?? (bestJunction.radius + 0.05);
					alpha = 1 - ((bestDistance - bestJunction.radius) / Math.max(blendRadius - bestJunction.radius, 0.001));
				}
				chain.samples[index] = makePoint(
					sample.x,
					sample.z,
					(sample.y ?? 0) + (((bestJunction.center.y ?? 0) - (sample.y ?? 0)) * alpha),
				);
			}
		}
	}
}

function collectAutomaticJunctions(chains) {
	const rawJunctions = collectEndpointJunctions(chains);
	rawJunctions.push(...collectCrossIntersections(chains));
	return mergeJunctions(rawJunctions).map((junction, index) => ({
		...junction,
		id: `auto-junction-${index}`,
		name: `AutoJunction${String(index + 1).padStart(4, "0")}`,
		automatic: true,
		portals: [],
	}));
}

function authoredJunctionSuppressionRadius(junction) {
	const center = junction.intersectionCenter ?? junction.center;
	let radius = junction.radius ?? 0;
	for (const portal of junction.portals ?? []) {
		const point = portal.boundaryPoint ?? portal.point ?? center;
		radius = Math.max(radius, distanceXZ(point, center) + (portal.halfWidth ?? 0));
	}
	return radius;
}

function mergeAuthoredAndAutomaticJunctions(authoredJunctions, automaticJunctions) {
	const junctions = [...authoredJunctions];
	for (const automatic of automaticJunctions) {
		const duplicate = authoredJunctions.some((authored) => {
			const duplicateDistance = Math.max(
				(automatic.width ?? ROAD_WIDTH_DEFAULT) * 0.5,
				automatic.radius ?? 0,
				authoredJunctionSuppressionRadius(authored),
			);
			return distanceXZ(automatic.center, authored.center) <= duplicateDistance;
		});
		if (!duplicate) {
			junctions.push(automatic);
		}
	}
	return junctions;
}
