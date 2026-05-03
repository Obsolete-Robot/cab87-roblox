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
				"defaultColor": "#ffdb38",
				"customColors": ["#34a0ff", "f04a4a", "#ffdb38"],
				"text": "cab time",
				"words": [
					{"index": 1, "text": "cab", "start": 0.1, "end": 0.4, "breakAfter": True},
					{"index": 2, "text": "time", "start": 0.5, "end": 0.8, "color": "#34a0ff", "colorOverride": True},
				],
			}
		)

		self.assertEqual(document.schema, "cab87-dialogue-timing")
		self.assertEqual(document.version, 1)
		self.assertEqual(document.fps, 30)
		self.assertEqual(document.default_color, "#ffdb38")
		self.assertEqual([word.text for word in document.words], ["cab", "time"])
		self.assertEqual([word.break_after for word in document.words], [True, False])
		self.assertEqual([word.color for word in document.words], ["#ffdb38", "#34a0ff"])
		self.assertEqual([word.color_override for word in document.words], [False, True])
		self.assertEqual(document.color_swatches, ("#ffdb38", "#34a0ff", "#f04a4a"))
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

	def test_word_and_character_limits_do_not_create_sections(self):
		payload = {
			"words": [
				{"text": "one", "start": 0.0, "end": 0.1},
				{"text": "two", "start": 0.2, "end": 0.3},
				{"text": "three", "start": 0.4, "end": 0.5},
				{"text": "four", "start": 0.6, "end": 0.7},
			]
		}

		result = layout.build_layout(payload, layout.LayoutOptions(max_words_per_section=2, max_chars_per_section=20))
		self.assertEqual([section.text for section in result.sections], ["one two three four"])

		result = layout.build_layout(payload, layout.LayoutOptions(max_words_per_section=10, max_chars_per_section=9))
		self.assertEqual([section.text for section in result.sections], ["one two three four"])

	def test_break_after_forces_new_section_within_existing_limits(self):
		payload = {
			"words": [
				{"text": "one", "start": 0.0, "end": 0.1},
				{"text": "two", "start": 0.2, "end": 0.3, "breakAfter": True},
				{"text": "three", "start": 0.4, "end": 0.5},
				{"text": "four", "start": 0.6, "end": 0.7},
			]
		}

		result = layout.build_layout(payload, layout.LayoutOptions(max_words_per_section=10, max_chars_per_section=80))

		self.assertEqual([section.text for section in result.sections], ["one two", "three four"])
		self.assertEqual(result.words[1].break_after, True)
		self.assertEqual(result.words[2].section_index, 1)

	def test_break_after_is_the_only_section_boundary(self):
		payload = {
			"words": [
				{"text": "one", "start": 0.0, "end": 0.1, "breakAfter": True},
				{"text": "two", "start": 0.2, "end": 0.3},
				{"text": "three", "start": 0.4, "end": 0.5},
				{"text": "four", "start": 0.6, "end": 0.7},
			]
		}

		result = layout.build_layout(payload, layout.LayoutOptions(max_words_per_section=2, max_chars_per_section=80))
		self.assertEqual([section.text for section in result.sections], ["one", "two three four"])

		result = layout.build_layout(payload, layout.LayoutOptions(max_words_per_section=10, max_chars_per_section=8))
		self.assertEqual([section.text for section in result.sections], ["one", "two three four"])

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

	def test_vertical_alignment_offsets_line_positions(self):
		payload = {
			"words": [
				{"text": "one", "start": 0.0, "end": 0.1},
				{"text": "two", "start": 0.2, "end": 0.3},
				{"text": "tri", "start": 0.4, "end": 0.5},
			]
		}
		options = {
			"max_chars_per_line": 3,
			"line_spacing": 2.0,
		}

		top = layout.build_layout(payload, layout.LayoutOptions(vertical_alignment="TOP", **options))
		center = layout.build_layout(payload, layout.LayoutOptions(vertical_alignment="CENTER", **options))
		bottom = layout.build_layout(payload, layout.LayoutOptions(vertical_alignment="BOTTOM", **options))

		self.assertEqual([word.y for word in top.words], [0.0, -2.0, -4.0])
		self.assertEqual([word.y for word in center.words], [2.0, 0.0, -2.0])
		self.assertEqual([word.y for word in bottom.words], [4.0, 2.0, 0.0])


if __name__ == "__main__":
	unittest.main()
