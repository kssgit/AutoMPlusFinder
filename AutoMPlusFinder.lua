local ADDON_NAME = ...
local AMPF = CreateFrame("Frame")

local DUNGEON_CATEGORY_ID = 2
local CURRENT_SEASON_FILTER = (Enum and Enum.LFGListFilter and Enum.LFGListFilter.CurrentSeason) or 64
local MAX_RENDERED_RESULTS = 50

local defaults = {
    minLevel = 10,
    maxLevel = 12,
    roles = {
        TANK = false,
        HEALER = false,
        DAMAGER = false,
    },
    roleInitialized = false,
    selectedDungeons = {},
    selectionInitialized = false,
    soundEnabled = true,
    point = "CENTER",
    relativePoint = "CENTER",
    x = 0,
    y = 0,
}

local state = {
    dungeons = {},
    dungeonByKey = {},
    dungeonButtons = {},
    resultRows = {},
    matches = {},
    lastNotified = {},
    lastTotalResults = 0,
}

local UI = {}

local function Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99AutoMPlusFinder|r: " .. tostring(msg))
end

local function CopyDefaults(src, dst)
    if type(dst) ~= "table" then
        dst = {}
    end
    for key, value in pairs(src) do
        if type(value) == "table" then
            dst[key] = CopyDefaults(value, type(dst[key]) == "table" and dst[key] or {})
        elseif dst[key] == nil then
            dst[key] = value
        end
    end
    return dst
end

local function ClampNumber(value, minValue, maxValue, fallback)
    value = tonumber(value)
    if not value then
        return fallback
    end
    value = math.floor(value)
    if value < minValue then value = minValue end
    if value > maxValue then value = maxValue end
    return value
end

local function GetCurrentSpecRole()
    local specIndex = GetSpecialization and GetSpecialization()
    if not specIndex then
        return nil
    end
    local role = GetSpecializationRole and GetSpecializationRole(specIndex)
    if role == "DPS" then
        role = "DAMAGER"
    end
    if role == "TANK" or role == "HEALER" or role == "DAMAGER" then
        return role
    end
    return nil
end

local function SetDefaultRoleFromSpec()
    if AutoMPlusFinderDB.roleInitialized then
        return
    end

    local role = GetCurrentSpecRole() or "DAMAGER"
    AutoMPlusFinderDB.roles.TANK = false
    AutoMPlusFinderDB.roles.HEALER = false
    AutoMPlusFinderDB.roles.DAMAGER = false
    AutoMPlusFinderDB.roles[role] = true
    AutoMPlusFinderDB.roleInitialized = true
end

local function DungeonKey(activityInfo, activityID)
    if activityInfo and activityInfo.mapID and activityInfo.mapID > 0 then
        return "map:" .. tostring(activityInfo.mapID)
    end
    if activityInfo and activityInfo.groupFinderActivityGroupID and activityInfo.groupFinderActivityGroupID > 0 then
        return "group:" .. tostring(activityInfo.groupFinderActivityGroupID)
    end
    return "activity:" .. tostring(activityID)
end

local function GetDungeonDisplayName(activityInfo)
    if not activityInfo then
        return "알 수 없는 던전"
    end

    local groupID = activityInfo.groupFinderActivityGroupID
    if groupID and groupID > 0 and C_LFGList.GetActivityGroupInfo then
        local groupName = C_LFGList.GetActivityGroupInfo(groupID)
        if groupName and groupName ~= "" then
            return groupName
        end
    end

    local name = activityInfo.fullName or activityInfo.shortName or "알 수 없는 던전"
    -- 대부분의 클라이언트에서 뒤쪽의 "(신화 쐐기돌)" 같은 난이도 표기를 제거한다.
    name = name:gsub("%s*%b()$", "")
    return name
end

local function DiscoverCurrentSeasonDungeons()
    wipe(state.dungeons)
    wipe(state.dungeonByKey)

    if not C_LFGList or not C_LFGList.GetAvailableActivities then
        return false
    end

    local activities = C_LFGList.GetAvailableActivities(DUNGEON_CATEGORY_ID, nil, CURRENT_SEASON_FILTER)
    local usedFallback = false
    if not activities or #activities == 0 then
        -- 아직 CurrentSeason 목록이 준비되지 않은 클라이언트를 위한 보조 경로.
        activities = C_LFGList.GetAvailableActivities(DUNGEON_CATEGORY_ID)
        usedFallback = true
    end
    if not activities then
        return false
    end

    for _, activityID in ipairs(activities) do
        local info = C_LFGList.GetActivityInfoTable(activityID)
        local currentSeason = true
        if usedFallback and info and info.filters and bit and bit.band then
            currentSeason = bit.band(info.filters, CURRENT_SEASON_FILTER) ~= 0
        end
        if info and info.isMythicPlusActivity and currentSeason then
            local key = DungeonKey(info, activityID)
            if not state.dungeonByKey[key] then
                local entry = {
                    key = key,
                    name = GetDungeonDisplayName(info),
                    mapID = info.mapID,
                    groupID = info.groupFinderActivityGroupID,
                    sampleActivityID = activityID,
                }
                state.dungeonByKey[key] = entry
                table.insert(state.dungeons, entry)
            end
        end
    end

    table.sort(state.dungeons, function(a, b)
        return a.name < b.name
    end)

    if #state.dungeons > 0 and not AutoMPlusFinderDB.selectionInitialized then
        for _, dungeon in ipairs(state.dungeons) do
            AutoMPlusFinderDB.selectedDungeons[dungeon.key] = true
        end
        AutoMPlusFinderDB.selectionInitialized = true
    end

    return #state.dungeons > 0
end

local function SaveFramePosition()
    if not UI.frame then return end
    local point, _, relativePoint, x, y = UI.frame:GetPoint(1)
    AutoMPlusFinderDB.point = point or "CENTER"
    AutoMPlusFinderDB.relativePoint = relativePoint or "CENTER"
    AutoMPlusFinderDB.x = math.floor((x or 0) + 0.5)
    AutoMPlusFinderDB.y = math.floor((y or 0) + 0.5)
end

local function SaveSettingsFromUI()
    if not UI.frame then return true end

    local minLevel = ClampNumber(UI.minLevel:GetText(), 2, 99, AutoMPlusFinderDB.minLevel)
    local maxLevel = ClampNumber(UI.maxLevel:GetText(), 2, 99, AutoMPlusFinderDB.maxLevel)
    if minLevel > maxLevel then
        minLevel, maxLevel = maxLevel, minLevel
    end

    AutoMPlusFinderDB.minLevel = minLevel
    AutoMPlusFinderDB.maxLevel = maxLevel
    UI.minLevel:SetText(tostring(minLevel))
    UI.maxLevel:SetText(tostring(maxLevel))

    AutoMPlusFinderDB.roles.TANK = UI.roleTank:GetChecked() and true or false
    AutoMPlusFinderDB.roles.HEALER = UI.roleHealer:GetChecked() and true or false
    AutoMPlusFinderDB.roles.DAMAGER = UI.roleDamage:GetChecked() and true or false

    if not AutoMPlusFinderDB.roles.TANK and not AutoMPlusFinderDB.roles.HEALER and not AutoMPlusFinderDB.roles.DAMAGER then
        Print("신청 역할을 최소 1개 선택해야 합니다.")
        return false
    end

    return true
end

local function IsApplied(resultID, appliedSet)
    return appliedSet[resultID] == true
end

local function BuildAppliedSet()
    local set = {}
    if not C_LFGList.GetApplications then
        return set
    end
    local applications = C_LFGList.GetApplications()
    if applications then
        for _, resultID in ipairs(applications) do
            set[resultID] = true
        end
    end
    return set
end

local function GetRoleRemaining(memberCounts, role)
    if not memberCounts then
        return nil
    end

    if role == "TANK" then
        if memberCounts.TANK_REMAINING ~= nil then
            return memberCounts.TANK_REMAINING
        end
        return math.max(0, 1 - (memberCounts.TANK or 0))
    elseif role == "HEALER" then
        if memberCounts.HEALER_REMAINING ~= nil then
            return memberCounts.HEALER_REMAINING
        end
        return math.max(0, 1 - (memberCounts.HEALER or 0))
    elseif role == "DAMAGER" then
        if memberCounts.DAMAGER_REMAINING ~= nil then
            return memberCounts.DAMAGER_REMAINING
        end
        return math.max(0, 3 - (memberCounts.DAMAGER or 0))
    end

    return nil
end

local function HasSelectedRoleSlot(memberCounts)
    if not memberCounts then
        return true
    end

    if AutoMPlusFinderDB.roles.TANK then
        local remaining = GetRoleRemaining(memberCounts, "TANK")
        if remaining == nil or remaining > 0 then return true end
    end
    if AutoMPlusFinderDB.roles.HEALER then
        local remaining = GetRoleRemaining(memberCounts, "HEALER")
        if remaining == nil or remaining > 0 then return true end
    end
    if AutoMPlusFinderDB.roles.DAMAGER then
        local remaining = GetRoleRemaining(memberCounts, "DAMAGER")
        if remaining == nil or remaining > 0 then return true end
    end

    return false
end

local function GetMythicPlusActivity(resultInfo)
    if not resultInfo then
        return nil
    end

    local activityIDs = resultInfo.activityIDs
    if (not activityIDs or #activityIDs == 0) and resultInfo.activityID then
        activityIDs = { resultInfo.activityID }
    end
    if not activityIDs then
        return nil
    end

    for _, activityID in ipairs(activityIDs) do
        local activityInfo = C_LFGList.GetActivityInfoTable(activityID)
        if activityInfo and activityInfo.isMythicPlusActivity then
            local keyLevel = C_LFGList.GetKeystoneForActivity and C_LFGList.GetKeystoneForActivity(activityID)
            if keyLevel and keyLevel > 0 then
                return activityID, activityInfo, keyLevel
            end
        end
    end

    return nil
end

local function BuildMatch(resultID, appliedSet)
    if IsApplied(resultID, appliedSet) then
        return nil
    end

    local resultInfo = C_LFGList.GetSearchResultInfo(resultID)
    if not resultInfo or resultInfo.isDelisted or resultInfo.hasSelf then
        return nil
    end

    if (resultInfo.numMembers or 0) >= 5 then
        return nil
    end

    local activityID, activityInfo, keyLevel = GetMythicPlusActivity(resultInfo)
    if not activityID then
        return nil
    end

    if keyLevel < AutoMPlusFinderDB.minLevel or keyLevel > AutoMPlusFinderDB.maxLevel then
        return nil
    end

    local dungeonKey = DungeonKey(activityInfo, activityID)
    if not AutoMPlusFinderDB.selectedDungeons[dungeonKey] then
        return nil
    end

    local memberCounts = C_LFGList.GetSearchResultMemberCounts and C_LFGList.GetSearchResultMemberCounts(resultID) or nil
    if not HasSelectedRoleSlot(memberCounts) then
        return nil
    end

    local dungeon = state.dungeonByKey[dungeonKey]
    local dungeonName = dungeon and dungeon.name or GetDungeonDisplayName(activityInfo)

    return {
        resultID = resultID,
        activityID = activityID,
        dungeonKey = dungeonKey,
        dungeonName = dungeonName,
        keyLevel = keyLevel,
        numMembers = resultInfo.numMembers or 0,
        leaderName = resultInfo.leaderName,
        leaderScore = resultInfo.leaderOverallDungeonScore,
        requiredScore = resultInfo.requiredDungeonScore,
        requiredItemLevel = resultInfo.requiredItemLevel,
        age = resultInfo.age or 0,
        memberCounts = memberCounts,
    }
end

local function FormatAge(seconds)
    seconds = tonumber(seconds) or 0
    if seconds < 60 then
        return string.format("%d초", seconds)
    end
    return string.format("%d분", math.floor(seconds / 60))
end

local function RoleSummary(memberCounts)
    if not memberCounts then
        return "역할 정보 없음"
    end
    return string.format("탱 %d / 힐 %d / 딜 %d",
        memberCounts.TANK or 0,
        memberCounts.HEALER or 0,
        memberCounts.DAMAGER or 0)
end

local function NotifyNewMatches(matches)
    local newCount = 0
    local current = {}

    for _, match in ipairs(matches) do
        current[match.resultID] = true
        if not state.lastNotified[match.resultID] then
            newCount = newCount + 1
        end
    end

    if newCount > 0 then
        if AutoMPlusFinderDB.soundEnabled and PlaySound then
            local soundID = (SOUNDKIT and (SOUNDKIT.READY_CHECK or SOUNDKIT.RAID_WARNING)) or 8960
            PlaySound(soundID, "Master")
        end
        if UIErrorsFrame then
            UIErrorsFrame:AddMessage(string.format("AutoMPlusFinder: 조건 일치 파티 %d개 발견", newCount), 0.2, 1.0, 0.2, 1.0)
        end
    end

    state.lastNotified = current
end

local function ApplyToMatch(match)
    if not match or not match.resultID then return end
    if InCombatLockdown and InCombatLockdown() then
        Print("전투 중에는 파티 신청을 시도하지 않습니다.")
        return
    end

    if not SaveSettingsFromUI() then
        return
    end

    local tank = AutoMPlusFinderDB.roles.TANK
    local healer = AutoMPlusFinderDB.roles.HEALER
    local damage = AutoMPlusFinderDB.roles.DAMAGER

    -- C_LFGList.ApplyToGroup는 hardware-event 제한 함수다.
    -- 이 함수는 반드시 사용자가 이 버튼을 직접 클릭한 OnClick 흐름에서만 호출한다.
    C_LFGList.ApplyToGroup(match.resultID, tank, healer, damage)
    Print(string.format("%s +%d 파티에 신청 요청을 보냈습니다.", match.dungeonName, match.keyLevel))
end

local function CreateResultRow(index)
    local row = CreateFrame("Frame", nil, UI.resultsContent, "BackdropTemplate")
    row:SetHeight(58)
    row:SetPoint("TOPLEFT", 0, -((index - 1) * 60))
    row:SetPoint("TOPRIGHT", -6, -((index - 1) * 60))
    row:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 10,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    row:SetBackdropColor(0.05, 0.05, 0.05, 0.75)
    row:SetBackdropBorderColor(0.25, 0.25, 0.25, 1)

    row.title = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.title:SetPoint("TOPLEFT", 9, -8)
    row.title:SetJustifyH("LEFT")

    row.details = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.details:SetPoint("TOPLEFT", row.title, "BOTTOMLEFT", 0, -5)
    row.details:SetJustifyH("LEFT")

    row.apply = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    row.apply:SetSize(72, 30)
    row.apply:SetPoint("RIGHT", -8, 0)
    row.apply:SetText("신청")
    row.apply:SetScript("OnClick", function(self)
        ApplyToMatch(self.match)
    end)

    state.resultRows[index] = row
    return row
end

local function RenderResults()
    if not UI.resultsContent then return end

    for index, row in ipairs(state.resultRows) do
        row:Hide()
    end

    local visibleCount = math.min(#state.matches, MAX_RENDERED_RESULTS)
    UI.resultsContent:SetHeight(math.max(1, visibleCount) * 60)

    for index = 1, visibleCount do
        local match = state.matches[index]
        local row = state.resultRows[index] or CreateResultRow(index)
        row.match = match

        row.title:SetText(string.format("|cffffffff%s|r  |cff33ff99+%d|r", match.dungeonName, match.keyLevel))

        local scoreText = match.leaderScore and string.format("리더 점수 %d", match.leaderScore) or "리더 점수 ?"
        local reqScoreText = (match.requiredScore and match.requiredScore > 0) and string.format("요구 %d", match.requiredScore) or "요구 없음"
        row.details:SetText(string.format("%d/5 · %s · %s · %s · %s",
            match.numMembers,
            RoleSummary(match.memberCounts),
            scoreText,
            reqScoreText,
            FormatAge(match.age)))

        row:Show()
    end

    if #state.matches > MAX_RENDERED_RESULTS then
        UI.status:SetText(string.format("조건 일치 %d개 (상위 %d개 표시) / 검색 결과 %d개", #state.matches, MAX_RENDERED_RESULTS, state.lastTotalResults))
    else
        UI.status:SetText(string.format("조건 일치 %d개 / 검색 결과 %d개", #state.matches, state.lastTotalResults))
    end
end

local function RefreshResults()
    if not AutoMPlusFinderDB or not C_LFGList.GetSearchResults then
        return
    end

    if UI.frame and not SaveSettingsFromUI() then
        return
    end

    local totalResults, results = C_LFGList.GetSearchResults()
    state.lastTotalResults = totalResults or 0
    results = results or {}

    local appliedSet = BuildAppliedSet()
    local matches = {}

    for _, resultID in ipairs(results) do
        local match = BuildMatch(resultID, appliedSet)
        if match then
            table.insert(matches, match)
        end
    end

    table.sort(matches, function(a, b)
        if a.keyLevel ~= b.keyLevel then
            return a.keyLevel > b.keyLevel
        end
        if a.numMembers ~= b.numMembers then
            return a.numMembers > b.numMembers
        end
        return (a.leaderScore or 0) > (b.leaderScore or 0)
    end)

    state.matches = matches
    NotifyNewMatches(matches)
    RenderResults()
end

local function DoSearch()
    if not SaveSettingsFromUI() then
        return
    end

    local selectedCount = 0
    for _, dungeon in ipairs(state.dungeons) do
        if AutoMPlusFinderDB.selectedDungeons[dungeon.key] then
            selectedCount = selectedCount + 1
        end
    end
    if selectedCount == 0 then
        Print("던전을 최소 1개 선택해야 합니다.")
        return
    end

    if InCombatLockdown and InCombatLockdown() then
        Print("전투 중에는 파티 검색을 실행하지 않습니다.")
        return
    end

    wipe(state.lastNotified)
    UI.status:SetText("파티 찾기 검색 중...")

    -- C_LFGList.Search 역시 hardware-event 제한 함수이므로 자동 타이머에서 호출하지 않는다.
    C_LFGList.Search(DUNGEON_CATEGORY_ID, CURRENT_SEASON_FILTER, 0, nil, true)
end

local function CreateLabeledEditBox(parent, labelText, x, y, width)
    local label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("TOPLEFT", x, y)
    label:SetText(labelText)

    local box = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    box:SetSize(width or 50, 24)
    box:SetPoint("LEFT", label, "RIGHT", 8, 0)
    box:SetAutoFocus(false)
    box:SetNumeric(true)
    box:SetMaxLetters(2)
    box:SetJustifyH("CENTER")
    return box, label
end

local function CreateRoleCheck(parent, labelText, x, y)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetPoint("TOPLEFT", x, y)
    cb:SetSize(24, 24)
    cb.Text:SetText(labelText)
    cb.Text:SetPoint("LEFT", cb, "RIGHT", 2, 0)
    return cb
end

local function RebuildDungeonButtons()
    if not UI.dungeonContent then return end

    for _, button in ipairs(state.dungeonButtons) do
        button:Hide()
    end
    wipe(state.dungeonButtons)

    if #state.dungeons == 0 then
        UI.dungeonHint:SetText("현재 시즌 쐐기 던전 정보를 아직 불러오지 못했습니다.\n파티 찾기 창을 한 번 열거나 /reload 후 다시 확인하세요.")
        UI.dungeonContent:SetHeight(55)
        return
    end

    UI.dungeonHint:SetText("")
    local rows = math.ceil(#state.dungeons / 2)
    UI.dungeonContent:SetHeight(math.max(1, rows) * 28)

    for index, dungeon in ipairs(state.dungeons) do
        local col = (index - 1) % 2
        local row = math.floor((index - 1) / 2)
        local cb = CreateFrame("CheckButton", nil, UI.dungeonContent, "UICheckButtonTemplate")
        cb:SetSize(24, 24)
        cb:SetPoint("TOPLEFT", 6 + (col * 245), -(row * 28))
        cb.Text:SetText(dungeon.name)
        cb.Text:SetPoint("LEFT", cb, "RIGHT", 2, 0)
        cb:SetChecked(AutoMPlusFinderDB.selectedDungeons[dungeon.key] == true)
        cb:SetScript("OnClick", function(self)
            AutoMPlusFinderDB.selectedDungeons[dungeon.key] = self:GetChecked() and true or nil
            RefreshResults()
        end)
        table.insert(state.dungeonButtons, cb)
    end
end

local function SelectAllDungeons(selected)
    for _, dungeon in ipairs(state.dungeons) do
        AutoMPlusFinderDB.selectedDungeons[dungeon.key] = selected and true or nil
    end
    RebuildDungeonButtons()
    RefreshResults()
end

local function CreateUI()
    local frame = CreateFrame("Frame", "AutoMPlusFinderFrame", UIParent, "BackdropTemplate")
    UI.frame = frame
    frame:SetSize(570, 650)
    frame:SetPoint(
        AutoMPlusFinderDB.point or "CENTER",
        UIParent,
        AutoMPlusFinderDB.relativePoint or "CENTER",
        AutoMPlusFinderDB.x or 0,
        AutoMPlusFinderDB.y or 0
    )
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        SaveFramePosition()
    end)
    frame:SetClampedToScreen(true)
    frame:SetFrameStrata("DIALOG")
    frame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true,
        tileSize = 32,
        edgeSize = 32,
        insets = { left = 10, right = 10, top = 10, bottom = 10 },
    })

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    title:SetPoint("TOP", 0, -18)
    title:SetText("AutoMPlusFinder")

    local subtitle = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    subtitle:SetPoint("TOP", title, "BOTTOM", 0, -5)
    subtitle:SetText("조건에 맞는 쐐기 파티를 필터링하고 클릭 한 번으로 신청")

    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -5, -5)

    UI.minLevel = CreateLabeledEditBox(frame, "최소 단수", 22, -70, 45)
    UI.minLevel:SetText(tostring(AutoMPlusFinderDB.minLevel))

    UI.maxLevel = CreateLabeledEditBox(frame, "최대 단수", 180, -70, 45)
    UI.maxLevel:SetText(tostring(AutoMPlusFinderDB.maxLevel))

    local rolesLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    rolesLabel:SetPoint("TOPLEFT", 330, -70)
    rolesLabel:SetText("신청 역할")

    UI.roleTank = CreateRoleCheck(frame, "탱", 390, -64)
    UI.roleTank:SetChecked(AutoMPlusFinderDB.roles.TANK)
    UI.roleHealer = CreateRoleCheck(frame, "힐", 445, -64)
    UI.roleHealer:SetChecked(AutoMPlusFinderDB.roles.HEALER)
    UI.roleDamage = CreateRoleCheck(frame, "딜", 500, -64)
    UI.roleDamage:SetChecked(AutoMPlusFinderDB.roles.DAMAGER)

    local dungeonLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    dungeonLabel:SetPoint("TOPLEFT", 22, -108)
    dungeonLabel:SetText("대상 던전")

    local allButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    allButton:SetSize(70, 22)
    allButton:SetPoint("LEFT", dungeonLabel, "RIGHT", 15, 0)
    allButton:SetText("전체 선택")
    allButton:SetScript("OnClick", function() SelectAllDungeons(true) end)

    local noneButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    noneButton:SetSize(70, 22)
    noneButton:SetPoint("LEFT", allButton, "RIGHT", 6, 0)
    noneButton:SetText("전체 해제")
    noneButton:SetScript("OnClick", function() SelectAllDungeons(false) end)

    local dungeonBox = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    dungeonBox:SetPoint("TOPLEFT", 20, -135)
    dungeonBox:SetPoint("TOPRIGHT", -20, -135)
    dungeonBox:SetHeight(125)
    dungeonBox:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 10,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    dungeonBox:SetBackdropColor(0.02, 0.02, 0.02, 0.55)

    local dungeonScroll = CreateFrame("ScrollFrame", nil, dungeonBox, "UIPanelScrollFrameTemplate")
    dungeonScroll:SetPoint("TOPLEFT", 6, -6)
    dungeonScroll:SetPoint("BOTTOMRIGHT", -26, 6)

    UI.dungeonContent = CreateFrame("Frame", nil, dungeonScroll)
    UI.dungeonContent:SetWidth(500)
    UI.dungeonContent:SetHeight(100)
    dungeonScroll:SetScrollChild(UI.dungeonContent)

    UI.dungeonHint = UI.dungeonContent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    UI.dungeonHint:SetPoint("TOPLEFT", 8, -8)
    UI.dungeonHint:SetWidth(460)
    UI.dungeonHint:SetJustifyH("LEFT")

    local searchButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    searchButton:SetSize(180, 34)
    searchButton:SetPoint("TOP", dungeonBox, "BOTTOM", 0, -12)
    searchButton:SetText("검색 / 갱신")
    searchButton:SetScript("OnClick", DoSearch)

    local restriction = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    restriction:SetPoint("TOP", searchButton, "BOTTOM", 0, -5)
    restriction:SetText("※ WoW API 제한으로 검색/신청은 사용자 클릭이 필요합니다.")

    UI.status = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    UI.status:SetPoint("TOPLEFT", 22, -325)
    UI.status:SetText("검색 결과 없음")

    local resultsBox = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    resultsBox:SetPoint("TOPLEFT", 20, -350)
    resultsBox:SetPoint("BOTTOMRIGHT", -20, 22)
    resultsBox:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 10,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    resultsBox:SetBackdropColor(0.02, 0.02, 0.02, 0.55)

    local resultsScroll = CreateFrame("ScrollFrame", nil, resultsBox, "UIPanelScrollFrameTemplate")
    resultsScroll:SetPoint("TOPLEFT", 6, -6)
    resultsScroll:SetPoint("BOTTOMRIGHT", -26, 6)

    UI.resultsContent = CreateFrame("Frame", nil, resultsScroll)
    UI.resultsContent:SetWidth(500)
    UI.resultsContent:SetHeight(1)
    resultsScroll:SetScrollChild(UI.resultsContent)

    frame:Hide()
    RebuildDungeonButtons()
end

local function ToggleUI()
    if not UI.frame then return end
    if UI.frame:IsShown() then
        UI.frame:Hide()
    else
        UI.frame:Show()
        DiscoverCurrentSeasonDungeons()
        RebuildDungeonButtons()
        RefreshResults()
    end
end

AMPF:RegisterEvent("ADDON_LOADED")
AMPF:RegisterEvent("PLAYER_LOGIN")
AMPF:RegisterEvent("LFG_LIST_AVAILABILITY_UPDATE")
AMPF:RegisterEvent("LFG_LIST_SEARCH_RESULTS_RECEIVED")
AMPF:RegisterEvent("LFG_LIST_SEARCH_RESULT_UPDATED")
AMPF:RegisterEvent("LFG_LIST_APPLICATION_STATUS_UPDATED")

AMPF:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        local loadedAddon = ...
        if loadedAddon ~= ADDON_NAME then return end

        AutoMPlusFinderDB = CopyDefaults(defaults, AutoMPlusFinderDB or {})
        C_LFGList.RequestAvailableActivities()

    elseif event == "PLAYER_LOGIN" then
        SetDefaultRoleFromSpec()
        DiscoverCurrentSeasonDungeons()
        CreateUI()
        Print("로드됨. /ampf 로 창을 열 수 있습니다.")

    elseif event == "LFG_LIST_AVAILABILITY_UPDATE" then
        if DiscoverCurrentSeasonDungeons() and UI.frame then
            RebuildDungeonButtons()
        end

    elseif event == "LFG_LIST_SEARCH_RESULTS_RECEIVED" then
        RefreshResults()

    elseif event == "LFG_LIST_SEARCH_RESULT_UPDATED" then
        RefreshResults()

    elseif event == "LFG_LIST_APPLICATION_STATUS_UPDATED" then
        RefreshResults()
    end
end)

SLASH_AUTOMPLUSFINDER1 = "/ampf"
SlashCmdList.AUTOMPLUSFINDER = function(msg)
    msg = (msg or ""):lower():match("^%s*(.-)%s*$")

    if msg == "show" then
        UI.frame:Show()
        DiscoverCurrentSeasonDungeons()
        RebuildDungeonButtons()
        RefreshResults()
    elseif msg == "hide" then
        UI.frame:Hide()
    elseif msg == "reset" then
        AutoMPlusFinderDB.minLevel = defaults.minLevel
        AutoMPlusFinderDB.maxLevel = defaults.maxLevel
        AutoMPlusFinderDB.roles = CopyDefaults(defaults.roles, {})
        AutoMPlusFinderDB.roleInitialized = false
        SetDefaultRoleFromSpec()
        AutoMPlusFinderDB.selectedDungeons = {}
        AutoMPlusFinderDB.selectionInitialized = false
        DiscoverCurrentSeasonDungeons()
        if UI.frame then
            UI.minLevel:SetText(tostring(AutoMPlusFinderDB.minLevel))
            UI.maxLevel:SetText(tostring(AutoMPlusFinderDB.maxLevel))
            UI.roleTank:SetChecked(AutoMPlusFinderDB.roles.TANK)
            UI.roleHealer:SetChecked(AutoMPlusFinderDB.roles.HEALER)
            UI.roleDamage:SetChecked(AutoMPlusFinderDB.roles.DAMAGER)
            RebuildDungeonButtons()
            RefreshResults()
        end
        Print("설정을 초기화했습니다.")
    elseif msg == "help" then
        Print("/ampf - 창 열기/닫기")
        Print("/ampf show - 창 열기")
        Print("/ampf hide - 창 닫기")
        Print("/ampf reset - 설정 초기화")
    else
        ToggleUI()
    end
end
