local class = require("class")
local byte = require("byte")
local bit = require("bit")

---@class mc.ChunkInfo
---@operator call: mc.ChunkInfo
local ChunkInfo = class()

---@param index integer
---@param sector_offset integer?
---@param sectors integer?
---@param timestamp integer?
function ChunkInfo:new(index, sector_offset, sectors, timestamp)
	assert(index >= 0 and index < 1024)
	self.index = index
	self.sector_offset = sector_offset or 0
	self.sectors = sectors or 0
	self.timestamp = timestamp or 0
end

---@param ptr ffi.cdata*
---@return ffi.cdata*
function ChunkInfo:getChunkPtr(ptr)
	return ptr + self.sector_offset * 0x1000
end

---@param ptr ffi.cdata*
---@return true?
---@return string?
function ChunkInfo:read(ptr)
	local p = ptr + self.index * 4

	local v = byte.read_uint32_be(p)
	local sector_offset = bit.rshift(v, 8)
	if sector_offset == 0 then
		return nil, "empty chunk"
	end

	self.sector_offset = sector_offset
	self.sectors = bit.band(v, 0xFF)
	self.timestamp = byte.read_uint32_be(p + 0x1000)

	return true
end

---@param ptr ffi.cdata*
function ChunkInfo:write(ptr)
	local i = self.index
	byte.write_uint32_be(ptr + i * 4, bit.bor(bit.lshift(self.sector_offset, 8), self.sectors))
	byte.write_uint32_be(ptr + i * 4 + 0x1000, self.timestamp)
end

return ChunkInfo
