-- S2R Egg Finder (violet / black UI)
-- Based on public commit 7fd7826415b94846abc924aa0ce9308b541c0653.
-- Public host/config; broadcast contract preserved from public v0.4.3.
-- NYX Spawn Panel: current-server field eggs, read-only display.
-- Schema reference: monthonsova/Steal-An-Egg, EggESP/esp/EggData.lua.
-- Reports egg sightings and server IDs to the shared Finder host.
-- V4: field snapshot.
-- Records are never filtered by distance or by model availability.
-- Auto-execute after a server hop reloads the script from this URL (where this S2R file is hosted).
local S2R_RELOAD_URL='https://raw.githubusercontent.com/preexmon-collab/RDP/refs/heads/main/S2R-Egg-Finder%20(1).lua'
local Players = game:GetService('Players')
local RS = game:GetService('ReplicatedStorage')
local player = Players.LocalPlayer
assert(player, 'Join the game first')
local parent = player:WaitForChild('PlayerGui', 15)
assert(parent, 'PlayerGui unavailable')
local old = parent:FindFirstChild('TENSHI_FINDER_TOP4_PREVIEW')
if old then old:Destroy() end
local gui = Instance.new('ScreenGui')
gui.Name = 'TENSHI_FINDER_TOP4_PREVIEW'
gui:SetAttribute('S2RUIBuild','PUBLIC-CONTABO')
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
pcall(function() gui.ScreenInsets = Enum.ScreenInsets.None end)
pcall(function() gui.ClipToDeviceSafeArea = false end)
gui.DisplayOrder = 1200
gui.Parent = parent
local alive = true
local highlight
gui.Destroying:Connect(function() alive = false; if highlight then highlight:Destroy() end end)
local function make(class, props, holder)
    local obj = Instance.new(class)
    for key, value in pairs(props) do obj[key] = value end
    obj.Parent = holder
    return obj
end
local function label(holder, text, pos, size, color, fontSize)
    return make('TextLabel', {Text=text,Position=pos,Size=size,BackgroundTransparency=1,TextColor3=color or Color3.new(1,1,1),Font=Enum.Font.GothamBold,TextSize=fontSize or 13,TextXAlignment=Enum.TextXAlignment.Left,TextTruncate=Enum.TextTruncate.AtEnd},holder)
end
local function module(path)
    local obj = RS
    for part in path:gmatch('[^.]+') do
        obj = obj:FindFirstChild(part)
        assert(obj, 'Missing game module: '..path)
    end
    return require(obj)
end
local function numberField(record, keys)
    for _, key in ipairs(keys) do
        local value = record and record[key]
        if type(value)=='number' and value==value and math.abs(value)<math.huge then return value end
    end
end
local function modelFor(uid)
    if type(uid)~='string' then return end
    local folder = workspace:FindFirstChild('AreaEggSlotsClient')
    local obj = (folder and folder:FindFirstChild(uid)) or workspace:FindFirstChild(uid)
    if obj and obj:IsA('Model') then return obj end
end
local function displayedRate(model)
    if not model then return end
    for _,obj in ipairs(model:GetDescendants()) do
        if obj:IsA('TextLabel') or obj:IsA('TextButton') then
            local text=obj.Text:gsub('<[^>]+>',''):gsub(',','')
            local amount,suffix=text:match('%$?%s*(%d+%.?%d*)%s*(%a*)%s*/[sS]')
            local powers={['']=1,k=1e3,m=1e6,b=1e9,t=1e12,qa=1e15,q=1e15,qi=1e18}
            local factor=suffix and powers[suffix:lower()]
            if amount and factor then return tonumber(amount)*factor end
        end
    end
end
local function money(value)
    if not value then return 'Income unavailable' end
    for _,entry in ipairs({{1e18,'Qi'},{1e15,'Qa'},{1e12,'T'},{1e9,'B'},{1e6,'M'},{1e3,'K'}}) do
        if value>=entry[1] then return string.format('$%.2f%s/s',value/entry[1],entry[2]) end
    end
    return string.format('$%.2f/s',value)
end
local MIN_BROADCAST_RATE = 60000000
local function valid(value)
    return type(value)=='number' and value==value and value>=0 and value<math.huge
end
local function computedRate(base, scale, muts, mutationModule)
    if not valid(base) or not valid(scale) or scale==0 then return nil end
    local multi=1
    if type(muts)~='table' then return nil end
    if next(muts) then
        local fn=mutationModule and mutationModule.EarningsFor
        if type(fn)~='function' then return nil end
        local ok,result=pcall(fn,muts)
        if not ok or not valid(result) then return nil end
        multi=result
    end
    -- Observed public implementation; displayed model income takes precedence.
    local factor=scale>5 and (scale/5)^1.2*19.637875755794113 or scale^1.85
    local result=base*factor*multi
    return valid(result) and result or nil
end
local function compare(a,b,sortMode)
    -- Unknown event species are visibly pinned for inspection, not called Divine.
    local av,bv
    if sortMode==1 then av,bv=a.rate,b.rate
    elseif sortMode==2 then av,bv=a.scale,b.scale
    else av,bv=a.tier,b.tier end
    -- Unavailable values are never replaced with invented zeroes.
    if av==nil and bv~=nil then return false end
    if bv==nil and av~=nil then return true end
    if av~=bv then return av>bv end
    if sortMode~=1 and a.rate~=b.rate then return (a.rate or -1)>(b.rate or -1) end
    if a.tier~=b.tier then return a.tier>b.tier end
    return tostring(a.key)<tostring(b.key)
end
local function readTraitNames(record)
    local names,seen={},{}
    local known=record.Mutations~=nil or record.BaseMutation~=nil
    local function add(value)
        if type(value)=='string' and value~='' and value~='None' and value~='Normal' and not seen[value] then seen[value]=true;names[#names+1]=value end
    end
    if type(record.Mutations)=='table' then
        for key,value in pairs(record.Mutations) do
            if value==true and type(key)=='string' then add(key)
            elseif type(value)=='string' then add(value)
            elseif type(value)=='table' then local id=value.Id or value._id or value.Name; if type(id)=='string' then add(id) else known=false end end
        end
    elseif type(record.Mutations)=='string' then
        for value in record.Mutations:gmatch('[^,;|]+') do add(value:match('^%s*(.-)%s*$')) end
    end
    add(record.BaseMutation);table.sort(names)
    return names,known
end
local allowedRarities={cosmic=7,secret=8,eternal=9,ethernal=9,divine=10}
local excludedEggs={triceratops=true,bronto=true,whaleshark=true,belugawhale=true,lavaccasaturnosaturnita=true}
local function excludedFinderEgg(name) return excludedEggs[tostring(name):lower():gsub('[^%a%d]','')]==true end
local function finderRarityRank(rarity) return allowedRarities[tostring(rarity):lower()] end
local function createFinder(D)
    local cycleModule
    pcall(function() cycleModule=module('Shared.Util.AreaEggCycle') end)
    local function cycleInfo()
        if not cycleModule then return nil end
        local ok,info=pcall(function()
            local now=workspace:GetServerTimeNow()
            local running=cycleModule.IsRunning()
            local remaining=cycleModule.SecondsUntilReset(now)
            local respawnAt
            if type(cycleModule.PeriodStartTime)=='function' and type(cycleModule.PeriodIndexAt)=='function' then
                local known,value=pcall(function() return cycleModule.PeriodStartTime(cycleModule.PeriodIndexAt(now))*1000 end)
                if known and type(value)=='number' then respawnAt=value end
            end
            return {resetAt=cycleModule.NextResetTime(now)*1000,respawnAt=respawnAt,remaining=remaining,running=running}
        end)
        return ok and info or nil
    end
    D.publicEntryAllowed=function(entry,now)
        return type(entry)=='table' and (not entry.takenConfirmed or entry.publicTopTaken==true) and finderRarityRank(entry.rarity)~=nil and not excludedFinderEgg(entry.name) and not excludedFinderEgg(entry.category) and entry.source~='event' and type(entry.expiresAt)=='number' and entry.expiresAt>now
    end

    local PREMIUM_EDITION=false
    local AUTO_KEY=''
    local originalMake,originalLabel=D.make,D.label
    D.make=function(class,props,parent)
        if class=='TextButton' or class=='TextBox' then props.Font=Enum.Font.GothamBold;props.TextSize=math.max(props.TextSize or 15,15) end
        if class=='TextBox' then props.TextColor3=Color3.fromRGB(25,25,30) end
        local obj=originalMake(class,props,parent)
        if class=='TextButton' or class=='TextBox' then originalMake('UICorner',{CornerRadius=UDim.new(0,8)},obj) end
        return obj
    end
    D.label=function(parent,text,pos,size,color,fontSize)
        local obj=originalLabel(parent,text,pos,size,color or Color3.fromRGB(240,242,255),math.max(fontSize or 15,14))
        obj.Font=Enum.Font.GothamBold;obj.TextStrokeColor3=Color3.new(0,0,0);obj.TextStrokeTransparency=0.45;return obj
    end
    local DISCORD='' -- S2R: put your own invite here if you want a Discord link
    local Http=game:GetService('HttpService')
    local Teleports=game:GetService('TeleportService')
    local requestFn=request or http_request or (syn and syn.request) or (http and http.request)
    local active,othersOnly=true,false
    local reporterId=Http:GenerateGUID(false)
    D.reporterStartedAt=DateTime.now().UnixTimestampMillis
    local config,configAt=nil,-math.huge
    local feed,feedAt={},0
    local clockOffset=0
    local networkBusy=false
    local networkTicket=0
    local reportStatus='Connecting'
    local queryStatus=''
    local minRate,minRank=0,6
    local joining=false
    local localHighlight
    local viewerCode=PREMIUM_EDITION and AUTO_KEY or ''
    local pageOffset,nextOffset=0,nil
    local queryEpoch=0
    local settingsPath=PREMIUM_EDITION and 's2r_beta_premium_ui.json' or 'top4_preview_s2r_beta_ui.json'
    local settings={}
    if type(readfile)=='function' then pcall(function() local data=Http:JSONDecode(readfile(settingsPath));if type(data)=='table' then settings=data end end) end
    if type(settings.myServer)=='boolean' then othersOnly=settings.myServer end
    if type(settings.minRank)=='number' then
        local saved=math.floor(settings.minRank)
        if saved>=6 and saved<=10 then minRank=saved
        elseif saved==0 and settings.rarityMenu=='mythic-up-v1' then minRank=0 end
    end
    local menuHotkey=Enum.KeyCode.F
    if type(settings.menuHotkey)=='string' then
        pcall(function() local saved=Enum.KeyCode[settings.menuHotkey];if saved and saved~=Enum.KeyCode.Unknown and not (settings.menuHotkey=='RightShift' and settings.hotkeyDefaultVersion~=2) then menuHotkey=saved end end)
    end
    local themeModal,loadUiAsset,syncCloseArt
    local sharingNotice=D.label(D.gui,'EGG FINDER ON • Sharing egg sightings & server ID',UDim2.new(0,12,1,-28),UDim2.new(1,-24,0,22),Color3.fromRGB(245,245,245),12)
    sharingNotice.Visible=false;sharingNotice.TextSize=12;sharingNotice.TextWrapped=true;sharingNotice.TextStrokeTransparency=0.15
    local panel=D.make('Frame',{AnchorPoint=Vector2.new(1,0.5),Position=UDim2.new(1,-18,0.5,0),Size=UDim2.new(0.94,0,0.86,0),BackgroundColor3=Color3.fromRGB(12,7,22),Visible=false},D.gui)
    local responsiveScale=D.make('UIScale',{Scale=0.8},panel)

    D.make('UICorner',{CornerRadius=UDim.new(0,10)},panel)
    D.make('UIStroke',{Color=Color3.fromRGB(139,92,246),Thickness=2},panel)
    local wallpaper=D.make('ImageLabel',{Name='S2RWallpaper',Size=UDim2.fromScale(1,1),BackgroundTransparency=1,ImageTransparency=0.22,Image='',ScaleType=Enum.ScaleType.Crop,Active=false,ZIndex=1},panel)
    D.make('UICorner',{CornerRadius=UDim.new(0,10)},wallpaper)
    local wallpaperShade=D.make('Frame',{Name='WallpaperShade',Size=UDim2.fromScale(1,1),BackgroundColor3=Color3.fromRGB(7,3,15),BackgroundTransparency=0.25,BorderSizePixel=0,Active=false,ZIndex=1},wallpaper)
    D.make('UICorner',{CornerRadius=UDim.new(0,10)},wallpaperShade)
    local function contentLayer(child)
        if child:IsA('GuiObject') and child~=wallpaper and not child:IsDescendantOf(wallpaper) and child.ZIndex<2 then child.ZIndex=2 end
    end
    for _,child in ipairs(panel:GetDescendants()) do contentLayer(child) end
    panel.DescendantAdded:Connect(contentLayer)
    do
        -- S2R: soft fade-in whenever the panel opens (non-interactive overlay)
        local veil=D.make('Frame',{Name='S2RFade',Size=UDim2.fromScale(1,1),BackgroundColor3=Color3.fromRGB(7,3,15),BackgroundTransparency=1,BorderSizePixel=0,Active=false,ZIndex=100},panel)
        D.make('UICorner',{CornerRadius=UDim.new(0,10)},veil)
        local fadeService=game:GetService('TweenService')
        panel:GetPropertyChangedSignal('Visible'):Connect(function()
            if not panel.Visible then return end
            veil.BackgroundTransparency=0.6
            fadeService:Create(veil,TweenInfo.new(0.3,Enum.EasingStyle.Quint,Enum.EasingDirection.Out),{BackgroundTransparency=1}):Play()
        end)
    end
    local bar=D.make('Frame',{Position=UDim2.fromOffset(1,1),Size=UDim2.new(1,-2,0,45),BackgroundColor3=Color3.fromRGB(32,16,62),BorderSizePixel=0},panel)
    D.make('UICorner',{CornerRadius=UDim.new(0,10)},bar)
    D.make('UICorner',{CornerRadius=UDim.new(0,10)},bar)
    D.make('UIGradient',{Color=ColorSequence.new(Color3.fromRGB(167,139,250),Color3.fromRGB(91,33,182)),Rotation=0},bar)
    local heading=D.label(panel,PREMIUM_EDITION and 'S2R Egg Finder / PREMIUM' or 'S2R Egg Finder',UDim2.fromOffset(14,8),UDim2.new(1,-55,0,32),nil,22)
    local open=D.make('ImageButton',{Image='',Position=UDim2.fromOffset(18,80),Size=UDim2.fromOffset(82,82),BackgroundColor3=Color3.fromRGB(250,250,250),ScaleType=Enum.ScaleType.Fit,ClipsDescendants=true},D.gui)
    D.make('UICorner',{CornerRadius=UDim.new(1,0)},open)
    D.make('UIStroke',{Color=Color3.fromRGB(139,92,246),Thickness=3},open)
    local iconCaption=D.label(open,'FINDER',UDim2.new(0.5,-44,1,5),UDim2.fromOffset(88,27),Color3.new(1,1,1),18)
    open.ClipsDescendants=false
    iconCaption.TextStrokeTransparency=0.15;iconCaption.TextXAlignment=Enum.TextXAlignment.Center
    local function restorePosition(target,value)
        if type(value)~='table' then return end
        for i=1,4 do if type(value[i])~='number' or value[i]~=value[i] or math.abs(value[i])>5000 then return end end
        target.Position=UDim2.new(value[1],value[2],value[3],value[4])
    end
    restorePosition(panel,settings.panel);restorePosition(open,settings.icon)
    D.publicGuiPercent=function(value,factor)
        local n=tonumber(value) or (tonumber(factor) or 1)*100
        if n~=n or math.abs(n)==math.huge then n=100 end
        return math.clamp(math.floor(n/10+0.5)*10,70,150)
    end
    do
        local latest
        local function consider(value)
            if type(value)=='table' and type(value.percent)=='number' and value.percent>=70 and value.percent<=150 and type(value.at)=='number' and (not latest or value.at>latest.at) then latest=value end
        end
        if type(readfile)=='function' then pcall(function() consider(Http:JSONDecode(readfile('top4_preview_s2r_public_gui_size_v2.json'))) end) end
        pcall(function() local data=Teleports:GetTeleportSetting('S2RPublicGuiSizeV2');if type(data)=='string' then consider(Http:JSONDecode(data)) end end)
        if latest then settings.sizePercent=latest.percent end
    end
    D.savePublicGuiSize=function(percent)
        local data=Http:JSONEncode({percent=percent,at=workspace:GetServerTimeNow()*1000})
        if type(writefile)=='function' then pcall(writefile,'top4_preview_s2r_public_gui_size_v2.json',data) end
        pcall(function() Teleports:SetTeleportSetting('S2RPublicGuiSizeV2',data) end)
    end
    D.baseEggVisuals={enabled=false,hideMine=false,saved={},prompts={},renderer=nil,hidden=0,candidates={},tracking=false}
    do
        pcall(function() if type(readfile)=='function' then D.baseEggVisuals.enabled=game:GetService('HttpService'):JSONDecode(readfile('s2r_do_test_hide_base_eggs_v1.json'))==true end end)
        pcall(function() local value=game:GetService('TeleportService'):GetTeleportSetting('S2RDoTestHideBaseEggs');if type(value)=='boolean' then D.baseEggVisuals.enabled=value end end)
        pcall(function() if type(readfile)=='function' then D.baseEggVisuals.hideMine=game:GetService('HttpService'):JSONDecode(readfile('s2r_do_test_hide_my_eggs_'..tostring(D.player.UserId)..'.json'))==true end end)
        pcall(function() local value=game:GetService('TeleportService'):GetTeleportSetting('S2RDoTestHideMyEggs_'..tostring(D.player.UserId));if type(value)=='boolean' then D.baseEggVisuals.hideMine=value end end)
    end
    D.trackEggAdornments=function()
        local state=D.baseEggVisuals
        if state.tracking then return end
        state.tracking=true;state.connections={}
        local function track(obj)
            if obj:IsA('BillboardGui') or obj:IsA('SurfaceGui') then state.candidates[obj]=true end
            if obj:IsA('TextLabel') and not obj:IsDescendantOf(D.gui) and state.hideMine then
                task.defer(function()
                    if active and obj.Parent and D.isOwnIncomePopup and D.isOwnIncomePopup(obj) then
                        state.candidates[obj]=true
                        if not state.saved[obj] then state.saved[obj]={Visible=obj.Visible} end
                        obj.Visible=false
                    end
                end)
            end
        end
        for _,root in pairs({workspace,D.player:FindFirstChildOfClass('PlayerGui')}) do
            pcall(function()
                state.connections[#state.connections+1]=root.DescendantAdded:Connect(track)
                task.spawn(function()
                    for i,obj in ipairs(root:GetDescendants()) do
                        if not active or not state.tracking then return end
                        track(obj);if i%256==0 then task.wait() end
                    end
                end)
            end)
        end
    end
    D.restoreBaseEggVisual=function(obj)
        local saved=D.baseEggVisuals.saved[obj]
        if saved then
            for property,value in pairs(saved) do pcall(function()
                obj[property]=value
                pcall(function() obj:SetAttribute('S2RDoTestOriginal_'..property,nil) end)
            end) end
            D.baseEggVisuals.prompts[obj]=nil
            D.baseEggVisuals.saved[obj]=nil
        end
    end
    D.isOwnIncomePopup=function(obj)
        if not D.baseEggVisuals.hideMine or not obj:IsA('TextLabel') or obj:IsDescendantOf(D.gui) then return false end
        local text=obj.Text:gsub('<[^>]*>',''):gsub('%s','')
        local color=obj.TextColor3
        return text:match('^%+%$[%d%.,]+[%a]*$')~=nil and color.G>color.R and color.G>color.B
    end
    D.applyBaseEggVisibility=function()
        local state=D.baseEggVisuals
        local keep={}
        if (state.enabled or state.hideMine) and state.renderer then
            pcall(D.trackEggAdornments)
            local players=game:GetService('Players'):GetPlayers()
            local targets,owners={},{}
            for _,owner in ipairs(players) do
                if owner==D.player and state.hideMine or owner~=D.player and state.enabled then
                    local selected={};pcall(state.renderer.AppendRaycastTargets,selected,owner.UserId)
                    for _,obj in ipairs(selected) do targets[#targets+1]=obj;owners[obj]=owner.UserId end
                end
            end
            local field=workspace:FindFirstChild('AreaEggSlotsClient')
            local function protected(obj)
                if field and (obj==field or obj:IsDescendantOf(field)) then return true end
                for _,owner in ipairs(players) do if owner.Character and (obj==owner.Character or obj:IsDescendantOf(owner.Character)) then return true end end
                return false
            end
            local function ownerOf(obj)
                local at=obj
                while at do if owners[at] then return owners[at] end;at=at.Parent end
            end
            local function hide(obj,own)
                if protected(obj) then return end
                local property,value
                if obj:IsA('BasePart') then property='LocalTransparencyModifier';value=1
                elseif obj:IsA('Decal') or obj:IsA('Texture') then property='Transparency';value=1
                elseif obj:IsA('ParticleEmitter') or obj:IsA('Trail') or obj:IsA('Beam') or obj:IsA('BillboardGui') or obj:IsA('SurfaceGui') then property='Enabled';value=false
                end
                if D.isOwnIncomePopup(obj) then property='Visible';value=false end
                if not property then return end
                keep[obj]=true
                if not state.saved[obj] then
                    local original=obj[property]
                    pcall(function()
                        local stored=obj:GetAttribute('S2RDoTestOriginal_'..property)
                        if stored~=nil then original=stored
                        else
                            if property=='LocalTransparencyModifier' and original==1 then original=0 end
                            obj:SetAttribute('S2RDoTestOriginal_'..property,original)
                        end
                    end)
                    state.saved[obj]={[property]=original}
                end
                if obj[property]~=value then obj[property]=value end
            end
            for _,root in ipairs(targets) do
                if typeof(root)=='Instance' and root.Parent and not protected(root) then
                    local own=owners[root]==D.player.UserId
                    pcall(hide,root,own)
                    for _,obj in ipairs(root:GetDescendants()) do pcall(hide,obj,own) end
                end
            end
            for obj in pairs(state.candidates) do
                if not obj.Parent then state.candidates[obj]=nil
                elseif obj:IsA('TextLabel') and not D.isOwnIncomePopup(obj) then state.candidates[obj]=nil
                elseif not protected(obj) then pcall(function()
                    if D.isOwnIncomePopup(obj) then hide(obj,true)
                    elseif obj:IsA('BillboardGui') or obj:IsA('SurfaceGui') then
                        local adornee=obj.Adornee or obj.Parent
                        local owner=ownerOf(adornee)
                        if owner and not protected(adornee) then hide(obj,owner==D.player.UserId) end
                    end
                end) end
            end
        end
        local count=0
        for obj in pairs(state.saved) do if not keep[obj] then D.restoreBaseEggVisual(obj) else count+=1 end end
        state.hidden=count
    end
    D.setHideBaseEggs=function(enabled)
        D.baseEggVisuals.enabled=enabled==true
        pcall(function() if type(writefile)=='function' then writefile('s2r_do_test_hide_base_eggs_v1.json',game:GetService('HttpService'):JSONEncode(D.baseEggVisuals.enabled)) end end)
        pcall(function() game:GetService('TeleportService'):SetTeleportSetting('S2RDoTestHideBaseEggs',D.baseEggVisuals.enabled) end)
        D.applyBaseEggVisibility()
    end
    D.setHideMyEggs=function(enabled)
        D.baseEggVisuals.hideMine=enabled==true
        pcall(function() if type(writefile)=='function' then writefile('s2r_do_test_hide_my_eggs_'..tostring(D.player.UserId)..'.json',game:GetService('HttpService'):JSONEncode(D.baseEggVisuals.hideMine)) end end)
        pcall(function() game:GetService('TeleportService'):SetTeleportSetting('S2RDoTestHideMyEggs_'..tostring(D.player.UserId),D.baseEggVisuals.hideMine) end)
        D.applyBaseEggVisibility()
    end
    D.gui.Destroying:Connect(function()
        D.baseEggVisuals.enabled=false;D.baseEggVisuals.hideMine=false;D.baseEggVisuals.tracking=false
        for _,connection in ipairs(D.baseEggVisuals.connections or {}) do connection:Disconnect() end
        D.applyBaseEggVisibility()
    end)
    task.spawn(function()
        while active do
            if (D.baseEggVisuals.enabled or D.baseEggVisuals.hideMine) and not D.baseEggVisuals.renderer then
                pcall(function()
                    local obj=game:GetService('ReplicatedStorage'):FindFirstChild('Shared')
                    obj=obj and obj:FindFirstChild('Eggs');obj=obj and obj:FindFirstChild('PlacedEggRenderer')
                    if obj then local renderer=require(obj);if type(renderer.AppendRaycastTargets)=='function' then D.baseEggVisuals.renderer=renderer end end
                end)
            end
            if D.baseEggVisuals.enabled or D.baseEggVisuals.hideMine then D.applyBaseEggVisibility() end
            if D.paintBaseEggOption then D.paintBaseEggOption() end
            if D.paintMyEggOption then D.paintMyEggOption() end
            task.wait(1)
        end
    end)
    D.nightSky={enabled=false,writing=false,skies={},clock=nil,created=nil}
    D.applyNightSky=function()
        local state=D.nightSky
        if not state.enabled or state.writing then return end
        local lighting=game:GetService('Lighting')
        state.writing=true
        if lighting.ClockTime~=22 then lighting.ClockTime=22 end
        for _,sky in ipairs(lighting:GetChildren()) do
            if sky:IsA('Sky') then
                if not state.skies[sky] then state.skies[sky]={stars=sky.StarCount,bodies=sky.CelestialBodiesShown} end
                sky.StarCount=3000;sky.CelestialBodiesShown=true
            end
        end
        state.writing=false
    end
    D.setNightSky=function(enabled,persist)
        local state=D.nightSky;local lighting=game:GetService('Lighting')
        enabled=enabled==true
        if enabled and not state.enabled then
            state.clock=lighting.ClockTime;state.enabled=true
            if not lighting:FindFirstChildOfClass('Sky') then state.created=Instance.new('Sky');state.created.Name='S2RDoTestNightSky';state.created.Parent=lighting end
            D.applyNightSky()
        elseif not enabled and state.enabled then
            state.enabled=false;state.writing=true
            -- A reload can observe our forced 22:00 as its initial clock.
            -- OFF must return to daylight rather than restoring that night.
            local restore=tonumber(state.clock)
            if not restore then restore=14 end
            lighting.ClockTime=restore
            for sky,saved in pairs(state.skies) do pcall(function() sky.StarCount=saved.stars;sky.CelestialBodiesShown=saved.bodies end) end
            state.skies={}
            if state.created then state.created:Destroy();state.created=nil end
            state.writing=false
        end
        if persist~=false then
            if type(writefile)=='function' then pcall(function() writefile('s2r_do_test_night_sky_'..tostring(D.player.UserId)..'.json',Http:JSONEncode(enabled)) end) end
            pcall(function() Teleports:SetTeleportSetting('S2RDoTestNightSky_'..tostring(D.player.UserId),enabled) end)
        end
        if D.paintNightSkyOption then D.paintNightSkyOption() end
    end
    D.installNightSky=function()
        local lighting=game:GetService('Lighting')
        local changed=lighting:GetPropertyChangedSignal('ClockTime'):Connect(function()
            local state=D.nightSky
            if state.enabled and not state.writing and lighting.ClockTime~=22 then state.clock=lighting.ClockTime;D.applyNightSky() end
        end)
        local added=lighting.ChildAdded:Connect(function(child) if child:IsA('Sky') and D.nightSky.enabled then D.applyNightSky() end end)
        D.gui.Destroying:Connect(function() changed:Disconnect();added:Disconnect();D.setNightSky(false,false) end)
        local enabled=false
        pcall(function() if type(readfile)=='function' then enabled=Http:JSONDecode(readfile('s2r_do_test_night_sky_'..tostring(D.player.UserId)..'.json'))==true end end)
        pcall(function() local value=Teleports:GetTeleportSetting('S2RDoTestNightSky_'..tostring(D.player.UserId));if type(value)=='boolean' then enabled=value end end)
        D.setNightSky(enabled,false)
    end
    D.installNightSky()

    local sizePercent=D.publicGuiPercent(settings.sizePercent,settings.sizeFactor)
    local sizeFactor=sizePercent/100
    local launcherScale=D.make('UIScale',{Scale=0.8},open)
    local function fitFinder()
        local view=D.gui.AbsoluteSize
        if view.X<=0 or view.Y<=0 then return end
        local landscape=view.X>view.Y
        local width=math.min(321.6*sizeFactor,view.X*(landscape and 0.40 or 0.92),view.X-16)
        local height=math.min(592*sizeFactor,view.Y*0.90)
        local scale=math.min(0.8*sizeFactor,width/402,height/680)
        responsiveScale.Scale=scale
        panel.Size=UDim2.fromOffset(402,height/scale)
        launcherScale.Scale=math.min(0.8,math.max(0.5,math.min(view.X,view.Y)/650))
        local function keepVisible(target,caption)
            local size=target.AbsoluteSize
            local p=target.Position
            local anchor=target.AnchorPoint
            local x=p.X.Scale*view.X+p.X.Offset
            local y=p.Y.Scale*view.Y+p.Y.Offset
            x=math.clamp(x,8+size.X*anchor.X,math.max(8+size.X*anchor.X,view.X-8-size.X*(1-anchor.X)))
            y=math.clamp(y,8+size.Y*anchor.Y,math.max(8+size.Y*anchor.Y,view.Y-8-caption-size.Y*(1-anchor.Y)))
            target.Position=UDim2.fromScale(x/view.X,y/view.Y)
        end
        task.defer(function()
            if panel.Parent then keepVisible(panel,0);keepVisible(open,28*launcherScale.Scale) end
        end)
    end
    local resizeConnection=D.gui:GetPropertyChangedSignal('AbsoluteSize'):Connect(fitFinder)
    D.gui.Destroying:Connect(function() resizeConnection:Disconnect() end)
    task.defer(fitFinder)

    local function saveSettings()
        pcall(D.savePublicGuiSize,sizePercent)
        if type(writefile)~='function' then return end
        pcall(function()
            local function coords(p) return {p.X.Scale,p.X.Offset,p.Y.Scale,p.Y.Offset} end
            writefile(settingsPath,Http:JSONEncode({myServer=othersOnly,minRank=minRank,rarityMenu='mythic-up-v1',menuHotkey=menuHotkey.Name,hotkeyDefaultVersion=2,sizeFactor=sizeFactor,sizePercent=sizePercent,panel=coords(panel.Position),icon=coords(open.Position)}))
        end)
    end
    D.saveGuiBeforeTeleport=saveSettings
    heading.Size=UDim2.fromOffset(185,32)
    heading.TextSize=19
    local brandLogo=D.make('ImageLabel',{Name='S2RBrandLogo',Position=UDim2.fromOffset(10,2),Size=UDim2.fromOffset(180,42),BackgroundTransparency=1,Image='',ScaleType=Enum.ScaleType.Fit,Active=true},panel)
    brandLogo.Visible=false
    heading.Text='S2R EGG FINDER'
    heading.TextSize=18
    heading.Font=Enum.Font.Arcade
    heading.TextScaled=true
    heading.TextWrapped=false
    heading.TextTruncate=Enum.TextTruncate.None
    D.make('UITextSizeConstraint',{MinTextSize=1,MaxTextSize=20},heading)
    heading.Size=UDim2.fromOffset(205,25)
    heading.Position=UDim2.fromOffset(10,2)
    heading.TextStrokeTransparency=0.65
    -- S2R launcher: native violet/black badge (no downloaded brand art)
    open.BackgroundTransparency=0
    open.BackgroundColor3=Color3.fromRGB(14,8,26)
    iconCaption.Text='S2R'
    iconCaption.Font=Enum.Font.Arcade
    iconCaption.TextSize=24
    iconCaption.Position=UDim2.new(0.5,-44,0.5,-13)
    iconCaption.Visible=true
    for _,decoration in ipairs(open:GetChildren()) do
        if decoration:IsA('UIStroke') then decoration.Color=Color3.fromRGB(139,92,246);decoration.Thickness=3 end
    end

    local sizeMinus=D.make('TextButton',{Name='SizeMinus',Text='',Position=UDim2.new(1,-182,0,3),Size=UDim2.fromOffset(40,40),BackgroundColor3=Color3.fromRGB(190,45,55),TextColor3=Color3.new(1,1,1)},panel)
    local sizePlus=D.make('TextButton',{Name='SizePlus',Text='',Position=UDim2.new(1,-94,0,3),Size=UDim2.fromOffset(40,40),BackgroundColor3=Color3.fromRGB(45,150,80),TextColor3=Color3.new(1,1,1)},panel)
    local sizeLabel=D.label(panel,'100%',UDim2.new(1,-138,0,13),UDim2.fromOffset(40,20),Color3.new(1,1,1),14)
    sizeLabel.TextXAlignment=Enum.TextXAlignment.Center
    sizeLabel.TextScaled=true;sizeLabel.TextWrapped=false
    D.make('UITextSizeConstraint',{MinTextSize=1,MaxTextSize=14},sizeLabel)
    for _,button in ipairs({sizeMinus,sizePlus}) do
        local corner=button:FindFirstChildOfClass('UICorner')
        if corner then corner.CornerRadius=UDim.new(0,6) end
        local line=D.make('Frame',{AnchorPoint=Vector2.new(0.5,0.5),Position=UDim2.fromScale(0.5,0.5),Size=UDim2.fromOffset(16,4),BackgroundColor3=Color3.new(1,1,1),BorderSizePixel=0},button)
        D.make('UICorner',{CornerRadius=UDim.new(1,0)},line)
    end
    local upright=D.make('Frame',{AnchorPoint=Vector2.new(0.5,0.5),Position=UDim2.fromScale(0.5,0.5),Size=UDim2.fromOffset(4,16),BackgroundColor3=Color3.new(1,1,1),BorderSizePixel=0},sizePlus)
    D.make('UICorner',{CornerRadius=UDim.new(1,0)},upright)
    local function paintSize()
        sizeLabel.Text=tostring(sizePercent)..'%'
        sizeMinus.Active=sizePercent>70;sizeMinus.Selectable=sizePercent>70
        sizePlus.Active=sizePercent<150;sizePlus.Selectable=sizePercent<150
    end
    local function changeSizeBy(delta)
        local nextPercent=math.clamp(sizePercent+delta,70,150)
        if nextPercent==sizePercent then return end
        sizePercent=nextPercent;sizeFactor=sizePercent/100
        paintSize();fitFinder();saveSettings()
    end
    sizeMinus.Activated:Connect(function() changeSizeBy(-10) end)
    sizePlus.Activated:Connect(function() changeSizeBy(10) end)
    paintSize()
    local close=D.make('TextButton',{Text='×',Position=UDim2.new(1,-33,0,4),Size=UDim2.fromOffset(27,27),BackgroundColor3=Color3.fromRGB(160,35,50),TextColor3=Color3.new(1,1,1),TextSize=22},panel)
    local closeArt=D.make('ImageLabel',{Size=UDim2.fromScale(1,1),BackgroundTransparency=1,Image='',ScaleType=Enum.ScaleType.Fit,Active=false},close)
    -- S2R: native x close button (no downloaded art)
    local suppressOpenUntil=0
    open.Activated:Connect(function() if os.clock()<suppressOpenUntil then return end; panel.Visible=not panel.Visible; D.localPanel.Visible=not panel.Visible end)
    close.Activated:Connect(function() panel.Visible=false; D.localPanel.Visible=true end)
    local Input=game:GetService('UserInputService')
    local drag
    local function draggable(target,handle,isLauncher)
        handle.Active=true
        handle.InputBegan:Connect(function(input)
            if input.UserInputType~=Enum.UserInputType.MouseButton1 and input.UserInputType~=Enum.UserInputType.Touch then return end
            drag={target=target,input=input,start=input.Position,position=target.Position,absolute=target.AbsolutePosition,size=target.AbsoluteSize,launcher=isLauncher,moved=false}
        end)
    end
    draggable(panel,heading,false)
    draggable(panel,brandLogo,false)
    -- Window dragging is confined to its header; scrollbar has no drag overlay.
    draggable(panel,bar,false)

    draggable(open,open,true)
    local launcherHit=D.make('TextButton',{Name='LauncherHitArea',Text='',AutoButtonColor=false,BackgroundTransparency=1,Position=UDim2.fromOffset(-8,-8),Size=UDim2.new(1,16,1,16),ZIndex=5},open)
    draggable(open,launcherHit,true)
    launcherHit.Activated:Connect(function()
        if os.clock()<suppressOpenUntil then return end
        panel.Visible=not panel.Visible;D.localPanel.Visible=not panel.Visible
    end)
    local moveConnection=Input.InputChanged:Connect(function(input)
        if not drag then return end
        local mouse=drag.input.UserInputType==Enum.UserInputType.MouseButton1
        if (mouse and input.UserInputType~=Enum.UserInputType.MouseMovement) or (not mouse and input~=drag.input) then return end
        local dx,dy=input.Position.X-drag.start.X,input.Position.Y-drag.start.Y
        if dx*dx+dy*dy>25 then drag.moved=true end
        if not drag.moved then return end
        if drag.launcher then suppressOpenUntil=os.clock()+0.5 end
        local view=D.gui.AbsoluteSize
        local origin=D.gui.AbsolutePosition
        if view.X<=0 or view.Y<=0 then return end
        local left=drag.absolute.X-origin.X
        local top=drag.absolute.Y-origin.Y
        local x=math.clamp(left+dx,0,math.max(0,view.X-drag.size.X))
        local y=math.clamp(top+dy,0,math.max(0,view.Y-drag.size.Y-(drag.launcher and 28*launcherScale.Scale or 0)))
        local anchor=drag.target.AnchorPoint
        drag.target.Position=UDim2.fromScale((x+anchor.X*drag.size.X)/view.X,(y+anchor.Y*drag.size.Y)/view.Y)
    end)
    local endConnection=Input.InputEnded:Connect(function(input)
        if drag and (input==drag.input or input.UserInputType==Enum.UserInputType.MouseButton1) then
            if drag.moved and drag.launcher then suppressOpenUntil=os.clock()+0.3 end
            if drag.moved then saveSettings() end
            drag=nil
        end
    end)
    D.gui.Destroying:Connect(function() moveConnection:Disconnect();endConnection:Disconnect();drag=nil end)
    local status=D.label(panel,'Connecting…',UDim2.fromOffset(14,52),UDim2.new(1,-28,0,48),Color3.fromRGB(210,218,240),14)
    status.Visible=false
    status.TextWrapped=true
    if not PREMIUM_EDITION then status.Size=UDim2.new(1,-28,0,24) end
    local discordSubtitle=D.label(panel,DISCORD,UDim2.fromOffset(10,27),UDim2.fromOffset(205,14),Color3.new(1,1,1),11)
    discordSubtitle.TextSize=11
    discordSubtitle.TextScaled=true;discordSubtitle.TextWrapped=false;discordSubtitle.Visible=true
    D.make('UITextSizeConstraint',{MinTextSize=1,MaxTextSize=11},discordSubtitle)
    discordSubtitle.Text='EGG & SERVER FINDER'
    local page={Text=''}
    local scope=D.make('TextButton',{Name='AllServers',Text='ALL SERVERS',Position=UDim2.new(0,10,1,-136),Size=UDim2.new(0.5,-15,0,34),BackgroundColor3=Color3.fromRGB(58,36,98),TextColor3=Color3.new(1,1,1),TextSize=14},panel)
    local myScope=D.make('TextButton',{Name='MyServer',Text='MY SERVER',Position=UDim2.new(0.5,5,1,-136),Size=UDim2.new(0.5,-15,0,34),BackgroundColor3=Color3.fromRGB(58,36,98),TextColor3=Color3.new(1,1,1),TextSize=14},panel)
    for _,button in ipairs({scope,myScope}) do
        button.TextScaled=true;button.TextWrapped=false
        D.make('UITextSizeConstraint',{MinTextSize=1,MaxTextSize=14},button)
    end
    local function styleScope()
        scope.BackgroundColor3=othersOnly and Color3.fromRGB(58,36,98) or Color3.fromRGB(45,130,75)
        myScope.BackgroundColor3=othersOnly and Color3.fromRGB(45,130,75) or Color3.fromRGB(58,36,98)
        scope.TextColor3=Color3.new(1,1,1);myScope.TextColor3=Color3.new(1,1,1)
    end
    local requestScopeRender
    local function setScope(myServer)
        if othersOnly==myServer then return end
        othersOnly=myServer;styleScope()
        page.Text=othersOnly and 'LOCAL EGGS' or PREMIUM_EDITION and 'GLOBAL TOP 10' or 'TOP 30'
        queryEpoch+=1;pageOffset=0;feedAt=-math.huge;task.defer(saveSettings)
        if requestScopeRender then requestScopeRender() end
    end
    scope.Activated:Connect(function() setScope(false) end)
    myScope.Activated:Connect(function() setScope(true) end)
    styleScope()
    local rarityOptions={{name='Any',rank=0},{name='Cosmic',rank=7},{name='Secret',rank=8},{name='Eternal',rank=9},{name='Divine',rank=10}}
    local rarityIndex=1
    for i,option in ipairs(rarityOptions) do if option.rank==minRank then rarityIndex=i;break end end
    minRank=rarityOptions[rarityIndex].rank
    local function rarityButtonText()
        local name=rarityOptions[rarityIndex].name
        local colors={Mythic='#FF4B55',Cosmic='#BE55FF',Secret='#FFFFFF',Eternal='#DACAEC',Divine='#FFCD37',Any='#FFFFFF'}
        return 'MIN RARITY: <font color="'..colors[name]..'">'..name..'</font>'
    end
    local rarity=D.make('TextButton',{Text=rarityButtonText(),RichText=true,Position=UDim2.new(0,10,1,-96),Size=UDim2.new(0.52,-14,0,36),BackgroundColor3=Color3.fromRGB(96,48,176),TextColor3=Color3.new(1,1,1),TextSize=12},panel)
    rarity.Activated:Connect(function()
        rarityIndex=rarityIndex%#rarityOptions+1;minRank=rarityOptions[rarityIndex].rank
        rarity.Text=rarityButtonText()
        queryEpoch+=1;feed={};pageOffset=0;feedAt=-math.huge;saveSettings()
    end)
    D.sortOptions={'Value','Weight','Rarity'}
    D.sortIndex=1
    D.sortButton=D.make('TextButton',{Name='SortBy',Text='SORT BY: Value',Position=UDim2.new(0.52,4,1,-96),Size=UDim2.new(0.48,-14,0,36),BackgroundColor3=rarity.BackgroundColor3,TextColor3=Color3.new(1,1,1),TextSize=12},panel)
    D.sortButton.Activated:Connect(function()
        D.sortIndex=D.sortIndex%#D.sortOptions+1
        D.sortButton.Text='SORT BY: '..D.sortOptions[D.sortIndex]
        queryEpoch+=1
        if requestScopeRender then requestScopeRender() end
    end)
    local access=PREMIUM_EDITION and AUTO_KEY=='' and D.make('TextBox',{Text='',PlaceholderText='PREMIUM code (top 10)',Position=UDim2.new(0,10,1,-44),Size=UDim2.new(1,-20,0,34),ClearTextOnFocus=false,BackgroundColor3=Color3.fromRGB(45,48,60),TextColor3=Color3.new(1,1,1),TextSize=12},panel) or {Text=''} 
    local unlock=D.make('TextButton',{Text='PREMIUM',Position=UDim2.new(0.70,4,1,-52),Size=UDim2.new(0.30,-14,0,40),BackgroundColor3=Color3.fromRGB(210,170,35),TextColor3=Color3.new(1,1,1),TextSize=12},panel)
    unlock.Visible=false -- S2R: Discord/premium upsell removed
    access.Visible=PREMIUM_EDITION and AUTO_KEY==''
    if PREMIUM_EDITION and AUTO_KEY~='' then
        unlock.Visible=false
        D.label(panel,'PREMIUM',UDim2.new(0.60,5,0,106),UDim2.new(0.40,-15,0,36),Color3.new(1,1,1),15)
    end
    local copy=D.make('TextButton',{Text='COPY DISCORD LINK',Position=UDim2.fromOffset(10,176),Size=UDim2.new(1,-110,0,27),BackgroundColor3=Color3.fromRGB(90,50,150),TextColor3=Color3.new(1,1,1),TextSize=12,Visible=not PREMIUM_EDITION},panel)
    copy.Visible=false -- Discord copying is now inside the Premium dialog.
    local function copyLink()
        if type(setclipboard)=='function' then
            local ok=pcall(setclipboard,DISCORD)
            if ok then
                copy.Text='LINK COPIED'
                task.delay(1.5,function() if active then copy.Text='COPY DISCORD LINK' end end)
                return true
            end
        end
        copy.Text=DISCORD; copy.TextWrapped=true; queryStatus='Discord: '..DISCORD; return false
    end
    copy.Activated:Connect(copyLink)
    local premiumPopup
    local function showPremiumPopup()
        if premiumPopup then premiumPopup.Visible=true;return end
        premiumPopup=D.make('Frame',{Size=UDim2.fromScale(1,1),BackgroundColor3=Color3.new(0,0,0),BackgroundTransparency=0.3,Active=true,ZIndex=30},panel)
        local box=D.make('Frame',{AnchorPoint=Vector2.new(0.5,0.5),Position=UDim2.fromScale(0.5,0.5),Size=UDim2.new(1,-28,0,232),BackgroundColor3=Color3.fromRGB(22,12,40),ZIndex=31},premiumPopup)
        D.make('UICorner',{CornerRadius=UDim.new(0,10)},box)
        themeModal(box)
        local discordMark=D.make('ImageLabel',{Name='PremiumDiscordIcon',Image='',AnchorPoint=Vector2.new(0.5,0),Position=UDim2.new(0.5,0,0,8),Size=UDim2.fromOffset(80,66),BackgroundTransparency=1,ScaleType=Enum.ScaleType.Fit,Active=false,ZIndex=32},box)
        loadUiAsset(discordMark,'discord')
        local title=D.label(box,'JOIN DISCORD TO GET PREMIUM',UDim2.fromOffset(12,76),UDim2.new(1,-24,0,52),Color3.new(1,1,1),20)
        title.Font=Enum.Font.FredokaOne;title.TextScaled=true;title.TextWrapped=true;title.TextXAlignment=Enum.TextXAlignment.Center;title.ZIndex=32
        D.make('UITextSizeConstraint',{MinTextSize=12,MaxTextSize=21},title)
        local bar=D.make('Frame',{Position=UDim2.fromOffset(12,148),Size=UDim2.new(1,-24,0,64),BackgroundColor3=Color3.fromRGB(38,22,70),ZIndex=32},box)
        D.make('UICorner',{CornerRadius=UDim.new(0,8)},bar)
        local link=D.label(bar,DISCORD,UDim2.fromOffset(8,6),UDim2.new(1,-116,1,-12),Color3.fromRGB(200,210,255),12)
        link.TextSize=12;link.TextWrapped=true;link.ZIndex=33
        local popupCopy=D.make('TextButton',{Font=Enum.Font.FredokaOne,Text='COPY LINK',Position=UDim2.new(1,-103,0.5,-18),Size=UDim2.fromOffset(96,36),BackgroundColor3=Color3.fromRGB(124,58,237),TextColor3=Color3.new(1,1,1),TextSize=14,ZIndex=33},bar)
        popupCopy.Font=Enum.Font.FredokaOne
        popupCopy.Activated:Connect(function()
            if type(setclipboard)=='function' and pcall(setclipboard,DISCORD) then
                popupCopy.Text='COPIED'
                task.delay(1.5,function() if active then popupCopy.Text='COPY LINK' end end)
            else popupCopy.Text='COPY UNAVAILABLE' end
        end)
        local dismiss=D.make('TextButton',{Text='×',Position=UDim2.new(1,-34,0,5),Size=UDim2.fromOffset(28,26),BackgroundColor3=Color3.fromRGB(135,55,90),TextColor3=Color3.new(1,1,1),TextSize=22,ZIndex=32},box)
        syncCloseArt(dismiss)
        dismiss.Activated:Connect(function() premiumPopup.Visible=false end)
    end
    unlock.Activated:Connect(function()
        if not PREMIUM_EDITION then
            showPremiumPopup()
            return
        end
        pageOffset=0
        if viewerCode~='' then viewerCode=''; feed={}; feedAt=-math.huge; unlock.Text='PREMIUM'; queryStatus='Public Finder'; return end
        viewerCode=access.Text:match('^%s*(.-)%s*$'); access.Text=''; feed={}; feedAt=-math.huge
        queryStatus='Checking access code'
    end)
    local refreshButton=D.make('TextButton',{Text='REFRESH',Position=UDim2.fromOffset(10,54),Size=UDim2.new(1,-20,0,30),BackgroundColor3=Color3.fromRGB(109,40,217),BackgroundTransparency=0.15,TextColor3=Color3.new(1,1,1),TextSize=14},panel)
    local resetTimer=D.label(refreshButton,'RESET --:--',UDim2.fromOffset(8,0),UDim2.new(0.28,-8,1,0),Color3.fromRGB(230,245,255),13)
    resetTimer.TextXAlignment=Enum.TextXAlignment.Left
    resetTimer.TextTruncate=Enum.TextTruncate.AtEnd
    resetTimer.Active=false
    local refreshing=false
    local list=D.make('ScrollingFrame',{Position=UDim2.fromOffset(14,92),Size=UDim2.new(1,-16,1,-238),BackgroundTransparency=1,BorderSizePixel=0,AutomaticCanvasSize=Enum.AutomaticSize.None,CanvasSize=UDim2.new(),ScrollBarThickness=6,ScrollBarImageColor3=Color3.fromRGB(167,139,250),ScrollBarImageTransparency=0},panel)
    D.make('UIListLayout',{Padding=UDim.new(0,4),SortOrder=Enum.SortOrder.LayoutOrder},list)
    local loadingVisible=true
    local function loadingText(now)
        return 'Loading '..string.rep('.',math.floor(now/0.4)%3+1)
    end
    local aliveMessage=D.label(list,loadingText(os.clock()),UDim2.new(),UDim2.new(1,-10,0,40),nil,12)
    local function network(url,method,body,headers,raw,timeout,independent)
        if type(requestFn)~='function' then return nil,'Executor HTTP POST unavailable' end
        local ticket
        if not independent then
            if networkBusy then return nil,'Network request still pending' end
            networkBusy=true;networkTicket+=1;ticket=networkTicket
        end
        local done,result=false,nil
        local worker=task.spawn(function()
            result=table.pack(pcall(requestFn,{Url=url,Method=method,Headers=headers or {},Body=body,Timeout=timeout or 10}))
            done=true; if ticket and networkTicket==ticket then networkBusy=false end
        end)
        local deadline=os.clock()+(timeout and timeout+0.5 or 12)
        while active and not done and os.clock()<deadline do task.wait(0.1) end
        if not done then
            if ticket and networkTicket==ticket then networkTicket+=1;networkBusy=false end
            pcall(task.cancel,worker)
            return nil,'Network timeout'
        end
        if not result[1] then return nil,'Network request failed' end
        local response=result[2]
        if type(response)~='table' then return nil,'Invalid HTTP response' end
        local code=tonumber(response.StatusCode or response.Status)
        if code~=200 then
            local message='HTTP '..tostring(code)
            local good,details=pcall(Http.JSONDecode,Http,response.Body or '')
            if good and type(details)=='table' and type(details.error)=='string' then message=message..': '..details.error:sub(1,120) end
            return nil,message
        end
        if raw then return response.Body end
        local ok,decoded=pcall(Http.JSONDecode,Http,response.Body or '')
        if not ok then return nil,'Invalid JSON response' end
        return decoded
    end
    -- Roblox public-server directory, independent of the Finder report feed.
    status.Size=UDim2.new(0.53,-14,0,24)
    status.TextSize=11
    local randomJoin=D.make('TextButton',{Name='RandomServer',Text='JOIN RANDOM SERVER',Position=UDim2.new(0,10,1,-52),Size=UDim2.new(1,-20,0,40),BackgroundColor3=Color3.fromRGB(124,58,237),TextColor3=Color3.new(1,1,1),TextSize=12,Font=Enum.Font.GothamBold},panel)
    D.make('UICorner',{CornerRadius=UDim.new(0,6)},randomJoin)
    randomJoin.TextScaled=true;randomJoin.TextWrapped=false
    D.make('UITextSizeConstraint',{MinTextSize=1,MaxTextSize=14},randomJoin)
    local featureConfig=nil
    local randomBusy=false
    local randomRetryAt=0
    local recentRandom={}
    local recentRandomPath='top4_preview_s2r_beta_random_recent_v1.json'
    pcall(function()
        if type(readfile)=='function' then
            local saved=Http:JSONDecode(readfile(recentRandomPath))
            if type(saved)=='table' then for _,id in ipairs(saved) do if type(id)=='string' and #recentRandom<20 then recentRandom[#recentRandom+1]=id end end end
        end
    end)
    local function rememberRandom(id)
        for i=#recentRandom,1,-1 do if recentRandom[i]==id then table.remove(recentRandom,i) end end
        recentRandom[#recentRandom+1]=id
        while #recentRandom>20 do table.remove(recentRandom,1) end
        if type(writefile)=='function' then pcall(function() writefile(recentRandomPath,Http:JSONEncode(recentRandom)) end) end
    end
    local function friendServerExclusions()
        local ok,friends=pcall(function() return D.player:GetFriendsOnlineAsync(200) end)
        if not ok then ok,friends=pcall(function() return D.player:GetFriendsOnline(200) end) end
        if not ok or type(friends)~='table' then error('Cannot check friend servers; try again') end
        local excluded={[game.JobId]=true}
        for _,friend in ipairs(friends) do
            local place=tonumber(friend.PlaceId or friend.placeId)
            local id=friend.GameId or friend.gameId or friend.JobId or friend.jobId
            if type(id)=='string' and id~='' then
                excluded[id]=true
            elseif place==game.PlaceId then
                local success,current,_,friendPlace,friendJob=pcall(function() return Teleports:GetPlayerPlaceInstanceAsync(friend.VisitorId or friend.visitorId) end)
                if success and tonumber(friendPlace)==game.PlaceId and type(friendJob)=='string' and friendJob~='' then excluded[friendJob]=true
                elseif success and current==true then excluded[game.JobId]=true
                else error('Friend server location unavailable; try again') end
            end
        end
        return excluded
    end
    D.queueTestReload=function()
        if D.testReloadQueued then return true end
        local env=type(getgenv)=='function' and getgenv() or {}
        local queue=queue_on_teleport or queueonteleport or queueOnTeleport
            or env.queue_on_teleport or env.queueonteleport or env.queueOnTeleport
            or (syn and syn.queue_on_teleport) or (fluxus and fluxus.queue_on_teleport)
        if type(queue)~='function' then
            D.gui:SetAttribute('S2RTestAutoExecute','Executor queue unavailable')
            return false
        end
        local code=string.format([==[
task.spawn(function()
    if not game:IsLoaded() then game.Loaded:Wait() end
    if game.JobId==%q then return end
    local players=game:GetService('Players')
    local deadline=os.clock()+25
    while not players.LocalPlayer and os.clock()<deadline do task.wait(0.2) end
    local player=players.LocalPlayer
    local gui=player and player:WaitForChild('PlayerGui',15)
    if not gui then return end
    local env=type(getgenv)=='function' and getgenv() or nil
    if env and env.__S2RDoTestBootJob==game.JobId then return end
    if env then env.__S2RDoTestBootJob=game.JobId end
    for attempt=1,3 do
        if gui:FindFirstChild('TENSHI_FINDER_TOP4_PREVIEW') then break end
        local ok,err=pcall(function()
            local source=game:HttpGet(%q..'?queued='..tostring(os.time())..'&attempt='..attempt)
            assert(loadstring(source))()
        end)
        if ok and gui:FindFirstChild('TENSHI_FINDER_TOP4_PREVIEW') then break end
        if not ok then warn('[S2R] Auto Execute: '..tostring(err)) end
        if attempt<3 then task.wait(1.5) end
    end
    if env then env.__S2RDoTestBootJob=nil end
end)
]==],game.JobId,S2R_RELOAD_URL)
        local ok,result=pcall(queue,code)
        D.testReloadQueued=ok and result~=false
        D.gui:SetAttribute('S2RTestAutoExecute',D.testReloadQueued and 'Queued' or 'Queue failed')
        return D.testReloadQueued
    end
    D.teleportReloadConnection=D.player.OnTeleport:Connect(function(state)
        if state==Enum.TeleportState.Started or state==Enum.TeleportState.InProgress then D.queueTestReload() end
    end)
    task.defer(function() if active then pcall(D.queueTestReload) end end)
    D.gui.Destroying:Connect(function() D.teleportReloadConnection:Disconnect() end)
    D.randomRejectedUntil={}
    D.fewestRandomCandidates=function(servers,excluded,now)
        local lowest=math.huge
        local choices,fresh,seen={},{},{}
        for id,untilAt in pairs(D.randomRejectedUntil) do if now>=untilAt then D.randomRejectedUntil[id]=nil end end
        for _,server in ipairs(servers) do
            local id=server.id
            local playing,maxPlayers=tonumber(server.playing),tonumber(server.maxPlayers)
            local observed=D.populationReports and D.populationReports[id]
            if observed and os.clock()-observed.observedAt<=12 then playing=observed.count end
            if type(id)=='string' and id~='' and not seen[id] and not excluded[id] and not D.randomRejectedUntil[id]
                and playing and maxPlayers and playing>=0 and playing<maxPlayers and playing<=lowest then
                seen[id]=true
                if playing<lowest then lowest=playing;choices={};fresh={} end
                choices[#choices+1]=id
                if not table.find(recentRandom,id) then fresh[#fresh+1]=id end
            end
        end
        return #fresh>0 and fresh or choices
    end
    local function finishRandom(run,cooldown,message)
        if not active or D.randomRun~=run then return end
        D.randomRun=nil
        randomBusy=false
        joining=false
        randomRetryAt=os.clock()+cooldown
        randomJoin.Active=true
        randomJoin.AutoButtonColor=true
        randomJoin.Text='TRY AGAIN'
        if cooldown>=3 then
            local retryAt=randomRetryAt
            randomJoin.Active=false
            randomJoin.AutoButtonColor=false
            randomJoin.Text='WAIT '..tostring(cooldown)..'s'
            task.delay(cooldown,function()
                if active and not randomBusy and randomRetryAt==retryAt then
                    randomJoin.Active=true
                    randomJoin.AutoButtonColor=true
                    randomJoin.Text='TRY AGAIN'
                end
            end)
        end
        if message then queryStatus='Random server: '..tostring(message) end
    end

    D.handleRandomFailure=function(run,target,result,message)
        if not active or D.randomRun~=run or run.target~=target then return end
        run.target=nil
        D.testReloadQueued=false
        warn(('[DO TEST random] failed job=%s place=%s result=%s message=%s'):format(target,tostring(game.PlaceId),tostring(result),tostring(message)))
        local failure=tostring(message):lower()
        local retryable=D.isFullFailure(result,message) or result==Enum.TeleportResult.GameEnded
            or result==Enum.TeleportResult.Failure or failure:find('unknown exception',1,true)
            or failure:find('unexpected error',1,true)
        local flooded=result==Enum.TeleportResult.Flooded or failure:find('flood',1,true)
        if retryable and not flooded then
            D.randomRejectedUntil[target]=os.clock()+60
            if run.attempts<4 and os.clock()+2<run.deadline then
                randomJoin.Text='SEARCHING...'
                task.delay(2,function() D.tryRandomTarget(run) end)
                return
            end
        end
        finishRandom(run,flooded and 15 or 0.75,message)
    end

    D.tryRandomTarget=function(run)
        if not active or D.randomRun~=run then return end
        if os.clock()>=run.deadline then
            finishRandom(run,0.75,'Server list expired')
            return
        end
        if run.attempts==2 or os.clock()-run.directoryAt>=8 then
            local ok,err=pcall(D.loadRandomDirectory,run)
            if not active or D.randomRun~=run then return end
            if not ok and os.clock()-run.directoryAt>12 then finishRandom(run,1,err);return end
        end
        local candidates=D.fewestRandomCandidates(run.servers,run.excluded,os.clock())
        if #candidates==0 then
            finishRandom(run,0.75,'No available random server without known friends')
            return
        end
        local target=candidates[math.random(1,#candidates)]
        if not run.prepared then
            run.prepared=true
            D.saveGuiBeforeTeleport()
            if type(D.flushReport)=='function' and (not D.lastSharedReport or os.clock()-D.lastSharedReport>=12) then
                task.spawn(function() pcall(D.flushReport,2) end)
            end
            D.stopFarm()
        end
        if not active or D.randomRun~=run then return end
        run.attempts+=1
        run.target=target
        randomJoin.Text='JOINING...'
        task.delay(0.5,function()
            if D.randomRun==run and run.target==target then randomJoin.Text='JOIN RANDOM SERVER' end
        end)
        print(('[DO TEST random] requesting job=%s place=%s listAge=%.1fs'):format(target,tostring(game.PlaceId),os.clock()-run.directoryAt))
        rememberRandom(game.JobId)
        rememberRandom(target)
        task.delay(5,function()
            if run.target==target then finishRandom(run,0.75,'Roblox did not complete the teleport') end
        end)
        local ok,err=pcall(Teleports.TeleportToPlaceInstance,Teleports,game.PlaceId,target,D.player)
        if not ok then D.handleRandomFailure(run,target,nil,err) end
    end

    D.loadRandomDirectory=function(run)
        local directory=featureConfig
        if not directory then error('Server directory is connecting; try again') end
        local data,err=network(directory.endpoint..'/v1/random-servers','GET',nil,{['X-NYX-Room']=directory.roomKey},false,9,true)
        if not data then error(err or 'Roblox server list unavailable') end
        if type(data)~='table' or type(data.data)~='table' then error('Invalid server list') end
        run.servers=data.data
        run.directoryAt=os.clock()-math.max(0,tonumber(data.ageSeconds) or 0)
    end

    D.joinRandomServer=function()
        if randomBusy or joining or os.clock()<randomRetryAt then return end
        local run={deadline=os.clock()+18,attempts=0}
        D.randomRun=run
        randomBusy=true
        joining=true
        randomJoin.Active=false
        randomJoin.AutoButtonColor=false
        randomJoin.Text='SEARCHING...'
        task.delay(18,function() finishRandom(run,0.75,'Random server request timed out') end)
        task.spawn(function()
            local ok,err=pcall(function()
                run.excluded=friendServerExclusions()
                if not active or D.randomRun~=run then return end
                D.loadRandomDirectory(run)
                D.tryRandomTarget(run)
            end)
            if not ok and active and D.randomRun==run then
                finishRandom(run,3,err)
            end
        end)
    end
    randomJoin.Activated:Connect(D.joinRandomServer)

    local publicBroadcastConfig=nil
    local featureSending=false
    local featureTicket=0
    local featureAttemptAt=os.clock()-15+Random.new():NextNumber(0,15)
    local featureAckAt=-math.huge
    local featureSignature=nil
    D.featureStatus='Connecting'
    local function sendFeature(payload,signature)
        if not featureConfig or featureSending or type(requestFn)~='function' then return end
        local endpoint,key=featureConfig.endpoint,featureConfig.roomKey
        featureSending=true;featureTicket+=1;featureAttemptAt=os.clock()
        local ticket=featureTicket
        local worker=task.spawn(function()
            local ok,response=pcall(requestFn,{Url=endpoint..'/v1/report',Method='POST',Timeout=6,
                Headers={['Content-Type']='application/json',['X-NYX-Room']=key},Body=Http:JSONEncode(payload)})
            if featureTicket~=ticket then return end
            featureSending=false
            local decoded,body=false,nil
            if ok and type(response)=='table' and tonumber(response.StatusCode or response.Status)==200 then
                decoded,body=pcall(Http.JSONDecode,Http,response.Body or '')
            end
            local acknowledged=decoded and type(body)=='table' and body.ok==true and type(body.accepted)=='number'
                and not body.staleScan and not body.cycleClosed and not body.metadataRequired
                and (#payload.eggs==0 or body.accepted>0)
            if acknowledged then
                featureAckAt=os.clock();featureSignature=signature
                D.featureStatus='Sent '..tostring(body.accepted)..'/'..tostring(#payload.eggs)
            else
                D.featureStatus='Report retry'
            end
            D.gui:SetAttribute('S2RFeatureReportOK',acknowledged==true)
        end)
        task.delay(8,function()
            if featureTicket==ticket and featureSending then
                featureTicket+=1;featureSending=false;pcall(task.cancel,worker)
                D.featureStatus='Report retry'
                D.gui:SetAttribute('S2RFeatureReportOK',false)
            end
        end)
    end
    local function loadConfig()
        local data,err=network('https://raw.githubusercontent.com/syss1211/Tenshi-script/main/NYX-Contabo-Config.json?nyx='..os.time(),'GET',nil,nil,false,4)
        if not data then return false,err end
        if type(data.endpoint)~='string' or not data.endpoint:match('^https://[%w%.%-]+$') or type(data.roomKey)~='string' then
            return false,'Contabo configuration unavailable'
        end
        local trial=data.endpoint..'/finder'
        local roomKey=data.roomKey
        featureConfig={endpoint=trial..'/feature',roomKey=roomKey}
        publicBroadcastConfig={endpoint=trial..'/primary',roomKey=roomKey}
        config=featureConfig;configAt=os.clock()
        return true
    end
    local broadcastInterval=12
    local function snapshot()
        local eggs={}
        for _,entry in ipairs(D.reportEntries()) do
            if not entry.unresolved and entry.uid and entry.rate and entry.rate>=MIN_BROADCAST_RATE then
                eggs[#eggs+1]={uid=tostring(entry.uid),name=entry.name,category=entry.category,rarity=entry.rarity,rank=entry.tier,rate=entry.rate,scale=entry.scale,weight=entry.weight,icon=entry.icon,area=entry.areaKey or entry.area,mutations=entry.mutationText or (entry.traitsKnown==false and 'UNKNOWN' or ''),traitsKnown=entry.traitsKnown~=false,estimated=entry.estimated==true or entry.unmutatedRate~=nil or entry.scaleFromModel==true,visualId=entry.visualId==true,source=entry.isEvent and 'event' or 'field'}
            end
        end
        table.sort(eggs,function(a,b) return a.rate>b.rate end)
        while #eggs>3 do eggs[#eggs]=nil end
        return eggs
    end
    local function report(timeout)
        if game.JobId=='' then return false,'No live server ID' end
        if not D.ready() then return false,'Waiting for a fresh field scan' end
        if not publicBroadcastConfig then return false,'Public broadcast configuration unavailable' end
        local eggs=snapshot()
        local good,metadata=pcall(function() return D.metadata and D.metadata() end)
        if not good then metadata=nil end
        local classicEggs=eggs
        -- Match the classic sender's native spawn-slot behavior. Optional state
        -- parsing is protected and never becomes a prerequisite for reporting.
        if metadata and type(metadata.states)=='table' then
            local parsed,filtered=pcall(function()
                local states={}
                for _,state in ipairs(metadata.states) do states[state.uid]=state.state end
                local values={}
                for _,e in ipairs(eggs) do
                    if states[e.uid]=='Slot' then
                        values[#values+1]=e
                        if #values==3 then break end
                    end
                end
                return values
            end)
            if parsed then classicEggs=filtered end
        end
        local removed={}
        for _,record in ipairs(metadata and metadata.states or {}) do
            if record.state=='Claimed' then
                removed[#removed+1]=record.uid
                if #removed==256 then break end
            end
        end
        local players=game:GetService('Players')
        local body={placeId=game.PlaceId,jobId=game.JobId,reporterId=reporterId,eggs=classicEggs,removedUids=removed,
            playerCount=#players:GetPlayers(),maxPlayers=players.MaxPlayers}
        if metadata and type(metadata.resetAt)=='number' then
            if metadata.resetAt-workspace:GetServerTimeNow()*1000<=2000 then return false,'Waiting for reset' end
            body.resetAt=metadata.resetAt
        end
        local data,err=network(publicBroadcastConfig.endpoint..'/v1/report','POST',Http:JSONEncode(body),
            {['Content-Type']='application/json',['X-NYX-Room']=publicBroadcastConfig.roomKey},false,timeout)
        if not data or data.ok~=true or type(data.accepted)~='number' then return false,err or 'Public broadcast not acknowledged' end
        if #classicEggs>0 and data.accepted<=0 then return false,'Public broadcast accepted zero eggs' end
        if D.gui then pcall(function() D.gui:SetAttribute('S2RPublicAccepted',data.accepted);D.gui:SetAttribute('S2RPublicSent',#classicEggs) end) end
        D.lastSharedReport=os.clock()
        return true,'Shared '..tostring(data.accepted)..' eggs'
    end
    D.flushReport=report
    task.spawn(function()
        while active do
            local ok,err=pcall(function()
                if not featureConfig or not D.ready() or featureSending or os.clock()-featureAttemptAt<broadcastInterval or game.JobId=='' then return end
                local metadata=D.metadata()
                if not metadata or not metadata.resetAt or not metadata.scanAt or not metadata.scanClock then return end
                local remaining=metadata.resetAt-workspace:GetServerTimeNow()*1000
                if remaining<=2000 then D.featureStatus='Waiting for reset';return end
                local players=game:GetService('Players')
                local ids={}
                for _,member in ipairs(players:GetPlayers()) do ids[#ids+1]=member.UserId end
                local signatureParts={tostring(metadata.resetAt),'players:'..tostring(#ids)}
                for _,record in ipairs(metadata.states) do signatureParts[#signatureParts+1]=record.uid..':'..tostring(record.state) end
                table.sort(signatureParts)
                local signature=table.concat(signatureParts,';')
                if signature==featureSignature and os.clock()-featureAckAt<broadcastInterval then return end
                local eggs=snapshot()
                sendFeature({placeId=game.PlaceId,jobId=game.JobId,reporterId=reporterId,reporterStartedAt=D.reporterStartedAt,eggs=eggs,publicDirect=true,
                    eggStates=metadata.states,resetAt=metadata.resetAt,scanAt=metadata.scanAt,
                    scanAgeMs=math.max(0,(os.clock()-metadata.scanClock)*1000),resetRemainingMs=remaining,
                    userId=D.player.UserId,playerIds=ids,maxPlayers=players.MaxPlayers},signature)
            end)
            if not ok then D.featureStatus='Report retry';warn('DO test broadcast: '..tostring(err)) end
            task.wait(1)
        end
    end)
    do
        local players=game:GetService('Players')
        local lastFull=#players:GetPlayers()>=players.MaxPlayers
        local scheduled=false
        local nextSend=0
        local function queuePopulation()
            if scheduled or not active then return end
            scheduled=true
            task.delay(math.max(0.20,nextSend-os.clock()),function()
                scheduled=false
                if not active or not featureConfig or game.JobId=='' then return end
                local count=#players:GetPlayers()
                local capacity=players.MaxPlayers
                local full=count>=capacity
                if full==lastFull then return end
                lastFull=full
                nextSend=os.clock()+2
                local body=Http:JSONEncode({placeId=game.PlaceId,jobId=game.JobId,reporterId=reporterId,
                    playerCount=count,maxPlayers=capacity})
                network(featureConfig.endpoint..'/v1/population','POST',body,
                    {['Content-Type']='application/json',['X-NYX-Room']=featureConfig.roomKey},false,2,true)
            end)
        end
        local added=players.PlayerAdded:Connect(queuePopulation)
        local removing=players.PlayerRemoving:Connect(queuePopulation)
        D.gui.Destroying:Connect(function() added:Disconnect();removing:Disconnect() end)
    end
    local function refresh()
        local directory=featureConfig
        local fallback=viewerCode=='' and publicBroadcastConfig or nil
        local epoch=queryEpoch
        local query='?localJob='..Http:UrlEncode(game.JobId)..'&placeId='..game.PlaceId..'&limit='..(viewerCode~='' and '10&tier=premium' or '30&tier=public')..'&offset=0'..(viewerCode~='' and '&minRate='..tostring(minRate)..'&minRank='..tostring(minRank) or '')
        local requestedCycle=cycleInfo()
        if requestedCycle then query=query..'&cycleRemainingMs='..tostring(math.max(0,requestedCycle.remaining*1000))..'&cycleId='..tostring(requestedCycle.resetAt) end
        if othersOnly and viewerCode~='' then query=query..'&onlyJob='..Http:UrlEncode(game.JobId) end
        local data,err
        local usedFallback=false
        if directory and os.clock()>=(D.featureReadRetryAt or 0) then
            data,err=network(directory.endpoint..'/v1/eggs'..query,'GET',nil,{['X-NYX-Room']=directory.roomKey,['X-NYX-Viewer']=viewerCode~='' and viewerCode or nil},false,5,true)
            if fallback and (type(data)~='table' or type(data.items)~='table') then
                D.featureReadRetryAt=os.clock()+10
            end
        end
        if epoch~=queryEpoch then return true end
        if fallback and (not directory or fallback.endpoint~=directory.endpoint) and (type(data)~='table' or type(data.items)~='table') then
            data,err=network(fallback.endpoint..'/v1/eggs'..query,'GET',nil,{['X-NYX-Room']=fallback.roomKey},false,4,true)
            usedFallback=true
        end
        if epoch~=queryEpoch then return true end
        if type(data)~='table' or type(data.items)~='table' then
            D.feedReadRetryAt=os.clock()+3
            if err=='HTTP 401' then viewerCode=''; unlock.Text='PREMIUM'; feed={}; pageOffset=0 end
            return false,err=='HTTP 401' and 'Wrong access code' or err or 'Invalid finder feed'
        end
        unlock.Text=data.tier=='premium' and 'PREMIUM ON' or 'PREMIUM'
        nextOffset=tonumber(data.nextOffset)
        page.Text=data.tier=='premium' and 'GLOBAL TOP 10' or 'TOP 30'
        local receivedAt=os.clock()
        clockOffset=math.max(clockOffset,(tonumber(data.serverTime) or os.time()*1000)/1000-receivedAt)
        feed={}
        for _,entry in ipairs(data.items) do
            local now=(os.clock()+clockOffset)*1000
            if D.publicEntryAllowed(entry,now) then
                feed[#feed+1]=entry
            end
        end
        D.gui:SetAttribute('S2RFeedRoute',usedFallback and 'fallback' or 'primary')
        local serverNow=(os.clock()+clockOffset)*1000
        D.hostTaken={}
        for _,entry in ipairs(feed) do
            if entry.jobId==game.JobId and type(entry.key)=='string' and entry.takenConfirmed==true then
                D.hostTaken[entry.key]=entry
            end
        end
        for _,entry in ipairs(data.localStates or {}) do
            if entry.jobId==game.JobId and type(entry.key)=='string' and entry.takenConfirmed==true and D.publicEntryAllowed(entry,serverNow) then
                D.hostTaken[entry.key]=entry
            end
        end
        D.feedReporters=tonumber(data.participants) or 0;feedAt=os.clock()
        D.feedPressureHint=data.refreshSeconds==5
        D.nearFull=false
        local limit=tonumber(data.joinerLimit)
        if not othersOnly and limit and limit>1 then
            for _,entry in ipairs(feed) do
                if (tonumber(entry.joinerCount) or 0)>=limit-1 then D.nearFull=true;break end
            end
        end
        queryStatus=data.tier=='premium' and string.format('PREMIUM | %d servers | %d reporters',data.servers or 0,data.participants or 0) or 'Updated'
        return true
    end
    local lastRender
    local rarityColors={
        divine=Color3.fromRGB(255,205,55),eternal=Color3.fromRGB(218,202,236),
        secret=Color3.fromRGB(255,255,255),cosmic=Color3.fromRGB(190,85,255),
        mythic=Color3.fromRGB(255,75,85),legendary=Color3.fromRGB(255,155,45),
        epic=Color3.fromRGB(255,110,200),rare=Color3.fromRGB(65,165,255),
        uncommon=Color3.fromRGB(105,220,120),common=Color3.fromRGB(220,225,235)
    }
    local function weightPresentation(entry)
        local isKg=type(entry.weight)=='number'
        local value=isKg and entry.weight or entry.scale
        local neutral=Color3.fromRGB(220,224,235)
        if type(value)~='number' or value~=value or value<0 or value==math.huge then return '—',neutral end
        local compact=value>=1000
        local number
        if value>=1e15 then number=string.format('%.2g',value)
        elseif value>=1e12 then number=string.format('%.2f',value/1e12):gsub('0+$',''):gsub('%.$','')..'T'
        elseif value>=1e9 then number=string.format('%.2f',value/1e9):gsub('0+$',''):gsub('%.$','')..'B'
        elseif value>=1e6 then number=string.format('%.2f',value/1e6):gsub('0+$',''):gsub('%.$','')..'M'
        elseif compact then number=string.format('%.2f',value/1000):gsub('0+$',''):gsub('%.$','')..'K'
        else number=string.format('%.2f',value) end
        local color=neutral
        if not isKg and not compact then
            if value<0.60 then color=Color3.fromRGB(245,85,85)
            elseif value<0.80 then color=Color3.fromRGB(255,210,75)
            elseif value>2.50 then color=Color3.fromRGB(100,240,140) end
        end
        return (isKg and number..' KG' or '×'..number),color
    end
    D.scalePresentation=function(entry)
        local value=entry.scale
        local neutral=Color3.fromRGB(220,224,235)
        if type(value)~='number' or value~=value or value<0 or value==math.huge then return '—',neutral,Color3.new(0,0,0) end
        local color=neutral
        if value<0.60 then color=Color3.fromRGB(245,85,85)
        elseif value<0.80 then color=Color3.fromRGB(255,210,75)
        elseif value>10 then color=Color3.fromRGB(125,55,190)
        elseif value>2.50 and value<1000 then color=Color3.fromRGB(45,155,80) end
        return (value>=1e5 and string.format('x%.2g',value) or string.format('x%.2f',value)),color,Color3.new(0,0,0)
    end
    local function mutationNames(entry)
        if entry.isEvent or entry.source=='event' then return {} end
        local raw=tostring(entry.mutations or entry.mutationText or ''):gsub('%s*%[[^%]]*%]',''):match('^%s*(.-)%s*$')
        raw=raw:gsub('^[Mm]utation[sS]?%s*:%s*','')
        local lower=raw:lower()
        if entry.traitsKnown==false or lower:find('unknown',1,true) or lower:find('unverified',1,true) then return {'Unknown'} end
        if raw=='' or lower=='none' or lower=='normal' or lower=='none (explicit data)' then return {} end
        local result,seen={},{}
        for token in raw:gmatch('[^,;|+]+') do
            local name=token:match('^%s*(.-)%s*$')
            local key=name:lower()
            if key=='gold' or key=='golden' then name='Golden';key='golden'
            elseif key=='silver' then name='Silver'
            elseif key=='rainbow' then name='Rainbow' end
            if name~='' and not seen[key] then result[#result+1]=name;seen[key]=true end
        end
        local order={golden=1,silver=2,rainbow=3}
        table.sort(result,function(a,b)
            local left,right=order[a:lower()] or 4,order[b:lower()] or 4
            if left~=right then return left<right end
            return a:lower()<b:lower()
        end)
        return result
    end
    -- Glyph masks rendered from Minecraft.ttf by Craftron Gaming:
    -- https://www.dafont.com/minecraft.font
    local mutationSpriteData={
        studs_v05={width=512,height=512,data='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'},
        kindly_full={width=82,height=32,data='iVBORw0KGgoAAAANSUhEUgAAAFIAAAAgCAYAAACBxi9RAAAAAXNSR0IArs4c6QAAAARnQU1BAACxjwv8YQUAAAAJcEhZcwAADsMAAA7DAcdvqGQAAAPTSURBVGhD7ZqNUeMwEEYpIA3QAA3QABVQAR3QQVqgBWqgCbqgmHDvW1ZCsn6d081ALm9GY0W7+iStZdmyc3Plys/n8/PzcDqdHklH0psSZVWwfZBeyN579QzKpSW7Qf7opgzKn91FPq+kOzcVYLslpZrvHB7cPM0qnSqIPX7JfkOZBvbqP5uorssYFCmI7yQFW502bY5ZMPld1aa8GkzKNeAIv+1Ec3x2lylW6RSg8SAhoUY8vW5tPfC/NTFQXS+TztEcvjm4T3HiAtg+TCiBsjs3qz+hTweS5bHH9nus0qmijpM06FuJcoyX2yzUeZIW2Xvpccwu7QRbCrBls2IL9myW67fqeD4uOeTtRHG09kes0imgYjhDCkBzloygrl0WHLUcqLM6KTVsLfJ8E+nILyB9T6G/GbK5a5dVOgVU1KDtUnKts/CO6RIRrdkobEZ6foQtA0IDDMltGSp31y6rdApcVFP8/ktqP9R/cS2dlBdSazYKC47nR8Q7qfpIWhHIJToFLnpWIKmndTWuZeT12GTBdJcM+bvrVCDxj4MirwDoJK0I5F/rFFBRa5oW/nBZGpS9uV2PL0/uY5BvPZ5YJ92tQDruOhtIm+lC2l5cBft0IL1KlVmdgpFwDerEAaa4uQn14qOFF3VR39z9YgMZB5ji5irUiZe14Lcekbqk7Yz6if0yAklxd42lznZXM2w3bWfkj/3/CCRke9mZdtN2Rv7Yf2Ugs12HoHg0I7MblDrspibqm7tfXiDxr77FwdQNpLtF1GE3NcHnsu7a+BQzcAs+1S1XwN0iFA2fW9NBKe/FVVLfHqt0Cqg4DKS7DnH3FnG7J/g9DCSkO5vfH0iovrzd4r4tMg3affLyJvikr+Z+fCCbO5HAjk42T4racTej5yuwZ+8kKQrvDqvgb7sz99WbLNv6krLXYtiW6BTI0RQ64FPdyWwZaWG3tVad8qIm+GQ3NYpmloIqaKV7/CU6BRhnAtkWSMCve8PZA1rZm2qKsncBe9E4V+oUYOtO9YC7D6Gh4dZvBBpn7eVHuMwynQw6PTWL5OdVuuiMeZWzQaP63YTymRtjkzCGVToFbh8xe+f+N5cOYNt+SNtL+F60RKdg8gxNf/eV71eVfdCP7DvNFlzOvlEIl1mmU8AAhh+98Jm6tAP4Dx+rUhREDtlDew38zlqDqZfN9FU6BTj03mxPPf5sUaMu0WXYuQTcd812tBWw4mpSmTlM0tKpgqMeQOO/H1R5zyBrUN/+HiItlzX4bQ+5ZIezcItrhm9NGZTZnxtI+jzSvYqwL9G5cuWncHPzB0AK0axMbE74AAAAAElFTkSuQmCC'},
        filter_divine={width=111,height=44,data='iVBORw0KGgoAAAANSUhEUgAAAG8AAAAsCAYAAABrCeaiAAAAAXNSR0IArs4c6QAAAARnQU1BAACxjwv8YQUAAAAJcEhZcwAADsMAAA7DAcdvqGQAAAQDSURBVHhe7ZoNcdwwEIUD4AiEQAgcgSIIgjAog1AIhWAIibIomLTv2c/u6VZayTr5nHT2m/HE2j/Jeo4se+4hCIL/nc/Pzycc738Ezj9ok3t3ju7/24K5Os1TZsEEPipsN9DNof3vCi7gp67FRXfrG45nNE9Kr4L4l7mChX0rbDeO7n9XeAG6lk0gj0JW71yvPnyvCtuNo/vfFe/iWkD+i0ploV+hBvatsN04uv9d4QXoWrpBjTeVM8Adz7y9GCEe8QSEL3abe4CLGCIeQS13CQ0GM1I80bwTDW7EEw++D8U84nhmW64irDcVDvaHk615N1Asha3AfJ69ZRQ6gaYXf2YM+nlUO8ePqVAG+uYQC2sqpto/8eZBIYwxNzDafJaudVpQnXccv+cqM6yNg7vjttULwZvEI7A/KaTEOuE4b5285EIWYPc2Qm8KS2AthQwRD5zgd1cdb5wLCDtzbHOGD+KelVbGGzQHrDBDJW9dOtFsnbyqENfQp7AE1lLIEPHg+6VTl8t+r4GPX6Y2wTEpPU9l0EXx4Pben9Y8NFsnr3hx8Jn3MdrkNrCWwoaItxGzzNM2u7ooPja6xSP0KzThMg/N1slrEmOBNrkNrKWwu4uHOslKAROX3KalMsd1vQRv0PDdTTyCvOzyBLtZjmiTO4E1FDIB073/8ziG9QMAzjcvl9ewhsqleIOGr1e8dQLR3CLeq+wGhazIbGANhUzANEQ8+HmzTLtA/PVqMnZ9VuG8+LyEb/qogVP+d2ZvRgLf+1TsGnakGAN8d/3PQ9vb+l/ezd5uN3lGoH2zePCZyfPGAN/l9WdBTG41Ke5oFZKChC7x4B66YSFoezXXT288lzlH8o6E9gjxst9BeZ0KSYB9WnmYJ9PNTB1eUxl0UbxK3uZXhQX2KV8C7Ovdz3OZE5irkBWYbxZPIYZaDv54fW/FzFVNhKx4sA9/SV9omUQ1DcxVyArMId4CzNUBKXQCzU3i0Ta7stA3tJ7C7i4ecqtfZKq0iIe/3R+mYdo02UQ+A2vzUNOg9ASYDxOPqFkie/3NeAPopGvDcAnGVHym8VAzgTlKT4DrUPEQ435ag5+vCGYeYOejid9CXxjDtlz/gHGYeKhlXiZh7hHP201mYY7SE+A6WrybX9KFnStvAFtAnewaDlePeJu32MxRegJch4pHENf9eeyCfcRDjeLDF+7N4hH5m1GaAa6vIN6I973x4iHf/d0KQrrEQ93scy8HY5VmgPtw8QhibxVwnHjIa/rRLUJ7xWt+VjBWaQa4v4R4BGb3G2aFfvEQ1/Vzd8T2iuf9NCKBsUozwP1lxFuAmyLy1YvzWdo9L/PN3Wb2eR4EQRAEQRAEQRAEQRAEQfB9eHj4C9ICM72pnaD1AAAAAElFTkSuQmCC'},
        filter_cosmic={width=126,height=44,data='iVBORw0KGgoAAAANSUhEUgAAAH4AAAAsCAYAAACjZQx0AAAAAXNSR0IArs4c6QAAAARnQU1BAACxjwv8YQUAAAAJcEhZcwAADsMAAA7DAcdvqGQAAATbSURBVHhe7ZsLcdwwEIYDIARKoARCoAiCIAzKoBRCIRhKIiwKJu336357zqeHJfvuEnf2m9HE2l2t1lo/JPnyEARBENybj4+P75S3v4bj35JZHfyPkOfHU7pzSP43m30eCoLyQnmjvDu2GWR/KLpSf1Ge3SxYgbF68RBmoPtps/tD/08EMD+GenHzYAUl10OWge6Xze4H/T6q41MI49hNsAJj/HXuePpU0rPH+Qh2FazAUH2Ndzz97U66sLugA8b782f16tT978LugiNA0p+dt93YZXAESPwf562KH0PPlMX7B5XeVU+UH+juPxsNtqGEUZoo4TbfBa40j5j2BLKLDZkuLum7Jzc007JTewjZqwrZO+WVkl2w1IvLKeS/rdf+xavFCep6Hz8lBxegUx/zHEnHFPXxaJMFyHWz1Cj2MYFe46j+ansraV+Fw7ofDBYndwn63UnHzfASUXFRqheAdJTueYls3TRBvZp4yndXi6BfjAn16hiiU2Ky5CMbTjxyjWN1/V+hnHwcVR/z6BaDtQV8aOa6+ippkAWOrLoUqnF5LtRrie+N9Yf9rF7Q2LynTs9APJR4fGwdxzzxCJsDSEe77nbaf7OrXeik7TJBvfmUKkGbrsT3QnttVXefH7aLsUTUnXjqwxf6GcXEtzrPBnwU2l9liahB5k96XOpvEg6iWFJQhvquxAvH1YVs3XUCUXfiFbvlWxhPvM02QfPVSeMISpT9NmOuocFLgRn5s+pu0Od8I1HtSryOT6LN3DfxnGTzAw967R3Mkx6OtRys7hyiS3cMh9WY1SdlnhDqGLFm/T9VLE6ofmpVJQ0YdtU99Qls9OrRxEsTztY5zDFQ7Uo8bdbGUed2ucTWOWvWr9VO/tSWQWpdodioE7sochnoBCoNXmvgNMFpvVfThKsH/FQTj25k1r54hLfiQ/dms+7Eu14Ef9vyQ9ubTO4UkF1koGt+ecKk9YqYZtLVdx463fVKqq761nKwdccvll/UqzHhJ9u0Qla8eJHPrxuqq4nHvjWO+zbLcFCdoJwHOgJNu67mEuirFyPxTO/55pPhHJ0fJbuA5csmGTaZwbZ1F7/YbAZZ8QmBfCjx+nuqFmmO4yq1ICfQD9/1NLtp4icUmwbT6iayc7OEfFm14NJuwuoS2fn0+Kb6uYnHwdW3bLG/6aO+BH51V2qC2Hofz33r2OIFyL9M4rG/3aNe4GR1PaqgKdmeNyrdoTqJxUcatalx6WMC1erkzqZNFIebLJBvmxwi8cL1IvjbPPlO4ODqn2XxeZPlnOBYH3LUXoN37kMXYfMJZtPDJJ4211/OnYPBVXbZ7G7txIYhvvPH9OZY7eIwidfxSbSZLL4FGHTPlFvYXUInavEu8DNv2Yqtfmk3r6M5PkTihdpZvoV24gVGu5NvVwl8tTZbusHP4nG1dSBoN09SOT5M4qk391tWWE+8wFDJv9rPq/F19c+yGkDruqHNq5snqB8m8YK21/ss28IdNScWJdx8AeLhiwn76g8xkA8lHvtsCSmZ1Qvk2yYLrC5xl8QL5BrHou8GY4mfoCN9eNAMUYkoDrjklNV/ocJUge/+6ZX0tpOfLCZk2q2TruoL+eESP4Fe46ic6ByzV7P6oehG25b0IAiCIAiCIAiCIAiCIAiCIAhuwMPDP7/xa7YQIwtaAAAAAElFTkSuQmCC'},
        filter_prefix={width=213,height=44,data='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'},
        filter_eternal={width=124,height=44,data='iVBORw0KGgoAAAANSUhEUgAAAHwAAAAsCAYAAACnkNxJAAAAAXNSR0IArs4c6QAAAARnQU1BAACxjwv8YQUAAAAJcEhZcwAADsMAAA7DAcdvqGQAAAQCSURBVHhe7ZqLcdwwDERdgBtwA27ADbgCV3AdpAO34BZcQ5pwFynmkl3e6ksSJCUmR2fwZjSSCCwACrJ+5wfHcRzHcb431+v1x+8TUK9Qzh2w+gfbT7kteMO/N0M1HLYLk06Lhp2O8PirFRHJY24JaqBeoSJg+yW3gIadjgzTcJhebx4LMjkdGabhTCaXGZmcjgzRcIw9ybxBZqcjXRueFFQA3btCbJDZ6chdGg7Xl5uiDcmTIPcblk8smwc/1oTlgs1HuUbAnpwTtXIJNWP/A8vXzbrUk9MTuUz1bW5b2P/E6kUuWeD3JP07Y2DZzJFwTLZDcyXUy22hWZAArt0ajmE2IjoAKeD3JtmG3Jw4H6wetY6Q3DwmIKufgP1DoZKU9CmguUi+waqVeeS2YAksJA9gt0vDUcubTNWwfslncnPC+BcX7UZIXjqIWf0a+GWbDltzwwnrUoiZQq3jNhy70WtcA68KEzg7p6P6BJu6JtgI2ZuB9klhAlatzCO3haOTkzyA3VMNxyYvk1WX8RTUKlTg7JyO6vfs65rA+JmGb64cVq3MI7cFS2AheQC7pxqOGpov5XsYQ+FOz+moPgViPSvsDMYON5woTMCqlXnktnB0cpJHWPHkEgFN9r4IW3hYwSavAh+30RjYPkMwYNUwwZxY+KScaoiph511hCdnrM2TnbFC0BUcUw4+oG7ycx8Ln/azrDWKkwS2MRsucwRiRQ8+nITMEXIpzol2uSax9LDNJ9YExp5ljoAtPugVMI9CpJhf/Qq1jtdw+GcPVisKWToIUcP2FPTRFYFgPHkiYvxLLk0wj0JEwFZ1+2JNcltoFhSw4sllA4YP3f8zhDO/MKdkw9a0zoG0aDDE21P46fjmscAx2rD5eBuJYS6Fau9fs6CAFU8uGzD8TxsekhY4oq/VwK/HA+r/2XDEMr9Y5cjVUDuf1jmQGg02z3xrmGEuhWzvX7OggBVPLhEy5yh+m96Tq6F2PkfmUKOBT/JbA8b5xjB/UMG2eRVgLrmaeWFra3gN6+SkEC/35cn8XAk7X4OixmOcDzZ8teH9kD+EhPsz1skaMH63hrM27aZIzS37NsJccjPzMobcFixBDevkBEPVl62pIKxP39eEeQ+f8pXI6YlcIkoarKxb17f+C0/+80OKdUHYPvxpdcWwDYe92+snc4WkwMoL299vOMGY+aVoYl0QtnsckGEbTuDT46QesuFVf+X7grB/tulDNxybYz+l17BOvgbjxealCsKw+c28wNANJ/Ab9z28hnXyPTBnvyiRZEECZmr54wafvrN62Zmj+IMC/eViktMTuUS0aDB0vy9tzrio+akl+a9djuM4juM4juM4juM4juM4TkceHv4APa4U8/FY6EsAAAAASUVORK5CYII='},
        filter_mythic={width=119,height=44,data='iVBORw0KGgoAAAANSUhEUgAAAHcAAAAsCAYAAABfcCe+AAAAAXNSR0IArs4c6QAAAARnQU1BAACxjwv8YQUAAAAJcEhZcwAADsMAAA7DAcdvqGQAAASiSURBVHhe7ZuNVeMwEIQpgAZogAZogAquguuADmiBFqiBJuiCYribkUfGykpryYkdO+h7zy/R/mglT+zIdnLX6XQ6HY/v7+9HbO//BN5/0CZ356hAy/tBUgsEflDYOqDAiwr9kemisF/1/yLTLon7IQd8HwprBrl/1Y1h9X0ynRTeX1Rg9qeuf7O4Xr+vCluH0+JoX0Rg9JN8YllHrk3hOLDxOy5sMhs4Pg3V4OXNgdx9HLkR2M4SGPlv6mpk9YkUQN0vDSEgsyG3HyLwLRYX6df/zj0F9kUCI88IS1hHIZuBss9D9R/kMpT2A4FvsbgE+ddZLaOIN6kmgRGfFZawjsI2AzU/VH5ELsPMfjhL3KvhTYrAXyUw4orCEtZR6Cag3oNKJ8ht8PYDfLcpLkGMKzD8rrCEdRS+Caj3qtIJchu8/QDf7YpLEJcVGPZZYQnrKMWtqZAEmJ8Gb5anipgioQDwxgRfEBevf/he5gDa/C4NY8hBXwjMU8wj8N+r5ju2zyHlB44FGz/E+X7grBKXIDYRGO0qYQnrKO2I4n5yUzML/G/qKgGuZnFhp6jVugjbV2sniA8CczIyVcE6oSDwaiokAearilsL94m6G4G5SVz0wZV1cvlWyfniEuSYVegcrKOSNyuueFaXAbSrxUW7eE1cwWXEXcJvERf9fKnLAEzV4iK3+aCZ0MU9JRQAl9wP6Gu8QYFmlbh8P5gWc7viTmntn8ztB/nvGYtXV4jpXNGsGjtyxjtYOdgntuR2JcxPsHE1/YrN3vFi0pBugY9L7dpLHXOZMIV1VPJw4nJeChuB7VFuwzQezaqxq52FtRTWRs2k8OoKDH9cQf8acQns2csj2hVSNXbEex+U5Y8FkVw1KRaROQH28dqX8TIbWEdhbk2FJMC8V3Fn6+Dt7Nj5OjSzmPlV0zIptMeH74RtuQKMl8vAOgqr2ilTYO7iLqF1UrDFn80kwhLGh8QMrKOwuZrmGSds2bOGOLy46Oe6p+UpsGcfMjNeqQbWURjjkjPAlGkcgYm34rw7NocXl6idBXXWW1DVwnilGlhHYYwrflIJ/HGB9oDNvUQATeKC5A5SxMuBb3Vx5+bJWtgueymksCoYr1QD6ygsgPaS+6c5jLiwmV9glIhz5PhkMsSYU7wchbQcuV5cDWY/XFPcYt1Gckdu9kF9jjhHbzwx5hQvRyHV4hLWkX0J+xEXpnNukk+xkwKoN3c6D8Q5cnwyGWLMKV6OQprERXu7BwelSZVgvFINrKOwEdiKC6spiPOepZbErTp6OWbFX11cgj63eeRXmlQJxivVwDoKS4DdFRh+3h1r2kER5LoLN8IxK3YX4hLY139YX5pUCcYr1cA6CjPAzVVfchpVO6xs8bpIXAI/d1T4YfoQnkI74/C6G3Ej8J/3M5sjwAkO08ly3Il1/DMCCI/hOgdk5qgdT3+dHQHR3rTxj1L8XkqOQNrop4Al4H9XeGdPQBjvVFtL/77dI+eKy3x11dkbFxB33b8/dpazVFzkfWFb9gissw1LxEUOF1j90mfvUCRszxCMzyl5pyV3B4b/0eHdGa6ou6idTudmubv7DwiIO8uNEMiQAAAAAElFTkSuQmCC'},
        filter_secret={width=113,height=44,data='iVBORw0KGgoAAAANSUhEUgAAAHEAAAAsCAYAAABSblf5AAAAAXNSR0IArs4c6QAAAARnQU1BAACxjwv8YQUAAAAJcEhZcwAADsMAAA7DAcdvqGQAAAQSSURBVHhe7ZrrVa0wEEYtwAZswAZswAqswA7swBZswRpswi5uMXr3FwYuHPKAZI7eH7PXYkGSL0MmA+Rxzk0QBEEQBG2+vr7uOV44Pjj+fGewMh3SPZF1a9WD34RgKHgfU5hO82Bmgt/C3qYRIogOEIdnvUjzYdltEN9ZIEaIIDpALDbDl2W3oeKb1RkhgjgIffg4deU/rKiN6UeJIA6iz6f15YIV1aHivelHiSAOUBrSrLgOuodJngfjn5z0mm+WEBb8B84aiN+UtqKgA/rvVf19iRXXQdcK4p1Jh8DOE8c7x2bgJq1Z2DOXp9aZ0q9s6kHbYHbVMcsXgvTLVLpFWpOk/iCth3KxaUVZ0HX5RX6130tY9S3cqDozVblJu8CEOiW7YXAJuierVgSZgpcNRoUUyFI98jUWyW52jZxufAHZQ36R7RdEYeVZaMA7p67dGDV+snIc6rxY9R2UaTPiUMdd0Aripw5L7kg3X4F22C+yfINYcm4NGi1DHq1KE2lTxT529yHvdirqohrEFqkBBkkXv7h2fxP1KSk+iZdYQIuzUcpkr+eNSaiumVogr3c7ULgEkUs3v0j6BlFwg9OfKvQavHezUvJGt/BkexlHSHY5vMIliJ5+cekfRIFGT9rp3RvqbAJJuvhWU/YsDZfVe1H2noyBri07C+X6JWUzASNbEw/NHF85Uvukm2qUQaPxUfVyD6erXzPkFdtlkvNg9I5Dzh9+M1XHqsuRLGjeTLJAXvEzaZKiPUH9w+tTtNUgqtykWUy2o9evmVq7TDIGdtK6aTJZBk16wjh77QAlB2r2KHuV5ijoi501t7+Et19rau0yiQ/Y02ei+lkDzSBHx681slWzV5xc5WgEsfpGI3H1y8wmfiyIAputaX6r08/yY0E0SREk/28QMaDx79C4gs2hIHKf3djRQm2z6jsoc/mckt/88RWZq19rSu0SJqmDbmmcGsOh/T6Ng7nZXmutlhazdl3i1NsjrF4W2jQ8sZFfJqli8hKn/ZoptUuYpA46988EjapuHFCe3SwgP/vLCOerLjHIPxREdK5+zZAuBhHau2SI3IJIY1JHch5eFBupQ3Sekt3MD9doEF39miF9eCsv21byXYKI8U8zmSDdvT21YnFWjbe8HlyCKLz9Etg8/B+nbFvJ93oTN689N/NYVy3Ocn21DfBsxxTw9msGu63lWyLbVvKHg6jOMXMbHBy+fGKv9VPU4SAKb78ENg+9jdm2qjLHoafgEuqpQ6sDL+Vd+7HGzlnyZK82EcjhGkRBNVe/BPaaD0e1rZSrUfNsTr9OZGdiVqa/PbRnTSvQz/Y1O8uOb2Y7LXM4qksH5LM9179nnIXq1/BLuqItkwZBEARBEARBEARBEARBEAQ7bm7+AieAv2/JJn6AAAAAAElFTkSuQmCC'},
        filter_any={width=73,height=44,data='iVBORw0KGgoAAAANSUhEUgAAAEkAAAAsCAYAAAApSpU1AAAAAXNSR0IArs4c6QAAAARnQU1BAACxjwv8YQUAAAAJcEhZcwAADsMAAA7DAcdvqGQAAAMISURBVGhD7ZoNceMwEIUDIARK4AiEQBAcgmMQBkehFIqhJMoiYNJ7b/PsiSxpLfnvppa/GY9r7Y+9L7aqdXI6ODg4+Gk8Ho+P7woU1haqvRiI+kuhbcCCVXsxiPmj8DZgwaq9GD6eCm8DFqzaq1B4G6jmaiDum1LsGxaqmqtB7G+l2TcsVDVXg9h3pdk3LFQ1V4PYu9JEwHaTW4Rc7APC9qlhA8ecHy9yiSjJ+wqGL09rkux5AnDSuwKSwP6lP5PAnpyXvGLAGfZAnCGwJ+9SL69cAjA8TyQWKGePq/ZJkCM5L3nFwOYK3wG/SCgvr1wCMDxPJDi5AhD64cKydxtsfy3ZAK+YSq5KaWwuEguUcxLYbcHIvYYiYPuyZAO8YmpAnmDe8/LKJQDDs0Uam2+s9eBeQznOlvAFr5hakKvvE728cgnA8HSR4HB++rlYEl6kjnMEjwQZEwl2/lc1cbH3CqHvzZKCrUUqmo86NJQEFx7NS14xsEV9H8ayHwRsn3LbViTvZOT1wgiOvXkp8CVeftiSr1mYRy4BGO/nPS+vXAIwPEskd51Si9L21BZDSmI2FUlOSxKc8MeLROPTZzl48Upv/A+RYItW/xjzljl5kbwTTQU5h3PYWiJlG3LGy83AENsfr+1yRVp0PupQeqOk4CElMfBxlyOwW5uE/Ru2sZeJ7uO2CixAp1hNJAI/tymvIC0SC5HD4iB3/+XAyiJl/SrJiuS2GLAne7EO2uUaAVu/SPQKkUtEaQwOS7qFErIiuc8p7O7bRtjdplhuq4pE4Fv0RhV+Xn+aFknGLDy5XJPAZez9ks1LNQV31MbwWmVOAjv7w7p1EguQMQt83G9A4OLe6rxw+mG/ukgEpgvigqdDx9Z0Yz99xd0K/NAkSIpDJAKRvDVh9B6sOUbuouwjvAtQ/Ls2Lmc45wR3BMdopxA5YN/3bxlQ4BJt1b7no7kiMV6p9ssCIu3/hx5TRULcHVsbv9CbIhJi+m9nmoDFYrui8BsFwxb1ZxzD9oGN/wGP9dDBJpxO/wBE6iojlRTS+wAAAABJRU5ErkJggg=='},
        varesco_b08={width=157,height=32,data='iVBORw0KGgoAAAANSUhEUgAAAJ0AAAAgCAYAAAAIcnp9AAAAAXNSR0IArs4c6QAAAARnQU1BAACxjwv8YQUAAAAJcEhZcwAADsMAAA7DAcdvqGQAAAUxSURBVHhe7ZyNcds4FIRdgBtIA24gDaSCVOAOroO0kBZcQ5pwFynGd7vU4gnEHx9AUPQl/GY0JPEWuwCM6IfS5Oni4uLi7+Hj4+Off51A+47HGx6vuHyWRZEB3594fMdl05f0eJdg/9iHuYvxZDQfyyMhswRqvyRz61JQ/npTlZHslLkbIXwE9P2JQ3GT7PRl3+rm2+NN2D/1wfnUxaefrFcLH2emoPbwTUdw/pC5G3H4Dr7Kztjri/589nuR3YoJ3tmmI7iesvjw4SuBEfJImhmD2imbjuD68LkbafgOVhtvli98vsjS2OsdFqLkg7Zdi4/+fPZfEfJIKTOA2mmbjqDt0LkbpfAd2EviLF/4vMvS2OsdFqLmg/ahxUe/bNFJyCO1TILaqZuOoP2wuRu18BEYLNvZvquF2OvN/ls+aeYW0BcXnYQ8spF5+qYjqB0yd6MVPoJsp/rC67dsF/Z6h4XY8kHdtfjQVRedhDzSykTtU2w6gvr0uRutcNTiRXhpaSOW93advs2BE2jsvZ3Xe4uWTwCa5uKj7hn7/27TEWimzt1ohaOWTQ5tLyoXQf1Vul5f+5hd4Zuk3d41Wj4xHJu6rED75qIT5qiLe+xeXQrK0zYdgW7a3I1WOGrFyalcJIQc5UtGvEu0fFKgXS0+rl2LTpijbu6xe3UpKE/ddATaKXM3WuGoZZND2yHPdETlIvSTrGvBYtTd6PWBfll8HN2LTrxjR+1TbjoC/e65G61w1OJFOOQ9XQBtU15eW6i7MeLDsevUDXMU6V4Xry4F5UM2HWGuTt0wR5F3RsJbyLZncad+kGih7saoTy/MUWTPurh0KSgftulGYI4i78wMh9dR9+lWN4hHvdXdmDnGFsxRZDMTtWvTDTD9GwlhL61k1FvdjTMWvpWJ2rXpOjnqu9c3WRqj3uputHxQ+4WH600zdN+p12UGcxS5mSmZW5eC8u5NR388ps/dYKPqe5j+KxMCj3ccsp84jXqru9HyQW35w+LYXHzUw6e6P2rTSTN17gYbVe9Gg5r+ezqC/j9kldHyRq36B0nx+nAsal6Bdrt/Rb2aM5gjWU/m0BxRnrbpCM6nzd1go+qbQHvIL4dT0Lf4O7pAyxu16ZuO4Hp1S4fXKi1Qr1IGcyRzZ27oVt9Fx6C2+j1bimTucRBcT5m7wUbVM2gmWTcbvr9Z51FNK1iTTZEN70M2HUHbsvg8qsmgfulYgDmSuTNbOoL6chM+Bs3PaC+uKWFN0lPmbrBR9QyaSdaNxxfH6r9K9scjvjfH+3nLNWuSZaDmHvOITxhDCvXqmsEcydyZuGy+TBLo7RUH51wfvgeugrp9KMP5w+dujIR78Pji2PxKLYWeW94ePD6odc2denXNCHmkJ1PN04B//D7s4XM3ZobHeH1x3vzXGUNP9al6e/D4oHb6pmtpB3HdR03HsQX16prBHMnuzAyP8frifOs7V4Oe6rPrj+HxQe30TYem51tlP/BevQfsGccW1KtrBnMkuzMzPKbHF9euZzt6Sl/19uDxQe30TUfQ/O1WHQe+XTfYS+NoQb26ZjBHsjszw2N6fHHtem9HT+mr3h48Pqh9ik1H0O5+NUhB3zccum6w18ZRg3p1zWCOZHdmhsf0+qJtc+PRU9qqtwePD2qfZtMR1PjptJpRAvrstkpgdBwlWuNijmR3ZobHjPiixPtMr6zflDd4jQfvjIfbA1VvD+y/5cNMarxQr64ZIY/szYSGm+8HtepmoM3+ew7Jq0Dz8LlfXFxc/Ok8Pf0HcLxyU2WIgC4AAAAASUVORK5CYII='},
        varesco_b12={width=169,height=32,data='iVBORw0KGgoAAAANSUhEUgAAAKkAAAAgCAYAAABpalg/AAAAAXNSR0IArs4c6QAAAARnQU1BAACxjwv8YQUAAAAJcEhZcwAADsMAAA7DAcdvqGQAAAT/SURBVHhe7ZwNceMwEIULoARKoARKoAgOQRkcg6NQCsVwJI5FwfTue87Kozj6WclKqtz4m/FEXj09b6RNnDpOHw4ODg4ObsXX19fPvxno+22yKmif2N7YPtj+mMWKYtYnzZMNq4LWlZ90bDruo4VctPhb+IKtju1qedRA/oj+B9u7xp0czlHcNh3zxYbOiyWaRE/EZFmQvUh3GuHHxlQnyJtf0PHYVCCt/ilSOh6vkkcOZFqHj9MIPx7vb6d3cujWK7Z5Urbg8YuH7GJ684t1tN0F0uO/JaejPTyPLXRrHd5PynZK3tPQMznEn9m0AEMwr+RievPb6kqeMb3+MSUd+0PziCG+ex1y3lPROjmE9cr9PCnGYZN9sZje/FK6nGfMHv9ATUdsWB4Bwo+n3n2kvKejdXIUs+7h4P1hh1nx5pfTES8WyF5/4dERH5JHwPx2k/KejpbJYf+HdV2TVzvcgje/ii5bIIP8b5aHYP/Nunaz9Z6SxsmpnuY1hk2XQNbLTGpbrPoujObThi2wv7s4BP3JAhnh79UJ+nflISxchDGfbCrmiysoxJ8U51Fr8mbheSFJ1+Sw+3qK5tGTNnkWTYrJS6wT682vpAuguSiQEf5eXQDNnjyqZzN5mfz/oGFyipc56He/IkvHFPT/MmlLftXiCKB9tmFD/L26LWh78ihe9qN//nfGVhomJ3uqp++Pydx4/WgPLw6BfimQEf5eXQr0TXlYKEms+6/wTA7N4uUOdNXT/BbGFE/7JrtacQjG6Drjbn+vLgdjXHnQbFoHby7Bf1qck/NyimRp/v5XY05D03Ds5Q8vT36ipCvBuOzp0+t/qzxo1uZs/fggvLkE/2kpPRHv5CxGjTDMVfie/ERJ14vX/1Z50GxaB28ucf5TUnoivZPjgWFHkToJ/jSPIt3inRyY+nRPn24T1GWfJhr8b5IHzaZ1KOUSE/ynpfREosm56z+cpONB9xw0FUiLv8munoeFkqArXn7K5Rb7T0kucREnT/tuL0EFHc2mAmn1Fx4dzT15lObt7Nu6LfQnc4v9p4QEdT9nkjh52nd7MT/WsesukB5/r47d3jxq6/Bu0gvoS+YW+08JCZZemfGk3u3XorFOEHIVSI+/VycINefBrmcd9DOdi5/oEJuzSMlh+VkB29nNBnoSbE2vSvazBR1AM90NJrEuQLhaID3+Xl2AcFMegv3qOgh0Wt9XHovfam39bw451P4izKInZTYL7N/rrXrJRaCrWCA9/l5dDF3uPASh6rtpC7E/u8plffOivdxNZd0LhIdoVujvLlK4uLTEge7qpmcR67bQnS2QHn+vbgvdrjwCxIpnwRZif7UtvGV98xilWSHYXaRmcQZhTabrdNMCnlqgq9/vmQJJskB6/L26FEiqeQQIZ4u6leDPo+4zTaJjjdScQbyrSDHL3pNI3/Q/xIuJdTmQXSx6j79XlwNZMY8YuqQd8YvdxZ9msVZGas4g1lykNknJogmof9AEDf9J85ZYVwLpWYH0+Ht1JZBm80hBv+eKSZbgz+P3vJMSfLZ+F+j1WaJYoDFop/rnECliXQ3ka4H0+Ht1NZAn88hhev33lOaPYrG/2hbecr3PpIIOPQFdAkr+6xVi+k55uVxhQ5ph/Lf/mx0LXxDrPDBkKZAef6/OA0Mu8vCAfrk/lS25FkKe1i/deosfXTrmbf+6Pzg4ODjo4uHhHx0JHOY9OmuWAAAAAElFTkSuQmCC'},
        varesco_b13={width=288,height=32,data='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'},
        varesco_b05={width=346,height=33,data='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'},
        varesco_b07={width=295,height=42,data='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'},
        varesco_b04={width=335,height=32,data='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'},
        varesco_b03={width=347,height=34,data='iVBORw0KGgoAAAANSUhEUgAAAVsAAAAiCAYAAADxlXpQAAAAAXNSR0IArs4c6QAAAARnQU1BAACxjwv8YQUAAAAJcEhZcwAADsMAAA7DAcdvqGQAAAukSURBVHhe7Z2NsZ04EoUdgBNwApOAE3AEE4Ez2AycglNwDJvEZjHBePYcOFAIdbdagvvjV/qqqHtR/0lCNEJw3/s0mUwmk8lkMplMJpPJ5E/n9+/f/8H2z7+C+xJNJpPJ5A6YWJVjC1D+Qyr3swXF598quhX6lf/9qrHFtIDsv1Lbrjz/Q/FnFaXI+u9B5ikYQ3X/S+bd0FbuUkD/u0xdpJqitw0y8/hKHfrU/iVYL/lzjzPZ9Dyu2j8DVOMb6vEDm9l3LMf2i3XF9kVmkwbqPhOp3A8PkmLwwN2acOlProuBe4x5BrIi2aqsK+Fm/fcg824YDx9LsukBdt9XDzmg/0umLlLtJtOGVdPlIckWXz+vJSHmuIGPL5KbQP6PVJ8Own9mG1mHtTY5tn6ZtFGXeXRN7tLwACnAAvZvSbjwUySL40A4xzwCWZVsCb6nE27Wfw8yH4Z1kqsU0P8l0zQydZHaMFEbpOLxkGRL+F3FJl6dUf5TKiaQP+ROrwVCf0XsriS74bV1UqMuM5HK/fAAKcbO1YEG+2ogHweCFXMDMjPZEuynEm7Wfw8yvwRip9eDZNIF/Ie3/FK7hNcGiT0elmyxy1lgKzkVYwb6bzmrRdz9TnCEY79MYthX6rYClD9+zfYMD7xUuoCdOWNgHKm4MQlkbrIlKGsm3Kz/HmR+B9/k0gV17Fqv3YBduG4rtTuo2qByj4clW4L9MElB/lOqC9yXyIT+pPo0Wm3IAB8z2XbA/sL2vLcRGECxKiDrGnTQdwfxsSGNmGGyJSgPE27Wfw8yvwziN2dN0Olar92AXZFUzkjtMlYbJPJ4aLIlrJPEJpAvD4/4qSIT+lkcPhGE/bpGv4bVL5M3ggdIx8oE8lTChV5rtnBbsiWQuQk3678Hmd8C6hD2KeRhX3rALkwUUruFcxtU7PGMZJua3eKztRa+1PWZoE5Da7RnrH6ZvBE8QDpWLtC5nByOAyGKCVkq2RLIzYSb9d+DzD2WExSfXD/8G1trlhXOQFv2EbB1X/+RiselNqjYw01glK0qNlJLkahzKyE3xwbUivpmbCJaddqA3g98VP2Ici458aEa74aaS1STF4KD1Ey2hINCJgUoT83CGEcmYUzI0smWQKdKuFn/PcjcozgJsM+ExXqZUCbVCsjC29wWsHcvjFLxuNQGFXs8JdlC/dtqNYxbzw3qrKor6IerydbtYyJ5+IwiC/wwKZvv7DIONp7L6YQNXY6R79j4nm91oUPZ8q42vlb9umqYLLqw4wV/7xt+ly9rcvUFW5GHsM87GPd4Qm7eZbFcKiaQ/4Ut6kP2BeteT3pQ2ExoG3QiswXsp293GUdmYUzIupLtBnT3J/FZ/z3I3KM6qK26S60Cds2ZDnTcGRxk7qxZKh6X2qAiD3fQU7aq2EgtDeo8tFRBO7kIgeptyRa2rfXjWxItfHS9TkZdbK272d7nCsUYUJkF6+rmFciKPsF++DDZawfKu5ItRKxXemyZflCYTmgE+kvl8ZlOtIRxloAgignZXslIzwL6S8LN+u9B5h53JtuwXyHnlTMajO66rVQ8PkSyhUnoL8Ct4xHqreor6KMrybZ1YU3VKQIxuPwwBGw5zqyZZNd5KYq2qKwCvsOZPqEOfeAzexdYzdZhm062KOvuQ8vPUMd5FY1gHIUMYx4rOVg3TvNT/nuQucd5IF1ZRggHG+S8bWudpOZsSDKPS21QsYebNChbVWyk1gXq1jU+od/89d0jQFz3JIbs8lsRkf8s577B/ugyVyrZZkE9eKuemvBBr+pLlKWSLfZHLiyVn4VRZ70wjkKGMY+VHK0b7Nwnzkf/PcjcYxlI+GSCGn5ABlHz56ew5cWk9R6uue4mmcelNqjY46nJFmZds1u05SV/UwBx3YsCZJcuAHAxOsOvQF3297fxfTSB351s08siBPrnJdBmssXucB8e/eyg8MMl24ij/x5kfhdeMmw+4JFqWB+0ceRXXr0UbVCZx1OTLeFxlosQ6IVvhjySqI6Q7efLCLBv3o53stwtZfvV4NZk2wvqfZ6hN5PthbYWfnZQOJNtAplfBvGjJYRw1nDqm2j2bsaQ+DKWf4k8XpFsU7/Cg97L/lIWYj8k2bbaDjnX/Y8PlPk0PzzXIN+e1UR1LmaPKOJDJd4l8el98VPy1cIGustaMT5Zr8xFYxlf0A0f2i2BBXTDZIvPVh/SvphwoIxLLGwzf5lWHz8WLtYGdIgtuy7CTk0NHn5XcQV9SK2lx9csuq/eR/89yPwyiO/+/YJWeyA/9mHraXC1bqvyy1htkMjj6cmWoJ7h2KVcqi8B8aPzZXgZAbbReeP+9h8y91nAVh98mn2KcncSYSGzCvgp1lex33pj47w84B5zyI4XmFayjfpwbNw0nG6BW4M2c9W7O9kyVvgQx+LovweZXwKxi4FxRmoRe9KCr9bMrUpwKr+E1waJPV6SbGEe+kZbXjarJYj/kAdksI1+JWc+PN2ArXk+sZxyfHX7lHXGxlksk7Z7zMlqUUN7qewwtsQWRXuwHy3FHc+fVrId7kMXOM0mPnNgoHw/+aiv4grGkVpPzKYevnYl3KP/HmQ+BGJyELozWgK1MDH0gnjVbYxEQ7TaIDWPt0y2UnsZ6M+HvPoFv2EiiYCOewGQSqbeO9D9ia26qElcAd3qjynRh8QVUtlhLIksepLtcB+6wDiV+Aj2i07mvkQL1JeognGklo6Z1cNuOuEe7XqQeTeIl7odjNo6gtVOibrJtEGqHjPZGqBfW7fIHNPdsyge+9VDiTUmzkCnmWwJ646NiTT7VkD2gWo1VhDDPDdQbrZHYos/J9kSlC0Jl58q2qH+YmjAOFJLx8zqERSlEu7ZLovMTeCTgy5aammeMKyXdG9DrndUbHK1DdLxmMnWAX0ejlnJuxIubB62jOABFT4Y4jvgUfLdY2vf4l2S7euWEY6g3Fzror5MKxhHaumYWb0NFDcTrmWXQeYey0HU9wrVab+y4zvfpy0GFfUeQE+MS22gTkBRjyOUrSo2UhsC5n9Csk3dkkOPM86qH1HOtfsl0eFzOT74Hp03lx6QtYBq9K74cfx4WG18RbKN+vBxD8iyUF+mFYwjtXTMrN4RiMKE69m1kLnHchDhO7oaViyOAb6GSWEU9p9CLKjY42obIqoTaIOyVcVGakPA/O2TLUGfd72g77Edb3w+8tWv7ReaTPDFGr5k0dsA+3hUkcW7JNvnv/oltRTUl2nFMXg2ZlbvDMRuwo3sImTusRxEfHb91anFMYjaeQX4LWYjKva41AbtesxkG4Cq3HKx5TiSy/BcHGS5dcbncF1Rp/3hl4os3iLZEk8ng1k3FH64ZEugYibclp2HzD2OBzE9S5EJbbpmkz0oxIKKPC61QbseM9k2QJ+nn/B7wMdx5nhLAifwe0ySV5LtPhNWkcXbJFvsXmlrXTevIcRrjIfXAMI4UkvHzOp5QK1KuBk7C5l77AcR39MzQ5m0fJPiduUIZauKDdqbGeDkkW34MMkWZoXP0fFkAV+XEi7s93OMYN99syALfJzvjoYSEPwU7w2r2OJtki3xYrcw6xY5Mw0CqC/TCsaRWjpmVi8CqkXCzdqdkblHMUAQI/wRyIZ0Wz9OYJ3dl+8hDv94DWwzt25kuA1Eux4z2SaBS675Da3hwq5ItgRlwwlXY6B48o790WRbrO+q2OKtki1BWXcfmnVD4YdOtgTqe8LtsTtC2wBrgDSTlfTCn91C3vwl0dY2C8j2mYmKPIbbQLTrMZNtJ/Bb/OfXDLSReQFEXQmcuti8Xwp2JVv44c/qi0RLJLZ4u2RLIGIfuvntjOkHhR8+2RKYLAm3125jjepiJhOWI17x4je/Y+Ma7faaTrheS/vFWQB03Csv40ntYW0gq8RlJttBEIL9z8TLv1NSJUyUbf+KhTrhz4+hTl+X/y0OdTY/2Kw6sZxjMlr+8njLZLsB+fi/xZlMJpPJZDKZTP5gPn36P+T1IXZnXHUNAAAAAElFTkSuQmCC'},
        varesco_b09={width=221,height=32,data='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'},
        varesco_b10={width=389,height=32,data='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'},
        varesco_b02={width=342,height=44,data='iVBORw0KGgoAAAANSUhEUgAAAVYAAAAsCAYAAAA+YZCQAAAAAXNSR0IArs4c6QAAAARnQU1BAACxjwv8YQUAAAAJcEhZcwAADsMAAA7DAcdvqGQAAAxASURBVHhe7Z2Ntds2DIUzQBfIAl0gC2SCTpANukFWyAqZoUt0iwyT9F7qWqVEAgQlS35J8J3jY4m4AEiJgvVjv/cuSZIkSZIkSZIkSZJX8/3797/x+vZDcF2mJEmSZBYWUdXTDWj/LMk1PBLj/S81PRXGVfz1U+KRswds/0j2+KT5F81/qClENP4Mcg/BHOr7n3Kfhr4KFwL6T3I1kTTE7BjkZvGBGsbU+inYL8Uz9zN56CzO+j8D5Zme4xEYU7F/qOnNwj46lPlzBPl3keQa6smF5acWV8ZT6M0krXPugW1TWNU2NfGi8WeQ+zTMh7fpiQG/T0uEGNB/lauJpNNExrAoTS4prFj8Y2lx6c4bxHgvexfYv0l6KUrHfE8troylmAU1v1nUTYtLCit4+ofZCiepkhSw/pTiijibwsA8MjU5a2BrCivBcnjiRePPIPfDsE8KFQL6r3INI1cTyQ7jjUESi0sKK+GymrtYfUb7F0m6wH7JFdwepSsg51OKK+K8V6wVmW4FaVnceeXzeJnbdOmlySWFVZJrwGCbieltgAjwbyYt88jsHgywdQsrwXpo4kXjzyD3UyB3+L6OXKZAfPeyXbJTWGOQ2eKywopVHrzrgwmDzZyB/k2crRKlXEHuU8UV/t1bSDLfCvqyXrESrJ/6YD4CcyrGBrTfc491DzeKJFPAr3smwDySmDkJbGZhJWgbTrxo/Bnk/gw+KqQJ+jh1f/UB/Nz7rJI9g2YMare4rLASrG8O4D2wf5G0wHWZujCepJejlBuQ/1BxhZ85byS5FY1jBeu3F1bCvHjd+60AJlG+BtimJhj05oStBzPI6RZWgnZ34kXjzyD30yD/8GwImqn7qw/gtykgeyQ7TW8MMllcWlgJ+yRzF9jfS/dmzlaJ0jagH1PFFXr3w1iy20DKD0vm/0EfX1JYXwIHq853gT1UXKEbnQU8rbAS2MyJF40/g9yfAvrgblPY3W1pAT+3KEj2FPZjULPFHYU1dNaK99G961sPYuXsgr6Giit0wyscSW+D21upV9CWhbUGmtOFoN6oXk7YQoWVwN6deNH4M8jdoux4vPN+3194jc6e3DPLkb8HfMuZWQ9JLE6NQc0W5oFB2yLpI1mIQJ9HxXc4NyDb9Dfi46EwJog/ujoL3TaS/BaQrvttDfQ1C+se6LrFFe2hs6t6o3o5YQsXVgJNM/Gi8WeQu8Vmx2N981WXPbRJ2gCbe6k6Av7mh6AkFqfGoGaLWwor5B8Xr8MMD2BqFukCtsOlhZVoP/ROIML34uVSUFMD4nULH8coyYZ67JbGo86nJosP0PKbDl/wWj88sfwvY2DR++AZ9t0Cmj/x+tyLgTbm/ooXT0Lakxk0hgorYRC5FbAevmRlHrm5OWGbKqwPoF2fiEfjzyB3i+aAHPVdsgb4uWdVBBrzzAw282xYEotTY1CTxS2FlaDPh2430E8hXCC9vbAS5NkUV6yHiyqRW0FNDYj5JgsrdJEr4u43Yqx+sV2SBphZyMPj6cZCY7h4EehLccV7uKgS5ikJgZcTtnpnzfatbNxo/BnkbvHMwupuV9j5KWlqYDPvs0pi8UsUVri48RzMPtZQt8gXsI0OzacHChMCuUpxxftUUSVKV1BTA/e3JBs4Rkk21GO3NB51PjWdAvGa4hrpew3aP0sSphsLjVPFi1id9WAepXRz1p082DeevofizyB3i81BifUztwJMPwL7J7xGZ7XdSyPZLE6NQc0WtxVWgr5NzU/oh79auwp1IYy3TzyUrqCmBsT+2Qtrc1xF+v6A/ZF5il6sw8FmYR6ldHPWnTzaN/iZT37r+DPI3aIUDryzGB1+eAXT8Cea8OUHx+iMpftdWdksTo1BzRa3Fla4TZ21YizmA7+rURcuR+kKamrAdvipCytBzP3tylBhRdPRK50mVoGDk/1SmEcp3Zx1J6/oWx1/Brk/C6vwDR++SOr2B2M88uuoWTZjUJvFrYWVcD8rhAt07jc0rkbduBylK6ipgcebJBusbcl2ScLbu6bOp6bTIObm6iPSd3Kk/w/2sQpozMIaQO6nQX7vNoB7f2e3bbyz8m4OmU/Tiy+TxSsKa+g+JHQvO1sl6sblKF1BTQ3YFocLa43MDVZ8IkkX+PH2R31F5T6HKAFFpO9YdueKYmxOJNDGb+/wIRd/1dWOi43FuwMD4hV6SAUdLx/Nqs88SjnMKdlIx687TN9vquPPIPfTIL/5e/7ReGCvt+Ho11nNfVa1n6Y3Bpksbi+sBP0cPQh86dkqUVe6BPZxATrOG/dqR+kKampAnDdZWEEzfxDL+6HHqo/0nf1ScwNsx+bIIGhJzuBq6gL745sCdxZW5nIfsPSo488g91Mgt/kdUyKZRz1hRmdkzWRU+ymsMchs8ZLCCnc3Nsby0rNVoq5Y8IxodDbF+c978+HtqKYGxPppCivavA+S9ewy0ncse0Xa/I6sCwerAA275N3LVLSvBxr1am5gHslmcg51WJwqrnX8GeR+COT8hpd5pkogcw+MWZCvmcQyHWI0Bsks3mRhleylqCsWZbtxu3P7q20FbaWoKs5vVViJbA11nkjfI5pp2AnFadgHxvrmaz5cl6lAvUwNzCNZOGdUh9Vwca39ZpD7NMgX+iqPN9Yj9MYp0zSRMUhqkYXVQF2xWLcbljdzXMvr2RSWs7CKOk+k7xHNNOyE4jT0AqOtFFe+q2mF+uLYgXkkC+eM6giaQsV17xdF7l0Qkz+1826XDC8n2C9pn4ZCr6i5y9kxSGORhdVAXbHYbDeslznOF5fVXKCWDhaSFdTUwP0vyQqaza8AQt89lmRugP6tFtbX3QqoQXv33hT1cm1gHsnCOaO6B2geFteeXwS5W5Qdr+UG9Wm974Plck9MqwXqLmAmx6kxUOOw6UcNbYukj2SHgPsvVVgJ2rjdm4OdWjpYSFbAvvS+o7yJDa35AM06lmRugP6tFlavzlz38CoK9XJtYB7JwjmjuhqY3OJq+Y2Qu0XZ8YjtffI1lMAAi+5BcRRuP6UoqNni7Bg8srAaqCsW5nbbQ+3i0keygrePacOrnDjh/dBfA5O5gXq8dc8AF4XJ1YX1/q9bSRaCerk21MmjOaO6PTCbxdXz85C7RdnxeJ/660olMPDGeQbE3dwbVbPFqTFo1SILq4G6YnFVYR3+oZ8I1rGEdveqccdj3nl0t4NsDTyeJGFfhoWVWLoI+1gFdkL2hq6Dg9c55pEsnDOq6wFJt7iO/CzkbrHueMR3fwpaIxf6TJ0lzqAUBTVZnBqDVi3MAkHbIukj2SHgnoVVSFbAqnnfdAbrWEJ76LvvooxRyxbd7SBbA/JPF1Y0udvPo7sd2AnZG7oODtYgCPNIFs4Z1VlA1hTXiF8PuVusOx7L4TM+uYxik81lSA1ti6QPxrt+RUpNFleOwSwQtC2SPpIdAu5Pjw23Tcyj8+mBwliY220PtYtLH8lW0G/z2IpijZ1zTpIIZYxatuhuB9kaODZJzJrU6zv9ZJ6iF+t08aqhXq4NzCNZOGdU5wHpprhG/fbI3WKz45Ej9Ikt7XASQmN+kR1m9+wDvus/GFSTxeExEK1amAWCtkXSR7JDwD0Lq5BsBU3us4ga6LpXMN7YYYv++b0yRi1bdLeDbA3Ifaiwkol+r3RjsROyN1jJLaiXawPzSBbOGdWNgHydRDN+NfR1aHY88gwLk3TuzxZhj/zzQfMAgW29z6omi8NjIFq1MAsEbYukj2SHgHsWViHZBjQPiyvs/HHCVHF6AHvkw7mMUcsW3e0gWwPyHi6sBOZr/9C1l7yH1xnmkSycM6qLAJcyiWb9HixZTawdzx20/3cS/AUT76mWy3stm9C/BHOAxvyUZT7JLhsDWSwmZoGgbZH0kewQcM/CKiRrgInHBZ9s11d13L+cU+UJPse4WLawvQRxgKyZPzvKGLVsYc3NLsh1qrA+gOb4v2ZJkiTxQOGYvhWQJEmSGKB+mmfCKKzdv/ubJEmSGKB2uvdgYVsfjCZJkvzWoCaWhzN48RnGR7xv/moZ1vmvpiP/nsf9i21JkiS/DaiJ7oOuCCiqeX81SZLkAeri6cIKwt9YSJIk+eVhUVxq4zFwtpoPrZIkSWpQGw8X1iyqSZIkHVAfpwurHmSZf7MiSZLkt4dP9PH6hBd/FWX+Ogkv/gIr76cmSZIkSZIkyS/Au3f/Ad/k8396nXlfAAAAAElFTkSuQmCC'},
        varesco_b14={width=192,height=32,data='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'},
        varesco_b00={width=224,height=32,data='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'},
        varesco_b01={width=196,height=32,data='iVBORw0KGgoAAAANSUhEUgAAAMQAAAAgCAYAAABNc9f/AAAAAXNSR0IArs4c6QAAAARnQU1BAACxjwv8YQUAAAAJcEhZcwAADsMAAA7DAcdvqGQAAAdRSURBVHhe7ZyNkds4DIVTwDZwDaSBNJAKUkE6SAdpIS2khm3iukgxuXuPfuSIIgiAMnNnz/ib0dgigAeSFinqZ/fDixcvXrx44fP79+9v/wB8flHRVqgr/W/cx9c37ge8lWAD2m4uLtP4DKjrR9YX2zu2X9LskI0b/djGlpNlN69rMH5VB75/Y/uBrauLBXw+3qKmfJbrFGiY/VJhPeT30H0xcExEARVvQRUqMI+Kw8Ydfc/A9kNuJswp12UQy4HwLqlVPkkmbF8E4+/VUaw3sUxB7He5mcD+l1ynwOejfB++LzrOibC/ZVBA56skC8wj0+VZHhruDwH7L7kuw3ZL5ioPNSAI4jlTlgPzDMp/ym2AcXIzgT3sK7k+RV90WIlQdtegQPwwizOPzAXsdwPmzNmfWLpHYL9Ub8SFM16ChxsQFbavVOwAytz+B9MZFbHR7/BTrk/RFx2zRCi/enCZncU8cmmgLFqHtsrzu4pNqCXXZRDr/sBJHnlADDM+yqLriNaeM9STjwnsX+X6FH3R4SWCbWlQwH96YDGP3BrUl9mEenJ1tQm15LqMJO7lYQcEsfpHJpNahzMwhctdxLalyb1tqPW4V+cItObHSpTIDT4Av+iANTsY5eFZAps7m8H+LrllIu0FHn1ADGdQlE1vINAmtw6YPt885si1cG8bGL9D5wi05quJTCL4uIMC9nDJwTxy76C2XEyojS268zM9vUcw9iZhg9xcHvAg6NbUKOdA+oTPr6pjalaELT14szrMjS3zG3TrZ0+fyK0DMd9lNoG9a5+X4+zrkdXB90t90fASHYGfOSgyyQnzKGQANndN6oHYdKdaQCIaEP5FmAHbqvCBlfqu6qAsuvvTPV/Avtt2MEw0yBFdP3S/82obZqzqoGypLxpeojNMorAC9lODgTCPwgZgjn4Yj8tnB4J6RRfrTzMgiMwm1JNbQyaTVX/R/R5X2mBxRUdmE6ttBS+RBfzLoMBnejCQaQUE7MsPxBij8LuQnAly8H597qGOYFtv0WsovOHpzNouswn15NagjswDsLXbpwRF4cQl14bXBg+FNzwdtkFuHTKbUE9uPVcqzAroa5ppBQRcls8S0IwftCTI9AF8OAGErzSQjJ6FwhueDmzDQYCy5WVCVFe5FSLfSZ2epi8KVyu8CvMo5RQ2TO4h8G23ZO8Fcm/QS1/HMDc+pks1tvXmuYbCG54ObO0gwPfLF5Iodu8aUVuu4e8D+/DKB8qepi8KXqKdMI9SToFb+iwxbdBFoMeOdG8Bn4E/X+4bzlIo++MHwSrQMh9IweQ+V0Bce8imIo/lM9AMhTf+i74o7EzkwTxK6QK/6Ts2FfhsOzscgTTPFEvXRgQx3aBgW2VaQuGNqzoTpss95JmeHWEr1xH4mpmsrPfPnqov3ESwcQZMHSDw+0J/7Q4wj1K6wC/zJuXWs8MZ6mP7ji19xjjWCd8f6iCATndxfAb26bMF2MpDLHxG756Zsy7Kn6ov3ESwlbUZPt1BAXu983T3gCCBzh85O8xASj58y6xJ736hTeGNqzpHoMHZ371LBnt0HcEJwj1zw26+Mn61DQpvXNU5Ao2wL9xEsB0vVsxZBOXt2QT9VTzAPHIL2aWzE6TmcipazpXOZh21P8C2FcEEnk4GxLt/11CBX/QsJrpjU3wk1+G1AbaH64ulCmO/6xjuy1Sgv0wDzCO3kF06u0H66MW2cueJddT+ANtWxBJ4OhGIXbolDf/p8hC28A4cfMxlrNcG2B6vL1YrjLIyKPipogb9S6AB88gtZJdOBuiVlwe164L0DzMgYPtFOz9V1EGbZFLAf/lmQoV1kMwA6yG3Adgery+CRGaFUT6bDZ5uQECy3T2BNl/S48Ujrxu6NqpsWi9R7l6wjtofoEYRTJDRwef0Ypfx2I4X+7y1PPvtwmXRDMROr+tge66+oKNiBmBLV5jQX6EDzCO3kF06GSC5/ITcITxDZKht9HTYR/JZen29ap9B+eW/GkSsef1AmE9ul6j19XRg29cXmURZ6K/QATP5hF06GSC5bUCgbmXGYR1VdInaRk8Htvbb4PvKU/Zp/8llGWiaZx3itSFDra+nA9u+vsgmykB/hQ6YySfs0skAyS0DAvVq9+FZRxVforbR04HteBCklztV2wK28KGohcJNvDZkqPX1dGDb1xfZRBnor9ABM/mEXToZILnrDNGefrKOKrtEbaOnwz4qyQT2UzNj1baALfrHAwOIiR76PVdfrCSKoL9CB8zkE3bpZIDk3QPiXCfuy3SJqufpwHY+CFLr56ptkdU4gpj2rpMF88n1ErW+ng5s+/piJVEE/RU6YCafsEsnA/TCp7AzEMfbfNteaKvUNno6sA2/DcrCA6Fqz5BbGuZUqInXhgy1vp4ObPv6YjWRB/0VOmAmn7BLZwVI80k038fiO0x8h8s87crGp/bey3L/y0FAYGI7+HfeXR9yHxvr7b66AJ+lyUFhU6D3tH3x4sWLFy9efPjwL8a498bnjU0jAAAAAElFTkSuQmCC'},
        varesco_b06={width=333,height=34,data='iVBORw0KGgoAAAANSUhEUgAAAU0AAAAiCAYAAADbJYv/AAAAAXNSR0IArs4c6QAAAARnQU1BAACxjwv8YQUAAAAJcEhZcwAADsMAAA7DAcdvqGQAAAurSURBVHhe7Z2Nsdw4DoQdgBNwApvAJuAINgJncBk4hU3BMVwSm8UG47tuTkslCgQIitK8XRe/qqkZAQ2AlDQY/T3702KxWCwWi8VisVgsFtf5+fPnf/D6+3+Cy3K9hY+uv1gsFmnYoNSrKmD/LsmjfHT9R9gmhfc/ZLoV5lX+/ddlq9kCvv9KVnR4/QXzZ5lSZPOPoPAUrKGx/6bwYRirdCmg/6ZQF0lTjM5BYR6/U8OcWp6C41I+dzuTTecxG38HKhWCcfyN16V9SimaSPIoKtVEkn8f3BCaAzfOrY2T+ZS62gGPNc/AVzVN2YYaZzb/CAofhvXwVprGCIj79sqQA/ofCnWRdJjMHF5Kl0eaJj5+fllCmvsNcnyRvwn8f0v6KCo3BMeGV+q7qhCPoYORK6iOx+P1H4E7oCZQyG6MHshTfelZRy5T8wh8pmkSfE43zmz+ERR+GY5JqVJA/0OhaRTqItllojlI4vFI0yT8LHMTb8yw/ylJE/gfOfM6o3KXwBh59PlFqZpI2kSSR1GpJpL8++BOpTnszO4wiDc7JOvIHe7o8DWbJsFyqnFm84+g8ClQO30dRyFDIH946ibZFN4c5PZ4rGli8TOW95sMDtU+A/0/4iiTqOQUGK+73bmuJKuAfV3TvEowqUuNE3HNX3DWkcStSeBzmyaBrds4s/lHUPgdfFVKF4xx6HrmBuLC65qS3YGZg+wejzVNguX9MlAL+P+UtMBluZown6SPo5LTYMxh48Rr3T2/C05AczHAN7TzQO/ujMcV1akZNk0Ce9g4s/lHUPg0qN89ioFm6HrmBuKq5nBGsmlac5DL49GmSTgmuZvAX05j+S5TE+YpCd+Eyk6j+acuXy0mwcp2GwyBP9U4oev9et/WNAl8buPM5h9B4beAMYTrFP5wXXogLvzCS3YL5znI7PGOppk62sR771pxGeu7UM1baK2XxQNwRWudu3CHlLwJd0hJXY4bNKoJX6ppEvibjTObfwSFe5QvGt55fe0PvHpHPeERYS8+ArHujQFJPKbmILOH24joe0naSJYiMeZeY+3uG5BV483ERCiNx7ZNfked7y9Tl3W0+TTYGN2mSbjDKaQC9tRREesoJN3UIt0GNKZxZvOPoHCPqilgmY2H42pCn6QG+MLTxx6Id3/gJPGYmoPMHm9pmpB/fUVdxh3nBjUv6Qush8eb5gaWuU16Z3TVdW2OT66K47i9nLC7+ymhX9IK5pMkVZ/IbICu9A28f2FevPYfRnz+i358TP1QKMd3vKoxYZmPcHEddLd/AeJU0yTQVl9IFUrBOgoLa8I31DQ3oN0vhGfzj6BwD7Oye2OXzIC48GiIQOMeUcHnHsVK4jE1B5k83J2RvpekjWRpMOZLlwAYpxQhkH5Y09zgNpbfAF/V6Lz1cRw3Prv7HHzNMxfaJTEwn2Sp+kRmA3S8iZT5Trg3wuDmj03qSJ3jwlvchDmolzwHJ6C4dMMkrFMKgqgmfMeNOTq2suKy+UdQuMedTTNcr/D/iDTwudc1JfH4JZomQsJ8Ae4Yj1D3kr/AOnp704Q9fKhfsgLHJ3PFcdz4nGqAR2iXxMB8kqXqE5kN0LlnO2egNY0T5vCMqQX0PPL0n3+Fc6gxEcQ0V0QE66hkWJO5Jbs6tt+y+UdQuEe1c2N55vQ83MDwf8Or98vb/KWUz2NqDjJ7vK1pEoxtaP+EvvvXVE+hIXi46w1jjo6c9jhvXdAuSQHLzbMX2JtnLrRLUsE8khRYR64K2iUpyDwFcprvFW1yD9HKtQPncGO6AuuoZFgTvqmmSRDn3iE95h9B4R5lJ8U7G83lG0Fwdf8sELH8Ueg9x9l8FlQ+j6k5yOzx1qaJsKGjTczFP6p4GA3B4+p6u9I0U01wg3ZJKphHkgLryFVBuyQFmadB3uOlgUuP7m0cc1XA8cs1zYhj/hEUfhdeU+veyJA0HA/meOWvdkap5iCbx1ubJuF2VooQ6NxrwO9Aw/B4W9OEyd33oK1+VLgsV4tqvxiofwvIu5814HP4w9+D8UpVA8dqmgkUPg3qR6fm4cXq07qJjqabNeSeppVfLo+PaJqpv6qC7sOOMomG4XF1ve2NC/PLNi33LAfa8x356Aju/CTLXU2zrAu880wovO4vXfQjwLvuZbtjMdz/oLM3mGAMGxhe4QA3oOMpnfvrzjoq2a0pWU/HiQ9frzjmH0Hh06C+e5evNx/4j+uwd+phrmvKPk1rDnJ5vL1pEowz3Hfpl/TD0FA8rq63PQ5zTDUtAltz/4O9uubLZbkqGC/JDuvIXUG7JAWZm0Br9jdvDILPtUa9o/qhhMldl9DaP03uJC8Tw3tv59vuqL+zabJWeLOixTH/CAqfArXb10iEZBHHL0PvSMp84WSfwpuD3B4f0jQR3juK+NCjTKKheLjrDWO/9UYQiXJKUpDJwHhJdrL1ZTZA17xJB1e0bb8yTp+nQJ69b+3QKL/hODF8bq5Q2I8XXt/aNKnBx6HGecw/gsIvgZp8hME9wiSQhV/wUVDPbGy5LtGbg2Qe/8imKdmHoqF4NNcb7Lc+crQBs7u+tm3Pd5lamPFm68tsgM42LSGJgTFe3VHO4yywgPyGcwCWq0dduCxXgXq5DKwjWbpmVofFdOM8xo2g8GFQL/U4SzTXK7TmKdcwmTlI6rGapoOG4tFcb9ge7pkffNUpMvcDuSpa+weR2wB9+f7yXSZDSXAiW19mw1a3hSQGxnh1RzmPs8AC8htaAbCVxsl3mXaoL4ENWEeydM2sjsCUapznuCwKb4Kc/POu6BJG98+8OC5pb0Opd2RuMjsHaTxW03TQUDyq9Ybl7k0Q+If/jPJIT393vg2ZDdDd3jThm7sswwLKZWBhySq8op2BPto0CczdxtmKy6Bwj7Jz67NBY9rvaOIzT6/OX4gnGKkxNQdqAqpxHKHvJWkj2SUQ/ks0Tb5j/YdPVhy4dPd6A3b3O0e/PhoYVxKcyNaX2eDlJZIYGMOXFg3w8Xpn90DGpZN8qMFQr1AD60iWrpnVHYErbJxeXA+Fe5SdG7mHLj6XxAAfwy/3Vbj+VKIgs8fsHCJW03TQUG7hvL0J93e5K2iXpAJ295ol8+ujgXFKUZGtL7OBNSUxSGLQOMNnnqEp/88SXuc76eVgAC/eTGLztc8808EkLeAbajDUK9TAOpKla2Z1Z+B2G2cUF6Fwj+2IYOhf2SmJQTTPGZC3uhYps8fUHLTosZqmg4YyjfZ3c/TE/f2lqIm+B5IMoVBDtr7MBuguNU368T71cDs5j7PAAvIbmgEB1CvUwDqSpWtmdS0gaTbOXpyHwj32poD86Q2lEMbc8nhEC5UoyOQxNQcteqym6aChTINtNnWkd2R0f6ReoYZsfZkN0M00ze6/jtTjPM4CC8hvaAYEUK9QA+tIlq6Z1XlAZhpnJq6Fwj32poDP6SM1hfRyk+pP047Q95K0wXz3L5NMHk/O4Zdpmgircl7dnzaUZorjNj7D8UlWEY0bvqG/2aZeoYZsfZkN0F1umgSfwxtnPc7jLLCA/IZmQAD1CjWwjmTpmlldBKRV48zGnVG4R9UUUCO1oaTt/rkfNO7dPrjDZ/YQu+/QMnlcngPRosdqmg5KcwnWjvYNQo3kFdG44Uv9CeoG9Qo1ZOvLbIBuqmkSLF9unOdxFlhAfkMzIIB6hRpYR7J0zayuB+R74xyJO8LYANMUUKe7oaQLf9XhD//fH7LNrQV8+6mTTB6X50C06LGapoPSDMHtjVf412UbHJ/CKnrjhj91iYY6hTTJ1pfZAN100yQw88bO8DXO8zgLLCC/oRkQQL1CDawjWbpmVpcBIaVxjsZtvKq6NJsC7ah3/if6edeO14zKKbc+uzC+JAuAxn0chfUke2wO5OVxWU3TQWlCtL55VMm7ue5RXQvGKU0F7ZI0gT91dEadQppk68tsgO6WprkBX/n3dlkfL9NEYSs9ghos8jLV9UeTFovFYrFYLBaLBJ8+/R+xWrzm+0H1GwAAAABJRU5ErkJggg=='},
        varesco_b11={width=223,height=32,data='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'},
        kindly_b01={width=83,height=32,data='iVBORw0KGgoAAAANSUhEUgAAAFMAAAAgCAYAAABuBERvAAAAAXNSR0IArs4c6QAAAARnQU1BAACxjwv8YQUAAAAJcEhZcwAADsMAAA7DAcdvqGQAAASbSURBVGhD7ZmBUdwwEEUpgAZogAZogAqogA7ogBZogRpoIl2kGMj7e1+KZa9lOafJJDO8Gc9Ju1/rtSzJsu/mm2/+D76+vm4/Pz/f+f3i9wfHvV0brP2w9tXmQ9DecTxzvHP8VPuC6hwf8lO9dZNdpEH7xJHFUpw3io+WD0GbOfkher00+w22O7sbFNSSgPqLXSmKk7RRci+ublAbN9+wbEdZF37P8WRTA3ad58lNU/DPy08OC9TrjyoL6m+WVLDd270mvVtFz+8Pfh51Do6fdsuvEbRBdksqmJczIkYOv68+mpG0Br/Os8kR+7T8AhwxKl2OqV4IwYKiXYP92ZIG7LrDSjQuhN+HaAC2p+D7iAALZLNbN1wd2+3ANejfHaqiGBxT8gtKI36bjhTYmrVTQexqyIKrrd2xdlFPb0QG2ubCqZdprItVR+5eaA/Fccip+QUYyxR/4djcaWzNiLM5xZKK2hZ7KZ+geXjQXg/FmKoqXyTnUVuHnJpfIKM8KhNwM+qw1YcL5ej4Dg+WBujfFNPl4SmpdhFggV0P+PZGT5n66Rq3xCGn5hfg0IgsAbPOrNOXal1PMtA2o1htfRzdhACdlpnmhgjZQuAbv4Z2dbQJm3vEOWblV5FAAV3udibldPtRwN/sOW0r07NCXefc3fqsQXt03makUE/X9UI5t8tX51ehUdwdlR2rofgE5d19l1hqhc0Z+3c3YeC8zT5XediVYtm0/CqcuDzJ0/2jErN0Wmeiy9ecHdB3n7LyWyptd8rir09hmzacza/i9tERLl6FwwY2pXA+7e9iVtgUUN+8rRzlhj/WTIojT/o66lxPIc5wfhVrpuGwgU2nIeGhve0SNIfbJTTN3tDm06zzq9g/DYcNbDoNyZ5aA0dwZzevkxfPedb5VeyfhsMGNp2GZJsn6bWdmXWkuHjPs86vYv80HDawaRiSjC9Abl65pjNpu/tFy5Jh9vKrWDcNhw0GOkFfaQ73cwNxUmjX/dY6K78K4sPXKEsPO55YzZsI9c2HkwK+7jfGJWivGZnxPu9QDbPyqxwlKr+lI53Z7DOp9/alm42xbLoIjtlrprY52fIxJb8Kju6HAfzLTftRxzebXUzpu7RAG1OQYvrxAltNeOC8Q52NrhltmKbkV8E4/Fajss0pimVpgOn24jkPseqNobw7HYXOq8PVLuhqh1Kdkl8F+9GXoNpBlI9GwGZq0OZwM52hcznEyA2Xf7hj0NcpPyO/BvtTaFTvpJPusVnoaXP2o2uwTJbq7nQUyks65WpTl2XsGfk14NhdN/HVtYFqb43ZfsYHXH80lYh35uPFmdkTWD4lv4a9ZJWYJRW7MnY/W+nE1gyjnNw8oL67hcO3nD1DH3otD2bk16CErFuSrYGbqY4tH/IGyal/EtFu/unMzlvAt+749HNiAX8zqjBdnd8GdNoG6H8RTfveSKsXRllP2nRTvARd9wILiu0mDbjSC8aWTjedb0efvqdLf1H0QZfm99chl/jDa32R1PXdUH/+708dwK8OijWRX23EuxeGTOerU5jy7tuQkE8axY4GhvpQft988y9xc/ML94+tDW2BbUAAAAAASUVORK5CYII='},
        kindly_b00={width=80,height=32,data='iVBORw0KGgoAAAANSUhEUgAAAFAAAAAgCAYAAACFM/9sAAAAAXNSR0IArs4c6QAAAARnQU1BAACxjwv8YQUAAAAJcEhZcwAADsMAAA7DAcdvqGQAAAS/SURBVGhD7ZqLbdw4FEVdgBtwA2kgDbiCVOAO0kFa2BZcg5twFynG2XOfLglS/I4yATYLH4AQ9X6i+B9qHj755O/j4+PjhfTzlyH/ncuj1Uuw/0Z6PbwPFI/0j3Q2W4Lbo3yOCBHjjfTF6i7oVdaA/Dtp+DzFIr3ZPN7TqusQJArM9cX3UZFc38NgAmZ64XfZC8UiVRUpHPOr3YbI//Bo6DZmsvczc1l8bXyQ506SQHa9EnH+5iAK/Mw1t46YBUd9rrxoea4vFjUkmx6oH22jMkQ+oZg2yyD+emgPvWL7NuC+6gBn/Ynt0VZBUA0RdfsfDtRg0wb5Si//MOSFyI96UAabbiWiigpB//0ch/tXm2VkQ9I08UTKDVmCPHcA8sN3RNc00BY4qgLjIY7VgL55YcmsS8N+WXEl2D9FoAJkeS47g+7NZhnLd54fvUsxfN8gf9ncjBxJqwpsgiNTy8dLcf1i022Sbwmy1EOqqUGc7RGl3hoNofwIbNLUMqvApjxb4KjhsqrAn2FsEKW555nUvOwu+FW9kHuNhtQozWQfRgZ97BqUR6VyDMEu5kLFtqhBOtncDL6at8L5CDUkT7LY/yBF4bkOh90KxYmARuWQDFW1gCRsFshO9s7vTB9q6D9Wgakyhg+AvAXBTouOCt28qGOosMthjU3Vs+VLUoPk1bXEZkGydX5nBDQ7jDMR+FbwS5WgihyuUpArUDcqPJdm6CDPm17ys21DouzZUSmO3WCzABs14nTqKcFWc/20p0bgK9h/Cg+P1Y5smrz1sk3LR8ACi2eUPXu7AnWP3StpuOc8M4qbcOjbsf8UPdy23eElsGnmEWTT4YU+b5HkL3tS80tG2Cyw6CaI2yxMJQ59O/afwsOvVuB03klxxcrWZoFFd8Whb2dVcIFN9BSywy2D4kTAglVs9P+LCtxZxWKu0vW4bblYgfkn1F9bgfafwsvF6kp2WIEiAhasKgXKRWS2C/hvViB+3U3rGZsvK5BKqH5dWDwkNYwgP1wl1RA2Cyy+Kw7dooKpACStbrnFBffTn0ECv+pYyOIRzzbTc5ebaZsGKqfFDSq/zQLdW3UXzvEzKJphoYKSnshu/Y5VDIcLuB9uB9DlgwflLe6CvjqiQrS9QOneqiHYTLctJef4AUJV0j3IvUoQd1Ux6nnToS6wq47JEG0vUNxPN8VC8Z1dco4fIF8Ozx0cLoPoLnGhOgXmJYYNjq46UtusnDgocX4Kdnk7lZHQ+st0A4PVlyFu9wDT6oZzObjfOYNUj95qbOK1J9J6qPW/Q/dbwe/Gxr85kRbIu/OWnmeTzMi2IBbMDTtRLa6BhIfuGjy4bRWDemv706NXGQl03SHX80G2dbqC3XK427QF5+2VqESFc4gh2GyfhCTw6W8XDPrRZrrpIdgOhzG681njsB7QNR+sMuhvnvAJuKy8hGzttgRbbZm6U0ICm25vQd79uI58q8cimq3wzUezilGheiyDdcBnWYnYxFG9XYbIJhwK8K16Uwm60crdPEvvZl0G2fLPA4EeRNJ3hGrjzL2+rulgUsGXLzgCX20Zzn/tiO/NpO6CMQLX+MzgGPoFtfprR/67hvxm9pjoaD/H5nL5nT/55E/w8PAv+DyTfMwCFGMAAAAASUVORK5CYII='},
        kindly_b02={width=109,height=32,data='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'},
        title_v05={width=262,height=28,data='iVBORw0KGgoAAAANSUhEUgAAAQYAAAAcCAYAAACDDxF1AAAAAXNSR0IArs4c6QAAAARnQU1BAACxjwv8YQUAAAAJcEhZcwAADsMAAA7DAcdvqGQAAATgSURBVHhe7dFBkts4EATA+f+ndy/JOqijAw2YIytk5s2FKlAY/zwej8fj8XjM/Xcz134tzwzxNvMQj5mF+PGh/De11MbMjrmmp3cb134tzwzxNvMQj5mF+PGh/De11MbMjrmmp3cb134tzwzxNvMQj5mF+OP4eSH+53h+S23M7Jhrenq3ce3X8swQbzMP8ZhZiD+Onxfif47nt9TGzI655px7Qvw1PGtJ/WP+Hj4f4o/j54X463luiFtqIW6phfh9fDfEX8OzltQ/5u/h8yH+OH5eiL+e54a4pRbillqI38d3Q7zNfMxse3cxX1JfUv+1v4d4zCzEt3P9mNlypxbibeYfx88LceG4cNxSC/H7+G6It5mPmW3vLuZL6kvqv/b3EI+Zhfh2rh8zW+7UQrzN/OP4eSEuHBeOW2ohfh/fDfE28zGz7d3FvHAc4jGzEIc4xIXjEI+ZhTjELbUl9TGz7e+Lt5l/HD8vxIXjwnFLLcTv47sh3mY+Zra9u5gXjkM8ZhbiEIe4cBziMbMQh7iltqQ+Zrb9ffE284/j54W4cFw4bqmF+H18N8RL6iFuqYX49u/7Z4jHzEIc4hAXjkM8ZhbiELfUCschbqmFOMQhvo1rQzxmFuIxsxDflnfUQvw+vhviJfUQt9RCfPv3/TPEY2YhDnGIC8chHjMLcYhbaoXjELfUQhziEN/GtSEeMwvxmFmIb8s7aiF+H98N8ZL6Mdfc9n1x4bhwXDhuqYU4xMfvupi11FpqIV7eu+KaEId4SX2b+ZhZiMfMQnxbPmU2ZnbOPSFeUj/mmtu+Ly4cF44Lxy21EIf4+F0Xs5ZaSy3Ey3tXXBPiEC+pbzMfMwvxmFmIb8unzMbMzrknxEvqY2aF4xAvqYe4cFw4Lhy31EIc4uN3Xcxaai21EC/vfWXWUgvxkvo28zGzEI+Zhbj9/Y4LxyEeMxszO+eeEC+pj5kVjkO8pB7iwnHhuHDcUgtxiI/fdTFrqbXUQry895VZSy3ES+rbzMfMQjxmFuL29zsuHId4zGzM7Jx7QrykHuJt5iFeUg/xmFmIt+9VC/Gv/b4psxD/8b2vXBPiwnGIl9RDfMw1IQ5xiAvHhePCcYhbasfvNQ/xnF2Il9RDvM08xEvqIR4zC/H2vWoh/rXfN2UW4j++95VrQlw4DvGSeoiPuSbEIQ5x4bhwXDgOcUvt+L3mIZ6zC/GSeohbaiF+2/dfmYX4r7/rYhbiMbMQ3/a+izjEheMQL6mH+JhrQhziEBeOQ9xSC3FL7fi95iGeswvxknqIW2ohftv3X5mF+K+/62IW4jGzEN/2vos4xIXjEC+ph/iYa0Ic4hAXjkPcUgtxS+34veYhnrML8TbzMbPj76uHePw71AvHIW6phfj4XRezY65ZUh8za6mFuHC8zfw2rg3xNvOWWuE4xCHeZn7OPSHeZj5mdvx99RCPf4d64TjELbUQH7/rYnbMNUvqY2YttRAXjreZ38a1Id5m3lIrHIc4xNvMz7knxNvMx8yOv68e4vHvUC8ch7ilFuLjd13MjrlmSX3MrKUW4sLxNvPbuDbE28xbaoXjEId4m/k594R4m/mY2fH31UM8/h3qheMQt9RCfPyui9kx1yypj5m11EJcON5mfhvXhnibeUutcBziEG8zfzwej8fj8dj28/M/9r5ff6xApwwAAAAASUVORK5CYII='},
        rainbow={width=138,height=28,data='iVBORw0KGgoAAAANSUhEUgAAAIoAAAAcCAYAAAC+uCc6AAAAAXNSR0IArs4c6QAAAARnQU1BAACxjwv8YQUAAAAJcEhZcwAADsMAAA7DAcdvqGQAAAK+SURBVGhD7dBBbuQwDEXB3P/SM5vy10IgaNqGg6C7dnmiaHV+vr6+vp737yHWvcZnQ36c9SF/Hr//Nute47MhP876kD+P33+bda/x2ZAfZ33In8fvv8261/hsyI+zPuTP4/eHPOZ6yH+enxPy5/H7Qx5zPeQ/z88J+fP4/SGPuR5yyGOubxyH/Np3nmZ9ydjv8Y6Qx1wPOeQx1zeOQ37tO0+zvmTs93jHbdaVjI25vnEc8mvfOcglYy3jJWMbxyGPuR7yot9mXcnYmOsbxyG/9p2DXDLWMl4ytnEc8pjrIS/6bdY9zvqQx71jPOR2n1wytnEccslYyOM9FddDXvTbrHuc9SE//o8zHnK7Ty4Z2zgOuWQs5PGeiushL3rIJWMhj7k+5nr5Dn+G3DIecvtOYyVjIY/faSzk8Z6K6yEvesglYyGPuT7mevkOf4bcMh5y+05jJWMhj99pLOTxnorrIS96yCVjIY+5PuZ6+Q5/htwyHnL7TmMlYyGP32ks5NN7HIcccsiLHnLJWMhjro+5Xr7DnyG3jIfcvtNYyVjI43caC/n0Hschhxzyood8mmshbxyH3DIe8rh3jId8ed/BtZDHe42FfHqP45BDDnnRQz7NtZA3jkNuGQ953DvGQ7687+BayOO9xkI+vcdxyCGHvOghn+ZayBvHIbeMhzzuHeMhX953cC3k8V5jIZ/e4zjkkENe9JBPcy3kjeOQW8ZDHveO8ZAv7zu4FvJ4r7GQT+9xHHLIIS96yJdZE/LG8Zjr5Xf8GXLLeMiX33mwpmW8ZKxl/DbrFj3ky6wJeeN4zPXyO/4MuWU85MvvPFjTMl4y1jJ+m3WLHvJl1oS8cTzmevkdf4bcMh7y5XcerGkZLxlrGb/NukUP+TJrQt44HnO9/I4/Q24ZD/nyOw/WtIyXjLWM32bd19fX12N+fv4D7uAs7aIGXtcAAAAASUVORK5CYII='},
        silver={width=90,height=28,data='iVBORw0KGgoAAAANSUhEUgAAAFoAAAAcCAYAAADhqahzAAAAAXNSR0IArs4c6QAAAARnQU1BAACxjwv8YQUAAAAJcEhZcwAADsMAAA7DAcdvqGQAAAGiSURBVGhD7dBBboRADEXBuf+lk03xF2MhbGgRKVDL5zYNfF6vZ/g5yXrZl3f7Y/kPY9bfH93lP4xZf390l/8wZv390Xt8d8jLeXzIz+G7Q17O40N+Dt8d8mkeE/Kf/2jXtllrf8/GuDIP+TSPCXn5PVOubbPW/p6N8THnDzleGIe82+/i2jZr472N9X3OHXK8MA75/dHfnDvkeGEc8rh3WQt5/FzHQi59Y1wYH3+Hc4ccL4xDHvcuayGPn+tYyKVvjAvj8Xfs8ryQl/UuayGXPuUxl9/vMveGvKx3WQu59CmPufx+l7k35GW9y1rIpR+xVhiHfB/3hrysd1kLufQj1grjkO/j3pDH/ZtxyCGHXBiHPGY95Pu4N+Rx/2YccsghF8Yhj1kP+T7uDXncvxmHHHLIhXHIuxwLefyc5dwb8uUXNg455JAL45B3ORby+Dm77I9ZL4xDPv3Cjoc8Zr3N2rL7xy+wsV4Yh3z6hR0Pecx6m7Vl949fYGO9MA759As7HvKY9TZry+4fv8DGemEc8ukXdjzkMett1pbd/3r9B5/PL5VzNHWy6yc2AAAAAElFTkSuQmCC'},
        golden={width=106,height=28,data='iVBORw0KGgoAAAANSUhEUgAAAGoAAAAcCAYAAACJWipLAAAAAXNSR0IArs4c6QAAAARnQU1BAACxjwv8YQUAAAAJcEhZcwAADsMAAA7DAcdvqGQAAAIZSURBVGhD7c5BjuMwDATA/P/Tu5dS+0AQMpNMnACuY7NJ6XG73T7h35s49zbOhnjMeoh/j/+/zLm3cTbEY9ZD/Hv8/2XOvY2zIR6zHuLf4/8vc+5tnA3xmPUQfz//DfHX8b0Qj1kP8ffz3xB/Hd8L8Zj1EH8//w3xn/FMS60wDnFhfJq1wvg0a+O9xXpPL8R/xjMttcI4xIXxadYK49OsjfcW6z29EG+pt9QK45ZaYRziwvg0a4XxadbGe4v1nl6It9RbaoVxS60wDnFhfJq1wvg0a+O9xXpPL8Rb6i218X21EI/zjlqIL7uzqIf4IA/xlnpLbXxfLcTjvKMW4svuLOohPshDPGY9xOP7aiH++P0pZ8b/WdRDfJCHeMx6iMf31UL88ftTzoz/s6iH+CAP8Zj1EI/vq4X44/d3rBXGId5SD/FBHuIx6yEe31cL8cfv71grjEO8pR7igzzEY9ZDPL6vFuLL7k9ZD/GWeogP8hCPWQ/x+L5aiC+7P2U9xFvqIT7IQzxmPcTj+2ohvux+Ry3E4zuLeogP8hCPWQ/x+L5aiC+731EL8fjOoh7int6Y9S31llphHOKn/7s4UxifZq395456iHt6Y9a31FtqhXGIn/7v4kxhfJq19p876iHu6Y1Z31JvqRXGIX76v4szhfFp1tp/7qiHuKc3Zn1LvaVWGIf46f8uzhTGp1lr/7mjHuLb7fZGj8d/InGwMdQW1FoAAAAASUVORK5CYII='}
    }
    local mutationSprites={}
    do
        local asset=getcustomasset or getsynasset
        if type(asset)=='function' and type(writefile)=='function' then
            local alphabet='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
            local values={}
            for i=1,#alphabet do values[alphabet:sub(i,i)]=i-1 end
            local function decode(value)
                local out,buffer,bits={},0,0
                for i=1,#value do
                    local digit=values[value:sub(i,i)]
                    if digit then
                        buffer=buffer*64+digit;bits+=6
                        if bits>=8 then
                            bits-=8;out[#out+1]=string.char(math.floor(buffer/2^bits)%256);buffer=buffer%2^bits
                        end
                    end
                end
                return table.concat(out)
            end
            D.decodeAsset=decode
            for key,spec in pairs(mutationSpriteData) do
                local ok,uri=pcall(function()
                    local filename='s2r_minecraft_'..key..'_v1.png'
                    writefile(filename,decode(spec.data))
                    return asset(filename)
                end)
                if ok and type(uri)=='string' then mutationSprites[key]={image=uri,width=spec.width,height=spec.height} end
            end
        end
    end
    local function styleRaisedButton(button)
        if button:FindFirstChild('StuddedSurface') then return end
        local corner=button:FindFirstChildOfClass('UICorner')
        if corner then corner.CornerRadius=UDim.new(0,3) end
        button.ClipsDescendants=true
        local spec=mutationSprites.studs_v05
        local texture=D.make('ImageLabel',{Name='StuddedSurface',Image=spec and spec.image or '',Size=UDim2.fromScale(1,1),BackgroundTransparency=1,
            ImageTransparency=0.65,ImageColor3=button.BackgroundColor3,ScaleType=Enum.ScaleType.Tile,TileSize=UDim2.fromOffset(256,256),Active=false,ZIndex=button.ZIndex},button)
        local function tint() texture.ImageColor3=button.BackgroundColor3 end
        button:GetPropertyChangedSignal('BackgroundColor3'):Connect(tint)
        D.make('UIStroke',{Color=Color3.fromRGB(8,4,16),Thickness=2,ApplyStrokeMode=Enum.ApplyStrokeMode.Border},button)
        D.make('UIGradient',{Color=ColorSequence.new(Color3.new(1,1,1),Color3.fromRGB(190,170,225)),Rotation=90},button)
        D.make('Frame',{Position=UDim2.fromOffset(3,2),Size=UDim2.new(1,-6,0,1),BackgroundColor3=Color3.new(1,1,1),BackgroundTransparency=0.55,BorderSizePixel=0,Active=false,ZIndex=button.ZIndex+1},button)
        D.make('Frame',{Position=UDim2.new(0,3,1,-3),Size=UDim2.new(1,-6,0,1),BackgroundColor3=Color3.new(0,0,0),BackgroundTransparency=0.25,BorderSizePixel=0,Active=false,ZIndex=button.ZIndex+1},button)
        local caption=D.make('TextLabel',{Name='RaisedCaption',Text=button.Text,RichText=button.RichText,Size=UDim2.fromScale(1,1),BackgroundTransparency=1,
            TextColor3=button.TextColor3,TextSize=button.TextSize,Font=button.Font,TextScaled=button.TextScaled,TextWrapped=false,
            TextTransparency=0,TextStrokeColor3=Color3.fromRGB(8,4,16),TextStrokeTransparency=0.35,Active=false,ZIndex=button.ZIndex+2},button)
        local function sync()
            local glyph=button:FindFirstChild('CustomButtonFont')
            caption.Text=button.Text;caption.TextColor3=button.TextColor3
            caption.TextTransparency=glyph and glyph.ImageTransparency==0 and 1 or 0
            if button.TextTransparency~=1 then button.TextTransparency=1 end
        end
        local glyph=button:FindFirstChild('CustomButtonFont')
        if glyph then glyph:GetPropertyChangedSignal('ImageTransparency'):Connect(sync) end
        sync()
        button:GetPropertyChangedSignal('Text'):Connect(sync)
        button:GetPropertyChangedSignal('TextTransparency'):Connect(sync)
        button:GetPropertyChangedSignal('TextColor3'):Connect(sync)
        for _,child in ipairs(button:GetDescendants()) do
            if child:IsA('GuiObject') and child~=texture and child~=caption and child.Name~='StuddedSurface' then child.ZIndex=math.max(child.ZIndex,button.ZIndex+3) end
        end
    end

    if mutationSprites.studs_v05 then
        bar.BackgroundColor3=Color3.fromRGB(32,16,62)
        local headerGradient=bar:FindFirstChildOfClass('UIGradient')
        if headerGradient then headerGradient.Color=ColorSequence.new(Color3.new(1,1,1),Color3.fromRGB(200,170,235));headerGradient.Rotation=90 end
        D.make('ImageLabel',{Name='HeaderStuds',Image=mutationSprites.studs_v05.image,Size=UDim2.fromScale(1,1),BackgroundTransparency=1,
            ScaleType=Enum.ScaleType.Tile,TileSize=UDim2.fromOffset(256,256),ImageColor3=Color3.fromRGB(170,120,240),ImageTransparency=0.52,Active=false,ZIndex=bar.ZIndex},bar)
        wallpaper.Image=mutationSprites.studs_v05.image;wallpaper.ScaleType=Enum.ScaleType.Tile
        wallpaper.TileSize=UDim2.fromOffset(256,256);wallpaper.ImageColor3=Color3.fromRGB(80,48,140);wallpaper.ImageTransparency=0.12
        wallpaperShade.BackgroundColor3=Color3.fromRGB(7,3,15);wallpaperShade.BackgroundTransparency=0.48
    end
    local buttonFontLookup={
        ["FULL"]='kindly_full',
        ["PREMIUM"]='varesco_b08',
        ["JOINING..."]='varesco_b12',
        ["MATCHMAKING..."]='varesco_b13',
        ["MIN RARITY: Eternal"]='varesco_b05',
        ["MIN RARITY: Any"]='varesco_b07',
        ["MIN RARITY: Secret"]='varesco_b04',
        ["MIN RARITY: Cosmic"]='varesco_b03',
        ["PREMIUM ON"]='varesco_b09',
        ["JOIN RANDOM SERVER"]='varesco_b10',
        ["MIN RARITY: Mythic"]='varesco_b02',
        ["TRY AGAIN"]='varesco_b14',
        ["ALL SERVERS"]='varesco_b00',
        ["MY SERVER"]='varesco_b01',
        ["MIN RARITY: Divine"]='varesco_b06',
        ["SEARCHING..."]='varesco_b11',
        ["HERE"]='kindly_b01',
        ["JOIN"]='kindly_b00',
        ["TAKEN"]='kindly_b02',
    }
    local function applyButtonFont(button)
        local glyph=D.make('ImageLabel',{Name='CustomButtonFont',Image='',ImageTransparency=1,BackgroundTransparency=1,ImageColor3=Color3.new(1,1,1),AnchorPoint=Vector2.new(0.5,0.5),Position=UDim2.fromScale(0.5,0.5),Size=UDim2.new(1,-14,0,20),ScaleType=Enum.ScaleType.Fit,Active=false},button)
        local function ready()
            local key=buttonFontLookup[button.Text]
            local spec=key and mutationSprites[key]
            if spec and glyph.Image==spec.image and glyph.IsLoaded then
                button.TextTransparency=1;glyph.ImageTransparency=0
            end
        end
        local function refreshFont()
            button.TextTransparency=0;glyph.ImageTransparency=1
            local key=buttonFontLookup[button.Text]
            local spec=key and mutationSprites[key]
            if not spec then glyph.Image='';return end
            glyph.Image=spec.image
            ready()
        end
        button:GetPropertyChangedSignal('Text'):Connect(refreshFont)
        glyph:GetPropertyChangedSignal('IsLoaded'):Connect(ready)
        refreshFont()
    end
    -- Bottom options use crisp native rounded text instead of bitmap captions.
    for _,button in ipairs({scope,myScope,rarity,D.sortButton,unlock,refreshButton,randomJoin,sizeMinus,sizePlus}) do styleRaisedButton(button) end
    for _,button in ipairs({scope,myScope,rarity,D.sortButton,unlock,randomJoin}) do
        button.Font=Enum.Font.FredokaOne
        local caption=button:FindFirstChild('RaisedCaption')
        if caption then
            caption.Font=Enum.Font.FredokaOne;caption.TextScaled=true;caption.TextSize=20
            caption.TextStrokeTransparency=1
            caption.Position=UDim2.fromOffset(6,2);caption.Size=UDim2.new(1,-12,1,-4)
            D.make('UITextSizeConstraint',{MinTextSize=10,MaxTextSize=(button==D.sortButton or button==unlock) and 22 or 20},caption)
            D.make('UIStroke',{Color=Color3.new(0,0,0),Thickness=2},caption)
        end
    end
    do
        local asset=getcustomasset or getsynasset
        if type(asset)=='function' and type(writefile)=='function' then
            for _,item in ipairs({
                {button=scope,file='s2r_beta_earth.png',bytes="\137\080\078\071\013\010\026\010\000\000\000\013\073\072\068\082\000\000\002\000\000\000\002\000\008\006\000\000\000\244\120\212\250\000\000\000\004\115\066\073\084\008\008\008\008\124\008\100\136\000\000\000\009\112\072\089\115\000\000\014\196\000\000\014\196\001\149\043\014\027\000\000\000\025\116\069\088\116\083\111\102\116\119\097\114\101\000\119\119\119\046\105\110\107\115\099\097\112\101\046\111\114\103\155\238\060\026\000\000\032\000\073\068\065\084\120\156\236\221\121\148\092\087\125\047\250\239\062\231\212\060\087\015\213\067\117\171\187\213\082\183\212\131\038\107\176\060\201\056\198\019\033\033\096\146\027\094\008\033\193\193\150\205\144\112\185\121\121\111\221\167\100\221\155\092\050\019\002\185\016\242\030\153\112\072\200\096\007\007\003\038\054\158\048\146\141\045\201\150\173\121\232\086\015\213\067\205\243\057\103\191\063\036\057\030\036\171\246\169\115\234\084\117\255\062\107\177\022\011\106\159\250\169\187\186\206\239\236\253\219\191\013\016\066\008\033\132\016\066\008\033\132\016\066\008\033\132\016\066\008\033\132\016\066\008\033\132\016\066\008\033\132\016\066\008\033\132\016\066\008\033\132\016\066\008\033\132\016\066\008\033\132\016\066\008\033\132\016\066\008\033\132\016\066\008\033\132\016\066\008\033\132\016\066\008\033\132\016\066\008\033\132\016\066\008\033\132\016\066\008\033\132\016\066\008\033\132\016\066\008\033\132\016\066\008\033\132\016\066\008\033\132\016\066\008\033\132\016\066\008\033\132\016\066\008\033\132\016\066\008\033\132\016\066\008\033\132\016\066\008\033\132\016\066\008\033\132\016\066\008\033\132\016\066\008\033\132\016\066\008\033\132\016\066\008\033\132\016\066\008\033\132\016\066\008\033\132\016\066\008\033\132\016\066\008\033\132\016\066\008\033\132\016\066\008\033\132\016\066\008\033\132\016\066\008\033\132\016\066\008\033\132\016\066\008\033\132\016\066\008\033\132\016\066\008\033\132\016\066\008\033\132\016\066\008\033\132\016\066\008\033\132\016\066\008\033\132\016\066\008\033\132\016\066\008\033\132\016\066\008\033\132\016\066\008\033\132\016\066\008\033\132\016\066\008\033\132\016\066\008\033\132\016\066\008\033\132\016\066\008\033\132\016\066\008\033\132\016\066\008\033\132\016\066\008\033\132\016\066\008\033\132\016\066\008\033\132\016\066\008\033\132\016\066\008\033\132\016\066\008\033\132\016\066\008\033\132\016\066\008\033\132\016\066\008\033\132\016\066\008\033\132\016\066\008\033\132\016\066\008\033\132\016\066\008\033\132\016\066\008\033\132\016\066\008\033\132\016\066\008\033\132\016\066\154\002\179\059\000\066\072\253\006\006\062\226\086\067\238\054\104\172\141\115\214\006\025\109\012\044\012\206\036\198\116\133\115\022\184\248\082\047\000\023\000\048\032\012\000\028\072\093\252\255\202\000\010\000\192\024\207\114\046\169\096\092\231\224\041\104\088\098\140\047\065\230\075\074\186\180\116\230\204\215\074\141\254\055\018\066\204\069\009\000\033\205\236\142\007\092\003\231\177\069\213\245\029\096\024\227\012\195\140\163\151\131\133\193\185\079\098\112\113\064\065\227\255\150\115\096\088\002\103\139\224\124\017\018\018\224\056\205\192\079\115\046\157\081\020\245\204\153\112\215\052\158\216\167\054\056\046\066\072\141\040\001\032\164\009\244\079\124\098\155\198\181\219\024\227\219\193\216\058\112\116\129\033\008\014\135\221\177\213\065\005\048\005\134\051\156\227\012\003\063\198\057\063\204\185\243\240\204\043\159\063\103\119\112\132\172\118\148\000\016\210\064\061\219\246\121\037\117\225\054\014\220\014\206\174\145\056\031\224\028\097\048\072\118\199\214\096\105\128\157\000\227\071\000\246\130\196\244\023\138\042\094\090\120\229\075\057\187\003\035\100\181\160\004\128\016\011\197\039\030\184\009\192\221\128\126\003\007\031\102\096\094\187\099\106\098\058\128\087\001\060\195\025\127\134\105\120\118\250\149\047\157\176\059\040\066\086\042\074\000\008\049\203\158\125\074\060\153\120\047\231\210\221\018\248\014\014\244\131\067\177\059\172\086\198\129\121\198\112\000\028\079\075\018\127\198\153\151\015\156\056\241\133\178\221\113\017\178\018\080\002\064\072\029\250\198\238\219\206\037\246\113\048\220\002\142\126\208\223\148\213\138\012\252\025\014\246\152\198\249\195\179\047\127\233\085\187\003\034\164\085\209\151\021\033\002\098\147\159\241\073\122\225\087\100\038\253\028\192\039\113\097\091\029\177\207\041\000\143\113\176\199\042\186\254\109\170\033\032\164\118\148\000\016\114\021\189\147\015\196\161\243\207\048\137\255\052\116\222\015\198\090\234\239\134\099\213\252\161\023\000\060\001\176\135\116\103\229\159\103\094\248\202\162\221\001\017\210\204\086\201\247\002\033\098\006\198\238\235\170\202\252\191\049\072\031\000\071\220\238\120\136\048\141\049\060\199\193\254\177\010\245\193\249\067\255\059\097\119\064\132\052\027\074\000\008\185\104\253\182\123\218\139\085\199\255\197\057\238\006\208\107\119\060\196\052\023\146\001\206\254\218\233\172\124\227\212\011\095\073\219\029\016\033\205\128\018\000\178\186\221\125\183\220\119\180\243\030\174\243\079\131\177\097\208\223\196\074\087\006\099\143\128\227\171\211\135\219\191\003\236\211\237\014\136\016\187\208\151\029\089\149\250\055\237\029\211\057\254\016\028\239\002\090\186\219\222\085\049\137\097\205\232\040\024\024\100\069\006\147\100\000\128\226\184\240\207\086\171\085\000\000\215\053\104\170\006\000\208\084\021\186\174\067\215\117\084\203\101\168\149\010\042\229\050\170\229\050\042\149\010\192\185\061\255\024\115\157\003\240\151\156\073\255\239\249\067\095\152\182\059\024\066\026\141\018\000\178\122\236\217\167\196\151\023\247\130\243\095\003\208\111\119\056\034\252\097\007\218\099\046\068\059\093\008\183\187\240\248\191\206\130\011\220\132\119\223\117\023\252\161\144\057\193\112\142\074\165\130\234\197\132\160\092\042\034\187\156\154\073\047\167\194\213\082\201\091\046\023\081\045\021\161\235\045\243\112\173\129\225\219\140\227\171\083\109\029\143\208\249\005\100\181\160\004\128\172\120\023\171\248\255\132\049\252\036\192\157\118\199\115\037\110\143\140\158\065\047\058\123\189\104\143\057\017\237\116\035\218\229\066\091\204\005\135\243\205\157\130\063\247\137\067\072\046\212\222\015\103\252\218\093\232\025\028\050\059\228\183\074\044\207\165\022\171\165\234\070\000\080\043\101\084\202\069\148\075\069\148\010\057\020\243\089\148\010\121\084\043\077\125\144\224\012\007\251\075\039\151\191\120\250\229\207\207\219\029\012\033\086\162\004\128\172\088\125\147\247\222\192\185\244\071\000\223\006\052\215\214\061\143\079\065\044\238\070\239\160\015\189\067\094\244\014\250\208\217\227\001\171\241\068\128\175\127\254\004\014\061\151\172\249\253\250\071\214\099\116\219\053\006\163\021\193\243\153\197\220\043\197\092\105\199\149\094\161\169\042\138\249\204\133\164\160\144\069\049\159\067\041\159\021\154\209\104\128\050\056\254\070\226\210\031\159\123\229\011\071\236\014\134\016\043\052\213\151\034\033\102\232\159\188\247\023\117\046\253\079\052\073\037\191\036\051\244\173\245\097\104\099\000\107\214\251\209\059\224\069\032\082\223\068\196\019\015\207\226\209\007\107\095\182\014\119\116\096\199\173\183\214\245\158\002\212\066\186\248\195\108\050\119\067\173\003\116\093\067\049\159\069\033\151\065\033\147\066\046\179\252\122\109\130\205\056\003\255\190\198\240\167\051\135\190\244\045\092\104\171\064\200\138\064\009\000\089\017\182\109\187\199\049\087\150\063\195\152\244\025\000\081\059\099\145\037\134\174\053\094\172\155\008\162\127\196\143\161\013\001\184\061\178\169\239\113\226\229\012\190\250\063\143\214\030\147\172\224\230\015\222\013\169\129\019\033\197\108\233\007\153\165\236\077\070\198\114\014\148\139\057\228\050\041\020\178\041\100\083\075\080\171\021\179\067\020\196\094\096\076\255\195\169\104\231\063\082\157\000\089\009\040\001\032\173\109\207\062\165\111\049\177\143\051\233\215\000\238\177\043\140\088\220\131\141\215\132\049\180\049\136\129\017\255\219\214\236\205\086\204\171\248\237\143\189\036\086\008\120\231\157\240\135\195\022\070\245\054\188\152\046\062\149\073\230\110\172\251\066\028\040\229\051\200\166\022\145\073\046\161\144\077\131\219\247\048\126\154\129\255\246\084\091\231\223\082\034\064\090\025\037\000\164\069\237\147\226\227\137\255\014\198\062\003\192\215\232\119\151\024\067\255\122\031\070\183\134\177\241\154\008\058\123\220\141\014\001\191\255\169\067\088\154\023\040\004\220\181\011\061\067\150\023\002\190\021\207\167\139\079\231\004\150\003\106\161\169\042\178\169\037\100\147\139\200\164\022\237\154\029\056\202\024\255\173\169\067\157\223\160\126\002\164\021\081\002\064\090\013\139\111\186\247\179\076\151\126\147\003\193\070\190\177\195\041\097\120\060\136\209\173\097\140\109\011\195\031\182\183\125\192\215\255\244\036\014\253\112\185\230\215\247\173\095\143\013\215\052\162\016\240\109\244\204\066\246\249\098\254\202\133\129\245\224\028\040\228\082\072\045\206\035\181\052\015\181\210\240\211\130\143\112\198\063\119\254\080\231\223\082\034\064\090\009\037\000\164\101\244\077\238\189\151\235\248\028\024\002\141\122\079\073\102\024\217\028\194\214\027\218\176\097\075\024\138\197\083\251\034\158\252\214\028\254\253\239\166\106\126\125\184\189\013\059\222\125\155\133\017\093\025\007\207\039\103\083\231\171\101\117\189\197\239\131\066\054\125\033\025\088\156\107\240\204\000\123\153\003\191\125\254\240\159\125\019\084\044\072\090\000\037\000\164\233\197\039\246\222\009\224\047\001\116\053\234\061\059\227\110\108\189\161\029\215\220\212\001\127\072\105\212\219\010\057\249\074\006\127\241\063\106\047\004\148\100\025\183\220\125\055\152\100\083\018\195\049\191\052\147\212\213\170\218\221\152\247\227\200\166\151\145\092\152\069\106\041\001\174\107\013\121\091\000\079\234\146\244\169\153\131\095\120\177\081\111\072\136\017\148\000\144\166\213\183\237\158\181\122\085\249\071\198\217\150\070\188\095\184\221\137\045\215\181\099\203\141\109\182\172\233\139\042\021\053\252\214\047\191\040\084\008\120\237\029\119\034\016\105\104\033\224\155\232\156\191\178\120\110\113\152\115\184\026\250\190\154\138\228\226\060\150\230\166\080\204\103\027\242\150\096\248\059\135\174\252\087\106\040\068\154\021\037\000\164\233\012\015\063\224\042\122\249\215\024\231\063\011\139\063\163\076\002\070\054\133\113\221\237\157\024\030\015\213\220\136\167\089\252\193\167\015\097\113\174\246\053\239\177\157\059\209\187\118\173\133\017\093\093\165\084\125\050\057\151\170\123\103\128\081\197\092\006\075\243\211\072\045\206\065\211\044\159\021\200\131\177\063\112\023\216\239\158\056\241\133\134\023\039\016\242\078\204\221\156\076\072\157\250\198\239\255\140\234\208\191\203\128\205\176\240\230\239\242\200\184\230\166\118\124\240\190\033\092\119\071\012\109\049\119\147\245\010\172\205\217\227\121\204\079\021\107\126\189\203\235\069\071\175\189\253\145\100\069\094\195\057\158\173\150\171\125\118\188\191\195\233\066\048\218\129\246\174\062\056\221\030\148\203\069\104\214\053\029\114\002\216\163\042\250\207\250\187\182\159\201\206\031\056\102\213\027\017\034\170\005\191\242\200\074\180\102\114\239\086\013\252\097\112\102\233\221\201\023\171\098\224\198\052\110\185\241\006\244\180\251\173\124\171\134\120\234\091\115\120\068\160\016\048\212\214\134\157\183\217\083\008\248\038\156\231\150\102\083\139\106\069\029\176\059\020\128\035\179\188\132\133\153\051\200\101\106\111\175\108\208\163\050\099\247\157\061\244\103\167\173\126\035\066\174\134\102\000\136\189\246\236\083\122\003\227\095\229\192\151\000\102\217\182\190\142\013\005\140\221\189\132\013\239\093\066\168\191\012\039\111\067\187\223\190\181\112\179\104\154\142\023\126\176\084\243\235\171\149\010\006\055\110\004\179\123\186\131\049\167\219\239\062\095\076\023\162\000\108\094\120\097\112\121\188\136\118\246\032\020\237\132\206\053\148\011\121\171\222\108\152\003\247\004\099\059\212\204\077\003\207\225\200\017\218\045\064\108\067\009\000\177\077\255\198\189\183\004\074\133\003\012\184\022\022\205\070\181\175\047\096\243\135\023\048\244\174\020\188\109\213\215\223\069\213\057\226\129\150\058\017\248\178\188\126\005\063\248\183\217\154\055\157\113\206\209\217\215\007\151\199\182\166\137\175\099\140\117\074\014\229\201\114\161\060\096\119\044\151\056\156\046\132\162\157\136\118\094\216\168\080\046\230\172\056\164\200\001\224\039\130\011\190\219\131\177\157\063\202\036\246\039\204\126\003\066\106\065\009\000\105\184\120\252\110\079\112\112\207\063\114\134\223\001\152\249\119\034\006\116\142\021\176\233\023\018\024\186\037\013\119\232\237\221\090\053\150\067\204\057\010\069\110\177\170\191\183\080\028\018\014\062\179\140\066\174\246\142\180\193\182\040\130\081\091\143\075\120\157\195\169\244\084\138\149\083\186\166\183\217\029\203\027\201\138\003\129\072\059\162\177\056\024\003\138\086\156\086\200\208\011\224\099\193\216\014\095\212\059\246\116\042\245\018\181\021\038\013\069\009\000\105\168\190\177\189\063\007\175\239\025\112\054\097\246\067\063\123\195\141\127\112\079\026\238\208\059\087\120\059\181\094\132\154\224\073\184\094\083\039\242\152\059\087\123\033\160\187\009\010\001\223\064\118\251\061\011\197\076\049\196\155\240\251\072\146\101\004\194\109\104\235\236\001\231\058\138\133\220\133\214\131\038\190\005\128\235\117\151\243\003\225\238\237\007\211\243\007\206\153\121\113\066\222\073\211\253\193\145\149\105\096\207\071\220\190\192\117\143\130\225\191\226\194\020\168\121\024\208\189\057\143\205\191\148\192\192\013\105\184\131\181\109\237\098\170\015\177\064\135\169\161\216\033\185\088\198\241\067\153\218\007\048\032\062\060\108\093\064\130\024\067\059\083\216\083\149\066\101\192\238\088\174\068\146\021\004\035\237\136\118\246\130\115\142\098\033\107\118\034\208\206\057\251\165\096\215\142\104\095\251\093\255\177\176\240\068\195\186\022\145\213\139\018\000\098\185\222\177\251\223\197\075\142\031\051\096\212\236\107\135\250\203\216\242\225\005\012\222\156\130\211\039\246\157\089\069\017\253\190\245\045\191\023\134\107\192\243\063\088\172\249\245\149\114\025\131\027\054\130\073\205\243\015\119\056\029\177\114\190\050\175\235\122\067\207\119\016\037\095\076\004\034\237\221\208\212\010\074\230\022\011\050\000\059\043\172\112\151\063\182\243\201\108\098\127\237\191\084\066\012\104\237\005\080\210\244\226\147\123\063\207\036\253\049\000\166\238\185\115\135\085\076\126\040\129\221\159\058\143\200\080\237\211\223\111\164\177\044\082\005\099\099\155\073\247\128\007\146\064\085\063\215\117\228\210\041\011\035\050\196\019\142\133\166\237\014\162\086\078\183\007\253\235\038\176\126\114\007\124\065\115\119\147\112\096\171\004\254\227\248\228\253\159\068\203\167\167\164\153\209\012\000\177\068\239\228\003\241\112\231\246\151\000\220\014\019\091\236\040\046\029\067\183\166\176\229\195\009\132\250\042\117\127\061\042\106\039\162\190\134\157\045\100\009\069\145\240\210\015\151\081\200\214\094\067\022\136\068\016\106\107\170\186\059\072\018\139\107\170\126\064\173\168\077\083\160\112\053\014\167\011\209\206\030\184\189\126\020\243\105\104\170\105\117\124\014\000\183\007\059\119\236\138\118\108\127\044\181\112\032\103\214\133\009\185\132\018\000\098\186\190\201\251\239\227\156\063\010\192\180\059\140\036\113\244\095\159\197\214\143\206\161\115\067\017\204\164\079\174\166\073\232\013\196\205\185\152\141\166\079\228\048\043\082\008\232\241\162\035\222\124\247\089\151\199\085\045\100\010\030\000\205\121\002\211\101\049\184\189\126\180\197\046\124\142\138\185\140\121\059\006\024\134\117\038\125\040\212\121\205\225\076\226\192\073\115\046\074\200\005\148\000\016\243\220\125\183\220\171\236\121\008\028\159\102\038\046\047\005\123\043\216\250\203\243\232\219\149\133\236\052\119\043\150\138\044\186\189\163\144\155\104\061\220\136\212\082\005\199\014\166\133\198\196\215\053\079\033\224\037\140\033\204\100\249\153\074\177\121\011\002\175\132\049\009\129\080\020\209\142\110\084\042\037\148\139\166\213\007\004\192\216\135\130\093\059\165\204\252\157\079\002\079\080\243\032\098\010\074\000\136\041\226\099\247\013\007\150\124\071\024\216\086\179\174\169\184\057\070\126\114\025\019\063\183\000\119\216\162\162\104\198\225\213\006\016\240\052\244\112\058\211\233\026\199\243\079\008\020\002\086\154\175\016\240\018\197\169\132\139\185\098\137\115\052\255\145\140\151\033\043\014\132\219\187\224\241\007\145\207\036\161\155\115\224\016\003\176\039\024\203\239\008\199\174\249\247\116\226\249\146\025\023\037\171\027\021\001\146\186\245\076\236\253\041\038\177\035\012\172\211\172\107\118\142\021\112\253\103\167\048\112\099\218\242\067\122\150\202\115\214\190\065\003\244\014\250\132\102\049\184\174\035\151\178\188\239\189\033\140\033\028\140\006\095\178\059\142\122\133\034\029\024\221\178\027\237\221\253\038\126\134\217\029\058\164\151\250\198\239\191\198\172\043\146\213\139\018\000\082\151\248\248\222\223\147\128\127\225\038\237\237\119\005\053\076\126\040\129\109\191\050\007\079\164\049\141\209\050\252\076\067\222\199\074\014\167\132\246\030\177\007\230\204\242\178\069\209\212\207\229\115\238\148\020\105\198\238\056\234\037\201\010\122\007\071\176\118\124\059\220\030\159\089\151\237\231\140\063\213\055\113\255\047\153\117\065\178\058\209\018\000\049\100\120\248\001\151\039\190\253\025\006\124\016\102\108\085\098\064\255\117\025\108\251\229\121\132\251\027\123\108\186\206\138\104\151\070\224\116\180\246\159\195\244\201\060\102\207\022\106\126\189\211\227\070\103\188\105\011\032\029\078\183\243\165\098\182\180\198\238\064\204\224\116\185\017\141\245\002\028\040\228\196\106\053\174\064\001\240\083\193\174\029\209\117\241\045\223\159\157\125\065\055\227\162\100\117\105\237\111\060\098\139\248\166\143\247\170\014\246\026\227\024\049\227\122\078\159\134\205\191\176\128\193\061\105\072\138\061\245\077\014\053\134\136\175\181\143\007\078\047\085\113\084\176\016\176\111\221\058\139\162\169\159\044\075\061\229\092\105\070\215\121\200\238\088\204\192\024\067\032\028\069\032\210\134\092\122\217\172\045\131\059\243\154\124\083\176\227\250\135\051\011\207\181\126\083\011\210\080\180\004\064\132\172\025\191\111\055\116\249\004\056\076\089\239\111\031\041\224\250\207\078\163\115\220\178\227\087\107\146\084\091\126\182\025\189\067\094\161\215\231\083\041\179\010\212\172\226\008\117\132\078\219\029\132\217\188\254\016\070\054\095\139\246\110\211\078\163\188\017\082\101\127\239\166\189\235\205\186\032\089\029\040\001\032\053\139\079\238\253\021\149\177\167\128\250\171\179\101\007\199\134\247\045\097\251\175\206\193\085\099\239\126\043\229\113\006\122\139\079\162\246\012\120\133\010\001\117\206\145\077\053\093\071\192\055\081\092\202\046\121\005\212\002\188\149\036\201\232\029\028\193\192\200\036\020\135\041\229\051\107\153\142\103\251\038\031\184\193\140\139\145\213\129\018\000\082\147\248\228\222\207\131\227\047\204\216\223\031\234\043\227\186\207\076\099\224\198\116\211\052\058\213\089\005\075\185\218\215\207\155\145\195\041\161\163\087\180\016\112\201\162\104\076\227\012\117\132\142\219\029\132\085\066\109\049\140\108\186\022\129\112\187\025\151\107\227\092\255\094\223\228\125\255\197\140\139\145\149\143\106\000\200\085\245\142\223\247\048\003\251\112\221\023\098\192\218\091\082\216\244\127\044\192\025\176\255\169\255\173\100\173\029\237\190\214\094\110\158\058\149\199\236\025\129\066\064\119\083\023\002\002\000\100\069\138\149\178\165\036\231\220\180\050\250\102\034\201\010\194\237\221\096\146\132\124\166\238\173\153\010\192\222\023\234\220\089\200\036\246\063\107\070\124\100\229\162\004\128\092\217\158\125\074\220\063\254\067\198\240\174\122\047\165\184\057\054\253\066\002\107\110\200\128\053\233\188\019\215\029\232\009\052\095\123\092\017\153\229\042\142\190\036\080\008\200\155\187\016\240\034\135\236\080\014\148\242\229\001\187\003\177\010\099\128\063\024\129\047\024\070\054\185\008\189\190\245\040\006\134\119\007\058\119\196\178\055\013\060\138\035\071\168\115\032\185\044\074\000\200\101\013\015\063\224\242\086\242\071\192\048\081\239\181\124\157\085\236\184\119\006\209\181\205\221\188\076\101\057\244\249\070\193\172\238\060\100\033\174\115\028\120\188\246\142\128\213\114\025\003\027\055\064\146\154\052\043\187\072\081\228\080\033\087\212\193\225\180\059\022\043\057\221\030\068\058\186\144\207\166\081\173\212\183\029\150\049\108\015\044\250\054\199\130\187\254\101\121\121\127\243\077\185\017\219\053\247\095\061\177\197\200\200\103\003\037\143\126\018\012\117\055\139\239\028\047\096\247\167\207\195\031\171\154\017\154\165\056\170\072\230\154\059\073\185\154\158\053\094\072\178\064\071\064\206\145\077\054\119\033\032\000\128\033\226\011\250\094\176\059\140\070\112\056\221\024\030\187\198\148\093\002\012\120\111\201\163\255\115\252\218\079\123\076\008\141\172\048\148\000\144\055\233\218\242\064\071\222\145\063\013\160\174\185\112\198\128\145\247\044\099\219\071\231\160\184\091\167\188\062\089\108\206\246\184\181\082\156\018\098\113\193\066\192\165\230\237\008\248\070\222\160\167\031\096\173\243\097\170\003\147\036\244\014\142\160\127\120\220\140\217\153\059\145\171\126\187\125\228\163\173\125\238\053\049\029\037\000\228\117\107\038\239\031\084\084\237\036\088\125\199\248\058\125\058\174\249\248\028\134\110\073\053\077\149\127\173\050\106\194\238\016\234\022\031\018\171\149\203\054\255\078\000\000\000\099\024\112\007\092\171\098\022\224\146\072\103\055\134\199\183\195\225\168\247\176\042\126\147\219\233\121\116\096\243\167\194\166\004\070\086\004\074\000\008\000\160\127\211\222\049\077\231\071\000\086\215\083\130\191\171\130\221\191\054\141\246\245\173\185\165\046\143\115\224\104\237\154\169\094\193\004\032\189\220\058\179\030\129\136\111\213\125\103\121\252\065\172\219\180\019\030\095\221\015\240\187\085\173\242\031\093\091\030\232\048\035\046\210\250\086\221\031\019\121\187\248\214\123\039\117\157\189\000\086\095\131\159\200\096\025\059\239\159\129\039\218\152\067\124\172\160\075\069\020\203\173\061\203\220\059\040\150\000\228\051\105\179\218\210\090\078\146\164\173\138\083\057\099\119\028\141\230\112\186\048\060\118\013\002\225\186\038\231\000\176\045\138\170\063\177\102\195\061\221\166\004\070\090\026\037\000\171\092\207\182\123\070\081\149\246\003\188\174\057\198\232\240\133\074\127\167\175\181\111\158\000\144\041\182\118\075\245\238\126\047\100\069\172\016\048\147\108\153\089\000\230\011\123\207\218\029\132\029\036\069\193\224\198\045\104\139\213\221\183\097\163\166\056\030\031\028\255\100\204\140\184\072\235\162\004\096\021\139\111\253\229\097\169\226\252\049\128\186\110\254\225\205\041\116\189\103\014\178\067\049\041\050\123\229\171\089\187\067\168\139\226\096\232\138\139\021\125\103\155\248\104\224\183\114\121\092\019\140\161\177\071\070\054\009\006\134\248\218\013\232\025\028\065\157\187\085\071\170\076\253\078\255\196\189\017\147\066\035\045\136\018\128\085\170\103\236\147\253\168\186\015\002\220\240\246\032\198\128\142\155\019\232\184\113\001\085\189\004\169\216\103\102\136\182\201\171\166\028\215\106\043\209\058\128\076\011\037\000\140\033\234\014\184\127\108\119\028\118\234\232\238\071\255\186\009\176\250\118\008\108\210\033\125\171\099\236\190\214\062\006\147\024\070\009\192\042\020\155\252\120\167\196\212\195\000\196\142\143\123\003\201\161\163\251\061\051\008\079\252\231\205\114\057\211\154\133\127\111\085\226\173\081\021\255\078\122\007\197\126\181\233\022\217\009\112\137\063\236\095\245\251\218\195\237\093\024\218\176\005\178\092\087\063\183\221\046\137\061\052\048\240\145\186\015\248\034\173\135\018\128\085\102\108\108\159\223\193\229\151\193\016\052\122\141\075\055\127\223\224\155\143\240\093\040\156\135\162\182\126\129\113\153\037\000\189\197\246\047\190\133\232\086\192\066\038\011\181\218\252\205\154\046\145\036\182\073\118\202\231\236\142\195\110\254\080\020\131\027\182\066\082\234\090\126\123\151\026\240\063\052\060\252\064\189\123\013\073\139\161\004\096\021\025\216\243\017\119\070\090\056\010\192\240\093\090\114\105\232\125\223\121\120\251\046\095\040\087\046\024\206\043\154\134\206\042\200\087\090\231\102\120\057\177\062\241\066\192\092\147\031\013\252\022\044\016\242\157\178\059\136\102\224\011\134\049\188\113\091\157\199\010\243\119\151\188\252\235\216\179\111\101\020\242\144\154\080\002\176\122\176\234\146\239\069\014\244\024\189\128\236\214\016\127\223\121\184\187\174\220\046\119\054\053\005\198\077\057\223\220\086\165\022\122\026\190\028\197\193\208\213\183\178\151\001\156\062\215\090\176\022\111\218\096\018\143\063\136\181\227\215\064\113\214\241\016\207\249\207\196\151\022\191\100\094\084\164\217\081\002\176\074\244\142\239\253\062\003\070\141\142\151\061\023\158\252\093\157\239\092\124\093\210\138\144\203\205\125\188\108\045\042\090\107\039\000\000\016\095\043\182\012\144\075\181\086\241\035\003\250\220\110\231\203\118\199\209\044\220\030\063\134\199\182\193\081\079\018\000\254\177\190\241\251\126\221\180\160\072\083\163\004\096\021\136\079\220\255\021\198\112\179\209\241\178\079\067\252\253\211\112\117\212\182\243\042\153\105\253\029\090\021\173\098\119\008\117\019\045\004\044\100\091\111\251\163\039\236\109\169\117\011\171\185\060\190\011\173\131\157\198\107\250\056\099\191\023\159\188\255\253\038\134\069\154\020\037\000\043\092\124\226\254\207\002\252\099\070\199\043\062\021\241\159\153\130\051\090\251\013\113\062\063\005\069\139\026\125\203\166\080\093\001\009\064\172\079\172\080\190\082\106\189\147\016\029\078\199\004\099\172\245\002\183\144\211\237\193\218\241\109\245\044\007\072\224\252\111\123\198\239\219\109\102\092\164\249\080\002\176\130\245\142\223\123\023\192\255\151\209\241\178\071\067\239\207\076\195\025\017\159\014\175\230\091\060\001\208\091\255\158\018\138\058\133\094\223\074\187\000\046\097\012\097\183\223\125\208\238\056\154\141\203\237\189\176\069\208\248\238\000\183\004\246\080\124\243\039\214\153\025\023\105\046\148\000\172\080\189\155\062\182\158\049\233\095\096\240\060\062\201\165\163\247\167\206\027\186\249\003\192\076\122\026\012\117\237\079\182\085\149\183\254\050\134\168\058\110\022\182\242\004\220\154\221\049\052\035\143\047\128\161\141\091\033\203\006\127\175\012\237\208\180\111\211\225\065\043\023\037\000\043\208\200\200\103\003\076\119\062\015\192\080\057\062\083\056\186\239\156\185\106\193\223\059\041\170\249\022\047\006\108\253\226\242\124\070\236\128\031\165\069\019\000\135\067\158\132\196\090\251\000\007\139\120\253\033\012\140\110\134\100\188\099\224\090\069\229\255\184\109\219\061\173\191\181\135\188\013\037\000\043\080\222\153\063\000\192\208\217\161\140\001\221\183\205\093\113\159\191\136\148\224\013\168\185\180\118\035\032\000\152\062\153\019\122\189\092\215\062\114\027\049\230\247\248\220\135\236\014\163\089\249\067\017\012\142\110\174\163\109\048\191\105\190\172\252\190\169\065\145\166\064\009\192\010\019\159\220\251\119\000\070\012\013\102\064\231\187\018\240\173\021\187\113\092\201\124\110\010\178\022\054\229\090\141\038\161\053\159\134\223\232\149\003\098\005\242\222\064\221\231\205\219\134\150\001\222\153\063\220\134\254\225\049\024\078\108\025\251\100\124\226\254\159\055\053\040\098\059\074\000\086\144\190\241\189\031\005\135\225\063\210\246\235\022\017\028\051\111\047\056\007\135\090\168\247\252\114\123\056\229\214\110\053\159\056\095\196\241\151\197\126\151\161\246\214\252\093\001\180\012\080\139\112\123\023\186\251\215\214\113\005\254\213\158\201\189\091\077\011\136\216\142\018\128\021\162\127\211\222\049\093\194\087\140\142\143\108\075\034\178\213\252\051\225\103\211\179\104\197\143\153\171\133\019\000\206\057\030\254\218\057\112\093\108\092\168\173\117\019\000\048\230\247\120\093\135\237\014\163\217\117\198\007\209\222\101\184\054\199\195\056\254\169\119\116\111\011\127\080\200\027\181\222\055\051\121\155\129\129\125\110\093\199\211\140\027\043\187\247\013\230\208\182\123\209\236\176\000\000\133\106\022\074\011\022\003\006\092\134\015\074\180\221\119\255\225\060\078\188\156\017\026\227\116\185\224\015\181\230\114\205\037\158\160\103\245\109\221\048\160\119\112\020\129\176\177\123\056\003\006\224\192\131\184\251\238\214\221\226\067\094\071\009\192\010\160\005\022\158\004\096\232\219\219\217\086\070\215\109\115\096\022\214\188\101\114\173\085\081\207\192\016\240\180\222\012\000\231\028\143\254\253\052\030\255\215\089\225\177\221\067\067\096\086\126\008\026\192\225\116\172\167\179\001\106\192\024\214\140\076\194\227\243\027\027\014\220\026\127\181\227\255\054\057\042\098\003\074\000\090\092\124\098\239\111\113\096\187\145\177\178\071\067\239\123\103\032\057\173\253\206\156\205\156\131\172\135\044\125\015\051\201\060\004\071\139\061\223\204\158\045\226\203\191\245\026\158\120\072\252\230\015\000\189\067\067\038\071\100\007\030\115\184\028\175\218\029\069\043\144\101\005\003\163\091\224\112\024\236\022\200\216\127\239\153\120\224\039\204\141\138\052\026\037\000\045\172\119\243\125\155\001\024\202\196\153\204\209\125\215\044\148\128\245\091\245\056\116\104\133\214\233\037\226\225\173\019\235\252\084\001\095\255\252\009\252\233\111\190\140\051\071\141\237\222\136\116\118\194\031\106\157\004\237\157\248\130\158\132\221\049\180\010\167\203\141\129\013\134\183\007\074\018\244\191\234\217\118\079\187\217\113\145\198\105\253\189\078\171\213\158\061\010\091\102\223\131\193\036\174\227\166\005\120\122\026\087\052\061\151\156\067\183\095\002\135\096\101\154\013\220\082\196\238\016\174\042\049\093\194\019\015\207\224\165\167\151\161\115\227\051\056\140\049\172\223\178\197\196\200\236\229\242\058\187\237\142\161\149\120\253\065\196\215\110\192\212\241\087\140\012\239\145\042\202\095\000\120\159\201\097\145\006\105\177\137\078\114\073\060\112\215\191\001\216\100\100\108\100\075\010\209\237\203\038\071\244\206\042\122\025\157\190\126\232\178\088\113\154\029\058\029\163\008\123\155\179\008\112\126\170\128\135\191\118\022\015\253\213\089\204\158\045\214\189\224\221\187\118\045\250\214\173\164\118\239\172\173\148\043\205\114\157\183\110\083\131\006\243\248\002\168\150\203\040\230\141\156\006\201\070\131\177\157\179\153\196\254\023\076\015\140\088\142\150\000\090\080\239\166\189\031\004\112\167\145\177\222\254\002\218\174\095\048\057\162\218\100\179\173\081\100\230\081\154\175\000\240\210\084\255\159\252\198\043\056\244\092\082\120\139\223\229\056\093\046\172\219\188\185\254\011\053\023\230\241\121\078\218\029\068\171\137\015\141\194\235\015\026\028\205\255\184\103\226\254\081\083\003\034\013\065\009\064\139\233\159\184\055\034\233\248\107\035\099\101\175\138\174\091\173\173\248\127\039\179\185\179\144\117\159\061\111\046\192\211\068\045\113\011\057\013\255\246\087\231\240\249\255\118\196\180\027\063\000\048\073\194\228\245\055\192\233\050\124\100\108\211\114\249\093\180\180\041\136\073\018\214\140\108\130\162\024\250\236\123\101\240\191\027\027\219\039\118\252\036\177\029\037\000\045\070\227\242\127\112\064\248\091\155\049\160\235\246\121\200\062\251\058\166\234\186\014\189\208\252\075\180\178\108\255\202\024\231\028\207\061\150\192\239\127\234\016\158\121\116\190\174\117\254\203\217\184\125\059\162\177\078\083\175\217\044\100\069\222\000\006\106\013\044\200\233\114\099\205\200\164\161\237\160\028\216\154\150\022\126\219\130\176\136\133\040\001\104\033\125\227\247\125\134\049\110\104\206\054\178\125\025\222\120\193\236\144\132\205\166\023\192\154\252\160\029\198\236\221\074\094\173\232\248\251\047\156\194\191\254\229\089\020\243\038\239\210\096\012\235\054\109\066\239\218\122\090\194\054\055\198\016\118\186\149\215\236\142\163\021\249\067\081\196\250\012\127\054\254\107\255\166\251\174\055\051\030\098\045\074\000\090\068\239\232\222\054\206\216\239\024\025\235\233\045\034\186\115\201\236\144\012\201\085\150\161\084\122\237\014\227\029\113\147\159\182\069\100\146\021\252\239\255\231\085\028\252\161\249\069\154\076\146\048\190\107\023\006\199\198\076\191\118\179\113\251\125\246\020\186\172\000\157\189\131\240\135\162\070\134\074\186\206\190\058\048\240\017\183\217\049\017\107\080\002\208\034\152\131\127\007\128\240\002\157\236\214\044\239\244\039\042\151\183\127\138\253\157\148\085\123\102\143\011\057\013\095\253\157\163\056\127\198\252\153\026\167\219\141\109\055\191\011\061\131\131\166\095\187\025\185\060\014\067\119\048\114\097\185\176\127\221\056\100\197\080\041\197\136\026\240\253\159\102\199\068\172\065\009\064\011\232\029\123\224\195\000\219\038\060\144\001\177\091\231\160\248\173\111\246\035\098\058\117\022\050\111\222\098\192\138\218\248\159\087\165\172\227\107\191\119\020\137\233\146\185\023\102\012\221\003\003\216\125\215\093\043\118\205\255\114\036\137\109\100\140\025\217\215\070\000\056\156\046\244\173\221\104\116\248\111\246\142\221\183\226\182\151\172\068\148\000\052\185\158\109\247\120\153\164\125\217\200\088\111\111\001\158\184\201\055\020\019\112\104\224\197\230\045\006\172\104\213\134\191\231\067\255\223\089\156\059\158\055\245\154\209\088\039\118\220\122\043\038\118\239\094\145\213\254\087\161\184\189\206\163\118\007\209\202\066\109\049\068\058\123\140\012\085\024\099\095\166\003\131\154\031\253\130\154\092\184\125\215\055\000\054\097\100\108\053\227\064\234\165\008\138\211\030\232\021\005\074\064\133\228\108\142\078\124\170\010\248\003\205\121\120\091\128\245\035\226\109\220\012\197\171\063\078\225\219\095\159\054\237\122\145\142\014\140\237\218\133\225\201\073\184\155\180\161\081\067\048\118\172\148\047\015\216\029\070\043\011\132\219\144\094\156\135\166\010\038\197\012\189\193\037\255\114\102\126\255\143\172\137\140\152\161\137\086\134\201\091\245\141\063\176\150\067\063\006\102\206\076\013\099\128\187\171\004\223\080\014\190\161\060\156\145\138\025\151\053\108\052\222\007\213\049\099\107\012\151\211\197\118\099\036\214\215\144\247\042\021\053\252\225\175\191\140\108\178\254\223\069\052\214\137\181\019\019\136\116\198\076\136\172\245\113\157\191\156\056\183\056\110\119\028\173\174\144\075\227\196\225\003\070\138\099\115\154\138\241\217\087\191\120\214\138\184\072\253\168\097\070\019\211\153\254\231\204\196\101\026\206\129\170\097\008\139\000\000\032\000\073\068\065\084\226\172\027\197\089\055\022\159\105\135\051\082\133\111\040\011\223\080\030\238\174\082\195\011\005\139\089\023\154\177\084\171\164\055\174\093\241\015\191\147\168\251\230\079\055\254\203\099\018\027\097\050\203\115\173\137\011\078\090\128\215\031\066\071\207\000\018\231\079\139\014\245\203\010\190\004\224\046\011\194\034\038\160\037\128\038\021\031\223\251\062\198\240\155\086\190\135\086\146\081\154\245\032\115\036\132\244\203\033\084\146\078\048\006\056\002\042\088\003\170\067\010\213\028\162\065\055\056\107\174\034\069\112\007\226\129\126\203\223\166\090\209\241\224\159\158\066\165\108\108\089\038\220\209\129\137\221\215\098\237\132\241\179\221\087\056\185\090\209\094\214\170\106\243\022\156\180\008\127\048\140\244\082\002\170\232\082\000\176\046\024\219\113\032\147\056\112\220\138\184\072\125\040\001\104\066\099\099\251\156\101\150\255\023\048\214\214\168\247\228\085\009\229\005\055\178\199\002\072\189\020\070\057\225\006\215\025\020\159\006\201\097\205\190\120\157\107\104\115\015\128\059\146\150\092\223\040\029\101\244\251\055\088\062\035\242\252\227\011\056\244\156\248\126\127\197\225\192\196\181\187\049\178\117\043\221\248\175\130\129\029\045\021\168\014\160\094\140\049\184\125\126\036\019\179\070\134\239\236\012\238\250\202\242\242\126\234\206\216\100\104\009\160\009\165\165\196\175\001\204\182\035\218\244\170\132\220\073\063\114\039\253\096\140\195\019\047\193\055\148\135\127\048\007\037\104\110\133\252\066\058\133\182\038\171\083\211\089\005\197\138\006\175\203\218\252\248\149\003\041\225\049\110\175\023\219\110\185\005\190\000\029\118\087\011\135\071\105\194\069\166\230\167\235\058\116\077\131\174\169\208\117\013\186\174\129\115\014\127\040\130\092\090\056\105\029\046\122\180\251\000\252\177\005\161\146\058\080\017\096\147\025\028\255\100\172\202\212\099\000\140\030\205\101\041\087\071\025\190\161\060\124\067\057\184\059\204\169\226\223\208\215\139\170\050\103\202\181\204\050\234\185\139\199\066\126\203\254\062\202\069\013\191\253\171\047\066\171\214\062\187\034\203\010\118\222\126\027\252\161\144\085\097\173\068\165\249\179\139\018\056\095\145\007\213\112\112\232\170\010\077\211\192\117\013\186\166\065\123\253\166\173\067\083\171\208\117\029\092\215\160\169\234\133\027\187\174\066\087\181\215\199\104\250\197\027\189\166\067\215\053\241\138\255\218\148\153\194\134\166\094\252\179\230\171\250\093\197\104\006\160\201\084\152\250\187\172\073\111\254\000\080\094\112\161\188\224\194\242\143\162\112\004\170\240\013\021\224\027\202\193\219\091\004\036\099\075\005\243\011\026\058\098\062\104\146\185\251\224\235\145\173\164\010\049\248\045\043\030\059\117\036\043\116\243\007\128\225\201\009\186\249\139\115\059\093\242\171\149\146\186\193\238\064\222\142\163\090\169\160\082\046\162\090\046\065\085\213\139\055\226\011\079\220\186\118\225\198\174\235\058\248\165\255\174\105\208\249\165\155\185\006\174\055\199\182\222\026\184\184\134\111\001\216\106\119\032\228\063\081\002\208\068\250\039\238\221\166\003\191\104\119\028\181\170\102\029\072\029\012\033\117\048\004\217\163\193\063\156\067\104\060\013\151\224\204\192\114\105\014\213\217\048\122\186\034\208\228\230\168\007\072\085\230\085\032\110\217\245\231\166\138\066\175\119\186\221\232\091\191\222\162\104\086\054\183\207\189\080\041\229\154\034\001\224\156\035\147\092\068\038\153\064\118\121\009\213\106\115\246\194\176\004\231\091\250\039\247\254\226\185\067\095\252\043\187\067\033\023\080\002\208\060\152\198\165\063\097\038\237\249\111\052\173\040\035\125\248\194\110\002\111\127\001\237\187\023\133\018\129\108\037\133\169\217\000\250\187\058\160\042\246\159\227\082\228\243\150\030\104\178\056\039\214\161\049\214\223\015\169\009\142\041\110\069\138\203\097\251\247\028\215\053\044\039\102\144\056\127\022\149\178\088\242\183\146\112\224\243\000\040\001\104\018\244\141\210\036\250\038\246\254\020\024\062\043\058\110\235\238\109\024\219\050\001\198\024\178\233\044\244\038\152\018\172\166\029\200\188\018\130\090\148\225\233\045\129\201\181\077\117\087\245\010\178\121\013\237\190\078\232\082\206\226\040\223\025\151\042\074\135\050\010\167\098\077\062\246\212\183\230\145\090\170\125\255\255\192\134\013\052\253\111\144\036\075\200\167\010\182\253\240\074\133\028\078\191\250\034\150\019\051\208\180\038\219\242\218\120\238\112\108\135\148\078\028\120\194\238\064\008\037\000\205\130\005\187\118\060\008\160\075\100\144\063\232\199\029\031\248\073\196\122\098\088\055\182\030\091\118\109\069\087\111\023\020\135\130\092\038\007\181\106\239\151\077\121\222\141\220\113\063\188\125\069\200\222\218\118\000\105\092\069\042\091\066\135\183\023\186\220\184\134\060\151\163\148\122\017\241\091\179\069\225\135\223\075\032\155\172\189\216\106\112\108\035\092\030\143\037\177\172\116\012\008\149\178\165\004\231\141\111\008\180\056\059\133\211\071\015\066\173\216\219\117\179\153\112\240\157\153\141\190\207\225\204\025\251\159\086\086\057\074\000\154\064\239\196\253\119\051\224\001\209\113\055\223\117\011\058\187\254\243\132\055\073\146\016\105\139\096\104\100\045\054\095\187\021\107\134\250\225\242\120\080\042\020\081\042\218\115\040\144\094\150\145\061\026\130\171\163\012\103\184\182\027\158\014\013\201\124\030\029\158\001\232\138\248\086\057\179\240\082\004\221\097\107\118\145\237\255\143\005\161\004\160\127\100\061\156\110\058\102\221\040\085\213\095\086\043\170\117\069\029\151\145\056\127\006\051\103\142\053\242\045\091\004\083\066\197\142\104\038\113\224\219\118\071\178\218\081\002\096\187\125\082\040\150\127\016\128\080\031\215\238\120\055\174\191\245\070\176\043\116\171\097\140\033\016\010\162\127\104\013\054\237\216\140\117\027\215\195\031\240\163\090\169\160\144\051\255\188\249\119\194\053\134\220\009\063\092\109\021\056\163\181\061\009\113\174\099\057\159\070\135\107\008\186\195\158\036\064\173\042\232\143\088\115\038\192\129\199\023\144\017\072\000\186\007\006\224\246\081\071\091\195\056\078\052\178\033\208\194\249\179\152\061\075\205\239\174\132\129\109\137\122\239\250\253\084\234\137\085\191\038\098\039\074\000\108\022\031\031\255\016\024\062\046\050\134\049\134\059\238\126\015\252\193\218\187\192\121\124\030\244\244\247\098\108\235\004\198\182\078\032\028\141\128\235\028\185\108\022\092\183\166\211\223\155\112\134\220\105\063\060\189\069\056\002\181\253\205\115\206\177\148\075\162\205\185\014\112\138\119\204\171\023\151\011\136\123\054\064\146\204\111\007\240\242\254\036\150\230\107\047\146\140\116\118\034\016\137\152\030\199\106\193\036\182\088\200\020\013\157\109\043\170\144\075\227\236\241\195\141\120\171\086\038\171\174\124\044\155\056\240\111\118\007\178\154\081\002\096\167\061\251\148\096\033\247\015\162\045\127\055\076\110\196\228\246\077\134\223\214\233\116\162\179\039\134\145\137\081\108\218\177\005\029\093\029\144\100\009\185\076\014\154\106\097\183\078\157\033\127\202\135\192\104\086\232\088\226\229\252\018\034\242\058\048\087\131\183\008\050\029\114\177\023\097\191\249\107\239\231\078\228\049\125\178\246\190\007\178\162\032\214\215\152\019\010\087\034\089\130\051\151\042\088\222\115\082\215\053\156\124\249\121\104\042\061\216\094\141\196\216\100\112\232\250\063\200\076\063\071\063\044\155\080\002\096\163\062\255\216\071\192\216\047\137\140\145\036\009\119\222\253\030\184\220\046\083\098\144\021\025\109\029\109\024\222\176\014\091\174\221\134\158\053\113\184\092\046\020\242\121\084\202\230\023\046\113\245\194\153\003\129\209\140\080\175\253\100\113\009\033\182\014\146\187\177\203\001\213\162\031\061\145\118\211\175\187\052\087\194\177\131\233\154\095\095\204\101\209\055\188\030\178\066\127\178\198\048\111\049\091\154\227\156\091\122\120\066\098\230\044\210\075\009\043\223\098\037\145\081\213\187\050\243\251\031\182\059\144\213\138\190\077\108\178\109\219\061\142\172\046\127\147\001\097\145\113\099\091\039\048\058\049\106\073\076\140\049\132\034\033\012\012\015\096\243\206\173\024\028\025\130\207\239\069\185\084\070\033\111\094\221\128\154\113\064\114\235\240\116\137\021\038\166\074\075\240\243\033\040\238\044\192\026\176\108\001\064\213\085\172\009\015\153\127\221\170\142\023\126\176\084\243\235\047\044\211\112\180\117\211\193\118\070\105\085\237\136\090\081\123\045\187\190\166\226\236\209\195\173\212\157\239\138\036\198\224\246\041\240\135\020\004\066\014\068\058\092\232\236\117\163\171\207\139\158\053\030\012\140\004\048\056\026\192\218\241\032\070\183\132\049\182\061\002\151\091\198\252\180\112\143\131\137\224\090\154\005\176\139\237\013\050\086\171\249\178\243\103\025\227\003\034\099\100\069\193\246\235\119\088\020\209\219\117\118\117\162\179\171\019\059\111\186\022\153\084\006\167\142\157\194\233\163\039\049\115\110\026\122\157\117\003\203\207\182\195\063\088\128\035\036\054\203\112\046\125\002\061\218\026\248\218\231\193\153\037\061\203\223\132\187\150\144\202\149\017\246\155\051\227\114\201\154\145\000\220\094\025\165\066\237\075\046\103\095\123\013\237\061\061\136\198\132\234\069\201\069\078\175\179\088\204\089\183\027\038\181\056\103\085\031\253\119\228\242\200\112\056\025\156\046\025\030\175\012\135\075\130\195\041\193\227\147\225\112\094\248\255\220\094\005\078\183\004\167\083\130\195\045\195\237\149\225\116\074\080\156\018\188\151\094\231\098\023\254\119\151\012\089\017\175\123\153\188\054\130\163\007\211\040\023\133\150\017\029\044\091\249\067\000\247\009\191\033\169\027\037\000\118\097\250\175\137\158\197\052\177\109\066\168\240\207\076\193\112\016\155\119\108\198\230\029\155\081\042\148\112\250\196\041\028\121\241\021\204\156\059\111\232\122\186\202\048\247\221\078\196\063\048\045\124\236\238\076\238\044\058\121\031\066\029\203\224\204\250\237\141\179\169\069\132\253\230\062\056\202\018\195\200\166\016\014\254\176\246\226\070\206\057\094\122\242\041\108\217\115\019\034\029\029\166\198\179\026\056\156\014\075\027\041\164\022\231\013\141\115\056\037\172\025\241\035\210\238\132\203\171\192\233\148\224\116\075\112\123\101\056\156\018\028\078\025\094\159\012\197\041\193\225\146\224\185\120\147\118\056\025\092\158\230\153\196\245\005\028\216\253\238\024\030\127\072\236\188\031\206\240\017\000\123\001\052\102\090\143\188\142\078\003\180\065\239\228\222\091\024\199\099\034\099\020\069\193\135\031\248\037\248\172\059\159\198\144\153\169\025\060\241\200\127\096\105\097\209\208\248\246\027\023\016\217\108\108\093\191\203\191\006\254\142\025\000\214\078\185\042\197\053\184\110\112\151\233\215\125\229\064\018\127\243\071\039\132\199\049\073\194\240\196\004\006\054\108\000\147\090\178\115\180\093\102\230\207\044\088\178\019\064\085\043\056\178\255\073\112\193\123\216\238\219\059\241\238\015\198\225\110\162\027\121\061\010\057\013\191\247\137\131\040\137\205\002\000\208\127\099\250\240\159\127\206\146\160\200\021\173\140\079\093\139\009\117\110\255\034\192\214\137\140\217\188\107\011\214\142\014\091\021\146\097\129\080\000\027\054\109\192\210\194\050\082\075\226\085\250\165\243\094\004\214\231\032\187\197\119\031\228\042\105\068\029\214\111\017\212\029\025\116\040\035\166\183\005\110\239\113\227\224\051\075\040\228\004\255\237\156\099\121\126\030\179\167\079\067\211\116\184\125\062\056\156\014\083\099\091\161\002\197\076\049\205\057\076\239\168\148\207\164\144\092\152\021\026\115\253\029\049\252\228\047\174\129\226\088\057\073\156\195\041\065\085\057\078\029\201\138\013\100\108\115\102\254\192\239\091\019\021\185\018\074\000\026\172\127\211\222\049\206\217\031\065\096\246\197\233\114\226\246\015\220\005\135\163\057\191\228\037\089\198\240\198\117\152\159\158\067\058\089\123\101\059\000\112\157\161\156\112\035\176\081\108\087\192\037\217\082\022\109\129\048\184\100\237\082\064\037\027\065\167\201\189\248\025\099\080\156\018\094\253\177\177\025\016\181\090\197\242\252\028\206\029\125\013\115\231\206\162\090\046\195\237\245\194\225\050\183\094\097\037\081\075\213\227\170\170\153\094\068\145\089\094\064\054\085\123\081\103\048\226\196\135\063\179\014\178\188\242\038\097\187\250\189\120\238\177\004\052\085\104\054\196\027\236\218\249\114\102\126\255\171\086\197\069\222\110\229\164\158\045\066\211\241\235\016\092\122\025\219\058\001\079\147\247\129\151\152\132\119\191\239\118\120\124\226\091\173\139\179\110\164\014\010\109\134\120\093\085\175\160\144\182\254\156\151\164\118\218\146\235\110\189\161\029\157\241\250\031\072\243\233\012\078\030\062\140\167\191\245\045\236\255\238\119\112\246\181\215\080\052\113\231\198\074\161\184\157\150\052\147\168\148\196\126\214\155\174\141\194\225\092\153\095\191\094\191\140\029\183\024\168\081\209\065\075\000\013\182\050\063\129\077\106\112\252\147\049\006\252\023\145\049\146\196\176\105\251\102\171\066\050\149\199\235\193\045\063\249\019\134\198\046\063\219\142\074\202\105\104\236\116\250\052\020\205\252\189\250\111\164\185\103\177\156\053\127\150\065\113\048\252\236\125\107\033\153\245\036\200\057\082\139\075\056\250\227\031\227\169\135\254\021\207\060\242\045\156\060\124\024\133\172\224\148\236\010\229\112\089\083\247\044\122\010\103\103\188\185\019\250\122\221\112\103\012\178\067\240\051\205\244\181\131\227\247\078\090\019\017\185\028\074\000\026\168\194\212\251\001\177\245\199\225\013\235\017\008\005\044\138\200\124\131\235\134\176\126\108\068\120\156\174\050\204\127\175\019\220\064\029\048\135\142\066\214\250\159\209\217\229\105\075\174\219\059\232\197\141\239\017\058\008\178\102\052\051\240\102\138\067\182\100\186\072\180\248\079\173\088\216\113\179\009\004\035\078\108\189\094\168\193\041\000\134\170\036\253\137\037\001\145\203\162\026\128\070\217\179\079\009\021\011\127\013\064\232\078\117\203\123\223\013\127\192\158\173\127\070\197\215\244\225\181\195\175\162\090\017\219\019\173\230\140\053\008\002\128\066\037\135\104\200\099\105\111\128\010\075\163\215\183\206\146\179\001\134\198\002\152\159\042\034\113\222\186\090\134\082\161\136\165\217\217\213\093\051\192\152\059\159\046\152\094\004\152\077\045\161\152\171\253\248\234\072\187\019\163\091\141\045\123\181\138\142\030\015\158\251\094\066\116\115\095\127\102\219\174\207\225\196\254\149\157\033\053\009\074\000\026\164\047\048\254\094\000\031\019\025\019\031\232\195\053\215\111\183\040\034\235\040\014\005\145\246\008\142\189\124\084\120\108\233\188\023\254\117\226\187\002\116\174\033\234\028\180\118\071\128\084\069\053\219\129\118\011\122\049\048\198\176\225\154\048\078\191\154\069\106\209\250\179\227\171\229\050\146\137\004\206\029\059\182\170\146\001\198\224\182\162\037\112\185\088\016\042\002\092\152\045\227\154\027\219\154\106\031\191\217\124\001\005\211\039\243\088\156\171\253\208\043\000\082\032\011\057\059\191\255\251\086\197\069\254\211\202\253\244\053\153\096\108\251\031\002\016\218\250\119\211\029\055\035\028\109\205\019\224\034\109\017\164\150\146\088\090\168\253\075\017\184\180\043\192\133\160\129\093\001\170\202\224\015\008\125\217\008\043\084\179\232\011\013\093\241\024\230\122\200\050\195\248\206\040\102\207\022\176\036\246\165\089\151\215\147\129\227\199\177\052\059\003\181\170\194\229\241\174\216\173\133\106\089\061\174\086\053\083\123\042\107\106\021\169\197\057\129\215\115\156\057\154\199\248\246\008\028\174\149\187\018\235\011\040\120\241\105\177\239\000\198\249\134\076\130\182\004\054\002\037\000\013\208\059\249\064\156\129\255\025\004\106\046\034\109\017\220\240\238\155\044\185\209\052\074\163\151\002\202\090\001\049\127\028\186\108\093\193\027\087\138\168\102\218\209\102\081\071\070\197\033\097\211\117\081\084\202\058\206\029\203\089\242\030\239\228\245\101\130\099\071\177\052\059\003\174\115\120\131\001\072\242\202\249\170\208\116\253\120\165\088\089\099\230\053\021\135\019\137\153\179\066\099\050\203\021\028\124\118\025\221\107\124\136\118\174\204\153\151\104\167\011\135\158\075\162\144\021\104\245\207\152\055\220\177\253\251\233\133\003\231\172\139\140\000\148\000\052\068\168\227\154\079\131\177\119\137\140\217\117\243\117\136\245\180\118\207\119\197\161\032\020\009\225\248\145\099\194\099\141\054\008\242\073\029\144\061\214\158\024\152\211\022\209\229\089\011\069\182\230\201\141\049\134\245\147\033\244\014\249\048\117\034\143\098\222\158\229\208\082\161\136\133\153\025\156\059\118\020\229\066\001\193\104\020\074\147\246\162\016\195\206\148\114\165\001\051\175\040\073\050\010\217\020\042\037\177\195\112\074\069\013\047\062\181\132\098\078\197\240\100\016\082\011\039\252\151\195\024\131\036\049\188\246\162\216\223\036\103\108\040\147\056\240\087\022\133\069\046\162\004\192\114\251\164\096\087\225\107\016\056\245\207\225\080\112\235\079\221\182\034\142\126\141\182\071\013\047\005\148\012\044\005\228\203\057\068\066\046\128\089\120\184\152\092\197\242\018\071\111\196\218\004\173\163\219\141\157\183\116\064\146\025\206\159\045\064\171\218\211\042\157\235\028\153\229\101\076\031\063\001\093\215\017\110\239\000\179\160\016\178\129\022\011\153\162\233\045\129\057\056\050\203\011\134\198\078\157\200\099\250\100\030\099\219\035\134\014\226\105\102\157\189\030\060\251\221\132\216\231\151\033\158\137\111\249\095\152\125\161\245\143\086\108\098\173\127\135\105\114\189\227\027\238\100\096\066\039\093\141\110\218\128\117\027\215\091\021\082\195\213\181\020\224\210\225\233\174\125\041\064\135\134\014\247\000\184\195\146\126\047\175\083\029\139\200\039\067\166\119\007\124\043\073\102\024\218\024\196\238\119\119\034\210\225\066\122\177\130\092\186\241\039\206\001\000\231\058\146\137\004\018\211\083\008\119\116\194\229\049\189\152\190\033\024\131\150\079\023\076\255\197\185\125\126\164\022\140\159\008\184\052\095\198\185\227\057\108\218\021\053\175\047\068\019\144\021\134\244\098\025\211\167\132\182\159\074\097\077\042\164\019\007\158\182\042\046\066\009\128\229\066\177\157\159\003\176\065\100\204\158\059\223\005\127\176\117\246\254\095\077\093\075\001\051\226\075\001\076\115\195\237\207\011\191\151\168\130\060\141\066\050\132\142\080\208\242\247\082\028\018\226\067\062\236\186\181\019\027\182\134\225\241\201\200\036\171\066\199\009\155\165\082\046\099\246\244\105\004\034\097\248\130\214\255\219\205\198\024\011\020\210\197\050\076\062\013\149\129\065\150\029\072\047\039\012\095\035\185\080\065\038\085\197\198\107\090\179\248\247\074\002\017\039\246\127\095\108\118\132\115\105\125\038\177\159\250\002\088\136\018\000\011\013\108\254\084\088\231\250\151\033\240\069\211\214\217\142\107\111\190\206\194\168\236\209\200\165\128\130\154\069\044\208\005\093\106\076\018\144\095\014\090\062\019\240\070\193\136\019\235\038\066\184\254\142\152\109\201\000\231\058\018\231\206\193\229\247\035\024\105\185\155\021\043\023\074\103\116\141\071\205\190\176\199\231\071\049\151\069\089\176\053\240\027\205\156\041\160\163\199\141\174\062\241\182\218\205\042\024\113\224\213\023\211\200\038\005\102\071\024\066\161\200\206\191\200\044\237\167\054\150\022\161\004\192\066\129\142\173\063\007\176\247\139\140\217\126\253\014\116\245\090\211\021\206\110\141\092\010\008\058\122\193\092\214\158\018\120\073\065\158\070\062\217\216\036\224\146\055\038\003\019\187\162\240\135\028\200\036\171\040\228\044\172\129\184\136\003\088\060\127\030\129\112\024\062\027\254\237\245\208\202\218\177\106\069\141\155\127\101\134\064\036\138\212\194\060\116\205\248\239\224\204\209\044\118\190\171\115\069\157\020\008\000\175\009\030\124\197\037\120\179\137\003\143\088\020\206\170\071\009\128\133\130\177\029\191\011\160\230\051\124\021\069\193\173\063\253\110\040\138\053\253\202\237\166\056\020\132\163\097\028\127\197\250\165\128\082\165\132\011\247\164\198\212\016\217\153\004\092\226\015\058\048\180\049\128\221\183\053\118\102\096\225\252\012\218\123\187\225\106\242\003\171\222\072\211\244\147\229\098\101\192\138\107\075\146\012\127\040\138\244\082\002\186\110\236\103\095\041\235\144\020\134\181\099\173\183\196\114\037\237\093\110\060\253\232\060\116\173\246\098\064\137\177\254\076\098\255\031\088\024\214\170\070\009\128\069\226\099\159\142\130\105\095\130\192\207\120\253\248\008\214\143\143\090\024\149\253\034\237\081\164\150\147\088\074\024\105\016\084\251\177\193\042\175\034\230\029\128\174\088\187\037\240\141\010\242\052\114\054\039\001\151\052\114\102\224\082\113\096\124\237\090\048\169\053\158\088\057\248\185\082\174\100\106\047\128\055\114\056\093\008\070\058\144\094\078\064\215\140\037\001\137\233\018\118\223\222\185\098\142\012\086\028\018\102\207\022\145\056\047\180\085\210\031\142\093\243\055\233\196\243\214\086\245\174\082\148\000\088\036\216\189\237\067\000\126\090\100\204\117\063\113\003\066\145\149\221\031\028\168\103\041\064\017\090\010\112\032\008\167\183\246\254\236\102\040\202\083\200\044\005\016\011\055\207\239\177\017\051\003\213\114\025\154\166\161\189\219\212\006\123\022\098\011\086\108\005\124\035\197\225\068\184\045\134\082\033\139\074\089\252\140\135\106\069\071\119\159\023\177\190\214\153\089\185\026\135\067\194\193\103\133\151\230\066\153\196\129\135\172\136\103\181\163\004\192\034\161\206\237\159\003\216\080\173\175\247\120\060\184\233\142\155\091\186\243\095\173\234\057\043\160\120\222\003\255\250\124\077\075\001\249\074\022\157\161\048\116\214\184\182\186\000\080\082\166\145\093\246\033\022\106\190\226\056\043\103\006\050\203\203\232\089\051\000\135\203\216\177\206\141\036\001\229\124\186\096\249\047\072\086\020\068\058\122\032\201\050\114\025\241\135\088\197\033\097\124\071\243\125\142\140\138\118\186\240\163\199\022\080\173\008\044\205\113\214\151\073\028\248\061\235\162\090\189\040\001\176\064\207\182\123\218\153\038\011\181\254\029\157\220\128\161\145\181\022\070\213\092\034\109\017\067\075\001\224\012\149\005\023\002\027\106\089\010\224\136\056\251\000\103\227\103\015\139\242\121\100\154\052\009\184\228\114\051\003\169\197\010\202\069\131\051\003\156\163\090\041\035\214\215\103\110\160\086\096\204\147\079\021\037\000\150\103\220\140\001\190\096\024\254\096\004\169\165\121\136\156\121\093\200\106\184\225\174\149\083\020\044\073\012\201\068\025\211\167\004\118\232\048\120\067\157\091\254\054\147\120\129\150\001\076\214\026\011\118\045\134\085\148\247\067\112\143\241\240\070\161\115\130\086\132\155\110\187\025\094\191\079\120\092\113\198\131\204\225\218\166\216\231\210\009\048\235\191\227\047\043\233\220\143\067\231\078\219\242\222\162\122\135\124\184\227\231\251\240\217\207\079\226\238\143\015\026\238\077\063\119\246\044\202\069\227\091\224\026\200\045\201\204\248\134\125\003\252\161\008\186\251\197\146\252\076\178\130\124\214\158\198\079\086\153\216\037\158\020\115\201\241\027\022\132\178\234\081\002\096\001\006\038\180\246\239\241\122\208\187\166\005\158\154\076\230\246\186\113\243\157\066\071\036\188\110\241\135\081\104\197\171\079\096\101\043\041\040\213\094\067\239\097\134\164\115\063\094\157\158\177\237\253\069\201\010\195\182\155\218\241\137\223\029\195\232\022\241\058\006\206\057\206\159\106\141\164\199\225\084\026\154\000\000\064\091\087\031\036\073\108\226\053\181\096\253\241\208\141\052\184\049\000\127\080\236\076\009\198\249\093\022\133\179\170\081\002\096\178\248\181\159\246\000\184\081\100\204\240\198\245\144\090\187\183\186\097\067\035\107\177\126\124\068\120\156\094\150\145\124\161\182\039\137\124\206\222\003\108\018\242\179\088\076\183\196\083\241\235\220\094\025\191\248\153\117\134\214\159\103\207\156\049\063\032\011\040\078\165\225\013\102\036\073\130\199\039\214\229\179\096\211\097\080\102\202\229\171\056\061\181\140\023\143\159\194\051\175\189\128\208\176\216\143\158\131\117\013\015\063\176\114\246\068\054\137\149\185\225\220\078\185\234\030\000\066\045\188\214\143\173\156\190\255\070\220\116\219\205\152\062\051\141\066\078\172\115\095\250\112\008\209\237\073\072\174\119\254\130\156\201\156\195\080\216\013\157\137\087\098\155\130\105\120\045\249\018\174\015\237\182\231\253\013\098\018\112\247\175\014\098\126\170\136\133\217\218\127\118\249\116\026\229\098\177\233\251\002\200\014\197\150\185\117\073\112\171\036\023\168\025\176\155\170\233\072\044\021\176\152\073\033\095\201\160\204\082\224\222\069\072\174\034\224\192\133\255\000\232\217\233\197\249\031\011\213\054\176\162\023\247\003\248\029\243\163\094\189\104\006\192\108\140\223\046\242\114\175\223\135\238\062\075\119\035\053\061\163\075\001\122\085\066\246\152\255\170\175\083\245\010\088\209\190\101\000\000\208\220\083\152\074\052\174\039\129\089\092\094\025\119\252\188\120\195\188\229\249\121\011\162\049\151\195\170\243\156\223\017\071\177\040\150\232\058\093\205\089\171\157\206\149\112\106\106\001\047\030\063\133\167\094\125\030\143\159\252\014\158\073\124\019\199\245\071\144\244\063\131\074\244\048\088\100\234\194\205\255\045\162\195\069\056\188\098\051\027\012\252\003\102\197\078\046\160\025\000\179\113\220\041\242\242\053\107\215\172\138\173\127\087\115\105\041\064\116\107\096\230\181\000\066\019\233\171\190\110\049\147\069\196\230\214\234\103\138\007\017\199\141\182\021\037\026\181\097\107\004\029\221\110\161\089\128\108\050\137\238\129\001\235\130\050\001\083\164\134\031\103\152\073\046\066\173\136\109\075\013\183\217\187\173\178\082\225\088\092\206\099\049\155\066\078\077\162\194\210\128\119\009\204\089\122\211\083\189\072\054\037\073\028\029\163\069\204\252\248\234\009\252\037\140\099\076\040\112\114\085\148\000\152\168\127\226\222\033\093\160\245\047\000\172\025\030\176\040\154\214\115\211\109\055\099\234\244\020\138\249\218\215\203\203\115\030\104\037\249\170\125\001\150\138\179\232\080\187\161\054\190\238\235\117\186\107\014\083\137\052\250\059\155\167\073\080\045\152\004\140\239\136\226\241\135\106\047\102\044\230\114\022\070\100\014\073\150\026\186\166\172\170\021\156\063\253\154\208\024\151\091\070\168\173\113\053\044\233\092\009\243\201\020\050\197\044\138\090\026\170\115\009\146\055\013\048\014\092\044\093\048\043\125\237\024\043\008\037\000\028\220\217\055\241\171\055\078\029\254\242\147\038\133\176\234\081\002\096\034\157\203\119\129\137\244\185\150\208\055\104\089\055\210\150\227\246\186\177\235\166\107\241\248\191\127\191\230\049\156\003\165\089\055\124\131\087\159\086\045\023\002\144\131\246\037\000\000\112\062\127\018\253\216\102\107\012\070\244\012\138\173\231\023\011\045\080\244\200\208\209\168\183\210\052\021\167\142\188\136\074\073\172\014\101\205\122\191\037\051\132\229\178\134\068\050\143\100\054\131\108\053\137\138\116\225\169\094\170\227\169\094\084\199\104\001\146\196\161\235\181\255\251\056\148\123\000\080\002\096\018\074\000\204\196\244\059\068\242\227\174\120\023\220\030\099\251\173\087\170\141\091\198\177\255\201\231\144\023\040\008\044\039\092\053\037\000\115\169\243\136\007\021\112\088\127\082\222\149\084\220\167\144\045\076\034\224\181\119\103\130\168\104\076\108\182\156\107\141\057\132\169\030\012\136\050\198\074\156\115\075\151\002\052\085\197\201\087\158\071\049\047\190\233\096\253\230\250\207\149\184\236\083\189\239\098\061\202\197\167\122\059\138\193\028\094\029\161\129\018\146\167\068\146\075\102\108\223\048\185\044\074\000\076\050\054\182\207\153\198\194\077\034\099\104\250\255\237\036\137\097\120\227\058\028\220\255\082\205\099\170\233\218\214\072\139\090\030\114\105\045\084\247\025\131\209\153\128\233\056\181\048\141\077\107\006\237\139\193\000\181\042\118\067\231\188\249\019\000\000\076\114\072\009\173\162\245\091\245\006\023\158\252\095\048\116\243\151\021\134\205\187\219\106\126\125\177\164\034\145\204\096\057\151\065\065\075\161\034\045\131\249\082\096\114\181\097\079\245\162\058\054\020\005\019\000\222\133\177\125\078\188\178\111\101\053\071\176\009\037\000\038\073\073\011\219\152\224\246\191\126\074\000\046\171\043\222\045\148\000\168\249\218\171\164\211\089\021\190\134\151\126\189\037\006\118\012\058\006\032\181\080\049\096\049\039\086\177\045\183\200\145\214\178\162\036\173\074\000\184\174\227\204\107\007\081\200\025\059\144\106\114\087\020\254\208\229\127\142\151\158\234\083\249\052\074\072\067\115\036\223\182\086\223\076\055\250\043\105\095\095\194\177\071\132\134\176\062\044\189\127\010\120\208\162\144\086\149\214\248\043\109\001\018\103\215\113\129\245\127\175\223\135\142\088\195\150\032\091\074\048\044\086\155\165\087\107\191\145\206\230\206\097\164\045\002\077\186\250\206\001\171\112\103\010\011\201\060\098\145\218\011\160\236\118\234\136\216\077\172\217\123\000\092\034\043\204\178\098\133\233\083\175\033\151\022\062\249\014\192\133\167\255\159\120\127\015\010\069\021\137\229\012\146\249\044\242\106\006\170\188\004\248\151\255\243\169\254\098\061\105\043\220\236\047\039\216\087\130\195\171\163\090\168\253\095\192\025\255\000\040\001\048\005\037\000\038\225\140\011\117\121\233\027\236\163\237\127\087\192\152\096\163\020\093\228\245\028\090\161\003\240\219\151\000\000\192\249\244\012\098\145\214\104\000\197\057\199\171\047\138\253\188\220\062\241\051\030\236\160\056\028\021\192\252\006\081\011\179\231\176\156\056\111\120\252\224\046\142\067\249\031\064\226\105\064\230\192\197\156\120\165\125\099\048\006\068\215\022\049\127\088\224\243\194\248\014\235\034\090\093\090\053\113\108\070\215\138\188\184\167\223\222\198\052\205\076\100\027\032\000\072\014\177\245\230\068\058\001\187\191\074\179\210\041\232\104\141\014\111\135\127\148\194\194\249\183\055\115\121\039\161\104\237\107\215\118\146\101\201\244\095\066\049\151\193\236\153\099\134\199\135\250\202\024\254\233\211\023\010\245\004\102\021\091\085\251\122\177\207\022\007\122\096\247\031\240\010\065\009\128\009\226\155\063\177\014\128\080\095\203\158\085\222\253\239\157\044\204\045\008\189\254\106\061\000\222\042\083\073\218\122\064\016\000\192\153\070\098\185\249\183\202\085\171\058\030\125\112\074\120\092\184\163\221\130\104\204\039\041\130\039\243\092\133\174\107\056\123\236\176\225\246\189\238\176\138\173\031\157\007\147\087\254\141\255\146\232\176\088\002\192\000\169\119\114\047\237\006\048\001\037\000\038\096\154\122\157\200\235\093\110\023\034\237\081\171\194\105\121\039\095\059\046\244\122\071\088\188\165\123\062\107\255\234\215\092\182\249\219\229\062\242\215\231\176\156\016\235\092\231\011\006\225\241\183\070\125\131\036\073\166\238\195\157\159\058\133\114\201\088\098\231\244\105\216\254\171\115\112\135\237\219\166\106\007\095\172\010\197\035\184\107\132\227\131\214\068\179\186\080\002\096\002\206\153\080\002\208\029\239\161\245\255\043\152\157\158\021\158\001\112\181\139\221\160\128\011\007\004\113\237\042\167\008\089\044\199\141\175\017\055\194\203\251\147\120\238\049\177\223\005\128\166\111\001\252\070\076\102\166\021\043\148\010\057\036\102\206\026\026\235\244\105\216\121\255\012\252\093\171\111\119\027\099\064\100\064\172\014\131\129\181\214\201\090\077\138\018\000\019\112\006\161\004\160\171\191\219\170\080\090\154\206\117\060\253\221\031\008\143\243\116\139\023\113\105\188\138\074\186\221\214\004\064\115\207\162\088\110\206\167\189\228\066\005\255\244\149\051\194\227\152\036\161\123\176\117\122\028\072\140\213\223\105\231\162\153\051\199\047\180\166\020\164\184\117\236\184\111\022\254\046\091\014\039\108\010\145\065\209\036\158\175\181\036\144\085\134\018\128\058\117\140\221\231\103\128\208\129\246\061\189\180\254\127\057\207\124\239\041\204\157\159\019\026\227\012\087\160\004\141\125\113\038\243\005\155\219\241\113\204\044\053\223\009\129\154\206\241\141\047\158\068\049\047\158\156\244\012\014\194\211\034\059\000\046\050\165\090\049\151\073\034\155\090\020\030\199\100\142\045\031\157\071\160\103\245\061\249\191\081\120\064\172\014\000\128\167\127\226\055\034\086\196\178\154\080\002\080\039\007\195\036\004\126\142\146\036\033\214\027\179\048\162\214\116\248\249\131\120\233\071\047\010\143\243\015\027\063\116\038\167\046\050\094\180\183\090\125\185\220\124\117\000\143\253\195\012\206\028\021\255\185\050\073\194\208\198\150\059\176\205\195\192\196\206\231\189\140\249\169\147\226\131\024\048\241\179\011\104\095\039\124\243\091\113\066\125\101\008\175\138\178\236\123\045\009\102\021\161\004\160\078\018\147\198\069\094\223\222\213\001\197\209\090\125\224\173\118\250\248\041\060\249\168\248\212\063\024\016\028\019\111\177\250\070\185\180\189\103\004\023\229\089\091\223\255\173\078\189\154\193\015\030\054\022\211\208\216\024\060\129\214\040\254\123\035\166\176\186\154\066\020\242\025\228\210\073\225\113\125\187\050\232\221\222\252\167\038\054\130\226\230\240\118\138\205\228\233\192\045\022\133\179\106\080\002\080\055\062\041\242\234\142\088\167\085\129\180\164\212\114\018\143\254\211\183\161\027\232\029\239\031\200\195\017\170\111\234\116\185\056\015\112\083\119\130\009\225\206\101\020\075\205\081\007\144\203\084\241\224\023\078\067\055\176\142\237\011\005\049\216\122\079\255\000\000\089\150\234\186\011\047\205\136\111\147\244\068\084\140\190\215\088\151\192\149\042\212\039\088\203\195\153\208\119\047\121\059\074\000\234\038\150\000\180\117\182\070\131\148\070\224\156\227\177\135\031\131\090\053\176\134\207\128\232\174\250\191\064\171\040\066\205\218\185\036\195\049\159\054\214\043\222\212\040\056\199\063\127\249\012\178\073\241\132\074\146\037\076\236\190\014\146\220\154\095\039\178\044\025\110\200\160\105\026\082\075\226\203\056\227\031\092\128\226\110\137\003\147\026\038\020\023\254\236\209\089\234\117\106\205\191\216\230\193\000\054\033\050\160\061\214\026\013\082\026\225\224\129\131\152\157\050\182\021\046\184\049\013\087\135\057\045\092\179\057\123\183\100\046\023\196\167\143\205\246\244\035\243\056\242\099\099\005\137\235\055\111\069\048\210\186\245\088\178\036\027\254\032\165\151\231\161\235\098\155\073\218\071\139\105\166\168\160\000\000\032\000\073\068\065\084\104\031\165\117\255\183\010\245\137\038\000\186\105\059\056\086\043\074\000\234\208\189\097\111\063\094\063\142\163\054\109\045\210\033\205\106\213\074\021\047\060\189\223\208\088\197\167\162\227\122\241\138\235\043\073\150\103\001\221\190\198\064\005\216\091\008\056\125\050\143\071\191\049\109\104\108\071\060\142\254\245\235\076\142\168\177\152\067\050\188\255\046\179\044\222\039\097\248\214\230\219\249\209\012\002\061\101\193\006\191\140\245\079\220\187\205\170\120\086\003\074\000\234\192\028\098\211\255\129\096\000\110\175\205\103\209\054\137\067\207\031\068\065\176\231\063\000\048\198\209\117\199\028\036\151\121\211\167\058\170\080\115\246\157\204\168\057\196\111\034\102\041\023\052\060\248\133\147\208\084\241\117\127\183\215\139\241\157\187\032\094\190\221\092\036\009\134\062\076\156\115\228\082\098\203\080\209\225\034\034\067\244\244\127\057\138\091\135\059\036\086\015\195\033\221\097\081\056\171\002\037\000\117\096\058\019\218\001\016\165\245\127\000\023\190\056\095\126\225\144\161\177\029\123\022\224\233\049\255\011\180\144\183\175\016\016\074\009\217\130\061\077\096\254\249\047\207\098\105\094\188\147\034\099\012\147\215\093\007\135\203\105\065\084\141\037\201\014\067\141\247\011\185\052\052\077\236\134\213\183\171\190\093\043\043\157\063\038\182\012\160\051\208\201\128\117\160\004\160\030\012\066\115\159\029\093\246\061\101\054\147\217\233\089\100\082\226\133\111\109\059\151\016\154\176\230\024\223\084\121\009\118\030\048\150\204\214\189\021\093\216\243\079\044\226\224\179\075\134\198\174\029\159\064\184\099\101\124\158\153\012\067\217\095\062\035\246\089\148\020\142\206\177\230\063\000\202\078\001\193\110\136\076\103\212\017\176\014\148\000\212\129\049\012\136\188\062\218\078\051\000\000\112\242\085\177\195\126\000\032\056\154\069\116\167\117\219\166\042\060\007\189\104\095\033\091\186\108\077\098\115\037\137\243\069\060\252\053\099\125\235\035\157\049\012\142\183\230\150\191\203\097\140\025\074\000\010\057\177\181\252\246\145\034\085\254\095\133\112\059\100\038\118\010\043\121\051\074\000\234\192\057\132\154\158\135\162\066\245\130\043\214\204\148\088\163\025\197\167\162\099\143\245\133\114\213\130\125\077\108\242\090\227\018\000\181\162\227\193\047\156\068\165\044\126\051\114\186\092\152\188\238\218\021\117\152\149\036\075\134\042\064\075\069\177\089\155\246\017\122\250\191\026\159\096\051\032\128\007\044\009\100\149\160\004\192\168\061\251\020\006\196\069\134\004\195\065\171\162\105\025\106\181\138\197\185\132\208\152\200\182\036\036\167\245\231\163\023\074\246\029\198\162\178\198\245\002\120\228\239\166\048\123\214\064\029\005\099\024\219\181\011\046\143\189\221\019\205\198\024\132\011\025\056\056\042\037\177\159\097\176\119\117\247\251\175\133\183\093\248\111\208\209\179\237\158\149\245\129\108\032\074\000\012\090\179\188\216\007\160\230\039\007\069\081\224\241\122\044\140\168\053\164\083\105\232\122\237\079\158\140\113\004\070\026\083\056\149\169\218\087\007\160\201\141\249\055\030\057\144\194\015\191\043\150\128\093\178\102\253\122\116\244\246\154\028\145\253\024\152\112\002\160\086\042\224\066\159\227\139\219\220\200\059\114\005\084\136\214\100\074\101\137\010\001\013\162\004\192\032\085\211\007\068\094\031\140\004\087\212\180\169\081\249\156\216\083\147\171\189\002\217\211\152\083\123\171\188\104\095\029\128\146\051\212\014\089\068\106\177\130\111\126\229\148\161\177\193\072\020\235\054\111\049\057\162\230\192\036\008\239\205\085\171\098\079\243\238\136\010\197\109\253\044\086\203\099\226\179\000\156\041\043\243\131\217\000\148\000\024\036\049\038\180\254\031\012\083\211\042\000\040\009\238\253\119\132\027\059\109\106\091\029\000\211\145\043\090\119\038\128\166\115\252\253\159\157\066\033\039\158\076\041\138\130\137\235\091\183\213\239\085\113\008\079\205\105\130\009\128\163\065\073\236\074\032\154\000\048\198\055\090\020\202\138\183\066\255\162\173\167\051\054\032\242\250\064\136\214\255\001\008\207\176\027\171\207\054\206\206\058\128\092\209\186\100\231\251\223\156\193\153\163\198\150\025\070\183\111\135\047\176\114\107\173\056\152\079\116\140\232\108\141\220\128\026\150\149\194\019\017\076\132\117\078\091\001\013\162\004\192\032\198\248\128\200\235\067\084\000\008\000\144\037\177\059\186\094\110\236\071\052\167\054\118\059\222\027\149\042\214\172\017\159\124\037\131\199\031\154\049\052\182\103\112\008\061\131\066\147\093\045\135\049\008\039\000\016\188\159\043\046\074\000\106\229\010\009\206\150\048\182\242\010\083\026\132\018\000\131\056\023\219\127\026\136\208\018\000\000\056\220\046\161\215\151\150\026\219\105\174\172\103\001\205\158\118\205\101\213\252\025\128\092\086\197\055\190\120\010\070\202\011\124\129\000\070\183\095\099\122\076\077\072\134\196\196\138\083\004\235\121\180\042\213\255\212\074\180\029\048\128\214\061\137\202\102\148\000\024\036\001\066\093\125\124\126\241\135\140\149\040\034\216\011\065\205\056\080\077\055\054\009\208\139\246\036\107\085\221\220\025\000\206\057\190\249\231\167\144\073\138\047\107\072\178\132\137\235\175\135\162\216\119\072\082\035\073\128\080\246\037\203\098\063\151\074\158\190\106\107\037\094\147\201\233\203\213\032\250\084\026\196\001\161\099\253\104\011\224\005\254\160\031\014\167\067\104\076\250\229\198\174\063\087\203\098\179\020\102\169\112\115\103\000\158\254\246\060\094\123\209\216\146\198\186\205\091\090\250\136\095\097\146\036\244\195\151\100\177\165\172\074\118\117\036\082\070\085\146\081\044\159\237\198\217\083\078\036\101\209\227\177\165\214\063\144\194\038\244\169\052\078\104\006\192\237\161\004\000\184\112\136\076\172\167\011\211\103\166\106\030\147\062\020\070\120\083\026\138\223\186\042\249\055\170\084\056\236\072\001\084\110\248\088\250\183\057\127\058\143\071\031\052\118\196\111\103\111\047\214\172\095\111\090\044\173\128\113\177\025\000\135\083\236\041\181\090\144\160\085\036\200\078\106\005\012\000\122\197\137\082\050\130\066\001\200\235\073\084\165\139\039\098\050\064\246\136\062\151\114\186\143\025\068\051\000\006\012\012\124\196\013\212\094\056\036\049\009\046\055\037\169\151\172\025\030\016\122\189\094\149\048\247\221\046\064\111\204\058\106\081\181\231\184\086\029\230\044\001\148\139\026\190\254\167\167\012\031\241\059\182\171\245\143\248\021\197\100\177\004\064\113\056\032\011\204\002\112\014\164\207\217\051\179\212\012\212\188\031\133\249\024\082\103\187\113\254\100\004\167\166\075\152\041\204\032\133\025\084\165\055\255\189\073\078\029\236\255\103\239\189\163\228\184\238\059\223\239\173\170\206\097\098\079\078\200\057\071\138\098\210\146\148\068\105\041\089\148\172\180\150\101\203\150\101\138\182\229\125\246\250\236\123\222\115\184\222\119\246\249\200\235\040\146\146\101\091\150\101\089\193\202\178\196\028\192\000\130\068\006\006\192\032\204\012\102\166\195\076\119\079\231\092\093\085\247\253\001\102\012\128\190\213\085\029\166\239\231\028\158\067\130\117\111\253\006\211\093\245\187\191\240\253\137\108\159\221\161\077\127\216\105\164\189\173\002\247\156\116\080\246\122\186\009\067\085\149\205\097\227\034\064\111\097\108\245\024\014\062\253\034\211\154\066\192\129\249\199\250\208\247\222\005\016\201\220\138\234\188\146\194\149\126\197\218\086\110\171\140\117\104\215\226\167\223\152\069\108\129\061\154\064\008\193\150\119\221\004\139\173\245\094\084\004\066\025\096\171\062\183\218\157\040\228\042\111\173\076\204\218\208\185\186\242\223\177\166\088\160\149\108\208\100\043\084\069\004\213\174\156\215\040\093\218\063\035\132\130\136\087\063\151\136\064\033\008\087\255\108\148\000\162\116\117\084\141\130\066\144\174\174\027\033\004\032\150\183\251\073\084\019\064\021\009\084\181\128\106\004\170\108\131\082\148\080\086\004\040\170\134\178\166\160\068\082\080\144\002\240\090\058\170\130\099\167\096\215\160\050\140\232\182\160\176\026\192\225\138\023\112\000\112\007\064\031\042\186\088\098\039\118\103\125\170\202\027\149\078\095\023\250\135\250\049\031\096\027\010\148\157\114\035\240\131\097\248\238\012\195\238\051\079\086\085\065\017\040\183\001\150\172\105\247\088\010\042\084\239\000\028\123\126\017\039\094\210\055\226\119\229\230\205\232\232\233\173\218\134\102\068\016\005\230\074\073\135\203\195\230\000\076\057\161\222\164\064\083\069\104\138\004\077\017\160\042\034\052\149\064\085\041\020\077\131\162\149\161\064\134\140\002\168\080\004\096\092\090\200\028\084\000\101\000\215\248\236\234\060\247\136\118\149\201\001\080\136\176\002\220\001\096\134\059\000\122\016\181\110\150\195\161\125\153\013\079\049\130\109\123\183\051\059\000\000\080\140\218\016\248\222\008\156\043\114\104\219\156\130\115\052\015\066\140\063\169\107\178\003\066\173\029\000\169\058\007\032\058\095\196\207\191\057\167\107\109\071\079\015\086\110\222\092\213\253\155\025\074\041\179\084\159\195\197\086\156\026\187\100\195\148\063\125\253\193\086\060\041\011\224\138\003\192\130\070\132\001\147\076\089\214\112\007\064\015\148\116\178\132\135\237\142\214\011\169\222\136\085\027\214\160\189\243\016\146\113\182\153\234\192\149\016\104\110\218\133\220\180\011\162\083\129\119\109\022\238\013\105\067\163\002\170\098\173\253\179\088\040\065\085\041\068\145\253\216\164\148\041\190\251\119\083\040\021\217\037\103\045\054\027\182\188\235\093\045\157\166\018\068\048\087\152\186\188\108\093\018\154\066\144\157\242\192\187\161\118\147\031\155\021\193\202\246\057\038\160\173\025\186\170\018\238\111\234\064\128\198\212\119\106\119\240\020\192\059\017\004\001\183\189\239\142\170\247\081\243\018\018\039\219\225\255\238\008\102\190\061\138\216\171\093\080\210\108\109\134\075\238\091\174\207\087\035\095\210\039\069\252\203\127\243\035\052\163\099\222\060\033\216\188\111\031\236\206\022\143\082\045\149\036\191\001\118\167\007\146\196\086\220\155\057\191\124\037\149\141\068\096\156\008\072\009\229\074\107\058\224\014\128\014\052\176\117\137\073\082\141\005\237\155\132\145\085\163\088\177\206\056\025\239\114\220\138\248\171\157\152\249\151\049\004\127\050\136\244\132\023\154\172\239\084\171\213\168\227\224\157\020\101\246\086\199\115\071\019\120\069\231\136\223\145\181\107\224\027\026\210\181\118\057\065\040\123\197\039\033\128\187\157\173\248\188\016\112\066\174\177\186\101\051\194\234\000\016\138\058\077\241\106\110\184\003\160\003\066\009\147\003\192\042\026\210\074\220\249\159\239\134\215\224\057\009\148\002\121\191\019\225\167\122\113\249\031\087\097\225\137\062\020\130\108\058\012\090\157\164\219\139\101\182\008\064\050\038\227\135\095\159\001\165\236\006\123\058\058\176\118\251\078\230\117\203\018\157\133\036\109\093\061\076\215\083\010\196\094\097\146\016\105\073\004\070\189\004\066\217\007\058\113\184\003\160\011\002\194\228\194\179\244\011\183\026\118\135\013\239\191\239\003\166\073\206\106\010\065\230\130\007\129\031\013\097\238\059\163\200\078\185\043\042\223\208\180\250\008\182\020\025\198\204\082\013\248\222\067\083\200\103\216\163\006\146\036\097\235\205\203\120\196\047\035\130\142\008\000\000\120\059\186\033\048\014\184\202\078\187\081\138\240\186\160\235\065\044\204\223\191\022\207\097\233\131\127\251\117\160\009\148\201\001\224\017\128\235\211\051\208\139\015\124\226\067\166\235\206\151\022\173\152\255\101\063\002\063\026\130\028\191\254\175\080\209\234\051\191\093\086\043\119\000\014\062\017\198\204\121\125\157\010\235\246\236\129\203\203\039\084\190\014\021\244\057\000\130\032\162\221\199\052\023\012\160\064\228\121\031\116\004\109\090\006\129\081\008\072\035\164\250\194\159\022\132\059\000\058\224\017\000\227\025\089\049\140\015\126\252\094\088\109\230\231\071\011\033\007\230\190\055\130\228\169\107\015\038\082\105\109\100\135\223\073\165\003\129\018\209\018\158\252\190\062\169\223\254\021\099\024\092\230\035\126\089\209\025\000\000\000\116\245\176\119\160\021\231\029\072\028\229\226\117\215\130\050\102\100\004\104\220\001\208\001\119\000\244\192\040\021\047\242\048\107\069\012\175\028\193\175\254\230\039\209\209\109\254\131\145\042\004\209\231\125\088\120\170\119\073\137\097\069\213\087\141\095\045\101\173\178\008\192\211\063\012\065\046\177\167\041\156\030\015\054\236\222\195\188\110\185\035\018\065\183\007\224\244\180\195\229\101\155\114\009\000\241\087\058\081\012\243\014\161\165\096\237\072\165\016\184\003\160\003\254\102\210\001\005\091\010\128\071\000\042\167\163\187\003\191\250\155\159\192\150\221\219\032\016\243\063\158\153\009\047\066\143\245\129\170\111\127\226\148\169\121\074\131\215\067\173\096\032\080\060\082\194\073\029\106\127\068\016\176\245\230\155\033\089\248\179\242\157\208\042\117\159\123\006\216\035\042\148\018\204\255\178\031\229\052\151\099\185\010\198\020\000\001\248\135\090\007\220\001\208\001\107\010\128\023\090\177\097\181\089\113\251\251\239\192\175\254\214\039\049\052\054\108\250\253\114\083\110\044\060\217\251\182\087\128\145\147\249\088\080\201\141\239\251\242\147\017\168\058\218\020\214\110\223\014\111\039\015\059\047\009\169\206\001\240\118\118\193\225\102\175\169\080\178\018\066\063\027\132\090\224\135\132\183\034\048\062\050\041\040\119\000\116\192\223\076\156\134\197\215\231\195\175\252\218\125\248\196\111\127\026\027\182\110\132\104\098\145\096\246\146\007\241\195\111\190\028\053\040\064\185\246\133\197\154\112\125\007\064\163\020\167\094\142\051\239\235\027\028\196\232\186\117\122\205\226\220\016\130\193\049\125\127\191\114\194\138\208\079\007\161\230\121\036\224\117\244\180\181\114\216\225\014\128\014\040\040\211\232\080\077\229\051\192\171\193\215\231\195\157\031\186\027\191\245\095\127\027\255\233\131\119\097\096\100\208\020\217\218\248\225\046\020\231\223\212\011\080\229\218\107\139\220\104\032\208\204\068\022\153\004\211\199\015\054\135\163\037\071\252\050\065\245\142\173\121\019\151\183\029\237\221\250\020\105\139\081\027\252\223\031\066\041\202\107\002\000\128\042\108\175\038\002\082\159\162\157\038\135\059\000\058\032\032\076\079\096\085\173\079\075\217\114\195\106\179\097\227\142\077\184\239\215\063\134\095\255\189\223\192\254\219\223\133\142\046\054\061\246\235\065\041\176\240\084\239\027\245\000\106\169\246\138\109\084\188\190\156\239\204\249\202\167\207\189\206\218\237\059\096\109\193\017\191\044\016\221\115\235\222\206\224\138\245\186\107\044\202\025\011\002\063\024\066\230\060\111\207\164\140\074\156\244\202\072\066\014\035\220\001\208\003\001\083\133\152\202\035\000\134\227\105\243\098\207\045\123\241\095\238\255\117\124\236\055\063\129\173\123\182\195\225\096\083\251\091\138\114\210\130\228\201\043\078\069\185\030\243\000\004\005\114\249\218\014\227\204\069\182\190\127\111\087\039\250\199\070\171\181\106\217\163\178\190\113\174\129\100\177\098\064\103\042\000\184\034\092\181\240\100\047\130\063\027\068\057\213\186\105\109\077\097\251\117\016\104\220\001\208\001\079\058\233\128\130\050\041\204\243\008\128\185\244\013\246\161\111\176\015\183\220\117\043\102\167\102\048\113\250\028\046\095\152\130\166\083\207\055\126\180\029\109\155\147\144\173\010\234\161\047\154\047\169\176\090\150\046\010\011\093\102\027\248\211\063\182\130\135\254\043\128\024\019\000\000\000\116\248\250\145\077\197\017\143\132\116\239\145\159\117\098\246\219\035\232\216\153\068\219\246\036\036\071\139\061\067\024\253\049\141\049\042\203\185\002\119\000\116\032\104\068\102\017\170\208\184\003\080\019\004\081\192\138\181\043\177\098\237\074\164\019\041\188\242\252\033\092\024\063\207\188\143\086\018\145\056\209\001\247\187\178\048\046\193\080\057\037\165\012\224\234\244\067\054\163\032\155\102\059\232\248\006\248\152\244\074\032\154\129\030\000\128\193\149\235\081\200\165\081\200\233\083\106\004\000\170\010\136\031\233\068\226\068\007\060\235\210\232\216\158\130\181\171\062\237\169\181\134\181\006\064\224\041\000\093\240\020\128\014\040\088\083\000\220\001\168\053\222\142\054\220\253\225\247\225\238\015\191\079\087\027\102\242\084\059\050\185\012\160\214\062\119\094\044\045\125\152\137\248\175\095\032\248\078\172\054\027\156\030\062\126\182\018\052\035\067\000\184\034\017\188\098\195\078\088\172\213\023\245\081\133\032\125\182\013\179\255\054\130\153\111\141\033\250\124\055\242\126\231\085\218\021\203\009\141\081\136\147\018\170\099\022\054\135\071\000\116\064\137\038\179\060\047\120\004\160\126\172\219\178\030\162\069\194\019\063\124\020\026\173\188\022\067\043\009\072\158\108\131\058\098\135\232\094\048\209\194\171\041\093\099\030\064\056\192\230\000\184\218\216\213\233\090\022\074\013\127\155\090\172\054\172\216\176\003\083\103\143\066\085\140\057\160\150\147\022\036\147\029\072\158\234\128\096\209\224\024\202\195\187\049\003\215\202\156\222\129\134\013\009\171\115\067\032\232\015\181\180\048\060\002\160\003\129\049\002\160\040\220\001\168\039\171\215\175\198\182\253\059\152\215\037\079\182\035\119\131\161\065\102\112\077\007\192\207\118\200\113\183\183\025\097\078\075\064\013\142\000\188\142\195\229\198\170\141\059\033\138\198\159\181\180\178\128\220\101\055\230\127\217\143\153\111\142\033\125\206\187\124\006\012\177\070\055\052\112\007\064\007\220\001\208\129\006\033\199\114\125\177\080\031\085\057\206\155\236\187\237\038\184\189\108\125\253\090\089\192\229\131\181\015\179\042\215\024\008\180\192\024\001\240\180\113\007\160\098\052\205\052\041\062\135\219\139\149\155\119\065\178\152\231\076\042\025\009\225\167\123\017\248\193\016\202\201\230\239\030\208\024\059\112\052\129\038\077\050\101\089\195\029\000\061\016\048\009\177\151\184\003\080\119\044\022\009\123\222\189\151\121\221\194\113\001\165\026\107\181\095\203\001\136\048\058\000\238\118\158\002\168\020\077\053\055\029\234\116\121\177\102\235\094\216\029\230\246\149\020\023\028\152\251\238\008\178\023\155\187\246\067\045\176\253\058\136\070\106\155\167\091\038\112\007\064\007\068\083\023\089\174\047\228\217\030\220\028\115\216\184\099\051\188\237\108\034\043\154\066\048\253\084\143\073\022\045\141\178\068\134\041\147\144\145\207\178\165\146\092\094\046\040\083\041\132\016\211\197\248\173\054\007\214\108\221\139\182\046\125\106\129\149\162\149\005\204\063\222\135\197\023\125\102\148\054\212\004\230\217\008\034\009\154\099\201\242\134\059\000\122\016\041\083\004\160\152\231\017\128\070\064\016\004\236\126\055\251\040\220\185\087\236\040\166\106\055\172\069\091\098\032\080\056\192\246\025\178\057\028\176\112\245\191\138\209\212\218\204\147\023\068\009\099\235\182\096\112\197\058\008\130\185\159\169\196\137\118\004\127\060\008\053\215\124\131\134\148\060\155\205\018\081\167\077\050\101\089\195\029\000\029\216\115\022\166\008\064\177\088\228\195\045\026\132\013\219\054\193\237\245\048\149\100\107\010\048\253\076\237\194\233\218\018\243\000\088\243\255\110\158\255\103\130\117\196\119\117\016\116\247\143\096\237\246\253\112\121\205\085\154\040\004\029\152\251\222\008\010\161\234\085\050\107\133\086\018\064\025\149\000\093\229\158\073\147\204\089\214\112\007\064\007\147\147\095\041\001\149\087\157\082\074\081\042\180\134\128\071\163\035\008\002\118\236\223\197\044\168\239\063\228\069\049\089\155\090\000\141\092\253\178\015\051\106\000\112\007\128\013\170\214\126\156\172\205\238\196\234\205\187\049\182\097\059\172\054\243\094\208\074\078\066\240\071\131\072\028\171\135\172\021\059\106\145\249\123\070\207\158\125\144\119\001\232\128\059\000\122\097\044\004\044\022\121\029\064\163\176\113\231\230\050\107\126\092\083\008\166\158\170\081\020\064\042\066\123\199\120\122\214\002\064\023\111\001\100\130\146\037\164\023\107\068\091\135\015\235\119\220\132\193\021\235\096\181\153\051\013\144\082\130\197\131\221\088\120\162\143\089\103\191\214\040\204\041\011\202\040\027\196\121\029\238\000\232\133\018\182\066\192\028\119\000\026\005\081\016\045\043\054\109\098\094\231\127\213\131\066\188\006\007\069\162\066\150\223\020\045\162\148\050\139\000\185\185\008\016\027\154\086\055\007\000\000\136\032\162\187\127\004\235\119\190\027\163\107\183\152\150\026\200\092\240\192\255\253\225\134\110\021\100\046\000\100\212\101\225\188\009\119\000\244\066\041\147\003\144\203\113\165\202\070\129\008\176\245\143\141\193\197\024\038\167\106\237\162\000\133\210\155\135\154\084\188\140\098\129\161\003\128\016\158\002\096\068\091\106\248\066\029\032\132\160\189\187\015\171\055\239\198\250\029\239\066\255\200\042\056\092\108\250\021\055\066\142\217\048\247\253\097\100\047\215\099\212\213\141\081\025\011\000\001\194\195\255\058\225\014\128\078\008\072\152\229\250\076\034\101\150\041\028\070\008\033\078\066\136\182\106\051\123\020\032\112\196\141\066\204\252\090\128\162\252\166\026\032\107\254\223\238\112\232\158\073\223\162\168\208\104\195\085\201\217\028\046\244\012\173\196\218\109\055\097\211\238\091\049\178\102\051\058\124\125\134\168\010\106\037\017\243\191\024\064\236\080\087\195\169\007\178\070\000\040\144\048\201\148\101\015\119\000\116\066\009\157\097\185\062\149\076\155\100\009\135\021\002\016\010\090\232\029\025\133\167\157\045\212\074\085\130\075\079\153\095\076\085\044\191\197\001\224\225\127\147\105\252\019\164\100\181\161\195\215\143\145\053\091\176\126\215\205\104\239\238\171\126\083\010\196\143\116\034\244\179\001\061\097\119\083\200\205\186\144\028\103\251\252\010\148\248\077\050\103\217\195\029\000\157\016\144\025\150\235\051\220\001\104\040\008\017\178\132\016\172\208\017\005\008\029\246\032\023\049\247\132\093\082\223\236\084\100\118\000\120\001\032\027\084\107\170\252\156\036\089\049\186\118\011\134\086\109\004\033\213\023\244\229\231\092\152\251\222\008\138\097\115\010\016\043\129\170\002\162\047\248\016\250\249\000\179\110\001\037\244\146\073\102\045\123\184\003\160\019\077\211\102\088\174\079\167\120\010\160\145\032\064\001\000\250\134\135\225\233\096\059\113\080\010\076\061\109\110\020\064\086\222\172\107\090\224\045\128\166\066\065\155\178\066\183\171\119\016\107\182\236\133\213\094\253\139\091\201\072\008\252\112\008\169\179\181\087\143\044\134\237\152\251\206\008\146\039\219\001\029\233\008\042\144\051\198\091\213\026\112\007\064\039\022\139\118\153\229\250\116\034\205\197\128\026\008\002\122\069\090\143\016\172\218\178\149\121\125\232\168\027\217\176\121\081\000\133\094\073\001\080\013\136\006\185\003\096\042\116\009\233\197\038\193\225\246\098\205\214\125\240\180\117\086\189\023\085\009\034\207\244\034\252\084\031\168\106\254\171\129\082\130\196\177\014\248\127\048\004\057\161\255\187\068\020\114\220\064\179\090\010\238\000\232\100\166\189\047\000\160\226\254\083\069\081\080\228\051\001\026\006\066\132\055\142\216\061\067\067\240\118\117\049\173\167\020\152\124\210\188\040\128\066\175\152\151\088\044\065\046\105\055\184\250\045\016\002\039\159\001\192\006\109\238\054\050\073\178\098\197\198\157\240\013\140\002\006\076\053\078\079\120\016\248\225\016\202\025\243\028\092\057\097\133\255\223\135\176\120\176\027\208\170\179\057\176\113\225\164\065\102\181\028\220\001\208\203\129\007\021\010\004\088\150\240\066\192\198\065\020\004\249\173\255\189\106\243\102\230\061\022\078\184\145\009\153\211\061\166\226\202\161\148\085\002\216\225\116\242\014\000\070\052\080\038\105\232\070\132\016\130\129\177\181\024\093\183\197\144\046\129\098\216\006\255\119\135\145\247\059\013\176\238\045\080\032\121\170\029\115\223\025\070\201\128\154\003\010\228\240\131\031\200\055\190\146\179\020\220\001\168\002\066\192\148\006\072\197\249\200\234\134\129\188\061\122\227\027\028\068\155\142\040\128\089\186\000\234\107\114\192\017\214\252\063\031\001\204\142\214\252\014\192\235\180\119\245\098\245\022\099\198\014\171\069\017\161\159\014\034\126\164\083\087\110\254\157\040\057\009\193\159\013\034\250\188\207\176\020\003\001\061\103\200\070\045\010\119\000\170\128\082\204\176\092\031\139\048\105\007\113\076\132\136\087\167\111\086\109\221\194\188\207\252\041\055\210\065\227\167\238\189\062\016\136\189\003\128\059\000\172\080\141\178\205\089\110\112\236\078\023\086\111\221\139\182\174\234\199\088\083\010\196\014\117\033\244\104\063\180\146\254\215\069\246\146\007\179\223\030\069\126\206\224\136\002\004\030\254\175\002\238\000\084\001\001\189\200\114\253\034\119\000\026\006\073\020\174\074\172\119\247\015\160\221\231\099\219\136\002\147\079\026\255\210\165\226\149\020\000\179\003\224\229\005\128\172\168\138\198\080\100\209\028\136\162\132\177\117\091\209\063\186\022\196\128\186\128\220\148\027\254\239\015\067\142\179\165\188\180\146\128\133\199\251\048\255\088\095\085\014\196\053\225\045\128\085\193\029\128\042\160\148\142\179\092\031\011\115\007\160\081\144\036\113\201\160\230\170\045\236\081\128\240\184\011\169\057\131\163\000\098\017\138\166\033\026\100\043\080\231\067\128\216\209\180\042\171\208\026\022\130\158\193\081\172\218\188\011\146\181\250\207\167\156\180\098\238\187\195\200\076\084\086\100\154\247\059\049\251\111\163\200\092\244\084\125\239\107\065\008\057\109\218\230\045\000\119\000\170\128\130\237\195\151\205\100\081\040\240\078\128\070\064\036\194\146\106\035\093\125\125\232\232\233\101\219\204\148\142\000\138\208\092\001\229\114\229\135\083\066\008\220\188\003\128\025\085\085\027\067\006\207\036\092\222\014\172\221\186\023\046\079\245\206\033\085\005\044\060\213\139\200\179\061\160\234\210\126\019\085\174\076\030\012\253\116\016\074\214\092\217\108\065\150\185\003\080\005\220\001\168\130\208\153\071\252\000\226\044\107\120\020\160\049\144\068\225\154\165\242\107\182\177\235\002\068\206\058\145\156\053\054\010\016\156\201\048\093\239\112\187\033\136\203\250\093\102\010\154\074\151\125\219\132\197\106\199\170\077\187\209\221\055\100\200\126\169\051\109\152\251\238\008\114\211\046\104\229\043\175\017\173\044\032\125\214\139\217\239\140\034\113\172\163\022\051\006\098\179\019\095\159\055\253\046\203\024\243\167\154\044\127\206\000\184\181\210\139\023\035\049\012\141\013\155\104\014\167\018\036\081\184\230\219\186\221\231\067\103\111\047\226\097\166\121\079\152\124\188\019\187\127\199\184\231\209\188\063\199\116\061\023\000\210\135\170\106\245\211\192\173\033\068\016\048\184\114\003\028\158\054\004\167\038\160\085\089\250\032\199\173\008\253\098\000\132\000\196\170\153\147\227\191\062\167\106\125\195\229\006\143\000\084\013\091\026\032\022\137\154\101\008\135\001\139\069\188\238\244\183\213\091\217\163\000\209\243\014\036\166\141\027\042\023\152\100\147\168\231\029\000\250\160\138\214\112\147\000\205\164\211\055\128\213\091\246\194\106\055\230\199\166\020\245\120\249\003\140\053\088\156\171\225\014\064\245\048\125\008\023\121\010\160\033\016\004\114\221\202\164\118\159\015\093\253\253\204\251\078\062\097\204\041\092\041\018\068\046\179\009\212\241\008\128\062\040\165\230\085\169\053\040\014\151\007\235\182\238\071\091\039\099\215\075\067\033\112\007\160\074\184\003\080\037\148\168\076\017\128\197\133\008\202\242\178\209\029\105\090\068\073\184\097\181\156\158\142\128\197\139\078\196\046\085\127\178\010\188\226\133\082\102\075\162\050\183\048\114\000\000\106\089\109\201\202\073\065\146\048\182\126\027\250\071\215\192\128\161\130\053\135\080\141\023\000\086\009\119\000\170\068\086\201\025\000\021\039\211\052\141\034\018\098\203\045\115\140\071\188\018\001\184\110\143\093\123\119\055\186\007\006\152\247\062\251\239\062\104\138\254\039\106\041\043\098\250\025\182\112\190\211\227\129\221\105\180\200\074\075\144\167\160\213\203\230\053\045\004\061\131\099\024\091\191\003\162\084\191\090\072\135\139\217\007\211\084\187\114\214\012\091\090\009\238\000\084\073\244\236\035\089\000\019\044\107\230\003\033\147\172\225\048\114\195\014\142\213\091\182\130\245\120\148\091\148\112\238\071\221\186\012\210\202\004\167\190\213\131\082\150\173\154\191\163\135\159\254\245\064\129\088\189\109\104\004\188\029\221\088\187\109\063\156\238\218\166\145\004\065\192\192\138\117\104\235\100\147\225\006\112\038\116\236\235\108\069\050\156\171\224\014\128\049\028\100\185\056\228\231\014\064\035\032\016\146\186\209\053\222\174\078\248\116\068\001\252\175\120\112\238\199\093\096\209\152\145\115\034\142\125\163\079\087\010\161\119\120\132\121\013\007\128\134\027\126\006\090\005\171\205\142\213\155\119\161\179\119\176\038\247\115\186\219\176\118\251\077\240\245\143\032\155\097\027\148\070\041\219\051\151\179\052\220\001\048\000\074\040\211\135\113\222\063\015\141\046\059\245\209\166\067\016\073\182\146\235\086\111\101\143\002\000\192\236\139\109\056\252\149\254\027\234\003\080\010\004\143\186\113\240\047\134\176\120\158\253\229\239\240\184\117\021\044\114\000\141\106\252\020\249\022\136\032\098\120\213\070\012\173\218\008\098\082\097\000\033\087\210\014\107\182\236\129\205\238\004\005\069\062\203\230\135\017\198\103\046\103\105\184\014\128\001\008\154\120\144\146\202\095\232\114\169\132\068\052\142\174\030\125\097\098\142\049\136\002\041\093\053\017\104\009\060\029\029\232\029\026\066\216\239\103\190\071\098\198\142\067\127\051\136\182\145\034\122\055\231\225\233\047\195\226\086\001\141\160\144\020\145\156\177\099\225\148\019\165\180\254\175\226\200\154\181\166\061\172\151\059\154\170\177\181\090\180\008\093\189\131\112\056\093\152\155\060\139\082\193\056\031\201\230\116\097\100\205\102\056\223\146\243\047\230\178\208\148\074\190\137\111\034\137\026\119\000\012\128\059\000\006\224\063\243\149\169\161\045\015\204\003\180\226\099\088\200\063\207\029\128\058\035\089\068\165\036\087\054\008\110\205\246\237\136\134\130\208\084\125\145\155\212\156\029\169\057\227\245\102\172\118\059\006\087\173\052\124\223\086\065\043\107\203\106\018\160\145\056\061\237\088\187\237\038\132\253\083\136\006\103\065\171\152\009\044\008\034\124\131\099\232\029\028\197\059\085\184\115\105\230\049\233\161\153\147\095\155\209\109\012\231\013\120\010\192\040\008\014\177\092\062\239\015\154\101\009\167\066\044\162\084\241\177\217\233\241\096\108\253\006\051\205\209\197\250\093\059\033\089\216\038\180\113\222\068\211\012\026\076\191\076\017\004\001\253\163\107\176\118\199\077\232\234\027\130\176\244\008\141\107\034\074\018\124\253\035\088\191\243\102\244\013\175\188\234\229\015\000\185\076\130\105\079\002\188\196\180\128\115\077\120\004\192\032\008\165\007\041\240\145\074\175\159\155\154\005\165\148\135\110\235\136\213\034\050\245\061\173\216\180\009\243\179\179\040\100\043\042\029\048\157\174\254\126\244\141\142\213\219\140\166\070\041\171\203\126\014\128\017\216\029\046\012\173\220\128\254\145\053\072\039\162\200\166\227\200\165\146\144\229\018\232\091\130\040\068\016\097\119\056\225\244\180\195\237\237\064\091\103\247\146\047\253\215\161\160\200\166\152\198\169\240\002\064\003\225\014\128\065\080\130\131\044\017\178\066\190\128\197\133\008\124\253\140\147\231\056\134\033\089\008\083\227\188\040\073\216\126\203\173\056\252\228\147\080\085\182\156\165\209\216\028\078\108\218\183\175\174\054\044\007\084\069\227\226\009\012\136\146\132\014\095\063\058\124\111\102\059\085\085\133\170\148\033\074\022\136\140\195\168\010\153\020\148\050\155\048\154\038\240\008\128\081\240\240\151\065\180\169\190\019\000\152\166\183\204\076\206\152\099\012\167\034\172\086\011\179\120\190\167\163\029\155\246\239\213\213\021\096\020\146\036\097\199\237\183\113\225\031\003\080\229\114\103\189\109\104\118\068\081\132\213\102\103\126\249\003\064\058\201\118\250\007\144\009\117\250\184\002\160\065\112\007\192\032\206\158\125\080\006\200\001\150\053\179\083\179\038\089\195\169\004\139\036\234\010\191\244\141\142\097\195\238\061\117\073\223\008\162\136\173\239\190\005\222\142\142\154\223\123\025\066\085\085\235\169\183\017\173\076\038\193\058\028\141\062\131\003\015\214\055\252\182\140\224\014\128\129\016\208\199\088\174\015\007\022\080\204\095\087\141\150\099\034\002\129\131\144\027\171\001\046\197\240\154\213\216\188\255\038\008\053\116\002\172\014\007\246\220\121\039\186\007\120\207\191\017\016\208\024\165\184\190\072\003\199\052\020\069\070\033\199\040\000\004\060\110\146\057\045\009\119\000\012\068\032\228\081\150\235\053\170\193\127\121\206\044\115\056\021\064\000\221\227\025\251\087\140\097\247\157\119\194\238\114\027\104\209\210\120\187\058\177\255\189\239\069\091\023\179\100\042\231\026\104\084\255\239\158\083\061\153\068\012\148\177\179\080\083\008\119\000\012\132\059\000\006\050\123\250\161\203\000\046\050\173\225\117\000\117\069\016\133\170\164\096\219\125\062\188\235\158\247\097\096\229\074\083\082\002\146\197\130\245\187\118\099\223\221\239\229\057\127\131\209\052\202\118\252\228\024\074\038\201\060\134\225\220\252\196\195\060\111\106\032\188\011\192\104\040\125\012\132\172\173\244\242\153\169\025\104\084\131\064\184\047\086\015\068\081\040\042\074\117\178\204\146\197\138\205\251\247\099\116\253\058\076\157\058\141\072\176\122\141\007\201\098\197\192\202\021\088\185\105\019\172\118\227\005\132\056\128\170\168\060\255\086\039\040\040\050\009\182\000\012\037\096\074\177\114\110\012\119\000\140\070\192\227\160\248\131\074\047\047\228\242\152\159\013\097\112\108\200\076\171\056\215\192\102\177\168\165\138\004\129\111\140\167\189\003\219\111\187\013\185\116\026\243\051\179\152\191\060\141\066\174\242\198\016\034\008\104\239\238\198\192\138\021\232\027\027\133\040\242\175\167\153\168\138\198\007\114\212\137\108\042\001\069\097\107\255\003\184\003\096\052\252\009\099\048\082\058\127\064\241\184\242\000\042\142\215\094\058\119\129\059\000\117\194\102\021\012\255\014\184\188\094\172\222\186\005\171\183\110\065\033\155\069\042\022\067\058\030\071\049\159\071\089\150\081\150\101\136\162\004\171\205\010\139\213\006\135\199\141\014\159\015\222\206\078\008\058\090\169\056\250\080\075\010\023\001\170\019\201\232\002\235\146\156\035\047\007\183\029\156\000\000\032\000\073\068\065\084\240\254\127\131\225\014\128\193\204\204\124\179\056\180\229\254\231\001\242\254\074\215\076\158\155\196\173\239\123\015\004\129\171\002\214\026\171\069\242\152\185\191\195\237\134\195\237\070\223\232\168\153\183\225\232\064\041\043\166\254\238\057\215\128\082\164\019\017\182\037\192\051\147\147\095\225\131\155\012\134\039\158\077\065\248\041\203\213\133\066\001\193\025\246\073\115\156\234\177\218\037\095\189\109\224\212\135\114\089\225\050\156\117\032\147\138\049\171\255\017\074\126\110\146\057\045\013\119\000\076\064\179\202\063\006\192\244\009\191\116\142\169\121\128\099\016\086\073\236\003\192\079\022\173\071\081\083\040\119\254\234\064\050\026\102\093\082\006\181\252\196\012\091\090\029\238\000\152\064\232\216\215\023\065\241\044\203\154\201\137\073\221\163\102\057\085\033\016\066\230\235\109\004\167\214\208\016\064\249\243\175\198\080\074\145\098\086\255\035\079\006\206\254\181\046\193\046\206\245\225\095\000\147\032\192\191\179\092\095\042\022\185\040\080\157\016\068\194\220\144\204\105\110\052\013\252\119\094\007\050\137\069\168\140\213\255\148\210\239\155\100\078\203\195\029\000\147\032\068\251\009\000\153\101\205\133\051\231\077\178\134\115\061\036\081\200\215\219\006\078\109\081\100\165\080\111\027\090\145\196\034\115\176\173\100\179\149\121\254\223\036\184\003\096\018\115\227\095\077\000\228\041\150\053\147\019\147\040\022\120\058\186\214\216\109\018\207\189\180\024\106\089\101\020\161\229\084\139\082\046\035\021\103\013\255\227\241\233\099\095\175\074\173\147\115\109\184\003\096\034\148\104\076\105\000\085\081\112\097\124\194\044\115\056\215\192\102\177\240\129\048\045\070\089\086\184\188\098\141\073\068\067\160\140\218\075\132\240\240\191\153\112\007\192\068\028\121\241\167\000\152\228\070\207\030\063\099\146\053\156\107\225\176\091\248\076\248\022\067\041\149\187\235\109\067\171\017\139\048\075\100\023\109\121\241\151\102\216\194\185\002\119\000\076\100\114\242\043\105\048\078\008\140\069\023\049\031\224\069\233\181\196\106\147\134\001\240\052\064\235\160\042\101\117\176\222\070\180\018\185\076\018\165\124\229\178\216\000\064\128\159\079\078\126\133\015\108\050\017\238\000\152\013\197\063\178\046\057\119\130\071\001\106\137\064\224\000\001\247\186\090\004\074\105\144\082\202\083\000\053\036\190\192\062\032\075\133\240\015\038\152\194\121\011\220\001\048\153\192\120\247\019\032\096\026\097\121\241\204\005\148\138\188\024\176\150\136\162\192\044\078\206\105\078\052\149\178\233\208\114\170\066\083\021\036\099\204\226\063\151\067\227\093\076\090\042\028\118\184\003\096\058\015\106\160\248\006\203\010\069\081\112\233\236\005\179\012\226\044\129\085\018\217\226\147\156\166\069\085\021\254\187\174\033\137\232\060\052\077\101\090\067\008\249\039\224\065\158\150\051\025\238\000\212\000\074\132\111\000\096\250\006\156\124\245\004\040\229\157\074\181\194\110\231\131\225\090\133\178\172\242\169\091\053\131\034\186\192\060\231\068\129\136\127\054\195\026\206\219\225\014\064\013\008\158\254\074\000\032\143\179\172\073\196\018\152\153\188\108\150\073\156\119\096\183\091\221\245\182\129\083\027\148\130\204\167\000\214\136\084\124\145\185\248\015\192\047\253\039\030\010\153\097\015\231\237\112\007\160\070\016\080\230\130\150\019\135\142\155\097\010\103\009\156\086\169\191\222\054\112\106\131\044\043\003\245\182\161\085\136\134\102\152\215\080\170\241\226\191\026\033\213\219\128\086\193\223\229\251\229\080\044\026\002\080\241\195\039\056\027\192\066\112\001\125\131\125\038\090\198\001\000\201\034\244\019\032\065\129\142\122\219\194\209\071\033\151\067\050\026\069\054\149\130\092\044\066\046\149\080\046\149\032\008\002\044\086\043\044\086\027\172\118\123\129\106\082\175\211\211\014\073\226\105\031\051\201\103\083\200\165\147\172\203\002\193\013\139\143\131\055\066\213\004\238\000\212\138\003\015\042\116\203\003\255\068\064\255\007\203\178\147\175\030\199\251\062\114\143\089\086\113\222\130\032\008\126\085\211\184\003\208\044\080\138\120\036\130\208\244\052\022\023\022\032\023\042\146\247\119\188\254\047\054\135\019\222\014\031\058\123\006\096\119\242\012\144\209\068\131\076\205\079\087\032\228\159\240\131\031\176\085\012\114\116\195\029\128\026\162\016\229\033\011\021\255\024\064\197\061\200\083\231\038\145\190\035\005\111\071\155\137\150\113\000\192\106\021\147\133\034\047\060\110\116\084\069\193\236\133\139\008\078\094\066\033\167\191\160\191\084\200\035\090\152\069\052\052\011\135\203\131\174\190\033\116\245\012\002\132\215\008\086\139\092\042\032\021\099\238\182\044\074\170\246\053\051\236\225\044\141\088\111\003\090\137\092\248\104\206\219\179\119\012\004\059\043\093\067\065\065\008\193\232\170\049\019\045\227\000\128\092\086\103\011\197\242\104\189\237\224\044\013\165\020\097\191\031\167\094\120\001\017\191\031\074\153\109\172\236\245\080\202\050\210\137\069\036\023\023\032\089\109\176\059\093\000\184\035\160\151\249\185\041\228\179\108\051\124\008\161\255\056\119\230\017\174\253\095\067\120\017\096\141\017\168\240\215\000\152\250\251\206\158\056\131\066\158\079\047\053\027\167\211\202\195\044\013\074\046\157\198\171\143\063\142\211\047\189\084\213\169\255\070\148\138\121\204\094\056\141\201\051\071\081\046\241\239\156\030\020\185\132\068\132\185\136\095\083\065\255\198\012\123\056\215\134\071\000\106\076\042\122\056\234\237\221\183\007\192\218\074\215\104\170\006\010\096\100\037\063\156\154\137\040\018\123\060\153\231\018\177\013\070\036\016\192\137\003\007\076\125\241\191\147\114\169\136\088\052\004\155\205\201\235\003\024\153\159\155\066\046\195\090\252\071\127\022\028\255\234\195\166\024\196\185\038\060\002\080\007\168\166\253\037\235\154\211\071\078\033\155\201\154\097\014\231\053\068\065\104\039\132\114\073\224\006\129\082\138\011\199\142\225\228\011\047\024\026\238\175\020\077\081\048\123\241\052\066\051\151\192\024\180\107\089\202\114\009\241\112\128\121\157\032\128\249\153\200\169\030\030\001\168\003\153\232\145\025\111\207\222\123\064\080\241\068\050\170\105\160\154\134\209\213\099\038\090\198\073\166\139\019\154\070\091\102\082\156\170\042\088\012\133\048\063\051\003\255\197\075\008\078\077\098\254\242\101\044\006\131\072\199\227\040\151\074\176\057\028\016\165\218\214\011\171\138\130\083\047\189\132\208\229\250\139\097\229\051\073\168\074\025\222\142\046\240\186\128\235\179\048\123\009\185\012\091\238\031\192\017\255\233\071\152\186\163\056\198\192\187\000\234\004\017\232\223\080\074\190\195\178\102\252\216\105\236\216\191\019\158\054\175\089\102\181\060\078\187\037\151\206\046\255\065\076\153\100\002\151\207\078\032\018\240\067\083\175\223\117\069\008\065\071\079\015\070\214\175\135\111\096\000\196\228\042\121\185\088\196\241\231\159\071\058\022\051\245\062\044\044\206\095\145\179\029\092\177\014\220\009\088\026\185\088\068\044\204\062\245\143\018\250\101\019\204\225\084\000\143\000\212\137\244\134\015\156\247\022\242\255\005\012\194\051\148\082\040\101\005\043\214\174\052\209\178\214\070\163\052\156\205\201\067\245\182\195\044\148\114\025\231\014\031\198\196\209\163\200\038\147\021\207\155\040\228\114\088\152\157\197\226\124\008\109\093\093\176\057\028\055\094\164\131\092\058\141\163\207\060\131\092\138\249\020\105\058\249\108\026\162\100\129\203\195\107\069\151\034\052\123\017\133\108\154\109\017\165\151\130\235\163\015\224\220\057\158\099\169\003\220\001\168\023\051\007\180\182\222\061\105\128\124\152\101\217\098\120\017\235\183\172\135\205\193\107\213\204\064\016\005\033\153\042\044\075\173\248\116\060\142\035\079\063\141\068\052\170\123\143\082\161\128\208\212\020\068\171\021\237\221\221\006\090\007\036\163\081\028\123\238\089\148\042\019\244\169\011\217\084\028\158\142\110\088\172\182\122\155\210\080\148\010\121\004\166\206\177\047\036\194\239\167\159\251\230\105\227\045\226\084\002\047\002\172\035\254\245\209\127\005\112\145\101\141\166\105\120\229\249\067\038\089\196\177\074\226\000\000\253\111\200\006\037\030\142\224\200\051\207\160\152\207\087\189\151\246\090\113\222\133\227\198\205\170\088\152\157\195\209\103\159\069\185\036\027\182\167\025\080\074\049\115\225\052\052\085\169\183\041\013\197\130\127\074\207\244\210\115\129\241\238\239\153\097\015\167\050\120\004\160\158\156\059\071\189\189\251\226\000\238\099\089\022\143\198\048\188\098\152\215\002\152\068\042\083\156\208\052\186\108\006\198\100\083\041\028\125\246\089\168\006\087\210\167\022\023\033\074\018\218\125\190\170\246\153\153\152\192\196\145\035\160\090\245\042\140\068\212\224\090\153\067\219\166\052\218\183\165\208\182\053\005\239\134\052\156\099\121\088\059\100\064\000\212\076\117\051\000\094\127\249\123\218\187\170\182\119\057\144\203\164\016\154\097\058\199\000\000\040\161\247\103\194\127\113\214\004\147\056\021\194\029\128\058\147\142\220\115\214\219\155\255\021\000\189\044\235\162\225\024\054\237\216\108\122\065\086\043\082\044\150\047\202\101\117\172\222\118\024\129\082\046\227\216\051\207\152\022\086\143\135\195\232\236\237\133\195\229\098\094\075\041\197\249\099\199\112\249\108\245\239\000\209\161\162\251\230\056\250\238\014\195\187\033\013\071\127\017\214\014\025\022\143\002\139\087\129\173\075\134\115\184\000\239\134\052\188\155\210\016\172\020\165\168\029\084\213\247\253\201\231\050\232\240\245\215\188\059\162\209\160\020\152\189\112\026\101\185\200\186\116\060\056\222\243\007\192\001\158\251\175\035\220\001\168\059\007\168\183\111\095\020\192\175\178\172\202\103\115\104\235\104\071\119\111\117\167\047\206\213\040\026\013\231\242\203\163\016\112\226\232\081\196\022\204\149\054\072\045\046\098\104\213\106\016\161\242\151\169\170\042\056\245\226\075\152\159\153\169\250\254\222\077\105\012\222\027\130\099\176\000\034\221\248\125\034\088\053\056\135\010\240\110\074\065\201\072\144\227\058\242\249\148\066\083\020\180\117\245\232\176\120\249\144\136\004\017\211\209\247\175\017\250\219\153\240\095\092\048\193\036\014\003\220\001\104\000\210\225\195\231\189\189\123\239\001\042\215\005\000\128\072\040\140\205\059\183\064\020\249\175\209\072\172\146\104\139\039\243\236\071\218\006\035\018\008\224\210\201\147\166\223\167\092\042\193\230\116\160\173\171\178\144\184\092\044\226\248\115\207\033\030\014\087\117\095\034\082\244\190\039\130\174\125\113\016\145\253\032\041\088\040\060\107\178\016\157\042\010\179\236\191\238\066\033\139\238\254\097\008\066\107\126\255\084\085\121\173\030\130\121\120\223\209\224\248\035\127\108\134\077\028\054\120\017\096\099\064\041\197\159\177\046\202\102\178\056\246\242\017\051\236\105\105\068\081\240\017\002\246\099\077\003\033\023\010\056\247\234\171\053\187\223\220\133\011\087\226\193\055\032\151\078\227\213\039\159\068\170\202\030\127\193\166\098\224\067\033\120\055\049\182\157\045\065\251\150\020\122\239\094\096\031\002\072\041\018\209\249\170\239\223\172\068\002\211\080\100\118\205\012\066\233\255\003\046\173\216\016\112\007\160\065\008\158\121\248\023\000\094\096\093\119\226\208\113\100\082\213\063\004\057\111\199\034\073\115\245\182\065\055\148\226\236\225\195\144\075\181\019\052\202\165\211\072\039\018\215\189\038\185\184\136\035\079\061\133\066\182\058\073\107\201\165\096\232\035\065\056\135\170\239\104\120\029\207\186\012\058\118\197\153\215\233\024\122\179\044\144\139\005\068\095\019\071\098\228\025\255\153\071\158\052\218\030\142\062\184\003\208\064\104\130\240\037\000\076\241\052\069\081\240\226\147\204\126\003\231\006\056\157\214\218\139\207\027\132\127\114\018\209\032\187\034\091\181\196\230\175\125\026\094\152\155\195\209\103\158\169\218\041\177\249\138\024\254\132\031\054\159\241\206\077\231\077\049\230\125\011\185\012\228\022\156\026\024\156\057\175\167\107\067\033\068\253\146\025\246\112\244\209\154\201\171\006\037\019\062\188\224\237\221\055\004\096\023\203\186\196\098\028\221\061\221\232\244\117\154\100\089\235\033\010\036\151\202\020\155\174\194\043\159\201\224\212\139\047\128\106\236\017\086\239\176\140\013\031\142\097\112\111\006\130\068\145\009\178\021\199\041\138\130\161\213\171\175\250\243\089\131\218\252\156\163\121\012\222\027\132\232\168\190\093\112\041\008\001\044\222\050\050\023\216\218\107\093\158\182\150\154\024\152\092\012\035\018\208\053\163\225\171\129\241\175\126\211\096\115\056\085\192\035\000\013\070\153\040\127\010\128\089\007\245\192\227\207\161\084\100\110\197\225\092\003\187\221\178\022\064\083\029\237\052\074\049\254\242\203\080\021\230\162\044\120\007\101\236\251\098\008\253\059\178\232\217\152\199\214\079\070\049\118\043\219\199\048\029\139\093\169\005\120\221\030\085\197\196\145\163\184\112\226\132\030\145\152\183\219\183\041\133\129\123\067\016\172\230\166\142\157\163\175\233\005\048\144\103\031\126\211\180\168\138\130\224\229\243\122\150\038\052\107\249\065\131\205\225\084\009\143\000\052\024\185\240\209\092\091\207\062\005\004\119\179\172\043\203\101\148\138\037\062\039\192\032\008\032\038\082\249\243\148\178\233\051\212\147\233\051\103\116\181\213\137\022\138\061\191\179\000\123\251\219\213\237\220\189\101\204\188\192\166\123\191\056\063\143\072\192\143\248\194\002\046\157\060\137\120\184\202\022\068\002\116\221\020\131\239\221\139\236\069\122\058\209\074\034\010\001\103\197\215\019\066\208\217\219\026\003\036\131\211\019\200\101\146\236\011\041\249\147\224\169\175\030\048\220\032\078\085\240\008\064\003\226\165\221\127\007\070\137\096\000\056\123\226\012\252\151\155\183\118\173\209\112\056\172\141\051\142\238\006\164\227\113\076\235\020\212\089\251\193\056\220\125\087\159\122\029\157\010\220\061\236\210\188\153\068\018\097\191\191\106\217\097\034\082\244\222\185\128\206\061\236\197\121\213\224\024\096\011\252\148\203\173\017\121\203\166\018\136\071\216\187\030\040\048\209\107\147\191\102\130\073\156\042\225\014\064\003\114\246\236\131\178\070\232\031\177\174\163\148\226\192\163\207\066\081\184\078\185\017\120\061\182\166\024\010\164\042\010\198\015\030\212\149\099\239\094\155\199\216\045\215\014\097\251\054\027\087\105\207\130\096\213\174\180\249\109\200\212\252\222\182\030\182\066\064\181\188\252\191\111\154\166\033\048\125\014\122\186\247\008\161\255\245\216\177\175\055\109\081\237\114\134\059\000\013\074\232\244\035\255\001\224\113\214\117\201\120\018\135\095\168\093\255\247\114\198\099\183\174\007\208\240\015\174\139\039\142\035\151\097\127\081\074\014\013\091\062\185\120\221\241\246\035\055\101\106\022\122\127\029\201\165\096\232\190\128\161\109\126\044\008\086\141\073\088\072\085\149\170\107\028\026\157\133\185\041\148\010\236\191\015\010\252\060\112\250\017\230\231\024\167\054\112\007\160\129\145\068\245\119\001\228\088\215\157\056\116\020\011\065\115\229\095\091\001\034\010\046\065\032\236\083\078\106\200\098\040\004\255\228\148\174\181\091\062\182\120\085\222\255\157\056\187\203\232\221\202\252\017\212\141\205\087\050\173\205\143\005\193\202\022\077\081\151\241\116\192\092\038\137\197\249\089\061\075\051\148\210\007\140\182\135\099\028\220\001\104\096\102\078\126\109\134\130\254\015\214\117\154\070\241\196\079\030\131\220\224\163\085\155\001\135\195\178\088\111\027\174\133\092\042\225\204\171\175\086\164\192\247\078\006\118\101\209\183\163\050\065\158\245\247\198\033\090\204\063\225\058\071\114\024\186\207\015\201\085\255\151\041\115\208\099\153\070\000\084\085\133\255\210\089\093\017\014\002\252\247\208\153\071\116\169\005\113\106\003\119\000\026\156\224\120\207\223\002\056\196\186\046\157\072\225\133\039\015\024\111\080\139\225\113\219\043\047\007\175\049\231\143\028\129\172\099\202\159\189\093\193\198\143\084\238\215\056\058\203\216\192\112\189\030\060\027\210\024\188\119\222\244\054\063\014\027\193\233\115\040\021\117\165\098\094\245\143\251\190\106\180\061\028\099\225\014\064\195\243\160\006\144\223\001\192\124\156\159\056\121\014\151\206\242\129\091\213\224\118\218\214\003\168\255\145\244\029\132\166\167\177\048\199\222\241\065\008\176\245\083\081\088\156\108\033\238\225\253\025\102\093\128\202\012\002\186\246\199\208\119\087\024\016\248\203\191\145\072\198\194\072\068\117\165\018\101\065\192\231\174\060\187\056\141\012\119\000\154\128\192\248\067\227\020\248\178\158\181\207\061\250\044\050\169\218\087\082\047\023\068\129\120\068\129\076\212\219\142\183\082\200\229\048\113\236\152\174\181\163\183\165\208\181\070\159\190\209\134\015\199\176\226\054\227\156\000\034\082\244\222\181\128\206\189\181\109\243\227\220\152\178\092\066\096\074\231\199\158\210\255\061\119\234\097\125\061\169\156\154\194\029\128\038\193\081\016\254\095\000\231\088\215\149\138\037\060\249\211\199\160\081\238\140\235\197\225\176\053\204\027\138\190\174\246\087\102\111\078\112\247\149\177\238\158\042\126\020\002\172\255\112\012\091\063\021\129\100\171\238\243\228\232\082\176\255\119\114\232\220\192\235\084\026\013\074\129\185\075\227\080\021\093\013\048\231\237\069\241\207\141\182\137\099\014\092\009\176\073\136\199\015\171\237\253\123\078\083\074\062\011\198\026\165\076\042\003\073\148\048\048\210\026\106\101\070\035\010\066\038\157\045\054\132\034\224\204\185\115\008\077\079\051\175\019\036\138\221\159\191\090\237\079\015\222\065\025\067\123\179\144\179\034\114\011\022\080\090\249\199\081\180\106\088\117\087\018\219\127\045\002\167\047\007\055\233\071\178\208\120\082\186\201\227\029\208\148\202\207\071\061\131\099\016\196\229\241\056\141\004\167\017\215\055\229\080\211\040\253\240\236\249\135\103\012\054\137\099\018\203\227\019\219\034\164\194\071\230\188\189\123\092\000\185\153\117\109\104\054\136\190\193\062\180\117\182\155\097\218\178\198\098\017\186\099\201\124\026\128\189\158\118\164\019\009\140\191\252\178\174\138\243\117\031\076\160\207\192\118\062\201\166\161\119\107\014\067\251\178\144\028\026\148\146\008\057\179\244\227\132\136\020\029\043\138\088\113\123\026\219\062\029\133\111\125\001\194\107\151\010\246\012\132\226\048\242\074\099\057\001\172\014\064\119\255\048\084\085\133\092\204\163\088\200\065\046\021\032\151\010\040\023\243\144\229\018\212\114\025\084\211\064\004\017\164\214\194\010\012\100\082\113\004\038\153\003\141\000\000\066\241\255\005\207\060\242\047\006\155\196\049\017\169\222\006\112\216\232\181\042\127\026\046\089\110\007\193\094\150\117\026\213\240\196\079\031\195\199\063\247\041\120\219\217\166\157\181\058\004\068\180\088\164\243\101\089\217\095\047\027\052\085\197\153\151\095\214\165\246\215\185\170\136\177\219\117\232\183\087\128\189\093\193\154\247\038\176\230\189\009\040\069\001\185\168\005\197\132\004\077\035\016\037\013\246\014\021\206\238\242\117\083\006\109\093\105\196\131\018\180\198\171\181\172\152\137\099\047\085\124\173\036\089\097\177\217\096\119\186\097\119\186\096\119\186\225\242\116\064\148\234\251\056\150\139\069\204\093\024\007\213\161\246\007\144\099\094\218\253\063\013\055\138\099\042\060\002\208\100\204\207\031\211\188\190\061\007\064\200\111\002\176\178\172\085\202\010\066\115\001\172\223\182\017\130\192\203\063\088\080\084\117\186\080\044\143\214\235\254\023\079\156\068\052\024\100\094\039\217\053\236\249\194\060\115\213\191\030\004\137\194\222\166\194\221\091\134\167\079\134\171\167\012\155\087\133\032\093\255\133\066\068\025\082\105\004\057\197\028\039\069\015\172\017\000\022\052\077\133\082\150\081\204\103\145\077\197\145\092\092\064\036\056\139\212\098\024\197\124\022\032\128\197\230\168\105\164\128\106\042\166\039\078\064\214\215\242\151\211\136\246\222\233\051\255\039\098\180\093\028\115\225\014\064\019\146\142\030\137\123\122\246\037\008\193\007\089\215\230\179\121\020\114\133\134\159\026\168\148\203\200\102\114\040\021\138\040\021\075\111\254\083\146\033\008\002\196\026\231\091\045\146\036\038\083\249\186\132\078\098\011\011\152\056\118\084\215\218\205\031\143\162\115\085\227\015\171\177\089\040\226\153\250\170\255\189\021\051\029\128\107\161\040\050\010\185\052\146\139\011\088\012\205\161\144\075\131\016\001\054\187\249\206\064\096\250\060\050\009\125\090\015\132\226\119\131\227\143\060\109\176\073\156\026\192\083\000\077\074\240\204\067\095\027\218\242\197\247\001\248\016\235\218\179\039\198\209\059\216\139\077\059\054\155\096\089\229\100\051\089\068\231\035\136\204\135\145\074\164\144\203\228\144\203\230\144\203\100\111\168\098\040\073\018\156\110\039\156\046\039\028\078\039\058\124\029\232\238\241\161\171\167\011\157\190\046\195\035\028\086\139\048\068\008\185\068\041\093\099\232\198\055\160\044\203\056\251\202\043\186\242\254\125\219\114\024\220\093\153\218\095\221\177\165\209\110\233\071\178\172\171\248\108\217\161\105\042\082\177\008\082\177\008\068\073\066\167\111\000\093\125\195\176\057\140\215\165\138\133\003\136\135\217\163\075\000\000\066\126\236\031\127\232\027\198\090\196\169\021\220\001\104\098\052\107\249\183\004\217\186\023\160\253\172\107\159\127\252\000\124\189\062\244\012\212\166\184\157\082\138\104\056\138\217\075\151\177\016\088\064\120\062\140\066\078\255\176\023\069\081\144\078\166\145\078\166\001\000\151\047\189\249\255\004\081\064\103\119\039\250\135\007\049\186\122\020\067\099\035\176\088\170\255\168\187\093\214\096\038\091\170\169\003\048\113\228\136\174\177\186\054\175\130\077\031\107\088\021\227\037\241\186\044\072\054\078\022\160\097\080\021\005\209\249\057\044\046\204\193\219\238\131\111\104\005\092\158\054\067\246\206\103\146\008\078\159\215\187\060\000\213\242\219\134\024\194\169\011\141\091\142\202\169\136\225\205\247\223\077\009\121\012\058\052\029\092\110\023\062\246\185\079\192\227\053\103\234\173\162\040\240\079\251\049\115\105\026\051\151\046\035\155\169\207\105\084\148\068\012\012\015\098\100\213\040\086\173\095\141\182\014\125\015\207\092\094\062\027\152\079\110\050\216\188\107\050\063\051\115\165\234\159\021\002\236\249\157\005\116\175\171\207\052\061\221\104\022\076\207\170\208\026\096\000\227\229\127\088\009\165\208\184\025\082\079\123\023\250\071\086\195\225\214\159\149\146\139\069\092\058\115\024\138\172\043\245\162\082\141\222\021\060\251\200\115\186\013\224\212\157\198\253\132\115\042\034\029\057\050\229\237\219\039\000\184\157\117\109\089\046\099\110\122\014\235\054\175\135\100\096\005\114\098\049\129\019\135\142\225\137\159\060\142\137\083\103\017\153\143\064\150\235\039\248\066\053\138\116\050\005\255\244\028\078\029\062\137\203\151\046\003\000\058\186\187\032\138\149\251\077\086\139\216\029\075\230\162\000\092\038\153\250\006\165\066\030\039\094\120\030\154\170\050\175\029\189\037\141\209\091\026\171\173\174\034\136\006\082\028\104\136\150\192\122\212\000\176\032\023\011\136\133\067\040\229\179\112\122\218\152\059\008\052\069\193\212\185\099\144\139\250\084\033\041\197\159\006\207\062\242\175\186\022\115\026\006\238\000\044\003\210\225\123\094\240\246\022\118\003\088\203\186\182\144\047\032\028\010\099\221\230\245\032\130\254\128\144\170\168\152\060\119\009\207\061\250\028\094\126\230\069\204\251\067\080\149\198\108\235\202\103\115\152\185\116\025\167\143\156\066\054\149\134\183\163\029\014\167\163\146\165\036\151\151\143\043\138\102\106\055\000\165\020\039\095\120\017\185\084\154\121\173\187\071\198\142\223\008\191\209\103\223\108\072\212\141\100\129\253\231\054\154\212\120\059\180\082\227\058\000\175\083\044\228\144\136\132\064\068\017\078\119\027\042\170\021\164\020\151\207\159\068\062\171\207\209\162\192\207\131\103\030\230\099\126\151\001\077\250\152\224\188\157\003\180\189\119\215\099\020\228\062\000\157\172\171\211\201\052\114\217\044\086\174\093\197\124\103\077\211\112\246\248\056\126\249\195\095\224\252\169\115\200\166\155\103\238\128\170\170\136\204\071\112\230\216\105\196\023\019\232\236\238\130\195\117\125\071\128\016\044\100\115\242\144\153\118\205\093\184\128\192\228\036\243\058\034\082\236\254\124\024\142\142\198\116\188\042\065\176\020\145\074\019\080\212\087\186\058\059\237\134\146\182\212\213\134\074\161\084\067\038\025\067\054\029\135\219\219\009\081\186\158\221\020\115\083\231\144\138\235\236\216\163\244\146\205\166\220\147\152\063\214\248\173\037\156\027\194\029\128\101\066\042\114\180\232\237\221\119\000\192\103\192\168\015\000\000\209\133\040\068\081\172\088\046\152\082\138\201\115\023\241\232\015\127\137\243\167\039\080\150\235\159\183\173\134\120\052\086\145\035\096\179\074\221\177\068\190\000\192\102\134\029\217\084\018\167\015\030\212\053\127\125\237\251\019\232\223\097\156\218\095\093\032\026\148\076\015\074\090\125\187\023\052\089\064\126\214\244\076\143\161\148\075\069\196\195\065\088\173\118\056\092\075\215\245\132\253\211\088\156\103\159\034\249\026\089\065\036\119\205\156\248\154\095\183\145\156\134\130\059\000\203\136\116\228\112\196\219\187\103\022\032\031\209\179\062\056\027\064\071\087\007\186\122\186\175\123\093\096\198\143\199\126\248\011\156\062\114\010\165\194\242\058\008\196\163\049\156\061\054\142\098\161\128\254\225\001\136\210\219\191\034\132\016\041\155\043\029\083\085\109\216\232\123\083\077\195\241\003\007\080\210\081\245\223\049\086\196\230\079\044\086\022\002\110\112\132\082\055\050\229\068\093\109\176\249\100\100\047\185\161\022\155\235\017\073\041\069\042\030\129\082\150\225\105\235\004\033\111\166\049\018\145\121\004\103\046\086\179\245\103\002\227\015\031\048\194\078\078\099\208\092\159\110\206\013\073\071\142\140\123\251\246\118\002\216\167\103\253\244\197\105\244\244\245\160\189\171\227\170\255\087\150\203\120\225\137\231\241\226\019\207\035\151\109\242\147\230\117\160\160\008\007\023\112\225\244\004\188\237\094\116\118\191\061\171\066\009\066\185\188\241\105\128\075\039\079\034\226\103\063\092\073\054\013\123\190\176\000\171\139\189\096\176\017\017\137\021\137\092\125\035\000\068\160\112\142\020\144\155\114\067\043\087\086\011\032\088\052\072\046\005\150\182\050\108\221\050\172\029\050\036\151\010\209\161\065\144\040\004\001\208\212\218\212\021\020\178\105\100\082\113\180\117\245\064\016\068\100\146\049\204\094\026\215\165\039\001\000\032\244\047\131\227\143\252\141\177\086\114\234\205\050\056\047\112\222\201\174\093\159\183\132\101\203\211\000\110\213\179\094\146\036\220\251\169\015\099\112\244\205\119\092\096\198\143\103\254\227\169\055\250\238\091\137\021\107\087\226\182\247\223\241\070\187\036\165\180\120\113\058\090\006\096\088\255\100\034\018\193\209\103\158\209\021\250\223\252\241\040\134\247\055\079\237\197\141\033\152\185\044\065\065\253\163\075\106\081\068\236\080\023\050\023\221\208\074\087\206\075\132\000\086\095\009\206\129\002\108\189\069\088\059\175\188\236\201\013\036\143\001\064\147\009\074\049\027\228\152\013\165\069\043\228\168\029\197\005\187\238\247\242\141\176\218\029\232\027\094\005\255\212\004\168\166\219\065\124\054\208\229\123\047\014\060\216\188\197\037\156\037\225\014\192\050\101\104\211\031\118\066\144\095\006\176\078\207\122\139\069\194\135\062\253\043\240\245\245\224\224\051\007\049\126\244\148\174\151\211\114\193\238\180\227\238\015\191\015\163\171\198\000\000\051\254\248\203\037\089\121\151\017\123\171\229\050\014\062\250\024\138\058\078\189\061\155\242\216\245\091\011\070\152\209\080\196\131\253\136\203\129\122\155\241\006\084\037\080\178\022\080\021\176\120\203\021\189\236\043\069\045\138\200\093\118\033\055\237\066\126\206\089\113\196\161\082\008\160\107\188\015\174\172\155\016\161\221\060\055\254\213\250\230\100\056\166\192\029\128\101\204\232\214\007\086\040\148\030\034\128\046\185\063\139\197\010\167\219\137\084\162\246\242\108\130\072\224\246\074\112\183\089\222\208\065\047\228\174\028\064\114\025\005\165\066\237\195\221\132\016\236\185\101\047\246\222\186\031\201\076\241\213\072\052\163\043\205\242\078\206\030\058\132\224\229\203\204\235\108\110\021\055\255\073\000\054\247\242\008\253\191\149\194\226\008\130\025\246\191\147\102\135\042\004\153\073\055\146\039\058\080\138\154\082\103\202\066\020\026\125\087\224\236\035\236\045\041\156\166\128\059\000\203\156\225\077\247\239\161\002\057\000\192\120\017\113\003\104\239\178\098\096\212\137\190\049\039\006\070\157\240\013\216\225\106\179\192\237\185\190\176\073\089\214\144\078\148\145\142\203\088\152\203\035\052\155\071\104\166\128\133\064\030\106\217\220\072\197\200\170\081\220\253\161\187\075\254\112\190\072\041\173\074\147\053\236\247\227\212\139\047\234\090\187\235\115\097\244\108\094\158\181\024\106\166\015\151\023\117\234\211\047\019\242\001\039\146\039\058\144\159\113\154\150\034\184\014\005\074\180\247\004\079\127\245\149\154\223\153\083\051\184\003\208\002\012\110\189\255\163\132\146\239\067\135\092\176\209\088\172\002\086\109\242\098\253\014\047\214\109\111\071\135\207\216\083\142\082\166\184\060\145\198\133\147\041\156\063\153\194\226\188\057\121\100\111\187\023\059\239\184\245\168\213\225\221\173\119\143\082\161\128\067\143\062\010\185\196\046\197\058\188\063\131\205\031\143\234\189\117\227\163\218\049\057\151\135\254\224\245\242\161\020\182\035\114\160\007\197\112\205\034\002\042\001\238\243\143\063\252\179\090\221\144\083\031\184\003\208\034\012\109\253\226\031\131\226\203\245\184\055\033\004\171\055\123\176\231\014\031\054\238\106\135\100\173\157\031\178\056\095\196\209\231\023\113\236\133\024\050\009\099\229\136\237\078\071\121\231\029\119\088\220\109\237\236\139\041\197\241\003\207\099\113\158\125\250\157\179\187\140\155\255\040\008\201\086\095\177\028\179\009\204\185\080\084\091\175\232\116\041\040\005\210\103\218\016\059\212\101\126\107\034\033\095\010\156\126\232\111\205\189\009\167\017\224\014\064\011\049\180\229\129\175\000\180\102\018\158\118\167\136\155\238\238\193\238\219\125\232\234\173\111\062\083\213\040\046\028\075\225\229\167\194\152\028\055\238\165\098\177\090\181\093\119\220\033\120\187\186\152\214\249\047\093\196\196\145\163\204\247\035\004\216\247\251\033\116\140\213\191\066\222\108\018\129\126\196\202\141\083\008\216\008\168\005\017\209\023\124\200\092\048\103\128\023\001\254\222\063\254\240\023\076\217\156\211\112\112\029\128\022\034\125\219\232\147\158\168\107\045\033\216\108\230\125\108\014\017\183\253\231\126\124\250\075\171\177\126\071\059\156\238\250\079\157\022\008\129\111\208\142\157\183\116\099\245\150\054\164\098\050\226\017\093\083\208\222\134\166\170\100\097\110\014\237\190\110\056\092\238\138\214\228\210\105\156\122\241\037\080\202\126\130\095\117\087\002\067\123\234\219\035\095\051\074\157\200\200\124\062\240\091\017\044\020\238\213\089\088\189\010\242\126\039\168\102\224\025\142\226\071\129\013\145\223\192\185\115\060\239\210\034\112\007\160\149\056\119\142\174\029\222\241\243\156\038\238\128\142\193\065\055\066\020\008\222\253\129\062\124\250\075\171\176\097\103\059\036\075\221\075\014\150\164\189\219\250\154\035\224\197\130\191\128\116\162\058\025\099\077\211\016\241\007\208\061\048\000\155\227\250\179\004\168\166\225\248\243\207\163\152\099\047\222\107\027\046\097\219\167\163\032\141\249\215\106\056\068\115\032\153\095\078\250\006\198\097\243\149\224\026\043\032\055\227\130\038\087\255\129\160\192\207\251\108\229\143\207\063\253\175\188\215\191\133\224\014\064\139\049\063\127\076\027\238\254\192\143\074\036\191\007\192\106\163\246\029\028\115\226\051\255\109\045\118\221\218\013\171\173\057\062\086\237\221\054\236\190\163\027\078\183\132\217\139\089\168\138\254\131\143\166\105\136\006\067\232\027\029\129\100\185\246\048\150\169\241\051\088\152\157\097\222\095\180\080\236\254\194\002\108\158\229\215\242\119\045\168\236\230\014\192\117\144\092\010\036\183\130\236\100\213\233\128\103\044\153\220\071\038\038\254\169\126\051\187\057\117\161\057\158\212\028\067\137\070\015\168\054\223\158\159\073\132\220\014\160\042\077\123\201\042\224\174\143\014\226\163\247\175\064\091\007\243\012\162\186\067\008\193\200\106\055\118\222\210\133\216\066\169\170\174\001\085\041\035\190\016\198\192\216\024\004\241\234\175\086\114\113\017\231\094\121\069\087\093\251\134\015\199\208\179\145\125\070\064\051\083\076\117\213\125\038\064\035\147\185\228\065\248\169\062\160\138\052\000\165\120\137\218\202\031\240\079\252\083\193\064\211\056\077\066\139\004\019\057\239\036\122\246\145\172\213\090\190\007\000\123\037\218\091\160\010\133\211\035\065\020\154\187\158\180\173\211\138\207\252\209\106\220\243\233\225\170\126\150\076\050\129\147\047\189\004\237\029\141\219\138\162\224\204\161\067\087\253\121\037\116\175\203\099\244\221\173\087\013\159\151\151\127\161\163\094\018\039\218\017\126\188\015\084\169\226\123\071\112\086\036\218\189\161\099\095\111\045\207\146\243\006\060\002\208\194\036\230\143\149\220\195\059\126\066\020\241\062\016\116\222\120\197\213\080\010\156\063\158\132\092\210\176\122\115\091\083\079\163\035\132\096\116\173\027\043\054\186\113\225\084\026\114\081\095\155\093\033\155\069\062\147\070\087\127\031\004\081\068\185\084\194\248\203\007\145\138\197\152\247\178\186\084\236\249\066\024\146\125\121\183\252\093\013\065\052\081\130\070\121\074\250\173\080\010\044\190\208\141\248\097\182\174\147\037\072\209\050\118\004\206\061\018\055\194\046\078\115\210\196\143\107\142\081\140\110\248\124\191\042\089\046\160\202\225\054\155\247\118\224\227\095\092\009\075\013\251\252\205\034\157\040\227\159\255\252\034\230\231\244\031\142\136\032\192\238\114\162\148\205\233\058\249\003\192\142\207\134\209\183\109\121\170\253\093\015\090\232\196\212\194\050\022\058\210\001\085\008\022\158\232\067\118\170\178\110\147\107\067\100\065\042\239\152\059\241\247\231\012\049\140\211\180\240\008\000\007\169\197\099\089\239\192\206\031\130\010\159\007\160\187\103\047\018\044\098\114\060\141\141\187\058\096\181\055\183\019\096\115\136\216\246\174\078\076\159\203\034\029\215\089\027\069\041\020\089\214\173\101\055\184\059\252\032\002\076\000\000\017\133\073\068\065\084\139\085\119\181\102\027\156\156\233\070\186\212\154\063\251\082\168\005\017\161\255\024\064\126\206\085\213\062\004\040\082\073\217\023\056\241\247\103\012\050\141\211\196\112\007\128\003\000\072\047\028\139\119\247\239\253\119\149\226\115\000\174\093\198\126\163\125\018\101\156\060\024\199\170\077\094\120\218\117\111\211\016\088\172\002\182\223\220\005\255\084\206\016\205\000\022\236\237\010\118\125\110\001\162\165\053\091\178\243\073\047\114\074\170\222\102\052\004\165\168\013\129\031\015\065\142\085\045\166\149\183\216\180\029\115\199\191\118\214\008\187\056\205\015\119\000\056\111\144\008\031\137\121\250\246\127\139\128\126\014\128\093\239\062\165\162\138\147\135\226\240\245\219\209\051\120\253\190\248\070\071\148\008\182\238\235\196\244\249\012\146\139\181\233\146\034\004\216\245\091\011\112\247\086\167\079\208\204\196\019\004\101\202\011\211\051\023\060\008\253\071\063\180\042\229\127\009\144\166\068\216\048\119\226\225\214\027\177\200\185\038\220\001\224\188\141\076\248\112\218\235\123\247\215\169\160\254\006\001\116\199\027\213\050\197\248\171\009\020\178\010\214\108\241\130\052\113\151\128\032\018\108\220\221\137\115\071\019\200\103\205\047\074\091\249\158\036\134\247\183\112\255\187\106\067\056\217\194\063\063\174\020\251\197\094\238\198\226\139\062\128\086\253\221\137\041\133\252\186\249\137\191\095\048\194\054\206\242\129\059\000\156\171\072\071\095\041\216\187\247\124\077\034\248\053\128\084\053\238\214\063\153\195\204\133\012\214\237\104\135\213\214\188\117\001\022\171\128\117\219\219\113\250\096\012\178\108\094\069\190\119\176\132\109\191\214\058\106\127\075\161\228\124\072\230\091\175\237\241\117\212\130\136\249\095\012\032\115\222\107\196\118\193\054\141\174\190\124\225\031\120\065\005\231\042\184\003\192\089\146\124\244\136\156\222\181\255\017\111\090\251\024\064\186\171\217\043\017\149\113\250\229\056\070\215\186\209\214\217\124\098\065\175\227\116\075\024\093\239\193\169\151\226\208\052\227\115\243\146\067\195\158\223\093\128\205\221\058\106\127\075\209\202\002\064\165\136\013\129\159\014\162\020\213\157\129\123\043\023\002\067\194\134\232\203\015\243\092\010\103\073\184\003\192\185\054\147\135\213\116\228\200\195\109\189\123\222\003\144\209\106\182\042\022\084\028\127\041\006\151\071\194\208\202\234\042\153\235\073\123\151\021\189\067\014\156\121\037\097\232\164\122\209\066\177\243\115\097\180\015\215\182\216\176\017\073\037\108\040\106\045\050\240\232\117\040\144\060\217\129\133\039\250\170\206\247\003\000\001\121\058\048\254\240\126\076\030\230\066\010\156\107\194\029\000\206\013\073\071\142\252\179\183\119\223\032\128\093\213\236\067\053\224\252\137\020\066\115\121\172\222\236\109\154\153\001\239\164\103\208\129\129\049\039\206\029\073\026\018\009\144\028\026\118\254\102\004\221\107\249\065\013\032\136\196\075\208\208\058\081\016\165\032\098\225\209\126\036\079\183\027\145\239\007\001\121\200\063\254\208\039\013\048\141\179\204\105\206\039\048\167\230\164\035\135\255\195\219\183\047\073\041\222\075\072\117\002\082\209\080\017\039\095\138\161\127\196\137\206\222\170\091\155\234\130\111\192\142\141\187\059\048\115\062\131\108\090\255\033\171\125\180\132\061\159\095\064\219\008\063\249\003\128\086\232\068\044\219\058\249\255\252\156\019\193\159\013\161\020\053\228\123\160\105\132\062\016\028\127\248\207\140\216\140\179\252\225\014\000\167\098\210\225\195\175\182\247\239\063\004\074\063\129\042\063\059\165\162\134\019\047\197\081\044\168\088\185\193\011\065\108\190\046\001\119\155\005\123\223\227\131\219\043\097\126\054\143\018\131\116\176\163\075\193\250\123\099\216\120\223\034\172\174\086\147\249\189\054\114\186\069\004\128\052\130\197\151\187\017\061\208\099\200\056\095\000\101\013\218\251\067\227\095\253\190\017\155\113\090\131\230\123\234\114\234\206\224\182\047\174\021\052\028\161\128\033\101\202\253\163\014\124\242\129\213\232\025\050\164\240\169\046\168\026\197\133\227\073\156\059\150\196\229\137\012\226\209\018\232\091\222\235\068\000\124\125\118\216\007\242\232\217\025\065\247\250\124\083\207\077\048\139\068\160\031\177\114\160\222\102\152\074\105\209\138\200\083\125\040\026\115\234\007\001\082\084\084\246\004\078\254\253\037\067\054\228\180\012\252\017\196\209\197\166\077\247\187\083\002\057\002\096\189\017\251\089\044\002\238\252\216\032\222\253\129\222\166\159\044\008\000\074\153\034\157\144\161\200\020\086\187\000\087\155\004\139\069\192\169\185\203\072\090\015\215\219\188\006\133\096\110\214\010\089\091\166\195\233\052\130\248\145\014\196\143\118\130\170\198\124\198\041\112\190\228\117\237\093\060\248\229\214\022\078\224\232\162\249\159\180\156\122\066\006\055\127\241\059\132\224\019\070\109\056\184\194\137\251\062\191\002\003\099\078\163\182\108\040\130\139\105\076\042\143\213\219\140\134\068\203\119\099\058\028\174\183\025\166\080\138\218\017\126\186\199\168\092\063\000\128\128\252\139\127\252\161\207\026\182\033\167\229\224\053\000\156\170\200\068\142\252\200\219\179\111\138\010\228\094\002\084\157\204\204\036\203\056\250\220\034\242\089\005\043\054\120\032\074\203\203\071\117\217\172\152\203\094\000\008\207\251\191\147\082\202\135\180\188\204\250\255\053\130\196\241\043\237\125\074\086\247\156\173\183\065\001\005\020\159\013\156\225\197\126\156\234\224\014\000\167\106\210\145\195\167\125\029\219\190\175\074\226\039\001\084\125\116\167\244\138\130\224\248\171\009\244\143\056\209\225\107\206\078\129\165\016\004\130\096\044\009\077\106\157\074\247\074\073\037\028\040\170\203\039\146\093\008\058\016\250\197\000\050\023\060\134\180\247\189\070\204\038\096\215\220\248\195\207\025\181\033\167\117\225\014\000\199\016\018\139\199\099\233\238\015\252\173\007\249\247\016\130\017\035\246\204\103\021\028\127\033\134\228\098\009\035\107\060\077\063\098\248\117\226\073\025\037\041\084\111\051\026\011\042\034\018\207\065\067\243\071\070\148\156\132\200\115\061\088\124\201\007\053\111\232\035\246\133\128\181\188\045\113\226\107\081\035\055\229\180\046\220\001\224\024\071\244\128\154\137\028\249\134\199\183\087\037\004\183\195\160\026\147\208\076\030\175\060\021\129\170\002\035\107\220\077\217\050\248\086\084\069\066\092\155\172\183\025\013\133\154\247\033\158\107\242\241\191\026\065\242\116\007\230\031\237\071\041\108\104\071\011\005\165\127\022\056\243\200\103\049\127\172\249\061\036\078\195\208\220\079\082\078\195\050\182\253\254\237\138\042\060\003\208\078\035\247\245\245\219\241\193\207\140\096\221\246\170\102\020\213\021\141\106\120\049\244\115\064\228\226\063\175\083\136\142\034\152\157\174\183\025\186\201\251\157\136\030\240\065\078\024\059\235\130\082\196\036\001\119\207\158\126\248\184\161\027\115\056\224\017\000\142\073\036\023\142\044\164\055\222\243\087\222\066\110\043\064\012\105\021\004\174\164\005\078\030\140\033\048\157\199\208\074\023\156\030\099\010\171\106\009\033\004\243\177\028\084\075\188\222\166\052\012\201\184\013\165\038\212\255\151\019\086\068\158\237\065\236\229\110\168\006\104\248\191\021\074\200\047\130\235\035\187\083\207\125\147\231\139\056\166\192\035\000\028\211\025\220\254\192\199\136\074\191\005\192\208\184\168\040\017\236\185\163\007\239\249\149\126\120\059\044\070\110\109\058\019\129\032\034\210\075\245\054\163\049\208\044\152\158\043\067\163\205\163\255\175\100\037\196\094\237\068\230\156\023\212\184\002\191\215\160\069\008\228\083\129\083\015\255\196\224\141\057\156\183\193\029\000\078\077\232\190\249\191\121\028\153\220\099\148\226\102\163\247\022\037\130\221\183\117\227\174\143\013\193\221\214\028\017\129\084\174\132\147\153\159\214\219\140\134\064\205\244\225\242\098\176\222\102\084\132\090\020\145\056\214\129\228\201\054\080\213\140\162\084\122\070\128\247\214\185\241\063\095\102\253\144\156\070\132\059\000\156\154\050\188\229\254\063\164\016\190\012\080\195\223\212\054\167\136\091\222\223\139\091\062\208\007\155\163\241\179\091\047\204\062\005\106\227\105\128\124\120\032\031\202\251\027\090\249\073\083\008\146\039\219\145\056\214\001\173\100\252\103\139\018\040\160\248\147\224\248\195\127\101\248\230\028\206\053\224\014\000\167\230\172\218\250\133\030\025\226\099\148\098\167\025\251\187\060\022\220\118\111\031\246\253\039\095\067\059\002\071\103\038\180\156\253\244\242\232\109\172\130\192\101\119\185\136\084\067\230\112\180\146\136\228\120\027\082\039\218\161\020\204\250\044\209\211\162\098\125\223\236\196\223\204\155\116\003\014\103\073\184\003\192\169\027\035\091\191\248\235\026\200\087\065\169\195\140\253\109\014\017\187\111\235\198\109\247\246\193\219\097\108\117\182\017\004\227\139\153\073\249\025\079\189\237\168\039\084\118\148\166\130\217\134\083\122\082\011\034\146\167\219\145\060\217\102\202\137\255\053\138\132\226\139\254\051\015\127\195\172\027\112\056\215\131\059\000\156\186\178\122\245\239\217\138\078\250\029\080\250\017\179\238\033\074\004\219\110\234\196\237\031\030\064\207\064\227\076\028\084\084\013\047\069\126\076\009\049\104\050\076\019\146\014\246\209\136\028\108\152\159\191\156\150\144\060\217\129\244\153\054\104\138\153\102\209\231\053\171\114\079\232\216\215\151\233\228\035\078\051\208\048\095\060\078\107\051\184\233\254\059\136\064\126\000\160\203\172\123\016\001\216\178\183\003\183\124\176\031\195\171\092\102\221\134\137\035\193\067\114\094\156\107\188\240\068\141\088\152\234\068\086\168\191\176\093\033\228\064\234\116\027\050\147\110\064\051\245\177\024\003\085\063\026\056\243\181\003\102\222\132\195\169\004\238\000\112\026\009\050\184\229\139\255\135\128\254\001\064\076\077\222\015\174\112\097\255\093\061\216\126\115\039\044\214\250\165\225\167\022\023\016\080\158\175\219\253\235\137\086\182\098\218\095\170\219\096\036\077\033\200\094\240\034\121\186\205\208\041\125\075\067\020\002\237\043\254\241\071\254\047\000\212\228\155\113\056\021\193\029\000\078\195\177\106\235\023\122\138\084\248\055\002\220\105\246\071\212\238\020\177\235\214\110\236\187\211\135\158\065\083\074\017\174\075\174\164\226\088\226\071\160\045\248\078\200\047\244\033\084\168\125\251\095\057\105\065\114\188\013\233\115\109\208\074\166\059\127\020\160\047\056\075\142\143\094\188\248\151\139\102\223\140\195\097\129\059\000\156\134\101\100\203\239\239\210\160\126\015\192\106\179\239\069\008\193\202\141\030\236\125\079\055\054\238\238\168\105\084\224\213\208\075\040\010\205\209\007\111\036\145\203\061\072\163\054\133\239\090\089\064\118\210\133\204\005\047\010\126\039\104\045\252\045\130\089\162\145\143\250\207\060\116\180\006\119\227\112\152\225\014\000\167\225\025\218\242\192\167\000\250\008\128\154\012\000\176\088\004\108\216\213\134\237\183\116\099\253\182\054\211\135\015\093\138\004\016\210\014\154\122\143\070\131\082\001\179\051\002\020\152\055\015\129\082\160\180\224\064\122\194\131\204\069\047\052\185\102\143\187\180\064\132\223\155\059\253\149\111\213\234\134\028\142\030\184\003\192\105\022\200\240\230\007\254\023\037\244\143\000\212\172\109\204\211\097\197\182\253\029\216\241\238\046\012\174\052\167\112\048\149\047\225\100\186\181\084\001\075\177\046\248\211\017\115\246\142\218\144\185\232\065\230\188\007\074\174\118\202\144\004\180\076\009\249\106\224\244\195\095\002\207\243\115\154\000\238\000\112\154\138\213\171\127\207\086\176\171\127\069\008\249\109\000\053\021\143\233\238\179\097\227\238\014\108\220\221\142\145\181\110\008\196\184\175\207\043\161\103\081\106\128\106\248\090\017\159\237\067\092\051\038\237\065\041\080\012\057\144\157\118\033\055\237\070\185\198\154\066\004\040\083\066\191\037\165\243\015\204\204\124\179\088\211\155\115\056\085\192\029\000\078\083\050\054\246\160\093\246\044\254\157\008\250\089\090\099\071\000\000\156\030\009\171\055\121\176\126\103\059\054\237\234\128\205\089\093\211\194\249\240\044\194\244\021\131\172\107\124\230\166\029\144\137\254\233\127\084\033\040\204\059\144\187\236\066\230\146\007\106\174\246\138\143\004\040\107\032\223\038\137\240\023\003\129\031\020\106\110\000\135\083\037\220\001\224\052\053\003\187\062\239\020\101\203\035\148\224\211\160\168\203\036\032\201\042\096\245\038\015\214\108\109\195\202\141\030\244\013\059\064\024\163\003\137\108\001\167\179\063\055\201\194\198\162\156\105\195\236\034\227\012\004\010\148\022\109\040\004\156\200\251\029\040\004\029\208\202\117\107\223\084\008\232\183\105\194\118\127\032\240\215\252\197\207\105\090\184\003\192\089\022\012\221\244\135\014\045\091\254\091\001\248\012\064\235\042\045\235\246\072\088\185\201\131\149\155\188\088\181\201\011\095\255\141\213\007\041\040\094\014\061\001\069\072\213\192\194\250\146\156\235\199\162\026\184\225\117\229\148\005\121\191\019\005\191\019\249\128\003\170\105\090\252\149\065\128\018\037\228\219\154\069\254\125\174\224\199\089\014\112\007\128\179\172\216\181\235\243\150\104\089\250\191\053\141\252\062\008\058\235\109\015\000\120\059\044\024\091\239\193\240\074\023\134\086\185\048\176\194\009\155\253\234\151\217\217\133\105\044\226\072\029\044\172\045\254\105\039\074\036\243\182\063\211\202\002\074\017\027\138\011\118\020\195\087\254\081\050\141\050\218\153\038\040\200\195\193\046\223\255\196\129\007\149\122\091\195\225\024\005\119\000\056\203\150\129\205\247\127\092\032\248\223\000\089\089\111\091\222\138\064\008\124\067\014\012\175\114\098\104\149\027\195\043\157\240\013\058\144\045\203\024\207\254\172\222\230\153\138\156\236\196\076\036\006\057\110\129\188\104\127\227\133\047\199\172\181\233\205\103\128\000\211\026\085\255\123\240\204\215\254\189\222\182\112\056\102\192\029\000\206\178\103\108\251\151\182\171\090\249\043\148\226\093\000\026\114\252\046\033\004\237\221\022\008\222\012\060\195\069\184\123\101\184\123\203\112\245\148\097\117\169\245\054\079\023\229\188\128\255\191\189\251\011\177\172\046\224\000\254\253\157\251\103\103\198\092\183\220\118\049\103\115\169\009\148\218\004\215\064\009\098\237\165\135\192\162\030\130\124\145\030\084\118\011\031\042\016\162\220\144\232\085\089\144\080\176\158\124\168\167\008\009\132\168\032\072\196\077\182\220\140\090\108\181\241\111\203\142\205\142\051\227\220\123\207\175\135\025\146\160\040\087\103\238\213\251\249\192\225\112\238\185\015\223\151\223\239\126\057\247\240\251\173\188\210\207\202\075\189\172\188\220\207\202\139\189\044\191\176\043\027\023\038\119\139\230\090\075\155\082\031\171\077\243\213\023\078\157\120\114\220\121\096\059\041\000\076\141\189\159\252\202\165\051\203\179\223\079\114\075\146\061\227\206\243\255\234\206\182\153\221\051\204\236\251\134\153\217\179\117\092\182\117\189\123\148\254\165\163\116\103\118\118\061\253\225\122\147\141\149\078\094\191\208\201\218\249\110\214\150\186\089\095\234\102\253\213\110\086\207\247\178\254\106\039\195\245\137\236\090\255\205\082\146\135\095\235\015\190\181\116\242\129\119\255\139\024\016\005\128\041\117\229\181\071\111\074\045\247\036\245\134\082\183\119\227\161\157\080\074\210\155\107\211\155\027\189\113\158\109\211\217\213\166\211\175\105\186\155\207\215\187\187\218\148\173\223\229\238\236\102\105\024\174\109\126\208\014\075\070\131\205\041\097\180\081\054\175\055\154\012\086\155\012\086\059\255\118\158\180\199\245\023\105\084\075\030\075\169\223\126\254\212\253\191\028\119\024\216\105\010\000\211\237\240\109\189\249\097\255\235\105\235\177\036\243\227\142\195\246\043\201\203\109\242\096\239\194\251\191\119\246\236\113\011\247\048\181\020\000\216\242\129\195\119\126\048\131\193\119\154\090\062\159\228\242\113\231\225\237\083\146\165\154\252\188\063\216\248\238\051\127\122\240\207\227\206\003\147\064\001\128\255\096\254\186\163\011\117\084\190\217\212\124\174\214\236\031\119\030\222\188\146\044\215\148\095\164\191\113\247\226\201\007\254\048\238\060\048\105\020\000\248\031\230\175\185\253\035\233\118\239\042\037\159\173\181\238\055\108\038\087\073\206\183\165\060\218\233\148\123\158\123\242\196\031\199\157\007\038\153\153\012\222\132\253\031\255\198\190\094\093\187\035\169\095\044\041\087\215\164\063\238\076\083\173\100\152\154\051\109\242\211\222\176\119\223\179\079\223\251\226\184\035\193\059\133\002\000\111\193\129\067\183\127\170\166\123\091\146\155\146\122\197\230\251\248\108\163\154\212\115\073\249\077\173\163\135\158\127\234\007\143\196\214\187\112\081\076\086\240\054\057\120\228\214\153\246\252\037\095\170\053\095\168\201\225\036\087\100\066\023\030\122\007\105\147\156\043\169\167\106\109\126\118\089\221\251\195\211\167\143\095\252\054\130\192\191\040\000\176\141\174\058\116\236\198\081\202\151\083\114\036\169\031\074\205\220\184\051\077\182\178\145\082\207\166\150\199\155\210\254\248\185\223\239\123\036\057\190\179\171\028\193\148\080\000\096\007\093\121\245\177\203\155\094\123\115\077\249\116\074\249\088\169\185\170\173\217\083\202\148\141\197\154\154\146\149\146\044\214\090\158\078\083\126\221\233\117\126\242\236\073\255\225\195\078\153\174\073\007\038\212\129\143\030\253\068\154\242\153\090\115\099\045\089\104\074\246\213\154\247\036\153\148\045\241\046\214\048\201\074\077\094\041\201\153\146\252\182\182\205\163\139\167\079\060\062\238\096\048\237\020\000\152\096\007\143\220\058\211\254\125\238\250\182\148\235\218\038\135\154\054\011\041\117\062\201\123\147\204\038\165\159\164\147\157\031\203\053\041\163\164\221\072\178\150\148\165\212\044\182\077\253\075\211\150\167\058\169\079\148\189\171\191\059\251\171\031\089\105\015\038\148\002\000\239\002\011\011\095\219\061\184\100\240\225\081\058\007\051\202\129\036\243\181\100\111\073\233\213\154\094\041\217\189\245\213\185\036\187\146\164\164\238\078\146\154\178\188\117\239\245\036\171\073\082\107\253\071\041\101\088\083\007\165\109\207\165\052\139\233\228\111\221\082\255\218\093\233\060\115\230\204\137\229\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\111\221\063\001\004\233\040\231\213\095\114\048\000\000\000\000\073\069\078\068\174\066\096\130",crop=true},
                {button=myScope,file='s2r_beta_egg.png',bytes="\137\080\078\071\013\010\026\010\000\000\000\013\073\072\068\082\000\000\002\000\000\000\002\000\008\006\000\000\000\244\120\212\250\000\000\000\004\115\066\073\084\008\008\008\008\124\008\100\136\000\000\000\009\112\072\089\115\000\000\014\196\000\000\014\196\001\149\043\014\027\000\000\000\025\116\069\088\116\083\111\102\116\119\097\114\101\000\119\119\119\046\105\110\107\115\099\097\112\101\046\111\114\103\155\238\060\026\000\000\032\000\073\068\065\084\120\156\236\221\119\152\085\213\213\199\241\239\185\247\078\111\048\012\109\104\051\012\189\247\094\004\065\081\145\162\160\130\138\189\160\070\077\098\143\061\166\039\026\019\091\140\026\095\123\193\142\168\081\081\131\024\069\016\065\016\164\055\005\065\122\135\097\238\251\199\097\034\234\012\204\156\189\207\173\191\207\243\204\163\009\115\214\222\014\112\247\058\187\172\237\032\034\137\162\033\080\012\052\006\026\028\252\223\245\128\252\067\190\114\015\126\111\006\144\126\240\223\119\001\123\015\254\251\118\096\211\033\095\235\129\111\128\085\192\202\131\255\092\005\148\249\251\159\034\034\126\115\162\221\001\017\169\182\124\160\203\193\175\246\064\043\160\037\144\019\161\246\247\000\011\128\133\192\124\096\046\240\041\176\046\066\237\139\136\005\074\000\068\098\091\000\104\007\012\000\250\001\061\112\223\242\099\209\026\220\068\224\019\224\003\096\038\080\026\213\030\137\072\165\148\000\136\196\158\018\224\216\131\095\003\128\026\209\237\142\103\059\128\015\129\247\129\055\129\057\081\237\141\136\136\072\140\009\002\131\129\191\003\139\129\112\130\126\173\006\254\001\140\000\050\173\252\228\068\068\068\226\076\010\112\002\240\048\176\129\232\015\206\145\254\218\001\060\003\156\132\187\033\081\068\068\036\097\057\064\031\224\094\224\059\162\063\008\199\202\215\118\224\009\096\040\238\158\007\017\017\145\132\080\008\220\008\044\037\250\131\109\172\127\173\002\238\000\154\123\250\073\139\136\136\068\089\000\056\030\120\025\216\079\244\007\214\120\251\042\003\222\193\093\034\008\085\243\103\047\034\034\018\113\185\192\021\232\109\223\230\215\106\224\087\064\157\106\252\062\136\136\136\068\068\049\112\023\176\149\232\015\152\137\250\181\027\120\000\045\015\136\136\072\012\104\003\060\134\166\249\035\249\117\000\120\017\232\085\133\223\031\017\017\017\171\186\002\047\224\014\070\209\030\016\147\249\235\045\220\147\021\034\034\034\190\106\009\060\135\187\073\045\218\131\159\190\190\255\250\016\024\116\152\223\055\017\017\017\079\010\113\171\216\105\170\063\182\191\038\227\094\144\036\034\071\160\187\000\068\014\175\006\112\045\112\057\113\080\190\182\176\078\013\154\055\169\067\163\250\053\105\092\063\159\134\245\242\169\157\159\077\126\094\022\249\185\089\212\204\203\036\020\012\144\154\026\034\051\061\021\128\093\123\246\177\111\095\041\007\202\202\216\180\101\023\027\183\238\100\211\214\157\108\216\180\157\213\107\055\177\242\155\077\172\090\187\137\101\171\055\176\118\195\214\040\255\023\086\073\025\240\056\112\051\110\093\001\017\169\128\018\000\145\138\165\003\151\001\215\227\094\191\027\083\082\066\065\218\054\043\164\075\155\198\116\110\211\152\182\205\011\105\085\092\151\220\108\127\171\234\110\222\186\139\005\203\214\242\229\210\181\204\254\114\021\051\231\173\100\225\178\117\028\040\043\243\181\093\143\246\224\222\175\112\007\176\045\202\125\017\137\057\074\000\068\126\106\060\240\123\160\081\180\059\082\046\035\045\133\238\029\138\232\223\181\057\003\187\183\160\075\219\198\164\167\166\068\187\091\000\236\220\181\151\207\190\092\197\180\089\139\121\239\147\069\204\156\183\130\253\165\007\162\221\173\067\125\011\220\000\060\138\059\059\032\034\040\001\016\057\084\011\224\062\224\232\104\119\004\160\118\126\014\199\015\104\199\240\065\029\024\212\179\101\204\012\248\071\178\115\247\062\166\127\182\132\041\255\153\199\155\255\153\199\154\111\055\071\187\075\229\102\226\022\105\250\040\218\029\017\137\005\074\000\068\220\233\254\235\113\215\250\211\162\217\145\226\134\005\156\056\168\003\039\014\234\064\143\014\197\004\003\241\127\055\206\220\175\214\048\249\253\047\152\244\214\044\022\173\248\054\218\221\009\003\255\002\174\001\054\070\185\047\034\081\165\004\064\146\221\049\184\183\243\053\139\086\007\234\021\228\114\198\136\094\140\029\214\149\182\205\010\163\213\141\136\152\251\213\026\158\127\115\022\147\222\154\197\234\117\081\157\025\216\000\092\141\091\196\041\028\205\142\136\068\139\018\000\073\086\245\113\075\247\158\026\141\198\131\129\000\199\244\109\195\089\163\123\051\172\127\059\066\193\248\127\211\175\142\178\178\048\083\063\089\200\099\047\127\204\235\031\204\101\239\190\210\104\117\229\125\224\098\224\171\104\117\064\036\090\148\000\072\178\113\128\075\128\223\000\121\145\110\188\073\097\062\103\142\236\205\153\035\122\209\160\110\141\072\055\031\147\054\109\221\201\147\175\125\194\131\207\078\099\249\215\223\069\163\011\187\129\091\128\059\113\043\059\138\036\005\037\000\146\076\026\225\174\255\070\124\147\223\128\238\205\249\249\089\067\056\186\087\107\002\001\253\181\171\072\089\089\152\055\166\205\227\129\103\062\224\253\025\139\008\135\035\062\051\255\009\112\046\240\101\164\027\022\137\006\125\018\073\178\056\029\184\007\183\176\079\068\056\142\195\009\003\219\243\139\115\134\210\163\125\081\164\154\077\008\095\044\250\154\063\060\244\038\175\078\157\067\089\089\068\019\129\189\192\173\192\159\208\108\128\036\056\037\000\146\232\106\224\022\131\057\035\082\013\006\002\014\035\143\238\196\013\023\030\071\235\146\250\145\106\054\033\045\092\182\142\191\252\235\109\158\123\099\102\164\139\013\253\023\055\105\092\030\201\070\069\034\073\009\128\036\178\097\192\195\184\117\252\125\151\158\154\194\132\081\189\185\098\194\209\052\041\140\185\226\129\113\109\209\138\111\249\211\195\255\230\249\055\103\082\122\032\098\137\192\070\224\124\224\229\072\053\040\018\073\074\000\036\017\101\224\086\242\251\025\017\248\051\238\056\014\163\134\116\226\215\151\143\164\168\065\045\191\155\075\106\043\191\217\196\061\079\078\229\145\023\166\071\242\228\192\227\192\068\096\103\164\026\020\137\004\037\000\146\104\058\000\207\227\086\245\243\221\160\158\045\185\227\138\081\116\108\213\048\018\205\201\065\139\087\172\231\134\187\094\226\141\105\243\034\213\228\124\096\028\240\069\164\026\020\241\155\018\000\073\036\103\224\094\217\235\251\173\125\045\139\235\113\227\197\199\051\122\104\103\191\155\146\195\120\127\198\087\092\247\151\151\152\183\248\235\072\052\183\007\184\014\248\027\042\030\036\009\064\009\128\036\130\116\220\015\229\011\252\110\168\065\221\026\220\056\241\004\078\031\222\083\199\249\098\068\233\129\050\030\121\225\067\238\184\127\010\155\182\070\100\150\254\085\224\060\032\042\069\011\068\108\209\039\152\196\187\198\184\083\254\061\252\108\036\020\012\112\193\041\253\185\229\146\019\201\206\138\234\117\001\082\137\045\219\118\113\231\163\239\112\239\083\239\069\098\127\192\026\224\036\224\083\191\027\018\241\139\018\000\137\103\195\113\107\185\215\244\179\145\174\109\155\240\247\027\079\163\067\075\173\243\199\131\069\043\190\229\170\063\078\098\234\199\011\253\110\106\055\238\172\211\147\126\055\036\226\007\037\000\018\143\130\192\077\007\191\124\043\162\159\149\145\202\181\023\012\227\138\009\071\039\196\173\124\201\230\165\183\103\115\197\111\159\141\196\178\192\131\192\101\192\126\191\027\018\177\073\009\128\196\155\090\192\115\192\096\063\027\025\049\184\035\127\190\102\012\133\117\084\175\063\158\173\221\176\149\159\255\238\057\038\191\063\215\239\166\222\006\078\003\054\249\221\144\136\045\074\000\036\158\180\004\038\227\227\213\189\013\234\214\224\174\235\079\229\248\001\237\252\106\066\162\096\210\091\179\184\234\143\147\248\110\243\014\063\155\089\006\140\066\071\005\037\078\004\163\221\001\145\042\234\007\252\027\240\109\033\126\244\208\206\076\186\251\098\173\245\039\160\054\205\010\057\123\116\031\182\108\219\205\236\005\171\253\106\166\038\048\001\088\132\046\020\146\056\160\004\064\226\193\005\184\211\254\057\126\004\207\203\201\224\254\091\078\231\166\137\039\144\145\158\234\071\019\018\003\210\211\082\056\110\064\059\058\182\106\196\244\207\150\176\099\215\094\063\154\073\005\198\030\252\231\251\168\094\128\196\048\045\001\072\044\115\112\239\105\191\197\175\006\122\118\044\230\161\059\038\080\220\160\192\175\038\036\006\109\220\178\131\139\110\121\146\055\253\173\036\248\050\048\030\247\180\128\072\204\209\012\128\196\170\044\220\183\254\139\252\008\158\018\010\114\221\005\195\120\240\182\051\201\207\203\242\163\009\137\097\153\233\169\140\029\214\149\026\185\025\252\103\198\034\014\248\115\229\112\043\224\104\224\021\096\151\031\013\136\152\208\012\128\196\162\134\192\107\064\039\063\130\183\109\086\200\195\191\153\064\187\230\013\252\008\047\113\230\179\249\171\056\235\218\071\088\254\205\070\191\154\152\015\028\007\248\182\249\064\196\011\205\000\072\172\233\128\187\118\218\220\143\224\019\070\246\226\153\187\046\208\241\062\249\159\250\117\242\056\115\068\047\086\046\095\207\151\043\190\245\163\137\058\184\251\002\222\006\214\251\209\128\136\023\074\000\036\150\244\192\221\233\095\215\118\224\180\212\016\191\251\249\104\110\253\217\008\066\065\253\177\151\031\074\075\013\049\234\216\046\052\201\203\097\234\172\197\236\047\061\096\187\137\092\224\076\096\022\176\212\118\112\017\047\244\073\040\177\098\024\048\005\200\179\029\184\073\097\062\047\223\123\041\035\006\119\180\029\090\018\076\135\118\077\056\161\083\011\166\207\089\198\006\251\021\004\211\128\083\112\143\009\206\183\029\092\164\186\148\000\072\044\024\013\076\002\050\108\007\030\208\189\057\175\220\123\041\037\141\107\219\014\045\009\170\118\097\077\198\015\232\200\226\229\223\242\213\154\013\182\195\135\128\049\184\039\003\166\219\014\046\082\029\074\000\036\218\038\002\143\002\041\054\131\006\002\014\215\095\120\028\247\221\124\058\217\153\186\189\079\170\039\053\039\157\209\189\218\192\254\050\166\207\095\097\059\188\003\012\197\061\233\242\142\237\224\034\085\165\004\064\162\233\087\192\095\176\124\026\165\070\110\038\079\254\233\124\206\030\221\007\199\209\065\023\241\198\201\076\161\095\203\038\180\045\172\205\091\179\190\242\099\095\064\095\160\000\120\195\118\096\145\170\080\002\032\209\224\000\127\002\110\180\029\184\184\065\001\083\030\252\025\061\058\020\219\014\045\073\200\201\072\161\101\157\090\012\235\220\130\119\102\047\102\235\206\061\182\155\232\001\052\000\094\071\085\003\037\194\148\000\072\164\005\129\135\129\075\108\007\238\221\169\132\201\255\184\140\070\245\242\109\135\150\100\229\000\153\033\106\167\103\112\074\223\246\204\092\180\134\213\027\182\216\110\165\011\208\024\183\246\133\146\000\137\024\037\000\018\073\001\224\095\192\089\182\003\159\052\180\011\079\253\229\124\114\179\173\239\035\148\036\231\056\014\078\102\010\153\101\001\078\237\223\145\173\187\246\048\115\209\026\219\205\116\198\189\237\242\021\160\204\118\112\145\138\040\001\144\072\009\000\143\096\121\240\119\028\135\027\046\058\158\191\092\059\134\148\144\254\056\139\079\014\038\001\206\158\082\134\118\106\078\173\220\044\222\157\189\132\112\216\234\011\123\059\160\005\074\002\036\066\244\137\041\145\224\000\247\003\231\217\012\154\150\026\226\129\219\206\096\226\184\129\218\236\039\254\011\056\056\025\041\176\123\063\093\075\026\208\190\168\030\083\102\044\164\244\128\213\177\186\029\238\146\192\139\128\245\093\135\034\135\082\002\032\126\043\031\252\173\094\234\147\159\151\197\011\127\187\152\227\007\180\183\025\086\228\240\002\014\078\122\136\240\174\253\180\104\080\192\081\029\074\152\252\201\002\118\239\219\111\179\149\022\184\075\002\047\002\165\054\003\139\028\074\009\128\248\041\000\060\004\092\096\051\104\147\194\124\222\122\232\074\058\182\106\100\051\172\072\213\004\003\056\169\033\194\187\246\209\160\086\030\067\187\182\096\202\140\005\236\216\189\207\102\043\045\248\126\038\064\073\128\248\066\009\128\248\197\001\238\005\046\180\025\180\069\081\093\166\060\120\057\069\013\106\217\012\043\082\061\161\128\251\181\187\148\058\053\178\025\213\167\029\239\204\094\204\198\109\086\111\253\109\142\123\057\214\036\180\039\064\124\160\004\064\252\080\062\248\079\180\025\180\115\235\070\188\254\143\159\081\175\192\250\117\001\034\213\230\164\006\221\067\123\123\015\144\151\149\206\216\001\029\249\120\193\042\214\124\183\213\102\051\045\129\166\184\027\003\117\068\080\172\082\002\032\126\184\015\203\131\127\191\174\205\120\229\222\075\169\153\155\105\051\172\136\017\039\061\004\165\101\176\191\140\140\212\020\078\238\215\158\185\203\215\178\116\237\070\155\205\116\000\242\081\197\064\177\076\009\128\216\246\107\224\151\054\003\030\215\191\029\207\222\117\033\089\025\170\233\047\177\199\201\012\193\158\082\056\016\038\037\020\228\164\126\237\089\181\097\011\243\086\172\179\217\076\079\220\061\053\239\219\012\042\201\077\009\128\216\116\009\240\007\155\001\199\014\235\202\163\191\063\135\180\212\144\205\176\034\022\057\056\153\033\194\187\074\161\044\076\032\224\048\188\103\107\054\110\219\197\103\075\190\182\217\208\064\096\039\240\145\205\160\146\188\148\000\136\045\227\112\119\252\091\059\144\127\254\152\126\220\119\243\233\132\130\001\091\033\069\252\225\124\127\060\144\176\091\160\234\152\174\045\216\180\125\023\179\022\091\077\002\134\002\095\003\159\217\012\042\201\073\009\128\216\048\004\120\014\139\087\250\094\050\254\040\254\114\237\088\021\248\145\248\017\012\064\106\016\118\186\053\001\028\199\097\104\151\022\108\218\177\155\089\139\173\149\014\118\128\019\128\133\192\124\091\065\037\057\041\001\016\083\061\128\041\128\181\221\121\231\156\212\135\059\053\248\075\028\114\066\007\103\171\246\186\069\252\220\036\160\057\155\237\038\001\001\096\036\048\011\088\098\043\168\036\031\037\000\098\162\013\240\046\096\237\092\222\249\099\251\115\247\013\167\106\240\151\184\229\164\135\008\239\043\115\079\007\240\125\018\096\121\038\032\008\140\002\166\002\214\111\038\146\228\160\004\064\188\106\136\251\225\083\207\086\192\009\035\123\113\247\013\167\017\008\104\240\151\248\230\100\164\184\251\001\202\220\163\251\229\073\128\229\155\004\083\129\209\192\075\192\038\091\065\037\121\040\001\016\047\010\112\143\035\149\216\010\120\214\168\222\220\115\211\120\013\254\146\024\156\131\053\002\118\126\095\030\216\113\028\134\116\110\206\246\221\123\249\244\171\213\182\090\202\196\221\024\248\020\176\199\086\080\073\014\074\000\164\186\210\128\215\113\235\148\091\113\230\136\094\026\252\037\241\004\003\056\041\065\119\038\224\160\242\036\096\235\206\061\124\186\200\090\018\080\128\091\039\224\105\116\131\160\084\131\018\000\169\014\007\120\004\056\209\086\192\147\143\233\194\063\110\063\131\096\064\071\253\036\001\165\004\221\042\254\251\126\056\046\031\221\185\025\223\108\220\198\156\101\107\109\181\084\004\052\006\094\182\021\080\018\159\018\000\169\142\027\129\043\109\005\059\249\152\046\060\242\219\179\052\248\075\066\115\050\066\132\247\150\066\233\247\165\252\221\058\001\045\153\191\114\029\139\190\254\206\086\083\157\112\103\000\254\099\043\160\036\054\037\000\082\085\099\112\047\248\177\050\079\063\176\123\011\158\248\211\121\164\132\244\071\080\018\159\147\017\034\188\115\255\015\174\243\009\004\028\078\236\221\150\153\139\214\176\124\157\181\061\124\131\128\165\192\092\091\001\037\113\233\211\087\170\162\027\238\109\100\169\054\130\117\105\211\152\151\239\185\132\204\012\043\225\068\098\159\227\184\069\130\014\217\015\000\016\012\004\024\222\179\053\083\231\044\101\221\166\237\086\090\002\134\003\031\002\043\108\004\148\196\165\185\087\057\146\038\192\100\044\021\250\105\218\168\054\147\238\190\152\236\044\093\236\035\201\197\073\015\225\228\252\244\207\125\118\070\026\047\222\124\022\045\027\214\182\213\084\042\048\009\104\110\043\160\036\038\037\000\114\056\057\192\171\064\093\027\193\234\215\206\227\181\251\047\163\078\173\028\027\225\068\226\142\147\151\142\083\193\197\086\181\114\051\121\229\182\115\104\092\167\166\173\166\106\225\094\031\092\096\043\160\036\030\037\000\082\153\032\240\044\238\093\228\198\242\114\050\120\233\158\137\052\041\204\183\017\078\036\062\057\224\020\100\184\075\002\063\082\088\043\151\151\110\057\139\130\220\044\091\173\149\000\207\000\186\074\083\042\164\061\000\082\153\187\128\051\108\004\202\072\075\225\197\191\079\164\107\219\038\054\194\137\196\183\128\003\033\007\118\151\254\228\151\106\229\102\050\176\067\009\207\079\155\203\190\082\043\071\250\155\226\046\223\189\109\035\152\036\022\037\000\082\145\241\192\031\109\004\010\006\002\060\250\251\115\024\210\167\181\141\112\034\009\193\073\013\186\119\005\236\047\251\201\175\213\203\207\161\099\211\066\094\248\240\011\202\194\225\010\158\174\182\222\192\002\116\123\160\252\136\018\000\249\177\014\184\059\254\173\092\237\123\215\245\167\048\238\132\030\054\066\137\036\020\039\061\244\131\251\002\014\213\180\126\045\106\102\103\240\239\207\022\089\105\010\056\014\119\063\207\006\027\001\037\049\040\001\144\067\213\000\222\193\210\166\191\075\199\015\226\218\243\143\181\017\074\036\241\056\014\164\005\097\231\254\010\127\185\107\139\134\108\218\190\203\214\013\130\169\184\119\006\060\142\238\012\144\131\148\000\072\057\007\247\066\145\190\054\130\013\237\211\134\007\110\059\067\245\253\069\014\195\009\006\220\068\096\207\079\247\003\128\091\050\248\139\229\107\089\108\167\090\096\045\160\045\238\230\094\043\107\011\018\223\148\000\072\185\091\128\137\054\002\181\106\090\143\151\239\153\072\070\186\010\253\136\028\137\147\022\130\221\007\224\192\079\247\003\004\028\135\097\221\090\242\239\089\139\088\191\101\135\141\230\090\002\165\168\092\176\160\004\064\092\067\129\007\177\112\044\180\086\141\108\166\252\227\103\212\043\200\051\239\149\072\146\112\210\130\132\119\084\188\020\144\154\018\226\248\030\173\121\233\195\047\216\190\123\175\141\230\142\002\102\002\139\109\004\147\248\165\058\000\210\004\119\234\223\056\025\076\079\077\225\185\191\094\072\113\067\213\030\017\169\150\148\032\078\094\229\213\049\235\231\231\240\204\013\103\144\105\103\086\045\000\060\129\091\039\064\146\152\018\128\228\150\014\188\128\133\106\097\142\227\112\239\205\227\233\217\161\216\188\087\034\073\200\201\075\171\176\074\096\185\142\037\133\252\223\085\167\218\186\061\179\038\240\034\150\074\124\075\124\210\018\064\114\251\039\112\188\141\064\055\092\116\028\019\199\013\180\017\074\036\105\029\110\041\000\160\089\097\001\105\041\065\222\159\179\212\070\115\117\129\006\184\199\126\037\009\041\001\072\094\103\002\183\217\008\116\210\208\046\252\229\218\177\056\021\148\055\021\145\106\008\030\124\187\223\091\241\169\000\128\094\173\026\243\213\154\013\044\092\189\222\070\139\157\112\247\002\124\097\035\152\196\023\125\098\039\167\018\224\051\032\215\052\080\243\162\058\252\231\241\171\201\201\074\055\239\149\136\000\016\094\183\147\240\190\202\147\128\157\123\246\049\248\154\007\088\176\202\074\018\176\003\232\010\088\169\058\036\241\067\123\000\146\079\010\240\036\022\006\255\172\204\052\158\254\243\005\026\252\069\044\115\106\165\115\184\247\179\172\244\084\158\188\110\060\185\153\086\254\238\101\227\126\038\232\220\110\146\209\018\064\242\249\003\112\138\105\016\199\113\120\228\055\103\209\175\107\051\011\093\018\145\031\008\006\220\241\191\146\002\065\000\249\057\153\180\106\084\135\023\062\180\050\123\095\136\251\114\240\174\141\096\018\031\148\000\036\151\099\128\123\177\176\244\243\139\179\135\106\211\159\136\143\156\180\016\225\221\165\112\160\242\162\125\205\027\020\176\175\244\000\255\253\114\165\141\038\251\000\031\001\203\108\004\147\216\167\004\032\121\212\001\222\196\194\212\255\128\238\205\085\230\087\036\018\082\130\176\107\223\097\191\101\064\251\166\204\092\188\134\101\107\055\153\182\230\000\199\226\222\023\176\211\052\152\196\062\237\001\072\014\014\240\008\080\223\052\080\189\130\092\030\249\205\217\132\130\250\163\035\226\055\039\045\136\147\117\248\165\249\128\227\240\240\047\078\161\073\221\154\054\154\172\011\252\011\109\016\079\010\154\001\072\014\087\003\151\154\006\073\009\005\121\225\111\023\211\186\169\113\030\033\034\085\228\164\030\188\054\056\092\249\082\064\070\106\010\253\218\021\243\244\123\159\083\090\193\157\002\213\212\028\216\012\124\098\026\072\098\155\018\128\196\215\013\119\135\175\241\239\245\159\175\025\195\168\163\059\155\247\072\068\170\046\224\064\032\000\187\043\047\016\004\080\183\102\014\245\106\230\048\101\198\066\027\173\014\002\038\003\235\108\004\147\216\164\004\032\177\229\000\111\003\181\077\003\141\057\182\043\191\190\098\164\121\143\068\164\218\156\212\032\225\189\165\080\122\248\091\124\059\054\045\100\217\218\077\204\095\105\060\110\135\112\047\013\122\020\056\124\230\033\113\075\009\064\098\187\015\024\098\026\164\168\065\045\038\221\125\017\105\169\041\022\186\036\034\094\056\169\033\194\059\015\191\033\016\096\080\199\018\094\154\062\143\045\059\118\155\054\089\000\228\001\083\076\003\073\108\210\078\174\196\053\020\056\215\052\072\040\024\224\225\223\156\069\110\118\134\133\046\137\136\103\041\001\156\156\202\111\012\044\151\147\153\198\163\087\157\074\106\200\202\251\221\037\184\159\037\146\128\052\003\144\152\242\112\143\252\229\153\006\186\249\210\225\156\050\172\155\121\143\068\196\152\147\022\130\093\251\161\236\240\075\001\245\243\115\073\009\089\185\052\200\001\250\227\158\034\058\242\244\131\196\021\037\000\137\233\031\192\000\211\032\253\186\054\227\239\055\141\035\160\075\126\068\098\131\003\132\130\110\018\112\004\061\091\053\230\147\175\086\179\098\157\113\125\128\026\184\245\067\180\020\144\096\244\201\158\120\078\192\221\189\107\164\086\141\108\062\126\246\058\234\215\054\158\068\016\017\203\194\027\118\186\085\002\143\096\253\150\029\244\253\249\061\124\187\121\135\113\147\184\069\130\222\054\013\036\177\067\123\000\018\075\013\224\001\211\032\142\227\112\239\205\227\052\248\139\196\040\167\102\070\149\094\223\234\212\200\230\254\159\157\108\227\170\110\007\120\016\247\100\145\036\008\045\001\036\150\127\002\253\076\131\076\028\055\144\203\078\031\100\161\059\034\226\139\128\003\101\192\190\003\071\252\214\166\245\107\177\101\231\110\102\046\090\099\218\170\150\002\018\140\150\000\018\199\137\192\171\166\065\218\052\171\207\007\143\095\077\070\154\142\252\137\196\180\178\048\101\223\108\063\226\134\064\128\189\251\075\057\250\218\127\048\119\217\090\211\086\181\020\144\064\180\004\144\024\242\113\055\254\025\073\079\077\225\241\063\156\171\193\095\036\030\004\028\156\188\244\042\125\107\090\074\136\071\126\113\010\025\230\181\060\028\220\207\154\108\211\064\018\125\090\002\072\012\015\225\094\229\105\228\246\203\071\114\194\192\246\022\186\035\034\145\224\164\005\009\239\042\173\210\044\064\173\220\044\050\211\082\121\119\246\098\211\102\107\226\046\007\104\041\032\206\105\006\032\254\141\002\198\155\006\233\217\177\152\075\079\063\202\188\055\034\018\081\078\141\035\023\007\042\055\241\196\222\244\106\221\196\070\179\019\113\239\011\144\056\166\004\032\190\229\002\247\154\006\201\076\079\229\031\183\158\065\048\160\063\014\034\241\198\201\072\193\201\008\085\233\123\003\142\195\253\063\059\201\198\050\159\003\060\012\100\153\006\146\232\209\018\064\124\251\019\022\106\253\255\230\202\081\028\219\191\173\133\238\136\072\052\056\169\033\194\059\170\086\168\047\063\039\211\230\082\064\000\120\215\052\144\068\135\094\249\226\087\087\220\058\221\070\122\117\106\202\197\167\013\180\208\029\017\137\154\148\000\078\118\106\149\191\125\226\137\189\233\219\182\200\070\203\087\001\218\056\020\167\148\000\196\167\000\238\212\191\209\012\078\102\122\042\015\222\118\006\129\128\078\131\138\196\059\039\047\013\170\088\240\039\224\056\220\127\249\073\100\165\087\061\105\168\068\008\247\179\072\031\034\113\072\075\000\241\233\103\192\249\166\065\254\112\213\073\012\233\211\198\066\119\068\036\234\202\019\249\189\071\046\017\012\080\035\059\131\204\180\020\222\049\095\010\104\002\044\005\230\154\006\146\200\210\012\064\252\169\007\220\102\026\100\064\247\230\092\048\182\191\133\238\136\072\172\112\114\082\033\088\245\143\245\139\135\091\091\010\248\019\238\158\000\137\035\074\000\226\207\223\112\207\224\122\150\157\153\198\253\183\156\097\163\062\184\136\196\146\128\227\038\001\085\254\118\135\123\046\029\109\227\084\064\093\224\014\211\032\018\089\090\002\136\047\199\002\191\051\013\242\155\043\071\051\164\079\107\011\221\017\145\088\227\164\005\009\239\220\095\165\226\064\224\158\010\200\074\079\181\177\020\208\021\120\011\248\218\052\144\068\134\102\000\226\071\006\112\159\105\144\206\173\027\113\225\169\154\250\023\073\092\014\129\106\204\002\128\187\020\096\161\064\080\000\184\007\189\088\198\013\037\000\241\227\070\160\169\073\128\096\032\192\223\110\028\167\130\063\034\137\046\059\013\066\085\255\123\030\112\028\238\158\056\146\148\160\241\216\221\013\184\200\052\136\068\134\050\181\248\208\006\120\012\195\223\175\137\227\006\050\097\100\047\059\061\018\145\216\229\224\158\010\216\093\181\019\001\000\181\243\178\216\190\123\047\159\044\092\101\218\122\095\224\081\096\167\105\032\241\151\094\005\227\195\093\128\209\129\221\122\005\185\220\120\241\241\150\186\035\034\177\206\201\076\133\148\234\189\051\252\106\220\209\052\170\109\180\199\024\220\077\202\127\052\013\034\254\083\002\016\251\078\004\142\049\013\114\231\245\167\144\155\157\097\161\059\034\018\023\028\008\084\227\162\032\128\140\180\020\126\123\238\113\054\090\063\019\080\137\209\024\167\004\032\182\165\000\127\054\013\114\108\191\182\140\024\212\209\066\119\068\036\174\100\164\224\164\086\237\162\160\114\035\123\183\229\216\110\045\077\091\118\128\187\209\024\019\211\244\155\019\219\046\003\090\152\004\200\076\079\229\206\235\078\177\212\029\017\137\059\213\156\005\000\184\243\162\019\109\212\006\232\008\156\097\026\068\252\163\077\128\177\043\031\120\030\200\052\009\242\235\043\070\114\076\095\149\251\021\073\086\078\040\064\120\079\041\028\168\090\093\000\128\188\172\116\014\148\133\153\054\111\185\105\243\061\128\007\128\253\166\129\196\062\205\000\196\174\219\128\090\038\001\058\182\106\168\155\254\068\004\039\183\250\179\000\063\063\169\063\205\010\011\076\155\110\000\252\220\052\136\248\067\009\064\108\106\141\225\089\090\199\113\248\211\213\099\008\085\163\046\184\136\036\038\039\035\165\218\039\002\210\082\066\252\229\162\019\109\052\127\029\080\223\070\032\177\075\163\067\108\186\019\119\003\160\103\099\135\117\165\079\231\018\075\221\017\145\120\023\200\171\254\044\192\160\142\037\156\220\175\189\105\211\217\192\045\166\065\196\062\037\000\177\103\216\193\047\207\050\211\083\185\253\242\017\150\186\035\034\009\033\051\005\082\170\255\145\255\219\115\143\039\039\179\250\201\195\143\156\007\180\053\013\034\118\105\019\096\108\009\001\047\000\117\076\130\092\125\222\177\156\048\208\056\107\023\145\068\019\008\192\238\234\237\199\203\201\072\035\024\008\240\222\156\165\070\045\003\069\192\083\038\065\196\046\205\000\196\150\137\064\059\147\000\013\234\214\224\138\009\071\091\234\142\136\036\018\039\051\005\167\026\119\004\148\187\228\196\062\020\215\203\055\109\254\120\044\020\053\019\123\148\000\196\142\092\224\102\211\032\119\092\049\138\172\012\163\170\193\034\146\168\028\192\195\137\128\212\080\144\155\078\031\098\163\007\127\068\227\078\204\208\111\068\236\248\037\096\116\230\166\103\135\098\198\028\219\197\082\119\068\036\017\057\217\041\016\116\170\253\220\201\253\218\219\184\050\184\035\112\150\105\016\177\067\009\064\108\040\000\174\052\009\016\008\056\252\241\234\147\113\156\234\255\197\022\145\100\226\224\228\084\127\022\192\113\028\126\115\246\048\027\159\049\119\000\089\166\065\196\156\018\128\216\112\061\238\018\128\103\167\015\239\073\215\182\198\217\185\136\036\001\039\059\213\189\046\184\154\186\183\108\196\168\062\198\155\249\011\129\203\077\131\136\057\189\046\070\095\033\176\004\240\124\085\095\118\102\026\159\191\124\051\245\010\140\114\008\017\073\034\225\045\123\008\111\219\091\237\231\086\126\187\153\110\151\221\205\222\253\165\038\205\111\001\138\015\254\083\162\068\051\000\209\119\011\006\131\063\192\047\207\057\070\131\191\136\084\139\147\147\230\233\021\176\073\221\154\092\120\124\047\211\230\107\160\089\128\168\211\012\064\116\053\003\190\196\160\234\095\189\130\092\230\188\114\139\118\254\139\072\181\133\055\238\038\188\115\095\181\159\219\186\115\015\157\038\222\201\198\109\187\076\154\223\138\059\011\176\217\036\136\120\167\025\128\232\186\029\195\146\191\215\093\120\156\006\127\017\241\038\199\219\103\071\094\086\058\215\158\050\200\180\245\060\224\010\211\032\226\157\018\128\232\105\015\156\106\018\160\168\065\045\038\140\236\109\169\059\034\146\108\156\212\032\164\133\060\061\123\254\113\061\105\213\200\168\104\041\184\055\005\026\087\024\018\111\148\000\068\207\029\024\254\252\111\189\236\068\082\171\121\195\151\136\200\161\028\143\179\000\161\096\128\155\207\024\106\218\124\046\110\013\020\137\002\037\000\209\209\003\048\186\103\179\125\139\006\156\052\084\069\127\068\196\140\147\145\002\030\202\003\003\012\239\217\154\110\045\026\154\118\225\010\012\239\063\017\111\148\000\068\199\239\049\220\128\121\251\229\035\008\120\056\199\043\034\242\003\142\247\089\000\128\027\078\051\190\123\036\011\205\002\068\133\018\128\200\027\000\024\237\158\233\219\165\025\067\251\180\177\212\029\017\073\118\078\086\154\167\194\064\000\067\186\052\167\079\155\034\211\046\092\010\212\053\013\034\213\163\004\032\242\110\048\013\112\251\229\035\108\244\067\068\196\021\000\039\203\251\044\192\117\167\025\159\008\200\002\174\049\013\034\213\163\004\032\178\058\099\120\029\230\136\193\029\233\217\161\216\082\119\068\068\014\050\088\006\056\170\067\009\253\219\025\127\046\093\002\052\048\013\034\085\167\004\032\178\110\196\096\237\063\024\008\112\203\165\195\045\118\071\068\196\229\132\002\144\233\189\044\201\013\227\140\247\002\164\003\215\154\006\145\170\083\002\016\057\173\129\081\038\001\198\014\235\074\203\226\122\150\186\035\034\242\067\129\108\239\179\000\125\219\022\049\168\099\137\105\023\046\000\244\033\023\033\074\000\034\231\006\012\126\222\129\128\195\047\206\054\062\115\043\034\082\185\244\016\024\212\022\185\229\140\099\076\175\011\078\007\038\154\004\144\170\083\002\016\025\197\192\105\038\001\070\029\221\153\054\205\234\091\234\142\136\072\197\076\054\003\118\105\222\128\033\157\155\155\118\225\050\032\219\052\136\028\153\018\128\200\184\022\240\086\111\019\112\028\135\107\206\055\218\059\040\034\082\037\078\118\010\038\101\074\110\058\125\136\233\044\064\062\112\174\073\000\169\026\037\000\254\171\007\156\101\018\224\196\163\058\208\174\185\054\199\138\072\004\004\028\156\044\207\239\043\116\042\041\228\248\030\173\076\123\113\021\134\023\165\201\145\041\001\240\223\213\184\235\090\158\056\142\195\053\023\028\107\177\059\034\034\135\231\024\108\006\004\247\068\128\225\044\064\035\096\172\081\039\228\136\148\000\248\043\031\184\208\036\192\177\253\218\208\169\085\035\075\221\017\017\169\130\052\179\205\128\237\139\234\049\180\139\241\094\128\107\049\044\153\046\135\167\004\192\095\087\098\184\153\229\154\243\135\089\234\138\136\072\213\185\123\001\188\251\249\073\003\076\187\208\001\208\209\039\031\041\001\240\079\006\110\101\043\207\142\238\221\138\030\237\139\236\244\070\068\164\026\156\172\084\163\105\252\190\109\139\232\217\170\177\105\055\174\054\013\032\149\083\002\224\159\051\129\090\038\001\174\213\219\191\136\068\075\192\049\170\012\008\112\249\168\126\166\189\024\002\116\053\013\034\021\083\002\224\159\075\077\030\238\223\173\057\125\058\027\087\213\018\017\241\204\116\025\096\120\207\214\180\106\084\199\180\027\087\153\006\144\138\041\001\240\199\049\184\235\087\158\093\117\142\206\253\139\072\148\165\133\032\213\251\048\225\056\014\151\141\236\107\218\139\177\128\222\134\124\160\004\192\031\151\155\060\220\166\089\125\006\247\106\105\171\047\034\034\158\153\084\006\004\056\117\096\071\234\231\231\152\132\008\226\110\168\022\203\148\000\216\215\028\056\206\036\192\207\206\024\108\122\134\086\068\196\010\039\051\197\232\048\094\090\074\136\137\039\246\049\237\198\217\064\158\105\016\249\033\037\000\246\093\137\193\207\181\118\126\014\099\135\105\207\139\136\196\136\096\000\039\221\108\047\192\121\199\246\032\047\203\115\061\052\112\143\083\079\048\234\132\252\132\018\000\187\106\096\248\135\116\226\184\129\164\167\170\002\166\136\196\014\039\203\236\051\041\039\051\141\115\143\237\097\218\141\075\080\097\032\171\148\000\216\117\001\006\133\127\050\211\083\057\239\100\227\013\051\034\034\118\101\134\220\099\129\006\046\029\209\135\244\084\239\119\012\000\173\128\065\070\157\144\031\080\002\096\079\008\195\163\127\227\135\247\160\086\013\221\130\041\034\177\198\193\201\048\026\188\169\083\035\155\083\007\118\050\237\136\209\103\172\252\144\018\000\123\070\003\077\188\062\236\056\014\151\140\063\202\094\111\068\068\044\050\061\013\000\238\044\128\225\006\231\017\064\067\227\142\008\160\004\192\038\163\163\127\199\015\104\071\139\162\186\182\250\034\034\098\087\122\008\039\100\054\100\180\106\084\135\254\237\138\077\066\132\048\188\096\077\190\167\004\192\142\246\128\081\205\203\203\207\028\108\169\043\034\034\062\049\044\013\012\112\193\241\061\141\067\000\230\211\017\162\004\192\018\163\140\180\115\235\070\244\237\210\204\086\095\068\068\124\225\100\155\143\187\039\244\104\077\131\090\185\038\033\234\225\046\185\138\033\037\000\230\050\128\211\077\002\092\118\186\222\254\069\036\014\132\002\056\105\065\179\016\193\000\231\152\031\009\212\102\064\011\148\000\152\027\011\212\244\250\112\173\026\217\140\028\210\209\098\119\068\068\124\100\097\051\224\185\195\186\147\150\098\116\170\160\063\134\247\173\136\018\000\027\046\048\121\248\172\081\189\085\248\071\068\226\134\147\025\050\046\199\083\144\155\197\200\052\191\217\166\000\000\032\000\073\068\065\084\062\109\077\187\050\209\052\064\178\083\002\096\166\037\224\185\114\143\227\056\156\053\170\183\197\238\136\136\248\044\016\192\073\055\171\009\000\112\161\249\102\192\051\208\253\000\070\148\000\152\185\016\131\092\248\232\094\173\040\105\092\219\098\119\068\068\034\032\195\124\214\178\071\203\198\116\044\041\052\009\145\013\140\051\238\072\018\083\002\224\093\042\112\166\073\128\243\198\024\157\028\020\017\137\010\199\194\113\064\128\011\143\051\158\005\056\203\070\063\146\149\018\000\239\078\002\060\191\190\215\043\200\101\088\127\227\053\048\017\145\200\011\056\086\150\001\198\012\232\064\126\078\166\073\136\094\184\119\004\136\007\074\000\188\051\218\252\119\238\201\253\072\009\153\029\167\017\017\137\026\011\179\000\025\169\041\156\057\196\248\250\115\093\019\236\145\018\000\111\074\048\184\149\042\020\012\112\246\104\109\254\019\145\248\229\100\154\207\000\000\156\055\172\187\233\253\000\019\000\189\077\121\160\004\192\155\243\049\216\252\119\252\128\246\020\214\169\097\177\059\034\034\017\022\008\064\154\121\018\080\084\055\159\126\109\139\076\066\052\000\142\054\238\072\018\082\002\080\125\065\012\055\158\156\059\198\243\201\065\017\145\152\017\176\180\025\240\140\163\187\152\134\056\219\066\055\146\142\018\128\234\059\026\168\239\245\225\226\006\005\012\238\169\061\043\034\146\000\044\037\000\035\123\183\037\039\051\205\036\196\104\064\211\170\213\164\004\160\250\198\155\060\060\097\084\111\002\001\195\050\090\034\034\177\032\232\064\186\249\242\123\102\122\042\163\251\180\051\009\145\142\091\150\093\170\065\009\064\245\100\000\163\188\062\028\008\056\140\027\222\221\098\119\068\068\162\203\177\080\020\008\172\044\003\168\038\064\053\041\001\168\158\145\024\148\158\028\216\189\005\013\235\122\190\055\072\068\036\230\056\089\041\198\119\003\000\244\106\221\132\022\013\141\042\163\246\197\045\207\046\085\164\004\160\122\140\174\253\029\063\220\248\010\076\017\145\216\018\008\064\170\157\083\120\167\029\213\201\052\196\025\054\250\145\044\148\000\084\093\062\112\140\215\135\179\050\082\025\049\072\215\254\138\072\226\177\181\012\048\126\080\103\130\001\163\097\233\108\084\019\160\202\148\000\084\221\105\184\245\255\061\025\053\164\051\089\102\187\092\069\068\098\146\147\097\167\040\080\097\173\092\006\117\042\049\009\209\016\056\202\074\103\146\128\018\128\170\051\154\090\058\125\184\241\165\023\034\034\177\041\037\136\019\178\051\156\156\062\216\120\051\224\169\054\250\145\012\148\000\084\077\017\238\165\019\158\052\170\087\147\126\093\155\217\235\141\136\072\140\009\167\219\089\006\056\161\071\107\106\100\103\152\132\024\013\216\153\146\072\112\074\000\170\230\076\012\246\185\142\059\161\135\206\254\139\072\066\179\181\012\144\158\026\098\108\255\014\038\033\010\048\184\171\037\153\040\001\168\026\163\226\063\227\078\208\238\127\017\073\108\078\070\208\244\082\159\255\177\112\026\064\069\129\170\064\009\192\145\117\197\224\190\233\030\237\139\104\094\084\199\098\119\068\068\098\145\157\170\128\000\221\090\052\164\081\109\163\202\190\090\006\168\002\037\000\071\102\148\073\142\063\081\155\255\068\036\073\088\058\014\232\056\014\163\251\026\149\006\046\064\167\001\142\072\009\192\145\121\046\253\155\018\010\114\210\208\206\054\251\034\034\018\179\156\116\123\047\221\039\245\109\111\026\066\203\000\071\160\004\224\240\218\098\080\090\114\096\247\022\228\231\101\089\236\142\136\072\012\011\217\171\010\216\165\121\003\154\214\175\101\018\226\036\180\012\112\088\074\000\014\239\036\147\135\071\013\049\222\200\034\034\018\087\108\157\006\000\024\213\167\173\201\227\090\006\056\002\037\000\135\055\218\235\131\193\064\128\225\071\025\029\101\017\017\137\063\150\234\001\000\140\214\050\128\175\148\000\084\174\008\240\252\010\063\160\123\115\010\106\102\219\235\141\136\072\028\112\210\130\238\005\065\022\116\108\090\223\244\134\064\045\003\028\134\018\128\202\141\198\160\248\207\168\033\218\252\039\034\073\202\210\113\064\128\145\189\141\151\001\006\090\234\074\194\081\002\080\057\163\233\255\017\131\052\253\047\034\201\201\230\105\000\195\227\128\160\101\128\074\041\001\168\088\029\160\143\215\135\251\118\045\161\118\126\142\197\238\136\136\196\015\155\009\064\187\162\122\180\052\091\006\024\141\198\186\010\233\135\082\177\081\024\220\041\125\146\166\255\069\036\153\133\002\056\033\123\247\159\156\212\207\104\051\096\029\160\155\165\174\036\020\037\000\021\243\060\253\031\008\056\012\031\212\209\102\095\068\068\226\079\154\189\211\000\039\155\037\000\000\039\216\232\071\162\081\002\240\083\121\192\096\175\015\247\238\084\066\189\130\092\139\221\017\017\137\067\022\151\001\090\052\172\109\122\026\064\009\064\005\148\000\252\212\113\064\170\215\135\071\171\248\143\136\136\213\125\000\000\195\186\121\046\202\010\208\005\168\111\169\043\009\067\009\192\079\013\243\250\160\227\056\140\024\172\233\127\017\017\130\142\091\026\216\146\097\221\141\018\000\007\247\229\078\014\161\004\224\135\028\224\024\175\015\119\104\217\128\194\058\070\087\088\138\136\036\014\139\101\129\123\183\110\066\126\078\166\073\136\227\109\245\037\081\040\001\248\161\078\024\076\019\013\235\103\084\176\066\068\036\161\004\210\236\037\000\193\064\128\193\157\154\153\132\024\138\193\242\110\034\082\002\240\067\158\167\255\001\142\237\111\092\176\066\068\036\113\164\133\012\234\169\254\148\225\062\128\092\160\159\165\174\036\004\037\000\063\116\172\215\007\107\213\200\166\107\219\198\054\251\034\034\018\223\130\014\164\216\043\011\060\180\107\011\066\065\163\097\075\203\000\135\080\002\240\189\028\012\170\255\029\211\183\013\065\075\023\096\136\136\036\010\199\226\189\000\053\179\051\232\209\210\232\069\075\199\001\015\161\017\235\123\067\000\207\149\043\142\237\215\198\098\087\068\068\018\132\197\125\000\096\124\026\160\021\096\180\145\032\145\040\001\248\158\231\233\255\096\032\192\224\094\173\108\246\069\068\036\033\056\177\181\015\000\116\028\240\127\148\000\124\207\243\006\192\158\029\139\201\207\203\178\217\023\017\145\196\016\112\032\100\111\025\160\085\163\058\052\173\095\203\036\132\246\001\028\164\004\192\213\026\104\226\245\225\099\117\252\079\068\164\082\078\154\189\004\000\224\152\174\045\076\030\063\010\072\183\211\147\248\166\004\192\101\116\252\239\056\029\255\019\017\169\156\229\004\224\056\179\101\128\116\160\151\165\174\196\053\037\000\046\207\235\255\141\234\213\164\077\051\149\152\022\017\169\140\099\121\035\096\159\182\069\100\152\221\054\056\200\086\095\226\153\018\000\072\003\006\120\125\088\211\255\034\034\071\016\010\128\197\099\210\105\041\033\122\181\246\188\106\011\074\000\000\037\000\000\061\128\012\175\015\015\238\173\221\255\034\034\071\226\164\217\029\110\006\182\111\106\242\120\079\192\232\098\129\068\160\004\192\224\237\063\016\112\232\219\185\196\102\095\068\068\018\147\229\101\128\129\029\140\018\128\084\160\183\165\174\196\045\037\000\006\009\064\187\230\013\168\085\035\219\102\095\068\068\018\146\147\106\055\001\232\084\082\072\094\150\209\102\254\164\095\006\072\246\004\032\132\065\022\056\160\091\115\139\093\017\017\073\092\097\203\039\001\130\129\000\125\219\022\153\132\080\002\016\237\014\068\089\087\220\059\000\060\025\208\221\232\044\170\136\072\210\112\028\112\044\094\012\004\048\176\189\209\018\108\015\012\062\255\019\065\178\039\000\158\167\255\131\129\128\214\255\069\068\170\195\242\044\192\000\179\125\000\070\051\192\137\064\009\128\071\029\091\053\036\047\199\243\225\001\017\145\228\099\121\035\096\155\198\117\168\091\211\104\031\086\082\047\003\036\115\002\016\000\250\121\125\120\064\119\173\255\139\136\084\139\229\025\000\199\113\232\223\206\104\022\064\009\064\146\234\008\212\240\250\240\128\110\090\255\023\017\169\014\039\020\128\160\197\171\001\129\001\102\245\000\186\002\185\150\186\018\119\146\057\001\240\060\253\031\010\006\232\221\201\232\015\157\136\072\114\074\177\092\016\200\124\031\128\231\153\224\120\167\004\192\131\206\173\027\147\099\118\254\084\068\036\041\057\041\118\247\001\020\215\203\167\081\109\207\147\185\000\253\109\245\037\222\036\107\002\224\096\240\155\174\245\127\017\017\143\082\237\015\059\253\219\023\155\060\222\211\086\063\226\077\178\038\000\045\128\218\094\031\214\250\191\136\136\055\182\103\000\000\122\180\108\108\242\120\055\192\238\238\196\056\145\172\009\064\015\175\015\006\002\014\061\058\020\089\236\138\136\072\018\073\013\224\056\118\055\002\246\104\217\200\228\241\028\160\181\165\174\196\149\100\077\000\186\123\125\176\085\211\122\090\255\023\017\049\097\185\034\096\155\038\117\201\201\076\051\009\145\148\203\000\074\000\170\169\135\217\090\147\136\136\088\222\007\016\112\028\186\052\107\096\018\066\009\064\146\072\193\173\001\224\073\183\118\077\044\118\069\068\036\009\165\218\095\114\055\220\007\160\004\032\073\116\000\060\215\240\237\222\190\200\094\079\068\068\146\145\015\039\001\186\155\237\003\104\011\036\221\221\238\201\152\000\120\158\254\207\206\076\163\085\211\122\054\251\034\034\146\116\252\057\009\208\200\100\115\097\016\183\042\096\082\081\002\080\013\093\218\054\038\024\072\198\031\153\136\136\069\014\214\055\002\230\231\100\082\092\047\223\036\068\210\045\003\036\227\104\230\249\008\160\054\000\138\136\216\225\248\176\012\096\120\028\208\243\216\016\175\146\045\001\200\002\090\121\125\088\027\000\069\068\044\177\060\003\000\198\251\000\052\003\144\224\186\226\094\254\224\237\225\182\074\000\068\068\172\240\033\001\232\209\194\040\001\104\008\024\157\037\140\055\201\150\000\120\158\226\105\092\063\159\250\181\243\108\246\069\068\036\105\057\150\111\005\004\104\091\084\143\172\244\084\147\016\073\181\012\144\108\009\064\055\207\015\182\043\178\216\013\017\145\036\023\012\224\238\006\180\039\020\012\208\169\164\208\036\132\231\049\034\030\037\091\002\208\197\235\131\221\219\107\250\095\068\196\026\007\240\097\022\160\067\211\250\038\143\183\183\213\143\120\144\076\009\064\006\208\212\235\195\029\205\054\151\136\136\200\143\249\144\000\180\047\050\074\000\058\216\234\071\060\072\166\004\160\013\006\087\062\182\109\110\244\135\074\068\068\126\196\241\097\035\096\251\034\163\098\109\141\129\026\150\186\018\243\146\041\001\104\231\245\193\250\181\243\168\085\035\233\170\068\138\136\248\043\100\127\008\106\213\184\014\041\065\207\137\133\131\251\178\152\020\148\000\084\229\193\230\073\117\050\068\068\036\050\124\040\006\148\150\018\162\089\131\090\038\033\146\102\031\128\018\128\170\060\216\220\104\087\169\136\136\084\036\020\176\125\016\000\128\182\077\140\150\001\148\000\036\032\207\009\064\091\037\000\034\034\214\057\142\131\019\176\159\001\180\047\086\002\080\021\201\146\000\228\097\080\225\169\109\051\037\000\034\034\190\240\101\035\160\142\002\086\069\178\036\000\237\241\056\209\020\010\006\104\081\084\215\114\119\068\068\004\240\037\001\104\103\054\003\080\147\036\041\009\156\044\009\128\231\233\255\022\197\117\073\075\181\127\119\181\136\136\128\019\178\191\004\080\175\102\014\181\243\178\076\066\036\197\044\064\178\036\000\109\189\062\168\019\000\034\034\062\242\097\006\000\160\157\089\061\000\037\000\009\196\251\006\064\173\255\139\136\248\199\135\090\000\000\237\180\015\224\136\146\037\001\048\152\001\080\002\032\034\226\155\160\063\071\001\117\018\224\200\146\033\001\168\003\212\246\250\112\027\205\000\136\136\248\199\001\039\232\067\069\192\070\117\076\030\111\141\065\233\248\120\145\012\009\064\137\215\007\179\050\211\104\088\055\105\202\066\139\136\068\069\216\135\141\128\037\245\141\170\001\166\001\009\127\003\092\050\036\000\205\188\062\088\210\168\054\142\227\195\220\148\136\136\252\143\227\189\118\127\165\114\050\211\076\079\002\120\190\061\054\094\036\067\002\224\121\006\160\105\163\002\155\253\016\017\145\138\248\180\017\176\164\208\232\051\220\243\216\017\047\148\000\028\238\193\070\158\183\014\136\136\072\085\249\176\007\000\140\151\001\148\000\036\000\207\191\137\197\013\053\003\032\034\226\055\063\138\001\001\148\020\042\001\056\028\037\000\135\123\080\051\000\034\034\190\011\251\181\004\160\025\128\195\074\244\004\032\027\247\024\160\039\077\149\000\136\136\248\206\143\099\128\000\205\026\024\205\226\122\222\064\030\047\018\061\001\240\156\193\101\164\165\080\191\118\158\205\190\136\136\072\069\028\124\217\007\080\082\047\223\228\036\087\014\006\053\100\226\129\018\128\074\052\109\084\155\128\015\247\084\139\136\072\005\124\216\007\144\153\158\074\189\154\217\038\033\018\122\025\064\009\064\101\015\106\250\095\068\036\098\252\090\006\040\169\175\163\128\149\081\002\080\137\166\141\117\002\064\068\036\098\124\171\005\160\141\128\149\241\043\001\008\000\245\128\154\062\197\175\042\131\035\128\154\001\016\017\137\024\037\000\021\169\137\059\150\250\242\195\177\029\244\120\096\010\176\019\088\011\108\002\054\000\143\002\109\044\183\085\021\158\075\057\150\168\010\160\136\072\228\248\180\004\208\180\158\081\002\016\141\147\000\109\129\255\003\190\195\029\067\215\002\059\128\215\129\227\108\054\100\235\039\158\013\188\200\247\029\076\063\228\215\010\128\179\128\185\192\175\240\229\226\199\010\057\128\231\171\252\138\204\142\143\136\136\072\117\248\180\233\186\097\129\209\105\174\072\222\007\224\000\055\226\142\149\019\128\067\051\151\012\190\127\193\158\132\059\230\026\179\145\000\164\226\014\252\163\143\240\125\065\224\014\224\001\034\147\004\228\243\195\068\164\202\028\199\209\017\064\017\145\072\010\250\051\044\020\022\228\154\060\094\023\119\140\243\155\131\059\054\254\154\035\143\203\039\003\147\129\020\211\070\109\036\000\055\003\003\170\241\253\023\018\153\036\192\243\219\127\065\205\108\210\082\067\054\251\034\034\034\135\225\215\041\128\058\053\178\073\241\126\219\160\131\155\004\248\169\124\240\191\176\026\207\012\196\157\045\048\098\250\019\207\007\174\244\240\092\036\146\000\207\009\128\222\254\069\068\034\204\193\151\017\033\224\056\212\053\171\005\224\121\044\169\002\047\131\127\185\095\096\184\209\222\052\001\056\030\240\122\225\178\223\073\128\018\000\017\145\120\226\211\044\064\097\045\163\207\244\250\182\250\241\035\038\131\063\184\251\000\140\054\005\154\254\180\059\026\062\127\033\240\079\011\253\168\136\018\000\017\145\120\226\211\062\128\006\102\251\000\252\072\000\028\224\030\188\015\254\229\140\198\096\211\129\215\232\167\122\208\121\192\253\216\159\009\240\252\155\166\004\064\068\036\242\156\128\063\051\000\245\243\099\042\001\040\127\243\191\196\066\044\163\193\202\244\167\189\193\240\249\114\126\044\007\120\254\077\171\167\004\064\068\036\242\252\058\009\080\203\040\001\176\185\007\192\116\218\255\199\190\053\121\216\052\001\152\110\248\252\161\108\047\007\104\009\064\068\036\158\248\182\007\032\038\102\000\108\077\251\031\234\067\147\135\077\127\218\083\129\213\134\049\014\101\115\057\064\009\128\136\072\028\113\060\159\214\059\188\006\102\197\128\108\036\000\054\167\253\203\173\002\062\048\009\096\154\000\236\005\174\051\140\241\099\054\150\003\028\220\250\201\158\040\001\016\017\137\002\159\246\000\020\154\237\001\048\093\002\176\061\237\095\238\090\096\159\073\000\027\063\237\167\128\187\045\196\057\212\133\184\051\001\094\021\224\177\122\083\048\016\160\118\190\149\042\139\034\034\082\029\062\237\001\168\095\043\023\199\241\028\187\054\096\082\025\238\126\236\015\254\127\005\158\049\013\098\043\221\250\057\240\160\165\088\229\046\002\126\233\241\089\207\083\054\117\106\229\016\244\041\011\021\017\145\195\240\233\179\055\053\020\164\032\055\211\235\227\001\188\087\003\188\026\119\044\179\233\065\220\034\064\198\108\253\180\195\192\197\192\125\150\226\149\187\003\104\228\225\057\079\119\000\000\052\168\091\195\235\163\034\034\098\194\167\011\129\000\106\231\025\205\236\122\121\169\108\130\091\219\223\166\135\129\137\184\099\174\049\155\233\086\024\184\012\187\051\001\233\120\219\052\177\205\107\131\077\204\238\142\022\017\017\175\124\090\002\000\168\153\147\097\242\184\151\125\000\151\000\105\038\141\254\200\131\192\005\064\153\173\128\182\231\091\202\103\002\108\038\001\199\122\120\102\017\176\197\075\099\093\218\052\246\242\152\136\136\216\224\083\014\080\051\219\040\001\240\114\063\188\151\177\171\050\015\226\142\173\086\222\252\203\249\177\224\098\123\057\160\200\195\051\101\184\155\019\171\037\020\012\048\118\088\087\015\205\137\136\136\021\062\045\003\212\048\075\000\188\028\013\043\054\105\240\016\086\167\253\015\229\215\110\183\242\229\000\027\073\128\215\233\142\223\083\205\089\128\139\079\027\072\097\029\237\001\016\017\137\026\239\187\245\015\171\102\182\231\077\128\224\045\001\176\049\085\255\048\238\009\002\107\211\254\135\242\115\187\187\173\061\001\203\061\062\183\026\056\027\216\095\149\111\238\211\185\132\091\046\059\209\099\083\034\034\098\131\193\113\189\195\050\220\003\224\037\001\240\058\118\149\251\039\150\215\252\127\204\239\243\110\054\246\004\188\105\240\236\043\192\137\192\218\195\125\211\105\199\119\231\197\191\077\036\035\045\197\160\041\017\017\049\021\246\105\035\160\225\018\128\151\169\097\147\177\235\159\184\199\007\173\079\251\031\202\164\184\065\085\149\039\001\165\084\127\071\255\110\220\010\074\038\222\002\090\227\206\006\156\028\010\006\186\100\103\165\103\213\204\201\164\119\231\166\156\055\166\031\061\059\216\090\170\017\017\017\019\142\227\248\050\234\025\110\002\244\050\003\112\015\112\005\080\221\181\135\135\241\097\195\095\069\034\145\000\192\247\203\001\033\170\087\017\233\106\224\107\011\237\111\197\173\086\120\247\230\079\255\058\198\193\121\222\066\076\017\017\177\205\167\121\233\252\200\207\000\124\131\091\042\255\111\213\120\038\034\111\254\229\034\089\242\174\124\038\224\207\085\252\222\219\129\123\109\119\194\009\059\057\182\099\138\136\136\029\097\159\170\001\070\225\020\000\192\223\113\011\218\085\101\064\255\051\017\028\252\033\178\009\000\184\255\097\087\003\035\128\249\149\124\207\028\224\056\224\022\095\058\224\132\149\000\136\136\196\040\159\246\000\070\099\019\096\185\155\128\019\128\185\149\252\250\060\220\049\241\106\034\056\248\067\228\150\000\126\236\181\131\095\029\128\174\184\151\045\172\007\102\000\095\250\217\112\000\114\035\250\019\022\017\145\170\243\169\014\128\225\049\064\211\243\225\111\028\252\106\011\116\007\234\224\142\121\179\128\047\012\099\123\022\173\004\160\220\092\042\207\138\124\017\118\156\156\200\230\088\034\034\082\101\062\077\001\228\102\166\017\012\004\056\080\230\233\084\093\030\110\141\066\211\209\099\062\149\207\126\071\092\210\093\123\231\132\181\004\032\034\018\179\124\074\000\028\199\033\039\211\115\105\254\016\213\223\205\031\243\146\046\001\008\059\218\004\040\034\018\171\156\160\127\177\211\083\140\038\189\077\246\001\196\164\228\075\000\202\048\186\019\082\068\068\252\019\246\235\054\032\032\045\213\040\001\072\184\058\241\073\151\000\056\014\070\091\065\069\068\196\063\126\149\002\006\200\072\053\170\246\154\112\047\143\073\151\000\000\233\209\238\128\136\136\084\194\241\111\151\118\106\138\209\250\066\194\213\138\079\190\004\192\081\002\032\034\018\171\194\062\206\000\164\167\024\141\225\074\000\226\094\056\172\037\000\017\145\036\148\110\182\007\032\213\086\063\098\069\242\037\000\056\154\001\016\017\137\081\062\078\000\144\102\118\010\064\051\000\009\064\009\128\136\072\204\242\113\009\192\108\006\064\009\064\002\080\002\032\034\018\171\052\003\016\049\063\254\105\004\128\211\128\113\184\053\250\235\000\094\183\077\030\192\173\117\060\019\120\026\120\022\240\084\131\209\080\049\112\022\238\101\011\069\133\003\174\169\209\170\184\046\253\186\054\231\156\147\251\080\220\160\032\010\093\138\125\123\246\237\231\233\201\159\242\194\191\063\099\206\087\171\217\186\125\055\117\242\115\232\209\161\152\051\070\244\226\184\254\109\125\061\174\019\207\062\153\187\156\127\189\056\157\255\124\186\152\181\027\182\146\150\026\162\077\073\125\078\056\170\003\231\158\212\151\154\121\009\087\080\204\138\141\091\118\240\240\011\211\153\242\193\023\044\088\182\142\253\251\075\041\172\083\131\001\221\154\115\222\152\126\116\109\219\036\218\093\140\073\225\112\152\201\239\127\193\083\147\063\097\198\220\021\108\216\188\157\026\057\153\116\108\213\144\049\199\118\229\180\227\187\155\158\127\143\040\063\043\181\027\038\000\145\218\003\016\177\113\248\208\079\240\018\224\121\160\179\199\134\142\228\051\096\044\176\204\167\248\063\230\000\151\001\191\167\146\018\142\169\041\065\174\187\240\056\174\058\231\024\002\062\093\064\017\143\062\157\183\130\011\110\122\156\037\043\215\087\250\061\003\186\055\231\193\219\207\164\097\221\154\017\236\089\108\219\177\115\047\191\252\227\243\060\249\218\039\149\126\079\173\026\217\252\245\250\083\024\061\212\175\191\102\241\233\249\055\103\241\139\063\060\199\230\173\187\042\252\117\199\113\152\048\178\023\127\188\122\012\089\025\009\183\023\203\179\085\107\055\113\193\077\143\051\253\179\037\149\126\079\139\162\186\060\120\251\153\116\107\023\039\009\084\105\025\101\223\108\247\037\244\207\031\120\149\135\223\156\225\245\241\115\128\071\237\245\166\066\037\192\036\160\147\079\241\127\048\014\151\103\021\037\192\127\015\254\211\047\245\129\241\192\011\192\102\031\219\041\119\007\240\059\014\051\109\115\160\044\204\007\159\046\098\250\236\037\012\237\211\134\044\239\117\162\019\198\035\047\078\103\194\053\143\176\097\211\142\195\126\223\202\111\054\241\212\228\025\180\109\094\072\073\227\218\017\234\093\236\090\180\226\091\070\092\122\047\083\063\094\120\216\239\219\189\103\031\047\189\051\155\117\027\182\113\116\239\214\004\131\201\184\010\247\189\189\251\074\185\254\206\023\185\241\238\087\216\179\119\255\097\191\119\206\194\053\188\050\245\115\006\116\109\065\237\124\085\244\126\235\195\249\140\186\236\062\022\173\248\246\176\223\183\113\203\078\158\120\245\099\082\083\067\244\238\228\231\071\188\037\097\008\111\223\235\075\232\247\231\044\229\211\069\171\189\062\062\005\119\000\245\075\196\199\225\032\110\018\240\142\207\141\150\203\002\250\003\015\225\239\076\207\072\224\094\170\184\154\180\242\155\077\188\240\239\207\232\222\161\040\105\223\104\119\236\220\203\121\055\061\198\093\143\190\195\129\178\170\253\214\236\222\187\159\231\223\154\069\089\089\152\190\093\074\008\036\233\146\192\083\147\103\112\202\149\015\178\118\195\214\042\063\051\123\193\106\166\126\188\144\163\123\183\038\047\059\057\079\166\174\248\122\035\163\047\187\143\215\222\171\250\133\160\155\182\236\228\169\215\103\080\084\088\139\182\205\010\125\236\093\236\058\080\086\198\029\247\189\206\149\191\123\142\221\123\014\159\052\149\043\011\135\121\239\147\175\088\180\098\061\067\122\183\038\053\198\151\004\194\219\252\073\000\166\206\089\194\140\175\060\039\000\111\001\159\090\236\206\161\162\050\014\007\113\215\025\046\141\064\163\229\234\003\011\129\121\062\182\241\244\193\118\170\108\219\206\061\060\245\218\039\164\166\134\232\213\177\105\082\173\111\151\191\189\078\155\185\184\218\207\134\195\240\225\172\037\076\255\108\041\067\251\180\038\059\137\102\081\202\223\094\111\249\251\171\236\047\061\080\237\231\191\089\191\133\167\147\116\022\229\141\105\243\056\233\103\247\179\124\205\198\106\063\187\127\255\001\094\121\247\115\150\175\217\200\208\190\109\072\009\249\120\123\076\140\249\110\243\014\078\191\250\033\158\120\181\242\101\166\195\249\114\233\090\094\158\250\057\253\187\053\167\078\012\207\162\248\145\000\252\235\223\159\242\251\103\166\086\249\005\167\002\111\003\031\091\236\210\161\162\050\014\007\113\167\201\091\068\176\097\112\055\083\060\227\083\236\174\192\045\094\030\044\207\146\023\044\091\203\208\062\109\226\106\227\140\087\094\222\094\043\178\234\155\077\076\122\235\051\186\183\043\162\097\189\196\159\069\089\254\245\119\140\186\244\062\038\191\095\245\183\215\138\148\207\162\148\150\030\160\095\215\102\009\063\139\082\122\160\140\091\239\121\141\095\254\225\249\042\191\189\086\102\222\226\175\153\250\241\066\006\247\106\069\141\156\196\159\069\249\104\246\082\134\095\124\015\115\191\250\218\040\206\166\173\059\121\122\242\012\026\213\207\167\093\243\006\150\122\103\147\099\053\001\216\190\107\047\231\223\249\060\127\125\105\154\201\224\015\048\021\248\200\082\183\126\044\042\227\112\016\248\011\145\191\228\032\007\184\211\167\216\067\129\209\038\001\022\046\091\199\203\239\126\078\255\174\205\168\083\043\215\082\183\098\139\233\219\107\069\182\239\220\195\083\147\103\036\252\044\202\148\255\184\111\175\043\190\174\254\219\107\069\194\097\152\254\217\210\132\159\069\249\110\243\014\198\253\242\159\060\253\186\231\077\088\063\177\118\195\086\158\120\245\019\154\055\169\067\203\226\122\214\226\198\146\112\056\204\253\079\127\192\121\055\062\198\214\029\187\173\196\220\095\122\128\087\167\206\137\217\089\020\091\009\192\087\107\054\048\234\214\071\153\062\127\133\141\112\239\003\211\108\004\170\064\084\198\225\032\240\091\188\031\049\240\042\021\119\147\158\031\134\003\131\077\131\108\222\186\139\167\038\207\160\126\237\026\116\104\217\208\066\183\098\199\242\053\223\049\242\210\123\153\252\254\023\214\099\151\207\162\204\095\242\013\067\251\180\038\205\236\246\173\152\082\122\160\140\155\255\254\010\087\253\113\210\017\055\172\121\081\062\139\210\173\093\019\026\213\203\183\030\063\154\166\205\092\204\240\139\239\097\222\226\111\172\199\222\187\175\148\023\223\158\205\254\210\082\250\119\107\158\080\179\040\091\183\239\230\236\235\031\229\222\167\222\167\204\236\237\181\066\243\022\127\205\059\031\125\233\206\162\228\198\200\241\084\007\194\091\205\019\128\039\222\253\140\113\191\125\146\117\155\173\157\040\248\015\240\129\173\096\063\018\149\113\056\008\092\130\251\070\030\073\223\226\223\012\192\000\044\036\000\224\102\201\147\223\159\203\242\053\027\025\210\167\117\204\101\201\094\148\191\189\174\180\244\246\090\153\175\150\127\203\075\239\124\078\191\174\205\168\155\000\179\040\027\054\109\103\220\047\031\226\153\041\126\237\001\114\109\223\185\135\167\039\207\160\044\028\166\111\151\102\113\063\139\082\254\246\122\193\077\143\179\109\231\030\095\219\250\104\246\082\166\205\116\079\244\036\194\044\202\156\133\107\024\062\241\030\102\204\093\238\107\059\235\190\219\198\227\175\126\076\243\038\117\104\213\052\054\102\081\076\018\128\061\251\074\185\225\095\111\112\219\019\111\083\122\192\106\233\153\183\129\015\109\006\060\068\084\198\225\032\048\016\104\025\225\134\167\226\022\036\240\067\079\224\024\155\001\231\045\254\154\183\062\252\146\065\061\091\082\051\047\203\102\232\136\041\061\080\198\239\255\249\006\087\254\238\089\227\181\215\170\218\188\109\023\079\190\250\009\217\153\105\116\111\095\020\145\054\253\240\225\172\037\156\056\209\159\183\215\138\148\133\195\076\155\181\132\057\011\087\051\180\079\027\210\211\226\115\022\101\251\206\061\156\251\171\199\184\231\201\247\124\121\123\173\200\234\181\155\120\250\245\079\233\216\178\033\197\013\227\183\200\215\083\147\103\112\250\085\015\177\097\147\063\231\225\127\108\223\254\082\094\122\231\115\054\111\219\201\160\158\045\009\006\162\120\060\053\236\125\009\096\217\218\141\140\186\245\081\166\204\056\252\113\092\143\166\224\030\211\243\067\084\198\225\242\087\218\147\035\220\240\173\192\124\159\098\119\003\142\179\029\244\219\141\219\120\226\181\079\040\105\084\155\214\037\213\058\096\016\117\229\111\175\143\191\250\049\225\200\124\014\255\079\233\129\050\222\254\104\065\092\206\162\148\191\189\158\127\211\099\108\219\225\239\219\107\069\022\175\092\207\164\183\062\163\103\199\166\020\214\169\017\241\246\077\124\190\112\053\195\047\186\135\143\231\068\170\238\215\247\118\237\222\199\115\111\204\036\028\135\179\040\123\246\237\231\202\223\062\199\175\239\127\221\218\222\156\234\152\057\111\037\211\102\046\102\072\159\214\228\100\069\167\106\122\024\192\067\002\048\101\198\066\078\254\245\099\172\218\176\197\122\159\014\122\013\255\142\001\066\020\198\225\032\240\037\112\034\213\060\054\103\096\038\240\115\252\171\003\208\025\119\031\128\117\251\246\151\242\242\187\049\146\037\087\081\164\223\094\043\051\111\241\215\188\058\117\046\003\187\183\160\160\102\164\247\186\084\223\182\029\187\057\247\087\255\023\209\183\215\138\108\221\177\155\103\094\255\052\174\102\081\158\154\060\131\241\191\124\136\013\155\015\095\076\202\079\225\131\179\040\159\047\088\205\049\125\227\099\022\101\201\202\245\140\184\228\062\254\061\253\203\168\246\099\245\186\205\060\253\250\012\058\068\105\022\197\033\092\173\025\128\210\003\101\220\246\196\219\092\253\207\201\236\217\087\234\099\207\120\009\255\010\001\069\101\028\014\226\014\196\239\224\158\067\244\123\126\123\061\238\244\188\159\149\000\219\227\022\002\242\205\204\121\043\121\231\163\005\028\221\187\021\121\049\122\252\232\251\157\195\255\231\251\218\107\085\109\220\178\131\167\038\207\160\105\163\130\152\158\069\041\127\123\253\196\231\181\215\170\058\116\022\229\232\222\173\073\077\137\205\089\148\221\123\247\115\197\111\158\225\142\007\166\216\094\123\245\108\201\170\245\060\255\230\044\122\118\044\166\065\012\207\162\188\246\222\092\198\092\241\000\171\215\110\138\118\087\000\216\181\103\031\207\189\049\043\058\179\040\101\085\175\004\248\205\198\109\140\189\227\113\038\077\051\059\142\091\069\047\000\115\124\138\029\149\113\184\252\147\100\051\238\127\092\063\192\175\242\090\051\129\099\129\021\062\197\047\215\022\056\201\231\054\088\187\097\043\207\076\153\073\135\022\013\105\218\040\182\214\026\055\109\221\201\153\215\060\194\003\207\124\064\089\164\231\252\143\096\223\254\003\188\244\206\231\049\091\010\055\022\222\094\043\051\111\241\215\188\246\094\108\206\162\044\094\177\158\017\151\220\203\059\255\093\016\237\174\252\196\182\029\123\120\230\245\079\201\201\076\143\185\089\148\242\186\008\087\253\241\121\246\250\251\246\090\109\229\179\040\179\023\172\098\104\159\054\100\164\071\104\022\165\138\165\128\167\205\091\206\232\219\030\229\171\213\027\034\208\041\192\221\183\230\215\210\053\184\227\240\139\184\085\250\252\122\067\250\193\056\124\232\171\196\022\220\018\189\011\113\143\233\229\224\094\162\227\245\019\250\000\176\014\119\195\223\173\184\211\254\145\184\003\160\037\112\074\004\218\097\247\158\125\060\251\198\076\246\236\221\207\192\238\045\098\098\173\113\246\130\213\140\152\120\015\179\230\175\140\118\087\014\107\246\130\213\188\243\223\005\049\083\196\101\231\174\189\092\116\203\019\252\225\159\111\198\204\219\107\069\202\103\081\138\027\022\208\038\070\102\081\094\125\111\014\099\174\248\007\107\214\069\226\175\183\055\007\014\206\162\044\093\189\129\033\189\219\196\196\044\202\215\223\110\225\228\203\239\103\210\091\179\162\221\149\195\090\178\106\003\207\191\057\139\030\029\139\105\080\215\255\089\148\112\089\024\182\239\171\252\215\195\097\254\250\210\052\046\190\251\069\182\239\246\167\100\112\037\158\196\029\031\253\180\153\008\142\195\209\031\177\236\027\001\188\018\233\070\007\118\111\193\191\126\123\054\117\106\069\175\188\230\035\047\078\231\170\063\060\207\190\253\145\223\060\228\085\173\026\217\060\252\155\009\012\233\221\058\106\125\088\188\098\061\167\095\243\016\095\046\089\027\181\062\120\113\238\073\125\249\243\181\099\163\054\152\149\030\040\227\246\123\039\115\231\163\111\071\165\125\175\090\020\213\229\201\063\157\023\213\101\168\015\062\093\196\057\055\060\202\250\141\145\217\229\111\067\090\106\136\095\095\062\146\075\198\031\229\111\067\251\015\080\182\182\226\025\184\077\219\119\113\254\093\207\243\206\103\213\047\091\110\193\241\192\027\209\104\216\047\209\079\131\237\043\002\206\136\116\163\043\191\217\200\139\111\127\022\149\181\198\029\059\247\114\225\045\079\240\151\127\189\109\090\234\178\082\126\205\110\236\222\179\143\231\222\156\073\056\076\084\118\108\063\059\101\038\099\175\124\128\111\214\155\149\066\174\140\159\255\061\179\023\172\230\253\025\095\113\116\239\086\228\070\248\066\161\085\107\055\049\234\210\251\120\241\109\255\046\071\243\235\103\183\113\203\078\158\126\061\058\179\040\007\202\202\248\237\003\083\184\236\215\079\179\099\151\063\111\175\126\253\220\202\103\081\150\172\218\224\094\040\148\226\079\169\244\240\129\048\236\248\233\012\192\167\095\173\102\196\205\255\226\243\165\081\219\208\252\047\032\054\054\006\089\146\136\009\064\099\224\172\104\052\188\109\135\091\196\037\047\039\131\110\237\138\034\210\230\130\165\107\057\113\226\061\076\155\229\095\070\060\110\080\103\254\239\234\083\153\179\108\045\107\190\179\063\080\134\195\048\109\214\098\062\253\098\005\067\251\182\038\051\221\255\251\222\247\238\043\229\170\063\078\226\214\123\236\149\066\254\177\038\117\107\242\202\173\103\211\176\160\006\211\231\175\032\236\195\126\140\175\191\221\194\211\175\127\074\251\022\013\104\218\040\050\023\010\189\057\205\189\134\118\217\234\239\124\137\031\012\004\184\249\244\033\220\114\230\080\166\126\190\132\109\187\236\111\098\221\183\255\000\047\191\243\057\027\183\236\100\080\207\086\017\217\139\082\126\028\247\137\087\063\241\237\056\110\239\214\077\120\229\182\179\217\178\099\015\243\087\174\243\165\141\249\075\190\241\117\047\138\083\026\038\188\243\135\009\192\253\175\253\151\243\238\124\142\205\150\074\033\123\244\079\096\085\052\059\096\091\034\038\000\181\128\011\163\213\248\129\178\048\255\158\254\037\095\044\250\154\099\250\182\241\181\020\238\179\083\102\114\234\047\030\100\221\119\219\124\137\159\150\018\226\183\231\028\199\109\019\142\033\063\039\147\113\131\058\179\175\244\000\159\044\244\231\239\192\178\053\223\241\252\155\179\232\222\190\216\215\011\055\053\030\230\000\000\032\000\073\068\065\084\133\214\124\187\153\049\151\063\080\173\107\104\171\107\088\183\150\188\120\203\089\020\215\203\167\111\219\034\250\182\045\226\221\217\139\217\185\167\242\181\077\175\014\221\139\050\160\187\127\165\112\015\148\149\241\251\007\223\224\138\223\250\087\076\170\032\055\139\167\174\027\207\248\193\093\040\172\149\203\153\067\186\176\228\155\239\248\106\141\063\027\189\102\205\095\201\191\167\207\247\189\020\238\172\249\043\025\113\201\189\204\089\184\198\151\248\142\227\112\241\240\222\060\252\203\177\212\206\203\102\068\239\054\020\213\173\201\187\179\151\248\178\167\101\227\150\029\060\254\202\199\212\171\157\071\199\086\118\075\165\135\075\203\096\167\251\231\107\199\238\189\092\116\247\011\252\237\149\015\125\155\221\172\134\187\113\171\216\038\140\068\076\000\082\129\043\163\221\137\069\043\190\229\149\169\115\124\185\118\179\252\034\159\155\254\246\138\111\111\175\013\107\215\224\197\155\039\048\162\119\219\255\253\127\129\128\195\160\142\037\116\108\090\200\219\159\045\098\239\126\251\187\150\221\011\133\252\187\150\249\205\105\243\025\121\233\189\044\093\229\207\128\018\012\004\184\238\212\065\252\117\226\072\050\015\057\123\222\164\078\077\198\013\234\204\156\101\223\176\242\091\127\054\203\253\247\243\101\124\052\123\041\067\124\184\080\232\187\205\059\024\127\213\067\060\246\138\127\197\164\250\180\041\226\213\219\207\165\125\241\247\211\242\105\041\033\070\247\109\071\205\236\076\062\152\187\204\151\083\045\235\190\219\198\051\083\062\245\237\090\230\071\094\156\206\153\215\060\204\166\173\187\172\199\006\200\201\076\227\193\043\199\112\249\168\126\063\168\077\210\190\184\062\199\116\109\201\251\115\150\178\197\135\055\231\210\003\101\188\254\193\023\246\047\020\218\127\000\118\237\255\223\069\062\211\230\197\204\172\251\111\128\248\217\180\081\005\137\152\000\028\000\110\136\118\039\192\061\142\247\196\043\159\080\167\086\014\157\090\055\178\018\115\245\186\205\156\252\179\007\120\101\170\095\199\081\225\184\238\173\120\249\150\179\104\090\191\086\133\191\222\188\065\001\163\250\180\101\250\252\021\172\223\098\255\184\092\249\133\066\095\044\250\218\090\041\220\072\188\189\214\206\203\226\201\235\079\231\204\033\093\043\076\092\178\210\083\057\101\064\071\002\001\135\143\230\175\240\165\018\214\074\031\174\101\046\191\134\246\139\069\102\215\208\086\166\252\237\245\161\095\140\037\175\130\234\115\142\227\208\189\101\035\250\182\043\226\221\217\075\216\225\199\044\202\222\253\060\247\230\044\171\179\040\059\118\238\229\188\155\030\227\174\071\223\241\237\237\181\067\113\125\094\187\253\028\250\180\041\170\240\215\235\213\204\225\140\193\093\088\250\205\070\223\102\081\230\045\254\154\183\167\127\201\160\094\045\169\105\099\022\101\239\001\158\125\099\038\167\254\246\073\214\110\242\103\118\211\163\095\001\177\117\086\211\080\034\038\000\251\128\235\000\127\118\168\084\083\233\129\050\166\252\103\158\149\082\184\111\076\155\199\168\203\238\099\169\079\231\094\067\193\000\215\158\058\136\187\038\142\032\227\008\131\110\205\156\076\078\031\220\133\237\187\247\050\115\145\063\211\154\238\044\138\249\181\204\145\120\123\237\219\246\224\219\107\209\225\047\083\009\004\028\250\183\043\166\099\073\033\239\204\094\236\075\229\050\091\215\050\251\113\013\237\143\229\100\166\241\208\047\198\242\179\145\125\143\088\089\179\113\157\154\156\054\168\051\115\151\173\101\133\143\179\040\054\174\101\158\251\213\026\078\184\248\030\254\059\123\169\197\222\253\208\105\071\117\226\169\235\079\167\078\141\195\175\195\071\106\022\229\201\215\102\024\095\203\188\103\223\126\110\184\243\037\110\254\215\155\081\041\133\124\024\059\128\095\071\187\019\182\037\098\002\000\048\017\136\169\043\232\230\045\254\154\127\079\255\146\193\061\091\085\059\075\046\127\123\189\210\231\183\215\167\174\063\157\051\143\174\248\237\181\034\161\096\128\161\093\090\184\107\141\159\251\179\214\184\121\235\046\158\120\245\019\106\231\231\208\217\195\044\202\244\207\220\082\200\017\121\123\205\172\122\237\244\230\013\010\024\211\191\003\159\044\092\229\203\091\142\233\044\202\246\157\123\056\239\198\199\248\251\019\254\149\066\238\208\180\062\147\111\063\151\094\173\155\084\249\153\172\244\084\198\250\060\139\178\234\027\247\066\161\078\173\026\082\212\160\250\069\190\158\154\060\131\241\087\061\196\122\159\046\242\073\079\013\113\231\069\035\184\233\244\033\085\126\161\040\159\069\233\215\174\152\169\159\047\102\199\110\251\179\040\229\215\050\123\045\149\190\106\237\038\078\190\252\001\094\253\192\254\053\229\022\124\131\187\007\032\161\036\106\002\112\022\080\215\203\131\019\134\116\101\254\202\111\125\201\146\191\253\110\027\079\077\158\065\171\166\245\104\081\084\181\238\173\251\110\027\099\175\248\007\079\077\158\225\219\219\235\128\246\077\121\237\246\115\105\219\196\091\230\222\190\184\062\199\117\111\197\251\115\151\178\121\187\063\107\141\111\252\103\030\223\172\223\202\224\222\173\008\005\143\252\199\054\028\014\115\215\255\189\195\069\055\063\225\219\069\062\053\178\051\120\236\154\211\152\056\188\183\167\123\033\242\178\210\057\237\168\078\172\223\178\131\057\203\252\057\218\228\101\022\037\018\023\249\156\123\108\119\030\187\102\028\181\061\220\174\089\062\139\210\193\199\189\040\229\023\010\101\102\164\209\163\067\081\149\146\226\221\123\247\115\249\029\207\240\155\007\166\248\246\246\218\172\176\128\087\110\059\135\099\186\182\240\244\124\227\058\053\056\101\064\039\062\095\250\053\171\214\251\115\105\206\204\121\043\249\104\118\245\102\081\094\123\111\046\163\046\189\143\229\107\252\057\089\146\018\012\112\070\175\118\204\089\179\222\107\136\101\192\131\022\187\020\019\018\053\001\024\011\020\123\121\240\230\051\134\114\241\009\189\121\215\167\227\071\123\247\149\242\194\191\063\171\082\150\060\253\179\037\140\152\120\015\011\150\250\083\160\166\252\237\245\193\159\143\033\183\026\111\175\021\169\083\035\155\051\006\119\097\249\186\205\044\088\237\249\047\217\097\125\190\112\053\111\078\155\127\196\107\153\203\175\161\245\179\020\114\199\146\066\094\187\253\028\186\181\048\219\219\017\010\006\056\190\071\043\138\235\229\243\238\231\075\124\025\056\202\103\081\010\242\179\233\220\186\241\097\191\215\189\134\246\097\054\108\246\231\237\053\035\053\133\191\078\028\201\181\167\014\034\100\120\244\174\121\131\002\078\025\208\129\079\190\090\197\055\027\253\153\069\121\247\227\133\085\186\150\121\233\170\013\140\188\244\094\222\254\200\191\082\200\039\244\108\205\164\155\038\208\168\182\089\157\145\236\140\084\078\059\170\019\001\199\255\089\148\035\093\203\092\126\077\249\047\126\255\028\123\246\250\051\187\089\152\151\205\115\023\157\068\081\065\030\207\207\244\252\251\051\023\120\194\098\183\098\066\162\038\000\039\224\222\009\080\109\253\219\021\115\092\247\086\156\118\084\039\190\088\190\150\229\235\252\185\156\227\112\215\110\254\239\026\218\027\253\187\134\054\055\051\157\071\126\121\010\151\141\056\242\218\107\085\165\166\132\024\213\183\029\245\242\115\152\058\123\137\047\027\159\142\116\045\243\156\133\107\056\225\226\191\251\250\246\234\174\189\142\167\118\158\189\051\208\237\138\234\113\098\175\054\076\251\098\057\223\109\219\105\045\110\185\242\089\148\202\246\162\068\226\026\218\242\183\215\161\093\154\091\139\153\123\112\022\197\207\189\040\071\186\150\121\242\251\115\057\249\242\007\088\229\211\069\062\161\096\128\091\206\028\202\159\046\024\078\186\165\099\197\001\199\157\069\233\220\172\001\239\124\230\207\094\148\035\093\203\028\137\107\202\251\053\111\196\075\151\140\165\085\189\090\076\091\188\154\055\231\121\222\147\049\003\183\078\127\066\137\118\002\080\126\117\239\080\220\026\254\165\184\055\021\153\026\012\116\247\242\096\167\146\066\250\183\043\038\051\045\133\083\007\118\036\035\045\133\255\204\093\230\075\150\092\209\181\155\145\184\134\182\099\073\033\147\127\125\014\061\091\029\254\109\208\171\206\037\013\024\210\185\005\083\231\044\101\171\015\055\017\086\118\045\179\123\145\207\063\125\187\200\039\035\053\133\187\039\142\228\198\241\067\072\169\194\050\068\117\021\228\102\049\110\080\039\086\124\187\153\005\171\252\153\069\169\232\066\161\072\092\067\123\098\175\054\076\186\233\076\227\183\215\138\148\239\069\041\169\095\139\119\124\154\069\169\232\090\230\239\047\242\153\228\219\219\107\131\090\185\076\186\105\002\099\250\119\240\165\194\095\179\194\002\198\014\232\200\140\175\086\251\050\139\114\232\181\204\135\094\040\052\109\230\098\134\095\124\015\243\151\248\179\244\229\056\112\229\144\030\060\112\198\241\228\028\044\044\054\229\139\037\076\095\226\057\073\124\015\120\211\066\215\058\224\142\121\199\000\173\112\111\001\244\167\098\083\021\068\043\001\024\133\155\077\221\136\091\187\127\008\238\021\190\019\129\147\113\111\042\090\098\016\191\039\048\208\203\131\205\010\107\113\092\247\086\128\059\069\222\187\117\019\122\183\241\175\136\203\161\215\110\102\101\166\113\226\197\247\250\122\013\237\057\199\116\231\241\107\199\081\144\235\239\141\147\245\107\229\114\234\192\078\204\091\177\206\215\089\148\255\124\186\152\254\093\155\113\227\095\095\230\142\251\095\247\237\034\159\230\013\010\120\249\182\115\024\098\241\237\181\034\169\041\033\070\245\241\119\022\229\187\205\238\133\066\037\141\106\179\100\213\006\078\190\252\001\086\251\244\123\116\232\219\107\154\079\165\099\203\181\045\170\199\136\094\109\152\054\111\057\223\109\245\103\022\229\237\143\022\176\108\245\119\180\041\169\207\105\191\252\039\207\191\233\223\069\062\003\218\055\229\229\091\207\166\101\067\127\043\060\230\102\250\063\139\178\100\213\122\038\189\053\139\030\029\138\121\246\141\079\185\232\230\039\216\238\195\018\043\064\126\086\006\143\159\059\146\243\250\117\250\193\113\206\231\102\046\048\217\003\048\005\248\192\160\091\039\224\142\121\183\240\253\152\055\002\184\024\247\242\186\053\192\087\006\241\061\137\244\101\064\014\240\071\224\170\035\124\095\024\184\003\184\217\099\059\151\001\127\247\242\224\049\093\091\048\233\166\009\063\249\255\215\108\216\194\132\063\061\227\219\095\016\112\019\014\063\202\197\130\187\123\250\239\151\142\098\076\255\014\190\196\175\076\089\056\204\031\158\125\143\063\060\251\158\111\235\241\126\254\220\000\198\244\239\192\223\047\029\069\086\004\074\020\031\106\198\087\171\056\251\079\255\223\222\125\199\089\085\093\011\028\255\013\067\111\210\123\007\001\193\065\186\136\138\098\001\137\093\099\215\128\045\201\083\099\018\095\098\073\162\177\037\121\026\019\099\162\070\017\020\027\010\034\032\210\005\164\119\024\134\025\135\050\076\003\166\049\189\222\059\183\157\247\199\153\081\132\025\152\123\246\062\183\174\239\231\115\063\106\228\236\179\130\195\061\235\236\178\214\060\091\202\047\131\253\191\111\189\058\183\227\227\039\239\100\204\185\122\043\197\157\077\133\163\154\095\189\181\152\047\055\219\183\155\220\206\223\187\070\049\049\060\117\199\100\158\186\099\178\109\085\029\235\243\197\198\004\030\127\251\043\091\094\118\192\254\159\185\113\253\186\051\231\254\235\233\213\254\244\013\175\183\254\247\075\214\028\176\252\114\245\008\240\095\139\215\190\132\089\067\224\108\255\049\095\003\158\004\091\038\156\235\020\200\025\128\024\224\029\224\087\013\252\181\151\001\133\152\107\047\254\234\002\220\109\225\058\090\052\107\194\131\215\140\063\237\127\111\219\170\057\247\092\049\026\151\199\203\246\003\161\221\106\247\084\230\219\235\012\046\027\049\048\224\247\142\169\089\107\156\056\188\031\107\108\154\069\177\075\109\041\228\151\103\092\067\083\093\085\206\252\208\179\211\057\220\053\121\020\073\153\185\164\217\180\190\108\151\203\070\152\111\175\131\122\248\127\140\078\085\032\102\081\236\210\177\109\075\062\125\250\110\126\118\245\216\160\180\023\031\222\183\027\055\094\052\156\205\073\233\228\219\048\139\098\167\025\019\071\240\225\003\055\208\190\101\221\141\177\094\095\179\147\130\010\203\213\024\223\196\218\172\244\227\192\223\104\216\203\246\068\160\059\176\204\194\125\044\009\212\183\090\012\230\111\224\047\253\188\238\010\224\067\192\223\197\169\166\152\025\155\223\060\094\031\191\185\229\210\058\255\093\109\041\220\184\254\221\249\102\111\138\045\199\143\116\187\253\178\011\152\255\199\251\232\217\241\156\160\198\209\183\107\123\110\189\116\004\187\015\031\035\203\166\055\090\157\122\117\058\135\005\207\254\140\027\039\090\218\075\170\077\139\102\077\184\125\146\185\023\101\083\098\186\173\111\079\058\196\196\196\240\219\091\038\241\206\175\111\165\117\128\103\076\078\053\106\096\079\166\140\025\194\186\132\035\182\236\069\209\109\244\185\061\089\242\194\253\140\026\212\051\168\113\116\108\219\146\123\174\028\077\094\113\005\251\211\066\191\069\118\235\102\077\121\231\190\105\060\113\245\133\103\220\208\252\226\210\077\084\091\223\031\242\050\230\011\169\063\122\000\075\000\127\118\110\142\001\122\001\075\009\192\076\064\032\018\128\218\055\127\127\031\254\096\086\243\115\000\235\252\188\174\018\139\229\128\029\046\055\191\185\229\210\051\110\242\026\220\171\051\055\092\052\044\164\179\228\218\183\215\151\166\079\013\202\219\107\093\218\182\108\198\221\054\055\020\210\097\234\216\033\044\126\126\006\003\123\212\093\010\057\208\106\247\162\076\028\214\151\181\251\066\119\022\165\099\219\150\204\125\230\030\030\152\058\046\040\111\175\117\233\214\161\013\119\094\062\146\239\050\243\072\203\241\247\251\059\112\106\247\230\116\104\099\095\067\034\127\052\137\141\229\218\241\231\217\218\080\072\135\193\093\059\176\232\145\159\050\105\240\153\055\052\087\185\220\252\101\249\022\171\183\049\048\167\230\253\125\227\123\006\152\108\225\126\163\009\208\076\128\221\079\134\218\135\191\074\119\190\086\248\095\128\193\141\057\003\096\105\167\219\093\151\143\162\227\089\170\245\117\104\211\146\187\039\143\226\120\065\041\073\025\065\219\196\089\167\190\093\219\179\240\185\233\092\127\209\176\096\135\114\154\218\089\148\243\250\116\101\077\124\010\046\119\232\148\251\140\109\212\136\103\239\185\138\215\127\113\253\089\075\033\007\067\040\207\162\092\116\094\095\190\126\233\065\070\244\063\253\104\102\176\181\104\214\132\219\038\141\160\113\108\172\109\109\153\173\106\211\178\025\179\159\184\157\223\220\114\169\182\227\184\058\197\245\239\206\085\163\206\101\221\062\123\078\244\168\184\107\252\112\230\253\252\102\186\183\059\123\179\181\212\252\018\102\109\218\103\245\086\185\192\043\022\174\123\013\176\090\023\121\012\001\072\002\236\076\000\172\078\251\159\170\005\214\126\243\111\007\044\205\165\093\049\114\016\231\054\160\004\104\147\198\177\092\063\097\152\173\165\112\253\053\245\164\054\180\161\108\104\239\046\220\116\209\249\182\053\020\242\087\109\027\218\123\174\024\029\050\111\175\117\009\181\089\148\147\219\208\214\213\200\039\084\196\196\196\216\222\150\217\095\067\122\117\102\241\243\051\184\100\184\165\154\101\001\211\189\067\091\238\189\210\222\182\204\254\104\214\056\150\191\220\052\153\023\110\152\212\224\227\184\091\083\179\088\020\111\121\147\125\034\240\190\133\235\094\001\084\254\080\216\190\028\096\087\002\080\251\240\183\180\014\127\010\007\230\201\001\127\093\133\197\098\064\035\006\116\247\171\062\185\221\109\055\027\162\190\054\180\161\172\067\077\067\161\252\210\010\246\165\218\115\030\184\033\234\106\067\027\202\106\103\081\070\244\239\206\154\248\224\237\069\169\175\013\109\040\011\068\091\230\134\184\243\242\145\204\255\227\125\116\239\016\082\045\075\234\021\136\134\066\013\209\171\125\091\190\252\159\091\185\097\164\127\165\144\151\238\079\097\195\097\203\009\243\070\172\021\001\122\026\181\004\000\204\229\000\219\146\000\059\018\000\149\053\255\186\028\192\090\013\230\113\192\197\086\110\216\171\115\059\174\029\127\158\095\215\212\182\221\076\203\041\228\160\077\221\250\234\211\169\109\077\035\159\122\218\208\134\178\198\177\141\152\054\110\104\080\102\081\206\214\134\054\212\013\238\213\153\027\047\026\206\214\032\204\162\156\173\013\109\040\011\068\091\230\250\052\111\218\152\191\204\152\198\139\211\167\042\117\006\013\134\147\027\010\173\141\079\177\165\045\243\153\076\059\127\032\139\030\249\041\003\058\251\223\230\250\163\109\137\036\101\089\254\094\094\130\089\008\200\095\119\098\125\009\224\100\182\237\009\208\253\019\168\099\205\255\084\115\128\181\022\174\027\132\089\113\201\111\045\154\054\225\103\087\141\241\251\186\102\053\199\143\002\153\037\127\223\134\086\161\005\103\040\136\235\223\157\169\099\135\176\126\127\026\197\001\152\069\105\211\178\025\239\253\182\097\109\104\067\089\237\044\074\065\105\101\192\102\081\026\218\134\054\148\005\162\045\243\169\006\116\239\200\226\023\238\231\218\011\253\123\185\008\053\125\186\180\227\206\201\163\072\076\183\175\045\243\201\026\055\106\196\147\215\092\196\235\119\092\077\011\139\165\144\255\249\205\078\114\074\045\039\201\031\001\241\022\174\235\007\092\098\245\166\167\176\101\079\128\206\004\064\215\154\255\201\156\152\157\253\172\212\168\236\004\220\107\229\166\085\078\023\191\189\101\146\149\075\191\207\146\047\141\171\201\146\109\104\187\089\123\159\112\126\123\173\075\215\246\109\184\231\138\209\164\231\022\113\208\166\134\066\240\067\027\218\139\252\088\230\009\101\129\154\069\105\222\180\049\175\255\210\191\054\180\161\206\238\182\204\181\126\050\126\040\095\062\055\157\062\117\244\018\008\071\173\154\055\229\246\203\046\176\181\161\016\064\231\054\045\153\251\240\077\220\059\225\124\165\217\205\103\191\218\160\114\004\240\013\192\074\005\161\195\152\203\224\186\074\096\106\223\019\160\235\079\177\238\105\255\090\079\001\171\044\094\027\067\195\138\014\157\198\233\242\240\208\180\011\149\042\191\245\238\220\142\059\046\027\201\190\212\108\050\079\232\205\146\219\181\110\193\135\191\191\131\071\174\159\024\214\111\175\117\049\103\081\134\211\166\101\051\054\038\234\159\069\185\127\202\056\062\182\216\134\054\212\197\245\239\206\053\227\134\178\062\033\085\251\044\202\015\141\124\172\181\161\013\101\118\182\101\110\018\027\203\095\238\159\198\043\015\254\068\091\035\159\080\081\219\080\104\196\000\123\102\081\038\013\238\195\146\199\110\103\184\098\049\169\220\178\074\094\091\189\093\101\136\231\001\043\189\147\075\049\095\098\167\168\220\252\020\090\151\003\116\037\000\255\002\030\213\052\086\173\119\049\203\039\090\085\130\089\114\216\210\083\252\039\227\135\042\055\046\105\213\188\041\119\092\174\055\075\030\049\192\092\123\029\167\216\134\054\148\197\196\196\112\225\208\062\076\026\049\064\219\044\074\237\219\235\211\119\094\161\220\134\054\148\117\109\215\154\123\175\028\077\154\198\089\020\093\109\104\067\153\029\109\153\123\116\108\203\023\127\186\143\091\046\137\011\187\189\057\254\056\183\103\039\110\187\084\095\091\230\152\024\248\229\101\163\153\249\179\031\026\249\168\136\063\154\203\220\157\223\089\189\188\028\115\051\159\085\091\049\031\216\099\021\198\056\213\024\160\029\026\154\019\233\072\000\238\197\218\049\189\051\153\137\217\024\072\133\129\217\096\200\210\081\192\241\067\250\048\114\096\015\197\016\244\182\221\172\093\123\213\217\134\054\148\245\238\220\142\187\039\143\086\110\203\060\168\071\039\022\063\063\131\041\099\034\239\237\181\046\077\107\118\108\171\150\194\181\163\013\109\168\211\213\150\121\082\220\000\022\253\121\006\067\123\119\209\024\093\232\210\213\150\185\109\139\102\204\158\126\029\143\078\030\171\173\015\194\154\003\233\172\250\206\114\123\240\061\192\108\197\016\150\097\038\001\254\111\044\171\223\004\032\005\243\136\162\101\170\009\064\051\204\029\146\058\207\178\204\196\092\074\208\241\194\060\001\115\202\196\111\189\187\180\211\250\192\024\212\163\019\183\094\018\199\246\131\071\201\041\042\247\235\218\150\205\155\242\246\099\055\243\204\157\087\216\210\134\054\148\181\172\041\226\098\024\006\219\146\051\253\254\161\184\229\226\056\190\120\246\062\122\069\240\219\107\125\070\013\236\201\164\184\001\172\221\119\132\114\071\181\095\215\246\234\116\014\011\158\179\175\013\109\040\235\212\182\021\119\094\062\210\210\094\148\218\070\062\111\062\118\051\109\090\054\179\041\194\208\084\219\150\121\128\197\089\148\209\253\123\176\244\209\219\025\215\079\253\197\235\100\159\108\079\034\254\168\229\098\109\203\049\215\220\085\217\145\004\140\003\222\006\044\079\087\169\062\077\174\065\239\186\255\108\244\061\252\001\250\099\198\232\183\070\141\098\152\126\181\206\089\027\056\167\085\011\238\154\060\202\175\044\249\220\158\230\219\235\228\145\131\180\198\018\078\026\197\196\048\041\110\128\095\109\153\107\223\094\095\121\232\090\154\218\220\134\054\148\245\234\220\206\108\040\228\071\091\230\073\113\003\088\244\252\012\006\219\220\134\054\148\053\179\048\139\210\161\077\075\062\121\234\110\166\079\209\247\246\026\142\206\175\105\203\188\057\041\163\193\165\210\239\159\050\142\015\031\186\145\014\205\244\247\143\248\219\138\173\228\090\063\001\240\001\176\075\083\040\203\128\206\152\015\110\029\206\001\182\000\169\086\007\080\077\000\166\003\214\182\203\159\110\038\240\011\244\022\059\104\001\204\176\114\097\113\185\195\150\242\156\181\089\242\224\094\157\217\156\148\142\163\218\093\231\175\139\137\137\225\190\171\198\048\247\153\123\232\217\041\184\141\124\066\069\191\174\237\185\229\226\243\073\204\200\061\227\198\202\193\189\058\051\239\143\247\113\235\037\113\001\140\046\116\213\206\162\052\137\141\101\199\193\163\120\125\117\159\018\104\222\180\049\127\188\235\074\254\253\232\077\180\110\017\093\111\175\245\025\053\176\039\147\047\024\196\214\228\076\138\202\235\239\036\119\249\136\129\124\249\231\233\090\150\013\035\065\199\154\089\148\188\146\010\018\207\080\042\189\083\219\086\188\253\248\045\060\113\235\036\098\203\093\160\185\115\163\203\235\229\153\133\223\170\116\132\124\005\208\089\114\115\005\122\103\002\210\177\086\163\000\104\088\139\194\051\121\023\061\103\254\117\078\251\159\172\035\080\096\245\226\205\175\063\106\107\109\243\226\010\007\239\175\220\201\138\093\135\056\112\044\015\151\219\075\143\142\109\185\244\252\254\060\120\205\248\160\119\005\011\085\134\097\176\114\247\033\062\093\183\151\093\135\142\145\095\090\073\187\086\045\024\049\160\059\183\094\018\199\029\151\143\012\153\006\072\161\038\035\175\136\247\150\239\100\109\124\010\233\121\069\196\196\196\208\191\107\123\174\030\061\152\135\166\141\167\079\023\255\139\172\068\131\106\183\135\207\215\239\099\225\230\068\246\167\231\080\090\233\164\075\187\214\140\027\220\155\123\175\028\205\148\049\131\163\110\169\164\161\246\166\100\049\107\229\014\054\039\101\144\083\084\070\211\038\177\012\235\211\149\159\140\031\202\253\083\198\209\174\117\011\048\012\140\227\165\218\159\000\241\071\115\185\252\181\079\172\094\110\000\029\176\118\002\224\076\116\214\203\121\023\133\089\120\213\159\216\087\129\223\043\142\049\027\243\055\194\174\018\112\199\177\184\017\240\063\143\222\164\125\025\064\008\033\196\143\025\046\047\228\250\183\055\170\033\102\109\218\199\255\126\177\198\234\229\025\152\203\200\118\208\085\046\255\255\048\187\014\090\162\058\191\157\160\120\253\076\224\097\236\123\248\003\236\183\122\097\252\145\044\157\113\008\033\132\168\139\077\093\065\227\143\041\117\106\181\252\236\104\000\003\120\012\107\101\238\079\166\020\163\106\002\176\002\176\122\086\198\174\105\255\083\089\254\013\218\035\009\128\016\066\216\046\198\099\207\059\160\194\238\127\080\060\098\215\000\006\230\051\208\106\018\080\129\098\045\000\213\004\160\008\120\221\194\117\129\122\248\131\194\044\197\129\204\188\160\117\090\019\066\136\168\097\195\012\128\195\229\230\144\066\253\016\236\157\001\168\165\146\004\252\003\080\042\051\171\099\139\251\139\192\006\063\126\125\032\031\254\096\086\098\178\196\229\241\146\116\134\029\172\066\008\033\212\025\110\253\051\000\009\199\079\224\169\231\196\075\003\089\126\118\248\201\074\018\176\030\248\139\234\141\117\036\000\110\204\174\123\011\206\242\235\188\192\031\008\236\195\031\032\019\115\035\160\037\091\147\051\244\069\034\132\016\226\199\124\134\045\051\000\091\083\173\087\036\196\220\000\168\052\128\159\106\147\128\063\113\246\194\062\095\000\215\099\062\123\149\232\058\228\094\001\220\134\089\116\103\041\112\114\039\146\019\192\251\192\249\192\223\008\236\195\191\150\229\076\110\099\162\149\038\080\066\008\033\026\194\112\217\179\001\112\099\138\210\241\253\045\186\226\240\131\129\249\086\031\135\089\128\040\255\164\127\087\133\249\108\157\010\220\142\249\204\085\166\187\068\218\042\126\232\222\215\021\179\019\082\169\230\123\088\177\005\243\055\205\255\011\191\203\192\237\245\070\093\009\094\033\132\008\132\024\183\087\251\091\161\203\235\101\135\090\103\199\096\036\000\181\014\000\015\212\252\253\057\064\115\032\207\142\027\217\217\022\045\143\208\120\248\131\194\127\204\010\071\053\009\169\057\058\099\017\066\008\081\171\090\255\070\235\221\025\057\084\185\148\102\200\131\153\000\156\172\020\155\030\254\096\111\002\016\074\246\097\182\117\180\100\195\126\203\165\150\133\016\066\156\129\029\075\000\155\082\142\169\092\094\006\088\238\031\028\078\162\037\001\240\002\059\173\094\188\049\073\246\001\008\033\132\118\062\003\060\250\183\133\105\088\255\183\103\099\066\136\137\150\004\000\020\166\116\182\031\200\148\122\000\066\008\161\155\203\139\238\125\225\078\183\135\221\025\074\203\182\161\050\253\111\059\073\000\026\192\081\237\102\079\074\032\079\132\008\033\068\228\051\108\088\255\223\149\145\141\083\237\133\077\018\128\008\180\013\133\115\147\235\019\100\031\128\016\066\104\101\195\250\255\183\135\050\085\046\175\070\097\185\056\220\068\083\002\080\142\066\061\128\229\059\015\106\012\069\008\033\162\157\097\203\009\128\021\137\074\047\107\027\049\207\220\071\133\104\074\000\192\108\094\100\201\254\244\028\142\158\080\042\187\044\132\016\162\150\203\103\110\002\212\040\163\176\148\228\156\002\149\033\044\063\035\194\145\036\000\126\088\185\235\144\174\056\132\016\034\186\217\240\246\191\108\255\017\213\033\036\001\136\096\251\001\203\007\068\151\237\146\101\000\033\132\208\193\142\013\128\203\147\148\018\128\012\032\170\190\228\163\045\001\000\088\109\245\194\205\137\233\148\086\058\117\198\034\132\016\081\200\000\167\222\004\160\184\202\201\246\212\044\149\033\162\234\237\031\162\051\001\176\252\031\217\237\245\178\038\062\069\103\044\066\008\017\117\012\027\214\255\087\125\151\166\218\254\087\018\128\040\240\013\010\199\001\229\052\128\016\066\168\137\169\214\127\252\111\121\162\210\244\191\011\248\086\083\040\097\035\026\019\128\050\020\142\003\126\179\247\048\110\111\084\084\137\020\066\008\123\056\149\091\217\255\072\181\199\203\186\131\025\042\067\108\068\083\139\221\112\018\141\009\000\192\074\171\023\150\084\056\088\027\175\188\211\084\008\033\162\147\161\127\003\224\234\228\052\202\157\046\149\033\162\110\250\031\162\055\001\088\164\114\241\252\013\009\186\226\016\066\136\232\226\242\104\095\255\159\183\043\089\117\136\037\058\226\008\055\209\154\000\028\002\044\063\197\151\237\056\064\089\149\156\006\016\066\008\191\057\244\190\253\151\057\170\089\147\172\212\177\117\023\016\149\211\186\209\154\000\000\204\183\122\161\195\229\102\233\246\003\058\099\017\066\136\168\096\056\244\174\255\047\138\063\132\067\173\249\143\229\103\065\184\139\230\004\224\115\020\250\080\206\219\040\203\000\066\008\225\015\195\107\128\091\233\168\222\105\230\239\086\122\025\051\128\005\154\066\009\059\209\156\000\164\001\123\173\094\188\033\033\149\236\194\050\141\225\008\033\068\132\115\184\081\120\239\058\077\086\113\057\091\083\149\090\181\111\199\172\000\024\149\162\057\001\000\152\103\245\066\159\097\176\112\115\162\206\088\132\016\034\178\105\062\254\055\127\119\050\062\067\041\161\176\252\012\136\004\209\158\000\200\050\128\016\066\004\130\097\104\223\000\248\197\030\165\233\127\031\081\060\253\015\146\000\028\003\118\088\189\056\033\053\155\125\169\217\026\195\017\066\136\008\229\244\154\073\128\038\187\051\115\248\046\091\169\245\239\102\064\169\121\064\184\139\246\004\000\020\119\128\190\191\106\167\174\056\132\016\034\098\025\014\165\066\061\167\153\189\105\159\234\016\081\061\253\015\146\000\128\153\000\088\174\237\059\127\227\126\169\009\032\132\016\103\100\064\149\190\245\255\226\042\039\139\226\015\169\012\225\006\190\212\020\078\216\146\004\192\156\002\178\092\026\184\202\233\226\179\111\149\051\081\033\132\136\092\014\175\214\234\127\159\108\079\082\061\251\191\020\200\211\020\078\216\146\004\192\244\158\202\197\179\086\236\192\208\184\182\037\132\016\145\196\168\210\055\253\111\024\048\103\171\242\006\108\165\239\252\072\033\009\128\105\025\010\155\065\014\029\207\103\243\119\025\250\162\017\066\136\136\097\212\156\255\215\227\219\067\025\028\057\081\172\050\196\049\096\181\166\112\194\154\036\000\038\015\048\071\101\128\217\043\100\051\160\016\066\156\070\243\244\255\236\205\202\075\174\179\080\216\247\021\073\036\001\248\193\108\204\115\161\150\044\217\254\029\057\069\229\026\195\017\066\136\240\167\115\250\063\187\164\156\149\073\105\042\067\248\080\124\217\139\036\146\000\252\032\029\088\099\245\098\143\215\199\236\149\150\075\010\008\033\068\228\049\208\058\253\255\238\198\120\060\062\165\094\002\043\128\163\154\194\009\123\146\000\252\216\044\149\139\103\046\223\065\133\163\090\087\044\066\008\017\214\012\135\091\219\244\127\185\211\197\007\091\100\243\159\078\146\000\252\216\087\192\009\171\023\151\084\056\152\179\122\183\198\112\132\016\034\140\085\232\155\254\159\181\041\158\082\181\023\172\092\096\185\166\112\034\130\036\000\063\230\066\113\125\232\173\037\091\112\121\100\127\137\016\034\202\121\124\224\212\083\251\191\218\227\229\157\013\150\155\183\214\154\141\089\000\072\212\144\004\224\116\255\070\225\135\036\171\176\140\249\027\164\073\144\016\034\186\153\155\255\244\076\255\207\221\145\068\110\089\165\202\016\110\224\029\045\193\068\016\073\000\078\151\133\098\127\128\215\023\110\084\109\081\041\132\016\225\173\082\207\203\182\215\103\240\159\117\202\075\171\159\000\199\053\132\019\081\036\001\168\219\171\040\164\174\041\089\005\044\219\161\212\166\082\008\033\194\087\181\007\220\122\150\066\151\036\028\038\053\095\169\240\143\001\188\161\037\152\008\035\009\064\221\246\003\235\084\006\120\125\225\070\077\161\008\033\068\120\049\052\110\254\123\099\237\046\213\033\086\001\178\046\091\007\073\000\234\247\015\149\139\119\031\062\206\154\189\041\186\098\017\066\136\240\224\211\087\250\119\101\082\042\241\071\115\085\135\249\187\142\088\034\145\036\000\245\091\129\098\214\248\226\167\223\072\147\032\033\068\084\049\042\245\156\253\247\025\006\047\047\219\162\058\076\002\240\173\114\048\017\074\018\128\051\083\090\055\218\151\154\205\087\219\146\117\197\034\132\016\033\206\128\010\061\197\208\190\220\115\144\196\044\203\101\089\106\189\130\174\163\008\017\072\018\128\051\251\020\200\086\025\224\197\079\190\193\227\085\042\093\041\132\016\225\193\233\213\178\249\207\227\243\241\202\202\109\170\195\028\007\022\040\007\019\193\036\001\056\051\023\240\031\149\001\142\100\023\240\249\122\229\238\085\066\008\017\242\140\114\061\111\255\159\108\079\034\229\068\145\234\048\255\068\010\255\156\145\036\000\103\247\038\010\229\129\001\254\246\249\058\170\221\122\042\098\009\033\068\072\242\250\192\161\254\061\231\116\123\120\117\149\242\219\127\046\240\174\114\048\017\078\018\128\179\171\000\094\083\025\224\088\126\137\244\008\016\066\068\052\243\237\095\125\185\125\230\166\120\178\138\149\091\171\255\021\168\082\014\038\194\073\002\208\048\111\097\102\148\150\253\253\139\245\084\058\245\157\141\021\066\136\144\097\024\090\026\255\148\057\170\249\215\055\059\085\135\057\006\204\084\014\038\010\196\006\059\128\048\225\174\249\076\179\058\064\165\211\133\097\024\092\126\193\064\125\081\009\033\068\008\048\042\093\080\165\190\220\254\194\210\077\108\056\124\084\117\152\039\001\229\044\034\026\200\012\064\195\189\139\153\089\090\246\230\087\091\056\146\093\160\041\028\033\132\008\001\006\080\166\254\246\127\040\175\144\153\027\227\085\135\201\068\177\163\107\052\145\004\160\225\170\049\215\149\044\115\121\188\252\225\253\021\154\194\017\066\136\016\080\229\002\013\045\208\255\176\112\061\110\245\035\211\207\099\158\222\018\013\032\009\128\127\102\003\105\042\003\172\220\125\136\213\123\014\107\010\071\008\033\130\201\192\040\083\063\250\183\116\255\017\214\028\072\087\029\038\005\179\235\159\104\032\073\000\252\227\006\094\086\029\228\201\089\203\228\088\160\016\034\252\057\212\187\254\085\123\188\060\247\213\006\029\209\252\025\144\047\086\063\072\002\224\191\143\001\165\094\191\105\057\133\188\179\084\249\156\171\016\066\004\149\142\183\255\255\172\219\165\218\238\023\204\014\174\243\148\131\137\050\146\000\248\207\003\060\174\058\200\043\243\215\147\083\164\124\214\085\008\033\130\194\112\122\160\090\237\133\059\187\180\130\127\172\222\161\035\156\223\001\082\115\221\079\146\000\088\179\006\088\174\050\064\133\163\154\063\126\032\027\002\133\016\097\074\195\219\255\147\011\214\082\229\082\062\062\184\008\248\070\057\152\040\036\009\128\117\191\070\113\183\233\130\077\251\089\186\067\105\053\065\008\033\002\175\218\003\078\181\007\247\087\251\014\243\117\066\138\106\036\046\224\041\213\065\162\149\036\000\214\029\193\172\016\168\228\137\119\150\080\090\233\212\016\142\016\066\004\072\137\218\119\086\153\163\154\167\191\092\167\035\146\127\096\238\254\023\022\072\037\064\053\059\128\007\129\086\086\007\168\112\186\040\173\116\112\205\184\161\250\162\018\066\008\187\056\221\202\155\255\126\059\127\122\162\175\027\000\000\021\215\073\068\065\084\013\091\083\143\171\070\146\007\220\129\089\163\069\088\032\051\000\106\074\128\231\084\007\249\096\245\110\190\077\072\213\016\142\016\066\216\201\192\080\124\251\223\120\248\040\115\119\038\233\008\230\041\160\076\199\064\209\074\018\000\117\239\097\030\065\177\204\048\012\030\127\123\049\085\210\044\072\008\017\194\140\042\055\184\172\159\251\119\184\220\252\234\179\085\024\234\077\003\247\098\030\201\022\010\100\009\064\157\001\028\006\166\171\012\082\090\233\196\237\245\113\197\200\065\122\162\018\066\008\173\012\040\168\002\159\245\167\247\179\095\109\096\205\129\012\013\129\112\027\160\220\053\040\218\201\012\128\030\235\128\079\085\007\121\107\201\022\118\029\082\234\055\036\132\016\246\168\112\131\219\250\081\251\173\169\199\121\119\131\114\179\031\128\247\129\173\058\006\138\118\146\000\232\243\107\224\132\202\000\030\175\143\007\255\249\005\229\085\178\167\069\008\017\066\012\003\163\204\250\218\127\153\163\154\095\124\188\002\159\250\220\127\046\240\123\213\065\132\073\150\000\244\113\096\238\074\189\089\101\144\146\074\007\185\197\229\092\119\225\048\061\081\009\033\132\034\163\172\026\028\214\207\253\063\050\119\037\219\210\178\116\132\114\063\230\250\191\208\064\018\000\189\246\003\099\129\193\042\131\036\166\231\050\168\071\071\134\247\237\166\039\042\033\132\176\200\240\026\080\088\101\174\188\091\240\217\206\239\120\117\213\118\029\161\044\003\254\164\099\032\097\138\009\118\000\017\168\047\144\004\180\086\025\164\109\203\230\108\253\215\163\244\233\210\094\079\084\066\008\097\069\097\021\070\165\181\019\074\025\133\165\092\242\202\135\148\171\159\112\042\003\134\003\202\197\003\196\015\100\015\128\126\153\192\179\170\131\148\085\057\121\232\245\005\120\125\210\223\066\008\017\036\213\030\140\074\107\083\255\030\159\143\135\063\090\166\227\225\015\230\153\127\121\248\107\038\075\000\246\216\009\092\013\244\086\025\228\120\065\041\141\099\027\113\201\240\254\122\162\018\066\008\063\024\005\149\224\181\246\018\242\183\021\091\153\191\091\075\175\147\109\192\163\088\094\132\016\245\145\025\000\123\248\128\095\162\216\044\008\224\149\121\223\178\053\057\067\057\032\033\132\240\135\081\225\178\092\244\103\115\202\049\254\177\090\203\186\127\053\240\000\210\234\215\022\146\000\216\039\017\120\089\117\016\143\215\199\244\191\127\078\078\081\185\134\144\132\016\162\001\124\006\148\056\044\093\154\093\082\206\140\057\095\227\085\040\024\116\146\231\128\131\058\006\018\167\147\037\000\123\109\006\046\007\250\169\012\082\233\116\177\227\224\081\238\154\060\138\216\070\146\179\009\033\236\101\020\059\205\150\191\126\114\123\125\220\049\115\017\135\243\138\116\132\177\017\115\038\085\166\254\109\034\009\128\189\012\096\045\048\003\104\161\050\080\118\097\025\037\149\078\166\140\081\058\097\040\132\016\103\230\244\064\177\181\162\063\079\204\255\134\165\251\143\232\136\162\004\152\082\243\087\097\019\073\000\236\087\006\164\097\214\174\086\178\039\229\056\125\186\180\099\068\255\238\234\081\009\033\196\169\012\195\220\248\103\097\250\254\243\093\201\188\188\108\179\174\072\102\032\229\126\109\039\009\064\096\036\003\231\002\035\084\007\090\027\159\194\148\209\131\233\214\161\141\122\084\066\008\113\178\082\107\021\255\018\179\078\112\207\123\139\241\232\057\182\060\027\248\155\142\129\196\153\201\130\114\224\060\010\100\168\014\226\116\121\184\251\255\230\082\084\094\165\030\145\016\066\212\114\123\049\202\253\239\067\082\092\229\228\158\089\095\225\112\251\191\103\160\014\169\192\111\117\012\036\206\078\018\128\192\041\005\238\003\172\055\211\174\113\044\191\132\251\095\155\135\219\171\060\148\016\066\000\096\020\057\192\207\102\061\046\175\151\123\103\127\069\102\097\169\142\016\220\192\093\128\028\121\010\016\089\002\008\172\163\064\099\224\050\213\129\050\242\138\201\041\042\231\218\241\231\169\071\037\132\136\110\229\213\080\225\095\217\018\195\128\199\230\174\098\121\162\150\077\127\096\086\080\157\167\107\048\113\118\146\000\004\222\038\204\163\129\125\085\007\218\159\150\067\211\198\177\076\028\214\079\117\040\033\068\180\114\123\205\141\127\126\122\117\213\054\254\187\126\143\174\040\190\001\254\007\057\242\023\080\146\000\004\158\015\088\001\220\009\180\085\029\108\099\098\058\003\187\119\100\120\063\233\028\040\132\240\147\001\070\126\037\120\253\123\238\046\220\123\144\223\047\088\171\043\138\163\192\084\192\255\044\068\040\145\061\000\193\145\135\121\044\208\255\029\055\167\048\012\131\199\222\090\196\142\131\071\213\163\018\066\068\151\050\167\223\229\126\183\165\101\241\203\079\086\248\187\093\160\062\078\224\086\160\064\203\104\194\047\050\003\016\060\199\129\066\224\090\213\129\060\094\031\203\118\028\224\250\009\195\232\208\166\165\122\100\066\136\200\087\237\193\040\242\239\052\081\122\065\009\055\189\181\064\087\135\063\048\043\253\045\211\053\152\240\143\036\000\193\181\027\232\015\140\084\029\200\225\114\179\110\223\017\126\122\233\008\090\054\107\162\030\153\016\034\114\249\012\140\252\042\191\010\254\228\151\087\113\221\155\243\200\042\209\182\073\255\093\224\037\093\131\009\255\197\004\059\000\065\115\204\141\129\099\117\012\022\215\175\027\203\094\126\144\118\173\149\042\015\011\033\034\089\081\149\217\237\175\129\202\028\213\092\255\230\124\246\029\203\211\021\193\014\204\211\080\202\203\160\194\058\217\003\016\124\090\215\192\018\051\114\249\233\075\031\083\165\111\138\078\008\017\065\140\042\183\095\015\127\135\203\205\029\051\023\233\124\248\159\000\126\138\060\252\131\078\150\000\066\067\041\144\000\220\141\134\164\044\171\176\148\125\105\217\220\124\113\156\116\015\020\066\252\192\227\131\019\013\223\108\095\237\241\114\231\123\139\216\148\114\076\091\004\192\141\192\126\093\003\010\235\036\001\008\029\169\152\167\003\174\211\049\088\090\078\017\201\153\121\220\056\241\124\026\053\146\149\030\033\162\158\001\070\126\005\120\027\086\175\223\235\051\120\232\163\101\172\076\074\213\025\197\227\192\124\157\003\010\235\036\001\008\045\123\128\246\192\004\029\131\029\206\042\224\104\126\009\215\094\120\030\049\049\146\004\008\017\213\138\171\192\209\176\122\253\134\001\191\158\183\154\121\187\146\117\070\240\042\240\087\157\003\010\053\146\000\132\158\213\192\005\192\080\029\131\037\101\228\082\082\233\228\234\209\131\117\012\039\132\008\071\149\046\140\082\103\131\126\169\097\192\239\022\172\225\131\045\090\103\233\191\064\042\253\133\028\073\000\066\143\001\044\001\174\004\122\233\024\112\247\225\227\156\040\169\096\202\152\193\050\019\032\068\180\113\251\204\082\191\013\120\244\026\006\060\189\112\029\051\055\198\235\140\096\023\112\019\032\059\147\067\140\036\000\161\201\003\124\005\220\002\116\208\049\096\252\145\044\114\139\203\153\058\118\136\036\001\066\068\011\159\081\083\234\247\236\235\254\181\111\254\154\031\254\105\152\047\051\037\058\007\021\122\072\002\016\186\170\128\053\152\039\003\180\028\234\223\151\154\077\106\078\017\215\142\063\079\054\006\010\017\005\140\194\042\168\062\251\186\191\215\103\240\232\220\149\124\184\045\081\231\237\011\049\031\254\082\167\060\068\073\002\016\218\010\128\109\152\073\064\099\029\003\038\103\230\145\146\085\192\181\019\206\147\035\130\066\068\048\163\216\001\149\103\159\117\247\250\012\254\231\211\021\124\174\119\195\159\011\243\184\223\110\157\131\010\189\036\001\008\125\153\152\071\004\111\070\083\229\198\003\199\078\112\240\216\009\174\155\048\076\146\000\033\034\081\165\011\074\206\190\233\207\229\245\050\227\131\037\044\138\063\164\243\238\094\204\151\150\229\058\007\021\250\073\002\016\030\146\128\108\224\122\052\037\001\135\142\231\147\144\150\195\013\019\134\211\056\086\146\000\033\034\070\181\007\163\224\236\077\126\028\110\015\247\205\090\194\010\189\231\252\125\192\131\192\103\058\007\021\246\144\004\032\124\236\005\138\128\105\186\006\076\205\046\100\253\254\084\174\187\112\152\052\016\018\034\018\120\125\024\039\042\207\218\228\167\184\202\201\237\239\046\100\253\225\076\221\017\252\047\240\142\238\065\133\061\036\001\008\047\059\049\167\215\174\208\053\096\118\097\025\095\111\079\102\202\152\193\180\151\086\194\066\132\047\195\128\188\074\179\220\239\025\100\022\150\234\110\236\083\235\025\224\053\221\131\010\251\072\002\016\126\054\002\205\128\075\117\013\088\092\225\096\209\214\036\038\197\013\160\091\135\054\186\134\021\066\004\140\097\158\245\175\246\158\241\087\125\151\157\207\013\111\206\039\163\176\084\119\000\047\002\047\235\030\084\216\075\018\128\240\180\022\104\003\076\212\053\096\165\211\197\188\141\009\140\232\223\157\129\061\058\234\026\086\008\097\059\003\163\200\001\085\238\051\254\170\111\015\102\114\203\127\023\080\088\233\208\029\192\191\129\167\116\015\042\236\039\009\064\248\250\006\232\001\140\209\053\160\219\227\101\225\150\068\186\180\111\205\168\129\061\117\013\043\132\176\145\081\226\132\242\051\031\247\251\100\123\018\015\126\184\020\135\187\097\189\000\252\240\001\240\136\238\065\069\096\072\002\016\222\150\003\253\049\123\007\104\225\051\012\086\237\062\012\192\037\195\251\073\213\064\033\066\152\081\230\132\210\234\122\255\189\207\048\120\121\217\022\254\180\120\061\062\067\123\025\254\057\192\067\072\125\255\176\037\009\064\120\051\128\197\152\029\004\047\212\057\240\230\164\116\246\165\102\051\117\236\016\154\053\209\082\131\072\008\161\083\165\011\138\235\063\235\095\081\237\226\193\057\203\152\179\085\107\083\159\090\239\000\191\192\060\246\039\194\148\036\000\145\097\021\208\026\141\123\002\000\142\100\023\242\245\246\100\038\095\048\144\142\109\091\233\028\090\008\161\194\081\123\214\191\238\151\239\180\252\018\110\124\235\011\182\164\030\183\227\238\175\002\191\169\247\230\034\108\072\002\016\057\086\003\078\224\042\157\131\022\149\087\241\217\250\125\012\235\211\149\115\123\118\210\057\180\016\194\010\167\251\140\015\255\053\007\210\185\249\237\005\028\047\046\183\227\238\175\000\079\219\049\176\008\060\073\000\034\203\022\204\038\066\087\161\169\098\032\128\203\237\101\209\150\036\154\053\137\101\194\208\062\178\047\064\136\096\113\214\188\249\215\177\158\111\024\240\198\218\157\060\246\217\042\059\054\251\025\192\239\128\151\116\015\044\130\071\018\128\200\179\021\200\199\172\024\168\237\073\109\024\006\235\019\082\057\146\093\200\148\049\131\105\210\088\126\116\132\008\168\106\143\121\214\191\142\042\127\085\046\055\063\255\120\057\255\221\176\183\174\220\064\149\015\115\189\255\045\237\035\139\160\146\111\241\200\180\011\056\130\217\141\075\107\161\255\228\163\121\124\189\061\153\137\195\250\209\165\093\107\157\067\011\033\234\083\237\049\075\252\214\241\116\063\152\091\200\173\255\093\192\198\148\099\118\220\217\139\089\219\255\003\059\006\023\193\037\009\064\228\074\004\018\128\027\128\166\058\007\046\044\171\098\238\186\120\058\159\211\154\145\003\123\232\028\090\008\113\010\195\233\129\252\138\058\151\252\103\111\222\199\125\179\151\144\083\090\097\199\173\043\128\091\129\005\118\012\046\130\079\022\115\035\223\005\192\082\160\151\029\131\095\063\097\024\111\061\118\051\237\090\183\176\099\120\033\162\154\225\116\067\065\213\105\211\254\229\078\023\143\127\190\154\133\123\015\218\117\235\028\204\238\163\123\236\186\129\008\062\073\000\162\067\079\204\036\096\164\029\131\247\234\220\142\247\159\184\141\009\231\245\181\099\120\033\162\083\149\027\163\176\242\180\055\255\061\153\057\060\048\103\169\029\245\252\107\037\001\215\002\071\237\186\129\008\013\178\004\016\029\202\129\185\152\009\192\185\186\007\047\171\114\242\217\250\125\248\012\131\139\165\122\160\016\234\042\092\024\069\085\063\122\248\027\006\188\179\097\047\015\124\184\148\162\202\250\011\000\041\090\003\092\003\156\176\235\006\034\116\072\002\016\061\092\192\060\160\043\048\086\247\224\062\195\096\115\082\058\235\247\167\049\113\088\063\058\072\107\097\033\044\049\202\156\167\085\248\203\044\044\229\222\217\075\120\127\203\062\059\074\250\214\122\031\184\011\243\040\177\136\002\146\000\068\023\031\230\082\064\009\048\005\027\150\128\142\023\148\242\209\154\061\052\142\109\196\133\082\051\064\008\063\024\024\037\213\080\250\195\195\223\048\224\195\109\251\185\123\214\098\142\156\040\182\239\198\102\059\223\039\144\210\190\081\069\190\157\163\215\221\192\044\192\182\221\123\147\226\006\240\214\099\055\211\183\107\123\187\110\033\068\132\168\105\233\091\241\067\087\191\244\130\018\030\253\116\165\093\229\124\107\085\002\015\000\243\237\188\137\008\077\050\003\016\189\018\049\103\003\166\096\054\019\210\046\243\068\049\115\190\217\045\179\001\066\156\137\207\128\252\042\168\114\003\063\188\245\223\051\107\049\169\249\037\118\222\249\008\048\021\088\103\231\077\068\232\146\111\100\209\001\248\020\115\227\143\109\038\197\013\224\205\199\110\162\095\215\014\118\222\070\136\240\226\241\098\228\087\130\219\156\121\079\047\040\225\177\185\171\216\124\196\150\162\062\039\091\010\220\135\185\028\040\162\148\204\000\008\007\230\009\001\007\112\005\054\037\133\153\039\138\153\179\122\055\030\175\143\113\131\123\211\056\086\107\129\066\033\194\079\109\117\063\175\129\195\237\225\181\213\219\121\232\163\101\164\021\216\250\076\054\048\187\249\061\140\249\103\094\068\049\153\001\016\039\187\022\248\024\155\150\004\106\245\239\214\129\087\031\186\150\169\099\135\216\121\027\033\066\087\069\053\070\145\019\048\088\127\040\147\223\047\088\203\225\188\034\187\239\090\006\076\007\022\219\125\035\017\030\036\001\016\167\026\004\044\004\226\236\190\209\053\099\135\240\218\207\175\163\079\023\217\036\040\162\132\001\070\137\003\202\171\201\046\041\231\133\175\055\241\249\174\228\064\220\057\001\184\005\072\011\196\205\068\120\144\037\000\113\170\034\224\035\160\015\048\194\206\027\029\201\046\228\131\213\187\001\024\059\184\151\044\011\136\200\230\051\048\010\170\112\150\086\241\143\111\118\112\255\007\095\179\239\088\094\032\238\060\007\179\166\191\020\247\017\063\034\051\000\226\076\238\006\222\006\206\177\251\070\003\123\116\228\249\251\166\112\195\132\097\114\090\064\068\030\167\007\095\065\021\139\247\028\224\133\175\055\145\110\239\058\127\173\098\224\151\200\017\063\081\015\249\166\021\103\211\007\115\095\192\164\064\220\108\204\185\189\120\113\250\084\046\061\191\127\032\110\039\132\205\012\040\119\177\099\111\026\207\126\181\158\237\105\089\129\186\241\054\224\094\100\202\095\156\129\036\000\162\033\026\001\191\194\220\061\172\181\181\112\125\038\095\048\144\151\239\159\070\092\191\110\129\184\157\016\250\025\006\007\147\142\241\215\133\027\088\028\127\040\080\119\245\000\127\001\094\002\188\129\186\169\008\079\146\000\008\127\140\195\172\025\160\189\161\080\093\026\197\196\112\227\196\225\188\052\125\170\108\020\020\097\037\043\187\136\087\230\174\229\227\173\251\241\250\108\171\221\127\170\116\204\183\254\173\129\186\161\008\111\146\000\008\127\181\001\254\013\204\008\212\013\091\052\109\194\195\063\185\144\199\111\186\132\046\237\090\007\234\182\066\248\045\175\184\156\055\230\173\103\214\218\061\056\221\158\064\222\122\054\240\027\160\034\144\055\021\225\077\018\000\097\213\205\192\091\064\247\064\221\176\069\211\038\252\236\234\049\252\250\230\075\233\213\201\246\125\137\066\052\216\241\252\018\254\245\229\070\062\090\187\055\208\015\254\044\224\017\096\073\032\111\042\034\131\036\000\066\197\057\152\093\196\030\195\220\039\016\016\077\098\099\185\245\210\056\158\188\253\114\006\245\232\020\168\219\010\113\154\204\188\098\222\250\122\043\115\086\237\010\244\131\223\000\062\193\124\235\183\189\130\144\136\076\146\000\008\029\046\001\222\003\134\006\242\166\181\123\004\254\112\215\149\012\233\213\057\144\183\022\081\238\192\209\019\188\190\112\035\011\054\237\199\227\013\120\007\221\035\192\047\144\038\062\066\145\036\000\066\151\022\192\115\192\255\002\077\002\121\227\070\049\049\076\027\063\148\095\092\059\129\203\226\006\072\029\001\097\011\195\048\088\159\144\202\059\203\182\179\106\247\033\124\070\192\054\247\213\114\003\175\096\238\242\119\006\250\230\034\242\200\055\165\208\109\004\230\108\192\248\096\220\124\080\143\078\060\060\237\066\166\095\061\134\150\205\003\114\098\081\068\056\167\203\195\162\045\137\188\177\104\051\201\071\003\082\185\175\046\241\192\067\192\222\096\005\032\034\143\036\000\194\014\177\192\227\192\159\009\064\021\193\186\156\211\170\057\063\187\106\044\015\255\100\188\180\032\022\150\164\231\022\049\115\249\118\062\094\179\151\178\170\160\189\112\151\000\207\003\111\034\231\250\133\102\146\000\008\059\117\005\094\006\030\032\128\155\004\079\214\040\038\134\107\198\013\225\193\107\198\115\197\200\065\196\054\146\126\003\162\126\094\159\143\181\241\071\152\189\114\103\176\166\249\191\015\005\152\005\060\011\228\007\043\008\017\217\036\001\016\129\048\010\248\023\001\042\039\092\159\110\237\219\112\211\197\231\115\239\149\163\025\209\063\096\167\023\069\024\056\116\060\159\133\155\019\249\100\237\094\142\229\007\164\078\255\153\172\199\220\221\159\016\228\056\068\132\147\004\064\004\210\245\192\027\064\208\011\253\015\237\221\133\187\038\143\228\190\171\198\208\169\109\171\096\135\035\130\160\180\210\201\194\045\137\124\246\237\062\182\031\200\012\118\056\000\199\128\063\097\118\227\020\194\118\146\000\136\064\107\129\121\082\224\105\032\232\079\222\102\077\026\051\109\220\016\238\184\108\036\087\142\058\151\230\077\027\007\059\036\097\035\135\203\205\218\248\035\124\190\062\158\149\187\014\225\242\132\196\178\122\005\240\087\224\117\100\119\191\008\032\073\000\068\176\244\004\094\000\166\003\033\241\212\109\213\188\041\083\198\012\230\134\139\134\051\117\204\096\090\183\104\022\236\144\132\006\229\085\213\172\218\115\136\037\219\190\099\245\222\020\170\156\174\096\135\084\203\013\204\193\220\044\155\019\220\080\068\052\146\004\064\004\091\063\224\025\224\065\204\211\003\033\161\089\147\198\076\028\214\151\107\198\014\229\214\075\227\164\007\065\152\041\174\112\176\114\215\065\022\109\073\226\219\132\084\170\003\091\165\239\108\124\192\151\192\031\129\148\032\199\034\162\152\036\000\034\084\012\195\060\238\244\083\066\236\231\178\113\108\035\046\025\222\159\043\071\013\098\242\200\065\196\245\235\038\197\134\066\140\207\048\072\076\207\229\219\132\035\172\217\155\194\150\239\050\240\250\002\094\161\239\108\124\192\060\204\153\175\128\245\007\022\162\062\242\045\038\066\205\112\204\041\209\144\075\004\106\117\108\219\146\073\113\003\184\252\130\129\092\053\234\092\122\119\110\023\236\144\162\082\094\113\005\091\147\051\088\159\144\202\202\221\007\201\041\042\015\118\072\245\049\128\101\152\149\050\227\131\028\139\016\223\011\201\047\088\033\128\113\152\141\134\174\009\118\032\103\051\184\087\103\038\095\048\144\073\113\003\024\055\164\055\221\218\183\009\118\072\017\041\167\168\156\093\135\142\177\049\041\141\111\247\029\033\037\171\032\216\033\157\141\060\248\069\072\147\004\064\132\186\011\048\079\013\220\073\128\123\012\088\213\173\125\027\070\014\236\193\069\195\250\050\225\188\190\140\026\216\083\078\023\248\201\227\245\145\146\085\192\246\131\153\108\075\206\100\095\106\054\007\143\157\008\118\088\013\229\006\022\003\127\007\118\005\057\022\033\234\037\009\128\008\023\125\048\203\011\063\012\180\013\114\044\126\105\214\164\049\023\012\232\193\184\033\189\024\209\191\059\195\250\116\101\112\239\206\180\104\026\022\249\140\237\028\213\110\014\029\207\231\192\209\060\018\210\114\216\117\248\024\251\211\114\066\109\227\094\067\148\002\051\049\107\093\100\005\057\022\033\206\074\018\000\017\110\218\096\150\022\126\002\051\041\008\091\221\218\183\225\188\062\093\024\210\187\011\163\006\246\224\188\062\093\025\018\193\137\129\219\235\229\072\086\033\007\143\157\248\254\115\224\232\009\082\178\010\066\113\195\158\063\114\048\031\252\255\194\172\221\047\068\088\144\004\064\132\171\038\192\077\192\239\008\082\231\065\187\180\107\221\130\126\093\219\211\191\091\007\250\117\237\064\191\110\237\233\214\190\013\221\059\180\101\080\143\142\033\091\159\192\229\241\146\093\088\074\122\110\049\185\069\101\228\022\151\147\145\091\076\070\094\017\233\185\197\028\047\040\193\227\013\235\007\253\169\018\128\127\002\159\097\078\251\011\017\086\036\001\016\145\224\018\204\086\169\183\001\045\131\028\139\237\186\182\111\077\199\054\173\232\208\166\037\237\219\180\160\125\235\022\180\111\211\146\142\109\091\210\190\117\139\239\255\247\214\205\205\068\161\117\139\166\052\142\109\068\012\049\156\211\170\057\000\077\027\199\126\223\046\185\202\233\250\190\034\094\105\165\019\003\003\143\215\071\133\195\044\152\083\225\172\166\184\220\065\081\121\021\197\021\014\010\203\170\040\174\249\251\162\242\042\138\203\029\020\150\087\146\087\092\017\132\223\141\128\171\004\230\099\054\234\217\026\228\088\132\016\066\212\104\011\252\028\216\131\185\003\091\062\242\209\245\249\014\120\010\144\222\210\066\008\017\226\198\096\110\198\042\034\248\015\015\249\132\231\167\020\120\023\243\103\073\008\033\068\152\105\141\185\060\176\009\179\199\122\176\031\042\242\009\237\143\023\179\029\239\012\162\096\057\073\068\055\217\003\032\162\073\079\204\010\131\183\001\019\145\159\127\241\131\061\192\199\192\023\064\118\144\099\017\034\032\228\011\080\068\171\222\192\045\072\050\016\205\146\049\031\248\031\003\169\065\142\069\136\128\147\047\061\033\096\016\112\059\102\050\048\050\200\177\008\251\024\152\037\121\231\215\124\210\131\027\142\016\193\037\009\128\016\063\214\005\184\012\184\030\184\014\104\031\220\112\132\162\010\204\053\253\175\129\229\192\241\160\070\035\068\008\145\004\064\136\250\197\098\206\008\212\038\003\163\145\063\051\225\032\025\243\129\191\006\216\128\020\233\017\162\078\242\101\038\068\195\117\003\166\001\087\098\022\031\234\027\220\112\068\141\116\096\051\230\003\127\021\144\023\220\112\132\008\015\146\000\008\097\093\119\096\044\112\049\102\066\048\014\104\026\212\136\034\159\023\056\132\249\192\223\002\108\004\050\130\025\144\016\225\074\018\000\033\244\105\003\076\192\076\008\046\198\076\014\218\005\053\162\240\087\140\217\082\119\075\205\103\007\230\186\190\016\066\145\036\000\066\216\171\007\048\012\024\142\089\081\110\024\112\062\016\154\029\125\130\199\003\028\197\092\191\223\131\089\122\055\185\230\099\004\049\046\033\034\150\036\000\066\004\094\051\204\068\032\174\230\051\020\232\095\243\137\244\234\115\149\152\107\246\233\192\065\032\177\230\147\012\184\130\024\151\016\081\071\018\000\033\066\075\023\160\031\102\050\112\234\095\123\003\045\130\020\087\067\085\001\199\048\215\229\211\235\248\107\126\144\226\018\066\156\066\018\000\033\194\075\075\160\099\205\167\051\208\233\164\127\174\253\116\194\060\194\088\187\255\160\057\063\036\014\231\000\141\128\038\152\125\018\192\092\083\119\003\062\204\006\056\000\014\192\089\243\247\037\152\083\244\133\117\124\242\129\130\147\254\185\074\227\255\087\033\132\141\254\031\138\115\009\226\188\133\111\140\000\000\000\000\073\069\078\068\174\066\096\130"},
            }) do
                local saved=pcall(writefile,item.file,item.bytes)
                local loaded,image=false,nil
                if saved then loaded,image=pcall(asset,item.file) end
                if loaded and type(image)=='string' and image~='' then
                    local icon=D.make('ImageLabel',{Name='ScopeIcon',Image=image,BackgroundTransparency=1,Position=UDim2.new(0,7,0.5,-11),Size=UDim2.fromOffset(22,22),ScaleType=Enum.ScaleType.Fit,Active=false,ZIndex=item.button.ZIndex+4},item.button)
                    if item.crop then
                        icon.ImageRectOffset=Vector2.new(72,72)
                        icon.ImageRectSize=Vector2.new(368,368)
                    end
                    local caption=item.button:FindFirstChild('RaisedCaption')
                    if caption then
                        caption.Position=UDim2.fromOffset(32,0)
                        caption.Size=UDim2.new(1,-38,1,0)
                    end
                end
            end
        end
    end
    do
    -- Settings and artwork are independent of the report worker/network lock.
    local uiAssetUris={}
    local uiAssetTargets={}
    local uiAssetsLoading=false
    loadUiAsset=function(target,key)
        if uiAssetUris[key] then target.Image=uiAssetUris[key];return end
        uiAssetTargets[#uiAssetTargets+1]={object=target,key=key}
        if uiAssetsLoading then return end
        uiAssetsLoading=true
        task.spawn(function()
            local asset=getcustomasset or getsynasset
            if type(asset)~='function' or type(writefile)~='function' or type(D.decodeAsset)~='function' then return end
            local missing={}
            for _,name in ipairs({'gear','discord'}) do
                local filename='s2r_beta_settings_v1_'..name..'.png'
                local exists=false
                if type(isfile)=='function' then pcall(function() exists=isfile(filename) end) end
                if exists then
                    local ok,uri=pcall(asset,filename)
                    if ok then uiAssetUris[name]=uri end
                end
                if not uiAssetUris[name] then missing[#missing+1]=name end
            end
            if #missing>0 then
                local ok,data=pcall(function() return Http:JSONDecode(game:HttpGet('https://raw.githubusercontent.com/syss1211/Tenshi-script/ebde34bfef44bce389f0a6a276455f8019f34051/assets/nyx-settings-art-v1.json')) end)
                if ok and type(data)=='table' then
                    for _,name in ipairs(missing) do
                        local encoded=data[name]
                        if type(encoded)=='string' then
                            pcall(function()
                                local bytes=D.decodeAsset(encoded)
                                if bytes:sub(1,8)~=string.char(137)..'PNG'..string.char(13,10,26,10) then return end
                                local filename='s2r_beta_settings_v1_'..name..'.png'
                                writefile(filename,bytes);uiAssetUris[name]=asset(filename)
                            end)
                        end
                    end
                else warn('S2R UI artwork: unable to load settings icons') end
            end
            for _,item in ipairs(uiAssetTargets) do
                if item.object.Parent and uiAssetUris[item.key] then item.object.Image=uiAssetUris[item.key] end
            end
            uiAssetTargets={};uiAssetsLoading=false
        end)
    end
    themeModal=function(box)
        box.BackgroundColor3=Color3.fromRGB(22,12,40);box.BackgroundTransparency=0.03
        D.make('UIGradient',{Color=ColorSequence.new(Color3.new(1,1,1),Color3.fromRGB(185,165,225)),Rotation=90},box)
        D.make('UIStroke',{Color=Color3.fromRGB(124,58,237),Thickness=2,ApplyStrokeMode=Enum.ApplyStrokeMode.Border},box)
        if mutationSprites.studs_v05 then
            D.make('ImageLabel',{Name='ModalStuds',Image=mutationSprites.studs_v05.image,Size=UDim2.fromScale(1,1),BackgroundTransparency=1,ScaleType=Enum.ScaleType.Tile,TileSize=UDim2.fromOffset(256,256),ImageColor3=Color3.fromRGB(140,100,220),ImageTransparency=0.7,Active=false,ZIndex=box.ZIndex},box)
        end
    end
    heading.Text='S2R EGG FINDER'
    heading.AnchorPoint=Vector2.new(0.5,0)
    heading.Position=UDim2.new(0.5,-10,0,2);heading.Size=UDim2.new(1,-112,0,24)
    heading.TextXAlignment=Enum.TextXAlignment.Center
    heading.Font=Enum.Font.Arcade;heading.TextTransparency=0
    discordSubtitle.AnchorPoint=Vector2.new(0.5,0)
    discordSubtitle.Position=UDim2.new(0.5,0,0,27);discordSubtitle.Size=UDim2.new(1,-112,0,14)
    discordSubtitle.TextXAlignment=Enum.TextXAlignment.Center
    local settingsButton=D.make('TextButton',{Name='OpenSettings',Text='⚙',TextSize=30,Font=Enum.Font.GothamBold,Position=UDim2.fromOffset(6,3),Size=UDim2.fromOffset(40,40),BackgroundTransparency=1,TextColor3=Color3.new(1,1,1),ZIndex=6},panel)
    local gear=D.make('ImageLabel',{Name='SettingsGear',Image='',Position=UDim2.fromOffset(-1,-1),Size=UDim2.fromOffset(42,42),BackgroundTransparency=1,ScaleType=Enum.ScaleType.Fit,Active=false,ZIndex=7},settingsButton)
    gear:GetPropertyChangedSignal('IsLoaded'):Connect(function() if gear.IsLoaded and gear.Image~='' then settingsButton.TextTransparency=1 end end)
    loadUiAsset(gear,'gear')
    local settingsOverlay=D.make('TextButton',{Name='SettingsOverlay',Text='',Visible=false,Size=UDim2.fromScale(1,1),BackgroundColor3=Color3.new(0,0,0),BackgroundTransparency=0.32,AutoButtonColor=false,Active=true,ZIndex=50},panel)
    local settingsBox=D.make('Frame',{Name='SettingsBox',AnchorPoint=Vector2.new(0.5,0.5),Position=UDim2.fromScale(0.5,0.5),Size=UDim2.new(1,-28,0,414),BackgroundColor3=Color3.fromRGB(22,12,40),Active=true,ZIndex=51},settingsOverlay)
    D.make('UICorner',{CornerRadius=UDim.new(0,10)},settingsBox)
    themeModal(settingsBox)
    local function settingsLabel(text,y)
        local label=D.label(settingsBox,text,UDim2.fromOffset(14,y),UDim2.new(1,-28,0,28),Color3.new(1,1,1),20)
        label.Font=Enum.Font.FredokaOne;label.TextXAlignment=Enum.TextXAlignment.Center;label.TextScaled=true;label.ZIndex=54
        D.make('UITextSizeConstraint',{MinTextSize=12,MaxTextSize=20},label)
        return label
    end
    settingsLabel('SETTINGS',10)
    settingsLabel('CUSTOM GUI',59)
    settingsLabel('CUSTOM HOTKEY MENU',160)
    sizeMinus.Parent=settingsBox;sizePlus.Parent=settingsBox;sizeLabel.Parent=settingsBox
    sizeMinus.Position=UDim2.new(0.5,-78,0,94);sizeMinus.Size=UDim2.fromOffset(48,48)
    sizePlus.Position=UDim2.new(0.5,30,0,94);sizePlus.Size=UDim2.fromOffset(48,48)
    sizeLabel.Position=UDim2.new(0.5,-28,0,107);sizeLabel.Size=UDim2.fromOffset(56,22)
    for _,obj in ipairs({sizeMinus,sizePlus,sizeLabel}) do
        obj.ZIndex=55
        for _,child in ipairs(obj:GetDescendants()) do if child:IsA('GuiObject') then child.ZIndex=56 end end
    end
    local hotkeyButton=D.make('TextButton',{Name='HotkeyBind',Text=menuHotkey.Name,Font=Enum.Font.FredokaOne,Position=UDim2.new(0,14,0,199),Size=UDim2.new(1,-28,0,42),BackgroundColor3=Color3.fromRGB(58,36,98),TextColor3=Color3.new(1,1,1),TextSize=18,ZIndex=55},settingsBox)
    hotkeyButton.Font=Enum.Font.FredokaOne
    local waitingForHotkey=false
    local function stopSettings()
        waitingForHotkey=false;settingsOverlay.Visible=false;hotkeyButton.Text=menuHotkey.Name
    end
    do
        local visuals=D.baseEggVisuals
        local function toggle(name,y,value,set,waiting)
            local button=D.make('TextButton',{Text='',Position=UDim2.fromOffset(14,y),Size=UDim2.new(1,-28,0,38),BackgroundColor3=Color3.fromRGB(58,36,98),TextColor3=Color3.new(1,1,1),TextSize=18,Font=Enum.Font.FredokaOne,ZIndex=55},settingsBox)
            styleRaisedButton(button)
            local caption=button:FindFirstChild('RaisedCaption')
            if caption then
                caption.Font=Enum.Font.FredokaOne
                caption.TextScaled=true
                D.make('UITextSizeConstraint',{MinTextSize=11,MaxTextSize=19},caption)
                D.make('UIStroke',{Color=Color3.new(0,0,0),Thickness=1.8},caption)
            end
            local function paint()
                local enabled=value()
                local text=name..': '..(enabled and (waiting and waiting() and 'LOADING...' or 'ON') or 'OFF')
                local color=enabled and Color3.fromRGB(40,135,70) or Color3.fromRGB(58,36,98)
                if button.Text~=text then button.Text=text end
                if button.BackgroundColor3~=color then button.BackgroundColor3=color end
            end
            button.Activated:Connect(function() set(not value());paint() end)
            paint()
            return paint
        end
        D.paintNightSkyOption=toggle('NIGHT SKY',250,function() return D.nightSky.enabled end,D.setNightSky)
        D.paintMyEggOption=toggle('HIDE MY EGGS',294,function() return visuals.hideMine end,D.setHideMyEggs,function() return not visuals.renderer end)
        D.paintBaseEggOption=toggle('HIDE OTHERS EGGS',338,function() return visuals.enabled end,D.setHideBaseEggs,function() return not visuals.renderer end)
    end
    local settingsClose=D.make('TextButton',{Name='CloseSettings',Text='×',Position=UDim2.new(1,-46,0,4),Size=UDim2.fromOffset(40,40),BackgroundColor3=Color3.fromRGB(170,45,55),TextColor3=Color3.new(1,1,1),TextSize=24,ZIndex=55},settingsBox)
    settingsClose.Activated:Connect(stopSettings)
    settingsOverlay.Activated:Connect(stopSettings)
    settingsButton.Activated:Connect(function()
        if settingsOverlay.Visible then stopSettings() else settingsOverlay.Visible=true end
    end)
    hotkeyButton.Activated:Connect(function() waitingForHotkey=true;hotkeyButton.Text='PRESS A KEY  (ESC TO CANCEL)' end)
    local hotkeyConnection=Input.InputBegan:Connect(function(input,processed)
        if input.UserInputType~=Enum.UserInputType.Keyboard or input.KeyCode==Enum.KeyCode.Unknown then return end
        if waitingForHotkey then
            waitingForHotkey=false
            if input.KeyCode~=Enum.KeyCode.Escape then menuHotkey=input.KeyCode;saveSettings() end
            hotkeyButton.Text=menuHotkey.Name
            return
        end
        if processed or Input:GetFocusedTextBox() then return end
        if input.KeyCode==menuHotkey then
            panel.Visible=not panel.Visible;D.localPanel.Visible=not panel.Visible
            if not panel.Visible then stopSettings() end
        end
    end)
    D.gui.Destroying:Connect(function() hotkeyConnection:Disconnect() end)

    do
    -- Header title and egg are laid out as one centered visual group.
    do
        local service=game:GetService('TextService')
        heading.Font=discordSubtitle.Font
        local available=(panel.Size.X.Offset>0 and panel.Size.X.Offset or 402)-100
        local fontSize=22
        local textWidth
        repeat
            textWidth=math.ceil(service:GetTextSize(heading.Text,fontSize,discordSubtitle.Font,Vector2.new(1000,1000)).X)+4
            if textWidth<=available or fontSize<=14 then break end
            fontSize-=1
        until false
        heading.AnchorPoint=Vector2.new(0.5,0);heading.Position=UDim2.new(0.5,0,0,1);heading.Size=UDim2.fromOffset(textWidth,26)
        heading.TextSize=fontSize;heading.TextScaled=false;heading.TextXAlignment=Enum.TextXAlignment.Center;heading.TextStrokeTransparency=1
        local limit=heading:FindFirstChildOfClass('UITextSizeConstraint');if limit then limit.MaxTextSize=22 end
        D.make('UIStroke',{Color=Color3.new(0,0,0),Thickness=1.4},heading)
        discordSubtitle.TextSize=14;discordSubtitle.TextScaled=true;discordSubtitle.Size=UDim2.new(1,-108,0,16)
        discordSubtitle.Position=UDim2.new(0.5,0,0,27);discordSubtitle.TextStrokeTransparency=1
        local discordLimit=discordSubtitle:FindFirstChildOfClass('UITextSizeConstraint');if discordLimit then discordLimit.MaxTextSize=14 end
        D.make('UIStroke',{Color=Color3.new(0,0,0),Thickness=1.3},discordSubtitle)
    end
    sizeLabel.Font=Enum.Font.FredokaOne;sizeLabel.TextStrokeTransparency=1;sizeLabel.TextSize=20
    local sizeLimit=sizeLabel:FindFirstChildOfClass('UITextSizeConstraint');if sizeLimit then sizeLimit.MaxTextSize=20 end
    D.make('UIStroke',{Color=Color3.new(0,0,0),Thickness=1.6},sizeLabel)
    refreshButton.Font=Enum.Font.FredokaOne
    local refreshCaption=refreshButton:FindFirstChild('RaisedCaption')
    if refreshCaption then
        refreshCaption.Font=Enum.Font.FredokaOne;refreshCaption.TextSize=20;refreshCaption.TextScaled=true;refreshCaption.TextStrokeTransparency=1
        refreshCaption.Position=UDim2.fromOffset(4,2);refreshCaption.Size=UDim2.new(1,-8,1,-4)
        D.make('UITextSizeConstraint',{MinTextSize=12,MaxTextSize=20},refreshCaption)
        D.make('UIStroke',{Color=Color3.new(0,0,0),Thickness=1.7},refreshCaption)
    end
    resetTimer.Font=Enum.Font.FredokaOne;resetTimer.TextSize=16;resetTimer.TextScaled=true;resetTimer.TextStrokeTransparency=1
    D.make('UITextSizeConstraint',{MinTextSize=10,MaxTextSize=16},resetTimer)
    D.make('UIStroke',{Color=Color3.new(0,0,0),Thickness=1.4},resetTimer)
    local controlImages={}
    local controlLayout={plus={x=-2.644934804413241,y=-2.2657973921765304,w=53.289869608826486,h=52.405215646940825},minus={x=-31.89664429530201,y=1.6469798657718115,w=111.79328859060402,h=44.70604026845638}}
    local function pngControl(button,key,fallback,color)
        for _,child in ipairs(button:GetChildren()) do child:Destroy() end
        button.BackgroundTransparency=1;button.AutoButtonColor=false;button.ClipsDescendants=true
        button.Text='';button.TextTransparency=1;button.TextStrokeTransparency=1
        local fallbackLabel=D.make('TextLabel',{Name='SizeFallback',Text=fallback,Font=Enum.Font.FredokaOne,TextSize=34,TextColor3=color,TextStrokeTransparency=1,BackgroundTransparency=1,Size=UDim2.fromScale(1,1),Active=false,ZIndex=button.ZIndex+1},button)
        local fallbackStroke=D.make('UIStroke',{Color=Color3.new(0,0,0),Thickness=1.8},fallbackLabel)
        local layout=controlLayout[key]
        local image=D.make('ImageLabel',{Name='SizePNG',Image='',BackgroundTransparency=1,Position=UDim2.fromOffset(layout.x,layout.y),Size=UDim2.fromOffset(layout.w,layout.h),ScaleType=Enum.ScaleType.Stretch,Active=false,ZIndex=button.ZIndex+2},button)
        local outlines={}
        for _,offset in ipairs({{-1,0},{1,0},{0,-1},{0,1}}) do
            outlines[#outlines+1]=D.make('ImageLabel',{Name='SizeIconOutline',Image='',ImageColor3=Color3.new(0,0,0),ImageTransparency=1,BackgroundTransparency=1,Position=UDim2.fromOffset(layout.x+offset[1],layout.y+offset[2]),Size=UDim2.fromOffset(layout.w,layout.h),ScaleType=Enum.ScaleType.Stretch,Active=false,ZIndex=button.ZIndex+1},button)
        end
        image:GetPropertyChangedSignal('IsLoaded'):Connect(function()
            if image.IsLoaded and image.Image~='' then
                fallbackLabel.Visible=false;fallbackStroke.Enabled=false
                for _,outline in ipairs(outlines) do outline.Image=image.Image;outline.ImageTransparency=0 end
            end
        end)
        controlImages[key]=image
    end
    pngControl(sizePlus,'plus','+',Color3.fromRGB(124,58,237))
    pngControl(sizeMinus,'minus','−',Color3.fromRGB(235,30,55))
    task.spawn(function()
        local asset=getcustomasset or getsynasset
        if type(asset)~='function' or type(writefile)~='function' or type(D.decodeAsset)~='function' then return end
        local pending={}
        for name,image in pairs(controlImages) do
            local filename='s2r_beta_size_png_v1_'..name..'.png'
            local exists=false;if type(isfile)=='function' then pcall(function() exists=isfile(filename) end) end
            if exists then local ok,uri=pcall(asset,filename);if ok then image.Image=uri end end
            if image.Image=='' then pending[#pending+1]=name end
        end
        if #pending==0 then return end
        local ok,data=pcall(function() return Http:JSONDecode(game:HttpGet('https://raw.githubusercontent.com/syss1211/Tenshi-script/609430c9c12e125ebdcdd94edbc9101691e7f863/assets/nyx-size-controls-v1.json')) end)
        if not ok or type(data)~='table' then warn('S2R UI: size icons unavailable');return end
        for _,name in ipairs(pending) do
            if type(data[name])=='string' then
                pcall(function()
                    local bytes=D.decodeAsset(data[name])
                    if bytes:sub(1,8)~=string.char(137)..'PNG'..string.char(13,10,26,10) then return end
                    local filename='s2r_beta_size_png_v1_'..name..'.png'
                    writefile(filename,bytes)
                    if controlImages[name].Parent then controlImages[name].Image=asset(filename) end
                end)
            end
        end
    end)
    syncCloseArt=function(button)
        button.BackgroundTransparency=1;button.Font=Enum.Font.FredokaOne;button.TextSize=30
        button.TextColor3=Color3.fromRGB(245,45,45);button.TextStrokeColor3=Color3.new(0,0,0)
        local art=D.make('ImageLabel',{Name='SharedClosePNG',Image='',AnchorPoint=Vector2.new(0.5,0.5),Position=UDim2.fromScale(0.5,0.5),Size=UDim2.new(1,-8,1,-8),BackgroundTransparency=1,ScaleType=Enum.ScaleType.Fit,Active=false,ZIndex=button.ZIndex+1},button)
        local function sync()
            if not art.Parent then return end
            local uri=closeArt.Image
            art.Image=uri
            local hasImage=type(uri)=='string' and uri~=''
            -- Clear the native X on URI assignment, before any IsLoaded signal.
            button.Text=hasImage and '' or '×'
            button.TextTransparency=hasImage and 1 or 0
            button.TextStrokeTransparency=hasImage and 1 or 0
        end
        closeArt:GetPropertyChangedSignal('Image'):Connect(sync)
        sync()
    end
    syncCloseArt(settingsClose)
    end
    end
    local mutationPalettes={
        title={Color3.fromRGB(223,221,221),Color3.fromRGB(225,223,223),Color3.fromRGB(226,225,225),Color3.fromRGB(228,227,227),Color3.fromRGB(230,229,229),Color3.fromRGB(231,231,231),Color3.fromRGB(233,233,233),Color3.fromRGB(236,236,236),Color3.fromRGB(239,239,239),Color3.fromRGB(242,242,242),Color3.fromRGB(246,246,246),Color3.fromRGB(249,249,249),Color3.fromRGB(252,252,252),Color3.fromRGB(255,255,255),Color3.fromRGB(255,255,255),Color3.fromRGB(255,255,255),Color3.fromRGB(255,255,255),Color3.fromRGB(255,255,255),Color3.fromRGB(255,255,255),Color3.fromRGB(255,255,255),Color3.fromRGB(252,252,252),Color3.fromRGB(249,249,249),Color3.fromRGB(246,246,246),Color3.fromRGB(242,242,242),Color3.fromRGB(239,239,239),Color3.fromRGB(236,236,236),Color3.fromRGB(233,233,233),Color3.fromRGB(230,230,230),Color3.fromRGB(227,227,227),Color3.fromRGB(224,224,224),Color3.fromRGB(220,220,220),Color3.fromRGB(217,217,217),Color3.fromRGB(214,214,214)},
        discord={Color3.fromRGB(255,0,225),Color3.fromRGB(251,0,226),Color3.fromRGB(247,0,227),Color3.fromRGB(244,0,229),Color3.fromRGB(240,0,230),Color3.fromRGB(236,0,231),Color3.fromRGB(232,0,232),Color3.fromRGB(229,0,233),Color3.fromRGB(225,0,235),Color3.fromRGB(221,0,236),Color3.fromRGB(217,0,237),Color3.fromRGB(214,0,238),Color3.fromRGB(210,0,239),Color3.fromRGB(206,0,241),Color3.fromRGB(202,0,242),Color3.fromRGB(199,0,243),Color3.fromRGB(195,0,244),Color3.fromRGB(191,0,245),Color3.fromRGB(187,0,247),Color3.fromRGB(184,0,248),Color3.fromRGB(180,0,249),Color3.fromRGB(176,0,250),Color3.fromRGB(172,0,251),Color3.fromRGB(169,0,253),Color3.fromRGB(165,0,254),Color3.fromRGB(161,0,255)},
        golden={Color3.fromRGB(206,164,0),Color3.fromRGB(222,173,0),Color3.fromRGB(239,182,0),Color3.fromRGB(255,191,0),Color3.fromRGB(254,209,46),Color3.fromRGB(253,227,92)},
        rainbow={Color3.fromRGB(255,0,0),Color3.fromRGB(255,113,0),Color3.fromRGB(255,169,0),Color3.fromRGB(255,248,0),Color3.fromRGB(139,255,0),Color3.fromRGB(0,255,7),Color3.fromRGB(0,255,154)},
        silver={Color3.fromRGB(71,71,71),Color3.fromRGB(104,104,104),Color3.fromRGB(137,137,137),Color3.fromRGB(170,170,170),Color3.fromRGB(137,137,137),Color3.fromRGB(104,104,104),Color3.fromRGB(71,71,71)}
    }
    local mutationGradients={golden={},silver={},rainbow={},discord={},title={}}
    local function mutationSequence(palette,now)
        local phase=(now/4)%1
        local points={}
        for i=0,16 do
            local sample=((i/16-phase)%1)*#palette
            local index=math.floor(sample)
            points[#points+1]=ColorSequenceKeypoint.new(i/16,palette[index+1]:Lerp(palette[(index+1)%#palette+1],sample-index))
        end
        return ColorSequence.new(points)
    end
    local function mutationStyle(object,name)
        local key=name:lower()
        if key=='gold' then key='golden' end
        local palette=mutationPalettes[key]
        if not palette then return end
        if object:IsA('TextLabel') then
            object.TextColor3=Color3.new(1,1,1);object.TextStrokeTransparency=1
        else object.ImageColor3=Color3.new(1,1,1) end
        local gradient=D.make('UIGradient',{Color=mutationSequence(palette,os.clock()),Rotation=0},object)
        local bucket=mutationGradients[key];bucket[#bucket+1]=gradient
    end
    mutationStyle(discordSubtitle,'discord')
    mutationStyle(heading,'title')
    local filterPalettes={
        cosmic={Color3.fromRGB(67,37,239),Color3.fromRGB(113,29,255),Color3.fromRGB(90,37,230),Color3.fromRGB(67,44,204),Color3.fromRGB(63,44,244),Color3.fromRGB(41,12,217)},
        secret={Color3.fromRGB(40,40,40),Color3.fromRGB(66,62,59),Color3.fromRGB(90,90,87),Color3.fromRGB(118,124,118),Color3.fromRGB(144,152,152),Color3.fromRGB(195,195,201)},
        eternal={Color3.fromRGB(143,203,193),Color3.fromRGB(179,236,227),Color3.fromRGB(192,236,229),Color3.fromRGB(205,236,230),Color3.fromRGB(216,236,232),Color3.fromRGB(227,236,234),Color3.fromRGB(182,165,198),Color3.fromRGB(82,28,125),Color3.fromRGB(141,92,164),Color3.fromRGB(183,125,193),Color3.fromRGB(216,151,220),Color3.fromRGB(230,171,234),Color3.fromRGB(227,187,236),Color3.fromRGB(218,202,236),Color3.fromRGB(212,216,236)}
    }
    local filterWords=D.make('Frame',{Name='RarityFontParts',AnchorPoint=Vector2.new(0.5,0.5),Position=UDim2.fromScale(0.5,0.5),Size=UDim2.fromOffset(1,26),BackgroundTransparency=1,Active=false,ZIndex=rarity.ZIndex+5},rarity)
    local function filterLabel(text)
        local label=D.make('TextLabel',{Text=text,Font=Enum.Font.FredokaOne,TextSize=20,TextColor3=Color3.new(1,1,1),TextStrokeTransparency=1,BackgroundTransparency=1,TextWrapped=false,TextScaled=false,Active=false,ZIndex=filterWords.ZIndex},filterWords)
        D.make('UIStroke',{Color=Color3.new(0,0,0),Thickness=2},label)
        return label
    end
    local filterPrefix=filterLabel('MIN RARITY:')
    local filterWord=filterLabel('Any')
    local filterGradient=D.make('UIGradient',{Enabled=false,Rotation=0},filterWord)
    local filterName=rarityOptions[rarityIndex].name:lower()
    local function updateFilterColor(now)
        local palette=filterPalettes[filterName]
        if palette then
            filterWord.TextColor3=Color3.new(1,1,1);filterGradient.Enabled=true
            filterGradient.Color=mutationSequence(palette,now)
        else
            filterGradient.Enabled=false;filterWord.TextColor3=rarityColors[filterName] or Color3.new(1,1,1)
        end
    end
    local function refreshFilterWord()
        local name=rarityOptions[rarityIndex].name
        filterName=name:lower();filterWord.Text=name
        filterGradient.Rotation=filterName=='eternal' and 90 or 0
        rarity.TextTransparency=1
        local caption=rarity:FindFirstChild('RaisedCaption');if caption then caption.Visible=false end
        local panelWidth=panel.Size.X.Offset>0 and panel.Size.X.Offset or 402
        local available=math.max(20,panelWidth*rarity.Size.X.Scale+rarity.Size.X.Offset-20)
        local service=game:GetService('TextService')
        local size,prefixWidth,wordWidth=22,0,0
        repeat
            prefixWidth=math.ceil(service:GetTextSize(filterPrefix.Text,size,Enum.Font.FredokaOne,Vector2.new(1000,1000)).X)+4
            wordWidth=math.ceil(service:GetTextSize(name,size,Enum.Font.FredokaOne,Vector2.new(1000,1000)).X)+4
            if prefixWidth+wordWidth+6<=available or size<=10 then break end
            size-=1
        until false
        filterWords.Size=UDim2.fromOffset(prefixWidth+wordWidth+6,26)
        filterPrefix.Position=UDim2.new();filterPrefix.Size=UDim2.fromOffset(prefixWidth,26);filterPrefix.TextSize=size
        filterWord.Position=UDim2.fromOffset(prefixWidth+6,0);filterWord.Size=UDim2.fromOffset(wordWidth,26);filterWord.TextSize=size
        updateFilterColor(os.clock())
    end
    rarity:GetPropertyChangedSignal('Text'):Connect(refreshFilterWord)
    refreshFilterWord()
    local rarityGradientBuckets={cosmic={},secret={},eternal={}}
    local function styleRarityLabel(label,key)
        local palette=filterPalettes[key]
        if not palette then return end
        label.TextColor3=Color3.new(1,1,1)
        if key=='secret' then label.TextStrokeColor3=Color3.new(0,0,0);label.TextStrokeTransparency=0.25 end
        local gradient=D.make('UIGradient',{Color=mutationSequence(palette,os.clock()),Rotation=key=='eternal' and 90 or 0},label)
        rarityGradientBuckets[key][gradient]=true
    end
    local lastMutationUpdate=0
    local mutationMotion=game:GetService('RunService').Heartbeat:Connect(function()
        local now=os.clock()
        if now-lastMutationUpdate<1/20 then return end
        lastMutationUpdate=now
        if refreshing then
            local text='REFRESHING'..string.rep('.',math.floor(now/0.4)%3+1)
            if refreshButton.Text~=text then refreshButton.Text=text end
        end
        if loadingVisible and aliveMessage.Visible then
            local text=loadingText(now);if aliveMessage.Text~=text then aliveMessage.Text=text end
        end
        updateFilterColor(now)
        for key,bucket in pairs(rarityGradientBuckets) do
            if next(bucket) then
                local colors=mutationSequence(filterPalettes[key],now)
                for gradient in pairs(bucket) do
                    if gradient.Parent then gradient.Color=colors else bucket[gradient]=nil end
                end
            end
        end
        for key,bucket in pairs(mutationGradients) do
            if #bucket>0 then
                local colors=mutationSequence(mutationPalettes[key],now)
                for i=#bucket,1,-1 do
                    local gradient=bucket[i]
                    if not gradient.Parent then table.remove(bucket,i) else gradient.Color=colors end
                end
            end
        end
    end)
    D.gui.Destroying:Connect(function() mutationMotion:Disconnect() end)
    local function mutationWidth(name,textService,available)
        local spec=mutationSpriteData[name:lower()]
        if spec then return math.min(available,math.ceil(spec.width/spec.height*24)+8) end
        return math.min(available,math.ceil(textService:GetTextSize(name,22,Enum.Font.Arcade,Vector2.new(1000,28)).X)+8)
    end
    local function mutationWord(row,name,position,width)
        local word=D.label(row,name,position,UDim2.fromOffset(width,28),Color3.fromRGB(245,210,125),22)
        word.Font=Enum.Font.Arcade
        word.TextXAlignment=Enum.TextXAlignment.Center
        word.TextTruncate=Enum.TextTruncate.None;word.TextScaled=true;word.TextWrapped=false
        D.make('UITextSizeConstraint',{MinTextSize=1,MaxTextSize=22},word)
        mutationStyle(word,name)
        word.TextStrokeColor3=Color3.new(0,0,0);word.TextStrokeTransparency=0
        local fallbackStroke=D.make('UIStroke',{Color=Color3.new(0,0,0),Thickness=1.1},word)
        local spec=mutationSprites[name:lower()]
        if spec then
            local glyph=D.make('ImageLabel',{Image=spec.image,ImageTransparency=1,BackgroundTransparency=1,ImageColor3=Color3.new(1,1,1),Size=UDim2.new(1,-4,1,-4),Position=UDim2.fromOffset(2,2),ScaleType=Enum.ScaleType.Fit,Active=false,ZIndex=word.ZIndex+2},word)
            pcall(function() glyph.ResampleMode=Enum.ResamplerMode.Pixelated end)
            local shadows={}
            for _,offset in ipairs({{-1,0},{1,0},{0,-1},{0,1}}) do
                local shadow=D.make('ImageLabel',{Image=spec.image,ImageTransparency=1,ImageColor3=Color3.new(0,0,0),BackgroundTransparency=1,Size=UDim2.new(1,-4,1,-4),Position=UDim2.fromOffset(2+offset[1],2+offset[2]),ScaleType=Enum.ScaleType.Fit,Active=false,ZIndex=word.ZIndex+1},word)
                pcall(function() shadow.ResampleMode=Enum.ResamplerMode.Pixelated end)
                shadows[#shadows+1]=shadow
            end
            mutationStyle(glyph,name)
            local function ready()
                if glyph.IsLoaded then fallbackStroke.Enabled=false;word.TextStrokeTransparency=1;word.TextTransparency=1;glyph.ImageTransparency=0;for _,shadow in ipairs(shadows) do shadow.ImageTransparency=0 end end
            end
            glyph:GetPropertyChangedSignal('IsLoaded'):Connect(ready)
            ready()
        end
        return word
    end
    local ageLabels={}
    local function resetAgeText(cycle)
        if not cycle or type(cycle.remaining)~='number' or cycle.remaining~=cycle.remaining then return '--' end
        local remaining=math.clamp(math.ceil(cycle.remaining),0,300)
        return tostring(math.floor((300-remaining)/60))..'m ago'
    end
    local function resetAgeColor(cycle)
        local text=resetAgeText(cycle)
        local minutes=tonumber(text:match('^(%d+)m ago$'))
        if minutes and minutes>=4 then return Color3.fromRGB(255,85,85) end
        if minutes and minutes>=2 then return Color3.fromRGB(255,215,65) end
        return Color3.fromRGB(210,216,230)
    end
    local function updateSpawnAges(cycle)
        local text=resetAgeText(cycle)
        local color=resetAgeColor(cycle)
        for _,item in ipairs(ageLabels) do
            if item.label.Parent then
                if item.label.Text~=text then item.label.Text=text end
                if item.label.TextColor3~=color then item.label.TextColor3=color end
            end
        end
    end

    local joiningKey=nil
    D.joinAttempt=nil
    D.joinNotice=function(message)
        queryStatus=message
        if not active then return end
        D.gui:SetAttribute('S2RLastJoinResult',message)
        warn('[S2R JOIN] '..tostring(message))
    end
    D.finishJoin=function(attempt)
        if D.joinAttempt~=attempt then return end
        D.joinAttempt=nil;joining=false;joiningKey=nil;feedAt=-math.huge
    end
    local joinRetryAt=0
    local cardsByKey={}
    local function compactCardHeight()
        return math.clamp(math.floor((panel.Size.Y.Offset-238-16)/5),76,112)
    end
    D.fullJobs={}
    D.populationFull=function(entry)
        local noted=D.fullJobs[entry.jobId]
        local count,capacity,seen=tonumber(entry.playerCount),tonumber(entry.maxPlayers),tonumber(entry.populationAt)
        local now=(os.clock()+clockOffset)*1000
        local fresh=count and capacity and capacity>0 and seen and now-seen>=0 and now-seen<30000
        if fresh and (not noted or seen>noted.at) then
            noted=count>=capacity and {at=seen,expiresAt=seen+30000} or nil
            D.fullJobs[entry.jobId]=noted
        end
        if noted and now<noted.expiresAt then return true end
        if noted then D.fullJobs[entry.jobId]=nil end
        return fresh and count>=capacity
    end
    D.noteFull=function(entry)
        local now=(os.clock()+clockOffset)*1000
        for job,note in pairs(D.fullJobs) do if now>=note.expiresAt then D.fullJobs[job]=nil end end
        D.fullJobs[entry.jobId]={at=now,expiresAt=now+30000}
    end
    D.isFullFailure=function(result,message)
        if result==Enum.TeleportResult.GameFull then return true end
        local text=tostring(message or ''):lower()
        return text:find('server is full',1,true)~=nil or text:find('experience is full',1,true)~=nil or text:find('error code: 772',1,true)~=nil
    end
    local function joinPresentation(entry)
        local here=entry.isLocal or entry.jobId==game.JobId
        if entry.takenConfirmed then return 'TAKEN',Color3.fromRGB(235,55,65),false end
        if here then return 'HERE',Color3.fromRGB(86,90,100),false end
        local capacity=D.populationFull(entry)
        if capacity or entry.full then return 'FULL',Color3.fromRGB(220,59,72),false end
        if entry.unavailable or entry.upstreamMissing then return 'UNAVAILABLE',Color3.fromRGB(86,90,100),false end
        if joining and joiningKey==entry.key then
            local attempt=D.joinAttempt
            if attempt and os.clock()-attempt.startedAt<0.5 then
                return 'JOINING...',Color3.fromRGB(40,160,85),false
            end
        end
        return 'JOIN',Color3.fromRGB(40,160,85),true
    end
    local rankWidthCache={}
    local raritySizeCache={}
    local function cardSignature(entry)
        return Http:JSONEncode({tostring(entry.rarity),tostring(entry.mutations),tostring(entry.mutationText),tostring(entry.traitsKnown),tostring(entry.isEvent),tostring(entry.source)})
    end
    local function compactWeightToFit(text,available,size,service)
        local function fits(value) return service:GetTextSize(value,size,Enum.Font.FredokaOne,Vector2.new(1000,1000)).X<=available end
        local result=text
        while not fits(result) do
            local prefix,whole,fraction,suffix=result:match('^(.-)(%d+)%.(%d+)(.*)$')
            if not fraction then break end
            fraction=fraction:sub(1,-2)
            result=prefix..whole..(#fraction>0 and '.'..fraction or '')..suffix
        end
        return result
    end
    local function fitFinanceText(card)
        local rowWidth=panel.Size.X.Offset-28
        local width=rowWidth-184
        local service=game:GetService('TextService')
        local weightSize=type(card.entry.weight)=='number' and 16 or 19
        local weightAvailable=width*0.46-10
        local text=weightPresentation(card.entry)
        card.weightLabel.Text=compactWeightToFit(text,weightAvailable,weightSize,service)
        for _,spec in ipairs({{card.incomeLabel,width*0.54-10,20},{card.weightLabel,weightAvailable,weightSize}}) do
            local label,available,size=spec[1],spec[2],spec[3]
            while size>8 and service:GetTextSize(label.Text,size,label.Font,Vector2.new(1000,1000)).X>available do size-=1 end
            label.TextSize=size
        end
    end
    local function updateCard(card,entry,i)
        local height=compactCardHeight()
        if card.compactHeight~=height or card.renderScale~=responsiveScale.Scale then
            card.renderScale=responsiveScale.Scale
            card.compactHeight=height;card.row.Size=UDim2.new(1,-12,0,height)
            local renderScale=responsiveScale.Scale
            if type(renderScale)~='number' or renderScale<=0 then renderScale=1 end
            local iconSize=math.floor(math.min(80,height-22)*renderScale)/renderScale
            card.icon.Size=UDim2.fromOffset(iconSize,iconSize);card.icon.Position=UDim2.fromOffset(math.floor((4+(78-iconSize)/2)*renderScale)/renderScale,0)
            card.spotlight.Position=card.icon.Position
            card.spotlight.Size=card.icon.Size
            card.join.Position=UDim2.new(1,-98,0,math.min(29,height-54))
        end
        local rankText='#'..tostring(entry.displayRank or entry.globalRank or i)
        if card.rankLabel.Text~=rankText then
            local width=rankWidthCache[rankText]
            if not width then
                width=math.ceil(game:GetService('TextService'):GetTextSize(rankText,20,Enum.Font.FredokaOne,Vector2.new(1000,28)).X)+4
                rankWidthCache[rankText]=width
            end
            card.rankLabel.Text=rankText;card.rankLabel.Size=UDim2.fromOffset(width,28)
            card.nameLabel.Position=UDim2.fromOffset(86+width,3);card.nameLabel.Size=UDim2.new(1,-94-width,0,26)
        end
        if card.nameLabel.Text~=tostring(entry.name) then card.nameLabel.Text=tostring(entry.name) end
        if card.icon.Image~=(entry.icon or '') then card.icon.Image=entry.icon or '' end
        if not card.financeReady or card.rate~=entry.rate or card.missingRate~=entry.missingRate then
            card.incomeLabel.Text=entry.missingRate and 'Income unavailable' or D.money(entry.rate)
            card.rate=entry.rate;card.missingRate=entry.missingRate
        end
        if not card.financeReady or card.scale~=entry.scale or card.weight~=entry.weight then
            local text,color=weightPresentation(entry)
            local isScale=type(entry.weight)~='number' and type(entry.scale)=='number'
            card.weightLabel.Text=text;card.weightLabel.TextColor3=color
            card.weightLabel.Font=Enum.Font.FredokaOne
            card.weightLabel.TextSize=isScale and 19 or 16
            card.weightLimit.MaxTextSize=isScale and 19 or 16
            card.scale=entry.scale;card.weight=entry.weight
        end
        if not card.financeReady or card.fittedRate~=entry.rate or card.fittedWeight~=entry.weight or card.fittedScale~=entry.scale then
            fitFinanceText(card);card.fittedRate=entry.rate;card.fittedWeight=entry.weight;card.fittedScale=entry.scale
        end
        card.multiplierLabel.Text,card.multiplierLabel.TextColor3=D.scalePresentation(entry)
        card.financeReady=true
        local text,color,enabled=joinPresentation(entry)
        if card.join.Text~=text then card.join.Text=text end
        if card.buttonText~=text or card.buttonEnabled~=enabled then
            card.join.BackgroundColor3=color
            card.join.Active=enabled;card.join.AutoButtonColor=enabled;card.join.Selectable=enabled
            card.buttonText=text;card.buttonEnabled=enabled
        end
    end
    D.scrollRows={}
    D.scrollAnchor=function(previous,nextOffsets,y,scale)
        if y<=0 or #previous==0 then return y end
        local index=1
        while index<#previous and previous[index+1].offset*scale<=y do index+=1 end
        local within=y-previous[index].offset*scale
        for i=index,#previous do
            local offset=nextOffsets[previous[i].key]
            if offset then return offset*scale+within end
        end
        for i=index-1,1,-1 do
            local offset=nextOffsets[previous[i].key]
            if offset then return offset*scale+within end
        end
        return y
    end
    local rendering,renderPending,renderQueued=false,false,false
    local function queueRender()
        if renderQueued or not active then return end
        renderQueued=true
        task.defer(function() renderQueued=false;if active then render() end end)
    end
    D.mergeOwnTaken=function(source,now)
        local takenByKey={}
        for key,entry in pairs(D.hostTaken or {}) do
            if D.publicEntryAllowed(entry,now) then
                local row=table.clone(entry);row.isLocal=true
                takenByKey[key]=row
            end
        end
        for i=#source,1,-1 do if takenByKey[source[i].key] then table.remove(source,i) end end
        for _,entry in pairs(takenByKey) do
            if (entry.rate or 0)>=minRate and (entry.rank or 0)>=minRank then source[#source+1]=entry end
        end
    end
    D.sortDisplayedEggs=function(entries,mode)
        if mode=='Value' then return end
        table.sort(entries,function(a,b)
            if mode=='Weight' then
                local left,right=tonumber(a.weight) or 0,tonumber(b.weight) or 0
                left=left>0 and left or 0
                right=right>0 and right or 0
                if left~=right then return left>right end
            else
                local left,right=a.rank or a.localTier or 0,b.rank or b.localTier or 0
                if left~=right then return left>right end
            end
            return a.displayRank<b.displayRank
        end)
        for index,entry in ipairs(entries) do entry.displayRank=index end
    end
    local function renderOnce()
        local passEpoch,passScope=queryEpoch,othersOnly
        local batchStarted=os.clock()
        local passDeadline=math.huge
        local function checkpoint()
            if os.clock()-batchStarted<0.003 then return true end
            task.wait()
            batchStarted=os.clock()
            if not active then return false end
            if queryEpoch~=passEpoch or othersOnly~=passScope or (os.clock()+clockOffset)*1000>=passDeadline then
                renderPending=true
                return false
            end
            return true
        end
        local now=(os.clock()+clockOffset)*1000
        local resetAge=resetAgeText(cycleInfo())
        local entries={}
        local source,seen={},{}
        local metadata=D.metadata and D.metadata()
        local gameNow=workspace:GetServerTimeNow()*1000
        local validLocal=not metadata or not metadata.resetAt or metadata.resetAt-2000>gameNow
        local current=validLocal and D.entries() or {}
        if othersOnly then
            -- MY SERVER is a live local view. ALL-only cache/tombstone rules
            -- must never suppress a record returned by the current field scan.
            local live=D.entries()
            local localCycle=cycleInfo()
            for _,e in ipairs(live) do
                if (e.rate or 0)>=minRate and (e.tier or 0)>=minRank then
                    local uid=tostring(e.uid or e.key)
                    source[#source+1]={key=game.PlaceId..':'..game.JobId..':'..uid,uid=uid,
                        name=e.name,rate=e.rate or 0,missingRate=e.rate==nil,scale=e.scale,weight=e.weight,
                        icon=e.icon,rarity=e.rarity,rank=e.tier,localTier=e.tier,mutations=e.mutationText,
                        traitsKnown=e.traitsKnown~=false,area=e.areaKey or e.area,model=e.model,isLocal=true,
                        source=e.isEvent and 'event' or 'field',estimated=e.estimated or e.unmutatedRate~=nil,
                        placeId=game.PlaceId,jobId=game.JobId,expiresAt=now+5000,seenAt=0,
                        spawnedAt=not e.isEvent and localCycle and localCycle.respawnAt or nil}
                end
            end
            if D.gui then pcall(function() D.gui:SetAttribute('S2RLocalScanCount',#live);D.gui:SetAttribute('S2RLocalVisibleCount',#source) end) end
        else
        if not othersOnly then
            for _,e in ipairs(feed) do
                if e.jobId~=game.JobId and (e.cached~=true or e.takenConfirmed==true) and (e.rate or 0)>=minRate and (e.rank or 0)>=minRank and type(e.expiresAt)=='number' and e.expiresAt>now then source[#source+1]=e;seen[e.key]=true end
            end
        end
            local localCycle=cycleInfo()
            for _,e in ipairs(current) do
                if e.broadcastEligible and (e.rate or 0)>=math.max(minRate,MIN_BROADCAST_RATE) and (e.tier or 0)>=minRank then
                    local key=game.PlaceId..':'..game.JobId..':'..tostring(e.uid or e.key)
                    if not seen[key] then
                        seen[key]=true
                        source[#source+1]={key=key,uid=tostring(e.uid or e.key),name=e.name,rate=e.rate or 0,missingRate=e.rate==nil,scale=e.scale,weight=e.weight,icon=e.icon,rarity=e.rarity,mutations=e.mutationText,traitsKnown=e.traitsKnown~=false,area=e.areaKey or e.area,model=e.model,isLocal=true,localTier=e.tier,full=false,source=e.isEvent and 'event' or 'field',estimated=e.estimated or e.unmutatedRate~=nil,placeId=game.PlaceId,jobId=game.JobId,expiresAt=now+5000,seenAt=0,spawnedAt=not e.isEvent and localCycle and localCycle.respawnAt or nil,spawnTimeKnown=not e.isEvent and localCycle~=nil and type(localCycle.respawnAt)=='number'}
                    end
                end
            end
        end
            if not othersOnly then D.mergeOwnTaken(source,now) end
            table.sort(source,function(a,b) if a.rate~=b.rate then return a.rate>b.rate end; return a.key<b.key end)
            local rowLimit=not othersOnly and viewerCode=='' and 30 or 25
            for _,entry in ipairs(source) do
                if #entries>=rowLimit then break end
                local hideHere=not othersOnly and #entries>=14 and not entry.takenConfirmed
                    and (entry.isLocal or entry.jobId==game.JobId)
                if not hideHere and D.publicEntryAllowed(entry,now) and (othersOnly or not entry.takenConfirmed or #entries<5) then
                    local visible=table.clone(entry)
                    visible.displayRank=#entries+1
                    entries[#entries+1]=visible
                end
        end
        D.sortDisplayedEggs(entries,D.sortOptions[D.sortIndex])
        -- Keep the old canvas extent while rebuilding so Roblox does not clamp
        -- the scroll position to zero when the rows are temporarily removed.
        local canvasHeight=#entries==0 and 40 or 0
        local nextRows,nextOffsets={},{}
        ageLabels={}
        local wanted={}
        for _,entry in ipairs(entries) do wanted[entry.key]=true;passDeadline=math.min(passDeadline,entry.expiresAt) end
        for key,card in pairs(cardsByKey) do
            if not wanted[key] then
                card.row:Destroy();cardsByKey[key]=nil
                if not checkpoint() then return end
            end
        end
        loadingVisible=#entries==0 and (othersOnly and type(D.ready)=='function' and not D.ready() or not othersOnly and feedAt<=0)
        aliveMessage.Visible=#entries==0
        aliveMessage.Text=loadingVisible and loadingText(os.clock()) or othersOnly and (type(D.ready)=='function' and not D.ready() and 'Reading current server eggs...' or 'No matching eggs in this server') or PREMIUM_EDITION and viewerCode=='' and 'Enter your Premium access code' or 'No matching eggs right now'
        for i,entry in ipairs(entries) do
            local signature=cardSignature(entry)
            local card=cardsByKey[entry.key]
            if not card or not card.row.Parent or card.signature~=signature then
            if card and card.row.Parent then card.row:Destroy() end
            card={entry=entry,signature=signature}
            local row=D.make('Frame',{Size=UDim2.new(1,-12,0,90),LayoutOrder=i,BackgroundColor3=Color3.fromRGB(70,44,112),BackgroundTransparency=0.24,BorderSizePixel=0},list)
            card.row=row
            row.ClipsDescendants=true
            D.make('UICorner',{CornerRadius=UDim.new(0,6)},row)
            D.make('UIGradient',{Color=ColorSequence.new(Color3.new(1,1,1),Color3.fromRGB(185,160,230)),Rotation=90},row)
            D.make('UIStroke',{Color=Color3.fromRGB(10,5,20),Thickness=2,ApplyStrokeMode=Enum.ApplyStrokeMode.Border},row)
            D.make('Frame',{Name='CardBevelTop',Position=UDim2.fromOffset(2,1),Size=UDim2.new(1,-4,0,1),BackgroundColor3=Color3.fromRGB(170,140,235),BackgroundTransparency=0.3,BorderSizePixel=0,Active=false},row)
            D.make('Frame',{Name='CardBevelBottom',Position=UDim2.new(0,2,1,-2),Size=UDim2.new(1,-4,0,1),BackgroundColor3=Color3.fromRGB(10,5,20),BorderSizePixel=0,Active=false},row)
            -- Static native UI rays: no downloads, image compression or animation work.
            local spotlight=D.make('Frame',{Name='PetSpotlight',Position=UDim2.fromOffset(2,0),Size=UDim2.new(0,82,1,-22),BackgroundTransparency=1,BorderSizePixel=0,ClipsDescendants=false,Active=false,ZIndex=row.ZIndex+1},row)
            for n=0,11 do
                local ray=D.make('Frame',{Name='WhiteRay',AnchorPoint=Vector2.new(0.5,0.5),Position=UDim2.fromScale(0.5,0.5),Size=UDim2.new(0.94,0,0,n%2==0 and 8 or 4),Rotation=n*15+8,BackgroundColor3=Color3.new(1,1,1),BackgroundTransparency=0.66,BorderSizePixel=0,Active=false,ZIndex=spotlight.ZIndex},spotlight)
                D.make('UIGradient',{Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,1),NumberSequenceKeypoint.new(0.2,0.97),NumberSequenceKeypoint.new(0.4,0.65),NumberSequenceKeypoint.new(0.5,0.2),NumberSequenceKeypoint.new(0.6,0.65),NumberSequenceKeypoint.new(0.8,0.97),NumberSequenceKeypoint.new(1,1)}),Rotation=0},ray)
            end
            for n=1,12 do
                local glow=D.make('Frame',{Name='SoftCenter',AnchorPoint=Vector2.new(0.5,0.5),Position=UDim2.fromScale(0.5,0.5),Size=UDim2.fromScale(1-n*0.065,1-n*0.065),BackgroundColor3=Color3.new(1,1,1),BackgroundTransparency=0.985-n*0.002,BorderSizePixel=0,Active=false,ZIndex=spotlight.ZIndex},spotlight)
                D.make('UICorner',{CornerRadius=UDim.new(1,0)},glow)
            end
            card.spotlight=spotlight
            card.icon=D.make('ImageLabel',{Name='PetIcon',Image=entry.icon or '',ZIndex=spotlight.ZIndex+1,BackgroundTransparency=1,Size=UDim2.fromOffset(88,88),Position=UDim2.fromOffset(4,4),ScaleType=Enum.ScaleType.Fit},row)
            local rarityKey=tostring(entry.rarity):lower():gsub('%s+','')
            local nameColor=rarityColors[rarityKey] or Color3.fromRGB(225,225,235)
            local rankText='#'..tostring(entry.displayRank or entry.globalRank or i)
            local textService=game:GetService('TextService')
            local rankWidth=rankWidthCache[rankText]
            if not rankWidth then
                rankWidth=math.ceil(textService:GetTextSize(rankText,20,Enum.Font.FredokaOne,Vector2.new(1000,28)).X)+4
                rankWidthCache[rankText]=rankWidth
            end
            local rankLabel=D.label(row,rankText,UDim2.fromOffset(86,3),UDim2.fromOffset(rankWidth,26),Color3.fromRGB(220,224,235),20)
            rankLabel.Font=Enum.Font.FredokaOne
            D.make('UIStroke',{Color=Color3.new(0,0,0),Thickness=1.5},rankLabel)
            card.rankLabel=rankLabel
            rankLabel.TextTruncate=Enum.TextTruncate.None
            local nameLabel=D.label(row,tostring(entry.name),UDim2.fromOffset(86+rankWidth,3),UDim2.new(1,-94-rankWidth,0,26),nameColor,21)
            card.nameLabel=nameLabel
            nameLabel.Font=Enum.Font.GothamBlack
            D.make('UIStroke',{Color=Color3.new(0,0,0),Thickness=1.1},nameLabel)
            nameLabel.TextStrokeColor3=Color3.new(0,0,0);nameLabel.TextStrokeTransparency=1
            rankLabel.TextStrokeColor3=Color3.new(0,0,0);rankLabel.TextStrokeTransparency=1
            pcall(function() card.icon.ResampleMode=Enum.ResamplerMode.Default end)
            local rarityCell=D.make('Frame',{Name='RarityCell',Position=UDim2.new(0,2,1,-26),Size=UDim2.fromOffset(82,22),BackgroundTransparency=1},row)
            local rarityText=tostring(entry.rarity)
            local rarityTextSize=raritySizeCache[rarityText]
            if not rarityTextSize then
                rarityTextSize=20
                while rarityTextSize>1 do
                    local bounds=textService:GetTextSize(rarityText,rarityTextSize,Enum.Font.GothamBlack,Vector2.new(1000,1000))
                    if bounds.X<=76 and bounds.Y<=20 then break end
                    rarityTextSize-=1
                end
                raritySizeCache[rarityText]=rarityTextSize
            end
            local rarityLabel=D.label(rarityCell,rarityText,UDim2.fromOffset(3,1),UDim2.new(1,-6,1,-2),nameColor,rarityTextSize)
            rarityLabel.Font=Enum.Font.GothamBlack
            rarityLabel.TextStrokeColor3=Color3.new(0,0,0);rarityLabel.TextStrokeTransparency=0.2
            rarityLabel.TextXAlignment=Enum.TextXAlignment.Center
            rarityLabel.TextYAlignment=Enum.TextYAlignment.Center
            rarityLabel.TextTruncate=Enum.TextTruncate.None
            rarityLabel.TextScaled=false
            rarityLabel.TextWrapped=false
            styleRarityLabel(nameLabel,rarityKey)
            local finance=D.make('Frame',{Name='IncomeAndWeight',Position=UDim2.fromOffset(86,31),Size=UDim2.new(1,-184,0,22),BackgroundTransparency=1},row)
            local incomeCell=D.make('Frame',{Name='IncomeCell',Position=UDim2.new(),Size=UDim2.new(0.54,-4,1,0),BackgroundTransparency=1,ClipsDescendants=false},finance)
            local incomeLabel=D.label(incomeCell,entry.missingRate and 'Income unavailable' or D.money(entry.rate),UDim2.fromOffset(3,2),UDim2.new(1,-6,1,-4),Color3.fromRGB(135,240,140),20)
            card.incomeLabel=incomeLabel
            incomeLabel.TextStrokeColor3=Color3.new(0,0,0);incomeLabel.TextStrokeTransparency=1
            incomeLabel.Font=Enum.Font.GothamBlack
            D.make('UIStroke',{Color=Color3.new(0,0,0),Thickness=1.1},incomeLabel)
            incomeLabel.TextTruncate=Enum.TextTruncate.None
            incomeLabel.TextScaled=false
            incomeLabel.TextWrapped=false
            D.make('UITextSizeConstraint',{MinTextSize=1,MaxTextSize=20},incomeLabel)
            local weightText,weightColor=weightPresentation(entry)
            local isScale=type(entry.weight)~='number' and type(entry.scale)=='number'
            local weightCell=D.make('Frame',{Name='WeightCell',Position=UDim2.new(0.54,4,0,0),Size=UDim2.new(0.46,-4,0,22),BackgroundTransparency=1,ClipsDescendants=false},finance)
            local weightLabel=D.label(weightCell,weightText,UDim2.fromOffset(3,2),UDim2.new(1,-6,1,-4),weightColor,isScale and 19 or 16)
            card.weightLabel=weightLabel
            card.multiplierLabel=D.label(weightCell,'',UDim2.fromOffset(3,21),UDim2.new(1,-6,0,18),Color3.fromRGB(220,224,235),18)
            card.multiplierLabel.Font=Enum.Font.FredokaOne;card.multiplierLabel.TextScaled=true
            card.multiplierLabel.TextWrapped=false;card.multiplierLabel.TextStrokeTransparency=1
            D.make('UITextSizeConstraint',{MinTextSize=10,MaxTextSize=18},card.multiplierLabel)
            D.make('UIStroke',{Color=Color3.new(0,0,0),Thickness=1.8},card.multiplierLabel)
            D.make('UIStroke',{Color=Color3.new(0,0,0),Thickness=1.8},weightLabel)
            weightLabel.TextStrokeColor3=Color3.new(0,0,0);weightLabel.TextStrokeTransparency=1
            weightLabel.Font=Enum.Font.FredokaOne
            weightLabel.TextTruncate=Enum.TextTruncate.None
            weightLabel.TextScaled=false
            weightLabel.TextWrapped=false
            card.weightLimit=D.make('UITextSizeConstraint',{MinTextSize=1,MaxTextSize=isScale and 19 or 16},weightLabel)
            local ageLabel=D.label(finance,resetAge,UDim2.new(1,-98,1,-23),UDim2.fromOffset(90,22),Color3.fromRGB(210,216,230),17)
            ageLabel.Font=Enum.Font.FredokaOne
            ageLabel.TextXAlignment=Enum.TextXAlignment.Center;ageLabel.TextYAlignment=Enum.TextYAlignment.Center
            ageLabel.TextStrokeColor3=Color3.new(0,0,0);ageLabel.TextStrokeTransparency=1
            D.make('UIStroke',{Color=Color3.new(0,0,0),Thickness=1.8},ageLabel)
            ageLabel.Parent=row
            ageLabel.Name='SpawnAge';ageLabel.TextScaled=true;ageLabel.TextWrapped=false;ageLabel.TextTruncate=Enum.TextTruncate.None
            D.make('UITextSizeConstraint',{MinTextSize=1,MaxTextSize=17},ageLabel)
            card.ageLabel=ageLabel
            rarityLabel.TextColor3=nameLabel.TextColor3
            local nameGradient=nameLabel:FindFirstChildOfClass('UIGradient')
            if nameGradient then
                local gradient=nameGradient:Clone();gradient.Parent=rarityLabel
                rarityGradientBuckets[rarityKey][gradient]=true
            end

            local names=mutationNames(entry)
            local available=math.max(100,panel.Size.X.Offset-130)
            local widths,total={},0
            for i,name in ipairs(names) do widths[i]=mutationWidth(name,textService,available);total+=widths[i]+5 end
            local strip=D.make('Frame',{Name='MutationStrip',Position=UDim2.new(0,86,1,-29),Size=UDim2.new(1,-94,0,28),BackgroundTransparency=1,ClipsDescendants=true},row)
            local words=D.make('Frame',{Name='MutationWords',Position=UDim2.fromOffset(4,0),Size=UDim2.fromOffset(math.max(1,total),28),BackgroundTransparency=1},strip)
            D.make('UIScale',{Scale=math.min(1,available/math.max(1,total))},words)
            local x=0
            for i,name in ipairs(names) do mutationWord(words,name,UDim2.fromOffset(x,0),widths[i]);x+=widths[i]+5 end
            row.Size=UDim2.new(1,-12,0,compactCardHeight())
            local here=entry.isLocal or entry.jobId==game.JobId
            local join=D.make('TextButton',{Text=select(1,joinPresentation(entry)),Position=UDim2.new(1,-98,0,29),Size=UDim2.fromOffset(90,32),BackgroundColor3=(entry.full or entry.unavailable) and Color3.fromRGB(255,75,85) or here and Color3.fromRGB(86,90,100) or Color3.fromRGB(40,160,85),TextColor3=Color3.new(1,1,1),TextSize=13},row)
            card.join=join
            local joinCorner=join:FindFirstChildOfClass('UICorner')
            if joinCorner then joinCorner.CornerRadius=UDim.new(0,3) end
            join.Font=Enum.Font.FredokaOne
            styleRaisedButton(join)
            local caption=join:FindFirstChild('RaisedCaption')
            if caption then
                caption.Font=Enum.Font.FredokaOne;caption.TextScaled=true;caption.TextSize=20
                caption.TextStrokeTransparency=1
                caption.Position=UDim2.fromOffset(5,2);caption.Size=UDim2.new(1,-10,1,-4)
                D.make('UITextSizeConstraint',{MinTextSize=10,MaxTextSize=20},caption)
                D.make('UIStroke',{Color=Color3.new(0,0,0),Thickness=2},caption)
            end
            join.Active=not (entry.full or entry.unavailable)
            join.AutoButtonColor=not (entry.full or entry.unavailable)
            join.Selectable=not (entry.full or entry.unavailable)
            join.Activated:Connect(function()
                local entry=card.entry
                if not D.publicEntryAllowed(entry,(os.clock()+clockOffset)*1000) or entry.takenConfirmed or entry.full or entry.unavailable or entry.upstreamMissing or D.populationFull(entry) or randomBusy or os.clock()<joinRetryAt or entry.jobId==game.JobId then return end
                if (os.clock()+clockOffset)*1000>=entry.expiresAt then queryStatus='Report expired; refreshing'; feedAt=0; return end
                joining=true;joiningKey=entry.key;joinRetryAt=os.clock()+0.5
                local attempt={startedAt=os.clock(),replacedPending=D.joinAttempt~=nil,id=Http:GenerateGUID(false),jobId=entry.jobId,uid=entry.uid,placeId=entry.placeId,entry=entry}
                D.joinAttempt=attempt
                task.delay(14,function()
                    if not active or D.joinAttempt~=attempt then return end
                    D.testReloadQueued=false
                    D.finishJoin(attempt)
                    queueRender()
                    D.joinNotice(attempt.teleportStarted and 'Roblox teleport timed out. Try again.' or 'Join request timed out. Try again.')
                end)
                queryStatus='Joining '..entry.name
                updateCard(card,entry,card.row.LayoutOrder or 1)
                task.delay(0.5,queueRender)
                entry=card.entry
                if not active or D.joinAttempt~=attempt then return end
                if not D.publicEntryAllowed(entry,(os.clock()+clockOffset)*1000) or entry.takenConfirmed or entry.full or entry.unavailable or entry.upstreamMissing or D.populationFull(entry) then
                    D.finishJoin(attempt);updateCard(card,entry,card.row.LayoutOrder or 1);return
                end
                if (os.clock()+clockOffset)*1000>=entry.expiresAt then
                    D.finishJoin(attempt);feedAt=-math.huge;render();return
                end
                local directory=featureConfig
                if directory then
                    local payload={placeId=entry.placeId,jobId=entry.jobId,uid=entry.uid,reporterId=reporterId,userId=D.player.UserId}
                    local result=network(directory.endpoint..'/v1/join','POST',Http:JSONEncode(payload),
                        {['Content-Type']='application/json',['X-NYX-Room']=directory.roomKey},false,2,true)
                    if not active or D.joinAttempt~=attempt then return end
                    if not result or result.allowed~=true then
                        if result and result.full and not result.unavailable then
                            entry.full=true
                            if result.capacityFull then D.noteFull(entry) end
                        end
                        feedAt=-math.huge
                        D.finishJoin(attempt);queueRender();return
                    end
                end
                D.saveGuiBeforeTeleport()
                D.stopFarm()
                attempt.teleportStarted=true;attempt.failureDeadline=os.clock()+30
                D.lastTeleportAttempt=attempt
                if not active or D.joinAttempt~=attempt then return end
                print('[S2R JOIN] Requesting Roblox teleport')
                local ok,err=pcall(function() Teleports:TeleportToPlaceInstance(entry.placeId,entry.jobId,D.player) end)
                if not ok and D.joinAttempt==attempt then
                    D.lastTeleportAttempt=nil
                    D.testReloadQueued=false
                    if D.isFullFailure(nil,err) then D.noteFull(entry);queueRender() end
                    D.finishJoin(attempt);D.joinNotice('Roblox: '..tostring(err));queueRender()
                end
            end)
            end
            card.entry=entry
            updateCard(card,entry,i)
            card.row.LayoutOrder=i
            cardsByKey[entry.key]=card
            ageLabels[#ageLabels+1]={label=card.ageLabel,entry=entry}
            nextRows[i]={key=entry.key,offset=canvasHeight}
            nextOffsets[entry.key]=canvasHeight
            canvasHeight+=card.row.Size.Y.Offset+4
            if not checkpoint() then return end
        end
        if queryEpoch~=passEpoch or othersOnly~=passScope then renderPending=true;return end
        local position=list.CanvasPosition
        local oldHeight=list.CanvasSize.Y.Offset
        local scale=oldHeight>0 and list.AbsoluteCanvasSize.Y/oldHeight or responsiveScale.Scale
        if scale<=0 then scale=1 end
        local target=D.scrollAnchor(D.scrollRows,nextOffsets,position.Y,scale)
        D.scrollRows=nextRows
        list.CanvasSize=UDim2.fromOffset(0,canvasHeight)
        target=math.clamp(target,0,math.max(0,canvasHeight*scale-list.AbsoluteWindowSize.Y))
        if math.abs(list.CanvasPosition.Y-target)>0.5 then
            list.CanvasPosition=Vector2.new(position.X,target)
        end
        list.Visible=true
    end
    render=function()
        if not active then return end
        if rendering then renderPending=true;return end
        rendering=true
        local ok,err=pcall(renderOnce)
        rendering=false
        if renderPending then renderPending=false;queueRender() end
        if not ok then list.Visible=true;error(err) end
    end
    requestScopeRender=function()
        -- Hide old-tab rows immediately; never expose remote JOINs as MY SERVER.
        list.Visible=false
        D.scrollRows={}
        list.CanvasPosition=Vector2.new(0,0)
        queueRender()
    end
    refreshButton.Activated:Connect(function()
        if refreshing or not active then return end
        refreshing=true;refreshButton.Text='REFRESHING.'
        task.spawn(function()
            local ok,err=pcall(function()
                local deadline=os.clock()+12
                while active and networkBusy and os.clock()<deadline do task.wait(0.1) end
                if not active then return end
                if networkBusy then error('Network busy; try again') end
                if not othersOnly then
                    local loaded,message=refresh();if not loaded then error(message) end
                end
                lastRender=nil;render()
            end)
            refreshing=false
            if active then
                refreshButton.Text='REFRESH'
                queryStatus=ok and 'List refreshed' or ('Refresh failed: '..tostring(err))
            end
        end)
    end)
    do
        local Tweens=game:GetService('TweenService')
        local states={}
        local function attachButtonMotion(button)
            if not (button:IsA('TextButton') or button:IsA('ImageButton')) then return end
            if button.Name=='SettingsOverlay' or button.Name=='LauncherHitArea' or button:GetAttribute('S2RButtonMotion') then return end
            button:SetAttribute('S2RButtonMotion',true)
            local motion=D.make('UIScale',{Name='ButtonMotion',Scale=1},button)
            local state={button=button,motion=motion,base=button.Position,hover=false,input=nil,tween=nil,writing=false,alive=true}
            states[button]=state
            local function enabled() return button.Active~=false and button.Selectable~=false end
            local function center()
                if not state.alive or not button.Parent then return end
                local delta=motion.Scale-1
                local x,y=0.5-button.AnchorPoint.X,0.5-button.AnchorPoint.Y
                local size=button.Size
                local goal=UDim2.new(state.base.X.Scale-size.X.Scale*delta*x,state.base.X.Offset-size.X.Offset*delta*x,state.base.Y.Scale-size.Y.Scale*delta*y,state.base.Y.Offset-size.Y.Offset*delta*y)
                state.lastPosition=goal
                if button.Position==goal then return end
                state.writing=true
                button.Position=goal
                state.writing=false
            end
            local function update()
                if not state.alive then return end
                if state.tween then state.tween:Cancel();state.tween=nil end
                local target=1
                if enabled() then
                    if state.input then target=0.95
                    elseif state.hover then
                        local width=math.max(1,button.AbsoluteSize.X/math.max(0.01,motion.Scale))
                        target=math.min(1.06,1+5/width)
                    end
                else state.input=nil;state.hover=false end
                state.tween=Tweens:Create(motion,TweenInfo.new(state.input and 0.1 or 0.18,Enum.EasingStyle.Quint,Enum.EasingDirection.Out),{Scale=target})
                state.tween:Play()
            end
            state.update=update
            motion:GetPropertyChangedSignal('Scale'):Connect(center)
            button:GetPropertyChangedSignal('Position'):Connect(function()
                if not state.writing and button.Position~=state.lastPosition then state.base=button.Position;center() end
            end)
            button:GetPropertyChangedSignal('Size'):Connect(center)
            button:GetPropertyChangedSignal('AnchorPoint'):Connect(center)
            button:GetPropertyChangedSignal('Active'):Connect(update)
            button:GetPropertyChangedSignal('Selectable'):Connect(update)
            button.MouseEnter:Connect(function()
                if Input:GetLastInputType()==Enum.UserInputType.Touch then return end
                state.hover=true;update()
            end)
            button.MouseLeave:Connect(function() state.hover=false;update() end)
            button.SelectionGained:Connect(function() state.hover=true;update() end)
            button.SelectionLost:Connect(function() state.hover=false;update() end)
            button.InputBegan:Connect(function(input)
                if not enabled() then return end
                if input.UserInputType==Enum.UserInputType.MouseButton1 or input.UserInputType==Enum.UserInputType.Touch then
                    if input.UserInputType==Enum.UserInputType.Touch then state.hover=false end
                    state.input=input;update()
                end
            end)
            button.Destroying:Connect(function()
                state.alive=false
                if state.tween then state.tween:Cancel() end
                states[button]=nil
            end)
        end
        local release=Input.InputEnded:Connect(function(input)
            for _,state in pairs(states) do
                if state.input and (state.input==input or state.input.UserInputType==Enum.UserInputType.MouseButton1 and input.UserInputType==Enum.UserInputType.MouseButton1) then
                    state.input=nil;state.update()
                end
            end
        end)
        for _,button in ipairs(panel:GetDescendants()) do attachButtonMotion(button) end
        local added=panel.DescendantAdded:Connect(function(button)
            if button:IsA('TextButton') or button:IsA('ImageButton') then
                task.defer(function() if active and button.Parent then attachButtonMotion(button) end end)
            end
        end)
        local hidden=panel:GetPropertyChangedSignal('Visible'):Connect(function()
            if panel.Visible then return end
            for _,state in pairs(states) do state.input=nil;state.hover=false;state.update() end
        end)
        D.gui.Destroying:Connect(function()
            release:Disconnect();added:Disconnect();hidden:Disconnect()
            for _,state in pairs(states) do
                state.alive=false;if state.tween then state.tween:Cancel() end
            end
            table.clear(states)
        end)
    end

    do
        local Tweens=game:GetService('TweenService')
        local hovered,moving,scheduled=false,false,false
        local lastMovement=0
        local tween
        local function paint()
            if tween then tween:Cancel() end
            local highlighted=hovered or moving
            tween=Tweens:Create(list,TweenInfo.new(0.14,Enum.EasingStyle.Quad,Enum.EasingDirection.Out),{
                ScrollBarThickness=highlighted and 9 or 6,
                ScrollBarImageColor3=highlighted and Color3.fromRGB(216,200,250) or Color3.fromRGB(167,139,250),
                ScrollBarImageTransparency=highlighted and 0 or 0.18
            })
            tween:Play()
        end
        local function idle()
            if not active or not list.Parent then scheduled=false;return end
            if os.clock()-lastMovement<0.22 then task.delay(0.12,idle);return end
            scheduled=false;moving=false;paint()
        end
        local enter=list.MouseEnter:Connect(function()
            if Input:GetLastInputType()==Enum.UserInputType.Touch then return end
            hovered=true;paint()
        end)
        local leave=list.MouseLeave:Connect(function() hovered=false;paint() end)
        local scrolled=list:GetPropertyChangedSignal('CanvasPosition'):Connect(function()
            lastMovement=os.clock()
            if not moving then moving=true;paint() end
            if not scheduled then scheduled=true;task.delay(0.24,idle) end
        end)
        local hidden=panel:GetPropertyChangedSignal('Visible'):Connect(function()
            if not panel.Visible then hovered=false;moving=false;paint() end
        end)
        D.gui.Destroying:Connect(function()
            enter:Disconnect();leave:Disconnect();scrolled:Disconnect();hidden:Disconnect()
            if tween then tween:Cancel() end
        end)
        paint()
    end

    fitFinder()
    panel.Visible=true
    local failed=Teleports.TeleportInitFailed:Connect(function(who,result,message,_,options)
        if who==D.player then
            local instance=options and options.ServerInstanceId
            local run=D.randomRun
            if run and run.target and (not instance or instance=='' or instance==run.target) then
                D.handleRandomFailure(run,run.target,result,message)
                return
            end
            local attempt=D.lastTeleportAttempt
            if not randomBusy then D.testReloadQueued=false end
            if attempt and os.clock()<attempt.failureDeadline and (instance==attempt.jobId or (not instance or instance=='') and not randomBusy and not attempt.replacedPending) then
                D.lastTeleportAttempt=nil
                if D.isFullFailure(result,message) then D.noteFull(attempt.entry) end
                D.finishJoin(attempt);queueRender()
                D.joinNotice('Roblox: '..tostring(message))
            elseif not attempt and not randomBusy then joining=false end
            queryStatus='Join failed: '..tostring(message)
        end
    end)
    D.gui.Destroying:Connect(function() active=false; failed:Disconnect();if localHighlight then localHighlight:Destroy() end end)
    function D.feedRefreshInterval(now)
        return viewerCode=='' and now<(D.feedPressureUntil or 0) and 5 or 3
    end
    function D.recordFeedRead(started,finished,loaded,jitter)
        if viewerCode~='' then return end
        if not loaded or D.feedPressureHint or finished-started>=0.8 then
            D.feedPressureUntil=finished+20+5*jitter
        end
        if not loaded then
            D.feedReadRetryAt=math.max(D.feedReadRetryAt or 0,finished+5+jitter)
        end
    end
    task.spawn(function()
        local random=Random.new()
        task.wait(random:NextNumber(0,5))
        while active do
            local started=os.clock()
            if (featureConfig or publicBroadcastConfig and viewerCode=='') and not refreshing and
                (not PREMIUM_EDITION or viewerCode~='') and started-feedAt>=D.feedRefreshInterval(started) and started>=(D.feedReadRetryAt or 0) then
                local ok,loaded,message=pcall(refresh)
                D.recordFeedRead(started,os.clock(),ok and loaded==true,random:NextNumber())
                if not ok or not loaded then
                    queryStatus='Finder: '..tostring(ok and message or loaded)
                    D.gui:SetAttribute('S2RFeedStatus',queryStatus)
                else
                    D.gui:SetAttribute('S2RFeedStatus','Updated')
                end
            end
            task.wait(0.25)
        end
    end)
    task.spawn(function()
        local lastReport=os.clock()-broadcastInterval+Random.new():NextNumber(0,broadcastInterval)
        while active do
            local ok,err=pcall(function()
                if networkBusy then return end
                if (not publicBroadcastConfig or os.clock()-configAt>60) and os.clock()>=(D.primaryConfigRetry or 0) then
                    D.primaryConfigRetry=os.clock()+5;loadConfig()
                end
                if publicBroadcastConfig and os.clock()>=(D.primaryReportRetry or 0) and os.clock()-lastReport>=broadcastInterval then
                    D.primaryReportRetry=os.clock()+3
                    local success,message=report(3)
                    if success then lastReport=os.clock() end
                    reportStatus=message
                    if not success then warn('S2R broadcast: '..tostring(message)) end
                end
            end)
            if not ok then reportStatus='BCAST: '..tostring(err);queryStatus=tostring(err);warn('S2R broadcast: '..tostring(err)) end
            task.wait(1)
        end
    end)
    task.spawn(function()
        while active do
            status.Text=PREMIUM_EDITION and (tostring(reportStatus)..'\n'..tostring(queryStatus)) or (joining and 'Joining server…' or tostring(reportStatus))
            local cycle=cycleInfo()
            if cycle then
                local seconds=math.max(0,math.ceil(cycle.remaining))
                resetTimer.Text=cycle.running and string.format('RESET %02d:%02d',math.floor(seconds/60),seconds%60) or 'RESET PAUSED'
                resetTimer.TextColor3=cycle.running and seconds<=60 and Color3.fromRGB(255,85,85) or cycle.running and seconds<=150 and Color3.fromRGB(255,215,65) or Color3.fromRGB(230,245,255)
            else
                resetTimer.Text='RESET --:--'
                resetTimer.TextColor3=Color3.fromRGB(230,245,255)
            end
            sharingNotice.Visible=false
            local ok=pcall(render)
            if not ok then queryStatus='Unable to display finder feed' end
            updateSpawnAges(cycle)
            task.wait(1)
        end
    end)
end


local function run()
    local EggState=module('Client.EggState')
    local Assets=module('Data.Assets')
    local States=module('Shared.Types.AreaEggs').States
    local mutations,eggRecords
    pcall(function() mutations=module('Shared.Modules.Mutations') end)
    pcall(function() eggRecords=module('Shared.Util.EggRecords') end)
    assert(type(EggState.ReadFieldEggs)=='function','ReadFieldEggs unavailable')
    assert(type(Assets.Directory)=='table' and States and States.Slot~=nil,'Game schema changed')
    local latestEntries={}
    local latestMetadata=nil
    local scanCycle
    pcall(function() scanCycle=module('Shared.Util.AreaEggCycle') end)
    local function parseValue(text)
        local amount,suffix=tostring(text):gsub(',',''):match('^%s*%$?%s*(%d+%.?%d*)%s*(%a*)%s*$')
        local powers={['']=1,k=1e3,m=1e6,b=1e9,t=1e12,qa=1e15,qi=1e18}
        local factor=suffix and powers[suffix:lower()]
        if not amount or not factor then return nil end
        local value=tonumber(amount)*factor
        return valid(value) and value or nil
    end
    local function newCycleSlots()
        local cycle,slots,count=nil,{},0
        local seenCycle,previousCycle={},{}
        return function(entries,states,resetAt)
            if resetAt and resetAt~=cycle then
                if cycle then previousCycle,seenCycle=seenCycle,{} end
                cycle,slots,count=resetAt,{},0
            end
            local ranked,byUid,stateByUid={},{},{}
            for _,state in ipairs(states) do stateByUid[state.uid]=state.state;seenCycle[state.uid]=true end
            for _,entry in ipairs(entries) do
                local uid=tostring(entry.uid)
                byUid[uid]=entry
                if entry.rate and entry.rate>=MIN_BROADCAST_RATE and stateByUid[uid]=='Slot' and not previousCycle[uid] then ranked[#ranked+1]=entry end
            end
            table.sort(ranked,function(a,b)
                if a.rate~=b.rate then return a.rate>b.rate end
                return tostring(a.uid)<tostring(b.uid)
            end)
            for _,entry in ipairs(ranked) do
                if count==4 then break end
                local uid=tostring(entry.uid)
                if not slots[uid] then slots[uid]={entry=entry,missing=0};count+=1 end
            end
            local reports,tracked,taken={},{},{}
            for uid,slot in pairs(slots) do
                local state=stateByUid[uid]
                if state=='Claimed' then slot.taken=true
                elseif state then slot.missing=0
                else slot.missing+=1;if slot.missing>=2 then slot.taken=true end end
                if byUid[uid] and byUid[uid].rate and not slot.taken then slot.entry=byUid[uid] end
                if slot.taken then
                    tracked[#tracked+1]={uid=uid,state='Claimed'}
                    taken[#taken+1]=slot.entry
                elseif state then
                    tracked[#tracked+1]={uid=uid,state=state}
                    if byUid[uid] then reports[#reports+1]=byUid[uid] end
                else
                    tracked[#tracked+1]={uid=uid,state='Unknown'}
                end
            end
            return reports,tracked,taken
        end
    end
    local selectCycleSlots=newCycleSlots()
    local reportEntries,takenEntries={},{}
    local lastScan=0
    createFinder({gui=gui,localPanel={Visible=false},player=player,make=make,label=label,entries=function() return os.clock()-lastScan<10 and latestEntries or {} end,metadata=function() return latestMetadata end,reportEntries=function() return reportEntries end,takenEntries=function() return takenEntries end,ready=function() return lastScan>0 and os.clock()-lastScan<10 end,parseValue=parseValue,money=money,stopFarm=function() end})
    while alive do
        local ok,err=pcall(function()
            local scanStartedClock=os.clock()
            local snapshot=EggState.ReadFieldEggs()
            assert(type(snapshot)=='table' and type(snapshot.Records)=='table','Field snapshot unavailable')
            local eggs={}
            local fieldStates={}
            local allStates={}
            local scanAt=workspace:GetServerTimeNow()*1000
            local resetAt
            if scanCycle then pcall(function() if scanCycle.IsRunning() then resetAt=scanCycle.NextResetTime(scanAt/1000)*1000 end end) end
            for recordKey,record in pairs(snapshot.Records) do
                local stateUid=tostring(record.Uid or recordKey)
                allStates[stateUid]=record.State
                local area=tostring(record.AreaId):lower():gsub("[^%a]", "")
                local broadcastEligible=area~="forest" and area~="lake" and area~="desert" and area~="volcano" and area~="volcanox"
                local asset=Assets.Directory[record.AssetCategory]
                if excludedFinderEgg(record.AssetCategory) or excludedFinderEgg(asset and asset.DisplayName) then continue end
                local rarity=asset and asset.Rarity
                if not rarity or not finderRarityRank(rarity.DisplayName or rarity._id) then continue end
                fieldStates[#fieldStates+1]={uid=tostring(record.Uid or recordKey),state=record.State}
                if record.State==States.Slot or record.State==States.Carried or record.State==States.Dropped or record.State==States.GuardCarried then
                    local uid=record.Uid or recordKey
                    local model=modelFor(uid)
                    local scale=numberField(record,{'AssetScale'})
                    local weight
                    if eggRecords and type(eggRecords.WeightKg)=='function' then
                        local good,result=pcall(eggRecords.WeightKg,record)
                        if good and valid(result) then weight=result end
                    end
                    local rate=displayedRate(model)
                    local estimated=false
                    if not rate then
                        rate=computedRate(asset.EarningRate,scale,record.Mutations or {},mutations)
                        estimated=rate~=nil
                    end
                    local traits,traitsKnown=readTraitNames(record)
                    table.insert(eggs,{key='field:'..tostring(uid),uid=uid,broadcastEligible=broadcastEligible,traitsKnown=traitsKnown,category=record.AssetCategory,areaKey=record.AreaId,worldPos=typeof(record.BottomCFrame)=='CFrame' and record.BottomCFrame.Position or nil,area=tostring(record.AreaId)..' | Mut: '..(#traits>0 and table.concat(traits,', ') or traitsKnown and 'None' or 'UNKNOWN'),model=model,icon=asset.Icon,name=asset.DisplayName or record.AssetCategory or 'Unknown',rarity=rarity.DisplayName or rarity._id or 'Unknown',tier=finderRarityRank(rarity.DisplayName or rarity._id),color=typeof(rarity.Color)=='Color3' and rarity.Color or Color3.new(1,1,1),scale=scale,weight=weight,rate=rate,estimated=estimated})
                end
            end
            for _,entry in ipairs(eggs) do
                entry.mutationText=tostring(entry.area or ''):match('Mut:%s*(.*)') or ''
            end
            local broadcastEggs={}
            for _,egg in ipairs(eggs) do
                if egg.broadcastEligible then broadcastEggs[#broadcastEggs+1]=egg end
            end
            reportEntries,fieldStates,takenEntries=selectCycleSlots(broadcastEggs,fieldStates,resetAt)
            for _,record in ipairs(fieldStates) do allStates[record.uid]=record.state end
            local completeStates={}
            for uid,state in pairs(allStates) do completeStates[#completeStates+1]={uid=uid,state=state} end
            latestEntries=eggs
            latestMetadata={states=completeStates,resetAt=resetAt,scanAt=scanAt,scanClock=scanStartedClock}
            lastScan=os.clock()
        end)
        if not ok then warn('NYX Finder scan:',err) end
        task.wait(2)
    end
end
 task.spawn(function()
    local ok,err=pcall(run)
    if not ok then warn('NYX Finder startup:',err) end
end)
