"""statemem - READ-ONLY reader of a zone object's STATE (a gate open or shut, a lever pulled) in a running Wizard101 client
(WizardGraphicalClient.exe): its ObjectStateBehavior's current state - for the vision helper's /blockers (each door's
state: the puzzle sees a gate open even when its model stays in the game's memory, not only its collision going). navmem.py
makes one per game (in a thread, like bossmem's) and reads each blocker's state under its lock at every /blockers.

    sm = StateMem(st, log=print)        # st: navmem's attached game (navmem._Attached); once per game. LookupError when
                                        # the classes or the state property aren't in this build
    text, why = sm.state(obj)           # a zone object's ClientObject -> its state's text ("Open"), or None and why
    b, why = sm.behavior(obj)           # ...its ObjectStateBehavior (its address), or 0 and why
    fields = sm.strings(b)              # [(property, offset, text)] every text property of the behaviour (--watch's)

    python statemem.py --watch [SECONDS] [--all] [--json] [--out state.txt]
                                        the state of the zone's doors and gates (--all: every object holding an
                                        ObjectStateBehavior - levers, pylons...) read every second for SECONDS (60): each
                                        object's template, place, behaviour class, state and every text property of its
                                        behaviour, again whenever one changes - open a gate (beat its guards, pull its
                                        lever) while it runs. The classes' own properties: python reflect.py --class
                                        ObjectStateBehavior --class ClientObjectStateBehavior --grep state

NOT CONFIRMED IN THE GAME YET. Which class the game's objects carry (ObjectStateBehavior, ClientObjectStateBehavior), which
property holds the CURRENT state and of what type (a std::string is assumed; an id or a pointer to a state object would
read "not a text"), its values for a shut and an open gate, and whether the TypeNamer names the behaviour or its vtable
sets are needed: run reflect.py and --watch at a gate (Storm Lord's Temple's CL-StormLordTempleGate and its
DynaTrigger_KT_DoorCollision) and at a lever, then pin STATE_PROP / STATE_BUILD. Till then STATE_PROPS' names are tried in
order, then any property named like a state (STATE_RX) - none found: LookupError, and navmem gives every door state None
(the bot as before: Puzzle.ahk acts on a state only with its puzzlestate setting on, off by default).

SAFETY. The game is opened by navmem.py's Proc - PROCESS_VM_READ | PROCESS_QUERY_INFORMATION (falling back to
PROCESS_VM_READ | PROCESS_QUERY_LIMITED_INFORMATION) - and only read: ReadProcessMemory (try_read / try_string). Nothing is
ever written, allocated, injected, hooked, suspended or debugged; no window is touched and no input is sent. Every class and
property offset is found by NAME in a copy of the game's code (its reflection registration: handmem.Image /
questmem.class_props); the behaviour is checked by its vtable (or its type name) and its owner before it's used.

FAILS SOFT. state(), behavior() and strings() never raise: (None, why) / (0, why) / [] when it can't be read. The
constructor raises LookupError when a class or property isn't in this build. Importable anywhere (no Windows module at
import - the tests run it on made-up memory: test_statemem.py).

WHAT IS READ (offsets by name each attach):
  CoreObject.m_inactiveBehaviors (the BEH_LISTS found): std::vector<SharedPointer<BehaviorInstance>> (16 bytes each) ->
    the ObjectStateBehavior: the element whose vtable is one of BEH_CLASSES' (their GetType's), else whose type name ends
    ObjectStateBehavior (bagmem's way) - BehaviorInstance +0x48 its object (== obj: checked - bossmem's beh_owner; not
    there, in another build: looked for in its first OWNER_SPAN bytes and kept once two objects agree - bossmem's _place)
  -> the state property (STATE_PROP once pinned; else the first of STATE_PROPS / STATE_RX the class registers): a
    std::string (MSVC x64: 16-byte inline buffer or a pointer, size +0x10, capacity +0x18)
"""
import json
import os
import re
import struct
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.insert(0, HERE)

# the behaviour classes a state may be on (the client's first), and the template's (its starting state - --watch only)
BEH_CLASSES = ("ClientObjectStateBehavior", "ObjectStateBehavior")
TEMPLATE_CLASS = "ObjectStateBehaviorTemplate"
CLASSES = ("CoreObject",) + BEH_CLASSES + (TEMPLATE_CLASS,)
BEH_LISTS = ("m_inactiveBehaviors", "m_activeBehaviors")     # CoreObject's behaviour vectors (those this build has)
# The current state's property: pinned once seen in the game (python reflect.py --class ObjectStateBehavior; --watch at a
# gate) - "" till then: STATE_PROPS' names tried in order, then any property named like a state
STATE_PROP, STATE_BUILD = "", ""
STATE_PROPS = ("m_currentState", "m_curState", "m_currentStateName", "m_stateName", "m_state", "m_sState",
               "m_sCurrentState")
STATE_RX = re.compile(r"(?i)^m_(s|str)?_?(current|cur)?_?state(_?name)?$")
KNOWN = {"beh_owner": 0x48}         # BehaviorInstance's object (not reflected - bossmem's KNOWN, checked at each read; a
                                    # first guess: another build's looked for - StateMem._owner)
OWNER_SPAN = 0x100                  # ...in the behaviour's first bytes (bossmem's _place: 0x100)
VEC_LIMIT = 128                     # behaviours an object holds at most (a vector longer than this isn't one)


def ptr_ok(v):
    """a user-mode address (navmem.ptr_ok: heap objects, and the exe's own sections at 0x7FF6...)"""
    return isinstance(v, int) and 0x10000 <= v < 0x7FFFFFFF0000


def pick_state_prop(props):
    """(class, property, offset) of the current state among props ({class: {property: offset}} - BEH_CLASSES' looked at in
    order): STATE_PROP when pinned, else the first of STATE_PROPS, else the first (by name) STATE_RX matches - None when
    none is there"""
    for want in ((STATE_PROP,) if STATE_PROP else STATE_PROPS):
        for c in BEH_CLASSES:
            if want in (props.get(c) or {}):
                return c, want, props[c][want]
    if STATE_PROP:
        return None
    for c in BEH_CLASSES:
        for k in sorted(props.get(c) or {}):
            if STATE_RX.match(k):
                return c, k, props[c][k]
    return None


class StateMem:
    """a zone object's state (its ObjectStateBehavior) - see the top. Not thread-safe: call it under navmem's lock (as
    bossmem / handmem / questmem)"""

    def __init__(self, st, log=None, props=None, vts=None, need_state=True):
        """props: {class: {property: offset}}, vts: {class: set(vtables)} - tests only (no code copy read); need_state
        False (--watch): made without a state property (state() says why)"""
        self.log = log or (lambda msg: None)
        t0 = time.perf_counter()
        self.st, self.p = st, st.p
        self.build = getattr(getattr(st, "m", None), "build", "")
        if props is None:
            import handmem as H
            import questmem as Q
            img = H.shared_image(st)
            got = {c: Q.class_props(img, c) for c in CLASSES}
            del img
            props = {c: {k: v[0] for k, v in got[c][0].items()} for c in got}
            vts = {c: set(got[c][2]) for c in got}
        self.P = {c: dict(props.get(c) or {}) for c in CLASSES}
        self.o, self._cand = {}, {}     # places found and kept (the owner's, another build's) / candidates seen
        self.vt = {c: set((vts or {}).get(c) or ()) for c in CLASSES}
        self.lists = [(k, self.P["CoreObject"][k]) for k in BEH_LISTS if k in self.P["CoreObject"]]
        if not self.lists:
            raise LookupError("CoreObject's behaviours aren't a reflected property in this build (%s)" % self.build)
        self.beh_vt = set().union(*(self.vt[c] for c in BEH_CLASSES))
        found = [c for c in BEH_CLASSES if self.P[c] or self.vt[c]]
        if not found:
            raise LookupError("no ObjectStateBehavior class in this build (%s): %s" % (self.build, ", ".join(BEH_CLASSES)))
        self.prop = pick_state_prop(self.P)
        if self.prop is None and need_state:
            raise LookupError("no state property found in this build (%s) - python reflect.py --class ObjectStateBehavior "
                              "--grep state" % self.build)
        self.attach_s = time.perf_counter() - t0
        self.log("statemem: ready in %.2f s - classes %s, %d vtables, state %s" % (
            self.attach_s, ", ".join(found), len(self.beh_vt),
            "%s.%s +%#x" % self.prop if self.prop else "not found"))

    # ------------------------------------------------------------------ small readers
    def u64(self, a):
        b = self.p.try_read(a, 8) if ptr_ok(a) else None
        return struct.unpack("<Q", b)[0] if b else 0

    def vec(self, a, limit=VEC_LIMIT):
        """the objects of a std::vector<SharedPointer<T>> at a (begin, end: 16-byte elements) - [] when it isn't one"""
        b = self.p.try_read(a, 16) if ptr_ok(a) else None
        if not b:
            return []
        x, y = struct.unpack("<QQ", b)
        if not (ptr_ok(x) and x <= y <= x + 16 * limit and (y - x) % 16 == 0):
            return []
        raw = self.p.try_read(x, y - x) or b""
        return [struct.unpack_from("<Q", raw, i)[0] for i in range(0, len(raw) - 7, 16)]

    def tname(self, obj):
        try:
            return self.st.tn.of(obj) if ptr_ok(obj) else None
        except Exception:  # noqa: BLE001 - not named
            return None

    def behaviours(self, obj):
        """[(list, element)] every behaviour of obj in its BEH_LISTS"""
        return [(k, b) for k, off in self.lists for b in self.vec(obj + off) if ptr_ok(b)]

    def is_state_behaviour(self, b):
        """b (a behaviour) is an ObjectStateBehavior: its vtable one of BEH_CLASSES', else its type name ends so"""
        if self.beh_vt and self.u64(b) in self.beh_vt:
            return True
        n = self.tname(b) or ""
        return n.endswith("ObjectStateBehavior")

    def _owner(self, b, obj):
        """the behaviour b's object is obj: at the place kept for it (KNOWN's +0x48 first) - else, another build, the first
        8-byte slot of b's first OWNER_SPAN bytes holding obj, the place kept once two different behaviours agree (bossmem's
        _place; a pointer to obj in its own behaviour is its owner)"""
        off = self.o.get("beh_owner", KNOWN["beh_owner"])
        if self.u64(b + off) == obj:
            return True
        raw = self.p.try_read(b, OWNER_SPAN) if ptr_ok(b) else None
        for i in range(0, len(raw or b"") - 7, 8):
            if struct.unpack_from("<Q", raw, i)[0] != obj:
                continue
            seen = self._cand.setdefault(i, set())
            seen.add(b)
            if len(seen) >= 2:
                self.o["beh_owner"] = i
                self._cand.clear()
                self.log("statemem: the behaviour's object found at +%#x" % i)
            return True
        return False

    # ------------------------------------------------------------------ an object
    def behavior(self, obj):
        """(the ObjectStateBehavior of the zone object obj, "") - by vtable or type name, its owner (+0x48, or where
        another build has it - _owner) obj - or (0, why). Never raises"""
        try:
            if not ptr_ok(obj):
                return 0, "not an object"
            cands = [b for _k, b in self.behaviours(obj) if self.is_state_behaviour(b)]
            if not cands:
                return 0, "no ObjectStateBehavior"
            for b in cands:
                if self._owner(b, obj):
                    return b, ""
            return 0, "its ObjectStateBehavior isn't the object's"
        except Exception as e:  # noqa: BLE001 - never into the caller
            return 0, "its behaviours couldn't be read (%r)" % (e,)

    def state(self, obj):
        """(the state's text of the zone object obj, "") - or (None, why): no state property in this build, no
        ObjectStateBehavior, not a text there, empty. Never raises"""
        try:
            if self.prop is None:
                return None, "no state property in this build"
            b, why = self.behavior(obj)
            if not b:
                return None, why
            s = self.p.try_string(b + self.prop[2])
            if s is None:
                return None, "its %s isn't a text" % self.prop[1]
            s = s.strip()
            return (s, "") if s else (None, "its %s is empty" % self.prop[1])
        except Exception as e:  # noqa: BLE001 - never into the caller
            return None, "its state couldn't be read (%r)" % (e,)

    def strings(self, b):
        """[(property, offset, text)] every property of the behaviour b (BEH_CLASSES' - by offset) that reads as a text
        now - what --watch prints to pin the state's property. Never raises"""
        out = []
        try:
            seen = set()
            for c in BEH_CLASSES:
                for k, off in sorted(self.P[c].items(), key=lambda kv: kv[1]):
                    if off in seen:
                        continue
                    seen.add(off)
                    s = self.p.try_string(b + off)
                    if s:
                        out.append((k, off, s))
        except Exception:  # noqa: BLE001 - what was read
            pass
        return out


# ============================================================================ command line
def watch_rows(sm, objs, names):
    """[{obj, gid, template, behaviour, class, state, why, strings}] of objs [(object, gid, template)] - names: the
    behaviour's class by its type name (sm.tname); one with no ObjectStateBehavior: behaviour 0 and why"""
    rows = []
    for obj, gid, tpl in objs:
        b, why = sm.behavior(obj)
        st, swhy = sm.state(obj) if b else (None, why)
        rows.append({"obj": obj, "gid": gid, "template": tpl, "behaviour": b, "class": names(b) if b else None,
                     "state": st, "why": swhy, "strings": sm.strings(b) if b else [],
                     "kinds": sorted({names(x) or "?" for _k, x in sm.behaviours(obj)}) if not b else []})
    return rows


def watch_line(row, pos=None):
    """--watch's line for a row of watch_rows"""
    where = "(%.0f, %.0f, %.0f)" % tuple(pos[:3]) if pos else "?"
    if not row["behaviour"]:
        return "   %-36s gid %#x at %s - %s (its behaviours: %s)" % (row["template"], row["gid"] or 0, where, row["why"],
                                                                     ", ".join(row["kinds"]) or "none")
    return "   %-36s gid %#x at %s - %s state %r%s  texts: %s" % (
        row["template"], row["gid"] or 0, where, row["class"] or "?", row["state"],
        "" if row["state"] is not None else " (%s)" % row["why"],
        ", ".join("%s+%#x=%r" % s for s in row["strings"]) or "none")


def _watch(nm, sm, seconds, every_obj=False, as_json=False):
    """--watch: the zone's doors (navmem's blockers - every object with a state behaviour with every_obj) read every second
    for seconds; a line each at the start and whenever its state or texts change"""
    import navmem as N
    import puzzlefile
    st = nm.st
    last, objs, objs_at = {}, [], 0.0
    t1 = time.time()
    while time.time() - t1 < seconds:
        if every_obj and time.time() - objs_at >= 10.0:
            # (every zone object, its template's name - a heap look, every 10 s)
            import bossmem
            objs_at = time.time()
            objs = []
            with nm.lock:
                for o in bossmem._zone_objects(st):
                    raw = st.p.try_read(o, N.OBJ_SPAN)
                    if not raw:
                        continue
                    if not sm.behavior(o)[0]:
                        continue                # (only those holding a state behaviour: read every second)
                    tpl = struct.unpack_from("<Q", raw, N.DATA["co_template"])[0]
                    tn = st.p.try_string(tpl + N.DATA["tpl_name"]) if N.ptr_ok(tpl) else None
                    objs.append((o, struct.unpack_from("<Q", raw, N.DATA["co_gid"])[0], tn or "?"))
        elif not every_obj:
            nm.blockers()                       # (keeps the objects thread looking)
            with nm.lock:
                objs = [(o, v[0], v[2]) for o, v in nm._blockers.items()]
        with nm.lock:
            rows = watch_rows(sm, objs, sm.tname)
            for r in rows:
                raw = st.p.try_read(r["obj"], N.OBJ_SPAN)
                p = N.NavMem._mob_pos(st, r["obj"], raw) if raw else None
                r["pos"] = p[:3] if p else None
        changed = []
        for r in rows:
            key = (r["obj"], r["gid"])
            sig = (r["state"], tuple(r["strings"]), r["behaviour"])
            if last.get(key) != sig:
                last[key] = sig
                changed.append(r)
        if changed:
            print("-- %s: %d object(s), %d changed" % (time.strftime("%H:%M:%S"), len(rows), len(changed)))
            for r in changed:
                if as_json:
                    print(json.dumps({k: v for k, v in r.items()}, default=str))
                else:
                    print(watch_line(r, r.get("pos")) + (
                        "" if puzzlefile.is_blocker(r["template"] or "") else "  (not a door's name)"))
        time.sleep(1.0)


class _Tee:
    """what's printed, also written to a file (--out)"""

    def __init__(self, f, out):
        self.f, self.out = f, out

    def write(self, s):
        self.out.write(s)
        self.f.write(s)
        self.f.flush()

    def flush(self):
        self.out.flush()


def _main(argv=None):
    import argparse
    ap = argparse.ArgumentParser(description="read-only: the state of the zone's doors and gates (ObjectStateBehavior)")
    ap.add_argument("--watch", type=float, nargs="?", const=60.0, default=None, metavar="SECONDS",
                    help="read the doors' states every second for this long (60) - a line when one changes")
    ap.add_argument("--all", action="store_true", help="every object holding an ObjectStateBehavior, not only doors")
    ap.add_argument("--json", action="store_true")
    ap.add_argument("--out", default="", help="also written to this file")
    a = ap.parse_args(argv)
    if a.watch is None:
        ap.print_help()
        return 2
    if a.out:
        with open(a.out, "w", encoding="utf-8") as f:
            old, sys.stdout = sys.stdout, _Tee(f, sys.stdout)
            try:
                print("# python statemem.py %s (%s)" % (" ".join(argv if argv is not None else sys.argv[1:]),
                                                        time.strftime("%Y-%m-%d %H:%M")))
                return _run(a)
            finally:
                sys.stdout = old
    return _run(a)


def _run(a):
    """--watch: attach, make the reader (no state property needed), watch"""
    import navmem as N
    nm = N.NavMem(log=lambda m: None)
    r, why = nm.read(wait=30)
    if r is None:
        print("ERR", why)
        return 1
    t0 = time.perf_counter()
    try:
        with nm.lock:
            sm = StateMem(nm.st, log=print, need_state=False)
    except LookupError as e:
        print("ERR %s" % e)
        return 1
    print("zone %s - reader made in %.2f s; state property: %s" % (
        r["zone"], time.perf_counter() - t0, "%s.%s +%#x" % sm.prop if sm.prop else
        "none found (python reflect.py --class ObjectStateBehavior --class ClientObjectStateBehavior --grep state)"))
    _watch(nm, sm, a.watch, a.all, a.json)
    nm.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(_main())
