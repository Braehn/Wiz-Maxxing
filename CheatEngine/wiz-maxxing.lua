-- Wiz-Maxxing: Cheat Engine's speedhack for the Wizard101 bot.
-- Setup.exe's "Cheat Engine speedhack" copies this into Cheat Engine's autorun folder (<Cheat Engine>\autorun\
-- wiz-maxxing.lua), with the bot's PlayerStats.txt written in below. Cheat Engine runs it every time it starts:
--   * It attaches Cheat Engine to Wizard101 (WizardGraphicalClient.exe) once the game is running - the Wizard101
--     window in front, else the newest - and again after that game exits. It stays on a game while it runs: a
--     second Wizard101 starting is left alone. Never over a process you opened yourself.
--   * The bot's two speedhack keys (its Settings: "...Cheat Engine's walking key" and "...Cheat Engine's 1x key",
--     F13-F24 - no keyboard has them) set the speed. The walking key speeds up the Wizard101 window in front - the
--     one the bot walks - to "...the speed its walking key sets": when that's another window than the one Cheat
--     Engine has, that one goes back to 1x first and Cheat Engine moves to the window in front. With no Wizard101 in
--     front it speeds only the one it sped last. So another account's window is never sped up unless the bot walks
--     it. The 1x key sets the one Cheat Engine has back to 1, only when it's sped up (it never switches the speedhack
--     on). Read from PlayerStats.txt every 2 s: a change in the bot's Settings needs no restart here.
--   * Only while the bot's speedhack setting is on ("Walk faster with Cheat Engine's speedhack", speedhack:1 in
--     PlayerStats.txt): switched off there, or never on, the walking key does nothing and no game is attached - a
--     key another program sends (macro keys, a mouse's side buttons, push-to-talk on F13-F24) never speeds a game
--     up. The 1x key stays. The walking key reads the setting again when it's pressed: switched on in Settings, the
--     bot's first press counts, not one 2 s later. PlayerStats.txt that can't be opened (the bot's folder moved or
--     deleted, or a folder name with letters beyond plain English that has no short name) is said once, in a box -
--     the settings read last are kept (none read: the speedhack stays off).
-- That's all: it reads and writes none of the game's memory itself, and has no other keys. Cheat Engine's own
-- Settings > Hotkeys entries for those keys aren't needed any more. To stop it: delete this file from the autorun
-- folder (Setup puts it back only when you tick "Cheat Engine speedhack" and press Install).

local GAME = "WizardGraphicalClient.exe"
local STATS = [[PLAYERSTATS]]   -- the bot's AutoFarmer\PlayerStats.txt (Setup writes it in)

-- pid: the game this script opened or took over; last: the game the walking key sped last; factor: the walking
-- speed; on: the bot's speedhack setting on; unread: PlayerStats.txt not opened that many times in a row; said: the
-- "failed" boxes shown already
local wm = {pid = 0, last = 0, factor = 2, on = false, unread = 0, said = {}}

-- The bot's speedhack settings: its PlayerStats.txt's "key:value" lines (";" starts a comment), its defaults where
-- a line isn't there - speedhack 0 (off, as the bot has it), speedfactor 2, speedkeyfast 2 (F14), speedkeynormal 1
-- (F13). Then false when the file can't be opened (the defaults), and the keys whose lines were there
local function readSettings()
  local s = {speedhack = 0, speedfactor = 2, speedkeyfast = 2, speedkeynormal = 1}
  local seen = {}
  local f = io.open(STATS, "r")
  if f == nil then
    return s, false, seen
  end
  for line in f:lines() do
    line = line:gsub(";.*", "")
    local k, v = line:match("^%s*([%w_]+)%s*:%s*(%-?%d+%.?%d*)%s*%%?%s*$")
    if k ~= nil and s[k:lower()] ~= nil then
      s[k:lower()] = tonumber(v)
      seen[k:lower()] = true
    end
  end
  f:close()
  return s, true, seen
end

-- F13-F24 by the bot's number for it (1 = F13): its virtual-key code, nil outside 1-12
local function keyOf(n)
  n = math.floor(tonumber(n) or 0)
  if n < 1 or n > 12 then
    return nil
  end
  return 0x7B + n
end

-- p a running Wizard101: Cheat Engine's process list names it WizardGraphicalClient.exe. False when the list can't
-- be read
local function isGame(p)
  if type(p) ~= "number" or p <= 0 then
    return false
  end
  local ok, list = pcall(getProcesslist)
  if not ok or type(list) ~= "table" then
    return false
  end
  local name = list[p]
  return type(name) == "string" and name:upper() == GAME:upper()
end

-- The Wizard101 window in front: its process, nil when the window in front isn't a game
local function frontGame()
  local ok, p = pcall(getForegroundProcess)
  if ok and isGame(p) then
    return p
  end
  return nil
end

-- What Cheat Engine has open is the bot's to use: nothing, the game this script opened, or a Wizard101 (one you or
-- Cheat Engine's own attach opened is taken over). Anything else is a process you opened yourself: left alone
local function ours(cur)
  return cur == 0 or cur == wm.pid or isGame(cur)
end

-- The walking key: the Wizard101 window in front sped up to the walking speed - the one the bot walks. When Cheat
-- Engine has another game, that one goes back to 1x first, while Cheat Engine is still on it (a process Cheat Engine
-- leaves keeps its speed), then Cheat Engine moves to the window in front. With no game in front, only the one it
-- sped last, never one the bot hasn't walked. Opened again when Windows didn't let Cheat Engine open it. Nothing
-- with the bot's speedhack setting off - read again now (PlayerStats.txt that can't be opened: as the last tick had
-- it), so the setting just switched on counts at the bot's first press, the tick up to 2 s behind. Only a file with
-- its speedhack line counts here: one the bot is just writing (part of it, or none yet) leaves it as it was
local function walkKey()
  local s, read, seen = readSettings()
  if read and seen.speedhack then
    wm.on = s.speedhack == 1
  end
  if not wm.on then
    return
  end
  local cur = getOpenedProcessID()
  if not ours(cur) then
    return
  end
  local target = frontGame()
  if target == nil then
    if cur ~= wm.last or not isGame(cur) then
      return
    end
    target = cur
  end
  if target ~= cur or getOpenedProcessHandle() == 0 then
    if isGame(cur) and getOpenedProcessHandle() ~= 0 and speedhack_getSpeed() ~= 1 then
      speedhack_setSpeed(1)
    end
    wm.pid = target
    if not openProcess(target) then
      return
    end
  end
  speedhack_setSpeed(wm.factor)
  wm.last = target
end

-- The 1x key: the game Cheat Engine has back to 1x - only when it's sped up: it never switches the speedhack on
-- (that would put it into a game just to set 1x). Never a process you opened yourself
local function normalKey()
  local cur = getOpenedProcessID()
  if cur == 0 or getOpenedProcessHandle() == 0 or not ours(cur) then
    return
  end
  if speedhack_getSpeed() ~= 1 then
    speedhack_setSpeed(1)
  end
end

-- (a step that fails says so once - in a box, as Cheat Engine does - then keeps trying quietly)
local function try(what, fn)
  local ok, err = pcall(fn)
  if not ok and not wm.said[what] then
    wm.said[what] = true
    showMessage("Wiz-Maxxing (autorun\\wiz-maxxing.lua): " .. what .. " failed - " .. tostring(err))
  end
end

-- The two keys, made again only when the bot's Settings changed them - the walking key does nothing while its
-- speedhack setting is off (walkKey). PlayerStats.txt that can't be opened: the keys and the setting as they were
-- (the bot may be just writing it), the first time the defaults (the setting off); still not after 3 tries (6 s):
-- said once, in a box - what to do, and whether the walking key works meanwhile
local function bindKeys()
  local s, read = readSettings()
  if read then
    wm.unread = 0
  else
    wm.unread = wm.unread + 1
    if wm.unread == 3 then
      error("can't open the bot's settings, " .. STATS .. " - the bot's folder moved or deleted, or a folder " ..
        "name with letters beyond plain English? Run the bot's Setup.exe again: tick Cheat Engine speedhack, " ..
        "Install (the bot in a folder named in plain English letters). The bot gone: delete " ..
        "autorun\\wiz-maxxing.lua in Cheat Engine's folder. " ..
        (wm.on and "The walking key keeps the settings read last" or "The walking key does nothing till then"), 0)
    end
    if wm.normal ~= nil then
      return
    end
  end
  wm.on = s.speedhack == 1
  local fast = keyOf(s.speedkeyfast) or keyOf(2)
  local normal = keyOf(s.speedkeynormal) or keyOf(1)
  local factor = tonumber(s.speedfactor) or 2
  if factor < 1 then
    factor = 1
  elseif factor > 50 then
    factor = 50
  end
  wm.factor = factor
  -- (one key for both: it's the 1x key - never stuck sped up. The setting off: the walking key stays, doing nothing -
  -- switched on, the bot's first press works)
  if fast == normal then
    fast = nil
  end
  if wm.fast ~= fast then
    if wm.hkFast ~= nil then
      wm.hkFast.destroy()
      wm.hkFast = nil
    end
    if fast ~= nil then
      wm.hkFast = createHotkey(function() try("the walking key", walkKey) end, fast)
    end
    wm.fast = fast
  end
  if wm.normal ~= normal then
    if wm.hkNormal ~= nil then
      wm.hkNormal.destroy()
      wm.hkNormal = nil
    end
    wm.hkNormal = createHotkey(function() try("the 1x key", normalKey) end, normal)
    wm.normal = normal
  end
end

-- Wizard101 opened when Cheat Engine has none: nothing open, or the one it had has exited - then the Wizard101 window
-- in front, else the newest. It stays on a game while that runs (a second one starting is left alone - the walking
-- key moves it), and never sets a speed. Never over a process you opened yourself, nor with the bot's speedhack
-- setting off
local function attach()
  if not wm.on then
    return
  end
  local cur = getOpenedProcessID()
  if cur ~= 0 and not ours(cur) then
    return
  end
  if isGame(cur) then
    wm.pid = cur
    return
  end
  local pid = frontGame() or getProcessIDFromProcessName(GAME)
  if pid == nil or pid == 0 or pid == cur then
    return
  end
  wm.pid = pid
  openProcess(pid)
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
