--!strict

local PlayerGui = game:GetService("Players").LocalPlayer:WaitForChild("PlayerGui")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RemoteEvent = ReplicatedStorage:WaitForChild("LispExec")

local Runtime = require(ReplicatedStorage:WaitForChild("LispMachine"):WaitForChild("Runtime"))

local TerminalGUI = Instance.new("ScreenGui")
TerminalGUI.Name = "TerminalGUI"
TerminalGUI.Parent = PlayerGui

local Terminal = Instance.new("Frame")
Terminal.Name = "Terminal"
Terminal.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
Terminal.BorderSizePixel = 0
Terminal.Size = UDim2.new(0.8, 0, 0.8, 0)
Terminal.Position = UDim2.new(0.1, 0, 0.1, 0)
Terminal.Parent = TerminalGUI

local UIPadding = Instance.new("UIPadding")
UIPadding.PaddingLeft = UDim.new(0, 8)
UIPadding.PaddingRight = UDim.new(0, 8)
UIPadding.PaddingTop = UDim.new(0, 8)
UIPadding.PaddingBottom = UDim.new(0, 8)
UIPadding.Parent = Terminal

local OutputFrame = Instance.new("Frame")
OutputFrame.Name = "OutputFrame"
OutputFrame.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
OutputFrame.BorderSizePixel = 0
OutputFrame.Size = UDim2.new(1, 0, 1, -30)
OutputFrame.Position = UDim2.new(0, 0, 0, 0)
OutputFrame.Parent = Terminal

local ScrollingFrame = Instance.new("ScrollingFrame")
ScrollingFrame.Name = "ScrollingFrame"
ScrollingFrame.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
ScrollingFrame.BorderSizePixel = 0
ScrollingFrame.Size = UDim2.new(1, 0, 1, 0)
ScrollingFrame.Position = UDim2.new(0, 0, 0, 0)
ScrollingFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
ScrollingFrame.ScrollBarThickness = 4
ScrollingFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
ScrollingFrame.Parent = OutputFrame

local GridLayout = Instance.new("UIGridLayout")
GridLayout.CellSize = UDim2.new(1, 0, 0, 0)
GridLayout.CellPadding = UDim2.new(0, 0, 0, 12)
GridLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
GridLayout.VerticalAlignment = Enum.VerticalAlignment.Top
GridLayout.SortOrder = Enum.SortOrder.LayoutOrder
GridLayout.Parent = ScrollingFrame

local InputFrame = Instance.new("Frame")
InputFrame.Name = "InputFrame"
InputFrame.BackgroundColor3 = Color3.fromRGB(10, 10, 10)
InputFrame.BorderSizePixel = 0
InputFrame.Size = UDim2.new(1, 0, 0, 30)
InputFrame.Position = UDim2.new(0, 0, 1, -30)
InputFrame.Parent = Terminal

local InputBox = Instance.new("TextBox")
InputBox.Name = "InputBox"
InputBox.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
InputBox.BorderSizePixel = 0
InputBox.TextColor3 = Color3.fromRGB(0, 255, 0)
InputBox.PlaceholderText = ""
InputBox.Font = Enum.Font.Code
InputBox.TextSize = 14
InputBox.TextXAlignment = Enum.TextXAlignment.Left
InputBox.TextYAlignment = Enum.TextYAlignment.Center
InputBox.Size = UDim2.new(1, -16, 0, 24)
InputBox.Position = UDim2.new(0, 8, 0, 3)
InputBox.Text = ""
InputBox.ClearTextOnFocus = false
InputBox.TextWrapped = false
InputBox.MultiLine = false
InputBox.Parent = InputFrame

local history: { string } = {}
local historyIndex: number = 0
local lineCounter: number = 0
local mode: string = "menu"

local function addOutput(text: string, color: Color3?): ()
	local line = Instance.new("TextLabel")
	line.BackgroundTransparency = 1
	line.Font = Enum.Font.Code
	line.TextSize = 14
	line.TextXAlignment = Enum.TextXAlignment.Left
	line.TextYAlignment = Enum.TextYAlignment.Top
	line.TextWrapped = true
	line.RichText = false
	line.Text = text
	line.TextColor3 = color or Color3.fromRGB(0, 255, 0)
	line.Size = UDim2.new(1, 0, 0, 0)
	line.AutomaticSize = Enum.AutomaticSize.Y
	line.LayoutOrder = lineCounter
	lineCounter = lineCounter + 1
	line.Parent = ScrollingFrame

	ScrollingFrame.CanvasPosition = Vector2.new(0, ScrollingFrame.CanvasSize.Y.Offset)
end

local function setMode(newMode: string): ()
	mode = newMode
	if mode == "server" then
		InputBox.PlaceholderText = "[SERVER] Enter Lisp code..."
		addOutput("Switched to SERVER mode", Color3.fromRGB(255, 255, 0))
	elseif mode == "local" then
		InputBox.PlaceholderText = "[LOCAL] Enter Lisp code..."
		addOutput("Switched to LOCAL mode", Color3.fromRGB(255, 255, 0))
	elseif mode == "menu" then
		InputBox.PlaceholderText = "[S]erver or [L]ocal? (type s or l)"
		addOutput("Select mode: [S]erver or [L]ocal?", Color3.fromRGB(255, 255, 0))
	end
end

local function executeCommand(input: string): ()
	local trimmed = input:gsub("^%s+", ""):gsub("%s+$", "")
	if trimmed == "" then return end

	if mode == "menu" then
		if trimmed == "s" then
			setMode("server")
		elseif trimmed == "l" then
			setMode("local")
		else
			addOutput("Invalid choice. Type 's' or 'l'", Color3.fromRGB(255, 100, 100))
		end
		return
	end

	if trimmed == "menu" then
		setMode("menu")
		return
	end

	table.insert(history, trimmed)
	historyIndex = #history + 1

	addOutput("> " .. trimmed, Color3.fromRGB(0, 255, 0))

	if mode == "server" then
		RemoteEvent:FireServer(trimmed)
	elseif mode == "local" then
		local success, result = pcall(Runtime.execute, trimmed)
		if not success then
			addOutput("ERROR: " .. tostring(result), Color3.fromRGB(255, 50, 50))
		else
			addOutput(tostring(result), Color3.fromRGB(100, 255, 100))
		end
	end
end

RemoteEvent.OnClientEvent:Connect(function(result: string, isError: boolean): ()
	if isError then
		addOutput("ERROR: " .. tostring(result), Color3.fromRGB(255, 50, 50))
	else
		addOutput(tostring(result), Color3.fromRGB(100, 255, 100))
	end
end)

InputBox.FocusLost:Connect(function(enterPressed: boolean): ()
	if enterPressed then
		local text = InputBox.Text
		InputBox.Text = ""
		executeCommand(text)
		task.wait()
		InputBox:CaptureFocus()
	end
end)

UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean): ()
	if gameProcessed then return end

	if input.KeyCode == Enum.KeyCode.Up then
		if historyIndex > 0 then
			historyIndex = historyIndex - 1
			InputBox.Text = history[historyIndex] or ""
		end
	elseif input.KeyCode == Enum.KeyCode.Down then
		if historyIndex < #history then
			historyIndex = historyIndex + 1
			InputBox.Text = history[historyIndex] or ""
		else
			historyIndex = #history + 1
			InputBox.Text = ""
		end
	end
end)

setMode("menu")
InputBox:CaptureFocus()
