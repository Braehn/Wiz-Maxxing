; Reconnect.ahk - gets Wizard101 back online by itself after a disconnect. AHK v1.1, functions only,
; #Included by Autofarmer.ahk, whose main loop calls ReconnectCheck() on every pass.
;
; How it knows: the game writes what it's doing to Bin\WizardClient.log as it happens. A disconnect is a
; "DisplayMessageBox(" line there, e.g. "You have been disconnected due to inactivity." (key
; GUI_ConnectionAFK - about 15 minutes with no input outside battle) or "Connection Lost!"
; (GUI_ConnectionLost). The box the game draws for it has RECONNECT and QUIT buttons.
;
; What it does:
;  1. A disconnect box is up: finds RECONNECT on screen (OCR, word by word, so never QUIT) and clicks
;     it. The game logs back in with the launcher's session - no password - and puts you back where
;     you were in about 5 s. It first clicks without bringing the game to the front; if the game
;     ignores that, it brings the game up for a moment, clicks, and gives focus back.
;  2. Still on the character select screen 6 s after logging back in: brings the game to the front
;     and clicks Play (that screen ignores background clicks), then gives focus back.
;  3. The game closed (a crash, or Quit): asks for 60 s whether to start it again (yes if nobody
;     answers), then starts it and logs in with the login saved with "Set Wizard101 login..." in the
;     tray menu. That's kept in Windows Credential Manager (encrypted, as "Wizard101Bot"), never in a
;     file, never written to debug.log, and only typed into the game's own login box once that box can
;     be seen - and Enter is only pressed once the username can be read back in it.
;  4. "Client is out of date" (a patch came out during maintenance): closes the game and starts the
;     launcher, fills in the login there so it can patch, and the launcher starts the game.
;  A failed try waits longer before the next: 30 s, 1, 2, 4 minutes, then every 10 minutes (servers
;  down for maintenance: 10 minutes straight away). After 6 failed RECONNECTs it restarts the game
;  (step 3). A login the game turns down is never typed again until it's saved again.
;
; Needs from the including script: the super-globals GameExe, GameClass, GameLeft, GameTop, GameW, GameH
; (kept up to date by its UpdateGameRect()), UiScale (optional), OcrRect() (Ocr.ahk), and optionally
; DebugLog(), UpdateGameRect() and ReleaseKeys(). Locals must not share a name with any super-global of
; the including script (AHK names are case-insensitive).

global RcOn, RcLog, RcPos, RcPid, RcExe, RcState, RcStateAt, RcMsg, RcTries, RcNext, RcLookAt
global RcCheckAt, RcProcAt, RcClickBg, RcLastBg, RcClickAt, RcCharAt, RcPlayTries, RcNoRelaunch
global RcLoginBad, RcNote, RcScanning, RcTyped, RcCredTarget, RcHead, RcPeekAt, RcPeeks, RcFrontOk, RcFindInfo
;A zone change under way by the game's log (when it began, 0 none), when the log last wrote anything but its memory
;notes, and a restart of a hung game (RcHungCheck) already asked about - RcGone doesn't ask again
global RcLoadAt, RcLastLineAt, RcHungAsked
;Restarts for a hang: how many, since when (two in an hour: left to you)
global RcHungCount, RcHungFirstAt
;(v2-only globals - the port tools don't know them: blank in ReconnectBlank, set in ReconnectInit)
;A relog: when the game was last back in the world after one (the bot's reconnect, or a character picked - yours too; 0 none since the
;start: the walker's sigil that won't start counts fewer X presses after one - RcBackAgo), and when a character was picked (0 none)
global RcBackAt, RcCharSelAt

;Call once at start. Picks up a disconnect box that's already showing
ReconnectInit()
	{
	global RcCredTarget, RcOn, RcState, RcStateAt, RcTries, RcNext, RcLookAt, RcCheckAt, RcProcAt, RcClickBg, RcLastBg ; (v1 globals it sets)
	global RcClickAt, RcCharAt, RcPlayTries, RcNoRelaunch, RcLoginBad, RcNote, RcTyped, RcMsg, RcHead, RcPeekAt, RcPeeks ; (v1 globals it sets)
	global RcLoadAt, RcLastLineAt, RcHungAsked, RcHungCount, RcHungFirstAt, ErrorLevel, RcPid, RcPos, RcScanning ; (v1 globals it sets)
	global RcBackAt, RcCharSelAt ; (v2-only: the port tools don't know them)
	RcCredTarget := "Wizard101Bot"
	RcOn := 1, RcState := "", RcStateAt := A_TickCount, RcTries := 0, RcNext := 0, RcLookAt := 0
	RcCheckAt := 0, RcProcAt := 0, RcClickBg := -1, RcLastBg := 0, RcClickAt := 0, RcCharAt := 0
	RcPlayTries := 0, RcNoRelaunch := 0, RcLoginBad := 0, RcNote := 0, RcTyped := 0, RcMsg := ""
	RcHead := "", RcPeekAt := 0, RcPeeks := 0, RcLoadAt := 0, RcLastLineAt := A_TickCount, RcHungAsked := 0
	RcHungCount := 0, RcHungFirstAt := 0, RcBackAt := 0, RcCharSelAt := 0
	ErrorLevel := ProcessExist(GameExe)
	RcPid := ErrorLevel
	RcSetClient(RcFindClient())
	;Replay the end of the game's log (quietly) to see where things stand
	RcPos := 0
	;(v1: no log yet - its size blank, not > 131072)
	logSize := V1Try(FileGetSize, RcLog)
	if (V1Gt(logSize, 131072))
		RcPos := logSize - 131072
	RcScanning := 1
	RcReadLog()
	RcScanning := 0
	if ((RcState = "box" || RcState = "outdated") && RcPid)
		{
		RcTries := 0, RcNext := 0, RcStateAt := A_TickCount
		RcLogMsg("a disconnect box is already up: `"" RcMsg "`"")
		}
	;Started (or restarted) in the middle of getting back in after a disconnect: carry on from there
	else if ((RcState = "select" || RcState = "enter") && RcPid)
		{
		RcTries := 0, RcNext := 0, RcStateAt := A_TickCount
		RcLogMsg("the game is logging back in after a disconnect (" (RcState = "select" ? "character select" : "going into the world") ")")
		}
	else
		RcState := "", RcTries := 0
	A_TrayMenu.Check("Auto-reconnect on/off")
	return true
	}

;Call on every pass of the main loop. True while it's getting back online (the caller then skips
;battles and walking)
ReconnectCheck()
	{
	global RcProcAt, ErrorLevel, RcPid, RcNoRelaunch, RcLoadAt, RcLastLineAt, RcHungAsked, RcTries, RcNext, RcCheckAt ; (v1 globals it sets)
	;(off: the log still read, for a relog only - the walker's sigil that won't start, RcBackAgo; RcLogLine does nothing else
	;while off. It also keeps RcPos current: switched back on, the lines from while it was off aren't replayed as new)
	if (!RcOn)
		{
		if (A_TickCount - RcCheckAt >= 1000)
			RcCheckAt := A_TickCount, RcReadLog()
		return false
		}
	nowMs := A_TickCount
	;Is the game still running? A new game process starts a new log, from the top
	if (nowMs - RcProcAt >= 2000)
		{
		RcProcAt := nowMs
		ErrorLevel := ProcessExist(GameExe)
		gamePid := ErrorLevel
		if (gamePid && gamePid != RcPid)
			{
			;(its new log is told apart from the old one by its first line: see RcReadLog)
			RcPid := gamePid, RcNoRelaunch := 0, RcLoadAt := 0, RcLastLineAt := nowMs, RcHungAsked := 0
			RcSetClient(RcFindClient())
			if (RcState = "gone" || RcState = "stopped")
				RcSet("", "the game is running again")
			}
		else if (!gamePid && RcPid)
			{
			RcPid := 0, RcLoadAt := 0
			if (RcState != "patch")
				{
				;Closed by itself (not during one of our own restarts): count tries afresh
				if (!RcTyped && RcState != "start")
					RcTries := 0, RcNext := 0
				RcSet("gone", "the game has closed")
				}
			}
		}
	if (nowMs - RcCheckAt >= 1000)
		{
		RcCheckAt := nowMs
		RcReadLog()
		}
	;(online: a loading screen that never finishes - RcHungCheck)
	if (RcState = "")
		RcHungCheck()
	if (RcState = "" || RcState = "stopped")
		return false
	return RcStep()
	}

;One step of getting back online, by state. True while it's busy
RcStep()
	{
	global RcLookAt, RcTries, RcPlayTries, RcPeekAt, RcNote, RcLastBg, RcClickBg ; (v1 globals it sets)
	nowMs := A_TickCount
	if (RcState = "box")
		{
		if (nowMs < RcNext)
			{
			RcStatus("disconnected - trying again in " Ceil((RcNext - nowMs) / 1000) " s")
			return true
			}
		;The first minute: look every second, and the bot waits. After that, if it still can't see the
		;button (the screen asleep, a screensaver, the game covered...): let the bot carry on meanwhile
		;and look again every 30 s - the game only says "disconnected" once, so never give up on it
		early := nowMs - Max(RcStateAt, RcNext) <= 60000
		if (nowMs - RcLookAt < (early ? 1000 : 30000))
			return early
		RcLookAt := nowMs
		;RECONNECT keeps failing: maybe the session ran out - start the game afresh (needs the login)
		if (RcTries >= 6 && !RcLoginBad && RcHaveLogin())
			{
			RcTries := 0
			RcCloseGame()
			RcSet("gone", "RECONNECT didn't work 6 times - restarting the game")
			return true
			}
		;The game in view but not in front: click it in the background (unless it has ignored that
		;before). Otherwise bring it to the front to look and click: when it can't be seen (another
		;window over it), every 20 s in the first minute, after that every 2 minutes and only once
		;you've left the computer alone for a minute
		inFront := RcGameActive()
		btn := RcFindWord("i)^reconn?ect$", "box", "RECONNECT")
		if (IsObject(btn) && !inFront && RcClickBg != 0)
			{
			RcClick(btn.x, btn.y, "RECONNECT")
			RcTries += 1, RcPlayTries := 0
			RcSet("wait", "try " RcTries ": clicked RECONNECT - waiting to log back in")
			return true
			}
		if (IsObject(btn) || inFront || (early ? nowMs - RcPeekAt > 20000 : nowMs - RcPeekAt > 120000 && UserIdle() > 60000))
			{
			RcPeekAt := nowMs
			if (RcFrontClick("i)^reconn?ect$", "box", "RECONNECT", "RECONNECT"))
				{
				RcTries += 1, RcPlayTries := 0
				RcSet("wait", "try " RcTries ": clicked RECONNECT - waiting to log back in")
				return true
				}
			}
		if (!RcNote)
			RcNote := 1, RcLogMsg("can't see the RECONNECT button yet - still looking (" RcFindInfo ")")
		if (!early && RcNote = 1)
			RcNote := 2, RcLogMsg("still can't see the RECONNECT button (" RcFindInfo ") - carrying on meanwhile, looking again every 30 s")
		return early
		}
	if (RcState = "wait")
		{
		;Nothing a while after a background click and RECONNECT still showing: the game ignores
		;those, so bring it to the front and click (and from now on always that way)
		if (RcLastBg && nowMs - RcClickAt > 6000)
			{
			RcLastBg := 0
			if (IsObject(RcFindWord("i)^reconn?ect$", "box", "RECONNECT")))
				{
				RcClickBg := 0
				RcLogMsg("the game ignored the background click - bringing it to the front to click")
				RcFrontClick("i)^reconn?ect$", "box", "RECONNECT", "RECONNECT")
				}
			}
		if (nowMs - RcStateAt > 60000)
			RcFail("no login a minute after clicking RECONNECT")
		return true
		}
	if (RcState = "select")
		{
		;Character select: if the game doesn't carry on by itself after a RECONNECT, click Play - with
		;the game in front (that screen ignores background clicks, even though the RECONNECT box
		;takes them; seen 2026-10-16)
		if (RcCharAt && nowMs - RcCharAt > 6000 && nowMs - RcClickAt > 8000 && RcPlayTries < 3)
			{
			RcPlayTries += 1
			RcFrontClick("i)^play!?$", "low", "Play on the character select screen", "PLAY")
			}
		if (nowMs - RcStateAt > 90000)
			RcFail("still not in the game 90 s after logging in")
		return true
		}
	if (RcState = "enter")
		{
		if (nowMs - RcStateAt > 60000)
			RcFail("the character didn't get into the world within a minute")
		return true
		}
	if (RcState = "gone")
		return RcGone()
	if (RcState = "start")
		return RcStartStep()
	if (RcState = "login")
		return RcLoginStep()
	if (RcState = "outdated")
		return RcOutdated()
	if (RcState = "patch")
		return RcPatchStep()
	return false
	}

;Reads what the game has written to its log since last time, a whole line at a time
RcReadLog()
	{
	global RcPos, RcHead ; (v1 globals it sets)
	;(v1's FileOpen gave no object when it couldn't open the file; v2 throws)
	logFile := V1Try(FileOpen, RcLog, "r", "CP0")
	if (!IsObject(logFile))
		return
	logSize := logFile.Length
	;Which log this is: the game starts a new one each time it starts, and its first line (a time
	;stamp) changes - read a new one from the top, even if it's already longer than the old one was
	logHead := logFile.Read(17)
	if (logHead != RcHead)
		{
		if (RcHead != "")
			RcPos := 0
		RcHead := logHead
		}
	if (logSize < RcPos)
		RcPos := 0
	if (logSize - RcPos > 1048576)
		RcPos := logSize - 1048576
	if (logSize <= RcPos)
		{
		logFile.Close()
		return
		}
	logFile.Pos := RcPos
	chunk := logFile.Read(logSize - RcPos)
	logFile.Close()
	;A line still being written is read next time
	lastNl := InStr(chunk, "`n", false, -1)
	if (!lastNl)
		return
	chunk := SubStr(chunk, 1, lastNl)
	RcPos += StrLen(chunk)
	Loop Parse, chunk, "`n", "`r"
		RcLogLine(A_LoopField)
	}

;What one line of the game's log means for getting back online
RcLogLine(logLine)
	{
	global RcLastLineAt, RcLoadAt, RcMsg, RcLoginBad, RcTries, RcNext, RcClickBg, RcCharAt, RcTyped ; (v1 globals it sets)
	global RcBackAt, RcCharSelAt ; (v2-only: the port tools don't know them)
	;(a zone change under way, and the log's last sign of life - RcHungCheck. Its memory notes come every 5 minutes
	;whatever the game's doing: they don't count)
	;(not the empty field after the chunk's last line break - RcReadLog's Loop Parse)
	if (logLine != "" && !InStr(logLine, "PROCESS MEMORY USAGE"))
		RcLastLineAt := A_TickCount
	if (InStr(logLine, "MSG_ServerTransfer") || InStr(logLine, "Transition windows has appeared"))
		RcLoadAt := RcLoadAt ? RcLoadAt : A_TickCount
	;(the zone loaded - "GameClient::LoadZone() - Finished loading zone '...'", then "OnZoneLoaded": never written in the
	;hang; or the character select screen or the login: no zone change under way - you may sit there a while)
	else if (InStr(logLine, "Finished loading zone") || InStr(logLine, "OnZoneLoaded")
		|| InStr(logLine, "WizardCharacterSelect") || InStr(logLine, "LOGIN RESPONSE"))
		RcLoadAt := 0
	;(auto-reconnect off: only a relog's two lines - ReconnectCheck)
	if (!RcOn && !InStr(logLine, "MSG_CharacterSelected: Error=0") && !InStr(logLine, "ConnectComplete destination Zone="))
		return
	if (InStr(logLine, "DisplayMessageBox("))
		{
		;(the msg string key can be empty - e.g. a Crown Shop error, keyed by its title: GUI_CrownShopError)
		RegExMatch(logLine, "msg = (.*?), title = (.*?), msg string key = (\w*)(?:, title string key = (\w*))?", &box)
		;(v1: no match - box1.. blank)
		boxMsg := V1At(box, 1), boxKey := (V1At(box, 3) != "") ? box[3] : V1At(box, 4)
		if (boxMsg = "")
			boxMsg := logLine
		if (RegExMatch(boxKey, "i)OutOfDate") || RegExMatch(boxMsg, "i)out of date"))
			{
			RcMsg := boxMsg
			RcSet("outdated", "the game says `"" boxMsg "`" - it needs patching")
			return
			}
		;Kicked because the account logged in somewhere else, or by an admin: don't fight that
		if (RegExMatch(boxKey, "i)ForceDisconnect|CSRDisconnect|Ban|Suspend")
			|| RegExMatch(boxMsg, "i)someone else has logged in|logged in (from|on|at) another|by an Administrator|suspended|banned"))
			{
			RcMsg := boxMsg
			RcSet("stopped", "not reconnecting: `"" boxMsg "`" (" boxKey ")")
			if (!RcScanning)
				TrayTip("Not reconnecting: " boxMsg, "Wizard101 bot", 2)
			return
			}
		;While typing the login in: whatever the game says is about that
		if (RcState = "login")
			{
			if (RegExMatch(boxMsg, "i)invalid|password|username|account"))
				{
				RcLoginBad := 1
				RcSet("stopped", "the game turned the saved login down (`"" boxMsg "`") - it won't be typed again until it's saved again (tray menu: Set Wizard101 login...)")
				TrayTip("The game turned the saved login down. Save it again with `"Set Wizard101 login...`" in the tray menu.", "Wizard101 bot", 2)
				}
			else
				RcFail("logging in: the game says `"" boxMsg "`"")
			return
			}
		if (!RegExMatch(boxKey, "i)Connect|Disconnect|Shutdown|Maintenance|FailedTo|Attach|ZoneFull|NoZones|Unavailable|EnterWorld|Technical|LoginError")
			&& !RegExMatch(boxMsg, "i)disconnect|connection|connect to|maintenance|failed to (load|enter)|try again later|unable to (connect|reach|contact|log ?in|enter|join)"))
			{
			RcLogMsg("(a game message, not a disconnect: `"" boxMsg "`")")
			return
			}
		;A disconnect. Straight after one of our tries: that try failed, so wait longer this time
		retry := (RcState = "wait" || RcState = "select" || RcState = "enter")
		if (!retry && RcState != "box")
			RcTries := 0
		RcMsg := boxMsg
		RcNext := RegExMatch(boxKey "|" boxMsg, "i)Shutdown|maintenance|try again later") ? A_TickCount + 600000
			: retry ? A_TickCount + RcBackoff() : 0
		RcSet("box", "disconnected: `"" boxMsg "`" (" boxKey ")")
		if (!RcScanning && !retry)
			TrayTip("Disconnected: " boxMsg "`nReconnecting...", "Wizard101 bot", 2)
		return
		}
	if (InStr(logLine, "LOGIN RESPONSE: Error=0"))
		{
		;Only after our own tries (not when you log in yourself)
		if (RegExMatch(RcState, "^(box|wait|start|login|patch)$"))
			{
			if (RcLastBg && RcState = "wait")
				RcClickBg := 1
			RcLoginBad := 0, RcCharAt := 0
			RcSet("select", "logged back in")
			}
		return
		}
	if (InStr(logLine, "WizardCharacterSelect: The scene has been loaded successfully"))
		{
		RcCharAt := A_TickCount
		return
		}
	if (InStr(logLine, "MSG_CharacterSelected: Error=0"))
		{
		RcCharAt := 0
		;(a character picked - yours too: the world it goes into next is a relog's - not the start's replay of the log)
		if (!RcScanning)
			RcCharSelAt := A_TickCount
		if (RcOn && RcState = "select")
			RcSet("enter", "character chosen - going into the world")
		return
		}
	if (InStr(logLine, "ConnectComplete destination Zone="))
		{
		;(back in the world after a relog - the bot's reconnect, or a character picked in the last 2 minutes: when, for the walker's sigil
		;that won't start - RcBackAgo. 2026-10-26 21:44: one never started after a relog)
		if (!RcScanning && ((RcOn && RcState != "") || (RcCharSelAt && A_TickCount - RcCharSelAt < 120000)))
			{
			RcBackAt := A_TickCount
			if (!RcOn || RcState = "")
				{
				RegExMatch(logLine, "Zone=(\S+)", &rcZone)
				RcLogMsg("in the world after a character select (" V1At(rcZone, 1) ") - a relog")
				}
			}
		RcCharSelAt := 0
		if (RcOn && RcState != "")
			{
			RegExMatch(logLine, "Zone=(\S+)", &zone)
			RcSet("", "back in the game (" V1At(zone, 1) ")")
			RcTries := 0, RcNext := 0, RcTyped := 0
			if (!RcScanning)
				TrayTip("Back in the game.", "Wizard101 bot", 1)
			}
		return
		}
	}

;How long ago the game was last back in the world after a relog (ms - the bot's reconnect, or a character picked: yours too); "" none
;since the bot started. The walker's sigil that won't start (Walker.ahk WalkSigilCheck) counts fewer X presses within 30 minutes of one
RcBackAgo()
	{
	return RcBackAt ? A_TickCount - RcBackAt : ""
	}

;A loading screen that never finishes (2026-10-23 18:30: a defeat's trip back to Celestia's hub connected, then the game
;wrote nothing but its memory notes for 69 minutes and showed its loading picture): a zone change the log says began
;hungload minutes ago (5; 0 never - Settings), the log silent for 3 minutes since, the game still running, and neither the
;spellbook nor a battle round seen since it began (AutoFarmer: BotWorldSeenSince - that's the load done, however the log
;put it). Asks - yes in 60 s if nobody answers - then closes the game and starts it again (RcGone, not asking again)
RcHungCheck()
	{
	global RcLoadAt, ErrorLevel, RcHungCount, RcHungFirstAt, RcTries, RcNext, RcHungAsked ; (v1 globals it sets)
	if (!RcLoadAt || !RcPid || RcScanning)
		return
	;(only with the game in front - covered by another window, the spellbook can't be seen on screen even when it's up)
	if (!RcGameActive())
		return
	hungMin := V1IsFunc("Stat") ? Stat.Call("hungload") : ""
	;(v1: a setting that isn't a number + 0 is blank, and a blank <= 0 as text: TRUE - never)
	hungMin := (hungMin = "") ? 5 : V1Add(hungMin, 0)
	if (V1Le(hungMin, 0))
		return
	;(in the world again - the spellbook, a battle round - since the zone change began: done)
	if (V1IsFunc("BotWorldSeenSince") && BotWorldSeenSince.Call(RcLoadAt))
		{
		RcLoadAt := 0
		return
		}
	if (A_TickCount - RcLoadAt < hungMin * 60000 || A_TickCount - RcLastLineAt < 180000)
		return
	;(a last look at the screen itself - the spellbook, a round's Pass: BotWorldSeenSince with look)
	if (V1IsFunc("BotWorldSeenSince") && BotWorldSeenSince.Call(RcLoadAt, true))
		{
		RcLoadAt := 0
		return
		}
	hungFor := Round((A_TickCount - RcLoadAt) / 60000), quietFor := Round((A_TickCount - RcLastLineAt) / 60000)
	RcLogMsg("the game has been on a loading screen " hungFor " minutes (nothing in its log for " quietFor ") - it's hung")
	;(not closed when it can't be started and logged in again: left to you, said once)
	if (RcLoginBad || RcNoRelaunch || !RcHaveLogin())
		{
		RcLoadAt := 0
		RcLogMsg("no saved login to start it again with (tray menu: Set Wizard101 login...) - the hung game left to you")
		if (V1IsFunc("AlertSend"))
			AlertSend.Call("hung", "Wizard101 hung on a loading screen", "Stuck " hungFor " minutes with nothing in the game's log - and no saved login to start it again with: close and start Wizard101 yourself.")
		return
		}
	;(two restarts for a hang within an hour: it's not going away - left to you)
	if (RcHungCount >= 2 && A_TickCount - RcHungFirstAt < 3600000)
		{
		RcLoadAt := 0
		RcSet("stopped", "the game hung on a loading screen again after " RcHungCount " restarts within an hour - left to you")
		return
		}
	if (V1IsFunc("ReleaseKeys"))
		ReleaseKeys.Call()
	if (V1IsFunc("AlertSend"))
		AlertSend.Call("hung", "Wizard101 hung on a loading screen", "Stuck " hungFor " minutes with nothing in the game's log - closing it and starting it again (Settings: hungload).")
	rcHungPid := RcPid
	msgResult := MsgBox("Wizard101 has been stuck on a loading screen for " hungFor " minutes.`n`nClose it and start it again, logging back in?`n(It will in 60 seconds if nobody answers.)", "Wizard101 bot", "4145 T60")
	if (msgResult = "Cancel")
		{
		RcLoadAt := 0
		RcLogMsg("the hung game left to you (you chose not to restart it)")
		return
		}
	;(things may have moved on while the question was up - the bot or auto-reconnect switched off, the load finished, a
	;disconnect, the game closed or started afresh: the log read now, and the screen looked at again)
	if (!RcOn || (V1IsFunc("BotIsOn") && !BotIsOn.Call()))
		{
		RcLoadAt := 0
		return
		}
	RcReadLog()
	if (!RcLoadAt || RcState != "" || (V1IsFunc("BotWorldSeenSince") && BotWorldSeenSince.Call(RcLoadAt, true)))
		{
		RcLoadAt := 0
		return
		}
	ErrorLevel := ProcessExist(GameExe)
	if (!ErrorLevel || ErrorLevel != rcHungPid)
		return
	RcCloseGame()
	RcHungCount := (RcHungFirstAt && A_TickCount - RcHungFirstAt < 3600000) ? RcHungCount + 1 : 1
	RcHungFirstAt := RcHungCount = 1 ? A_TickCount : RcHungFirstAt
	RcLoadAt := 0, RcTries := 0, RcNext := 0, RcHungAsked := 1
	RcSet("gone", "closed the hung game - starting it again")
	}

;A try didn't work: back to looking for RECONNECT, after a longer wait each time
RcFail(why)
	{
	global RcTries, RcNext ; (v1 globals it sets)
	RcLogMsg(why)
	;On the login box or the character select screen there's no RECONNECT: start the game afresh
	if (RegExMatch(RcState, "^(start|login|select|enter)$"))
		{
		if (!RcLoginBad && RcHaveLogin())
			{
			RcTries := RcTyped ? RcTries + 1 : 1
			RcCloseGame()
			RcNext := A_TickCount + RcBackoff()
			RcSet("gone", "closing the game to start it again")
			return
			}
		RcSet("stopped", "can't get back into the game by itself - please log in yourself")
		if (!RcScanning)
			TrayTip("Couldn't get back into the game by itself - please log in yourself.", "Wizard101 bot", 2)
		return
		}
	RcNext := A_TickCount + RcBackoff()
	RcSet("box", "")
	}

;How long to wait before the next try: 30 s, 1, 2, 4 minutes, then 10 minutes
RcBackoff()
	{
	return RcTries <= 1 ? 30000 : RcTries = 2 ? 60000 : RcTries = 3 ? 120000 : RcTries = 4 ? 240000 : 600000
	}

;The game has closed: start it again (asking first, yes if nobody answers in 60 s) and log in
RcGone()
	{
	global RcNote, RcNoRelaunch, ErrorLevel, RcHungAsked ; (v1 globals it sets)
	if (RcNoRelaunch || RcLoginBad)
		return false
	if (A_TickCount < RcNext)
		return true
	if (!RcHaveLogin())
		{
		if (!RcNote)
			{
			RcNote := 1
			RcLogMsg("the game has closed and there's no saved login (tray menu: Set Wizard101 login...), so it can't start it again by itself")
			TrayTip("Wizard101 has closed. Save your login with `"Set Wizard101 login...`" in the tray menu and the bot can start it again by itself.", "Wizard101 bot", 2)
			if (V1IsFunc("AlertSend"))
				AlertSend.Call("reconnect", "Wizard101 has closed", "There's no saved login to start it again with (tray menu: Set Wizard101 login...).")
			}
		return false
		}
	if (RcTries >= 4)
		{
		RcSet("stopped", "couldn't get the game started and logged in after 4 tries - start it yourself")
		TrayTip("Couldn't restart Wizard101 by itself - please start it yourself.", "Wizard101 bot", 2)
		return false
		}
	if (V1IsFunc("ReleaseKeys"))
		ReleaseKeys.Call()
	;(a hung game the bot closed itself has been asked about already - RcHungCheck)
	if (!RcHungAsked)
		{
		msgResult := MsgBox("Wizard101 has closed.`n`nStart it again and log back in?`n(It will in 60 seconds if nobody answers.)", "Wizard101 bot", "4145 T60")
		if (msgResult = "Cancel")
			{
			RcNoRelaunch := 1
			RcLogMsg("the game has closed - you chose not to start it again")
			return false
			}
		}
	;Things may have changed while the question was up: the game started some other way, or
	;auto-reconnect switched off in the tray menu. (The hung game still going away: looked at again next time, not
	;asked about again)
	ErrorLevel := ProcessExist(GameExe)
	if (ErrorLevel && RcHungAsked)
		return true
	if (ErrorLevel || !RcOn || RcState != "gone")
		return false
	RcHungAsked := 0
	return RcLaunchClient()
	}

;Starts the game itself (not the launcher), which then shows its own login box
RcLaunchClient()
	{
	global RcNext, RcPid, RcTyped ; (v1 globals it sets)
	SplitPath(RcExe, , &binDir)
	loginHost := "login.us.wizard101.com", loginPort := 12000
	patchCfg := V1FileRead(binDir "\PatchConfig.xml")
	;(v1's match variable cfg: renamed - v2's Cfg is the Settings window's Gui object, a global)
	if (RegExMatch(patchCfg, "CommandLine args=`"-L\s+(\S+)\s+(\d+)", &pcfgM))
		loginHost := pcfgM[1], loginPort := pcfgM[2]
	V1Run("`"" RcExe "`" -L " loginHost " " loginPort, binDir, "", &newPid)
	if (ErrorLevel)
		{
		RcNext := A_TickCount + 600000
		RcLogMsg("couldn't start " RcExe " - trying again in 10 minutes")
		return true
		}
	RcPid := newPid, RcTyped := 0
	RcSet("start", "started the game - waiting for its login box")
	return true
	}

;Waiting for the game's login box (Account / Password), then types the saved login into it
RcStartStep()
	{
	global RcNext, RcTries, RcLookAt, RcTyped ; (v1 globals it sets)
	nowMs := A_TickCount
	if (nowMs - RcStateAt > 180000)
		{
		RcCloseGame()
		RcNext := nowMs + RcBackoff(), RcTries += 1
		RcSet("gone", "no login box 3 minutes after starting the game - closing it and trying again later")
		return true
		}
	if (nowMs - RcStateAt < 5000 || nowMs - RcLookAt < 1500)
		return true
	RcLookAt := nowMs
	;(v1: no game window - blank)
	gameWin := V1Try(WinGetID, "ahk_class " GameClass " ahk_exe " GameExe)
	if (!gameWin)
		return true
	if (V1IsFunc("UpdateGameRect"))
		UpdateGameRect.Call()
	;(its PASSWORD label - read badly at 1440p, "PASSWQD:": a word near it counts; the Account field worked out from it)
	rcPw := RcFindWord("i)^password:?$", "all", "PASSWORD")
	if (!IsObject(rcPw))
		return true
	rcField := RcAccountField(rcPw)
	if (!RcCredLoad(&loginUser, &loginPass))
		{
		RcSet("stopped", "the saved login is gone - save it again (tray menu: Set Wizard101 login...)")
		return false
		}
	;(read back from the Account field alone, closer up, allowing an OCR slip or two in a longer username - RcLineTol:
	;2026-10-23 19:39 it was typed, but the whole game read at once didn't find it, and the login was left to you)
	rcTol := RcLineTol(loginUser)
	;A fresh start has an empty login box: if the username is already there, don't guess where the
	;typing would go
	if (RcLineDist(loginUser, gameWin, &rcDistX, rcField) <= rcTol)
		{
		loginUser := "", loginPass := ""
		return RcLoginHelp("the login box already has the username in it")
		}
	;Typed straight to the game window as characters, checking each step. 0. Into the Account field: a click there, and a
	;test (zq7) typed and read back before anything of the login is - nothing of the login typed where it can't be seen
	RcLoginFocus(rcField)
	Sleep(300)
	RcChars(gameWin, "", 40)
	RcChars(gameWin, "zq7")
	Sleep(400)
	rcDist := RcLineDist("zq7", gameWin, &rcDistX, rcField)
	RcChars(gameWin, "", 10)
	if (rcDist > 1)
		{
		loginUser := "", loginPass := ""
		return RcLoginHelp("a test (zq7) typed into the login box's Account field wasn't read back there (" (rcDist = 99 ? "nothing like it read" : rcDist " letters off") ", the field at " rcField.x - GameLeft "," rcField.y - GameTop " " rcField.w "x" rcField.h ")")
		}
	;1. The username into the Account box (cleared first), then read it back
	RcChars(gameWin, "", 40)
	RcChars(gameWin, loginUser)
	Sleep(400)
	rcDist := RcLineDist(loginUser, gameWin, &rcDistX, rcField)
	if (rcDist > rcTol)
		{
		RcChars(gameWin, "", 40)
		loginUser := "", loginPass := ""
		return RcLoginHelp("couldn't see the username in the login box after typing it (" (rcDist = 99 ? "no line like it read" : "the nearest line read was " rcDist " letters off") ")")
		}
	;2. Tab to the Password box: test letters (xqz) typed now mustn't show up in the Account box - the line read is
	;nearer the username than the username with them after it, by 2 letters or more (an OCR slip can't make up for 3)
	RcChars(gameWin, Chr(9))
	RcChars(gameWin, "xqz")
	Sleep(400)
	rcDist := RcLineDist(loginUser, gameWin, &rcDistX, rcField)
	if (rcDist > rcTol || rcDistX < rcDist + 2)
		{
		RcChars(gameWin, "", 40)
		loginUser := "", loginPass := ""
		return RcLoginHelp("Tab didn't move on to the Password box")
		}
	;3. The password (the test letter cleared first), and the Account box still just the username
	RcChars(gameWin, "", 40)
	RcChars(gameWin, loginPass)
	loginPass := ""
	Sleep(300)
	if (RcLineDist(loginUser, gameWin, &rcDistX, rcField) > rcTol)
		{
		RcChars(gameWin, "", 40)
		loginUser := ""
		return RcLoginHelp("the login box didn't look right after typing the password")
		}
	loginUser := ""
	RcChars(gameWin, Chr(13))
	RcTyped := 1
	RcSet("login", "typed the saved login into the game's login box")
	return true
	}

;Typing the login in didn't work out: stop and leave it to you
RcLoginHelp(why)
	{
	RcSet("stopped", why " - didn't press Enter, log in yourself")
	TrayTip("Couldn't fill in the game's login box - please log in yourself.", "Wizard101 bot", 2)
	return false
	}

;How near a line of text on the game comes to reading text (the username in the login box): the fewest letter changes
;between them - both lower case, spaces left out, an "Account:" in front taken off or not, whichever is nearer; 99
;nothing like it read. withX: the same for text with xqz after it (the test letters of RcStartStep's Tab step). Nothing
;read is kept or logged
RcLineDist(text, gameWin, &withX := "", field := "")
	{
	rcWant := RegExReplace(Format("{:L}", text), "\s"), rcBest := 99, withX := 99
	;(field: only that box - the login box's Account field, RcAccountField - read closer up: its text is small)
	for each, zoom in (IsObject(field) ? [3, 4] : [1, 2])
		{
		if (IsObject(field))
			OcrRect(field.x, field.y, field.w, field.h, "en", zoom, &ocrLines)
		else
			OcrRect(GameLeft, GameTop, GameW, GameH, "en", zoom, &ocrLines)
		if (ErrorLevel || !IsObject(ocrLines))
			continue
		for i, ocrLine in ocrLines
			{
			if (!RcOnGame(ocrLine.x + ocrLine.w // 2, ocrLine.y + ocrLine.h // 2, gameWin))
				continue
			rcRaw := RegExReplace(Format("{:L}", Trim(ocrLine.text)), "\s")
			for each2, rcSeen in [rcRaw, RegExReplace(rcRaw, "^account:?")]
				{
				if (rcSeen = "" || Abs(StrLen(rcSeen) - StrLen(rcWant)) > 4)
					continue
				rcD := RcEditDistance(rcSeen, rcWant), rcDX := RcEditDistance(rcSeen, rcWant "xqz")
				rcBest := rcD < rcBest ? rcD : rcBest, withX := rcDX < withX ? rcDX : withX
				}
			}
		ocrLines := ""
		if (rcBest = 0 && withX > 0)
			break
		}
	rcWant := "", rcSeen := "", rcRaw := ""
	return rcBest
	}

;The login box's Account field, from its PASSWORD label (word, RcFindWord: its left, top, height) - the box is small and
;its labels read badly ("PASSWQD:", "Accmna:" at 1440p, 2026-10-23): the field is the black box over that label,
;from 1.6 to 0.1 of the label's height above it, 14 heights wide. {x, y, w, h, cx, cy} (screen)
RcAccountField(word)
	{
	rcH := word.h
	rcX := word.left - Round(rcH * 0.2), rcY := word.top - Round(rcH * 1.6), rcW := Round(rcH * 14.2), rcFH := Round(rcH * 1.5)
	return V1Obj({x: rcX, y: rcY, w: rcW, h: rcFH, cx: rcX + rcW // 2, cy: rcY + rcFH // 2})
	}

;A click into the login box's Account field (field: RcAccountField), so what's typed goes there: with the real mouse
;when the game's in front (your mouse held off meanwhile, put back after), else in the background (RcClick)
RcLoginFocus(field)
	{
	if (!RcGameActive())
		return RcClick(field.cx, field.cy, "the login box's Account field")
	MouseGetPos(&rcMx, &rcMy)
	;(your mouse locked meanwhile - Settings.ahk MouseLockOn)
	MouseLockOn("login")
	MouseMove(field.cx, field.cy, 0)
	;(its clicks too, now the pointer's on the game - Settings.ahk MouseLockMoved)
	MouseLockMoved()
	Sleep(120)
	Click()
	Sleep(120)
	MouseMove(rcMx, rcMy, 0)
	MouseLockOff("login")
	RcLogMsg("clicked into the login box's Account field at " field.cx - GameLeft "," field.cy - GameTop)
	return true
	}

;The OCR slips let through reading the username back: none in a short one, 1 from 6 letters, 2 from 14
RcLineTol(text)
	{
	rcN := StrLen(RegExReplace(text, "\s"))
	return rcN >= 14 ? 2 : rcN >= 6 ? 1 : 0
	}
;Logging in: the log's LOGIN RESPONSE moves on to "select"; "Invalid..." stops for good
RcLoginStep()
	{
	global RcLookAt, RcLoginBad, RcTries, RcNext ; (v1 globals it sets)
	nowMs := A_TickCount
	if (nowMs - RcStateAt > 4000 && nowMs - RcLookAt > 2000)
		{
		RcLookAt := nowMs
		if (IsObject(RcFindWord("i)^invalid$", "all")))
			{
			RcLoginBad := 1
			RcSet("stopped", "the game says the saved login is invalid - it won't be typed again until it's saved again")
			TrayTip("The game turned the saved login down. Save it again with `"Set Wizard101 login...`" in the tray menu.", "Wizard101 bot", 2)
			return false
			}
		}
	if (nowMs - RcStateAt > 60000)
		{
		RcTries += 1
		RcCloseGame()
		RcNext := nowMs + RcBackoff()
		RcSet("gone", "no answer from the login server within a minute - closing the game and trying again later")
		}
	return true
	}

;"Client is out of date": close the game and let the launcher patch it (it needs the login too)
RcOutdated()
	{
	global RcTyped ; (v1 globals it sets)
	if (RcLoginBad || !RcHaveLogin())
		{
		RcSet("stopped", "the game needs patching and there's no usable saved login - start Wizard101 yourself")
		TrayTip("Wizard101 needs patching - start it yourself (or save your login in the tray menu).", "Wizard101 bot", 2)
		return false
		}
	RcCloseGame()
	SplitPath(RcExe, , &binDir)
	SplitPath(binDir, , &gameRoot)
	V1Run("`"" gameRoot "\Wizard101.exe`"", gameRoot)
	if (ErrorLevel)
		{
		RcSet("stopped", "couldn't start the launcher (" gameRoot "\Wizard101.exe) - start Wizard101 yourself")
		return false
		}
	RcTyped := 0
	RcSet("patch", "started the launcher to patch the game")
	return true
	}

;The launcher: fill in the login, press PLAY!, then wait while it patches and starts the game (the
;process check notices the new game, and the log takes it from there)
RcPatchStep()
	{
	global RcLookAt, RcTyped, RcStateAt ; (v1 globals it sets)
	nowMs := A_TickCount
	if (RcTyped)
		{
		if (RcPid)
			RcSet("select", "the launcher started the game")
		else if (nowMs - RcStateAt > 1200000)
			RcSet("stopped", "the launcher hasn't started the game after 20 minutes - check it yourself")
		return true
		}
	if (nowMs - RcLookAt < 2000)
		return true
	RcLookAt := nowMs
	;(v1: no launcher window - blank)
	launchWin := V1Try(WinGetID, "ahk_exe WizardLauncher.exe")
	if (!launchWin)
		{
		if (nowMs - RcStateAt > 180000)
			RcSet("stopped", "the launcher didn't open - start Wizard101 yourself")
		return true
		}
	userBox := "", passBox := "", playBtn := "", seen := ""
	;(v1's WinGet ControlList: the names a line each - blank when the window's gone; ControlGet / ControlGetText on a control
	;that's gone: blank)
	ctlList := "", ctlNames := V1Try(WinGetControls, "ahk_id " launchWin)
	if (IsObject(ctlNames))
		for ctlName in ctlNames
			ctlList .= (A_Index = 1 ? "" : "`n") ctlName
	Loop Parse, ctlList, "`n"
		{
		ctlVis := V1Try(ControlGetVisible, A_LoopField, "ahk_id " launchWin)
		ctlStyle := V1Try(ControlGetStyle, A_LoopField, "ahk_id " launchWin)
		if (!ctlVis)
			continue
		if (InStr(A_LoopField, "Edit") = 1)
			{
			if (V1IsNum(ctlStyle) && (ctlStyle & 0x20))
				passBox := A_LoopField
			else if (userBox = "")
				userBox := A_LoopField
			continue
			}
		ctlText := V1Try(ControlGetText, A_LoopField, "ahk_id " launchWin)
		if (RegExMatch(ctlText, "i)^\s*(play!?|log\s*in)\s*$"))
			playBtn := A_LoopField
		seen .= A_LoopField " "
		}
	if (passBox = "")
		{
		;Its login boxes show once the page has loaded
		if (nowMs - RcStateAt > 120000)
			{
			RcLogMsg("launcher controls seen: " seen)
			RcSet("stopped", "the launcher is open but its password box wasn't found - log in there yourself")
			TrayTip("The launcher needs you: log in there yourself.", "Wizard101 bot", 2)
			}
		return true
		}
	if (!RcCredLoad(&loginUser, &loginPass))
		{
		RcSet("stopped", "the saved login is gone - log in to the launcher yourself")
		return false
		}
	if (userBox != "")
		{
		curUser := V1Try(ControlGetText, userBox, "ahk_id " launchWin)
		if (curUser != loginUser)
			V1Do(ControlSetText, loginUser, userBox, "ahk_id " launchWin)
		}
	;(v1: ErrorLevel 1 when the launcher's control has gone - v2 throws)
	V1Do(ControlSetText, loginPass, passBox, "ahk_id " launchWin)
	loginUser := "", loginPass := ""
	Sleep(300)
	if (playBtn != "")
		V1Do(ControlClick, playBtn, "ahk_id " launchWin, , , , "NA")
	else
		V1Do(ControlSend, "{Enter}", passBox, "ahk_id " launchWin)
	RcTyped := 1, RcStateAt := A_TickCount
	RcLogMsg("launcher: filled in the login and pressed " (playBtn = "" ? "Enter" : playBtn) " - it patches, then starts the game")
	return true
	}

;Closes the game (and makes sure it's gone)
RcCloseGame()
	{
	global ErrorLevel, RcPid ; (v1 globals it sets)
	;(v1: no window - nothing; v2 throws)
	try WinClose("ahk_class " GameClass " ahk_exe " GameExe)
	ErrorLevel := ProcessWaitClose(GameExe, 15)
	if (ErrorLevel)
		{
		ErrorLevel := ProcessClose(GameExe)
		;(a hung game takes a moment to go even when forced)
		ErrorLevel := ProcessWaitClose(GameExe, 10)
		}
	RcPid := 0
	}

;Clicks at a screen point in the game, leaving it in the background: mouse messages straight to its
;window (some games ignore those - then RcFrontClick)
RcClick(px, py, what)
	{
	global RcClickAt, RcLastBg ; (v1 globals it sets)
	;(v1: no game window - blank)
	gameWin := V1Try(WinGetID, "ahk_class " GameClass " ahk_exe " GameExe)
	if (!gameWin)
		return false
	RcClickAt := A_TickCount
	cx := px - GameLeft, cy := py - GameTop
	pos := (cy << 16) | (cx & 0xFFFF)
	;(v1: ErrorLevel 1 when the window has gone meanwhile - v2 throws)
	V1Do(PostMessage, 0x200, 0, pos, , "ahk_id " gameWin)
	Sleep(50)
	V1Do(PostMessage, 0x201, 1, pos, , "ahk_id " gameWin)
	Sleep(80)
	V1Do(PostMessage, 0x202, 0, pos, , "ahk_id " gameWin)
	RcLastBg := 1
	RcLogMsg("clicked " what " at " cx "," cy " (game left in the background)")
	return true
	}

;Brings the game to the front (if it isn't), finds the word there again and clicks it with the real
;mouse - your mouse movements held off meanwhile - then gives the focus and the mouse back. False if
;the game couldn't be brought up or the word isn't there
RcFrontClick(pattern, area, what, fuzzy := "")
	{
	global RcClickAt, RcLastBg, RcFrontOk, ErrorLevel ; (v1 globals it sets)
	;(v1: no window - blank; WinActivate of a window that's gone: nothing)
	gameWin := V1Try(WinGetID, "ahk_class " GameClass " ahk_exe " GameExe)
	if (!gameWin)
		return false
	RcClickAt := A_TickCount, RcLastBg := 0, RcFrontOk := 0
	prevWin := V1Try(WinGetID, "A")
	MouseGetPos(&mouseX, &mouseY)
	if (prevWin != gameWin)
		{
		try WinActivate("ahk_id " gameWin)
		ErrorLevel := !WinWaitActive("ahk_id " gameWin, , 2)
		;Windows sometimes won't hand over the focus (e.g. to Windows' own hidden input window): a
		;real click on the game's title bar always brings it up, and does nothing in the game
		if (ErrorLevel)
			{
			;(v1: the window gone meanwhile - its place blank, and the sums with it blank: not >= 12; v2's WinGetPos
			;unsets its output variables before it throws - the blanks are set in the catch)
			try WinGetPos(&winX, &winY, &winW, , "ahk_id " gameWin)
			catch
				winX := "", winY := "", winW := ""
			barX := V1Add(winX, V1FloorDiv(winW, 2)), barY := V1Add(winY, V1FloorDiv(V1Sub(GameTop, winY), 2))
			;(v1: RcOnGame's DllCalls set ErrorLevel to 0 - once the title bar's point was looked at, covered or not, the
			;check below let it on; only a click there whose wait failed, or no look at all, stopped it)
			onBar := false
			if (V1Ge(V1Sub(GameTop, winY), 12))
				onBar := RcOnGame(barX, barY, gameWin), ErrorLevel := 0
			if (onBar)
				{
				;(Settings.ahk MouseLockOn - it only locks with the game in front, so not for this click)
				MouseLockOn("login")
				MouseMove(barX, barY, 0)
				Click()
				MouseLockOff("login")
				ErrorLevel := !WinWaitActive("ahk_id " gameWin, , 2)
				}
			}
		if (ErrorLevel)
			{
			MouseMove(mouseX, mouseY, 0)
			RcLogMsg("couldn't bring the game to the front to click " what)
			return false
			}
		Sleep(700)
		if (V1IsFunc("UpdateGameRect"))
			UpdateGameRect.Call()
		}
	RcFrontOk := 1
	btn := RcFindWord(pattern, area, fuzzy)
	if (IsObject(btn))
		{
		;(your mouse locked meanwhile - Settings.ahk MouseLockOn)
		MouseLockOn("login")
		MouseMove(btn.x, btn.y, 0)
		;(its clicks too, now the pointer's on the game - Settings.ahk MouseLockMoved)
		MouseLockMoved()
		Sleep(150)
		;(Wizard101 gone to the tray meanwhile - AutoFarmer's Settings: traygame: not clicked, it would land on the window
		;behind - not said clicked, no try counted)
		if (GameInTray)
			btn := ""
		else
			Click()
		Sleep(150)
		MouseLockOff("login")
		}
	;(the focus back to your window - not when you've left the PC, nothing touched for 5 minutes: the game stays in front,
	;else the bot can't walk and the game logs out for inactivity again)
	if (prevWin && prevWin != gameWin && UserIdle() < 300000)
		{
		Sleep(200)
		MouseMove(mouseX, mouseY, 0)
		try WinActivate("ahk_id " prevWin)
		}
	if (IsObject(btn))
		RcLogMsg("clicked " what " at " btn.x - GameLeft "," btn.y - GameTop (prevWin != gameWin ? " (brought the game to the front for it)" : ""))
	return IsObject(btn)
	}

RcGameActive()
	{
	return WinActive("ahk_class " GameClass " ahk_exe " GameExe)
	}

;Is that screen point on the game window itself (not on another window over it)?
RcOnGame(px, py, gameWin)
	{
	hitWin := DllCall("WindowFromPoint", "Int64", (py << 32) | (px & 0xFFFFFFFF), "Ptr")
	return hitWin && DllCall("GetAncestor", "Ptr", hitWin, "UInt", 2, "Ptr") = gameWin
	}

;Screen {x, y, text} of the middle of the first word on screen matching pattern, read by OCR in an
;area of the game: "box" (the middle, where the disconnect box is), "low" (the bottom half) or "all".
;With fuzzy (e.g. "RECONNECT"), a word OCR got slightly wrong counts too - a letter or two off, 0 for
;O and the like, or split in two - but never QUIT
RcFindWord(pattern, area, fuzzy := "")
	{
	global RcFindInfo ; (v1 globals it sets)
	;(v1: UiScale not set - blank - isn't > 0)
	uiS := V1Gt(UiScale, 0) ? UiScale : 1
	midX := GameLeft + GameW // 2, midY := GameTop + GameH // 2
	if (area = "box")
		ax := midX - Round(450 * uiS), ay := midY - Round(220 * uiS), aw := Round(900 * uiS), ah := Round(440 * uiS)
	else if (area = "low")
		ax := GameLeft, ay := midY, aw := GameW, ah := GameH - GameH // 2
	else
		ax := GameLeft, ay := GameTop, aw := GameW, ah := GameH
	;Keep it inside the game
	if (ax < GameLeft)
		aw -= GameLeft - ax, ax := GameLeft
	if (ay < GameTop)
		ah -= GameTop - ay, ay := GameTop
	aw := (ax + aw > GameLeft + GameW) ? GameLeft + GameW - ax : aw
	ah := (ay + ah > GameTop + GameH) ? GameTop + GameH - ay : ah
	if (aw < 20 || ah < 20)
		return ""
	;Only words on the game itself: OCR reads the screen, and another window over the game could show
	;the same word
	;(v1: no window - blank)
	gameWin := V1Try(WinGetID, "ahk_class " GameClass " ahk_exe " GameExe)
	if (!gameWin)
		return ""
	;For the log if it isn't found: how many words it read, and what window is over the middle
	hitWin := DllCall("GetAncestor", "Ptr", DllCall("WindowFromPoint", "Int64", (midY << 32) | (midX & 0xFFFFFFFF), "Ptr"), "UInt", 2, "Ptr")
	hitExe := V1Try(WinGetProcessName, "ahk_id " hitWin)
	hitClass := V1Try(WinGetClass, "ahk_id " hitWin)
	wordCount := 0, wordsSeen := ""
	for each, zoom in [1, 2]
		{
		OcrRect(ax, ay, aw, ah, "en", zoom, &ocrLines)
		if (ErrorLevel || !IsObject(ocrLines))
			continue
		for i, ocrLine in ocrLines
			for j, ocrWord in ocrLine.words
				{
				wordCount += 1
				if (zoom = 1 && wordCount <= 30)
					wordsSeen .= (wordsSeen = "" ? "" : " ") ocrWord.text
				wx := ocrWord.x + ocrWord.w // 2, wy := ocrWord.y + ocrWord.h // 2
				found := RegExMatch(Trim(ocrWord.text), pattern) || RcLooksLike(ocrWord.text, fuzzy)
				;Split in two ("RECON NECT"): both halves together
				if (!found && fuzzy != "" && j < ocrLine.words.Length)
					{
					nextWord := ocrLine.words[j + 1]
					if (RcLooksLike(ocrWord.text nextWord.text, fuzzy))
						found := true, wx := (ocrWord.x + nextWord.x + nextWord.w) // 2
					}
				if (found && RcOnGame(wx, wy, gameWin))
					return V1Obj({x: wx, y: wy, text: ocrWord.text, left: ocrWord.x, top: ocrWord.y, w: ocrWord.w, h: ocrWord.h})
				}
		}
	RcFindInfo := wordCount " words read there (" SubStr(wordsSeen, 1, 200) "), over the middle: " (hitWin = gameWin ? "the game" : (hitClass = "" ? "an unknown window" : hitClass) (hitExe = "" ? "" : " (" hitExe ")"))
	return ""
	}

;Is an OCR'd word close enough to want (a word in capitals)? Letters only, digits OCR often swaps in
;for letters turned back, then at most 1 letter off (2 for words of 7 or more). Never QUIT
RcLooksLike(word, want)
	{
	if (want = "")
		return false
	word := StrUpper(word)
	word := RegExReplace(StrReplace(StrReplace(StrReplace(StrReplace(StrReplace(word, "0", "O"), "1", "I"), "5", "S"), "8", "B"), "|", "I"), "[^A-Z]")
	if (word = "" || word = "QUIT" || Abs(StrLen(word) - StrLen(want)) > 1)
		return false
	return RcEditDistance(word, want) <= (StrLen(want) >= 7 ? 2 : 1)
	}

;How many single-letter changes (add, drop or swap one) turn a into b
RcEditDistance(a, b)
	{
	lenB := StrLen(b), prevRow := []
	;(each item the next one: v2's Array grows by Push)
	Loop lenB + 1
		prevRow.Push(A_Index - 1)
	Loop Parse, a
		{
		row := [A_Index]
		charA := A_LoopField
		Loop lenB
			row.Push(Min(prevRow[A_Index + 1] + 1, row[A_Index] + 1, prevRow[A_Index] + (charA == SubStr(b, A_Index, 1) ? 0 : 1)))
		prevRow := row
		}
	return prevRow[lenB + 1]
	}

;Types text into a window as WM_CHAR messages (backspaces first: clears the box it goes into)
RcChars(win, text, backspaces := 0)
	{
	global ErrorLevel ; (v1 globals it sets)
	;(v1: ErrorLevel the reply, FAIL when the window has gone - v2 throws)
	Loop backspaces
		{
		try ErrorLevel := SendMessage(0x102, 8, 0, , "ahk_id " win)
		catch
			ErrorLevel := "FAIL"
		}
	Loop Parse, text
		{
		try ErrorLevel := SendMessage(0x102, Ord(A_LoopField), 0, , "ahk_id " win)
		catch
			ErrorLevel := "FAIL"
		Sleep(15)
		}
	}

;Where the game is: the running one's path, else the last known one, else the usual install folder
RcFindClient()
	{
	;(v1: no game window - blank)
	exePath := V1Try(WinGetProcessPath, "ahk_class " GameClass " ahk_exe " GameExe)
	if (exePath != "")
		return exePath
	if (RcExe != "")
		return RcExe
	progData := EnvGet("ProgramData")
	return (progData = "" ? "C:\ProgramData" : progData) "\KingsIsle Entertainment\Wizard101\Bin\" GameExe
	}

RcSetClient(exePath)
	{
	global RcExe, RcLog ; (v1 globals it sets)
	RcExe := exePath
	SplitPath(exePath, , &binDir)
	RcLog := binDir "\WizardClient.log"
	}

RcSet(newState, why := "")
	{
	global RcState, RcStateAt, RcNote, RcPeeks, RcPeekAt ; (v1 globals it sets)
	RcState := newState, RcStateAt := A_TickCount, RcNote := 0, RcPeeks := 0, RcPeekAt := 0
	if (why != "")
		RcLogMsg(why)
	;(stopped: it needs you - to Discord too, if alerts are set up: Alerts.ahk)
	if (newState = "stopped" && !RcScanning && V1IsFunc("AlertSend"))
		AlertSend.Call("reconnect", "can't get back into the game", why)
	if (newState = "")
		RcStatus("online")
	}

RcLogMsg(text)
	{
	if (!RcScanning && V1IsFunc("DebugLog"))
		DebugLog.Call("Reconnect: " text)
	}

RcStatus(text)
	{
	static lastText := ""
	if (RcScanning || text = lastText)
		return
	lastText := text
	A_IconTip := "Wizard101 bot " BotVersion() ": " SubStr(text, 1, 100)
	}

;Wizard101 back from the tray (AutoFarmer's GameTrayForget - its Settings: traygame): the bot was off meanwhile, so what
;Reconnect times - a disconnect box's first minute, its looks and peeks - starts afresh (none ran on while it was hidden)
RcAfterTray()
	{
	global RcStateAt, RcLookAt, RcPeekAt ; (v1 globals it sets)
	if (RcState != "" && RcState != "stopped")
		RcStateAt := A_TickCount
	RcLookAt := 0, RcPeekAt := 0
	}

;Tray menu: switches auto-reconnect on and off
ReconnectToggle()
	{
	global RcOn, RcState, RcTries, RcNext, RcNoRelaunch ; (v1 globals it sets)
	RcOn := !RcOn
	if (RcOn)
		{
		RcState := "", RcTries := 0, RcNext := 0, RcNoRelaunch := 0
		A_TrayMenu.Check("Auto-reconnect on/off")
		}
	else
		A_TrayMenu.Uncheck("Auto-reconnect on/off")
	RcLogMsg("auto-reconnect " (RcOn ? "on" : "off"))
	TrayTip("Auto-reconnect " (RcOn ? "on" : "off"), "Wizard101 bot", 1)
	}

;Tray menu: asks for the Wizard101 login and keeps it in Windows Credential Manager
ReconnectSetLogin()
	{
	global ErrorLevel, RcLoginBad ; (v1 globals it sets)
	if (V1IsFunc("ReleaseKeys"))
		ReleaseKeys.Call()
	;(v1: no such value - blank)
	rememberedUser := RegRead("HKCU\Software\KingsIsle\Wizard101", "UserName", "")
	IB := InputBox("Your Wizard101 username.`nUsed only to log back in if the game closes.", "Wizard101 login", "w380 h160", rememberedUser), loginUser := IB.Value, ErrorLevel := IB.Result="OK" ? 0 : IB.Result="CANCEL" ? 1 : IB.Result="Timeout" ? 2 : "ERROR"
	if (ErrorLevel || Trim(loginUser) = "")
		return
	IB := InputBox("Password for " Trim(loginUser) ".`nKept encrypted in Windows Credential Manager as `"" RcCredTarget "`".", "Wizard101 login", "Password w380 h160"), loginPass := IB.Value, ErrorLevel := IB.Result="OK" ? 0 : IB.Result="CANCEL" ? 1 : IB.Result="Timeout" ? 2 : "ERROR"
	if (ErrorLevel || loginPass = "")
		return
	saved := RcCredSave(Trim(loginUser), loginPass)
	loginPass := ""
	if (saved)
		{
		RcLoginBad := 0
		RcLogMsg("login saved (in Windows Credential Manager)")
		MsgBox("Saved. If Wizard101 closes, the bot can start it and log back in.`n`n(To remove it: Windows Credential Manager > Windows Credentials > " RcCredTarget ")", "Wizard101 bot", "64 T15")
		}
	else
		MsgBox("Couldn't save the login in Windows Credential Manager (error " A_LastError ").", "Wizard101 bot", 16)
	}

;Is there a saved login?
RcHaveLogin()
	{
	found := RcCredLoad(&loginUser, &loginPass)
	loginUser := "", loginPass := ""
	return found
	}

;Windows Credential Manager (CredWriteW / CredReadW): a "generic" credential named RcCredTarget.
;CREDENTIALW offsets differ between 32- and 64-bit AutoHotkey
RcCredSave(user, pass)
	{
	is64 := (A_PtrSize = 8)
	targetW := Buffer((StrLen(RcCredTarget) + 1) * 2, 0), StrPut(RcCredTarget, targetW.Ptr, "UTF-16")
	userW := Buffer((StrLen(user) + 1) * 2, 0), StrPut(user, userW.Ptr, "UTF-16")
	blobSize := StrLen(pass) * 2
	blob := Buffer(blobSize + 2, 0), StrPut(pass, blob.Ptr, "UTF-16")
	cred := Buffer(is64 ? 80 : 52, 0)
	NumPut("UInt", 1, cred, 4)                          ;Type: CRED_TYPE_GENERIC
	NumPut("Ptr", targetW.Ptr, cred, 8)                    ;TargetName
	NumPut("UInt", blobSize, cred, is64 ? 32 : 24)      ;CredentialBlobSize
	NumPut("Ptr", blob.Ptr, cred, is64 ? 40 : 28)          ;CredentialBlob
	NumPut("UInt", 2, cred, is64 ? 48 : 32)             ;Persist: CRED_PERSIST_LOCAL_MACHINE
	NumPut("Ptr", userW.Ptr, cred, is64 ? 72 : 48)         ;UserName
	saved := DllCall("Advapi32\CredWriteW", "Ptr", cred.Ptr, "UInt", 0)
	DllCall("RtlZeroMemory", "Ptr", blob.Ptr, "Ptr", blobSize + 2)
	return saved
	}

RcCredLoad(&user, &pass)
	{
	user := "", pass := "", credPtr := 0
	is64 := (A_PtrSize = 8)
	targetW := Buffer((StrLen(RcCredTarget) + 1) * 2, 0), StrPut(RcCredTarget, targetW.Ptr, "UTF-16")
	if (!DllCall("Advapi32\CredReadW", "Ptr", targetW.Ptr, "UInt", 1, "UInt", 0, "Ptr*", &credPtr) || !credPtr)
		return false
	blobSize := NumGet(credPtr + 0, is64 ? 32 : 24, "UInt")
	blobPtr := NumGet(credPtr + 0, is64 ? 40 : 28, "Ptr")
	userPtr := NumGet(credPtr + 0, is64 ? 72 : 48, "Ptr")
	if (blobPtr && blobSize)
		pass := StrGet(blobPtr, blobSize // 2, "UTF-16")
	if (userPtr)
		user := StrGet(userPtr, "UTF-16")
	if (blobPtr && blobSize)
		DllCall("RtlZeroMemory", "Ptr", blobPtr, "Ptr", blobSize)
	DllCall("Advapi32\CredFree", "Ptr", credPtr)
	return (user != "" && pass != "")
	}

;(v2 port, CONVENTIONS.md "Blank start": v1 started every variable blank; v2 leaves it unset and throws on
;reading it. The entry script calls this first thing: this file's globals start blank, as in v1)
ReconnectBlank()
	{
	global RcOn := "", RcLog := "", RcPos := "", RcPid := "", RcExe := "", RcState := "", RcStateAt := "", RcMsg := "", RcTries := "", RcNext := ""
	global RcLookAt := "", RcCheckAt := "", RcProcAt := "", RcClickBg := "", RcLastBg := "", RcClickAt := "", RcCharAt := "", RcPlayTries := ""
	global RcNoRelaunch := "", RcLoginBad := "", RcNote := "", RcScanning := "", RcTyped := "", RcCredTarget := "", RcHead := "", RcPeekAt := ""
	global RcPeeks := "", RcFrontOk := "", RcFindInfo := "", RcLoadAt := "", RcLastLineAt := "", RcHungAsked := "", RcHungCount := ""
	global RcHungFirstAt := "", RcBackAt := "", RcCharSelAt := ""
	}
