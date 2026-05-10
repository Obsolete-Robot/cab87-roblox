from __future__ import annotations

from dataclasses import dataclass
import aifc
import math
from pathlib import Path
import wave


SUPPORTED_EXTENSIONS = {".wav", ".aif", ".aiff", ".aifc"}


class AudioDecodeError(RuntimeError):
	pass


@dataclass(frozen=True)
class AudioData:
	samples: list[float]
	sample_rate: int


@dataclass(frozen=True)
class BeatHit:
	time_seconds: float
	strength: float
	energy: float


def load_audio_mono(filepath: str) -> AudioData:
	path = Path(filepath)
	suffix = path.suffix.lower()
	if suffix == ".wav":
		return _load_wave_mono(path)
	if suffix in {".aif", ".aiff", ".aifc"}:
		return _load_aiff_mono(path)
	raise AudioDecodeError(f"Unsupported analysis format: {suffix or 'unknown'}. Use WAV/AIFF or enable FFmpeg conversion.")


def detect_bass_beats(
	samples: list[float],
	sample_rate: int,
	*,
	lowpass_hz: float = 160.0,
	window_ms: float = 45.0,
	hop_ms: float = 10.0,
	sensitivity: float = 1.35,
	major_percentile: float = 65.0,
	min_gap_ms: float = 220.0,
	max_beats: int = 0,
) -> list[BeatHit]:
	if sample_rate <= 0:
		raise ValueError("sample_rate must be positive.")
	if not samples:
		return []

	lowpassed_energy = _lowpass_energy(samples, sample_rate, lowpass_hz)
	window_size = max(8, int(sample_rate * window_ms / 1000.0))
	hop_size = max(1, int(sample_rate * hop_ms / 1000.0))
	energies = _windowed_average(lowpassed_energy, window_size, hop_size)
	if len(energies) < 3:
		return []

	local_means = _running_mean(energies, max(3, int(0.8 / (hop_ms / 1000.0))))
	peak_radius = max(1, int(0.055 / (hop_ms / 1000.0)))
	rise_frames = max(1, int(0.08 / (hop_ms / 1000.0)))

	candidates: list[BeatHit] = []
	for index in range(1, len(energies) - 1):
		energy = energies[index]
		if energy <= 0.0:
			continue
		if not _is_local_peak(energies, index, peak_radius):
			continue

		floor = max(local_means[index], 1.0e-12)
		relative_energy = energy / floor
		if relative_energy < sensitivity:
			continue

		start = max(0, index - rise_frames)
		pre_peak_floor = min(energies[start:index] or [0.0])
		rise_strength = max(0.0, energy - pre_peak_floor) / floor
		if rise_strength < 0.18:
			continue

		score = relative_energy + rise_strength
		time_seconds = index * hop_size / sample_rate
		candidates.append(BeatHit(time_seconds=time_seconds, strength=score, energy=energy))

	if not candidates:
		return []

	major_threshold = _percentile([candidate.strength for candidate in candidates], major_percentile)
	major_candidates = [candidate for candidate in candidates if candidate.strength >= major_threshold]
	thinned = _thin_peaks_by_cooldown(major_candidates, min_gap_ms / 1000.0)
	if max_beats > 0:
		thinned = sorted(thinned, key=lambda hit: hit.strength, reverse=True)[:max_beats]
		thinned.sort(key=lambda hit: hit.time_seconds)
	return thinned


def _load_wave_mono(path: Path) -> AudioData:
	try:
		with wave.open(str(path), "rb") as reader:
			channel_count = reader.getnchannels()
			sample_width = reader.getsampwidth()
			sample_rate = reader.getframerate()
			compression = reader.getcomptype()
			if compression != "NONE":
				raise AudioDecodeError(f"Unsupported WAV compression: {compression}. Convert the stem to PCM WAV.")
			raw = reader.readframes(reader.getnframes())
	except wave.Error as error:
		raise AudioDecodeError(f"Could not read WAV file: {error}") from error

	return AudioData(
		samples=_decode_pcm_to_mono(raw, channel_count, sample_width, "little", unsigned_8=True),
		sample_rate=sample_rate,
	)


def _load_aiff_mono(path: Path) -> AudioData:
	try:
		with aifc.open(str(path), "rb") as reader:
			channel_count = reader.getnchannels()
			sample_width = reader.getsampwidth()
			sample_rate = reader.getframerate()
			compression = reader.getcomptype()
			if compression not in {b"NONE", "NONE"}:
				raise AudioDecodeError(f"Unsupported AIFF compression: {compression!r}. Convert the stem to PCM WAV.")
			raw = reader.readframes(reader.getnframes())
	except (aifc.Error, EOFError) as error:
		raise AudioDecodeError(f"Could not read AIFF file: {error}") from error

	return AudioData(
		samples=_decode_pcm_to_mono(raw, channel_count, sample_width, "big", unsigned_8=False),
		sample_rate=sample_rate,
	)


def _decode_pcm_to_mono(raw: bytes, channel_count: int, sample_width: int, byteorder: str, *, unsigned_8: bool) -> list[float]:
	if channel_count <= 0:
		raise AudioDecodeError("Audio file has no channels.")
	if sample_width not in {1, 2, 3, 4}:
		raise AudioDecodeError(f"Unsupported sample width: {sample_width} bytes.")

	frame_width = channel_count * sample_width
	if frame_width <= 0:
		raise AudioDecodeError("Invalid audio frame width.")

	frame_count = len(raw) // frame_width
	samples: list[float] = []
	samples_extend = samples.append
	for frame_index in range(frame_count):
		frame_offset = frame_index * frame_width
		total = 0.0
		for channel_index in range(channel_count):
			offset = frame_offset + channel_index * sample_width
			total += _decode_pcm_sample(raw[offset : offset + sample_width], sample_width, byteorder, unsigned_8)
		samples_extend(total / channel_count)
	return samples


def _decode_pcm_sample(data: bytes, sample_width: int, byteorder: str, unsigned_8: bool) -> float:
	if sample_width == 1:
		if unsigned_8:
			return (data[0] - 128) / 128.0
		value = data[0] - 256 if data[0] >= 128 else data[0]
		return value / 128.0

	value = int.from_bytes(data, byteorder=byteorder, signed=True)
	scale = float(1 << (sample_width * 8 - 1))
	return max(-1.0, min(1.0, value / scale))


def _lowpass_energy(samples: list[float], sample_rate: int, lowpass_hz: float) -> list[float]:
	if lowpass_hz <= 0.0:
		return [sample * sample for sample in samples]

	nyquist = sample_rate * 0.5
	cutoff = min(max(10.0, lowpass_hz), nyquist * 0.95)
	rc = 1.0 / (2.0 * math.pi * cutoff)
	dt = 1.0 / sample_rate
	alpha = dt / (rc + dt)

	value = 0.0
	energy: list[float] = []
	append = energy.append
	for sample in samples:
		value += alpha * (sample - value)
		append(value * value)
	return energy


def _windowed_average(values: list[float], window_size: int, hop_size: int) -> list[float]:
	if len(values) < window_size:
		return [sum(values) / max(1, len(values))]

	prefix = [0.0]
	total = 0.0
	for value in values:
		total += value
		prefix.append(total)

	averages: list[float] = []
	for start in range(0, len(values) - window_size + 1, hop_size):
		end = start + window_size
		averages.append((prefix[end] - prefix[start]) / window_size)
	return averages


def _running_mean(values: list[float], window_size: int) -> list[float]:
	if not values:
		return []
	half_window = max(1, window_size // 2)
	prefix = [0.0]
	total = 0.0
	for value in values:
		total += value
		prefix.append(total)

	means: list[float] = []
	for index in range(len(values)):
		start = max(0, index - half_window)
		end = min(len(values), index + half_window + 1)
		means.append((prefix[end] - prefix[start]) / max(1, end - start))
	return means


def _is_local_peak(values: list[float], index: int, radius: int) -> bool:
	value = values[index]
	start = max(0, index - radius)
	end = min(len(values), index + radius + 1)
	for other_index in range(start, end):
		if other_index != index and values[other_index] > value:
			return False
	return True


def _percentile(values: list[float], percentile: float) -> float:
	if not values:
		return 0.0
	ordered = sorted(values)
	clamped = min(100.0, max(0.0, percentile))
	position = (len(ordered) - 1) * (clamped / 100.0)
	lower = int(math.floor(position))
	upper = int(math.ceil(position))
	if lower == upper:
		return ordered[lower]
	fraction = position - lower
	return ordered[lower] * (1.0 - fraction) + ordered[upper] * fraction


def _thin_peaks_by_cooldown(candidates: list[BeatHit], min_gap_seconds: float) -> list[BeatHit]:
	if min_gap_seconds <= 0.0:
		return sorted(candidates, key=lambda hit: hit.time_seconds)

	accepted: list[BeatHit] = []
	for candidate in sorted(candidates, key=lambda hit: hit.strength, reverse=True):
		if all(abs(candidate.time_seconds - hit.time_seconds) >= min_gap_seconds for hit in accepted):
			accepted.append(candidate)
	accepted.sort(key=lambda hit: hit.time_seconds)
	return accepted
