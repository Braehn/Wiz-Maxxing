"""Party: up to 4 wizards, one per PC on the same home network - the leader quests, the followers go where it goes
(TODO goal 1). State only: where each wizard is and what it's doing - nothing one bot sends can make another press,
click, buy or type anything. Its battle part (hitter, blader, healer), its wizard's in-game name, school and hits steer
one thing: a blader's or healer's boosts go to the hitter's plate - found on its own screen by that name, among the
names the game's own log gives for its own side.

  * Each bot's helper reads its own wizard's zone and position (the game's memory, read-only) every BEAT s, and keeps
    what its AutoFarmer says (/party: in battle, health %, ready, walking, bot on, why it's holding).
  * The leader's helper serves the LAN (0.0.0.0, the party port - a server of its own: none of the helper's other
    requests can be reached from the LAN): GET /party/beat?... - a follower's state in, the leader's (and the other
    followers') out, as JSON. Only from private addresses; every field checked.
  * A follower's helper calls the leader's every BEAT s in its own thread (AutoFarmer never waits on the network).
  * The leader's "door": when it changes zone, the last spot in the zone it left and which way it was going there -
    a follower in that zone walks there and on through. Each is marked walked (it moved WALK_MIN units or more in the
    DOOR_WINDOW s before it left - its readings while zoning, navmem's 'object' ones, left out) or not (it stood still:
    End, Home, a sigil, a potion run, a friend's teleport - no door a follower can walk through); the last MAX_DOORS are
    kept with their ages, so a follower two zones behind still has the door out of its own zone (A -> B -> C: a follower
    in A walks A -> B, then B -> C). Walked or not isn't checked in the game yet: Party.ahk only logs it, and walks to
    the door all the same, unless Settings' partytpdoors is on.
  * The leader's loading flag and how long it's been in its zone go to the followers too, and port_advice() says when a
    follower should teleport to it (TODO goal 1 - the Friends list's Teleport; the AutoHotkey side decides and clicks).
  * A follower's teleport state (tp: wait - it can't follow -, stuck, porting, refused) goes to the leader, which stops
    waiting for one that can't follow.
  * The leader's battle spot: where it stood when its battle started - followers walk into the circle there.
  * partyorders (TODO goal 3 - advice only): a follower's hand (what its own AutoFarmer read - its helper keeps it, no
    read of its own) goes to the leader once the leader asks ('hands' in its answer - an older leader never does); the
    leader's planner plans the team with it and each follower's card comes back in its own answer ('order') - its bot
    only logs it.
Never sent: the game's login, anything from Credential Manager, the character's id, file paths, screenshots, gold."""
import http.client
import ipaddress
import json
import math
import random
import re
import socket
import threading
import time
import urllib.parse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

PORT = 47140            # the leader's LAN port (a setting)
BEAT = 0.4              # how often each helper reads its wizard and (a follower) calls the leader
STALE = 10.0            # a follower not heard from this long is dropped
MAX_FOLLOWERS = 3
LOG_EVERY = 60.0        # the same party log line at most this often (s)
REBIND_JOIN = 1.0       # s a new server on the port of one still closing waits for it (in a thread of its own)...
REBIND_TRIES = 6        # ...then its bind tried this many times...
REBIND_GAP = 0.25       # ...this far apart (s): about 1.5 s in all
REBIND_RECENT = 3.0     # an old server on the port closed this recently (s): the new one's bind is waited and retried too
FRESH = 3.0             # s a reading of the wizard's place is good for (older: its zone not known - a loading screen?)
MAX_DOORS = 3           # the leader's last doors kept and sent (a follower behind by up to that many zones)
DOOR_WINDOW = 1.5       # s before a zone change its trail is looked at: the door's way on, and walked or not...
WALK_MIN = 60.0         # ...walked: this many units or more covered in it (walking is ~1000 units a second - Walker.ahk;
                        # stood still before End / Home / a sigil / a friend's teleport: 0)
WALK_SPAN_MIN = 0.3     # less trail than this (s) before the change: walked not known (None)
PORT_ZONE_AGE = 3.0     # s the leader has been in its zone before a follower should teleport to it (not mid-arrival)
LEADER_FRESH = 5.0      # s since the leader's answer: older, nothing's decided on it (as Party.ahk's 5 s)
TP_STATES = ('wait', 'stuck', 'porting', 'refused')     # a follower's tp ('' following)
MAX_PATH = 1024         # the longest request the leader's server takes (characters): a longer beat gets a 403
NAME_RE = re.compile(r"^[\w .'-]{1,24}$")
ZONE_RE = re.compile(r"^[\w/\\ .'-]{1,120}$")
HOLD_RE = re.compile(r"^[\w .,'()/-]{0,80}$")
ROLES = ('hitter', 'blader', 'healer')
SCHOOLS = ('storm', 'fire', 'myth', 'balance', 'ice', 'life', 'death')
# (partyorders - TODO goal 3, advice only: a follower's hand to the leader, the leader's card for it back)
MAX_PATH_HANDS = 2048   # the leader's server with partyorders on: a beat with a 9-card hand is ~1972 at its worst
HAND_FRESH = 40.0       # s a follower's hand is good for (a 30 s planning phase and the reads)
ORDER_FRESH = 20.0      # s the leader's order for a follower is good for
MAX_CARDS = 9           # a hand's cards sent (7 and a pet's, a treasure card or two)
TAG_RE = re.compile(r'd(\d{1,9})r(\d{1,3})')     # a follower's own key for its hand: its AutoFarmer's duel and log round
KIND_RE = re.compile(r'[a-z]{1,16}')               # a card's kind (handmem's: damage, aoe, blade, enchantother...)
MARK_RE = re.compile(r'[a-z]{1,10}')               # what the simulator reads off a card's name: resh, tower, an enchant
TARGET_RE = re.compile(r"[A-Za-z0-9 .'-]{1,40}")   # the enemy an order is aimed at (its name - no ( ) : | or line break)
# (a marker: no order for a follower's hand this round, and why - a code; the follower says it in its own words)
MARK_WHYS = ('late', 'old', 'noplay', 'noplan')
MARK_TEXT = {'late': "the leader planned this round before this wizard's hand got there",
             'old': "the leader had only an old hand of this wizard's",
             'noplay': "the team's plan gave this wizard no play",
             'noplan': "the leader's round went another way - no team plan this round"}


def _f(v):
    """a finite float within reach of any zone, else None"""
    try:
        x = float(v)
    except (TypeError, ValueError):
        return None
    return x if math.isfinite(x) and abs(x) < 1e6 else None


def _flag(v):
    return '1' if str(v) == '1' else '0'


def clean_state(q):
    """a wizard's state from a request's fields - only these, each checked (a wrong one: blank)"""
    s = {}
    name = (q.get('name') or '').strip()
    s['name'] = name if NAME_RE.match(name) else ''
    zone = (q.get('zone') or '').strip()
    s['zone'] = zone if ZONE_RE.match(zone) else ''
    for k in ('x', 'y', 'z', 'yaw'):
        s[k] = _f(q.get(k))
    for k in ('battle', 'ready', 'walk', 'bot', 'loading'):
        s[k] = _flag(q.get(k))
    hp = _f(q.get('hp'))
    s['hp'] = None if hp is None or not 0 <= hp <= 100 else round(hp)
    hold = (q.get('hold') or '').strip()
    s['hold'] = hold if HOLD_RE.match(hold) else ''
    # (its battle part, its wizard's in-game name, its school, its hits and the log's round of the last - a blader's or
    # healer's boosts go to the hitter's plate, found on its own screen by that name among its own side's in the log)
    brole = str(q.get('brole') or '').strip()
    s['brole'] = brole if brole in ROLES else ''
    wiz = str(q.get('wiz') or '').strip()
    s['wiz'] = wiz if NAME_RE.match(wiz) else ''
    sch = str(q.get('school') or '').strip().lower()
    s['school'] = sch if sch in SCHOOLS else ''
    for k in ('hits', 'hitr'):
        v = _f(q.get(k))
        s[k] = int(v) if v is not None and 0 <= v < 1e6 else None
    # (the hitter's planned hit's schools - its supports boost for them - and its last hit's: a support's blades that fit
    # none of those stay on it; the seven schools only, each once)
    for k in ('plan', 'lasthit'):
        seen = []
        for p in str(q.get(k) or '').lower().split(','):
            p = p.strip()
            if p in SCHOOLS and p not in seen:
                seen.append(p)
        s[k] = ','.join(seen)
    # (a follower's teleport state - TODO goal 1: '' following; wait - it can't follow (the leader went where no door it
    # walked through leads from here, or its door didn't take it); stuck - five stuck tries on the way; porting - the
    # Friends list's teleport under way; refused - the game said no. And why, as the leader's hold is checked)
    tp = str(q.get('tp') or '').strip()
    s['tp'] = tp if tp in TP_STATES else ''
    tpwhy = str(q.get('tpwhy') or '').strip()
    s['tpwhy'] = tpwhy if s['tp'] and HOLD_RE.match(tpwhy) else ''
    # (the party's hit round - TODO goal 3, v1.0.0: the hitter's planned hit's round in its game's log, the earliest it can
    # go out - its supports time their blades and traps to it, Party.ahk PartyHitHold -, and each wizard's seat in the
    # battle: its subcircle 4-7, the cast order of our side. None: not said - an older bot, no hit planned)
    v = _f(q.get('hitat'))
    s['hitat'] = int(v) if v is not None and v == int(v) and 1 <= v <= 99 else None
    v = _f(q.get('seat'))
    s['seat'] = int(v) if v is not None and v == int(v) and 4 <= v <= 7 else None
    return s


def _walked(v):
    """a door's walked flag as sent (True / 1 / '1', False / 0 / '0'), else None (not known - an older helper)"""
    if v is True or v is False:
        return v
    if str(v) in ('1', '0'):
        return str(v) == '1'
    return None


def _ms(v):
    """an age in ms as sent: a whole number from 0 up to ~11 days, else None. (Not _f: its 1e6 - a zone's reach - is 16.7
    minutes in ms: a leader that long in its zone, or a door that old, read as no age - "an older version" - and the
    teleport advice never came)"""
    if isinstance(v, bool):
        return None
    try:
        x = float(v)
    except (TypeError, ValueError):
        return None
    return int(x) if math.isfinite(x) and 0 <= x < 1e9 else None


def clean_door(door):
    """one of the leader's doors as a follower got it, each field checked: {zone, to, x, y, z, dx, dy, walked, age} or
    None (not a door)"""
    if not isinstance(door, dict):
        return None
    z, to = str(door.get('zone') or ''), str(door.get('to') or '')
    # (fullmatch: a trailing newline - which $ lets by - would break the lines AutoHotkey reads)
    d = {'zone': z if ZONE_RE.fullmatch(z) else '', 'to': to if ZONE_RE.fullmatch(to) else '',
         **{k: _f(door.get(k)) for k in ('x', 'y', 'z', 'dx', 'dy')}}
    d['walked'], d['age'] = _walked(door.get('walked')), _ms(door.get('age'))
    return d


def door_from(zone, doors):
    """the leader's door out of zone: the latest of its doors (oldest first) left from there - the way its path went on
    from zone the last time it was in it; None when none was (or zone isn't known)"""
    if not zone:
        return None
    for d in reversed(doors or []):
        if isinstance(d, dict) and d.get('zone') == zone:
            return d
    return None


def walked_before(trail):
    """how the wizard left a zone, from its trail there [(t, zone, x, y, z) ...], oldest first: (walked, moved, span, back)
    - walked True when it covered WALK_MIN units or more in the last DOOR_WINDOW s (walking through a door), False when it
    didn't (it stood still: a teleport - End, Home, a sigil, a potion run, a friend's), None when there's too little of its
    trail to tell (under WALK_SPAN_MIN s); moved the units covered, span the s looked at, back the trail point the door's
    way on is measured from"""
    if not trail:
        return None, 0.0, 0.0, None
    last = trail[-1]
    win = [p for p in trail if last[0] - p[0] <= DOOR_WINDOW]
    # (readings far apart - a slow read -: the one before too)
    if len(win) < 2 and len(trail) >= 2:
        win = trail[-2:]
    span = last[0] - win[0][0]
    moved = sum(math.hypot(b[2] - a[2], b[3] - a[3]) for a, b in zip(win, win[1:]))
    if span < WALK_SPAN_MIN:
        return None, moved, span, win[0]
    return moved >= WALK_MIN, moved, span, win[0]


def still_for(trail, tol=1.0):
    """how long (s) the wizard's place hadn't moved (more than tol units) at the end of its trail [(t, zone, x, y, ...)]:
    0.0 when its last reading had moved. (For the log: a door walked through whose last readings stood still - the game
    keeping the old zone into the loading screen, its place frozen, with a body - is how WALK_MIN / DOOR_WINDOW would go
    wrong)"""
    if not trail:
        return 0.0
    last = trail[-1]
    t0 = last[0]
    for p in reversed(trail[:-1]):
        if math.hypot(p[2] - last[2], p[3] - last[3]) > tol:
            break
        t0 = p[0]
    return last[0] - t0


def port_advice(me_zone, leader, now):
    """should a follower teleport to its leader now (the Friends list's Teleport - TODO goal 1)? ('1', why) or ('0', why).
    me_zone: the follower's own zone ('' not known); leader: its view of the leader (Party.leader: zone, loading, zage -
    ms in its zone as sent -, doors, at - when heard), now: time.time(). Yes only when the leader's been heard from in
    LEADER_FRESH s, its zone is known and isn't the follower's, it isn't loading, it's been there PORT_ZONE_AGE s or more
    (not mid-arrival - or about to go on), and no door it walked through leads on from the follower's zone (one whose
    walked isn't known - an older leader's helper - counts as walked: tried as ever). Pure: Party.ahk decides (the setting,
    the game in front, you not playing, a try at most once a minute...) and clicks. why: words for the log and the status
    - no |"""
    if not isinstance(leader, dict) or not leader:
        return '0', 'the leader not heard from'
    heard = now - (leader.get('at') or 0)
    if heard > LEADER_FRESH:
        return '0', f'the leader not heard from in {heard:.0f} s'
    lz = leader.get('zone') or ''
    if not lz:
        return '0', "the leader's zone isn't known (loading?)"
    if not me_zone:
        return '0', "this wizard's zone isn't known (loading?)"
    if lz == me_zone:
        return '0', 'in the same zone'
    if str(leader.get('loading')) == '1':
        return '0', 'the leader is loading'
    zage = leader.get('zage')
    if zage is None:
        return '0', "the leader's helper doesn't say how long it's been in its zone (an older version)"
    zage += max(0.0, heard) * 1000
    if zage < PORT_ZONE_AGE * 1000:
        return '0', f'the leader only just got to {lz} ({zage / 1000:.0f} s ago)'
    d = door_from(me_zone, leader.get('doors'))
    if d is not None and d.get('walked') is not False:
        return '0', f"a door the leader walked through leads on from here (to {d.get('to') or '?'})"
    if d is not None:
        return '1', f"the leader teleported from here (to {d.get('to') or '?'}) and is in {lz} - no door to walk through"
    return '1', f'the leader is in {lz} - no door it walked through leads there from here'


def clean_peer(d):
    """the leader's state as a follower got it (its answer: each field checked again - nothing in it reaches AutoFarmer
    unchecked)"""
    d = d if isinstance(d, dict) else {}
    s = clean_state({k: str(v) for k, v in d.items() if isinstance(v, (str, int, float))})
    s['door'] = clean_door(d.get('door'))
    # (its last doors, oldest first, with their ages and walked - an older leader's helper sends only the last: that one,
    # walked and age not known)
    doors = d.get('doors')
    if isinstance(doors, list):
        s['doors'] = [c for c in (clean_door(x) for x in doors[-MAX_DOORS:]) if c is not None]
    else:
        s['doors'] = [s['door']] if s['door'] else []
    # (ms it's been in its zone - None not known: an older helper, or its zone isn't read)
    s['zage'] = _ms(d.get('zage'))
    b = d.get('bspot')
    s['bspot'] = tuple(_f(v) for v in b[:3]) if isinstance(b, (list, tuple)) and len(b) >= 3 else None
    return s


# ---------------------------------------------------------------- partyorders (TODO goal 3 - advice only)
def name_key(s):
    """a wizard's name as the plates and the log are matched by (Walker.ahk WalkLetters): its letters in capitals, the
    digits OCR takes for letters turned back (0 O, 1 I, 5 S, 8 B); only a-z made capitals - every other letter goes, as
    in AutoHotkey"""
    s = ''.join(c.upper() if 'a' <= c <= 'z' else c for c in str(s or ''))
    for a, b in (('0', 'O'), ('1', 'I'), ('5', 'S'), ('8', 'B')):
        s = s.replace(a, b)
    return re.sub(r'[^A-Z]', '', s)


def _int_in(v, lo, hi):
    """v as an int when it is one (not a bool) and lo <= v <= hi, else None"""
    return v if isinstance(v, int) and not isinstance(v, bool) and lo <= v <= hi else None


def _num_in(v, lo, hi):
    """int(v) when v is a number (int or float, not a bool) with lo <= v < hi, else None"""
    if isinstance(v, bool) or not isinstance(v, (int, float)):
        return None
    return int(v) if lo <= v < hi else None


def hand_of(r):
    """the hand a follower sends its leader, from a handmem HandMem.read() reading (what its own AutoFarmer's /cards
    read - no read here): {hp, max, pips, power, cards: [{tid, kind, pips, school, value, ench, mark, gi, name}]} - pips
    and power as /plan counts them (vision.py plan_lines_for: shadow pips left out); each card's plain value (the
    enchant not in it - its damage enchant is ench, as /plan's card_of reads it), mark what the simulator reads off its
    name (resh, tower, an enchant's word - the name itself never travels), gi its place in the game's hand and name its
    name (both local only: never sent). None: not a settled hand in a planning phase, or no card left (the hand not
    known - never an empty hand). Never raises"""
    try:
        if not isinstance(r, dict) or not (r.get('in_battle') and r.get('planning') and r.get('settled')):
            return None
        from battlesim import ENCHANT_RE, RESH_RE, TOWER_RE     # (the simulator's own name checks - one source)
        me = r.get('me') if isinstance(r.get('me'), dict) else {}
        pp = me.get('pips') if isinstance(me.get('pips'), dict) else {}

        def pip(k):
            v = pp.get(k)
            return int(v) if isinstance(v, (int, float)) and not isinstance(v, bool) and v > 0 else 0
        school = str(me.get('school') or '').lower()
        cards = []
        for gi, c in enumerate(r.get('cards') or []):
            if len(cards) >= MAX_CARDS:
                break
            if not isinstance(c, dict) or not c.get('name'):
                continue
            tid = c.get('template_id')
            if not isinstance(tid, int) or isinstance(tid, bool) or not 0 <= tid < 10 ** 10:
                continue
            kind = str(c.get('kind') or '').lower()
            if not KIND_RE.fullmatch(kind):
                continue
            ench = None
            if kind in ('damage', 'aoe'):
                m = re.search(r"kModifyCardDamage\s*\+?(\d{1,4})", str(c.get('ench_effect') or ''))
                ench = int(m.group(1)) if m else None
            txt = '%s %s' % (c.get('name') or '', c.get('display') or '')
            em = ENCHANT_RE.search(txt) if kind == 'enchant' else None
            mark = ('resh' if RESH_RE.search(txt) else 'tower' if kind == 'ward' and TOWER_RE.search(txt)
                    else em.group(1).lower() if em else '')
            cards.append({'tid': tid, 'kind': kind, 'pips': _int_in(c.get('pips'), 0, 14),
                          'school': re.sub('[^a-z]', '', str(c.get('school') or '').lower())[:12],
                          'value': re.sub(r"[^\w%+/.-]", '', str(c.get('value_text') or ''), flags=re.A)[:24],
                          'ench': ench, 'mark': mark, 'gi': gi, 'name': str(c.get('display') or c.get('name'))[:40]})
        if not cards:
            return None
        return {'hp': _num_in(me.get('health'), 0, 1e6), 'max': _num_in(me.get('max_health'), 1, 1e6),
                'pips': pip('generic') + pip('power') + sum(pip(s) for s in SCHOOLS),
                'power': pip('power') + (pip(school) if school in SCHOOLS else 0), 'cards': cards}
    except Exception:  # noqa: BLE001 - the hand not known
        return None


def _card_cells(c):
    """a hand card as the wire has it: tid:kind:pips:school:value[:ench[:mark]] - the empty cells after the 5th left off"""
    cells = ['' if c.get(k) is None else str(c.get(k)) for k in ('tid', 'kind', 'pips', 'school', 'value', 'ench', 'mark')]
    while len(cells) > 5 and cells[-1] == '':
        cells.pop()
    return ':'.join(cells)


def mates_hand(cards):
    """a hand's cards as /plan's mates= hand field takes them (vision.py plan_mates) - the same text the follower sent, in
    the same order"""
    return ';'.join(_card_cells(c) for c in cards or [] if isinstance(c, dict))


def hand_wire(stash, now):
    """a follower's beat's hand: tag~round~age~hp~max~pips~power~cards (cards: mates_hand's) - round its stash's (the
    battle recorder's, else its tag's), age ms since it was read (the PCs' clocks differ: only ages travel), None as ''"""
    h = stash['hand']
    return '~'.join([stash['tag'], str(stash['round']), str(max(0, round((now - stash['at']) * 1000))),
                     '' if h.get('hp') is None else str(h['hp']), '' if h.get('max') is None else str(h['max']),
                     str(h.get('pips') or 0), str(h.get('power') or 0), mates_hand(h.get('cards'))])


def clean_hand(text):
    """a follower's hand as the leader got it (its beat's 'hand' - hand_wire's), each cell checked: {tag, round, age, hp,
    max, pips, power, cards: [{tid, kind, pips, school, value, ench, mark}]}, or None (not known: a bad tag, round or
    age, or no card left). Never raises"""
    try:
        if not isinstance(text, str) or not text:
            return None
        f = (text.split('~') + [''] * 8)[:8]
        if not TAG_RE.fullmatch(f[0]) or not re.fullmatch(r'\d{1,3}', f[1]) or not 1 <= int(f[1]) <= 999:
            return None
        age = _ms(f[2])
        if age is None:
            return None

        def num(v, lo, hi, d=None):
            return int(v) if re.fullmatch(r'\d{1,7}', v) and lo <= int(v) <= hi else d
        cards = []
        for item in f[7].split(';')[:MAX_CARDS]:
            c = (item.split(':') + [''] * 7)[:7]
            if not re.fullmatch(r'\d{1,10}', c[0]) or not KIND_RE.fullmatch(c[1]):
                continue
            cards.append({'tid': int(c[0]), 'kind': c[1], 'pips': int(c[2]) if re.fullmatch(r'\d{1,2}', c[2]) else None,
                          'school': c[3] if re.fullmatch(r'[a-z]{0,12}', c[3]) else '',
                          'value': c[4] if re.fullmatch(r'[\w%+/.-]{0,24}', c[4], re.A) else '',
                          'ench': int(c[5]) if re.fullmatch(r'\d{1,4}', c[5]) else None,
                          'mark': c[6] if MARK_RE.fullmatch(c[6]) else ''})
        if not cards:
            return None
        return {'tag': f[0], 'round': int(f[1]), 'age': age, 'hp': num(f[3], 0, 1000000), 'max': num(f[4], 1, 1000000),
                'pips': num(f[5], 0, 14, 0), 'power': num(f[6], 0, 14, 0), 'cards': cards}
    except Exception:  # noqa: BLE001 - not known
        return None


def clean_ask(v):
    """the leader's ask for this follower's hand as it got it (its answer's 'hands'): {max - the longest beat its server
    takes, MAX_PATH to MAX_PATH_HANDS -, got - the tag of the hand it holds, or ''}, or None (no ask: an older leader,
    or one with partyorders off or unable to plan)"""
    try:
        if not isinstance(v, dict):
            return None
        m = v.get('max')
        if isinstance(m, bool) or not isinstance(m, (int, float)) or not math.isfinite(m):
            return None
        got = v.get('got')
        return {'max': max(MAX_PATH, min(MAX_PATH_HANDS, int(m))),
                'got': got if isinstance(got, str) and TAG_RE.fullmatch(got) else ''}
    except Exception:  # noqa: BLE001 - no ask
        return None


def clean_order(o):
    """the leader's order for this follower as it got it (its answer's 'order'), each field checked: {tag, duel, round,
    kind, i, tid, target, won, n, age, why} - tag '' a marker (no order for its hand this round: why one of MARK_WHYS,
    duel the duel of its hand's tag); None not an order (a key it doesn't know - an older or newer leader's - dropped).
    Nothing in it is logged but target, and that only when it's one of the follower's own log names (Party.ahk)"""
    try:
        if not isinstance(o, dict) or _int_in(o.get('round'), 1, 999) is None:
            return None
        tag = o.get('tag')
        if tag in (None, ''):
            tag = ''
        elif not isinstance(tag, str) or not TAG_RE.fullmatch(tag):
            return None
        duel = o.get('duel')
        duel = str(duel) if duel is not None and not isinstance(duel, bool) and isinstance(duel, (str, int)) else ''
        kind = o.get('kind')
        kind = kind if isinstance(kind, str) and KIND_RE.fullmatch(kind) else ''
        tid = o.get('tid')
        if isinstance(tid, str) and re.fullmatch(r'\d{1,10}', tid):
            tid = int(tid)
        target = o.get('target')
        why = o.get('why')
        d = {'tag': tag, 'duel': duel if re.fullmatch(r'\d{1,9}', duel) else '', 'round': o['round'], 'kind': kind,
             'i': _int_in(o.get('i'), 0, 8), 'tid': _int_in(tid, 0, 10 ** 10 - 1),
             'target': target if isinstance(target, str) and (target == 'all' or TARGET_RE.fullmatch(target)) else '',
             'won': _int_in(o.get('won'), 0, 100), 'n': _int_in(o.get('n'), 0, 1000000), 'age': _ms(o.get('age')),
             'why': why if tag == '' and why in MARK_WHYS else ''}
        if tag == '':
            return d if d['duel'] and d['why'] else None
        return d if d['kind'] else None
    except Exception:  # noqa: BLE001 - not an order
        return None


def order_cells(state, rnd='', card='', tid='', kind='', target='', won='', n='', age='', why=''):
    """/partyorder's line for AutoFarmer (Party.ahk PartyOrderRound): order|state|round|card|tid|kind|target|won|n|age|why
    - 11 fields, each with no | or line break in it (None as '')"""
    def cell(v):
        return '' if v is None else re.sub(r'[\r\n]', ' ', str(v)).replace('|', '/')
    return 'order|' + '|'.join(cell(v) for v in (state, rnd, card, tid, kind, target, won, n, age, why))


class PartyServer(ThreadingHTTPServer):
    """the leader's LAN server: its port its own (no address reuse - on Windows that lets a second server share it)"""
    allow_reuse_address = False
    daemon_threads = True

    def server_bind(self):
        if hasattr(socket, 'SO_EXCLUSIVEADDRUSE'):
            self.socket.setsockopt(socket.SOL_SOCKET, socket.SO_EXCLUSIVEADDRUSE, 1)
        super().server_bind()


class Party:
    """this PC's part of the party. reader(): the game's memory now - {'zone', 'pos', 'yaw'} or None"""

    def __init__(self, reader, log=print):
        self.reader, self.log = reader, log
        self.lock = threading.Lock()
        # (orders, plans: partyorders - '1' on, '' off; plans the leader's, while it can plan - Party.ahk PartyTick)
        self.cfg = {'role': 'off', 'name': '', 'leader': '', 'port': PORT, 'bind': '', 'orders': '', 'plans': ''}
        self.ahk = {}                       # what AutoFarmer said last (clean_state)
        self.ahk_at = 0.0
        self.mem = {}                       # zone, x, y, z, yaw, at - read here
        self.trail = []                     # (t, zone, x, y, z, zoning) of the last few seconds (the door) - zoning:
                                            # navmem's 'object' reading (the wizard has no body)
        self.door = None                    # {zone, x, y, z, dx, dy, to, walked, at}: the last spot in the zone left,
                                            # the way on
        self.doors = []                     # the last MAX_DOORS of those, oldest first (self.door the last)
        self.zone_at = 0.0                  # when its zone last changed (its first reading there)
        self.battle_spot = None             # (x, y, z) where its battle started
        self.members = {}                   # leader: follower id -> state (with 'at', 'ip')
        self.leader = None                  # follower: the leader's answer (with 'at')
        # (partyorders - TODO goal 3, advice only. A follower: its hand as its AutoFarmer last read it - {tag, round, at,
        # hand}: saw_hand -, the leader's ask for it - clean_ask -, the leader's order for it - clean_order, with
        # 'heard'. The leader: each follower's hand - clean_hand, with 'at' - and its order or marker for that
        # follower's next beat, by follower id. All of it this battle's only)
        self.stash, self.asked, self.order = None, None, None
        self.hands, self.orders = {}, {}
        self.state, self.why = 'off', ''
        self.server, self.server_key = None, None
        # (the server's lifecycle: one change at a time; the old servers still closing, by port - {port: [(thread, when
        # it closed or None)]}; which change a background bind belongs to)
        self.srv_lock = threading.RLock()
        self.closing = {}
        self.srv_gen = 0
        self.fails, self.next_beat = 0, 0.0
        self.id = '%08x' % random.getrandbits(32)
        self._said = {}                     # a log line -> (when it was last written, how many times it came since)
        threading.Thread(target=self._loop, name='party', daemon=True).start()

    def _log_once(self, msg, every=LOG_EVERY):
        """msg into the log - the same line again at most every `every` s, with how many times it came in between (a
        fault that repeats every beat: 2026-10-25's "'tuple' object has no attribute 'get'", 3 a second all evening)"""
        now = time.time()
        at, n = self._said.get(msg, (None, 0))
        if at is not None and now - at < every:
            self._said[msg] = (at, n + 1)
            return
        if len(self._said) > 50:
            self._said.clear()
        self._said[msg] = (now, 0)
        self.log(msg + (f' (and {n} times more in the last {every:.0f} s)' if n else ''))

    # ------------------------------------------------------------------ from AutoFarmer
    def update(self, q):
        """/party from AutoFarmer: its settings and state; the lines it shows (see vision.py's /party)"""
        role = q.get('role', 'off')
        role = role if role in ('off', 'leader', 'follower') else 'off'
        port = int(_f(q.get('port')) or PORT)
        port = port if 1024 <= port <= 65535 else PORT
        # (partyorders: this PC in the team's plan - plans: the leader's, only while it can plan; neither sent: off)
        orders = '1' if q.get('orders') == '1' else ''
        plans = '1' if q.get('plans') == '1' and orders == '1' else ''
        with self.lock:
            was_orders, was_plans = self.cfg.get('orders'), self.cfg.get('plans')
            was_at = (self.cfg.get('leader'), self.cfg.get('port'))
            self.cfg.update(role=role, port=port, leader=(q.get('leader') or '').strip()[:64],
                            name=clean_state(q)['name'], bind=q.get('bind', '') if q.get('bind') == '127.0.0.1' else '',
                            orders=orders, plans=plans)
            if was_orders == '1' and orders != '1':
                self.stash, self.asked, self.order = None, None, None
            if (self.cfg['leader'], self.cfg['port']) != was_at:
                # (pointed at another leader: the old one's ask and order aren't the new one's - its first beat as
                # before, the hand only once it asks. The leader's last answer kept as ever, and this wizard's own hand)
                self.asked, self.order = None, None
            if (was_orders == '1' and orders != '1') or (was_plans == '1' and plans != '1'):
                # (the leader stopped planning: its followers' next answers lack 'hands' - their waits end)
                self.hands, self.orders = {}, {}
            self.ahk, self.ahk_at = clean_state(q), time.time()
            if self.ahk['battle'] == '1' and self.battle_spot is None and self.mem.get('x') is not None:
                self.battle_spot = (self.mem['x'], self.mem['y'], self.mem['z'])
            elif self.ahk['battle'] != '1':
                self.battle_spot = None
            if self.ahk['battle'] != '1':
                # (partyorders: no hand or order outlives its battle - a follower's, a leader's)
                self.stash, self.order = None, None
                self.hands, self.orders = {}, {}
        self._serve()
        return self.lines()

    def _serve(self):
        """the leader's LAN server running (on its port) only while the role is leader. A change of the server wanted
        closes the old one in a thread (/party isn't held up: its shutdown takes up to half a second); a new one on the
        same port as one still closing - or just closed - is bound in a thread too, once the old one's gone (2026-10-26
        22:18:11: bound before the old socket was closed - "port 47140 taken or blocked")"""
        with self.lock:
            want = (self.cfg['bind'] or '0.0.0.0', self.cfg['port']) if self.cfg['role'] == 'leader' else None
        with self.srv_lock:
            if want == self.server_key:
                return
            self.srv_gen += 1
            gen = self.srv_gen
            if self.server is not None:
                srv, old = self.server, self.server_key
                self.server = None
                self._close_later(srv, old[1] if old else None)
            # (set now: a failure isn't tried again every call - a role or port change tries again)
            self.server_key = want
            if want is None:
                return
            if not self._closing_on(want[1]):
                self._start(want, gen, 1)
                return
        threading.Thread(target=self._start, args=(want, gen, REBIND_TRIES, True), name='party-bind', daemon=True).start()

    def _close_later(self, srv, port):
        """srv shut down and its socket closed in a thread (noted under its port till REBIND_RECENT s after)"""
        rec = [None, None]                  # the thread, when it had closed

        def close():
            try:
                srv.shutdown()
            except Exception:  # noqa: BLE001 - closed all the same
                pass
            try:
                srv.server_close()
            except OSError:
                pass
            rec[1] = time.monotonic()
        rec[0] = threading.Thread(target=close, name='party-close', daemon=True)
        if port is not None:
            self.closing.setdefault(port, []).append(rec)
        rec[0].start()

    def _closing_on(self, port):
        """the old servers on port still closing or closed under REBIND_RECENT s ago (the others forgotten)"""
        now = time.monotonic()
        for p in list(self.closing):
            keep = [r for r in self.closing[p] if r[1] is None or now - r[1] < REBIND_RECENT]
            if keep:
                self.closing[p] = keep
            else:
                del self.closing[p]
        return list(self.closing.get(port, ()))

    def _start(self, want, gen, tries, wait_old=False):
        """the leader's server bound on want - tries times REBIND_GAP s apart; wait_old: first the old ones on its port
        waited for (REBIND_JOIN s each at most). Not when the server wanted has changed meanwhile (gen)"""
        if wait_old:
            with self.srv_lock:
                old = self._closing_on(want[1])
            for rec in old:
                if rec[0] is not None and rec[0] is not threading.current_thread():
                    rec[0].join(REBIND_JOIN)
        err = None
        for i in range(max(1, tries)):
            with self.srv_lock:
                if gen != self.srv_gen:
                    return                  # (another change since: that one's own)
                try:
                    srv = PartyServer(want, self._handler())
                except OSError as e:
                    err = e
                else:
                    self.server = srv
                    threading.Thread(target=srv.serve_forever, name='party-server', daemon=True).start()
                    self.log(f'party: leader - serving the party on {want[0]}:{want[1]}'
                             + (f' (bound at try {i + 1})' if i else ''))
                    return
            if i + 1 < tries:
                time.sleep(REBIND_GAP)
        with self.srv_lock:
            if gen != self.srv_gen:
                return
            with self.lock:
                self.state, self.why = 'error', f'port {want[1]} taken or blocked ({err.strerror or err})'
            self.log(f'party: the leader\'s server can\'t start on port {want[1]} ({err!r})'
                     + (f' - {tries} tries' if tries > 1 else ''))

    def _handler(self):
        """the leader's server's request handler (GET /party/beat only, from private addresses)"""
        party = self

        class Handler(BaseHTTPRequestHandler):
            timeout = 3

            def log_message(self, *a):
                pass

            def do_GET(self):
                ip = self.client_address[0]
                try:
                    a = ipaddress.ip_address(ip)
                    ok = a.is_private or a.is_loopback or a.is_link_local
                except ValueError:
                    ok = False
                u = urllib.parse.urlparse(self.path)
                if not ok or len(self.path) > party.path_max() or u.path != '/party/beat':
                    self.send_response(403)
                    self.end_headers()
                    return
                q = {k: v[0] for k, v in urllib.parse.parse_qs(u.query).items()}
                body = json.dumps(party.beat_in(q, ip)).encode('utf-8')
                self.send_response(200)
                self.send_header('Content-Type', 'application/json')
                self.send_header('Content-Length', str(len(body)))
                self.end_headers()
                self.wfile.write(body)

        return Handler

    def stop(self):
        with self.srv_lock:
            # (a bind still waiting in its thread: not made now)
            self.srv_gen += 1
            srv, self.server, self.server_key = self.server, None, None
        if srv is not None:
            srv.shutdown()
            srv.server_close()

    # ------------------------------------------------------------------ state
    def _me(self):
        """this wizard's state to send: AutoFarmer's fields and the memory's place, the door (the last - as older helpers
        read it), the doors (the last MAX_DOORS, oldest first, each with its age in ms - the PCs' clocks differ - and
        walked), how long it's been in its zone (zage, ms - None while its zone isn't read), the battle spot"""
        with self.lock:
            now = time.time()
            s = dict(self.ahk)
            m = self.mem
            fresh = bool(m) and now - m.get('at', 0) < FRESH
            for k in ('zone', 'x', 'y', 'z', 'yaw'):
                s[k] = m.get(k) if fresh else (None if k != 'zone' else '')
            s['name'] = self.cfg['name']
            s['door'] = dict(self.door) if self.door else None
            s['doors'] = [dict({k: d.get(k) for k in ('zone', 'x', 'y', 'z', 'dx', 'dy', 'to', 'walked')},
                               age=max(0, round((now - d['at']) * 1000))) for d in self.doors]
            s['zage'] = max(0, round((now - self.zone_at) * 1000)) if fresh and self.zone_at else None
            s['bspot'] = self.battle_spot
        return s

    def beat_in(self, q, ip):
        """the leader's side of a follower's beat: it noted; the leader's state and the others' back. partyorders on
        and the leader able to plan (cfg plans): its hand kept (clean_hand - never in members, others or lines), and
        two keys after 'others' - hands (the ask: the longest beat taken, the tag of the hand held) and order (its own
        order or marker, ORDER_FRESH s) - which an older follower doesn't read. Off: the answer as before"""
        fid = re.sub(r'[^0-9a-f]', '', q.get('id', ''))[:16]
        s = clean_state(q)
        now = time.time()
        ask = order = None
        with self.lock:
            stored = False
            if fid and (fid in self.members or len(self.members) < MAX_FOLLOWERS):
                s.update(at=now, ip=ip)
                self.members[fid] = s
                stored = True
            others = [dict(v, age=round((now - v['at']) * 1000)) for k, v in self.members.items() if k != fid]
            if stored and self.cfg['role'] == 'leader' and self.cfg['orders'] == '1' and self.cfg['plans'] == '1':
                try:
                    if s['battle'] != '1':
                        # (that follower's battle is over: its hand and order go with it)
                        self.hands.pop(fid, None)
                        self.orders.pop(fid, None)
                    else:
                        h = clean_hand(q.get('hand'))
                        if h is not None:
                            self.hands[fid] = dict(h, at=now)
                    ask = {'max': MAX_PATH_HANDS, 'got': (self.hands.get(fid) or {}).get('tag', '')}
                    o = self.orders.get(fid)
                    if o and now - o['at'] <= ORDER_FRESH:
                        order = {k: o.get(k) for k in ('tag', 'duel', 'round', 'i', 'tid', 'kind', 'target', 'won', 'n',
                                                       'why')}
                        order['age'] = max(0, round((now - o['at']) * 1000))
                except Exception as e:  # noqa: BLE001 - the answer as before
                    ask = order = None
                    self._log_once(f'party: a follower\'s hand couldn\'t be taken ({e!r})')
        me = self._me()
        d = {'v': 1, 'leader': me, 'others': [{k: o.get(k) for k in
             ('name', 'zone', 'x', 'y', 'z', 'battle', 'hp', 'ready', 'walk', 'age', 'brole', 'wiz', 'school', 'hits',
              'hitr', 'plan', 'lasthit', 'tp', 'tpwhy', 'hitat', 'seat')} for o in others]}
        if ask is not None:
            d['hands'] = ask
            if order is not None:
                d['order'] = order
        return d

    def path_max(self):
        """the longest request the leader's server takes: MAX_PATH_HANDS with partyorders on (whether it plans or not -
        a hand already on its way when planning stops isn't refused), else MAX_PATH"""
        try:
            with self.lock:
                on = self.cfg['role'] == 'leader' and self.cfg.get('orders') == '1'
            return MAX_PATH_HANDS if on else MAX_PATH
        except Exception:  # noqa: BLE001 - as before
            return MAX_PATH

    def _beat_out(self):
        """a follower's beat to the leader (its own thread); a failure backs off and says why"""
        with self.lock:
            host, port = self.cfg['leader'], self.cfg['port']
        if not host:
            with self.lock:
                self.state, self.why = 'error', "no leader address (tray menu: Party...)"
            return
        if re.fullmatch(r'[\d.]+', host):
            try:
                if not ipaddress.ip_address(host).is_private:
                    with self.lock:
                        self.state, self.why = 'error', 'the leader address isn\'t a home-network one'
                    return
            except ValueError:
                with self.lock:
                    self.state, self.why = 'error', 'the leader address isn\'t an address'
                return
        q = self._beat_query()
        try:
            c = http.client.HTTPConnection(host, port, timeout=1.5)
            c.request('GET', '/party/beat?' + urllib.parse.urlencode(q))
            r = c.getresponse()
            body = r.read(16384)
            c.close()
            if r.status != 200:
                raise OSError(f'the leader answered {r.status}')
            d = json.loads(body.decode('utf-8'))
            if not isinstance(d, dict):
                raise ValueError('not an object')
            self._took(d, at=(host, port))
        except socket.timeout:
            self._fail('no answer - is that PC\'s bot the leader, and its firewall letting Python in (Private networks)?')
        except ConnectionRefusedError:
            self._fail('refused - that PC\'s bot isn\'t set to Leader, or the port is wrong')
        except OSError as e:
            self._fail(f'can\'t reach it ({e.strerror or e})')
        except (ValueError, http.client.HTTPException):
            self._fail('its answer couldn\'t be read')

    def _took(self, d, at=None):
        """a follower's side of the leader's answer d (a dict): the leader's state and the other followers', each field
        checked; partyorders on here: the leader's ask for its hand (clean_ask - None: an older leader, or one not
        planning) and its order (clean_order) - only from the leader it's pointed at now (at: the (host, port) the beat
        went to - an answer still on its way when the address changed asks nothing)"""
        with self.lock:
            others = []
            got = d.get('others') if isinstance(d.get('others'), list) else []
            for o in got[:MAX_FOLLOWERS]:
                if isinstance(o, dict):
                    c = clean_state({k: str(v) for k, v in o.items() if isinstance(v, (str, int, float))})
                    age = _f(o.get('age'))
                    c['age'] = int(age) if age is not None and 0 <= age < 1e6 else ''
                    others.append(c)
            self.leader = dict(clean_peer(d.get('leader')), at=time.time(), others=others)
            self.state, self.why, self.fails = 'following', '', 0
            self.asked, self.order = None, None
            if self.cfg['role'] == 'follower' and self.cfg.get('orders') == '1' \
                    and at in (None, (self.cfg['leader'], self.cfg['port'])):
                self.asked = clean_ask(d.get('hands'))
                o = clean_order(d.get('order'))
                self.order = dict(o, heard=time.time()) if o else None

    def _hand_out(self):
        """(the hand for this beat - hand_wire -, the longest beat the leader takes) or ('', 0): only a follower with
        partyorders on, in battle, its leader heard from in LEADER_FRESH s and asking (clean_ask), its hand under
        HAND_FRESH s old"""
        try:
            now = time.time()
            with self.lock:
                if self.cfg['role'] != 'follower' or self.cfg.get('orders') != '1' or self.ahk.get('battle') != '1':
                    return '', 0
                st, ask, L = self.stash, self.asked, self.leader
                if not st or not ask or not L or now - L.get('at', 0) > LEADER_FRESH or now - st['at'] > HAND_FRESH:
                    return '', 0
                return hand_wire(st, now), min(ask['max'], MAX_PATH_HANDS)
        except Exception:  # noqa: BLE001 - no hand this beat
            return '', 0

    def _beat_query(self):
        """a follower's beat's fields: its state (_me - its tp and tpwhy too) and its id; not its doors, battle spot or
        zone's age (the leader's to send - a list in a query would only make it longer: the leader's server takes
        MAX_PATH characters). Longer than that - a 120-character zone of backslashes, an 80-character hold and why of
        commas and apostrophes, 3 characters each in the URL: ~1300 - its why, then its hold, left out till it fits (~840
        without them, the hit round's hitat and seat in; the leader answered 403 to the whole beat, and the follower went
        'unreachable'). Still over: the seat, then hitat (the hit round not said: its supports cast as ever)"""
        q = {k: ('' if v is None else v) for k, v in self._me().items() if k not in ('door', 'doors', 'bspot', 'zage')}
        q['id'] = self.id
        # (partyorders: the hand last - only once the leader asks, and only while the whole beat fits what its server
        # takes; else left out first, and the beat as before)
        wire, cap = self._hand_out()
        if wire:
            qh = dict(q, hand=wire)
            if len('/party/beat?' + urllib.parse.urlencode(qh)) <= cap:
                return qh
        for k in ('tpwhy', 'hold', 'seat', 'hitat'):
            if len('/party/beat?' + urllib.parse.urlencode(q)) <= MAX_PATH:
                break
            q[k] = ''
        return q

    def _fail(self, why):
        with self.lock:
            self.fails += 1
            self.state, self.why = 'unreachable', why
            # (a 403 too: the next beat as before - no hand - till a good answer asks again)
            self.asked = None
            self.next_beat = time.time() + min(5.0, 0.5 * 2 ** min(self.fails, 4))

    def _loop(self):
        while True:
            t0 = time.time()
            try:
                self._read()
                with self.lock:
                    role = self.cfg['role']
                    for k in [k for k, v in self.members.items() if t0 - v['at'] > STALE]:
                        self.members.pop(k, None)
                    self._prune_orders(t0)
                    if role == 'leader' and self.server is not None:
                        self.state, self.why = 'serving', ''
                    elif role == 'off':
                        self.state, self.why = 'off', ''
                if role == 'follower' and t0 >= self.next_beat:
                    self._beat_out()
            except Exception as e:  # noqa: BLE001 - one bad beat mustn't end the thread (said once a minute)
                self._log_once(f'party: {e!r}')
            time.sleep(max(0.05, BEAT - (time.time() - t0)))

    def _read(self):
        """the wizard's zone and place (only while the party's on); the door when the zone changes"""
        with self.lock:
            if self.cfg['role'] == 'off':
                return
        r = self.reader()
        # (a reader answering navmem's (reading, why) pair: its reading)
        if isinstance(r, tuple):
            r = r[0] if r else None
        if not isinstance(r, dict) or not r.get('zone') or r.get('pos') is None:
            return
        now = time.time()
        x, y, z = r['pos'][:3]
        # (navmem's reading from the ClientObject's own copy of its place - it has no body: zoning. The game can keep the
        # old zone a while into the loading screen - Dungeons.ahk: "still in the zone it's leaving" -, its place frozen
        # at the doorway: that isn't standing still)
        zoning = r.get('source') == 'object'
        said = None
        with self.lock:
            last = self.trail[-1] if self.trail else None
            if last and last[1] != r['zone']:
                # (the zone changed: the last spot in the old one, and the way it was going there - from ~1.5 s before;
                # walked or not - it stood still: a teleport, no door a follower can walk through. Both from its readings
                # with a body: 1.5 s of frozen zoning reads made a door walked through a teleport, and its way on none.
                # All of them zoning: all, as before)
                old = [p for p in self.trail if p[1] == last[1]]
                body = [p for p in old if not (len(p) > 5 and p[5])] or old
                walked, moved, span, back = walked_before(body)
                nz, still = len(old) - len(body), still_for(old)
                dx, dy = last[2] - back[2], last[3] - back[3]
                n = math.hypot(dx, dy) or 1.0
                self.door = {'zone': last[1], 'x': last[2], 'y': last[3], 'z': last[4], 'dx': dx / n, 'dy': dy / n,
                             'to': r['zone'], 'walked': walked, 'at': now}
                self.doors = (self.doors + [self.door])[-MAX_DOORS:]
                self.trail = []
                said = (f'party: {last[1]} -> {r["zone"]}: '
                        + ('walked through a door' if walked else 'a teleport (it stood still)' if walked is False
                           else 'walked or not not known (too little of its trail)')
                        + f' - moved {moved:.0f} in the last {span:.1f} s'
                        + (f', still for the last {still:.1f} s' if still >= BEAT else '')
                        + (f' ({nz} zoning reads left out)' if nz else ''))
            if last is None or last[1] != r['zone']:
                self.zone_at = now
            self.trail.append((now, r['zone'], x, y, z, zoning))
            self.trail = [p for p in self.trail if now - p[0] <= 4.0]
            self.mem = {'zone': r['zone'], 'x': x, 'y': y, 'z': z, 'yaw': r.get('yaw'), 'at': now}
        if said:
            # (one line a zone change - how the doors are told apart, to check in the game: WALK_MIN, DOOR_WINDOW - and
            # whether its last readings in the old zone stand still with a body: "still for")
            self.log(said)

    # ------------------------------------------------------------------ partyorders (TODO goal 3 - advice only)
    def _prune_orders(self, t0):
        """(self.lock held) the leader's hands of followers no longer in members, and orders of those or older than
        ORDER_FRESH s, dropped"""
        for k in [k for k in self.hands if k not in self.members]:
            self.hands.pop(k, None)
        for k in [k for k, o in self.orders.items() if k not in self.members or t0 - o.get('at', 0) > ORDER_FRESH]:
            self.orders.pop(k, None)

    def _hand_fresh(self, h, now):
        """a follower's hand at the leader is HAND_FRESH s old or less (its age as sent and since it came)"""
        return (h.get('age') or 0) / 1000.0 + (now - h.get('at', 0)) <= HAND_FRESH

    def saw_hand(self, r, tag, local=None):
        """(vision.py /cards?ptag=, a follower's AutoFarmer's read of its own hand - no read here) the hand kept for the
        leader: {tag - the follower's own key, its AutoFarmer's duel and log round -, round - the battle recorder's round
        (local: vision.py rec_local's (duel, round) - its own duel only), else the tag's -, at, hand - hand_of}. Only a
        follower with partyorders on, in battle, a good tag and a settled hand (else the last one stays). Never raises"""
        try:
            m = TAG_RE.fullmatch(tag) if isinstance(tag, str) else None
            if not m:
                return
            h = hand_of(r)
            if h is None:
                return
            rnd = int(m.group(2))
            if isinstance(local, (tuple, list)) and len(local) >= 2 and _int_in(local[1], 1, 999) is not None:
                rnd = local[1]
            with self.lock:
                if self.cfg['role'] != 'follower' or self.cfg.get('orders') != '1' or self.ahk.get('battle') != '1':
                    return
                self.stash = {'tag': tag, 'round': rnd, 'at': time.time(), 'hand': h}
        except Exception as e:  # noqa: BLE001 - the last hand stays
            self._log_once(f'party: the hand couldn\'t be kept ({e!r})')

    def order_line(self, tag):
        """/partyorder?tag= for the follower's AutoFarmer (Party.ahk PartyOrderRound): order_cells' line - ok (the
        leader's card for this hand, named from this wizard's own hand as read - never the leader's text), wait (its hand
        on its way, or the leader has it and no order yet) or none (why: this PC's own words - a marker's code in them,
        the kind cell 'mark'). The round cell: the tag's round, the stash's once it's found. Never raises"""
        try:
            now = time.time()
            m = TAG_RE.fullmatch(tag) if isinstance(tag, str) else None
            rnd = int(m.group(2)) if m else ''
            with self.lock:
                if self.cfg['role'] != 'follower':
                    return order_cells('none', rnd, why="this PC isn't a follower")
                if self.cfg.get('orders') != '1':
                    return order_cells('none', rnd, why='partyorders is off on this PC')
                L = self.leader
                if not L or now - L.get('at', 0) > LEADER_FRESH:
                    return order_cells('none', rnd, why='the leader not heard from')
                if self.asked is None:
                    return order_cells('none', rnd, why="the leader's bot doesn't plan the team now (an older version, "
                                                        "partyorders or planner off there, its bot off or unable to read "
                                                        "the game)")
                st = self.stash
                if not m or not st or st['tag'] != tag or now - st['at'] > HAND_FRESH:
                    return order_cells('none', rnd, why="this wizard's hand wasn't read this round (navmem on, one game "
                                                        "window?)")
                rnd = st['round']
                o = self.order
                age = None
                if o:
                    age = (o.get('age') or 0) + (now - o['heard']) * 1000
                    if age > ORDER_FRESH * 1000:
                        o = None
                if o and o['tag'] and o['tag'] == tag and o['round'] == rnd:
                    return self._order_ok(o, st, age)
                if o and not o['tag'] and o['duel'] == m.group(1) and o['round'] == rnd:
                    return order_cells('none', rnd, kind='mark', why=MARK_TEXT.get(o['why'], ''))
                if self.asked.get('got') != tag:
                    return order_cells('wait', rnd, why='its hand is on its way to the leader')
                return order_cells('wait', rnd, why='the leader has its hand - no order yet')
        except Exception:  # noqa: BLE001 - said so
            return order_cells('none', why="the party's state couldn't be read")

    @staticmethod
    def _order_ok(o, st, age):
        """an order's ok line: its card named from the stash (the card at its place i with its tid, else the first with
        its tid - its own name, '(enchanted)' with a damage enchant on it), 'tid N' when none has it, 'pass'"""
        cards = st['hand'].get('cards') or []
        tid, why = o.get('tid'), ''
        if o.get('kind') == 'pass':
            card, tid = 'pass', ''
        else:
            i = o.get('i')
            c = cards[i] if isinstance(i, int) and 0 <= i < len(cards) and cards[i].get('tid') == tid else None
            if c is None:
                c = next((x for x in cards if tid is not None and x.get('tid') == tid), None)
            if c is not None:
                card = str(c.get('name') or '?') + (' (enchanted)' if c.get('ench') else '')
            else:
                card = 'tid %s' % ('?' if tid is None else tid)
                why = "not in this wizard's hand as last read"
        return order_cells('ok', st['round'], card, tid, o.get('kind'), o.get('target'), o.get('won'), o.get('n'),
                           '' if o.get('age') is None else round(age), why)

    def fill_mates(self, text, rnd):
        """(the leader's /plan with hands=party - vision.py plan_lines_for) /plan's mates= with each follower's hand,
        pips, power and health from the hand it sent for round rnd: (text, used, notes) - text the kept specs (plan_mates'
        walk: 3 at most, blank ones dropped - plan_team's who k is used[k - 1]), used per spec None (not one of the
        party's bots' hands) or {fid, tag ('' its hand not used - why late / old), duel, name}, notes why a mate's hand
        wasn't used (the leader's own words and names). Never raises"""
        try:
            text = text if isinstance(text, str) else ''
            kept = []
            for spec in text.split('|')[:12]:
                bits = (spec.split('~') + [''] * 9)[:9]
                if not any(b.strip() for b in bits):
                    continue
                if len(kept) >= 3:
                    break
                kept.append((spec, bits))
            with self.lock:
                if self.cfg['role'] != 'leader' or self.cfg.get('orders') != '1':
                    return text, [None] * len(kept), ["partyorders isn't on in this helper - the mates' hands not known"]
                now = time.time()
                out, used, notes = [], [], []
                for spec, bits in kept:
                    out.append(spec)
                    used.append(None)
                    name = re.sub(r'[^\w .\'-]', '', bits[0])[:24].strip()
                    key = name_key(bits[0])
                    if bits[8].strip() or len(key) < 3:
                        continue
                    seat = int(bits[1].strip()) if re.fullmatch(r'[4-7]', bits[1].strip()) else None
                    fids = [k for k, v in self.members.items() if name_key(v.get('wiz')) == key
                            and (seat is None or v.get('seat') is None or v.get('seat') == seat)]
                    if not fids:
                        notes.append("%s: not one of the party's bots - its hand not known" % name)
                        continue
                    fid = max(fids, key=lambda k: self.members[k].get('at', 0))
                    h = self.hands.get(fid)
                    if h is None:
                        notes.append('%s: no hand from its bot (an older version, partyorders off there, or its hand not '
                                     'read)' % name)
                        continue
                    hm = TAG_RE.fullmatch(h['tag'])
                    duel = hm.group(1) if hm else ''
                    if h['round'] != rnd:
                        notes.append("%s: its hand is round %s's, not this round's (%s) - played its role's way" % (
                            name, h['round'], rnd))
                        used[-1] = {'fid': fid, 'tag': '', 'duel': duel, 'name': name, 'why': 'late'}
                        continue
                    if not self._hand_fresh(h, now):
                        notes.append("%s: its hand is %.0f s old - played its role's way" % (
                            name, (h.get('age') or 0) / 1000.0 + (now - h.get('at', 0))))
                        used[-1] = {'fid': fid, 'tag': '', 'duel': duel, 'name': name, 'why': 'old'}
                        continue
                    nb = [bits[0], bits[1], bits[2], str(h['hp']) if h.get('hp') is not None else bits[3],
                          str(h['max']) if h.get('max') else bits[4], bits[5], str(h.get('pips') or 0),
                          str(h.get('power') or 0), mates_hand(h.get('cards'))]
                    out[-1] = '~'.join(nb)
                    used[-1] = {'fid': fid, 'tag': h['tag'], 'duel': duel, 'name': name}
                return '|'.join(out), used, notes
        except Exception as e:  # noqa: BLE001 - the mates as AutoFarmer sent them
            return (text if isinstance(text, str) else ''), [], ["the mates' hands couldn't be filled (%r)" % (e,)]

    def set_orders(self, orders, used, foe_names, rnd):
        """(the leader's /plan with hands=party, after plan_team) each follower's order for its next beat: its play
        (plan_team's order with who k + 1 - the card's place i in the hand it sent, its tid and kind, the enemy's name
        it's aimed at - 'all' an aoe -, won % and rollouts; never the card's name: the follower names it from its own
        hand) or a marker (tag '': why a code - late, old, noplay); nothing for a follower whose hand wasn't in. Only
        with partyorders on and the leader planning. Never raises"""
        try:
            now = time.time()
            with self.lock:
                if self.cfg['role'] != 'leader' or self.cfg.get('orders') != '1' or self.cfg.get('plans') != '1':
                    return
                for k, u in enumerate(used or []):
                    if not isinstance(u, dict) or not u.get('fid'):
                        continue
                    if u.get('tag') == '':
                        self.orders[u['fid']] = {'tag': '', 'duel': u.get('duel'), 'round': rnd, 'why': u.get('why'),
                                                 'at': now}
                        continue
                    o = next((x for x in orders or [] if isinstance(x, dict) and x.get('who') == k + 1), None)
                    if o is None:
                        self.orders[u['fid']] = {'tag': '', 'duel': u.get('duel'), 'round': rnd, 'why': 'noplay',
                                                 'at': now}
                        continue
                    aim = o.get('aim')
                    if o.get('kind') == 'aoe':
                        target = 'all'
                    elif isinstance(aim, int) and not isinstance(aim, bool) and 0 <= aim < len(foe_names or []):
                        target = re.sub(r"[^A-Za-z0-9 .'-]", '', str(foe_names[aim]))[:40].strip()
                    else:
                        target = ''
                    self.orders[u['fid']] = {'tag': u['tag'], 'round': rnd, 'i': o.get('i'), 'tid': o.get('tid'),
                                             'kind': o.get('kind'), 'target': target,
                                             'won': int(round(100 * float(o.get('won') or 0))), 'n': int(o.get('n') or 0),
                                             'why': '', 'at': now}
        except Exception as e:  # noqa: BLE001 - no orders this round
            self._log_once(f'party: the orders couldn\'t be kept ({e!r})')

    def no_plan(self, rnd):
        """(/partyorder?noplan=, the leader's AutoFarmer at its round's end) a 'noplan' marker for each follower whose
        fresh hand is for round rnd, in battle, with no order for that round yet - a round the leader didn't plan the
        team in, told at once. How many were marked (a round already covered: none - it may be asked every round). Never
        raises"""
        try:
            now = time.time()
            n = 0
            with self.lock:
                if self.cfg['role'] != 'leader' or self.cfg.get('orders') != '1' or self.cfg.get('plans') != '1':
                    return 0
                for fid, h in list(self.hands.items()):
                    mem = self.members.get(fid)
                    o = self.orders.get(fid)
                    if h.get('round') != rnd or not self._hand_fresh(h, now) or not mem or mem.get('battle') != '1' \
                            or (o and o.get('round') == rnd):
                        continue
                    hm = TAG_RE.fullmatch(h['tag'])
                    self.orders[fid] = {'tag': '', 'duel': hm.group(1) if hm else '', 'round': rnd, 'why': 'noplan',
                                        'at': now}
                    n += 1
            return n
        except Exception:  # noqa: BLE001 - none marked
            return 0

    def lead_count(self):
        """(/partyorder?lead=1, the leader's AutoFarmer - Party.ahk PartyOrderHands) how many followers' fresh hands this
        helper holds, each in battle; 0 unless a leader with partyorders on and planning. Never raises"""
        try:
            now = time.time()
            with self.lock:
                if self.cfg['role'] != 'leader' or self.cfg.get('orders') != '1' or self.cfg.get('plans') != '1':
                    return 0
                return sum(1 for fid, h in self.hands.items() if self._hand_fresh(h, now)
                           and (self.members.get(fid) or {}).get('battle') == '1')
        except Exception:  # noqa: BLE001 - none
            return 0

    # ------------------------------------------------------------------ to AutoFarmer
    def lines(self):
        """party|role|state|why; me|zone|x|y|z|yaw; leader|...; member|... (one per follower, the leader's view).
        AutoHotkey's fields (Party.ahk PartyTick - f[1] the line's kind): the leader's 2-31 as ever, then 32 loading,
        33 dwalk (the door below walked: 1, 0, '' not known), 34 zage (ms in its zone), 35 dage (the door's age, ms), 36
        port, 37 its why (port_advice), 38 hitat, 39 seat (the party's hit round - v1.0.0); a member's 2-21 as ever, then 22
        tp, 23 tpwhy, 24 hitat, 25 seat. The door (14-20): the leader's latest out of this wizard's zone (door_from), else
        its last as before. Old bots read only the fields they know (and pad the ones they don't: blank)"""
        def num(v, d=0):
            return '' if v is None else f'{v:.{d}f}'
        now = time.time()
        with self.lock:
            role, state, why = self.cfg['role'], self.state, self.why
            # (this wizard's place as last read - not when that's FRESH s old: a loading screen, its zone not known - as
            # _me sends it to the leader)
            m = self.mem if self.mem and now - self.mem.get('at', 0) < FRESH else {}
            out = [f'party|{role}|{state}|{why}',
                   f"me|{m.get('zone', '')}|{num(m.get('x'))}|{num(m.get('y'))}|{num(m.get('z'))}|{num(m.get('yaw'), 4)}"]
            if role == 'follower' and self.leader:
                L = self.leader
                age = round((now - L['at']) * 1000)
                dist = ''
                if L.get('zone') and L.get('zone') == m.get('zone') and L.get('x') is not None and m.get('x') is not None:
                    dist = f"{math.hypot(L['x'] - m['x'], L['y'] - m['y']):.0f}"
                doors = L.get('doors') or []
                d = door_from(m.get('zone'), doors) or (doors[-1] if doors else None) or L.get('door') or {}
                b = L.get('bspot') or (None, None, None)
                walked = d.get('walked')
                port, pwhy = port_advice(m.get('zone') or '', L, now)
                out.append('leader|' + '|'.join([
                    L.get('name') or '', L.get('zone') or '', num(L.get('x')), num(L.get('y')), num(L.get('z')),
                    num(L.get('yaw'), 4), L.get('battle', '0'), num(L.get('hp')), L.get('ready', '0'), L.get('walk', '0'),
                    str(age), dist, d.get('zone', ''), num(d.get('x')), num(d.get('y')), num(d.get('z')),
                    num(d.get('dx'), 3), num(d.get('dy'), 3), d.get('to', ''), num(b[0]), num(b[1]), num(b[2]),
                    L.get('hold') or '', L.get('brole') or '', L.get('wiz') or '', L.get('school') or '',
                    num(L.get('hits')), num(L.get('hitr')), L.get('plan') or '', L.get('lasthit') or '',
                    # (32-37: its loading flag; the door's walked, the leader's time in its zone and the door's age - each
                    # as sent and since that answer -; the teleport advice)
                    L.get('loading', '0'), '' if walked is None else ('1' if walked else '0'),
                    '' if L.get('zage') is None else str(L['zage'] + age),
                    '' if d.get('age') is None else str(d['age'] + age), port, pwhy.replace('|', '/'),
                    # (38-39: the hit round - its planned hit's log round, its seat)
                    num(L.get('hitat')), num(L.get('seat'))]))
                # (the other followers: as the leader's own rows below - walk, loading and hold where it doesn't say)
                for o in L.get('others') or []:
                    # (its age as the leader last heard it, and since that answer: a leader gone quiet takes them along)
                    oa = o.get('age')
                    out.append('member|' + '|'.join([o.get('name') or '', o.get('zone') or '', num(o.get('x')),
                               num(o.get('y')), num(o.get('z')), o.get('battle', '0'), num(o.get('hp')),
                               o.get('ready', '0'), str(oa + age) if isinstance(oa, int) else '', '', o.get('walk', '0'), '0', '',
                               o.get('brole') or '', o.get('wiz') or '', o.get('school') or '', num(o.get('hits')),
                               num(o.get('hitr')), o.get('plan') or '', o.get('lasthit') or '', o.get('tp') or '',
                               o.get('tpwhy') or '', num(o.get('hitat')), num(o.get('seat'))]))
            elif role == 'leader':
                for v in self.members.values():
                    dist = ''
                    if v.get('zone') and v['zone'] == m.get('zone') and v.get('x') is not None and m.get('x') is not None:
                        dist = f"{math.hypot(v['x'] - m['x'], v['y'] - m['y']):.0f}"
                    out.append('member|' + '|'.join([v.get('name') or '', v.get('zone') or '', num(v.get('x')),
                               num(v.get('y')), num(v.get('z')), v.get('battle', '0'), num(v.get('hp')),
                               v.get('ready', '0'), str(round((now - v['at']) * 1000)), dist, v.get('walk', '0'),
                               v.get('loading', '0'), v.get('hold') or '', v.get('brole') or '', v.get('wiz') or '',
                               v.get('school') or '', num(v.get('hits')), num(v.get('hitr')), v.get('plan') or '',
                               v.get('lasthit') or '', v.get('tp') or '', v.get('tpwhy') or '', num(v.get('hitat')),
                               num(v.get('seat'))]))
        return out
