--!strict

local Environment = {}

local function parseProps(args: { any }): { [string]: any }
	local props: { [string]: any } = {}
	for i = 1, #args, 2 do
		local key = args[i]
		local keyName: string? = nil
		if type(key) == "string" then
			if key:sub(1, 1) == ":" then
				keyName = key:sub(2)
			end
		elseif type(key) == "table" and (key :: any).type == "symbol" then
			local symName = (key :: any).name
			if symName:sub(1, 1) == ":" then
				keyName = symName:sub(2)
			end
		end
		if keyName and i + 1 <= #args then
			props[keyName] = args[i + 1]
		end
	end
	return props
end

function Environment.create(): { [string]: any }
	local env: { [string]: any } = {}
	env.__macros__ = {}

	env["+"] = function(...: number): number
		local result = 0
		for _, v in ipairs({...}) do result = result + v end
		return result
	end
	env["-"] = function(a: number, b: number): number return a - b end
	env["*"] = function(...: number): number
		local result = 1
		for _, v in ipairs({...}) do result = result * v end
		return result
	end
	env["/"] = function(a: number, b: number): number return a / b end
	env["%"] = function(a: number, b: number): number return a % b end
	env["^"] = function(a: number, b: number): number return a ^ b end
	env["="] = function(a: any, b: any): boolean return a == b end
	env["<"] = function(a: any, b: any): boolean return a < b end
	env[">"] = function(a: any, b: any): boolean return a > b end
	env["<="] = function(a: any, b: any): boolean return a <= b end
	env[">="] = function(a: any, b: any): boolean return a >= b end
	env["~="] = function(a: any, b: any): boolean return a ~= b end

	env["print"] = function(...: any): () print(...) end
	env["warn"] = function(...: any): () warn(...) end

	env["vector3"] = function(x: number, y: number, z: number): Vector3 return Vector3.new(x, y, z) end
	env["vector2"] = function(x: number, y: number): Vector2 return Vector2.new(x, y) end
	env["cframe"] = function(x: number, y: number, z: number): CFrame return CFrame.new(x, y, z) end
	env["color3"] = function(r: number, g: number, b: number): Color3 return Color3.fromRGB(r, g, b) end

	env["vector3+"] = function(a: Vector3, b: Vector3): Vector3 return a + b end
	env["vector3-"] = function(a: Vector3, b: Vector3): Vector3 return a - b end
	env["vector3*"] = function(v: Vector3, s: number): Vector3 return v * s end
	env["vector3/"] = function(v: Vector3, s: number): Vector3 return v / s end
	env["vector3-dot"] = function(a: Vector3, b: Vector3): number return a:Dot(b) end
	env["vector3-cross"] = function(a: Vector3, b: Vector3): Vector3 return a:Cross(b) end
	env["vector3-length"] = function(v: Vector3): number return v.Magnitude end
	env["vector3-unit"] = function(v: Vector3): Vector3 return v.Unit end
	env["vector3-lerp"] = function(a: Vector3, b: Vector3, t: number): Vector3 return a:Lerp(b, t) end

	env["cframe*"] = function(a: CFrame, b: CFrame): CFrame return a * b end
	env["cframe-lookAt"] = function(from: Vector3, to: Vector3): CFrame return CFrame.lookAt(from, to) end
	env["cframe-angles"] = function(rx: number, ry: number, rz: number): CFrame return CFrame.Angles(rx, ry, rz) end

	env["wait"] = function(t: number): () task.wait(t) end
	env["spawn"] = function(fn: any): () task.spawn(fn) end

	env["apply"] = function(fn: any, ...: any): any
		local args = {...}
		if #args > 0 and type(args[#args]) == "table" then
			local last = table.remove(args)
			for _, v in last do table.insert(args, v) end
		end
		return fn(table.unpack(args))
	end

	env["append"] = function(...: { any }): { any }
		local result = {}
		for _, lst in ipairs({...}) do
			if type(lst) == "table" then
				for _, v in ipairs(lst) do table.insert(result, v) end
			end
		end
		return result
	end

	env["nth"] = function(lst: { any }, n: number): any
		if type(lst) == "table" and lst[n] ~= nil then
			return lst[n]
		end
		return nil
	end

	env["list?"] = function(val: any): boolean
		if type(val) == "table" then
			local rawType = rawget(val, "type")
			if rawType == "list" then return true end
			if #val > 0 and rawget(val, 1) ~= nil then return true end
			if rawget(val, "car") ~= nil or rawget(val, "cdr") ~= nil then return true end
		end
		return false
	end

	env["cons"] = function(car: any, cdr: any): any
		if cdr == nil then
			return {car}
		elseif type(cdr) == "table" and #cdr > 0 then
			local result = {car}
			for _, v in ipairs(cdr) do table.insert(result, v) end
			return result
		else
			return {car = car, cdr = cdr}
		end
	end
	env["car"] = function(lst: any): any
		if lst == nil then return nil end
		if type(lst) == "table" then
			if #lst > 0 then return lst[1] end
			if rawget(lst, "car") ~= nil then return rawget(lst, "car") end
		end
		return nil
	end
	env["cdr"] = function(lst: any): any
		if lst == nil then return nil end
		if type(lst) == "table" then
			if #lst > 1 then
				local result = {}
				for i = 2, #lst do table.insert(result, lst[i]) end
				return result
			elseif #lst == 1 then
				return {}
			elseif rawget(lst, "cdr") ~= nil then
				return rawget(lst, "cdr")
			end
		end
		return nil
	end
	env["list"] = function(...: any): { any } return {...} end
	env["null?"] = function(lst: any): boolean
		if lst == nil then return true end
		if type(lst) == "table" then
			local rawType = rawget(lst, "type")
			if rawType == "nil" then return true end
			if #lst == 0 and rawget(lst, "car") == nil and rawget(lst, "cdr") == nil then return true end
		end
		return false
	end

	env["gensym"] = function(): string
		return "G__" .. tostring(math.random(1000000))
	end

	env["string-append"] = function(...: string): string
		return table.concat({...})
	end
	env["string-length"] = function(s: string): number
		return #s
	end
	env["string-ref"] = function(s: string, i: number): string
		return s:sub(i, i)
	end
	env["substring"] = function(s: string, start: number, finish: number?): string
		return s:sub(start, finish or #s)
	end
	env["string-upcase"] = function(s: string): string
		return s:upper()
	end
	env["string-downcase"] = function(s: string): string
		return s:lower()
	end
	env["string-split"] = function(s: string, sep: string): { string }
		local result = {}
		for part in s:gmatch("[^" .. sep .. "]+") do table.insert(result, part) end
		return result
	end
	env["string-trim"] = function(s: string): string
		return s:match("^%s*(.-)%s*$") or s
	end

	env["sort"] = function(lst: { any }, cmp: any?): { any }
		local copy = {}
		for _, v in lst do table.insert(copy, v) end
		if cmp then
			table.sort(copy, function(a: any, b: any): boolean return cmp(a, b) end)
		else
			table.sort(copy)
		end
		return copy
	end
	env["filter"] = function(fn: any, lst: { any }): { any }
		local result = {}
		for _, v in lst do
			if fn(v) then table.insert(result, v) end
		end
		return result
	end
	env["reduce"] = function(fn: any, init: any, lst: { any }): any
		local acc = init
		for _, v in lst do acc = fn(acc, v) end
		return acc
	end
	env["map"] = function(fn: any, lst: { any }): { any }
		local result = {}
		for _, v in lst do table.insert(result, fn(v)) end
		return result
	end
	env["range"] = function(start: number, stop: number, step: number?): { number }
		step = step or 1
		local result = {}
		if step > 0 then
			for i = start, stop, step do table.insert(result, i) end
		else
			for i = start, stop, step do table.insert(result, i) end
		end
		return result
	end
	env["zip"] = function(...: { any }): { { any } }
		local lists = {...}
		local result = {}
		local minLen = math.huge
		for _, lst in lists do if #lst < minLen then minLen = #lst end end
		for i = 1, minLen do
			local tuple = {}
			for _, lst in lists do table.insert(tuple, lst[i]) end
			table.insert(result, tuple)
		end
		return result
	end

	env["curry"] = function(fn: any, ...: any): any
		local fixed = {...}
		return function(...: any): any
			local args = {}
			for _, v in fixed do table.insert(args, v) end
			for _, v in {...} do table.insert(args, v) end
			return fn(table.unpack(args))
		end
	end
	env["compose"] = function(...: any): any
		local fns = {...}
		return function(x: any): any
			local result = x
			for i = #fns, 1, -1 do result = fns[i](result) end
			return result
		end
	end
	env["printf"] = function(fmt: string, ...: any): ()
		print(string.format(fmt, ...))
	end
	env["time"] = function(fn: any): number
		local start = os.clock()
		fn()
		return os.clock() - start
	end
	env["assert"] = function(condition: any, msg: string?): any
		if not condition then error(msg or "assertion failed") end
		return condition
	end
	env["memoize"] = function(fn: any): any
		local cache: { [string]: any } = {}
		return function(...: any): any
			local key = table.concat({...}, "\0")
			if cache[key] == nil then cache[key] = fn(...) end
			return cache[key]
		end
	end

	env["raycast"] = function(origin: Vector3, direction: Vector3, params: RaycastParams?): RaycastResult?
		local raycastParams = params or RaycastParams.new()
		return workspace:Raycast(origin, direction, raycastParams)
	end
	env["disconnect"] = function(connection: any): ()
		connection:Disconnect()
	end
	env["get-prop"] = function(obj: any, propName: string): any
		return obj[propName]
	end
	env["tostring"] = function(val: any): string
		return tostring(val)
	end

	env["data-store"] = function(name: string): any
		local useMock = true
		local runService = game:GetService("RunService")
		if not runService:IsStudio() then
			local success, ds = pcall(function() return game:GetService("DataStoreService"):GetDataStore(name) end)
			if success then useMock = false end
		end
		if useMock then
			local mockData: { [string]: any } = {}
			return {
				SetAsync = function(_: any, key: string, value: any): boolean mockData[key] = value; return true end,
				GetAsync = function(_: any, key: string): any return mockData[key] end,
				UpdateAsync = function(_: any, key: string, callback: any): boolean mockData[key] = callback(mockData[key]); return true end,
				RemoveAsync = function(_: any, key: string): boolean mockData[key] = nil; return true end
			}
		else return ds end
	end
	env["data-set!"] = function(ds: any, key: string, value: any): any
		local success, err = pcall(function() ds:SetAsync(key, value) end)
		if not success then error("DataStore set failed: " .. tostring(err)) end
		return value
	end
	env["data-get"] = function(ds: any, key: string): any
		local success, result = pcall(function() return ds:GetAsync(key) end)
		if not success then error("DataStore get failed: " .. tostring(result)) end
		return result
	end
	env["data-update!"] = function(ds: any, key: string, fn: any): boolean
		local success, err = pcall(function() ds:UpdateAsync(key, function(old: any): any return fn(old) end) end)
		if not success then error("DataStore update failed: " .. tostring(err)) end
		return true
	end
	env["data-remove!"] = function(ds: any, key: string): boolean
		local success, err = pcall(function() ds:RemoveAsync(key) end)
		if not success then error("DataStore remove failed: " .. tostring(err)) end
		return true
	end

	env["http-get"] = function(url: string): string
		local hs = game:GetService("HttpService")
		local success, result = pcall(function() return hs:GetAsync(url) end)
		if not success then error("HTTP GET failed: " .. tostring(result)) end
		return result
	end
	env["http-post"] = function(url: string, body: string): string
		local hs = game:GetService("HttpService")
		local success, result = pcall(function() return hs:PostAsync(url, body) end)
		if not success then error("HTTP POST failed: " .. tostring(result)) end
		return result
	end
	env["http-get-async"] = function(url: string, callback: any): boolean
		local hs = game:GetService("HttpService")
		task.spawn(function()
			local success, result = pcall(function() return hs:GetAsync(url) end)
			if success then callback(result)
			else warn("HTTP GET failed: " .. tostring(result)) end
		end)
		return true
	end

	env["udim2"] = function(xScale: number, xOffset: number, yScale: number, yOffset: number): UDim2
		return UDim2.new(xScale, xOffset, yScale, yOffset)
	end
	env["udim"] = function(scale: number, offset: number): UDim
		return UDim.new(scale, offset)
	end
	env["rect"] = function(x0: number, y0: number, x1: number, y1: number): Rect
		return Rect.new(x0, y0, x1, y1)
	end
	env["font"] = function(name: string): Enum.Font
		return Enum.Font[name] or Enum.Font.SourceSans
	end

	env["play-sound"] = function(soundId: string, ...: any): Sound
		local props = parseProps({...})
		local sound = Instance.new("Sound")
		sound.SoundId = soundId
		sound.Volume = props.Volume or 0.5
		sound.Looped = props.Looped or false
		sound.Parent = props.Parent or workspace
		sound:Play()
		return sound
	end
	env["stop-sound"] = function(sound: Sound): () sound:Stop() end
	env["sound"] = function(soundId: string, ...: any): Sound
		local props = parseProps({...})
		local sound = Instance.new("Sound")
		sound.SoundId = soundId
		sound.Volume = props.Volume or 0.5
		sound.Looped = props.Looped or false
		sound.Parent = props.Parent or workspace
		return sound
	end

	env["animator"] = function(humanoid: Humanoid): Animator
		return humanoid:WaitForChild("Animator") :: Animator
	end
	env["load-animation"] = function(animator: Animator, animationId: string): AnimationTrack
		local animation = Instance.new("Animation")
		animation.AnimationId = animationId
		return animator:LoadAnimation(animation)
	end
	env["play-animation"] = function(track: AnimationTrack): AnimationTrack
		track:Play()
		return track
	end
	env["stop-animation"] = function(track: AnimationTrack): AnimationTrack
		track:Stop()
		return track
	end

	env["body-velocity"] = function(parent: Instance, ...: any): BodyVelocity
		local props = parseProps({...})
		local bv = Instance.new("BodyVelocity")
		bv.Velocity = props.Velocity or Vector3.new(0, 0, 0)
		bv.MaxForce = props.MaxForce or Vector3.new(4000, 4000, 4000)
		bv.Parent = parent
		return bv
	end
	env["body-force"] = function(parent: Instance, ...: any): BodyForce
		local props = parseProps({...})
		local bf = Instance.new("BodyForce")
		bf.Force = props.Force or Vector3.new(0, 0, 0)
		bf.Parent = parent
		return bf
	end
	env["body-position"] = function(parent: Instance, ...: any): BodyPosition
		local props = parseProps({...})
		local bp = Instance.new("BodyPosition")
		bp.Position = props.Position or Vector3.new(0, 0, 0)
		bp.MaxForce = props.MaxForce or Vector3.new(4000, 4000, 4000)
		bp.Parent = parent
		return bp
	end
	env["body-gyro"] = function(parent: Instance, ...: any): BodyGyro
		local props = parseProps({...})
		local bg = Instance.new("BodyGyro")
		bg.MaxTorque = props.MaxTorque or Vector3.new(4000, 4000, 4000)
		bg.Parent = parent
		return bg
	end

	setmetatable(env, {
		__index = function(t: { [string]: any }, k: string): any
			if rawget(t, k) ~= nil then return rawget(t, k) end
			if _G[k] ~= nil then return _G[k] end
			if _G.game and (_G.game :: any)[k] ~= nil then return (_G.game :: any)[k] end
			return nil
		end
	})

	return env
end

return Environment
