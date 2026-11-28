#Warn Unreachable, Off
; Alerts.ahk - Discord alerts when the wizard needs you, through a webhook of your Discord channel. AHK v1.1, functions
; and labels only; #Included by Autofarmer.ahk.
;
; Sent for: the walker's "needs you" notices (stuck, a teleport that doesn't work, no quest arrow, waiting at the
; quest goal, a collect quest), out of potions with none to be had, "Crowns" seen in a potion run or a quick sell, out of
; mana, a wizard whose school the bot doesn't know, the backpack full and not quick sold (inventory - held for a dungeon's
; drops, quick sell failing, an Equipment Set's item sold), the gold bag nearly full (gold - Prospector Zeke's alert), and
; not getting back into the game (a login turned
; down, patching, the launcher, a ban or another login). The message says what's wrong, the zone and the time -
; nothing else: never a login, never a screenshot.
;
; The webhook's address is kept in Windows Credential Manager as "Wiz-Maxxing Discord webhook" - never in a file,
; never in debug.log (tray menu "Discord alerts...": set it - a test message is sent - or type OFF to remove it).
; alertson:0 in PlayerStats.txt (the Settings window) switches the alerts off. The same alert at most once in 10
; minutes; alerts less than 20 s apart wait their turn (held, then sent - never dropped); sent in the background
; (the bot doesn't wait for Discord) and the answer logged ("Discord: ...").

;When each kind was last sent (kind -> tick; "" -> any); the sends still under way ({req, kind, at}); alerts held
;for the 20 s gap ({kind, title, text}); tests only: another address for every send
global AlertLast, AlertReqs, AlertTestUrl, AlertWait

AlertTarget()
	{
	return "Wiz-Maxxing Discord webhook"
	}

;The webhook's address from Windows Credential Manager ("" none)
AlertUrl()
	{
	if (AlertTestUrl != "")
		return AlertTestUrl
	credPtr := 0, url := ""
	is64 := (A_PtrSize = 8)
	targetW := Buffer((StrLen(AlertTarget()) + 1) * 2, 0), StrPut(AlertTarget(), targetW.Ptr, "UTF-16")
	if (!DllCall("Advapi32\CredReadW", "Ptr", targetW.Ptr, "UInt", 1, "UInt", 0, "Ptr*", &credPtr) || !credPtr)
		return ""
	blobSize := NumGet(credPtr + 0, is64 ? 32 : 24, "UInt")
	blobPtr := NumGet(credPtr + 0, is64 ? 40 : 28, "Ptr")
	if (blobPtr && blobSize)
		url := StrGet(blobPtr, blobSize // 2, "UTF-16")
	DllCall("Advapi32\CredFree", "Ptr", credPtr)
	return Trim(url)
	}

;Keeps the webhook's address in Windows Credential Manager ("" removes it). True if done
AlertUrlSave(url)
	{
	targetW := Buffer((StrLen(AlertTarget()) + 1) * 2, 0), StrPut(AlertTarget(), targetW.Ptr, "UTF-16")
	if (url = "")
		{
		DllCall("Advapi32\CredDeleteW", "Ptr", targetW.Ptr, "UInt", 1, "UInt", 0)
		return AlertUrl() = ""
		}
	is64 := (A_PtrSize = 8)
	user := "discord-webhook"
	userW := Buffer((StrLen(user) + 1) * 2, 0), StrPut(user, userW.Ptr, "UTF-16")
	blobSize := StrLen(url) * 2
	blob := Buffer(blobSize + 2, 0), StrPut(url, blob.Ptr, "UTF-16")
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

;A Discord webhook's address: https://discord.com/api/webhooks/<id>/<token> (also discordapp.com, ptb., canary.)
AlertUrlOk(url)
	{
	return RegExMatch(url, "^https://(?:ptb\.|canary\.)?discord(?:app)?\.com/api/webhooks/\d+/[\w-]+$")
	}

;An alert, if they're on and a webhook's set: kind and title - the same alert (both alike) at most once in 10 minutes,
;one not sent said in debug.log; title, text - what's
;wrong and what to do; link - a page about it (the quest's Wizard101 Central page: Walker.ahk WalkNotify), its own line right
;under the title - before the text, so the 1900-character cut can't drop it - in <...> (no preview). Sent in the background
AlertSend(kind, title, text, link := "")
	{
	global AlertLast, AlertWait ; (v1 globals it sets)
	;(the log's OneDrive copy, when it's on: what the game showed - at most every 20 s)
	if (V1IsFunc("LogMirrorSnap"))
		LogMirrorSnap.Call(20000, kind)
	if (Stats.Has("alertson") && !Stats["alertson"])
		return
	url := AlertUrl()
	if (url = "")
		return
	if (!IsObject(AlertLast))
		AlertLast := V1Obj()
	now := A_TickCount
	;(the same alert: its kind and its title - one kind has several alerts ("inventory": a backpack full in a dungeon,
	;and minutes later an Equipment Set's item sold; "potions": not drinking, then none left), and a kind alone
	;swallowed the second one for 10 minutes, unlogged)
	same := kind "|" title
	if (AlertLast.Has(same) && now - AlertLast[same] < 600000)
		{
		;(said once for each one sent - a round's alert comes again every round)
		if (!AlertLast.Has(same "|said") || AlertLast[same "|said"] != AlertLast[same])
			{
			AlertLast[same "|said"] := AlertLast[same]
			DebugLog("Discord: alert '" title "' not sent - the same one went " Round((now - AlertLast[same]) / 60000) " min ago (once in 10 minutes)")
			}
		return
		}
	;(another went less than 20 s ago: this one waits its turn - an alert that the bot has stopped often comes
	;right after the one that led to it)
	if (AlertLast.Has("") && now - AlertLast[""] < 20000)
		{
		if (!IsObject(AlertWait))
			AlertWait := []
		for i, w in AlertWait
			if (w.kind = kind && w.title = title)
				return
		AlertWait.Push(V1Obj({kind: kind, title: title, text: text, link: link}))
		DebugLog("Discord: alert '" title "' held - another went less than 20 s ago")
		SetTimer(AlertFlush,-(20000 - (now - AlertLast[""]) + 200))
		return
		}
	AlertLast[same] := now, AlertLast[""] := now
	zone := V1IsFunc("WalkZone") ? WalkZone.Call() : ""
	at := FormatTime(, "HH:mm")
	AlertPost(url, "**Wizard101 bot needs you: " title "**" (link != "" ? "`n<" link ">" : "") "`n" text "`n_" (zone != "" ? zone " - " : "") at "_", kind)
	}

;Posts content to the webhook in the background (wait: until Discord answers, up to 10 s - the HTTP status, or ""
;when it couldn't be sent). Never logs the address
AlertPost(url, content, kind, wait := false)
	{
	global AlertReqs ; (v1 globals it sets)
	body := "{`"content`": `"" AlertJson(SubStr(content, 1, 1900)) "`", `"username`": `"Wiz-Maxxing`", `"allowed_mentions`": {`"parse`": []}}"
	try
		{
		req := ComObject("WinHttp.WinHttpRequest.5.1")
		req.Open("POST", url, !wait)
		req.SetTimeouts(5000, 5000, 10000, 10000)
		req.SetRequestHeader("Content-Type", "application/json; charset=utf-8")
		req.Send(body)
		}
	Catch Error as e
		{
		DebugLog("Discord: alert '" kind "' couldn't be sent (" e.Message ")")
		return ""
		}
	if (wait)
		return req.Status
	if (!IsObject(AlertReqs))
		AlertReqs := []
	AlertReqs.Push(V1Obj({req: req, kind: kind, at: A_TickCount}))
	SetTimer(AlertPoll,1000)
	return ""
	}

;The sends under way: their answers logged (204 = Discord took it)
AlertPoll()
	{
	local v1Keep := V1Thread() ; (v1: each thread had its own ErrorLevel)
	if (!IsObject(AlertReqs) || !AlertReqs.Length)
		{
		SetTimer(AlertPoll,0)
		return
		}
	i := 1
	while (i <= AlertReqs.Length)
		{
		r := AlertReqs[i]
		done := false
		try done := r.req.WaitForResponse(0)
		if (done)
			{
			status := ""
			try status := r.req.Status
			DebugLog("Discord: alert '" r.kind "' " ((status = 204 || status = 200) ? "sent" : "not taken (HTTP " status (status = 404 ? " - the webhook was deleted? Tray menu: Discord alerts..." : status = 429 ? " - too many messages for now" : "") ")"))
			AlertReqs.RemoveAt(i)
			continue
			}
		if (A_TickCount - r.at > 30000)
			{
			DebugLog("Discord: alert '" r.kind "' - no answer from Discord in 30 s")
			AlertReqs.RemoveAt(i)
			continue
			}
		i += 1
		}
	}

;s for a JSON string: backslash, quote and control characters escaped
AlertJson(s)
	{
	s := StrReplace(s, "\", "\\")
	s := StrReplace(s, "`"", "\`"")
	s := StrReplace(s, "`r", "")
	s := StrReplace(s, "`n", "\n")
	s := StrReplace(s, "`t", "\t")
	return RegExReplace(s, "[\x00-\x1F]", " ")
	}

;Tray menu "Discord alerts...": set the webhook (a test message is sent), test the one there (empty), or OFF to
;remove it. The address is typed hidden and kept only in Windows Credential Manager
AlertSetup()
	{
	global ErrorLevel ; (v1 globals it sets)
	;(a walking key the bot holds let go: this box can stay up a while)
	if (V1IsFunc("ReleaseKeys"))
		ReleaseKeys.Call()
	have := AlertUrl() != ""
	prompt := have ? "Alerts go to a Discord webhook already.`n`nPaste a new webhook address to change it, leave it empty to send a test message, or type OFF to remove it." : "In Discord: the channel's settings > Integrations > Webhooks > New Webhook > Copy Webhook URL.`nPaste it here - it's kept in Windows Credential Manager on this PC only.`n`nThe bot then messages that channel when the wizard needs you."
	IB := InputBox(prompt, "Discord alerts", "Password w560 h210"), url := IB.Value, ErrorLevel := IB.Result="OK" ? 0 : IB.Result="CANCEL" ? 1 : IB.Result="Timeout" ? 2 : "ERROR"
	if (ErrorLevel)
		return
	url := Trim(url)
	if (url = "OFF" || url = "off")
		{
		AlertUrlSave("")
		DebugLog("Discord: alerts' webhook removed")
		TrayTip("Discord alerts are off (the webhook was removed).", "Wizard101 bot", 1)
		return
		}
	isNew := (url != "")
	if (!isNew)
		{
		if (!have)
			return
		url := AlertUrl()
		}
	else if (!AlertUrlOk(url))
		{
		MsgBox("That isn't a Discord webhook address (it starts https://discord.com/api/webhooks/). Nothing was changed.", "Discord alerts", 48)
		return
		}
	;(the test first: a new address is kept only once Discord takes it - the one there before stays otherwise)
	status := AlertPost(url, "**Wiz-Maxxing alerts are on.** This channel gets a message when the wizard needs you.", "test", true)
	took := (status = 204 || status = 200)
	saved := !isNew || (took && AlertUrlSave(url))
	url := ""
	DebugLog("Discord: test message - " (took ? "sent" : "not taken (HTTP " status ")"))
	off := (Stats.Has("alertson") && !Stats["alertson"])
	if (took && !saved)
		MsgBox("The test message went through, but the address couldn't be kept in Windows Credential Manager - nothing was changed.", "Discord alerts", 48)
	else if (took)
		MsgBox("A test message went to your Discord channel. " (off ? "Alerts are switched off in the Settings window, though (`"Discord alerts when the wizard needs you`") - tick it to get them." : "Alerts are on."), "Discord alerts", 64)
	else
		MsgBox("Discord didn't take the test message (" (status = "" ? "no answer" : "HTTP " status) "). " (isNew ? "The new address wasn't kept" (have ? " - alerts still go to the one before" : "") "." : "Check the webhook still exists, then try again."), "Discord alerts", 48)
	}

AlertPoll:
AlertPoll()
	return

;An alert held for the 20 s gap: sent now (the rules checked again), the next one 20 s later
AlertFlush:
AlertFlush()
	return

;###############  (v2 port: v1's labels, as functions)  ###############
AlertFlush() { ; (v1: a label - its code ran in the global scope)
	global
	local v1Keep := V1Thread() ; (v1: each thread had its own ErrorLevel)
	if (IsObject(AlertWait) && AlertWait.Length)
		{
		AlertFlushOne := AlertWait.RemoveAt(1)
		AlertSend(AlertFlushOne.kind, AlertFlushOne.title, AlertFlushOne.text, AlertFlushOne.link)
		if (AlertWait.Length)
			SetTimer(AlertFlush,-20200)
		}
	return
}

;(v2 port, CONVENTIONS.md "Blank start": v1 started every variable blank; v2 leaves it unset and throws on
;reading it. The entry script calls this first thing: this file's globals start blank, as in v1)
AlertsBlank()
	{
	global AlertLast := "", AlertReqs := "", AlertTestUrl := "", AlertWait := ""
	}
