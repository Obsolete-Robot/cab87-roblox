"""Animation compatibility helpers for Blender action API versions."""

from __future__ import annotations


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
