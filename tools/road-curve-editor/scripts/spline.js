// Spline sampling, path helpers, and shared curve utilities.

function createVector(point) {
	return { x: point.x, y: point.y ?? 0, z: point.z };
}

function catmullRom(p0, p1, p2, p3, t) {
	const t2 = t * t;
	const t3 = t2 * t;
	return {
		x: 0.5 * ((2 * p1.x) + (-p0.x + p2.x) * t + (2 * p0.x - 5 * p1.x + 4 * p2.x - p3.x) * t2 + (-p0.x + 3 * p1.x - 3 * p2.x + p3.x) * t3),
		y: 0.5 * ((2 * p1.y) + (-p0.y + p2.y) * t + (2 * p0.y - 5 * p1.y + 4 * p2.y - p3.y) * t2 + (-p0.y + 3 * p1.y - 3 * p2.y + p3.y) * t3),
		z: 0.5 * ((2 * p1.z) + (-p0.z + p2.z) * t + (2 * p0.z - 5 * p1.z + 4 * p2.z - p3.z) * t2 + (-p0.z + 3 * p1.z - 3 * p2.z + p3.z) * t3),
	};
}

function magnitude(a, b) {
	const dx = b.x - a.x;
	const dy = b.y - a.y;
	const dz = b.z - a.z;
	return Math.sqrt((dx * dx) + (dy * dy) + (dz * dz));
}

function samplePositions(positions, closedCurve, sampleStep = SAMPLE_STEP_STUDS) {
	if (positions.length < 2) {
		return positions.slice();
	}

	let closed = closedCurve;
	if (closed && positions.length < 3) {
		closed = false;
	}

	const samples = [];
	const step = Math.max(Number(sampleStep) || SAMPLE_STEP_STUDS, 1);

	if (closed) {
		const count = positions.length;
		for (let i = 0; i < count; i += 1) {
			const p0 = positions[(i - 1 + count) % count];
			const p1 = positions[i];
			const p2 = positions[(i + 1) % count];
			const p3 = positions[(i + 2) % count];
			const segmentLength = magnitude(p1, p2);
			const subdivisions = Math.max(2, Math.floor(segmentLength / step));
			for (let s = 0; s < subdivisions; s += 1) {
				samples.push(catmullRom(p0, p1, p2, p3, s / subdivisions));
			}
		}
		if (samples.length > 1) {
			samples.push({ ...samples[0] });
		}
	} else {
		for (let i = 0; i < positions.length - 1; i += 1) {
			const p0 = positions[Math.max(0, i - 1)];
			const p1 = positions[i];
			const p2 = positions[i + 1];
			const p3 = positions[Math.min(positions.length - 1, i + 2)];
			const segmentLength = magnitude(p1, p2);
			const subdivisions = Math.max(2, Math.floor(segmentLength / step));
			for (let s = 0; s < subdivisions; s += 1) {
				samples.push(catmullRom(p0, p1, p2, p3, s / subdivisions));
			}
		}
		samples.push({ ...positions[positions.length - 1] });
	}

	return samples;
}

function clonePoint(point) {
	return { x: point.x, y: point.y ?? 0, z: point.z };
}

function makePoint(x, z, y = 0) {
	return { x, y, z };
}

function lerpPoint(a, b, alpha) {
	return makePoint(
		a.x + ((b.x - a.x) * alpha),
		a.z + ((b.z - a.z) * alpha),
		(a.y ?? 0) + ((((b.y ?? 0) - (a.y ?? 0)) * alpha)),
	);
}

function distanceXZ(a, b) {
	return Math.hypot(a.x - b.x, a.z - b.z);
}

function horizontalUnit(vector) {
	const length = Math.hypot(vector.x, vector.z);
	if (length < 1e-4) {
		return null;
	}
	return { x: vector.x / length, z: vector.z / length };
}

function roadRightFromTangent(tangent) {
	const length = Math.hypot(tangent.x, tangent.z);
	if (length < 1e-4) {
		return { x: 1, z: 0 };
	}
	return { x: tangent.z / length, z: -tangent.x / length };
}

function add2D(a, b) {
	return { x: a.x + b.x, z: a.z + b.z };
}

function subtract2D(a, b) {
	return { x: a.x - b.x, z: a.z - b.z };
}

function scale2D(vector, scalar) {
	return { x: vector.x * scalar, z: vector.z * scalar };
}

function dot2D(a, b) {
	return (a.x * b.x) + (a.z * b.z);
}

function cross2D(a, b) {
	return (a.x * b.z) - (a.z * b.x);
}

function lineIntersectionXZ(a, dirA, b, dirB) {
	const denom = cross2D(dirA, dirB);
	if (Math.abs(denom) < 1e-5) {
		return null;
	}

	const dx = b.x - a.x;
	const dz = b.z - a.z;
	const t = ((dx * dirB.z) - (dz * dirB.x)) / denom;
	return makePoint(a.x + (dirA.x * t), a.z + (dirA.z * t), a.y ?? 0);
}

function circleCenterXZ(a, b, c) {
	const ax = a.x;
	const az = a.z;
	const bx = b.x;
	const bz = b.z;
	const cx = c.x;
	const cz = c.z;
	const denom = 2 * ((ax * (bz - cz)) + (bx * (cz - az)) + (cx * (az - bz)));
	if (Math.abs(denom) < 1e-4) {
		return null;
	}

	const a2 = (ax * ax) + (az * az);
	const b2 = (bx * bx) + (bz * bz);
	const c2 = (cx * cx) + (cz * cz);
	const ux = ((a2 * (bz - cz)) + (b2 * (cz - az)) + (c2 * (az - bz))) / denom;
	const uz = ((a2 * (cx - bx)) + (b2 * (ax - cx)) + (c2 * (bx - ax))) / denom;
	return makePoint(ux, uz, b.y ?? 0);
}

function sampleLoopIsClosed(samples) {
	if (samples.length < 3) {
		return false;
	}
	const first = samples[0];
	const last = samples[samples.length - 1];
	return distanceXZ(first, last) <= 0.05 && Math.abs((first.y ?? 0) - (last.y ?? 0)) <= 0.05;
}

function polylineLength(points, closedLoop) {
	const count = points.length;
	if (count < 2) {
		return 0;
	}

	const segmentCount = closedLoop ? count : count - 1;
	let total = 0;
	for (let index = 0; index < segmentCount; index += 1) {
		const nextIndex = closedLoop ? ((index + 1) % count) : (index + 1);
		total += magnitude(points[index], points[nextIndex]);
	}
	return total;
}

function samplePolylineAtFraction(points, closedLoop, fraction) {
	const count = points.length;
	if (count === 0) {
		return makePoint(0, 0);
	}
	if (count === 1) {
		return clonePoint(points[0]);
	}

	const totalLength = polylineLength(points, closedLoop);
	if (totalLength <= 1e-4) {
		return clonePoint(points[0]);
	}

	let target = Math.min(1, Math.max(0, fraction)) * totalLength;
	if (closedLoop) {
		target %= totalLength;
	} else if (target <= 0) {
		return clonePoint(points[0]);
	} else if (target >= totalLength) {
		return clonePoint(points[count - 1]);
	}

	let traveled = 0;
	const segmentCount = closedLoop ? count : count - 1;
	for (let index = 0; index < segmentCount; index += 1) {
		const nextIndex = closedLoop ? ((index + 1) % count) : (index + 1);
		const a = points[index];
		const b = points[nextIndex];
		const segmentLength = magnitude(a, b);
		if (segmentLength > 1e-4) {
			if ((traveled + segmentLength) >= target) {
				return lerpPoint(a, b, (target - traveled) / segmentLength);
			}
			traveled += segmentLength;
		}
	}

	return clonePoint(closedLoop ? points[0] : points[count - 1]);
}

function sampleSmoothedCurveControls(points, closedLoop, sampleStep) {
	const count = points.length;
	if (count < 3) {
		return points.map(clonePoint);
	}

	const smoothed = [];
	const appendPoint = (point) => {
		const last = smoothed[smoothed.length - 1];
		if (!last || magnitude(point, last) > 1e-4) {
			smoothed.push(clonePoint(point));
		}
	};

	const segmentCount = closedLoop ? count : count - 1;
	for (let index = 0; index < segmentCount; index += 1) {
		const p0 = closedLoop
			? points[(index - 1 + count) % count]
			: points[Math.max(0, index - 1)];
		const p1 = points[index];
		const p2 = points[(index + 1) % count] || points[index + 1];
		const p3 = closedLoop
			? points[(index + 2) % count]
			: points[Math.min(count - 1, index + 2)];
		const segmentLength = magnitude(p1, p2);
		const subdivisions = Math.max(2, Math.ceil(segmentLength / sampleStep));
		for (let step = 0; step < subdivisions; step += 1) {
			appendPoint(catmullRom(p0, p1, p2, p3, step / subdivisions));
		}
	}

	if (!closedLoop) {
		appendPoint(points[count - 1]);
	}

	return smoothed.length >= count ? smoothed : points.map(clonePoint);
}

function resamplePolylineControls(points, closedLoop, targetCount) {
	const roundedTarget = Math.floor(targetCount);
	if (roundedTarget <= 0 || points.length === 0) {
		return [];
	}
	if (points.length === 1) {
		return [clonePoint(points[0])];
	}

	const count = Math.max(closedLoop ? 3 : 2, roundedTarget);
	const resampled = [];
	for (let index = 0; index < count; index += 1) {
		const fraction = closedLoop
			? (index / count)
			: (count > 1 ? (index / (count - 1)) : 0);
		resampled[index] = samplePolylineAtFraction(points, closedLoop, fraction);
	}
	return resampled;
}

function fairEdgeCurveControls(points, closedLoop, sampleStep) {
	const length = polylineLength(points, closedLoop);
	let targetCount;
	if (length > 1e-4) {
		targetCount = closedLoop ? Math.ceil(length / sampleStep) : (Math.ceil(length / sampleStep) + 1);
		targetCount = Math.max(points.length, targetCount);
	} else {
		targetCount = points.length;
	}

	let relaxed = resamplePolylineControls(points, closedLoop, targetCount);
	for (let pass = 0; pass < ROAD_EDGE_CURVE_FAIR_PASSES; pass += 1) {
		const count = relaxed.length;
		if (count < 3) {
			return relaxed;
		}

		const nextPoints = [];
		for (let index = 0; index < count; index += 1) {
			if (closedLoop || (index > 0 && index < count - 1)) {
				const prevIndex = index > 0 ? index - 1 : count - 1;
				const nextIndex = index < count - 1 ? index + 1 : 0;
				const average = makePoint(
					(relaxed[prevIndex].x + relaxed[nextIndex].x) * 0.5,
					(relaxed[prevIndex].z + relaxed[nextIndex].z) * 0.5,
					((relaxed[prevIndex].y ?? 0) + (relaxed[nextIndex].y ?? 0)) * 0.5,
				);
				nextPoints[index] = lerpPoint(relaxed[index], average, ROAD_EDGE_CURVE_FAIR_ALPHA);
			} else {
				nextPoints[index] = clonePoint(relaxed[index]);
			}
		}
		relaxed = resamplePolylineControls(nextPoints, closedLoop, targetCount);
	}

	return sampleSmoothedCurveControls(relaxed, closedLoop, sampleStep);
}


function segmentCircleIntersections(a, b, center, radius) {
	const dx = b.x - a.x;
	const dz = b.z - a.z;
	const fx = a.x - center.x;
	const fz = a.z - center.z;
	const aa = (dx * dx) + (dz * dz);
	if (aa <= 1e-6) {
		return [];
	}

	const bb = 2 * ((fx * dx) + (fz * dz));
	const cc = (fx * fx) + (fz * fz) - (radius * radius);
	const discriminant = (bb * bb) - (4 * aa * cc);
	if (discriminant < -1e-6) {
		return [];
	}

	const root = Math.sqrt(Math.max(0, discriminant));
	return [(-bb - root) / (2 * aa), (-bb + root) / (2 * aa)]
		.filter((t) => t > 1e-4 && t < 1 - 1e-4);
}

function interpolateSegmentPoint(a, b, t) {
	return makePoint(
		a.x + ((b.x - a.x) * t),
		a.z + ((b.z - a.z) * t),
		(a.y ?? 0) + ((((b.y ?? 0) - (a.y ?? 0)) * t)),
	);
}

function samplesWithClosedSeam(samples, closedLoop) {
	const result = samples.map(clonePoint);
	if (closedLoop && result.length > 1 && distanceXZ(result[0], result[result.length - 1]) > 0.05) {
		result.push(clonePoint(result[0]));
	}
	return result;
}

function closestPointOnSegmentXZ(a, b, point) {
	const dx = b.x - a.x;
	const dz = b.z - a.z;
	const lengthSq = (dx * dx) + (dz * dz);
	if (lengthSq <= 1e-6) {
		return { t: 0, point: clonePoint(a), distance: distanceXZ(a, point) };
	}

	const rawT = (((point.x - a.x) * dx) + ((point.z - a.z) * dz)) / lengthSq;
	const t = Math.min(1, Math.max(0, rawT));
	const projected = interpolateSegmentPoint(a, b, t);
	return { t, point: projected, distance: distanceXZ(projected, point) };
}

function buildChainPath(chain) {
	const closed = chain.closed || sampleLoopIsClosed(chain.samples);
	const samples = getUniqueRoadSamples(chain.samples, closed);
	if (samples.length < (closed ? 3 : 2)) {
		return null;
	}

	const distances = [0];
	let totalLength = 0;
	for (let index = 0; index < samples.length - 1; index += 1) {
		totalLength += distanceXZ(samples[index], samples[index + 1]);
		distances[index + 1] = totalLength;
	}
	if (closed) {
		totalLength += distanceXZ(samples[samples.length - 1], samples[0]);
	}
	if (totalLength <= 1e-4) {
		return null;
	}

	return { chain, samples, closed, distances, totalLength };
}

function pathSegmentInfo(path, segmentIndex) {
	const nextIndex = (segmentIndex + 1) % path.samples.length;
	const startDistance = path.distances[segmentIndex];
	const endDistance = path.closed && segmentIndex === path.samples.length - 1
		? path.totalLength
		: path.distances[nextIndex];
	return {
		a: path.samples[segmentIndex],
		b: path.samples[nextIndex],
		startDistance,
		endDistance,
	};
}

function pathPointAtDistance(path, distance) {
	let d = path.closed
		? ((distance % path.totalLength) + path.totalLength) % path.totalLength
		: Math.min(path.totalLength, Math.max(0, distance));
	const segmentCount = path.closed ? path.samples.length : path.samples.length - 1;
	for (let index = 0; index < segmentCount; index += 1) {
		const segment = pathSegmentInfo(path, index);
		if (d <= segment.endDistance || index === segmentCount - 1) {
			const segmentLength = Math.max(segment.endDistance - segment.startDistance, 1e-6);
			return interpolateSegmentPoint(segment.a, segment.b, (d - segment.startDistance) / segmentLength);
		}
	}
	return clonePoint(path.samples[path.samples.length - 1]);
}

function collectPathSamples(path, startDistance, endDistance) {
	const result = [];
	let effectiveEnd = endDistance;
	if (path.closed && effectiveEnd <= startDistance) {
		effectiveEnd += path.totalLength;
	}

	const appendPoint = (point) => {
		if (result.length === 0 || distanceXZ(result[result.length - 1], point) > 0.05) {
			result.push(clonePoint(point));
		}
	};

	appendPoint(pathPointAtDistance(path, startDistance));
	const passes = path.closed ? 1 : 0;
	for (let pass = 0; pass <= passes; pass += 1) {
		const offset = pass * path.totalLength;
		for (let index = 0; index < path.samples.length; index += 1) {
			const d = path.distances[index] + offset;
			if (d > startDistance + 0.05 && d < effectiveEnd - 0.05) {
				appendPoint(path.samples[index]);
			}
		}
	}
	appendPoint(pathPointAtDistance(path, effectiveEnd));
	return result;
}

function pathDistanceForSegment(path, segmentIndex, t) {
	const segment = pathSegmentInfo(path, segmentIndex);
	return segment.startDistance + ((segment.endDistance - segment.startDistance) * t);
}

function closestPathHit(path, point) {
	let best = null;
	const segmentCount = path.closed ? path.samples.length : path.samples.length - 1;
	for (let index = 0; index < segmentCount; index += 1) {
		const segment = pathSegmentInfo(path, index);
		const projection = closestPointOnSegmentXZ(segment.a, segment.b, point);
		if (!best || projection.distance < best.distance) {
			best = {
				path,
				chain: path.chain,
				segment: index,
				t: projection.t,
				point: projection.point,
				distance: projection.distance,
				pathDistance: pathDistanceForSegment(path, index, projection.t),
				lineDir: horizontalUnit(subtract2D(segment.b, segment.a)) || { x: 0, z: 1 },
			};
		}
	}
	return best;
}
