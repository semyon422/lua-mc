local byte = require("byte")
local ffi = require("ffi")

-- Named Binary Tag

local nbt = {}

local tag_ids = {
	[0] = "end",
	"byte",
	"short",
	"int",
	"long",
	"float",
	"double",
	"byte_array",
	"string",
	"list",
	"compound",
	"int_array",
	"long_array",
}
for k, v in pairs(tag_ids) do
	tag_ids[v] = k
end

local function assert_tag_id(tag_id)
	assert(type(tag_id) == "string" and tag_ids[tag_id], "unknown tag: " .. tostring(tag_id))
	return tag_id
end

-- tag_size[tag_id] returns payload size for lua value

local tag_size = {}

function tag_size.byte() return 1 end
function tag_size.short() return 2 end
function tag_size.int() return 4 end
function tag_size.long() return 8 end
function tag_size.float() return 4 end
function tag_size.double() return 8 end
function tag_size.string(s) return 2 + #s end
function tag_size.byte_array(array) return 4 + #array end
function tag_size.int_array(array) return 4 + 4 * #array end
function tag_size.long_array(array) return 4 + 8 * #array end

function tag_size.list(list)
	local sizer = tag_size[list.tag_id]
	local length = 0
	for i = 1, #list do
		length = length + sizer(list[i])
	end
	return length + 5
end

function tag_size.compound(compound)
	local length = 0
	for name, value, tag_id in nbt.iter(compound) do
		length = length + nbt.size(value, name, tag_id)
	end
	return length + 1
end

-- tag_bound[tag_id] yields number of bytes required for decoding tag payload
-- tag_bound.bound yields number of bytes required for decoding tag
-- tag_bound[tag_id] returns nothing
-- tag_bound.bound returns true if tag_id is not end

local tag_bound = {}

function tag_bound.byte() return coroutine.yield(1) end
function tag_bound.short() return coroutine.yield(2) end
function tag_bound.int() return coroutine.yield(4) end
function tag_bound.long() return coroutine.yield(8) end
function tag_bound.float() return coroutine.yield(4) end
function tag_bound.double() return coroutine.yield(8) end

function tag_bound.string()
	local p = coroutine.yield(2)
	local size = byte.read_uint16_be(p)
	return coroutine.yield(size)
end

local function bound_array(bytes)
	local p = coroutine.yield(4)
	return coroutine.yield(bytes * byte.read_int32_be(p))
end

function tag_bound.byte_array() return bound_array(1) end
function tag_bound.int_array() return bound_array(4) end
function tag_bound.long_array() return bound_array(8) end

function tag_bound.list()
	local p = coroutine.yield(1)
	local tag_id = tag_ids[byte.read_uint8(p)]
	p = coroutine.yield(4)
	local count = byte.read_int32_be(p)
	local bound = tag_bound[tag_id]
	for i = 1, count do
		bound()
	end
end

function tag_bound.compound()
	repeat until tag_bound.bound()
end

function tag_bound.bound()
	local p = coroutine.yield(1)
	local tag_id = tag_ids[byte.read_uint8(p)]
	if tag_id == "end" then
		return true
	end
	p = coroutine.yield(2)
	p = coroutine.yield(byte.read_uint16_be(p))
	tag_bound[tag_id](p)
end

-- equal[*] returns true if array/list/compound are equal

local equal = {}

function equal.array(a, b)
	if #a ~= #b then
		return false
	end
	for i = 1, #a do
		if not nbt.equal(a[i], b[i]) then
			return false
		end
	end
	return true
end

function equal.list(a, b)
	return a.tag_id == b.tag_id and equal.array(a, b)
end

function equal.compound(a, b)
	local size, _size = 0, 0
	for name, value, tag_id in nbt.iter(a) do
		size = size + 1
		local _value, _tag_id = nbt.get(b, name)
		if _tag_id ~= tag_id or not nbt.equal(value, _value) then
			return false
		end
	end
	for _ in nbt.iter(b) do
		_size = _size + 1
	end
	return size == _size
end

-- pl_enc[tag_id] is decoder (nbt to lua)
-- pl_dec[tag_id] is encoder (lua to nbt)
-- decoders take pointer to the tag payload, return decoded data and length of payload
-- encoders take pointer to the tag payload, value to encode, return length of payload

local pl_enc = {}
local pl_dec = {}

function pl_enc.byte(p, n) byte.write_int8(p, n) return 1 end
function pl_enc.short(p, n) byte.write_int16_be(p, n) return 2 end
function pl_enc.int(p, n) byte.write_int32_be(p, n) return 4 end
function pl_enc.long(p, n) byte.write_int64_be(p, n) return 8 end
function pl_enc.float(p, n) byte.write_float_be(p, n) return 4 end
function pl_enc.double(p, n) byte.write_double_be(p, n) return 8 end

function pl_dec.byte(p) return byte.read_int8(p), 1 end
function pl_dec.short(p) return byte.read_int16_be(p), 2 end
function pl_dec.int(p) return byte.read_int32_be(p), 4 end
function pl_dec.long(p) return byte.read_int64_be(p), 8 end
function pl_dec.float(p) return byte.read_float_be(p), 4 end
function pl_dec.double(p) return byte.read_double_be(p), 8 end

function pl_enc.string(p, s)
	byte.write_uint16_be(p, #s)
	ffi.copy(p + 2, s, #s)
	return #s + 2
end

function pl_dec.string(p)
	local size = byte.read_uint16_be(p)
	return ffi.string(p + 2, size), size + 2
end

function pl_enc.list(p, list)
	local length = 5
	byte.write_uint8(p, tag_ids[list.tag_id])
	byte.write_int32_be(p + 1, #list)
	if #list == 0 then
		return length
	end
	p = p + 5
	local decode = pl_enc[list.tag_id]
	for i = 1, #list do
		local size = decode(p, list[i])
		length = length + size
		p = p + size
	end
	return length
end

function pl_dec.list(p)
	local length = 5
	local tag_id = tag_ids[byte.read_uint8(p)]
	local count = byte.read_int32_be(p + 1)
	local list = {tag_id = tag_id}
	if count == 0 then
		return list, length
	end
	p = p + 5
	local decode = pl_dec[tag_id]
	for i = 1, count do
		local value, size = decode(p)
		list[i] = value
		length = length + size
		p = p + size
	end
	return list, length
end

local function encode_array(p, array, encode)
	local length = 4
	byte.write_int32_be(p, #array)
	if #array == 0 then
		return length
	end
	p = p + 4
	for i = 1, #array do
		local size = encode(p, array[i])
		length = length + size
		p = p + size
	end
	return length
end

local function decode_array(p, decode)
	local length = 4
	local count = byte.read_int32_be(p)
	local array = {}
	if count == 0 then
		return array, length
	end
	p = p + 4
	for i = 1, count do
		local value, size = decode(p)
		array[i] = value
		length = length + size
		p = p + size
	end
	return array, length
end

function pl_enc.byte_array(p, array) return encode_array(p, array, pl_enc.byte) end
function pl_enc.int_array(p, array) return encode_array(p, array, pl_enc.int) end
function pl_enc.long_array(p, array) return encode_array(p, array, pl_enc.long) end

function pl_dec.byte_array(p) return decode_array(p, pl_dec.byte) end
function pl_dec.int_array(p) return decode_array(p, pl_dec.int) end
function pl_dec.long_array(p) return decode_array(p, pl_dec.long) end

function pl_enc.compound(p, compound)
	local length = 0
	for name, value, tag_id in nbt.iter(compound) do
		local size = nbt.encode(p, value, name, tag_id)
		length = length + size
		p = p + size
	end
	return length + nbt.encode(p, nil, nil, "end")
end

function pl_dec.compound(p)
	local length = 0
	local compound = {{}}
	while true do
		local value, size, name, tag_id = nbt.decode(p)
		length = length + size
		p = p + size
		if not value then
			break
		end
		nbt.set(compound, name, value, tag_id)
	end
	return compound, length
end

-- stringified nbt
-- snbt[tag_id] returns string representation of lua value

local snbt = {}

snbt.indent = "  "
snbt.new_line = "\n"

local function snbt_end(bracket, depth, buffer)
	if #buffer == 1 then
		return buffer[1] .. bracket
	end
	local i, n = snbt.indent, snbt.new_line
	return table.concat(buffer, n .. i:rep(depth)) .. n .. i:rep(depth - 1) .. bracket
end

function snbt.byte(v) return tonumber(v) .. "b" end
function snbt.short(v) return tonumber(v) .. "s" end
function snbt.int(v) return tonumber(v) end
function snbt.long(v) return tostring(v):match("^(.-)[^0-9]*$") .. "l" end
function snbt.float(v) return tonumber(v) .. "f" end
function snbt.double(v) return tonumber(v) .. "d" end
function snbt.string(v) return ("%q"):format(v) end

function snbt.compound(obj, depth)
	local sorted_keys = {}
	for name in nbt.iter(obj) do
		table.insert(sorted_keys, name)
	end
	table.sort(sorted_keys)
	local buffer = {"{"}
	for i, name in ipairs(sorted_keys) do
		local value, tag_id = nbt.get(obj, name)
		local comma = i ~= #sorted_keys and "," or ""
		table.insert(buffer, name .. ": " .. nbt.string(value, tag_id, depth + 1) .. comma)
	end
	return snbt_end("}", depth, buffer)
end

function snbt.list(obj, depth)
	local buffer = {"["}
	for i = 1, #obj do
		local comma = i ~= #obj and "," or ""
		table.insert(buffer, nbt.string(obj[i], obj.tag_id, depth + 1) .. comma)
	end
	return snbt_end("]", depth, buffer)
end

local function snbt_array(obj, depth, array_char, tag_id)
	local buffer = {"[" .. array_char}
	for i = 1, #obj do
		local comma = i ~= #obj and "," or ""
		table.insert(buffer, nbt.string(obj[i], tag_id, depth + 1) .. comma)
	end
	if #buffer > 1 then
		buffer[1] = buffer[1] .. ";"
	end
	return snbt_end("]", depth, buffer)
end

function snbt.byte_array(obj, depth) return snbt_array(obj, depth, "B", "byte") end
function snbt.int_array(obj, depth) return snbt_array(obj, depth, "I", "int") end
function snbt.long_array(obj, depth) return snbt_array(obj, depth, "L", "long") end

-- public nbt interface

function nbt.decode(p)
	local tag_id = tag_ids[byte.read_uint8(p)]
	if tag_id == "end" then
		return nil, 1, nil, tag_id
	end
	local name_length = byte.read_uint16_be(p + 1)
	local name = ""
	if name_length > 0 then
		name = ffi.string(p + 3, name_length)
	end
	local decode = pl_dec[tag_id]
	local obj, size = decode(p + 3 + name_length)
	return obj, 3 + name_length + size, name, tag_id
end

function nbt.encode(p, obj, name, tag_id)
	assert_tag_id(tag_id)
	byte.write_uint8(p, tag_ids[tag_id])
	if tag_id == "end" then
		return 1
	end
	name = name or ""
	byte.write_uint16_be(p + 1, #name)
	if #name > 0 then
		ffi.copy(p + 3, name, #name)
	end
	local encode = pl_enc[tag_id]
	local size = encode(p + 3 + #name, obj)
	return 3 + #name + size
end

function nbt.size(obj, name, tag_id)
	assert_tag_id(tag_id)
	if tag_id == "end" then
		return 1
	end
	local get_size = tag_size[tag_id]
	local size = get_size(obj)
	return 3 + #(name or "") + size
end

function nbt.bound(p, size)
	local offset = 0
	local bound = coroutine.wrap(tag_bound.bound)
	local ps = 0
	while true do
		local s = bound(p + offset - ps)
		ps = s
		if not s then
			return true
		end
		if offset + s > size then
			return false
		end
		offset = offset + s
	end
end

function nbt.set(compound, name, value, tag_id)
	assert_tag_id(tag_id)
	compound[1][name] = tag_id
	compound[name] = value
	return compound
end

function nbt.get(compound, name)
	return compound[name], compound[1][name]
end

--[[
	array:
		{}
		{1}
	list:
		{tag_id = "byte"}
		{tag_id = "byte", 1}
		{tag_id = "compound"}
		{tag_id = "compound", {{}}}
		{tag_id = "array"}
		{tag_id = "array", {}}
		{tag_id = "list"}
		{tag_id = "list", {tag_id = "byte"}}
		{{{tag_id = "string"}, tag_id = "compound"}, tag_id = "compound"}
	compound:
		{{}}
		{{k = "byte"}, k = 1}
		{{tag_id = "string"}, tag_id = "compound"}
	invalid (nil):
		{{{}}}
		{tag_id = "", {tag_id = "", {}}}
]]
function nbt.type(obj)
	if type(obj) ~= "table" then
		return
	end
	local is_table = type(obj[1]) == "table"
	if not obj.tag_id and not is_table then
		return "array"
	end
	if obj.tag_id and not (is_table and obj[1].tag_id and obj[1][1]) then
		return "list"
	end
	if is_table and not obj[1][1] then
		return "compound"
	end
end

function nbt.equal(a, b)
	if type(a) ~= "table" or type(b) ~= "table" then
		return a == b
	end
	if a == b then
		return true
	end
	local ta, tb = nbt.type(a), nbt.type(b)
	if ta ~= tb then
		return false
	end
	local eq = equal[ta]
	return eq and eq(a, b)
end

function nbt.string(obj, tag_id, depth)
	if not tag_id then
		tag_id = nbt.type(obj)
		assert(tag_id ~= "array", "Unknown array type")
	end
	local to_snbt = snbt[tag_id]
	if not to_snbt then
		return ""
	end
	return snbt[tag_id](obj, depth or 1)
end

local function next_compound(compound, name)
	local name, tag_id = next(compound[1], name)
	return name, compound[name], tag_id
end

function nbt.iter(compound)
	return next_compound, compound, nil
end

--------------------------------------------------------------------------------
-- tests
--------------------------------------------------------------------------------

local test_tag0 = {
	{k = "byte", l = "list", j = "byte_array", m = "compound", n = "string", o = "long"},
	k = -128,
	l = {tag_id = "compound", {{}}, {{}}},
	j = {1, 2, 3},
	m = {{k = "list"}, k = {tag_id = "byte_array", {}, {}}},
	n = "qwerty",
	o = -1LL,
}

local test_tag1 = {{}}
nbt.set(test_tag1, "k", -128, "byte")
nbt.set(test_tag1, "l", {tag_id = "compound", {{}}, {{}}}, "list")
nbt.set(test_tag1, "j", {1, 2, 3}, "byte_array")
nbt.set(test_tag1, "m", nbt.set({{}}, "k", {tag_id = "byte_array", {}, {}}, "list"), "compound")
nbt.set(test_tag1, "n", "qwerty", "string")
nbt.set(test_tag1, "o", -1LL, "long")

local test_tag2
do
	local size = nbt.size(test_tag1, "", "compound")
	assert(size == 77)
	local p = ffi.new("uint8_t[?]", size)
	nbt.encode(p, test_tag1, "", "compound")
	test_tag2 = nbt.decode(p)
	assert(nbt.bound(p, size))
	assert(not nbt.bound(p, size - 1))
end

assert(nbt.equal(test_tag0, test_tag1))
assert(nbt.equal(test_tag1, test_tag2))
assert(not nbt.equal({{{}}}, {{{}}}))
assert(nbt.size(test_tag2, "", "compound") == 77)
assert(nbt.string(test_tag2) == [[{
  j: [B;
    1b,
    2b,
    3b
  ],
  k: -128b,
  l: [
    {},
    {}
  ],
  m: {
    k: [
      [B],
      [B]
    ]
  },
  n: "qwerty",
  o: -1l
}]])

return nbt
