// Mesh preview orchestration and caching.

function computeMeshPreview() {
	const sourceChains = buildSourceChainsFromSplines(state.splines);

	if (sourceChains.length === 0) {
		return { chains: [], junctions: [] };
	}

	const junctions = state.junctions
		.filter(junctionHasCurveConnections)
		.map(cloneJunctionForPreview);
	const chains = applyExplicitJunctionsToChains(sourceChains, junctions);
	const activeJunctions = mergeAuthoredAndAutomaticJunctions(junctions, collectAutomaticJunctions(chains));
	const automaticJunctions = activeJunctions.slice(junctions.length);
	applyJunctionsToChains(chains, automaticJunctions);
	attachMemberJunctionPortals(automaticJunctions);
	finalizeAutomaticJunctionPortals(automaticJunctions);

	for (const chain of chains) {
		chain.sections = buildRoadCrossSections(chain.samples, chain.width);
	}

	return { chains, junctions: activeJunctions };
}

function getMeshPreview() {
	if (!state.meshPreviewEnabled) {
		return null;
	}
	if (!state.meshPreviewDirty && state.meshPreviewCache) {
		return state.meshPreviewCache;
	}
	state.meshPreviewCache = computeMeshPreview();
	state.meshPreviewDirty = false;
	return state.meshPreviewCache;
}
