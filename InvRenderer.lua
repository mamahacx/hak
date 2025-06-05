--[[--------------------------------------------------------------------
 InvRenderer – v5.3.2 (Head Disappearing Fix + Dummy Anchoring + Clean Camera Create)
 • Fixes DummyAvatar head disappearing by making cloned accessory parts Massless.
 • Anchors all parts of DummyAvatar and makes them Massless for stability.
 • Script creates ViewportCam under AvatarDisplay if not found, with user's CFrame/FOV.
 • Correctly updates Equip/Unequip button for Pickaxes with client-side prediction.
 • Sorts items by Rarity, Type, ArmorSlot (for SuitPieces), then Name.
 • Sets LayoutOrder property on cards for UIGridLayout.
 • Displays specific ArmorSlot type in detail panel instead of generic "SuitPiece".
 • Uses specific icons for ArmorSlots in detail panel.
 • Updates DummyAvatar in EquipmentDock to reflect player's equipped armor.
 • Adds hover highlight effect to armor pieces on DummyAvatar.
 • Implements EquipButton functionality for Pickaxe AND SuitPiece items.
 • Fires events to server for equipping/unequipping Pickaxes AND Armor.
 • Syncs equipped state for both Pickaxes AND Armor from server on init/respawn.
 ---------------------------------------------------------------------]]

-----------------------------------------------------------------------\
--  Services & shared modules
-----------------------------------------------------------------------\
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local ItemDefs  = require(ReplicatedStorage:WaitForChild("ItemDefs"))
local Remote    = ReplicatedStorage:WaitForChild("InvSync") -- Main inventory sync

local InvConst  = require(script.Parent.Parent:WaitForChild("InventoryConstants"))
local RarityCol = InvConst.RarityColours

-- Pickaxe RemoteEvents and Functions
local EquipPickaxeGearEvent = ReplicatedStorage:WaitForChild("EquipPickaxeGearEvent")
local UnequipPickaxeGearEvent = ReplicatedStorage:WaitForChild("UnequipPickaxeGearEvent")
local GetEquippedPickaxeState = ReplicatedStorage:WaitForChild("GetEquippedPickaxeState")

-- Armor RemoteEvents and Function
local EquipArmorEventRemote = ReplicatedStorage:WaitForChild("EquipArmorEvent")
local UnequipArmorEventRemote = ReplicatedStorage:WaitForChild("UnequipArmorEvent")
local GetEquippedArmorStateRemote = ReplicatedStorage:WaitForChild("GetEquippedArmorState")
local ArmorSyncEvent = ReplicatedStorage:WaitForChild("ArmorSync")

-----------------------------------------------------------------------\
--  Sorting Order Tables
-----------------------------------------------------------------------\
local RARITY_SORT_ORDER = { Mythical=6, Legendary=5, Epic=4, Rare=3, Uncommon=2, Common=1, Default=0 }
local TYPE_SORT_ORDER = { Pickaxe=4, Crystal=3, SuitPiece=2, Other=1, Default=0 }
local ARMOR_SLOT_SORT_ORDER = { Helmet=6, Chestplate=5, Bracers=4, Gauntlets=3, Leggings=2, Boots=1, Default=0 }

-----------------------------------------------------------------------\
--  GUI references
-----------------------------------------------------------------------\
local gui       = script.Parent
local mainFrame = gui:WaitForChild("MainFrame")
local grid      = mainFrame:WaitForChild("ItemGrid")
local template  = grid:WaitForChild("ItemCardTemplate")
local detail    = mainFrame:WaitForChild("DetailPanel")
local equipButton = mainFrame:WaitForChild("EquipButton")

local independentCountLabel     = mainFrame:WaitForChild("IndependentCountLabel")
local independentDetailTypeIcon = mainFrame:WaitForChild("IndependentDetailTypeIcon")

local equipmentDock = mainFrame:WaitForChild("EquipmentDock")
local avatarDisplay = equipmentDock:WaitForChild("AvatarDisplay")
local avatarWorld = avatarDisplay:WaitForChild("AvatarWorld")
local dummyAvatarModel = avatarWorld:WaitForChild("DummyAvatar")
local viewportCamera = nil -- Will be created/assigned in initializeAndSync

-----------------------------------------------------------------------\
--  Appearance Constants for EquipButton
-----------------------------------------------------------------------\
local EQUIP_BUTTON_DEFAULT_BG_COLOR = Color3.fromRGB(0, 189, 13)
local EQUIP_BUTTON_DEFAULT_BORDER_COLOR = Color3.fromRGB(5, 95, 0)
local UNEQUIP_BUTTON_BG_COLOR = Color3.fromRGB(200, 60, 60)
local UNEQUIP_BUTTON_BORDER_COLOR = Color3.fromRGB(150, 40, 40)

-----------------------------------------------------------------------\
--  state
-----------------------------------------------------------------------\
local currentlySelectedCard = nil
local currentlyEquippedPickaxeId = nil
local currentlySelectedItemInfo = nil
local equippedArmorSlots = {}

local isMouseOverViewport = false
local currentlyHoveredAccessoryPart = nil
local currentHighlightClone = nil

local highlightRaycastParams = RaycastParams.new()
highlightRaycastParams.FilterType = Enum.RaycastFilterType.Include
highlightRaycastParams.FilterDescendantsInstances = {dummyAvatarModel}

-----------------------------------------------------------------------\
--  lookup tables
-----------------------------------------------------------------------\
local TypeIcons = {
	Crystal    = "rbxassetid://85975584277283",
	Pickaxe    = "rbxassetid://70425302178746",
	SuitPiece  = "rbxassetid://120897419587052", 
	Other      = "rbxassetid://121566773164449",
}
local ArmorSlotIcons = { 
	Helmet     = "rbxassetid://120897419587052", 
	Chestplate = "rbxassetid://98091445604273",
	Bracers    = "rbxassetid://117578556913774", 
	Gauntlets  = "rbxassetid://77447896018172",
	Leggings   = "rbxassetid://103547109735930", 
	Boots      = "rbxassetid://85566592392770",
	Default    = TypeIcons.SuitPiece
}
local DUMMY_AVATAR_PART_MAP = {
	Helmet = { PartName = "Head", AttachmentName = "HatAttachment" },
	Chestplate = { PartName = "UpperTorso", AttachmentName = "BodyFrontAttachment" },
	RightGauntlet = { PartName = "RightHand", AttachmentName = "RightGripAttachment" },
	LeftGauntlet = { PartName = "LeftHand", AttachmentName = "LeftGripAttachment" },
	RightBoot = { PartName = "RightFoot", AttachmentName = "RightFootAttachment" },
	LeftBoot = { PartName = "LeftFoot", AttachmentName = "LeftFootAttachment" },
	-- Ensure PartNames exist in DummyAvatar and they (and accessory Handles) have these Attachments.
}

local BG_NORMAL = {Common="rbxassetid://134128052288586",Uncommon="rbxassetid://120889455288372",Rare="rbxassetid://77332589446988",Epic="rbxassetid://116549055440678",Legendary="rbxassetid://84459473169975",Mythical="rbxassetid://92314227237368",Default="rbxassetid://134128052288586"}
local BG_HOVER = {Common="rbxassetid://70429029183567",Uncommon="rbxassetid://101767010955289",Rare="rbxassetid://102008356818997",Epic="rbxassetid://123574456520365",Legendary="rbxassetid://100726613602825",Mythical="rbxassetid://140441766213439",Default="rbxassetid://70429029183567"}
local BG_SELECTED = {Common="rbxassetid://76362948244335",Uncommon="rbxassetid://83203418311852",Rare="rbxassetid://100748755457345",Epic="rbxassetid://121748856705163",Legendary="rbxassetid://71010507098208",Mythical="rbxassetid://73211337228185",Default="rbxassetid://76362948244335"}
local function getRootBackground(r,s)if s=="Hover"then return BG_HOVER[r]or BG_HOVER.Default end;if s=="Selected"then return BG_SELECTED[r]or BG_SELECTED.Default end;return BG_NORMAL[r]or BG_NORMAL.Default end
local function clearGrid()for _,c in ipairs(grid:GetChildren())do if(c:IsA("ImageLabel")or c:IsA("Frame"))and c~=template then c:Destroy()end end end
local function applyCardRootVisual(c,r,s)if c:IsA("ImageLabel")then c.Image=getRootBackground(r,s)end end
local function fillNestedIcons(c,rK,iId)local b=c:FindFirstChild("BackgroundIcon")if b and b:IsA("ImageLabel")then b.Image=BG_NORMAL[rK]or BG_NORMAL.Default;local f=b:FindFirstChild("Icon")if f and f:IsA("ImageLabel")then f.Image=iId or""end;return end;local l=c:FindFirstChild("Icon")if l and l:IsA("ImageLabel")then l.Image=iId or""end end

local function updateDummyAvatarArmor()
	if not dummyAvatarModel then return end
	if not viewportCamera then return end 

	for _, child in ipairs(dummyAvatarModel:GetChildren()) do
		if child:GetAttribute("IsDummyArmorVisual") then child:Destroy() end
	end
	for slotName, itemId in pairs(equippedArmorSlots) do
		if itemId then 
			local itemDef = ItemDefs[itemId]
			if itemDef and itemDef.Type == "SuitPiece" and itemDef.AccessoryRef and itemDef.ArmorSlot == slotName then
				local accessoryTemplate = ReplicatedStorage.ArmorAssets:FindFirstChild(itemDef.AccessoryRef)
				if accessoryTemplate and accessoryTemplate:IsA("Accessory") then
					local targetPartInfo = DUMMY_AVATAR_PART_MAP[slotName] 
					local dummyPartTarget = targetPartInfo and dummyAvatarModel:FindFirstChild(targetPartInfo.PartName, true)
					if dummyPartTarget and dummyPartTarget:IsA("BasePart") then
						local handleToClone = accessoryTemplate:FindFirstChild("Handle")
						if handleToClone and handleToClone:IsA("BasePart") then
							local newVisualPart = handleToClone:Clone()
							newVisualPart.Name = slotName .. "DummyVisual"; newVisualPart:SetAttribute("IsDummyArmorVisual", true) 
							newVisualPart.Parent = dummyAvatarModel; 

							newVisualPart.Anchored = false 
							newVisualPart.CanCollide = false; newVisualPart.CanTouch = false; newVisualPart.CanQuery = false
							newVisualPart.Massless = true -- <<<< FIX: Make cloned accessory part massless

							if newVisualPart:IsA("MeshPart") or newVisualPart:IsA("Part") then newVisualPart.TextureID = "" end
							local exTex = newVisualPart:FindFirstChildOfClass("Texture") if exTex then exTex:Destroy() end
							local exSA = newVisualPart:FindFirstChildOfClass("SurfaceAppearance") if exSA then exSA:Destroy() end
							local weld = Instance.new("WeldConstraint"); weld.Part0 = dummyPartTarget; weld.Part1 = newVisualPart; weld.Parent = newVisualPart 
							local accHandleAttName; for _,o in ipairs(handleToClone:GetChildren())do if o:IsA("Attachment")then accHandleAttName=o.Name;break end end
							local dummyPartAttName = targetPartInfo.AttachmentName
							if accHandleAttName and dummyPartAttName then
								local accAttInst=handleToClone:FindFirstChild(accHandleAttName); local dumAttInst=dummyPartTarget:FindFirstChild(dummyPartAttName)
								if accAttInst and dumAttInst then newVisualPart.CFrame=dumAttInst.WorldCFrame*accAttInst.CFrame:Inverse()
								else newVisualPart.CFrame=dummyPartTarget.CFrame; warn("InvR: Attachments missing for",newVisualPart.Name,"on",dummyPartTarget.Name) end
							else newVisualPart.CFrame=dummyPartTarget.CFrame; warn("InvR: Att names not spec for",slotName,"for",newVisualPart.Name) end
						end
					end
				end
			end
		end
	end
end

local function updateEquipButtonDisplayState()
	if not currentlySelectedItemInfo or not currentlySelectedItemInfo.def then equipButton.Visible=false;return end
	local def=currentlySelectedItemInfo.def; local itemId=currentlySelectedItemInfo.id
	if def.Type=="Pickaxe"then equipButton.Visible=true;if itemId==currentlyEquippedPickaxeId then equipButton.Text="Unequip";equipButton.BackgroundColor3=UNEQUIP_BUTTON_BG_COLOR;equipButton.BorderColor3=UNEQUIP_BUTTON_BORDER_COLOR else equipButton.Text="Equip";equipButton.BackgroundColor3=EQUIP_BUTTON_DEFAULT_BG_COLOR;equipButton.BorderColor3=EQUIP_BUTTON_DEFAULT_BORDER_COLOR end
	elseif def.Type=="SuitPiece"and def.ArmorSlot then equipButton.Visible=true;local s=def.ArmorSlot;if equippedArmorSlots[s]and equippedArmorSlots[s]==itemId then equipButton.Text="Unequip";equipButton.BackgroundColor3=UNEQUIP_BUTTON_BG_COLOR;equipButton.BorderColor3=UNEQUIP_BUTTON_BORDER_COLOR else equipButton.Text="Equip";equipButton.BackgroundColor3=EQUIP_BUTTON_DEFAULT_BG_COLOR;equipButton.BorderColor3=EQUIP_BUTTON_DEFAULT_BORDER_COLOR end
	else equipButton.Visible=false;equipButton.BackgroundColor3=EQUIP_BUTTON_DEFAULT_BG_COLOR;equipButton.BorderColor3=EQUIP_BUTTON_DEFAULT_BORDER_COLOR end
end

local function makeCard(info, sortIndex) 
	local def=ItemDefs[info.id]or{Name="??",Icon="",Description="Unknown item.",Type="Other",Rarity="Common",Stackable=true}
	local qty=info.n or 1;local rK=def.Rarity or"Default";local c=template:Clone();c.Name=info.id;c.Visible=true
	if sortIndex then c.LayoutOrder=sortIndex end
	c:SetAttribute("ItemType",def.Type);c:SetAttribute("ItemRarity",rK);c:SetAttribute("ItemName",string.lower(def.Name or"unknown"))
	applyCardRootVisual(c,rK,"Normal");fillNestedIcons(c,rK,def.Icon)
	local nL=c:FindFirstChild("NameLabel")if nL and nL:IsA("TextLabel")then nL.Text=def.Name end
	local tI=c:FindFirstChild("TypeIcon")if tI and tI:IsA("ImageLabel")then if def.Type=="SuitPiece"and def.ArmorSlot then tI.Image=ArmorSlotIcons[def.ArmorSlot]or ArmorSlotIcons.Default else tI.Image=TypeIcons[def.Type]or TypeIcons.Other end end
	local cL=c:FindFirstChild("CountLabel")if cL and cL:IsA("TextLabel")then if def.Stackable and qty>1 then cL.Text="x"..qty;cL.Visible=true else cL.Visible=false end end
	c.MouseEnter:Connect(function()if c~=currentlySelectedCard then applyCardRootVisual(c,rK,"Hover")end end)
	c.MouseLeave:Connect(function()if c~=currentlySelectedCard then applyCardRootVisual(c,rK,"Normal")end end)
	local clk=c:FindFirstChild("ClickDetector")::TextButton;if clk then clk.MouseButton1Click:Connect(function()if currentlySelectedCard and currentlySelectedCard~=c then local oR=currentlySelectedCard:GetAttribute("ItemRarity")or"Default";applyCardRootVisual(currentlySelectedCard,oR,"Normal")end;currentlySelectedCard=c;applyCardRootVisual(c,rK,"Selected")
			currentlySelectedItemInfo={id=info.id,def=def,qty=qty}
			if detail and detail:IsA("Frame")then detail.Visible=true;fillNestedIcons(detail,rK,def.Icon)
				local dN=detail:FindFirstChild("NameLabel")if dN and dN:IsA("TextLabel")then dN.Text=def.Name end;local dD=detail:FindFirstChild("DescLabel")if dD and dD:IsA("TextLabel")then dD.Text=def.Description end
				local dR=detail:FindFirstChild("RarityLabel")if dR and dR:IsA("TextLabel")then if def.Type=="SuitPiece"and def.ArmorSlot then dR.Text=(def.Rarity or"Item").." "..def.ArmorSlot else dR.Text=(def.Rarity or"Item").." ".. (def.Type or"Item")end;dR.TextColor3=RarityCol[def.Rarity]or Color3.new(1,1,1)end
				if independentCountLabel then independentCountLabel.Text=(def.Stackable and qty>1)and("x"..qty)or""end
				if independentDetailTypeIcon then if def.Type=="SuitPiece"and def.ArmorSlot then independentDetailTypeIcon.Image=ArmorSlotIcons[def.ArmorSlot]or ArmorSlotIcons.Default else independentDetailTypeIcon.Image=TypeIcons[def.Type]or TypeIcons.Other end end
				updateEquipButtonDisplayState()end end)else warn("ItemCardTemplate missing 'ClickDetector'.")end;c.Parent=grid
end

equipButton.MouseButton1Click:Connect(function()
	if not equipButton.Visible or not currentlySelectedItemInfo or not currentlySelectedItemInfo.def then return end
	local selectedItemId = currentlySelectedItemInfo.id
	local selectedItemDef = currentlySelectedItemInfo.def

	if selectedItemDef.Type == "Pickaxe" then
		if selectedItemId == currentlyEquippedPickaxeId then
			currentlyEquippedPickaxeId = nil -- Client-side prediction for responsiveness
			UnequipPickaxeGearEvent:FireServer(selectedItemId)
		else
			currentlyEquippedPickaxeId = selectedItemId -- Client-side prediction
			EquipPickaxeGearEvent:FireServer(selectedItemId)
		end
	elseif selectedItemDef.Type == "SuitPiece" and selectedItemDef.ArmorSlot then
		local slot = selectedItemDef.ArmorSlot
		if equippedArmorSlots[slot] and equippedArmorSlots[slot] == selectedItemId then
			UnequipArmorEventRemote:FireServer(slot) 
		else
			EquipArmorEventRemote:FireServer(selectedItemId)
		end
	else
		return 
	end
	updateEquipButtonDisplayState() 
end)

Remote.OnClientEvent:Connect(function(list)
	if typeof(list)=="table"then table.sort(list,function(a,b)local dA=ItemDefs[a.id]or{N="",R="Default",T="Default",AS="Default"};local dB=ItemDefs[b.id]or{N="",R="Default",T="Default",AS="Default"};local rA=RARITY_SORT_ORDER[dA.Rarity]or 0;local rB=RARITY_SORT_ORDER[dB.Rarity]or 0;if rA~=rB then return rA>rB end;local tA=TYPE_SORT_ORDER[dA.Type]or 0;local tB=TYPE_SORT_ORDER[dB.Type]or 0;if tA~=tB then return tA>tB end;if dA.Type=="SuitPiece"and dB.Type=="SuitPiece"then local asA=ARMOR_SLOT_SORT_ORDER[dA.ArmorSlot]or 0;local asB=ARMOR_SLOT_SORT_ORDER[dB.ArmorSlot]or 0;if asA~=asB then return asA>asB end end;return string.lower(dA.Name or"")<string.lower(dB.Name or"")end)end
	clearGrid()if detail then detail.Visible=false end;currentlySelectedCard=nil;equipButton.Visible=false;currentlySelectedItemInfo=nil
	if typeof(list)=="table"then for i,e in ipairs(list)do makeCard(e,i)end else warn("InvR: Non-table list from InvSync:",list)end
end)

ArmorSyncEvent.OnClientEvent:Connect(function(newEquippedArmor)
	if typeof(newEquippedArmor)=="table"then equippedArmorSlots=newEquippedArmor;updateDummyAvatarArmor()if detail.Visible and currentlySelectedItemInfo and currentlySelectedItemInfo.def then updateEquipButtonDisplayState()end
	else warn("InvR: Non-table data from ArmorSyncEvent:",newEquippedArmor)end
end)

local function handleDummyArmorHover(hitInstance)
	if currentHighlightClone then currentHighlightClone:Destroy();currentHighlightClone=nil end;currentlyHoveredAccessoryPart=nil
	if hitInstance and hitInstance:IsA("BasePart")and hitInstance:IsDescendantOf(dummyAvatarModel)and hitInstance:GetAttribute("IsDummyArmorVisual")then
		currentlyHoveredAccessoryPart=hitInstance;currentHighlightClone=hitInstance:Clone();currentHighlightClone.Name=hitInstance.Name.."_Highlight"
		if currentHighlightClone:IsA("MeshPart")or currentHighlightClone:IsA("Part")then currentHighlightClone.TextureID=""end;local exTex=currentHighlightClone:FindFirstChildOfClass("Texture")if exTex then exTex:Destroy()end;local exSA=currentHighlightClone:FindFirstChildOfClass("SurfaceAppearance")if exSA then exSA:Destroy()end
		currentHighlightClone.Material=Enum.Material.Neon;currentHighlightClone.Color=Color3.fromRGB(255,255,100);currentHighlightClone.Transparency=0.7;currentHighlightClone.Size=hitInstance.Size*1.08
		currentHighlightClone.Anchored=false;currentHighlightClone.CanCollide=false;currentHighlightClone.CanTouch=false;currentHighlightClone.CanQuery=false;currentHighlightClone.Parent=dummyAvatarModel
		currentHighlightClone.Massless = true 
		local w=Instance.new("WeldConstraint");w.Part0=hitInstance;w.Part1=currentHighlightClone;w.Parent=currentHighlightClone
	end
end
avatarDisplay.MouseEnter:Connect(function()isMouseOverViewport=true end)
avatarDisplay.MouseLeave:Connect(function()isMouseOverViewport=false;handleDummyArmorHover(nil)end)

RunService.RenderStepped:Connect(function()
	if not isMouseOverViewport or not viewportCamera or UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1)then if currentlyHoveredAccessoryPart and not isMouseOverViewport then handleDummyArmorHover(nil)end;return end
	highlightRaycastParams.FilterDescendantsInstances={dummyAvatarModel} 
	local mL=UserInputService:GetMouseLocation();local vpAP=avatarDisplay.AbsolutePosition;local vpAS=avatarDisplay.AbsoluteSize
	if not(mL.X>=vpAP.X and mL.X<=vpAP.X+vpAS.X and mL.Y>=vpAP.Y and mL.Y<=vpAP.Y+vpAS.Y)then if currentlyHoveredAccessoryPart then handleDummyArmorHover(nil)end;isMouseOverViewport=false;return end
	local rMP=mL-vpAP; local uR = nil
	if viewportCamera then uR=viewportCamera:ViewportPointToRay(rMP.X,rMP.Y) else return end 
	local rR=avatarWorld:Raycast(uR.Origin,uR.Direction*500,highlightRaycastParams) 
	local hP=nil;if rR and rR.Instance then hP=rR.Instance end
	if hP~=currentlyHoveredAccessoryPart then handleDummyArmorHover(hP)end
end)

if detail then local function sDPV()local dIV=detail.Visible;if independentCountLabel then independentCountLabel.Visible=dIV;if not dIV then independentCountLabel.Text=""end end;if independentDetailTypeIcon then independentDetailTypeIcon.Visible=dIV;if not dIV then independentDetailTypeIcon.Image=""end end;if not dIV then equipButton.Visible=false;equipButton.Text="Equip";equipButton.BackgroundColor3=EQUIP_BUTTON_DEFAULT_BG_COLOR;equipButton.BorderColor3=EQUIP_BUTTON_DEFAULT_BORDER_COLOR else if currentlySelectedItemInfo then updateEquipButtonDisplayState()else equipButton.Visible=false;equipButton.Text="Equip";equipButton.BackgroundColor3=EQUIP_BUTTON_DEFAULT_BG_COLOR;equipButton.BorderColor3=EQUIP_BUTTON_DEFAULT_BORDER_COLOR end end end;sDPV();detail:GetPropertyChangedSignal("Visible"):Connect(sDPV)end

local function syncEquippedStateFromServer()
	local p=Players.LocalPlayer;if not p then return end
	local ps,pR=pcall(function()return GetEquippedPickaxeState:InvokeServer()end)
	if ps then currentlyEquippedPickaxeId=pR or nil else warn("InvR: Pickaxe sync error:",pR);currentlyEquippedPickaxeId=nil end
	if GetEquippedArmorStateRemote then local as,aR=pcall(function()return GetEquippedArmorStateRemote:InvokeServer()end)
		if as then equippedArmorSlots=aR or{};updateDummyAvatarArmor()else warn("InvR: Armor sync error:",aR);equippedArmorSlots={};updateDummyAvatarArmor()end
	else warn("InvR: GetEquippedArmorStateRemote N/A")end
	if detail.Visible and currentlySelectedItemInfo and currentlySelectedItemInfo.def then updateEquipButtonDisplayState()end
end

local function initializeAndSync()
	equipButton.Visible=false;equipButton.Text="Equip";equipButton.BackgroundColor3=EQUIP_BUTTON_DEFAULT_BG_COLOR;equipButton.BorderColor3=EQUIP_BUTTON_DEFAULT_BORDER_COLOR;if equipButton.BorderSizePixel==0 then equipButton.BorderSizePixel=1 end

	print("InvRenderer: Initializing Camera. AvatarDisplay:", avatarDisplay and avatarDisplay:GetFullName() or "nil")

	local camChild = avatarDisplay:FindFirstChild("ViewportCam")
	if not camChild or not camChild:IsA("Camera") then
		print("InvRenderer: ViewportCam not found or not a Camera under AvatarDisplay. Creating new one.")
		camChild = Instance.new("Camera")
		camChild.Name = "ViewportCam"
		-- User's preferred CFrame and FieldOfView:
		camChild.CFrame = CFrame.new(0, 0, 8) * CFrame.Angles(0, math.rad(0), 0) 
		camChild.FieldOfView = 70
		camChild.Parent = avatarDisplay 
		print("InvRenderer: Created and parented new ViewportCam:", camChild:GetFullName())
	end

	viewportCamera = camChild 

	if avatarDisplay.CurrentCamera ~= viewportCamera then
		print("InvRenderer: Assigning ViewportFrame.CurrentCamera to ViewportCam instance.")
		avatarDisplay.CurrentCamera = viewportCamera
	elseif not avatarDisplay.CurrentCamera then 
		print("InvRenderer: ViewportFrame.CurrentCamera was nil. Assigning it to ViewportCam instance.")
		avatarDisplay.CurrentCamera = viewportCamera
	else
		print("InvRenderer: ViewportFrame.CurrentCamera was already set correctly.")
	end

	if not viewportCamera then
		warn("InvRenderer: CRITICAL - viewportCamera is still nil after creation/assignment attempt.")
	elseif not avatarDisplay.CurrentCamera then
		warn("InvRenderer: CRITICAL - viewportCamera is set, but AvatarDisplay.CurrentCamera is still nil.")
	elseif avatarDisplay.CurrentCamera ~= viewportCamera then
		warn("InvRenderer: CRITICAL - viewportCamera is set, but AvatarDisplay.CurrentCamera is different.")
	else
		print("InvRenderer: Camera setup successful. CurrentCamera is:", viewportCamera:GetFullName())
	end

	-- Anchor DummyAvatar parts and set massless (Belt-and-braces fix)
	if dummyAvatarModel then
		print("InvRenderer: Anchoring DummyAvatar parts and setting them to massless.")
		for _, partDescendant in ipairs(dummyAvatarModel:GetDescendants()) do
			if partDescendant:IsA("BasePart") then
				partDescendant.Anchored = true
				partDescendant.Massless = true 
			end
		end
	end

	highlightRaycastParams.FilterDescendantsInstances = {dummyAvatarModel}
	syncEquippedStateFromServer()
end

initializeAndSync()
