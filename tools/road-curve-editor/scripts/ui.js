// Sidebar UI and inspector updates.

function setStatus(message) {
	state.statusMessage = message;
	updateStatus();
}

function updateStatus() {
	const spline = getActiveSpline();
	const selected = getSelectedPointRecord();
	const previewMode = state.meshPreviewEnabled ? "Mesh" : "Ribbon";
	const selectedText = selected
		? `Selected ${selected.spline.name}:${selected.pointIndex + 1} at X ${formatNumber(selected.point.x, 1)}, Z ${formatNumber(selected.point.z, 1)}.`
		: "No point selected.";
	elements.status.textContent =
		`${spline.name} | ${spline.points.length} control points | ${spline.closed ? "Closed" : "Open"} | Width ${formatNumber(spline.width, 1)} studs | Preview ${previewMode}.\n` +
		`${selectedText}\n` +
		`${state.statusMessage || "Preview uses the same Catmull-Rom subdivision rule as the Roblox road editor sampler."}`;
}

function setJunctionModeEnabled(enabled) {
	state.junctionModeEnabled = enabled;
	elements.junctionModeButton.classList.toggle("primary", enabled);
	elements.junctionModeButton.textContent = enabled ? "Junction Mode: On" : "Junction Mode";
}

function getJunctionModeStatus() {
	return state.junctionModeEnabled
		? "Junction Mode enabled. Click an existing curve point to add, drag centers to move grouped points, drag radius rings to scale, Alt-click to delete."
		: "Junction Mode disabled.";
}

function toggleJunctionMode() {
	setJunctionModeEnabled(!state.junctionModeEnabled);
	refreshInspector();
	setStatus(getJunctionModeStatus());
}

function refreshInspector() {
	const spline = getActiveSpline();
	elements.widthInput.value = formatNumber(spline.width, 1);
	elements.closedToggle.checked = spline.closed;
	elements.meshPreviewToggle.checked = state.meshPreviewEnabled;
	setJunctionModeEnabled(state.junctionModeEnabled);
	const selectedJunction = getSelectedJunction();
	elements.junctionRadiusInput.value = formatNumber(selectedJunction ? selectedJunction.radius : JUNCTION_RADIUS_DEFAULT, 1);
	elements.junctionSubdivisionsInput.value = String(selectedJunction ? sanitizeJunctionSubdivisions(selectedJunction.subdivisions) : JUNCTION_SUBDIVISIONS_DEFAULT);
	elements.imageOffsetXInput.value = formatNumber(state.image.offsetX, 1);
	elements.imageOffsetZInput.value = formatNumber(state.image.offsetZ, 1);
	elements.imageScaleInput.value = formatNumber(state.image.scale, 2);
	elements.imageOpacityInput.value = String(state.image.opacity);
	updateStatus();
}

function markMeshPreviewDirty() {
	state.meshPreviewDirty = true;
	state.meshPreviewCache = null;
}

function renderSplineList() {
	elements.splineList.textContent = "";
	state.splines.forEach((spline, index) => {
		const card = document.createElement("button");
		card.type = "button";
		card.className = `spline-card${index === state.activeSplineIndex ? " active" : ""}`;
		card.addEventListener("click", () => {
			setActiveSpline(index);
			setStatus(`Active spline set to ${spline.name}.`);
		});

		const title = document.createElement("div");
		title.className = "spline-card-title";
		title.innerHTML = `<span>${spline.name}</span><span>${formatNumber(spline.width, 1)}</span>`;

		const meta = document.createElement("div");
		meta.className = "spline-card-meta";
		meta.textContent = `${spline.closed ? "Closed" : "Open"} | ${spline.points.length} pts`;

		card.append(title, meta);
		elements.splineList.append(card);
	});
}

