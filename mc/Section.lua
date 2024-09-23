local class = require("class")
local bit = require("bit")
local nbt = require("mc.nbt")

---@class mc.Section
---@operator call: mc.Section
local Section = class()

function Section:new()
	self.block_palette_cache = {}
	self.biome_palette_cache = {}
end

function Section:getY()
	return self.tag.Y
end

local bits_cache = {}
local function get_palette_bits(size, min)
	if size <= 2 ^ min then
		return min
	end
	local bits = bits_cache[size]
	if bits then
		return bits
	end
	bits_cache[size] = math.floor(math.log(size - 1, 2)) + 1
	return bits_cache[size]
end

local function create_block_states(section_tag, block_states)
	block_states = block_states or {{}}
	nbt.set(section_tag, "block_states", block_states, "compound")

	local data = {}
	for i = 1, 256 do
		data[i] = 0LL
	end

	local palette = {tag_id = "compound",
		nbt.set({{}}, "Name", "minecraft:air", "string")
	}

	nbt.set(block_states, "data", data, "long_array")
	nbt.set(block_states, "palette", palette, "list")

	return block_states
end

local function create_biomes(section_tag, biomes)
	biomes = biomes or {{}}
	nbt.set(section_tag, "biomes", biomes, "compound")

	local data = {0LL, 0LL}

	local palette = {tag_id = "string",
		"minecraft:plains"
	}

	nbt.set(biomes, "data", data, "long_array")
	nbt.set(biomes, "palette", palette, "list")

	return biomes
end

local function set_data_index(data, bits, index, palette_index)
	if not data or bits == 0 then
		return
	end

	local indices = math.floor(64 / bits)
	local mask = bit.lshift(1, bits) - 1ULL

	local v_index = math.floor(index / indices) + 1
	local bits_offset = index % indices * bits

	local v = data[v_index]
	v = bit.ror(v, bits_offset)
	v = bit.band(v, bit.bnot(mask))
	v = bit.bor(v, palette_index - 1)
	v = bit.rol(v, bits_offset)
	data[v_index] = v
end
Section.set_data_index = set_data_index

local function get_data_index(data, bits, index)
	if not data or bits == 0 then
		return 1
	end

	local indices = math.floor(64 / bits)
	local mask = bit.lshift(1, bits) - 1ULL

	local v_index = math.floor(index / indices) + 1
	local bits_offset = index % indices * bits

	local v = data[v_index]
	local i = bit.band(bit.rshift(v, bits_offset), mask) + 1

	return tonumber(i)
end
Section.get_data_index = get_data_index

local function rearrange_states(root, states, bits, new_bits)
	local data = root.data

	local new_data = {}
	for i = 1, math.ceil(states / math.floor(64 / new_bits)) do
		new_data[i] = 0LL
	end

	for i = 0, states - 1 do
		set_data_index(new_data, new_bits, i, get_data_index(data, bits, i))
	end

	nbt.set(root, "data", new_data, "long_array")
end

local function add_palette_index(root, obj, states, min_bits, palette_cache)
	local cached_index = palette_cache[obj]
	if cached_index then
		return cached_index
	end

	local palette = root.palette
	for i, _obj in ipairs(palette) do
		if nbt.equal(obj, _obj) then
			palette_cache[obj] = i
			return i
		end
	end

	local bits = get_palette_bits(#palette, min_bits)
	table.insert(palette, obj)
	local new_bits = get_palette_bits(#palette, min_bits)
	if new_bits > bits then
		rearrange_states(root, states, bits, new_bits)
	end

	palette_cache[obj] = #palette
	return #palette
end

function Section:init(cy)
	local section_tag = {{}}
	self.tag = section_tag

	nbt.set(section_tag, "Y", cy, "byte")
	create_block_states(section_tag)
	create_biomes(section_tag)
end

function Section:getBlock(x, y, z)
	local block_states = self.tag.block_states
	if not block_states then
		return
	end
	local index = (y % 16) * 256 + z % 16 * 16 + x % 16
	local i = get_data_index(block_states.data, get_palette_bits(#block_states.palette, 4), index)
	return block_states.palette[i]
end

function Section:setBlock(x, y, z, block_state)
	local block_states = self.tag.block_states
	local block_state_index = add_palette_index(block_states, block_state, 4096, 4, self.block_palette_cache)
	local index = (y % 16) * 256 + z % 16 * 16 + x % 16
	set_data_index(block_states.data, get_palette_bits(#block_states.palette, 4), index, block_state_index)
end

function Section:mapBlock(sx, sz, f)
	local block_states = self.tag.block_states
	local palette_cache = self.block_palette_cache
	local data = block_states.data
	local palette = block_states.palette

	local sy = self.tag.Y

	local index = 0
	for y = 0, 15 do
		for z = 0, 15 do
			for x = 0, 15 do
				local block_state = f(sx * 16 + x, sy * 16 + y, sz * 16 + z)
				if block_state then
					local block_state_index = add_palette_index(block_states, block_state, 4096, 4, palette_cache)
					set_data_index(data, get_palette_bits(#palette, 4), index, block_state_index)
				end
				index = index + 1
			end
		end
	end
end

function Section:getBiome(x, y, z)
	local biomes = self.tag.biomes
	if not biomes then
		return
	end
	local index = math.floor(y % 16 / 4) * 16 + math.floor(z % 16 / 4) * 4 + math.floor(x % 16 / 4)
	local i = get_data_index(biomes.data, get_palette_bits(#biomes.palette, 0), index)
	return biomes.palette[i]
end

function Section:setBiome(x, y, z, biome)
	local biomes = self.tag.biomes
	local biome_index = add_palette_index(biomes, biome, 64, 0, self.biome_palette_cache)
	local index = math.floor(y % 16 / 4) * 16 + math.floor(z % 16 / 4) * 4 + math.floor(x % 16 / 4)
	set_data_index(biomes.data, get_palette_bits(#biomes.palette, 0), index, biome_index)
end

return Section
