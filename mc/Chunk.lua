local class = require("class")
local nbt = require("mc.nbt")
local Section = require("mc.Section")

---@class mc.Chunk
---@operator call: mc.Chunk
local Chunk = class()

Chunk.defaultDataVersion = 3578  -- 1.20.2

function Chunk:new()
	self.sections = {}
end

---@param p ffi.cdata*
---@param size integer
function Chunk:read(p, size)
	local chunk_nbt = nbt.decode(p)
	self.tag = chunk_nbt
	self:readSections()
end

---@param p ffi.cdata*
---@param size integer
function Chunk:write(p, size)
	local _size = nbt.encode(p, "compound", self.tag)
	return _size
end

function Chunk:getPosition()
	local t = self.tag
	return t.xPos, t.yPos, t.zPos
end

function Chunk:init(cx, cz)
	local chunk_nbt = {{}}
	self.tag = chunk_nbt

	nbt.set(chunk_nbt, "DataVersion", self.defaultDataVersion, "int")
	nbt.set(chunk_nbt, "Status", "full", "string")
	nbt.set(chunk_nbt, "xPos", cx, "int")
	nbt.set(chunk_nbt, "yPos", 0, "int")  -- it doesn't matter
	nbt.set(chunk_nbt, "zPos", cz, "int")
	nbt.set(chunk_nbt, "sections", {tag_id = "compound"}, "list")
end

function Chunk:readSections()
	local sections = {}
	self.sections = sections

	for i, section in ipairs(self.tag.sections) do
		local _section = Section:new()
		_section.nbt = section
		sections[section.Y] = _section
	end
end

function Chunk:getSection(sy)
	return self.sections[sy]
end

function Chunk:setSection(section)
	local section_nbt = section.nbt
	self.sections[section_nbt.Y] = section

	local sections = self.tag.sections
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

function Chunk:getHeight(x, z, bits, name)
	local index = z % 16 * 16 + x % 16
	return Section.get_data_index(self.tag.Heightmaps[name], bits, index) + self.tag.yPos * 16 - 2
end

return Chunk
