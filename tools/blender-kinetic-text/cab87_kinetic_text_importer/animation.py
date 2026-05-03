"""Animation compatibility helpers for Blender action API versions."""

from __future__ import annotations


def intro_keyframe_allowed(frame: int, outro_start_frame: int | None = None) -> bool:
	return outro_start_frame is None or frame < outro_start_frame


def section_clear_end_frame(next_section_start_frame: int, intro_frames: int, scene_start_frame: int) -> int:
	return max(int(scene_start_frame), int(next_section_start_frame) - max(0, int(intro_frames)))


def outro_frame_range(word_start_frame: int, clear_end_frame: int, clear_frames: int) -> tuple[int, int]:
	clear_end_frame = int(clear_end_frame)
	clear_start_frame = max(int(word_start_frame), clear_end_frame - max(0, int(clear_frames)))
	if clear_start_frame > clear_end_frame:
		clear_start_frame = clear_end_frame
	return clear_start_frame, clear_end_frame


def intro_scale_frame_plan(
	start_frame: int,
	overshoot_scale: float,
	overshoot_frames: int,
	settle_frames: int,
	outro_start_frame: int | None = None,
) -> tuple[tuple[int, str], ...]:
	overshoot_scale = max(1.0, float(overshoot_scale))
	overshoot_frames = max(0, int(overshoot_frames))
	settle_frames = max(0, int(settle_frames))
	frames: list[tuple[int, str]] = []

	def add_frame(frame: int, target: str) -> None:
		if intro_keyframe_allowed(frame, outro_start_frame):
			frames.append((frame, target))

	if overshoot_scale <= 1.0 or settle_frames <= 0:
		add_frame(start_frame, "full")
		return tuple(frames)

	overshoot_frame = start_frame + overshoot_frames
	settle_frame = overshoot_frame + settle_frames
	if overshoot_frame > start_frame:
		add_frame(start_frame, "full")
	add_frame(overshoot_frame, "overshoot")
	add_frame(settle_frame, "full")
	return tuple(frames)


def set_fcurve_interpolation(owner, interpolation: str) -> None:
	if not owner:
		return

	animation_data = getattr(owner, "animation_data", None)
	action = getattr(animation_data, "action", None) if animation_data else None
	if not action:
		return

	action_slot = getattr(animation_data, "action_slot", None)
	for fcurve in iter_action_fcurves(action, action_slot):
		for keyframe in fcurve.keyframe_points:
			keyframe.interpolation = interpolation


def iter_action_fcurves(action, action_slot=None):
	layers = getattr(action, "layers", None)
	if action_slot is not None and layers is not None:
		yield from iter_layered_action_fcurves(layers, action_slot)
		return

	legacy_fcurves = getattr(action, "fcurves", None)
	if legacy_fcurves is not None:
		for fcurve in legacy_fcurves:
			yield fcurve
		return

	if layers is not None:
		yield from iter_layered_action_fcurves(layers, action_slot)


def iter_layered_action_fcurves(layers, action_slot=None):
	for layer in layers or ():
		for strip in getattr(layer, "strips", ()) or ():
			for channelbag in iter_strip_channelbags(strip, action_slot):
				for fcurve in getattr(channelbag, "fcurves", ()) or ():
					yield fcurve


def iter_strip_channelbags(strip, action_slot=None):
	if action_slot is not None:
		channelbag_for_slot = getattr(strip, "channelbag", None)
		if callable(channelbag_for_slot):
			try:
				channelbag = channelbag_for_slot(action_slot)
			except (AttributeError, RuntimeError, TypeError, ValueError):
				channelbag = None
			if channelbag is not None:
				yield channelbag
				return

	for channelbag in getattr(strip, "channelbags", ()) or ():
		if channelbag_matches_slot(channelbag, action_slot):
			yield channelbag


def channelbag_matches_slot(channelbag, action_slot) -> bool:
	if action_slot is None:
		return True

	if getattr(channelbag, "slot", None) == action_slot:
		return True

	channelbag_slot_handle = getattr(channelbag, "slot_handle", None)
	action_slot_handle = getattr(action_slot, "handle", None)
	return action_slot_handle is not None and channelbag_slot_handle == action_slot_handle
