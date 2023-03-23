local byte = require("byte")
local nbt = require("mc.nbt")
local ffi = require("ffi")
local mc_util = require("mc.util")
local Section = require("mc.Section")

local Chunk = {}

function Chunk:new()
	local chunk = setmetatable({}, self)
	self.__index = self

	chunk.sections = {}

	return chunk
end

function Chunk:getPosition()
	local t = self.nbt
	return t.xPos, t.yPos, t.zPos
end

function Chunk:init(cx, cz)
	local chunk_nbt = {{}}
	self.nbt = chunk_nbt

	nbt.set(chunk_nbt, "DataVersion", 3218, "int")
	nbt.set(chunk_nbt, "Status", "full", "string")
	nbt.set(chunk_nbt, "xPos", cx, "int")
	nbt.set(chunk_nbt, "yPos", 0, "int")  -- it doesn't matter
	nbt.set(chunk_nbt, "zPos", cz, "int")
	nbt.set(chunk_nbt, "sections", {tag_id = "compound"}, "list")
end

function Chunk:decode(p)
	local length = byte.read_uint32_be(p)
	local compression_type = byte.read_uint8(p + 4)
	assert(compression_type == 2)

	local chunk_nbt_ptr, chunk_nbt_size = mc_util.uncompress(p + 5, length - 1)
	local chunk_nbt, size, name, tag_id = nbt.decode(chunk_nbt_ptr)
	self.nbt = chunk_nbt

	local sections = {}
	self.sections = sections

	for i, section in ipairs(self.nbt.sections) do
		local _section = Section:new()
		_section.nbt = section
		sections[section.Y] = _section
	end
end

function Chunk:encode(p)
	local size = nbt.encode(p, self.nbt, "", "compound")
	local chunk_nbt_ptr, chunk_nbt_size = mc_util.compress(p, size)

	byte.write_uint32_be(p, chunk_nbt_size + 1)
	byte.write_uint8(p + 4, 2)
	ffi.copy(p + 5, chunk_nbt_ptr, chunk_nbt_size)

	return 5 + chunk_nbt_size
end

function Chunk:getSection(sy)
	return self.sections[sy]
end

function Chunk:setSection(section)
	local section_nbt = section.nbt
	self.sections[section_nbt.Y] = section

	local sections = self.nbt.sections
	for i, _section_nbt in ipairs(sections) do
		if _section_nbt.Y == section_nbt.Y then
			sections[i] = section_nbt
			return
		end
	end

	table.insert(sections, section_nbt)
end

function Chunk:getBlock(x, y, z)
	local section = self:getSection(math.floor(y / 16))
	if not section then
		return
	end
	return section:getBlock(x, y, z)
end

function Chunk:setBlock(x, y, z, block_state)
	local cy = math.floor(y / 16)
	local section = self:getSection(cy)
	if not section then
		section = Section:new()
		section:init(cy)
		self:setSection(section)
	end
	return section:setBlock(x, y, z, block_state)
end

function Chunk:getBiome(x, y, z)
	local section = self:getSection(math.floor(y / 16))
	if not section then
		return
	end
	return section:getBiome(x, y, z)
end

function Chunk:setBiome(x, y, z, biome)
	local cy = math.floor(y / 16)
	local section = self:getSection(cy)
	if not section then
		section = Section:new()
		section:init(cy)
		self:setSection(section)
	end
	return section:setBiome(x, y, z, biome)
end

return Chunk
