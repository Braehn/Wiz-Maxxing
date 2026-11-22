"""routemem - the walker's route memory: the legs of the quests it walked well, kept per zone, and the heat map they
make of the ways that worked - for the route planner (navroute: those squares a little cheaper to walk - the
routeheat setting) and the dashboard's Map (a warm shade under the route).

READ-ONLY toward the game: it keeps only the wizard's positions vision.py's /nav already reads (route=1 with avoid=1:
the walker following the quest's way, keeping away from mobs). Nothing is sent to the game.

    rm = RouteMem(folder, log=print)
    rm.see(zone, pos, goal, target, clean=True)        # each /nav route reading; a line for the log when a leg ends
    rm.heat01(zone, x0, y0, nx, ny, cell)              # the heat (0-1) of a window's squares - None: nothing known

A leg: the walk to one goal in one zone - from the first reading with that goal (its line, less a "(n of m)" count,
and where the game's quest path leads: the goal itself, or the way out to the zone it's in) to the first reading
within ARRIVE of where it leads. Kept (a success) when the goal then moves on, the way it leads moves, or the zone
changes - with the wizard arrived. Dropped when it ends with the wizard not there (a knockout, a recall, a teleport,
the quest changed), when a reading wasn't clean (you playing, mob avoidance off - walked into mobs on purpose), when
it took longer than LEG_MAX, nothing was read for GAP_MAX (the bot off), or it was shorter than MIN_LEN.

Its weight - how well it went: eff = (the straight line from its start to its end / the length walked) x (the time
spent walking / the time it took). A detour, a wait for a mob to move off, standing stuck and each battle on the way
(the walker doesn't read /nav in one) lower it; at least EFF_MIN. An older leg weighs less: halved every HALF_LIFE
days.

Files: AutoFarmer\\routes\\heat\\<zone>.jsonl - one leg a line (JSON): t (when it ended, epoch s), goal, from, to
([x, y]), s (seconds), len (units walked), eff, pts ([[x, y], ...] - the wizard's trail, a point every STEP units). The
updater keeps routes\\. Delete a zone's file to forget it. At most KEEP legs a zone (the oldest dropped).

A square's heat (CELL units across): the summed weights of the legs that passed through it, or WIDE squares beside it,
each leg once; heat01 = min(1, heat / FULL) - what the planner's discount and the map's shade go by."""
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
ARRIVE = 400.0          # within this of where the quest's path leads: arrived
TARGET_MOVED = 400.0    # where it leads moved this far: another leg
JUMP = 1500.0           # the wizard this far from his last reading...
JUMP_S = 3.0            # ...after more than this (s - a battle, a knockout's respawn), or...
TELE_SPEED = 3000.0     # ...faster than this (units / s - no walk, even sped up): a teleport - the leg dropped
MOVING = 150.0          # faster than this (units / s) between two readings JUMP_S or less apart: walking
GAP_MAX = 600.0         # nothing read for this long (s): the leg dropped (the bot off, a long stop)
LEG_MAX = 900.0         # a leg taking longer than this (s): dropped (it got stuck, or waited for you)
MIN_LEN = 300.0         # walked less than this (units): not kept
EFF_MIN = 0.2           # a kept leg weighs at least this
HALF_LIFE = 14.0        # days: an older leg's weight halved every this many
KEEP = 300              # legs kept a zone
FULL = 3.0              # heat at which a square counts as fully walked (heat01 1 - navroute.HEAT_DISCOUNT off it)

_COUNT = re.compile(r'\(\s*\d+\s*of\s*\d+\s*\)', re.I)


def goal_key(text):
    """a goal line as a leg's key: its "(n of m)" count left out (it goes up along the way), spaces and case evened"""
    return ' '.join(_COUNT.sub(' ', text or '').split()).lower()


def zone_file(folder, zone):
    """the zone's legs file in folder: <zone>.jsonl, every character but letters, digits, _ and - made _"""
    return os.path.join(folder, re.sub(r'[^\w-]', '_', zone) + '.jsonl')


def leg_weight(leg, now):
    """a kept leg's weight now: its eff (at least EFF_MIN), halved every HALF_LIFE days since it ended"""
    try:
        eff = max(EFF_MIN, min(1.0, float(leg.get('eff', 0.0))))
        age = max(0.0, now - float(leg.get('t', now))) / 86400.0
    except (TypeError, ValueError):
        return 0.0
    return eff * 0.5 ** (age / HALF_LIFE)


def trail_cells(pts, x0, y0, nx, ny, cell=CELL, wide=WIDE):
    """the flat indices (j * nx + i) of the squares a trail passes through - or wide squares beside it - each once"""
    if not pts:
        return np.zeros(0, dtype=np.int64)
    p = np.asarray(pts, dtype=float).reshape(-1, 2)
    if len(p) > 1:
        seg = np.diff(p, axis=0)
        n = np.maximum(1, np.ceil(np.hypot(seg[:, 0], seg[:, 1]) / (cell / 2.0)).astype(int))
        s = np.concatenate([p[k] + seg[k] * (np.arange(n[k])[:, None] / n[k]) for k in range(len(seg))] + [p[-1:]])
    else:
        s = p
    i = np.floor((s[:, 0] - x0) / cell).astype(np.int64)
    j = np.floor((s[:, 1] - y0) / cell).astype(np.int64)
    d = np.arange(-wide, wide + 1)
    ii = (i[:, None, None] + d[None, None, :]).repeat(len(d), axis=1).reshape(-1)
    jj = (j[:, None, None] + d[None, :, None]).repeat(len(d), axis=2).reshape(-1)
    ok = (ii >= 0) & (ii < nx) & (jj >= 0) & (jj < ny)
    return np.unique(jj[ok] * nx + ii[ok])


class ZoneHeat:
    """one zone's kept legs and the heat grid they make (built when first asked for after a change)"""

    def __init__(self, legs, lines=0):
        self.legs, self.lines = legs, lines     # (lines: in its file - bad ones too)
        self.grid, self.x0, self.y0, self.at = None, 0.0, 0.0, 0.0

    def build(self, now):
        pts = [q for leg in self.legs for q in (leg.get('pts') or ())]
        if not pts:
            self.grid = np.zeros((0, 0))
            return
        a = np.asarray(pts, dtype=float).reshape(-1, 2)
        pad = (WIDE + 1) * CELL
        self.x0, self.y0 = float(a[:, 0].min()) - pad, float(a[:, 1].min()) - pad
        nx = int(math.ceil((float(a[:, 0].max()) + pad - self.x0) / CELL))
        ny = int(math.ceil((float(a[:, 1].max()) + pad - self.y0) / CELL))
        grid = np.zeros(ny * nx)
        for leg in self.legs:
            w = leg_weight(leg, now)
            if w > 0:
                grid[trail_cells(leg.get('pts') or (), self.x0, self.y0, nx, ny)] += w
        self.grid, self.at = grid.reshape(ny, nx), now


class RouteMem:
    """the route memory: the leg being walked, and each zone's kept legs (read from folder when first needed)"""

    def __init__(self, folder, log=print, clock=time.time):
        self.folder, self.log, self.clock = folder, log, clock
        self.lock = threading.Lock()
        self.zones = {}         # zone: ZoneHeat
        self.leg = None         # the leg being walked (a dict), None none

    # ---- the leg being walked

    def see(self, zone, pos, goal, target, clean=True, now=None, label=None):
        """one /nav route reading: the zone, the wizard's pos (x, y, z), the goal (what tells it from the next one: the
        game's ids for it, or its line - empty: as the last reading), where the quest's path leads (target: x, y, z -
        None: no way known, no leg begun at it) and clean (mob avoidance on, you not playing); label: the goal's line
        for the file and the log (else goal). A line for the log when a leg ends (kept or dropped), else None"""
        now = self.clock() if now is None else now
        if not zone or pos is None:
            return None
        with self.lock:
            said = []
            leg = self.leg
            key = goal_key(goal)
            if leg is not None:
                why = self._ends(leg, zone, pos, key, target, now)
                if why is not None:
                    # (the goal moved on - or its way did - right where the wizard stands: there, at this reading)
                    if why.startswith('done') and zone == leg['zone'] and leg['arrived'] is None and math.hypot(
                            pos[0] - leg['target'][0], pos[1] - leg['target'][1]) <= ARRIVE:
                        leg['arrived'] = now
                    said.append(self._end(leg, why, now))
                    leg = self.leg = None
            if leg is None and target is not None and key:
                leg = self.leg = {'zone': zone, 'key': key, 'goal': ' '.join((label or goal or '').split()), 'target': target,
                                  't0': now, 'last': now, 'at': pos, 'pts': [(pos[0], pos[1])], 'len': 0.0,
                                  'moving': 0.0, 'arrived': None, 'clean': bool(clean)}
            elif leg is not None:
                self._step(leg, pos, target, clean, now)
            return '; '.join(s for s in said if s) or None

    def _ends(self, leg, zone, pos, key, target, now):
        """why the leg ends at this reading ('done' - its goal moved on, the zone changed, where it leads moved - or
        'drop: ...'), None it goes on"""
        dt = now - leg['last']
        step = math.hypot(pos[0] - leg['at'][0], pos[1] - leg['at'][1])
        if dt > GAP_MAX:
            return 'drop: nothing read for %.0f s' % dt
        if zone != leg['zone']:
            return 'done: into ' + zone
        if step > JUMP and (dt > JUMP_S or step / max(dt, 1e-3) > TELE_SPEED):
            return 'drop: the wizard moved %.0f in %.1f s (a teleport, a knockout)' % (step, dt)
        if key and key != leg['key']:
            return 'done: the goal moved on'
        if target is not None and math.hypot(target[0] - leg['target'][0], target[1] - leg['target'][1]) > TARGET_MOVED:
            return 'done: the way on moved'
        if now - leg['t0'] > LEG_MAX:
            return 'drop: longer than %.0f s' % LEG_MAX
        return None

    def _step(self, leg, pos, target, clean, now):
        dt = now - leg['last']
        step = math.hypot(pos[0] - leg['at'][0], pos[1] - leg['at'][1])
        if dt <= JUMP_S and dt > 0 and step / dt > MOVING:
            leg['moving'] += dt
        leg['len'] += step
        leg['last'], leg['at'] = now, pos
        leg['clean'] = leg['clean'] and bool(clean)
        if target is not None:
            leg['target'] = target
        last = leg['pts'][-1]
        if math.hypot(pos[0] - last[0], pos[1] - last[1]) >= STEP:
            leg['pts'].append((pos[0], pos[1]))
        if leg['arrived'] is None and math.hypot(pos[0] - leg['target'][0], pos[1] - leg['target'][1]) <= ARRIVE:
            leg['arrived'] = now

    def _end(self, leg, why, now):
        """a leg over: kept (written to its zone's file) when it's a success, else dropped - the log's line"""
        where = "leg in %s to '%s'" % (leg['zone'], leg['goal'][:60])
        if why.startswith('drop'):
            return 'route memory: dropped the ' + where + ' - ' + why[6:]
        if leg['arrived'] is None:
            return 'route memory: dropped the ' + where + ' - ' + why[6:] + ' with the wizard not there'
        if not leg['clean']:
            return 'route memory: dropped the ' + where + ' - you were playing, or mob avoidance was off'
        if leg['len'] < MIN_LEN:
            return None
        took = max(1e-3, leg['arrived'] - leg['t0'])
        a, b = leg['pts'][0], leg['pts'][-1]
        straight = math.hypot(b[0] - a[0], b[1] - a[1])
        eff = min(1.0, straight / max(leg['len'], 1e-3)) * min(1.0, leg['moving'] / took)
        kept = {'t': round(now, 1), 'goal': leg['goal'], 'from': [round(a[0]), round(a[1])], 'to': [round(b[0]), round(b[1])],
                's': round(took, 1), 'len': round(leg['len']), 'eff': round(eff, 3),
                'pts': [[round(x), round(y)] for x, y in leg['pts']]}
        try:
            n = self._keep(leg['zone'], kept)
        except OSError as e:
            return 'route memory: the ' + where + " couldn't be written (%s)" % e
        return 'route memory: kept the %s - %.0f s, %.0f walked, eff %.2f (%d legs there)' % (where, took, leg['len'], eff, n)

    # ---- the kept legs

    def _zone(self, zone):
        """the zone's ZoneHeat, its file read the first time (lines that don't parse skipped)"""
        zh = self.zones.get(zone)
        if zh is None:
            legs, lines = [], 0
            try:
                with open(zone_file(self.folder, zone), encoding='utf-8') as f:
                    for line in f:
                        lines += 1
                        try:
                            leg = json.loads(line)
                        except ValueError:
                            continue
                        if isinstance(leg, dict) and isinstance(leg.get('pts'), list):
                            legs.append(leg)
            except OSError:
                pass
            zh = self.zones[zone] = ZoneHeat(legs[-KEEP:], lines)
        return zh

    def _keep(self, zone, kept):
        """a kept leg added to its zone's file (rewritten with the newest KEEP once it has twice that many lines); how
        many legs now"""
        zh = self._zone(zone)
        zh.legs.append(kept)
        os.makedirs(self.folder, exist_ok=True)
        path = zone_file(self.folder, zone)
        zh.lines += 1
        if zh.lines > 2 * KEEP:
            zh.legs = zh.legs[-KEEP:]
            tmp = path + '.tmp'
            with open(tmp, 'w', encoding='utf-8', newline='\n') as f:
                f.writelines(json.dumps(leg, separators=(',', ':')) + '\n' for leg in zh.legs)
            os.replace(tmp, path)
            zh.lines = len(zh.legs)
        else:
            with open(path, 'a', encoding='utf-8', newline='\n') as f:
                f.write(json.dumps(kept, separators=(',', ':')) + '\n')
        zh.grid = None
        return len(zh.legs)

    def zone_grid(self, zone, now=None):
        """(grid, x0, y0) - the zone's heat by CELL squares from (x0, y0), grid[j, i] - or None, no legs kept there"""
        now = self.clock() if now is None else now
        with self.lock:
            zh = self._zone(zone)
            if not zh.legs:
                return None
            if zh.grid is None or now - zh.at > 3600:
                zh.build(now)
            if zh.grid.size == 0:
                return None
            return zh.grid, zh.x0, zh.y0

    def heat01(self, zone, x0, y0, nx, ny, cell):
        """a window's squares' heat, 0-1 (ny, nx): the window's squares cell across from (x0, y0) - by the heat square
        under each one's middle -, None when the zone has no legs kept"""
        got = self.zone_grid(zone)
        if got is None:
            return None
        grid, gx0, gy0 = got
        cx = x0 + (np.arange(nx) + 0.5) * cell
        cy = y0 + (np.arange(ny) + 0.5) * cell
        gi = np.floor((cx - gx0) / CELL).astype(np.int64)
        gj = np.floor((cy - gy0) / CELL).astype(np.int64)
        oki = (gi >= 0) & (gi < grid.shape[1])
        okj = (gj >= 0) & (gj < grid.shape[0])
        out = np.zeros((ny, nx))
        if oki.any() and okj.any():
            sub = grid[np.ix_(gj[okj], gi[oki])]
            out[np.ix_(np.nonzero(okj)[0], np.nonzero(oki)[0])] = sub
        return np.minimum(1.0, out / FULL)
