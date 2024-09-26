local class = require("class")
local RegionTaskPool = require("world.RegionTaskPool")

---@class world.ThreadedRegionGen
---@operator call: world.ThreadedRegionGen
local ThreadedRegionGen = class()

---@param threads_count integer
---@param gen_region_async function
function ThreadedRegionGen:new(threads_count, gen_region_async)
	self.threads_count = threads_count
	self.gen_region_async = gen_region_async
end

---@param rx_0 integer
---@param rz_0 integer
---@param rx_1 integer
---@param rz_1 integer
function ThreadedRegionGen:generateThreaded(rx_0, rz_0, rx_1, rz_1)
	local function task_handler(task)
		local rx, rz = task[1], task[2]
		self.gen_region_async(rx, rz)
	end

	local task_pool = RegionTaskPool(self.threads_count)
	task_pool:setTaskHandler(task_handler)
	task_pool:onCopmlete(os.exit)

	for rz = rz_0, rz_1 do
		for rx = rx_0, rx_1 do
			task_pool:addTask({rx, rz})
		end
	end

	task_pool:run()
end

return ThreadedRegionGen
