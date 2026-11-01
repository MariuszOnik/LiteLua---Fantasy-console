"""blender -b -P render.py -- IN.gltf OUT_DIR PREFIX KEY [KEY ...]
KEY = shape key name (e.g. Galopar1_3) or 'base'; applied to every object that has it.
Writes OUT_DIR/PREFIX_KEY.png; the view is framed on the base pose."""
import math, os, sys
import bpy
from mathutils import Vector

args = sys.argv[sys.argv.index("--") + 1:]
src, out, prefix, keys = args[0], args[1], args[2], args[3:]
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=src)
objs = [o for o in bpy.context.scene.objects if o.type == "MESH"]
for o in objs:
    if o.data.shape_keys and o.data.shape_keys.animation_data:
        o.data.shape_keys.animation_data_clear()

pts = [o.matrix_world @ v.co for o in objs for v in o.data.vertices]
lo = Vector([min(p[i] for p in pts) for i in range(3)])
hi = Vector([max(p[i] for p in pts) for i in range(3)])
target = (lo + hi) / 2
size = max(hi - lo)

scene = bpy.context.scene
scene.render.engine = "BLENDER_WORKBENCH"
scene.display.shading.light = "FLAT"
scene.display.shading.color_type = "TEXTURE"
scene.render.resolution_x = scene.render.resolution_y = 900
scene.render.film_transparent = True
cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
scene.collection.objects.link(cam)
scene.camera = cam
cam.data.type = "ORTHO"
cam.data.ortho_scale = size * float(os.environ.get("ZOOM", "1.35"))
a = math.radians(float(os.environ.get("AZ", "-60")))
cam.location = target + Vector((math.cos(a), math.sin(a), float(os.environ.get("EL", "0.35")))) * size * 3
cam.rotation_euler = (target - cam.location).to_track_quat("-Z", "Y").to_euler()

for k in keys:
    for o in objs:
        for b in (o.data.shape_keys.key_blocks if o.data.shape_keys else []):
            b.value = 1.0 if b.name == k else 0.0
    scene.render.filepath = os.path.join(out, f"{prefix}_{k}.png")
    bpy.ops.render.render(write_still=True)


