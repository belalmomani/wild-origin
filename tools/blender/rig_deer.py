# Blender 4.x rig + animation builder for stylized_forest_deer.glb
# Run: blender --background --python rig_deer.py
# Outputs: deer_rigged.blend, deer_rigged.glb, deer_rigged.fbx

import bpy, math, os
from mathutils import Vector

ROOT = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(ROOT, "stylized_forest_deer.glb")
if not os.path.exists(SRC):
    raise FileNotFoundError("Put stylized_forest_deer.glb beside this script.")

# Clean scene and import the previously-created deer mesh.
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete(use_global=False)
bpy.ops.import_scene.gltf(filepath=SRC)

# Keep mesh object names and world transforms; create a centered armature.
meshes = [o for o in bpy.context.scene.objects if o.type == 'MESH']
if not meshes:
    raise RuntimeError("No mesh objects found in the GLB.")
bpy.ops.object.select_all(action='DESELECT')

arm_data = bpy.data.armatures.new("Deer_Armature")
arm = bpy.data.objects.new("Deer_Rig", arm_data)
bpy.context.collection.objects.link(arm)
bpy.context.view_layer.objects.active = arm
arm.select_set(True)
bpy.ops.object.mode_set(mode='EDIT')

# Bone definitions use the same coordinate system as the source asset:
# +X forward, +Z up, Y left/right.
bones = {
    "Root": ((0,0,0.10),(0,0,0.55), None),
    "Spine": ((-0.48,0,1.45),(0.18,0,1.60),"Root"),
    "Chest": ((0.18,0,1.60),(0.50,0,1.72),"Spine"),
    "Neck": ((0.50,0,1.72),(0.70,0,2.15),"Chest"),
    "Head": ((0.70,0,2.15),(0.82,0,2.48),"Neck"),
    "Tail": ((-0.72,0,1.65),(-1.00,0,1.80),"Spine"),
    "Ear.L": ((0.72,0.08,2.48),(0.50,0.28,2.78),"Head"),
    "Ear.R": ((0.72,-0.08,2.48),(0.50,-0.28,2.78),"Head"),
    "Antler.L": ((0.72,0.10,2.62),(0.66,0.36,3.12),"Head"),
    "Antler.R": ((0.72,-0.10,2.62),(0.66,-0.36,3.12),"Head"),
}
leg_bones = {}
for label, x, y, hipz, knee_x in [
    ("Front.L", .48, .22, 1.42, .465),
    ("Front.R", .48,-.22, 1.42, .465),
    ("Hind.L", -.53, .23, 1.43, -.48),
    ("Hind.R", -.53,-.23, 1.43, -.48),
]:
    upper = label + ".Upper"
    lower = label + ".Lower"
    foot = label + ".Foot"
    bones[upper] = ((x,y,hipz),(knee_x,y,.78),"Chest" if "Front" in label else "Spine")
    bones[lower] = ((knee_x,y,.78),(x+.02,y,.20),upper)
    bones[foot] = ((x+.02,y,.20),(x+.02,y,.08),lower)
    leg_bones[label] = (upper, lower, foot)

edit_bones = {}
for name, (head, tail, parent) in bones.items():
    b = arm_data.edit_bones.new(name)
    b.head = head
    b.tail = tail
    if parent:
        b.parent = arm_data.edit_bones[parent]
    edit_bones[name] = b
bpy.ops.object.mode_set(mode='OBJECT')
arm.show_in_front = True
arm_data.display_type = 'OCTAHEDRAL'

# Rigid-bind each source mesh part to the most appropriate bone.
def choose_bone(obj):
    n = obj.name.lower()
    if "hoof" in n:
        if "front_near" in n: return "Front.R.Foot"
        if "front_far" in n: return "Front.L.Foot"
        if "hind_near" in n: return "Hind.R.Foot"
        if "hind_far" in n: return "Hind.L.Foot"
    if "front_near" in n: return "Front.R.Lower" if "lower" in n else "Front.R.Upper"
    if "front_far" in n: return "Front.L.Lower" if "lower" in n else "Front.L.Upper"
    if "hind_near" in n: return "Hind.R.Lower" if "lower" in n else "Hind.R.Upper"
    if "hind_far" in n: return "Hind.L.Lower" if "lower" in n else "Hind.L.Upper"
    if "ear" in n:
        return "Ear.L" if obj.matrix_world.translation.y >= 0 else "Ear.R"
    if "antler" in n:
        return "Antler.L" if obj.matrix_world.translation.y >= 0 else "Antler.R"
    if "tail" in n: return "Tail"
    if any(k in n for k in ("head","muzzle","nose","eye")): return "Head"
    if "neck" in n or "throat" in n: return "Neck"
    if "chest" in n: return "Chest"
    if "belly" in n or "rump" in n or "torso" in n: return "Spine"
    if "knee" in n:
        if "front_near" in n: return "Front.R.Lower"
        if "front_far" in n: return "Front.L.Lower"
        if "hind_near" in n: return "Hind.R.Lower"
        if "hind_far" in n: return "Hind.L.Lower"
    return "Spine"

for obj in meshes:
    bone_name = choose_bone(obj)
    vg = obj.vertex_groups.get(bone_name) or obj.vertex_groups.new(name=bone_name)
    vg.add(list(range(len(obj.data.vertices))), 1.0, 'REPLACE')
    mod = obj.modifiers.new("Deer_Skin", 'ARMATURE')
    mod.object = arm
    obj.parent = arm

# Helpers for keyframing named clips.
def reset_pose():
    for pb in arm.pose.bones:
        pb.rotation_mode = 'XYZ'
        pb.location = (0,0,0)
        pb.rotation_euler = (0,0,0)
        pb.scale = (1,1,1)

def clip(name, frames, keys):
    bpy.context.scene.frame_start = frames[0]
    bpy.context.scene.frame_end = frames[-1]
    reset_pose()
    for frame, pose in keys:
        for bone_name, value in pose.items():
            if bone_name.endswith("_LOC"):
                real_name = bone_name[:-4]
                pb = arm.pose.bones.get(real_name)
                if pb:
                    pb.location = value
                    pb.keyframe_insert(data_path="location", frame=frame, group=real_name)
                continue
            pb = arm.pose.bones.get(bone_name)
            if pb:
                pb.rotation_euler = value
                pb.keyframe_insert(data_path="rotation_euler", frame=frame, group=bone_name)
        arm.pose.bones["Root"].keyframe_insert(data_path="location", frame=frame, group="Root")
    action = arm.animation_data.action
    action.name = name
    # Set repeating cycles for locomotion and idle/eating.
    if name in {"Idle","Walk","Run","Eat","Drink","Sleep"}:
        for fc in action.fcurves:
            for kp in fc.keyframe_points:
                kp.interpolation = 'BEZIER'
            mod = fc.modifiers.new('CYCLES')
    else:
        for fc in action.fcurves:
            for kp in fc.keyframe_points:
                kp.interpolation = 'BEZIER'
    actions.append(action)

actions = []
# All angles in radians. Leg swing is deliberately stylized; refine in Blender as needed.
clip("Idle", (1,48), [
    (1, {"Neck":(0,0,0), "Head":(0,0,0), "Tail":(0,.08,0), "Ear.L":(0,0,.04), "Ear.R":(0,0,-.04)}),
    (24,{"Neck":(.025,0,0), "Head":(-.025,0,0), "Tail":(0,-.08,0)}),
    (48,{"Neck":(0,0,0), "Head":(0,0,0), "Tail":(0,.08,0)})
])
clip("Walk", (1,24), [
    (1, {"Front.L.Upper":(.35,0,0),"Front.R.Upper":(-.35,0,0),"Hind.L.Upper":(-.30,0,0),"Hind.R.Upper":(.30,0,0),"Head":(0,0,0)}),
    (7, {"Front.L.Upper":(0,0,0),"Front.R.Upper":(0,0,0),"Hind.L.Upper":(0,0,0),"Hind.R.Upper":(0,0,0)}),
    (13,{"Front.L.Upper":(-.35,0,0),"Front.R.Upper":(.35,0,0),"Hind.L.Upper":(.30,0,0),"Hind.R.Upper":(-.30,0,0)}),
    (19,{"Front.L.Upper":(0,0,0),"Front.R.Upper":(0,0,0),"Hind.L.Upper":(0,0,0),"Hind.R.Upper":(0,0,0)}),
    (24,{"Front.L.Upper":(.35,0,0),"Front.R.Upper":(-.35,0,0),"Hind.L.Upper":(-.30,0,0),"Hind.R.Upper":(.30,0,0)})
])
clip("Run", (1,16), [
    (1, {"Front.L.Upper":(.75,0,0),"Front.R.Upper":(-.75,0,0),"Hind.L.Upper":(-.65,0,0),"Hind.R.Upper":(.65,0,0),"Neck":(-.12,0,0)}),
    (5, {"Front.L.Upper":(-.35,0,0),"Front.R.Upper":(.35,0,0),"Hind.L.Upper":(.45,0,0),"Hind.R.Upper":(-.45,0,0),"Root":(0,0,0)}),
    (9, {"Front.L.Upper":(.75,0,0),"Front.R.Upper":(-.75,0,0),"Hind.L.Upper":(-.65,0,0),"Hind.R.Upper":(.65,0,0)}),
    (13,{"Front.L.Upper":(-.35,0,0),"Front.R.Upper":(.35,0,0),"Hind.L.Upper":(.45,0,0),"Hind.R.Upper":(-.45,0,0)}),
    (16,{"Front.L.Upper":(.75,0,0),"Front.R.Upper":(-.75,0,0),"Hind.L.Upper":(-.65,0,0),"Hind.R.Upper":(.65,0,0)})
])
clip("Jump", (1,24), [
    (1, {"Front.L.Upper":(.55,0,0),"Front.R.Upper":(.55,0,0),"Hind.L.Upper":(-.55,0,0),"Hind.R.Upper":(-.55,0,0),"Root_LOC":(0,0,0.0)}),
    (8, {"Front.L.Upper":(-.45,0,0),"Front.R.Upper":(-.45,0,0),"Hind.L.Upper":(.55,0,0),"Hind.R.Upper":(.55,0,0),"Root_LOC":(0,0,.38)}),
    (14,{"Front.L.Upper":(-.35,0,0),"Front.R.Upper":(-.35,0,0),"Hind.L.Upper":(.35,0,0),"Hind.R.Upper":(.35,0,0),"Root_LOC":(0,0,.25)}),
    (24,{"Front.L.Upper":(0,0,0),"Front.R.Upper":(0,0,0),"Hind.L.Upper":(0,0,0),"Hind.R.Upper":(0,0,0),"Root":(0,0,0)})
])
clip("Eat", (1,40), [
    (1, {"Neck":(.05,0,0),"Head":(.10,0,0)}),
    (20,{"Neck":(.48,0,0),"Head":(.35,0,0)}),
    (40,{"Neck":(.05,0,0),"Head":(.10,0,0)})
])
clip("Drink", (1,36), [
    (1, {"Neck":(.10,0,0),"Head":(.10,0,0)}),
    (18,{"Neck":(.62,0,0),"Head":(.42,0,0)}),
    (36,{"Neck":(.10,0,0),"Head":(.10,0,0)})
])
clip("Sleep", (1,48), [
    (1, {"Neck":(.28,0,0),"Head":(.38,0,0),"Tail":(0,.12,0)}),
    (24,{"Neck":(.32,0,0),"Head":(.42,0,0),"Tail":(0,-.08,0)}),
    (48,{"Neck":(.28,0,0),"Head":(.38,0,0),"Tail":(0,.12,0)})
])
clip("Sit", (1,30), [
    (1, {"Hind.L.Upper":(.15,0,0),"Hind.R.Upper":(.15,0,0),"Neck":(0,0,0)}),
    (15,{"Hind.L.Upper":(.75,0,0),"Hind.R.Upper":(.75,0,0),"Neck":(-.05,0,0)}),
    (30,{"Hind.L.Upper":(.75,0,0),"Hind.R.Upper":(.75,0,0)})
])
clip("Look_Around", (1,36), [
    (1, {"Head":(0,0,-.35)}),(18,{"Head":(0,0,.35)}),(36,{"Head":(0,0,0)})
])
clip("Turn", (1,24), [
    (1, {"Root":(0,0,0)}),(12,{"Root":(0,0,math.pi/2)}),(24,{"Root":(0,0,math.pi)})
])
clip("Alert", (1,20), [
    (1, {"Neck":(-.12,0,0),"Head":(-.18,0,0),"Ear.L":(0,0,.18),"Ear.R":(0,0,-.18)}),
    (10,{"Neck":(-.12,0,0),"Head":(-.18,0,0),"Tail":(0,-.12,0)}),
    (20,{"Neck":(0,0,0),"Head":(0,0,0)})
])
clip("Flee", (1,16), [
    (1, {"Front.L.Upper":(.85,0,0),"Front.R.Upper":(-.85,0,0),"Hind.L.Upper":(-.8,0,0),"Hind.R.Upper":(.8,0,0),"Neck":(-.2,0,0)}),
    (8, {"Front.L.Upper":(-.65,0,0),"Front.R.Upper":(.65,0,0),"Hind.L.Upper":(.7,0,0),"Hind.R.Upper":(-.7,0,0),"Neck":(-.2,0,0)}),
    (16,{"Front.L.Upper":(.85,0,0),"Front.R.Upper":(-.85,0,0),"Hind.L.Upper":(-.8,0,0),"Hind.R.Upper":(.8,0,0),"Neck":(-.2,0,0)})
])
clip("Interact", (1,32), [
    (1, {"Head":(0,0,-.2),"Neck":(-.05,0,0)}),
    (16,{"Head":(.08,0,.2),"Neck":(-.08,0,0)}),
    (32,{"Head":(0,0,0),"Neck":(0,0,0)})
])
clip("Defend", (1,24), [
    (1, {"Head":(-.12,0,0),"Neck":(-.18,0,0),"Front.L.Upper":(-.25,0,0),"Front.R.Upper":(-.25,0,0)}),
    (12,{"Head":(-.25,0,0),"Neck":(-.25,0,0),"Front.L.Upper":(.25,0,0),"Front.R.Upper":(.25,0,0)}),
    (24,{"Head":(-.12,0,0),"Neck":(-.18,0,0)})
])
clip("Hurt", (1,18), [
    (1, {"Head":(.18,0,-.12),"Neck":(.15,0,0),"Root":(0,0,0)}),
    (6, {"Head":(-.18,0,.12),"Neck":(-.12,0,0)}),
    (18,{"Head":(0,0,0),"Neck":(0,0,0)})
])

# Save each action as a separate NLA strip for convenient engine export.
arm.animation_data.action = None
for act in actions:
    track = arm.animation_data.nla_tracks.new()
    track.name = act.name
    strip = track.strips.new(act.name, int(act.frame_range[0]), act)
    strip.blend_type = 'REPLACE'
    strip.extrapolation = 'NOTHING'

# Select rig and save native Blender project.
bpy.ops.object.select_all(action='DESELECT')
arm.select_set(True)
bpy.context.view_layer.objects.active = arm
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(ROOT, "deer_rigged.blend"))

# Export GLB with skin and animation tracks.
bpy.ops.export_scene.gltf(
    filepath=os.path.join(ROOT, "deer_rigged.glb"),
    export_format='GLB',
    export_skins=True,
    export_animations=True,
    export_nla_strips=True,
    export_apply=False
)

# Also export FBX for Unity / Unreal workflows.
bpy.ops.export_scene.fbx(
    filepath=os.path.join(ROOT, "deer_rigged.fbx"),
    use_selection=False,
    object_types={'ARMATURE','MESH'},
    add_leaf_bones=False,
    bake_anim=True,
    bake_anim_use_nla_strips=True,
    bake_anim_simplify_factor=0.0
)
print("Finished: deer_rigged.blend, deer_rigged.glb, deer_rigged.fbx")
