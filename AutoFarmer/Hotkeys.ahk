#Warn Unreachable, Off
; Hotkeys.ahk - the bot's keys, yours to change (the dashboard's Keys tab, asked 2026-10-24). Each action's key is kept in
; dashboard.ini [hotkeys] (<id>=<AutoHotkey key name>; none: switched off; not there: its default) and made with the
; Hotkey command at start and whenever it's changed - not hotkey labels in the script any more. Keys the bot presses in
; the game (W A S D, X, Space, Ctrl+O, Ctrl+1-9, Cheat Engine's F13-F24) and plain letters and digits can't be taken.
; AutoHotkey v1.1, #Included by Autofarmer.ahk.

;The keys made now (id -> key name, "" none), the tray menu's items named with them (id -> its name now), the action
;whose key is being caught (Change... on the Keys tab) and its InputHook
global HkOn, HkMenuNames, HkCapId, HkCapHook
;(the modifiers held while a key's caught - by scan code, as they go down and up: read when the key went down, not
;when the end's thread gets to run)
global HkCapMods
;The Keys tab's controls (Dashboard.ahk)
global KeyList, KeyHelp, KeyStatus, KeyChangeBtn, KeyDefaultBtn, KeyNoneBtn, KeyAllBtn

;Every action that has a key: {id, label, def (its key out of the box), ctx (when it works: game - the bot on, or
;Wizard101 in front; front - only with Wizard101 in front, the bot on or not; on - the bot on; "" always; rec - only
;while recording, made by the recorder), run (the label it runs - in Autofarmer.ahk)}
HkActions()
	{
	static list := ""
	if (!IsObject(list))
		list := [V1Obj({id: "bot", label: "The bot on / off", def: "F6", ctx: "game", run: "MenuBotToggle"})
			, V1Obj({id: "walk", label: "Walking on / off", def: "F8", ctx: "game", run: "MenuWalk"})
			, V1Obj({id: "dash", label: "The dashboard (show / hide)", def: "#2", ctx: "", run: "HkDash"})
			, V1Obj({id: "overlay", label: "The overlay over the game on / off (map and log)", def: "#4", ctx: "front", run: "MenuOverlay"})
			, V1Obj({id: "restart", label: "Restart the bot", def: "#1", ctx: "", run: "MenuRestart"})
			, V1Obj({id: "restart2", label: "Restart the bot (a second key)", def: "!Esc", ctx: "", run: "HkRestart2"})
			, V1Obj({id: "quit", label: "Quit the bot", def: "#Esc", ctx: "", run: "HkQuit"})
			, V1Obj({id: "record", label: "Stop recording (a dungeon run, potion buying)", def: "F9", ctx: "rec", run: ""})
			, V1Obj({id: "boss", label: "Pick the boss, then click its name plate (in a battle)", def: "!1", ctx: "on", run: "HkBoss"})
			, V1Obj({id: "boost", label: "Pick who your blades and traps go to (in a battle)", def: "!2", ctx: "on", run: "HkBoost"})
			, V1Obj({id: "player", label: "Pick your own name plate (in a battle)", def: "#3", ctx: "on", run: "HkPlayer"})
			, V1Obj({id: "loop", label: "Loop mode on / off", def: "!e", ctx: "on", run: "HkLoop"})
			, V1Obj({id: "lore", label: "Lore mode on / off", def: "!l", ctx: "on", run: "HkLore"})
			, V1Obj({id: "dual", label: "Dual mode on / off", def: "!d", ctx: "on", run: "HkDual"})
			, V1Obj({id: "carry", label: "Carry mode on / off (two clients: the main wizard - the window in front - passes, the other plays the battles)", def: "!t", ctx: "game", run: "HkCarry"})
			, V1Obj({id: "command", label: "Command mode on / off", def: "!c", ctx: "on", run: "HkCommand"})
			, V1Obj({id: "stats", label: "Statistic mode on / off", def: "!s", ctx: "on", run: "HkStats"})
			, V1Obj({id: "response", label: "Response mode on / off", def: "!r", ctx: "on", run: "HkResponse"})
			, V1Obj({id: "dev", label: "Developer mode on / off", def: "#!d", ctx: "on", run: "HkDev"})]
	return list
	}

HkAction(id)
	{
	for i, a in HkActions()
		if (a.id = id)
			return a
	return ""
	}

;Action id's key now: yours (dashboard.ini), else its default - "" switched off. Not its default when you gave that
;key to another action (one new in an update has a default you may have taken already): none, never taken from it
HkKeyOf(id)
	{
	a := HkAction(id)
	if (!IsObject(a))
		return ""
	k := IniRead(A_ScriptDir "\dashboard.ini", "hotkeys", id, A_Space)
	k := Trim(k)
	if (k = "none")
		return ""
	if (k != "" && HkValid(k))
		return k
	;(its default another action's in dashboard.ini - the Keys tab shows none; the default back once that one's changed)
	sec := ""
	try sec := IniRead(A_ScriptDir "\dashboard.ini", "hotkeys")
	Loop Parse, sec, "`n", "`r"
		{
		p := InStr(A_LoopField, "=")
		if (!p)
			continue
		other := Trim(SubStr(A_LoopField, 1, p - 1))
		if (other != id && IsObject(HkAction(other)) && HkSame(Trim(SubStr(A_LoopField, p + 1)), a.def))
			return ""
		}
	return a.def
	}

;A key name the Hotkey command takes: modifiers (# ^ ! +) and one key
HkValid(k)
	{
	if (!RegExMatch(k, "^([#^!+]*)(.+)$", &m) || m[2] = "")
		return false
	return GetKeyVK(m[2]) || GetKeySC(m[2])
	}

;A key name in words: "#!d" -> "Windows+Alt+D", "" -> "(none)"
HkName(k)
	{
	if (k = "")
		return "(none)"
	RegExMatch(k, "^([#^!+]*)(.+)$", &m)
	t := ""
	Loop Parse, m[1]
		t .= A_LoopField = "#" ? "Windows+" : A_LoopField = "^" ? "Ctrl+" : A_LoopField = "!" ? "Alt+" : "Shift+"
	key := m[2] = "Escape" ? "Esc" : m[2]
	return t (StrLen(key) = 1 ? Format("{:U}", key) : Format("{:T}", SubStr(key, 1, 1)) SubStr(key, 2))
	}

;Action id's key in words - for the messages that say which key to press
HkText(id)
	{
	return HkName(HkKeyOf(id))
	}

;Why key can't be action id's ("" it can): one the bot or the game needs, or another action's
HkRefuse(k, id)
	{
	if (!HkValid(k))
		return "that isn't a key the bot can use"
	RegExMatch(k, "^([#^!+]*)(.+)$", &m)
	mods := m[1], key := m[2]
	low := StrLower(key)
	if (RegExMatch(low, "^f(1[3-9]|2[0-4])$"))
		return HkName(k) " is Cheat Engine's speedhack's (F13-F24)"
	if (InStr(mods, "^") && !InStr(mods, "!") && !InStr(mods, "#") && (low = "o" || RegExMatch(low, "^[1-9]$")))
		return HkName(k) " is the game's (Ctrl+O: a potion, Ctrl+1-9: an Equipment Set - the bot presses those)"
	if (RegExMatch(low, "^(lbutton|rbutton|mbutton|wheel)"))
		return "a mouse button can't be one"
	if ((mods = "" || mods = "+") && (StrLen(low) = 1 || RegExMatch(low, "^(space|enter|tab|escape|esc|backspace|up|down|left|right|delete|home|end|pgup|pgdn|insert|numpad\w+)$")))
		return HkName(k) " is typed in the game or the bot's windows - add Ctrl, Alt or Windows (or take an F key)"
	if (low = "f4" && InStr(mods, "!"))
		return "Alt+F4 closes windows"
	if (InStr(mods, "#") && RegExMatch(low, "^(l|d|e|r|tab|g)$") && StrLen(mods) = 1)
		return HkName(k) " is Windows' own"
	;(the developer's keys, still made in Autofarmer.ahk itself - they'd take it first while the bot's on)
	if (HkSame(k, "!0") || HkSame(k, "#``"))
		return HkName(k) " is the bot's developer key"
	;(the key a recording going on now stops with - kept as it was when it began)
	if ((DgRecording && HkSame(k, DgRecKey)) || (PotionRecording && HkSame(k, PotionStopKey)))
		return HkName(k) " stops the recording going on now - finish it first"
	for i, a in HkActions()
		if (a.id != id && HkSame(HkKeyOf(a.id), k))
			return HkName(k) " is already the key for `"" a.label "`" - change that one first"
	return ""
	}

;The same key, however it's written (modifiers in any order, a letter's case, Esc / Escape)
HkSame(a, b)
	{
	if (a = "" || b = "")
		return false
	return HkNorm(a) = HkNorm(b)
	}

HkNorm(k)
	{
	RegExMatch(k, "^([#^!+]*)(.+)$", &m)
	mods := (InStr(m[1], "#") ? "#" : "") (InStr(m[1], "^") ? "^" : "") (InStr(m[1], "!") ? "!" : "") (InStr(m[1], "+") ? "+" : "")
	n := GetKeyName(m[2])
	n := StrLower(n)
	return mods n
	}

;When an action's key works (the Hotkey command's If): the bot on, or Wizard101 in front (F6 and F8 while it's off -
;standby, paused: only in the game, not taken from other programs); the bot on (the modes and picks: off, their keys
;go to whatever program has them)
HkCtxGame(hk := "")
	{
	return BotOn || WinActive("ahk_exe WizardGraphicalClient.exe")
	}

HkCtxOn(hk := "")
	{
	return BotOn
	}

;Only with Wizard101 in front (the overlay's: Windows+4 isn't taken from your other programs while the bot runs)
HkCtxFront(hk := "")
	{
	return WinActive("ahk_exe WizardGraphicalClient.exe")
	}

;Every action's key made as it's set now - the ones changed taken off first, then the new ones put on (two actions
;swapping keys don't take each other's). $: the bot's own Send never sets one off. A key the Hotkey command won't take:
;said, and that action has none
HkApply()
	{
	static ctx := ""
	global HkOn ; (v1 globals it sets)
	if (!IsObject(ctx))
		ctx := V1Obj({game: HkCtxGame, on: HkCtxOn, front: HkCtxFront})
	if (!IsObject(HkOn))
		HkOn := V1Obj()
	want := V1Obj()
	for i, a in HkActions()
		if (a.ctx != "rec")
			want[a.id] := HkKeyOf(a.id)
	for i, a in HkActions()
		{
		if (a.ctx = "rec" || !HkOn.Has(a.id) || HkOn[a.id] = "" || HkSame(HkOn[a.id], want[a.id]))
			continue
		if (a.ctx != "")
			HotIf(ctx[a.ctx])
		else
			HotIf()
		k := HkOn[a.id]
		HkTry("$" k, "Off")
		HkOn[a.id] := ""
		}
	for i, a in HkActions()
		{
		if (a.ctx = "rec" || want[a.id] = "" || (HkOn.Has(a.id) && HkSame(HkOn[a.id], want[a.id])))
			continue
		if (a.ctx != "")
			HotIf(ctx[a.ctx])
		else
			HotIf()
		k := want[a.id], run := a.run
		;(v1: the label named run, as the hotkey's own thread - HkRun calls the function of that name)
		HkTry("$" k, HkRun.Bind(run), "On")
		if (ErrorLevel)
			{
			DebugLog("Keys: " HkName(k) " couldn't be made " a.label "'s key (" ErrorLevel ") - it has none")
			continue
			}
		HkOn[a.id] := k
		}
	HotIf()
	HkMenuRename()
	}

;v1's Hotkey, key, action, options UseErrorLevel: ErrorLevel 0, or why it couldn't (v2 throws instead) - v1's numbers:
;2 a key it doesn't know, 3 an unsupported prefix key, 4 an AltTab one, 5 no such hotkey, 6 no such variant (its If),
;98 too many hotkeys, 99 out of memory, 1 anything else (v1: no such label)
HkTry(key, action, opts := "")
	{
	global ErrorLevel ; (v1 globals it sets)
	try
		{
		Hotkey(key, action, opts)
		ErrorLevel := 0
		}
	catch as e
		{
		msg := e.Message
		ErrorLevel := (e is MemoryError) ? 99 : InStr(msg, "Nonexistent hotkey variant") ? 6 : InStr(msg, "Nonexistent hotkey") ? 5
			: InStr(msg, "AltTab") ? 4 : InStr(msg, "Unsupported prefix") ? 3 : InStr(msg, "Max hotkeys") ? 98
			: (InStr(msg, "Invalid key name") || InStr(msg, "Invalid hotkey")) ? 2 : 1
		}
	return ErrorLevel
	}

;An action's key pressed: v1's Hotkey ran the action's label (Autofarmer.ahk) as the hotkey's own thread, with its own
;ErrorLevel and A_ThisHotkey - here the function of that name (called with nothing, as v1 ran a label)
HkRun(run, hk := "", *)
	{
	local v1Own := V1Thread()  ; (v1: the hotkey's label ran as a thread of its own - its own ErrorLevel)
	%run%()
	}

;Was the hotkey running now (A_ThisHotkey) one of these actions' (a comma list of ids)?
HkIsAny(hk, ids)
	{
	hk := RegExReplace(hk, "^[$~*]+")
	Loop Parse, ids, ",", A_Space
		if (HkSame(HkKeyOf(A_LoopField), hk))
			return true
	return false
	}

;---- The tray menu's items that say their key ----

;Item id's name now: what it does and its key ("Bot on/off (F6)")
HkMenu(id)
	{
	global HkMenuNames ; (v1 globals it sets)
	if (!IsObject(HkMenuNames))
		HkMenuNames := V1Obj()
	if (!HkMenuNames.Has(id))
		HkMenuNames[id] := HkMenuText(id)
	return HkMenuNames[id]
	}

HkMenuText(id)
	{
	k := HkText(id)
	if (id = "bot")
		return "Bot on/off (" k ")"
	if (id = "walk")
		return "Walking on/off (" k ")"
	if (id = "dash")
		return "Dashboard (" k ")"
	if (id = "overlay")
		return "Overlay over the game on/off (" k ")"
	if (id = "restart")
		return "Restart (" k ")"
	if (id = "quit")
		return "Exit (" k ")"
	if (id = "standby")
		return "Open with Wizard101 (in standby - " HkText("bot") " starts it)"
	return id
	}

;The items renamed after a key's changed (Check / Uncheck find them by HkMenu)
HkMenuRename()
	{
	global ErrorLevel ; (v1 globals it sets)
	if (!IsObject(HkMenuNames))
		return
	for id, was in HkMenuNames.Clone()
		{
		now := HkMenuText(id)
		if (now == was)
			continue
		;(v1: Menu, Tray, UseErrorLevel around it - an item that isn't there only set ErrorLevel 1; v2 throws)
		try
			{
			A_TrayMenu.Rename(was, now)
			ErrorLevel := 0
			}
		catch
			ErrorLevel := 1
		HkMenuNames[id] := now
		}
	}

;---- The Keys tab ----

;The list filled: each action, its key, its default, when it works (the picked one stays picked)
KeyListFill()
	{
	if (!DashHwnd)
		return
	;(v1: Gui, Dash:Default and Gui, Dash:ListView, KeyList for the LV_ functions, the one before put back after - v2
	;names the list it works on: nothing to put back)
	lv := Dash["KeyList"]
	row := lv.GetNext(0), keep := ""
	if (row)
		keep := lv.GetText(row, 5)
	lv.Opt("-Redraw")
	lv.Delete()
	for i, a in HkActions()
		{
		when := a.ctx = "game" ? "the bot on, or in Wizard101" : a.ctx = "front" ? "in Wizard101" : a.ctx = "on" ? "the bot on" : a.ctx = "rec" ? "while recording" : "always"
		k := HkKeyOf(a.id)
		r := lv.Add("", a.label, HkName(k), HkName(a.def) (HkSame(k, a.def) ? "" : "  (changed)"), when, a.id)
		if (a.id = keep)
			lv.Modify(r, "Select Focus")
		}
	lv.Opt("+Redraw")
	}

;The picked action's id ("" none)
KeyPicked()
	{
	if (!DashHwnd)
		return ""  ; (v1: no dashboard - no list, no row picked; Dash is made only by DashInit)
	;(v1: Gui, Dash:ListView, KeyList and back - v2 names the list)
	lv := Dash["KeyList"]
	row := lv.GetNext(0), id := ""
	if (row)
		id := lv.GetText(row, 5)
	return id
	}

KeySay(text)
	{
	;(v1: GuiControl, Dash:, KeyStatus with no dashboard did nothing - Dash is made only by DashInit)
	if (!DashHwnd)
		return
	Dash["KeyStatus"].Value := text
	}

;Action id's key set (k: a key name, "none" switched off, "" its default) - kept in dashboard.ini and made now
KeySet(id, k)
	{
	a := HkAction(id)
	if (!IsObject(a))
		return
	if (k = "")
		V1Do(IniDelete, A_ScriptDir "\dashboard.ini", "hotkeys", id)
	else
		V1Do(IniWrite, k, A_ScriptDir "\dashboard.ini", "hotkeys", id)
	HkApply()
	KeyListFill()
	now := HkKeyOf(id)
	;(Open with Wizard101's shortcut names the bot's key: made again)
	if (id = "bot" && V1IsFunc("WatchIsOn") && WatchIsOn.Call() && V1IsFunc("WatchSet"))
		{
		SplitPath(A_ScriptDir, , &root)
		WatchSet.Call(root, true)
		}
	KeySay(a.label ": " HkName(now) (k = "" ? " (its default)" : ""))
	DebugLog("Keys: " a.label " - " HkName(now) (k = "" ? " (its default)" : ""))
	;(the dashboard's texts that name a key: with the new one)
	if (V1IsFunc("DashKeysChanged"))
		DashKeysChanged.Call()
	}

;Change...: the next key pressed (with Ctrl, Alt, Shift or Windows) caught - 8 s, Esc: not changed. The bot's keys are
;off meanwhile (Suspend) and what's pressed goes nowhere else (the InputHook keeps it)
KeyCapStart(id)
	{
	global HkCapId, HkCapMods, HkCapHook ; (v1 globals it sets)
	a := HkAction(id)
	if (!IsObject(a))
		return KeySay("Pick an action in the list first")
	;(a capture still waiting: stopped without its end running - it would end this new one)
	if (IsObject(HkCapHook))
		{
		HkCapHook.OnEnd := ""
		HkCapHook.Stop()
		}
	HkCapId := id
	KeySay("Press the new key for " a.label " - with Ctrl, Alt, Shift or Windows if you like (Esc: leave it as it is)...")
	Suspend(true)
	;(I: the bot's own Send keys - Cheat Engine's F13-F24, W, X - go by, not caught or held back)
	ih := InputHook("T8 I")
	ih.KeyOpt("{All}", "ES")
	ih.KeyOpt("{F13}{F14}{F15}{F16}{F17}{F18}{F19}{F20}{F21}{F22}{F23}{F24}", "-ES")
	;(v1's {0x1D: ...}: number keys - the scan codes KeyCapMod gets)
	HkCapMods := V1Obj(0x1D, GetKeyState("LControl", "P"), 0x11D, GetKeyState("RControl", "P"), 0x38, GetKeyState("LAlt", "P"), 0x138, GetKeyState("RAlt", "P")
		, 0x2A, GetKeyState("LShift", "P"), 0x36, GetKeyState("RShift", "P"), 0x15B, GetKeyState("LWin", "P"), 0x15C, GetKeyState("RWin", "P"))
	ih.KeyOpt("{LCtrl}{RCtrl}{LAlt}{RAlt}{LShift}{RShift}{LWin}{RWin}", "-E+N")
	ih.OnKeyDown := KeyCapMod.Bind(1)
	ih.OnKeyUp := KeyCapMod.Bind(0)
	ih.OnEnd := KeyCapEnd
	HkCapHook := ih
	ih.Start()
	}

;A modifier going down or up while a key's caught
KeyCapMod(down, ih, vk, sc)
	{
	if (ih == HkCapHook && IsObject(HkCapMods))
		HkCapMods[sc] := down
	}

;The key caught: the modifiers held (as the keyboard has them) and the key - refused if it's one the bot or the game
;needs, or another action's
KeyCapEnd(ih)
	{
	global HkCapHook, HkCapId ; (v1 globals it sets)
	local v1Keep := V1Thread() ; (v1: each thread had its own ErrorLevel)
	;(a capture replaced by a newer Change...: not this one's end)
	if (ih != HkCapHook)
		return
	m := IsObject(HkCapMods) ? HkCapMods : V1Obj()
	win := m[0x15B] || m[0x15C], ctrl := m[0x1D] || m[0x11D], alt := m[0x38] || m[0x138], shift := m[0x2A] || m[0x36]
	Suspend(false)
	HkCapHook := ""
	id := HkCapId, HkCapId := ""
	a := HkAction(id)
	if (!IsObject(a))
		return
	if (ih.EndReason != "EndKey")
		return KeySay(a.label ": not changed (no key in 8 s)")
	key := GetKeyName(Format("vk{:x}sc{:x}", ih.EndVK, ih.EndSC))
	if (key = "")
		key := ih.EndKey
	if (key = "Escape" && !win && !ctrl && !alt && !shift)
		return KeySay(a.label ": not changed")
	k := (win ? "#" : "") (ctrl ? "^" : "") (alt ? "!" : "") (shift ? "+" : "") (StrLen(key) = 1 ? Format("{:L}", key) : key)
	why := HkRefuse(k, id)
	if (why != "")
		return KeySay(a.label ": not changed - " why)
	KeySet(id, k)
	}

KeyChangeClick:
KeyChangeClick()
	return

KeyDefaultClick:
KeyDefaultClick()
	return

KeyNoneClick:
KeyNoneClick()
	return

KeyAllClick:
KeyAllClick()
	return

;(a double-click: Change...)
KeyListEvent:
KeyListEvent()
	return

;###############  V1toV2 FUNCS  ###############
;(the Keys tab's buttons and list - g-labels in v1: Dashboard.ahk binds them, Fn.Bind("Normal") / the list's
;.Bind("DoubleClick"); Info: v1's A_EventInfo)
KeyChangeClick(A_GuiEvent:="", A_GuiControl:="", Info:="", *) { ; V1toV2: Lbl->Func
	global
	KeyCapStart(KeyPicked())
	return
}
;##############################################
KeyDefaultClick(A_GuiEvent:="", A_GuiControl:="", Info:="", *) { ; V1toV2: Lbl->Func
	global
	local v1Own := V1Thread()  ; (v1: a button's thread had its own ErrorLevel - KeySet's V1Do and HkApply set it)
	KeyId := KeyPicked()
	if (KeyId = "")
		{
		KeySay("Pick an action in the list first")
		return
		}
	;(V1At: v1 read a blank where HkAction gave none)
	KeyW := HkRefuse(V1At(HkAction(KeyId), "def"), KeyId)
	if (KeyW != "")
		{
		KeySay(V1At(HkAction(KeyId), "label") ": not changed - " KeyW)
		return
		}
	KeySet(KeyId, "")
	return
}
;##############################################
KeyNoneClick(A_GuiEvent:="", A_GuiControl:="", Info:="", *) { ; V1toV2: Lbl->Func
	global
	local v1Own := V1Thread()  ; (v1: a button's thread had its own ErrorLevel - KeySet's V1Do and HkApply set it)
	KeyId := KeyPicked()
	if (KeyId = "")
		{
		KeySay("Pick an action in the list first")
		return
		}
	if (KeyId = "bot" || KeyId = "quit" || KeyId = "record")
		{
		KeySay(V1At(HkAction(KeyId), "label") " always has a key - change it instead")
		return
		}
	KeySet(KeyId, "none")
	return
}
;##############################################
KeyAllClick(A_GuiEvent:="", A_GuiControl:="", Info:="", *) { ; V1toV2: Lbl->Func
	global
	local v1Own := V1Thread()  ; (v1: a button's thread had its own ErrorLevel - V1Do and HkApply set it)
	msgResult := MsgBox("Put every key back to its default (F6, F8, Alt+1...)?", "Keys", 262180)
	if (msgResult = "No")
		return
	V1Do(IniDelete, A_ScriptDir "\dashboard.ini", "hotkeys")
	HkApply()
	KeyListFill()
	KeySay("Every key back to its default")
	DebugLog("Keys: every key back to its default")
	if (V1IsFunc("DashKeysChanged"))
		DashKeysChanged.Call()
	return
}
;##############################################
KeyListEvent(A_GuiEvent:="", A_GuiControl:="", Info:="", *) { ; V1toV2: Lbl->Func
	global
	;(Info: v1's A_EventInfo - the row double-clicked, 0 none)
	if (A_GuiEvent = "DoubleClick" && Info)
		KeyCapStart(KeyPicked())
	return
}

;(v2 port, CONVENTIONS.md "Blank start": v1 started every variable blank; v2 leaves it unset and throws on
;reading it. The entry script calls this first thing: this file's globals start blank, as in v1)
HotkeysBlank()
	{
	global HkOn := "", HkMenuNames := "", HkCapId := "", HkCapHook := "", HkCapMods := "", KeyList := "", KeyHelp := "", KeyStatus := ""
	global KeyChangeBtn := "", KeyDefaultBtn := "", KeyNoneBtn := "", KeyAllBtn := ""
	}
