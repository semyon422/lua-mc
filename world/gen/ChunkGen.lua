local class = require("class")
local Chunk = require("mc.Chunk")

---@class world.ChunkGen
---@operator call: world.ChunkGen
local ChunkGen = class()

---@param cx integer
---@param cz integer
---@return mc.Chunk
function ChunkGen:gen(cx, cz)
	local chunk = Chunk()
	chunk:init(cx, cz)
	return chunk
end

return ChunkGen
