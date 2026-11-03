-- Wiz-Maxxing: Cheat Engine's speedhack for the Wizard101 bot.
-- Setup.exe's "Cheat Engine speedhack" copies this into Cheat Engine's autorun folder (<Cheat Engine>\autorun\
-- wiz-maxxing.lua), with the bot's PlayerStats.txt written in below. Cheat Engine runs it every time it starts:
--   * It attaches Cheat Engine to Wizard101 (WizardGraphicalClient.exe) once the game is running, and again after
--     the game restarts - only while Cheat Engine has nothing else open (never a process you opened yourself). With
--     two game windows it stays on the one it has, and never moves onto one that ran beside it (another account):
--     when the one it has closes, it waits for a new one. (Started with two already open, it takes the newest.)
--   * The bot's two speedhack keys (its Settings: "...Cheat Engine's walking key" and "...Cheat Engine's 1x key",
--     F13-F24 - no keyboard has them) set the game's speed: the walking key to "...the speed its walking key sets",
--     the 1x key to 1. Read from PlayerStats.txt every 2 s: a change in the bot's Settings needs no restart here.
-- That's all: it reads and writes none of the game's memory itself, and has no other keys. Cheat Engine's own
-- Settings > Hotkeys entries for those keys aren't needed any more. To stop it: delete this file from the autorun
-- folder (Setup puts it back only when you tick "Cheat Engine speedhack" and press Install).

local GAME = "WizardGraphicalClient.exe"
local STATS = [[PLAYERSTATS]]   -- the bot's AutoFarmer\PlayerStats.txt (Setup writes it in)

local wm = {pid = 0, factor = 2, said = {}, beside = {}}

-- The bot's speedhack settings: its PlayerStats.txt's "key:value" lines (";" starts a comment), its defaults where
-- a line isn't there - speedfactor 2, speedkeyfast 2 (F14), speedkeynormal 1 (F13)
local function readSettings()
  local s = {speedfactor = 2, speedkeyfast = 2, speedkeynormal = 1}
  local f = io.open(STATS, "r")
  if f == nil then
    return s
  end
  for line in f:lines() do
    line = line:gsub(";.*", "")
    local k, v = line:match("^%s*([%w_]+)%s*:%s*(%-?%d+%.?%d*)%s*%%?%s*$")
    if k ~= nil and s[k:lower()] ~= nil then
      s[k:lower()] = tonumber(v)
    end
  end
  f:close()
  return s
end

-- F13-F24 by the bot's number for it (1 = F13): its virtual-key code, nil outside 1-12
local function keyOf(n)
  n = math.floor(tonumber(n) or 0)
  if n < 1 or n > 12 then
    return nil
  end
  return 0x7B + n
end

local function setSpeed(speed)
  if getOpenedProcessID() == 0 then
    return
  end
  pcall(speedhack_setSpeed, speed)
end

-- The two keys, made again only when the bot's Settings changed them
local function bindKeys()
  local s = readSettings()
  local fast = keyOf(s.speedkeyfast) or keyOf(2)
  local normal = keyOf(s.speedkeynormal) or keyOf(1)
  local factor = tonumber(s.speedfactor) or 2
  if factor < 1 then
    factor = 1
  elseif factor > 50 then
    factor = 50
  end
  wm.factor = factor
  -- (one key for both: it's the 1x key - never stuck sped up)
  if fast == normal then
    fast = nil
  end
  if wm.fast ~= fast then
    if wm.hkFast ~= nil then
      wm.hkFast.destroy()
      wm.hkFast = nil
    end
    if fast ~= nil then
      wm.hkFast = createHotkey(function() setSpeed(wm.factor) end, fast)
    end
    wm.fast = fast
  end
  if wm.normal ~= normal then
    if wm.hkNormal ~= nil then
      wm.hkNormal.destroy()
      wm.hkNormal = nil
    end
    wm.hkNormal = createHotkey(function() setSpeed(1) end, normal)
    wm.normal = normal
  end
end

-- Wizard101 opened: once it's running with nothing open in Cheat Engine, or when the one it had is gone and a new one
-- runs (the game restarted). Never over a process you opened yourself, and never onto a game window that ran beside
-- the one it had (another account's - it would get the bot's keys): with one of those open, a restart is waited for
local function attach()
  local pid = getProcessIDFromProcessName(GAME)
  if pid == nil or pid == 0 then
    return
  end
  local cur = getOpenedProcessID()
  if cur ~= 0 and cur ~= wm.pid and cur ~= pid then
    return
  end
  -- (Cheat Engine names the newest game window; the process list says which others run. Can't it list them: as
  -- before v1.9.1 - the newest, whenever the one it had isn't it)
  local ok, pl = pcall(getProcesslist)
  if not ok or type(pl) ~= "table" then
    pl = nil
  end
  local function isGame(p)
    return pl ~= nil and type(pl[p]) == "string" and pl[p]:upper() == GAME:upper()
  end
  if pl ~= nil then
    for p in pairs(wm.beside) do
      if not isGame(p) then
        wm.beside[p] = nil
      end
    end
  end
  if cur ~= 0 and (cur == pid or isGame(cur)) then
    -- (the one it had still runs: every other game window is another account's - stay, and never move onto those)
    wm.pid = cur
    for p in pairs(pl or {}) do
      if p ~= cur and isGame(p) then
        wm.beside[p] = true
      end
    end
    return
  end
  if wm.beside[pid] then
    return
  end
  wm.pid = pid
  openProcess(pid)
end

-- (a step that fails says so once - in a box, as Cheat Engine does - then keeps trying quietly)
local function try(what, fn)
  local ok, err = pcall(fn)
  if not ok and not wm.said[what] then
    wm.said[what] = true
    showMessage("Wiz-Maxxing (autorun\\wiz-maxxing.lua): " .. what .. " failed - " .. tostring(err))
  end
end

local function tick()
  try("setting the speed keys", bindKeys)
  try("attaching to Wizard101", attach)
end

wm.timer = createTimer(nil, false)
wm.timer.Interval = 2000
wm.timer.OnTimer = function(sender) tick() end
wm.timer.Enabled = true
tick()
