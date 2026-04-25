// Trace image loading and transform helpers.

function hasLoadedImage() {
	return Boolean(state.image.element && state.image.dataUrl);
}


function readFileAsDataUrl(file) {
	return new Promise((resolve, reject) => {
		const reader = new FileReader();
		reader.onload = () => resolve(typeof reader.result === "string" ? reader.result : "");
		reader.onerror = () => reject(new Error(`Could not read ${file.name}.`));
		reader.readAsDataURL(file);
	});
}

function loadImageFromDataUrl(dataUrl, metadata = {}) {
	return new Promise((resolve, reject) => {
		if (!dataUrl) {
			reject(new Error("Missing image data."));
			return;
		}

		const image = new Image();
		image.onload = () => {
			state.image.element = image;
			state.image.dataUrl = dataUrl;
			state.image.fileName = metadata.fileName || "";
			state.image.mimeType = metadata.mimeType || "";
			state.image.intrinsicWidth = image.naturalWidth || image.width || Number(metadata.width) || 0;
			state.image.intrinsicHeight = image.naturalHeight || image.height || Number(metadata.height) || 0;
			resolve(image);
		};
		image.onerror = () => reject(new Error(`Could not decode image ${metadata.fileName || ""}`.trim()));
		image.src = dataUrl;
	});
}

function clearImageSourceState() {
	if (state.image.objectUrl) {
		URL.revokeObjectURL(state.image.objectUrl);
	}
	state.image = createEmptyImageState();
}

function updateImageTransformFromInputs() {
	const offsetX = Number(elements.imageOffsetXInput.value);
	const offsetZ = Number(elements.imageOffsetZInput.value);
	const scale = Number(elements.imageScaleInput.value);
	state.image.offsetX = Number.isFinite(offsetX) ? offsetX : 0;
	state.image.offsetZ = Number.isFinite(offsetZ) ? offsetZ : 0;
	state.image.scale = Number.isFinite(scale) && scale > 0 ? scale : 1;
	refreshInspector();
	requestRender();
}

function resetImageTransform() {
	state.image.offsetX = 0;
	state.image.offsetZ = 0;
	state.image.scale = 1;
	state.image.opacity = 55;
	refreshInspector();
	requestRender();
	setStatus("Reset image transform.");
}

function clearImage() {
	clearImageSourceState();
	elements.imageInput.value = "";
	refreshInspector();
	requestRender();
	setStatus("Cleared trace image.");
}

async function loadImageFromFile(file) {
	if (!file) {
		return;
	}
	try {
		clearImageSourceState();
		const dataUrl = await readFileAsDataUrl(file);
		await loadImageFromDataUrl(dataUrl, {
			fileName: file.name,
			mimeType: file.type,
		});
		resetImageTransform();
		setStatus(`Loaded trace image ${file.name}.`);
	} catch (error) {
		setStatus(error.message || `Could not load image ${file.name}.`);
	}
}
