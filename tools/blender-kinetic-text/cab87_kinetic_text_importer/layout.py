"""Pure layout helpers for Cab87 kinetic text timing files.

This module intentionally has no Blender dependency so sectioning, wrapping,
and timing import behavior can be tested from a normal Python interpreter.
"""

from __future__ import annotations

from dataclasses import dataclass
import json
from pathlib import Path
from typing import Any, Iterable


DEFAULT_MAX_WORDS_PER_SECTION = 8
DEFAULT_MAX_CHARS_PER_SECTION = 42
DEFAULT_MAX_CHARS_PER_LINE = 24
DEFAULT_WORD_SPACING = 0.28
DEFAULT_LINE_SPACING = 1.2
DEFAULT_CHARACTER_WIDTH = 0.58


@dataclass(frozen=True)
class TimingWord:
	source_index: int
	text: str
	start: float
	end: float
	break_after: bool = False


@dataclass(frozen=True)
class TimingDocument:
	schema: str | None
	version: int | None
	fps: float | None
	duration: float
	text: str
	words: tuple[TimingWord, ...]


@dataclass(frozen=True)
class LayoutOptions:
	max_words_per_section: int = DEFAULT_MAX_WORDS_PER_SECTION
	max_chars_per_section: int = DEFAULT_MAX_CHARS_PER_SECTION
	max_chars_per_line: int = DEFAULT_MAX_CHARS_PER_LINE
	word_spacing: float = DEFAULT_WORD_SPACING
	line_spacing: float = DEFAULT_LINE_SPACING
	character_width: float = DEFAULT_CHARACTER_WIDTH
	horizontal_alignment: str = "CENTER"


@dataclass(frozen=True)
class LayoutSection:
	index: int
	start: float
	end: float
	text: str
	word_source_indices: tuple[int, ...]


@dataclass(frozen=True)
class LayoutWord:
	source_index: int
	section_index: int
	line_index: int
	word_index_in_section: int
	text: str
	start: float
	end: float
	break_after: bool
	x: float
	y: float
	width: float


@dataclass(frozen=True)
class LayoutDocument:
	source: TimingDocument
	options: LayoutOptions
	sections: tuple[LayoutSection, ...]
	words: tuple[LayoutWord, ...]


def load_timing_file(path: str | Path) -> TimingDocument:
	with Path(path).open("r", encoding="utf-8") as file:
		return parse_timing_payload(json.load(file))


def parse_timing_payload(payload: dict[str, Any]) -> TimingDocument:
	if not isinstance(payload, dict):
		raise ValueError("Timing payload must be a JSON object.")

	source_words = payload.get("words")
	if not isinstance(source_words, list):
		source_words = payload.get("items")
	if not isinstance(source_words, list):
		source_words = []

	parsed_words: list[TimingWord] = []
	for raw_word in source_words:
		if not isinstance(raw_word, dict):
			continue

		text = _clean_text(raw_word.get("text", raw_word.get("word", "")))
		if not text:
			continue

		start = max(0.0, _read_number(raw_word, ("start", "startSeconds", "start_time", "startTime"), 0.0))
		end = _read_number(raw_word, ("end", "endSeconds", "end_time", "endTime"), start)
		end = max(start, end)
		break_after = _read_bool(
			raw_word,
			("breakAfter", "manualBreakAfter", "captionBreakAfter", "forceBreakAfter", "break_after"),
		)
		parsed_words.append(TimingWord(source_index=-1, text=text, start=start, end=end, break_after=break_after))

	parsed_words.sort(key=lambda word: (word.start, word.end, word.text))
	indexed_words = tuple(
		TimingWord(
			source_index=index,
			text=word.text,
			start=word.start,
			end=word.end,
			break_after=word.break_after and index < len(parsed_words) - 1,
		)
		for index, word in enumerate(parsed_words)
	)

	duration = max(
		_read_float(payload.get("duration"), 0.0),
		max((word.end for word in indexed_words), default=0.0),
	)
	return TimingDocument(
		schema=_clean_optional_text(payload.get("schema")),
		version=_read_int(payload.get("version")),
		fps=_read_optional_float(payload.get("fps")),
		duration=duration,
		text=_clean_text(payload.get("text", " ".join(word.text for word in indexed_words))),
		words=indexed_words,
	)


def build_layout(payload_or_document: dict[str, Any] | TimingDocument, options: LayoutOptions | None = None) -> LayoutDocument:
	document = payload_or_document if isinstance(payload_or_document, TimingDocument) else parse_timing_payload(payload_or_document)
	active_options = sanitize_options(options or LayoutOptions())
	section_words = _split_into_sections(document.words, active_options)

	sections: list[LayoutSection] = []
	layout_words: list[LayoutWord] = []
	for section_index, words in enumerate(section_words):
		if not words:
			continue
		sections.append(
			LayoutSection(
				index=section_index,
				start=words[0].start,
				end=max(word.end for word in words),
				text=" ".join(word.text for word in words),
				word_source_indices=tuple(word.source_index for word in words),
			)
		)
		layout_words.extend(_layout_section_words(section_index, words, active_options))

	return LayoutDocument(
		source=document,
		options=active_options,
		sections=tuple(sections),
		words=tuple(layout_words),
	)


def sanitize_options(options: LayoutOptions) -> LayoutOptions:
	alignment = (options.horizontal_alignment or "CENTER").upper()
	if alignment not in {"LEFT", "CENTER", "RIGHT"}:
		alignment = "CENTER"

	return LayoutOptions(
		max_words_per_section=max(1, int(options.max_words_per_section or DEFAULT_MAX_WORDS_PER_SECTION)),
		max_chars_per_section=max(1, int(options.max_chars_per_section or DEFAULT_MAX_CHARS_PER_SECTION)),
		max_chars_per_line=max(1, int(options.max_chars_per_line or DEFAULT_MAX_CHARS_PER_LINE)),
		word_spacing=max(0.0, float(options.word_spacing)),
		line_spacing=max(0.1, float(options.line_spacing)),
		character_width=max(0.05, float(options.character_width)),
		horizontal_alignment=alignment,
	)


def _split_into_sections(words: Iterable[TimingWord], options: LayoutOptions) -> list[list[TimingWord]]:
	sections: list[list[TimingWord]] = []
	current: list[TimingWord] = []

	for word in words:
		current.append(word)

		if word.break_after and current:
			sections.append(current)
			current = []

	if current:
		sections.append(current)

	return sections


def _layout_section_words(section_index: int, words: list[TimingWord], options: LayoutOptions) -> list[LayoutWord]:
	lines = _wrap_lines(words, options.max_chars_per_line)
	if not lines:
		return []

	layout_words: list[LayoutWord] = []
	line_count = len(lines)
	word_index_in_section = 0
	for line_index, line_words in enumerate(lines):
		widths = [_word_width(word.text, options.character_width) for word in line_words]
		line_width = sum(widths) + options.word_spacing * max(0, len(line_words) - 1)
		cursor = _line_left_edge(line_width, options.horizontal_alignment)
		y = ((line_count - 1) * options.line_spacing * 0.5) - (line_index * options.line_spacing)

		for word, width in zip(line_words, widths):
			x = cursor + width * 0.5
			layout_words.append(
				LayoutWord(
					source_index=word.source_index,
					section_index=section_index,
					line_index=line_index,
					word_index_in_section=word_index_in_section,
					text=word.text,
					start=word.start,
					end=word.end,
					break_after=word.break_after,
					x=x,
					y=y,
					width=width,
				)
			)
			cursor += width + options.word_spacing
			word_index_in_section += 1

	return layout_words


def _wrap_lines(words: list[TimingWord], max_chars_per_line: int) -> list[list[TimingWord]]:
	lines: list[list[TimingWord]] = []
	current: list[TimingWord] = []

	for word in words:
		candidate = [*current, word]
		if current and _joined_length(candidate) > max_chars_per_line:
			lines.append(current)
			current = [word]
		else:
			current = candidate

	if current:
		lines.append(current)

	return lines


def _line_left_edge(line_width: float, alignment: str) -> float:
	if alignment == "LEFT":
		return 0.0
	if alignment == "RIGHT":
		return -line_width
	return -line_width * 0.5


def _joined_length(words: Iterable[TimingWord]) -> int:
	return len(" ".join(word.text for word in words))


def _word_width(text: str, character_width: float) -> float:
	return max(character_width, len(text) * character_width)


def _clean_text(value: Any) -> str:
	return " ".join(str(value or "").split())


def _clean_optional_text(value: Any) -> str | None:
	text = _clean_text(value)
	return text or None


def _read_number(payload: dict[str, Any], keys: tuple[str, ...], fallback: float) -> float:
	for key in keys:
		if key in payload:
			return _read_float(payload.get(key), fallback)
	return fallback


def _read_bool(payload: dict[str, Any], keys: tuple[str, ...]) -> bool:
	for key in keys:
		if key not in payload:
			continue
		value = payload.get(key)
		if isinstance(value, bool):
			return value
		if isinstance(value, str):
			return value.strip().lower() in {"1", "true", "yes", "on"}
		return bool(value)
	return False


def _read_float(value: Any, fallback: float) -> float:
	try:
		number = float(value)
	except (TypeError, ValueError):
		return fallback
	return number if number == number else fallback


def _read_optional_float(value: Any) -> float | None:
	number = _read_float(value, float("nan"))
	return None if number != number else number


def _read_int(value: Any) -> int | None:
	try:
		return int(value)
	except (TypeError, ValueError):
		return None
