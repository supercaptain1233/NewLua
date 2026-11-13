--[[
════════════════════════════════════════════════════════════════════
   N O C L I P
   --------------------------------------------------------------
   file      : noclip.lua
   author    : supercaptain1233
   target    : Delta (Android)  ·  universal  ·  any Roblox game
   version   : 1.0.0
   --------------------------------------------------------------
   panel
     · medium floating panel, anchored top-left
     · header title  : "Noclip"
     · X button      : collapses the entire script to a dot
     · move button   : arrow-cross icon, whole panel becomes draggable
     · circle button : ring icon, whole script becomes a dot that
                       follows the finger
     · centre button : big red NOCLIP toggle
   --------------------------------------------------------------
   noclip
     · every BasePart of the character is ghosted (CanCollide off)
     · the floor is preserved with a downward raycast hover, so
       walls are ignored but the ground is not
     · original CanCollide values are stored and restored
   --------------------------------------------------------------
   no print() calls in this file
════════════════════════════════════════════════════════════════════
]]

--====================================================================
-- 01 · CONFIG
--====================================================================

local CONFIG = {
	-- panel geometry -------------------------------------------------
	panelWidth        = 190,
	panelHeight       = 148,
	panelX            = 24,
	panelY            = 88,
	cornerRadius      = 10,

	-- header ---------------------------------------------------------
	headerHeight      = 30,
	title             = "Noclip",
	titleSize         = 13,
	headerButtonSize  = 24,
	headerGap         = 4,

	-- body -----------------------------------------------------------
	bodyPadding       = 12,
	noclipHeight      = 54,
	noclipLabel       = "NOCLIP",
	noclipLabelActive = "NOCLIP: ON",
	noclipTextSize    = 15,

	-- compact representation -----------------------------------------
	dotCircleSize     = 46,
	dotCollapsedSize  = 30,
	dotLetter         = "N",

	-- colours --------------------------------------------------------
	colorPanel        = Color3.fromRGB(19, 22, 28),
	colorHeader       = Color3.fromRGB(28, 32, 40),
	colorBody         = Color3.fromRGB(15, 17, 22),
	colorButton       = Color3.fromRGB(44, 49, 60),
	colorButtonHover  = Color3.fromRGB(60, 67, 82),
	colorActive       = Color3.fromRGB(64, 110, 74),
	colorOff          = Color3.fromRGB(224, 49, 49),
	colorOn           = Color3.fromRGB(45, 168, 88),
	colorText         = Color3.fromRGB(235, 238, 243),
	colorMuted        = Color3.fromRGB(120, 128, 140),
	colorStroke       = Color3.fromRGB(52, 58, 70),

	-- noclip engine --------------------------------------------------
	hoverHeight       = 0.25,   -- studs between feet and floor
	stickRange        = 14,     -- max ray length looking for floor
	stickStiffness    = 14,     -- hover spring strength
	maxStickSpeed     = 55,     -- clamp on the hover correction
	ghostRefreshRate  = 10,     -- frames between CanCollide re-applies

	-- drag -----------------------------------------------------------
	tapThreshold      = 8,      -- px of movement before it counts as drag
	screenPadding     = 4,

	-- misc -----------------------------------------------------------
	displayOrder      = 9999,
	guiName           = "NoClipUI",
	tweenTime         = 0.16,
}

--====================================================================
-- 02 · SERVICES
--====================================================================

local Players          = game:GetService("Players")
local RunService       = game:GetService("RunService")
local TweenService     = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local CoreGui          = game:GetService("CoreGui")
local Workspace        = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer
if not LocalPlayer then
	Players:GetPropertyChangedSignal("LocalPlayer"):Wait()
	LocalPlayer = Players.LocalPlayer
end

--====================================================================
-- 03 · SMALL UTILITIES
--====================================================================

-- single-shot wait for a child, bounded
local function waitFor(parent, name, timeout)
	timeout = timeout or 10
	local found = parent:FindFirstChild(name)
	if found then
		return found
	end
	local start = os.clock()
	while os.clock() - start < timeout do
		found = parent:FindFirstChild(name)
		if found then
			return found
		end
		task.wait(0.1)
	end
	return nil
end

-- instance builder: properties first, parent last
local function new(class, props, children)
	local inst = Instance.new(class)
	local parent = nil
	if props then
		parent = props.Parent
		for key, value in pairs(props) do
			if key ~= "Parent" then
				inst[key] = value
			end
		end
	end
	if children then
		for _, child in ipairs(children) do
			child.Parent = inst
		end
	end
	if parent then
		inst.Parent = parent
	end
	return inst
end

-- rounded corners
local function round(inst, radius)
	new("UICorner", {
		CornerRadius = UDim.new(0, radius or 8),
		Parent = inst,
	})
	return inst
end

-- hairline border
local function stroke(inst, colour, thickness, transparency)
	new("UIStroke", {
		Color = colour or CONFIG.colorStroke,
		Thickness = thickness or 1,
		Transparency = transparency or 0,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Parent = inst,
	})
	return inst
end

-- padding helper
local function pad(inst, top, right, bottom, left)
	new("UIPadding", {
		PaddingTop = UDim.new(0, top or 0),
		PaddingRight = UDim.new(0, right or 0),
		PaddingBottom = UDim.new(0, bottom or 0),
		PaddingLeft = UDim.new(0, left or 0),
		Parent = inst,
	})
	return inst
end

-- tween wrapper
local function tween(inst, props, time, style, direction)
	local info = TweenInfo.new(
		time or CONFIG.tweenTime,
		style or Enum.EasingStyle.Quad,
		direction or Enum.EasingDirection.Out
	)
	local anim = TweenService:Create(inst, info, props)
	anim:Play()
	return anim
end

-- current viewport size, safe on mobile
local function viewport()
	local camera = Workspace.CurrentCamera
	if camera then
		return camera.ViewportSize
	end
	return Vector2.new(1080, 1920)
end

-- keep an absolute pixel position inside the screen
local function clampToScreen(x, y, width, height)
	local vp = viewport()
	local padPx = CONFIG.screenPadding
	local maxX = math.max(padPx, vp.X - width - padPx)
	local maxY = math.max(padPx, vp.Y - height - padPx)
	return math.clamp(x, padPx, maxX), math.clamp(y, padPx, maxY)
end

-- where the gui should live
local function guiParent()
	local ok, hidden = pcall(function()
		return gethui and gethui() or nil
	end)
	if ok and hidden then
		return hidden
	end
	local okCore = pcall(function()
		return CoreGui
	end)
	if okCore and CoreGui then
		return CoreGui
	end
	return LocalPlayer:WaitForChild("PlayerGui")
end

--====================================================================
-- 04 · STATE
--====================================================================

local state = {
	mode       = "normal",   -- normal | circle | collapsed
	dragMode   = false,
	noclip     = false,
	destroyed  = false,
}

local panel, dot, dotGlyph, dotLetter
local noclipButton, noclipLabel, statusLabel
local moveButton, moveButtonStroke, moveIconParts
local circleButton, circleButtonStroke
local closeButton
local gui

local connections = {}

local function track(connection)
	connections[#connections + 1] = connection
	return connection
end

--====================================================================
-- 05 · ICONS
--====================================================================

-- arrow cross:  ↑  /  ← →  /  ↓
local function buildMoveIcon(parent)
	local wrap = new("Frame", {
		Name = "MoveIcon",
		Size = UDim2.fromOffset(16, 16),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		Parent = parent,
	})

	local glyphs = {
		{ text = "\u{2191}", x = 0, y = 0 },      -- up
		{ text = "\u{2190}", x = 0, y = 5.5 },    -- left
		{ text = "\u{2192}", x = 8, y = 5.5 },    -- right
		{ text = "\u{2193}", x = 0, y = 11 },     -- down
	}

	local parts = {}
	for _, glyph in ipairs(glyphs) do
		local label = new("TextLabel", {
			Size = UDim2.fromOffset(8, 5),
			Position = UDim2.fromOffset(glyph.x, glyph.y),
			BackgroundTransparency = 1,
			Text = glyph.text,
			TextSize = 8,
			Font = Enum.Font.GothamBold,
			TextColor3 = CONFIG.colorText,
			TextXAlignment = Enum.TextXAlignment.Center,
			TextYAlignment = Enum.TextYAlignment.Center,
			Parent = wrap,
		})
		parts[#parts + 1] = label
	end

	return parts
end

-- compact ring: outer circle plus centre dot
local function buildCircleIcon(parent)
	local wrap = new("Frame", {
		Name = "CircleIcon",
		Size = UDim2.fromOffset(16, 16),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		Parent = parent,
	})

	local ring = new("Frame", {
		Name = "Ring",
		Size = UDim2.fromOffset(12, 12),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		Parent = wrap,
	})
	round(ring, 12)
	stroke(ring, CONFIG.colorText, 1.4, 0)

	local centre = new("Frame", {
		Name = "Centre",
		Size = UDim2.fromOffset(4, 4),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = CONFIG.colorText,
		BorderSizePixel = 0,
		Parent = wrap,
	})
	round(centre, 4)

	return { ring = ring, centre = centre }
end

--====================================================================
-- 06 · GUI CONSTRUCTION
--====================================================================

local function buildGui()
	gui = new("ScreenGui", {
		Name = CONFIG.guiName,
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		IgnoreGuiInset = true,
		DisplayOrder = CONFIG.displayOrder,
		Parent = guiParent(),
	})

	panel = new("Frame", {
		Name = "Panel",
		Size = UDim2.fromOffset(CONFIG.panelWidth, CONFIG.panelHeight),
		Position = UDim2.fromOffset(CONFIG.panelX, CONFIG.panelY),
		BackgroundColor3 = CONFIG.colorPanel,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		Parent = gui,
	})
	round(panel, CONFIG.cornerRadius)
	stroke(panel, CONFIG.colorStroke, 1, 0.25)

	-- header ---------------------------------------------------------
	local header = new("Frame", {
		Name = "Header",
		Size = UDim2.new(1, 0, 0, CONFIG.headerHeight),
		Position = UDim2.fromOffset(0, 0),
		BackgroundColor3 = CONFIG.colorHeader,
		BorderSizePixel = 0,
		Parent = panel,
	})

	local title = new("TextLabel", {
		Name = "Title",
		Size = UDim2.new(1, -(CONFIG.headerButtonSize * 3) - (CONFIG.headerGap * 3) - 10, 1, 0),
		Position = UDim2.fromOffset(10, 0),
		BackgroundTransparency = 1,
		Text = CONFIG.title,
		TextSize = CONFIG.titleSize,
		Font = Enum.Font.GothamBold,
		TextColor3 = CONFIG.colorText,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
		Parent = header,
	})

	local buttonRow = new("Frame", {
		Name = "Buttons",
		Size = UDim2.new(0, (CONFIG.headerButtonSize * 3) + (CONFIG.headerGap * 2), 1, 0),
		Position = UDim2.new(1, -6, 0, 0),
		AnchorPoint = Vector2.new(1, 0),
		BackgroundTransparency = 1,
		Parent = header,
	})

	new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Right,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, CONFIG.headerGap),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = buttonRow,
	})

	-- circle button (leftmost)
	circleButton = new("TextButton", {
		Name = "CircleButton",
		LayoutOrder = 1,
		Size = UDim2.fromOffset(CONFIG.headerButtonSize, CONFIG.headerButtonSize),
		BackgroundColor3 = CONFIG.colorButton,
		BorderSizePixel = 0,
		Text = "",
		AutoButtonColor = false,
		Parent = buttonRow,
	})
	round(circleButton, 6)
	circleButtonStroke = stroke(circleButton, CONFIG.colorStroke, 1, 0.4)
	buildCircleIcon(circleButton)

	-- move button (middle)
	moveButton = new("TextButton", {
		Name = "MoveButton",
		LayoutOrder = 2,
		Size = UDim2.fromOffset(CONFIG.headerButtonSize, CONFIG.headerButtonSize),
		BackgroundColor3 = CONFIG.colorButton,
		BorderSizePixel = 0,
		Text = "",
		AutoButtonColor = false,
		Parent = buttonRow,
	})
	round(moveButton, 6)
	moveButtonStroke = stroke(moveButton, CONFIG.colorStroke, 1, 0.4)
	moveIconParts = buildMoveIcon(moveButton)

	-- close button (rightmost)
	closeButton = new("TextButton", {
		Name = "CloseButton",
		LayoutOrder = 3,
		Size = UDim2.fromOffset(CONFIG.headerButtonSize, CONFIG.headerButtonSize),
		BackgroundColor3 = CONFIG.colorButton,
		BorderSizePixel = 0,
		Text = "\u{2715}",
		TextSize = 12,
		Font = Enum.Font.GothamBold,
		TextColor3 = CONFIG.colorText,
		AutoButtonColor = false,
		Parent = buttonRow,
	})
	round(closeButton, 6)
	stroke(closeButton, CONFIG.colorStroke, 1, 0.4)

	-- body -----------------------------------------------------------
	local body = new("Frame", {
		Name = "Body",
		Size = UDim2.new(1, 0, 1, -CONFIG.headerHeight),
		Position = UDim2.fromOffset(0, CONFIG.headerHeight),
		BackgroundColor3 = CONFIG.colorBody,
		BorderSizePixel = 0,
		Parent = panel,
	})
	pad(body, CONFIG.bodyPadding, CONFIG.bodyPadding, 8, CONFIG.bodyPadding)

	new("UIListLayout", {
		FillDirection = Enum.FillDirection.Vertical,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = body,
	})

	noclipButton = new("TextButton", {
		Name = "NoclipButton",
		LayoutOrder = 1,
		Size = UDim2.new(1, 0, 0, CONFIG.noclipHeight),
		BackgroundColor3 = CONFIG.colorOff,
		BorderSizePixel = 0,
		Text = "",
		AutoButtonColor = false,
		Parent = body,
	})
	round(noclipButton, 8)
	stroke(noclipButton, Color3.fromRGB(255, 255, 255), 1, 0.75)

	noclipLabel = new("TextLabel", {
		Name = "Label",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Text = CONFIG.noclipLabel,
		TextSize = CONFIG.noclipTextSize,
		Font = Enum.Font.GothamBold,
		TextColor3 = Color3.fromRGB(255, 255, 255),
		Parent = noclipButton,
	})

	statusLabel = new("TextLabel", {
		Name = "Status",
		LayoutOrder = 2,
		Size = UDim2.new(1, 0, 0, 14),
		BackgroundTransparency = 1,
		Text = "idle",
		TextSize = 11,
		Font = Enum.Font.Gotham,
		TextColor3 = CONFIG.colorMuted,
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = body,
	})

	-- compact dot ----------------------------------------------------
	dot = new("TextButton", {
		Name = "Dot",
		Size = UDim2.fromOffset(CONFIG.dotCircleSize, CONFIG.dotCircleSize),
		Position = UDim2.fromOffset(CONFIG.panelX, CONFIG.panelY),
		BackgroundColor3 = CONFIG.colorPanel,
		BorderSizePixel = 0,
		Text = "",
		AutoButtonColor = false,
		Visible = false,
		Parent = gui,
	})
	round(dot, 1)
	stroke(dot, CONFIG.colorStroke, 1, 0.2)

	dotGlyph = new("Frame", {
		Name = "Glyph",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Parent = dot,
	})
	buildCircleIcon(dotGlyph)

	dotLetter = new("TextLabel", {
		Name = "Letter",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Text = CONFIG.dotLetter,
		TextSize = 13,
		Font = Enum.Font.GothamBold,
		TextColor3 = CONFIG.colorText,
		Visible = false,
		Parent = dot,
	})
end

--====================================================================
-- 07 · MODES
--====================================================================

local function applyMode(mode)
	state.mode = mode

	if mode == "normal" then
		dot.Visible = false
		panel.Visible = true
		panel.Position = dot.Position
		local x, y = clampToScreen(
			panel.Position.X.Offset,
			panel.Position.Y.Offset,
			panel.AbsoluteSize.X,
			panel.AbsoluteSize.Y
		)
		panel.Position = UDim2.fromOffset(x, y)
		return
	end

	local size = (mode == "circle") and CONFIG.dotCircleSize or CONFIG.dotCollapsedSize

	dot.Size = UDim2.fromOffset(size, size)
	dotGlyph.Visible = (mode == "circle")
	dotLetter.Visible = (mode == "collapsed")

	local x, y = clampToScreen(
		panel.Position.X.Offset,
		panel.Position.Y.Offset,
		size,
		size
	)
	dot.Position = UDim2.fromOffset(x, y)

	panel.Visible = false
	dot.Visible = true
end

local function toggleMode(mode)
	if state.mode == mode then
		applyMode("normal")
	else
		applyMode(mode)
	end
end

--====================================================================
-- 08 · DRAG
--====================================================================

local function attachDrag(handle, target, options)
	options = options or {}

	track(handle.InputBegan:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.MouseButton1
			and input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end
		if options.condition and not options.condition() then
			return
		end

		local origin = input.Position
		local startPos = target.Position
		local moved = 0
		local watcher

		local function update()
			local delta = input.Position - origin
			moved = math.max(moved, delta.Magnitude)

			local x = startPos.X.Offset + delta.X
			local y = startPos.Y.Offset + delta.Y
			x, y = clampToScreen(x, y, target.AbsoluteSize.X, target.AbsoluteSize.Y)
			target.Position = UDim2.fromOffset(x, y)
		end

		watcher = input.Changed:Connect(update)

		input.Ended:Connect(function()
			if watcher then
				watcher:Disconnect()
				watcher = nil
			end
			if options.onEnd then
				options.onEnd(moved)
			end
		end)
	end))
end

--====================================================================
-- 09 · NOCLIP ENGINE
--====================================================================

local ghosted      = {}          -- [BasePart] = original CanCollide
local engineConns  = {}
local heartbeat
local frameClock   = 0

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.IgnoreWater = true
rayParams.RespectCanCollide = false

local function ghostPart(part)
	if not part:IsA("BasePart") then
		return
	end
	if ghosted[part] == nil then
		ghosted[part] = part.CanCollide
	end
	part.CanCollide = false
end

local function ghostCharacter(character)
	for _, descendant in ipairs(character:GetDescendants()) do
		ghostPart(descendant)
	end
end

local function restoreCharacter()
	for part, value in pairs(ghosted) do
		if part and part.Parent then
			pcall(function()
				part.CanCollide = value
			end)
		end
	end
	table.clear(ghosted)
end

-- hover correction, keeps the character on the floor without
-- letting walls get in the way
local function hoverStep(character, humanoid, root)
	local okState, humanoidState = pcall(function()
		return humanoid:GetState()
	end)
	if not okState then
		humanoidState = nil
	end

	if humanoidState == Enum.HumanoidStateType.Swimming
		or humanoidState == Enum.HumanoidStateType.Climbing then
		return
	end

	local velocity = root.AssemblyLinearVelocity
	if humanoidState == Enum.HumanoidStateType.Jumping or velocity.Y > 2 then
		return
	end

	local hip = humanoid.HipHeight or 0
	local offset = (root.Size.Y * 0.5) + hip + CONFIG.hoverHeight
	local reach = CONFIG.stickRange + offset

	local result = Workspace:Raycast(
		root.Position,
		Vector3.new(0, -reach, 0),
		rayParams
	)
	if not result then
		return
	end

	local targetY = result.Position.Y + offset
	local difference = targetY - root.Position.Y

	if math.abs(difference) < 0.02 then
		root.AssemblyLinearVelocity = Vector3.new(velocity.X, 0, velocity.Z)
	else
		local correction = math.clamp(
			difference * CONFIG.stickStiffness,
			-CONFIG.maxStickSpeed,
			CONFIG.maxStickSpeed
		)
		root.AssemblyLinearVelocity = Vector3.new(velocity.X, correction, velocity.Z)
	end

	-- hold the humanoid in a grounded state so walking and jumping
	-- still behave normally while every part is ghosted
	if humanoidState == Enum.HumanoidStateType.Freefall and difference < 0.6 then
		pcall(function()
			humanoid:ChangeState(Enum.HumanoidStateType.Running)
		end)
	end
end

local function onHeartbeat()
	if not state.noclip then
		return
	end

	local character = LocalPlayer.Character
	if not character or not character.Parent then
		return
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if not humanoid or not root or root.Parent ~= character then
		return
	end

	frameClock += 1
	if frameClock >= CONFIG.ghostRefreshRate then
		frameClock = 0
		ghostCharacter(character)
	end

	rayParams.FilterDescendantsInstances = { character }
	hoverStep(character, humanoid, root)
end

local function stopEngine()
	for _, connection in ipairs(engineConns) do
		connection:Disconnect()
	end
	table.clear(engineConns)

	if heartbeat then
		heartbeat:Disconnect()
		heartbeat = nil
	end

	restoreCharacter()
end

local function startEngine()
	local character = LocalPlayer.Character
	if not character then
		return false
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if not humanoid or not root then
		return false
	end

	table.clear(ghosted)
	ghostCharacter(character)

	engineConns[#engineConns + 1] = character.DescendantAdded:Connect(ghostPart)

	engineConns[#engineConns + 1] = humanoid.Died:Connect(function()
		stopEngine()
		if state.noclip then
			local fresh = LocalPlayer:WaitForChild("Character", 10)
			if fresh then
				task.wait(0.4)
				if state.noclip then
					startEngine()
				end
			end
		end
	end)

	heartbeat = RunService.Heartbeat:Connect(onHeartbeat)
	return true
end

--====================================================================
-- 10 · UI REFRESH
--====================================================================

local function paintNoclip()
	if state.noclip then
		noclipButton.BackgroundColor3 = CONFIG.colorOn
		noclipLabel.Text = CONFIG.noclipLabelActive
		statusLabel.Text = "active"
		statusLabel.TextColor3 = CONFIG.colorOn
	else
		noclipButton.BackgroundColor3 = CONFIG.colorOff
		noclipLabel.Text = CONFIG.noclipLabel
		statusLabel.Text = "idle"
		statusLabel.TextColor3 = CONFIG.colorMuted
	end
end

local function paintDragMode()
	local on = state.dragMode
	moveButton.BackgroundColor3 = on and CONFIG.colorActive or CONFIG.colorButton
	if moveButtonStroke then
		moveButtonStroke.Transparency = on and 0 or 0.4
	end
end

local function setNoclip(enabled)
	if state.noclip == enabled then
		return
	end

	if enabled then
		if startEngine() then
			state.noclip = true
		end
	else
		state.noclip = false
		stopEngine()
	end

	paintNoclip()
end

--====================================================================
-- 11 · WIRING
--====================================================================

local function wire()
	-- noclip toggle
	track(noclipButton.Activated:Connect(function()
		setNoclip(not state.noclip)
	end))

	-- move mode toggle
	track(moveButton.Activated:Connect(function()
		state.dragMode = not state.dragMode
		paintDragMode()
	end))

	-- circle mode
	track(circleButton.Activated:Connect(function()
		toggleMode("circle")
	end))

	-- collapse
	track(closeButton.Activated:Connect(function()
		toggleMode("collapsed")
	end))

	-- drag the panel from the header
	attachDrag(panel, panel, {
		condition = function()
			local mouse = UserInputService:GetMouseLocation()
			local headerTop = panel.AbsolutePosition.Y
			return mouse.Y <= headerTop + CONFIG.headerHeight
		end,
	})

	-- drag the whole panel from anywhere while move mode is on
	attachDrag(panel, panel, {
		condition = function()
			return state.dragMode
		end,
	})

	-- drag the compact dot, tap to expand
	attachDrag(dot, dot, {
		onEnd = function(moved)
			if moved < CONFIG.tapThreshold then
				applyMode("normal")
			end
		end,
	})

	-- keep everything on screen after rotation / resize
	track(Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
		local camera = Workspace.CurrentCamera
		if not camera then
			return
		end
		track(camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
			local target = (state.mode == "normal") and panel or dot
			local x, y = clampToScreen(
				target.Position.X.Offset,
				target.Position.Y.Offset,
				target.AbsoluteSize.X,
				target.AbsoluteSize.Y
			)
			target.Position = UDim2.fromOffset(x, y)
		end))
	end))

	-- hover feedback on desktop
	local function bindHover(button, baseColour)
		track(button.MouseEnter:Connect(function()
			if button == moveButton and state.dragMode then
				return
			end
			if button == noclipButton and state.noclip then
				return
			end
			tween(button, { BackgroundColor3 = CONFIG.colorButtonHover }, 0.1)
		end))
		track(button.MouseLeave:Connect(function()
			if button == noclipButton then
				paintNoclip()
			elseif button == moveButton then
				paintDragMode()
			else
				tween(button, { BackgroundColor3 = baseColour }, 0.1)
			end
		end))
	end

	bindHover(moveButton, CONFIG.colorButton)
	bindHover(circleButton, CONFIG.colorButton)
	bindHover(closeButton, CONFIG.colorButton)
end

--====================================================================
-- 12 · PUBLIC API
--====================================================================

local api = {}

function api.toggle()
	setNoclip(not state.noclip)
end

function api.on()
	setNoclip(true)
end

function api.off()
	setNoclip(false)
end

function api.circle()
	applyMode("circle")
end

function api.collapse()
	applyMode("collapsed")
end

function api.expand()
	applyMode("normal")
end

function api.destroy()
	if state.destroyed then
		return
	end
	state.destroyed = true
	state.noclip = false
	stopEngine()
	for _, connection in ipairs(connections) do
		connection:Disconnect()
	end
	table.clear(connections)
	if gui then
		gui:Destroy()
	end
	getgenv().NoClip = nil
end

--====================================================================
-- 13 · BOOT
--====================================================================

local function boot()
	local existing = nil
	pcall(function()
		existing = guiParent():FindFirstChild(CONFIG.guiName)
	end)
	if existing and existing:FindFirstChild("Panel") then
		existing:Destroy()
	end

	buildGui()
	paintNoclip()
	paintDragMode()
	wire()

	getgenv().NoClip = api

	-- clean up if the game re-parents or kills the gui
	track(LocalPlayer.CharacterAdded:Connect(function(character)
		if not state.noclip then
			return
		end
		character:WaitForChild("HumanoidRootPart", 10)
		task.wait(0.4)
		if state.noclip then
			startEngine()
		end
	end))
end

boot()
--[[
════════════════════════════════════════════════════════════
   N O C L I P   ·   h a r d   m o d e
   ------------------------------------------------------------
   file    : noclip.lua
   author  : supercaptain1233
   target  : Delta (Android) · universal · any Roblox game
   version : 2.0.0
   ------------------------------------------------------------
   panel   : Noclip header, X collapse, move toggle, circle dot
   noclip  : ghost parts, revert collision restamps, shove the
             body through geometry, freeze inside walls, rewind
             position corrections, keep the floor with a hover
   ------------------------------------------------------------
   no print() calls in this file
   ════════════════════════════════════════════════════════════
]]


--============================================================
-- 01 · CONFIG
--============================================================

local CONFIG = {
    -- panel geometry
    panelWidth        = 190,
    panelHeight       = 148,
    panelX            = 24,
    panelY            = 88,
    cornerRadius      = 10,
    -- header
    headerHeight      = 30,
    title             = "Noclip",
    titleSize         = 13,
    headerButtonSize  = 24,
    headerGap         = 4,
    -- body
    bodyPadding       = 12,
    noclipHeight      = 54,
    noclipLabel       = "NOCLIP",
    noclipLabelActive = "NOCLIP: ON",
    noclipTextSize    = 15,
    -- compact dot
    dotCircleSize     = 46,
    dotCollapsedSize  = 30,
    dotLetter         = "N",
    -- colours
    colorPanel        = Color3.fromRGB(19, 22, 28),
    colorHeader       = Color3.fromRGB(28, 32, 40),
    colorBody         = Color3.fromRGB(15, 17, 22),
    colorButton       = Color3.fromRGB(44, 49, 60),
    colorButtonHover  = Color3.fromRGB(60, 67, 82),
    colorActive       = Color3.fromRGB(64, 110, 74),
    colorOff          = Color3.fromRGB(224, 49, 49),
    colorOn           = Color3.fromRGB(45, 168, 88),
    colorText         = Color3.fromRGB(235, 238, 243),
    colorMuted        = Color3.fromRGB(120, 128, 140),
    colorStroke       = Color3.fromRGB(52, 58, 70),
    -- engine
    hoverHeight       = 0.25,
    stickRange        = 14,
    stickStiffness    = 14,
    maxStickSpeed     = 55,
    ghostRefreshRate  = 10,
    ghostBurstFrames  = 40,
    penetrationSpeed  = 26,
    penetrationPush   = 1.4,
    freezeFrames      = 6,
    freezeCooldown    = 0.35,
    guardDistance     = 3.5,
    guardMaxPerSecond = 6,
    probeSize         = 1.6,
    -- drag
    tapThreshold      = 8,
    screenPadding     = 4,
    -- misc
    displayOrder      = 9999,
    guiName           = "NoClipUI",
    tweenTime         = 0.16,
}

--============================================================
-- 02 · SERVICES
--============================================================

local Players          = game:GetService("Players")
local RunService       = game:GetService("RunService")
local TweenService     = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local CoreGui          = game:GetService("CoreGui")
local Workspace        = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer
if not LocalPlayer then
    Players:GetPropertyChangedSignal("LocalPlayer"):Wait()
    LocalPlayer = Players.LocalPlayer
end

--============================================================
-- 03 · UTILITIES
--============================================================

local function new(class, props, children)
    local inst = Instance.new(class)
    local parent = props and props.Parent
    if props then
        for key, value in pairs(props) do
            if key ~= "Parent" then
                inst[key] = value
            end
        end
    end
    for _, child in ipairs(children or {}) do
        child.Parent = inst
    end
    if parent then
        inst.Parent = parent
    end
    return inst
end

local function round(inst, radius)
    new("UICorner", { CornerRadius = UDim.new(0, radius or 8), Parent = inst })
    return inst
end

local function stroke(inst, colour, thickness, transparency)
    new("UIStroke", {
        Color = colour or CONFIG.colorStroke,
        Thickness = thickness or 1,
        Transparency = transparency or 0,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
        Parent = inst,
    })
    return inst
end

local function pad(inst, top, right, bottom, left)
    new("UIPadding", {
        PaddingTop = UDim.new(0, top or 0),
        PaddingRight = UDim.new(0, right or 0),
        PaddingBottom = UDim.new(0, bottom or 0),
        PaddingLeft = UDim.new(0, left or 0),
        Parent = inst,
    })
    return inst
end

local function tween(inst, props, time)
    local info = TweenInfo.new(time or CONFIG.tweenTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
    local anim = TweenService:Create(inst, info, props)
    anim:Play()
    return anim
end

local function viewport()
    local camera = Workspace.CurrentCamera
    return camera and camera.ViewportSize or Vector2.new(1080, 1920)
end

local function clampToScreen(x, y, width, height)
    local vp = viewport()
    local padPx = CONFIG.screenPadding
    local maxX = math.max(padPx, vp.X - width - padPx)
    local maxY = math.max(padPx, vp.Y - height - padPx)
    return math.clamp(x, padPx, maxX), math.clamp(y, padPx, maxY)
end

local function guiParent()
    local ok, hidden = pcall(function()
        return gethui and gethui() or nil
    end)
    if ok and hidden then
        return hidden
    end
    local okCore = pcall(function()
        return CoreGui
    end)
    if okCore and CoreGui then
        return CoreGui
    end
    return LocalPlayer:WaitForChild("PlayerGui")
end

local function flatLook(cframe)
    local look = cframe.LookVector
    local flat = Vector3.new(look.X, 0, look.Z)
    if flat.Magnitude < 0.01 then
        return Vector3.new(0, 0, -1)
    end
    return flat.Unit
end

--============================================================
-- 04 · STATE
--============================================================

local state = {
    mode        = "normal",
    dragMode    = false,
    noclip      = false,
    destroyed   = false,
    freezeUntil = 0,
}

local panel, dot, dotGlyph, dotLetter
local noclipButton, noclipLabel, statusLabel
local moveButton, moveButtonStroke
local circleButton, circleButtonStroke
local closeButton
local gui

local connections = {}
local function track(connection)
    connections[#connections + 1] = connection
    return connection
end

--============================================================
-- 05 · ICONS
--============================================================

local function buildMoveIcon(parent)
    local wrap = new("Frame", {
        Name = "MoveIcon",
        Size = UDim2.fromOffset(16, 16),
        Position = UDim2.fromScale(0.5, 0.5),
        AnchorPoint = Vector2.new(0.5, 0.5),
        BackgroundTransparency = 1,
        Parent = parent,
    })
    local glyphs = {
        { text = "\u{2191}", x = 0, y = 0 },
        { text = "\u{2190}", x = 0, y = 5.5 },
        { text = "\u{2192}", x = 8, y = 5.5 },
        { text = "\u{2193}", x = 0, y = 11 },
    }
    for _, glyph in ipairs(glyphs) do
        new("TextLabel", {
            Size = UDim2.fromOffset(8, 5),
            Position = UDim2.fromOffset(glyph.x, glyph.y),
            BackgroundTransparency = 1,
            Text = glyph.text,
            TextSize = 8,
            Font = Enum.Font.GothamBold,
            TextColor3 = CONFIG.colorText,
            Parent = wrap,
        })
    end
end

local function buildCircleIcon(parent)
    local wrap = new("Frame", {
        Name = "CircleIcon",
        Size = UDim2.fromOffset(16, 16),
        Position = UDim2.fromScale(0.5, 0.5),
        AnchorPoint = Vector2.new(0.5, 0.5),
        BackgroundTransparency = 1,
        Parent = parent,
    })
    local ring = new("Frame", {
        Name = "Ring",
        Size = UDim2.fromOffset(12, 12),
        Position = UDim2.fromScale(0.5, 0.5),
        AnchorPoint = Vector2.new(0.5, 0.5),
        BackgroundTransparency = 1,
        Parent = wrap,
    })
    round(ring, 12)
    stroke(ring, CONFIG.colorText, 1.4, 0)
    local centre = new("Frame", {
        Name = "Centre",
        Size = UDim2.fromOffset(4, 4),
        Position = UDim2.fromScale(0.5, 0.5),
        AnchorPoint = Vector2.new(0.5, 0.5),
        BackgroundColor3 = CONFIG.colorText,
        BorderSizePixel = 0,
        Parent = wrap,
    })
    round(centre, 4)
end

--============================================================
-- 06 · GUI
--============================================================

local function buildGui()
    gui = new("ScreenGui", {
        Name = CONFIG.guiName, ResetOnSpawn = false, IgnoreGuiInset = true,
        ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
        DisplayOrder = CONFIG.displayOrder, Parent = guiParent(),
    })
    panel = new("Frame", {
        Name = "Panel", Parent = gui, ClipsDescendants = true,
        Size = UDim2.fromOffset(CONFIG.panelWidth, CONFIG.panelHeight),
        Position = UDim2.fromOffset(CONFIG.panelX, CONFIG.panelY),
        BackgroundColor3 = CONFIG.colorPanel, BorderSizePixel = 0,
    })
    round(panel, CONFIG.cornerRadius)
    stroke(panel, CONFIG.colorStroke, 1, 0.25)

    local header = new("Frame", {
        Name = "Header", Parent = panel, BorderSizePixel = 0,
        Size = UDim2.new(1, 0, 0, CONFIG.headerHeight),
        BackgroundColor3 = CONFIG.colorHeader,
    })
    new("TextLabel", {
        Name = "Title", Parent = header, BackgroundTransparency = 1,
        Size = UDim2.new(1, -104, 1, 0), Position = UDim2.fromOffset(10, 0),
        Text = CONFIG.title, TextSize = CONFIG.titleSize,
        Font = Enum.Font.GothamBold, TextColor3 = CONFIG.colorText,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Center,
    })

    local buttonRow = new("Frame", {
        Name = "Buttons", Parent = header, BackgroundTransparency = 1,
        Size = UDim2.new(0, 80, 1, 0), Position = UDim2.new(1, -6, 0, 0),
        AnchorPoint = Vector2.new(1, 0),
    })
    new("UIListLayout", {
        Parent = buttonRow, FillDirection = Enum.FillDirection.Horizontal,
        HorizontalAlignment = Enum.HorizontalAlignment.Right,
        VerticalAlignment = Enum.VerticalAlignment.Center,
        Padding = UDim.new(0, CONFIG.headerGap),
        SortOrder = Enum.SortOrder.LayoutOrder,
    })

    circleButton = new("TextButton", {
        Name = "CircleButton", Parent = buttonRow, LayoutOrder = 1, Text = "",
        Size = UDim2.fromOffset(CONFIG.headerButtonSize, CONFIG.headerButtonSize),
        BackgroundColor3 = CONFIG.colorButton, BorderSizePixel = 0,
        AutoButtonColor = false,
    })
    round(circleButton, 6)
    circleButtonStroke = stroke(circleButton, CONFIG.colorStroke, 1, 0.4)
    buildCircleIcon(circleButton)

    moveButton = new("TextButton", {
        Name = "MoveButton", Parent = buttonRow, LayoutOrder = 2, Text = "",
        Size = UDim2.fromOffset(CONFIG.headerButtonSize, CONFIG.headerButtonSize),
        BackgroundColor3 = CONFIG.colorButton, BorderSizePixel = 0,
        AutoButtonColor = false,
    })
    round(moveButton, 6)
    moveButtonStroke = stroke(moveButton, CONFIG.colorStroke, 1, 0.4)
    buildMoveIcon(moveButton)

    closeButton = new("TextButton", {
        Name = "CloseButton", Parent = buttonRow, LayoutOrder = 3,
        Size = UDim2.fromOffset(CONFIG.headerButtonSize, CONFIG.headerButtonSize),
        BackgroundColor3 = CONFIG.colorButton, BorderSizePixel = 0,
        Text = "\u{2715}", TextSize = 12, Font = Enum.Font.GothamBold,
        TextColor3 = CONFIG.colorText, AutoButtonColor = false,
    })
    round(closeButton, 6)
    stroke(closeButton, CONFIG.colorStroke, 1, 0.4)

    local body = new("Frame", {
        Name = "Body", Parent = panel, BorderSizePixel = 0,
        Size = UDim2.new(1, 0, 1, -CONFIG.headerHeight),
        Position = UDim2.fromOffset(0, CONFIG.headerHeight),
        BackgroundColor3 = CONFIG.colorBody,
    })
    pad(body, CONFIG.bodyPadding, CONFIG.bodyPadding, 8, CONFIG.bodyPadding)
    new("UIListLayout", {
        Parent = body, FillDirection = Enum.FillDirection.Vertical,
        HorizontalAlignment = Enum.HorizontalAlignment.Center,
        VerticalAlignment = Enum.VerticalAlignment.Center,
        Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder,
    })

    noclipButton = new("TextButton", {
        Name = "NoclipButton", Parent = body, LayoutOrder = 1, Text = "",
        Size = UDim2.new(1, 0, 0, CONFIG.noclipHeight),
        BackgroundColor3 = CONFIG.colorOff, BorderSizePixel = 0,
        AutoButtonColor = false,
    })
    round(noclipButton, 8)
    stroke(noclipButton, Color3.fromRGB(255, 255, 255), 1, 0.75)
    noclipLabel = new("TextLabel", {
        Name = "Label", Parent = noclipButton, BackgroundTransparency = 1,
        Size = UDim2.fromScale(1, 1), Text = CONFIG.noclipLabel,
        TextSize = CONFIG.noclipTextSize, Font = Enum.Font.GothamBold,
        TextColor3 = Color3.fromRGB(255, 255, 255),
    })

    statusLabel = new("TextLabel", {
        Name = "Status", Parent = body, LayoutOrder = 2,
        Size = UDim2.new(1, 0, 0, 14), BackgroundTransparency = 1,
        Text = "idle", TextSize = 11, Font = Enum.Font.Gotham,
        TextColor3 = CONFIG.colorMuted,
        TextXAlignment = Enum.TextXAlignment.Center,
    })

    dot = new("TextButton", {
        Name = "Dot", Parent = gui, Visible = false, Text = "",
        Size = UDim2.fromOffset(CONFIG.dotCircleSize, CONFIG.dotCircleSize),
        Position = UDim2.fromOffset(CONFIG.panelX, CONFIG.panelY),
        BackgroundColor3 = CONFIG.colorPanel, BorderSizePixel = 0,
        AutoButtonColor = false,
    })
    round(dot, 1)
    stroke(dot, CONFIG.colorStroke, 1, 0.2)
    dotGlyph = new("Frame", {
        Name = "Glyph", Parent = dot, BackgroundTransparency = 1,
        Size = UDim2.fromScale(1, 1),
    })
    buildCircleIcon(dotGlyph)
    dotLetter = new("TextLabel", {
        Name = "Letter", Parent = dot, BackgroundTransparency = 1,
        Size = UDim2.fromScale(1, 1), Text = CONFIG.dotLetter, TextSize = 13,
        Font = Enum.Font.GothamBold, TextColor3 = CONFIG.colorText,
        Visible = false,
    })
end

--============================================================
-- 07 · MODES
--============================================================

local function applyMode(mode)
    state.mode = mode
    if mode == "normal" then
        dot.Visible = false
        panel.Visible = true
        panel.Position = dot.Position
        local x, y = clampToScreen(panel.Position.X.Offset, panel.Position.Y.Offset,
            panel.AbsoluteSize.X, panel.AbsoluteSize.Y)
        panel.Position = UDim2.fromOffset(x, y)
        return
    end
    local size = (mode == "circle") and CONFIG.dotCircleSize or CONFIG.dotCollapsedSize
    dot.Size = UDim2.fromOffset(size, size)
    dotGlyph.Visible = (mode == "circle")
    dotLetter.Visible = (mode == "collapsed")
    local x, y = clampToScreen(panel.Position.X.Offset, panel.Position.Y.Offset, size, size)
    dot.Position = UDim2.fromOffset(x, y)
    panel.Visible = false
    dot.Visible = true
end

local function toggleMode(mode)
    if state.mode == mode then
        applyMode("normal")
    else
        applyMode(mode)
    end
end

--============================================================
-- 08 · DRAG
--============================================================

local function attachDrag(handle, target, options)
    options = options or {}
    track(handle.InputBegan:Connect(function(input)
        if input.UserInputType ~= Enum.UserInputType.MouseButton1
            and input.UserInputType ~= Enum.UserInputType.Touch then
            return
        end
        if options.condition and not options.condition() then
            return
        end
        local origin = input.Position
        local startPos = target.Position
        local moved = 0
        local watcher
        watcher = input.Changed:Connect(function()
            local delta = input.Position - origin
            moved = math.max(moved, delta.Magnitude)
            local x = startPos.X.Offset + delta.X
            local y = startPos.Y.Offset + delta.Y
            x, y = clampToScreen(x, y, target.AbsoluteSize.X, target.AbsoluteSize.Y)
            target.Position = UDim2.fromOffset(x, y)
        end)
        input.Ended:Connect(function()
            if watcher then
                watcher:Disconnect()
                watcher = nil
            end
            if options.onEnd then
                options.onEnd(moved)
            end
        end)
    end))
end

--============================================================
-- 09 · ENGINE STATE
--============================================================

local ghosted      = {}
local ghostHooks   = {}
local engineConns  = {}
local heartbeat
local frameClock   = 0
local lastPosition = nil
local guardClock   = 0
local guardCount   = 0
local freezeClock  = 0
local lastHumanoid = nil

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.IgnoreWater = true
rayParams.RespectCanCollide = false

local probeParams = OverlapParams.new()
probeParams.FilterType = Enum.RaycastFilterType.Exclude
probeParams.RespectCanCollide = false

local DISABLED_STATES = {
    Enum.HumanoidStateType.FallingDown,
    Enum.HumanoidStateType.Ragdoll,
    Enum.HumanoidStateType.GettingUp,
    Enum.HumanoidStateType.StrafingNoPhysics,
    Enum.HumanoidStateType.PlatformStanding,
}

--============================================================
-- 10 · GHOSTING
--============================================================

-- store the original value once, then hold the part ghosted even
-- when the game stamps CanCollide back on
local function ghostPart(part)
    if not part:IsA("BasePart") then
        return
    end
    if ghosted[part] == nil then
        ghosted[part] = part.CanCollide
    end
    if part.CanCollide then
        part.CanCollide = false
    end
    if not ghostHooks[part] then
        ghostHooks[part] = part:GetPropertyChangedSignal("CanCollide"):Connect(function()
            if state.noclip and part.CanCollide then
                part.CanCollide = false
            end
        end)
    end
end

local function ghostCharacter(character)
    for _, descendant in ipairs(character:GetDescendants()) do
        ghostPart(descendant)
    end
end

local function clearGhostHooks()
    for part, connection in pairs(ghostHooks) do
        connection:Disconnect()
        ghostHooks[part] = nil
    end
end

local function restoreCharacter()
    clearGhostHooks()
    for part, value in pairs(ghosted) do
        if part and part.Parent then
            pcall(function()
                part.CanCollide = value
            end)
        end
    end
    table.clear(ghosted)
end

--============================================================
-- 11 · HUMANOID HARDENING
--============================================================

local function hardenHumanoid(humanoid)
    humanoid.RequiresNeck = false
    humanoid.BreakJointsOnDeath = false
    for _, humanoidState in ipairs(DISABLED_STATES) do
        pcall(function()
            humanoid:SetStateEnabled(humanoidState, false)
        end)
    end
end

local function relaxHumanoid(humanoid)
    for _, humanoidState in ipairs(DISABLED_STATES) do
        pcall(function()
            humanoid:SetStateEnabled(humanoidState, true)
        end)
    end
end

local function claimOwnership(root)
    pcall(function()
        root:SetNetworkOwner(LocalPlayer)
    end)
end

--============================================================
-- 12 · PENETRATION ASSIST
--============================================================

-- is the root sitting inside geometry?
local function isEmbedded(root)
    local size = Vector3.new(CONFIG.probeSize, CONFIG.probeSize, CONFIG.probeSize)
    local parts = Workspace:GetPartBoundsInBox(root.CFrame, size, probeParams)
    for _, part in ipairs(parts) do
        if part.CanCollide then
            return true
        end
    end
    return false
end

-- walk input first, camera look as fallback
local function shoveDirection(root)
    local humanoid = root.Parent and root.Parent:FindFirstChildOfClass("Humanoid")
    local move = humanoid and humanoid.MoveDirection or Vector3.zero
    if move.Magnitude > 0.05 then
        return Vector3.new(move.X, 0, move.Z).Unit
    end
    return flatLook(root.CFrame)
end

-- hold the body for a few frames so the physics step cannot bounce
-- it straight back out of the wall it just entered
local function freezeBody()
    local now = os.clock()
    if now < state.freezeUntil then
        return true
    end
    if now - freezeClock < CONFIG.freezeCooldown then
        return false
    end
    state.freezeUntil = now + (CONFIG.freezeFrames / 60)
    freezeClock = now
    return true
end

--============================================================
-- 13 · TELEPORT GUARD
--============================================================

-- games that notice a body inside a wall try to snap it back to the
-- last known good spot. this rewinds corrections but leaves real
-- forward progress and real teleports alone
local function guardPosition(root, direction)
    local now = os.clock()
    if now - guardClock > 1 then
        guardCount = 0
    end
    local current = root.Position
    if not lastPosition then
        lastPosition = current
        return
    end
    local delta = current - lastPosition
    local flat = Vector3.new(delta.X, 0, delta.Z)
    if flat.Magnitude < CONFIG.guardDistance then
        lastPosition = current
        return
    end
    if flat.Unit:Dot(direction) > -0.2 or guardCount >= CONFIG.guardMaxPerSecond then
        lastPosition = current
        return
    end
    guardCount += 1
    local keep = root.CFrame - root.Position
    root.CFrame = CFrame.new(lastPosition) * keep
    root.AssemblyLinearVelocity = Vector3.zero
end

--============================================================
-- 14 · FLOOR HOVER
--============================================================

-- keeps the body standing on the floor while every part is ghosted
local function hoverStep(root, humanoid, velocity)
    local hip = humanoid.HipHeight or 0
    local offset = (root.Size.Y * 0.5) + hip + CONFIG.hoverHeight
    local reach = CONFIG.stickRange + offset
    local result = Workspace:Raycast(root.Position, Vector3.new(0, -reach, 0), rayParams)
    if not result then
        return false
    end
    local difference = (result.Position.Y + offset) - root.Position.Y
    if math.abs(difference) < 0.02 then
        root.AssemblyLinearVelocity = Vector3.new(velocity.X, 0, velocity.Z)
    else
        local correction = math.clamp(difference * CONFIG.stickStiffness,
            -CONFIG.maxStickSpeed, CONFIG.maxStickSpeed)
        root.AssemblyLinearVelocity = Vector3.new(velocity.X, correction, velocity.Z)
    end
    return true
end

--============================================================
-- 15 · HEARTBEAT
--============================================================

local function onHeartbeat()
    if not state.noclip then
        return
    end
    local character = LocalPlayer.Character
    if not character or not character.Parent then
        return
    end
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    local root = character:FindFirstChild("HumanoidRootPart")
    if not humanoid or not root or root.Parent ~= character then
        return
    end

    frameClock += 1
    if frameClock <= CONFIG.ghostBurstFrames
        or frameClock % CONFIG.ghostRefreshRate == 0 then
        ghostCharacter(character)
    end

    rayParams.FilterDescendantsInstances = { character }
    probeParams.FilterDescendantsInstances = { character }

    local okState, humanoidState = pcall(function()
        return humanoid:GetState()
    end)
    if not okState then
        humanoidState = nil
    end

    local velocity = root.AssemblyLinearVelocity
    local direction = shoveDirection(root)
    guardPosition(root, direction)

    if humanoidState == Enum.HumanoidStateType.Swimming
        or humanoidState == Enum.HumanoidStateType.Climbing then
        return
    end

    if humanoidState == Enum.HumanoidStateType.Jumping or velocity.Y > 2 then
        return
    end

    local grounded = hoverStep(root, humanoid, velocity)

    -- shove through anything the body is sitting inside of
    if isEmbedded(root) then
        local speed = CONFIG.penetrationSpeed
        if freezeBody() then
            root.AssemblyLinearVelocity = direction * speed
        else
            root.AssemblyLinearVelocity = direction * (speed * CONFIG.penetrationPush)
        end
        pcall(function()
            humanoid:ChangeState(Enum.HumanoidStateType.Running)
        end)
        return
    end

    if grounded and humanoidState == Enum.HumanoidStateType.Freefall then
        pcall(function()
            humanoid:ChangeState(Enum.HumanoidStateType.Running)
        end)
    end
end

--============================================================
-- 16 · LIFECYCLE
--============================================================

local function stopEngine()
    for _, connection in ipairs(engineConns) do
        connection:Disconnect()
    end
    table.clear(engineConns)
    if heartbeat then
        heartbeat:Disconnect()
        heartbeat = nil
    end
    if lastHumanoid then
        relaxHumanoid(lastHumanoid)
        lastHumanoid = nil
    end
    lastPosition = nil
    restoreCharacter()
end

local function startEngine()
    local character = LocalPlayer.Character
    if not character then
        return false
    end
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    local root = character:FindFirstChild("HumanoidRootPart")
    if not humanoid or not root then
        return false
    end
    table.clear(ghosted)
    ghostCharacter(character)
    hardenHumanoid(humanoid)
    claimOwnership(root)
    lastHumanoid = humanoid
    engineConns[#engineConns + 1] = character.DescendantAdded:Connect(ghostPart)
    engineConns[#engineConns + 1] = humanoid.Died:Connect(function()
        stopEngine()
        if state.noclip then
            LocalPlayer:WaitForChild("Character", 10)
            task.wait(0.4)
            if state.noclip then
                startEngine()
            end
        end
    end)
    heartbeat = RunService.Heartbeat:Connect(onHeartbeat)
    return true
end

--============================================================
-- 17 · PAINT
--============================================================

local function paintNoclip()
    if state.noclip then
        noclipButton.BackgroundColor3 = CONFIG.colorOn
        noclipLabel.Text = CONFIG.noclipLabelActive
        statusLabel.Text = "active"
        statusLabel.TextColor3 = CONFIG.colorOn
    else
        noclipButton.BackgroundColor3 = CONFIG.colorOff
        noclipLabel.Text = CONFIG.noclipLabel
        statusLabel.Text = "idle"
        statusLabel.TextColor3 = CONFIG.colorMuted
    end
end

local function paintDragMode()
    moveButton.BackgroundColor3 = state.dragMode and CONFIG.colorActive or CONFIG.colorButton
    if moveButtonStroke then
        moveButtonStroke.Transparency = state.dragMode and 0 or 0.4
    end
end

local function setNoclip(enabled)
    if state.noclip == enabled then
        return
    end
    if enabled then
        if startEngine() then
            state.noclip = true
        end
    else
        state.noclip = false
        stopEngine()
    end
    paintNoclip()
end

--============================================================
-- 18 · WIRING
--============================================================

local function wire()
    track(noclipButton.Activated:Connect(function()
        setNoclip(not state.noclip)
    end))
    track(moveButton.Activated:Connect(function()
        state.dragMode = not state.dragMode
        paintDragMode()
    end))
    track(circleButton.Activated:Connect(function()
        toggleMode("circle")
    end))
    track(closeButton.Activated:Connect(function()
        toggleMode("collapsed")
    end))

    attachDrag(panel, panel, {
        condition = function()
            local mouse = UserInputService:GetMouseLocation()
            return mouse.Y <= panel.AbsolutePosition.Y + CONFIG.headerHeight
        end,
    })
    attachDrag(panel, panel, {
        condition = function()
            return state.dragMode
        end,
    })
    attachDrag(dot, dot, {
        onEnd = function(moved)
            if moved < CONFIG.tapThreshold then
                applyMode("normal")
            end
        end,
    })

    track(Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
        local camera = Workspace.CurrentCamera
        if not camera then
            return
        end
        track(camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
            local target = (state.mode == "normal") and panel or dot
            local x, y = clampToScreen(target.Position.X.Offset, target.Position.Y.Offset,
                target.AbsoluteSize.X, target.AbsoluteSize.Y)
            target.Position = UDim2.fromOffset(x, y)
        end))
    end))
end

--============================================================
-- 19 · PUBLIC API
--============================================================

local api = {}
api.toggle = function()
    setNoclip(not state.noclip)
end
api.on = function()
    setNoclip(true)
end
api.off = function()
    setNoclip(false)
end
api.circle = function()
    applyMode("circle")
end
api.collapse = function()
    applyMode("collapsed")
end
api.expand = function()
    applyMode("normal")
end
api.destroy = function()
    if state.destroyed then
        return
    end
    state.destroyed = true
    state.noclip = false
    stopEngine()
    for _, connection in ipairs(connections) do
        connection:Disconnect()
    end
    table.clear(connections)
    if gui then
        gui:Destroy()
    end
    getgenv().NoClip = nil
end

--============================================================
-- 20 · BOOT
--============================================================

local function boot()
    local existing = guiParent():FindFirstChild(CONFIG.guiName)
    if existing then
        existing:Destroy()
    end
    buildGui()
    paintNoclip()
    paintDragMode()
    wire()
    getgenv().NoClip = api
    track(LocalPlayer.CharacterAdded:Connect(function(character)
        if not state.noclip then
            return
        end
        character:WaitForChild("HumanoidRootPart", 10)
        task.wait(0.4)
        if state.noclip then
            startEngine()
        end
    end))
end

boot()

--============================================================
-- 21 · NOTES
--============================================================
-- how the hard mode works, step by step:
--
--   1. every BasePart is ghosted and watched, so a game that
--      stamps collisions back on gets reverted same frame.
--   2. the humanoid is hardened: ragdoll, falling down, getting
--      up and platform standing are turned off so the body never
--      collapses inside geometry.
--   3. network ownership of the root is claimed by the client so
--      the server cannot drag the assembly back.
--   4. a 1.6 stud overlap probe runs every frame; anything the
--      body sits inside of gets it shoved along the walk vector
--      at fixed speed, so it leaves the wall instead of resting.
--   5. the first trip freezes the body for six frames at shove
--      speed so physics cannot bounce it back out.
--   6. the teleport guard rewinds backwards corrections over
--      3.5 studs, capped at six a second.
--   7. a downward raycast keeps the feet on the floor, so walls
--      are ignored but the ground is not.
--   8. turning noclip off restores every CanCollide value and
--      re-enables the disabled humanoid states.
--
-- end of file
--[[
════════════════════════════════════════════════════════
   N O C L I P   ·   h a r d   m o d e   3
   ------------------------------------------------------------
   file    : noclip.lua
   author  : supercaptain1233
   target  : Delta (Android) · universal · any Roblox game
   version : 3.0.0
   ------------------------------------------------------------
   panel   : Noclip header, X collapse, move toggle, circle dot
   noclip  : double collision layer, measured wall exit, forced
             CFrame pass, freeze hold, position history guard,
             fall clamp, stuck breaker, floor hover
   ------------------------------------------------------------
   no print() calls in this file
   ════════════════════════════════════════════════════════════
]]


--============================================================
-- 01 · CONFIG
--============================================================

local CONFIG = {
    panelWidth = 190, panelHeight = 148, panelX = 24, panelY = 88,
    cornerRadius = 10, headerHeight = 30, headerGap = 4,
    title = "Noclip", titleSize = 13, headerButtonSize = 24,
    bodyPadding = 12, noclipHeight = 54, noclipTextSize = 15,
    noclipLabel = "NOCLIP", noclipLabelActive = "NOCLIP: ON",
    dotCircleSize = 46, dotCollapsedSize = 30, dotLetter = "N",
    colorPanel = Color3.fromRGB(19, 22, 28),
    colorHeader = Color3.fromRGB(28, 32, 40),
    colorBody = Color3.fromRGB(15, 17, 22),
    colorButton = Color3.fromRGB(44, 49, 60),
    colorButtonHover = Color3.fromRGB(60, 67, 82),
    colorActive = Color3.fromRGB(64, 110, 74),
    colorOff = Color3.fromRGB(224, 49, 49),
    colorOn = Color3.fromRGB(45, 168, 88),
    colorText = Color3.fromRGB(235, 238, 243),
    colorMuted = Color3.fromRGB(120, 128, 140),
    colorStroke = Color3.fromRGB(52, 58, 70),
    hoverHeight = 0.25, stickRange = 16, stickStiffness = 14,
    maxStickSpeed = 55, ghostGroup = "NoClipGhost",
    ghostRefreshRate = 6, ghostBurstFrames = 45,
    probeSize = 1.4, shoveStep = 0.6, shoveLimit = 14,
    shoveSpeed = 30, shoveClearance = 1.2, shoveMaxFrames = 48,
    shoveCooldown = 0.2, freezeFrames = 5, freezeCooldown = 0.3,
    guardDistance = 3.5, guardHistory = 14, guardMaxPerSecond = 8,
    fallProbe = 60, fallMargin = 3, stuckFrames = 9, stuckEpsilon = 0.35,
    tapThreshold = 8, screenPadding = 4,
    displayOrder = 9999, guiName = "NoClipUI", tweenTime = 0.16,
}

--============================================================
-- 02 · SERVICES
--============================================================

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local PhysicsService = game:GetService("PhysicsService")
local Workspace = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer
if not LocalPlayer then
    Players:GetPropertyChangedSignal("LocalPlayer"):Wait()
    LocalPlayer = Players.LocalPlayer
end

--============================================================
-- 03 · UTILITIES
--============================================================

local function new(class, props, children)
    local inst = Instance.new(class)
    local parent = props and props.Parent
    if props then
        for key, value in pairs(props) do
            if key ~= "Parent" then
                inst[key] = value
            end
        end
    end
    for _, child in ipairs(children or {}) do
        child.Parent = inst
    end
    if parent then
        inst.Parent = parent
    end
    return inst
end

local function round(inst, radius)
    new("UICorner", { CornerRadius = UDim.new(0, radius or 8), Parent = inst })
    return inst
end

local function stroke(inst, colour, thickness, transparency)
    new("UIStroke", {
        Color = colour or CONFIG.colorStroke, Thickness = thickness or 1,
        Transparency = transparency or 0,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = inst,
    })
    return inst
end

local function viewport()
    local camera = Workspace.CurrentCamera
    return camera and camera.ViewportSize or Vector2.new(1080, 1920)
end

local function clampToScreen(x, y, width, height)
    local vp = viewport()
    local edge = CONFIG.screenPadding
    return math.clamp(x, edge, math.max(edge, vp.X - width - edge)),
        math.clamp(y, edge, math.max(edge, vp.Y - height - edge))
end

local function guiParent()
    local ok, hidden = pcall(function()
        return gethui and gethui() or nil
    end)
    if ok and hidden then
        return hidden
    end
    return LocalPlayer:WaitForChild("PlayerGui")
end

local function horizontal(vector)
    return Vector3.new(vector.X, 0, vector.Z)
end

local function flatLook(cframe)
    local flat = horizontal(cframe.LookVector)
    if flat.Magnitude < 0.01 then
        return Vector3.new(0, 0, -1)
    end
    return flat.Unit
end

--============================================================
-- 04 · STATE
--============================================================

local state = { mode = "normal", dragMode = false, noclip = false, destroyed = false }

local panel, dot, dotGlyph, dotLetter
local noclipButton, noclipLabel, statusLabel
local moveButton, moveButtonStroke, circleButton, circleButtonStroke
local closeButton, gui

local connections = {}
local function track(connection)
    connections[#connections + 1] = connection
    return connection
end

--============================================================
-- 05 · ICONS
--============================================================

local function buildMoveIcon(parent)
    local wrap = new("Frame", {
        Name = "MoveIcon", Parent = parent, BackgroundTransparency = 1,
        Size = UDim2.fromOffset(16, 16), Position = UDim2.fromScale(0.5, 0.5),
        AnchorPoint = Vector2.new(0.5, 0.5),
    })
    local glyphs = {
        { text = "\u{2191}", x = 0, y = 0 }, { text = "\u{2190}", x = 0, y = 5.5 },
        { text = "\u{2192}", x = 8, y = 5.5 }, { text = "\u{2193}", x = 0, y = 11 },
    }
    for _, glyph in ipairs(glyphs) do
        new("TextLabel", {
            Parent = wrap, BackgroundTransparency = 1, Text = glyph.text,
            Size = UDim2.fromOffset(8, 5), Position = UDim2.fromOffset(glyph.x, glyph.y),
            TextSize = 8, Font = Enum.Font.GothamBold, TextColor3 = CONFIG.colorText,
        })
    end
end

local function buildCircleIcon(parent)
    local wrap = new("Frame", {
        Name = "CircleIcon", Parent = parent, BackgroundTransparency = 1,
        Size = UDim2.fromOffset(16, 16), Position = UDim2.fromScale(0.5, 0.5),
        AnchorPoint = Vector2.new(0.5, 0.5),
    })
    local ring = new("Frame", {
        Name = "Ring", Parent = wrap, BackgroundTransparency = 1,
        Size = UDim2.fromOffset(12, 12), Position = UDim2.fromScale(0.5, 0.5),
        AnchorPoint = Vector2.new(0.5, 0.5),
    })
    round(ring, 12)
    stroke(ring, CONFIG.colorText, 1.4, 0)
    local centre = new("Frame", {
        Name = "Centre", Parent = wrap, BackgroundColor3 = CONFIG.colorText,
        Size = UDim2.fromOffset(4, 4), Position = UDim2.fromScale(0.5, 0.5),
        AnchorPoint = Vector2.new(0.5, 0.5), BorderSizePixel = 0,
    })
    round(centre, 4)
end

--============================================================
-- 06 · GUI
--============================================================

local function buildGui()
    gui = new("ScreenGui", {
        Name = CONFIG.guiName, ResetOnSpawn = false, IgnoreGuiInset = true,
        ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
        DisplayOrder = CONFIG.displayOrder, Parent = guiParent(),
    })
    panel = new("Frame", {
        Name = "Panel", Parent = gui, ClipsDescendants = true,
        Size = UDim2.fromOffset(CONFIG.panelWidth, CONFIG.panelHeight),
        Position = UDim2.fromOffset(CONFIG.panelX, CONFIG.panelY),
        BackgroundColor3 = CONFIG.colorPanel, BorderSizePixel = 0,
    })
    round(panel, CONFIG.cornerRadius)
    stroke(panel, CONFIG.colorStroke, 1, 0.25)
    local header = new("Frame", {
        Name = "Header", Parent = panel, BorderSizePixel = 0,
        Size = UDim2.new(1, 0, 0, CONFIG.headerHeight),
        BackgroundColor3 = CONFIG.colorHeader,
    })
    new("TextLabel", {
        Name = "Title", Parent = header, BackgroundTransparency = 1,
        Size = UDim2.new(1, -104, 1, 0), Position = UDim2.fromOffset(10, 0),
        Text = CONFIG.title, TextSize = CONFIG.titleSize,
        Font = Enum.Font.GothamBold, TextColor3 = CONFIG.colorText,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Center,
    })
    local row = new("Frame", {
        Name = "Buttons", Parent = header, BackgroundTransparency = 1,
        Size = UDim2.new(0, 80, 1, 0), Position = UDim2.new(1, -6, 0, 0),
        AnchorPoint = Vector2.new(1, 0),
    })
    new("UIListLayout", {
        Parent = row, FillDirection = Enum.FillDirection.Horizontal,
        HorizontalAlignment = Enum.HorizontalAlignment.Right,
        VerticalAlignment = Enum.VerticalAlignment.Center,
        Padding = UDim.new(0, CONFIG.headerGap), SortOrder = Enum.SortOrder.LayoutOrder,
    })
    circleButton = new("TextButton", {
        Name = "CircleButton", Parent = row, LayoutOrder = 1, Text = "",
        Size = UDim2.fromOffset(CONFIG.headerButtonSize, CONFIG.headerButtonSize),
        BackgroundColor3 = CONFIG.colorButton, BorderSizePixel = 0,
        AutoButtonColor = false,
    })
    round(circleButton, 6)
    circleButtonStroke = stroke(circleButton, CONFIG.colorStroke, 1, 0.4)
    buildCircleIcon(circleButton)
    moveButton = new("TextButton", {
        Name = "MoveButton", Parent = row, LayoutOrder = 2, Text = "",
        Size = UDim2.fromOffset(CONFIG.headerButtonSize, CONFIG.headerButtonSize),
        BackgroundColor3 = CONFIG.colorButton, BorderSizePixel = 0,
        AutoButtonColor = false,
    })
    round(moveButton, 6)
    moveButtonStroke = stroke(moveButton, CONFIG.colorStroke, 1, 0.4)
    buildMoveIcon(moveButton)
    closeButton = new("TextButton", {
        Name = "CloseButton", Parent = row, LayoutOrder = 3,
        Size = UDim2.fromOffset(CONFIG.headerButtonSize, CONFIG.headerButtonSize),
        BackgroundColor3 = CONFIG.colorButton, BorderSizePixel = 0,
        Text = "\u{2715}", TextSize = 12, Font = Enum.Font.GothamBold,
        TextColor3 = CONFIG.colorText, AutoButtonColor = false,
    })
    round(closeButton, 6)
    stroke(closeButton, CONFIG.colorStroke, 1, 0.4)
    local body = new("Frame", {
        Name = "Body", Parent = panel, BorderSizePixel = 0,
        Size = UDim2.new(1, 0, 1, -CONFIG.headerHeight),
        Position = UDim2.fromOffset(0, CONFIG.headerHeight),
        BackgroundColor3 = CONFIG.colorBody,
    })
    new("UIPadding", {
        Parent = body, PaddingTop = UDim.new(0, CONFIG.bodyPadding),
        PaddingLeft = UDim.new(0, CONFIG.bodyPadding),
        PaddingRight = UDim.new(0, CONFIG.bodyPadding), PaddingBottom = UDim.new(0, 8),
    })
    new("UIListLayout", {
        Parent = body, FillDirection = Enum.FillDirection.Vertical,
        HorizontalAlignment = Enum.HorizontalAlignment.Center,
        VerticalAlignment = Enum.VerticalAlignment.Center,
        Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder,
    })
    noclipButton = new("TextButton", {
        Name = "NoclipButton", Parent = body, LayoutOrder = 1, Text = "",
        Size = UDim2.new(1, 0, 0, CONFIG.noclipHeight),
        BackgroundColor3 = CONFIG.colorOff, BorderSizePixel = 0,
        AutoButtonColor = false,
    })
    round(noclipButton, 8)
    stroke(noclipButton, Color3.fromRGB(255, 255, 255), 1, 0.75)
    noclipLabel = new("TextLabel", {
        Name = "Label", Parent = noclipButton, BackgroundTransparency = 1,
        Size = UDim2.fromScale(1, 1), Text = CONFIG.noclipLabel,
        TextSize = CONFIG.noclipTextSize, Font = Enum.Font.GothamBold,
        TextColor3 = Color3.fromRGB(255, 255, 255),
    })
    statusLabel = new("TextLabel", {
        Name = "Status", Parent = body, LayoutOrder = 2, BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 0, 14), Text = "idle", TextSize = 11,
        Font = Enum.Font.Gotham, TextColor3 = CONFIG.colorMuted,
        TextXAlignment = Enum.TextXAlignment.Center,
    })
    dot = new("TextButton", {
        Name = "Dot", Parent = gui, Visible = false, Text = "",
        Size = UDim2.fromOffset(CONFIG.dotCircleSize, CONFIG.dotCircleSize),
        Position = UDim2.fromOffset(CONFIG.panelX, CONFIG.panelY),
        BackgroundColor3 = CONFIG.colorPanel, BorderSizePixel = 0,
        AutoButtonColor = false,
    })
    round(dot, 1)
    stroke(dot, CONFIG.colorStroke, 1, 0.2)
    dotGlyph = new("Frame", {
        Name = "Glyph", Parent = dot, BackgroundTransparency = 1,
        Size = UDim2.fromScale(1, 1),
    })
    buildCircleIcon(dotGlyph)
    dotLetter = new("TextLabel", {
        Name = "Letter", Parent = dot, BackgroundTransparency = 1,
        Size = UDim2.fromScale(1, 1), Text = CONFIG.dotLetter, TextSize = 13,
        Font = Enum.Font.GothamBold, TextColor3 = CONFIG.colorText, Visible = false,
    })
end

--============================================================
-- 07 · MODES
--============================================================

local function applyMode(mode)
    state.mode = mode
    if mode == "normal" then
        dot.Visible = false
        panel.Visible = true
        panel.Position = dot.Position
        local x, y = clampToScreen(panel.Position.X.Offset, panel.Position.Y.Offset,
            panel.AbsoluteSize.X, panel.AbsoluteSize.Y)
        panel.Position = UDim2.fromOffset(x, y)
        return
    end
    local size = (mode == "circle") and CONFIG.dotCircleSize or CONFIG.dotCollapsedSize
    dot.Size = UDim2.fromOffset(size, size)
    dotGlyph.Visible = (mode == "circle")
    dotLetter.Visible = (mode == "collapsed")
    local x, y = clampToScreen(panel.Position.X.Offset, panel.Position.Y.Offset, size, size)
    dot.Position = UDim2.fromOffset(x, y)
    panel.Visible = false
    dot.Visible = true
end

local function toggleMode(mode)
    applyMode(state.mode == mode and "normal" or mode)
end

--============================================================
-- 08 · DRAG
--============================================================

local function attachDrag(handle, target, options)
    options = options or {}
    track(handle.InputBegan:Connect(function(input)
        if input.UserInputType ~= Enum.UserInputType.MouseButton1
            and input.UserInputType ~= Enum.UserInputType.Touch then
            return
        end
        if options.condition and not options.condition() then
            return
        end
        local origin, startPos, moved = input.Position, target.Position, 0
        local watcher
        watcher = input.Changed:Connect(function()
            local delta = input.Position - origin
            moved = math.max(moved, delta.Magnitude)
            local x, y = clampToScreen(startPos.X.Offset + delta.X, startPos.Y.Offset + delta.Y,
                target.AbsoluteSize.X, target.AbsoluteSize.Y)
            target.Position = UDim2.fromOffset(x, y)
        end)
        input.Ended:Connect(function()
            if watcher then
                watcher:Disconnect()
                watcher = nil
            end
            if options.onEnd then
                options.onEnd(moved)
            end
        end)
    end))
end

--============================================================
-- 09 · ENGINE STATE
--============================================================

local ghosted, ghostHooks, engineConns = {}, {}, {}
local heartbeat, frameClock = nil, 0
local lastPosition, guardClock, guardCount = nil, 0, 0
local freezeClock, shoveClock, lastHumanoid = 0, 0, nil
local history, stuckClock, stuckAnchor = {}, 0, nil
local shove = { active = false, direction = Vector3.zero, target = Vector3.zero, frames = 0 }

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.IgnoreWater = true
rayParams.RespectCanCollide = false

local probeParams = OverlapParams.new()
probeParams.FilterType = Enum.RaycastFilterType.Exclude
probeParams.RespectCanCollide = false

local DISABLED_STATES = {
    Enum.HumanoidStateType.FallingDown, Enum.HumanoidStateType.Ragdoll,
    Enum.HumanoidStateType.GettingUp, Enum.HumanoidStateType.StrafingNoPhysics,
    Enum.HumanoidStateType.PlatformStanding,
}

--============================================================
-- 10 · COLLISION LAYER
--============================================================

-- second, independent layer. even if a game re-stamps CanCollide or
-- resets a part's group, the ghost group collides with nothing
local groupReady = false

local function ensureGroup()
    if groupReady then
        return true
    end
    if not pcall(function()
        PhysicsService:RegisterCollisionGroup(CONFIG.ghostGroup)
    end) then
        return false
    end
    local ok, groups = pcall(function()
        return PhysicsService:GetCollisionGroups()
    end)
    if ok and groups then
        for _, group in ipairs(groups) do
            if group.name ~= CONFIG.ghostGroup then
                pcall(function()
                    PhysicsService:CollisionGroupSetCollidable(CONFIG.ghostGroup, group.name, false)
                end)
            end
        end
    end
    groupReady = true
    return true
end

--============================================================
-- 11 · GHOSTING
--============================================================

local function ghostPart(part)
    if not part:IsA("BasePart") then
        return
    end
    if ghosted[part] == nil then
        ghosted[part] = { collide = part.CanCollide, group = part.CollisionGroup }
    end
    if part.CanCollide then
        part.CanCollide = false
    end
    if groupReady and part.CollisionGroup ~= CONFIG.ghostGroup then
        part.CollisionGroup = CONFIG.ghostGroup
    end
    if not ghostHooks[part] then
        ghostHooks[part] = {
            part:GetPropertyChangedSignal("CanCollide"):Connect(function()
                if state.noclip and part.CanCollide then
                    part.CanCollide = false
                end
            end),
            part:GetPropertyChangedSignal("CollisionGroup"):Connect(function()
                if state.noclip and groupReady and part.CollisionGroup ~= CONFIG.ghostGroup then
                    part.CollisionGroup = CONFIG.ghostGroup
                end
            end),
        }
    end
end

local function ghostCharacter(character)
    for _, descendant in ipairs(character:GetDescendants()) do
        ghostPart(descendant)
    end
end

local function clearGhostHooks()
    for part, hooks in pairs(ghostHooks) do
        for _, connection in ipairs(hooks) do
            connection:Disconnect()
        end
        ghostHooks[part] = nil
    end
end

local function restoreCharacter()
    clearGhostHooks()
    for part, saved in pairs(ghosted) do
        if part and part.Parent then
            pcall(function()
                part.CanCollide = saved.collide
                part.CollisionGroup = saved.group
            end)
        end
    end
    table.clear(ghosted)
end

--============================================================
-- 12 · HUMANOID HARDENING
--============================================================

local function hardenHumanoid(humanoid)
    humanoid.RequiresNeck = false
    humanoid.BreakJointsOnDeath = false
    for _, humanoidState in ipairs(DISABLED_STATES) do
        pcall(function()
            humanoid:SetStateEnabled(humanoidState, false)
        end)
    end
end

local function relaxHumanoid(humanoid)
    for _, humanoidState in ipairs(DISABLED_STATES) do
        pcall(function()
            humanoid:SetStateEnabled(humanoidState, true)
        end)
    end
end

local function claimOwnership(root)
    pcall(function()
        root:SetNetworkOwner(LocalPlayer)
    end)
end

--============================================================
-- 13 · PENETRATION
--============================================================

local function embeddedAt(position)
    local size = Vector3.new(CONFIG.probeSize, CONFIG.probeSize, CONFIG.probeSize)
    for _, part in ipairs(Workspace:GetPartBoundsInBox(CFrame.new(position), size, probeParams)) do
        if part.CanCollide then
            return true
        end
    end
    return false
end

local function shoveDirection(root, humanoid)
    local move = humanoid.MoveDirection
    if move.Magnitude > 0.05 then
        return horizontal(move).Unit
    end
    return flatLook(root.CFrame)
end

-- march forward until the body is clear so the shove knows how far
-- it has to travel before it can stop
local function findExit(root, direction)
    local origin, travelled = root.Position, 0
    while travelled < CONFIG.shoveLimit do
        travelled += CONFIG.shoveStep
        if not embeddedAt(origin + direction * travelled) then
            return travelled
        end
    end
    return CONFIG.shoveLimit
end

local function beginShove(root, humanoid)
    local now = os.clock()
    if now - shoveClock < CONFIG.shoveCooldown then
        return false
    end
    local direction = shoveDirection(root, humanoid)
    local distance = findExit(root, direction) + CONFIG.shoveClearance
    shove.active = true
    shove.direction = direction
    shove.target = root.Position + direction * distance
    shove.frames = 0
    shoveClock = now
    return true
end

local function endShove()
    shove.active = false
    shove.frames = 0
    shove.direction = Vector3.zero
end

--============================================================
-- 14 · SHOVE STEP
--============================================================

local function freezing()
    return os.clock() < freezeClock
end

-- the body is stepped by CFrame, not by velocity, so the humanoid
-- and the solver cannot pull it back into the wall mid-pass
local function stepShove(root)
    if not shove.active then
        return
    end
    shove.frames += 1
    if shove.frames > CONFIG.shoveMaxFrames then
        endShove()
        return
    end
    local flat = horizontal(shove.target - root.Position)
    if flat.Magnitude <= 0.2 then
        endShove()
        return
    end
    local speed = freezing() and CONFIG.shoveSpeed * 0.5 or CONFIG.shoveSpeed
    local step = math.min(speed / 60, flat.Magnitude)
    root.CFrame = root.CFrame + flat.Unit * step
    root.AssemblyLinearVelocity = flat.Unit * speed
    if shove.frames == 1 then
        freezeClock = os.clock() + (CONFIG.freezeFrames / 60)
    end
end

--============================================================
-- 15 · POSITION GUARD
--============================================================

-- keeps a short history. a backwards jump past the threshold is a
-- game-side correction and is rewound, capped per second so real
-- teleports still pass
local function pushHistory(position)
    history[#history + 1] = position
    if #history > CONFIG.guardHistory then
        table.remove(history, 1)
    end
end

local function guardPosition(root, direction)
    local now = os.clock()
    if now - guardClock > 1 then
        guardCount = 0
    end
    local current = root.Position
    pushHistory(current)
    if not lastPosition then
        lastPosition = current
        return
    end
    local flat = horizontal(current - lastPosition)
    if flat.Magnitude < CONFIG.guardDistance then
        lastPosition = current
        return
    end
    if flat.Unit:Dot(direction) > -0.2 or guardCount >= CONFIG.guardMaxPerSecond then
        lastPosition = current
        return
    end
    guardCount += 1
    local restore = history[math.max(1, #history - 2)] or lastPosition
    local keep = root.CFrame - root.Position
    root.CFrame = CFrame.new(restore) * keep
    root.AssemblyLinearVelocity = Vector3.zero
    lastPosition = restore
end

--============================================================
-- 16 · FLOOR
--============================================================

local function hoverStep(root, humanoid, velocity)
    local hip = humanoid.HipHeight or 0
    local offset = (root.Size.Y * 0.5) + hip + CONFIG.hoverHeight
    local result = Workspace:Raycast(root.Position,
        Vector3.new(0, -(CONFIG.stickRange + offset), 0), rayParams)
    if not result then
        return false
    end
    local difference = (result.Position.Y + offset) - root.Position.Y
    if math.abs(difference) < 0.02 then
        root.AssemblyLinearVelocity = Vector3.new(velocity.X, 0, velocity.Z)
    else
        local correction = math.clamp(difference * CONFIG.stickStiffness,
            -CONFIG.maxStickSpeed, CONFIG.maxStickSpeed)
        root.AssemblyLinearVelocity = Vector3.new(velocity.X, correction, velocity.Z)
    end
    return true
end

-- while falling, look further down than this frame's travel so a
-- thin floor cannot be skipped over
local function fallClamp(root, velocity)
    local result = Workspace:Raycast(root.Position, Vector3.new(0, -CONFIG.fallProbe, 0), rayParams)
    if not result then
        return
    end
    if result.Distance > math.abs(velocity.Y) / 60 + CONFIG.fallMargin then
        return
    end
    local stop = result.Position.Y + (root.Size.Y * 0.5) + CONFIG.hoverHeight
    if root.Position.Y - stop < 1 then
        root.AssemblyLinearVelocity = Vector3.new(velocity.X, 0, velocity.Z)
    end
end

--============================================================
-- 17 · STUCK BREAKER
--============================================================

-- if input is held and the body has barely moved for a while while
-- inside geometry, force a pass instead of waiting on physics
local function checkStuck(root, humanoid)
    if humanoid.MoveDirection.Magnitude < 0.05 then
        stuckAnchor, stuckClock = root.Position, 0
        return false
    end
    if not stuckAnchor then
        stuckAnchor = root.Position
        return false
    end
    if horizontal(root.Position - stuckAnchor).Magnitude > CONFIG.stuckEpsilon then
        stuckAnchor, stuckClock = root.Position, 0
        return false
    end
    stuckClock += 1
    if stuckClock >= CONFIG.stuckFrames then
        stuckClock, stuckAnchor = 0, root.Position
        return true
    end
    return false
end

--============================================================
-- 18 · HEARTBEAT
--============================================================

local function onHeartbeat()
    if not state.noclip then
        return
    end
    local character = LocalPlayer.Character
    if not character or not character.Parent then
        return
    end
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    local root = character:FindFirstChild("HumanoidRootPart")
    if not humanoid or not root or root.Parent ~= character then
        return
    end

    frameClock += 1
    if frameClock <= CONFIG.ghostBurstFrames or frameClock % CONFIG.ghostRefreshRate == 0 then
        ghostCharacter(character)
        claimOwnership(root)
    end

    rayParams.FilterDescendantsInstances = { character }
    probeParams.FilterDescendantsInstances = { character }

    if humanoid.PlatformStand then
        pcall(function()
            humanoid.PlatformStand = false
        end)
    end

    local okState, humanoidState = pcall(function()
        return humanoid:GetState()
    end)
    if not okState then
        humanoidState = nil
    end

    local velocity = root.AssemblyLinearVelocity
    local direction = shoveDirection(root, humanoid)

    if humanoidState == Enum.HumanoidStateType.Swimming
        or humanoidState == Enum.HumanoidStateType.Climbing
        or humanoidState == Enum.HumanoidStateType.Seated then
        return
    end

    guardPosition(root, direction)

    if shove.active then
        stepShove(root)
        return
    end

    if embeddedAt(root.Position) then
        beginShove(root, humanoid)
        stepShove(root)
        return
    end

    if checkStuck(root, humanoid) then
        beginShove(root, humanoid)
        stepShove(root)
        return
    end

    if humanoidState == Enum.HumanoidStateType.Jumping or velocity.Y > 2 then
        fallClamp(root, velocity)
        return
    end

    if hoverStep(root, humanoid, velocity)
        and humanoidState == Enum.HumanoidStateType.Freefall then
        pcall(function()
            humanoid:ChangeState(Enum.HumanoidStateType.Running)
        end)
    end
end

--============================================================
-- 19 · LIFECYCLE
--============================================================

local function stopEngine()
    for _, connection in ipairs(engineConns) do
        connection:Disconnect()
    end
    table.clear(engineConns)
    if heartbeat then
        heartbeat:Disconnect()
        heartbeat = nil
    end
    if lastHumanoid then
        relaxHumanoid(lastHumanoid)
        lastHumanoid = nil
    end
    lastPosition = nil
    table.clear(history)
    endShove()
    restoreCharacter()
end

local function startEngine()
    local character = LocalPlayer.Character
    if not character then
        return false
    end
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    local root = character:FindFirstChild("HumanoidRootPart")
    if not humanoid or not root then
        return false
    end
    ensureGroup()
    table.clear(ghosted)
    ghostCharacter(character)
    hardenHumanoid(humanoid)
    claimOwnership(root)
    lastHumanoid = humanoid
    engineConns[#engineConns + 1] = character.DescendantAdded:Connect(ghostPart)
    engineConns[#engineConns + 1] = humanoid.Died:Connect(function()
        stopEngine()
        if state.noclip then
            LocalPlayer:WaitForChild("Character", 10)
            task.wait(0.4)
            if state.noclip then
                startEngine()
            end
        end
    end)
    heartbeat = RunService.Heartbeat:Connect(onHeartbeat)
    return true
end

--============================================================
-- 20 · PAINT
--============================================================

local function paintNoclip()
    if state.noclip then
        noclipButton.BackgroundColor3 = CONFIG.colorOn
        noclipLabel.Text = CONFIG.noclipLabelActive
        statusLabel.Text = "active"
        statusLabel.TextColor3 = CONFIG.colorOn
    else
        noclipButton.BackgroundColor3 = CONFIG.colorOff
        noclipLabel.Text = CONFIG.noclipLabel
        statusLabel.Text = "idle"
        statusLabel.TextColor3 = CONFIG.colorMuted
    end
end

local function paintDragMode()
    moveButton.BackgroundColor3 = state.dragMode and CONFIG.colorActive or CONFIG.colorButton
    if moveButtonStroke then
        moveButtonStroke.Transparency = state.dragMode and 0 or 0.4
    end
end

local function setNoclip(enabled)
    if state.noclip == enabled then
        return
    end
    if enabled then
        if startEngine() then
            state.noclip = true
        end
    else
        state.noclip = false
        stopEngine()
    end
    paintNoclip()
end

--============================================================
-- 21 · WIRING
--============================================================

local function wire()
    track(noclipButton.Activated:Connect(function()
        setNoclip(not state.noclip)
    end))
    track(moveButton.Activated:Connect(function()
        state.dragMode = not state.dragMode
        paintDragMode()
    end))
    track(circleButton.Activated:Connect(function()
        toggleMode("circle")
    end))
    track(closeButton.Activated:Connect(function()
        toggleMode("collapsed")
    end))

    attachDrag(panel, panel, {
        condition = function()
            return UserInputService:GetMouseLocation().Y
                <= panel.AbsolutePosition.Y + CONFIG.headerHeight
        end,
    })
    attachDrag(panel, panel, {
        condition = function()
            return state.dragMode
        end,
    })
    attachDrag(dot, dot, {
        onEnd = function(moved)
            if moved < CONFIG.tapThreshold then
                applyMode("normal")
            end
        end,
    })

    track(Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
        local camera = Workspace.CurrentCamera
        if not camera then
            return
        end
        track(camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
            local target = (state.mode == "normal") and panel or dot
            local x, y = clampToScreen(target.Position.X.Offset, target.Position.Y.Offset,
                target.AbsoluteSize.X, target.AbsoluteSize.Y)
            target.Position = UDim2.fromOffset(x, y)
        end))
    end))
end

--============================================================
-- 22 · PUBLIC API
--============================================================

local api = {}
api.toggle = function() setNoclip(not state.noclip) end
api.on = function() setNoclip(true) end
api.off = function() setNoclip(false) end
api.circle = function() applyMode("circle") end
api.collapse = function() applyMode("collapsed") end
api.expand = function() applyMode("normal") end
api.destroy = function()
    if state.destroyed then
        return
    end
    state.destroyed = true
    state.noclip = false
    stopEngine()
    for _, connection in ipairs(connections) do
        connection:Disconnect()
    end
    table.clear(connections)
    if gui then
        gui:Destroy()
    end
    getgenv().NoClip = nil
end

--============================================================
-- 23 · BOOT
--============================================================

local function boot()
    local existing = guiParent():FindFirstChild(CONFIG.guiName)
    if existing then
        existing:Destroy()
    end
    buildGui()
    paintNoclip()
    paintDragMode()
    wire()
    getgenv().NoClip = api
    track(LocalPlayer.CharacterAdded:Connect(function(character)
        if not state.noclip then
            return
        end
        character:WaitForChild("HumanoidRootPart", 10)
        task.wait(0.4)
        if state.noclip then
            startEngine()
        end
    end))
end

boot()

--============================================================
-- 24 · NOTES
--============================================================
-- why this holds where a plain CanCollide toggle does not:
--
--   layer one  every BasePart is ghosted and watched, so a
--              restamped CanCollide is reverted the same frame
--   layer two  every part is moved into a collision group that
--              collides with nothing, so physics ignores it even
--              while CanCollide is true
--   measured   the exit distance is raycast-marched before any
--              push starts, so the body always travels the full
--              depth of the wall instead of stopping halfway
--   forced     the pass is applied as CFrame steps, which neither
--              the humanoid nor the solver can pull back
--   frozen     the first frames run at half speed so the body
--              cannot bounce out the face it entered
--   guard      backwards corrections over 3.5 studs are rewound
--              from a position history, capped at eight a second
--   stuck      held input with no movement forces a pass
--   floor      downward raycast hover, plus a longer fall clamp
--              so thin floors cannot be skipped
--   off        restores CanCollide, groups and humanoid states
--
-- end of file
--[[
════════════════════════════════════════════════════════════
   N O C L I P   ·   h a r d   m o d e   4   ·   s h i e l d
   ------------------------------------------------------------
   file    : noclip.lua
   author  : supercaptain1233
   target  : Delta (Android) · universal · any Roblox game
   version : 4.0.0
   ------------------------------------------------------------
   panel   : Noclip header, X collapse, move toggle, circle dot
   noclip  : double collision layer, measured exit, forced
             CFrame pass, freeze, history guard, fall clamp
   shield  : every property a game can use to pin the body is
             watched and put back, gui and engine self-heal
   ------------------------------------------------------------
   no print() calls in this file
   ════════════════════════════════════════════════════════════
]]


--============================================================
-- 01 · CONFIG
--============================================================

local CONFIG = {
    panelWidth = 190, panelHeight = 148, panelX = 24, panelY = 88, cornerRadius = 10,
    headerHeight = 30, headerGap = 4, title = "Noclip", titleSize = 13,
    headerButtonSize = 24, bodyPadding = 12, noclipHeight = 54, noclipTextSize = 15,
    noclipLabel = "NOCLIP", noclipLabelActive = "NOCLIP: ON",
    dotCircleSize = 46, dotCollapsedSize = 30, dotLetter = "N",
    colorPanel = Color3.fromRGB(19, 22, 28), colorHeader = Color3.fromRGB(28, 32, 40),
    colorBody = Color3.fromRGB(15, 17, 22), colorButton = Color3.fromRGB(44, 49, 60),
    colorButtonHover = Color3.fromRGB(60, 67, 82), colorActive = Color3.fromRGB(64, 110, 74),
    colorOff = Color3.fromRGB(224, 49, 49), colorOn = Color3.fromRGB(45, 168, 88),
    colorText = Color3.fromRGB(235, 238, 243), colorMuted = Color3.fromRGB(120, 128, 140),
    colorStroke = Color3.fromRGB(52, 58, 70),
    hoverHeight = 0.25, stickRange = 16, stickStiffness = 14, maxStickSpeed = 55,
    ghostGroup = "NoClipGhost", ghostRefreshRate = 6, ghostBurstFrames = 45,
    probeSize = 1.4, shoveStep = 0.6, shoveLimit = 14, shoveSpeed = 30,
    shoveClearance = 1.2, shoveMaxFrames = 48, shoveCooldown = 0.2, shoveDrift = 2.5,
    freezeFrames = 5, guardDistance = 3.5, guardHistory = 14, guardMaxPerSecond = 8,
    fallProbe = 60, fallMargin = 3, stuckFrames = 9, stuckEpsilon = 0.35,
    tapThreshold = 8, screenPadding = 4, engineErrorLimit = 30,
    displayOrder = 9999, guiName = "NoClipUI",
}

--============================================================
-- 02 · SERVICES
--============================================================

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local PhysicsService = game:GetService("PhysicsService")
local Workspace = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer
if not LocalPlayer then
    Players:GetPropertyChangedSignal("LocalPlayer"):Wait()
    LocalPlayer = Players.LocalPlayer
end

--============================================================
-- 03 · UTILITIES
--============================================================

local function new(class, props, children)
    local inst = Instance.new(class)
    local parent = props and props.Parent
    if props then
        for key, value in pairs(props) do
            if key ~= "Parent" then
                inst[key] = value
            end
        end
    end
    for _, child in ipairs(children or {}) do
        child.Parent = inst
    end
    if parent then
        inst.Parent = parent
    end
    return inst
end

local function round(inst, radius)
    new("UICorner", { CornerRadius = UDim.new(0, radius or 8), Parent = inst })
    return inst
end

local function stroke(inst, colour, thickness, transparency)
    new("UIStroke", {
        Color = colour or CONFIG.colorStroke, Thickness = thickness or 1,
        Transparency = transparency or 0, Parent = inst,
    })
    return inst
end

local function clampToScreen(x, y, width, height)
    local camera = Workspace.CurrentCamera
    local vp = camera and camera.ViewportSize or Vector2.new(1080, 1920)
    local edge = CONFIG.screenPadding
    return math.clamp(x, edge, math.max(edge, vp.X - width - edge)),
        math.clamp(y, edge, math.max(edge, vp.Y - height - edge))
end

local function guiParent()
    local ok, hidden = pcall(function()
        return gethui and gethui() or nil
    end)
    return (ok and hidden) or LocalPlayer:WaitForChild("PlayerGui")
end

local function horizontal(vector)
    return Vector3.new(vector.X, 0, vector.Z)
end

local function flatLook(cframe)
    local flat = horizontal(cframe.LookVector)
    return flat.Magnitude < 0.01 and Vector3.new(0, 0, -1) or flat.Unit
end

--============================================================
-- 04 · STATE
--============================================================

local state = { mode = "normal", dragMode = false, noclip = false, destroyed = false }
local panel, dot, dotGlyph, dotLetter
local noclipButton, noclipLabel, statusLabel
local moveButton, moveButtonStroke, circleButton, circleButtonStroke
local closeButton, gui

local connections = {}
local function track(connection)
    connections[#connections + 1] = connection
    return connection
end

local shield = { hooks = {}, gravity = 0, walk = 0, jump = 0 }
local engineErrors = 0

--============================================================
-- 05 · ICONS
--============================================================

local function buildMoveIcon(parent)
    local wrap = new("Frame", {
        Name = "MoveIcon", Parent = parent, BackgroundTransparency = 1,
        Size = UDim2.fromOffset(16, 16), Position = UDim2.fromScale(0.5, 0.5),
        AnchorPoint = Vector2.new(0.5, 0.5),
    })
    local glyphs = {
        { text = "\u{2191}", x = 0, y = 0 }, { text = "\u{2190}", x = 0, y = 5.5 },
        { text = "\u{2192}", x = 8, y = 5.5 }, { text = "\u{2193}", x = 0, y = 11 },
    }
    for _, glyph in ipairs(glyphs) do
        new("TextLabel", {
            Parent = wrap, BackgroundTransparency = 1, Text = glyph.text,
            Size = UDim2.fromOffset(8, 5), Position = UDim2.fromOffset(glyph.x, glyph.y),
            TextSize = 8, Font = Enum.Font.GothamBold, TextColor3 = CONFIG.colorText,
        })
    end
end

local function buildCircleIcon(parent)
    local ring = new("Frame", {
        Name = "Ring", Parent = parent, BackgroundTransparency = 1, BorderSizePixel = 0,
        Size = UDim2.fromOffset(11, 11), Position = UDim2.fromScale(0.5, 0.5),
        AnchorPoint = Vector2.new(0.5, 0.5),
    })
    round(ring, 11)
    stroke(ring, CONFIG.colorText, 1.4, 0)
end

--============================================================
-- 06 · GUI
--============================================================

local function buildGui()
    gui = new("ScreenGui", {
        Name = CONFIG.guiName, ResetOnSpawn = false, IgnoreGuiInset = true,
        DisplayOrder = CONFIG.displayOrder, Parent = guiParent(),
    })
    panel = new("Frame", {
        Name = "Panel", Parent = gui, ClipsDescendants = true, BorderSizePixel = 0,
        Size = UDim2.fromOffset(CONFIG.panelWidth, CONFIG.panelHeight),
        Position = UDim2.fromOffset(CONFIG.panelX, CONFIG.panelY),
        BackgroundColor3 = CONFIG.colorPanel,
    })
    round(panel, CONFIG.cornerRadius)
    stroke(panel, CONFIG.colorStroke, 1, 0.25)
    local header = new("Frame", {
        Name = "Header", Parent = panel, BorderSizePixel = 0,
        Size = UDim2.new(1, 0, 0, CONFIG.headerHeight), BackgroundColor3 = CONFIG.colorHeader,
    })
    new("TextLabel", {
        Name = "Title", Parent = header, BackgroundTransparency = 1,
        Size = UDim2.new(1, -104, 1, 0), Position = UDim2.fromOffset(10, 0),
        Text = CONFIG.title, TextSize = CONFIG.titleSize, Font = Enum.Font.GothamBold,
        TextColor3 = CONFIG.colorText, TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Center,
    })
    local row = new("Frame", {
        Name = "Buttons", Parent = header, BackgroundTransparency = 1,
        Size = UDim2.new(0, 80, 1, 0), Position = UDim2.new(1, -6, 0, 0),
        AnchorPoint = Vector2.new(1, 0),
    })
    new("UIListLayout", {
        Parent = row, FillDirection = Enum.FillDirection.Horizontal,
        HorizontalAlignment = Enum.HorizontalAlignment.Right,
        VerticalAlignment = Enum.VerticalAlignment.Center,
        Padding = UDim.new(0, CONFIG.headerGap),
    })
    circleButton = new("TextButton", {
        Name = "CircleButton", Parent = row, LayoutOrder = 1, Text = "",
        Size = UDim2.fromOffset(CONFIG.headerButtonSize, CONFIG.headerButtonSize),
        BackgroundColor3 = CONFIG.colorButton, BorderSizePixel = 0, AutoButtonColor = false,
    })
    round(circleButton, 6)
    circleButtonStroke = stroke(circleButton, CONFIG.colorStroke, 1, 0.4)
    buildCircleIcon(circleButton)
    moveButton = new("TextButton", {
        Name = "MoveButton", Parent = row, LayoutOrder = 2, Text = "",
        Size = UDim2.fromOffset(CONFIG.headerButtonSize, CONFIG.headerButtonSize),
        BackgroundColor3 = CONFIG.colorButton, BorderSizePixel = 0, AutoButtonColor = false,
    })
    round(moveButton, 6)
    moveButtonStroke = stroke(moveButton, CONFIG.colorStroke, 1, 0.4)
    buildMoveIcon(moveButton)
    closeButton = new("TextButton", {
        Name = "CloseButton", Parent = row, LayoutOrder = 3, BorderSizePixel = 0,
        Size = UDim2.fromOffset(CONFIG.headerButtonSize, CONFIG.headerButtonSize),
        BackgroundColor3 = CONFIG.colorButton, Text = "\u{2715}", TextSize = 12,
        Font = Enum.Font.GothamBold, TextColor3 = CONFIG.colorText, AutoButtonColor = false,
    })
    round(closeButton, 6)
    stroke(closeButton, CONFIG.colorStroke, 1, 0.4)
    local body = new("Frame", {
        Name = "Body", Parent = panel, BorderSizePixel = 0,
        Size = UDim2.new(1, 0, 1, -CONFIG.headerHeight),
        Position = UDim2.fromOffset(0, CONFIG.headerHeight),
        BackgroundColor3 = CONFIG.colorBody,
    })
    new("UIPadding", {
        Parent = body, PaddingTop = UDim.new(0, CONFIG.bodyPadding),
        PaddingLeft = UDim.new(0, CONFIG.bodyPadding),
        PaddingRight = UDim.new(0, CONFIG.bodyPadding), PaddingBottom = UDim.new(0, 8),
    })
    new("UIListLayout", {
        Parent = body, FillDirection = Enum.FillDirection.Vertical,
        HorizontalAlignment = Enum.HorizontalAlignment.Center,
        VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 8),
    })
    noclipButton = new("TextButton", {
        Name = "NoclipButton", Parent = body, LayoutOrder = 1, Text = "",
        Size = UDim2.new(1, 0, 0, CONFIG.noclipHeight),
        BackgroundColor3 = CONFIG.colorOff, BorderSizePixel = 0, AutoButtonColor = false,
    })
    round(noclipButton, 8)
    stroke(noclipButton, Color3.fromRGB(255, 255, 255), 1, 0.75)
    noclipLabel = new("TextLabel", {
        Name = "Label", Parent = noclipButton, BackgroundTransparency = 1,
        Size = UDim2.fromScale(1, 1), Text = CONFIG.noclipLabel,
        TextSize = CONFIG.noclipTextSize, Font = Enum.Font.GothamBold,
        TextColor3 = Color3.fromRGB(255, 255, 255),
    })
    statusLabel = new("TextLabel", {
        Name = "Status", Parent = body, LayoutOrder = 2, BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 0, 14), Text = "idle", TextSize = 11,
        Font = Enum.Font.Gotham, TextColor3 = CONFIG.colorMuted,
        TextXAlignment = Enum.TextXAlignment.Center,
    })
    dot = new("TextButton", {
        Name = "Dot", Parent = gui, Visible = false, Text = "",
        Size = UDim2.fromOffset(CONFIG.dotCircleSize, CONFIG.dotCircleSize),
        Position = UDim2.fromOffset(CONFIG.panelX, CONFIG.panelY),
        BackgroundColor3 = CONFIG.colorPanel, BorderSizePixel = 0, AutoButtonColor = false,
    })
    round(dot, 1)
    stroke(dot, CONFIG.colorStroke, 1, 0.2)
    dotGlyph = new("Frame", {
        Name = "Glyph", Parent = dot, BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1),
    })
    buildCircleIcon(dotGlyph)
    dotLetter = new("TextLabel", {
        Name = "Letter", Parent = dot, BackgroundTransparency = 1,
        Size = UDim2.fromScale(1, 1), Text = CONFIG.dotLetter, TextSize = 13,
        Font = Enum.Font.GothamBold, TextColor3 = CONFIG.colorText, Visible = false,
    })
end

--============================================================
-- 07 · MODES
--============================================================

local function applyMode(mode)
    state.mode = mode
    if mode == "normal" then
        dot.Visible = false
        panel.Visible = true
        panel.Position = dot.Position
        local x, y = clampToScreen(panel.Position.X.Offset, panel.Position.Y.Offset,
            panel.AbsoluteSize.X, panel.AbsoluteSize.Y)
        panel.Position = UDim2.fromOffset(x, y)
        return
    end
    local size = (mode == "circle") and CONFIG.dotCircleSize or CONFIG.dotCollapsedSize
    dot.Size = UDim2.fromOffset(size, size)
    dotGlyph.Visible = (mode == "circle")
    dotLetter.Visible = (mode == "collapsed")
    local x, y = clampToScreen(panel.Position.X.Offset, panel.Position.Y.Offset, size, size)
    dot.Position = UDim2.fromOffset(x, y)
    panel.Visible = false
    dot.Visible = true
end

local function toggleMode(mode)
    applyMode(state.mode == mode and "normal" or mode)
end

--============================================================
-- 08 · DRAG
--============================================================

local function attachDrag(handle, target, options)
    options = options or {}
    track(handle.InputBegan:Connect(function(input)
        if input.UserInputType ~= Enum.UserInputType.MouseButton1
            and input.UserInputType ~= Enum.UserInputType.Touch then
            return
        end
        if options.condition and not options.condition() then
            return
        end
        local origin, startPos, moved = input.Position, target.Position, 0
        local watcher
        watcher = input.Changed:Connect(function()
            local delta = input.Position - origin
            moved = math.max(moved, delta.Magnitude)
            local x, y = clampToScreen(startPos.X.Offset + delta.X, startPos.Y.Offset + delta.Y,
                target.AbsoluteSize.X, target.AbsoluteSize.Y)
            target.Position = UDim2.fromOffset(x, y)
        end)
        input.Ended:Connect(function()
            if watcher then
                watcher:Disconnect()
            end
            if options.onEnd then
                options.onEnd(moved)
            end
        end)
    end))
end

--============================================================
-- 09 · ENGINE STATE
--============================================================

local stopEngine, startEngine
local ghosted, ghostHooks, engineConns = {}, {}, {}
local heartbeat, frameClock = nil, 0
local lastPosition, guardClock, guardCount = nil, 0, 0
local freezeClock, shoveClock, lastHumanoid = 0, 0, nil
local history, stuckClock, stuckAnchor = {}, 0, nil
local shove = { active = false, direction = Vector3.zero, target = Vector3.zero,
    frames = 0, last = Vector3.zero }

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.IgnoreWater = true
rayParams.RespectCanCollide = false

local probeParams = OverlapParams.new()
probeParams.FilterType = Enum.RaycastFilterType.Exclude
probeParams.RespectCanCollide = false

local DISABLED_STATES = {
    Enum.HumanoidStateType.FallingDown, Enum.HumanoidStateType.Ragdoll,
    Enum.HumanoidStateType.GettingUp, Enum.HumanoidStateType.StrafingNoPhysics,
    Enum.HumanoidStateType.PlatformStanding,
}

--============================================================
-- 10 · COLLISION LAYER
--============================================================

-- second, independent layer. even if a game re-stamps CanCollide or
-- resets a part's group, the ghost group collides with nothing
local groupReady = false

local function ensureGroup()
    if groupReady then
        return true
    end
    if not pcall(function()
        PhysicsService:RegisterCollisionGroup(CONFIG.ghostGroup)
    end) then
        return false
    end
    local ok, groups = pcall(function()
        return PhysicsService:GetCollisionGroups()
    end)
    if ok and groups then
        for _, group in ipairs(groups) do
            if group.name ~= CONFIG.ghostGroup then
                pcall(function()
                    PhysicsService:CollisionGroupSetCollidable(CONFIG.ghostGroup, group.name, false)
                end)
            end
        end
    end
    groupReady = true
    return true
end

--============================================================
-- 11 · GHOSTING
--============================================================

local function ghostPart(part)
    if not part:IsA("BasePart") then
        return
    end
    if ghosted[part] == nil then
        ghosted[part] = { collide = part.CanCollide, group = part.CollisionGroup }
    end
    if part.CanCollide then
        part.CanCollide = false
    end
    if groupReady and part.CollisionGroup ~= CONFIG.ghostGroup then
        part.CollisionGroup = CONFIG.ghostGroup
    end
    if not ghostHooks[part] then
        ghostHooks[part] = {
            part:GetPropertyChangedSignal("CanCollide"):Connect(function()
                if state.noclip and part.CanCollide then
                    part.CanCollide = false
                end
            end),
            part:GetPropertyChangedSignal("CollisionGroup"):Connect(function()
                if state.noclip and groupReady and part.CollisionGroup ~= CONFIG.ghostGroup then
                    part.CollisionGroup = CONFIG.ghostGroup
                end
            end),
        }
    end
end

local function ghostCharacter(character)
    for _, descendant in ipairs(character:GetDescendants()) do
        ghostPart(descendant)
    end
end

local function clearGhostHooks()
    for part, hooks in pairs(ghostHooks) do
        for _, connection in ipairs(hooks) do
            connection:Disconnect()
        end
        ghostHooks[part] = nil
    end
end

local function restoreCharacter()
    clearGhostHooks()
    for part, saved in pairs(ghosted) do
        if part and part.Parent then
            pcall(function()
                part.CanCollide = saved.collide
                part.CollisionGroup = saved.group
            end)
        end
    end
    table.clear(ghosted)
end

--============================================================
-- 12 · HUMANOID HARDENING
--============================================================

local function hardenHumanoid(humanoid)
    humanoid.RequiresNeck = false
    humanoid.BreakJointsOnDeath = false
    for _, humanoidState in ipairs(DISABLED_STATES) do
        pcall(function()
            humanoid:SetStateEnabled(humanoidState, false)
        end)
    end
end

local function relaxHumanoid(humanoid)
    for _, humanoidState in ipairs(DISABLED_STATES) do
        pcall(function()
            humanoid:SetStateEnabled(humanoidState, true)
        end)
    end
end

local function claimOwnership(root)
    pcall(function()
        root:SetNetworkOwner(LocalPlayer)
    end)
end

--============================================================
-- 13 · SHIELD
--============================================================

-- everything a game can use to pin, freeze or hide the body gets a
-- watcher that puts it straight back on the next change
local function shieldProp(inst, prop, fix)
    shield.hooks[inst] = shield.hooks[inst] or {}
    if shield.hooks[inst][prop] then
        return
    end
    shield.hooks[inst][prop] = inst:GetPropertyChangedSignal(prop):Connect(function()
        if state.noclip and not state.destroyed then
            pcall(fix)
        end
    end)
end

local function armShield(character, humanoid, root)
    shield.gravity, shield.walk, shield.jump = Workspace.Gravity, humanoid.WalkSpeed,
        humanoid.JumpPower
    shieldProp(root, "Anchored", function() if root.Anchored then root.Anchored = false end end)
    shieldProp(root, "CanCollide", function() if root.CanCollide then root.CanCollide = false end end)
    shieldProp(root, "Massless", function() if not root.Massless then root.Massless = true end end)
    shieldProp(root, "CanQuery", function() if not root.CanQuery then root.CanQuery = true end end)
    shieldProp(humanoid, "PlatformStand",
        function() if humanoid.PlatformStand then humanoid.PlatformStand = false end end)
    shieldProp(humanoid, "RequiresNeck",
        function() if humanoid.RequiresNeck then humanoid.RequiresNeck = false end end)
    shieldProp(humanoid, "BreakJointsOnDeath",
        function() if humanoid.BreakJointsOnDeath then humanoid.BreakJointsOnDeath = false end end)
    shieldProp(humanoid, "WalkSpeed", function()
        if humanoid.WalkSpeed <= 0 and shield.walk > 0 then
            humanoid.WalkSpeed = shield.walk
        end
    end)
    shieldProp(humanoid, "JumpPower", function()
        if humanoid.JumpPower <= 0 and shield.jump > 0 then
            humanoid.JumpPower = shield.jump
        end
    end)
    shieldProp(Workspace, "Gravity",
        function() if Workspace.Gravity < 1 then Workspace.Gravity = shield.gravity end end)
    shieldProp(character, "Parent", function()
        if character.Parent ~= Workspace and character.Parent then
            character.Parent = Workspace
        end
    end)
end

local function disarmShield()
    for inst, props in pairs(shield.hooks) do
        for _, connection in pairs(props) do
            connection:Disconnect()
        end
        shield.hooks[inst] = nil
    end
end

--============================================================
-- 14 · PENETRATION
--============================================================

local function embeddedAt(position)
    local size = Vector3.new(CONFIG.probeSize, CONFIG.probeSize, CONFIG.probeSize)
    for _, part in ipairs(Workspace:GetPartBoundsInBox(CFrame.new(position), size, probeParams)) do
        if part.CanCollide then
            return true
        end
    end
    return false
end

local function shoveDirection(root, humanoid)
    local move = humanoid.MoveDirection
    if move.Magnitude > 0.05 then
        return horizontal(move).Unit
    end
    return flatLook(root.CFrame)
end

-- march forward until the body is clear so the shove knows the full
-- depth it has to cover before it can stop
local function findExit(root, direction)
    local origin, travelled = root.Position, 0
    while travelled < CONFIG.shoveLimit do
        travelled += CONFIG.shoveStep
        if not embeddedAt(origin + direction * travelled) then
            return travelled
        end
    end
    return CONFIG.shoveLimit
end

local function beginShove(root, humanoid)
    local now = os.clock()
    if now - shoveClock < CONFIG.shoveCooldown then
        return false
    end
    local direction = shoveDirection(root, humanoid)
    shove.active = true
    shove.direction = direction
    shove.target = root.Position + direction * (findExit(root, direction) + CONFIG.shoveClearance)
    shove.frames, shove.last, shoveClock = 0, root.Position, now
    return true
end

local function endShove()
    shove.active = false
    shove.frames = 0
    shove.direction = Vector3.zero
end

--============================================================
-- 15 · SHOVE STEP
--============================================================

-- stepped by CFrame, not velocity, so neither the humanoid nor the
-- solver can drag the body back into the wall mid-pass
local function stepShove(root)
    if not shove.active then
        return
    end
    shove.frames += 1
    if shove.frames > CONFIG.shoveMaxFrames then
        endShove()
        return
    end
    if horizontal(root.Position - shove.last).Magnitude > CONFIG.shoveDrift then
        shove.target = root.Position + shove.direction * CONFIG.shoveClearance
    end
    shove.last = root.Position
    local flat = horizontal(shove.target - root.Position)
    if flat.Magnitude <= 0.2 then
        endShove()
        return
    end
    local speed = (os.clock() < freezeClock) and CONFIG.shoveSpeed * 0.5 or CONFIG.shoveSpeed
    root.CFrame = root.CFrame + flat.Unit * math.min(speed / 60, flat.Magnitude)
    root.AssemblyLinearVelocity = flat.Unit * speed
    if shove.frames == 1 then
        freezeClock = os.clock() + (CONFIG.freezeFrames / 60)
    end
end

--============================================================
-- 16 · POSITION GUARD
--============================================================

-- a backwards jump past the threshold is a game-side correction and
-- is rewound from history, capped per second so real teleports pass
local function guardPosition(root, direction)
    local now = os.clock()
    if now - guardClock > 1 then
        guardCount = 0
    end
    local current = root.Position
    history[#history + 1] = current
    if #history > CONFIG.guardHistory then
        table.remove(history, 1)
    end
    if not lastPosition then
        lastPosition = current
        return
    end
    local flat = horizontal(current - lastPosition)
    if flat.Magnitude < CONFIG.guardDistance then
        lastPosition = current
        return
    end
    if flat.Unit:Dot(direction) > -0.2 or guardCount >= CONFIG.guardMaxPerSecond then
        lastPosition = current
        return
    end
    guardCount += 1
    local restore = history[math.max(1, #history - 2)] or lastPosition
    local keep = root.CFrame - root.Position
    root.CFrame = CFrame.new(restore) * keep
    root.AssemblyLinearVelocity = Vector3.zero
    lastPosition = restore
end

--============================================================
-- 17 · FLOOR
--============================================================

local function hoverStep(root, humanoid, velocity)
    local hip = humanoid.HipHeight or 0
    local offset = (root.Size.Y * 0.5) + hip + CONFIG.hoverHeight
    local result = Workspace:Raycast(root.Position,
        Vector3.new(0, -(CONFIG.stickRange + offset), 0), rayParams)
    if not result then
        return false
    end
    local difference = (result.Position.Y + offset) - root.Position.Y
    if math.abs(difference) < 0.02 then
        root.AssemblyLinearVelocity = Vector3.new(velocity.X, 0, velocity.Z)
    else
        local correction = math.clamp(difference * CONFIG.stickStiffness,
            -CONFIG.maxStickSpeed, CONFIG.maxStickSpeed)
        root.AssemblyLinearVelocity = Vector3.new(velocity.X, correction, velocity.Z)
    end
    return true
end

local function fallClamp(root, velocity)
    local result = Workspace:Raycast(root.Position, Vector3.new(0, -CONFIG.fallProbe, 0), rayParams)
    if not result or result.Distance > math.abs(velocity.Y) / 60 + CONFIG.fallMargin then
        return
    end
    local stop = result.Position.Y + (root.Size.Y * 0.5) + CONFIG.hoverHeight
    if root.Position.Y - stop < 1 then
        root.AssemblyLinearVelocity = Vector3.new(velocity.X, 0, velocity.Z)
    end
end

--============================================================
-- 18 · STUCK BREAKER
--============================================================

local function checkStuck(root, humanoid)
    if humanoid.MoveDirection.Magnitude < 0.05 then
        stuckAnchor, stuckClock = root.Position, 0
        return false
    end
    if not stuckAnchor then
        stuckAnchor = root.Position
        return false
    end
    if horizontal(root.Position - stuckAnchor).Magnitude > CONFIG.stuckEpsilon then
        stuckAnchor, stuckClock = root.Position, 0
        return false
    end
    stuckClock += 1
    if stuckClock >= CONFIG.stuckFrames then
        stuckClock, stuckAnchor = 0, root.Position
        return true
    end
    return false
end

--============================================================
-- 19 · HEARTBEAT
--============================================================

local function beat()
    local character = LocalPlayer.Character
    if not character or not character.Parent then
        return
    end
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    local root = character:FindFirstChild("HumanoidRootPart")
    if not humanoid or not root or root.Parent ~= character then
        return
    end
    frameClock += 1
    if frameClock <= CONFIG.ghostBurstFrames or frameClock % CONFIG.ghostRefreshRate == 0 then
        ghostCharacter(character)
        claimOwnership(root)
    end
    rayParams.FilterDescendantsInstances = { character }
    probeParams.FilterDescendantsInstances = { character }
    if humanoid.PlatformStand then
        humanoid.PlatformStand = false
    end
    if root.Anchored then
        root.Anchored = false
    end
    local okState, humanoidState = pcall(function()
        return humanoid:GetState()
    end)
    if not okState then
        humanoidState = nil
    end
    local velocity = root.AssemblyLinearVelocity
    local direction = shoveDirection(root, humanoid)
    if humanoidState == Enum.HumanoidStateType.Swimming
        or humanoidState == Enum.HumanoidStateType.Climbing
        or humanoidState == Enum.HumanoidStateType.Seated then
        return
    end
    guardPosition(root, direction)
    if shove.active then
        stepShove(root)
        return
    end
    if embeddedAt(root.Position) then
        beginShove(root, humanoid)
        stepShove(root)
        return
    end
    if checkStuck(root, humanoid) then
        beginShove(root, humanoid)
        stepShove(root)
        return
    end
    if humanoidState == Enum.HumanoidStateType.Jumping or velocity.Y > 2 then
        fallClamp(root, velocity)
        return
    end
    if hoverStep(root, humanoid, velocity)
        and humanoidState == Enum.HumanoidStateType.Freefall then
        pcall(function()
            humanoid:ChangeState(Enum.HumanoidStateType.Running)
        end)
    end
end

-- a single error must never kill the loop; repeated errors rebuild
-- the engine from scratch
local function onHeartbeat()
    if not state.noclip then
        return
    end
    if pcall(beat) then
        engineErrors = 0
        return
    end
    engineErrors += 1
    if engineErrors >= CONFIG.engineErrorLimit then
        engineErrors = 0
        pcall(stopEngine)
        pcall(startEngine)
    end
end

--============================================================
-- 20 · LIFECYCLE
--============================================================

stopEngine = function()
    for _, connection in ipairs(engineConns) do
        connection:Disconnect()
    end
    table.clear(engineConns)
    if heartbeat then
        heartbeat:Disconnect()
        heartbeat = nil
    end
    disarmShield()
    if lastHumanoid then
        relaxHumanoid(lastHumanoid)
        lastHumanoid = nil
    end
    lastPosition = nil
    table.clear(history)
    endShove()
    restoreCharacter()
end

startEngine = function()
    local character = LocalPlayer.Character
    if not character then
        return false
    end
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    local root = character:FindFirstChild("HumanoidRootPart")
    if not humanoid or not root then
        return false
    end
    ensureGroup()
    table.clear(ghosted)
    ghostCharacter(character)
    hardenHumanoid(humanoid)
    claimOwnership(root)
    armShield(character, humanoid, root)
    lastHumanoid = humanoid
    engineConns[#engineConns + 1] = character.DescendantAdded:Connect(ghostPart)
    engineConns[#engineConns + 1] = humanoid.Died:Connect(function()
        stopEngine()
        if state.noclip then
            LocalPlayer:WaitForChild("Character", 10)
            task.wait(0.4)
            if state.noclip then
                startEngine()
            end
        end
    end)
    heartbeat = RunService.Heartbeat:Connect(onHeartbeat)
    return true
end

--============================================================
-- 21 · PAINT
--============================================================

local function paintNoclip()
    if state.noclip then
        noclipButton.BackgroundColor3 = CONFIG.colorOn
        noclipLabel.Text = CONFIG.noclipLabelActive
        statusLabel.Text = "active"
        statusLabel.TextColor3 = CONFIG.colorOn
    else
        noclipButton.BackgroundColor3 = CONFIG.colorOff
        noclipLabel.Text = CONFIG.noclipLabel
        statusLabel.Text = "idle"
        statusLabel.TextColor3 = CONFIG.colorMuted
    end
end

local function paintDrag()
    moveButton.BackgroundColor3 = state.dragMode and CONFIG.colorActive or CONFIG.colorButton
    if moveButtonStroke then
        moveButtonStroke.Transparency = state.dragMode and 0 or 0.4
    end
end

local function setNoclip(enabled)
    if state.noclip == enabled then
        return
    end
    if enabled then
        if startEngine() then
            state.noclip = true
        end
    else
        state.noclip = false
        stopEngine()
    end
    paintNoclip()
end

--============================================================
-- 22 · WIRING
--============================================================

local function wire()
    track(noclipButton.Activated:Connect(function()
        setNoclip(not state.noclip)
    end))
    track(moveButton.Activated:Connect(function()
        state.dragMode = not state.dragMode
        paintDrag()
    end))
    track(circleButton.Activated:Connect(function()
        toggleMode("circle")
    end))
    track(closeButton.Activated:Connect(function()
        toggleMode("collapsed")
    end))
    attachDrag(panel, panel, {
        condition = function()
            return UserInputService:GetMouseLocation().Y
                <= panel.AbsolutePosition.Y + CONFIG.headerHeight
        end,
    })
    attachDrag(panel, panel, {
        condition = function()
            return state.dragMode
        end,
    })
    attachDrag(dot, dot, {
        onEnd = function(moved)
            if moved < CONFIG.tapThreshold then
                applyMode("normal")
            end
        end,
    })
    track(Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
        local camera = Workspace.CurrentCamera
        if not camera then
            return
        end
        track(camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
            local target = (state.mode == "normal") and panel or dot
            local x, y = clampToScreen(target.Position.X.Offset, target.Position.Y.Offset,
                target.AbsoluteSize.X, target.AbsoluteSize.Y)
            target.Position = UDim2.fromOffset(x, y)
        end))
    end))
end

--============================================================
-- 23 · GUARD DOG
--============================================================

-- repairs the gui and the engine if either gets taken down
local function guardDog()
    task.spawn(function()
        while not state.destroyed do
            task.wait(0.5)
            if state.destroyed then
                break
            end
            if gui and gui.Parent == nil then
                pcall(function()
                    gui.Parent = guiParent()
                end)
            end
            if state.noclip and not heartbeat then
                pcall(stopEngine)
                pcall(startEngine)
            end
            if gui and not gui.Enabled then
                gui.Enabled = true
            end
        end
    end)
end

--============================================================
-- 24 · PUBLIC API
--============================================================

local api = {}
api.toggle = function() setNoclip(not state.noclip) end
api.on = function() setNoclip(true) end
api.off = function() setNoclip(false) end
api.circle = function() applyMode("circle") end
api.collapse = function() applyMode("collapsed") end
api.expand = function() applyMode("normal") end
api.destroy = function()
    if state.destroyed then
        return
    end
    state.destroyed = true
    state.noclip = false
    stopEngine()
    for _, connection in ipairs(connections) do
        connection:Disconnect()
    end
    table.clear(connections)
    if gui then
        gui:Destroy()
    end
    getgenv().NoClip = nil
end

--============================================================
-- 25 · BOOT
--============================================================

local function boot()
    local old = getgenv().NoClip
    if old and old.destroy then
        pcall(old.destroy)
    end
    buildGui()
    paintNoclip()
    paintDrag()
    wire()
    guardDog()
    getgenv().NoClip = api
    track(LocalPlayer.CharacterAdded:Connect(function(character)
        if not state.noclip then
            return
        end
        character:WaitForChild("HumanoidRootPart", 10)
        task.wait(0.4)
        if state.noclip then
            startEngine()
        end
    end))
end

boot()
--[[
════════════════════════════════════════════════════════════
   N O C L I P   ·   h a r d   m o d e   5   ·   e x p l o i t
   ------------------------------------------------------------
   file    : noclip.lua
   author  : supercaptain1233
   target  : Delta (Android) · universal · any Roblox game
   version : 5.0.0
   ------------------------------------------------------------
   panel   : Noclip header, X collapse, move toggle, circle dot
   noclip  : double collision layer, measured exit, pre-physics
             CFrame pass, history guard, floor hover
   exploit : the game's own blind spots are used against it, not
             just its properties reverted
   ------------------------------------------------------------
   no print() calls in this file
   ════════════════════════════════════════════════════════════
]]


--============================================================
-- 01 · CONFIG
--============================================================

local CONFIG = {
    panelWidth = 190, panelHeight = 148, panelX = 24, panelY = 88, cornerRadius = 10,
    headerHeight = 30, headerGap = 4, title = "Noclip", titleSize = 13,
    headerButtonSize = 24, bodyPadding = 12, noclipHeight = 54, noclipTextSize = 15,
    noclipLabel = "NOCLIP", noclipLabelActive = "NOCLIP: ON",
    dotCircleSize = 46, dotCollapsedSize = 30, dotLetter = "N",
    colorPanel = Color3.fromRGB(19, 22, 28), colorHeader = Color3.fromRGB(28, 32, 40),
    colorBody = Color3.fromRGB(15, 17, 22), colorButton = Color3.fromRGB(44, 49, 60),
    colorButtonHover = Color3.fromRGB(60, 67, 82), colorActive = Color3.fromRGB(64, 110, 74),
    colorOff = Color3.fromRGB(224, 49, 49), colorOn = Color3.fromRGB(45, 168, 88),
    colorText = Color3.fromRGB(235, 238, 243), colorMuted = Color3.fromRGB(120, 128, 140),
    colorStroke = Color3.fromRGB(52, 58, 70),
    hoverHeight = 0.25, stickRange = 16, stickStiffness = 14, maxStickSpeed = 55,
    ghostGroup = "NoClipGhost", ghostRefreshRate = 6, ghostBurstFrames = 45,
    probeSize = 1.4, shoveStep = 0.6, shoveLimit = 14, shoveSpeed = 30,
    shoveClearance = 1.2, shoveMaxFrames = 48, shoveCooldown = 0.2, shoveDrift = 2.5,
    freezeFrames = 5, guardDistance = 3.5, guardHistory = 14, guardMaxPerSecond = 8,
    fallProbe = 60, fallMargin = 3, stuckFrames = 9, stuckEpsilon = 0.35,
    pollInterval = 0.4, tapThreshold = 8, screenPadding = 4, engineErrorLimit = 30,
    displayOrder = 9999, guiName = "NoClipUI",
}

--============================================================
-- 02 · SERVICES
--============================================================

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local PhysicsService = game:GetService("PhysicsService")
local Workspace = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer
if not LocalPlayer then
    Players:GetPropertyChangedSignal("LocalPlayer"):Wait()
    LocalPlayer = Players.LocalPlayer
end

--============================================================
-- 03 · UTILITIES
--============================================================

local function new(class, props, children)
    local inst = Instance.new(class)
    local parent = props and props.Parent
    if props then
        for key, value in pairs(props) do
            if key ~= "Parent" then
                inst[key] = value
            end
        end
    end
    for _, child in ipairs(children or {}) do
        child.Parent = inst
    end
    if parent then
        inst.Parent = parent
    end
    return inst
end

local function round(inst, radius)
    new("UICorner", { CornerRadius = UDim.new(0, radius or 8), Parent = inst })
    return inst
end

local function stroke(inst, colour, thickness, transparency)
    new("UIStroke", {
        Color = colour or CONFIG.colorStroke, Thickness = thickness or 1,
        Transparency = transparency or 0, Parent = inst,
    })
    return inst
end

local function clampToScreen(x, y, width, height)
    local camera = Workspace.CurrentCamera
    local vp = camera and camera.ViewportSize or Vector2.new(1080, 1920)
    local edge = CONFIG.screenPadding
    return math.clamp(x, edge, math.max(edge, vp.X - width - edge)),
        math.clamp(y, edge, math.max(edge, vp.Y - height - edge))
end

local function guiParent()
    local ok, hidden = pcall(function()
        return gethui and gethui() or nil
    end)
    return (ok and hidden) or LocalPlayer:WaitForChild("PlayerGui")
end

local function horizontal(vector)
    return Vector3.new(vector.X, 0, vector.Z)
end

local function flatLook(cframe)
    local flat = horizontal(cframe.LookVector)
    return flat.Magnitude < 0.01 and Vector3.new(0, 0, -1) or flat.Unit
end

--============================================================
-- 04 · STATE
--============================================================

local state = { mode = "normal", dragMode = false, noclip = false, destroyed = false }
local panel, dot, dotGlyph, dotLetter
local noclipButton, noclipLabel, statusLabel
local moveButton, moveButtonStroke, circleButton, circleButtonStroke
local closeButton, gui

local connections = {}
local function track(connection)
    connections[#connections + 1] = connection
    return connection
end

local shield = { hooks = {}, gravity = 0, walk = 0, jump = 0, hip = 0, size = nil }
local engineErrors = 0
local pollClock = 0

--============================================================
-- 05 · ICONS
--============================================================

local function buildMoveIcon(parent)
    local wrap = new("Frame", {
        Name = "MoveIcon", Parent = parent, BackgroundTransparency = 1,
        Size = UDim2.fromOffset(16, 16), Position = UDim2.fromScale(0.5, 0.5),
        AnchorPoint = Vector2.new(0.5, 0.5),
    })
    local glyphs = {
        { text = "\u{2191}", x = 0, y = 0 }, { text = "\u{2190}", x = 0, y = 5.5 },
        { text = "\u{2192}", x = 8, y = 5.5 }, { text = "\u{2193}", x = 0, y = 11 },
    }
    for _, glyph in ipairs(glyphs) do
        new("TextLabel", {
            Parent = wrap, BackgroundTransparency = 1, Text = glyph.text,
            Size = UDim2.fromOffset(8, 5), Position = UDim2.fromOffset(glyph.x, glyph.y),
            TextSize = 8, Font = Enum.Font.GothamBold, TextColor3 = CONFIG.colorText,
        })
    end
end

local function buildCircleIcon(parent)
    local ring = new("Frame", {
        Name = "Ring", Parent = parent, BackgroundTransparency = 1, BorderSizePixel = 0,
        Size = UDim2.fromOffset(11, 11), Position = UDim2.fromScale(0.5, 0.5),
        AnchorPoint = Vector2.new(0.5, 0.5),
    })
    round(ring, 11)
    stroke(ring, CONFIG.colorText, 1.4, 0)
end

--============================================================
-- 06 · GUI
--============================================================

local function buildGui()
    gui = new("ScreenGui", {
        Name = CONFIG.guiName, ResetOnSpawn = false, IgnoreGuiInset = true,
        DisplayOrder = CONFIG.displayOrder, Parent = guiParent(),
    })
    panel = new("Frame", {
        Name = "Panel", Parent = gui, ClipsDescendants = true, BorderSizePixel = 0,
        Size = UDim2.fromOffset(CONFIG.panelWidth, CONFIG.panelHeight),
        Position = UDim2.fromOffset(CONFIG.panelX, CONFIG.panelY),
        BackgroundColor3 = CONFIG.colorPanel,
    })
    round(panel, CONFIG.cornerRadius)
    stroke(panel, CONFIG.colorStroke, 1, 0.25)
    local header = new("Frame", {
        Name = "Header", Parent = panel, BorderSizePixel = 0,
        Size = UDim2.new(1, 0, 0, CONFIG.headerHeight), BackgroundColor3 = CONFIG.colorHeader,
    })
    new("TextLabel", {
        Name = "Title", Parent = header, BackgroundTransparency = 1,
        Size = UDim2.new(1, -104, 1, 0), Position = UDim2.fromOffset(10, 0),
        Text = CONFIG.title, TextSize = CONFIG.titleSize, Font = Enum.Font.GothamBold,
        TextColor3 = CONFIG.colorText, TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Center,
    })
    local row = new("Frame", {
        Name = "Buttons", Parent = header, BackgroundTransparency = 1,
        Size = UDim2.new(0, 80, 1, 0), Position = UDim2.new(1, -6, 0, 0),
        AnchorPoint = Vector2.new(1, 0),
    })
    new("UIListLayout", {
        Parent = row, FillDirection = Enum.FillDirection.Horizontal,
        HorizontalAlignment = Enum.HorizontalAlignment.Right,
        VerticalAlignment = Enum.VerticalAlignment.Center,
        Padding = UDim.new(0, CONFIG.headerGap),
    })
    circleButton = new("TextButton", {
        Name = "CircleButton", Parent = row, LayoutOrder = 1, Text = "",
        Size = UDim2.fromOffset(CONFIG.headerButtonSize, CONFIG.headerButtonSize),
        BackgroundColor3 = CONFIG.colorButton, BorderSizePixel = 0, AutoButtonColor = false,
    })
    round(circleButton, 6)
    circleButtonStroke = stroke(circleButton, CONFIG.colorStroke, 1, 0.4)
    buildCircleIcon(circleButton)
    moveButton = new("TextButton", {
        Name = "MoveButton", Parent = row, LayoutOrder = 2, Text = "",
        Size = UDim2.fromOffset(CONFIG.headerButtonSize, CONFIG.headerButtonSize),
        BackgroundColor3 = CONFIG.colorButton, BorderSizePixel = 0, AutoButtonColor = false,
    })
    round(moveButton, 6)
    moveButtonStroke = stroke(moveButton, CONFIG.colorStroke, 1, 0.4)
    buildMoveIcon(moveButton)
    closeButton = new("TextButton", {
        Name = "CloseButton", Parent = row, LayoutOrder = 3, BorderSizePixel = 0,
        Size = UDim2.fromOffset(CONFIG.headerButtonSize, CONFIG.headerButtonSize),
        BackgroundColor3 = CONFIG.colorButton, Text = "\u{2715}", TextSize = 12,
        Font = Enum.Font.GothamBold, TextColor3 = CONFIG.colorText, AutoButtonColor = false,
    })
    round(closeButton, 6)
    stroke(closeButton, CONFIG.colorStroke, 1, 0.4)
    local body = new("Frame", {
        Name = "Body", Parent = panel, BorderSizePixel = 0,
        Size = UDim2.new(1, 0, 1, -CONFIG.headerHeight),
        Position = UDim2.fromOffset(0, CONFIG.headerHeight),
        BackgroundColor3 = CONFIG.colorBody,
    })
    new("UIPadding", {
        Parent = body, PaddingTop = UDim.new(0, CONFIG.bodyPadding),
        PaddingLeft = UDim.new(0, CONFIG.bodyPadding),
        PaddingRight = UDim.new(0, CONFIG.bodyPadding), PaddingBottom = UDim.new(0, 8),
    })
    new("UIListLayout", {
        Parent = body, FillDirection = Enum.FillDirection.Vertical,
        HorizontalAlignment = Enum.HorizontalAlignment.Center,
        VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 8),
    })
    noclipButton = new("TextButton", {
        Name = "NoclipButton", Parent = body, LayoutOrder = 1, Text = "",
        Size = UDim2.new(1, 0, 0, CONFIG.noclipHeight),
        BackgroundColor3 = CONFIG.colorOff, BorderSizePixel = 0, AutoButtonColor = false,
    })
    round(noclipButton, 8)
    stroke(noclipButton, Color3.fromRGB(255, 255, 255), 1, 0.75)
    noclipLabel = new("TextLabel", {
        Name = "Label", Parent = noclipButton, BackgroundTransparency = 1,
        Size = UDim2.fromScale(1, 1), Text = CONFIG.noclipLabel,
        TextSize = CONFIG.noclipTextSize, Font = Enum.Font.GothamBold,
        TextColor3 = Color3.fromRGB(255, 255, 255),
    })
    statusLabel = new("TextLabel", {
        Name = "Status", Parent = body, LayoutOrder = 2, BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 0, 14), Text = "idle", TextSize = 11,
        Font = Enum.Font.Gotham, TextColor3 = CONFIG.colorMuted,
        TextXAlignment = Enum.TextXAlignment.Center,
    })
    dot = new("TextButton", {
        Name = "Dot", Parent = gui, Visible = false, Text = "",
        Size = UDim2.fromOffset(CONFIG.dotCircleSize, CONFIG.dotCircleSize),
        Position = UDim2.fromOffset(CONFIG.panelX, CONFIG.panelY),
        BackgroundColor3 = CONFIG.colorPanel, BorderSizePixel = 0, AutoButtonColor = false,
    })
    round(dot, 1)
    stroke(dot, CONFIG.colorStroke, 1, 0.2)
    dotGlyph = new("Frame", {
        Name = "Glyph", Parent = dot, BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1),
    })
    buildCircleIcon(dotGlyph)
    dotLetter = new("TextLabel", {
        Name = "Letter", Parent = dot, BackgroundTransparency = 1,
        Size = UDim2.fromScale(1, 1), Text = CONFIG.dotLetter, TextSize = 13,
        Font = Enum.Font.GothamBold, TextColor3 = CONFIG.colorText, Visible = false,
    })
end

--============================================================
-- 07 · MODES
--============================================================

local function applyMode(mode)
    state.mode = mode
    if mode == "normal" then
        dot.Visible = false
        panel.Visible = true
        panel.Position = dot.Position
        local x, y = clampToScreen(panel.Position.X.Offset, panel.Position.Y.Offset,
            panel.AbsoluteSize.X, panel.AbsoluteSize.Y)
        panel.Position = UDim2.fromOffset(x, y)
        return
    end
    local size = (mode == "circle") and CONFIG.dotCircleSize or CONFIG.dotCollapsedSize
    dot.Size = UDim2.fromOffset(size, size)
    dotGlyph.Visible = (mode == "circle")
    dotLetter.Visible = (mode == "collapsed")
    local x, y = clampToScreen(panel.Position.X.Offset, panel.Position.Y.Offset, size, size)
    dot.Position = UDim2.fromOffset(x, y)
    panel.Visible = false
    dot.Visible = true
end

local function toggleMode(mode)
    applyMode(state.mode == mode and "normal" or mode)
end

--============================================================
-- 08 · DRAG
--============================================================

local function attachDrag(handle, target, options)
    options = options or {}
    track(handle.InputBegan:Connect(function(input)
        if input.UserInputType ~= Enum.UserInputType.MouseButton1
            and input.UserInputType ~= Enum.UserInputType.Touch then
            return
        end
        if options.condition and not options.condition() then
            return
        end
        local origin, startPos, moved = input.Position, target.Position, 0
        local watcher
        watcher = input.Changed:Connect(function()
            local delta = input.Position - origin
            moved = math.max(moved, delta.Magnitude)
            local x, y = clampToScreen(startPos.X.Offset + delta.X, startPos.Y.Offset + delta.Y,
                target.AbsoluteSize.X, target.AbsoluteSize.Y)
            target.Position = UDim2.fromOffset(x, y)
        end)
        input.Ended:Connect(function()
            if watcher then
                watcher:Disconnect()
            end
            if options.onEnd then
                options.onEnd(moved)
            end
        end)
    end))
end

--============================================================
-- 09 · ENGINE STATE
--============================================================

local stopEngine, startEngine
local ghosted, ghostHooks, engineConns = {}, {}, {}
local heartbeat, preStep, frameClock = nil, nil, 0
local lastPosition, guardClock, guardCount = nil, 0, 0
local freezeClock, shoveClock, lastHumanoid = 0, 0, nil
local history, stuckClock, stuckAnchor = {}, 0, nil
local shove = { active = false, direction = Vector3.zero, target = Vector3.zero,
    frames = 0, last = Vector3.zero }

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.IgnoreWater = true
rayParams.RespectCanCollide = false

local probeParams = OverlapParams.new()
probeParams.FilterType = Enum.RaycastFilterType.Exclude
probeParams.RespectCanCollide = false

local DISABLED_STATES = {
    Enum.HumanoidStateType.FallingDown, Enum.HumanoidStateType.Ragdoll,
    Enum.HumanoidStateType.GettingUp, Enum.HumanoidStateType.StrafingNoPhysics,
    Enum.HumanoidStateType.PlatformStanding,
}

--============================================================
-- 10 · COLLISION LAYER
--============================================================

-- second, independent layer. even if a game re-stamps CanCollide or
-- resets a part's group, the ghost group collides with nothing
local groupReady = false

local function ensureGroup()
    if groupReady then
        return true
    end
    if not pcall(function()
        PhysicsService:RegisterCollisionGroup(CONFIG.ghostGroup)
    end) then
        return false
    end
    groupReady = true
    pollGroups()
    return true
end

-- their side can call CollisionGroupSetCollidable to undo the layer, so
-- the pairs are re-pressed on a timer instead of trusted once
function pollGroups()
    if not groupReady then
        return
    end
    local ok, groups = pcall(function()
        return PhysicsService:GetCollisionGroups()
    end)
    if not ok or not groups then
        return
    end
    for _, group in ipairs(groups) do
        if group.name ~= CONFIG.ghostGroup then
            pcall(function()
                PhysicsService:CollisionGroupSetCollidable(CONFIG.ghostGroup, group.name, false)
            end)
        end
    end
end

--============================================================
-- 11 · GHOSTING
--============================================================

local function ghostPart(part)
    if not part:IsA("BasePart") then
        return
    end
    if ghosted[part] == nil then
        ghosted[part] = {
            collide = part.CanCollide, group = part.CollisionGroup,
            query = part.CanQuery, touch = part.CanTouch, anchor = part.Anchored,
        }
    end
    if part.CanCollide then
        part.CanCollide = false
    end
    if part.Anchored then
        part.Anchored = false
    end
    if groupReady and part.CollisionGroup ~= CONFIG.ghostGroup then
        part.CollisionGroup = CONFIG.ghostGroup
    end
    -- query off: their raycasts and box checks skip us entirely
    -- touch on: their trigger volumes still fire on us
    if part.CanQuery then
        part.CanQuery = false
    end
    if not part.CanTouch then
        part.CanTouch = true
    end
    if not ghostHooks[part] then
        ghostHooks[part] = {
            part:GetPropertyChangedSignal("CanCollide"):Connect(function()
                if state.noclip and part.CanCollide then
                    part.CanCollide = false
                end
            end),
            part:GetPropertyChangedSignal("CollisionGroup"):Connect(function()
                if state.noclip and groupReady and part.CollisionGroup ~= CONFIG.ghostGroup then
                    part.CollisionGroup = CONFIG.ghostGroup
                end
            end),
            part:GetPropertyChangedSignal("CanQuery"):Connect(function()
                if state.noclip and part.CanQuery then
                    part.CanQuery = false
                end
            end),
            part:GetPropertyChangedSignal("CanTouch"):Connect(function()
                if state.noclip and not part.CanTouch then
                    part.CanTouch = true
                end
            end),
            part:GetPropertyChangedSignal("Anchored"):Connect(function()
                if state.noclip and part.Anchored then
                    part.Anchored = false
                end
            end),
        }
    end
end

local function ghostCharacter(character)
    for _, descendant in ipairs(character:GetDescendants()) do
        ghostPart(descendant)
    end
end

local function clearGhostHooks()
    for part, hooks in pairs(ghostHooks) do
        for _, connection in ipairs(hooks) do
            connection:Disconnect()
        end
        ghostHooks[part] = nil
    end
end

local function restoreCharacter()
    clearGhostHooks()
    for part, saved in pairs(ghosted) do
        if part and part.Parent then
            pcall(function()
                part.CanCollide = saved.collide
                part.CollisionGroup = saved.group
                part.CanQuery = saved.query
                part.CanTouch = saved.touch
                part.Anchored = saved.anchor
            end)
        end
    end
    table.clear(ghosted)
end

--============================================================
-- 12 · HUMANOID HARDENING
--============================================================

local function hardenHumanoid(humanoid)
    humanoid.RequiresNeck = false
    humanoid.BreakJointsOnDeath = false
    for _, humanoidState in ipairs(DISABLED_STATES) do
        pcall(function()
            humanoid:SetStateEnabled(humanoidState, false)
        end)
    end
end

local function relaxHumanoid(humanoid)
    for _, humanoidState in ipairs(DISABLED_STATES) do
        pcall(function()
            humanoid:SetStateEnabled(humanoidState, true)
        end)
    end
end

local function claimOwnership(root)
    pcall(function()
        root:SetNetworkOwner(LocalPlayer)
    end)
end

--============================================================
-- 13 · SHIELD
--============================================================

local function shieldProp(inst, prop, fix)
    shield.hooks[inst] = shield.hooks[inst] or {}
    if shield.hooks[inst][prop] then
        return
    end
    shield.hooks[inst][prop] = inst:GetPropertyChangedSignal(prop):Connect(function()
        if state.noclip and not state.destroyed then
            pcall(fix)
        end
    end)
end

local function armShield(character, humanoid, root)
    shield.gravity, shield.walk = Workspace.Gravity, humanoid.WalkSpeed
    shield.jump, shield.hip = humanoid.JumpPower, humanoid.HipHeight
    shield.size = root.Size
    shieldProp(root, "Anchored", function() if root.Anchored then root.Anchored = false end end)
    shieldProp(root, "Massless", function() if not root.Massless then root.Massless = true end end)
    shieldProp(root, "Size", function()
        if root.Size ~= shield.size then
            root.Size = shield.size
        end
    end)
    shieldProp(humanoid, "PlatformStand",
        function() if humanoid.PlatformStand then humanoid.PlatformStand = false end end)
    shieldProp(humanoid, "Sit", function()
        if humanoid.Sit and humanoid.SeatPart == nil then
            humanoid.Sit = false
        end
    end)
    shieldProp(humanoid, "RequiresNeck",
        function() if humanoid.RequiresNeck then humanoid.RequiresNeck = false end end)
    shieldProp(humanoid, "AutoRotate",
        function() if not humanoid.AutoRotate then humanoid.AutoRotate = true end end)
    shieldProp(humanoid, "EvaluateStateMachine", function()
        if not humanoid.EvaluateStateMachine then
            humanoid.EvaluateStateMachine = true
        end
    end)
    shieldProp(humanoid, "WalkSpeed", function()
        if humanoid.WalkSpeed <= 0 and shield.walk > 0 then
            humanoid.WalkSpeed = shield.walk
        end
    end)
    shieldProp(humanoid, "JumpPower", function()
        if humanoid.JumpPower <= 0 and shield.jump > 0 then
            humanoid.JumpPower = shield.jump
        end
    end)
    shieldProp(humanoid, "HipHeight", function()
        if shield.hip > 0 and math.abs(humanoid.HipHeight - shield.hip) > 0.5 then
            humanoid.HipHeight = shield.hip
        end
    end)
    shieldProp(Workspace, "Gravity",
        function() if Workspace.Gravity < 1 then Workspace.Gravity = shield.gravity end end)
    shieldProp(character, "Parent", function()
        if character.Parent ~= Workspace and character.Parent then
            character.Parent = Workspace
        end
    end)
    shieldProp(character, "PrimaryPart", function()
        if character.PrimaryPart ~= root then
            character.PrimaryPart = root
        end
    end)
end

local function disarmShield()
    for inst, props in pairs(shield.hooks) do
        for _, connection in pairs(props) do
            connection:Disconnect()
        end
        shield.hooks[inst] = nil
    end
end

--============================================================
-- 14 · PENETRATION
--============================================================

local function embeddedAt(position)
    local size = Vector3.new(CONFIG.probeSize, CONFIG.probeSize, CONFIG.probeSize)
    for _, part in ipairs(Workspace:GetPartBoundsInBox(CFrame.new(position), size, probeParams)) do
        if part.CanCollide then
            return true
        end
    end
    return false
end

local function shoveDirection(root, humanoid)
    local move = humanoid.MoveDirection
    if move.Magnitude > 0.05 then
        return horizontal(move).Unit
    end
    return flatLook(root.CFrame)
end

local function findExit(root, direction)
    local origin, travelled = root.Position, 0
    while travelled < CONFIG.shoveLimit do
        travelled += CONFIG.shoveStep
        if not embeddedAt(origin + direction * travelled) then
            return travelled
        end
    end
    return CONFIG.shoveLimit
end

local function beginShove(root, humanoid)
    local now = os.clock()
    if now - shoveClock < CONFIG.shoveCooldown then
        return false
    end
    local direction = shoveDirection(root, humanoid)
    shove.active = true
    shove.direction = direction
    shove.target = root.Position + direction * (findExit(root, direction) + CONFIG.shoveClearance)
    shove.frames, shove.last, shoveClock = 0, root.Position, now
    return true
end

local function endShove()
    shove.active = false
    shove.frames = 0
    shove.direction = Vector3.zero
end

--============================================================
-- 15 · SHOVE STEP
--============================================================

local function stepShove(root)
    if not shove.active then
        return
    end
    shove.frames += 1
    if shove.frames > CONFIG.shoveMaxFrames then
        endShove()
        return
    end
    if horizontal(root.Position - shove.last).Magnitude > CONFIG.shoveDrift then
        shove.target = root.Position + shove.direction * CONFIG.shoveClearance
    end
    shove.last = root.Position
    local flat = horizontal(shove.target - root.Position)
    if flat.Magnitude <= 0.2 then
        endShove()
        return
    end
    local speed = (os.clock() < freezeClock) and CONFIG.shoveSpeed * 0.5 or CONFIG.shoveSpeed
    root.CFrame = root.CFrame + flat.Unit * math.min(speed / 60, flat.Magnitude)
    root.AssemblyLinearVelocity = flat.Unit * speed
    if shove.frames == 1 then
        freezeClock = os.clock() + (CONFIG.freezeFrames / 60)
    end
end

--============================================================
-- 16 · POSITION GUARD
--============================================================

local function guardPosition(root, direction)
    local now = os.clock()
    if now - guardClock > 1 then
        guardCount = 0
    end
    local current = root.Position
    history[#history + 1] = current
    if #history > CONFIG.guardHistory then
        table.remove(history, 1)
    end
    if not lastPosition then
        lastPosition = current
        return
    end
    local flat = horizontal(current - lastPosition)
    if flat.Magnitude < CONFIG.guardDistance then
        lastPosition = current
        return
    end
    if flat.Unit:Dot(direction) > -0.2 or guardCount >= CONFIG.guardMaxPerSecond then
        lastPosition = current
        return
    end
    guardCount += 1
    local restore = history[math.max(1, #history - 2)] or lastPosition
    local keep = root.CFrame - root.Position
    root.CFrame = CFrame.new(restore) * keep
    root.AssemblyLinearVelocity = Vector3.zero
    lastPosition = restore
end

--============================================================
-- 17 · FLOOR
--============================================================

local function hoverStep(root, humanoid, velocity)
    local hip = humanoid.HipHeight or 0
    local offset = (root.Size.Y * 0.5) + hip + CONFIG.hoverHeight
    local result = Workspace:Raycast(root.Position,
        Vector3.new(0, -(CONFIG.stickRange + offset), 0), rayParams)
    if not result then
        return false
    end
    local difference = (result.Position.Y + offset) - root.Position.Y
    if math.abs(difference) < 0.02 then
        root.AssemblyLinearVelocity = Vector3.new(velocity.X, 0, velocity.Z)
    else
        local correction = math.clamp(difference * CONFIG.stickStiffness,
            -CONFIG.maxStickSpeed, CONFIG.maxStickSpeed)
        root.AssemblyLinearVelocity = Vector3.new(velocity.X, correction, velocity.Z)
    end
    return true
end

local function fallClamp(root, velocity)
    local result = Workspace:Raycast(root.Position, Vector3.new(0, -CONFIG.fallProbe, 0), rayParams)
    if not result or result.Distance > math.abs(velocity.Y) / 60 + CONFIG.fallMargin then
        return
    end
    local stop = result.Position.Y + (root.Size.Y * 0.5) + CONFIG.hoverHeight
    if root.Position.Y - stop < 1 then
        root.AssemblyLinearVelocity = Vector3.new(velocity.X, 0, velocity.Z)
    end
end

--============================================================
-- 18 · STUCK BREAKER
--============================================================

local function checkStuck(root, humanoid)
    if humanoid.MoveDirection.Magnitude < 0.05 then
        stuckAnchor, stuckClock = root.Position, 0
        return false
    end
    if not stuckAnchor then
        stuckAnchor = root.Position
        return false
    end
    if horizontal(root.Position - stuckAnchor).Magnitude > CONFIG.stuckEpsilon then
        stuckAnchor, stuckClock = root.Position, 0
        return false
    end
    stuckClock += 1
    if stuckClock >= CONFIG.stuckFrames then
        stuckClock, stuckAnchor = 0, root.Position
        return true
    end
    return false
end

--============================================================
-- 19 · PRE-PHYSICS STEP
--============================================================

-- RunService.Stepped fires before the solver integrates, so the value
-- written here is the one physics starts from. the solver never gets a
-- chance to integrate a position the game already considers wrong
local function applyStep()
    if not state.noclip then
        return
    end
    local character = LocalPlayer.Character
    if not character then
        return
    end
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    local root = character:FindFirstChild("HumanoidRootPart")
    if not humanoid or not root or root.Parent ~= character then
        return
    end
    if root.Anchored then
        root.Anchored = false
    end
    if humanoid.PlatformStand then
        humanoid.PlatformStand = false
    end
    if shove.active then
        stepShove(root)
        return
    end
    local okState, humanoidState = pcall(function()
        return humanoid:GetState()
    end)
    if not okState then
        return
    end
    if humanoidState == Enum.HumanoidStateType.Swimming
        or humanoidState == Enum.HumanoidStateType.Climbing
        or humanoidState == Enum.HumanoidStateType.Seated then
        return
    end
    local velocity = root.AssemblyLinearVelocity
    if humanoidState == Enum.HumanoidStateType.Jumping or velocity.Y > 2 then
        return
    end
    hoverStep(root, humanoid, velocity)
end

--============================================================
-- 20 · SENSE
--============================================================

local function sense()
    local character = LocalPlayer.Character
    if not character or not character.Parent then
        return
    end
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    local root = character:FindFirstChild("HumanoidRootPart")
    if not humanoid or not root or root.Parent ~= character then
        return
    end
    frameClock += 1
    if frameClock <= CONFIG.ghostBurstFrames or frameClock % CONFIG.ghostRefreshRate == 0 then
        ghostCharacter(character)
        claimOwnership(root)
    end
    rayParams.FilterDescendantsInstances = { character }
    probeParams.FilterDescendantsInstances = { character }
    local okState, humanoidState = pcall(function()
        return humanoid:GetState()
    end)
    if not okState then
        humanoidState = nil
    end
    local velocity = root.AssemblyLinearVelocity
    local direction = shoveDirection(root, humanoid)
    if humanoidState == Enum.HumanoidStateType.Swimming
        or humanoidState == Enum.HumanoidStateType.Climbing
        or humanoidState == Enum.HumanoidStateType.Seated then
        return
    end
    guardPosition(root, direction)
    if shove.active then
        return
    end
    if embeddedAt(root.Position) then
        beginShove(root, humanoid)
        return
    end
    if checkStuck(root, humanoid) then
        beginShove(root, humanoid)
        return
    end
    if humanoidState == Enum.HumanoidStateType.Jumping or velocity.Y > 2 then
        fallClamp(root, velocity)
        return
    end
    -- holding a grounded state keeps FloorMaterial off Air, which is the
    -- single most common "is this player falling" check
    if humanoidState == Enum.HumanoidStateType.Freefall then
        pcall(function()
            humanoid:ChangeState(Enum.HumanoidStateType.Running)
        end)
    end
end

local function onHeartbeat()
    if not state.noclip then
        return
    end
    local now = os.clock()
    if now - pollClock > CONFIG.pollInterval then
        pollClock = now
        pollGroups()
    end
    if pcall(sense) then
        engineErrors = 0
        return
    end
    engineErrors += 1
    if engineErrors >= CONFIG.engineErrorLimit then
        engineErrors = 0
        pcall(stopEngine)
        pcall(startEngine)
    end
end

--============================================================
-- 21 · LIFECYCLE
--============================================================

stopEngine = function()
    for _, connection in ipairs(engineConns) do
        connection:Disconnect()
    end
    table.clear(engineConns)
    if heartbeat then
        heartbeat:Disconnect()
        heartbeat = nil
    end
    if preStep then
        preStep:Disconnect()
        preStep = nil
    end
    disarmShield()
    if lastHumanoid then
        relaxHumanoid(lastHumanoid)
        lastHumanoid = nil
    end
    lastPosition = nil
    table.clear(history)
    endShove()
    restoreCharacter()
end

startEngine = function()
    local character = LocalPlayer.Character
    if not character then
        return false
    end
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    local root = character:FindFirstChild("HumanoidRootPart")
    if not humanoid or not root then
        return false
    end
    ensureGroup()
    table.clear(ghosted)
    ghostCharacter(character)
    hardenHumanoid(humanoid)
    claimOwnership(root)
    armShield(character, humanoid, root)
    lastHumanoid = humanoid
    engineConns[#engineConns + 1] = character.DescendantAdded:Connect(ghostPart)
    engineConns[#engineConns + 1] = humanoid.Died:Connect(function()
        stopEngine()
        if state.noclip then
            LocalPlayer:WaitForChild("Character", 10)
            task.wait(0.4)
            if state.noclip then
                startEngine()
            end
        end
    end)
    preStep = RunService.Stepped:Connect(function()
        pcall(applyStep)
    end)
    heartbeat = RunService.Heartbeat:Connect(onHeartbeat)
    return true
end

--============================================================
-- 22 · PAINT
--============================================================

local function paintNoclip()
    if state.noclip then
        noclipButton.BackgroundColor3 = CONFIG.colorOn
        noclipLabel.Text = CONFIG.noclipLabelActive
        statusLabel.Text = "active"
        statusLabel.TextColor3 = CONFIG.colorOn
    else
        noclipButton.BackgroundColor3 = CONFIG.colorOff
        noclipLabel.Text = CONFIG.noclipLabel
        statusLabel.Text = "idle"
        statusLabel.TextColor3 = CONFIG.colorMuted
    end
end

local function paintDrag()
    moveButton.BackgroundColor3 = state.dragMode and CONFIG.colorActive or CONFIG.colorButton
    if moveButtonStroke then
        moveButtonStroke.Transparency = state.dragMode and 0 or 0.4
    end
end

local function setNoclip(enabled)
    if state.noclip == enabled then
        return
    end
    if enabled then
        if startEngine() then
            state.noclip = true
        end
    else
        state.noclip = false
        stopEngine()
    end
    paintNoclip()
end

--============================================================
-- 23 · WIRING
--============================================================

local function wire()
    track(noclipButton.Activated:Connect(function()
        setNoclip(not state.noclip)
    end))
    track(moveButton.Activated:Connect(function()
        state.dragMode = not state.dragMode
        paintDrag()
    end))
    track(circleButton.Activated:Connect(function()
        toggleMode("circle")
    end))
    track(closeButton.Activated:Connect(function()
        toggleMode("collapsed")
    end))
    attachDrag(panel, panel, {
        condition = function()
            return UserInputService:GetMouseLocation().Y
                <= panel.AbsolutePosition.Y + CONFIG.headerHeight
        end,
    })
    attachDrag(panel, panel, {
        condition = function()
            return state.dragMode
        end,
    })
    attachDrag(dot, dot, {
        onEnd = function(moved)
            if moved < CONFIG.tapThreshold then
                applyMode("normal")
            end
        end,
    })
    track(Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
        local camera = Workspace.CurrentCamera
        if not camera then
            return
        end
        track(camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
            local target = (state.mode == "normal") and panel or dot
            local x, y = clampToScreen(target.Position.X.Offset, target.Position.Y.Offset,
                target.AbsoluteSize.X, target.AbsoluteSize.Y)
            target.Position = UDim2.fromOffset(x, y)
        end))
    end))
end

--============================================================
-- 24 · GUARD DOG
--============================================================

local function guardDog()
    task.spawn(function()
        while not state.destroyed do
            task.wait(0.5)
            if state.destroyed then
                break
            end
            if gui and gui.Parent == nil then
                pcall(function()
                    gui.Parent = guiParent()
                end)
            end
            if gui and not gui.Enabled then
                gui.Enabled = true
            end
            if state.noclip and not heartbeat then
                pcall(stopEngine)
                pcall(startEngine)
            end
        end
    end)
end

--============================================================
-- 25 · PUBLIC API
--============================================================

local api = {}
api.toggle = function() setNoclip(not state.noclip) end
api.on = function() setNoclip(true) end
api.off = function() setNoclip(false) end
api.circle = function() applyMode("circle") end
api.collapse = function() applyMode("collapsed") end
api.expand = function() applyMode("normal") end
api.destroy = function()
    if state.destroyed then
        return
    end
    state.destroyed = true
    state.noclip = false
    stopEngine()
    for _, connection in ipairs(connections) do
        connection:Disconnect()
    end
    table.clear(connections)
    if gui then
        gui:Destroy()
    end
    getgenv().NoClip = nil
end

--============================================================
-- 26 · BOOT
--============================================================

local function boot()
    local old = getgenv().NoClip
    if old and old.destroy then
        pcall(old.destroy)
    end
    buildGui()
    paintNoclip()
    paintDrag()
    wire()
    guardDog()
    getgenv().NoClip = api
    track(LocalPlayer.CharacterAdded:Connect(function(character)
        if not state.noclip then
            return
        end
        character:WaitForChild("HumanoidRootPart", 10)
        task.wait(0.4)
        if state.noclip then
            startEngine()
        end
    end))
end

boot()
--[[
════════════════════════════════════════════════════════════
   N O C L I P   ·   h a r d   m o d e   6   ·   c o l l i s i o n
   ------------------------------------------------------------
   file    : noclip.lua
   author  : supercaptain1233
   target  : Delta (Android) · universal · any Roblox game
   version : 6.0.0
   ------------------------------------------------------------
   panel   : Noclip header, X collapse, move toggle, circle dot
   noclip  : global collision kill, metatable hijack, forced
             raycast respect, measured exit, pre-physics pass
   ------------------------------------------------------------
   no print() calls in this file
   ════════════════════════════════════════════════════════════
]]


--============================================================
-- 01 · CONFIG
--============================================================

local CONFIG = {
    panelWidth = 190, panelHeight = 148, panelX = 24, panelY = 88, cornerRadius = 10,
    headerHeight = 30, headerGap = 4, title = "Noclip", titleSize = 13,
    headerButtonSize = 24, bodyPadding = 12, noclipHeight = 54, noclipTextSize = 15,
    noclipLabel = "NOCLIP", noclipLabelActive = "NOCLIP: ON",
    dotCircleSize = 46, dotCollapsedSize = 30, dotLetter = "N",
    colorPanel = Color3.fromRGB(19, 22, 28), colorHeader = Color3.fromRGB(28, 32, 40),
    colorBody = Color3.fromRGB(15, 17, 22), colorButton = Color3.fromRGB(44, 49, 60),
    colorButtonHover = Color3.fromRGB(60, 67, 82), colorActive = Color3.fromRGB(64, 110, 74),
    colorOff = Color3.fromRGB(224, 49, 49), colorOn = Color3.fromRGB(45, 168, 88),
    colorText = Color3.fromRGB(235, 238, 243), colorMuted = Color3.fromRGB(120, 128, 140),
    colorStroke = Color3.fromRGB(52, 58, 70),
    hoverHeight = 0.25, stickRange = 16, stickStiffness = 14, maxStickSpeed = 55,
    ghostGroup = "NoClipGhost", ghostRefreshRate = 6, ghostBurstFrames = 45,
    probeSize = 1.4, shoveStep = 0.6, shoveLimit = 14, shoveSpeed = 30,
    shoveClearance = 1.2, shoveMaxFrames = 48, shoveCooldown = 0.2, shoveDrift = 2.5,
    freezeFrames = 5, guardDistance = 3.5, guardHistory = 14, guardMaxPerSecond = 8,
    fallProbe = 60, fallMargin = 3, stuckFrames = 9, stuckEpsilon = 0.35,
    pollInterval = 0.4, tapThreshold = 8, screenPadding = 4, engineErrorLimit = 30,
    nukeAll = true, nukeBatch = 250, nukeRescan = 1.5,
    displayOrder = 9999, guiName = "NoClipUI",
}

--============================================================
-- 02 · SERVICES
--============================================================

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local PhysicsService = game:GetService("PhysicsService")
local Workspace = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer
if not LocalPlayer then
    Players:GetPropertyChangedSignal("LocalPlayer"):Wait()
    LocalPlayer = Players.LocalPlayer
end

--============================================================
-- 03 · UTILITIES
--============================================================

local function new(class, props, children)
    local inst = Instance.new(class)
    local parent = props and props.Parent
    if props then
        for key, value in pairs(props) do
            if key ~= "Parent" then
                inst[key] = value
            end
        end
    end
    for _, child in ipairs(children or {}) do
        child.Parent = inst
    end
    if parent then
        inst.Parent = parent
    end
    return inst
end

local function round(inst, radius)
    new("UICorner", { CornerRadius = UDim.new(0, radius or 8), Parent = inst })
    return inst
end

local function stroke(inst, colour, thickness, transparency)
    new("UIStroke", {
        Color = colour or CONFIG.colorStroke, Thickness = thickness or 1,
        Transparency = transparency or 0, Parent = inst,
    })
    return inst
end

local function clampToScreen(x, y, width, height)
    local camera = Workspace.CurrentCamera
    local vp = camera and camera.ViewportSize or Vector2.new(1080, 1920)
    local edge = CONFIG.screenPadding
    return math.clamp(x, edge, math.max(edge, vp.X - width - edge)),
        math.clamp(y, edge, math.max(edge, vp.Y - height - edge))
end

local function guiParent()
    local ok, hidden = pcall(function()
        return gethui and gethui() or nil
    end)
    return (ok and hidden) or LocalPlayer:WaitForChild("PlayerGui")
end

local function horizontal(vector)
    return Vector3.new(vector.X, 0, vector.Z)
end

local function flatLook(cframe)
    local flat = horizontal(cframe.LookVector)
    return flat.Magnitude < 0.01 and Vector3.new(0, 0, -1) or flat.Unit
end

--============================================================
-- 04 · STATE
--============================================================

local state = { mode = "normal", dragMode = false, noclip = false, destroyed = false }
local panel, dot, dotGlyph, dotLetter
local noclipButton, noclipLabel, statusLabel
local moveButton, moveButtonStroke, circleButton, circleButtonStroke
local closeButton, gui

local connections = {}
local function track(connection)
    connections[#connections + 1] = connection
    return connection
end

local shield = { hooks = {}, gravity = 0, walk = 0, jump = 0, hip = 0, size = nil }
local engineErrors = 0
local pollClock = 0

--============================================================
-- 05 · ICONS
--============================================================

local function buildMoveIcon(parent)
    local wrap = new("Frame", {
        Name = "MoveIcon", Parent = parent, BackgroundTransparency = 1,
        Size = UDim2.fromOffset(16, 16), Position = UDim2.fromScale(0.5, 0.5),
        AnchorPoint = Vector2.new(0.5, 0.5),
    })
    local glyphs = {
        { text = "\u{2191}", x = 0, y = 0 }, { text = "\u{2190}", x = 0, y = 5.5 },
        { text = "\u{2192}", x = 8, y = 5.5 }, { text = "\u{2193}", x = 0, y = 11 },
    }
    for _, glyph in ipairs(glyphs) do
        new("TextLabel", {
            Parent = wrap, BackgroundTransparency = 1, Text = glyph.text,
            Size = UDim2.fromOffset(8, 5), Position = UDim2.fromOffset(glyph.x, glyph.y),
            TextSize = 8, Font = Enum.Font.GothamBold, TextColor3 = CONFIG.colorText,
        })
    end
end

local function buildCircleIcon(parent)
    local ring = new("Frame", {
        Name = "Ring", Parent = parent, BackgroundTransparency = 1, BorderSizePixel = 0,
        Size = UDim2.fromOffset(11, 11), Position = UDim2.fromScale(0.5, 0.5),
        AnchorPoint = Vector2.new(0.5, 0.5),
    })
    round(ring, 11)
    stroke(ring, CONFIG.colorText, 1.4, 0)
end

--============================================================
-- 06 · GUI
--============================================================

local function buildGui()
    gui = new("ScreenGui", {
        Name = CONFIG.guiName, ResetOnSpawn = false, IgnoreGuiInset = true,
        DisplayOrder = CONFIG.displayOrder, Parent = guiParent(),
    })
    panel = new("Frame", {
        Name = "Panel", Parent = gui, ClipsDescendants = true, BorderSizePixel = 0,
        Size = UDim2.fromOffset(CONFIG.panelWidth, CONFIG.panelHeight),
        Position = UDim2.fromOffset(CONFIG.panelX, CONFIG.panelY),
        BackgroundColor3 = CONFIG.colorPanel,
    })
    round(panel, CONFIG.cornerRadius)
    stroke(panel, CONFIG.colorStroke, 1, 0.25)
    local header = new("Frame", {
        Name = "Header", Parent = panel, BorderSizePixel = 0,
        Size = UDim2.new(1, 0, 0, CONFIG.headerHeight), BackgroundColor3 = CONFIG.colorHeader,
    })
    new("TextLabel", {
        Name = "Title", Parent = header, BackgroundTransparency = 1,
        Size = UDim2.new(1, -104, 1, 0), Position = UDim2.fromOffset(10, 0),
        Text = CONFIG.title, TextSize = CONFIG.titleSize, Font = Enum.Font.GothamBold,
        TextColor3 = CONFIG.colorText, TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Center,
    })
    local row = new("Frame", {
        Name = "Buttons", Parent = header, BackgroundTransparency = 1,
        Size = UDim2.new(0, 80, 1, 0), Position = UDim2.new(1, -6, 0, 0),
        AnchorPoint = Vector2.new(1, 0),
    })
    new("UIListLayout", {
        Parent = row, FillDirection = Enum.FillDirection.Horizontal,
        HorizontalAlignment = Enum.HorizontalAlignment.Right,
        VerticalAlignment = Enum.VerticalAlignment.Center,
        Padding = UDim.new(0, CONFIG.headerGap),
    })
    circleButton = new("TextButton", {
        Name = "CircleButton", Parent = row, LayoutOrder = 1, Text = "",
        Size = UDim2.fromOffset(CONFIG.headerButtonSize, CONFIG.headerButtonSize),
        BackgroundColor3 = CONFIG.colorButton, BorderSizePixel = 0, AutoButtonColor = false,
    })
    round(circleButton, 6)
    circleButtonStroke = stroke(circleButton, CONFIG.colorStroke, 1, 0.4)
    buildCircleIcon(circleButton)
    moveButton = new("TextButton", {
        Name = "MoveButton", Parent = row, LayoutOrder = 2, Text = "",
        Size = UDim2.fromOffset(CONFIG.headerButtonSize, CONFIG.headerButtonSize),
        BackgroundColor3 = CONFIG.colorButton, BorderSizePixel = 0, AutoButtonColor = false,
    })
    round(moveButton, 6)
    moveButtonStroke = stroke(moveButton, CONFIG.colorStroke, 1, 0.4)
    buildMoveIcon(moveButton)
    closeButton = new("TextButton", {
        Name = "CloseButton", Parent = row, LayoutOrder = 3, BorderSizePixel = 0,
        Size = UDim2.fromOffset(CONFIG.headerButtonSize, CONFIG.headerButtonSize),
        BackgroundColor3 = CONFIG.colorButton, Text = "\u{2715}", TextSize = 12,
        Font = Enum.Font.GothamBold, TextColor3 = CONFIG.colorText, AutoButtonColor = false,
    })
    round(closeButton, 6)
    stroke(closeButton, CONFIG.colorStroke, 1, 0.4)
    local body = new("Frame", {
        Name = "Body", Parent = panel, BorderSizePixel = 0,
        Size = UDim2.new(1, 0, 1, -CONFIG.headerHeight),
        Position = UDim2.fromOffset(0, CONFIG.headerHeight),
        BackgroundColor3 = CONFIG.colorBody,
    })
    new("UIPadding", {
        Parent = body, PaddingTop = UDim.new(0, CONFIG.bodyPadding),
        PaddingLeft = UDim.new(0, CONFIG.bodyPadding),
        PaddingRight = UDim.new(0, CONFIG.bodyPadding), PaddingBottom = UDim.new(0, 8),
    })
    new("UIListLayout", {
        Parent = body, FillDirection = Enum.FillDirection.Vertical,
        HorizontalAlignment = Enum.HorizontalAlignment.Center,
        VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 8),
    })
    noclipButton = new("TextButton", {
        Name = "NoclipButton", Parent = body, LayoutOrder = 1, Text = "",
        Size = UDim2.new(1, 0, 0, CONFIG.noclipHeight),
        BackgroundColor3 = CONFIG.colorOff, BorderSizePixel = 0, AutoButtonColor = false,
    })
    round(noclipButton, 8)
    stroke(noclipButton, Color3.fromRGB(255, 255, 255), 1, 0.75)
    noclipLabel = new("TextLabel", {
        Name = "Label", Parent = noclipButton, BackgroundTransparency = 1,
        Size = UDim2.fromScale(1, 1), Text = CONFIG.noclipLabel,
        TextSize = CONFIG.noclipTextSize, Font = Enum.Font.GothamBold,
        TextColor3 = Color3.fromRGB(255, 255, 255),
    })
    statusLabel = new("TextLabel", {
        Name = "Status", Parent = body, LayoutOrder = 2, BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 0, 14), Text = "idle", TextSize = 11,
        Font = Enum.Font.Gotham, TextColor3 = CONFIG.colorMuted,
        TextXAlignment = Enum.TextXAlignment.Center,
    })
    dot = new("TextButton", {
        Name = "Dot", Parent = gui, Visible = false, Text = "",
        Size = UDim2.fromOffset(CONFIG.dotCircleSize, CONFIG.dotCircleSize),
        Position = UDim2.fromOffset(CONFIG.panelX, CONFIG.panelY),
        BackgroundColor3 = CONFIG.colorPanel, BorderSizePixel = 0, AutoButtonColor = false,
    })
    round(dot, 1)
    stroke(dot, CONFIG.colorStroke, 1, 0.2)
    dotGlyph = new("Frame", {
        Name = "Glyph", Parent = dot, BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1),
    })
    buildCircleIcon(dotGlyph)
    dotLetter = new("TextLabel", {
        Name = "Letter", Parent = dot, BackgroundTransparency = 1,
        Size = UDim2.fromScale(1, 1), Text = CONFIG.dotLetter, TextSize = 13,
        Font = Enum.Font.GothamBold, TextColor3 = CONFIG.colorText, Visible = false,
    })
end

--============================================================
-- 07 · MODES
--============================================================

local function applyMode(mode)
    state.mode = mode
    if mode == "normal" then
        dot.Visible = false
        panel.Visible = true
        panel.Position = dot.Position
        local x, y = clampToScreen(panel.Position.X.Offset, panel.Position.Y.Offset,
            panel.AbsoluteSize.X, panel.AbsoluteSize.Y)
        panel.Position = UDim2.fromOffset(x, y)
        return
    end
    local size = (mode == "circle") and CONFIG.dotCircleSize or CONFIG.dotCollapsedSize
    dot.Size = UDim2.fromOffset(size, size)
    dotGlyph.Visible = (mode == "circle")
    dotLetter.Visible = (mode == "collapsed")
    local x, y = clampToScreen(panel.Position.X.Offset, panel.Position.Y.Offset, size, size)
    dot.Position = UDim2.fromOffset(x, y)
    panel.Visible = false
    dot.Visible = true
end

local function toggleMode(mode)
    applyMode(state.mode == mode and "normal" or mode)
end

--============================================================
-- 08 · DRAG
--============================================================

local function attachDrag(handle, target, options)
    options = options or {}
    track(handle.InputBegan:Connect(function(input)
        if input.UserInputType ~= Enum.UserInputType.MouseButton1
            and input.UserInputType ~= Enum.UserInputType.Touch then
            return
        end
        if options.condition and not options.condition() then
            return
        end
        local origin, startPos, moved = input.Position, target.Position, 0
        local watcher
        watcher = input.Changed:Connect(function()
            local delta = input.Position - origin
            moved = math.max(moved, delta.Magnitude)
            local x, y = clampToScreen(startPos.X.Offset + delta.X, startPos.Y.Offset + delta.Y,
                target.AbsoluteSize.X, target.AbsoluteSize.Y)
            target.Position = UDim2.fromOffset(x, y)
        end)
        input.Ended:Connect(function()
            if watcher then
                watcher:Disconnect()
            end
            if options.onEnd then
                options.onEnd(moved)
            end
        end)
    end))
end

--============================================================
-- 09 · ENGINE STATE
--============================================================

local stopEngine, startEngine
local saved, ghostHooks, engineConns = {}, {}, {}
local heartbeat, preStep, frameClock = nil, nil, 0
local lastPosition, guardClock, guardCount = nil, 0, 0
local freezeClock, shoveClock, lastHumanoid = 0, 0, nil
local history, stuckClock, stuckAnchor = {}, 0, nil
local scanQueue, scanIndex, scanClock = {}, 0, 0
local shove = { active = false, direction = Vector3.zero, target = Vector3.zero,
    frames = 0, last = Vector3.zero }

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.IgnoreWater = true
rayParams.RespectCanCollide = false

local probeParams = OverlapParams.new()
probeParams.FilterType = Enum.RaycastFilterType.Exclude
probeParams.RespectCanCollide = false

local ownParams = { [rayParams] = true, [probeParams] = true }

local DISABLED_STATES = {
    Enum.HumanoidStateType.FallingDown, Enum.HumanoidStateType.Ragdoll,
    Enum.HumanoidStateType.GettingUp, Enum.HumanoidStateType.StrafingNoPhysics,
    Enum.HumanoidStateType.PlatformStanding,
}

--============================================================
-- 10 · COLLISION GROUP
--============================================================

local groupReady = false

local function ensureGroup()
    if groupReady then
        return true
    end
    if not pcall(function()
        PhysicsService:RegisterCollisionGroup(CONFIG.ghostGroup)
    end) then
        return false
    end
    -- self pair off: nothing inside the group collides with anything else
    -- inside the group, so one call kills every part-part contact at once
    pcall(function()
        PhysicsService:CollisionGroupSetCollidable(CONFIG.ghostGroup, CONFIG.ghostGroup, false)
    end)
    groupReady = true
    pollGroups()
    return true
end

local function pollGroups()
    if not groupReady then
        return
    end
    local ok, groups = pcall(function()
        return PhysicsService:GetCollisionGroups()
    end)
    if not ok or not groups then
        return
    end
    for _, group in ipairs(groups) do
        pcall(function()
            PhysicsService:CollisionGroupSetCollidable(CONFIG.ghostGroup, group.name, false)
        end)
    end
end

--============================================================
-- 11 · PART PASS
--============================================================

local function savePart(part)
    if saved[part] then
        return false
    end
    saved[part] = {
        collide = part.CanCollide, group = part.CollisionGroup,
        query = part.CanQuery, touch = part.CanTouch, anchor = part.Anchored,
    }
    return true
end

local function strip(part)
    if not part:IsA("BasePart") then
        return
    end
    savePart(part)
    if part.CanCollide then
        part.CanCollide = false
    end
    if groupReady and part.CollisionGroup ~= CONFIG.ghostGroup then
        part.CollisionGroup = CONFIG.ghostGroup
    end
    if part.CanQuery then
        part.CanQuery = false
    end
    if not part.CanTouch then
        part.CanTouch = true
    end
end

local function ghostPart(part)
    if not part:IsA("BasePart") then
        return
    end
    strip(part)
    if part.Anchored then
        part.Anchored = false
    end
    if not ghostHooks[part] then
        ghostHooks[part] = {
            part:GetPropertyChangedSignal("CanCollide"):Connect(function()
                if state.noclip and part.CanCollide then
                    part.CanCollide = false
                end
            end),
            part:GetPropertyChangedSignal("CollisionGroup"):Connect(function()
                if state.noclip and groupReady and part.CollisionGroup ~= CONFIG.ghostGroup then
                    part.CollisionGroup = CONFIG.ghostGroup
                end
            end),
            part:GetPropertyChangedSignal("CanQuery"):Connect(function()
                if state.noclip and part.CanQuery then
                    part.CanQuery = false
                end
            end),
            part:GetPropertyChangedSignal("CanTouch"):Connect(function()
                if state.noclip and not part.CanTouch then
                    part.CanTouch = true
                end
            end),
            part:GetPropertyChangedSignal("Anchored"):Connect(function()
                if state.noclip and part.Anchored then
                    part.Anchored = false
                end
            end),
        }
    end
end

local function ghostCharacter(character)
    for _, descendant in ipairs(character:GetDescendants()) do
        ghostPart(descendant)
    end
end

--============================================================
-- 12 · GLOBAL SWEEP
--============================================================

local function nukePart(part)
    if not part:IsA("BasePart") or part:IsDescendantOf(LocalPlayer.Character or Workspace) then
        if part:IsA("BasePart") and not (LocalPlayer.Character
            and part:IsDescendantOf(LocalPlayer.Character)) then
            strip(part)
        end
        return
    end
    strip(part)
end

local function buildScan()
    local ok, list = pcall(function()
        return Workspace:GetDescendants()
    end)
    if not ok or not list then
        return
    end
    scanQueue, scanIndex = list, 0
end

-- batched so a big map does not hitch the frame it turns on
local function sweepStep()
    if not CONFIG.nukeAll or scanIndex >= #scanQueue then
        return
    end
    local limit = math.min(scanIndex + CONFIG.nukeBatch, #scanQueue)
    for index = scanIndex + 1, limit do
        local part = scanQueue[index]
        if part and part.Parent then
            strip(part)
        end
    end
    scanIndex = limit
end

local function restoreAll()
    for part, values in pairs(saved) do
        if part and part.Parent then
            pcall(function()
                part.CanCollide = values.collide
                part.CollisionGroup = values.group
                part.CanQuery = values.query
                part.CanTouch = values.touch
                part.Anchored = values.anchor
            end)
        end
    end
    table.clear(saved)
    scanQueue, scanIndex = {}, 0
end

local function clearGhostHooks()
    for part, hooks in pairs(ghostHooks) do
        for _, connection in ipairs(hooks) do
            connection:Disconnect()
        end
        ghostHooks[part] = nil
    end
end

--============================================================
-- 13 · METATABLE HIJACK
--============================================================

-- the game is told CanCollide is false even when the real value is true,
-- and their own raycasts are forced to respect it so wall checks miss us
local hooked = false
local oldIndex, oldNamecall

local function hookSystem()
    if hooked then
        return true
    end
    if not getrawmetatable then
        return false
    end
    local ok = pcall(function()
        local mt = getrawmetatable(game)
        oldIndex, oldNamecall = mt.__index, mt.__namecall
        setreadonly(mt, false)
        mt.__index = newcclosure(function(self, key)
            if state.noclip and key == "CanCollide" and typeof(self) == "Instance" then
                local okPart, isPart = pcall(function()
                    return self:IsA("BasePart")
                end)
                if okPart and isPart then
                    return false
                end
            end
            return oldIndex(self, key)
        end)
        mt.__namecall = newcclosure(function(self, ...)
            if state.noclip and getnamecallmethod() == "Raycast" then
                local params = select(3, ...)
                if typeof(params) == "RaycastParams" and not ownParams[params] then
                    pcall(function()
                        params.RespectCanCollide = true
                    end)
                end
            end
            return oldNamecall(self, ...)
        end)
        setreadonly(mt, true)
    end)
    hooked = ok
    return ok
end

local function unhookSystem()
    if not hooked then
        return
    end
    pcall(function()
        local mt = getrawmetatable(game)
        setreadonly(mt, false)
        if oldIndex then
            mt.__index = oldIndex
        end
        if oldNamecall then
            mt.__namecall = oldNamecall
        end
        setreadonly(mt, true)
    end)
    hooked = false
end

--============================================================
-- 14 · HUMANOID HARDENING
--============================================================

local function hardenHumanoid(humanoid)
    humanoid.RequiresNeck = false
    humanoid.BreakJointsOnDeath = false
    for _, humanoidState in ipairs(DISABLED_STATES) do
        pcall(function()
            humanoid:SetStateEnabled(humanoidState, false)
        end)
    end
end

local function relaxHumanoid(humanoid)
    for _, humanoidState in ipairs(DISABLED_STATES) do
        pcall(function()
            humanoid:SetStateEnabled(humanoidState, true)
        end)
    end
end

local function claimOwnership(root)
    pcall(function()
        root:SetNetworkOwner(LocalPlayer)
    end)
end

--============================================================
-- 15 · SHIELD
--============================================================

local function shieldProp(inst, prop, fix)
    shield.hooks[inst] = shield.hooks[inst] or {}
    if shield.hooks[inst][prop] then
        return
    end
    shield.hooks[inst][prop] = inst:GetPropertyChangedSignal(prop):Connect(function()
        if state.noclip and not state.destroyed then
            pcall(fix)
        end
    end)
end

local function armShield(character, humanoid, root)
    shield.gravity, shield.walk = Workspace.Gravity, humanoid.WalkSpeed
    shield.jump, shield.hip = humanoid.JumpPower, humanoid.HipHeight
    shield.size = root.Size
    shieldProp(root, "Anchored", function() if root.Anchored then root.Anchored = false end end)
    shieldProp(root, "Massless", function() if not root.Massless then root.Massless = true end end)
    shieldProp(root, "Size", function()
        if root.Size ~= shield.size then
            root.Size = shield.size
        end
    end)
    shieldProp(humanoid, "PlatformStand",
        function() if humanoid.PlatformStand then humanoid.PlatformStand = false end end)
    shieldProp(humanoid, "RequiresNeck",
        function() if humanoid.RequiresNeck then humanoid.RequiresNeck = false end end)
    shieldProp(humanoid, "AutoRotate",
        function() if not humanoid.AutoRotate then humanoid.AutoRotate = true end end)
    shieldProp(humanoid, "EvaluateStateMachine", function()
        if not humanoid.EvaluateStateMachine then
            humanoid.EvaluateStateMachine = true
        end
    end)
    shieldProp(humanoid, "WalkSpeed", function()
        if humanoid.WalkSpeed <= 0 and shield.walk > 0 then
            humanoid.WalkSpeed = shield.walk
        end
    end)
    shieldProp(humanoid, "JumpPower", function()
        if humanoid.JumpPower <= 0 and shield.jump > 0 then
            humanoid.JumpPower = shield.jump
        end
    end)
    shieldProp(humanoid, "HipHeight", function()
        if shield.hip > 0 and math.abs(humanoid.HipHeight - shield.hip) > 0.5 then
            humanoid.HipHeight = shield.hip
        end
    end)
    shieldProp(Workspace, "Gravity",
        function() if Workspace.Gravity < 1 then Workspace.Gravity = shield.gravity end end)
    shieldProp(character, "Parent", function()
        if character.Parent ~= Workspace and character.Parent then
            character.Parent = Workspace
        end
    end)
end

local function disarmShield()
    for inst, props in pairs(shield.hooks) do
        for _, connection in pairs(props) do
            connection:Disconnect()
        end
        shield.hooks[inst] = nil
    end
end

--============================================================
-- 16 · PENETRATION
--============================================================

local function embeddedAt(position)
    local size = Vector3.new(CONFIG.probeSize, CONFIG.probeSize, CONFIG.probeSize)
    for _, part in ipairs(Workspace:GetPartBoundsInBox(CFrame.new(position), size, probeParams)) do
        if part.CanCollide then
            return true
        end
    end
    return false
end

local function shoveDirection(root, humanoid)
    local move = humanoid.MoveDirection
    if move.Magnitude > 0.05 then
        return horizontal(move).Unit
    end
    return flatLook(root.CFrame)
end

local function findExit(root, direction)
    local origin, travelled = root.Position, 0
    while travelled < CONFIG.shoveLimit do
        travelled += CONFIG.shoveStep
        if not embeddedAt(origin + direction * travelled) then
            return travelled
        end
    end
    return CONFIG.shoveLimit
end

local function beginShove(root, humanoid)
    local now = os.clock()
    if now - shoveClock < CONFIG.shoveCooldown then
        return false
    end
    local direction = shoveDirection(root, humanoid)
    shove.active = true
    shove.direction = direction
    shove.target = root.Position + direction * (findExit(root, direction) + CONFIG.shoveClearance)
    shove.frames, shove.last, shoveClock = 0, root.Position, now
    return true
end

local function endShove()
    shove.active = false
    shove.frames = 0
    shove.direction = Vector3.zero
end

local function stepShove(root)
    if not shove.active then
        return
    end
    shove.frames += 1
    if shove.frames > CONFIG.shoveMaxFrames then
        endShove()
        return
    end
    if horizontal(root.Position - shove.last).Magnitude > CONFIG.shoveDrift then
        shove.target = root.Position + shove.direction * CONFIG.shoveClearance
    end
    shove.last = root.Position
    local flat = horizontal(shove.target - root.Position)
    if flat.Magnitude <= 0.2 then
        endShove()
        return
    end
    local speed = (os.clock() < freezeClock) and CONFIG.shoveSpeed * 0.5 or CONFIG.shoveSpeed
    root.CFrame = root.CFrame + flat.Unit * math.min(speed / 60, flat.Magnitude)
    root.AssemblyLinearVelocity = flat.Unit * speed
    if shove.frames == 1 then
        freezeClock = os.clock() + (CONFIG.freezeFrames / 60)
    end
end

--============================================================
-- 17 · POSITION GUARD
--============================================================

local function guardPosition(root, direction)
    local now = os.clock()
    if now - guardClock > 1 then
        guardCount = 0
    end
    local current = root.Position
    history[#history + 1] = current
    if #history > CONFIG.guardHistory then
        table.remove(history, 1)
    end
    if not lastPosition then
        lastPosition = current
        return
    end
    local flat = horizontal(current - lastPosition)
    if flat.Magnitude < CONFIG.guardDistance then
        lastPosition = current
        return
    end
    if flat.Unit:Dot(direction) > -0.2 or guardCount >= CONFIG.guardMaxPerSecond then
        lastPosition = current
        return
    end
    guardCount += 1
    local restore = history[math.max(1, #history - 2)] or lastPosition
    local keep = root.CFrame - root.Position
    root.CFrame = CFrame.new(restore) * keep
    root.AssemblyLinearVelocity = Vector3.zero
    lastPosition = restore
end

--============================================================
-- 18 · FLOOR
--============================================================

local function hoverStep(root, humanoid, velocity)
    local hip = humanoid.HipHeight or 0
    local offset = (root.Size.Y * 0.5) + hip + CONFIG.hoverHeight
    local result = Workspace:Raycast(root.Position,
        Vector3.new(0, -(CONFIG.stickRange + offset), 0), rayParams)
    if not result then
        return false
    end
    local difference = (result.Position.Y + offset) - root.Position.Y
    if math.abs(difference) < 0.02 then
        root.AssemblyLinearVelocity = Vector3.new(velocity.X, 0, velocity.Z)
    else
        local correction = math.clamp(difference * CONFIG.stickStiffness,
            -CONFIG.maxStickSpeed, CONFIG.maxStickSpeed)
        root.AssemblyLinearVelocity = Vector3.new(velocity.X, correction, velocity.Z)
    end
    return true
end

local function fallClamp(root, velocity)
    local result = Workspace:Raycast(root.Position, Vector3.new(0, -CONFIG.fallProbe, 0), rayParams)
    if not result or result.Distance > math.abs(velocity.Y) / 60 + CONFIG.fallMargin then
        return
    end
    local stop = result.Position.Y + (root.Size.Y * 0.5) + CONFIG.hoverHeight
    if root.Position.Y - stop < 1 then
        root.AssemblyLinearVelocity = Vector3.new(velocity.X, 0, velocity.Z)
    end
end

--============================================================
-- 19 · STUCK BREAKER
--============================================================

local function checkStuck(root, humanoid)
    if humanoid.MoveDirection.Magnitude < 0.05 then
        stuckAnchor, stuckClock = root.Position, 0
        return false
    end
    if not stuckAnchor then
        stuckAnchor = root.Position
        return false
    end
    if horizontal(root.Position - stuckAnchor).Magnitude > CONFIG.stuckEpsilon then
        stuckAnchor, stuckClock = root.Position, 0
        return false
    end
    stuckClock += 1
    if stuckClock >= CONFIG.stuckFrames then
        stuckClock, stuckAnchor = 0, root.Position
        return true
    end
    return false
end

--============================================================
-- 20 · PRE-PHYSICS STEP
--============================================================

local function applyStep()
    if not state.noclip then
        return
    end
    local character = LocalPlayer.Character
    if not character then
        return
    end
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    local root = character:FindFirstChild("HumanoidRootPart")
    if not humanoid or not root or root.Parent ~= character then
        return
    end
    if shove.active then
        stepShove(root)
        return
    end
    local okState, humanoidState = pcall(function()
        return humanoid:GetState()
    end)
    if not okState then
        return
    end
    if humanoidState == Enum.HumanoidStateType.Swimming
        or humanoidState == Enum.HumanoidStateType.Climbing
        or humanoidState == Enum.HumanoidStateType.Seated then
        return
    end
    local velocity = root.AssemblyLinearVelocity
    if humanoidState == Enum.HumanoidStateType.Jumping or velocity.Y > 2 then
        return
    end
    hoverStep(root, humanoid, velocity)
end

--============================================================
-- 21 · SENSE
--============================================================

local function sense()
    local character = LocalPlayer.Character
    if not character or not character.Parent then
        return
    end
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    local root = character:FindFirstChild("HumanoidRootPart")
    if not humanoid or not root or root.Parent ~= character then
        return
    end
    frameClock += 1
    if frameClock <= CONFIG.ghostBurstFrames or frameClock % CONFIG.ghostRefreshRate == 0 then
        ghostCharacter(character)
        claimOwnership(root)
    end
    sweepStep()
    rayParams.FilterDescendantsInstances = { character }
    probeParams.FilterDescendantsInstances = { character }
    local okState, humanoidState = pcall(function()
        return humanoid:GetState()
    end)
    if not okState then
        humanoidState = nil
    end
    local velocity = root.AssemblyLinearVelocity
    local direction = shoveDirection(root, humanoid)
    if humanoidState == Enum.HumanoidStateType.Swimming
        or humanoidState == Enum.HumanoidStateType.Climbing
        or humanoidState == Enum.HumanoidStateType.Seated then
        return
    end
    guardPosition(root, direction)
    if shove.active then
        return
    end
    if embeddedAt(root.Position) then
        beginShove(root, humanoid)
        return
    end
    if checkStuck(root, humanoid) then
        beginShove(root, humanoid)
        return
    end
    if humanoidState == Enum.HumanoidStateType.Jumping or velocity.Y > 2 then
        fallClamp(root, velocity)
        return
    end
    if humanoidState == Enum.HumanoidStateType.Freefall then
        pcall(function()
            humanoid:ChangeState(Enum.HumanoidStateType.Running)
        end)
    end
end

local function onHeartbeat()
    if not state.noclip then
        return
    end
    local now = os.clock()
    if now - pollClock > CONFIG.pollInterval then
        pollClock = now
        pollGroups()
    end
    if pcall(sense) then
        engineErrors = 0
        return
    end
    engineErrors += 1
    if engineErrors >= CONFIG.engineErrorLimit then
        engineErrors = 0
        pcall(stopEngine)
        pcall(startEngine)
    end
end

--============================================================
-- 22 · LIFECYCLE
--============================================================

stopEngine = function()
    for _, connection in ipairs(engineConns) do
        connection:Disconnect()
    end
    table.clear(engineConns)
    if heartbeat then
        heartbeat:Disconnect()
        heartbeat = nil
    end
    if preStep then
        preStep:Disconnect()
        preStep = nil
    end
    disarmShield()
    if lastHumanoid then
        relaxHumanoid(lastHumanoid)
        lastHumanoid = nil
    end
    lastPosition = nil
    table.clear(history)
    endShove()
    clearGhostHooks()
    restoreAll()
end

startEngine = function()
    local character = LocalPlayer.Character
    if not character then
        return false
    end
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    local root = character:FindFirstChild("HumanoidRootPart")
    if not humanoid or not root then
        return false
    end
    ensureGroup()
    hookSystem()
    table.clear(saved)
    ghostCharacter(character)
    buildScan()
    hardenHumanoid(humanoid)
    claimOwnership(root)
    armShield(character, humanoid, root)
    lastHumanoid = humanoid
    engineConns[#engineConns + 1] = character.DescendantAdded:Connect(ghostPart)
    engineConns[#engineConns + 1] = Workspace.DescendantAdded:Connect(function(part)
        if state.noclip and CONFIG.nukeAll then
            pcall(strip, part)
        end
    end)
    engineConns[#engineConns + 1] = humanoid.Died:Connect(function()
        stopEngine()
        if state.noclip then
            LocalPlayer:WaitForChild("Character", 10)
            task.wait(0.4)
            if state.noclip then
                startEngine()
            end
        end
    end)
    preStep = RunService.Stepped:Connect(function()
        pcall(applyStep)
    end)
    heartbeat = RunService.Heartbeat:Connect(onHeartbeat)
    return true
end

--============================================================
-- 23 · PAINT
--============================================================

local function paintNoclip()
    if state.noclip then
        noclipButton.BackgroundColor3 = CONFIG.colorOn
        noclipLabel.Text = CONFIG.noclipLabelActive
        statusLabel.Text = "collision off"
        statusLabel.TextColor3 = CONFIG.colorOn
    else
        noclipButton.BackgroundColor3 = CONFIG.colorOff
        noclipLabel.Text = CONFIG.noclipLabel
        statusLabel.Text = "idle"
        statusLabel.TextColor3 = CONFIG.colorMuted
    end
end

local function paintDrag()
    moveButton.BackgroundColor3 = state.dragMode and CONFIG.colorActive or CONFIG.colorButton
    if moveButtonStroke then
        moveButtonStroke.Transparency = state.dragMode and 0 or 0.4
    end
end

local function setNoclip(enabled)
    if state.noclip == enabled then
        return
    end
    if enabled then
        if startEngine() then
            state.noclip = true
        end
    else
        state.noclip = false
        stopEngine()
    end
    paintNoclip()
end

--============================================================
-- 24 · WIRING
--============================================================

local function wire()
    track(noclipButton.Activated:Connect(function()
        setNoclip(not state.noclip)
    end))
    track(moveButton.Activated:Connect(function()
        state.dragMode = not state.dragMode
        paintDrag()
    end))
    track(circleButton.Activated:Connect(function()
        toggleMode("circle")
    end))
    track(closeButton.Activated:Connect(function()
        toggleMode("collapsed")
    end))
    attachDrag(panel, panel, {
        condition = function()
            return UserInputService:GetMouseLocation().Y
                <= panel.AbsolutePosition.Y + CONFIG.headerHeight
        end,
    })
    attachDrag(panel, panel, {
        condition = function()
            return state.dragMode
        end,
    })
    attachDrag(dot, dot, {
        onEnd = function(moved)
            if moved < CONFIG.tapThreshold then
                applyMode("normal")
            end
        end,
    })
    track(Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
        local camera = Workspace.CurrentCamera
        if not camera then
            return
        end
        track(camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
            local target = (state.mode == "normal") and panel or dot
            local x, y = clampToScreen(target.Position.X.Offset, target.Position.Y.Offset,
                target.AbsoluteSize.X, target.AbsoluteSize.Y)
            target.Position = UDim2.fromOffset(x, y)
        end))
    end))
end

--============================================================
-- 25 · GUARD DOG
--============================================================

local function guardDog()
    task.spawn(function()
        while not state.destroyed do
            task.wait(0.5)
            if state.destroyed then
                break
            end
            if gui and gui.Parent == nil then
                pcall(function()
                    gui.Parent = guiParent()
                end)
            end
            if gui and not gui.Enabled then
                gui.Enabled = true
            end
            if state.noclip and not heartbeat then
                pcall(stopEngine)
                pcall(startEngine)
            end
            if state.noclip and not hooked then
                hookSystem()
            end
        end
    end)
end

--============================================================
-- 26 · PUBLIC API
--============================================================

local api = {}
api.toggle = function() setNoclip(not state.noclip) end
api.on = function() setNoclip(true) end
api.off = function() setNoclip(false) end
api.circle = function() applyMode("circle") end
api.collapse = function() applyMode("collapsed") end
api.expand = function() applyMode("normal") end
api.destroy = function()
    if state.destroyed then
        return
    end
    state.destroyed = true
    state.noclip = false
    stopEngine()
    unhookSystem()
    for _, connection in ipairs(connections) do
        connection:Disconnect()
    end
    table.clear(connections)
    if gui then
        gui:Destroy()
    end
    getgenv().NoClip = nil
end

--============================================================
-- 27 · BOOT
--============================================================

local function boot()
    local old = getgenv().NoClip
    if old and old.destroy then
        pcall(old.destroy)
    end
    buildGui()
    paintNoclip()
    paintDrag()
    wire()
    guardDog()
    getgenv().NoClip = api
    track(LocalPlayer.CharacterAdded:Connect(function(character)
        if not state.noclip then
            return
        end
        character:WaitForChild("HumanoidRootPart", 10)
        task.wait(0.4)
        if state.noclip then
            startEngine()
        end
    end))
end

boot()
--[[
════════════════════════════════════════════════════════════
   N O C L I P   ·   h a r d   m o d e   7   ·   q u i e t
   ------------------------------------------------------------
   file    : quiet.lua
   author  : supercaptain1233
   target  : Delta (Android) · universal · any Roblox game
   version : 7.0.0
   ------------------------------------------------------------
   collision is off, but nothing observable says so:
     · CanCollide forced TRUE and reported true by a metatable hook
     · CanQuery and CanTouch kept TRUE so their rays and volumes hit
     · CollisionGroup left Default, contact killed at group level
     · world parts untouched, only the player is moved
   ------------------------------------------------------------
   no print() calls in this file
   ════════════════════════════════════════════════════════════
]]


--============================================================
-- 01 · CONFIG
--============================================================

local CONFIG = {
    panelWidth = 190, panelHeight = 148, panelX = 24, panelY = 88, cornerRadius = 10,
    headerHeight = 30, headerGap = 4, title = "Quiet", titleSize = 13,
    headerButtonSize = 24, bodyPadding = 12, noclipHeight = 54, noclipTextSize = 15,
    noclipLabel = "NOCLIP", noclipLabelActive = "NOCLIP: ON",
    dotCircleSize = 46, dotCollapsedSize = 30, dotLetter = "Q",
    colorPanel = Color3.fromRGB(19, 22, 28), colorHeader = Color3.fromRGB(28, 32, 40),
    colorBody = Color3.fromRGB(15, 17, 22), colorButton = Color3.fromRGB(44, 49, 60),
    colorButtonHover = Color3.fromRGB(60, 67, 82), colorActive = Color3.fromRGB(64, 110, 74),
    colorOff = Color3.fromRGB(224, 49, 49), colorOn = Color3.fromRGB(120, 96, 200),
    colorText = Color3.fromRGB(235, 238, 243), colorMuted = Color3.fromRGB(120, 128, 140),
    colorStroke = Color3.fromRGB(52, 58, 70),
    ghostGroup = "NoClipQuiet",
    hoverHeight = 0.25, stickRange = 16, stickStiffness = 14, maxStickSpeed = 55,
    fallProbe = 60, fallMargin = 3,
    nudgeSpeed = 24, nudgeFrames = 20, stuckFrames = 10, stuckEpsilon = 0.3,
    guardDistance = 3.5, guardHistory = 14, guardMaxPerSecond = 8,
    pollInterval = 0.4, refreshRate = 6, burstFrames = 45,
    tapThreshold = 8, screenPadding = 4, engineErrorLimit = 30,
    displayOrder = 9999, guiName = "QuietUI",
}

--============================================================
-- 02 · SERVICES
--============================================================

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local PhysicsService = game:GetService("PhysicsService")
local Workspace = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer
if not LocalPlayer then
    Players:GetPropertyChangedSignal("LocalPlayer"):Wait()
    LocalPlayer = Players.LocalPlayer
end

--============================================================
-- 03 · UTILITIES
--============================================================

local function new(class, props, children)
    local inst = Instance.new(class)
    local parent = props and props.Parent
    if props then
        for key, value in pairs(props) do
            if key ~= "Parent" then
                inst[key] = value
            end
        end
    end
    for _, child in ipairs(children or {}) do
        child.Parent = inst
    end
    if parent then
        inst.Parent = parent
    end
    return inst
end

local function round(inst, radius)
    new("UICorner", { CornerRadius = UDim.new(0, radius or 8), Parent = inst })
    return inst
end

local function stroke(inst, colour, thickness, transparency)
    new("UIStroke", {
        Color = colour or CONFIG.colorStroke, Thickness = thickness or 1,
        Transparency = transparency or 0, Parent = inst,
    })
    return inst
end

local function clampToScreen(x, y, width, height)
    local camera = Workspace.CurrentCamera
    local vp = camera and camera.ViewportSize or Vector2.new(1080, 1920)
    local edge = CONFIG.screenPadding
    return math.clamp(x, edge, math.max(edge, vp.X - width - edge)),
        math.clamp(y, edge, math.max(edge, vp.Y - height - edge))
end

local function guiParent()
    local ok, hidden = pcall(function()
        return gethui and gethui() or nil
    end)
    return (ok and hidden) or LocalPlayer:WaitForChild("PlayerGui")
end

local function horizontal(vector)
    return Vector3.new(vector.X, 0, vector.Z)
end

local function flatLook(cframe)
    local flat = horizontal(cframe.LookVector)
    return flat.Magnitude < 0.01 and Vector3.new(0, 0, -1) or flat.Unit
end

--============================================================
-- 04 · STATE
--============================================================

local state = { mode = "normal", dragMode = false, noclip = false, destroyed = false }
local panel, dot, dotGlyph, dotLetter
local noclipButton, noclipLabel, statusLabel
local moveButton, moveButtonStroke, circleButton, circleButtonStroke
local closeButton, gui

local connections = {}
local function track(connection)
    connections[#connections + 1] = connection
    return connection
end

local shield = { hooks = {}, gravity = 0, walk = 0, jump = 0, hip = 0, size = nil }
local engineErrors = 0
local pollClock = 0

--============================================================
-- 05 · ICONS
--============================================================

local function buildMoveIcon(parent)
    local wrap = new("Frame", {
        Name = "MoveIcon", Parent = parent, BackgroundTransparency = 1,
        Size = UDim2.fromOffset(16, 16), Position = UDim2.fromScale(0.5, 0.5),
        AnchorPoint = Vector2.new(0.5, 0.5),
    })
    local glyphs = {
        { text = "\u{2191}", x = 0, y = 0 }, { text = "\u{2190}", x = 0, y = 5.5 },
        { text = "\u{2192}", x = 8, y = 5.5 }, { text = "\u{2193}", x = 0, y = 11 },
    }
    for _, glyph in ipairs(glyphs) do
        new("TextLabel", {
            Parent = wrap, BackgroundTransparency = 1, Text = glyph.text,
            Size = UDim2.fromOffset(8, 5), Position = UDim2.fromOffset(glyph.x, glyph.y),
            TextSize = 8, Font = Enum.Font.GothamBold, TextColor3 = CONFIG.colorText,
        })
    end
end

local function buildCircleIcon(parent)
    local ring = new("Frame", {
        Name = "Ring", Parent = parent, BackgroundTransparency = 1, BorderSizePixel = 0,
        Size = UDim2.fromOffset(11, 11), Position = UDim2.fromScale(0.5, 0.5),
        AnchorPoint = Vector2.new(0.5, 0.5),
    })
    round(ring, 11)
    stroke(ring, CONFIG.colorText, 1.4, 0)
end

--============================================================
-- 06 · GUI
--============================================================

local function buildGui()
    gui = new("ScreenGui", {
        Name = CONFIG.guiName, ResetOnSpawn = false, IgnoreGuiInset = true,
        DisplayOrder = CONFIG.displayOrder, Parent = guiParent(),
    })
    panel = new("Frame", {
        Name = "Panel", Parent = gui, ClipsDescendants = true, BorderSizePixel = 0,
        Size = UDim2.fromOffset(CONFIG.panelWidth, CONFIG.panelHeight),
        Position = UDim2.fromOffset(CONFIG.panelX, CONFIG.panelY),
        BackgroundColor3 = CONFIG.colorPanel,
    })
    round(panel, CONFIG.cornerRadius)
    stroke(panel, CONFIG.colorStroke, 1, 0.25)
    local header = new("Frame", {
        Name = "Header", Parent = panel, BorderSizePixel = 0,
        Size = UDim2.new(1, 0, 0, CONFIG.headerHeight), BackgroundColor3 = CONFIG.colorHeader,
    })
    new("TextLabel", {
        Name = "Title", Parent = header, BackgroundTransparency = 1,
        Size = UDim2.new(1, -104, 1, 0), Position = UDim2.fromOffset(10, 0),
        Text = CONFIG.title, TextSize = CONFIG.titleSize, Font = Enum.Font.GothamBold,
        TextColor3 = CONFIG.colorText, TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Center,
    })
    local row = new("Frame", {
        Name = "Buttons", Parent = header, BackgroundTransparency = 1,
        Size = UDim2.new(0, 80, 1, 0), Position = UDim2.new(1, -6, 0, 0),
        AnchorPoint = Vector2.new(1, 0),
    })
    new("UIListLayout", {
        Parent = row, FillDirection = Enum.FillDirection.Horizontal,
        HorizontalAlignment = Enum.HorizontalAlignment.Right,
        VerticalAlignment = Enum.VerticalAlignment.Center,
        Padding = UDim.new(0, CONFIG.headerGap),
    })
    circleButton = new("TextButton", {
        Name = "CircleButton", Parent = row, LayoutOrder = 1, Text = "",
        Size = UDim2.fromOffset(CONFIG.headerButtonSize, CONFIG.headerButtonSize),
        BackgroundColor3 = CONFIG.colorButton, BorderSizePixel = 0, AutoButtonColor = false,
    })
    round(circleButton, 6)
    circleButtonStroke = stroke(circleButton, CONFIG.colorStroke, 1, 0.4)
    buildCircleIcon(circleButton)
    moveButton = new("TextButton", {
        Name = "MoveButton", Parent = row, LayoutOrder = 2, Text = "",
        Size = UDim2.fromOffset(CONFIG.headerButtonSize, CONFIG.headerButtonSize),
        BackgroundColor3 = CONFIG.colorButton, BorderSizePixel = 0, AutoButtonColor = false,
    })
    round(moveButton, 6)
    moveButtonStroke = stroke(moveButton, CONFIG.colorStroke, 1, 0.4)
    buildMoveIcon(moveButton)
    closeButton = new("TextButton", {
        Name = "CloseButton", Parent = row, LayoutOrder = 3, BorderSizePixel = 0,
        Size = UDim2.fromOffset(CONFIG.headerButtonSize, CONFIG.headerButtonSize),
        BackgroundColor3 = CONFIG.colorButton, Text = "\u{2715}", TextSize = 12,
        Font = Enum.Font.GothamBold, TextColor3 = CONFIG.colorText, AutoButtonColor = false,
    })
    round(closeButton, 6)
    stroke(closeButton, CONFIG.colorStroke, 1, 0.4)
    local body = new("Frame", {
        Name = "Body", Parent = panel, BorderSizePixel = 0,
        Size = UDim2.new(1, 0, 1, -CONFIG.headerHeight),
        Position = UDim2.fromOffset(0, CONFIG.headerHeight),
        BackgroundColor3 = CONFIG.colorBody,
    })
    new("UIPadding", {
        Parent = body, PaddingTop = UDim.new(0, CONFIG.bodyPadding),
        PaddingLeft = UDim.new(0, CONFIG.bodyPadding),
        PaddingRight = UDim.new(0, CONFIG.bodyPadding), PaddingBottom = UDim.new(0, 8),
    })
    new("UIListLayout", {
        Parent = body, FillDirection = Enum.FillDirection.Vertical,
        HorizontalAlignment = Enum.HorizontalAlignment.Center,
        VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 8),
    })
    noclipButton = new("TextButton", {
        Name = "NoclipButton", Parent = body, LayoutOrder = 1, Text = "",
        Size = UDim2.new(1, 0, 0, CONFIG.noclipHeight),
        BackgroundColor3 = CONFIG.colorOff, BorderSizePixel = 0, AutoButtonColor = false,
    })
    round(noclipButton, 8)
    stroke(noclipButton, Color3.fromRGB(255, 255, 255), 1, 0.75)
    noclipLabel = new("TextLabel", {
        Name = "Label", Parent = noclipButton, BackgroundTransparency = 1,
        Size = UDim2.fromScale(1, 1), Text = CONFIG.noclipLabel,
        TextSize = CONFIG.noclipTextSize, Font = Enum.Font.GothamBold,
        TextColor3 = Color3.fromRGB(255, 255, 255),
    })
    statusLabel = new("TextLabel", {
        Name = "Status", Parent = body, LayoutOrder = 2, BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 0, 14), Text = "idle", TextSize = 11,
        Font = Enum.Font.Gotham, TextColor3 = CONFIG.colorMuted,
        TextXAlignment = Enum.TextXAlignment.Center,
    })
    dot = new("TextButton", {
        Name = "Dot", Parent = gui, Visible = false, Text = "",
        Size = UDim2.fromOffset(CONFIG.dotCircleSize, CONFIG.dotCircleSize),
        Position = UDim2.fromOffset(CONFIG.panelX, CONFIG.panelY),
        BackgroundColor3 = CONFIG.colorPanel, BorderSizePixel = 0, AutoButtonColor = false,
    })
    round(dot, 1)
    stroke(dot, CONFIG.colorStroke, 1, 0.2)
    dotGlyph = new("Frame", {
        Name = "Glyph", Parent = dot, BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1),
    })
    buildCircleIcon(dotGlyph)
    dotLetter = new("TextLabel", {
        Name = "Letter", Parent = dot, BackgroundTransparency = 1,
        Size = UDim2.fromScale(1, 1), Text = CONFIG.dotLetter, TextSize = 13,
        Font = Enum.Font.GothamBold, TextColor3 = CONFIG.colorText, Visible = false,
    })
end

--============================================================
-- 07 · MODES
--============================================================

local function applyMode(mode)
    state.mode = mode
    if mode == "normal" then
        dot.Visible = false
        panel.Visible = true
        panel.Position = dot.Position
        local x, y = clampToScreen(panel.Position.X.Offset, panel.Position.Y.Offset,
            panel.AbsoluteSize.X, panel.AbsoluteSize.Y)
        panel.Position = UDim2.fromOffset(x, y)
        return
    end
    local size = (mode == "circle") and CONFIG.dotCircleSize or CONFIG.dotCollapsedSize
    dot.Size = UDim2.fromOffset(size, size)
    dotGlyph.Visible = (mode == "circle")
    dotLetter.Visible = (mode == "collapsed")
    local x, y = clampToScreen(panel.Position.X.Offset, panel.Position.Y.Offset, size, size)
    dot.Position = UDim2.fromOffset(x, y)
    panel.Visible = false
    dot.Visible = true
end

local function toggleMode(mode)
    applyMode(state.mode == mode and "normal" or mode)
end

--============================================================
-- 08 · DRAG
--============================================================

local function attachDrag(handle, target, options)
    options = options or {}
    track(handle.InputBegan:Connect(function(input)
        if input.UserInputType ~= Enum.UserInputType.MouseButton1
            and input.UserInputType ~= Enum.UserInputType.Touch then
            return
        end
        if options.condition and not options.condition() then
            return
        end
        local origin, startPos, moved = input.Position, target.Position, 0
        local watcher
        watcher = input.Changed:Connect(function()
            local delta = input.Position - origin
            moved = math.max(moved, delta.Magnitude)
            local x, y = clampToScreen(startPos.X.Offset + delta.X, startPos.Y.Offset + delta.Y,
                target.AbsoluteSize.X, target.AbsoluteSize.Y)
            target.Position = UDim2.fromOffset(x, y)
        end)
        input.Ended:Connect(function()
            if watcher then
                watcher:Disconnect()
            end
            if options.onEnd then
                options.onEnd(moved)
            end
        end)
    end))
end

--============================================================
-- 09 · ENGINE STATE
--============================================================

local stopEngine, startEngine
local saved, ghostHooks, engineConns = {}, {}, {}
local heartbeat, preStep, frameClock = nil, nil, 0
local lastPosition, guardClock, guardCount = nil, 0, 0
local freezeClock, lastHumanoid = 0, nil
local history, stuckClock, stuckAnchor = {}, 0, nil
local nudge = { active = false, direction = Vector3.zero, frames = 0 }

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.IgnoreWater = true
rayParams.RespectCanCollide = false

local probeParams = OverlapParams.new()
probeParams.FilterType = Enum.RaycastFilterType.Exclude
probeParams.RespectCanCollide = false

local ownParams = { [rayParams] = true, [probeParams] = true }

local function otherScriptOn()
    return getgenv().NoClip ~= nil or getgenv().NoClipSolid ~= nil
end

--============================================================
-- 10 · COLLISION GROUP
--============================================================

-- the contact is killed here, at a layer no property check can read.
-- parts keep CanCollide true the whole time
local groupReady = false

local function pollGroups()
    if not groupReady then
        return
    end
    local ok, groups = pcall(function()
        return PhysicsService:GetCollisionGroups()
    end)
    if not ok or not groups then
        return
    end
    for _, group in ipairs(groups) do
        pcall(function()
            PhysicsService:CollisionGroupSetCollidable(CONFIG.ghostGroup, group.name, false)
        end)
    end
end

local function ensureGroup()
    if groupReady then
        return true
    end
    if not pcall(function()
        PhysicsService:RegisterCollisionGroup(CONFIG.ghostGroup)
    end) then
        return false
    end
    pcall(function()
        PhysicsService:CollisionGroupSetCollidable(CONFIG.ghostGroup, CONFIG.ghostGroup, false)
    end)
    groupReady = true
    pollGroups()
    return true
end

--============================================================
-- 11 · CLAIM
--============================================================

local function claimPart(part)
    if not part:IsA("BasePart") then
        return
    end
    if not saved[part] then
        saved[part] = {
            collide = part.CanCollide, group = part.CollisionGroup,
            query = part.CanQuery, touch = part.CanTouch, anchor = part.Anchored,
        }
    end
    -- collision forced ON, then made harmless by the group. every read
    -- of the property is honest, so nothing looks unusual
    if not part.CanCollide then
        part.CanCollide = true
    end
    if groupReady and part.CollisionGroup ~= CONFIG.ghostGroup then
        part.CollisionGroup = CONFIG.ghostGroup
    end
    if not part.CanQuery then
        part.CanQuery = true
    end
    if not part.CanTouch then
        part.CanTouch = true
    end
    if part.Anchored then
        part.Anchored = false
    end
    if not ghostHooks[part] then
        ghostHooks[part] = {
            part:GetPropertyChangedSignal("CanCollide"):Connect(function()
                if state.noclip and not part.CanCollide then
                    part.CanCollide = true
                end
            end),
            part:GetPropertyChangedSignal("CollisionGroup"):Connect(function()
                if state.noclip and groupReady and part.CollisionGroup ~= CONFIG.ghostGroup then
                    part.CollisionGroup = CONFIG.ghostGroup
                end
            end),
            part:GetPropertyChangedSignal("CanQuery"):Connect(function()
                if state.noclip and not part.CanQuery then
                    part.CanQuery = true
                end
            end),
            part:GetPropertyChangedSignal("CanTouch"):Connect(function()
                if state.noclip and not part.CanTouch then
                    part.CanTouch = true
                end
            end),
            part:GetPropertyChangedSignal("Anchored"):Connect(function()
                if state.noclip and part.Anchored then
                    part.Anchored = false
                end
            end),
        }
    end
end

local function claimCharacter(character)
    for _, descendant in ipairs(character:GetDescendants()) do
        claimPart(descendant)
    end
end

local function clearHooks()
    for part, hooks in pairs(ghostHooks) do
        for _, connection in ipairs(hooks) do
            connection:Disconnect()
        end
        ghostHooks[part] = nil
    end
end

local function restoreAll()
    clearHooks()
    for part, values in pairs(saved) do
        if part and part.Parent then
            pcall(function()
                part.CanCollide = values.collide
                part.CollisionGroup = values.group
                part.CanQuery = values.query
                part.CanTouch = values.touch
                part.Anchored = values.anchor
            end)
        end
    end
    table.clear(saved)
end

--============================================================
-- 12 · METATABLE
--============================================================

-- belt over the group: CanCollide always reads true, and their raycasts
-- are forced to ignore it so they always hit a visible body
local hooked = false
local oldIndex, oldNamecall

local function hookSystem()
    if hooked or not getrawmetatable then
        return hooked
    end
    local ok = pcall(function()
        local mt = getrawmetatable(game)
        oldIndex, oldNamecall = mt.__index, mt.__namecall
        setreadonly(mt, false)
        mt.__index = newcclosure(function(self, key)
            if state.noclip and key == "CanCollide" and typeof(self) == "Instance" then
                local okPart, isPart = pcall(function()
                    return self:IsA("BasePart")
                end)
                if okPart and isPart then
                    return true
                end
            end
            return oldIndex(self, key)
        end)
        mt.__namecall = newcclosure(function(self, ...)
            if state.noclip and getnamecallmethod() == "Raycast" then
                local params = select(3, ...)
                if typeof(params) == "RaycastParams" and not ownParams[params] then
                    pcall(function()
                        params.RespectCanCollide = false
                    end)
                end
            end
            return oldNamecall(self, ...)
        end)
        setreadonly(mt, true)
    end)
    hooked = ok
    return ok
end

local function unhookSystem()
    if not hooked then
        return
    end
    pcall(function()
        local mt = getrawmetatable(game)
        setreadonly(mt, false)
        if oldIndex then
            mt.__index = oldIndex
        end
        if oldNamecall then
            mt.__namecall = oldNamecall
        end
        setreadonly(mt, true)
    end)
    hooked = false
end

--============================================================
-- 13 · SHIELD
--============================================================

local function shieldProp(inst, prop, fix)
    shield.hooks[inst] = shield.hooks[inst] or {}
    if shield.hooks[inst][prop] then
        return
    end
    shield.hooks[inst][prop] = inst:GetPropertyChangedSignal(prop):Connect(function()
        if state.noclip and not state.destroyed then
            pcall(fix)
        end
    end)
end

local function armShield(character, humanoid, root)
    shield.gravity, shield.walk = Workspace.Gravity, humanoid.WalkSpeed
    shield.jump, shield.hip = humanoid.JumpPower, humanoid.HipHeight
    shield.size = root.Size
    shieldProp(root, "Anchored", function() if root.Anchored then root.Anchored = false end end)
    shieldProp(root, "Size", function()
        if root.Size ~= shield.size then
            root.Size = shield.size
        end
    end)
    shieldProp(humanoid, "PlatformStand",
        function() if humanoid.PlatformStand then humanoid.PlatformStand = false end end)
    shieldProp(humanoid, "RequiresNeck",
        function() if humanoid.RequiresNeck then humanoid.RequiresNeck = false end end)
    shieldProp(humanoid, "AutoRotate",
        function() if not humanoid.AutoRotate then humanoid.AutoRotate = true end end)
    shieldProp(humanoid, "WalkSpeed", function()
        if humanoid.WalkSpeed <= 0 and shield.walk > 0 then
            humanoid.WalkSpeed = shield.walk
        end
    end)
    shieldProp(humanoid, "JumpPower", function()
        if humanoid.JumpPower <= 0 and shield.jump > 0 then
            humanoid.JumpPower = shield.jump
        end
    end)
    shieldProp(Workspace, "Gravity",
        function() if Workspace.Gravity < 1 then Workspace.Gravity = shield.gravity end end)
    shieldProp(character, "Parent", function()
        if character.Parent ~= Workspace and character.Parent then
            character.Parent = Workspace
        end
    end)
end

local function disarmShield()
    for inst, props in pairs(shield.hooks) do
        for _, connection in pairs(props) do
            connection:Disconnect()
        end
        shield.hooks[inst] = nil
    end
end

--============================================================
-- 14 · FLOOR
--============================================================

local function hoverStep(root, humanoid, velocity)
    local hip = humanoid.HipHeight or 0
    local offset = (root.Size.Y * 0.5) + hip + CONFIG.hoverHeight
    local result = Workspace:Raycast(root.Position,
        Vector3.new(0, -(CONFIG.stickRange + offset), 0), rayParams)
    if not result then
        return false
    end
    local difference = (result.Position.Y + offset) - root.Position.Y
    if math.abs(difference) < 0.02 then
        root.AssemblyLinearVelocity = Vector3.new(velocity.X, 0, velocity.Z)
    else
        local correction = math.clamp(difference * CONFIG.stickStiffness,
            -CONFIG.maxStickSpeed, CONFIG.maxStickSpeed)
        root.AssemblyLinearVelocity = Vector3.new(velocity.X, correction, velocity.Z)
    end
    return true
end

local function fallClamp(root, velocity)
    local result = Workspace:Raycast(root.Position, Vector3.new(0, -CONFIG.fallProbe, 0), rayParams)
    if not result or result.Distance > math.abs(velocity.Y) / 60 + CONFIG.fallMargin then
        return
    end
    local stop = result.Position.Y + (root.Size.Y * 0.5) + CONFIG.hoverHeight
    if root.Position.Y - stop < 1 then
        root.AssemblyLinearVelocity = Vector3.new(velocity.X, 0, velocity.Z)
    end
end

--============================================================
-- 15 · NUDGE
--============================================================

-- if the group layer ever fails the body can catch, so a plain velocity
-- nudge keeps it moving instead of standing in the wall
local function startNudge(root, humanoid)
    local move = humanoid.MoveDirection
    nudge.direction = move.Magnitude > 0.05 and horizontal(move).Unit or flatLook(root.CFrame)
    nudge.active = true
    nudge.frames = 0
end

local function stepNudge(root)
    if not nudge.active then
        return
    end
    nudge.frames += 1
    if nudge.frames > CONFIG.nudgeFrames then
        nudge.active = false
        return
    end
    local velocity = root.AssemblyLinearVelocity
    root.AssemblyLinearVelocity = nudge.direction * CONFIG.nudgeSpeed
        + Vector3.new(0, velocity.Y, 0)
end

--============================================================
-- 16 · GUARD
--============================================================

local function guardPosition(root, direction)
    local now = os.clock()
    if now - guardClock > 1 then
        guardCount = 0
    end
    local current = root.Position
    history[#history + 1] = current
    if #history > CONFIG.guardHistory then
        table.remove(history, 1)
    end
    if not lastPosition then
        lastPosition = current
        return
    end
    local flat = horizontal(current - lastPosition)
    if flat.Magnitude < CONFIG.guardDistance then
        lastPosition = current
        return
    end
    if flat.Unit:Dot(direction) > -0.2 or guardCount >= CONFIG.guardMaxPerSecond then
        lastPosition = current
        return
    end
    guardCount += 1
    local restore = history[math.max(1, #history - 2)] or lastPosition
    local keep = root.CFrame - root.Position
    root.CFrame = CFrame.new(restore) * keep
    root.AssemblyLinearVelocity = Vector3.zero
    lastPosition = restore
end

local function checkStuck(root, humanoid)
    if humanoid.MoveDirection.Magnitude < 0.05 then
        stuckAnchor, stuckClock = root.Position, 0
        return false
    end
    if not stuckAnchor then
        stuckAnchor = root.Position
        return false
    end
    if horizontal(root.Position - stuckAnchor).Magnitude > CONFIG.stuckEpsilon then
        stuckAnchor, stuckClock = root.Position, 0
        return false
    end
    stuckClock += 1
    if stuckClock >= CONFIG.stuckFrames then
        stuckClock, stuckAnchor = 0, root.Position
        return true
    end
    return false
end

--============================================================
-- 17 · PRE-PHYSICS STEP
--============================================================

local function applyStep()
    if not state.noclip then
        return
    end
    local character = LocalPlayer.Character
    if not character then
        return
    end
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    local root = character:FindFirstChild("HumanoidRootPart")
    if not humanoid or not root or root.Parent ~= character then
        return
    end
    if root.Anchored then
        root.Anchored = false
    end
    if nudge.active then
        stepNudge(root)
        return
    end
    local okState, humanoidState = pcall(function()
        return humanoid:GetState()
    end)
    if not okState then
        return
    end
    if humanoidState == Enum.HumanoidStateType.Swimming
        or humanoidState == Enum.HumanoidStateType.Climbing
        or humanoidState == Enum.HumanoidStateType.Seated then
        return
    end
    local velocity = root.AssemblyLinearVelocity
    if humanoidState == Enum.HumanoidStateType.Jumping or velocity.Y > 2 then
        return
    end
    hoverStep(root, humanoid, velocity)
end

--============================================================
-- 18 · SENSE
--============================================================

local function sense()
    local character = LocalPlayer.Character
    if not character or not character.Parent then
        return
    end
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    local root = character:FindFirstChild("HumanoidRootPart")
    if not humanoid or not root or root.Parent ~= character then
        return
    end
    frameClock += 1
    if frameClock <= CONFIG.burstFrames or frameClock % CONFIG.refreshRate == 0 then
        claimCharacter(character)
        pcall(function()
            root:SetNetworkOwner(LocalPlayer)
        end)
    end
    rayParams.FilterDescendantsInstances = { character }
    probeParams.FilterDescendantsInstances = { character }
    local okState, humanoidState = pcall(function()
        return humanoid:
