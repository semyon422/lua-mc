local mc_util = require("mc.util")
local Region = require("mc.Region")

local World = {}

function World:new(region_path)
	local world = setmetatable({}, self)
	self.__index = self

	world.region_path = region_path
	world.regions = {}
	world.chunks = {}

	return world
end

function World:onChunkLoad(chunk) end
function World:onChunkUnload(chunk) end
function World:onRegionLoad(region) end
function World:onRegionUnload(region) end

function World:loadChunks(x, z, cr)
	local regions = self.regions
	local chunks = self.chunks
	local visible_regions = {}
	local visible_chunks = {}

	local x0, x1 = x - cr * 16, x + cr * 16
	local z0, z1 = z - cr * 16, z + cr * 16

	local cx0, cx1 = mc_util.get_chunk_pos(x0, x1)
	local cz0, cz1 = mc_util.get_chunk_pos(z0, z1)
	for cx = cx0, cx1 do
		for cz = cz0, cz1 do
			local rx, rz = mc_util.get_region_pos_c(cx, cz)
			local rkey = rx .. "." .. rz
			local region = regions[rkey]
			if not region then
				region = Region:new(self.region_path, rx, rz)
				if region then
					self:onRegionLoad(region)
				end
			end
			regions[rkey] = region
			visible_regions[rkey] = true

			local ckey = cx .. "." .. cz
			local chunk = chunks[ckey]
			if not chunk then
				chunk = region:getChunk(cx % 32, cz % 32)
				if chunk then
					self:onChunkLoad(chunk)
				end
			end
			chunks[ckey] = chunk
			visible_chunks[ckey] = true
		end
	end

	for key, chunk in pairs(chunks) do
		if not visible_chunks[key] then
			self:onChunkUnload(chunk)
			chunks[key] = nil
		end
	end
	for key, region in pairs(regions) do
		if not visible_regions[key] then
			self:onRegionUnload(region)
			regions[key] = nil
		end
	end
end

function World:unloadChunks()
	local regions = self.regions
	local chunks = self.chunks
	for key, chunk in pairs(chunks) do
		self:onChunkUnload(chunk)
		chunks[key] = nil
	end
	for key, region in pairs(regions) do
		self:onRegionUnload(region)
		regions[key] = nil
	end
end

function World:getBlock(x, y, z)
	local cx, cz = mc_util.get_chunk_pos(x, z)
	local ckey = cx .. "." .. cz
	local chunk = self.chunks[ckey]

	if not chunk then
		return
	end

	return chunk:getBlock(x, y, z)
end

function World:setBlock(x, y, z, block_state)
	local cx, cz = mc_util.get_chunk_pos(x, z)
	local ckey = cx .. "." .. cz
	local chunk = self.chunks[ckey]

	if not chunk then
		return
	end

	return chunk:setBlock(x, y, z, block_state)
end

return World
