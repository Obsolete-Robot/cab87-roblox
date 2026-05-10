import math
import importlib.util
from pathlib import Path
import sys
import unittest

MODULE_PATH = Path(__file__).resolve().parents[1] / "cab87_beat_maker" / "audio_analysis.py"
spec = importlib.util.spec_from_file_location("cab87_beat_maker_audio_analysis", MODULE_PATH)
audio_analysis = importlib.util.module_from_spec(spec)
assert spec.loader is not None
sys.modules[spec.name] = audio_analysis
spec.loader.exec_module(audio_analysis)

detect_bass_beats = audio_analysis.detect_bass_beats


def synth_kicks(sample_rate: int, duration: float, beat_times: list[float]) -> list[float]:
	sample_count = int(sample_rate * duration)
	samples = [0.0] * sample_count
	for beat_time in beat_times:
		start = int(beat_time * sample_rate)
		length = int(0.12 * sample_rate)
		for offset in range(length):
			index = start + offset
			if index >= sample_count:
				break
			age = offset / sample_rate
			envelope = math.exp(-age * 35.0)
			samples[index] += math.sin(2.0 * math.pi * 65.0 * age) * envelope
	return samples


class BeatDetectionTests(unittest.TestCase):
	def test_detects_major_synthetic_kicks(self):
		sample_rate = 4000
		beat_times = [0.5, 1.0, 1.5, 2.0]
		samples = synth_kicks(sample_rate, 2.5, beat_times)

		hits = detect_bass_beats(
			samples,
			sample_rate,
			lowpass_hz=180.0,
			window_ms=35.0,
			hop_ms=5.0,
			sensitivity=1.15,
			major_percentile=0.0,
			min_gap_ms=250.0,
		)

		self.assertEqual(len(hits), len(beat_times))
		for hit, expected_time in zip(hits, beat_times):
			self.assertAlmostEqual(hit.time_seconds, expected_time, delta=0.04)

	def test_major_percentile_filters_weaker_hits(self):
		sample_rate = 4000
		samples = synth_kicks(sample_rate, 2.5, [0.5, 1.0, 1.5, 2.0])
		for index in range(int(1.5 * sample_rate), int(1.62 * sample_rate)):
			samples[index] *= 0.18

		hits = detect_bass_beats(
			samples,
			sample_rate,
			lowpass_hz=180.0,
			window_ms=35.0,
			hop_ms=5.0,
			sensitivity=1.05,
			major_percentile=25.0,
			min_gap_ms=250.0,
		)

		self.assertEqual(len(hits), 3)
		self.assertTrue(all(abs(hit.time_seconds - 1.5) > 0.08 for hit in hits))


if __name__ == "__main__":
	unittest.main()
