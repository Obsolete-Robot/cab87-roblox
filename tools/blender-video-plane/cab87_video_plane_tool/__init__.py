bl_info = {
	"name": "Cab87 Video Plane Tool",
	"author": "Cab87",
	"version": (0, 2, 0),
	"blender": (3, 6, 0),
	"location": "View3D > Sidebar > Cab87 > Video Plane",
	"description": "Create aspect-ratio movie planes and Resolve/FCP XML cut grids.",
	"category": "Import-Export",
}

from dataclasses import dataclass, field
import math
from pathlib import Path
import re
from urllib.parse import unquote, urlparse
import xml.etree.ElementTree as ET

import bpy
from bpy.props import BoolProperty, EnumProperty, FloatProperty, IntProperty, PointerProperty, StringProperty
from bpy.types import Operator, Panel, PropertyGroup
from bpy_extras.io_utils import ImportHelper
from mathutils import Vector


ADDON_VERSION = ".".join(str(part) for part in bl_info["version"])
COLLECTION_NAME = "Cab87VideoPlanes"
XML_COLLECTION_PREFIX = "Cab87XmlSequence"
VIDEO_FILTER = "*.mp4;*.mov;*.m4v;*.avi;*.mkv;*.webm;*.mpg;*.mpeg"
XML_FILTER = "*.xml;*.fcpxml"


@dataclass
class TimeRemapInfo:
	speed_percent: float | None = None
	reverse: bool = False
	keyframes: list[tuple[float, float]] = field(default_factory=list)


@dataclass
class XmlVideoClip:
	clip_id: str
	name: str
	filepath: str
	timeline_start: int
	timeline_end: int
	source_in: float
	source_out: float
	source_width: int
	source_height: int
	track_index: int
	time_remap: TimeRemapInfo | None = None


@dataclass
class XmlSequence:
	name: str
	duration: int
	timebase: int
	width: int
	height: int
	clips: list[XmlVideoClip]


class CAB87_VideoPlaneSettings(PropertyGroup):
	video_path: StringProperty(
		name="Video File",
		subtype="FILE_PATH",
	)
	fit_dimension: EnumProperty(
		name="Fit By",
		items=(
			("WIDTH", "Width", "Use Fit Size as the plane width."),
			("HEIGHT", "Height", "Use Fit Size as the plane height."),
		),
		default="WIDTH",
	)
	fit_size: FloatProperty(name="Fit Size", default=6.0, min=0.01, soft_max=100.0)
	fallback_width: IntProperty(name="Fallback Width", default=1920, min=1, soft_max=8192)
	fallback_height: IntProperty(name="Fallback Height", default=1080, min=1, soft_max=8192)
	placement: EnumProperty(
		name="Placement",
		items=(
			("CURSOR", "3D Cursor", "Create the plane at the 3D cursor."),
			("CAMERA", "Active Camera", "Create the plane in front of the active camera."),
		),
		default="CURSOR",
	)
	cursor_orientation: EnumProperty(
		name="Cursor Orientation",
		items=(
			("FRONT", "Front", "Create a vertical plane facing front view."),
			("TOP", "Top", "Create a horizontal plane in top view."),
		),
		default="FRONT",
	)
	camera_distance: FloatProperty(name="Camera Distance", default=6.0, min=0.01, soft_max=100.0)
	shader_mode: EnumProperty(
		name="Shader",
		items=(
			("EMISSION", "Emission", "Use an unlit material for easy preview."),
			("PRINCIPLED", "Principled", "Use a regular Principled BSDF material."),
		),
		default="EMISSION",
	)
	emission_strength: FloatProperty(name="Emission Strength", default=1.0, min=0.0, soft_max=10.0)
	use_alpha: BoolProperty(name="Use Alpha", default=False)
	auto_refresh: BoolProperty(name="Auto Refresh", default=True)
	sync_timeline: BoolProperty(name="Set Scene Frame Range", default=True)
	frame_start: IntProperty(name="Frame Start", default=1, min=1)
	use_cyclic: BoolProperty(name="Loop Movie", default=False)
	xml_path: StringProperty(
		name="XML File",
		subtype="FILE_PATH",
	)
	xml_media_root: StringProperty(
		name="Media Root Override",
		description="Optional folder used to resolve XML media by filename when the exported paths are not valid on this machine.",
		subtype="DIR_PATH",
	)
	xml_grid_columns: IntProperty(
		name="Grid Columns",
		description="Set to 0 to choose columns automatically.",
		default=0,
		min=0,
		soft_max=24,
	)
	xml_grid_gap: FloatProperty(name="Grid Gap", default=0.6, min=0.0, soft_max=20.0)
	xml_clear_previous: BoolProperty(
		name="Clear Previous XML Import",
		description="Delete objects previously created by this XML importer before importing.",
		default=False,
	)
	xml_add_markers: BoolProperty(name="Add Cut Markers", default=True)
	xml_animate_camera: BoolProperty(name="Animate Camera", default=True)
	xml_camera_name: StringProperty(name="Camera Name", default="Cab87 XML Cut Camera")
	xml_camera_distance: FloatProperty(name="Camera Distance", default=7.0, min=0.01, soft_max=100.0)
	xml_camera_lens: FloatProperty(name="Camera Lens", default=35.0, min=1.0, soft_max=200.0)
	xml_camera_interpolation: EnumProperty(
		name="Camera Interpolation",
		items=(
			("CONSTANT", "Cuts", "Hold each camera pose until the next edit."),
			("LINEAR", "Linear Move", "Move linearly from one plane to the next."),
			("BEZIER", "Smooth Move", "Use Blender's default eased interpolation between planes."),
		),
		default="CONSTANT",
	)


class CAB87_OT_pick_video_plane(Operator, ImportHelper):
	bl_idname = "cab87.pick_video_plane"
	bl_label = "Load Video Plane"
	bl_description = "Choose a video file and create a matching movie-textured plane."
	bl_options = {"REGISTER", "UNDO"}

	filename_ext = ".mp4"
	filter_glob: StringProperty(default=VIDEO_FILTER, options={"HIDDEN"})

	def invoke(self, context, event):
		settings = context.scene.cab87_video_plane_settings
		if settings.video_path:
			self.filepath = bpy.path.abspath(settings.video_path)
		return super().invoke(context, event)

	def execute(self, context):
		settings = context.scene.cab87_video_plane_settings
		settings.video_path = self.filepath
		return create_and_report(self, context, settings, self.filepath)


class CAB87_OT_create_video_plane_from_path(Operator):
	bl_idname = "cab87.create_video_plane_from_path"
	bl_label = "Create Video Plane"
	bl_description = "Create a movie-textured plane from the Video File path."
	bl_options = {"REGISTER", "UNDO"}

	def execute(self, context):
		settings = context.scene.cab87_video_plane_settings
		if not settings.video_path:
			self.report({"ERROR"}, "Choose a video file first.")
			return {"CANCELLED"}
		return create_and_report(self, context, settings, settings.video_path)


class CAB87_OT_pick_xml_video_grid(Operator, ImportHelper):
	bl_idname = "cab87.pick_xml_video_grid"
	bl_label = "Import XML Video Grid"
	bl_description = "Choose a Resolve/FCP XML file and create a cut grid of movie-textured planes."
	bl_options = {"REGISTER", "UNDO"}

	filename_ext = ".xml"
	filter_glob: StringProperty(default=XML_FILTER, options={"HIDDEN"})

	def invoke(self, context, event):
		settings = context.scene.cab87_video_plane_settings
		if settings.xml_path:
			self.filepath = bpy.path.abspath(settings.xml_path)
		return super().invoke(context, event)

	def execute(self, context):
		settings = context.scene.cab87_video_plane_settings
		settings.xml_path = self.filepath
		return import_xml_and_report(self, context, settings, self.filepath)


class CAB87_OT_import_xml_video_grid_from_path(Operator):
	bl_idname = "cab87.import_xml_video_grid_from_path"
	bl_label = "Import XML Grid"
	bl_description = "Import a Resolve/FCP XML cut grid from the XML File path."
	bl_options = {"REGISTER", "UNDO"}

	def execute(self, context):
		settings = context.scene.cab87_video_plane_settings
		if not settings.xml_path:
			self.report({"ERROR"}, "Choose an XML file first.")
			return {"CANCELLED"}
		return import_xml_and_report(self, context, settings, settings.xml_path)


class CAB87_PT_video_plane_panel(Panel):
	bl_label = f"Video Plane v{ADDON_VERSION}"
	bl_idname = "CAB87_PT_video_plane_panel"
	bl_space_type = "VIEW_3D"
	bl_region_type = "UI"
	bl_category = "Cab87"

	def draw(self, context):
		layout = self.layout
		settings = context.scene.cab87_video_plane_settings

		layout.operator(CAB87_OT_pick_video_plane.bl_idname, icon="FILE_MOVIE")
		layout.prop(settings, "video_path")
		layout.operator(CAB87_OT_create_video_plane_from_path.bl_idname, icon="ADD")

		box = layout.box()
		box.label(text="Plane")
		box.prop(settings, "fit_dimension")
		box.prop(settings, "fit_size")
		box.prop(settings, "fallback_width")
		box.prop(settings, "fallback_height")

		box = layout.box()
		box.label(text="Placement")
		box.prop(settings, "placement")
		if settings.placement == "CAMERA":
			box.prop(settings, "camera_distance")
		else:
			box.prop(settings, "cursor_orientation")

		box = layout.box()
		box.label(text="Material")
		box.prop(settings, "shader_mode")
		if settings.shader_mode == "EMISSION":
			box.prop(settings, "emission_strength")
		box.prop(settings, "use_alpha")
		box.prop(settings, "auto_refresh")
		box.prop(settings, "use_cyclic")

		box = layout.box()
		box.label(text="Timeline")
		box.prop(settings, "frame_start")
		box.prop(settings, "sync_timeline")

		box = layout.box()
		box.label(text="Resolve/FCP XML")
		box.operator(CAB87_OT_pick_xml_video_grid.bl_idname, icon="FILE_FOLDER")
		box.prop(settings, "xml_path")
		box.operator(CAB87_OT_import_xml_video_grid_from_path.bl_idname, icon="SEQ_STRIP_DUPLICATE")
		box.prop(settings, "xml_media_root")
		box.prop(settings, "xml_grid_columns")
		box.prop(settings, "xml_grid_gap")
		box.prop(settings, "xml_clear_previous")
		box.prop(settings, "xml_add_markers")

		box = layout.box()
		box.label(text="XML Camera")
		box.prop(settings, "xml_animate_camera")
		if settings.xml_animate_camera:
			box.prop(settings, "xml_camera_name")
			box.prop(settings, "xml_camera_distance")
			box.prop(settings, "xml_camera_lens")
			box.prop(settings, "xml_camera_interpolation")


def create_and_report(operator, context, settings: CAB87_VideoPlaneSettings, filepath: str):
	try:
		result = create_video_plane(context, settings, filepath)
	except Exception as error:
		operator.report({"ERROR"}, f"Could not create video plane: {error}")
		return {"CANCELLED"}

	object_name = result["object"].name
	source_width = result["source_width"]
	source_height = result["source_height"]
	message = f"Created {object_name} from {source_width}x{source_height} video."
	if result["used_fallback"]:
		message = f"{message} Used fallback dimensions."
	operator.report({"INFO"}, message)
	return {"FINISHED"}


def import_xml_and_report(operator, context, settings: CAB87_VideoPlaneSettings, filepath: str):
	try:
		result = import_xml_video_grid(context, settings, filepath)
	except Exception as error:
		operator.report({"ERROR"}, f"Could not import XML grid: {error}")
		return {"CANCELLED"}

	created_count = len(result["clips"])
	missing_count = len(result["missing_media"])
	if created_count == 0:
		operator.report({"ERROR"}, "XML parsed, but no video planes were created. Check media paths.")
		return {"CANCELLED"}

	message = f"Imported {created_count} XML video clips into {result['collection'].name}."
	if result["camera"] is not None:
		message = f"{message} Animated {result['camera'].name}."
	if missing_count > 0:
		message = f"{message} Skipped {missing_count} missing media file(s)."
		operator.report({"WARNING"}, message)
	else:
		operator.report({"INFO"}, message)
	return {"FINISHED"}


def import_xml_video_grid(context, settings: CAB87_VideoPlaneSettings, filepath: str):
	xml_path = bpy.path.abspath(filepath)
	if not Path(xml_path).is_file():
		raise FileNotFoundError(xml_path)

	sequence = parse_xmeml_sequence(xml_path, settings)
	if not sequence.clips:
		raise ValueError("No enabled video clipitems with media paths were found.")

	if settings.xml_clear_previous:
		clear_previous_xml_import(context.scene)

	root_collection = ensure_video_collection(context)
	sequence_slug = slug(sequence.name) or "Sequence"
	xml_collection = bpy.data.collections.new(unique_name(f"{XML_COLLECTION_PREFIX}_{sequence_slug}", bpy.data.collections))
	root_collection.children.link(xml_collection)

	columns = int(settings.xml_grid_columns)
	if columns <= 0:
		columns = max(1, math.ceil(math.sqrt(len(sequence.clips))))
	rows = math.ceil(len(sequence.clips) / columns)

	plane_sizes = [resolve_plane_dimensions(max(1, clip.source_width), max(1, clip.source_height), settings) for clip in sequence.clips]
	cell_width = max(width for width, _height in plane_sizes) + settings.xml_grid_gap
	cell_height = max(height for _width, height in plane_sizes) + settings.xml_grid_gap

	imported_clips = []
	missing_media = []
	for index, clip in enumerate(sequence.clips):
		media_path = resolve_xml_media_path(clip.filepath, settings.xml_media_root)
		if not Path(bpy.path.abspath(media_path)).is_file():
			missing_media.append(media_path)
			continue

		column = index % columns
		row = index // columns
		x = (column - (columns - 1) * 0.5) * cell_width
		z = ((rows - 1) * 0.5 - row) * cell_height
		position = Vector((x, 0.0, z))
		timing = build_clip_timing(clip, settings.frame_start)
		metadata = {
			"xml_clip_id": clip.clip_id,
			"xml_clip_name": clip.name,
			"xml_track_index": clip.track_index,
			"xml_timeline_start": clip.timeline_start,
			"xml_timeline_end": clip.timeline_end,
			"xml_source_in": clip.source_in,
			"xml_source_out": clip.source_out,
			"xml_source_start": timing["source_start"],
			"xml_source_end": timing["source_end"],
			"xml_speed_multiplier": timing["speed_multiplier"],
		}
		result = create_video_plane(
			context,
			settings,
			media_path,
			collection=xml_collection,
			position=position,
			rotation_euler=(math.radians(90.0), 0.0, 0.0),
			fallback_dimensions=(clip.source_width, clip.source_height),
			timing=timing,
			metadata=metadata,
			select_object=False,
		)

		obj = result["object"]
		obj.name = unique_name(f"Cab87XmlClip_{index + 1:03d}_{slug(clip.name) or 'Clip'}", bpy.data.objects)
		imported_clips.append({"clip": clip, "object": obj, "timing": timing})

	if settings.sync_timeline and sequence.duration > 0:
		context.scene.frame_start = settings.frame_start
		context.scene.frame_end = settings.frame_start + sequence.duration - 1

	if settings.xml_add_markers:
		add_xml_cut_markers(context.scene, imported_clips)

	camera = None
	if settings.xml_animate_camera and imported_clips:
		camera = animate_xml_camera(context, settings, xml_collection, imported_clips)

	if imported_clips:
		for item in imported_clips:
			item["object"].select_set(True)
		context.view_layer.objects.active = imported_clips[0]["object"]

	return {
		"sequence": sequence,
		"collection": xml_collection,
		"clips": imported_clips,
		"missing_media": missing_media,
		"camera": camera,
	}


def parse_xmeml_sequence(filepath: str, settings: CAB87_VideoPlaneSettings) -> XmlSequence:
	tree = ET.parse(filepath)
	root = tree.getroot()
	sequence_element = root.find("sequence")
	if sequence_element is None:
		sequence_element = root.find(".//sequence")
	if sequence_element is None:
		raise ValueError("XML does not contain a sequence element.")

	file_lookup = build_xml_file_lookup(root)
	name = read_text(sequence_element, "name", "XML Sequence")
	timebase = read_int(sequence_element.find("rate"), "timebase", 30)
	duration = read_int(sequence_element, "duration", 0)
	width = read_int(sequence_element.find("./media/video/format/samplecharacteristics"), "width", settings.fallback_width)
	height = read_int(sequence_element.find("./media/video/format/samplecharacteristics"), "height", settings.fallback_height)

	clips: list[XmlVideoClip] = []
	video_element = sequence_element.find("./media/video")
	if video_element is not None:
		for track_index, track_element in enumerate(video_element.findall("track"), start=1):
			for clip_element in track_element.findall("clipitem"):
				if not read_bool(clip_element, "enabled", True):
					continue
				clip = parse_xml_video_clip(clip_element, file_lookup, track_index, width, height)
				if clip is not None:
					clips.append(clip)

	clips.sort(key=lambda item: (item.timeline_start, item.track_index, item.clip_id))
	if duration <= 0 and clips:
		duration = max(clip.timeline_end for clip in clips)

	return XmlSequence(name=name, duration=duration, timebase=timebase, width=width, height=height, clips=clips)


def build_xml_file_lookup(root) -> dict[str, dict]:
	file_lookup = {}
	for file_element in root.findall(".//file"):
		file_id = file_element.get("id")
		if not file_id:
			continue
		info = read_xml_file_info(file_element)
		if info["path"]:
			file_lookup[file_id] = info
	return file_lookup


def parse_xml_video_clip(clip_element, file_lookup: dict[str, dict], track_index: int, sequence_width: int, sequence_height: int) -> XmlVideoClip | None:
	start = read_int(clip_element, "start", -1)
	end = read_int(clip_element, "end", -1)
	if start < 0 or end <= start:
		return None

	file_element = clip_element.find("file")
	if file_element is None:
		return None

	file_info = read_xml_file_info(file_element)
	file_id = file_element.get("id")
	if not file_info["path"] and file_id in file_lookup:
		file_info = file_lookup[file_id]
	if not file_info["path"]:
		return None

	name = read_text(clip_element, "name", file_info["name"] or "Clip")
	source_in = read_float(clip_element, "in", 0.0)
	source_out = read_float(clip_element, "out", source_in + (end - start))
	source_width = int(file_info["width"] or sequence_width)
	source_height = int(file_info["height"] or sequence_height)

	return XmlVideoClip(
		clip_id=clip_element.get("id", name),
		name=name,
		filepath=pathurl_to_path(file_info["path"]),
		timeline_start=start,
		timeline_end=end,
		source_in=source_in,
		source_out=source_out,
		source_width=source_width,
		source_height=source_height,
		track_index=track_index,
		time_remap=parse_time_remap(clip_element),
	)


def read_xml_file_info(file_element) -> dict:
	return {
		"name": read_text(file_element, "name", ""),
		"path": read_text(file_element, "pathurl", ""),
		"width": read_int(file_element.find("./media/video/samplecharacteristics"), "width", 0),
		"height": read_int(file_element.find("./media/video/samplecharacteristics"), "height", 0),
		"duration": read_int(file_element, "duration", 0),
	}


def parse_time_remap(clip_element) -> TimeRemapInfo | None:
	for filter_element in clip_element.findall("filter"):
		effect_element = filter_element.find("effect")
		if effect_element is None:
			continue
		effect_id = read_text(effect_element, "effectid", "").lower()
		effect_name = read_text(effect_element, "name", "").lower()
		if effect_id != "timeremap" and "time remap" not in effect_name:
			continue

		info = TimeRemapInfo()
		for parameter in effect_element.findall("parameter"):
			parameter_id = read_text(parameter, "parameterid", "").lower()
			parameter_name = read_text(parameter, "name", "").lower()
			key = parameter_id or parameter_name
			if key == "speed":
				info.speed_percent = read_float(parameter, "value", 100.0)
			elif key == "reverse":
				info.reverse = read_bool(parameter, "value", False)
			elif key == "graphdict":
				info.keyframes = read_time_remap_keyframes(parameter)
		return info
	return None


def read_time_remap_keyframes(parameter) -> list[tuple[float, float]]:
	keyframes = []
	for keyframe in parameter.findall("keyframe"):
		when = read_float(keyframe, "when", 0.0)
		value = read_float(keyframe, "value", when)
		keyframes.append((when, value))
	keyframes.sort(key=lambda item: item[0])
	return keyframes


def build_clip_timing(clip: XmlVideoClip, scene_frame_start: int) -> dict:
	duration = max(1, clip.timeline_end - clip.timeline_start)
	source_start = resolve_displayed_source_at_relative_frame(clip, 0.0, duration)
	source_end = resolve_displayed_source_at_relative_frame(clip, float(duration), duration)
	speed_multiplier = (source_end - source_start) / duration

	frame_start = scene_frame_start + clip.timeline_start
	frame_end = scene_frame_start + clip.timeline_end - 1
	return {
		"frame_start": frame_start,
		"frame_end": frame_end,
		"duration": duration,
		"source_start": source_start,
		"source_end": source_end,
		"speed_multiplier": speed_multiplier,
		"offset_keyframes": build_clip_offset_keyframes(clip, frame_start, duration),
	}


def resolve_remapped_source_frame(clip: XmlVideoClip, source_frame: float) -> float:
	time_remap = clip.time_remap
	if time_remap is None:
		return source_frame
	if time_remap is not None and time_remap.keyframes:
		return interpolate_keyframes(time_remap.keyframes, source_frame)
	return source_frame


def resolve_displayed_source_at_relative_frame(clip: XmlVideoClip, relative_frame: float, timeline_duration: int) -> float:
	time_remap = clip.time_remap
	if time_remap is None:
		source_span = resolve_source_span(clip, timeline_duration)
		return clip.source_in + source_span * (relative_frame / max(1, timeline_duration))

	if time_remap is not None and time_remap.keyframes:
		source_span = resolve_source_span(clip, timeline_duration)
		source_time = clip.source_in + source_span * (relative_frame / max(1, timeline_duration))
		source_frame = resolve_remapped_source_frame(clip, source_time)
	elif time_remap.speed_percent is not None:
		speed_multiplier = time_remap.speed_percent / 100.0
		source_frame = clip.source_in + relative_frame * speed_multiplier
	else:
		source_frame = clip.source_in + relative_frame

	if time_remap.reverse:
		source_frame = clip.source_out - (source_frame - clip.source_in)
	return source_frame


def build_clip_offset_keyframes(clip: XmlVideoClip, frame_start: int, timeline_duration: int) -> list[tuple[int, float]]:
	time_remap = clip.time_remap
	source_span = resolve_source_span(clip, timeline_duration)
	implicit_speed = source_span / max(1, timeline_duration)
	if time_remap is None and abs(implicit_speed - 1.0) <= 0.001:
		return []

	samples: list[float] = [0.0]
	if time_remap is not None and time_remap.keyframes:
		for when, _value in time_remap.keyframes:
			if when <= clip.source_in or when >= clip.source_out:
				continue
			relative_frame = ((when - clip.source_in) / source_span) * timeline_duration
			if 0.0 < relative_frame < timeline_duration - 1:
				samples.append(relative_frame)
	if timeline_duration > 1:
		samples.append(float(timeline_duration - 1))

	keyframes_by_frame: dict[int, float] = {}
	for relative_frame in sorted(samples):
		scene_frame = frame_start + int(round(relative_frame))
		displayed_source = resolve_displayed_source_at_relative_frame(clip, relative_frame, timeline_duration)
		keyframes_by_frame[scene_frame] = displayed_source - relative_frame
	return sorted(keyframes_by_frame.items())


def resolve_source_span(clip: XmlVideoClip, timeline_duration: int) -> float:
	source_span = clip.source_out - clip.source_in
	if source_span <= 0:
		return float(timeline_duration)
	return source_span


def interpolate_keyframes(keyframes: list[tuple[float, float]], frame: float) -> float:
	if not keyframes:
		return frame
	if frame <= keyframes[0][0]:
		return keyframes[0][1]
	for index in range(1, len(keyframes)):
		left_when, left_value = keyframes[index - 1]
		right_when, right_value = keyframes[index]
		if frame <= right_when:
			span = right_when - left_when
			if span == 0:
				return right_value
			alpha = (frame - left_when) / span
			return left_value + (right_value - left_value) * alpha
	return keyframes[-1][1]


def pathurl_to_path(pathurl: str) -> str:
	if not pathurl:
		return ""
	parsed = urlparse(pathurl)
	if parsed.scheme.lower() != "file":
		return unquote(pathurl)

	path = unquote(parsed.path or "")
	if parsed.netloc and parsed.netloc.lower() != "localhost":
		return f"//{parsed.netloc}{path}"
	if re.match(r"^/[A-Za-z]:/", path):
		path = path[1:]
	return path


def resolve_xml_media_path(filepath: str, media_root: str) -> str:
	if not media_root:
		return filepath
	absolute = bpy.path.abspath(filepath)
	if Path(absolute).is_file():
		return filepath
	filename = path_leaf(filepath)
	if not filename:
		return filepath
	return str(Path(bpy.path.abspath(media_root)) / filename)


def path_leaf(filepath: str) -> str:
	normalized = filepath.replace("\\", "/")
	return Path(normalized).name


def read_text(element, path: str, default: str = "") -> str:
	if element is None:
		return default
	found = element.find(path)
	if found is None or found.text is None:
		return default
	return found.text.strip()


def read_int(element, path: str, default: int = 0) -> int:
	value = read_float(element, path, float(default))
	return int(round(value))


def read_float(element, path: str, default: float = 0.0) -> float:
	text = read_text(element, path, "")
	if text == "":
		return default
	try:
		return float(text)
	except ValueError:
		return default


def read_bool(element, path: str, default: bool = False) -> bool:
	text = read_text(element, path, "")
	if text == "":
		return default
	return text.strip().upper() in {"TRUE", "1", "YES"}


def create_video_plane(
	context,
	settings: CAB87_VideoPlaneSettings,
	filepath: str,
	*,
	collection=None,
	position: Vector | None = None,
	rotation_euler=None,
	fallback_dimensions: tuple[int, int] | None = None,
	timing: dict | None = None,
	metadata: dict | None = None,
	select_object: bool = True,
):
	absolute_path = bpy.path.abspath(filepath)
	if not Path(absolute_path).is_file():
		raise FileNotFoundError(absolute_path)

	image = load_movie_image(absolute_path, settings)
	source_width, source_height, used_fallback = resolve_image_dimensions(image, settings, fallback_dimensions)
	plane_width, plane_height = resolve_plane_dimensions(source_width, source_height, settings)

	stem = slug(Path(absolute_path).stem) or "Video"
	mesh = create_plane_mesh(unique_name(f"Cab87VideoPlane_{stem}_Mesh", bpy.data.meshes), plane_width, plane_height)
	obj = bpy.data.objects.new(unique_name(f"Cab87VideoPlane_{stem}", bpy.data.objects), mesh)
	obj.data.materials.append(create_video_material(unique_name(f"Cab87Video_{stem}_Material", bpy.data.materials), image, settings))

	if collection is None:
		collection = ensure_video_collection(context)
	collection.objects.link(obj)
	if position is None:
		position_video_plane(context, obj, settings)
	else:
		obj.location = position
		obj.rotation_euler = rotation_euler if rotation_euler is not None else (math.radians(90.0), 0.0, 0.0)
	write_video_properties(obj, image, absolute_path, source_width, source_height, plane_width, plane_height)
	if metadata is not None:
		write_xml_clip_properties(obj, metadata)

	if select_object:
		context.view_layer.objects.active = obj
		obj.select_set(True)
		for other in context.selected_objects:
			if other != obj:
				other.select_set(False)

	if timing is None:
		duration = configure_movie_timing(context.scene, image, obj.active_material, settings)
	else:
		duration = configure_clip_movie_timing(context.scene, image, obj.active_material, settings, timing)

	return {
		"object": obj,
		"image": image,
		"source_width": source_width,
		"source_height": source_height,
		"used_fallback": used_fallback,
		"duration": duration,
	}


def load_movie_image(filepath: str, settings: CAB87_VideoPlaneSettings):
	image = bpy.data.images.load(filepath, check_existing=True)
	try:
		image.source = "MOVIE"
	except TypeError:
		pass
	except ValueError:
		pass

	if hasattr(image, "use_auto_refresh"):
		image.use_auto_refresh = settings.auto_refresh
	if hasattr(image, "use_cyclic"):
		image.use_cyclic = settings.use_cyclic
	return image


def resolve_image_dimensions(
	image,
	settings: CAB87_VideoPlaneSettings,
	fallback_dimensions: tuple[int, int] | None = None,
) -> tuple[int, int, bool]:
	width = 0
	height = 0
	if getattr(image, "size", None) and len(image.size) >= 2:
		width = int(image.size[0])
		height = int(image.size[1])

	if width > 0 and height > 0:
		return width, height, False

	if fallback_dimensions is not None and fallback_dimensions[0] > 0 and fallback_dimensions[1] > 0:
		return int(fallback_dimensions[0]), int(fallback_dimensions[1]), True

	return int(settings.fallback_width), int(settings.fallback_height), True


def resolve_plane_dimensions(source_width: int, source_height: int, settings: CAB87_VideoPlaneSettings) -> tuple[float, float]:
	aspect = source_width / source_height
	if settings.fit_dimension == "HEIGHT":
		height = settings.fit_size
		width = height * aspect
	else:
		width = settings.fit_size
		height = width / aspect
	return width, height


def create_plane_mesh(name: str, width: float, height: float):
	half_width = width * 0.5
	half_height = height * 0.5
	mesh = bpy.data.meshes.new(name)
	mesh.from_pydata(
		[
			(-half_width, -half_height, 0.0),
			(half_width, -half_height, 0.0),
			(half_width, half_height, 0.0),
			(-half_width, half_height, 0.0),
		],
		[],
		[(0, 1, 2, 3)],
	)
	mesh.update()

	uv_layer = mesh.uv_layers.new(name="VideoUV")
	for loop_index, uv in enumerate(((0.0, 0.0), (1.0, 0.0), (1.0, 1.0), (0.0, 1.0))):
		uv_layer.data[loop_index].uv = uv
	return mesh


def create_video_material(name: str, image, settings: CAB87_VideoPlaneSettings):
	material = bpy.data.materials.new(name)
	material.use_nodes = True
	material.diffuse_color = (1.0, 1.0, 1.0, 1.0)
	if hasattr(material, "use_backface_culling"):
		material.use_backface_culling = False
	if hasattr(material, "show_transparent_back"):
		material.show_transparent_back = True
	if settings.use_alpha:
		set_first_supported_enum(material, "blend_method", ("BLEND", "HASHED", "CLIP"))

	nodes = material.node_tree.nodes
	links = material.node_tree.links
	nodes.clear()

	output = nodes.new("ShaderNodeOutputMaterial")
	output.location = (500.0, 0.0)
	texture = nodes.new("ShaderNodeTexImage")
	texture.location = (-450.0, 100.0)
	texture.image = image
	texture.extension = "CLIP"
	configure_image_user(texture.image_user, image, settings)

	if settings.shader_mode == "PRINCIPLED":
		shader = nodes.new("ShaderNodeBsdfPrincipled")
		shader.location = (120.0, 0.0)
		link_if_present(links, texture.outputs, "Color", shader.inputs, "Base Color")
		link_if_present(links, texture.outputs, "Alpha", shader.inputs, "Alpha")
		shader_output = shader.outputs.get("BSDF")
	else:
		shader = nodes.new("ShaderNodeEmission")
		shader.location = (120.0, 0.0)
		link_if_present(links, texture.outputs, "Color", shader.inputs, "Color")
		if "Strength" in shader.inputs:
			shader.inputs["Strength"].default_value = settings.emission_strength
		shader_output = shader.outputs.get("Emission")

	if settings.use_alpha and shader_output is not None:
		transparent = nodes.new("ShaderNodeBsdfTransparent")
		transparent.location = (120.0, -180.0)
		mix = nodes.new("ShaderNodeMixShader")
		mix.location = (330.0, 0.0)
		link_if_present(links, texture.outputs, "Alpha", mix.inputs, "Fac")
		links.new(transparent.outputs["BSDF"], mix.inputs[1])
		links.new(shader_output, mix.inputs[2])
		links.new(mix.outputs["Shader"], output.inputs["Surface"])
	elif shader_output is not None:
		links.new(shader_output, output.inputs["Surface"])

	return material


def configure_movie_timing(scene, image, material, settings: CAB87_VideoPlaneSettings) -> int:
	duration = get_movie_duration(image)
	for node in material.node_tree.nodes:
		if node.bl_idname == "ShaderNodeTexImage" and node.image == image:
			configure_image_user(node.image_user, image, settings, duration)

	if settings.sync_timeline and duration > 0:
		scene.frame_start = settings.frame_start
		scene.frame_end = settings.frame_start + duration - 1
	return duration


def configure_clip_movie_timing(scene, image, material, settings: CAB87_VideoPlaneSettings, timing: dict) -> int:
	duration = max(1, int(timing.get("duration", 1)))
	source_start = int(round(float(timing.get("source_start", 0.0))))
	frame_start = int(timing.get("frame_start", settings.frame_start))
	offset_keyframes = timing.get("offset_keyframes", [])

	for node in material.node_tree.nodes:
		if node.bl_idname != "ShaderNodeTexImage" or node.image != image:
			continue

		configure_image_user(node.image_user, image, settings, duration)
		assign_if_available(node.image_user, "frame_start", frame_start)
		assign_if_available(node.image_user, "frame_duration", duration)
		assign_if_available(node.image_user, "frame_offset", source_start)

		if len(offset_keyframes) > 1 and has_offset_animation(offset_keyframes):
			keyframe_image_offsets(node.image_user, offset_keyframes)

	return duration


def configure_image_user(image_user, image, settings: CAB87_VideoPlaneSettings, duration: int | None = None) -> None:
	if image_user is None:
		return
	if duration is None:
		duration = get_movie_duration(image)

	assign_if_available(image_user, "frame_start", settings.frame_start)
	if duration > 0:
		assign_if_available(image_user, "frame_duration", duration)
	assign_if_available(image_user, "use_auto_refresh", settings.auto_refresh)
	assign_if_available(image_user, "use_cyclic", settings.use_cyclic)


def get_movie_duration(image) -> int:
	for property_name in ("frame_duration", "frames"):
		try:
			value = int(getattr(image, property_name, 0) or 0)
		except TypeError:
			value = 0
		if value > 0:
			return value
	return 0


def keyframe_image_offsets(image_user, offset_keyframes: list[tuple[int, float]]) -> None:
	if image_user is None or not hasattr(image_user, "frame_offset"):
		return
	try:
		for frame, frame_offset in offset_keyframes:
			image_user.frame_offset = int(round(frame_offset))
			image_user.keyframe_insert(data_path="frame_offset", frame=frame)
	except Exception:
		return

	try:
		action = image_user.id_data.animation_data.action
	except AttributeError:
		return
	if action is None:
		return
	for fcurve in action.fcurves:
		if "frame_offset" not in fcurve.data_path:
			continue
		for keyframe in fcurve.keyframe_points:
			if int(round(keyframe.co.x)) in {frame for frame, _offset in offset_keyframes}:
				keyframe.interpolation = "LINEAR"


def has_offset_animation(offset_keyframes: list[tuple[int, float]]) -> bool:
	first_offset = offset_keyframes[0][1]
	return any(abs(frame_offset - first_offset) > 0.001 for _frame, frame_offset in offset_keyframes[1:])


def position_video_plane(context, obj, settings: CAB87_VideoPlaneSettings) -> None:
	if settings.placement == "CAMERA":
		camera = context.scene.camera
		if camera is None:
			raise ValueError("Active Camera placement requires a scene camera.")
		forward = camera.matrix_world.to_quaternion() @ Vector((0.0, 0.0, -1.0))
		obj.location = camera.location + forward * settings.camera_distance
		obj.rotation_euler = camera.rotation_euler
		return

	obj.location = context.scene.cursor.location
	if settings.cursor_orientation == "FRONT":
		obj.rotation_euler = (math.radians(90.0), 0.0, 0.0)
	else:
		obj.rotation_euler = (0.0, 0.0, 0.0)


def ensure_video_collection(context):
	collection = bpy.data.collections.get(COLLECTION_NAME)
	if collection is None:
		collection = bpy.data.collections.new(COLLECTION_NAME)

	if collection.name not in {child.name for child in context.scene.collection.children}:
		context.scene.collection.children.link(collection)
	return collection


def clear_previous_xml_import(scene=None) -> None:
	for obj in list(bpy.data.objects):
		if obj.get("cab87_xml_import"):
			bpy.data.objects.remove(obj, do_unlink=True)
	for collection in list(bpy.data.collections):
		if collection.name.startswith(XML_COLLECTION_PREFIX) and not collection.objects and not collection.children:
			bpy.data.collections.remove(collection)
	if scene is not None:
		for marker in list(scene.timeline_markers):
			if marker.name.startswith("Cab87 XML "):
				scene.timeline_markers.remove(marker)


def add_xml_cut_markers(scene, imported_clips: list[dict]) -> None:
	for item in imported_clips:
		clip = item["clip"]
		timing = item["timing"]
		marker_name = f"Cab87 XML {clip.timeline_start:05d} {clip.name}"
		scene.timeline_markers.new(marker_name[:63], frame=timing["frame_start"])


def animate_xml_camera(context, settings: CAB87_VideoPlaneSettings, collection, imported_clips: list[dict]):
	camera = bpy.data.objects.get(settings.xml_camera_name)
	if camera is None or camera.type != "CAMERA":
		camera_data = bpy.data.cameras.new(unique_name(f"{settings.xml_camera_name}_Data", bpy.data.cameras))
		camera = bpy.data.objects.new(settings.xml_camera_name, camera_data)
		collection.objects.link(camera)
	elif camera.name not in {obj.name for obj in collection.objects}:
		collection.objects.link(camera)

	camera["cab87_xml_import"] = True
	camera["cab87_xml_import_camera"] = True
	camera.data.lens = settings.xml_camera_lens
	camera.animation_data_clear()

	for item in imported_clips:
		frame = item["timing"]["frame_start"]
		location, rotation = camera_pose_for_plane(item["object"], settings.xml_camera_distance)
		camera.location = location
		camera.rotation_euler = rotation
		camera.keyframe_insert(data_path="location", frame=frame)
		camera.keyframe_insert(data_path="rotation_euler", frame=frame)

	set_object_keyframe_interpolation(camera, settings.xml_camera_interpolation)
	context.scene.camera = camera
	return camera


def camera_pose_for_plane(obj, distance: float) -> tuple[Vector, object]:
	target = obj.location.copy()
	normal = obj.matrix_world.to_quaternion() @ Vector((0.0, 0.0, 1.0))
	if normal.length == 0.0:
		normal = Vector((0.0, -1.0, 0.0))
	else:
		normal.normalize()
	location = target + normal * distance
	direction = target - location
	rotation = direction.to_track_quat("-Z", "Y").to_euler()
	return location, rotation


def set_object_keyframe_interpolation(obj, interpolation: str) -> None:
	if obj.animation_data is None or obj.animation_data.action is None:
		return
	for fcurve in obj.animation_data.action.fcurves:
		for keyframe in fcurve.keyframe_points:
			keyframe.interpolation = interpolation


def write_video_properties(obj, image, filepath: str, source_width: int, source_height: int, plane_width: float, plane_height: float) -> None:
	obj["cab87_video_plane"] = True
	obj["cab87_video_path"] = filepath
	obj["cab87_video_image"] = image.name
	obj["cab87_source_width"] = source_width
	obj["cab87_source_height"] = source_height
	obj["cab87_plane_width"] = plane_width
	obj["cab87_plane_height"] = plane_height
	obj["cab87_aspect_ratio"] = source_width / source_height


def write_xml_clip_properties(obj, metadata: dict) -> None:
	obj["cab87_xml_import"] = True
	for key, value in metadata.items():
		obj[f"cab87_{key}"] = value


def link_if_present(links, outputs, output_name: str, inputs, input_name: str) -> None:
	if output_name in outputs and input_name in inputs:
		links.new(outputs[output_name], inputs[input_name])


def assign_if_available(owner, property_name: str, value) -> None:
	if not hasattr(owner, property_name):
		return
	try:
		setattr(owner, property_name, value)
	except TypeError:
		pass
	except ValueError:
		pass


def set_first_supported_enum(owner, property_name: str, candidates: tuple[str, ...]) -> None:
	for candidate in candidates:
		try:
			setattr(owner, property_name, candidate)
			return
		except TypeError:
			continue
		except ValueError:
			continue


def unique_name(base: str, registry) -> str:
	if registry.get(base) is None:
		return base
	index = 2
	while True:
		candidate = f"{base}_{index:03d}"
		if registry.get(candidate) is None:
			return candidate
		index += 1


def slug(value: str) -> str:
	value = re.sub(r"[^A-Za-z0-9_]+", "_", value.strip())
	value = re.sub(r"_+", "_", value).strip("_")
	return value[:48]


classes = (
	CAB87_VideoPlaneSettings,
	CAB87_OT_pick_video_plane,
	CAB87_OT_create_video_plane_from_path,
	CAB87_OT_pick_xml_video_grid,
	CAB87_OT_import_xml_video_grid_from_path,
	CAB87_PT_video_plane_panel,
)


def register():
	for cls in classes:
		bpy.utils.register_class(cls)
	bpy.types.Scene.cab87_video_plane_settings = PointerProperty(type=CAB87_VideoPlaneSettings)


def unregister():
	del bpy.types.Scene.cab87_video_plane_settings
	for cls in reversed(classes):
		bpy.utils.unregister_class(cls)


if __name__ == "__main__":
	register()
