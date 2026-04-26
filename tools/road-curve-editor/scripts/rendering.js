// Canvas transforms and draw routines.

function worldToScreen(x, z) {
	return {
		x: ((x - state.cameraX) * state.zoom) + (elements.canvas.clientWidth * 0.5),
		y: ((state.cameraZ - z) * state.zoom) + (elements.canvas.clientHeight * 0.5),
	};
}

function screenToWorld(x, y) {
	return {
		x: ((x - (elements.canvas.clientWidth * 0.5)) / state.zoom) + state.cameraX,
		z: state.cameraZ - ((y - (elements.canvas.clientHeight * 0.5)) / state.zoom),
	};
}

function requestRender(options = {}) {
	if (!options.skipAutosave) {
		scheduleAutosave();
	}
	if (renderQueued) {
		return;
	}
	renderQueued = true;
	window.requestAnimationFrame(() => {
		renderQueued = false;
		render();
	});
}

function resizeCanvas() {
	const dpr = window.devicePixelRatio || 1;
	const width = Math.max(1, Math.floor(elements.canvas.clientWidth * dpr));
	const height = Math.max(1, Math.floor(elements.canvas.clientHeight * dpr));
	if (elements.canvas.width !== width || elements.canvas.height !== height) {
		elements.canvas.width = width;
		elements.canvas.height = height;
	}
	ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
	requestRender();
}

function drawGrid() {
	const width = elements.canvas.clientWidth;
	const height = elements.canvas.clientHeight;
	const bounds = {
		left: screenToWorld(0, height).x,
		right: screenToWorld(width, 0).x,
		bottom: screenToWorld(0, height).z,
		top: screenToWorld(width, 0).z,
	};
	const minorStep = 25;
	const majorStep = 100;

	ctx.fillStyle = "#d5dfe1";
	ctx.fillRect(0, 0, width, height);

	for (let x = Math.floor(bounds.left / minorStep) * minorStep; x <= bounds.right; x += minorStep) {
		const screen = worldToScreen(x, 0).x;
		const major = Math.abs(x % majorStep) < 0.001;
		ctx.beginPath();
		ctx.strokeStyle = major ? "rgba(35, 49, 58, 0.18)" : "rgba(35, 49, 58, 0.08)";
		ctx.lineWidth = major ? 1.2 : 1;
		ctx.moveTo(screen, 0);
		ctx.lineTo(screen, height);
		ctx.stroke();
	}

	for (let z = Math.floor(bounds.bottom / minorStep) * minorStep; z <= bounds.top; z += minorStep) {
		const screen = worldToScreen(0, z).y;
		const major = Math.abs(z % majorStep) < 0.001;
		ctx.beginPath();
		ctx.strokeStyle = major ? "rgba(35, 49, 58, 0.18)" : "rgba(35, 49, 58, 0.08)";
		ctx.lineWidth = major ? 1.2 : 1;
		ctx.moveTo(0, screen);
		ctx.lineTo(width, screen);
		ctx.stroke();
	}

	const origin = worldToScreen(0, 0);
	ctx.beginPath();
	ctx.strokeStyle = "rgba(200, 91, 42, 0.35)";
	ctx.lineWidth = 1.5;
	ctx.moveTo(origin.x, 0);
	ctx.lineTo(origin.x, height);
	ctx.moveTo(0, origin.y);
	ctx.lineTo(width, origin.y);
	ctx.stroke();
}

function drawTraceImage() {
	const image = state.image.element;
	if (!image) {
		return;
	}
	const center = worldToScreen(state.image.offsetX, state.image.offsetZ);
	const width = image.width * state.image.scale * state.zoom;
	const height = image.height * state.image.scale * state.zoom;
	ctx.save();
	ctx.globalAlpha = Math.min(1, Math.max(0, state.image.opacity / 100));
	ctx.drawImage(image, center.x - (width * 0.5), center.y - (height * 0.5), width, height);
	ctx.restore();
}

function drawSoftSelectionOverlay() {
	const softDrag = state.drag && state.drag.mode === "soft-selection" ? state.drag : null;
	if (!state.softSelectionEnabled && !softDrag) {
		return;
	}

	const center = softDrag
		? { x: softDrag.originX, z: softDrag.originZ }
		: state.mouseWorld;
	const radius = softDrag ? softDrag.radius : sanitizeSoftSelectionRadius(state.softSelectionRadius);
	const screen = worldToScreen(center.x, center.z);
	const radiusPixels = radius * state.zoom;

	ctx.save();
	ctx.beginPath();
	ctx.arc(screen.x, screen.y, radiusPixels, 0, Math.PI * 2);
	ctx.fillStyle = "rgba(44, 112, 122, 0.09)";
	ctx.fill();
	ctx.setLineDash([8, 7]);
	ctx.lineWidth = 1.5;
	ctx.strokeStyle = "rgba(44, 112, 122, 0.72)";
	ctx.stroke();
	ctx.setLineDash([]);

	ctx.beginPath();
	ctx.arc(screen.x, screen.y, 4.5, 0, Math.PI * 2);
	ctx.fillStyle = "rgba(44, 112, 122, 0.85)";
	ctx.fill();

	if (softDrag) {
		for (const target of softDrag.targets) {
			const targetScreen = worldToScreen(target.target.x, target.target.z);
			ctx.beginPath();
			ctx.arc(targetScreen.x, targetScreen.y, 3.5 + (4 * target.weight), 0, Math.PI * 2);
			ctx.fillStyle = target.type === "junction"
				? `rgba(28, 132, 125, ${0.28 + (target.weight * 0.48)})`
				: `rgba(255, 175, 69, ${0.24 + (target.weight * 0.5)})`;
			ctx.fill();
			ctx.lineWidth = 1;
			ctx.strokeStyle = `rgba(255, 250, 242, ${0.45 + (target.weight * 0.45)})`;
			ctx.stroke();
		}
	}

	ctx.restore();
}

function drawSplineRibbon(spline, active) {
	if (spline.points.length < 2) {
		return;
	}
	const samples = samplePositions(spline.points.map(createVector), spline.closed, SAMPLE_STEP_STUDS);
	if (samples.length < 2) {
		return;
	}

	ctx.save();
	ctx.beginPath();
	samples.forEach((sample, index) => {
		const screen = worldToScreen(sample.x, sample.z);
		if (index === 0) {
			ctx.moveTo(screen.x, screen.y);
		} else {
			ctx.lineTo(screen.x, screen.y);
		}
	});
	ctx.lineCap = "round";
	ctx.lineJoin = "round";
	ctx.strokeStyle = active ? "rgba(26, 33, 38, 0.95)" : "rgba(55, 67, 76, 0.55)";
	ctx.lineWidth = Math.max(2, spline.width * state.zoom);
	ctx.stroke();

	ctx.beginPath();
	samples.forEach((sample, index) => {
		const screen = worldToScreen(sample.x, sample.z);
		if (index === 0) {
			ctx.moveTo(screen.x, screen.y);
		} else {
			ctx.lineTo(screen.x, screen.y);
		}
	});
	ctx.lineCap = "round";
	ctx.lineJoin = "round";
	ctx.strokeStyle = active ? "rgba(235, 224, 207, 0.52)" : "rgba(236, 231, 222, 0.28)";
	ctx.lineWidth = Math.max(1.5, (spline.width * state.zoom) - 4);
	ctx.stroke();
	ctx.restore();
}

function drawMeshPreview() {
	const preview = getMeshPreview();
	if (!preview) {
		return;
	}

	ctx.save();

	for (const chain of preview.chains) {
		const sections = chain.sections;
		if (!sections) {
			continue;
		}

		for (let rowIndex = 0; rowIndex < sections.spanCount; rowIndex += 1) {
			const nextIndex = sections.closed ? ((rowIndex + 1) % sections.rowCount) : (rowIndex + 1);
			const leftA = worldToScreen(sections.left[rowIndex].x, sections.left[rowIndex].z);
			const leftB = worldToScreen(sections.left[nextIndex].x, sections.left[nextIndex].z);
			const rightB = worldToScreen(sections.right[nextIndex].x, sections.right[nextIndex].z);
			const rightA = worldToScreen(sections.right[rowIndex].x, sections.right[rowIndex].z);

			ctx.beginPath();
			ctx.moveTo(leftA.x, leftA.y);
			ctx.lineTo(leftB.x, leftB.y);
			ctx.lineTo(rightB.x, rightB.y);
			ctx.lineTo(rightA.x, rightA.y);
			ctx.closePath();
			ctx.fillStyle = "rgba(26, 33, 38, 0.9)";
			ctx.fill();
		}
	}

	for (const junction of preview.junctions) {
		for (const quad of buildJunctionConnectorQuads(junction)) {
			ctx.beginPath();
			quad.forEach((point, index) => {
				const screen = worldToScreen(point.x, point.z);
				if (index === 0) {
					ctx.moveTo(screen.x, screen.y);
				} else {
					ctx.lineTo(screen.x, screen.y);
				}
			});
			ctx.closePath();
			ctx.fillStyle = "rgba(26, 33, 38, 0.92)";
			ctx.fill();
		}

		const boundary = addJunctionPatchToMeshPreviewRows(junction);
		if (boundary.length < 3) {
			continue;
		}
		ctx.beginPath();
		boundary.forEach((point, index) => {
			const screen = worldToScreen(point.x, point.z);
			if (index === 0) {
				ctx.moveTo(screen.x, screen.y);
			} else {
				ctx.lineTo(screen.x, screen.y);
			}
		});
		ctx.closePath();
		ctx.fillStyle = "rgba(26, 33, 38, 0.92)";
		ctx.fill();
	}

	ctx.strokeStyle = "rgba(223, 238, 241, 0.3)";
	ctx.lineWidth = 1;

	for (const chain of preview.chains) {
		const sections = chain.sections;
		if (!sections) {
			continue;
		}

		const rows = [];
		for (let rowIndex = 0; rowIndex < sections.rowCount; rowIndex += 1) {
			rows[rowIndex] = buildLoftRowVertices(sections.left[rowIndex], sections.right[rowIndex], sections.widthSegments);
		}

		for (let rowIndex = 0; rowIndex < sections.rowCount; rowIndex += 1) {
			ctx.beginPath();
			for (let segment = 0; segment <= sections.widthSegments; segment += 1) {
				const vertex = worldToScreen(rows[rowIndex][segment].x, rows[rowIndex][segment].z);
				if (segment === 0) {
					ctx.moveTo(vertex.x, vertex.y);
				} else {
					ctx.lineTo(vertex.x, vertex.y);
				}
			}
			ctx.stroke();
		}

		for (let rowIndex = 0; rowIndex < sections.spanCount; rowIndex += 1) {
			const nextIndex = sections.closed ? ((rowIndex + 1) % sections.rowCount) : (rowIndex + 1);
			for (let segment = 0; segment <= sections.widthSegments; segment += 1) {
				const from = worldToScreen(rows[rowIndex][segment].x, rows[rowIndex][segment].z);
				const to = worldToScreen(rows[nextIndex][segment].x, rows[nextIndex][segment].z);
				ctx.beginPath();
				ctx.moveTo(from.x, from.y);
				ctx.lineTo(to.x, to.y);
				ctx.stroke();
			}

			for (let segment = 0; segment < sections.widthSegments; segment += 1) {
				const diagonalFrom = worldToScreen(rows[rowIndex][segment].x, rows[rowIndex][segment].z);
				const diagonalTo = worldToScreen(rows[nextIndex][segment + 1].x, rows[nextIndex][segment + 1].z);
				ctx.beginPath();
				ctx.moveTo(diagonalFrom.x, diagonalFrom.y);
				ctx.lineTo(diagonalTo.x, diagonalTo.y);
				ctx.stroke();
			}
		}
	}

	ctx.strokeStyle = "rgba(223, 238, 241, 0.28)";
	for (const junction of preview.junctions) {
		for (const quad of buildJunctionConnectorQuads(junction)) {
			ctx.beginPath();
			quad.forEach((point, index) => {
				const screen = worldToScreen(point.x, point.z);
				if (index === 0) {
					ctx.moveTo(screen.x, screen.y);
				} else {
					ctx.lineTo(screen.x, screen.y);
				}
			});
			ctx.closePath();
			ctx.stroke();

			const a = worldToScreen(quad[0].x, quad[0].z);
			const c = worldToScreen(quad[2].x, quad[2].z);
			ctx.beginPath();
			ctx.moveTo(a.x, a.y);
			ctx.lineTo(c.x, c.y);
			ctx.stroke();
		}

		const boundary = addJunctionPatchToMeshPreviewRows(junction);
		if (boundary.length < 2) {
			continue;
		}
		ctx.beginPath();
		boundary.forEach((point, index) => {
			const screen = worldToScreen(point.x, point.z);
			if (index === 0) {
				ctx.moveTo(screen.x, screen.y);
			} else {
				ctx.lineTo(screen.x, screen.y);
			}
		});
		ctx.closePath();
		ctx.stroke();
		const meshCenter = getJunctionMeshCenter(junction);
		const center = worldToScreen(meshCenter.x, meshCenter.z);
		for (const point of boundary) {
			const edge = worldToScreen(point.x, point.z);
			ctx.beginPath();
			ctx.moveTo(center.x, center.y);
			ctx.lineTo(edge.x, edge.y);
			ctx.stroke();
		}
	}

	ctx.restore();
}

function drawControlPolygon(spline, active) {
	if (spline.points.length === 0) {
		return;
	}

	ctx.save();
	if (spline.points.length >= 2) {
		ctx.beginPath();
		spline.points.forEach((point, index) => {
			const screen = worldToScreen(point.x, point.z);
			if (index === 0) {
				ctx.moveTo(screen.x, screen.y);
			} else {
				ctx.lineTo(screen.x, screen.y);
			}
		});
		if (spline.closed && spline.points.length >= 3) {
			const first = worldToScreen(spline.points[0].x, spline.points[0].z);
			ctx.lineTo(first.x, first.y);
		}
		ctx.setLineDash([6, 6]);
		ctx.strokeStyle = active ? "rgba(200, 91, 42, 0.95)" : "rgba(200, 91, 42, 0.45)";
		ctx.lineWidth = active ? 1.5 : 1;
		ctx.stroke();
		ctx.setLineDash([]);
	}

	spline.points.forEach((point, pointIndex) => {
		const screen = worldToScreen(point.x, point.z);
		const isSelected = state.selectedPoint
			&& state.selectedPoint.splineId === spline.id
			&& state.selectedPoint.pointIndex === pointIndex;

		ctx.beginPath();
		ctx.arc(screen.x, screen.y, isSelected ? 7 : 5.5, 0, Math.PI * 2);
		ctx.fillStyle = isSelected ? "#d6421a" : "#ffaf45";
		ctx.fill();
		ctx.lineWidth = 2;
		ctx.strokeStyle = active ? "rgba(255, 250, 242, 0.96)" : "rgba(255, 250, 242, 0.74)";
		ctx.stroke();
	});

	ctx.restore();
}

function drawJunctions() {
	ctx.save();
	for (const junction of state.junctions) {
		const screen = worldToScreen(junction.x, junction.z);
		const selected = junction.id === state.selectedJunctionId;
		const radiusPixels = Math.max(5, junction.radius * state.zoom);
		ctx.beginPath();
		ctx.arc(screen.x, screen.y, radiusPixels, 0, Math.PI * 2);
		ctx.fillStyle = selected ? "rgba(214, 66, 26, 0.2)" : "rgba(28, 132, 125, 0.16)";
		ctx.fill();
		ctx.lineWidth = selected ? 2.5 : 1.5;
		ctx.strokeStyle = selected ? "rgba(214, 66, 26, 0.9)" : "rgba(28, 132, 125, 0.78)";
		ctx.stroke();

		if (selected) {
			ctx.beginPath();
			ctx.arc(screen.x + radiusPixels, screen.y, 4.5, 0, Math.PI * 2);
			ctx.fillStyle = "#d6421a";
			ctx.fill();
			ctx.strokeStyle = "rgba(255, 250, 242, 0.92)";
			ctx.lineWidth = 1.5;
			ctx.stroke();
		}

		ctx.beginPath();
		ctx.arc(screen.x, screen.y, selected ? 6 : 4.5, 0, Math.PI * 2);
		ctx.fillStyle = selected ? "#d6421a" : "#1c847d";
		ctx.fill();
		ctx.strokeStyle = "rgba(255, 250, 242, 0.9)";
		ctx.lineWidth = 1.5;
		ctx.stroke();
	}
	ctx.restore();
}

function render() {
	resizeCanvas();
	const width = elements.canvas.clientWidth;
	const height = elements.canvas.clientHeight;
	ctx.clearRect(0, 0, width, height);
	drawGrid();
	drawTraceImage();
	if (state.meshPreviewEnabled) {
		drawMeshPreview();
	} else {
		state.splines.forEach((spline, index) => {
			drawSplineRibbon(spline, index === state.activeSplineIndex);
		});
	}

	drawSoftSelectionOverlay();
	state.splines.forEach((spline, index) => {
		drawControlPolygon(spline, index === state.activeSplineIndex);
	});
	drawJunctions();
}
