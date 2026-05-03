bl_info = {
	"name": "Cab87 Kinetic Text Importer",
	"author": "Cab87",
	"version": (0, 1, 12),
	"blender": (3, 6, 0),
	"location": "View3D > Sidebar > Cab87 > Kinetic Text",
	"description": "Import Cab87 dialogue timing JSON and create animated kinetic Text objects.",
	"category": "Import-Export",
}

import json
from math import cos, pi, sin
from pathlib import Path
import re

import bpy
from bpy.props import (
	BoolProperty,
	CollectionProperty,
	EnumProperty,
	FloatProperty,
	FloatVectorProperty,
	IntProperty,
	PointerProperty,
	StringProperty,
)
from bpy.types import Operator, Panel, PropertyGroup
from bpy_extras.io_utils import ImportHelper
from mathutils import Vector

from .animation import intro_keyframe_allowed, intro_scale_frame_plan, outro_frame_range, section_clear_end_frame, set_fcurve_interpolation
from .layout import LayoutDocument, LayoutOptions, TimingDocument, build_layout, parse_timing_payload
from .utils.version_gate import run_version_gate


GROUP_PROP = "cab87_kinetic_text_group"
WORD_PROP = "cab87_kinetic_text_word"
STROKE_PROP = "cab87_kinetic_text_stroke"
STROKE_LAYER_PROP = "cab87_stroke_layer_index"
COLLECTION_PROP = "cab87_kinetic_text_collection"
ADDON_ID = "cab87_kinetic_text_importer"
ADDON_VERSION = ".".join(str(part) for part in bl_info["version"])
FILL_MODE_ALIASES = {
	"FULL": "BOTH",
	"BOTH": "FULL",
}
SETTINGS_FILL_MODES = {"BOTH", "FRONT", "BACK", "NONE"}
ANIMATION_MODE_ITEMS = (
	("SCALE_FADE", "Scale + Fade", "Animate both scale and material alpha."),
	("SCALE", "Scale", "Animate scale only."),
	("FADE", "Fade", "Animate material alpha only."),
)
ANIMATION_MODES = {item[0] for item in ANIMATION_MODE_ITEMS}


class CAB87_KineticTextColorRemap(PropertyGroup):
	source_hex: StringProperty(name="Source HEX", default="")
	source_color: FloatVectorProperty(
		name="Source",
		subtype="COLOR",
		size=3,
		min=0.0,
		max=1.0,
		default=(1.0, 1.0, 1.0),
	)
	target_color: FloatVectorProperty(
		name="Material",
		subtype="COLOR",
		size=3,
		min=0.0,
		max=1.0,
		default=(1.0, 1.0, 1.0),
	)


class CAB87_KineticTextSettings(PropertyGroup):
	use_json_fps: BoolProperty(
		name="Use JSON FPS",
		description="Set the Blender scene FPS from the JSON file when it includes an fps value.",
		default=True,
	)
	start_frame: IntProperty(name="Start Frame", default=1)
	clear_existing: BoolProperty(
		name="Clear Previous Imports",
		description="Remove previous Cab87 kinetic text collections before importing.",
		default=False,
	)
	import_at_cursor: BoolProperty(name="Create At 3D Cursor", default=True)
	align_to_camera: BoolProperty(
		name="Align To Active Camera",
		description="Place the group in front of the active camera and match its rotation.",
		default=False,
	)
	camera_distance: FloatProperty(name="Camera Distance", default=6.0, min=0.1, soft_max=100.0)

	max_words_per_section: IntProperty(name="Max Words", default=8, min=1, soft_max=64)
	max_chars_per_section: IntProperty(name="Max Section Chars", default=42, min=1, soft_max=180)
	max_chars_per_line: IntProperty(name="Max Line Chars", default=24, min=1, soft_max=120)
	horizontal_alignment: EnumProperty(
		name="Line Align",
		items=(
			("LEFT", "Left", "Anchor wrapped lines on the left."),
			("CENTER", "Center", "Center wrapped lines around the group origin."),
			("RIGHT", "Right", "Anchor wrapped lines on the right."),
		),
		default="CENTER",
	)
	vertical_alignment: EnumProperty(
		name="Vertical Align",
		items=(
			("TOP", "Top", "Anchor the first text line at the group origin."),
			("CENTER", "Center", "Center each section vertically around the group origin."),
			("BOTTOM", "Bottom", "Anchor the last text line at the group origin."),
		),
		default="CENTER",
	)
	word_spacing: FloatProperty(name="Word Spacing", default=0.28, min=0.0, soft_max=4.0)
	line_spacing: FloatProperty(name="Line Spacing", default=1.2, min=0.1, soft_max=6.0)
	character_width: FloatProperty(
		name="Character Width",
		description="Approximate glyph width used for layout before Blender evaluates the font.",
		default=0.58,
		min=0.05,
		soft_max=2.0,
	)

	intro_animation: EnumProperty(name="Start Animation", items=ANIMATION_MODE_ITEMS, default="SCALE_FADE")
	outro_animation: EnumProperty(name="End Animation", items=ANIMATION_MODE_ITEMS, default="FADE")
	intro_frames: IntProperty(name="Intro Frames", default=6, min=0, soft_max=60)
	clear_frames: IntProperty(name="Clear Frames", default=5, min=0, soft_max=60)
	intro_scale: FloatProperty(name="Intro Scale", default=0.72, min=0.0, soft_max=2.0)
	outro_scale: FloatProperty(name="End Scale", default=0.0, min=0.0, soft_max=2.0)
	intro_overshoot_scale: FloatProperty(
		name="Overshoot Scale",
		description="Scale target for start animation overshoot. Set to 1.0 to disable overshoot.",
		default=1.0,
		min=1.0,
		soft_max=2.0,
	)
	intro_overshoot_frames: IntProperty(
		name="Overshoot Frames",
		description="Frames after the word start frame before hitting the overshoot scale.",
		default=0,
		min=0,
		soft_max=30,
	)
	intro_settle_frames: IntProperty(
		name="Settle Frames",
		description="Frames after overshoot before settling back to full scale.",
		default=0,
		min=0,
		soft_max=30,
	)

	font_path: StringProperty(name="Font File", subtype="FILE_PATH")
	font_size: FloatProperty(name="Font Size", default=1.0, min=0.01, soft_max=20.0)
	color: FloatVectorProperty(
		name="Color",
		subtype="COLOR",
		size=4,
		min=0.0,
		max=1.0,
		default=(1.0, 0.86, 0.22, 1.0),
	)
	color_remaps: CollectionProperty(type=CAB87_KineticTextColorRemap)
	stroke_enabled: BoolProperty(
		name="Stroke",
		description="Create a larger backing text object behind each word for an outline-like stroke.",
		default=False,
	)
	stroke_color: FloatVectorProperty(
		name="Stroke Color",
		subtype="COLOR",
		size=4,
		min=0.0,
		max=1.0,
		default=(0.0, 0.0, 0.0, 1.0),
	)
	stroke_width: FloatProperty(
		name="Stroke Width",
		description="Offset distance for backing stroke copies, scaled by font size.",
		default=0.06,
		min=0.0,
		soft_max=1.0,
	)
	stroke_copies: IntProperty(
		name="Stroke Copies",
		description="Number of same-size backing copies arranged around each fill word.",
		default=8,
		min=4,
		soft_max=24,
	)
	stroke_z_offset: FloatProperty(
		name="Stroke Z Offset",
		description="Local Z offset for stroke objects. Negative values place the stroke behind the fill text.",
		default=-0.02,
		soft_min=-1.0,
		soft_max=1.0,
	)
	bevel_depth: FloatProperty(name="Bevel Depth", default=0.0, min=0.0, soft_max=1.0)
	bevel_resolution: IntProperty(name="Bevel Resolution", default=0, min=0, soft_max=8)
	extrude: FloatProperty(name="Extrusion", default=0.0, min=0.0, soft_max=2.0)
	resolution_u: IntProperty(name="Curve Resolution", default=12, min=1, soft_max=64)
	fill_mode: EnumProperty(
		name="Fill Mode",
		items=(
			("BOTH", "Both", "Fill front and back faces."),
			("FRONT", "Front", "Fill front face only."),
			("BACK", "Back", "Fill back face only."),
			("NONE", "None", "No face fill."),
		),
		default="BOTH",
	)


class CAB87_OT_import_kinetic_text(Operator, ImportHelper):
	bl_idname = "cab87.import_kinetic_text"
	bl_label = "Import Kinetic Text JSON"
	bl_description = "Import Cab87 dialogue timing JSON as animated Blender Text objects."
	bl_options = {"REGISTER", "UNDO"}

	filename_ext = ".json"
	filter_glob: StringProperty(default="*.json", options={"HIDDEN"})

	def execute(self, context):
		settings = context.scene.cab87_kinetic_text_settings
		try:
			with Path(self.filepath).open("r", encoding="utf-8") as file:
				payload = json.load(file)
			document = parse_timing_payload(payload)
			if not document.words:
				raise ValueError("The timing JSON has no timed words.")
			sync_color_remaps_from_document(settings, document)

			if settings.clear_existing:
				remove_generated_collections()

			fps = resolve_import_fps(context.scene, document, settings)
			layout_document = build_layout(document, layout_options_from_settings(settings))
			group = create_kinetic_text_group(context, layout_document, settings, fps, self.filepath)
			context.scene.cab87_kinetic_text_last_group = group.name
			context.view_layer.objects.active = group
			group.select_set(True)
			update_scene_frame_range(context.scene, layout_document, settings, fps)
		except Exception as error:
			self.report({"ERROR"}, f"Could not import kinetic text: {error}")
			return {"CANCELLED"}

		self.report({"INFO"}, f"Imported {len(document.words)} words into {group.name}.")
		return {"FINISHED"}


class CAB87_OT_apply_kinetic_text_style(Operator):
	bl_idname = "cab87.apply_kinetic_text_style"
	bl_label = "Apply Layout And Style To Group"
	bl_description = "Reapply layout, font, bevel, extrusion, material, and animation settings to the selected kinetic text group."
	bl_options = {"REGISTER", "UNDO"}

	def execute(self, context):
		settings = context.scene.cab87_kinetic_text_settings
		group = find_target_group(context)
		if group is None:
			self.report({"ERROR"}, "Select a Cab87 kinetic text group or one of its generated words.")
			return {"CANCELLED"}

		word_objects = collect_word_objects(group)
		if not word_objects:
			self.report({"ERROR"}, "The selected kinetic text group has no generated word objects.")
			return {"CANCELLED"}

		document = document_from_group(group, word_objects)
		if len(settings.color_remaps) == 0:
			sync_color_remaps_from_document(settings, document)
		fps = resolve_group_fps(context.scene, group, document, settings)
		layout_document = build_layout(document, layout_options_from_settings(settings))
		apply_layout_to_existing_group(group, word_objects, layout_document, settings, fps)
		write_group_properties(group, settings, document, fps, group.get("cab87_source_file", ""))
		update_scene_frame_range(context.scene, layout_document, settings, fps)
		context.scene.cab87_kinetic_text_last_group = group.name

		self.report({"INFO"}, f"Updated {len(word_objects)} kinetic text words in {group.name}.")
		return {"FINISHED"}


class CAB87_OT_load_kinetic_text_settings(Operator):
	bl_idname = "cab87.load_kinetic_text_settings"
	bl_label = "Load Group Settings"
	bl_description = "Load layout, animation, and style settings from the selected Cab87 kinetic text group into the panel."
	bl_options = {"REGISTER", "UNDO"}

	def execute(self, context):
		group = find_target_group(context)
		if group is None:
			self.report({"ERROR"}, "Select a Cab87 kinetic text group or one of its generated words.")
			return {"CANCELLED"}

		settings = context.scene.cab87_kinetic_text_settings
		load_group_properties_into_settings(group, settings)
		if len(settings.color_remaps) == 0:
			word_objects = collect_word_objects(group)
			if word_objects:
				sync_color_remaps_from_document(settings, document_from_group(group, word_objects))
		context.scene.cab87_kinetic_text_last_group = group.name
		self.report({"INFO"}, f"Loaded settings from {group.name}.")
		return {"FINISHED"}


class CAB87_PT_kinetic_text_panel(Panel):
	bl_label = f"Kinetic Text v{ADDON_VERSION}"
	bl_idname = "CAB87_PT_kinetic_text_panel"
	bl_space_type = "VIEW_3D"
	bl_region_type = "UI"
	bl_category = "Cab87"

	def draw(self, context):
		layout = self.layout
		settings = context.scene.cab87_kinetic_text_settings
		group = find_target_group(context)

		layout.operator(CAB87_OT_import_kinetic_text.bl_idname, icon="IMPORT")
		if group:
			layout.label(text=f"Target: {group.name}", icon="EMPTY_AXIS")
			layout.operator(CAB87_OT_load_kinetic_text_settings.bl_idname, icon="PRESET")
			layout.operator(CAB87_OT_apply_kinetic_text_style.bl_idname, icon="FILE_REFRESH")
		else:
			layout.label(text="Target: select a generated group", icon="INFO")

		box = layout.box()
		box.label(text="Import")
		box.prop(settings, "use_json_fps")
		box.prop(settings, "start_frame")
		box.prop(settings, "clear_existing")
		box.prop(settings, "import_at_cursor")
		box.prop(settings, "align_to_camera")
		if settings.align_to_camera:
			box.prop(settings, "camera_distance")

		box = layout.box()
		box.label(text="Layout")
		box.prop(settings, "max_chars_per_line")
		box.prop(settings, "horizontal_alignment")
		box.prop(settings, "vertical_alignment")
		box.prop(settings, "word_spacing")
		box.prop(settings, "line_spacing")
		box.prop(settings, "character_width")

		box = layout.box()
		box.label(text="Animation")
		box.prop(settings, "intro_animation")
		box.prop(settings, "intro_frames")
		if animation_uses_scale(settings.intro_animation):
			box.prop(settings, "intro_scale")
			box.prop(settings, "intro_overshoot_scale")
			row = box.row(align=True)
			row.prop(settings, "intro_overshoot_frames")
			row.prop(settings, "intro_settle_frames")
		box.prop(settings, "outro_animation")
		box.prop(settings, "clear_frames")
		if animation_uses_scale(settings.outro_animation):
			box.prop(settings, "outro_scale")

		box = layout.box()
		box.label(text="Text Style")
		box.prop(settings, "font_path")
		box.prop(settings, "font_size")
		box.prop(settings, "color")
		if len(settings.color_remaps) > 0:
			box.label(text="JSON Color Remaps")
			for remap in settings.color_remaps:
				row = box.row(align=True)
				source = row.row(align=True)
				source.enabled = False
				source.prop(remap, "source_color", text=remap.source_hex)
				row.label(text="to")
				row.prop(remap, "target_color", text="")
		box.prop(settings, "stroke_enabled")
		if settings.stroke_enabled:
			box.prop(settings, "stroke_color")
			box.prop(settings, "stroke_width")
			box.prop(settings, "stroke_copies")
			box.prop(settings, "stroke_z_offset")
		box.prop(settings, "fill_mode")
		box.prop(settings, "bevel_depth")
		box.prop(settings, "bevel_resolution")
		box.prop(settings, "extrude")
		box.prop(settings, "resolution_u")


def layout_options_from_settings(settings: CAB87_KineticTextSettings) -> LayoutOptions:
	return LayoutOptions(
		max_words_per_section=settings.max_words_per_section,
		max_chars_per_section=settings.max_chars_per_section,
		max_chars_per_line=settings.max_chars_per_line,
		word_spacing=settings.word_spacing,
		line_spacing=settings.line_spacing,
		character_width=settings.character_width,
		horizontal_alignment=settings.horizontal_alignment,
		vertical_alignment=settings.vertical_alignment,
	)


def resolve_import_fps(scene, document: TimingDocument, settings: CAB87_KineticTextSettings) -> float:
	if settings.use_json_fps and document.fps and document.fps > 0:
		set_scene_fps(scene, document.fps)
		return document.fps
	return scene_fps(scene)


def resolve_group_fps(scene, group, document: TimingDocument, settings: CAB87_KineticTextSettings) -> float:
	source_fps = _float_prop(group, "cab87_source_fps", document.fps or 0.0)
	if settings.use_json_fps and source_fps > 0:
		set_scene_fps(scene, source_fps)
		return source_fps
	timeline_fps = _float_prop(group, "cab87_timeline_fps", 0.0)
	return timeline_fps if timeline_fps > 0 else scene_fps(scene)


def scene_fps(scene) -> float:
	return float(scene.render.fps) / max(0.0001, float(scene.render.fps_base))


def set_scene_fps(scene, fps: float) -> None:
	if abs(fps - 29.97) < 0.02:
		scene.render.fps = 30000
		scene.render.fps_base = 1001
		return
	if abs(fps - 23.976) < 0.02:
		scene.render.fps = 24000
		scene.render.fps_base = 1001
		return
	scene.render.fps = max(1, int(round(fps)))
	scene.render.fps_base = 1


def create_kinetic_text_group(context, layout_document: LayoutDocument, settings: CAB87_KineticTextSettings, fps: float, source_path: str):
	collection = bpy.data.collections.new(unique_name(f"Cab87_KineticText_{Path(source_path).stem}"))
	collection[COLLECTION_PROP] = True
	context.scene.collection.children.link(collection)

	group = bpy.data.objects.new(unique_name("Cab87KineticText_Group"), None)
	group.empty_display_type = "PLAIN_AXES"
	group.empty_display_size = 1.0
	group[GROUP_PROP] = True
	collection.objects.link(group)
	place_group_object(context, group, settings)
	write_group_properties(group, settings, layout_document.source, fps, source_path)

	font = load_font(settings.font_path)
	section_starts = [section.start for section in layout_document.sections]
	active_stroke_offsets = stroke_offsets(settings) if settings.stroke_enabled else ()
	for layout_word in layout_document.words:
		for stroke_layer_index, stroke_offset in enumerate(active_stroke_offsets):
			stroke_obj = create_stroke_object(layout_word, settings, font, stroke_layer_index, stroke_offset)
			stroke_obj.parent = group
			collection.objects.link(stroke_obj)
			stroke_material = create_word_material(f"{stroke_obj.name}_Material", settings, stroke_rgb(settings), stroke_alpha(settings))
			stroke_obj.data.materials.append(stroke_material)
			animate_word_object(
				stroke_obj,
				stroke_material,
				layout_word,
				section_starts,
				settings,
				fps,
				stroke_rgb(settings),
				stroke_alpha(settings),
			)

		curve = bpy.data.curves.new(unique_name(f"Cab87Word_{layout_word.source_index + 1:03d}_{slug(layout_word.text)}"), "FONT")
		curve.body = layout_word.text
		apply_text_curve_style(curve, settings, font)

		obj = bpy.data.objects.new(curve.name, curve)
		obj[WORD_PROP] = True
		write_word_properties(obj, layout_word)
		obj.parent = group
		obj.location = scaled_location(layout_word, settings)
		collection.objects.link(obj)

		word_color = color_for_layout_word(layout_word, settings)
		material = create_word_material(f"{curve.name}_Material", settings, word_color)
		curve.materials.append(material)
		animate_word_object(obj, material, layout_word, section_starts, settings, fps)

	return group


def place_group_object(context, group, settings: CAB87_KineticTextSettings) -> None:
	if settings.align_to_camera and context.scene.camera:
		camera = context.scene.camera
		group.location = camera.matrix_world @ Vector((0.0, 0.0, -settings.camera_distance))
		group.rotation_euler = camera.rotation_euler
	elif settings.import_at_cursor:
		group.location = context.scene.cursor.location


def apply_layout_to_existing_group(group, word_objects, layout_document: LayoutDocument, settings: CAB87_KineticTextSettings, fps: float) -> None:
	font = load_font(settings.font_path)
	section_starts = [section.start for section in layout_document.sections]
	objects_by_index = {int(obj.get("cab87_word_index", -1)): obj for obj in word_objects}
	stroke_objects = collect_stroke_objects(group)
	stroke_objects_by_key = {}
	duplicate_stroke_objects = []
	for obj in stroke_objects:
		key = stroke_object_key(obj)
		if key in stroke_objects_by_key:
			duplicate_stroke_objects.append(obj)
		else:
			stroke_objects_by_key[key] = obj
	active_stroke_offsets = stroke_offsets(settings) if settings.stroke_enabled else ()
	expected_stroke_keys = {
		(layout_word.source_index, stroke_layer_index)
		for layout_word in layout_document.words
		for stroke_layer_index, _stroke_offset in enumerate(active_stroke_offsets)
	}

	for obj in word_objects:
		clear_generated_word_animation(obj)
	for obj in stroke_objects:
		clear_generated_word_animation(obj)

	if not settings.stroke_enabled:
		for obj in stroke_objects:
			remove_object_data(obj)
		stroke_objects_by_key = {}
	else:
		for obj in duplicate_stroke_objects:
			remove_object_data(obj)
		for key, obj in list(stroke_objects_by_key.items()):
			if key not in expected_stroke_keys:
				remove_object_data(obj)
				stroke_objects_by_key.pop(key, None)

	for layout_word in layout_document.words:
		obj = objects_by_index.get(layout_word.source_index)
		if obj is None or obj.type != "FONT":
			continue
		for stroke_layer_index, stroke_offset in enumerate(active_stroke_offsets):
			stroke_key = (layout_word.source_index, stroke_layer_index)
			stroke_obj = stroke_objects_by_key.get(stroke_key)
			if stroke_obj is None:
				stroke_obj = create_stroke_object(layout_word, settings, font, stroke_layer_index, stroke_offset)
				stroke_obj.parent = group
				target_collection = collection_for_generated_object(obj, group)
				target_collection.objects.link(stroke_obj)
			else:
				stroke_obj.data.body = layout_word.text
				apply_stroke_text_curve_style(stroke_obj.data, settings, font)
				stroke_obj.location = stroke_location(layout_word, settings, stroke_offset)
				write_stroke_properties(stroke_obj, layout_word, stroke_layer_index)
			stroke_material = ensure_word_material(stroke_obj, settings, stroke_rgb(settings), stroke_alpha(settings))
			clear_material_animation(stroke_material)
			animate_word_object(
				stroke_obj,
				stroke_material,
				layout_word,
				section_starts,
				settings,
				fps,
				stroke_rgb(settings),
				stroke_alpha(settings),
			)
		obj.data.body = layout_word.text
		apply_text_curve_style(obj.data, settings, font)
		obj.location = scaled_location(layout_word, settings)
		write_word_properties(obj, layout_word)
		word_color = color_for_layout_word(layout_word, settings)
		material = ensure_word_material(obj, settings, word_color)
		clear_material_animation(material)
		animate_word_object(obj, material, layout_word, section_starts, settings, fps)


def clear_generated_word_animation(obj) -> None:
	clear_animation_data(obj)
	clear_animation_data(getattr(obj, "data", None))
	for material in getattr(getattr(obj, "data", None), "materials", []):
		clear_material_animation(material)


def clear_material_animation(material) -> None:
	if material is None:
		return
	clear_animation_data(material)
	clear_animation_data(getattr(material, "node_tree", None))


def clear_animation_data(owner) -> None:
	if owner is not None and hasattr(owner, "animation_data_clear"):
		owner.animation_data_clear()


def apply_text_curve_style(curve, settings: CAB87_KineticTextSettings, font) -> None:
	curve.size = settings.font_size
	curve.align_x = "CENTER"
	curve.align_y = "CENTER"
	curve.bevel_depth = settings.bevel_depth
	curve.bevel_resolution = settings.bevel_resolution
	curve.extrude = settings.extrude
	curve.resolution_u = settings.resolution_u
	if hasattr(curve, "fill_mode"):
		set_curve_fill_mode(curve, settings.fill_mode)
	if font is not None:
		curve.font = font


def apply_stroke_text_curve_style(curve, settings: CAB87_KineticTextSettings, font) -> None:
	apply_text_curve_style(curve, settings, font)
	if hasattr(curve, "offset"):
		curve.offset = 0.0


def create_stroke_object(layout_word, settings: CAB87_KineticTextSettings, font, stroke_layer_index: int, stroke_offset):
	curve = bpy.data.curves.new(
		unique_name(f"Cab87Stroke_{layout_word.source_index + 1:03d}_{stroke_layer_index + 1:02d}_{slug(layout_word.text)}"),
		"FONT",
	)
	curve.body = layout_word.text
	apply_stroke_text_curve_style(curve, settings, font)

	obj = bpy.data.objects.new(curve.name, curve)
	write_stroke_properties(obj, layout_word, stroke_layer_index)
	obj.location = stroke_location(layout_word, settings, stroke_offset)
	return obj


def collection_for_generated_object(obj, group):
	if getattr(obj, "users_collection", None):
		return obj.users_collection[0]
	if getattr(group, "users_collection", None):
		return group.users_collection[0]
	return bpy.context.scene.collection


def set_curve_fill_mode(curve, fill_mode: str) -> None:
	last_error = None
	for candidate in curve_fill_mode_candidates(curve, fill_mode):
		try:
			curve.fill_mode = candidate
			return
		except TypeError as error:
			last_error = error
		except ValueError as error:
			last_error = error

	if last_error is not None:
		raise last_error


def curve_fill_mode_candidates(curve, fill_mode: str) -> list[str]:
	candidates = [
		resolve_curve_fill_mode(curve, fill_mode),
		FILL_MODE_ALIASES.get(fill_mode, ""),
		"BOTH",
		"FULL",
		"FRONT",
		"BACK",
		"NONE",
	]

	seen = set()
	return [
		candidate
		for candidate in candidates
		if candidate and not (candidate in seen or seen.add(candidate))
	]


def resolve_curve_fill_mode(curve, fill_mode: str) -> str:
	enum_property = get_curve_fill_mode_property(curve)
	supported_modes = {item.identifier for item in enum_property.enum_items} if enum_property else set()
	if not supported_modes or fill_mode in supported_modes:
		return fill_mode

	alias = FILL_MODE_ALIASES.get(fill_mode)
	if alias in supported_modes:
		return alias

	for fallback in ("BOTH", "FULL", "FRONT", "BACK", "NONE"):
		if fallback in supported_modes:
			return fallback
	return fill_mode


def get_curve_fill_mode_property(curve):
	properties = curve.bl_rna.properties
	get_property = getattr(properties, "get", None)
	if callable(get_property):
		property_info = get_property("fill_mode")
		if property_info:
			return property_info

	try:
		return properties["fill_mode"]
	except Exception:
		return None


def resolve_settings_fill_mode(fill_mode: str, fallback: str) -> str:
	if fill_mode in SETTINGS_FILL_MODES:
		return fill_mode

	alias = FILL_MODE_ALIASES.get(fill_mode)
	if alias in SETTINGS_FILL_MODES:
		return alias

	return fallback if fallback in SETTINGS_FILL_MODES else "BOTH"


def resolve_animation_mode(mode: str, fallback: str) -> str:
	if mode in ANIMATION_MODES:
		return mode
	if mode == "BOTH":
		return "SCALE_FADE"
	return fallback if fallback in ANIMATION_MODES else "SCALE_FADE"


def animation_uses_scale(mode: str) -> bool:
	return resolve_animation_mode(mode, "SCALE_FADE") in {"SCALE", "SCALE_FADE"}


def animation_uses_fade(mode: str) -> bool:
	return resolve_animation_mode(mode, "SCALE_FADE") in {"FADE", "SCALE_FADE"}


def sync_color_remaps_from_document(settings: CAB87_KineticTextSettings, document: TimingDocument) -> None:
	sync_color_remaps(settings, document.color_swatches)


def sync_color_remaps(settings: CAB87_KineticTextSettings, source_colors, saved_targets=None) -> None:
	targets = saved_targets if saved_targets is not None else current_color_remap_targets(settings)
	unique_sources = []
	seen = set()
	for raw_color in source_colors or []:
		source = normalize_hex_color(raw_color)
		if not source or source in seen:
			continue
		unique_sources.append(source)
		seen.add(source)

	settings.color_remaps.clear()
	for source in unique_sources:
		source_rgb = hex_to_rgb(source) or tuple(float(value) for value in settings.color[:3])
		target_rgb = targets.get(source, source_rgb) if targets else source_rgb
		remap = settings.color_remaps.add()
		remap.source_hex = source
		remap.source_color = source_rgb
		remap.target_color = sanitize_rgb(target_rgb, source_rgb)


def current_color_remap_targets(settings: CAB87_KineticTextSettings) -> dict[str, tuple[float, float, float]]:
	targets = {}
	for remap in settings.color_remaps:
		source = normalize_hex_color(remap.source_hex)
		if source:
			targets[source] = sanitize_rgb(remap.target_color, tuple(float(value) for value in settings.color[:3]))
	return targets


def color_remap_lookup(settings: CAB87_KineticTextSettings) -> dict[str, tuple[float, float, float]]:
	return current_color_remap_targets(settings)


def color_for_layout_word(layout_word, settings: CAB87_KineticTextSettings):
	source = normalize_hex_color(getattr(layout_word, "color", ""))
	if source:
		remapped_color = color_remap_lookup(settings).get(source)
		if remapped_color is not None:
			return remapped_color
		color = hex_to_rgb(source)
		if color is not None:
			return color
	return tuple(float(value) for value in settings.color[:3])


def normalize_hex_color(value) -> str | None:
	text = str(value or "").strip()
	if len(text) in {3, 6}:
		text = f"#{text}"
	if len(text) == 4 and text.startswith("#"):
		text = f"#{text[1] * 2}{text[2] * 2}{text[3] * 2}"
	if len(text) != 7 or not text.startswith("#"):
		return None
	try:
		int(text[1:], 16)
	except ValueError:
		return None
	return text.lower()


def hex_to_rgb(value: str):
	text = normalize_hex_color(value)
	if text is None:
		return None
	try:
		return tuple(int(text[index : index + 2], 16) / 255 for index in (1, 3, 5))
	except ValueError:
		return None


def rgb_from_value(value, fallback=None):
	if isinstance(value, str):
		return hex_to_rgb(value) or fallback
	if isinstance(value, dict):
		return rgb_from_value(value.get("target") or value.get("targetColor") or value.get("targetRgb"), fallback)
	if isinstance(value, (list, tuple)) and len(value) >= 3:
		return sanitize_rgb(value, fallback)
	return fallback


def sanitize_rgb(value, fallback=None):
	channels = []
	try:
		source = list(value)[:3]
	except TypeError:
		return fallback
	if len(source) < 3:
		return fallback
	for raw_channel in source:
		try:
			channel = float(raw_channel)
		except (TypeError, ValueError):
			return fallback
		channels.append(max(0.0, min(1.0, channel)))
	return tuple(channels)


def rgb_to_hex(value) -> str:
	rgb = sanitize_rgb(value, (1.0, 1.0, 1.0))
	return "#" + "".join(f"{round(channel * 255):02x}" for channel in rgb)


def stroke_rgb(settings: CAB87_KineticTextSettings):
	return sanitize_rgb(settings.stroke_color[:3], (0.0, 0.0, 0.0))


def stroke_alpha(settings: CAB87_KineticTextSettings) -> float:
	try:
		return max(0.0, min(1.0, float(settings.stroke_color[3])))
	except (TypeError, ValueError):
		return 1.0


def stroke_copy_count(settings: CAB87_KineticTextSettings) -> int:
	return max(4, int(settings.stroke_copies or 8))


def stroke_offsets(settings: CAB87_KineticTextSettings) -> tuple[tuple[float, float], ...]:
	radius = max(0.0, float(settings.stroke_width)) * max(0.01, float(settings.font_size))
	if radius <= 0:
		return ()
	count = stroke_copy_count(settings)
	return tuple(
		(
			cos((2 * pi * index) / count) * radius,
			sin((2 * pi * index) / count) * radius,
		)
		for index in range(count)
	)


def create_word_material(name: str, settings: CAB87_KineticTextSettings, color=None, alpha=None):
	material = bpy.data.materials.new(unique_name(name))
	material.use_nodes = True
	if hasattr(material, "blend_method"):
		material.blend_method = "BLEND"
	if hasattr(material, "show_transparent_back"):
		material.show_transparent_back = True
	set_material_color(material, settings, settings.color[3] if alpha is None else alpha, color)
	return material


def ensure_word_material(obj, settings: CAB87_KineticTextSettings, color=None, alpha=None):
	if obj.data.materials:
		material = obj.data.materials[0]
	else:
		material = create_word_material(f"{obj.name}_Material", settings, color, alpha)
		obj.data.materials.append(material)
	set_material_color(material, settings, settings.color[3] if alpha is None else alpha, color)
	return material


def animate_word_object(
	obj,
	material,
	layout_word,
	section_starts: list[float],
	settings: CAB87_KineticTextSettings,
	fps: float,
	material_color=None,
	material_alpha=None,
) -> None:
	start_frame = frame_for_seconds(layout_word.start, fps, settings.start_frame)
	intro_frame = max(settings.start_frame, start_frame - settings.intro_frames)
	full_scale = (1.0, 1.0, 1.0)
	intro_scale = (settings.intro_scale, settings.intro_scale, settings.intro_scale)
	outro_scale = (settings.outro_scale, settings.outro_scale, settings.outro_scale)
	word_color = material_color if material_color is not None else color_for_layout_word(layout_word, settings)
	word_alpha = settings.color[3] if material_alpha is None else material_alpha
	intro_animation = resolve_animation_mode(settings.intro_animation, "SCALE_FADE")
	outro_animation = resolve_animation_mode(settings.outro_animation, "FADE")

	next_section_start = next_section_start_for(layout_word.section_index, section_starts)
	clear_start_frame = None
	clear_end_frame = None
	if next_section_start is not None:
		next_section_start_frame = frame_for_seconds(next_section_start, fps, settings.start_frame)
		clear_end_frame = section_clear_end_frame(next_section_start_frame, settings.intro_frames, settings.start_frame)
		clear_start_frame, clear_end_frame = outro_frame_range(start_frame, clear_end_frame, settings.clear_frames)

	animate_intro(
		obj,
		material,
		settings,
		intro_animation,
		intro_frame,
		start_frame,
		intro_scale,
		full_scale,
		word_color,
		word_alpha,
		clear_start_frame,
	)

	if clear_start_frame is not None and clear_end_frame is not None:
		animate_outro(
			obj,
			material,
			settings,
			outro_animation,
			clear_start_frame,
			clear_end_frame,
			full_scale,
			outro_scale,
			word_color,
			word_alpha,
		)

	set_fcurve_interpolation(obj, "BEZIER")
	if material:
		set_fcurve_interpolation(material, "LINEAR")
		set_fcurve_interpolation(getattr(material, "node_tree", None), "LINEAR")


def animate_intro(
	obj,
	material,
	settings: CAB87_KineticTextSettings,
	mode: str,
	intro_frame: int,
	start_frame: int,
	intro_scale,
	full_scale,
	word_color,
	word_alpha: float,
	outro_start_frame: int | None = None,
) -> None:
	if animation_uses_scale(mode):
		if intro_keyframe_allowed(intro_frame, outro_start_frame):
			set_object_scale_key(obj, intro_scale, intro_frame)
		set_intro_scale_target_keys(obj, settings, start_frame, full_scale, outro_start_frame)
	else:
		if intro_keyframe_allowed(start_frame, outro_start_frame):
			set_object_scale_key(obj, full_scale, start_frame)

	if animation_uses_fade(mode):
		if intro_keyframe_allowed(intro_frame, outro_start_frame):
			set_material_alpha_key(material, settings, 0.0, intro_frame, word_color)
		if intro_keyframe_allowed(start_frame, outro_start_frame):
			set_material_alpha_key(material, settings, word_alpha, start_frame, word_color)
	else:
		hidden_frame = max(settings.start_frame, intro_frame - 1)
		if hidden_frame < intro_frame and intro_keyframe_allowed(hidden_frame, outro_start_frame):
			set_material_alpha_key(material, settings, 0.0, hidden_frame, word_color)
		if intro_keyframe_allowed(intro_frame, outro_start_frame):
			set_material_alpha_key(material, settings, word_alpha, intro_frame, word_color)


def set_intro_scale_target_keys(obj, settings: CAB87_KineticTextSettings, start_frame: int, full_scale, outro_start_frame: int | None = None) -> None:
	overshoot_scale = max(1.0, float(settings.intro_overshoot_scale))
	overshoot = (overshoot_scale, overshoot_scale, overshoot_scale)
	for frame, target in intro_scale_frame_plan(
		start_frame,
		settings.intro_overshoot_scale,
		settings.intro_overshoot_frames,
		settings.intro_settle_frames,
		outro_start_frame,
	):
		set_object_scale_key(obj, overshoot if target == "overshoot" else full_scale, frame)


def animate_outro(obj, material, settings: CAB87_KineticTextSettings, mode: str, clear_start_frame: int, clear_end_frame: int, full_scale, outro_scale, word_color, word_alpha: float) -> None:
	if animation_uses_scale(mode):
		set_object_scale_key(obj, full_scale, clear_start_frame)
		set_object_scale_key(obj, outro_scale, clear_end_frame)
	else:
		set_object_scale_key(obj, full_scale, clear_start_frame)

	if animation_uses_fade(mode):
		set_material_alpha_key(material, settings, word_alpha, clear_start_frame, word_color)
		set_material_alpha_key(material, settings, 0.0, clear_end_frame, word_color)
	else:
		set_material_alpha_key(material, settings, word_alpha, clear_start_frame, word_color)
		set_material_alpha_key(material, settings, word_alpha, clear_end_frame, word_color)


def set_object_scale_key(obj, scale, frame: int) -> None:
	obj.scale = scale
	obj.keyframe_insert(data_path="scale", frame=frame)


def set_material_alpha_key(material, settings: CAB87_KineticTextSettings, alpha: float, frame: int, color=None) -> None:
	if material is None:
		return
	set_material_color(material, settings, alpha, color)
	material.keyframe_insert(data_path="diffuse_color", frame=frame)
	for input_socket in material_alpha_sockets(material):
		input_socket.keyframe_insert(data_path="default_value", frame=frame)


def set_material_color(material, settings: CAB87_KineticTextSettings, alpha: float, color=None) -> None:
	r, g, b = color[:3] if color else settings.color[:3]
	material.diffuse_color = (r, g, b, alpha)
	for input_socket in material_color_sockets(material):
		if hasattr(input_socket, "default_value"):
			if len(input_socket.default_value) == 4:
				input_socket.default_value = (r, g, b, alpha)
	for input_socket in material_alpha_sockets(material):
		input_socket.default_value = alpha


def material_color_sockets(material):
	if not material or not material.use_nodes:
		return []
	node = material.node_tree.nodes.get("Principled BSDF")
	if not node:
		return []
	socket = node.inputs.get("Base Color")
	return [socket] if socket else []


def material_alpha_sockets(material):
	if not material or not material.use_nodes:
		return []
	node = material.node_tree.nodes.get("Principled BSDF")
	if not node:
		return []
	socket = node.inputs.get("Alpha")
	return [socket] if socket else []


def next_section_start_for(section_index: int, section_starts: list[float]) -> float | None:
	next_index = section_index + 1
	if next_index >= len(section_starts):
		return None
	return section_starts[next_index]


def frame_for_seconds(seconds: float, fps: float, start_frame: int) -> int:
	return int(start_frame + round(max(0.0, seconds) * fps))


def scaled_location(layout_word, settings: CAB87_KineticTextSettings):
	scale = settings.font_size
	return (layout_word.x * scale, layout_word.y * scale, 0.0)


def stroke_location(layout_word, settings: CAB87_KineticTextSettings, stroke_offset):
	x, y, _z = scaled_location(layout_word, settings)
	offset_x, offset_y = stroke_offset
	return (x + offset_x, y + offset_y, settings.stroke_z_offset)


def update_scene_frame_range(scene, layout_document: LayoutDocument, settings: CAB87_KineticTextSettings, fps: float) -> None:
	animation_tail_frames = max(
		settings.clear_frames,
		settings.intro_frames,
		settings.intro_overshoot_frames + settings.intro_settle_frames,
		12,
	)
	end_frame = frame_for_seconds(layout_document.source.duration, fps, settings.start_frame) + animation_tail_frames
	scene.frame_start = min(scene.frame_start, settings.start_frame)
	scene.frame_end = max(scene.frame_end, end_frame)


def write_word_properties(obj, layout_word) -> None:
	obj["cab87_word_index"] = layout_word.source_index
	obj["cab87_word_text"] = layout_word.text
	obj["cab87_word_start"] = layout_word.start
	obj["cab87_word_end"] = layout_word.end
	obj["cab87_break_after"] = layout_word.break_after
	obj["cab87_word_color"] = layout_word.color or ""
	obj["cab87_color_override"] = bool(layout_word.color_override)
	obj["cab87_section_index"] = layout_word.section_index
	obj["cab87_line_index"] = layout_word.line_index


def write_stroke_properties(obj, layout_word, stroke_layer_index: int) -> None:
	obj[STROKE_PROP] = True
	obj[STROKE_LAYER_PROP] = int(stroke_layer_index)
	write_word_properties(obj, layout_word)


def write_group_properties(group, settings: CAB87_KineticTextSettings, document: TimingDocument, fps: float, source_path: str) -> None:
	group[GROUP_PROP] = True
	group["cab87_source_file"] = str(source_path)
	group["cab87_source_schema"] = document.schema or ""
	group["cab87_source_version"] = document.version or 0
	group["cab87_source_fps"] = document.fps or 0.0
	group["cab87_default_color"] = document.default_color or ""
	group["cab87_color_swatches"] = json.dumps(list(document.color_swatches))
	group["cab87_color_remaps"] = json.dumps(serialize_color_remaps(settings))
	group["cab87_timeline_fps"] = fps
	group["cab87_start_frame"] = settings.start_frame
	group["cab87_max_words_per_section"] = settings.max_words_per_section
	group["cab87_max_chars_per_section"] = settings.max_chars_per_section
	group["cab87_max_chars_per_line"] = settings.max_chars_per_line
	group["cab87_horizontal_alignment"] = settings.horizontal_alignment
	group["cab87_vertical_alignment"] = settings.vertical_alignment
	group["cab87_word_spacing"] = settings.word_spacing
	group["cab87_line_spacing"] = settings.line_spacing
	group["cab87_character_width"] = settings.character_width
	group["cab87_intro_animation"] = settings.intro_animation
	group["cab87_outro_animation"] = settings.outro_animation
	group["cab87_intro_frames"] = settings.intro_frames
	group["cab87_clear_frames"] = settings.clear_frames
	group["cab87_intro_scale"] = settings.intro_scale
	group["cab87_outro_scale"] = settings.outro_scale
	group["cab87_intro_overshoot_scale"] = settings.intro_overshoot_scale
	group["cab87_intro_overshoot_frames"] = settings.intro_overshoot_frames
	group["cab87_intro_settle_frames"] = settings.intro_settle_frames
	group["cab87_font_path"] = settings.font_path
	group["cab87_font_size"] = settings.font_size
	group["cab87_color"] = [float(value) for value in settings.color]
	group["cab87_stroke_enabled"] = bool(settings.stroke_enabled)
	group["cab87_stroke_color"] = [float(value) for value in settings.stroke_color]
	group["cab87_stroke_width"] = settings.stroke_width
	group["cab87_stroke_copies"] = settings.stroke_copies
	group["cab87_stroke_z_offset"] = settings.stroke_z_offset
	group["cab87_fill_mode"] = settings.fill_mode
	group["cab87_bevel_depth"] = settings.bevel_depth
	group["cab87_bevel_resolution"] = settings.bevel_resolution
	group["cab87_extrude"] = settings.extrude
	group["cab87_resolution_u"] = settings.resolution_u


def serialize_color_remaps(settings: CAB87_KineticTextSettings) -> list[dict[str, object]]:
	remaps = []
	for remap in settings.color_remaps:
		source = normalize_hex_color(remap.source_hex)
		if not source:
			continue
		target = sanitize_rgb(remap.target_color, hex_to_rgb(source) or (1.0, 1.0, 1.0))
		remaps.append(
			{
				"source": source,
				"target": list(target),
				"targetHex": rgb_to_hex(target),
			}
		)
	return remaps


def load_color_remaps_from_group(group, settings: CAB87_KineticTextSettings) -> None:
	saved_targets = color_remap_targets_from_group(group)
	source_colors = color_swatches_from_group(group)
	if not source_colors:
		source_colors = list(saved_targets.keys())
	sync_color_remaps(settings, source_colors, saved_targets)


def color_remap_targets_from_group(group) -> dict[str, tuple[float, float, float]]:
	targets = {}
	for entry in read_json_list_prop(group, "cab87_color_remaps"):
		if not isinstance(entry, dict):
			continue
		source = normalize_hex_color(entry.get("source") or entry.get("sourceHex") or entry.get("hex"))
		if not source:
			continue
		target = rgb_from_value(
			entry.get("target") or entry.get("targetColor") or entry.get("targetRgb") or entry.get("targetHex"),
			hex_to_rgb(source),
		)
		if target is not None:
			targets[source] = target
	return targets


def color_swatches_from_group(group) -> list[str]:
	swatches = []
	for raw_color in read_json_list_prop(group, "cab87_color_swatches"):
		color = normalize_hex_color(raw_color)
		if color and color not in swatches:
			swatches.append(color)
	if swatches:
		return swatches
	return list(color_remap_targets_from_group(group).keys())


def read_json_list_prop(owner, key: str) -> list:
	value = owner.get(key)
	if value is None:
		return []
	if isinstance(value, str):
		try:
			decoded = json.loads(value)
		except json.JSONDecodeError:
			return []
		return decoded if isinstance(decoded, list) else []
	if isinstance(value, (list, tuple)):
		return list(value)
	return []


def load_group_properties_into_settings(group, settings: CAB87_KineticTextSettings) -> None:
	settings.start_frame = int(group.get("cab87_start_frame", settings.start_frame))
	settings.max_words_per_section = int(group.get("cab87_max_words_per_section", settings.max_words_per_section))
	settings.max_chars_per_section = int(group.get("cab87_max_chars_per_section", settings.max_chars_per_section))
	settings.max_chars_per_line = int(group.get("cab87_max_chars_per_line", settings.max_chars_per_line))
	settings.horizontal_alignment = group.get("cab87_horizontal_alignment", settings.horizontal_alignment)
	settings.vertical_alignment = group.get("cab87_vertical_alignment", settings.vertical_alignment)
	settings.word_spacing = _float_prop(group, "cab87_word_spacing", settings.word_spacing)
	settings.line_spacing = _float_prop(group, "cab87_line_spacing", settings.line_spacing)
	settings.character_width = _float_prop(group, "cab87_character_width", settings.character_width)
	settings.intro_animation = resolve_animation_mode(
		group.get("cab87_intro_animation", settings.intro_animation),
		settings.intro_animation,
	)
	settings.outro_animation = resolve_animation_mode(
		group.get("cab87_outro_animation", settings.outro_animation),
		settings.outro_animation,
	)
	settings.intro_frames = int(group.get("cab87_intro_frames", settings.intro_frames))
	settings.clear_frames = int(group.get("cab87_clear_frames", settings.clear_frames))
	settings.intro_scale = _float_prop(group, "cab87_intro_scale", settings.intro_scale)
	settings.outro_scale = _float_prop(group, "cab87_outro_scale", settings.outro_scale)
	settings.intro_overshoot_scale = _float_prop(
		group,
		"cab87_intro_overshoot_scale",
		settings.intro_overshoot_scale,
	)
	settings.intro_overshoot_frames = int(group.get("cab87_intro_overshoot_frames", settings.intro_overshoot_frames))
	settings.intro_settle_frames = int(group.get("cab87_intro_settle_frames", settings.intro_settle_frames))
	settings.font_path = group.get("cab87_font_path", settings.font_path)
	settings.font_size = _float_prop(group, "cab87_font_size", settings.font_size)
	settings.fill_mode = resolve_settings_fill_mode(
		group.get("cab87_fill_mode", settings.fill_mode),
		settings.fill_mode,
	)
	settings.bevel_depth = _float_prop(group, "cab87_bevel_depth", settings.bevel_depth)
	settings.bevel_resolution = int(group.get("cab87_bevel_resolution", settings.bevel_resolution))
	settings.extrude = _float_prop(group, "cab87_extrude", settings.extrude)
	settings.resolution_u = int(group.get("cab87_resolution_u", settings.resolution_u))
	color = group.get("cab87_color")
	if color and len(color) == 4:
		settings.color = tuple(float(value) for value in color)
	settings.stroke_enabled = bool(group.get("cab87_stroke_enabled", settings.stroke_enabled))
	stroke_color = group.get("cab87_stroke_color")
	if stroke_color and len(stroke_color) == 4:
		settings.stroke_color = tuple(float(value) for value in stroke_color)
	settings.stroke_width = _float_prop(group, "cab87_stroke_width", settings.stroke_width)
	settings.stroke_copies = int(group.get("cab87_stroke_copies", settings.stroke_copies))
	settings.stroke_z_offset = _float_prop(group, "cab87_stroke_z_offset", settings.stroke_z_offset)
	load_color_remaps_from_group(group, settings)


def document_from_group(group, word_objects) -> TimingDocument:
	words = []
	for obj in word_objects:
		words.append(
			{
				"text": obj.data.body if obj.type == "FONT" else obj.get("cab87_word_text", ""),
				"start": _float_prop(obj, "cab87_word_start", 0.0),
				"end": _float_prop(obj, "cab87_word_end", 0.0),
				"breakAfter": bool(obj.get("cab87_break_after", False)),
				"color": obj.get("cab87_word_color", "") or None,
				"colorOverride": bool(obj.get("cab87_color_override", False)),
			}
		)
	return parse_timing_payload(
		{
			"schema": group.get("cab87_source_schema", "cab87-dialogue-timing"),
			"version": int(group.get("cab87_source_version", 1)),
			"fps": _float_prop(group, "cab87_source_fps", 0.0) or None,
			"defaultColor": group.get("cab87_default_color", "") or None,
			"customColors": color_swatches_from_group(group),
			"words": words,
		}
	)


def collect_word_objects(group):
	return sorted(
		(obj for obj in group.children if obj.get(WORD_PROP) and obj.type == "FONT"),
		key=lambda obj: int(obj.get("cab87_word_index", 0)),
	)


def collect_stroke_objects(group):
	return sorted(
		(obj for obj in group.children if obj.get(STROKE_PROP) and obj.type == "FONT"),
		key=lambda obj: stroke_object_key(obj),
	)


def stroke_object_key(obj) -> tuple[int, int]:
	return (int(obj.get("cab87_word_index", -1)), int(obj.get(STROKE_LAYER_PROP, 0)))


def find_target_group(context):
	active = context.object
	current = active
	while current is not None:
		if current.get(GROUP_PROP):
			return current
		current = current.parent

	last_name = getattr(context.scene, "cab87_kinetic_text_last_group", "")
	if last_name:
		group = bpy.data.objects.get(last_name)
		if group and group.get(GROUP_PROP):
			return group
	return None


def remove_generated_collections() -> None:
	for collection in list(bpy.data.collections):
		if collection.get(COLLECTION_PROP):
			for obj in list(collection.objects):
				remove_object_data(obj)
			bpy.data.collections.remove(collection)


def remove_object_data(obj) -> None:
	data = obj.data
	for material_slot in getattr(obj, "material_slots", []):
		material = material_slot.material
		if material and material.users <= 1:
			bpy.data.materials.remove(material)
	bpy.data.objects.remove(obj, do_unlink=True)
	if data and data.users == 0:
		bpy.data.curves.remove(data)


def load_font(path: str):
	if not path:
		return None
	resolved = bpy.path.abspath(path)
	if not resolved or not Path(resolved).is_file():
		return None
	try:
		return bpy.data.fonts.load(resolved, check_existing=True)
	except RuntimeError:
		return None


def unique_name(base: str) -> str:
	name = base or "Cab87KineticText"
	existing = bpy.data.objects.get(name) or bpy.data.collections.get(name) or bpy.data.curves.get(name) or bpy.data.materials.get(name)
	if existing is None:
		return name
	index = 1
	while True:
		candidate = f"{name}.{index:03d}"
		if not (
			bpy.data.objects.get(candidate)
			or bpy.data.collections.get(candidate)
			or bpy.data.curves.get(candidate)
			or bpy.data.materials.get(candidate)
		):
			return candidate
		index += 1


def slug(text: str) -> str:
	cleaned = re.sub(r"[^A-Za-z0-9]+", "_", text.strip())[:20].strip("_")
	return cleaned or "word"


def _float_prop(owner, key: str, fallback: float) -> float:
	try:
		return float(owner.get(key, fallback))
	except (TypeError, ValueError):
		return fallback


classes = (
	CAB87_KineticTextColorRemap,
	CAB87_KineticTextSettings,
	CAB87_OT_import_kinetic_text,
	CAB87_OT_apply_kinetic_text_style,
	CAB87_OT_load_kinetic_text_settings,
	CAB87_PT_kinetic_text_panel,
)


def register():
	run_version_gate()
	for cls in classes:
		bpy.utils.register_class(cls)
	bpy.types.Scene.cab87_kinetic_text_settings = PointerProperty(type=CAB87_KineticTextSettings)
	bpy.types.Scene.cab87_kinetic_text_last_group = StringProperty(name="Last Cab87 Kinetic Text Group")


def unregister():
	del bpy.types.Scene.cab87_kinetic_text_last_group
	del bpy.types.Scene.cab87_kinetic_text_settings
	for cls in reversed(classes):
		bpy.utils.unregister_class(cls)


if __name__ == "__main__":
	register()
