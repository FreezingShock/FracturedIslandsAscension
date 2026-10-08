--[[
	DropStackConfig (ModuleScript, Shared)
	Place inside: ReplicatedStorage > Modules > Config

	How FLOOR items (ItemDrops) stack. Read by the server (ItemDrops: what merges, when) and the client
	(ItemDropRenderer: the fly-in and the punch, DropFXController: the stack burst), so the timing matches.

	  maxStack        most items one floor drop can hold (also capped by the item's own maxStack; gear never stacks)
	  mergeRadius     settled drops closer than this clump together
	  spawnRadius     a NEW drop (even a thrown one) that appears within this many studs of a matching drop does not
	                  start its own motion: it flies into that drop instead
	  flyTime         seconds the incoming item takes to fly into the stack
	  flyArc          studs the incoming item arcs upward on the way
	  punch           the stack squashes: scale rises to `scale`, lands on `settle`, `time` seconds, `spin` extra radians/s
	                  that fades out. Bigger stacks punch harder: scale + perCount * count (max `maxScale`)
	  layers          { count thresholds }: a stack shows one more offset copy of the item per threshold passed
	  layerSpread     studs the extra copies are scattered over (horizontal / vertical)
  layerTurn       radians each extra copy may be turned about the vertical (0 = all copies face the same way, like Minecraft;
                  thick sprites show every turned edge as a separate outline)
  pickup          a picked-up item is not deleted: it flies into the player like an item flies into a stack (the same
                  accelerating arc, spin and shrink), then pops: flyTime seconds, flyArc studs of arc, chest studs above
                  the player's root it flies to, shrink = fraction of its size it loses on the way
]]

local DropStackConfig = {
	maxStack = 99,
	mergeRadius = 15,
	spawnRadius = 10,
	flyTime = 0.26,
	flyArc = 1.2,
	punch = { scale = 1.18, perCount = 0.0015, maxScale = 1.35, time = 0.42, spin = 9 },
	layers = { 1, 3, 6, 12, 24, 48, 80 },
	layerSpread = { 0.8, 0.28 },
	layerTurn = 0,
	pickup = { flyTime = 0.3, flyArc = 1.0, chest = 0.5, shrink = 0.7 },
}

return DropStackConfig
