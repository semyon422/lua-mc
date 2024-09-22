local class = require("class")
local nbt = require("mc.nbt")

---@class mc.NbtChunk
---@operator call: mc.NbtChunk
local NbtChunk = class()

---@param tag table
function NbtChunk:new(tag)
	self.tag = tag
end

---@param p ffi.cdata*
---@param size integer
function NbtChunk:read(p, size)
	local chunk_nbt = nbt.decode(p)
	self.tag = chunk_nbt
end

---@param p ffi.cdata*
---@param size integer
function NbtChunk:write(p, size)
	local _size = nbt.encode(p, "compound", self.tag)
	return _size
end

return NbtChunk
