#Requires AutoHotkey v2.0
; StatsReader.ahk - reads your wizard's Damage, Accuracy, Critical, Block and Armor Piercing off the
; Spellbook's stats pages and writes them into PlayerStats.txt as <school>.damage, <school>.pierce, ...
; for that wizard's school (the kill check uses <school>.damage and <school>.pierce). Run it while
; you're NOT in a battle; it opens the Spellbook, turns to the two stats pages and closes it again.
;
; Works at any window size / UI size (the pictures and positions follow it, see PicScale.ahk), and works
; out which wizard is logged in: AutoFarmer notes each character's school (from its name plate in
; battle) in resources\characters.txt; for a character it hasn't seen, the school with clearly the
; highest damage is taken. Set School below to force one.
;
; While AutoFarmer is running, this asks AutoFarmer to do it instead (two scripts clicking at once
; would get in each other's way): it reads them at the next quiet moment out of battle. AutoFarmer also
; reads them by itself when it fights with a wizard whose school has no stats yet.
;
; A number is only written when it was read the same way twice (digit pictures and Windows OCR), so it
; never writes a wrong one; what it couldn't read for sure keeps its old value. What it read goes to
; StatsReader.log, and pictures of the two stats pages to %TEMP%\Wizard101 bot rounds\stats_*.bmp.
; (v1's #NoEnv: v2 always)
#SingleInstance force
; (v1's SetBatchLines -1: v2 always runs at full speed)
V1Start(), StatsReaderBlank(), PicScaleBlank(), StatsReadBlank() ; (v2 port: v1 started every variable blank - CONVENTIONS.md "Blank start")
CoordMode("Pixel", "Screen")
CoordMode("Mouse", "Screen")
;(v1's default sending mode was Event - v2's is Input, which moves the mouse at once (MouseMove's speed ignored) and
;sends with no key or click delays: the Spellbook's C and clicks as v1 sent them)
SendMode("Event")
SetWorkingDir(A_ScriptDir)

; ---- Settings ----
School := ""             ; "" = work it out; or one of: fire ice storm myth life death balance shadow

global GameExe := "WizardGraphicalClient.exe", GameClass := "Wizard Graphical Client"
global GameLeft := 0, GameTop := 0, GameW := 0, GameH := 0, GameRight := 0, GameBottom := 0, ScreenX := 0, ScreenY := 0
global PicSets := [], PicSet := 1, PicDir := A_WorkingDir, UiScale := 1.0

Try FileDelete(A_ScriptDir "\StatsReader.log")

;AutoFarmer running? Then it does the reading (message 0x5555 = "read the stats")
DetectHiddenWindows(true)
SetTitleMatchMode("RegEx")
;(the script's window, or the compiled AutoFarmer.exe's)
farmer := WinExist("i)\\Autofarmer\.(ahk - AutoHotkey|exe$) ahk_class AutoHotkey")
SetTitleMatchMode(1)
if (farmer)
	{
	;(v1: ErrorLevel 1 when it couldn't be posted - v2 throws)
	try
		PostMessage(0x5555, 0, 0, , "ahk_id " farmer), ErrorLevel := 0
	catch
		ErrorLevel := 1
	if (ErrorLevel)
		Fail("AutoFarmer is running but didn't take the request. Close AutoFarmer and run this again.")
	MsgBox("AutoFarmer is running, so it will read your stats itself at the next quiet moment out of battle: with Wizard101 in front and your hands off the mouse and keyboard for 5 seconds. A tray tip says when it's done.", "StatsReader", 64)
	ExitApp()
	}
DetectHiddenWindows(false)

hwnd := V1Try(WinGetID, "ahk_class " GameClass " ahk_exe " GameExe)  ; (v1: no window - blank; v2 throws)
if (!hwnd)
	Fail("Wizard101 isn't running.")
V1Try(WinActivate, "ahk_id " hwnd)  ; (v1: the window gone meanwhile - nothing, the wait below fails; v2 throws)
ErrorLevel := !WinWaitActive("ahk_id " hwnd, , 3)
if (ErrorLevel)
	Fail("Couldn't bring Wizard101 to the front.")
;(the client area - a full-screen one bigger than its screen only the part on it, the part the game draws: GameRect.ahk)
GameClientRect(hwnd, &GameLeft, &GameTop, &GameW, &GameH)
GameRight := GameLeft + GameW, GameBottom := GameTop + GameH, ScreenX := GameLeft + GameW // 2, ScreenY := GameTop + GameH // 2
Sleep(300)

;The UI size: whichever picture set sees the Spellbook icon, else look for the icon at every size
LoadPicSets()
if (!DetectPicSet())
	{
	DebugLog("No picture set sees the Spellbook icon - looking for it at every UI size")
	sc := PicScaleFromBook()
	if (!sc)
		Fail("Couldn't find the Spellbook icon at the bottom right. Run this outside battle, with nothing over the icon.")
	UsePicSet(PicSetFor(sc), "the Spellbook icon made at every size matches best at " sc)
	}

charID := StatsCharID()
if (School = "")
	{
	School := StatsSchoolOf(charID)
	DebugLog("Character " (charID = "" ? "?" : charID) ": " (School = "" ? "school not known yet - taking the one with clearly the highest damage" : School))
	}
err := StatsRead(&School, &got)
if (err != "")
	Fail("Couldn't read your stats: " err ".")
msg := StatsWrite(got, School, charID)
DebugLog(StrReplace(msg, "`n", " "))
MsgBox(msg, "StatsReader", 64)
ExitApp()

; ------------------------------------------------------------------------------------------------

Fail(why)
	{
	DebugLog(why)
	MsgBox(why "`n`n(Details: StatsReader.log next to this script.)", "StatsReader", 48)
	ExitApp()
	}

;Each line goes to StatsReader.log
DebugLog(msg)
	{
	stamp := FormatTime(, "HH:mm:ss")
	V1Do(FileAppend, stamp " " msg "`r`n", A_ScriptDir "\StatsReader.log")  ; (v1: ErrorLevel 1 when it can't be written - v2 throws)
	}

;Picture set i (PicScale.ahk) and its UI size; why: what chose it
UsePicSet(i, why := "")
	{
	global PicSet, PicDir, UiScale ; (v1 globals it sets)
	PicSet := i, PicDir := PicSets[i].dir, UiScale := PicSets[i].scale
	DebugLog("Pictures: " (i = 1 ? "main set" : SubStr(PicDir, StrLen(A_WorkingDir) + 2)) " (UI scale " Round(UiScale, 3) ")" (why != "" ? " - " why : ""))
	}

;A picture at the UI size in use: the set's own, or one made at its size (PicMake), else the main one
PicPath(rel)
	{
	set := PicSets[PicSet], p := ""
	if (set.gen)
		p := PicMake(rel, set)
	else if (FileExist(set.dir "\" rel))
		p := set.dir "\" rel
	else if (set.dir != A_WorkingDir)
		p := PicMake(rel, V1Obj({dir: GenRoot "\ui" Round(set.scale, 3), scale: set.scale}))
	return (p != "" && FileExist(p)) ? p : A_WorkingDir "\" rel
	}

#Include "%A_ScriptDir%\Ocr.ahk"
#Include "%A_ScriptDir%\PicScale.ahk"
#Include "%A_ScriptDir%\StatsRead.ahk"
#Include "%A_ScriptDir%\..\GameRect.ahk"
#Include "%A_ScriptDir%\..\V1Compat.ahk" ; (v2 port: the v1 behaviours it keeps)

;(v2 port, CONVENTIONS.md "Blank start": v1 started every variable blank; v2 leaves it unset and throws on
;reading it. The entry script calls this first thing: this file's globals start blank, as in v1)
StatsReaderBlank()
	{
	global GameExe := "", GameClass := "", GameLeft := "", GameTop := "", GameW := "", GameH := "", GameRight := "", GameBottom := "", ScreenX := ""
	global ScreenY := "", PicSets := "", PicSet := "", PicDir := "", UiScale := ""
	}
