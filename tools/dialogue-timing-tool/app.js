const state = {
	file: null,
	audioUrl: "",
	audioBuffer: null,
	duration: 0,
	result: null,
	words: [],
	segments: [],
	activeIndex: -1,
	selectedIndex: -1,
	playbackFrameId: 0,
	sidebarCollapsed: false,
	status: "idle",
};

const els = {
	audioInput: document.getElementById("audioInput"),
	jsonInput: document.getElementById("jsonInput"),
	importButton: document.getElementById("importButton"),
	dropZone: document.getElementById("dropZone"),
	fileMeta: document.getElementById("fileMeta"),
	audioPlayer: document.getElementById("audioPlayer"),
	playPauseButton: document.getElementById("playPauseButton"),
	transcribeButton: document.getElementById("transcribeButton"),
	sidebarToggleButton: document.getElementById("sidebarToggleButton"),
	clearButton: document.getElementById("clearButton"),
	engineInput: document.getElementById("engineInput"),
	languageInput: document.getElementById("languageInput"),
	promptInput: document.getElementById("promptInput"),
	fpsInput: document.getElementById("fpsInput"),
	statusText: document.getElementById("statusText"),
	waveformCanvas: document.getElementById("waveformCanvas"),
	playhead: document.getElementById("playhead"),
	currentTimeReadout: document.getElementById("currentTimeReadout"),
	wordCountReadout: document.getElementById("wordCountReadout"),
	durationReadout: document.getElementById("durationReadout"),
	wordPreview: document.getElementById("wordPreview"),
	wordTableBody: document.getElementById("wordTableBody"),
	exportButtons: Array.from(document.querySelectorAll("[data-export]")),
	nudgeButtons: Array.from(document.querySelectorAll("[data-nudge]")),
	borrowButtons: Array.from(document.querySelectorAll("[data-borrow]")),
};

const ctx = els.waveformCanvas.getContext("2d");
const DEFAULT_WAVE_COLOR = "#6fa797";
const ACTIVE_COLOR = "#f9d35b";
const WORD_COLOR = "rgba(219, 235, 228, 0.18)";
const SELECTED_COLOR = "rgba(249, 211, 91, 0.26)";
const SIDEBAR_STORAGE_KEY = "cab87-dialogue-sidebar-collapsed";
const MIN_WORD_DURATION_SECONDS = 0.02;

function secondsToClock(seconds) {
	const safeSeconds = Math.max(0, Number.isFinite(seconds) ? seconds : 0);
	const totalMs = Math.round(safeSeconds * 1000);
	const minutes = Math.floor(totalMs / 60000);
	const remainingMs = totalMs - minutes * 60000;
	const wholeSeconds = Math.floor(remainingMs / 1000);
	const ms = remainingMs % 1000;
	return `${String(minutes).padStart(2, "0")}:${String(wholeSeconds).padStart(2, "0")}.${String(ms).padStart(3, "0")}`;
}

function secondsToSrt(seconds) {
	const safeSeconds = Math.max(0, Number.isFinite(seconds) ? seconds : 0);
	const totalMs = Math.round(safeSeconds * 1000);
	const hours = Math.floor(totalMs / 3600000);
	const minutes = Math.floor((totalMs % 3600000) / 60000);
	const wholeSeconds = Math.floor((totalMs % 60000) / 1000);
	const ms = totalMs % 1000;
	return `${String(hours).padStart(2, "0")}:${String(minutes).padStart(2, "0")}:${String(wholeSeconds).padStart(2, "0")},${String(ms).padStart(3, "0")}`;
}

function secondsToVtt(seconds) {
	return secondsToSrt(seconds).replace(",", ".");
}

function secondsToTimecode(seconds, fps) {
	const safeFps = Number.isFinite(fps) && fps > 0 ? fps : 30;
	const safeSeconds = Math.max(0, Number.isFinite(seconds) ? seconds : 0);
	const nominalFps = Math.round(safeFps);
	let totalFrames = Math.round(safeSeconds * safeFps);
	let separator = ":";

	if (Math.abs(safeFps - 29.97) < 0.01) {
		const dropFrames = 2;
		const framesPer10Minutes = nominalFps * 60 * 10 - dropFrames * 9;
		const framesPerMinute = nominalFps * 60 - dropFrames;
		const tenMinuteChunks = Math.floor(totalFrames / framesPer10Minutes);
		const remainingFrames = totalFrames % framesPer10Minutes;
		totalFrames += dropFrames * 9 * tenMinuteChunks;
		totalFrames += dropFrames * Math.max(0, Math.floor((remainingFrames - dropFrames) / framesPerMinute));
		separator = ";";
	}

	const frames = totalFrames % nominalFps;
	const totalSeconds = Math.floor(totalFrames / nominalFps);
	const hours = Math.floor(totalSeconds / 3600);
	const minutes = Math.floor((totalSeconds % 3600) / 60);
	const secondsPart = totalSeconds % 60;
	return `${String(hours).padStart(2, "0")}:${String(minutes).padStart(2, "0")}:${String(secondsPart).padStart(2, "0")}${separator}${String(frames).padStart(2, "0")}`;
}

function parseClock(value) {
	const text = String(value).trim();
	if (!text) {
		return 0;
	}

	const parts = text.split(":").map(Number);
	if (parts.some((part) => !Number.isFinite(part))) {
		return Number(text) || 0;
	}

	if (parts.length === 3) {
		return parts[0] * 3600 + parts[1] * 60 + parts[2];
	}

	if (parts.length === 2) {
		return parts[0] * 60 + parts[1];
	}

	return parts[0] || 0;
}

function setStatus(message, tone = "") {
	els.statusText.textContent = message;
	els.statusText.className = `status-text ${tone}`.trim();
}

function readStoredSidebarState() {
	try {
		return window.localStorage.getItem(SIDEBAR_STORAGE_KEY) === "true";
	} catch {
		return false;
	}
}

function storeSidebarState(isCollapsed) {
	try {
		window.localStorage.setItem(SIDEBAR_STORAGE_KEY, String(isCollapsed));
	} catch {
		// Ignore storage failures; the toggle still works for the current session.
	}
}

function redrawAfterLayoutChange() {
	window.requestAnimationFrame(() => {
		drawWaveform();
		updatePlayhead();
	});
}

function setSidebarCollapsed(isCollapsed) {
	state.sidebarCollapsed = isCollapsed;
	document.body.classList.toggle("sidebar-collapsed", isCollapsed);
	els.sidebarToggleButton.textContent = isCollapsed ? "Show Sidebar" : "Hide Sidebar";
	els.sidebarToggleButton.setAttribute("aria-expanded", String(!isCollapsed));
	storeSidebarState(isCollapsed);
	redrawAfterLayoutChange();
}

function setBusy(isBusy) {
	state.status = isBusy ? "busy" : "idle";
	els.transcribeButton.disabled = isBusy || !state.file;
	els.audioInput.disabled = isBusy;
	els.importButton.disabled = isBusy;
}

function setExportEnabled(enabled) {
	for (const button of els.exportButtons) {
		button.disabled = !enabled;
	}
}

function updateTimingActionButtons() {
	const hasSelection = state.selectedIndex >= 0 && state.selectedIndex < state.words.length;
	for (const button of els.nudgeButtons) {
		button.disabled = !hasSelection;
	}
	for (const button of els.borrowButtons) {
		const direction = button.dataset.borrow;
		const hasNeighbor =
			hasSelection &&
			((direction === "prev" && state.selectedIndex > 0) ||
				(direction === "next" && state.selectedIndex < state.words.length - 1));
		button.disabled = !hasNeighbor;
	}
}

function clampWord(word) {
	word.start = Math.max(0, Number(word.start) || 0);
	word.end = Math.max(word.start, Number(word.end) || word.start);
	word.startMs = Math.round(word.start * 1000);
	word.endMs = Math.round(word.end * 1000);
}

function renumberWords() {
	state.words.forEach((word, index) => {
		word.id = index + 1;
	});
}

function activeWordIndexAtTime(time) {
	if (!state.words.length) {
		return -1;
	}

	let nearest = -1;
	for (let index = 0; index < state.words.length; index += 1) {
		const word = state.words[index];
		if (time >= word.start && time <= word.end) {
			return index;
		}
		if (time >= word.start) {
			nearest = index;
		}
	}

	return nearest;
}

function drawWaveform() {
	const canvas = els.waveformCanvas;
	const ratio = window.devicePixelRatio || 1;
	const rect = canvas.getBoundingClientRect();
	const width = Math.max(1, Math.round(rect.width * ratio));
	const height = Math.max(1, Math.round(rect.height * ratio));

	if (canvas.width !== width || canvas.height !== height) {
		canvas.width = width;
		canvas.height = height;
	}

	ctx.clearRect(0, 0, width, height);
	ctx.fillStyle = "#111a17";
	ctx.fillRect(0, 0, width, height);

	const duration = getDuration();
	if (duration > 0) {
		for (let index = 0; index < state.words.length; index += 1) {
			const word = state.words[index];
			const x = (word.start / duration) * width;
			const nextX = (word.end / duration) * width;
			ctx.fillStyle = index === state.selectedIndex ? SELECTED_COLOR : WORD_COLOR;
			ctx.fillRect(x, 0, Math.max(1, nextX - x), height);
		}
	}

	ctx.strokeStyle = "rgba(255, 255, 255, 0.12)";
	ctx.lineWidth = 1;
	for (let i = 1; i < 6; i += 1) {
		const y = (height / 6) * i;
		ctx.beginPath();
		ctx.moveTo(0, y);
		ctx.lineTo(width, y);
		ctx.stroke();
	}

	const channel = state.audioBuffer?.getChannelData(0);
	if (!channel) {
		ctx.strokeStyle = DEFAULT_WAVE_COLOR;
		ctx.lineWidth = Math.max(1, ratio);
		ctx.beginPath();
		ctx.moveTo(0, height / 2);
		ctx.lineTo(width, height / 2);
		ctx.stroke();
		return;
	}

	const samplesPerPixel = Math.max(1, Math.floor(channel.length / width));
	ctx.strokeStyle = DEFAULT_WAVE_COLOR;
	ctx.lineWidth = Math.max(1, ratio);
	ctx.beginPath();

	for (let x = 0; x < width; x += 1) {
		const start = x * samplesPerPixel;
		let min = 1;
		let max = -1;
		for (let sample = 0; sample < samplesPerPixel && start + sample < channel.length; sample += 1) {
			const value = channel[start + sample];
			if (value < min) {
				min = value;
			}
			if (value > max) {
				max = value;
			}
		}
		const y1 = ((1 - max) / 2) * height;
		const y2 = ((1 - min) / 2) * height;
		ctx.moveTo(x, y1);
		ctx.lineTo(x, y2);
	}

	ctx.stroke();

	if (state.activeIndex >= 0) {
		const word = state.words[state.activeIndex];
		if (duration > 0) {
			const x = (word.start / duration) * width;
			const w = Math.max(2, ((word.end - word.start) / duration) * width);
			ctx.fillStyle = "rgba(249, 211, 91, 0.28)";
			ctx.fillRect(x, 0, w, height);
		}
	}
}

function updatePlayhead() {
	const duration = getDuration();
	const percent = duration > 0 ? Math.min(1, Math.max(0, els.audioPlayer.currentTime / duration)) : 0;
	els.playhead.style.left = `${percent * 100}%`;
	els.currentTimeReadout.textContent = secondsToClock(els.audioPlayer.currentTime || 0);
}

function getDuration() {
	return state.duration || state.audioBuffer?.duration || els.audioPlayer.duration || 0;
}

function updateActiveWord() {
	const nextActive = activeWordIndexAtTime(els.audioPlayer.currentTime || 0);
	if (nextActive === state.activeIndex) {
		updatePlayhead();
		return;
	}

	const previousActive = state.activeIndex;
	state.activeIndex = nextActive;
	updatePreviewActive(previousActive, nextActive);
	updateTableActive(previousActive, nextActive);
	updatePlayhead();
	drawWaveform();
	updateTimingActionButtons();
}

function updatePlayButton() {
	const hasAudio = Boolean(state.file && els.audioPlayer.src);
	els.playPauseButton.disabled = !hasAudio;
	els.playPauseButton.textContent = !hasAudio || els.audioPlayer.paused ? "Play" : "Pause";
}

function playbackTick() {
	updateActiveWord();
	if (!els.audioPlayer.paused && !els.audioPlayer.ended) {
		state.playbackFrameId = window.requestAnimationFrame(playbackTick);
	}
}

function startPlaybackLoop() {
	if (state.playbackFrameId) {
		window.cancelAnimationFrame(state.playbackFrameId);
	}
	state.playbackFrameId = window.requestAnimationFrame(playbackTick);
}

function stopPlaybackLoop() {
	if (state.playbackFrameId) {
		window.cancelAnimationFrame(state.playbackFrameId);
		state.playbackFrameId = 0;
	}
	updateActiveWord();
}

async function togglePlayback() {
	if (!state.file || !els.audioPlayer.src) {
		return;
	}

	if (els.audioPlayer.ended) {
		els.audioPlayer.currentTime = 0;
	}

	if (els.audioPlayer.paused) {
		await els.audioPlayer.play();
	} else {
		els.audioPlayer.pause();
	}
}

function updatePreviewActive(previousIndex, nextIndex) {
	if (previousIndex >= 0) {
		els.wordPreview.querySelector(`[data-word-index="${previousIndex}"]`)?.classList.remove("active");
	}
	if (nextIndex >= 0) {
		els.wordPreview.querySelector(`[data-word-index="${nextIndex}"]`)?.classList.add("active");
	}
}

function updateTableActive(previousIndex, nextIndex) {
	if (previousIndex >= 0) {
		els.wordTableBody.querySelector(`[data-row-index="${previousIndex}"]`)?.classList.remove("active");
	}
	if (nextIndex >= 0) {
		els.wordTableBody.querySelector(`[data-row-index="${nextIndex}"]`)?.classList.add("active");
	}
}

function selectWord(index, shouldSeek = true) {
	state.selectedIndex = index;

	for (const node of els.wordPreview.querySelectorAll(".selected")) {
		node.classList.remove("selected");
	}
	for (const node of els.wordTableBody.querySelectorAll(".selected")) {
		node.classList.remove("selected");
	}

	if (index >= 0) {
		els.wordPreview.querySelector(`[data-word-index="${index}"]`)?.classList.add("selected");
		const row = els.wordTableBody.querySelector(`[data-row-index="${index}"]`);
		row?.classList.add("selected");
		row?.scrollIntoView({ block: "nearest" });

		if (shouldSeek) {
			els.audioPlayer.currentTime = state.words[index].start;
			updateActiveWord();
		}
	}

	drawWaveform();
	updateTimingActionButtons();
}

function renderPreview() {
	els.wordPreview.textContent = "";

	if (!state.words.length) {
		const empty = document.createElement("span");
		empty.className = "drop-meta";
		empty.textContent = "No timed words yet.";
		els.wordPreview.append(empty);
		return;
	}

	const fragment = document.createDocumentFragment();
	state.words.forEach((word, index) => {
		const chip = document.createElement("button");
		chip.type = "button";
		chip.className = "word-chip";
		chip.dataset.wordIndex = String(index);
		chip.textContent = word.word;
		chip.title = `${secondsToClock(word.start)} - ${secondsToClock(word.end)}`;
		chip.addEventListener("click", () => selectWord(index));
		fragment.append(chip);
	});

	els.wordPreview.append(fragment);
}

function renderTable() {
	els.wordTableBody.textContent = "";

	if (!state.words.length) {
		const row = document.createElement("tr");
		const cell = document.createElement("td");
		cell.colSpan = 6;
		cell.className = "empty-cell";
		cell.textContent = "No transcript loaded.";
		row.append(cell);
		els.wordTableBody.append(row);
		return;
	}

	const fps = Number(els.fpsInput.value);
	const fragment = document.createDocumentFragment();
	state.words.forEach((word, index) => {
		const row = document.createElement("tr");
		row.dataset.rowIndex = String(index);
		row.addEventListener("click", (event) => {
			if (event.target instanceof HTMLInputElement || event.target instanceof HTMLButtonElement) {
				return;
			}
			selectWord(index);
		});

		const numberCell = document.createElement("td");
		numberCell.textContent = String(index + 1);

		const wordCell = document.createElement("td");
		const wordInput = document.createElement("input");
		wordInput.className = "word-input";
		wordInput.value = word.word;
		wordInput.addEventListener("change", () => {
			word.word = wordInput.value.trim();
			renderPreview();
			selectWord(index, false);
		});
		wordCell.append(wordInput);

		const startCell = document.createElement("td");
		const startInput = document.createElement("input");
		startInput.className = "time-input";
		startInput.value = secondsToClock(word.start);
		startInput.addEventListener("change", () => {
			word.start = parseClock(startInput.value);
			clampWord(word);
			renderAll(false);
			selectWord(index, false);
		});
		startCell.append(startInput);

		const endCell = document.createElement("td");
		const endInput = document.createElement("input");
		endInput.className = "time-input";
		endInput.value = secondsToClock(word.end);
		endInput.addEventListener("change", () => {
			word.end = parseClock(endInput.value);
			clampWord(word);
			renderAll(false);
			selectWord(index, false);
		});
		endCell.append(endInput);

		const timecodeCell = document.createElement("td");
		timecodeCell.className = "timecode-cell";
		timecodeCell.textContent = `${secondsToTimecode(word.start, fps)} - ${secondsToTimecode(word.end, fps)}`;

		const actionsCell = document.createElement("td");
		actionsCell.className = "actions-cell";
		const splitButton = document.createElement("button");
		splitButton.type = "button";
		splitButton.className = "split-button";
		splitButton.textContent = "Split";
		splitButton.disabled = word.word.trim().length < 2;
		splitButton.addEventListener("click", () => {
			word.word = wordInput.value.trim();
			splitWord(index, wordInput.value, wordInput.selectionStart);
		});

		const deleteButton = document.createElement("button");
		deleteButton.type = "button";
		deleteButton.className = "delete-button";
		deleteButton.textContent = "Trash";
		deleteButton.title = `Remove "${word.word}"`;
		deleteButton.addEventListener("click", () => deleteWord(index));

		actionsCell.append(splitButton, deleteButton);

		row.append(numberCell, wordCell, startCell, endCell, timecodeCell, actionsCell);
		fragment.append(row);
	});

	els.wordTableBody.append(fragment);
}

function renderAll(resetSelection = true) {
	if (resetSelection) {
		state.activeIndex = -1;
		state.selectedIndex = -1;
	}

	state.duration = Math.max(
		state.duration,
		state.words.reduce((max, word) => Math.max(max, word.end), 0),
		state.segments.reduce((max, segment) => Math.max(max, segment.end), 0),
		state.audioBuffer?.duration || 0,
		els.audioPlayer.duration || 0,
	);

	els.wordCountReadout.textContent = String(state.words.length);
	els.durationReadout.textContent = secondsToClock(state.duration);

	renderPreview();
	renderTable();
	setExportEnabled(state.words.length > 0);
	updatePlayButton();
	updateTimingActionButtons();
	updatePlayhead();
	drawWaveform();
}

async function decodeAudio(file) {
	if (!file) {
		state.audioBuffer = null;
		drawWaveform();
		return;
	}

	try {
		const AudioContextClass = window.AudioContext || window.webkitAudioContext;
		if (!AudioContextClass) {
			throw new Error("AudioContext is not available.");
		}
		const audioContext = new AudioContextClass();
		const arrayBuffer = await file.arrayBuffer();
		state.audioBuffer = await audioContext.decodeAudioData(arrayBuffer.slice(0));
		state.duration = state.audioBuffer.duration;
		await audioContext.close();
	} catch {
		state.audioBuffer = null;
		state.duration = 0;
	}

	els.durationReadout.textContent = secondsToClock(getDuration());
	drawWaveform();
}

async function loadAudioFile(file) {
	if (!file) {
		return;
	}

	if (state.audioUrl) {
		URL.revokeObjectURL(state.audioUrl);
	}

	state.file = file;
	state.audioUrl = URL.createObjectURL(file);
	els.audioPlayer.src = state.audioUrl;
	els.fileMeta.textContent = `${file.name} - ${formatBytes(file.size)}`;
	els.transcribeButton.disabled = false;
	updatePlayButton();
	setStatus("Audio loaded.");
	await decodeAudio(file);
}

function formatBytes(bytes) {
	if (!Number.isFinite(bytes)) {
		return "";
	}
	if (bytes < 1024 * 1024) {
		return `${Math.round(bytes / 1024)} KB`;
	}
	return `${(bytes / 1024 / 1024).toFixed(1)} MB`;
}

async function transcribe() {
	if (!state.file) {
		return;
	}

	setBusy(true);
	setStatus("Uploading and transcribing...");

	const form = new FormData();
	form.append("audio", state.file, state.file.name);
	form.append("engine", els.engineInput.value);
	form.append("language", els.languageInput.value.trim());
	form.append("prompt", els.promptInput.value.trim());

	try {
		const response = await fetch("/api/transcribe", {
			method: "POST",
			body: form,
		});
		const payload = await response.json();
		if (!response.ok) {
			throw new Error(payload.error || "Transcription failed.");
		}

		loadResult(payload);
		setStatus(`Transcribed ${state.words.length} timed words.`);
	} catch (error) {
		setStatus(error.message, "error");
	} finally {
		setBusy(false);
	}
}

function normalizeImportedWords(input) {
	const sourceWords = Array.isArray(input.words)
		? input.words
		: Array.isArray(input.items)
			? input.items
			: [];

	return sourceWords
		.map((word, index) => {
			const start = Number(word.start ?? word.startSeconds ?? word.start_time ?? word.startTime ?? 0);
			const end = Number(word.end ?? word.endSeconds ?? word.end_time ?? word.endTime ?? start);
			return {
				id: Number(word.id || index + 1),
				word: String(word.word ?? word.text ?? "").trim(),
				start: Math.max(0, start),
				end: Math.max(start, end),
				startMs: Math.round(Math.max(0, start) * 1000),
				endMs: Math.round(Math.max(start, end) * 1000),
			};
		})
		.filter((word) => word.word.length > 0);
}

function normalizeImportedSegments(input) {
	const sourceSegments = Array.isArray(input.segments) ? input.segments : [];
	return sourceSegments
		.map((segment, index) => {
			const start = Number(segment.start ?? segment.startSeconds ?? segment.start_time ?? 0);
			const end = Number(segment.end ?? segment.endSeconds ?? segment.end_time ?? start);
			return {
				id: segment.id ?? index + 1,
				text: String(segment.text ?? "").trim(),
				start: Math.max(0, start),
				end: Math.max(start, end),
				startMs: Math.round(Math.max(0, start) * 1000),
				endMs: Math.round(Math.max(start, end) * 1000),
			};
		})
		.filter((segment) => segment.text.length > 0);
}

function loadResult(payload) {
	state.result = payload;
	state.words = normalizeImportedWords(payload);
	state.segments = normalizeImportedSegments(payload);
	state.duration = Number(payload.duration) || state.duration;
	renumberWords();
	renderAll();
}

function splitCandidateFromPrompt(text) {
	const prompted = window.prompt("Insert a space where this timing should split.", text);
	if (prompted === null) {
		return null;
	}
	return prompted;
}

function splitTextParts(text, cursorIndex) {
	const rawText = String(text || "");
	const normalized = rawText.replace(/\s+/g, " ").trim();
	if (!normalized) {
		return null;
	}

	if (Number.isInteger(cursorIndex) && cursorIndex > 0 && cursorIndex < rawText.length) {
		const left = rawText.slice(0, cursorIndex).trim();
		const right = rawText.slice(cursorIndex).trim();
		if (left && right) {
			return [left, right];
		}
	}

	const whitespaceMatch = normalized.match(/\s+/);
	if (whitespaceMatch?.index) {
		const left = normalized.slice(0, whitespaceMatch.index).trim();
		const right = normalized.slice(whitespaceMatch.index).trim();
		if (left && right) {
			return [left, right];
		}
	}

	const prompted = splitCandidateFromPrompt(normalized);
	if (!prompted) {
		return null;
	}

	const promptedText = prompted.replace(/\s+/g, " ").trim();
	const promptedMatch = promptedText.match(/\s+/);
	if (!promptedMatch?.index) {
		return null;
	}

	const left = promptedText.slice(0, promptedMatch.index).trim();
	const right = promptedText.slice(promptedMatch.index).trim();
	return left && right ? [left, right] : null;
}

function splitRatioForParts(left, right) {
	const leftWeight = left.replace(/\s+/g, "").length;
	const rightWeight = right.replace(/\s+/g, "").length;
	const totalWeight = leftWeight + rightWeight;
	if (totalWeight <= 0) {
		return 0.5;
	}
	return Math.min(0.85, Math.max(0.15, leftWeight / totalWeight));
}

function splitWord(index, text, cursorIndex) {
	const word = state.words[index];
	if (!word) {
		return;
	}

	const parts = splitTextParts(text, cursorIndex);
	if (!parts) {
		setStatus("Add a space where the word should split, then try Split again.", "warning");
		return;
	}

	const [leftText, rightText] = parts;
	const splitRatio = splitRatioForParts(leftText, rightText);
	const duration = Math.max(0, word.end - word.start);
	const splitTime = duration > 0 ? word.start + duration * splitRatio : word.start;

	const leftWord = {
		...word,
		word: leftText,
		end: splitTime,
	};
	const rightWord = {
		...word,
		word: rightText,
		start: splitTime,
	};
	clampWord(leftWord);
	clampWord(rightWord);

	state.words.splice(index, 1, leftWord, rightWord);
	renumberWords();
	renderAll(false);
	selectWord(index, false);
	setStatus(`Split "${leftText} ${rightText}" at ${secondsToClock(splitTime)}.`);
}

function deleteWord(index) {
	const removedWord = state.words[index];
	if (!removedWord) {
		return;
	}

	state.words.splice(index, 1);
	renumberWords();

	const nextSelection = state.words.length ? Math.min(index, state.words.length - 1) : -1;
	renderAll(false);
	if (nextSelection >= 0) {
		selectWord(nextSelection, false);
	} else {
		state.selectedIndex = -1;
		state.activeIndex = -1;
		updateTimingActionButtons();
	}
	setStatus(`Removed "${removedWord.word}".`);
}

async function importJson(file) {
	if (!file) {
		return;
	}

	try {
		const payload = JSON.parse(await file.text());
		loadResult(payload);
		setStatus(`Imported ${state.words.length} timed words from JSON.`);
	} catch (error) {
		setStatus(`Could not import JSON: ${error.message}`, "error");
	}
}

function buildCaptionCues(words) {
	const cues = [];
	let current = [];
	let charCount = 0;
	const maxChars = 42;
	const maxDuration = 3.2;

	for (const word of words) {
		if (!word.word) {
			continue;
		}

		const wouldDuration = current.length ? word.end - current[0].start : 0;
		const wouldChars = charCount + word.word.length + (current.length ? 1 : 0);
		const endsSentence = /[.!?]$/.test(current[current.length - 1]?.word || "");

		if (current.length && (wouldChars > maxChars || wouldDuration > maxDuration || endsSentence)) {
			cues.push(wordsToCue(current));
			current = [];
			charCount = 0;
		}

		current.push(word);
		charCount += word.word.length + (current.length > 1 ? 1 : 0);
	}

	if (current.length) {
		cues.push(wordsToCue(current));
	}

	return cues;
}

function wordsToCue(words) {
	return {
		start: words[0].start,
		end: words[words.length - 1].end,
		text: words.map((word) => word.word).join(" "),
	};
}

function exportKineticJson() {
	const fps = Number(els.fpsInput.value);
	return {
		schema: "cab87-dialogue-timing",
		version: 1,
		fps,
		sourceFile: state.file?.name || null,
		duration: getDuration(),
		text: state.words.map((word) => word.word).join(" "),
		words: state.words.map((word, index) => ({
			index: index + 1,
			text: word.word,
			start: Number(word.start.toFixed(3)),
			end: Number(word.end.toFixed(3)),
			startMs: Math.round(word.start * 1000),
			endMs: Math.round(word.end * 1000),
			timecodeIn: secondsToTimecode(word.start, fps),
			timecodeOut: secondsToTimecode(word.end, fps),
		})),
		cues: buildCaptionCues(state.words).map((cue, index) => ({
			index: index + 1,
			text: cue.text,
			start: Number(cue.start.toFixed(3)),
			end: Number(cue.end.toFixed(3)),
			timecodeIn: secondsToTimecode(cue.start, fps),
			timecodeOut: secondsToTimecode(cue.end, fps),
		})),
	};
}

function exportCsv() {
	const fps = Number(els.fpsInput.value);
	const rows = [["index", "word", "start_seconds", "end_seconds", "start_ms", "end_ms", "timecode_in", "timecode_out"]];
	for (const [index, word] of state.words.entries()) {
		rows.push([
			index + 1,
			word.word,
			word.start.toFixed(3),
			word.end.toFixed(3),
			Math.round(word.start * 1000),
			Math.round(word.end * 1000),
			secondsToTimecode(word.start, fps),
			secondsToTimecode(word.end, fps),
		]);
	}

	return rows
		.map((row) =>
			row
				.map((value) => {
					const text = String(value);
					return /[",\n]/.test(text) ? `"${text.replace(/"/g, '""')}"` : text;
				})
				.join(","),
		)
		.join("\n");
}

function exportVtt() {
	const cues = buildCaptionCues(state.words);
	return [
		"WEBVTT",
		"",
		...cues.flatMap((cue) => [`${secondsToVtt(cue.start)} --> ${secondsToVtt(cue.end)}`, cue.text, ""]),
	].join("\n");
}

function exportSrt() {
	const cues = buildCaptionCues(state.words);
	return cues
		.map((cue, index) => [
			String(index + 1),
			`${secondsToSrt(cue.start)} --> ${secondsToSrt(cue.end)}`,
			cue.text,
			"",
		].join("\n"))
		.join("\n");
}

function downloadText(filename, content, type) {
	const blob = new Blob([content], { type });
	const url = URL.createObjectURL(blob);
	const link = document.createElement("a");
	link.href = url;
	link.download = filename;
	document.body.append(link);
	link.click();
	link.remove();
	URL.revokeObjectURL(url);
}

function handleExport(kind) {
	if (!state.words.length) {
		return;
	}

	const stem = (state.file?.name || "dialogue").replace(/\.[^.]+$/, "");
	if (kind === "json") {
		downloadText(`${stem}-timing.json`, JSON.stringify(exportKineticJson(), null, 2), "application/json");
	}
	if (kind === "csv") {
		downloadText(`${stem}-timing.csv`, exportCsv(), "text/csv");
	}
	if (kind === "vtt") {
		downloadText(`${stem}.vtt`, exportVtt(), "text/vtt");
	}
	if (kind === "srt") {
		downloadText(`${stem}.srt`, exportSrt(), "application/x-subrip");
	}
}

function nudgeSelected(amount) {
	if (state.selectedIndex < 0) {
		return;
	}

	const word = state.words[state.selectedIndex];
	word.start += amount;
	word.end += amount;
	clampWord(word);
	renderAll(false);
	selectWord(state.selectedIndex, false);
}

function borrowFromAdjacent(direction, amountSeconds) {
	const index = state.selectedIndex;
	const selected = state.words[index];
	if (!selected) {
		setStatus("Select a word before borrowing timing.", "warning");
		return;
	}

	if (direction === "prev") {
		const previous = state.words[index - 1];
		if (!previous) {
			setStatus("There is no previous word to borrow timing from.", "warning");
			return;
		}

		const available = Math.max(0, previous.end - previous.start - MIN_WORD_DURATION_SECONDS);
		const requested = Math.max(0, amountSeconds);
		const actual = Math.min(requested, available, selected.start);
		if (actual <= 0) {
			setStatus(`"${previous.word}" is already at the minimum timing.`, "warning");
			return;
		}

		previous.end -= actual;
		selected.start -= actual;
		clampWord(previous);
		clampWord(selected);
		renderAll(false);
		selectWord(index, false);
		setStatus(`Added ${Math.round(actual * 1000)} ms to "${selected.word}" from "${previous.word}".`);
		return;
	}

	if (direction === "next") {
		const next = state.words[index + 1];
		if (!next) {
			setStatus("There is no next word to borrow timing from.", "warning");
			return;
		}

		const available = Math.max(0, next.end - next.start - MIN_WORD_DURATION_SECONDS);
		const requested = Math.max(0, amountSeconds);
		const actual = Math.min(requested, available);
		if (actual <= 0) {
			setStatus(`"${next.word}" is already at the minimum timing.`, "warning");
			return;
		}

		selected.end += actual;
		next.start += actual;
		clampWord(selected);
		clampWord(next);
		renderAll(false);
		selectWord(index, false);
		setStatus(`Added ${Math.round(actual * 1000)} ms to "${selected.word}" from "${next.word}".`);
	}
}

function resetTool() {
	if (state.audioUrl) {
		URL.revokeObjectURL(state.audioUrl);
	}

	state.file = null;
	state.audioUrl = "";
	state.audioBuffer = null;
	state.duration = 0;
	state.result = null;
	state.words = [];
	state.segments = [];
	state.activeIndex = -1;
	state.selectedIndex = -1;
	stopPlaybackLoop();

	els.audioInput.value = "";
	els.jsonInput.value = "";
	els.audioPlayer.removeAttribute("src");
	els.audioPlayer.load();
	els.fileMeta.textContent = "mp3, m4a, wav, webm, mp4";
	els.transcribeButton.disabled = true;
	updatePlayButton();
	setStatus("Waiting for an audio clip.");
	renderAll();
}

els.audioInput.addEventListener("change", () => {
	loadAudioFile(els.audioInput.files?.[0]);
});

els.dropZone.addEventListener("dragover", (event) => {
	event.preventDefault();
	els.dropZone.classList.add("dragging");
});

els.dropZone.addEventListener("dragleave", () => {
	els.dropZone.classList.remove("dragging");
});

els.dropZone.addEventListener("drop", (event) => {
	event.preventDefault();
	els.dropZone.classList.remove("dragging");
	const file = event.dataTransfer?.files?.[0];
	if (file) {
		loadAudioFile(file);
	}
});

els.transcribeButton.addEventListener("click", transcribe);
els.playPauseButton.addEventListener("click", () => {
	togglePlayback().catch((error) => setStatus(`Playback failed: ${error.message}`, "error"));
});
els.sidebarToggleButton.addEventListener("click", () => {
	setSidebarCollapsed(!state.sidebarCollapsed);
});
els.clearButton.addEventListener("click", resetTool);
els.importButton.addEventListener("click", () => els.jsonInput.click());
els.jsonInput.addEventListener("change", () => importJson(els.jsonInput.files?.[0]));
els.fpsInput.addEventListener("change", () => renderAll(false));
els.audioPlayer.addEventListener("timeupdate", updateActiveWord);
els.audioPlayer.addEventListener("play", () => {
	updatePlayButton();
	startPlaybackLoop();
});
els.audioPlayer.addEventListener("pause", () => {
	updatePlayButton();
	stopPlaybackLoop();
});
els.audioPlayer.addEventListener("ended", () => {
	updatePlayButton();
	stopPlaybackLoop();
});
els.audioPlayer.addEventListener("seeked", updateActiveWord);
els.audioPlayer.addEventListener("loadedmetadata", () => {
	state.duration = Math.max(state.duration, els.audioPlayer.duration || 0);
	els.durationReadout.textContent = secondsToClock(state.duration);
	updatePlayButton();
	drawWaveform();
});

els.waveformCanvas.addEventListener("click", (event) => {
	const duration = getDuration();
	if (!duration) {
		return;
	}
	const rect = els.waveformCanvas.getBoundingClientRect();
	const percent = Math.min(1, Math.max(0, (event.clientX - rect.left) / rect.width));
	els.audioPlayer.currentTime = percent * duration;
	updateActiveWord();
});

for (const button of els.exportButtons) {
	button.addEventListener("click", () => handleExport(button.dataset.export));
}

for (const button of els.nudgeButtons) {
	button.addEventListener("click", () => nudgeSelected(Number(button.dataset.nudge)));
}

for (const button of els.borrowButtons) {
	button.addEventListener("click", () => {
		borrowFromAdjacent(button.dataset.borrow, Number(button.dataset.borrowMs) / 1000);
	});
}

window.addEventListener("resize", drawWaveform);

setSidebarCollapsed(readStoredSidebarState());
renderAll();
