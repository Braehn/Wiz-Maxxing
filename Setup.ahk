#Warn Unreachable, Off
#Requires AutoHotkey v2.0
; Setup.ahk - gets a PC ready to run the Wizard101 bot. Compiled to Setup.exe by build.ps1; it sits next to
; AutoFarmer\ and AutoQuester\. AutoHotkey v2 (ported from v1.1).
;
; Each part shows whether it's there already; the ones that are missing are ticked. Install does the ticked
; ones, in order, writing what happens in the log below:
;   Install to your Programs folder   %LOCALAPPDATA%\Programs\Wiz-Maxxing (yours, no admin - the updater keeps
;                     working): the bot (and the watcher) closed, this folder copied there - over an install that's
;                     there already as an update does, its settings, learned cards and routes kept - then Setup
;                     starts from there and goes; that one does the rest of what was ticked (the shortcuts, Start
;                     menu, PATH and watcher now point there) and offers the download - the unpacked folder and the
;                     Wiz-Maxxing zip(s) beside it - to the Recycle Bin. Not for a git checkout
;   Python 3          the vision helper (card and badge matching) runs on it. winget installs it for you
;                     only (no admin); without winget, the installer from python.org
;   numpy and Pillow  the Python packages the vision helper uses (pip), then checked by importing them;
;                     katsuba too, as a spare reader of the game's zone files for the zone map (optional:
;                     the helper reads them itself)
;   Unblock files     Windows marks files that came from the internet and warns about every exe; this
;                     takes the mark off the bot's files
;   Start menu        a Wiz-Maxxing folder: Wiz-Maxxing (the bot), Wiz-Maxxing Setup, Stats reader, Quest walker only
;   Desktop shortcut  "Wiz-Maxxing" -> Wiz-Maxxing.exe (it starts AutoFarmer\Autofarmer.exe)
;   Run box and PATH  this folder on your PATH (type Wiz-Maxxing in a terminal) and Wiz-Maxxing.exe in "App
;                     Paths" (type Wiz-Maxxing in Win+R) - yours only, no admin
;   Cheat Engine speedhack  (optional, never ticked by itself - risky: KingsIsle may notice) the speedhack the bot's
;                     Settings switch on: Cheat Engine installed if it isn't (its installer from cheatengine.org,
;                     opened for you to click through - never silently: that takes the other programs it recommends),
;                     and the bot's script (CheatEngine\wiz-maxxing.lua) put in its autorun folder (Program Files: asks
;                     for admin) - Cheat Engine then attaches to Wizard101 by itself and the bot's two keys set the
;                     speed (of the Wizard101 window in front, the one the bot walks). Then, if you say so, the
;                     bot's speedhack setting on: the bot starts Cheat Engine
;   AutoHotkey v2     only to change the scripts and rebuild the exes (build.cmd); asks for admin
;   Git               only to get updates with git pull; asks for admin
;   GitHub updates    a read-only GitHub token, so Wiz-Maxxing can check for and download new versions when you
;                     open it (the repo is private): the token page opens, you paste the token, it's tested and
;                     kept in Windows Credential Manager (Updater.ahk)
;(v1's #NoEnv and SetBatchLines, -1: what v2 does anyway)
#SingleInstance force
V1Start(), SetupBlank(), UpdaterBlank() ; (v2 port: v1 started every variable blank - CONVENTIONS.md "Blank start")
SetWorkingDir(A_ScriptDir)

global SuLog, SuPyS, SuPkS, SuUnS, SuShS, SuAhS, SuGiS, SuPy, SuPk, SuUn, SuSh, SuAh, SuGi, SuGo, SuStart, SuSm, SuSmS, SuUp, SuUpS, SuPa, SuPaS
global SuWa, SuWaS, SuIn, SuInS, SuCe, SuCeS
global SuLogHwnd := 0, SuBusy := 0
;(started again from the Programs folder after the copy: the folder it was in, the parts still to do, the old
;Setup's pid - /moved <folder> /do <py,pk,...> /oldpid <pid>)
global SuMovedFrom := "", SuMovedDo := "", SuMovedPid := 0, SuMovedSaved := ""
for suI, suA in A_Args
	{
	;(v1: A_Args[i] past the last one - blank; v2 throws. A blank or text + 0 - blank)
	if (suA = "/moved")
		SuMovedFrom := RTrim(V1At(A_Args, suI + 1), "\")
	else if (suA = "/saved")
		SuMovedSaved := V1At(A_Args, suI + 1)
	else if (suA = "/do")
		SuMovedDo := V1At(A_Args, suI + 1)
	else if (suA = "/oldpid")
		SuMovedPid := V1Add(V1At(A_Args, suI + 1), 0)
	}

if (!FileExist(A_ScriptDir "\AutoFarmer\Autofarmer.ahk"))
	{
	MsgBox("Setup.exe has to be in the bot's folder - next to AutoFarmer\ and AutoQuester\ (it's in " A_ScriptDir ").", "Wizard101 bot setup", 48)
	ExitApp()
	}

suVersion := V1FileRead(A_ScriptDir "\version.txt")
Su := Gui(, "Wizard101 bot setup " Trim(suVersion, " `t`r`n"))
Su.OnEvent("Close", SuGuiClose)
Su.OnEvent("Escape", SuGuiEscape)
Su.MarginX := 14, Su.MarginY := 12
Su.SetFont("s11 w600", "Segoe UI")
Su.Add("Text", "w620", "Get this PC ready to run the Wizard101 bot")
Su.SetFont("s9 w400", "Segoe UI")
Su.Add("Text", "w620 y+4", "The ticked parts get installed. Python and its packages are needed for the card matching and the zone map; the last two are only for changing the bot.")
ogcCheckboxSuIn := Su.Add("Checkbox", "xm y+14 w260 vSuIn", "Install to your Programs folder")
ogcTextSuInS := Su.Add("Text", "x+8 w350 vSuInS", "...")
ogcCheckboxSuPy := Su.Add("Checkbox", "xm y+8 w260 vSuPy", "Python 3")
ogcTextSuPyS := Su.Add("Text", "x+8 w350 vSuPyS", "...")
ogcCheckboxSuPk := Su.Add("Checkbox", "xm y+8 w260 vSuPk", "numpy and Pillow (Python packages)")
ogcTextSuPkS := Su.Add("Text", "x+8 w350 vSuPkS", "...")
ogcCheckboxSuUn := Su.Add("Checkbox", "xm y+8 w260 vSuUn", "Unblock the bot's files")
ogcTextSuUnS := Su.Add("Text", "x+8 w350 vSuUnS", "...")
ogcCheckboxSuUp := Su.Add("Checkbox", "xm y+8 w260 vSuUp", "GitHub updates (a token, once)")
ogcTextSuUpS := Su.Add("Text", "x+8 w350 vSuUpS", "...")
ogcCheckboxSuSm := Su.Add("Checkbox", "xm y+8 w260 vSuSm", "Start menu (Wiz-Maxxing)")
ogcTextSuSmS := Su.Add("Text", "x+8 w350 vSuSmS", "...")
ogcCheckboxSuSh := Su.Add("Checkbox", "xm y+8 w260 vSuSh", "Desktop shortcut `"Wiz-Maxxing`"")
ogcTextSuShS := Su.Add("Text", "x+8 w350 vSuShS", "...")
ogcCheckboxSuPa := Su.Add("Checkbox", "xm y+8 w260 vSuPa", "Run box and PATH (Win+R: Wiz-Maxxing)")
ogcTextSuPaS := Su.Add("Text", "x+8 w350 vSuPaS", "...")
ogcCheckboxSuWa := Su.Add("Checkbox", "xm y+8 w260 vSuWa", "Open with Wizard101 (" WatchBotKey(A_ScriptDir "\AutoFarmer") " starts it)")
ogcTextSuWaS := Su.Add("Text", "x+8 w350 vSuWaS", "...")
ogcCheckboxSuCe := Su.Add("Checkbox", "xm y+8 w260 vSuCe", "Cheat Engine speedhack (optional, risky)")
ogcTextSuCeS := Su.Add("Text", "x+8 w350 vSuCeS", "...")
ogcCheckboxSuAh := Su.Add("Checkbox", "xm y+8 w260 vSuAh", "AutoHotkey v2 (to rebuild the exes)")
ogcTextSuAhS := Su.Add("Text", "x+8 w350 vSuAhS", "...")
ogcCheckboxSuGi := Su.Add("Checkbox", "xm y+8 w260 vSuGi", "Git (to get updates with git pull)")
ogcTextSuGiS := Su.Add("Text", "x+8 w350 vSuGiS", "...")
ogcButtonSuGo := Su.Add("Button", "xm y+16 w120 h28 vSuGo Default", "Install")
ogcButtonSuGo.OnEvent("Click", SuInstall.Bind("Normal"))
ogcButtonSuStart := Su.Add("Button", "x+10 w140 h28 vSuStart", "Start the bot")
ogcButtonSuStart.OnEvent("Click", SuStartBot.Bind("Normal"))
ogcButtonClose := Su.Add("Button", "x+10 w90 h28", "Close")
ogcButtonClose.OnEvent("Click", SuGuiClose.Bind("Normal"))
Su.SetFont("s9", "Consolas")
ogcEditSuLog := Su.Add("Edit", "xm y+12 w620 h240 ReadOnly -Wrap +HScroll vSuLog"), SuLogHwnd := ogcEditSuLog.hwnd
Su.Show()
SuCheck(true)
;(started from the Programs folder after the copy: the parts that were ticked, and the shortcuts / Start menu / PATH /
;watcher that point to the old folder - SuCheck ticks those - done; then the download offered to the Recycle Bin)
if (SuMovedFrom != "")
	{
	SuMovedPrep()
	SuInstall()  ;(v1: gosub, SuInstall - in this same thread)
	SuOfferDelete(SuMovedFrom)
	}
return

;Before the moved-on install: the parts that were ticked ticked again, the old Setup gone, the old folder off the PATH
SuMovedPrep()
	{
	global ErrorLevel ; (v1 globals it sets)
	SuLogLine("Installed in " A_ScriptDir " - doing the rest here")
	;(never copied on again from here; the parts exactly as they were ticked - plus what still points into the old
	;folder, which may go to the Recycle Bin: the shortcuts, the watcher, the PATH)
	Su["SuIn"].Value := 0
	for each, code in ["py", "pk", "un", "up", "sm", "sh", "pa", "wa", "ce", "ah", "gi"]
		Su["Su" code].Value := InStr("," SuMovedDo ",", "," code ",") ? 1 : 0
	if (SuLinkHere(A_Programs "\Wiz-Maxxing\Wiz-Maxxing.lnk", SuMovedFrom))
		Su["SuSm"].Value := 1
	if (SuLinkHere(A_Desktop "\Wiz-Maxxing.lnk", SuMovedFrom))
		Su["SuSh"].Value := 1
	if (SuLinkHere(WatchLink(), SuMovedFrom))
		Su["SuWa"].Value := 1
	;(Cheat Engine's script there, but another folder's - the old one's PlayerStats.txt: put in again for this one)
	suCeDir := CeDir()
	if (suCeDir != "" && FileExist(CeScriptPath(suCeDir)) && V1FileRead(CeScriptPath(suCeDir), "UTF-8") !== SuCeScript())
		Su["SuCe"].Value := 1
	;(v1's RegRead of a value that isn't there: blank - v2 throws)
	oldPath := V1Try(RegRead, "HKCU\Environment", "Path")
	if (SuInPath(oldPath, SuMovedFrom))
		Su["SuPa"].Value := 1
	;(the old Setup gone, so its folder can go)
	if (SuMovedPid)
		ErrorLevel := ProcessWaitClose(SuMovedPid, 15)
	;(the old folder off your PATH - this one goes on it)
	pa := Su["SuPa"].Value
	if (pa)
		SuRemovePath(SuMovedFrom)
	}

;What's there already. tick: tick the missing parts (the first look)
SuCheck(tick := false)
	{
	home := SuHome()
	notOwn := SuOwnFolder(A_ScriptDir)
	newer := SuNewerThere(home)
	if (SuSamePath(A_ScriptDir, home))
		SuShow("SuIn", "SuInS", true, "installed: " SuShort(home), tick)
	else if (FileExist(A_ScriptDir "\.git") != "")
		SuShow("SuIn", "SuInS", true, "a git checkout - it stays where it is (git pull updates it)", tick)
	else if (notOwn != "")
		SuShow("SuIn", "SuInS", false, "can't from here: " notOwn " - put the bot's files in a folder of their own", tick, false)
	else if (newer != "")
		SuShow("SuIn", "SuInS", true, "a newer version (" newer ") is installed - start that one", tick)
	else
		SuShow("SuIn", "SuInS", false, "runs from " SuShort(A_ScriptDir) " - copies itself to " SuShort(home), tick)
	py := SuPython()
	SuShow("SuPy", "SuPyS", py != "", py != "" ? "found: " SuShort(py) : "not installed", tick)
	pk := py != "" && SuRun("`"" py "`" -c `"import numpy, PIL`"", false) = 0
	SuShow("SuPk", "SuPkS", pk, pk ? "installed" : (py = "" ? "needs Python first" : "not installed"), tick)
	marked := SuMarkedCount()
	SuShow("SuUn", "SuUnS", marked = 0, marked = 0 ? "nothing blocked" : marked " file(s) marked as downloaded", tick)
	up := UpToken() != ""
	SuShow("SuUp", "SuUpS", up, up ? "token saved - Wiz-Maxxing checks for updates when you open it" : "no token yet", tick)
	sm := SuLinkHere(A_Programs "\Wiz-Maxxing\Wiz-Maxxing.lnk")
	SuShow("SuSm", "SuSmS", sm, sm ? "in the Start menu" : FileExist(A_Programs "\Wiz-Maxxing\Wiz-Maxxing.lnk") ? "there, but for another folder" : "not there", tick)
	sc := SuLinkHere(A_Desktop "\Wiz-Maxxing.lnk")
	SuShow("SuSh", "SuShS", sc, sc ? "on the desktop" : FileExist(A_Desktop "\Wiz-Maxxing.lnk") ? "there, but for another folder" : "not there", tick)
	pa := SuPathOk()
	SuShow("SuPa", "SuPaS", pa, pa ? "Win+R or a terminal: Wiz-Maxxing" : "not set up", tick)
	wa := WatchIsOn() && SuLinkHere(WatchLink())
	SuShow("SuWa", "SuWaS", wa, wa ? "on - the bot opens in standby when the game starts" : WatchIsOn() ? "on, but for another folder" : "off (the bot's tray menu switches it too)", tick, WatchIsOn())
	;(never ticked by itself - unless the bot's script is in Cheat Engine already, from another folder or older)
	ce := CeDir()
	ceIn := ce != "" && FileExist(CeScriptPath(ce)) != ""
	ceOk := ceIn && V1FileRead(CeScriptPath(ce), "UTF-8") == SuCeScript()
	SuShow("SuCe", "SuCeS", ceOk, ce = "" ? "not installed (only for the speedhack)" : ceOk ? "set up: attaches to Wizard101, the bot's speed keys" : ceIn ? "found - its Wiz-Maxxing script is older or another folder's" : "found - not set up for the bot yet", tick, ceIn)
	ahk := SuAhk()
	SuShow("SuAh", "SuAhS", ahk != "", ahk != "" ? "found: " SuShort(ahk) : "not installed (only needed to rebuild)", tick, false)
	git := SuWhere("git.exe")
	SuShow("SuGi", "SuGiS", git != "", git != "" ? "found" : "not installed (only for updates)", tick, false)
	}

;A part's status; tick it when it's missing (and wanted by default)
SuShow(box, label, ok, text, tick, wanted := true)
	{
	Su[label].Text := (ok ? "OK - " : "") text
	if (tick)
		Su[box].Value := (!ok && wanted) ? 1 : 0
	}

SuInstall:
SuInstall()
	return

SuStartBot:
SuStartBot()
	return

SuGuiClose:
SuGuiClose()
return
SuGuiEscape:
SuGuiEscape()
	ExitApp()

;---- the parts ----

;A line in the log, and code back (for a return)
SuSay(text, code)
	{
	SuLogLine(text)
	return code
	}

;Your own Programs folder's Wiz-Maxxing (%LOCALAPPDATA%\Programs\Wiz-Maxxing: no admin needed, as Discord and VS Code)
SuHome()
	{
	la := EnvGet("LOCALAPPDATA")
	return (la = "" ? A_AppData "\..\Local" : la) "\Programs\Wiz-Maxxing"
	}

;Whether two folders are the same (any case, with or without a trailing \)
SuSamePath(a, b)
	{
	return RTrim(a, "\") = RTrim(b, "\")
	}

;Whether shortcut lnk is there and starts something in this folder (in: another) - its own folder, or the script it
;runs (v2 port: the parameter in is inV - "in" is a v2 word)
SuLinkHere(lnk, inV := "")
	{
	if (!FileExist(lnk))
		return false
	;(v1: a shortcut it couldn't read - its outputs blank, ErrorLevel 1; v2 throws, and leaves them unset)
	if (V1Do(FileGetShortcut, lnk, &target, &dir, &args))
		target := "", dir := "", args := ""
	here := RTrim(inV = "" ? A_ScriptDir : inV, "\") "\"
	return InStr(target, here) = 1 || InStr(dir "\", here) = 1 || InStr(args, here)
	}

;Why folder dir isn't the bot's own ("" if it is): a whole drive, a folder of yours (the Desktop, Documents,
;Downloads, your profile, OneDrive...), or one with other things in it besides the bot's - those are never copied
;into the Programs folder or offered to the Recycle Bin. contentsToo false: only whether it's a drive or such a folder
SuOwnFolder(dir, contentsToo := true)
	{
	dir := RTrim(dir, "\")
	if (RegExMatch(dir, "^[A-Za-z]:$") || RegExMatch(dir, "^\\\\[^\\]+\\[^\\]+$"))
		return "it's a whole drive"
	prof := EnvGet("USERPROFILE")
	od1 := EnvGet("OneDrive")
	od2 := EnvGet("OneDriveConsumer")
	od3 := EnvGet("OneDriveCommercial")
	for i, k in [A_Desktop, A_DesktopCommon, A_MyDocuments, prof, prof "\Downloads", SuKnownFolder("{374DE290-123F-4565-9164-39C4925E467B}")
		, od1, od2, od3, A_ProgramFiles, A_WinDir, A_Temp, A_AppData, RegExReplace(SuHome(), "\\[^\\]+$")]
		if (k != "" && SuSamePath(dir, k))
			return "it's " k " itself"
	if (!contentsToo)
		return ""
	;(v2 port: V1Compat.ahk - the port's own file beside Updater.ahk and Watch.ahk - is the bot's too)
	Loop Files, dir "\*", "FD"
		if (!RegExMatch(A_LoopFileName, "i)^(\.git.*|\.github|AutoFarmer|AutoPetTrainer|AutoQuester|assets|backups|README\.md|Setup\.(ahk|exe)|Updater\.ahk|Watch\.ahk|V1Compat\.ahk|Wiz-Maxxing\.(ahk|exe)|build\.(cmd|ps1)|version\.txt|updater\.(ini|log)|.+\.old|desktop\.ini|Thumbs\.db)$"))
			return "it has other things in it too (" A_LoopFileName ")"
	return ""
	}

;A known folder's path (guid: its FOLDERID), "" if Windows doesn't say
SuKnownFolder(guid)
	{
	id := Buffer(16, 0)
	if (DllCall("ole32\CLSIDFromString", "WStr", guid, "Ptr", id.Ptr) != 0)
		return ""
	;(v1: p blank - 0; v2's DllCall wants the variable set)
	p := 0
	if (DllCall("shell32\SHGetKnownFolderPath", "Ptr", id.Ptr, "UInt", 0, "Ptr", 0, "Ptr*", &p) != 0 || !p)
		return ""
	path := StrGet(p, "UTF-16")
	DllCall("ole32\CoTaskMemFree", "Ptr", p)
	return path
	}

;The version installed in home when it's newer than this folder's ("" if not, or none there)
SuNewerThere(home)
	{
	if (!FileExist(home "\AutoFarmer\Autofarmer.ahk"))
		return ""
	theirs := V1FileRead(home "\version.txt")
	mine := V1FileRead(A_ScriptDir "\version.txt")
	theirs := Trim(theirs, " `t`r`n"), mine := Trim(mine, " `t`r`n")
	return (theirs != "" && UpCompare(theirs, mine) > 0) ? theirs : ""
	}

;When the bot last ran from folder dir (its debug.log's time, else the last run's; 0 never)
SuLastRun(dir)
	{
	for i, f in [dir "\AutoFarmer\debug.log", dir "\AutoFarmer\debug.previous.log"]
		if (FileExist(f))
			{
			;(v1: a time it couldn't read - blank, and blank + 0 blank)
			at := V1Try(FileGetTime, f, "M")
			return V1Add(at, 0)
			}
	return 0
	}

;Your files in folder from (settings, learned cards, routes, the walker's memory: the updater's UpIsMine - not the
;logs, backups or made pictures) copied into folder to, as they lie. How many
SuCopyMine(from, to)
	{
	slots := UpLearnedSlots(from "\AutoFarmer\learned\cards.txt")
	n := 0
	Loop Files, from "\*", "FR"
		{
		rel := SubStr(A_LoopFilePath, StrLen(from) + 2)
		if (RegExMatch(rel, "i)(^|\\)(backups|generated)\\|\.log$") || !UpIsMine(rel, slots))
			continue
		target := to "\" rel
		SplitPath(target, , &targetDir)
		V1Do(DirCreate, targetDir)
		V1Do(FileCopy, A_LoopFilePath, target, 1)
		if (!ErrorLevel)
			n++
		}
	return n
	}

;The install stopped: the watcher started again if it was closed for it (closedWatch), and -1 back
SuInstallStop(text, closedWatch)
	{
	SuLogLine(text)
	if (closedWatch && WatchIsOn())
		V1Run(WatchLink())
	return -1
	}

;Copies the bot to SuHome and starts Setup from there (the rest of what's ticked, /do) - 1 if it did (this Setup
;then goes), 0 if there was nothing to do (here already), -1 if it couldn't (nothing else is done)
SuInstallHome()
	{
	global ErrorLevel ; (v1 globals it sets)
	SuLogLine("== Install to your Programs folder")
	home := SuHome()
	if (SuSamePath(A_ScriptDir, home))
		return SuSay("installed here already", 0)
	if (FileExist(A_ScriptDir "\.git") != "")
		return SuSay("this is a git checkout - it stays where it is", 0)
	if (InStr(home "\", A_ScriptDir "\") = 1 || InStr(A_ScriptDir "\", home "\") = 1)
		return SuSay("this folder and " home " are inside each other - move this folder somewhere else first", -1)
	notOwn := SuOwnFolder(A_ScriptDir)
	if (notOwn != "")
		return SuSay("not from " A_ScriptDir ": " notOwn " - put the bot's files in a folder of their own (unzip the download as it is) and run Setup there", -1)
	newer := SuNewerThere(home)
	if (newer != "")
		return SuSay("a newer version (" newer ") is installed there - start that one (Start menu: Wiz-Maxxing); this older one isn't put over it", -1)
	if (WatchBotRunning())
		{
		msgResult := MsgBox("The bot is running. Close it to install it in your Programs folder?", "Wiz-Maxxing setup", 262180)
		if (msgResult = "No")
			return SuSay("the bot is running - not installed", -1)
		}
	;(the bot from here and from there, and the watcher - they keep their files open)
	UpCloseBots(A_ScriptDir)
	UpCloseBots(home)
	DetectHiddenWindows(true)
	closedWatch := WatchPids().Length > 0
	for i, pid in WatchPids()
		{
		;(v1: WinClose of a window that's gone meanwhile did nothing - v2 throws)
		try WinClose("ahk_pid " pid " ahk_class AutoHotkey")
		ErrorLevel := ProcessWaitClose(pid, 5)
		if (ErrorLevel)
			ErrorLevel := ProcessClose(pid)
		}
	ver := V1FileRead(A_ScriptDir "\version.txt")
	ver := Trim(ver, " `t`r`n")
	if (FileExist(home "\AutoFarmer\Autofarmer.ahk"))
		{
		;(an install there already: this version's files over it - all or nothing, as an update does. Your settings,
		;learned cards and routes: the folder the bot ran from last keeps them in use, the other's are saved in the
		;install's backups\ - nothing lost)
		;(v1: a blank time - one it couldn't read - compared as text)
		oldWins := V1Gt(SuLastRun(A_ScriptDir), SuLastRun(home))
		stamp := FormatTime(, "yyyy-MM-dd HHmm")
		SplitPath(A_ScriptDir, , &oldParent)
		SplitPath(oldParent, &oldParentName)
		saved := home "\backups\install " stamp (oldWins ? " - the install's own before" : " - from " oldParentName)
		SuLogLine("an install is there already - copying this version over it")
		rollback := A_Temp "\wiz-maxxing-install-rollback"
		V1Do(DirDelete, rollback, 1)
		res := UpCopy(A_ScriptDir, home, rollback)
		if (res.failed.Length)
			{
			UpRollback(res, home, rollback)
			V1Do(DirDelete, rollback, 1)
			return SuInstallStop("couldn't write " res.failed.Length " file(s) there (in use?) - put back as it was: " res.failed[1], closedWatch)
			}
		V1Do(DirDelete, rollback, 1)
		if (oldWins)
			{
			n := SuCopyMine(home, saved)
			SuLogLine("the bot ran from here last: your settings, learned cards and routes from here are used there (the install's own " n " file(s) saved in " saved ")")
			SuCopyMine(A_ScriptDir, home)
			}
		else
			{
			n := SuCopyMine(A_ScriptDir, saved)
			SuLogLine("the install's own settings, learned cards and routes stay in use (this folder's " n " file(s) saved in " saved ")")
			}
		UpMergeStats(A_ScriptDir "\AutoFarmer\PlayerStats.txt", home "\AutoFarmer\PlayerStats.txt", ver)
		V1Do(FileCopy, A_ScriptDir "\version.txt", home "\version.txt", 1)
		SuLogLine(res.copied " file(s) copied")
		}
	else
		{
		existed := InStr(FileExist(home), "D")
		V1Do(DirCreate, home)
		V1Do(DirCopy, A_ScriptDir, home, 1)
		if (ErrorLevel || !FileExist(home "\AutoFarmer\Autofarmer.ahk"))
			{
			;(half a copy must never count as an install)
			if (!existed)
				V1Do(DirDelete, home, 1)
			return SuInstallStop("couldn't copy everything to " home " (in use? the disk full?) - nothing installed", closedWatch)
			}
		saved := ""
		SuLogLine("copied to " home " - with your settings, learned cards and routes")
		}
	do := ""
	for each, code in ["py", "pk", "un", "up", "sm", "sh", "pa", "wa", "ce", "ah", "gi"]
		if (Su%code%)
			do .= (do = "" ? "" : ",") code
	if (!BotRun(home "\Setup", "/moved `"" A_ScriptDir "`" /do " (do = "" ? "-" : do) " /oldpid " DllCall("GetCurrentProcessId") (saved = "" ? "" : " /saved `"" saved "`""), home))
		return SuInstallStop("installed in " home ", but its Setup didn't start - start it there yourself (Start menu or " home "\Setup)", closedWatch)
	return 1
	}

;Your PATH without folder dir (and its App Paths entry, if it's that folder's)
SuRemovePath(dir, envKey := "HKCU\Environment")
	{
	path := V1Try(RegRead, envKey, "Path")
	if (!SuInPath(path, dir))
		return
	keep := ""
	Loop Parse, path, "`;"
		if (Trim(A_LoopField) != "" && RTrim(Trim(A_LoopField), "\") != RTrim(dir, "\"))
			keep .= (keep = "" ? "" : ";") A_LoopField
	V1Do(RegWrite, keep, "REG_EXPAND_SZ", envKey, "Path")
	SuLogLine(ErrorLevel ? "couldn't take the old folder off your PATH" : "the old folder taken off your PATH: " dir)
	}

;The download offered to the Recycle Bin once it's installed: the folder it was unpacked to (the outer
;Wiz-Maxxing-v... one too, when it holds nothing else) and the Wiz-Maxxing zip(s) beside it. Never the install, a
;git checkout, or a folder that isn't the bot's
SuOfferDelete(old)
	{
	home := SuHome()
	old := RTrim(old, "\")
	if (old = "" || !FileExist(old "\AutoFarmer\Autofarmer.ahk") || SuSamePath(old, home)
		|| InStr(home "\", old "\") = 1 || InStr(old "\", home "\") = 1 || FileExist(old "\.git") != "" || SuOwnFolder(old) != "")
		return
	top := old
	SplitPath(old, , &parent)
	SplitPath(parent, &parentName, &grand)
	zipDir := parent
	if (RegExMatch(parentName, "i)^Wiz-Maxxing") && grand != "" && SuOnlyChild(parent, old) && SuOwnFolder(parent, false) = "")
		top := parent, zipDir := grand
	zips := []
	Loop Files, zipDir "\Wiz-Maxxing*.zip"
		zips.Push(A_LoopFilePath)
	list := "`n   " top
	for i, z in zips
		list .= "`n   " z
	note := SuMovedSaved = "" ? "(Everything was copied over - your settings, learned cards and routes too.)"
		: "(The settings, learned cards and routes in use are in the install; the other copy was saved in`n   " SuMovedSaved ")"
	msgResult := MsgBox("Wiz-Maxxing is installed in`n   " home "`n`nMove the download to the Recycle Bin?" list "`n`n" note, "Wiz-Maxxing setup", 262436)
	if (msgResult = "No")
		return SuLogLine("the download was left where it is")
	SuLogLine("== The download to the Recycle Bin")
	for i, f in [top]
		{
		;(the old bot's vision helper can take a few seconds to go after the bot)
		Loop 5
			{
			V1Do(FileRecycle, f)
			if (!FileExist(f))
				break
			Sleep(1500)
			}
		SuLogLine(FileExist(f) ? "couldn't move " f " (still in use? an Explorer window open in it?) - delete it yourself" : "to the Recycle Bin: " f)
		}
	for i, z in zips
		{
		V1Do(FileRecycle, z)
		SuLogLine(FileExist(z) ? "couldn't move " z : "to the Recycle Bin: " z)
		}
	}

;Whether folder parent holds child and nothing else
SuOnlyChild(parent, child)
	{
	n := 0, other := false
	Loop Files, parent "\*", "FD"
		{
		n++
		if (!SuSamePath(A_LoopFilePath, child))
			other := true
		}
	return n = 1 && !other
	}

SuInstallPython()
	{
	SuLogLine("== Python 3")
	if (SuPython() != "")
		return SuLogLine("already installed: " SuPython())
	if (SuWhere("winget.exe") != "")
		{
		SuLogLine("installing with winget (for you only - no admin)...")
		SuRun("winget install --id Python.Python.3.12 -e --scope user --silent --accept-package-agreements --accept-source-agreements")
		}
	if (SuPython() = "")
		{
		url := "https://www.python.org/ftp/python/3.12.7/python-3.12.7-amd64.exe"
		file := A_Temp "\python-3.12.7-amd64.exe"
		SuLogLine("downloading the installer from python.org: " url)
		V1Do(Download, url, file)
		if (ErrorLevel || !FileExist(file))
			return SuLogLine("couldn't download it - check the internet connection, or install Python 3 from https://www.python.org/downloads/ (tick 'Add python.exe to PATH')")
		SuLogLine("installing (for you only)...")
		V1RunWait("`"" file "`" /quiet InstallAllUsers=0 PrependPath=1 Include_launcher=1")
		SuLogLine("installer finished (exit " ErrorLevel ")")
		V1Do(FileDelete, file)
		}
	py := SuPython()
	SuLogLine(py != "" ? "Python is ready: " py : "Python still isn't found - install it from https://www.python.org/downloads/ and run Setup again")
	}

SuInstallPackages()
	{
	SuLogLine("== numpy and Pillow (and katsuba, optional)")
	SuLogLine("numpy and Pillow: the card matching and the zone map. katsuba: a spare reader of the game's zone files")
	py := SuPython()
	if (py = "")
		return SuLogLine("needs Python first")
	SuRun("`"" py "`" -m pip install --user --upgrade numpy pillow")
	ok := SuRun("`"" py "`" -c `"import numpy, PIL; print('numpy', numpy.__version__, '- Pillow', PIL.__version__)`"") = 0
	;(installed but broken - a DLL that won't load, a half-finished update: pip calls that "already satisfied" and leaves
	;it, so the packages are put in again from scratch, once)
	if (!ok)
		{
		SuLogLine("they don't load - installing them again from scratch")
		SuRun("`"" py "`" -m pip install --user --upgrade --force-reinstall --no-cache-dir numpy pillow")
		ok := SuRun("`"" py "`" -c `"import numpy, PIL; print('numpy', numpy.__version__, '- Pillow', PIL.__version__)`"") = 0
		}
	SuLogLine(ok ? "the vision helper's packages load" : "they still don't load - see the messages above")
	;(on its own and optional: the helper reads the zone files itself; katsuba is only its spare)
	SuRun("`"" py "`" -m pip install --user --upgrade katsuba")
	kt := SuRun("`"" py "`" -c `"import katsuba`"") = 0
	SuLogLine(kt ? "katsuba loads" : "katsuba didn't install - that's fine, it's only a spare (nothing needs it)")
	}

SuUnblock()
	{
	SuLogLine("== Unblock the bot's files")
	before := SuMarkedCount()
	SuRun("powershell -NoProfile -ExecutionPolicy Bypass -Command `"Get-ChildItem -LiteralPath '" A_ScriptDir "' -Recurse -File | Unblock-File`"")
	SuLogLine(before " file(s) were marked; " SuMarkedCount() " still are")
	}

SuShortcut()
	{
	SuLogLine("== Desktop shortcut")
	p := SuBotProgram()
	V1Do(FileCreateShortcut, p.target, A_Desktop "\Wiz-Maxxing.lnk", A_ScriptDir, p.args, "Wiz-Maxxing - the Wizard101 bot (battles and quest walking)")
	SuLogLine(ErrorLevel ? "couldn't make it" : "made: " A_Desktop "\Wiz-Maxxing.lnk -> " p.target (p.args = "" ? "" : " " p.args))
	;(the one an earlier Setup made, by its old name)
	if (FileExist(A_Desktop "\Wizard101 bot.lnk"))
		{
		;(v1: a shortcut it couldn't read - old blank; v2 throws, and leaves it unset)
		if (V1Do(FileGetShortcut, A_Desktop "\Wizard101 bot.lnk", &old))
			old := ""
		if (InStr(old, A_ScriptDir) = 1)
			V1Do(FileDelete, A_Desktop "\Wizard101 bot.lnk")
		}
	}

;Start menu: a Wiz-Maxxing folder with the bot, Setup, the stats reader and the quest walker on its own (only
;the ones that are here). Start-menu search finds them ("Wiz-Maxxing")
SuStartMenu(menuDir := "")
	{
	SuLogLine("== Start menu")
	if (menuDir = "")
		menuDir := A_Programs "\Wiz-Maxxing"
	V1Do(DirCreate, menuDir)
	made := 0
	;(each its exe - or its script when Setup runs as one: Watch.ahk BotProgram)
	for each, e in [["Wiz-Maxxing", "", A_ScriptDir, "The Wizard101 bot: battles and quest walking"]
		, ["Wiz-Maxxing Setup", A_ScriptDir "\Setup", A_ScriptDir, "Installs what the bot needs"]
		, ["Stats reader", A_ScriptDir "\AutoFarmer\StatsReader", A_ScriptDir "\AutoFarmer", "Reads your wizard's stats for the kill check"]
		, ["Quest walker only", A_ScriptDir "\AutoQuester\AutoQuester", A_ScriptDir "\AutoQuester", "Walks to the quest goal, no battles"]]
		{
		p := e[2] = "" ? SuBotProgram() : BotProgram(e[2])
		if (!FileExist(p.target) || (e[2] != "" && !FileExist(e[2] ".exe") && !FileExist(e[2] ".ahk")))
			continue
		V1Do(FileCreateShortcut, p.target, menuDir "\" e[1] ".lnk", e[3], p.args, e[4])
		if (!ErrorLevel)
			made++, SuLogLine("made: " e[1] " -> " p.target (p.args = "" ? "" : " " p.args))
		}
	SuLogLine(made ? made " shortcut(s) in " menuDir " - search the Start menu for Wiz-Maxxing" : "couldn't make any")
	}

;The GitHub token for updates: the page to make one opens, you paste it (hidden), it's tried, then kept in
;Windows Credential Manager. It's never shown or logged
SuToken()
	{
	global ErrorLevel ; (v1 globals it sets)
	SuLogLine("== GitHub updates")
	if (UpToken() != "" && UpTokenTest(UpToken()) = "")
		return SuLogLine("the saved token works")
	Run("https://github.com/settings/personal-access-tokens/new")
	MsgBox("A GitHub page opened (sign in if it asks). Make a token there:`n`n1. Token name: Wiz-Maxxing updates`n2. Expiration: the longest it offers (or No expiration)`n3. Repository access: Only select repositories -> Wiz-Maxxing`n4. Permissions -> Repository permissions -> Contents: Read-only, and Issues: Read and write (for the dashboard's Report a bug)`n5. Generate token, then copy it`n`nClick OK, then paste it into the next box.", "GitHub updates", 64)
	IB := InputBox("Paste the token (it's kept in Windows Credential Manager on this PC only):", "GitHub updates", "Password w560 h150"), token := IB.Value, ErrorLevel := IB.Result="OK" ? 0 : IB.Result="CANCEL" ? 1 : IB.Result="Timeout" ? 2 : "ERROR"
	if (ErrorLevel || Trim(token) = "")
		return SuLogLine("no token entered")
	token := Trim(token)
	why := UpTokenTest(token)
	if (why != "")
		{
		token := ""
		return SuLogLine("not saved: " why)
		}
	saved := UpTokenSave(token)
	token := ""
	SuLogLine(saved ? "saved - Wiz-Maxxing now checks for updates whenever you open it" : "couldn't save it in Credential Manager")
	}

;---- PATH and App Paths (envKey / appKey: other keys for tests) ----

;Whether this folder is on your PATH and Wiz-Maxxing.exe is in App Paths
SuPathOk(envKey := "HKCU\Environment", appKey := "HKCU\Software\Microsoft\Windows\CurrentVersion\App Paths\Wiz-Maxxing.exe")
	{
	;(v1's RegRead of a value that isn't there: blank - v2 throws)
	path := V1Try(RegRead, envKey, "Path")
	app := V1Try(RegRead, appKey)
	return SuInPath(path, A_ScriptDir) && app = A_ScriptDir "\Wiz-Maxxing.exe"
	}

;Whether dir is one of path's folders (any case, with or without a trailing \)
SuInPath(path, dir)
	{
	dir := RTrim(dir, "\")
	Loop Parse, path, "`;"
		if (RTrim(Trim(A_LoopField), "\") = dir)
			return true
	return false
	}

;Adds this folder to your PATH (your own, kept as it is otherwise) and Wiz-Maxxing.exe to App Paths, then
;tells Windows (new terminals and the Run box see it; already open ones don't)
SuAddPath(envKey := "HKCU\Environment", appKey := "HKCU\Software\Microsoft\Windows\CurrentVersion\App Paths\Wiz-Maxxing.exe")
	{
	SuLogLine("== Run box and PATH")
	path := V1Try(RegRead, envKey, "Path")
	if (SuInPath(path, A_ScriptDir))
		SuLogLine("this folder is on your PATH already")
	else
		{
		newPath := (Trim(path) = "" ? "" : RTrim(path, "; ") ";") A_ScriptDir
		V1Do(RegWrite, newPath, "REG_EXPAND_SZ", envKey, "Path")
		SuLogLine(ErrorLevel ? "couldn't add it to your PATH" : "added to your PATH: " A_ScriptDir)
		}
	exe := A_ScriptDir "\Wiz-Maxxing.exe"
	if (!FileExist(exe))
		return SuLogLine("no Wiz-Maxxing.exe here - the Run box entry is skipped")
	;(Setup run as a script - Smart App Control: the exe would be blocked; the shortcuts start the scripts)
	if (!A_IsCompiled)
		return SuLogLine("Setup runs as a script (Smart App Control?) - the Run box entry is skipped: use the Start menu or desktop shortcut")
	V1Do(RegWrite, exe, "REG_SZ", appKey)
	V1Do(RegWrite, A_ScriptDir, "REG_SZ", appKey, "Path")
	SuLogLine(ErrorLevel ? "couldn't add it to App Paths" : "Win+R: type Wiz-Maxxing")
	;(WM_SETTINGCHANGE "Environment" to every window)
	;(v1: result blank - 0; v2's DllCall wants the variable set)
	result := 0
	DllCall("SendMessageTimeout", "Ptr", 0xFFFF, "UInt", 0x1A, "Ptr", 0, "Str", "Environment", "UInt", 2, "UInt", 3000, "Ptr*", &result)
	}

;What starts the bot ({target, args}): the launcher (Wiz-Maxxing - its exe, or its script when Setup runs as one),
;else AutoFarmer\Autofarmer
SuBotProgram()
	{
	if (FileExist(A_ScriptDir "\Wiz-Maxxing.exe") || FileExist(A_ScriptDir "\Wiz-Maxxing.ahk"))
		return BotProgram(A_ScriptDir "\Wiz-Maxxing")
	return BotProgram(A_ScriptDir "\AutoFarmer\Autofarmer")
	}

SuInstallAhk()
	{
	SuLogLine("== AutoHotkey v2")
	if (SuAhk() != "")
		return SuLogLine("already installed: " SuAhk())
	;(v2 port: the scripts are v2 now - v1 downloaded v1.1's installer, ahk-install.exe, and ran it with /S; v2's
	;installer takes /silent /installto, and doesn't ask for admin itself - *RunAs: Windows asks, as it did for v1.1's)
	url := "https://www.autohotkey.com/download/ahk-v2.exe"
	file := A_Temp "\ahk-v2-install.exe"
	SuLogLine("downloading the v2 installer from autohotkey.com...")
	V1Do(Download, url, file)
	if (ErrorLevel || !FileExist(file))
		return SuLogLine("couldn't download it - get it from https://www.autohotkey.com/")
	SuLogLine("installing (Windows asks for admin)...")
	V1RunWait("*RunAs `"" file "`" /silent /installto `"" A_ProgramFiles "\AutoHotkey`"")
	;(v1: the "exit" below was this FileDelete's ErrorLevel - 0 deleted, 1 not - not the installer's exit code)
	V1Do(FileDelete, file)
	SuLogLine(SuAhk() != "" ? "AutoHotkey v2 is ready - build.cmd can rebuild the exes" : "it isn't found after the installer (exit " ErrorLevel ") - get it from https://www.autohotkey.com/ (its compiler: AutoHotkey's Dash > Compile)")
	}

SuInstallGit()
	{
	SuLogLine("== Git")
	if (SuWhere("git.exe") != "")
		return SuLogLine("already installed")
	if (SuWhere("winget.exe") = "")
		return SuLogLine("no winget here - install Git from https://git-scm.com/download/win")
	SuLogLine("installing with winget (Windows asks for admin)...")
	SuRun("winget install --id Git.Git -e --silent --accept-package-agreements --accept-source-agreements")
	SuLogLine(SuWhere("git.exe") != "" ? "Git is ready (open a new PowerShell window to use it)" : "Git isn't found yet - open a new window, or install it from https://git-scm.com/download/win")
	}

;Cheat Engine for the bot's speedhack: installed if it isn't (SuGetCheatEngine), the bot's script in its autorun folder
;(SuCePut), then - if you say so - the bot's speedhack setting on
SuInstallCe()
	{
	SuLogLine("== Cheat Engine speedhack")
	SuLogLine("Cheat Engine speeds the game up while the bot walks. Risky: KingsIsle may notice")
	text := SuCeScript()
	if (text = "")
		return SuLogLine("CheatEngine\wiz-maxxing.lua isn't in " A_ScriptDir " - download the bot's zip again")
	ce := CeDir()
	if (ce = "")
		ce := SuGetCheatEngine()
	if (ce = "")
		return
	SuLogLine("Cheat Engine: " ce)
	if (!SuCePut(ce, text))
		return SuLogLine("the bot's script couldn't be put in " ce "\autorun (admin not given?) - nothing else done")
	SuLogLine("the bot's script is in its autorun folder (wiz-maxxing.lua): each time Cheat Engine starts it attaches to Wizard101 by itself (again after the game exits), and the bot's keys set the speed - the walking key speeds up the Wizard101 window in front, so another account's window is never sped up - " SuCeKeys())
	SuLogLine("Cheat Engine's own Settings > Hotkeys entries for those keys aren't needed now (clear them if you set them before)")
	if (CeRunning())
		SuLogLine("Cheat Engine is running - close it and start it again: the script runs when it starts")
	stats := A_ScriptDir "\AutoFarmer\PlayerStats.txt"
	if (SuStat(stats, "speedhack") = "1")
		return SuLogLine("the bot's speedhack setting is on: the bot starts Cheat Engine when it starts")
	if (MsgBox("Cheat Engine is set up for the bot.`n`nSwitch the bot's speedhack on now (its Settings: `"Walk faster with Cheat Engine's speedhack`")? The bot then starts Cheat Engine when it starts.`n`nRisky: KingsIsle may notice.", "Wizard101 bot setup", 36) != "Yes")
		return SuLogLine("the bot's speedhack setting left off - switch it on in its Settings when you want it")
	if (WatchBotRunning())
		return SuLogLine("the bot is running - switch it on in its Settings window (`"Walk faster with Cheat Engine's speedhack`")")
	SuLogLine(SuStatSet(stats, "speedhack", 1) ? "the bot's speedhack setting is on (PlayerStats.txt): the bot starts Cheat Engine when it starts" : "couldn't write " stats " - switch it on in the bot's Settings window")
	}

;Cheat Engine from cheatengine.org: its installer downloaded and opened for you to click through - one of its pages
;recommends other programs: Decline it. Never silently (/VERYSILENT): that takes those offers. Opened only when Windows
;finds a valid signature on it, and you've seen whose; otherwise its download page opens (SuCeByHand). Its folder, "" if not
SuGetCheatEngine()
	{
	page := "https://www.cheatengine.org/downloads.php"
	if (MsgBox("Cheat Engine isn't installed.`n`nSetup downloads its installer from cheatengine.org and opens it for you to click through. One of its pages recommends other programs - Decline them: the bot needs only Cheat Engine. Antivirus programs may warn about Cheat Engine.`n`nUsing its speedhack in Wizard101 is risky: KingsIsle may notice.`n`nDownload Cheat Engine's installer?", "Wizard101 bot setup", 36) != "Yes")
		return SuSay("Cheat Engine not installed - nothing done", "")
	html := A_Temp "\su_ce_downloads.html"
	V1Do(Download, page, html)
	text := V1FileRead(html)
	V1Do(FileDelete, html)
	;(its Windows download: a cloudfront link to an .exe - its name changes with every version)
	url := RegExMatch(text, "i)https://[a-z0-9.-]+\.cloudfront\.net/[^\x22'<>\s]+\.exe", &suM) ? suM[0] : ""
	if (url = "" && RegExMatch(text, "i)https://[^\x22'<>\s]+\.exe", &suM))
		url := suM[0]
	if (url = "")
		return SuCeByHand(page, "its download link wasn't found on " page)
	file := A_Temp "\CheatEngineSetup.exe"
	SuLogLine("downloading Cheat Engine's installer: " url)
	V1Do(FileDelete, file)
	V1Do(Download, url, file)
	if (ErrorLevel || !FileExist(file) || FileGetSize(file) < 1000000)
		return SuCeByHand(page, "couldn't download it")
	signer := SuSigner(file)
	if (signer = "")
		{
		V1Do(FileDelete, file)
		return SuCeByHand(page, "Windows finds no valid signature on the downloaded installer - not opened")
		}
	SuLogLine("its installer is signed by: " signer)
	if (MsgBox("Cheat Engine's installer is downloaded - signed by:`n" signer "`n`nOpen it? Click through it yourself, and Decline the other programs it recommends.", "Wizard101 bot setup", 36) != "Yes")
		{
		V1Do(FileDelete, file)
		return SuSay("not opened - nothing done", "")
		}
	SuLogLine("opening it - Decline the other programs it recommends...")
	V1RunWait("`"" file "`"")
	SuLogLine("its installer closed (exit " ErrorLevel ")")
	;(an installer that starts another and closes: waited for)
	if (CeDir() = "")
		MsgBox("Press OK once Cheat Engine's installer has finished.", "Wizard101 bot setup", 64)
	V1Do(FileDelete, file)
	ce := CeDir()
	return ce != "" ? ce : SuCeByHand(page, "Cheat Engine still isn't found")
	}

;Cheat Engine's download page opened instead: why in the log, and what to do. ""
SuCeByHand(page, why)
	{
	SuLogLine(why)
	V1Run(page)
	SuLogLine("its download page is open: install Cheat Engine from there (Decline the other programs its installer recommends), then tick `"Cheat Engine speedhack`" and press Install again")
	return ""
	}

;Whose valid signature an exe carries (Windows' Authenticode check), "" if none
SuSigner(file)
	{
	tmp := A_Temp "\su_signer.txt"
	V1RunWait(A_ComSpec " /c powershell -NoProfile -ExecutionPolicy Bypass -Command `"$s = Get-AuthenticodeSignature -LiteralPath '" StrReplace(file, "'", "''") "'; if ($s.Status -eq 'Valid') { $s.SignerCertificate.GetNameInfo('SimpleName', $false) }`" > `"" tmp "`" 2>nul", , "Hide")
	out := Trim(V1FileRead(tmp), " `t`r`n")
	V1Do(FileDelete, tmp)
	return out
	}

;The bot's script for Cheat Engine (CheatEngine\wiz-maxxing.lua) with this folder's PlayerStats.txt written in
;(CheatEngine.ahk CeScriptText - the bot builds it the same way, to tell an older copy in Cheat Engine). "" if the file
;isn't here
SuCeScript()
	{
	return CeScriptText(A_ScriptDir)
	}

;The bot's script into Cheat Engine's autorun folder: as you, else - Program Files - Windows asks for admin. True if it's
;there as it should be
SuCePut(ce, text)
	{
	dest := CeScriptPath(ce)
	tmp := A_Temp "\wiz-maxxing.lua"
	V1Do(FileDelete, tmp)
	V1Do(FileAppend, text, tmp, "UTF-8-RAW")
	if (ErrorLevel)
		return SuSay("couldn't write " tmp, false)
	V1Do(DirCreate, ce "\autorun")
	V1Do(FileCopy, tmp, dest, 1)
	if (V1FileRead(dest, "UTF-8") !== text)
		{
		SuLogLine("putting it in " ce "\autorun (Windows asks for admin)...")
		V1RunWait("*RunAs `"" A_ComSpec "`" /c mkdir `"" ce "\autorun`" 2>nul & copy /y `"" tmp "`" `"" dest "`"", , "Hide")
		}
	ok := V1FileRead(dest, "UTF-8") == text
	V1Do(FileDelete, tmp)
	return ok
	}

;The bot's speed keys and speed for the log, as its Settings have them: "F14 = 2x (walking), F13 = 1x"
SuCeKeys()
	{
	stats := A_ScriptDir "\AutoFarmer\PlayerStats.txt"
	fast := SuStat(stats, "speedkeyfast"), normal := SuStat(stats, "speedkeynormal"), factor := SuStat(stats, "speedfactor")
	fast := (IsInteger(fast) && fast >= 1 && fast <= 12) ? fast : 2
	normal := (IsInteger(normal) && normal >= 1 && normal <= 12) ? normal : 1
	factor := IsNumber(factor) && factor >= 1 ? Min(factor, 50) : 2
	return "F" (12 + fast) " = " factor "x (walking), F" (12 + normal) " = 1x"
	}

;A setting's value in PlayerStats.txt (its plain key:value line, not a school's), "" if it isn't there
SuStat(file, key)
	{
	Loop Parse, V1FileRead(file), "`n", "`r"
		if (RegExMatch(A_LoopField, "i)^\s*\Q" key "\E\s*:\s*([^;\s]*)", &suM))
			return suM[1]
	return ""
	}

;A setting written in PlayerStats.txt as the bot's Settings window writes it (Settings.ahk CfgWrite): its line changed,
;comment kept; else added at the end under that window's heading. True if written
SuStatSet(file, key, value)
	{
	text := V1FileRead(file)
	if (ErrorLevel || !InStr(text, ":"))
		return false
	lines := StrSplit(StrReplace(text, "`r"), "`n")
	if (lines.Length && lines[lines.Length] = "")
		lines.Pop()
	found := false
	for i, line in lines
		if (RegExMatch(line, "i)^(\s*\Q" key "\E\s*:\s*)[^;\s]*(.*)$", &suM))
			lines[i] := suM[1] value suM[2], found := true
	if (!found)
		{
		head := "; ---- Set in the Settings window (the dashboard's Settings menu) ----"
		;(the heading before v1.10.0, naming the dashboard's Settings button, counts too: no second heading)
		oldHead := "; ---- Set in the Settings window (the dashboard's Settings button) ----"
		hasHead := false
		for i, line in lines
			if (line == head || line == oldHead)
				hasHead := true
		if (!hasHead)
			lines.Push(""), lines.Push(head)
		lines.Push(key ":" value)
		}
	out := ""
	for i, line in lines
		out .= line "`r`n"
	V1Do(FileDelete, file ".tmp")
	V1Do(FileAppend, out, file ".tmp")
	if (ErrorLevel)
		return false
	V1Do(FileMove, file ".tmp", file, 1)
	return !ErrorLevel
	}

;---- finding things ----

;python.exe whose pythonw.exe the bot's vision helper will find (Vision.ahk: on the PATH or in
;%LOCALAPPDATA%\Programs\Python\Python3*) - never the Microsoft Store stub (WindowsApps)
SuPython()
	{
	pathVar := EnvGet("PATH")
	Loop Parse, pathVar, "`;"
		{
		dir := Trim(A_LoopField)
		if (dir != "" && !InStr(dir, "WindowsApps") && FileExist(dir "\pythonw.exe") && FileExist(dir "\python.exe"))
			return dir "\python.exe"
		}
	best := ""
	Loop Files, A_AppData "\..\Local\Programs\Python\Python3*", "D"
		if (FileExist(A_LoopFilePath "\pythonw.exe") && FileExist(A_LoopFilePath "\python.exe"))
			best := A_LoopFilePath "\python.exe"
	return best
	}

;Ahk2Exe with a v2 base, i.e. what build.cmd needs ("" if not): v2's AutoHotkey64.exe - in v2\ (a v2.x.y folder
;when several are installed), or the root's when it's v2. (v2 port: the scripts are v2 now - v1 looked for a v1.1 base,
;the v1 installer's Unicode 64-bit.bin or v1.1's AutoHotkeyU64.exe, the same way)
SuAhk()
	{
	for each, root in [A_ProgramFiles "\AutoHotkey", A_AppData "\..\Local\Programs\AutoHotkey"]
		{
		if (!FileExist(root "\Compiler\Ahk2Exe.exe"))
			continue
		if (SubStr(V1Try(FileGetVersion, root "\AutoHotkey64.exe"), 1, 2) = "2.")
			return root
		Loop Files, root "\v2*", "D"
			if (SubStr(V1Try(FileGetVersion, A_LoopFilePath "\AutoHotkey64.exe"), 1, 2) = "2.")
				return root
		}
	return ""
	}

;A program on the PATH (as the system sees it now: after an install the PATH of this process is old)
SuWhere(exe)
	{
	;(v1's RegRead of a value that isn't there: blank - v2 throws)
	sysPath := V1Try(RegRead, "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Environment", "Path")
	userPath := V1Try(RegRead, "HKCU\Environment", "Path")
	procPath := EnvGet("PATH")
	all := procPath ";" sysPath ";" userPath
	Loop Parse, all, "`;"
		{
		dir := Trim(A_LoopField)
		if (dir = "")
			continue
		;(%USERPROFILE% and the like, as the registry keeps them)
		if (InStr(dir, "%"))
			{
			buf := Buffer(4096 * 2, 0)
			DllCall("ExpandEnvironmentStrings", "Str", dir, "Ptr", buf, "UInt", 4096)
			dir := StrGet(buf)
			}
		if (FileExist(dir "\" exe))
			return dir "\" exe
		}
	if (exe = "winget.exe" && FileExist(A_AppData "\..\Local\Microsoft\WindowsApps\winget.exe"))
		return A_AppData "\..\Local\Microsoft\WindowsApps\winget.exe"
	return ""
	}

;How many of the bot's files carry the "downloaded from the internet" mark (Zone.Identifier)
SuMarkedCount()
	{
	tmp := A_Temp "\su_marked.txt"
	V1RunWait(A_ComSpec " /c powershell -NoProfile -ExecutionPolicy Bypass -Command `"(Get-ChildItem -LiteralPath '" A_ScriptDir "' -Recurse -File | Get-Item -Stream Zone.Identifier -ErrorAction SilentlyContinue | Measure-Object).Count`" > `"" tmp "`" 2>nul", , "Hide")
	n := V1FileRead(tmp)
	V1Do(FileDelete, tmp)
	n := Trim(n, " `t`r`n")
	return (n ~= "^\d+$") ? n + 0 : 0
	}

;---- running and the log ----

;Runs a command hidden and puts what it printed in the log (log false: quietly). Its exit code
SuRun(cmd, log := true)
	{
	tmp := A_Temp "\su_out_" A_TickCount ".txt"
	if (log)
		SuLogLine("> " cmd)
	V1RunWait(A_ComSpec " /c `"" cmd " > `"" tmp "`" 2>&1`"", A_ScriptDir, "Hide")
	code := ErrorLevel
	if (log)
		{
		out := V1FileRead(tmp)
		;(progress bars: only what's left after the last carriage return of each line)
		text := ""
		Loop Parse, out, "`n"
			{
			;(a line can also end in two: pip's do)
			line := RegExReplace(RTrim(A_LoopField, "`r"), "s).*\r", "")
			line := RTrim(RegExReplace(line, "[^\x20-\x7E]", ""), " ")
			if (line != "" && !RegExMatch(line, "^[\s\-\\|/]+$"))
				text .= "   " line "`r`n"
			}
		if (text != "")
			SuAppend(text)
		SuLogLine("  (exit code " code ")")
		}
	V1Do(FileDelete, tmp)
	return code
	}

SuLogLine(text)
	{
	SuAppend(text "`r`n")
	}

SuAppend(text)
	{
	len := DllCall("GetWindowTextLength", "Ptr", SuLogHwnd)
	DllCall("SendMessage", "Ptr", SuLogHwnd, "UInt", 0xB1, "Ptr", len, "Ptr", len)
	DllCall("SendMessage", "Ptr", SuLogHwnd, "UInt", 0xC2, "Ptr", 0, "Str", text)
	DllCall("SendMessage", "Ptr", SuLogHwnd, "UInt", 0xB7, "Ptr", 0, "Ptr", 0)
	}

;A long path shortened for the status column
SuShort(path)
	{
	return StrLen(path) > 48 ? "..." SubStr(path, -45) : path
	}

#Include "%A_ScriptDir%\Updater.ahk"
#Include "%A_ScriptDir%\Watch.ahk"
#Include "%A_ScriptDir%\CheatEngine.ahk"
#Include "%A_ScriptDir%\V1Compat.ahk" ; (v2 port: the v1 behaviours it keeps)

;###############  v1's labels, as functions  ###############
SuInstall(A_GuiEvent:="", A_GuiControl:="", Info:="", *) { ; (v1: the label SuInstall - the Install button's, and gosub)
	global
	if (SuBusy)
		return
	V1GuiSubmit(Su, false)
	SuBusy := 1
	Su["SuGo"].Enabled := false
	;(first: copied to the Programs folder - Setup starts again from there and does the rest; this one goes)
	if (SuIn)
		{
		suHomeRes := SuInstallHome()
		if (suHomeRes = 1)
			ExitApp()
		if (suHomeRes = -1)
			{
			SuLogLine("")
			SuLogLine("Stopped: nothing else was done (see above). Untick `"Install to your Programs folder`" to set this folder up as it is.")
			Su["SuGo"].Enabled := true
			SuBusy := 0
			return
			}
		}
	if (SuPy)
		SuInstallPython()
	if (SuPk)
		SuInstallPackages()
	if (SuUn)
		SuUnblock()
	if (SuUp)
		SuToken()
	if (SuSm)
		SuStartMenu()
	if (SuSh)
		SuShortcut()
	if (SuPa)
		SuAddPath()
	if (SuWa)
		{
		SuLogLine("== Open with Wizard101")
		SuLogLine(WatchSet(A_ScriptDir, true) ? "on: a watcher starts with Windows (" WatchLink() ") and opens the bot in standby when Wizard101 starts - press " WatchBotKey(A_ScriptDir "\AutoFarmer") " in the game to start it" : "couldn't make the Startup folder's shortcut")
		}
	if (SuCe)
		SuInstallCe()
	if (SuAh)
		SuInstallAhk()
	if (SuGi)
		SuInstallGit()
	SuLogLine("")
	SuLogLine("Done. The statuses above are looked at again.")
	SuCheck()
	Su["SuGo"].Enabled := true
	SuBusy := 0
	return
}
;##############################################
SuStartBot(A_GuiEvent:="", A_GuiControl:="", Info:="", *) { ; (v1: the label SuStartBot - the Start the bot button's)
	global
	local v1Keep := V1Thread() ; (v1: each thread had its own ErrorLevel)
	;(the launcher - its exe, or its script when Setup runs as one: Watch.ahk BotProgram)
	if (FileExist(A_ScriptDir "\Wiz-Maxxing.exe") || FileExist(A_ScriptDir "\Wiz-Maxxing.ahk"))
		{
		BotRun(A_ScriptDir "\Wiz-Maxxing", "", A_ScriptDir)
		return
		}
	if (FileExist(A_ScriptDir "\AutoFarmer\Autofarmer.exe") || SuAhk() != "")
		BotRun(A_ScriptDir "\AutoFarmer\Autofarmer", "", A_ScriptDir "\AutoFarmer")
	else
		MsgBox("There's no AutoFarmer\Autofarmer.exe here - download the zip from the GitHub Releases page (it has the exes), or install AutoHotkey v2 and run build.cmd.", "Wizard101 bot setup", 48)
	return
}
;##############################################
SuGuiClose(A_GuiEvent:="", A_GuiControl:="", Info:="", *) { ; (v1: the labels SuGuiClose and SuGuiEscape - one body; the Close button's)
global
;(v1: the window stayed open when the GuiClose label returned - v2 hides it unless the Close callback returns true)
return SuGuiEscape()
}
;##############################################
SuGuiEscape(*) { ; (v1: the label SuGuiEscape)
	global
	if (SuBusy)
		{
		msgResult := MsgBox("Setup is still installing. Close anyway?", "Wizard101 bot setup", 52)
		if (msgResult = "No")
			return true
		}
	ExitApp()
}

;(v2 port, CONVENTIONS.md "Blank start": v1 started every variable blank; v2 leaves it unset and throws on
;reading it. The entry script calls this first thing: this file's globals start blank, as in v1)
SetupBlank()
	{
	global SuLog := "", SuPyS := "", SuPkS := "", SuUnS := "", SuShS := "", SuAhS := "", SuGiS := "", SuPy := "", SuPk := "", SuUn := "", SuSh := ""
	global SuAh := "", SuGi := "", SuGo := "", SuStart := "", SuSm := "", SuSmS := "", SuUp := "", SuUpS := "", SuPa := "", SuPaS := "", SuWa := ""
	global SuWaS := "", SuIn := "", SuInS := "", SuLogHwnd := "", SuBusy := "", SuMovedFrom := "", SuMovedDo := "", SuMovedPid := ""
	global SuCe := "", SuCeS := ""
	global SuMovedSaved := ""
	}
