local class = require("class")
local ffi = require("ffi")
local RawRegion = require("mc.RawRegion")
local RawChunk = require("mc.RawChunk")

---@class world.RegionGen
---@operator call: world.RegionGen
local RegionGen = class()

---@param region_path string
---@param chunk_gen world.ChunkGen
function RegionGen:new(region_path, chunk_gen)
	self.region_path = region_path
	self.chunk_gen = chunk_gen

	self.region = RawRegion(region_path, 0, 0)
	self.region:allocate(100e6)

	self.chunk_buf_size = 100e6
	self.chunk_buf = ffi.new("uint8_t[?]", self.chunk_buf_size)
end

---@param rx integer
---@param rz integer
function RegionGen:gen(rx, rz)
	local region = self.region

	region:setPos(rx, rz)
	region:reset()

	local buf, buf_size = self.chunk_buf, self.chunk_buf_size
	local chunk_gen = self.chunk_gen

	for czr = 0, 31 do
		for cxr = 0, 31 do
			local chunk = chunk_gen:gen(cxr + rx * 32, czr + rz * 32)
			local tag_size = chunk:write(buf, buf_size)

			local raw_chunk = RawChunk()
			raw_chunk:compressRaw(buf, tag_size)

			region:addRawChunk(cxr, czr, raw_chunk)
		end
	end

	region:write()
end

return RegionGen
