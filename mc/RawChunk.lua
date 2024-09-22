local ffi = require("ffi")
local class = require("class")
local byte = require("byte")
local mc_util = require("mc.util")

---@class mc.RawChunk
---@operator call: mc.RawChunk
local RawChunk = class()

---@param ptr ffi.cdata*
function RawChunk:read(ptr)
	self.length = byte.read_uint32_be(ptr)
	self.compression_type = byte.read_uint8(ptr + 4)
	self.compressed_data_ptr = ptr + 5
end

---@param ptr ffi.cdata*
function RawChunk:write(ptr)
	byte.write_uint32_be(ptr, self.length)
	byte.write_uint8(ptr + 4, 2)
	ffi.copy(ptr + 5, self.compressed_data_ptr, self.length - 1)
end

---@return integer
function RawChunk:getSectors()
	return mc_util.to_sectors(self.length + 4)
end

---@return boolean
function RawChunk:isValid()
	return self.length > 0 and self.compression_type == 2
end

---@return ffi.cdata*
---@return integer
function RawChunk:decompressRaw()
	return mc_util.uncompress(self.compressed_data_ptr, self.length - 1)
end

---@param p ffi.cdata*
---@param size integer
function RawChunk:compressRaw(p, size)
	local _p, _size = mc_util.compress(p, size)
	self.compressed_data_ptr = _p
	self.length = _size + 1
end

return RawChunk
