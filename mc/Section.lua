local nbt = require("mc.nbt")

local Section = {}

function Section:new()
	local section = setmetatable({}, self)
	self.__index = self
	return section
end

function Section:getY()
	return self.nbt.Y
end

local function get_palette_bits(size)
	return size <= 16 and 4 or math.floor(math.log(size - 1, 2)) + 1
end

local function create_block_states(section_nbt, block_states)
	block_states = block_states or {{}}
	nbt.set(section_nbt, "block_states", block_states, "compound")

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

function Section:init(cy)
	local section_nbt = {{}}

	nbt.set(section_nbt, "Y", cy, "byte")
	create_block_states(section_nbt)

	self:setTag(section_nbt)
end

function Section:setTag(section_nbt)
	self.nbt = section_nbt

	local block_states = section_nbt.block_states
	if not block_states then
		block_states = create_block_states(section_nbt)
		-- return
	end

	local palette = block_states.palette
	self.bits = get_palette_bits(#palette)
end

function Section:getPalette()
	return self.nbt.block_states.palette
end

local function set_block_state_index(data, bits, block_index, block_state_index)
	local indices = math.floor(64 / bits)
	local mask = bit.lshift(1, bits) - 1ULL

	local v_index = math.floor(block_index / indices) + 1
	local bits_offset = block_index % indices * bits

	local v = data[v_index]
	v = bit.ror(v, bits_offset)
	v = bit.band(v, bit.bnot(mask))
	v = bit.bor(v, block_state_index - 1)
	v = bit.rol(v, bits_offset)
	data[v_index] = v
end

local function get_block_state_index(data, bits, block_index)
	local indices = math.floor(64 / bits)
	local mask = bit.lshift(1, bits) - 1ULL

	local v_index = math.floor(block_index / indices) + 1
	local bits_offset = block_index % indices * bits

	local v = data[v_index]
	local i = bit.band(bit.rshift(v, bits_offset), mask) + 1

	return tonumber(i)
end

function Section:getBlock(x, y, z)
	local block_states = self.nbt.block_states
	if not block_states then
		return
	end

	local palette = block_states.palette
	if #palette == 1 then
		return palette[1]
	end

	local index = (y % 16) * 256 + z % 16 * 16 + x % 16

	local i = get_block_state_index(block_states.data, self.bits, index)

	return palette[tonumber(i)]
end

function Section:addBlockState(block_state)
	local bs_type = nbt.type(block_state)
	assert(bs_type == "compound", "compound expected, got " .. bs_type)

	local block_states = self.nbt.block_states
	local palette = block_states.palette

	for i, _block_state in ipairs(palette) do
		if nbt.equal(block_state, _block_state) then
			return i
		end
	end

	table.insert(palette, block_state)
	local bits = get_palette_bits(#palette)
	if bits > self.bits then
		self:rearrangeBlockStates(bits)
	end

	return #palette
end

function Section:rearrangeBlockStates(bits)
	local data = self.nbt.block_states.data

	local new_data = {}
	for i = 1, math.ceil(4096 / math.floor(64 / bits)) do
		new_data[i] = 0LL
	end

	for i = 0, 0x1000 - 1 do
		set_block_state_index(new_data, bits, i, get_block_state_index(data, self.bits, i))
	end

	self.nbt.block_states.data = new_data
	self.bits = bits
end

function Section:setBlock(x, y, z, block_state)
	local block_states = self.nbt.block_states
	if not block_states.data then
		local data = {}
		for i = 1, math.ceil(4096 / math.floor(64 / self.bits)) do
			data[i] = 0LL
		end
		nbt.set(block_states, "data", data, "long_array")
	end

	local block_state_index = self:addBlockState(block_state)
	local index = (y % 16) * 256 + z % 16 * 16 + x % 16
	set_block_state_index(block_states.data, self.bits, index, block_state_index)
end

return Section
