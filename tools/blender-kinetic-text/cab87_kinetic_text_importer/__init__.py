bl_info = {
	"name": "Cab87 Kinetic Text Importer",
	"author": "Cab87",
	"version": (0, 1, 0),
	"blender": (3, 6, 0),
	"location": "View3D > Sidebar > Cab87 > Kinetic Text",
	"description": "Import Cab87 dialogue timing JSON and create animated kinetic Text objects.",
	"category": "Import-Export",
}

import json
from pathlib import Path
import re

import bpy
from bpy.props import BoolProperty, EnumProperty, FloatProperty, FloatVectorProperty, IntProperty, PointerProperty, StringProperty
from bpy.types import Operator, Panel, PropertyGroup
from bpy_extras.io_utils import ImportHelper
from mathutils import Vector

from .layout import LayoutDocument, LayoutOptions, TimingDocument, build_layout, parse_timing_payload
from .utils.version_gate import run_version_gate


GROUP_PROP = "cab87_kinetic_text_group"
WORD_PROP = "cab87_kinetic_text_word"
COLLECTION_PROP = "cab87_kinetic_text_collection"
ADDON_ID = "cab87_kinetic_text_importer"


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
	word_spacing: FloatProperty(name="Word Spacing", default=0.28, min=0.0, soft_max=4.0)
	line_spacing: FloatProperty(name="Line Spacing", default=1.2, min=0.1, soft_max=6.0)
	character_width: FloatProperty(
		name="Character Width",
		description="Approximate glyph width used for layout before Blender evaluates the font.",
		default=0.58,
		min=0.05,
		soft_max=2.0,
	)

	intro_frames: IntProperty(name="Intro Frames", default=6, min=0, soft_max=60)
	clear_frames: IntProperty(name="Clear Frames", default=5, min=0, soft_max=60)
	intro_scale: FloatProperty(name="Intro Scale", default=0.72, min=0.01, soft_max=2.0)

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
	bevel_depth: FloatProperty(name="Bevel Depth", default=0.0, min=0.0, soft_max=1.0)
	bevel_resolution: IntProperty(name="Bevel Resolution", default=0, min=0, soft_max=8)
	extrude: FloatProperty(name="Extrusion", default=0.0, min=0.0, soft_max=2.0)
	resolution_u: IntProperty(name="Curve Resolution", default=12, min=1, soft_max=64)
	fill_mode: EnumProperty(
		name="Fill Mode",
		items=(
			("FULL", "Full", "Fill front and back faces."),
			("FRONT", "Front", "Fill front face only."),
			("BACK", "Back", "Fill back face only."),
			("NONE", "None", "No face fill."),
		),
		default="FULL",
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
		context.scene.cab87_kinetic_text_last_group = group.name
		self.report({"INFO"}, f"Loaded settings from {group.name}.")
		return {"FINISHED"}


class CAB87_PT_kinetic_text_panel(Panel):
	bl_label = "Kinetic Text"
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
		box.prop(settings, "max_words_per_section")
		box.prop(settings, "max_chars_per_section")
		box.prop(settings, "max_chars_per_line")
		box.prop(settings, "horizontal_alignment")
		box.prop(settings, "word_spacing")
		box.prop(settings, "line_spacing")
		box.prop(settings, "character_width")

		box = layout.box()
		box.label(text="Animation")
		box.prop(settings, "intro_frames")
		box.prop(settings, "clear_frames")
		box.prop(settings, "intro_scale")

		box = layout.box()
		box.label(text="Text Style")
		box.prop(settings, "font_path")
		box.prop(settings, "font_size")
		box.prop(settings, "color")
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
	for layout_word in layout_document.words:
		curve = bpy.data.curves.new(unique_name(f"Cab87Word_{layout_word.source_index + 1:03d}_{slug(layout_word.text)}"), "FONT")
		curve.body = layout_word.text
		apply_text_curve_style(curve, settings, font)

		obj = bpy.data.objects.new(curve.name, curve)
		obj[WORD_PROP] = True
		write_word_properties(obj, layout_word)
		obj.parent = group
		obj.location = scaled_location(layout_word, settings)
		collection.objects.link(obj)

		material = create_word_material(f"{curve.name}_Material", settings)
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

	for layout_word in layout_document.words:
		obj = objects_by_index.get(layout_word.source_index)
		if obj is None or obj.type != "FONT":
			continue
		obj.data.body = layout_word.text
		apply_text_curve_style(obj.data, settings, font)
		obj.location = scaled_location(layout_word, settings)
		write_word_properties(obj, layout_word)
		material = ensure_word_material(obj, settings)
		obj.animation_data_clear()
		if material:
			material.animation_data_clear()
		animate_word_object(obj, material, layout_word, section_starts, settings, fps)


def apply_text_curve_style(curve, settings: CAB87_KineticTextSettings, font) -> None:
	curve.size = settings.font_size
	curve.align_x = "CENTER"
	curve.align_y = "CENTER"
	curve.bevel_depth = settings.bevel_depth
	curve.bevel_resolution = settings.bevel_resolution
	curve.extrude = settings.extrude
	curve.resolution_u = settings.resolution_u
	if hasattr(curve, "fill_mode"):
		curve.fill_mode = settings.fill_mode
	if font is not None:
		curve.font = font


def create_word_material(name: str, settings: CAB87_KineticTextSettings):
	material = bpy.data.materials.new(unique_name(name))
	material.use_nodes = True
	if hasattr(material, "blend_method"):
		material.blend_method = "BLEND"
	if hasattr(material, "show_transparent_back"):
		material.show_transparent_back = True
	set_material_color(material, settings, settings.color[3])
	return material


def ensure_word_material(obj, settings: CAB87_KineticTextSettings):
	if obj.data.materials:
		material = obj.data.materials[0]
	else:
		material = create_word_material(f"{obj.name}_Material", settings)
		obj.data.materials.append(material)
	set_material_color(material, settings, settings.color[3])
	return material


def animate_word_object(obj, material, layout_word, section_starts: list[float], settings: CAB87_KineticTextSettings, fps: float) -> None:
	start_frame = frame_for_seconds(layout_word.start, fps, settings.start_frame)
	intro_frame = max(settings.start_frame, start_frame - settings.intro_frames)
	full_scale = (1.0, 1.0, 1.0)
	intro_scale = (settings.intro_scale, settings.intro_scale, settings.intro_scale)

	set_object_scale_key(obj, intro_scale, intro_frame)
	set_material_alpha_key(material, settings, 0.0, intro_frame)
	set_object_scale_key(obj, full_scale, start_frame)
	set_material_alpha_key(material, settings, settings.color[3], start_frame)

	next_section_start = next_section_start_for(layout_word.section_index, section_starts)
	if next_section_start is not None:
		clear_end_frame = frame_for_seconds(next_section_start, fps, settings.start_frame)
		clear_start_frame = max(start_frame, clear_end_frame - settings.clear_frames)
		set_object_scale_key(obj, full_scale, clear_start_frame)
		set_material_alpha_key(material, settings, settings.color[3], clear_start_frame)
		set_object_scale_key(obj, full_scale, clear_end_frame)
		set_material_alpha_key(material, settings, 0.0, clear_end_frame)

	set_fcurve_interpolation(obj, "BEZIER")
	if material:
		set_fcurve_interpolation(material, "LINEAR")


def set_object_scale_key(obj, scale, frame: int) -> None:
	obj.scale = scale
	obj.keyframe_insert(data_path="scale", frame=frame)


def set_material_alpha_key(material, settings: CAB87_KineticTextSettings, alpha: float, frame: int) -> None:
	if material is None:
		return
	set_material_color(material, settings, alpha)
	material.keyframe_insert(data_path="diffuse_color", frame=frame)
	for input_socket in material_alpha_sockets(material):
		input_socket.keyframe_insert(data_path="default_value", frame=frame)


def set_material_color(material, settings: CAB87_KineticTextSettings, alpha: float) -> None:
	r, g, b, _ = settings.color
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


def set_fcurve_interpolation(owner, interpolation: str) -> None:
	if not owner or not owner.animation_data or not owner.animation_data.action:
		return
	for fcurve in owner.animation_data.action.fcurves:
		for keyframe in fcurve.keyframe_points:
			keyframe.interpolation = interpolation


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


def update_scene_frame_range(scene, layout_document: LayoutDocument, settings: CAB87_KineticTextSettings, fps: float) -> None:
	end_frame = frame_for_seconds(layout_document.source.duration, fps, settings.start_frame) + max(settings.clear_frames, settings.intro_frames, 12)
	scene.frame_start = min(scene.frame_start, settings.start_frame)
	scene.frame_end = max(scene.frame_end, end_frame)


def write_word_properties(obj, layout_word) -> None:
	obj["cab87_word_index"] = layout_word.source_index
	obj["cab87_word_text"] = layout_word.text
	obj["cab87_word_start"] = layout_word.start
	obj["cab87_word_end"] = layout_word.end
	obj["cab87_section_index"] = layout_word.section_index
	obj["cab87_line_index"] = layout_word.line_index


def write_group_properties(group, settings: CAB87_KineticTextSettings, document: TimingDocument, fps: float, source_path: str) -> None:
	group[GROUP_PROP] = True
	group["cab87_source_file"] = str(source_path)
	group["cab87_source_schema"] = document.schema or ""
	group["cab87_source_version"] = document.version or 0
	group["cab87_source_fps"] = document.fps or 0.0
	group["cab87_timeline_fps"] = fps
	group["cab87_start_frame"] = settings.start_frame
	group["cab87_max_words_per_section"] = settings.max_words_per_section
	group["cab87_max_chars_per_section"] = settings.max_chars_per_section
	group["cab87_max_chars_per_line"] = settings.max_chars_per_line
	group["cab87_horizontal_alignment"] = settings.horizontal_alignment
	group["cab87_word_spacing"] = settings.word_spacing
	group["cab87_line_spacing"] = settings.line_spacing
	group["cab87_character_width"] = settings.character_width
	group["cab87_intro_frames"] = settings.intro_frames
	group["cab87_clear_frames"] = settings.clear_frames
	group["cab87_intro_scale"] = settings.intro_scale
	group["cab87_font_path"] = settings.font_path
	group["cab87_font_size"] = settings.font_size
	group["cab87_color"] = [float(value) for value in settings.color]
	group["cab87_fill_mode"] = settings.fill_mode
	group["cab87_bevel_depth"] = settings.bevel_depth
	group["cab87_bevel_resolution"] = settings.bevel_resolution
	group["cab87_extrude"] = settings.extrude
	group["cab87_resolution_u"] = settings.resolution_u


def load_group_properties_into_settings(group, settings: CAB87_KineticTextSettings) -> None:
	settings.start_frame = int(group.get("cab87_start_frame", settings.start_frame))
	settings.max_words_per_section = int(group.get("cab87_max_words_per_section", settings.max_words_per_section))
	settings.max_chars_per_section = int(group.get("cab87_max_chars_per_section", settings.max_chars_per_section))
	settings.max_chars_per_line = int(group.get("cab87_max_chars_per_line", settings.max_chars_per_line))
	settings.horizontal_alignment = group.get("cab87_horizontal_alignment", settings.horizontal_alignment)
	settings.word_spacing = _float_prop(group, "cab87_word_spacing", settings.word_spacing)
	settings.line_spacing = _float_prop(group, "cab87_line_spacing", settings.line_spacing)
	settings.character_width = _float_prop(group, "cab87_character_width", settings.character_width)
	settings.intro_frames = int(group.get("cab87_intro_frames", settings.intro_frames))
	settings.clear_frames = int(group.get("cab87_clear_frames", settings.clear_frames))
	settings.intro_scale = _float_prop(group, "cab87_intro_scale", settings.intro_scale)
	settings.font_path = group.get("cab87_font_path", settings.font_path)
	settings.font_size = _float_prop(group, "cab87_font_size", settings.font_size)
	settings.fill_mode = group.get("cab87_fill_mode", settings.fill_mode)
	settings.bevel_depth = _float_prop(group, "cab87_bevel_depth", settings.bevel_depth)
	settings.bevel_resolution = int(group.get("cab87_bevel_resolution", settings.bevel_resolution))
	settings.extrude = _float_prop(group, "cab87_extrude", settings.extrude)
	settings.resolution_u = int(group.get("cab87_resolution_u", settings.resolution_u))
	color = group.get("cab87_color")
	if color and len(color) == 4:
		settings.color = tuple(float(value) for value in color)


def document_from_group(group, word_objects) -> TimingDocument:
	words = []
	for obj in word_objects:
		words.append(
			{
				"text": obj.data.body if obj.type == "FONT" else obj.get("cab87_word_text", ""),
				"start": _float_prop(obj, "cab87_word_start", 0.0),
				"end": _float_prop(obj, "cab87_word_end", 0.0),
			}
		)
	return parse_timing_payload(
		{
			"schema": group.get("cab87_source_schema", "cab87-dialogue-timing"),
			"version": int(group.get("cab87_source_version", 1)),
			"fps": _float_prop(group, "cab87_source_fps", 0.0) or None,
			"words": words,
		}
	)


def collect_word_objects(group):
	return sorted(
		(obj for obj in group.children if obj.get(WORD_PROP) and obj.type == "FONT"),
		key=lambda obj: int(obj.get("cab87_word_index", 0)),
	)


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
