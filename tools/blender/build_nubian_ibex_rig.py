# Nubian Ibex Rig + Animation Builder for Blender 3.6+
# Run from Blender's Scripting workspace after placing this file beside nubian_ibex_game_character.glb.
import bpy, math, os
from mathutils import Vector
base=os.path.dirname(os.path.abspath(__file__))
glb=os.path.join(base,'nubian_ibex_game_character.glb')
# Clear scene
bpy.ops.object.select_all(action='SELECT'); bpy.ops.object.delete(use_global=False)
bpy.ops.import_scene.gltf(filepath=glb)
meshes=[o for o in bpy.context.scene.objects if o.type=='MESH']
# Create armature; bones are oriented along animal's long axis (Y forward, Z up).
arm_data=bpy.data.armatures.new('NubianIbex_Armature')
arm=bpy.data.objects.new('NubianIbex_Rig',arm_data); bpy.context.collection.objects.link(arm)
bpy.context.view_layer.objects.active=arm; arm.select_set(True)
bpy.ops.object.mode_set(mode='EDIT')
def bone(name,head,tail,parent=None,connected=False):
    b=arm_data.edit_bones.new(name); b.head=head; b.tail=tail
    if parent: b.parent=arm_data.edit_bones[parent]; b.use_connect=connected
    return b
bone('Root',(0,0,0.08),(0,0,0.55))
bone('Pelvis',(0,-.48,1.42),(0,-.10,1.48),'Root')
bone('Spine',(0,-.10,1.48),(0,.42,1.55),'Pelvis')
bone('Chest',(0,.42,1.55),(0,.72,1.72),'Spine')
bone('Neck',(0,.72,1.72),(0,.94,2.02),'Chest')
bone('Head',(0,.94,2.02),(0,1.25,2.05),'Neck')
bone('Tail',(0,-.48,1.52),(0,-1.18,1.48),'Pelvis')
for s,side in [(-1,'L'),(1,'R')]:
  bone('Ear.'+side,(s*.18,.82,2.22),(s*.48,.69,2.33),'Head')
  bone('Horn.'+side,(s*.16,.83,2.29),(s*.35,.31,2.98),'Head')
  for y,sy in [(.53,'F'),(-.57,'H')]:
    hip=(s*.27,y,1.42); knee=(s*.28,y+.02,.83 if sy=='F' else .87); ankle=(s*.29,y+.08,.20)
    bone('Leg.'+sy+side,hip,knee,'Chest' if sy=='F' else 'Pelvis')
    bone('Shin.'+sy+side,knee,ankle,'Leg.'+sy+side,True)
bpy.ops.object.mode_set(mode='OBJECT')
# Parent mesh pieces to the closest semantic bone with rigid weights. This keeps each modeled part intact.
def target_for(obj):
 n=obj.name.lower()
 if 'horn' in n: return 'Horn.'+('L' if '_L' in n else 'R')
 if 'ear' in n: return 'Ear.'+('L' if '_L' in n else 'R')
 if 'tail' in n: return 'Tail'
 for sy in ('F','H'):
  for side in ('L','R'):
   if ('_'+sy+side.lower() in n) or (sy+side.lower() in n):
    return ('Shin.' if ('hoof' in n or 'toe' in n or 'lower' in n) else 'Leg.')+sy+side
 if any(k in n for k in ['head','muzzle','nose','eye','beard']): return 'Head'
 if 'neck' in n: return 'Neck'
 if any(k in n for k in ['chest']): return 'Chest'
 if any(k in n for k in ['rump','dorsal','flank']): return 'Pelvis'
 if 'legupper' in n or 'knee' in n: return 'Leg.'+('F' if '_F' in n else 'H')+('L' if '_l' in n else 'R')
 return 'Spine'
for obj in meshes:
 vg=obj.vertex_groups.new(name=target_for(obj)); vg.add(list(range(len(obj.data.vertices))),1.0,'REPLACE')
 mod=obj.modifiers.new('Ibex_Rig','ARMATURE'); mod.object=arm
 obj.parent=arm
# Animation helpers. Clips are separate actions, looping clips repeat in engine via loop setting.
def make_action(name,frames,loop=False):
 arm.animation_data_create()
 arm.animation_data.action=bpy.data.actions.new(name=name)
 bpy.context.scene.frame_start=1; bpy.context.scene.frame_end=max(f for f,_ in frames)
 bpy.ops.object.mode_set(mode='POSE')
 for pb in arm.pose.bones: pb.rotation_mode='XYZ'
 for frame,values in frames:
  bpy.context.scene.frame_set(frame)
  for bn,rot in values.items():
   pb=arm.pose.bones.get(bn)
   if pb:
    pb.rotation_euler=rot; pb.keyframe_insert(data_path='rotation_euler',frame=frame,group=bn)
 bpy.ops.object.mode_set(mode='OBJECT')
 act=arm.animation_data.action; act.name=name
 for fc in act.fcurves:
  for kp in fc.keyframe_points: kp.interpolation='BEZIER'
  if loop:
   mod=fc.modifiers.new('CYCLES')
 return act
# radians, pose rotations around local axes; each action is a distinct clip.
clips={}
clips['Idle']=make_action('Idle',[(1,{}),(18,{'Head':(0,0,.035),'Tail':(.08,0,.06)}),(36,{'Head':(0,0,-.025),'Tail':(-.06,0,-.04)}),(54,{})],True)
clips['Walk']=make_action('Walk',[(1,{'Leg.FL':(.32,0,0),'Leg.FR':(-.32,0,0),'Leg.HL':(-.28,0,0),'Leg.HR':(.28,0,0)}),(9,{'Leg.FL':(-.32,0,0),'Leg.FR':(.32,0,0),'Leg.HL':(.28,0,0),'Leg.HR':(-.28,0,0)}),(17,{'Leg.FL':(.32,0,0),'Leg.FR':(-.32,0,0),'Leg.HL':(-.28,0,0),'Leg.HR':(.28,0,0)})],True)
clips['Run']=make_action('Run',[(1,{'Leg.FL':(.75,0,0),'Leg.FR':(-.75,0,0),'Leg.HL':(-.7,0,0),'Leg.HR':(.7,0,0),'Spine':(.08,0,0)}),(6,{'Leg.FL':(-.85,0,0),'Leg.FR':(.85,0,0),'Leg.HL':(.8,0,0),'Leg.HR':(-.8,0,0),'Spine':(-.08,0,0)}),(12,{'Leg.FL':(.75,0,0),'Leg.FR':(-.75,0,0),'Leg.HL':(-.7,0,0),'Leg.HR':(.7,0,0),'Spine':(.08,0,0)})],True)
clips['Jump']=make_action('Jump',[(1,{}),(6,{'Leg.FL':(-.7,0,0),'Leg.FR':(-.7,0,0),'Leg.HL':(.7,0,0),'Leg.HR':(.7,0,0),'Spine':(-.12,0,0)}),(12,{'Leg.FL':(.5,0,0),'Leg.FR':(.5,0,0),'Leg.HL':(-.5,0,0),'Leg.HR':(-.5,0,0)}),(20,{})])
clips['Eat']=make_action('Eat',[(1,{}),(10,{'Neck':(.35,0,0),'Head':(.35,0,0)}),(20,{'Neck':(.4,0,0),'Head':(.4,0,0)}),(30,{})],True)
clips['Drink']=make_action('Drink',[(1,{}),(12,{'Neck':(.5,0,0),'Head':(.45,0,0)}),(28,{'Neck':(.55,0,0),'Head':(.5,0,0)}),(40,{})])
clips['Sleep']=make_action('Sleep',[(1,{'Neck':(.65,0,0),'Head':(.55,0,0),'Tail':(.1,0,0)}),(24,{'Neck':(.68,0,0),'Head':(.58,0,0)}),(48,{'Neck':(.65,0,0),'Head':(.55,0,0)})],True)
clips['Sit']=make_action('Sit',[(1,{}),(12,{'Leg.HL':(.75,0,0),'Leg.HR':(.75,0,0),'Spine':(-.08,0,0)}),(24,{'Leg.HL':(.75,0,0),'Leg.HR':(.75,0,0),'Spine':(-.08,0,0)})])
clips['Look_Around']=make_action('Look_Around',[(1,{}),(12,{'Head':(0,0,.35)}),(24,{'Head':(0,0,-.35)}),(36,{})])
clips['Turn']=make_action('Turn',[(1,{}),(12,{'Spine':(0,0,.55),'Neck':(0,0,.25)}),(24,{'Spine':(0,0,1.1),'Neck':(0,0,.45)}),(36,{})])
clips['Alert']=make_action('Alert',[(1,{}),(5,{'Head':(-.12,0,0),'Ear.L':(0,0,.25),'Ear.R':(0,0,-.25)}),(18,{'Head':(-.12,0,0)}),(28,{})])
clips['Flee']=make_action('Flee',[(1,{}),(5,{'Leg.FL':(.8,0,0),'Leg.FR':(-.8,0,0),'Leg.HL':(-.8,0,0),'Leg.HR':(.8,0,0),'Spine':(.12,0,0)}),(10,{'Leg.FL':(-.8,0,0),'Leg.FR':(.8,0,0),'Leg.HL':(.8,0,0),'Leg.HR':(-.8,0,0),'Spine':(-.12,0,0)})],True)
clips['Interact']=make_action('Interact',[(1,{}),(12,{'Head':(.12,0,.18),'Neck':(.08,0,0),'Tail':(.12,0,.12)}),(24,{})])
clips['Attack_Defend']=make_action('Attack_Defend',[(1,{}),(7,{'Neck':(-.25,0,0),'Head':(-.2,0,0),'Leg.FL':(-.4,0,0),'Leg.FR':(-.4,0,0)}),(14,{'Neck':(.25,0,0),'Head':(.2,0,0)}),(22,{})])
clips['Hurt']=make_action('Hurt',[(1,{}),(4,{'Head':(.2,0,-.18),'Spine':(.12,0,0),'Leg.FL':(-.25,0,0)}),(10,{'Head':(.1,0,.12),'Spine':(-.05,0,0)}),(18,{})])
# Save native project with all named actions; export FBX with current action as a general rigged interchange.
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(base,'nubian_ibex_rigged_source.blend'))
print('Rig and 15 named animation actions created. Review/retarget poses before production use.')
