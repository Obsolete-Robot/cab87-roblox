bl_info = {
	"name": "Cab87 Video Plane Tool",
	"author": "Cab87",
	"version": (0, 1, 0),
	"blender": (3, 6, 0),
	"location": "View3D > Sidebar > Cab87 > Video Plane",
	"description": "Create an aspect-ratio plane with a movie texture material.",
	"category": "Import-Export",
}

import math
from pathlib import Path
import re

import bpy
from bpy.props import BoolProperty, EnumProperty, FloatProperty, IntProperty, PointerProperty, StringProperty
from bpy.types import Operator, Panel, PropertyGroup
from bpy_extras.io_utils import ImportHelper
from mathutils import Vector


ADDON_VERSION = ".".join(str(part) for part in bl_info["version"])
COLLECTION_NAME = "Cab87VideoPlanes"
VIDEO_FILTER = "*.mp4;*.mov;*.m4v;*.avi;*.mkv;*.webm;*.mpg;*.mpeg"


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


def create_video_plane(context, settings: CAB87_VideoPlaneSettings, filepath: str):
	absolute_path = bpy.path.abspath(filepath)
	if not Path(absolute_path).is_file():
		raise FileNotFoundError(absolute_path)

	image = load_movie_image(absolute_path, settings)
	source_width, source_height, used_fallback = resolve_image_dimensions(image, settings)
	plane_width, plane_height = resolve_plane_dimensions(source_width, source_height, settings)

	stem = slug(Path(absolute_path).stem) or "Video"
	mesh = create_plane_mesh(unique_name(f"Cab87VideoPlane_{stem}_Mesh", bpy.data.meshes), plane_width, plane_height)
	obj = bpy.data.objects.new(unique_name(f"Cab87VideoPlane_{stem}", bpy.data.objects), mesh)
	obj.data.materials.append(create_video_material(unique_name(f"Cab87Video_{stem}_Material", bpy.data.materials), image, settings))

	collection = ensure_video_collection(context)
	collection.objects.link(obj)
	position_video_plane(context, obj, settings)
	write_video_properties(obj, image, absolute_path, source_width, source_height, plane_width, plane_height)

	context.view_layer.objects.active = obj
	obj.select_set(True)
	for other in context.selected_objects:
		if other != obj:
			other.select_set(False)

	duration = configure_movie_timing(context.scene, image, obj.active_material, settings)

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


def resolve_image_dimensions(image, settings: CAB87_VideoPlaneSettings) -> tuple[int, int, bool]:
	width = 0
	height = 0
	if getattr(image, "size", None) and len(image.size) >= 2:
		width = int(image.size[0])
		height = int(image.size[1])

	if width > 0 and height > 0:
		return width, height, False

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


def write_video_properties(obj, image, filepath: str, source_width: int, source_height: int, plane_width: float, plane_height: float) -> None:
	obj["cab87_video_plane"] = True
	obj["cab87_video_path"] = filepath
	obj["cab87_video_image"] = image.name
	obj["cab87_source_width"] = source_width
	obj["cab87_source_height"] = source_height
	obj["cab87_plane_width"] = plane_width
	obj["cab87_plane_height"] = plane_height
	obj["cab87_aspect_ratio"] = source_width / source_height


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
