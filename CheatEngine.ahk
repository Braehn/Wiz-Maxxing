#Warn Unreachable, Off
; CheatEngine.ahk - Cheat Engine for the speedhack (AutoFarmer's Settings: "Walk faster with Cheat Engine's speedhack"):
; where it's installed, whether the bot's script is in its autorun folder, and starting it. #Included by Setup.ahk
; ("Cheat Engine speedhack": installs Cheat Engine, puts the script there) and AutoFarmer\Autofarmer.ahk (starts Cheat
; Engine when the speedhack's on). AutoHotkey v2.
;
; The script, CheatEngine\wiz-maxxing.lua (its own lines say what it does): Cheat Engine runs it every time it starts -
; it attaches itself to Wizard101 (again after the game restarts) and the bot's two speedhack keys set the speed, read
; from the bot's PlayerStats.txt. Nobody sets up Cheat Engine's hotkeys or attaches it by hand any more.

;Cheat Engine's folder, "" if it isn't installed: its uninstall entry (Inno Setup's "Cheat Engine 7.x_is1") with
;Cheat Engine in it, else the usual places (Program Files, yours) - the newest name when there are several
CeDir()
	{
	for each, root in ["HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall"
		, "HKLM\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall", "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall"]
		{
		try
			{
			Loop Reg, root, "K"
				{
				ceKey := A_LoopRegKey "\" A_LoopRegName
				if (!RegExMatch(A_LoopRegName, "i)^Cheat Engine") && !RegExMatch(V1Try(RegRead, ceKey, "DisplayName"), "i)^Cheat Engine"))
					continue
				cdDir := RTrim(V1Try(RegRead, ceKey, "InstallLocation"), "\")
				if (cdDir != "" && CeExe(cdDir) != "")
					return cdDir
				}
			}
		}
	ceBest := ""
	for each, root in [A_ProgramFiles, EnvGet("ProgramFiles(x86)"), EnvGet("LOCALAPPDATA") "\Programs"]
		{
		if (root = "" || root = "\Programs")
			continue
		Loop Files, root "\Cheat Engine*", "D"
			if (CeExe(A_LoopFilePath) != "" && (ceBest = "" || StrCompare(A_LoopFileName, ceBest[2], "Logical") > 0))
				ceBest := [A_LoopFilePath, A_LoopFileName]
		}
	return ceBest = "" ? "" : ceBest[1]
	}

;Cheat Engine's program in its folder: "Cheat Engine.exe" (it starts the build that suits this PC), else the 64-bit
;one itself. "" if neither is there
CeExe(dir)
	{
	for each, name in ["Cheat Engine.exe", "cheatengine-x86_64-SSE4-AVX2.exe", "cheatengine-x86_64.exe"]
		if (FileExist(dir "\" name))
			return dir "\" name
	return ""
	}

;The bot's script as Cheat Engine runs it: <Cheat Engine>\autorun\wiz-maxxing.lua
CeScriptPath(dir)
	{
	return dir "\autorun\wiz-maxxing.lua"
	}

;Whether Cheat Engine is running (any of its builds): its pid, else 0
CeRunning()
	{
	for each, name in ["cheatengine-x86_64-SSE4-AVX2.exe", "cheatengine-x86_64.exe", "cheatengine-i386.exe", "Cheat Engine.exe"]
		if (cePid := ProcessExist(name))
			return cePid
	return 0
	}

;Cheat Engine started from its folder, its window minimized once it shows (CeMinimizeSoon: "Cheat Engine.exe" only
;starts the build that suits this PC, at full size - Run's "Min" never reaches that window). False if Windows wouldn't
CeStart(dir)
	{
	csExe := CeExe(dir)
	if (csExe = "" || V1Run("`"" csExe "`"", dir, "Min") != 0)
		return false
	CeMinimizeSoon(true)
	return true
	}

;Cheat Engine's main window minimized as soon as it shows: looked for 4 times a second for 20 s after CeStart, on a
;timer - nothing waits for it. A shown window of one of its builds whose title starts "Cheat Engine" ("Cheat Engine
;7.5"); never one of its message boxes (a box from the bot's script stays for you to read). Minimized the way its
;own minimize button does it (WM_SYSCOMMAND SC_MINIMIZE), so Cheat Engine minimizes itself; Windows gives the focus
;back to the window you had. start: true from CeStart - only (re)starts the 20 s
CeMinimizeSoon(start := false)
	{
	static cmsLeft := 0
	if (start)
		{
		cmsLeft := 80
		SetTimer(CeMinimizeSoon, -250)
		return
		}
	cmsLeft--
	DetectHiddenWindows(false)
	for each, cmsName in ["cheatengine-x86_64-SSE4-AVX2.exe", "cheatengine-x86_64.exe", "cheatengine-i386.exe"]
		for each, cmsHwnd in V1Try(WinGetList, "ahk_exe " cmsName) || []
			if (SubStr(V1Try(WinGetTitle, "ahk_id " cmsHwnd), 1, 12) = "Cheat Engine"
				&& V1Try(WinGetClass, "ahk_id " cmsHwnd) != "#32770")
				{
				cmsLeft := 0
				try PostMessage(0x0112, 0xF020, 0, , "ahk_id " cmsHwnd)
				return
				}
	if (cmsLeft > 0)
		SetTimer(CeMinimizeSoon, -250)
	}
