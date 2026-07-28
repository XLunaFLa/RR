--[[
    ============================================================================
    AUTO RAID STANDALONE (TANPA UI) - by FLa
    Port logika dari 13_PREM_MergeGems.lua (panel AUTOMATION -> AUTO RAID)
    ============================================================================

    KONFIGURASI SESUAI PERMINTAAN:
    1) Pick Mode utama : RAID LIST ENTRY
         - Map   : 20
         - Rank  : E / D / C / B / A
    2) Fallback (kalau List Entry di atas tidak match sama sekali) : MANUAL
         - Map   : 16 / 17 / 18 / 19
         - Rank  : E / D / C / B / A / S / SS / G / N / M / M+
    3) AUTO BOSS KILL : ON
         - Delay TP ke Boss : 1 detik
    4) Startup delay 10 detik sebelum loop mulai jalan
         (buffer aman untuk Auto-Execute, supaya remote/workspace sempat
         ready dulu setelah character baru spawn -- BUKAN auto-stop,
         setelah 10 detik loop RAID akan jalan terus menerus).

    Cara pakai: taruh script ini di folder Auto Execute executor kamu.
    ============================================================================
--]]

--  SERVICES 
local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local LP                = Players.LocalPlayer

local PG = LP:WaitForChild("PlayerGui", 30)
local Remotes = ReplicatedStorage:WaitForChild("Remotes", 30)
if not Remotes then
    warn("[AutoRaid] Folder 'Remotes' tidak ditemukan, script berhenti.")
    return
end

--  GLOBAL RINGAN YANG DIBUTUHKAN 
HERO_GUIDS = HERO_GUIDS or {}
MY_USER_ID = MY_USER_ID or LP.UserId

local function IsValidUUID(str)
    if type(str) ~= "string" then return false end
    return str:match("^%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x$") ~= nil
end

--  REMOTES 
local RE = {}
RE.CreateRaidTeam        = Remotes:FindFirstChild("CreateRaidTeam")
RE.StartChallengeRaidMap = Remotes:FindFirstChild("StartChallengeRaidMap")
RE.UseRaidItem           = Remotes:FindFirstChild("UseRaidItem")
RE.CollectItem           = Remotes:FindFirstChild("CollectItem")
RE.ExtraReward           = Remotes:FindFirstChild("ExtraReward")
RE.StartTp               = Remotes:FindFirstChild("StartLocalPlayerTeleport")
RE.Click                 = Remotes:FindFirstChild("ClickEnemy")
RE.Atk                   = Remotes:FindFirstChild("PlayerClickAttackSkill")
RE.HeroUseSkill          = Remotes:FindFirstChild("HeroUseSkill")
RE.UnEquipHero           = Remotes:FindFirstChild("UnequipAllHero")
RE.EquipBestHero         = Remotes:FindFirstChild("AutoEquipBestHero")
RE.EquipHeroWithData     = Remotes:FindFirstChild("EquipHeroWithData")
RE.HeroStand             = Remotes:FindFirstChild("HeroStandTo")
RE.QuitRaidsMap          = Remotes:FindFirstChild("QuitRaidsMap")
local RE_ChallengeSuccess = Remotes:FindFirstChild("ChallengeRaidsSuccess")
local RE_ChallengeFail    = Remotes:FindFirstChild("ChallengeRaidsFail")
local RE_UpdateRaidInfo   = Remotes:FindFirstChild("UpdateRaidInfo")
local RE_EnterRaidsUpdate = Remotes:FindFirstChild("EnterRaidsUpdateInfo")

--  KONSTANTA 
local GRADE_RANK = {
    ["E"]=1,["D"]=2,["C"]=3,["B"]=4,["A"]=5,["S"]=6,["SS"]=7,
    ["G"]=8,["N"]=9,["M"]=10,["M+"]=11,["M++"]=12,["XM"]=15,["ULT"]=17,["GOD"]=18,
}
local RAID_MAP_INFO = {
    [1]={instance="Map1",rootPart="4025"},[2]={instance="Map2",rootPart="4050"},
    [3]={instance="Map3",rootPart="4025"},[4]={instance="Map4",rootPart="4050"},
    [5]={instance="Map5",rootPart="4050"},[6]={instance="Map6",rootPart="4044"},
    [7]={instance="Map7",rootPart="4050"},[8]={instance="Map8",rootPart="4050"},
    [9]={instance="Map9",rootPart="4050"},[10]={instance="Map10",rootPart="4050"},
    [11]={instance="Map11",rootPart="4050"},[12]={instance="Map12",rootPart="4050"},
    [13]={instance="Map13",rootPart="4050"},[14]={instance="Map14",rootPart="4050"},
    [15]={instance="Map15",rootPart="4050"},[16]={instance="Map16",rootPart="4050"},
    [17]={instance="Map17",rootPart="4050"},[18]={instance="Map18",rootPart="4050"},
    [19]={instance="Map19",rootPart="4050"},[20]={instance="Map20",rootPart="4050"},
}
local BOSS_NAME_BY_MAP = { [1] = "Goblin King", [3] = "Igris" }
local RAID_CONFIG_GRADE
do
    local _GRADE_IDX  = {"E","D","C","B","A","S","SS","G","N","M","M+","M++","XM","ULT","GOD"}
    local _GRADE_RAID = {"D","B","S","SS","G","N","M+","M++","XM","ULT"}
    RAID_CONFIG_GRADE = setmetatable({},{
        __index = function(_, raidId)
            if type(raidId) ~= "number" then return nil end
            if raidId == 937101 then return nil end
            if raidId >= 935001 then return _GRADE_IDX[raidId%100] or "?" end
            if raidId >= 930001 then return _GRADE_RAID[(raidId-930001)%10+1] or "?" end
            return nil
        end
    })
end

--  KONFIGURASI SESUAI PERMINTAAN USER 
-- 1) Raid List Entry: Map 20, Rank E/D/C/B/A
local LIST_ENTRY = {
    maps  = { [20] = true },
    ranks = { E = true, D = true, C = true, B = true, A = true },
}
-- 2) Fallback Manual: Map 16/17/18/19, Rank E/D/C/B/A/S/SS/G/N/M/M+
local MANUAL_FALLBACK = {
    maps  = { [16] = true, [17] = true, [18] = true, [19] = true },
    ranks = { E=true, D=true, C=true, B=true, A=true, S=true, SS=true, G=true, N=true, M=true, ["M+"]=true },
}
-- 3) Auto Boss Kill
local AUTO_KILL_BOSS = true
local BOSS_TP_DELAY  = 1 -- detik
-- 4) Startup delay (buffer Auto Execute)
local STARTUP_DELAY  = 10 -- detik

--  STATE RUNTIME 
local RAID_LIVE    = {}
local RAID_ID_LIST = {}
local _defaultRRIdx = 0
local RAID = {
    running=false, inMap=false, raidId=nil, raidMapId=nil, serverMapId=nil,
    fromMapId=nil, slotIndex=2, sukses=0, collected=0,
}

local function Log(msg)
    print("[AutoRaid] " .. tostring(msg))
end

--  GetCurrentMapId 
local function GetCurrentMapId()
    local ok, wm = pcall(function()
        return workspace:GetAttribute("MapId") or workspace:GetAttribute("mapId") or workspace:GetAttribute("CurrentMapId")
    end)
    return (ok and type(wm) == "number") and wm or nil
end

--  GetRaidMapNum (deteksi nomor map dari instance workspace.Maps) 
local function GetRaidMapNum(mapId)
    local mf = workspace:FindFirstChild("Maps")
    if mf then
        for i = 1, 20 do
            if mf:FindFirstChild("Map" .. i) then return i end
        end
    end
    if type(mapId) ~= "number" then return nil end
    if mapId >= 50101 and mapId <= 50120 then return mapId - 50100 end
    if mapId >= 50001 and mapId <= 50020 then return mapId - 50000 end
    return nil
end

local function GetBossRootPartCFrame(mapNum)
    local info = RAID_MAP_INFO[mapNum]; if not info then return nil end
    local mf = workspace:FindFirstChild("Maps"); if not mf then return nil end
    local mapFolder = mf:FindFirstChild(info.instance); if not mapFolder then return nil end
    local mapChild = mapFolder:FindFirstChild("Map"); if not mapChild then return nil end
    local re = mapChild:FindFirstChild("RaidsEnemys"); if not re then return nil end
    local rp = re:FindFirstChild(info.rootPart); if not rp then return nil end
    return rp.CFrame
end

--  GetBestGrade (ambil rank/grade raid entry yang sedang live) 
local function GetBestGrade(mapNum)
    local mapId = 50000 + mapNum
    for _, ent in pairs(RAID_LIVE) do
        if ent.mapId == mapId and ent.raidId and ent.raidId > 0 then
            local g = RAID_CONFIG_GRADE[ent.raidId]
            if g and g ~= "?" then return g end
        end
    end
    for _, ent in pairs(RAID_LIVE) do
        if ent.mapId == mapId and ent.grade and ent.grade ~= "?" then
            return ent.grade
        end
    end
    return nil
end

--  REBUILD RAID LIST dari RAID_LIVE 
local function RebuildRaidList()
    local sorted = {}
    for _, e in pairs(RAID_LIVE) do
        local ridAbs = e.raidId and (e.raidId < 0 and math.abs(e.raidId) or e.raidId) or 0
        local mn = e.mapId and (e.mapId - 50000) or 0
        if ridAbs ~= 937101 and ridAbs < 935001 and mn >= 1 and mn <= 20 then
            table.insert(sorted, e)
        end
    end
    table.sort(sorted, function(a, b) return (a.mapId or 0) < (b.mapId or 0) end)
    RAID_ID_LIST = {}
    for _, e in ipairs(sorted) do
        table.insert(RAID_ID_LIST, { id = e.raidId, mapId = e.mapId, rank = e.rank })
    end
end

--  WORKSPACE WATCHER: RE1001/RE1002 (deteksi lobby raid via child ChildAdded) 
local function _parseRaidEnterName(name)
    local n = name:match("^RaidEnter(%d+)$")
    return n and tonumber(n) or nil
end

local function _onRaidChildAdded(child, slotName)
    local mapNum = _parseRaidEnterName(child.Name)
    if not mapNum or mapNum < 1 or mapNum > 20 then return end
    local mapId = 50000 + mapNum
    for _, ent in pairs(RAID_LIVE) do
        if ent.mapId == mapId and not ent._tempEntry then return end
    end
    local tempKey = -(mapId)
    RAID_LIVE[tempKey] = {
        raidId = tempKey, mapId = mapId, spawnName = slotName or "RE1001",
        rank = 0, grade = "?", endTime = nil, _tempEntry = true,
    }
    Log("[DIAG] Watcher deteksi RaidEnter" .. mapNum .. " (Map " .. mapNum .. ") via " .. tostring(slotName))
    RebuildRaidList()
end

local function _onRaidChildRemoved(child)
    local mapNum = _parseRaidEnterName(child.Name); if not mapNum then return end
    local mapId = 50000 + mapNum; local changed = false
    for rid, ent in pairs(RAID_LIVE) do
        if ent.mapId == mapId then RAID_LIVE[rid] = nil; changed = true end
    end
    if changed then RebuildRaidList() end
end

local function _watchRaidSlot(reFolder)
    if not reFolder then return end
    for _, child in ipairs(reFolder:GetChildren()) do _onRaidChildAdded(child, reFolder.Name) end
    reFolder.ChildAdded:Connect(function(child) _onRaidChildAdded(child, reFolder.Name) end)
    reFolder.ChildRemoved:Connect(function(child) _onRaidChildRemoved(child) end)
end

task.spawn(function()
    local ok, mapsF = pcall(function() return workspace:WaitForChild("Maps", 15) end)
    if not ok or not mapsF then
        Log("[DIAG] workspace.Maps TIDAK ditemukan dalam 15 detik - watcher raid tidak aktif!")
        return
    end
    local ok2, mapF = pcall(function() return mapsF:WaitForChild("Map", 10) end)
    if not ok2 or not mapF then
        Log("[DIAG] workspace.Maps.Map TIDAK ditemukan dalam 10 detik - watcher raid tidak aktif!")
        return
    end
    local ok3, reF = pcall(function() return mapF:WaitForChild("RaidEnter", 10) end)
    if not ok3 or not reF then
        Log("[DIAG] workspace.Maps.Map.RaidEnter TIDAK ditemukan dalam 10 detik - watcher raid tidak aktif!")
        return
    end
    local re1 = reF:WaitForChild("RE1001", 5)
    local re2 = reF:WaitForChild("RE1002", 5)
    if not re1 and not re2 then
        Log("[DIAG] RE1001/RE1002 tidak ditemukan di RaidEnter - cek apakah nama folder slot berubah.")
    else
        Log("[DIAG] Watcher raid aktif (RE1001=" .. tostring(re1 ~= nil) .. ", RE1002=" .. tostring(re2 ~= nil) .. ")")
    end
    _watchRaidSlot(re1); _watchRaidSlot(re2)
end)

--  LISTENER: UpdateRaidInfo / EnterRaidsUpdateInfo (data raidId + grade dari server) 
local function ConnectRaidListeners()
    if RE_UpdateRaidInfo then
        RE_UpdateRaidInfo.OnClientEvent:Connect(function(data)
            if type(data) ~= "table" then return end
            local raidInfos = data.raidInfos
            if type(raidInfos) ~= "table" then return end
            Log("[DIAG] UpdateRaidInfo event masuk (" .. #raidInfos .. " raidInfos)")
            for _, info in ipairs(raidInfos) do
                if type(info) == "table" and info.raidId then
                    local mapId = info.mapId or (RAID_LIVE[info.raidId] and RAID_LIVE[info.raidId].mapId)
                    if mapId then
                        RAID_LIVE[info.raidId] = {
                            raidId = info.raidId, mapId = mapId,
                            grade = RAID_CONFIG_GRADE[info.raidId] or info.grade or "?",
                            endTime = info.endTime,
                        }
                    end
                end
            end
            RebuildRaidList()
        end)
    end
    if RE_EnterRaidsUpdate then
        RE_EnterRaidsUpdate.OnClientEvent:Connect(function(data)
            if type(data) ~= "table" then return end
            RebuildRaidList()
        end)
    end
end
ConnectRaidListeners()

--  RESOLVE ENTRY: RAID LIST ENTRY (Map 20, Rank E-A) 
local function ResolveEntryFromList()
    if #RAID_ID_LIST == 0 then return nil end
    local matched = {}
    for _, r in ipairs(RAID_ID_LIST) do
        local mn = r.mapId - 50000
        if LIST_ENTRY.maps[mn] then
            local grade = GetBestGrade(mn)
            if grade and LIST_ENTRY.ranks[grade] then
                table.insert(matched, r)
            end
        end
    end
    if #matched == 0 then return nil end
    table.sort(matched, function(a, b) return a.mapId < b.mapId end)
    return matched[1]
end

--  RESOLVE ENTRY: FALLBACK MANUAL (Map 16-19, Rank E/D/C/B/A/S/SS/G/N/M/M+) 
local function ResolveEntryManualFallback()
    if #RAID_ID_LIST == 0 then return nil end
    local matched = {}
    for _, r in ipairs(RAID_ID_LIST) do
        local mn = r.mapId - 50000
        if MANUAL_FALLBACK.maps[mn] then
            local grade = GetBestGrade(mn)
            if grade and MANUAL_FALLBACK.ranks[grade] then
                table.insert(matched, r)
            end
        end
    end
    if #matched == 0 then return nil end
    -- Sort dari Rank tertinggi ke terendah (biar prioritas rank terbaik dulu)
    table.sort(matched, function(a, b)
        local ga = GetBestGrade(a.mapId - 50000) or "?"
        local gb = GetBestGrade(b.mapId - 50000) or "?"
        local ra = GRADE_RANK[ga] or 0
        local rb = GRADE_RANK[gb] or 0
        if ra == rb then return a.mapId < b.mapId end
        return ra > rb
    end)
    return matched[1]
end

local function ResolveEntry()
    -- Tahap 1: Raid List Entry (Map 20 E-A)
    local listResult = ResolveEntryFromList()
    if listResult then return listResult end
    -- Tahap 2: Fallback Manual (Map 16-19 semua rank yang diizinkan)
    return ResolveEntryManualFallback()
end

--  DIAGNOSTIK: dump isi RAID_ID_LIST + grade yang terbaca (dipanggil tiap N detik saat waiting) 
local function DumpRaidListDiagnostic()
    if #RAID_ID_LIST == 0 then
        Log("[DIAG] RAID_ID_LIST kosong - belum ada raid entry terdeteksi sama sekali di RAID_LIVE.")
        Log("[DIAG] Cek: apakah workspace.Maps.Map.RaidEnter.RE1001/RE1002 ada isinya? Apakah remote UpdateRaidInfo / EnterRaidsUpdateInfo ke-fire?")
        return
    end
    Log("[DIAG] Isi RAID_ID_LIST saat ini (" .. #RAID_ID_LIST .. " entri):")
    for _, r in ipairs(RAID_ID_LIST) do
        local mn = r.mapId - 50000
        local grade = GetBestGrade(mn)
        local inList   = LIST_ENTRY.maps[mn] and "YA" or "tidak"
        local inManual = MANUAL_FALLBACK.maps[mn] and "YA" or "tidak"
        Log(string.format(
            "[DIAG]  Map %d | raidId=%s | grade=%s | target List Entry=%s | target Manual Fallback=%s",
            mn, tostring(r.id), tostring(grade or "nil/?"), inList, inManual
        ))
    end
end

local RE_UpdateRaidInfoName   = RE_UpdateRaidInfo and RE_UpdateRaidInfo.Name or "TIDAK DITEMUKAN"
local RE_EnterRaidsUpdateName = RE_EnterRaidsUpdate and RE_EnterRaidsUpdate.Name or "TIDAK DITEMUKAN"
Log("[DIAG] Remote UpdateRaidInfo: " .. RE_UpdateRaidInfoName)
Log("[DIAG] Remote EnterRaidsUpdateInfo: " .. RE_EnterRaidsUpdateName)

--  SAFE REEQUIP HERO SETELAH TELEPORT 
local _SafeReequipBusy = false
local function SafeReequipAfterTeleport()
    if _SafeReequipBusy then return end
    _SafeReequipBusy = true
    task.spawn(function()
        pcall(function()
            if RE.UnEquipHero then RE.UnEquipHero:FireServer() end
            task.wait(0.4)
            if RE.EquipBestHero then RE.EquipBestHero:FireServer() end
        end)
        _SafeReequipBusy = false
    end)
end

--  GET RAID ENEMIES (scan folder musuh di workspace) 
local function GetRaidEnemies()
    local list = {}
    local seen = {}
    local function addEnemy(e)
        if not e:IsA("Model") then return end
        local g = e:GetAttribute("EnemyGuid") or e:GetAttribute("BossGuid") or e:GetAttribute("Guid") or e:GetAttribute("GUID")
        if not g or seen[g] then return end
        local hrp = e:FindFirstChild("HumanoidRootPart") or e.PrimaryPart
        local hum = e:FindFirstChildOfClass("Humanoid")
        if not (hrp and hum) then return end
        if hum.Health <= 0 then return end
        seen[g] = true
        table.insert(list, { guid = g, hrp = hrp, model = e })
    end
    for _, fname in ipairs({"Bosses","Boss","RaidBoss","Enemys","Enemy","Enemies","RaidEnemys","Monsters","Monster"}) do
        local folder = workspace:FindFirstChild(fname)
        if folder then
            for _, e in ipairs(folder:GetChildren()) do addEnemy(e) end
        end
    end
    return list
end

--  HERO ATTACK THREAD PER-GUID 
local _heroAtkThreads = {}
local function IsEnemyGuidValid(g)
    if not g then return false end
    for _, e in ipairs(GetRaidEnemies()) do
        if e.guid == g then return true end
    end
    return false
end

local function EnsureHeroAtkThreadFor(g)
    if not g then return end
    if _heroAtkThreads[g] and _heroAtkThreads[g].running then return end
    local handle = { running = true }
    _heroAtkThreads[g] = handle
    task.spawn(function()
        while handle.running do
            if #HERO_GUIDS > 0 and IsEnemyGuidValid(g) and RE.HeroUseSkill then
                for _, hGuid in ipairs(HERO_GUIDS) do
                    pcall(function() RE.HeroUseSkill:FireServer({heroGuid=hGuid, attackType=1, userId=MY_USER_ID, enemyGuid=g}) end)
                    task.wait(0.02)
                    pcall(function() RE.HeroUseSkill:FireServer({heroGuid=hGuid, attackType=2, userId=MY_USER_ID, enemyGuid=g}) end)
                    task.wait(0.02)
                    pcall(function() RE.HeroUseSkill:FireServer({heroGuid=hGuid, attackType=3, userId=MY_USER_ID, enemyGuid=g}) end)
                end
            end
            task.wait(0.1)
            if not IsEnemyGuidValid(g) then handle.running = false end
        end
        _heroAtkThreads[g] = nil
    end)
end

--  COLLECT LOOT / REWARD DI DALAM RAID 
local function RaidCollectAll()
    local collected = {}
    local function collectFolder(folder)
        if not folder then return end
        for _, obj in ipairs(folder:GetChildren()) do
            local guid = obj:GetAttribute("GUID") or obj:GetAttribute("Guid") or obj:GetAttribute("guid") or obj:GetAttribute("ItemGuid")
            if guid and not collected[guid] then
                collected[guid] = true
                if RE.CollectItem then pcall(function() RE.CollectItem:InvokeServer(guid) end) end
                if RE.ExtraReward then pcall(function() RE.ExtraReward:FireServer({isSell=true, guid=guid}) end) end
                task.wait(0.05)
            end
        end
    end
    for _, folderName in ipairs({"Golds","Items","Drops","Rewards","Loot","Chests","RewardItems","DropItems"}) do
        collectFolder(workspace:FindFirstChild(folderName))
    end
    task.wait(1.5)
    for _, folderName in ipairs({"Golds","Items","Drops","Rewards","Loot","Chests","RewardItems","DropItems"}) do
        collectFolder(workspace:FindFirstChild(folderName))
    end
end

--  MAIN RAID LOOP 
local function StartRaidLoop()
    RAID.running = true
    task.spawn(function()
        while RAID.running do
            repeat
                -- Prune entri raid yang sudah expired
                local now0 = os.time()
                for rid, ent in pairs(RAID_LIVE) do
                    if ent.endTime and ent.endTime < (now0 - 10) then RAID_LIVE[rid] = nil end
                end
                RebuildRaidList()

                local raidEntry = ResolveEntry()
                local _waitTick = 0
                while RAID.running and not raidEntry do
                    task.wait(1)
                    _waitTick = _waitTick + 1
                    if _waitTick % 5 == 0 then
                        Log("Masih menunggu raid match... (sudah " .. _waitTick .. "s)")
                        DumpRaidListDiagnostic()
                    end
                    raidEntry = ResolveEntry()
                end
                if not RAID.running then break end

                -- STEP 1: masuk raid map
                Log("Match ditemukan -> Map " .. (raidEntry.mapId - 50000) .. " (raidId=" .. tostring(raidEntry.id) .. ")")
                RAID.raidId = raidEntry.id
                RAID.raidMapId = raidEntry.mapId
                RAID.inMap = true
                SafeReequipAfterTeleport()

                local targetMapId = raidEntry.mapId + 100 -- 50101-50120
                if not RAID.fromMapId then RAID.fromMapId = RAID.raidMapId end
                if RE.CreateRaidTeam then pcall(function() RE.CreateRaidTeam:InvokeServer(RAID.raidId) end) end
                task.wait(0.2)

                local _cfail = false
                local _cfConn
                if RE_ChallengeFail then
                    _cfConn = RE_ChallengeFail.OnClientEvent:Connect(function() _cfail = true end)
                end
                if RE.StartChallengeRaidMap then
                    pcall(function() RE.StartChallengeRaidMap:FireServer({mapId = targetMapId}) end)
                end
                local _w = 0
                while RAID.serverMapId == nil and _w < 5 and RAID.running and not _cfail do
                    task.wait(0.05); _w = _w + 0.05
                end
                if _cfConn then pcall(function() _cfConn:Disconnect() end) end
                if _cfail then
                    Log("Gagal masuk raid (ChallengeRaidsFail) - retry...")
                    RAID_LIVE[RAID.raidId] = nil; RebuildRaidList()
                    RAID.inMap = false
                    task.wait(1); break
                end

                -- STEP 2: tunggu masuk map
                local _tpOk = false
                local _tpWait = 0
                while not _tpOk and _tpWait < 2 and RAID.running do
                    task.wait(0.3); _tpWait = _tpWait + 0.3
                    local wMapId = GetCurrentMapId()
                    if wMapId and wMapId >= 50101 and wMapId <= 50120 then
                        RAID.serverMapId = wMapId; _tpOk = true
                    end
                    if not _tpOk and #GetRaidEnemies() > 0 then _tpOk = true end
                end
                if not _tpOk and RAID.running then
                    Log("Gagal masuk map - retry...")
                    RAID_LIVE[RAID.raidId] = nil; RebuildRaidList()
                    RAID.inMap = false; RAID.fromMapId = nil
                    task.wait(1); break
                end

                -- Equip hero ke map ini
                if #HERO_GUIDS > 0 and RE.EquipHeroWithData then
                    task.spawn(function()
                        task.wait(0.5)
                        for _, hGuid in ipairs(HERO_GUIDS) do
                            pcall(function() RE.EquipHeroWithData:FireServer({heroGuid = hGuid, userId = MY_USER_ID}) end)
                            task.wait(0.1)
                        end
                    end)
                end

                -- STEP 3: render delay
                local _preMapNum = GetRaidMapNum(raidEntry.mapId)
                local _renderDelay = (_preMapNum == 1) and 4 or 2
                task.wait(_renderDelay)

                -- STEP 4: AUTO BOSS KILL
                local _raidDone = false
                local _raidSuccess = false
                local connS, connF
                if RE_ChallengeSuccess then
                    connS = RE_ChallengeSuccess.OnClientEvent:Connect(function() _raidDone = true; _raidSuccess = true end)
                end
                if RE_ChallengeFail then
                    connF = RE_ChallengeFail.OnClientEvent:Connect(function() _raidDone = true end)
                end

                local _freezeConn, _frozenCFrame
                local function _step4Cleanup()
                    pcall(function()
                        local char = LP.Character
                        local hrp = char and char:FindFirstChild("HumanoidRootPart")
                        if hrp then hrp.Anchored = false end
                    end)
                    if _freezeConn then pcall(function() _freezeConn:Disconnect() end); _freezeConn = nil end
                    if connS then pcall(function() connS:Disconnect() end) end
                    if connF then pcall(function() connF:Disconnect() end) end
                end

                if AUTO_KILL_BOSS and RAID.running then
                    local _mapNumNow = GetRaidMapNum(raidEntry.mapId)
                    local _tpTargetCF = _mapNumNow and GetBossRootPartCFrame(_mapNumNow) or nil
                    local _tpTargetPos = _tpTargetCF and _tpTargetCF.Position or nil

                    if not _tpTargetPos and (_mapNumNow == 1 or _mapNumNow == 3) then
                        local _bossName = BOSS_NAME_BY_MAP[_mapNumNow]
                        local _enemysFolder = workspace:FindFirstChild("Enemys")
                        if _enemysFolder and _bossName then
                            for _, e in ipairs(_enemysFolder:GetChildren()) do
                                if e:IsA("Model") and e.Name:find(_bossName, 1, true) then
                                    local _bHrp = e:FindFirstChild("HumanoidRootPart") or e.PrimaryPart
                                    local _bHum = e:FindFirstChildOfClass("Humanoid")
                                    if _bHrp and _bHum and _bHum.Health > 0 then
                                        _tpTargetPos = _bHrp.Position; _tpTargetCF = _bHrp.CFrame
                                        break
                                    end
                                end
                            end
                        end
                    end

                    if not _tpTargetPos then
                        Log("RootPart boss tidak ditemukan - skip map ini")
                        _step4Cleanup()
                        task.wait(2)
                    else
                        -- Delay TP ke boss: 1 detik (BOSS_TP_DELAY)
                        for _ci = BOSS_TP_DELAY, 1, -1 do
                            if not RAID.running or _raidDone then break end
                            Log("TP ke Boss Map " .. tostring(_mapNumNow) .. " dalam " .. _ci .. "s...")
                            task.wait(1)
                        end

                        if RAID.running and not _raidDone then
                            _tpTargetCF = GetBossRootPartCFrame(_mapNumNow) or _tpTargetCF
                            _tpTargetPos = _tpTargetCF.Position

                            pcall(function()
                                local char = LP.Character
                                local hrp = char and char:FindFirstChild("HumanoidRootPart")
                                if hrp then hrp.CFrame = _tpTargetCF end
                            end)

                            if RE.UnEquipHero then pcall(function() RE.UnEquipHero:FireServer() end) end
                            task.wait(1)
                            if RE.EquipBestHero then pcall(function() RE.EquipBestHero:FireServer() end) end
                            task.wait(2)

                            if #HERO_GUIDS == 0 then
                                pcall(function()
                                    for _, obj in ipairs(PG:GetChildren()) do
                                        local g = obj:GetAttribute("heroGuid") or obj:GetAttribute("guid")
                                        if type(g) == "string" and IsValidUUID(g) then
                                            table.insert(HERO_GUIDS, g)
                                        end
                                    end
                                end)
                            end

                            -- Kunci posisi player di titik boss selama attack
                            pcall(function()
                                local char = LP.Character
                                local hrp = char and char:FindFirstChild("HumanoidRootPart")
                                if hrp then
                                    _frozenCFrame = _tpTargetCF
                                    hrp.Anchored = true
                                    hrp.CFrame = _frozenCFrame
                                    _freezeConn = RunService.Heartbeat:Connect(function()
                                        if not RAID.running or _raidDone then
                                            pcall(function() if hrp and hrp.Parent then hrp.Anchored = false end end)
                                            if _freezeConn then _freezeConn:Disconnect(); _freezeConn = nil end
                                            return
                                        end
                                        if hrp and hrp.Parent and _frozenCFrame then
                                            hrp.CFrame = _frozenCFrame
                                        end
                                    end)
                                end
                            end)

                            local TP_SCAN_RADIUS = 50
                            local function _scanNearbyEnemy()
                                local best, bestDist = nil, nil
                                for _, e in ipairs(GetRaidEnemies()) do
                                    local d = (e.hrp.Position - _tpTargetPos).Magnitude
                                    if d <= TP_SCAN_RADIUS and (not bestDist or d < bestDist) then
                                        best = e; bestDist = d
                                    end
                                end
                                return best
                            end

                            local target = _scanNearbyEnemy()
                            local _scanWait = 0
                            while not target and _scanWait < 3 and RAID.running and not _raidDone do
                                task.wait(0.5); _scanWait = _scanWait + 0.5
                                target = _scanNearbyEnemy()
                            end

                            if not target then
                                Log("Tidak ada musuh dalam radius " .. TP_SCAN_RADIUS .. " studs - skip")
                                _step4Cleanup()
                                task.wait(2)
                            else
                                local targetGuid = target.guid
                                Log("Attack: " .. target.model.Name)

                                local function _fireOnce(guid)
                                    if not guid then return end
                                    if RE.Atk then pcall(function() RE.Atk:FireServer({attackEnemyGUID = guid}) end) end
                                    if RE.Click then
                                        task.spawn(function() pcall(function() RE.Click:InvokeServer({enemyGuid = guid}) end) end)
                                    end
                                    EnsureHeroAtkThreadFor(guid)
                                end

                                local _atkStart = tick()
                                local BOSS_TIMEOUT = 240
                                while RAID.running do
                                    if tick() - _atkStart >= BOSS_TIMEOUT then
                                        Log("Timeout 4 menit - dianggap sukses, keluar...")
                                        _raidSuccess = true
                                        break
                                    end
                                    if _raidDone then break end
                                    if not target.model or not target.model.Parent then break end
                                    local hum = target.model:FindFirstChildOfClass("Humanoid")
                                    if not hum or hum.Health <= 0 then break end

                                    local _nearNow = _scanNearbyEnemy()
                                    if _nearNow and _nearNow.guid ~= targetGuid then
                                        target = _nearNow
                                        targetGuid = target.guid
                                        Log("Target baru: " .. target.model.Name)
                                    end

                                    pcall(function() _fireOnce(targetGuid) end)
                                    task.wait()
                                end

                                _step4Cleanup()
                                _raidSuccess = true
                                Log("Boss target down / raid selesai")
                            end
                        end
                    end
                else
                    -- Auto Boss Kill OFF (tidak dipakai karena user minta ON) - tunggu event server
                    local _wt = 0
                    while RAID.running and not _raidDone and _wt < 300 do
                        task.wait(1); _wt = _wt + 1
                    end
                end

                _step4Cleanup()

                if _raidSuccess then
                    RAID.sukses = RAID.sukses + 1
                    Log("SUCCESS #" .. RAID.sukses .. " - Map " .. (raidEntry.mapId - 50000))
                    task.wait(1)
                end
                if not RAID.running then break end

                -- STEP 5: Collect reward + keluar raid
                task.spawn(function() pcall(RaidCollectAll) end)
                RAID_LIVE[RAID.raidId] = nil
                RebuildRaidList()

                local _toMapId = (RAID.fromMapId and RAID.fromMapId >= 50001 and RAID.fromMapId <= 50020) and RAID.fromMapId or 50001
                if RE.QuitRaidsMap then
                    pcall(function() RE.QuitRaidsMap:FireServer({ currentSlotIndex = RAID.slotIndex or 2, toMapId = _toMapId }) end)
                end
                task.wait(0.3)
                if RE.StartTp then
                    pcall(function() RE.StartTp:FireServer({ mapId = _toMapId }) end)
                end

                RAID.inMap = false
                RAID.raidId = nil
                RAID.raidMapId = nil
                RAID.serverMapId = nil
                RAID.fromMapId = nil

                task.wait(1)
            until true
        end
    end)
end

--  STARTUP: delay 10 detik sebelum loop mulai jalan (buffer Auto Execute) 
Log("Script ter-load. Menunggu " .. STARTUP_DELAY .. " detik sebelum AUTO RAID mulai...")
task.spawn(function()
    task.wait(STARTUP_DELAY)
    Log("Startup delay selesai - AUTO RAID dimulai (List Entry: Map 20 [E-A] -> Fallback Manual: Map 16-19 [E..M+], Auto Boss Kill ON, delay TP boss " .. BOSS_TP_DELAY .. "s).")
    StartRaidLoop()
end)
