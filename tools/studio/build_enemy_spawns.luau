-- Workspace.EnemySpawns: one marker Part per mob, used by EnemyService. The part's attribute EnemyType picks the
-- EnemyConfig entry (placeholder_mob). Marker = flat translucent red Neon pad: move / add / delete freely.
-- Placed beside the DummySpawns row (offset Z); change the position if the spawn moves.
-- Edit datamodel. Refuses to overwrite unless FORCE.
local FORCE = false
local folder = workspace:FindFirstChild("EnemySpawns")
if folder and not FORCE then
	return "EnemySpawns exists (set FORCE = true to rebuild)"
end
if folder then
	folder:Destroy()
end
folder = Instance.new("Folder")
folder.Name = "EnemySpawns"

local base = Vector3.new(-944.66, 282.1, -820)
local dummies = workspace:FindFirstChild("DummySpawns")
local first = dummies and dummies:FindFirstChildWhichIsA("BasePart")
if first then
	base = first.Position + Vector3.new(10, 0, 19)
end
local marker = Instance.new("Part")
marker.Name = "EnemySpawn1"
marker.Anchored = true
marker.CanCollide = false
marker.Size = Vector3.new(4, 0.2, 4)
marker.Position = base
marker.Color = Color3.new(1, 0.333333, 0.333333)
marker.Material = Enum.Material.Neon
marker.Transparency = 0.8
marker:SetAttribute("EnemyType", "placeholder_mob")
marker.Parent = folder
folder.Parent = workspace
return "built Workspace.EnemySpawns at " .. tostring(base)
