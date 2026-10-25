-- ChatKeeper by feralpaw - lightweight 7-day chat log for WoW 3.3.5a
local ADDON = ...
local DAY = 86400
local db, sessionStart, lastMsg, lastT
local replaying = false
local elvCH -- ElvUI chat module, if ElvUI chat is used
local RawAdd = getmetatable(ChatFrame1).__index.AddMessage -- Blizzard method, skips every addon hook
local defaults = { days = 7, max = 30000, replay = 500, chatLines = 2000, off = {} }

local function P(s) DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99ChatKeeper|r: " .. s) end
local function IsCL(f) return f and (f == COMBATLOG or (IsCombatLog and IsCombatLog(f))) end
local function Hex(r, g, b)
  return format("%02x%02x%02x", floor((r or 1) * 255 + .5), floor((g or 1) * 255 + .5), floor((b or 1) * 255 + .5))
end
local function RGB(h) return tonumber(h:sub(1, 2), 16) / 255, tonumber(h:sub(3, 4), 16) / 255, tonumber(h:sub(5, 6), 16) / 255 end
-- line format: "time<TAB>tabs<TAB>color<TAB>message"   tabs = letters A..J (chat frame 1..10)
local function Parse(l)
  local t, fr, c, m = l:match("^(%d+)\t(%u+)\t(%x+)\t(.*)$")
  return tonumber(t), fr, c, m
end
local function Plain(s)
  return (s:gsub("|Hurl:(.-)|h.-|h", "%1"):gsub("|H.-|h(.-)|h", "%1"):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", ""))
end

-- drop lines older than X days / over the cap
local function Trim()
  local L, n, cut = db.lines, #db.lines, time() - db.days * DAY
  local first = max(1, n - db.max + 1)
  while first <= n and (tonumber(L[first]:match("^%d+")) or 0) < cut do first = first + 1 end
  if first > 1 then
    local new = {}
    for k = first, n do new[#new + 1] = L[k] end
    db.lines = new
    if sessionStart then sessionStart = max(1, sessionStart - (first - 1)) end
  end
end

local function Log(i, msg, r, g, b)
  if replaying or not db or db.off[i] or type(msg) ~= "string" or msg == "" then return end
  local f = _G["ChatFrame" .. i]
  if IsCL(f) then return end
  -- ElvUI puts its own [hh:mm] in front; we keep our own time, so drop theirs
  if f.OldAddMessage and elvCH and elvCH.db and elvCH.db.timeStampFormat and elvCH.db.timeStampFormat ~= "NONE" then
    msg = msg:gsub("^|c%x%x%x%x%x%x%x%x%[[^%]]-%]|r ", "", 1):gsub("^%[[^%]]-%] ", "", 1)
  end
  local L, t, c = db.lines, time(), string.char(64 + i)
  local n = #L
  if msg == lastMsg and t - lastT <= 1 and n > 0 then -- same line in another tab: only tag it
    local lt, fr, col, m = Parse(L[n])
    if lt and not fr:find(c, 1, true) then L[n] = lt .. "\t" .. fr .. c .. "\t" .. col .. "\t" .. m; return end
  end
  lastMsg, lastT = msg, t
  L[n + 1] = t .. "\t" .. c .. "\t" .. Hex(r, g, b) .. "\t" .. msg
  if n > db.max + 2000 then Trim() end
end

-- put the last N old lines back into each chat tab so you can scroll up
local function Restore()
  local L, b, need = db.lines, {}, 0
  for i = 1, NUM_CHAT_WINDOWS do
    local f = _G["ChatFrame" .. i]
    if f and not db.off[i] and not IsCL(f) then
      -- ElvUI controls its own line limit (ElvUI > Chat > Max Lines); only raise Blizzard's
      if not f.OldAddMessage and f:GetMaxLines() < db.chatLines then f:SetMaxLines(db.chatLines) end
      b[i] = { old = {}, new = {}, lim = max(1, min(db.replay, f:GetMaxLines() - 60)) }; need = need + 1
    end
  end
  for k = #L, 1, -1 do
    local fr = L[k]:match("^%d+\t(%u+)")
    if fr then
      for p = 1, #fr do
        local s = b[fr:byte(p) - 64]
        if s then
          if k >= sessionStart then s.new[#s.new + 1] = k
          elseif not s.full then
            s.old[#s.old + 1] = k
            if #s.old >= s.lim then s.full = true; need = need - 1 end
          end
        end
      end
    end
    if need <= 0 then break end
  end
  replaying = true
  for i, s in pairs(b) do
    local f = _G["ChatFrame" .. i]
    f:Clear()
    for j = #s.old, 1, -1 do
      local t, _, c, m = Parse(L[s.old[j]])
      if t then RawAdd(f, "|cff707070" .. date("%a %H:%M", t) .. "|r " .. m, RGB(c)) end
    end
    if #s.old > 0 then RawAdd(f, "|cff707070---- " .. #s.old .. " older lines restored, /ck for the full week ----|r") end
    for j = #s.new, 1, -1 do
      local t, _, c, m = Parse(L[s.new[j]])
      if t then RawAdd(f, (f.OldAddMessage and "|cff707070" .. date("%H:%M", t) .. "|r " or "") .. m, RGB(c)) end
    end
  end
  replaying = false
end

-- clickable URLs
local function Linkify(w)
  if not w:find("|", 1, true) and (w:find("^%a[%w+.-]*://") or w:find("^www%.%w")) then
    return "|cff33ccff|Hurl:" .. w .. "|h[" .. w .. "]|h|r"
  end
end
local function URLFilter(_, _, msg, ...)
  if type(msg) == "string" and (msg:find("://", 1, true) or msg:find("www.", 1, true)) then
    return false, (msg:gsub("%S+", Linkify)), ...
  end
end
local function AddURLFilter()
  if elvCH and elvCH.Initialized and elvCH.db and elvCH.db.url then return end -- ElvUI already makes URLs clickable
  for _, e in ipairs({ "SAY", "YELL", "WHISPER", "WHISPER_INFORM", "GUILD", "OFFICER", "PARTY", "PARTY_LEADER",
  "RAID", "RAID_LEADER", "RAID_WARNING", "CHANNEL", "BATTLEGROUND", "BATTLEGROUND_LEADER", "BN_WHISPER", "BN_WHISPER_INFORM" }) do
    ChatFrame_AddMessageEventFilter("CHAT_MSG_" .. e, URLFilter)
  end
end

-- windows
local view, copy
local function Window(name, w, h)
  local f = CreateFrame("Frame", name, UIParent)
  f:SetWidth(w); f:SetHeight(h); f:SetPoint("CENTER"); f:SetFrameStrata("DIALOG"); f:SetClampedToScreen(true)
  f:SetBackdrop({ bgFile = "Interface\\ChatFrame\\ChatFrameBackground", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    edgeSize = 14, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
  f:SetBackdropColor(0, 0, 0, .85); f:SetBackdropBorderColor(.5, .5, .5)
  f:EnableMouse(true); f:SetMovable(true); f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving); f:SetScript("OnDragStop", f.StopMovingOrSizing)
  tinsert(UISpecialFrames, name)
  CreateFrame("Button", nil, f, "UIPanelCloseButton"):SetPoint("TOPRIGHT", 2, 2)
  f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal"); f.title:SetPoint("TOPLEFT", 12, -10)
  f:Hide()
  return f
end

local function ShowCopy(text)
  if not copy then
    copy = Window("ChatKeeperCopy", 620, 320)
    copy.title:SetText("Ctrl+C to copy, Esc to close")
    copy:SetFrameStrata("FULLSCREEN_DIALOG"); copy:SetToplevel(true)
    copy:SetBackdropColor(.05, .05, .05, 1)
    local sf = CreateFrame("ScrollFrame", "ChatKeeperCopyScroll", copy, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT", 10, -30); sf:SetPoint("BOTTOMRIGHT", -30, 10)
    local eb = CreateFrame("EditBox", nil, sf)
    eb:SetMultiLine(true); eb:SetAutoFocus(false); eb:SetMaxLetters(0)
    eb:SetFontObject(ChatFontNormal); eb:SetWidth(570); eb:SetHeight(270)
    eb:SetScript("OnEscapePressed", function() copy:Hide() end)
    sf:SetScrollChild(eb)
    copy.eb = eb
  end
  copy:Show(); copy:Raise(); copy.eb:SetText(text); copy.eb:HighlightText(); copy.eb:SetFocus()
end

local origSetItemRef = SetItemRef
SetItemRef = function(link, text, button, ...)
  if type(link) == "string" and link:sub(1, 4) == "url:" then
    local url = link:sub(5)
    if IsShiftKeyDown() and ChatEdit_InsertLink then ChatEdit_InsertLink(url) else ShowCopy(url) end
    return
  end
  return origSetItemRef(link, text, button, ...)
end

local function Fill(filter)
  local smf, L, n = view.smf, db.lines, 0
  smf:Clear(); view.shown = {}
  filter = filter ~= "" and filter:lower() or nil
  for k = 1, #L do
    local t, _, c, m = Parse(L[k])
    if t and (not filter or Plain(m):lower():find(filter, 1, true)) then
      smf:AddMessage("|cff707070" .. date("%a %d.%m %H:%M", t) .. "|r " .. m, RGB(c))
      n = n + 1; view.shown[n] = k
    end
  end
  view.title:SetText(format("ChatKeeper - %d lines", n))
end

local tipTypes = { item = 1, spell = 1, enchant = 1, achievement = 1, quest = 1, talent = 1 }
local function ToggleView()
  if not view then
    view = Window("ChatKeeperFrame", 760, 460)
    local s = CreateFrame("EditBox", "ChatKeeperSearch", view, "InputBoxTemplate")
    s:SetWidth(180); s:SetHeight(20); s:SetAutoFocus(false); s:SetPoint("TOPRIGHT", -112, -6)
    s:SetScript("OnEnterPressed", function(self) self:ClearFocus(); Fill(self:GetText()) end)
    s:SetScript("OnEscapePressed", function(self) self:SetText(""); self:ClearFocus(); Fill("") end)
    -- search while typing (short delay so it doesn't run on every key)
    local pending = 0
    s:SetScript("OnTextChanged", function(self) pending = .4; self:SetScript("OnUpdate", function(me, el)
      pending = pending - el
      if pending <= 0 then me:SetScript("OnUpdate", nil); if view:IsShown() then Fill(me:GetText()) end end
    end) end)
    local sl = view:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); sl:SetPoint("RIGHT", s, "LEFT", -8, 0); sl:SetText("Search:")
    local cb = CreateFrame("Button", nil, view, "UIPanelButtonTemplate")
    cb:SetWidth(70); cb:SetHeight(20); cb:SetPoint("TOPRIGHT", -30, -6); cb:SetText("Copy")
    cb:SetScript("OnClick", function()
      local out, sh = {}, view.shown
      for j = max(1, #sh - 499), #sh do
        local t, _, _, m = Parse(db.lines[sh[j]])
        if t then out[#out + 1] = date("%d.%m %H:%M ", t) .. Plain(m) end
      end
      ShowCopy(table.concat(out, "\n"))
    end)
    local smf = CreateFrame("ScrollingMessageFrame", nil, view)
    smf:SetPoint("TOPLEFT", 10, -32); smf:SetPoint("BOTTOMRIGHT", -10, 10)
    smf:SetFontObject(ChatFontNormal); smf:SetJustifyH("LEFT"); smf:SetFading(false); smf:SetMaxLines(db.max + 2500)
    smf:EnableMouse(true); smf:EnableMouseWheel(true)
    if smf.SetHyperlinksEnabled then smf:SetHyperlinksEnabled(true) end
    smf:SetScript("OnHyperlinkClick", function(_, link, text, button) ChatFrame_OnHyperlinkShow(DEFAULT_CHAT_FRAME, link, text, button) end)
    smf:SetScript("OnHyperlinkEnter", function(self, link)
      if tipTypes[link:match("^(%a+):") or ""] then GameTooltip:SetOwner(self, "ANCHOR_CURSOR"); GameTooltip:SetHyperlink(link); GameTooltip:Show() end
    end)
    smf:SetScript("OnHyperlinkLeave", function() GameTooltip:Hide() end)
    smf:SetScript("OnMouseWheel", function(self, d)
      if IsShiftKeyDown() then if d > 0 then self:ScrollToTop() else self:ScrollToBottom() end
      else for _ = 1, 3 do if d > 0 then self:ScrollUp() else self:ScrollDown() end end end
    end)
    view.smf = smf
  end
  if view:IsShown() then view:Hide() else view:Show(); Fill(ChatKeeperSearch:GetText()) end
end

-- small magnifier button next to the chat (between the friends and the chat-menu button)
local function OpenSearch()
  if not (view and view:IsShown()) then ToggleView() end
  ChatKeeperSearch:SetFocus(); ChatKeeperSearch:HighlightText()
end
local function CreateSearchButton()
  if ChatKeeperSearchButton then return end
  local menu = ChatFrameMenuButton
  local useMenu = menu and menu:IsShown() and menu:GetNormalTexture()
  local b = CreateFrame("Button", "ChatKeeperSearchButton", UIParent)
  local holder = CreateFrame("Frame", nil, b) -- icon sits on a child frame so it draws above the button art
  holder:SetAllPoints()
  local icon = holder:CreateTexture(nil, "OVERLAY")
  icon:SetTexture("Interface\\Minimap\\Tracking\\None") -- magnifier
  icon:SetDesaturated(true); icon:SetVertexColor(1, .82, 0) -- same yellow as the other chat icons
  if useMenu then
    -- copy the size, frame and highlight of the chat menu (speech bubble) button so it looks the same
    b:SetWidth(menu:GetWidth()); b:SetHeight(menu:GetHeight())
    b:SetFrameStrata(menu:GetFrameStrata()); b:SetFrameLevel(menu:GetFrameLevel())
    b:SetPoint("BOTTOM", menu, "TOP", 0, 2)
    b:SetNormalTexture(menu:GetNormalTexture():GetTexture())
    if menu:GetPushedTexture() then b:SetPushedTexture(menu:GetPushedTexture():GetTexture()) end
    if menu:GetHighlightTexture() then b:SetHighlightTexture(menu:GetHighlightTexture():GetTexture(), "ADD") end
    -- paint over the bubble so only the round frame of the button is left
    local cover = b:CreateTexture(nil, "OVERLAY")
    cover:SetTexture(1, 1, 1, 1); cover:SetGradient("VERTICAL", .02, .02, .02, .10, .09, .07)
    cover:SetPoint("TOPLEFT", 6, -6); cover:SetPoint("BOTTOMRIGHT", -6, 6)
  else
    b:SetWidth(32); b:SetHeight(32)
    b:SetPoint("BOTTOMRIGHT", ChatFrame1, "BOTTOMLEFT", -4, 0)
    b:SetBackdrop({ bgFile = "Interface\\ChatFrame\\ChatFrameBackground", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
      edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    b:SetBackdropColor(.05, .05, .05, 1); b:SetBackdropBorderColor(.6, .6, .6)
    b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
  end
  local function Place(down)
    local o = down and 1 or 0
    icon:ClearAllPoints(); icon:SetPoint("TOPLEFT", 7 + o, -7 - o); icon:SetPoint("BOTTOMRIGHT", -7 + o, 7 - o)
  end
  Place()
  b:SetScript("OnMouseDown", function() Place(true) end)
  b:SetScript("OnMouseUp", function() Place() end)
  b:SetScript("OnClick", OpenSearch)
  b:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetText("Search chat")
    GameTooltip:AddLine("Search the last 7 days of chat (/ck)", 1, 1, 1); GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

SLASH_CHATKEEPER1, SLASH_CHATKEEPER2 = "/chatkeeper", "/ck"
SlashCmdList.CHATKEEPER = function(msg)
  local cmd, arg = msg:lower():match("^(%S*)%s*(.-)$")
  local n = tonumber(arg)
  if cmd == "" then ToggleView()
  elseif (cmd == "off" or cmd == "on") and n then db.off[n] = (cmd == "off") or nil; P("chat tab " .. n .. " logging " .. cmd)
  elseif (cmd == "days" or cmd == "max" or cmd == "replay") and n then db[cmd] = n; Trim(); P(cmd .. " = " .. n)
  elseif cmd == "clear" then wipe(db.lines); sessionStart = 1; P("log cleared")
  elseif cmd == "stats" then
    local b = 0
    for _, l in ipairs(db.lines) do b = b + #l end
    P(format("%d lines, ~%d KB saved", #db.lines, b / 1024))
  else
    P("/ck = open log | /ck stats | /ck off N, /ck on N (chat tab N) | /ck days N | /ck max N | /ck replay N | /ck clear")
  end
end

-- Up/Down arrow keys scroll the chat while the mouse is over it (Shift = jump to top/bottom).
-- Uses temporary override bindings, so outside the chat the arrows still move your character.
local hovered, bound, holdDir, holdT
local function ScrollHovered(dir, jump)
  local f = hovered
  if not f then return end
  if jump then if dir > 0 then f:ScrollToTop() else f:ScrollToBottom() end
  elseif dir > 0 then f:ScrollUp() else f:ScrollDown() end
end
-- called from Bindings.xml; keystate is "down" on press and "up" on release
function ChatKeeper_Key(dir, jump, keystate)
  if keystate == "up" then holdDir = nil; return end
  ScrollHovered(dir, jump)
  if not jump then holdDir, holdT = dir, .35 end
end
BINDING_HEADER_CHATKEEPER = "ChatKeeper"
BINDING_NAME_CHATKEEPER_UP = "Scroll chat up (mouse over chat)"
BINDING_NAME_CHATKEEPER_DOWN = "Scroll chat down (mouse over chat)"
BINDING_NAME_CHATKEEPER_TOP = "Chat to top (mouse over chat)"
BINDING_NAME_CHATKEEPER_BOTTOM = "Chat to bottom (mouse over chat)"

local keys = CreateFrame("Frame")
local function Unbind()
  if bound and not InCombatLockdown() then ClearOverrideBindings(keys); bound = nil end
  holdDir = nil
end
local function Bind()
  if bound or InCombatLockdown() then return end
  SetOverrideBinding(keys, true, "UP", "CHATKEEPER_UP")
  SetOverrideBinding(keys, true, "DOWN", "CHATKEEPER_DOWN")
  SetOverrideBinding(keys, true, "SHIFT-UP", "CHATKEEPER_TOP")
  SetOverrideBinding(keys, true, "SHIFT-DOWN", "CHATKEEPER_BOTTOM")
  bound = true
end
local poll = 0
keys:SetScript("OnUpdate", function(_, el)
  if holdDir then -- holding the key keeps scrolling
    holdT = holdT - el
    if holdT <= 0 then holdT = .05; ScrollHovered(holdDir) end
  end
  poll = poll - el
  if poll > 0 then return end
  poll = .1
  local over
  if view and view:IsVisible() and MouseIsOver(view.smf) then over = view.smf
  else
    for i = 1, NUM_CHAT_WINDOWS do
      local f = _G["ChatFrame" .. i]
      if f and f:IsVisible() and not IsCL(f) and MouseIsOver(f) then over = f; break end
    end
  end
  hovered = over
  if over then Bind() elseif bound then Unbind() end
end)
keys:RegisterEvent("PLAYER_REGEN_DISABLED") -- bindings can't change in combat: drop them just before it starts
keys:SetScript("OnEvent", Unbind)

-- ElvUI has its own (short) chat history; ours replaces it so lines don't show/log twice
local function HookElvUI()
  if elvCH or not ElvUI then return end
  local E = ElvUI[1]
  local ok, CH = pcall(E.GetModule, E, "Chat", true)
  if not ok or not CH then return end
  elvCH = CH
  local orig = CH.DisplayChatHistory
  if orig then
    CH.DisplayChatHistory = function(...)
      if db and db.replay > 0 then return end
      replaying = true
      pcall(orig, ...)
      replaying = false
    end
  end
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("ADDON_LOADED"); ev:RegisterEvent("PLAYER_ENTERING_WORLD")
ev:SetScript("OnEvent", function(self, e, a)
  if e == "ADDON_LOADED" and a == "ElvUI" then HookElvUI()
  elseif e == "ADDON_LOADED" and a == ADDON then
    ChatKeeperDB = ChatKeeperDB or {}
    db = ChatKeeperDB
    for k, v in pairs(defaults) do if db[k] == nil then db[k] = v end end
    db.lines = db.lines or {}
    Trim()
    sessionStart = #db.lines + 1
    for i = 1, NUM_CHAT_WINDOWS do
      local f = _G["ChatFrame" .. i]
      if f then hooksecurefunc(f, "AddMessage", function(_, msg, r, g, b) pcall(Log, i, msg, r, g, b) end) end
    end
    HookElvUI()
  elseif e == "PLAYER_ENTERING_WORLD" then
    self:UnregisterEvent("PLAYER_ENTERING_WORLD")
    -- wait until ElvUI / other chat addons have finished setting up the chat frames
    local wait = 2
    self:SetScript("OnUpdate", function(s, el)
      wait = wait - el
      if wait > 0 then return end
      s:SetScript("OnUpdate", nil)
      AddURLFilter()
      pcall(CreateSearchButton)
      if db.replay > 0 then
        local ok, err = pcall(Restore)
        replaying = false
        if not ok then P("restore failed: " .. tostring(err)) end
      end
    end)
  end
end)
