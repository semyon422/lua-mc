local byte = require("byte")
local ffi = require("ffi")
local Chunk = require("mc.Chunk")
local mc_util = require("mc.util")

local Region = {}

function Region:new(path, rx, rz)
	local region = setmetatable({}, self)
	self.__index = self

	region.x = rx
	region.z = rz
	region.path = path
	region.chunks = {}
	region:read()

	return region
end

function Region:read()
	local path = mc_util.get_region_path(self.path, self.x, self.z)
	local file = io.open(path, "rb")
	if not file then
		self.missing = true
		return
	end

	self.data = file:read("*a")
	file:close()

	if #self.data == 0 then
		self.missing = true
		return
	end

	self.pointer = ffi.cast("const uint8_t*", self.data)
	self.size = #self.data
end

local function write_chunk_info(p, i, offset, sectors, timestamp)
	byte.write_uint32_be(p + i * 4, bit.bor(bit.lshift(offset, 8), sectors))
	byte.write_uint32_be(p + i * 4 + 0x1000, timestamp)
end

function Region:write()
	local sectors_out = 0
	local _timestamp = os.time()

	local chunks_by_index = self.chunks
	local raw_chunks = {}

	for i = 0, 1023 do
		local chunk = chunks_by_index[i]
		if chunk then
			local size = chunk:encode_bound()
			sectors_out = sectors_out + mc_util.to_sectors(size)
		else
			local offset, sectors, timestamp = self:getRawChunk(i)
			if offset then
				sectors_out = sectors_out + sectors
				raw_chunks[i] = {offset, sectors, timestamp}
			end
		end
	end

	if sectors_out == 0 then
		return
	end

	local p = ffi.new("uint8_t[?]", (sectors_out + 2) * 0x1000)
	local _p = self.pointer

	local sector_offset = 0
	for i = 0, 1023 do
		if chunks_by_index[i] then
			local size = chunks_by_index[i]:encode(p + sector_offset * 0x1000)
			local sectors = mc_util.to_sectors(size)
			write_chunk_info(p, i, sector_offset, sectors, _timestamp)
			sector_offset = sector_offset + sectors
		elseif raw_chunks[i] then
			local offset, sectors, timestamp = unpack(raw_chunks[i])
			ffi.copy(p + sector_offset * 0x1000, _p + offset * 0x1000, sectors * 0x1000)
			write_chunk_info(p, i, sector_offset, sectors, timestamp)
			sector_offset = sector_offset + sectors
		end
	end

	local path = mc_util.get_region_path(self.path, self.x, self.z)
	local file = assert(io.open(path, "wb"))
	file:write(ffi.string(p, (sector_offset + 2) * 0x1000))
	file:close()

	return true
end

function Region:getRawChunk(index)
	if self.missing then
		return
	end

	local p = self.pointer + index * 4

	local v = byte.read_uint32_be(p)
	local offset = bit.rshift(v, 8)
	if offset == 0 then
		return
	end

	local sectors = bit.band(v, 0xFF)
	local timestamp = byte.read_uint32_be(p + 0x1000)

	return offset, sectors, timestamp
end

function Region:setRawChunk(index, offset, timestamp, p, size)
	local _p = self.pointer + offset * 0x1000

	byte.write_uint32_be(_p, size + 1)
	byte.write_uint8(_p + 4, 2)
	ffi.copy(_p + 5, p, size)

	local sectors = mc_util.to_sectors(5 + size)
	write_chunk_info(self.pointer, index, offset, sectors, timestamp)
	return sectors
end

function Region:getChunk(cx, cz)
	local index = cx % 32 + cz % 32 * 32
	local chunk = self.chunks[index]
	if chunk then
		return chunk
	end
	chunk = Chunk:new()
	self.chunks[index] = chunk

	local offset = self:getRawChunk(index)
	if offset then
		chunk:decode(self.pointer + offset * 0x1000)
	else
		chunk:init(cx, cz)
	end
	return chunk
end

function Region:unloadChunk(cx, cz)
	local index = cx % 32 + cz % 32 * 32
	self.chunks[index] = nil
end

function Region:getBlock(x, y, z)
	local chunk = self:getChunk(mc_util.get_chunk_pos(x, z))
	return chunk:getBlock(x, y, z)
end

function Region:setBlock(x, y, z, block_state)
	local chunk = self:getChunk(mc_util.get_chunk_pos(x, z))
	return chunk:setBlock(x, y, z, block_state)
end

function Region:getBiome(x, y, z)
	local chunk = self:getChunk(mc_util.get_chunk_pos(x, z))
	return chunk:getBiome(x, y, z)
end

function Region:setBiome(x, y, z, block_state)
	local chunk = self:getChunk(mc_util.get_chunk_pos(x, z))
	return chunk:setBiome(x, y, z, block_state)
end

return Region
