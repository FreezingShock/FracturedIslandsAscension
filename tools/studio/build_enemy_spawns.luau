-- Workspace.EnemySpawns: one marker Part per mob, used by EnemyService. The part's attribute EnemyType picks the
-- EnemyConfig entry. Marker = flat translucent red Neon pad: move / add / delete freely.
-- Placed beside the DummySpawns row (offset Z). ADDITIVE: a marker that already exists (by name) is left alone, so hand moves
-- survive; set FORCE = true to rebuild the whole folder. Edit datamodel.
local FORCE = false

-- name, EnemyType, x offset from the first marker
local SPAWNS = {
	{ "EnemySpawn1", "placeholder_mob", 0 },
	{ "EnemySpawn2", "slime_blob", -40 },
	{ "EnemySpawn3", "skeleton_grunt", -30 },
	{ "EnemySpawn4", "spider_scout", -20 },
	{ "EnemySpawn5", "cinder_imp", -10 },
	{ "EnemySpawn6", "void_wisp", 10 },
}

local folder = workspace:FindFirstChild("EnemySpawns")
if folder and FORCE then
	folder:Destroy()
	folder = nil
end
if not folder then
	folder = Instance.new("Folder")
	folder.Name = "EnemySpawns"
	folder.Parent = workspace
end

local base = Vector3.new(-944.66, 282.1, -820)
local dummies = workspace:FindFirstChild("DummySpawns")
local first = dummies and dummies:FindFirstChildWhichIsA("BasePart")
if first then
	base = first.Position + Vector3.new(10, 0, 19)
end
local made = {}
for _, spec in ipairs(SPAWNS) do
	if not folder:FindFirstChild(spec[1]) then
		local marker = Instance.new("Part")
		marker.Name = spec[1]
		marker.Anchored = true
		marker.CanCollide = false
		marker.Size = Vector3.new(4, 0.2, 4)
		marker.Position = base + Vector3.new(spec[3], 0, 0)
		marker.Color = Color3.new(1, 0.333333, 0.333333)
		marker.Material = Enum.Material.Neon
		marker.Transparency = 0.8
		marker:SetAttribute("EnemyType", spec[2])
		marker.Parent = folder
		table.insert(made, spec[1] .. "=" .. spec[2])
	end
end
return "EnemySpawns: created " .. (#made > 0 and table.concat(made, ", ") or "nothing (all exist)")
