<p align="center"><img src="assets/avatar.png" width="180" alt="Wizard101 bots"></p>

https://github.com/Braehn/Wiz-Maxxing/releases

# Wizard101 Wiz-Maxxer Bot

Deisnged to play the game for you and Max wizards with very little necessary intervention.

Features:
   1. Walks and Talks, activates dialogs and spaces through them.
   2. Plays battles and learned the most efficient strategy per mobs vs bosses.
   3. Learns how you solve puzzles and saves them.
   4. Learns Dungeon Runs.
   5. Can communicate on a lan with 3 other clients and formulate plans and work together.
   6. Learns new cards and schools.
   7. Mass card editing and you can manually change how you want it to use those cards.
   8. Tons of settings for how you want it to operate.
   9. WIP: Has a 3d Mesh map of the environment read from the game's code for accurate pathing.
   10. Active Logging and statistic screen.
   11. Hotkey's tab

Setup:

1. Download the newest **Wiz-Maxxing-v#.#.#.zip**

2. Double-click **Setup.exe**. It shows what's there already and installs what's missing: first it copies the bot
   into your own Programs folder (`%LOCALAPPDATA%\Programs\Wiz-Maxxing` - no admin needed, updates keep working;
   over an earlier install there, its settings and learned cards are kept), then, from there, Python 3 and its
   numpy and Pillow packages (for the card matching), unblocks the downloaded files, and adds **Wiz-Maxxing** to the
   Start menu, the desktop, the Run box (Win+R) and your PATH. AutoHotkey v2 and Git are optional (only to change
   the bot or get updates with `git pull`). So is **Cheat Engine speedhack** (never ticked for you - risky: KingsIsle
   may notice): it installs Cheat Engine if it isn't there (its installer from cheatengine.org, opened for you to
   click through - decline the other programs it recommends) and puts the bot's script in Cheat Engine's autorun
   folder, so Cheat Engine attaches itself to Wizard101 and the bot's speed keys work with nothing set by hand.
   At the end it offers to move the download - the unzipped folder and the Wiz-Maxxing zip(s) beside it - to the
   Recycle Bin.
   The **Version** list at the top installs another version instead: any release on GitHub, newest first (no token
   needed). Install downloads it and puts it in, keeping your settings and learned cards. An older one than what's
   installed is asked about first, and its updating by itself is switched off so it stays; picking the latest again
   switches it back on. **alpha-v1** (the 2018 original, an AutoHotkey v1.1 script) and v0.02-v0.06 (from before the
   Wiz-Maxxing.exe launcher) are only downloaded and unpacked in your Downloads folder.
   
3. Start the bot from the Start menu (search "Wiz-Maxxing") or the desktop shortcut.
   If Windows says "Windows protected your PC", click **More info**, then **Run anyway**.

Updating:

Tick **GitHub updates** in Setup once per PC: it opens GitHub's token page (make a fine-grained token with
read-only **Contents** access to this repository - and **Issues: Read and write** for the dashboard's
**Report a bug**) and keeps the token in Windows Credential Manager. From then
on, opening **Wiz-Maxxing** checks for a newer release and asks before installing it - your PlayerStats.txt,
learned cards, potion routes and the bot's memory are kept. The bot's tray menu has **Check for updates** too.
