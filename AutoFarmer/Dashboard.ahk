#Warn Unreachable, Off
; Dashboard.ahk - a window with the bot's statistics, what it sees right now, and a live log (every line
; of debug.log as it's written). AHK v1.1, functions and labels only; #Included by Autofarmer.ahk.
;
; Windows+2 or the tray menu shows / hides it; its X stops the bot - or, with "Put the bot's window in the
; tray" on (Settings: traybot), its X and minimize button put it in the tray and the bot plays on (DashToTray).
; It opens on a monitor the game isn't on (if there is one) and remembers where you put it (dashboard.ini). It
; never takes the focus by itself - clicking into it does, and the walker waits while Wizard101 isn't the active
; window.
;
; The numbers come from the log lines (DashLog sees every DebugLog line) plus a few calls from the battle
; code: DashCast (a card was cast), DashSee (what the bot sees: the hand, enemies, your health...).
;
; Its menu bar - File, Bot, View, Settings, Help (v1.10.0: most of the buttons moved there) - is "The menu bar"
; below. View > Map (or the tray menu) opens a second window: a top-down picture of the zone the wizard is in,
; drawn by the vision helper (/navmap) - see "The map" below.

global DashHwnd, DashCon, DashShown, DashPaused, DashHeld, DashStart ;(v1 never ran: DashHwnd := 0, DashCon := 0, DashShown := 0, DashPaused := 0, DashHeld := "", DashStart := 0 - blank at start: DashboardBlank)
;Counts (rounds, passes, ...) and casts per card; what it sees ({key: text}); card names off PlayerStats.txt
global DashN, DashCasts, DashSees, DashNames ;(v1 never ran: DashN := "", DashCasts := "", DashSees := "", DashNames := "" - blank at start: DashboardBlank)
global DashHead, DashStatText, DashSeeText, DashConsole
;CPU and RAM in use, on the STATISTICS row (DashUsage)
global DashUsageText
;The view: simple (1 - what it's doing and seeing: no log) or advanced (0 - everything, the log too); View > Simple
;view switches it. The LOG heading
global DashSimple, DashLogHead
;The Colours window's swatches and buttons (View > Log colours...: DashLogColorsWindow)
global LogColHwnd
;Help > Check for updates says "Checking..." a while after a click (DashUpdBusy: when - DashUpdButton)
global DashUpdBusy
;The "Play for me" button (a coloured bar - red off, green on - and clickable words: a button can't be coloured) -
;Autofarmer.ahk PlayForMeToggle
global DashPlayBtn, DashPlayBg
;Where the tabs' inside starts in the window (GuiControl Move places a tab's controls from there: DashGuiSize)
global DashTabOX, DashTabOY, DashTabOW, DashTabOH
;The bot on / off button, at the heading row's right end (BotToggle in Autofarmer.ahk)
global DashBotBtn
;The menu bar's menus ({file, bot, view, set, help, bar} - DashMenuMake; "" till it's made)
global DashMenus
;The Cards tab: your hand - its heading, and a picture and a label for each of up to 7 cards - and the enemies' spells
;(their heading and list: DashFoesSeen)
global DashFoeHead, DashFoeList
global DashLearnBtn, DashHandHead, DashCardPic1, DashCardPic2, DashCardPic3, DashCardPic4, DashCardPic5, DashCardPic6, DashCardPic7
global DashCardTxt1, DashCardTxt2, DashCardTxt3, DashCardTxt4, DashCardTxt5, DashCardTxt6, DashCardTxt7
;The map window: the window, its picture and line; the request it's waiting for (kind: map / nav, sent at); when
;it last asked for a picture and at what size (screen pixels); the picture's file; what went wrong with the
;picture; /nav's last answer; when the picture shown was made
global DashMapHwnd, DashMapPic, DashMapPicH, DashMapText, DashMapShown, DashMapReq, DashMapKind, DashMapReqAt
global DashMapAt, DashMapW, DashMapH, DashMapFile, DashMapNote, DashMapNav, DashMapPicAt

;Makes the window (shown unless dashboard.ini says it was hidden). Called once at start
;(v2 port: the window is the Gui object Dash, its map window MapGui, the Colours window LogCol - each control by its
;v1 variable's name: Dash["DashHead"]. Every v1 gLabel is a DashGLabel binding: the label's function called as v1
;ran the label - Dungeons', Spells', Decks' and Hotkeys' too, by their v1 label names)
DashInit()
	{
	global DashN, DashCasts, DashSees, DashStart, DashSimple, DashCon, Dash, DashHwnd ; (v1 globals it sets)
	DashN := V1Obj(), DashCasts := V1Obj(), DashSees := V1Obj(), DashStart := A_TickCount
	DashSimple := ViewSimple("dashboard")
	;(v1: the log box's hwnd blank till the box is made, and DllCall took a blank as 0 - v2 throws on a blank: a line
	;logged in between - by another thread, DashHwnd set already - goes to no window, as in v1)
	DashCon := 0
	Dash := Gui("+Resize +MinSize740x640", "Wizard101 bot " BotVersion()), DashHwnd := Dash.Hwnd
	Dash.OnEvent("Close", DashGuiClose)
	Dash.OnEvent("Size", DashGuiSize)
	;(v1: Gui, Dash:Color, 1B1D22, 111317 - v2 has no control colour for the window: each Edit and DropDownList that
	;took it says Background111317 itself, as the ListViews do; the read-only NetLog took the window's, 1B1D22. v1's
	;DropDownList face had the window's colour too, its list the controls' - v2's Background is one colour for both)
	Dash.BackColor := "1B1D22"
	Dash.MarginX := 12, Dash.MarginY := 10
	Dash.SetFont("s11 w600 cF2F2F2", "Segoe UI")
	Dash.Add("Text", "x12 y10 w622 h22 vDashHead", BotVersion())
	;(the bot on / off: the heading row's right end - DashGuiSize keeps it there; its words: DashBotShow, DashKeysChanged.
	;"on" till BotOnShow says how it is, as the bot starts)
	Dash.SetFont("s9 w400 c000000", "Segoe UI")
	Dash.Add("Button", "x640 y7 w136 h24 vDashBotBtn", "Bot: on (" HkText("bot") ")").OnEvent("Click", DashGLabel.Bind(DashBotToggle, "Normal"))
	;Six tabs: Bot (statistics, what it sees, the log), Dungeons (Dungeons.ahk), Spells (the cards the bot learned by
	;itself: Spells.ahk), Cards (your hand, the enemies' spells), Network (Network.ahk) and Keys (Hotkeys.ahk)
	Dash.SetFont("s9 w600 cF2F2F2", "Segoe UI")
	tabs := Dash.Add("Tab3", "x6 y36 w772 h742 +Buttons -Theme vDashTabs", ["Bot", "Dungeons", "Spells", "Cards", "Network", "Keys"])
	tabs.UseTab(1)
	Dash.SetFont("s9 w600 c8AB4F8", "Segoe UI")
	Dash.Add("Text", "x12 y68 w86 h16", "STATISTICS")
	Dash.SetFont("s8 w400 c9AA0A6", "Segoe UI")
	Dash.Add("Text", "x100 y69 w270 h16 vDashUsageText", "CPU / RAM ...")
	Dash.SetFont("s9 w600 c8AB4F8", "Segoe UI")
	Dash.Add("Text", "x372 y68 w150 h16", "WHAT IT SEES")
	Dash.SetFont("s9 w400 cDADADA", "Consolas")
	Dash.Add("Text", "x12 y88 w350 h190 vDashStatText")
	Dash.Add("Text", "x372 y88 w400 h196 vDashSeeText")
	Dash.SetFont("s9 w600 c8AB4F8", "Segoe UI")
	Dash.Add("Text", "x12 y286 w200 h16 vDashLogHead", "LOG")
	;(each kind of line in its colour - movement, battle, waits... - set in View > Log colours...: a rich edit, as an
	;Edit can't colour its lines; read-only, no wrap. Down to the window's bottom - DashGuiSize)
	Dash.SetFont("s9 w400 cB9E2B9", "Consolas")
	DllCall("LoadLibrary", "Str", "Msftedit.dll", "Ptr")
	DashCon := Dash.Add("Custom", "ClassRICHEDIT50W x12 y306 w760 h468 +0x200000 +0x100000 +0x4 +0x800 +0x100 +0x40 +0x80 vDashConsole").Hwnd
	DashLogInit()
	;The Dungeons tab: a run recorded once, walked again and again (Dungeons.ahk)
	tabs.UseTab(2)
	Dash.SetFont("s9 w600 c8AB4F8", "Segoe UI")
	Dash.Add("Text", "x12 y68 w400 h16", "DUNGEON FARMING")
	Dash.SetFont("s9 w400 c9AA0A6", "Segoe UI")
	Dash.Add("Text", "x12 y88 w760 h48 vDgHelp", DashDgHelpText())
	Dash.SetFont("s9 w400 c000000", "Segoe UI")
	Dash.Add("Button", "x12 y142 w120 h26 vDgRecBtn", "Record a run").OnEvent("Click", DashGLabel.Bind(DgRecordClick, "Normal"))
	Dash.Add("Button", "x138 y142 w150 h26 vDgRecStopBtn Disabled", "Stop recording (" HkText("record") ")").OnEvent("Click", DashGLabel.Bind(DgRecStopClick, "Normal"))
	Dash.Add("Button", "x300 y142 w90 h26 vDgRunBtn", "Run").OnEvent("Click", DashGLabel.Bind(DgRunClick, "Normal"))
	Dash.Add("Button", "x396 y142 w90 h26 vDgStopBtn Disabled", "Stop run").OnEvent("Click", DashGLabel.Bind(DgStopClick, "Normal"))
	Dash.Add("Button", "x498 y142 w90 h26 vDgDelBtn", "Delete").OnEvent("Click", DashGLabel.Bind(DgDeleteClick, "Normal"))
	Dash.Add("Button", "x594 y142 w110 h26 vDgFolderBtn", "Open folder").OnEvent("Click", DashGLabel.Bind(DgFolderClick, "Normal"))
	Dash.SetFont("s9 w400 cDADADA", "Segoe UI")
	Dash.Add("Text", "x12 y182 w44 h18 vDgTimesLabel", "Run it")
	Dash.SetFont("s9 w400 cF2F2F2", "Segoe UI")
	Dash.Add("Edit", "x58 y179 w60 h22 Number Right Background111317 vDgTimes", "0")
	Dash.Add("UpDown", "vDgTimesUD Range0-9999 0x80", "0")
	Dash.SetFont("s9 w400 cDADADA", "Segoe UI")
	Dash.Add("Text", "x126 y182 w220 h18 vDgTimesNote", "times (0 = until you stop it)")
	Dash.Add("Checkbox", "x352 y182 w186 h18 vDgAvoid", "Keep away from mobs on the way")
	;(the deck a run's fought with - kept in its file: Decks.ahk)
	Dash.Add("Text", "x542 y182 w36 h18 vDgDeckT", "Deck")
	Dash.SetFont("s9 w400 c000000", "Segoe UI")
	Dash.Add("DropDownList", "x580 y179 w190 AltSubmit Background111317 vDgDeck", ["(none)"]).OnEvent("Change", DashGLabel.Bind(DgDeckPick, "Normal"))
	Dash.SetFont("s9 w400 cDADADA", "Segoe UI")
	;(v1.0.0: "Until its gear is swapped" and the run after it - kept in the picked run's file: Dungeons.ahk DgGearSet; the gear
	;pass itself is Settings' gearswap - Gear.ahk)
	Dash.Add("Checkbox", "x12 y209 w300 h18 vDgUntilGear", "Until its gear is swapped (Settings: gearswap)").OnEvent("Click", DashGLabel.Bind(DgGearPick, "Normal"))
	Dash.Add("Text", "x318 y210 w30 h18 vDgNextT", "then")
	Dash.SetFont("s9 w400 c000000", "Segoe UI")
	Dash.Add("DropDownList", "x352 y206 w240 AltSubmit Background111317 vDgNextRun", ["(stop)"]).OnEvent("Change", DashGLabel.Bind(DgGearPick, "Normal"))
	Dash.SetFont("s9 w400 cDADADA", "Segoe UI")
	Dash.SetFont("s9 w400 cB9E2B9", "Consolas")
	Dash.Add("Text", "x12 y234 w760 h50 vDgStatus", "Not running.")
	Dash.SetFont("s9 w400 cDADADA", "Segoe UI")
	;(the Gear column - v1.0.0, after the hidden File one: DgSelected reads the 7th - its gear pass's state, learned\drops)
	lv := Dash.Add("ListView", "x12 y286 w760 h502 vDgList AltSubmit -Multi Background111317 cDADADA", ["Run", "Steps", "Zones", "X", "Battles", "Recorded", "File", "Gear"])
	lv.OnEvent("DoubleClick", DashGLabel.Bind(DgListEvent, "DoubleClick"))
	lv.OnNotify(-101, DashLvItem.Bind(DgListEvent))
	lv.ModifyCol(1, 260), lv.ModifyCol(2, "50 Integer"), lv.ModifyCol(3, "50 Integer"), lv.ModifyCol(4, "40 Integer"), lv.ModifyCol(5, "60 Integer")
	lv.ModifyCol(6, 120), lv.ModifyCol(7, 0), lv.ModifyCol(8, 170)
	;The Spells tab: the cards the bot learned by itself, and your corrections (Spells.ahk)
	tabs.UseTab(3)
	Dash.SetFont("s9 w600 c8AB4F8", "Segoe UI")
	Dash.Add("Text", "x12 y68 w400 h16", "LEARNED SPELLS")
	Dash.SetFont("s9 w400 c9AA0A6", "Segoe UI")
	Dash.Add("Text", "x12 y88 w760 h32 vSpHelp", "Every card the bot learned by itself, and what it took it for. Pick one to see it. Change kind or Edit puts one right (applied out of battle; the learner never changes what you set). Forget: out of the list.")
	Dash.SetFont("s9 w400 c000000", "Segoe UI")
	Dash.Add("Button", "x12 y124 w100 h26 vSpKindBtn", "Change kind...").OnEvent("Click", DashGLabel.Bind(SpKindClick, "Normal"))
	Dash.Add("Button", "x118 y124 w64 h26 vSpEditBtn", "Edit...").OnEvent("Click", DashGLabel.Bind(SpEditClick, "Normal"))
	Dash.Add("Button", "x188 y124 w64 h26 vSpForgetBtn", "Forget").OnEvent("Click", DashGLabel.Bind(SpForgetClick, "Normal"))
	Dash.Add("Button", "x258 y124 w96 h26 vSpHoldBtn", "Never discard").OnEvent("Click", DashGLabel.Bind(SpHoldClick, "Normal"))
	Dash.Add("Button", "x360 y124 w92 h26 vSpPicBtn", "Show picture").OnEvent("Click", DashGLabel.Bind(SpPicClick, "Normal"))
	Dash.Add("Button", "x458 y124 w86 h26 vSpFolderBtn", "Open folder").OnEvent("Click", DashGLabel.Bind(SpFolderClick, "Normal"))
	Dash.Add("Button", "x550 y124 w100 h26 vSpMovedBtn", "Moved away...").OnEvent("Click", DashGLabel.Bind(SpMovedClick, "Normal"))
	Dash.Add("Button", "x656 y124 w66 h26 vSpRefreshBtn", "Refresh").OnEvent("Click", DashGLabel.Bind(SpRefreshClick, "Normal"))
	Dash.SetFont("s9 w400 cB9E2B9", "Consolas")
	Dash.Add("Text", "x12 y156 w760 h30 vSpStatus")
	Dash.SetFont("s9 w400 cDADADA", "Segoe UI")
	lv := Dash.Add("ListView", "x12 y190 w612 h598 vSpList AltSubmit Background111317 cDADADA", ["Name", "Kind", "School", "Pips", "Value", "Sure", "In use", "Text read", "TC", "Learned", "Set", "Id"])
	lv.OnNotify(-101, DashLvItem.Bind(SpListEvent))
	lv.OnEvent("DoubleClick", DashGLabel.Bind(SpListEvent, "DoubleClick"))
	lv.ModifyCol(1, 96), lv.ModifyCol(2, 84), lv.ModifyCol(3, 50), lv.ModifyCol(4, 34), lv.ModifyCol(5, 66), lv.ModifyCol(6, "44 Integer")
	lv.ModifyCol(7, 112), lv.ModifyCol(8, 100), lv.ModifyCol(9, 26), lv.ModifyCol(10, 96), lv.ModifyCol(11, 50), lv.ModifyCol(12, 0)
	;(the spell picked: its picture, and what the bot took it for under it)
	Dash.Add("Picture", "x632 y190 w140 h233 Hidden vSpPreview")
	Dash.SetFont("s8 w400 cDADADA", "Segoe UI")
	Dash.Add("Text", "x632 y428 w140 h360 vSpPreviewTxt", "Pick a spell to see it.")
	;The Cards tab: your hand - each card as the bot saw it this round, and what it took it for (DashHandSeen) - and the
	;enemies' spells: what each is likely to cast this round (EnemySpells.ahk EnemyDanger: DashFoesSeen)
	tabs.UseTab(4)
	;(its row of views: your hand and the enemies, or one of your decks - Decks.ahk; push-like radio buttons: tabs inside a
	;tab can't be)
	Dash.SetFont("s9 w400 c000000", "Segoe UI")
	Dash.Add("Radio", "x12 y62 w110 h24 +0x1000 Group Checked vDeckView0", "Hand && enemies").OnEvent("Click", DashGLabel.Bind(DeckViewClick, "Normal"))
	Loop 6
		{
		dx := 126 + (A_Index - 1) * 96
		Dash.Add("Radio", "x" dx " y62 w92 h24 +0x1000 Hidden vDeckView" A_Index, "Deck " A_Index).OnEvent("Click", DashGLabel.Bind(DeckViewClick, "Normal"))
		}
	Dash.Add("Button", "x704 y62 w72 h24 vDeckAddBtn", "+ Deck").OnEvent("Click", DashGLabel.Bind(DeckAddClick, "Normal"))
	Dash.SetFont("s9 w600 c8AB4F8", "Segoe UI")
	Dash.Add("Text", "x12 y100 w630 h16 vDashHandHead", "YOUR HAND - nothing read yet (once a round in battle)")
	Dash.SetFont("s9 w400 c000000", "Segoe UI")
	Dash.Add("Button", "x646 y94 w130 h24 vDashLearnBtn", "Learn every card").OnEvent("Click", DashGLabel.Bind(DashLearnAll, "Normal"))
	Dash.SetFont("s8 w400 cDADADA", "Segoe UI")
	Loop 7
		{
		cx := 12 + (A_Index - 1) * 72
		Dash.Add("Picture", "x" cx " y122 w58 h97 Hidden vDashCardPic" A_Index)
		Dash.Add("Text", "x" cx " y221 w66 h28 Hidden vDashCardTxt" A_Index)
		}
	Dash.SetFont("s9 w600 c8AB4F8", "Segoe UI")
	Dash.Add("Text", "x12 y258 w760 h16 vDashFoeHead", "ENEMIES - nothing yet (each battle round, with Settings > Predict the enemies' spells on)")
	Dash.SetFont("s9 w400 cDADADA", "Segoe UI")
	lv := Dash.Add("ListView", "x12 y278 w760 h514 vDashFoeList NoSort -Multi Background111317 cDADADA", ["Enemy", "Spell", "This round", "Pips, what it does", "This battle", "Seen (all battles)"])
	lv.ModifyCol(1, 130), lv.ModifyCol(2, 170), lv.ModifyCol(3, 76), lv.ModifyCol(4, 186), lv.ModifyCol(5, 84), lv.ModifyCol(6, 96)
	;(a deck's view: what it is, what it's for, its damage, and the settings it has of its own - hidden till one's picked)
	Dash.SetFont("s9 w400 cDADADA", "Segoe UI")
	Dash.Add("Text", "x12 y101 w44 h18 Hidden vDeckFNameT", "Name")
	Dash.SetFont("s9 w400 cF2F2F2", "Segoe UI")
	Dash.Add("Edit", "x58 y98 w180 h22 Limit30 Hidden Background111317 vDeckFName")
	Dash.SetFont("s9 w400 cDADADA", "Segoe UI")
	Dash.Add("Text", "x250 y101 w48 h18 Hidden vDeckFSchoolT", "School")
	Dash.SetFont("s9 w400 c000000", "Segoe UI")
	Dash.Add("DropDownList", "x300 y98 w90 Hidden Background111317 vDeckFSchool", ["any", "storm", "fire", "myth", "balance", "ice", "life", "death"])
	Dash.SetFont("s9 w400 cDADADA", "Segoe UI")
	Dash.Add("Text", "x402 y101 w96 h18 Hidden vDeckFSetT", "Equipment Set")
	Dash.SetFont("s9 w400 cF2F2F2", "Segoe UI")
	Dash.Add("Edit", "x498 y98 w30 h22 Number Limit1 Hidden Background111317 vDeckFSet")
	Dash.SetFont("s9 w400 c9AA0A6", "Segoe UI")
	Dash.Add("Text", "x534 y101 w240 h18 Hidden vDeckFSetN", "(its Ctrl+1-9 puts its in-game deck on; 0: none)")
	Dash.SetFont("s9 w400 cDADADA", "Segoe UI")
	Dash.Add("Text", "x12 y131 w64 h18 Hidden vDeckFWhenT", "Used for")
	Dash.Add("Checkbox", "x78 y130 w104 h20 Hidden vDeckFWDefault", "anything else")
	Dash.Add("Checkbox", "x186 y130 w104 h20 Hidden vDeckFWCollect", "collect goals")
	Dash.Add("Checkbox", "x294 y130 w112 h20 Hidden vDeckFWBoss", "bosses (" HkText("boss") ")")
	Dash.Add("Checkbox", "x410 y130 w104 h20 Hidden vDeckFWDungeon", "dungeon runs")
	Dash.Add("Checkbox", "x518 y130 w104 h20 Hidden vDeckFWFarm", "farming (loop)")
	Dash.Add("Text", "x630 y131 w48 h18 Hidden vDeckFPriT", "Priority")
	Dash.SetFont("s9 w400 cF2F2F2", "Segoe UI")
	Dash.Add("Edit", "x680 y128 w40 h22 Number Limit3 Hidden Background111317 vDeckFPri")
	Dash.SetFont("s9 w400 cDADADA", "Segoe UI")
	Dash.Add("Checkbox", "x12 y160 w360 h20 Hidden vDeckFPin", "Use this deck now, whatever's ahead (pinned)")
	Dash.SetFont("s9 w400 c000000", "Segoe UI")
	;(your in-game decks read from the game's memory and made into decks here - Decks.ahk DeckLearnGame)
	Dash.Add("Button", "x380 y157 w94 h24 Hidden vDeckGameBtn", "From game").OnEvent("Click", DashGLabel.Bind(DeckGameClick, "Normal"))
	Dash.Add("Button", "x480 y157 w90 h24 Hidden vDeckFSave", "Save").OnEvent("Click", DashGLabel.Bind(DeckSaveClick, "Normal"))
	Dash.Add("Button", "x576 y157 w90 h24 Hidden vDeckFCopy", "Copy").OnEvent("Click", DashGLabel.Bind(DeckCopyClick, "Normal"))
	Dash.Add("Button", "x672 y157 w90 h24 Hidden vDeckFDel", "Delete").OnEvent("Click", DashGLabel.Bind(DeckDelClick, "Normal"))
	Dash.SetFont("s9 w400 cB9E2B9", "Consolas")
	Dash.Add("Text", "x12 y188 w760 h44 Hidden vDeckFDmg")
	Dash.SetFont("s9 w400 cDADADA", "Segoe UI")
	lv := Dash.Add("ListView", "x12 y236 w760 h470 Hidden vDeckFList AltSubmit -Multi NoSort Background111317 cDADADA", ["Setting", "This deck", "Everywhere else", "Key"])
	lv.OnNotify(-101, DashLvItem.Bind(DeckListEvent))
	lv.ModifyCol(1, 360), lv.ModifyCol(2, 170), lv.ModifyCol(3, 200), lv.ModifyCol(4, 0)
	Dash.Add("Text", "x12 y715 w128 h18 Hidden vDeckFValT", "Value for this deck:")
	Dash.SetFont("s9 w400 cF2F2F2", "Segoe UI")
	Dash.Add("Edit", "x142 y712 w70 h22 Hidden Background111317 vDeckFVal")
	Dash.SetFont("s9 w400 c000000", "Segoe UI")
	Dash.Add("Button", "x218 y711 w60 h24 Hidden vDeckFValSet", "Set").OnEvent("Click", DashGLabel.Bind(DeckValSet, "Normal"))
	Dash.Add("Button", "x284 y711 w150 h24 Hidden vDeckFValClear", "Not set by this deck").OnEvent("Click", DashGLabel.Bind(DeckValClear, "Normal"))
	Dash.SetFont("s9 w400 cB9E2B9", "Segoe UI")
	Dash.Add("Text", "x442 y715 w330 h36 Hidden vDeckFNote")
	;The Network tab: every bot on your home network (Network.ahk) - pick one: its log and its game; the buttons send it
	;a command (with the network PIN)
	tabs.UseTab(5)
	Dash.SetFont("s9 w600 c8AB4F8", "Segoe UI")
	Dash.Add("Text", "x12 y68 w400 h16", "BOTS ON YOUR NETWORK")
	Dash.SetFont("s9 w400 c9AA0A6", "Segoe UI")
	Dash.Add("Text", "x12 y88 w760 h32 vNetHelp", "Every PC on your home network running the bot with Settings > NETWORK > neton. Pick one to see its log and its game. The buttons need the network PIN, the same on both PCs (Settings: netpin); Play for me can only be switched off from here.")
	Dash.SetFont("s9 w400 c000000", "Segoe UI")
	Dash.Add("Button", "x12 y124 w80 h26 vNetOnBtn", "Bot on").OnEvent("Click", DashGLabel.Bind(DashNetOn, "Normal"))
	Dash.Add("Button", "x98 y124 w80 h26 vNetOffBtn", "Bot off").OnEvent("Click", DashGLabel.Bind(DashNetOff, "Normal"))
	Dash.Add("Button", "x184 y124 w120 h26 vNetPfmBtn", "Play for me off").OnEvent("Click", DashGLabel.Bind(DashNetPfm, "Normal"))
	Dash.Add("Button", "x310 y124 w80 h26 vNetRestartBtn", "Restart").OnEvent("Click", DashGLabel.Bind(DashNetRestart, "Normal"))
	Dash.Add("Button", "x396 y124 w80 h26 vNetRefreshBtn", "Refresh").OnEvent("Click", DashGLabel.Bind(DashNetRefresh, "Normal"))
	Dash.SetFont("s9 w400 cB9E2B9", "Consolas")
	Dash.Add("Text", "x12 y156 w760 h30 vNetStatus", "Network: off (Settings > NETWORK > neton)")
	Dash.SetFont("s9 w400 cDADADA", "Segoe UI")
	lv := Dash.Add("ListView", "x12 y190 w760 h150 vNetList AltSubmit -Multi Background111317 cDADADA", ["PC", "Version", "Wizard", "Zone", "Bot", "Play for me", "Doing", "Health", "Mana", "Deaths", "Seen", "Id"])
	lv.OnNotify(-101, DashLvItem.Bind(DashNetListEvent))
	lv.ModifyCol(1, 110), lv.ModifyCol(2, 58), lv.ModifyCol(3, 110), lv.ModifyCol(4, 130), lv.ModifyCol(5, 52), lv.ModifyCol(6, 72)
	lv.ModifyCol(7, 96), lv.ModifyCol(8, 74), lv.ModifyCol(9, 60), lv.ModifyCol(10, 54), lv.ModifyCol(11, 60), lv.ModifyCol(12, 0)
	Dash.SetFont("s8 w400 cDADADA", "Consolas")
	;(v1: a read-only Edit took the window's colour, not the controls' - measured with both interpreters)
	Dash.Add("Edit", "x12 y348 w380 h440 ReadOnly -Wrap +HScroll +VScroll Background1B1D22 vNetLog")
	Dash.Add("Picture", "x400 y348 w372 h210 vNetPic")
	Dash.SetFont("s9 w400 c9AA0A6", "Segoe UI")
	Dash.Add("Text", "x400 y564 w372 h60 vNetPicNote", "Pick a bot to see its log and its game.")
	;The Keys tab: every action's key - yours to change (Hotkeys.ahk)
	tabs.UseTab(6)
	Dash.SetFont("s9 w600 c8AB4F8", "Segoe UI")
	Dash.Add("Text", "x12 y68 w400 h16", "KEYS")
	Dash.SetFont("s9 w400 c9AA0A6", "Segoe UI")
	Dash.Add("Text", "x12 y88 w760 h32 vKeyHelp", "Pick an action and click Change (or double-click it), then press the new key - with Ctrl, Alt, Shift or Windows if you like. Keys the bot presses in the game (W A S D, X, Space, Ctrl+O, Ctrl+1-9, F13-F24) and plain letters can't be taken.")
	Dash.SetFont("s9 w400 c000000", "Segoe UI")
	Dash.Add("Button", "x12 y124 w90 h26 vKeyChangeBtn", "Change...").OnEvent("Click", DashGLabel.Bind(KeyChangeClick, "Normal"))
	Dash.Add("Button", "x108 y124 w90 h26 vKeyDefaultBtn", "Its default").OnEvent("Click", DashGLabel.Bind(KeyDefaultClick, "Normal"))
	Dash.Add("Button", "x204 y124 w90 h26 vKeyNoneBtn", "No key").OnEvent("Click", DashGLabel.Bind(KeyNoneClick, "Normal"))
	Dash.Add("Button", "x300 y124 w110 h26 vKeyAllBtn", "All to defaults").OnEvent("Click", DashGLabel.Bind(KeyAllClick, "Normal"))
	Dash.SetFont("s9 w400 cB9E2B9", "Consolas")
	Dash.Add("Text", "x12 y156 w760 h30 vKeyStatus")
	Dash.SetFont("s9 w400 cDADADA", "Segoe UI")
	lv := Dash.Add("ListView", "x12 y190 w760 h598 vKeyList AltSubmit -Multi Background111317 cDADADA", ["Action", "Key", "Default", "Works", "Id"])
	lv.OnEvent("DoubleClick", DashGLabel.Bind(KeyListEvent, "DoubleClick"))
	lv.ModifyCol(1, 330), lv.ModifyCol(2, 130), lv.ModifyCol(3, 150), lv.ModifyCol(4, 140), lv.ModifyCol(5, 0)
	tabs.UseTab()
	;The Play for me button, on every tab - the tab row's right end (DashGuiSize keeps it there), not the heading's
	;room: every check for you off till you click it again; off at every start. A red bar (green while on: DashPlayShow) -
	;a Progress control takes a colour - with the clickable words over it
	Dash.Add("Progress", "x668 y37 w108 h24 BackgroundB71C1C Disabled vDashPlayBg")
	Dash.SetFont("s9 w700 cFFFFFF", "Segoe UI")
	play := Dash.Add("Text", "x668 y37 w108 h24 +Center +0x200 BackgroundTrans vDashPlayBtn", "Play for me")
	play.OnEvent("Click", DashGLabel.Bind(DashPlayToggle, "Normal"))
	;(v1: a Text's gLabel ran for a double-click too - A_GuiEvent DoubleClick)
	play.OnEvent("DoubleClick", DashGLabel.Bind(DashPlayToggle, "DoubleClick"))
	Dash.SetFont("s9 w400 c000000", "Segoe UI")
	;(the menu bar: after the last control, before the window's minimum size - DashApplyView - and its first show)
	DashMenuMake()
	;(the log so far: the lines written before the window was made)
	earlier := V1FileRead(A_ScriptDir "\debug.log")
	if (earlier != "")
		DashAppend(earlier)
	shown := IniRead(A_ScriptDir "\dashboard.ini", "window", "shown", 1)
	DashApplyView()
	;(the Dungeons tab's list and status; the Spells tab's)
	DgListFill()
	DgShow()
	SpInit()
	;(the Keys tab's list)
	if (V1IsFunc("KeyListFill"))
		KeyListFill.Call()
	if (shown)
		DashShow()
	SetTimer(DashRefreshTick, 1000)
	OnExit(DashOnExit)
	;(the map: back if it was open when the bot stopped)
	mapShown := IniRead(A_ScriptDir "\dashboard.ini", "map", "shown", 0)
	if (mapShown = 1)
		DashMapShow()
	}

;(v2 port) v1's gLabel: the label ran as a thread of its own (its own ErrorLevel) with A_GuiEvent ("Normal",
;"DoubleClick", "I"), A_GuiControl (the control's variable, else its text) and A_EventInfo (a ListView's row - for a
;double-click its focused row), and a ListView item's change ("I": DashLvItem) had ErrorLevel the letters of what
;changed (el). fn: the label's function - this file's, Dungeons', Spells', Decks' or Hotkeys' - called the converter's
;way, fn(A_GuiEvent, A_GuiControl, A_EventInfo), or fn() when it takes no parameters
DashGLabel(fn, guiEvent, ctl, info := "", el := "", *)
	{
	global ErrorLevel
	local v1Keep := V1Thread() ; (v1: each thread had its own ErrorLevel)
	if (guiEvent = "I")
		ErrorLevel := el
	else if (guiEvent = "DoubleClick" && ctl is Gui.ListView)
		info := ctl.GetNext(0, "F")
	if (fn.IsVariadic || fn.MaxParams >= 3)
		fn(guiEvent, V1GuiName(ctl), info)
	else
		fn()
	}

;(v2 port) v1's "I" gLabel event of an AltSubmit ListView: each LVN_ITEMCHANGED (lParam: its NMLISTVIEW) whose state
;changed - ErrorLevel S / s (selected / deselected), F / f (focused / not), C / c (checked / not), A_EventInfo the row -
;the script's own Modify too (v2's ItemSelect isn't raised for those; v1's "I" was). Launched as v1 launched it: a
;thread of its own once the current one can be interrupted (after its Critical), not inside the Modify. Only when the
;selection changed: every "I" handler of this window (DgListEvent, SpListEvent, DeckListEvent, DashNetListEvent) did
;nothing in v1 without S or s in ErrorLevel - the other files' v2 handlers no longer look
DashLvItem(fn, ctl, lParam)
	{
	item := NumGet(lParam, 3 * A_PtrSize, "Int"), newState := NumGet(lParam, 3 * A_PtrSize + 8, "UInt")
	oldState := NumGet(lParam, 3 * A_PtrSize + 12, "UInt"), changed := NumGet(lParam, 3 * A_PtrSize + 16, "UInt")
	if (!(changed & 0x8))
		return
	diff := newState ^ oldState
	el := (diff & 0x2 ? (newState & 0x2 ? "S" : "s") : "") (diff & 0x1 ? (newState & 0x1 ? "F" : "f") : "")
		. (diff & 0xF000 ? ((newState & 0xF000) = 0x2000 ? "C" : "c") : "")
	if (diff & 0x2)
		SetTimer(DashGLabel.Bind(fn, "I", ctl, item + 1, el), -1)
	}

;The "Learn every card" button's label
DashLearnShow(learnOn)
	{
	if (DashHwnd)
		Dash["DashLearnBtn"].Text := learnOn ? "Learning... (stop)" : "Learn every card"
	}

;The bot on/off button's label, and the Bot menu's tick
DashBotShow(isOn)
	{
	if (DashHwnd)
		Dash["DashBotBtn"].Text := "Bot: " (isOn ? "on" : "off") " (" HkText("bot") ")"
	DashMenuTicks()
	}

;The Dungeons tab's help line - with the keys set now (Hotkeys.ahk)
DashDgHelpText()
	{
	return "Record a run once: stand outside the dungeon by its sigil, click Record a run and play it - X at the sigil, to the boss (fighting on the way), back out to where you started - then press " HkText("record") ". Pick it and click Run: the bot walks the same way, presses X where you did, fights every battle (the bot on, " HkText("bot") ") and starts over. " HkText("walk") " pauses it."
	}

;A key changed on the Keys tab (KeySet, KeyAllClick - Hotkeys.ahk): the dashboard's texts that name a key made again
;with the keys set now (the others - the status lines - are made afresh every second), the menu bar's items too
;(DashMenuKeys)
DashKeysChanged()
	{
	if (!DashHwnd)
		return
	Dash["DashBotBtn"].Text := "Bot: " (BotOn ? "on" : "off") " (" HkText("bot") ")"
	DashMenuKeys()
	Dash["DgHelp"].Text := DashDgHelpText()
	;(while a run's being recorded: the key it was begun with - the one that stops it)
	Dash["DgRecStopBtn"].Text := "Stop recording (" (DgRecording ? HkName(DgRecKey) : HkText("record")) ")"
	Dash["DeckFWBoss"].Text := "bosses (" HkText("boss") ")"
	}

;"Bring Wizard101 to the front" switched (Autofarmer.ahk GameFrontShow): the Bot menu's tick (DashMenuTicks reads
;GameFrontOn itself - frontOn is what it says)
DashFrontShow(frontOn)
	{
	DashMenuTicks()
	}

;The "Play for me" button: red "Play for me" off, green "PLAYING FOR ME" on (you asked, 2026-10-26)
DashPlayShow(on)
	{
	if (!DashHwnd)
		return
	playCol := on ? "2E7D32" : "B71C1C"
	Dash["DashPlayBg"].Opt("+Background" playCol)
	Dash["DashPlayBtn"].Text := on ? "PLAYING FOR ME" : "Play for me"
	;(the words drawn again over the bar's new colour)
	Dash["DashPlayBtn"].Redraw()
	;(the Bot menu's tick)
	DashMenuTicks()
	}

;"Wait while I play" switched (Autofarmer.ahk HandsOffShow): the Bot menu's "Wait for me" tick (DashMenuTicks reads
;HandsOffOn itself - waitOn is what it says)
DashHandsShow(waitOn)
	{
	DashMenuTicks()
	}

;Simple (true) or advanced: which view of a window (what: "dashboard", "settings") - dashboard.ini [view]. Not set yet:
;advanced where the bot ran before (it had a dashboard.ini - nothing that was there goes missing), simple on a new one
;(v2 port: IniRead's "" default is v1's %A_Space% - a blank; v2 would give the space itself)
ViewSimple(what)
	{
	ini := A_ScriptDir "\dashboard.ini"
	v := IniRead(ini, "view", what, "")
	if (v = "")
		{
		;(both views decided at once - the first one asked mustn't make the file the other takes for "ran before")
		v := FileExist(ini) ? 0 : 1
		for each, w in ["dashboard", "settings"]
			{
			had := IniRead(ini, "view", w, "")
			if (had = "")
				V1Do(IniWrite, v, ini, "view", w)
			}
		v := IniRead(ini, "view", what, v)
		}
	return v = 1
	}

;The view shown: simple hides the log (the window that much shorter - the Bot tab ends under WHAT IT SEES), advanced
;shows it; the View menu's tick (and Pause log, Clear log greyed while simple: DashMenuTicks)
DashApplyView()
	{
	if (!DashHwnd)
		return
	act := DashSimple ? "Hide" : "Show"
	for each, c in ["DashLogHead", "DashConsole"]
		Dash[c].Visible := act = "Show"
	Dash.Opt("+MinSize740x" (DashSimple ? 294 : 640))
	DashMenuTicks()
	}

;Shows the window where it was (else on a monitor the game isn't on), without taking the focus - each view its own
;place and size ([window]: advanced, [simple])
;(v2 port: dashboard.ini's numbers as v1 did math with them - V1Add, V1Max...: a blank or text one gave a blank)
DashShow()
	{
	global DashShown ; (v1 globals it sets)
	;(minimized - its minimize button put it in the tray (Settings: traybot - DashToTray), or Windows+2 hid it so: its
	;place wasn't saved (DashSaveWin can't), Windows kept it. Shown with no x/y/w/h it comes back there, nothing
	;moves it)
	if (DashHwnd && DllCall("IsIconic", "Ptr", DashHwnd))
		{
		Dash.Show("NoActivate")
		DashShown := 1
		DashRefresh()
		return
		}
	section := DashSimple ? "simple" : "window"
	x := IniRead(A_ScriptDir "\dashboard.ini", section, "x", "")
	y := IniRead(A_ScriptDir "\dashboard.ini", section, "y", "")
	w := IniRead(A_ScriptDir "\dashboard.ini", section, "w", 784)
	h := IniRead(A_ScriptDir "\dashboard.ini", section, "h", "")
	layout := IniRead(A_ScriptDir "\dashboard.ini", "window", "layout", 1)
	;(the Hand section came in above the log, then the tabs: a window saved before that is that much taller now.
	;v1.10.0, layout 4: the menu bar over it - about 20 px on the screen - and no bottom row: 20 less, as tall on the
	;screen as it was. The simple view's place has no layout: a saved one stays as it is)
	if (DashSimple)
		h := (h = "") ? 294 : V1Max(294, h)
	else
		h := (h = "") ? 784 : (V1Lt(layout, 2) ? V1Add(h, 160) : V1Lt(layout, 3) ? V1Add(h, 8) : V1Lt(layout, 4) ? V1Sub(h, 20) : h)
	;(w and h are at 100% display scaling; Windows' scaling makes the window that much bigger. Its frame - the title bar,
	;the borders and the menu bar - is DashFrameH at 100%)
	dpi := A_ScreenDPI / 96
	frameH := DashFrameH()
	if (x = "" || y = "" || !DashOnScreen(V1Add(x, 40), V1Add(y, 20)))
		{
		;(the first monitor that doesn't hold the middle of the game window; else the bottom right)
		spare := DashSpareMonitor(&mLeft, &mTop, &mRight, &mBottom)
		;(no bigger than that monitor)
		w := V1Min(w, Floor((mRight - mLeft - 40) / dpi) - 16), h := V1Min(h, Floor((mBottom - mTop - 40) / dpi) - frameH)
		x := spare ? mLeft + 20 : mRight - V1Round(V1Mul(V1Add(w, 16), dpi)) - 20
		y := spare ? mTop + 20 : mBottom - V1Round(V1Mul(V1Add(h, frameH), dpi)) - 20
		}
	DashFitHeight(x, y, &h, frameH)
	Dash.Show("x" x " y" y " w" w " h" h " NoActivate")
	DashShown := 1
	DashRefresh()
	}

;The work area of the first monitor that doesn't hold the middle of the game window: true; else the main
;monitor's and false
;(v2 port: the game window not found yet - GameLeft... blank - v1's sums were blank, and a blank compared as text: the
;first monitor counts as spare, as in v1)
DashSpareMonitor(&mLeft, &mTop, &mRight, &mBottom)
	{
	gx := V1Add(GameLeft, V1FloorDiv(GameW, 2)), gy := V1Add(GameTop, V1FloorDiv(GameH, 2))
	count := MonitorGetCount()
	Loop count
		{
		MonitorGetWorkArea(A_Index, &mLeft, &mTop, &mRight, &mBottom)
		if (!(V1Ge(gx, mLeft) && V1Lt(gx, mRight) && V1Ge(gy, mTop) && V1Lt(gy, mBottom)))
			return true
		}
	MonitorGetWorkArea(, &mLeft, &mTop, &mRight, &mBottom)
	return false
	}

;The work area of the monitor that holds x, y (else the main monitor's)
DashMonitorAt(x, y, &mLeft, &mTop, &mRight, &mBottom)
	{
	count := MonitorGetCount()
	Loop count
		{
		MonitorGetWorkArea(A_Index, &mLeft, &mTop, &mRight, &mBottom)
		if (x >= mLeft && x < mRight && y >= mTop && y < mBottom)
			return
		}
	MonitorGetWorkArea(, &mLeft, &mTop, &mRight, &mBottom)
	}

;h (a window's inside, at 100% display scaling) cut so a window at x, y fits on the monitor it's on - frameH: its frame
;at 100% (the title bar and borders: 40 - the map's; the dashboard's has its menu bar too: DashFrameH)
DashFitHeight(x, y, &h, frameH := 40)
	{
	dpi := A_ScreenDPI / 96
	count := MonitorGetCount()
	Loop count
		{
		MonitorGetWorkArea(A_Index, &mLeft, &mTop, &mRight, &mBottom)
		if (x + 40 >= mLeft && x + 40 < mRight && y + 20 >= mTop && y + 20 < mBottom)
			h := V1Min(h, Floor((mBottom - y - 20) / dpi) - frameH)
		}
	}

;The dashboard's frame at 100% display scaling: the title bar and borders (40), and its menu bar - Windows' height
;for one (SM_CYMENU, at the scaling in use) - once it's made
DashFrameH()
	{
	return 40 + (IsObject(DashMenus) ? Round(DllCall("GetSystemMetrics", "Int", 15, "Int") * 96 / A_ScreenDPI) : 0)
	}

;(v2 port: x, y blank when dashboard.ini's place wasn't a number - v1 compared a blank as text: not on a screen)
DashOnScreen(x, y)
	{
	count := MonitorGetCount()
	Loop count
		{
		MonitorGet(A_Index, &mLeft, &mTop, &mRight, &mBottom)
		if (V1Ge(x, mLeft) && V1Lt(x, mRight) && V1Ge(y, mTop) && V1Lt(y, mBottom))
			return true
		}
	return false
	}

;Windows+2 / tray menu
DashToggle()
	{
	global DashShown ; (v1 globals it sets)
	if (!DashHwnd)
		return
	if (DashShown)
		{
		DashSavePlace()
		Dash.Hide()
		DashShown := 0
		}
	else
		DashShow()
	V1Do(IniWrite, DashShown, A_ScriptDir "\dashboard.ini", "window", "shown")
	}

;Settings: traybot ("Put the bot's window in the tray") - its X or minimize button (how, for the log) puts it in the
;tray and the bot plays on: its place kept (minimized: Windows keeps it - DashShow), hidden. The tray icon's double-click
;(DashFromTray) or Windows+2 brings it back, the tray menu's Exit stops the bot - a tray tip says so the first time
DashToTray(how)
	{
	static said := false
	global DashShown ; (v1 globals it sets)
	if (!DashHwnd)
		return
	DashSavePlace()
	Dash.Hide()
	DashShown := 0
	DebugLog("Dashboard in the tray (" how " - Settings: traybot) - the bot plays on: the tray icon brings it back, the tray menu's " HkMenu("quit") " stops the bot")
	if (!said)
		said := true, TrayTip("The bot plays on - its window is in the tray. Double-click the tray icon to bring it back - " HkMenu("quit") " in the tray menu stops the bot.", "Wizard101 bot", 1)
	}

;The tray menu's "Show the bot's window" - the tray icon's double-click while traybot is on (Settings): the window
;shown where it was - never hidden, as DashToggle hides it when it's up - and brought to the front (you asked)
DashFromTray()
	{
	if (!DashHwnd)
		return
	if (!DashShown || V1Try(WinGetMinMax, "ahk_id " DashHwnd) = -1)
		DashShow()
	V1Do(IniWrite, 1, A_ScriptDir "\dashboard.ini", "window", "shown")
	V1Try(WinActivate, "ahk_id " DashHwnd)
	}

DashSavePlace()
	{
	if (!DashShown || !DashHwnd)
		return
	if (DashSimple)
		DashSaveWin(DashHwnd, "simple")
	else if (DashSaveWin(DashHwnd, "window"))
		V1Do(IniWrite, 4, A_ScriptDir "\dashboard.ini", "window", "layout")
	}

;Saves where a window is in dashboard.ini [section]: x, y on the screen, and its inside's width and height at
;100% display scaling (as Gui Show takes them). Not while it's minimized or maximized (false)
DashSaveWin(hwnd, section)
	{
	;(v1: WinGet MinMax / WinGetPos of a window that isn't there - blank; v2 throws)
	mm := V1Try(WinGetMinMax, "ahk_id " hwnd)
	if (mm != 0)
		return false
	rc := Buffer(16, 0)
	DllCall("GetClientRect", "Ptr", hwnd, "Ptr", rc.Ptr)
	;(v2's WinGetPos unsets its output variables before it throws - the blanks are set in the catch)
	try WinGetPos(&x, &y, , , "ahk_id " hwnd)
	catch
		x := "", y := ""
	if (x = "")
		return false
	V1Do(IniWrite, x, A_ScriptDir "\dashboard.ini", section, "x")
	V1Do(IniWrite, y, A_ScriptDir "\dashboard.ini", section, "y")
	V1Do(IniWrite, Round(NumGet(rc, 8, "Int") * 96 / A_ScreenDPI), A_ScriptDir "\dashboard.ini", section, "w")
	V1Do(IniWrite, Round(NumGet(rc, 12, "Int") * 96 / A_ScreenDPI), A_ScriptDir "\dashboard.ini", section, "h")
	return true
	}

;---- The menu bar ----
;
;The standard File | Bot | View | Settings | Help menus at the window's top left (you asked, v1.10.0: most of the
;buttons moved there - the bot's on / off button stays at the heading's right end, Play for me on the tab row, each
;tab's own buttons on it). Made once (DashMenuMake); kept as things are by DashMenuTicks - the ticks, the greyed
;items, the keys the items name and, while a newer version is out, "Update to vX" at the bar's right end. Alt+F, B,
;V, T and H open them (Settings is Alt+T: Alt+S is Statistic mode's key while the bot's on). A pick is yours, as a
;tray menu pick is: what it opens may take the focus. Each pick a thread of its own, logged (DashMenuRun)

;Makes the menus and puts the bar on the window (DashInit: after its last control, before it's first shown). An item
;is found again by its place in its menu ("2&" - DashMenuName, DashMenuSet): the names that say a key change. Couldn't
;be made: said in the log, the window works on without it (the tray menu has most of it)
DashMenuMake()
	{
	global DashMenus
	try
		{
		dmFile := Menu(), dmBot := Menu(), dmView := Menu(), dmSet := Menu(), dmHelp := Menu()
		;(File: 1 Save settings as..., 2 Load settings from..., 4 Open bot folder, 5 Open debug.log, 7 Exit - the tray
		;menu's Exit: the bot stops)
		dmFile.Add("Save settings as...", DashMenuRun.Bind("File", DashMenuSaveAs))
		dmFile.Add("Load settings from...", DashMenuRun.Bind("File", DashMenuLoadFrom))
		dmFile.Add()
		dmFile.Add("Open bot folder", DashMenuRun.Bind("File", DashFolder))
		dmFile.Add("Open debug.log", DashMenuRun.Bind("File", DashOpenLog))
		dmFile.Add()
		dmFile.Add("Exit" DashMenuKey("quit"), DashMenuRun.Bind("File", ExitApp))
		;(Bot: 1 Bot on/off, 2 Walking on/off, 4 Play for me, 5 Wait for me, 6 Bring Wizard101 to the front, 8 Show
		;Wizard101 - greyed unless Wizard101 is in the tray)
		dmBot.Add("Bot on/off" DashMenuKey("bot"), DashMenuRun.Bind("Bot", DashBotToggle))
		dmBot.Add("Walking on/off" DashMenuKey("walk"), DashMenuRun.Bind("Bot", DashWalkToggle))
		dmBot.Add()
		dmBot.Add("Play for me", DashMenuRun.Bind("Bot", DashPlayToggle))
		dmBot.Add("Wait for me", DashMenuRun.Bind("Bot", DashHandsToggle))
		dmBot.Add("Bring Wizard101 to the front", DashMenuRun.Bind("Bot", DashFrontToggle))
		dmBot.Add()
		dmBot.Add("Show Wizard101", DashMenuRun.Bind("Bot", DashMenuGameShow))
		;(View: 1 Map, 2 Simple view, 4 Log colours..., 5 Pause log, 6 Clear log - those two greyed in the simple view,
		;which shows no log - 8 Overlay)
		dmView.Add("Map", DashMenuRun.Bind("View", DashMapButton))
		dmView.Add("Simple view", DashMenuRun.Bind("View", DashViewToggle))
		dmView.Add()
		dmView.Add("Log colours...", DashMenuRun.Bind("View", DashLogColorsBtn))
		dmView.Add("Pause log", DashMenuRun.Bind("View", DashPauseLog))
		dmView.Add("Clear log", DashMenuRun.Bind("View", DashClearLog))
		dmView.Add()
		dmView.Add("Overlay" DashMenuKey("overlay"), DashMenuRun.Bind("View", DashMenuOverlay))
		;(Settings: 1 Settings..., 3 Put the bot's window in the tray, 4 Put Wizard101 in the tray, 6 Discord alerts...,
		;7 Party..., 8 Wizard101 login...)
		dmSet.Add("Settings...", DashMenuRun.Bind("Settings", DashSettingsButton))
		dmSet.Add()
		dmSet.Add("Put the bot's window in the tray", DashMenuRun.Bind("Settings", DashMenuTraySet.Bind("traybot")))
		dmSet.Add("Put Wizard101 in the tray", DashMenuRun.Bind("Settings", DashMenuTraySet.Bind("traygame")))
		dmSet.Add()
		dmSet.Add("Discord alerts...", DashMenuRun.Bind("Settings", DashMenuAlerts))
		dmSet.Add("Party...", DashMenuRun.Bind("Settings", DashMenuParty))
		dmSet.Add("Wizard101 login...", DashMenuRun.Bind("Settings", DashMenuLogin))
		;(Help: 1 Check for updates, 2 Report a bug..., 3 Read me, 5 About)
		dmHelp.Add("Check for updates", DashMenuRun.Bind("Help", DashUpdButton))
		dmHelp.Add("Report a bug...", DashMenuRun.Bind("Help", DashBugButton))
		dmHelp.Add("Read me", DashMenuRun.Bind("Help", DashMenuReadMe))
		dmHelp.Add()
		dmHelp.Add("About", DashMenuRun.Bind("Help", DashMenuAbout))
		;(the bar: 1-5 the menus, 6 "Update to vX" while a newer version is out - DashMenuTicks)
		dmBar := MenuBar()
		dmBar.Add("&File", dmFile)
		dmBar.Add("&Bot", dmBot)
		dmBar.Add("&View", dmView)
		dmBar.Add("Se&ttings", dmSet)
		dmBar.Add("&Help", dmHelp)
		Dash.MenuBar := dmBar
		DashMenus := Map("file", dmFile, "bot", dmBot, "view", dmView, "set", dmSet, "help", dmHelp, "bar", dmBar)
		}
	catch as dmErr
		{
		DashMenus := ""
		DebugLog("Dashboard: the menu bar couldn't be made - " dmErr.Message " (" dmErr.What ", line " dmErr.Line ")")
		}
	DashMenuTicks()
	}

;The menu bar as things are now: each item's tick, the greyed ones, Help's "Checking..." and the bar's "Update to vX"
;while a newer version is out (the last look-up: UpdState). Called by each hook that shows a state (DashBotShow,
;DashPlayShow, DashFrontShow, DashHandsShow, DashApplyView, DashMapShow / DashMapHide, DashPauseLog), by Settings.ahk
;CfgApply, and every second by DashRefresh - walking, the tray settings, Wizard101 in the tray and the overlay change in
;many places. The keys the items name: DashMenuKeys. Before the bar is made: nothing. An error said in the log once,
;never a box (it would take the focus)
DashMenuTicks()
	{
	static updItem := "", updOn := 1, errSaid := 0
	try
		{
		if (!IsObject(DashMenus))
			return
		DashMenuSet("bot", 1, "tick", BotOn)
		DashMenuSet("bot", 2, "tick", Walking)
		DashMenuSet("bot", 4, "tick", PlayForMe)
		DashMenuSet("bot", 5, "tick", V1IsFunc("HandsOffOn") && HandsOffOn.Call())
		;(what it does now: Play for me brings the game up whatever gamefront is - GameFrontOn)
		DashMenuSet("bot", 6, "tick", V1IsFunc("GameFrontOn") && GameFrontOn.Call())
		DashMenuSet("bot", 8, "on", GameInTray)
		DashMenuSet("view", 1, "tick", DashMapShown)
		DashMenuSet("view", 2, "tick", DashSimple)
		;(the simple view shows no log: Pause log and Clear log greyed - not Log colours..., the overlay's log takes them)
		DashMenuSet("view", 5, "on", !DashSimple)
		DashMenuSet("view", 6, "on", !DashSimple)
		DashMenuSet("view", 5, "tick", DashPaused)
		DashMenuSet("view", 8, "tick", V1IsFunc("OvStat") && OvStat.Call("overlay", 0))
		DashMenuSet("set", 3, "tick", V1IsFunc("TrayBotOn") && TrayBotOn.Call())
		DashMenuSet("set", 4, "tick", V1IsFunc("TrayGameOn") && TrayGameOn.Call())
		;(Help > Check for updates: "Checking..." and greyed for 10 s after a click - DashUpdButton, DashRefresh)
		DashMenuName("help", 1, DashUpdBusy ? "Checking..." : "Check for updates")
		DashMenuSet("help", 1, "on", !DashUpdBusy)
		;(a newer version out: "Update to vX" at the bar's right end - what the Updates button said and did - gone once
		;there's none; greyed while it's checking. The bar drawn again after a change of its own items)
		mtUpd := V1IsFunc("UpdState") ? UpdState.Call() : ""
		mtWant := (IsObject(mtUpd) && mtUpd.newer) ? "Update to " mtUpd.latest : ""
		mtBar := DashMenus["bar"]
		if (mtWant != updItem)
			{
			if (updItem != "")
				mtBar.Delete("6&")
			if (mtWant != "")
				mtBar.Add(mtWant, DashMenuRun.Bind("", DashUpdButton), "Right"), updOn := 1
			updItem := mtWant
			DllCall("DrawMenuBar", "Ptr", DashHwnd)
			}
		if (updItem != "" && updOn != (DashUpdBusy ? 0 : 1))
			{
			updOn := DashUpdBusy ? 0 : 1
			if (updOn)
				mtBar.Enable("6&")
			else
				mtBar.Disable("6&")
			DllCall("DrawMenuBar", "Ptr", DashHwnd)
			}
		}
	catch as mtErr
		{
		if (!errSaid)
			errSaid := 1, DebugLog("Dashboard: the menu bar - " mtErr.Message " (" mtErr.What ", line " mtErr.Line ") - said once a run")
		}
	}

;The items that say a key ("Bot on/off`t(F6)"), named with the keys set now - a key changed on the Keys tab
;(DashKeysChanged; DashMenuMake made them with the keys then). By place: their names change. Not every second, as the
;ticks are - each key is read from dashboard.ini (Hotkeys.ahk HkKeyOf)
DashMenuKeys()
	{
	try
		{
		if (!IsObject(DashMenus))
			return
		DashMenuName("file", 7, "Exit" DashMenuKey("quit"))
		DashMenuName("bot", 1, "Bot on/off" DashMenuKey("bot"))
		DashMenuName("bot", 2, "Walking on/off" DashMenuKey("walk"))
		DashMenuName("view", 8, "Overlay" DashMenuKey("overlay"))
		}
	catch as mkErr
		DebugLog("Dashboard: the menu bar's keys - " mkErr.Message " (" mkErr.What ", line " mkErr.Line ")")
	}

;Item pos of menu which (DashMenus' key: "file", "bot"...) named name - renamed only when that's new (its tick and
;greying stay)
DashMenuName(which, pos, name)
	{
	static named := Map()
	mnKey := which "|" pos
	if (named.Has(mnKey) && named[mnKey] == name)
		return
	DashMenus[which].Rename(pos "&", name)
	named[mnKey] := name
	}

;Item pos of menu which ticked (what "tick") or there to pick (what "on") - want true or false; set only when it
;changed
DashMenuSet(which, pos, what, want)
	{
	static was := Map()
	msKey := which "|" pos "|" what
	want := want ? 1 : 0
	if (was.Has(msKey) && was[msKey] = want)
		return
	msMenu := DashMenus[which], msItem := pos "&"
	if (what = "tick")
		{
		if (want)
			msMenu.Check(msItem)
		else
			msMenu.Uncheck(msItem)
		}
	else if (want)
		msMenu.Enable(msItem)
	else
		msMenu.Disable(msItem)
	was[msKey] := want
	}

;"`t(F6)": a tab and action id's key now, in brackets, for a menu item's right end; "" while the action has no key.
;Display only - the keys are Hotkeys.ahk's. In brackets as the tray menu has them: a bare key name after the tab
;("`tF6") AutoHotkey makes a shortcut of while the window is active (its menu bar accelerators), so F6 or F8 in the
;dashboard would act even with the bot off - "(F6)" is no key name, nothing is made of it
DashMenuKey(id)
	{
	mkKey := HkText(id)
	return mkKey = "(none)" ? "" : "`t(" mkKey ")"
	}

;A menu bar pick - top: its menu, for the log ("" the bar's own Update item); fn: what it does, called with nothing (a
;Dash* button handler would take the menu's ItemName, ItemPos and Menu for its A_GuiEvent, A_GuiControl and Info);
;item: the item picked, as Windows passes it. A thread of its own, as a tray pick is - logged as one: "Menu: Bot > Play
;for me picked" (the key after the tab left out)
DashMenuRun(top, fn, item := "", *)
	{
	local v1Keep := V1Thread() ; (v1: each thread had its own ErrorLevel)
	DebugLog("Menu: " (top = "" ? "" : top " > ") RegExReplace(item, "`t.*") " picked")
	fn()
	}

;File > Save settings as... / Load settings from...: the settings to a file of your own, or from one (SettingsFile.ahk
;CfgSaveAs, CfgLoadFrom - their dialogs their own)
DashMenuSaveAs()
	{
	if (V1IsFunc("CfgSaveAs"))
		CfgSaveAs.Call()
	}

DashMenuLoadFrom()
	{
	if (V1IsFunc("CfgLoadFrom"))
		CfgLoadFrom.Call()
	DashMenuTicks()
	}

;Bot > Show Wizard101 (there to pick only while Wizard101 is in the tray - Settings: traygame): shown and brought to the
;front, as the tray menu's Show Wizard101 does (Autofarmer.ahk GameTrayShow - you asked, so it may take the focus)
DashMenuGameShow()
	{
	if (V1IsFunc("GameTrayShow"))
		GameTrayShow.Call(true, "Show Wizard101 (the dashboard's Bot menu)")
	DashMenuTicks()
	}

;View > Overlay: the overlay over the game on / off - Settings: overlay (Overlay.ahk OverlayToggle, as the tray menu's
;item and its key)
DashMenuOverlay()
	{
	if (V1IsFunc("OverlayToggle"))
		OverlayToggle.Call()
	DashMenuTicks()
	}

;Settings > Put the bot's window in the tray / Put Wizard101 in the tray (key: traybot, traygame): switched and saved as
;the Settings window's Save does it - Critical as it is, then Settings.ahk CfgApply (PlayerStats.txt, the log's line,
;the tray menu and these ticks). Not saved: said in a tray tip
DashMenuTraySet(key)
	{
	if (!V1IsFunc("CfgApply"))
		return
	Critical()
	tsWas := (key = "traybot") ? (V1IsFunc("TrayBotOn") && TrayBotOn.Call()) : (V1IsFunc("TrayGameOn") && TrayGameOn.Call())
	if (!CfgApply.Call(Map(key, tsWas ? 0 : 1), "Menu"))
		TrayTip("Couldn't save that setting - PlayerStats.txt couldn't be written.", "Wizard101 bot", 2)
	DashMenuTicks()
	}

;Settings > Discord alerts... / Wizard101 login...: what the tray menu's items open (Alerts.ahk AlertSetup, Reconnect.ahk
;ReconnectSetLogin) - their boxes the dashboard's, in front of it (the tray's are kept in front of the game:
;Autofarmer.ahk DialogsInFront)
DashMenuAlerts()
	{
	Dash.Opt("+OwnDialogs")
	if (V1IsFunc("AlertSetup"))
		AlertSetup.Call()
	}

DashMenuLogin()
	{
	Dash.Opt("+OwnDialogs")
	if (V1IsFunc("ReconnectSetLogin"))
		ReconnectSetLogin.Call()
	}

;Settings > Party...: the party window, as the tray menu's item opens it (Party.ahk PartySetup - an error opening it
;logged and said in a tray tip, not a box: PartyWinFailed)
DashMenuParty()
	{
	if (!V1IsFunc("PartySetup"))
		return
	try PartySetup.Call()
	catch Any as pmErr
		{
		if (V1IsFunc("PartyWinFailed"))
			PartyWinFailed.Call(pmErr)
		}
	}

;Help > Read me: README.txt (in this folder, AutoFarmer) in Notepad - else a box saying why not
DashMenuReadMe()
	{
	rmFile := A_ScriptDir "\README.txt"
	rmWhy := !FileExist(rmFile) ? "README.txt isn't in the bot's AutoFarmer folder." : V1Run("notepad.exe `"" rmFile "`"") ? "Notepad couldn't be started for README.txt." : ""
	if (rmWhy = "")
		return
	Dash.Opt("+OwnDialogs")
	MsgBox(rmWhy, "Wizard101 bot", 48)
	}

;Help > About: the bot's name and version, and the name of the folder it's in (the name only - never a whole path)
DashMenuAbout()
	{
	SplitPath(A_ScriptDir, , &abDir)
	SplitPath(abDir, &abName)
	Dash.Opt("+OwnDialogs")
	MsgBox("Wiz-Maxxing " (BotVersion() = "" ? "(no version.txt)" : BotVersion()) "`n`nIts folder: " abName, "About Wiz-Maxxing", 64)
	}

;---- The Network tab (Network.ahk) ----

;The Network tab is the one showing (and the window's up)
DashNetShown()
	{
	if (!DashHwnd || !DashShown)
		return false
	;(v1: GuiControlGet of a Tab - its tab's name)
	netTab := Dash["DashTabs"].Text
	return netTab = "Network"
	}

;The Network tab's list and status line afresh (NetTick, every 2 s): this PC first, then every bot heard - the one
;picked kept picked
DashNetFill()
	{
	if (!DashHwnd)
		return
	n := IsObject(NetPeers) ? NetPeers.Length : 0
	DashSet("NetStatus", "Network: " NetState (NetWhy != "" ? " - " NetWhy : "") (NetState = "on" ? "`n" n " other bot" (n = 1 ? "" : "s") " heard on your home network" (n ? "" : " - is neton switched on there, and Python allowed through its firewall?") : ""))
	if (!DashNetShown())
		return
	wasCrit := A_IsCritical
	Critical()
	;(v1: Gui, Dash:ListView, NetList made it the LV_ functions' list, the one before put back after - v2: the control)
	lv := Dash["NetList"]
	lv.Opt("-Redraw")
	lv.Delete()
	lv.Add("", A_ComputerName " (this PC)", BotVersion(), OwnName(), WalkZone(), (BotStandby && !BotEverOn) ? "standby" : BotOn ? "on" : "off"
		, PlayForMe ? "ON" : "off", "-", RegExReplace(IsObject(DashSees) ? DashSees.hp : "", "\s*\(.*"), IsObject(DashSees) ? DashSees.mana : ""
		, IsObject(DashN) && DashN.deaths ? DashN.deaths : 0, "now", "")
	;(v1: for over a blank NetPeers - nothing; a peer's age as the network sent it: V1Gt)
	for i, p in IsObject(NetPeers) ? NetPeers : []
		{
		row := lv.Add("", p.pc, p.ver, p.wiz (p.school != "" ? " (" p.school ")" : ""), p.zone, p.bot, p.pfm = 1 ? "ON" : "off", p.doing
			, p.hp, p.mana, p.deaths (p.dall != "" ? " / " p.dall : ""), V1Gt(p.age, 15) ? NetAge(p.age) " ago (quiet)" : "now", p.id)
		if (p.id = NetSel)
			lv.Modify(row, "Select Focus")
		}
	lv.Opt("+Redraw")
	CfgUncritical(wasCrit, 0)
	}

;The picked bot's log and picture onto the tab (NetFetchPicked); pic "" - none, why says why
DashNetShow(log, pic, why)
	{
	global ErrorLevel ; (v1 globals it sets)
	if (!DashHwnd)
		return
	if (log != "")
		{
		Dash["NetLog"].Value := log
		;(the log's end in view)
		netLogHwnd := Dash["NetLog"].Hwnd
		;(v1: SendMessage's answer in ErrorLevel, FAIL when it couldn't be sent - v2 throws)
		try
			ErrorLevel := SendMessage(0x115, 7, 0, , "ahk_id " netLogHwnd)
		catch
			ErrorLevel := "FAIL"
		}
	if (pic != "")
		{
		;(v1: a picture that couldn't be loaded - ErrorLevel, nothing thrown, the control left blank and 0 x 0; v2 throws
		;and keeps the old picture: blanked as v1 did)
		try Dash["NetPic"].Value := "*w372 *h-1 " pic
		catch
			try Dash["NetPic"].Value := ""
		Dash["NetPic"].Visible := true
		Dash["NetPicNote"].Text := "Its game, " A_Hour ":" A_Min ":" A_Sec (why != "" ? " - " why : "")
		}
	else
		{
		;(no picture this time: the last one isn't left up under it)
		Dash["NetPic"].Visible := false
		Dash["NetPicNote"].Text := why != "" ? why : "No picture"
		}
	}

DashOnExit(reason := "", code := "", *)
	{
	local v1Keep := V1Thread() ; (v1: each thread had its own ErrorLevel)
	DashSavePlace()
	if (DashMapShown && DashMapHwnd)
		DashSaveWin(DashMapHwnd, "map")
	}

;---- What goes in ----

;Every DebugLog line (with its time): onto the log, and into the counts
DashLog(line)
	{
	global NetLastLine, DashHeld ; (v1 globals it sets)
	;(the last line written - the Network tab's "last" for the other bots, Network.ahk)
	NetLastLine := line
	if (!DashHwnd)
		return
	DashParse(line)
	if (DashPaused)
		DashHeld .= line "`r`n"
	else
		DashAppend(line "`r`n")
	}

;---- The log in colour: each line's kind (DashLogKind) in its colour (dashboard.ini [logcolors], View > Log colours...) ----

;The kinds, in the order the Colours window lists them: [key, label, default colour RRGGBB]
DashLogKinds()
	{
	static kinds := ""
	if (!IsObject(kinds))
		kinds := [["problem", "Problems (needs you, stuck, couldn't...)", "FF6B6B"], ["movement", "Movement (walking)", "7FB3FF"]
			, ["battle", "Battle (rounds, cards, enemies)", "F2A65A"], ["wait", "Waits and delays", "8A8F98"]
			, ["potion", "Potions", "C792EA"], ["reconnect", "Reconnect and the game's window", "E5C07B"]
			, ["party", "Party", "56D4C9"], ["alert", "Discord alerts", "F78FB3"]
			, ["system", "The bot itself (start, settings, pictures)", "B9E2B9"], ["other", "Everything else", "DADADA"]]
	return kinds
	}

;Which kind a log line is ("HH:mm:ss text")
DashLogKind(line)
	{
	msg := SubStr(line, 10)
	if (RegExMatch(msg, "i)^Defeated:|NEEDS YOU|\bstuck\b|couldn't|can't|\bfailed\b|didn't work|gave up|giving up|\bERR\b|error|not found|wasn't found|hung"))
		return "problem"
	if (RegExMatch(msg, "i)^Walk: (waiting|paused)|^Watching for a round|resting|^Walk: loading|loading screen|^Walk: speed: 1x"))
		return "wait"
	if (InStr(msg, "Walk:") = 1)
		return "movement"
	if (InStr(msg, "Potions:") = 1)
		return "potion"
	if (InStr(msg, "Reconnect:") = 1 || InStr(msg, "Wizard101 brought to the front") = 1)
		return "reconnect"
	if (InStr(msg, "Party:") = 1)
		return "party"
	if (InStr(msg, "Discord:") = 1)
		return "alert"
	if (RegExMatch(msg, "^(Round start|Round done|Out of battle|In a battle|Battle log|  )"))
		return "battle"
	if (RegExMatch(msg, "^(Started|Vision:|Overlay:|UI size|Pictures:|Settings|Play for me|Wait while I play|Bring Wizard101|Walking on|Walking off|Bot )"))
		return "system"
	return "other"
	}

;The colours in use: {kind: "RRGGBB"} - dashboard.ini [logcolors], else the defaults
DashLogColors(reload := false)
	{
	static colours := ""
	if (IsObject(colours) && !reload)
		return colours
	colours := V1Obj()
	for each, k in DashLogKinds()
		{
		c := IniRead(A_ScriptDir "\dashboard.ini", "logcolors", k[1], k[3])
		colours[k[1]] := RegExMatch(c, "^[0-9A-Fa-f]{6}$") ? c : k[3]
		}
	return colours
	}

;A colour RRGGBB as the COLORREF Windows wants (0x00BBGGRR)
DashBGR(rgb)
	{
	;(a standalone += - "0x" rgb + 0 inside an expression comes out blank)
	v := "0x" rgb
	v := V1N(v) + 0
	return ((v & 0xFF) << 16) | (v & 0xFF00) | ((v >> 16) & 0xFF)
	}

;The text that follows in the log box: in this colour (CHARFORMAT2W on the selection - the end, where it's added)
DashLogColour(rgb)
	{
	cf := Buffer(116, 0)
	NumPut("UInt", 116, cf, 0), NumPut("UInt", 0x40000000, cf, 4), NumPut("UInt", DashBGR(rgb), cf, 20)    ; CFM_COLOR, crTextColor
	DllCall("SendMessage", "Ptr", DashCon, "UInt", 0x444, "Ptr", 1, "Ptr", cf.Ptr)    ; EM_SETCHARFORMAT, SCF_SELECTION
	}

;The log box's length in its own characters (a line break counts 1 - as EM_SETSEL counts)
DashLogLen()
	{
	gtl := Buffer(8, 0), NumPut("UInt", 10, gtl, 0), NumPut("UInt", 1200, gtl, 4)       ; GTL_PRECISE|GTL_NUMCHARS, UTF-16
	return DllCall("SendMessage", "Ptr", DashCon, "UInt", 0x45F, "Ptr", gtl.Ptr, "Ptr", 0, "Ptr")  ; EM_GETTEXTLENGTHEX
	}

;The log box (a rich edit - an Edit can't colour its lines) set up: the dark background, Consolas 9, no word wrap
DashLogInit()
	{
	DllCall("SendMessage", "Ptr", DashCon, "UInt", 0x443, "Ptr", 0, "Ptr", DashBGR("111317"))   ; EM_SETBKGNDCOLOR
	cf := Buffer(116, 0)
	NumPut("UInt", 116, cf, 0), NumPut("UInt", 0xE0000000, cf, 4)      ; CFM_SIZE | CFM_COLOR | CFM_FACE
	NumPut("Int", 180, cf, 12), NumPut("UInt", DashBGR("DADADA"), cf, 20)
	StrPut("Consolas", cf.Ptr + 26, 32, "UTF-16")
	DllCall("SendMessage", "Ptr", DashCon, "UInt", 0x444, "Ptr", 4, "Ptr", cf.Ptr)    ; EM_SETCHARFORMAT, SCF_ALL
	DllCall("SendMessage", "Ptr", DashCon, "UInt", 0x448, "Ptr", 0, "Ptr", 1)      ; EM_SETTARGETDEVICE: no wrap
	DllCall("SendMessage", "Ptr", DashCon, "UInt", 0x435, "Ptr", 0, "Ptr", 0x7FFFFFFE)   ; EM_EXLIMITTEXT
	}

;Lines added to the log box, each in its kind's colour (runs of one kind added at once); the first half let go past
;200000 characters
DashAppend(text)
	{
	;(a rich edit's own text ends its lines with a bare CR: DashLogRecolour)
	text := StrReplace(StrReplace(text, "`r`n", "`n"), "`r", "`n")
	len := DashLogLen()
	if (len > 200000)
		{
		cutLine := DllCall("SendMessage", "Ptr", DashCon, "UInt", 0x436, "Ptr", 0, "Ptr", len // 2, "Ptr")    ; EM_EXLINEFROMCHAR
		cut := DllCall("SendMessage", "Ptr", DashCon, "UInt", 0xBB, "Ptr", cutLine + 1, "Ptr", 0, "Ptr")      ; EM_LINEINDEX
		if (cut > 0)
			{
			DllCall("SendMessage", "Ptr", DashCon, "UInt", 0xB1, "Ptr", 0, "Ptr", cut)      ; EM_SETSEL
			DllCall("SendMessage", "Ptr", DashCon, "UInt", 0xC2, "Ptr", 0, "Str", "")       ; EM_REPLACESEL
			}
		len := DashLogLen()
		}
	colours := DashLogColors()
	run := "", runKind := ""
	Loop Parse, text, "`n"
		{
		if (A_LoopField = "" && A_Index > 1)
			continue
		k := DashLogKind(A_LoopField)
		if (k != runKind && run != "")
			DashAppendRun(run, colours[runKind]), run := ""
		runKind := k, run .= A_LoopField "`r`n"
		}
	if (run != "")
		DashAppendRun(run, colours[runKind])
	DllCall("SendMessage", "Ptr", DashCon, "UInt", 0xB7, "Ptr", 0, "Ptr", 0)         ; EM_SCROLLCARET
	}

;One run of lines at the log box's end, in colour rgb
DashAppendRun(run, rgb)
	{
	len := DashLogLen()
	DllCall("SendMessage", "Ptr", DashCon, "UInt", 0xB1, "Ptr", len, "Ptr", len)      ; EM_SETSEL (the end)
	DashLogColour(rgb)
	DllCall("SendMessage", "Ptr", DashCon, "UInt", 0xC2, "Ptr", 0, "Str", run)       ; EM_REPLACESEL
	}

;The Colours window: each kind of log line - a swatch of its colour, Change... (Windows' colour picker) - and Reset
DashLogColorsWindow()
	{
	global
	local kinds, colours, i, k, y, col
	;(v1: Gui, LogCol:New - the one that was there destroyed first)
	if (IsSet(LogCol) && IsObject(LogCol))
		try LogCol.Destroy()
	LogCol := Gui("+Owner" Dash.Hwnd " +ToolWindow", "Log colours"), LogColHwnd := LogCol.Hwnd
	LogCol.OnEvent("Close", LogColGuiClose)
	LogCol.OnEvent("Escape", LogColGuiEscape)
	LogCol.BackColor := "1B1D22"
	LogCol.SetFont("s9 w400 cF2F2F2", "Segoe UI")
	kinds := DashLogKinds(), colours := DashLogColors()
	for i, k in kinds
		{
		y := 10 + (i - 1) * 28, col := colours[k[1]]
		LogCol.Add("Progress", "x10 y" y " w22 h18 Background" col " Disabled vLogColSw" i)
		LogCol.Add("Text", "x40 y" y " w270 h18 +0x200", k[2])
		LogCol.SetFont("s9 w400 c000000", "Segoe UI")
		LogCol.Add("Button", "x316 y" y " w76 h20 vLogColBtn" i, "Change...").OnEvent("Click", DashGLabel.Bind(DashLogColorPick, "Normal"))
		LogCol.SetFont("s9 w400 cF2F2F2", "Segoe UI")
		}
	y := 16 + kinds.Length * 28
	LogCol.SetFont("s9 w400 c000000", "Segoe UI")
	LogCol.Add("Button", "x10 y" y " w110 h24", "Reset all").OnEvent("Click", DashGLabel.Bind(DashLogColorReset, "Normal"))
	LogCol.Add("Button", "x292 y" y " w100 h24", "Close").OnEvent("Click", DashGLabel.Bind(DashLogColorClose, "Normal"))
	LogCol.Show("AutoSize")
	}

;Windows' colour picker, starting at rgb (RRGGBB): the colour chosen, "" cancelled
DashPickColour(rgb, owner)
	{
	;(its 16 custom colours kept between opens - made once: the buffer read as text is "" whenever slot 1 is black)
	static cust := "", custMade := 0
	if (!custMade)
		cust := Buffer(64, 0), custMade := 1
	size := A_PtrSize = 8 ? 72 : 36
	cc := Buffer(size, 0)
	NumPut("UInt", size, cc, 0)
	NumPut("Ptr", owner, cc, A_PtrSize)                         ; hwndOwner
	NumPut("UInt", DashBGR(rgb), cc, 3 * A_PtrSize)             ; rgbResult
	NumPut("Ptr", cust.Ptr, cc, 4 * A_PtrSize)                     ; lpCustColors
	NumPut("UInt", 0x3, cc, 5 * A_PtrSize)                      ; CC_RGBINIT | CC_FULLOPEN
	if (!DllCall("comdlg32\ChooseColorW", "Ptr", cc.Ptr))
		return ""
	c := NumGet(cc, 3 * A_PtrSize, "UInt")
	return Format("{:02X}{:02X}{:02X}", c & 0xFF, (c >> 8) & 0xFF, (c >> 16) & 0xFF)
	}

;The log box coloured afresh - its lines put back in, each in its kind's colour now
DashLogRecolour()
	{
	;(v1: GuiControl / GuiControlGet of a Custom control - its window text)
	lrAll := Dash["DashConsole"].Text
	Dash["DashConsole"].Text := ""
	if (lrAll != "")
		DashAppend(lrAll)
	}

;The counts and what it sees, from a log line ("HH:mm:ss text")
DashParse(line)
	{
	msg := SubStr(line, 10)
	if (InStr(msg, "Round start:") = 1)
		DashAdd("rounds"), DashSees.mode := "battle", DashSees.roundAt := A_TickCount, DashSees.plan := "", DashSees.threat := ""
	else if (msg = "Round done")
		DashSees.mode := "battle"
	else if (InStr(msg, "Out of battle") = 1)
		DashSees.mode := "out", DashSees.plan := ""
	else if (RegExMatch(msg, "^  saving pips for (\w+) \((\d+) pips, you have (\d+)\).*up to (\d+) round", &m))
		DashAdd("pipsaves"), DashSees.plan := "saving pips for " DashShortName(m[1]) " (" m[3] "/" m[2] " pips)"
	else if (RegExMatch(msg, "^  (not saving pips|saved pips) .*", &m))
		DashSees.plan := Trim(m[0])
	else if (RegExMatch(msg, "^  Click pass: found=1"))
		DashAdd("passes")
	else if (InStr(msg, "  Discarded ") = 1)
		DashAdd("discards")
	else if (InStr(msg, "  fleeing: ") = 1)
		DashAdd("flees")
	else if (InStr(msg, "Defeated:") = 1)
		DashAdd("deaths"), DashDeathsAll(1)
	;(the walker's badly-stuck count and the time lost to being stuck - Walker.ahk WalkBadlyStuckCount / WalkLostClose; a dungeon run's
	;stop for being stuck is counted there too: Dungeons.ahk)
	else if (RegExMatch(msg, "^Walk: badly stuck #\d+"))
		DashAdd("badstuck"), DashStuckAll(1, 0)
	else if (RegExMatch(msg, "^Walk: stuck over - (\d+) s lost", &m))
		DashAdd("stuckLost", m[1] + 0), DashStuckAll(0, m[1] + 0)
	else if (RegExMatch(msg, "^  kill check: (.*) -> (.*)$", &m))
		{
		DashSees.enemies := m[1]
		if (m[2] != "no lethal hit")
			DashAdd("lethal")
		}
	else if (RegExMatch(msg, "^  pips=(-?\d+)", &m))
		DashSees.pips := (m[1] < 0 ? "?" : m[1])
	;(v1: a max health of 0 - a division by zero - gave a blank, rounded to 0)
	else if (RegExMatch(msg, "^  own health: (\d+)/(\d+)", &m))
		DashSees.hp := m[1] "/" m[2] " (" V1Round(V1Div(100 * m[1], m[2])) "%, " (InStr(msg, "the game's memory") ? "the game's memory" : "name plate") ")"
	;(the round's line: " school=storm (the game's memory) | hitter=..." when the school came from the memory)
	else if (RegExMatch(msg, "school=(\w*)(?: \([^)]*\))? \| hitter=(\w*)", &m))
		DashSees.school := m[1], DashSees.hitter := m[2]
	else if (RegExMatch(msg, "^  learned a new card: (.*?)( \(picture:|$)", &m))
		DashAdd("learned"), DashSees.lastLearned := m[1]
	else if (InStr(msg, "Potions: drank one") = 1)
		DashAdd("potions")
	else if (InStr(msg, "Potions: no potion left - going to buy some") = 1)
		DashAdd("potionRuns")
	;(the backpack quick sold - QuickSell.ahk: "Backpack: quick sold 37 items for 12,345 gold (...) - 2,000 gold lost over the pouch")
	else if (RegExMatch(msg, "^Backpack: quick sold (\d+) items for ([\d,]+) gold(?:.* - ([\d,]+) gold lost over the pouch)?", &m))
		DashAdd("quicksells"), DashAdd("itemsSold", m[1] + 0), DashAdd("goldSold", StrReplace(m[2], ",") + 0), DashAdd("goldLost", m[3] = "" ? 0 : StrReplace(m[3], ",") + 0)
	else if (InStr(msg, "Reconnect: ") = 1)
		DashSees.reconnect := SubStr(msg, 12), DashSees.reconnectAt := A_TickCount
	else if (InStr(msg, "Pictures: ") = 1)
		DashSees.pictures := SubStr(msg, 11)
	else if (InStr(msg, "Stats: ") = 1)
		DashSees.stats := SubStr(msg, 8)
	else if (RegExMatch(msg, "^  (UseHeal|UseHit|UseBlade|UseTrap|UseOnSelf|UseOnHammer|UseConvert|Click) (\w+): found=1", &m) && m[2] != "pass")
		DashSees.lastTry := m[2]
	}

DashAdd(key, n := 1)
	{
	if (IsObject(DashN))
		DashN[key] := (DashN.Has(key) ? DashN[key] : 0) + n
	}

;A card went down (CastResult saw it cast)
DashCast(title)
	{
	if (!IsObject(DashCasts))
		return
	DashCasts[title] := (DashCasts.Has(title) ? DashCasts[title] : 0) + 1
	DashAdd("casts")
	DashSees.lastCast := DashCardName(title) " at " A_Hour ":" A_Min ":" A_Sec
	}

;What the bot sees (key: hand, you...)
DashSee(key, text)
	{
	if (IsObject(DashSees))
		DashSees[key] := text
	}

;The hand as the vision helper read it (/hand's answer, CardLearn.ahk): each card's name, ?<type> for one
;the bot doesn't know, * for a greyed-out one (not enough pips). A box the helper says isn't a card (field 15 = 0:
;the deck's back, the round's timer, the floor) is left out
DashHandSeen(answer)
	{
	text := "", n := 0, box := 0, notCards := 0
	Loop Parse, answer, "`n", "`r"
		{
		f := StrSplit(A_LoopField, "|")
		if (f.Length < 12 || f[1] != "card")
			continue
		;(the helper saves every box's picture, generated\hand\hand<box>.png)
		box += 1
		if (f.Length >= 15 && f[15] = "0")
			{
			notCards += 1
			continue
			}
		known := f[6]
		name := known = "" ? "?" (f[9] = "" ? "card" : f[9]) : InStr(known, "learned/") = 1 ? DashLearnedName(SubStr(known, 9)) : DashShortName(SubStr(known, InStr(known, "/") + 1), SubStr(known, 1, InStr(known, "/") - 1))
		text .= (text = "" ? "" : ", ") name (f[8] = 1 ? "*" : "")
		n += 1
		if (n <= 7)
			DashHandCard(n, name, known, f[8] = 1, f[11] != "" ? f[11] : DashKnownPips(known), box)
		}
	;(the slots past the hand: empty)
	Loop 7 - Min(n, 7)
		{
		slot := n + A_Index
		DashCardShow(slot, 0, 0)
		}
	now := FormatTime(, "HH:mm:ss")
	;(v1: GuiControl on a window not made yet did nothing)
	if (DashHwnd)
		Dash["DashHandHead"].Text := "YOUR HAND " now " (" n " card" (n = 1 ? "" : "s") (notCards ? ", " notCards " not a card" : "") ")   white known   yellow new to it   grey can't cast"
	DashSee("hand", text)
	}

;A known card's pip cost when its digit wasn't read ("" not known): an enchant (Sharpened Blade, Potent Trap, Epic,
;Colossal...) and the like are free - 0 - and a slot's cost is in PlayerStats.txt (<school>.<slot>pips); a "?" for a
;free card was shown otherwise (2026-10-23)
DashKnownPips(known)
	{
	if (known = "")
		return ""
	dir := SubStr(known, 1, InStr(known, "/") - 1), title := SubStr(known, InStr(known, "/") + 1)
	if (dir = "resources" && RegExMatch(title, "i)^(sharpen|potent|epic|colossal|gargantuan|monstrous|giant|strong)$"))
		return 0
	if (dir = "life" && title = "enchant")
		return 0
	;(0 there is an X-pip spell's - all your pips - not a free one: left as not known)
	if (IsObject(Stats) && Stats.Has(dir "." title "pips") && V1Gt(Stats[dir "." title "pips"], 0))
		return Stats[dir "." title "pips"]
	return ""
	}

;A learned card's name in the hand: the one you gave it on the Spells tab, else "learned"
DashLearnedName(id)
	{
	c := V1IsFunc("LearnCardOf") ? LearnCardOf.Call(id) : ""
	return (IsObject(c) && V1At(c, "name") != "") ? c.name : "learned"
	}

;One card of the Hand section (n: its place there): its picture as the bot saw it (generated\hand\hand<box>.png,
;saved by the vision helper - box: the helper's count, non-cards too) and under it what it took it for and the pips it
;read - white known, yellow unknown, grey greyed out
DashHandCard(n, name, known, grey, pips, box := "")
	{
	if (!DashHwnd)
		return
	pic := A_ScriptDir "\generated\hand\hand" (box = "" ? n : box) ".png"
	if (FileExist(pic))
		{
		;(the picture control is sized for 100% display scaling; the picture is loaded at its real size)
		;(v1: a picture that couldn't be loaded - ErrorLevel, nothing thrown, the control left blank and 0 x 0; v2 throws
		;and keeps the old picture: blanked as v1 did)
		try Dash["DashCardPic" n].Value := "*w" Round(58 * A_ScreenDPI / 96) " *h" Round(97 * A_ScreenDPI / 96) " " pic
		catch
			try Dash["DashCardPic" n].Value := ""
		DashCardShow(n, 1, "")
		}
	else
		DashCardShow(n, 0, "")
	colour := grey ? "8A8A8A" : known = "" ? "F2C14E" : "E8E8E8"
	Dash["DashCardTxt" n].SetFont("c" colour)
	Dash["DashCardTxt" n].Text := SubStr(name, 1, 12) "`n" (pips = "" ? "? pips" : pips " pip" (pips = 1 ? "" : "s")) (grey ? " - grey" : "")
	DashCardShow(n, "", 1)
	}

;A hand card's picture (pic) and words (txt) shown (1) or not (0) - "" left as they are: kept for the hand's view, shown
;only while it's the one up (a deck's view over it: Decks.ahk DeckViewShow puts them back)
DashCardShow(n, pic, txt)
	{
	global DashCardWant ; (v1 globals it sets)
	if (!IsObject(DashCardWant))
		DashCardWant := V1Obj()
	if (pic != "")
		DashCardWant["p" n] := pic
	if (txt != "")
		DashCardWant["t" n] := txt
	;(v1: GuiControl on a window not made yet did nothing)
	if (DeckView || !DashHwnd)
		return
	if (pic != "")
		Dash["DashCardPic" n].Visible := pic ? true : false
	if (txt != "")
		Dash["DashCardTxt" n].Visible := txt ? true : false
	}

;The Cards tab's enemies (EnemySpells.ahk EnemyDanger, each round): each one - its school, rank and health off the wiki,
;the chance it hits you, its pips - and under it every spell it has, likeliest first: the chance it casts it this
;round, its pips and damage, the rounds it cast it this battle, how often it was seen casting it (all battles, weighed).
;answer: /enemies'; lethal: the chance their hits kill you this round ("" not known); health: yours as read ("" not
;read); rnd: the round
;(v2 port: a field the line hasn't - V1At - was blank in v1, and v1 did math with a blank or text one: V1Round, V1Mul;
;v1's Round of one to 1 place was "0.0": Round(V1N(x), 1))
DashFoesSeen(answer, lethal, health, rnd)
	{
	if (!DashHwnd)
		return
	wasCrit := A_IsCritical
	Critical()
	;(the window has three ListViews: this one for the LV_ functions, the one before put back after - v2: the control)
	lv := Dash["DashFoeList"]
	lv.Opt("-Redraw")
	lv.Delete()
	foes := 0
	Loop Parse, answer, "`n", "`r"
		{
		f := StrSplit(A_LoopField, "|")
		if (f[1] != "enemy")
			continue
		foes += 1
		if (foes > 1)
			lv.Add("", "")
		if (V1At(f, 4) != "ok")
			lv.Add("", V1At(f, 3), V1At(f, 4) = "pending" ? "looking it up on the wiki" : "not on the wiki - its spells not known")
		else
			{
			about := (V1At(f, 9) != "" ? f[9] : "") (V1At(f, 10) != "" ? ", rank " f[10] : "") (V1At(f, 11) != "" ? ", " f[11] " health" : "")
			lv.Add("", f[3], about = "" ? "" : "(" LTrim(about, ", ") ")", "hits you " V1Round(V1Mul(V1At(f, 6), 100)) "%"
				, "~" Round(V1N(V1At(f, 5)), 1) " pips now" (V1Gt(V1At(f, 7), 0) ? ", biggest hit " f[7] : ""))
			}
		;(spell:chance:pips and damage:seen before:rounds cast this battle)
		for each, card in StrSplit(V1At(f, 12), ";")
			{
			p := StrSplit(card, ":")
			if (p[1] = "")
				continue
			lv.Add("", "", "   " p[1], V1Round(V1Mul(V1At(p, 2), 100)) "%", V1At(p, 3), V1At(p, 5) = "" ? "" : "round " StrReplace(p[5], "/", ", ")
				, V1Gt(V1At(p, 4), 0) ? RegExReplace(V1Round(p[4], 1), "\.0$") : "")
			}
		}
	lv.Opt("+Redraw")
	now := FormatTime(, "HH:mm:ss")
	Dash["DashFoeHead"].Text := "ENEMIES " now ", round " rnd " - " (foes = 0 ? "none named in the game's log"
		: lethal = "" ? "your health not read: the chance they kill you not known" : V1Round(V1Mul(lethal, 100)) "% chance their hits kill you this round (your health " health ")")
	if (!wasCrit)
		Critical("Off")
	}

;A slot's card name alone (e.g. "Scarab"), else the slot
DashShortName(title, dir := "")
	{
	full := DashCardName(title, dir)
	return InStr(full, " (") ? SubStr(full, 1, InStr(full, " (") - 1) : full
	}

;A card's name for a slot (e.g. hit1 -> "Scarab"), from its comment in PlayerStats.txt; else the slot
DashCardName(title, dir := "")
	{
	global DashNames ; (v1 globals it sets)
	if (!IsObject(DashNames) || A_TickCount - DashNames._at > 60000)
		{
		DashNames := V1Obj({_at: A_TickCount})
		prevKey := ""
		Loop Read, A_ScriptDir "\PlayerStats.txt"
			{
			line := A_LoopReadLine
			if (RegExMatch(line, "^\s*([\w.]+)\s*:[^;]*;\s*(.*)$", &m))
				key := m[1], comment := m[2]
			else if (prevKey != "" && RegExMatch(line, "^\s*;\s*\^\s*(.*)$", &m))
				key := prevKey, comment := m[1]
			else
				{
				prevKey := RegExMatch(line, "^\s*([\w.]+)\s*:", &m) ? m[1] : ""
				continue
				}
			prevKey := RegExMatch(line, "^\s*([\w.]+)\s*:", &k) ? k[1] : ""
			comment := RegExReplace(comment, "i)^learned \d+:\s*")
			if (RegExMatch(comment, "^([A-Z][A-Za-z']*(?: [A-Z][A-Za-z']*)*)", &n) && !DashNames.Has(key))
				DashNames[key] := n[1]
			}
		;(v1: no PlayerStats.txt - no lines read, nothing thrown)
		else
			{
			}
		}
	key := Format("{:L}", (dir != "" && dir != "resources" ? dir : hitschool) "." title)
	if (DashNames.Has(key))
		return DashNames[key] " (" title ")"
	key := Format("{:L}", title)
	return DashNames.Has(key) ? DashNames[key] " (" title ")" : title
	}

;---- Showing it ----

;(v2 port) v1's timer label DashRefresh: - DashRefresh() on a thread of its own (with its own ErrorLevel)
DashRefreshTick()
	{
	local v1Own := V1Thread()  ; (v1: the timer's label ran as its own thread, with its own ErrorLevel)
	local v1Keep := V1Thread() ; (v1: each thread had its own ErrorLevel)
	DashRefresh()
	}

DashRefresh()
	{
	global DashUpdBusy ; (v1 globals it sets)
	;(a dungeon run or recording: its line on the Dungeons tab)
	if (IsObject(DgRun) || DgRecording)
		DgShow()
	if (!DashShown || !DashHwnd)
		return
	;(the Spells tab's list: again when the catalog changed - LearnSave - or a correction was applied)
	if (SpDirty)
		SpListFill()
	up := (A_TickCount - DashStart) // 1000
	upText := Format("{:02}:{:02}:{:02}", up // 3600, Mod(up // 60, 60), Mod(up, 60))
	;What it's doing
	;(Wizard101 in the tray - Settings: traygame - Autofarmer.ahk GameTrayHide: the bot off till it's shown again - the
	;Bot menu's Show Wizard101, or the tray menu's)
	if (GameInTray)
		doing := "Wizard101 is in the tray - Bot > Show Wizard101 brings it back"
	else if (!BotOn)
		doing := BotEverOn ? "Off - " HkText("bot") " turns the bot on" : "Standby - press " HkText("bot") " to start the bot"
	else if (PotionRecording)
		doing := "Recording potion buying"
	else if (LearnAll)
		doing := "Learning every card (" (IsObject(LearnedCards) ? V1Sub(LearnedCards.Length, LearnAllFrom) : 0) " new so far)"
	else if (WkNoteKind != "")
		doing := "Needs you: " WkNoteTitle
	else if (PlayerActive)
		doing := "You're playing - the bot waits"
	;(v1: a round never started - roundAt blank - counted as just now: "" < 120000 as text)
	else if (DashSees.mode = "battle" && V1Lt(V1Ago(DashSees.roundAt), 120000))
		doing := "In battle (round " DashN.rounds ")"
	;(battles only - Settings: battlesonly - Autofarmer.ahk: out of battle it waits for one and moves nothing)
	else if (V1IsFunc("BattlesOnly") && BattlesOnly.Call())
		doing := "Battles only - waiting for a battle (Settings)"
	else if (!Walking)
		doing := "Walking off (" HkText("walk") ")"
	else if (StatusText != "")
		doing := StatusText
	else
		doing := "Watching"
	;(the window's title says "Wizard101 bot")
	DashSet("DashHead", BotVersion() "  |  up " upText "  |  vision " (VisionOn ? "on" : "off") "  |  " SubStr(doing, 1, 70))
	;The version, and whether a newer one is out (the last look-up: UpdState) - the menu bar's "Update to vX" too
	;(DashMenuTicks)
	upd := UpdState()
	verNote := upd.newer ? upd.latest " is out" : upd.err != "" ? "can't check" : upd.latest != "" ? "up to date" : "not checked yet"
	;(why it can't check: in the log, once each time it changes)
	static updErrSaid := ""
	if (upd.err != updErrSaid)
		{
		updErrSaid := upd.err
		if (upd.err != "")
			DebugLog("Updates: can't check for a newer version - " upd.err)
		}
	;(Help > Check for updates: "Checking..." for 10 s after a click - DashUpdButton)
	if (DashUpdBusy && A_TickCount - DashUpdBusy > 10000)
		DashUpdBusy := 0
	;(the menu bar as things are - walking, the tray settings, Wizard101 in the tray and the overlay change in many
	;places, so they're looked at here every second - and the Update item)
	DashMenuTicks()
	;Statistics
	n := DashN
	casts := ""
	for title, count in DashCasts
		casts .= "`n   " SubStr(DashCardName(title) "                              ", 1, 25) Format("{:6}", count)
	;(the cards cast one by one last: what the box's height cuts off)
	s := "Version          " (BotVersion() = "" ? "?" : BotVersion()) " - " verNote "`n"
		. "Battles          " DashNum(battles) (V1IsFunc("BrecToday") ? BrecToday.Call() : "") "`n"
		. "Deaths           " DashNum(n.deaths) "   (all time: " DashDeathsAll() ")`n"
		. "Badly stuck      " DashNum(n.badstuck) "   (" DashLostSay(n.stuckLost) "; all: " DashStuckAll().n ", " DashLostSay(DashStuckAll().s) ")`n"
		. "Rounds played    " DashNum(n.rounds) "`n"
		. "Passed           " DashNum(n.passes) "   (fled: " (n.flees = "" ? 0 : n.flees) ")`n"
		. "Discarded        " DashNum(n.discards) "`n"
		. "Kill-check hits  " DashNum(n.lethal) "`n"
		. "Rounds saving pips" SubStr(DashNum(n.pipsaves), 2) "`n"
		. "Potions drunk    " DashNum(n.potions) "   (buying runs: " (n.potionRuns = "" ? 0 : n.potionRuns) ")`n"
		. (n.quicksells ? "Quick sells      " DashNum(n.quicksells) "   (" n.itemsSold " items, " QsThousands(n.goldSold) " gold" (n.goldLost ? ", " QsThousands(n.goldLost) " lost over the pouch" : "") ")`n" : "")
		. "Cards learned    " DashNum(n.learned) "`n"
		. "Cards cast       " DashNum(n.casts) casts
	DashSet("DashStatText", s)
	DashSet("DashUsageText", DashUsage())
	;What it sees
	see := DashSees
	zone := V1IsFunc("WalkZone") ? WalkZone.Call() : ""
	t := "You          " (see.hp != "" ? see.hp : "?") (see.mana != "" ? ", mana " see.mana : "") ", pips " (see.pips != "" ? see.pips : "?") "`n"
		. "School       " (see.school != "" ? see.school : "?") "  (hitting with " (see.hitter != "" ? see.hitter : "?") ")`n"
		. "Hand         " DashCut(see.hand != "" ? see.hand : "-") "`n"
		. "Enemies      " DashCut(see.enemies != "" ? see.enemies : "-") "`n"
		. "Threat       " DashCut(see.threat != "" ? see.threat : "-") "`n"
		. "Plan         " DashCut(see.plan != "" ? see.plan : "-") "`n"
		. "Deck         " DashCut(see.deck != "" ? see.deck : "-") "`n"
		. ((V1IsFunc("TrainStatus") && TrainStatus.Call() != "") ? "Spells       " DashCut(TrainStatus.Call()) "`n" : "")
		. "Last cast    " (see.lastCast != "" ? see.lastCast : "-") "`n"
		. "Zone         " DashCut(zone != "" ? zone : "?") "`n"
		. "Walker       " DashCut(StatusText != "" ? StatusText : "-") "`n"
		. (see.party != "" ? "Party        " DashCut(see.party) "`n" : "")
		. "Pictures     " DashCut(see.pictures != "" ? RegExReplace(see.pictures, " - card area.*") : "?") "`n"
		. "Last learned " DashCut(see.lastLearned != "" ? see.lastLearned : "-")
		. (see.reconnect != "" && V1Lt(V1Ago(see.reconnectAt), 600000) ? "`nReconnect    " DashCut(see.reconnect) : "")
	DashSet("DashSeeText", t)
	}

;A value cut to what fits the "What it sees" column (its width, past the 13-letter label; Consolas 9 is
;about 7 px a letter - the width is in 100%-scaling pixels too)
DashCut(text)
	{
	Dash["DashSeeText"].GetPos(, , &posW)
	fit := Max(20, Floor(posW / 7) - 14)
	return StrLen(text) > fit ? SubStr(text, 1, fit - 1) "~" : text
	}

;Deaths over every run (dashboard.ini [stats] deaths - updates keep it): add one or more, and the total
DashDeathsAll(add := 0)
	{
	static total := ""
	if (total = "")
		{
		total := IniRead(A_ScriptDir "\dashboard.ini", "stats", "deaths", 0)
		total := RegExMatch(total, "^\d+$") ? total + 0 : 0
		}
	if (add)
		{
		total += add
		V1Do(IniWrite, total, A_ScriptDir "\dashboard.ini", "stats", "deaths")
		}
	return total
	}

;Badly stuck over every run, and the seconds lost to being stuck (dashboard.ini [stats] badstuck, stucklost - updates keep them; the
;walker's "badly stuck #N" and "stuck over - N s lost" lines, DashParse): add to them, and the totals {n, s}
DashStuckAll(addN := 0, addS := 0)
	{
	static all := ""
	if (!IsObject(all))
		{
		all := V1Obj({n: IniRead(A_ScriptDir "\dashboard.ini", "stats", "badstuck", 0), s: IniRead(A_ScriptDir "\dashboard.ini", "stats", "stucklost", 0)})
		all.n := RegExMatch(all.n, "^\d+$") ? all.n + 0 : 0
		all.s := RegExMatch(all.s, "^\d+$") ? all.s + 0 : 0
		}
	if (addN)
		{
		all.n += addN
		V1Do(IniWrite, all.n, A_ScriptDir "\dashboard.ini", "stats", "badstuck")
		}
	if (addS)
		{
		all.s += addS
		V1Do(IniWrite, all.s, A_ScriptDir "\dashboard.ini", "stats", "stucklost")
		}
	return all
	}

;Seconds lost to being stuck, said short: "0 min", "12 min", "3.4 h" (blank = 0)
DashLostSay(s)
	{
	s := V1N(s)
	return s < 3600 ? Round(s / 60) " min" : Round(s / 3600, 1) " h"
	}

;A count, right-aligned (blank = 0)
DashNum(v)
	{
	return Format("{:6}", v = "" ? 0 : v)
	}

;Sets a control's text only when it changed (no flicker)
;(v2 port: the controls it's given are Text and Button ones - their text; v1's GuiControl did nothing without the window)
DashSet(control, text)
	{
	static last := V1Obj()
	if (last[control] == text)
		return
	last[control] := text
	if (DashHwnd)
		Dash[control].Text := text
	}

;---- The map ----
;
;A window with a top-down picture of the zone the wizard is in, drawn by the vision helper (/navmap: the
;floor, what's in the way, the game's path, the wizard as an arrow, where the arrow points, the goal), and
;under it a line off /nav: the zone, where the wizard is, how far the goal is. Read from the game's memory by
;the helper (read-only). A new picture once a second while it's shown; closing it only hides it (and stops
;asking). Its requests don't wait for the answer - the next tick (every 250 ms) picks it up - so the bot never
;waits for the map. It never takes the focus by itself. Its place is kept in dashboard.ini [map].
;(v2 port: the window is the Gui object MapGui - v1's GUI Map; Map is v2's class)

;View > Map / the tray menu: shows or hides it
DashMapToggle()
	{
	if (DashMapShown)
		DashMapHide()
	else
		DashMapShow()
	V1Do(IniWrite, DashMapShown ? 1 : 0, A_ScriptDir "\dashboard.ini", "map", "shown")
	}

;Makes the window (hidden), the first time it's shown
DashMapMake()
	{
	global DashMapShown, DashMapReq, DashMapKind, DashMapAt, DashMapW, DashMapH, DashMapNote, DashMapNav, DashMapPicAt ; (v1 globals it sets)
	global DashMapFile, MapGui, DashMapHwnd, DashMapPicH ; (v1 globals it sets)
	DashMapShown := 0, DashMapReq := "", DashMapKind := "", DashMapAt := 0, DashMapW := 0, DashMapH := 0
	DashMapNote := "", DashMapNav := "", DashMapPicAt := ""
	;(in the temp folder: it's rewritten every second, which OneDrive would keep uploading)
	DashMapFile := A_Temp "\Wizard101 bot map\navmap.png"
	V1Do(DirCreate, A_Temp "\Wizard101 bot map")
	V1Do(DirCreate, A_ScriptDir "\generated")
	MapGui := Gui("+Resize +MinSize320x240"), DashMapHwnd := MapGui.Hwnd
	MapGui.OnEvent("Close", MapGuiClose)
	MapGui.OnEvent("Size", MapGuiSize)
	MapGui.BackColor := "1B1D22"
	MapGui.MarginX := 8, MapGui.MarginY := 8
	DashMapPicH := MapGui.Add("Picture", "x8 y8 w624 h460 vDashMapPic").Hwnd
	MapGui.SetFont("s9 w400 cDADADA", "Consolas")
	;(one line: cut with "..." when it's longer than the window is wide, not wrapped)
	MapGui.Add("Text", "x8 y474 w624 h18 +0x400C vDashMapText", "Asking the vision helper for the map...")
	}

;Shows it where it was (else beside the dashboard), without taking the focus, and starts asking
;(v2 port: IniRead's "" default is v1's %A_Space% - a blank; dashboard.ini's numbers as v1 did math with them)
DashMapShow()
	{
	global DashMapShown, DashMapAt ; (v1 globals it sets)
	if (!DashMapHwnd)
		DashMapMake()
	x := IniRead(A_ScriptDir "\dashboard.ini", "map", "x", "")
	y := IniRead(A_ScriptDir "\dashboard.ini", "map", "y", "")
	w := IniRead(A_ScriptDir "\dashboard.ini", "map", "w", 640)
	h := IniRead(A_ScriptDir "\dashboard.ini", "map", "h", 500)
	if (x = "" || y = "" || !DashOnScreen(V1Add(x, 40), V1Add(y, 20)))
		DashMapPlace(&x, &y, w, h)
	DashFitHeight(x, y, &h)
	MapGui.Title := "Wizard101 bot " BotVersion() " - map"
	MapGui.Show("x" x " y" y " w" w " h" h " NoActivate")
	DashMapShown := 1, DashMapAt := 0
	SetTimer(DashMapTick, 250)
	;(the View menu's tick)
	DashMenuTicks()
	}

;Hides it (keeping its place) and stops asking
DashMapHide()
	{
	global DashMapShown, DashMapReq ; (v1 globals it sets)
	if (!DashMapHwnd)
		return
	if (DashMapShown)
		DashSaveWin(DashMapHwnd, "map")
	MapGui.Hide()
	DashMapShown := 0
	SetTimer(DashMapTick, 0)
	if (IsObject(DashMapReq))
		try DashMapReq.Abort()
	DashMapReq := ""
	;(the View menu's tick)
	DashMenuTicks()
	}

;Where it goes the first time (w, h: its inside at 100% display scaling): beside the dashboard - right of it,
;below, left or above, whichever fits on the dashboard's monitor - else that monitor's bottom right (the
;spare monitor's, when the dashboard is hidden)
DashMapPlace(&x, &y, w, h)
	{
	dpi := A_ScreenDPI / 96
	ow := V1Round(V1Mul(w, dpi)) + 16, oh := V1Round(V1Mul(h, dpi)) + 40
	if (DashShown && DashHwnd)
		{
		WinGetPos(&dx, &dy, &dw, &dh, "ahk_id " DashHwnd)
		DashMonitorAt(dx + dw // 2, dy + dh // 2, &mLeft, &mTop, &mRight, &mBottom)
		for each, p in [[dx + dw + 8, dy], [dx, dy + dh + 8], [dx - ow - 8, dy], [dx, dy - oh - 8]]
			if (p[1] >= mLeft && p[2] >= mTop && p[1] + ow <= mRight && p[2] + oh <= mBottom)
				{
				x := p[1], y := p[2]
				return
				}
		}
	else
		DashSpareMonitor(&mLeft, &mTop, &mRight, &mBottom)
	x := Max(mLeft, mRight - ow - 20), y := Max(mTop, mBottom - oh - 20)
	}

;Every 250 ms while it's shown: picks up the answer it's waiting for; else asks for a new picture once a
;second (at once when the window's size changed)
DashMapTick()
	{
	global DashMapAt, DashMapW, DashMapH ; (v1 globals it sets)
	if (!DashMapShown)
		{
		SetTimer(DashMapTick, 0)
		return
		}
	if (IsObject(DashMapReq))
		return DashMapCheck()
	;(minimized: nothing to draw)
	if (DllCall("IsIconic", "Ptr", DashMapHwnd))
		return
	;(the picture is asked for at the size it's shown at, in screen pixels: shown as it is, not stretched)
	rc := Buffer(16, 0)
	DllCall("GetClientRect", "Ptr", DashMapPicH, "Ptr", rc.Ptr)
	pw := NumGet(rc, 8, "Int"), ph := NumGet(rc, 12, "Int")
	if (pw < 16 || ph < 16)
		{
		;(a picture that didn't load shrinks the control to nothing: back to the window's size)
		DashMapFit()
		return
		}
	if (A_TickCount - DashMapAt < 1000 && pw = DashMapW && ph = DashMapH)
		return
	DashMapAt := A_TickCount, DashMapW := pw, DashMapH := ph
	DashMapAsk("map", "/navmap?w=" pw "&h=" ph "&out=" DashMapUri(DashMapFile))
	}

;Sends a request to the vision helper without waiting for the answer (DashMapCheck picks it up). Not
;VisionGet: that waits, and its failures count towards turning the card vision off - the map's mustn't
DashMapAsk(kind, path)
	{
	global DashMapReq, DashMapKind, DashMapReqAt ; (v1 globals it sets)
	DashMapReq := "", DashMapKind := kind, DashMapReqAt := A_TickCount
	try
		{
		req := ComObject("WinHttp.WinHttpRequest.5.1")
		req.Open("GET", "http://127.0.0.1:" (VisionPort ? VisionPort : 47128) path, true)
		req.Send()
		DashMapReq := req
		}
	catch
		DashMapGot(kind, "", false)
	}

;The answer to the request sent, once it's there (after 4 s it's given up)
DashMapCheck()
	{
	global DashMapReq ; (v1 globals it sets)
	req := DashMapReq, done := 0
	try
		done := req.WaitForResponse(0)
	catch
		{
		;(nothing answering on the port: the helper isn't running)
		DashMapReq := ""
		return DashMapGot(DashMapKind, "", false)
		}
	if (!done)
		{
		if (A_TickCount - DashMapReqAt > 4000)
			{
			try req.Abort()
			DashMapReq := ""
			DashMapGot(DashMapKind, "ERR the vision helper didn't answer in 4 s", false)
			}
		return
		}
	DashMapReq := "", text := "", status := 0
	try
		text := req.ResponseText, status := req.Status
	text := Trim(text, " `t`r`n")
	if (status != 200 && InStr(text, "ERR") != 1)
		text := "ERR the vision helper answered " status
	DashMapGot(DashMapKind, text, true)
	}

;An answer ("" = the helper couldn't be asked; answered: it did answer): the picture, then the line under it
DashMapGot(kind, text, answered)
	{
	global DashMapNote, DashMapPicAt, DashMapNav ; (v1 globals it sets)
	if (kind = "map")
		{
		f := SubStr(text, 4)
		if (InStr(text, "ok|") != 1)
			DashMapNote := "Map: " DashMapWhy(text)
		else if (!FileExist(f) && !FileExist(f := DashMapFile))
			DashMapNote := "Map: the picture isn't there (" f ")"
		else
			{
			;(no *w *h: fitted to the control - the size it was asked for)
			;(v1: a picture that couldn't be loaded - ErrorLevel, nothing thrown, the control left blank and 0 x 0 - what
			;DashMapTick's refit is for; v2 throws and keeps the old picture: blanked as v1 did)
			try MapGui["DashMapPic"].Value := f
			catch
				try MapGui["DashMapPic"].Value := ""
			DashMapPicAt := A_Hour ":" A_Min ":" A_Sec, DashMapNote := ""
			}
		if (DashMapNote != "" && DashMapPicAt != "")
			DashMapNote .= " (picture from " DashMapPicAt ")"
		;(then /nav for the line under it, if the helper is there to ask)
		if (answered)
			DashMapAsk("nav", "/nav")
		else
			DashMapNav := ""
		}
	else
		DashMapNav := text
	DashMapLine()
	}

;Why a request got no picture / no position ("ERR <why>", or "" when the helper couldn't be asked)
DashMapWhy(text)
	{
	if (text = "")
		return VisionOn ? "no answer from the vision helper (see vision\vision.log)" : "the vision helper isn't running (debug.log says why)"
	return InStr(text, "ERR") = 1 ? Trim(SubStr(text, 4)) : "an odd answer: " SubStr(text, 1, 60)
	}

;The line under the picture: what went wrong with the picture (if anything), then the zone, the place, the goal
DashMapLine()
	{
	static last := ""
	nav := DashMapNav
	if (InStr(nav, "ERR") = 1)
		{
		why := DashMapWhy(nav)
		;(the same reason as the picture's: once is enough)
		nav := InStr(DashMapNote, why) ? "" : "Can't read the game: " why
		}
	else
		nav := DashMapNavLine(nav)
	line := DashMapNote (DashMapNote != "" && nav != "" ? " | " : "") nav
	if (line == last)
		return
	last := line
	MapGui["DashMapText"].Text := line
	}

;/nav's answer as "zone | at x, y, z | goal in this zone | arrow 1520" (? for what it couldn't read; arrow = how
;far the on-screen arrow's point is, along the game's path)
;(v2 port: a field a line hasn't - V1At - was blank in v1)
DashMapNavLine(answer)
	{
	if (answer = "")
		return ""
	f := V1Obj()
	Loop Parse, answer, "`n", "`r"
		{
		p := StrSplit(A_LoopField, "|")
		f[p[1]] := p
		}
	if (!IsObject(f.ok))
		return "an odd /nav answer: " SubStr(answer, 1, 60)
	zone := IsObject(f.zone) && V1At(f.zone, 2) != "" ? f.zone[2] : "zone ?"
	pos := IsObject(f.pos) ? "at " DashMapNum(V1At(f.pos, 2)) ", " DashMapNum(V1At(f.pos, 3)) ", " DashMapNum(V1At(f.pos, 4)) : "at ?"
	hops := IsObject(f.goal) ? V1At(f.goal, 5) : ""
	goal := hops = "" ? "goal ?" : hops = 0 ? "goal in this zone" : "goal " hops " zone" (hops = 1 ? "" : "s") " away"
	if (IsObject(f.quest) && V1At(f.quest, 2) = "0")
		goal := "no quest goal (the quest helper is off)"
	arrow := IsObject(f.dist) && V1At(f.dist, 2) != "" ? " | arrow " DashMapNum(f.dist[2]) : ""
	return zone " | " pos " | " goal arrow
	}

;(v2 port: v1's Round of text - 0)
DashMapNum(v)
	{
	return v = "" ? "?" : V1Round(v)
	}

;Fits the picture and the line to the window (gw, gh: its inside at 100% display scaling, as GuiSize gives
;them; blank: the window's now)
DashMapFit(gw := "", gh := "")
	{
	if (gw = "")
		{
		rc := Buffer(16, 0)
		DllCall("GetClientRect", "Ptr", DashMapHwnd, "Ptr", rc.Ptr)
		gw := Round(NumGet(rc, 8, "Int") * 96 / A_ScreenDPI), gh := Round(NumGet(rc, 12, "Int") * 96 / A_ScreenDPI)
		}
	MapGui["DashMapPic"].Move(, , Max(16, gw - 16), Max(16, gh - 40))
	MapGui["DashMapText"].Move(, gh - 26, Max(16, gw - 16))
	}

;Text for a URL: UTF-8, everything but letters, digits and - . _ ~ %-escaped
DashMapUri(s)
	{
	buf := Buffer(StrPut(s, "UTF-8"), 0)
	n := StrPut(s, buf, "UTF-8") - 1
	out := ""
	Loop n
		{
		c := NumGet(buf, A_Index - 1, "UChar")
		out .= (c >= 48 && c <= 57 || c >= 65 && c <= 90 || c >= 97 && c <= 122 || c = 45 || c = 46 || c = 95 || c = 126) ? Chr(c) : "%" Format("{:02X}", c)
		}
	return out
	}

DashMapButton:
DashMapButton()
	return

DashMapTick:
DashMapTick()
	return

MapGuiClose:
MapGuiClose()
	return

MapGuiSize:
MapGuiSize()
	return

;---- The dashboard's buttons and menu items (the menu bar: DashMenuMake) ----

DashRefresh:
DashRefresh()
	return

DashPauseLog:
DashPauseLog()
	return

DashClearLog:
DashClearLog()
	return

;The Network tab: a bot picked (its log and picture fetched now), and the buttons for it
DashNetListEvent:
DashNetListEvent()
	return

DashNetOn:
DashNetOn()
return
DashNetOff:
DashNetOff()
return
DashNetPfm:
DashNetPfm()
return
DashNetRestart:
DashNetRestart()
	return

DashNetRefresh:
DashNetRefresh()
	return

;View > Log colours..., and its window's buttons: a kind's colour changed (kept in dashboard.ini [logcolors]), all
;back to the defaults, the window closed - the log coloured afresh each time
DashLogColorsBtn:
DashLogColorsBtn()
	return

DashLogColorPick:
DashLogColorPick()
	return

DashLogColorReset:
DashLogColorReset()
	return

DashLogColorClose:
DashLogColorClose()
return
LogColGuiClose:
LogColGuiClose()
return
LogColGuiEscape:
LogColGuiEscape()
	return

DashOpenLog:
DashOpenLog()
	return

DashWalkToggle:
DashWalkToggle()
	return

DashFolder:
DashFolder()
	return

;CPU and RAM in use, for the STATISTICS row: the bot (this script and its vision helper), the game, the whole PC.
;CPU from the time each has used since the last look (all cores = 100%), RAM its working set (what Task Manager
;shows, about). Read-only process queries - nothing is changed
DashUsage()
	{
	static last := V1Obj(), procs := V1Obj()
	cores := EnvGet("NUMBER_OF_PROCESSORS")
	cores := V1Gt(cores, 0) ? cores : 1
	now := A_TickCount
	gamePid := 0
	;(v1: WinGet PID with no game window - blank; v2 throws)
	gamePid := V1Try(WinGetPID, "ahk_class " GameClass " ahk_exe " GameExe)
	who := V1Obj({bot: [DllCall("GetCurrentProcessId"), VisionPid], game: [gamePid]})
	out := V1Obj()
	for name, pids in who
		{
		cpu := 0, ram := 0, seen := 0
		for each, pid in pids
			{
			if (!pid)
				continue
			if (!procs.Has(pid))
				procs[pid] := DllCall("OpenProcess", "UInt", 0x1000, "Int", 0, "UInt", pid, "Ptr")
			h := procs[pid]
			if (!h)
				continue
			ft := Buffer(32, 0)
			if (!DllCall("GetProcessTimes", "Ptr", h, "Ptr", ft.Ptr, "Ptr", ft.Ptr + 8, "Ptr", ft.Ptr + 16, "Ptr", ft.Ptr + 24))
				{
				DllCall("CloseHandle", "Ptr", h), procs.Delete(pid)
				continue
				}
			used := NumGet(ft, 16, "Int64") + NumGet(ft, 24, "Int64")
			if (last.Has(pid) && now > last[pid].at)
				cpu += (used - last[pid].used) / 10000 / (now - last[pid].at) / cores * 100
			last[pid] := V1Obj({used: used, at: now})
			cb := 8 + 8 * A_PtrSize
			pmc := Buffer(cb, 0), NumPut("UInt", cb, pmc, 0)
			if (DllCall("K32GetProcessMemoryInfo", "Ptr", h, "Ptr", pmc.Ptr, "UInt", cb))
				ram += NumGet(pmc, 8 + A_PtrSize, "UPtr")
			seen += 1
			}
		out[name] := seen ? DashUsageNum(cpu) "%" Chr(183) DashBytes(ram) : "-"
		}
	;the whole PC: busy share of all cores since the last look, and RAM in use
	st := Buffer(24, 0)
	pcCpu := "?"
	if (DllCall("GetSystemTimes", "Ptr", st.Ptr, "Ptr", st.Ptr + 8, "Ptr", st.Ptr + 16))
		{
		idle := NumGet(st, 0, "Int64"), total := NumGet(st, 8, "Int64") + NumGet(st, 16, "Int64")
		if (last.Has("pc") && total > last.pc.total)
			pcCpu := DashUsageNum(100 * (1 - (idle - last.pc.idle) / (total - last.pc.total)))
		last.pc := V1Obj({idle: idle, total: total})
		}
	ms := Buffer(64, 0), NumPut("UInt", 64, ms, 0)
	pcRam := DllCall("GlobalMemoryStatusEx", "Ptr", ms.Ptr) ? NumGet(ms, 4, "UInt") "%" : "?"
	return "CPU" Chr(183) "RAM   bot " out.bot "   game " out.game "   PC " pcCpu "%" Chr(183) pcRam
	}

DashUsageNum(v)
	{
	return v < 0 ? 0 : v < 10 ? Round(v, 1) : Round(v)
	}

DashBytes(n)
	{
	return n >= 1073741824 ? Round(n / 1073741824, 1) "GB" : Round(n / 1048576) "MB"
	}

DashUpdButton:
DashUpdButton()
	return

;Help > Report a bug... (BugReport.ahk): what went wrong, posted as an issue on GitHub
DashBugButton:
DashBugButton()
	return

;Settings > Settings... - the Settings window (Settings.ahk): the mouse, the waits, how it plays its cards
DashSettingsButton:
DashSettingsButton()
	return

;"Learn every card" on/off (CardLearn.ahk)
DashLearnAll:
DashLearnAll()
	return

;The bot on/off (BotToggle in Autofarmer.ahk)
DashBotToggle:
DashBotToggle()
	return

;View > Simple view on / off (dashboard.ini [view] dashboard): each view keeps its own place and size
DashViewToggle:
DashViewToggle()
	return

;"Bring Wizard101 to the front" on/off (GameFrontToggle in Autofarmer.ahk)
DashFrontToggle:
DashFrontToggle()
	return

;"Play for me" on/off (PlayForMeToggle in Autofarmer.ahk)
DashPlayToggle:
DashPlayToggle()
	return

;"Wait while I play" on/off (HandsOffToggle in Autofarmer.ahk)
DashHandsToggle:
DashHandsToggle()
	return

;(v1's label, never run: the window's X runs DashGuiClose(*) - it stops the bot, or with traybot on puts the window
;in the tray)
DashGuiClose:
DashGuiClose()
	ExitApp()
	return

DashGuiSize:
DashGuiSize()
	return

;###############  v1's labels, as functions  ###############
;(v2 port: each v1 label as a function - called through DashGLabel for a control, so A_GuiControl is the control's v1
;name; the window events with v2's own parameters)
DashMapButton(A_GuiEvent:="", A_GuiControl:="", Info:="", *) { ; (v1: a label - its code ran in the global scope)
	global
	DashMapToggle()
	return
}
;##############################################
MapGuiClose(*) { ; (v1: a label - its code ran in the global scope)
	global
	local v1Keep := V1Thread() ; (v1: each thread had its own ErrorLevel)
	local v1Own := V1Thread()  ; (v1: the close ran as a thread of its own - DashMapToggle's IniWrite set its ErrorLevel only)
	DashMapToggle()
	return
}
;##############################################
;(v1: A_EventInfo 1 - minimized; v2's MinMax -1)
MapGuiSize(thisGui:="", MinMax:="", A_GuiWidth:="", A_GuiHeight:="") { ; (v1: a label - its code ran in the global scope)
	global
	if (MinMax != -1)
		DashMapFit(A_GuiWidth, A_GuiHeight)
	return
}
;##############################################
DashPauseLog(A_GuiEvent:="", A_GuiControl:="", Info:="", *) { ; (v1: a label - its code ran in the global scope)
	global
	DashPaused := !DashPaused
	;(View > Pause log: ticked while it's paused)
	DashMenuTicks()
	if (!DashPaused && DashHeld != "")
		DashAppend(DashHeld), DashHeld := ""
	return
}
;##############################################
DashClearLog(A_GuiEvent:="", A_GuiControl:="", Info:="", *) { ; (v1: a label - its code ran in the global scope)
	global
	;(v1: GuiControl of a Custom control - its window text)
	Dash["DashConsole"].Text := ""
	return
}
;##############################################
;(v1: A_GuiEvent "I" with ErrorLevel S / s / F / f - DashLvItem gives them; LV_GetText of a row that isn't there -
;blank)
DashNetListEvent(A_GuiEvent:="", A_GuiControl:="", Info:="", *) { ; (v1: a label - its code ran in the global scope)
	global
	if (A_GuiEvent = "I" && InStr(ErrorLevel, "S"))
		{
		DashNetId := ""
		try DashNetId := Dash["NetList"].GetText(Info, 12)
		if (DashNetId != NetSel)
			{
			;(kept by its PC: a bot started again has a new id)
			NetSelPc := ""
			if (DashNetId != "")
				try NetSelPc := Dash["NetList"].GetText(Info, 1)
			NetSel := DashNetId, NetLogAt := 0, NetSnapAt := "", NetRefresh := 1
			Dash["NetLog"].Value := ""
			Dash["NetPic"].Visible := false
			Dash["NetPicNote"].Text := NetSel = "" ? "This PC - its log is the Bot tab's." : "Fetching its log and game..."
			}
		}
	return
}
;##############################################
;(v1: the labels DashNetOn, DashNetOff, DashNetPfm and DashNetRestart over one body - A_ThisLabel picked the
;command: DashNetCommand, given the label's name)
DashNetOn(A_GuiEvent:="", A_GuiControl:="", Info:="", *) { ; (v1: a label - its code ran in the global scope)
	global
	DashNetCommand(A_ThisFunc)
	return
}
;##############################################
DashNetOff(A_GuiEvent:="", A_GuiControl:="", Info:="", *) { ; (v1: a label - its code ran in the global scope)
	global
	DashNetCommand(A_ThisFunc)
	return
}
;##############################################
DashNetPfm(A_GuiEvent:="", A_GuiControl:="", Info:="", *) { ; (v1: a label - its code ran in the global scope)
	global
	DashNetCommand(A_ThisFunc)
	return
}
;##############################################
DashNetRestart(A_GuiEvent:="", A_GuiControl:="", Info:="", *) { ; (v1: a label - its code ran in the global scope)
	global
	DashNetCommand(A_ThisFunc)
	return
}
;##############################################
DashNetCommand(label)
	{
	global DashNetCmd, NetLogAt ; (v1 globals it sets)
	DashNetCmd := V1Obj({DashNetOn: "on", DashNetOff: "off", DashNetPfm: "pfmoff", DashNetRestart: "restart"})[label]
	DashSet("NetStatus", "Network: " NetSend(DashNetCmd))
	NetLogAt := A_TickCount - 4000
	}
;##############################################
DashNetRefresh(A_GuiEvent:="", A_GuiControl:="", Info:="", *) { ; (v1: a label - its code ran in the global scope)
	global
	NetRefresh := 1
	return
}
;##############################################
DashLogColorsBtn(A_GuiEvent:="", A_GuiControl:="", Info:="", *) { ; (v1: a label - its code ran in the global scope)
	global
	DashLogColorsWindow()
	return
}
;##############################################
DashLogColorPick(A_GuiEvent:="", A_GuiControl:="", Info:="", *) { ; (v1: a label - its code ran in the global scope)
	global
	A_GuiControl := V1GuiName(A_GuiControl)  ; (v1: the control's v-name, else its text)
	lcI := RegExReplace(A_GuiControl, "\D")
	lcKinds := DashLogKinds(), lcK := lcKinds[Integer(lcI)], lcCols := DashLogColors()
	lcNew := DashPickColour(lcCols[lcK[1]], LogColHwnd)
	if (lcNew != "")
		{
		V1Do(IniWrite, lcNew, A_ScriptDir "\dashboard.ini", "logcolors", lcK[1])
		DashLogColors(true)
		;(v1: GuiControl on a window or control that isn't there did nothing)
		try LogCol["LogColSw" lcI].Opt("+Background" lcNew)
		DashLogRecolour()
		}
	return
}
;##############################################
DashLogColorReset(A_GuiEvent:="", A_GuiControl:="", Info:="", *) { ; (v1: a label - its code ran in the global scope)
	global
	V1Do(IniDelete, A_ScriptDir "\dashboard.ini", "logcolors")
	lcCols := DashLogColors(true), lcKinds := DashLogKinds()
	for lcI, lcK in lcKinds
		{
		lcCol := lcCols[lcK[1]]
		;(v1: GuiControl on a window or control that isn't there did nothing)
		try LogCol["LogColSw" lcI].Opt("+Background" lcCol)
		}
	DashLogRecolour()
	return
}
;##############################################
;(v1: DashLogColorClose, LogColGuiClose and LogColGuiEscape over one body)
DashLogColorClose(A_GuiEvent:="", A_GuiControl:="", Info:="", *) { ; (v1: a label - its code ran in the global scope)
	global
	LogColGuiEscape()
}
;##############################################
LogColGuiClose(*) { ; (v1: a label - its code ran in the global scope)
	global
	LogColGuiEscape()
}
;##############################################
LogColGuiEscape(*) { ; (v1: a label - its code ran in the global scope)
	global
	Try LogCol.Destroy()
	return
}
;##############################################
DashOpenLog(A_GuiEvent:="", A_GuiControl:="", Info:="", *) { ; (v1: a label - its code ran in the global scope)
	global
	Run("notepad.exe `"" A_ScriptDir "\debug.log`"")
	return
}
;##############################################
DashWalkToggle(A_GuiEvent:="", A_GuiControl:="", Info:="", *) { ; (v1: a label - its code ran in the global scope)
	global
	if (V1IsFunc("WalkToggle"))
		WalkToggle.Call()
	;(the Bot menu's tick at once - F8 and the rest: DashRefresh's look every second)
	DashMenuTicks()
	return
}
;##############################################
DashFolder(A_GuiEvent:="", A_GuiControl:="", Info:="", *) { ; (v1: a label - its code ran in the global scope)
	global
	Run(A_ScriptDir)
	return
}
;##############################################
DashUpdButton(A_GuiEvent:="", A_GuiControl:="", Info:="", *) { ; (v1: a label - its code ran in the global scope)
	global
	;Help > Check for updates, and the menu bar's "Update to vX" while a newer version is out: the usual check - a newer
	;version offered (its notes), installed if you say so, the bot then started again as it is now - or "you're up to
	;date" (UpdCheckNow, as the tray menu's Check for updates). "Checking..." and greyed for 10 s (DashMenuTicks)
	if (UpdCheckNow())
		{
		DashUpdBusy := A_TickCount
		DashMenuTicks()
		DashRefresh()
		}
	return
}
;##############################################
DashBugButton(A_GuiEvent:="", A_GuiControl:="", Info:="", *) { ; (v1: a label - its code ran in the global scope)
	global
	if (V1IsFunc("BugShow"))
		BugShow.Call()
	return
}
;##############################################
DashSettingsButton(A_GuiEvent:="", A_GuiControl:="", Info:="", *) { ; (v1: a label - its code ran in the global scope)
	global
	if (V1IsFunc("CfgShow"))
		CfgShow.Call()
	return
}
;##############################################
DashLearnAll(A_GuiEvent:="", A_GuiControl:="", Info:="", *) { ; (v1: a label - its code ran in the global scope)
	global
	if (V1IsFunc("LearnAllToggle"))
		LearnAllToggle.Call()
	return
}
;##############################################
DashBotToggle(A_GuiEvent:="", A_GuiControl:="", Info:="", *) { ; (v1: a label - its code ran in the global scope)
	global
	if (V1IsFunc("BotToggle"))
		BotToggle.Call()
	return
}
;##############################################
DashViewToggle(A_GuiEvent:="", A_GuiControl:="", Info:="", *) { ; (v1: a label - its code ran in the global scope)
	global
	DashSavePlace()
	DashSimple := !DashSimple
	V1Do(IniWrite, DashSimple ? 1 : 0, A_ScriptDir "\dashboard.ini", "view", "dashboard")
	DashApplyView()
	DashShow()
	return
}
;##############################################
DashFrontToggle(A_GuiEvent:="", A_GuiControl:="", Info:="", *) { ; (v1: a label - its code ran in the global scope)
	global
	if (V1IsFunc("GameFrontToggle"))
		GameFrontToggle.Call()
	return
}
;##############################################
DashPlayToggle(A_GuiEvent:="", A_GuiControl:="", Info:="", *) { ; (v1: a label - its code ran in the global scope)
	global
	if (V1IsFunc("PlayForMeToggle"))
		PlayForMeToggle.Call()
	return
}
;##############################################
DashHandsToggle(A_GuiEvent:="", A_GuiControl:="", Info:="", *) { ; (v1: a label - its code ran in the global scope)
	global
	if (V1IsFunc("HandsOffToggle"))
		HandsOffToggle.Call()
	return
}
;##############################################
DashGuiClose(*) { ; (v1: a label - its code ran in the global scope)
	global
	local v1Keep := V1Thread() ; (v1: each thread had its own ErrorLevel)
	;(Settings: traybot - "Put the bot's window in the tray": the X puts it there and the bot plays on - DashToTray.
	;True: v2 doesn't hide it once more itself)
	if (V1IsFunc("TrayBotOn") && TrayBotOn.Call())
		{
		DashToTray("its X")
		return true
		}
	DebugLog("Dashboard closed - the bot stops")
	ExitApp()
}
;##############################################
;(v1: A_EventInfo 1 - minimized; v2's MinMax -1)
DashGuiSize(thisGui:="", MinMax:="", A_GuiWidth:="", A_GuiHeight:="") { ; (v1: a label - its code ran in the global scope)
	global
	if (MinMax = -1)
		{
		;(Settings: traybot - minimized: into the tray instead, the bot plays on - DashToTray)
		if (V1IsFunc("TrayBotOn") && TrayBotOn.Call())
			DashToTray("its minimize button")
		return
		}
	;(GuiControl Move places a tab's controls from the tabs' inside, not the window's: where that starts, measured
	;once the window's up - a Bot tab control, the LOG heading, moved to 0,0 there and where it lands read, then put
	;back where it was made: x12 y286)
	if (DashTabOX = "")
		{
		Dash["DashLogHead"].Move(0, 0)
		Dash["DashLogHead"].GetPos(&DashTabOX, &DashTabOY, &DashTabOW, &DashTabOH)
		Dash["DashLogHead"].Move(12 - DashTabOX, 286 - DashTabOY)
		}
	;(the heading's status line up to the bot's button at the row's right end - both outside the tabs)
	Dash["DashHead"].Move(, , A_GuiWidth - 162)
	Dash["DashBotBtn"].Move(A_GuiWidth - 144)
	Dash["DashPlayBg"].Move(A_GuiWidth - 116)
	Dash["DashPlayBtn"].Move(A_GuiWidth - 116)
	Dash["DashSeeText"].Move(, , A_GuiWidth - 384)
	;(the log down to the window's bottom)
	Dash["DashConsole"].Move(, , A_GuiWidth - 24, Max(40, A_GuiHeight - 316))
	;(the Cards tab: the Learn button at the right end of the hand's row, its heading up to it; the enemies' list takes
	;what's left)
	Dash["DashLearnBtn"].Move(A_GuiWidth - 138 - DashTabOX)
	Dash["DashHandHead"].Move(, , A_GuiWidth - 154)
	Dash["DashFoeHead"].Move(, , A_GuiWidth - 24)
	Dash["DashFoeList"].Move(, , A_GuiWidth - 24, Max(40, A_GuiHeight - 290))
	;(a deck's view: its settings list takes what's left, the value's row under it; the right end's buttons at the right
	;end - the window can be narrower than they were placed for)
	Dash["DeckFDmg"].Move(, , A_GuiWidth - 24)
	Dash["DeckFList"].Move(, , A_GuiWidth - 24, Max(60, A_GuiHeight - 330))
	DashDeckRowY := Max(236 + 60 + 6, A_GuiHeight - 88) - DashTabOY
	Dash["DeckFValT"].Move(, DashDeckRowY + 4)
	Dash["DeckFVal"].Move(, DashDeckRowY + 1)
	Dash["DeckFValSet"].Move(, DashDeckRowY)
	Dash["DeckFValClear"].Move(, DashDeckRowY)
	Dash["DeckFNote"].Move(, DashDeckRowY + 4, Max(120, A_GuiWidth - 454))
	Dash["DeckAddBtn"].Move(A_GuiWidth - 80 - DashTabOX)
	Dash["DeckFSave"].Move(A_GuiWidth - 304 - DashTabOX)
	Dash["DeckGameBtn"].Move(A_GuiWidth - 404 - DashTabOX)
	Dash["DeckFCopy"].Move(A_GuiWidth - 208 - DashTabOX)
	Dash["DeckFDel"].Move(A_GuiWidth - 112 - DashTabOX)
	Dash["DeckFPriT"].Move(A_GuiWidth - 154 - DashTabOX)
	Dash["DeckFPri"].Move(A_GuiWidth - 104 - DashTabOX)
	Dash["DeckFSetN"].Move(, , Max(80, A_GuiWidth - 544))
	Dash["DgDeck"].Move(, , Min(260, Max(100, A_GuiWidth - 594)))
	;(the Network tab: the list across, the log under it on the left, the game's picture on the right)
	Dash["NetHelp"].Move(, , A_GuiWidth - 24)
	Dash["NetStatus"].Move(, , A_GuiWidth - 24)
	Dash["NetList"].Move(, , A_GuiWidth - 24)
	Dash["NetLog"].Move(, , Max(200, A_GuiWidth - 404), Max(40, A_GuiHeight - 360))
	Dash["NetPic"].Move(A_GuiWidth - 384 - DashTabOX)
	Dash["NetPicNote"].Move(A_GuiWidth - 384 - DashTabOX)
	;(the tabs fill the window under the heading; the Dungeons tab's list takes what's left)
	Dash["DashTabs"].Move(, , A_GuiWidth - 12, A_GuiHeight - 42)
	Dash["DgHelp"].Move(, , A_GuiWidth - 24)
	Dash["DgStatus"].Move(, , A_GuiWidth - 24)
	Dash["DgList"].Move(, , A_GuiWidth - 24, Max(40, A_GuiHeight - 298))
	;(the Keys tab: its list takes what's left)
	Dash["KeyHelp"].Move(, , A_GuiWidth - 24)
	Dash["KeyStatus"].Move(, , A_GuiWidth - 24)
	Dash["KeyList"].Move(, , A_GuiWidth - 24, Max(60, A_GuiHeight - 202))
	;(the Spells tab: its list takes what's left of the picture on its right)
	Dash["SpHelp"].Move(, , A_GuiWidth - 24)
	Dash["SpStatus"].Move(, , A_GuiWidth - 24)
	Dash["SpList"].Move(, , A_GuiWidth - 172, Max(40, A_GuiHeight - 202))
	Dash["SpPreview"].Move(A_GuiWidth - 152 - DashTabOX)
	Dash["SpPreviewTxt"].Move(A_GuiWidth - 152 - DashTabOX, , , Max(40, A_GuiHeight - 440))
	return
}

;(Windows+2 is in Autofarmer.ahk: it shows the dev-mode info box in dev mode)

;(v2 port, CONVENTIONS.md "Blank start": v1 started every variable blank; v2 leaves it unset and throws on
;reading it. The entry script calls this first thing: this file's globals start blank, as in v1)
DashboardBlank()
	{
	global DashHwnd := "", DashCon := "", DashShown := "", DashPaused := "", DashHeld := "", DashStart := "", DashN := "", DashCasts := ""
	global DashSees := "", DashNames := "", DashHead := "", DashStatText := "", DashSeeText := "", DashConsole := ""
	global DashUsageText := "", DashSimple := "", DashLogHead := "", DashMenus := ""
	global LogColHwnd := "", DashUpdBusy := "", DashPlayBtn := "", DashPlayBg := ""
	global DashTabOX := "", DashTabOY := "", DashTabOW := "", DashTabOH := ""
	global DashBotBtn := "", DashFoeHead := "", DashFoeList := "", DashLearnBtn := "", DashHandHead := "", DashCardPic1 := ""
	global DashCardPic2 := "", DashCardPic3 := "", DashCardPic4 := "", DashCardPic5 := "", DashCardPic6 := "", DashCardPic7 := "", DashCardTxt1 := ""
	global DashCardTxt2 := "", DashCardTxt3 := "", DashCardTxt4 := "", DashCardTxt5 := "", DashCardTxt6 := "", DashCardTxt7 := ""
	global DashMapHwnd := "", DashMapPic := "", DashMapPicH := "", DashMapText := "", DashMapShown := "", DashMapReq := "", DashMapKind := ""
	global DashMapReqAt := "", DashMapAt := "", DashMapW := "", DashMapH := "", DashMapFile := "", DashMapNote := "", DashMapNav := ""
	global DashMapPicAt := "", NetSel := ""
	}
