#Requires AutoHotkey v2.0
;(v1's #InstallMouseHook / #InstallKeybdHook: both hooks from the start)
V1Start() ; (v2 port: v1 started every variable blank - CONVENTIONS.md "Blank start")
InstallMouseHook()
InstallKeybdHook()
;(v1's default sending mode was Event - v2's is Input, which moves the mouse at once (MouseMove's speed ignored) and
;sends with no key or click delays)
SendMode("Event")
;
;PetTrainer.ahk - the old blind pet trainer (README.txt): Win+1 by the Pet Pavilion's sigil plays the dance game over and
;over with fixed clicks and RANDOM W/A/S/D presses (not the moves the game shows - most rounds fail), no reading of the
;game at all: no level or energy check, no look at what's on screen. Win+1 works only with Wizard101 the window in front,
;and stops as soon as it isn't (v1.14.7 - the keys and clicks went to whatever was: x, clicks and 600 random w/a/s/d
;typed into another program, the mouse locked; Windows' own Win+1 is left alone elsewhere). Esc closes it. Kept as it
;is otherwise till AutoFarmer's own pet trainer replaces it (TODO.md goal 6 - by the game's memory: vision\petmem.py
;reads the pets now; the pet game's windows have to be seen first).
;KNOWN, NOT FIXED BLIND (no game here to check against): the clicks below are an 800x600 window's spots plus offsets that
;centre an 800x600 area on the SCREEN, while CoordMode is Window - so they assume the game window fills the screen from
;its top left (full screen, or borderless at the screen's size: at 1920x1080 the click meant for (625, 470) lands at
;(1185, 710), that centred area's spot - the original design) with the game's dialogs laid out as that centred 800x600
;area. A smaller window, or one moved off the top left (an 800x600 window on a bigger screen: (1185, 710) is outside it),
;is missed; and whether the dialogs keep to that centred area at every resolution (the game's UI may scale) isn't known.
;To check in the game before any click is moved: where each click lands with your window.

#HotIf WinActive("ahk_exe WizardGraphicalClient.exe")
#1::
{
global ; (v1: a hotkey label - global scope)

;Screen Varibles
CoordMode("Mouse", "Window")
leftoffset := (A_ScreenWidth - 800) / 2
topoffset := (A_ScreenHeight - 600) / 2

;Rng Varibles
up := 1
left := 2
right := 3
down := 4

;Mouse timings
Mousespeedfast := 5 ;Default is 5
Mousespeedslow := 10 ;Default is 10

;Sleep Timings
Loading := 5100 ;Default is 5000
Wait := 325 ;Default is 300
Delay := 175 ;Default is 150
BufferVar := 10 ;Default is 10

Loop{
  ;(Wizard101 not in front any more - you switched away: the trainer stops, your mouse let go; Win+1 there again goes on)
  if (PetGameGone())
    return
  BlockInput("SendAndMouse")
  BlockInput("MouseMove")
  Sleep(Wait)
  if (PetGameGone())
    return
  Send("x")
  Sleep(Wait)
  if (PetGameGone())
    return
  Send("x")
  Sleep(Wait)
  if (PetGameGone())
    return
  MouseMove(625 + leftoffset, 470 + topoffset, Mousespeedfast)
  Click()
  Sleep(Wait)
  if (PetGameGone())
    return
  MouseMove(615 + leftoffset, 575 + topoffset, Mousespeedfast)
  Click()
  Sleep(BufferVar)
  MouseMove(A_ScreenWidth/2, A_ScreenHeight/2, Mousespeedfast)
  BlockInput("SendAndMouse")
  BlockInput("Mousemove")
  Sleep(Loading)
  Loop 600
  {
    if (PetGameGone())
      return
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
    ;(v1: "sleep, %Loading% - 1500" was an expression whose %Loading% read the variable named "5100" - a blank one:
    ;blank - 1500 is blank, a sleep of 0 - checked with v1.1. Kept: no wait here)
    Sleep(0)
  if (PetGameGone())
    return
  MouseMove(610 + leftoffset, 575 + topoffset, Mousespeedfast)
  Sleep(Delay)
  if (PetGameGone())
    return
  Click()
  Sleep(Delay)
  if (PetGameGone())
    return
  MouseMove(170 + leftoffset, 470 + topoffset, Mousespeedfast)
  Click()
  Sleep(Delay)
  if (PetGameGone())
    return
  MouseMove(615 + leftoffset, 575 + topoffset, Mousespeedfast)
  Click()
  Sleep(Wait)
  if (PetGameGone())
    return
  MouseMove(635 + leftoffset, 540 + topoffset, Mousespeedfast)
  Click()
  Sleep(Delay)
  if (PetGameGone())
    return
  MouseMove(180 + leftoffset, 570 + topoffset, Mousespeedfast)
  Click()
  MouseMove(A_ScreenWidth/2, A_ScreenHeight/2, Mousespeedslow)
  ;Your mouse let go while the next round loads (v1.0.0 - it was BlockInput("Off") after the wait, which doesn't end the
  ;MouseMove mode: your mouse stayed frozen for as long as the script ran). Each round locks it again at its start
  BlockInput("MouseMoveOff")
  BlockInput("Default")
  BlockInput("Off")
  Sleep(Loading)
}
}
#HotIf

;Whether Wizard101 isn't the window in front any more: then your mouse let go first (the round's lock ended) - the
;trainer's round stops there (Win+1 with the game in front starts it again)
PetGameGone()
{
if (WinActive("ahk_exe WizardGraphicalClient.exe"))
  return false
BlockInput("MouseMoveOff")
BlockInput("Default")
BlockInput("Off")
return true
}

;Esc closes the trainer, as README.txt says (v1.0.0 - it was Esc::Reload, which restarted it instead): your mouse let go
;first. This Esc isn't passed on to the game (the press that stops the trainer doesn't also close a game window); once
;closed, Esc is the game's again
Esc::
{
BlockInput("MouseMoveOff")
BlockInput("Default")
BlockInput("Off")
ExitApp()
}
#Include %A_ScriptDir%\..\V1Compat.ahk ; (v2 port: the v1 behaviours it keeps)