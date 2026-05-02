import importlib.util
from pathlib import Path
from types import SimpleNamespace
import sys
import unittest


ANIMATION_PATH = Path(__file__).resolve().parents[1] / "cab87_kinetic_text_importer" / "animation.py"
SPEC = importlib.util.spec_from_file_location("cab87_kinetic_animation", ANIMATION_PATH)
animation = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = animation
SPEC.loader.exec_module(animation)


class ActionWithoutLegacyFcurves:
	def __init__(self, layers):
		self.layers = layers


class AnimationTests(unittest.TestCase):
	def test_sets_legacy_action_fcurve_interpolation(self):
		keyframe = SimpleNamespace(interpolation="BEZIER")
		fcurve = SimpleNamespace(keyframe_points=[keyframe])
		action = SimpleNamespace(fcurves=[fcurve])
		owner = SimpleNamespace(animation_data=SimpleNamespace(action=action, action_slot=None))

		animation.set_fcurve_interpolation(owner, "LINEAR")

		self.assertEqual(keyframe.interpolation, "LINEAR")

	def test_sets_slotted_action_fcurve_interpolation(self):
		slot = SimpleNamespace(handle=7)
		keyframe = SimpleNamespace(interpolation="BEZIER")
		matching_fcurve = SimpleNamespace(keyframe_points=[keyframe])
		matching_bag = SimpleNamespace(slot=slot, slot_handle=7, fcurves=[matching_fcurve])
		other_keyframe = SimpleNamespace(interpolation="BEZIER")
		other_bag = SimpleNamespace(
			slot=SimpleNamespace(handle=8),
			slot_handle=8,
			fcurves=[SimpleNamespace(keyframe_points=[other_keyframe])],
		)
		strip = SimpleNamespace(channelbags=[other_bag, matching_bag])
		action = ActionWithoutLegacyFcurves(layers=[SimpleNamespace(strips=[strip])])
		owner = SimpleNamespace(animation_data=SimpleNamespace(action=action, action_slot=slot))

		animation.set_fcurve_interpolation(owner, "LINEAR")

		self.assertEqual(keyframe.interpolation, "LINEAR")
		self.assertEqual(other_keyframe.interpolation, "BEZIER")

	def test_uses_keyframe_strip_channelbag_lookup_when_available(self):
		slot = SimpleNamespace(handle=7)
		keyframe = SimpleNamespace(interpolation="BEZIER")
		channelbag = SimpleNamespace(fcurves=[SimpleNamespace(keyframe_points=[keyframe])])

		class Strip:
			channelbags = []

			def __init__(self):
				self.requested_slot = None

			def channelbag(self, requested_slot):
				self.requested_slot = requested_slot
				return channelbag

		strip = Strip()
		action = ActionWithoutLegacyFcurves(layers=[SimpleNamespace(strips=[strip])])
		owner = SimpleNamespace(animation_data=SimpleNamespace(action=action, action_slot=slot))

		animation.set_fcurve_interpolation(owner, "LINEAR")

		self.assertIs(strip.requested_slot, slot)
		self.assertEqual(keyframe.interpolation, "LINEAR")

	def test_prefers_action_slot_over_legacy_proxy(self):
		slot = SimpleNamespace(handle=7)
		legacy_keyframe = SimpleNamespace(interpolation="BEZIER")
		slotted_keyframe = SimpleNamespace(interpolation="BEZIER")
		channelbag = SimpleNamespace(
			slot=slot,
			slot_handle=7,
			fcurves=[SimpleNamespace(keyframe_points=[slotted_keyframe])],
		)
		strip = SimpleNamespace(channelbags=[channelbag])
		action = SimpleNamespace(
			fcurves=[SimpleNamespace(keyframe_points=[legacy_keyframe])],
			layers=[SimpleNamespace(strips=[strip])],
		)
		owner = SimpleNamespace(animation_data=SimpleNamespace(action=action, action_slot=slot))

		animation.set_fcurve_interpolation(owner, "LINEAR")

		self.assertEqual(legacy_keyframe.interpolation, "BEZIER")
		self.assertEqual(slotted_keyframe.interpolation, "LINEAR")


if __name__ == "__main__":
	unittest.main()
