#Warn Unreachable, Off
#Requires AutoHotkey v2.0
V1Start(), AutofarmerBlank(), KillCalcBlank(), ReconnectBlank() ; (v2 port: v1 started every variable blank - CONVENTIONS.md "Blank start")
PicScaleBlank(), StatsReadBlank(), VisionBlank(), CardLearnBlank() ; (v2 port: v1 started every variable blank - CONVENTIONS.md "Blank start")
PotionsBlank(), FleeBlank(), DrawBlank(), EnemySpellsBlank(), PartyBlank() ; (v2 port: v1 started every variable blank - CONVENTIONS.md "Blank start")
SettingsBlank(), AlertsBlank(), DashboardBlank(), BugReportBlank() ; (v2 port: v1 started every variable blank - CONVENTIONS.md "Blank start")
DungeonsBlank(), CollectBlank(), NetworkBlank(), DecksBlank() ; (v2 port: v1 started every variable blank - CONVENTIONS.md "Blank start")
QuickSellBlank(), HotkeysBlank(), SpellsBlank(), WalkerBlank() ; (v2 port: v1 started every variable blank - CONVENTIONS.md "Blank start")
MouseSteerBlank(), PlannerBlank() ; (v2 port: v1 started every variable blank - CONVENTIONS.md "Blank start")
GearBlank() ; (v2-only: Gear.ahk's globals blank at start too - CONVENTIONS.md "Blank start")
TrainingBlank() ; (Training.ahk - v2-only globals, blank at start too)
UsedBlank() ; (v2 port: the battle flags made by name - used0..used52, bladetype, traptype - blank at start too)
OverlayBlank() ; (Overlay.ahk - v2-only globals, blank at start too)
InstallMouseHook()
InstallKeybdHook()
;(v1: Settings.ahk's #MaxHotkeysPerInterval 1000 - a directive, in force from the start; v2's default is 70 in 2 s.
;v1's other defaults - SendMode Event, SetTitleMatchMode 1, CoordMode Window: V1Start)
A_MaxHotkeysPerInterval := 1000
#SingleInstance force

;All the pictures are found relative to this folder, however the script was started (shortcut, editor, ...)
SetWorkingDir(A_ScriptDir)

;The wizard icon in the tray and on the dashboard (built into the exe; run as a script, set here)
if (!A_IsCompiled && FileExist(A_ScriptDir "\..\assets\wizard.ico"))
	TraySetIcon(A_ScriptDir . "\..\assets\wizard.ico")

;All ImageSearch/Mouse coordinates are absolute screen coordinates, offset from the game's client area (see UpdateGameRect)
CoordMode("Pixel", "Screen")
CoordMode("Mouse", "Screen")
CoordMode("ToolTip", "Screen")

;Battles (this script) and quest walking (..\AutoQuester\Walker.ahk) run together in one loop and
;start by themselves: fight when a battle round is up, otherwise follow the quest arrow.
;  F6           the bot on / off (off: no battles, walking, potions or reconnecting). Opened by the game -
;               "Open with Wizard101", /standby - it starts off and waits for F6
;  F8           walking on / off
;  Windows+1    restart (also Alt+Esc)
;  Windows+Esc  quit
;(the keys out of the box - yours to change on the dashboard's Keys tab: Hotkeys.ahk makes them, these labels run)
;Disconnected: it clicks the game's RECONNECT, and if the game closes it can start it and log back in
;(Reconnect.ahk). Tray menu: "Auto-reconnect on/off" and "Set Wizard101 login..." (the login it uses then)
OnExit(WalkerQuit)
;No standard tray menu: its "Pause Script" would freeze the walker with a key held down
Tray := A_TrayMenu
Tray.Delete() ; (v1: Menu, Tray, NoStandard - only the standard items are there yet)
;(the version, on top - not a command)
Tray.Add("Wiz-Maxxing " (BotVersion() = "" ? "(no version.txt)" : BotVersion()), MenuNothing)
Tray.Disable("Wiz-Maxxing " (BotVersion() = "" ? "(no version.txt)" : BotVersion()))
Tray.Add()
Tray.Add(HkMenu("bot"), MenuBotToggle)
Tray.Add(HkMenu("walk"), MenuWalk)
;(battles only - Settings: battlesonly: out of battle the bot moves nothing; ticked while it's on - BattlesOnlyShow)
Tray.Add("Battles only (moves nothing out of battle)", MenuBattlesOnly)
Tray.Add("Wait while I play", MenuHandsOff)
Tray.Add("Play for me (leave it alone for days)", MenuPlayForMe)
Tray.Add("Bring Wizard101 to the front", MenuGameFront)
Tray.Add("Auto-reconnect on/off", MenuReconnect)
Tray.Add("Set Wizard101 login...", MenuLogin)
Tray.Add("Discord alerts...", MenuAlerts)
Tray.Add("Party...", MenuParty)
Tray.Add(HkMenu("dash"), MenuDash)
Tray.Add("Learned spells", MenuSpells)
Tray.Add("Settings...", MenuSettings)
Tray.Add("Map of the zone", MenuMap)
Tray.Add(HkMenu("overlay"), MenuOverlay)
Tray.Add("Speedhack: press its walking key in 3 s (for Cheat Engine)", MenuSpeedKeyFast)
Tray.Add("Speedhack: press its 1x key in 3 s (for Cheat Engine)", MenuSpeedKeyNormal)
Tray.Add("Check for updates", MenuUpdates)
Tray.Add("Report a bug...", MenuBug)
Tray.Add(HkMenu("standby"), MenuWatch)
Tray.Add("Read wizard stats now", MenuStats)
Tray.Add("Record potion buying...", MenuPotionRoute)
Tray.Add("Buy potions now", MenuPotionRun)
Tray.Add("Quick sell the backpack now", MenuQuickSell)
Tray.Add("Quick sell rehearsal (stops at the confirmation)", MenuQuickSellRehearse)
Tray.Add("Learn every card (a deck of one of each)", MenuLearnAll)
Tray.Add(HkMenu("restart"), MenuRestart)
Tray.Add(HkMenu("quit"), MenuExit)
Tray.Default := HkMenu("walk")
SetTimer(StartBot,-300)
return

;(F6 / F8 - the bot on / off, walking on / off; while the bot is off - standby, paused: only in Wizard101, not taken
;from other programs. Their keys: Hotkeys.ahk)
MenuBotToggle:
MenuBotToggle()
return

MenuWalk:
MenuWalk()
return

;"Open with Wizard101": a watcher started with Windows opens the bot when the game starts (..\Watch.ahk)
MenuWatch:
MenuWatch()
return

MenuReconnect:
MenuReconnect()
return

MenuHandsOff:
MenuHandsOff()
return

MenuPlayForMe:
MenuPlayForMe()
return

MenuGameFront:
MenuGameFront()
return

MenuLearnAll:
MenuLearnAll()
return

MenuStats:
MenuStats()
return

MenuDash:
MenuDash()
return

;The dashboard's Spells tab: the cards the bot learned by itself, and your corrections (Spells.ahk)
MenuSpells:
MenuSpells()
return

;The Settings window (Settings.ahk): the mouse, the waits, how it plays its cards
MenuSettings:
MenuSettings()
return

;Cheat Engine's speedhack keys (F13-F24 - no keyboard has them): pressed 3 s after you pick this, so you can click into
;Cheat Engine's hotkey box first and set them there
MenuSpeedKeyFast:
MenuSpeedKeyFast()
return
MenuSpeedKeyNormal:
MenuSpeedKeyNormal()
return

;The map window (Dashboard.ahk): a top-down picture of the zone, the wizard and the quest goal
MenuMap:
MenuMap()
return

;(Wiz-Maxxing /check - the exe, or the script when this runs as one: asks GitHub; if you update, it closes this and
;starts the new one)
MenuUpdates:
MenuUpdates()
return

;What went wrong, posted as an issue on GitHub (BugReport.ahk)
MenuBug:
MenuBug()
return

MenuNothing:
MenuNothing()
return

;The latest release looked up now and then, out of this process (Wiz-Maxxing /latest writes updater.ini): the
;dashboard's menu bar (Update to vX) and STATISTICS say from it whether a newer version is out - and UpdAuto installs it.
;45 s after start, then every autoupdate minutes (Settings; 2 hours with it off)
UpdPeekNow:
UpdPeekNow()
return

MenuPotionRoute:
MenuPotionRoute()
return

MenuPotionRun:
MenuPotionRun()
return

;The backpack quick sold for gold now - whether it's full or not (never in a dungeon) - or up to the confirmation only, read
;and closed: nothing sold (QuickSell.ahk)
MenuQuickSell:
MenuQuickSell()
return

MenuQuickSellRehearse:
MenuQuickSellRehearse()
return

MenuLogin:
MenuLogin()
return

;Discord alerts when the wizard needs you (Alerts.ahk): the webhook set, tested or removed
;The party window: this wizard's party name, its role, the leader's address, its battle part (Party.ahk; the role and
;the battle part are Settings > PARTY's too)
MenuParty:
MenuParty()
return

MenuAlerts:
MenuAlerts()
return

MenuRestart:
MenuRestart()
return

MenuExit:
MenuExit()
ExitApp()

StartBot:
StartBot()
return

	
;Functions
;You're playing: a key, a click or a mouse move of yours (not the bot's own, nor what the mouse lock swallowed: UserIdle
;leaves those out) in the last handsoff seconds (PlayerStats.txt, default 3 - and 3 at every start; 0 = never wait for you), while "Wait while
;I play" is on (HandsOffOn). Logged when it starts and ends; PlayerActive tells the dashboard
PlayerActing()
	{
	static logged := 0
	global PlayerActive ; (v1 globals it sets)
	secs := Stats.Has("handsoff") ? Stats["handsoff"] : 3
	acting := (HandsOffOn() && secs > 0 && UserIdle() < secs * 1000)
	;(the bot's own hotkeys aren't you playing: the key itself, and for Alt+1 / Alt+2 / Windows+3 the click
	;on the boss / player that follows within 10 s)
	if (acting && A_ThisHotkey != "")
		{
		;(a click or wheel turn of yours the mouse lock swallowed is a hotkey too - Settings.ahk MouseLockSwallow: the bot's
		;own is the one before it. Your last input as UserIdle has it: what the lock swallowed isn't you)
		hkNow := A_ThisHotkey, keyAt := A_TickCount - A_TimeSinceThisHotkey
		if (MouseLockIsKey(hkNow))
			hkNow := A_PriorHotkey, keyAt := A_TickCount - (A_TimeSincePriorHotkey = "" ? -1 : A_TimeSincePriorHotkey)  ; (v1: -1 with no prior hotkey - v2: blank)
		;(the X key's pass-through hotkey - Puzzle.ahk's, the dungeon recorder's - is your own X, not one of the bot's hotkeys)
		if (hkNow = "~*x")
			hkNow := ""
		lastInput := A_TickCount - UserIdle()
		if (hkNow != "" && lastInput >= keyAt - 50 && lastInput <= keyAt + (HkIsAny(hkNow, "boss,boost,player") ? 11000 : 600))
			acting := false
		}
	if (acting && !logged)
		{
		DebugLog("You're playing - the bot waits until you've left the keyboard and mouse alone for " secs " s"), logged := 1
		SpeedSet(0, "you're playing")
		}
	else if (!acting && logged)
		{
		DebugLog("You've stopped - the bot carries on")
		logged := 0
		;(the walker starts its watch afresh: you may have moved, and the time you played isn't it being stuck - a sigil's
		;wait goes on: WalkResume)
		if (V1IsFunc("WalkResume"))
			WalkResume.Call()
		else if (V1IsFunc("WalkReset"))
			WalkReset.Call()
		}
	PlayerActive := acting
	;(the battle recorder told who plays - only on a change: BattleRec.ahk)
	if (V1IsFunc("BrecWho"))
		BrecWho.Call(acting)
	return acting
	}

;The bot on / off (F6, the tray menu, the dashboard's button): off, the main loop does nothing; keys held let go
BotToggle()
	{
	global BotOn, BotEverOn, PlayerTookRound, BossChoosen, DeckBoss ; (v1 globals it sets)
	;(Wizard101 in the tray - Settings: traygame: the bot stays off till it's shown again - GameTrayBlocked says so)
	if (!BotOn && GameTrayBlocked("turn the bot on"))
		return
	BotOn := !BotOn
	if (BotOn)
		{
		BotEverOn := 1
		;(turned on in a battle: what was played meanwhile isn't known - no kill check till it ends, and the boss
		;picked again with Alt+1)
		if (inbattle == 1)
			PlayerTookRound := 1, BossChoosen := 0, DebugLog("  (turned on in a battle: no kill check till it ends - " HkText("boss") " the boss again to put traps on it, else they go on the enemy with the most health)")
		;(the walker starts afresh: the wizard may have moved meanwhile)
		if (V1IsFunc("WalkReset"))
			WalkReset.Call()
		;(battles only - Settings: battlesonly: it waits for battles and plays them, and moves nothing else)
		if (BattlesOnly())
			{
			DebugLog("Bot on (" HkText("bot") ") - battles only (Settings): it waits for battles and plays them, and moves nothing else")
			TrayTip("On - battles only: the bot plays battles and moves nothing else. " HkText("bot") " pauses it.", "Wizard101 bot", 1)
			}
		else
			{
			DebugLog("Bot on (" HkText("bot") ") - battles, quest walking and potions")
			TrayTip("On - battles, quest walking and potions. " HkText("bot") " pauses it.", "Wizard101 bot", 1)
			}
		}
	else
		{
		if (KeysDown || HeldW)
			ReleaseKeys()
		;(your mouse let go at once - Settings.ahk MouseLockRelease)
		MouseLockRelease("the bot's off")
		if (IsObject(DeckBoss))
			DebugLog("Deck: no boss ahead now - " DeckBoss.name " (the bot's off)"), DeckBoss := ""
		DebugLog("Bot off (" HkText("bot") ") - it does nothing till " HkText("bot") " again")
		SpeedSet(0, "bot off", true)
		TrayTip("Off - the bot does nothing till you press " HkText("bot") " again.", "Wizard101 bot", 1)
		}
	BotOnShow()
	;(the battle recorder told - BattleRec.ahk)
	if (V1IsFunc("BrecWho"))
		BrecWho.Call(PlayerActive, 1)
	}

;A restart (Windows+1, Alt+Esc, the tray menu) that keeps the bot off or in standby - Reload drops the arguments
BotRestart()
	{
	global ErrorLevel ; (v1 globals it sets)
	arg := (BotStandby && !BotEverOn) ? "/standby" : (!BotOn ? "/off" : "")
	if (arg = "")
		{
		Reload()
		return
		}
	;(v1: Run, ..., UseErrorLevel - ErrorLevel "ERROR" when it couldn't start it)
	if (A_IsCompiled)
		ErrorLevel := V1Run("`"" A_ScriptFullPath "`" /restart " arg, A_ScriptDir)
	else
		ErrorLevel := V1Run("`"" A_AhkPath "`" /restart `"" A_ScriptFullPath "`" " arg, A_ScriptDir)
	}

;Walker.ahk's check before it presses a key or clicks for the game's menu: the bot on (F6) - or a potion run you
;started from the tray - and no key or mouse of yours since from (A_TickCount; 0: not looked at)
WalkHostOn(from := 0)
	{
	return (BotOn || PotionManual) && !(from && A_TickCount - UserIdle() > from)
	}

;The tray menu's tick and the dashboard's button for the bot on / off
BotOnShow()
	{
	if (BotOn)
		Tray.Check(HkMenu("bot"))
	else
		Tray.Uncheck(HkMenu("bot"))
	if (V1IsFunc("DashBotShow"))
		DashBotShow.Call(BotOn)
	}

;The tray menu's tick for "Open with Wizard101"
WatchShow()
	{
	if (WatchIsOn())
		Tray.Check(HkMenu("standby"))
	else
		Tray.Uncheck(HkMenu("standby"))
	}

;For Reconnect.ahk's hung-loading check: the game seen in the world since (tick) - the spellbook (out of battle) or a
;battle round's Pass; look: if not, looked for on screen now too (the main loop's own look can be a while ago)
BotWorldSeenSince(since, look := false)
	{
	global BookSeenAt ; (v1 globals it sets)
	if (BookSeenAt > since || PassSeenAt > since)
		return true
	if (!look)
		return false
	UpdateGameRect()
	V1ImageSearch(&bwX, &bwY, GameLeft, GameTop, GameRight, GameBottom, PicOpt("resources\roundfinish.png"))
	if (ErrorLevel = 0)
		{
		BookSeenAt := A_TickCount
		return true
		}
	return PassButtonAt(&bwX, &bwY) = 0
	}

;For Reconnect.ahk: the bot on (F6), or a run from the tray
BotIsOn()
	{
	return BotOn || PotionManual
	}

;For the walker: no battle on - the spellbook (it only shows out of battle) seen in the last 2 s
BotNoBattle(since := 0)
	{
	return BookSeenAt > since && A_TickCount - BookSeenAt < 2000
	}

;"Bring Wizard101 to the front" (tray menu, the dashboard's Bot menu): gamefront in PlayerStats.txt, off unless it's 1
GameFrontOn()
	{
	;(Play for me: the game brought up whenever it's needed)
	return PlayForMe || (Stats.Has("gamefront") && Stats["gamefront"] = 1)
	}

;Turns it on/off and keeps it in PlayerStats.txt (gamefront)
GameFrontToggle()
	{
	;(the setting itself switched - not what Play for me makes of it)
	frontOn := !(Stats.Has("gamefront") && Stats["gamefront"] = 1)
	if (!StatsSet([["gamefront", frontOn ? 1 : 0]]))
		Stats["gamefront"] := frontOn ? 1 : 0
	GameFrontShow()
	DebugLog("Bring Wizard101 to the front: " (frontOn ? "on - when the quest arrow shows or a battle round is up, and you've left the keyboard and mouse alone 3 s" : "off"))
	TrayTip("Bring Wizard101 to the front: " (frontOn ? "ON - when there's something to do (the quest arrow, a battle round)." : "OFF - click into Wizard101 yourself."), "Wizard101 bot", 1)
	}

;The tray menu's tick and the Bot menu's
GameFrontShow()
	{
	frontOn := GameFrontOn()
	if (frontOn)
		Tray.Check("Bring Wizard101 to the front")
	else
		Tray.Uncheck("Bring Wizard101 to the front")
	if (V1IsFunc("DashFrontShow"))
		DashFrontShow.Call(frontOn)
	}

;Wizard101 to the front (gamefront on, it isn't): why - for debug.log; idle - only once you've left the keyboard and
;mouse alone 3 s (walking: what you type elsewhere mustn't end up in the game). WinActivate - never a click (the game's
;Crown shop is in its corner). force: gamefront off too (you've left the PC: nothing touched for 5 minutes). True if it's
;in front now
GameToFront(why, idle := true, force := false)
	{
	static saidAt := 0
	global ErrorLevel ; (v1 globals it sets)
	;(Wizard101 in the tray - Settings: traygame: never brought up by the bot, only by you - the tray menu's Show Wizard101)
	if (GameInTray)
		return false
	if ((!GameFrontOn() && !force) || GameActive())
		return GameActive()
	if (idle && UserIdle() < 3000)
		return false
	;(v1: nothing when the game isn't there - v2 throws)
	V1Try(WinActivate, "ahk_class " GameClass " ahk_exe " GameExe)
	ErrorLevel := !WinWaitActive("ahk_class " GameClass " ahk_exe " GameExe, , 1)
	front := GameActive()
	if (A_TickCount - saidAt > 30000)
		saidAt := A_TickCount, DebugLog((front ? "Wizard101 brought to the front - " : "Wizard101 couldn't be brought to the front (Windows wouldn't let it) - ") why)
	return front
	}

;---- The bot's window and Wizard101 in the tray (Settings: traybot, traygame - THE MOUSE AND WAITS) ----

;"Put the bot's window in the tray" (Settings: traybot, off unless 1): the dashboard's X and minimize button put it in
;the tray, the bot plays on (Dashboard.ahk DashToTray); the tray icon's double-click brings it back (DashFromTray)
TrayBotOn()
	{
	try
		return (IsObject(Stats) && Stats.Has("traybot") && Stats["traybot"] = 1) ? 1 : 0
	catch
		return 0
	}

;"Put Wizard101 in the tray" (Settings: traygame, off unless 1): Alt+F4 in it, its own X and - windowed - its minimize
;button hide its window in the tray, the game still running (GameTrayHide); the tray menu's Show Wizard101 brings it
;back (GameTrayShow)
TrayGameOn()
	{
	try
		return (IsObject(Stats) && Stats.Has("traygame") && Stats["traygame"] = 1) ? 1 : 0
	catch
		return 0
	}

;The tray settings applied (Settings.ahk CfgApply - the Settings window's Save, the dashboard's Settings menu, a
;settings file loaded - and once as the bot starts): the tray menu (TrayWinShow), Alt+F4's hotkey in Wizard101
;(GameTrayKeys) and the watch on its window (GameTrayTick) as they're set now. traygame switched off with Wizard101
;in the tray: shown again, without taking the focus. A switch said in the log
TrayWinTick()
	{
	static wasBot := "", wasGame := ""
	tbOn := TrayBotOn(), tgOn := TrayGameOn()
	TrayWinShow()
	GameTrayKeys(tgOn)
	if (tgOn || GameInTray)
		SetTimer(GameTrayTick, 100)
	if (tbOn != wasBot && (wasBot != "" || tbOn))
		DebugLog("Put the bot's window in the tray (Settings: traybot): " (tbOn ? "on - the dashboard's X or minimize button puts it in the tray, the bot plays on - the tray icon's double-click brings it back, the tray menu's " HkMenu("quit") " stops the bot" : "off - the dashboard's X stops the bot, as before"))
	if (tgOn != wasGame && (wasGame != "" || tgOn))
		DebugLog("Put Wizard101 in the tray (Settings: traygame): " (tgOn ? "on - Alt+F4 in it, its X or (windowed) its minimize button hide it in the tray, the game still running and the bot off meanwhile - the tray menu's Show Wizard101 brings it back" : "off - Alt+F4, its X and its minimize button as ever"))
	wasBot := tbOn, wasGame := tgOn
	if (!tgOn && GameInTray)
		GameTrayShow(false, "Put Wizard101 in the tray switched off (Settings)")
	}

;The tray menu as the tray settings are: traybot on - "Show the bot's window" in it (under the dashboard's item) and the
;tray icon's double-click (else walking on/off, as ever); traygame on, or Wizard101 in the tray - "Show Wizard101" in it
;(under "Bring Wizard101 to the front"), picked only while Wizard101 is in the tray. Off: neither is in the menu
TrayWinShow()
	{
	static botItem := 0, gameItem := 0
	tbOn := TrayBotOn(), tgOn := TrayGameOn() || GameInTray
	try
		{
		if (tbOn && !botItem)
			Tray.Insert("Learned spells", "Show the bot's window", MenuDashShow), botItem := 1
		Tray.Default := tbOn ? "Show the bot's window" : HkMenu("walk")
		if (!tbOn && botItem)
			Tray.Delete("Show the bot's window"), botItem := 0
		}
	try
		{
		if (tgOn && !gameItem)
			Tray.Insert("Auto-reconnect on/off", "Show Wizard101", MenuGameShow), gameItem := 1
		if (gameItem && GameInTray)
			Tray.Enable("Show Wizard101")
		else if (gameItem)
			Tray.Disable("Show Wizard101")
		if (!tgOn && gameItem)
			Tray.Delete("Show Wizard101"), gameItem := 0
		}
	}

;Alt+F4 with Wizard101 the window in front (Shift or Ctrl with it too): on while traygame is - to the tray instead of
;closed (GameTrayAltF4), swallowed either way. The hook itself checks the window in front (HotIfWinActive - as the mouse
;lock's, Settings.ahk), so it never waits on a busy bot
GameTrayKeys(on)
	{
	static made := 0
	if (!on && !made)
		return
	HotIfWinActive("ahk_class Wizard Graphical Client ahk_exe WizardGraphicalClient.exe")
	HkTry("$*!F4", GameTrayAltF4, on ? "On" : "Off")
	HotIfWinActive()
	if (on && ErrorLevel)
		DebugLog("Put Wizard101 in the tray: Alt+F4 couldn't be made a hotkey (ErrorLevel " ErrorLevel ") - it closes Wizard101 as ever")
	made := 1
	}

;Alt+F4 in Wizard101 (GameTrayKeys): the window in front to the tray
GameTrayAltF4(*)
	{
	local v1Keep := V1Thread() ; (v1: each thread had its own ErrorLevel)
	gaWin := 0
	try gaWin := WinActive("ahk_class " GameClass " ahk_exe " GameExe)
	GameTrayHide(gaWin, "Alt+F4")
	}

;A left click on Wizard101's X (GameTrayXHit said so - swallowed, the game gets nothing): to the tray
GameTrayXClick(*)
	{
	local v1Keep := V1Thread() ; (v1: each thread had its own ErrorLevel)
	GameTrayHide(GameTrayXWin, "its X")
	}

;Why Wizard101 can't go to the tray now - "" it can: two game windows open (which one the bot plays, and which one is
;hidden, can't be told apart), a reconnect under way (its clicks and a restart of the game need the window), a run you
;started from the tray or a potion recording going on (they send keys and clicks to the game)
GameTrayNo()
	{
	gnCount := 0
	try gnCount := WinGetCount("ahk_class " GameClass " ahk_exe " GameExe)
	if (gnCount >= 2)
		return "two Wizard101 windows are open"
	if (RcState != "" && RcState != "box" && RcState != "stopped")
		return "the bot is getting it back online (auto-reconnect)"
	if (PotionManual || PotionRecording || (QsBusy && QsManual))
		return "a potion run, potion recording or quick sell you started is under way"
	return ""
	}

;Wizard101's window (win) to the tray - how: "Alt+F4", "its X", "its minimize button" (for the log). Not while
;GameTrayNo says why not (said - the log and a tray tip - and nothing done). Every key let go first (they still reach the
;game), the bot switched off the normal way (BotToggle - each round and the walker stop as for F6; a click or key it
;had under way is dropped, not sent to the window behind: ClickAt, TargetClick, the potions' keys... look at
;GameInTray) - on again once it's back (GameTrayBack) - and the window hidden: the game runs on, nothing is sent into
;it. Its handle and process kept, in dashboard.ini [gametray] too (shown again at the next start, or by the watcher, if
;the bot ends without showing it - Watch.ahk WatchTrayBack). True if it went
GameTrayHide(win, how)
	{
	static said := false
	global GameInTray, GameTrayHwnd, GameTrayPid, GameTrayMin, GameTrayBotWas, GameTrayAt
	if (!win || !TrayGameOn() || (GameInTray && win = GameTrayHwnd))
		return false
	ghCrit := A_IsCritical
	Critical()
	ghNo := GameInTray ? "another Wizard101 is in the tray already" : GameTrayNo()
	if (ghNo != "")
		{
		ghMin := (how = "its minimize button")
		DebugLog("Wizard101 to the tray (" how "): not now - " ghNo (ghMin ? " - it stays minimized" : " - nothing done"))
		TrayTip("Wizard101 can't go to the tray now: " ghNo "." (ghMin ? " It stays minimized." : ""), "Wizard101 bot", 2)
		if (!ghCrit)
			Critical("Off")
		return false
		}
	ReleaseKeys()
	ghPid := 0
	DllCall("GetWindowThreadProcessId", "Ptr", win, "UInt*", &ghPid)
	GameTrayBotWas := BotOn ? 1 : 0
	if (BotOn)
		BotToggle()
	GameTrayMin := DllCall("IsIconic", "Ptr", win) ? 1 : 0
	;(SW_HIDE - async: a hung game doesn't hold the bot)
	DllCall("ShowWindowAsync", "Ptr", win, "Int", 0)
	GameTrayHwnd := win, GameTrayPid := ghPid, GameTrayAt := A_TickCount, GameInTray := 1
	ghIni := A_ScriptDir "\dashboard.ini"
	V1Do(IniWrite, win, ghIni, "gametray", "hwnd")
	V1Do(IniWrite, ghPid, ghIni, "gametray", "pid")
	V1Do(IniWrite, GameTrayMin, ghIni, "gametray", "min")
	TrayWinShow()
	DebugLog("Wizard101 in the tray (" how " - Settings: traygame): its window hidden, the game still running" (GameTrayBotWas ? " - the bot off till it's shown again" : "") " - the tray menu's Show Wizard101 brings it back")
	if (!said)
		said := true, TrayTip("Wizard101 is in the tray, still running" (GameTrayBotWas ? " - the bot is off till it's back" : "") ". The tray menu's `"Show Wizard101`" brings it back.", "Wizard101 bot", 1)
	else if (GameTrayBotWas)
		TrayTip("Wizard101 is in the tray - the bot is off till it's back (the tray menu's `"Show Wizard101`").", "Wizard101 bot", 1)
	if (!ghCrit)
		Critical("Off")
	return true
	}

;Wizard101 out of the tray: user (the tray menu's Show Wizard101 - you asked) restored and brought to the front; else
;(traygame switched off, the bot closing) shown as it was - minimized if it was - never taking the focus. Then
;forgotten, and - not as the bot closes (botBack false) - the bot on again if it was when the game went (GameTrayBack)
GameTrayShow(user, why, botBack := true)
	{
	if (!GameInTray)
		return
	;(Critical till it's forgotten - GameTrayBack: the tick, GameTrayStep, if it ran in the wait below or in
	;WinActivate's own delay, would take this show for the game showing its window by itself. A Critical thread's
	;Sleep holds the tick back: it runs once the show's done, the game out of the tray)
	gsCrit := A_IsCritical
	Critical()
	gsWin := GameTrayHwnd, gsMin := GameTrayMin
	if (DllCall("IsWindow", "Ptr", gsWin))
		{
		;(yours: SW_RESTORE 9 if it was minimized, else SW_SHOW 5 - a maximized game stays so. Else SW_SHOWMINNOACTIVE 7
		;or SW_SHOWNA 8: never activated. Async: a hung game doesn't hold the bot)
		DllCall("ShowWindowAsync", "Ptr", gsWin, "Int", user ? (gsMin ? 9 : 5) : (gsMin ? 7 : 8))
		if (user)
			{
			;(shown by the game's own thread: once it's up, to the front - you asked)
			Loop 20
				{
				if (DllCall("IsWindowVisible", "Ptr", gsWin))
					break
				Sleep(25)
				}
			V1Try(WinActivate, "ahk_id " gsWin)
			}
		}
	GameTrayBack("shown again - " why, botBack)
	if (!gsCrit)
		Critical("Off")
	}

;Wizard101 no longer in the tray (why: for the log): forgotten (GameTrayForget), and the bot on again the normal way if
;it was when the game went (botBack - not as the bot closes). A game that closed while hidden: Reconnect then sees it
;closed and offers to start it again, as whenever the game closes with the bot on
GameTrayBack(why, botBack := true)
	{
	gbBot := GameTrayBotWas
	GameTrayForget(why)
	if (botBack && gbBot && !BotOn)
		BotToggle()
	}

;Its handle and dashboard.ini's entry forgotten, the tray menu's Show Wizard101 greyed (gone with traygame off),
;Reconnect's waits started afresh (Reconnect.ahk RcAfterTray - none ran on while it was hidden)
GameTrayForget(why)
	{
	global GameInTray, GameTrayHwnd, GameTrayPid, GameTrayMin, GameTrayBotWas
	GameInTray := 0, GameTrayHwnd := 0, GameTrayPid := 0, GameTrayMin := 0, GameTrayBotWas := 0
	try IniDelete(A_ScriptDir "\dashboard.ini", "gametray")
	TrayWinShow()
	RcAfterTray()
	DebugLog("Wizard101 out of the tray: " why)
	}

;Something you started from the tray or the dashboard that needs the game (what: "buy potions"...) while Wizard101 is in
;the tray: said - the log and a tray tip - and true: nothing done
GameTrayBlocked(what)
	{
	if (!GameInTray)
		return false
	DebugLog("Wizard101 is in the tray: can't " what " - show Wizard101 first (the tray menu)")
	TrayTip("Wizard101 is in the tray - show Wizard101 first (the tray menu's `"Show Wizard101`"), then " what ".", "Wizard101 bot", 1)
	return true
	}

;The bot closing (OnExit - every way it ends but a kill or a crash: those are put right at the next start, or by the
;watcher): a Wizard101 in the tray shown again as it was, never taking the focus. 0: the exit goes on
GameTrayOnExit(*)
	{
	local v1Keep := V1Thread() ; (v1: each thread had its own ErrorLevel)
	try
		{
		if (GameInTray)
			GameTrayShow(false, "the bot is closing", false)
		}
	return 0
	}

;Every 100 ms while traygame is on or Wizard101 is in the tray (TrayWinTick starts it, it stops itself): one step
;(GameTrayStep) - an error said in the log once, never an error box (it would take the focus)
GameTrayTick()
	{
	static busy := 0, errSaid := 0
	local v1Keep := V1Thread() ; (v1: each thread had its own ErrorLevel)
	if (busy)
		return
	busy := 1
	try
		GameTrayStep()
	catch Any as gtErr
		{
		if (!errSaid)
			errSaid := 1, DebugLog("Put Wizard101 in the tray: " gtErr.Message " (" gtErr.What ", line " gtErr.Line ") - said once a run")
		}
	busy := 0
	}

;The tick. Wizard101 in the tray: its process ended or its window gone, or the game showed it again by itself (seen
;hidden first - the hide is async, a busy game takes it late) - not in the tray any more (GameTrayBack). traygame on, a
;game window up: its minimize button - a window with a title bar (windowed), not exclusive full screen, minimized while
;the bot watched (one minimized already when first seen is left) - sends it to the tray; the left button's hotkey for
;its X is on only while the pointer is over its title bar (GameTrayXGate). Off and nothing in the tray: the timer stops
GameTrayStep()
	{
	static seenWin := 0, seenIconic := 0, seenCaption := 0, fullScreen := 0, fsLookAt := 0, hidAt := 0
	if (GameInTray)
		{
		if (!DllCall("IsWindow", "Ptr", GameTrayHwnd) || (GameTrayPid && !ProcessExist(GameTrayPid)))
			GameTrayBack("the game closed while it was in the tray")
		else if (!DllCall("IsWindowVisible", "Ptr", GameTrayHwnd))
			hidAt := GameTrayAt
		else if (hidAt = GameTrayAt)
			GameTrayBack("the game showed its window again by itself")
		}
	if (!TrayGameOn())
		{
		if (!GameTrayXGate(0) && !GameInTray)
			SetTimer(GameTrayTick, 0)
		seenWin := 0
		return
		}
	stWin := 0
	try stWin := WinExist("ahk_class " GameClass " ahk_exe " GameExe)
	if (!stWin)
		{
		GameTrayXGate(0)
		seenWin := 0
		return
		}
	stIconic := DllCall("IsIconic", "Ptr", stWin) ? 1 : 0
	if (stWin != seenWin)
		seenWin := stWin, seenIconic := stIconic, seenCaption := 0, fullScreen := 0, fsLookAt := 0
	if (!stIconic)
		{
		;(windowed: a title bar - WS_CAPTION 0xC00000. Borderless has none, and its minimize never sends it to the tray)
		seenCaption := (DllCall("GetWindowLong", "Ptr", stWin, "Int", -16, "Int") & 0xC00000) = 0xC00000
		;(exclusive full screen - it minimizes itself on Alt+Tab: Windows says QUNS_RUNNING_D3D_FULL_SCREEN, 3, while it's
		;in front - looked at once a second)
		if (A_TickCount - fsLookAt > 1000 && DllCall("GetForegroundWindow", "Ptr") = stWin)
			{
			fsLookAt := A_TickCount, stQuns := 0
			if (DllCall("shell32\SHQueryUserNotificationState", "Int*", &stQuns, "Int") = 0)
				fullScreen := (stQuns = 3)
			}
		}
	if (stIconic != seenIconic)
		{
		seenIconic := stIconic
		if (stIconic && seenCaption && !fullScreen)
			{
			GameTrayXGate(0)
			GameTrayHide(stWin, "its minimize button")
			return
			}
		}
	GameTrayXGate(!stIconic && seenCaption && GameTrayOverCaption(stWin), stWin)
	}

;The pointer over win's title bar - or within 24 pixels of it, never in the game's inside: where its X is
GameTrayOverCaption(win)
	{
	ocPt := Buffer(8, 0), ocWr := Buffer(16, 0), ocCt := Buffer(8, 0)
	if (!DllCall("GetCursorPos", "Ptr", ocPt) || !DllCall("GetWindowRect", "Ptr", win, "Ptr", ocWr) || !DllCall("ClientToScreen", "Ptr", win, "Ptr", ocCt))
		return false
	ocX := NumGet(ocPt, 0, "Int"), ocY := NumGet(ocPt, 4, "Int")
	return ocX >= NumGet(ocWr, 0, "Int") - 24 && ocX < NumGet(ocWr, 8, "Int") + 24 && ocY >= NumGet(ocWr, 4, "Int") - 24 && ocY < NumGet(ocCt, 4, "Int")
	}

;The left button's hotkey for Wizard101's X (GameTrayXHit decides at each click) on or off - on only while the pointer
;is over the game's title bar: each left click then waits for the bot's answer, so nowhere else. Not switched while the
;mouse lock holds the mouse (a Hotkey command after BlockInput could take the hook it needs - Settings.ahk
;MouseLockApply). win: the game's window it's for. On now?
GameTrayXGate(on, win := 0)
	{
	static made := 0, now := 0
	global GameTrayXWin
	on := on ? 1 : 0
	if (on)
		GameTrayXWin := win
	if (on = now || (!on && !made) || MouseLocked)
		return now
	;(its own check - not the mouse lock's or the potion recorder's left button: theirs stay as they are)
	HotIf(GameTrayXHit)
	HkTry("*LButton", GameTrayXClick, on ? "On" : "Off")
	HotIf()
	if (!ErrorLevel)
		now := on, made := 1
	return now
	}

;The left button's hotkey's check (HotIf - asked at each left click while the gate is on): true only for a click on
;Wizard101's own X. Never in its inside (the game's picture: no click of yours or the bot's in the game is taken); the
;window under the pointer the game's own (not one over it, not a hung game's stand-in); then the game is asked what's
;there (WM_NCHITTEST 0x84, waited for 40 ms at most - a hung or busy game: false, the click goes through) - its close
;button: HTCLOSE, 20. Measured as the game sees the screen (its DPI awareness - Windows 10 1607 or newer). Any error:
;false
GameTrayXHit(*)
	{
	xhOld := 0
	try
		{
		xhWin := GameTrayXWin
		if (!xhWin || GameInTray || !TrayGameOn())
			return false
		try xhOld := DllCall("SetThreadDpiAwarenessContext", "Ptr", DllCall("GetWindowDpiAwarenessContext", "Ptr", xhWin, "Ptr"), "Ptr")
		xhPt := Buffer(8, 0), xhRc := Buffer(16, 0), xhCt := Buffer(8, 0)
		if (!DllCall("GetCursorPos", "Ptr", xhPt))
			return false
		xhX := NumGet(xhPt, 0, "Int"), xhY := NumGet(xhPt, 4, "Int")
		xhAt := DllCall("WindowFromPoint", "Int64", (xhY << 32) | (xhX & 0xFFFFFFFF), "Ptr")
		if (!xhAt || DllCall("GetAncestor", "Ptr", xhAt, "UInt", 2, "Ptr") != xhWin)
			return false
		DllCall("GetClientRect", "Ptr", xhWin, "Ptr", xhRc)
		DllCall("ClientToScreen", "Ptr", xhWin, "Ptr", xhCt)
		xhL := NumGet(xhCt, 0, "Int"), xhT := NumGet(xhCt, 4, "Int")
		if (xhX >= xhL && xhX < xhL + NumGet(xhRc, 8, "Int") && xhY >= xhT && xhY < xhT + NumGet(xhRc, 12, "Int"))
			return false
		return SendMessage(0x84, 0, ((xhY & 0xFFFF) << 16) | (xhX & 0xFFFF), , "ahk_id " xhWin, , , , 40) = 20
		}
	catch
		return false
	finally
		{
		if (xhOld)
			DllCall("SetThreadDpiAwarenessContext", "Ptr", xhOld, "Ptr")
		}
	}

;"Wait while I play" (tray menu, the dashboard's Bot menu): handsoffon in PlayerStats.txt, on unless it's 0
HandsOffOn()
	{
	return !(Stats.Has("handsoffon") && !Stats["handsoffon"])
	}

;Turns "Wait while I play" on/off and keeps it in PlayerStats.txt (handsoffon)
HandsOffToggle()
	{
	waitOn := !HandsOffOn()
	if (!StatsSet([["handsoffon", waitOn ? 1 : 0]]))
		Stats["handsoffon"] := waitOn ? 1 : 0
	HandsOffShow()
	DebugLog("Wait while I play: " (waitOn ? "on - the bot waits while you use the keyboard or mouse" : "off - the bot carries on while you play"))
	TrayTip("Wait while I play: " (waitOn ? "ON - the bot waits while you use the keyboard or mouse." : "OFF - the bot carries on even while you play."), "Wizard101 bot", 1)
	}

;"Play for me" on/off - the dashboard's button (red off, green on), the tray menu. On: every check for you off (UserIdle) -
;the bot plays on as if you've left the PC, taking the mouse and the game's window whenever it needs them. F6 / F8 still
;stop it. On and off at a click - no box to type in (you asked, 2026-10-26: the pimpmeout box of 2026-10-23 gone). Never
;kept: off at every start
PlayForMeToggle()
	{
	global PlayForMe ; (v1 globals it sets)
	PlayForMe := !PlayForMe
	PlayForMeShow()
	DebugLog("Play for me: " (PlayForMe ? "ON - every check for you is off: the bot takes the mouse and the game's window whenever it needs them (" HkText("bot") " stops it)" : "off - the bot waits for you and keeps its hands off while you play, as set"))
	TrayTip(PlayForMe ? "PLAY FOR ME is on: the bot no longer waits for you - it takes the mouse and the game whenever it needs them. " HkText("bot") " stops it." : "Play for me is off: the bot waits for you again.", "Wizard101 bot", PlayForMe ? 2 : 1)
	}

;The tray menu's tick and the dashboard's button (green while it's on)
PlayForMeShow()
	{
	if (PlayForMe)
		Tray.Check("Play for me (leave it alone for days)")
	else
		Tray.Uncheck("Play for me (leave it alone for days)")
	if (V1IsFunc("DashPlayShow"))
		DashPlayShow.Call(PlayForMe)
	;(the Bring Wizard101 to the front ticks too: Play for me brings the game up whatever it's set to)
	GameFrontShow()
	}

;The tray menu's tick and the Bot menu's
HandsOffShow()
	{
	waitOn := HandsOffOn()
	if (waitOn)
		Tray.Check("Wait while I play")
	else
		Tray.Uncheck("Wait while I play")
	if (V1IsFunc("DashHandsShow"))
		DashHandsShow.Call(waitOn)
	}

;"Battles only" (Settings: battlesonly - the tray menu; kept in PlayerStats.txt like the others): for a wizard riding another's
;mount - the driver takes it everywhere -, or wherever the bot must only play battles. Out of battle it moves nothing: quest
;walking stays off (every start, an update's restart too; F8 says why), no party following, dungeon run, puzzle try or potion
;run (a potion is still drunk - Ctrl+O - when health is low; out of potions it only alerts), no mob-loop / lore / afk move, no
;chat command's walk, sigil or teleport, no developer loop. Kept: battles as ever (rounds, cards, the kill check, boosts, the
;deck for a boss, flee, potions in battle), the party's link and battle roles, auto-reconnect, quick sell, alerts, the log's copy
BattlesOnly()
	{
	try
		return (IsObject(Stats) && Stats.Has("battlesonly") && Stats["battlesonly"]) ? 1 : 0
	catch
		return 0
	}

;A move battles only keeps from happening (what: what it would have been - "run to buy potions"): true while it's on, the
;reason in the log once while it's on (tell: each time, and a tray tip - a key or menu item of yours). what "": the ones said
;forgotten (BattlesOnlyTick, at each switch)
BattlesOnlyNo(what, tell := false)
	{
	static said := Map()
	if (what = "")
		{
		said := Map()
		return false
		}
	if (!BattlesOnly())
		return false
	if (tell || !said.Has(what))
		{
		said[what] := 1
		DebugLog("Battles only (Settings): no " what " - the bot plays battles and moves nothing else")
		if (tell)
			TrayTip("Battles only is on: no " what " - the bot plays battles and moves nothing else. Settings or the tray menu switches it off.", "Wizard101 bot", 1)
		}
	return true
	}

;Battles only switched (CfgApply - the Settings window's Save, a settings file loaded -, the tray menu - and the main loop's
;look at it, each pass): said in the log, the tray menu's tick. On: walking off and every key let go, a dungeon run stopped, a
;puzzle try dropped, the walker's notice closed. At the start (StartBot's call) said only when it's on
BattlesOnlyTick()
	{
	static was := ""
	global Walking
	now := BattlesOnly()
	if (was != "" && now = was)
		return
	first := (was = "")
	was := now
	BattlesOnlyShow()
	BattlesOnlyNo("")
	if (!now)
		{
		if (!first)
			{
			DebugLog("Battles only: off - walking (" HkText("walk") "), party following, dungeon runs, puzzle tries and potion runs as set (Settings)")
			TrayTip("Battles only: OFF - walking (" HkText("walk") " starts it), following, dungeon and potion runs as set.", "Wizard101 bot", 1)
			}
		return
		}
	DebugLog("Battles only: on - the bot plays battles and moves nothing else (Settings)")
	TrayTip("Battles only: ON - the bot plays battles and moves nothing else (no walking, following, dungeon or potion runs). Settings or the tray menu switches it off.", "Wizard101 bot", 1)
	if (Walking)
		{
		Walking := 0
		DebugLog("  walking off (" HkText("walk") " doesn't walk while battles only is on)")
		}
	if (KeysDown || HeldW)
		ReleaseKeys()
	if (IsObject(DgRun) && V1IsFunc("DgStop"))
		DgStop.Call("battles only is on (Settings)", false)
	if (V1IsFunc("PuzzleForget"))
		PuzzleForget.Call("battles only is on (Settings)")
	if (V1IsFunc("WalkNotifyClose"))
		WalkNotifyClose.Call()
	}

;The tray menu's tick (the dashboard's top line and the Network tab say it too - DashRefresh, NetTick)
BattlesOnlyShow()
	{
	if (BattlesOnly())
		Tray.Check("Battles only (moves nothing out of battle)")
	else
		Tray.Uncheck("Battles only (moves nothing out of battle)")
	}

;The tray menu's Battles only: switched, and kept in PlayerStats.txt (battlesonly - Settings has it too)
BattlesOnlyToggle()
	{
	boOn := !BattlesOnly()
	if (!StatsSet([["battlesonly", boOn ? 1 : 0]]))
		Stats["battlesonly"] := boOn ? 1 : 0
	BattlesOnlyTick()
	}

;The main loop's step out of a battle round while battles only is on - instead of the walker's, a party follower's, a dungeon
;run's, a puzzle try's or the farming modes': nothing moved, any key let go, a short wait - the round watch goes on
BattlesOnlyWait()
	{
	;(when it last tried to bring the game to the front - at most every 1.5 s, as the walker)
	static frontLook := 0
	global Walking
	;(nothing turns walking on while it's on - the start, F8 and a dungeon run's Run keep it off: never left on all the same)
	if (Walking)
		{
		Walking := 0
		BattlesOnlyNo("walking - it was on: off again")
		}
	if (KeysDown || HeldW)
		ReleaseKeys()
	;(Wizard101 behind another window: no walking or following brings it forward now. You away 5 minutes - or Play for me: to
	;the front, as the walker and a party's follower do - else a battle the driver takes it into is never seen (its Pass is
	;looked for on the screen), and the driver holds for it for good (ready only with its game in front - Party.ahk PartyTick).
	;gamefront on: as soon as the game's log says a round is up. WinActivate only - nothing pressed or clicked)
	if (!GameActive() && A_TickCount - frontLook > 1500)
		{
		if (UserIdle() > 300000)
			frontLook := A_TickCount, GameToFront("battles only: nothing touched for 5 minutes, another window in front", true, true)
		else if (GameFrontOn() && BattleLogPlanning(0))
			frontLook := A_TickCount, GameToFront("battles only: a battle round is up (the game's log)")
		}
	if (inbattle != 1)
		SetStatus("battles only - waiting for a battle")
	Sleep(50)
	}

;Moves the mouse to x, y and clicks, quickly: mousespeed (0 = jump there, 1 = fastest glide; it used to
;be 5), clickwait ms before the click (used to be 150) plus up to clickrandom ms, and after it `after` ms
;times clickafter % (PlayerStats.txt, the Settings window; it used to wait the whole of it)
ClickAt(x, y, after := 0)
	{
	;(Wizard101 in the tray - Settings: traygame: nothing clicked, it would land on the window behind it - the clicks of
	;a round under way when Alt+F4 or its X sent it there, from another thread, too)
	if (GameInTray)
		return
	;(not in a battle round: the mouse goes back where it was after the click - mousereturn)
	ownGrab := MouseGrab()
	;(your mouse locked meanwhile - a battle round has it locked already: Settings.ahk MouseLockOn)
	MouseLockOn("click")
	MoveToCard(x, y)
	Sleep(Stats.Has("clickwait") ? Stats["clickwait"] : 40)
	;(and a random bit more: clickrandom)
	if (Stat("clickrandom") > 0)
		{
		clickExtra := Random(0, Stat("clickrandom"))
		Sleep(clickExtra)
		}
	;(gone to the tray during the waits: not clicked)
	if (!GameInTray)
		Click()
	if (after)
		AfterClick(after)
	if (ownGrab)
		MouseLetGo()
	MouseLockOff("click")
	}

;A wait after a click: ms times clickafter % (PlayerStats.txt; lower is faster)
AfterClick(ms)
	{
	Sleep(Round(ms * (Stats.Has("clickafter") ? Stats["clickafter"] : 50) / 100))
	}

;The mouse to x, y - a card in the hand from above: moved straight across the hand it passes over the cards between,
;the game zooms each up as it's hovered, and a zoomed card covers part of its neighbour - the click lands on it
;(2026-10-22: Sharpened Blade picked up, the click meant for the Balanceblade at the hand's end hit the greyed Sandstorm
;beside it and the enchant dropped). So: straight up above the hand, across, a moment for the zoom to go down, then
;down onto the card. Not on the hand's row (an enemy, Pass, yourself): straight there. Already on that card: just there
MoveToCard(x, y)
	{
	;(Wizard101 in the tray - Settings: traygame: your pointer left where it is - as ClickAt)
	if (GameInTray)
		return
	;(the bot still at it: the mouse lock's watchdog starts again - Settings.ahk MouseLockRenew; after each move, your
	;clicks swallowed now the pointer's on the game - MouseLockMoved)
	MouseLockRenew()
	top := ScreenY - Px(90), bottom := ScreenY + Px(80), above := ScreenY - Px(150)
	;(v1: a spot not found is blank - MouseMove kept the mouse's own place for a blank coordinate, and a blank y, "less"
	;than every number as text, went straight there)
	if (x = "" || y = "")
		{
		MouseGetPos(&bx, &by)
		if (y = "")
			{
			MouseMove(x = "" ? bx : x, by, MouseSpeedNow())
			MouseLockMoved()
			return
			}
		x := bx
		}
	if (y < top || y > bottom)
		{
		MouseMove(x, y, MouseSpeedNow())
		MouseLockMoved()
		return
		}
	MouseGetPos(&mx, &my)
	if (Abs(mx - x) > Px(20) || my < top || my > bottom)
		{
		if (my >= top)
			MouseMove(mx, above, MouseSpeedNow())
		MouseMove(x, above, MouseSpeedNow())
		MouseLockMoved()
		Sleep(120)
		}
	MouseMove(x, y, MouseSpeedNow())
	MouseLockMoved()
	}

MouseSpeedNow()
	{
	return Stats.Has("mousespeed") ? Stats["mousespeed"] : 1
	}

CenterMouse()
	{
	;(Wizard101 in the tray - Settings: traygame: your pointer left where it is - as ClickAt)
	if (GameInTray)
		return
	UpdateGameRect()
	MouseLockRenew()
	MouseMove(ScreenX, ScreenY + Px(100), MouseSpeedNow())
	MouseLockMoved()
	}

;This bot's version (version.txt in its folder: v0.25.1...), "" if there's none
BotVersion()
	{
	static v := "-"
	if (v = "-")
		{
		v := V1FileRead(A_ScriptDir "\..\version.txt")
		v := Trim(v, " `t`r`n")
		}
	return v
	}

;The update check (Wiz-Maxxing /check): a newer version offered and installed if you say so, the bot then started
;again as it is now (off: /off, in standby: /standby). False (and a tray tip) if Wiz-Maxxing can't be started
UpdCheckNow()
	{
	updArg := UpdBotArgs(), updArg := updArg = "" ? "" : " " updArg
	if (BotRun(A_ScriptDir "\..\Wiz-Maxxing", "/check" updArg, A_ScriptDir "\.."))
		return true
	TrayTip("Couldn't start Wiz-Maxxing for the update check (error " A_LastError ").", "Wizard101 bot", 2)
	return false
	}

;Updates by itself (Settings: autoupdate - you asked 2026-10-23, so Claude's fixes get tried with nobody at the PC).
;1. A newer release seen by the look-up (UpdPeekNow): Wiz-Maxxing /check /auto downloads it while the bot plays on.
;2. It's ready (updater.ini [auto] ready, by a Wiz-Maxxing still running - readypid): the bot closes itself at a safe
;point (UpdSafe), writing how it is (handover, args - UpdBotArgs), and Wiz-Maxxing installs it and starts it again so.
;Never closed under it. A version tried 3 times in 6 hours (Updater.ahk UpAuto) is left to the dashboard's Help > Check for updates
UpdAuto()
	{
	static lookAt := 0, startAt := 0, ranAt := 0, saidTag := "", gaveUpTag := "", waitTag := "", aliveAt := 0, aliveTag := ""
	static alive := false
	if (A_TickCount - lookAt < 5000)
		return
	lookAt := A_TickCount
	startAt := startAt ? startAt : A_TickCount
	if (Stat("autoupdate") <= 0 || A_TickCount - startAt < 60000)
		return
	ini := A_ScriptDir "\..\updater.ini"
	ready := IniRead(ini, "auto", "ready", A_Space)
	if (ready != "" && VersionCompare(ready, BotVersion()) > 0)
		{
		;(the Wiz-Maxxing that downloaded it still waiting - UpdReadyAlive; looked at every 30 s, and again just before
		;closing)
		if (A_TickCount - aliveAt > 30000 || aliveTag != ready)
			alive := UpdReadyAlive(ini), aliveAt := A_TickCount, aliveTag := ready
		if (!alive)
			{
			aliveAt := 0
			return
			}
		;(Update to vX picked in the dashboard's menu bar meanwhile: closed for it as soon as it's out of battle - you asked)
		nowAsked := IniRead(ini, "auto", "now", 0)
		if (!UpdSafe(nowAsked = 1))
			{
			if (waitTag != ready)
				DebugLog("Updates: " ready " is downloaded - the bot closes for it once out of battle, nothing's loading and you've left the keys and mouse alone a minute")
			waitTag := ready
			return
			}
		if (!UpdReadyAlive(ini))
			{
			aliveAt := 0
			return
			}
		hand := UpdBotArgs()
		V1Do(IniWrite, hand, ini, "auto", "args")
		V1Do(IniWrite, 1, ini, "auto", "handover")
		DebugLog("Updates: closing for " ready " - Wiz-Maxxing installs it and starts the bot again as it is now" (hand = "" ? "" : " (" hand ")"))
		ExitApp()
		}
	upd := UpdState()
	if (!upd.newer)
		return
	triedTag := IniRead(ini, "auto", "tag", A_Space)
	tries := IniRead(ini, "auto", "tries", 0)
	triedAt := IniRead(ini, "auto", "at", A_Space)
	age := A_Now
	;(v1 EnvSub: a time that isn't one made age blank - v2's DateDiff throws)
	age := V1Try(DateDiff, (age != "" ? age : A_Now), (triedAt != "" ? triedAt : A_Now), "Hours")
	if (triedTag = upd.latest && age != "" && age < 6 && V1Ge(tries, 3))
		{
		if (gaveUpTag != upd.latest)
			DebugLog("Updates: " upd.latest " didn't install by itself in 3 tries (updater.log) - left to the dashboard's Help > Check for updates")
		gaveUpTag := upd.latest
		return
		}
	;(one download at a time - another try 15 minutes on, if this one's come to nothing)
	if ((ranAt && A_TickCount - ranAt < 900000) || (A_IsCompiled && !FileExist(A_ScriptDir "\..\Wiz-Maxxing.exe")))
		return
	ranAt := A_TickCount
	if (saidTag != upd.latest)
		DebugLog("Updates: " upd.latest " is out - downloading it (Settings: autoupdate); the bot plays on till it's ready")
	saidTag := upd.latest
	if (!BotRun(A_ScriptDir "\..\Wiz-Maxxing", "/check /auto", A_ScriptDir "\.."))
		DebugLog("Updates: couldn't start Wiz-Maxxing to download " upd.latest " (error " A_LastError ")")
	}

;The Wiz-Maxxing that downloaded an update by itself still waiting for the bot to close (UpdAuto): its process there with
;/auto, under 58 minutes since it said ready (it waits an hour: never closed just as it gives up). Else - the PC restarted, it was ended - nothing to close for (a recycled
;process id taken for it would leave the bot closed): its marks cleared
UpdReadyAlive(ini)
	{
	readyPid := IniRead(ini, "auto", "readypid", 0)
	readyAt := IniRead(ini, "auto", "readyat", A_Space)
	age := A_Now
	;(v1 EnvSub: a time that isn't one made age blank - v2's DateDiff throws)
	age := V1Try(DateDiff, (age != "" ? age : A_Now), (readyAt != "" ? readyAt : A_Now), "Minutes")
	if (RegExMatch(readyPid, "^\d+$") && age != "" && age < 58)
		for p in ComObjGet("winmgmts:").ExecQuery("SELECT CommandLine FROM Win32_Process WHERE ProcessId=" readyPid)
			if (InStr(p.CommandLine, "/auto"))
				return true
	for i, k in ["ready", "readypid", "readyat", "now"]
		V1Do(IniDelete, ini, "auto", k)
	return false
	}

;A safe point to close the bot for an update (UpdAuto; out of battle: its caller): nothing loading, no login or restart of
;the game going on, no dungeon run or recording under way, and the keyboard and mouse left alone a minute (Play for me:
;never waited for; anyNow: you clicked Update). The loading / reconnect state only counts while it's kept up to date -
;the bot on, auto-reconnect on and not told to leave the game closed ("stopped": it gave up - nothing going on)
UpdSafe(anyNow := false)
	{
	rcBusy := BotOn && RcOn && !RcNoRelaunch && (RcLoadAt || (RcState != "" && RcState != "stopped"))
	;(the game closed with no login to start it again with - or one it turned down: nothing going on either)
	if (rcBusy && !RcLoadAt && RcState = "gone" && (RcLoginBad || !RcHaveLogin()))
		rcBusy := false
	return !(BattleLogInBattle() || rcBusy || IsObject(DgRun) || DgRecording || PotionRecording
		|| (!anyNow && UserIdle() < 60000))
	}

;How the bot is, for starting it again so after an update (Wiz-Maxxing /check passes them on - StartBot): off or in
;standby, Play for me on, walking (F8) or auto-reconnect off, Learn every card on
UpdBotArgs()
	{
	a := (BotStandby && !BotEverOn) ? " /standby" : !BotOn ? " /off" : ""
	a .= (PlayForMe ? " /playforme" : "") (!Walking ? " /nowalk" : "") (!RcOn ? " /noreconnect" : "") (LearnAll ? " /learnall" : "")
	return Trim(a)
	}

;"v0.25.2" vs "v0.25.1" (vMAJOR.MAIN.BUG): 1 newer, 0 the same, -1 older; "" is older than any
VersionCompare(a, b)
	{
	if (a = b)
		return 0
	if (!RegExMatch(a, "(\d+)\.(\d+)(?:\.(\d+))?", &x))
		return -1
	if (!RegExMatch(b, "(\d+)\.(\d+)(?:\.(\d+))?", &y))
		return 1
	pa := [x[1] + 0, x[2] + 0, x[3] = "" ? 0 : x[3] + 0], pb := [y[1] + 0, y[2] + 0, y[3] = "" ? 0 : y[3] + 0]
	Loop 3
		{
		if (pa[A_Index] != pb[A_Index])
			return pa[A_Index] > pb[A_Index] ? 1 : -1
		}
	return 0
	}

;What the last look-up of the latest release said (updater.ini [latest], read at most every 5 s): {latest: its
;tag, err, newer: true when it's newer than this bot}
UpdState()
	{
	static state := "", readAt := 0
	if (!IsObject(state) || A_TickCount - readAt > 5000)
		{
		readAt := A_TickCount
		ini := A_ScriptDir "\..\updater.ini"
		latest := IniRead(ini, "latest", "tag", A_Space)
		err := IniRead(ini, "latest", "err", A_Space)
		state := V1Obj({latest: Trim(latest), err: Trim(err), newer: Trim(latest) != "" && VersionCompare(Trim(latest), BotVersion()) > 0})
		}
	return state
	}

;A pixel distance measured at UI scale 1 (a 1920x1080 window, UI Size Small), at the UI size in use
Px(n)
	{
	return Round(n * UiScale)
	}

;Full path of a picture (e.g. "storm\hit1.png") in the picture set for the UI size in use; the main
;one if that set has no picture of its own for it (logged once)
PicPath(rel)
	{
	static missing := V1Obj()
	if (PicDir != A_WorkingDir)
		{
		;(a made set: the picture made at its size, see PicMake)
		p := PicSets[PicSet].gen ? PicMake(rel, PicSets[PicSet]) : PicDir "\" rel
		if (p != "" && FileExist(p))
			return p
		;A cut set without this picture: one made at its size from the other sets
		if (!PicSets[PicSet].gen)
			{
			p := PicMake(rel, V1Obj({dir: GenRoot "\ui" Round(UiScale, 3), scale: UiScale}))
			if (p != "" && FileExist(p))
				return p
			}
		if (!missing.Has(PicDir "|" rel))
			{
			missing[PicDir "|" rel] := 1
			DebugLog("  (no " rel " at UI size " Round(UiScale, 3) " and none to make it from - using the main picture, which won't match at this size)")
			}
		}
	return A_WorkingDir "\" rel
	}

;Switches to picture set i and sizes the search areas to its UI scale; why: what chose it (the log - every switch says
;why since 2026-10-25, when one at 23:14:47 didn't)
UsePicSet(i, why := "")
	{
	static upsUsed := 0
	global PicSet, PicDir, UiScale, HandHalf, HalfPitch ; (v1 globals it sets)
	upsWas := upsUsed ? PicSet : "", upsUsed := 1
	PicSet := i, PicDir := PicSets[i].dir, UiScale := PicSets[i].scale
	HandHalf := Px(400), HalfPitch := Px(41)
	DebugLog("Pictures: " (i = 1 ? "main set (UI scale 1)" : SubStr(PicDir, (StrLen(A_WorkingDir) + 2)<1 ? (StrLen(A_WorkingDir) + 2)-1 : (StrLen(A_WorkingDir) + 2)) " (UI scale " Round(UiScale, 3) (PicSets[i].gen ? (PicSets[i].copy ? ", the cut set's copy made 1:1" : ", made from the cut pictures") : "") ")") " - card area +-" HandHalf " px, card spacing " 2 * HalfPitch " px"
		. (why != "" ? " - " why : "") (upsWas != "" && upsWas != i ? " (was " PicSetName(upsWas) ")" : ""))
	}

;Finds the Wizard101 client area on screen so searches follow the window when it's moved or resized
UpdateGameRect()
	{
	global GameLeft, GameTop, GameW, GameH, GameRight, GameBottom, ScreenX, ScreenY ; (v1 globals it sets)
	;(v1: no such window - blank; v2 throws)
	hwnd := V1Try(WinGetID, "A")
	proc := V1Try(WinGetProcessName, "ahk_id " hwnd)
	cls := V1Try(WinGetClass, "ahk_id " hwnd)
	if (proc != GameExe) || (cls != GameClass)
		{
		;Active window isn't the game (e.g. one of our popups, or the game's short-lived D3DProxyWindow),
		;use the top-most real Wizard101 window instead
		gameHwnd := V1Try(WinGetID, "ahk_class " GameClass " ahk_exe " GameExe)
		if (!gameHwnd)
			{
			;Game not open: keep the last known position rather than measuring some other window
			return
			}
		hwnd := gameHwnd
		}
	if (!hwnd)
		{
		return
		}
	rect := Buffer(16, 0)
	pt := Buffer(8, 0)
	DllCall("GetClientRect", "Ptr", hwnd, "Ptr", rect.Ptr)
	DllCall("ClientToScreen", "Ptr", hwnd, "Ptr", pt.Ptr)
	w := NumGet(rect, 8, "Int")
	h := NumGet(rect, 12, "Int")
	if (w <= 0 || h <= 0)
		{
		;Minimized, keep the last known position
		return
		}
	GameLeft := NumGet(pt, 0, "Int")
	GameTop := NumGet(pt, 4, "Int")
	GameW := w
	GameH := h
	GameRight := GameLeft + w
	GameBottom := GameTop + h
	ScreenX := GameLeft + w // 2
	ScreenY := GameTop + h // 2
	}

TestSchool(class)
	{
	global schoolX, schoolY, school ; (v1 globals it sets)
	V1ImageSearch(&schoolX, &schoolY, V1Sub(playerX, Px(100)), V1Sub(playerY, Px(100)), V1Add(playerX, Px(250)), V1Add(playerY, Px(250)), PicOpt(class "\" class ".png"))
	if (Errorlevel = 0)
		{
		school := class
		return true
		} else {
			return false
			}
	}
	
Tri(type1, type2) 
	{
	global
	;(v2: the names %type2%2X / %type2%type make, and the card variables &%bladetype% / &%traptype% name - UseBlade,
	;UseTrap - must exist: v1 made them by their names; PlanGroups' groups are elemental and spirit)
	global blade2X, blade2Y, trap2X, trap2Y, elementalblade, spiritblade, elementaltrap, spirittrap
	visionHit := VisionFind("resources", type1 type2, &typeX, &typeY)
	if (visionHit = -1)
		{
		V1ImageSearch(&typeX, &typeY, ScreenX - HandHalf, ScreenY - Px(75), ScreenX + HandHalf, ScreenY + Px(75), PicOpt("resources\" type1 type2 ".png", CardTol))
		visionHit := (ErrorLevel = 0)
		}
	if (visionHit = 1)
		{
		%type2%2X := typeX
		%type2%2Y := typeY
		;(the blade found names the blade kind, the trap found the trap kind - each by itself: an Elemental Blade in hand no
		;longer stands for an Elemental Trap)
		%type2%type := type1 type2
		;(the card variable that names - blank till UseBlade / UseTrap set it, as v1's)
		if (!IsSet(%type1 type2%))
			%type1 type2% := ""
		return true
		} else 
			{
			return false
			}
	}

ErrorBox(&funcN, &dir, &title)
	{
	;(v1: Log, Join and the Command* checks pass a dir and title nothing set - blank)
	if (!IsSet(dir))
		dir := ""
	if (!IsSet(title))
		title := ""
	if (devmode == 1)
		{
		n1 := "Error in " . funcN . " Function"
		n2 := "Directory: " PicPath(dir "\" title ".png")
		msgResult := MsgBox(n2 "`n`nWould You like to continue running script?", n1, "4 T5")
		if (msgResult = "Yes")
			{
			return
			}
		if (msgResult = "No")
			{
			ExitApp()
			}
		if (msgResult = "Timeout")
			{
			return
			}
		}
	}
	
Find(title, &card, &X, &Y, &dir)
	{
	global
	local _funcn ; (v1 passed these literals as temporaries: locals here, not globals)
	local fdEnch := 0
	;(v1.0.0, memclicks:1: where the game's memory has the card, first - only once its boxes have been seen lining up with
	;the screen's at this window size, KillCalc.ahk MemCardFind; noted in FoundByMem, so the re-finds by its picture are
	;skipped - and "dir\title|ench" 1 when that copy carries an enchantment already (a plain copy's taken first: UseBlade /
	;UseTrap don't Sharpen / Potent it again, UseHit puts no enchant on it - the game takes no second one). memclicks:0, or
	;the memory can't tell: by its picture as ever)
	if (IsObject(FoundByMem))
		FoundByMem.Delete(dir "\" title), FoundByMem.Delete(dir "\" title "|ench")
	if (MemCardFind(dir, title, &X, &Y, &fdEnch))
		{
		card := 1
		if (IsObject(FoundByMem))
			FoundByMem[dir "\" title] := 1, FoundByMem[dir "\" title "|ench"] := fdEnch ? 1 : 0
		return
		}
	;(the vision helper, if it's running: 1 found, 0 not in hand)
	visionHit := VisionFind(dir, title, &X, &Y)
	if (visionHit >= 0)
		{
		card := visionHit
		;(v1: X, Y as they were - not set yet: blank)
		if (!IsSet(X))
			X := ""
		if (!IsSet(Y))
			Y := ""
		return
		}
	V1ImageSearch(&X, &Y, ScreenX - HandHalf, ScreenY - Px(75), ScreenX + HandHalf, ScreenY + Px(150), PicOpt(dir "\" title ".png", CardTol))
	if (Errorlevel == 0)	
		{
		card := 1
		} else if (Errorlevel == 1)
			{
			card := 0
			} else if (Errorlevel == 2)
				{
				ErrorBox(&_funcn := "Find", &dir, &title)
				}
	}
	
FindAndClick(&title, &click, &dir) ; (v1: Click - renamed: a v2 script function named Click would take over every file's mouse clicks)
	{
	global
	Find(title, &click, &clickX, &clickY, &dir)
	DebugLog("  Click " title ": found=" click " at " V1Sub(clickX, GameLeft) "," V1Sub(clickY, GameTop))  ; (v1: A_ThisFunc - the function was Click)
	if (click == 1)
		{
		ClickAt(clickX + Px(5), clickY + Px(5), 100)
		return true
		} else 
			{
			return false
			}
	}
	
;Your school's bubble (<school>\bubble - a global, all of the battle; the battle chain casts it before a hit, usebubble):
;by its picture (Click), or - no picture found it, or the picture may be on another global (KillCalc.ahk BubbleMem:
;BoostMemOnly["<school>/bubble"]) - at the game's card's box, only while the hand's boxes and the game's cards line up for
;sure (KillCalc.ahk BoostMemBox, as UseMemAt casts a Tower Shield); not sure: the picture's spot as before, unless there's
;none or the global already up may be under it (BubbleUpHeld). A global has no target: the card alone is clicked. The
;global it put up is noted (BubbleUp - the game's name: the same one isn't cast again this battle; the slot's learned card
;up already: its picture not clicked, the game's hand read or not). True if clicked; false: nothing was (the chain goes on
;to the next card)
ClickBubble()
	{
	global
	local _title ; (v1 passed these literals as temporaries: locals here, not globals)
	local cbKey, cbAt, cbName, cbSlot
	cbKey := BoostKey("bubble", hitschool)
	if (IsObject(BoostMemOnly) && BoostMemOnly.Has(cbKey))
		{
		cbAt := BoostMemBox(cbKey, 0, "", "")
		if (cbAt.x != "")
			{
			DebugLog("  " cbKey ": " (bubbleX != "" ? "its picture found a global, the game has another in hand too" : "no picture found it") " - the game's " cbAt.name " is card " cbAt.n " of " cbAt.of " in hand: cast at its box " cbAt.x - GameLeft "," cbAt.y - GameTop cbAt.note)
			ClickAt(cbAt.x, cbAt.y, 100)
			bubble := 1, BubbleUp := cbAt.name
			return true
			}
		if (bubbleX = "" || BubbleUpHeld())
			{
			DebugLog("  " cbKey ": in hand (the game), not cast: " cbAt.why (bubbleX != "" ? " - the global up already may be under its picture" : ""))
			bubble := 0
			return false
			}
		DebugLog("  " cbKey ": in hand (the game), its box not sure (" cbAt.why ") - its picture's spot")
		}
	;(the slot's picture is its learned card's own: that card the global the bot put up this battle - not cast again,
	;whether or not the game's hand is read this look: the hand still changing after a discard, the helper restarting...)
	cbSlot := BubbleSlotName(hitschool)
	if (BubbleUp != "" && cbSlot = BubbleUp)
		{
		if (IsObject(BoostSaid) && !BoostSaid.Has("up|" BubbleUp))
			BoostSaid["up|" BubbleUp] := 1, DebugLog("  " cbKey ": its picture is " cbSlot "'s, the global the bot put up this battle - not cast again")
		bubble := 0
		return false
		}
	;(the game's name of the global the picture is on - the one every global in hand has, else the slot's learned card's
	;(KillCalc.ahk BubbleHandName) - before the hand changes; not known: the global known up stays known, never blanked)
	cbName := BubbleHandName()
	if (!FindAndClick(&_title := "bubble", &bubble, &hitschool))
		return false
	if (cbName != "")
		BubbleUp := cbName
	return true
	}

;TODO (TODO.md goal 3, needs the game): Pass, Flee (Flee.ahk FleeWord, FleeConfirm), Draw (Draw.ahk DrawWord, DrawLit)
;through the game's windows (Vision.ahk NavGui - QuickSell.ahk QsPx / QsTargetOk's checks: shown, once, inside the root,
;not greyed; the flee box by NavGui's message box) once their window names are known - python bagmem.py --tree --under
;CombatPlanningPhaseWindow in a battle; the pictures and OCR stay as the fallback
;Pass: its picture in the hand's area (resources\pass.png - Click), else the round's Pass button where the round start
;finds it (PassButtonAt: resources\roundstart.png, or drawn hovered with the mouse on it) - clicked in its middle. A made
;pass.png can miss when roundstart.png matches (2026-10-25 at UI 1.130: made from the 1.265 cut, it missed 9 times running,
;the round start's Pass found each time at 984,829 - nothing cast, the same planning phase played again every 3 s till the
;timer ended it). True if clicked
ClickPass()
	{
	global
	local _title, _dir ; (v1 passed these literals as temporaries: locals here, not globals)
	local cpX, cpY
	if (FindAndClick(&_title := "pass", &pass, &_dir := "resources"))
		return true
	if (PassButtonAt(&cpX, &cpY) != 0)
		return false
	DebugLog("  Click pass: found=1 at " cpX - GameLeft "," cpY - GameTop " - the round's Pass button" (PassHover ? ", drawn hovered" : "") ", as the round start finds it (pass.png missed it)")
	;(the button's middle: the Pass picture is 64 x 26 at UI 1 - 81 x 33 cut at 1.265)
	ClickAt(cpX + Px(32), cpY + Px(13), 100)
	pass := 1
	return true
	}

UseOnSelf(&title, &card, &dir) 
	{
	global
	Find(title, &card, &foundX, &foundY, &dir)
	DebugLog("  " A_ThisFunc " " title ": found=" card " at " V1Sub(foundX, GameLeft) "," V1Sub(foundY, GameTop))
	;(no picture found it, the game's hand has it - Tower Shield: at its card box - UseMemAt)
	UseMemAt(title, dir, &card, &foundX, &foundY)

	;(v1.0.0: your plate not found this round - playerX, playerY blank: its target click would land wherever the mouse is,
	;on the card just clicked - not cast)
	if (card == 1 && (playerX = "" || playerY = ""))
		{
		DebugLog("  " title ": your name plate wasn't found this round - not cast (nowhere to click it onto)")
		return false
		}
	if (card == 1)
		{
		ClickAt(foundX, foundY, 150)
		ClickAt(playerX, playerY, 150)
		}
	;(true if the card was in hand - clicked - as UseOnHammer: the solo filler goes on to Reshuffle when it wasn't)
	return card == 1
	}

;The card, then the hitter's plate (hammerX, hammerY) - or tx, ty (a party battle's ally). True if the card was in hand
UseOnHammer(&title, &card, &dir, tx := "", ty := "")
	{
	global
	Find(title, &card, &foundX, &foundY, &dir)
	DebugLog("  " A_ThisFunc " " title ": found=" card " at " V1Sub(foundX, GameLeft) "," V1Sub(foundY, GameTop))
	;(no picture found it, the game's hand has it: at its card box - UseMemAt)
	UseMemAt(title, dir, &card, &foundX, &foundY)

	;(v1.0.0 review: the hitter's plate not found this round - hammerX, hammerY blank (RoundStart: your school known from the
	;game's memory or characters.txt, your plate not found): not cast - its click would land wherever the mouse is)
	if (card == 1 && tx = "" && (hammerX = "" || hammerY = ""))
		{
		DebugLog("  " title ": the hitter's name plate wasn't found this round - not cast (nowhere to click it onto)")
		return false
		}
	if (card == 1)
		{
		ClickAt(foundX, foundY, 150)
		ClickAt(tx != "" ? tx : hammerX, ty != "" ? ty : hammerY, 150)
		}
	return card == 1
	}

;A card dir\title no picture found that the game's hand has (KillCalc.ahk BoostSearch's BoostMemOnly - Tower Shield:
;TowerMem): card 1 and x, y its card box's middle - a fresh look at the hand's boxes laid on the game's cards, only while
;they line up for sure (KillCalc.ahk BoostMemBox, as UseBlade / UseTrap cast a blade or trap no picture found). Found by its
;picture while the game's hand has a Tower Shield and another shield the picture may be on (TowerMem): its card box the
;same way, else the picture's spot as found. False, nothing set: not one the game's hand found, or the boxes and the game's
;cards not lining up for sure
UseMemAt(title, dir, &card, &x, &y)
	{
	global BoostMemOnly, GameLeft, GameTop
	umaKey := BoostKey(title, dir)
	if (!IsObject(BoostMemOnly) || !BoostMemOnly.Has(umaKey))
		return false
	umaAt := BoostMemBox(umaKey, 0, "", "")
	if (umaAt.x = "")
		{
		DebugLog("  " umaKey ": in hand (the game), " (card == 1 ? "found by its picture - another shield's too? - its box not sure, the picture's spot: " : "no picture found it - not cast: ") umaAt.why)
		return false
		}
	umaPic := (card == 1)
	card := 1, x := umaAt.x, y := umaAt.y
	DebugLog("  " umaKey ": " (umaPic ? "its picture found a shield, the game has another shield in hand too" : "no picture found it") " - the game's " umaAt.name " is card " umaAt.n " of " umaAt.of " in hand: cast at its box " x - GameLeft "," y - GameTop umaAt.note)
	return true
	}

;The solo filler's absorb (the battle chain, when no Tower Shield went - 2026-10-26): one that costs no pips (AbsorbFreeOk -
;an X-pip or 3-pip one would spend what the next hit needs), on you - by its picture, else at its card box (UseOnSelf /
;UseMemAt with AbsorbOnlyFree: only such a card's box). With usetower and useabsorb (KillCalc.ahk AbsorbOn). True if clicked
AbsorbFiller()
	{
	global absorb, AbsorbFreeOk, AbsorbOnlyFree
	if (absorb != 1 || !AbsorbFreeOk || !AbsorbOn())
		return false
	AbsorbOnlyFree := 1
	afGo := UseOnSelf(&_title := "absorb", &absorb, &_dir := "resources")
	AbsorbOnlyFree := 0
	return afGo
	}

;The battle chain's negative aura (KillCalc.ahk NegAuraMem - an Attenuate: +N% damage taken for 4 rounds): one that adds to
;the planned hit's schools (NegAuraMatches) at its card box - only while the hand's boxes and the game's cards line up for
;sure (BoostMemBox) -, then the trap rule's enemy (NegAuraWhere: the Alt+1 boss, else the one with the most health) - not
;one it went on in the last 4 rounds (NegAuraOn - the enemy by the game's memory's participant, else its most health, else
;its plate's place: KillCalc.ahk NegAuraKey, NegAuraWhen, NegAuraNote). Never by a picture (it has no slot). True if cast;
;false: nothing clicked, the chain goes on (said once a battle why)
UseNegAura()
	{
	global negaura, roundnumber, GameLeft, GameTop, BoostSaid
	if (negaura != 1 || !Stat("usetraps"))
		return false
	unHand := V1IsFunc("VisionCards") ? VisionCards.Call(300, 5000) : ""
	if (!IsObject(unHand) || !NegAuraMatches(unHand.cards).Length)
		{
		if (IsObject(BoostSaid) && !BoostSaid.Has("negaura|nofit"))
			BoostSaid["negaura|nofit"] := 1, DebugLog("  negaura: none in hand adds to the planned hit's schools - not cast")
		return false
		}
	if (!NegAuraWhere(&unX, &unY, &unKey, &unWho))
		{
		DebugLog("  negaura: no enemy's plate found to put it on - not cast")
		return false
		}
	unWhen := NegAuraWhen(unKey)
	if (unWhen != "" && V1Lt(V1Sub(roundnumber, unWhen), 4))  ; (v1: a blank round - dual mode - counted as within 4)
		{
		DebugLog("  negaura: " unWho " has one from round " unWhen " (4 rounds) - not cast again yet")
		return false
		}
	unAt := BoostMemBox("negaura", 0, "", "")
	if (unAt.x = "")
		{
		DebugLog("  negaura: in hand (the game), not cast: " unAt.why)
		return false
		}
	DebugLog("  negaura: the game's " unAt.name " is card " unAt.n " of " unAt.of " in hand: cast at its box " unAt.x - GameLeft "," unAt.y - GameTop " on " unWho " (" unX - GameLeft "," unY - GameTop ")" unAt.note)
	ClickAt(unAt.x, unAt.y, 150)
	ClickAt(unX, unY, 200)
	NegAuraNote(unKey, roundnumber), negaura := 0
	return true
	}

UseBlade(&title, &blade, &Use1, &Use2, &dir)
	{
	global
	local _dir, _funcn ; (v1 passed these literals as temporaries: locals here, not globals)
	local ubKey, ubCp, ubSrc, ubItem, ubGo1, ubGo2, ubMoved, ubMem, ubAt, ubEnch, ubFm
	Find(title, &blade, &foundX, &foundY, &dir)
	DebugLog("  " A_ThisFunc " " title ": found=" blade " at " V1Sub(foundX, GameLeft) "," V1Sub(foundY, GameTop))
	;(found where the game's memory has it - memclicks, Find: no picture re-find, its slide after a Sharpen by the memory)
	ubFm := V1At(FoundByMem, dir "\" title) = 1
	;(v1.0.0 review: the hitter's plate not found this round - hammerX, hammerY blank (RoundStart: your school known from the
	;game's memory or characters.txt, your plate not found): not cast - its click onto the hitter would land wherever the
	;mouse is, and it'd be counted on the hitter. blade4 is clicked onto no plate)
	if (title != "blade4" && (hammerX = "" || hammerY = ""))
		{
		DebugLog("  " title ": the hitter's name plate wasn't found this round - not cast (nowhere to click it onto)")
		return false
		}

	;The hand may have re-centred since FindCards (a discard or a used enchant)
	Find("sharpen", &sharpen, &SharpX, &SharpY, &_dir := "resources")
	;(the game's hand read this look - KillCalc.ahk BoostSearch: which copy of the card this is. A pet's or gear's - an item
	;card - is never sharpened: it can't be enchanted. A treasure or item card's copy stacks with the deck's - the user,
	;2026-10-24 - so it goes once a battle besides the deck's casts; a copy that can't go swapped for one that can)
	ubKey := BoostKey(title, dir), ubSrc := "", ubItem := 0, ubMoved := 0, ubMem := 0, ubEnch := 0
	;(v1.0.0 review: found where the game's memory has it on a copy that carries an enchantment already - Find's MemCardFor
	;takes a plain copy first, this one only when there's none: never sharpened again - the game takes no second one, and
	;the blade was logged sharpened on the hitter -, cast as it is, counted with the Sharpen it carries, as BoostMemBox's)
	if (ubFm && V1At(FoundByMem, dir "\" title "|ench") = 1)
		ubEnch := 1
	;(no picture found it but the game's hand has it - BoostSearch's BoostMemOnly: cast at its card box, a fresh look at the
	;hand's boxes laid on the game's cards - only while they line up for sure; that copy's own kind - KillCalc.ahk BoostMemBox)
	if (blade != 1 && IsObject(BoostMemOnly) && BoostMemOnly.Has(ubKey))
		{
		ubAt := BoostMemBox(ubKey, sharpen == 1, Use1, Use2)
		if (ubAt.x = "")
			{
			DebugLog("  " ubKey ": in hand (the game), no picture found it - not cast: " ubAt.why)
			BoostOneOfBack("blade")
			return UseHeldBack("blade", title)
			}
		blade := 1, foundX := ubAt.x, foundY := ubAt.y, ubSrc := ubAt.src, ubItem := ubAt.item, ubMem := 1, ubEnch := ubAt.ench ? 1 : 0
		DebugLog("  " ubKey ": no picture found it - the game's " ubAt.name " is card " ubAt.n " of " ubAt.of " in hand: cast at its box " foundX - GameLeft "," foundY - GameTop ubAt.note)
		}
	else if (blade == 1 && IsObject(BoostHand) && BoostHand.Has(ubKey))
		{
		ubCp := BoostCopyPick(ubKey, &foundX, &foundY, sharpen == 1 || ubEnch, Use1, Use2)
		if (!IsObject(ubCp))
			{
			DebugLog("  " ubKey ": no copy in hand can be cast now (each one's casts used this battle, or one would need a Sharpen it can't get)")
			;(the blades held back this round for it go on instead - KillCalc.ahk BoostOneOf: the chain's next one; one before
			;it in the chain, which has passed it already, right here - UseHeldBack)
			BoostOneOfBack("blade")
			return UseHeldBack("blade", title)
			}
		ubSrc := ubCp.src, ubItem := ubCp.item, ubMoved := ubCp.moved
		;(another copy moved to: cast plain, as ever)
		if (ubMoved)
			ubEnch := 0
		}
	ubGo1 := (ubSrc = "") ? (Use1 != 1) : !BoostSrcUsed.Has(ubKey "@" ubSrc)
	ubGo2 := (ubSrc = "") ? (Use2 != 1) : ubGo1
	;(a copy that carries an enchantment already - only the game's hand finds one, KillCalc.ahk BoostMemBox: a plain copy
	;first - is never sharpened again: cast as it is, counted with the Sharpen it carries)
	if (sharpen == 1) && (blade == 1) && ubGo1 && !ubItem && !ubMoved && !ubEnch
		{
		boostX := SharpX
		ClickAt(SharpX, SharpY, 150)
		ClickAt(foundX, foundY, 150)
		CenterMouse()
		n := PicPath(dir "\" title ".png")
		;The boost card left the hand and the hand re-centres, so the card moves: go as soon as it has (one cast by the game's
		;hand: where the game's hand has it then - no picture finds it; one found where the memory has it: there again)
		if (ubMem)
			BoostSettleMem(ubKey, &foundX, &foundY, boostX)
		else if (ubFm)
			MemSettle(dir, title, &foundX, &foundY, boostX)
		else
			BoostSettle(n, &foundX, &foundY, boostX)
		if ((Errorlevel == 2) && (devmode == 1))
			{
			ErrorBox(&_funcn := "UseBlade", &dir, &title)
			}
			ClickAt(foundX, foundY, 150)
		if (title != "blade4")
			{
			ClickAt(hammerX, hammerY, 200)
			}
		boosts++
		if (ubSrc = "")
			Use1 := 1
		else
			BoostSrcUsed[ubKey "@" ubSrc] := 1
		if BladeOnUs(title)
			{
			AddBoost(AppliedBlades, ubKey, Stat("sharpen"), ubSrc)
			}
		;(cast on you but not seen there - your plate or badge not read this round: noted, so reboost:1 casts it again after
		;a hit it fits - KillCalc.ahk ConsumeBoosts; not Alt+2's pick's or a party support's: those went on another wizard)
		else if (Manual != 1 && !PartySupport())
			BoostUnrec.Push(ubKey (ubSrc != "" ? "@" ubSrc : "") "+")
		return true
		} else if (blade == 1) && (ubGo2 || (ubEnch && ubGo1))
			{
			n := PicPath(dir "\" title ".png")
			;If the card can't be found again, click where it was (not when it's another copy's box: BoostCopyPick; nor one
			;cast by the game's hand - its box: no picture finds it, and one that doesn't fit might match elsewhere)
			keepX := foundX, keepY := foundY
			if (!ubMoved && !ubMem && !ubFm)
				V1ImageSearch(&foundX, &foundY, GameLeft, GameTop, GameRight, GameBottom, PicOptFile(n, CardTol))
			if (ErrorLevel || ubMoved || ubMem || ubFm)
				foundX := keepX, foundY := keepY
			if ((Errorlevel == 2) && (devmode == 1))
				{
				ErrorBox(&_funcn := "UseBlade", &dir, &title)
				}
				ClickAt(foundX, foundY, 150)
			if (title != "blade4")
				{
				ClickAt(hammerX, hammerY, 200)
				}
			boosts++
			;(an enchanted copy takes the sharpened cast's flag while it's free)
			if (ubSrc != "")
				BoostSrcUsed[ubKey "@" ubSrc] := 1
			else if (ubEnch && Use1 != 1)
				Use1 := 1
			else
				Use2 := 1
			if BladeOnUs(title)
				{
				AddBoost(AppliedBlades, ubKey, ubEnch ? Stat("sharpen") : 0, ubSrc)
				}
			;(cast on you but not seen there: noted, as above)
			else if (Manual != 1 && !PartySupport())
				BoostUnrec.Push(ubKey (ubSrc != "" ? "@" ubSrc : "") (ubEnch ? "+" : ""))
			return true
			} else
				{
				return false
				}
	}

UseTrap(&title, &trap, &Use1, &Use2, &dir)
	{
	global
	local _dir, _funcn ; (v1 passed these literals as temporaries: locals here, not globals)
	local utKey, utCp, utSrc, utItem, utGo1, utGo2, utMoved, utMem, utAt, utEnch, utFm
	Find(title, &trap, &foundX, &foundY, &dir)
	DebugLog("  " A_ThisFunc " " title ": found=" trap " at " V1Sub(foundX, GameLeft) "," V1Sub(foundY, GameTop))
	;(found where the game's memory has it - memclicks, Find: as UseBlade's)
	utFm := V1At(FoundByMem, dir "\" title) = 1

	;The hand may have re-centred since FindCards (a discard or a used enchant)
	Find("potent", &potent, &PotentX, &PotentY, &_dir := "resources")
	;(which copy of the card this is, as UseBlade: an item card's never made potent; a treasure or item card's goes once a
	;battle besides the deck's)
	utKey := BoostKey(title, dir), utSrc := "", utItem := 0, utMoved := 0, utMem := 0, utEnch := 0
	;(v1.0.0 review: found where the game's memory has it on a copy already potent - as UseBlade's: cast as it is, counted
	;potent, never made potent again)
	if (utFm && V1At(FoundByMem, dir "\" title "|ench") = 1)
		utEnch := 1
	;(no picture found it but the game's hand has it: cast at its card box, as UseBlade's)
	if (TrapOn == 1 && trap != 1 && IsObject(BoostMemOnly) && BoostMemOnly.Has(utKey))
		{
		utAt := BoostMemBox(utKey, potent == 1, Use1, Use2)
		if (utAt.x = "")
			{
			DebugLog("  " utKey ": in hand (the game), no picture found it - not cast: " utAt.why)
			if (utKey != "feint" && utKey != "trap4")
				{
				BoostOneOfBack("trap")
				return UseHeldBack("trap", title)
				}
			return false
			}
		trap := 1, foundX := utAt.x, foundY := utAt.y, utSrc := utAt.src, utItem := utAt.item, utMem := 1, utEnch := utAt.ench ? 1 : 0
		DebugLog("  " utKey ": no picture found it - the game's " utAt.name " is card " utAt.n " of " utAt.of " in hand: cast at its box " foundX - GameLeft "," foundY - GameTop utAt.note)
		}
	else if (TrapOn == 1 && trap == 1 && IsObject(BoostHand) && BoostHand.Has(utKey))
		{
		utCp := BoostCopyPick(utKey, &foundX, &foundY, potent == 1 || utEnch, Use1, Use2)
		if (!IsObject(utCp))
			{
			DebugLog("  " utKey ": no copy in hand can be cast now (each one's casts used this battle, or one would need a Potent it can't get)")
			;(the traps held back this round for it go on instead - KillCalc.ahk BoostOneOf; not for a Feint or trap4: they
			;aren't among those it picks from, so nothing was held back for them; one before it in the chain right here -
			;UseHeldBack)
			if (utKey != "feint" && utKey != "trap4")
				{
				BoostOneOfBack("trap")
				return UseHeldBack("trap", title)
				}
			return false
			}
		utSrc := utCp.src, utItem := utCp.item, utMoved := utCp.moved
		;(another copy moved to: cast plain, as ever)
		if (utMoved)
			utEnch := 0
		}
	utGo1 := (utSrc = "") ? (Use1 != 1) : !BoostSrcUsed.Has(utKey "@" utSrc)
	utGo2 := (utSrc = "") ? (Use2 != 1) : utGo1
	;(a copy already potent - the game's hand finds one: cast as it is, counted potent - as UseBlade's)
	if (TrapOn == 1) && (potent == 1) && (trap == 1) && utGo1 && !utItem && !utMoved && !utEnch
		{
		boostX := PotentX
		ClickAt(potentX, potentY, 150)
		ClickAt(foundX, foundY, 150)
		CenterMouse()
		n := PicPath(dir "\" title ".png")
		;The boost card left the hand and the hand re-centres, so the card moves: go as soon as it has (by the game's hand for
		;one cast so)
		if (utMem)
			BoostSettleMem(utKey, &foundX, &foundY, boostX)
		else if (utFm)
			MemSettle(dir, title, &foundX, &foundY, boostX)
		else
			BoostSettle(n, &foundX, &foundY, boostX)
		if ((Errorlevel == 2) && (devmode == 1))
			{
			ErrorBox(&_funcn := "UseTrap", &dir, &title)
			}
		ClickAt(foundX, foundY, 150)
		ClickAt(TrapAtX, TrapAtY, 200)
		boosts++
		if (utSrc = "")
			Use1 := 1
		else
			BoostSrcUsed[utKey "@" utSrc] := 1
		;(the kill check counts them on the enemy they went on - the boss's, the one with the most health: KillCalc.ahk
		;TrapPut; a party support's aren't)
		if (BossChoosen == 1 || TrapMine)
			TrapPut(utKey, Stat("potent"), utSrc)
		return true
		} else if (TrapOn == 1) && (trap == 1) && (utGo2 || (utEnch && utGo1))
			{
			n := PicPath(dir "\" title ".png")
			;If the card can't be found again, click where it was (not when it's another copy's box: BoostCopyPick, nor one
			;cast by the game's hand)
			keepX := foundX, keepY := foundY
			if (!utMoved && !utMem && !utFm)
				V1ImageSearch(&foundX, &foundY, GameLeft, GameTop, GameRight, GameBottom, PicOptFile(n, CardTol))
			if (ErrorLevel || utMoved || utMem || utFm)
				foundX := keepX, foundY := keepY
			if ((Errorlevel == 2) && (devmode == 1))
				{
				ErrorBox(&_funcn := "UseTrap", &dir, &title)
				}
			ClickAt(foundX, foundY, 150)
			ClickAt(TrapAtX, TrapAtY, 200)
			boosts++
			if (utSrc != "")
				BoostSrcUsed[utKey "@" utSrc] := 1
			else if (utEnch && Use1 != 1)
				Use1 := 1
			else
				Use2 := 1
			if (BossChoosen == 1 || TrapMine)
				TrapPut(utKey, utEnch ? Stat("potent") : 0, utSrc)
			return true
			} else 
				{
				return false
				}
	}

;The blades (kind "blade") or traps ("trap") BoostOneOf held back, set again by BoostOneOfBack because the one it kept
;(title) can't go after all: those before it in the battle chain (blade, blade2, blade3 / trap, trap2) the chain has
;passed already - tried here, in the chain's order; those after it the chain reaches itself. True if one was cast. (Its
;own function: inside UseBlade the name blade is the ByRef parameter; it can't loop - BoostOneOfBack empties its list)
UseHeldBack(kind, title)
	{
	global
	local _title, _dir ; (v1 passed these literals as temporaries: locals here, not globals)
	if (kind = "blade")
		{
		if (title != "blade" && blade == 1 && UseBlade(&_title := "blade", &blade, &used%BladeU1%, &used%BladeU2%, &BladeDir))
			return true
		if ((title = "blade3" || title = "blade4") && blade2 == 1 && UseBlade(&bladetype, &%bladetype%, &used%Blade2U1%, &used%Blade2U2%, &_dir := "resources"))
			return true
		if (title = "blade4" && blade3 == 1 && UseBlade(&_title := "blade3", &blade3, &used15, &used16, &_dir := "resources"))
			return true
		return false
		}
	if (title != "trap" && trap == 1 && UseTrap(&_title := "trap", &trap, &used%TrapU1%, &used%TrapU2%, &TrapDir))
		return true
	if (title = "trap3" && trap2 == 1 && UseTrap(&traptype, &%traptype%, &used%Trap2U1%, &used%Trap2U2%, &_dir := "resources"))
		return true
	return false
	}

;Your school's prism (<school>\convert) on the boss picked with Alt+1 (the chain asks NeedsConvert first: it's of your
;school): by its picture, else - no picture found it, the game's hand has it (KillCalc.ahk ConvertMem) - at its card box
;(UseMemAt); then the boss. True if clicked (before 2026-10-26 it clicked where the picture had been even when it wasn't
;found again, and gave nothing back - the chain went on to the next card). Noted as on the boss till a hit of yours goes
;out (ConvertOn: your hits counted now - KillCalc.ahk ConvertUp)
UseConvert(&title, &convert, &dir)
	{
	global
	CenterMouse()
	Find(title, &convert, &foundX, &foundY, &dir)
	DebugLog("  " A_ThisFunc " " title ": found=" convert " at " V1Sub(foundX, GameLeft) "," V1Sub(foundY, GameTop))
	UseMemAt(title, dir, &convert, &foundX, &foundY)
	if (convert != 1)
		return false
	ClickAt(foundX, foundY, 150)
	ClickAt(bossX, bossY, 200)
	ConvertOn := V1Obj({hits: PartyHits ? PartyHits : 0, round: roundnumber})
	return true
	}
	
UseHit(&title, &hit, &dir, useEnchant := 1)
	{
	global
	local _funcn ; (v1 passed these literals as temporaries: locals here, not globals)
	;Saving pips for a hit that ends the battle (PlanPips): no other hit spends them. The wand's card is free,
	;but it uses up blades, traps and an enchant: only when the saved hit kills without them, unenchanted
	if (PipSaveFor != "" && title != PipSaveFor && (title != "wand" || !PipSaveBare))
		{
		DebugLog("  " title ": not cast - saving pips for " PipSaveFor)
		return false
		}
	if (PipSaveFor != "" && title = "wand")
		useEnchant := 0
	;(never on an item card - the wand's own, a pet's or gear's: it can't be enchanted - the user, 2026-10-24; the game's
	;hand or the learned card says which is one - KillCalc.ahk HitHeads)
	if (useEnchant && (title = "wand" || HitHeads(title).item))
		useEnchant := 0
	Find(title, &hit, &foundX, &foundY, &dir)
	DebugLog("  " A_ThisFunc " " title ": found=" hit " at " V1Sub(foundX, GameLeft) "," V1Sub(foundY, GameTop))
	;(v1.0.0 review: found where the game's memory has it on a copy that carries an enchantment already - memclicks, Find
	;takes a plain copy first: no enchant clicked onto it, the game takes no second one; cast as it is)
	if (useEnchant && V1At(FoundByMem, dir "\" title "|ench") = 1)
		{
		useEnchant := 0
		DebugLog("  " title ": the game's memory has an enchantment on it already - cast as it is, no enchant put on it")
		}

	;Can you pay for it yet? If not, keep it for a later round (no click, no enchant used on it)
	if (hit == 1) && !Affordable(title)
		{
		DebugLog("  " title " costs more pips than you have (" PipsNow "): keeping it for later")
		hit := 0
		return false
		}
	;The hand may have re-centred since FindCards (a discard or a used enchant)
	if (useEnchant)
		FindEnchant()
	if (useEnchant) && (enchant >= 1) && (hit == 1) && !EnchantedHits[title]
		{
		EnchantedHits[title] := enchant
		boostX := enchantX
		ClickAt(enchantX, enchantY, 150)
		ClickAt(foundX, foundY, 150)
		CenterMouse()	
		n := PicPath(dir "\" title ".png")
		;The boost card left the hand and the hand re-centres, so the card moves: go as soon as it has (found where the
		;game's memory has it - memclicks, Find: there again)
		if (V1At(FoundByMem, dir "\" title) = 1)
			MemSettle(dir, title, &foundX, &foundY, boostX)
		else
			BoostSettle(n, &foundX, &foundY, boostX)
		;The enchant card is used up and the hand has shifted
		FindEnchant()
		if ((Errorlevel == 2) && (devmode == 1))
			{
			ErrorBox(&_funcn := "UseHit", &dir, &title)
			}
		ClickAt(foundX, foundY)
		HitTarget(title, dir, 0, HitDamage(title, false, BossChoosen == 1))
		return CastResult(title, &hit, dir, 1)
		} else if (hit == 1)
			{
			n := PicPath(dir "\" title ".png")
			;If the card can't be found again, click where it was (found where the game's memory has it - memclicks: not
			;looked for by its picture)
			keepX := foundX, keepY := foundY
			if (V1At(FoundByMem, dir "\" title) != 1)
				V1ImageSearch(&foundX, &foundY, GameLeft, GameTop, GameRight, GameBottom, PicOptFile(n, CardTol))
			if (ErrorLevel || V1At(FoundByMem, dir "\" title) = 1)
				foundX := keepX, foundY := keepY
			if ((Errorlevel == 2) && (devmode == 1))
				{
				ErrorBox(&_funcn := "UseHit", &dir, &title)
				}
			ClickAt(foundX, foundY)
			HitTarget(title, dir, 0, HitDamage(title, false, BossChoosen == 1))
			return CastResult(title, &hit, dir, 0)
			} else
				{
				return false
				}
	}	
	
;A name plate's health - the red cur/max under its name (nx, ny: where the name starts) - read by the helper by its
;digits' shape (VisionPlate: 3 votes, 2 when a glyph's only fairly like its picture), else by OCR at four sizes, what at
;least two of them agree on: {cur, max, votes} ("" not read for sure). Yours (OwnHealthLow), an ally's (Party.ahk)
PlateHealth(nx, ny)
	{
	local x, y, w, h, t, a, key, n, best, bestN, zoom, gl, votes, phLines, phW, vp
	;(2026-10-23, 1440p: OCR read 2,848/3,153 at 1 of its 8 tries - none of the round's 4 reads of yours came out)
	;(the box ends above the pips - a Balance pip's red joins the digits: from ny + Px(50))
	;(v1: your plate not found - nx, ny blank: blank arithmetic, passed on)
	vp := VisionPlate(V1Sub(nx, Px(22)), V1Add(ny, Px(10)), V1Add(nx, Px(165)), V1Add(ny, Px(43)))
	if (IsObject(vp))
		return V1Obj({cur: vp.cur, max: vp.max, votes: V1Lt(vp.worst, 0.2) ? 3 : 2})
	;(110 wide first; not read: 150 - a four-figure health, 1,772/3,153, runs past 110 and its last figure is cut, never
	;read: 2026-10-23 - the wider box takes in more of what's round it, so it's only the second try)
	for each, phW in [110, 150]
		{
		x := V1Sub(nx, Px(8)), y := V1Add(ny, Px(20)), w := Px(phW), h := Px(24)
		;(its 3s, 5s and 8s told by their shape - the OCR reads 1,234 as 1,254: KillCalc.ahk HealthGlyphs)
		gl := HealthGlyphs(V1Sub(x, Px(20)), y, w + Px(40), h)
		;(the game's digits fool OCR now and then - B for 8, a 3 for an 8 - so it reads at four sizes and
		;takes what at least two of them read)
		votes := V1Obj(), best := "", bestN := 0
		for each2, zoom in [2, 3, 4, 5]
			{
			t := OcrRect(x, y, w, h, "en", zoom, &phLines, 1)
			if (ErrorLevel)
				continue
			t := StrReplace(StrReplace(StrReplace(StrReplace(StrReplace(StrReplace(t, "B", "8"), "O", "0"), "o", "0"), "S", "5"), "l", "1"), "I", "1")
			a := ParseHealth(HealthDigits(t, gl))
			if (!IsObject(a) || a.Length != 1)
				continue
			key := a[1].cur "/" a[1].max, n := votes.Has(key) ? votes[key] + 1 : 1, votes[key] := n
			if (n > bestN)
				best := a, bestN := n
			}
		if (bestN >= 2 && best[1].max > 0)
			return V1Obj({cur: best[1].cur, max: best[1].max, votes: bestN})
		}
	return ""
	}

;Your own health off your name plate (the red cur/max under your name), read by OCR at two sizes that
;must agree. True if it's under healat % (PlayerStats.txt, default 40). Logged each round it's read
;v1.0.0: the game's memory's first (OwnMemHealth - read for sure: counted as 3 reads); not read there, the plate as before
;quiet: only read (and logged) - not a heal's question (EnemySpells.ahk's look). Read once a round: a second ask in the same
;round (within 15 s) uses that reading (OwnHpCur, OwnHpMax, OwnHpVotes)
OwnHealthLow(quiet := false)
	{
	global
	local pct, limit, bestN, cur, most, r, ohlSrc := ""
	limit := StatOr("healat", 40)
	if (OwnHpCur != "" && OwnHpRound = roundnumber && V1Lt(V1Ago(OwnHpAt), 15000) && OwnHpWin = WinExist("A"))
		{
		cur := OwnHpCur, most := OwnHpMax, bestN := OwnHpVotes
		Goto("OwnHealthLowRead")
		}
	r := OwnMemHealth()
	if (!IsObject(r))
		r := PlateHealth(playerX, playerY)
	if (!IsObject(r))
		{
		DebugLog("  own health: couldn't read it for sure" (VisionPlateWhy != "" ? " (by shape: " SubStr(VisionPlateWhy, 1, 80) ")" : ""))
		return false
		}
	cur := r.cur, most := r.max, bestN := r.votes, ohlSrc := (V1At(r, "src") != "") ? " - " r.src : ""
	;(your most health, for the potions out of battle)
	PotionNoteMax(most)
	OwnHpCur := cur, OwnHpMax := most, OwnHpAt := A_TickCount, OwnHpVotes := bestN, OwnHpWin := WinExist("A")
OwnHealthLowRead:
	;(v1: blank or 0 health read - blank arithmetic, Round of it 0)
	pct := V1Round(V1Div(V1Mul(100, cur), most))
	;(for saving pips: not while your health is low)
	OwnHpPct := pct, OwnHpRound := roundnumber
	if (quiet)
		{
		DebugLog("  own health: " cur "/" most " (" pct "%)" ohlSrc)
		return pct < limit
		}
	;(healing on a misread wastes the card - e.g. 775 read as 75 by two sizes - so a low reading needs
	;three of the four sizes to agree)
	if (pct < limit && bestN < 3)
		{
		DebugLog("  own health: read " cur "/" most " only " bestN " times out of 4 - not sure enough to heal")
		return false
		}
	DebugLog("  own health: " cur "/" most " (" pct "%)" ohlSrc (pct < limit ? " - under " limit "%: healing" : ""))
	return pct < limit
	}

;Your health from the game's memory (OwnHealthLow's first try): VisionCards' me - the hand read this look (within 5 s: no
;new read; the round's first look reads it afresh - FindCards' VisionForget) - {cur, max, votes: 3 (read, not guessed: sure
;enough to heal on), src}; "" not read (navmem:0, the helper not running, not the planning phase...) or not plausible
OwnMemHealth()
	{
	;(only while one game window runs - Vision.ahk VisionMemOneClient: with two or more navmem can be on another client, and
	;VisionCards refuses its hand only when the badge read by your plate is another school; the plate as before)
	if (!V1IsFunc("VisionMemOneClient") || !VisionMemOneClient.Call())
		return ""
	omhHand := V1IsFunc("VisionCards") ? VisionCards.Call(300, 5000) : ""
	if (!IsObject(omhHand) || !IsObject(omhHand.me))
		return ""
	omhCur := omhHand.me.health, omhMax := omhHand.me.max
	if (omhCur = "" || omhMax = "" || omhMax <= 0 || omhCur < 0 || omhCur > omhMax)
		return ""
	return V1Obj({cur: omhCur, max: omhMax, votes: 3, src: "the game's memory"})
	}

;A healing card on yourself: the card, then your own name plate (a heal for one wizard asks who; one that
;heals only you or everyone doesn't, and the extra click does nothing). tx, ty: an ally's plate instead (a party
;battle's healer) - a heal that went out with the card's click, not asking who: one that heals all of you (its learned
;text says "all") kept as <school>.healNtarget:2, still used on an ally; one that heals only you :0, not used on an ally
;again (a heal slot learned afresh asks again: CardLearn.ahk). True if it was cast
UseHeal(title, &card, dir, tx := "", ty := "")
	{
	global
	local lc, allOf
	Find(title, &card, &foundX, &foundY, &dir)
	DebugLog("  " A_ThisFunc " " title ": found=" card " at " V1Sub(foundX, GameLeft) "," V1Sub(foundY, GameTop))
	if (card != 1)
		return false
	if !Affordable(title)
		{
		DebugLog("  " title " costs more pips than you have (" PipsNow ")")
		return false
		}
	;(v1.0.0: on you with your plate not found this round - its click would land wherever the mouse is: not cast)
	if (tx = "" && (playerX = "" || playerY = ""))
		{
		DebugLog("  " title ": your name plate wasn't found this round - not cast (nowhere to click it onto)")
		return false
		}
	ClickAt(foundX, foundY, 300)
	if (tx = "")
		ClickAt(playerX, playerY)
	else if (Stats[dir "." title "target"] = 2)
		DebugLog("  " title " heals all of you - the ally too")
	else if (!TargetPending())
		{
		;(Wizard101 gone to the tray - Settings: traygame: a hidden game shows no Pass button, so it reads as gone
		;out - nothing learned about who it heals)
		if (GameInTray)
			return false
		lc := V1IsFunc("LearnCardInSlot") ? LearnCardInSlot.Call(dir "\" title) : ""
		allOf := IsObject(lc) && RegExMatch(lc.text, "i)\ba[l1][l1]\b")
		StatsSet([[dir "." title "target", allOf ? 2 : 0]])
		DebugLog("  " title " went out without asking who - " (allOf ? "it heals all of you: still used on an ally (" dir "." title "target:2)" : "it heals only you: not used on an ally again (" dir "." title "target:0)"))
		}
	else
		{
		if (!Stats.Has(dir "." title "target"))
			StatsSet([[dir "." title "target", 1]])
		TargetClick(tx, ty)
		DebugLog("  " title ": the ally's plate clicked at " tx - GameLeft "," ty - GameTop)
		}
	;(a heal: the blades and traps out stay - the kill check still counts them)
	return CastResult(title, &card, dir, 0, false)
	}

;A hit that strikes one enemy (<school>.hitNtarget:1 in PlayerStats.txt, e.g. Scarab) waits for a target
;after its card is clicked: click the boss if one was picked (Alt+1), else the enemy with the least
;health, else the leftmost one (their nameplates along the top). All-enemy hits need nothing
;v1.0.0: also when the game's memory says the card in hand is for one enemy (KillCalc.ahk HitHeads' one - its kind damage,
;not aoe): before, a hit cut by hand with no target key clicked no enemy and the round ran out
HitTarget(title, dir, force := 0, dmg := "")
	{
	global
	local key, i, e, pick, tx, ty, eff, best, why, one
	key := dir "." title "target"
	;(force: a learned hit in no slot that needs a target - its card says so, not PlayerStats.txt)
	one := (dir = hitschool) ? HitHeads(title).one : ""
	if (!force && (!Stats.Has(key) || Stats[key] != 1) && one != 1)
		return
	if (!force && one = 1 && (!Stats.Has(key) || Stats[key] != 1))
		DebugLog("  " title ": the game's memory says it hits one enemy (" key " isn't 1) - a target clicked")
	;(the plates as they are now - not as they were when last read: the kill check's off for a battle you played a
	;round in, and an enemy gone since leaves its place behind)
	if (BossChoosen != 1 && V1Gt(V1Ago(EnemyPlatesAt), 8000))
		ReadEnemyHealth()
	if (BossChoosen == 1)
		tx := BossX, ty := BossY, pick := "the boss"
	else if (EnemyPlates.Length)
		{
		;(the enemy the hit does the most to - HitPick)
		pick := HitPick(dmg), why := ""
		if (V1Gt(dmg, 0) && IsObject(EnemyHP) && EnemyHP.Length > 1 && EnemyHP.Length = EnemyPlates.Length)
			why := ", " Min(dmg, EnemyHP[pick].cur) " of its " dmg " damage on it" (dmg >= EnemyHP[pick].cur ? " - kills it" : "")
		tx := EnemyPlates[pick].x, ty := EnemyPlates[pick].y
		pick := "enemy " pick " of " EnemyPlates.Length (IsObject(EnemyHP) ? " (" V1At(V1At(EnemyHP, pick), "cur") " health" why ")" : "")  ; (v1: an enemy with no health read - blank)
		}
	else
		{
		DebugLog("  " title " needs a target, but no enemy nameplate was found to click")
		return
		}
	;(the game asking for a target a moment after the card's clicked: then the plate hovered, then clicked)
	AfterClick(600)
	if (!TargetClick(tx, ty))
		return
	DebugLog("  " title ": clicked " pick " as the target at " tx - GameLeft "," ty - GameTop)
	;(a click on a nameplate doesn't always take: the round's still waiting - its Pass button there - 0.8 s later:
	;once more, on the plate's health line just under the name)
	if (TargetPending())
		{
		TargetClick(tx, ty + Px(20))
		DebugLog("  " title ": the target click didn't take - clicked the plate again at " tx - GameLeft "," ty + Px(20) - GameTop)
		}
	}

;Which enemy a hit on one enemy goes for (HitTarget; KillCalc.ahk TrapTarget: the planned hit's target): the one it does
;the most to - the least of its damage dmg and that enemy's health: not a big hit thrown at one nearly dead while another's
;at full (2026-10-23, a Hydra); one it kills, the healthiest of those; none, the weakest - the first to go. Its damage not
;known: the weakest. Equal: the leftmost. Health not read: the leftmost plate (1). among: only those slots ({slot: 1}), ""
;all. Its slot in EnemyPlates
HitPick(dmg, among := "")
	{
	global EnemyHP, EnemyPlates
	hpPick := "", hpBest := ""
	if (IsObject(EnemyHP) && EnemyHP.Length = EnemyPlates.Length)
		for hpI, hpE in EnemyHP
			{
			if (IsObject(among) && !among.Has(hpI))
				continue
			hpEff := V1Gt(dmg, 0) ? Min(dmg, hpE.cur) : -hpE.cur  ; (v1: damage not known - blank - is not > 0)
			if (hpBest = "" || hpEff > hpBest || (hpEff = hpBest && hpE.cur < EnemyHP[hpPick].cur))
				hpPick := hpI, hpBest := hpEff
			}
	return (hpPick = "") ? 1 : hpPick
	}

;A target clicked: the mouse there, a moment on it (the game takes a nameplate click better hovered), the click;
;the mouse back where it was afterwards (MouseGrab: mousereturn)
TargetClick(x, y)
	{
	;(Wizard101 in the tray - Settings: traygame: nothing clicked - as ClickAt)
	if (GameInTray)
		return 0
	;(never in the Crown shop's corner - SHOP and EARN CROWNS at its top left, to about Px(170): an enemy's plate read
	;that far left isn't clicked)
	if (x < GameLeft + Px(185) && y < GameTop + Px(110))
		{
		DebugLog("  a target click at " x - GameLeft "," y - GameTop " is in the Crown shop's corner - not clicked")
		return 0
		}
	ownGrab := MouseGrab()
	;(your mouse locked meanwhile - Settings.ahk MouseLockOn)
	MouseLockOn("click")
	MouseMove(x, y, MouseSpeedNow())
	;(a battle move: the round's hold renewed, your clicks swallowed now the pointer's on the game - Settings.ahk
	;MouseLockRenew)
	MouseLockRenew()
	Sleep(Max(150, Stats.Has("clickwait") ? Stats["clickwait"] : 40))
	;(gone to the tray during the wait: not clicked)
	if (!GameInTray)
		Click()
	if (ownGrab)
		MouseLetGo()
	MouseLockOff("click")
	return 1
	}

;The round's Pass button (resources\roundstart.png) - or as Wizard101 draws it with the mouse on it: white, not yellow
;(roundstart_hover.png, cut 2026-10-23 at 1440p - the mouse left on Pass hid two battles' first rounds that afternoon).
;ErrorLevel as ImageSearch's - 0 found (x, y its top left), 1 not, 2 the picture can't be opened - and returned;
;PassHover 1 when it was the hovered one
PassButtonAt(&x, &y)
	{
	global PassHover, ErrorLevel ; (v1 globals it sets)
	V1ImageSearch(&x, &y, GameLeft, GameTop, GameRight, GameBottom, PicOpt("resources\roundstart.png"))
	pbErr := ErrorLevel, PassHover := 0
	if (pbErr = 1)
		{
		;(the main set - UI 1 - has none of its own: one made from the 1.144 cut, in a folder that isn't a picture set)
		hp := (PicDir = A_WorkingDir && !FileExist(A_WorkingDir "\resources\roundstart_hover.png"))
			? PicMake("resources\roundstart_hover.png", V1Obj({dir: GenRoot "\main", scale: 1.0})) : PicPath("resources\roundstart_hover.png")
		if (hp != "")
			{
			V1ImageSearch(&x, &y, GameLeft, GameTop, GameRight, GameBottom, PicOptFile(hp))
			if (ErrorLevel = 0)
				pbErr := 0, PassHover := 1
			}
		}
	ErrorLevel := pbErr
	return pbErr
	}

;True while the round still waits for us 0.8 s on: its Pass button is still there (a target click that took starts
;the cast and the button goes)
;TODO (TODO.md goal 3, needs the game): ask the game's memory first - Vision.ahk VisionPhase (/phase): what the hand does
;between a single-target card's click and its target's is NOT SEEN yet (CastPhaseShadow logs it next to the Pass picture's
;verdict); the Pass picture stays as the fallback
TargetPending()
	{
	t0 := A_TickCount
	while (A_TickCount - t0 < 800)
		{
		Sleep(100)
		if (PassButtonAt(&pendX, &pendY))
			return false
		}
	return true
	}

;(v1: Switch - a v2 keyword: a line starting Switch() is a switch statement)
SwitchWindow()
	{
	if (dualmode == 1)
		{
		Send("{Alt down}")
		Send("{Tab down}")
		Send("{Alt up}")
		Send("{Tab up}")
		}
	}
	
s(time) 
	{
	Sleep(time)
	}
	
Respond(Text) 
	{
	;(Wizard101 gone to the tray - Settings: traygame: nothing typed - the line and its Enter would go to the window in front)
	if (GameInTray)
		return
	if (responcemode == 1)
		{
		BlockInput("Send")
		Send("{r}")
		s(100)
		if (GameInTray)
			return
		SendInput("{Raw}" Text)
		Send("{Enter}")
		}
	}
	
Spam(key)
	{
	;(Wizard101 gone to the tray - Settings: traygame: not pressed - the keys would go to the window in front)
	if (GameInTray)
		return
	Send("{" key "}")
	Send("{" key "}")
	Send("{" key "}")
	}
	
ResetUsed()
	{
	;Assume-global so used1..used52 are the battle code's flags, not locals that vanish on return (21-52: each school's
	;blade and trap, the spirit ones - KillCalc.ahk KeyFlags); and the treasure / item copies cast (BoostSrcUsed), the
	;blades cast on you that weren't seen there (BoostUnrec: UseBlade)
	global
	;(v2: a name used%n% makes must exist - each flag declared here, v1 made them by their names)
	global used0, used1, used2, used3, used4, used5, used6, used7, used8, used9, used10, used11, used12, used13, used14
	global used15, used16, used17, used18, used19, used20, used21, used22, used23, used24, used25, used26, used27, used28
	global used29, used30, used31, used32, used33, used34, used35, used36, used37, used38, used39, used40, used41, used42
	global used43, used44, used45, used46, used47, used48, used49, used50, used51, used52
	local n := 0
	while (n <= 52)
		{
		used%n% := 0
		n++
		}
	BoostSrcUsed := V1Obj(), BoostUnrec := []
	}

;(v2 port: v1 started every variable blank - used0..used52, made by name (used%n%), and bladetype / traptype, set by
;name in KillCalc.ahk BoostSearch, are in no <File>Blank(): blank here at the start, as v1's were till the first round's
;ResetUsed / BoostSearch - HkDev's box (dev mode) reads them before that)
UsedBlank()
	{
	global
	local n := 0
	while (n <= 52)
		{
		used%n% := ""
		n++
		}
	bladetype := "", traptype := ""
	}
	
ResetVariables() 
	{
	global
	inbattle := 0
	roundnumber := 0
	playerX := 0
	playerY := 0
	Player := ""
	BossChoosen := 0
	boosts := 0
	BoostRun := 0
	sharpen := 0 
	potent := 0
	blade := 0
	blade2 := 0
	blade3 := 0
	blade4 := 0
	trap := 0
	trap2 := 0
	trap3 := 0
	trap4 := 0
	feint := 0
	aura := 0
	enchant := 0 
	reshuffle := 0
	hit1 := 0
	hit2 := 0
	hit3 := 0
	hit4 := 0
	EnchantedHits := V1Obj()
	PipSaveFor := "", PipSaveRounds := 0, PipSaveGaveUp := 0, PipSaveTarget := "", PipSaveStall := 0, PipSaveLastPips := -1
	PlayerTookRound := 0, RoundLeft := 0, RoundAgain := 0
	;(the no-hits flee counts afresh - Flee.ahk; treasure cards drawn for an enchant too - Draw.ahk)
	FleeNoHits := 0, FleeHitsRound := ""
	DrawsBattle := 0, DrawOff := "", LearnHitFails := V1Obj()
	OwnHpPct := 0, OwnHpRound := -1
	tower := 0  
	hitter := 0
	hitschool := ""
	hammerX := 0
	hammerY := 0
	hitterX := 0
	hitterY := 0
	school := ""
	schoolX := 0
	schoolY := 0
	bladetype := ""
	traptype := ""
	;(a party battle's roles - and Alt+2's pick, for that battle only)
	BattleRole := "", HammerSchool := "", HammerName := "", HammerSlot := 0, HammerGroup := "", SidePlatesKey := "", MySlot := 0
	PartyHitsSeen := "", PartyHitsDuel := "", PartyHitsWait := "", PartyLowKey := "", PartyLowX := "", PartyLowY := "", TrapOn := 0
	TrapMine := 0, TrapAtMax := "", TrapPick := 0, TrapWhy := "", TrapFoeX := "", TrapFoeY := "", TrapFoeMax := "", TrapFoeN := 0, TrapSlot := 0
	PartyFlagDuel := "", PartyFlagRound := V1Obj(), PartyCastRound := ""
	Manual := 0, ManualSchool := ""
	bossX := 0
	bossY := 0
	AppliedBlades := V1Obj()
	BossTraps := V1Obj()
	AuraRounds := 0
	;(blades and traps by damage school - KillCalc.ahk; SlotGame is kept: the slots' cards don't change with the battle)
	HeadsMemo := V1Obj(), BoostPctMem := V1Obj(), AuraSch := "", PartyLastSch := "", PlanHit := "", PlanHeads := "", PlanList := ""
	BladeDir := "", TrapDir := "", BladeU1 := "", BladeU2 := "", TrapU1 := "", TrapU2 := "", Blade2U1 := "", Blade2U2 := "", Trap2U1 := "", Trap2U2 := ""
	SbFound := V1Obj(), GbFound := V1Obj(), BoostHand := V1Obj(), BoostSrcUsed := V1Obj(), BoostExtra := "", HammerPlan := "", BoostMemOk := 0, BoostSaid := V1Obj(), BoostMisfitDone := 0, DeckSharp := "", SpentOff := V1Obj()
	BoostUnrec := [], BoostOneOfOff := V1Obj(), BoostMemOnly := V1Obj(), BubbleUp := ""
	;(the negative auras put up this battle, an absorb or one in hand, your prism on the boss - 2026-10-26)
	NegAuraOn := V1Obj(), absorb := 0, AbsorbFreeOk := 0, AbsorbOnlyFree := 0, negaura := 0, ConvertOn := ""
	EnemyHP := ""
	BossSlot := 0
	BossMax := 0
	DualBattle := 0
	HealthStatus := ""
	ToolTip(, , , 20)
}
	
;Whether the boss picked with Alt+1 needs your school's prism (the chain's convert): the game's memory says it's of your
;school - it resists your hits (KillCalc.ahk ConvertNeedMem, read-only). Not known - the memory not read: no. (Before
;2026-10-26 it looked for <school>\convertN.png by the boss with a folder that was always blank, so it never found it - a
;10 px badge at tolerance 100 would match about anything: not looked for). Your prism on it already and no hit of yours since
;(KillCalc.ahk ConvertUp - the review, 2026-10-26: one went out every round while one was in hand): no
NeedsConvert()
	{
	global BossChoosen, hitschool, BoostSaid, ConvertOn
	if (BossChoosen != 1 || !V1IsFunc("ConvertNeedMem"))
		return false
	if (V1IsFunc("ConvertUp") && ConvertUp.Call())
		{
		if (IsObject(BoostSaid) && !BoostSaid.Has("convert|up" V1At(ConvertOn, "round")))
			BoostSaid["convert|up" V1At(ConvertOn, "round")] := 1, DebugLog("  convert: your prism went on the boss in round " V1At(ConvertOn, "round") " and no hit of yours has gone out since - not a second one")
		return false
		}
	ncMem := ConvertNeedMem.Call()
	ncSay := "convert|" (ncMem = "" ? "unknown" : ncMem)
	if (IsObject(BoostSaid) && !BoostSaid.Has(ncSay))
		BoostSaid[ncSay] := 1, DebugLog("  convert: the boss " (ncMem = 1 ? "is " hitschool " (the game's memory) - it resists your hits: your prism first"
			: ncMem = 0 ? "isn't " hitschool " (the game's memory) - no prism" : "- its school not read from the game's memory (" NavBattleWhy "): no prism"))
	return (ncMem = 1)
	}
	
LockMove(&direction)
	{
	;(Wizard101 gone to the tray - Settings: traygame: not pressed - the keys would go to the window in front)
	if (GameInTray)
		return
	Send("{" direction " down}")
	s(50)
	Send("{Shift down}")
	s(50)
	Send("{" direction " up}")
	s(50)
	Send("{Shift up}")
	}
	
Log()
	{
	Send("{Esc}")
	s(1000)
	UpdateGameRect()
	V1ImageSearch(&logX, &logY, GameLeft, GameTop, GameRight, GameBottom, PicOpt("resources\log.png"))
	if (Errorlevel == 0)
		{
		ClickAt(logX, logY)
		} else if (Errorlevel == 2)
			{
			ErrorBox(&_funcn := "Log", &dir, &title)
			}
	s(5000)
	}
	
Join()
	{
	UpdateGameRect()
	V1ImageSearch(&joinX, &joinY, GameLeft, GameTop, GameRight, GameBottom, PicOpt("resources\join.png"))
	if (Errorlevel == 0)
		{
		ClickAt(joinX, joinY)
		} else if (Errorlevel == 2)
			{
			ErrorBox(&_funcn := "Join", &dir, &title)
			}
	s(5000)
	}

UsePotion()
	{
	UpdateGameRect()
	V1ImageSearch(&potionX, &potionY, GameLeft, GameTop, GameRight, GameBottom, PicOpt("resources\potion.png"))
	ClickAt(potionX, potionY)
	}

CheckAfk()
	{
	global ErrorLevel, AfkRetries, FleeWhy, afkVar, AfkWhy ; (v1 globals it sets)
	if (afkVar == 1)
		{
		;Waits for you to press w/a/s/d, checking for a disconnect every second meanwhile - held for mana: every
		;30 s the mana globe looked at, and on by itself once there's enough for the cheapest hit (at least 3), or
		;once the 10 minutes after a failed run to buy potions are up (checkmana tries another)
		;(3 tries at most a hold - each a run and its alert; on again by itself once there's mana, or by your keys)
		waitRun := (AfkWhy = "mana" && Stat("fleeon") && V1Lt(A_TickCount, PotionFailUntil) && AfkRetries < 3)  ; (v1: no run failed - blank - compared as text: false)
		Loop
			{
			;(battles only - Settings: battlesonly: a hold for mana let go - one from before it was switched on, or switched on
			;meanwhile (checkmana and FleeAfter start none then): it would only leave the driver's battles unplayed)
			if (AfkWhy = "mana" && BattlesOnly())
				{
				DebugLog("no mana: not holding - battles only is on (Settings), the battles are played on")
				break
				}
			ihOutputVar := InputHook("T1","{w} {a} {s} {d}","w, a, s, d"), ihOutputVar.Start(), ErrorLevel := ihOutputVar.Wait(), OutputVar := ihOutputVar.Input
			if (Errorlevel != "Timeout")
				{
				AfkRetries := 0
				break
				}
			;(Wizard101 in the tray - Settings: traygame: the bot's off, so no reconnecting on the hidden game, as in the
			;main loop - the log caught up and the waits started afresh once it's shown, Reconnect.ahk RcAfterTray)
			if (!GameInTray)
				ReconnectCheck()
			if (AfkWhy = "mana" && VisionOn && Mod(A_Index, 30) = 0 && GameActive())
				{
				afkMana := V1At(PotionGlobes(), "mana")
				if (afkMana != "" && V1Ge(V1Add(afkMana, 0), Max(3, FleeCheapestHit() = "" ? 0 : FleeCheapestHit())))  ; (v1: a reading that isn't a number - blank - compared as text)
					{
					DebugLog("no mana: the mana globe reads " afkMana " now - carrying on")
					AfkRetries := 0
					break
					}
				;(FleeAfter, right after this, tries: a potion, else a run - whether the mana picture matches or not)
				if (waitRun && V1Ge(A_TickCount, PotionFailUntil))
					{
					AfkRetries := V1Add(AfkRetries, 1), FleeWhy := "mana"
					DebugLog("no mana: 10 minutes since the run to buy potions failed - trying again (" AfkRetries " of 3)")
					break
					}
				}
			}
		afkVar := 0, AfkWhy := ""
		}
	}
return

Afk(why := "")
	{
	global afkVar, AfkWhy ; (v1 globals it sets)
	if (afkVar == 0)
		{
		;(battles only - Settings: battlesonly: not the step that keeps the wizard from timing out - it moves nothing; the hold
		;itself is kept)
		if (!BattlesOnlyNo("step to keep from timing out (afk)"))
			LockMove(&_direction := "a")
		afkVar := 1, AfkWhy := why
		}
	}

checkmana()
	{
	;(when the picture was last found with mana in the globe - logged at most every 5 minutes)
	static wrongSaid := 0
	;(battles only: when it last found no mana and none to be had - looked at again 2 minutes on; said and alerted when)
	static boNoneAt := 0, boSaidAt := 0
	if (afkVar == 0)
		{
		;(battles only - Settings: battlesonly: no mana and no potion a moment ago - not each pass of the loop: a Ctrl+O and its
		;2.5 s wait every pass would keep the round watch from the driver's battles)
		if (boNoneAt && A_TickCount - boNoneAt < 120000 && BattlesOnly())
			return
		V1ImageSearch(&manaX, &manaY, GameLeft, ScreenY, GameLeft + GameW / 4, GameBottom, PicOpt("resources\manaempty.png"))
		if (Errorlevel == 0)
			{
			;(the picture is small and, made for other UI sizes, mostly see-through: it can match the energy globe
			;beside the mana globe, clear when it's low. The mana globe's number, read by the helper, has the last
			;word: enough for the cheapest hit - at least 3 - is mana)
			manaNow := VisionOn ? V1At(PotionGlobes(), "mana") : ""
			manaNeed := Max(3, FleeCheapestHit() = "" ? 0 : FleeCheapestHit())
			;(the helper running but the number not read - the wrong picture set, a window over it: not on the
			;picture alone)
			if (VisionOn && manaNow = "")
				{
				if (!wrongSaid || A_TickCount - wrongSaid > 300000)
					DebugLog("no mana? The mana-empty picture matched, but the mana globe's number can't be read - not acting on the picture alone")
				wrongSaid := A_TickCount
				return
				}
			if (manaNow != "" && V1Ge(V1Add(manaNow, 0), manaNeed))  ; (v1: a reading that isn't a number - blank - compared as text)
				{
				if (!wrongSaid || A_TickCount - wrongSaid > 300000)
					DebugLog("no mana? The mana-empty picture matched at " manaX - GameLeft "," manaY - GameTop " (the energy globe beside it?), but the mana globe reads " manaNow " - carrying on")
				wrongSaid := A_TickCount
				return
				}
			;(a potion first - or a run to buy some - so it can carry on; only then keep the character from timing out)
			if (Stat("fleeon") && FleeRefillMana("no mana"))
				return
			;(battles only - Settings: battlesonly: no hold - the driver takes this wizard into its battles all the same, and a hold
			;would only leave them unplayed (no pass, no support with the mana left): said and an alert - once in 10 minutes -, the
			;battles played on, looked at again in 2 minutes)
			if (BattlesOnly())
				{
				boNoneAt := A_TickCount
				if (!boSaidAt || A_TickCount - boSaidAt > 600000)
					{
					boSaidAt := A_TickCount
					DebugLog("no mana and no potion - not holding: battles only is on (Settings), the battles are played on (buy or drink potions yourself)")
					AlertSend("mana", "out of mana", "No mana and no potion left, and battles only is on (Settings): the bot doesn't go to buy any and plays the battles on with what mana it has - drink or buy some yourself.")
					}
				return
				}
			Respond("Error, It Seems I Have No Mana. Preventing Timeout.")
			AlertSend("mana", "out of mana", "No mana and no potion to be had - the bot is holding (kept from timing out) and carries on by itself once there's mana again.")
			afk("mana")
			}
		}
	}
	
mobloop:
mobloop()
return
	
LoreLoop:
LoreLoop()
return 
return

NewStaticGui(&Text, &x, &y, &w, &h) 
	{
	global myGui ; (v1 globals it sets)
	box := " x" . x . " y" . y . " w" . w . " h" . h 
	;(v1's GUI 1: made by its first Add, a later Add put into the same window till it's destroyed)
	if (!IsSet(myGui) || !IsObject(myGui))
		{
		myGui := Gui()
		myGui.OnEvent("Close", GuiClose)
		}
	myGui.Add("Text", box, Text)
	myGui.Title := "AutoFarmer"
	myGui.Show("AutoSize Center")
	}

NewTempGui(&timeout, &Text, &x, &y, &w, &h) 
	{
	global myGui ; (v1 globals it sets)
	box := " x" . x . " y" . y . " w" . w . " h" . h 
	;(v1's GUI 1, as NewStaticGui)
	if (!IsSet(myGui) || !IsObject(myGui))
		{
		myGui := Gui()
		myGui.OnEvent("Close", GuiClose)
		}
	myGui.Add("Text", box, Text)
	myGui.Title := "AutoFarmer"
	myGui.Show("AutoSize Center")
	Sleep(timeout)
	Gui1Destroy()
	}

;v1's Gui, 1:Destroy: GUI 1 gone (none there: nothing happens) - the next Add makes a new one
Gui1Destroy()
	{
	global myGui
	if (IsSet(myGui) && IsObject(myGui))
		myGui.Destroy()
	myGui := ""
	}
	
ModeBox(&mode, &name, &x, &y, &w, &h)
	{
	
	if ((inbattle == 1) && (mode != 1))
		{
		NewTempGui(&_timeout := 1500, &_text := "Please Don't turn modes on while in combat", &_x := 10, &_y := 10, &_w := 210, &_h := 30)
		}	
	
	if (mode == 0) && (inbattle == 0)
		{
		gui := "Turning On " . name . " Mode."
		NewTempGui(&_timeout := 1000, &gui, &x, &y, &w, &h)
		mode := 1
		} else if (mode == 1)
			{
			gui := "Turning Off " . name . " Mode."
			NewTempGui(&_timeout := 1000, &gui, &x, &y, &w, &h)
			mode := 0
			}
	}
	
;(the modes and picks below - Alt+D, Alt+S, Alt+1... - only while the bot is on: off, their keys go to whatever
;program has them; their keys: Hotkeys.ahk)
HkDev:
HkDev()
return

HkLore:
HkLore()
return

HkDual:
HkDual()
return
		
HkCommand:
HkCommand()
return

HkStats:
HkStats()
return

HkResponse:
HkResponse()
return
	
HkBoss:
HkBoss()
return

HkLoop:
HkLoop()
return

HkBoost:
HkBoost()
return

HkPlayer:
HkPlayer()
return

GuiClose:
GuiClose()
return

HkDash:
HkDash()
return

CommandOff()
	{
	global
	local _funcn ; (v1 passed these literals as temporaries: locals here, not globals)
	if ((devmode == 1) && (commandmode == 1)) 
		{
		V1ImageSearch(&offX, &offY, GameLeft, GameBottom - Px(25), GameLeft + GameW / 4 + Px(20), GameBottom, PicOpt("resources\off.png", 120))
		if (ErrorLevel == 0) 
			{			
			Respond("Shutting Down.")
			ExitApp()
			} else if (Errorlevel == 2)
				{
				ErrorBox(&_funcn := "CommandOff", &dir, &title)
				}
		}
	}
	
CommandReload()
	{
	global
	local _funcn ; (v1 passed these literals as temporaries: locals here, not globals)
	if ((devmode == 1) && (commandmode == 1)) 
		{
		;Requires devmode to be on to reloaded script manually
		V1ImageSearch(&relX, &relY, GameLeft, GameTop + GameH * 0.65, GameLeft + GameW / 7.4, GameTop + GameH * 0.775, PicOpt("resources\rel.png", 120))
		if (ErrorLevel == 0) 
			{
			Respond("Reloading Script.")
			BotRestart()
			} else if (Errorlevel == 2)
				{
				ErrorBox(&_funcn := "CommandReload", &dir, &title)
				}
		}
	}

CommandHit()
	{
	global
	local _title, _funcn ; (v1 passed these literals as temporaries: locals here, not globals)
	if (commandmode == 1)
		{
		V1ImageSearch(&X, &Y, GameLeft, GameTop + GameH * 0.65, GameLeft + GameW / 7.4, GameTop + GameH * 0.775, PicOpt("resources\PlayerHit.png", 120))
		if (Errorlevel == 0)
			{
			Respond("Okay, Ill OverRide The Automatic Battle Sequence.")
			if ((hit == 1) || (hit2 == 1) || (hit3 == 1) || (hit4 == 1))
				{
				if (hit4 == 1) && (BossChoosen = 1)
					{
					UseHit(&_title := "hit4", &hit4, &hitschool)
					} else if (hit3 == 1)
						{
						UseHit(&_title := "hit3", &hit3, &hitschool)
						} else if (hit2 == 1)
							{
							UseHit(&_title := "hit2", &hit2, &hitschool)
							} else if (hit1 == 1)
								{
								UseHit(&_title := "hit1", &hit1, &hitschool)
								} else 
									{
									Respond("It Seems There Are No Hits In Hand, I'll Pass Instead.")
									ClickPass()
									}
				}
			} else if (Errorlevel == 1)
				{
				return false
				} else if (ErrorLevel == 2)
					{
					ErrorBox(&_funcn := "CommandHit", &dir, &title)
					}
		}
	}
	
CommandPass()
	{	
	global
	local _funcn ; (v1 passed these literals as temporaries: locals here, not globals)
	if (commandmode == 1)
		{
		V1ImageSearch(&PlayerPassX, &PlayerPassY, GameLeft, GameTop + GameH * 0.65, GameLeft + GameW / 7.4, GameTop + GameH * 0.775, PicOpt("resources\PlayerPass.png", 120))
		if (ErrorLevel == 0)
			{
			Respond("Alright, Ill Pass Instead.")
			ClickAt(passX, passY)
			return true
			} else if (Errorlevel == 1)
				{
				return false
				} else if (ErrorLevel == 2)
					{
					ErrorBox(&_funcn := "CommandPass", &dir, &title)
					return false
					} 
		}
	}
	
CommandWalk()
	{
	global
	local _funcn ; (v1 passed these literals as temporaries: locals here, not globals)
	if (commandmode == 1)
		{
		V1ImageSearch(&walkX, &walkY, GameLeft, GameTop + GameH * 0.65, GameLeft + GameW / 7.4, GameTop + GameH * 0.775, PicOpt("resources\walk.png", 120))
		if (ErrorLevel == 0) 
			{
			;(battles only - Settings: battlesonly: the command's walk not done - it moves nothing out of battle)
			if (BattlesOnlyNo("walk the chat command asked for (command mode)"))
				return false
			Respond("I'm Not A Dog, But Ill Do It Anyways")
			Send("{w Down}")
			Sleep(2000)
			Send("{w Up}")
			Sleep(Ten)
			return true
			} else if (Errorlevel == 1)
				{
				return false
				} else if (ErrorLevel == 2)
					{
					ErrorBox(&_funcn := "CommandWalk", &dir, &title)
					return false
					}
		}
	}
	
CommandEnter()
	{
	global
	local _funcn ; (v1 passed these literals as temporaries: locals here, not globals)
	if (commandmode == 1)
		{
		V1ImageSearch(&enterX, &enterY, GameLeft, GameTop + GameH * 0.65, GameLeft + GameW / 7.4, GameTop + GameH * 0.775, PicOpt("resources\enter.png", 120))
		if (ErrorLevel == 0) 
			{
			;(battles only - Settings: battlesonly: no X at the sigil the command asked for)
			if (BattlesOnlyNo("X at a sigil the chat command asked for (command mode)"))
				return false
			Respond("Entering Sigil. Make Sure You Have The Right Deck On.")
			Send("{x}")
			Sleep(Tick)
			Send("{x}")
			Sleep(Tick)
			Send("{x}")
			return true
			} else if (Errorlevel == 1)
				{
				return false
				} else if (ErrorLevel == 2)
					{
					ErrorBox(&_funcn := "CommandEnter", &dir, &title)
					return false
					}
		} 
	}
	
CommandAfk()
	{
	global
	local _funcn ; (v1 passed these literals as temporaries: locals here, not globals)
	if (commandmode == 1)
		{
		V1ImageSearch(&afkX, &afkY, GameLeft, GameTop + GameH * 0.65, GameLeft + GameW / 7.4, GameTop + GameH * 0.775, PicOpt("resources\afk.png", 120))
		if (ErrorLevel == 0)
			{
			Respond("Okay, I'll Prevent Time Out Until Further Notice.")
			afk()
			return true
			} else if (Errorlevel == 1)
				{
				return false
				} else if (ErrorLevel == 2)
					{
					ErrorBox(&_funcn := "CommandAfk", &dir, &title)
					return false
					}
		}
	}
	
CommandPort() 
	{
	global
	local _funcn ; (v1 passed these literals as temporaries: locals here, not globals)
	if (commandmode == 1)
		{
		V1ImageSearch(&wordportX, &wordportY, GameLeft, GameTop + GameH * 0.65, GameLeft + GameW / 7.4, GameTop + GameH * 0.775, PicOpt("resources\wordport.png", 120))
		if (ErrorLevel == 0)
			{
			;(battles only - Settings: battlesonly: no teleport to the friend the command named)
			if (BattlesOnlyNo("teleport the chat command asked for (command mode)"))
				return false
		
			Send("{/}")
			Sleep(Tick)
			Send("{BS}")
			Sleep(Tick)
			Send("{Enter}")
			Sleep(Half)
			
			V1ImageSearch(&checkX, &checkY, GameLeft, GameTop, GameRight, GameBottom, PicOpt("resources\check.png"))
			if (Errorlevel == 0) 
				{
				Sleep(Half)
				V1ImageSearch(&nameX, &nameY, GameLeft, checkY - Px(20), checkX, checkY + Px(20), PicOpt("resources\name.png"))
				if (ErrorLevel == 0) 
					{		
					ClickAt(nameX + Px(30), nameY)
					
					s(2000)		
					V1ImageSearch(&portX, &portY, GameLeft, GameTop, GameRight, GameBottom, PicOpt("resources\port.png"))
					if (Errorlevel == 0) 
						{
						ClickAt(portX, portY)
						Sleep(Half)
						
						V1ImageSearch(&yesX, &yesY, GameLeft, GameTop, GameRight, GameBottom, PicOpt("resources\yes.png"))
						if (Errorlevel == 0) 
							{
							ClickAt(yesX, yesY)
							Sleep(Half)
							
							Respond("Initiating Teleportation Sequence.")
								
							V1ImageSearch(&okX, &okY, GameLeft, GameTop, GameRight, GameBottom, PicOpt("resources\ok.png"))
							if (Errorlevel == 0) 
								{
								ClickAt(okX, okY)
								
								Respond("Error Teleporting, Check If Ports Are On, Or If You're In A Dungeon.")
									
								}
							} else if ((Errorlevel == 1) && (devmode == 1))
								{
								Respond("Error Teleporting, Invalid Gui.")
								}
						} else if ((Errorlevel == 1) && (devmode == 1))
							{
							Respond("Error Teleporting, Invalid Gui.")
							}
					} else if ((Errorlevel == 1) && (devmode == 1))
						{
						Respond("Error Teleporting, Invalid Gui.")
						}
				} else if ((Errorlevel == 1) && (devmode == 1))
					{
					Respond("Error Teleporting, Invalid Gui.")
					}
			return true
			Sleep(Ten)
			} else if (Errorlevel == 1)
				{
				return false
				} else if (Errorlevel == 2)
					{
					ErrorBox(&_funcn := "CommandPort", &dir, &title)
					return false
					}
		}
	}

#HotIf BotOn
!0::HK1_()

#`::HK2_()
return

#HotIf

HkQuit:
HkQuit()
ExitApp()
return

HkRestart2:
HkRestart2()
return


;Which school's badge (a name plate's school icon) matches best in the rectangle: each school with a
;badge picture at this UI size is looked for, and where it's found, how little colour tolerance it
;still matches with there decides - a badge made at another size roughly matches the other schools'
;too (they share the gold ring), the right one matches closest. Returns the school ("" if none) and
;its position in bx, by
BestBadge(x1, y1, x2, y2, &bx, &by, nearX := 0, nearY := 0)
	{
	;(the vision helper, if it's running; with several plates, the one nearest nearX, nearY)
	sch := VisionBadge(x1, y1, x2, y2, &bx, &by, nearX, nearY)
	if (sch != -1)
		return sch
	best := "", bestTol := 99, bx := 0, by := 0
	for each, sch in ["storm", "fire", "myth", "balance", "ice", "life", "death"]
		{
		rel := sch "\" sch ".png", p := PicPath(rel)
		;(the main set's 2018 badge, which doesn't match at another size)
		if (UiScale != 1 && p = A_WorkingDir "\" rel)
			continue
		V1ImageSearch(&fx, &fy, x1, y1, x2, y2, "*" GenTol " *TransFF00FF " p)
		if (ErrorLevel)
			continue
		for each2, tol in [0, 3, 6, 10, 14, GenTol]
			{
			if (tol >= bestTol)
				break
			V1ImageSearch(&gx, &gy, fx - 3, fy - 3, fx + Px(40), fy + Px(40), "*" tol " *TransFF00FF " p)
			if (ErrorLevel = 0)
				{
				best := sch, bestTol := tol, bx := gx, by := gy
				break
				}
			}
		}
	return best
	}

;The bot's number for a hitter school (0 = none)
BadgeNumber(sch)
	{
	for i, name in ["storm", "fire", "myth", "balance", "ice", "life", "death"]
		if (name = sch)
			return i
	return 0
	}

;A school's blades and traps: "elemental" (storm, fire, ice), "spirit" (myth, life, death), "balance"; "" not a school
SchoolGroup(sch)
	{
	n := BadgeNumber(sch)
	return (n = 1 || n = 2 || n = 5) ? "elemental" : (n = 3 || n = 6 || n = 7) ? "spirit" : n = 4 ? "balance" : ""
	}

;Did the card just clicked go out? The Pass button has to stay gone for 1 s (it can blink out for a moment while
;the hand updates) - looked at every 100 ms; still there 0.7 s after the click = the card didn't cast
;v1.0.0: the game's memory's phase logged beside the verdict (CastPhaseShadow - log only, nothing acts on it yet)
;TODO (TODO.md goal 3, needs the game): once those lines show how the hand reads right after a cast goes out (state
;"waiting" or the planning flag dropping, and how fast), the memory's verdict first here, the Pass picture as the fallback;
;then the same check before UseBlade, UseTrap, ClickBubble, the aura and UseNegAura record a cast (none of them checks now)
CastWentOut()
	{
	global
	local passX, passY, stillThere, t0, goneFrom
	stillThere := false, goneFrom := 0, t0 := A_TickCount
	while (A_TickCount - t0 < 2500)
		{
		Sleep(100)
		UpdateGameRect()
		if (PassButtonAt(&passX, &passY) = 0)
			{
			goneFrom := 0
			if (A_TickCount - t0 >= 700)
				{
				stillThere := true
				break
				}
			}
		else if (!goneFrom)
			goneFrom := A_TickCount
		else if (A_TickCount - goneFrom >= 1000)
			break
		}
	CastPhaseShadow(!stillThere, A_TickCount - t0)
	return !stillThere
	}

;The game's memory's round phase beside a cast check's verdict (v1.0.0 - CastWentOut: went 1 the Pass picture says the card
;went out, ms since the click): Vision.ahk VisionPhase, LOG ONLY - each verdict with the state it came with, once per
;pairing a battle, so what the memory says after a cast can be seen in debug.log before anything acts on it ("cast check
;(memory, log only)"). Nothing when it can't be read
CastPhaseShadow(went, ms)
	{
	static said := V1Obj(), saidDuel := ""
	if (!V1IsFunc("VisionPhase"))
		return
	cpsP := VisionPhase.Call()
	if (!IsObject(cpsP))
		return
	if (saidDuel != BlDuel)
		said := V1Obj(), saidDuel := BlDuel
	cpsKey := (went ? 1 : 0) "|" cpsP.state "|" cpsP.planning
	if (said.Has(cpsKey))
		return
	said[cpsKey] := 1
	DebugLog("  cast check (memory, log only): the Pass picture says the card " (went ? "went out" : "didn't go out") " (" ms " ms) - the game's memory: " cpsP.state
		. ", planning " cpsP.planning ", " cpsP.shown " card(s) shown of " cpsP.size (cpsP.why != "" ? " (" cpsP.why ")" : "") " (said once a battle)")
	}

;A learned hit in no slot cast (CastBestHit, when no hit1-4 went): the strongest in hand you can pay for, by a fresh
;look at the hand (LearnHitCards) - an enchant in hand on it first (as UseHit does for hit1-4: free, more damage), its
;card clicked, then a target if it hits one enemy. Not the kill check's (it knows the slots' hits only).
;learnedhits:0 in PlayerStats.txt: never. True if it went out
CastLearnedHit()
	{
	global
	local ans, list, c, enchanted
	if (!Stat("learnedhits") || !VisionOn || hitschool = "" || PipSaveFor != "" || !V1IsFunc("LearnHitCards"))
		return false
	if (!LearnHitReady())
		return false
	;(the strongest first; one that doesn't go - an off-school card's power pips count 1, a guessed cost - is left for
	;this battle till there are more pips, and the next is tried: two a round at most, each looked for afresh)
	Loop 2
		{
		ans := LearnHandRead()
		list := LearnHitCards(ans)
		if (!list.Length)
			return false
		c := list[1]
		;(an enchant in hand: on the hit first - then the hand closes up round the gap it left, the hit half a card's
		;width towards it)
		enchanted := false
		;(never on an item card - a pet's or gear's: it can't be enchanted)
		if (A_Index = 1 && !LearnHasFlag(c.c, "item"))
			{
			FindEnchant()
			if (enchant >= 1 && enchantX != "" && Abs(enchantX - c.x) > HalfPitch)
				{
				DebugLog("  enchant (level " enchant ") on learned hit " c.id " first, at " enchantX - GameLeft "," enchantY - GameTop)
				ClickAt(enchantX, enchantY, 150)
				ClickAt(Round(c.x), Round(c.y), 150)
				CenterMouse()
				Sleep(500)
				c.x += (c.x < enchantX ? HalfPitch : -HalfPitch), enchanted := true
				}
			}
		DebugLog("  learned hit " c.id " (" LearnDescribe(c.c) ")" (enchanted ? ", enchanted," : "") " - in no slot: cast at " Round(c.x) - GameLeft "," Round(c.y) - GameTop)
		ClickAt(Round(c.x), Round(c.y))
		if (c.c.type = "damage" && c.c.target != 0)
			HitTarget("learned hit", hitschool, 1, LearnedHitDamage(c.c, enchanted))
		if (CastWentOut())
			{
			;(the blades and traps that fit its heads used up - KillCalc.ahk)
			ConsumeBoosts(LearnHitHeads(c.c))
			DashCast("learned/" c.id)
			return true
			}
		LearnHitFails[c.id] := PipsNow
		DebugLog("  learned hit " c.id " didn't cast (not enough pips?) - not tried again this battle with " PipsNow " pips or fewer")
		CenterMouse()
		VisionForget()
		}
	return false
	}

;The enchant cards it knows, the most damage added first (PlayerStats.txt enchantN - change one and the order
;follows): [level (enchantN), picture folder, name]. 1 is the old life\enchant placeholder; Strong, Giant and
;Monstrous (5-7) are learned from the card the first time one's in hand (CardLearn.ahk, kind "enchant")
EnchantList()
	{
	list := []
	for i, e in [[4, "resources", "epic"], [3, "resources", "colossal"], [2, "resources", "gargantuan"], [7, "resources", "monstrous"], [6, "resources", "giant"], [5, "resources", "strong"], [1, "life", "enchant"]]
		{
		at := 1
		while (at <= list.Length && Stat("enchant" list[at][1]) >= Stat("enchant" e[1]))
			at++
		list.InsertAt(at, e)
		}
	return list
	}

;Looks for an enchant card in hand - the best (EnchantList): enchant := its level, enchantX/Y where it is; 0 none.
;Epic only once a hitter's known (as before). By the vision helper; what it can't tell (-1: not running, no picture
;it can use) by ImageSearch. Run again after one is used, since the hand shifts
FindEnchant()
	{
	global
	local each, ench, r, unsure
	enchant := 0, unsure := []
	;(v1.0.0, memclicks:1: the best enchant where the game's memory has it, first - only once its boxes have been seen
	;lining up with the screen's at this window size, KillCalc.ahk MemEnchantFind; else by their pictures as ever)
	if (MemEnchantFind(&enchant, &enchantX, &enchantY))
		return
	for each, ench in EnchantList()
		{
		if (ench[1] = 4 && hitter = 0)
			continue
		r := VisionOn ? VisionFind(ench[2], ench[3], &enchantX, &enchantY) : -1
		if (r = 1)
			{
			enchant := ench[1]
			return
			}
		if (r = -1)
			unsure.Push(ench)
		}
	for each, ench in unsure
		{
		V1ImageSearch(&enchantX, &enchantY, ScreenX - HandHalf, ScreenY - Px(75), ScreenX + HandHalf, ScreenY + Px(75), PicOpt(ench[2] "\" ench[3] ".png", CardTol))
		if (ErrorLevel = 0)
			{
			enchant := ench[1]
			return
			}
		}
	}

;The battle from the game's memory at a round's start (v1.0.0 - RoundStart): sch your school (your participant's,
;Vision.ahk NavBattle - READ-ONLY, read now; lower case, "" not read or not a school the bot knows) and, with memclicks:1
;only, x, y your plate's middle in pixels (NavPlatePx - NOT TRIED as a click in the game yet; "" not read). Clicks nothing
;Only while one game window runs (Vision.ahk VisionMemOneClient - v1.0.0 review): with two or more navmem can be on another
;client, and its wizard's school written over the badge's (RoundStart) would make the hitter that school, write it to
;characters.txt for this character and blind VisionCards' "another client's wizard" check (it compares the two) - "" then
RoundBattleMem(&sch, &x, &y)
	{
	sch := "", x := "", y := ""
	if (!V1IsFunc("VisionMemOneClient") || !VisionMemOneClient.Call())
		return
	rbmB := V1IsFunc("NavBattle") ? NavBattle.Call() : ""
	if (!IsObject(rbmB) || !IsObject(rbmB.me))
		return
	rbmS := StrLower(Trim(rbmB.me.school))
	if (BadgeNumber(rbmS))
		sch := rbmS
	if (Stat("memclicks") = 1 && V1IsFunc("NavPlatePx") && NavPlatePx.Call(rbmB.me, &rbmX, &rbmY))
		x := rbmX, y := rbmY
	}

;Checks a hit really got cast: once a spell is chosen the Pass button goes away. If it's still
;there the card couldn't be cast (not enough pips), so the round tries the next option instead
;consume: a hit uses up the blades and traps on it (ConsumeBoosts) - a heal doesn't (false)
;Another of your wizards' name plates (player.png, player2.png, player3.png) in the battle besides the one found: a party
;battle - which plate is this PC's isn't sure (phase 1b), so its school isn't saved for the character (StatsNoteSchool)
PlayerPlates2()
	{
	;(only when the battle has more than one wizard on your side - the game's log, EnemySpells.ahk)
	n := 0
	if (IsObject(BlNames))
		Loop 4
			n += BlNames.Has(A_Index + 3) ? 1 : 0
	if (n < 2)
		return false
	n := 0
	for each, pic in ["player.png", "player2.png", "player3.png"]
		{
		if (!FileExist(A_ScriptDir "\resources\" pic))
			continue
		V1ImageSearch(&px, &py, GameLeft, GameTop + GameH / 4, GameRight, GameBottom, PicOpt("resources\" pic))
		if (ErrorLevel = 0)
			n += 1
		}
	if (n > 1)
		DebugLog("  " n " of your wizards' name plates in this battle - its school not saved for this character")
	return n > 1
	}

CastResult(title, &hit, dir, enchanted, consume := true)
	{
	global
	if (CastWentOut())
		{
		EnchantedHits.Delete(title)
		;(the blades and traps that fit its heads used up - KillCalc.ahk HitHeads, ConsumeBoosts)
		if (consume)
			ConsumeBoosts(HitHeads(title))
		DashCast(title)
		BrecCast(title)
		return true
		}
	DebugLog("  " title " didn't cast (not enough pips?)")
	hit := 0
	;An unaffordable card is discarded, unless it carries an enchant (now or from an earlier round)
	if (!enchanted && !EnchantedHits[title] && Stat("discardunaffordable") == 1)
		DiscardCard(title, dir)
	CenterMouse()
	return false
	}

;Right-clicks (discards) cards that can't help this battle. Returns how many were discarded
DiscardSpare()
	{
	global
	local did := 0, dsK, dsF, dsKeys, dsI, dsSharpUsed, dsNeed, dsC, dsDone, dsKeep
	;(a party battle's blader or healer casts its blades again after each of the hitter's hits: none is spare - not with
	;Alt+2's pick, whose hits nothing follows; but one that boosts neither the hitter's planned hit nor its own school
	;goes - KillCalc.ahk BoostMisfitDiscard)
	if (PartySupport() && HammerSlot)
		return BoostMisfitDiscard()
	;(v1.8.0: with the game's hand read and its boxes seen lining up, every blade's and trap's copies past the casts its key
	;has left this battle go - DiscardSpent; the both-casts rule below takes only the keys it didn't settle - dsDone)
	dsDone := V1Obj()
	if (DiscardSpentOn())
		did += DiscardSpent(dsDone)
	;A blade whose sharpened and plain casts have both been used this battle won't stack again - each school's (SbFound),
	;the group's (GbFound), Balanceblade, Bladestorm (a treasure or item card's copy still to go - the game's hand - stays)
	dsKeys := []
	for dsK in SbFound
		if (BoostKind(dsK) = "blade")
			dsKeys.Push(dsK)
	for dsK in GbFound
		if (BoostKind(dsK) = "blade")
			dsKeys.Push(dsK)
	for dsI, dsK in ["blade3", "blade4"]
		if (%dsK% == 1)
			dsKeys.Push(dsK)
	;(v1.9.1: not with reboost:1 where a hit of yours frees both its casts again - ReboostKeepRole: set to Hitter or the
	;party off, not Alt+2's pick -: its copies stay in hand for the casts after that hit, said once a battle a blade.
	;Decks.ahk DeckSimVals tells the simulator - reboostkeep)
	dsKeep := Stat("reboost") == 1 && ReboostKeepRole()
	for dsI, dsK in dsKeys
		{
		dsF := KeyFlags(dsK)
		if (!dsDone.Has(dsK) && IsObject(dsF) && UsedFlag(dsF[1]) == 1 && UsedFlag(dsF[2]) == 1 && !BoostCanGo(dsK))
			{
			;(kept only while a hit of yours can still free it - a deck cast of it still on you: BoostFreeable; one used
			;up before reboost came on in the battle - Alt+1's boss deck, the Settings window - never is: thrown, as before)
			if (!dsKeep || !BoostFreeable(dsK))
				did += InStr(dsK, "/") ? DiscardCard("blade", SubStr(dsK, 1, InStr(dsK, "/") - 1)) : DiscardCard(dsK, "resources")
			else if (IsObject(BoostSaid) && !BoostSaid.Has("both|" dsK))
				BoostSaid["both|" dsK] := 1, DebugLog("  " dsK ": its plain and sharpened casts both went - its copies kept in hand: with reboost on, the next hit it fits lets it go again (said once a battle)")
			}
		}
	;Sharpen is spare once a sharpened blade has been used and no blade in hand still needs sharpening (an item card's never
	;does: it can't be enchanted)
	dsSharpUsed := 0, dsNeed := 0
	for dsI, dsK in ["blade3", "blade4", "elementalblade", "spiritblade", "storm/blade", "fire/blade", "myth/blade", "ice/blade", "life/blade", "death/blade"]
		if (UsedFlag(KeyFlags(dsK)[1]) == 1)
			dsSharpUsed := 1
	for dsI, dsK in dsKeys
		{
		dsF := KeyFlags(dsK)
		if (IsObject(BoostHand) && BoostHand.Has(dsK))
			{
			for dsC, dsF in BoostHand[dsK]
				if (!dsF.item && (dsF.src = "" ? UsedFlag(KeyFlags(dsK)[1]) != 1 : !BoostSrcUsed.Has(dsK "@" dsF.src)))
					dsNeed := 1
			}
		else if (UsedFlag(dsF[1]) != 1)
			dsNeed := 1
		}
	if (sharpen == 1) && dsSharpUsed && !dsNeed
		did += DiscardCard("sharpen", "resources")
	return did
	}

;v1.8.0 (TODO goal 3): whether this wizard's used flags stay its own all battle - set to Hitter (partybattle), or the party
;off. A Blader's or Healer's come back after its party's hitter's hits (Party.ahk PartyReblade - only with the party on),
;those set in a round it played alone too (before the hitter joined: PartyNoteBoosts notes them at round 0) - a copy
;thrown then would be cast again later. Decks.ahk DeckSimVals sends discardspent 0 when this says no (and reboostkeep
;0 - ReboostKeepRole, v1.9.1)
DiscardSpentRole()
	{
	return PartyBattleSet() = "hitter" || PartyRoleSet() = "off"
	}

;v1.9.1: whether DiscardSpare keeps a blade's copies once both its casts went, with reboost:1 (its both-casts rule off):
;where a hit of yours frees the blades it fits to be cast again - KillCalc.ahk ConsumeBoosts, reboost and no support:
;this is inside that test -, set to Hitter or the party off (DiscardSpentRole: a Blader's or Healer's with the party on
;throws them as before, whatever round it plays), not with Alt+2's pick (Manual: thrown as before, on purpose - its
;blades mostly go on another wizard's plate, whose casts a hit of yours doesn't free; a Bladestorm, or your own plate
;picked, would be freed too). Decks.ahk DeckSimVals sends reboostkeep by it
ReboostKeepRole()
	{
	global Manual
	return Manual != 1 && !PartySupport() && DiscardSpentRole()
	}

;v1.9.1: whether a hit of yours can still free blade key's deck casts (KillCalc.ahk ConsumeBoosts frees the flags
;of the AppliedBlades / BoostUnrec entries it uses up): its plain or sharpened entry, not a treasure or item copy's
;('@'), still there. Always so with reboost on all battle, as a Hitter or with the party off (each deck cast adds one -
;UseBlade -, and a hit that takes it frees its flag); not when reboost came on in the battle after a hit used both up
BoostFreeable(key)
	{
	global AppliedBlades, BoostUnrec
	if (IsObject(AppliedBlades) && (AppliedBlades.Has(key) || AppliedBlades.Has(key "+")))
		return true
	for bfI, bfK in (IsObject(BoostUnrec) ? BoostUnrec : [])
		if (bfK = key || bfK = key "+")
			return true
	return false
	}

;v1.8.0 (TODO goal 3): whether DiscardSpent runs this look - else DiscardSpare's both-casts rule, as before (v1.9.1:
;not with reboost:1 where ReboostKeepRole says so - the copies kept).
;discardspent:1 under "Discard cards it never plays" (discardunused); reboost off (with reboost:1 a hit frees its blades
;and traps - KillCalc.ahk ConsumeBoosts); the game's hand read this look (BoostMemOk: each copy's kind and boosts -
;BoostSearch's BoostHand) and its card boxes seen lining up with the screen's (KillCalc.ahk MemBoxLinedUp: the right-click
;goes by a box laid on the game's cards by its place in the hand); not dual mode (two windows, one set of used flags);
;DiscardSpentRole
DiscardSpentOn()
	{
	global BoostMemOk, DualBattle, dualmode
	return Stat("discardspent") == 1 && Stat("discardunused") && Stat("reboost") != 1 && BoostMemOk == 1
		&& DualBattle != 1 && dualmode != 1 && DiscardSpentRole() && MemBoxLinedUp()
	}

;v1.8.0: the worn deck's Sharpen and Potent cards (main side and item cards - a pet's Sharpened Blade) - the helper's
;/deckkinds, from its last reading of the decks (never a fresh read: it answers in a battle), asked once a battle
;(DeckSharp, emptied by ResetVariables): {sharpen, potent}, each "" not known - no reading, an older helper, another deck
;worn since the reading (its signature: sig 0) -: then only one in hand keeps a copy back. Said once a battle
DiscardSpentDeck()
	{
	global VisionOn, VisionErr
	local ddsA, ddsF, ddsOut, ddsWhy
	ddsOut := V1Obj({sharpen: "", potent: ""})
	ddsA := VisionOn ? Trim(VisionGet("/deckkinds", 600, true), " `r`n") : ""
	ddsF := StrSplit(ddsA, "|")
	if (V1At(ddsF, 1) = "kinds" && ddsF.Length >= 5 && V1IsNum(ddsF[2]) && V1IsNum(ddsF[3]) && ddsF[4] != "0")
		{
		ddsOut.sharpen := ddsF[2] + 0, ddsOut.potent := ddsF[3] + 0
		DebugLog("  spent copies: the worn deck holds " ddsOut.sharpen " Sharpen and " ddsOut.potent " Potent card(s) (the helper's reading, " ddsF[5] " s old"
			. (ddsF[4] = "" ? ", its signature not checked" : "") ") - a blade's or trap's copy kept back while one may still come")
		return ddsOut
		}
	ddsWhy := (ddsA = "") ? (VisionErr != "" ? VisionErr : "no answer") : (V1At(ddsF, 4) = "0") ? "another deck worn since the helper's reading" : SubStr(ddsA, 6)
	DebugLog("  spent copies: the worn deck's Sharpen and Potent cards not known (" ddsWhy ") - only one in hand keeps a copy back")
	return ddsOut
	}

;v1.8.0: how many of kind's ("blade" / "trap") keys have had their sharpened / potent cast this battle (Use1 set - each a
;Sharpen / Potent spent): DiscardSpent's count of the deck's still to come
DiscardSpentSharpened(kind)
	{
	dssN := 0
	for dssI, dssK in ["feint", "elementaltrap", "trap3", "trap4", "elementalblade", "blade3", "blade4", "spiritblade", "spirittrap"
		, "storm/blade", "storm/trap", "fire/blade", "fire/trap", "myth/blade", "myth/trap", "ice/blade", "ice/trap"
		, "life/blade", "life/trap", "death/blade", "death/trap"]
		if (BoostKind(dssK) = kind && UsedFlag(KeyFlags(dssK)[1]) == 1)
			dssN += 1
	return dssN
	}

;v1.8.0 (TODO goal 3 - discardspent, on): a blade's or trap's copies in hand past the casts its key has left this battle
;can't go - right-clicked away, one a key a look (the discard step looks again after each one: at most 3 looks a round -
;Discards), not counted in discardmax. The casts left (KeyFlags: the deck's copies share them): the plain one while its
;Use2 isn't set; the sharpened / potent one while its Use1 isn't and a Sharpen / Potent is in hand, a copy carries an
;enchantment already, or the worn deck holds one still to come (DiscardSpentDeck less DiscardSpentSharpened) - KillCalc.ahk
;BoostCopyCanGo's rule and the cast it would make later. Only the deck's copies the game's hand reads for sure as the key's
;(BoostSureOf - each card under one key) count and go - a treasure or item card's never (once a battle each:
;BoostSrcUsed) -, by their card box (KillCalc.ahk BoostMemDiscard: one with no enchantment first, the weakest); not a kind
;switched off (DiscardSwitchedOff's), nothing while you play or the bot's off. A key it settles goes into done (DiscardSpare's
;both-casts rule leaves it); one it can't - copies not sure, no box, a treasure card's lavender, a right-click that didn't
;take (as many copies the next look: off for the battle - SpentOff) - is left to that rule. Returns how many
DiscardSpent(done)
	{
	global
	local dspDid := 0, dspK, dspCps, dspF, dspKind, dspI, dspC, dspDeck, dspEnc, dspLeft, dspAt, dspSay, dspSeen, dspSure
	local dspCome, dspHas
	if (!BotOn || !IsObject(BoostHand) || PlayerActing())
		return 0
	if (!IsObject(DeckSharp))
		DeckSharp := DiscardSpentDeck()
	if (!IsObject(SpentOff))
		SpentOff := V1Obj()
	if (!IsObject(SpentLook))
		SpentLook := V1Obj()
	dspSeen := V1Obj()
	for dspK, dspCps in BoostHand
		{
		dspF := KeyFlags(dspK), dspKind := BoostKind(dspK)
		if (!IsObject(dspF) || !IsObject(dspCps) || dspKind = "" || (dspKind = "blade" && !Stat("useblades"))
			|| (dspKind = "trap" && !Stat("usetraps")))
			continue
		;(its right-click didn't take earlier this battle - SpentOff -, or no box for it this round - SpentLook "fail": the
		;both-casts rule's)
		if (SpentOff.Has(dspK) || (SpentLook.Has(dspK) && SpentLook[dspK] = "fail"))
			continue
		;(only copies read for sure as this key's - BoostMatches' fallbacks (boosts not read, an every-school card at another
		;%) aren't -, each card of the game's hand under one key)
		dspDeck := 0, dspEnc := 0, dspSure := true
		for dspI, dspC in dspCps
			{
			if (!IsObject(dspC) || dspC.src != "")
				continue
			if (dspC.sure != 1 || dspSeen.Has(dspC.n))
				{
				dspSure := false
				break
				}
			dspSeen[dspC.n] := 1, dspDeck += 1, dspEnc += (dspC.ench = 1) ? 1 : 0
			}
		if (!dspSure)
			{
			if (IsObject(BoostSaid) && !BoostSaid.Has("spent|" dspK "|unsure"))
				BoostSaid["spent|" dspK "|unsure"] := 1, DebugLog("  spent copies of " dspK ": the game's hand doesn't say for sure which cards are its copies - the both-casts rule's (said once a battle)")
			continue
			}
		;(clicked an earlier look this round and as many copies now - SpentLook, emptied at each RoundStart: the right-click
		;didn't take - the game refused it, or it missed: this key is the both-casts rule's for the rest of the battle)
		if (SpentLook.Has(dspK) && dspDeck >= SpentLook[dspK])
			{
			SpentOff[dspK] := 1
			DebugLog("  spent copies of " dspK ": " dspDeck " in hand after a right-click on one - it didn't go; not tried again this battle")
			continue
			}
		dspLeft := (UsedFlag(dspF[2]) != 1) ? 1 : 0
		dspHas := IsObject(DeckSharp) ? (dspKind = "trap" ? DeckSharp.potent : DeckSharp.sharpen) : ""
		;(a treasure card drawn this battle - Draw.ahk DrawsBattle: a Use1 may have been a treasure Sharpen's / Potent's,
		;so the deck's count isn't counted down - a copy kept longer. One you drew in a round you played isn't known: then a
		;copy can go too early)
		dspCome := V1IsNum(dspHas) && dspHas - (V1N(DrawsBattle) ? 0 : DiscardSpentSharpened(dspKind)) > 0
		if (UsedFlag(dspF[1]) != 1 && ((dspKind = "trap" ? potent : sharpen) == 1 || dspEnc || dspCome))
			dspLeft += 1
		done[dspK] := 1
		if (dspDeck <= dspLeft)
			continue
		dspAt := BoostMemDiscard(dspK, 1)
		if (dspAt.x = "" || (V1IsFunc("DiscardIsTc") && DiscardIsTc(dspAt.x)))
			{
			;(not this round again; the both-casts rule may take it now - said once a battle per reason)
			done.Delete(dspK), SpentLook[dspK] := "fail"
			dspSay := (dspAt.x = "") ? dspAt.why : "card " dspAt.n " of " dspAt.of " looks like a treasure card"
			if (IsObject(BoostSaid) && !BoostSaid.Has("spent|" dspK "|" dspSay))
				BoostSaid["spent|" dspK "|" dspSay] := 1, DebugLog("  spent copies of " dspK ": " dspDeck " in hand, "
					. dspLeft " cast" (dspLeft = 1 ? "" : "s") " left this battle - not discarded: " dspSay)
			continue
			}
		MoveToCard(dspAt.x, dspAt.y)
		s(Stats.Has("clickwait") ? Stats["clickwait"] : 40)
		;(Wizard101 gone to the tray - Settings: traygame: not clicked - it would land on the window behind it)
		if (GameInTray)
			break
		Click("right")
		SpentLook[dspK] := dspDeck
		;(the hand has changed: a fresh look for the next key's box and the next pass)
		VisionForget()
		s(Stat("discardafter"))
		dspDid += 1
		DebugLog("  Discarded " dspAt.name " - " dspK ": " dspDeck " of the deck's copies in hand, " dspLeft " cast"
			. (dspLeft = 1 ? "" : "s") " left this battle (card " dspAt.n " of " dspAt.of ", right-click at "
			. dspAt.x - GameLeft "," dspAt.y - GameTop ")")
		}
	if (dspDid)
		CenterMouse()
	return dspDid
	}

;Right-clicks one card in hand to discard it. Returns 1 if it was found
;v1.0.0: a blade no picture finds but the game's hand has (KillCalc.ahk BoostSearch's BoostMemOnly - DiscardSpare's spare
;blades) at its card box, laid on the game's cards as UseBlade casts one (KillCalc.ahk BoostMemDiscard - the deck's copy,
;never a treasure card): before, one was never discarded and stayed in hand
DiscardCard(title, dir)
	{
	global
	local card := 0, cardX := 0, cardY := 0, dcKey, dcAt
	Find(title, &card, &cardX, &cardY, &dir)
	dcKey := BoostKey(title, dir)
	if (card != 1 && IsObject(BoostMemOnly) && BoostMemOnly.Has(dcKey))
		{
		dcAt := BoostMemDiscard(dcKey)
		if (dcAt.x = "")
			{
			DebugLog("  " dcKey ": in hand (the game), no picture found it - not discarded: " dcAt.why)
			return 0
			}
		;(as Find's: the right-click goes Px(5) on from it)
		card := 1, cardX := dcAt.x - Px(5), cardY := dcAt.y - Px(5)
		DebugLog("  " dcKey ": no picture found it - the game's " dcAt.name " is card " dcAt.n " of " dcAt.of " in hand: discarded at its box")
		}
	if (card != 1)
		return 0
	;(never a treasure card - discarding one uses it up: one drawn for an enchant (Draw.ahk) looks like the deck's)
	if (V1IsFunc("DiscardIsTc") && DiscardIsTc(cardX + Px(5)))
		{
		DebugLog("  " title " not discarded: it's a treasure card")
		return 0
		}
	MoveToCard(cardX + Px(5), cardY + Px(5))
	s(Stats.Has("clickwait") ? Stats["clickwait"] : 40)
	;(Wizard101 gone to the tray - Settings: traygame: not clicked - it would land on the window behind it)
	if (GameInTray)
		return 0
	Click("right")
	;(the hand has changed: a fresh look next time, not the vision helper's picture of it from before)
	VisionForget()
	s(Stat("discardafter"))
	DebugLog("  Discarded " title " (right-click at " cardX - GameLeft "," cardY - GameTop ")")
	return 1
	}

;A boost card was just put on the card at fx,fy: the hand re-centres. Looks for the card where it slides
;to every 100 ms (from 250 ms on) and goes once it's in the same spot twice running - the slide is over -
;instead of a fixed 1.5 s; not seen by then: RefindAfterBoost's guess
BoostSettle(n, &fx, &fy, boostX)
	{
	global
	local expX, nx, ny, lastX := "", lastY := "", t0 := A_TickCount
	expX := fx + (fx < boostX ? HalfPitch : -HalfPitch)
	Sleep(250)
	while (A_TickCount - t0 < 1500)
		{
		V1ImageSearch(&nx, &ny, expX - Px(30), fy - Px(25), expX + Px(50), fy + Px(40), PicOptFile(n, CardTol))
		if (ErrorLevel = 0)
			{
			if (nx = lastX && ny = lastY)
				{
				DebugLog("    card moved from " fx - GameLeft "," fy - GameTop " to " nx - GameLeft "," ny - GameTop " (settled in " A_TickCount - t0 " ms)")
				fx := nx, fy := ny
				return
				}
			lastX := nx, lastY := ny
			}
		Sleep(100)
		}
	RefindAfterBoost(n, &fx, &fy, boostX)
	}

;A boost card (enchant, Sharpen or Potent) was just put on the card at fx,fy and left the hand.
;The hand re-centres: cards left of the boost card slide right by half a card, cards right of it
;slide left. Looks for the card where it should be now; if it can't be seen there, uses that spot
RefindAfterBoost(n, &fx, &fy, boostX)
	{
	global
	local expX, nx, ny
	expX := fx + (fx < boostX ? HalfPitch : -HalfPitch)
	V1ImageSearch(&nx, &ny, expX - Px(30), fy - Px(25), expX + Px(50), fy + Px(40), PicOptFile(n, CardTol))
	if (ErrorLevel = 0)
		{
		DebugLog("    card moved from " fx - GameLeft "," fy - GameTop " to " nx - GameLeft "," ny - GameTop)
		fx := nx, fy := ny
		}
	else
		{
		DebugLog("    card not seen after the hand moved, using where it should be: " expX - GameLeft "," fy - GameTop)
		fx := expX
		}
	}

;A Sharpen or Potent was just put on the card at fx, fy that no picture finds - one cast by the game's hand (UseBlade,
;UseTrap: BoostMemOnly) - and the hand re-centres: where the game's hand has boost key's card once it's settled (a fresh
;look at the hand's boxes laid on the game's cards - KillCalc.ahk BoostMemBox): the copy with the enchantment on it, else a
;copy of it that's there (the enchant didn't take); neither (they don't line up): where it should be, as RefindAfterBoost
BoostSettleMem(key, &fx, &fy, boostX)
	{
	global
	local bsmExp, bsmAt, bsmT0 := A_TickCount
	bsmExp := fx + (fx < boostX ? HalfPitch : -HalfPitch)
	Sleep(250)
	VisionForget()
	bsmAt := BoostMemBox(key, 0, "", "", 1, 1500)
	if (bsmAt.x = "")
		{
		VisionForget()
		bsmAt := BoostMemBox(key, 0, "", "", 0, 1500)
		}
	if (bsmAt.x != "")
		{
		DebugLog("    card moved from " fx - GameLeft "," fy - GameTop " to " bsmAt.x - GameLeft "," bsmAt.y - GameTop " (the game's hand: card " bsmAt.n " of " bsmAt.of ", " A_TickCount - bsmT0 " ms)")
		fx := bsmAt.x, fy := bsmAt.y
		return
		}
	DebugLog("    card not found in the game's hand after it moved (" bsmAt.why "), using where it should be: " bsmExp - GameLeft "," fy - GameTop)
	fx := bsmExp
	}

;Reads the wizard's stats off the Spellbook (StatsRead.ahk) into PlayerStats.txt and reloads them,
;out of battle: by itself when the wizard logged in now (whose school it knows from a battle) has no
;<school>.damage yet, or the ones there are from another character of that school - at most every 30
;minutes per character - or when asked (StatsWanted). Only with the game in front and nobody having
;touched the mouse or keyboard for 5 s, since it clicks through the book
StatsAuto()
	{
	static triedAt := V1Obj()
	global StatsWanted, SrHandsOff ; (v1 globals it sets)
	;(cheap checks first: this runs on every pass out of battle)
	if (!StatsWanted && SrBattleSchool = "")
		return
	if (UserIdle() < 5000 || afkVar || loopmode || loremode || !WinActive("ahk_class " GameClass " ahk_exe " GameExe))
		return
	;The school of the wizard logged in now: the last battle's if that was this character (it may have
	;switched since), else the one noted for it before
	charNow := StatsCharID()
	statsFor := (charNow != "" && charNow = SrBattleChar) ? SrBattleSchool : StatsSchoolOf(charNow)
	if (statsFor = "" && !StatsWanted)
		return
	need := StatsWanted || !Stats.Has(statsFor ".damage") || (charNow != "" && Stats[statsFor ".charid"] != charNow)
	tryKey := charNow "|" statsFor
	if (!need || (!StatsWanted && triedAt.Has(tryKey) && A_TickCount - triedAt[tryKey] < 1800000))
		return
	if (KeysDown || HeldW)
		ReleaseKeys()
	triedAt[tryKey] := A_TickCount, StatsWanted := 0
	;(it stops if you touch the mouse or keyboard while it reads)
	SrHandsOff := 1
	DebugLog("Stats: reading the " (statsFor = "" ? "wizard's" : statsFor " wizard's") " stats off the Spellbook (character " (charNow = "" ? "?" : charNow) ", UI scale " Round(UiScale, 3) ")")
	err := StatsRead(&statsFor, &statsGot)
	if (err != "")
		{
		DebugLog("Stats: " err)
		TrayTip("Couldn't read your stats: " err, "Wizard101 bot", 2)
		return
		}
	msg := StatsWrite(statsGot, statsFor, charNow)
	;(Critical, as CfgWrite and LearnStatsWrite: no timer - the overlay's OvTick, PartyTimer - reads Stats half
	;reloaded, its built-in defaults - overlay:0 - before PlayerStats.txt's lines)
	wasCrit := A_IsCritical
	Critical()
	LoadStats(true)
	CfgUncritical(wasCrit, 0)
	DebugLog("Stats: " StrReplace(msg, "`n", " "))
	TrayTip(msg, "Wizard101 bot", 1)
	}

;On exit: stop the vision helper too (it would stop by itself within 5 s anyway)
VisionOnExit(reason, code)
	{
	local v1Keep := V1Thread() ; (v1: each thread had its own ErrorLevel)
	VisionStop()
	}

;StatsReader.ahk was started while this runs: it asks this script to read them (no two scripts
;clicking at once)
StatsAsked(wParam, lParam, msg, hwnd)
	{
	global StatsWanted ; (v1 globals it sets)
	StatsWanted := 1
	TrayTip("Reading your stats at the next quiet moment out of battle (hands off the mouse and keys for 5 s).", "Wizard101 bot", 1)
	return 1
	}

;Saves the game as a picture (BMP) for cutting new pictures from, in the Windows temp folder
;("Wizard101 bot rounds"), keeping the newest 25. Returns the file name, or "" if it couldn't
SaveRoundPicture()
	{
	dir := A_Temp "\Wizard101 bot rounds"
	V1Do(DirCreate, dir)
	files := ""
	Loop Files, dir "\round_*.bmp"
		files .= A_LoopFileName "`n"
	files := Sort(files)
	list := StrSplit(Trim(files, "`n"), "`n")
	while (list.Length >= 25)
		V1Do(FileDelete, dir "\" list.RemoveAt(1))
	if (!ArrowCapture(GameLeft, GameTop, GameW, GameH, &pix))
		return ""
	stamp := FormatTime(, "yyyyMMdd_HHmmss")
	path := dir "\round_" stamp ".bmp"
	;(v1: FileOpen gave no object when it couldn't - v2 throws)
	bmp := V1Try(FileOpen, path, "w")
	if (!IsObject(bmp))
		return ""
	bmp.WriteUShort(0x4D42), bmp.WriteUInt(54 + GameW * GameH * 4), bmp.WriteUInt(0), bmp.WriteUInt(54)
	bmp.WriteUInt(40), bmp.WriteInt(GameW), bmp.WriteInt(-GameH), bmp.WriteUShort(1), bmp.WriteUShort(32)
	bmp.WriteUInt(0), bmp.WriteUInt(GameW * GameH * 4), bmp.WriteInt(2835), bmp.WriteInt(2835), bmp.WriteUInt(0), bmp.WriteUInt(0)
	bmp.RawWrite(pix, GameW * GameH * 4)
	bmp.Close()
	return path
	}

;Appends a timestamped line to debug.log next to this script (and to its copy on OneDrive: LogMirrorDir)
DebugLog(msg)
	{
	global ErrorLevel ; (v1 globals it sets)
	now := FormatTime(, "HH:mm:ss")
	;(v1's FileAppend set ErrorLevel - 0, or 1 when the line couldn't be written, e.g. the log held open by another
	;program: a log line resets it - the main loop's startErr; v2's throws instead)
	ErrorLevel := V1Do(FileAppend, now " " msg "`r`n", A_ScriptDir "\debug.log")
	lmTo := LogMirrorDir(&lmFresh)
	if (lmTo != "" && !lmFresh)
		V1Do(FileAppend, now " " msg "`r`n", lmTo "\debug.log")
	;(and onto the dashboard's log)
	if (DashHwnd)
		DashLog(now " " msg)
	;(the battle recorder: a line of a round open kept for it - BattleRec.ahk; ErrorLevel untouched)
	if (V1IsFunc("BrecNote"))
		BrecNote.Call(msg)
	;(the overlay over the game: the line kept for its next picture - Overlay.ahk; nothing drawn here, ErrorLevel untouched)
	if (V1IsFunc("OvLogNote"))
		OvLogNote.Call(now " " msg)
	}

;The log copied to OneDrive as well (logmirror:1 - Settings, ALERTS), for help from another PC (OneDrive syncs it
;there): <OneDrive>\Wiz-Maxxing logs\<this PC's name>\ - debug.log line by line (when it's switched on, the run so far
;and debug.previous.log are copied over first), and pictures of the game (LogMirrorSnap). The folder, or "" when it's
;off or this PC has no OneDrive folder; fresh: 1 when it was switched on just now (the log copied, this line in it)
LogMirrorDir(&fresh := 0)
	{
	static lmDir := "", lmOn := 0
	fresh := 0
	if (!(IsObject(Stats) && Stats.Has("logmirror") && Stats["logmirror"]))  ; (v1: Stats not made yet - HkApply's log line - .HasKey of a blank: blank)
		{
		lmOn := 0
		return ""
		}
	if (!lmOn)
		{
		lmOn := 1, lmDir := ""
		;(your own OneDrive first - a work account's is %OneDrive% too)
		od := EnvGet("OneDriveConsumer")
		if (od = "" || !InStr(FileExist(od), "D"))
			od := EnvGet("OneDrive")
		now := FormatTime(, "HH:mm:ss")
		if (od != "" && InStr(FileExist(od), "D"))
			{
			lmDir := od "\Wiz-Maxxing logs\" A_ComputerName
			V1Do(DirCreate, lmDir)
			V1Do(FileAppend, now " Log copy: on - " lmDir "`r`n", A_ScriptDir "\debug.log")
			V1Do(FileCopy, A_ScriptDir "\debug.previous.log", lmDir "\debug.previous.log", 1)
			V1Do(FileCopy, A_ScriptDir "\debug.log", lmDir "\debug.log", 1)
			fresh := 1
			}
		else
			V1Do(FileAppend, now " Log copy: no OneDrive folder on this PC - not copied`r`n", A_ScriptDir "\debug.log")
		}
	return lmDir
	}

;A picture of the game into the log's OneDrive copy (snap_<when>.jpg, the newest 15 kept; the vision helper makes
;it): every: at most this often (ms) - out of battle and at a round's start every 2 minutes, an alert's at once (kind:
;the alert's). Only the game itself: its window there and not minimised with nothing else's over it (the bot's own may
;be: LogMirrorGameShown), in its world - its spellbook or a battle's Pass button on screen, never the login screen -
;and no reconnect under way (nor for a reconnect alert)
LogMirrorSnap(every := 0, kind := "")
	{
	static lmLast := 0
	if (every && lmLast && A_TickCount - lmLast < every)
		return
	if (InStr(kind, "reconnect") || RcState != "")
		return
	lmTo := LogMirrorDir()
	if (lmTo = "" || !VisionOn || !LogMirrorGameShown())
		return
	V1ImageSearch(&lmX, &lmY, GameLeft, GameTop, GameRight, GameBottom, PicOpt("resources\roundfinish.png"))
	if (ErrorLevel)
		{
		V1ImageSearch(&lmX, &lmY, GameLeft, GameTop, GameRight, GameBottom, PicOpt("resources\roundstart.png"))
		if (ErrorLevel)
			return
		}
	lmLast := A_TickCount
	stamp := FormatTime(A_NowUTC, "yyyyMMdd_HHmmss")
	VisionGet("/snap?x1=" GameLeft "&y1=" GameTop "&x2=" GameLeft + GameW "&y2=" GameTop + GameH "&keep=15&out=" NavUri(lmTo "\snap_" stamp ".jpg"), 3000, true)
	}

;The game's window is up, not minimised, and on top over the game area: at its middle, corners and edges the window
;there is the game's (or one of the bot's own - its notices, the dashboard)
LogMirrorGameShown()
	{
	;(v1: no such window - blank; v2 throws)
	g := V1Try(WinGetID, "ahk_class " GameClass " ahk_exe " GameExe)
	if (!g || DllCall("IsIconic", "Ptr", g) || GameW <= 0 || GameH <= 0)
		return false
	me := DllCall("GetCurrentProcessId")
	for i, f in [[0.5, 0.5], [0.05, 0.05], [0.5, 0.05], [0.95, 0.05], [0.05, 0.5], [0.95, 0.5], [0.05, 0.95], [0.5, 0.95], [0.95, 0.95]]
		{
		x := GameLeft + Round(GameW * f[1]), y := GameTop + Round(GameH * f[2])
		w := DllCall("WindowFromPoint", "Int64", (y << 32) | (x & 0xFFFFFFFF), "Ptr")
		top := w ? DllCall("GetAncestor", "Ptr", w, "UInt", 2, "Ptr") : 0
		if (top = g)
			continue
		pid := V1Try(WinGetPID, "ahk_id " top)
		if (!top || pid != me)
			return false
		}
	return true
	}

#Include "%A_ScriptDir%\Ocr.ahk"
#Include "%A_ScriptDir%\KillCalc.ahk"
#Include "%A_ScriptDir%\Reconnect.ahk"
#Include "%A_ScriptDir%\PicScale.ahk"
#Include "%A_ScriptDir%\StatsRead.ahk"
#Include "%A_ScriptDir%\Vision.ahk"
#Include "%A_ScriptDir%\CardLearn.ahk"
#Include "%A_ScriptDir%\Potions.ahk"
#Include "%A_ScriptDir%\Flee.ahk"
#Include "%A_ScriptDir%\Draw.ahk"
#Include "%A_ScriptDir%\EnemySpells.ahk"
#Include "%A_ScriptDir%\BattleRec.ahk"
#Include "%A_ScriptDir%\Planner.ahk"
#Include "%A_ScriptDir%\Party.ahk"
#Include "%A_ScriptDir%\Settings.ahk"
#Include "%A_ScriptDir%\SettingsFile.ahk"
#Include "%A_ScriptDir%\Alerts.ahk"
#Include "%A_ScriptDir%\Dashboard.ahk"
#Include "%A_ScriptDir%\BugReport.ahk"
#Include "%A_ScriptDir%\Dungeons.ahk"
#Include "%A_ScriptDir%\Collect.ahk"
#Include "%A_ScriptDir%\Puzzle.ahk"
#Include "%A_ScriptDir%\Network.ahk"
#Include "%A_ScriptDir%\Decks.ahk"
#Include "%A_ScriptDir%\Training.ahk"
#Include "%A_ScriptDir%\QuickSell.ahk"
#Include "%A_ScriptDir%\Gear.ahk"
#Include "%A_ScriptDir%\Hotkeys.ahk"
#Include "%A_ScriptDir%\Spells.ahk"
#Include "%A_ScriptDir%\Overlay.ahk"
#Include "%A_ScriptDir%\..\AutoQuester\Walker.ahk"
#Include "%A_ScriptDir%\..\AutoQuester\ArrowReader.ahk"
#Include "%A_ScriptDir%\..\Watch.ahk"
#Include "%A_ScriptDir%\..\CheatEngine.ahk"
#Include "%A_ScriptDir%\..\V1Compat.ahk" ; (v2 port: the v1 behaviours it keeps)

;###############  (v1: the labels, as functions)  ###############
MenuBotToggle(A_ThisMenuItem:="", A_ThisMenuItemPos:="", MyMenu:="", *) { ; (v1: a label)
global
local v1Keep := V1Thread() ; (v1: each thread had its own ErrorLevel)
TrayPicked(A_ThisMenuItem, MyMenu)
BotToggle()
return
}
;##############################################
MenuWalk(A_ThisMenuItem:="", A_ThisMenuItemPos:="", MyMenu:="", *) { ; (v1: a label)
global
local v1Keep := V1Thread() ; (v1: each thread had its own ErrorLevel)
TrayPicked(A_ThisMenuItem, MyMenu)
WalkToggle()
return
}
;##############################################
MenuWatch(A_ThisMenuItem:="", A_ThisMenuItemPos:="", MyMenu:="", *) { ; (v1: a label)
global
local v1Keep := V1Thread() ; (v1: each thread had its own ErrorLevel)
TrayPicked(A_ThisMenuItem, MyMenu)
SplitPath(A_ScriptDir, , &watchRoot)
watchOn := !WatchIsOn()
if (WatchSet(watchRoot, watchOn))
	TrayTip(watchOn ? "The bot now opens by itself when Wizard101 starts - in standby: " HkText("bot") " starts it." : "The bot won't open by itself with Wizard101 any more.", "Wizard101 bot", 1)
else
	TrayTip("Couldn't change `"Open with Wizard101`" (the Startup folder's shortcut).", "Wizard101 bot", 2)
WatchShow()
return
}
;##############################################
MenuReconnect(A_ThisMenuItem:="", A_ThisMenuItemPos:="", MyMenu:="", *) { ; (v1: a label)
global
local v1Keep := V1Thread() ; (v1: each thread had its own ErrorLevel)
local v1Own := V1Thread()  ; (v1: a menu item ran as a thread of its own, with its own ErrorLevel - it logs or writes an ini)
TrayPicked(A_ThisMenuItem, MyMenu)
ReconnectToggle()
return
}
;##############################################
MenuHandsOff(A_ThisMenuItem:="", A_ThisMenuItemPos:="", MyMenu:="", *) { ; (v1: a label)
global
local v1Keep := V1Thread() ; (v1: each thread had its own ErrorLevel)
TrayPicked(A_ThisMenuItem, MyMenu)
HandsOffToggle()
return
}
;##############################################
MenuPlayForMe(A_ThisMenuItem:="", A_ThisMenuItemPos:="", MyMenu:="", *) { ; (v1: a label)
global
local v1Keep := V1Thread() ; (v1: each thread had its own ErrorLevel)
TrayPicked(A_ThisMenuItem, MyMenu)
PlayForMeToggle()
return
}
;##############################################
;(the tray menu's Battles only - Settings: battlesonly)
MenuBattlesOnly(A_ThisMenuItem:="", A_ThisMenuItemPos:="", MyMenu:="", *)
	{
	local v1Keep := V1Thread() ; (v1: each thread had its own ErrorLevel)
	TrayPicked(A_ThisMenuItem, MyMenu)
	BattlesOnlyToggle()
	}
;##############################################
MenuGameFront(A_ThisMenuItem:="", A_ThisMenuItemPos:="", MyMenu:="", *) { ; (v1: a label)
global
local v1Keep := V1Thread() ; (v1: each thread had its own ErrorLevel)
TrayPicked(A_ThisMenuItem, MyMenu)
GameFrontToggle()
return
}
;##############################################
MenuLearnAll(A_ThisMenuItem:="", A_ThisMenuItemPos:="", MyMenu:="", *) { ; (v1: a label)
global
local v1Keep := V1Thread() ; (v1: each thread had its own ErrorLevel)
TrayPicked(A_ThisMenuItem, MyMenu)
LearnAllToggle()
return
}
;##############################################
MenuStats(A_ThisMenuItem:="", A_ThisMenuItemPos:="", MyMenu:="", *) { ; (v1: a label)
global
TrayPicked(A_ThisMenuItem, MyMenu)
StatsWanted := 1
TrayTip("Reading your stats at the next quiet moment out of battle (hands off the mouse and keys for 5 s).", "Wizard101 bot", 1)
return
}
;##############################################
MenuDash(A_ThisMenuItem:="", A_ThisMenuItemPos:="", MyMenu:="", *) { ; (v1: a label)
global
local v1Keep := V1Thread() ; (v1: each thread had its own ErrorLevel)
TrayPicked(A_ThisMenuItem, MyMenu)
DashToggle()
return
}
;##############################################
MenuSpells(A_ThisMenuItem:="", A_ThisMenuItemPos:="", MyMenu:="", *) { ; (v1: a label)
global
local v1Keep := V1Thread() ; (v1: each thread had its own ErrorLevel)
TrayPicked(A_ThisMenuItem, MyMenu)
SpShowTab()
return
}
;##############################################
MenuSettings(A_ThisMenuItem:="", A_ThisMenuItemPos:="", MyMenu:="", *) { ; (v1: a label)
global
local v1Keep := V1Thread() ; (v1: each thread had its own ErrorLevel)
local v1Own := V1Thread()  ; (v1: a menu item ran as a thread of its own, with its own ErrorLevel - it logs or writes an ini)
TrayPicked(A_ThisMenuItem, MyMenu)
CfgShow()
return
}
;##############################################
MenuSpeedKeyFast(A_ThisMenuItem:="", A_ThisMenuItemPos:="", MyMenu:="", *) { ; (v1: a label - it fell into MenuSpeedKeyNormal's lines)
global
local v1Keep := V1Thread() ; (v1: each thread had its own ErrorLevel)
TrayPicked(A_ThisMenuItem, MyMenu)
MenuSpeedKey(true)
}
;##############################################
MenuSpeedKeyNormal(A_ThisMenuItem:="", A_ThisMenuItemPos:="", MyMenu:="", *) { ; (v1: a label)
global
local v1Keep := V1Thread() ; (v1: each thread had its own ErrorLevel)
TrayPicked(A_ThisMenuItem, MyMenu)
MenuSpeedKey(false)
}
;(v1: the lines of the labels MenuSpeedKeyFast / MenuSpeedKeyNormal, told apart by A_ThisLabel = "MenuSpeedKeyFast" - fast)
MenuSpeedKey(fast) {
global
speedKeyName := SpeedKey(fast)
TrayTip("Click into Cheat Engine's hotkey box now - " speedKeyName " is pressed in 3 seconds.", "Wizard101 bot", 1)
Sleep(3000)
Send("{" speedKeyName " down}")
Sleep(250)
Send("{" speedKeyName " up}")
;(if Cheat Engine already has it: the game's at that speed now - only with the speedhack setting on. Off, the key is
;for Cheat Engine's hotkey box, and a walking speed counted then held the mouse's turns back till the next stop)
if (SpeedSetting())
	SpeedNow := fast ? SpeedFactor() : 1
SpeedSentAt := A_TickCount
DebugLog("Speedhack: " speedKeyName " pressed (for Cheat Engine's hotkey box)")
return
}
;Cheat Engine for the speedhack (Settings: speedhack on), when Setup's "Cheat Engine speedhack" put the bot's script in it
;(CheatEngine.ahk): started if it isn't running, its window minimized once it shows (7.4 / 7.5 ask for admin first - the
;bot doesn't wait for the answer) - and the script attaches it to Wizard101 and sets the bot's speed keys by itself.
;Without the script it's yours to start, attach and set up, as before (said once a run). Cheat Engine's copy of the
;script not the one this bot's Setup puts in (CeScriptText - an older version's, say, which still speeds the newest game
;window): said once a run, in debug.log only. why: for debug.log
SpeedCheatEngine(why) {
static saidNoScript := false, lookedOld := false
if (Stat("speedhack") != 1)
	return
sceDir := CeDir()
if (sceDir = "" || !FileExist(CeScriptPath(sceDir)))
	{
	if (!saidNoScript)
		saidNoScript := true, DebugLog("Speedhack: on - " (sceDir = "" ? "Cheat Engine isn't installed" : "Cheat Engine (" sceDir ") doesn't have the bot's script") ": start, attach and set it up yourself, or let Setup.exe's `"Cheat Engine speedhack`" do it")
	return
	}
if (!lookedOld)
	{
	lookedOld := true
	SplitPath(A_ScriptDir, , &sceRoot)
	sceWant := CeScriptText(sceRoot)
	if (sceWant != "" && V1FileRead(CeScriptPath(sceDir), "UTF-8") !== sceWant)
		DebugLog("Speedhack: on - Cheat Engine's Wiz-Maxxing script is older - run Setup.exe, tick Cheat Engine speedhack, Install, then restart Cheat Engine")
	}
if (CeRunning())
	return DebugLog("Speedhack: on - Cheat Engine is running, the bot's script in it (" why ")")
DebugLog("Speedhack: on - " (CeStart(sceDir) ? "starting Cheat Engine (" CeExe(sceDir) "), its window minimized once it shows - Cheat Engine 7.4 / 7.5 ask for admin first: say Yes (the bot doesn't wait)" : "Cheat Engine (" CeExe(sceDir) ") couldn't be started") " (" why "). Its Wiz-Maxxing script attaches it to Wizard101 and sets the speed keys")
}
;##############################################
MenuMap(A_ThisMenuItem:="", A_ThisMenuItemPos:="", MyMenu:="", *) { ; (v1: a label)
global
local v1Keep := V1Thread() ; (v1: each thread had its own ErrorLevel)
local v1Own := V1Thread()  ; (v1: a menu item ran as a thread of its own, with its own ErrorLevel - it logs or writes an ini)
TrayPicked(A_ThisMenuItem, MyMenu)
DashMapToggle()
return
}
;##############################################
;(the tray menu's / Windows+4's overlay over the game - Settings: overlay; Overlay.ahk)
MenuOverlay(A_ThisMenuItem:="", A_ThisMenuItemPos:="", MyMenu:="", *)
	{
	local v1Keep := V1Thread() ; (v1: each thread had its own ErrorLevel)
	TrayPicked(A_ThisMenuItem, MyMenu)
	OverlayToggle()
	}
;##############################################
MenuUpdates(A_ThisMenuItem:="", A_ThisMenuItemPos:="", MyMenu:="", *) { ; (v1: a label)
global
local v1Keep := V1Thread() ; (v1: each thread had its own ErrorLevel)
TrayPicked(A_ThisMenuItem, MyMenu)
UpdCheckNow()
return
}
;##############################################
MenuBug(A_ThisMenuItem:="", A_ThisMenuItemPos:="", MyMenu:="", *) { ; (v1: a label)
global
local v1Keep := V1Thread() ; (v1: each thread had its own ErrorLevel)
TrayPicked(A_ThisMenuItem, MyMenu)
BugShow()
return
}
;##############################################
MenuNothing(A_ThisMenuItem:="", A_ThisMenuItemPos:="", MyMenu:="", *) { ; (v1: a label)
global
return
}
;##############################################
UpdPeekNow() { ; (v1: a label)
global
local v1Keep := V1Thread() ; (v1: each thread had its own ErrorLevel)
;(only with a program that can run it: Wiz-Maxxing.exe - or, run as a script, Wiz-Maxxing.ahk by this AutoHotkey)
if (!A_IsCompiled || FileExist(A_ScriptDir "\..\Wiz-Maxxing.exe"))
	BotRun(A_ScriptDir "\..\Wiz-Maxxing", "/latest", A_ScriptDir "\..")
else
	V1Do(IniWrite, "Wiz-Maxxing.exe is missing", A_ScriptDir "\..\updater.ini", "latest", "err")
;(updating by itself - Settings: autoupdate: every that many minutes, 5 at least. Wiz-Maxxing.exe not found: again in a
;minute - 2026-10-23 23:22 it wasn't for a moment while Windows Security restarted, and the look-up waited 10 minutes)
updEvery := Stat("autoupdate") > 0 ? Max(5, Stat("autoupdate")) : 120
if (A_IsCompiled && !FileExist(A_ScriptDir "\..\Wiz-Maxxing.exe"))
	updEvery := 1
SetTimer(UpdPeekNow,-60000 * updEvery)
return
}
;##############################################
MenuPotionRoute(A_ThisMenuItem:="", A_ThisMenuItemPos:="", MyMenu:="", *) { ; (v1: a label)
global
local v1Keep := V1Thread() ; (v1: each thread had its own ErrorLevel)
TrayPicked(A_ThisMenuItem, MyMenu)
;(Wizard101 in the tray - Settings: traygame: show it first, GameTrayBlocked says so)
if (GameTrayBlocked("record potion buying"))
	return
PotionRecordStart()
return
}
;##############################################
MenuPotionRun(A_ThisMenuItem:="", A_ThisMenuItemPos:="", MyMenu:="", *) { ; (v1: a label)
global
local v1Keep := V1Thread() ; (v1: each thread had its own ErrorLevel)
TrayPicked(A_ThisMenuItem, MyMenu)
;(Wizard101 in the tray - Settings: traygame: show it first, GameTrayBlocked says so)
if (GameTrayBlocked("buy potions"))
	return
;(battles only - Settings: battlesonly: no run - its Recall or Home / End, the walk to the seller - said, a tray tip)
if (BattlesOnlyNo("run to buy potions", true))
	return
;(v1: nothing when the game isn't there - v2 throws)
V1Try(WinActivate, "ahk_class " GameClass " ahk_exe " GameExe)
Sleep(500)
;(the mouse back where it was afterwards - mousereturn)
mouseOwn := MouseGrab()
PotionManual := 1
PotionRun()
PotionManual := 0
if (mouseOwn)
	MouseLetGo()
return
}
;##############################################
MenuQuickSell(A_ThisMenuItem:="", A_ThisMenuItemPos:="", MyMenu:="", *) { ; (v1: a label)
global
local v1Keep := V1Thread() ; (v1: each thread had its own ErrorLevel)
TrayPicked(A_ThisMenuItem, MyMenu)
;(Wizard101 in the tray - Settings: traygame: show it first, GameTrayBlocked says so)
if (GameTrayBlocked("quick sell the backpack"))
	return
QsMenuNow(false)
return
}
;##############################################
MenuQuickSellRehearse(A_ThisMenuItem:="", A_ThisMenuItemPos:="", MyMenu:="", *) { ; (v1: a label)
global
local v1Keep := V1Thread() ; (v1: each thread had its own ErrorLevel)
TrayPicked(A_ThisMenuItem, MyMenu)
;(Wizard101 in the tray - Settings: traygame: show it first, GameTrayBlocked says so)
if (GameTrayBlocked("quick sell the backpack"))
	return
QsMenuNow(true)
return
}
;##############################################
;A hidden always-on-top window owning the boxes this thread opens from now on (InputBox, MsgBox: Gui +OwnDialogs -
;one per thread, so a menu's own thread asks for it): they open in front of the game instead of out of sight behind it
;(v2: the tray menu's InputBoxes did). Destroy it when they're done (a local's is when its function ends, too)
DialogsInFront()
	{
	;(local - a name given Gui(...) is taken for a v1 GUI's global otherwise: v2port globals_tool)
	local dfGui := Gui("+AlwaysOnTop -Caption +ToolWindow")
	dfGui.Opt("+OwnDialogs")
	return dfGui
	}
;##############################################
;(the tray menu's "Show the bot's window" - Settings: traybot: the tray icon's double-click then - Dashboard.ahk)
MenuDashShow(A_ThisMenuItem:="", A_ThisMenuItemPos:="", MyMenu:="", *)
	{
	local v1Keep := V1Thread() ; (v1: each thread had its own ErrorLevel)
	TrayPicked(A_ThisMenuItem, MyMenu)
	DashFromTray()
	}
;##############################################
;(the tray menu's "Show Wizard101" - Settings: traygame: there to pick only while Wizard101 is in the tray)
MenuGameShow(A_ThisMenuItem:="", A_ThisMenuItemPos:="", MyMenu:="", *)
	{
	local v1Keep := V1Thread() ; (v1: each thread had its own ErrorLevel)
	TrayPicked(A_ThisMenuItem, MyMenu)
	GameTrayShow(true, "Show Wizard101 (the tray menu)")
	}
;##############################################
;A tray menu pick logged: "Tray: Party... picked" (v1.2.1: Party... did nothing on two PCs and nothing said whether the
;click even reached the bot - no such line now means it didn't). Only a pick in a menu: the same functions run for
;their hotkeys (Hotkeys.ahk HkRun - no menu then)
TrayPicked(item, inMenu)
	{
	if (inMenu is Menu)
		DebugLog("Tray: " item " picked")
	}
;##############################################
MenuLogin(A_ThisMenuItem:="", A_ThisMenuItemPos:="", MyMenu:="", *) { ; (v1: a label)
global
local v1Keep := V1Thread() ; (v1: each thread had its own ErrorLevel)
TrayPicked(A_ThisMenuItem, MyMenu)
;(v2: its boxes in front of the game - they opened behind it)
local dlgFront := DialogsInFront()
ReconnectSetLogin()
dlgFront.Destroy()
return
}
;##############################################
MenuParty(A_ThisMenuItem:="", A_ThisMenuItemPos:="", MyMenu:="", *) { ; (v1: a label)
global
local v1Keep := V1Thread() ; (v1: each thread had its own ErrorLevel)
local pwErr
TrayPicked(A_ThisMenuItem, MyMenu)
;(v1.2.1: an error opening it logged and said in a tray tip - Party.ahk PartyWinFailed - not a box out of sight. Any:
;whatever is thrown - a bare catch takes Error objects only)
try PartySetup()
catch Any as pwErr
	PartyWinFailed(pwErr)
return
}
;##############################################
MenuAlerts(A_ThisMenuItem:="", A_ThisMenuItemPos:="", MyMenu:="", *) { ; (v1: a label)
global
local v1Keep := V1Thread() ; (v1: each thread had its own ErrorLevel)
TrayPicked(A_ThisMenuItem, MyMenu)
;(v2: its boxes in front of the game - they opened behind it)
local dlgFront := DialogsInFront()
AlertSetup()
dlgFront.Destroy()
return
}
;##############################################
MenuRestart(A_ThisMenuItem:="", A_ThisMenuItemPos:="", MyMenu:="", *) { ; (v1: a label)
global
local v1Keep := V1Thread() ; (v1: each thread had its own ErrorLevel)
TrayPicked(A_ThisMenuItem, MyMenu)
BotRestart()
return
}
;##############################################
MenuExit(A_ThisMenuItem:="", A_ThisMenuItemPos:="", MyMenu:="", *) { ; (v1: a label)
global
TrayPicked(A_ThisMenuItem, MyMenu)
ExitApp()
}
;##############################################
StartBot() { ; (v1: a label)
global
local v1Keep := V1Thread() ; (v1: each thread had its own ErrorLevel)
global on := 1
;(the keys - yours from the Keys tab, else F6, F8, Alt+1...: Hotkeys.ahk)
HkApply()
;The bot on (F6): off, it does nothing - no battles, walking, potions or reconnecting. Opened by the game in
;standby (/standby: "Open with Wizard101") it starts off; never turned on, the game closing closes it too
global BotOn := 1, BotStandby := 0, BotEverOn := 1, BotGameSeenAt := A_TickCount
;(a potion run started from the tray: on for it even with the bot off)
global PotionManual := 0
for each, botArg in A_Args
	if (botArg = "/standby")
		BotOn := 0, BotStandby := 1, BotEverOn := 0
	else if (botArg = "/off")
		BotOn := 0
if (BotOn)
	TrayTip("Running: battles and quest walking. " HkText("bot") " pauses it, " HkText("walk") " turns walking on/off - " HkText("quit") " quits.", "Wizard101 bot")
else
	TrayTip("Ready - Wizard101 started. Press " HkText("bot") " to start the bot (battles, quest walking, potions).", "Wizard101 bot")

;Kill calculator (KillCalc.ahk): settings from PlayerStats.txt, enemy health read off the screen,
;and the blades/traps/aura/bubble we've put up this battle
global Stats := V1Obj()
global EnemyHP := ""
global BossSlot := 0
global HealthStatus := ""
global AppliedBlades := V1Obj()
global BossTraps := V1Obj()
global AuraRounds := 0
;Hits we put an enchant on that haven't been cast yet (they keep the enchant): title -> enchant level
global EnchantedHits := V1Obj()
;Saving pips for a hit that ends the battle (KillCalc.ahk PlanPips): the hit ("" none), rounds saved so far,
;given up this battle; and your health % off your name plate, and the round it was read in
;(PipSaveBare: the wand's free hit is fine meanwhile; PipSaveTarget/LastPips/Stall: counting the rounds
;saved; PipOrbs: pip orb slots filled, from PipValue)
global PipSaveFor := "", PipSaveRounds := 0, PipSaveGaveUp := 0, OwnHpPct := 0, OwnHpRound := -1
global PipSaveBare := 0, PipSaveTarget := "", PipSaveLastPips := -1, PipSaveStall := 0, PipOrbs := 0
;You're at the keyboard and mouse right now (PlayerActing): the bot waits. PlayerTookRound: you played (part
;of) a round of this battle - the bot's record of blades/traps may be wrong, so no kill check till it ends.
;RoundLeft: the bot left the round that's up to you (seeing it again isn't a new round)
global PlayerActive := 0, PlayerTookRound := 0, RoundLeft := 0, RoundAgain := 0
;"Play for me" (the dashboard's button - green while on -, the tray menu): every check for you off - nothing waits for you or keeps its
;hands off the mouse for you (UserIdle, Walker.ahk). Off at every start: the bot takes control only once you've said so
global PlayForMe := 0
;Walking without a mob the quest doesn't want catching the wizard, since the last catch or the last time the mobs' reach
;was made smaller (ms - Vision.ahk MobShrinkTick)
global MobWalkMs := 0
;(started again by an update - Wiz-Maxxing /check passes /playforme on when it was on: kept on, you'd said so)
for each, botArg in A_Args
	if (botArg = "/playforme")
		PlayForMe := 1
;The game log's planning phase the enemies' odds were last worked out for while you played (EnemyDanger)
global EnemyPhaseDone := 0
;The battle (the game log's duel) your plate was last found in - playerX is that battle's
global PlateDuel := ""
;When the spellbook (out of battle only) was last seen - the walker's "no battle on" (BotNoBattle)
global BookSeenAt := 0
;When a battle round's Pass button was last seen, when the mouse was last moved onto the scene for one that wasn't, and
;how many times since (a button shown as hovered: see the main loop)
global PassSeenAt := 0, PassNudgeAt := 0, PassNudges := 0, PassNudgeSaidAt := 0, PassHover := 0, PassHoverSaidAt := 0
;Your pips this round, from the game's memory or read off your nameplate (-1 = couldn't read; KillCalc.ahk PipsRead),
;and what the log says about where they came from
global PipsNow := -1, PipsNote := ""
;Boost cards cast since the last hit (Settings.ahk CardBoostOk: boostmax)
global BoostRun := 0
global BossMax := 0
global DualBattle := 0
;Party battle roles (Party.ahk PartyBattleRole): this wizard's part this round ("hitter" - plays as ever -, "blader",
;"healer"); who the boosts go to - its school, wizard's name, slot (hammerX/Y its plate) -, the school of Alt+2's pick;
;the blade and trap kind for it (SchoolGroup)
global BattleRole := "", HammerSchool := "", HammerName := "", HammerSlot := 0, ManualSchool := "", HammerGroup := ""
;Your side's name plates this round ({slot: {name, x, y, me}} - EnemySpells.ahk ReadSidePlates, once a round: the round
;it was read for) and your slot; the healer's ally lowest on health (its plate, %, name; the round read)
global SidePlates := V1Obj(), SidePlatesKey := "", MySlot := 0
global PartyLowX := "", PartyLowY := "", PartyLowPct := 101, PartyLowName := "", PartyLowKey := ""
;Your hits (shared: a support's blades on you are spent when it goes up) and the log's round of the last; the hitter's
;as last seen, in which battle, and the round its new hit goes out in (blades cast again once it's resolved: Party.ahk
;PartyReblade); your school (shared)
global PartyHits := 0, PartyHitR := 0, PartyHitsSeen := "", PartyHitsDuel := "", PartyHitsWait := "", PartyMySchool := ""
;A support's boosts: the round (the log's) each used flag's cast went out in ({n: round}), the battle that's for, the
;round this round's cast goes out in, the round each treasure / item copy's cast went out in ({"storm/blade@tc": round} -
;KillCalc.ahk BoostSrcUsed) (Party.ahk PartyNoteBoosts)
global PartyFlagRound := V1Obj(), PartyFlagDuel := "", PartyCastRound := "", PartySrcRound := V1Obj()
;Where traps go this round: on (the boss picked with Alt+1, a party support's pick, else the enemy with the most health -
;KillCalc.ahk TrapTarget) and where; TrapMine: noted for the kill check (BossTraps - not a party support's), the picked
;enemy's most health and slot (TrapPick), why it was picked (the log)
global TrapOn := 0, TrapAtX := 0, TrapAtY := 0, TrapMine := 0, TrapAtMax := "", TrapPick := 0, TrapWhy := ""
;The enemy this battle's traps (BossTraps) went on when no boss was picked: where its plate was and its most health, how
;many plates there were then (KillCalc.ahk TrapPut); its slot in each round's health read (TrapSlot - ReadEnemyHealth;
;the boss's BossSlot when one was picked): the kill check counts them on it only (solotraps:1)
global TrapFoeX := "", TrapFoeY := "", TrapFoeMax := "", TrapFoeN := 0, TrapSlot := 0
;Blades and traps by damage school (KillCalc.ahk): the game's name of the card on each hit slot's picture ({"balance/hit3":
;"Hydra"} - CardLearn.ahk LearnCards; kept across battles), each hit's heads this look (HitHeads), the % of each boost's
;card in the game's hand, the aura's schools, the schools of the party's last hit (Party.ahk); the planned hit, its heads
;and schools (BoostPick); the school blade's and trap's folders and used flags, the group's; the boosts found (SbFound,
;GbFound), their copies in the game's hand and the treasure / item copies cast (BoostHand, BoostSrcUsed), the other
;schools' pictures asked about this battle, the hitter's planned hit's schools (a support's - Party.ahk), the game's hand
;read this look, what's been said once a battle, a support's misfit blades thrown away this round; the blades cast on you
;that weren't seen there (UseBlade - reboost:1 casts them again after a hit they fit: ConsumeBoosts), the flags BoostOneOf
;held back this round ({blade: [...], trap: [...]})
global SlotGame := V1Obj(), HeadsMemo := V1Obj(), BoostPctMem := V1Obj(), AuraSch := "", PartyLastSch := ""
global PlanHit := "", PlanHeads := "", PlanList := ""
global BladeDir := "", TrapDir := "", BladeU1 := "", BladeU2 := "", TrapU1 := "", TrapU2 := "", Blade2U1 := "", Blade2U2 := "", Trap2U1 := "", Trap2U2 := ""
;(the game's hand's hit the boosts go for while it waits for its pips - KillCalc.ahk BoostPick)
global PlanWait := ""
;(v1.0.0, TODO.md goal 3: the cards this look found where the game's memory has them - Find with memclicks, {"dir\title": 1}:
;their re-finds by picture skipped -, your school as the game's memory has it this round (RoundStart - "" not read), your
;plate taken from the memory this round (memclicks: no picture found it))
global FoundByMem := V1Obj(), RoundMemSchool := "", PlateMem := 0
;(v1.8.0: the round's read of the hand out of date - a discard since -; DiscardSpent's count of the worn deck's Sharpen and
;Potent cards (asked once a battle), its keys off for the battle (a right-click that didn't take) and this round's
;right-clicks)
global HandStale := 0, DeckSharp := "", SpentOff := V1Obj(), SpentLook := V1Obj()
global SbFound := V1Obj(), GbFound := V1Obj(), BoostHand := V1Obj(), BoostSrcUsed := V1Obj(), BoostExtra := "", HammerPlan := "", BoostMemOk := 0, BoostSaid := V1Obj(), BoostMisfitDone := 0
global BoostUnrec := [], BoostOneOfOff := V1Obj()
;(the boosts this look found by the game's hand alone - no picture found them: cast at their card box - KillCalc.ahk
;BoostSearch, BoostMemBox)
global BoostMemOnly := V1Obj()
;(the game's name of the global - bubble - the bot put up this battle: the same isn't cast again - KillCalc.ahk BubbleMem,
;ClickBubble; ResetVariables empties it)
global BubbleUp := ""
;(2026-10-26 - KillCalc.ahk "Absorbs, negative auras and your school's prism": an absorb in hand this look - resources\absorb
;or the game's hand - and whether one that costs no pips can go (the filler casts only such: AbsorbFiller sets
;AbsorbOnlyFree for its box); a negative aura that adds damage taken in hand this look, and the enemies one went on this
;battle - {each of its identities - KillCalc.ahk NegAuraKey: the round} - once in 4 rounds an enemy: UseNegAura; your
;prism on the boss this battle - {hits: your hits counted then (PartyHits), round} - once till a hit of yours goes out:
;UseConvert, KillCalc.ahk ConvertUp; ResetVariables empties them)
global absorb := 0, absorbX := "", absorbY := "", AbsorbFreeOk := 0, AbsorbOnlyFree := 0, negaura := 0, NegAuraOn := V1Obj(), ConvertOn := ""
LoadStats()
;"Wait while I play" on, 3 s, at every start - the bot never takes the mouse from you as it starts (you asked,
;2026-10-23); the tray menu, the dashboard and Settings change it for the run
if (!HandsOffOn() || !Stats.Has("handsoff") || Stats["handsoff"] != 3)
	{
	if (!StatsSet([["handsoffon", 1], ["handsoff", 3]], "Wait while I play: on and 3 s at every start"))
		Stats["handsoffon"] := 1, Stats["handsoff"] := 3
	}

;Misc Initilization
global inbattle := 0
global roundnumber := 0
global battles := 0
global BossChoosen := 0
;The boss picked with Alt+1, from the game window's top left in UI scale 1 pixels (BossX/BossY are
;worked out from it each round, so a moved or resized window still finds it)
global BossRelX := 0, BossRelY := 0
;Enemy nameplates found this round, left to right ({x, y} on screen; KillCalc's ReadEnemyHealth)
global EnemyPlates := []
;(when they were last read - ReadEnemyHealth)
global EnemyPlatesAt := 0
global boosts := 0
global afkVar := 0
global bossX := 0
global bossY := 0
global afkVar := 0

;Screen variable initilization
;Game* is the Wizard101 client area in screen coordinates, ScreenX/ScreenY is its center
global GameExe := "WizardGraphicalClient.exe"
global GameClass := "Wizard Graphical Client"
;Colour tolerance for card pictures (cards shimmer a little between rounds)
global CardTol := 20
;The game draws its UI bigger or smaller with the window size, the Windows display scaling and its
;UI Size setting, and ImageSearch only finds a picture at the size it was cut at. So there's a set of
;pictures per UI size: the main one (resources\, storm\, ... cut at a 1920x1080 window, UI Size
;Small) and a ui<scale> folder for each other size, e.g. ui1.265\ (1920x1200 window at 100%
;scaling: the UI 1.265 times as big). A ui folder only needs the pictures cut at its size; for the
;rest the main picture is used (it won't match at that size, so that card counts as not in hand).
;The set whose Pass button or spellbook is on screen is used (UsePicSet), and every pixel distance
;below is times UiScale. At a size with no pictures cut for it, the bot makes a set itself from the
;cut ones (PicScale.ahk: generated\ui<scale>\)
global PicSets := []
global PicSet := 1
global PicDir := A_WorkingDir
global UiScale := 1.0
global LastSetTry := 0
;Half the width of the area searched for cards in hand (a full 7-card hand is about 580 px wide at
;UI scale 1). Set by UsePicSet
global HandHalf := 400
;Half the distance between two cards in hand: when a card leaves the hand the rest slide this far
;(41 at UI scale 1). Set by UsePicSet
global HalfPitch := 41
global GameLeft := 0
global GameTop := 0
global GameW := A_ScreenWidth
global GameH := A_ScreenHeight
global GameRight := A_ScreenWidth
global GameBottom := A_ScreenHeight
global ScreenX := A_ScreenWidth / 2
global ScreenY := A_ScreenHeight / 2
;(a Wizard101 the bot had put in the tray - Settings: traygame - left hidden by a run that ended without showing it: shown
;again, without taking the focus, before its window is measured - Watch.ahk WatchTrayBack; said in the log below)
local gtBack := WatchTrayBack(A_ScriptDir, 500)
UpdateGameRect()

;debug.log: what the script sees and decides each round (starts fresh every start / restart; the last
;run's is kept as debug.previous.log - e.g. to see why a wizard died before you restarted)
V1Do(FileMove, A_ScriptDir "\debug.log", A_ScriptDir "\debug.previous.log", 1)
;The dashboard: statistics, what the bot sees, the log as it's written (Dashboard.ahk; Windows+2)
DashInit()
SetTimer(UpdPeekNow,-45000)
HandsOffShow()
PlayForMeShow()
GameFrontShow()
BotOnShow()
WatchShow()
DebugLog("Started " BotVersion() ". Game area " GameLeft "," GameTop " " GameW "x" GameH)
if (gtBack != "")
	DebugLog("Put Wizard101 in the tray: " gtBack)
;(the tray settings - Settings: traybot, traygame: the tray menu's items and double-click, Alt+F4's hotkey in Wizard101,
;the watch on its window - and, closing, a Wizard101 in the tray shown again: TrayWinTick, GameTrayOnExit)
TrayWinTick()
OnExit(GameTrayOnExit, -1)
;(the tray menu's picks are logged - TrayPicked: this line says the running program has that, whatever version.txt says)
DebugLog("Tray: the menu is ready (" DllCall("GetMenuItemCount", "Ptr", A_TrayMenu.Handle, "Int") " items) - each pick is logged")
;(the speedhack on: Cheat Engine started if Setup's "Cheat Engine speedhack" set it up - SpeedCheatEngine)
SpeedCheatEngine("the bot started")
if (PlayForMe)
	DebugLog("Play for me kept on: started again by an update while it was on")
LoadPicSets()
;(nothing to tell the size by yet: the set this window size was last played at, else the main one)
if (!DetectPicSet())
	UsePicSet(PicSetForSize(), "nothing on screen to tell the size by yet: " (PicScaleFor(GameW "x" GameH) != "" ? "the size this window was last played at (generated\scales.txt: " GameW "x" GameH "=" PicScaleFor(GameW "x" GameH) ")" : "no size remembered for " GameW "x" GameH " - the main set"))
LastBeat := 0
SeenOut := 0

;Quest walking: on from the start (F8 switches it off and on) - not with battles only (Settings: battlesonly): then off at
;every start, an update's restart too, and F8 doesn't walk (BattlesOnlyTick says so, and ticks the tray menu)
BattlesOnlyTick()
if (WalkerInit("Wizard101 bot " BotVersion()))
	{
	if (BattlesOnly())
		DebugLog("Walking off: battles only (" HkText("walk") " doesn't walk while it's on)")
	else
		{
		Walking := 1
		DebugLog("Walking on (" HkText("walk") " switches it off)")
		}
	}
else
	DebugLog("Walking off: couldn't load the quest arrow shapes (AutoQuester\resources\arrow_refs.txt)")

;Auto-reconnect (Reconnect.ahk): on from the start (tray menu switches it off and on)
ReconnectInit()
;The battle recorder (BattleRec.ahk - Settings: battlerec): set up; it's told to record by its hello, after the helper starts
BrecInit()

;A blocked way's tries, the journal, what you do learned (Puzzle.ahk - Settings: puzzles, puzzlelearn)
PuzzleInit()

;(started again by an update: walking, auto-reconnect and Learn every card as they were - Wiz-Maxxing /check passes
;them on, UpdBotArgs)
for each, botArg in A_Args
	if (botArg = "/nowalk" && Walking)
		{
		Walking := 0
		DebugLog("Walking off: it was off before the update (" HkText("walk") " switches it on)")
		}
	else if (botArg = "/noreconnect" && RcOn)
		{
		RcOn := 0
		Tray.Uncheck("Auto-reconnect on/off")
		DebugLog("Auto-reconnect off: it was off before the update")
		}
	else if (botArg = "/learnall" && !LearnAll && V1IsFunc("LearnAllToggle"))
		LearnAllToggle.Call()

;Stats (StatsRead.ahk): read by itself out of battle when the school it fights with has none yet, or
;when asked (tray menu, or StatsReader.ahk started while this runs - it sends message 0x5555)
global StatsWanted := 0
OnMessage(0x5555, StatsAsked)

;The Python vision helper (Vision.ahk): finds the cards in hand and school badges; ImageSearch if it
;can't run
VisionStart()
;(the battle recorder's hello: recording on or off, the game's log, the bot's state - BattleRec.ahk)
BrecHello()
;(the party - Party.ahk: this bot's state to the helper and the party back, every half second, battles too)
SetTimer(PartyTimer,500)
;(the Network tab - Network.ahk: this bot's state to the others on your home network, theirs and commands back)
SetTimer(NetTick,2000)
OnExit(VisionOnExit)
;(the overlay over the game - the map and the log see-through over Wizard101: Overlay.ahk; Settings: overlay, off by default)
OverlayInit()

;Initializes modes
global commandmode := 0
global dualmode := 0
global responcemode := 0
global devmode := 0
global loremode := 0
global boostlimitmode := 0
global dualhittermode := 0
global statsmode := 0
global loopmode := 0

;Sleep timings
global Tick := 100
;Why the bot is holding (afk): "mana" - it carries on by itself once there's mana again (CheckAfk)
global AfkWhy := "", AfkRetries := 0
;When the picture set in use last matched (the spellbook or a round's Pass button), and at what game size
global PicSetOkAt := 0, PicSetOkSize := ""
global BufferVar := 300
global Half := 600
global Second := 1100
global Five := 5000
global Ten := 10000
global Loading := 15000 

ResetUsed()	
;(v1: on into the label TestRound - the battle loop, for good)
BattleLoop()
}
;##############################################
;The battle loop (v1: the labels TestRound, RoundStart, TestHammer, FindCards and EndRound in the auto-execute section,
;Goto between them - StartBot's thread fell into TestRound and ran them for good, never returning). v2: one function,
;the labels inside it and the Gotos as they were (CONVENTIONS.md 9 - a call each round would grow the stack till it crashed)
BattleLoop() {
global
local _dir, _title ; (v1 passed these literals as temporaries: locals here, not globals)
;Checks if in battle
;(TODO - TODO.md goal 3, needs the game: the round's start and the battle's end from the game's memory - Vision.ahk
;VisionPhase's "hand" / "none" with EnemySpells.ahk BattleLogPlanning - once it's been seen that the planning window's flag
;rises and falls with the Pass button and the participant reads "not in a battle" out of one (python handmem.py --phase);
;roundstart.png and roundfinish.png stay as the fallback, and for the UI-size measure)
TestRound:
Loop
{
	;(no round being played here: a battle round's hold on your mouse let go, however the round was left - Settings.ahk
	;MouseLockOff)
	MouseLockOff("round")
	;(the battle recorder: the round just left - its lines and the bot's state - posted, never waited for: BattleRec.ahk)
	BrecRoundClose()
	;(battles only switched - Settings, the tray menu: said, and walking off - BattlesOnlyTick)
	BattlesOnlyTick()
	;Corrections made on the dashboard's Spells tab: applied here, out of battle only - never in a round, where a hit
	;moved to another slot would take the round's enchants and saved pips with it (Spells.ahk). With the bot off too
	;An update installed by itself (UpdAuto - Settings: autoupdate): out of battle only too
	if (inbattle != 1)
		{
		SpApplyPending()
		UpdAuto()
		;(the deck for what's ahead - Decks.ahk)
		DeckTick()
		}
	;Off (F6) - or opened by the game in standby: nothing till F6 (no battles, walking, potions or reconnecting).
	;Opened in standby and never turned on: Wizard101 closing closes the bot too (it opens again with the game)
	if (!BotOn)
		{
		if (KeysDown || HeldW)
			ReleaseKeys()
		;(your mouse never locked with the bot off - Settings.ahk MouseLockRelease)
		MouseLockRelease("the bot's off")
		if (BotStandby && !BotEverOn)
			{
			ErrorLevel := ProcessExist(GameExe)
			if (ErrorLevel)
				BotGameSeenAt := A_TickCount
			else if (A_TickCount - BotGameSeenAt > 15000)
				{
				DebugLog("Wizard101 closed while the bot was waiting for " HkText("bot") " - closing the bot (it opens again with the game)")
				ExitApp()
				}
			}
		Sleep(300)
		continue
		}
	UpdateGameRect()
	if (A_TickCount - LastBeat > 10000)
		{
		LastBeat := A_TickCount
		;(another program's window: only its program's name - its title can be anything of yours, and the log goes to the
		;OneDrive copy, bug reports and the Network tab)
		;(v1: no window active - blank; v2 throws)
		activeTitle := V1Try(WinGetTitle, "A")
		activePid := V1Try(WinGetPID, "A")
		if (!GameActive() && activePid != DllCall("GetCurrentProcessId"))
			{
			activeExe := V1Try(WinGetProcessName, "A")
			activeTitle := "another program (" (activeExe != "" ? activeExe : "?") ")"
			}
		DebugLog("Watching for a round. Active window: " activeTitle " | game area " GameLeft "," GameTop " " GameW "x" GameH)
		}
	;You're playing (a key, click or mouse move of yours in the last handsoff seconds): the bot waits - no
	;battle rounds, no walking, no potions; it lets go of any walking key at once
	if (PlayerActing())
		{
		if (KeysDown || HeldW)
			ReleaseKeys()
		;(never your mouse locked while you play - Settings.ahk MouseLockRelease)
		MouseLockRelease("you're playing")
		if (inbattle == 1 && !PlayerTookRound)
			PlayerTookRound := 1, DebugLog("  (you're playing in this battle: no kill check till it ends - the bot can't know which blades and traps are left)")
		;(the enemies' likely spells kept up on the dashboard while you play the rounds - once a round, by the game's log,
		;read here too: 2026-10-23 its list stayed on the last round the bot played. Your plate as found in another battle
		;isn't read for your health - an ally's can be there now)
		BattleLogRead()
		if (V1IsFunc("BattleLogInBattle") && BattleLogInBattle() && BlPhase = "kPhase_Planning" && BlPhaseAt != EnemyPhaseDone && V1Gt(V1Ago(BlPhaseAt), 1500))  ; (v1: no phase seen - blank - is not > 1500)
			{
			if (PlateDuel != BlDuel)
				playerX := 0, playerY := 0
			EnemyPhaseDone := BlPhaseAt, EnemyDanger()
			}
		;(the round left to you is over once its Pass button goes)
		if (RoundLeft)
			{
			if (PassButtonAt(&gx, &gy))
				RoundLeft := 0
			}
		Sleep(200)
		continue
		}
	;(the game's log, for the battle: who's in it, what each cast - EnemySpells.ahk)
	BattleLogRead()
	;(mobs kept off less far after 10 minutes of walking unbothered - Vision.ahk)
	MobShrinkTick()
	;Disconnected, or the game closed: get back online first (no battles or walking meanwhile)
	if (ReconnectCheck())
		{
		if (KeysDown || HeldW)
			ReleaseKeys()
		Sleep(300)
		continue
		}
	V1ImageSearch(&roundX, &roundY, GameLeft, GameTop, GameRight, GameBottom, PicOpt("resources\roundfinish.png"))
	bookSeen := (ErrorLevel = 0)
	;(the spellbook only proves the set right when its picture isn't too see-through to tell sizes apart)
	if (bookSeen)
		{
		BookSeenAt := A_TickCount
		if (!PicTooThin(PicPath("resources\roundfinish.png")))
			PicSetOkAt := A_TickCount, PicSetOkSize := GameW "x" GameH, PicCutOk(PicPath("resources\roundfinish.png"))
		}
	if (bookSeen)
		{
		if (!SeenOut)
			{
			DebugLog("Out of battle (spellbook visible)")
			SeenOut := 1
			}
		if (inbattle = 1)
			{
			battles++
			;(the backpack looked at after the bot's battle - QuickSell.ahk: noted before ResetVariables clears inbattle)
			QsBattleEnd()
			}
		;(the mouse, if any of this takes it - potions, stats - goes back where it was at the end: mousereturn)
		MouseGrab()
		;(the mob loop, lore farming, afk: they move the wizard themselves - the walker's keys let go and the game at 1x
		;first, not after their first steps)
		if ((afkVar || loopmode || loremode) && (KeysDown || HeldW || V1Gt(SpeedNow, 1)))
			ReleaseKeys()
		checkafk()
		;Fled a battle out of mana or cards (Flee.ahk): a potion first (or a run to buy some), then on as usual
		FleeAfter()
		checkmana()
		CommandAfk()
		CommandEnter()
		CommandWalk()
		CommandPort()
		CommandOff()
		CommandReload()
		ResetVariables() 
		ResetUsed()	
		;(the card learner's work out of battle: its catalog checked once a run, stray copies of a learned picture put
		;right, a stronger learned hit arranged into hit1-3 - CardLearn.ahk)
		if (V1IsFunc("LearnOutOfBattle"))
			LearnOutOfBattle.Call()
		StatsAuto()
		;(the battle recorder: the stats, settings and deck after a battle - once a battle: BattleRec.ahk)
		BrecState("end")
		;Low on health: a potion, or a run to buy more (Potions.ahk)
		PotionCheck()
		;The backpack full after the battle (Prospector Zeke's alert, the game's memory): quick sold for gold - quicksell,
		;Settings: THE BACKPACK (QuickSell.ahk). Here, before the walker's step: walking waits while it runs
		QsTick()
		;(the spellbook watched for new spells - read only, about every 10 minutes; the spell quest, trainer and deck
		;settings aren't built: said once - Training.ahk)
		TrainBookTick()
		MouseLetGo()
		;(the log's OneDrive copy, when it's on: a picture of the game every 2 minutes - LogMirrorSnap)
		LogMirrorSnap(120000)
		mobloop() ; (v1: Gosub)
		LoreLoop() ; (v1: Gosub)
		}
	;(the Pass button, or as it's drawn with the mouse on it - PassButtonAt)
	PassButtonAt(&startX, &startY)
	;Kept, since writing the log line below resets ErrorLevel (which would start a round that isn't there)
	startErr := ErrorLevel
	if (startErr = 2 && !PicError)
		{
		DebugLog("Can't open " PicPath("resources\roundstart.png") " - the pictures aren't where the script expects them")
		PicError := 1
		}
	If (startErr = 0)
		{
		PassSeenAt := A_TickCount, PassNudges := 0
		;(a battle: the game at normal speed - Cheat Engine's speedhack, if walking had it on)
		SpeedSet(0, "a battle round", true)
		;(gamefront: the game in front for its cards - a first click on a window behind only brings it forward)
		if (!GameActive())
			GameToFront("a battle round is up", false, UserIdle() > 300000)
		;(the first round at a window size: the UI size measured from Pass and Flee before it's played - a made set's
		;Pass button, mostly see-through, matches at a size a little off too: a 2544x1401 window's 1.121 was kept at
		;2560x1440 borderless, 1.144, and your nameplate never found. 3 rounds tried, then played with the set in use)
		pmSize := GameW "x" GameH
		;(not on a hovered Pass - the yellow one's picture tells the size: the next round, the mouse moved off it)
		if (PicMeasuredSize != pmSize && !PassHover)
			{
			;(the Pass button just found is a cut picture - it only matches nearly pixel for pixel, *3: that's the size.
			;A made one is mostly see-through and matches at a size a little off too)
			pmPic := PicPath("resources\roundstart.png")
			if (SubStr(pmPic, -4) = ".png")
				{
				PicMeasuredSize := pmSize
				DebugLog("UI size: the Pass button cut at " Round(PicSets[PicSet].scale, 3) " matches - that's the size (" pmSize ")")
				}
			else
				{
				if (PicMeasureSize != pmSize)
					PicMeasureSize := pmSize, PicMeasureTries := 0
				if (V1Lt(PicMeasureTries, 3))
					{
					PicMeasureTries := V1Add(PicMeasureTries, 1), pmWas := PicSet, PicMeasureWhy := ""
					;(another set: the round start looked for again with it)
					if (DetectUiScale())
						{
						if (PicSet != pmWas)
							continue
						}
					else
						DebugLog("UI size: not measured this round - " PicMeasureWhy " (try " PicMeasureTries " of 3)")
					}
				}
			}
		;(PicCutOk: only the set's own cut Pass button counts - not one made for a card learner's folder at its size)
		PicSetOkAt := A_TickCount, PicSetOkSize := GameW "x" GameH, PicCutOk(PicPath(PassHover ? "resources\roundstart_hover.png" : "resources\roundstart.png"))
		PicRemember()
		;(the set's UI scale against the game's memory's: a disagreement logged, nothing switched on it yet - Vision.ahk)
		PicMemCheck()
		;A battle round is up: stop walking first (a key could still be held from the last step)
		if (KeysDown || HeldW)
			ReleaseKeys()
		RoundAgain := RoundLeft, RoundLeft := 0
		if (RoundAgain)
			{
			;(the round the bot left to you, still up: not a new round)
			BrecRoundOpen(1)
			DebugLog("Round start again (the round left to you is still up): Pass button at " startX - GameLeft "," startY - GameTop)
			Goto("RoundStart")
			}
		;(the battle recorder: the round's lines kept from here - BattleRec.ahk)
		BrecRoundOpen()
		DebugLog("Round start: Pass button at " startX - GameLeft "," startY - GameTop)
		;(a battle's first round: which mob started it, from how far and how far off its facing - Vision.ahk)
		if (SeenOut)
			CaughtLog()
		LogMirrorSnap(120000)
		SeenOut := 0
		if (dualmode == 1)
			{
			;(v1: blank counted as 0; "%roundnumber% / 2" read the variable named by the number - a command-line parameter,
			;never a number - so the round number was blank in dual mode)
			roundnumber := V1N(roundnumber) + 1
			roundnumber := ""
			} else
				{
				roundnumber := V1N(roundnumber) + 1
				}
		Goto("RoundStart")
		}
	;Neither the spellbook nor the Pass button: maybe the game's UI is another size now (the window
	;or the display scaling changed), so every few seconds look with the other picture sets - and if
	;none fits and a round is up, measure the UI size and make a set for it
	;(only when the game's window changed size since the pictures last matched, or nothing has matched for 10
	;minutes - between battle rounds and in dialogues neither shows, and a made set can match what's there then)
	if (!bookSeen && A_TickCount - LastSetTry > 3000 && (PicSetOkSize != GameW "x" GameH || A_TickCount - PicSetOkAt > 600000))
		{
		LastSetTry := A_TickCount
		if (DetectPicSet(true) || DetectUiScale())
			continue
		}
	;In a battle (no spellbook since one) and no round seen for 15 s: Wizard101 draws a button as hovered - white, not
	;yellow - when the mouse last left the game from it (a jump to another monitor never crosses the game), and the Pass
	;button isn't known by its picture then (2026-10-23 06:35: a whole battle left to auto-pass). You away, the game in
	;front: the mouse moved onto the scene - every 15 s, said at most once in 5 minutes (a round's spells take 15 s and more).
	;A battle's first round too: by the game's log, its planning phase up 4 s and no round seen (2026-10-23 17:22: a
	;first round's Pass drawn hovered, not one round of the battle seen till 17:25)
	;(only before a round of the battle's been seen: after the bot's own, a party's planning goes on while the others choose)
	passLog := inbattle != 1 && BattleLogPlanning(4000)
	if (!bookSeen && ((inbattle = 1 && PassSeenAt && A_TickCount - PassSeenAt > 15000) || passLog) && A_TickCount - PassNudgeAt > 15000
		&& GameActive() && UserIdle() > 5000)
		{
		PassNudgeAt := A_TickCount, PassNudges := V1Add(PassNudges, 1)
		MouseMove(ScreenX, GameTop + Round(GameH * 0.4), 0)
		if (A_TickCount - PassNudgeSaidAt > 300000)
			PassNudgeSaidAt := A_TickCount, DebugLog("In a battle, no round seen " (passLog ? "though the game's log says one is up (" V1Round(V1Div(V1Ago(BlPhaseAt), 1000)) " s)" : "for " Round((A_TickCount - PassSeenAt) / 1000) " s") " - the mouse moved onto the scene (a button the mouse was left on shows as hovered, and isn't known; said once in 5 minutes)")
		;(the round still not seen with the mouse off Pass: the set's own cut Pass button looked for with more colour
		;tolerance - learned and kept, the round seen from the next look on: PicScale.ahk PicCutPassSlack. 2026-10-26 14:42
		;the remembered 1.144 set's spellbook matched at *3, its Pass button only at *16 - two battles passed by the game)
		Sleep(200)
		if (PicCutPassSlack(true))
			continue
		}
	;(a battle's first round up by the game's log for 2 s, not seen - between those moves, and with you at the PC too: the
	;same look, every 4 s at most - in the round's time)
	else if (!bookSeen && inbattle != 1 && BattleLogPlanning(2000) && PicCutPassSlack())
		continue
	;No battle round to play right now: take a step towards the quest goal (with no quest arrow
	;on screen, e.g. during the battle's spell animations, it just lets go of the keys and waits).
	;Not while afk, mob-loop or lore farming: those move the wizard themselves
	;(battles only - Settings: battlesonly: no step at all - no walking, following, dungeon run, puzzle try or farming mode's
	;move: it waits for the next round - BattlesOnlyWait)
	if (BattlesOnly())
		BattlesOnlyWait()
	else if (afkVar || loopmode || loremode)
		{
		if (KeysDown || HeldW)
			ReleaseKeys()
		}
	;(low on health with no potions and none to be bought: standing still till it's back - Potions.ahk)
	else if (PotionResting)
		{
		if (KeysDown || HeldW)
			ReleaseKeys()
		PotionRestCheck()
		}
	;(a party's follower: where the leader goes instead of its own quest - Party.ahk)
	else if (PartyFollowing())
		PartyFollowStep()
	;(a dungeon run on the Dungeons tab: its way instead of the quest's - Dungeons.ahk)
	else if (IsObject(DgRun))
		DungeonStep()
	;(a blocked way's tries - Puzzle.ahk: its way instead of the walker's, till the way's open or it's told you; what a timer or a
	;button asked of it done first)
	else if (PuzzleRunning(true))
		PuzzleStep()
	else
		WalkStep()
}

RoundStart:

;A wait before playing a new round (roundwait, the Settings window) - then, as the round's look began: you may
;have started playing meanwhile (the round's yours - nothing's been taken yet), or the round may be over
if (!RoundAgain && Stat("roundwait") > 0)
	{
	Sleep(Stat("roundwait"))
	UpdateGameRect()
	if (PlayerActing())
		{
		DebugLog("  you're playing (during the wait before the round) - leaving this round to you")
		RoundLeft := 1
		if (!PlayerTookRound)
			PlayerTookRound := 1
		Goto("TestRound")
		}
	if (PassButtonAt(&rwX, &rwY))
	{
		Goto("TestRound")
	}
	}
;(a walker notice mustn't cover what the battle reads)
WalkNoteHide()
;(where the mouse is now: it goes back there when the round's done - mousereturn)
MouseGrab()
;(your mouse locked till the round's done - Settings.ahk MouseLockOn; mouselock:0 not)
MouseLockOn("round")
;(Pass drawn hovered - the mouse on it: moved onto the scene, so the buttons and cards look as their pictures)
if (PassHover)
	{
	MouseMove(ScreenX, GameTop + Round(GameH * 0.4), 0)
	;(and the mouse's way back - mousereturn - there too, not onto Pass: the next round would come up hovered again)
	if (MouseHomeSet && MouseOnGame(MouseHomeX, MouseHomeY))
		MouseHomeX := ScreenX, MouseHomeY := GameTop + Round(GameH * 0.4)
	if (A_TickCount - PassHoverSaidAt > 300000)
		PassHoverSaidAt := A_TickCount, DebugLog("  the Pass button was drawn hovered (the mouse on it) - the mouse moved onto the scene (said once in 5 minutes)")
	}
CenterMouse()

;The Alt+1 boss where the window and UI size are now (the nameplates are drawn from its top left)
if (BossChoosen == 1)
	BossX := GameLeft + Round(BossRelX * UiScale), BossY := GameTop + Round(BossRelY * UiScale)

global inbattle := 1
LearnedThisRound := 0, LastHandAnswer := "", DiscardedUnused := 0, DiscardOffCount := 0, BoostMisfitDone := 0, HandStale := 0, SpentLook := V1Obj()

;Both windows share one record of blades/traps in dual mode, so the kill check is off for that whole battle
if (dualmode == 1)
	{
	DualBattle := 1
	}

;Finds the player
global playerX := 0
global playerY := 0
;(v1.0.0: 0 till your plate is found - it was 1 from here on even when nothing found it: playerX, playerY blank, and the
;heal and Tower Shield clicks meant for your plate, and hammerX, hammerY worked out from it, landed wherever the mouse was)
global player := 0
global PlateMem := 0
;(the battle from the game's memory, read once now - your school, and with memclicks:1 your plate: RoundBattleMem)
global RoundMemSchool := ""
RoundBattleMem(&rbmSchool, &rbmX, &rbmY)
RoundMemSchool := rbmSchool

;(the game's log read now: a battle's first round names its wizards only as the Pass button comes up - the loop's last
;read, at most every 500 ms, can be from before; only what's new is read)
BattleLogRead(true)
;(more than one of your wizards in the battle - a party: your plate by your name, EnemySpells.ahk PlayerPlateByName)
global PlateByName := 0
if (PlayerPlateByName(&pbnX, &pbnY))
	{
	playerX := pbnX, playerY := pbnY, PlateByName := 1, player := 1
	}
else
	{
	V1ImageSearch(&playerX, &playerY, GameLeft, GameTop + GameH / 4, GameRight, GameBottom, PicOpt("resources\player.png"))
	if (ErrorLevel = 0)
		{
		player := 1
		} else if (ErrorLevel = 1)
			{
			V1ImageSearch(&playerX, &playerY, GameLeft, GameTop + GameH / 4, GameRight, GameBottom, PicOpt("resources\player2.png"))
			if (Errorlevel = 0)
				{
				player := 1
				}
			} else 
				{
				Goto("TestHammer")
				}
	}
		
;(v1.0.0, memclicks:1: neither your name nor player.png found your plate - where the game's memory has it (RoundBattleMem:
;its box's middle - the click for a heal or Tower Shield on you; NOT TRIED in the game yet). memclicks:0: not found, as before)
if (player != 1 && rbmX != "")
	{
	playerX := rbmX, playerY := rbmY, player := 1, PlateMem := 1
	DebugLog("  your name plate: no picture found it - where the game's memory has it, " playerX - GameLeft "," playerY - GameTop " (memclicks)")
	}
;(the battle it's this battle's plate for)
if (player == 1)
	PlateDuel := BlDuel

;Find player school

global school := ""
global schoolX := 0
global schoolY := 0

;(the badge nearest your plate - it's left of your name: a party battle's next plate is ~300 px on, past the box)
;(v1: your plate not found - playerX blank: blank arithmetic)
if (player == 1)
	school := BestBadge(V1Sub(playerX, Px(100)), V1Sub(playerY, Px(100)), V1Add(playerX, Px(250)), V1Add(playerY, Px(250)), &schoolX, &schoolY, V1Sub(playerX, Px(45)), V1Add(playerY, Px(15)))

;Checks who's hammer
TestHammer:

global hitter := 0
global hitschool := ""
global hammerX := 0
global hammerY := 0
global hitterX := 0
global hitterY := 0

;(the school whose badge matches best: a badge made at another size roughly matches the others too) - your own: the
;cards are looked for in your school's pictures whoever the boosts go to (Alt+2's pick, or a party battle's hitter -
;after). Your plate found by your name (a party battle): its badge, read by it - the helper's one-badge-a-school answer
;could be a teammate's of the same school
if (PlateByName && BadgeNumber(school))
	hitschool := school, hitterX := schoolX, hitterY := schoolY, hitter := BadgeNumber(school)
else
	{
	hitschool := BestBadge(GameLeft, GameTop + GameH * 3 // 4, GameRight, GameBottom, &hitterX, &hitterY, playerX, playerY)
	hitter := BadgeNumber(hitschool)
	}

;(v1.0.0: your school as the game's memory has it, when it's read - the badge by your plate can be a teammate's in a party
;battle (PlayerPlates2), or read wrong. The hitter - the cards are looked for in its school's pictures, the boosts go to it -
;found as another school or none: you, at your plate where the memory has it (memclicks) or as found on the screen (as the
;characters.txt way below has it); neither known: the badge's as before (never a blank spot: the boosts would land wherever
;the mouse is))
if (RoundMemSchool != "")
	{
	if (school != "" && school != RoundMemSchool)
		DebugLog("  your school: the game's memory says " RoundMemSchool ", the badge by your plate " school " - the memory's")
	school := RoundMemSchool
	if (hitschool != RoundMemSchool && (rbmX != "" || player == 1))
		{
		DebugLog("  hitter: " (hitschool = "" ? "no school badge found" : "the " hitschool " badge found") " - the game's memory says you're " RoundMemSchool ": your own plate as the hitter's" (rbmX != "" ? " (where the memory has it - memclicks)" : ""))
		hitschool := RoundMemSchool, hitter := BadgeNumber(RoundMemSchool)
		hitterX := (rbmX != "") ? rbmX : V1Add(playerX, Px(25)), hitterY := (rbmX != "") ? rbmY : V1Add(playerY, Px(8))
		}
	;(v1.0.0 review: no badge found and your plate not found either - you as the hitter all the same, the memory's school:
	;the round is played (its hits cast), as it was while player stayed 1 - not left to you as a wizard the bot doesn't know.
	;No spot for the boosts: hitterX, hitterY blank - UseBlade and UseOnHammer don't cast one onto nothing)
	else if (hitter = 0)
		{
		DebugLog("  hitter: no school badge found, your name plate not found - the game's memory says you're " RoundMemSchool ": you as the hitter, no plate to cast the boosts onto this round")
		hitschool := RoundMemSchool, hitter := BadgeNumber(RoundMemSchool), hitterX := "", hitterY := ""
		}
	}
hammerX := hitterX
hammerY := hitterY

;No school badge found on the name plates - your plate in another slot can show none (seen with a 1280x1024
;window, the left plate): the school this character was seen fighting with before (resources\characters.txt,
;by its CharID in the game's log), and your own plate - found by your name - as the hitter's (a solo battle)
;(v1.0.0 review: also with your plate not found - as while player stayed 1, so the round's still played, not left to you;
;hammerX, hammerY blank then - UseBlade and UseOnHammer don't cast a boost onto nothing)
if (hitter = 0)
	{
	knownSchool := StatsSchoolOf(StatsCharID())
	if (BadgeNumber(knownSchool))
		{
		hitschool := knownSchool, hitter := BadgeNumber(knownSchool)
		hammerX := (player == 1) ? V1Add(playerX, Px(25)) : "", hammerY := (player == 1) ? V1Add(playerY, Px(8)) : ""
		if (school = "")
			school := knownSchool
		DebugLog("  no school badge found on the name plates - this character fought as " knownSchool " before: using that, " (player == 1 ? "with your own plate as the hitter's" : "your name plate not found - no plate to cast the boosts onto this round"))
		}
	}
;(the deck for this battle, once the school's known - the badge's or the one fought as before: a new battle, or your
;Alt+1 boss pick: Decks.ahk)
if (hitter != 0)
	DeckRound()

;A character the bot has no pictures for (no school icon it knows on the screen, e.g. a new wizard of
;another school): leave the round to you rather than passing it, and keep a picture of the round so
;that character's name, school icon and cards can be cut from it
if (hitter = 0)
	{
	MouseLockOff("round")
	savedTo := SaveRoundPicture()
	;(the mouse back once the picture's taken)
	MouseLetGo()
	DebugLog("  no school icon the bot knows - leaving this round to you" (savedTo = "" ? "" : " (picture of it: " savedTo ")"))
	TrayTip("The bot doesn't know this wizard's school yet - play this round yourself.", "Wizard101 bot", 1)
	AlertSend("school", "a wizard it doesn't know", "No school icon the bot knows on the name plates - the round is left to you (a new wizard? its pictures get cut from the round pictures it saves).")
	;Wait for the round to be played (the Pass button goes), then watch for the next one
	unknownFrom := A_TickCount
	Loop
		{
		Sleep(500)
		UpdateGameRect()
		if (PassButtonAt(&unknownX, &unknownY) != 0 || A_TickCount - unknownFrom > 180000)
			break
		}
	Goto("TestRound")
	}

;Who the boosts go to: you - as found above -, the plate picked with Alt+2, or a party battle's hitter (Party.ahk
;PartyBattleRole: this wizard a blader or healer); its school picks the elemental / spirit blade and trap (SchoolGroup -
;Ice is elemental)
HammerSchool := hitschool
if (Manual = 1)
	hammerX := ManualX, hammerY := ManualY, HammerSchool := ManualSchool != "" ? ManualSchool : hitschool
PartyBattleRole()
HammerGroup := SchoolGroup(HammerSchool)
;(the elemental / spirit blades and traps are looked for by the planned hit's schools now - KillCalc.ahk BoostSearch)

;Looks at the hand (and again after discarding, since the cards shift)
if (!RoundAgain)
	Discards := 0
FindCards:

;Enchants (and a fresh look at the hand for the vision helper; each hit's heads looked at afresh - KillCalc.ahk HitHeads;
;the cards found where the game's memory has them - Find - found afresh)
VisionForget()
HeadsMemo := V1Obj(), FoundByMem := V1Obj()
FindEnchant()

;Finds cards avaliable

global sharpen := 0
Find("sharpen", &sharpen, &SharpX, &SharpY, &_dir := "resources") 
 
global potent := 0
Find("potent", &potent, &PotentX, &PotentY, &_dir := "resources") 

;(the school blades and traps - yours and those of every school the hits need: KillCalc.ahk BoostSearch, once the pips
;are read)
global blade := 0

global blade3 := 0
Find("blade3", &blade3, &Blade3X, &Blade3Y, &_dir := "resources")
 
global blade4 := 0
Find("blade4", &blade4, &Blade4X, &Blade4Y, &_dir := "resources")

global trap := 0

global trap3 := 0
Find("trap3", &trap3, &trap3X, &trap3Y, &_dir := "resources")

global aura := 0
Find("aura", &aura, &auraX, &auraY, &hitschool)

global tower := 0
Find("tower", &tower, &towerX, &towerY, &_dir := "resources")

global reshuffle := 0
Find("reshuffle", &reshuffle, &reshuffleX, &reshuffleY, &_dir := "resources")

global feint := 0
Find("feint", &feint, &feintX, &feintY, &_dir := "resources")

global bubble := 0
Find("bubble", &bubble, &bubbleX, &bubbleY, &hitschool)

global convert := 0
Find("convert", &convert, &convertX, &convertY, &hitschool)
;(whether the boss needs it - the game's memory: of your school, it resists your hits - is asked when the chain gets to it:
;NeedsConvert; your school's prism no picture finds: by the game's hand - KillCalc.ahk ConvertMem)

;(an absorb - resources\absorb, its learned slot, by its picture when it has one; else the game's hand: KillCalc.ahk
;AbsorbMem - and a negative aura, by the game's hand only: NegAuraMem)
global absorb := 0
absorbX := "", absorbY := "", AbsorbFreeOk := 0, negaura := 0
if (AbsorbPicThere())
	{
	Find("absorb", &absorb, &absorbX, &absorbY, &_dir := "resources")
	AbsorbFreeOk := (absorb == 1) ? AbsorbSlotFree() : 0
	}

;Finds hit specific cards
if (hitter != 0)
	{
	global hit4 := 0
	Find("hit4", &hit4, &hit4X, &hit4Y, &hitschool)
	
	global hit3 := 0
	Find("hit3", &hit3, &hit3X, &hit3Y, &hitschool)
	
	global hit2 := 0
	Find("hit2", &hit2, &hit2X, &hit2Y, &hitschool)
	
	global hit1 := 0
	Find("hit1", &hit1, &hit1X, &hit1Y, &hitschool)

	;The wand's own card (an item card from the wand, e.g. Minor Clash: no pips)
	global wand := 0
	Find("wand", &wand, &wandX, &wandY, &hitschool)

	;Healing cards (heal1 / heal2 pictures in the school's folder), used when your health is low
	global heal1 := 0
	Find("heal1", &heal1, &heal1X, &heal1Y, &hitschool)
	global heal2 := 0
	Find("heal2", &heal2, &heal2X, &heal2Y, &hitschool)
	}
;(the deck in use's slots it doesn't play: out of this round's hand - Decks.ahk)
DeckFilterHand()

;(the boosts going to another school's wizard - Alt+2's pick, a party battle's hitter: your school's bubble only boosts
;your school's hits - not cast; its blades and traps are looked for in its school's folder - BoostSearch; a blader's or
;healer's aura only boosts itself)
if (HammerSchool != hitschool)
	bubble := 0
if (PartySupport())
	aura := 0

;How many pips you have (the game doesn't grey out cards you can't afford): the game's own count from its memory, else
;off the pip row under your name (KillCalc.ahk PipsRead)
PipsNow := PipsRead()
DebugLog("  pips=" PipsNow PipsNote)
DebugLog("  player=" player " at " V1Sub(playerX, GameLeft) "," V1Sub(playerY, GameTop) (PlateMem ? " (the game's memory)" : "") " school=" school (RoundMemSchool != "" ? " (the game's memory)" : "") " | hitter=" hitschool " at " V1Sub(hammerX, GameLeft) "," V1Sub(hammerY, GameTop) " | enchant=" enchant
	. (PartySupport() ? " | " BattleRole ": the boosts to " HammerName " (" (HammerSchool = "" ? "school not known" : HammerSchool) ")" : ""))
;The blades and traps of every school the hits need - a Balance Hydra's fire, ice and storm (KillCalc.ahk BoostSearch: the
;game's memory, read-only, says what's in hand; without it, your school's as before)
BoostSearch()
;(which school the logged-in character is, for StatsReader: the badge by its own name plate - the
;hitter can be an ally; the game's memory's is this client's own for sure - v1.0.0)
if (RoundMemSchool != "" || PlateByName || !PlayerPlates2())
	{
	StatsNoteSchool(school)
	;(and the party's told it: Party.ahk)
	if (BadgeNumber(school))
		PartyMySchool := school
	}
DebugLog("  cards: hit1-4=" hit1 hit2 hit3 hit4 " wand=" wand " heal1-2=" heal1 heal2 " blade=" blade " blade2=" blade2 " blade3=" blade3 " blade4=" blade4 " sharpen=" sharpen " trap=" trap " trap2=" trap2 " trap3=" trap3 " potent=" potent " feint=" feint " aura=" aura " bubble=" bubble " convert=" convert " tower=" tower " reshuffle=" reshuffle " absorb=" absorb " negaura=" negaura)

;Cards in hand the bot has no picture for yet: learned (CardLearn.ahk); one that went into a free slot is
;used this round, so look at the hand again
if (Manual != 1) && (!LearnedThisRound)
	{
	LearnedThisRound := 1
	if (LearnCards())
	{
		Goto("FindCards")
	}
	;(v1.0.0: the game's memory's card boxes against the ones that look saw on the screen - logged, clicks nothing; with
	;memclicks:1, 3 looks in a row lining up let the cards be clicked where the memory has them: KillCalc.ahk MemBoxCheck)
	MemBoxCheck(LastHandAnswer)
	}

;Discard (right-click) cards that can't help this battle, then look at the hand again (not while learning
;every card: that discards everything it knows): first, once a round, the cards it never plays (learned, in no
;slot - CardLearn.ahk DiscardUnused, off the hand as the helper read it), then spare blades and Sharpen
;(and cards of kinds switched off in the Settings window: Settings.ahk DiscardSwitchedOff)
if (!LearnAll) && V1Lt(Discards, 3) && V1Add(V1Add(DiscardUnused(), DiscardSpare()), DiscardSwitchedOff())  ; (v1: a blank count made the sum blank)
	{
	Discards := V1N(Discards) + 1, HandStale := 1  ; (v1: never set yet - the first round left to you in roundwait, then up again - blank: "" < 3 true, ++ from 0)
	s(Stat("discardlook"))
	Goto("FindCards")
	}

;(v1.8.0: the round's read of the hand - LearnCards' LastHandAnswer - is out of date once something's been discarded:
;read afresh, once, for what reads it later - a learned hit in no slot (CardLearn.ahk LearnHitReady held every one back
;in a round that discarded), the flee check's count of cards, the planned hit; "" the helper didn't answer: none, as
;before. The mouse off the hand first, as for LearnCards' read: a card zoomed up under it is read wrong)
if (HandStale && LastHandAnswer != "")
	{
	LearnMouseClear()
	LastHandAnswer := LearnHandRead()
	}
HandStale := 0

CenterMouse()

;Our aura only lasts a few rounds
if (AuraRounds > 0 && !RoundAgain)
	{
	AuraRounds--
	}

;Turned off (F6) during the round: it's left - nothing more cast, the mouse given back
if (!BotOn)
	{
	DebugLog("  bot off (" HkText("bot") ") - leaving this round")
	RoundLeft := 1
	MouseLetGo()
	MouseLockOff("round")
	Goto("TestRound")
	}

;You started playing while the bot looked at the hand: the round is yours
if (PlayerActing())
	{
	DebugLog("  you're playing - leaving this round to you")
	RoundLeft := 1
	if (!PlayerTookRound)
		PlayerTookRound := 1, DebugLog("  (no kill check till this battle ends - the bot can't know which blades and traps you use)")
	Goto("EndRound")
	}

;Out of mana or cards - it could only pass for the rest of the battle: flee, and try again (Flee.ahk)
;(TODO - TODO.md goal 3, needs the game: mana from the game's memory - which object holds the wizard's mana isn't known yet
;(python reflect.py --class X --grep mana); Potions.ahk PotionGlobes' pixels till then)
if FleeCheck()
{
	Goto("EndRound")
}

;Learning every card (dashboard button / tray menu): no casting but a heal when low - learn, discard what
;it knows so the next round draws new cards, pass (CardLearn.ahk LearnAllRound)
if (LearnAll)
	{
	if (player == 1) && ((heal1 == 1) || (heal2 == 1)) && OwnHealthLow()
		{
		if (heal1 == 1) && UseHeal("heal1", &heal1, hitschool)
		{
			Goto("EndRound")
		}
		if (heal2 == 1) && UseHeal("heal2", &heal2, hitschool)
		{
			Goto("EndRound")
		}
		}
	LearnAllRound()
	ClickPass()
	Goto("EndRound")
	}

;Kill check: read every enemy's health and, if a hit in hand already kills them all, cast it now instead of boosting more
global KillHit := ""
global KillEnchant := 0
PipSaveFor := ""
;(v1.0.0: the enemies' health from the game's memory first - KillCalc.ahk EnemyMemHealth; healthocr:0 with memclicks:1 - from
;it alone, no OCR)
if (hitter != 0) && (DualBattle != 1) && (!PlayerTookRound) && (Stat("healthocr") == 1 || Stat("memclicks") == 1) && ((hit1 == 1) || (hit2 == 1) || (hit3 == 1) || (hit4 == 1) || (wand == 1 && Stat("usewand")))
	{
	if (ReadEnemyHealth(Stat("healthocr") != 1))
		{
		;(nothing ends it now: one would with an enchant on it and there's none in hand - drawenchant: treasure cards
		;drawn for one, then looked at again - Draw.ahk; still nothing: is a hit worth saving pips for? KillCalc.ahk
		;PlanPips)
		if (!FindLethalHit(&KillHit, &KillEnchant))
			{
			if (DrawWouldKill() && DrawForKill())
				FindLethalHit(&KillHit, &KillEnchant)
			;(a blader's or healer's pips are for its boosts: no saving them for a hit)
			if (KillHit = "" && !PartySupport())
				PlanPips()
			}
		}
	ShowKillInfo()
	DebugLog("  kill check: " HealthText() " -> " (KillHit = "" ? "no lethal hit" : KillHit (KillEnchant ? " with enchant" : "")))
	;(and the damage it counts on from each hit in hand - you asked, 2026-10-23)
	khText := KillHitsText()
	if (khText != "")
		DebugLog("  your hits now: " khText)
	CenterMouse()
	if (KillHit != "")
		{
		if UseHit(&KillHit, &%KillHit%, &hitschool, KillEnchant)
			{
			;(a saved-for hit went out: the next save counts afresh)
			PipSaveRounds := 0, PipSaveTarget := "", PipSaveStall := 0, BoostRun := 0
			Goto("EndRound")
			}
		}
	}

;Enemy spells (EnemySpells.ahk): what each enemy will likely cast, off the wiki and the battle so far (the game's log) -
;logged and on the dashboard; the chance their hits kill you this round defendat % or more: a heal, else Tower Shield,
;first (a hit that ends the battle went first, above)
;(worked out every round the bot plays - the dashboard's list kept up even after you played one; defending only while
;the bot's record of the battle is its own)
if (hitter != 0) && (playerX != "")
	{
	EnemyPhaseDone := BlPhaseAt
	if (EnemyDanger() && !PlayerTookRound && EnemyDefend())
	{
		Goto("EndRound")
	}
	}

;A party battle's healer (Party.ahk): the ally lowest on health - under healat % and lower than you - healed first
if (BattleRole = "healer") && ((heal1 == 1) || (heal2 == 1)) && PartyHealAlly()
{
	Goto("EndRound")
}

;Low on health (under healat % of it, PlayerStats.txt): a healing card on yourself before anything else
if (player == 1) && ((heal1 == 1) || (heal2 == 1)) && OwnHealthLow()
	{
	if (heal1 == 1) && UseHeal("heal1", &heal1, hitschool)
	{
		Goto("EndRound")
	}
	if (heal2 == 1) && UseHeal("heal2", &heal2, hitschool)
	{
		Goto("EndRound")
	}
	}

;(the healer: Tower Shield on the ally that's low, else on the hitter - Party.ahk PartyShield)
if (BattleRole = "healer") && PartyShield()
{
	Goto("EndRound")
}

;The round planner (Planner.ahk - Settings: planner, off unless you switch it on): every card in hand tried in the
;battle simulator from this round on, its advice logged and recorded - planner 1 never casts, the round goes on below
;exactly as without it (PlannerRound returns false; planner 2, a cast of its own, isn't built). planner 0: nothing asked.
;Turned off (F6) already: not asked - no wait for the helper while the mouse is still held (the check below gives it
;back; one pressed during the ask is caught there too)
if (BotOn && PlannerMode() && PlannerRound())
{
	Goto("EndRound")
}
;(partyorders - Party.ahk PartyOrderRound: a follower's round - the leader's card for its hand logged, advice
;only, waited for 3 s at most, nothing cast; the leader: a note once a battle when planner is off. Off: nothing)
if (BotOn && PartyOrdersOn())
	PartyOrderRound()

;How it plays its cards (the Settings window: cardlogic, boostmax, use...): hit first - before any boost - when
;the card logic says so (Settings.ahk CardHitFirst); boosts only up to boostmax before a hit it can cast
;(CardBoostOk); kinds switched off aren't played. BoostRun counts the boosts since the last hit
;Turned off (F6) during the round: it's left - nothing more cast, the mouse given back
if (!BotOn)
	{
	DebugLog("  bot off (" HkText("bot") ") - leaving this round")
	RoundLeft := 1
	MouseLetGo()
	MouseLockOff("round")
	Goto("TestRound")
	}
;Where traps go: the boss picked with Alt+1; a party battle's blader or healer - the enemy the hitter goes for (Party.ahk
;PartyTrapTarget); else, in every battle (the user, 2026-10-24: "the enemy with the highest health always"), the enemy
;with the most health - a tie or health not read: the planned hit's target (KillCalc.ahk TrapTarget, only with a trap in
;hand). Which traps: those that fit the planned hit's schools (BoostPick), one a round, as ever
TrapWhere()

;The hit this round's boosts are for - with the game's hand read, the one dealing the most with the boosts in hand and on;
;a blader's or healer's: the hitter's - and the blades and traps that fit its schools, the most that adds first
;(KillCalc.ahk BoostPick; CastBestHit casts that hit first)
BoostPick()

;(a blader or healer: no hit first, no boost limit - boosting is what it's for)
HitsTried := 0
if (!PartySupport()) && CardHitFirst()
	{
	HitsTried := 1
	if CastBestHit()
	{
		Goto("EndRound")
	}
	}
BoostOk := PartySupport() ? 1 : CardBoostOk()

;Automatic Battle code
;(each school's blade and trap with its own used flags - KillCalc.ahk KeyFlags: BoostPick names them)
if (feint == 1) && (TrapOn == 1) && BoostOk && Stat("usetraps") && UseTrap(&_title := "feint", &feint, &Used1, &Used2, &_dir := "resources")
	{
	BoostRun++
	Goto("EndRound")
	} else if (convert == 1) && (BossChoosen == 1) && BoostOk && NeedsConvert() && UseConvert(&_title := "convert", &convert, &hitschool)
		{
		;(a boost - boostmax counts it -, once till a hit of yours goes out: NeedsConvert, KillCalc.ahk ConvertUp - the
		;review, 2026-10-26)
		BoostRun++
		Goto("EndRound")
		;(a negative aura - an Attenuate: +N% damage taken on the trap rule's enemy for 4 rounds, before the traps and blades;
		;once in 4 rounds an enemy, only one that adds to the planned hit - UseNegAura, KillCalc.ahk NegAuraMem)
		} else if (negaura == 1) && BoostOk && Stat("usetraps") && UseNegAura()
			{
			BoostRun++
			Goto("EndRound")
			} else if (trap == 1) && (TrapOn == 1) && BoostOk && Stat("usetraps") && UseTrap(&_title := "trap", &trap, &used%TrapU1%, &used%TrapU2%, &TrapDir)
			{
			BoostRun++
			Goto("EndRound")
			} else if (trap2 == 1) && (TrapOn == 1) && BoostOk && Stat("usetraps") && UseTrap(&traptype, &%traptype%, &used%Trap2U1%, &used%Trap2U2%, &_dir := "resources")
				{
				BoostRun++
				Goto("EndRound")
				} else if (trap3 == 1) && (TrapOn == 1) && BoostOk && Stat("usetraps") && UseTrap(&_title := "trap3", &trap3, &used7, &used8, &_dir := "resources")
					{
					BoostRun++
					Goto("EndRound")
					} else if (trap4 == 1) && (TrapOn == 1) && BoostOk && Stat("usetraps") && UseTrap(&_title := "trap4", &trap4, &used9, &used10, &_dir := "resources")
						{
						BoostRun++
						Goto("EndRound")
						} else if (blade == 1) && BoostOk && Stat("useblades") && UseBlade(&_title := "blade", &blade, &used%BladeU1%, &used%BladeU2%, &BladeDir)
							{
							BoostRun++
							Goto("EndRound")
							} else if (blade2 == 1) && BoostOk && Stat("useblades") && UseBlade(&bladetype, &%bladetype%, &used%Blade2U1%, &used%Blade2U2%, &_dir := "resources")
								{
								BoostRun++
								Goto("EndRound")
								} else if (blade3 == 1) && BoostOk && Stat("useblades") && UseBlade(&_title := "blade3", &blade3, &used15, &used16, &_dir := "resources")
									{
									BoostRun++
									Goto("EndRound")
									}  else if (blade4 == 1) && BoostOk && Stat("useblades") && UseBlade(&_title := "blade4", &blade4, &used17, &used18, &_dir := "resources")
										{
										BoostRun++
										Goto("EndRound")
										} else if (bubble == 1) && BoostOk && Stat("usebubble") && ClickBubble()
											{
											;(by its picture, else at the game's card's box - ClickBubble; not clicked: on
											;down the chain, not a round with nothing cast)
											BoostRun++
											} else if (aura == 1) && BoostOk && Stat("useaura") && (AuraRounds <= 0)
												{
												if FindAndClick(&_title := "aura", &aura, &hitschool)
													{
													AuraRounds := 4
													;(the schools it boosts: its card's in the game's hand, else yours)
													AuraSch := BoostAuraSchools()
													BoostRun++
													}
												} else if (BattleRole = "blader") && PartyShield()
													{
													Goto("EndRound")
													} else if (!HitsTried) && CastBestHit()
													{
													Goto("EndRound")
													} else if (wand == 1) && Stat("usewand") && !WandWastes() && UseHit(&_title := "wand", &wand, &hitschool)
														{
														BoostRun := 0
														Goto("EndRound")
														} else if (tower == 1) && Stat("usetower") && UseOnSelf(&_title := "tower", &tower, &_dir := "resources") || AbsorbFiller()
															{
															;(it has to go out, as when defending - CastWentOut; the card didn't go: passed,
															;not left to the round's timer. Not clicked at all - the game's Tower Shield's box
															;not lined up for sure (UseMemAt): on to Reshuffle, else Pass. No Tower Shield: an
															;absorb that costs no pips the same way - AbsorbFiller, 2026-10-26)
															if (!CastWentOut())
																ClickPass()
															} else if (reshuffle == 1) && Stat("usereshuffle")
																{
																;(a party battle's blader or healer: on itself - hammerX/Y is the hitter's
																;plate; its boosts on the hitter are cast again by Party.ahk, not here)
																if (PartySupport())
																	UseOnSelf(&_title := "reshuffle", &reshuffle, &_dir := "resources")
																else
																	{
																	;(the used flags reset only once it's clicked - not when
																	;its card wasn't found again or there's no plate to
																	;cast it onto: UseOnHammer)
																	if (UseOnHammer(&_title := "reshuffle", &reshuffle, &_dir := "resources"))
																		ResetUsed()
																	}
																} else if ClickPass()
																	{
																	Goto("EndRound")
																	}
EndRound:
DebugLog("Round done")
;(partyorders, the leader: a round it didn't plan the team in told to its followers - Party.ahk PartyOrderSkip)
if (PartyOrdersLead())
	PartyOrderSkip()
;The mouse back where it was when the round began (mousereturn, the Settings window), else off the cards - not
;if you've used the mouse or keys meanwhile (MouseLetGo -1: it's yours)
if (MouseLetGo() = 0)
	CenterMouse()
;(your mouse unlocked - Settings.ahk MouseLockOff)
MouseLockOff("round")

SwitchWindow()
	
Goto("TestRound")
}
;##############################################
mobloop() { ; (v1: a label)
global
;(Wizard101 in the tray - Settings: traygame: no step - its keys would go to the window in front)
if (GameInTray)
	return
;(battles only - Settings: battlesonly: no mob-loop step - S back, W on - it moves nothing out of battle)
if (loopmode == 1 && !BattlesOnlyNo("mob-loop step (" HkText("loop") ")"))
	{
	Send("{s down}")
	s(1000)
	Send("{s up}")
	;(the backpack full and not sold - held for a dungeon's drops, quick sell failed or waiting: QuickSell.ahk's last look
	;after the battle, by the game's memory. resources\full.png never existed - that search never found anything)
	if (QsStillFull())
		{
		AlertSend("inventory", "backpack full", "The backpack is full and wasn't quick sold - mob-loop farming has stopped (kept from timing out).")
		afk()
		loopmode := 0
		return
		}
	s(5000)
	;(gone to the tray meanwhile: no W)
	if (GameInTray)
		return
	Send("{w down}")
	s(1000)
	Send("{w up}")
	}
return
}
;##############################################
LoreLoop()
	{ ; (v1: a label)
	global
	local _direction ; (v1 passed these literals as temporaries: locals here, not globals)
	;(Wizard101 in the tray - Settings: traygame: none of lore farming's moves - they'd go to the window in front)
	if (GameInTray)
		return
	;(battles only - Settings: battlesonly: no lore farming's moves - its log out and join, X at the sigil, the walk in)
	if (loremode == 1 && BattlesOnlyNo("lore farming (" HkText("lore") ")"))
		return
	if ((loremode == 1) && (dualmode == 0))
		{
		;(v1: "Mod(%battles% + 1, 50)" read the variable named by the number of battles - a command-line parameter or
		;the count of them, never 49: never 0)
		num := ""
		if (num == 0)
			{
			UsePotion()
			}	
		log()	
		join()
		s(5000)
		Spam("x")
		s(16000)
		LockMove(&_direction := "w")
		s(5000)
		} else if ((loremode == 1) && (dualmode == 1))
			{
			;Joins Battles with same wizard you started the loop in
			;(your mouse locked the whole way - about a minute: Settings.ahk MouseLockOn, 2 minutes before its watchdog)
			MouseLockOn("lore", 120000)
			;(v1: never 0 - as above)
			num := ""
			if (num == 0)
				{
				UsePotion()
				SwitchWindow()
				s(500)
				UsePotion()
				SwitchWindow()
				}	
			log()
			SwitchWindow()
			centermouse()
			log()
			join()
			SwitchWindow()
			centermouse()
			join()
			SwitchWindow()
			s(30000)
			Spam("x")
			SwitchWindow()
			s(1000)
			Spam("x")
			s(17000)
			LockMove(&_direction := "w")
			SwitchWindow()
			s(1000)
			LockMove(&_direction := "w")
			s(5000)
			SwitchWindow()
			MouseLockOff("lore")
			return
			} else 
				{
				return
				}
	}
;##############################################
HkDev(*) { ; (v1: a label - a hotkey's: Hotkeys.ahk HkRun calls it by name)
global
local _name, _x, _y, _w, _h ; (v1 passed these literals as temporaries: locals here, not globals)
if (on == 1)
	{
	ModeBox(&devmode, &_name := "Developer", &_x := 10, &_y := 10, &_w := 144, &_h := 30)
	}
return
}
;##############################################
HkLore(*) { ; (v1: a label - a hotkey's: Hotkeys.ahk HkRun calls it by name)
global
local _name, _x, _y, _w, _h ; (v1 passed these literals as temporaries: locals here, not globals)
if (on == 1)
	{
	msgResult := MsgBox("Please make sure you're standing next to the lore sigil when activating this mode.`n`nPress Ok to continue.", "AutoFarmer: Lore Mode", 1)
	if (msgResult = "ok")
		{
		ModeBox(&loremode, &_name := "Lore", &_x := 10, &_y := 10, &_w := 140, &_h := 30)
		}
	if (msgResult = "cancel")
		{
		return
		}
	if (msgResult = "timeout")
		{
		return
		}
	}
return
}
;##############################################
HkDual(*) { ; (v1: a label - a hotkey's: Hotkeys.ahk HkRun calls it by name)
global
local _name, _x, _y, _w, _h ; (v1 passed these literals as temporaries: locals here, not globals)
if (on == 1)
	{
	msgResult := MsgBox("Please make sure that, when activating this mode two Wizard101 instances are open and that, when `"Alt+Tab`" is pressed it'll switch bewteen them.`n`nPress Ok to continue.", "AutoFarmer: Dual Mode", 1)
	if (msgResult = "ok")
		{
		ModeBox(&dualmode, &_name := "Dual", &_x := 10, &_y := 10, &_w := 120, &_h := 30)
		}
	if (msgResult = "cancel")
		{
		return
		}
	}
return
}
;##############################################
HkCommand(*) { ; (v1: a label - a hotkey's: Hotkeys.ahk HkRun calls it by name)
global
local _name, _x, _y, _w, _h ; (v1 passed these literals as temporaries: locals here, not globals)
if (on == 1)
	{
	ModeBox(&commandmode, &_name := "Command", &_x := 10, &_y := 10, &_w := 144, &_h := 30)
	}
return
}
;##############################################
HkStats(*) { ; (v1: a label - a hotkey's: Hotkeys.ahk HkRun calls it by name)
global
local _name, _x, _y, _w, _h ; (v1 passed these literals as temporaries: locals here, not globals)
if (on == 1)
	{
	ModeBox(&statsmode, &_name := "Statistic", &_x := 10, &_y := 10, &_w := 140, &_h := 30)
	}
return
}
;##############################################
HkResponse(*) { ; (v1: a label - a hotkey's: Hotkeys.ahk HkRun calls it by name)
global
local _name, _x, _y, _w, _h ; (v1 passed these literals as temporaries: locals here, not globals)
if (on == 1)
	{
	ModeBox(&responcemode, &_name := "Responce", &_x := 10, &_y := 10, &_w := 140, &_h := 30)
	}
return
}
;##############################################
HkBoss(*) { ; (v1: a label - a hotkey's: Hotkeys.ahk HkRun calls it by name)
global
local _text, _x, _y, _w, _h ; (v1 passed these literals as temporaries: locals here, not globals)
if ((on == 1) && (inbattle == 1))
	{
	;(your mouse free for the pick - Settings.ahk MouseLockPause; locked again after if a round still has it)
	MouseLockPause(1)
	NewStaticGui(&_text := "Please Select Boss Location.", &_x := 10, &_y := 10, &_w := 140, &_h := 30)
	ErrorLevel := !KeyWait("LButton", "D, 10")
		If (Errorlevel = 0)
			{
			global BossChoosen := 1
			MouseGetPos(&BossX, &bossY)
			UpdateGameRect()
			BossRelX := (BossX - GameLeft) / UiScale, BossRelY := (BossY - GameTop) / UiScale
			;A newly picked boss starts with no traps counted (those on the enemy with the most health too: KillCalc.ahk
			;TrapPut - BossTraps holds one enemy's)
			BossMax := 0
			BossTraps := V1Obj(), TrapFoeX := "", TrapFoeY := "", TrapFoeMax := "", TrapFoeN := 0, TrapSlot := 0
			Gui1Destroy()
			}
	MouseLockPause(0)
	CenterMouse()
	}
return
}
;##############################################
HkLoop(*) { ; (v1: a label - a hotkey's: Hotkeys.ahk HkRun calls it by name)
global
local _name, _x, _y, _w, _h ; (v1 passed these literals as temporaries: locals here, not globals)
if (on == 1)
	{
	ModeBox(&loopmode, &_name := "Loop", &_x := 10, &_y := 10, &_w := 140, &_h := 30)
	}
return
}
;##############################################
HkBoost(*) { ; (v1: a label - a hotkey's: Hotkeys.ahk HkRun calls it by name)
global
local _text, _x, _y, _w, _h ; (v1 passed these literals as temporaries: locals here, not globals)
if ((on == 1) && (inbattle == 1))
	{
	MouseLockPause(1)
	NewStaticGui(&_text := "Please Select Hammer Location.", &_x := 10, &_y := 10, &_w := 140, &_h := 30)
	ErrorLevel := !KeyWait("LButton", "D, 10")
		If (Errorlevel == 0)
			{
			Manual := 1
			MouseGetPos(&ManualX, &ManualY)
			;(its school - the blade and trap kind for it; your own school - the cards looked for - stays yours)
			ManualSchool := BestBadge(ManualX - Px(75), ManualY - Px(75), ManualX + Px(75), ManualY + Px(75), &manualBX, &manualBY, ManualX, ManualY)
			DebugLog(HkText("boost") ": the boosts go to the plate at " ManualX - GameLeft "," ManualY - GameTop " (" (ManualSchool = "" ? "its school not read" : ManualSchool) ") this battle")
			Gui1Destroy()
			CenterMouse()
			}
	;(locked again whether or not a plate was picked - if a round still has it)
	MouseLockPause(0)
}
return
}
;##############################################
HkPlayer(*) { ; (v1: a label - a hotkey's: Hotkeys.ahk HkRun calls it by name)
global
local _text, _x, _y, _w, _h ; (v1 passed these literals as temporaries: locals here, not globals)
if ((on == 1) && (inbattle == 1))
	{
	MouseLockPause(1)
	NewStaticGui(&_text := "Please Select New Player Location.", &_x := 10, &_y := 10, &_w := 140, &_h := 30)
	ErrorLevel := !KeyWait("LButton", "D, 10")
		If (Errorlevel = 0)
			{
			global ManualPlayer := 1
			MouseGetPos(&ManualPlayerX, &ManualPlayerY)
			Gui1Destroy()
			}
	MouseLockPause(0)
	CenterMouse()
	}
return
}
;##############################################
GuiClose(*) { ; (v1: a label)
global
Gui1Destroy()
return
}
;##############################################
HkDash(*) { ; (v1: a label - a hotkey's: Hotkeys.ahk HkRun calls it by name)
global
;Windows+2: the dashboard (Dashboard.ahk) - in dev mode, the info box below
if (devmode != 1)
	{
	DashToggle()
	return
	}
if (devmode == 1)
{
HealthInfo := HealthText()
;(v1: boostlimit and responsemode are set nowhere - blank in the box)
boostlimit := "", responsemode := ""
;(the school blade's and trap's flags, the group's - this round's: KillCalc.ahk BoostPick)
DevB1 := used%BladeU2%, DevSB1 := used%BladeU1%, DevB2 := used%Blade2U2%, DevSB2 := used%Blade2U1%
DevT1 := used%TrapU2%, DevPT1 := used%TrapU1%, DevT2 := used%Trap2U2%, DevPT2 := used%Trap2U1%
MsgBox(
( 
"GENERAL:
Window:(X:" GameLeft " Y:" GameTop " " GameW "x" GameH ")
InBattle:(" inbattle ")
Battles:(" battles ")
Round:(" roundnumber ") 
Player:(" player ")
Hammer:(" hitschool " (X:" hammerX " Y:" hitterY ")) 
Boss:(" BossChoosen ":(X:" BossX " Y:" BossY "))
Enemy Health:(" HealthInfo ")
Boosts(" boosts ":" boostlimit ")

CARDS: 
Sharpen:(" sharpen ") 
Potent:(" potent ")
Blade:(" blade ") 
Blade2:(" blade2 ":(" bladetype ")) 
Balanceblade:(" blade3 ")
Bladestorm:(" blade4 ")
Convert(" convert ")
Trap:(" trap ")  
Trap2:(" trap2 ":(" traptype "))
Trap3:(" trap3 ")
Feint:(" feint ") 
Aura:(" aura ") 
Enchant:(" enchant ") 
Active Hits:(" hit4 ":" hit3 ":" hit2 ":" hit1 ") 
Tower:(" tower ")  
Reshuffle:(" reshuffle ")

     USED:
 F(" used2 ")   pF(" used1 ") 
B1(" DevB1 ") sB1(" DevSB1 ") " BladeDir "
B2(" DevB2 ") sB2(" DevSB2 ")
B3(" Used16 ") sB3(" Used15 ")
B4(" Used18 ") sB4(" Used17 ")
T1(" DevT1 ")  pT1(" DevPT1 ") " TrapDir "
T2(" DevT2 ")  pT2(" DevPT2 ")
T3(" Used8 ")  pT3(" Used7 ")
T4(" Used10 ") pT4(" Used9 ")

MODES: 
Developer(" devmode ") Command(" commandmode ") 
Respond(" responsemode ") Dual(" dualmode ")
Lore(" loremode ")"
))
}
return
}
;##############################################
HK1_() { ; (v1: a hotkey)
global
local v1Keep := V1Thread() ; (v1: each thread had its own ErrorLevel)
if (on = 1)
	{
	if (devmode = 1)
		{	
		;(battles only - Settings: battlesonly: not the developer's loop - X, clicks, random W A S D - nor the clicks of
		;Windows+`'s lines after it, which it runs on into)
		if (inbattle = 0 && BattlesOnlyNo("developer loop (Alt+0)", true))
			return
		if (inbattle = 0)
			{
			InstallMouseHook()
			InstallKeybdHook()
			CoordMode("Mouse", "Window")
			leftoffset := (A_ScreenWidth - 800) / 2
			topoffset := (A_ScreenHeight - 600) / 2
			up := 1
			left := 2
			right := 3
			down := 4
			Mousespeedfast := 5 ;Default is 5
			Mousespeedslow := 10 ;Default is 10
			Loading := 5100 ;Default is 5000
			Wait := 325 ;Default is 300
			Delay := 175 ;Default is 150
			BufferVar := 10 ;Default is 10
			
			Loop
				{
				BlockInput("SendAndMouse")
				;(your mouse locked - Settings.ahk MouseLockOn; a loop's turn takes about 20 s)
				MouseLockOn("dev", 120000)
				Sleep(Wait)
				Send("x")
				Sleep(Wait)
				Send("x")
				Sleep(Wait)
				MouseMove(625 + leftoffset, 470 + topoffset, Mousespeedfast)
				Click()
				Sleep(Wait)
				MouseMove(615 + leftoffset, 575 + topoffset, Mousespeedfast)
				Click()
				Sleep(BufferVar)
				MouseMove(A_ScreenWidth/2, A_ScreenHeight/2, Mousespeedfast)
				BlockInput("SendAndMouse")
				MouseLockRenew()
				Sleep(Loading)
				Loop 600
					{
					direction := Random(1, 4)
					if (direction == up) 
					{
					Send("w")
					}
					if (direction == left) 
					{
					Send("a")
					} 
					if (direction == right) 
					{
					Send("d")
					}
					if (direction == down) 
					{
					 Send("s")
					 }
					Sleep(BufferVar)
					}
				;(v1: "sleep, %Loading% - 1500a" - not a number: it slept 0 ms)
				Sleep(0)
				MouseMove(610 + leftoffset, 575 + topoffset, Mousespeedfast)
				Sleep(Delay)
				Click()
				Sleep(Delay)
				MouseMove(170 + leftoffset, 470 + topoffset, Mousespeedfast)
				Click()
				Sleep(Delay)
				MouseMove(615 + leftoffset, 575 + topoffset, Mousespeedfast)
				Click()
				Sleep(Wait)
				MouseMove(635 + leftoffset, 540 + topoffset, Mousespeedfast)
				Click()
				Sleep(Delay)
				MouseMove(180 + leftoffset, 570 + topoffset, Mousespeedfast)
				Click()
				MouseMove(A_ScreenWidth/2, A_ScreenHeight/2, Mousespeedslow)
				Sleep(Loading)
				BlockInput("Off")
				MouseLockOff("dev")
				}
			}
		}
	}
;(v1: no return before #`:: - Alt+0's lines ran on into Win+`'s)
HK2_()
}
;##############################################
HK2_() { ; (v1: a hotkey)
global
if (on = 1)
	{
	if (devmode = 1)
		{
		;(battles only - Settings: battlesonly: not developer mode's endless clicks out of battle - as Alt+0's loop)
		if (inbattle = 0 && BattlesOnlyNo("developer clicks (Windows+``)", true))
			return
		Loop
			{
			Click()
			}
		}
	}
return
}
;##############################################
HkQuit(*) { ; (v1: a label - a hotkey's: Hotkeys.ahk HkRun calls it by name)
global
ExitApp()
}
;##############################################
HkRestart2(*) { ; (v1: a label - a hotkey's: Hotkeys.ahk HkRun calls it by name)
global
BotRestart()
return
}

;(v2 port, CONVENTIONS.md "Blank start": v1 started every variable blank; v2 leaves it unset and throws on
;reading it. The entry script calls this first thing: this file's globals start blank, as in v1)
AutofarmerBlank()
	{
	global on := "", BotOn := "", BotStandby := "", BotEverOn := "", BotGameSeenAt := "", PotionManual := "", Stats := "", EnemyHP := ""
	global BossSlot := "", HealthStatus := "", AppliedBlades := "", BossTraps := "", AuraRounds := "", EnchantedHits := "", PipSaveFor := ""
	global PipSaveRounds := "", PipSaveGaveUp := "", OwnHpPct := "", OwnHpRound := "", PipSaveBare := "", PipSaveTarget := "", PipSaveLastPips := ""
	global PipSaveStall := "", PipOrbs := "", PlayerActive := "", PlayerTookRound := "", RoundLeft := "", RoundAgain := "", PlayForMe := ""
	global MobWalkMs := "", EnemyPhaseDone := "", PlateDuel := "", BookSeenAt := "", PassSeenAt := "", PassNudgeAt := "", PassNudges := ""
	global PassNudgeSaidAt := "", PassHover := "", PassHoverSaidAt := "", PipsNow := "", PipsNote := "", BoostRun := "", BossMax := ""
	global DualBattle := "", BattleRole := "", HammerSchool := "", HammerName := "", HammerSlot := "", ManualSchool := "", HammerGroup := ""
	global SidePlates := "", SidePlatesKey := "", MySlot := "", PartyLowX := "", PartyLowY := "", PartyLowPct := "", PartyLowName := ""
	global PartyLowKey := "", PartyHits := "", PartyHitR := "", PartyHitsSeen := "", PartyHitsDuel := "", PartyHitsWait := "", PartyMySchool := ""
	global PartyFlagRound := "", PartyFlagDuel := "", PartyCastRound := "", PartySrcRound := "", TrapOn := "", TrapAtX := "", TrapAtY := ""
	global TrapMine := "", TrapAtMax := "", TrapPick := "", TrapWhy := "", TrapFoeX := "", TrapFoeY := "", TrapFoeMax := "", TrapFoeN := ""
	global TrapSlot := "", SlotGame := "", HeadsMemo := "", BoostPctMem := "", AuraSch := "", PartyLastSch := "", PlanHit := "", PlanHeads := ""
	global PlanList := "", BladeDir := "", TrapDir := "", BladeU1 := "", BladeU2 := "", TrapU1 := "", TrapU2 := "", Blade2U1 := "", Blade2U2 := ""
	global Trap2U1 := "", Trap2U2 := "", PlanWait := "", SbFound := "", GbFound := "", BoostHand := "", BoostSrcUsed := "", BoostExtra := ""
	global HammerPlan := "", BoostMemOk := "", BoostSaid := "", BoostMisfitDone := "", BoostUnrec := "", BoostOneOfOff := "", BoostMemOnly := ""
	global BubbleUp := "", absorb := "", absorbX := "", absorbY := "", AbsorbFreeOk := "", AbsorbOnlyFree := "", negaura := "", NegAuraOn := ""
	global ConvertOn := "", inbattle := "", roundnumber := "", battles := "", BossChoosen := "", BossRelX := "", BossRelY := "", EnemyPlates := ""
	global EnemyPlatesAt := "", boosts := "", afkVar := "", bossX := "", bossY := "", GameExe := "", GameClass := "", CardTol := "", PicSets := ""
	global PicSet := "", PicDir := "", UiScale := "", LastSetTry := "", HandHalf := "", HalfPitch := "", GameLeft := "", GameTop := "", GameW := ""
	global GameH := "", GameRight := "", GameBottom := "", ScreenX := "", ScreenY := "", StatsWanted := "", commandmode := "", dualmode := ""
	global responcemode := "", devmode := "", loremode := "", boostlimitmode := "", dualhittermode := "", statsmode := "", loopmode := "", Tick := ""
	global AfkWhy := "", AfkRetries := "", PicSetOkAt := "", PicSetOkSize := "", BufferVar := "", Half := "", Second := "", Five := "", Ten := ""
	global Loading := "", playerX := "", playerY := "", player := "", PlateByName := "", school := "", schoolX := "", schoolY := "", hitter := ""
	global hitschool := "", hammerX := "", hammerY := "", hitterX := "", hitterY := "", sharpen := "", potent := "", blade := "", blade3 := ""
	global blade4 := "", trap := "", trap3 := "", aura := "", tower := "", reshuffle := "", feint := "", bubble := "", convert := "", hit4 := ""
	global hit3 := "", hit2 := "", hit1 := "", wand := "", heal1 := "", heal2 := "", KillHit := "", KillEnchant := "", ManualPlayer := ""
	global bubbleX := "", Manual := "", blade2 := "", trap2 := "", enchant := "", enchantX := "", enchantY := "", OwnHpCur := "", OwnHpAt := ""
	global OwnHpWin := "", OwnHpMax := "", OwnHpVotes := "", VisionPlateWhy := "", used := "", hit := "", passX := "", passY := "", VisionOn := ""
	global LearnHitFails := "", RcOn := "", Tray := "", LearnAll := "", KeysDown := "", HeldW := "", LastBeat := "", BlPhase := "", BlPhaseAt := ""
	global BlDuel := "", SeenOut := "", SpeedNow := "", PicError := "", PicMeasuredSize := "", PicMeasureSize := "", PotionResting := "", DgRun := ""
	global MouseHomeSet := "", MouseHomeX := "", MouseHomeY := "", ManualX := "", ManualY := "", trap4 := ""
	global FoundByMem := "", RoundMemSchool := "", PlateMem := "", HandStale := "", DeckSharp := "", SpentOff := "", SpentLook := ""
	;(v2-only: Wizard101 in the tray - Settings: traygame: GameTrayHide - the window, its process, minimized then, the
	;bot on then, when, and the window the X's hotkey is for)
	global GameInTray := 0, GameTrayHwnd := 0, GameTrayPid := 0, GameTrayMin := 0, GameTrayBotWas := 0, GameTrayAt := 0
	global GameTrayXWin := 0
	}
