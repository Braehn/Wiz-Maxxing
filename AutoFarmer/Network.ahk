#Warn Unreachable, Off
; Network.ahk - the dashboard's Network tab (v0.46.0, asked 2026-10-24: a PC that runs the bot all day, watched and
; steered from another): every bot on your home network with Settings > Network on - its PC, version, wizard, zone,
; on / off, Play for me, what it's doing, health, mana, deaths - and, once you pick it, its recent log and its game's
; picture; buttons turn it on or off, switch its Play for me off or restart it (with the network PIN, the same on both
; PCs - Settings: netpin). Play for me can only be switched OFF from the network: on only at that PC (its button).
; The vision helper does the talking (vision\netmon.py): NetTick tells it this bot's state every 2 s and takes the
; others' and any commands for this one. Settings: neton (off till you switch it on - Windows then asks once to let
; Python through its firewall: allow it on Private networks), netport, netpin. AutoHotkey v1.1, #Included by
; Autofarmer.ahk.

;The bots heard ([{id, ip, age, pc, ver, wiz, school, zone, bot, pfm, doing, hp, mana, deaths, dall, up, status, last}]),
;this bot's network state and why, the last line of its log, the bot picked on the tab (its id), when its log and
;picture were last fetched, when NetTick first ran (the uptime sent)
global NetPeers, NetState, NetWhy, NetLastLine, NetSel, NetLogAt, NetSnapAt, NetStartAt
;The picked bot's PC (the pick kept when it restarts - its id is new each start); a refresh asked for; the Network tab's
;controls (Dashboard.ahk - a control's variable has to be global)
global NetSelPc, NetRefresh
global NetHelp, NetOnBtn, NetOffBtn, NetPfmBtn, NetRestartBtn, NetRefreshBtn, NetStatus, NetList, NetLog, NetPic, NetPicNote
global DashNetId, DashNetCmd

NetTick:
NetTick()
return

NetRestartNow:
NetRestartNow()
return

;This bot's state to the helper and the others' (and commands for this one) back; the picked bot's log and picture
;fetched every 6 s while the Network tab is up
NetTick()
	{
	static wasOn := 0, schoolAt := 0, school := "", busy := 0
	global NetState, NetWhy, NetPeers, NetStartAt, NetRefresh, NetSel ; (v1 globals it sets)
	local v1Keep := V1Thread() ; (v1: each thread had its own ErrorLevel)
	if (busy || !VisionOn || !V1IsFunc("VisionGet"))
		return
	netOn := Stat("neton") ? 1 : 0
	;(never on: the helper isn't asked at all - no sockets, no firewall question)
	if (!netOn && !wasOn)
		{
		NetState := "off", NetWhy := "Settings > NETWORK > neton", NetPeers := []
		if (V1IsFunc("DashNetFill"))
			DashNetFill.Call()
		return
		}
	busy := 1
	wasOn := netOn
	NetStartAt := NetStartAt ? NetStartAt : A_TickCount
	;(the school this character fights as - looked for once in 20 s)
	if (!schoolAt || A_TickCount - schoolAt > 20000)
		schoolAt := A_TickCount, school := StatsSchoolOf(StatsCharID())
	bot := (BotStandby && !BotEverOn) ? "standby" : BotOn ? "on" : "off"
	;(battles only - Settings: battlesonly - Autofarmer.ahk: waiting for a battle, moving nothing)
	doing := !BotOn ? "off" : inbattle = 1 ? "in a battle" : WkLoading ? "loading" : PlayerActive ? "you're playing"
		: (V1IsFunc("BattlesOnly") && BattlesOnly.Call()) ? "battles only" : !Walking ? "walking off (" HkText("walk") ")" : WkArrived = 7 ? "collecting" : "walking"
	see := IsObject(DashSees) ? DashSees : V1Obj()
	hp := RegExReplace(see.hp, "\s*\(.*")
	;(the bot picked - fetched by the helper's own thread only while the Network tab's up)
	shown := V1IsFunc("DashNetShown") && DashNetShown.Call()
	;(v1: Round of a setting that isn't a number - 0)
	q := "/net?on=" netOn "&sel=" (shown ? NetSel : "") "&refresh=" (NetRefresh ? 1 : 0) "&port=" V1Round(Stat("netport")) "&pin=" V1Round(Stat("netpin")) "&pc=" NavUri(A_ComputerName)
		. "&ver=" NavUri(BotVersion()) "&wiz=" NavUri(OwnName()) "&school=" school "&zone=" NavUri(WalkZone())
		. "&bot=" bot "&pfm=" (PlayForMe ? 1 : 0) "&doing=" NavUri(doing) "&hp=" NavUri(hp) "&mana=" NavUri(see.mana)
		. "&deaths=" (IsObject(DashN) && DashN.deaths ? DashN.deaths : 0) "&dall=" (V1IsFunc("DashDeathsAll") ? DashDeathsAll.Call() : 0)
		. "&up=" Round((A_TickCount - NetStartAt) / 1000) "&status=" NavUri(SubStr(StatusText, 1, 120)) "&last=" NavUri(SubStr(NetLastLine, 1, 160))
		. "&front=" (GameActive() ? 1 : 0) "&gx=" GameLeft "&gy=" GameTop "&gw=" GameW "&gh=" GameH
	NetRefresh := 0
	ans := VisionGet(q, 800, true)
	if (ans = "" || SubStr(ans, 1, 3) = "ERR")
		{
		NetState := "error", NetWhy := "the vision helper didn't answer", busy := 0
		return
		}
	peers := []
	;(v2 port: a field the line hasn't - V1At - was blank in v1)
	Loop Parse, ans, "`n", "`r"
		{
		f := StrSplit(A_LoopField, "|")
		if (f[1] = "net")
			{
			if (NetState != V1At(f, 2) || NetWhy != V1At(f, 3))
				DebugLog("Network: " V1At(f, 2) (V1At(f, 3) != "" ? " - " f[3] : ""))
			NetState := V1At(f, 2), NetWhy := V1At(f, 3)
			}
		else if (f[1] = "peer" && f.Length >= 19)
			peers.Push(V1Obj({id: f[2], ip: f[3], age: f[4], pc: f[5], ver: f[6], wiz: f[7], school: f[8], zone: f[9], bot: f[10]
				, pfm: f[11], doing: f[12], hp: f[13], mana: f[14], deaths: f[15], dall: f[16], up: f[17], status: f[18], last: f[19]}))
		else if (f[1] = "cmd")
			NetDo(V1At(f, 2), V1At(f, 3))
		}
	NetPeers := peers
	;(the pick by its PC: a bot started again has a new id)
	if (NetSelPc != "")
		{
		NetSel := ""
		for i, p in peers
			if (p.pc = NetSelPc)
				NetSel := p.id
		}
	if (V1IsFunc("DashNetFill"))
		DashNetFill.Call()
	;(the bot picked on the Network tab: its log and picture as the helper's fetched them - nothing waited for here)
	if (NetSel != "" && shown)
		NetFetchPicked()
	busy := 0
	}

;The picked bot's recent log and its game's picture as the helper's fetch thread has them, onto the Network tab
;(Dashboard.ahk DashNetShow) - an answer at once, never a wait on the network
NetFetchPicked()
	{
	static shownLog := ""
	global NetSnapAt ; (v1 globals it sets)
	sel := NetSel
	if (sel = "")
		return
	ans := VisionGet("/netpeer?id=" sel, 800, true)
	if (sel != NetSel)
		return
	if (ans = "")
		{
		why := RegExReplace(VisionErr, "^ERR\s*")
		;(shown afresh once it answers again)
		NetSnapAt := ""
		if (V1IsFunc("DashNetShow"))
			DashNetShow.Call("", "", why != "" ? why : "The vision helper didn't answer")
		return
		}
	text := "", pic := "", why := ""
	Loop Parse, ans, "`n", "`r"
		{
		if (SubStr(A_LoopField, 1, 4) = "log|")
			text .= SubStr(A_LoopField, 5) "`r`n"
		else if (SubStr(A_LoopField, 1, 5) = "snap|")
			pic := SubStr(A_LoopField, 6)
		else if (SubStr(A_LoopField, 1, 4) = "why|")
			why := SubStr(A_LoopField, 5)
		}
	pic := pic != "" && FileExist(pic) ? pic : ""
	;(the same picture and log as last shown: not loaded again - the helper's fetch thread gets them every 6 s, this runs
	;every 2 s, and the tab's note gives the time it's shown: it stays the time the picture came. Its "at" is how many
	;seconds ago - new at every ask, so 2026-11-27 review: never the same, every picture loaded again and stamped now. The
	;picture told by its file's time and size - the helper writes a new one over it each fetch. NetSnapAt: "" on a new
	;pick, Dashboard.ahk)
	snapKey := pic = "" ? "none" : pic "|" V1Try(FileGetTime, pic, "M") "|" V1Try(FileGetSize, pic)
	snapKey .= "|" why
	if (NetSnapAt != "" && snapKey == NetSnapAt && text == shownLog)
		return
	NetSnapAt := snapKey, shownLog := text
	if (V1IsFunc("DashNetShow"))
		DashNetShow.Call(text, pic, why)
	}

;A command from another bot on the network (netmon.py checked its PIN): done here, and said in the log
NetDo(c, from)
	{
	global PlayForMe ; (v1 globals it sets)
	who := from != "" ? from : "another PC"
	if (c = "on" && !BotOn)
		DebugLog("Network: " who " turned the bot on"), BotToggle()
	else if (c = "off" && BotOn)
		DebugLog("Network: " who " turned the bot off"), BotToggle()
	else if (c = "pfmoff" && PlayForMe)
		{
		PlayForMe := 0
		PlayForMeShow()
		DebugLog("Network: " who " switched Play for me off - the bot waits for you and keeps its hands off while you play, as set")
		}
	else if (c = "restart")
		{
		DebugLog("Network: " who " restarted the bot")
		SetTimer(NetRestartNow,-500)
		}
	else
		DebugLog("Network: " who " asked for '" c "' - it's that way already")
	}

;A command to the bot picked on the Network tab (signed with this PC's PIN by the helper): what came of it
NetSend(c)
	{
	if (NetSel = "")
		return "Pick a bot in the list first"
	ans := Trim(VisionGet("/netcmd?id=" NetSel "&c=" c, 4000, true), " `r`n")
	;(its ERR's why - VisionGet keeps it in VisionErr)
	if (ans = "")
		return VisionErr != "" ? RegExReplace(VisionErr, "^ERR\s*") : "The vision helper didn't answer"
	return SubStr(ans, 1, 3) = "ok|" ? "Sent - " SubStr(ans, 4) : SubStr(ans, 1, 4) = "ERR " ? SubStr(ans, 5) : ans
	}

;Seconds as "3 h 20 m" / "4 m" / "12 s"
;(v2 port: a peer's age as the network sent it - v1's Round of a blank or text: 0)
NetAge(s)
	{
	s := V1Round(s)
	return s >= 3600 ? (s // 3600) " h " Mod(s // 60, 60) " m" : s >= 60 ? (s // 60) " m" : s " s"
	}

;###############  v1's labels, as functions  ###############
NetRestartNow() { ; (v1: a label - its code ran in the global scope)
global
local v1Keep := V1Thread() ; (v1: each thread had its own ErrorLevel)
BotRestart()
return
}

;(v2 port, CONVENTIONS.md "Blank start": v1 started every variable blank; v2 leaves it unset and throws on
;reading it. The entry script calls this first thing: this file's globals start blank, as in v1)
NetworkBlank()
	{
	global NetPeers := "", NetState := "", NetWhy := "", NetLastLine := "", NetSel := "", NetLogAt := "", NetSnapAt := "", NetStartAt := ""
	global NetSelPc := "", NetRefresh := "", NetHelp := "", NetOnBtn := "", NetOffBtn := "", NetPfmBtn := "", NetRestartBtn := "", NetRefreshBtn := ""
	global NetStatus := "", NetList := "", NetLog := "", NetPic := "", NetPicNote := "", DashNetId := "", DashNetCmd := ""
	}
