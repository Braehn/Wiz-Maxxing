"""battlerec.py - the battle recorder of the vision helper: every battle (the ones you play too) written down from the
game's own log and memory, so the bot can learn battles later (TODO goal 3, step 1).

    rec = battlerec.start(root=ROOT, nav=nav_reader, log=log, gate=GATE)      (vision.py main(), after placements)

WHERE IT COMES FROM
  * The game's log (Bin\\WizardClient.log): every caster's spell, its targets, damage, crits, wards / traps, hanging
    effects, health changes, passes, misses, deaths and the result. Tailed here (short opens 500 ms apart, read only -
    Python's open shares read and write: the game keeps writing). A line is used only when it matches one of the
    patterns below; raw lines are never kept (the log may hold chat).
  * The game's memory (read only, navmem's reader): the hand (template ids, enchantments, treasure / item cards), my pips,
    the enemies' rank, title, school, boss flag and max health, the deck. Mostly COPIED from answers the bot already got
    (the /cards and /battle hooks in vision.py - no new read), plus a few own reads only when the bot can't be reading:
    a round the bot doesn't play (bot off / you playing), a battle's first PrePlanning (the deck's signature, navmem's
    cached mob infos - no read) and out of battle (the deck).
  * The bot (AutoFarmer\\BattleRec.ahk): its round's DebugLog lines (the reasons, verbatim) posted once, fire-and-forget,
    after the round's last click (POST /rec?ev=round), and its state (hello / who).

NEVER SLOWS A ROUND. The request threads only put what they already have on a queue (microseconds). This thread does the
rest; while a gated request (a memory read the bot or walker waits on) is in flight it stops within 10 log lines and
sleeps until the request is over; it writes files and makes own reads only when nothing gated ran for 100 ms; it never
reads memory in a planning phase the bot plays. FAILS SOFT: every hook is wrapped (vision.py _rec_hook); an item that
can't be used is dropped and counted; an unexpected error in this thread is written to vision.log once and the recorder
switches itself off till the next hello - the helper and the bot go on as they were.

=====================================================================================================================
THE FORMAT (schema "wizmaxx-battles", version 1) - this docstring is its source of truth
=====================================================================================================================
Files (under AutoFarmer\\learned\\battles\\ - kept by updates, never sent anywhere):
  YYYY-MM\\YYYY-MM-DD.jsonl     the battles started that day (by t0); -2, -3 ... after a day file reached 32 MB
  YYYY-MM.jsonl.gz             months before the last two (each day file one gzip member; read back, then removed)
  cards.jsonl                  card facts by template id (the last line per tid wins)
  current.json                 the battle in progress (checkpoint after each round; tmp + os.replace)
  today.txt                    date|battles|won|lost|fled|bytes|last|why (one line; the dashboard's "recorded today")
  Over CAP_MB (1 GB): months gzipped (all but the current one); still over: recording pauses (today.txt why "paused:
  learned\\battles is full - move old months away"). Nothing is deleted but a .jsonl whose gzip copy was read back.

Lines: JSON Lines, UTF-8 (ASCII: non-ASCII as \\uXXXX), no BOM, "\\n" ends, one object a line, written in one os.write
(a leading "\\n" first when the file doesn't end with one: a torn line from a crash stays on its own line). Readers skip
a line that doesn't parse and a "rec" they don't know, and check "v" line by line.
  {"rec":"header","v":1,"format":"wizmaxx-battles","doc":"AutoFarmer\\\\vision\\\\battlerec.py","made":"...","bot":"v1.3.0"}
      the first line of every .jsonl
  {"rec":"battle",...}         one battle (below)
  {"rec":"card",...}           one spell template's facts (cards.jsonl)

Rules for every field: null = unknown / not read / not readable (each section's "why" or "src" says which); an absent
key = doesn't apply, or this version / phase doesn't write it; [] = read and empty; 0 / "" = a real "none"
(enchantment 0 = none). 64-bit ids (gids, the Duel ID) are decimal STRINGS; template ids (u32) and the log's short ids
are numbers. t* fields: local wall clock "YYYY-MM-DD HH:MM:SS" from the log's own stamps (1 s). *_s fields: seconds (1
decimal) by GetTickCount64 ticks (the helper's; AHK's A_TickCount is the same clock). Health in HP. Effect params are
the game's integers (35 = 35 %). Stat floats the game's own (sDamage 29.999998 = +30 %). A new optional field keeps v;
a changed meaning or a removed field raises v.

A battle (rec "battle"):
  rec, v          "battle", 1
  id              "YYYYMMDD-HHMMSS-<duel>" - t0 + the duel number; unique
  duel            the log's short duel number ("Duel 7445553"), int
  duel_gid        the 64-bit Duel ID (ResolveCombatRound "Duel ID:", or HandleEnterCombat "combatGid:"), str - the
                  same in every party member's log: records of one battle on several PCs join by it; null none seen
  t0 / t1         the duel's first line / its end (EndDuel, or its last line); t1 null: cut
  dur_s           t1 - t0 (by ticks when seen whole, else by the stamps)
  build           the game's build ("6A9721E9-370E000", navmem), null not attached
  bot_ver         the bot's version (hello), null no hello
  char            CharID (the log's MSG_LoginComplete, else the bot's state), str
  zone            the zone (the log's last ConnectComplete before t0)
  enter           [x, y, z] where the wizard entered the circle (game units)
  result          won / lost / fled / left / cut / unknown:
                    fled  MSG_CombatFlee in the round, then MSG_CombatRemove(Local Player)
                    lost  MSG_CombatRemove(Local Player) with no flee in that round
                    won   the Victory phase or MSG_CombatMatchResult(0), and every enemy dead or removed
                    left  the log restarted (the game closed), or the duel's lines stopped for 15 min with no game
                    cut   the helper stopped mid-battle and the duel isn't in the current log
                    unknown  anything else (match_result kept raw)
  match_result    raw MSG_CombatMatchResult(n) (0 on a win), null not seen
  rounds_n        the game's last Round:N (0 none resolved)
  pvp             GetCritParams a_isPvP (bool), null not seen
  me              {sc, pid, gid, name, school, level, crit_rating, hp0, max0, hp1, died_round, killed_by, role}
                    sc my subcircle (4-7: cast order); pid / gid my log short id / 64-bit gid; name my wizard's (the
                    log's slot name when I'm the only wizard on my side, else the bot's own - never a typed one);
                    school: the hand's (memory) > the bot's hitschool > resources\\characters.txt; level, crit_rating:
                    GetCritParams (the local player's own); hp0 / max0 at the start (the first hand read > the log);
                    hp1 at the end; died_round / killed_by {sc, spell, dmg} when my health hit 0; role (hitter / blader /
                    healer) the first bot round's
  party           {on, size, role_set, roles, dual, mode}: on = more than one wizard on my side; size wizards on my side;
                  role_set the bot's party battle role set (hitter / blader / healer - null no state); roles {round:
                  role} of the bot's rounds; dual: dual mode; mode the party mode (off / leader / follower)
  parts           every participant, by sc: {sc, side (enemy / me / ally), team, pid, gid, obj, name | name_h, player,
                  template_id, title, rank, rank_src, school, school2, boss, minion, kind, hp0, max, max_src, ai, joined,
                  out_round, out, died_round, killed_by}
                    sc 0-3 enemies, 4-7 my side; team the log's (mine 0); obj the template's object name
                    (MSG_CombatAdd(CL_MorgantineGhost-Blue-R9), null for a wizard); name the shown name - a wizard not
                    mine (not in the bot's own party) only as name_h = the first 10 hex of sha1(name); title / rank /
                    school / school2 / boss / minion / kind from memory (the bot's /battle, navmem's cached mob info),
                    rank from obj's "-R<n>" with rank_src "obj" when memory has none; hp0 / max / max_src ("mem" or
                    "log" - the log has no max: its first health; mine the health globe's max, me.max0); ai
                    {intelligence, selfish, aggressive, max_shadow_pips}; joined the round it joined; out_round / out
                    (dead / removed / fled) when and how it left; died_round / killed_by (the caster's sc) when its
                    health hit 0
  rounds          one per game round:
                    n          the game's round (Round:N; with no cast line, the count of Planning phases)
                    t_plan     the Planning phase's stamp
                    plan_s / exec_s   Planning to Execution / Execution to Resolution (the animations)
                    timer      MSG_SetPlanningPhaseTimer (30)
                    moves      [[move, s since Planning]] - mine (MSG_CombatMoveSelection(Local Player, X))
                    who        bot / user / none (nothing chosen) / unknown:
                                 a bot post, its rule not user / botoff / unknown-school, not "again" -> bot;
                                 no spell of mine (Spell:None / no line) -> none; a bot post (rule user / botoff /
                                 unknown-school, or again) -> user; no post and the bot off or you playing -> user;
                                 else unknown
                    hand       the hand at the round's first settled read, left to right, or null (hand_why says why):
                               [{i, slot, tid, name, kind, school, pips, x, sp, sh, ench, en, ve, tc, item, pet, ok, ov}]
                                 i position (0 = leftmost); slot Card1-7 / PetCard; tid template id; name the spell's
                                 m_name; kind the bot's (damage aoe heal ward blade trap aura bubble weakness enchant dot
                                 stun dispel prism clear polymorph keep...); school; pips; x an X-pip spell; sp school
                                 pips {"fire":1}; sh shadow pips; ench / en / ve the enchantment's template id (0 none),
                                 name, the value with it; tc / item / pet treasure, item, the pet's card; ok castable
                                 (an estimate, null unknown); ov param overrides [[effect index, value]] (absent none)
                    hand_src   "bot" (copied from a /cards answer) / "rec" (the recorder's own read: a round the bot
                               didn't play)
                    hand_s     when it was read, s after Planning
                    hand_last  the last settled hand before the cast, when it differs (discards, Draw, an enchant on)
                    pips       mine at the hand read {generic, power, balance, death, fire, ice, life, myth, storm,
                               shadow}; else pips_log [pips, power] from the log (school pips left out there)
                    hp / max   mine at the hand read (memory), else the log's
                    start      [[sc, hp, pips, ppips]] everyone at Execution (the log's Participant lines)
                    played     mine: {spell, tid, hand_i, ench, tc, item, targets [sc], pass, missed, by} (my first
                               non-pet cast, matched to the hand by name, then display - the first of equal cards,
                               noted when ambiguous), null nothing cast
                    bot        the bot's round, null it didn't play it: {rule, rule_v, plan, casts, lines, seen_s,
                               lock_s, flags, role, hitschool, botround, blround, dropped}
                                 rule what decided it (RULES below): kill defend heal party-heal party-shield flee
                                 planner boostmax-hit learned-hit trap blade aura bubble hit tower reshuffle pass failed user
                                 botoff unknown-school learnall other; rule_v the classifier's version (lines are kept:
                                 old records can be classified again); plan the text after "plan: "; casts the bot's
                                 titles that went out ("@cast" lines); lines [[ms since the round opened, text]] every
                                 DebugLog line of the round (120 at most, 400 chars each; a line with http, webhook,
                                 token, password or login is "(line left out)"); seen_s Planning (helper tick) to the
                                 bot's round start (AHK tick); lock_s "(locked N s)"; flags {bot, acting, took, left,
                                 again, pfm} at the round's end; role, hitschool; botround / blround the bot's round
                                 numbers (a mismatch with n goes to notes); dropped lines over the cap; and when the
                                 bot sent them: prole / brole (its party mode, battle role set), myslot (its plate's
                                 slot on my side), hslot / hschool (the hitter's - a party's support), pips (PipsNow)
                    casts      every caster's action in order: {sc, spell, pet, pass, missed, dead, pips, rebal, res,
                               fx, crit, wards, hang, aura, removed, hp, crit_p} (absent = not in the log)
                                 spell the log's name (template m_name), null Spell:None; pet a second line of the same
                                 caster in a round; pips [cost, shadow, cur, cur_power]; rebal [dmg, mult] (StatRebalance
                                 as caster); res [[t, resist, mult]] (as target); fx [[t, effect, param]]
                                 (ProcessTargets); crit [[cur, mult, blocked, new]]; wards [[c, t, effect, param]] (the
                                 param after the ward / trap); hang [[t, effect, charm 1/0, param]]; aura [[t, effect,
                                 param]]; removed [[t, effect, param, how charm/ward/dot/type]]; hp [[sc, before,
                                 delta]] (ModifyHealth); crit_p [rating, level, target_level, final]
                    hp_end     {sc: hp} everyone's health after the round
                    died       [sc] who hit 0 this round
                    fx         effects outside any cast {hang, aura, removed, hp} (DoT ticks, auras at the round's start)
                    mem        Phase B memory snapshot after the round (absent until LIVE-1..4,6 pass)
  deck            {src "mem" | null, at, age_s, sig_ok, gid, object, display, school, set, limits {max_spells,
                  max_treasure, generic_max_copies, school_max_copies, generic_max_rank, school_max_rank,
                  max_archmastery}, main [[tid, n, ench]], tc [[tid, n, ench]], items [[tid, n, from]], excl [[tid, n]],
                  main_n, tc_n, item_n, why, belief {id, school, set, why, eqset}} - the equipped deck (deckmem), read
                  out of battle; at its read time, age_s its age at t0; sig_ok the worn deck's signature checked at this
                  battle's first PrePlanning matched; belief what the bot thinks is on (Decks.ahk DeckNow's id, school
                  and Equipment Set, DeckWhy, dashboard.ini's eqset - never the name typed for it)
  stats           {bot {school, damage, pierce, critical, accuracy, block, maxhealth, charid_ok} - the bot's own Stat()
                  numbers, copied (null: the bot's Stats had none); log {sdamage, dmg_mult, resist, res_mult,
                  crit_rating, level, target_levels, final_crit} - my first StatRebalance as caster / as target and
                  GetCritParams}; mem (Phase B)
  settings        {k: v} the effective Stat(k) of a whitelist (the deck keys + enemyspells, defendat, healat,
                  learnedhits, roundwait, partybattle, navmem, handsoff, handsoffon, planner, memclicks, deckzone,
                  partyhitround, partyorders; null: not set) - never anything typed
  who             {bot: [n..], user: [..], none: [..], unknown: [..]}
  src             {log, mem, ahk, hands "k/n", deck, phase_b [groups on]} what fed the record
  partial         {from_round, why}: rounds before from_round lack memory or bot data (a helper restart, the log
                  skipped), null a whole record
  notes           [str] things worth knowing ([] none)

A card (cards.jsonl, rec "card"): {rec, v, tid, name, display, school, type, kind, pips, x, sh, sp, value, dot, heads,
boosts, text, acc, tc_tpl, full, seen} - full false when only the deck's brief is known (no effects; a later full line
wins); seen the first date seen. One line per new template id (a hand or deck read showing a tid not in the file).

THE BOT'S POSTS (BattleRec.ahk -> POST /rec?ev=<round|hello|who|state>, Content-Type text/plain; charset=us-ascii):
  the body: "key<TAB>value" lines, then "L<TAB><ms><TAB><escaped line>" lines; escaped: \\\\ \\t \\n \\uXXXX (ASCII only)
  ev=round   duel (BlDuel), round (BlRound+1 - the record's blround), botround (roundnumber), open / close
             (A_TickCount: GetTickCount64), again, bot, acting, took, left, pfm, role (BattleRole), hitschool, drop,
             prole / brole (party mode / battle role set), myslot, hslot, hschool (the hitter's), pips (PipsNow) + the
             state on a duel's first round post + the L lines ("@cast <title>" for a cast that went out)
  ev=hello   on (battlerec 1/0), log (RcLog), ver, navmem (1/0), dual (1/0), bot, acting, pfm, tk + the state fields
  ev=who     bot, acting, pfm, tk (in the query; also as GET /rec?ev=who&...)
  ev=state   (why=end: out of battle after each battle) the hello's keys and the state fields: char, school, name,
             stat.<school|damage|pierce|critical|accuracy|block|maxhealth|charid_ok>, set.<setting key>, deck.id,
             deck.school, deck.set, deck.why, deck.eqset, party.mode, party.role_set, party.own (my own party's
             wizards' names, "|" between) - a key the helper doesn't know is skipped; settings only from SETTINGS_KEYS
"""
import collections
import ctypes
import gzip
import hashlib
import json
import os
import queue
import re
import threading
import time
import traceback

SCHEMA = "wizmaxx-battles"
V = 1
RULE_V = 3                   # (2: the planner rule - v1.0.0; 3: "Plan:" lines never match a rule - partyorders)
# Phase B groups switched on (each needs its live probe item first - SPEC 8): "snapshot" (LIVE-1..4, 6: a memory
# snapshot of every participant after each round), "wizstats" (LIVE-5: WizGameStats at the battle's first PrePlanning).
# None yet: their fields are not written.
PHASE_B = frozenset()

TAIL_S = 0.5                 # the log looked at this often
READ_MAX = 1 << 20           # at most this much read a look
BEHIND_MAX = 4 << 20         # further behind: jump to the end minus this (the open duel marked partial)
BACKSCAN = 8 << 20           # the first start looks this far back for the zone, the CharID and a duel in progress
DAY_MAX = 32 << 20           # a day file this big: the next goes to -2
CAP_MB = 1024                # learned\battles over this: months zipped, then paused
QUEUE_MAX = 64
POST_WAIT_MS = 10000         # a bot post waits this long for its round in the log
LINES_CAP, LINE_CAP, BODY_CAP = 120, 400, 64 * 1024
OUT_GRACE_MS = 20000         # after MSG_CombatRemove(Local Player): the duel closes this long after its last line
SILENT_MS = 900000           # a duel with no line for 15 min is closed
IN_PROGRESS_S = 180          # (back-scan) a duel whose last phase line is this near the log's last stamp
HAND_PRE_MS, HAND_POST_MS = 600, 300
POST_PRE_MS, POST_POST_MS = 600, 3000
OWN_FIRST_MS, OWN_EVERY_MS, OWN_TRIES = 800, 300, 10
DECK_SIG_MS, DECK_AFTER_MS, OUT_IDLE_MS = 10000, 3000, 5000
DECK_READ_S = 2.0            # an own deck read gives way after this long (the log not looked at meanwhile) - or at once
                             # when the bot's /cards or /battle reads a battle; read again 3 s later (it goes on)
WRITE_TRIES = 3
MAINTAIN_MS = 3600000
LIVE_S = 3.0                 # a line this fresh (its stamp against the wall clock) was seen live
SETTINGS_KEYS = ("cardlogic", "boostmax", "useblades", "usetraps", "usebubble", "useaura", "usewand", "usetower",
                 "usereshuffle", "reboost", "solotraps", "healthocr", "killmargin", "drawenchant", "pipsave",
                 "discardunused", "discardmax", "discardspent", "discardunaffordable", "healat", "defendat", "fleeon",
                 "usehit1", "usehit2", "usehit3", "usehit4", "useheal", "enemyspells", "learnedhits", "roundwait",
                 "partybattle", "navmem", "handsoff", "handsoffon", "planner", "memclicks", "deckzone", "partyhitround",
                 "partyorders")
STAT_KEYS = ("school", "damage", "pierce", "critical", "accuracy", "block", "maxhealth", "charid_ok")
PIP_KINDS = ("generic", "power", "balance", "death", "fire", "ice", "life", "myth", "storm", "shadow")
BAD_WORDS = re.compile(r"http|webhook|token|password|login", re.I)
TEMPLATE_RX = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_.\-]*[-_][A-Za-z0-9_.\-]*$")
RANK_RX = re.compile(r"-R(\d{1,3})$")


# ============================================================================ time
def _gtc64():
    try:
        f = ctypes.windll.kernel32.GetTickCount64
        f.restype = ctypes.c_uint64
        f()
        return f
    except Exception:  # noqa: BLE001 - not Windows: the monotonic clock
        return lambda: int(time.monotonic() * 1000)


class Clock:
    """GetTickCount64 ms (AHK's A_TickCount is the same clock) and the wall clock (s) - a test passes its own"""
    _f = None

    def tk(self):
        if Clock._f is None:
            Clock._f = _gtc64()
        return int(Clock._f())

    def wall(self):
        return time.time()


_STAMPS = {}


def stamp_of(line):
    """the log line's "MM/DD/YY HH:MM:SS" as ("YYYY-MM-DD HH:MM:SS", epoch s) - (None, None) no stamp"""
    s = line[:17]
    hit = _STAMPS.get(s)
    if hit is not None:
        return hit
    try:
        if s[2] != "/" or s[5] != "/" or s[8] != " " or s[11] != ":" or s[14] != ":":
            return None, None
        mo, d, y, hh, mm, ss = int(s[0:2]), int(s[3:5]), int(s[6:8]), int(s[9:11]), int(s[12:14]), int(s[15:17])
        st = "20%02d-%02d-%02d %02d:%02d:%02d" % (y, mo, d, hh, mm, ss)
        w = time.mktime((2000 + y, mo, d, hh, mm, ss, 0, 0, -1))
    except (ValueError, IndexError, OverflowError):
        return None, None
    if len(_STAMPS) > 4096:
        _STAMPS.clear()
    _STAMPS[s] = (st, w)
    return st, w


def wall_of(stamp):
    try:
        return time.mktime(time.strptime(stamp, "%Y-%m-%d %H:%M:%S"))
    except (ValueError, TypeError, OverflowError):
        return None


def secs(a, b):
    return round((b - a) / 1000.0, 1) if a is not None and b is not None else None


def num(s):
    """'536.000000' -> 536, '29.999998' -> 29.999998"""
    v = float(s)
    return int(v) if v.is_integer() and abs(v) < 1e15 else v


def name_h(name):
    return hashlib.sha1((name or "").encode("utf-8")).hexdigest()[:10]


# ============================================================================ the game log's lines
# (anchors first - one C-level search a line on its bytes; then the line's message - after "[TAG] Category " - is
# matched at its start: a pattern typed into chat further on in a line never counts)
ANCHORS = [b"MSG_Combat", b"MSG_SetPlanningPhaseTimer", b"MSG_EndDuel received", b"Entering Combat at",
           b"AddNewParticipant player:", b"My SubCircle:", b"Added participant ", b"Subcircle ", b"CombatantDataControl",
           b"Participant: ID ", b"ResolveCombatRound.", b"{IsSim:", b"ProcessTargets.", b"ProcessWards.",
           b"AddHangingEffect.", b"AddAuraEffect.", b"REMOVED", b"ProcessCriticalHitEffect.", b"StatRebalance.",
           b"ModifyHealth called", b"GetCritParams.", b"Updating health globe", b"ConnectComplete destination Zone=",
           b"MSG_LoginComplete CharID:", b"combatGid:", b"Player's Duel"]
ANY = re.compile(b"|".join(re.escape(a) for a in ANCHORS))
HEAD = re.compile(r"\d\d/\d\d/\d\d \d\d:\d\d:\d\d \[\w+\] (\S+) +")
REPEAT = re.compile(r"\| \(x(\d+)\)\s*$")
DUEL_N = re.compile(r"Duel (\d+): ")
_P = lambda s: re.compile(s)   # noqa: E731
PAT = {
    "add": _P(r"Duel (\d+): MSG_CombatAdd\((.+?)\)"),
    "phase": _P(r"Duel (\d+): MSG_CombatPhase\((kPhase_\w+)\)"),
    "move": _P(r"Duel (\d+): MSG_CombatMoveSelection\((.+?), (.+?)\)"),
    "remove": _P(r"Duel (\d+): MSG_CombatRemove\((.+?)\)"),
    "result": _P(r"Duel (\d+): MSG_CombatMatchResult\((-?\d+)\)"),
    "flee": _P(r"(?:Duel (\d+): )?(?:\w+::)?MSG_CombatFlee"),
    "timer": _P(r"Duel (\d+): MSG_SetPlanningPhaseTimer\((\d+)\)"),
    "end": _P(r"Duel (\d+): MSG_EndDuel received(?:: and we were (NOT )?a part of it)?"),
    "enter": _P(r"Duel (\d+): Local Player Entering Combat at \(([-\d.]+), ([-\d.]+), ([-\d.]+)\)"),
    "side": _P(r"Duel (\d+): CombatPlanningPhaseWindow::HandleCombatPhase\(kPhase_\w+, (Local|Other) Player's Duel\)"),
    "gid": _P(r"(?:\w+ )?AddNewParticipant player:(\d+)"),
    "sub": _P(r"My SubCircle: (\d+), OtherPart's SubCircle: (\d+)"),
    "pid": _P(r"Added participant (\d+) to duel (\d+)"),
    "slot": _P(r"Subcircle (\d+)\s*$"),
    "name": _P(r"CombatantDataControl(?:Small)?, name:(.*?)\s*$"),
    "part": _P(r"Participant: ID (\d+), Team (\d+), Health (-?\d+) Pips (\d+) PPips (\d+)"),
    "cast": _P(r"(?:\w+::)?ResolveCombatRound\. Duel ID:(\d+) Round:(\d+) Caster:(\d+) Spell:(.*?)\s*$"),
    "pass": _P(r"\{IsSim:0\} Participant \(sc (\d+)\) chose to pass\."),
    "missed": _P(r"\{IsSim:0\} Participant \(id (\d+)\) missed"),
    "dead": _P(r"\{IsSim:0\} Participant \(sc (\d+)\) is dead after DoTs"),
    "pips": _P(r"\{IsSim:0\} Processing spell pips - ID\((\d+)\) rank\((\d+)\) shadowRank\((\d+)\) curPips\((\d+)\) "
               r"curPowerPips\((\d+)\)"),
    "target": _P(r"(?:\w+::)?ProcessTargets\. Caster:(\d+) Target:(\d+) Effect:(\w+) Param:(-?\d+)"),
    "ward": _P(r"(?:\w+::)?ProcessWards\. Caster:(\d+) Target:(\d+) Effect:(\w+) Param:(-?\d+)"),
    "hang": _P(r"(?:\w+::)?AddHangingEffect\. Target:(\d+) Effect:(\w+) Charm:(\w+) Param:(-?\d+)"),
    "aura": _P(r"(?:\w+::)?AddAuraEffect\. Target:(\d+) Effect:(\w+) Param:(-?\d+)"),
    # (not seen in a log yet - from the game's strings: searched in the line's message)
    "removed": _P(r"(RemoveCharm|RemoveWard|RemoveOverTime)ByDisposition\. REMOVED Target:(\d+) Effect:(\w+) Param:(-?\d+)"),
    "removedt": _P(r"RemoveHangingEffectByType\. hmg\. REMOVED Target:(\d+) Effect:(\w+) Param:(-?\d+)"),
    "crit": _P(r"(?:\w+::)?ProcessCriticalHitEffect\. curEffectParam:([\d.]+)\s+Crit\.Mult:([\d.]+) Crit\.Blocked:(\d) "
               r"newEffectParam:(-?\d+)"),
    "rebal": _P(r"StatRebalance\. (Caster|Target) SC\[(\d+)\] (\w+)\[([-\d.]+)\].*sAppliedMultiplier = ([\d.]+)"),
    "hp": _P(r"(?:\w+::)?ModifyHealth called OwnerID:(\d+), m_playerHealth:(-?\d+), a_deltaHealth:(-?\d+)"),
    "critp": _P(r"GetCritParams\. attackerCrit:([\d.]+) attackerLevel:(\d+) .*targetLevel:(\d+)"),
    "critf": _P(r"GetCritParams\. finalCrit:([\d.]+)"),
    "pvp": _P(r"GetCritParams\. .*a_isPvP:(YES|NO)"),
    "globe": _P(r"(MSG_CombatHealth|HandleEnterCombat|MSG_UpdateHealth): Updating health globe \(new health: (-?\d+), "
                r"new health max: (\d+)\)"),
    "zone": _P(r"(?:\w+::)?ConnectComplete destination Zone=(\S+)"),
    "char": _P(r"(?:\w+::)?MSG_LoginComplete CharID:(\d+)"),
    "cgid": _P(r"(?:\w+::)?HandleEnterCombat\(\) combatGid:(\d+)"),
}
BY_ANCHOR = {
    b"MSG_Combat": ("add", "phase", "move", "remove", "result", "flee", "globe"),
    b"MSG_SetPlanningPhaseTimer": ("timer",), b"MSG_EndDuel received": ("end",), b"Entering Combat at": ("enter",),
    b"AddNewParticipant player:": ("gid",), b"My SubCircle:": ("sub",), b"Added participant ": ("pid",),
    b"Subcircle ": ("slot",), b"CombatantDataControl": ("name",), b"Participant: ID ": ("part",),
    b"ResolveCombatRound.": ("cast",), b"{IsSim:": ("pass", "missed", "dead", "pips"), b"ProcessTargets.": ("target",),
    b"ProcessWards.": ("ward",), b"AddHangingEffect.": ("hang",), b"AddAuraEffect.": ("aura",),
    b"REMOVED": ("removed", "removedt"), b"ProcessCriticalHitEffect.": ("crit",), b"StatRebalance.": ("rebal",),
    b"ModifyHealth called": ("hp",), b"GetCritParams.": ("critp", "critf", "pvp"), b"Updating health globe": ("globe",),
    b"ConnectComplete destination Zone=": ("zone",), b"MSG_LoginComplete CharID:": ("char",), b"combatGid:": ("cgid",),
    b"Player's Duel": ("side",),
}
SEARCHED = {"removed", "removedt", "pvp"}
REPEATABLE = {"target", "ward", "hang", "aura", "removed", "removedt", "crit", "hp"}
DUEL_KINDS = {"add", "phase", "move", "remove", "result", "timer", "end", "enter", "side"}
OPENS = {"add", "phase", "move", "timer", "enter", "side"}
# (the planning window's and the health globe's lines are the local player's own: they go to my duel)
MINE_ONLY = {"slot", "name", "globe", "critp", "critf", "pvp", "flee"}
# Each kind only from the game's logger that writes it (its "Category" - the same in every copied log, 2026-10-23..27):
# a chat line, or anything else written like one, never counts. (removed / flee: not seen yet - a wider set)
_DUELCAT = frozenset({"ClientDuel"})
CATS = {"add": _DUELCAT, "phase": _DUELCAT, "move": _DUELCAT, "remove": _DUELCAT, "result": _DUELCAT,
        "timer": _DUELCAT, "enter": _DUELCAT, "side": _DUELCAT, "cgid": _DUELCAT,
        "end": frozenset({"CORE_SEER", "ClientDuel"}), "gid": frozenset({"Duel"}),
        "sub": frozenset({"CORE_SEER"}), "pid": frozenset({"CORE_SEER"}), "part": frozenset({"CORE_SEER"}),
        "pass": frozenset({"CORE_SEER"}), "missed": frozenset({"CORE_SEER"}), "dead": frozenset({"CORE_SEER"}),
        "pips": frozenset({"CORE_SEER"}), "hp": frozenset({"CORE_SEER"}), "zone": frozenset({"CORE_SEER"}),
        "slot": frozenset({"CombatPlanningP"}), "name": frozenset({"MINION"}),
        "cast": frozenset({"CombatDetails"}), "target": frozenset({"CombatDetails"}),
        "ward": frozenset({"CombatDetails"}), "hang": frozenset({"CombatDetails"}), "aura": frozenset({"CombatDetails"}),
        "crit": frozenset({"CombatResolver"}), "rebal": frozenset({"CombatResolver"}),
        "critp": frozenset({"WizGameStats"}), "critf": frozenset({"WizGameStats"}), "pvp": frozenset({"WizGameStats"}),
        "globe": frozenset({"ClientDuelManag", "WizardGraphical", "WizClientGameEf", "WizardClientMod", "Cinematics"}),
        "char": frozenset({"CROSSPLAY", "CORE_SEER"}),
        "removed": frozenset({"CombatDetails", "CombatResolver", "CombatParticipa", "StatsOrganizer", "CORE_SEER"}),
        "removedt": frozenset({"CombatDetails", "CombatResolver", "CombatParticipa", "StatsOrganizer", "CORE_SEER"}),
        "flee": frozenset({"ClientDuel", "CORE_SEER", "CombatDetails"})}


def new_duel(num_, stamp, tk, pos, zone, char):
    return {"num": num_, "gid": None, "t0": stamp, "tk0": tk, "t1": None, "tk1": None, "pos0": pos, "zone": zone,
            "char": char, "enter": None, "adds": [], "names": {}, "parts": {}, "pid2sc": {}, "me_sc": None,
            "rounds": [], "plannings": 0, "phase": None, "pre_first": None, "victory": False, "ended": False,
            "match_result": None, "me_out": None, "pvp": None, "level": None, "crit_rating": None,
            "stats_log": {"sdamage": None, "dmg_mult": None, "resist": None, "res_mult": None, "crit_rating": None,
                          "level": None, "target_levels": [], "final_crit": None},
            "globe0": None, "globe1": None, "notes": [], "last_tk": tk, "last_stamp": stamp, "rounds_n": 0,
            "skipped_from": None, "result": None, "mine": None}


def new_round(k, n, stamp, tk, live):
    return {"k": k, "n": n, "t_plan": stamp, "plan_tk": tk, "exec_tk": None, "res_tk": None, "cast_tk": None,
            "timer": None, "moves": [], "start": [], "casts": [], "fx": {}, "died": [], "flee": False, "live": live,
            "closed": False, "hp_end": {}}


class Parser:
    """the game log's duel state machine - fed line by line (feed). The client logs other wizards' duels nearby too
    ("MSG_CombatAdd(Non-local Player)", "Other Player's Duel", "we were NOT a part of it"): every open duel is followed
    on its own (a line without a duel number goes to the duel of the last "Duel N:" line - a cast line by its 64-bit
    Duel ID), and only one shown to be the local player's (its Local Player add / enter / move, "Local Player's Duel")
    is kept: .duel my open one, .closed mine closed. .events says what happened for the recorder's windows. All state
    is plain JSON-able data (the checkpoint)"""

    def __init__(self):
        self.zone = None
        self.char = None
        self.duel = None
        self.duels = {}
        self.cx = {}
        self.cur_num = None
        self.closed = []
        self.done = collections.deque(maxlen=64)
        self.slot = None
        self.events = []
        self.n_lines = 0
        self.foreign = 0

    # ------------------------------------------------------------------ the checkpoint (my duel only)
    def save(self, own=()):
        d = self.duel
        out = {"zone": self.zone, "char": self.char, "duel": safe_duel(d, own) if d else None, "add": None,
               "ctx": None, "crit": None, "slot": self.slot, "cur": self.cur_num, "done": list(self.done)}
        if d is not None:
            cx = self.cx.get(d["num"]) or {}
            if cx.get("ctx") is not None:
                for ri, r in enumerate(d["rounds"]):
                    for ci, c in enumerate(r["casts"]):
                        if c is cx["ctx"]:
                            out["ctx"] = [ri, ci]
            if cx.get("add") is not None:
                out["add"] = next((i for i, a in enumerate(d["adds"]) if a is cx["add"]), None)
            out["crit"] = cx.get("crit")
        return out

    def load(self, s):
        self.zone, self.char = s.get("zone"), s.get("char")
        self.done = collections.deque(s.get("done") or [], maxlen=64)
        d = s.get("duel")
        self.duel = load_duel(d) if d else None
        self.duels, self.cx = {}, {}
        self.slot, self.cur_num = s.get("slot"), s.get("cur")
        if self.duel is not None:
            d = self.duel
            self.duels[d["num"]] = d
            cx = self.cx[d["num"]] = {"add": None, "ctx": None, "crit": s.get("crit")}
            if s.get("add") is not None:
                try:
                    cx["add"] = d["adds"][s["add"]]
                except (IndexError, TypeError):
                    pass
            c = s.get("ctx")
            if c:
                try:
                    cx["ctx"] = d["rounds"][c[0]]["casts"][c[1]]
                except (IndexError, KeyError, TypeError):
                    pass

    # ------------------------------------------------------------------ lines
    def feed(self, raw, tk, pos, live, m=None):
        """one line (bytes, without its end) seen at tick tk, starting at byte pos of the log; m its anchor's match"""
        m = m or ANY.search(raw)
        if m is None:
            return
        line = raw.decode("cp1252", "replace").rstrip("\r")
        h = HEAD.match(line)
        if h is None:
            return
        stamp, _w = stamp_of(line)
        if stamp is None:
            return
        rep = REPEAT.search(line)
        times = 1
        if rep:
            line = line[:rep.start()]
            times = max(1, min(int(rep.group(1)), 10))
        msg = line[h.end():]
        if "{IsSim:1}" in msg:
            return
        cat = h.group(1)
        dn = DUEL_N.match(msg)
        if dn is not None and cat in _DUELCAT:
            self.cur_num = int(dn.group(1))
        self.n_lines += 1
        for kind in BY_ANCHOR.get(m.group(0), ()):
            if cat not in CATS[kind]:
                continue
            rx = PAT[kind]
            mm = rx.search(msg) if kind in SEARCHED else rx.match(msg)
            if mm is None:
                continue
            for _ in range(times if kind in REPEATABLE else 1):
                self._line(kind, mm.groups(), stamp, tk, pos, live)
            return

    def _line(self, kind, g, stamp, tk, pos, live):
        if kind == "zone":
            self.zone = g[0]
            return
        if kind == "char":
            self.char = g[0]
            return
        if kind in DUEL_KINDS:
            d = self._get(int(g[0]), kind, stamp, tk, pos)
        elif kind == "flee" and g[0]:
            d = self.duels.get(int(g[0]))
        elif kind == "pid":
            d = self.duels.get(int(g[1]))
        elif kind == "cast":
            d = next((x for x in self.duels.values() if x["gid"] == g[0]), None)
            if d is None:
                d = self.duels.get(self.cur_num)
                if d is not None and d["gid"] is None:
                    d["gid"] = g[0]
                elif d is not None:
                    d = None                  # (a cast of a duel not followed)
            if d is not None:
                self.cur_num = d["num"]
        elif kind in MINE_ONLY:
            d = self.duel if self.duel is not None else self.duels.get(self.cur_num)
        else:
            d = self.duels.get(self.cur_num)
        if d is None:
            return
        d["last_tk"], d["last_stamp"] = tk, stamp
        getattr(self, "_" + kind)(d, g, stamp, tk, live)

    def _get(self, n, kind, stamp, tk, pos):
        d = self.duels.get(n)
        if d is not None:
            return d
        if n in self.done or kind not in OPENS:
            return None
        d = self.duels[n] = new_duel(n, stamp, tk, pos, self.zone, self.char)
        self.cx[n] = {"add": None, "ctx": None, "crit": None}
        return d

    def _mine(self, d, yes):
        if not yes:
            if d["mine"] is None:
                d["mine"] = False
            return
        if d["mine"] is True:
            return
        d["mine"] = True
        if self.duel is not None and self.duel is not d:
            self.close(self.duel, note="a new duel (%d) started before this one ended" % d["num"])
        self.duel = d
        self.events.append(("duel", d["num"]))
        if d["pre_first"] is not None and d["plannings"] == 0:
            self.events.append(("preplan_first", d["num"]))

    def cur(self, d):
        return d["rounds"][-1] if d["rounds"] else None

    def ctx(self, d):
        return self.cx[d["num"]]["ctx"]

    def open_round(self, d, tk, n=None, live=False):
        """the round lines go to: the last one while it's open, else one opened for them (its Planning not seen:
        joined mid-round, or the log skipped)"""
        r = self.cur(d)
        if r is None or r["closed"]:
            r = new_round(len(d["rounds"]) + 1, n if n is not None else ((r["n"] + 1) if r else 1), None, None, live)
            d["rounds"].append(r)
        return r

    # ------------------------------------------------------------------ the adds
    def _add(self, d, g, stamp, tk, live):
        obj = g[1]
        me = obj == "Local Player"
        if not me and not TEMPLATE_RX.match(obj):
            obj = None                    # (a wizard's add - "Non-local Player" -, or anything not a template's name)
        a = {"obj": None if me else obj, "me": me, "wiz": (not me and obj is None), "gid": None, "sc": None,
             "pid": None, "others": [], "joined": len(d["rounds"]) + (0 if d["phase"] == "Planning" else 1),
             "placed": False}
        self.cx[d["num"]]["add"] = a
        d["adds"].append(a)
        if me:
            self._mine(d, True)

    def _gid(self, d, g, stamp, tk, live):
        a = self.cx[d["num"]]["add"]
        if a is not None and a["gid"] is None:
            a["gid"] = g[0]

    def _sub(self, d, g, stamp, tk, live):
        a = self.cx[d["num"]]["add"]
        if a is not None:
            a["sc"] = int(g[0])
            a["others"].append(int(g[1]))

    def _pid(self, d, g, stamp, tk, live):
        cx = self.cx[d["num"]]
        a = cx["add"]
        if a is not None and a["pid"] is None:
            a["pid"] = int(g[0])
        cx["add"] = None
        self._resolve(d)

    def _resolve(self, d):
        """the first add's sc - it gets no 'My SubCircle' line: the one OtherPart's SubCircle no add has as its own"""
        unknown = [a for a in d["adds"] if a["sc"] is None and a["pid"] is not None]
        if len(unknown) == 1:
            own = {a["sc"] for a in d["adds"] if a["sc"] is not None}
            cands = {o for a in d["adds"] for o in a["others"]} - own
            if len(cands) == 1:
                unknown[0]["sc"] = cands.pop()
        for a in d["adds"]:
            if not a["placed"] and a["sc"] is not None and a["pid"] is not None:
                self._place(d, a)

    def _place(self, d, a):
        a["placed"] = True
        sc = a["sc"]
        p = d["parts"].get(sc)
        if p is None or p.get("out"):
            p = d["parts"][sc] = {"sc": sc, "team": None, "pid": a["pid"], "gid": a["gid"], "obj": a["obj"],
                                  "me": a["me"], "wiz": a["wiz"], "hp0": None, "hp": None, "joined": a["joined"],
                                  "out": None, "out_round": None, "died_round": None, "killed_by": None,
                                  "removed": False}
        d["pid2sc"][a["pid"]] = sc
        if a["me"]:
            d["me_sc"] = sc

    def _enter(self, d, g, stamp, tk, live):
        d["enter"] = [num(g[1]), num(g[2]), num(g[3])]
        self._mine(d, True)

    def _side(self, d, g, stamp, tk, live):
        self._mine(d, g[1] == "Local")

    def _cgid(self, d, g, stamp, tk, live):
        if not d["gid"]:
            d["gid"] = g[0]

    def _slot(self, d, g, stamp, tk, live):
        self.slot = int(g[0])

    def _name(self, d, g, stamp, tk, live):
        if self.slot is not None:
            d["names"][self.slot] = g[0]
            self.slot = None

    # ------------------------------------------------------------------ phases
    def _phase(self, d, g, stamp, tk, live):
        ph = g[1][7:]
        self.cx[d["num"]]["ctx"] = None
        d["phase"] = ph
        r = self.cur(d)
        if ph == "PrePlanning":
            if d["plannings"] == 0 and d["pre_first"] is None:
                d["pre_first"] = tk
                if d["mine"]:
                    self.events.append(("preplan_first", d["num"]))
        elif ph == "Planning":
            if r is not None and not r["closed"]:
                self.close_round(d, r)
            d["plannings"] += 1
            d["rounds"].append(new_round(d["plannings"], (r["n"] + 1) if r is not None else d["plannings"], stamp, tk,
                                         live))
            self.events.append(("planning", d["num"]))
        elif ph == "Execution":
            r = self.open_round(d, tk, live=live)
            r["exec_tk"] = tk
            self.events.append(("execution", d["num"]))
        elif ph == "Resolution":
            if r is not None and not r["closed"]:
                r["res_tk"] = tk
                self.close_round(d, r)
        elif ph == "Victory":
            d["victory"] = True
            if r is not None and not r["closed"]:
                self.close_round(d, r)
        elif ph == "Ended":
            d["ended"] = True

    def close_round(self, d, r):
        r["closed"] = True
        hp = {s[0]: s[1] for s in r["start"] if s[0] is not None}
        for c in r["casts"]:
            for e in c.get("hp", ()):
                if e[0] is not None:
                    hp[e[0]] = e[1] + e[2]
        for e in r["fx"].get("hp", ()):
            if e[0] is not None:
                hp[e[0]] = e[1] + e[2]
        r["hp_end"] = hp
        self.cx[d["num"]]["ctx"] = None
        if d["mine"]:
            self.events.append(("round", d["num"]))

    def _timer(self, d, g, stamp, tk, live):
        r = self.cur(d)
        if r is not None and not r["closed"]:
            r["timer"] = int(g[1])

    def _move(self, d, g, stamp, tk, live):
        if g[1] != "Local Player":
            return
        self._mine(d, True)
        r = self.cur(d)
        if r is None or r["closed"]:
            return
        r["moves"].append([g[2], secs(r["plan_tk"], tk)])
        if g[2] == "Cast Spell":
            r["cast_tk"] = tk

    def _remove(self, d, g, stamp, tk, live):
        r = self.cur(d)
        n = r["n"] if r is not None else None
        if g[1] == "Local Player":
            fled = bool(r is not None and r["flee"])
            d["me_out"] = {"tk": tk, "round": n, "fled": fled}
            p = d["parts"].get(d["me_sc"])
            if p is not None and not p["out"]:
                p["out"], p["out_round"] = ("fled" if fled else "removed"), n
            return
        obj = g[1] if TEMPLATE_RX.match(g[1]) else None
        if obj is None:
            return
        cands = [p for p in d["parts"].values() if p["obj"] == obj and not p["removed"]]
        if not cands:
            return
        dead = [p for p in cands if p["out"] == "dead" or (p["hp"] is not None and p["hp"] <= 0)]
        p = dead[0] if dead else cands[0]
        p["removed"] = True
        if not p["out"]:
            p["out"], p["out_round"] = "removed", n

    def _flee(self, d, g, stamp, tk, live):
        r = self.cur(d)
        if r is not None:
            r["flee"] = True

    def _result(self, d, g, stamp, tk, live):
        d["match_result"] = int(g[1])

    def _end(self, d, g, stamp, tk, live):
        if g[1] is not None:                  # ("and we were NOT a part of it": another wizard's duel)
            self._mine(d, False)
        self.close(d)

    # ------------------------------------------------------------------ a round's lines
    def _part(self, d, g, stamp, tk, live):
        pid, team, hp, pips, pp = (int(x) for x in g)
        r = self.open_round(d, tk, live=live)
        sc = d["pid2sc"].get(pid)
        if sc is None and not any(x[0] is None for x in r["start"]) and len(d["rounds"]) == 1:
            # (no 'Added participant' for it: the Participant lines come in add order)
            i = len(r["start"])
            if i < len(d["adds"]) and d["adds"][i]["pid"] is None and d["adds"][i]["sc"] is not None:
                d["adds"][i]["pid"] = pid
                self._resolve(d)
                sc = d["pid2sc"].get(pid)
        r["start"].append([sc, hp, pips, pp])
        p = d["parts"].get(sc)
        if p is not None:
            p["team"] = team
            if p["hp0"] is None:
                p["hp0"] = hp
            p["hp"] = hp

    def _cast(self, d, g, stamp, tk, live):
        n, sc, spell = int(g[1]), int(g[2]), g[3]
        r = self.open_round(d, tk, n=n, live=live)
        if r["n"] != n:
            if not r["casts"]:
                r["n"] = n
            elif len(d["notes"]) < 20:
                d["notes"].append("round %d: a cast line of round %d" % (r["n"], n))
        d["rounds_n"] = max(d["rounds_n"], n)
        c = {"sc": sc, "spell": None if spell in ("None", "") else spell}
        if any(x["sc"] == sc for x in r["casts"]):
            c["pet"] = True
        if c["spell"] is None:
            c["pass"] = True
        r["casts"].append(c)
        cx = self.cx[d["num"]]
        cx["ctx"], cx["crit"] = c, None

    def _of(self, d, sc):
        """the round's cast of caster sc (the context when it's that caster's)"""
        ctx = self.ctx(d)
        if ctx is not None and ctx["sc"] == sc:
            return ctx
        r = self.cur(d)
        for c in reversed(r["casts"] if r else []):
            if c["sc"] == sc:
                return c
        return None

    def _pass(self, d, g, stamp, tk, live):
        c = self._of(d, int(g[0]))
        if c is not None:
            c["pass"] = True

    def _missed(self, d, g, stamp, tk, live):
        c = self._of(d, int(g[0]))
        if c is not None:
            c["missed"] = True

    def _dead(self, d, g, stamp, tk, live):
        c = self._of(d, int(g[0]))
        if c is not None:
            c["dead"] = True

    def _pips(self, d, g, stamp, tk, live):
        sc = d["pid2sc"].get(int(g[0]))
        c = self._of(d, sc) if sc is not None else self.ctx(d)
        if c is not None:
            c["pips"] = [int(g[1]), int(g[2]), int(g[3]), int(g[4])]

    def _put(self, d, key, entry):
        ctx = self.ctx(d)
        if ctx is not None:
            ctx.setdefault(key, []).append(entry)
        else:
            r = self.cur(d)
            if r is not None:
                r["fx"].setdefault(key, []).append(entry)

    def _target(self, d, g, stamp, tk, live):
        self._put(d, "fx", [int(g[1]), g[2], int(g[3])])

    def _ward(self, d, g, stamp, tk, live):
        self._put(d, "wards", [int(g[0]), int(g[1]), g[2], int(g[3])])

    def _hang(self, d, g, stamp, tk, live):
        self._put(d, "hang", [int(g[0]), g[1], 1 if g[2] == "Yes" else 0, int(g[3])])

    def _aura(self, d, g, stamp, tk, live):
        self._put(d, "aura", [int(g[0]), g[1], int(g[2])])

    def _removed(self, d, g, stamp, tk, live):
        how = {"RemoveCharm": "charm", "RemoveWard": "ward", "RemoveOverTime": "dot"}[g[0]]
        self._put(d, "removed", [int(g[1]), g[2], int(g[3]), how])

    def _removedt(self, d, g, stamp, tk, live):
        self._put(d, "removed", [int(g[0]), g[1], int(g[2]), "type"])

    def _crit(self, d, g, stamp, tk, live):
        self._put(d, "crit", [num(g[0]), num(g[1]), int(g[2]), int(g[3])])

    def _rebal(self, d, g, stamp, tk, live):
        side, sc, f, m = g[0], int(g[1]), num(g[3]), num(g[4])
        S = d["stats_log"]
        ctx = self.ctx(d)
        if side == "Caster":
            if ctx is not None and "rebal" not in ctx:
                ctx["rebal"] = [f, m]
            if sc == d["me_sc"] and S["sdamage"] is None:
                S["sdamage"], S["dmg_mult"] = f, m
        else:
            self._put(d, "res", [sc, f, m])
            if sc == d["me_sc"] and S["resist"] is None:
                S["resist"], S["res_mult"] = f, m

    def _hp(self, d, g, stamp, tk, live):
        pid, before, delta = int(g[0]), int(g[1]), int(g[2])
        sc = d["pid2sc"].get(pid)
        self._put(d, "hp", [sc, before, delta])
        p = d["parts"].get(sc)
        if p is None:
            return
        p["hp"] = before + delta
        r = self.cur(d)
        if p["hp"] <= 0 and p["died_round"] is None:
            n = r["n"] if r is not None else None
            p["died_round"] = n
            ctx = self.ctx(d)
            if p["me"]:
                p["killed_by"] = {"sc": ctx["sc"], "spell": ctx["spell"], "dmg": -delta} if ctx else None
            else:
                p["killed_by"] = ctx["sc"] if ctx else None
            if not p["out"]:
                p["out"], p["out_round"] = "dead", n
            if r is not None:
                r["died"].append(sc)

    def _critp(self, d, g, stamp, tk, live):
        cp = [num(g[0]), int(g[1]), int(g[2]), None]
        cx = self.cx[d["num"]]
        cx["crit"] = cp
        S = d["stats_log"]
        ctx = cx["ctx"]
        if ctx is not None:
            ctx["crit_p"] = cp
        else:
            if S["crit_rating"] is None:
                S["crit_rating"], S["level"] = cp[0], cp[1]
            if cp[2] not in S["target_levels"] and len(S["target_levels"]) < 16:
                S["target_levels"].append(cp[2])
        d["level"], d["crit_rating"] = cp[1], cp[0]

    def _critf(self, d, g, stamp, tk, live):
        cx = self.cx[d["num"]]
        if cx["crit"] is not None:
            cx["crit"][3] = num(g[0])
            if cx["ctx"] is None and d["stats_log"]["final_crit"] is None:
                d["stats_log"]["final_crit"] = num(g[0])

    def _pvp(self, d, g, stamp, tk, live):
        d["pvp"] = g[0] == "YES"

    def _globe(self, d, g, stamp, tk, live):
        v = [int(g[1]), int(g[2])]
        if d["globe0"] is None:
            d["globe0"] = v
        d["globe1"] = v

    # ------------------------------------------------------------------ closing
    def close(self, d, forced=None, note=None):
        """a duel ends: mine to .closed with its result; another wizard's (or one never shown to be mine) dropped"""
        n = d["num"]
        if d["mine"]:
            r = self.cur(d)
            if r is not None and not r["closed"]:
                self.cx.setdefault(n, {"add": None, "ctx": None, "crit": None})
                self.close_round(d, r)
        self.duels.pop(n, None)
        self.cx.pop(n, None)
        self.done.append(n)
        if self.duel is d:
            self.duel = None
        if not d["mine"]:
            self.foreign += 1
            return
        d["t1"], d["tk1"] = d["last_stamp"], d["last_tk"]
        if note and len(d["notes"]) < 20:
            d["notes"].append(note)
        d["result"] = forced or result_of(d)
        if forced == "cut":
            d["t1"] = None
        self.closed.append(d)
        self.events.append(("closed", n))

    def close_all(self, forced, note):
        """the log started again: my duel closed (forced), the others dropped"""
        for d in list(self.duels.values()):
            self.close(d, forced=forced if d["mine"] else None, note=note if d["mine"] else None)

    def poll(self, now, game_running=None):
        """time-based closes: taken out (Remove(Local Player)) and quiet for OUT_GRACE_MS; quiet for 15 min"""
        for d in list(self.duels.values()):
            quiet = now - (d["last_tk"] or now)
            if d["me_out"] is not None and quiet > OUT_GRACE_MS:
                self.close(d)
            elif quiet > SILENT_MS:
                if not d["mine"]:
                    self.close(d)
                    continue
                running = True
                try:
                    running = bool(game_running()) if game_running else True
                except Exception:  # noqa: BLE001
                    running = True
                if running:
                    self.close(d, note="the duel's lines stopped for 15 minutes")
                else:
                    self.close(d, forced="left", note="the duel's lines stopped and the game isn't running")


def my_team(d):
    p = d["parts"].get(d["me_sc"])
    return p["team"] if p is not None else None


def side_of(d, p):
    if p["me"] or p["sc"] == d["me_sc"]:
        return "me"
    mt = my_team(d)
    if mt is not None and p["team"] is not None:
        return "ally" if p["team"] == mt else "enemy"
    ms = d["me_sc"]
    if ms is not None:
        return "ally" if (p["sc"] >= 4) == (ms >= 4) else "enemy"
    return "enemy" if p["sc"] < 4 else "ally"


def result_of(d):
    if d["me_out"] is not None:
        return "fled" if d["me_out"]["fled"] else "lost"
    enemies = [p for p in d["parts"].values() if side_of(d, p) == "enemy"]
    gone = bool(enemies) and all(p["out"] in ("dead", "removed", "fled") or p["removed"] or
                                 (p["hp"] is not None and p["hp"] <= 0) for p in enemies)
    if (d["victory"] or d["match_result"] == 0) and gone:
        return "won"
    return "unknown"


def safe_duel(d, own=()):
    """the duel as JSON-able data for current.json - a wizard's name not of my own party only as its hash"""
    out = dict(d)
    names = {}
    for sc, nm in d["names"].items():
        p = d["parts"].get(sc)
        wiz = p is not None and not p["me"] and (p["wiz"] or p["obj"] is None)
        names[str(sc)] = ("#h:" + name_h(nm)) if (wiz and nm not in own and not nm.startswith("#h:")) else nm
    out["names"] = names
    out["parts"] = {str(k): v for k, v in d["parts"].items()}
    out["pid2sc"] = {str(k): v for k, v in d["pid2sc"].items()}
    out["rounds"] = [dict(r, hp_end={str(k): v for k, v in r["hp_end"].items()}) for r in d["rounds"]]
    return out


def load_duel(s):
    d = dict(s)
    d["names"] = {int(k): v for k, v in (s.get("names") or {}).items()}
    d["parts"] = {int(k): v for k, v in (s.get("parts") or {}).items()}
    d["pid2sc"] = {int(k): v for k, v in (s.get("pid2sc") or {}).items()}
    d["rounds"] = [dict(r, hp_end={int(k): v for k, v in (r.get("hp_end") or {}).items()}) for r in s.get("rounds") or []]
    for a in d.get("adds") or []:
        a.setdefault("placed", True)
    return d


# ============================================================================ the bot's rounds
def unesc(s):
    if "\\" not in s:
        return s

    def f(m):
        t = m.group(1)
        return {"\\": "\\", "t": "\t", "n": "\n"}.get(t) or chr(int(t[1:], 16))
    out = re.sub(r"\\(\\|t|n|u[0-9A-Fa-f]{4})", f, s)
    try:
        # (UTF-16 surrogate pairs - BrecEsc writes a character past U+FFFF as two - made one character)
        return out.encode("utf-16", "surrogatepass").decode("utf-16")
    except UnicodeError:
        return out.encode("ascii", "backslashreplace").decode("ascii")


def parse_body(body):
    """({key: value}, [[ms, line]], dropped) of a post's body (bytes or str)"""
    if isinstance(body, bytes):
        body = body[:BODY_CAP].decode("ascii", "replace")
    fields, lines, dropped = {}, [], 0
    for ln in (body or "").split("\n"):
        ln = ln.rstrip("\r")
        if not ln:
            continue
        if ln.startswith("L\t"):
            parts = ln.split("\t", 2)
            if len(parts) < 3:
                continue
            if len(lines) >= LINES_CAP:
                dropped += 1
                continue
            try:
                ms = int(float(parts[1]))
            except ValueError:
                ms = None
            text = unesc(parts[2])[:LINE_CAP]
            if BAD_WORDS.search(text):
                text = "(line left out)"
            lines.append([ms, text])
        else:
            k, _, v = ln.partition("\t")
            if k and len(fields) < 200:
                fields[k.strip()] = unesc(v)[:LINE_CAP]
    return fields, lines, dropped


RULES = [
    ("user", (r"you're playing - leaving this round to you", r"you're playing \(during the wait")),
    ("botoff", (r"bot off \(.*leaving this round",)),
    ("unknown-school", (r"no school icon the bot knows",)),
    ("flee", (r"\bfleeing: ",)),
    ("learnall", (r"\blearn every card: ",)),
    ("kill", ()),
    ("defend", (r"\bdefending: ",)),
    ("heal", (r"own health: .*healing",)),
    ("party-heal", (r"\bhealer: .* - a heal on ",)),
    ("party-shield", (r"^\s*(?:hitter|blader|healer): Tower Shield on ",)),
    # (a card the round planner cast itself - Planner.ahk, planner:2, not built yet: its advice alone - planner:1, "Plan:
    # would play ..." - never matches, the round is its own rule's)
    ("planner", (r"\bplanner: .* cast",)),
    ("boostmax-hit", (r"boosts? since the last hit \(boostmax",)),
    ("learned-hit", (r"\blearned hit .* cast at",)),
    ("trap", (r"\bUseTrap \S+: found=1", r" - the kill check counts it there", r" - not counted \(solotraps:0\)")),
    ("blade", (r"\bUseBlade \S+: found=1", r"^\s*\S*(?:blade|sharpen)\S*: (?:no picture found it|its picture found .*?) "
               r"- the game's .* cast at its box")),
    ("aura", (r"\bClick aura: found=1", r"^\s*negaura: the game's .* cast at its box",
              r"^\s*aura\S*: (?:no picture found it|its picture found .*?) - the game's .* cast at its box")),
    ("bubble", (r"\bClick bubble: found=1",
                r"^\s*bubble\S*: (?:no picture found it|its picture found .*?) - the game's .* cast at its box")),
    ("tower", (r"\bUse\w+ tower: found=1",)),
    ("reshuffle", (r"\bUse\w+ reshuffle: found=1",)),
    ("hit", (r"\bUseHit hit\d: found=1",)),
    ("pass", (r"\bClick pass: found=1",)),
    ("failed", (r"didn't cast \(not enough pips\?\)",)),
]
_RULES = [(n, [re.compile(p) for p in ps]) for n, ps in RULES]
KILL = re.compile(r"\bkill check: .* -> hit\d")
KILL_CAST = re.compile(r"^@cast |\bUseHit hit\d: found=1|\blearned hit .* cast at")
LOCKED = re.compile(r"Mouse unlocked - the round's done \(locked ([\d.]+) s\)")
# (the planner's advice and the party leader's orders - "  Plan: ..." lines: never a cast, never a round's rule)
PLAN_LINE = re.compile(r"^\s*Plan: ")


def classify(lines):
    """(rule, plan, casts) of a bot round's lines ([[ms, text]]) - the first rule that matches (RULES, rule_v 3). The
    rules (the kill rule's scan too) are matched on the lines that aren't "Plan:" lines: advice and the party leader's
    orders are never casts, and nothing in one - a card's name, an enemy's - can spell a rule's phrase into a round"""
    texts = [t for _, t in lines if isinstance(t, str)]
    rtexts = [t for t in texts if not PLAN_LINE.match(t)]
    plan = next((t.split("plan: ", 1)[1] for t in texts if "plan: " in t), None)
    casts = [t[6:].strip() for t in texts if t.startswith("@cast ")]
    for name, rxs in _RULES:
        if name == "kill":
            for i, t in enumerate(rtexts):
                if KILL.search(t) and any(KILL_CAST.search(u) for u in rtexts[i + 1:]):
                    return "kill", plan, casts
            continue
        if any(rx.search(t) for t in rtexts for rx in rxs):
            return name, plan, casts
    return "other", plan, casts


# ============================================================================ the hand
def hand_key(r):
    """a cheap key of a settled hand: my pips and each card's slot / template / enchantment; None not a settled hand"""
    if not r or not r.get("settled") or not r.get("in_battle") or not r.get("planning"):
        return None
    me = r.get("me") or {}
    pp = me.get("pips") or {}
    return (tuple(pp.get(k) for k in PIP_KINDS), me.get("health"),
            tuple((c.get("slot"), c.get("template_id"), c.get("enchantment_id")) for c in r.get("cards") or ()))


def slim_card(i, c):
    out = {"i": i, "slot": c.get("slot"), "tid": c.get("template_id"), "name": c.get("name"), "kind": c.get("kind"),
           "school": c.get("school"), "pips": c.get("pips"), "x": bool(c.get("x_pips")),
           "sp": dict(c.get("school_pips") or {}), "sh": c.get("shadow_pips") or 0,
           "ench": c.get("enchantment_id") or 0, "en": c.get("enchantment") or "", "ve": c.get("value_ench") or "",
           "tc": bool(c.get("treasure")), "item": bool(c.get("item_card")), "pet": c.get("slot") == "PetCard",
           "ok": c.get("castable")}
    ov = c.get("overrides")
    if ov:
        out["ov"] = [list(x) for x in ov]
    return out


def slim_hand(r):
    me = r.get("me") or {}
    pp = me.get("pips") or {}
    cards = [slim_card(i, c) for i, c in enumerate(r.get("cards") or ())]
    facts = [card_fact(c) for c in r.get("cards") or () if c.get("template_id")]
    return {"cards": cards, "pips": {k: pp.get(k) for k in PIP_KINDS} if pp else None, "hp": me.get("health"),
            "max": me.get("max_health"), "school": me.get("school") or None}, facts


def card_fact(c, full=True):
    return {"rec": "card", "v": V, "tid": c.get("template_id"), "name": c.get("name"), "display": c.get("display"),
            "school": c.get("school"), "type": c.get("type"), "kind": c.get("kind"), "pips": c.get("pips"),
            "x": bool(c.get("x_pips")), "sh": c.get("shadow_pips") or 0, "sp": dict(c.get("school_pips") or {}),
            "value": c.get("value_text"), "dot": c.get("dot"), "heads": c.get("heads_text"),
            "boosts": c.get("boosts_text"), "text": c.get("text"), "acc": c.get("accuracy"),
            "tc_tpl": c.get("tc_flag"), "full": bool(full and c.get("kind") is not None)}


def slim_battle(parts):
    out = []
    for p in parts or ():
        mob = p.get("mob") or {}
        ai = mob.get("ai") or {}
        out.append({"gid": str(p.get("owner")) if p.get("owner") else None, "me": bool(p.get("me")),
                    "team": p.get("team"), "health": p.get("health"), "max": p.get("max_health"),
                    "boss": p.get("boss"), "player": p.get("player"), "minion": p.get("minion"),
                    "template_id": p.get("template_id"), "school": p.get("school") or None,
                    "title": mob.get("title"), "rank": mob.get("rank"), "mschool": mob.get("school"),
                    "school2": mob.get("school2"), "kind": mob.get("kind"), "mhealth": mob.get("health"),
                    "ai": {"intelligence": ai.get("intelligence"), "selfish": ai.get("selfish"),
                           "aggressive": ai.get("aggressive"), "max_shadow_pips": mob.get("max_shadow_pips")}
                    if mob else None})
    return out


def slim_info(info):
    ai = info.get("ai") or {}
    return {"title": info.get("title"), "rank": info.get("rank"), "school": info.get("school"),
            "school2": info.get("school2"), "boss": info.get("boss"), "kind": info.get("kind"),
            "health": info.get("health"), "minion": info.get("kind") == "minion" if info.get("kind") else None,
            "ai": {"intelligence": ai.get("intelligence"), "selfish": ai.get("selfish"),
                   "aggressive": ai.get("aggressive"), "max_shadow_pips": info.get("max_shadow_pips")}}


# ============================================================================ the record
def _n(v):
    """a bot field as a number when it is one"""
    if v is None:
        return None
    if isinstance(v, (int, float)):
        return v
    s = str(v).strip()
    try:
        return int(s)
    except ValueError:
        try:
            return float(s)
        except ValueError:
            return s


def _b(v):
    return None if v in (None, "") else str(v).strip() not in ("0", "false", "False")


def ahk_tick(v, now):
    """an A_TickCount the bot sent, on this clock (a 32-bit count lined up with GetTickCount64's low 32 bits) - None
    when it isn't one"""
    try:
        v = int(float(v))
    except (TypeError, ValueError):
        return None
    if abs(v - now) < 86400000:
        return v
    base = now - (now & 0xFFFFFFFF)
    c = base + (v & 0xFFFFFFFF)
    if c - now > 0x7FFFFFFF:
        c -= 1 << 32
    elif now - c > 0x7FFFFFFF:
        c += 1 << 32
    return c if abs(c - now) < 86400000 else None


def hidden_names(d, own):
    """the names of the duel's wizards that aren't me nor of my own party (kept only as name_h)"""
    out = []
    for sc, nm in d["names"].items():
        p = d["parts"].get(sc)
        if p is not None and not p["me"] and (p["wiz"] or p["obj"] is None) and nm and not nm.startswith("#h:") and \
                nm not in own and len(nm) >= 3:
            out.append(nm)
    return out


def scrub(lines, names):
    """a bot round's lines with those names put as "(ally <name_h>)" """
    if not names:
        return lines
    out = []
    for ms, t in lines:
        if isinstance(t, str):
            for nm in names:
                if nm in t:
                    t = t.replace(nm, "(ally %s)" % name_h(nm))
        out.append([ms, t])
    return out


def build_record(d, env):
    """one battle line (a dict) of closed duel d; env: what the recorder knew (see Recorder._env)"""
    state, hello = env.get("state") or {}, env.get("hello") or {}
    notes = list(d["notes"])
    own = set(env.get("own") or ())
    hide = hidden_names(d, own)
    me_sc = d["me_sc"]
    rounds_out, who = [], {"bot": [], "user": [], "none": [], "unknown": []}
    posts = sorted(env.get("posts") or [], key=lambda p: p["at"])
    hands = sorted(env.get("hands") or [], key=lambda h: h["tk"])
    by_round_posts = collections.defaultdict(list)
    rs = d["rounds"]
    for p in posts:
        best = None
        for i, r in enumerate(rs):
            if r["plan_tk"] is None:
                continue
            nxt = next((x["plan_tk"] for x in rs[i + 1:] if x["plan_tk"] is not None), None)
            end = r["exec_tk"] or r["res_tk"] or nxt
            if r["plan_tk"] - POST_PRE_MS <= p["at"] and (end is None or p["at"] <= end + POST_POST_MS):
                best = i
        if best is None:
            notes.append("a bot post (its round %s) matched no round" % p["f"].get("round"))
            continue
        by_round_posts[best].append(p)
    hands_n, posts_n = 0, 0
    me_hand0 = None
    roles = {}
    first_role = None
    hitschool = None
    whostate = env.get("who") or []
    for i, r in enumerate(rs):
        R = {"n": r["n"], "t_plan": r["t_plan"], "plan_s": secs(r["plan_tk"], r["exec_tk"]),
             "exec_s": secs(r["exec_tk"], r["res_tk"]), "timer": r["timer"], "moves": r["moves"]}
        # the hand
        lo = (r["plan_tk"] - HAND_PRE_MS) if r["plan_tk"] is not None else None
        nxt = rs[i + 1]["plan_tk"] if i + 1 < len(rs) else None
        hi_tk = r["exec_tk"] or r["cast_tk"] or r["res_tk"] or nxt
        hi = (hi_tk + HAND_POST_MS) if hi_tk is not None else None
        inr = [h for h in hands if lo is not None and h["tk"] >= lo and (hi is None or h["tk"] <= hi)]
        my_cast = next((c for c in r["casts"] if c["sc"] == me_sc and not c.get("pet")), None) if me_sc is not None else None
        # who
        ps = by_round_posts.get(i, [])
        post = next((p for p in reversed(ps) if not _b(p["f"].get("again"))), ps[-1] if ps else None)
        again = any(_b(p["f"].get("again")) for p in ps)
        bot = None
        if post is not None:
            posts_n += 1
            rule, plan, casts = classify(post["lines"])
            f = post["f"]
            lock = next((float(m.group(1)) for _, t in post["lines"] for m in [LOCKED.search(t or "")] if m), None)
            opened = post.get("open")
            bot = {"rule": rule, "rule_v": RULE_V, "plan": plan, "casts": casts, "lines": scrub(post["lines"], hide),
                   "seen_s": secs(r["plan_tk"], opened) if opened is not None else None, "lock_s": lock,
                   "flags": {k: _b(f.get(k)) for k in ("bot", "acting", "took", "left", "again", "pfm")},
                   "role": f.get("role") or None, "hitschool": f.get("hitschool") or None,
                   "botround": _n(f.get("botround")), "blround": _n(f.get("round")),
                   "dropped": (_n(f.get("drop")) or 0) + post.get("dropped", 0)}
            # (a party battle's: the bot's party mode and battle role set, its plate's slot, the hitter's slot and school;
            # its pips count)
            for k, a in (("prole", "prole"), ("brole", "brole"), ("myslot", "myslot"), ("hslot", "hslot"),
                         ("hschool", "hschool"), ("pips", "pips")):
                if f.get(a) not in (None, ""):
                    bot[k] = _n(f[a]) if k in ("myslot", "hslot", "pips") else f[a]
            if bot["blround"] not in (None, r["n"]) and len(notes) < 40:
                notes.append("round %d: the bot's round number was %s" % (r["n"], bot["blround"]))
            if bot["role"]:
                roles[str(r["n"])] = bot["role"]
                first_role = first_role or bot["role"]
            hitschool = hitschool or bot["hitschool"]
            pd = f.get("duel")
            if pd and str(pd) != str(d["num"]) and len(notes) < 40:
                notes.append("round %d: the bot's duel was %s" % (r["n"], pd))
        if bot is not None and bot["rule"] not in ("user", "botoff", "unknown-school") and not again:
            w = "bot"
        elif my_cast is None or my_cast["spell"] is None:
            w = "none"
        elif bot is not None:
            w = "user"
        else:
            st = state_at(whostate, r["plan_tk"], r["exec_tk"] or r["res_tk"] or nxt)
            w = "user" if st == "off" else "unknown"
        who[w].append(r["n"])
        R["who"] = w
        if inr:
            first, last = inr[0], inr[-1]
            R["hand"] = first["hand"]["cards"]
            R["hand_src"] = first["src"]
            R["hand_s"] = secs(r["plan_tk"], first["tk"])
            if last["key"] != first["key"]:
                R["hand_last"] = last["hand"]["cards"]
            if first["hand"]["pips"] is not None:
                R["pips"] = first["hand"]["pips"]
            R["hp"], R["max"] = first["hand"]["hp"], first["hand"]["max"]
            hands_n += 1
            if me_hand0 is None:
                me_hand0 = first["hand"]
        else:
            R["hand"] = None
            R["hand_why"] = env.get("own_why", {}).get(r["k"]) or env.get("hand_why") or "no settled hand read in the round"
        mine = next((s for s in r["start"] if s[0] == me_sc), None) if me_sc is not None else None
        if "pips" not in R and mine is not None:
            R["pips_log"] = [mine[2], mine[3]]
        if R.get("hp") is None and mine is not None:
            R["hp"] = mine[1]
        R["start"] = r["start"]
        # played
        played = None
        if my_cast is not None:
            hand = (R.get("hand_last") or R.get("hand")) or []
            hi_, amb = match_card(hand, my_cast["spell"], env.get("displays") or {})
            tg = []
            for e in my_cast.get("fx", ()):
                if e[0] not in tg:
                    tg.append(e[0])
            c = hand[hi_] if hi_ is not None else {}
            played = {"spell": my_cast["spell"], "tid": c.get("tid"), "hand_i": hi_, "ench": c.get("ench"),
                      "tc": c.get("tc"), "item": c.get("item"), "targets": tg, "pass": bool(my_cast.get("pass")),
                      "missed": bool(my_cast.get("missed")), "by": w}
            if amb and len(notes) < 40:
                notes.append("round %d: %s - several equal cards in hand, the first taken" % (r["n"], my_cast["spell"]))
        R["played"] = played
        R["bot"] = bot
        R["casts"] = r["casts"]
        R["hp_end"] = {str(k): v for k, v in r["hp_end"].items()}
        R["died"] = r["died"]
        if r["fx"]:
            R["fx"] = r["fx"]
        rounds_out.append(R)
    # the participants
    infos = env.get("mobinfo") or {}
    bmem = {}
    for b in sorted(env.get("battles") or [], key=lambda b: b["tk"]):
        for p in b["parts"]:
            if p.get("gid") and p["gid"] not in bmem:
                bmem[p["gid"]] = p
    wiz_mine = 0
    parts_out = []
    for sc in sorted(d["parts"]):
        p = d["parts"][sc]
        side = side_of(d, p)
        gid = p["gid"]
        bm = bmem.get(gid) if gid else None
        info = infos.get(gid) if gid else None
        player = bm["player"] if bm is not None and bm.get("player") is not None else (p["obj"] is None)
        if side in ("me", "ally") and player:
            wiz_mine += 1
        P = {"sc": sc, "side": side, "team": p["team"], "pid": p["pid"], "gid": gid, "obj": p["obj"]}
        nm = d["names"].get(sc)
        if nm is not None:
            if nm.startswith("#h:"):
                P["name_h"] = nm[3:]
            elif side != "me" and player and nm not in own:
                P["name_h"] = name_h(nm)
            else:
                P["name"] = nm
        else:
            P["name"] = None
        P["player"] = player
        P["template_id"] = bm.get("template_id") if bm else None
        src = None
        if bm is not None and (bm.get("title") is not None or bm.get("rank") is not None or bm.get("kind") is not None):
            src = {"title": bm.get("title"), "rank": bm.get("rank"), "school": bm.get("mschool") or bm.get("school"),
                   "school2": bm.get("school2"), "boss": bm.get("boss"), "minion": bm.get("minion"),
                   "kind": bm.get("kind"), "health": bm.get("mhealth"), "ai": bm.get("ai")}
        elif info is not None:
            src = info
        for k in ("title", "rank", "school", "school2", "boss", "minion", "kind"):
            P[k] = src.get(k) if src else None
        if bm is not None:
            if P["boss"] is None:
                P["boss"] = bm.get("boss")
            if P["minion"] is None:
                P["minion"] = bm.get("minion")
            if P["school"] is None and bm.get("school"):
                P["school"] = bm["school"]
        if P["rank"] is None and p["obj"]:
            m = RANK_RX.search(p["obj"])
            if m:
                P["rank"], P["rank_src"] = int(m.group(1)), "obj"
        hp0_mem = bm.get("health") if bm else None
        P["hp0"] = hp0_mem if hp0_mem is not None else p["hp0"]
        mx = (bm.get("max") if bm else None) or (src.get("health") if src else None)
        if mx is not None:
            P["max"], P["max_src"] = mx, "mem"
        else:
            # (mine: the health globe's max - the log's real one, me.max0's; another's: its first health)
            mx = d["globe0"][1] if side == "me" and d["globe0"] else p["hp0"]
            P["max"], P["max_src"] = mx, ("log" if mx is not None else None)
        P["ai"] = (src.get("ai") if src else None) if side == "enemy" else None
        P["joined"] = p["joined"]
        P["out_round"], P["out"] = p["out_round"], p["out"]
        P["died_round"], P["killed_by"] = p["died_round"], p["killed_by"] if not p["me"] else (
            p["killed_by"]["sc"] if p["killed_by"] else None)
        parts_out.append(P)
    # me
    mp = d["parts"].get(me_sc) if me_sc is not None else None
    my_name = d["names"].get(me_sc) if me_sc is not None else None
    if wiz_mine != 1 or (my_name or "").startswith("#h:"):
        my_name = state.get("name") or None
    school = (me_hand0 or {}).get("school") or hitschool or state.get("school") or \
        (env.get("chars") or {}).get(d["char"] or state.get("char") or "") or None
    hp0 = (me_hand0 or {}).get("hp")
    max0 = (me_hand0 or {}).get("max")
    if hp0 is None and mp is not None:
        hp0 = mp["hp0"]
    if max0 is None and d["globe0"]:
        max0 = d["globe0"][1]
    hp1 = mp["hp"] if mp is not None and mp["hp"] is not None else (d["globe1"][0] if d["globe1"] else None)
    me = {"sc": me_sc, "pid": mp["pid"] if mp else None, "gid": mp["gid"] if mp else None, "name": my_name,
          "school": (school or "").lower() or None, "level": d["level"], "crit_rating": d["crit_rating"], "hp0": hp0,
          "max0": max0, "hp1": hp1, "died_round": mp["died_round"] if mp else None,
          "killed_by": mp["killed_by"] if mp else None, "role": first_role}
    size = max(wiz_mine, 1 if me_sc is not None else 0)
    party = {"on": size > 1, "size": size, "role_set": state.get("role_set") if state else None, "roles": roles,
             "dual": _b(hello.get("dual")) if hello else None, "mode": state.get("mode") if state else None}
    # partial: the rounds from from_round on were all seen live (a round parsed from the log after a restart wasn't)
    partial = None
    if rs and not all(r["live"] for r in rs):
        fr = rs[-1]["n"] + 1
        for r in reversed(rs):
            if not r["live"]:
                break
            fr = r["n"]
        partial = {"from_round": fr, "why": env.get("partial_why") or "the helper restarted"}
    if d.get("skipped_from") is not None:
        partial = {"from_round": d["skipped_from"], "why": "the log was skipped (the recorder fell behind)"}
    t0, t1 = d["t0"], d["t1"]
    dur = None
    if d["result"] != "cut" and t1:
        if rs and all(r["live"] for r in rs) and d["tk0"] is not None and d["tk1"] is not None:
            dur = secs(d["tk0"], d["tk1"])
        else:
            w0, w1 = wall_of(t0), wall_of(t1)
            dur = round(w1 - w0, 1) if w0 is not None and w1 is not None else None
    stats_bot = env.get("stats") or None
    rid = "%s-%s" % (t0.replace("-", "").replace(":", "").replace(" ", "-"), d["num"])
    rec = {"rec": "battle", "v": V, "id": rid, "duel": d["num"], "duel_gid": d["gid"], "t0": t0, "t1": t1,
           "dur_s": dur, "build": env.get("build"), "bot_ver": hello.get("ver") or None,
           "char": d["char"] or state.get("char") or None, "zone": d["zone"], "enter": d["enter"],
           "result": d["result"], "match_result": d["match_result"], "rounds_n": d["rounds_n"], "pvp": d["pvp"],
           "me": me, "party": party, "parts": parts_out, "rounds": rounds_out, "deck": env.get("deck") or
           {"src": None, "why": "not read"},
           "stats": {"bot": stats_bot, "log": d["stats_log"]}, "settings": env.get("settings") or {}, "who": who,
           "src": {"log": "rebuilt" if partial else "tail", "mem": env.get("mem_src"), "ahk": env.get("ahk_src"),
                   "hands": "%d/%d" % (hands_n, len(rs)), "deck": (env.get("deck") or {}).get("src"),
                   "phase_b": sorted(PHASE_B)},
           "partial": partial, "notes": notes[:40]}
    return rec


def match_card(hand, spell, displays):
    """(index, ambiguous) of the card cast: by its name, then its display (case-blind); the first of equal cards"""
    if not spell or not hand:
        return None, False
    s = spell.lower()
    hits = [c for c in hand if (c.get("name") or "").lower() == s and not c.get("pet")]
    if not hits:
        hits = [c for c in hand if (displays.get(c.get("tid")) or "").lower() == s and not c.get("pet")]
    if not hits:
        return None, False
    amb = len({(c.get("tid"), c.get("ench")) for c in hits}) > 1 or len(hits) > 1
    return hits[0]["i"], amb


def state_at(events, lo, hi):
    """'off' when the who-state said bot off or you playing at any time from tick lo to hi (or the last before lo),
    'on' when it said the bot played, None not known"""
    if lo is None:
        return None
    before = None
    hit = None
    for e in events:
        if e["tk"] <= lo:
            before = e
        elif hi is None or e["tk"] <= hi:
            if e["bot"] == 0 or e["acting"] == 1:
                hit = "off"
    if hit:
        return hit
    if before is None:
        return None
    return "off" if before["bot"] == 0 or before["acting"] == 1 else "on"


# ============================================================================ the charms on now (from the log)
# (v1.0.0, TODO goal 3 step 17 - Phase B's memory snapshot not built: the log's AddHangingEffect lines are the only
# record of what's on whom. Its Effect is the game's SpellEffect type - "kModifyOutgoingDamage" or the same without the
# k, matched either way: a charm out (a blade, + ; a weakness, -), a ward in (a trap, + ; a shield, -), an absorb)
CHARM_KINDS = {"modifyoutgoingdamage": ("blades", "weak"), "modifyincomingdamage": ("traps", "shields"),
               "absorbdamage": ("absorb", "absorb")}
# (a hit's own effects - handmem.py's DAMAGE and DOT, plain (_fx_name), not imported: handmem reads the game's memory.
# A whitelist, not "damage" anywhere in the name: kModifyOutgoingDamage / kModifyIncomingDamage / kAbsorbDamage are the
# charms and wards themselves - were a ProcessTargets line written for a blade's or trap's own effect, it would be taken
# for a hit and use up the charms on before putting the new one on)
DAMAGE_FX = {"damage", "damagenocrit", "stealhealth", "maxhealthdamage", "damagepertotalpippower", "dividedamage",
             "damageovertime", "deferreddamage"}


def _fx_name(e):
    """an effect's type as the log names it, plain: 'kModifyOutgoingDamage' / 'ModifyOutgoingDamage' -> 'modifyoutgoingdamage'"""
    s = str(e or "").strip()
    return (s[1:] if s[:1] == "k" and s[1:2].isupper() else s).lower()


def _fact_index(facts):
    """{spell name or display (lower case): fact} of cards.jsonl's facts ({tid: fact})"""
    out = {}
    for f in (facts or {}).values():
        if not isinstance(f, dict):
            continue
        for k in ("name", "display"):
            n = str(f.get(k) or "").strip().lower()
            if n and n not in out:
                out[n] = f
    return out


def _schools_of(text):
    """the schools of a heads / boosts text ('storm:35,fire:35', 'all:25') - None when it names none (not known)"""
    out = []
    for part in str(text or "").split(","):
        k = part.partition(":")[0].strip().lower()
        if k == "all":
            return None
        if k in ("balance", "death", "fire", "ice", "life", "myth", "storm") and k not in out:
            out.append(k)
    return out or None


def _fits(charm, schools):
    """charm ({schools: [..] or None - every school}) fits a hit of schools ([..], None - not known: every charm, the
    bot's own rule when a hit's heads aren't known - KillCalc.ahk ConsumeBoosts)"""
    return charm["schools"] is None or schools is None or any(s in charm["schools"] for s in schools)


def charms_now(duel, facts=None):
    """the blades, traps, shields, weaknesses and absorbs on each participant now, rebuilt from the log alone (Phase B's
    memory snapshot isn't built): duel - the recorder's open duel (Parser.duel) or a battle record - its rounds' casts in
    order: each cast's AddHangingEffect lines (hang [[target sc, effect, charm 1/0, param]]) put one on its target, its
    schools those of the caster's spell in cards.jsonl's facts ({tid: fact}: its boosts, else its school - None not known:
    an enemy's spell, a card never seen in a hand: it fits every school); each hit (a cast with damage on another sc -
    ModifyHealth's, or a ProcessTargets damage effect's - DAMAGE_FX -, not missed) uses up the caster's charms out and
    each target's wards in that fit its schools (the spell's heads in the facts; not known: every one - KillCalc.ahk
    ConsumeBoosts' rule), absorbs taken off by the damage; a REMOVED line (not seen in a log yet) takes its own off.
    Identical blades on one wizard don't stack (the game's - one of a spell's name kept); traps and shields do.
    -> {by: {sc: {blades, traps, shields, weak, absorb: [{pct (an absorb's: the damage it still soaks), schools, spell
    (the log's - the template's name), name (the card's display in the facts, else the spell), by (the caster's sc),
    round}]}}, me (my sc, None not known), round (the last round seen), n (the charms put on), why
    [notes]}. Never raises: what it got to"""
    out = {"by": {}, "me": None, "round": None, "n": 0, "why": []}
    try:
        if not isinstance(duel, dict):
            out["why"].append("no battle")
            return out
        me = duel.get("me_sc")
        if me is None and isinstance(duel.get("me"), dict):
            me = duel["me"].get("sc")
        out["me"] = me
        idx = _fact_index(facts)
        unknown = 0
        by = out["by"]

        def lists(sc):
            return by.setdefault(sc, {"blades": [], "traps": [], "shields": [], "weak": [], "absorb": []})

        def side(sc):
            return None if not isinstance(sc, int) else (sc >= 4)
        for r in duel.get("rounds") or []:
            if not isinstance(r, dict):
                continue
            n = r.get("n")
            out["round"] = n if n is not None else out["round"]
            for c in r.get("casts") or []:
                if not isinstance(c, dict) or c.get("pass") or not c.get("spell"):
                    continue
                f = idx.get(str(c["spell"]).strip().lower())
                cs = c.get("sc")
                # (the hit first - a spell that hits and puts a charm on keeps that one)
                if not c.get("missed"):
                    hit = set()
                    dmg = collections.Counter()
                    for e in c.get("hp") or []:
                        if isinstance(e, (list, tuple)) and len(e) >= 3 and isinstance(e[2], (int, float)) and e[2] < 0 \
                                and side(e[0]) is not None and side(e[0]) != side(cs):
                            hit.add(e[0])
                            dmg[e[0]] += -e[2]
                    for e in c.get("fx") or []:
                        if isinstance(e, (list, tuple)) and len(e) >= 2 and _fx_name(e[1]) in DAMAGE_FX \
                                and side(e[0]) is not None and side(e[0]) != side(cs):
                            hit.add(e[0])
                    if hit:
                        heads = _schools_of(f.get("heads")) if f else None
                        if heads is None and f and f.get("school") and not f.get("heads"):
                            heads = _schools_of(str(f.get("school")) + ":1")
                        if cs in by:
                            for k in ("blades", "weak"):
                                by[cs][k] = [x for x in by[cs][k] if not _fits(x, heads)]
                        for t in hit:
                            if t in by:
                                for k in ("traps", "shields"):
                                    by[t][k] = [x for x in by[t][k] if not _fits(x, heads)]
                                left = dmg.get(t, 0)
                                keep = []
                                for a in by[t]["absorb"]:
                                    take = min(a["pct"], left)
                                    left -= take
                                    if a["pct"] - take > 0:
                                        keep.append(dict(a, pct=a["pct"] - take))
                                by[t]["absorb"] = keep
                for e in c.get("hang") or []:
                    if not (isinstance(e, (list, tuple)) and len(e) >= 4 and isinstance(e[3], (int, float))):
                        continue
                    kinds = CHARM_KINDS.get(_fx_name(e[1]))
                    if kinds is None or not e[3]:
                        continue
                    k = kinds[0] if e[3] > 0 else kinds[1]
                    sch = None
                    if f:
                        sch = _schools_of(f.get("boosts"))
                        if sch is None and not f.get("boosts") and f.get("school"):
                            sch = _schools_of(str(f.get("school")) + ":1")
                    else:
                        unknown += 1
                    # (name: the card as a hand shows it - cards.jsonl's display, as battlesim.card_of names a hand's
                    # card - so the planner's "that blade's on already" sees a copy in hand; spell: the log's own)
                    ch = {"pct": abs(e[3]), "schools": sch, "spell": c["spell"], "by": cs, "round": n,
                          "name": str((f.get("display") or f.get("name") or c["spell"]) if f else c["spell"])}
                    L = lists(e[0])[k]
                    if k == "blades" and any(x["spell"] == ch["spell"] for x in L):
                        continue
                    L.append(ch)
                    out["n"] += 1
                for e in c.get("removed") or []:
                    _charm_off(by, e)
            for e in (r.get("fx") or {}).get("removed") or []:
                _charm_off(by, e)
        if unknown:
            out["why"].append("%d charm%s from a spell not in cards.jsonl (an enemy's?) - taken to fit every school"
                              % (unknown, "" if unknown == 1 else "s"))
    except Exception as e:  # noqa: BLE001 - what it got to
        out["why"].append("the charms couldn't all be read (%r)" % (e,))
    return out


def _charm_off(by, e):
    """a REMOVED line's charm ([target sc, effect, param, how]) taken off its target - the first of that kind and %"""
    if not (isinstance(e, (list, tuple)) and len(e) >= 3 and isinstance(e[2], (int, float))) or e[0] not in by:
        return
    kinds = CHARM_KINDS.get(_fx_name(e[1]))
    if kinds is None or not e[2]:
        return
    L = by[e[0]][kinds[0] if e[2] > 0 else kinds[1]]
    for i, x in enumerate(L):
        if x["pct"] == abs(e[2]):
            del L[i]
            return


# ============================================================================ the files
def header(bot):
    return {"rec": "header", "v": V, "format": SCHEMA, "doc": "AutoFarmer\\vision\\battlerec.py",
            "made": time.strftime("%Y-%m-%d %H:%M:%S"), "bot": bot}


def dumps(o):
    return json.dumps(o, separators=(",", ":"), ensure_ascii=True)


def append_line(path, data):
    """one os.write of data (bytes, ending with \\n) at the end of path - a leading \\n when the file doesn't end with
    one; the header first when it's new (data is then header + line). Raises OSError"""
    os.makedirs(os.path.dirname(path), exist_ok=True)
    fd = os.open(path, os.O_RDWR | os.O_APPEND | os.O_CREAT | getattr(os, "O_BINARY", 0), 0o666)
    try:
        size = os.fstat(fd).st_size
        pre = b""
        if size:
            os.lseek(fd, size - 1, os.SEEK_SET)
            if os.read(fd, 1) != b"\n":
                pre = b"\n"
        out = pre + data
        n = os.write(fd, out)
        while n < len(out):
            n += os.write(fd, out[n:])
        return size == 0
    finally:
        os.close(fd)


def replace_text(path, text, tries=3):
    tmp = path + ".tmp"
    for k in range(tries):
        try:
            with open(tmp, "w", encoding="utf-8", newline="\n") as f:
                f.write(text)
            os.replace(tmp, path)
            return True
        except OSError:
            if k + 1 < tries:
                time.sleep(0.05)
    return False


class Store:
    """learned\\battles\\ - day files, cards.jsonl, today.txt, current.json, the month zips and the cap"""

    def __init__(self, root_dir, log, bot_ver=lambda: None):
        self.dir = root_dir
        self.log = log
        self.bot_ver = bot_ver
        self.pending = []            # [record, tries]
        self.cards = {}              # tid -> full (bool)
        self.displays = {}           # tid -> the card's display name (played matched by it after the spell's name)
        self.cards_new = []          # card facts to append
        self.cards_loaded = False
        self.today = {"date": None, "n": 0, "won": 0, "lost": 0, "fled": 0, "bytes": 0, "last": ""}
        self.why = ""
        self.paused = None
        self.written = 0
        self.dropped = 0
        self.next_maintain = 0
        self.dirty_today = True

    def load(self):
        os.makedirs(self.dir, exist_ok=True)
        p = os.path.join(self.dir, "cards.jsonl")
        try:
            with open(p, "rb") as f:
                for ln in f:
                    try:
                        o = json.loads(ln)
                    except ValueError:
                        continue
                    if isinstance(o, dict) and o.get("rec") == "card" and o.get("tid") is not None:
                        self.cards[o["tid"]] = bool(o.get("full")) or self.cards.get(o["tid"], False)
                        if o.get("display") and len(self.displays) < 20000:
                            self.displays[o["tid"]] = o["display"]
        except OSError:
            pass
        self.cards_loaded = True
        try:
            with open(os.path.join(self.dir, "today.txt"), encoding="utf-8") as f:
                t = f.read().strip().split("|")
            if len(t) >= 7 and t[0] == time.strftime("%Y-%m-%d"):
                self.today.update(date=t[0], n=int(t[1]), won=int(t[2]), lost=int(t[3]), fled=int(t[4]),
                                  bytes=int(t[5]), last=t[6])
        except (OSError, ValueError):
            pass

    def day_path(self, day):
        mdir = os.path.join(self.dir, day[:7])
        p = os.path.join(mdir, day + ".jsonl")
        k = 1
        while True:
            try:
                if os.path.getsize(p) < DAY_MAX:
                    return p
            except OSError:
                return p
            k += 1
            p = os.path.join(mdir, "%s-%d.jsonl" % (day, k))

    def add(self, rec):
        self.pending.append([rec, 0, 0])

    def note_card(self, fact):
        tid = fact.get("tid")
        if tid is None or not self.cards_loaded:
            return
        if fact.get("display") and len(self.displays) < 20000:
            self.displays[tid] = fact["display"]
        have = self.cards.get(tid)
        if have is None or (fact.get("full") and not have):
            self.cards[tid] = bool(fact.get("full"))
            f = dict(fact)
            f["seen"] = time.strftime("%Y-%m-%d")
            self.cards_new.append(f)

    def flush(self, now=None):
        """writes what's waiting (records, card facts, today.txt) - True when something was written. A battle that
        can't be written (the file held open, the disk full) is tried again 5 s, then 60 s later (kept in current.json
        meanwhile), then left out with a vision.log line"""
        did = False
        now = now if now is not None else int(time.monotonic() * 1000)
        if self.paused:
            self.dropped += len(self.pending)
            if self.pending:
                self.log("battlerec: %d battle(s) not written - %s" % (len(self.pending), self.paused))
            self.pending = []
        keep = []
        for item in self.pending:
            rec, tries, due = item
            if now < due:
                keep.append(item)
                continue
            try:
                line = (dumps(rec) + "\n").encode("ascii")
                p = self.day_path(rec["t0"][:10])
                new = not os.path.exists(p) or os.path.getsize(p) == 0
                data = ((dumps(header(self.bot_ver())) + "\n").encode("ascii") if new else b"") + line
                append_line(p, data)
                self.written += 1
                did = True
                self.count(rec, len(line))
            except OSError as e:
                item[1] = tries + 1
                if item[1] >= WRITE_TRIES:
                    self.dropped += 1
                    self.log("battlerec: battle %s couldn't be written (%r) - left out" % (rec.get("id"), e))
                else:
                    item[2] = now + (5000 if item[1] == 1 else 60000)
                    keep.append(item)
        self.pending = keep
        if self.cards_new:
            try:
                p = os.path.join(self.dir, "cards.jsonl")
                new = not os.path.exists(p) or os.path.getsize(p) == 0
                data = ((dumps(header(self.bot_ver())) + "\n") if new else "") + "".join(dumps(c) + "\n"
                                                                                       for c in self.cards_new)
                append_line(p, data.encode("ascii"))
                self.cards_new = []
                did = True
            except OSError:
                pass
        if self.dirty_today:
            if self.write_today():
                self.dirty_today = False
        return did

    def count(self, rec, nbytes):
        day = time.strftime("%Y-%m-%d")
        T = self.today
        if T["date"] != day:
            T.update(date=day, n=0, won=0, lost=0, fled=0, bytes=0, last="")
        T["n"] += 1
        if rec["result"] in ("won", "lost", "fled"):
            T[rec["result"]] += 1
        T["bytes"] += nbytes
        T["last"] = "%s %s" % ((rec.get("t1") or rec["t0"])[11:], rec["result"])
        self.dirty_today = True

    def set_why(self, why):
        if why != self.why:
            self.why = why
            self.dirty_today = True

    def write_today(self):
        T = self.today
        day = time.strftime("%Y-%m-%d")
        if T["date"] != day:
            T.update(date=day, n=0, won=0, lost=0, fled=0, bytes=0, last="")
        try:
            os.makedirs(self.dir, exist_ok=True)
        except OSError:
            return False
        why = self.paused or self.why or ""
        return replace_text(os.path.join(self.dir, "today.txt"), "%s|%d|%d|%d|%d|%d|%s|%s\n" % (
            T["date"], T["n"], T["won"], T["lost"], T["fled"], T["bytes"], T["last"], why.replace("|", "/")))

    # ------------------------------------------------------------------ months and the cap
    def size_mb(self):
        tot = 0
        for base, _dirs, files in os.walk(self.dir):
            for fn in files:
                try:
                    tot += os.path.getsize(os.path.join(base, fn))
                except OSError:
                    pass
        return tot / 1048576.0

    def months(self):
        try:
            return sorted(n for n in os.listdir(self.dir) if re.match(r"^\d{4}-\d\d$", n) and
                          os.path.isdir(os.path.join(self.dir, n)))
        except OSError:
            return []

    def maintain(self, pace=None, today=None):
        """months before the last two zipped; over CAP_MB all but the current month too; still over: paused"""
        today = today or time.strftime("%Y-%m")
        y, m = int(today[:4]), int(today[5:7])
        prev = "%04d-%02d" % ((y, m - 1) if m > 1 else (y - 1, 12))
        for mo in self.months():
            if mo < prev:
                self.zip_month(mo, pace)
        if self.size_mb() > CAP_MB:
            for mo in self.months():
                if mo < today:
                    self.zip_month(mo, pace)
            if self.size_mb() > CAP_MB:
                if not self.paused:
                    self.log("battlerec: learned\\battles is over %d MB - recording paused" % CAP_MB)
                self.paused = "paused: learned\\battles is full - move old months away"
                self.dirty_today = True
                return
        if self.paused:
            self.paused = None
            self.dirty_today = True

    def zip_month(self, mo, pace=None):
        mdir = os.path.join(self.dir, mo)
        out = os.path.join(self.dir, mo + ".jsonl.gz")
        try:
            files = sorted(f for f in os.listdir(mdir) if f.endswith(".jsonl"))
        except OSError:
            return
        for fn in files:
            src = os.path.join(mdir, fn)
            try:
                at = os.path.getsize(out) if os.path.exists(out) else 0
                h = hashlib.sha1()
                with open(src, "rb") as fi, open(out, "ab") as fo:
                    with gzip.GzipFile(filename="", mode="wb", fileobj=fo, mtime=0) as gz:
                        while True:
                            b = fi.read(1 << 20)
                            if not b:
                                break
                            h.update(b)
                            gz.write(b)
                            if pace:
                                pace()
                # (read back: the member just added decompresses to the day file, byte for byte)
                h2 = hashlib.sha1()
                with open(out, "rb") as fo:
                    fo.seek(at)
                    with gzip.GzipFile(fileobj=fo, mode="rb") as gz:
                        while True:
                            b = gz.read(1 << 20)
                            if not b:
                                break
                            h2.update(b)
                            if pace:
                                pace()
                if h.digest() == h2.digest():
                    try:
                        os.remove(src)
                    except OSError as e:
                        # (the day file open elsewhere - battlereport, a virus scan: its member taken back out, so the
                        # next maintain doesn't zip the day twice)
                        with open(out, "r+b") as fo:
                            fo.truncate(at)
                        self.log("battlerec: %s zipped but couldn't be removed (%r) - kept, zipped later" % (fn, e))
                        return
                else:
                    with open(out, "r+b") as fo:
                        fo.truncate(at)
                    self.log("battlerec: %s didn't zip back the same - kept" % fn)
            except (OSError, EOFError, ValueError) as e:
                self.log("battlerec: %s couldn't be zipped (%r) - kept" % (fn, e))
                return
        try:
            if not os.listdir(mdir):
                os.rmdir(mdir)
        except OSError:
            pass


# ============================================================================ the log
class Tail:
    """the game's log read from pos on, short opens (read only; the game keeps writing)"""

    def __init__(self, path):
        self.path = path
        self.pos = None
        self.head = None

    def look(self):
        """(head, size) now - None when it can't be read"""
        try:
            with open(self.path, "rb") as f:
                head = f.read(17)
                size = os.fstat(f.fileno()).st_size
            return head, size
        except OSError:
            return None

    def read(self):
        """(state, base, data): state 'new' (another log: the head changed or it shrank), 'skip' (more than BEHIND_MAX
        behind: jumped), 'ok'; base the byte position of data's start. data holds whole lines only. None unreadable"""
        try:
            with open(self.path, "rb") as f:
                head = f.read(17)
                size = os.fstat(f.fileno()).st_size
                state = "ok"
                if self.head is not None and (head != self.head or (self.pos is not None and size < self.pos)):
                    state, self.pos = "new", 0
                self.head = head
                if self.pos is None:
                    self.pos = size
                if size - self.pos > BEHIND_MAX:
                    self.pos = size - BEHIND_MAX
                    state = "skip" if state == "ok" else state
                    f.seek(self.pos)
                    f.readline()                      # (to the next whole line)
                    self.pos = f.tell()
                f.seek(self.pos)
                data = f.read(min(READ_MAX, max(0, size - self.pos)))
        except OSError:
            return None
        cut = data.rfind(b"\n")
        if cut < 0:
            return state, self.pos, b""
        base = self.pos
        self.pos += cut + 1
        return state, base, data[:cut + 1]


def back_scan(path, size, pace=None):
    """(zone, char, duel in progress: (number, its first line's position) or None, the log's last stamp) - the last
    BACKSCAN bytes, 1 MB slices"""
    zone = char = None
    first, last_phase, over, mine = {}, {}, set(), set()
    last_stamp_w = None
    start = max(0, size - BACKSCAN)
    rx = re.compile(rb"ConnectComplete destination Zone=|MSG_LoginComplete CharID:|Duel \d+: ")
    with open(path, "rb") as f:
        f.seek(start)
        if start:
            f.readline()
        pos = f.tell()
        while pos < size:
            chunk = f.read(min(1 << 20, size - pos))
            if not chunk:
                break
            cut = chunk.rfind(b"\n")
            if cut < 0:
                break
            chunk = chunk[:cut + 1]
            off = 0
            for raw in chunk.split(b"\n")[:-1]:
                lp = pos + off
                off += len(raw) + 1
                if raw[:2].isdigit():
                    st, w = stamp_of(raw[:17].decode("ascii", "replace"))
                    if w is not None:
                        last_stamp_w = w
                m = rx.search(raw)
                if m is None:
                    continue
                line = raw.decode("cp1252", "replace").rstrip("\r")
                h = HEAD.match(line)
                if h is None:
                    continue
                msg = line[h.end():]
                mz = PAT["zone"].match(msg)
                if mz:
                    zone = mz.group(1)
                    continue
                mc = PAT["char"].match(msg)
                if mc:
                    char = mc.group(1)
                    continue
                md = re.match(r"Duel (\d+): (MSG_CombatAdd\(Local Player\)|MSG_CombatAdd|MSG_CombatPhase\((kPhase_\w+)\)|"
                              r"MSG_EndDuel received|MSG_CombatRemove\(Local Player\)|MSG_SetPlanningPhaseTimer|"
                              r"MSG_CombatMoveSelection\(Local Player|Local Player Entering Combat|"
                              r"CombatPlanningPhaseWindow::HandleCombatPhase\(kPhase_\w+, Local Player's Duel)", msg)
                if md is None:
                    continue
                n = int(md.group(1))
                w2 = md.group(2)
                if n not in first and w2.startswith(("MSG_CombatAdd", "MSG_CombatPhase", "Local Player")):
                    first[n] = lp
                if w2.startswith(("MSG_CombatAdd(Local", "MSG_CombatMoveSelection(Local", "Local Player",
                                  "CombatPlanningPhaseWindow")):
                    mine.add(n)
                if md.group(3):
                    last_phase[n] = stamp_of(line)[1]
                    if md.group(3) == "kPhase_Ended":
                        over.add(n)
                if w2.startswith(("MSG_EndDuel", "MSG_CombatRemove")):
                    over.add(n)
            pos += len(chunk)
            f.seek(pos)
            if pace:
                pace()
    prog = None
    first = {k: v for k, v in first.items() if k in mine}
    if first:
        n = max(first, key=lambda k: first[k])
        lp = last_phase.get(n)
        if n not in over and lp is not None and last_stamp_w is not None and last_stamp_w - lp <= IN_PROGRESS_S:
            prog = (n, first[n])
    return zone, char, prog, last_stamp_w


# ============================================================================ the recorder
class _NoGate:
    n = 0
    entered = 0

    def busy(self):
        return False

    def idle(self, d=0.1, own=0):
        return True


class Recorder:
    def __init__(self, root, nav=None, log=None, gate=None, clock=None):
        self.root = root
        self.dir = os.path.join(root, "learned", "battles")
        self.nav_fn = nav
        self._logf = log or (lambda m: None)
        self.gate = gate or _NoGate()
        self.clock = clock or Clock()
        self.q = queue.Queue(maxsize=QUEUE_MAX)
        self.stop_ev = threading.Event()
        self.thread = None
        self.on = False
        self.broken = None
        self.hello = {}
        self.state = {}
        self.who = collections.deque(maxlen=400)
        self.hands = collections.deque(maxlen=300)
        self.battles = collections.deque(maxlen=60)
        self.posts = []
        self.attached = collections.defaultdict(list)      # duel number -> its posts
        self.mobinfo = {}                                   # duel number -> {gid: info}
        self.sig_ok = {}                                    # duel number -> bool
        self.own_why = collections.defaultdict(dict)        # duel number -> {round k: why}
        self.own_try = {}                                   # (duel, k) -> [tries, next tick]
        self.parser = Parser()
        self.tail = None
        self.store = Store(self.dir, self._log, lambda: self.hello.get("ver") or None)
        self.counts = collections.Counter()
        self.said = set()
        self.own = collections.deque(maxlen=400)            # own reads: (tick, what, gate.n, phase, bot playing)
        self.deck = {"r": None, "tk": None, "at": None, "sig": None, "zone": None, "due": 0, "sig_next": 0, "why":
                     "not read yet"}
        self.last_close = None
        self.next_tail = 0
        self.last_hand = (None, 0)
        self.last_battle = (None, 0)
        self.chars = None
        self.partial_why = {}
        self.ckpt_due = False
        self.no_log_said = 0
        self.logread_said = 0
        self._seen_entered = 0
        self.last_result = ""
        self.started = False
        self.store_loaded = False
        self.pre_due = None
        self.k_live = 0              # lines looked at (counted every 10 - the tests' measure of the gate's stop)
        self.hello_seen = False
        self.said_implicit = False
        self.fight_at = 0.0          # (monotonic s: the bot's /cards or /battle last read a battle - own deck reads stop)

    # ------------------------------------------------------------------ small things
    def _log(self, msg):
        try:
            self._logf(msg)
        except Exception:  # noqa: BLE001
            pass

    def _say_once(self, key, msg):
        if key not in self.said:
            self.said.add(key)
            self._log(msg)

    def _nav(self):
        if self.nav_fn is None or self.hello.get("navmem", "1") == "0":
            return None
        try:
            return self.nav_fn()
        except Exception:  # noqa: BLE001
            return None

    def mem_ok(self):
        return self.hello.get("navmem", "1") != "0" and self.hello.get("dual") != "1" and self.nav_fn is not None

    def in_duel(self):
        return self.parser.duel is not None

    # ------------------------------------------------------------------ the hooks (request threads: microseconds)
    def saw_hand(self, r):
        """/cards (memory) read a hand: a settled one put on the queue (a cheap key against the last first) - never
        raises"""
        try:
            if not self.on or self.broken:
                return
            k = hand_key(r)
            if k is None:
                return
            self.fight_at = time.monotonic()
            tk = self.clock.tk()
            lk, lt = self.last_hand
            if k == lk and tk - lt < 3000:
                return
            self.last_hand = (k, tk)
            self.q.put_nowait((tk, "hand", r, k))
        except queue.Full:
            self.counts["qdrop"] += 1
        except Exception:  # noqa: BLE001 - not a hand
            self.counts["bad_hook"] += 1

    def saw_battle(self, parts):
        """/battle read the participants: onto the queue - never raises"""
        try:
            if not self.on or self.broken or not parts:
                return
            self.fight_at = time.monotonic()
            tk = self.clock.tk()
            k = tuple((p.get("owner"), p.get("health")) for p in parts)
            lk, lt = self.last_battle
            if k == lk and tk - lt < 3000:
                return
            self.last_battle = (k, tk)
            self.q.put_nowait((tk, "battle", parts, None))
        except queue.Full:
            self.counts["qdrop"] += 1
        except Exception:  # noqa: BLE001 - not a battle reading
            self.counts["bad_hook"] += 1

    def post(self, q, body=b""):
        """POST /rec (and GET /rec?ev=who): onto the queue - 'ok', or 'off' when the recorder is off. Before any hello
        (the helper restarted while the bot runs: its hello came to the one before) a post is taken too: the bot posts
        only with recording on"""
        try:
            ev = (q or {}).get("ev", "")
            if (not self.on or self.broken) and ev != "hello" and (self.hello_seen or self.broken):
                return "off"
            self.q.put_nowait((self.clock.tk(), "post", dict(q or {}), body if body is not None else b""))
        except queue.Full:
            self.counts["qdrop"] += 1
        except Exception:  # noqa: BLE001 - not a post
            self.counts["bad_hook"] += 1
        return "ok"

    def stat(self):
        """/recstat: rec|on|today n|bytes|last result|why|orphans|queue drops|errors|records|pending|lines|posts"""
        T = self.store.today
        on = "on" if self.on and not self.broken else "off"
        why = self.broken or self.store.paused or self.store.why or ""
        return "|".join(str(x) for x in ("rec", on, T["n"], T["bytes"], self.last_result, why.replace("|", "/"),
                                         self.counts["orphans"], self.counts["qdrop"], self.counts["errors"],
                                         self.store.written, len(self.store.pending), self.parser.n_lines,
                                         self.counts["posts"]))

    # ------------------------------------------------------------------ the thread
    def start(self):
        if self.thread is None or not self.thread.is_alive():
            self.thread = threading.Thread(target=self._run, name="battlerec", daemon=True)
            self.thread.start()
        return self

    def stop(self, wait=1.0):
        self.stop_ev.set()
        th = self.thread
        if th is not None and th.is_alive() and th is not threading.current_thread():
            th.join(wait)

    def _run(self):
        while not self.stop_ev.is_set():
            try:
                self.step(block=True)
            except Exception as e:  # noqa: BLE001 - never into the helper: off till the next hello
                self._broke(e)
        try:
            if self.on and not self.broken:
                self._checkpoint()
                self.store.flush()
        except Exception:  # noqa: BLE001
            pass

    def _broke(self, e):
        self.counts["errors"] += 1
        tb = traceback.format_exc().strip().splitlines()
        where = next((ln.strip() for ln in reversed(tb) if ln.strip().startswith("File")), "")
        self.broken = "off after an error: %r" % (e,)
        self._log("battlerec: switched off till the next hello - %r (%s)" % (e, where[-160:]))
        try:
            self.store.set_why("recorder off: an error (vision.log)")
            self.store.write_today()
        except Exception:  # noqa: BLE001
            pass

    def step(self, block=False):
        """one pass: the queue, the log, the windows, the closed duels, the files at idle"""
        try:
            item = self.q.get(timeout=TAIL_S) if block else self.q.get_nowait()
        except queue.Empty:
            item = None
        k = 0
        while item is not None and k < 256:
            self._item(item)
            k += 1
            try:
                item = self.q.get_nowait()
            except queue.Empty:
                item = None
        if not self.on or self.broken:
            return
        now = self.clock.tk()
        if not self.started:
            self._begin(now)
        if self.tail is not None and now >= self.next_tail:
            self.next_tail = now + int(TAIL_S * 1000)
            self._tail(now)
        elif self.tail is None and now >= self.next_tail:
            self.next_tail = now + 5000
            self._find_log(now)
        self._attach(now)
        self.parser.poll(now, self._game_running)
        self._events()
        self._windows(now)
        if self.parser.closed and self.gate.idle(0.1):
            self._close_duels(now)
        if self.gate.idle(0.1):
            self._flush(now)

    def _item(self, item):
        tk, kind, a, b = item
        try:
            if kind == "hand":
                self._hand(tk, a, "bot", b)
            elif kind == "battle":
                self.battles.append({"tk": tk, "parts": slim_battle(a)})
            elif kind == "post":
                self._post(tk, a, b)
        except Exception as e:  # noqa: BLE001 - that item only
            self.counts["bad_" + kind] += 1
            self._say_once("bad_" + kind, "battlerec: a %s couldn't be used (%r) - left out (said once)" % (kind, e))

    def _hand(self, tk, r, src, key=None):
        key = key or hand_key(r)
        if key is None:
            return
        hand, facts = slim_hand(r)
        self.hands.append({"tk": tk, "key": [list(key[0]), key[1], [list(x) for x in key[2]]], "hand": hand,
                           "src": src})
        for f in facts:
            self.store.note_card(f)

    def _post(self, tk, q, body):
        fields, lines, dropped = parse_body(body)
        f = dict(q)
        f.update(fields)
        ev = f.get("ev", "")
        self.counts["posts"] += 1
        if ev != "hello" and not self.hello_seen and ev in ("round", "who", "state"):
            # (no hello yet - the helper restarted while the bot runs: this post stands for it; a state post carries
            # the hello's keys, a round or who post doesn't - the game's log then from navmem's game folder)
            self._hello(tk, dict({"on": "1"}, **{k: f[k] for k in ("on", "log", "ver", "navmem", "dual", "bot", "acting",
                                                                    "pfm", "tk") if k in f}), implicit=True)
            if ev == "state":
                self._state(f)
                return
        if ev == "hello":
            self._hello(tk, f)
        elif ev == "who":
            self._who(tk, f)
        elif ev == "state":
            self._state(f)
        elif ev == "round":
            if self.hello.get("dual") == "1":
                return
            if "char" in fields or "stat.damage" in fields:
                self._state(fields)         # (a duel's first round post carries the state it was played with)
            opened = ahk_tick(f.get("open"), tk)
            at = opened if opened is not None and abs(opened - tk) < 120000 else tk
            self.posts.append({"tk": tk, "at": at, "open": opened if opened is not None and abs(opened - tk) < 120000
                               else None, "f": f, "lines": lines, "dropped": dropped})
        else:
            self.counts["bad_post"] += 1

    def _who(self, tk, f):
        if "bot" not in f and "acting" not in f:
            return
        t = ahk_tick(f.get("tk"), tk) if f.get("tk") else None
        t = t if t is not None and abs(t - tk) < 60000 else tk
        self.who.append({"tk": t, "bot": 0 if f.get("bot") == "0" else 1, "acting": 1 if f.get("acting") == "1" else 0,
                         "pfm": 1 if f.get("pfm") == "1" else 0})

    def _state(self, f):
        S = self.state
        for k, names in (("char", ("char",)), ("school", ("school", "stat.school")), ("name", ("name",)),
                         ("role_set", ("party.role_set", "role_set", "roleset")),
                         ("mode", ("party.mode", "partymode"))):
            for a in names:
                if f.get(a):
                    S[k] = f[a]
                    break
        own = f.get("party.own", f.get("own"))
        if own is not None:
            S["own"] = [x.strip() for x in re.split(r"[|,]", own) if x.strip()][:16]
        st = dict(S.get("stats") or {})
        for k in STAT_KEYS:
            for a in ("stat." + k, "stats." + k, "stat_" + k):
                if a in f:
                    # (a blank one - Stats without the key: unknown, null)
                    st[k] = (f[a] or None) if k == "school" else _n(f[a]) if str(f[a]).strip() != "" else None
                    break
        if st:
            if "charid_ok" in st and st["charid_ok"] is not None:
                st["charid_ok"] = bool(st["charid_ok"]) if not isinstance(st["charid_ok"], str) else \
                    st["charid_ok"] not in ("0", "")
            S["stats"] = st
        sets = dict(S.get("settings") or {})
        for k, v in f.items():
            key = None
            for pre in ("set.", "setting.", "cfg."):
                if k.startswith(pre):
                    key = k[len(pre):]
            if key is None and k in SETTINGS_KEYS:
                key = k
            if key in SETTINGS_KEYS:
                sets[key] = _n(v) if str(v).strip() != "" else None
        if sets:
            S["settings"] = sets
        bel = dict(S.get("belief") or {})
        for k, names in (("id", ("deck.id", "deck_id", "deckid")), ("name", ("deck.name", "deck_name", "deckname")),
                         ("school", ("deck.school",)), ("set", ("deck.set",)),
                         ("why", ("deck.why", "deck_why", "deckwhy")), ("eqset", ("deck.eqset", "eqset"))):
            for a in names:
                if a in f:
                    bel[k] = (f[a] or None) if k not in ("eqset", "set") else _n(f[a] or None)
                    break
        if bel:
            S["belief"] = bel

    def _hello(self, tk, f, implicit=False):
        if not implicit:
            self.hello_seen = True
        elif not self.said_implicit:
            self.said_implicit = True
            self._log("battlerec: the bot posts with no hello (the helper restarted?) - recording")
        was_on = self.on
        prev_log = self.hello.get("log")
        for k in ("on", "log", "ver", "navmem", "dual"):
            if k in f:
                self.hello[k] = f[k]
        self._state(f)
        self._who(tk, f)
        on = self.hello.get("on", "1") != "0" and self.hello.get("dual") != "1"
        if on and (not was_on or self.broken):
            self.broken = None
            self.started = False
            self.store.set_why("")
        elif on and self.hello.get("log") != prev_log and self.started:
            self.started = False
        if not on and was_on:
            self._checkpoint()
        self.on = on

    def _game_running(self):
        try:
            import navmem
            return bool(navmem.find_pids())
        except Exception:  # noqa: BLE001
            return True

    # ------------------------------------------------------------------ the start: current.json and the back-scan
    def _log_path(self):
        p = self.hello.get("log") or ""
        if p and os.path.basename(p).lower() == "wizardclient.log" and os.path.isfile(p):
            return p
        nav = self._nav()
        gd = getattr(nav, "game_dir", "") if nav is not None else ""
        if gd:
            p = os.path.join(gd, "Bin", "WizardClient.log")
            if os.path.isfile(p):
                return p
        return None

    def _find_log(self, now):
        path = self._log_path()
        if not path:
            self.store.set_why("no game log")
            if now - self.no_log_said > 60000 or not self.no_log_said:
                self.no_log_said = now
                self._log("battlerec: no game log to read (WizardClient.log) - nothing recorded")
            return
        self.store.set_why("")
        self.tail = Tail(path)
        self._resume(now)

    def _begin(self, now):
        self.started = True
        self.parser = Parser()
        self.tail = None
        if not self.store_loaded:
            self.store.load()
            self.store_loaded = True
            self.store.next_maintain = now + 60000
        self._find_log(now)

    def _load_ckpt(self):
        p = os.path.join(self.dir, "current.json")
        try:
            with open(p, encoding="utf-8") as f:
                ck = json.load(f)
            if not isinstance(ck, dict) or ck.get("v") != 1:
                raise ValueError("not a checkpoint")
            return ck
        except FileNotFoundError:
            return None
        except (OSError, ValueError) as e:
            try:
                os.replace(p, os.path.join(self.dir, "current.bad.json"))
            except OSError:
                pass
            self._log("battlerec: current.json couldn't be read (%r) - kept as current.bad.json" % (e,))
            return None

    def _resume(self, now):
        """the log looked at once: a checkpoint of this log continued, a duel in progress rebuilt, else from the end"""
        look = self.tail.look()
        if look is None:
            self.tail = None
            return
        head, size = look
        ck = self._load_ckpt()
        if ck:
            for rec in ck.get("pending") or []:
                self.store.add(rec)
            for w in ck.get("who") or []:
                self.who.append(w)
            dk = ck.get("deck")
            if dk and dk.get("r") and self.deck["r"] is None:
                self.deck.update(r=dk["r"], tk=dk.get("tk"), at=dk.get("at"),
                                 sig=tuple(dk["sig"]) if isinstance(dk.get("sig"), list) else dk.get("sig"),
                                 zone=dk.get("zone"), why="")
        same = ck is not None and ck.get("head") == head.hex() and os.path.normcase(ck.get("path") or "") == \
            os.path.normcase(self.tail.path)
        if same and ck.get("pos") is not None and 0 <= size - ck["pos"] <= BACKSCAN:
            self.parser.load(ck.get("parser") or {})
            for h in ck.get("hands") or []:
                self.hands.append(h)
            for b in ck.get("battles") or []:
                self.battles.append(b)
            d = self.parser.duel
            if d is not None:
                self.attached[d["num"]] = list(ck.get("posts") or [])
                self.mobinfo[d["num"]] = dict(ck.get("mobinfo") or {})
                if ck.get("sig_ok") is not None:
                    self.sig_ok[d["num"]] = ck["sig_ok"]
            self.tail.head, self.tail.pos = head, ck["pos"]
            return
        if ck and (ck.get("parser") or {}).get("duel"):
            # (the duel of the checkpoint isn't in this log - the game restarted too: written as it was, cut)
            p = Parser()
            p.load(ck["parser"])
            d = p.duel
            if d is not None:
                self.attached[d["num"]] = list(ck.get("posts") or [])
                self.mobinfo[d["num"]] = dict(ck.get("mobinfo") or {})
                for h in ck.get("hands") or []:
                    self.hands.append(h)
                p.close(d, forced="cut", note="the helper stopped mid-battle and the duel's end isn't in the game's log"
                        if not same else "the helper stopped mid-battle; the duel is too far back in the game's log")
                self.parser.closed.extend(p.closed)
        try:
            zone, char, prog, _ = back_scan(self.tail.path, size, self._pace)
        except OSError:
            zone, char, prog = None, None, None
        self.parser.zone, self.parser.char = zone, char
        self.tail.head = head
        if prog is not None:
            self.tail.pos = prog[1]
            self.partial_why[prog[0]] = "the helper restarted"
        else:
            self.tail.pos = size

    # ------------------------------------------------------------------ the log
    def _pace(self):
        """the recorder's own Python work gives way: a gated request in flight - sleep till it's over (1 s at most)"""
        g = self.gate
        if g.n > 0:
            t0 = time.monotonic()
            while g.n > 0 and time.monotonic() - t0 < 1.0:
                time.sleep(0.002)
        else:
            time.sleep(0)

    def _tail(self, now):
        got = self.tail.read()
        if got is None:
            if now - self.logread_said > 60000 or not self.logread_said:
                self.logread_said = now
                self._log("battlerec: the game's log couldn't be read (%s) - said once a minute" % self.tail.path)
            return
        state, base, data = got
        if state == "new":
            self.parser.close_all("left", "the game's log started again (the game closed)")
        elif state == "skip":
            d = self.parser.duel
            if d is not None and d["skipped_from"] is None:
                d["skipped_from"] = (self.parser.cur(d)["n"] + 1) if d["rounds"] else 1
            self._log("battlerec: fell behind the game's log - jumped to its last 4 MB")
        if not data:
            return
        wall = self.clock.wall()
        off = 0
        g = self.gate
        p = self.parser
        k = 0
        for raw in data.split(b"\n"):
            pos = base + off
            off += len(raw) + 1
            k += 1
            if k % 10 == 0:
                self.k_live += 10
                # (a gated request in flight - a memory read the bot or the walker waits on: given the GIL at once)
                if g.n > 0:
                    if g.entered != self._seen_entered:
                        self._seen_entered = g.entered
                        self.counts["gate_waits"] += 1
                    self._pace()
                elif k % 50 == 0:
                    time.sleep(0)
            m = ANY.search(raw)
            if m is None:
                continue
            st, w = stamp_of(raw[:17].decode("ascii", "replace"))
            if w is None:
                continue
            tk = int(min(now, now - (wall - w) * 1000.0 + 1000))
            try:
                p.feed(raw, tk, pos, (wall - w) < LIVE_S, m)
            except Exception as e:  # noqa: BLE001 - that line only (a value written oddly): left out, the rest goes on
                self.counts["bad_lines"] += 1
                self._say_once("bad_line", "battlerec: a game log line couldn't be read (%s) - left out (said once)" %
                               type(e).__name__)
        self.counts["lines"] += k

    def _events(self):
        for ev, n in self.parser.events:
            d = self.parser.duel
            if ev in ("round", "closed", "duel"):
                self.ckpt_due = True
            if ev == "preplan_first" and d is not None and d["num"] == n:
                self.pre_due = n
        self.parser.events = []

    # ------------------------------------------------------------------ joins
    def _attach(self, now):
        """each waiting bot post to its duel (the open one, or one just closed) once the log shows its round"""
        if not self.posts:
            return
        keep = []
        cands = ([self.parser.duel] if self.parser.duel is not None else []) + list(self.parser.closed)
        for p in self.posts:
            pd = str(p["f"].get("duel") or "")
            hit = None
            for d in cands:
                if pd and pd != str(d["num"]) and any(str(x["num"]) == pd for x in cands):
                    continue
                if any(r["plan_tk"] is not None and r["plan_tk"] - POST_PRE_MS <= p["at"] for r in d["rounds"]) and \
                        (d["tk1"] is None or p["at"] <= d["tk1"] + POST_POST_MS):
                    hit = d
            if hit is not None:
                self.attached[hit["num"]].append(p)
            elif now - p["tk"] > POST_WAIT_MS:
                self.counts["orphans"] += 1
            else:
                keep.append(p)
        self.posts = keep

    def _bot_playing(self, now):
        """the latest who-state: the bot on and you not playing - also when nothing's known (no hello yet)"""
        if not self.who:
            return True
        e = self.who[-1]
        return e["bot"] == 1 and e["acting"] == 0

    def _hand_in(self, r):
        lo = (r["plan_tk"] or 0) - HAND_PRE_MS
        return any(h["tk"] >= lo for h in self.hands)

    # ------------------------------------------------------------------ own reads (only when the bot can't be reading)
    def _windows(self, now):
        if not self.mem_ok():
            return
        d = self.parser.duel
        if d is not None:
            n = d["num"]
            if getattr(self, "pre_due", None) == n and d["plannings"] == 0 and self.gate.idle(0.1):
                self.pre_due = None
                self._first_preplanning(now, d)
            r = self.parser.cur(d)
            if r is None or r["closed"] or d["phase"] != "Planning" or r["exec_tk"] is not None or \
                    r["cast_tk"] is not None or r["plan_tk"] is None:
                return
            if self._bot_playing(now) or self._hand_in(r) or now < r["plan_tk"] + OWN_FIRST_MS:
                return
            t = self.own_try.setdefault((n, r["k"]), [0, 0])
            if t[0] >= OWN_TRIES or now < t[1] or not self.gate.idle(0.1):
                return
            t[0] += 1
            t[1] = now + OWN_EVERY_MS
            nav = self._nav()
            if nav is None or not hasattr(nav, "cards"):
                return
            self.own.append((now, "cards", self.gate.n, d["phase"], self._bot_playing(now)))
            try:
                hr, why = nav.cards(want_effects=False, wait=0)
            except Exception as e:  # noqa: BLE001
                hr, why = None, "the hand couldn't be read (%r)" % (e,)
            if hand_key(hr) is not None:
                self._hand(self.clock.tk(), hr, "rec")
            else:
                self.own_why[n][r["k"]] = "the recorder's own read: " + ((hr or {}).get("why") or why or "not settled")
            return
        # out of battle
        last = self.last_close if self.last_close is not None else -OUT_IDLE_MS
        if now - last < OUT_IDLE_MS or not self.gate.idle(0.1):
            return
        D = self.deck
        nav = self._nav()
        if nav is None or not hasattr(nav, "deck"):
            return
        want = D["r"] is None or self.parser.zone != D["zone"] or (D["due"] and now >= D["due"])
        if not want and now >= D["sig_next"] and hasattr(nav, "deck_sig"):
            D["sig_next"] = now + DECK_SIG_MS
            self.own.append((now, "deck_sig", self.gate.n, None, None))
            try:
                sig, _ = nav.deck_sig()
            except Exception:  # noqa: BLE001
                sig = None
            want = sig is not None and sig != D["sig"]
        if not want or now < D.get("retry", 0):
            return
        self.own.append((now, "deck", self.gate.n, None, None))
        go = time.monotonic()
        # (it gives way - its lock let go, not taken again - when a battle's /cards or /battle comes, or after
        # DECK_READ_S: the log isn't looked at while it reads)
        stop = lambda: self.fight_at >= go or time.monotonic() - go > DECK_READ_S   # noqa: E731
        try:
            r, why = nav.deck(fresh=True, wait=0, idle=self.gate.idle, stop=stop)
        except Exception as e:  # noqa: BLE001
            r, why = None, "the deck couldn't be read (%r)" % (e,)
        D["due"] = 0
        if r is None or not r.get("decks"):
            D["why"] = why or (r or {}).get("why") or "no deck read"
            soon = "once" in (D["why"] or "") or (D["why"] or "").startswith("gave way")
            D["retry"] = now + (3000 if soon else 30000)   # (its reader being made, or it gave way: soon)
            return
        D.update(r=r, tk=self.clock.tk(), at=time.strftime("%Y-%m-%d %H:%M:%S", time.localtime(self.clock.wall())),
                 zone=self.parser.zone,
                 sig=r.get("sig"), why="")
        eq = next((x for x in r.get("decks") or [] if x.get("equipped")), None)
        for c in (eq or {}).get("cards") or []:
            if c.get("template_id"):
                self.store.note_card(card_fact(c, full=False))

    def _first_preplanning(self, now, d):
        nav = self._nav()
        if nav is None:
            return
        gids = [a["gid"] for a in d["adds"] if a.get("gid")]
        if hasattr(nav, "mob_infos") and gids:
            self.own.append((now, "mob_infos", self.gate.n, d["phase"], None))
            try:
                got = nav.mob_infos([int(g) for g in gids]) or {}
                self.mobinfo[d["num"]] = {str(g): slim_info(i) for g, i in got.items() if i}
            except Exception:  # noqa: BLE001
                pass
        if hasattr(nav, "deck_sig") and self.deck["sig"] is not None:
            self.own.append((now, "deck_sig", self.gate.n, d["phase"], None))
            try:
                sig, _ = nav.deck_sig()
                self.sig_ok[d["num"]] = sig is not None and sig == self.deck["sig"]
            except Exception:  # noqa: BLE001
                pass

    # ------------------------------------------------------------------ closed duels -> records
    def _env(self, d):
        n = d["num"]
        lo, hi = (d["tk0"] or 0) - 2000, (d["tk1"] or self.clock.tk()) + 2000
        S = self.state
        nav = self._nav() if self.mem_ok() else None
        build = None
        try:
            st = getattr(nav, "st", None)
            build = st.m.build if st is not None else None
        except Exception:  # noqa: BLE001
            build = None
        if self.chars is None:
            self.chars = {}
            try:
                with open(os.path.join(self.root, "resources", "characters.txt"), encoding="utf-8",
                          errors="replace") as f:
                    for ln in f:
                        m = re.match(r"^(\d+)\|(\w+)", ln)
                        if m:
                            self.chars[m.group(1)] = m.group(2)
            except OSError:
                pass
        deck = None
        D = self.deck
        if D["r"] is not None:
            deck = deck_field(D, d, self.sig_ok.get(n), S.get("belief"))
        else:
            deck = {"src": None, "why": D["why"] if self.mem_ok() else "the memory reading is off (navmem:0)",
                    "belief": S.get("belief")}
        mem_src = "on" if self.mem_ok() else ("off (navmem:0)" if self.hello.get("navmem") == "0" else
                                              "off (no helper reader)")
        return {"state": S, "hello": self.hello, "own": S.get("own") or [], "posts": self.attached.pop(n, []),
                "hands": [h for h in self.hands if lo <= h["tk"] <= hi],
                "battles": [b for b in self.battles if lo <= b["tk"] <= hi], "who": list(self.who),
                "mobinfo": self.mobinfo.pop(n, {}), "deck": deck, "stats": S.get("stats"),
                "settings": S.get("settings") or {}, "chars": self.chars, "build": build, "mem_src": mem_src,
                "ahk_src": "on" if self.hello else "no hello", "own_why": self.own_why.pop(n, {}),
                "hand_why": None if self.mem_ok() else "the memory reading is off (navmem:0)",
                "partial_why": self.partial_why.pop(n, None), "displays": self._displays()}

    def _displays(self):
        """{tid: display name} of the cards known (cards.jsonl's facts this run) - played matched by it after the name"""
        return dict(self.store.displays)

    def _close_duels(self, now):
        while self.parser.closed:
            d = self.parser.closed.pop(0)
            if self.hello.get("dual") == "1":
                continue
            # (its waiting posts first)
            for p in list(self.posts):
                if any(r["plan_tk"] is not None and r["plan_tk"] - POST_PRE_MS <= p["at"] for r in d["rounds"]) and \
                        (d["tk1"] is None or p["at"] <= d["tk1"] + POST_POST_MS) and \
                        (not p["f"].get("duel") or str(p["f"]["duel"]) == str(d["num"])):
                    self.attached[d["num"]].append(p)
                    self.posts.remove(p)
            env = self._env(d)
            rec = build_record(d, env)
            self.store.add(rec)
            self.last_result = rec["result"]
            self.last_close = now
            self.deck["due"] = now + DECK_AFTER_MS
            self.sig_ok.pop(d["num"], None)
            for k in [k for k in self.own_try if k[0] == d["num"]]:
                del self.own_try[k]
            self.ckpt_due = True

    def _checkpoint(self):
        """current.json: my open duel (parsed), its pieces (posts, hands, /battle copies, mob infos), the deck reading,
        the who-state and the battles not written yet - with the log position they go with"""
        d = self.parser.duel
        own = set(self.state.get("own") or ())
        lo = ((d["tk0"] or 0) - 2000) if d else None
        hide = hidden_names(d, own) if d else []
        D = self.deck
        ck = {"v": 1, "path": self.tail.path if self.tail else None,
              "head": self.tail.head.hex() if self.tail and self.tail.head else None,
              "pos": self.tail.pos if self.tail else None, "parser": self.parser.save(own),
              "posts": [dict(x, lines=scrub(x["lines"], hide)) for x in self.attached.get(d["num"], [])] if d else [],
              "hands": [h for h in self.hands if lo is not None and h["tk"] >= lo],
              "battles": [b for b in self.battles if lo is not None and b["tk"] >= lo],
              "mobinfo": self.mobinfo.get(d["num"], {}) if d else {},
              "sig_ok": self.sig_ok.get(d["num"]) if d else None, "who": list(self.who)[-50:],
              "deck": {k: D[k] for k in ("r", "tk", "at", "sig", "zone")} if D["r"] is not None else None,
              "pending": [item[0] for item in self.store.pending], "saved": time.strftime("%Y-%m-%d %H:%M:%S")}
        os.makedirs(self.dir, exist_ok=True)
        return replace_text(os.path.join(self.dir, "current.json"), dumps(ck))

    def _flush(self, now):
        if self.ckpt_due:
            if self._checkpoint():
                self.ckpt_due = False
        if self.store.pending or self.store.cards_new or self.store.dirty_today:
            n0 = len(self.store.pending)
            self.store.flush(now)
            if len(self.store.pending) != n0:
                self.ckpt_due = True
            if self.store.pending:
                self.ckpt_due = True
        if now >= self.store.next_maintain and self.parser.duel is None:
            self.store.next_maintain = now + MAINTAIN_MS
            try:
                self.store.maintain(self._pace)
            except Exception as e:  # noqa: BLE001
                self._say_once("maintain", "battlerec: the old months couldn't be zipped (%r)" % (e,))


def deck_field(D, d, sig_ok, belief):
    r = D["r"]
    eq = next((x for x in r.get("decks") or [] if x.get("equipped")), None)
    age = secs(D["tk"], d["tk0"]) if D["tk"] is not None and d["tk0"] is not None else None
    if eq is None:
        return {"src": None, "why": r.get("why") or "no deck worn", "belief": belief}
    cards = eq.get("cards") or []
    return {"src": "mem", "at": D["at"], "age_s": age, "sig_ok": sig_ok, "gid": str(eq.get("gid")),
            "object": eq.get("object_name"), "display": eq.get("display"), "school": eq.get("school"),
            "set": r.get("equipped_set"), "limits": eq.get("limits"),
            "main": [[c.get("template_id"), c.get("count"), c.get("enchantment_id") or 0] for c in cards
                     if c.get("side") == "main"],
            "tc": [[c.get("template_id"), c.get("count"), c.get("enchantment_id") or 0] for c in cards
                   if c.get("side") == "treasure"],
            "items": [[c.get("template_id"), c.get("count"), c.get("from")] for c in eq.get("item_cards") or []],
            "excl": [[c.get("template_id"), c.get("count")] for c in eq.get("excluded") or []],
            "main_n": eq.get("main_n"), "tc_n": eq.get("treasure_n"), "item_n": eq.get("item_n"),
            "why": "; ".join(x for x in (r.get("why"), eq.get("why")) if x), "belief": belief}


def start(root, nav=None, log=None, gate=None, clock=None):
    """the recorder, its thread running (idle till the bot's hello says on=1)"""
    return Recorder(root, nav=nav, log=log, gate=gate, clock=clock).start()
