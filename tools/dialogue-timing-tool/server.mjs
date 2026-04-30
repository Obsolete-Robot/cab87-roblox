import { createServer } from "node:http";
import { readFile, stat } from "node:fs/promises";
import { dirname, extname, join, normalize } from "node:path";
import { Readable } from "node:stream";
import { fileURLToPath } from "node:url";

const ROOT = dirname(fileURLToPath(import.meta.url));
const PORT = Number(process.env.PORT || 8011);
const HOST = process.env.HOST || "127.0.0.1";
const MAX_AUDIO_BYTES = Number(process.env.MAX_AUDIO_BYTES || 25 * 1024 * 1024);
const OPENAI_TRANSCRIPTION_URL = "https://api.openai.com/v1/audio/transcriptions";

const MIME_TYPES = {
	".html": "text/html; charset=utf-8",
	".css": "text/css; charset=utf-8",
	".js": "text/javascript; charset=utf-8",
	".json": "application/json; charset=utf-8",
	".svg": "image/svg+xml",
	".png": "image/png",
	".jpg": "image/jpeg",
	".jpeg": "image/jpeg",
	".webp": "image/webp",
	".ico": "image/x-icon",
};

function sendJson(res, status, payload) {
	const body = JSON.stringify(payload);
	res.writeHead(status, {
		"Content-Type": "application/json; charset=utf-8",
		"Content-Length": Buffer.byteLength(body),
		"Cache-Control": "no-store",
	});
	res.end(body);
}

function sendText(res, status, text) {
	res.writeHead(status, {
		"Content-Type": "text/plain; charset=utf-8",
		"Content-Length": Buffer.byteLength(text),
		"Cache-Control": "no-store",
	});
	res.end(text);
}

function safeNumber(value, fallback = 0) {
	const number = Number(value);
	return Number.isFinite(number) ? number : fallback;
}

function cleanWord(value) {
	return String(value ?? "").replace(/\s+/g, " ").trim();
}

function normalizeWords(words) {
	if (!Array.isArray(words)) {
		return [];
	}

	return words
		.map((word, index) => {
			const start = Math.max(0, safeNumber(word.start));
			const end = Math.max(start, safeNumber(word.end, start));
			return {
				id: index + 1,
				word: cleanWord(word.word ?? word.text),
				start,
				end,
				startMs: Math.round(start * 1000),
				endMs: Math.round(end * 1000),
			};
		})
		.filter((word) => word.word.length > 0);
}

function normalizeSegments(segments) {
	if (!Array.isArray(segments)) {
		return [];
	}

	return segments
		.map((segment, index) => {
			const start = Math.max(0, safeNumber(segment.start));
			const end = Math.max(start, safeNumber(segment.end, start));
			return {
				id: segment.id ?? index + 1,
				text: cleanWord(segment.text),
				start,
				end,
				startMs: Math.round(start * 1000),
				endMs: Math.round(end * 1000),
			};
		})
		.filter((segment) => segment.text.length > 0);
}

function normalizeTranscription(raw, model) {
	const words = normalizeWords(raw.words);
	const segments = normalizeSegments(raw.segments);
	const finalWordEnd = words.reduce((max, word) => Math.max(max, word.end), 0);
	const finalSegmentEnd = segments.reduce((max, segment) => Math.max(max, segment.end), 0);
	const duration = Math.max(safeNumber(raw.duration), finalWordEnd, finalSegmentEnd);

	return {
		provider: "openai",
		model,
		text: cleanWord(raw.text),
		duration,
		words,
		segments,
		raw,
	};
}

async function requestFormData(req) {
	const origin = `http://${req.headers.host || `${HOST}:${PORT}`}`;
	const headers = new Headers();
	for (const [key, value] of Object.entries(req.headers)) {
		if (Array.isArray(value)) {
			for (const entry of value) {
				headers.append(key, entry);
			}
		} else if (value !== undefined) {
			headers.set(key, value);
		}
	}

	const request = new Request(`${origin}${req.url}`, {
		method: req.method,
		headers,
		body: Readable.toWeb(req),
		duplex: "half",
	});

	return request.formData();
}

function formString(form, key) {
	const value = form.get(key);
	return typeof value === "string" ? value.trim() : "";
}

function isUpload(value) {
	return value && typeof value !== "string" && typeof value.arrayBuffer === "function";
}

async function handleTranscribe(req, res) {
	const apiKey = process.env.OPENAI_API_KEY;
	if (!apiKey) {
		sendJson(res, 500, {
			error: "Missing OPENAI_API_KEY. Start this tool from a shell where OPENAI_API_KEY is set.",
		});
		return;
	}

	const contentLength = Number(req.headers["content-length"] || 0);
	if (contentLength > MAX_AUDIO_BYTES + 1024 * 1024) {
		sendJson(res, 413, {
			error: `Upload is too large. Max audio size is ${Math.round(MAX_AUDIO_BYTES / 1024 / 1024)} MB.`,
		});
		return;
	}

	let form;
	try {
		form = await requestFormData(req);
	} catch (error) {
		sendJson(res, 400, { error: `Could not read upload form: ${error.message}` });
		return;
	}

	const audio = form.get("audio");
	if (!isUpload(audio)) {
		sendJson(res, 400, { error: "Upload an audio or video file before transcribing." });
		return;
	}

	if (audio.size > MAX_AUDIO_BYTES) {
		sendJson(res, 413, {
			error: `Audio file is too large. Max size is ${Math.round(MAX_AUDIO_BYTES / 1024 / 1024)} MB.`,
		});
		return;
	}

	const model = "whisper-1";
	const language = formString(form, "language");
	const prompt = formString(form, "prompt");

	const outbound = new FormData();
	outbound.append("file", audio, audio.name || "dialogue-audio.webm");
	outbound.append("model", model);
	outbound.append("response_format", "verbose_json");
	outbound.append("timestamp_granularities[]", "word");
	outbound.append("timestamp_granularities[]", "segment");

	if (language) {
		outbound.append("language", language);
	}

	if (prompt) {
		outbound.append("prompt", prompt);
	}

	let response;
	try {
		response = await fetch(OPENAI_TRANSCRIPTION_URL, {
			method: "POST",
			headers: {
				Authorization: `Bearer ${apiKey}`,
			},
			body: outbound,
		});
	} catch (error) {
		sendJson(res, 502, { error: `Transcription request failed: ${error.message}` });
		return;
	}

	const responseText = await response.text();
	let payload;
	try {
		payload = JSON.parse(responseText);
	} catch {
		payload = { error: responseText };
	}

	if (!response.ok) {
		const message = payload?.error?.message || payload?.error || "Transcription failed.";
		sendJson(res, response.status, { error: message, details: payload });
		return;
	}

	const normalized = normalizeTranscription(payload, model);
	if (normalized.words.length === 0) {
		sendJson(res, 502, {
			error: "The transcription response did not include word timestamps.",
			details: normalized,
		});
		return;
	}

	sendJson(res, 200, normalized);
}

async function serveStatic(req, res) {
	const url = new URL(req.url, `http://${req.headers.host || `${HOST}:${PORT}`}`);
	const requestedPath = url.pathname === "/" ? "/index.html" : decodeURIComponent(url.pathname);
	const targetPath = normalize(join(ROOT, requestedPath.slice(1)));

	if (!targetPath.startsWith(ROOT)) {
		sendText(res, 403, "Forbidden");
		return;
	}

	try {
		const fileStat = await stat(targetPath);
		if (!fileStat.isFile()) {
			sendText(res, 404, "Not found");
			return;
		}

		const body = await readFile(targetPath);
		res.writeHead(200, {
			"Content-Type": MIME_TYPES[extname(targetPath)] || "application/octet-stream",
			"Content-Length": body.length,
			"Cache-Control": "no-store",
		});
		res.end(body);
	} catch {
		sendText(res, 404, "Not found");
	}
}

const server = createServer((req, res) => {
	if (req.method === "POST" && req.url?.startsWith("/api/transcribe")) {
		handleTranscribe(req, res);
		return;
	}

	if (req.method === "GET" || req.method === "HEAD") {
		serveStatic(req, res);
		return;
	}

	sendText(res, 405, "Method not allowed");
});

server.listen(PORT, HOST, () => {
	console.log(`[cab87] Dialogue Timing Tool running at http://${HOST}:${PORT}`);
	console.log("[cab87] Press Ctrl+C to stop.");
});
