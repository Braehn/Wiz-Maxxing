#Warn Unreachable, Off
; Watch.ahk - "Open with Wizard101": a watcher started with Windows (a shortcut in your Startup folder to
; Wiz-Maxxing.exe /watch) opens the bot when Wizard101 starts - in standby: it does nothing (no battles, walking
; or potions) till you press F6. AHK v1.1, functions and labels only; #Included by Wiz-Maxxing.ahk (the watcher
; itself), Setup.ahk ("Open with Wizard101") and AutoFarmer\Autofarmer.ahk (its tray menu's "Open with Wizard101").
;
; The watcher looks every 3 s whether Wizard101 (WizardGraphicalClient.exe) is running. A game it hasn't seen yet
; (a new process) with no bot running: the update check (it asks only if there's a newer release), then the bot in
; standby (AutoFarmer\Autofarmer.exe /standby). A bot already running (from any folder) is left alone - never a
; second one. One watcher at a time. Its tray icon: stop watching, or don't open with Wizard101 any more.
; While no bot runs it also shows a Wizard101 the bot put in the tray and left hidden (WatchTrayBack).

;How one of the bot's programs is started - rel: its path without .exe / .ahk (e.g. ...\AutoFarmer\Autofarmer):
;{target, args}. Started as a script ourselves (AutoHotkey running a .ahk - Windows 11's Smart App Control blocks
;the bot's unsigned exes, AutoHotkey itself it lets run): its script, by this same AutoHotkey. Else its exe - or
;its script when there's no exe
BotProgram(rel, args := "")
	{
	if (!A_IsCompiled && FileExist(rel ".ahk"))
		return V1Obj({target: A_AhkPath, args: "`"" rel ".ahk`"" (args = "" ? "" : " " args)})
	if (FileExist(rel ".exe"))
		return V1Obj({target: rel ".exe", args: args})
	return V1Obj({target: rel ".ahk", args: args})
	}

;Starts it (BotProgram) in dir. False if Windows wouldn't (A_LastError says why)
BotRun(rel, args, dir)
	{
	p := BotProgram(rel, args)
	V1Run("`"" p.target "`"" (p.args = "" ? "" : " " p.args), dir)
	return !ErrorLevel
	}

;The Startup folder's shortcut that starts the watcher with Windows
WatchLink()
	{
	return A_Startup "\Wiz-Maxxing (opens with Wizard101).lnk"
	}

;"Open with Wizard101" on: the shortcut is there
WatchIsOn()
	{
	return FileExist(WatchLink()) != ""
	}

;root: the bot's folder (where Wiz-Maxxing.exe is). wantOn: the Startup shortcut made, and the watcher started now
;(not only at the next sign-in); off: the shortcut deleted and a running watcher closed. True if done
WatchSet(root, wantOn)
	{
	global ErrorLevel ; (v1 globals it sets)
	link := WatchLink()
	if (wantOn)
		{
		p := BotProgram(root "\Wiz-Maxxing", "/watch")
		V1Do(FileCreateShortcut, p.target, link, root, p.args, "Opens the Wizard101 bot when Wizard101 starts (in standby - " WatchBotKey(root "\AutoFarmer") " starts it)")
		if (ErrorLevel)
			return false
		if (!WatchPids().Length)
			BotRun(root "\Wiz-Maxxing", "/watch", root)
		return true
		}
	V1Do(FileDelete, link)
	DetectHiddenWindows(true)
	for i, pid in WatchPids()
		{
		;(v1: WinClose of a window that's gone meanwhile did nothing - v2 throws)
		try WinClose("ahk_pid " pid " ahk_class AutoHotkey")
		ErrorLevel := ProcessWaitClose(pid, 3)
		if (ErrorLevel)
			ErrorLevel := ProcessClose(pid)
		}
	return !FileExist(link)
	}

;The running watchers' pids: Wiz-Maxxing.exe /watch, or AutoHotkey running Wiz-Maxxing.ahk /watch
WatchPids()
	{
	pids := []
	for p in ComObjGet("winmgmts:").ExecQuery("SELECT ProcessId, CommandLine FROM Win32_Process WHERE CommandLine LIKE '%Wiz-Maxxing%/watch%'")
		if (p.ProcessId != DllCall("GetCurrentProcessId") && RegExMatch(p.CommandLine, "i)Wiz-Maxxing\.(exe|ahk)`"?\s+/watch\b"))
			pids.Push(p.ProcessId)
	return pids
	}

;Whether the bot (AutoFarmer\Autofarmer.exe or .ahk, from any folder) is running - or the quest walker on its own
;(AutoQuester: a bot next to it would take its F8): their hidden AutoHotkey windows
WatchBotRunning()
	{
	DetectHiddenWindows(true)
	SetTitleMatchMode(2)
	return WinExist("\Autofarmer. ahk_class AutoHotkey") || WinExist("\AutoQuester. ahk_class AutoHotkey")
	}

;After an update: a new watcher from the new Wiz-Maxxing.exe (it waits for this one's mutex), this one goes
WatchRestart()
	{
	BotRun(A_ScriptDir "\Wiz-Maxxing", "/watch", A_ScriptDir)
	ExitApp()
	}

;The bot's on/off key in words, for the texts here - F6 out of the box, yours from the dashboard's Keys tab (dir: the
;AutoFarmer folder, its dashboard.ini [hotkeys] bot). In the bot: Hotkeys.ahk's HkText; the watcher and Setup.ahk
;don't have it, so it's read here
WatchBotKey(dir)
	{
	;(by its name: the watcher and Setup don't have HkText - a plain HkText there would be a load-time warning)
	if (V1IsFunc("HkText"))
		{
		hk := "HkText"
		return %hk%("bot")
		}
	k := IniRead(dir "\dashboard.ini", "hotkeys", "bot", A_Space)
	k := Trim(k)
	if (k = "none")
		return "(none)"
	if (!RegExMatch(k, "^([#^!+]*)(.+)$", &m) || !(GetKeyVK(m[2]) || GetKeySC(m[2])))
		return "F6"
	t := ""
	Loop Parse, m[1]
		t .= A_LoopField = "#" ? "Windows+" : A_LoopField = "^" ? "Ctrl+" : A_LoopField = "!" ? "Alt+" : "Shift+"
	key := m[2] = "Escape" ? "Esc" : m[2]
	return t (StrLen(key) = 1 ? Format("{:U}", key) : Format("{:T}", SubStr(key, 1, 1)) SubStr(key, 2))
	}

;---- A Wizard101 the bot left in the tray ----

;The bot puts Wizard101 in the tray (its Settings: traygame) and keeps the hidden window in dashboard.ini [gametray]
;(hwnd, pid, min) till it's shown again - at the latest as the bot closes. A bot that ended without that (Task Manager, a
;crash, an update's forced close) left it hidden: this shows it again - minimized if it was, never taking the focus -
;and forgets it. dir: the AutoFarmer folder. Run by the bot as it starts, and by the watcher while no bot runs
;(WatchTrayLeft). wait: ms to wait for the window to be up. What was done, for the bot's log ("" nothing to do)
WatchTrayBack(dir, wait := 0)
	{
	wtIni := dir "\dashboard.ini"
	try
		{
		wtHwnd := IniRead(wtIni, "gametray", "hwnd", "")
		if (wtHwnd = "")
			return ""
		wtPid := IniRead(wtIni, "gametray", "pid", "")
		wtMin := IniRead(wtIni, "gametray", "min", 0)
		wtSaid := "the Wizard101 window a run had left in the tray is gone - forgotten"
		if (IsInteger(wtHwnd) && IsInteger(wtPid) && DllCall("IsWindow", "Ptr", wtHwnd))
			{
			;(the same window: its process and class - a handle Windows gave something else since is left alone)
			wtWinPid := 0, wtCls := Buffer(512, 0)
			DllCall("GetWindowThreadProcessId", "Ptr", wtHwnd, "UInt*", &wtWinPid)
			DllCall("GetClassName", "Ptr", wtHwnd, "Ptr", wtCls, "Int", 256)
			if (wtWinPid = wtPid && StrGet(wtCls) = "Wizard Graphical Client")
				{
				if (DllCall("IsWindowVisible", "Ptr", wtHwnd))
					wtSaid := "the Wizard101 window a run had put in the tray is up again - forgotten"
				else
					{
					;(SW_SHOWMINNOACTIVE 7 / SW_SHOWNA 8: as it was, never activated - async: a hung game doesn't hold it)
					DllCall("ShowWindowAsync", "Ptr", wtHwnd, "Int", wtMin = 1 ? 7 : 8)
					wtTries := wait // 25
					Loop wtTries
						{
						if (DllCall("IsWindowVisible", "Ptr", wtHwnd))
							break
						Sleep(25)
						}
					wtSaid := "Wizard101 was still in the tray, left by a run that ended without showing it - shown again" (wtMin = 1 ? " (minimized)" : "") ", without taking the focus"
					}
				}
			}
		IniDelete(wtIni, "gametray")
		return wtSaid
		}
	catch
		return ""
	}

;A Wizard101 window kept in dashboard.ini [gametray] (dir: the AutoFarmer folder) - WatchTrayBack's to show
WatchTrayLeft(dir)
	{
	try
		return IniRead(dir "\dashboard.ini", "gametray", "hwnd", "") != ""
	catch
		return false
	}

;Starts the bot from dir (the AutoFarmer folder) in standby
WatchStartBot(dir)
	{
	BotRun(dir "\Autofarmer", "/standby", dir)
	}

;The watcher (Wiz-Maxxing.exe /watch) - never returns, except when another watcher is running already (a named
;mutex: a new one started by an update waits up to 8 s for the old one to go)
WatchGame(dir)
	{
	global ErrorLevel ; (v1 globals it sets)
	t0 := A_TickCount
	Loop
		{
		mutex := DllCall("CreateMutex", "Ptr", 0, "Int", 0, "Str", "Wiz-Maxxing watcher", "Ptr")
		if (A_LastError != 183)
			break
		DllCall("CloseHandle", "Ptr", mutex)
		if (A_TickCount - t0 > 8000)
			return
		Sleep(1000)
		}
	if (!A_IsCompiled && FileExist(A_ScriptDir "\assets\wizard.ico"))
		TraySetIcon(A_ScriptDir . "\assets\wizard.ico")
	;(shown: the launcher's #NoTrayIcon hides it)
	A_IconHidden := false
	Tray := A_TrayMenu
	;(v1's Menu, Tray, NoStandard: only the standard items are there yet)
	Tray.Delete()
	watchItem := "Opens the bot when Wizard101 starts (" WatchBotKey(dir) " starts it)"
	Tray.Add(watchItem, WatchMenuNothing)
	Tray.Disable(watchItem)
	Tray.Add("Stop watching (till Windows starts again)", WatchMenuStop)
	Tray.Add("Don't open with Wizard101 any more", WatchMenuOff)
	A_IconTip := "Wiz-Maxxing - watching for Wizard101"
	seen := 0
	Loop
		{
		ErrorLevel := ProcessExist("WizardGraphicalClient.exe")
		pid := ErrorLevel
		;(the game closed: the next one is new, whatever pid Windows gives it)
		if (!pid)
			seen := 0
		else if (pid != seen)
			{
			seen := pid
			if (!WatchBotRunning())
				{
				;(the game's window first, then the bot - then a newer release, if any, is offered: an update closes
				;the bot, so it's opened again, and the watcher starts again from the new Wiz-Maxxing.exe)
				Sleep(3000)
				WatchStartBot(dir)
				if (V1IsFunc("UpCheck") && WatchUpCheck())
					{
					Sleep(1500)
					if (!WatchBotRunning())
						WatchStartBot(dir)
					WatchRestart()
					}
				}
			}
		;(a Wizard101 the bot had put in the tray and left hidden - it ended without showing it: shown again, without
		;taking the focus - only while no bot runs: a running one keeps its own)
		if (WatchTrayLeft(dir) && !WatchBotRunning())
			WatchTrayBack(dir)
		;(the bot's key changed on the Keys tab: the item says the new one)
		now := "Opens the bot when Wizard101 starts (" WatchBotKey(dir) " starts it)"
		if (now != watchItem)
			{
			;(v1: Menu, Tray, UseErrorLevel - a rename that fails is no error; v2 throws)
			try Tray.Rename(watchItem, now)
			watchItem := now
			}
		Sleep(3000)
		}
	}

;The watcher's update check (UpCheck) - only when no other check or install is going on (the bot's update by
;itself, the dashboard's Update to vX): the same lock as UpOnlyOne, let go of afterwards - the watcher runs for days. True if it
;updated
WatchUpCheck()
	{
	mutex := DllCall("CreateMutex", "Ptr", 0, "Int", 0, "Str", "Wiz-Maxxing update", "Ptr")
	if (A_LastError = 183)
		{
		DllCall("CloseHandle", "Ptr", mutex)
		return false
		}
	;(by its name: the bot's program doesn't have UpCheck - a plain UpCheck there would be a load-time warning)
	up := "UpCheck"
	updated := %up%(true)
	DllCall("CloseHandle", "Ptr", mutex)
	return updated
	}

WatchMenuNothing:
WatchMenuNothing()
	return

WatchMenuStop:
WatchMenuStop()
	ExitApp()

WatchMenuOff:
WatchMenuOff()
	ExitApp()

;###############  v1's labels, as functions  ###############
WatchMenuNothing(A_ThisMenuItem:="", A_ThisMenuItemPos:="", MyMenu:="", *) { ; (v1: the label WatchMenuNothing - a tray item)
	global
	return
}
;##############################################
WatchMenuStop(A_ThisMenuItem:="", A_ThisMenuItemPos:="", MyMenu:="", *) { ; (v1: the label WatchMenuStop - a tray item)
	global
	ExitApp()
}
;##############################################
WatchMenuOff(A_ThisMenuItem:="", A_ThisMenuItemPos:="", MyMenu:="", *) { ; (v1: the label WatchMenuOff - a tray item)
	global
	local v1Keep := V1Thread() ; (v1: each thread had its own ErrorLevel)
	V1Do(FileDelete, WatchLink())
	TrayTip("The bot won't open with Wizard101 any more (the bot's tray menu `"Open with Wizard101`" turns it back on).", "Wiz-Maxxing", 1)
	Sleep(3000)
	ExitApp()
}
