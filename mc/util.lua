local ffi = require("ffi")

local zlib = ffi.load("z")
ffi.cdef([[
int uncompress(char *dest, unsigned long *destLen, const char *source, unsigned long sourceLen);
int compress2(char *dest, unsigned long *destLen, const char *source, unsigned long sourceLen, int level);
]])

local mc_util = {}

function mc_util.get_region_pos(x, z)
	return math.floor(x / 512), math.floor(z / 512)
end
function mc_util.get_region_pos_c(cx, cz)
	return math.floor(cx / 32), math.floor(cz / 32)
end

function mc_util.get_chunk_pos(x, z)
	return math.floor(x / 16), math.floor(z / 16)
end

function mc_util.get_region_chunk_pos(x, z)
	return math.floor(x / 16) % 32, math.floor(z / 16) % 32
end

mc_util.region_pattern = "r.%d.%d.mca"

function mc_util.match_region_path(path)
	local rx, rz = path:match("r%.(.+)%.(.+)%.mca")
	return tonumber(rx), tonumber(rz)
end

function mc_util.get_region_path(path, rx, rz)
	return path .. "/" .. mc_util.region_pattern:format(rx, rz)
end

local default_color = {1, 1, 1, 1}
function mc_util.get_block_color(name)
	local _name = name:match("^minecraft:(.+)$")
	if not _name then
		return default_color
	end

	local path = "block/" .. _name .. ".png"
	local path_top = "block/" .. _name .. "_top.png"
	local file_info = love.filesystem.getInfo(path)
	local file_top_info = love.filesystem.getInfo(path_top)
	if not file_info and not file_top_info then
		return default_color
	end
	if file_top_info and not file_info then
		path = path_top
	end

	local imageData = love.image.newImageData(path)
	local color = {imageData:getPixel(0, 0)}
	imageData:release()

	return color
end

local buf_out_size = 2 ^ 20
local buf_out = ffi.new("uint8_t[?]", buf_out_size)

mc_util.chunk_buffer_size = buf_out_size
mc_util.chunk_buffer = ffi.new("uint8_t[?]", buf_out_size)

function mc_util.uncompress(p, size)
	local out_size = ffi.new("size_t[1]", buf_out_size)
	assert(zlib.uncompress(buf_out, out_size, p, size) == 0)
	return buf_out, tonumber(out_size[0])
end

function mc_util.compress(p, size)
	local out_size = ffi.new("size_t[1]", buf_out_size)
	assert(zlib.compress2(buf_out, out_size, p, size, -1) == 0)
	return buf_out, tonumber(out_size[0])
end

function mc_util.to_sectors(size)
	return math.ceil(size / 0x1000)
end

function mc_util.next_block(range, i)
	i = i or 0

	local size = #range / 2
	assert(size == math.floor(size))

	local d, v, p = range.d, range.v, range.p
	if not d then
		d, v, p = {}, 1, {}
		for j = 1, size do
			d[j] = range[j + size] - range[j] + 1
			v = v * d[j]
		end
		range.d, range.v, range.p = d, v, p
	end

	if i + 1 > v then
		return
	end

	for j = 1, size do
		local a, b = d[size], 1
		for k = size - 1, j, -1 do
			a = a * d[k]
			b = b * d[k + 1]
		end
		p[j] = math.floor(i % a / b) + range[j]
	end
	-- 	for j = 1, size do
	-- 		local a, b = d[1], 1
	-- 		for k = 2, j do
	-- 			a = a * d[k]
	-- 			b = b * d[k - 1]
	-- 		end
	-- 		p[j] = math.floor(i % a / b) + range[j]
	-- 	end

	return i + 1, unpack(p)
end

function mc_util.iter(range)
	return mc_util.next_block, range, 0
end

return mc_util
