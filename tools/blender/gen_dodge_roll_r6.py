"""gen_dodge_roll_r6.py - the 8 DODGE ROLL clips of the R6 rig (Blender), baked for Roblox.

Run INSIDE Blender (Blender MCP execute_blender_code: exec(open(path).read())). Idempotent: it always starts from the committed
assets/blender/combat/SwordCombo_R6.blend (the same R6 rig as the sword combo), drops the combo actions and the swords, builds the
8 actions DodgeRoll_F, _FR, _R, _BR, _B, _BL, _L, _FL and writes
  assets/blender/combat/DodgeRoll_R6.blend              the rig + the 8 actions (frames 0..14 at 30 fps = 0.467 s)
  assets/blender/combat/dodge_roll_motor6d_r6.json      the same format as combo_motor6d_r6.json: { clip: [ { part: [qx,qy,qz,qw,tx,ty,tz] } per frame ] }
  tools/studio/build_dodge_roll_keyframes.luau          creates the KeyframeSequences in Studio (Workspace.CombatRig_R6.AnimSaves)

THE BAKE: Roblox poses are Motor6D Transforms. For every joint the Blender pose-bone quaternion maps to the Transform quaternion by a signed
axis permutation that depends on the bone (the C0 / C1 rotations of R6: T = C0^-1 * Part0pose^-1 * Part1pose * C1). Those permutations are
not typed in: they are FITTED from the sword combo (its actions + combo_motor6d_r6.json, which Roblox accepted) and must reproduce it exactly.
The torso translation is the same fit: Transform t = (-x, z, y) of the pose-bone location.

THE CLIPS are authored in Roblox part space (x right, y up, z back, forward = -z) and converted to the bones:
  roll direction d (0 = forward, 90 = right ...), roll axis w = up x d; the torso turns 360 degrees about w while it drops;
  crouch (0-3) -> tuck + roll (2-10) -> rise (10-14); every clip starts and ends in the exact standing pose (all joints identity).
"""
import json
import math
import os

import bpy
from mathutils import Matrix, Quaternion, Vector

ROOT = r"C:\Users\natea\Documents\Roblox Game Development\Fractured Islands Ascension"
SRC_BLEND = os.path.join(ROOT, "assets", "blender", "combat", "SwordCombo_R6.blend")
SRC_JSON = os.path.join(ROOT, "assets", "blender", "combat", "combo_motor6d_r6.json")
OUT_BLEND = os.path.join(ROOT, "assets", "blender", "combat", "DodgeRoll_R6.blend")
OUT_JSON = os.path.join(ROOT, "assets", "blender", "combat", "dodge_roll_motor6d_r6.json")
OUT_LUAU = os.path.join(ROOT, "tools", "studio", "build_dodge_roll_keyframes.luau")

FPS = 30
LAST = 14  # frames 0..14
PARTS = ["Torso", "Head", "Right Arm", "Left Arm", "Right Leg", "Left Leg"]
CLIPS = [("F", 0), ("FR", 45), ("R", 90), ("BR", 135), ("B", 180), ("BL", 225), ("L", 270), ("FL", 315)]  # name, degrees clockwise from forward

# ---- tuning (degrees / studs) -------------------------------------------------------------------------------------------------------
TUCK = {"Head": -40.0, "Arm": -100.0, "ArmIn": 25.0, "Leg": -110.0, "LegIn": 6.0}
DROP = 1.25  # starting drop of the torso (studs); each clip then gets its own so the lowest point of the body just touches the floor (FLOOR_MARGIN)
FLOOR_MARGIN = 0.05  # studs the body may dip below the floor (the floor is z = 0 in Blender, the HumanoidRootPart height above the soles in Roblox)
LEAN = 18.0
ROLL_START, ROLL_END = 2.0, 10.0
TUCK_IN, TUCK_OUT_START, TUCK_OUT_END = 3.0, 10.0, 14.0


def smooth(x: float) -> float:
    x = max(0.0, min(1.0, x))
    return x * x * (3 - 2 * x)


def open_base():
    bpy.ops.wm.open_mainfile(filepath=SRC_BLEND)
    return bpy.data.objects["R6Rig"]


# ---- 1. fit the bone -> Transform axis maps from the sword combo -------------------------------------------------------------------
def fit_maps(rig):
    data = json.load(open(SRC_JSON))
    rig.animation_data_create()
    maps = {}
    candidates = []
    for perm in [(0, 1, 2), (0, 2, 1), (1, 0, 2), (1, 2, 0), (2, 0, 1), (2, 1, 0)]:
        for sx in (1, -1):
            for sy in (1, -1):
                for sz in (1, -1):
                    candidates.append((perm, (sx, sy, sz)))
    samples = {p: [] for p in PARTS}
    tsamples = []
    for clip, frames in data.items():
        rig.animation_data.action = bpy.data.actions[clip]
        for f in range(len(frames)):
            bpy.context.scene.frame_set(f)
            for p in PARTS:
                q = rig.pose.bones[p].rotation_quaternion.copy()
                q.normalize()
                if q.w < 0:
                    q.negate()
                j = frames[f][p]
                jq = Quaternion((j[3], j[0], j[1], j[2]))
                if jq.w < 0:
                    jq.negate()
                samples[p].append(((q.x, q.y, q.z), (jq.x, jq.y, jq.z)))
            loc = rig.pose.bones["Torso"].location
            tsamples.append(((loc.x, loc.y, loc.z), tuple(frames[f]["Torso"][4:7])))
    for p in PARTS:
        best = None
        for perm, signs in candidates:
            err = 0.0
            for b, j in samples[p]:
                for k in range(3):
                    err = max(err, abs(signs[k] * b[perm[k]] - j[k]))
            if best is None or err < best[0]:
                best = (err, perm, signs)
        assert best[0] < 2e-3, f"axis map of {p} does not reproduce the sword combo (err {best[0]})"
        maps[p] = (best[1], best[2])
    # torso translation: Transform t = (-x, z, y) of the pose location
    terr = max(max(abs(t[0] + b[0]), abs(t[1] - b[2]), abs(t[2] - b[1])) for b, t in tsamples)
    assert terr < 2e-3, f"torso translation map does not reproduce the sword combo (err {terr})"
    return maps


def to_json(p, bone, maps):
    q = bone.rotation_quaternion.copy()
    q.normalize()
    if q.w < 0:
        q.negate()
    perm, signs = maps[p]
    b = (q.x, q.y, q.z)
    jx, jy, jz = (signs[k] * b[perm[k]] for k in range(3))
    t = (0.0, 0.0, 0.0)
    if p == "Torso":
        loc = bone.location
        t = (-loc.x, loc.z, loc.y)
    return [round(jx, 5), round(jy, 5), round(jz, 5), round(q.w, 5), round(t[0], 5), round(t[1], 5), round(t[2], 5)]


# ---- 2. author in Roblox part space, convert to pose-bone values -----------------------------------------------------------------
def rob_to_bl(v):  # Roblox (x, y, z) -> Blender armature (x, -z, y)
    return Vector((v[0], -v[2], v[1]))


def axis_angle(axis_rob, degrees) -> Quaternion:
    return Quaternion(rob_to_bl(axis_rob).normalized(), math.radians(degrees))


def rest_frames(rig):
    """For every bone: (Rrel = child rest basis relative to its parent's rest basis, Pm3 = the parent's rest basis)."""
    out = {}
    for bone in rig.data.bones:
        parent = bone.parent
        pm = parent.matrix_local if parent else Matrix.Identity(4)
        rrel = (pm.inverted() @ bone.matrix_local).to_3x3()
        out[bone.name] = (rrel, pm.to_3x3())
    return out


def pose_value(frames, bone_name, d_world: Quaternion) -> Quaternion:
    """The pose-bone quaternion that turns the bone by `d_world` (a rotation in the PARENT's rest-aligned axes, applied in its posed frame)."""
    rrel, pm3 = frames[bone_name]
    d = d_world.to_matrix()
    local = rrel.inverted() @ (pm3.inverted() @ d @ pm3) @ rrel
    return local.to_quaternion()


def clip_pose(angle_deg: float, f: float, drop: float = DROP):
    """{part: (Quaternion rotation in Roblox-axes-converted world, Vector part-space translation)} for frame f."""
    a = math.radians(angle_deg)
    d = (math.sin(a), 0.0, -math.cos(a))  # roll direction in part space (forward = -z, right = +x)
    w = (d[2], 0.0, -d[0])  # up x d
    tuck = smooth(f / TUCK_IN) * (1 - smooth((f - TUCK_OUT_START) / (TUCK_OUT_END - TUCK_OUT_START)))
    roll = smooth((f - ROLL_START) / (ROLL_END - ROLL_START))
    lean = LEAN * math.sin(math.pi * max(0.0, min(1.0, f / 4.0)))
    phi = 360.0 * roll + lean
    pose = {}
    pose["Torso"] = (axis_angle(w, phi), Vector((0.0, -drop * tuck, 0.0)))
    X, Z = (1, 0, 0), (0, 0, 1)
    pose["Head"] = (axis_angle(X, TUCK["Head"] * tuck), Vector())
    pose["Right Arm"] = (axis_angle(X, TUCK["Arm"] * tuck) @ axis_angle(Z, -TUCK["ArmIn"] * tuck), Vector())
    pose["Left Arm"] = (axis_angle(X, TUCK["Arm"] * tuck) @ axis_angle(Z, TUCK["ArmIn"] * tuck), Vector())
    pose["Right Leg"] = (axis_angle(X, TUCK["Leg"] * tuck) @ axis_angle(Z, -TUCK["LegIn"] * tuck), Vector())
    pose["Left Leg"] = (axis_angle(X, TUCK["Leg"] * tuck) @ axis_angle(Z, TUCK["LegIn"] * tuck), Vector())
    return pose


def build(rig, maps, drops=None):
    drops = drops or {}
    frames_rest = rest_frames(rig)
    for action in list(bpy.data.actions):
        bpy.data.actions.remove(action)
    for obj in list(bpy.data.objects):
        if obj.name.startswith("Sword") or obj.name == "Prev_Sword":
            bpy.data.objects.remove(obj)
    rig.animation_data_create()
    result = {}
    report = {}
    for name, angle in CLIPS:
        action = bpy.data.actions.new("DodgeRoll_" + name)
        action.use_fake_user = True
        rig.animation_data.action = action
        for pb in rig.pose.bones:
            pb.rotation_mode = "QUATERNION"
        frames = []
        prev = {}
        for f in range(LAST + 1):
            pose = clip_pose(angle, float(f), drops.get(name, DROP))
            entry = {}
            for part in PARTS:
                rot, trans = pose[part]
                q = pose_value(frames_rest, part, rot)
                if part in prev and prev[part].dot(q) < 0:
                    q.negate()  # keep the quaternion continuous between frames
                prev[part] = q.copy()
                bone = rig.pose.bones[part]
                bone.rotation_quaternion = q
                bl = rob_to_bl(trans)
                rrel, pm3 = frames_rest[part]
                bone.location = rrel.inverted() @ (pm3.inverted() @ bl)
                bone.keyframe_insert("rotation_quaternion", frame=f, group=part)
                if part == "Torso":
                    bone.keyframe_insert("location", frame=f, group=part)
                entry[part] = to_json(part, bone, maps)
            frames.append(entry)
        result["DodgeRoll_" + name] = frames
        # verification: first and last frame = the standing pose
        worst = 0.0
        for fi in (0, LAST):
            for part in PARTS:
                j = frames[fi][part]
                angle_deg = math.degrees(2 * math.acos(min(1.0, abs(j[3]))))
                worst = max(worst, angle_deg, max(abs(x) for x in j[4:7]))
        report[name] = round(worst, 4)
        assert worst < 0.5, f"clip {name} does not start/end in the standing pose ({worst})"
        # after the first clip the rest pose of the rig for the next one
        for pb in rig.pose.bones:
            pb.rotation_quaternion = (1, 0, 0, 0)
            pb.location = (0, 0, 0)
    return result, report


def lowest_point(rig, clip_name: str, first: int = 4, last: int = 10) -> float:
    """The lowest world z of the body meshes while it is rolling (frames first..last: the start and the end are the standing pose)."""
    rig.animation_data.action = bpy.data.actions[clip_name]
    low = 9.0
    for f in range(first, last + 1):
        bpy.context.scene.frame_set(f)
        depsgraph = bpy.context.evaluated_depsgraph_get()
        for obj in bpy.data.objects:
            if obj.name.startswith("Prev_"):
                evaluated = obj.evaluated_get(depsgraph)
                mesh = evaluated.to_mesh()
                for vertex in mesh.vertices:
                    low = min(low, (obj.matrix_world @ vertex.co).z)
                evaluated.to_mesh_clear()
    return low


def luau(result) -> str:
    lines = [
        "-- build_dodge_roll_keyframes.luau  (GENERATED by tools/blender/gen_dodge_roll_r6.py: do not edit by hand)",
        "-- Creates the 8 dodge roll KeyframeSequences (DodgeRoll_F ... DodgeRoll_FL) in Workspace.CombatRig_R6.AnimSaves, ready to be",
        "-- published from the Animation Editor (rig CombatRig_R6, select the clip, Publish to Roblox, copy the asset id).",
        "-- Run through the Studio MCP (execute_luau, Edit datamodel, Play stopped). Replaces sequences of the same name.",
        "local DATA = {",
    ]
    for clip, frames in result.items():
        lines.append(f'\t["{clip}"] = {{')
        for f, entry in enumerate(frames):
            cells = []
            for part in PARTS:
                cells.append('["%s"] = {%s}' % (part, ",".join(("%g" % x) for x in entry[part])))
            lines.append("\t\t{" + ", ".join(cells) + "},")
        lines.append("\t},")
    lines.append("}")
    lines.append(f"local FPS = {FPS}")
    lines.append(
        """
local rig = workspace:FindFirstChild("CombatRig_R6")
assert(rig, "Workspace.CombatRig_R6 is missing")
local saves = rig:FindFirstChild("AnimSaves") or Instance.new("Folder")
saves.Name = "AnimSaves"
saves.Parent = rig

local CHILDREN = { "Head", "Right Arm", "Left Arm", "Right Leg", "Left Leg" }
local function cframeOf(v)
	return CFrame.new(v[5], v[6], v[7]) * CFrame.new(0, 0, 0, v[1], v[2], v[3], v[4])
end

local made = {}
for clip, frames in pairs(DATA) do
	local old = saves:FindFirstChild(clip)
	if old then
		old:Destroy()
	end
	local sequence = Instance.new("KeyframeSequence")
	sequence.Name = clip
	sequence.Loop = false
	sequence.Priority = Enum.AnimationPriority.Action
	for index, entry in ipairs(frames) do
		local keyframe = Instance.new("Keyframe")
		keyframe.Time = (index - 1) / FPS
		local root = Instance.new("Pose")
		root.Name = "HumanoidRootPart"
		root.Weight = 0
		root.CFrame = CFrame.new()
		local torso = Instance.new("Pose")
		torso.Name = "Torso"
		torso.Weight = 1
		torso.CFrame = cframeOf(entry["Torso"])
		torso.Parent = root
		for _, name in ipairs(CHILDREN) do
			local pose = Instance.new("Pose")
			pose.Name = name
			pose.Weight = 1
			pose.CFrame = cframeOf(entry[name])
			pose.Parent = torso
		end
		root.Parent = keyframe
		keyframe.Parent = sequence
	end
	sequence.Parent = saves
	table.insert(made, clip .. " (" .. #frames .. " keyframes)")
end
table.sort(made)
return "created in AnimSaves: " .. table.concat(made, ", ")
"""
    )
    return "\n".join(lines)


def main():
    rig = open_base()
    maps = fit_maps(rig)
    result, report = build(rig, maps)
    drops = {name: DROP for name, _ in CLIPS}
    for _ in range(4):  # fit: every clip lowers the body just enough that it does not sink into the floor (a few passes: the lowest point moves as it turns)
        for name, _angle in CLIPS:
            low = lowest_point(rig, "DodgeRoll_" + name)
            drops[name] = max(0.0, drops[name] - max(0.0, -low - FLOOR_MARGIN))
        result, report = build(rig, maps, drops)
    print("fitted drops:", {k: round(v, 2) for k, v in drops.items()})
    print("lowest point after the fit:", {name: round(lowest_point(rig, "DodgeRoll_" + name), 2) for name, _ in CLIPS})
    # leave the rig on the first clip, pose reset, scene 0..14 @ 30 fps
    rig.animation_data.action = bpy.data.actions["DodgeRoll_F"]
    scene = bpy.context.scene
    scene.render.fps = FPS
    scene.frame_start, scene.frame_end = 0, LAST
    scene.frame_set(0)
    bpy.ops.wm.save_as_mainfile(filepath=OUT_BLEND)
    with open(OUT_JSON, "w", encoding="utf-8", newline="\n") as handle:
        json.dump(result, handle, separators=(",", ":"))
    with open(OUT_LUAU, "w", encoding="utf-8", newline="\n") as handle:
        handle.write(luau(result))
    print("axis maps:", maps)
    print("standing-pose check (max deg / studs at frames 0 and 14):", report)
    print("wrote", OUT_BLEND, OUT_JSON, OUT_LUAU)


main()
