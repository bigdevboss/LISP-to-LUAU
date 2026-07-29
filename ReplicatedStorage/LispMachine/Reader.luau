--!strict

local Reader = {}

local function tokenize(str: string): { any }
	local tokens = {}
	local i = 1

	while i <= #str do
		local c = str:sub(i, i)

		if c == " " or c == "\t" or c == "\n" or c == "\r" then
			i = i + 1
		elseif c == ";" then
			while i <= #str and str:sub(i, i) ~= "\n" and str:sub(i, i) ~= "\r" do
				i = i + 1
			end
		elseif c == "(" then
			table.insert(tokens, {type = "lparen", value = "("})
			i = i + 1
		elseif c == ")" then
			table.insert(tokens, {type = "rparen", value = ")"})
			i = i + 1
		elseif c == "'" then
			table.insert(tokens, {type = "quote", value = "'"})
			i = i + 1
		elseif c == '"' then
			local s = ""
			i = i + 1
			while i <= #str do
				local ch = str:sub(i, i)
				if ch == '\\' then
					i = i + 1
					local nextCh = str:sub(i, i)
					if nextCh == 'n' then s = s .. '\n'
					elseif nextCh == 't' then s = s .. '\t'
					elseif nextCh == '"' then s = s .. '"'
					elseif nextCh == '\\' then s = s .. '\\'
					else s = s .. nextCh end
				elseif ch == '"' then
					break
				else
					s = s .. ch
				end
				i = i + 1
			end
			i = i + 1
			table.insert(tokens, {type = "string", value = s})
		elseif c == "-" and str:sub(i+1, i+1) and tonumber(str:sub(i+1, i+1)) then
			local start = i
			i = i + 1
			while i <= #str do
				local ch = str:sub(i, i)
				if ch == "." or tonumber(ch) then
					i = i + 1
				else
					break
				end
			end
			local num = tonumber(str:sub(start, i - 1))
			table.insert(tokens, {type = "number", value = num})
		elseif tonumber(c) then
			local start = i
			while i <= #str do
				local ch = str:sub(i, i)
				if ch == "." or tonumber(ch) then
					i = i + 1
				else
					break
				end
			end
			local num = tonumber(str:sub(start, i - 1))
			table.insert(tokens, {type = "number", value = num})
		else
			local start = i
			while i <= #str do
				local ch = str:sub(i, i)
				if ch == " " or ch == "\t" or ch == "\n" or ch == "\r" or ch == "(" or ch == ")" or ch == ";" then
					break
				end
				i = i + 1
			end
			local sym = str:sub(start, i - 1)
			if sym == "nil" then
				table.insert(tokens, {type = "nil"})
			elseif sym == "true" or sym == "#t" then
				table.insert(tokens, {type = "boolean", value = true})
			elseif sym == "false" or sym == "#f" then
				table.insert(tokens, {type = "boolean", value = false})
			else
				table.insert(tokens, {type = "symbol", value = sym})
			end
		end
	end

	return tokens
end

local function readTokens(tokens: { any }, pos: number): (any, number)
	if pos > #tokens then
		return nil, pos
	end

	local token = tokens[pos]

	if token.type == "lparen" then
		local list = {type = "list", elements = {}}
		pos = pos + 1
		while pos <= #tokens and tokens[pos].type ~= "rparen" do
			local elem, newPos = readTokens(tokens, pos)
			if elem then
				table.insert(list.elements, elem)
				pos = newPos
			else
				break
			end
		end
		if pos <= #tokens and tokens[pos].type == "rparen" then
			pos = pos + 1
		end
		return list, pos
	elseif token.type == "quote" then
		pos = pos + 1
		local quoted, newPos = readTokens(tokens, pos)
		local quoteList = {
			type = "list",
			elements = {
				{type = "symbol", value = "quote"},
				quoted
			}
		}
		return quoteList, newPos
	elseif token.type == "number" then
		return {type = "number", value = token.value}, pos + 1
	elseif token.type == "string" then
		return {type = "string", value = token.value}, pos + 1
	elseif token.type == "boolean" then
		return {type = "boolean", value = token.value}, pos + 1
	elseif token.type == "nil" then
		return {type = "nil"}, pos + 1
	elseif token.type == "symbol" then
		return {type = "symbol", name = token.value}, pos + 1
	end

	return nil, pos
end

function Reader.parse(str: string): { any }
	local tokens = tokenize(str)
	local ast = {}
	local pos = 1

	while pos <= #tokens do
		local expr, newPos = readTokens(tokens, pos)
		if expr then
			table.insert(ast, expr)
			pos = newPos
		else
			pos = pos + 1
		end
	end

	return ast
end

return Reader
