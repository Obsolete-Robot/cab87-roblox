bl_info = {
	"name": "Cab87 Beat Maker",
	"author": "Cab87",
	"version": (0, 2, 1),
	"blender": (3, 6, 0),
	"location": "View3D > Sidebar > Cab87 > Beat Maker",
	"description": "Detect major kick beats from a drum stem and animate camera beat pulses.",
	"category": "Animation",
}

from pathlib import Path
import math
import os
import subprocess
import tempfile

import bpy
from bpy.props import BoolProperty, EnumProperty, FloatProperty, IntProperty, PointerProperty, StringProperty
from bpy.types import Object, Operator, Panel, PropertyGroup
from bpy_extras.io_utils import ImportHelper

from .audio_analysis import AudioDecodeError, SUPPORTED_EXTENSIONS, detect_bass_beats, load_audio_mono


ADDON_ID = "cab87_beat_maker"
ADDON_VERSION = ".".join(str(part) for part in bl_info["version"])
AUDIO_FILTER = "*.wav;*.aif;*.aiff;*.aifc;*.mp3;*.flac;*.ogg;*.m4a"
BEAT_STRIP_PREFIX = "BeatMaker_DrumStem"
MARKER_PREFIX_DEFAULT = "Kick"
POSITION_AXIS_ITEMS = (
	("X", "X", "Animate the camera X location on each beat."),
	("Y", "Y", "Animate the camera Y location on each beat."),
	("Z", "Z", "Animate the camera Z location on each beat."),
)
POSITION_AXIS_INDEX = {"X": 0, "Y": 1, "Z": 2}


def camera_object_poll(_self, obj: Object) -> bool:
	return obj is not None and obj.type == "CAMERA"


class CAB87_BeatMakerSettings(PropertyGroup):
	audio_path: StringProperty(
		name="Drum Stem",
		description="Audio file to analyze. Use an isolated drum stem for best major kick detection.",
		subtype="FILE_PATH",
	)
	camera_object: PointerProperty(
		name="Camera",
		description="Camera to animate. Falls back to the active scene camera.",
		type=Object,
		poll=camera_object_poll,
	)

	animate_fov: BoolProperty(
		name="Animate FOV",
		description="Keyframe camera FOV pulses on detected major beat frames.",
		default=True,
	)
	default_fov: FloatProperty(
		name="Default FOV",
		description="Camera FOV before and after each beat pulse.",
		subtype="ANGLE",
		unit="ROTATION",
		default=math.radians(50.0),
		min=math.radians(1.0),
		max=math.radians(175.0),
	)
	beat_fov: FloatProperty(
		name="Beat FOV",
		description="Camera FOV on each detected major beat frame.",
		subtype="ANGLE",
		unit="ROTATION",
		default=math.radians(68.0),
		min=math.radians(1.0),
		max=math.radians(175.0),
	)
	frames_to_beat: IntProperty(
		name="Frames To Beat",
		description="Number of frames before each beat used to key the Default FOV.",
		default=2,
		min=0,
		soft_max=24,
	)
	settle_frames: IntProperty(
		name="Settle Frames",
		description="Number of frames after each beat before returning to Default FOV.",
		default=10,
		min=1,
		soft_max=60,
	)
	start_frame: IntProperty(
		name="Audio Start Frame",
		description="Timeline frame where the audio stem starts.",
		default=1,
		min=1,
	)
	interpolation: EnumProperty(
		name="Interpolation",
		items=(
			("BEZIER", "Bezier", "Smooth camera FOV pulse."),
			("LINEAR", "Linear", "Straight interpolation between FOV keyframes."),
			("SINE", "Sine", "Sine easing when supported by this Blender version."),
			("QUAD", "Quad", "Quadratic easing when supported by this Blender version."),
		),
		default="BEZIER",
	)
	clear_existing_fov: BoolProperty(
		name="Replace FOV Animation",
		description="Remove existing FOV keyframes from the target camera before adding beat pulses.",
		default=True,
	)
	animate_position: BoolProperty(
		name="Animate Position",
		description="Keyframe one camera location axis on detected major beat frames.",
		default=False,
	)
	position_axis: EnumProperty(
		name="Position Axis",
		description="Camera location axis to pulse on each detected major beat.",
		items=POSITION_AXIS_ITEMS,
		default="Z",
	)
	default_position: FloatProperty(
		name="Default Pos",
		description="Camera location value on the selected axis before and after each beat pulse.",
		subtype="DISTANCE",
		unit="LENGTH",
		default=0.0,
	)
	beat_position: FloatProperty(
		name="Beat Pos",
		description="Camera location value on the selected axis at each detected major beat frame.",
		subtype="DISTANCE",
		unit="LENGTH",
		default=0.5,
	)
	clear_existing_position: BoolProperty(
		name="Replace Position Animation",
		description="Remove existing location keyframes on the selected axis before adding beat pulses.",
		default=True,
	)
	sync_frame_range: BoolProperty(
		name="Extend Scene End",
		description="Extend the scene end frame to include the final beat settle key.",
		default=True,
	)

	lowpass_hz: FloatProperty(
		name="Bass Cutoff",
		description="Approximate low-pass cutoff used to focus detection on kick/bass drum energy.",
		default=160.0,
		min=20.0,
		soft_max=400.0,
	)
	window_ms: FloatProperty(
		name="Window ms",
		description="Analysis energy window length.",
		default=45.0,
		min=5.0,
		soft_max=120.0,
	)
	hop_ms: FloatProperty(
		name="Hop ms",
		description="Analysis step size. Lower values are more precise but slower.",
		default=10.0,
		min=2.0,
		soft_max=40.0,
	)
	sensitivity: FloatProperty(
		name="Sensitivity",
		description="Required bass energy over the local floor. Lower detects more beats.",
		default=1.35,
		min=1.0,
		soft_max=4.0,
	)
	major_percentile: FloatProperty(
		name="Major Beat Percentile",
		description="Keep only stronger candidate beats. Lower values keep more kicks.",
		default=65.0,
		min=0.0,
		max=100.0,
	)
	min_gap_ms: FloatProperty(
		name="Min Beat Gap ms",
		description="Minimum time between accepted major beats.",
		default=220.0,
		min=0.0,
		soft_max=1000.0,
	)
	max_beats: IntProperty(
		name="Max Beats",
		description="Optional cap on accepted beats. Use 0 for no cap.",
		default=0,
		min=0,
		soft_max=1000,
	)

	add_audio_strip: BoolProperty(
		name="Add Audio Strip",
		description="Add the analyzed stem to the Video Sequencer at Audio Start Frame.",
		default=True,
	)
	replace_audio_strip: BoolProperty(
		name="Replace Audio Strip",
		description="Remove previous Beat Maker audio strips before adding this stem.",
		default=True,
	)
	audio_channel: IntProperty(name="Audio Channel", default=1, min=1, soft_max=32)
	audio_volume: FloatProperty(name="Audio Volume", default=1.0, min=0.0, soft_max=2.0)

	create_markers: BoolProperty(
		name="Create Beat Markers",
		description="Create timeline markers on detected major beat frames.",
		default=True,
	)
	replace_markers: BoolProperty(
		name="Replace Beat Markers",
		description="Remove previous Beat Maker markers with the marker prefix before creating new ones.",
		default=True,
	)
	marker_prefix: StringProperty(name="Marker Prefix", default=MARKER_PREFIX_DEFAULT)

	use_ffmpeg: BoolProperty(
		name="Use FFmpeg For Non-WAV",
		description="Convert MP3/FLAC/OGG/M4A to a temporary mono WAV before analysis when ffmpeg is available.",
		default=True,
	)
	ffmpeg_path: StringProperty(
		name="FFmpeg Path",
		description="Path or command name for ffmpeg.",
		default="ffmpeg",
		subtype="FILE_PATH",
	)


class CAB87_OT_pick_beat_audio(Operator, ImportHelper):
	bl_idname = "cab87.pick_beat_audio"
	bl_label = "Choose Drum Stem"
	bl_description = "Choose the drum stem or kick-heavy audio file Beat Maker should analyze."
	bl_options = {"REGISTER", "UNDO"}

	filename_ext = ".wav"
	filter_glob: StringProperty(default=AUDIO_FILTER, options={"HIDDEN"})

	def invoke(self, context, event):
		settings = context.scene.cab87_beat_maker_settings
		if settings.audio_path:
			self.filepath = bpy.path.abspath(settings.audio_path)
		return super().invoke(context, event)

	def execute(self, context):
		context.scene.cab87_beat_maker_settings.audio_path = self.filepath
		self.report({"INFO"}, f"Selected {Path(self.filepath).name}.")
		return {"FINISHED"}


class CAB87_OT_animate_beat_fov(Operator):
	bl_idname = "cab87.animate_beat_fov"
	bl_label = "Animate Beat Camera"
	bl_description = "Detect major bass drum beats and keyframe enabled camera beat pulses."
	bl_options = {"REGISTER", "UNDO"}

	def execute(self, context):
		settings = context.scene.cab87_beat_maker_settings
		if not settings.audio_path:
			self.report({"ERROR"}, "Choose a drum stem first.")
			return {"CANCELLED"}
		if not settings.animate_fov and not settings.animate_position:
			self.report({"ERROR"}, "Enable FOV or Position animation first.")
			return {"CANCELLED"}

		try:
			result = build_beat_animation(context, settings)
		except Exception as error:
			self.report({"ERROR"}, f"Beat Maker failed: {error}")
			return {"CANCELLED"}

		channels = ", ".join(result["animated_channels"])
		self.report(
			{"INFO"},
			f"Animated {result['camera_name']} {channels} on {result['beat_count']} major beats from {Path(result['audio_path']).name}.",
		)
		return {"FINISHED"}


class CAB87_OT_clear_beat_fov(Operator):
	bl_idname = "cab87.clear_beat_fov"
	bl_label = "Clear Beat Animation"
	bl_description = "Remove Beat Maker FOV animation, selected-axis position animation, audio strips, and markers from the current scene."
	bl_options = {"REGISTER", "UNDO"}

	def execute(self, context):
		settings = context.scene.cab87_beat_maker_settings
		camera = resolve_camera(context, settings)
		remove_fov_animation(camera.data)
		remove_location_axis_animation(camera, get_position_axis_index(settings))
		if settings.replace_audio_strip:
			remove_beat_audio_strips(context.scene)
		if settings.replace_markers:
			remove_beat_markers(context.scene, settings.marker_prefix)
		self.report({"INFO"}, f"Cleared Beat Maker data from {camera.name}.")
		return {"FINISHED"}


class CAB87_PT_beat_maker_panel(Panel):
	bl_label = f"Beat Maker v{ADDON_VERSION}"
	bl_idname = "CAB87_PT_beat_maker_panel"
	bl_space_type = "VIEW_3D"
	bl_region_type = "UI"
	bl_category = "Cab87"

	def draw(self, context):
		layout = self.layout
		settings = context.scene.cab87_beat_maker_settings

		layout.operator(CAB87_OT_pick_beat_audio.bl_idname, icon="FILE_SOUND")
		layout.prop(settings, "audio_path")
		layout.prop(settings, "camera_object")
		row = layout.row(align=True)
		row.operator(CAB87_OT_animate_beat_fov.bl_idname, icon="ANIM")
		row.operator(CAB87_OT_clear_beat_fov.bl_idname, icon="TRASH")

		box = layout.box()
		box.label(text="FOV Pulse")
		box.prop(settings, "animate_fov")
		if settings.animate_fov:
			box.prop(settings, "default_fov")
			box.prop(settings, "beat_fov")
			box.prop(settings, "clear_existing_fov")

		box = layout.box()
		box.label(text="Position Pulse")
		box.prop(settings, "animate_position")
		if settings.animate_position:
			box.prop(settings, "position_axis")
			box.prop(settings, "default_position")
			box.prop(settings, "beat_position")
			box.prop(settings, "clear_existing_position")

		box = layout.box()
		box.label(text="Pulse Timing")
		box.prop(settings, "frames_to_beat")
		box.prop(settings, "settle_frames")
		box.prop(settings, "start_frame")
		box.prop(settings, "interpolation")
		box.prop(settings, "sync_frame_range")

		box = layout.box()
		box.label(text="Beat Detection")
		box.prop(settings, "sensitivity")
		box.prop(settings, "major_percentile")
		box.prop(settings, "min_gap_ms")
		box.prop(settings, "max_beats")
		box.prop(settings, "lowpass_hz")
		box.prop(settings, "window_ms")
		box.prop(settings, "hop_ms")

		box = layout.box()
		box.label(text="Timeline")
		box.prop(settings, "add_audio_strip")
		if settings.add_audio_strip:
			box.prop(settings, "replace_audio_strip")
			box.prop(settings, "audio_channel")
			box.prop(settings, "audio_volume")
		box.prop(settings, "create_markers")
		if settings.create_markers:
			box.prop(settings, "replace_markers")
			box.prop(settings, "marker_prefix")

		box = layout.box()
		box.label(text="Format Conversion")
		box.prop(settings, "use_ffmpeg")
		if settings.use_ffmpeg:
			box.prop(settings, "ffmpeg_path")


def build_beat_animation(context, settings: CAB87_BeatMakerSettings) -> dict[str, object]:
	audio_path = bpy.path.abspath(settings.audio_path)
	if not Path(audio_path).is_file():
		raise FileNotFoundError(audio_path)

	camera = resolve_camera(context, settings)
	analysis_path, temporary_path = prepare_analysis_audio(audio_path, settings)
	try:
		audio = load_audio_mono(analysis_path)
	finally:
		if temporary_path is not None:
			try:
				os.remove(temporary_path)
			except OSError:
				pass

	hits = detect_bass_beats(
		audio.samples,
		audio.sample_rate,
		lowpass_hz=settings.lowpass_hz,
		window_ms=settings.window_ms,
		hop_ms=settings.hop_ms,
		sensitivity=settings.sensitivity,
		major_percentile=settings.major_percentile,
		min_gap_ms=settings.min_gap_ms,
		max_beats=settings.max_beats,
	)
	if not hits:
		raise RuntimeError("No major bass drum beats were detected. Try lowering Sensitivity or Major Beat Percentile.")

	beat_frames = [seconds_to_frame(context.scene, settings.start_frame, hit.time_seconds) for hit in hits]
	animated_channels: list[str] = []

	if settings.animate_fov and settings.clear_existing_fov:
		remove_fov_animation(camera.data)
	if settings.animate_fov:
		animate_camera_fov(camera.data, beat_frames, settings)
		animated_channels.append("FOV")

	if settings.animate_position:
		position_axis_index = get_position_axis_index(settings)
		if settings.clear_existing_position:
			remove_location_axis_animation(camera, position_axis_index)
		animate_camera_position_axis(camera, beat_frames, settings, position_axis_index)
		animated_channels.append(f"{settings.position_axis} position")

	if settings.create_markers:
		if settings.replace_markers:
			remove_beat_markers(context.scene, settings.marker_prefix)
		create_beat_markers(context.scene, beat_frames, settings.marker_prefix)

	if settings.add_audio_strip:
		if settings.replace_audio_strip:
			remove_beat_audio_strips(context.scene)
		add_audio_strip(context.scene, audio_path, settings)

	last_frame = max(beat_frames) + settings.settle_frames
	if settings.sync_frame_range:
		context.scene.frame_end = max(context.scene.frame_end, last_frame)

	context.scene["cab87_beat_maker_last_audio"] = audio_path
	context.scene["cab87_beat_maker_last_count"] = len(beat_frames)
	context.scene["cab87_beat_maker_last_first_frame"] = min(beat_frames)
	context.scene["cab87_beat_maker_last_last_frame"] = last_frame

	return {
		"audio_path": audio_path,
		"camera_name": camera.name,
		"beat_count": len(beat_frames),
		"first_frame": min(beat_frames),
		"last_frame": last_frame,
		"animated_channels": animated_channels,
	}


def build_beat_fov_animation(context, settings: CAB87_BeatMakerSettings) -> dict[str, object]:
	return build_beat_animation(context, settings)


def prepare_analysis_audio(audio_path: str, settings: CAB87_BeatMakerSettings) -> tuple[str, str | None]:
	suffix = Path(audio_path).suffix.lower()
	if suffix in SUPPORTED_EXTENSIONS:
		return audio_path, None
	if not settings.use_ffmpeg:
		raise AudioDecodeError("This file type needs FFmpeg conversion or a PCM WAV/AIFF stem.")

	handle = tempfile.NamedTemporaryFile(prefix="cab87_beat_maker_", suffix=".wav", delete=False)
	temporary_path = handle.name
	handle.close()
	command = [
		settings.ffmpeg_path or "ffmpeg",
		"-y",
		"-i",
		audio_path,
		"-ac",
		"1",
		"-ar",
		"22050",
		"-vn",
		temporary_path,
	]
	try:
		subprocess.run(command, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
	except FileNotFoundError as error:
		_cleanup_temp_file(temporary_path)
		raise AudioDecodeError("FFmpeg was not found. Set FFmpeg Path or use a PCM WAV/AIFF stem.") from error
	except subprocess.CalledProcessError as error:
		_cleanup_temp_file(temporary_path)
		message = error.stderr.decode("utf-8", errors="replace").strip().splitlines()
		detail = message[-1] if message else str(error)
		raise AudioDecodeError(f"FFmpeg conversion failed: {detail}") from error
	return temporary_path, temporary_path


def animate_camera_fov(camera_data, beat_frames: list[int], settings: CAB87_BeatMakerSettings) -> None:
	default_fov = settings.default_fov
	beat_fov = settings.beat_fov
	start_frame = settings.start_frame
	keyframes: dict[int, tuple[int, float]] = {}

	def set_key(frame: int, value: float, priority: int) -> None:
		frame = max(start_frame, int(frame))
		existing = keyframes.get(frame)
		if existing is None or priority >= existing[0]:
			keyframes[frame] = (priority, value)

	for beat_frame in beat_frames:
		set_key(beat_frame - settings.frames_to_beat, default_fov, 0)
		set_key(beat_frame, beat_fov, 2)
		set_key(beat_frame + settings.settle_frames, default_fov, 1)

	for frame in sorted(keyframes):
		camera_data.angle = keyframes[frame][1]
		camera_data.keyframe_insert(data_path="angle", frame=frame)

	set_fcurve_interpolation(camera_data, "angle", settings.interpolation)
	if beat_frames:
		camera_data.angle = default_fov


def animate_camera_position_axis(
	camera: Object,
	beat_frames: list[int],
	settings: CAB87_BeatMakerSettings,
	axis_index: int,
) -> None:
	default_position = settings.default_position
	beat_position = settings.beat_position
	start_frame = settings.start_frame
	keyframes: dict[int, tuple[int, float]] = {}

	def set_key(frame: int, value: float, priority: int) -> None:
		frame = max(start_frame, int(frame))
		existing = keyframes.get(frame)
		if existing is None or priority >= existing[0]:
			keyframes[frame] = (priority, value)

	for beat_frame in beat_frames:
		set_key(beat_frame - settings.frames_to_beat, default_position, 0)
		set_key(beat_frame, beat_position, 2)
		set_key(beat_frame + settings.settle_frames, default_position, 1)

	for frame in sorted(keyframes):
		camera.location[axis_index] = keyframes[frame][1]
		camera.keyframe_insert(data_path="location", frame=frame, index=axis_index)

	set_fcurve_interpolation(camera, "location", settings.interpolation, axis_index)
	if beat_frames:
		camera.location[axis_index] = default_position


def resolve_camera(context, settings: CAB87_BeatMakerSettings):
	if settings.camera_object is not None and settings.camera_object.type == "CAMERA":
		return settings.camera_object
	if context.scene.camera is not None:
		return context.scene.camera
	raise RuntimeError("Choose a camera or set an active scene camera.")


def seconds_to_frame(scene, start_frame: int, time_seconds: float) -> int:
	fps = scene.render.fps / scene.render.fps_base
	return int(start_frame + round(time_seconds * fps))


def remove_fov_animation(camera_data) -> None:
	if camera_data.animation_data is None or camera_data.animation_data.action is None:
		return
	action = camera_data.animation_data.action
	for fcurve in list(action.fcurves):
		if fcurve.data_path == "angle":
			action.fcurves.remove(fcurve)


def remove_location_axis_animation(camera: Object, axis_index: int) -> None:
	if camera.animation_data is None or camera.animation_data.action is None:
		return
	action = camera.animation_data.action
	for fcurve in list(action.fcurves):
		if fcurve.data_path == "location" and fcurve.array_index == axis_index:
			action.fcurves.remove(fcurve)


def get_position_axis_index(settings: CAB87_BeatMakerSettings) -> int:
	return POSITION_AXIS_INDEX.get(settings.position_axis, 2)


def set_fcurve_interpolation(owner, data_path: str, interpolation: str, array_index: int | None = None) -> None:
	if owner.animation_data is None or owner.animation_data.action is None:
		return
	for fcurve in owner.animation_data.action.fcurves:
		if fcurve.data_path != data_path:
			continue
		if array_index is not None and fcurve.array_index != array_index:
			continue
		for keyframe in fcurve.keyframe_points:
			try:
				keyframe.interpolation = interpolation
			except TypeError:
				keyframe.interpolation = "BEZIER"
			except ValueError:
				keyframe.interpolation = "BEZIER"


def create_beat_markers(scene, beat_frames: list[int], marker_prefix: str) -> None:
	prefix = marker_prefix.strip() or MARKER_PREFIX_DEFAULT
	for index, frame in enumerate(beat_frames, start=1):
		scene.timeline_markers.new(f"{prefix}_{index:03d}", frame=frame)


def remove_beat_markers(scene, marker_prefix: str) -> None:
	prefix = marker_prefix.strip() or MARKER_PREFIX_DEFAULT
	for marker in list(scene.timeline_markers):
		if marker.name.startswith(f"{prefix}_"):
			scene.timeline_markers.remove(marker)


def add_audio_strip(scene, audio_path: str, settings: CAB87_BeatMakerSettings) -> None:
	if scene.sequence_editor is None:
		scene.sequence_editor_create()
	sequence_editor = scene.sequence_editor
	strip = sequence_editor.sequences.new_sound(
		name=f"{BEAT_STRIP_PREFIX}_{Path(audio_path).stem}",
		filepath=audio_path,
		channel=settings.audio_channel,
		frame_start=settings.start_frame,
	)
	strip.volume = settings.audio_volume


def remove_beat_audio_strips(scene) -> None:
	if scene.sequence_editor is None:
		return
	for strip in list(scene.sequence_editor.sequences_all):
		if strip.name.startswith(BEAT_STRIP_PREFIX):
			scene.sequence_editor.sequences.remove(strip)


def _cleanup_temp_file(path: str) -> None:
	try:
		os.remove(path)
	except OSError:
		pass


classes = (
	CAB87_BeatMakerSettings,
	CAB87_OT_pick_beat_audio,
	CAB87_OT_animate_beat_fov,
	CAB87_OT_clear_beat_fov,
	CAB87_PT_beat_maker_panel,
)


def register():
	for cls in classes:
		bpy.utils.register_class(cls)
	bpy.types.Scene.cab87_beat_maker_settings = PointerProperty(type=CAB87_BeatMakerSettings)


def unregister():
	del bpy.types.Scene.cab87_beat_maker_settings
	for cls in reversed(classes):
		bpy.utils.unregister_class(cls)


if __name__ == "__main__":
	register()
