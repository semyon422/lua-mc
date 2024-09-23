local class = require("class")
local ffi = require("ffi")
local mc_util = require("mc.util")
local ChunkInfo = require("mc.ChunkInfo")
local RawChunk = require("mc.RawChunk")

---@class mc.RawRegion
---@operator call: mc.RawRegion
local RawRegion = class()

---@param path string
---@param rx integer
---@param rz integer
function RawRegion:new(path, rx, rz)
	self.path = path
	self:setPos(rx, rz)
	self.sector_offset = 2
end

---@param rx integer
---@param rz integer
function RawRegion:setPos(rx, rz)
	self.rx = rx
	self.rz = rz
end

---@param p ffi.cdata*
---@param size integer
function RawRegion:setPointer(p, size)
	self.pointer = p
	self.size = size
end

---@param size integer
function RawRegion:allocate(size)
	self:setPointer(ffi.new("uint8_t[?]", size), size)
end

function RawRegion:reset()
	ffi.fill(self.pointer, self.size, 0)
	self.sector_offset = 2
end

---@return true?
---@return string?
function RawRegion:read()
	local path = mc_util.get_region_path(self.path, self.rx, self.rz)
	local file, err = io.open(path, "rb")
	if not file then
		return nil, err
	end

	self.data = file:read("*a")
	file:close()

	if #self.data == 0 then
		return nil, "empty file"
	end

	self:setPointer(ffi.cast("const uint8_t*", self.data), #self.data)

	return true
end

function RawRegion:write()
	local sector_offset = 2
	for i = 0, 1023 do
		local chunk_info = self:getChunkInfo(i)
		if chunk_info then
			sector_offset = sector_offset + chunk_info.sectors
		end
	end

	local path = mc_util.get_region_path(self.path, self.rx, self.rz)
	local file = assert(io.open(path, "wb"))
	file:write(ffi.string(self.pointer, sector_offset * 0x1000))
	file:close()
end

---@param sector_offset integer
---@return ffi.cdata*
function RawRegion:getSectorPtr(sector_offset)
	return self.pointer + sector_offset * 0x1000
end

---@param index integer
---@return mc.ChunkInfo?
function RawRegion:getChunkInfo(index)
	local chunk_info = ChunkInfo(index)
	if chunk_info:read(self.pointer) then
		return chunk_info
	end
end

---@param index integer
---@return mc.RawChunk?
---@return mc.ChunkInfo?
function RawRegion:getRawChunkIndex(index)
	local chunk_info = self:getChunkInfo(index)
	if not chunk_info then
		return
	end

	local raw_chunk = RawChunk()
	raw_chunk:read(chunk_info:getChunkPtr(self.pointer))

	return raw_chunk, chunk_info
end

---@param cx integer
---@param cz integer
---@return mc.RawChunk?
---@return mc.ChunkInfo?
function RawRegion:getRawChunk(cx, cz)
	local index = mc_util.get_chunk_index(cx % 32, cz % 32)
	return self:getRawChunkIndex(index)
end

---@param chunk_info mc.ChunkInfo
---@param raw_chunk mc.RawChunk
function RawRegion:setRawChunk(chunk_info, raw_chunk)
	chunk_info:write(self.pointer)
	raw_chunk:write(chunk_info:getChunkPtr(self.pointer))
end

---@param raw_chunk mc.RawChunk
function RawRegion:addRawChunkIndex(index, raw_chunk)
	local chunk_info = ChunkInfo(index)
	chunk_info.sector_offset = self.sector_offset
	chunk_info.sectors = raw_chunk:getSectors()
	chunk_info.timestamp = os.time()

	self.sector_offset = self.sector_offset + chunk_info.sectors

	self:setRawChunk(chunk_info, raw_chunk)
end

---@param cx integer
---@param cz integer
---@param raw_chunk mc.RawChunk
function RawRegion:addRawChunk(cx, cz, raw_chunk)
	local index = mc_util.get_chunk_index(cx % 32, cz % 32)
	return self:addRawChunkIndex(index, raw_chunk)
end

return RawRegion
