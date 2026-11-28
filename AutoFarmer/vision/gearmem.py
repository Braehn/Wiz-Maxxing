"""gearmem - READ-ONLY reader of the wizard's GEAR in a running Wizard101 client: every worn item (hat, robe, shoes, weapon,
athame, amulet, ring - the deck, pet and mount too, by slot only) and every gear item in the backpack, each with its
template's EQUIP EFFECTS (every GameEffectInfo subtype - a StatisticEffectInfo's stat name and its number or lookup index,
StartingPipEffectInfo, SpeedEffectInfo, ProvideSpellEffectInfo...) and EQUIP REQUIREMENTS (RequirementList ->
ReqMagicLevel, ReqSchoolOfFocus...), the Equipment Sets each is in, every backpack item's id (a dungeon run's drops are
the new ones) and the wizard's level - for the vision helper's /gear (vision\\gearrank.py turns it into a swap plan;
AutoFarmer's Gear.ahk logs it). navmem.py makes one per game in a thread (as bagmem's) and reads it under its lock.

    gm = GearMem(st, hm, log=print)   # st: navmem's attached game (navmem._Attached), hm: handmem.HandMem (the template
                                      # map, the name tables); about a second once a game (the reflection lookup)
    r, why = gm.read()                # {worn, bag, bag_gids, bag_size, sets, sets_ok, level, player_gid} or (None, why)
    r = finish(r, hm.lang_text)       # each item's display name from its key - outside navmem's lock

    python gearmem.py [--json] [--effects] [--out gear.txt]     what it reads now, one line an item (--effects: each
                                      equip effect's and requirement's type and fields - to send back); the classes
                                      themselves: python reflect.py --class StatisticEffectInfo --class RequirementList
                                      --grep "Effect|Req" --out gearclass.txt

NOT CONFIRMED IN THE GAME YET. Which properties the effect and requirement classes have (the names in EFFECT_CLASSES /
REQ_CLASSES are the community's - a class or property this build hasn't is left out, never guessed), and what a
StatisticEffectInfo's number is - the stat's size, or an index into a table looked up by the item's level (bossmem.py saw
"a resist looked up by level, its number isn't here" on mobs). Each field is read by the type its property's adder shares
with a property of a known type (reflect.guess_types over reflect.ANCHORS); a field whose type that doesn't tell: by its
name (a ...Name / m_s... a string, m_b... a flag), else a number as an int when it reads as a small one, else as a float
when it reads as a plausible one, else None. gearrank.py takes a number as the stat's size only from a property named like
one (an m_lookupIndex is an index: the size NOT known).

SAFETY. The game is opened by navmem.py's Proc - PROCESS_VM_READ | PROCESS_QUERY_INFORMATION (falling back to
PROCESS_VM_READ | PROCESS_QUERY_LIMITED_INFORMATION) - and only read: ReadProcessMemory (try_read / try_string). Nothing is
ever written, allocated, injected, hooked, suspended or debugged; no window is touched, nothing is clicked and no input is
sent - equipping is AutoFarmer's (Gear.ahk - a rehearsal for now: it equips nothing). Every class and property offset is
found by NAME in a copy of the game's code (its reflection registration: handmem.Image / questmem.class_props); every
object is checked by its type name before it's used. No memory scan: everything is followed from the wizard's own object.

FAILS SOFT. read() never raises: (None, why) when the wizard or its item lists can't be read; an item whose template, effects
or requirements can't be read whole has None there (gearrank: not judged), never a guess. The constructor raises
LookupError when a needed class or property isn't in this build. Importable anywhere (no Windows module at import - the
tests run it on made-up memory: test_gearmem.py).

WHAT IS READ (offsets by name each attach):
  the wizard    the camera's object (navmem: GameClient -> ElasticCamController -> its ClientObject - deckmem's way)
                  CoreObject.m_globalID.m_full, m_inactiveBehaviors (16-byte SharedPointers): ...WizEquipmentBehavior,
                  ...WizInventoryBehavior by type name; WizClientObject.m_gameStats -> WizGameStats.m_referenceLevel (the
                  level - OPTIONAL)
  worn          ClientEquipmentBehavior.m_itemList - std::list {head, size} of SharedPointer<WizClientObjectItem> (node:
                  next, prev, the item at +0x10)
  backpack      InventoryBehaviorBase.m_itemList (bagmem's) - every item's global id; details for gear of the planned slots
                  (an item whose template or adjectives can't be read: kept with slot None - gearrank: "unknown")
  sets          ClientWizEquipmentBehavior.m_equipmentSets: std::list of EquipmentSet - m_serializedItems (u16 n, n u64
                  global ids), m_isEquipped (bagmem's)
  an item       CoreObject.m_globalID.m_full, m_templateID.m_full -> handmem's template map -> its template:
                  GameObjectTemplate.m_objectName, m_adjectiveList (its slot: Hat, Robe...; FLAG_CrownsOnly, FLAG_NoSell),
                  m_displayName (a name-table key); ItemTemplate.m_equipEffects (std::list of SharedPointer<GameEffectInfo>:
                  each effect's type name and the fields of its class and GameEffectInfo's), m_equipRequirements (a
                  SharedPointer<RequirementList>: m_requirements - std::list of SharedPointer<Requirement> -, m_applyNOT,
                  m_operator; each requirement's type and the fields of its class, its bases' (REQ_BASES) and
                  Requirement's) - kept per template (they don't change while the game runs) once read whole
"""
import json
import math
import os
import re
import struct
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.insert(0, HERE)
import gearrank as G                 # noqa: E402 - pure (an item's slot from its adjectives)

NEED = {"CoreObject": ("m_inactiveBehaviors", "m_globalID.m_full", "m_templateID.m_full"),
        "InventoryBehaviorBase": ("m_itemList",),
        "ClientEquipmentBehavior": ("m_itemList",),
        "GameObjectTemplate": ("m_objectName", "m_adjectiveList"),
        "ItemTemplate": ("m_equipEffects",)}
# (read when found: without them that part's left out - None)
OPTIONAL = {"GameObjectTemplate": ("m_displayName",),
            "ItemTemplate": ("m_equipRequirements",),
            "WizClientObject": ("m_gameStats",),
            "WizGameStats": ("m_referenceLevel",),
            "ClientWizEquipmentBehavior": ("m_equipmentSets",),
            "EquipmentSet": ("m_serializedItems", "m_isEquipped"),
            "RequirementList": ("m_requirements", "m_applyNOT", "m_operator")}
# the equip effects' classes whose own fields are read (every property each registers); an effect of another class: its
# type name and GameEffectInfo's fields only ("own fields not read" - reflect.py --class it)
EFFECT_BASE = "GameEffectInfo"
EFFECT_CLASSES = (EFFECT_BASE, "StatisticEffectInfo", "StartingPipEffectInfo", "SpeedEffectInfo", "ProvideSpellEffectInfo",
                  "ProvideCombatTriggerInfo", "MaxManaPercentReductionInfo", "PetStatEffectInfo")
# the requirements' classes, and the bases each one's fields come from too (single inheritance: a base's offsets hold)
REQ_BASE = "Requirement"
REQ_CLASSES = (REQ_BASE, "ReqNumeric", "ReqMagicLevel", "ReqSchoolOfFocus", "ReqIsSchool", "ReqHasBadge")
REQ_BASES = {"ReqMagicLevel": ("ReqNumeric",)}
CLASSES = tuple(sorted(set(NEED) | set(OPTIONAL) | set(EFFECT_CLASSES) | set(REQ_CLASSES)))
ITEMS_CAP = 400          # backpack items walked at most (150 slots + emotes)
EQUIPPED_CAP = 64
SETS_CAP = 20
SET_IDS_CAP = 64
EFFECTS_CAP = 50         # equip effects of one item at most
REQS_CAP = 24            # requirements of one item at most
FIELDS_CAP = 24          # fields read from one effect / requirement at most
TPL_CAP = 5000           # templates kept at most
# a field's reader by its type (reflect.guess_types' names)
READERS = {"int": "i32", "unsigned int": "u32", "float": "f32", "std::string": "str", "std::wstring": "wstr",
           "bool": "flag", "unsigned char (u8)": "u8", "gid (u64)": "u64"}
STR_NAME = re.compile(r"^m_(s[A-Z]|.*(Name|School|Text|String|Template)$)")
FLAG_NAME = re.compile(r"^m_(b[A-Z]|applyNOT$)")
SKIP_TYPE = re.compile(r"std::(vector|list)|SharedPointer|\*")


def ptr_ok(v):
    """a user-mode address (navmem.ptr_ok: heap objects, and the exe's own sections at 0x7FF6...)"""
    return isinstance(v, int) and 0x10000 <= v < 0x7FFFFFFF0000


def parse_set_ids(data):
    """the global ids in an EquipmentSet's m_serializedItems bytes (u16 n, then n u64s) - None when they don't add up
    (bagmem's / deckmem's)"""
    if data is None:
        return None
    if len(data) < 2:
        return [] if not data else None
    n = struct.unpack_from("<H", data, 0)[0]
    if n > SET_IDS_CAP or 2 + 8 * n > len(data):
        return None
    return [struct.unpack_from("<Q", data, 2 + 8 * i)[0] for i in range(n)]


def either(raw4):
    """a 4-byte number whose type isn't known: an int when it reads as a small one (|v| < 1e6), else a float when it
    reads as a plausible one (0, or 1e-3 < |v| < 1e7), else None - 100 and 100.0 can't be mistaken (100.0's bits read
    as an int are 1120403456; 100's as a float a denormal)"""
    if raw4 is None or len(raw4) < 4:
        return None
    i = struct.unpack_from("<i", raw4)[0]
    if abs(i) < 1000000:
        return i
    f = struct.unpack_from("<f", raw4)[0]
    if math.isfinite(f) and (f == 0 or 1e-3 < abs(f) < 1e7):
        return round(f, 4)
    return None


def kind_of(prop, ty):
    """how a field is read: READERS' for its guessed type, "skip" for a list / pointer, else by its name - "str", "flag" -
    else "num" (either)"""
    if ty in READERS:
        return READERS[ty]
    if ty and SKIP_TYPE.search(ty):
        return "skip"
    if STR_NAME.match(prop):
        return "str"
    if FLAG_NAME.match(prop):
        return "flag"
    return "num"


class GearMem:
    """the wizard's gear - see the top. Not thread-safe: call it under navmem's lock (as bagmem / deckmem)"""

    def __init__(self, st, hm, log=None, props=None, types=None):
        """props: {class: {property: offset or (offset, adder rva)}}, types: {class: {property: type}} - tests only (no
        code copy read)"""
        self.log = log or (lambda msg: None)
        t0 = time.perf_counter()
        self.st, self.p, self.hm = st, st.p, hm
        self.build = getattr(getattr(st, "m", None), "build", "")
        if props is None:
            props, types = self._lookup(st)
        self.P = {c: {k: (v[0] if isinstance(v, tuple) else v) for k, v in (props.get(c) or {}).items()} for c in CLASSES}
        self.T = {c: dict((types or {}).get(c) or {}) for c in CLASSES}
        missing = [c + "." + k for c, ks in NEED.items() for k in ks if k not in self.P[c]]
        if missing:
            raise LookupError("reflected properties not found in this build (%s): %s" % (self.build, ", ".join(missing)))
        self.lack = [c + "." + k for c, ks in OPTIONAL.items() for k in ks if k not in self.P[c]]
        self.lack += [c for c in EFFECT_CLASSES + REQ_CLASSES if not self.P[c]]
        self.tpl = {}            # template id -> (object name, adjectives, display key) - read whole
        self.gear = {}           # template id -> {effects, reqs} - read whole
        self.attach_s = time.perf_counter() - t0
        self.log("gearmem: ready in %.2f s%s" % (self.attach_s, (" - not in this build: " + ", ".join(self.lack))
                                                 if self.lack else ""))

    def _lookup(self, st):
        """({class: {property: (offset, adder rva)}}, {class: {property: type}}) - the classes' registrations in a copy of
        the game's code, each property's type by its adder (reflect.guess_types over reflect.ANCHORS' classes)"""
        import handmem as H
        import questmem as Q
        import reflect as R
        img = H.shared_image(st)
        raw = {}
        for c in set(CLASSES) | {a[0] for a in R.ANCHORS}:
            try:
                p = Q.class_props(img, c)[0]
                raw[c] = {k: (v[0], v[1]) for k, v in p.items()}
            except Exception as e:  # noqa: BLE001 - that class left out (NEED says so)
                self.log("gearmem: %s couldn't be read (%r)" % (c, e))
                raw[c] = {}
        del img
        adders = R.guess_types(raw)
        types = {c: {k: adders.get(a, "?") if a is not None else "?" for k, (_o, a) in raw[c].items()} for c in raw}
        return raw, types

    # ------------------------------------------------------------------ small readers
    def off(self, cls, prop):
        return self.P.get(cls, {}).get(prop)

    def rd(self, a, n):
        return self.p.try_read(a, n) if ptr_ok(a) else None

    def u64(self, a):
        b = self.rd(a, 8)
        return struct.unpack("<Q", b)[0] if b else 0

    def u32(self, a):
        b = self.rd(a, 4)
        return struct.unpack("<I", b)[0] if b else None

    def i32(self, a):
        b = self.rd(a, 4)
        return struct.unpack("<i", b)[0] if b else None

    def f32(self, a):
        b = self.rd(a, 4)
        if not b:
            return None
        f = struct.unpack("<f", b)[0]
        return round(f, 4) if math.isfinite(f) else None

    def u8(self, a):
        b = self.rd(a, 1)
        return b[0] if b else None

    def flag(self, a):
        """a bool member: True / False, None when it's neither 0 nor 1"""
        v = self.u8(a)
        return None if v not in (0, 1) else bool(v)

    def tname(self, obj):
        return self.st.tn.of(obj) if ptr_ok(obj) else None

    def string(self, a):
        return self.p.try_string(a) if ptr_ok(a) else None

    def wstr(self, a):
        raw = self.rd(a, 0x20)
        if not raw:
            return None
        size, cap = struct.unpack_from("<QQ", raw, 0x10)
        if size > 0x2000 or cap < size or cap > 0x100000:
            return None
        data = raw[:size * 2] if cap < 8 else (self.rd(struct.unpack_from("<Q", raw)[0], size * 2) if size else b"")
        try:
            return data.decode("utf-16-le") if data is not None else None
        except UnicodeDecodeError:
            return None

    def raw_string(self, a, limit=0x1000):
        """an MSVC x64 std::string's bytes (16-byte inline buffer or a pointer, size @+0x10, capacity @+0x18), or None"""
        raw = self.rd(a, 0x20)
        if not raw:
            return None
        size, cap = struct.unpack_from("<QQ", raw, 0x10)
        if size > limit or cap < size or cap > 0x100000:
            return None
        if cap < 16:
            return raw[:size]
        return self.rd(struct.unpack_from("<Q", raw)[0], size) if size else b""

    def slist(self, a, cap):
        """(its size, [the pointer at each node's +0x10]) of an MSVC std::list<SharedPointer<T>> at a ({head, size}; node:
        next, prev, value) - walked to cap nodes at most; (None, []) unreadable. Fewer than its size: cut short (callers
        check)"""
        b = self.rd(a, 16)
        if not b:
            return None, []
        head, size = struct.unpack("<QQ", b)
        if not ptr_ok(head) or size > 1000000:
            return None, []
        out, n = [], self.u64(head)
        while ptr_ok(n) and n != head and len(out) < min(size, cap):
            out.append(self.u64(n + 0x10))
            n = self.u64(n)
        return size, out

    def str_list(self, a, cap=40):
        """the strings of an MSVC std::list<std::string> at a - None unreadable, longer than cap or not read whole
        (bagmem's)"""
        b = self.rd(a, 16)
        if not b:
            return None
        head, size = struct.unpack("<QQ", b)
        if not ptr_ok(head) or size > cap:
            return None
        out, n = [], self.u64(head)
        while ptr_ok(n) and n != head and len(out) < size:
            s = self.string(n + 0x10)
            if s is None:
                return None
            out.append(s)
            n = self.u64(n)
        return out if len(out) == size else None

    def vec16(self, a, limit=256):
        """the objects of a std::vector<SharedPointer<T>> at a (begin, end: 16-byte elements)"""
        b = self.rd(a, 16)
        if not b:
            return []
        x, y = struct.unpack("<QQ", b)
        if not (ptr_ok(x) and x <= y <= x + 16 * limit and (y - x) % 16 == 0):
            return []
        raw = self.rd(x, y - x) or b""
        return [v for v in (struct.unpack_from("<Q", raw, i)[0] for i in range(0, len(raw) - 7, 16)) if ptr_ok(v)]

    def field(self, obj, cls, prop):
        """one field of obj - its class cls's property prop - read by its type (kind_of); None not read"""
        a = obj + self.P[cls][prop]
        k = kind_of(prop, self.T[cls].get(prop, "?"))
        if k == "str":
            return self.string(a)
        if k == "wstr":
            return self.wstr(a)
        if k == "flag":
            return self.flag(a)
        if k == "i32":
            return self.i32(a)
        if k == "u32":
            return self.u32(a)
        if k == "f32":
            return self.f32(a)
        if k == "u8":
            return self.u8(a)
        if k == "u64":
            return self.u64(a) or None
        if k == "num":
            return either(self.rd(a, 4))
        return None

    def fields(self, obj, classes):
        """{property: value} of obj's fields in classes (its own class first, then its bases: each class's own properties
        - listed the base's first, by offset; the first class's value kept for a name two have), FIELDS_CAP at most"""
        out = {}
        for c in reversed(classes):
            for prop in sorted(self.P.get(c) or {}, key=lambda k: self.P[c][k]):
                if prop not in out and len(out) >= FIELDS_CAP:
                    continue
                out[prop] = self.field(obj, c, prop)
        return out

    # ------------------------------------------------------------------ the wizard
    def player(self):
        """(the wizard's WizClientObject - the camera's object, "") or (0, why) - deckmem's way"""
        st = self.st
        try:
            gc = st.gameclient()
        except Exception as e:  # noqa: BLE001 - navmem's ReadError and the like
            return 0, "no GameClient (%s)" % e
        if not ptr_ok(gc):
            return 0, "no GameClient yet (not in the game world)"
        try:
            _pl, why = st.player(gc)
        except Exception as e:  # noqa: BLE001
            return 0, "the wizard: %s" % e
        o = st.o
        if o.get("gc_elastic_cam") is None or o.get("cam_attached_object") is None:
            return 0, why or "no camera (not in the game world)"
        co = self.u64(self.u64(gc + o["gc_elastic_cam"]) + o["cam_attached_object"])
        tn = self.tname(co)
        if not tn or not tn.endswith("ClientObject"):
            return 0, "the camera follows no wizard (%s)" % (tn or "nothing")
        return co, ""

    def behaviors(self, obj):
        """{type name: behavior} of an object's m_inactiveBehaviors (the first of each type)"""
        out = {}
        for b in self.vec16(obj + self.P["CoreObject"]["m_inactiveBehaviors"]):
            tn = self.tname(b)
            if tn and tn not in out:
                out[tn] = b
        return out

    def level(self, co):
        """the wizard's level (WizGameStats.m_referenceLevel), None not read"""
        gso, lvo = self.off("WizClientObject", "m_gameStats"), self.off("WizGameStats", "m_referenceLevel")
        if gso is None or lvo is None:
            return None
        gs = self.u64(co + gso)
        if self.tname(gs) != "WizGameStats":
            return None
        v = self.i32(gs + lvo)
        return v if v is not None and 0 < v <= 1000 else None

    # ------------------------------------------------------------------ templates
    def template_info(self, tid):
        """(object name, [adjectives], display key) of template id tid - None each not read; kept once name and adjectives
        were read whole"""
        if tid in self.tpl:
            return self.tpl[tid]
        name = adjs = key = None
        t = self.hm.template(tid) if tid else 0
        if t and (self.tname(t) or "").endswith("Template"):
            GT = self.P["GameObjectTemplate"]
            name = self.string(t + GT["m_objectName"])
            adjs = self.str_list(t + GT["m_adjectiveList"])
            if adjs is not None:
                adjs = [a for a in adjs if a]
            if "m_displayName" in GT:
                key = self.string(t + GT["m_displayName"])
        got = (name, adjs, key)
        if name is not None and adjs is not None:
            if len(self.tpl) > TPL_CAP:
                self.tpl.clear()
            self.tpl[tid] = got
        return got

    def effects(self, t):
        """[{type, fields, own}] of a template's equip effects (own False: its class's own fields not read - not among
        EFFECT_CLASSES / this build's) - None unreadable or cut short"""
        size, effs = self.slist(t + self.P["ItemTemplate"]["m_equipEffects"], EFFECTS_CAP)
        if size is None or size > EFFECTS_CAP or len(effs) != size:
            return None
        out = []
        for e in effs:
            tn = self.tname(e)
            if not tn:
                return None
            own = bool(self.P.get(tn)) if tn in self.P else False
            out.append({"type": tn, "fields": self.fields(e, ((tn,) if own else ()) + (EFFECT_BASE,)), "own": own})
        return out

    def requirements(self, t):
        """{op, not, list [{type, fields, own}]} of a template's equip requirements - {op None, not None, list []} when it
        has none (no RequirementList), None unreadable (this build has no m_equipRequirements, a list cut short, an
        object not of its type)"""
        ro = self.off("ItemTemplate", "m_equipRequirements")
        if ro is None:
            return None
        rl = self.u64(t + ro)
        if not rl:
            return {"op": None, "not": None, "list": []}
        if self.tname(rl) != "RequirementList":
            return None
        RL = self.P["RequirementList"]
        out = {"op": None, "not": None, "list": []}
        if "m_operator" in RL:
            out["op"] = either(self.rd(rl + RL["m_operator"], 4))
        if "m_applyNOT" in RL:
            out["not"] = self.flag(rl + RL["m_applyNOT"])
        if "m_requirements" not in RL:
            return None
        size, reqs = self.slist(rl + RL["m_requirements"], REQS_CAP)
        if size is None or size > REQS_CAP or len(reqs) != size:
            return None
        for q in reqs:
            tn = self.tname(q)
            if not tn:
                return None
            own = bool(self.P.get(tn)) if tn in self.P else False
            chain = ((tn,) if own else ()) + tuple(b for b in REQ_BASES.get(tn, ()) if self.P.get(b)) + (REQ_BASE,)
            out["list"].append({"type": tn, "fields": self.fields(q, chain), "own": own})
        return out

    def gear_info(self, tid):
        """{effects, reqs} of a gear template (each None not read) - kept once both were read"""
        hit = self.gear.get(tid)
        if hit is not None:
            return hit
        t = self.hm.template(tid) if tid else 0
        if not t or not (self.tname(t) or "").endswith("Template"):
            return {"effects": None, "reqs": None}
        got = {"effects": self.effects(t), "reqs": self.requirements(t)}
        if got["effects"] is not None and (got["reqs"] is not None or self.off("ItemTemplate", "m_equipRequirements")
                                           is None):
            if len(self.gear) > TPL_CAP:
                self.gear.clear()
            self.gear[tid] = got
        return got

    # ------------------------------------------------------------------ the read
    def read(self):
        """({worn [item], bag [item - gear of the planned slots, and any whose slot couldn't be read], bag_gids [every
        backpack item's id], bag_size, sets [{n, equipped, ids}], sets_ok, level, player_gid, ms}, "") or (None, why).
        item: {gid, tid, name (object name), display_key, adjs, slot ("" not a slot's, None not read), crowns, nosell,
        effects, reqs, sets [n...], where}. Never raises"""
        t0 = time.perf_counter()
        try:
            r, why = self._read()
        except Exception as e:  # noqa: BLE001 - never into navmem
            return None, "reading the gear failed (%r)" % (e,)
        if r is not None:
            r["ms"] = round((time.perf_counter() - t0) * 1000, 1)
        return r, why

    def _item(self, it, where, details):
        CO = self.P["CoreObject"]
        gid = self.u64(it + CO["m_globalID.m_full"])
        tid = self.u32(it + CO["m_templateID.m_full"])
        name, adjs, key = self.template_info(tid)
        slot = G.slot_of(adjs)
        # (slot: "hat"..., "" read and not a slot's, None its template or adjective list NOT read - not known, never taken
        # for "not gear": gearrank judges such a piece "unknown", which holds a quick sell)
        d = {"gid": gid or None, "tid": tid, "name": name, "display_key": key, "adjs": adjs, "slot": slot,
             "crowns": adjs is None or "FLAG_CrownsOnly" in adjs or name is None or name.startswith(("Crown-", "Crowns-")),
             "nosell": adjs is not None and "FLAG_NoSell" in adjs, "effects": None, "reqs": None, "sets": [],
             "where": where}
        if details and slot in G.SLOTS:
            d.update(self.gear_info(tid))
        return d

    def _read(self):
        co, why = self.player()
        if not co:
            return None, why
        CO = self.P["CoreObject"]
        bs = self.behaviors(co)
        eq = next((b for n, b in bs.items() if n.endswith("WizEquipmentBehavior")), 0)
        inv = next((b for n, b in bs.items() if n.endswith("WizInventoryBehavior")), 0)
        if not eq:
            return None, "no equipment on the wizard (its equipment behavior wasn't found)"
        if not inv:
            return None, "no backpack on the wizard (its inventory behavior wasn't found)"
        r = {"worn": [], "bag": [], "bag_gids": [], "bag_size": None, "sets": [], "sets_ok": False,
             "level": self.level(co), "player_gid": self.u64(co + CO["m_globalID.m_full"]) or None}
        esize, worn = self.slist(eq + self.P["ClientEquipmentBehavior"]["m_itemList"], EQUIPPED_CAP)
        if esize is None:
            return None, "the worn items can't be read"
        if len(worn) < min(esize, EQUIPPED_CAP):
            return None, "the worn items' list broke off after %d of %d (read again in a moment)" % (len(worn), esize)
        bsize, bag = self.slist(inv + self.P["InventoryBehaviorBase"]["m_itemList"], ITEMS_CAP)
        if bsize is None:
            return None, "the backpack's item list can't be read"
        if len(bag) < min(bsize, ITEMS_CAP):
            return None, "the backpack's item list broke off after %d of %d (read again in a moment)" % (len(bag), bsize)
        r["bag_size"] = bsize
        for it in worn:
            if (self.tname(it) or "").endswith("ClientObjectItem"):
                r["worn"].append(self._item(it, "worn", True))
        for it in bag:
            if not (self.tname(it) or "").endswith("ClientObjectItem"):
                continue
            gid = self.u64(it + CO["m_globalID.m_full"])
            if gid:
                r["bag_gids"].append(gid)
            d = self._item(it, "backpack", True)
            # (gear of the planned slots - and an item whose slot couldn't be read: kept, not judged, never left out as if
            # it weren't gear - a full backpack holding it isn't quick sold on the gear pass's word)
            if d["slot"] in G.SLOTS or d["slot"] is None:
                r["bag"].append(d)
        # the Equipment Sets (bagmem's) - each item's sets
        so, ES = self.off("ClientWizEquipmentBehavior", "m_equipmentSets"), self.P["EquipmentSet"]
        if so is not None and all(k in ES for k in ("m_serializedItems", "m_isEquipped")):
            ssize, sets = self.slist(eq + so, SETS_CAP)
            ok = ssize is not None and len(sets) == ssize
            for i, es in enumerate(sets, 1):
                if self.tname(es) != "EquipmentSet":
                    ok = False
                    continue
                ids = parse_set_ids(self.raw_string(es + ES["m_serializedItems"]))
                if ids is None:
                    ok, ids = False, []
                r["sets"].append({"n": i, "equipped": self.flag(es + ES["m_isEquipped"]), "ids": ids})
            r["sets_ok"] = ok
            for d in r["worn"] + r["bag"]:
                d["sets"] = [s["n"] for s in r["sets"] if d["gid"] in s["ids"]]
        return r, ""


# ============================================================================ answers
def finish(r, lang):
    """each item's display name from its key (lang(key) -> text or None) - outside navmem's lock (the name tables are
    read from Root.wad the first time)"""
    for d in ((r or {}).get("worn") or []) + ((r or {}).get("bag") or []):
        t = None
        if d.get("display_key") and lang is not None:
            try:
                t = lang(d["display_key"])
            except Exception:  # noqa: BLE001 - none then
                t = None
        d["display"] = t
    return r


def _v(v):
    return "" if v is None else str(v).replace("|", "/").replace("\r", " ").replace("\n", " ")


def item_lines(r, effects=False):
    """gearmem.py's own lines (to read, and with --effects to send back): an item a line - where|slot|gid hex|tid|object
    name|display|sets|stats (gearrank.stats_text)|reqs (gearrank.reqs_text); --effects: effect|type|own|k=v,... and
    req|type|own|k=v,... under each; read|worn n|bag gear n|bag items|level|sets ok|ms"""
    out = []
    for d in (r.get("worn") or []) + (r.get("bag") or []):
        st, _u, how = G.item_stats(d.get("effects"))
        out.append("|".join([d["where"], _v(d.get("slot")), "%x" % d["gid"] if d.get("gid") else "", _v(d.get("tid")),
                             _v(d.get("name")), _v(d.get("display")), ",".join(str(n) for n in d.get("sets") or []),
                             G.stats_text(st, how), G.reqs_text(d.get("reqs"))]))
        if effects:
            for e in d.get("effects") or []:
                out.append("  effect|%s|%d|%s" % (_v(e["type"]), e.get("own", False),
                                                   ",".join("%s=%s" % (k, _v(v)) for k, v in e["fields"].items())))
            for q in (d.get("reqs") or {}).get("list") or []:
                out.append("  req|%s|%d|%s" % (_v(q["type"]), q.get("own", False),
                                                ",".join("%s=%s" % (k, _v(v)) for k, v in q["fields"].items())))
    out.append("read|%d|%d|%s|%s|%d|%s" % (len(r.get("worn") or []), len(r.get("bag") or []), _v(r.get("bag_size")),
                                          _v(r.get("level")), 1 if r.get("sets_ok") else 0, _v(r.get("ms"))))
    return out


# ============================================================================ the command line
def _main(argv=None):
    import argparse
    ap = argparse.ArgumentParser(description="read-only: the wizard's worn gear and the backpack's, with their equip "
                                             "effects and requirements")
    ap.add_argument("--json", action="store_true")
    ap.add_argument("--effects", action="store_true", help="each equip effect's and requirement's type and fields")
    ap.add_argument("--out", default="", help="also write the answer to this file (to send)")
    a = ap.parse_args(argv)
    import navmem as N
    import handmem as H
    pids = N.find_pids()
    if not pids:
        sys.exit("the game is not running")
    fg = N.foreground_pid()
    st = N._Attached(fg if fg in pids else pids[0], lambda m: None)
    try:
        hm = H.HandMem(st, log=print)
        gm = GearMem(st, hm, log=print)
        r, why = gm.read()
        lines = ["# python gearmem.py%s (%s) - build %s" % (" --effects" if a.effects else "",
                                                           time.strftime("%Y-%m-%d %H:%M:%S"), gm.build)]
        if gm.lack:
            lines.append("# not in this build: " + ", ".join(gm.lack))
        if r is None:
            lines.append("none|" + _v(why))
        else:
            finish(r, hm.lang_text)
            lines += item_lines(r, a.effects)
            if a.json:
                lines.append(json.dumps(r, default=str))
    finally:
        st.close()
    print("\n".join(lines))
    if a.out:
        with open(a.out, "w", encoding="utf-8") as f:
            f.write("\n".join(lines) + "\n")
        print("(written to %s - %d lines)" % (os.path.abspath(a.out), len(lines)))
    return 0


if __name__ == "__main__":
    _main()
