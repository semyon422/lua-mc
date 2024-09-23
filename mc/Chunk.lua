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
	local chunk_tag = nbt.decode(p)
	self.tag = chunk_tag
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
	local chunk_tag = {{}}
	self.tag = chunk_tag

	nbt.set(chunk_tag, "DataVersion", self.defaultDataVersion, "int")
	nbt.set(chunk_tag, "Status", "full", "string")
	nbt.set(chunk_tag, "xPos", cx, "int")
	nbt.set(chunk_tag, "yPos", 0, "int")  -- it doesn't matter
	nbt.set(chunk_tag, "zPos", cz, "int")
	nbt.set(chunk_tag, "sections", {tag_id = "compound"}, "list")
end

function Chunk:readSections()
	local sections = {}
	self.sections = sections

	for i, section in ipairs(self.tag.sections) do
		local _section = Section()
		_section.tag = section
		sections[section.Y] = _section
	end
end

function Chunk:getSection(sy)
	return self.sections[sy]
end

function Chunk:getOrCreateSection(sy)
	local section = self.sections[sy]
	if section then
		return section
	end

	section = Section()
	section:init(sy)
	self:setSection(section)

	return section
end

function Chunk:setSection(section)
	local section_tag = section.tag
	self.sections[section_tag.Y] = section

	local sections = self.tag.sections
	for i, _section_tag in ipairs(sections) do
		if _section_tag.Y == section_tag.Y then
			sections[i] = section_tag
			return
		end
	end

	table.insert(sections, section_tag)
end

function Chunk:getBlock(x, y, z)
	local section = self:getSection(math.floor(y / 16))
	if not section then
		return
	end
	return section:getBlock(x, y, z)
end

function Chunk:setBlock(x, y, z, block_state)
	local sy = math.floor(y / 16)
	local section = self:getOrCreateSection(sy)
	return section:setBlock(x, y, z, block_state)
end

function Chunk:mapBlock(sy_0, sy_1, f)
	local cx = self.tag.xPos
	local cz = self.tag.zPos

	for sy = sy_0, sy_1 do
		local section = self:getOrCreateSection(sy)
		section:mapBlock(cx, cz, f)
	end
end

function Chunk:getBiome(x, y, z)
	local section = self:getSection(math.floor(y / 16))
	if not section then
		return
	end
	return section:getBiome(x, y, z)
end

function Chunk:setBiome(x, y, z, biome)
	local sy = math.floor(y / 16)
	local section = self:getOrCreateSection(sy)
	return section:setBiome(x, y, z, biome)
end

function Chunk:getHeight(x, z, bits, name)
	local index = z % 16 * 16 + x % 16
	return Section.get_data_index(self.tag.Heightmaps[name], bits, index) + self.tag.yPos * 16 - 2
end

return Chunk
