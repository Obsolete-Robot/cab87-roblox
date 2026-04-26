// Sidebar UI and inspector updates.

function activateSidebarPanel(panelId) {
	const hasPanel = elements.sidebarPanels.some((panel) => panel.dataset.sidebarPanel === panelId);
	const activePanel = hasPanel ? panelId : "splines";
	const wasJunctionModeEnabled = state.junctionModeEnabled;
	const wasSoftSelectionEnabled = state.softSelectionEnabled;
	state.activeSidebarPanel = activePanel;
	setJunctionModeEnabled(activePanel === "junctions");
	state.softSelectionEnabled = activePanel === "soft-selection";
	if (!state.softSelectionEnabled && state.drag && state.drag.mode === "soft-selection") {
		state.drag = null;
	}

	for (const tab of elements.sidebarTabs) {
		const active = tab.dataset.sidebarTab === activePanel;
		tab.classList.toggle("active", active);
		tab.setAttribute("aria-selected", String(active));
		tab.tabIndex = active ? 0 : -1;
	}

	for (const panel of elements.sidebarPanels) {
		const active = panel.dataset.sidebarPanel === activePanel;
		panel.classList.toggle("active", active);
		panel.hidden = !active;
	}

	refreshInspector();
	requestRender();

	if (autosaveReady) {
		if (state.softSelectionEnabled && wasSoftSelectionEnabled !== state.softSelectionEnabled) {
			setStatus(getSoftSelectionStatus());
		} else if (state.junctionModeEnabled && wasJunctionModeEnabled !== state.junctionModeEnabled) {
			setStatus(getJunctionModeStatus());
		} else if (wasSoftSelectionEnabled !== state.softSelectionEnabled) {
			setStatus(getSoftSelectionStatus());
		} else if (wasJunctionModeEnabled !== state.junctionModeEnabled) {
			setStatus(getJunctionModeStatus());
		}
	}
}

function activateAdjacentSidebarPanel(direction) {
	const tabs = elements.sidebarTabs;
	const currentIndex = tabs.findIndex((tab) => tab.dataset.sidebarTab === state.activeSidebarPanel);
	const safeIndex = currentIndex >= 0 ? currentIndex : 0;
	const nextIndex = (safeIndex + direction + tabs.length) % tabs.length;
	const nextTab = tabs[nextIndex];

	activateSidebarPanel(nextTab.dataset.sidebarTab);
	nextTab.focus();
}

function handleSidebarTabKeyDown(event) {
	if (event.key === "ArrowRight") {
		event.preventDefault();
		activateAdjacentSidebarPanel(1);
	} else if (event.key === "ArrowLeft") {
		event.preventDefault();
		activateAdjacentSidebarPanel(-1);
	} else if (event.key === "Home") {
		event.preventDefault();
		activateSidebarPanel(elements.sidebarTabs[0].dataset.sidebarTab);
		elements.sidebarTabs[0].focus();
	} else if (event.key === "End") {
		event.preventDefault();
		const lastTab = elements.sidebarTabs[elements.sidebarTabs.length - 1];
		activateSidebarPanel(lastTab.dataset.sidebarTab);
		lastTab.focus();
	}
}

function setStatus(message) {
	state.statusMessage = message;
	updateStatus();
}

function updateStatus() {
	const spline = getActiveSpline();
	const selected = getSelectedPointRecord();
	const previewMode = state.meshPreviewEnabled ? "Mesh" : "Ribbon";
	const softMode = state.softSelectionEnabled
		? ` | Soft ${formatNumber(state.softSelectionRadius, 1)} studs`
		: "";
	const selectedText = selected
		? `Selected ${selected.spline.name}:${selected.pointIndex + 1} at X ${formatNumber(selected.point.x, 1)}, Z ${formatNumber(selected.point.z, 1)}.`
		: "No point selected.";
	elements.status.textContent =
		`${spline.name} | ${spline.points.length} control points | ${spline.closed ? "Closed" : "Open"} | Width ${formatNumber(spline.width, 1)} studs | Preview ${previewMode}${softMode}.\n` +
		`${selectedText}\n` +
		`${state.statusMessage || "Preview uses the same Catmull-Rom subdivision rule as the Roblox road editor sampler."}`;
}

function setJunctionModeEnabled(enabled) {
	state.junctionModeEnabled = enabled;
}

function getJunctionModeStatus() {
	return state.junctionModeEnabled
		? "Junction editing enabled. Click an existing curve point to add, drag centers to move junctions and grouped points, drag radius rings to scale, Alt-click to delete."
		: "Junction editing disabled.";
}

function focusJunctionPanel() {
	activateSidebarPanel("junctions");
	refreshInspector();
	setStatus(getJunctionModeStatus());
}

function focusSoftSelectionPanel() {
	activateSidebarPanel("soft-selection");
	refreshInspector();
	setStatus(getSoftSelectionStatus());
}

function refreshInspector() {
	const spline = getActiveSpline();
	elements.widthInput.value = formatNumber(spline.width, 1);
	elements.closedToggle.checked = spline.closed;
	elements.meshPreviewToggle.checked = state.meshPreviewEnabled;
	setJunctionModeEnabled(state.activeSidebarPanel === "junctions");
	const selectedJunction = getSelectedJunction();
	elements.junctionRadiusInput.value = formatNumber(selectedJunction ? selectedJunction.radius : JUNCTION_RADIUS_DEFAULT, 1);
	elements.junctionSubdivisionsInput.value = String(selectedJunction ? sanitizeJunctionSubdivisions(selectedJunction.subdivisions) : JUNCTION_SUBDIVISIONS_DEFAULT);
	elements.softSelectionRadiusInput.value = formatNumber(state.softSelectionRadius, 1);
	elements.softSelectionRadiusSlider.value = String(Math.round(state.softSelectionRadius));
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
