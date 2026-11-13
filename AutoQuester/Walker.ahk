; Walker.ahk - walks the wizard towards the current quest goal by following the yellow quest arrow,
; one step per WalkStep() call. AHK v1.1, functions only. Shared by AutoQuester.ahk (walking only)
; and AutoFarmer\Autofarmer.ahk (battles and walking in one loop), so walking fixes go here.
;
; Needs, from the script that includes it: the super-globals GameLeft, GameTop, GameW, GameH (the
; game's client area, kept up to date by its UpdateGameRect()), GameExe and GameClass, and an
; #Include of ArrowReader.ahk. Call WalkerInit() once at start.
;
; In AutoFarmer the game's memory is a better source for the same decisions (NavRead in Vision.ahk: the
; vision helper reads where the wizard is and where the quest arrow points - READ-ONLY, navmem in
; PlayerStats.txt): its heading once it has agreed with the arrow's, its distance instead of the OCR'd
; number, steering on while scenery hides the arrow, and turns measured as they go. Whenever it can't be
; used the arrow on screen decides, as before. See "The game's memory" near the bottom.

global ArriveDist, TurnRate, AheadAngle, TurnInPlace, StuckTime, UnstickTries, UnreadLimit, MinMatch
;Turning walking on (smoother): the most it turns walking by the game's memory when the helper says the arc's clear of
;walls, the most with nothing said about it, the "just walk" band by memory; the wizard's turning circle (game units,
;learned from its walking speed: WkWalkSpeed, game units per ms at 1x); when W last came up; the once-a-minute counts
global SpotTurnMem, ArcBlind, AheadMem, TurnRadius, WkWalkSpeed, WkWUpAt, WkMet, WkMetAt
;(the last walking-speed readings the turning circle's worked out from - at 1x only)
global WkWalkSamples
;Arriving at the closest approach: the nearest the game's memory had it to this goal, and the goal that's for
global WkPassMin, WkPassKey, WkPassAt
;The "Press X ..." prompt's verb last read ("Talk", "Collect", "Interact", "Use"... - "" none)
global WkPromptVerb
;When a window's close button was last looked for (WalkCloseWindow)
global WkCloseLook
;"Play for me" (AutoFarmer's button - green while on -, off at every start): every check for you off - UserIdle
global PlayForMe
;Going to and fro (WalkFroNote): the last big turns ([{at, x, y, d}]), the course held till then, the holds this minute, the
;third hold in a minute just made (1: taken as stuck in that same step - WalkStep - not after a turn that puts the watch off)
global WkFroTurns, WkFroUntil, WkFroHolds, WkFroStuck
global NearDist, TalkMax, TalkGap, PushTime, PushStraightDist, PushStraightTime, BackupTime, UnstickTurn, UnstickBias, BiasTime
global HiddenWalkTime, PushHiddenTime, LoadSpaceWait, LoadSpaceMax, GateDist, GateWait, SigilWait
global FastStuckTime, StillFrac, MemNear, MemAhead, TurnSettle, TransportWait, WkAcceptLook
;Cheat Engine's speedhack (AutoFarmer's speedhack setting): the game's speed now (1 = normal - the walker's timings are
;divided by it), when the bot last pressed one of its keys, normal speed held till (getting round an obstacle), and
;how near the goal it goes back to normal (the arrow's number / game units; the way out of this zone's, game units)
global SpeedNow, SpeedSentAt, WkSpeedHold, SpeedSlowDist, SpeedSlowUnits, SpeedExitUnits
;Why the speedhack's off for this run ("" on - the game was seen not sped up: Cheat Engine not attached, the key not
;taking), and how many turns in a row looked wrong (NavTurn)
global SpeedOff, SpeedMiss
;A quest offer's Accept: when a dialogue was last Spaced through (its offer may follow), the looks since, the clicks
;on this offer and when the first was
global WkDlgEndAt, WkAcceptLooks, WkAcceptClicks, WkAcceptAt
global WkGoalZones, WkKnownZones, WkZonesFile, WkPromptDest, WkTransUsed, WkTransSeen, WkTransStep, WkTransStepAt, WkWaitWhat
global WkPromptUsed, WkZoneFrom, WkZoneAt, WkPressAt, DialogQuiet, WkQuietUntil, WkQuietLogged
;A loading screen per the game's log: a zone transfer under way (WkLoading), when the last one finished
global WkLoading, WkLoadedAt, SkipGap, WkDlgLook
global CollectWait, RoamRadius, ChaseTime, CollectMax
;Telling you when it needs you (WalkNotify): settings; the notice up now ("" none: its kind, title, window,
;shown now, OK'd - not shown again till it's sorted); how long without an arrow / waiting at a goal; the
;last X of the bot's and its one Escape; the last distance read; on top of the goal / stuck by it
global NoArrowNotify, WaitNotify, CollectStall, OnTopDist
;Badly stuck: teleport to the Commons and start over (WalkCommonsReset) - settings; when it last did; the
;watch on getting closer to the goal (best distance, since when, the last step it looked)
global ResetTeleport, ResetEvery, StuckForever, WkResetAt, WkProgBest, WkProgAt, WkProgStep
global WkNoteKind, WkNoteTitle, WkNoteHwnd, WkNoteShown, WkNoteOff, WkNoArrowFrom, WkWaitFrom, WkLastX, WkEscTried
;(no arrow and the game's memory not standing in for it either: since when - the "No quest arrow" notice)
global WkNoGuideFrom
global WkLastDist, WkLastDistAt, WkOnTop, WkOnTopAt, WkOnTopBacked, WkOnTopDone, WkStuckNearDone, WkStuckTalk, WkTalkAt
global WkCollect, WkGoalReadAt, WkArr1At, WkFoesAt, WkChaseFrom, WkChaseSkipUntil, WkRoamLeg, WkRoamLegAt, WkRoamSide
global Walking, HeldW, KeysDown, Refocus, StatusText, StatusKind, StatusPrefix
;(when the arrow was last looked for to bring the game to the front - AutoFarmer's gamefront)
global WkFrontLook
global WkBestDist, WkBestTime, WkLastRead, WkSide, WkTries, WkNear, WkFar, WkArrived, WkTalk, WkPushUntil
global WkSeenAt, WkHidden, WkHiddenAt, WkBias, WkBiasUntil, WkPrevMovedH, WkLastBoxOff, WkLastMode, WkBackups, WkBackupsFrom
global WkDialog, WkPushes, WkPushStart, WkStraight, WkStraightAt
global WkTalkDist, WkArrDist, WkLoadAt, WkSpaceAt, WkGoneSpaces
global WkGateAt, WkGateClicks, WkGateX, WkGateLook, WkSigilUntil, WkFarAt, WkSigilSeen
;Sigils: the zones entered through one ({zone: 1} - coming out of those puts you on their sigil), when X was last
;pressed at one, its prompt's key and the zone it was in, the tries at each ({key: [ticks]}; "zone:" and a dungeon's zone: the times
;back into it just out of it - WalkSigilGo)
global WkSigilZones, WkSigilAt, WkSigilKey, WkSigilFromZone, WkSigilTries
;(v2-only globals - the port tools don't know them: set in WalkerInit, blank in WalkerBlank)
;A sigil that doesn't start (2026-10-26 21:44: one never started after a relog, and was X'd again and again): each sigil X'd at, by
;its spot - the zone and where the wizard stood by the game's memory, within 400 units; no memory: the zone - not the prompt's OCR'd
;letters, which differ read to read ([{zone, x, y, fails, failAt, resetAt, gaveUp, xs}]: the X presses in a row its dungeon didn't
;load from, when the last was, when it was last left and come back to - WalkSigilReset -, when it was given up on - its notice -, the
;X presses at it [ticks]); when X was pressed for the wait under way (its loading screen looked for from then - WkSigilAt is
;cleared by WalkZone once the zone changes, this isn't); that X the quest's way (1 - StartTalk's at the goal, WalkSigilGo's with the
;arrow leading there or back into the goal's dungeon) or a sigil only walked past (0: one that won't start is never left or given up
;on - X at it 3 times in 10 minutes at most, walking on as before)
global WkSigilSpots, WkSigilXAt, WkSigilGoal
;(settings - WalkerInit: the X presses in a row that didn't start it before it's left, the fewer within SigilRelogMs of a relog, the
;leaving at most once in SigilResetEvery at a spot)
global SigilFails, SigilFailsRelog, SigilRelogMs, SigilResetEvery
;Stuck, counted and timed (TODO goal 2 "Measure it": the "badly stuck #N" and "stuck over - N s lost" lines the dashboard's
;STATISTICS and vision\stuckreport.py count - WalkLostOpen ...): the episode under way (when it began, 0 none), the time lost in it so
;far (ms: the gaps between steps of LostGap or less while walking - or with a "stuck" notice up, waiting for you -, battles left out),
;when that was last added to, its kind (obstacle, nocloser, teleport, commons, sigil, notice) and why, the unstick tries in it, badly
;stuck said for it (1); where it began - the distance to the goal and the route's way left (arrow units, "" not known), the zone, the
;quest goal's id: clearly closer than that, another zone or another goal ends it; the time lost up to its last unstick try (ms); when
;the last one ended (0 none - StuckForever's minutes aren't counted twice); the badly-stuck count this run (the #N)
global WkLostOn, WkLostMs, WkLostAt, WkLostKind, WkLostWhy, WkLostTries, WkLostBad, WkLostDist, WkLostLeft, WkLostZone, WkLostGoal
global WkLostTryMs, WkLostEndAt, WkBadN, LostGap
global WkSnapPrev, WkSnapAt, WkTurnAt, WkWalkFrom, WkStill, WkMotion, WkMem, WkMemFile, WkEsc
;Walking on by the game's memory (the stuck watch - WalkMoveTrack): settings; its place reading by reading over the last
;StuckTime ([{at, x, y, yaw, f}] - f: the units from the reading before the way it faces), their zone ("" none); when it last
;walked on (0 not since the watch started over), whether the last reading did, when its place was last read (0 not since)
global MovingStuckTime, MoveFrac, WkMoveLog, WkMoveZone, WkMovedAt, WkMoveNow, WkMoveSeen
;Turns made on the spot in a row with no walking between (a route point jumping behind the wizard): after 3 the next
;one's made walking on, so it never just spins
global WkSpins
;When the last small turn on the spot (70 degrees or less) ended - WkTurnAt then ("" walked since, or a bigger one): the
;camera's wait after it is walked through (not after a back-up or another turn since - WkTurnAt moved on)
global WkSpotTurn
;AutoFarmer's "a battle is on" flag (blank in AutoQuester on its own): never talk or push on during a battle
global inbattle
;The game's memory (AutoFarmer's NavRead, read-only; AutoQuester on its own has none): settings; this step's
;reading - usable, its heading in use, the heading (degrees, + = right, like ReadArrow's), the distance in the
;arrow's own units ("" until known), zone changes to go, the reading itself; its heading's sign (the game's
;world could be either way round) and whether it's trusted yet (readings that agree with the arrow / are its
;mirror image / match neither); the arrow's distance per game unit (the readings it's from; readings far off
;it in a row); on or off (logged when that changes); the
;last position (how fast it's moving); closed-loop turns so far, the last odd one logged; the file it's kept
;in, and the sign saved there; why the last NavRead got nothing (Vision.ahk)
global NavTurnTol, NavTurnCap, NavAgreeNeed
global WkNavOk, WkNavUse, WkNavH, WkNavD, WkNavHops, WkNavObj, WkNavSign, WkNavTrusted, WkNavAgree, WkNavMirror, WkNavOdd
;(the goal zones away: the rest of the way past this zone's leg as the arrow's number last had it - arrow units - and the
;zone, goal and zone changes it's for: on top of the memory's leg when it stands in for the number)
global WkNavRest, WkNavRestKey
;Where the route's aim lies from the quest's target (degrees, + = right; "" no route): both from the memory's positions,
;its facing cancelling out - added to the arrow on screen while the memory's facing isn't steered by (WkNavByArrow: this
;step did)
global WkNavRel, WkNavByArrow
;When the last reading said the wizard was in a mob's reach (escape) - carried over a missed reading for 1.5 s; where
;the last back-out of one started and how many in a row hardly moved
global WkNavEscAt, WkBackOutX, WkBackOutY, WkBackOutStill
;Since when the bare arrow's straight way has had a mob's reach or sight on it with no route to keep to (0 not) - waited
;for 20 s at most; a back-up left out for one behind: when it was last said
global WkBlindAt, WkBlindBackSaid, WkBlindMob
global WkNavScale, WkNavScales, WkNavScaleBad, WkNavState, WkNavPrev, WkNavTurns, WkNavTurnLog, WkNavFile, WkNavSignSaved, NavWhy
;Its heading's sign checked (by the arrow agreeing, or a turn - kept in the file); the arrow's distance per game
;unit for each zone it's been worked out in, the zone the readings so far are from, and the middle of all the
;zones' (for a zone not worked out yet); the memory standing in for an arrow it can't see (since when)
global WkNavChecked, WkNavZScales, WkNavScaleZone, WkNavScaleAll, WkStandIn
;The route round walls over the zone's map (the vision helper plans it, vision\navroute.py): on or off (the
;setting); steering along it this step; how far is left along it (arrow units); the least left so far, for
;"is it getting anywhere" and for the badly-stuck watch; on or off (logged when that changes)
global NavRoute, WkNavRouted, WkNavLeft, WkRouteBest, WkRouteProg, WkRouteState
;(arrival and walking straight through a doorway by the game's memory, in game units: see the settings)
global ArriveUnits, PushUnits
;(X pressed at a prompt: what it opened looked at already; the quest's goal line as last read, and when; where the last
;WalkGoalText got it from: "the game" - its memory, AutoFarmer's NavGoal -, "the screen" - the OCR -, "" nowhere)
global WkAfterXLooked, WkGoalLine, WkGoalLineAt, WkGoalFrom
;When each prompt's NPC was last looked at for a quest marker (WalkQuestMarker: {name letters: tick})
global WkQmLooked
;When each NPC was last talked to for its quest marker - once per 5 minutes ({name letters: tick})
global WkQmTalked
;(prompts walked past - not the quest's - logged, when: apart from WkPromptUsed, which says what X was pressed at;
;what was on screen just before X, for what X opened: WalkCloseAfterX)
global WkPromptSkip, WkPreXText
;A teleport on the game's path, right at it (the helper's route stops there): the seconds waited there ("" not
;at one), where it is ("x,y"); the one walked on into already; no way on but teleports that don't take the wizard
global WkNavJump, WkNavJumpAt, WkJumpKey, WkJumpStuck, WkJumpPushUntil
;A mob on the way that the helper's route can't go round (mobavoid): the seconds waited for it to move off ("" none),
;its name; the one last logged
global WkNavMob, WkNavMobName, WkMobLogged, WkNavMobAt
;(when the arrow itself was last on screen; whether it was right before X was pressed at a prompt)
global WkRealSeenAt, WkArrowAtX
;(an arrow read as the memory's mirror image, its sign checked: when that was last logged)
global WkNavMirrorSaid
;(pushing into the way out of the zone without an X first: if it doesn't load, X after all - a World Gate)
global WkNavDoor
;Near the goal by the game's memory, in game units (WalkGoalNear - the goal in this zone): the last bit walked closed loop
;(WalkApproach) from this close; a talk goal's NPC stopped this far off, its prompt taken as the quest's this close; the
;approach's tries at this goal, and the route followed instead till (tick)
global ApproachUnits, TalkUnits, TalkReach, WkApTries, WkApOffUntil
;The quest's goal from the game's memory (NavGoal, kept by WalkGoalText): its kind (PERSONA - talk to...), the NPC it names
;and its id; X at a talk goal's NPC ([{at, id}] - 3 in 2 minutes per goal); the goal id at the last X of a talk, at an
;arrival wait, last seen (a new one ends the no-X time after a dialogue), and the one the "talking didn't work" notice was for
global WkGoalType, WkGoalNpc, WkGoalId, WkTalkXs, WkTalkGoal, WkArrGoal, WkGoalIdWas, WkTalkNoted
;(...and the thing it names, its count and total, and the game's own keys for the thing, the mob and the NPC's first and last
;name - a newer helper's; "" an older one's. All cleared when the goal isn't read: a kind of before is stale - WalkGoalKind)
global WkGoalItem, WkGoalCount, WkGoalTotal, WkGoalItemKey, WkGoalMobKey, WkGoalNpcFirst, WkGoalNpcLast
;...and the quest's title (NavGoal's quest - the game's memory): the notices' link to its Wizard101 Central page (WalkWikiUrl)
;(v2-only - not known to the port tools: set in WalkerInit and WalkGoalText; WalkerBlank doesn't have it)
global WkGoalQuest
;A goal the game shows no way to (the game's memory, a newer helper: noplace 1 held 2 s, two readings running with the same
;goal id - 2026-10-25 "Use Inactive Protector"): the arrow on screen is a phantom then (shadow matches 0.62-0.78, its heading
;flipping 180 standing still) - not followed, not arrived at: the goal's kind's own way instead. The readings in a row and
;their goal id, when the last was; the last reading taken, usable or not; a talk goal's NPC found by name standing in for
;the place the game has none for ({goalid, x, y, z, name} - Collect.ahk TalkStep: the talk logic works on it)
global WkNavNoPlace, WkNpN, WkNpGoal, WkNpAt, WkNavLast, WkNpTarget
;Waiting at a goal (WkArrived = 1): its id and count by the game's memory when the wait began ("" not yet looked), the last
;look; the prompt panel's text as InteractPrompt last read it (Crowns on it: never an X)
global WkArr1Key, WkArr1Look, WkPromptText

;Settings and starting state. Returns false if the arrow shapes (resources\arrow_refs.txt) are missing
WalkerInit(prefix := "AutoQuester")
	{
	global WkGoalQuest ; (v2-only: the port tools don't know it)
	global ArriveDist, ArriveUnits, PushUnits, ApproachUnits, TalkUnits, TalkReach, TurnRate, TurnSettle, AheadAngle, AheadMem ; (v1 globals it sets)
	global SpotTurnMem, ArcBlind, TurnRadius, TurnInPlace, StuckTime, UnstickTries, UnreadLimit, MinMatch, NearDist, TalkMax ; (v1 globals it sets)
	global TalkGap, PushTime, PushStraightDist, PushStraightTime, BackupTime, UnstickTurn, UnstickBias, BiasTime ; (v1 globals it sets)
	global HiddenWalkTime, PushHiddenTime, LoadSpaceWait, LoadSpaceMax, GateDist, GateWait, SigilWait, SkipGap, DialogQuiet ; (v1 globals it sets)
	global TransportWait, FastStuckTime, StillFrac, MovingStuckTime, MoveFrac, MemNear, MemAhead, CollectWait, RoamRadius ; (v1 globals it sets)
	global ChaseTime, CollectMax, CollectStall, NoArrowNotify, WaitNotify, ResetTeleport, ResetEvery, StuckForever, OnTopDist ; (v1 globals it sets)
	global NavAgreeNeed, NavTurnTol, NavTurnCap, NavRoute, Walking, HeldW, KeysDown, Refocus, WkFarAt, WkTurnAt, WkWalkFrom ; (v1 globals it sets)
	global SpeedNow, SpeedSentAt, WkSpeedHold, SpeedSlowDist, SpeedSlowUnits, SpeedOff, SpeedMiss, SpeedExitUnits, WkTalkXs ; (v1 globals it sets)
	global WkTalkGoal, WkArrGoal, WkGoalIdWas, WkTalkNoted, WkGoalType, WkGoalNpc, WkGoalId, WkGoalItem, WkGoalCount ; (v1 globals it sets)
	global WkGoalTotal, WkGoalItemKey, WkGoalMobKey, WkGoalNpcFirst, WkGoalNpcLast, WkNavNoPlace, WkNpN, WkNpGoal, WkNpAt ; (v1 globals it sets)
	global WkNavLast, WkNpTarget, WkArr1Key, WkArr1Look, WkPromptText, WkGoalZones, WkTransUsed, WkTransSeen, WkTransStep ; (v1 globals it sets)
	global WkTransStepAt, WkWaitWhat, WkPromptUsed, WkZoneFrom, WkZoneAt, WkPressAt, WkQuietUntil, WkQuietLogged, WkSigilZones ; (v1 globals it sets)
	global WkSigilAt, WkSigilKey, WkSigilFromZone, WkSigilTries, WkWalkSpeed, WkWalkSamples, WkWUpAt, WkFrontLook, WkMetAt ; (v1 globals it sets)
	global WkMet, WkPassMin, WkPassKey, WkPromptSkip, WkPreXText, WkQmLooked, WkQmTalked, WkNavJump, WkNavJumpAt, WkJumpKey ; (v1 globals it sets)
	global WkJumpStuck, WkJumpPushUntil, WkNavMob, WkNavMobName, WkMobLogged, WkNavMobAt, WkBlindAt, WkBlindBackSaid ; (v1 globals it sets)
	global WkBlindMob, WkLoading, WkLoadedAt, WkDlgLook, WkCloseLook, WkNavEscAt, WkCollect, WkGoalReadAt, WkAfterXLooked ; (v1 globals it sets)
	global WkGoalLine, WkGoalLineAt, WkRealSeenAt, WkArrowAtX, WkGoalFrom, WkNoteKind, WkNoteTitle, WkNoteHwnd, WkNoteShown ; (v1 globals it sets)
	global WkNoteOff, WkWaitFrom, WkLastX, WkResetAt, WkNavOk, WkNavUse, WkNavH, WkNavD, WkNavHops, WkNavObj, WkNavState ; (v1 globals it sets)
	global WkNavTrusted, WkNavAgree, WkNavMirror, WkNavOdd, WkNavScales, WkNavScaleBad, WkNavPrev, WkNavTurns, WkNavTurnLog ; (v1 globals it sets)
	global WkStandIn, WkNavRest, WkNavRestKey, WkNavRouted, WkNavLeft, WkRouteBest, WkRouteProg, WkRouteState, WkNavMirrorSaid ; (v1 globals it sets)
	global WkMoveLog, WkMoveZone, WkMovedAt, WkMoveNow, WkMoveSeen, WkFroStuck, StatusText, StatusKind, StatusPrefix ; (v1 globals it sets)
	global WkSigilSpots, WkSigilXAt, SigilFails, SigilFailsRelog, SigilRelogMs, SigilResetEvery, WkLostOn, WkLostMs, WkLostAt ; (v2-only: the port tools don't know them)
	global WkLostKind, WkLostWhy, WkLostTries, WkLostBad, WkLostDist, WkLostLeft, WkLostZone, WkLostGoal, WkLostTryMs, WkBadN, LostGap ; (v2-only: the port tools don't know them)
	global WkLostEndAt, WkSigilGoal ; (v2-only: the port tools don't know them)
	;---- Settings ----
	ArriveDist := 15     ;stop when the distance on the arrow is this or less (walks again when a new goal appears)
	ArriveUnits := 150   ;...by the game's memory (when it can be used): this many game units from the goal - the
	                     ;arrow's number means more or less in each zone (15 on it is 120-1500 units), this doesn't
	PushUnits := 250     ;...and the PushStraightDist below, by the game's memory
	ApproachUnits := 1500 ;by the game's memory, the goal in this zone and straight ahead (no wall, no mob): the last this
	                     ;many units walked closed loop - 1x, turned to face it on the spot, W held while its place is read
	                     ;every ~40 ms, let go at it (WalkApproach). A step a second apart walked 900-1800 units over it
	TalkUnits := 300     ;...a talk goal's NPC: stopped this far off, then X (the NPC's in the way closer in)
	TalkReach := 700     ;...a prompt this close to the goal is the goal's (a talk goal's: its NPC's name too)
	TurnRate := 0.15     ;degrees the wizard turns per ms of holding A/D (measured: 22.5 degrees per 150 ms)
	TurnSettle := 500    ;ms the camera takes to catch up after a turn: don't steer on the arrow before then
	AheadAngle := 12     ;arrow within this many degrees of straight ahead: just walk
	AheadMem := 6        ;...steering by the game's memory (it knows the facing at once): this many
	SpotTurnMem := 100   ;by the game's memory on the route: a turn up to this made walking on when the helper says the
	                     ;arc round the wizard's turning circle is clear of the walls (and the aim's outside it)
	ArcBlind := 60       ;...by memory with nothing said about the arc: up to this (its bulge stays inside the walls' margin)
	TurnRadius := 400    ;the wizard's turning circle (game units) till it's worked out from its walking speed at 1x -
	                     ;about 1000 units a second over about 145 degrees a second (measured 2026-10-23, Celestia):
	                     ;a wide one, so till then it's taken as that
	TurnInPlace := 45    ;arrow (or the route) further off than this: stop, turn on the spot, then walk straight on -
	                     ;turning with W held swings the wizard round an arc about 100 units wide, into walls and round
	                     ;NPCs and the goal; under it (and over AheadAngle) the small turn is made walking on
	StuckTime := 4000    ;ms of walking without getting any closer = stuck, try to get around
	UnstickTries := 5    ;give up after this many tries at getting round the same obstacle
	UnreadLimit := 3000  ;ms without a readable distance before it stops and waits
	MinMatch := 0.6      ;how well a yellow shape must match the arrow (real arrows score 0.9-1.0)
	NearDist := 30       ;the number can't be read after it was this or less: next to the goal (lone digits often don't OCR)
	TalkMax := 15        ;at the goal: press X, then Space (up to this many times) while the dialogue is open
	TalkGap := 350       ;ms between Space presses
	PushTime := 8000     ;nobody to talk to: walk on into the goal (doorway, loading point) for up to this long
	PushStraightDist := 6 ;...and once this close, stop steering and walk straight through it
	PushStraightTime := 3000 ;...for at most this long (a loading point triggers well within it)
	BackupTime := 800    ;stuck: back up this long (ms) before turning away
	UnstickTurn := 75    ;stuck: turn this many degrees to one side and walk along the obstacle
	UnstickBias := 40    ;after that, keep aiming this many degrees off the goal on that side...
	BiasTime := 3000     ;...easing back to the goal over this many ms, so it doesn't walk straight back in
	HiddenWalkTime := 1500 ;arrow hidden while walking (an arch, door frame or pillar): keep walking this long before stopping
	PushHiddenTime := 2000 ;...and while pushing into a doorway: keep walking straight on this long (a loading screen also hides it)
	LoadSpaceWait := 4000 ;after a loading screen: no arrow for this long = maybe a dialogue that opened by itself, press Space
	LoadSpaceMax := 40    ;...every 1.5 s, at most this many times
	GateDist := 60       ;a World Gate's prompt shows up with the arrow last this close: the arrow leads there (another world), so use it
	GateWait := 6000     ;ms to wait for the Spiral Map after pressing X at a World Gate
	SigilWait := 30000   ;at a sigil (dungeon entrance, "Press X to Enter"): after X, stand still this long (ms)
	SkipGap := 70        ;a dialogue box showing (NEXT / DONE / MORE): Space every this many ms until it's gone
	DialogQuiet := 20000 ;after a dialogue X opened has closed: no X at any prompt for this long (ms), so it walks
	                     ;away instead of talking to the same NPC again and again
	TransportWait := 15000 ;after using a boat or the like ("BOAT TO GOBBLERTON ... to Use"): stand still this long
	FastStuckTime := 1200 ;...or stuck after this long already if the picture has stopped moving too (W held,
	StillFrac := 0.15     ;   and less than this share of the picture changed between two looks, twice)
	MovingStuckTime := 15000 ;by the game's memory, the wizard walking on all the while (the way it faces, within StuckTime):
	                      ;stuck only once it's this long no closer - going round a wall gets no closer for a while, circling
	                      ;still gets caught. Not walking on by it - pressed on a wall, sliding sideways along one: StuckTime
	MoveFrac := 0.5       ;...walking on: over a second, its place this share of its walking speed (WkWalkSpeed, by SpeedNow)
	                      ;or more the way it faces (the picture still or not)
	MemNear := 15         ;a remembered obstacle: same zone and the distance to the goal within this of it
	MemAhead := 25        ;...and on the way to one (this much further from the goal): keep to the side that worked
	CollectWait := 5000   ;a "collect / defeat N things" goal (the line under the arrow): arrived and nothing changed for this long = collect
	RoamRadius := 70      ;collecting: stay within this distance of where the arrow leads
	ChaseTime := 12000    ;collecting: walk towards a monster's name label at most this long, then look elsewhere
	CollectMax := 900000  ;collecting: give up on a goal after this long (ms) and just wait
	CollectStall := 180000 ;collecting: the count ("2 of 5") hasn't gone up for this long (battles left out):
	                      ;stop, wait there, and show you a notice (Keep trying / Stop walking)
	NoArrowNotify := 45000 ;no quest arrow this long out of battle (no loading screen): a notice for you
	WaitNotify := 180000  ;at a goal, waiting this long for the next one: a notice for you
	ResetTeleport := 1    ;badly stuck (gave up going round an obstacle, or no closer to the goal for StuckForever of
	                      ;walking): teleport to the world's Commons (End) and walk on from there; 0 = just stop
	ResetEvery := 600000  ;...at most once every this long (ms); stuck again sooner: it stops and tells you
	StuckForever := 180000 ;walking (battles, talks, collecting left out) this long without getting closer = badly stuck
	OnTopDist := 20       ;the arrow gone (or stuck) this close to the goal: it's on top of it / the thing itself
	                      ;is in the way - arrived (X), not backing up and turning, not going round it
	LostGap := 8000       ;the time lost while stuck adds up the gaps between steps up to this long (the longest unstick try is
	                      ;about 5 s: its back-up, turn and walk); longer - a battle, a loading screen, the bot off - left out
	;A sigil that doesn't start (X pressed, SigilWait stood, still in the zone it was pressed in with no loading screen since by the
	;game's log - WalkSigilCheck). Guesses till it's seen in the game (2026-10-26 21:44's lines weren't kept) - tune them there:
	SigilFails := 3       ;this many in a row at the same sigil, the quest's way: left and come back to (Settings: sigilhome, off
	                      ;unless switched on - WalkSigilReset), or a notice and walking off; one only walked past: said, walked on
	SigilFailsRelog := 2  ;...this many within SigilRelogMs of a relog (the bot's reconnect or yours - Reconnect.ahk): the 21:44 case
	SigilRelogMs := 1800000
	SigilResetEvery := 1800000 ;...left at most once in this long at a sigil; not starting after that either: the notice, walking off
	;The game's memory (AutoFarmer, navmem:1 in PlayerStats.txt - read-only):
	NavAgreeNeed := 3     ;its heading is steered by once this many readings agree with the arrow on screen
	NavTurnTol := 5       ;a turn holds A / D until the wizard's facing is within this many degrees...
	NavTurnCap := 2500    ;...for at most this long (ms)
	NavRoute := 1         ;steer along the route the vision helper plans round walls over the zone's map (its
	                      ;floor and obstacles); 0 = straight at where the quest arrow points, as before

	Walking := 0, HeldW := 0, KeysDown := 0, Refocus := 0, WkFarAt := 0, WkTurnAt := 0, WkWalkFrom := 0
	;(1x within SpeedSlowUnits of the goal - 1.4 s at 2x; 600 was a third of a second, less than a step: 2026-10-25 2x at 23 by Edith)
	SpeedNow := 1, SpeedSentAt := 0, WkSpeedHold := 0, SpeedSlowDist := 40, SpeedSlowUnits := 2500, SpeedOff := "", SpeedMiss := 0
	;(...the goal zones away - the way out of this one: nothing to overshoot pushing into it, as before)
	SpeedExitUnits := 600
	WkTalkXs := [], WkTalkGoal := "", WkArrGoal := "", WkGoalIdWas := "", WkTalkNoted := "", WkGoalType := "", WkGoalNpc := "", WkGoalId := ""
	WkGoalItem := "", WkGoalCount := "", WkGoalTotal := "", WkGoalItemKey := "", WkGoalMobKey := "", WkGoalNpcFirst := "", WkGoalNpcLast := ""
	WkGoalQuest := ""
	WkNavNoPlace := 0, WkNpN := 0, WkNpGoal := "", WkNpAt := 0, WkNavLast := "", WkNpTarget := "", WkArr1Key := "", WkArr1Look := 0, WkPromptText := ""
	WkGoalZones := [], WkTransUsed := V1Obj(), WkTransSeen := "", WkTransStep := 0, WkTransStepAt := 0, WkWaitWhat := "sigil"
	WkPromptUsed := V1Obj(), WkZoneFrom := "", WkZoneAt := 0, WkPressAt := 0, WkQuietUntil := 0, WkQuietLogged := 0
	WkSigilZones := V1Obj(), WkSigilAt := 0, WkSigilKey := "", WkSigilFromZone := "", WkSigilTries := V1Obj()
	WkSigilSpots := [], WkSigilXAt := 0, WkSigilGoal := 0
	WkLostOn := 0, WkLostMs := 0, WkLostAt := 0, WkLostKind := "", WkLostWhy := "", WkLostTries := 0, WkLostBad := 0
	WkLostDist := "", WkLostLeft := "", WkLostZone := "", WkLostGoal := "", WkLostTryMs := 0, WkLostEndAt := 0, WkBadN := 0
	WkWalkSpeed := "", WkWalkSamples := [], WkWUpAt := 0, WkFrontLook := 0, WkMetAt := A_TickCount
	WkMet := V1Obj({wms: 0, wfrom: 0, stops: 0, spot: 0, walkturns: 0, keys: 0, act: 0, last: 0, mturns: 0})
	WkPassMin := "", WkPassKey := ""
	WkPromptSkip := V1Obj(), WkPreXText := "", WkQmLooked := V1Obj(), WkQmTalked := V1Obj()
	WkNavJump := "", WkNavJumpAt := "", WkJumpKey := "", WkJumpStuck := 0, WkJumpPushUntil := 0
	WkNavMob := "", WkNavMobName := "", WkMobLogged := "", WkNavMobAt := 0, WkBlindAt := 0, WkBlindBackSaid := 0, WkBlindMob := ""
	;(0, not blank: A_TickCount - "" is blank, and blank < 5000 holds - WalkCloseWindow never looked, 2026-10-23 15:02, a
	;potion shop left open held the wizard; blank > 1500 doesn't - the party leader never waited for followers)
	WkLoading := 0, WkLoadedAt := 0, WkDlgLook := 0, WkCloseLook := 0, WkNavEscAt := 0
	WkCollect := "", WkGoalReadAt := 0, WkAfterXLooked := 0, WkGoalLine := "", WkGoalLineAt := 0, WkRealSeenAt := 0, WkArrowAtX := 0
	WkGoalFrom := ""
	WkNoteKind := "", WkNoteTitle := "", WkNoteHwnd := 0, WkNoteShown := 0, WkNoteOff := 0, WkWaitFrom := 0, WkLastX := 0
	WkResetAt := 0
	WkNavOk := 0, WkNavUse := 0, WkNavH := "", WkNavD := "", WkNavHops := "", WkNavObj := "", WkNavState := ""
	WkNavTrusted := 0, WkNavAgree := 0, WkNavMirror := 0, WkNavOdd := 0, WkNavScales := [], WkNavScaleBad := 0
	WkNavPrev := "", WkNavTurns := 0, WkNavTurnLog := 0, WkStandIn := 0, WkNavRest := 0, WkNavRestKey := ""
	WkNavRouted := 0, WkNavLeft := "", WkRouteBest := "", WkRouteProg := "", WkRouteState := "", WkNavMirrorSaid := 0
	WkMoveLog := [], WkMoveZone := "", WkMovedAt := 0, WkMoveNow := 0, WkMoveSeen := 0, WkFroStuck := 0
	WalkNavLoad()
	WalkMemLoad()
	WalkZonesLoad()
	StatusText := "", StatusKind := "", StatusPrefix := prefix
	WalkReset()
	return IsObject(ArrowRefs())
	}

;Forget progress (new goal, or walking switched back on)
WalkReset()
	{
	global WkBestDist, WkBestTime, WkLastRead, WkSide, WkTries, WkNear, WkFar, WkArrived, WkTalk, WkPushUntil, WkDialog ; (v1 globals it sets)
	global WkPushes, WkPushStart, WkStraight, WkStraightAt, WkSpins, WkTalkDist, WkArrDist, WkLoadAt, WkSpaceAt, WkGoneSpaces ; (v1 globals it sets)
	global WkGateAt, WkGateClicks, WkGateX, WkGateLook, WkSigilUntil, WkSigilSeen, WkBackups, WkBackupsFrom, WkSeenAt, WkHidden ; (v1 globals it sets)
	global WkHiddenAt, WkBias, WkBiasUntil, WkPrevMovedH, WkLastBoxOff, WkLastMode, WkSnapPrev, WkSnapAt, WkStill, WkMotion ; (v1 globals it sets)
	global WkEsc, WkArr1At, WkFoesAt, WkChaseFrom, WkChaseSkipUntil, WkRoamLeg, WkRoamLegAt, WkRoamSide, WkNoArrowFrom ; (v1 globals it sets)
	global WkNoGuideFrom, WkEscTried, WkLastDist, WkLastDistAt, WkOnTop, WkOnTopAt, WkOnTopBacked, WkOnTopDone, WkStuckNearDone ; (v1 globals it sets)
	global WkStuckTalk, WkTalkAt, WkProgBest, WkProgAt, WkProgStep, WkNavDoor, WkStandIn, WkRouteBest, WkRouteProg, WkPassMin ; (v1 globals it sets)
	global WkApTries, WkApOffUntil, WkArrGoal, WkGoalLineAt, WkFroStuck ; (v1 globals it sets)
	WkBestDist := "", WkBestTime := A_TickCount, WkLastRead := A_TickCount
	WkSide := 1, WkTries := 0, WkNear := 0, WkFar := 0, WkArrived := 0, WkTalk := 0, WkPushUntil := 0
	WkDialog := 0, WkPushes := 0, WkPushStart := 0, WkStraight := 0, WkStraightAt := 0, WkSpins := 0
	WkTalkDist := "", WkArrDist := "", WkLoadAt := 0, WkSpaceAt := 0, WkGoneSpaces := 0
	WkGateAt := 0, WkGateClicks := 0, WkGateX := 0, WkGateLook := 0, WkSigilUntil := 0, WkSigilSeen := 0
	WkBackups := 0, WkBackupsFrom := 0
	WkSeenAt := 0, WkHidden := 0, WkHiddenAt := 0, WkBias := 0, WkBiasUntil := 0, WkPrevMovedH := "", WkLastBoxOff := 0, WkLastMode := 0
	WkSnapPrev := "", WkSnapAt := 0, WkStill := 0, WkMotion := "", WkEsc := ""
	WkArr1At := 0, WkFoesAt := 0, WkChaseFrom := 0, WkChaseSkipUntil := 0, WkRoamLeg := 0, WkRoamLegAt := 0, WkRoamSide := 1
	WkNoArrowFrom := 0, WkNoGuideFrom := 0, WkEscTried := 0, WkLastDist := "", WkLastDistAt := 0
	WkOnTop := 0, WkOnTopAt := 0, WkOnTopBacked := 0, WkOnTopDone := 0, WkStuckNearDone := 0, WkStuckTalk := 0, WkTalkAt := 0
	WkProgBest := "", WkProgAt := A_TickCount, WkProgStep := A_TickCount
	WkNavDoor := 0, WkStandIn := 0, WkRouteBest := "", WkRouteProg := "", WkPassMin := ""
	WkApTries := 0, WkApOffUntil := 0, WkArrGoal := ""
	;(a new goal: its line is read again)
	WkGoalLineAt := 0
	WalkMoveReset()
	WkFroStuck := 0
	}

;A line in AutoFarmer's debug.log (when the including script has DebugLog), so walker problems leave evidence
WalkLog(text)
	{
	if (V1IsFunc("DebugLog"))
		%"DebugLog"%.Call("Walk: " text)
	}

;One step towards the quest goal: read the arrow, then walk / turn / stop. Call it over and over while
;there's no battle; with no arrow on screen it just lets go of the keys. Takes up to about a second
;(longer while getting round an obstacle). Returns false when walking is off.
;At the goal (WkArrived): 2 = talking (X, then Space to skip the dialogue), 3 = pushing on into it
;(doorway or loading point), 4 = at a World Gate (X, then Go To World on the Spiral Map), 5 = entering
;a sigil (X, then stand still SigilWait), 6 = pressed X at a prompt on the way (Space through what it
;opens), 7 = collecting (a "collect / defeat N things" goal: walk into monsters, roam the area),
;1 = done, waiting for the next goal to show up
WalkStep()
	{
	global Refocus, WkFrontLook, WkBestTime, WkLastRead, WkNoArrowFrom, WkNoGuideFrom, WkWaitFrom, WkGateLook, WkArrived ; (v1 globals it sets)
	global WkPressAt, WkTalk, WkDialog, WkSpaceAt, WkLoadAt, WkSeenAt, WkHidden, WkLastBoxOff, WkLastMode, WkQuietUntil ; (v1 globals it sets)
	global WkGoalIdWas, WkJumpStuck, Walking, WkNavByArrow, WkNavRest, WkNavRestKey, WkRealSeenAt, WkStandIn, WkDlgLook ; (v1 globals it sets)
	global WkLastDist, WkLastDistAt, WkEscTried, WkArr1Key, WkArr1Look, WkAcceptLooks, WkAcceptLook, WkFarAt, WkSigilSeen ; (v1 globals it sets)
	global WkQuietLogged, WkAfterXLooked, WkFar, WkOnTopBacked, WkOnTop, WkHiddenAt, WkGateAt, WkGateClicks, WkGateX ; (v1 globals it sets)
	global WkStuckTalk, WkStraight, WkStraightAt, WkPushes, WkGoneSpaces, WkOnTopDone, WkOnTopAt, WkBackups, WkBackupsFrom ; (v1 globals it sets)
	global WkBestDist, WkRouteBest, WkTries, WkNavDoor, WkArrDist, WkJumpKey, WkMobLogged, WkNavMobAt, WkJumpPushUntil ; (v1 globals it sets)
	global WkArrGoal, WkNear, WkRouteProg, WkProgAt, WkProgStep, WkProgBest, WkEsc, WkBias, WkBiasUntil, WkPrevMovedH, WkSpins ; (v1 globals it sets)
	global WkBackOutStill, WkBackOutX, WkBackOutY, WkSpotTurn, WkBlindAt, WkBlindMob, WkFroStuck, WkStill, WkSnapPrev ; (v1 globals it sets)
	global WkStuckNearDone, WkSide ; (v1 globals it sets)
	;(stood still 1.5 s - the walker's own short stops keep the speed: back to 1x; the minute's line)
	if (!HeldW && SpeedNow > 1 && WkWUpAt && A_TickCount - WkWUpAt > 1500)
		SpeedSet(0, "standing")
	WalkMetrics()
	;(a stuck episode's time lost - also while walking is off with a "stuck" notice up: the wait for you is lost too)
	WalkLostTick()
	;A notice for you: hidden in a battle (it mustn't cover what the battle reads), shown again after - also
	;while walking is off (the "stuck" one)
	if (inbattle && WkNoteShown)
		WalkNoteHide()
	else if (!inbattle && WkNoteKind != "" && !WkNoteShown && !WkNoteOff)
		WalkNoteShow()
	if (!Walking)
		return false
	if (!GameActive())
		{
		if (KeysDown)
			ReleaseKeys(), Refocus := 1
		;(AutoFarmer's "Bring Wizard101 to the front": the quest arrow on screen - something to walk to - and you've left
		;the keyboard and mouse alone a moment: the game in front, walking on)
		;(you've left the PC with another window in front - nothing touched for 5 minutes: the game in front all the same,
		;else it logs you out for inactivity)
		if (V1IsFunc("GameToFront") && UserIdle() > 300000 && A_TickCount - WkFrontLook > 1500)
			{
			WkFrontLook := A_TickCount
			if (%"GameToFront"%.Call("nothing touched for 5 minutes, another window in front", true, true))
				return true
			}
		if (V1IsFunc("GameFrontOn") && %"GameFrontOn"%.Call() && A_TickCount - WkFrontLook > 1500)
			{
			WkFrontLook := A_TickCount
			if (ReadArrow() != "" && %"GameToFront"%.Call("the quest arrow showed"))
				return true
			}
		SetStatus("paused - click into Wizard101 to carry on")
		WkBestTime := A_TickCount, WkLastRead := A_TickCount, WkNoArrowFrom := 0, WkNoGuideFrom := 0, WkWaitFrom := 0
		Sleep(300)
		return true
		}
	if (Refocus)
		ReleaseKeys(), Refocus := 0
	if (inbattle && WkArrived >= 2)
		WalkReset()
	;At a World Gate: the Spiral Map covers the arrow, so no reading it
	if (WkArrived = 4)
		{
		WkNoArrowFrom := 0
		return GateStep()
		}
	;Entering a sigil (X pressed): stand still while it counts down and the dungeon loads, then carry
	;on like after a loading screen. Short steps, so AutoFarmer still notices a battle meanwhile
	if (WkArrived = 5)
		{
		WkNoArrowFrom := 0
		;(in the sigil's dungeon already - another zone since the X and its loading screen over 3 s, by the game's log: on from here,
		;not the rest of SigilWait standing in it, ~20 s a dungeon - WalkSigilIn)
		if (WkWaitWhat = "sigil" && A_TickCount < WkSigilUntil && WalkSigilIn() != "")
			{
			WalkReset()
			WkLoadAt := A_TickCount
			return true
			}
		if (A_TickCount < WkSigilUntil)
			{
			if (KeysDown || HeldW)
				ReleaseKeys()
			;X opened a dialogue instead of a dungeon (e.g. "you spot an access grate..." with Back and
			;Done): Space through it like after any other prompt (WkArrived = 6)
			if (WkWaitWhat = "sigil" && A_TickCount > WkGateLook)
				{
				WkGateLook := A_TickCount + 1000
				if (WalkDialogOpen())
					{
					WalkLog("sigil: X opened a dialogue, not a dungeon - pressing Space through it")
					WkArrived := 6, WkPressAt := A_TickCount, WkTalk := 0, WkDialog := 0, WkSpaceAt := 0
					return true
					}
				}
			SetStatus((WkWaitWhat = "sigil" ? "entering the sigil" : "on the way (" WkWaitWhat ")") " - waiting " Ceil((WkSigilUntil - A_TickCount) / 1000) " s")
			Sleep(300)
			return true
			}
		WalkLog((WkWaitWhat = "sigil" ? "sigil" : "transport") ": waited " Round((WkWaitWhat = "sigil" ? SigilWait : TransportWait) / 1000) " s - walking on")
		;(provably not started - still in its zone, no loading screen since the X by the game's log: counted at its spot; the
		;SigilFails-th in a row there - fewer after a relog - it's left and come back to, or given up on: WalkSigilCheck took over)
		if (WkWaitWhat = "sigil" && WalkSigilCheck())
			return Walking ? true : false
		;(still in the sigil's zone: X didn't take - or its countdown stopped, the wizard moved off: X again when its prompt
		;shows, 3 tries in 10 minutes)
		if (WkWaitWhat = "sigil" && WkSigilKey != "" && WalkZone() = WkSigilFromZone && WalkSigilTriesLeft(WkSigilKey))
			{
			WkPromptUsed.Delete(WkSigilKey)
			WalkLog("sigil: still here - X again when its prompt shows")
			}
		WalkReset()
		WkLoadAt := A_TickCount
		return true
		}
	;Reading the arrow is a lot of per-pixel script work: run it at full speed (AutoFarmer keeps the
	;default speed for everything else, so its loop doesn't hog the CPU)
	;(v2 always runs at full speed - v1 had SetBatchLines -1 around this read)
	h := ReadArrow(&dist, &score)
	if (!Walking)
		return false
	seen := (h != "" && score >= MinMatch)
	;(a goal the game shows no way to by the game's memory - WkNavNoPlace: what's read as the arrow is a phantom - not followed,
	;no distance off it, not arrived at; the goal's kind's own way instead. 2026-10-25 "Use Inactive Protector": heading 153 /
	;-25 in turn standing still, shadow matches 0.62-0.78, a lone "0" - X at nothing, a push, then waiting there for good)
	if (seen && WkNavNoPlace)
		seen := false, h := "", dist := ""
	;Where the arrow was found: pushed up (by a talk prompt) or in its usual spot, bright or in shadow
	info := ArrowInfo()
	boxOff := (seen && info.boxY != "" && info.homeY != "") ? info.homeY - info.boxY : 0
	moved := seen && (boxOff > 12 * info.scale || boxOff < -12 * info.scale)
	if (seen)
		{
		WkSeenAt := A_TickCount, WkLoadAt := 0
		if (IsObject(WkTransSeen))
			WkTransSeen.seenAfter := 1
		;Found again: the next time it goes, start over (with a back-up; see below)
		WkHidden := 0
		if (moved != (WkLastBoxOff != 0) || info.mode != WkLastMode)
			WalkLog("arrow " (moved ? "pushed up " boxOff " px (talk prompt?)" : "in its usual spot") (info.mode = 1 ? ", dark (shadow test)" : info.mode = 2 ? ", under water" : "") " - heading " Round(h) ", distance " (dist = "" ? "?" : dist) ", match " Round(score, 2))
		WkLastBoxOff := moved ? boxOff : 0, WkLastMode := info.mode
		}
	;The game's memory (AutoFarmer's vision helper, read-only), when it can be used: its heading instead of
	;the arrow's once the two have agreed, its distance instead of the OCR'd number (which misses lone digits)
	;once it's known how the two compare. Compared with the arrow only when it reads well (in its usual spot,
	;matching well) - the heading only once the camera has settled after the last turn. Anything wrong with
	;it: the arrow, as before
	fair := seen && !moved && score >= 0.8
	WalkNav(fair && A_TickCount - WkTurnAt > WalkSettle() + 150 ? h : "", fair ? dist : "")
	;(...the verdict just come with this reading: this step's arrow left out too)
	if (seen && WkNavNoPlace)
		seen := false, moved := false, h := "", dist := ""
	;(a new quest goal by the game's memory - its id: the no-X time after a dialogue is over, the new goal's prompt is X'd -
	;2026-10-25 11:28:44, Edith Benchley's kept from X by the Star Portal's dialogue just before)
	if (WkNavOk && WkNavObj.goalid != "")
		{
		if (WkGoalIdWas != "" && WkNavObj.goalid "|" != WkGoalIdWas "|" && A_TickCount < WkQuietUntil)
			WkQuietUntil := 0, WalkLog("a new quest goal (the game's memory) - prompts may be X'd again")
		WkGoalIdWas := WkNavObj.goalid
		}
	;(the goal in this zone by the game's memory - near it, the prompt's looked for whatever the arrow does: the NPC hides it)
	apNear := WalkGoalNear()
	apNear := IsObject(apNear) && apNear.r <= ApproachUnits && (apNear.dz = "" || Abs(apNear.dz) <= 150)
	;The way on is only teleports that don't take the wizard (locked till a quest's done, or only the other way)
	;and the zone's paths have no other: walking off, and a notice - the arrow would lead back to one
	if (WkJumpStuck = 1)
		{
		;(a give-up point: counted - once an episode, whatever takes over)
		WalkBadlyStuck("teleport", "the quest's way on is a teleport that doesn't take the wizard")
		;(AutoFarmer's Puzzle.ahk: what usually opens a blocked way tried first - it takes over, or it doesn't and this goes on as
		;before)
		if (V1IsFunc("PuzzleBeforeNotice") && %"PuzzleBeforeNotice"%.Call("teleport", "a teleport on the way that doesn't take the wizard"))
			{
			WkJumpStuck := 0
			return true
			}
		WkJumpStuck := 2
		Walking := 0
		ReleaseKeys()
		WalkLog("stuck at a teleport: the quest's way on is a teleport that doesn't take the wizard (locked, or one way only), and the zone's paths have no other - walking off")
		SetStatus("stuck - the way on is a teleport that doesn't work here. Press " WalkKeyText() " to walk again")
		WalkNotify("stuck", "Stuck at a teleport", "The quest's way on goes through a teleport here that doesn't take the wizard (locked till a quest's done, or it only goes the other way), and the zone's paths have no other way, so walking is off. Do what opens it (or move on to another quest) and press " WalkKeyText() " to walk again.")
		return false
		}
	WkNavByArrow := 0
	;(the arrow's own heading, for the to-and-fro note)
	hRaw := seen ? h : ""
	if (WkNavUse)
		h := WkNavH
	;(the memory's facing not steered by - a battle starting froze a turn, say - but its sign checked and a route round
	;walls and mobs there: the arrow on screen turned by where the route's aim lies from the quest's target - so the
	;route is kept to, not the game's straight path through mobs)
	else if (seen && h != "" && WkNavChecked && WkNavRel != "")
		h := ArrowWrap(h + WkNavRel), WkNavByArrow := 1
	;(zones away - hops > 0 - the memory's distance is this zone's leg only, the arrow's number counts every leg: the arrow's
	;then, when it's read off an arrow that's seen; the memory's only stands in - no number, no arrow, a poor match's number -
	;with the rest of the way as the arrow last had it for this goal on top, so the two don't jump against each other: an
	;arrow in and out of a door frame is no "next goal")
	if (WkNavD != "" && WkNavHops != 0 && dist != "" && seen)
		WkNavRest := Max(0, dist - WkNavD), WkNavRestKey := WkNavObj.zone "|" WkNavObj.goalid "|" WkNavHops
	else if (WkNavD != "")
		dist := WkNavD + ((WkNavHops != 0 && WkNavRestKey = WkNavObj.zone "|" WkNavObj.goalid "|" WkNavHops) ? WkNavRest : 0)
	;No arrow on screen while the game's memory can be used: it stands in for the arrow - its heading and
	;distance, as if the arrow were seen (WalkNavStandIn: not in a battle or at a loading screen). A see-through
	;arrow on a floor its own colour (the gold carpet in Pigswick Academy) can't be picked out, and scenery hides
	;it. Dialogues and prompts are still looked for meanwhile (standIn, below), as when there's no arrow
	arrowSeen := seen
	if (arrowSeen)
		WkRealSeenAt := A_TickCount
	standIn := seen ? 0 : WalkNavStandIn()
	;(it turned to check the memory's heading: look again)
	if (standIn < 0)
		return Walking ? true : false
	if (standIn)
		{
		seen := 1, WkSeenAt := A_TickCount, WkLoadAt := 0, WkHidden := 0
		if (IsObject(WkTransSeen))
			WkTransSeen.seenAfter := 1
		if (!WkStandIn)
			{
			;(a dialogue that's just opened covers the arrow too: looked for now, below)
			WkStandIn := A_TickCount, WkDlgLook := 0
			WalkLog("no arrow on screen - the game's memory stands in for it (heading " Round(h) " degrees, distance " dist ")")
			}
		}
	else if (WkStandIn)
		{
		WalkLog((seen ? "arrow back" : "no arrow, and the game's memory can't stand in for it now") " - it stood in for " Round((A_TickCount - WkStandIn) / 1000, 1) " s")
		WkStandIn := 0
		}
	;The last distance read (on top of the goal, below) - the arrow's, or the memory's even while the arrow is
	;hidden. No arrow out of battle with no loading screen: how long - Escape once if an X of the bot's may have
	;opened something Space doesn't close (a shop), then a notice for you; it's closed once the arrow is back.
	;(The Escape goes by the arrow on screen even while the game's memory stands in for it - a window X opened
	;covers the arrow, not the memory; the notice only when nothing stands in for it either)
	if ((seen || WkNavD != "") && dist != "")
		WkLastDist := dist, WkLastDistAt := A_TickCount
	;(a battle by the game's log counts too - its first round not seen yet: no Escape over it, no notice)
	if (arrowSeen || inbattle || WkLoading || inbattle = "" || (V1IsFunc("BattleLogInBattle") && %"BattleLogInBattle"%.Call()))
		{
		WkNoArrowFrom := 0, WkNoGuideFrom := 0
		if (arrowSeen)
			WkEscTried := 0, WalkNotifyClose("arrow")
		}
	else
		{
		if (!WkNoArrowFrom)
			WkNoArrowFrom := A_TickCount
		if (standIn)
			WkNoGuideFrom := 0, WalkNotifyClose("arrow")
		else if (!WkNoGuideFrom)
			WkNoGuideFrom := A_TickCount
		gone := A_TickCount - WkNoArrowFrom
		;(no arrow and nothing standing in for it: a goal the game shows no way to - its line read where it sits; a
		;collect goal: collecting - its things by the game's memory, else roaming. Not over X just pressed (6) or a talk
		;(2): what X opened hides the arrow - once that's over, back to 0, it can start)
		if (!standIn && WkArrived != 7 && WkArrived != 6 && WkArrived != 2 && gone > 2000 && CollectNoPlace())
			return Walking ? true : false
		;(not while collecting a goal the game shows no arrow for: no arrow is how it is, not a window an X opened)
		;(nor by the goal with the game's memory standing in: the NPC and its prompt hide the arrow there - a window X opened is
		;closed right after it, WalkCloseAfterX. 2026-10-25 11:42:13: that Escape opened the game's menu)
		if (gone > 15000 && !WkEscTried && WkLastX && A_TickCount - WkLastX < 120000 && !(IsObject(WkCollect) && WkCollect.noPlace && !WkCollect.gaveUp)
			&& !(standIn && apNear) && !WalkDialogOpen())
			{
			;(a quest offer: accepted, not closed)
			if (WalkAcceptQuest("no arrow since an X"))
				return Walking ? true : false
			WkEscTried := 1
			WalkEscape()
			return Walking ? true : false
			}
		if (WkNoGuideFrom && A_TickCount - WkNoGuideFrom > NoArrowNotify && !(IsObject(WkCollect) && WkCollect.noPlace && !WkCollect.gaveUp))
			WalkNotify("arrow", "No quest arrow", "No quest arrow for " Round((A_TickCount - WkNoGuideFrom) / 1000) " s, out of battle. Is a quest tracked? Is a window open over the game? It walks on by itself once the arrow is back.")
		}
	;Waiting at a goal for the next one for WaitNotify, out of battle: tell you (only while the arrow shows -
	;no arrow has its own notice)
	if (WkArrived = 1 && !inbattle)
		{
		if (!WkWaitFrom)
			{
			WkWaitFrom := A_TickCount
			;(AutoFarmer's Puzzle.ahk: "arrived" well short of the goal by the game's memory - a blocked way's evidence; it may take over)
			if (V1IsFunc("PuzzleEvidence"))
				{
				pzGn := WalkGoalNear()
				if (IsObject(pzGn) && %"PuzzleEvidence"%.Call("short", pzGn.r))
					return true
				}
			}
		;(held at a blocked way - Puzzle.ahk: its own notice says so)
		else if (seen && A_TickCount - WkWaitFrom > WaitNotify && !(V1IsFunc("PuzzleHeld") && %"PuzzleHeld"%.Call()))
			{
			;(Puzzle.ahk: what usually opens a blocked way tried first - once, before the notice)
			if (WkNoteKind != "wait" && V1IsFunc("PuzzleBeforeNotice") && %"PuzzleBeforeNotice"%.Call("wait", "waiting at the goal " Round((A_TickCount - WkWaitFrom) / 60000) " minutes"))
				return true
			WalkNotify("wait", "Waiting at the quest goal", "The wizard has been at the quest goal for " Round((A_TickCount - WkWaitFrom) / 60000) " minutes and the quest hasn't moved on - it may need something the bot can't do. It walks on by itself once there's a new goal.")
			}
		}
	else if (WkArrived != 1)
		{
		WkWaitFrom := 0
		WalkNotifyClose("wait")
		}
	;(the goal's id and count by the game's memory are taken again at the next wait - WalkArrivedMoved)
	if (WkArrived != 1)
		WkArr1Key := "", WkArr1Look := 0

	;A dialogue box (its NEXT / DONE / MORE / BACK button showing - it covers or pushes up the arrow):
	;Space through it as fast as the game takes it, whatever the walker was doing
	if ((!seen || moved || standIn) && !inbattle && A_TickCount > WkDlgLook)
		{
		WkDlgLook := A_TickCount + 400
		if (WalkDialogOpen())
			return WalkSkipDialog()
		}
	;A quest offer still up after a dialogue (it covers the arrow): its ACCEPT
	;(v1: WkAcceptLook blank before the first look - a number > blank compared as text, true; WkAcceptLooks blank += 1: 1)
	if ((!seen || standIn) && !inbattle && WkDlgEndAt && A_TickCount - WkDlgEndAt < 30000 && V1Gt(A_TickCount, WkAcceptLook))
		{
		WkAcceptLooks := V1N(WkAcceptLooks) + 1
		WkAcceptLook := A_TickCount + (WkAcceptLooks > 2 ? 3000 : 1500)
		if (WalkAcceptQuest("the arrow's gone since the dialogue"))
			return Walking ? true : false
		}

	;The arrow led to a World Gate (the goal is in another world) or a sigil (a dungeon entrance):
	;close to it, its prompt pushes the arrow up or covers it. Only when the arrow was last this close,
	;so walking past a World Gate or a sigil on the way somewhere else doesn't count (the game's memory knows
	;the distance even while the prompt covers the arrow)
	if ((seen || WkNavD != "") && dist != "" && dist > GateDist)
		WkFarAt := A_TickCount
	near := (WkBestDist != "" && WkBestDist <= GateDist) || ((seen || WkNavD != "") && dist != "" && dist <= GateDist)
	;Standing on a sigil (or started there) its prompt covers the arrow and no distance reads at all.
	;If the arrow hasn't shown a far-off goal lately, the sigil is where it led - checked a few times
	;over a second or two first, so a passing frame without the arrow doesn't count
	hiddenHere := !seen && A_TickCount - WkFarAt > 10000
	if (!hiddenHere)
		WkSigilSeen := 0
	;(using, going to or talking to by the game's memory's kind - AutoFarmer's own steps for it read the prompts themselves: X only
	;at the thing's own, never a sigil's, a boat's or a teleporter's walked past - WalkOwnPrompts)
	if ((WkArrived <= 1 || WkArrived = 3 || WkArrived = 7) && !inbattle && (!seen || moved || standIn || apNear) && A_TickCount > WkGateLook
		&& !WalkOwnPrompts())
		{
		WkGateLook := A_TickCount + ((seen && !near && !standIn && !apNear) ? 1500 : 700)
		prompt := InteractPrompt()
		if (prompt = "gate" && near)
			{
			StartGate("World Gate prompt showing, the arrow led here (distance " (WkBestDist = "" ? dist : WkBestDist) ")")
			return true
			}
		;(or the game's memory: the goal zones away and its way on - this gate - within TalkReach, as WalkPromptWanted takes a
		;door's prompt; v1: hops blank - an older helper's - > 0 compared as text, false)
		if (prompt = "gate" && WkNavOk && V1Gt(WkNavHops, 0) && IsObject(WkNavObj) && WkNavObj.dist != "" && WkNavObj.dist <= TalkReach)
			{
			StartGate("World Gate prompt showing, the game's memory's way on " Round(WkNavObj.dist) " away (the goal " WkNavHops " zone changes on)")
			return true
			}
		;(the quest's own NPC by the game's memory - its name on the prompt, within TalkReach: X, even just out of a dialogue -
		;3 s after the last X, 3 tries in 2 minutes. 2026-10-25 11:30:07-22: a dialogue left Thornton Lewis' goal as it was,
		;and his prompt was kept from X for 15 s while the wizard went round him)
		if (prompt = "press" && WalkTalkPromptOk(WkPromptDest))
			{
			StartPressX(WkPromptDest)
			return true
			}
		;Just out of a dialogue X opened: no X at any prompt for a while (walk away from it), so the same
		;NPC or object can't be talked to over and over
		;(a quest marker over it - a "?" with its name under it - is something new there: talked to all the same)
		if (prompt = "press" && A_TickCount < WkQuietUntil && WalkPromptFree(WkPromptDest, 60000) && !WalkTalkSpent(WkPromptDest) && WalkQuestMarkerTalk(WkPromptDest))
			return true
		if ((prompt = "sigil" || prompt = "press") && A_TickCount < WkQuietUntil)
			{
			if (!WkQuietLogged)
				WkQuietLogged := 1, WalkLog("prompt showing, but a dialogue just closed - no X for " Ceil((WkQuietUntil - A_TickCount) / 1000) " s")
			prompt := ""
			}
		;A sigil: always in (once per 10 minutes for the same one) - but not straight back into the
		;dungeon just left: coming out puts you right at its sigil (unless the quest's goal is in it - WalkSigilGo)
		WkSigilSeen := 0
		if (prompt = "sigil")
			{
			WalkZone()
			;(the quest's way - the arrow led here, or back into the goal's dungeon - or one only walked past: StartSigil notes which)
			sgGoal := 0
			sgWhy := WalkSigilGo(near, &sgGoal)
			if (sgWhy != "")
				{
				StartSigil(sgWhy, sgGoal)
				return true
				}
			}
		;Any other "Press X ..." prompt (talk, collect, open...) the quest wants (WalkPromptWanted: its name in the
		;goal line, close to the goal, or collecting): press X - once a minute for the same one - then Space
		;through whatever it opens and walk on. Others - an NPC or a vendor walked past - are left alone
		;(the talk goal's own NPC X'd 3 times in 2 minutes for nothing: left till its tries come free - WalkTalkSpent)
		if (prompt = "press" && WalkPromptFree(WkPromptDest, 60000) && !WalkTalkSpent(WkPromptDest))
			{
			if (WalkPromptWanted(WkPromptDest, dist))
				{
				StartPressX(WkPromptDest)
				return true
				}
			;(not in the goal line - but a quest marker over it: a gold "?" with its name under it - another goal of this
			;quest, or another quest's: the game wants it talked to)
			if (WalkQuestMarkerTalk(WkPromptDest))
				return true
			if (!WkPromptSkip.Has(WkPromptDest) || A_TickCount - WkPromptSkip[WkPromptDest] > 60000)
				WkPromptSkip[WkPromptDest] := A_TickCount, WalkLog("prompt '" SubStr(WkPromptDest, 1, 40) "' - not the quest's (not in the goal line, not near the goal): no X, walking on")
			}
		;A boat or the like ("BOAT TO GOBBLERTON", "Press X or click to Use") covering the arrow: use it
		;if it goes where the quest is, otherwise step out of it and walk on
		if (prompt = "transport" && WalkTransport(WkPromptDest, seen))
			return true
		}

	;Pressed X at a prompt on the way (WkArrived = 6): a dialogue or the like covers the arrow - Space
	;through it; once the arrow is back (or nothing opened within a second), walk on
	if (WkArrived = 6)
		{
		;(X opened the Spiral Map - a World Gate's prompt read as a plain one, 'WORLDGATE' (2026-11-13 00:16): Go To World, not
		;Space - by the game's memory, WalkSpiralMapUp)
		if (A_TickCount - WkPressAt > 700 && WalkSpiralMapUp("pressed X"))
			return true
		;What X opened: an OK box or a window - a shop, a vendor's list - is closed first (WalkCloseAfterX: OK, or
		;Escape - nothing in it is ever clicked); looked at once, a moment after X
		if (!WkDialog && !WkAfterXLooked && A_TickCount - WkPressAt > 700 && !WalkDialogOpen())
			{
			WkAfterXLooked := 1
			if (WalkCloseAfterX())
				{
				WkArrived := 0, WkBestTime := A_TickCount, WkLastRead := A_TickCount
				WkQuietUntil := A_TickCount + DialogQuiet, WkQuietLogged := 0
				return true
				}
			}
		;(a dialogue covers the arrow on screen - not the game's memory standing in for it, which goes on
		;regardless: then it counts when the arrow itself was on screen right before X and has gone; with no
		;arrow to go by - Pigswick's carpet - only a dialogue box that's read)
		;(by the goal by the game's memory - apNear - only the dialogue box read: the NPC and its prompt hide the arrow there
		;anyway. 2026-10-25 11:42:01-16: 28 Space presses with nothing open, then an Escape into the game's menu)
		;(nor a goal the game shows no way to - WkNavNoPlace: there's no arrow to go by at all)
		if ((((apNear || WkNavNoPlace) ? false : standIn ? WkArrowAtX : !seen) || WalkDialogOpen()) && A_TickCount - WkPressAt < 60000)
			{
			if (!WkDialog)
				WalkLog("pressed X: something opened (arrow covered) - pressing Space")
			WkDialog := 1
			if (WkTalk < TalkMax * 3 && A_TickCount - WkSpaceAt > TalkGap)
				PressKey("Space"), WkTalk += 1, WkSpaceAt := A_TickCount
			SetStatus("pressed X - Space through what it opened")
			Sleep(100)
			return true
			}
		if (WkDialog || A_TickCount - WkPressAt > 1200)
			{
			WalkLog("pressed X: " (WkDialog ? "done after " WkTalk " Space presses" : "nothing opened") " - walking on" (WkDialog ? " (no X at prompts for " Round(DialogQuiet / 1000) " s)" : ""))
			WkArrived := 0, WkBestTime := A_TickCount, WkLastRead := A_TickCount
			if (WkDialog)
				WkQuietUntil := A_TickCount + DialogQuiet, WkQuietLogged := 0
			}
		Sleep(100)
		return true
		}

	;Waiting at a goal for the next one: the goal's id and count by the game's memory every 3 s - moved on, walking on at once
	;(the arrow's number needn't change - a goal with no place has none: it waited there till the game logged it out, 2026-10-25);
	;the same, with no place: its kind's own way (WalkArrivedMoved)
	if (WkArrived = 1 && !inbattle && WalkArrivedMoved())
		return Walking ? true : false
	;A "collect / defeat N things" goal: the arrow only leads to the area, and standing there does
	;nothing. Walk into the monsters there, or roam about the spot (CollectStep) - or a goal to use things, go to a place or
	;talk to an NPC the game shows no way to (the game's memory's kind): their own steps
	if (WkArrived = 7)
		return CollectStep(seen, h, dist)
	if ((WkArrived = 0 || WkArrived = 1) && !inbattle && seen && dist != "" && (dist <= RoamRadius || (IsObject(WkCollect) && (WkCollect.gaveUp || A_TickCount - WkCollect.stepAt < 300000))) && CollectCheck(dist))
		return true

	;Talking (after X). The dialogue box covers the arrow, so: no arrow = dialogue open, press Space to
	;skip through it. Arrow back with a new goal = done, walk on. Arrow still there with the same goal
	;(nobody to talk to: a doorway or loading point) = push on into it. The wizard doesn't move while
	;talking, so a distance that's changed from the one at X means a new goal, even a close one
	if (WkArrived = 2)
		{
		;(by the game's memory the goal's id says: a new one is the next goal at once, the same one isn't - whatever the arrow's
		;number does: it's along the game's path, and jumps by its nodes right by the goal. 2026-10-25 11:29:00 "next goal
		;(distance 23)" with the goal as it was, a shop holding the wizard; 11:33:34 6 from 1, standing still)
		memSame := (WkNavOk && WkTalkGoal != "" && WkNavObj.goalid != "") ? (WkNavObj.goalid "|" = WkTalkGoal "|") : ""
		if (memSame != "")
			WkFar := memSame ? 0 : 2
		else
			WkFar := (seen && dist != "" && (dist > ArriveDist + 20 || DistChanged(dist, WkTalkDist))) ? WkFar + 1 : 0
		if (WkFar >= 2)
			{
			WalkLog("talk: next goal (distance " dist (memSame = 0 ? ", a new goal by the game's memory" : "") ") after " WkTalk " Space presses")
			if (WkDialog)
				WkQuietUntil := A_TickCount + DialogQuiet, WkQuietLogged := 0
			WalkReset()
			SetStatus("next goal (distance " dist ") - walking on")
			return true
			}
		;One far reading: wait for a second before deciding it's a new goal
		if (WkFar = 1)
			{
			Sleep(100)
			return true
			}
		;(what X opened, if not a dialogue: an OK box or a window - a shop - closed first, as after X at a prompt on the way -
		;WalkCloseAfterX; looked at once, a moment after X. 2026-10-25 11:28:49: a vendor's shop by Edith Benchley left open)
		if (!WkDialog && !WkAfterXLooked && A_TickCount - WkTalkAt > 700 && !WalkDialogOpen())
			{
			WkAfterXLooked := 1
			if (WalkCloseAfterX())
				{
				WkArrived := 0, WkBestTime := A_TickCount, WkLastRead := A_TickCount
				return true
				}
			}
		;(by the goal by the game's memory - apNear - the arrow hidden is the NPC, not a dialogue: only a dialogue box read is one)
		if (!seen && !(apNear && !WalkDialogOpen()))
			{
			;On top of the goal and X opened no dialogue (one would have been Spaced through above, setting
			;WkDialog): no Space (it jumps) - after 2.5 s step back once so the arrow shows again
			if (WkOnTop && !WkDialog)
				{
				if (!WkOnTopBacked && A_TickCount - WkOnTopAt > 2500)
					{
					WkOnTopBacked := A_TickCount
					WalkLog("talk: X on top of the goal opened nothing - stepping back so the arrow shows")
					BackUp(600)
					return Walking ? true : false
					}
				;(stepped back and still no arrow: something hides it after all - the usual search)
				if (WkOnTopBacked && A_TickCount - WkOnTopBacked > 2000)
					{
					WalkLog("talk: still no arrow after stepping back - looking for it (backing up, turning)")
					WkArrived := 0, WkOnTop := 0, WkSeenAt := A_TickCount - 1100, WkHidden := 0, WkHiddenAt := 0
					return true
					}
				SetStatus("at the goal - waiting for what X opened")
				Sleep(300)
				return true
				}
			;X at a World Gate opens the Spiral Map (it covers the arrow too): Go To World, not Space
			if (WkTalk < 3 && IsObject(SpiralMapButton()))
				{
				WalkLog("talk: the Spiral Map opened - it's a World Gate")
				WkArrived := 4, WkGateAt := A_TickCount, WkGateClicks := 0, WkGateX := 1
				return true
				}
			;(slower to open than 2 Space presses: the game's memory looks on - WalkSpiralMapUp)
			if (WkTalk >= 3 && WalkSpiralMapUp("talk"))
				return true
			if (!WkDialog)
				WalkLog("talk: dialogue open (arrow covered) - pressing Space")
			WkDialog := 1
			if (WkTalk < TalkMax)
				{
				PressKey("Space")
				WkTalk += 1, WkSpaceAt := A_TickCount
				SetStatus("talking - Space to skip the dialogue (" WkTalk " of " TalkMax ")")
				Sleep(TalkGap)
				}
			else
				{
				;A long dialogue (or a press lost while a page slid in): keep skipping, more slowly
				if (WkTalk < TalkMax * 3 && A_TickCount - WkSpaceAt > 1500)
					PressKey("Space"), WkTalk += 1, WkSpaceAt := A_TickCount
				SetStatus("waiting - dialogue or loading screen")
				Sleep(300)
				}
			return true
			}
		;(the game's memory standing in for an arrow the Spiral Map covers: X at a World Gate all the same)
		if (standIn && WkTalk < 3 && IsObject(SpiralMapButton()))
			{
			WalkLog("talk: the Spiral Map opened - it's a World Gate")
			WkArrived := 4, WkGateAt := A_TickCount, WkGateClicks := 0, WkGateX := 1
			return true
			}
		;Arrow visible: give a slow dialogue two Space presses to show up first (not after X on top of the
		;goal opened nothing: it's been waited for)
		;(the game's memory standing in for the arrow, or a talk goal by it: no Space - with nothing open it jumps - a moment
		;for a dialogue to show instead; one that does is Spaced through by the dialogue look above)
		if (!WkDialog && WkTalk < 2 && !WkOnTop && !WkStuckTalk)
			{
			WkTalk += 1
			if (standIn || apNear || IsObject(WalkTalkGoal()))
				{
				SetStatus("talking - waiting for a dialogue (" WkTalk ")")
				Sleep(400)
				return true
				}
			PressKey("Space")
			SetStatus("talking - Space (" WkTalk ")")
			Sleep(TalkGap)
			return true
			}
		;(a talk goal by the game's memory - its NPC in this zone: X at it again from close by, facing it - never walked on
		;through it (2026-10-25 11:33: pushed straight through Thornton Lewis twice, 3 s each, into a Piscean Guard's reach);
		;its 3 tries in 2 minutes used: waiting by it. A dialogue just over: a moment for the goal to move on first)
		talkNext := WalkNoDialogNext()
		if (talkNext != "push")
			{
			if (WkDialog && A_TickCount - Max(WkDlgEndAt ? WkDlgEndAt : 0, WkSpaceAt ? WkSpaceAt : 0) < 1500)
				{
				Sleep(100)
				return true
				}
			if (WkDialog)
				WkQuietUntil := A_TickCount + DialogQuiet, WkQuietLogged := 0
			return WalkTalkAgain(talkNext, dist)
			}
		;X by the obstacle near the goal opened nothing: it wasn't the thing (a fence, a wall) - go round it
		;after all, as before (the next stuck tries Unstick; WkStuckNearDone keeps the X to once)
		if (WkStuckTalk && !WkDialog)
			{
			if (A_TickCount - WkTalkAt < 1500)
				{
				Sleep(100)
				return true
				}
			WalkLog("talk: X by the obstacle opened nothing - going round it after all")
			WkArrived := 0, WkStuckTalk := 0, WkBestTime := A_TickCount, WkLastRead := A_TickCount
			return true
			}
		if (WkDialog)
			WkQuietUntil := A_TickCount + DialogQuiet, WkQuietLogged := 0
		StartPush(WkDialog ? "same goal after the dialogue" : "nobody to talk to (no dialogue opened)", dist)
		return true
		}

	;No arrow (and the game's memory not standing in for it, above)
	if (!seen)
		{
		;(the Spiral Map open over it - left open, or the bot started under it: a World Gate, Go To World - by the game's memory,
		;WalkSpiralMapUp; 2 s after the arrow went, so a battle's start isn't asked about. Only a map the walker's own X may have
		;opened - that X in the last 2 minutes, nothing of yours since - or one left up with nobody at the PC for a minute: never
		;one you opened and ticked a world on, then left alone for the few seconds 'Wait while I play' waits)
		if (!inbattle && (!WkSeenAt || A_TickCount - WkSeenAt > 2000)
			&& ((WkLastX && A_TickCount - WkLastX < 120000 && A_TickCount - UserIdle() < WkLastX) || UserIdle() > 60000)
			&& WalkSpiralMapUp("no arrow"))
			return true
		;Pushing into a doorway and the arrow went: the door frame between the camera and the wizard,
		;or the loading screen starting. Stopping would leave a door frame hiding it for good, so walk
		;straight on for a moment either way
		if (WkArrived = 3 && !inbattle && A_TickCount < WkPushUntil && A_TickCount - WkSeenAt < PushHiddenTime)
			{
			if (!WkStraight)
				{
				WkStraight := 1, WkStraightAt := A_TickCount
				WalkLog("push: arrow hidden (door frame or loading screen?) - walking straight on")
				}
			HoldW(1)
			if (!Walking)
				return false
			SetStatus("pushing on straight - arrow hidden (door frame or loading screen?)")
			Sleep(100)
			return true
			}
		;Walking and the arrow went: an arch, door frame or pillar between the camera and the wizard.
		;Stopping would freeze the view with it still hidden, so keep walking for a moment
		if (WkArrived = 0 && HeldW && !inbattle && A_TickCount - WkSeenAt < HiddenWalkTime / (SpeedNow ? SpeedNow : 1) && !(WkLastDist != "" && WkLastDist <= OnTopDist))
			{
			SetStatus("walking on - arrow hidden (behind something?)")
			Sleep(100)
			return true
			}
		if (KeysDown)
			ReleaseKeys(true)
		;(on top of the goal by the game's memory - within TalkUnits, the goal in this zone: 1 / 0; "" not known - the arrow's
		;last number then: OnTopDist, 2000 game units at Celestia's 100 to the arrow's 1)
		onTopMem := WalkGoalOnTop()
		;Walking into a doorway and the arrow stayed gone: a loading screen, carry on normally afterwards
		if (WkArrived = 3)
			{
			WalkLog("push: arrow gone - loading screen?")
			WkArrived := 0, WkSeenAt := 0, WkPushes := 0, WkLastDist := ""
			WkLoadAt := A_TickCount, WkGoneSpaces := 0, WkSpaceAt := 0
			}
		;Right at the goal and the arrow went: on top of it (it isn't drawn there). Backing up and turning would
		;only walk away from the thing: it's arrived - X (talk / use / collect), once per goal
		;(not a loading screen, and in AutoFarmer not a battle starting - the arrow goes then too)
		;(nor a goal the game shows no way to: there's no "at it" - WkNavNoPlace)
		else if (WkArrived = 0 && !inbattle && !WkOnTopDone && !WkNavNoPlace && (onTopMem != "" ? onTopMem : (WkLastDist != "" && WkLastDist <= OnTopDist && A_TickCount - WkLastDistAt < 4000))
			&& A_TickCount - WkSeenAt > 700 && !WkLoadAt && !WalkLoadingScreen() && (inbattle = "" || WalkSureNoBattle(WkSeenAt)))
			{
			WkOnTopDone := 1
			WalkLog("arrow gone right at the goal (last distance " WkLastDist WalkGoalSay() ") - on top of it: arrived")
			StartTalk("?")
			if (WkArrived = 2)
				WkOnTop := 1, WkOnTopAt := A_TickCount, WkOnTopBacked := 0
			return true
			}
		;Lost it while walking: the arrow is drawn at the wizard's feet, so a pillar or wall between the
		;camera and the wizard hides it - or the wizard's own mount, when it points back towards the
		;camera. Back up, then turn 70 degrees at a time (a full circle at most) until it shows again
		;(also when it hasn't shown at all since walking was switched on - started right there - but not
		;after a loading screen: then it's a dialogue, see below)
		;(not while a battle may be starting: the arrow goes as the wizard's pulled in, before the Pass button shows -
		;the logs: every back-up came 1-3 s before a battle)
		;(nor while the game's memory steers - it stands in for the arrow, here only a moment it can't: a battle starting, a
		;loading screen - nor on top of the goal by it. 2026-10-25 11:28:15-19: two back-ups by the Star Portal, the memory's
		;distance dropped over a distrusted scale)
		;(nor a goal the game shows no way to - WkNavNoPlace: there's no arrow to find)
		else if (WkArrived = 0 && !inbattle && !WkSigilSeen && !WkNavNoPlace && WkHidden < 6 && A_TickCount - WkHiddenAt > 1500 && WalkHiddenBackUpOk(onTopMem)
			&& (WkSeenAt ? A_TickCount - WkSeenAt > 1000 && A_TickCount - WkSeenAt < 30000 : !WkLoadAt)
			&& !WalkLoadingScreen() && (inbattle = "" || WalkSureNoBattle(WkSeenAt)))
			{
			;Only turn when it stays gone: a moment out of sight just gets a back-up - unless it has
			;already backed up twice in the last 20 s (the arrow keeps going at the same place)
			if (A_TickCount - WkBackupsFrom > 20000)
				WkBackups := 0, WkBackupsFrom := A_TickCount
			if (WkHidden = 0 && WkBackups >= 2)
				WkHidden := 1
			if (WkHidden = 0)
				WkBackups += 1
			WkHidden += 1, WkHiddenAt := A_TickCount
			WalkLog("arrow hidden (behind something, or under the mount?) - " (WkHidden = 1 ? "backing up" : "turning 70 degrees (" WkHidden - 1 " of 5)"))
			SetStatus("arrow hidden - " (WkHidden = 1 ? "backing up" : "turning") " to find it again")
			if (WkHidden = 1)
				BackUp(600)
			else
				Turn(70 * WkSide)
			WkHiddenAt := A_TickCount
			return Walking ? true : false
			}
		;Still no arrow a while after a loading screen: a new zone can open a dialogue by itself, which
		;covers the arrow. Press Space now and then to get through it (a jump if there's nothing open)
		if (WkLoadAt && !inbattle && A_TickCount - WkLoadAt > LoadSpaceWait && A_TickCount - WkSpaceAt > 1500 && WkGoneSpaces < LoadSpaceMax)
			{
			if (!WkGoneSpaces)
				WalkLog("no arrow " Round((A_TickCount - WkLoadAt) / 1000) " s after the loading screen - pressing Space in case a dialogue opened")
			PressKey("Space")
			WkGoneSpaces += 1, WkSpaceAt := A_TickCount
			}
		SetStatus("waiting - no quest arrow on screen (battle, loading or dialogue?)")
		WkBestDist := "", WkRouteBest := "", WkBestTime := A_TickCount, WkLastRead := A_TickCount, WkTries := 0
		Sleep(300)
		return true
		}

	;Pushing on into the goal (doorway, loading point): follow the arrow until right at it, then stop
	;steering (it swings about on top of the goal) and walk straight through. A loading screen hides
	;the arrow (handled above); otherwise it gives up after PushTime
	if (WkArrived = 3)
		{
		if (dist != "")
			{
			WkLastRead := A_TickCount
			;The goal was reached and the quest moved on: the arrow jumps away (while still following
			;the arrow in, a jump of 15 is enough - it only gets closer then)
			WkFar := (WkBestDist != "" && dist > WkBestDist + (WkStraight ? 60 : 15)) ? WkFar + 1 : 0
			if (WkFar >= 2)
				{
				WalkLog("push: next goal (distance " dist ") - walking on")
				WalkReset()
				SetStatus("next goal (distance " dist ") - walking on")
				return true
				}
			;(v1: a number < blank compared as text - false)
			if (V1Lt(dist, WkBestDist) || WkBestDist = "")
				WkBestDist := dist
			}
		if (A_TickCount > WkPushUntil || (WkStraight && A_TickCount - WkStraightAt > PushStraightTime))
			{
			HoldW(0)
			;(walked into the way out without an X - the game's memory said so - and nothing loaded: X after
			;all, in case it's something to use, like a World Gate whose prompt didn't read)
			if (WkNavDoor)
				{
				WkNavDoor := 0
				WalkLog("push: the way out didn't load after " Round((A_TickCount - WkPushStart) / 1000, 1) " s - pressing X after all")
				StartTalk(dist = "" ? "?" : dist, false)
				return true
				}
			WkArrived := 1, WkFar := 0, WkArrDist := dist
			WalkLog("push: no loading screen after " Round((A_TickCount - WkPushStart) / 1000, 1) " s (distance " (dist = "" ? "?" : dist) ") - waiting for the next goal")
			SetStatus("arrived" (dist = "" ? "" : " (distance " dist ")") " - waiting for the next goal")
			return true
			}
		if (!WkStraight && ((dist != "" && WalkNear(dist, PushStraightDist, PushUnits)) || (dist = "" && (WkBestDist = "" || WkBestDist <= NearDist))))
			{
			;Face the goal first if it's off to the side. Not if it's behind: then the wizard has just
			;walked over the goal point, and turning round would walk it away from a door beyond it
			if (Abs(h) > AheadAngle && Abs(h) <= 120)
				{
				HoldW(0)
				Turn(h)
				if (!Walking)
					return false
				}
			WkStraight := 1, WkStraightAt := A_TickCount
			WalkLog("push: at the goal (distance " (dist = "" ? "?" : dist) ") - walking straight on through it")
			}
		;(right after a turn the arrow doesn't show it yet: see TurnSettle. The game's memory does)
		if (!WkStraight && !WkNavUse && A_TickCount - WkTurnAt < WalkSettle())
			{
			Sleep(50)
			return true
			}
		if (WkStraight)
			HoldW(1)
		else if (Abs(h) > TurnInPlace)
			{
			HoldW(0)
			Turn(h)
			}
		else
			{
			HoldW(1)
			if (Abs(h) > AheadAngle)
				Turn(h)
			}
		if (!Walking)
			return false
		SetStatus("pushing on " (WkStraight ? "straight" : "- " (WkNavUse ? "heading " : "arrow ") Round(h) " degrees") ", distance " (dist = "" ? "?" : dist) (WkNavUse ? " (game's memory)" : ""))
		Sleep(50)
		return true
		}

	;A teleport on the game's path (the route stops at it - the zone's paths jump from there to far off: a
	;trolley, a hole down to the sewers): walk straight on into it for a second, once (X at its prompt if it
	;asks: WalkPromptWanted), then stand by it - not back and forth over it - while the helper waits for it to
	;take the wizard. One that doesn't in 15 s is given up and the route goes another way: walking on
	if (WkJumpKey != "" && WkNavJump = "" && WkNavRouted && IsObject(WkNavObj) && WkNavObj.ax != "")
		{
		jk := StrSplit(WkJumpKey, ",")
		if (Sqrt((WkNavObj.ax - jk[1]) ** 2 + (WkNavObj.ay - jk[2]) ** 2) > 400)
			WalkLog("teleport at " WkJumpKey ": the route goes another way now - walking on"), WkJumpKey := ""
		}
	;A mob on the way that the route can't go round (a corridor, a doorway - mobavoid): stand still till it
	;moves off - also through a reading missed meanwhile (not a step towards it). The helper gives up after 25 s
	;and routes on past it
	if ((WkNavMob != "" || (!WkNavOk && WkNavMobAt && A_TickCount - WkNavMobAt < 1500)) && WkNavJump = "")
		{
		if (WkMobLogged != WkNavMobName)
			WkMobLogged := WkNavMobName, WalkLog("a mob on the way (" WkNavMobName ") and no way round it - waiting for it to move off")
		if (KeysDown || HeldW)
			ReleaseKeys(true)
		WkBestTime := A_TickCount, WkLastRead := A_TickCount, WkTries := 0
		SetStatus("waiting - a mob on the way (" WkNavMobName (WkNavMob != "" ? ", " WkNavMob " s" : "") ")")
		Sleep(300)
		return true
		}
	;Another player's battle on the way that the route can't go round (duelavoid): stand still till it ends - WalkDuelWait
	if (WalkDuelWait())
		return true
	;A party's leader (AutoFarmer's Party.ahk): it waits while a follower is far, in another zone or not ready - walking,
	;not mid-talk or mid-push, and never inside a mob's reach (getting out of it first)
	if ((WkArrived = 0 || WkArrived = 1) && A_TickCount - WkNavEscAt > 1500 && WkNavMob = "" && V1IsFunc("PartyHoldWhy"))
		{
		pWhy := %"PartyHoldWhy"%.Call()
		if (pWhy != "")
			{
			if (KeysDown || HeldW)
				ReleaseKeys(true)
			WkBestTime := A_TickCount, WkLastRead := A_TickCount, WkTries := 0
			SetStatus("party: waiting - " pWhy)
			Sleep(300)
			return true
			}
		}
	if (WkNavOk)
		WkMobLogged := "", WkNavMobAt := 0
	if (WkNavJump != "")
		{
		if (WkJumpKey != WkNavJumpAt)
			{
			WkJumpKey := WkNavJumpAt, WkJumpPushUntil := A_TickCount + 1000
			WalkLog("teleport on the game's path at " WkNavJumpAt " - walking on into it (given up if it doesn't take the wizard)")
			}
		if (A_TickCount < WkJumpPushUntil)
			{
			HoldW(1)
			SetStatus("walking on into a teleport on the game's path")
			Sleep(50)
			return true
			}
		if (KeysDown || HeldW)
			ReleaseKeys()
		WkBestTime := A_TickCount, WkLastRead := A_TickCount, WkTries := 0
		SetStatus("at a teleport - waiting for it to take the wizard (" WkNavJump " s)")
		Sleep(300)
		return true
		}
	;Near the goal by the game's memory - in this zone, straight ahead, no mob on the way: the last bit walked closed loop
	;and X there (WalkApproachStep). Steps a second apart walked 900-1800 units over it and turned round: 2026-10-25
	;11:28-11:42, Celestia, a 160-175 degree turn by every NPC
	if (WalkApproachWanted(&apGn))
		return WalkApproachStep(apGn, dist)
	if (dist != "")
		{
		WkLastRead := A_TickCount
		;Arrived: stay put until the distance is clearly bigger again (the next goal). After two pushes
		;at the same goal it needs a much bigger jump, so it doesn't go back and forth over the spot
		if (WkArrived)
			{
			;The wizard stands still while it waits here, so a distance that's changed is a new goal,
			;even a close one (the next NPC in the same room)
			if (WkArrDist = "")
				WkArrDist := dist
			changed := DistChanged(dist, WkArrDist)
			;(waiting on a collect goal it gave up on - it stopped wherever it was: only a new goal moves it on; held at a blocked way
			;- AutoFarmer's Puzzle.ahk - the same)
			gaveUpWait := (IsObject(WkCollect) && WkCollect.gaveUp) || (V1IsFunc("PuzzleHeld") && %"PuzzleHeld"%.Call())
			WkFar := (!gaveUpWait && (changed || dist > ArriveDist + (WkPushes >= 2 ? 60 : 5))) ? WkFar + 1 : 0
			;(the goal zones away by the game's memory - waiting by this zone's way out, which didn't take the wizard: the arrow's
			;number counts the zones beyond too and stays big there - walked on only once well off the way out, or a new goal)
			;(v1: hops blank - an older helper's - > 0 compared as text, false)
			if (!gaveUpWait && WkNavOk && V1Gt(WkNavHops, 0) && IsObject(WkNavObj) && WkNavObj.dist != "")
				WkFar := WkNavObj.dist > ArriveUnits * 4 ? WkFar + 1 : 0
			;(by the game's memory a new goal id is the next goal at once, even one right here; a talk goal's NPC X'd for nothing:
			;X again once its tries come free - WalkTalkRetry)
			if (WkArrGoal = "" && WkNavOk)
				WkArrGoal := WkNavObj.goalid
			arrNew := !gaveUpWait && WkNavOk && WkArrGoal != "" && WkNavObj.goalid != "" && WkNavObj.goalid "|" != WkArrGoal "|"
			if (arrNew)
				WkFar := 2, changed := true
			else if (WkFar < 2 && WalkTalkRetry(dist))
				return true
			if (WkFar < 2)
				{
				SetStatus("arrived (distance " dist ") - waiting for the next goal")
				Sleep(400)
				return true
				}
			;A new goal: it may be pushed into twice again
			if (changed || dist > ArriveDist + 60)
				WkPushes := 0
			WalkLog("arrived: distance now " dist " (was " WkArrDist (arrNew ? "; a new goal by the game's memory" : "") ") - walking on")
			WkArrived := 0, WkFar := 0, WkArrDist := "", WkArrGoal := "", WkBestDist := "", WkBestTime := A_TickCount, WkTries := 0
			}
		;Two readings in a row, so one misread number can't stop us early
		;(by the game's memory, in game units, when it can be used: the arrow's number means more or less in
		;each zone)
		WkNear := WalkNear(dist, ArriveDist, ArriveUnits) ? WkNear + 1 : 0
		;(or walked right over it - ahead, then behind, close by - or past its nearest and on away)
		passedGoal := WalkPassedGoal()
		;(a talk goal's NPC by the game's memory with the route round walls much longer than straight to it - a fence, a wall
		;between: not there by the straight distance, the route goes round; X at its own prompt when that shows)
		arTalk := WalkTalkGoal()
		if (IsObject(arTalk) && WalkRouteRound(arTalk.r))
			WkNear := 0, passedGoal := ""
		if (passedGoal != "")
			WalkLog("walked right past the goal (" passedGoal ") - there")
		;(the game's memory's distance isn't misread like the arrow's number: one reading is enough)
		if (WkNear >= ((WkNavOk && IsObject(WkNavObj) && WkNavObj.dist != "") ? 1 : 2) || passedGoal != "")
			{
			StartTalk(dist)
			return true
			}
		;Progress = closer than ever before, or a new goal further away
		if (WkBestDist = "" || dist < WkBestDist - 1 || dist > WkBestDist + 50)
			WkBestDist := dist, WkBestTime := A_TickCount, WkTries := 0
		;...or getting on along the route round walls: going round one gets no closer as the crow flies for a
		;while (and for the badly-stuck watch below)
		onRoute := WkNavUse && WkNavRouted && WkNavLeft != ""
		if (onRoute && (WkRouteBest = "" || WkNavLeft < WkRouteBest - 1 || WkNavLeft > WkRouteBest + 50))
			WkRouteBest := WkNavLeft, WkBestTime := A_TickCount, WkTries := 0
		if (onRoute && (WkRouteProg = "" || WkNavLeft < WkRouteProg - 30 || WkNavLeft > WkRouteProg + 300))
			WkRouteProg := WkNavLeft, WkProgAt := A_TickCount
		;(a stuck episode under way: over once clearly closer than where it began - WalkLostProgress)
		WalkLostProgress(dist, onRoute ? WkNavLeft : "")
		;Badly stuck: walking on and on without getting any closer to the goal for StuckForever (the clock only
		;runs while it walks here - a gap of over 5 s since it last looked, a battle or a talk, is left out):
		;the Commons, and start over from there
		if (A_TickCount - WkProgStep > 5000)
			WkProgAt += A_TickCount - WkProgStep
		WkProgStep := A_TickCount
		if (WkProgBest = "" || dist < WkProgBest - 30 || dist > WkProgBest + 300)
			WkProgBest := dist, WkProgAt := A_TickCount
		else if (A_TickCount - WkProgAt > StuckForever)
			{
			sfWhy := "no closer to the goal in " Round(StuckForever / 60000) " minutes of walking"
			;(a give-up point: counted, its minutes lost - since the last stuck episode ended, if that was later: not counted twice -
			;once an episode, whatever takes over)
			WalkBadlyStuck("nocloser", sfWhy, Min(A_TickCount - WkProgAt, A_TickCount - V1N(WkLostEndAt)), WkProgBest)
			;(AutoFarmer's Puzzle.ahk: what usually opens a blocked way tried first - inside a dungeon the Commons would leave it)
			if (V1IsFunc("PuzzleBeforeNotice") && %"PuzzleBeforeNotice"%.Call("stuck", sfWhy, dist))
				return true
			if (WalkCommonsReset(sfWhy, dist))
				return true
			;(neither - the Commons used in the last ResetEvery: this was silent, every step. Said once an episode, with a tray tip and
			;Discord - it goes on trying round, and the Commons comes once it may; no notice window: what you'd do then is recorded as
			;a puzzle's way - Puzzle.ahk - while the bot still walks)
			if (Walking)
				WalkStuckNoCommons(sfWhy)
			}
		;Got round an obstacle: clearly closer than where it got stuck. Remember which way worked there
		if (IsObject(WkEsc))
			{
			;(too long ago - a battle or a loading screen in between - and it proves nothing)
			if (A_TickCount - WkEsc.at > 20000)
				WkEsc := ""
			;(v1: stuck with no distance - WkEsc.dist blank: blank - 10 blank, a number < blank false)
			else if (V1Lt(dist, V1Sub(WkEsc.dist, 10)))
				{
				if (WkEsc.zone != "")
					WalkMemLearn(WkEsc.zone, WkEsc.dist, WkEsc.side, WkEsc.walkMs, true)
				WalkLog("got round the obstacle at distance " WkEsc.dist " going " (WkEsc.side > 0 ? "right" : "left") (WkEsc.zone != "" ? " - remembered for " WkEsc.zone : ""))
				WkEsc := ""
				}
			}
		;On the way to an obstacle remembered from before: keep to the side that got round it then (not
		;while already getting round something)
		;(not on the route round walls: that knows the walls - the ones remembered were met without it)
		if (A_TickCount > WkBiasUntil && WkTries = 0 && !IsObject(WkEsc) && WkMem.Length && !onRoute)
			{
			spot := WalkMemAhead(WalkZone(), dist)
			if (IsObject(spot))
				{
				spot.preAt := A_TickCount
				WkBias := UnstickBias * spot.side, WkBiasUntil := A_TickCount + BiasTime
				WalkLog("remembered obstacle ahead (" spot.zone ", distance " spot.dist ") - keeping to the " (spot.side > 0 ? "right" : "left"))
				}
			}
		}
	else if (WkArrived)
		{
		Sleep(400)
		return true
		}
	;(those two guesses only with no game's memory this step - it knows the distance; 2026-10-25 11:28:20 "at the goal
	;(distance ?)" about 2400 units off the Star Portal, its distance dropped over a distrusted scale)
	else if (!WkNavOk && WkBestDist != "" && WkBestDist <= NearDist && A_TickCount - WkLastRead > 1000)
		{
		;Was close and now the number won't read (Windows OCR misses lone digits): we're at the goal
		StartTalk("?")
		return true
		}
	else if (A_TickCount - WkLastRead > UnreadLimit)
		{
		;No number has read since the arrow came back (after a battle, a hidden arrow or a restart):
		;a lone digit, which Windows OCR misses - so the goal is under 10 away. Treat it as arrived
		if (WkBestDist = "" && !WkNavOk)
			{
			WkBestDist := 9
			StartTalk("?")
			return true
			}
		if (KeysDown)
			ReleaseKeys(true)
		SetStatus("waiting - can't read the distance on the arrow")
		WkBestTime := A_TickCount
		Sleep(300)
		return true
		}
	;The camera swings round after the wizard about half a second late (measured 2026-10-16: a 62
	;degree turn showed on screen 0.35-0.47 s after the key came up), so right after a turn the arrow
	;still shows part of it. Steering on that turns too far again - the zig-zags and circles. Wait for
	;it, walking on (or standing) as before. (Steering by the game's memory: it knows the facing at once)
	if (!WkNavUse && A_TickCount - WkTurnAt < WalkSettle())
		{
		;(after a turn on the spot of up to 70 degrees: walking on meanwhile - it faces about the right way)
		if (!HeldW && WkSpotTurn != "" && WkSpotTurn = WkTurnAt && !(WkNavOk && IsObject(WkNavObj) && WkNavObj.blindahead != ""))
			HoldW(1)
		Sleep(50)
		return true
		}
	;Arrow pushed up by the talk prompt (next to an NPC): the prompt slides in and out, so readings
	;jump. Only act once two readings agree, and don't fine-steer - just walk until clear of the NPC
	fine := true
	if (moved && !WkNavUse)
		{
		stable := (WkPrevMovedH != "" && Abs(ArrowWrap(h - WkPrevMovedH)) <= 30)
		WkPrevMovedH := h
		if (!stable)
			{
			;(walking straight on past the NPC - not steered on a jumping arrow, not stopped)
			SetStatus("walking on - arrow moving (talk prompt?)")
			Sleep(50)
			WkBestTime := A_TickCount
			return true
			}
		fine := false
		}
	else
		WkPrevMovedH := ""
	;After getting round an obstacle, keep aiming a bit off to that side for a while
	steer := h
	if (A_TickCount < WkBiasUntil)
		steer := h + WkBias * (WkBiasUntil - A_TickCount) / BiasTime
	;(a big turn: on the spot - walking on, it would swing round an arc into walls, round NPCs and the goal. Three in a
	;row with no walking between: this one walking on - WkSpins)
	WkSpins := WkSpins ? WkSpins : 0
	;(getting out of a mob's reach or sight: standing still turning in it is how it catches the wizard (the logs) - the way
	;out behind: backed straight out, a moment at a time; else turned walking on)
	escaping := (WkNavUse || WkNavByArrow) && IsObject(WkNavObj) && WkNavObj.escape != "" && (WkNavOk || A_TickCount - WkNavEscAt < 1500)
	;(going to and fro - what it steers at flipping end for end: WalkFroNote - the course held, small corrections only;
	;the stuck watch below goes on counting meanwhile)
	;(v1: WkFroUntil blank till the first to-and-fro - a number < blank compared as text, false)
	if (V1Lt(A_TickCount, WkFroUntil) && !escaping && Abs(steer) > TurnInPlace)
		steer := 0, fine := false
	else if (Abs(steer) >= 140 && !escaping && WalkFroNote(dist, hRaw))
		{
		StartTalk(dist)
		return true
		}
	;(the third hold in a minute - WalkFroNote's WkFroStuck: stuck in this very step, the turn not made - a turn resets the watch.
	;2026-10-26 15:00:28, 15:07:37 "taken as stuck", then a 169 / 173 degree turn and no Unstick)
	if (WkFroStuck && !escaping)
		steer := 0, fine := false
	;(two back-outs in a row that hardly moved it - a wall behind: turned walking on instead)
	if (escaping && Abs(steer) > 120 && WkNavOk && WkNavObj.x != "")
		{
		;(v1: blank += 1 on a line of its own counted the blank as 0)
		if (WkBackOutX != "" && Sqrt((WkNavObj.x - WkBackOutX) ** 2 + (WkNavObj.y - WkBackOutY) ** 2) < 20)
			WkBackOutStill := V1N(WkBackOutStill) + 1
		else
			WkBackOutStill := 0
		WkBackOutX := WkNavObj.x, WkBackOutY := WkNavObj.y
		}
	;(the way out behind: turned toward it by the mouse - running, MouseTurn; standing, MouseStandTurn - and run on out,
	;not turned back toward the mob (2026-10-24: no S key, the mouse is the steadier); the mouse can't: backed out with S)
	if (escaping && Abs(steer) > 120 && MsK != "" && (WkNavTrusted || WkNavChecked) && !(MsTriedAt && A_TickCount - MsTriedAt < 500)
		&& MouseSteerWhyNot(HeldW ? true : false, false, true) = "")
		{
		turned := MouseTurnAny(steer)
		if (turned != "" && !HeldW)
			HoldW(1, true)
		if (turned != "" && Abs(turned) >= 90)
			{
			SetStatus("turning out of " WkNavObj.escape "'s reach by the mouse - the way out is behind")
			if (!Walking)
				return false
			WkBestTime := A_TickCount
			return true
			}
		}
	;(another mob's reach behind - BackUp won't: turned walking on instead)
	;(v1: WkBackOutStill blank till the first back-out by the memory - blank < 2 compared as text, true)
	if (escaping && Abs(steer) > 120 && V1Lt(WkBackOutStill, 2) && BackUp(400))
		{
		SetStatus("backing out of " WkNavObj.escape "'s reach - the way out is behind")
		if (!Walking)
			return false
		WkBestTime := A_TickCount
		return true
		}
	;(by the game's memory: walking on round it - the helper's look round the wizard's turning circle says the arc's
	;clear of the walls and the aim's outside it - up to SpotTurnMem; nothing said about it, up to ArcBlind. Not while
	;aiming off after an obstacle. By the bare arrow - the camera lags, no walls known: on the spot over TurnInPlace)
	arcOk := (WkNavUse && IsObject(WkNavObj) && WkNavObj.arc != "") ? WkNavObj.arc : ""
	;(by the mouse - MouseSteer.ahk: the wizard turned at once, walking on, its arc looked at for the mouse's small circle:
	;up to 150 degrees with it clear, 100 with nothing said; the arc looked at for the mouse's circle is no use to A/D's)
	;(only once a count's worth is measured - the measuring isn't for a big turn walking on)
	;(and only with the wizard running a moment already - MouseSteerWhyNot's "just set off": a big turn from standing goes
	;the counted way, on the spot)
	;(getting out of a mob's reach too - turning on the spot there, or by A/D, is how it got caught: 2026-10-24)
	;(not sped up over 5x - MouseSteerWhyNot's slows false: the arc was looked at for the speed now, and dropping to 1x
	;first would take it past; the turns on the spot drop to 1x and take the mouse - Turn)
	msWalk := WkNavUse && steer = h && Abs(steer) > TurnInPlace && WkArcMouse && MsK != ""
		&& HeldW && WkWalkFrom && A_TickCount - WkWalkFrom >= 600
		&& ((arcOk = 1 && Abs(steer) <= 150) || (arcOk = "" && Abs(steer) <= 100)) && MouseSteerWhyNot(false) = ""
	walkTurn := msWalk || (WkNavUse && steer = h && SpeedNow <= 5 && Abs(steer) <= SpotTurnMem
		&& ((arcOk = 1 && !WkArcMouse) || (arcOk = "" && Abs(steer) <= ArcBlind)))
	if (Abs(steer) > TurnInPlace && WkSpins < 3 && !escaping && !walkTurn)
		{
		WkSpins += 1
		HoldW(0)
		SetStatus("turning " (steer < 0 ? "left " : "right ") Round(Abs(steer)) " degrees")
		WkMet.spot += 1
		Turn(steer)
		WkSpotTurn := Abs(steer) <= 70 ? WkTurnAt : ""
		if (!Walking)
			return false
		;(the camera's wait is the arrow's - the game's memory knows the facing at once)
		if (!WkNavUse)
			Sleep(150)
		WkBestTime := A_TickCount
		;Turning doesn't count against the unreadable-distance timers, except next to the goal: there
		;the wizard keeps walking over the goal point and turning back, which would put them off forever
		if (WkBestDist != "" && WkBestDist > NearDist)
			WkLastRead := A_TickCount
		return true
		}
	;(steering by the bare arrow - no route to keep to: it walks the game's straight way - and a mob's reach or sight is on
	;it (the helper's blind check): stand till there's a route to keep to or the mob's off it, 20 s at most, then on)
	;(the timer goes with its mob - another one ahead: its own 20 s; not while in another mob's reach: moving on)
	if (!(WkNavUse && WkNavRouted) && !WkNavByArrow && WkNavOk && IsObject(WkNavObj) && WkNavObj.blindahead != "" && WkNavObj.blindin = "")
		{
		if (!WkBlindAt || WkBlindMob != WkNavObj.blindahead)
			{
			WkBlindAt := A_TickCount, WkBlindMob := WkNavObj.blindahead
			WalkLog(WkNavObj.blindahead "'s reach or sight is on the arrow's straight way, and there's no route to keep to - waiting for one, or for it to move off (20 s at most)")
			}
		if (A_TickCount - WkBlindAt < 20000)
			{
			if (KeysDown || HeldW)
				ReleaseKeys(true)
			;(the wait puts the stuck watch off - a to-and-fro taken as stuck in this step too: WkFroStuck is this step's only)
			WkBestTime := A_TickCount, WkLastRead := A_TickCount, WkFroStuck := 0
			SetStatus("waiting - " WkNavObj.blindahead " ahead on the arrow's way (no route to keep to)")
			Sleep(300)
			return true
			}
		}
	;(a missed reading isn't "nothing ahead")
	else if (WkNavOk)
		WkBlindAt := 0, WkBlindMob := ""
	;(a small turn: walking on - W stays down while A/D turns the wizard; a big one after three on the spot too)
	;(a big turn walking on: no speed key first - the wizard would walk on past where the helper looked at the arc)
	HoldW(1, Abs(steer) > TurnInPlace)
	WkSpotTurn := ""
	if (Abs(steer) > TurnInPlace)
		{
		SetStatus("walking - turning " (steer < 0 ? "left " : "right ") Round(Abs(steer)) " degrees on the move" (msWalk ? " (by the mouse)" : walkTurn ? (arcOk = 1 ? " (its arc clear of walls)" : "") : " (" WkSpins " turns on the spot in a row)"))
		WkMet.walkturns += 1
		;(by the mouse; it couldn't after all - A/D's wide arc isn't looked at: stopped, and turned on the spot)
		if (msWalk && MouseTurn(steer) = "")
			{
			HoldW(0)
			WkMet.spot += 1
			Turn(steer)
			}
		else if (!msWalk)
			Turn(steer)
		WkBestTime := A_TickCount
		}
	;(sped up, the shortest key press (30 ms) turns more than a small correction: smaller ones are left. By the game's
	;memory a narrower band - it knows the facing; by the mouse when it may)
	else if (fine && Abs(steer) > Max(WkNavUse ? AheadMem : AheadAngle, TurnRate * 30 * (SpeedNow ? SpeedNow : 1)))
		{
		if (!WkNavUse || MouseTurn(steer) = "")
			Turn(steer)
		}
	WkSpins := 0
	if (!Walking)
		return false
	SetStatus("walking - " (WkNavUse ? "heading " : "arrow ") Round(h) " degrees, distance " (dist = "" ? "?" : dist) (steer != h ? " (keeping clear of the obstacle)" : "") (fine ? "" : " (talk prompt showing)")
		. (standIn ? " (no arrow on screen - by the game's memory)" : WkNavUse && WkNavRouted ? " (on the route round walls)" : WkNavByArrow ? " (on the route round walls, by the arrow)" : WkNavUse ? " (game's memory)" : ""))
	;Is the wizard actually moving? With W held, the picture moves along. Two looks in a row where it
	;has hardly changed = walking into something, so don't wait the full StuckTime
	still := WalkStill()
	if (still != "")
		WkStill := (still && dist != "") ? WkStill + 1 : 0
	;(by the game's memory - its place read a moment ago, WalkMoveState: walking on the way it faces all the while, within
	;StuckTime - is stuck only once it's MovingStuckTime no closer, along the route or straight: going round a wall gets no closer
	;for a while; and a picture that hardly changes isn't the wizard standing while it walks on. Not walking on by it - W held into
	;a wall, or sliding sideways along one: stuck as before; no memory: as before)
	mvState := WalkMoveState()
	if (mvState = 2)
		WkStill := 0
	;(going to and fro a third time in a minute: stuck now - WalkFroNote; this step's only - getting out of a mob's reach puts the
	;stuck watch off, as the blind wait above does)
	froStuck := WkFroStuck && !escaping, WkFroStuck := 0
	slowStuck := froStuck || A_TickCount - WkBestTime > (mvState >= 1 ? MovingStuckTime : StuckTime)
	stillStuck := WkStill >= 2 && A_TickCount - WkBestTime > FastStuckTime
	;(not moving: a quest offer's window up holds the wizard still - accepted, not counted as stuck)
	if ((slowStuck || stillStuck) && WalkAcceptQuest("the wizard isn't moving"))
		return Walking ? true : false
	if (slowStuck || stillStuck)
		{
		zone := WalkZone()
		stuckAt := WkBestDist != "" ? WkBestDist : dist
		;The last try didn't get round: if that was a remembered way, it's trusted less now (and isn't
		;tried again straight away)
		memFailed := false
		if (IsObject(WkEsc))
			{
			if (WkEsc.mem && A_TickCount - WkEsc.at <= 20000)
				WalkMemLearn(WkEsc.zone, WkEsc.dist, WkEsc.side, WkEsc.walkMs, false), memFailed := true
			WkEsc := ""
			}
		;(the distance now - the closest ever can be elsewhere: 2026-10-25 11:28:58 "stuck 6 from the goal" at 23, a shop
		;holding the wizard)
		nowAt := dist != "" ? dist : stuckAt
		;(a window over the game - a shop X opened that Escape didn't close - holds him: its close button, not stuck. 2026-10-25
		;11:29:18 Unstick straight after it was closed, walking off from Edith Benchley)
		if (WalkCloseWindow("not moving - a window open over the game?"))
			{
			WkBestTime := A_TickCount, WkLastRead := A_TickCount, WkStill := 0, WkSnapPrev := ""
			return Walking ? true : false
			}
		;Stuck right by the goal: the thing itself is in the way (an item on a table, someone behind a
		;counter) - going round it only walks away. It's arrived: X, once per goal (WalkStuckNear: by the game's
		;memory within TalkUnits; X done already - waiting there)
		stuckNear := WalkStuckNear(nowAt)
		if (stuckNear = "talk")
			{
			WkStuckNearDone := 1
			WalkLog("stuck " nowAt " from the goal" WalkGoalSay() " - the goal itself in the way? Arrived: X")
			StartTalk(nowAt, false)
			if (WkArrived = 2)
				WkStuckTalk := 1
			return true
			}
		if (stuckNear = "wait")
			{
			if (KeysDown || HeldW)
				ReleaseKeys()
			WkArrived := 1, WkFar := 0, WkArrDist := nowAt, WkArrGoal := ""
			WalkLog("stuck " nowAt " from the goal" WalkGoalSay() " after X there - not going round it (it walks away): waiting for the next goal")
			SetStatus("arrived (by the goal) - waiting for the next goal")
			return true
			}
		;(AutoFarmer's Puzzle.ahk: held against something - not walking on by the game's memory - is a blocked way's evidence; it may
		;take over)
		if (mvState <= 0 && V1IsFunc("PuzzleEvidence") && %"PuzzleEvidence"%.Call("stuck", ""))
			return true
		if (WkTries >= UnstickTries)
			{
			;(a give-up point: counted - once an episode, whatever takes over)
			WalkBadlyStuck("obstacle", "couldn't get round an obstacle in " UnstickTries " tries")
			;(Puzzle.ahk: what usually opens a blocked way tried first - inside a dungeon the Commons would leave it)
			if (V1IsFunc("PuzzleBeforeNotice") && %"PuzzleBeforeNotice"%.Call("stuck", "couldn't get round an obstacle in " UnstickTries " tries"))
				return true
			;(what the game showed, to see what held it - AutoFarmer: Windows temp, "Wizard101 bot rounds")
			stuckPic := V1IsFunc("SaveRoundPicture") ? %"SaveRoundPicture"%.Call() : ""
			WalkLog("stuck: gave up after " UnstickTries " tries" (stuckPic != "" ? " (the game's picture: " stuckPic ")" : ""))
			if (WalkCommonsReset("couldn't get round an obstacle in " UnstickTries " tries", stuckAt))
				return true
			Walking := 0
			ReleaseKeys()
			SetStatus("stuck - couldn't get around the obstacle. Move the wizard a bit and press " WalkKeyText())
			WalkNotify("stuck", "Stuck", "The wizard couldn't get round an obstacle (" (stuckAt = "" ? "?" : stuckAt) " from the goal) and the teleport to the Commons didn't help (used in the last " Round(ResetEvery / 60000) " minutes, or not possible here), so walking is off. Move it a bit and press " WalkKeyText() " to walk again.")
			return false
			}
		SetStatus("stuck - backing up and going around (try " WkTries + 1 " of " UnstickTries ")")
		;Each try walks further along the obstacle, on alternate sides, then keeps aiming off to that
		;side. The first try at an obstacle remembered from before goes the way that worked then
		walkMs := 900 * (WkTries + 1)
		walkMs := walkMs > 3600 ? 3600 : walkMs
		side := WkSide, fromMem := false
		spot := (WkTries = 0 && !memFailed && zone != "" && stuckAt != "") ? WalkMemFind(zone, stuckAt) : ""
		if (IsObject(spot))
			side := spot.side, walkMs := spot.walkMs, fromMem := true
		;(close to the goal by the game's memory: a short walk along the obstacle, not off away from the goal)
		gnStuck := WalkGoalNear()
		if (IsObject(gnStuck) && gnStuck.r <= ApproachUnits && walkMs > 900)
			walkMs := 900
		;(which watch it was - by the game's memory: walking on all the while, or not walking on either; and what its place did:
		;WalkMoveSay - the stucks of 2026-10-26 14:33 and 15:05 had the route's progress counted and the picture still, the wizard
		;held by something no one could see)
		stuckWhy := froStuck ? "going to and fro a third time in a minute" : slowStuck ? (mvState >= 1 ? "walking on but no closer for " Round(MovingStuckTime / 1000) " s - the game's memory" : "no closer in " Round(StuckTime / 1000) " s") : "picture not moving: " WkMotion " changed"
		if (mvState = 0)
			stuckWhy .= " - not walking on by the game's memory either"
		;(a stuck episode begins - its time lost from when it last got closer: the stall before this first try -, or goes on; the
		;route's way left only when steering on it - onRoute isn't set this step with no distance read)
		WalkLostTry(stuckWhy, Min(A_TickCount - WkBestTime, MovingStuckTime + 5000), stuckAt, (WkNavUse && WkNavRouted && WkNavLeft != "") ? WkNavLeft : "")
		WalkLog("stuck at distance " (nowAt = "" ? "?" : nowAt) " (" stuckWhy "): try " WkTries + 1 " - back up, turn " UnstickTurn " degrees " (side > 0 ? "right" : "left") ", walk " walkMs " ms" (fromMem ? " (the way that worked here before)" : "") WalkMoveSay())
		Unstick(side, walkMs)
		WkEsc := V1Obj({zone: zone, dist: stuckAt, side: side, walkMs: walkMs, mem: fromMem, at: A_TickCount})
		WkBias := UnstickBias * side, WkBiasUntil := A_TickCount + BiasTime
		WkSide := -side, WkTries += 1
		WkBestTime := A_TickCount, WkLastRead := A_TickCount, WkStill := 0, WkSnapPrev := ""
		;(the back-up, the turn and the walk along it are the bot's own: not the wizard walking on - the watch starts over)
		WalkMoveReset()
		if (!Walking)
			return false
		}
	Sleep(50)
	return true
	}

;True if the distance has clearly changed from was (the wizard was standing still, so it's a new
;goal). Lone digits misread easily (5 / 9, 3 / 8), so one of the two has to be 10 or more
DistChanged(dist, was)
	{
	if (dist = "" || was = "" || was = "?")
		return false
	return Abs(dist - was) > 3 && (dist >= 10 || was >= 10)
	}

;At the goal: stop, press X (talk / use), then WalkStep presses Space through the dialogue. door: at the
;way out of this zone (the game's memory says so) walk on into it instead (not when stuck by the goal)
StartTalk(d, door := true)
	{
	global WkArrived, WkBestTime, WkLastRead, WkNavDoor, WkTalk, WkFar, WkNear, WkDialog, WkTalkDist, WkTalkAt, WkTalkGoal ; (v1 globals it sets)
	global WkPreXText, WkAfterXLooked, WkLastX ; (v1 globals it sets)
	;(a goal the game shows no way to - WkNavNoPlace - has no "at it": no X at nothing (2026-10-25 "Use Inactive Protector": X, then a
	;push, then waiting there for good) - its kind's own way instead (CollectNoPlace); a talk goal's NPC found by name standing in
	;for its place - TalkStep - is X'd as any talk goal's)
	if (WkNavNoPlace && !(IsObject(WkNpTarget) && WkNpGoal != "" && WkNpTarget.goalid "|" = WkNpGoal "|"))
		{
		WalkLog("talk: the game shows no way to this goal - no X at " (d = "" ? "?" : d) " (its kind's own way instead)")
		if (KeysDown || HeldW)
			ReleaseKeys(true)
		WkArrived := 0, WkBestTime := A_TickCount, WkLastRead := A_TickCount
		return
		}
	;A World Gate's prompt: Go To World instead. A sigil's: enter it and wait (read walking on - each of those stops
	;itself; a way out of the zone is walked straight on into)
	prompt := InteractPrompt()
	if (prompt = "gate")
		{
		StartGate("at the goal (distance " d ") and it's a World Gate")
		return
		}
	;(through the one gate for every X at a sigil - WalkSigilMayX: StartTalk's X - on top of the goal, by it, pushing, the distance
	;unread - went round WalkSigilGo's 10 minutes before, a dead sigil X'd every ~30 s: the 21:44 case's likely way. Not now: standing
	;by it, the watches put off - asked again each step, so X comes once the gate lets it)
	if (prompt = "sigil")
		{
		stNo := WalkSigilMayX()
		if (stNo != "")
			{
			if (!WkPromptUsed.Has("sigilno") || A_TickCount - WkPromptUsed["sigilno"] > 30000)
				WkPromptUsed["sigilno"] := A_TickCount, WalkLog("sigil: at the goal (distance " d "), no X - " stNo)
			if (KeysDown || HeldW)
				ReleaseKeys(true)
			WkArrived := 0, WkBestTime := A_TickCount, WkLastRead := A_TickCount
			SetStatus("at a sigil, no X - " stNo)
			Sleep(400)
			return
			}
		StartSigil("at the goal (distance " d ") and it's a sigil", 1)
		return
		}
	;The game's memory says the goal is in another zone: this is the way out of this one (a door, a loading
	;point) - nobody to talk to, walk on into it straight away (no prompt showing: one asking for X gets X)
	;(v1: hops blank - an older helper's - > 0 compared as text, false)
	if (door && prompt = "" && WkNavOk && V1Gt(WkNavHops, 0))
		{
		WalkLog("talk: at the goal (distance " d ") - the game's memory says it's the way out of this zone (" WkNavHops " zone change" (WkNavHops = 1 ? "" : "s") " to the goal): no X")
		StartPush("the way out of this zone (the game's memory)", d)
		WkNavDoor := WkArrived = 3
		;(pushed twice here already - waiting: stopped)
		if (WkArrived != 3 && (KeysDown || HeldW))
			ReleaseKeys()
		return
		}
	;(a talk goal by the game's memory and another NPC's prompt up - a vendor beside it: no X at it. Closer to the goal's NPC
	;and facing it first; still another's: no X, a try used all the same - 3 and it waits by it (WalkTalkWait), not a loop.
	;2026-10-25 11:28:49: X at Bartholomew's prompt by Edith Benchley opened his shop)
	stGoal := WalkTalkGoal()
	if (prompt = "press" && StrLen(WkPromptDest) >= 4 && IsObject(stGoal) && stGoal.r <= TalkReach && (stGoal.dz = "" || Abs(stGoal.dz) <= 150)
		&& !WalkIsGoalNpc(WkPromptDest, stGoal))
		{
		if (stGoal.r > 150)
			WalkApproach(120)
		if (!Walking)
			return
		stGoal := WalkTalkGoal()
		if (IsObject(stGoal) && Abs(stGoal.h) > 20 && GameActive())
			NavTurn(stGoal.h)
		if (Walking && IsObject(stGoal) && InteractPrompt() = "press" && StrLen(WkPromptDest) >= 4 && !WalkIsGoalNpc(WkPromptDest, stGoal))
			{
			WalkTalkCount()
			WalkLog("talk: the prompt up is '" SubStr(WkPromptDest, 1, 30) "', not " (stGoal.npc != "" ? stGoal.npc : "the goal's NPC") "'s - no X")
			WkArrived := 0, WkBestTime := A_TickCount, WkLastRead := A_TickCount
			return
			}
		}
	if (KeysDown || HeldW || SpeedNow > 1)
		ReleaseKeys()
	WkArrived := 2, WkTalk := 0, WkFar := 0, WkNear := 0, WkDialog := 0, WkTalkDist := d, WkTalkAt := A_TickCount
	;(the goal's id now - a new one after is the talk done: WalkStep; a talk goal's tries counted - WalkTalkTriesLeft)
	WkTalkGoal := (WkNavOk && IsObject(WkNavObj)) ? WkNavObj.goalid : ""
	WalkTalkCount()
	;(what's on screen before X: what X opens is what's new - WalkCloseAfterX, in the talk step)
	WkPreXText := WalkAfterXText(&stPre), WkAfterXLooked := 0
	PressKey("x"), WkLastX := A_TickCount
	WalkLog("talk: at the goal (distance " d WalkGoalSay() "), pressed X")
	SetStatus("talking - pressed X at the goal (distance " d ")")
	Sleep(600)
	}

;Walk on into the goal (doorway / loading point), at most twice for the same goal
StartPush(why, d)
	{
	global WkNavDoor, WkArrived, WkFar, WkBestTime, WkLastRead, WkArrDist, WkPushes, WkStraight, WkPushStart, WkPushUntil ; (v1 globals it sets)
	WkNavDoor := 0
	;(a goal the game shows no way to - WkNavNoPlace: no doorway to push into, no waiting there - its kind's own way instead)
	if (WkNavNoPlace && !(IsObject(WkNpTarget) && WkNpGoal != "" && WkNpTarget.goalid "|" = WkNpGoal "|"))
		{
		WalkLog("push: " why " - the game shows no way to this goal: no pushing on (its kind's own way instead)")
		if (KeysDown || HeldW)
			ReleaseKeys(true)
		WkArrived := 0, WkFar := 0, WkBestTime := A_TickCount, WkLastRead := A_TickCount
		return
		}
	if (WkPushes >= 2)
		{
		;(AutoFarmer's Puzzle.ahk: the way out of this zone pushed into twice and it didn't load - a blocked way's evidence; it may
		;take over)
		;(v1: hops blank - an older helper's - > 0 compared as text, false)
		if (WkNavOk && V1Gt(WkNavHops, 0) && V1IsFunc("PuzzleEvidence") && %"PuzzleEvidence"%.Call("door", ""))
			return
		WalkLog("push: " why " - already pushed twice here, waiting for the next goal")
		WkArrived := 1, WkFar := 0, WkArrDist := (d = "?" ? "" : d)
		SetStatus("arrived - waiting for the next goal")
		return
		}
	WkPushes += 1, WkArrived := 3, WkFar := 0, WkStraight := 0
	WkPushStart := A_TickCount, WkPushUntil := A_TickCount + PushTime
	WalkLog("push: " why " (distance " (d = "" ? "?" : d) ") - walking on into it, try " WkPushes)
	SetStatus("pushing on - walking into the goal (doorway or loading point?)")
	}

;The arrow led to a World Gate (its prompt is showing): stop and press X to open the Spiral Map,
;then GateStep clicks Go To World
StartGate(why)
	{
	global WkArrived, WkGateAt, WkGateClicks, WkGateX ; (v1 globals it sets)
	if (KeysDown || HeldW || SpeedNow > 1)
		ReleaseKeys()
	WkArrived := 4, WkGateAt := A_TickCount, WkGateClicks := 0, WkGateX := 1
	PressKey("x")
	WalkLog("gate: " why " - pressed X")
	SetStatus("World Gate - pressed X, waiting for the Spiral Map")
	Sleep(800)
	}

;A "Press X ..." prompt on the way: stop, press X, then WalkStep (WkArrived = 6) presses Space
;through whatever it opens and walks on
StartPressX(key)
	{
	global WkArrived, WkPressAt, WkTalk, WkDialog, WkSpaceAt, WkAfterXLooked, WkArrowAtX, WkPreXText, WkLastX ; (v1 globals it sets)
	if (KeysDown || HeldW || SpeedNow > 1)
		ReleaseKeys()
	WkPromptUsed[key = "" ? "?" : key] := A_TickCount
	WkArrived := 6, WkPressAt := A_TickCount, WkTalk := 0, WkDialog := 0, WkSpaceAt := 0, WkAfterXLooked := 0
	WkArrowAtX := (WkRealSeenAt && A_TickCount - WkRealSeenAt < 1500)
	;(what's on screen before X: what X opens is what's new - WalkCloseAfterX)
	WkPreXText := WalkAfterXText(&preLines)
	;(the talk goal's own NPC: a try at it - WalkTalkTriesLeft)
	tgX := WalkTalkGoal()
	if (IsObject(tgX) && WalkIsGoalNpc(key, tgX))
		WalkTalkCount()
	PressKey("x"), WkLastX := A_TickCount
	WalkLog("prompt '" SubStr(key, 1, 40) "' - pressed X" WalkGoalSay())
	SetStatus("pressed X at a prompt")
	Sleep(400)
	}

;True if that prompt hasn't been used (X pressed) in the last ms. The key is the prompt's letters as
;OCR read them, which can come out a little different each time: nearly the same letters count as the
;same prompt
WalkPromptFree(key, ms)
	{
	key := (key = "") ? "?" : key
	for used, at in WkPromptUsed
		if (A_TickCount - at <= ms && (used = key || (StrLen(key) > 6 && WalkEditDistance(used, key) <= StrLen(key) // 4)))
			return false
	return true
	}

;Spaces through an open dialogue box every SkipGap ms, looking again every 4 presses, until it's gone
;(at most 80). Counts as the dialogue the talking / pressed-X steps are waiting for, and starts the
;no-X time after it (DialogQuiet)
WalkSkipDialog()
	{
	global WkDlgEndAt, WkAcceptLooks, WkAcceptClicks, WkDialog, WkTalk, WkSpaceAt, WkQuietUntil, WkQuietLogged, WkBestTime ; (v1 globals it sets)
	global WkLastRead ; (v1 globals it sets)
	if (KeysDown || HeldW || SpeedNow > 1)
		ReleaseKeys()
	presses := 0, acc := ""
	Loop 80
		{
		PressKey("Space"), presses += 1
		Sleep(SkipGap)
		if (!Walking)
			return false
		;(no NEXT / DONE any more: closed - or its last page is a quest offer, its button ACCEPT)
		if (Mod(A_Index, 4) = 0 && !WalkDialogOpen())
			{
			acc := WalkDialogAccept()
			break
			}
		}
	WalkLog("dialogue: skipped with " presses " Space presses" (IsObject(acc) ? " - its last page a quest offer" : ""))
	SetStatus("dialogue skipped (" presses " Space presses)")
	if (IsObject(acc) && Walking && GameActive())
		{
		WalkLog("quest offer: ACCEPT in the dialogue box - clicking it at " acc.x - GameLeft "," acc.y - GameTop)
		SetStatus("accepting the quest")
		WalkClick(acc.x, acc.y)
		Sleep(700)
		}
	;(a quest-giver's: the quest offer comes up after it - its ACCEPT clicked; looked for again a while: WalkStep)
	Sleep(300)
	if (Walking)
		WalkAcceptQuest("after the dialogue")
	;(a new offer may follow: its own clicks)
	WkDlgEndAt := A_TickCount, WkAcceptLooks := 0, WkAcceptClicks := 0
	WkDialog := 1, WkTalk += presses, WkSpaceAt := A_TickCount
	WkQuietUntil := A_TickCount + DialogQuiet, WkQuietLogged := 0
	WkBestTime := A_TickCount, WkLastRead := A_TickCount
	return true
	}

;A quest offer's ACCEPT button (the window a quest-giver opens after the dialogue - Space doesn't take it, and the
;wizard can't walk while it's up), read by OCR over the middle of the game: {x, y} on the screen, or "" - never in a
;window that says anything about Crowns, or that's a friend / trade / teleport / group request or a duel
WalkAcceptButton()
	{
	;(the middle of the game, then its lower part bigger - a button's coloured letters read better larger)
	;(the second down to the bottom: a dialogue box's own ACCEPT is in its button row there)
	for pass, f in [[0.8, 0.07, 0.86], [0.6, 0.45, 0.55]]
		{
		readW := Round(GameW * f[1]), readH := Round(GameH * f[3])
		acceptLines := ""  ; (v1: a ByRef output OcrRect may leave unset was blank)
		t := OcrRect(Round(GameLeft + (GameW - readW) / 2), Round(GameTop + GameH * f[2]), readW, readH, "en", Min(pass = 1 ? 2 : 3, 2500 / readW), &acceptLines)
		;(anything about Crowns anywhere: never)
		if (ErrorLevel || !IsObject(acceptLines) || RegExMatch(t, "i)cr[o0]wn"))
			return ""
		;(a button: the word on a short line - ACCEPT and DECLINE side by side can read as one)
		btn := ""
		for each, line in acceptLines
			{
			if (!IsObject(line.words) || line.words.Length > 3)
				continue
			for each, word in line.words
				if (btn = "" && RegExMatch(word.text, "i)^\W*ACC?E[PF]T\W*$"))
					btn := V1Obj({x: Round(word.x + word.w / 2), y: Round(word.y + word.h / 2)})
			}
		if (btn = "")
			continue
		;(its window: the lines just above the button and on its row, hugging it - a quest offer says so (DECLINE beside
		;it, or quest / reward / experience / gold words); a friend, trade, teleport or group request never)
		;(in the dialogue box's button row at the bottom - a quest-giver's offer as the dialogue's last page - with no
		;request's words anywhere in what was read)
		offer := (btn.y > GameTop + GameH * 0.85) && !RegExMatch(t, "i)friend request|be your friend|would like to|wants? to (trade|duel|teleport|join)|invit(e|es|ed) you|teleport to|join (my|your|the|a|our) (group|team|party)|party invit")
		for each, line in acceptLines
			{
			cy := line.y + line.h / 2
			if (cy < btn.y - GameH * 0.35 || cy > btn.y + GameH * 0.05 || Abs(line.x + line.w / 2 - btn.x) > GameW * 0.2)
				continue
			if (RegExMatch(line.text, "i)friend request|be your friend|would like to|wants? to (trade|duel|teleport|join)|invit(e|es|ed) you|teleport to|join (my|your|the|a|our) (group|team|party)|party invit"))
				return ""
			if (RegExMatch(line.text, "i)\bDECLINE\b|\bquest\b|\breward|experience|\bXP\b|\bgold\b"))
				offer := true
			}
		if (offer)
			return btn
		;(not an offer it can tell: nothing - the next pass, or the next look)
		continue
		}
	return ""
	}

;The quest offer's ACCEPT clicked if it's up (why: for the log). True if it was
WalkAcceptQuest(why)
	{
	global WkAcceptClicks, WkAcceptAt, WkBestTime, WkLastRead, WkStill ; (v1 globals it sets)
	;(this offer clicked twice already in the last 20 s: no more - the stuck / Escape / notice ways carry on)
	;(v1: both blank till the first click - blank >= 2 compared as text false; A_TickCount - blank blank, >= 20000 false)
	if (V1Ge(WkAcceptClicks, 2) && V1Lt(V1Ago(WkAcceptAt), 20000))
		return false
	if (V1Ge(V1Ago(WkAcceptAt), 20000))
		WkAcceptClicks := 0
	btn := WalkAcceptButton()
	if (!IsObject(btn) || !Walking || !GameActive())
		return false
	if (KeysDown || HeldW || SpeedNow > 1)
		ReleaseKeys()
	if (!WkAcceptClicks)
		WkAcceptAt := A_TickCount
	WkAcceptClicks := V1N(WkAcceptClicks) + 1  ; (v1: blank += 1 - 1)
	WalkLog("quest offer: ACCEPT showing (" why ") - clicking it at " btn.x - GameLeft "," btn.y - GameTop (WkAcceptClicks > 1 ? " (again)" : ""))
	SetStatus("accepting the quest")
	WalkClick(btn.x, btn.y)
	Sleep(700)
	WkBestTime := A_TickCount, WkLastRead := A_TickCount, WkStill := 0
	return true
	}

;The dialogue box's own ACCEPT - a quest-giver's offer as the dialogue's last page (Space doesn't take it, and with no
;NEXT / DONE the box looks closed to WalkDialogOpen): {x, y} on the screen, or "" - never with "Crown" read in the box
;or the offer's window above it
WalkDialogAccept()
	{
	s := ArrowScale().scale
	lines := ""  ; (v1: a ByRef output OcrRect may leave unset was blank)
	t := OcrRect(Round(GameLeft + GameW / 2 - 480 * s), Round(GameTop + GameH - 170 * s), Round(960 * s), Round(168 * s), "en", 1, &lines)
	;(nor a friend / trade / teleport / group request or a duel - as WalkAcceptButton)
	if (ErrorLevel || !IsObject(lines) || RegExMatch(t, "i)cr[o0]wn")
		|| RegExMatch(t, "i)friend request|be your friend|would like to|wants? to (trade|duel|teleport|join)|invit(e|es|ed) you|teleport to|join (my|your|the|a|our) (group|team|party)|party invit"))
		return ""
	btn := ""
	for i, line in lines
		for j, word in line.words
			if (btn = "" && RegExMatch(word.text, "i)^\W*ACC?E[PF]T\W*$"))
				btn := V1Obj({x: Round(word.x + word.w / 2), y: Round(word.y + word.h / 2)})
	if (!IsObject(btn))
		return ""
	;(the offer's window above the box - the quest's name, what to do, its rewards: no Crowns there either)
	t := OcrRect(Round(GameLeft + GameW * 0.2), Round(GameTop + GameH * 0.3), Round(GameW * 0.6), Round(GameH * 0.6), "en", 1)
	return (ErrorLevel || RegExMatch(t, "i)cr[o0]wn")) ? "" : btn
	}

;True if a dialogue box is open at the bottom of the game: its DONE / NEXT / BACK / MORE buttons, read by OCR
WalkDialogOpen()
	{
	s := ArrowScale().scale
	t := OcrRect(Round(GameLeft + GameW / 2 - 480 * s), Round(GameTop + GameH - 170 * s), Round(960 * s), Round(168 * s))
	return !ErrorLevel && RegExMatch(t, "\b(DONE|D0NE|NEXT|BACK|MORE)\b")
	}

;A turn of 140 degrees or more about to be made (WalkStep): three of them in 12 s with the wizard no further on (within 500
;units - the game's memory - else the distance within a tenth) is going to and fro: what it steers at flipping end for end
;(2026-10-23 07:29: 30 a minute, 175 degrees each, for minutes - each turn put the stuck watch off). Then: by the goal
;(within NearDist on the arrow, twice ArriveUnits by the memory) - it's there: true (StartTalk); else the course held 5 s
;(WkFroUntil), and the third hold in a minute is taken as stuck (got round as any obstacle). Logged with what it steered by
WalkFroNote(d, hRaw)
	{
	global WkFroTurns, WkFroHolds, WkFroUntil, WkBestTime, WkFroStuck ; (v1 globals it sets)
	if (!IsObject(WkFroTurns))
		WkFroTurns := []
	if (!IsObject(WkFroHolds))
		WkFroHolds := []
	fx := (WkNavOk && IsObject(WkNavObj)) ? WkNavObj.x : "", fy := (WkNavOk && IsObject(WkNavObj)) ? WkNavObj.y : ""
	WkFroTurns.Push(V1Obj({at: A_TickCount, x: fx, y: fy, d: d}))
	keep := []
	for each, ft in WkFroTurns
		if (A_TickCount - ft.at <= 12000)
			keep.Push(ft)
	WkFroTurns := keep
	if (keep.Length < 3)
		return false
	f1 := keep[1]
	if (fx != "" && f1.x != "")
		moved := Sqrt((fx - f1.x) ** 2 + (fy - f1.y) ** 2) > 500
	else
		moved := (d != "" && f1.d != "" && f1.d > 0) ? Abs(d - f1.d) > f1.d * 0.1 : false
	if (moved)
		return false
	WkFroTurns := []
	by := WkNavUse ? (WkNavRouted ? "the route's aim" : "the game's memory") : WkNavByArrow ? "the arrow and the route" : "the arrow"
	what := keep.Length " turns of 140 degrees or more in " Round((A_TickCount - f1.at) / 1000) " s, no further on - by " by " (the arrow " (hRaw = "" ? "not seen" : Round(hRaw)) ", the memory " (WkNavH = "" ? "-" : Round(WkNavH)) ")"
	if (WalkNear(d, NearDist, ArriveUnits * 2))
		{
		WalkLog("going to and fro by the goal: " what " - there")
		return true
		}
	WkFroUntil := A_TickCount + 5000
	keepH := []
	for each, at in WkFroHolds
		if (A_TickCount - at <= 60000)
			keepH.Push(at)
	keepH.Push(A_TickCount)
	WkFroHolds := keepH
	WalkLog("going to and fro: " what " - holding the course 5 s")
	if (keepH.Length >= 3)
		{
		WkFroHolds := []
		WkBestTime := A_TickCount - StuckTime - 1
		;(stuck in this same step - WalkStep: the turn this note came before would reset the watch, and the course held after it
		;walks on - the game's memory's longer watch)
		WkFroStuck := 1
		WalkLog("going to and fro a third time in a minute - taken as stuck")
		}
	return false
	}

;Coming out of a dungeon puts you on its sigil: not straight back in (for 90 s). The zone just left is that dungeon when
;the bot went in through a sigil (WkSigilZones), or - one you went into yourself - an interior while the quest's arrow
;doesn't lead to this sigil (near) or the game's memory says the goal's in this zone. A house or shop left by its door
;with the goal through this sigil isn't: in
WalkSigilJustLeft(near)
	{
	if (WkZoneFrom = "" || A_TickCount - WkZoneAt >= 90000)
		return false
	if (IsObject(WkSigilZones) && WkSigilZones.Has(WkZoneFrom))
		return true
	if (!InStr(WkZoneFrom, "/Interiors/"))
		return false
	return !near || (WkNavOk && WkNavHops = 0)
	}

;A sigil's prompt showing (WalkStep): the why for X at it (StartSigil), or "" - no X. Not straight back into the dungeon just come
;out of (WalkSigilJustLeft - said once in 30 s), unless the quest's goal is in it: the game's memory had this goal in that zone
;(WalkGoalZone), or its route leads into this sigil (zone changes to go, and the teleporter to take - the memory's goal point then -
;within 300, the sigil the wizard's on: a door further off isn't it). Then X even within its 10 minutes: 2 minutes apart, 3 times in
;10 for the same dungeon - by its zone's name, not the prompt's OCR'd letters (they differ read to read); more: as any (said, no X).
;Any other: once in 10 minutes for the same one. 2026-10-26 16:08:11-16:09:14 "Defeat Karolak Nightspinner and Collect Celestian
;Portal in Stormriven": out of Celestia/Interiors/CL_Z06i1_StormHaven where he is - "just came out", 3 minutes outside, NEEDS YOU.
;goal: 1 when the X is the quest's way (back into the goal's dungeon, or the arrow led here - near), 0 a sigil only walked past
;(pressing X at every prompt): one that won't start is left or given up on only when it's the quest's way - WalkSigilCheck
WalkSigilGo(near, &goal := 0)
	{
	goal := near ? 1 : 0
	;(the one gate for every X at a sigil first - WalkSigilMayX: a sigil that didn't start, given up on; 3 X at its spot in 10 minutes)
	sgNo := WalkSigilMayX()
	if (sgNo != "")
		{
		if (!WkPromptUsed.Has("sigilno") || A_TickCount - WkPromptUsed["sigilno"] > 30000)
			WkPromptUsed["sigilno"] := A_TickCount, WalkLog("sigil: prompt showing, no X - " sgNo)
		return ""
		}
	sgIn := ""
	if (WkZoneFrom != "" && A_TickCount - WkZoneAt < 90000)
		{
		if (WalkSameZone(WalkGoalZone(), WkZoneFrom))
			sgIn := "the game's memory had this goal in it"
		;(hops blank - an older helper's: not zones away)
		else if (WkNavOk && IsObject(WkNavObj) && V1Gt(WkNavHops, 0) && WkNavObj.gx != "" && WkNavObj.gy != "" && WkNavObj.x != "" && WkNavObj.y != ""
			&& Sqrt((WkNavObj.gx - WkNavObj.x) ** 2 + (WkNavObj.gy - WkNavObj.y) ** 2) <= 300)
			sgIn := "the game's route leads into this sigil - " WkNavHops " zone change" (WkNavHops = 1 ? "" : "s") " to go, the way on " Round(Sqrt((WkNavObj.gx - WkNavObj.x) ** 2 + (WkNavObj.gy - WkNavObj.y) ** 2)) " off"
		}
	;(the times back into this dungeon - WkSigilTries' "zone:" key: WalkSigilTriesLeft keeps the last 10 minutes')
	sgKey := "zone:" WkZoneFrom
	if (sgIn != "" && IsObject(WkSigilTries) && WalkSigilTriesLeft(sgKey) && WalkPromptFree(WkPromptDest, 120000)
		&& !(WkSigilTries.Has(sgKey) && WkSigilTries[sgKey].Length && A_TickCount - WkSigilTries[sgKey][WkSigilTries[sgKey].Length] < 120000))
		{
		if (!WkSigilTries.Has(sgKey))
			WkSigilTries[sgKey] := []
		WkSigilTries[sgKey].Push(A_TickCount)
		goal := 1
		return "just came out of " WkZoneFrom " (its dungeon), and the quest's goal is in it (" sgIn ") - back in"
		}
	if (WalkSigilJustLeft(near))
		{
		if (!WkPromptUsed.Has("exitlog") || A_TickCount - WkPromptUsed["exitlog"] > 30000)
			WkPromptUsed["exitlog"] := A_TickCount, WalkLog("sigil: just came out of " WkZoneFrom " (its dungeon) - not going straight back in")
		return ""
		}
	return WalkPromptFree(WkPromptDest, 600000) ? "sigil prompt showing (" (near ? "the arrow led here" : "pressing X at every prompt") ")" : ""
	}

;The zone the quest's goal is in, by the game's memory. nav: WalkNav's usable reading - one with no zone change to go notes its
;goal's zone ({goal id: zone}); "" returned. None: the current goal's zone ("" not known - never read in its own zone)
WalkGoalZone(nav := "")
	{
	static gzOf := ""
	if (!IsObject(gzOf))
		gzOf := V1Obj()
	if (IsObject(nav))
		{
		if (nav.hops = 0 && nav.goalid != "" && nav.zone != "")
			gzOf[nav.goalid] := nav.zone
		return ""
		}
	gzId := (WkNavOk && IsObject(WkNavObj)) ? WkNavObj.goalid : IsObject(WkNavLast) ? WkNavLast.goalid : ""
	return (gzId != "" && gzOf.Has(gzId)) ? gzOf[gzId] : ""
	}

;Tries left at the sigil whose prompt key is key: 3 X presses in 10 minutes (the old ones dropped)
WalkSigilTriesLeft(key)
	{
	if (!IsObject(WkSigilTries) || !WkSigilTries.Has(key))
		return true
	recent := []
	for each, at in WkSigilTries[key]
		if (A_TickCount - at < 600000)
			recent.Push(at)
	WkSigilTries[key] := recent
	return recent.Length < 3
	}

;You've stopped playing (AutoFarmer's PlayerActing): the walker's watch starts afresh - but a sigil's or a boat's wait goes
;on (walking off a sigil stops its countdown)
WalkResume()
	{
	global WkArrived, WkSigilUntil, WkWaitWhat ; (v1 globals it sets)
	keepUntil := (WkArrived = 5 && A_TickCount < WkSigilUntil) ? WkSigilUntil : 0, keepWhat := WkWaitWhat
	WalkReset()
	if (keepUntil)
		WkArrived := 5, WkSigilUntil := keepUntil, WkWaitWhat := keepWhat
	;(held at a blocked way - AutoFarmer's Puzzle.ahk: still waiting there, not walked back into the gate)
	else if (V1IsFunc("PuzzleHeld") && %"PuzzleHeld"%.Call())
		WkArrived := 1
	}

;Walked right past the goal, by the game's memory: it was ahead and close, and is now behind and as close - its point a
;step off the ground (a sigil's: the distance never gets down to ArriveUnits, and the wizard goes to and fro over it) -
;or it came within 1.5 x ArriveUnits in the last 4 s, and is now 40 further than that (still within 2 x) and the goal's
;well behind. Counts as there: why ("" not). Called each step the goal's distance is looked at
WalkPassedGoal()
	{
	static prevH := "", prevD := "", prevAt := 0
	global WkPassKey, WkPassMin, WkPassAt ; (v1 globals it sets)
	if (!WkNavOk || !IsObject(WkNavObj) || WkNavObj.dist = "" || WkNavH = "")
		{
		prevH := "", prevD := ""
		return ""
		}
	;(the heading to the game's own target - WkNavH is the route's aim's once there's a route)
	nowH := WalkNavHeading(WkNavObj.x, WkNavObj.y, WkNavObj.yaw, WkNavObj.tx, WkNavObj.ty), nowD := WkNavObj.dist
	;(the goal in this zone: straight at the goal itself - the path's distance jumps by its nodes right by it; on the same floor
	;only - walked over or under it on a bridge or a balcony isn't past it: the path's distance then, which stays long)
	pgNear := WalkGoalNear()
	pgFlat := IsObject(pgNear) && (pgNear.dz = "" || Abs(pgNear.dz) <= 150)
	if (pgFlat)
		nowH := pgNear.h, nowD := pgNear.r
	if (nowH = "")
		return ""
	;(straight or the path's: a change between the two starts over - never compared with each other)
	pgKey := WkNavObj.zone "|" WkNavObj.goalid "|" WkNavObj.hops "|" Round(WkNavObj.tx / 50) "|" Round(WkNavObj.ty / 50) "|" pgFlat
	if (pgKey != WkPassKey)
		WkPassKey := pgKey, WkPassMin := "", prevH := ""
	passed := prevH != "" && A_TickCount - prevAt < 4000 && Abs(prevH) <= 45 && Abs(nowH) >= 135 && nowD <= ArriveUnits * 2 && prevD <= ArriveUnits * 2
	why := passed ? Round(nowD) " game units off, from ahead to behind - its point a step off the ground?" : ""
	if (why = "" && WkPassMin != "" && WkPassMin <= ArriveUnits * 1.5 && nowD >= WkPassMin + 40 && nowD <= ArriveUnits * 2
		&& A_TickCount - WkPassAt < 4000 && Abs(nowH) > 100)
		why := "it came within " Round(WkPassMin) " and is going away (" Round(nowD) ")"
	if (WkPassMin = "" || nowD < WkPassMin)
		WkPassMin := nowD, WkPassAt := A_TickCount
	prevH := nowH, prevD := nowD, prevAt := A_TickCount
	if (why != "")
		WkPassMin := ""
	return why
	}

;The arrow led to a sigil (a dungeon entrance: its prompt says "Press X to Enter"): stop, press X, and
;stand still for SigilWait while it counts down and the dungeon loads (WalkStep's WkArrived = 5). goal: 1 the quest's way (StartTalk at
;the goal, WalkSigilGo's near or back into the goal's dungeon), 0 a sigil only walked past - one that won't start is left or given up
;on only when it's the quest's way (WalkSigilCheck)
StartSigil(why, goal := 0)
	{
	global WkArrived, WkSigilUntil, WkWaitWhat, WkSigilKey, WkSigilAt, WkSigilFromZone, WkSigilTries ; (v1 globals it sets)
	global WkSigilXAt, WkSigilGoal ; (v2-only: the port tools don't know them)
	if (KeysDown || HeldW || SpeedNow > 1)
		ReleaseKeys()
	WkArrived := 5, WkSigilUntil := A_TickCount + SigilWait, WkWaitWhat := "sigil"
	WkPromptUsed[WkPromptDest = "" ? "?" : WkPromptDest] := A_TickCount
	;(for the tries at it, and the zone it leads to - WalkZone notes it when the zone changes)
	WkSigilKey := WkPromptDest = "" ? "?" : WkPromptDest, WkSigilAt := A_TickCount, WkSigilFromZone := WalkZone()
	if (!IsObject(WkSigilTries))
		WkSigilTries := V1Obj()
	if (!WkSigilTries.Has(WkSigilKey))
		WkSigilTries[WkSigilKey] := []
	WkSigilTries[WkSigilKey].Push(A_TickCount)
	;(...and by its spot, for the one gate and the "didn't start" count - WalkSigilMayX, WalkSigilCheck; its load looked for from now)
	WkSigilXAt := A_TickCount, WkSigilGoal := goal ? 1 : 0
	ssAt := WalkSigilSpot(true)
	if (IsObject(ssAt))
		ssAt.xs.Push(A_TickCount)
	PressKey("x")
	WalkLog("sigil: " why " - pressed X, waiting " Round(SigilWait / 1000) " s")
	SetStatus("entering the sigil - pressed X")
	}

;A boat or the like ("<SOMETHING> TO <PLACE>", "Press X ... to Use") covers the arrow. Use it if
;the place is the zone one of the quest's goals is in (the game's log names the goals' zones, e.g.
;Karamelle/Interiors/KM_Z10_UnderwaterGrotto, and KM_Z10 is Karamelle/KM_Z10_Gobblerton), we're not
;in that zone already, and it wasn't used in the last 10 minutes. Can't tell where it goes (a zone
;never visited): use it the second time it gets in the way without the goal getting closer. Otherwise
;step out of it, so the arrow shows again, and walk on. True if it did something
WalkTransport(dest, arrowSeen := false)
	{
	global WkTransSeen, WkTransStep, WkTransStepAt, WkSide, WkBestTime, WkLastRead ; (v1 globals it sets)
	zone := WalkZone()
	leads := WalkTransportLeads(dest, zone)
	recent := WkTransUsed.Has(dest) && A_TickCount - WkTransUsed[dest] < 600000
	;Second time at the same one, the goal no closer, can't tell where it goes
	;(and the arrow showed again in between: it really was walked on from, and came back here)
	again := IsObject(WkTransSeen) && WkTransSeen.dest = dest && A_TickCount - WkTransSeen.at < 180000
		&& WkTransSeen.seenAfter && (WkBestDist = "" || WkTransSeen.dist = "" || WkBestDist > WkTransSeen.dist - 20)
	if (!recent && (leads = 1 || (leads = "" && again && !arrowSeen)))
		{
		StartTransport(dest, leads = 1 ? "it goes to the quest's zone" : "can't tell where it goes, and walking on didn't get any closer")
		return true
		}
	;Its prompt only pushes the arrow up: nothing in the way, walk on
	if (arrowSeen)
		return false
	if (!IsObject(WkTransSeen) || WkTransSeen.dest != dest || A_TickCount - WkTransSeen.at >= 180000)
		WkTransSeen := V1Obj({dest: dest, at: A_TickCount, dist: WkBestDist, seenAfter: 0})
	;Step out of it (not over and over at the same spot)
	if (WkTransStep >= 3 && A_TickCount - WkTransStepAt < 60000)
		return false
	WkTransStep := (A_TickCount - WkTransStepAt < 60000) ? WkTransStep + 1 : 1, WkTransStepAt := A_TickCount
	WalkLog("transport: '" dest "' covers the arrow - " (recent ? "used it in the last 10 minutes" : leads = 0 ? "it doesn't go to the quest's zone" : "can't tell where it goes yet") ", stepping out of it")
	SetStatus("stepping out of the " dest " prompt")
	BackUp(900)
	if (!Walking || !GameActive())
		return true
	Turn(60 * WkSide)
	HoldW(1)
	HoldFor(Round(1000 / (SpeedNow ? SpeedNow : 1)))
	HoldW(0)
	WkSide := -WkSide, WkBestTime := A_TickCount, WkLastRead := A_TickCount
	return true
	}

;1 if a "... TO <dest>" transport goes to the zone of one of the quest's goals (and not the zone
;we're in), 0 if it goes somewhere else, "" if it can't tell
WalkTransportLeads(dest, zone)
	{
	destName := WalkLetters(dest)
	;(v1: the lists blank till WalkerInit / WalkZone read them - .Length() blank, a for over blank nothing; v2 throws on a blank)
	if (StrLen(destName) < 3 || !IsObject(WkGoalZones) || !WkGoalZones.Length)
		return ""
	;The zone whose name is closest to it - the game's title font fools OCR ("GOBBLERTON" can come out
	;as "coeeLERTON"), so up to a third of the letters may be off, if no other zone is as close
	destKey := "", best := "", tie := false
	for knownZone in (IsObject(WkKnownZones) ? WkKnownZones : [])
		{
		zoneName := WalkLetters(RegExReplace(RegExReplace(knownZone, "^.*/"), "i)^[A-Z]+_Z\d+_"))
		if (zoneName = "")
			continue
		off := WalkEditDistance(destName, zoneName)
		if (off > StrLen(zoneName) // 3)
			continue
		if (best = "" || off < best)
			best := off, destKey := WalkZoneKey(knownZone), tie := false
		else if (off = best && WalkZoneKey(knownZone) != destKey)
			tie := true
		}
	if (destKey = "" || tie)
		return ""
	if (destKey = WalkZoneKey(zone))
		return 0
	for i, goalZone in WkGoalZones
		if (WalkZoneKey(goalZone) = destKey)
			return 1
	return 0
	}

;Just the letters, in capitals, with the digits OCR mistakes for letters turned back (0 O, 1 I, 5 S, 8 B)
WalkLetters(text)
	{
	text := StrUpper(text)
	return RegExReplace(StrReplace(StrReplace(StrReplace(StrReplace(text, "0", "O"), "1", "I"), "5", "S"), "8", "B"), "[^A-Z]")
	}

;How many single-letter changes (add, drop or swap one) turn a into b
WalkEditDistance(a, b)
	{
	lenB := StrLen(b), prevRow := []
	;(v2: an Array grows by Push - each index here is the next one, as v1's assignment made it)
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

;The part of a zone name shared by a zone and the places inside it: "KM_Z10" for both
;Karamelle/KM_Z10_Gobblerton and Karamelle/Interiors/KM_Z10_UnderwaterGrotto
WalkZoneKey(zoneName)
	{
	return RegExMatch(zoneName, "i)([A-Z]+_Z\d+)", &key) ? key[1] : zoneName
	}

;Uses a boat or the like: X, then stand still while it moves us and the new zone loads
StartTransport(dest, why)
	{
	global WkTransSeen, WkArrived, WkSigilUntil, WkWaitWhat ; (v1 globals it sets)
	if (KeysDown || HeldW || SpeedNow > 1)
		ReleaseKeys()
	WkTransUsed[dest] := A_TickCount, WkTransSeen := ""
	WkArrived := 5, WkSigilUntil := A_TickCount + TransportWait, WkWaitWhat := dest
	PressKey("x")
	WalkLog("transport: '" dest "' covers the arrow and " why " - pressed X, waiting " Round(TransportWait / 1000) " s")
	SetStatus("using the " dest " - pressed X")
	}

;One step at a World Gate (after X). The Spiral Map opens with the quest's world picked, so click its
;Go To World button (at most 3 times). The map gone after a click = the loading screen into the new
;world, handled like a door's. No map within GateWait: X once more, then back to walking
GateStep()
	{
	global Walking, WkGateClicks, WkGateAt, WkLoadAt, WkGateX, WkArrived, WkGateLook, WkBestTime, WkLastRead ; (v1 globals it sets)
	btn := SpiralMapButton()
	if (!Walking)
		return false
	if (IsObject(btn))
		{
		if (WkGateClicks >= 3)
			{
			WalkLog("gate: clicked Go To World 3 times and the Spiral Map is still open - stopped")
			Walking := 0
			ReleaseKeys()
			SetStatus("stopped - World Gate: pick the world and click Go To World, then press " WalkKeyText())
			return false
			}
		WkGateClicks += 1
		WalkLog("gate: Spiral Map open - clicking Go To World at " btn.x - GameLeft "," btn.y - GameTop " (try " WkGateClicks ")")
		SetStatus("World Gate - clicking Go To World")
		WalkClick(btn.x, btn.y)
		WkGateAt := A_TickCount
		Sleep(1500)
		return Walking ? true : false
		}
	if (WkGateClicks)
		{
		WalkLog("gate: Spiral Map closed - loading the new world")
		WalkReset()
		WkLoadAt := A_TickCount
		SetStatus("waiting - loading the new world")
		return true
		}
	if (A_TickCount - WkGateAt > GateWait)
		{
		if (WkGateX < 2)
			{
			WalkLog("gate: no Spiral Map " Round(GateWait / 1000) " s after X - pressing X again")
			WkGateX += 1, WkGateAt := A_TickCount
			PressKey("x")
			Sleep(800)
			return Walking ? true : false
			}
		;Not a World Gate after all (or out of reach): walk on, and don't look for one again for a while
		WalkLog("gate: no Spiral Map after pressing X twice - walking on")
		WkArrived := 0, WkGateLook := A_TickCount + 15000
		WkBestTime := A_TickCount, WkLastRead := A_TickCount
		return true
		}
	SetStatus("World Gate - waiting for the Spiral Map")
	Sleep(300)
	return true
	}

;Which prompt panel is showing at the bottom of the game: "gate" (a World Gate: titled World Gate,
;"Press X or click to Interact"), "sigil" (a dungeon entrance: "Press X to Enter", with Team Up),
;"transport" (a boat or the like: titled e.g. "BOAT TO GOBBLERTON", "Press X or click to Use" - where it
;goes in WkPromptDest), "press" (any other "Press X ..." prompt) or "". WkPromptDest also tells one
;prompt from another. Read by OCR; the panel grows with the UI like the arrow does
InteractPrompt()
	{
	global WkPromptDest, WkPromptVerb, WkPromptText ; (v1 globals it sets)
	WkPromptDest := "", WkPromptVerb := "", WkPromptText := ""
	s := ArrowScale().scale
	t := OcrRect(Round(GameLeft + GameW / 2 - 330 * s), Round(GameTop + GameH - 300 * s), Round(660 * s), Round(240 * s))
	if (ErrorLevel)
		return ""
	;(all of it, for a look for Crowns before an X - Collect.ahk UseStep)
	WkPromptText := t
	;(its title and "... to Interact" - or its title line alone in capitals, WORLD GATE, with "Press" / "click" by it: "Interact"
	;garbled at a small UI - 2026-11-13 00:16:27, UI 0.856, a World Gate's read as a plain 'WORLDGATE' prompt - X'd, its Spiral
	;Map Spaced at, left open 4 hours. Not the quest line under an NPC's prompt naming one: not a title)
	if (RegExMatch(t, "i)w[o0]rld\s*gate") && RegExMatch(t, "i)interact"))
		return "gate"
	if (RegExMatch(t, "m`n)^\s*W[O0]RLD\s*GATE\s*$") && RegExMatch(t, "i)\bpress\b|\bclick\b"))
		return "gate"
	if (RegExMatch(t, "i)to\s*enter"))
		{
		WkPromptDest := SubStr(WalkLetters(RegExMatch(t, "m`n)^\s*TO\s+(.+?)\s*$", &sigil) ? sigil[1] : t), 1, 60)
		return "sigil"
		}
	;(the title is in capitals; the quest line under it isn't, so "Talk To Rosina" doesn't count)
	if (RegExMatch(t, "i)to\s*use") && RegExMatch(t, "m`n)^\s*[A-Z][A-Z']*(?:\s+[A-Z][A-Z']*)*\s+TO\s+(\S.*?)\s*$", &title))
		{
		WkPromptDest := Trim(title[1])
		return "transport"
		}
	;Any other prompt: "Press X to Talk", "... or click to Interact", "to Collect"... The key that tells one
	;prompt from another: its title line (an NPC's or object's name, in capitals) - the quest line OCR
	;picks up under it changes from read to read - else all its letters
	if (RegExMatch(t, "i)\bpress\b") && RegExMatch(t, "i)\bto\s+[a-z]{3,}"))
		{
		;(read again at twice the size - at a small UI its name comes out garbled at 1: 2026-11-01 11:50, UI scale 0.86,
		;'ENGDCERMONTGWRY' and 'MONTGOQYPRESSXTOTALK' for Engineer Montgomery's own prompt - no X, NEEDS YOU; the quest marker's
		;name over him, read at 2, came out right. Only a "Press X" prompt's: the others are told apart well enough at 1)
		t2 := OcrRect(Round(GameLeft + GameW / 2 - 330 * s), Round(GameTop + GameH - 300 * s), Round(660 * s), Round(240 * s), "en", 2)
		if (!ErrorLevel && RegExMatch(t2, "i)\bpress\b") && RegExMatch(t2, "i)\bto\s+[a-z]{3,}"))
			t := t2, WkPromptText := t2
		;(a World Gate's title only read right at 2: its prompt all the same - its title line, as above)
		if (RegExMatch(t, "m`n)^\s*W[O0]RLD\s*GATE\s*$"))
			return "gate"
		WkPromptDest := RegExMatch(t, "m`n)^\s*([A-Z][A-Z'.\- ]{3,}?)\s*$", &cap) ? WalkLetters(cap[1]) : SubStr(WalkLetters(t), 1, 60)
		WkPromptVerb := RegExMatch(t, "i)\bpress\b.*?\bto\s+([a-z]{3,})", &verb) ? verb[1] : ""
		return "press"
		}
	return ""
	}

;Within the arrow's arrowMax of the goal - or, when the game's memory can be used this step, within units game
;units of it (the arrow's number means more or less in different zones; the memory's distance doesn't)
WalkNear(d, arrowMax, units)
	{
	if (WkNavOk && IsObject(WkNavObj) && WkNavObj.dist != "")
		{
		;(the goal in this zone: straight at it, on the same floor - the path's distance jumps by its nodes right by it,
		;2026-10-25 11:33:31-34 1 to 6 on the arrow standing still)
		wnGoal := WalkGoalNear()
		if (IsObject(wnGoal))
			return wnGoal.r <= units && (wnGoal.dz = "" || Abs(wnGoal.dz) <= 150)
		return WkNavObj.dist <= units
		}
	return d != "" && d <= arrowMax
	}

;The quest's goal by the game's memory, when it's in this zone (hops 0) and has a place: {r: how far, straight and flat (game
;units), dz: how far up from the wizard ("" not known), h: the heading to it (degrees, + right; 0 right on it)}; "" when it
;can't be told - no reading this step, the goal zones away, no goal point (a goal the game shows no way to)
WalkGoalNear()
	{
	if (!WkNavOk || !IsObject(WkNavObj) || WkNavObj.hops = "" || WkNavObj.hops != 0 || WkNavObj.gx = "" || WkNavObj.gy = ""
		|| WkNavObj.x = "" || WkNavObj.y = "" || WkNavObj.yaw = "")
		return ""
	gdx := WkNavObj.gx - WkNavObj.x, gdy := WkNavObj.gy - WkNavObj.y
	gh := WalkNavHeading(WkNavObj.x, WkNavObj.y, WkNavObj.yaw, WkNavObj.gx, WkNavObj.gy)
	return V1Obj({r: Sqrt(gdx * gdx + gdy * gdy), dz: (WkNavObj.gz != "" && WkNavObj.z != "") ? WkNavObj.gz - WkNavObj.z : "", h: gh = "" ? 0 : gh})
	}

;By the goal by the game's memory - within TalkUnits, on the same floor: 1 / 0; "" not known (no memory, the goal zones away)
WalkGoalOnTop()
	{
	gotGn := WalkGoalNear()
	if (!IsObject(gotGn))
		return ""
	return (gotGn.r <= TalkUnits && (gotGn.dz = "" || Abs(gotGn.dz) <= 150)) ? 1 : 0
	}

;Where the goal is by the game's memory, for debug.log (" - the game's memory: the goal N units off, N up"), "" not known
WalkGoalSay()
	{
	gsGn := WalkGoalNear()
	return IsObject(gsGn) ? " - the game's memory: the goal " Round(gsGn.r) " units off" (gsGn.dz = "" ? "" : ", " Round(gsGn.dz) " up") ", " Round(gsGn.h) " degrees" : ""
	}

;The arrow hidden: may it back up and turn to find it? Not while the game's memory steers (its heading trusted, its distance
;known - it stands in for the arrow, and can't only a moment: a battle starting, a loading screen), nor on top of the goal by
;it (onTop: WalkGoalOnTop)
WalkHiddenBackUpOk(onTop)
	{
	return !(WkNavUse && WkNavD != "") && onTop != 1
	}

;Stuck - not getting any closer (d: the distance now) - right by the goal: the thing itself in the way (an item on a table,
;someone behind a counter), going round it only walks away. "talk": X (once per goal - WkStuckNearDone); "wait": X done already
;and a talk goal's NPC this close by the game's memory - waiting there (X there is all it takes); "": not by it - going round
;(a go-to goal behind a fence may need it). By the game's memory within TalkUnits (the goal in this zone, the same floor); else
;the arrow's number within OnTopDist
WalkStuckNear(d)
	{
	snTop := WalkGoalOnTop()
	if (snTop = "")
		return (d != "" && d <= OnTopDist && !WkStuckNearDone) ? "talk" : ""
	if (!snTop)
		return ""
	;(the route round walls much longer than straight to it: a fence or a wall between - going round, not waiting by it)
	snGn := WalkGoalNear()
	if (IsObject(snGn) && WalkRouteRound(snGn.r))
		return ""
	return !WkStuckNearDone ? "talk" : IsObject(WalkTalkGoal()) ? "wait" : ""
	}

;Near the goal by the game's memory (WalkGoalNear in gn): the last bit to be walked closed loop (WalkApproachStep)? Walking on
;(not at a goal), its heading steered by, out of battle, not a dungeon run; within ApproachUnits on the same floor; no mob's
;reach or sight on the way, none waited for, no teleport ahead (the route's way then, as before); a straight way there - the
;route (or the game's path) not much longer than straight - or right by it anyway; not given up on for now (WkApOffUntil)
WalkApproachWanted(&gn)
	{
	gn := ""
	;(DgRun: AutoFarmer's dungeon run - blank in AutoQuester, as in v1)
	if (WkArrived != 0 || !WkNavUse || inbattle || IsObject(DgRun) || (WkApOffUntil && A_TickCount < WkApOffUntil) || !V1IsFunc("NavRead"))
		return false
	gn := WalkGoalNear()
	if (!IsObject(gn) || gn.r > ApproachUnits || (gn.dz != "" && Abs(gn.dz) > 150))
		return false
	if (WkNavObj.escape != "" || WkNavObj.blindahead != "" || WkNavMob != "" || WkNavJump != "")
		return false
	;(a collect / defeat goal: its arrow only leads to the area - collecting's, CollectCheck)
	if (WkGoalLine != "" && CollectGoal(WkGoalLine))
		return false
	awLen := (WkNavRouted && WkNavObj.left != "") ? WkNavObj.left : WkNavObj.dist
	if (gn.r > 600 && (awLen = "" || awLen > gn.r * 1.15 + 150))
		return false
	;(right by it too: not straight at it through a fence, a wall or water - the route round it as before)
	if (WalkRouteRound(gn.r))
		return false
	return true
	}

;The route round walls (the helper's, this step) much longer than straight to the goal r game units off: a fence, a wall or
;water between - walking straight at it only gets stopped there
WalkRouteRound(r)
	{
	return WkNavRouted && IsObject(WkNavObj) && WkNavObj.left != "" && WkNavObj.left > r * 1.3 + 300
	}

;Near the goal by the game's memory (WalkApproachWanted - gn its WalkGoalNear): the last bit walked closed loop (WalkApproach),
;then X - a talk goal's NPC from TalkUnits off, anything else ArriveUnits. Past it, off to the side, the time up: turned and
;walked again the next step (3 tries, then the route as before for 8 s); stopped by something (a wall, the NPC itself) within
;TalkReach: X from there. A talk goal whose 3 tries in 2 minutes are used: waiting by it (WalkTalkWait). Just out of a
;dialogue: a moment for the goal to move on first. dist: the step's distance (arrow units) for the log
WalkApproachStep(gn, dist)
	{
	global WkBestTime, WkLastRead, WkTries, WkApTries, WkApOffUntil ; (v1 globals it sets)
	if (WkDlgEndAt && A_TickCount - WkDlgEndAt < 1500)
		{
		if (KeysDown || HeldW)
			ReleaseKeys(true)
		Sleep(150)
		return true
		}
	asTalk := WalkTalkGoal()
	asStop := IsObject(asTalk) ? TalkUnits : ArriveUnits
	asWhy := gn.r <= asStop ? "there" : WalkApproach(asStop)
	if (!Walking)
		return false
	WkBestTime := A_TickCount, WkLastRead := A_TickCount, WkTries := 0
	asNow := WalkGoalNear()
	if (asWhy = "" || asWhy = "new goal" || asWhy = "you" || !IsObject(asNow))
		return true
	;(AutoFarmer's Puzzle.ahk: stopped by something well short of the goal - a blocked way's evidence; it may take over)
	if (asWhy = "blocked" && V1IsFunc("PuzzleEvidence") && %"PuzzleEvidence"%.Call("approach", asNow.r))
		return true
	;("there": let go a look's walking early - it may read a few dozen units over stopR; "blocked" with the route going round -
	;a fence, a wall: a try that didn't get there, the route's way after 3)
	if (asWhy = "there" || asNow.r <= asStop || (asWhy = "blocked" && asNow.r <= TalkReach && !WalkRouteRound(asNow.r)))
		{
		WkApTries := 0
		if (IsObject(asTalk) && !WalkTalkTriesLeft())
			return WalkTalkWait(dist, "at the goal again")
		StartTalk(dist = "" ? "?" : dist)
		return true
		}
	WkApTries += 1
	if (WkApTries >= 3)
		{
		WkApTries := 0, WkApOffUntil := A_TickCount + 8000
		WalkLog("approach: 3 tries didn't get within " asStop " of the goal (" Round(asNow.r) " off, the last: " asWhy ") - the route as before for 8 s")
		}
	return true
	}

;Walks the last bit to the goal closed loop by the game's memory (WalkGoalNear): W up and 1x first (no speed key with W down),
;turned to face it on the spot (NavTurn, over 8 degrees off), then W held - no speed key - while the wizard's place is read
;look after look (~40 ms each: 30-50 units at 1x), and let go once within stopR (a look's walking early), past its nearest
;(further two looks running), the goal well off to the side close by or drifting off further out, not getting closer (a wall,
;the NPC itself), the time it should take up (3 s at most), a new goal, you touching the keyboard or mouse, or the memory lost.
;Each reading's place kept in WkNavObj. Why it stopped: "there", "passed", "off", "blocked", "time", "new goal", "you", "lost",
;"" (walking off, the game not in front)
WalkApproach(stopR)
	{
	gn := WalkGoalNear()
	if (!IsObject(gn))
		return "lost"
	if (gn.r <= stopR)
		return "there"
	if (HeldW)
		HoldW(0)
	SpeedSet(0, "near the goal")
	if (Abs(gn.h) > 8)
		{
		NavTurn(gn.h)
		if (!Walking || !GameActive())
			return ""
		gn := WalkApproachLook()
		if (!IsObject(gn))
			return gn = "new" ? "new goal" : "lost"
		if (gn.r <= stopR)
			return "there"
		}
	;(v1: WkWalkSpeed blank till it's measured - blank > 0.1 compared as text, false)
	apSpeed := (V1Gt(WkWalkSpeed, 0.1) ? WkWalkSpeed : 0.9) * (SpeedNow ? SpeedNow : 1)
	apCap := Min(3000, Round((gn.r - stopR) / apSpeed * 1.4) + 300)
	apFrom := gn.r, apPrev := gn.r, apRises := 0, apMisses := 0, apLooks := 0, apWhy := "time"
	HoldW(1, true)
	apDown := A_TickCount, apLookAt := A_TickCount, apProgAt := A_TickCount, apProgX := WkNavObj.x, apProgY := WkNavObj.y
	Loop
		{
		Sleep(10)
		if (!Walking || !GameActive())
			{
			apWhy := ""
			break
			}
		if (UserIdle() < A_TickCount - apDown)
			{
			apWhy := "you"
			break
			}
		apLookMs := A_TickCount - apLookAt, apLookAt := A_TickCount
		g := WalkApproachLook()
		if (g = "new")
			{
			apWhy := "new goal"
			break
			}
		if (!IsObject(g))
			{
			if (++apMisses >= 3)
				{
				apWhy := "lost"
				break
				}
			continue
			}
		apMisses := 0, apLooks += 1, gn := g
		;(it walks on a look's worth after this reading was taken, and a little after W comes up)
		if (g.r - apSpeed * (apLookMs / 2 + 30) <= stopR)
			{
			apWhy := "there"
			break
			}
		apRises := g.r > apPrev + 5 ? apRises + 1 : 0
		if (apRises >= 2)
			{
			apWhy := "passed"
			break
			}
		if ((Abs(g.h) > 100 && g.r <= stopR * 2) || (Abs(g.h) > 30 && g.r > stopR * 2 && A_TickCount - apDown > 300))
			{
			apWhy := "off"
			break
			}
		;(the wizard himself hardly moving - not the distance: walking past beside the goal it hardly changes - a wall, the NPC)
		if (A_TickCount - apProgAt >= 400)
			{
			if ((WkNavObj.x - apProgX) ** 2 + (WkNavObj.y - apProgY) ** 2 < 3600)
				{
				apWhy := "blocked"
				break
				}
			apProgAt := A_TickCount, apProgX := WkNavObj.x, apProgY := WkNavObj.y
			}
		apPrev := g.r
		if (A_TickCount - apDown > apCap)
			break
		}
	HoldW(0)
	WalkLog("approach: " (apWhy = "" ? "stopped" : apWhy) " - " Round(apFrom) " to " Round(gn.r) " units off the goal (stopping at " stopR "), " A_TickCount - apDown " ms, " apLooks " looks at the game's memory")
	return apWhy
	}

;One look at the game's memory for WalkApproach: the wizard's place and facing (and the goal's) put into WkNavObj - its
;WalkGoalNear; "new" a new goal meanwhile; "" not read (or another zone). A miss doesn't put the walker's own reads off
;(NavRead's wait after one is put back, as MouseSteerYaw)
WalkApproachLook()
	{
	global NavWait, NavWaitUntil, NavWhy ; (v1 globals it sets)
	alWait := NavWait, alUntil := NavWaitUntil, alWhy := NavWhy
	nav := %"NavRead"%.Call(120)
	NavWait := alWait, NavWaitUntil := alUntil, NavWhy := alWhy
	if (!IsObject(nav) || nav.x = "" || nav.y = "" || nav.yaw = "" || !IsObject(WkNavObj) || (nav.zone != "" && nav.zone != WkNavObj.zone))
		return ""
	if (nav.goalid != "" && WkNavObj.goalid != "" && nav.goalid "|" != WkNavObj.goalid "|")
		return "new"
	WkNavObj.x := nav.x, WkNavObj.y := nav.y, WkNavObj.yaw := nav.yaw
	if (nav.z != "")
		WkNavObj.z := nav.z
	if (nav.dist != "")
		WkNavObj.dist := nav.dist
	if (nav.hops = 0 && nav.gx != "" && nav.gy != "")
		WkNavObj.gx := nav.gx, WkNavObj.gy := nav.gy, WkNavObj.gz := nav.gz
	return WalkGoalNear()
	}

;Is this "Press X" prompt (key: its name's letters, WkPromptDest) one the quest wants? Its name in the quest's
;goal line ("Talk To Benedict Glendemming in ..." has BENEDICT GLENDEMMING), close to the goal (NearDist on the
;arrow), or collecting (a collect goal - it's how things are picked up: not an NPC's "Press X to Talk", whose chatter
;isn't). Prompts at others - an NPC or a vendor walked past - aren't: X there opens their chatter, an OK box or their
;shop (2026-10-23 07:07: X at an NPC on the way to "Defeat Optio Agenor and collect ...", its Escape then opening the
;game's menu, the arrow lost for 2 minutes)
;(by the goal's kind - WalkGoalKind: collecting a fight goal's things, every prompt but an NPC's chatter and a teleporter's;
;a goal to use things, only the prompts naming its thing - 2026-10-25 11:49:38: X at a TELEPORTER on "Use Inactive Protector";
;going to a place, none; talking, its NPC's)
WalkPromptWanted(key, d)
	{
	;(right at a teleport on the game's path: its prompt is the way on)
	if (WkNavJump != "")
		return true
	if (WkArrived = 7)
		{
		pwMode := IsObject(WkCollect) ? WkCollect.kind : ""
		if (pwMode = "use" || pwMode = "talk")
			return WalkUseNames(key)
		if (pwMode = "go")
			return false
		return !InStr(key, "TELEPORT")
		}
	;(close to the goal: by the game's memory - the goal in this zone - within TalkReach on the same floor, a talk goal's only
	;with its NPC's name on it (2026-10-25 11:28:49: X at a vendor's prompt by Edith Benchley, 3000 units "near" on the arrow's
	;number, opened his shop); no memory: the arrow's number within NearDist, as before)
	pwGn := WalkGoalNear()
	if (IsObject(pwGn))
		{
		pwTalk := WalkTalkGoal()
		if (pwGn.r <= TalkReach && (pwGn.dz = "" || Abs(pwGn.dz) <= 150) && (!IsObject(pwTalk) || WalkIsGoalNpc(key, pwTalk)))
			return true
		}
	;(the goal zones away by the game's memory: only the way out's own prompt - a door wanting X - within TalkReach of it; not
	;every NPC or vendor by every way out)
	;(v1: hops blank - an older helper's - > 0 compared as text, false)
	else if (WkNavOk && V1Gt(WkNavHops, 0))
		{
		if (IsObject(WkNavObj) && WkNavObj.dist != "" && WkNavObj.dist <= TalkReach)
			return true
		}
	;(a goal the game shows no way to has no "close": no distance to it - WkNavNoPlace)
	else if (!WkNavNoPlace && ((d != "" && d <= NearDist) || (WkBestDist != "" && WkBestDist <= NearDist)))
		return true
	goal := WalkGoalLine()
	if (goal != "" && CollectGoal(goal))
		{
		pwKind := WalkGoalKind(goal)
		if (pwKind = "use")
			return WalkUseNames(key, goal)
		if (pwKind = "fight" && !InStr(key, "TELEPORT") && !RegExMatch(WkPromptVerb, "i)^(talk|speak|chat|shop|trade|buy|sell|browse|craft|learn|train)"))
			return true
		}
	g := WalkLetters(goal)
	return (StrLen(key) >= 4 && g != "" && InStr(g, key))
	}

;Does the prompt (key: its name's letters - WkPromptDest) name the thing the goal has the wizard use - or the NPC a talk goal
;names (WalkGoalItemName: the game's memory's, else the goal line's)? OCR slips allowed (WalkNameLike). Never a teleporter's
;unless that's the thing. goal: the goal line ("" the last read)
WalkUseNames(key, goal := "")
	{
	unItem := WalkLetters(WalkGoalItemName(goal))
	;(no capitals title line read: InteractPrompt's key is all the panel's letters then, the quest line pushed up over it among them -
	;"...INACTIVEPROTECTORINDISTRICTOFTHESTARSHILDABREWERPRESSXTOTALK": the name is the letters right before its "Press X"; cut off
	;at 60 with none - no name read)
	unAt := InStr(key, "PRESS")
	;(a title whose name has PRESS in it - EMPRESSANTUSKETTE, PRESSUREPLATE: the name read whole, no "Press X" to cut at)
	if (unAt && StrLen(key) < 60 && Abs(StrLen(key) - StrLen(unItem)) <= StrLen(unItem) // 4 && WalkNameLike(key, unItem))
		unAt := 0
	if (unAt)
		key := SubStr(key, Max(1, unAt - StrLen(unItem)), Min(unAt - 1, StrLen(unItem)))
	else if (StrLen(key) >= 60)
		return false
	if (StrLen(key) < 4 || StrLen(unItem) < 4)
		return false
	if (InStr(key, "TELEPORT") && !InStr(unItem, "TELEPORT"))
		return false
	;(a shorter name inside the thing's - a prompt titled PROTECTOR for INACTIVEPROTECTOR - only with two thirds of its letters)
	if (InStr(unItem, key) && !InStr(key, unItem) && StrLen(key) * 3 < StrLen(unItem) * 2)
		return false
	return WalkNameLike(key, unItem)
	}

;The thing (or NPC, or place) the quest's goal names: the game's memory's (WalkGoalText keeps it - the item, else the NPC), else
;the goal line's words after its verb, up to " in <place>" and the count ("Use Inactive Protector in District of the Stars (0 of
;3)": Inactive Protector). goal: the goal line ("" the last read); "" when there's none
WalkGoalItemName(goal := "")
	{
	if (WkGoalItem != "")
		return WkGoalItem
	if (WkGoalNpc != "")
		return WkGoalNpc
	giLine := goal != "" ? goal : WkGoalLine
	if (RegExMatch(giLine, "i)^\W*(?:Use|Open|Activate|Cl[i]ck|Inspect|Interact\s+With|Interact|Read|Examine|Search|Touch|Collect|Go\s+To|Travel\s+To|Talk\s+To|Find|Defeat)\s+(.+?)(?:\s+in\s+[^()]+?)?\s*(?:\(\s*\d+\s*(?:of|/)\s*\d+\s*\))?\s*$", &giM))
		return Trim(giM[1])
	return ""
	}

;What the quest's goal has the wizard do: "fight" (defeat things - collecting what they drop: walked into, the area roamed),
;"use" (X at things: Use, Read, a "Collect X" object), "go" (walk to a place - no X), "talk" (X at an NPC), "" (anything else -
;"Practice Photomancy": the arrow's own way, nothing roamed for). By the game's memory's kind for this goal when it's read
;(WalkGoalText - NavGoal: BOUNTY, BOUNTYCOLLECT, COLLECTAFTERBOUNTY fight; SCAVENGE only with a mob or more than one to get;
;USAGE use; WAYPOINT, ENCOUNTER_WAYPOINT_FOREACH go; PERSONA talk); else by the line's words (any case, OCR junk before them
;allowed: Use / Open / Read... use, Talk To talk, Go / Travel To go, else a collect / defeat line fight - CollectGoal). text:
;the goal line ("" the last read)
WalkGoalKind(text := "")
	{
	gkText := text != "" ? text : WkGoalLine
	gkType := WkGoalType, gkTotal := WkGoalTotal
	;(nothing kept from NavGoal: the kind on /nav's goal line, read this step for the same goal)
	if (gkType = "" && WkNavOk && IsObject(WkNavObj) && WkNavObj.goaltype != "" && (WkGoalId = "" || WkNavObj.goalid = "" || WkGoalId "|" = WkNavObj.goalid "|"))
		gkType := WkNavObj.goaltype, gkTotal := WkNavObj.goaltotal
	if (gkType != "")
		{
		if (RegExMatch(gkType, "i)^(BOUNTY|BOUNTYCOLLECT|COLLECTAFTERBOUNTY)$"))
			return "fight"
		if (RegExMatch(gkType, "i)^SCAVENGE"))
			;(v1: a total that isn't a number + 0 was blank, > 1 false)
			return (WkGoalMobKey != "" || (gkTotal != "" && V1Gt(V1Add(gkTotal, 0), 1))) ? "fight" : ""
		if (gkType = "USAGE")
			return "use"
		if (gkType = "WAYPOINT" || gkType = "ENCOUNTER_WAYPOINT_FOREACH")
			return "go"
		if (gkType = "PERSONA")
			return "talk"
		return ""
		}
	;("Cl[i]ck": the same word - the test harnesses look for no bare one in the walker's copied code)
	if (RegExMatch(gkText, "i)^\W*(Use|Open|Activate|Cl[i]ck|Inspect|Interact|Read|Examine|Search|Touch)\b"))
		return "use"
	if (RegExMatch(gkText, "i)^\W*Talk\s+To\b"))
		return "talk"
	if (RegExMatch(gkText, "i)^\W*(Go|Travel)\s+To\b"))
		return "go"
	return CollectGoal(gkText) ? "fight" : ""
	}

;Use / go / talk mode (WkArrived = 7, the game's memory's kind) with AutoFarmer's own steps for it (Collect.ahk UseStep, GoStep,
;TalkStep): they read the prompts themselves - X only at the thing's (or the NPC's) own
WalkOwnPrompts()
	{
	return WkArrived = 7 && IsObject(WkCollect) && WkCollect.kind != "" && WkCollect.kind != "fight" && V1IsFunc("UseStep")
	}

;Waiting at a goal (WkArrived = 1, not a collect goal given up on): the goal's id and count by the game's memory (NavGoal, every
;3 s) against the ones when the wait began - changed: the next goal, walking on at once (true); the same and the game shows no way
;to it (WkNavNoPlace): its kind's own way (CollectNoPlace - true if it began). False: still waiting
WalkArrivedMoved()
	{
	global WkArr1Look, WkArr1Key ; (v1 globals it sets)
	if (!V1IsFunc("NavGoal") || (IsObject(WkCollect) && WkCollect.gaveUp) || (WkArr1Look && A_TickCount - WkArr1Look < 3000))
		return false
	WkArr1Look := A_TickCount
	amGoal := %"NavGoal"%.Call()
	if (!IsObject(amGoal) || amGoal.text = "" || amGoal.goalid = "")
		return false
	;(the goal's "count": a data key named like a Map's own Count - V1At reads the key, whatever kind of object NavGoal gives)
	amKey := amGoal.goalid "|" V1At(amGoal, "count")
	if (WkArr1Key = "")
		{
		WkArr1Key := amKey
		return false
		}
	if (amKey != WkArr1Key)
		{
		WalkLog("arrived: the goal moved on by the game's memory (goal|count " amKey ", was " WkArr1Key ") - walking on")
		WalkReset()
		WkArr1Key := "", WkArr1Look := 0
		return true
		}
	if (WkNavNoPlace)
		return CollectNoPlace()
	return false
	}

;The quest's goal by the game's memory when it's a talk goal (PERSONA - "Talk To ...") in this zone: WalkGoalNear's {r, dz, h}
;and npc (the NPC it names - NavGoal, "" not read for this goal), id (its goal id); "" otherwise
WalkTalkGoal()
	{
	tgGn := WalkGoalNear()
	if (!IsObject(tgGn))
		return ""
	tgSame := WkGoalId = "" || WkNavObj.goalid = "" || WkGoalId "|" = WkNavObj.goalid "|"
	tgType := WkNavObj.goaltype != "" ? WkNavObj.goaltype : tgSame ? WkGoalType : ""
	if (tgType != "PERSONA")
		return ""
	tgGn.npc := tgSame ? WkGoalNpc : "", tgGn.id := WkNavObj.goalid
	return tgGn
	}

;Is the prompt key (its name's letters - WkPromptDest) the talk goal's NPC (tg: WalkTalkGoal)? Its name like the one the goal
;names (OCR slips allowed - "EDITHBERHLEY", "ENGDCERMONTGWRY": WalkNpcLike), or each of its words in the key in any order; not
;read: in the goal line
WalkIsGoalNpc(key, tg)
	{
	if (StrLen(key) < 4 || !IsObject(tg))
		return false
	if (tg.npc != "")
		return WalkNpcLike(key, tg.npc)
	ignLine := WalkLetters(WkGoalLine)
	return ignLine != "" && InStr(ignLine, key)
	}

;A try at the talk goal's NPC - X there (StartTalk, StartPressX at its prompt), by the game's memory within TalkReach on the
;same floor
WalkTalkCount()
	{
	global WkTalkXs ; (v1 globals it sets)
	tcGoal := WalkTalkGoal()
	if (!IsObject(tcGoal) || tcGoal.r > TalkReach || (tcGoal.dz != "" && Abs(tcGoal.dz) > 150))
		return
	if (!IsObject(WkTalkXs))
		WkTalkXs := []
	WkTalkXs.Push(V1Obj({at: A_TickCount, id: tcGoal.id}))
	}

;Tries left at the talk goal's NPC: fewer than 3 X in the last 2 minutes for this goal (the older ones dropped)
WalkTalkTriesLeft()
	{
	global WkTalkXs ; (v1 globals it sets)
	ttId := (WkNavOk && IsObject(WkNavObj)) ? WkNavObj.goalid : ""
	ttN := 0, ttKeep := []
	for each, ttX in (IsObject(WkTalkXs) ? WkTalkXs : [])
		if (A_TickCount - ttX.at < 120000)
			ttKeep.Push(ttX), ttN += (ttX.id "|" = ttId "|")
	WkTalkXs := ttKeep
	return ttN < 3
	}

;X at this prompt (key: its name's letters) - the talk goal's own NPC by the game's memory, within TalkReach on the same floor -
;even right after a dialogue or an X there (no DialogQuiet, no once a minute): 3 s after the last X, while its tries last
WalkTalkPromptOk(key)
	{
	tpGoal := WalkTalkGoal()
	if (!IsObject(tpGoal) || tpGoal.r > TalkReach || (tpGoal.dz != "" && Abs(tpGoal.dz) > 150) || !WalkIsGoalNpc(key, tpGoal))
		return false
	return (!WkLastX || A_TickCount - WkLastX >= 3000) && WalkTalkTriesLeft()
	}

;Is this prompt (key: its name's letters) the talk goal's own NPC with its 3 tries in 2 minutes used? Then no X at it by any
;way (the prompt, a quest marker) till they come free - WalkTalkRetry X's it again then
WalkTalkSpent(key)
	{
	tsGoal := WalkTalkGoal()
	return IsObject(tsGoal) && WalkIsGoalNpc(key, tsGoal) && !WalkTalkTriesLeft()
	}

;After X at the goal opened nothing, or its dialogue left the goal as it was: "push" - walk on into it (a doorway, a loading
;point: as before - anything but a talk goal by the game's memory, or a door's or teleporter's prompt); for a talk goal's NPC
;in this zone: "again" - X at it again from close by (WalkTalkAgain), "wait" - its 3 tries in 2 minutes used, waiting by it
;(WalkTalkWait), "walk" - too far for X (over TalkReach, another floor): walking on to it
WalkNoDialogNext()
	{
	ndGoal := WalkTalkGoal()
	if (!IsObject(ndGoal) || RegExMatch(WkPromptVerb, "i)^(enter|open|use)$"))
		return "push"
	if (ndGoal.r > TalkReach || (ndGoal.dz != "" && Abs(ndGoal.dz) > 150))
		return "walk"
	if (!WalkTalkTriesLeft())
		return "wait"
	;(or the route round walls much longer than straight to it: behind a fence or a wall, X doesn't reach it - walking round;
	;only while its tries last - the arrival by the straight distance X's it again at once)
	return WalkRouteRound(ndGoal.r) ? "walk" : "again"
	}

;What WalkNoDialogNext said for a talk goal: "again" - walked up within 150 if it's over 200 off (WalkApproach), turned to face
;the NPC if it's over 45 degrees off, X again (2026-10-25 11:36:55: X from right over him worked, so close by is enough); "wait"
;- WalkTalkWait; "walk" - walking on (the approach takes it there). dist: the step's distance, for the log
WalkTalkAgain(what, dist)
	{
	global WkArrived, WkBestTime, WkLastRead, WkApOffUntil ; (v1 globals it sets)
	why := WkDialog ? "the goal as it was after the dialogue" : "X opened nothing"
	if (what = "wait")
		return WalkTalkWait(dist, why)
	taGoal := WalkTalkGoal()
	if (what = "walk")
		{
		WalkLog("talk: " why " - the goal's NPC" (IsObject(taGoal) ? " " Round(taGoal.r) " off by the game's memory" (taGoal.dz = "" ? "" : ", " Round(taGoal.dz) " up") : "") " - walking on to it")
		WkArrived := 0, WkBestTime := A_TickCount, WkLastRead := A_TickCount
		return true
		}
	if (IsObject(taGoal) && taGoal.r > 200)
		{
		taFrom := taGoal.r
		taWhy := WalkApproach(150)
		if (!Walking)
			return false
		taGoal := WalkTalkGoal()
		;(stopped on the way further off than TalkUnits and no closer - a fence or a wall, not the NPC: X doesn't reach from there;
		;round it by the route for 8 s, as after the approach's 3 tries - a fence's end near the straight way leaves the route not
		;much longer, WalkRouteRound doesn't tell)
		if (taWhy = "blocked" && IsObject(taGoal) && taGoal.r > TalkUnits && taGoal.r > taFrom - 50)
			{
			WalkLog("talk: " why " - the way to " (taGoal.npc != "" ? taGoal.npc : "the goal's NPC") " blocked " Round(taGoal.r) " off (a fence, a wall?) - round it by the route, no X")
			WkArrived := 0, WkApOffUntil := A_TickCount + 8000, WkBestTime := A_TickCount, WkLastRead := A_TickCount
			return true
			}
		}
	if (IsObject(taGoal) && Abs(taGoal.h) > 45 && GameActive())
		NavTurn(taGoal.h)
	if (!Walking)
		return false
	WalkLog("talk: " why " - X at " (IsObject(taGoal) && taGoal.npc != "" ? taGoal.npc : "the goal's NPC") " again" (IsObject(taGoal) ? ", " Round(taGoal.r) " off" : "") " - not walking on through it")
	StartTalk(dist = "" ? "?" : dist, false)
	return true
	}

;A talk goal's NPC X'd 3 times in 2 minutes with nothing coming of it: waiting by it for the next goal - X again once its tries
;come free (WalkTalkRetry) - and a notice, once for this goal. why: for the log
WalkTalkWait(dist, why)
	{
	global WkArrived, WkFar, WkArrDist, WkArrGoal, WkTalkNoted ; (v1 globals it sets)
	twGoal := WalkTalkGoal()
	if (KeysDown || HeldW)
		ReleaseKeys()
	WkArrived := 1, WkFar := 0, WkArrDist := (dist = "?" ? "" : dist), WkArrGoal := (WkNavOk && IsObject(WkNavObj)) ? WkNavObj.goalid : ""
	twNpc := (IsObject(twGoal) && twGoal.npc != "") ? twGoal.npc : "the quest's NPC"
	WalkLog("talk: " why " - X at " twNpc " 3 times in 2 minutes and nothing came of it: waiting by it for the next goal (X again in a while)")
	SetStatus("arrived - X at " twNpc " did nothing, waiting for the next goal")
	if (WkTalkNoted != WkArrGoal "|")
		{
		WkTalkNoted := WkArrGoal "|"
		WalkNotify("wait", "Talking to " twNpc " didn't work", "X at " twNpc " opened nothing 3 times (or its dialogue left the quest as it was), so the bot waits by it and tries again every 2 minutes. Talk to it yourself if it needs something the bot can't do - it walks on by itself once there's a new goal.")
		}
	return true
	}

;Waiting at a talk goal's NPC (WkArrived = 1) by the game's memory, within TalkReach: X again once its tries have come free
;and a minute's gone since the last X. True if it did
WalkTalkRetry(dist)
	{
	trGoal := WalkTalkGoal()
	if (!IsObject(trGoal) || trGoal.r > TalkReach || (trGoal.dz != "" && Abs(trGoal.dz) > 150) || inbattle
		|| (WkLastX && A_TickCount - WkLastX < 60000) || !WalkTalkTriesLeft())
		return false
	WalkLog("talk: still by " (trGoal.npc != "" ? trGoal.npc : "the goal's NPC") " with the goal as it was - X again")
	StartTalk(dist = "" ? "?" : dist, false)
	return true
	}

;An NPC whose "Press X" prompt shows, wearing a quest marker - a gold "?" in a red swirl over its head, its name in
;green under it (the vision helper's /qmark, measured on Shalek the Wise at 1440p): a quest has something for it.
;key: the prompt's name letters (WkPromptDest). The marker's name as read, if one of the "?"s on screen has a name like
;key under it; "" none - or not looked: no helper, or this one looked at in the last 4 s (a look takes ~0.3 s). A "!"
;(a new quest offered) isn't followed. The NPC behind the camera: its marker isn't on screen, so it isn't seen
WalkQuestMarker(key)
	{
	;(VisionOn: AutoFarmer's - blank in AutoQuester, as in v1)
	if (StrLen(key) < 4 || !V1IsFunc("VisionGet") || !VisionOn)
		return ""
	if (WkQmLooked.Has(key) && A_TickCount - WkQmLooked[key] < 4000)
		return ""
	WkQmLooked[key] := A_TickCount
	;(walking on through the look - X is only pressed with its prompt still showing)
	;(the game above its bottom bar - the markers float over heads)
	ans := %"VisionGet"%.Call("/qmark?x1=" GameLeft "&y1=" GameTop "&x2=" GameLeft + GameW "&y2=" Round(GameTop + GameH * 0.85), 1500, true)
	if (ans = "" || ans = "none" || ans = " ")
		return ""
	Loop Parse, ans, "`n", "`r"
		{
		qm := StrSplit(A_LoopField, "|")
		;(v1: a field past the line's end read blank - V1At)
		if (qm[1] != "qmark" || V1At(qm, 2) != "?" || V1At(qm, 7) = "")
			continue
		t := OcrRect(qm[7], V1At(qm, 8), V1At(qm, 9), V1At(qm, 10), "en", 2, , 5)
		if (ErrorLevel || t = "")
			continue
		;(the marker's name reads right - big, green -, the prompt's may be garbled: WalkNpcLike)
		if (WalkNpcLike(key, t))
			return Trim(RegExReplace(t, "\s+", " "))
		WalkLog("quest marker (?) over '" Trim(RegExReplace(t, "\s+", " ")) "' - not the prompt's '" SubStr(key, 1, 30) "'")
		}
	return ""
	}

;X at a prompt's NPC wearing a quest marker (WalkQuestMarker) - once per 5 minutes for the same one. The wizard stands
;for the look (~0.5 s), and X goes only if the prompt still shows for the same NPC (not walked out of its range).
;key: the prompt's name letters. True if X was pressed
WalkQuestMarkerTalk(key)
	{
	if (WkQmTalked.Has(key) && A_TickCount - WkQmTalked[key] < 300000)
		return false
	qmName := WalkQuestMarker(key)
	if (qmName = "" || !Walking)
		return false
	if (InteractPrompt() != "press" || !(WalkNameLike(WkPromptDest, key) || WalkNpcLike(WkPromptDest, qmName)))
		{
		WalkLog("quest marker (?) over " qmName " - its prompt went before X: walking on")
		return false
		}
	WkQmTalked[key] := A_TickCount
	WalkLog("prompt '" SubStr(key, 1, 40) "' - a quest marker (?) over " qmName ": pressing X")
	StartPressX(WkPromptDest)
	return true
	}

;Two names' letters (WalkLetters) alike, allowing for OCR's misreadings: one inside the other (4 letters at least), or
;at most a quarter of the longer one's letters different ("MRLIKOLN" for MR LINCOLN). name: b as the game writes it - then a
;holding each of its words of 3 letters or more also counts, in any order, each with one letter in four changed, dropped or
;added: the prompt panel's letters come out of order, others among them (2026-10-26 15:18:48 'TALKTONIGHTSPINNERRMVENKAROLAK',
;'NIEMTORRLNKAROLAKNIGHTSPINRTOTALKPRESS' for Karolak Nightspinner's own prompt: no X, NEEDS YOU). A word of 4 letters or fewer
;only whole - one off is 3 letters anywhere ("BILL" in WILLOW, HILL, SKILL) -, and those words three quarters of its letters at
;least ("Mo Lee" isn't LEE anywhere: another NPC's prompt)
WalkNameLike(a, b, name := "")
	{
	if (StrLen(a) < 4 || StrLen(b) < 4)
		return false
	if (InStr(a, b) || InStr(b, a))
		return true
	if (WalkEditDist(a, b) <= Max(StrLen(a), StrLen(b)) // 4)
		return true
	if (name = "")
		return false
	nlGot := 0
	for each, nlWord in StrSplit(RegExReplace(name, "[^A-Za-z]+", " "), " ")
		{
		nlWord := WalkLetters(nlWord), nlLen := StrLen(nlWord)
		if (nlLen < 3)
			continue
		if (WalkWordIn(nlWord, a) > (nlLen >= 5 ? nlLen // 4 : 0))
			return false
		nlGot += nlLen
		}
	return nlGot * 4 >= StrLen(b) * 3
	}

;The fewest letters changed, dropped or added that put word somewhere in a - the edit distance with the match free to start
;and end anywhere in a (both WalkLetters')
WalkWordIn(word, a)
	{
	wiLen := StrLen(word), wiCol := []
	Loop wiLen + 1
		wiCol.Push(A_Index - 1)
	wiBest := wiLen
	Loop Parse, a
		{
		wiC := A_LoopField, wiDiag := 0
		Loop wiLen
			{
			wiOld := wiCol[A_Index + 1]
			wiCol[A_Index + 1] := Min(wiOld + 1, wiCol[A_Index] + 1, wiDiag + (SubStr(word, A_Index, 1) == wiC ? 0 : 1))
			wiDiag := wiOld
			}
		wiBest := Min(wiBest, wiCol[wiLen + 1])
		}
	return wiBest
	}

;A prompt's name letters (key) an NPC's (name: as the game writes it, or as its quest marker's green name reads), allowing for
;OCR at its worst: WalkNameLike's slips; or each of name's words of 3 letters or more somewhere in key with up to 2 letters in 5
;changed, dropped or added (1 in a word of 5 letters, none in a shorter one), a third of those words' letters at most all told
;and those words three quarters of name's letters; or its last word - the surname, the part that tells one NPC from another
;(not ENGINEER, PROFESSOR, SERGEANT) - of 5 letters or more there with up to 3 in 10, one other word at most lost (cut off,
;garbled past that), the words there half name's letters at least. A small UI's prompt comes out like that (2026-11-01 11:50,
;UI scale 0.86: 'ENGDCERMONTGWRY', 'MONTGOQYPRESSXTOTALK', 'ERMENGQMONTGWRYPRESSXORYCENTER' for Engineer Montgomery's own
;prompt - no X, NEEDS YOU); the NPCs by him aren't him (RACE CONRAD ENGINEER; Bartholomew by Edith Benchley). Two of the same
;surname side by side, one's first name lost, would pass - X at the other: its chatter, a try used (WalkTalkCount)
WalkNpcLike(key, name)
	{
	nkAll := WalkLetters(name)
	if (WalkNameLike(key, nkAll, name))
		return true
	if (StrLen(key) < 4 || StrLen(nkAll) < 4)
		return false
	nkWords := [], nkErrs := []
	for each, nkWord in StrSplit(RegExReplace(name, "[^A-Za-z]+", " "), " ")
		{
		nkWord := WalkLetters(nkWord)
		if (StrLen(nkWord) >= 3)
			nkWords.Push(nkWord), nkErrs.Push(WalkWordIn(nkWord, key))
		}
	if (!nkWords.Length)
		return false
	nkLen := 0, nkErr := 0, nkGot := 0, nkLost := 0
	for nkI, nkWord in nkWords
		{
		nkN := StrLen(nkWord), nkLen += nkN
		if (nkErrs[nkI] <= (nkN >= 6 ? nkN * 2 // 5 : nkN = 5 ? 1 : 0))
			nkGot += nkN, nkErr += nkErrs[nkI]
		else
			nkLost += 1
		}
	;(every word there, garbled)
	if (!nkLost && nkLen * 4 >= StrLen(nkAll) * 3 && nkErr * 3 <= nkLen)
		return true
	;(a word lost - the last one there)
	nkN := StrLen(nkWords[nkWords.Length])
	return nkN >= 5 && nkErrs[nkWords.Length] <= nkN * 3 // 10 && nkLost <= 1 && nkGot * 2 >= StrLen(nkAll)
	}

;How many letters added, dropped or changed turn a into b (Levenshtein)
WalkEditDist(a, b)
	{
	la := StrLen(a), lb := StrLen(b)
	prev := []
	;(v2: an Array grows by Push - each index here is the next one, as v1's assignment made it)
	Loop lb + 1
		prev.Push(A_Index - 1)
	Loop la
		{
		i := A_Index, ca := SubStr(a, i, 1), cur := [i]
		Loop lb
			{
			j := A_Index
			cost := (ca == SubStr(b, j, 1)) ? 0 : 1
			cur.Push(Min(prev[j + 1] + 1, cur[j] + 1, prev[j] + cost))
			}
		prev := cur
		}
	return prev[lb + 1]
	}

;The quest's goal line under the arrow, read at most every 3 s - from the game's memory when it can be (WalkGoalText),
;else by OCR (the arrow not on screen: where it usually is)
WalkGoalLine()
	{
	global WkGoalLineAt, WkGoalFrom, WkGoalLine ; (v1 globals it sets)
	if (WkGoalLineAt && A_TickCount - WkGoalLineAt < 3000)
		return WkGoalLine
	WkGoalLineAt := A_TickCount
	text := WalkGoalText()
	if (text = "")
		{
		s := ArrowScale().scale
		px := GameLeft + GameW / 2 - 0.7 * s, py := GameTop + GameH - 220 * s + 81.7 * s
		text := OcrRect(Round(px - 450 * s), Round(py + 28 * s), Round(900 * s), Round(60 * s))
		text := ErrorLevel ? "" : Trim(RegExReplace(text, "\s+", " "))
		WkGoalFrom := text != "" ? "the screen" : ""
		}
	;(what the quest's goal line says, in the log when it changes - which mobs are the quest's comes from it: from the
	;game's memory each time it changes (it's exact); read off the screen at most once in 30 s, OCR slips change it too)
	static said := "", saidAt := 0
	if (text != "" && text != said && (WkGoalFrom = "the game" || !saidAt || A_TickCount - saidAt > 30000))
		said := text, saidAt := A_TickCount, WalkLog("the quest's goal line: " SubStr(text, 1, 120) " (from " WkGoalFrom ")")
	WkGoalLine := text
	return text
	}

;What X at a prompt opened, if it's not a dialogue - only what's new since just before X (WkPreXText), in the
;middle of the game where its windows open (not the chat, the prompt or the goal line): a window with a shop's
;words (Buy, Sell, Shop, Crowns...) - closed with Escape, nothing in it clicked (never anything that could
;spend); else a lone OK / Okay button on a line of its own - an OK box - clicked (never with Crowns on screen).
;Escape that opened the game's menu instead closes it again. True if it closed something
WalkCloseAfterX()
	{
	t := WalkAfterXText(&lines)
	if (t = "" || !IsObject(lines))
		return false
	if (RegExMatch(t, "i)\b(buy|sell|shop|cr[o0]wns?|purchase|recipes|reagents|treasure cards)\b", &m) && !RegExMatch(WkPreXText, "i)\b\Q" m[0] "\E\b"))
		{
		WalkLog("pressed X: a window opened (`"" m[0] "`" in it - a shop?) - Escape, nothing in it clicked")
		PressKey("Escape")
		Sleep(800)
		WalkCloseGameMenu()
		;(a shop Escape doesn't close - 2026-10-23 07:11, Avery Templeton's Recipe Shop: its Escape opened the game's menu,
		;the shop stayed and held the wizard 3 minutes - its close button)
		WalkCloseWindow("the shop didn't close with Escape", true)
		return true
		}
	;(an OK with Crowns anywhere in sight is never clicked)
	if (RegExMatch(t, "i)cr[o0]wn"))
		return false
	for i, line in lines
		if (IsObject(line.words) && line.words.Length = 1 && RegExMatch(Trim(line.words[1].text), "i)^(ok|okay)[.!]?$")
			&& !RegExMatch(WkPreXText, "i)\b(ok|okay)\b"))
			{
			w := line.words[1]
			if (!Walking || !GameActive())
				return false
			WalkLog("pressed X: an OK box opened - OK")
			ReleaseKeys()
			;(the mouse back where it was afterwards, in AutoFarmer: mousereturn)
			ownGrab := V1IsFunc("MouseGrab") ? %"MouseGrab"%.Call() : false
			;(your mouse locked meanwhile, in AutoFarmer - Settings.ahk MouseLockOn)
			if (V1IsFunc("MouseLockOn"))
				%"MouseLockOn"%.Call("walker")
			MouseMove(Round(w.x + w.w / 2), Round(w.y + w.h / 2), 2)
			;(its clicks too, now the pointer's on the game - Settings.ahk MouseLockMoved)
			if (V1IsFunc("MouseLockMoved"))
				%"MouseLockMoved"%.Call()
			Sleep(60)
			Click()
			Sleep(500)
			if (ownGrab)
				%"MouseLetGo"%.Call()
			if (V1IsFunc("MouseLockOff"))
				%"MouseLockOff"%.Call("walker")
			return true
			}
	return false
	}

;An open window's close button - the red X in a brown ring at the bottom right of shops and the like (AutoFarmer's
;resources\closewin.png, cut 2026-10-23 at UI 1.144 off a Recipe Shop) - clicked: never with Crowns anywhere in sight (the
;game read first; then you're told instead), never more than once in 5 s (now: a shop just opened). True if one was there
;and went
WalkCloseWindow(why, now := false)
	{
	global WkCloseLook, WkBestTime, WkLastRead ; (v1 globals it sets)
	if (!V1IsFunc("PicOpt") || !Walking || !GameActive() || (!now && A_TickCount - WkCloseLook < 5000))
		return false
	WkCloseLook := A_TickCount
	V1ImageSearch(&cwX, &cwY, Round(GameLeft + GameW * 0.3), Round(GameTop + GameH * 0.3), Round(GameLeft + GameW * 0.92), Round(GameTop + GameH * 0.95), %"PicOpt"%.Call("resources\closewin.png", 50))
	if (ErrorLevel)
		return false
	cwT := OcrRect(GameLeft, GameTop, GameW, GameH)
	;(not read: not clicked - Crowns can't be ruled out)
	if (ErrorLevel)
		{
		WalkLog(why " - a window's close button is there, but the game couldn't be read for Crowns: not clicked")
		return false
		}
	if (RegExMatch(cwT, "i)cr[o0]wn"))
		{
		WalkLog(why " - a window's close button is there, but Crowns are in sight: not clicked")
		WalkNotify("window", "A window is open", "A window is open over the game (" why ") and Crowns are in sight, so the bot doesn't click its close button. Close it yourself.")
		return false
		}
	ReleaseKeys()
	;(the picture's middle - it's 60 px at UI 1.144; the mouse back where it was afterwards, in AutoFarmer: mousereturn)
	;(UiScale: AutoFarmer's - this needs PicOpt, AutoFarmer's too)
	cwHalf := Round(30 * (UiScale ? UiScale : 1.144) / 1.144)
	ownGrab := V1IsFunc("MouseGrab") ? %"MouseGrab"%.Call() : false
	;(your mouse locked meanwhile, in AutoFarmer - Settings.ahk MouseLockOn)
	if (V1IsFunc("MouseLockOn"))
		%"MouseLockOn"%.Call("walker")
	MouseMove(cwX + cwHalf, cwY + cwHalf, 2)
	;(its clicks too, now the pointer's on the game - Settings.ahk MouseLockMoved)
	if (V1IsFunc("MouseLockMoved"))
		%"MouseLockMoved"%.Call()
	Sleep(80)
	Click()
	Sleep(700)
	if (ownGrab)
		%"MouseLetGo"%.Call()
	if (V1IsFunc("MouseLockOff"))
		%"MouseLockOff"%.Call("walker")
	V1ImageSearch(&cwX2, &cwY2, Round(GameLeft + GameW * 0.3), Round(GameTop + GameH * 0.3), Round(GameLeft + GameW * 0.92), Round(GameTop + GameH * 0.95), %"PicOpt"%.Call("resources\closewin.png", 50))
	cwGone := ErrorLevel != 0
	WalkLog(why " - clicked a window's close button at " cwX + cwHalf - GameLeft "," cwY + cwHalf - GameTop ": " (cwGone ? "closed" : "still there"))
	;(the time it held him isn't walking without getting closer: the stuck watch starts afresh)
	if (cwGone)
		WkBestTime := A_TickCount, WkLastRead := A_TickCount
	return cwGone
	}

;The middle of the game - where a window X opens shows: not the chat (bottom left), the prompt or the goal line
;(bottom), the walker's notice (top right) - read by OCR. "" if it can't be read; its lines (with their words)
WalkAfterXText(&lines)
	{
	lines := ""
	t := OcrRect(Round(GameLeft + GameW * 0.25), Round(GameTop + GameH * 0.12), Round(GameW * 0.5), Round(GameH * 0.58), "en", 1, &lines)
	return ErrorLevel ? "" : t
	}

;Screen {x, y} of the middle of the Spiral Map's Go To World button, or "" if the map isn't open. By the game's memory first
;(SpiralMapMem); not told by it (no helper - AutoQuester on its own -, navmem off, its windows not found): read by OCR in the
;lower right part of the map (it sits in the middle of the game, sized with the UI) - memOnly: not
SpiralMapButton(memOnly := false)
	{
	smm := SpiralMapMem(&smKnown)
	if (IsObject(smm) || smKnown || memOnly)
		return smm
	s := ArrowScale().scale
	x := Round(GameLeft + GameW / 2 + 60 * s), y := Round(GameTop + GameH / 2 + 200 * s)
	w := Round(500 * s), h := Round(240 * s)
	if (y + h > GameTop + GameH)
		h := GameTop + GameH - y
	lineRects := ""  ; (v1: a ByRef output OcrRect may leave unset was blank)
	OcrRect(x, y, w, h, "en", 1, &lineRects)
	if (ErrorLevel || !IsObject(lineRects))
		return ""
	for each, line in lineRects
		if (RegExMatch(line.text, "i)go\s*to\s*w[o0]rld"))
			return V1Obj({x: Round(line.x + line.w / 2), y: Round(line.y + line.h / 2)})
	return ""
	}

;The Spiral Map's Go To World button by the game's memory (AutoFarmer's NavGui - read-only): {x, y (screen), world (the one
;ticked - the quest's, as the game opens it; "" not read), mem: 1} with the map up - its button shown once, not greyed, its
;words "Go To World" or the map's title "Spiral Map", no message box over it; "" not. known: 1 when the memory told (its
;button found: up, or hidden - closed), 0 when it can't say (no helper - AutoQuester on its own -, navmem off, not found).
;Its windows read 2026-11-13 04:45 with the map up (UI 0.856, the GUI 1827x1027): an unnamed UniverseMapWindow, messageBoxBG
;514,214-1314,814 - title "Spiral Map", teleportButton "Go To World" 1079,772-1206,805, cancelButton "Exit", optionWindow
;opt0..opt3 (check boxes, the worlds on the page shown: Grizzleheim's checked). 2026-11-13 00:16: the prompt read as a plain
;'WORLDGATE' one, its X then Spaced 45 times, the map left open over 4 hours (an inactivity kick every 16 minutes)
SpiralMapMem(&known)
	{
	known := 0
	if (!V1IsFunc("NavGui"))
		return ""
	smPaths := "messageBoxBG/title,messageBoxBG/teleportButton,optionWindow/opt0,optionWindow/opt1,optionWindow/opt2,optionWindow/opt3"
	g := %"NavGui"%.Call(smPaths, 600)
	if (!IsObject(g) || !g.rootW || !g.rootH)
		return ""
	smB := g.win["messageBoxBG/teleportButton"], smT := g.win["messageBoxBG/title"]
	if (!IsObject(smB) || !smB.found)
		return ""
	known := 1
	if (!smB.shown || smB.dups != 1 || smB.greyed = 1 || g.box.shown || smB.l = "" || smB.t = "" || smB.r = "" || smB.b = ""
		|| smB.r <= smB.l || smB.b <= smB.t)
		return ""
	if (!RegExMatch(smB.text, "i)go\s*to\s*w[o0]rld") && !(IsObject(smT) && smT.shown && RegExMatch(smT.text, "i)spiral\s*map")))
		return ""
	smWorld := ""
	Loop 4
		{
		smO := g.win["optionWindow/opt" (A_Index - 1)]
		if (IsObject(smO) && smO.shown && smO.checked = 1)
			smWorld := smO.text
		}
	return V1Obj({x: Round(GameLeft + (smB.l + smB.r) / 2 * GameW / g.rootW), y: Round(GameTop + (smB.t + smB.b) / 2 * GameH / g.rootH)
		, world: smWorld, mem: 1})
	}

;The Spiral Map up by the game's memory - looked at once in 1.5 s at most - while the walker waits on something else (WalkStep:
;X at a prompt read as a plain one, no arrow - the map left open, a restart under it): true - on to the World Gate's step
;(WkArrived 4: GateStep clicks Go To World). why: what it was waiting on, for the log
WalkSpiralMapUp(why)
	{
	global WkMapLook, WkArrived, WkGateAt, WkGateClicks, WkGateX ; (v1 globals it sets)
	if (WkMapLook && A_TickCount - WkMapLook < 1500)
		return false
	WkMapLook := A_TickCount
	smu := SpiralMapButton(true)
	if (!IsObject(smu))
		return false
	if (KeysDown || HeldW || SpeedNow > 1)
		ReleaseKeys()
	WalkLog(why ": the Spiral Map is open (the game's memory" (smu.world != "" ? " - " smu.world " picked" : "") ") - a World Gate: Go To World")
	WkArrived := 4, WkGateAt := A_TickCount, WkGateClicks := 0, WkGateX := 1
	return true
	}

;Moves the mouse there and clicks (screen coordinates), only while walking is on and Wizard101 has focus
WalkClick(x, y)
	{
	global MsWinAt ; (v1 globals it sets)
	MsWinAt := 0
	if (!Walking || !GameActive())
		return
	;(the mouse back where it was afterwards, in AutoFarmer: mousereturn)
	ownGrab := V1IsFunc("MouseGrab") ? %"MouseGrab"%.Call() : false
	;(your mouse locked meanwhile, in AutoFarmer - Settings.ahk MouseLockOn: the Spiral Map's Go To World, ACCEPT...)
	if (V1IsFunc("MouseLockOn"))
		%"MouseLockOn"%.Call("walker")
	MouseMove(x, y, 1)
	;(its clicks too, now the pointer's on the game - Settings.ahk MouseLockMoved)
	if (V1IsFunc("MouseLockMoved"))
		%"MouseLockMoved"%.Call()
	Sleep(40)
	if (Walking && GameActive())
		Click()
	Sleep(100)
	if (ownGrab)
		%"MouseLetGo"%.Call()
	if (V1IsFunc("MouseLockOff"))
		%"MouseLockOff"%.Call("walker")
	}

;One key press (down and up), only while walking is on and Wizard101 has focus
PressKey(key)
	{
	global MsWinAt ; (v1 globals it sets)
	Critical()
	;(a window may open: the mouse's look for one done afresh - MouseSteer.ahk)
	MsWinAt := 0
	if (Walking && GameActive())
		Send("{Blind}{" key "}")
	Critical("Off")
	}

;Switches walking on or off (F8). Off lets go of every key straight away
WalkToggle()
	{
	global Walking, WkJumpStuck, WkJumpKey, NavUnblock, Refocus ; (v1 globals it sets)
	;(AutoFarmer's battles only - Settings: battlesonly: walking stays off, and F8 says why - a tray tip. AutoQuester has none)
	if (!Walking && V1IsFunc("BattlesOnlyNo") && %"BattlesOnlyNo"%.Call("walking (" WalkKeyText() ")", true))
		return
	WalkNotifyClose()
	Walking := !Walking
	if (Walking)
		{
		;(a collect goal given up on gets another go - a goal to use things: the ones left for a while tried again, as Keep trying
		;does - Collect.ahk)
		if (IsObject(WkCollect) && WkCollect.gaveUp)
			{
			WkCollect.gaveUp := 0, WkCollect.from := A_TickCount, WkCollect.progressAt := A_TickCount, WkCollect.stepAt := A_TickCount
			if (V1IsFunc("UseForget"))
				%"UseForget"%.Call()
			}
		;(teleports the helper gave up get another go - you may have done what opens one: NavRead, AutoFarmer)
		WkJumpStuck := 0, WkJumpKey := "", NavUnblock := 1
		;(a sigil given up on - "The sigil won't start" - gets another go too: you may have relogged, or want it tried)
		WalkSigilForgive()
		;(a blocked way's hold and tries - AutoFarmer's Puzzle.ahk - forgotten: walking on)
		if (V1IsFunc("PuzzleForget"))
			%"PuzzleForget"%.Call("walking on with " WalkKeyText())
		WalkReset()
		SetStatus("walking on")
		}
	else
		{
		if (KeysDown || HeldW)
			{
			if (!GameActive())
				Refocus := 1
			ReleaseKeys()
			}
		;(a keep-speed stop just before left it fast)
		SpeedSet(0, "walking off (" WalkKeyText() ")")
		SetStatus("walking off - press " WalkKeyText() " to walk again")
		;Keys let go while another window had focus: give Wizard101 one clean release when it's back
		if (Refocus)
			SetTimer(WalkerRefocusWatch,250)
		}
	}

WalkerRefocusWatch()
	{
	local v1KeepGui := V1Thread()  ; (v1: a timer ran as its own thread - the ErrorLevel its WalkLog leaves stayed in it)
	global Refocus ; (v1 globals it sets)
	local v1Keep := V1Thread() ; (v1: each thread had its own ErrorLevel)
	if (Walking || !Refocus)
		{
		SetTimer(WalkerRefocusWatch,0)
		return
		}
	if (GameActive())
		{
		ReleaseKeys()
		Refocus := 0
		SetTimer(WalkerRefocusWatch,0)
		}
	}

;Holds A (goal to the left) or D (goal to the right) long enough to turn h degrees. Steering by the game's
;memory (its heading agreed with the arrow's): held until the wizard's own facing, re-read as it turns, has
;turned that far (NavTurn) - else for as long as TurnRate says
Turn(h)
	{
	global MsStandGot, WkTurnAt, KeysDown, WkNavSign ; (v1 globals it sets)
	;(a game sped up more than 5 times turns too far in the shortest key press: turns at normal speed)
	if (SpeedNow > 5)
		SpeedSet(0, "a turn")
	;(by the mouse - steadier than A/D (2026-10-24: the keyboard only when the mouse fails): running, the mouse turns him;
	;standing, it turns the camera and W sends him the new way - MouseSteer.ahk. A/D when it couldn't)
	;(only with the heading's sign checked: the mouse can't tell it turned the wrong way - A/D's check below does)
	if (Abs(h) >= 3 && Abs(h) <= 180 && MsK != "" && V1IsFunc("MouseTurnAny") && !(MsTriedAt && A_TickCount - MsTriedAt < 500)
		&& WkNavChecked && WkNavTrusted && MouseSteerWhyNot(HeldW ? true : false, false) = "")
		{
		MsStandGot := ""
		if (MouseTurnAny(h) != "")
			return
		;(a turn from standing by the mouse that missed may have turned him part of the way, or past: the rest - not h again
		;on top. 2026-10-25 11:42:26: 158 wanted, the mouse -168 (192 right), then A/D 158 more)
		if (MsStandGot != "" && Abs(MsStandGot) >= 3)
			{
			h := ArrowWrap(h - MsStandGot)
			if (Abs(h) < 3)
				{
				WkTurnAt := A_TickCount
				return
				}
			}
		}
	if (WkNavUse && NavTurn(h))
		return
	Critical()
	if (!Walking || !GameActive())
		{
		Critical("Off")
		return
		}
	key := h < 0 ? "a" : "d"
	ms := Round(Abs(h) / (TurnRate * SpeedNow))
	ms := ms < 30 ? 30 : ms > 800 ? 800 : ms
	;(the game's memory readable this step but its heading's sign not checked yet - or checked, but not steered by
	;since: a turn froze by a battle starting - the wizard's facing before and after this turn checks it: see the end)
	yaw0 := (WkNavOk && (!WkNavChecked || !WkNavTrusted) && IsObject(WkNavObj) && V1IsFunc("NavRead")) ? WkNavObj.yaw : ""
	KeysDown := 1
	Send("{Blind}{" key " down}")
	Critical("Off")
	HoldFor(ms)
	Send("{Blind}{" key " up}")
	WkTurnAt := A_TickCount
	if (yaw0 != "" && Walking)
		{
		Sleep(120)
		nav := %"NavRead"%.Call(120)
		if (IsObject(nav) && nav.yaw != "")
			{
			turned := WkNavSign * ArrowWrap((nav.yaw - yaw0) * 57.29578)
			;(a fair way round: which way round its heading is, is settled - the keys turn the wizard. Its sign
			;checked already: only a turn the way it said counts - not one to turn it round on)
			if (WkNavChecked && turned * h < 0)
				turned := 0
			if (Abs(turned) >= 15 && turned * h < 0)
				{
				WkNavSign := -WkNavSign, turned := -turned
				WalkLog("turn: holding " key " turned the wizard " Round(Abs(turned)) " degrees the other way than the game's memory's heading said - turned its sign round")
				}
			if (Abs(turned) >= 15)
				WalkNavConfirm("holding " key " turned the wizard " Round(Abs(turned)) " degrees the way its heading said")
			}
		}
	}

;Back up, turn UnstickTurn degrees to one side and walk along the obstacle for walkMs
Unstick(side, walkMs)
	{
	global WkSpeedHold ; (v1 globals it sets)
	;(at normal speed - backing up, turning and walking off as measured - and for a few seconds after)
	WkSpeedHold := A_TickCount + walkMs + 1500
	SpeedSet(0, "getting round an obstacle")
	BackUp(BackupTime)
	if (!Walking || !GameActive())
		return
	Turn(UnstickTurn * side)
	if (!Walking || !GameActive())
		return
	WkSpeedHold := A_TickCount + walkMs + 1500
	HoldW(1)
	HoldFor(walkMs)
	}

;Holds S for ms (W let go first). False if it didn't: walking off, Wizard101 not in front, or a mob's reach or sight
;behind (the helper's blind check)
BackUp(ms)
	{
	global WkBlindBackSaid, MsStandGot, WkTurnAt, KeysDown ; (v1 globals it sets)
	;(blind - straight back: not into a mob's reach or sight - the helper's blind check on this moment's reading - looked
	;at before W comes up: a refusal walks on)
	if (IsObject(WkNavObj) && WkNavObj.blindback != "" && IsObject(WkNavPrev) && A_TickCount - WkNavPrev.at < 1500)
		{
		if (A_TickCount - WkBlindBackSaid > 10000)
			WkBlindBackSaid := A_TickCount, WalkLog("not backing up: " WkNavObj.blindback "'s reach or sight is behind the wizard")
		return false
		}
	;(the wizard running: by the mouse - turned round, walked off for as long, turned back to face the way he was: no S
	;key (2026-10-24: the mouse is the steadier). Standing - the mouse turns only the camera then - or the mouse can't:
	;S, as before)
	if (MsK != "" && V1IsFunc("MouseTurnAny") && (WkNavTrusted || WkNavChecked) && !(MsTriedAt && A_TickCount - MsTriedAt < 500)
		&& MouseSteerWhyNot(HeldW ? true : false, false, true) = "")
		{
		MsStandGot := ""
		round1 := MouseTurnAny(180)
		if (round1 != "" && Abs(round1) >= 120)
			{
			;(walked off - long enough that the mouse turns him back running, not standing with a step back in)
			HoldW(1, true)
			HoldFor(Max(Round(ms / SpeedNow), 650))
			;(running: turned back by the mouse - not running long enough for that yet: standing, MouseStandTurn, then A/D)
			back := MouseTurnAny(-round1)
			;(the turn back by the mouse missed: standing, by the mouse again - else A/D - he mustn't walk on the wrong way)
			if (back = "")
				HoldW(0), NavTurnOrKeys(-round1)
			WkTurnAt := A_TickCount
			return true
			}
		;(turned part of the way and stopped: turned back first)
		if (round1 != "" && Abs(round1) >= 3)
			MouseTurn(-round1, false)
		;(a turn from standing by the mouse that missed but turned him: turned back before S - else S backs him off the wrong
		;way. 2026-10-25 11:29:50: the mouse turned -133 of 180, S, then a 133 turn back the next step)
		else if (round1 = "" && MsStandGot != "" && Abs(MsStandGot) >= 3)
			NavTurnOrKeys(-MsStandGot)
		}
	HoldW(0)
	Critical()
	if (!Walking || !GameActive())
		{
		Critical("Off")
		return false
		}
	KeysDown := 1
	Send("{Blind}{s down}")
	Critical("Off")
	HoldFor(Round(ms / SpeedNow))
	Send("{Blind}{s up}")
	WkTurnAt := A_TickCount
	return true
	}

;A turn standing still (BackUp's way back when the mouse's missed): by the game's memory if it can, else A/D held
NavTurnOrKeys(h)
	{
	global MsStandGot, KeysDown, WkTurnAt ; (v1 globals it sets)
	MsStandGot := ""
	if (MouseStandTurn(h) != "")
		return
	;(the mouse missed but turned him: the rest, not h again on top)
	if (MsStandGot != "" && Abs(MsStandGot) >= 3)
		{
		h := ArrowWrap(h - MsStandGot)
		if (Abs(h) < 3)
			return
		}
	if ((WkNavUse || WkNavTrusted || WkNavChecked) && NavTurn(h))
		return
	key := h < 0 ? "a" : "d"
	ms := Round(Abs(h) / (TurnRate * (SpeedNow ? SpeedNow : 1)))
	ms := ms < 30 ? 30 : ms > 800 ? 800 : ms
	Critical()
	if (!Walking || !GameActive())
		{
		Critical("Off")
		return
		}
	KeysDown := 1
	Send("{Blind}{" key " down}")
	Critical("Off")
	HoldFor(ms)
	Send("{Blind}{" key " up}")
	WkTurnAt := A_TickCount
	}

;Waits ms, but returns early (false) once walking is stopped or Wizard101 loses focus
HoldFor(ms)
	{
	global Refocus ; (v1 globals it sets)
	stopAt := A_TickCount + ms
	while (A_TickCount < stopAt)
		{
		if (!Walking)
			return false
		if (!GameActive())
			{
			if (KeysDown || HeldW)
				ReleaseKeys(), Refocus := 1
			return false
			}
		left := stopAt - A_TickCount
		Sleep(left < 50 ? left : 50)
		}
	return true
	}

;noSpeed: no speed key now (the next step's HoldW sees to it)
HoldW(on, noSpeed := false)
	{
	global KeysDown, HeldW, WkWalkFrom ; (v1 globals it sets)
	Critical()
	if (on && !HeldW && Walking && GameActive())
		{
		KeysDown := 1
		Send("{Blind}{w down}")
		HeldW := 1, WkWalkFrom := A_TickCount
		WalkMetW(1)
		}
	else if (!on && HeldW)
		{
		Send("{Blind}{w up}")
		HeldW := 0
		WalkMetW(0)
		}
	Critical("Off")
	;(walking: Cheat Engine's speed for it, if that's on)
	if (on && HeldW && !noSpeed)
		SpeedWalking()
	}

;{Blind} so an Alt/Ctrl/Shift the user is holding isn't let go. Stopping: the game back to normal speed (Cheat Engine)
;- keepSpeed: the walker's own short stop (a mob or the party waited for, the arrow gone a moment): the speed kept, 1x
;once it's stood 1.5 s (WalkStep)
ReleaseKeys(keepSpeed := false)
	{
	global HeldW, KeysDown ; (v1 globals it sets)
	;(the right button too, if a mouse turn held it - MouseSteer.ahk)
	if (MsHeld)
		MouseSteerButton(0)
	Send("{Blind}{w up}{a up}{s up}{d up}")
	if (HeldW)
		WalkMetW(0)
	HeldW := 0, KeysDown := 0
	if (!keepSpeed)
		SpeedSet(0, "stopped")
	}

;W's time held, and stops (W coming up), for the minute's line; when W last came up (the 1x after standing)
WalkMetW(down)
	{
	global WkMet, WkWUpAt ; (v1 globals it sets)
	if (!IsObject(WkMet))
		WkMet := V1Obj({wms: 0, wfrom: 0, stops: 0, spot: 0, walkturns: 0, keys: 0, act: 0, last: 0, mturns: 0})
	if (down)
		WkMet.wfrom := A_TickCount
	else
		{
		if (WkMet.wfrom)
			WkMet.wms += A_TickCount - WkMet.wfrom
		WkMet.wfrom := 0, WkMet.stops += 1, WkWUpAt := A_TickCount
		}
	}

;Once a minute, after walking: how smooth it was - W held (of the time it was out to walk: walking, pushing on, collecting -
;not battles, talks, waits at a sigil or gate, the game behind another window, you playing), stops, turns on the spot and
;walking on, speed keys pressed; the walking speed and turning circle learned. Each step: its time counted
WalkMetrics()
	{
	global WkMetAt ; (v1 globals it sets)
	if (!IsObject(WkMet))
		return
	gap := WkMet.last ? A_TickCount - WkMet.last : 0
	if (gap > 0 && gap < 2000 && Walking && GameActive() && !PlayerActive && (WkArrived = 0 || WkArrived = 3 || WkArrived = 7))
		WkMet.act += gap
	WkMet.last := A_TickCount
	if (A_TickCount - WkMetAt < 60000)
		return
	held := WkMet.wms + (WkMet.wfrom ? A_TickCount - WkMet.wfrom : 0)
	if (held > 3000 && WkMet.act > 5000)
		WalkLog("the last minute: W held " Min(100, Round(100 * held / WkMet.act)) "% of " Round(WkMet.act / 1000) " s out walking, " WkMet.stops " stops, " WkMet.spot " turns on the spot, " WkMet.walkturns " turns walking on (" (WkMet.mturns ? WkMet.mturns : 0) " by the mouse), " WkMet.keys " speed keys"
			. (WkWalkSpeed != "" ? " (walks " Round(WkWalkSpeed * 1000) " a second at 1x, turning circle " Round(TurnRadius) ")" : " (turning circle " TurnRadius " till it's measured at 1x)"))
	WkMet.wms := 0, WkMet.stops := 0, WkMet.spot := 0, WkMet.walkturns := 0, WkMet.keys := 0, WkMet.act := 0, WkMet.mturns := 0
	if (WkMet.wfrom)
		WkMet.wfrom := A_TickCount
	WkMetAt := A_TickCount
	}

;The wizard's turning circle for the helper's arc look (game units, a fifth more to be safe): the mouse's small one
;(a mouse turn takes ~0.1 s: the wizard walks on ~100 units meanwhile at 1x - 120, times the speed: the turn's time is
;the bot's, the walking the game's) when the mouse may steer now (as MouseSteerWhyNot - its window look done here,
;before the reading), else A/D's. Kept as sent (WkArcSentR, WkArcMouse) - an arc looked at for the mouse's circle is no
;use to A/D's
WalkTurnRadius()
	{
	global WkArcMouse, WkArcSentR ; (v1 globals it sets)
	WkArcMouse := V1IsFunc("MouseSteerOn") && MouseSteerOn() && MsK != "" && !(MsOffUntil && A_TickCount < MsOffUntil) && SpeedNow <= 5
		&& GameActive() && !PlayerActive && UserIdle() >= 3000 && (WkArrived = 0 || WkArrived = 3 || WkArrived = 7)
		&& MouseSteerWindowClear()
	WkArcSentR := WkArcMouse ? Round(120 * Max(1, SpeedNow ? SpeedNow : 1)) : Round((TurnRadius ? TurnRadius : 400) * 1.2)
	return WkArcSentR
	}

;---- Cheat Engine's speedhack (AutoFarmer's Settings window: speedhack) ----
;Cheat Engine (yours - installed, attached to Wizard101 and its hotkeys set by you) speeds the game up; the bot only
;presses its hotkeys: speedkeyfast (the speed speedfactor) while walking, speedkeynormal (1x) for everything else -
;battles, talking, dialogues, shops, near the goal, getting round an obstacle, when you play, F6, and when it stops.
;F13-F24: no keyboard has them, nothing else uses them

;Whether the speedhack's on (AutoFarmer's speedhack setting; AutoQuester by itself: never)
SpeedOn()
	{
	return SpeedSetting() && SpeedFactor() > 1 && SpeedOff = ""
	}

;The speedhack setting switched on (AutoFarmer's Settings window)
SpeedSetting()
	{
	return V1IsFunc("Stat") && %"Stat"%.Call("speedhack") = 1
	}

;The speed Cheat Engine's walking key sets (speedfactor, 1-50)
SpeedFactor()
	{
	f := V1IsFunc("Stat") ? %"Stat"%.Call("speedfactor") : 1
	;(v1: a blank or text setting + 0 was blank, >= 1 false)
	return V1Ge(V1Add(f, 0), 1) ? Min(f + 0, 50) : 1
	}

;Cheat Engine's key for walking (fast) or for 1x: speedkeyfast / speedkeynormal, F13-F24 (1 = F13)
SpeedKey(fast)
	{
	n := V1IsFunc("Stat") ? %"Stat"%.Call(fast ? "speedkeyfast" : "speedkeynormal") : 0
	;(v1: a blank or text setting + 0 was blank, compared as text: >= 1 false)
	n := (V1Ge(V1Add(n, 0), 1) && V1Le(V1Add(n, 0), 12)) ? n + 0 : (fast ? 2 : 1)
	return "F" (12 + n)
	}

;The game to walking speed (fast true, the speedhack on) or normal: Cheat Engine's key pressed when that changes.
;force: the 1x key pressed even when it should be at 1x already (a battle round, F6 off, the bot stopping) - a press
;Cheat Engine missed, a speed set by hand - only with the speedhack set up (never a key you didn't give it). The key is
;held 250 ms - Cheat Engine looks at its hotkeys every 100 ms - and two presses are 400 ms apart at least (it takes no
;second press within 350 ms). The speed counts as changed before the key goes, so F6 / F8 / exit meanwhile set it back.
;why: for debug.log
SpeedSet(fast, why := "", force := false)
	{
	global SpeedNow, SpeedSentAt ; (v1 globals it sets)
	want := (fast && SpeedOn()) ? SpeedFactor() : 1
	SpeedNow := SpeedNow ? SpeedNow : 1
	if (want = SpeedNow && !(force && want = 1 && (SpeedSentAt || SpeedSetting())))
		return
	key := SpeedKey(want > 1)
	gap := SpeedSentAt ? 400 - (A_TickCount - SpeedSentAt) : 0
	SpeedNow := want, SpeedSentAt := A_TickCount
	;(a caller's own Critical kept - AutoFarmer's GameTrayHide, Critical till the game's in the tray, switches the bot
	;off on the way: its 1x press)
	spCrit := A_IsCritical
	Critical()
	if (gap > 0)
		Sleep(gap)
	Send("{Blind}{" key " down}")
	Sleep(250)
	Send("{Blind}{" key " up}")
	SpeedSentAt := A_TickCount
	if (!spCrit)
		Critical("Off")
	if (IsObject(WkMet))
		WkMet.keys += 1
	WalkLog("speed: " want "x - " key (why != "" ? " (" why ")" : ""))
	}

;Walking: fast - or normal near the goal (no running past an NPC or a door), and for a while after getting round an
;obstacle
SpeedWalking()
	{
	if (!SpeedOn())
		return SpeedSet(0)
	if (A_TickCount < WkSpeedHold)
		return SpeedSet(0, "getting round an obstacle")
	;(a dungeon run, collecting round a spot, a teleport on the game's path walked into - its loading screen - or no
	;distance to the goal known: normal speed)
	;(DgRun: AutoFarmer's dungeon run - blank in AutoQuester, as in v1)
	if (IsObject(DgRun))
		return SpeedSet(0, "a dungeon run")
	;(a blocked way's tries - AutoFarmer's Puzzle.ahk: guards walked into, a gate looked at - at 1x throughout)
	if (V1IsFunc("PuzzleRunning") && %"PuzzleRunning"%.Call())
		return SpeedSet(0, "a puzzle")
	if (WkArrived = 7)
		return SpeedSet(0, "collecting")
	if (WkNavJump != "")
		return SpeedSet(0, "a teleport ahead")
	if (WkLastDist = "" && !(WkNavOk && IsObject(WkNavObj) && WkNavObj.dist != ""))
		return SpeedSet(0, "the distance to the goal unknown")
	;(slowed within SpeedSlowDist / Units, fast again only half as far again past it - not on and off at the line)
	k := (SpeedNow > 1) ? 1 : 1.5
	;(the goal zones away by the game's memory: the way out of this zone - SpeedExitUnits, not a whole stretch of every leg at 1x)
	;(v1: hops blank - an older helper's - > 0 compared as text, false)
	spUnits := (WkNavOk && V1Gt(WkNavHops, 0)) ? SpeedExitUnits : SpeedSlowUnits
	if (WkLastDist != "" && WalkNear(WkLastDist, SpeedSlowDist * k, spUnits * k))
		return SpeedSet(0, "near the goal")
	;(the goal in this zone by the game's memory: straight at it too - another floor's, or one round a wall, is near as well)
	spGoal := WalkGoalNear()
	if (IsObject(spGoal) && spGoal.r <= SpeedSlowUnits * k)
		return SpeedSet(0, "near the goal")
	;(no flip to fast and back: fast once W's been held 0.8 s, and not within 3 s of the last press)
	if (SpeedNow <= 1 && (A_TickCount - WkWalkFrom < 800 || (SpeedSentAt && A_TickCount - SpeedSentAt < 3000)))
		return
	SpeedSet(1, "walking")
	}

;How long the camera takes to catch up after a turn, at the game's speed now (TurnSettle at 1x)
WalkSettle()
	{
	return Round(TurnSettle / (SpeedNow ? SpeedNow : 1))
	}

GameActive()
	{
	return WinActive("ahk_class " GameClass " ahk_exe " GameExe)
	}

;How long you've left the keyboard and mouse alone (ms; the bot's own input doesn't count) - as A_TimeIdlePhysical, which
;every check for you goes by. "Play for me" on (AutoFarmer: PlayForMe - its button, green while on; off at every start):
;you're taken as away for good - nothing waits for you, yields to you or keeps its hands off for you. In AutoFarmer, what
;its mouse lock swallowed (your mouse while the bot had it) isn't you either (Settings.ahk MouseLockIdle)
UserIdle()
	{
	static lockIdle := "-"
	;(PlayForMe: AutoFarmer's - blank in AutoQuester, as in v1)
	if (PlayForMe)
		return 2147483647
	if (lockIdle = "-")
		lockIdle := V1IsFunc("MouseLockIdle") ? %"MouseLockIdle"% : 0
	return lockIdle ? lockIdle.Call() : A_TimeIdlePhysical
	}

;The walking on/off key in words, for the messages that say which key to press: AutoFarmer's (Hotkeys.ahk - yours from
;the dashboard's Keys tab), else F8 (AutoQuester's own - it has no Hotkeys.ahk)
WalkKeyText()
	{
	return V1IsFunc("HkText") ? %"HkText"%.Call("walk") : "F8"
	}

;Shows what the walker is doing in the tray tip. In AutoFarmer each new kind of status (walking,
;turning, arrived, stuck...) also goes to debug.log
SetStatus(text)
	{
	global StatusText, StatusKind ; (v1 globals it sets)
	if (text = StatusText)
		return
	StatusText := text
	A_IconTip := StatusPrefix ": " SubStr(text, 1, 110)
	kind := V1At(StrSplit(text, " "), 1)
	if (kind != StatusKind)
		{
		StatusKind := kind
		if (V1IsFunc("DebugLog"))
			%"DebugLog"%.Call("Walk: " text)
		}
	}

;---- Collecting: "collect / defeat N things" goals ----

;Close to the goal (or stuck near it): is it a goal to collect or defeat a number of things? Then start
;collecting (WkArrived = 7) - straight away when the arrow got there, else once nothing has changed for
;CollectWait. After a battle (or X at a prompt) with the same goal still on: carry on collecting. The
;goal line is read at most every 3 s. True if collecting started
CollectCheck(dist)
	{
	global WkArr1At, WkGoalReadAt, WkCollect, WkArrived, WkFar, WkArrDist, WkBestDist, WkBestTime, WkTries ; (v1 globals it sets)
	;(held at a blocked way - AutoFarmer's Puzzle.ahk: no use mode walked into the gate)
	if (V1IsFunc("PuzzleHeld") && %"PuzzleHeld"%.Call())
		return false
	if (WkArrived = 1 && !WkArr1At)
		WkArr1At := A_TickCount
	;(collecting a fight goal's things, or using a use goal's - carried on; going to a place or talking to an NPC the game shows no
	;way to aren't taken up here: the arrow's own arrival with a place, CollectNoPlace without)
	ccMode := IsObject(WkCollect) ? WkCollect.kind : ""
	ccOn := ccMode = "" || ccMode = "fight" || ccMode = "use"
	going := IsObject(WkCollect) && !WkCollect.gaveUp && ccOn
	if (going && A_TickCount - WkCollect.sureAt < 20000)
		{
		StartCollect(WkCollect.text, "same goal as before")
		return true
		}
	;(collecting before a battle or a prompt: check the goal line at once, wherever the arrow is)
	;(not by the distance with the goal zones away by the game's memory: that's by the way out of this zone, not the goal)
	;(v1: hops blank - an older helper's - > 0 compared as text, false)
	;(no closer for 8 s: not while the game's memory has the wizard walking on - going round a wall by the goal isn't stuck by it)
	there := going || (dist <= ArriveDist && !(WkNavOk && V1Gt(WkNavHops, 0))) || (WkArrived = 1 && A_TickCount - WkArr1At > CollectWait) || (A_TickCount - WkBestTime > 8000 && WalkMoveState() < 1)
	if (!there || A_TickCount - WkGoalReadAt < 3000)
		return false
	WkGoalReadAt := A_TickCount
	text := WalkGoalText()
	if (text = "")
		return false
	;(the goal of before changed or not - by the game's memory's goal id, else the goal line read twice alike)
	changed := IsObject(WkCollect) ? CollectGoalChanged(text) : true
	;(the goal it gave up on has changed: the quest moved on - walk on)
	if (IsObject(WkCollect) && WkCollect.gaveUp && changed)
		{
		WalkLog("collect: the goal is now '" text "' (was '" WkCollect.text "') - walking on")
		WkCollect := ""
		WalkNotifyClose("collect")
		if (WkArrived = 1)
			WkArrived := 0, WkFar := 0, WkArrDist := "", WkBestDist := "", WkBestTime := A_TickCount, WkTries := 0
		}
	;(a goal it gave up on - no progress for CollectStall, or CollectMax in all - without it changing: leave it be)
	if (IsObject(WkCollect) && WkCollect.gaveUp)
		return false
	if (IsObject(WkCollect) && !changed && ccOn)
		{
		WkCollect.sureAt := A_TickCount
		StartCollect(WkCollect.text, "same goal as before")
		return true
		}
	if (!CollectGoal(text))
		return false
	;(by the goal's kind - WalkGoalKind: a fight goal's things collected, a use goal's used; going to a place or talking: the arrow's
	;own arrival; anything else - Practice Photomancy - nothing roamed for)
	ccKind := WalkGoalKind(text)
	if (ccKind != "fight" && ccKind != "use")
		return false
	WkCollect := V1Obj({text: text, from: A_TickCount, sureAt: A_TickCount, last: text, gaveUp: 0, battles: 0
		, count: CollectCount(text), progressAt: A_TickCount, stepAt: A_TickCount, goalid: CollectGoalId(), newText: "", kind: ccKind})
	WalkNotifyClose("collect")
	StartCollect(text, ccKind = "use" ? "a goal to use things (the game's memory's kind)" : "a goal to collect / defeat things")
	return true
	}

;Stops collecting a goal (no progress / too long): waits where it is (battles still get fought) and
;shows the collect notice. Only the goal line changing (CollectCheck), Keep trying or F8 off and on end it. title: the notice's
CollectGiveUp(dist, why, title := "Collect quest needs you")
	{
	global WkArrived, WkArrDist, WkFar ; (v1 globals it sets)
	;(AutoFarmer's Puzzle.ahk: what usually opens a blocked way tried first, in a zone that may hold one - it takes over, or this goes
	;on as before)
	if (V1IsFunc("PuzzleBeforeNotice") && %"PuzzleBeforeNotice"%.Call("collect", why))
		return
	WkCollect.gaveUp := 1
	ReleaseKeys()
	WkArrived := 1, WkArrDist := dist, WkFar := 0
	mins := Round(CollectStall / 60000)
	WalkNotify("collect", title, "'" WkCollect.text "' - " why ". The bot waits here (battles still get fought) and walks on once the quest moves on.`n`nKeep trying: " (WkCollect.kind = "use" || WkCollect.kind = "go" || WkCollect.kind = "talk" ? "look again" : "collect again (" mins " minutes without progress)") ". Stop walking: walking off (" WalkKeyText() " turns it back on).", true)
	}

;No arrow, nothing standing in for it (a goal the game shows no way to - collect things lying about the zone): its line
;read where it sits (every 3 s); by its kind (WalkGoalKind): a fight goal's collect line - collecting starts (or goes on: the
;same goal as before); a goal to use things, go to a place or talk to an NPC - their own ways (WkCollect.kind - Collect.ahk
;UseStep, GoStep, TalkStep: the things, the place, the NPC by name); anything else - "Practice Photomancy" - left alone,
;nothing roamed for. True if it did
CollectNoPlace()
	{
	global WkGoalReadAt, WkCollect ; (v1 globals it sets)
	;(held at a blocked way - AutoFarmer's Puzzle.ahk: no use mode walked into the gate)
	if (V1IsFunc("PuzzleHeld") && %"PuzzleHeld"%.Call())
		return false
	if (A_TickCount - WkGoalReadAt < 3000 && WkGoalReadAt)
		return false
	WkGoalReadAt := A_TickCount
	text := WalkGoalText()
	if (text = "")
		return false
	cnpKind := WalkGoalKind(text)
	;(using, going to or talking to only on the game's memory's verdict - WkNavNoPlace: an arrow hidden 2 s with nothing standing in
	;for it - a zone change, the memory not trusted, an older helper, no helper - isn't "no way to it"; the arrow's own way then)
	if (cnpKind = "" || (cnpKind = "fight" && !CollectGoal(text)) || (cnpKind != "fight" && !WkNavNoPlace))
		return false
	;(the memory keeps the line whatever is drawn over it - a dialogue or window X opened, a screen Remote Desktop doesn't
	;draw: taken only while the line shows there too - its OCR a collect goal, or sharing a word with it; the memory's exact
	;text is the one kept)
	if (WkGoalFrom = "the game")
		{
		cnpOcr := WalkGoalOcr()
		if (cnpOcr = "" || WalkDialogOpen() || !(CollectGoal(cnpOcr) || WalkLineShares(text, cnpOcr)))
			return false
		}
	if (IsObject(WkCollect) && !WkCollect.gaveUp && !CollectGoalChanged(text))
		{
		WkCollect.sureAt := A_TickCount, WkCollect.noPlace := 1, WkCollect.kind := cnpKind
		StartCollect(WkCollect.text, "same goal as before, no arrow")
		return true
		}
	if (IsObject(WkCollect) && WkCollect.gaveUp && !CollectGoalChanged(text))
		return false
	WkCollect := V1Obj({text: text, from: A_TickCount, sureAt: A_TickCount, last: text, gaveUp: 0, battles: 0, noPlace: 1
		, count: CollectCount(text), progressAt: A_TickCount, stepAt: A_TickCount, goalid: CollectGoalId(), newText: "", kind: cnpKind})
	WalkNotifyClose("collect")
	WalkNotifyClose("arrow")
	StartCollect(text, cnpKind = "fight" ? "a goal to collect things with no arrow (the game shows no way to it)"
		: "a goal to " (cnpKind = "use" ? "use things" : cnpKind = "go" ? "go to a place" : "talk to an NPC") " with no arrow (the game shows no way to it)")
	return true
	}

;Collecting (WkArrived = 7) starts - or using, going to or talking to (WkCollect.kind: the game's memory's kind) a goal's thing,
;place or NPC the game shows no way to: Collect.ahk's UseStep, GoStep, TalkStep (1x for each: SpeedWalking)
StartCollect(text, why)
	{
	global WkArrived, WkChaseFrom, WkRoamLeg, WkRoamLegAt, WkFoesAt ; (v1 globals it sets)
	;(walking on into it - collecting roams; 1x for it: SpeedWalking)
	WkArrived := 7, WkChaseFrom := 0, WkRoamLeg := 0, WkRoamLegAt := 0, WkFoesAt := 0
	scKind := IsObject(WkCollect) ? WkCollect.kind : ""
	if (scKind = "use" || scKind = "go" || scKind = "talk")
		{
		WalkLog(scKind ": '" text "' - " why " - " (scKind = "use" ? "the things to use by the game's memory and the zone's file, X at each"
			: scKind = "go" ? "the place by its name, walked to (no X)" : "the NPC by its name, walked to") " - no monsters walked into")
		SetStatus((scKind = "use" ? "using - " : scKind = "go" ? "going - " : "finding - ") SubStr(text, 1, 60))
		return
		}
	WalkLog("collect: '" text "' - " why " - looking for monsters, roaming the area")
	SetStatus("collecting - " SubStr(text, 1, 60))
	}

;One step of collecting. Things the goal names lying about the zone, by the game's memory (AutoFarmer Collect.ahk):
;walked to one by one. Else monster name labels on screen: walk into the biggest (a battle starts on
;contact; AutoFarmer fights it). None: roam about the spot in a widening square (walking over things
;picks them up; their "Press X" prompts are taken above), heading back once RoamRadius away. Ends when
;the goal line under the arrow changes (done, or the next goal), or after CollectMax
CollectStep(seen, h, dist)
	{
	global WkGoalReadAt, WkCollect, WkChaseFrom, WkFoesAt, WkChaseSkipUntil, WkRoamLeg, WkRoamSide, WkRoamLegAt ; (v1 globals it sets)
	;(time away from collecting - a battle, a prompt - doesn't count as no progress)
	if (A_TickCount - WkCollect.stepAt > 5000)
		WkCollect.progressAt += A_TickCount - WkCollect.stepAt, WkCollect.from += A_TickCount - WkCollect.stepAt
	WkCollect.stepAt := A_TickCount
	;Is it still the same goal? (every 4 s, when the arrow and so its line are showing - or with none at all: a goal the
	;game shows no way to, its line where it sits - or using a goal's things, arrow or not: a pickup on contact, the goal moving on)
	if ((seen || WkCollect.noPlace || WkCollect.kind = "use") && A_TickCount - WkGoalReadAt > 4000)
		{
		WkGoalReadAt := A_TickCount
		text := WalkGoalText()
		;(no arrow on screen for a goal that has a place: only the game's own line - an OCR read where no arrow is is no line)
		if (!seen && !WkCollect.noPlace && WkGoalFrom != "the game")
			text := ""
		if (CollectGoalChanged(text))
			{
			WalkLog("collect: the goal is now '" text "' (was '" WkCollect.text "') - following the arrow again")
			WkCollect := ""
			WalkNotifyClose("collect")
			ReleaseKeys()
			WalkReset()
			return true
			}
		if (text != "")
			{
			WkCollect.sureAt := A_TickCount
			if (text != WkCollect.last)
				WkCollect.last := text, WalkLog("collect: " text)
			;(progress: the count going up)
			n := CollectCount(text)
			;(WkCollect["count"]: a data key named like the V1Obj's - a Map's - own Count)
			if (n != "" && n != WkCollect["count"])
				{
				if (WkCollect["count"] != "")
					WalkLog("collect: the count is now " n " (was " WkCollect["count"] ")")
				WkCollect["count"] := n, WkCollect.progressAt := A_TickCount
				}
			}
		}
	if (A_TickCount - WkCollect.from > CollectMax)
		{
		WalkLog("collect: still '" WkCollect.text "' after " Round(CollectMax / 60000) " minutes - giving up, waiting here")
		CollectGiveUp(dist, Round(CollectMax / 60000) " minutes of collecting and it's still not done")
		return true
		}
	;(using, going to or talking to by the game's memory's kind, with AutoFarmer's own steps for it: their own tries and notices)
	csKind := WkCollect.kind
	csOwn := (csKind = "use" || csKind = "go" || csKind = "talk") && V1IsFunc("UseStep")
	;(a goal the game showed no way to has one now - a newer helper's noplace 0 and its place read: the arrow's own way from here;
	;a use goal's things are taken up again at its arrival - CollectCheck)
	if (WkCollect.noPlace && (csKind = "use" || csKind = "go" || csKind = "talk") && !WkNavNoPlace && WkNavOk && IsObject(WkNavObj)
		&& WkNavObj.noplace = 0 && WkNavObj.tx != "")
		{
		WalkLog(csKind ": the game shows a way to '" WkCollect.text "' now - following it")
		WkCollect := ""
		ReleaseKeys()
		WalkReset()
		return true
		}
	;No progress for CollectStall: an odd one (items it can't find, monsters elsewhere...) - stop, wait here
	;(battles still get fought) and tell you. It carries on once the goal changes, or on Keep trying
	;(not while one of the goal's items lies in the game's memory waiting to be tried again - Collect.ahk)
	if ((seen || WkCollect.noPlace) && A_TickCount - WkCollect.progressAt > CollectStall && !csOwn
		&& !(V1IsFunc("CollectItemsWaiting") && %"CollectItemsWaiting"%.Call()))
		{
		WalkLog("collect: no progress on '" WkCollect.text "' in " Round(CollectStall / 60000) " minutes - stopping here, telling you")
		CollectGiveUp(dist, "no progress in " Round(CollectStall / 60000) " minutes of roaming and fighting")
		return true
		}
	;Right after a turn the picture is still swinging round: don't steer on it yet
	if (A_TickCount - WkTurnAt < WalkSettle())
		{
		Sleep(50)
		return true
		}
	;A goal to use things (X at each - Collect.ahk UseStep: the game's memory's things and the zone file's, nearest first), go to
	;a place (GoStep) or talk to an NPC (TalkStep) by name: theirs. Nothing to go for: roaming - no monsters walked into
	csGoal := WkCollect.last != "" ? WkCollect.last : WkCollect.text
	if (csOwn)
		{
		if (%csKind = "use" ? "UseStep" : csKind = "go" ? "GoStep" : "TalkStep"%.Call(csGoal))
			return Walking ? true : false
		;(a use goal with no thing it names to go for, the wizard on its spot by the game's memory: X once at a prompt there not
		;naming the thing - one naming it is UseStep's)
		if (csKind = "use" && WalkUseSpotX(csGoal))
			return true
		}
	;Things lying about the zone that the goal names, by the game's memory (AutoFarmer Collect.ahk): walked to and picked
	;up one by one. None seen: monsters and roaming as before
	else if (V1IsFunc("CollectItemStep") && %"CollectItemStep"%.Call(csGoal))
		return Walking ? true : false
	;(not a fight goal's: the walk / roam below, no monsters walked into)
	if (csKind = "use" || csKind = "go" || csKind = "talk")
		WkChaseFrom := 0
	;Monsters?
	else if (A_TickCount - WkFoesAt > 600)
		{
		WkFoesAt := A_TickCount
		foes := (A_TickCount > WkChaseSkipUntil) ? WalkFoes() : []
		if (foes.Length)
			{
			foe := foes[1]
			if (!WkChaseFrom)
				{
				WkChaseFrom := A_TickCount
				WalkLog("collect: monster label on screen (" foes.Length " in all, " foe.n " px, " Round((foe.x - GameLeft) / GameW * 100) "% across) - walking into it")
				}
			if (A_TickCount - WkChaseFrom > ChaseTime)
				{
				WalkLog("collect: no battle after " Round(ChaseTime / 1000) " s of walking at it - looking elsewhere")
				WkChaseFrom := 0, WkChaseSkipUntil := A_TickCount + 15000
				HoldW(0)
				Turn(120 * WkRoamSide)
				return Walking ? true : false
				}
			;(the camera shows about 40 degrees either side of straight ahead)
			ang := (foe.x - (GameLeft + GameW / 2)) / (GameW / 2) * 40
			HoldW(1)
			if (Abs(ang) > 30)
				Turn(ang)
			else if (Abs(ang) > 6)
				Turn(ang * 0.7)
			SetStatus("collecting - walking into a monster (" Round(ang) " degrees)")
			return Walking ? true : false
			}
		if (WkChaseFrom)
			WalkLog("collect: lost sight of the monster - roaming"), WkChaseFrom := 0
		}
	else if (WkChaseFrom)
		{
		Sleep(50)
		return true
		}
	;Roaming. Too far from the spot: back towards it (the arrow, or the game's memory while it's hidden), then
	;a new square
	if ((seen || WkNavUse) && dist != "" && dist > RoamRadius)
		{
		if (WkRoamLeg)
			WalkLog("collect: " dist " away from the spot - heading back"), WkRoamLeg := 0
		;(a big turn on the spot first, then walking - as on the way to a goal)
		if (Abs(h) > TurnInPlace)
			HoldW(0), Turn(h)
		HoldW(1)
		if (Abs(h) > AheadAngle && Abs(h) <= TurnInPlace)
			Turn(h)
		SetStatus("collecting - back towards the spot (distance " dist ")")
		return Walking ? true : false
		}
	;Walking into something: back off and turn the other way
	if (HeldW && WalkStill() = 1)
		{
		WalkLog("collect: walked into something - backing off, turning")
		BackUp(600)
		Turn(110 * WkRoamSide)
		WkRoamSide := -WkRoamSide, WkRoamLegAt := A_TickCount
		return Walking ? true : false
		}
	;A widening square: legs 2 s, 2 s, 2.5 s, 2.5 s, 3 s... with a quarter turn between
	if (!WkRoamLeg || A_TickCount - WkRoamLegAt > 2000 + (WkRoamLeg // 2) * 500)
		{
		if (WkRoamLeg)
			Turn(90 * WkRoamSide)
		WkRoamLeg += 1, WkRoamLegAt := A_TickCount
		}
	HoldW(1)
	SetStatus("collecting - roaming the area (leg " WkRoamLeg ")")
	Sleep(100)
	return Walking ? true : false
	}

;A use goal (WkCollect.kind "use") with no thing it names to go for (Collect.ahk UseStep said so - looking about) and the wizard on
;its spot by the game's memory - within 300 of the goal, the same floor: X once at a prompt showing there that doesn't name the
;thing - one naming it is UseStep's own (its X, the count watched, its tries and Crowns remembered: one tried twice or with Crowns
;on it is never X'd again) - never a teleporter's, a vendor's (a shop's verb), nor one with Crowns on it. Then as after any X on
;the way (StartPressX: what it opened Spaced through or closed), the goal and its count watched by the collect step as ever; once
;per goal and count. goal: the goal line as UseStep was given it ("" the last read). True if it pressed X. 2026-10-26 16:31-16:34
;"Collect Artifact in Stormriven Hall": circling the spot 1-7 off for 3 minutes, no thing named Artifact in the game's memory or
;the zone's file - the notice
WalkUseSpotX(goal := "")
	{
	static usxDone := "", usxLook := 0
	usxGn := WalkGoalNear()
	if (!IsObject(usxGn) || usxGn.r > 300 || (usxGn.dz != "" && Abs(usxGn.dz) > 150) || WkNavNoPlace || !IsObject(WkCollect))
		return false
	;(WkCollect["count"]: a data key named like the V1Obj's - a Map's - own Count)
	usxKey := (WkNavObj.goalid != "" ? WkNavObj.goalid : WkCollect.text) "|" WkCollect["count"]
	if (usxKey = usxDone || A_TickCount - usxLook < 700)
		return false
	usxLook := A_TickCount
	;(a teleporter by its name, its verb or anywhere on the panel - "Press X to Teleport" under a place's name)
	if (InteractPrompt() != "press" || StrLen(WkPromptDest) < 3 || RegExMatch(WkPromptDest " " WkPromptText, "i)teleport")
		|| RegExMatch(WkPromptVerb, "i)^(shop|trade|buy|sell|browse|craft|learn|train)") || RegExMatch(WkPromptText, "i)cr[o0]wn")
		|| WalkUseNames(WkPromptDest, goal))
		return false
	usxDone := usxKey
	WalkLog("use: on the goal's spot (the game's memory: " Round(usxGn.r) " off) and no thing it names to go for - X once at the prompt there ('" SubStr(WkPromptDest, 1, 30) "')")
	StartPressX(WkPromptDest)
	return true
	}

;The quest goal's line under the arrow (e.g. "Defeat Frost Fins in Kataba IceBlock (2 of 5)"): from the game's memory
;when AutoFarmer's vision helper can read it (NavGoal in Vision.ahk, read-only - the line exactly as the game draws it;
;2026-10-24 the OCR read "Opiio (jn -rhe" for "Defeat Optio Agenor ..." and the quest's own mob was kept away from) -
;not while the game hides it (the memory keeps the text: a battle, the quest helper switched off - no line, as on the
;screen) - else read by OCR just below where the last arrow read found the arrow. WkGoalFrom says which ("the game", "the
;screen"). "" if it can't be read
WalkGoalText()
	{
	global WkGoalQuest ; (v2-only: the port tools don't know it)
	global WkGoalType, WkGoalNpc, WkGoalId, WkGoalItem, WkGoalCount, WkGoalTotal, WkGoalItemKey, WkGoalMobKey, WkGoalNpcFirst ; (v1 globals it sets)
	global WkGoalNpcLast, WkGoalFrom ; (v1 globals it sets)
	if (V1IsFunc("NavGoal"))
		{
		g := %"NavGoal"%.Call()
		;(its kind, the NPC it names and its id kept - a talk goal's NPC: WalkTalkGoal; the thing it names, its count and total and
		;the game's own keys - WalkGoalKind, Collect.ahk's use / go / talk steps; an older helper's has no keys: "". Nothing read:
		;none kept - the kind of a goal before is stale)
		;(the quest's title too - the notices' Wizard101 Central link, WalkNotify)
		if (IsObject(g) && g.text != "")
			WkGoalType := g.type, WkGoalNpc := g.npc, WkGoalId := g.goalid, WkGoalItem := g.item, WkGoalCount := V1At(g, "count")
				, WkGoalTotal := g.total, WkGoalItemKey := g.itemkey, WkGoalMobKey := g.mobkey, WkGoalNpcFirst := g.npcfirst
				, WkGoalNpcLast := g.npclast, WkGoalQuest := g.quest
		else
			WkGoalType := "", WkGoalNpc := "", WkGoalId := "", WkGoalItem := "", WkGoalCount := "", WkGoalTotal := ""
				, WkGoalItemKey := "", WkGoalMobKey := "", WkGoalNpcFirst := "", WkGoalNpcLast := "", WkGoalQuest := ""
		if (IsObject(g) && g.text != "" && g.shown != 0)
			{
			WkGoalFrom := "the game"
			return g.text
			}
		}
	WkGoalFrom := ""
	t := WalkGoalOcr()
	WkGoalFrom := t != "" ? "the screen" : ""
	return t
	}

;The quest goal's line read off the screen by OCR, just below where the last arrow read found the arrow (WalkGoalText's
;fallback; CollectNoPlace: whether the memory's line shows) - WkGoalFrom left as it is. "" if nothing's read
WalkGoalOcr()
	{
	info := ArrowInfo()
	px := info.pvx, py := info.pvy, s := info.scale ? info.scale : 1
	;(no arrow read yet - a goal the game shows no way to has none, 2026-10-23 Piece Of Coral: the line where it sits,
	;under the arrow's usual box at the bottom middle - ArrowFind)
	if (px = "" || py = "")
		{
		asV := ArrowScale()
		s := asV.scale ? asV.scale : 1
		px := GameLeft + GameW / 2 - 0.7 * s, py := GameTop + GameH - 138.3 * s
		}
	t := OcrRect(Round(px - 450 * s), Round(py + 28 * s), Round(900 * s), Round(60 * s))
	return ErrorLevel ? "" : Trim(RegExReplace(t, "\s+", " "))
	}

;True if a word of a (4 letters or more) is among b's letters (WalkLetters: an OCR'd line's slips - 0 for O - put right)
WalkLineShares(a, b)
	{
	wlsB := WalkLetters(b)
	Loop Parse, a, A_Space
		{
		wlsW := WalkLetters(A_LoopField)
		if (StrLen(wlsW) >= 4 && InStr(wlsB, wlsW))
			return true
		}
	return false
	}

;True if a goal line is about collecting or defeating a number of things: a count ("(2 of 5)", "2/5")
;or a word like Collect / Defeat / Gather
CollectGoal(text)
	{
	return RegExMatch(text, "i)\(\s*\d+\s*(of|/)\s*\d+\s*\)|\b\d+\s*/\s*\d+\b|\b(collect|defeat|gather|recover|retrieve|obtain|destroy|hunt|catch|kill|harvest|loot|acquire)\b")
	}

;The count in a goal line ("(2 of 5)", "2/5"): the first number, "" if there's none
CollectCount(text)
	{
	;(a number above the total is a misread)
	return (RegExMatch(text, "i)(\d+)\s*(?:of|/)\s*(\d+)", &cnt) && cnt[1] + 0 <= cnt[2] + 0) ? cnt[1] + 0 : ""
	}

;The quest goal's id off the game's memory (read-only) - "" when it isn't read for sure
CollectGoalId()
	{
	;(a goal the game shows no way to: no usable reading, its id read all the same - WalkNav's WkNpGoal)
	return (WkNavOk && IsObject(WkNavObj)) ? WkNavObj.goalid : (WkNavNoPlace && WkNpGoal != "") ? WkNpGoal : ""
	}

;The goal collecting is for has changed (the quest moved on): by the game's memory's goal id when it's known both then
;and now - a slip in the goal line's OCR is no change (2026-10-23: "D op gentrvand Collect PTta19iece urvey" for "Defeat
;Optio Agenor and Collect Portal Piece in Survey Camp" left the collecting); else by the goal line, a new one read twice
;alike, 4 s apart. text: the goal line now ("" not read)
CollectGoalChanged(text)
	{
	gid := CollectGoalId()
	;(the id missed when collecting began: taken from a read whose line is the same goal)
	if (WkCollect.goalid = "" && gid != "" && text != "" && CollectSameGoal(text, WkCollect.text))
		WkCollect.goalid := gid
	;(compared as text - a 64-bit id as a number can lose its last figures; a line read wrong meanwhile forgotten)
	if (gid != "" && WkCollect.goalid != "")
		{
		WkCollect.newText := ""
		return gid "|" != WkCollect.goalid "|"
		}
	if (text = "" || CollectSameGoal(text, WkCollect.text))
		{
		WkCollect.newText := ""
		return false
		}
	if (WkCollect.newText != "" && CollectSameGoal(text, WkCollect.newText))
		return true
	WkCollect.newText := text
	return false
	}

;True if two goal lines are the same goal: the same letters (bar a few OCR slips), not counting the
;count, which goes up as things are collected
CollectSameGoal(a, b)
	{
	a := WalkLetters(RegExReplace(a, "i)\(?\s*\d+\s*(of|/)\s*\d+\s*\)?")), b := WalkLetters(RegExReplace(b, "i)\(?\s*\d+\s*(of|/)\s*\d+\s*\)?"))
	if (a = "" || b = "")
		return a = b
	return a = b || WalkEditDistance(a, b) <= (StrLen(a) > 10 ? StrLen(a) // 5 : 2)
	}

;Monsters on screen: their name labels (crimson text, e.g. "FROST FIN" over "RANK 15 ELITE"; other
;names are white, green or blue) in the game shrunk to about 240 rows (GDI COLORONCOLOR keeps each
;picked pixel's own colour). Not the bars at the top and bottom (the health globe is red). [{x, y, n},
;...] in screen pixels, the biggest label first (n = crimson samples; nearer monsters have bigger labels)
WalkFoes()
	{
	step := Round(GameH / 240), step := step < 2 ? 2 : step, sw := GameW // step, sh := GameH // step
	foes := []
	bi := Buffer(40, 0)
	NumPut("UInt", 40, bi, 0), NumPut("Int", sw, bi, 4), NumPut("Int", -sh, bi, 8)
	NumPut("UShort", 1, bi, 12), NumPut("UShort", 32, bi, 14)
	sdc := DllCall("GetDC", "Ptr", 0, "Ptr")
	mdc := DllCall("CreateCompatibleDC", "Ptr", sdc, "Ptr")
	bits := 0, cells := V1Obj()
	hbm := DllCall("CreateDIBSection", "Ptr", mdc, "Ptr", bi.Ptr, "UInt", 0, "Ptr*", &bits, "Ptr", 0, "UInt", 0, "Ptr")
	if (hbm && bits)
		{
		obm := DllCall("SelectObject", "Ptr", mdc, "Ptr", hbm, "Ptr")
		DllCall("SetStretchBltMode", "Ptr", mdc, "Int", 3)
		if (DllCall("StretchBlt", "Ptr", mdc, "Int", 0, "Int", 0, "Int", sw, "Int", sh
, "Ptr", sdc, "Int", GameLeft, "Int", GameTop, "Int", GameW, "Int", GameH, "UInt", 0x00CC0020))
			{
			DllCall("GdiFlush")
			;(v2 always runs at full speed - v1 had SetBatchLines -1 around this loop)
			cw := sw // 40, ch := sh // 45, cw := cw < 1 ? 1 : cw, ch := ch < 1 ? 1 : ch
			y1 := Round(sh * 0.08), y2 := Round(sh * 0.80)
			Loop y2 - y1
				{
				y := y1 + A_Index - 1, rowAt := bits + y * sw * 4
				Loop sw
					{
					c := NumGet(rowAt + (A_Index - 1) * 4, "UInt"), r := (c >> 16) & 0xFF
					if (r < 120)
						continue
					g := (c >> 8) & 0xFF, b := c & 0xFF
					if (g > 75 || r - g < 80 || b - g < 25 || r - b < 30)
						continue
					x := A_Index - 1, key := (y // ch) * 1000 + x // cw
					;(a plain object: its five keys are always there - read in this per-pixel loop)
					if (!cells.Has(key))
						cells[key] := {n: 0, sx: 0, sy: 0, x1: x, x2: x}
					cell := cells[key], cell.n += 1, cell.sx += x, cell.sy += y
					if (x < cell.x1)
						cell.x1 := x
					if (x > cell.x2)
						cell.x2 := x
					}
				}
			}
		DllCall("SelectObject", "Ptr", mdc, "Ptr", obm, "Ptr")
		DllCall("DeleteObject", "Ptr", hbm)
		}
	DllCall("DeleteDC", "Ptr", mdc)
	DllCall("ReleaseDC", "Ptr", 0, "Ptr", sdc)
	;Neighbouring cells make one label (a name and the rank line under it)
	done := V1Obj()
	for key, cell in cells
		{
		if (done.Has(key))
			continue
		todo := [key], done[key] := 1, n := 0, sx := 0, sy := 0, x1 := cell.x1, x2 := cell.x2
		while (todo.Length)
			{
			k := todo.Pop(), c := cells[k], n += c.n, sx += c.sx, sy += c.sy
			x1 := c.x1 < x1 ? c.x1 : x1, x2 := c.x2 > x2 ? c.x2 : x2
			for each, dk in [1, -1, 1000, -1000, 999, 1001, -999, -1001]
				if (cells.Has(k + dk) && !done.Has(k + dk))
					done[k + dk] := 1, todo.Push(k + dk)
			}
		;(a label is text: at least 10 samples and 2% of the width - not a red flag in the scenery)
		if (n >= 10 && x2 - x1 + 1 >= sw * 0.02)
			{
			at := 1
			while (at <= foes.Length && foes[at].n >= n)
				at++
			foes.InsertAt(at, V1Obj({x: GameLeft + Round((sx / n + 0.5) * step), y: GameTop + Round((sy / n + 0.5) * step), n: n}))
			}
		}
	return foes
	}

;---- Badly stuck: the Commons, and start over ----

;Teleports to the world's Commons (End) and starts the walk over from there (the quest arrow leads on from
;wherever it lands). At most once every ResetEvery. False if it didn't: too soon, in a battle, or no
;loading screen came within 10 s (a dungeon, say) - or it's badly stuck where it was before (the same zone, the
;goal as far - within MemNear of distance at - and the same quest line, in the last 3 hours): the teleport only
;brings it back there (2026-10-21: Krokotopia's Throne Room, at a wall 35 from the goal, every 10 minutes for half
;an hour), so walking goes off and a notice says so
WalkCommonsReset(why, at := "")
	{
	static spots := []
	global Walking, WkResetAt, WkLoadAt ; (v1 globals it sets)
	if (!ResetTeleport || (WkResetAt && A_TickCount - WkResetAt < ResetEvery) || inbattle || !Walking || !GameActive())
		return false
	zone := WalkZone(true), goal := SubStr(WalkLetters(WalkGoalLine()), 1, 24)
	for i, s in spots
		if (s.zone = zone && zone != "" && at != "" && s.dist != "" && Abs(at - s.dist) <= MemNear && A_TickCount - s.tick < 10800000
			&& (s.goal = "" || goal = "" || s.goal = goal))
			{
			;(counted - once an episode: its give-up point's own call came first, if it has one)
			WalkBadlyStuck("commons", why)
			Walking := 0
			ReleaseKeys()
			WalkLog("badly stuck (" why ") where it was at " s.time " too (" zone ", " at " from the goal) - the Commons only brings it back here: walking off")
			SetStatus("stuck at the same place again - walking is off. Walk it past, then press " WalkKeyText())
			WalkNotify("stuck", "Stuck at the same place again", "The wizard got badly stuck where it was at " s.time " too (" zone ", " at " from the goal). Teleporting to the Commons only brings it back here, so walking is off - the way on may be a door or something the bot can't open. Walk it past, then press " WalkKeyText() ".")
			return false
			}
	spots.Push(V1Obj({zone: zone, dist: at, goal: goal, tick: A_TickCount, time: A_Hour ":" A_Min}))
	WkResetAt := A_TickCount
	ReleaseKeys()
	WalkBadlyStuck("commons", why)
	WalkLog("badly stuck (" why ") - teleporting to the Commons (End) to start over")
	SetStatus("badly stuck - teleporting to the Commons to start over")
	t0 := A_TickCount, started := false
	PressKey("End")
	while (A_TickCount - t0 < 40000)
		{
		Sleep(250)
		if (!Walking)
			return false
		WalkZone(true)
		if (WkLoading)
			started := true
		if (!WkLoading && WkLoadedAt > t0 + 500)
			{
			WalkLog("at the Commons (" WalkZone(true) ") - walking on from here")
			TrayTip("The wizard was badly stuck (" why ") - it went to the Commons and walks on from there.", "Wizard101 bot", 1)
			;(the stuck episode over - the teleport's wait counted too)
			WalkLostTick(true)
			WalkLostClose("at the Commons - walking on from there")
			WalkReset()
			WkLoadAt := A_TickCount
			return true
			}
		if (!started && A_TickCount - t0 > 10000)
			break
		}
	WalkLog("the teleport to the Commons didn't happen (no loading screen) - " why)
	return false
	}

;Badly stuck with nothing taking over at StuckForever (WalkStep): the puzzle code declined and the Commons was used in the last
;ResetEvery (or its End just now brought no loading screen - WalkCommonsReset sets WkResetAt before pressing it) - it goes on trying
;round, the Commons once it may. Was silent (every step, nothing said); now said once an episode (one counted badly stuck stays open
;while StuckForever's watch has it no closer - WalkLostProgress): the log, a tray tip and Discord (AutoFarmer's Alerts.ahk, if set up)
;- not the notice window: what you did then would be recorded as a blocked way's (Puzzle.ahk) while the bot still walks. Discord's kind
;is its own ("walk-trying"): AlertSend lets each kind through once in 10 minutes, and "walk-stuck" - WalkNotify's - must still tell you
;when it gives up and walking goes off, which can only come within those 10 minutes
WalkStuckNoCommons(why)
	{
	static sncSaid := 0
	if (!WkLostOn || sncSaid = WkLostOn)
		return
	sncSaid := WkLostOn
	sncAgo := WkResetAt ? A_TickCount - WkResetAt : ""
	sncText := "The wizard is badly stuck (" why ")" (!ResetTeleport ? " and the teleport to the Commons is off"
		: (V1IsNum(sncAgo) && sncAgo < 60000) ? " and the teleport to the Commons (End) didn't happen - no loading screen - "
		. "it's tried again in " Round(ResetEvery / 60000) " minutes"
		: (V1IsNum(sncAgo) && sncAgo < ResetEvery) ? " and the teleport to the Commons was used " Round(sncAgo / 60000) " minutes ago - "
		. "it goes there again in " Max(1, Ceil((ResetEvery - sncAgo) / 60000)) " minutes" : " and the teleport to the Commons isn't possible here")
		. ". It goes on trying round meanwhile - walk it past if you're there."
	WalkLog("badly stuck, nothing takes over: " sncText)
	TrayTip(sncText, "Wizard101 bot", 2)
	if (V1IsFunc("AlertSend"))
		%"AlertSend"%.Call("walk-trying", "Badly stuck", sncText)
	}

;---- Stuck: counted and timed (TODO goal 2 "Measure it" - the dashboard's STATISTICS, vision\stuckreport.py) ----

;A badly-stuck episode counted: "badly stuck #N (kind): why" in the log - the dashboard counts the line (Dashboard.ahk DashParse: this
;run, and all time in dashboard.ini [stats]), so does vision\stuckreport.py. Every call counts: a dungeon run's stop (Dungeons.ahk) is
;no episode of the walker's; the walker's own give-up points call WalkBadlyStuck - once an episode
WalkBadlyStuckCount(kind, why)
	{
	global WkBadN ; (v2-only: the port tools don't know it)
	WkBadN := V1N(WkBadN) + 1
	WalkLog("badly stuck #" WkBadN " (" kind "): " why)
	}

;A give-up point of the walker's - gave up going round an obstacle, no closer for StuckForever, the Commons (or "the same place
;again"), a teleport that doesn't take, a sigil that won't start, a "stuck" notice: the episode under way - or one begun now (stalledMs:
;the time since it last got closer, lost too; at: the distance to the goal there) - counted badly stuck, once (the first give-up point
;names its kind; the Commons and the notice after it don't count it again)
WalkBadlyStuck(kind, why, stalledMs := 0, at := "")
	{
	global WkLostBad ; (v2-only: the port tools don't know it)
	WalkLostOpen(kind, why, stalledMs, at)
	if (WkLostBad)
		return
	WkLostBad := 1
	WalkBadlyStuckCount(kind, why)
	}

;A stuck episode begins (nothing when one's under way - its kind and why kept): the time already lost (stalledMs: since it last got
;closer - the stall before the first unstick try, StuckForever's minutes, a sigil's wait), where it began (at: the distance to the
;goal, else the closest this goal's walk read - left: the route's way left; arrow units, "" not known), the zone, the quest goal's id.
;Its time from here on: WalkLostTick; its end: WalkLostClose
WalkLostOpen(kind, why, stalledMs := 0, at := "", left := "")
	{
	global WkLostOn, WkLostMs, WkLostAt, WkLostKind, WkLostWhy, WkLostTries, WkLostBad, WkLostDist, WkLostLeft, WkLostZone ; (v2-only: the port tools don't know them)
	global WkLostGoal, WkLostTryMs ; (v2-only: the port tools don't know them)
	if (WkLostOn)
		return
	WkLostOn := A_TickCount, WkLostAt := A_TickCount, WkLostMs := V1IsNum(stalledMs) ? Max(0, Round(stalledMs)) : 0, WkLostTryMs := 0
	WkLostKind := kind, WkLostWhy := why, WkLostTries := 0, WkLostBad := 0
	WkLostDist := V1IsNum(at) ? at : V1IsNum(WkBestDist) ? WkBestDist : ""
	WkLostLeft := V1IsNum(left) ? left : ""
	WkLostZone := WalkZone(), WkLostGoal := (WkNavOk && IsObject(WkNavObj)) ? WkNavObj.goalid : ""
	}

;An unstick try (WalkStep): the obstacle's episode begun (WalkLostOpen - its stall before this first try lost too) or gone on with,
;its tries counted, the time lost so far noted (an episode with no new try for 60 s is over - WalkLostTick)
WalkLostTry(why, stalledMs, at, left)
	{
	global WkLostTries, WkLostTryMs ; (v2-only: the port tools don't know them)
	WalkLostOpen("obstacle", why, stalledMs, at, left)
	WkLostTries += 1, WkLostTryMs := WkLostMs
	}

;Each step (WalkStep, first thing - walking off too): the stuck episode's time lost goes on - the gap since the last step when it's
;LostGap or less (longer - a battle, a loading screen, the bot off - left out), out of battle, and it's walking (not you playing) or a
;"stuck" notice is up (the wait for you is lost too); all: the whole gap, whatever it was (a teleport the bot waited out itself). Ends
;it: another zone (a sigil's: "the sigil started"), another quest goal, at the goal (not while held at a blocked way - AutoFarmer's
;Puzzle.ahk - nor a sigil's), and an obstacle's with no new try for 60 s of walking (lost: up to its last try, and 5 s)
WalkLostTick(all := false)
	{
	global WkLostMs, WkLostAt, WkLostZone, WkLostGoal ; (v2-only: the port tools don't know them)
	if (!WkLostOn)
		return
	ltGap := A_TickCount - WkLostAt
	WkLostAt := A_TickCount
	if (ltGap > 0 && (all || (ltGap <= LostGap && !inbattle && ((Walking && !PlayerActive) || WkNoteKind = "stuck"))))
		WkLostMs += ltGap
	if (all)
		return
	ltZone := WalkZone()
	if (WkLostZone = "")
		WkLostZone := ltZone
	if (WkLostGoal = "" && WkNavOk && IsObject(WkNavObj))
		WkLostGoal := WkNavObj.goalid
	if (ltZone != "" && !WalkSameZone(ltZone, WkLostZone))
		WalkLostClose((WkLostKind = "sigil" && IsObject(WkSigilZones) && WkSigilZones.Has(ltZone) ? "the sigil started - in " : "in another zone - ") ltZone)
	else if (WkNavOk && IsObject(WkNavObj) && WkNavObj.goalid != "" && WkLostGoal != "" && WkNavObj.goalid "|" != WkLostGoal "|")
		WalkLostClose("a new quest goal")
	else if (WkArrived && WkLostKind != "sigil" && Walking && !(V1IsFunc("PuzzleHeld") && %"PuzzleHeld"%.Call()))
		WalkLostClose("at the goal")
	else if (WkLostKind = "obstacle" && !WkLostBad && WkLostTries && WkLostMs - WkLostTryMs > 60000)
		WalkLostClose("no new try in 60 s of walking", WkLostTryMs + 5000)
	}

;Each step with a distance (WalkStep's progress look): the stuck episode under way (not a sigil's) is over once clearly closer than
;where it began - 10 nearer the goal (arrow units: as "got round the obstacle"; StuckForever's: 30, as its own watch) or 30 on along
;the route round walls. An episode begun with no distance takes this one. One counted badly stuck isn't over while StuckForever's
;watch still has it no closer (WkProgAt: 30 nearer or 30 on along the route since): ended by these smaller steps, that watch's next
;step would count the same stall again - another "badly stuck" line, its tray tip and Discord once more
WalkLostProgress(dist, left := "")
	{
	global WkLostDist, WkLostLeft ; (v2-only: the port tools don't know them)
	if (!WkLostOn || WkLostKind = "sigil")
		return
	if (WkLostBad && A_TickCount - WkProgAt > StuckForever)
		return
	if (WkLostDist = "" && V1IsNum(dist))
		WkLostDist := dist
	if (WkLostLeft = "" && V1IsNum(left))
		WkLostLeft := left
	if (V1IsNum(dist) && V1IsNum(WkLostDist) && dist < WkLostDist - (WkLostKind = "nocloser" ? 30 : 10))
		WalkLostClose("got round - " Round(WkLostDist - dist) " closer to the goal than where it got stuck")
	else if (V1IsNum(left) && V1IsNum(WkLostLeft) && left < WkLostLeft - 30)
		WalkLostClose("on along the route round walls")
	}

;The stuck episode over (how): "stuck over - N s lost (kind, T tries, how)" in the log - the dashboard adds it up (this run, all
;time), so does vision\stuckreport.py. ms: the time lost when it's less than all that was counted
WalkLostClose(how, ms := "")
	{
	global WkLostOn, WkLostBad, WkLostEndAt ; (v2-only: the port tools don't know them)
	if (!WkLostOn)
		return
	lcMs := V1IsNum(ms) ? Min(ms, WkLostMs) : WkLostMs
	WalkLog("stuck over - " Round(lcMs / 1000) " s lost (" WkLostKind ", " WkLostTries " tr" (WkLostTries = 1 ? "y" : "ies") ", " how ")")
	WkLostOn := 0, WkLostBad := 0, WkLostEndAt := A_TickCount
	}

;---- A sigil that doesn't start: counted, left and come back to (TODO goal 2 - Settings: sigilhome) ----

;This sigil's spot ({zone, x, y, fails, failAt, resetAt, gaveUp, xs} - see WkSigilSpots): the zone the game's log has, and where the
;wizard stands by the game's memory (a reading in this zone) - one within 400 units; with no position, one in the zone. "" with no zone
;known; make: a new one when there's none
WalkSigilSpot(make := false)
	{
	global WkSigilSpots ; (v2-only: the port tools don't know it)
	if (!IsObject(WkSigilSpots))
		WkSigilSpots := []
	ssZone := WalkZone()
	if (ssZone = "")
		return ""
	ssNav := (WkNavOk && IsObject(WkNavObj)) ? WkNavObj : WkNavLast
	ssHere := IsObject(ssNav) && WalkSameZone(ssNav.zone, ssZone) && V1IsNum(ssNav.x) && V1IsNum(ssNav.y)
	ssX := ssHere ? ssNav.x : "", ssY := ssHere ? ssNav.y : ""
	for i, s in WkSigilSpots
		if (WalkSameZone(s.zone, ssZone) && (s.x = "" || ssX = "" || Sqrt((s.x - ssX) ** 2 + (s.y - ssY) ** 2) <= 400))
			return s
	if (!make)
		return ""
	s := V1Obj({zone: ssZone, x: ssX, y: ssY, fails: 0, failAt: 0, resetAt: 0, gaveUp: 0, xs: []})
	WkSigilSpots.Push(s)
	return s
	}

;The one gate for every X at a sigil (WalkSigilGo's and StartTalk's - StartTalk's went round WalkSigilGo's 10 minutes, a dead sigil
;X'd every ~30 s): "" X may be pressed, else why not - this spot given up on (it didn't start SigilFails times in a row, and leaving it
;didn't help or wasn't done: its notice) for SigilResetEvery - F8 forgives it -, or X here 3 times in the last 10 minutes already (by
;its spot, not the prompt's OCR'd letters: those differ read to read and slipped past WalkSigilTriesLeft)
WalkSigilMayX()
	{
	smSpot := WalkSigilSpot()
	if (!IsObject(smSpot))
		return ""
	if (smSpot.gaveUp && A_TickCount - smSpot.gaveUp < SigilResetEvery)
		return "it didn't start " smSpot.fails " times in a row here - given up on (" WalkKeyText() " tries it again)"
	smRecent := []
	for i, at in smSpot.xs
		if (A_TickCount - at < 600000)
			smRecent.Push(at)
	smSpot.xs := smRecent
	if (smRecent.Length >= 3)
		return "X here 3 times in the last 10 minutes - again in " Ceil((600000 - (A_TickCount - smRecent[1])) / 60000) " min"
	return ""
	}

;In the sigil's dungeon already (the wait at a sigil, WkArrived 5): another zone than the one X was pressed in, and its loading screen
;over 3 s by the game's log - that zone, said with how long X to there took (the X-to-dungeon time, to tune SigilWait by); "" not yet.
;The rest of the wait isn't stood
WalkSigilIn()
	{
	if (WkSigilFromZone = "" || !WkSigilXAt)
		return ""
	siZone := WalkZone()
	if (siZone = "" || WalkSameZone(siZone, WkSigilFromZone) || WkLoading || WkLoadedAt <= WkSigilXAt || A_TickCount - WkLoadedAt < 3000)
		return ""
	WalkLog("sigil: in " siZone " " Round((WkLoadedAt - WkSigilXAt) / 1000) " s after X (its loading screen over) - walking on, not the rest of the " Round(SigilWait / 1000) " s")
	return siZone
	}

;The wait at a sigil over (WkArrived 5, SigilWait stood): did it start? Provably not - the zone known and still the one X was pressed
;in, no loading screen since the X by the game's log (WkSigilAt not cleared by WalkZone, its last load from before the X, none under
;way), no battle; X opening a dialogue is WkArrived 6, not here - counted at its spot, said (with a relog's minutes ago - AutoFarmer's
;Reconnect.ahk), its time lost from the X. The SigilFails-th in a row there (SigilFailsRelog within SigilRelogMs of a relog) when this X
;was the quest's way (WkSigilGoal - StartTalk's at the goal, WalkSigilGo's near or back in): left and come back to, or given up on -
;WalkSigilStuck. A sigil only walked past (pressing X at every prompt) never is: said, and walked on from as before (X at it again 3
;times in 10 minutes at most - WalkSigilTriesLeft, the one gate). True when WalkSigilStuck took over
WalkSigilCheck()
	{
	if (!WkSigilXAt || WkSigilFromZone = "" || !WkSigilAt)
		return false
	scZone := WalkZone(true)
	if (scZone = "" || !WalkSameZone(scZone, WkSigilFromZone) || WkLoading || WkLoadedAt > WkSigilXAt || inbattle)
		return false
	scSpot := WalkSigilSpot(true)
	if (!IsObject(scSpot))
		return false
	scSpot.fails += 1, scSpot.failAt := A_TickCount
	scAgo := V1IsFunc("RcBackAgo") ? %"RcBackAgo"%.Call() : ""
	scRelog := V1IsNum(scAgo) && scAgo < SigilRelogMs
	WalkLog("sigil: didn't start - still in " scZone " " Round((A_TickCount - WkSigilXAt) / 1000) " s after X, no loading screen by the game's log ("
		. scSpot.fails " in a row here" (V1IsNum(scAgo) ? "; a relog " Round(scAgo / 60000) " min ago" : "") ")")
	scWait := A_TickCount - WkSigilXAt
	scMany := scSpot.fails >= (scRelog ? SigilFailsRelog : SigilFails)
	if (scMany && WkSigilGoal)
		{
		;(the episode the give-up counts - its time lost from this X; one under way - an obstacle's, or this sigil's after leaving it and
		;coming back - goes on, the wait counted in it already)
		WalkLostOpen("sigil", "a sigil that doesn't start", scWait)
		WalkSigilStuck(scSpot, "it didn't start " scSpot.fails " times in a row" (scRelog ? ", a relog " Round(scAgo / 60000) " min before" : ""))
		return true
		}
	;(below the count, or a sigil only walked past: its wait lost - an episode of its own, over at once: the walker X's it again or walks
	;on, and that walking isn't time lost. One under way - an obstacle's, or this sigil's badly stuck after leaving it and coming back -
	;goes on: the wait counted in it already, as each step's)
	if (!WkLostOn)
		{
		WalkLostOpen("sigil", "a sigil that doesn't start", scWait)
		WalkLostClose("didn't start - its wait")
		}
	if (scMany)
		WalkLog("sigil: not the quest's way (only walked past - the arrow didn't lead to it): not left or given up on, walking on as before")
	return false
	}

;A sigil just started (WalkZone: the zone changed within SigilWait + 15 s of its X): its spot's X presses that didn't, forgotten - the
;spot X'd last from fromZone
WalkSigilStarted(fromZone)
	{
	if (!IsObject(WkSigilSpots))
		return
	for i, s in WkSigilSpots
		if (WalkSameZone(s.zone, fromZone) && s.xs.Length && s.xs[s.xs.Length] = WkSigilXAt)
			s.fails := 0, s.gaveUp := 0
	}

;Walking on with F8: the sigils given up on - and their counts - start over
WalkSigilForgive()
	{
	if (!IsObject(WkSigilSpots))
		return
	for i, s in WkSigilSpots
		if (s.gaveUp || s.fails)
			s.gaveUp := 0, s.fails := 0, s.xs := []
	}

;A sigil that won't start (WalkSigilCheck - the SigilFails-th X in a row that didn't, the quest's way - never one only walked past):
;badly stuck. Left and come back to (AutoFarmer's sigilhome, off unless switched on - WalkSigilReset) once in SigilResetEvery at its
;spot - its count started over, the normal flow X's it again; left already, the setting off, AutoQuester (none) or the leaving not
;done: given up on - walking off, the notice (F8 tries it again)
WalkSigilStuck(spot, why)
	{
	global Walking ; (v1 globals it sets)
	WalkBadlyStuck("sigil", why)
	ssLeft := spot.resetAt && A_TickCount - spot.resetAt < SigilResetEvery
	ssOn := V1IsFunc("Stat") && %"Stat"%.Call("sigilhome") = 1
	if (!ssLeft && ssOn)
		{
		spot.resetAt := A_TickCount
		if (WalkSigilReset(why))
			{
			spot.fails := 0, spot.xs := []
			return
			}
		}
	spot.gaveUp := A_TickCount
	Walking := 0
	ReleaseKeys()
	ssHow := ssLeft ? "and not after leaving it and coming back " Round((A_TickCount - spot.resetAt) / 60000) " min ago either"
		: !V1IsFunc("Stat") ? "leaving it and coming back is AutoFarmer's" : !ssOn ? "leaving it and coming back is off (Settings: sigilhome)"
		: "leaving it and coming back didn't work"
	ssNow := WalkZone(true)
	WalkLog("sigil: won't start (" why ") - " ssHow ": walking off")
	SetStatus("the sigil won't start - walking is off. Press " WalkKeyText() " to try it again")
	WalkNotify("stuck", "The sigil won't start", "X at the sigil in " spot.zone " didn't start it (" why ")" (ssLeft ? ", not even after going home and coming back" : "")
		. ", so walking is off" (ssNow != "" && !WalkSameZone(ssNow, spot.zone) ? " - the wizard is in " ssNow " now" : "") ". Enter it yourself if you can (a relog, or leaving the zone and coming back, may clear it), then press " WalkKeyText() " to walk again.")
	}

;Leaves a sigil that won't start and comes back to it (2026-10-26 21:44: one never started after a relog - TODO goal 2 "leave it, go
;home and come back"). Written without the game: to be tried in it. AutoFarmer's setting sigilhome (Settings), walking on, out of
;battle, the game in front, not battles only. WkSigilAt cleared first: WalkZone mustn't take the house as the sigil's dungeon
;(WkSigilZones, the quick sell's hold), nor the Recall back as coming out of it (WalkSigilJustLeft - WkZoneFrom cleared after). The Mark
;way when a Mark may be made here (AutoFarmer's SigilMarkOk: never moving your Mark kept at the potion seller) and the mana globe reads
;20 or more (a Mark and a Recall take up to 10 each; a globe that can't be read: not the Mark way - a Mark that didn't take couldn't be
;told, and Home would then lose the way back: inside a dungeon, its instance and the run's progress): Page Down - the mana gone down
;(PotionArrivedMana; a Mark that didn't take isn't gone back to) -, Home (a loading screen; not a house: said, on all the same), then the
;Recall (Page Up, once more after 3 s) into the zone it was in: X again when its prompt shows. Not back (still in the house - End goes
;nowhere there -, or elsewhere): false. Otherwise (commons) the Commons (End) and the walk back, as when badly stuck (WalkCommonsReset -
;not within ResetEvery of the last). fromZone: the sigil's zone ("" the walker's last sigil's - WkSigilFromZone; a dungeon run gives its
;own, and commons false: it can't walk back - nor is the walker's stuck episode its: WalkStep doesn't run during a run). True when back
;at the sigil, or at the Commons walking back
WalkSigilReset(why, fromZone := "", commons := true)
	{
	global WkSigilAt, WkZoneFrom, WkLoadAt ; (v1 globals it sets)
	if (fromZone = "")
		fromZone := WkSigilFromZone
	srNo := !V1IsFunc("Stat") ? "AutoQuester has no Mark, Home or Recall of its own" : %"Stat"%.Call("sigilhome") != 1 ? "it's off (Settings: sigilhome)"
		: !Walking ? "walking is off" : inbattle ? "a battle is on" : !GameActive() ? "the game isn't in front"
		: (V1IsFunc("BattlesOnly") && %"BattlesOnly"%.Call()) ? "battles only (Settings)" : fromZone = "" ? "its zone isn't known" : ""
	if (srNo != "")
		{
		WalkLog("sigil: not leaving it and coming back - " srNo " (" why ")")
		return false
		}
	WkSigilAt := 0
	ReleaseKeys()
	srMana := V1IsFunc("PotionGlobes") ? %"PotionGlobes"%.Call().mana : ""
	srWhyNot := !(V1IsFunc("SigilMarkOk") && %"SigilMarkOk"%.Call()) ? "no Mark made here - your Mark is kept (the potion seller's: Settings potionmark, buying recorded at it)"
		: !V1IsNum(srMana) ? "the mana globe can't be read - a Mark that didn't take couldn't be told, and Home would lose the way back"
		: srMana < 20 ? "mana " srMana " - a Mark and a Recall take up to 10 each" : ""
	if (srWhyNot = "")
		{
		WalkLog("sigil: leaving it (" why ") - a Mark here (Page Down), Home, then the Recall (Page Up) back to it")
		SetStatus("a sigil that won't start - Home and back")
		PressKey("PgDn")
		Sleep(1500)
		;(the globe's number given a moment more to go down - read twice the same and lower; not read so: not taken, no Home)
		srTook := false
		Loop 4
			{
			if (srTook := (V1IsFunc("PotionArrivedMana") && %"PotionArrivedMana"%.Call(srMana)))
				break
			Sleep(500)
			}
		if (!Walking)
			return false
		if (!srTook)
			srWhyNot := "the Mark (Page Down) didn't take - mana " srMana
		else
			{
			;(a potion run's own Mark, kept for its Recall - PotionMarkKept - is gone: this one's in its place)
			%"SigilMarkOk"%.Call(true)
			if (!WalkSigilTeleport("Home", "home"))
				srWhyNot := "Home didn't load"
			else
				{
				srHome := WalkZone(true)
				if (!InStr(srHome, "Housing"))
					WalkLog("sigil: Home went to " srHome " - not a house: the Recall back all the same")
				Sleep(2000)
				srBack := WalkSigilTeleport("PgUp", "the Mark at the sigil")
				if (!srBack && Walking)
					{
					Sleep(3000)
					srBack := WalkSigilTeleport("PgUp", "the Mark at the sigil (a second Recall)")
					}
				srAt := WalkZone(true)
				if (srBack && WalkSameZone(srAt, fromZone))
					{
					WkZoneFrom := ""
					;(the walker's stuck episode: the teleports' wait lost too - the walker's own call only, which ticked just before; a dungeon
					;run's isn't - WalkStep doesn't run then, and an episode left open from before the run would get the whole run added)
					if (commons)
						WalkLostTick(true)
					WalkReset()
					WkLoadAt := A_TickCount
					WalkSigilPromptsFree()
					WalkLog("sigil: back at the sigil (" fromZone ") after Home and the Recall - X again when its prompt shows")
					TrayTip("A sigil didn't start (" why ") - the wizard went home and came back to it, to try it again.", "Wizard101 bot", 1)
					return true
					}
				WalkLog("sigil: the Recall " (srBack ? "went to " srAt ", not " fromZone : "didn't load - still in " srAt) " - not back at the sigil")
				return false
				}
			}
		}
	if (!commons)
		{
		WalkLog("sigil: not leaving it - " srWhyNot)
		return false
		}
	if (!ResetTeleport || (WkResetAt && A_TickCount - WkResetAt < ResetEvery))
		{
		WalkLog("sigil: not leaving it - " srWhyNot ", and the Commons " (ResetTeleport ? "was used " Round((A_TickCount - WkResetAt) / 60000) " min ago (once in " Round(ResetEvery / 60000) " min)" : "teleport is off"))
		return false
		}
	WalkLog("sigil: leaving it (" why ") by the Commons (End) - " srWhyNot " - then walking back to it")
	if (!WalkCommonsReset("a sigil that won't start - " why))
		return false
	WkZoneFrom := ""
	return true
	}

;Presses a teleport key (Home, Page Up) and waits for its loading screen to come and go by the game's log - as WalkCommonsReset's End.
;True once there (and 2.5 s more for the new zone's first look round, as PotionTeleport); false: walking went off, no loading screen
;began within 10 s (no Mark, too little mana, a battle) or it didn't end in 40 s
WalkSigilTeleport(key, what)
	{
	stT0 := A_TickCount, stStarted := false
	PressKey(key)
	while (A_TickCount - stT0 < 40000)
		{
		Sleep(250)
		if (!Walking)
			return false
		WalkZone(true)
		if (WkLoading)
			stStarted := true
		if (!WkLoading && WkLoadedAt > stT0 + 500)
			{
			Sleep(2500)
			WalkLog("sigil: at " what " (" WalkZone(true) ")")
			return true
			}
		if (!stStarted && A_TickCount - stT0 > 10000)
			break
		}
	WalkLog("sigil: no loading screen after " key " for " what " (still in " WalkZone(true) ")")
	return false
	}

;The sigil's X presses forgotten (after leaving it and coming back): its prompt's - nearly the same letters too, as WalkPromptFree
;matches them - and its tries, so the normal flow X's it again when the prompt shows
WalkSigilPromptsFree()
	{
	spKey := WkSigilKey = "" ? "?" : WkSigilKey
	spOld := []
	for used, at in WkPromptUsed
		if (used = spKey || used = "sigilno" || (StrLen(spKey) > 6 && WalkEditDistance(used, spKey) <= StrLen(spKey) // 4))
			spOld.Push(used)
	for i, used in spOld
		WkPromptUsed.Delete(used)
	if (IsObject(WkSigilTries))
		WkSigilTries.Delete(spKey)
	}

;---- Telling you when it needs you ----

;Sure there's no battle on: AutoFarmer saw the spellbook (it only shows out of battle) a moment ago
;(BotNoBattle). AutoQuester can't tell
;(since: the spellbook seen after then too - after the arrow went, say: the battle's own start hides both)
WalkSureNoBattle(since := 0)
	{
	return V1IsFunc("BotNoBattle") ? %"BotNoBattle"%.Call(since) : false
	}

;Wizard101's own menu (Escape opens it when nothing else is open) up: two of its page's labels read (GRAPHICS,
;RESOLUTION, FULLSCREEN, TEXTURE DETAIL, HARDWARE CURSOR, UI SIZE - often read clipped: ESOLUTION, ULLSCREEN...), or
;its buttons QUIT / IDLE / HELP / OK (WalkMenuButtons) - read enlarged, as yellow on red they aren't read at 1:1. Never
;with a disconnect box, a question or Crowns read. okBtn: the screen spot of its OK, if read (wantOk: the buttons
;read for it even with the labels read). seen: what was read (for debug.log)
WalkGameMenuOpen(&okBtn := "", wantOk := false, &seen := "")
	{
	okBtn := "", seen := ""
	;(the middle 70% of the game - the chat's corner mostly left out - enlarged up to twice, to 2500 px across at
	;most, Windows OCR's limit: small labels read better)
	readW := Min(Round(GameW * 0.7), 2500)
	menuLines := "", bandLines := ""  ; (v1: a ByRef output OcrRect may leave unset was blank)
	t := OcrRect(Round(GameLeft + (GameW - readW) / 2), Round(GameTop + GameH * 0.1), readW, Round(GameH * 0.8), "en", Min(2, 2500 / readW), &menuLines)
	if (ErrorLevel || !IsObject(menuLines))
		return false
	seen := RegExReplace(t, "\s+", " ")
	if (RegExMatch(t, "i)reconnect|disconnect|are you sure|cr[o0]wn"))
		return false
	;(labels: from short lines only - a word or two, not sentences - one label a line)
	labels := V1Obj()
	for i, line in menuLines
		{
		if (!IsObject(line.words) || line.words.Length > 3)
			continue
		flat := RegExReplace(Format("{:L}", line.text), "[^a-z]")
		;(a V1Obj: enumerated in key order, as v1's object - a v2 Object literal can't be enumerated)
		for k, re in V1Obj({graphics: "graphic", resolution: "solutio|olution", fullscreen: "lscreen|fullscr", texture: "texture|t[ui]redet"
			, cursor: "cursor|recurs|hardwar", uisize: "uisiz"})
			if (RegExMatch(flat, re))
				{
				labels[k] := 1
				break
				}
		}
	;(its buttons are sometimes read at 1:1 too)
	menuUp := WalkMenuButtons(menuLines, &okRead)
	menuUp := menuUp || labels.Count >= 2
	if (menuUp && (!wantOk || IsObject(okRead)))
		{
		okBtn := okRead
		return true
		}
	;(the buttons: the lower middle of the game, enlarged to 2500 px across at most)
	bandW := Min(Round(GameW * 0.6), 1560)
	b := OcrRect(Round(GameLeft + (GameW - bandW) / 2), Round(GameTop + GameH * 0.5), bandW, Round(GameH * 0.45), "en", Min(2, 2500 / bandW), &bandLines)
	if (!ErrorLevel && IsObject(bandLines) && !RegExMatch(b, "i)reconnect|disconnect|are you sure|cr[o0]wn"))
		{
		seen .= " | " RegExReplace(b, "\s+", " ")
		if (WalkMenuButtons(bandLines, &bandOk))
			menuUp := true, okRead := IsObject(bandOk) ? bandOk : okRead
		}
	okBtn := menuUp ? okRead : ""
	return menuUp
	}

;The game menu's button row in an OCR read (lines as OcrRect gives them): three or four of QUIT, IDLE, HELP, OK
;(0K, 1DLE... too) side by side at one height - no other word between them - in that order left to right, far apart
;like buttons (a gap of more than a word's height between them): not words of a sentence. okAt: the OK's middle,
;if it's one of them
WalkMenuButtons(lines, &okAt := "")
	{
	okAt := "", allWords := []
	for i, line in lines
		{
		if (!IsObject(line.words))
			continue
		for j, bw in line.words
			{
			word := RegExReplace(Format("{:L}", bw.text), "[^a-z0-9]")
			n := RegExMatch(word, "^[qo0]uit$") ? 1 : RegExMatch(word, "^[il1]dle$") ? 2 : word = "help" ? 3 : RegExMatch(word, "^[o0]k$") ? 4 : 0
			allWords.Push(V1Obj({n: n, x: bw.x, y: bw.y + bw.h / 2, w: bw.w, h: bw.h}))
			}
		}
	for i, first in allWords
		{
		if (!first.n)
			continue
		;(every word at this one's height, left to right)
		row := []
		for j, bw in allWords
			if (Abs(bw.y - first.y) <= Max(first.h, 10) * 0.6)
				{
				at := row.Length + 1
				for k, r in row
					if (bw.x < r.x)
						{
						at := k
						break
						}
				row.InsertAt(at, bw)
				}
		firstAt := 0, lastAt := 0
		for k, r in row
			if (r.n)
				lastAt := k, firstAt := firstAt ? firstAt : k
		runLen := lastAt - firstAt + 1
		if (runLen < 3 || runLen > 4)
			continue
		okRow := true, okSpot := ""
		Loop runLen
			{
			r := row[firstAt + A_Index - 1]
			if (!r.n)
				{
				okRow := false
				break
				}
			if (A_Index > 1)
				{
				prev := row[firstAt + A_Index - 2]
				if (r.n <= prev.n || r.x - (prev.x + prev.w) < Max(r.h, 8))
					{
					okRow := false
					break
					}
				}
			if (r.n = 4)
				okSpot := V1Obj({x: Round(r.x + r.w / 2), y: Round(r.y)})
			}
		if (okRow)
			{
			okAt := okSpot
			return true
			}
		}
	return false
	}

;May the bot press a key or click for the game's menu: Wizard101 in front, walking on (needWalking - not for the
;potion run, which works with walking off) and, in AutoFarmer, its WalkHostOn: the bot on (F6) and no key or mouse
;of yours since from (A_TickCount)
WalkMenuMayAct(needWalking, from := 0)
	{
	if (!GameActive() || (needWalking && !Walking))
		return false
	return V1IsFunc("WalkHostOn") ? %"WalkHostOn"%.Call(from) : true
	}

;Closes Wizard101's menu if it's up (WalkGameMenuOpen): Escape - twice at most - and if it's still there, its OK
;(never Quit), each only while the bot may act (WalkMenuMayAct, checked right before it, from since - or the start
;of this). -1: not looked at (the bot mayn't act), 0: no menu, 1: closed, 2: still up (left to you). seen: what the
;first look read (for debug.log)
WalkCloseGameMenu(needWalking := true, &seen := "", since := 0)
	{
	seen := "", from := since ? since : A_TickCount
	if (!WalkMenuMayAct(needWalking, from))
		return -1
	if (!WalkGameMenuOpen(&_okbtn := "", false, &seen))
		return 0
	Loop 2
		{
		WalkLog("the game's menu is open (an Escape opened it?) - Escape to close it")
		Critical()
		if (!WalkMenuMayAct(needWalking, from))
			{
			Critical("Off")
			WalkLog("the game's menu left to you (the bot is off, Wizard101 isn't in front or you've taken over)")
			return 2
			}
		Send("{Blind}{Escape}")
		Critical("Off")
		Sleep(800)
		;(the second time, its OK looked for too - for a click if Escape won't do)
		if (!WalkGameMenuOpen(&menuOk, A_Index = 2))
			return 1
		}
	if (!IsObject(menuOk))
		{
		WalkLog("the game's menu is still open and its OK wasn't read - left to you")
		return 2
		}
	WalkLog("the game's menu is still open - its OK")
	;(the mouse back where it was afterwards, in AutoFarmer: mousereturn)
	ownGrab := V1IsFunc("MouseGrab") ? %"MouseGrab"%.Call() : false
	Critical()
	clicked := WalkMenuMayAct(needWalking, from)
	if (clicked)
		{
		;(your mouse locked meanwhile, in AutoFarmer - Settings.ahk MouseLockOn)
		if (V1IsFunc("MouseLockOn"))
			%"MouseLockOn"%.Call("walker")
		Click(menuOk.x " " menuOk.y)
		;(its clicks too, now the pointer's on the game - Settings.ahk MouseLockMoved)
		if (V1IsFunc("MouseLockMoved"))
			%"MouseLockMoved"%.Call()
		}
	Critical("Off")
	Sleep(100)
	if (ownGrab)
		%"MouseLetGo"%.Call()
	if (clicked && V1IsFunc("MouseLockOff"))
		%"MouseLockOff"%.Call("walker")
	if (!clicked)
		{
		WalkLog("the game's menu left to you (the bot is off, Wizard101 isn't in front or you've taken over)")
		return 2
		}
	Sleep(700)
	return WalkGameMenuOpen() ? 2 : 1
	}

;Escape, once: for a window an X of the bot's opened that Space doesn't close (a shop, say). If that opened
;the game's own menu instead (nothing else was open), it's closed again (WalkCloseGameMenu)
WalkEscape()
	{
	if (KeysDown || HeldW)
		ReleaseKeys()
	WalkLog("no arrow for " Round((A_TickCount - WkNoArrowFrom) / 1000) " s since an X of the bot's - Escape, in case that opened a window Space doesn't close (a shop?)")
	PressKey("Escape")
	Sleep(1200)
	WalkCloseGameMenu()
	}

;A notice for you: a small window on top (it doesn't take the focus from the game) with a sound, plus a
;tray tip and a line in the log. One at a time; the same kind isn't shown twice till it's sorted
;(WalkNotifyClose). withKeep: Keep trying / Stop walking buttons too (a collect goal)
WalkNotify(kind, title, text, withKeep := false)
	{
	global WkNoteKind, WkNoteTitle, WkNoteShown, WkNoteOff, WkNote, WkNoteHwnd ; (v1 globals it sets)
	;(a "stuck" notice is a give-up point: counted - once an episode; its own give-up's call came first, if it has one)
	if (kind = "stuck")
		WalkBadlyStuck("notice", title)
	if (WkNoteKind = kind)
		return
	;(one at a time: one up for something as or more important stays - two causes can't take turns)
	if (WkNoteKind != "" && WalkNoteRank(WkNoteKind) >= WalkNoteRank(kind))
		return
	global WkGoalQuest ; (v2-only: the port tools don't know it)
	WalkNotifyClose()
	WkNoteKind := kind, WkNoteTitle := title, WkNoteShown := 0, WkNoteOff := 0
	WalkLog("NEEDS YOU - " title ": " text)
	;(the quest's page on Wizard101 Central, for a notice about the quest - in the notice, the log and Discord: yours to open, the bot
	;never fetches it. The quest's title by the game's memory - asked once more if it isn't known yet)
	wkLink := "", wkFind := "", wkTitle := ""
	if (kind = "stuck" || kind = "collect" || kind = "wait" || kind = "puzzle" || kind = "arrow")
		{
		if (WkGoalQuest = "" && V1IsFunc("NavGoal"))
			{
			wkG := %"NavGoal"%.Call(400)
			if (IsObject(wkG) && wkG.quest != "")
				WkGoalQuest := wkG.quest
			}
		wkLink := WalkWikiUrl(WkGoalQuest), wkFind := WalkWikiUrl(WkGoalQuest, true)
		;(the title shown: no markup, & as "and" - the link control's text)
		wkTitle := Trim(RegExReplace(RegExReplace(StrReplace(WkGoalQuest, "&", "and"), "<[^>]*>|[<>]", " "), "\s+", " "))
		if (wkLink != "")
			WalkLog("the quest on Wizard101 Central: " wkLink)
		}
	;(what you do now is recorded - AutoFarmer's Puzzle.ahk: learned for next time)
	if (V1IsFunc("PuzzleNoticed"))
		%"PuzzleNoticed"%.Call(kind, title)
	;(and to Discord, if alerts are set up: AutoFarmer's Alerts.ahk)
	if (V1IsFunc("AlertSend"))
		%"AlertSend"%.Call("walk-" kind, title, text, wkLink)
	;(+E0x08000000: clicking it never takes the focus from the game)
	WkNote := Gui("+AlwaysOnTop +ToolWindow +E0x08000000", "Wizard101 bot needs you"), WkNoteHwnd := WkNote.Hwnd
	;(v1 called WkNoteGuiClose by the GUI's name: the title-bar X)
	WkNote.OnEvent("Close", WkNoteGuiClose)
	WkNote.MarginX := 14, WkNote.MarginY := 12
	WkNote.SetFont("s11 w700", "Segoe UI")
	WkNote.Add("Text", "w400", title)
	WkNote.SetFont("s9 w400", "Segoe UI")
	WkNote.Add("Text", "w400 y+6", text)
	;(a click on it is yours: the page opens in your browser)
	if (wkLink != "")
		WkNote.Add("Link", "w400 y+6", 'The quest on Wizard101 Central: <a href="' wkLink '">' wkTitle '</a>  (<a href="' wkFind '">search</a>)')
	if (withKeep)
		{
		ogcButtonKeeptrying := WkNote.Add("Button", "w120 y+12", "Keep trying")
		ogcButtonKeeptrying.OnEvent("Click", WalkNoteKeep.Bind("Normal"))
		ogcButtonStopwalking := WkNote.Add("Button", "w120 x+8", "Stop walking")
		ogcButtonStopwalking.OnEvent("Click", WalkNoteStop.Bind("Normal"))
		ogcButtonOK := WkNote.Add("Button", "w80 x+8", "OK")
		ogcButtonOK.OnEvent("Click", WalkNoteOk.Bind("Normal"))
		}
	else
	{
		ogcButtonOK := WkNote.Add("Button", "w80 y+12", "OK")
		ogcButtonOK.OnEvent("Click", WalkNoteOk.Bind("Normal"))
	}
	if (!inbattle)
		WalkNoteShow()
	V1Do(SoundPlay, "*48")  ; (v1: a sound that couldn't play - ErrorLevel, no error)
	TrayTip(title ": " SubStr(text, 1, 200), "Wizard101 bot needs you", 2)
	}

;How important a notice is: stuck > collect, a blocked way (AutoFarmer's Puzzle.ahk) > no arrow > waiting at a goal
WalkNoteRank(kind)
	{
	return (kind = "stuck" || kind = "shop") ? 4 : (kind = "collect" || kind = "puzzle") ? 3 : kind = "arrow" ? 2 : 1
	}

;The quest's page on Wizard101 Central (search: its search, which lands on the page when one has exactly that name - and finds the
;titles that need a world in brackets): "" no title. Only a URL - the bot never fetches it. The title's markup and the characters a
;page title can't hold left out ([ ] { } | < >, from a # on), spaces as _ (the search's %20), its UTF-8 bytes %XX but for letters,
;digits and - _ . ~ ! * ' ( ) , : ; @ $ / (an apostrophe stays readable: Storm_Lord's_Temple)
WalkWikiUrl(title, search := false)
	{
	t := RegExReplace(title, "<[^>]*>")
	if (wuHash := InStr(t, "#"))
		t := SubStr(t, 1, wuHash - 1)
	t := Trim(RegExReplace(RegExReplace(t, "[\[\]{}|<>]"), "\s+", " "))
	if (t = "")
		return ""
	wuBuf := Buffer(StrPut(t, "UTF-8"), 0)
	wuLen := StrPut(t, wuBuf.Ptr, "UTF-8") - 1
	wuOut := ""
	Loop wuLen
		{
		wuB := NumGet(wuBuf, A_Index - 1, "UChar")
		if (wuB = 32)
			wuOut .= search ? "%20" : "_"
		else if ((wuB >= 48 && wuB <= 57) || (wuB >= 65 && wuB <= 90) || (wuB >= 97 && wuB <= 122) || InStr("-_.~!*'(),:;@$/", Chr(wuB), true))
			wuOut .= Chr(wuB)
		else
			wuOut .= "%" Format("{:02X}", wuB)
		}
	return search ? "https://wiki.wizard101central.com/wiki/index.php?title=Special:Search&search=Quest%3A" wuOut "&go=Go"
		: "https://wiki.wizard101central.com/wiki/Quest:" wuOut
	}

;The notice's title-bar X: the same as OK
WkNoteGuiClose(args*)
	{
	local v1KeepGui := V1Thread()  ; (v1: a GUI event ran as its own thread - the ErrorLevel its WalkLog leaves stayed in it)
	WalkNoteOk()
	}

;Shows the notice (see WalkNotePlace), without taking the focus from the game
WalkNoteShow()
	{
	global WkNoteShown ; (v1 globals it sets)
	if (WkNoteKind = "" || WkNoteOff)
		return
	WkNote.Show("Hide AutoSize")
	dhw := A_DetectHiddenWindows
	DetectHiddenWindows(true)
	WinGetPos(, , &noteW, &noteH, "ahk_id " WkNoteHwnd)
	DetectHiddenWindows(dhw)
	at := WalkNotePlace(noteW, noteH)
	noteX := at[1], noteY := at[2]
	WkNote.Show("x" . noteX . " y" . noteY . " NoActivate")
	WkNoteShown := 1
	}

;Where the notice goes: on a monitor the game isn't on; else beside the game window if there's room; else
;the top middle of the game (clear of the arrow, prompts, dialogues and globes - and it hides in a battle,
;whose name plates are up there)
WalkNotePlace(noteW, noteH)
	{
	gx := GameLeft + GameW // 2, gy := GameTop + GameH // 2
	monCount := MonitorGetCount()
	Loop monCount
		{
		MonitorGetWorkArea(A_Index, &waLeft, &waTop, &waRight, &waBottom)
		if (gx >= waLeft && gx < waRight && gy >= waTop && gy < waBottom)
			continue
		return [waRight - noteW - 20, waTop + 20]
		}
	Loop monCount
		{
		MonitorGetWorkArea(A_Index, &waLeft, &waTop, &waRight, &waBottom)
		if (gx >= waLeft && gx < waRight && gy >= waTop && gy < waBottom)
			break
		}
	if (waRight - (GameLeft + GameW) >= noteW + 16)
		return [GameLeft + GameW + 8, Max(waTop, GameTop)]
	if (GameLeft - waLeft >= noteW + 16)
		return [GameLeft - noteW - 8, Max(waTop, GameTop)]
	return [gx - noteW // 2, Max(waTop, GameTop) + 4]
	}

WalkNoteHide()
	{
	global WkNoteShown ; (v1 globals it sets)
	if (WkNoteShown)
		WkNote.Hide()
	WkNoteShown := 0
	}

;The notice is sorted (kind: only that kind; "": whatever is up) - gone
WalkNotifyClose(kind := "")
	{
	global WkNoteKind, WkNoteTitle, WkNoteShown, WkNoteOff ; (v1 globals it sets)
	if (WkNoteKind = "" || (kind != "" && WkNoteKind != kind))
		return
	WalkLog("notice '" WkNoteTitle "' closed")
	Try WkNote.Destroy()
	WkNoteKind := "", WkNoteTitle := "", WkNoteShown := 0, WkNoteOff := 0
	}

;The notice's buttons. OK: put away (not shown again till it's sorted). Keep trying: collect again for
;CollectStall. Stop walking: walking off. Each gives the game the focus back
WalkNoteOk(args*)
	{
	local v1KeepGui := V1Thread()  ; (v1: a GUI event ran as its own thread - the ErrorLevel its WalkLog leaves stayed in it)
	global WkNoteShown, WkNoteOff ; (v1 globals it sets)
	WkNote.Hide()
	WkNoteShown := 0, WkNoteOff := 1
	WalkGameFocus()
	}

WalkNoteKeep(args*)
	{
	local v1KeepGui := V1Thread()  ; (v1: a GUI event ran as its own thread - the ErrorLevel its WalkLog leaves stayed in it)
	local v1Keep := V1Thread() ; (v1: each thread had its own ErrorLevel)
	;(a blocked way's notice - AutoFarmer's Puzzle.ahk: its tries once more)
	if (WkNoteKind = "puzzle" && V1IsFunc("PuzzleKeep"))
		{
		WalkNotifyClose()
		%"PuzzleKeep"%.Call()
		WalkGameFocus()
		return
		}
	if (IsObject(WkCollect))
		{
		WkCollect.gaveUp := 0, WkCollect.from := A_TickCount, WkCollect.progressAt := A_TickCount, WkCollect.stepAt := A_TickCount
		;(a goal to use things: the ones left for a while tried again - Collect.ahk)
		if (V1IsFunc("UseForget"))
			%"UseForget"%.Call()
		WalkNotifyClose()
		StartCollect(WkCollect.text, "you said keep trying")
		}
	else
		WalkNotifyClose()
	WalkGameFocus()
	}

WalkNoteStop(args*)
	{
	local v1KeepGui := V1Thread()  ; (v1: a GUI event ran as its own thread - the ErrorLevel its WalkLog leaves stayed in it)
	local v1Keep := V1Thread() ; (v1: each thread had its own ErrorLevel)
	WalkNotifyClose()
	if (Walking)
		WalkToggle()
	WalkGameFocus()
	}

WalkGameFocus()
	{
	V1Try(WinActivate, "ahk_class " GameClass " ahk_exe " GameExe)  ; (v1: no game window - nothing, no error)
	}

;---- Is the wizard moving? A tiny grey copy of the game compared with the one before ----

;The game shrunk to 64x40 (GDI averages it), as grey levels, leaving out the wizard's column (the
;wizard and the arrow move with you) and the bars of buttons at the top and bottom
WalkSnap()
	{
	snapW := 64, snapH := 40, snap := ""
	bi := Buffer(40, 0)
	NumPut("UInt", 40, bi, 0), NumPut("Int", snapW, bi, 4), NumPut("Int", -snapH, bi, 8)
	NumPut("UShort", 1, bi, 12), NumPut("UShort", 32, bi, 14)
	sdc := DllCall("GetDC", "Ptr", 0, "Ptr")
	mdc := DllCall("CreateCompatibleDC", "Ptr", sdc, "Ptr")
	bits := 0
	hbm := DllCall("CreateDIBSection", "Ptr", mdc, "Ptr", bi.Ptr, "UInt", 0, "Ptr*", &bits, "Ptr", 0, "UInt", 0, "Ptr")
	if (hbm && bits)
		{
		obm := DllCall("SelectObject", "Ptr", mdc, "Ptr", hbm, "Ptr")
		DllCall("SetStretchBltMode", "Ptr", mdc, "Int", 4)
		DllCall("SetBrushOrgEx", "Ptr", mdc, "Int", 0, "Int", 0, "Ptr", 0)
		if (DllCall("StretchBlt", "Ptr", mdc, "Int", 0, "Int", 0, "Int", snapW, "Int", snapH
, "Ptr", sdc, "Int", GameLeft, "Int", GameTop, "Int", GameW, "Int", GameH, "UInt", 0x00CC0020))
			{
			DllCall("GdiFlush")
			snap := []
			Loop snapH
				{
				row := A_Index - 1
				if (row < snapH * 0.10 || row >= snapH * 0.75)
					continue
				Loop snapW
					{
					col := A_Index - 1
					if (col >= snapW * 0.35 && col < snapW * 0.65)
						continue
					bgr := NumGet(bits + 0, (row * snapW + col) * 4, "UInt")
					snap.Push(((bgr >> 16 & 0xFF) * 299 + (bgr >> 8 & 0xFF) * 587 + (bgr & 0xFF) * 114) // 1000)
					}
				}
			}
		DllCall("SelectObject", "Ptr", mdc, "Ptr", obm, "Ptr")
		DllCall("DeleteObject", "Ptr", hbm)
		}
	DllCall("DeleteDC", "Ptr", mdc)
	DllCall("ReleaseDC", "Ptr", 0, "Ptr", sdc)
	return snap
	}

;1 if the picture has hardly changed since the last look (W held, no turn or backing up since - nor
;the camera still swinging round after one), 0 if
;it has, "" if there's nothing fair to compare with yet. Standing still or walking into a wall: 0-1%
;of it changes between looks; walking: 45-85% (measured on recorded frames, 2026-10-16)
WalkStill()
	{
	global WkMotion, WkSnapPrev, WkSnapAt ; (v1 globals it sets)
	nowMs := A_TickCount
	if (IsObject(WkSnapPrev) && nowMs - WkSnapAt < 300)
		return ""
	;(v2 always runs at full speed - v1 had SetBatchLines -1 around this look)
	snap := WalkSnap()
	result := ""
	if (IsObject(snap) && IsObject(WkSnapPrev) && snap.Length && snap.Length = WkSnapPrev.Length
		&& nowMs - WkSnapAt <= 1500 && WkSnapAt > WkTurnAt + WalkSettle() && WkSnapAt > WkWalkFrom + 200)
		{
		;A cell counts as changed by more than a bit of its brightness (dark places change less)
		changedCells := 0
		for i, grey in snap
			if (Abs(grey - WkSnapPrev[i]) > 3 + (grey + WkSnapPrev[i]) // 25)
				changedCells += 1
		WkMotion := Round(changedCells / snap.Length, 2)
		result := WkMotion < StillFrac ? 1 : 0
		}
	WkSnapPrev := snap, WkSnapAt := nowMs
	return result
	}

;A loading screen, or just after one with no arrow seen since (the game's log, read now): then the
;arrow isn't behind something - no backing up or turning, just wait for it (and press Space now and
;then for a dialogue the new zone may open: WkLoadAt)
WalkLoadingScreen()
	{
	global WkLoadAt, WkGoneSpaces, WkSpaceAt ; (v1 globals it sets)
	WalkZone(true)
	if (!WkLoading && !(WkLoadedAt && WkLoadedAt > WkSeenAt))
		return false
	if (!WkLoadAt)
		{
		WkLoadAt := A_TickCount, WkGoneSpaces := 0, WkSpaceAt := 0
		WalkLog("loading screen (the game's log) - waiting for the arrow, no turning")
		}
	return true
	}

;---- Remembered obstacles: where it got stuck (zone + distance to the goal) and which way round worked ----

;Which zone the wizard is in, from the game's own log ("ConnectComplete destination Zone=..."), e.g.
;"Karamelle/KM_Z03_GumdropForest". Looked at every few seconds, only when the log has grown
WalkZone(fresh := false)
	{
	static logPath := "", lastSize := -1, zone := "", checkedAt := 0, lastHead := ""
	global ErrorLevel, WkGoalZones, WkLoading, WkLoadedAt, WkZoneFrom, WkZoneAt, WkSigilAt ; (v1 globals it sets)
	if (A_TickCount - checkedAt < (fresh ? 250 : 3000))
		return zone
	checkedAt := A_TickCount
	exePath := V1Try(WinGetProcessPath, "ahk_class " GameClass " ahk_exe " GameExe)  ; (v1: blank with no game window)
	if (exePath != "")
		{
		SplitPath(exePath, , &binDir)
		logPath := binDir "\WizardClient.log"
		}
	if (logPath = "")
		return zone
	;(v1: FileGetSize of a file that isn't there - blank, ErrorLevel 1)
	try
		logSize := FileGetSize(logPath), ErrorLevel := 0
	catch
		logSize := "", ErrorLevel := 1
	if (ErrorLevel || logSize = lastSize)
		return zone
	;The last part of the log normally has the latest zone change; the whole log if not known yet
	readFrom := (zone != "" && logSize > lastSize && lastSize > 300) ? lastSize - 300 : (zone != "" && logSize > 262144 ? logSize - 262144 : 0)
	if (logSize < lastSize)
		readFrom := 0
	lastSize := logSize
	;(v1: FileOpen gave 0 when the file couldn't be opened - v2 throws)
	try
		logFile := FileOpen(logPath, "r", "CP0")
	catch
		logFile := ""
	if (!IsObject(logFile))
		return zone
	;The game starts a new log each time it starts, with a new time stamp on its first line: read
	;that one from the top, however long it has got
	logHead := logFile.Read(17)
	if (logHead != lastHead)
		{
		if (lastHead != "")
			readFrom := 0, zone := ""
		lastHead := logHead
		}
	logFile.Pos := readFrom
	chunk := logFile.Read(logSize - readFrom)
	logFile.Close()
	;(whole lines only: a line still being written could hold half a zone name). After each zone change
	;the game lists the zones of the quest's goals ("checking goal zone ...")
	foundAt := 1, goals := "", zoneBefore := zone
	while (foundAt := RegExMatch(chunk, "(ConnectComplete destination Zone=|checking goal zone )(\S+)\r?\n", &zoneMatch, foundAt))
		{
		if (InStr(zoneMatch[1], "ConnectComplete"))
			zone := zoneMatch[2], goals := []
		else
			{
			if (!IsObject(goals))
				goals := []
			isNew := true
			for i, goalZone in goals
				if (goalZone = zoneMatch[2])
					isNew := false
			if (isNew)
				goals.Push(zoneMatch[2])
			}
		WalkZoneSeen(zoneMatch[2])
		foundAt += StrLen(zoneMatch[0])
		}
	if (IsObject(goals) && goals.Length)
		WkGoalZones := goals
	;A zone transfer (a loading screen) started and not finished yet, or finished just now - only from
	;what was written since the last look (the first read of a log is history)
	if (zoneBefore != "" && readFrom > 0)
		{
		startAt := InStr(chunk, "MSG_ZoneTransferRequest", false, -1), doneAt := InStr(chunk, "ConnectComplete destination", false, -1)
		if (startAt > doneAt)
			WkLoading := 1
		else if (doneAt)
			WkLoading := 0, WkLoadedAt := A_TickCount
		}
	;(the zone just left, and when that was noticed: coming out of a dungeon puts you at its sigil)
	if (zoneBefore != "" && zone != zoneBefore)
		{
		WkZoneFrom := zoneBefore, WkZoneAt := A_TickCount
		;(X at a sigil just before: this zone's its dungeon)
		if (WkSigilAt && A_TickCount - WkSigilAt < SigilWait + 15000 && IsObject(WkSigilZones))
			{
			;(it started: its spot's X presses that didn't, forgotten - WalkSigilCheck counts them in a row)
			WalkSigilStarted(zoneBefore)
			WkSigilZones[zone] := 1, WkSigilAt := 0
			;(a dungeon: its drops held from quick selling - AutoFarmer's QuickSell.ahk; AutoQuester has none)
			if (V1IsFunc("QsDungeonMark"))
				%"QsDungeonMark"%.Call(zone)
			}
		;(a zone a dungeon's zone leads to - its deeper zones held from quick selling too: QuickSell.ahk)
		if (V1IsFunc("QsZoneChange"))
			%"QsZoneChange"%.Call(zoneBefore, zone)
		}
	return zone
	}

;Every zone name seen in the game's log, kept in resources\known_zones.txt (a boat's "TO GOBBLERTON"
;is only understood once Karamelle/KM_Z10_Gobblerton has been seen)
WalkZonesLoad()
	{
	global WkKnownZones, WkZonesFile ; (v1 globals it sets)
	WkKnownZones := V1Obj()
	dir := AqDir()
	WkZonesFile := dir "\resources\known_zones.txt"
	Loop Read, WkZonesFile
		{
		if (Trim(A_LoopReadLine) != "")
			WkKnownZones[Trim(A_LoopReadLine)] := 1
		}
	else  ; (v1: a file that isn't there - nothing read; v2 throws without the else)
		{
		}
	}

WalkZoneSeen(zoneName)
	{
	;(v1: the list blank before WalkerInit's WalkZonesLoad - WalkZone runs earlier: DashInit - HasKey blank, the key set and the
	;append to the blank file name did nothing; v2 throws on a blank: "no method named Has")
	if (zoneName = "" || !IsObject(WkKnownZones) || WkKnownZones.Has(zoneName))
		return
	WkKnownZones[zoneName] := 1
	;(the "`n" option: v1's FileAppend wrote each `n as `r`n - v2's only with it)
	V1Do(FileAppend, zoneName "`n", WkZonesFile, "`n")
	}

WalkMemLoad()
	{
	global WkMem, WkMemFile ; (v1 globals it sets)
	WkMem := []
	if (WkMemFile = "")
		{
		dir := AqDir()
		WkMemFile := dir "\resources\walk_memory.txt"
		}
	Loop Read, WkMemFile
		{
		line := Trim(A_LoopReadLine)
		if (line = "" || SubStr(line, 1, 1) = ";" || !RegExMatch(line, "^[^|]+(\|-?\d+){5}$"))
			continue
		part := StrSplit(line, "|")
		if (part.Length >= 6)
			WkMem.Push(V1Obj({zone: part[1], dist: part[2] + 0, side: part[3] + 0, walkMs: part[4] + 0, wins: part[5] + 0, fails: part[6] + 0, preAt: 0}))
		}
	else  ; (v1: a file that isn't there - nothing read; v2 throws without the else)
		{
		}
	}

WalkMemSave()
	{
	text := "; Walker.ahk's remembered obstacles, one per line (delete a line, or the file, to forget):`n"
		. "; zone|distance to the goal where it got stuck|side that got round it (1 right, -1 left)|ms walked along it|times it worked|times it didn't`n"
	for i, spot in WkMem
		text .= spot.zone "|" spot.dist "|" spot.side "|" spot.walkMs "|" spot.wins "|" spot.fails "`n"
	V1Do(FileDelete, WkMemFile ".tmp")
	V1Do(FileAppend, text, WkMemFile ".tmp", "`n")  ; (v1 wrote each `n as `r`n)
	V1Do(FileMove, WkMemFile ".tmp", WkMemFile, 1)
	}

;The remembered obstacle in that zone nearest that distance (within MemNear), if its way round has
;worked more often than not
WalkMemFind(zone, d, any := false)
	{
	best := ""
	for i, spot in WkMem
		if (spot.zone = zone && Abs(spot.dist - d) <= MemNear && (any || spot.wins > spot.fails)
			&& (!IsObject(best) || Abs(spot.dist - d) < Abs(best.dist - d)))
			best := spot
	return best
	}

;A remembered obstacle just ahead: same zone, the goal up to MemAhead further than where it was, its
;way round has worked at least twice (so most likely the same route), and not already steered round
;in the last 20 s
WalkMemAhead(zone, d)
	{
	if (zone = "")
		return ""
	for i, spot in WkMem
		if (spot.zone = zone && d >= spot.dist && d <= spot.dist + MemAhead && spot.wins >= 2 && spot.wins > spot.fails
			&& A_TickCount - spot.preAt > 20000)
			return spot
	return ""
	}

;Learns from a try at getting round an obstacle: worked (it got clearly closer afterwards) or not
WalkMemLearn(zone, d, side, walkMs, worked)
	{
	if (zone = "" || d = "")
		return
	;What's in the file now (the other script may have learned something meanwhile)
	WalkMemLoad()
	spot := WalkMemFind(zone, d, true)
	if (!IsObject(spot))
		{
		if (!worked)
			return
		spot := V1Obj({zone: zone, dist: Round(d), side: side, walkMs: walkMs, wins: 0, fails: 0, preAt: 0})
		WkMem.Push(spot)
		}
	if (worked)
		{
		;The other way round worked this time: switch to it
		if (spot.side != side)
			spot.side := side, spot.wins := 0, spot.fails := 0
		spot.wins += 1, spot.walkMs := walkMs, spot.dist := Round((spot.dist * 3 + d) / 4)
		}
	else
		spot.fails += 1
	;Forget one that keeps failing
	if (spot.fails >= spot.wins + 2)
		{
		for i, other in WkMem
			if (other = spot)
				{
				WkMem.RemoveAt(i)
				break
				}
		WalkLog("forgot the obstacle at distance " spot.dist " in " zone " (its way round stopped working)")
		}
	WalkMemSave()
	}

;---- The game's memory: a better source for the same decisions ----
;
;In AutoFarmer, NavRead (Vision.ahk) asks the vision helper where the wizard is (x, y and its facing, yaw)
;and where the quest arrow points (the node on the game's own path it points at, the distance along that
;path, the zone changes to go), read straight out of the game's memory - READ-ONLY: nothing in the game is
;written, no keys or clicks (navmem:0 in PlayerStats.txt switches it off). The walker uses it for the
;decisions it makes anyway:
;  - heading: from the wizard's facing to where the arrow points (+ = right, like ReadArrow's). Which way
;    round the game's world is isn't known for sure, so it's only used once it's been checked: NavAgreeNeed
;    fair readings agree with the arrow on screen (mirror images and its sign is turned round), or a turn
;    went the way it said - then kept (resources\nav_calibration.txt, checked:1) and used from the start
;  - distance: the memory's / how it compares with the number printed on the arrow (worked out from fair
;    readings for each zone - it differs - kept in resources\nav_calibration.txt) - instead of the OCR'd
;    number, which misses lone digits
;  - no arrow on screen (scenery hides it, or a see-through arrow on a floor its own colour can't be picked
;    out): the memory stands in for it (WalkNavStandIn), not back up and turn to find it, or wait
;  - turns: until the wizard's facing has turned that far (NavTurn), not TurnRate's guess
;  - the goal in another zone (hops > 0): this is the way out - walk on into it, no X (StartTalk)
;Anything wrong with it (no answer, an ERR, the quest helper off, a zone that isn't the one in the game's log,
;nothing to steer at): the arrow on screen, at once - logged when it comes and goes ("the game's memory ...")

;This step's reading of the game's memory (see above). Sets WkNavOk (usable), WkNavH, WkNavD ("" until it's
;known how its distance compares with the arrow's), WkNavHops and WkNavUse (its heading is steered by).
;hScr, dScr: the arrow's heading and distance off the screen this step, to check the memory's against - ""
;when they aren't fair to (the arrow hidden or pushed up, a poor match; the heading also right after a turn,
;the camera still swinging round)
WalkNav(hScr, dScr)
	{
	static navGoalKey := "", escSaid := "", relKeep := "", relAt := 0
	global WkNavOk, WkNavUse, WkNavH, WkNavD, WkNavHops, WkNavRouted, WkNavLeft, WkNavJump, WkNavJumpAt, WkNavMob, WkNavRel ; (v1 globals it sets)
	global WkNavLast, WkNpN, WkNpGoal, WkNpAt, WkNavNoPlace, WkNpTarget, WkCollect, WkNavObj, WkRouteBest, WkRouteProg ; (v1 globals it sets)
	global WkProgBest, WkJumpKey, WkJumpStuck, WkNavMobName, WkNavMobAt, WkNavEscAt, WkNavPrev, WkWalkSamples, WkWalkSpeed ; (v1 globals it sets)
	global TurnRadius ; (v1 globals it sets)
	WkNavOk := 0, WkNavUse := 0, WkNavH := "", WkNavD := "", WkNavHops := "", WkNavRouted := 0, WkNavLeft := ""
	WkNavJump := "", WkNavJumpAt := "", WkNavMob := "", WkNavRel := ""
	;(AutoQuester on its own has no vision helper - nor the mouse's turns: said once. In a battle there's nothing to
	;steer, and the battle shouldn't wait for it)
	if (!V1IsFunc("NavRead") || inbattle)
		{
		if (!inbattle)
			WalkMouseSay("")
		return
		}
	;(the route kept away from mobs - mobavoid, on unless it's 0 - a collect goal's too: the quest's goal line goes along,
	;read only if the ask is sent, and the mobs it names aren't avoided - only the others. 2026-10-24: a collect goal
	;turned avoiding off for every mob - the map's rings went and the wizard walked into crabs it didn't need)
	;(...and while using things, going to a place or talking to an NPC the game shows no way to: only a fight goal's collecting walks
	;into mobs - WkCollect.kind)
	avoidMobs := NavRoute && !(IsObject(Stats) && Stats.Has("mobavoid") && !Stats["mobavoid"])
		&& !(WkArrived = 7 && !(IsObject(WkCollect) && WkCollect.kind != "" && WkCollect.kind != "fight"))
	nav := %"NavRead"%.Call(150, false, NavRoute, avoidMobs, WalkGoalLine)
	;A goal the game shows no way to (a newer helper's noplace 1, held 2 s for this goal, two readings running with the same goal id;
	;a missed reading keeps it 3 s): the arrow on screen is a phantom - WalkStep leaves it out, the goal's kind's own way instead.
	;An older helper sends no noplace: never - the arrow as before
	if (IsObject(nav))
		{
		WkNavLast := nav
		if (nav.noplace = 1 && nav.noplaceheld != "" && nav.noplaceheld >= 2 && nav.goalid != "")
			WkNpN := (WkNpGoal != "" && nav.goalid "|" = WkNpGoal "|") ? WkNpN + 1 : 1, WkNpGoal := nav.goalid, WkNpAt := A_TickCount
		else
			WkNpN := 0, WkNpGoal := ""
		}
	else if (WkNpN && A_TickCount - WkNpAt > 3000)
		WkNpN := 0, WkNpGoal := ""
	npWas := WkNavNoPlace ? 1 : 0
	WkNavNoPlace := WkNpN >= 2 ? 1 : 0
	if (WkNavNoPlace != npWas)
		WalkLog(WkNavNoPlace ? "the game shows no way to this goal (the game's memory: no place for " Round(nav.noplaceheld, 1) " s) - the arrow on screen left out, the goal's kind's own way instead"
			: "the game's memory no longer says the goal has no place - the arrow followed again")
	;(a talk goal the game shows no way to, its NPC found by name - TalkStep, Collect.ahk: within ApproachUnits the NPC stands in for
	;the goal's place, so the talk logic - WalkTalkGoal, the approach, X at its own prompt, the tries - works on it as on a goal that
	;has one; further off TalkStep walks the route there. Another goal's: forgotten)
	if (IsObject(WkNpTarget) && IsObject(nav) && nav.goalid != "" && nav.goalid "|" != WkNpTarget.goalid "|")
		WkNpTarget := ""
	;(...and a goal whose mode was left - to the walker's own talk logic, TalkStep's X, or a battle that finished it - and moved on
	;out there: forgotten, so its collect deck, the held-back Escape and no-arrow notice don't carry on to the goals after it. One
	;given up on: CollectCheck's)
	if (IsObject(WkCollect) && WkArrived != 7 && !WkCollect.gaveUp && IsObject(nav)
		&& nav.goalid != "" && WkCollect.goalid != "" && nav.goalid "|" != WkCollect.goalid "|")
		{
		WalkLog(WkCollect.kind ": the goal moved on (was '" WkCollect.text "') - forgotten")
		WkCollect := ""
		}
	if (IsObject(nav) && IsObject(WkNpTarget) && nav.noplace = 1 && nav.x != "" && nav.y != ""
		&& Sqrt((nav.x - WkNpTarget.x) ** 2 + (nav.y - WkNpTarget.y) ** 2) <= ApproachUnits)
		{
		nav.tx := WkNpTarget.x, nav.ty := WkNpTarget.y, nav.tz := WkNpTarget.z, nav.gx := WkNpTarget.x, nav.gy := WkNpTarget.y
		nav.gz := WkNpTarget.z, nav.hops := 0, nav.dist := Sqrt((nav.x - WkNpTarget.x) ** 2 + (nav.y - WkNpTarget.y) ** 2)
		}
	;(where the arrow points not read, but the goal in this zone known: steered at the goal itself - not the whole reading
	;dropped. 2026-10-25 11:42:01: "can't say where the arrow points", then a guessed arrival and a push)
	if (IsObject(nav) && (nav.tx = "" || nav.ty = "") && nav.hops = 0 && nav.gx != "" && nav.gy != "")
		nav.tx := nav.gx, nav.ty := nav.gy, nav.tz := nav.gz
	why := WalkNavProblem(nav)
	if (why = "")
		{
		;(set again below if this reading has a route - only a route's offset is carried over a missed reading)
		relKeep := ""
		WkNavOk := 1, WkNavObj := nav, WkNavHops := nav.hops
		;(the goal in this zone: noted - a dungeon walked out of with the goal in it is gone back into, WalkSigilGo)
		WalkGoalZone(nav)
		;(a new goal - another zone, quest goal or zone changes to go: "getting on" along the route, and the
		;badly-stuck watch, start over from it)
		goalKey := nav.zone "|" nav.goalid "|" nav.hops
		if (goalKey != navGoalKey)
			navGoalKey := goalKey, WkRouteBest := "", WkRouteProg := "", WkProgBest := "", WkJumpKey := "", WkJumpStuck := 0, relKeep := ""
		WkNavH := WalkNavHeading(nav.x, nav.y, nav.yaw, nav.tx, nav.ty)
		;(checked against the arrow on screen by where it points, not by the route)
		hTarget := WkNavH
		;The route round walls (the helper's plan over the zone's map): steer at its aim - a point ahead on it,
		;in sight - instead of straight at where the arrow points; how far is left along it
		if (NavRoute && nav.ax != "" && nav.ay != "")
			{
			hAim := WalkNavHeading(nav.x, nav.y, nav.yaw, nav.ax, nav.ay)
			if (hAim != "")
				WkNavH := hAim, WkNavRouted := 1
			if (hAim != "" && hTarget != "")
				WkNavRel := ArrowWrap(hAim - hTarget), relKeep := WkNavRel, relAt := A_TickCount
			else
				relKeep := ""
			;(right at a teleport on the game's path: the route stops there - see the teleport step in WalkStep;
			;also when its aim is the wizard's own spot, the free spot by a teleport inside its object)
			if (nav.jump != "" && nav.jx != "")
				WkNavJump := nav.jump, WkNavJumpAt := Round(nav.jx) "," V1Round(nav.jy)  ; (v1: Round of a blank - 0)
			;(a mob on the way it can't go round: see the mob step in WalkStep)
			if (nav.mob != "")
				WkNavMob := nav.mob, WkNavMobName := nav.mobname != "" ? nav.mobname : "a mob", WkNavMobAt := A_TickCount
			;(inside a mob's ring or sight: the aim leads out of it - said once each time)
			if (nav.escape != "")
				WkNavEscAt := A_TickCount
			if (nav.escape != "" && nav.escape != escSaid)
				WalkLog("inside " nav.escape "'s reach or sight - getting out of it (the way out nearest the quest's way), not waiting there")
			escSaid := nav.escape
			}
		;How fast the wizard is moving (game units per ms): the number on screen and the memory's are read a
		;moment apart (up to ~150 ms with the OCR), so a pair only says how the two compare when that moment's
		;walking is small next to the distance. (Lone digits misread: 20 or more only)
		navSpeed := ""
		if (IsObject(WkNavPrev) && A_TickCount - WkNavPrev.at < 1500 && A_TickCount > WkNavPrev.at)
			navSpeed := Sqrt((nav.x - WkNavPrev.x) ** 2 + (nav.y - WkNavPrev.y) ** 2) / (A_TickCount - WkNavPrev.at)
		WkNavPrev := V1Obj({x: nav.x, y: nav.y, at: A_TickCount})
		;(walking straight on at 1x - W held a second, no turn just now, no speed key just pressed: Cheat Engine missing a
		;press would make a 2x reading wrong - its speed, and from it the turning circle - speed over turn rate - the
		;helper's arc look goes by. Off the last 15 readings, the upper quarter: brushing a wall or being pulled into a
		;battle doesn't shrink or swell it)
		if (navSpeed != "" && navSpeed > 0.02 && navSpeed < 3 && HeldW && SpeedNow = 1 && A_TickCount - WkWalkFrom > 1000 && A_TickCount - WkTurnAt > 700
			&& (!SpeedSentAt || A_TickCount - SpeedSentAt > 1500))
			{
			if (!IsObject(WkWalkSamples))
				WkWalkSamples := []
			WkWalkSamples.Push(navSpeed)
			if (WkWalkSamples.Length > 15)
				WkWalkSamples.RemoveAt(1)
			if (WkWalkSamples.Length >= 5)
				{
				wsSorted := ""
				for each, wsV in WkWalkSamples
					wsSorted .= (wsSorted = "" ? "" : "`n") Format("{:012.6f}", wsV)
				wsSorted := Sort(wsSorted)
				wsList := StrSplit(wsSorted, "`n")
				WkWalkSpeed := wsList[Ceil(wsList.Length * 0.75)] + 0
				TurnRadius := V1Min(900, V1Max(60, V1Div(WkWalkSpeed, V1Mul(TurnRate, 0.0174533))))  ; (v1: TurnRate blank before WalkerInit - TurnRadius blank)
				}
			}
		WalkNavMoveCheck(nav)
		;(is the wizard walking on - the stuck watch's)
		WalkMoveTrack(nav)
		;(how the arrow's distance compares with the memory's differs from zone to zone - 41 in one, about 100
		;in Pigswick Academy: each zone's own once worked out there)
		if (nav.zone != WkNavScaleZone)
			WalkNavZoneScale(nav.zone)
		;(only with the goal in this zone: zones away the arrow's number counts the legs in the other zones too - its readings
		;fell 29.67 to 14.44 walking one zone, 2026-10-25 11:25, and put the scale off: the memory's distance dropped)
		;(v1: the memory's distance blank - blank > 0 compared as text, false)
		if (dScr != "" && dScr >= 20 && V1Gt(nav.dist, 0) && navSpeed != "" && navSpeed * 150 <= nav.dist * 0.04 && nav.hops = 0)
			WalkNavLearnScale(nav.dist / dScr, nav.hops)
		;(its distance always, the memory read: a scale distrusted, or none - 100, every zone worked out with the goal in it
		;has been 100-103; the OCR'd number misses lone digits, and with no distance the memory can't stand in for the arrow)
		;(v1: no scale known - blank > 0 compared as text, false)
		navScale := (V1Gt(WkNavScale, 0) && WkNavScaleBad < 2) ? WkNavScale : 100
		if (nav.dist != "")
			WkNavD := Round(nav.dist / navScale)
		if (WkNavRouted && nav.left != "")
			WkNavLeft := nav.left / navScale
		if (hScr != "" && hTarget != "")
			WalkNavVote(hScr, hTarget)
		WkNavUse := WkNavTrusted && WkNavH != ""
		}
	;(a reading missed - the helper busy a moment: the route's offset from the arrow kept for 2 s, the arrow steered by
	;with it - never the memory's old heading)
	if (why != "" && relKeep != "" && A_TickCount - relAt < 2000)
		WkNavRel := relKeep
	WalkNavSay(why, nav)
	;(the mouse's turns not tried at all - not steering by the game's memory, or switched off: said - MouseSteer.ahk)
	WalkMouseSay(why)
	WalkNavRouteSay(why = "" ? nav : "")
	;(no way on but teleports that don't take the wizard - the helper gave them up: WalkStep stops walking)
	if (why = "" && InStr(nav.routewhy, "teleport that doesn't take the wizard") && !WkJumpStuck)
		WkJumpStuck := 1
	}

;Another player's battle on the way that the helper's route can't go round (AutoFarmer's duelavoid setting - off unless 1:
;the duel circles in the game's memory aren't confirmed in the game yet; the helper's route line's 14-16, NavRead's duel):
;stand still till it ends - also through a reading missed meanwhile (1.5 s) - said once a battle, and when the wait ends.
;The helper gives up after 4 minutes (a battle takes minutes, and walking in joins it) and routes on past it, round its edge
;where there's room. Not at a teleport. True while waiting (WalkStep returns then); an older helper, or none: never
WalkDuelWait()
	{
	static wdAt := 0, wdSaid := "", wdLong := 0
	global WkBestTime, WkLastRead, WkTries ; (v1 globals it sets)
	;(a battle said but not asked about for 5 s - the walk stopped (F8) or ended, or another wait came first: a fresh
	;start, not said - else the next walk's first step logs an old walk's battle as gone from the way)
	if (wdSaid != "" && A_TickCount - wdAt > 5000)
		wdAt := 0, wdSaid := "", wdLong := 0
	wdSecs := (WkNavOk && IsObject(WkNavObj)) ? WkNavObj.duel : ""
	if (wdSecs != "" && WkNavJump = "")
		{
		wdAt := A_TickCount, wdLong := wdSecs
		wdWhere := V1Round(WkNavObj.duelx) "," V1Round(WkNavObj.duely)  ; (v1: Round of a blank - 0)
		if (wdSaid = "")
			wdSaid := wdWhere, WalkLog("another player's battle on the way at " wdWhere " and no way round it - waiting for it to end (walked past after 4 minutes)")
		}
	else if (!wdAt || WkNavOk || WkNavJump != "" || A_TickCount - wdAt >= 1500)
		{
		;(over: said - the helper walking on past it after its 4 minutes, or the battle gone from the way. Given up: the
		;helper's last seconds said were within 2 of its 240 - its asks counted only less than 2 s apart - so 235 and
		;more; a battle that ended sooner is gone from the way)
		if (wdSaid != "")
			WalkLog("another player's battle at " wdSaid (wdLong >= 235 ? " still going after " Round(wdLong) " s - walking on past it, round its edge where there's room" : " no longer on the way - walking on"))
		wdAt := 0, wdSaid := "", wdLong := 0
		return false
		}
	if (KeysDown || HeldW)
		ReleaseKeys(true)
	WkBestTime := A_TickCount, WkLastRead := A_TickCount, WkTries := 0
	SetStatus("waiting - another player's battle on the way (" Round(wdLong) " s)")
	Sleep(300)
	return true
	}

;Logs the route round walls coming and going: once each way (a moment with none while it plans isn't a change)
WalkNavRouteSay(nav)
	{
	global WkRouteState ; (v1 globals it sets)
	if (!NavRoute || !IsObject(nav))
		return
	if (WkNavRouted && WkRouteState != "on")
		WalkLog("the route round walls (the zone's map): steering along it" (WkNavLeft != "" ? " - " Round(WkNavLeft) " to go" : ""))
	else if (!WkNavRouted && WkRouteState = "on" && nav.routewhy != "planning")
		WalkLog("no route round walls (" (nav.routewhy = "" ? "?" : nav.routewhy) ") - steering at where the arrow points")
	else if (!WkNavRouted && WkRouteState = "" && nav.routewhy != "" && nav.routewhy != "planning")
		WalkLog("no route round walls (" nav.routewhy ") - steering at where the arrow points")
	if (WkNavRouted)
		WkRouteState := "on"
	else if (nav.routewhy != "planning")
		WkRouteState := "off"
	}

;Why this reading of the game's memory can't be used ("" it can)
WalkNavProblem(nav)
	{
	if (!IsObject(nav))
		return InStr(NavWhy, "navmem:0") ? "is switched off (" NavWhy ")" : "can't be read (" (NavWhy != "" ? NavWhy : "no answer") ")"
	if (nav.x = "" || nav.y = "" || nav.yaw = "")
		return "can't say where the wizard is (loading?)"
	if (nav.enabled = "")
		return "can't say if the game's quest helper is on"
	if (!nav.enabled)
		return "says the game's quest helper is off (no quest tracked?)"
	if (nav.tx = "" || nav.ty = "")
		return "can't say where the arrow points (the quest catching up after a zone change?)"
	if (nav.zone = "")
		return "can't say which zone it is"
	;(the game's log is looked at every few seconds: after a zone change, look again before calling it wrong)
	logZone := WalkZone()
	if (logZone != "" && !WalkSameZone(logZone, nav.zone))
		{
		logZone := WalkZone(true)
		if (logZone != "" && !WalkSameZone(logZone, nav.zone))
			return "says the zone is " nav.zone ", the game's log " logZone
		}
	return ""
	}

WalkSameZone(a, b)
	{
	return StrReplace(a, "\", "/") = StrReplace(b, "\", "/")
	}

;Degrees from where the wizard faces (yaw: forward = (-sin yaw, -cos yaw), z up) to (tx, ty), + = to the
;right like ReadArrow's - if the game's world is right-handed; WkNavSign turns it round when the arrow on
;screen says otherwise. "" if the target is right where the wizard is
WalkNavHeading(x, y, yaw, tx, ty)
	{
	dx := tx - x, dy := ty - y
	if (dx * dx + dy * dy < 4)
		return ""
	;(the yaw a wizard facing the target would have, less the one it has)
	return WkNavSign * ArrowWrap((ArrowAtan2(-dx, -dy) - yaw) * 57.29578)
	}

;Checks the memory's heading against the arrow's on screen. NavAgreeNeed readings that agree (the same side,
;within 35 degrees) and it's steered by; that many mirror images in a row (the other side) and its sign is
;turned round; five that match neither while it's trusted and it isn't till they agree again. Only clear
;readings count: 20-160 degrees off straight ahead both (near 0 or 180 a few degrees decide the side)
WalkNavVote(hScr, hMem)
	{
	global WkNavAgree, WkNavMirror, WkNavOdd, WkNavMirrorSaid, WkNavSign, WkNavTrusted ; (v1 globals it sets)
	if (Abs(hScr) < 20 || Abs(hScr) > 160 || Abs(hMem) < 20 || Abs(hMem) > 160)
		return
	if (hScr * hMem > 0 && Abs(ArrowWrap(hScr - hMem)) <= 35)
		{
		WkNavAgree += 1, WkNavMirror := 0, WkNavOdd := 0
		if ((!WkNavTrusted || !WkNavChecked) && WkNavAgree >= NavAgreeNeed)
			WalkNavConfirm("its heading agrees with the arrow's (" WkNavAgree " readings, the last: arrow " Round(hScr) ", memory " Round(hMem) " degrees)")
		}
	else if (hScr * hMem < 0 && Abs(ArrowWrap(hScr + hMem)) <= 35)
		{
		WkNavMirror += 1, WkNavAgree := 0, WkNavOdd := 0
		;(its sign checked - the wizard's own facing turned with the keys the way it said, or the arrow agreed:
		;it's the game's, the same everywhere. An arrow that reads as its mirror image is misread there - a dais,
		;a carpet, the camera's angle - and isn't followed; turns go on checking the sign: NavTurn turns it round
		;if one ever goes the other way)
		if (WkNavMirror >= NavAgreeNeed && WkNavChecked)
			{
			WkNavMirror := 0
			if (A_TickCount - WkNavMirrorSaid > 60000)
				{
				WkNavMirrorSaid := A_TickCount
				WalkLog("the arrow reads as the game's memory's mirror image (" NavAgreeNeed " readings, the last: arrow " Round(hScr) ", memory " Round(hMem) " degrees) - the arrow misread here? Keeping the memory's heading (checked by turning)")
				}
			}
		else if (WkNavMirror >= NavAgreeNeed)
			{
			WkNavSign := -WkNavSign, WkNavMirror := 0, WkNavTrusted := 0
			WalkLog("the game's memory: its heading is the arrow's mirror image (" NavAgreeNeed " readings, the last: arrow " Round(hScr) ", memory " Round(hMem) " degrees) - turned it round, checking again")
			WalkNavUncheck()
			}
		}
	else
		{
		WkNavOdd += 1
		if (WkNavOdd >= 5 && WkNavTrusted)
			{
			WkNavTrusted := 0, WkNavAgree := 0
			WalkLog("the game's memory: its heading doesn't match the arrow's (" WkNavOdd " readings, the last: arrow " Round(hScr) ", memory " Round(hMem) " degrees) - following the arrow till they agree again")
			}
		}
	}

;Walking straight on (W held, no turn just made) while the memory's heading isn't steered by - its sign checked
;before (a battle starting froze a turn, say): once the wizard has gone 80 units the way the memory says it faces
;(within 20 degrees; its facing not changed on the way), that facing is live - steered by again. Till then the walker
;steers at the arrow, which walks the game's straight path - through mobs the route goes round
WalkNavMoveCheck(nav)
	{
	static from := ""
	if (WkNavTrusted || !WkNavChecked || !HeldW || nav.x = "" || nav.yaw = "" || A_TickCount - WkTurnAt < 300)
		{
		from := ""
		return
		}
	if (!IsObject(from) || Abs(ArrowWrap((nav.yaw - from.yaw) * 57.29578)) > 10)
		{
		from := V1Obj({x: nav.x, y: nav.y, yaw: nav.yaw})
		return
		}
	mvX := nav.x - from.x, mvY := nav.y - from.y
	if (mvX * mvX + mvY * mvY < 6400)
		return
	;(the way it went against the way the memory says it faces - a wizard facing along it would have this yaw)
	mvOff := Abs(ArrowWrap((ArrowAtan2(-mvX, -mvY) - nav.yaw) * 57.29578))
	from := ""
	if (mvOff <= 20)
		WalkNavConfirm("the wizard walked " Round(Sqrt(mvX * mvX + mvY * mvY)) " units the way its facing says (" Round(mvOff) " degrees off)")
	}

;Is the wizard walking on, by the game's memory - WalkStep's stuck watch (each usable reading, from WalkNav): its place reading
;by reading over the last StuckTime (WkMoveLog), each step's part the way it faces (forward is (-sin yaw, -cos yaw), as
;WalkNavHeading has it). Walking on (WkMovedAt): over the last second or so, MoveFrac of its walking speed or more the way it
;faces. W held into a wall a few degrees off square slides it sideways along the wall - a hundred units a second or more, no
;nearer anything: not walking on (any 120 units in 4 s counted before: a wall slid along kept the picture's watch off and the
;stuck watch 15 s). A gap in the readings (over 2 s - a battle, a loading screen, a talk), another zone, or a jump far beyond
;walking (a teleport, a reading of something else): begun again there, nothing walked
;(v2: the watch's ticks are 0 or a tick, never blank - WalkerInit / WalkMoveReset - and each is looked at only once it's set;
;the settings, WkWalkSpeed and SpeedNow by V1Ge / V1Gt / V1Mul - blank before WalkerInit or till measured, as v1 compared them)
WalkMoveTrack(nav)
	{
	global WkMoveNow, WkMoveLog, WkMoveZone, WkMoveSeen, WkMovedAt ; (v1 globals it sets)
	if (nav.x = "" || nav.y = "" || nav.yaw = "")
		return
	now := A_TickCount
	WkMoveNow := 0
	;(walking is about 0.9 units a ms at 1x - WkWalkSpeed once measured, a mount's faster; never less: sliding along a wall a while
	;brings WkWalkSpeed's samples down -, sped up as the speedhack has it)
	mvSpeed := (V1Gt(WkWalkSpeed, 0.9) ? WkWalkSpeed : 0.9) * (V1Gt(SpeedNow, 1) ? SpeedNow : 1)
	mvLast := (IsObject(WkMoveLog) && WkMoveLog.Length) ? WkMoveLog[WkMoveLog.Length] : ""
	if (!IsObject(mvLast) || !WkMoveSeen || now - WkMoveSeen > 2000 || nav.zone != WkMoveZone)
		{
		WkMoveLog := [V1Obj({at: now, x: nav.x, y: nav.y, yaw: nav.yaw, f: 0})], WkMoveZone := nav.zone, WkMoveSeen := now
		return
		}
	WkMoveSeen := now
	mvDx := nav.x - mvLast.x, mvDy := nav.y - mvLast.y
	;(over 3 times walking, and a margin: not walked)
	if (Sqrt(mvDx * mvDx + mvDy * mvDy) > (now - mvLast.at) * 3 * mvSpeed + 1000)
		{
		WkMoveLog := [V1Obj({at: now, x: nav.x, y: nav.y, yaw: nav.yaw, f: 0})]
		return
		}
	;(the step's part the way it faced - halfway between the two readings' facings: a mouse turn swings it at once)
	mvFwd := -(mvDx * (Sin(nav.yaw) + Sin(mvLast.yaw)) + mvDy * (Cos(nav.yaw) + Cos(mvLast.yaw))) / 2
	WkMoveLog.Push(V1Obj({at: now, x: nav.x, y: nav.y, yaw: nav.yaw, f: mvFwd}))
	while (WkMoveLog.Length > 2 && V1Gt(now - WkMoveLog[2].at, StuckTime))
		WkMoveLog.RemoveAt(1)
	;(the last second or so: back to the first reading a second or more before this one)
	mvFwd := 0
	mvFrom := now
	mvI := WkMoveLog.Length
	while (mvI > 1 && now - mvFrom < 1000)
		{
		mvFwd += WkMoveLog[mvI].f
		mvI -= 1
		mvFrom := WkMoveLog[mvI].at
		}
	if (now - mvFrom >= 700 && V1Ge(mvFwd, V1Mul(V1Mul(MoveFrac, mvSpeed), now - mvFrom)))
		WkMovedAt := now, WkMoveNow := 1
	}

;What the game's memory says of the wizard walking on, for the stuck watch: -1 nothing (no usable reading in the last 2 s - navmem
;off, the helper down or busy, the watch just begun again: the watch as without it), 0 not walking on (not within StuckTime),
;1 walking on (within the last StuckTime), 2 walking on right now (the last reading's second - judged afresh each reading, so no
;grace after it: walked into a wall, the picture's watch is back within half a second)
WalkMoveState()
	{
	if (!WkMoveSeen || A_TickCount - WkMoveSeen > 2000)
		return -1
	if (!WkMovedAt || V1Gt(A_TickCount - WkMovedAt, StuckTime))
		return 0
	return WkMoveNow ? 2 : 1
	}

;The stuck watch's walking on by the game's memory begun again: WalkReset, after Unstick (its back-up, turn and walk are the
;bot's own moves)
WalkMoveReset()
	{
	global WkMoveLog, WkMoveZone, WkMovedAt, WkMoveNow, WkMoveSeen ; (v1 globals it sets)
	WkMoveLog := [], WkMoveZone := "", WkMovedAt := 0, WkMoveNow := 0, WkMoveSeen := 0
	}

;For the stuck line: what the game's memory saw the wizard's place do over the last StuckTime - how far it went, how far that took
;it from where it was, and how much of it the way it faces ("" no reading in the last 2 s). 2026-10-26 "stuck on nothing": this
;says whether it stood, slid along something or walked on
WalkMoveSay()
	{
	if (!WkMoveSeen || A_TickCount - WkMoveSeen > 2000 || !IsObject(WkMoveLog) || WkMoveLog.Length < 2)
		return ""
	mvPath := 0
	mvFwd := 0
	Loop WkMoveLog.Length - 1
		{
		mvLast := WkMoveLog[A_Index], mvE := WkMoveLog[A_Index + 1]
		mvPath += Sqrt((mvE.x - mvLast.x) ** 2 + (mvE.y - mvLast.y) ** 2)
		mvFwd += mvE.f
		}
	mvFirst := WkMoveLog[1]
	mvNet := Sqrt((mvE.x - mvFirst.x) ** 2 + (mvE.y - mvFirst.y) ** 2)
	return "; the game's memory: its place moved " Round(mvPath) " units in the last " Round((mvE.at - mvFirst.at) / 1000, 1) " s (" Round(mvNet) " from where it was, " Round(mvFwd) " the way it faces)"
	}

;One reading of how the memory's distance compares with the number on the arrow (game units per arrow unit).
;The last nine are kept; once five are within 12% of their middle one, that's it (kept in the file; the
;memory's distance is used from then on). Two in a row 25% off the one in use and it isn't used till it's
;worked out again
WalkNavLearnScale(ratio, hops)
	{
	global WkNavScaleBad, WkNavScale, WkNavScaleAll ; (v1 globals it sets)
	WkNavScales.Push(ratio)
	if (WkNavScales.Length > 9)
		WkNavScales.RemoveAt(1)
	;(v1: no scale known - blank > 0 compared as text, false)
	if (V1Gt(WkNavScale, 0))
		{
		if (Abs(ratio / WkNavScale - 1) <= 0.25)
			WkNavScaleBad := 0
		;(only a guess borrowed from other zones: this zone's own readings so far, till it's worked out)
		else if (++WkNavScaleBad >= 2 && WalkNavOwnScale(WkNavScaleZone) = "")
			{
			WkNavScale := WalkMedian(WkNavScales), WkNavScaleBad := 0
			WalkLog("the game's memory: other zones' distance scale doesn't fit " WkNavScaleZone " - " Round(WkNavScale, 2) " from its readings so far, till it's worked out")
			}
		else if (WkNavScaleBad = 2)
			WalkLog("the game's memory: its distance doesn't match the arrow's any more (" Round(ratio, 2) " game units per arrow unit, not " Round(WkNavScale, 2) ") - its distance by 100 to the arrow's 1 till it's worked out again")
		}
	if (WkNavScales.Length < 5)
		return
	mid := WalkMedian(WkNavScales), close := 0
	for i, r in WkNavScales
		if (Abs(r / mid - 1) <= 0.12)
			close += 1
	own := WalkNavOwnScale(WkNavScaleZone) != ""
	if (close < 5 || (own && Abs(mid / WkNavScale - 1) <= 0.03))
		return
	was := WkNavScale
	WkNavScale := mid, WkNavScaleBad := 0, WkNavZScales[WkNavScaleZone] := mid
	WkNavScaleAll := WalkNavMiddleScale()
	WalkLog("the game's memory: in " WkNavScaleZone " the arrow's distance is its distance / " Round(mid, 2) " (" close " readings agree" (hops = "" ? "" : ", " hops " zone changes to go") (was = "" ? "" : "; " (own ? "it was " : "other zones' ") Round(was, 2)) ") - its distance used from now on, not the OCR'd number")
	WalkNavSave()
	}

;The middle value of a list of numbers
WalkMedian(list)
	{
	sorted := []
	for i, v in list
		{
		at := 1
		while (at <= sorted.Length && sorted[at] < v)
			at++
		sorted.InsertAt(at, v)
		}
	n := sorted.Length
	return Mod(n, 2) ? sorted[(n + 1) // 2] : (sorted[n // 2] + sorted[n // 2 + 1]) / 2
	}

;Why the walker can't try the mouse's turns at all now (MouseSteer.ahk): switched off, or not steering by the game's
;memory - a mouse count's worth is measured only on a turn steered by it, and WalkStep's small corrections (MouseTurn)
;try the mouse only while it steers so, measured or not. Said once a run and on each change, and "ready" once it can
;after that; nothing said while all's well from the start. why: this reading's problem (WalkNavProblem - "" none).
;Nothing read for it: the walker's own state
WalkMouseSay(why)
	{
	static wmSaid := ""
	if (!V1IsFunc("MouseSteerOn"))
		return
	if (!MouseSteerOn())
		wmNow := V1IsFunc("NavRead") ? "off (Settings: Turn with the mouse while walking)" : "off (no game memory read here - AutoFarmer's vision helper reads it)"
	else if (WkNavUse)
		wmNow := wmSaid = "" ? "" : "ready - steering by the game's memory, the mouse tried on its turns"
	else
		wmNow := "waiting for the game's memory (" (why != "" ? "it " why : WkNavTrusted ? "no heading to the goal" : "its heading not checked against the arrow's yet") ")"
	if (wmNow = wmSaid)
		return
	wmSaid := wmNow
	if (wmNow != "")
		MouseSteerNote(wmNow)
	}

;Logs the game's memory coming and going: once each way, not every step
WalkNavSay(why, nav)
	{
	global WkNavState ; (v1 globals it sets)
	state := why = "" ? "on" : "off"
	if (state = WkNavState)
		return
	if (state = "on")
		WalkLog("the game's memory (read-only) can be used: " nav.zone (nav.hops = "" ? "" : nav.hops > 0 ? ", the goal " nav.hops " zone change" (nav.hops = 1 ? "" : "s") " away" : ", the goal in this zone")
			. " - " (WkNavTrusted ? "steering by it" : "steering by it once its heading agrees with the arrow's")
			. (V1Gt(WkNavScale, 0) ? "" : "; its distance once it's known how it compares with the arrow's"))
	else
		WalkLog("the game's memory " why " - following the on-screen arrow")
	WkNavState := state
	}

;Holds A (h < 0) or D until the wizard's facing, re-read from the game's memory as it turns, has turned h
;degrees (+ = right): within NavTurnTol - let go a little early for the bit it turns on after the key is up
;- at most NavTurnCap ms; it doesn't turn back if it went past. The memory lost on the way: the rest by TurnRate, like
;Turn. Turned the other way than the memory's heading said: its sign was wrong - turned round, and checked
;against the arrow again. Not turning at all (the keys not taken: a window open?): let go - twice in a row and
;its heading isn't trusted till it agrees with the arrow again. False if the facing can't be read to start
;with (Turn then turns by TurnRate)
NavTurn(h)
	{
	static stillTurns := 0, wrongTurns := 0
	global KeysDown, Refocus, WkTurnAt, SpeedMiss, SpeedOff, WkNavSign, WkNavTrusted, WkNavAgree, WkNavMirror, WkNavOdd ; (v1 globals it sets)
	global WkNavTurnLog, WkNavTurns, WkBestTime, WkLastRead ; (v1 globals it sets)
	if (!V1IsFunc("NavRead") || Abs(h) < 1)
		return false
	first := %"NavRead"%.Call(120)
	if (!IsObject(first) || first.yaw = "")
		return false
	Critical()
	if (!Walking || !GameActive())
		{
		Critical("Off")
		return true
		}
	key := h < 0 ? "a" : "d"
	KeysDown := 1
	Send("{Blind}{" key " down}")
	Critical("Off")
	downAt := A_TickCount, lookAt := A_TickCount, prevYaw := first.yaw, turned := 0, looks := 0, ending := ""
	capMs := Round(Abs(h) / (TurnRate * SpeedNow) * 1.6) + 300
	capMs := capMs > NavTurnCap ? NavTurnCap : capMs
	Loop
		{
		Sleep(10)
		if (!Walking)
			{
			ending := "walking off"
			break
			}
		if (!GameActive())
			{
			ReleaseKeys(), Refocus := 1, ending := "focus lost"
			break
			}
		lookMs := A_TickCount - lookAt, lookAt := A_TickCount
		nav := %"NavRead"%.Call(120)
		took := A_TickCount - downAt
		if (!IsObject(nav) || nav.yaw = "")
			{
			;(the rest by TurnRate, as Turn would)
			rest := Round((Abs(h) - Abs(turned)) / (TurnRate * SpeedNow))
			if (rest > 0 && turned * h >= 0)
				HoldFor(rest > 800 ? 800 : rest)
			ending := "the memory lost"
			break
			}
		looks += 1
		turned += WkNavSign * ArrowWrap((nav.yaw - prevYaw) * 57.29578), prevYaw := nav.yaw
		left := h - turned
		;Let go now or after one more look, whichever lands nearer (within NavTurnTol): it turns on a little
		;after the key comes up, and this look is a moment old (coast: that much more, at the rate so far)
		rate := (took > 60 && Abs(turned) > 1) ? Abs(turned) / took : TurnRate * SpeedNow
		coast := rate * (lookMs / 2 + 16), shortNow := Abs(left) - coast
		if (left * h <= 0 || shortNow <= 0 || (shortNow <= NavTurnTol && shortNow <= Abs(shortNow - rate * lookMs)))
			break
		if (turned * h < 0 && Abs(turned) > 10)
			{
			ending := "wrong way"
			break
			}
		if (took > 500 && Abs(turned) < 2)
			{
			ending := "not turning"
			break
			}
		if (took > capMs)
			{
			ending := "time limit"
			break
			}
		}
	Send("{Blind}{" key " up}")
	WkTurnAt := A_TickCount
	took := A_TickCount - downAt
	stillTurns := ending = "not turning" ? stillTurns + 1 : 0
	;(not turning: Wizard101's own menu may be up - keys don't reach the wizard then; closed, and tried again)
	if (ending = "not turning")
		HoldW(0), SpeedSet(0, "the game's menu up?")
	if (ending = "not turning" && WalkCloseGameMenu() = 1)
		stillTurns := 0
	;(the speed checked by how fast the wizard turned: Cheat Engine not attached (the game restarted), the key not taking
	;('Disable when released' ticked) - off for this run; sped up while it should be at 1x - its 1x key again)
	if (ending = "" && took > 150 && Abs(turned) > 20 && V1IsFunc("SpeedSet"))
		{
		ratio := (Abs(turned) / took) / TurnRate
		if (SpeedNow > 1 && ratio < SpeedNow * 0.55)
			{
			SpeedMiss += 1
			if (SpeedMiss >= 2 && SpeedOff = "")
				{
				SpeedOff := "the wizard turned at " Round(ratio, 1) "x, not " SpeedNow "x - is Cheat Engine running and attached to this Wizard101 (Setup's 'Cheat Engine speedhack' does both), its walking key set, 'Disable when released' unticked?"
				WalkLog("speed: off for this run - " SpeedOff)
				SpeedSet(0, "not sped up", true)
				}
			}
		else if (SpeedNow = 1 && ratio > 1.6 && SpeedSentAt && A_TickCount - SpeedSentAt > 10000)
			SpeedSet(0, "the wizard turned at " Round(ratio, 1) "x - the 1x key again", true)
		else
			SpeedMiss := 0
		}
	;(its sign checked once - the arrow agreed, or turns went the way it said: a turn the other way is the game turning the
	;wizard - pulled into a battle's circle, a mob's charge (the logs: all of them came 4-6 s before a battle) - not a wrong
	;sign. Kept, unless three in a row, none the right way between)
	if (ending = "wrong way" && WkNavChecked)
		{
		wrongTurns += 1
		if (wrongTurns < 3)
			{
			WalkLog("memory turn: holding " key " turned the wizard " Round(Abs(turned)) " degrees the other way - the game turning him (a battle starting?): its heading's sign kept (" wrongTurns " of 3 in a row)")
			ending := "turned by the game"
			}
		else
			wrongTurns := 0
		}
	else if (turned * h > 0 && Abs(turned) >= 15)
		wrongTurns := 0
	if (ending = "wrong way")
		{
		WkNavSign := -WkNavSign, WkNavTrusted := 0, WkNavAgree := 0, WkNavMirror := 0, WkNavOdd := 0
		WalkLog("memory turn: holding " key " turned the wizard " Round(Abs(turned)) " degrees the other way than the game's memory said - turned its sign round, checking it again")
		WalkNavUncheck()
		}
	;(its sign checked: a wizard that doesn't turn is held - a battle starting, a ride, a menu - not the memory wrong:
	;still steered by. Not checked yet: not till it agrees with the arrow, or the wizard turns or walks the way it says)
	else if (ending = "not turning" && stillTurns >= 2 && WkNavChecked)
		{
		if V1Gt(V1Ago(WkNavTurnLog), 20000)  ; (v1: WkNavTurnLog blank before WalkerInit - false)
			WkNavTurnLog := A_TickCount, WalkLog("memory turn: the wizard's facing didn't change with " key " held, twice - held by the game (a battle starting, a ride?): still steering by the game's memory")
		;(out of battle a window can be what holds him - a shop X opened that Escape didn't close: its close button)
		if (!inbattle)
			WalkCloseWindow("the wizard doesn't turn - a window open over the game?")
		}
	else if (ending = "not turning" && stillTurns >= 2)
		{
		WkNavTrusted := 0, WkNavAgree := 0
		WalkLog("memory turn: the wizard's facing didn't change with " key " held, twice - not steering by the game's memory till it agrees with the arrow again, or the wizard turns or walks the way it says")
		}
	else if (!WkNavTurns || (ending != "" && ending != "walking off" && ending != "focus lost" && V1Gt(V1Ago(WkNavTurnLog), 60000)))  ; (v1: WkNavTurnLog blank before WalkerInit - false)
		{
		if (ending != "")
			WkNavTurnLog := A_TickCount
		WalkLog("memory turn" (WkNavTurns ? "" : " (the first)") ": " Round(h) " degrees asked, " Round(turned) " turned in " took " ms, " looks " looks at the game's memory" (ending = "" ? "" : " - stopped: " ending))
		}
	;(turned a fair way, the way its heading said: which way round that is, is right)
	if (ending != "wrong way" && ending != "not turning" && turned * h > 0 && Abs(turned) >= 15 && (!WkNavChecked || !WkNavTrusted))
		WalkNavConfirm("holding " key " turned the wizard " Round(Abs(turned)) " degrees the way its heading said")
	WkNavTurns := V1N(WkNavTurns) + 1  ; (v1: += on a blank counted it as 0)
	;(a long one - a window closed, the game's menu looked at: its time isn't walking without getting closer. 2026-10-25
	;11:29:18: Unstick the moment the shop held him 11 s here was closed)
	if (A_TickCount - downAt > 1500)
		WkBestTime := A_TickCount, WkLastRead := A_TickCount
	return true
	}

;The memory's heading is right way round (the arrow agreed, or a turn went the way it said): steered by from now
;on, and kept in resources\nav_calibration.txt (checked:1), so the next run steers by it from the start
WalkNavConfirm(how)
	{
	global WkNavTrusted, WkNavAgree, WkNavMirror, WkNavOdd, WkNavChecked ; (v1 globals it sets)
	was := WkNavTrusted
	WkNavTrusted := 1, WkNavAgree := NavAgreeNeed, WkNavMirror := 0, WkNavOdd := 0
	if (!was)
		WalkLog("the game's memory: " how " - steering by it")
	if (!WkNavChecked || WkNavSign != WkNavSignSaved)
		WkNavChecked := 1, WalkNavSave()
	}

;Its sign was turned round: not checked any more (in the file too) till the arrow or a turn checks it again
WalkNavUncheck()
	{
	global WkNavChecked ; (v1 globals it sets)
	if (WkNavChecked)
		WkNavChecked := 0, WalkNavSave()
	}

;No arrow on screen: can the game's memory stand in for it? Its heading in use and its distance known, no
;battle (AutoFarmer saw the spellbook a moment ago), no loading screen (the game's log) and not the first
;moment after one. Its heading not checked yet (WkNavTrusted): a turn checks it - towards the goal when that's
;well off to one side, else 45 degrees right (walking turns back) - when the arrow's been gone a moment, no
;dialogue's open and it's walking (not at a goal), at most once every 10 s (straight away again after one that
;turned its sign round); NavTurn trusts it if the wizard turned the way it said. True if it stands in, -1 if it turned to check
WalkNavStandIn()
	{
	static checkAt := 0, checkSign := 0
	if (!WkNavOk || WkNavH = "" || WkNavD = "" || inbattle || !WalkSureNoBattle())
		return false
	WalkZone(true)
	if (WkLoading || (WkLoadedAt && A_TickCount - WkLoadedAt < 1500))
		return false
	if (WkNavTrusted)
		return WkNavUse
	;(its sign is checked - distrusted for not matching the arrow, or the keys not being taken: a turn can't
	;settle that - the arrow agreeing again, or the next zone)
	if (WkNavChecked)
		return false
	;(just turned round by the last check: the next one straight away, to confirm it)
	if (WkArrived != 0 || (WkSeenAt && A_TickCount - WkSeenAt < 1500) || A_TickCount - checkAt < (WkNavSign != checkSign ? 1500 : 10000) || WalkDialogOpen())
		return false
	checkAt := A_TickCount, checkSign := WkNavSign
	turnBy := Abs(WkNavH) >= 25 ? WkNavH : 45
	WalkLog("no arrow on screen, and the game's memory's heading isn't checked yet - turning " Round(turnBy) " degrees to check it (it's right if the wizard turns the way it says)")
	if (KeysDown || HeldW)
		ReleaseKeys()
	if (!NavTurn(turnBy))
		{
		WalkLog("the game's memory: the wizard's facing can't be read - no check")
		return false
		}
	return -1
	}

;The arrow's distance per game unit for this zone: its own once worked out there, else the middle of the same
;world's zones (it seems to go by world: Wysteria's about 100, Wizard City's about 41), else of all of them (or
;the one kept from before zones were told apart); readings start over
WalkNavZoneScale(zone)
	{
	global WkNavScaleZone, WkNavScales, WkNavScaleBad, WkNavScale, WkNavTrusted, WkNavAgree, WkNavOdd ; (v1 globals it sets)
	WkNavScaleZone := zone, WkNavScales := [], WkNavScaleBad := 0
	zsOwn := WalkNavOwnScale(zone)
	WkNavScale := zsOwn != "" ? zsOwn : WalkNavMiddleScale(V1At(StrSplit(zone, "/"), 1))
	;(nothing worked out anywhere yet - a new install: a first guess, 100 (every zone worked out with the goal in it); two
	;fair readings that disagree put this zone's own in its place, WalkNavLearnScale)
	if (WkNavScale = "")
		WkNavScale := 100
	;(a heading that's checked but was distrusted in the last zone - not matching the arrow, the keys not taken:
	;another go here, as a fresh run would)
	if (WkNavChecked && !WkNavTrusted)
		WkNavTrusted := 1, WkNavAgree := NavAgreeNeed, WkNavOdd := 0
	}

;The middle of the zones' distance per game unit: those in world (the zone's first part, e.g. "Wysteria") if
;any are known, else all of them; the one kept from before zones were told apart if none
WalkNavMiddleScale(world := "")
	{
	vals := [], inWorld := []
	for zoneName, sc in WkNavZScales
		{
		;(only fair ones - WalkNavOwnScale)
		if (WalkNavOwnScale(zoneName) = "")
			continue
		vals.Push(sc)
		if (world != "" && V1At(StrSplit(zoneName, "/"), 1) = world)
			inWorld.Push(sc)
		}
	;(v1: none kept - blank >= 50 compared as text, false)
	return inWorld.Length ? WalkMedian(inWorld) : vals.Length ? WalkMedian(vals) : (V1Ge(WkNavScaleAll, 50) && V1Le(WkNavScaleAll, 200)) ? WkNavScaleAll : ""
	}

;A zone's own scale (the arrow's distance per game unit) as kept - "" none, or one off 50-200: learned before v0.51.3 with the
;goal zones away, the arrow's number counting the other zones' legs too (3-87 in the file then: KT_Library 3.15, WC_Ravenwood
;4.59, WC_Hub 11.7); every zone worked out with the goal in it has been 100-103. Learned again there, with the goal in it
WalkNavOwnScale(zone)
	{
	osSc := (IsObject(WkNavZScales) && WkNavZScales.Has(zone)) ? WkNavZScales[zone] : ""
	return (osSc != "" && osSc >= 50 && osSc <= 200) ? osSc : ""
	}

;What was learned about the game's memory, from resources\nav_calibration.txt: WkNavSign (which way round its
;heading is - a first guess till it's checked; once it has been, it's steered by from the start) and the arrow's
;distance per game unit, for each zone and all of them (WkNavScale is the one in use)
WalkNavLoad()
	{
	global WkNavSign, WkNavChecked, WkNavZScales, WkNavScaleAll, WkNavScaleZone, WkNavFile, WkNavScale, WkNavSignSaved ; (v1 globals it sets)
	global WkNavTrusted, WkNavAgree ; (v1 globals it sets)
	WkNavSign := 1, WkNavChecked := 0, WkNavZScales := V1Obj(), WkNavScaleAll := "", WkNavScaleZone := ""
	dir := AqDir()
	WkNavFile := dir "\resources\nav_calibration.txt"
	Loop Read, WkNavFile
		{
		if (RegExMatch(A_LoopReadLine, "^\s*sign\s*:\s*(-?1)\s*(;.*)?$", &m))
			WkNavSign := m[1] + 0
		else if (RegExMatch(A_LoopReadLine, "^\s*checked\s*:\s*([01])\s*(;.*)?$", &m))
			WkNavChecked := m[1] + 0
		else if (RegExMatch(A_LoopReadLine, "^\s*scale\s*:\s*(\d+(?:\.\d+)?)\s*(;.*)?$", &m) && m[1] > 0)
			WkNavScaleAll := m[1] + 0
		else if (RegExMatch(A_LoopReadLine, "^\s*zone\s*:\s*(.+?)\s*\|\s*(\d+(?:\.\d+)?)\s*$", &m) && m[2] > 0)
			WkNavZScales[m[1]] := m[2] + 0
		}
	else  ; (v1: a file that isn't there - nothing read; v2 throws without the else)
		{
		}
	WkNavScale := WkNavScaleAll
	WkNavSignSaved := WkNavSign
	if (WkNavChecked)
		WkNavTrusted := 1, WkNavAgree := NavAgreeNeed
	}

WalkNavSave()
	{
	global WkNavSignSaved ; (v1 globals it sets)
	text := "; What Walker.ahk has learned about the game's memory (read-only). Delete this file to make it learn again.`n"
		. "; scale: the game's distance per unit of the distance printed on the quest arrow (the middle of the zones')`n"
		. "; sign: 1 or -1, which way round the memory's heading is compared with the arrow's`n"
		. "; checked: 1 once the sign has been checked (the arrow agreed, or a turn went the way it said)`n"
		. "; zone: a zone's own scale (zone|scale) - it differs from zone to zone`n"
		. (V1Gt(WkNavScaleAll, 0) ? "scale:" Round(WkNavScaleAll, 4) "`n" : "")
		. "sign:" WkNavSign "`n"
		. "checked:" (WkNavChecked ? 1 : 0) "`n"
	for zone, sc in WkNavZScales
		text .= "zone:" zone "|" Round(sc, 4) "`n"
	V1Do(FileDelete, WkNavFile ".tmp")
	V1Do(FileAppend, text, WkNavFile ".tmp", "`n")  ; (v1 wrote each `n as `r`n)
	V1Do(FileMove, WkNavFile ".tmp", WkNavFile, 1)
	WkNavSignSaved := WkNavSign
	}

;OnExit handler: never leave a movement key held down - nor the game sped up
WalkerQuit(reason := "", code := "", *)
	{
	local v1Keep := V1Thread() ; (v1: each thread had its own ErrorLevel)
	ReleaseKeys()
	SpeedSet(0, "the bot stops", true)
	return 0
	}
;Turning by the mouse while walking
#Include "%A_LineFile%\..\MouseSteer.ahk"

;(v2 port, CONVENTIONS.md "Blank start": v1 started every variable blank; v2 leaves it unset and throws on
;reading it. The entry script calls this first thing: this file's globals start blank, as in v1)
WalkerBlank()
	{
	global ArriveDist := "", TurnRate := "", AheadAngle := "", TurnInPlace := "", StuckTime := "", UnstickTries := "", UnreadLimit := ""
	global MinMatch := "", SpotTurnMem := "", ArcBlind := "", AheadMem := "", TurnRadius := "", WkWalkSpeed := "", WkWUpAt := "", WkMet := ""
	global WkMetAt := "", WkWalkSamples := "", WkPassMin := "", WkPassKey := "", WkPassAt := "", WkPromptVerb := "", WkCloseLook := ""
	global PlayForMe := "", WkFroTurns := "", WkFroUntil := "", WkFroHolds := "", WkFroStuck := "", NearDist := "", TalkMax := "", TalkGap := ""
	global PushTime := "", PushStraightDist := "", PushStraightTime := "", BackupTime := "", UnstickTurn := "", UnstickBias := "", BiasTime := ""
	global HiddenWalkTime := "", PushHiddenTime := "", LoadSpaceWait := "", LoadSpaceMax := "", GateDist := "", GateWait := "", SigilWait := ""
	global FastStuckTime := "", StillFrac := "", MemNear := "", MemAhead := "", TurnSettle := "", TransportWait := "", WkAcceptLook := ""
	global SpeedNow := "", SpeedSentAt := "", WkSpeedHold := "", SpeedSlowDist := "", SpeedSlowUnits := "", SpeedExitUnits := "", SpeedOff := ""
	global SpeedMiss := "", WkDlgEndAt := "", WkAcceptLooks := "", WkAcceptClicks := "", WkAcceptAt := "", WkGoalZones := "", WkKnownZones := ""
	global WkZonesFile := "", WkPromptDest := "", WkTransUsed := "", WkTransSeen := "", WkTransStep := "", WkTransStepAt := "", WkWaitWhat := ""
	global WkPromptUsed := "", WkZoneFrom := "", WkZoneAt := "", WkPressAt := "", DialogQuiet := "", WkQuietUntil := "", WkQuietLogged := ""
	global WkLoading := "", WkLoadedAt := "", SkipGap := "", WkDlgLook := "", CollectWait := "", RoamRadius := "", ChaseTime := "", CollectMax := ""
	global NoArrowNotify := "", WaitNotify := "", CollectStall := "", OnTopDist := "", ResetTeleport := "", ResetEvery := "", StuckForever := ""
	global WkResetAt := "", WkProgBest := "", WkProgAt := "", WkProgStep := "", WkNoteKind := "", WkNoteTitle := "", WkNoteHwnd := ""
	global WkNoteShown := "", WkNoteOff := "", WkNoArrowFrom := "", WkWaitFrom := "", WkLastX := "", WkEscTried := "", WkNoGuideFrom := ""
	global WkLastDist := "", WkLastDistAt := "", WkOnTop := "", WkOnTopAt := "", WkOnTopBacked := "", WkOnTopDone := "", WkStuckNearDone := ""
	global WkStuckTalk := "", WkTalkAt := "", WkCollect := "", WkGoalReadAt := "", WkArr1At := "", WkFoesAt := "", WkChaseFrom := ""
	global WkChaseSkipUntil := "", WkRoamLeg := "", WkRoamLegAt := "", WkRoamSide := "", Walking := "", HeldW := "", KeysDown := "", Refocus := ""
	global StatusText := "", StatusKind := "", StatusPrefix := "", WkFrontLook := "", WkBestDist := "", WkBestTime := "", WkLastRead := ""
	global WkSide := "", WkTries := "", WkNear := "", WkFar := "", WkArrived := "", WkTalk := "", WkPushUntil := "", WkSeenAt := "", WkHidden := ""
	global WkHiddenAt := "", WkBias := "", WkBiasUntil := "", WkPrevMovedH := "", WkLastBoxOff := "", WkLastMode := "", WkBackups := ""
	global WkBackupsFrom := "", WkDialog := "", WkPushes := "", WkPushStart := "", WkStraight := "", WkStraightAt := "", WkTalkDist := ""
	global WkArrDist := "", WkLoadAt := "", WkSpaceAt := "", WkGoneSpaces := "", WkGateAt := "", WkGateClicks := "", WkGateX := "", WkGateLook := ""
	global WkMapLook := ""
	global WkSigilUntil := "", WkFarAt := "", WkSigilSeen := "", WkSigilZones := "", WkSigilAt := "", WkSigilKey := "", WkSigilFromZone := ""
	global WkSigilTries := "", WkSnapPrev := "", WkSnapAt := "", WkTurnAt := "", WkWalkFrom := "", WkStill := "", WkMotion := "", WkMem := ""
	global WkMemFile := "", WkEsc := "", MovingStuckTime := "", MoveFrac := "", WkMoveLog := "", WkMoveZone := "", WkMovedAt := "", WkMoveNow := ""
	global WkMoveSeen := "", WkSpins := "", WkSpotTurn := "", inbattle := "", NavTurnTol := "", NavTurnCap := "", NavAgreeNeed := "", WkNavOk := ""
	global WkNavUse := "", WkNavH := "", WkNavD := "", WkNavHops := "", WkNavObj := "", WkNavSign := "", WkNavTrusted := "", WkNavAgree := ""
	global WkNavMirror := "", WkNavOdd := "", WkNavRest := "", WkNavRestKey := "", WkNavRel := "", WkNavByArrow := "", WkNavEscAt := ""
	global WkBackOutX := "", WkBackOutY := "", WkBackOutStill := "", WkBlindAt := "", WkBlindBackSaid := "", WkBlindMob := "", WkNavScale := ""
	global WkNavScales := "", WkNavScaleBad := "", WkNavState := "", WkNavPrev := "", WkNavTurns := "", WkNavTurnLog := "", WkNavFile := ""
	global WkNavSignSaved := "", NavWhy := "", WkNavChecked := "", WkNavZScales := "", WkNavScaleZone := "", WkNavScaleAll := "", WkStandIn := ""
	global NavRoute := "", WkNavRouted := "", WkNavLeft := "", WkRouteBest := "", WkRouteProg := "", WkRouteState := "", ArriveUnits := ""
	global PushUnits := "", WkAfterXLooked := "", WkGoalLine := "", WkGoalLineAt := "", WkGoalFrom := "", WkQmLooked := "", WkQmTalked := ""
	global WkPromptSkip := "", WkPreXText := "", WkNavJump := "", WkNavJumpAt := "", WkJumpKey := "", WkJumpStuck := "", WkJumpPushUntil := ""
	global WkNavMob := "", WkNavMobName := "", WkMobLogged := "", WkNavMobAt := "", WkRealSeenAt := "", WkArrowAtX := "", WkNavMirrorSaid := ""
	global WkNavDoor := "", ApproachUnits := "", TalkUnits := "", TalkReach := "", WkApTries := "", WkApOffUntil := "", WkGoalType := ""
	global WkGoalNpc := "", WkGoalId := "", WkTalkXs := "", WkTalkGoal := "", WkArrGoal := "", WkGoalIdWas := "", WkTalkNoted := "", WkGoalItem := ""
	global WkGoalCount := "", WkGoalTotal := "", WkGoalItemKey := "", WkGoalMobKey := "", WkGoalNpcFirst := "", WkGoalNpcLast := ""
	global WkNavNoPlace := "", WkNpN := "", WkNpGoal := "", WkNpAt := "", WkNavLast := "", WkNpTarget := "", WkArr1Key := "", WkArr1Look := ""
	global WkPromptText := ""
	;(v2-only - the stuck episodes counted and timed, a sigil that doesn't start)
	global WkSigilSpots := "", WkSigilXAt := "", WkSigilGoal := "", SigilFails := "", SigilFailsRelog := "", SigilRelogMs := "", SigilResetEvery := ""
	global WkLostOn := "", WkLostMs := "", WkLostAt := "", WkLostKind := "", WkLostWhy := "", WkLostTries := "", WkLostBad := ""
	global WkLostDist := "", WkLostLeft := "", WkLostZone := "", WkLostGoal := "", WkLostTryMs := "", WkLostEndAt := "", WkBadN := "", LostGap := ""
	}
