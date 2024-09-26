local class = require("class")

---@class world.RegionTaskPool
---@operator call: world.RegionTaskPool
---@field threads thread[]
---@field tasks table[]
local RegionTaskPool = class()

---@param thread_count integer
function RegionTaskPool:new(thread_count)
	self.thread_count = thread_count
	self.threads = {}
	self.tasks = {}
	self.complete = true
end

---@param handle_task function
function RegionTaskPool:setTaskHandler(handle_task)
	self.handle_task = handle_task
end

---@param on_complete function
function RegionTaskPool:onCopmlete(on_complete)
	self.on_complete = on_complete
end

function RegionTaskPool:checkComplete()
	if self.complete or next(self.threads) then
		return
	end
	self.complete = true
	if self.on_complete then
		self.on_complete()
	end
end

function RegionTaskPool:stop()
	self.tasks = {}
end

function RegionTaskPool:getNextTask()
	local tasks = self.tasks
	if #tasks == 0 then
		return
	end
	local file = tasks[#tasks]
	tasks[#tasks] = nil
	return file
end

---@param task table
function RegionTaskPool:addTask(task)
	table.insert(self.tasks, task)
end

function RegionTaskPool:run()
	self.complete = false

	local threads = self.threads
	for i = 1, self.thread_count do
		if not threads[i] then
			threads[i] = coroutine.create(function()
				local task = self:getNextTask()
				while task do
					self.handle_task(task)
					task = self:getNextTask()
				end
				threads[i] = nil
				self:checkComplete()
			end)
			coroutine.resume(threads[i])
		end
	end
end

return RegionTaskPool
