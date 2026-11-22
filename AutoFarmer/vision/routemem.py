"""routemem - the walker's route memory: the walks to quest goals that went well, kept per zone, and the heat map they
make of the ways that worked - for the route planner (navroute.HEAT: those squares a little cheaper to walk - the
routeheat setting) and the dashboard's Map (an orange shade under the route); and a line for each quest followed.

READ-ONLY toward the game: it keeps only what vision.py's /nav already reads (route=1: the walker following the
quest's way). Nothing is sent to the game.

    rm = RouteMem(folder, log=print)
    rm.see(zone, pos, goal, target, clean=True, played=False, ahead=None, label=None)   # each /nav route reading
    rm.quest(qid, title, zone, goal)                    # ...and its quest
    rm.heat01(zone, x0, y0, nx, ny, cell)               # the heat (0-1) of a window's squares - None: nothing known

A leg: the walk to one goal in one zone - from the first reading with that goal (the game's ids for it) and a way to
it (target: where the quest's path leads - the goal itself, or the way out to the zone it's in) to the first reading
within ARRIVE of that. It's frozen there: what comes after - a fight at a "Defeat ..." goal (mob avoidance off),
walking about to a goal's things, a talk - isn't part of it. Kept (a success) when after that the goal moves on, the
way on moves, the zone changes or the wizard is moved (a knockout in the goal's fight: the walk there still went
well) - within AFTER_MAX. Dropped when it ends before arriving (a knockout, a recall, a teleport, the quest changed),
when you played or the bot or its walking was off on the way (played: the reading after says so), when a reading on
the way had mob avoidance off (walking into mobs on purpose), when it took longer than LEG_MAX to arrive, when nothing
was read for GAP_MAX before it arrived (the bot off), or when it was shorter than MIN_LEN.

Its weight - how well it went: eff = (the game's own path length from where it began, else the straight line, / the
length walked) x (the time spent walking / the time it took), at most 1. A detour, a wait for a mob to move off,
standing stuck and every battle on the way (the walker doesn't read /nav in one) lower it. An older leg weighs less:
halved every HALF_LIFE days.

A square's heat (CELL units across): of the legs that passed through it (or WIDE squares beside it - each leg once),
n = their weights summed (each counts 1, halved with age) and e = their weights times their eff; heat01 = e /
max(n, FULL) - the legs' mean eff once FULL of them have passed, less with fewer. So it says how well the walks that
way went, not only how often one did; the planner's discount on it (navroute.HEAT_DISCOUNT) only breaks near-ties.

Files (in folder - AutoFarmer\\routes\\heat\\, kept by the updater):
  <zone>.jsonl   one kept leg a line (JSON): t (when it ended, epoch s), goal (its line), from, to ([x, y]), s
                 (seconds to arrive), len (units walked), ahead (the game's path length at its start), eff, pts
                 ([[x, y], ...] - the trail, a point every STEP units). At most 2 x KEEP lines (then the newest KEEP
                 kept). Delete it to forget the zone - noticed at once, the bot running or not.
  quests.jsonl   one line a quest followed (by the game's id for it), written once another quest's id is read: t,
                 quest (its title), id, s (the seconds it was followed - its battles and waits in, a stop of more than
                 GAP_MAX not), span (first reading to last), zones and goals (in order), kept and dropped (its legs).
                 Over doesn't say done: you may have picked another quest. One followed under QUEST_MIN: not written.

Locks: the leg being walked has its own (see() - the walker's /nav - never waits for a zone's file being read or its
heat being built); a zone's legs and heat another, held only to look or swap; the files a third."""
import json
import math
import os
import re
import threading
import time

import numpy as np

CELL = 40.0             # game units per heat square (2 of the planner's)
WIDE = 1                # ...the squares this many beside the trail count too (the wizard's body, a route's slack)
STEP = 40.0             # a trail point kept each time the wizard is this far from the last one
ARRIVE = 400.0          # within this of where the quest's path leads: arrived (the leg frozen)
TARGET_MOVED = 400.0    # where it leads moved this far: another leg
JUMP = 1500.0           # the wizard this far from his last reading...
JUMP_S = 3.0            # ...after more than this (s - a battle, a knockout's respawn), or...
TELE_SPEED = 3000.0     # ...faster than this (units / s - no walk, even sped up): a teleport
MOVING = 150.0          # faster than this (units / s) between two readings JUMP_S or less apart: walking
GAP_MAX = 600.0         # nothing read for this long (s) before arriving: the leg dropped (the bot off, a long stop)
LEG_MAX = 900.0         # a leg taking longer than this (s) to arrive: dropped (it got stuck, or waited for you)
AFTER_MAX = 2700.0      # arrived, the goal not moving on in this long (s): dropped (it wasn't the goal after all)
MIN_LEN = 300.0         # walked less than this (units): not kept
HALF_LIFE = 14.0        # days: an older leg's weight halved every this many
KEEP = 300              # legs kept a zone
FULL = 3.0              # legs' weight at which a square's heat is their mean eff (fewer: less)
REBASE = 30.0           # days: a zone's heat built afresh this long after it was last (its weights' base time)
QUEST_MIN = 30.0        # a quest followed for less than this (s): not written to quests.jsonl
QUESTS = 'quests.jsonl'

_COUNT = re.compile(r'\(\s*\d+\s*of\s*\d+\s*\)', re.I)


def goal_key(text):
    """a goal as a leg's key: its "(n of m)" count left out (it goes up along the way), spaces and case evened"""
    return ' '.join(_COUNT.sub(' ', text or '').split()).lower()


def zone_file(folder, zone):
    """the zone's legs file in folder: <zone>.jsonl, every character but letters, digits, _ and - made _"""
    return os.path.join(folder, re.sub(r'[^\w-]', '_', zone) + '.jsonl')


def path_len(pos, path, goal):
    """the game's quest path's length (x / y) from pos through its nodes to goal - None without a goal"""
    if pos is None or goal is None:
        return None
    pts = [(pos[0], pos[1])] + [(p[0], p[1]) for p in (path or ())] + [(goal[0], goal[1])]
    return sum(math.hypot(b[0] - a[0], b[1] - a[1]) for a, b in zip(pts, pts[1:]))


def leg_eff(leg):
    """a kept leg's eff (0-1), as written - not a number: 0"""
    try:
        v = float(leg.get('eff', 0.0))
    except (TypeError, ValueError):
        return 0.0
    return max(0.0, min(1.0, v)) if math.isfinite(v) else 0.0


def leg_age_w(leg, base):
    """a kept leg's count at time base: 1 when it ended then, halved every HALF_LIFE days before it (more after) - None
    when its time isn't a number"""
    try:
        t = float(leg.get('t'))
    except (TypeError, ValueError):
        return None
    if not math.isfinite(t):
        return None
    return 0.5 ** ((base - t) / 86400.0 / HALF_LIFE)


def trail_cells(pts, x0, y0, nx, ny, cell=CELL, wide=WIDE):
    """the flat indices (j * nx + i) of the squares a trail passes through - or wide squares beside it - each once"""
    try:
        p = np.asarray(pts, dtype=float).reshape(-1, 2)
    except (TypeError, ValueError):
        return np.zeros(0, dtype=np.int64)
    p = p[np.isfinite(p).all(axis=1)]
    if not len(p):
        return np.zeros(0, dtype=np.int64)
    if len(p) > 1:
        seg = np.diff(p, axis=0)
        n = np.clip(np.ceil(np.hypot(seg[:, 0], seg[:, 1]) / (cell / 2.0)), 1, 1000).astype(np.int64)
        k = np.repeat(np.arange(len(seg)), n)                       # (each sample's segment)
        f = (np.arange(int(n.sum())) - np.repeat(np.cumsum(n) - n, n)) / n[k]
        s = np.vstack([p[k] + seg[k] * f[:, None], p[-1:]])
    else:
        s = p
    i = np.floor((s[:, 0] - x0) / cell).astype(np.int64)
    j = np.floor((s[:, 1] - y0) / cell).astype(np.int64)
    d = np.arange(-wide, wide + 1)
    ii = (i[:, None, None] + d[None, None, :] + 0 * d[None, :, None]).reshape(-1)
    jj = (j[:, None, None] + d[None, :, None] + 0 * d[None, None, :]).reshape(-1)
    ok = (ii >= 0) & (ii < nx) & (jj >= 0) & (jj < ny)
    return np.unique(jj[ok] * nx + ii[ok])


class ZoneHeat:
    """one zone's kept legs and their heat: n and e by CELL squares from (x0, y0), their weights as at base (epoch s)"""

    def __init__(self, legs=(), lines=0, stat=None):
        self.legs, self.lines, self.stat = list(legs), lines, stat     # (lines: in its file, bad ones too)
        self.n = self.e = None                                         # (None: to be built)
        self.x0 = self.y0 = self.base = 0.0
        self.ver = 0                                                   # (each change to legs: +1)

    def fits(self, pts):
        """whether a trail's squares (and WIDE beside) are all inside the heat built"""
        if self.n is None or not pts:
            return False
        a = np.asarray(pts, dtype=float).reshape(-1, 2)
        ny, nx = self.n.shape
        pad = (WIDE + 0.5) * CELL
        return bool(a[:, 0].min() - pad >= self.x0 and a[:, 1].min() - pad >= self.y0
                    and a[:, 0].max() + pad < self.x0 + nx * CELL and a[:, 1].max() + pad < self.y0 + ny * CELL)

    def add(self, leg):
        """one kept leg added to the heat built (it fits)"""
        w = leg_age_w(leg, self.base)
        if w is None:
            return
        ny, nx = self.n.shape
        idx = trail_cells(leg.get('pts') or (), self.x0, self.y0, nx, ny)
        self.n.reshape(-1)[idx] += w
        self.e.reshape(-1)[idx] += w * leg_eff(leg)


def build_heat(legs, base):
    """(n, e, x0, y0) for legs, their weights as at base - n None when there's no trail in them"""
    pts = []
    for leg in legs:
        try:
            a = np.asarray(leg.get('pts') or (), dtype=float).reshape(-1, 2)
        except (TypeError, ValueError):
            continue
        a = a[np.isfinite(a).all(axis=1)]
        if len(a):
            pts.append(a)
    if not pts:
        return None, None, 0.0, 0.0
    a = np.vstack(pts)
    pad = (WIDE + 2) * CELL
    x0, y0 = float(a[:, 0].min()) - pad, float(a[:, 1].min()) - pad
    nx = int(math.ceil((float(a[:, 0].max()) + pad - x0) / CELL))
    ny = int(math.ceil((float(a[:, 1].max()) + pad - y0) / CELL))
    if nx * ny > 4_000_000:             # (a stray point far off: 80000 units across - not a zone; not built)
        return None, None, 0.0, 0.0
    zh = ZoneHeat()
    zh.n, zh.e, zh.x0, zh.y0, zh.base = np.zeros((ny, nx)), np.zeros((ny, nx)), x0, y0, base
    for leg in legs:
        zh.add(leg)
    return zh.n, zh.e, x0, y0


class RouteMem:
    """the route memory: the leg being walked and the quest followed (lock), each zone's kept legs and heat (zlock -
    read from folder when first needed), the files (flock)"""

    def __init__(self, folder, log=print, clock=time.time):
        self.folder, self.log, self.clock = folder, log, clock
        self.lock = threading.Lock()
        self.zlock = threading.Lock()
        self.flock = threading.Lock()
        self.zones = {}         # zone: ZoneHeat
        self.leg = None         # the leg being walked (a dict), None none
        self.qs = None          # the quest being followed (a dict), None none

    # ---- the leg being walked

    def see(self, zone, pos, goal, target, clean=True, played=False, now=None, label=None, ahead=None):
        """one /nav route reading: the zone, the wizard's pos (x, y, z), the goal (what tells it from the next one: the
        game's ids for it - empty: as the last reading, and no leg begun), where the quest's path leads (target: x, y,
        z - None: no way known, no leg begun), clean (mob avoidance on in this reading), played (you played, or the bot
        or its walking was off, since the reading before), label (the goal's line, for the file and the log - else
        goal) and ahead (the game's path length from here: the leg's eff is measured against it). A line for the log
        when a leg ends (kept or dropped), else None"""
        now = self.clock() if now is None else now
        if not zone or pos is None:
            return None
        with self.lock:
            said = None
            leg = self.leg
            key = goal_key(goal)
            if leg is not None and played and leg['arrived'] is None:
                said = self._said(self._drop(leg, 'you played, or the bot or its walking was off on the way'))
                leg = self.leg = None
            if leg is not None:
                why = self._ends(leg, zone, pos, key, target, now)
                if why is not None:
                    # (the goal moved on - or its way did - right where the wizard stands: there, at this reading)
                    if why.startswith('done') and zone == leg['zone'] and leg['arrived'] is None and math.hypot(
                            pos[0] - leg['target'][0], pos[1] - leg['target'][1]) <= ARRIVE:
                        self._arrive(leg, pos, now)
                    said = self._said(self._end(leg, why, now))
                    leg = self.leg = None
            if leg is None and target is not None and key:
                leg = self.leg = {'zone': zone, 'key': key, 'goal': ' '.join((label or goal or '').split()), 'target': target,
                                  't0': now, 'last': now, 'at': pos, 'pts': [(pos[0], pos[1])], 'len': 0.0,
                                  'moving': 0.0, 'arrived': None, 'clean': bool(clean), 'ahead': ahead}
                if math.hypot(pos[0] - target[0], pos[1] - target[1]) <= ARRIVE:
                    self._arrive(leg, pos, now)
            elif leg is not None:
                self._step(leg, pos, target, clean, now)
            return said

    def _said(self, line):
        """the quest followed told how its leg went; the line"""
        if self.qs is not None and line:
            self.qs['kept' if ': kept the ' in line else 'dropped'] += 1
        return line

    def _ends(self, leg, zone, pos, key, target, now):
        """why the leg ends at this reading ('done: ...' - kept if it arrived - or 'drop: ...'), None it goes on"""
        dt = now - leg['last']
        step = math.hypot(pos[0] - leg['at'][0], pos[1] - leg['at'][1])
        there = leg['arrived'] is not None
        if not there and dt > GAP_MAX:
            return 'drop: nothing read for %.0f s' % dt
        if zone != leg['zone']:
            return 'done: into ' + zone
        if step > JUMP and (dt > JUMP_S or step / max(dt, 1e-3) > TELE_SPEED):
            return ('done' if there else 'drop') + ': the wizard moved %.0f in %.1f s (a teleport, a knockout)' % (step, dt)
        if key and key != leg['key']:
            return 'done: the goal moved on'
        if target is not None and math.hypot(target[0] - leg['target'][0], target[1] - leg['target'][1]) > TARGET_MOVED:
            return 'done: the way on moved'
        if not there and now - leg['t0'] > LEG_MAX:
            return 'drop: longer than %.0f s to get there' % LEG_MAX
        if there and now - leg['arrived'] > AFTER_MAX:
            return 'drop: there %.0f s and the goal not moving on' % (now - leg['arrived'])
        return None

    def _step(self, leg, pos, target, clean, now):
        dt = now - leg['last']
        step = math.hypot(pos[0] - leg['at'][0], pos[1] - leg['at'][1])
        leg['last'], leg['at'] = now, pos
        if leg['arrived'] is not None:
            return                                   # (frozen at its arrival: only the end's checks go on)
        if 0 < dt <= JUMP_S and step / dt > MOVING:
            leg['moving'] += dt
        leg['len'] += step
        if target is not None:
            leg['target'] = target
        last = leg['pts'][-1]
        if math.hypot(pos[0] - last[0], pos[1] - last[1]) >= STEP:
            leg['pts'].append((pos[0], pos[1]))
        if math.hypot(pos[0] - leg['target'][0], pos[1] - leg['target'][1]) <= ARRIVE:
            # (a reading that arrives may be the first of the goal's own: a fight's has mob avoidance off - not counted)
            self._arrive(leg, pos, now)
        else:
            leg['clean'] = leg['clean'] and bool(clean)

    def _arrive(self, leg, pos, now):
        leg['arrived'] = now
        last = leg['pts'][-1]
        if math.hypot(pos[0] - last[0], pos[1] - last[1]) > 1.0:
            leg['pts'].append((pos[0], pos[1]))

    def _drop(self, leg, why):
        return "route memory: dropped the leg in %s to '%s' - %s" % (leg['zone'], leg['goal'][:60], why)

    def _end(self, leg, why, now):
        """a leg over: kept (written to its zone's file) when it's a success, else dropped - the log's line"""
        if why.startswith('drop'):
            return self._drop(leg, why[6:])
        if leg['arrived'] is None:
            return self._drop(leg, why[6:] + ' with the wizard not there')
        if not leg['clean']:
            return self._drop(leg, 'mob avoidance was off on the way')
        if leg['len'] < MIN_LEN:
            return None
        took = max(1e-3, leg['arrived'] - leg['t0'])
        a, b = leg['pts'][0], leg['pts'][-1]
        ahead = leg['ahead']
        if ahead is None or not math.isfinite(ahead) or ahead <= 0:
            ahead = math.hypot(b[0] - a[0], b[1] - a[1])
        eff = min(1.0, ahead / max(leg['len'], 1e-3)) * min(1.0, leg['moving'] / took)
        kept = {'t': round(now, 1), 'goal': leg['goal'], 'from': [round(a[0]), round(a[1])], 'to': [round(b[0]), round(b[1])],
                's': round(took, 1), 'len': round(leg['len']), 'ahead': round(ahead), 'eff': round(eff, 3),
                'pts': [[round(x), round(y)] for x, y in leg['pts']]}
        where = "leg in %s to '%s'" % (leg['zone'], leg['goal'][:60])
        try:
            n = self._keep(leg['zone'], kept)
        except OSError as e:
            return 'route memory: the ' + where + " couldn't be written (%s)" % e
        return 'route memory: kept the %s - %.0f s, %.0f walked, eff %.2f%s' % (
            where, took, leg['len'], eff, '' if n is None else ' (%d legs there)' % n)

    # ---- the quest being followed

    def quest(self, qid, title, zone, goal, now=None):
        """one /nav route reading's quest: the game's id for it (None / '' / 0 - not read: as the last reading), its
        title, the zone, the goal's line. A line for the log when the quest followed before is over (another id read)
        and written to quests.jsonl, else None"""
        now = self.clock() if now is None else now
        if qid in (None, '', 0):
            return None
        qid = str(qid)
        with self.lock:
            q, said = self.qs, None
            if q is not None and q['id'] != qid:
                said = self._quest_over(q, now)
                q = self.qs = None
            if q is None:
                q = self.qs = {'id': qid, 'title': '', 't0': now, 'last': now, 's': 0.0, 'zones': [], 'goals': [],
                               'kept': 0, 'dropped': 0}
            dt = now - q['last']
            if 0 < dt <= GAP_MAX:
                q['s'] += dt
            q['last'] = now
            q['title'] = ' '.join((title or '').split()) or q['title']
            if zone and (not q['zones'] or q['zones'][-1] != zone):
                q['zones'].append(zone)
            line = ' '.join((goal or '').split())
            if line and (not q['goals'] or goal_key(q['goals'][-1]) != goal_key(line)):
                q['goals'].append(line)
            return said

    def _quest_over(self, q, now):
        if q['s'] < QUEST_MIN:
            return None
        line = {'t': round(now, 1), 'quest': q['title'], 'id': q['id'], 's': round(q['s']), 'span': round(q['last'] - q['t0']),
                'zones': q['zones'][:50], 'goals': q['goals'][:100], 'kept': q['kept'], 'dropped': q['dropped']}
        try:
            with self.flock:
                os.makedirs(self.folder, exist_ok=True)
                with open(os.path.join(self.folder, QUESTS), 'a', encoding='utf-8', newline='\n') as f:
                    f.write(json.dumps(line, separators=(',', ':')) + '\n')
        except OSError as e:
            return "route memory: the quest '%s' couldn't be written (%s)" % (q['title'][:60], e)
        return "route memory: the quest '%s' over - followed %.0f min, %d zone(s), %d goal(s), %d walk(s) kept" % (
            q['title'][:60], q['s'] / 60.0, len(q['zones']), len(q['goals']), q['kept'])

    # ---- the kept legs

    @staticmethod
    def _stat(path):
        try:
            st = os.stat(path)
        except OSError:
            return None
        return st.st_size, st.st_mtime_ns

    def _keep(self, zone, kept):
        """a kept leg appended to its zone's file - and to its heat, when that's built and the leg fits in it (else built
        again when next asked for). How many legs there now, None when the zone isn't read yet. The file rewritten with
        the newest KEEP once it has twice that many lines"""
        path = zone_file(self.folder, zone)
        with self.flock:
            os.makedirs(self.folder, exist_ok=True)
            with self.zlock:
                zh = self.zones.get(zone)
                if zh is not None and zh.stat != self._stat(path):
                    # (its file deleted or changed by someone else: what's kept of it read again when next asked for)
                    del self.zones[zone]
                    zh = None
                rewrite = zh is not None and zh.lines + 1 > 2 * KEEP
                legs = (zh.legs + [kept])[-KEEP:] if rewrite else None
            if rewrite:
                tmp = path + '.tmp'
                with open(tmp, 'w', encoding='utf-8', newline='\n') as f:
                    f.writelines(json.dumps(leg, separators=(',', ':')) + '\n' for leg in legs)
                os.replace(tmp, path)
            else:
                with open(path, 'a', encoding='utf-8', newline='\n') as f:
                    f.write(json.dumps(kept, separators=(',', ':')) + '\n')
            st = self._stat(path)
            if zh is None:
                return None
            with self.zlock:
                if self.zones.get(zone) is not zh:
                    return None
                if rewrite:
                    zh.legs, zh.lines, zh.n, zh.e = legs, len(legs), None, None
                else:
                    zh.legs.append(kept)
                    zh.lines += 1
                    if zh.fits(kept['pts']):
                        zh.add(kept)
                    else:
                        zh.n = zh.e = None
                zh.stat, zh.ver = st, zh.ver + 1
                return len(zh.legs)

    def _read(self, zone):
        """(legs, lines, stat) from the zone's file - lines that don't parse skipped; ([], 0, None) with none"""
        path = zone_file(self.folder, zone)
        legs, lines = [], 0
        with self.flock:
            st = self._stat(path)
            if st is None:
                return [], 0, None
            try:
                with open(path, encoding='utf-8') as f:
                    for line in f:
                        lines += 1
                        try:
                            leg = json.loads(line)
                        except ValueError:
                            continue
                        if isinstance(leg, dict) and isinstance(leg.get('pts'), list):
                            legs.append(leg)
            except (OSError, UnicodeDecodeError):
                return [], 0, None
        return legs[-KEEP:], lines, st

    def zone_heat(self, zone, now=None):
        """(n, e, x0, y0, scale) - the zone's kept legs' heat by CELL squares from (x0, y0) ([j, i]), n and e to be
        multiplied by scale (their age now) - or None, no legs kept there. Its file read again when it changed or went
        (deleted: forgotten); the heat built again when it's to be - outside the zone's lock: see() never waits for it"""
        now = self.clock() if now is None else now
        path = zone_file(self.folder, zone)
        for _ in range(3):
            st = self._stat(path)
            with self.zlock:
                zh = self.zones.get(zone)
                fresh = zh is not None and zh.stat == st
                if fresh and zh.n is not None and now - zh.base <= REBASE * 86400:
                    return zh.n, zh.e, zh.x0, zh.y0, 0.5 ** ((now - zh.base) / 86400.0 / HALF_LIFE)
                if fresh and not zh.legs:
                    return None
                legs, ver = (list(zh.legs), zh.ver) if fresh else (None, None)
            if legs is None:
                legs, lines, st = self._read(zone)
                with self.zlock:
                    if self.zones.get(zone) is not zh:
                        continue
                    zh = self.zones[zone] = ZoneHeat(legs, lines, st)
                    ver = zh.ver
                if lines > 2 * KEEP:
                    self._trim(zone)
                if not legs:
                    return None
            n, e, x0, y0 = build_heat(legs, now)
            with self.zlock:
                if self.zones.get(zone) is zh and zh.ver == ver:
                    if n is None:
                        return None
                    zh.n, zh.e, zh.x0, zh.y0, zh.base = n, e, x0, y0, now
                    return n, e, x0, y0, 1.0
        return None

    def _trim(self, zone):
        """the zone's file rewritten with the newest KEEP legs (it had more than twice that many lines)"""
        path = zone_file(self.folder, zone)
        with self.flock:
            with self.zlock:
                zh = self.zones.get(zone)
                if zh is None or zh.lines <= 2 * KEEP:
                    return
                legs = list(zh.legs)
            try:
                tmp = path + '.tmp'
                with open(tmp, 'w', encoding='utf-8', newline='\n') as f:
                    f.writelines(json.dumps(leg, separators=(',', ':')) + '\n' for leg in legs)
                os.replace(tmp, path)
            except OSError as e:
                self.log("route memory: %s couldn't be made shorter (%s)" % (path, e))
                return
            st = self._stat(path)
            with self.zlock:
                if self.zones.get(zone) is zh:
                    zh.lines, zh.stat = len(legs), st

    def zone_grid(self, zone, now=None):
        """(heat01, x0, y0) - the zone's heat (0-1) by CELL squares from (x0, y0), [j, i] - or None, no legs kept"""
        got = self.zone_heat(zone, now)
        if got is None:
            return None
        n, e, x0, y0, scale = got
        return (e * scale) / np.maximum(n * scale, FULL), x0, y0

    def heat01(self, zone, x0, y0, nx, ny, cell):
        """a window's squares' heat, 0-1 (ny, nx): the window's squares cell across from (x0, y0) - by the heat square
        under each one's middle -, None when the zone has no legs kept"""
        got = self.zone_heat(zone)
        if got is None:
            return None
        n, e, gx0, gy0, scale = got
        gi = np.floor((x0 + (np.arange(nx) + 0.5) * cell - gx0) / CELL).astype(np.int64)
        gj = np.floor((y0 + (np.arange(ny) + 0.5) * cell - gy0) / CELL).astype(np.int64)
        oki = (gi >= 0) & (gi < n.shape[1])
        okj = (gj >= 0) & (gj < n.shape[0])
        out = np.zeros((ny, nx))
        if oki.any() and okj.any():
            sj, si = np.ix_(gj[okj], gi[oki])
            out[np.ix_(np.nonzero(okj)[0], np.nonzero(oki)[0])] = (e[sj, si] * scale) / np.maximum(n[sj, si] * scale, FULL)
        return out
