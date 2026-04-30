"""Safe add-on version gate for Cab87 Kinetic Text Importer.

On register, this detects older installed copies of the same add-on family,
disables them, and purges stale modules from the current Blender interpreter.
It never deletes files from disk.
"""

from __future__ import annotations

import re
import sys

import bpy  # type: ignore[import-untyped]


_BASE_NAMES: tuple[str, ...] = (
	"Cab87 Kinetic Text Importer",
	"Cab87KineticTextImporter",
	"cab87_kinetic_text_importer",
)

_PATTERNS: list[re.Pattern[str]] = [
	re.compile(rf"^{re.escape(name)}(?:_\d+(?:_\d+)*)?$")
	for name in _BASE_NAMES
]


def _current_package() -> str:
	return __package__.split(".")[0] if __package__ else __name__.split(".")[0]


def _current_version() -> tuple[int, ...]:
	from .. import bl_info  # type: ignore[import-untyped]

	return tuple(bl_info["version"])


def _matches_identity(name: str) -> bool:
	return any(pattern.match(name) for pattern in _PATTERNS)


def _get_candidate_version(module) -> tuple[int, ...] | None:
	try:
		import addon_utils  # type: ignore[import-untyped]

		info = addon_utils.module_bl_info(module)
		version = info.get("version")
		if version is not None:
			return tuple(version)
	except Exception:
		pass

	bl_info = getattr(module, "bl_info", None)
	if isinstance(bl_info, dict):
		version = bl_info.get("version")
		if version is not None:
			return tuple(version)

	return None


def run_version_gate(
	persist: bool = True,
	save_prefs: bool = True,
	purge_modules: bool = True,
) -> list[str]:
	current_package = _current_package()

	try:
		current_version = _current_version()
	except Exception as exc:
		print(f"[{current_package}] version_gate: Could not determine current version - {exc}. Skipping.")
		return []

	print(f"[{current_package}] version_gate: Running for v{'.'.join(str(part) for part in current_version)}")

	candidates: set[str] = set()

	try:
		import addon_utils  # type: ignore[import-untyped]

		for module in addon_utils.modules(refresh=True):
			name = getattr(module, "__name__", "")
			if name and _matches_identity(name) and name != current_package:
				version = _get_candidate_version(module)
				if version is not None and version < current_version:
					candidates.add(name)
				elif version is None:
					print(f"[{current_package}] version_gate: Skipping '{name}' - no version metadata.")
	except Exception as exc:
		print(f"[{current_package}] version_gate: addon_utils.modules failed - {exc}")

	for module_name in list(sys.modules.keys()):
		if not isinstance(module_name, str) or not module_name:
			continue
		top_level = module_name.split(".", 1)[0]
		if _matches_identity(top_level) and top_level != current_package and top_level not in candidates:
			module = sys.modules.get(top_level)
			if module:
				version = _get_candidate_version(module)
				if version is not None and version < current_version:
					candidates.add(top_level)

	if not candidates:
		print(f"[{current_package}] version_gate: No older copies detected - nothing to do.")
		return []

	print(f"[{current_package}] version_gate: Found {len(candidates)} older candidate(s): {sorted(candidates)}")
	disabled_now = False

	for name in sorted(candidates):
		try:
			import addon_utils  # type: ignore[import-untyped]

			is_enabled, _is_loaded = addon_utils.check(name)
			if is_enabled:
				try:
					addon_utils.disable(name, default_set=bool(persist))
					disabled_now = True
					print(f"[{current_package}] version_gate: addon_utils.disable('{name}', persist={persist}) OK")
				except Exception as exc:
					print(f"[{current_package}] version_gate: WARN addon_utils.disable('{name}') failed: {exc}")
			else:
				print(f"[{current_package}] version_gate: '{name}' already disabled - skipping disable step.")
		except Exception as exc:
			print(f"[{current_package}] version_gate: WARN addon_utils.check('{name}') failed: {exc}")

		try:
			bpy.ops.preferences.addon_disable(module=name)
			print(f"[{current_package}] version_gate: preferences.addon_disable('{name}') OK")
		except Exception:
			pass

		old_module = sys.modules.get(name)
		if old_module and hasattr(old_module, "unregister"):
			try:
				old_module.unregister()
				print(f"[{current_package}] version_gate: {name}.unregister() OK")
			except Exception as exc:
				print(f"[{current_package}] version_gate: WARN {name}.unregister() raised: {exc}")

		if purge_modules:
			purged = [module_name for module_name in sys.modules if module_name == name or module_name.startswith(name + ".")]
			for module_name in purged:
				del sys.modules[module_name]
			if purged:
				print(f"[{current_package}] version_gate: Purged {len(purged)} modules for '{name}'")

	if disabled_now and persist and save_prefs and hasattr(bpy.context, "window_manager"):
		try:
			bpy.ops.wm.save_userpref()
			print(f"[{current_package}] version_gate: Saved user preferences")
		except Exception:
			pass

	print(f"[{current_package}] version_gate: Complete - processed {len(candidates)} candidate(s).")
	return sorted(candidates)
