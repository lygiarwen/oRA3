--------------------------------------------------------------------------------
-- Setup
--

local oRA = LibStub("AceAddon-3.0"):GetAddon("oRA3")
local module = oRA:NewModule("Cooldowns", "AceEvent-3.0")
local L = LibStub("AceLocale-3.0"):GetLocale("oRA3")
local AceGUI = LibStub("AceGUI-3.0")
local candy = LibStub("LibCandyBar-3.0")
local media = LibStub("LibSharedMedia-3.0")

module.VERSION = tonumber(("$Revision$"):sub(12, -3))

--------------------------------------------------------------------------------
-- Locals
--

local mType = media and media.MediaType and media.MediaType.STATUSBAR or "statusbar"
local playerName = UnitName("player")
local _, playerClass = UnitClass("player")
local bloodlustId = UnitFactionGroup("player") == "Alliance" and 32182 or 2825

local glyphCooldowns = {
	[55455] = {2894, 600}, -- Fire Elemental Totem, 10min
	[58618] = {47476, 20}, -- Strangulate, 20sec
	[56373] = {31687, 30}, -- Summon Water Elemental, 30sec
	[63229] = {47585, 45}, -- Dispersion, 45sec
	[63329] = {871, 120}, -- Shield Wall, 2min
	[57903] = {5384, 5}, -- Feign Death, 5sec
	[57858] = {5209, 30}, -- Challenging Roar, 30sec
	[55678] = {6346, 60}, -- Fear Ward, 60sec
	[58376] = {12975, 60}, -- Last Stand, 1min
	[57955] = {633, 300}, -- Lay on Hands, 5min
}

local spells = {
	DRUID = {
		[26994] = 1200, -- Rebirth
		[29166] = 360, -- Innervate
		[17116] = 180, -- Nature's Swiftness
		[5209] = 180, -- Challenging Roar
	},
	HUNTER = {
		[34477] = 30, -- Misdirect
		[5384] = 30, -- Feign Death
		[62757] = 1800, -- Call Stabled Pet
		[781] = 25, -- Disengage
	},
	MAGE = {
		[45438] = 300, -- Iceblock
		[2139] = 24, -- Counterspell
		[31687] = 180, -- Summon Water Elemental
		[12051] = 240, -- Evocation
		[66] = 180, -- Invisibility
	},
	PALADIN = {
		[19752] = 1200, -- Divine Intervention
		[642] = 300, -- Divine Shield
		[64205] = 120, -- Divine Sacrifice
		[498] = 180, -- Divine Protection
		[10278] = 300, -- Hand of Protection
		[6940] = 120, -- Hand of Sacrifice
		[633] = 1200, -- Lay on Hands
	},
	PRIEST = {
		[33206] = 180, -- Pain Suppression
		[47788] = 180, -- Guardian Spirit
		[6346] = 180, -- Fear Ward
		[64843] = 600, -- Divine Hymn
		[64901] = 360, -- Hymn of Hope
		[34433] = 300, -- Shadowfiend
		[10060] = 120, -- Power Infusion
		[47585] = 180, -- Dispersion
	},
	ROGUE = {
		[31224] = 90, -- Cloak of Shadows
		[38768] = 10, -- Kick
		[1725] = 30, -- Distract
		[13750] = 180, -- Adrenaline Rush
		[13877] = 120, -- Blade Flurry
		[14177] = 180, -- Cold Blood
		[11305] = 180, -- Sprint
		[26889] = 180, -- Vanish
	},
	SHAMAN = {
		[bloodlustId] = 300, -- Bloodlust/Heroism
		[20608] = 3600, -- Reincarnation
		[16190] = 300, -- Mana Tide Totem
		[2894] = 1200, -- Fire Elemental Totem
		[2062] = 1200, -- Earth Elemental Totem
		[16188] = 180, -- Nature's Swiftness
	},
	WARLOCK = {
		[27239] = 1800, -- Soulstone Resurrection
		[29858] = 300, -- Soulshatter
		[47241] = 180, -- Metamorphosis
		[18708] = 900, -- Fel Domination
		[698] = 120, -- Ritual of Summoning
		[58887] = 300, -- Ritual of Souls
	},
	WARRIOR = {
		[871] = 300, -- Shield Wall
		[1719] = 300, -- Recklessness
		[20230] = 300, -- Retaliation
		[12975] = 180, -- Last Stand
		[6554] = 10, -- Pummel
		[1161] = 180, -- Challenging Shout
		[5246] = 180, -- Intimidating Shout
		[64380] = 300, -- Shattering Throw (could be 64382)
		[55694] = 180, -- Enraged Regeneration
	},
	DEATHKNIGHT = {
		[42650] = 1200, -- Army of the Dead
		[61999] = 900, -- Raise Ally
		[49028] = 90, -- Dancing Rune Weapon
		[49206] = 180, -- Summon Gargoyle
		[47476] = 120, -- Strangulate
		[49576] = 35, -- Death Grip
		[51271] = 120, -- Unbreakable Armor
		[55233] = 120, -- Vampiric Blood
		[49222] = 120, -- Bone Shield
		[47528] = 10, -- Mind Freeze
	},
}

local allSpells = {}
local classLookup = {}
for class, spells in pairs(spells) do
	for id, cd in pairs(spells) do
		allSpells[id] = cd
		classLookup[id] = class
	end
end

local classes = {}
do
	local hexColors = {}
	for k, v in pairs(RAID_CLASS_COLORS) do
		hexColors[k] = "|cff" .. string.format("%02x%02x%02x", v.r * 255, v.g * 255, v.b * 255)
	end
	for class in pairs(spells) do
		classes[class] = hexColors[class] .. L[class] .. "|r"
	end
	wipe(hexColors)
	hexColors = nil
end

local db = nil
local cdModifiers = {}
local broadcastSpells = {}

--------------------------------------------------------------------------------
-- GUI
--

local function onControlEnter(widget, event, value)
	GameTooltip:ClearLines()
	GameTooltip:SetOwner(widget.frame, "ANCHOR_CURSOR")
	GameTooltip:AddLine(widget.text and widget.text:GetText() or widget.label:GetText())
	GameTooltip:AddLine(widget:GetUserData("tooltip"), 1, 1, 1, 1)
	GameTooltip:Show()
end
local function onControlLeave() GameTooltip:Hide() end

local lockDisplay, unlockDisplay, isDisplayLocked, showDisplay, hideDisplay, isDisplayShown
local showPane, hidePane
do
	local frame = nil
	local tmp = {}
	local group = nil

	local function spellCheckboxCallback(widget, event, value)
		local id = widget:GetUserData("id")
		if not id then return end
		db.spells[id] = value and true or nil
	end

	local function dropdownGroupCallback(widget, event, key)
		widget:PauseLayout()
		widget:ReleaseChildren()
		wipe(tmp)
		if spells[key] then
			-- Class spells
			for id in pairs(spells[key]) do
				table.insert(tmp, id)
			end
			table.sort(tmp) -- ZZZ Sorted by spell ID, oh well!
			for i, v in ipairs(tmp) do
				local name = GetSpellInfo(v)
				if not name then break end
				local checkbox = AceGUI:Create("CheckBox")
				checkbox:SetLabel(name)
				checkbox:SetValue(db.spells[v] and true or false)
				checkbox:SetUserData("id", v)
				checkbox:SetCallback("OnValueChanged", spellCheckboxCallback)
				checkbox:SetFullWidth(true)
				widget:AddChild(checkbox)
			end
		end
		widget:ResumeLayout()
		-- DoLayout the parent to update the scroll bar for the new height of the dropdowngroup
		frame:DoLayout()
	end

	local function showCallback(widget, event, value)
		db.showDisplay = value
		if value then
			showDisplay()
		else
			hideDisplay()
		end
	end
	local function onlyMineCallback(widget, event, value)
		db.onlyShowMine = value
	end
	local function neverMineCallback(widget, event, value)
		db.neverShowMine = value
	end
	local function lockCallback(widget, event, value)
		db.lockDisplay = value
		if value then
			lockDisplay()
		else
			unlockDisplay()
		end
	end

	local function createFrame()
		if frame then return end
		frame = AceGUI:Create("ScrollFrame")
		frame:PauseLayout() -- pause here to stop excessive DoLayout invocations

		local monitorHeading = AceGUI:Create("Heading")
		monitorHeading:SetText(L["Monitor settings"])
		monitorHeading:SetFullWidth(true)
		
		local show = AceGUI:Create("CheckBox")
		show:SetLabel(L["Show monitor"])
		show:SetValue(db.showDisplay)
		show:SetCallback("OnEnter", onControlEnter)
		show:SetCallback("OnLeave", onControlLeave)
		show:SetCallback("OnValueChanged", showCallback)
		show:SetUserData("tooltip", L["Show or hide the cooldown bar display in the game world."])
		show:SetFullWidth(true)
		
		local lock = AceGUI:Create("CheckBox")
		lock:SetLabel(L["Lock monitor"])
		lock:SetValue(db.lockDisplay)
		lock:SetCallback("OnEnter", onControlEnter)
		lock:SetCallback("OnLeave", onControlLeave)
		lock:SetCallback("OnValueChanged", lockCallback)
		lock:SetUserData("tooltip", L["Note that locking the cooldown monitor will hide the title and the drag handle and make it impossible to move it, resize it or open the display options for the bars."])
		lock:SetFullWidth(true)

		local only = AceGUI:Create("CheckBox")
		only:SetLabel(L["Only show my own spells"])
		only:SetValue(db.onlyShowMine)
		only:SetCallback("OnEnter", onControlEnter)
		only:SetCallback("OnLeave", onControlLeave)
		only:SetCallback("OnValueChanged", onlyMineCallback)
		only:SetUserData("tooltip", L["Toggle whether the cooldown display should only show the cooldown for spells cast by you, basically functioning as a normal cooldown display addon."])
		only:SetFullWidth(true)
		
		local never = AceGUI:Create("CheckBox")
		never:SetLabel(L["Never show my own spells"])
		never:SetValue(db.neverShowMine)
		never:SetCallback("OnEnter", onControlEnter)
		never:SetCallback("OnLeave", onControlLeave)
		never:SetCallback("OnValueChanged", neverMineCallback)
		never:SetUserData("tooltip", L["Toggle whether the cooldown display should never show your own cooldowns. For example if you use another cooldown display addon for your own cooldowns."])
		never:SetFullWidth(true)

		local cooldownHeading = AceGUI:Create("Heading")
		cooldownHeading:SetText(L["Cooldown settings"])
		cooldownHeading:SetFullWidth(true)
		
		local moduleDescription = AceGUI:Create("Label")
		moduleDescription:SetText(L["Select which cooldowns to display using the dropdown and checkboxes below. Each class has a small set of spells available that you can view using the bar display. Select a class from the dropdown and then configure the spells for that class according to your own needs."])
		moduleDescription:SetFullWidth(true)
		moduleDescription:SetFontObject(GameFontHighlight)

		group = AceGUI:Create("DropdownGroup")
		group:SetTitle(L["Select class"])
		group:SetGroupList(classes)
		group:SetCallback("OnGroupSelected", dropdownGroupCallback)
		group.dropdown:SetWidth(120)
		group:SetGroup(playerClass)
		group:SetFullWidth(true)

		frame:AddChildren(monitorHeading, show, lock, only, never, cooldownHeading, moduleDescription, group)

		-- resume and update layout
		frame:ResumeLayout()
		frame:DoLayout()
	end

	function showPane()
		if not frame then createFrame() end
		oRA:SetAllPointsToPanel(frame.frame)
		frame.frame:Show()
	end

	function hidePane()
		if frame then
			frame:Release()
			frame = nil
		end
	end
end

--------------------------------------------------------------------------------
-- Bar config window
--

local restyleBars
local showBarConfig
do
	local function onTestClick() module:SpawnTestBar() end
	local function colorChanged(widget, event, r, g, b)
		db.barColor = {r, g, b, 1}
		if not db.barClassColor then
			restyleBars()
		end
	end
	local function toggleChanged(widget, event, value)
		local key = widget:GetUserData("key")
		if not key then return end
		db[key] = value
		restyleBars()
	end
	local function heightChanged(widget, event, value)
		db.barHeight = value
		restyleBars()
	end
	local function scaleChanged(widget, event, value)
		db.barScale = value
		restyleBars()
	end
	local function textureChanged(widget, event, value)
		local list = media:List(mType)
		db.barTexture = list[value]
		restyleBars()
	end
	local function alignChanged(widget, event, value)
		db.barLabelAlign = value
		restyleBars()
	end
	
	local plainFrame = nil
	local function show()
		if not plainFrame then
			plainFrame = CreateFrame("Frame", nil, UIParent)
			local f = plainFrame
			f:SetWidth(240)
			f:SetHeight(348)
			f:SetPoint("CENTER", UIParent, "CENTER")
			f:SetMovable(true)
			f:EnableMouse(true)
			f:SetClampedToScreen(true)
			
			local titlebg = f:CreateTexture(nil, "BACKGROUND")
			titlebg:SetTexture([[Interface\PaperDollInfoFrame\UI-GearManager-Title-Background]])
			titlebg:SetPoint("TOPLEFT", 9, -6)
			titlebg:SetPoint("BOTTOMRIGHT", f, "TOPRIGHT", -28, -24)
			
			local dialogbg = f:CreateTexture(nil, "BACKGROUND")
			dialogbg:SetTexture([[Interface\Tooltips\UI-Tooltip-Background]])
			dialogbg:SetPoint("TOPLEFT", 8, -24)
			dialogbg:SetPoint("BOTTOMRIGHT", -6, 8)
			dialogbg:SetVertexColor(0, 0, 0, .75)
			
			local topleft = f:CreateTexture(nil, "BORDER")
			topleft:SetTexture([[Interface\PaperDollInfoFrame\UI-GearManager-Border]])
			topleft:SetWidth(64)
			topleft:SetHeight(64)
			topleft:SetPoint("TOPLEFT")
			topleft:SetTexCoord(0.501953125, 0.625, 0, 1)
			
			local topright = f:CreateTexture(nil, "BORDER")
			topright:SetTexture([[Interface\PaperDollInfoFrame\UI-GearManager-Border]])
			topright:SetWidth(64)
			topright:SetHeight(64)
			topright:SetPoint("TOPRIGHT")
			topright:SetTexCoord(0.625, 0.75, 0, 1)
			
			local top = f:CreateTexture(nil, "BORDER")
			top:SetTexture([[Interface\PaperDollInfoFrame\UI-GearManager-Border]])
			top:SetHeight(64)
			top:SetPoint("TOPLEFT", topleft, "TOPRIGHT")
			top:SetPoint("TOPRIGHT", topright, "TOPLEFT")
			top:SetTexCoord(0.25, 0.369140625, 0, 1)
			
			local bottomleft = f:CreateTexture(nil, "BORDER")
			bottomleft:SetTexture([[Interface\PaperDollInfoFrame\UI-GearManager-Border]])
			bottomleft:SetWidth(64)
			bottomleft:SetHeight(64)
			bottomleft:SetPoint("BOTTOMLEFT")
			bottomleft:SetTexCoord(0.751953125, 0.875, 0, 1)
			
			local bottomright = f:CreateTexture(nil, "BORDER")
			bottomright:SetTexture([[Interface\PaperDollInfoFrame\UI-GearManager-Border]])
			bottomright:SetWidth(64)
			bottomright:SetHeight(64)
			bottomright:SetPoint("BOTTOMRIGHT")
			bottomright:SetTexCoord(0.875, 1, 0, 1)
			
			local bottom = f:CreateTexture(nil, "BORDER")
			bottom:SetTexture([[Interface\PaperDollInfoFrame\UI-GearManager-Border]])
			bottom:SetHeight(64)
			bottom:SetPoint("BOTTOMLEFT", bottomleft, "BOTTOMRIGHT")
			bottom:SetPoint("BOTTOMRIGHT", bottomright, "BOTTOMLEFT")
			bottom:SetTexCoord(0.376953125, 0.498046875, 0, 1)
			
			local left = f:CreateTexture(nil, "BORDER")
			left:SetTexture([[Interface\PaperDollInfoFrame\UI-GearManager-Border]])
			left:SetWidth(64)
			left:SetPoint("TOPLEFT", topleft, "BOTTOMLEFT")
			left:SetPoint("BOTTOMLEFT", bottomleft, "TOPLEFT")
			left:SetTexCoord(0.001953125, 0.125, 0, 1)
			
			local right = f:CreateTexture(nil, "BORDER")
			right:SetTexture([[Interface\PaperDollInfoFrame\UI-GearManager-Border]])
			right:SetWidth(64)
			right:SetPoint("TOPRIGHT", topright, "BOTTOMRIGHT")
			right:SetPoint("BOTTOMRIGHT", bottomright, "TOPRIGHT")
			right:SetTexCoord(0.1171875, 0.2421875, 0, 1)
			
			local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
			close:SetPoint("TOPRIGHT", 2, 1)
			close:SetScript("OnClick", function(self, button) f:Hide() end)
			
			local title = f:CreateFontString(nil, "ARTWORK")
			title:SetFontObject(GameFontNormal)
			title:SetPoint("TOPLEFT", 12, -8)
			title:SetPoint("TOPRIGHT", -32, -8)
			title:SetText(L["Bar Settings"])
			
			local titlebutton = CreateFrame("Button", nil, f)
			titlebutton:SetPoint("TOPLEFT", titlebg)
			titlebutton:SetPoint("BOTTOMRIGHT", titlebg)
			titlebutton:RegisterForDrag("LeftButton")
			titlebutton:SetScript("OnDragStart", function()
				f.moving = true
				f:StartMoving()
			end)
			titlebutton:SetScript("OnDragStop", function()
				f.moving = nil
				f:StopMovingOrSizing()
			end)
			
			local frame = AceGUI:Create("SimpleGroup")
			frame:SetLayout("Flow")
			frame:SetWidth(216) -- set width so flow layout fricking works
			frame:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -32)
			frame:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -12, 12)
			frame.frame:SetParent(f)

			local test = AceGUI:Create("Button")
			test:SetText(L["Spawn test bar"])
			test:SetCallback("OnClick", onTestClick)
			test:SetFullWidth(true)

			local classColor = AceGUI:Create("CheckBox")
			classColor:SetValue(db.barClassColor)
			classColor:SetLabel(L["Use class color"])
			classColor:SetUserData("key", "barClassColor")
			classColor:SetCallback("OnValueChanged", toggleChanged)
			classColor:SetRelativeWidth(0.7)

			local picker = AceGUI:Create("ColorPicker")
			picker:SetHasAlpha(false)
			picker:SetCallback("OnValueConfirmed", colorChanged)
			picker:SetRelativeWidth(0.3)
			picker:SetColor(unpack(db.barColor))

			local height = AceGUI:Create("Slider")
			height:SetLabel(L["Height"])
			height:SetValue(db.barHeight)
			height:SetSliderValues(8, 32, 1)
			height:SetCallback("OnValueChanged", heightChanged)
			height:SetRelativeWidth(0.5)
			height.editbox:Hide()
			
			local scale = AceGUI:Create("Slider")
			scale:SetLabel(L["Scale"])
			scale:SetValue(db.barScale)
			scale:SetSliderValues(0.1, 5.0, 0.1)
			scale:SetCallback("OnValueChanged", scaleChanged)
			scale:SetRelativeWidth(0.5)
			scale.editbox:Hide()

			local tex = AceGUI:Create("Dropdown")
			local list = media:List(mType)
			local selected = nil
			for k, v in pairs(list) do
				if v == db.barTexture then
					selected = k
				end
			end
			tex:SetList(media:List(mType))
			tex:SetValue(selected)
			tex:SetLabel(L["Texture"])
			tex:SetCallback("OnValueChanged", textureChanged)
			tex:SetFullWidth(true)
			
			local align = AceGUI:Create("Dropdown")
			align:SetList( { ["LEFT"] = L["Left"], ["CENTER"] = L["Center"], ["RIGHT"] = L["Right"] } )
			align:SetValue( db.barLabelAlign )
			align:SetLabel(L["Label Align"])
			align:SetCallback("OnValueChanged", alignChanged)
			align:SetFullWidth(true)

			local header = AceGUI:Create("Heading")
			header:SetText(L["Show"])
			header:SetFullWidth(true)
			
			local icon = AceGUI:Create("CheckBox")
			icon:SetValue(db.barShowIcon)
			icon:SetLabel(L["Icon"])
			icon:SetUserData("key", "barShowIcon")
			icon:SetCallback("OnValueChanged", toggleChanged)
			icon:SetRelativeWidth(0.5)
			
			local duration = AceGUI:Create("CheckBox")
			duration:SetValue(db.barShowDuration)
			duration:SetLabel(L["Duration"])
			duration:SetUserData("key", "barShowDuration")
			duration:SetCallback("OnValueChanged", toggleChanged)
			duration:SetRelativeWidth(0.5)
			
			local unit = AceGUI:Create("CheckBox")
			unit:SetValue(db.barShowUnit)
			unit:SetLabel(L["Unit name"])
			unit:SetUserData("key", "barShowUnit")
			unit:SetCallback("OnValueChanged", toggleChanged)
			unit:SetRelativeWidth(0.5)
			
			local spell = AceGUI:Create("CheckBox")
			spell:SetValue(db.barShowSpell)
			spell:SetLabel(L["Spell name"])
			spell:SetUserData("key", "barShowSpell")
			spell:SetCallback("OnValueChanged", toggleChanged)
			spell:SetRelativeWidth(0.5)
			
			local short = AceGUI:Create("CheckBox")
			short:SetValue(db.barShorthand)
			short:SetLabel(L["Short Spell name"])
			short:SetUserData("key", "barShorthand")
			short:SetCallback("OnValueChanged", toggleChanged)
			--short:SetRelativeWidth(0.5)
			
			frame:AddChildren(test, classColor, picker, height, scale, tex, align, header, icon, duration, unit, spell, short)
			frame.frame:Show()
		end
		plainFrame:Show()
	end
	showBarConfig = show
end

--------------------------------------------------------------------------------
-- Bar display
--

local startBar, setupCooldownDisplay, barStopped
do
	local display = nil
	local maximum = 10
	local bars = {}
	local visibleBars = {}
	local locked = nil
	local shown = nil
	function isDisplayLocked() return locked end
	function isDisplayShown() return shown end

	local function utf8trunc(text, num)
		local len = 0
		local i = 1
		local text_len = #text
		while len < num and i <= text_len do
			len = len + 1
			local b = text:byte(i)
			if b <= 127 then
				i = i + 1
			elseif b <= 223 then
				i = i + 2
			elseif b <= 239 then
				i = i + 3
			else
				i = i + 4
			end
		end
		return text:sub(1, i-1)
	end

	local shorts = setmetatable({}, {__index =
		function(self, key)
			if type(key) == "nil" then return nil end
			local p1, p2, p3, p4 = string.split(" ", (string.gsub(key,":", " :")))
			if not p2 then
				self[key] = utf8trunc(key, 4)
			elseif not p3 then
				self[key] = utf8trunc(p1, 1) .. utf8trunc(p2, 1)
			elseif not p4 then
				self[key] = utf8trunc(p1, 1) .. utf8trunc(p2, 1) .. utf8trunc(p3, 1)
			else
				self[key] = utf8trunc(p1, 1) .. utf8trunc(p2, 1) .. utf8trunc(p3, 1) .. utf8trunc(p4, 1)
			end
			return self[key]
		end
	})
	
	local function restyleBar(bar)
		bar:SetHeight(db.barHeight)
		bar:SetIcon(db.barShowIcon and bar:Get("ora3cd:icon") or nil)
		bar:SetTimeVisibility(db.barShowDuration)
		bar:SetScale(db.barScale)
		bar:SetTexture(media:Fetch(mType, db.barTexture))
		local spell = bar:Get("ora3cd:spell")
		if db.barShorthand then spell = shorts[spell] end
		if db.barShowSpell and db.barShowUnit and not db.onlyShowMine then
			bar:SetLabel(("%s: %s"):format(bar:Get("ora3cd:unit"), spell))
		elseif db.barShowSpell then
			bar:SetLabel(spell)
		elseif db.barShowUnit and not db.onlyShowMine then
			bar:SetLabel(bar:Get("ora3cd:unit"))
		else
			bar:SetLabel()
		end
		bar.candyBarLabel:SetJustifyH(db.barLabelAlign)
		if db.barClassColor then
			local c = RAID_CLASS_COLORS[bar:Get("ora3cd:unitclass")]
			bar:SetColor(c.r, c.g, c.b, 1)
		else
			bar:SetColor(unpack(db.barColor))
		end
	end
	
	function restyleBars()
		for bar in pairs(visibleBars) do
			restyleBar(bar)
		end
	end
	
	local function barSorter(a, b)
		return a.remaining < b.remaining and true or false
	end
	local tmp = {}
	local function rearrangeBars()
		wipe(tmp)
		for bar in pairs(visibleBars) do
			table.insert(tmp, bar)
		end
		table.sort(tmp, barSorter)
		local lastBar = nil
		for i, bar in ipairs(tmp) do
			bar:ClearAllPoints()
			if i <= maximum then
				if not lastBar then
					bar:SetPoint("TOPLEFT", display, 4, -4)
					bar:SetPoint("TOPRIGHT", display, -4, -4)
				else
					bar:SetPoint("TOPLEFT", lastBar, "BOTTOMLEFT")
					bar:SetPoint("TOPRIGHT", lastBar, "BOTTOMRIGHT")
				end
				lastBar = bar
				bar:Show()
			else
				bar:Hide()
			end
		end
	end

	function barStopped(event, bar)
		if visibleBars[bar] then
			visibleBars[bar] = nil
			rearrangeBars()
		end
	end

	local function OnDragHandleMouseDown(self) self.frame:StartSizing("BOTTOMRIGHT") end
	local function OnDragHandleMouseUp(self, button) self.frame:StopMovingOrSizing() end
	local function onResize(self, width, height)
		oRA3:SavePosition("oRA3CooldownFrame")
		maximum = math.floor(height / db.barHeight)
		-- if we have that many bars shown, hide the ones that overflow
		rearrangeBars()
	end
	
	local function displayOnMouseDown(self, button)
		if button == "RightButton" then showBarConfig() end
	end
	
	local function onDragStart(self) self:StartMoving() end
	local function onDragStop(self)
		self:StopMovingOrSizing()
		oRA3:SavePosition("oRA3CooldownFrame")
	end
	local function onEnter(self)
		if not next(visibleBars) then self.help:Show() end
	end
	local function onLeave(self) self.help:Hide() end

	function lockDisplay()
		if locked then return end
		display:EnableMouse(false)
		display:SetMovable(false)
		display:SetResizable(false)
		display:RegisterForDrag()
		display:SetScript("OnSizeChanged", nil)
		display:SetScript("OnDragStart", nil)
		display:SetScript("OnDragStop", nil)
		display:SetScript("OnMouseDown", nil)
		display:SetScript("OnEnter", nil)
		display:SetScript("OnLeave", nil)
		display.drag:Hide()
		display.header:Hide()
		display.bg:SetTexture(0, 0, 0, 0)
		locked = true
	end
	function unlockDisplay()
		if not locked then return end
		display:EnableMouse(true)
		display:SetMovable(true)
		display:SetResizable(true)
		display:RegisterForDrag("LeftButton")
		display:SetScript("OnSizeChanged", onResize)
		display:SetScript("OnDragStart", onDragStart)
		display:SetScript("OnDragStop", onDragStop)
		display:SetScript("OnMouseDown", displayOnMouseDown)
		display:SetScript("OnEnter", onEnter)
		display:SetScript("OnLeave", onLeave)
		display.bg:SetTexture(0, 0, 0, 0.3)
		display.drag:Show()
		display.header:Show()
		locked = nil
	end
	function showDisplay()
		display:Show()
		shown = true
	end
	function hideDisplay()
		display:Hide()
		shown = nil
	end

	local function setup()
		display = CreateFrame("Frame", "oRA3CooldownFrame", UIParent)
		display:SetMinResize(100, 20)
		display:SetWidth(200)
		display:SetHeight(148)
		oRA3:RestorePosition("oRA3CooldownFrame")
		local bg = display:CreateTexture(nil, "PARENT")
		bg:SetAllPoints(display)
		bg:SetBlendMode("BLEND")
		bg:SetTexture(0, 0, 0, 0.3)
		display.bg = bg
		local header = display:CreateFontString(nil, "OVERLAY")
		header:SetFontObject(GameFontNormal)
		header:SetText("Cooldowns")
		header:SetPoint("BOTTOM", display, "TOP", 0, 4)
		local help = display:CreateFontString(nil, "OVERLAY")
		help:SetFontObject(GameFontNormal)
		help:SetText(L["Right-Click me for options!"])
		help:SetAllPoints(display)
		help:Hide()
		display.help = help
		display.header = header

		local drag = CreateFrame("Frame", nil, display)
		drag.frame = display
		drag:SetFrameLevel(display:GetFrameLevel() + 10) -- place this above everything
		drag:SetWidth(16)
		drag:SetHeight(16)
		drag:SetPoint("BOTTOMRIGHT", display, -1, 1)
		drag:EnableMouse(true)
		drag:SetScript("OnMouseDown", OnDragHandleMouseDown)
		drag:SetScript("OnMouseUp", OnDragHandleMouseUp)
		drag:SetAlpha(0.5)
		display.drag = drag

		local tex = drag:CreateTexture(nil, "BACKGROUND")
		tex:SetTexture("Interface\\AddOns\\oRA3\\images\\draghandle")
		tex:SetWidth(16)
		tex:SetHeight(16)
		tex:SetBlendMode("ADD")
		tex:SetPoint("CENTER", drag)

		if db.lockDisplay then
			locked = nil
			lockDisplay()
		else
			locked = true
			unlockDisplay()
		end
		if db.showDisplay then
			shown = true
			showDisplay()
		else
			shown = nil
			hideDisplay()
		end
	end
	setupCooldownDisplay = setup
	
	local function start(unit, id, name, icon, duration)
		local bar
		for b, v in pairs(visibleBars) do
			if b:Get("ora3cd:unit") == unit and b:Get("ora3cd:spell") == name then
				bar = b
				break;
			end
		end
		if not bar then
			bar = candy:New("Interface\\AddOns\\oRA3\\images\\statusbar", display:GetWidth(), db.barHeight)
		end
		visibleBars[bar] = true
		bar:Set("ora3cd:unitclass", classLookup[id])
		bar:Set("ora3cd:unit", unit)
		bar:Set("ora3cd:spell", name)
		bar:Set("ora3cd:icon", icon)
		bar:SetDuration(duration)
		restyleBar(bar)
		bar:Start()
		rearrangeBars()
	end
	startBar = start
end

--------------------------------------------------------------------------------
-- Module
--

function module:OnRegister()
	local database = oRA.db:RegisterNamespace("Cooldowns", {
		profile = {
			spells = {
				[26994] = true,
				[19752] = true,
				[20608] = true,
				[27239] = true,
			},
			showDisplay = false,
			onlyShowMine = nil,
			neverShowMine = nil,
			lockDisplay = false,
			barShorthand = false,
			barHeight = 14,
			barScale = 1.0,
			barShowIcon = true,
			barShowDuration = true,
			barShowUnit = true,
			barShowSpell = true,
			barClassColor = true,
			barLabelAlign = "CENTER",
			barColor = { 0.25, 0.33, 0.68, 1 },
			barTexture = "oRA3",
		},
	})
	db = database.profile

	oRA:RegisterPanel(
		L["Cooldowns"],
		showPane,
		hidePane
	)

	-- These are the spells we broadcast to the raid
	for spell, cd in pairs(spells[playerClass]) do
		local name = GetSpellInfo(spell)
		if name then broadcastSpells[name] = spell end
	end
	
	setupCooldownDisplay()
	
	oRA.RegisterCallback(self, "OnCommCooldown")
	oRA.RegisterCallback(self, "OnStartup")
	oRA.RegisterCallback(self, "OnShutdown")
	
	candy.RegisterCallback(self, "LibCandyBar_Stop", barStopped)
	if media then
		media:Register(mType, "oRA3", "Interface\\AddOns\\oRA3\\images\\statusbar")
	end
end

do
	local spellList, reverseClass = nil, nil
	function module:SpawnTestBar()
		if not spellList then
			spellList = {}
			reverseClass = {}
			for k in pairs(allSpells) do table.insert(spellList, k) end
			for name, class in pairs(oRA._testUnits) do reverseClass[class] = name end
		end
		local spell = spellList[math.random(1, #spellList)]
		local name, _, icon = GetSpellInfo(spell)
		if not name then return end
		local unit = reverseClass[classLookup[spell]]
		local duration = (allSpells[spell] / 30) + math.random(1, 120)
		startBar(unit, spell, name, icon, duration)
	end
end

local function getCooldown(spellId)
	local cd = spells[playerClass][spellId]
	if cdModifiers[spellId] then
		cd = cd - cdModifiers[spellId]
	end
	return cd
end

function module:OnEnable()
	--self:RegisterEvent("CHARACTER_POINTS_CHANGED", "UpdateCooldownModifiers")
	self:RegisterEvent("PLAYER_TALENT_UPDATE", "UpdateCooldownModifiers")
	self:UpdateCooldownModifiers()
end

function module:OnStartup()
	self:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
	if playerClass == "SHAMAN" then
		local resTime = GetTime()
		local ankhs = GetItemCount(17030)
		self:RegisterEvent("PLAYER_ALIVE", function()
			resTime = GetTime()
		end)
		self:RegisterEvent("BAG_UPDATE", function()
			if (GetTime() - (resTime or 0)) > 1 then return end
			local newankhs = GetItemCount(17030)
			if newankhs == (ankhs - 1) then
				oRA:SendComm("Cooldown", 20608, getCooldown(20608)) -- Spell ID + CD in seconds
			end
			ankhs = newankhs
		end)
	end
end

function module:OnShutdown()
	self:UnregisterEvent("UNIT_SPELLCAST_SUCCEEDED")
end

function module:OnCommCooldown(commType, sender, spell, cd)
	--print("We got a cooldown for " .. tostring(spell) .. " (" .. tostring(cd) .. ") from " .. tostring(sender))
	if type(spell) ~= "number" or type(cd) ~= "number" then error("Spell or number had the wrong type.") end
	if not db.spells[spell] then return end
	if db.onlyShowMine and sender ~= playerName then return end
	if db.neverShowMine and sender == playerName then return end
	local name, _, icon = GetSpellInfo(spell)
	if not name or not icon then return end
	startBar(sender, spell, name, icon, cd)
end

local function addMod(s, m)
	if m == 0 then return end
	if not cdModifiers[s] then
		cdModifiers[s] = m
	else
		cdModifiers[s] = cdModifiers[s] + m
	end
end

function module:UpdateCooldownModifiers()
	wipe(cdModifiers)
	for i = 1, GetNumGlyphSockets() do
		local enabled, _, spellId = GetGlyphSocketInfo(i)
		if enabled and spellId and glyphCooldowns[spellId] then
			local info = glyphCooldowns[spellId]
			addMod(info[1], info[2])
		end
	end
	if playerClass == "PALADIN" then
		local _, _, _, _, rank = GetTalentInfo(2, 4)
		addMod(10278, rank * 60)
		_, _, _, _, rank = GetTalentInfo(1, 8)
		addMod(633, rank * 120)
		_, _, _, _, rank = GetTalentInfo(2, 14)
		addMod(642, rank * 30)
		addMod(498, rank * 30)
	elseif playerClass == "SHAMAN" then
		local _, _, _, _, rank = GetTalentInfo(3, 3)
		addMod(20608, rank * 600)
	elseif playerClass == "WARRIOR" then
		local _, _, _, _, rank = GetTalentInfo(3, 13)
		addMod(871, rank * 30)
		addMod(1719, rank * 30)
		addMod(20230, rank * 30)
	elseif playerClass == "DEATHKNIGHT" then
		local _, _, _, _, rank = GetTalentInfo(3, 6)
		addMod(49576, rank * 5)
	elseif playerClass == "HUNTER" then
		local _, _, _, _, rank = GetTalentInfo(3, 11)
		addMod(781, rank * 2)
	elseif playerClass == "MAGE" then
		local _, _, _, _, rank = GetTalentInfo(1, 24)
		addMod(12051, rank * 60)
		if rank > 0 then
			local percent = rank * 15
			local currentCd = getCooldown(66)
			addMod(66, (currentCd * percent) / 100)
		end
	elseif playerClass == "PRIEST" then
		local _, _, _, _, rank = GetTalentInfo(1, 23)
		if rank > 0 then
			local percent = rank * 10
			local currentCd = getCooldown(10060)
			addMod(10060, (currentCd * percent) / 100)
			currentCd = getCooldown(33206)
			addMod(33206, (currentCd * percent) / 100)
		end
	elseif playerClass == "ROGUE" then
		local _, _, _, _, rank = GetTalentInfo(2, 7)
		addMod(11305, rank * 30)
		_, _, _, _, rank = GetTalentInfo(3, 7)
		addMod(26889, rank * 30)
		addMod(31224, rank * 15)
		_, _, _, _, rank = GetTalentInfo(3, 26)
		addMod(1725, rank * 5)
	end
end

function module:UNIT_SPELLCAST_SUCCEEDED(event, unit, spell)
	if unit ~= "player" then return end
	if broadcastSpells[spell] then
		local spellId = broadcastSpells[spell]
		oRA:SendComm("Cooldown", spellId, getCooldown(spellId)) -- Spell ID + CD in seconds
	end
end

