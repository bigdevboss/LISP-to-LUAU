--!strict

local Reader = require(script.Parent.Reader)
local CEKMachine = require(script.Parent.CEKMachine)
local Environment = require(script.Parent.Environment)

local Runtime = {}
Runtime.env = Environment.create()

Runtime.env["game"] = game
Runtime.env["workspace"] = workspace

Runtime.env["spawn"] = function(fn: any): ()
	if type(fn) == "table" and (fn :: any).type == "function" then
		local lispFn = fn :: any
		task.spawn(function()
			local localEnv = {}
			setmetatable(localEnv, {__index = lispFn.closure})
			for _, expr in lispFn.body do
				CEKMachine.evaluate(expr, localEnv)
			end
		end)
	else
		task.spawn(fn)
	end
end

local IGNORED_KEYS = {
	closure = true,
	__macros__ = true,
	type = true,
	argsInfo = true,
	body = true,
	literals = true,
	rules = true,
	isMacro = true,
}

local function toLispString(val: any, depth: number?, visited: any?): string
	depth = depth or 0
	if depth > 100 then return "..." end
	visited = visited or {}
	if val == nil then return "nil"
	elseif type(val) == "table" then
		if visited[val] then return "#<circular>" end
		visited[val] = true
		local rawType = rawget(val, "type")
		if rawType == "function" then return "#<function>"
		elseif rawType == "syntax-rules" then return "#<syntax-rules>"
		elseif rawType == "continuation" then return "#<continuation>"
		elseif rawget(val, "car") ~= nil and rawget(val, "cdr") ~= nil then
			return "(" .. toLispString(rawget(val, "car"), depth + 1, visited) .. " . " .. toLispString(rawget(val, "cdr"), depth + 1, visited) .. ")"
		else
			local items = {}
			local len = #val
			for i = 1, len do
				local v = rawget(val, i)
				if v ~= nil and not IGNORED_KEYS[i] then
					table.insert(items, toLispString(v, depth + 1, visited))
				end
			end
			return "(" .. table.concat(items, " ") .. ")"
		end
	else
		return tostring(val)
	end
end

function Runtime.execute(lispCode: string): (string?, string?)
	local ast = Reader.parse(lispCode)
	if #ast == 0 then return nil end

	local results = {}
	for _, expr in ipairs(ast) do
		local success, result = pcall(CEKMachine.evaluate, expr, Runtime.env)
		if not success then
			local errMsg = "RUNTIME ERROR: " .. tostring(result)
			print(errMsg)
			return nil, errMsg
		end
		table.insert(results, result)
	end

	local output: string
	if #results == 1 then
		output = toLispString(results[1], 0, {})
	else
		local parts = {}
		for _, r in results do
			table.insert(parts, toLispString(r, 0, {}))
		end
		output = table.concat(parts, "\n")
	end
	print(output)
	return output, nil
end

function Runtime.resetEnv(): ()
	Runtime.env = Environment.create()
	Runtime.env["game"] = game
	Runtime.env["workspace"] = workspace
	Runtime.env["spawn"] = Runtime.env["spawn"]
end

return Runtime
