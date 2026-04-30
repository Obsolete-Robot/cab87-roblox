import importlib.util
from pathlib import Path
import sys
import unittest


LAYOUT_PATH = Path(__file__).resolve().parents[1] / "cab87_kinetic_text_importer" / "layout.py"
SPEC = importlib.util.spec_from_file_location("cab87_kinetic_layout", LAYOUT_PATH)
layout = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = layout
SPEC.loader.exec_module(layout)


class LayoutTests(unittest.TestCase):
	def test_parses_exported_kinetic_json_shape(self):
		document = layout.parse_timing_payload(
			{
				"schema": "cab87-dialogue-timing",
				"version": 1,
				"fps": 30,
				"duration": 2.0,
				"text": "cab time",
				"words": [
					{"index": 1, "text": "cab", "start": 0.1, "end": 0.4},
					{"index": 2, "text": "time", "start": 0.5, "end": 0.8},
				],
			}
		)

		self.assertEqual(document.schema, "cab87-dialogue-timing")
		self.assertEqual(document.version, 1)
		self.assertEqual(document.fps, 30)
		self.assertEqual([word.text for word in document.words], ["cab", "time"])
		self.assertEqual(document.duration, 2.0)

	def test_supports_simple_word_fallback_shape(self):
		document = layout.parse_timing_payload(
			{
				"words": [
					{"word": "later", "start": 1.0, "end": 1.2},
					{"word": "first", "start": 0.2, "end": 0.4},
					{"word": " ", "start": 0.5, "end": 0.6},
				]
			}
		)

		self.assertEqual([word.text for word in document.words], ["first", "later"])
		self.assertEqual([word.source_index for word in document.words], [0, 1])

	def test_splits_sections_by_word_and_character_limits(self):
		payload = {
			"words": [
				{"text": "one", "start": 0.0, "end": 0.1},
				{"text": "two", "start": 0.2, "end": 0.3},
				{"text": "three", "start": 0.4, "end": 0.5},
				{"text": "four", "start": 0.6, "end": 0.7},
			]
		}

		result = layout.build_layout(payload, layout.LayoutOptions(max_words_per_section=2, max_chars_per_section=20))
		self.assertEqual([section.text for section in result.sections], ["one two", "three four"])

		result = layout.build_layout(payload, layout.LayoutOptions(max_words_per_section=10, max_chars_per_section=9))
		self.assertEqual([section.text for section in result.sections], ["one two", "three", "four"])

	def test_wraps_lines_by_character_limit(self):
		payload = {
			"words": [
				{"text": "quick", "start": 0.0, "end": 0.1},
				{"text": "cab", "start": 0.2, "end": 0.3},
				{"text": "dispatch", "start": 0.4, "end": 0.5},
			]
		}

		result = layout.build_layout(
			payload,
			layout.LayoutOptions(max_words_per_section=10, max_chars_per_section=80, max_chars_per_line=9),
		)

		self.assertEqual([word.line_index for word in result.words], [0, 0, 1])
		self.assertGreater(result.words[0].y, result.words[-1].y)

	def test_left_and_right_alignment_shift_line_positions(self):
		payload = {"words": [{"text": "cab", "start": 0.0, "end": 0.1}]}

		left = layout.build_layout(payload, layout.LayoutOptions(horizontal_alignment="LEFT"))
		center = layout.build_layout(payload, layout.LayoutOptions(horizontal_alignment="CENTER"))
		right = layout.build_layout(payload, layout.LayoutOptions(horizontal_alignment="RIGHT"))

		self.assertGreater(left.words[0].x, center.words[0].x)
		self.assertGreater(center.words[0].x, right.words[0].x)


if __name__ == "__main__":
	unittest.main()
