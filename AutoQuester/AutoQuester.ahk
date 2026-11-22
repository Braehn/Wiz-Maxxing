#Warn Unreachable, Off
#Requires AutoHotkey v2.0
; AutoQuester - walks your Wizard101 wizard towards the current quest goal by following the yellow
; quest arrow at the bottom of the screen. AHK v1.1. Walking only: AutoFarmer\Autofarmer.ahk does
; battles AND this walking in one script, so you normally don't need to run this one as well.
;   F8        start / stop walking
;   Shift+F8  quit
; Keys are only sent while Wizard101 is the active window. When there's no arrow (battle, loading
; screen, dialogue) it stops and waits. The walking itself lives in Walker.ahk (settings at its top).
;(v1's #NoEnv: always so in v2)
#SingleInstance force
;(v1's SetBatchLines -1: v2 always runs at full speed)
V1Start(), AutoQuesterBlank(), WalkerBlank(), MouseSteerBlank() ; (v2 port: v1 started every variable blank - CONVENTIONS.md "Blank start")
CoordMode("Pixel", "Screen")
CoordMode("Mouse", "Screen")
;(v1's default sending mode was Event - v2's is Input, which moves the mouse at once (MouseMove's speed ignored)
;and sends with no key or click delays: W/A/S/D, X, Space, the right button and the clicks as v1 sent them)
SendMode("Event")
SetWorkingDir(A_ScriptDir)

global GameExe := "WizardGraphicalClient.exe"
global GameClass := "Wizard Graphical Client"
global GameLeft := 0, GameTop := 0, GameW := 0, GameH := 0
;(AutoFarmer's globals the walker files read - blank here, as in v1: it has no settings, mouse lock, dungeon runs, vision
;helper, picture sets, "Play for me" or player watch)
Stats := "", PlayerActive := "", DgRun := "", VisionOn := "", UiScale := ""

OnExit(WalkerQuit)
;No standard tray menu: its "Pause Script" would freeze the walker with a key held down
Tray := A_TrayMenu
Tray.Delete() ; (v1: Menu, Tray, NoStandard - the standard items are all there is so far)
Tray.Add("Start/stop walking (F8)", ToggleWalk)
Tray.Add("Exit (Shift+F8)", QuitApp)
Tray.Default := "Start/stop walking (F8)"
if (!WalkerInit("AutoQuester"))
	{
	MsgBox("Couldn't load resources\arrow_refs.txt - AutoQuester can't read the quest arrow without it.", "AutoQuester", 16)
	ExitApp()
	}
SetStatus("stopped - press F8 in Wizard101 to start walking")
return

F8::HK1_F8()
ToggleWalk:
ToggleWalk()
return

+F8::HK2_F8()
QuitApp:
QuitApp()
ExitApp()

WalkLoop:
WalkLoop()
return

;Finds the Wizard101 client area on screen (same as AutoFarmer)
UpdateGameRect()
	{
	global GameLeft, GameTop, GameW, GameH ; (v1 globals it sets)
	hwnd := V1Try(WinGetID, "ahk_class " GameClass " ahk_exe " GameExe)  ; (v1: blank with no game window)
	if (!hwnd)
		return false
	;(the client area - a full-screen one bigger than its screen only the part on it, the part the game draws: GameRect.ahk)
	if (!GameClientRect(hwnd, &x, &y, &w, &h))
		return false
	GameLeft := x, GameTop := y, GameW := w, GameH := h
	return true
	}

#Include "%A_ScriptDir%\Walker.ahk"
#Include "%A_ScriptDir%\ArrowReader.ahk"
#Include "%A_ScriptDir%\..\GameRect.ahk"
#Include "%A_ScriptDir%\..\V1Compat.ahk" ; (v2 port: the v1 behaviours it keeps)

;(v1's hotkey and label bodies, as functions: assume-global, as v1 ran them)
HK1_F8() { ; (v1: the F8 hotkey)
global
local v1Keep := V1Thread() ; (v1: each thread had its own ErrorLevel)
ToggleWalk()
}
;##############################################
ToggleWalk(A_ThisMenuItem:="", A_ThisMenuItemPos:="", MyMenu:="", *) { ; (v1: the label ToggleWalk - a menu item too)
global
local v1Keep := V1Thread() ; (v1: each thread had its own ErrorLevel)
WalkToggle()
if (Walking)
	SetTimer(WalkLoop,-1)
return
}
;##############################################
HK2_F8() { ; (v1: the Shift+F8 hotkey)
global
QuitApp()
}
;##############################################
QuitApp(A_ThisMenuItem:="", A_ThisMenuItemPos:="", MyMenu:="", *) { ; (v1: the label QuitApp - a menu item too)
global
ExitApp()
}
;##############################################
WalkLoop() { ; (v1: the label WalkLoop - its timer)
global
local v1Keep := V1Thread() ; (v1: each thread had its own ErrorLevel)
;A quick stop+start can queue a second run of this; only run while walking
if (!Walking)
	return
while (Walking)
	{
	UpdateGameRect()
	if (!WalkStep())
		break
	}
if (KeysDown || HeldW)
	ReleaseKeys()
;"stuck" keeps its own message, everything else says it's stopped
if (StatusKind != "stuck")
	SetStatus("stopped - press F8 to start walking")
return
}

;(v2 port, CONVENTIONS.md "Blank start": v1 started every variable blank; v2 leaves it unset and throws on
;reading it. The entry script calls this first thing: this file's globals start blank, as in v1)
AutoQuesterBlank()
	{
	global GameExe := "", GameClass := "", GameLeft := "", GameTop := "", GameW := "", GameH := "", Walking := "", KeysDown := "", HeldW := ""
	global StatusKind := ""
	}
