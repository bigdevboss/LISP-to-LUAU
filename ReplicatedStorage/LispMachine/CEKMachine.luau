--!strict

local CEKMachine = {}

local function tableClone(tbl: {any}): {any}
	local result = {}
	for k, v in pairs(tbl) do
		result[k] = v
	end
	return result
end

local function parseLambdaArgs(argsAst: any): any
	local required: { string } = {}
	local optional: { any } = {}
	local key: { any } = {}
	local vararg = false
	local varargName: string? = nil

	if argsAst.type == "symbol" then
		vararg = true
		varargName = argsAst.name
		return { required = required, optional = optional, key = key, vararg = vararg, varargName = varargName }
	end

	local elements: { any } = argsAst.elements
	local i = 1
	local mode = "required"

	while i <= #elements do
		local elem = elements[i]
		if elem.type == "symbol" then
			local name: string = elem.name
			if name == "&optional" then
				mode = "optional"
				i = i + 1
			elseif name == "&key" then
				mode = "key"
				i = i + 1
			elseif name == "&rest" then
				vararg = true
				i = i + 1
				if i <= #elements and elements[i].type == "symbol" then
					varargName = elements[i].name
					i = i + 1
				end
			else
				if mode == "required" then
					table.insert(required, name)
					i = i + 1
				elseif mode == "optional" then
					if i + 1 <= #elements and elements[i + 1].type ~= "symbol" then
						table.insert(optional, { name = name, default = elements[i + 1] })
						i = i + 2
					else
						table.insert(optional, { name = name, default = { type = "nil" } })
						i = i + 1
					end
				elseif mode == "key" then
					if i + 1 <= #elements and elements[i + 1].type ~= "symbol" then
						table.insert(key, { name = name, default = elements[i + 1] })
						i = i + 2
					else
						table.insert(key, { name = name, default = { type = "nil" } })
						i = i + 1
					end
				end
			end
		else
			i = i + 1
		end
	end

	return { required = required, optional = optional, key = key, vararg = vararg, varargName = varargName }
end

local function bindLambdaArgs(argsInfo: any, args: { any }, localEnv: { [string]: any }): ()
	local argIndex = 1

	for _, name in ipairs(argsInfo.required) do
		if argIndex <= #args then
			localEnv[name] = args[argIndex]
			argIndex = argIndex + 1
		else
			error("Missing required argument: " .. name)
		end
	end

	for _, opt in ipairs(argsInfo.optional) do
		if argIndex <= #args then
			localEnv[opt.name] = args[argIndex]
			argIndex = argIndex + 1
		else
			localEnv[opt.name] = CEKMachine.evaluate(opt.default, localEnv)
		end
	end

	if argsInfo.vararg then
		local rest: { any } = {}
		while argIndex <= #args do
			table.insert(rest, args[argIndex])
			argIndex = argIndex + 1
		end
		localEnv[argsInfo.varargName :: string] = rest
	else
		for _, kw in ipairs(argsInfo.key) do
			localEnv[kw.name] = nil
		end

		for _, kw in ipairs(argsInfo.key) do
			local found = false
			local keyIdx = 1
			while keyIdx < #args do
				local keySym = args[keyIdx]
				if type(keySym) == "string" and keySym:sub(1, 1) == ":" and keySym:sub(2) == kw.name then
					localEnv[kw.name] = args[keyIdx + 1]
					found = true
					break
				end
				keyIdx = keyIdx + 2
			end
			if not found then
				localEnv[kw.name] = CEKMachine.evaluate(kw.default, localEnv)
			end
		end
	end
end

local function expandSyntaxRules(macro: any, elements: { any }, env: { [string]: any }): any
	local macroName = elements[1].name
	local macroArgs = {}
	for i = 2, #elements do table.insert(macroArgs, elements[i]) end

	local builtins = {
		"define", "lambda", "if", "begin", "quote", "set!", "let", "let*", "letrec",
		"named-let", "cond", "case", "try", "and", "or", "for", "while", "when", "unless",
		"struct", "tween", "once", "on-touched", "syntax-rules", "defmacro",
		"quasiquote", "eval", "apply", "cons", "car", "cdr", "list", "instance", "service", "connect",
		"call/cc", "print", "warn", "+", "-", "*", "/", "%", "^", "=", "<", ">", "<=", ">=", "~=",
		"raycast", "play-sound", "body-velocity"
	}

	for _, rule in ipairs(macro.rules) do
		local pattern = rule.pattern
		local template = rule.template
		if pattern.type == "list" and #pattern.elements > 0 then
			local patFirst = pattern.elements[1]
			if patFirst.type == "symbol" and patFirst.name == macroName then
				local bindings = {}
				local argIdx = 1
				local matchSuccess = true

				local function matchPattern(pat, args, isFirst)
					if pat.type == "symbol" then
						local name = pat.name
						local isLiteral = false
						if isFirst then isLiteral = true
						else
							for _, lit in ipairs(macro.literals) do
								if lit == name then isLiteral = true break end
							end
						end
						if isLiteral then
							if argIdx <= #args then
								local arg = args[argIdx]
								argIdx = argIdx + 1
								return (arg.type == "symbol" and arg.name == name)
							end
							return false
						end
						if name == "..." then
							local rest = {}
							while argIdx <= #args do
								table.insert(rest, args[argIdx])
								argIdx = argIdx + 1
							end
							bindings["..."] = rest
							return true
						end
						if argIdx <= #args then
							bindings[name] = args[argIdx]
							argIdx = argIdx + 1
							return true
						end
						return false
					elseif pat.type == "list" then
						if argIdx > #args then return false end
						local arg = args[argIdx]
						argIdx = argIdx + 1
						if arg.type ~= "list" then return false end
						local subArgs = arg.elements
						local savedBindings = {}
						for kk, vv in pairs(bindings) do savedBindings[kk] = vv end
						local subIdx = 1
						local savedArgIdx = argIdx
						argIdx = 1
						for _, subPat in ipairs(pat.elements) do
							if subPat.type == "symbol" and subPat.name == "..." then
								local rest = {}
								while subIdx <= #subArgs do
									table.insert(rest, subArgs[subIdx])
									subIdx = subIdx + 1
								end
								if #pat.elements >= 2 then
									local varName = pat.elements[2].name
									bindings[varName] = rest
								end
								return true
							end
							if subIdx > #subArgs then
								for kk in pairs(bindings) do bindings[kk] = nil end
								for kk, vv in pairs(savedBindings) do bindings[kk] = vv end
								return false
							end
							if not matchPattern(subPat, { subArgs[subIdx] }, false) then
								for kk in pairs(bindings) do bindings[kk] = nil end
								for kk, vv in pairs(savedBindings) do bindings[kk] = vv end
								return false
							end
							subIdx = subIdx + 1
						end
						argIdx = savedArgIdx
						return true
					else
						if argIdx <= #args then
							local arg = args[argIdx]
							argIdx = argIdx + 1
							return arg.type == pat.type and arg.value == pat.value
						end
						return false
					end
				end

				for i = 2, #pattern.elements do
					if not matchPattern(pattern.elements[i], macroArgs, (i == 2)) then
						matchSuccess = false
						break
					end
				end

				if matchSuccess then
					local gensymCounter = 0
					local gensymMap = {}

					local function gensym(prefix)
						gensymCounter = gensymCounter + 1
						return prefix .. "_" .. tostring(gensymCounter)
					end

					local function isBuiltin(name)
						for _, b in ipairs(builtins) do if b == name then return true end end
						return false
					end

					local function rename(node)
						if node.type == "symbol" then
							local name = node.name
							if bindings[name] then return bindings[name] end
							for _, lit in ipairs(macro.literals) do if lit == name then return { type = "symbol", name = name } end end
							if isBuiltin(name) then return { type = "symbol", name = name } end
							if not gensymMap[name] then gensymMap[name] = gensym(name) end
							return { type = "symbol", name = gensymMap[name] }
						elseif node.type == "list" then
							local newElements = {}
							for _, elem in ipairs(node.elements) do
								if elem.type == "symbol" and elem.name == "..." then
									local restBind = bindings["..."]
									if restBind then
										for _, restElem in ipairs(restBind) do table.insert(newElements, restElem) end
									end
								else
									table.insert(newElements, rename(elem))
								end
							end
							return { type = "list", elements = newElements }
						else
							return node
						end
					end

					local expanded = rename(template)
					return expanded
				end
			end
		end
	end
	error("syntax-rules: no matching pattern")
end

function CEKMachine.evaluate(ast: any, globalEnv: { [string]: any }): any
	local control: any = ast
	local env: { [string]: any } = globalEnv
	local val: any = nil
	local kStack: { any } = {}

	while control ~= nil or #kStack > 0 do
		if control ~= nil then
			if type(control) == "table" and control.type == "value" then
				val = control.value
				control = nil
			else
				local node = control
				control = nil

				if node.type == "number" or node.type == "string" or node.type == "boolean" or node.type == "nil" then
					val = node.value
				elseif node.type == "symbol" then
					local name: string = node.name
					if name:sub(1, 1) == ":" then
						val = name
					else
						local current: any = env
						local found: any = nil
						while current do
							found = rawget(current, name)
							if found ~= nil then break end
							local mt = getmetatable(current)
							if mt and mt.__index then
								if type(mt.__index) == "table" then
									current = mt.__index
								elseif type(mt.__index) == "function" then
									found = mt.__index(current, name)
									break
								else
									break
								end
							else
								break
							end
						end
						if found == nil then
							if _G[name] ~= nil then
								found = _G[name]
							elseif _G.game and (_G.game :: any)[name] ~= nil then
								found = (_G.game :: any)[name]
							else
								error("Undefined symbol: " .. name)
							end
						end
						val = found
					end
				elseif node.type == "list" then
					local elements: { any } = node.elements
					if #elements == 0 then
						val = nil
					else
						local first = elements[1]

						if first.type == "symbol" then
							local formName: string = first.name

							if formName == "call/cc" then
								local stackSnapshot = {}
								for _, frame in ipairs(kStack) do
									local frameCopy = {
										type = frame.type,
										env = frame.env,
										pending = frame.pending and tableClone(frame.pending) or nil,
										ready = frame.ready and tableClone(frame.ready) or nil,
										varName = frame.varName,
										thenBranch = frame.thenBranch,
										elseBranch = frame.elseBranch,
										bindings = frame.bindings,
										index = frame.index,
										body = frame.body,
									}
									table.insert(stackSnapshot, frameCopy)
								end
								local continuationObject = {
									type = "continuation",
									stack = stackSnapshot,
								}
								table.insert(kStack, {
									type = "callcc",
									env = env,
									cont = continuationObject
								})
								control = elements[2]

							elseif formName == "define" then
								local varName = elements[2].name
								table.insert(kStack, { type = "define-var", env = env, varName = varName })
								control = elements[3]

							elseif formName == "lambda" then
								local argsAst = elements[2]
								local body: { any } = {}
								for i = 3, #elements do table.insert(body, elements[i]) end
								local func = {
									type = "function",
									argsInfo = parseLambdaArgs(argsAst),
									body = body,
									closure = env
								}
								val = func

							elseif formName == "if" then
								table.insert(kStack, {
									type = "if-branch",
									env = env,
									thenBranch = elements[3],
									elseBranch = elements[4]
								})
								control = elements[2]

							elseif formName == "begin" then
								for i = #elements, 2, -1 do
									if i == #elements then
										control = elements[i]
									else
										table.insert(kStack, { type = "begin-seq", env = env })
										control = elements[i]
									end
								end

							elseif formName == "quote" then
								val = elements[2]

							elseif formName == "set!" then
								local varName = elements[2].name
								table.insert(kStack, { type = "set-var", env = env, varName = varName })
								control = elements[3]

							elseif formName == "let" then
								if #elements < 3 then
									error("Malformed let expression")
								end
								local second = elements[2]
								if second.type == "symbol" then
									-- Именованный let: (let loop ((vars) ...) body)
									local loopName = second.name
									local bindingsNode = elements[3]
									if not bindingsNode or bindingsNode.type ~= "list" then
										error("Malformed named-let bindings")
									end
									local bindingsList = bindingsNode.elements or {}
									local body: { any } = {}
									for i = 4, #elements do table.insert(body, elements[i]) end

									local argsSymbols = {}
									local initExprs = {}
									for _, binding in ipairs(bindingsList) do
										if binding.type == "list" and binding.elements and #binding.elements == 2 then
											table.insert(argsSymbols, binding.elements[1])
											table.insert(initExprs, binding.elements[2])
										end
									end

									-- Трансформация в: ((lambda (loop) (set! loop (lambda (xs) body)) (loop lst)) #f)
									local lambdaBody = {
										type = "list",
										elements = {
											{ type = "symbol", name = "begin" },
											{
												type = "list",
												elements = {
													{ type = "symbol", name = "set!" },
													{ type = "symbol", name = loopName },
													{
														type = "list",
														elements = {
															{ type = "symbol", name = "lambda" },
															{ type = "list", elements = argsSymbols },
															table.unpack(body)
														}
													}
												}
											},
											{
												type = "list",
												elements = {
													{ type = "symbol", name = loopName },
													table.unpack(initExprs)
												}
											}
										}
									}

									local transformedAst = {
										type = "list",
										elements = {
											{
												type = "list",
												elements = {
													{ type = "symbol", name = "lambda" },
													{ type = "list", elements = { { type = "symbol", name = loopName } } },
													lambdaBody
												}
											},
											{ type = "boolean", value = false }
										}
									}

									control = transformedAst
								else
									-- Обычный let: (let ((vars) ...) body)
									local bindingsList = elements[2].elements
									local body: { any } = {}
									for i = 3, #elements do table.insert(body, elements[i]) end
									local newEnv: { [string]: any } = {}
									setmetatable(newEnv, { __index = env })
									if #bindingsList > 0 then
										local binding = bindingsList[1]
										if binding.type == "list" and #binding.elements == 2 then
											table.insert(kStack, {
												type = "let-bind",
												env = newEnv,
												varName = binding.elements[1].name,
												bindings = bindingsList,
												index = 1,
												body = body
											})
											control = binding.elements[2]
										end
									else
										if #body > 0 then
											control = body[1]
											env = newEnv
										else
											val = nil
										end
									end
								end

							elseif formName == "cond" then
								local function buildIf(clauses: { any }): any
									if #clauses == 0 then
										return { type = "nil" }
									end
									local clause = clauses[1]
									if clause.type == "list" and #clause.elements >= 1 then
										local test = clause.elements[1]
										if test.type == "symbol" and test.name == "else" then
											if #clause.elements > 1 then
												return clause.elements[2]
											else
												return { type = "nil" }
											end
										else
											local thenExpr = nil
											if #clause.elements > 1 then
												thenExpr = clause.elements[2]
											else
												thenExpr = { type = "nil" }
											end
											local elsePart = buildIf({ table.unpack(clauses, 2) })
											return {
												type = "list",
												elements = {
													{ type = "symbol", name = "if" },
													test,
													thenExpr,
													elsePart
												}
											}
										end
									end
									return { type = "nil" }
								end
								local ifExpr = buildIf({ table.unpack(elements, 2) })
								control = ifExpr

							elseif formName == "case" then
								local key = elements[2]
								local clauses = { table.unpack(elements, 3) }
								local function buildIf(): any
									if #clauses == 0 then return { type = "nil" } end
									local clause = clauses[1]
									if clause.type == "list" and #clause.elements >= 1 then
										local pattern = clause.elements[1]
										if pattern.type == "symbol" and pattern.name == "else" then
											if #clause.elements > 1 then return clause.elements[2] end
											return { type = "nil" }
										else
											local thenExpr = nil
											if #clause.elements > 1 then thenExpr = clause.elements[2] end
											local rest = { table.unpack(clauses, 2) }
											local elsePart = buildIf()
											if pattern.type == "list" then
												local condExpr = { type = "list", elements = { { type = "symbol", name = "=" }, key, { type = "quote", elements = nil, value = pattern } } }
												return { type = "list", elements = { { type = "symbol", name = "if" }, condExpr, thenExpr or { type = "nil" }, elsePart } }
											else
												local condExpr = { type = "list", elements = { { type = "symbol", name = "=" }, key, pattern } }
												return { type = "list", elements = { { type = "symbol", name = "if" }, condExpr, thenExpr or { type = "nil" }, elsePart } }
											end
										end
									end
									return { type = "nil" }
								end
								local ifExpr = buildIf()
								control = ifExpr

							elseif formName == "for" then
								local init, cond, step, body
								if #elements == 3 and elements[2].type == "list" then
									local controlList = elements[2].elements
									init = controlList[1]
									cond = controlList[2]
									step = controlList[3]
									body = elements[3]
								else
									init = elements[2]
									cond = elements[3]
									step = elements[4]
									body = elements[5]
								end
								table.insert(kStack, {
									type = "for-loop",
									env = env,
									init = init,
									cond = cond,
									step = step,
									body = body
								})
								control = init

							elseif formName == "while" then
								local cond = elements[2]
								local body = elements[3]
								table.insert(kStack, {
									type = "while-loop",
									env = env,
									cond = cond,
									body = body
								})
								control = cond

							elseif formName == "when" then
								local cond = elements[2]
								local body = { type = "begin", elements = { table.unpack(elements, 3) } }
								if #elements == 3 then body = elements[3] end
								local newIf = {
									type = "list",
									elements = {
										{ type = "symbol", name = "if" },
										cond,
										body,
										{ type = "nil" }
									}
								}
								control = newIf

							elseif formName == "unless" then
								local cond = elements[2]
								local body = { type = "begin", elements = { table.unpack(elements, 3) } }
								if #elements == 3 then body = elements[3] end
								local newIf = {
									type = "list",
									elements = {
										{ type = "symbol", name = "if" },
										cond,
										{ type = "nil" },
										body
									}
								}
								control = newIf

							elseif formName == "struct" then
								local structName = elements[2].name
								local fieldsAst = elements[3]
								local fields = {}
								if fieldsAst.type == "list" then
									for _, fieldSym in ipairs(fieldsAst.elements) do
										table.insert(fields, fieldSym.name)
									end
								end
								local constructor = function(...)
									local args = { ... }
									local obj = {}
									obj.__struct_type = structName
									for i, field in ipairs(fields) do
										obj[field] = args[i]
									end
									return obj
								end
								env[structName] = constructor
								for _, field in ipairs(fields) do
									env[structName .. "-" .. field] = function(obj)
										return obj[field]
									end
								end
								val = constructor

							elseif formName == "syntax-rules" then
								local literalsList = elements[2].elements
								local literals = {}
								for _, lit in ipairs(literalsList) do table.insert(literals, lit.name) end
								local rules = {}
								for i = 3, #elements do
									local rule = elements[i]
									if rule.type == "list" and #rule.elements == 2 then
										table.insert(rules, { pattern = rule.elements[1], template = rule.elements[2] })
									end
								end
								val = { type = "syntax-rules", rules = rules, literals = literals, closure = env }

							elseif formName == "defmacro" then
								local macroName = elements[2].name
								local argsAst = elements[3]
								local body: { any } = {}
								for i = 4, #elements do table.insert(body, elements[i]) end
								local argsInfo = parseLambdaArgs(argsAst)
								local macroFn = {
									type = "function",
									argsInfo = argsInfo,
									body = body,
									closure = env,
									isMacro = true
								}
								env.__macros__[macroName] = macroFn
								val = macroFn

							elseif formName == "tween" then
								local obj = CEKMachine.evaluate(elements[2], env)
								local props = {}
								local time = 1
								local easing = "Linear"
								local i = 3
								while i <= #elements do
									local key = elements[i]
									if key.type == "symbol" then
										local keyName = key.name
										if keyName == ":time" then
											time = CEKMachine.evaluate(elements[i + 1], env)
											i = i + 2
										elseif keyName == ":easing" then
											easing = elements[i + 1].value
											i = i + 2
										elseif keyName:sub(1, 1) == ":" then
											local propName = keyName:sub(2)
											propName = propName:sub(1, 1):upper() .. propName:sub(2)
											local propVal = CEKMachine.evaluate(elements[i + 1], env)
											props[propName] = propVal
											i = i + 2
										else
											i = i + 1
										end
									elseif type(key) == "string" and key:sub(1, 1) == ":" then
										local keyName = key:sub(2)
										if keyName == "time" then
											time = CEKMachine.evaluate(elements[i + 1], env)
											i = i + 2
										elseif keyName == "easing" then
											easing = elements[i + 1].value
											i = i + 2
										else
											local propName = keyName:sub(1, 1):upper() .. keyName:sub(2)
											local propVal = CEKMachine.evaluate(elements[i + 1], env)
											props[propName] = propVal
											i = i + 2
										end
									else
										i = i + 1
									end
								end
								local tweenService = game:GetService("TweenService")
								local tweenInfo = TweenInfo.new(time, Enum.EasingStyle[easing])
								local goals = {}
								for k, v in pairs(props) do goals[k] = v end
								local tween = tweenService:Create(obj, tweenInfo, goals)
								tween:Play()
								val = tween

							elseif formName == "once" then
								local obj = CEKMachine.evaluate(elements[2], env)
								local eventName = elements[3].value
								local handler = CEKMachine.evaluate(elements[4], env)
								local connection
								if type(handler) == "table" and handler.type == "function" then
									local lispFn = handler
									handler = function(...)
										connection:Disconnect()
										local args = { ... }
										local localEnv = {}
										setmetatable(localEnv, { __index = lispFn.closure })
										bindLambdaArgs(lispFn.argsInfo, args, localEnv)
										for _, expr in ipairs(lispFn.body) do
											CEKMachine.evaluate(expr, localEnv)
										end
									end
								else
									handler = function(...)
										connection:Disconnect()
										handler(...)
									end
								end
								connection = obj[eventName]:Connect(handler)
								val = connection

							elseif formName == "on-touched" then
								local obj = CEKMachine.evaluate(elements[2], env)
								local handler = CEKMachine.evaluate(elements[3], env)
								if type(handler) == "table" and handler.type == "function" then
									local lispFn = handler
									local wrapped = function(...)
										local args = { ... }
										local localEnv = {}
										setmetatable(localEnv, { __index = lispFn.closure })
										bindLambdaArgs(lispFn.argsInfo, args, localEnv)
										for _, expr in ipairs(lispFn.body) do
											CEKMachine.evaluate(expr, localEnv)
										end
									end
									val = obj.Touched:Connect(wrapped)
								else
									val = obj.Touched:Connect(handler)
								end

							elseif formName == "instance" then
								local className = elements[2].value
								local obj = Instance.new(className)
								local i = 3
								while i <= #elements do
									local elem = elements[i]
									if elem.type == "symbol" and elem.name:sub(1, 1) == ":" then
										local propName = elem.name:sub(2)
										if i + 1 <= #elements then
											local propVal = CEKMachine.evaluate(elements[i + 1], env)
											if propName == "BrickColor" and type(propVal) == "string" then
												propVal = BrickColor.new(propVal)
											end
											obj[propName] = propVal
											i = i + 2
										else
											i = i + 1
										end
									elseif elem.type == "list" then
										local child = CEKMachine.evaluate(elem, env)
										if child and type(child) == "userdata" then
											child.Parent = obj
										end
										i = i + 1
									else
										i = i + 1
									end
								end
								val = obj

							elseif formName == "service" then
								local serviceName = elements[2].value
								val = game:GetService(serviceName)

							elseif formName == "connect" then
								local obj = CEKMachine.evaluate(elements[2], env)
								local eventName = elements[3].value
								local handler = CEKMachine.evaluate(elements[4], env)
								if type(handler) == "table" and handler.type == "function" then
									local lispFn = handler
									handler = function(...)
										local args = { ... }
										local localEnv = {}
										setmetatable(localEnv, { __index = lispFn.closure })
										bindLambdaArgs(lispFn.argsInfo, args, localEnv)
										for _, expr in ipairs(lispFn.body) do
											CEKMachine.evaluate(expr, localEnv)
										end
									end
								end
								val = obj[eventName]:Connect(handler)

							elseif formName == "raycast" then
								local origin = CEKMachine.evaluate(elements[2], env)
								local direction = CEKMachine.evaluate(elements[3], env)
								local params = nil
								if #elements >= 5 then
									params = CEKMachine.evaluate(elements[4], env)
								end
								local raycastParams = params or RaycastParams.new()
								val = workspace:Raycast(origin, direction, raycastParams)

							elseif formName == "play-sound" then
								local soundId = elements[2].value
								local props = {}
								local i = 3
								while i <= #elements do
									local key = elements[i]
									if key.type == "symbol" and key.name:sub(1, 1) == ":" then
										local propName = key.name:sub(2)
										if i + 1 <= #elements then
											props[propName] = CEKMachine.evaluate(elements[i + 1], env)
											i = i + 2
										end
									elseif type(key) == "string" and key:sub(1, 1) == ":" then
										local propName = key:sub(2)
										if i + 1 <= #elements then
											props[propName] = CEKMachine.evaluate(elements[i + 1], env)
											i = i + 2
										end
									else
										i = i + 1
									end
								end
								local sound = Instance.new("Sound")
								sound.SoundId = soundId
								sound.Volume = props.Volume or 0.5
								sound.Looped = props.Looped or false
								sound.Parent = props.Parent or workspace
								sound:Play()
								val = sound

							elseif formName == "body-velocity" then
								local parent = CEKMachine.evaluate(elements[2], env)
								local props = {}
								local i = 3
								while i <= #elements do
									local key = elements[i]
									if key.type == "symbol" and key.name:sub(1, 1) == ":" then
										local propName = key.name:sub(2)
										if i + 1 <= #elements then
											props[propName] = CEKMachine.evaluate(elements[i + 1], env)
											i = i + 2
										end
									elseif type(key) == "string" and key:sub(1, 1) == ":" then
										local propName = key:sub(2)
										if i + 1 <= #elements then
											props[propName] = CEKMachine.evaluate(elements[i + 1], env)
											i = i + 2
										end
									else
										i = i + 1
									end
								end
								local bv = Instance.new("BodyVelocity")
								bv.Velocity = props.Velocity or Vector3.new(0, 0, 0)
								bv.MaxForce = props.MaxForce or Vector3.new(4000, 4000, 4000)
								bv.Parent = parent
								val = bv

							else
								local pendingArgs = {}
								for i = 2, #elements do table.insert(pendingArgs, elements[i]) end
								table.insert(kStack, { type = "eval-arg", env = env, pending = pendingArgs, ready = {} })
								control = first
							end
						else
							local pendingArgs = {}
							for i = 2, #elements do table.insert(pendingArgs, elements[i]) end
							table.insert(kStack, { type = "eval-arg", env = env, pending = pendingArgs, ready = {} })
							control = first
						end
					end
				end
			end
		else
			if #kStack == 0 then break end
			local frame = table.remove(kStack)

			if frame.type == "define-var" then
				frame.env[frame.varName] = val
				val = frame.varName

			elseif frame.type == "if-branch" then
				local cond = val
				local branch = cond and frame.thenBranch or frame.elseBranch
				if branch then
					control = branch
				else
					val = nil
				end

			elseif frame.type == "begin-seq" then
				-- nothing

			elseif frame.type == "set-var" then
				local varName = frame.varName
				local cur = frame.env
				while cur do
					if rawget(cur, varName) ~= nil then
						cur[varName] = val
						break
					end
					local mt = getmetatable(cur)
					if mt and mt.__index and type(mt.__index) == "table" then
						cur = mt.__index
					else
						break
					end
				end
				if not rawget(frame.env, varName) then
					frame.env[varName] = val
				end

			elseif frame.type == "let-bind" then
				frame.env[frame.varName] = val
				local nextIndex = frame.index + 1
				if nextIndex <= #frame.bindings then
					local binding = frame.bindings[nextIndex]
					if binding.type == "list" and #binding.elements == 2 then
						frame.index = nextIndex
						table.insert(kStack, frame)
						control = binding.elements[2]
					end
				else
					env = frame.env
					if #frame.body > 0 then
						control = frame.body[1]
					else
						val = nil
					end
				end

			elseif frame.type == "callcc" then
				local f = val
				if type(f) == "table" and f.type == "function" then
					local localEnv: { [string]: any } = {}
					setmetatable(localEnv, { __index = f.closure })
					if f.argsInfo.required[1] then
						localEnv[f.argsInfo.required[1]] = frame.cont
					end
					if #f.body > 0 then
						if #f.body > 1 then
							table.insert(kStack, {
								type = "func-body",
								body = { table.unpack(f.body, 2) },
								env = localEnv
							})
						end
						control = f.body[1]
						env = localEnv
					else
						val = nil
					end
				elseif type(f) == "function" then
					val = f(frame.cont)
					control = nil
				else
					error("call/cc: argument must be a function")
				end

			elseif frame.type == "func-body" then
				if #frame.body > 0 then
					local nextExpr = table.remove(frame.body, 1)
					table.insert(kStack, frame)
					control = nextExpr
				end

			elseif frame.type == "for-loop" then
				local loopFrame = frame
				local localEnv = {}
				setmetatable(localEnv, { __index = loopFrame.env })
				local varName
				if type(loopFrame.init) == "table" and loopFrame.init.type == "symbol" then
					varName = loopFrame.init.name
				elseif type(loopFrame.init) == "table" and loopFrame.init.type == "list" then
					varName = loopFrame.init.elements[1].name
				end
				localEnv[varName] = val
				table.insert(kStack, {
					type = "for-check",
					env = localEnv,
					cond = loopFrame.cond,
					step = loopFrame.step,
					body = loopFrame.body,
					varName = varName
				})
				control = loopFrame.cond

			elseif frame.type == "for-check" then
				local condResult = val
				if condResult then
					table.insert(kStack, { type = "for-step", env = frame.env, cond = frame.cond, step = frame.step, body = frame.body })
					control = frame.body
				else
					val = nil
				end

			elseif frame.type == "for-step" then
				local stepFrame = frame
				local localEnv = {}
				setmetatable(localEnv, { __index = stepFrame.env })
				localEnv[stepFrame.varName] = val
				table.insert(kStack, {
					type = "for-check",
					env = localEnv,
					cond = stepFrame.cond,
					step = stepFrame.step,
					body = stepFrame.body,
					varName = stepFrame.varName
				})
				control = stepFrame.step

			elseif frame.type == "while-loop" then
				if val then
					table.insert(kStack, { type = "while-body", env = frame.env, cond = frame.cond, body = frame.body })
					control = frame.body
				else
					val = nil
				end

			elseif frame.type == "while-body" then
				table.insert(kStack, { type = "while-loop", env = frame.env, cond = frame.cond, body = frame.body })
				control = frame.cond

			elseif frame.type == "eval-arg" then
				env = frame.env
				table.insert(frame.ready, val)
				if #frame.pending > 0 then
					local nextNode = table.remove(frame.pending, 1)
					table.insert(kStack, frame)
					control = nextNode
				else
					local func = table.remove(frame.ready, 1)
					local args = frame.ready

					if type(func) == "table" and func.type == "continuation" then
						kStack = {}
						for _, savedFrame in ipairs(func.stack) do
							local restoredFrame = {
								type = savedFrame.type,
								env = savedFrame.env,
								pending = savedFrame.pending and tableClone(savedFrame.pending) or nil,
								ready = savedFrame.ready and tableClone(savedFrame.ready) or nil,
								varName = savedFrame.varName,
								thenBranch = savedFrame.thenBranch,
								elseBranch = savedFrame.elseBranch,
								bindings = savedFrame.bindings,
								index = savedFrame.index,
								body = savedFrame.body,
							}
							table.insert(kStack, restoredFrame)
						end
						if #kStack > 0 then
							local topFrame = kStack[#kStack]
							if topFrame.type == "eval-arg" then
								topFrame.pending = {}
							end
						end
						val = args[1] or nil
						control = nil
					elseif type(func) == "table" and func.type == "function" then
						local localEnv: { [string]: any } = {}
						setmetatable(localEnv, { __index = func.closure })
						bindLambdaArgs(func.argsInfo, args, localEnv)
						if #func.body > 0 then
							if #func.body > 1 then
								table.insert(kStack, {
									type = "func-body",
									body = { table.unpack(func.body, 2) },
									env = localEnv
								})
							end
							control = func.body[1]
							env = localEnv
						else
							val = nil
						end
					elseif type(func) == "table" and func.type == "syntax-rules" then
						local expanded = expandSyntaxRules(func, { { type = "symbol", name = "macro" }, table.unpack(args) }, frame.env)
						if expanded then
							control = expanded
							env = frame.env
						else
							error("syntax-rules: no matching pattern")
						end
					elseif type(func) == "function" then
						val = func(table.unpack(args))
						control = nil
					else
						error("Not a function: " .. tostring(func))
					end
				end
			end
		end
	end
	return val
end

return CEKMachine
