"""test_speedhack.py - v1.10.1: Cheat Engine's speedhack on the bot's own game window, two or more open. The bot's
script for Cheat Engine (CheatEngine/wiz-maxxing.lua) run in a fake Cheat Engine, then static pins on its text and on
the bot's side. python3 -m unittest test_speedhack  (from AutoFarmer\\vision)

The scenarios run the real script with Lua 5.3 (Cheat Engine's own Lua) through lupa: pip install lupa. Without it
they're skipped; the static pins need nothing. WIZ_MAXXING_LUA=<file> runs both on another copy of the script (v1.10.0's
fails most scenarios: it follows the newest game and speeds whatever is open).

The rule (TODO.md section 2, "The speedhack on the bot's own game window when two or more are open"):
- the walking key speeds the Wizard101 window in front - the old one back to 1x first, only if Cheat Engine has it
  above 1x. With no game in front, only the one it sped last. Never a process you opened yourself;
- the 1x key acts on the process open and never switches the speedhack on (Cheat Engine injects on the first
  speedhack_setSpeed, even a 1x one: that put it into the other account's game);
- the 2 s timer attaches only: it stays on a running game, and never calls speedhack_*;
- nothing comes up by itself: no print() (it opens Cheat Engine's Lua Engine window), every callback through try().

The fake Cheat Engine follows Cheat Engine's source (master ec45d5f; 7.5 the same on these paths):
- one opened process: openProcess(pid) sets the pid first, then OpenProcess - a denied open leaves that pid with no
  handle and returns nothing (pluginexports.pas:1447-1477, LuaHandler.pas:3273-3302);
- one speedhack object, tied to the pid it was made for. A move to another pid frees it, and its destroy sets 1x only
  on the process open by then - the old process keeps its last speed: the bug (MainUnit.pas:3201-3206, 10974-10981;
  speedhack2.pas:566-579);
- speedhack_setSpeed(x) switches the speedhack on first if it's off - an activation (the DLL injected, or the hooks put
  in) in the process open - and makes the object again when the open pid changed; a failed activation shows Cheat
  Engine's own box: through the checkbox its MessageDlg, and on 7.6+ SpeedhackV3's messageDialog on either path - the
  re-make in btnSetSpeedhack2Click too (pluginexports.pas:2268-2287; MainUnit.pas:10907-10974; SpeedhackV3.lua:47-50,
  314-329);
- speedhack_getSpeed: the object's last speed, 1 with none (speedhack2.pas:584-590);
- getProcesslist (pid -> exe name), getForegroundProcess (garbage with no foreground window: LuaHandler.pas:8257-8270),
  getProcessIDFromProcessName (the last match: pluginexports.pas:1371), createHotkey (a key fires its callback),
  createTimer (a tick fires OnTimer), showMessage (a box), print (the Lua Engine window), and an error out of a callback
  (the Lua Engine window too: LuaHandler.pas:303-389)."""
import os
import re
import shutil
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
AF = os.path.dirname(HERE)              # the AutoFarmer folder
ROOT = os.path.dirname(AF)              # the repository
LUA = os.environ.get('WIZ_MAXXING_LUA') or os.path.join(ROOT, 'CheatEngine', 'wiz-maxxing.lua')
CE_AHK = os.path.join(ROOT, 'CheatEngine.ahk')
SETUP_AHK = os.path.join(ROOT, 'Setup.ahk')
BOT_AHK = os.path.join(AF, 'Autofarmer.ahk')

sys.path.insert(0, HERE)
import test_ahk_names as tan            # noqa: E402  (its AutoHotkey function finder)

try:
    from lupa import lua53
except ImportError:
    lua53 = None

GAME = 'WizardGraphicalClient.exe'
F13, F14, F16, F17 = 0x7C, 0x7D, 0x7F, 0x80      # the bot's defaults: F14 the walking key, F13 the 1x key
BOX = 'Wiz-Maxxing (autorun\\wiz-maxxing.lua): '  # how the script's own box starts (LIVE_CHECKS asks for its text)
OLDER = ("Cheat Engine's Wiz-Maxxing script is older - run Setup.exe, tick Cheat Engine speedhack, Install, then "
         "restart Cheat Engine")
EXPLORER, CEPID, NOTEPAD = 1000, 1100, 1300      # the desktop, Cheat Engine's own window, a process you opened
M, O, M2, O2 = 4100, 5200, 6300, 7400            # the bot's game, the other account's, each restarted


# -- the fake Cheat Engine ---------------------------------------------------------------------------------------------
FAKE_CE = r'''
ce = {
  procs = {},          -- pid -> exe name: the processes that run
  order = {},          -- their pids in the process list's order, the newest last
  inst = {},           -- pid -> which process it is (a pid used again is another process)
  nextInst = 0,
  fg = 0,              -- the foreground window's pid
  noFg = false,        -- no foreground window at all
  garbage = 0x5A5A5A,  -- what getForegroundProcess gives then (its pid isn't initialised)
  opened = 0,          -- processid: getOpenedProcessID, never reset when the process exits
  handle = 0,          -- processhandle: getOpenedProcessHandle
  handleInst = nil,
  nextHandle = 0x200,
  deny = {},           -- pid -> true: OpenProcess fails (an elevated game, Cheat Engine not)
  checked = false,     -- MainForm.cbSpeedhack
  sh = nil,            -- the one TSpeedhack: {pid, inst, last}
  speed = {},          -- pid -> the speed its hooks hold (1 when never sped)
  activations = {},    -- pid -> TSpeedhack.Create in it: the DLL injected (7.4 / 7.5), the hooks put in (7.6+)
  log = {},            -- the script's calls, in order
  boxes = {},          -- showMessage
  ceBoxes = {},        -- Cheat Engine's own boxes: an activation that failed
  luaEngine = {},      -- what opened the Lua Engine window: print(), an error out of a callback or the load
  prints = {},
  forbidden = {},      -- calls the script must never make
  where = "idle",      -- what runs: "load", "timer", "key", "user"
  hotkeys = {},
  timers = {},
  tablesOff = 0,       -- your own table's entries switched off by a move (addresslist.disableAllWithoutExecute)
  fault = {},          -- name -> n: its next n calls raise an error
  listFails = false,   -- getProcesslist raises
}

local function note(kind, pid, x, arg, ok)
  ce.log[#ce.log + 1] = {kind = kind, pid = pid, x = x, arg = arg, ok = ok, where = ce.where, handle = ce.handle}
end

local function fault(name)
  local n = ce.fault[name]
  if n ~= nil and n > 0 then
    ce.fault[name] = n - 1
    error(name .. ": a fault the test put in")
  end
end

-- the opened process can be reached: a handle, to the process it was opened for
local function reach()
  return ce.handle ~= 0 and ce.inst[ce.opened] ~= nil and ce.inst[ce.opened] == ce.handleInst
end

-- TSpeedhack.Create for the process open now (speedhack2.pas:100-563): ends at 1x
local function create()
  if not reach() then
    -- (7.6+: hookSpeedFunctions' messageDialog, whichever path asked - SpeedhackV3.lua:47-50)
    ce.ceBoxes[#ce.ceBoxes + 1] = "SpeedhackV3: no process to hook in " .. tostring(ce.opened)
    error("the speedhack couldn't be activated in " .. tostring(ce.opened))
  end
  ce.activations[ce.opened] = (ce.activations[ce.opened] or 0) + 1
  note("activate", ce.opened)
  ce.speed[ce.opened] = 1
  return {pid = ce.opened, inst = ce.handleInst, last = 1}
end

-- TSpeedhack.setSpeed: in the object's own process, an error when that process is gone
local function shSet(sh, x)
  if ce.inst[sh.pid] == nil or ce.inst[sh.pid] ~= sh.inst then
    error("failure setting the speed")
  end
  ce.speed[sh.pid] = x
  sh.last = x
end

-- FreeAndNil(speedhack): its destroy sets 1x only if its process is still the one open (speedhack2.pas:566-579)
local function free()
  local sh = ce.sh
  ce.sh = nil
  if sh ~= nil and sh.pid == ce.opened then
    pcall(shSet, sh, 1)
  end
end

-- MainForm.cbSpeedhack.Checked := v, and its cbSpeedhackChange (MainUnit.pas:10943-10981)
local setChecked
setChecked = function(v)
  if ce.checked == v then
    return
  end
  ce.checked = v
  if v then
    local ok, err = pcall(function()
      if ce.sh ~= nil then
        free()
      end
      ce.sh = create()
    end)
    if not ok then
      setChecked(false)
      ce.ceBoxes[#ce.ceBoxes + 1] = tostring(err)
    end
  elseif ce.sh ~= nil then
    free()
  end
end

-- ce_openProcess2 (pluginexports.pas:1447-1477): the pid first, then OpenProcess; the epilogue only with a handle
local function ceOpen(pid)
  local old = ce.opened
  ce.opened = pid
  ce.handle = 0
  ce.handleInst = nil
  if ce.procs[pid] ~= nil and not ce.deny[pid] then
    ce.nextHandle = ce.nextHandle + 4
    ce.handle = ce.nextHandle
    ce.handleInst = ce.inst[pid]
    if old ~= 0 and pid ~= old then
      setChecked(false)
      ce.tablesOff = ce.tablesOff + 1
    end
  end
end

local function byName(name)
  for i = #ce.order, 1, -1 do
    local pid = ce.order[i]
    if ce.procs[pid] ~= nil and ce.procs[pid]:upper() == tostring(name):upper() then
      return pid
    end
  end
  return 0
end

function getProcesslist(strings)
  fault("getProcesslist")
  if ce.listFails then
    error("the process list can't be read")
  end
  if strings ~= nil then
    error("getProcesslist(Strings) isn't in this fake")
  end
  local t = {}
  for pid, name in pairs(ce.procs) do
    t[pid] = name
  end
  return t
end

function getForegroundProcess()
  fault("getForegroundProcess")
  note("fg")
  if ce.noFg then
    return ce.garbage
  end
  return ce.fg
end

function getForegroundWindow()
  if ce.noFg then
    return 0
  end
  return ce.fg * 16 + 6
end

function getWindowProcessID(h)
  if h == nil or h == 0 then
    return ce.garbage
  end
  return h // 16
end

function getOpenedProcessID()
  fault("getOpenedProcessID")
  return ce.opened
end

function getOpenedProcessHandle()
  fault("getOpenedProcessHandle")
  return ce.handle
end

function getProcessIDFromProcessName(name)
  fault("getProcessIDFromProcessName")
  note("byname")
  local pid = byName(name)
  if pid ~= 0 then
    return pid
  end
end

function openProcess(x)
  fault("openProcess")
  local pid = 0
  if type(x) == "string" then
    pid = byName(x)
  elseif type(x) == "number" then
    pid = math.tointeger(x) or 0
  end
  if pid ~= 0 then
    ceOpen(pid)
  end
  local ok = ce.handle ~= 0 and ce.opened == pid
  note("open", pid, nil, type(x), ok)
  if ok then
    return true
  end
end

function speedhack_setSpeed(...)
  fault("speedhack_setSpeed")
  local n = select("#", ...)
  local x = ...
  note("set", ce.opened, x)
  if n ~= 1 then
    return
  end
  x = tonumber(x) or 0
  pcall(function()
    if not ce.checked then
      setChecked(true)
    end
    if ce.checked then
      if x ~= x or x == math.huge or x == -math.huge then
        error("not a valid speed")
      end
      if ce.sh ~= nil then
        if ce.sh.pid ~= ce.opened then
          free()
          ce.sh = create()
        end
        shSet(ce.sh, x)
      end
    end
  end)
end

function speedhack_getSpeed()
  fault("speedhack_getSpeed")
  note("get", ce.opened)
  if ce.sh == nil then
    return 1.0
  end
  return ce.sh.last + 0.0
end

function createHotkey(fn, ...)
  local keys = {...}
  if type(keys[1]) == "table" then
    keys = keys[1]
  end
  local h = {keys = keys, OnHotkey = fn, alive = true, DelayBetweenActivate = 0}
  h.destroy = function() h.alive = false end
  h.Destroy = h.destroy
  h.setOnHotkey = function(a, b) h.OnHotkey = b or a end
  ce.hotkeys[#ce.hotkeys + 1] = h
  note("hotkey", nil, keys[1])
  return h
end

function createTimer(...)
  local n = select("#", ...)
  local a, b = ...
  local t = {Interval = 1000, Enabled = true}
  if math.type(a) == "integer" and type(b) == "function" then
    local args = table.pack(select(3, ...))
    t.Interval = a
    t.once = true
    t.OnTimer = function() b(table.unpack(args, 1, args.n)) end
  elseif n >= 2 and b ~= nil then
    t.Enabled = b and true or false
  end
  local function last(...) return select(select("#", ...), ...) end
  t.destroy = function() t.dead = true end
  t.Destroy = t.destroy
  t.setInterval = function(...) t.Interval = last(...) end
  t.setOnTimer = function(...) t.OnTimer = last(...) end
  t.setEnabled = function(...) t.Enabled = last(...) end
  ce.timers[#ce.timers + 1] = t
  return t
end

function showMessage(s)
  note("box")
  ce.boxes[#ce.boxes + 1] = tostring(s)
end

function messageDialog(s, ...)
  note("box")
  ce.boxes[#ce.boxes + 1] = tostring(s)
end

function print(...)
  local t = table.pack(...)
  for i = 1, t.n do
    t[i] = tostring(t[i])
  end
  ce.prints[#ce.prints + 1] = table.concat(t, " ")
  ce.luaEngine[#ce.luaEngine + 1] = "print: " .. table.concat(t, " ")
end

for _, name in ipairs({"writeBytes", "writeSmallInteger", "writeInteger", "writeQword", "writeFloat", "writeDouble",
    "writeString", "writePointer", "autoAssemble", "autoAssembleCheck", "executeCode", "executeCodeEx",
    "executeCodeLocal", "executeCodeLocalEx", "injectDLL", "injectLibrary", "allocateMemory", "deAlloc",
    "registerSymbol", "unregisterSymbol", "registerSpeedhackCallbacks", "setGlobalDelayBetweenHotkeyActivation",
    "setGlobalKeyPollInterval", "shellExecute", "runCommand"}) do
  _G[name] = function() ce.forbidden[#ce.forbidden + 1] = name end
end
MainForm = setmetatable({}, {__index = function(_, k) ce.forbidden[#ce.forbidden + 1] = "MainForm." .. tostring(k) end})

-- Cheat Engine's LuaCaller: an error that gets out of a callback opens the Lua Engine window with it
local function run(fn, ...)
  if type(fn) ~= "function" then
    return
  end
  local ok, err = pcall(fn, ...)
  if not ok then
    ce.luaEngine[#ce.luaEngine + 1] = "error: " .. tostring(err)
  end
end

-- the test's side
function ce.load(text)
  local f, err = load(text, "=wiz-maxxing.lua", "t")
  if f == nil then
    ce.luaEngine[#ce.luaEngine + 1] = "load: " .. tostring(err)
    return false
  end
  ce.where = "load"
  run(f)
  ce.where = "idle"
  return true
end

function ce.press(vk)
  local n = 0
  for _, h in ipairs(ce.hotkeys) do
    if h.alive and #h.keys == 1 and h.keys[1] == vk then
      n = n + 1
      ce.where = "key"
      run(h.OnHotkey or h.onHotkey, h)
      ce.where = "idle"
    end
  end
  return n
end

function ce.tick()
  for _, t in ipairs(ce.timers) do
    if not t.dead and t.Enabled and t.OnTimer ~= nil then
      ce.where = "timer"
      run(t.OnTimer, t)
      ce.where = "idle"
      if t.once then
        t.dead = true
      end
    end
  end
end

function ce.launch(pid, name)
  ce.nextInst = ce.nextInst + 1
  ce.procs[pid] = name
  ce.inst[pid] = ce.nextInst
  for i = #ce.order, 1, -1 do
    if ce.order[i] == pid then
      table.remove(ce.order, i)
    end
  end
  ce.order[#ce.order + 1] = pid
end

function ce.exit(pid)
  ce.procs[pid] = nil
  ce.inst[pid] = nil
  ce.speed[pid] = nil
  for i = #ce.order, 1, -1 do
    if ce.order[i] == pid then
      table.remove(ce.order, i)
    end
  end
end

-- Cheat Engine crashes (no FormClose, so no cbSpeedhack.Checked := False: MainUnit.pas:7751): each game keeps the
-- speed its hooks hold, the keys and the timer die with it, and the next session has nothing open and no object
function ce.crash()
  for _, h in ipairs(ce.hotkeys) do
    h.alive = false
  end
  for _, t in ipairs(ce.timers) do
    t.dead = true
  end
  ce.opened = 0
  ce.handle = 0
  ce.handleInst = nil
  ce.checked = false
  ce.sh = nil
end

-- you open a process in Cheat Engine yourself (or its own auto-attach does)
function ce.userOpen(pid)
  local w = ce.where
  ce.where = "user"
  ceOpen(pid)
  ce.where = w
end

-- you tick Speedhack in Cheat Engine's window and set a speed in the process open (btnSetSpeedhack2Click)
function ce.userSpeed(x)
  local w = ce.where
  ce.where = "user"
  pcall(function()
    if not ce.checked then
      setChecked(true)
    end
    if ce.sh ~= nil then
      if ce.sh.pid ~= ce.opened then
        free()
        ce.sh = create()
      end
      shSet(ce.sh, x)
    end
  end)
  ce.where = w
end
'''


class Rig:
    """one Cheat Engine session with the script loaded, the processes around it, and the bot's keys"""

    def __init__(self, tc, games=(), front=EXPLORER, stats=None, start=True):
        self.tc = tc
        self.L = lua53.LuaRuntime()
        self.L.execute(FAKE_CE)
        self.ce = self.L.globals().ce
        self.dir = tempfile.mkdtemp(prefix='wm_speedhack_')
        tc.addCleanup(shutil.rmtree, self.dir, True)
        self.stats = os.path.join(self.dir, 'PlayerStats.txt')
        self.set_stats(stats or 'speedhack:1\r\nspeedfactor:2\r\nspeedkeyfast:2\r\nspeedkeynormal:1\r\n')
        self.factor = 2
        self.walked = set()
        self.yours = set()                       # processes you sped yourself in Cheat Engine's window
        self.ce.launch(EXPLORER, 'explorer.exe')
        self.ce.launch(CEPID, 'cheatengine-x86_64-SSE4-AVX2.exe')
        for p in games:
            self.ce.launch(p, GAME)
        self.front(front)
        if start:
            self.start()

    def set_stats(self, text):
        with open(self.stats, 'w', newline='') as f:
            f.write(text)

    def start(self):
        """Cheat Engine starts: its autorun runs the script, the way Setup put it there (PlayerStats.txt written in)"""
        with open(LUA, encoding='utf-8', newline='') as f:
            text = f.read()
        self.tc.assertIn('[[PLAYERSTATS]]', text)
        self.tc.assertTrue(self.ce.load(text.replace('[[PLAYERSTATS]]', '[==[' + self.stats + ']==]')),
                           self.lua_list('luaEngine'))

    # -- the world
    def launch(self, pid, front=True, name=GAME):
        self.ce.launch(pid, name)
        if front:
            self.front(pid)

    def close(self, pid, front=EXPLORER):
        self.ce.exit(pid)
        if self.ce.fg == pid:
            self.front(front)

    def front(self, pid):
        """the window in front: a pid, or None for no foreground window at all"""
        self.ce.noFg = pid is None
        self.ce.fg = 0 if pid is None else pid

    def crash_restart(self):
        """Cheat Engine crashes and is started again, the games still running: the script loads afresh"""
        self.ce.crash()
        self.start()

    def user_open(self, pid):
        self.ce.userOpen(pid)

    def user_speed(self, x):
        """you switch Cheat Engine's speedhack on in the process it has open, at x"""
        self.yours.add(int(self.ce.opened))
        self.ce.userSpeed(x)

    def deny(self, pid):
        self.ce.deny[pid] = True

    def fault(self, name, n=1):
        self.ce.fault[name] = n

    def tick(self, n=1):
        for _ in range(n):
            self.ce.tick()

    # -- the bot's keys
    def walk(self, pid, key=F14):
        """the bot walks the Wizard101 window in front (it presses the walking key only then)"""
        self.front(pid)
        self.walked.add(pid)
        return self.ce.press(key)

    def walk_key(self, key=F14):
        """the walking key with whatever is in front (the tray's "press its walking key", focus moved meanwhile)"""
        return self.ce.press(key)

    def onex(self, why='', key=F13):
        """the 1x key - a battle round, you playing, bot off, the bot's stop - with whatever is in front"""
        return self.ce.press(key)

    # -- what happened
    def lua_list(self, name):
        return list(self.ce[name].values())

    def log(self):
        return [{k: e[k] for k in ('kind', 'pid', 'x', 'arg', 'ok', 'where', 'handle')} for e in self.ce.log.values()]

    def mark(self):
        return len(self.ce.log)

    def sets(self, since=0):
        return [(e['pid'], e['x']) for e in self.log()[since:] if e['kind'] == 'set']

    def opens(self, since=0, where=None):
        return [e['pid'] for e in self.log()[since:] if e['kind'] == 'open' and (where is None or e['where'] == where)]

    def opened(self):
        return self.ce.opened

    def activations(self):
        return {int(k): int(v) for k, v in self.ce.activations.items()}

    def speeds(self):
        """every running game's speed"""
        out = {}
        for pid, name in self.ce.procs.items():
            if name.upper() == GAME.upper():
                v = self.ce.speed[pid]
                out[int(pid)] = 1 if v is None else v
        return out

    def tail(self, n=14):
        return '\n'.join('  %(where)s %(kind)s pid=%(pid)s x=%(x)s ok=%(ok)s handle=%(handle)s' % e
                         for e in self.log()[-n:])

    # -- checks
    def assert_speeds(self, want, what=''):
        got = self.speeds()
        self.tc.assertEqual(got, {p: float(v) for p, v in want.items()},
                            '%s: speeds %r, wanted %r (Cheat Engine on %s)\n%s'
                            % (what, got, want, self.opened(), self.tail()))

    def assert_moved(self, old, new, since=0):
        """the move to new: the old window to 1x first (still attached), then openProcess(new), then the walking speed
        on new"""
        seq = [(e['kind'], e['pid'], e['x']) for e in self.log()[since:] if e['kind'] in ('set', 'open')]
        at = [i for i, s in enumerate(seq) if s[:2] == ('open', new)]
        self.tc.assertTrue(at, 'no move to %d\n%s' % (new, self.tail()))
        i = at[-1]
        self.tc.assertGreater(i, 0, 'nothing before the move to %d\n%s' % (new, self.tail()))
        self.tc.assertEqual(seq[i - 1], ('set', old, 1), 'the old window to 1x right before the move\n' + self.tail())
        self.tc.assertLess(i + 1, len(seq), 'no speed after the move\n' + self.tail())
        self.tc.assertEqual(seq[i + 1], ('set', new, self.factor), 'the walking speed right after the move\n'
                            + self.tail())

    def assert_clean(self, boxes=0):
        """nothing came up by itself, the timer and the load set no speed, nothing outside the walked windows was
        sped, and openProcess only ever got a pid"""
        tc = self.tc
        tc.assertEqual(self.lua_list('prints'), [], "print() opens Cheat Engine's Lua Engine window")
        tc.assertEqual(self.lua_list('luaEngine'), [], "Cheat Engine's Lua Engine window came up")
        tc.assertEqual(self.lua_list('ceBoxes'), [], "Cheat Engine's own box came up (an activation that failed)")
        if boxes is not None:
            tc.assertEqual(len(self.lua_list('boxes')), boxes, self.lua_list('boxes'))
        tc.assertEqual(self.lua_list('forbidden'), [], 'calls the script never makes')
        bad = [e for e in self.log() if e['kind'] in ('set', 'get') and e['where'] != 'key']
        tc.assertEqual(bad, [], "speedhack_* outside a key's callback (the timer's or the load's)")
        tc.assertEqual([e for e in self.log() if e['kind'] == 'open' and e['arg'] != 'number'], [],
                       'openProcess gets a pid (a string is a process name to Cheat Engine)')
        stray = set(self.activations()) - self.walked - self.yours
        tc.assertEqual(stray, set(), "Cheat Engine's speedhack put into a process never walked\n" + self.tail())


@unittest.skipUnless(lua53 is not None, "needs lupa (pip install lupa) - Lua 5.3, Cheat Engine's own")
class Scenarios(unittest.TestCase):
    """every order of events with one or two clients, and what the script must do in each. M = the bot's game, O =
    the other account's, M2 / O2 = each started again. Each ends with assert_clean: no print(), no Lua Engine window,
    no box, no speedhack_* from the timer or the load, no activation in a process the bot never walked"""

    def rig(self, games=(), front=EXPLORER, **kw):
        return Rig(self, games, front, **kw)

    def test_one_client(self):
        """as before, but for one thing: a 1x before the first walk no longer switches the speedhack on"""
        r = self.rig([M], M)
        self.assertEqual(r.opened(), M, 'the first tick attaches the game')
        r.onex('a battle round')
        self.assertEqual(r.sets(), [], 'a 1x before the first walk: nothing to set, nothing injected')
        self.assertEqual(r.activations(), {})
        r.walk(M)
        r.assert_speeds({M: 2})
        r.onex('standing')
        r.assert_speeds({M: 1})
        r.walk(M)
        r.onex()
        r.assert_speeds({M: 1})
        r.tick(3)
        self.assertEqual(r.opened(), M)
        self.assertEqual(r.activations(), {M: 1}, 'one activation: Cheat Engine stayed on it')
        r.assert_clean()

    def test_other_account_started_behind_while_the_bot_walks(self):
        r = self.rig([M], M)
        r.walk(M)
        r.launch(O, front=False)
        r.tick(3)
        self.assertEqual(r.opened(), M, 'the timer stays on the game it has (no more moving to the newest)')
        r.assert_speeds({M: 2, O: 1}, 'O started')
        r.onex('a battle round')
        r.assert_speeds({M: 1, O: 1}, 'the battle 1x reached M')
        r.walk(M)
        r.assert_speeds({M: 2, O: 1})
        r.onex()
        r.assert_speeds({M: 1, O: 1})
        self.assertNotIn(O, r.opens())
        r.assert_clean()

    def test_other_account_started_in_front_you_log_in(self):
        r = self.rig([M], M)
        r.walk(M)
        r.launch(O, front=True)
        r.onex("you're playing")
        r.assert_speeds({M: 1, O: 1}, "your input's 1x reached M behind")
        r.tick(3)
        r.walk(M)
        r.assert_speeds({M: 2, O: 1}, 'back in M')
        r.onex()
        self.assertNotIn(O, r.opens())
        r.assert_clean()

    def test_other_account_left_in_front_the_bot_walks_it(self):
        r = self.rig([M], M)
        r.walk(M)
        r.launch(O, front=True)
        r.onex("you're playing")
        r.tick()
        r.walk(O)
        r.assert_speeds({M: 1, O: 2}, 'the speed goes where W goes')
        r.onex()
        r.assert_speeds({M: 1, O: 1})
        r.walk(M)
        r.assert_speeds({M: 2, O: 1})
        r.assert_clean()

    def test_other_account_first_then_the_bots(self):
        r = self.rig([O], O)
        self.assertEqual(r.opened(), O)
        r.onex('a battle round')
        self.assertEqual(r.sets(), [], "the 1x on O switched the speedhack on in it")
        r.launch(M, front=True)
        r.tick(3)
        self.assertEqual(r.opened(), O, 'the timer stays on a running game')
        at = r.mark()
        r.walk(M)
        self.assertEqual(r.sets(at), [(M, 2)], 'no 1x needed on O (never sped): open M, speed M')
        self.assertEqual(r.opens(at), [M])
        r.assert_speeds({M: 2, O: 1})
        r.onex()
        r.assert_speeds({M: 1, O: 1})
        self.assertEqual(r.activations(), {M: 1})
        r.assert_clean()

    def test_one_client_restarts(self):
        r = self.rig([M], M)
        r.walk(M)
        r.onex()
        r.close(M)
        r.onex('the game is gone')
        r.tick()
        r.launch(M2, front=True)
        r.tick()
        self.assertEqual(r.opened(), M2, 'the timer follows the game that restarted')
        r.walk(M2)
        r.assert_speeds({M2: 2})
        r.onex()
        r.assert_speeds({M2: 1})
        r.assert_clean()

    def test_bots_game_closes_while_the_other_runs(self):
        r = self.rig([M, O], M)
        self.assertEqual(r.opened(), M, 'the timer took the game in front')
        r.walk(M)
        r.onex()
        r.close(M, front=O)
        at = r.mark()
        r.tick()
        self.assertEqual(r.opened(), O, 'the one it had exited: the timer attaches the one running')
        self.assertEqual(r.sets(at), [], 'attached with no speed')
        r.onex('a battle round')
        self.assertEqual(r.sets(at), [], 'the 1x on O, never sped: nothing')
        r.walk(O)
        r.assert_speeds({O: 2}, 'the bot plays O now (Reconnect adopted it)')
        r.launch(M2, front=True)
        r.tick(2)
        self.assertEqual(r.opened(), O)
        at = r.mark()
        r.walk(M2)
        r.assert_moved(O, M2, at)
        r.assert_speeds({O: 1, M2: 2})
        r.onex()
        r.assert_speeds({O: 1, M2: 1})
        r.assert_clean()

    def test_bots_game_restarted_beside_the_other(self):
        r = self.rig([M], M)
        r.walk(M)
        r.launch(O, front=False)
        r.onex()
        r.close(M)
        r.tick()
        self.assertEqual(r.opened(), O, 'no game in front: the timer takes the one running')
        r.launch(M2, front=True)
        r.tick(2)
        self.assertEqual(r.opened(), O)
        r.walk(M2)
        r.assert_speeds({O: 1, M2: 2})
        r.onex()
        r.assert_speeds({O: 1, M2: 1})
        self.assertNotIn(O, r.activations())
        r.assert_clean()

    def test_other_account_closes(self):
        r = self.rig([M, O], M)
        r.walk(M)
        r.close(O, front=M)
        r.tick()
        r.walk(M)
        r.assert_speeds({M: 2})
        r.onex()
        r.assert_speeds({M: 1})
        r.assert_clean()

    def test_both_close_the_other_starts_first(self):
        r = self.rig([M, O], M)
        r.walk(M)
        r.onex()
        r.close(M)
        r.close(O)
        r.tick()
        r.launch(O2, front=True)
        r.tick()
        self.assertEqual(r.opened(), O2, 'attached with no speed')
        r.onex('a battle round')
        r.launch(M2, front=True)
        r.tick()
        self.assertEqual(r.opened(), O2)
        r.walk(M2)
        r.assert_speeds({O2: 1, M2: 2})
        r.onex()
        r.assert_speeds({O2: 1, M2: 1})
        self.assertNotIn(O2, r.activations())
        r.assert_clean()

    def test_both_close_the_bots_starts_first(self):
        r = self.rig([M, O], M)
        r.walk(M)
        r.onex()
        r.close(M)
        r.close(O)
        r.tick()
        r.launch(M2, front=True)
        r.tick()
        r.launch(O2, front=False)
        r.tick(3)
        self.assertEqual(r.opened(), M2, 'the timer stays on a running game')
        r.walk(M2)
        r.assert_speeds({M2: 2, O2: 1})
        r.onex()
        self.assertNotIn(O2, r.opens())
        r.assert_clean()

    def test_dual_mode(self):
        """Alt+Tab at every round's end, a forced 1x every battle round: the speed follows the walked window, the
        other at 1x. Every return to a window is a new activation in it (Cheat Engine 7.6+ hooks it again: LIVE_CHECKS
        has an hour of it)"""
        r = self.rig([M, O], M)
        at = r.mark()
        for w in (M, O, M, O, M):
            r.walk(w)
            r.assert_speeds({M: 2 if w == M else 1, O: 2 if w == O else 1}, 'walking %d' % w)
            r.onex('a battle round')
            r.assert_speeds({M: 1, O: 1}, 'after the round')
        self.assertEqual(r.opens(at, 'key'), [O, M, O, M], 'one move per change of the walked window')
        self.assertEqual(r.activations(), {M: 3, O: 2}, 'one activation per return (7.6+: one re-hook)')
        self.assertEqual(len(r.sets(at)), 10, 'one speed per key: a window already at 1x gets no 1x')
        r.assert_clean()

    def test_dual_mode_with_no_1x_between(self):
        """the old window still fast at the move: a 1x press missed while Cheat Engine's main thread was busy (its
        hotkey thread waits for the callback), the tray's walking key"""
        r = self.rig([M, O], M)
        r.walk(M)
        at = r.mark()
        r.walk(O)
        r.assert_moved(M, O, at)
        r.assert_speeds({M: 1, O: 2})
        at = r.mark()
        r.walk(M)
        r.assert_moved(O, M, at)
        r.assert_speeds({M: 2, O: 1})
        r.onex()
        r.assert_speeds({M: 1, O: 1})
        r.assert_clean()

    def test_bot_crash_at_2x_then_a_new_run(self):
        r = self.rig([M], M)
        r.walk(M)
        r.launch(O, front=False)
        r.tick(3)
        self.assertEqual(r.opened(), M, 'the timer keeps a running game')
        r.assert_speeds({M: 2, O: 1}, 'the bot killed at 2x: left fast till its next run')
        r.onex('the new run: a battle round')
        r.assert_speeds({M: 1, O: 1}, "the next run's first 1x resets it")
        r.walk(M)
        r.assert_speeds({M: 2, O: 1})
        r.onex()
        self.assertNotIn(O, r.opens())
        r.assert_clean()

    def test_cheat_engine_crash_at_2x_then_started_again(self):
        """the release notes' "Still possible": a speed an earlier Cheat Engine set reads 1x in a new one, so its 1x
        key leaves that window fast - and puts no speedhack into it just for a 1x - till that game restarts"""
        r = self.rig([M, O], M)
        r.walk(M)
        r.assert_speeds({M: 2, O: 1})
        r.crash_restart()
        self.assertEqual(r.opened(), M, 'the window in front')
        at = r.mark()
        r.onex('a battle round')
        self.assertEqual(r.sets(at), [], 'the 1x key: getSpeed reads 1 in a new Cheat Engine')
        self.assertEqual(r.activations(), {M: 1}, 'no speedhack put in again just to set 1x')
        r.assert_speeds({M: 2, O: 1}, 'left fast')
        r.close(M)
        r.launch(M2)
        r.tick()
        self.assertEqual(r.opened(), M2, 'that game restarted')
        r.walk(M2)
        r.onex()
        r.assert_speeds({M2: 1, O: 1})
        self.assertNotIn(O, r.activations())
        r.assert_clean()

    def test_cheat_engine_starts_with_two_running_the_bots_in_front(self):
        r = self.rig([M, O], M)
        self.assertEqual(r.opened(), M, 'the game in front, not the newest')
        r.walk(M)
        r.assert_speeds({M: 2, O: 1})
        r.onex()
        self.assertNotIn(O, r.opens())
        r.assert_clean()

    def test_cheat_engine_starts_with_two_running_none_in_front(self):
        # (the timer's fallback: getProcessIDFromProcessName, Cheat Engine's last match - the newest)
        r = self.rig([M, O], EXPLORER)
        self.assertEqual(r.opened(), O, 'no game in front: the newest')
        r.onex('a battle round')
        self.assertEqual(r.sets(), [])
        at = r.mark()
        r.walk(M)
        self.assertEqual(r.sets(at), [(M, 2)], 'O never sped: no 1x for it')
        r.assert_speeds({M: 2, O: 1})
        r.onex()
        self.assertEqual(r.activations(), {M: 1})
        r.assert_clean()

    def test_cheat_engine_starts_with_two_running_the_other_in_front(self):
        r = self.rig([M, O], O)
        self.assertEqual(r.opened(), O)
        r.walk(M)
        r.assert_speeds({M: 2, O: 1}, 'the walking key corrects it')
        r.onex()
        r.assert_speeds({M: 1, O: 1})
        self.assertEqual(r.activations(), {M: 1})
        r.assert_clean()

    def test_you_switch_to_the_other_and_back(self):
        r = self.rig([M, O], M)
        r.walk(M)
        r.front(O)
        r.onex("you're playing")
        r.assert_speeds({M: 1, O: 1}, 'the 1x reaches M behind')
        r.walk(O)
        r.assert_speeds({M: 1, O: 2}, 'O left in front: the bot walks it')
        r.front(M)
        r.onex("you're playing")
        r.assert_speeds({M: 1, O: 1})
        r.walk(M)
        r.assert_speeds({M: 2, O: 1})
        r.assert_clean()

    def test_you_switch_between_the_bots_check_and_cheat_engines_poll(self):
        """the race the rule keeps: the bot checked M in front, you switched to O before Cheat Engine's hotkey poll
        (0-100 ms later) - O sped for a moment; your input's 1x ("you're playing") heals it"""
        r = self.rig([M, O], M)
        r.walk(M)
        r.onex()
        r.walked.add(O)
        r.front(O)
        r.walk_key()
        r.assert_speeds({M: 1, O: 2})
        r.onex("you're playing")
        r.assert_speeds({M: 1, O: 1})
        r.assert_clean()

    def test_no_game_in_front_the_one_sped_last(self):
        r = self.rig([M], M)
        r.walk(M)
        r.onex()
        r.front(CEPID)
        r.walk_key()
        r.assert_speeds({M: 2}, "the tray's walking key, Cheat Engine's hotkey box in front")
        r.onex()
        r.front(None)
        r.walk_key()
        r.assert_speeds({M: 2}, 'no foreground window at all')
        r.onex()
        r.assert_speeds({M: 1})
        r.assert_clean()

    def test_no_game_in_front_the_one_sped_last_after_a_move(self):
        r = self.rig([M, O], M)
        r.walk(M)
        r.walk(O)
        r.onex()
        r.front(CEPID)
        r.walk_key()
        r.assert_speeds({M: 1, O: 2}, 'the one sped last is the one it moved to, not the one it left')
        r.onex()
        r.assert_speeds({M: 1, O: 1})
        r.assert_clean()

    def test_no_game_in_front_never_a_game_never_walked(self):
        r = self.rig([O], O)
        r.front(CEPID)
        r.walk_key()
        r.front(None)
        r.walk_key()
        r.front(NOTEPAD)
        r.fault('getForegroundProcess')
        r.walk_key()
        self.assertEqual(r.sets(), [], 'O (never walked) sped')
        r.assert_speeds({O: 1})
        self.assertEqual(r.activations(), {})
        r.assert_clean()

    def test_no_game_in_front_after_the_sped_one_exited(self):
        r = self.rig([M], M)
        r.walk(M)
        r.close(M)
        at = r.mark()
        r.walk_key()
        self.assertEqual(r.sets(at), [], 'a speed for a game that has exited')
        r.assert_clean()

    def test_a_process_you_opened_is_yours(self):
        r = self.rig([M], M)
        r.launch(NOTEPAD, front=False, name='notepad.exe')
        r.user_open(NOTEPAD)
        r.user_speed(3)
        r.walk(M)
        r.onex()
        r.tick(3)
        r.walk_key()
        self.assertEqual(r.opened(), NOTEPAD, 'moved off a process you opened')
        self.assertEqual(r.sets(), [], 'the keys set a speed in a process you opened')
        self.assertEqual(r.ce.speed[NOTEPAD], 3, 'your own speedhack in it, at your speed: the 1x key reset it')
        r.assert_speeds({M: 1})
        r.walked.discard(M)
        r.assert_clean()

    def test_a_wizard101_you_opened_is_taken_over(self):
        r = self.rig([M, O], M)
        r.walk(M)
        r.onex()
        r.user_open(O)
        r.tick(3)
        self.assertEqual(r.opened(), O, 'the timer stays on a running game, even one you opened')
        at = r.mark()
        r.front(CEPID)
        r.walk_key()
        self.assertEqual(r.sets(at), [], 'no game in front, and O is not the one sped last')
        r.walk(M)
        r.assert_speeds({M: 2, O: 1}, 'the next walking key moves back')
        r.onex()
        r.assert_speeds({M: 1, O: 1})
        self.assertNotIn(O, r.activations())
        r.assert_clean()

    def test_cheat_engines_own_attach_moved_it_while_fast(self):
        r = self.rig([M, O], M)
        r.walk(M)
        r.user_open(O)
        r.assert_speeds({M: 2, O: 1}, "Cheat Engine's own move leaves M fast (a hazard of its own)")
        r.walk(M)
        r.assert_speeds({M: 2, O: 1})
        r.onex()
        r.assert_speeds({M: 1, O: 1})
        self.assertNotIn(O, r.activations())
        r.assert_clean()

    def test_open_process_fails(self):
        """an elevated game and Cheat Engine not: openProcess sets the pid, gets no handle, returns nothing. Then
        nothing usable is open: no speed into it (a first activation there shows Cheat Engine's own box).
        The rule says to treat getOpenedProcessHandle() == 0 as not usable; read here as at every key, not only
        right after the openProcess that failed - the next walking key, the same window in front, finds the pid
        already open (no move) and would otherwise speed a process with no handle"""
        r = self.rig([O], O)
        r.deny(M)
        r.launch(M, front=True)
        r.walk(M)
        r.tick(2)
        r.walk(M)
        r.onex()
        r.tick()
        r.walk(M)
        self.assertEqual([e for e in r.log() if e['kind'] == 'set' and e['handle'] == 0], [],
                         'speedhack_setSpeed with no handle open')
        r.assert_speeds({M: 1, O: 1})
        self.assertEqual(r.activations(), {})
        r.assert_clean()

    def test_open_process_fails_the_old_window_first_to_1x(self):
        r = self.rig([O], O)
        r.walk(O)
        r.deny(M)
        r.launch(M, front=True)
        at = r.mark()
        r.walk(M)
        seq = [(e['kind'], e['pid'], e['x']) for e in r.log()[at:] if e['kind'] in ('set', 'open')]
        self.assertEqual(seq[:2], [('set', O, 1), ('open', M, None)], r.tail())
        r.assert_speeds({M: 1, O: 1})
        r.walk(M)
        r.onex()
        self.assertEqual([e for e in r.log() if e['kind'] == 'set' and e['handle'] == 0], [],
                         'speedhack_setSpeed with no handle open')
        r.walk(O)
        r.assert_speeds({M: 1, O: 2}, 'back on O, which can be opened')
        r.assert_clean()

    def test_open_process_fails_the_one_it_had_exited_fast(self):
        """the bot's game exits at 2x and the timer's open of the other is refused: Cheat Engine has O's pid, no
        handle, and still M's speedhack (at 2x - the epilogue runs only with a handle). The 1x key: nothing usable
        open, so nothing - a 1x would make the speedhack again for O, and that fails with Cheat Engine's own box"""
        r = self.rig([M], M)
        r.walk(M)
        r.deny(O)
        r.launch(O, front=False)
        r.close(M)
        r.tick()
        self.assertEqual((r.opened(), r.ce.handle), (O, 0), 'the timer tried O')
        r.onex('the bot stops: its 1x')
        r.walk(O)
        r.onex()
        self.assertEqual([e for e in r.log() if e['kind'] == 'set' and e['handle'] == 0], [],
                         'speedhack_setSpeed with no handle open')
        r.assert_speeds({O: 1})
        r.assert_clean()

    def test_walking_key_attaches_when_nothing_is_open(self):
        r = self.rig([], EXPLORER)
        self.assertEqual(r.opened(), 0)
        r.launch(M, front=True)
        r.walk(M)
        r.assert_speeds({M: 2}, 'sped at once, not after the next tick')
        r.assert_clean()

    def test_an_error_in_a_key_goes_through_try(self):
        r = self.rig([M], M)
        r.fault('getOpenedProcessID')
        r.walk(M)
        self.assertEqual(r.lua_list('luaEngine'), [], "the error got out to Cheat Engine: its Lua Engine window")
        boxes = r.lua_list('boxes')
        self.assertEqual(len(boxes), 1, boxes)
        self.assertTrue(boxes[0].startswith(BOX), boxes)
        r.fault('getOpenedProcessID')
        r.walk(M)
        self.assertEqual(len(r.lua_list('boxes')), 1, 'said once, then quietly')
        r.fault('getOpenedProcessID')
        r.onex()
        self.assertEqual(r.lua_list('luaEngine'), [])
        self.assertLessEqual(len(r.lua_list('boxes')), 2, 'the 1x key: once at most (its own step, or the same)')
        r.fault('getOpenedProcessID')
        r.onex()
        r.walk(M)
        r.assert_speeds({M: 2}, 'the keys still work')
        r.assert_clean(boxes=None)
        self.assertTrue(all(b.startswith(BOX) for b in r.lua_list('boxes')))

    def test_an_error_in_the_timer_goes_through_try(self):
        r = self.rig([M], M)
        r.close(M)
        r.launch(M2, front=True)
        r.fault('getOpenedProcessID')
        r.tick()
        r.fault('getOpenedProcessID')
        r.tick()
        self.assertEqual(len(r.lua_list('boxes')), 1, 'said once')
        r.tick()
        self.assertEqual(r.opened(), M2)
        r.assert_clean(boxes=1)

    def test_process_list_unreadable(self):
        """isGame reads Cheat Engine's process list through pcall: unreadable, nothing counts as a game - so no game
        in front, none sped last: nothing sped, no box (the attach still works: by name)"""
        r = self.rig([M], M, start=False)
        r.ce.listFails = True
        r.start()
        r.walk(M)
        r.onex()
        r.tick(2)
        r.walk(M)
        self.assertEqual(r.sets(), [])
        r.walked.discard(M)
        r.assert_clean()

    def test_settings_speed_and_keys(self):
        r = self.rig([M], M, stats='speedfactor:3\r\nspeedkeyfast:5 ; F17\r\nspeedkeynormal:4\r\n')
        r.factor = 3
        self.assertEqual(r.walk(M, key=F17), 1)
        r.assert_speeds({M: 3})
        self.assertEqual(r.onex(key=F16), 1)
        r.assert_speeds({M: 1})
        self.assertEqual(r.walk(M, key=F14), 0, 'the default walking key, not bound')
        r.set_stats('speedfactor:1.5\r\nspeedkeyfast:5\r\nspeedkeynormal:4\r\n')
        r.tick()
        r.walk(M, key=F17)
        r.assert_speeds({M: 1.5}, 'a Settings change within 2 s')
        r.set_stats('speedfactor:99\r\nspeedkeyfast:5\r\nspeedkeynormal:4\r\n')
        r.tick()
        r.walk(M, key=F17)
        r.assert_speeds({M: 50}, 'at most 50')
        r.set_stats('speedfactor:3\r\nspeedkeyfast:4\r\nspeedkeynormal:4\r\n')
        r.tick()
        self.assertEqual(r.walk(M, key=F16), 1, 'one key for both: the 1x key')
        r.assert_speeds({M: 1}, 'never stuck sped up')
        r.assert_clean()

    def test_the_games_name_in_any_case(self):
        r = self.rig([], EXPLORER)
        r.launch(M, front=True, name=GAME.lower())
        r.tick()
        r.walk(M)
        r.assert_speeds({M: 2}, 'its name as Windows has it, in any case')
        r.assert_clean()

    def test_pid_used_again_within_a_tick(self):
        """a known gap: the game exits and a new one gets its pid within 2 s - Cheat Engine sits on the old process
        (a live check). Pinned only: nothing comes up, nothing else is sped"""
        r = self.rig([M, O], M)
        r.walk(M)
        r.onex()
        r.close(M)
        r.launch(M, front=True)
        r.tick()
        r.walk(M)
        r.onex()
        self.assertNotIn(O, r.activations())
        r.assert_clean()


# -- static pins on the script's text (no Lua needed) ------------------------------------------------------------------
LONG = re.compile(r'\[(=*)\[')
KW = re.compile(r'\b(function|if|do|repeat|end|until)\b')
TOK = re.compile(r'[A-Za-z_]\w*|[(){}\[\],]')


def lua_blank(text, strings=True):
    """the text with its comments (and, with strings, the insides of its strings) blanked: same length, same lines"""
    out, i, n = list(text), 0, len(text)

    def blank(a, b):
        for k in range(a, min(b, n)):
            if out[k] != '\n':
                out[k] = ' '
    while i < n:
        if text.startswith('--', i):
            m = LONG.match(text, i + 2)
            if m:
                j = text.find(']' + m.group(1) + ']', m.end())
                j = n if j < 0 else j + len(m.group(1)) + 2
            else:
                j = text.find('\n', i)
                j = n if j < 0 else j
            blank(i, j)
            i = j
            continue
        c = text[i]
        if c in '"\'':
            j = i + 1
            while j < n and text[j] != c and text[j] != '\n':
                j += 2 if text[j] == '\\' else 1
            if strings:
                blank(i + 1, j)
            i = j + 1
            continue
        m = LONG.match(text, i)
        if m:
            j = text.find(']' + m.group(1) + ']', m.end())
            j = n if j < 0 else j
            if strings:
                blank(m.end(), j)
            i = j + len(m.group(1)) + 2
            continue
        i += 1
    return ''.join(out)


def block_end(code, at):
    """the index just past the end that closes the block opened at at (function / if / do / repeat)"""
    depth = 0
    for m in KW.finditer(code, at):
        depth += 1 if m.group(1) in ('function', 'if', 'do', 'repeat') else -1
        if depth == 0:
            return m.end()
    raise ValueError('no end for the block at %d' % at)


def body_of(code, at):
    """(start, end) of a function's body: after its parameter list, before its closing end"""
    p = code.index(')', code.index('(', at)) + 1
    e = block_end(code, at)
    return p, e - 3


def call_args(code, open_paren):
    """[(start, end)] of a call's arguments, its ( at open_paren; and the index of its )"""
    args, depth, block, start = [], 0, 0, open_paren + 1
    for m in TOK.finditer(code, open_paren + 1):
        t = m.group(0)
        if t in ('function', 'if', 'do', 'repeat'):
            block += 1
        elif t in ('end', 'until'):
            block -= 1
        elif t in '([{':
            depth += 1
        elif t in ')]}':
            if depth == 0 and block == 0:
                args.append((start, m.start()))
                return args, m.start()
            depth -= 1
        elif t == ',' and depth == 0 and block == 0:
            args.append((start, m.start()))
            start = m.end()
    raise ValueError('no ) for the call at %d' % open_paren)


class LuaText:
    """the script's functions by name, its hotkeys and timer, and its text with helper calls expanded"""

    def __init__(self, text):
        self.text = text
        self.plain = lua_blank(text, strings=False)    # no comments
        self.code = lua_blank(text)                    # no comments, no string contents
        self.code_h, self.plain_h = list(self.code), list(self.plain)   # the same, the createHotkey calls blanked
        for m in re.finditer(r'\bcreateHotkey\s*\(', self.code):
            _, close = call_args(self.code, m.end() - 1)
            for k in range(m.start(), close + 1):
                if self.code[k] != '\n':
                    self.code_h[k] = self.plain_h[k] = ' '
        self.code_h, self.plain_h = ''.join(self.code_h), ''.join(self.plain_h)
        self.funcs = {}
        for m in re.finditer(r'\bfunction\b', self.code):
            before = self.code[max(0, m.start() - 80):m.start()]
            after = re.match(r'\s*([A-Za-z_][\w.:]*)\s*\(', self.code[m.end():])
            name = None
            if after:
                name = after.group(1)
            else:
                b = re.search(r'([A-Za-z_][\w.]*)\s*=\s*$', before)
                if b:
                    name = b.group(1)
            if name and name not in self.funcs:
                self.funcs[name] = body_of(self.code, m.start())

    def function_arg(self, a, b):
        """the body range of a callback argument: an inline function, or a function's name"""
        s = self.code[a:b].strip()
        if s.startswith('function'):
            at = a + self.code[a:b].index('function')
            return body_of(self.code, at)
        return self.funcs.get(s)

    def hotkeys(self):
        """[(key argument, callback body range, start of the call)] for every createHotkey"""
        out = []
        for m in re.finditer(r'\bcreateHotkey\s*\(', self.code):
            args, _ = call_args(self.code, m.end() - 1)
            line = self.code[self.code.rfind('\n', 0, m.start()) + 1:m.start()]
            key = self.code[args[-1][0]:args[-1][1]].strip() + ' ' + line.strip()
            out.append((key, self.function_arg(*args[0]), m.start()))
        return out

    def hotkey(self, which):
        hits = [h for h in self.hotkeys() if re.search(r'\b%s\b|hk%s' % (which, which.title()), h[0], re.I)]
        return hits[0][1] if len(hits) == 1 else None

    def expand(self, a, b, seen=(), skip=('try',), hide=False):
        """the text from a to b with every reference to one of the script's own functions replaced by its body (with
        hide, the createHotkey calls left out: what runs on the timer, not in a key)"""
        code, plain = (self.code_h, self.plain_h) if hide else (self.code, self.plain)
        out, pos = [], a
        for m in re.finditer(r'(?<![\w.:])([A-Za-z_]\w*)\b', code[a:b]):
            name = m.group(1)
            if name in self.funcs and name not in seen and name not in skip:
                s = a + m.start()
                out.append(plain[pos:s])
                fa, fb = self.funcs[name]
                out.append(' (' + self.expand(fa, fb, seen + (name,), skip, hide) + ') ')
                pos = a + m.end()
        out.append(plain[pos:b])
        return ''.join(out)

    def only_try(self, a, b, depth=0):
        """the body is nothing but try(...) calls (or a call of a function that is)"""
        s, ok = a, False
        while True:
            m = re.compile(r'\s*;?\s*').match(self.code, s)
            s = m.end()
            if s >= b:
                return ok
            t = re.compile(r'(try|[A-Za-z_]\w*)\s*\(').match(self.code, s)
            if not t:
                return False
            _, close = call_args(self.code, t.end() - 1)
            if t.group(1) != 'try':
                f = self.funcs.get(t.group(1))
                if depth > 1 or f is None or not self.only_try(f[0], f[1], depth + 1):
                    return False
            ok = True
            s = close + 1


def read_text(path):
    with open(path, encoding='utf-8', errors='replace') as f:
        return f.read()


class ScriptText(unittest.TestCase):
    """the order inside the walking key, the 1x key's guard, a timer that sets no speed, every callback through
    try(), no print(), nothing written - read from the text, no Lua needed (the keys found as bindKeys makes them:
    createHotkey(..., fast) and createHotkey(..., normal))"""

    @classmethod
    def setUpClass(cls):
        with open(LUA, 'rb') as f:
            cls.raw = f.read()
        cls.lua = LuaText(read_text(LUA))

    def key_text(self, which):
        rng = self.lua.hotkey(which)
        self.assertIsNotNone(rng, 'the %s key\'s createHotkey (its key "%s", as bindKeys has it)' % (which, which))
        return self.lua.expand(*rng)

    def test_plain_ascii(self):
        self.assertTrue(all(b < 128 for b in self.raw), 'Cheat Engine reads autorun files by the old code page')

    def test_the_playerstats_token(self):
        self.assertRegex(self.lua.plain, r'\bSTATS\s*=\s*\[\[PLAYERSTATS\]\]', 'Setup writes the path in for it')

    def test_no_print(self):
        self.assertNotRegex(self.lua.code, r'(?<![\w.:])print\b', "print() opens Cheat Engine's Lua Engine window")

    def test_walking_key_order(self):
        t = self.key_text('fast')
        guard = re.search(r'speedhack_getSpeed\(\)\s*~=\s*1\b', t)
        self.assertIsNotNone(guard, 'the old window to 1x only if Cheat Engine has it above 1x')
        op = re.compile(r'\bopenProcess\(').search(t, guard.end())
        self.assertIsNotNone(op, 'openProcess after the 1x')
        self.assertIsNotNone(re.compile(r'\bspeedhack_setSpeed\(\s*wm\.factor\s*\)').search(t, op.end()),
                             'the walking speed after the move')
        self.assertRegex(t, r'\bgetForegroundProcess\b', 'the window in front')
        self.assertRegex(t, r'\bgetOpenedProcessHandle\(\)\s*[=~]=\s*0', 'no handle: nothing usable open')

    def test_every_1x_is_guarded(self):
        """a speedhack_setSpeed that can switch the speedhack on just to set 1x: every one in the 1x key, the 1x ones
        in the walking key (the old window's), each inside an if on speedhack_getSpeed() ~= 1"""
        for which, call in (('normal', r'\bspeedhack_setSpeed\b'),
                            ('fast', r'\bspeedhack_setSpeed\(\s*1\s*\)|\bpcall\(\s*speedhack_setSpeed\s*,\s*1\s*\)')):
            t = self.key_text(which)
            hits = list(re.finditer(call, t))
            if which == 'normal':
                self.assertTrue(hits)
            for m in hits:
                cond = t[:m.start()][t[:m.start()].rfind('if '):]
                self.assertRegex(cond, r'speedhack_getSpeed\(\)\s*~=\s*1\b',
                                 'a speedhack_setSpeed that can switch the speedhack on (the %s key)' % which)

    def test_1x_key_never_moves_or_speeds(self):
        t = self.key_text('normal')
        self.assertRegex(t, r'speedhack_getSpeed\(\)\s*~=\s*1\b')
        self.assertNotRegex(t, r'\bopenProcess\(|\bwm\.factor\b')

    def test_the_timer_sets_no_speed(self):
        m = re.search(r'\.OnTimer\s*=', self.lua.code)
        self.assertIsNotNone(m)
        rng = self.lua.function_arg(m.end(), self.lua.code.index('\n', m.end()))
        self.assertIsNotNone(rng, 'OnTimer is a function')
        t = self.lua.expand(*rng, hide=True)
        # (a speed set on the timer could run a key's callback in the middle of it: Cheat Engine 7.4 / 7.5's
        # activation waits with CheckSynchronize on the main thread)
        self.assertNotRegex(t, r'\bspeedhack_', 'the timer calls speedhack_*')
        self.assertIn('attach', self.lua.funcs)
        self.assertNotRegex(self.lua.expand(*self.lua.funcs['attach']), r'\bspeedhack_')
        self.assertRegex(self.lua.expand(*self.lua.funcs['attach']), r'\bgetProcessIDFromProcessName\(')

    def test_every_callback_through_try(self):
        hk = self.lua.hotkeys()
        self.assertGreaterEqual(len(hk), 2)
        for key, rng, at in hk:
            self.assertIsNotNone(rng, 'a createHotkey callback: ' + key)
            self.assertTrue(self.lua.only_try(*rng), 'a key whose callback is not all inside try(): ' + key)
        m = re.search(r'\.OnTimer\s*=', self.lua.code)
        rng = self.lua.function_arg(m.end(), self.lua.code.index('\n', m.end()))
        self.assertTrue(self.lua.only_try(*rng), 'the timer: not all inside try()')

    def test_reads_only(self):
        c = self.lua.code
        for bad in (r'\bwrite\w*\s*\(', r'\bautoAssemble', r'\bexecuteCode', r'\binject', r'\bregisterSymbol',
                    r'\bunregisterSymbol', r'\bregisterSpeedhackCallbacks', r'\ballocateMemory',
                    r'\bsetGlobalDelayBetweenHotkeyActivation', r'\bsetGlobalKeyPollInterval', r'\bMainForm\b',
                    r'\bcbSpeedhack\b', r'\bos\.(execute|remove|rename)', r'\bio\.(popen|write|output)',
                    r'\bshellExecute', r'\brunCommand'):
            self.assertNotRegex(c, bad)
        opens = re.findall(r'\bio\.open\s*\(([^)]*)\)', self.lua.plain)
        self.assertTrue(opens)
        for a in opens:
            self.assertRegex(a, r',\s*"rb?"\s*$', 'io.open only to read: ' + a)

    def test_header_says_the_rule(self):
        head = re.match(r'(?:--[^\n]*\n)+', read_text(LUA)).group(0)
        self.assertRegex(head, r'(?i)\bin front\b', 'the window in front at the walking key')
        self.assertRegex(head, r'(?i)walking key')


# -- static pins on the bot's side ------------------------------------------------------------------------------------
def ahk_uncomment(line):
    """an AutoHotkey line without its ; comment (one after a space or a tab, outside a "string")"""
    inq, i = False, 0
    while i < len(line):
        c = line[i]
        if c == '`':
            i += 2
            continue
        if c == '"':
            inq = not inq
        elif c == ';' and not inq and (i == 0 or line[i - 1] in ' \t'):
            return line[:i]
        i += 1
    return line


def ahk_function(path, name):
    """(raw body lines, code body lines) of an AutoHotkey function, None if it isn't there"""
    text = tan.read(path)
    raw = text.splitlines()
    for fname, params, at, body in tan.functions(text):
        if fname == name:
            return [raw[n - 1] for n, _ in body], [c for _, c in body]
    return None


class BotSide(unittest.TestCase):
    """Setup's script text built in CheatEngine.ahk (CeScriptText), used by Setup and by the bot, whose
    SpeedCheatEngine says once a run, in debug.log only, that Cheat Engine's copy is older (a new script reaches
    Cheat Engine only through Setup: the Updater never touches its autorun folder)"""

    def test_the_text_is_built_in_cheat_engine_ahk(self):
        f = ahk_function(CE_AHK, 'CeScriptText')
        self.assertIsNotNone(f, 'CheatEngine.ahk: CeScriptText()')
        raw = '\n'.join(f[0])
        for must in ('[[PLAYERSTATS]]', '"[==["', '"]==]"', 'StrReplace(', 'A_LoopFileShortPath', '[^\\x01-\\x7F]',
                     'CheatEngine\\wiz-maxxing.lua', 'AutoFarmer\\PlayerStats.txt', '"UTF-8"'):
            self.assertIn(must, raw)

    def test_setup_uses_it(self):
        text = tan.read(SETUP_AHK)
        code = '\n'.join(tan.code_lines(text))
        self.assertRegex(code, r'\bCeScriptText\(')
        own = [ln for ln in text.splitlines() if 'StrReplace(' in ln and '[[PLAYERSTATS]]' in ln]
        self.assertEqual(own, [], 'Setup builds the text itself again')
        self.assertRegex(text, r'(?m)^#Include "%A_ScriptDir%\\CheatEngine\.ahk"')
        su = ahk_function(SETUP_AHK, 'SuCeScript')
        if su is not None:
            self.assertRegex('\n'.join(su[1]), r'\bCeScriptText\(')

    def test_the_bot_compares_the_installed_copy(self):
        f = ahk_function(BOT_AHK, 'SpeedCheatEngine')
        self.assertIsNotNone(f)
        raw, code = '\n'.join(f[0]), '\n'.join(f[1])
        self.assertRegex(tan.read(BOT_AHK), r'(?m)^#Include "%A_ScriptDir%\\\.\.\\CheatEngine\.ahk"')
        for must in (r'\bCeScriptText\(', r'\bCeScriptPath\(', r'\b(V1)?FileRead\('):
            self.assertRegex(code, must)
        # the same compare Setup makes (== / !==, case and all): older exactly when Setup ticks the box again
        self.assertRegex(code, r'!==|[^:!<>=]==')
        # (said when the installed copy differs from the one this bot's Setup would put in - built from the bot's
        # own folder, AutoFarmer's parent, as Setup builds it from its folder)
        self.assertRegex(raw, r'SplitPath\(A_ScriptDir, , &(\w+)\)\s*(\w+) := CeScriptText\(\1\)\s*'
                               r'if \(\2 != "" && V1FileRead\(CeScriptPath\(sceDir\), "UTF-8"\) !== \2\)\s*'
                               r'DebugLog\(')
        self.assertIn('return CeScriptText(A_ScriptDir)', tan.read(os.path.join(ROOT, 'Setup.ahk')))
        self.assertIn(OLDER, raw)

    def test_the_older_note(self):
        f = ahk_function(BOT_AHK, 'SpeedCheatEngine')
        self.assertIsNotNone(f)
        raw, code = f
        line = [i for i, ln in enumerate(raw) if OLDER in ln]
        self.assertEqual(len(line), 1, 'one line says it')
        said = raw[line[0]]
        self.assertRegex(said, r'\bDebugLog\(', 'debug.log only')
        self.assertNotIn('\\', said, 'a path in the note')
        self.assertNotRegex(said, r'(?i)\bsceDir\b|\bCeDir\(|\bCeScriptPath\(|\bCeExe\(|\bA_ScriptDir\b|'
                                  r'\bA_WorkingDir\b|\bA_ProgramFiles\b|\bA_AppData\b|LOCALAPPDATA',
                            'a full path in debug.log')
        body = '\n'.join(code)
        self.assertNotRegex(body, r'\b(MsgBox|TrayTip|ToolTip|SoundBeep|WinActivate|Gui)\(',
                            'SpeedCheatEngine shows nothing: debug.log only (nothing takes the focus)')
        statics = []
        for ln in code:
            m = re.match(r'\s*static\s+(.*)$', ln)
            if m:
                statics += re.findall(r'(?:^|,)\s*([A-Za-z_]\w*)', re.sub(r':=[^,]*', '', m.group(1)))
        once = [s for s in statics if s.lower() != 'saidnoscript'
                and re.search(r'(?i)\b%s\s*:=\s*(true|1)\b' % s, body)
                and re.search(r'(?i)(!\s*%s\b|\b%s\s*=\s*(false|0)\b|\bif\s*\(?\s*%s\b)' % (s, s, s), body)]
        self.assertTrue(once, 'once a run: a static flag, set and tested (SpeedCheatEngine runs at each start '
                              'and each time Settings switches the speedhack on)')
        first = min(i for i, c in enumerate(code) if not re.match(r'\s*static\b', c)
                    and any(re.search(r'(?i)\b%s\b' % s, c) for s in once))
        self.assertLessEqual(first, line[0], 'the flag tested before the note')

    def test_the_bots_folder_not_through_dotdot(self):
        """CeScriptText writes <folder>\\AutoFarmer\\PlayerStats.txt into the text: from the bot (AutoFarmer\\), its
        folder must be the plain parent - "AutoFarmer\\.." would make a text Setup never wrote: "older" every run"""
        f = ahk_function(BOT_AHK, 'SpeedCheatEngine')
        calls = [ahk_uncomment(c) for c in f[0] if 'CeScriptText(' in ahk_uncomment(c)]
        self.assertTrue(calls)
        cst = ahk_function(CE_AHK, 'CeScriptText')
        own = [ahk_uncomment(c) for c in cst[0]] if cst else []
        norm = re.search(r'GetFullPathName|A_LoopFileFullPath', '\n'.join(own))
        for c in calls + own:
            if '..' in c and not norm:
                self.fail('a path through ".." for the bot\'s folder: ' + c.strip())


if __name__ == '__main__':
    unittest.main()
