"""petmem - READ-ONLY reader of the wizard's PETS (every pet it owns: the one worn and those in the backpack) in a running
Wizard101 client: each pet's global id, where it is, its template and name, its level (Baby ... Ultra) and its level's
power cards - plus the values not confirmed in the game yet (XP, talents, derby talents, stats, the wizard's pet energy)
once their reflected names are pinned (PINS: None till then). The vision helper's (navmem.NavMem.pets - /pets: Quick
Sell keeps pets with the wanted talents, vision\\petplan.py), deckmem's way. Goal 6 of TODO.md, "Perfect pets".

    pm = PetMem(st, hm, log=print)   # st: navmem's attached game (navmem._Attached), hm: handmem.HandMem (template map,
                                     # names); about half a second once a game (the reflection lookup). LookupError when
                                     # a needed class or property isn't in this build
    r = pm.read(pace=f)              # {pets: [...], energy, energy_max, whole, why, ms, lack} - never raises
    print("\\n".join(pet_lines(r)))   # one line a pet, then energy| and pets|
    cards = level_cards(rd, level_entries(rd, tpl, off_levels, off_level), level, PL)
                                     # a pet template's power cards at a level (deckmem.DeckMem.pet_cards' too)

    python petmem.py [--json] [-n 1] [-i 2] [--pin FIELD=Class.m_prop:KIND ...] [--out petread.txt]
                                     readings from the command line; --pin tries a value's name for one run (xp=
                                     BasePetItemBehavior.m_XP:u32 - FIELDS and KINDS below) - read it while the game
                                     shows the number (the pet window), and say which name and kind matched
                                     (never --out pets.txt: that's the wanted talents QuickSell.ahk reads)

SAFETY. The game is opened by navmem.py's Proc - PROCESS_VM_READ | PROCESS_QUERY_INFORMATION (falling back to
PROCESS_VM_READ | PROCESS_QUERY_LIMITED_INFORMATION) and nothing else - and only read: ReadProcessMemory (try_read /
try_string). Nothing is ever written, allocated, injected, hooked, suspended or debugged; no window is touched and no
input is sent. Every class and property offset is found by NAME in a copy of the game's code (its reflection
registration: handmem.Image / questmem.class_props) - a pin names its property, never an offset; every object is checked
by its type name before it's used. No memory scan: everything is followed from the wizard's own object (the camera's).

FAILS SOFT. read() never raises: whatever goes wrong comes back as why. A value that can't be read for sure is None, never
a guess; whole is False when the worn items or the backpack weren't read whole - a list cut short, an entry in it not an
item, or an item whose global id or behaviours couldn't be read (a pet may be missing - QuickSell.ahk then keeps every
pet; it also checks the backpack's pets read against /bag's Pet count). The constructor raises LookupError when a needed
class or property isn't in this build. Importable anywhere (no Windows module at import - the tests run it on made-up
memory: test_petmem.py).

WHAT IS READ (deckmem's offsets, build 6A9721E9-370E000 - found by name each attach; the numbers are what they were):
  the wizard    the camera's object (navmem: GameClient -> ElasticCamController -> its ClientObject: a WizClientObject)
                  CoreObject.m_inactiveBehaviors +0xE0: ClientWizEquipmentBehavior, ClientWizInventoryBehavior
  worn          ClientEquipmentBehavior.m_itemList +0x78 - std::list of SharedPointer<WizClientObjectItem>
  backpack      InventoryBehaviorBase.m_itemList +0x70 of the ClientWizInventoryBehavior
  a pet         an item whose behaviours hold a *PetItemBehavior (ClientPetItemBehavior : BasePetItemBehavior):
                  CoreObject.m_globalID.m_full, m_templateID.m_full; BasePetItemBehavior.m_level +0x70 (u8: 1 Baby,
                  2 Teen, 3 Adult, 4 Ancient, 5 Epic, 6 Mega, 7 Ultra); its template - the first pointer in it typed
                  PetItemBehaviorTemplate (+0x58 seen) - .m_Levels +0x130: a std::list holding PetLevelInfo BY VALUE
                  (the object at node +0x10): m_level +0x48 (u8), m_powerCardCount +0x54, m_powerCardName +0x58,
                  m_powerCardName2 +0x78, m_powerCardName3 +0x98 - the entry of the pet's level: its power cards
                the item's template (handmem's template map): GameObjectTemplate.m_objectName +0x60, m_displayName +0xA8
                  (a name-table key: the species as the game shows it)
  energy        WizClientObject.m_gameStats -> WizGameStats (bagmem's way) - its energy properties once pinned

NOT CONFIRMED IN THE GAME YET - PINS is empty and these read None: a pet's XP and the XP its next level needs, its
talents and derby talents (manifested only, or the hidden pool too?), its stats and their maxima, the wizard's pet
energy. Find the names with "python reflect.py --class BasePetItemBehavior,ClientPetItemBehavior,PetItemBehaviorTemplate,
PetLevelInfo,WizGameStats --grep "XP|Exp|Talent|Stat|Energy"" (their type guess too), try one with --pin while the game
shows it, then pin it here (field: (class, property NAME, kind)) - nothing in the bot acts on these yet (petplan's
decisions read them; QuickSell keeps every pet whose talents aren't read)."""
import json
import struct
import sys
import time

# ============================================================================ what is read
NEED = {"CoreObject": ("m_inactiveBehaviors", "m_globalID.m_full", "m_templateID.m_full"),
        "InventoryBehaviorBase": ("m_itemList",),
        "ClientEquipmentBehavior": ("m_itemList",),
        "BasePetItemBehavior": ("m_level",)}
# (read when found: without them that part's None)
OPTIONAL = {"GameObjectTemplate": ("m_objectName", "m_displayName"),
            "PetItemBehaviorTemplate": ("m_Levels",),
            "PetLevelInfo": ("m_level", "m_powerCardCount", "m_powerCardName", "m_powerCardName2", "m_powerCardName3"),
            "WizClientObject": ("m_gameStats",)}
POWER_KEYS = ("m_powerCardName", "m_powerCardName2", "m_powerCardName3")

# The values not confirmed in the game yet: {field: (class, property name, kind)} - EMPTY till each is seen to match the
# game (python petmem.py --pin ...). The class says which object it's read from: a pet behaviour class -> the pet's
# *PetItemBehavior, PetItemBehaviorTemplate -> its template, PetLevelInfo -> a level's entry, WizGameStats -> the
# wizard's stats, any other (talent_name only) -> a talent's template (handmem's template map, by the talent's id)
PINS = {}
PET_CLASSES = ("BasePetItemBehavior", "ClientPetItemBehavior")
PIN_BASES = PET_CLASSES + ("PetItemBehaviorTemplate", "PetLevelInfo", "WizGameStats")
# field: (the objects it may be read from, what it is)
FIELDS = {"xp": (("pet",), "the pet's XP"),
          "level_xp": (("level",), "a PetLevelInfo's XP - read from the NEXT level's entry: xp_next"),
          "talents": (("pet", "template"), "its talents (a list of names, or of talent template ids - talent_name)"),
          "derby": (("pet", "template"), "its derby talents (as talents)"),
          "stats": (("pet", "template"), "its stats (Strength, Intellect, Agility, Will, Power - as they're held)"),
          "max_stats": (("pet", "template"), "their maxima"),
          "energy": (("stats",), "the wizard's pet energy"),
          "energy_max": (("stats",), "its maximum"),
          "talent_name": (("talent",), "a talent template's name (when talents are ids) - a name-table key gets its "
                                       "words")}
KINDS = ("u8", "u16", "u32", "i32", "f32", "str", "vec_u32", "list_u32", "vec_str", "list_str")
LEVELS = {1: "Baby", 2: "Teen", 3: "Adult", 4: "Ancient", 5: "Epic", 6: "Mega", 7: "Ultra"}
ITEMS_CAP = 400          # backpack items walked at most (deckmem's)
EQUIPPED_CAP = 64        # worn items at most
LEVELS_CAP = 32          # PetLevelInfo entries at most (7 levels)
LIST_CAP = 64            # a pinned list's entries at most
VEC_LIMIT = 256          # behaviours an object holds at most


# ============================================================================ pure helpers
def ptr_ok(v):
    """a user-mode address (navmem.ptr_ok: heap objects, and the exe's own sections at 0x7FF6...)"""
    return isinstance(v, int) and 0x10000 <= v < 0x7FFFFFFF0000


def level_name(level):
    """1 -> 'Baby' ... 7 -> 'Ultra'; None for anything else"""
    return LEVELS.get(level) if isinstance(level, int) else None


def base_of(cls):
    """which object a pin on class cls is read from: 'pet', 'template', 'level', 'stats' or 'talent' (any other class)"""
    if cls in PET_CLASSES:
        return "pet"
    return {"PetItemBehaviorTemplate": "template", "PetLevelInfo": "level", "WizGameStats": "stats"}.get(cls, "talent")


def check_pins(pins):
    """(the pins that make sense, [why each other was dropped]) of {field: (class, property, kind)}: a known field, a
    known kind, a property name (m_...), a class its field may be read from"""
    good, bad = {}, []
    for field, spec in (pins or {}).items():
        try:
            cls, prop, kind = spec
        except (TypeError, ValueError):
            bad.append("%s: not (class, property, kind)" % field)
            continue
        if field not in FIELDS:
            bad.append("%s: no such field (%s)" % (field, ", ".join(sorted(FIELDS))))
        elif kind not in KINDS:
            bad.append("%s: no such kind %r (%s)" % (field, kind, ", ".join(KINDS)))
        elif not (isinstance(cls, str) and cls and isinstance(prop, str) and prop.startswith("m_")):
            bad.append("%s: %r.%r isn't a class and a property name" % (field, cls, prop))
        elif base_of(cls) not in FIELDS[field][0]:
            bad.append("%s: read from %s, not %s (%s)" % (field, "/".join(FIELDS[field][0]), base_of(cls), cls))
        else:
            good[field] = (cls, prop, kind)
    return good, bad


def parse_pin(text):
    """'xp=BasePetItemBehavior.m_XP:u32' -> ('xp', ('BasePetItemBehavior', 'm_XP', 'u32')); None when it isn't one"""
    try:
        field, rest = text.split("=", 1)
        where, kind = rest.rsplit(":", 1)
        cls, prop = where.split(".", 1)
    except ValueError:
        return None
    field, cls, prop, kind = field.strip(), cls.strip(), prop.strip(), kind.strip()
    if not (field and cls and prop and kind):
        return None
    return field, (cls, prop, kind)


def level_entries(rd, tpl, off_levels, off_level, cap=LEVELS_CAP):
    """[(level, PetLevelInfo address)] of a PetItemBehaviorTemplate's m_Levels (at tpl + off_levels): a std::list
    {head, size} holding each PetLevelInfo BY VALUE in its node (+0x10), m_level (u8) at off_level - every entry
    checked by its type name; None when it can't be read (the head bad, more than cap, an entry not a PetLevelInfo,
    the walk cut short of the list's own size - a level then not reached would read as no cards, never a guess).
    rd: a reader with _rd, u64, u8, tname and pace (deckmem.DeckMem's or PetMem's)"""
    if not ptr_ok(tpl):
        return None
    b = rd._rd(tpl + off_levels, 16)
    if not b:
        return None
    head, size = struct.unpack("<QQ", b)
    if not ptr_ok(head) or size > cap:
        return None
    out, n = [], rd.u64(head)
    while ptr_ok(n) and n != head and len(out) < size:
        rd.pace()
        li = n + 0x10                                     # (the PetLevelInfo itself, in the node)
        if rd.tname(li) != "PetLevelInfo":
            return None
        out.append((rd.u8(li + off_level), li))
        n = rd.u64(n)
    if len(out) != size:                                  # (a next pointer bad mid-walk: not all of it read)
        return None
    return out


def level_cards(rd, entries, level, PL):
    """[(spell m_name, copies, 'pet level N')] of the entry of level among entries (level_entries'): m_powerCardName(2,
    3), each taken m_powerCardCount times - whether the count is for each name isn't known (only one name was seen:
    deckmem's note); [] that level not among them. rd: a reader with i32 and string; PL: PetLevelInfo's offsets"""
    for lv, li in entries or []:
        if lv == level:
            cnt = rd.i32(li + PL["m_powerCardCount"]) or 0
            out = []
            for key in POWER_KEYS:
                nm = rd.string(li + PL[key])
                if nm and cnt > 0:
                    out.append((nm, cnt, "pet level %d" % level))
            return out
    return []


def _f(v):
    """a field: no | or line break; None empty; a flag 1/0"""
    if v is None:
        return ""
    if isinstance(v, bool):
        return "1" if v else "0"
    return str(v).replace("|", "/").replace("\r", " ").replace("\n", " ").strip()


def _list(v):
    """a list field: "" not read (None), "-" read and empty, else its items joined by "," (a comma in one: a space)"""
    if v is None:
        return ""
    if not isinstance(v, (list, tuple)):
        return _f(v)
    if not v:
        return "-"
    return ",".join(_f(x).replace(",", " ") for x in v)


def pet_lines(r, why=""):
    """/pets' answer for read()'s reading (r None: none|<why>):
    pet|gid hex|where|level|level name|template id|object name|display|cards|xp|xp next|talents|derby|stats|max stats|
        behavior class                 (one a pet, the worn one first; cards "name*copies,..." - the power cards of its
                                       level; a list field "" not read, "-" none)
    energy|current|max                 ("" not read - not pinned yet)
    pets|n|whole|ms|why                (whole 1: the worn items and the backpack both read whole, every item's id and
                                       behaviours too - no pet missed)"""
    if not r:
        return ["none|" + _f(why or "the pets can't be read")]
    out = []
    for p in r.get("pets") or []:
        cards = None if p.get("cards") is None else ["%s*%s" % (nm, q) for nm, q, _how in p["cards"]]
        out.append("|".join(["pet", "%x" % p["gid"], _f(p.get("where")), _f(p.get("level")), _f(p.get("level_name")),
                             _f(p.get("template_id")), _f(p.get("object_name")), _f(p.get("display")), _list(cards),
                             _f(p.get("xp")), _f(p.get("xp_next")), _list(p.get("talents")), _list(p.get("derby")),
                             _list(p.get("stats")), _list(p.get("max_stats")), _f(p.get("behavior_class"))]))
    out.append("|".join(["energy", _f(r.get("energy")), _f(r.get("energy_max"))]))
    out.append("|".join(["pets", str(len(r.get("pets") or [])), _f(bool(r.get("whole"))), _f(r.get("ms")),
                         _f(r.get("why") or why)]))
    return out


# ============================================================================ the reader
class PetMem:
    """the wizard's pets - see the top. Not thread-safe: call it under navmem's lock (as deckmem / bagmem)"""

    def __init__(self, st, hm, log=None, props=None, pins=None):
        """props: {class: {property: offset}} - tests only (no code copy read); pins: {field: (class, property, kind)}
        (PINS when None - the command line's --pin adds to them)"""
        self.log = log or (lambda msg: None)
        t0 = time.perf_counter()
        self.st, self.p, self.hm = st, st.p, hm
        self.build = getattr(getattr(st, "m", None), "build", "")
        self.pins, dropped = check_pins(PINS if pins is None else pins)
        for d in dropped:
            self.log("petmem: a pin dropped - " + d)
        classes = sorted(set(NEED) | set(OPTIONAL) | set(PIN_BASES) | {c for c, _k, _t in self.pins.values()})
        if props is None:
            import handmem as H
            import questmem as Q
            img = H.shared_image(st)
            props = {c: {k: v[0] for k, v in Q.class_props(img, c)[0].items()} for c in classes}
            del img
        self.P = {c: dict(props.get(c) or {}) for c in classes}
        missing = [c + "." + k for c, ks in NEED.items() for k in ks if k not in self.P[c]]
        if missing:
            raise LookupError("reflected properties not found in this build (%s): %s" % (self.build, ", ".join(missing)))
        self.lack = [c + "." + k for c, ks in OPTIONAL.items() for k in ks if k not in self.P[c]]
        self.lack += ["%s (pin %s)" % (c + "." + k, f) for f, (c, k, _t) in sorted(self.pins.items()) if k not in self.P[c]]
        self.o = {}              # places found by type (checked at every read): the pet behaviour's template
        self.info_cache = {}     # item template id -> {object_name, display_key, display} (templates don't change)
        self._pace = None
        self._k = 0
        self.attach_s = time.perf_counter() - t0
        self.log("petmem: ready in %.2f s%s%s" % (self.attach_s,
                                                  (" - pinned: " + ", ".join(sorted(self.pins))) if self.pins else "",
                                                  (" - not in this build: " + ", ".join(self.lack)) if self.lack else ""))

    # ------------------------------------------------------------------ small readers
    def pace(self):
        """read's pace (navmem releases its lock there when it has held it long enough) - raises to stop the read"""
        if self._pace is not None:
            self._pace()

    def _rd(self, a, n):
        if self._pace is not None:
            self._k += 1
            if not self._k & 7:
                self._pace()
        return self.p.try_read(a, n) if ptr_ok(a) else None

    def off(self, cls, prop):
        return self.P.get(cls, {}).get(prop)

    def u64(self, a):
        b = self._rd(a, 8)
        return struct.unpack("<Q", b)[0] if b else 0

    def u32(self, a):
        b = self._rd(a, 4)
        return struct.unpack("<I", b)[0] if b else None

    def u16(self, a):
        b = self._rd(a, 2)
        return struct.unpack("<H", b)[0] if b else None

    def i32(self, a):
        b = self._rd(a, 4)
        return struct.unpack("<i", b)[0] if b else None

    def f32(self, a):
        b = self._rd(a, 4)
        return round(struct.unpack("<f", b)[0], 3) if b else None

    def u8(self, a):
        b = self._rd(a, 1)
        return b[0] if b else None

    def tname(self, obj):
        return self.st.tn.of(obj) if ptr_ok(obj) else None

    def string(self, a):
        return self.p.try_string(a) if ptr_ok(a) else None

    def slist(self, a, cap):
        """(its size, [the 8 bytes at each node's +0x10]) of an MSVC std::list at a ({head, size}; node: next, prev,
        value) - walked to cap nodes at most; (None, []) unreadable. Fewer than its size: cut short (callers check)"""
        b = self._rd(a, 16)
        if not b:
            return None, []
        head, size = struct.unpack("<QQ", b)
        if not ptr_ok(head) or size > 1000000:
            return None, []
        out, n = [], self.u64(head)
        while ptr_ok(n) and n != head and len(out) < min(size, cap):
            out.append(n + 0x10)
            n = self.u64(n)
            if len(out) % 8 == 0:
                self.pace()
        return size, out

    def vec16(self, a, limit=VEC_LIMIT):
        """the objects of a std::vector<SharedPointer<T>> at a (begin, end: 16-byte elements; a null pointer in it left
        out); [] read and empty (begin = end, 0 when never allocated); None when it can't be read or isn't one (begin
        / end bad, its elements unreadable) - told apart from empty: an item whose behaviours can't be read isn't
        taken for an item with none (a pet missed - read() says so)"""
        b = self._rd(a, 16)
        if not b:
            return None
        x, y = struct.unpack("<QQ", b)
        if x == y and (x == 0 or ptr_ok(x)):
            return []
        if not (ptr_ok(x) and x < y <= x + 16 * limit and (y - x) % 16 == 0):
            return None
        raw = self._rd(x, y - x)
        if raw is None:
            return None
        return [v for v in (struct.unpack_from("<Q", raw, i)[0] for i in range(0, len(raw) - 7, 16)) if ptr_ok(v)]

    def value(self, a, kind, cap=LIST_CAP):
        """the value of a pinned property at a, read as kind (KINDS); None when it can't be read (a list longer than cap,
        a vector that isn't one)"""
        if kind in ("u8", "u16", "u32", "i32", "f32"):
            return getattr(self, kind)(a)
        if kind == "str":
            return self.string(a)
        if kind in ("vec_u32", "vec_str"):
            b = self._rd(a, 16)
            if not b:
                return None
            x, y = struct.unpack("<QQ", b)
            if x == y == 0:
                return []
            step = 4 if kind == "vec_u32" else 0x20
            if not (ptr_ok(x) and x <= y <= x + step * cap and (y - x) % step == 0):
                return None
            if kind == "vec_u32":
                raw = self._rd(x, y - x) if y > x else b""
                return None if raw is None else [struct.unpack_from("<I", raw, i)[0] for i in range(0, len(raw), 4)]
            vals = [self.string(x + i) for i in range(0, y - x, step)]
            return None if any(v is None for v in vals) else vals
        if kind in ("list_u32", "list_str"):
            size, nodes = self.slist(a, cap)
            if size is None or size > cap or len(nodes) != size:
                return None
            vals = [self.u32(v) if kind == "list_u32" else self.string(v) for v in nodes]
            return None if any(v is None for v in vals) else vals
        return None

    def pinned(self, field, bases):
        """the value of a pinned field read from its object (bases: {'pet': behaviour, 'template': ..., 'level': ...,
        'stats': ...}) - None not pinned, its property not in this build, its object not there or not of its class"""
        pin = self.pins.get(field)
        if pin is None:
            return None
        cls, prop, kind = pin
        o = self.off(cls, prop)
        obj = bases.get(base_of(cls))
        if o is None or not ptr_ok(obj):
            return None
        if cls == "ClientPetItemBehavior" and self.tname(obj) != cls:
            return None                                   # (the client class's property on another class's object)
        return self.value(obj + o, kind)

    # ------------------------------------------------------------------ the wizard
    def player(self):
        """(the wizard's WizClientObject - the camera's object, "") or (0, why) - deckmem's way"""
        st = self.st
        try:
            gc = st.gameclient()
            if not ptr_ok(gc):
                return 0, "no GameClient yet (not in the game world)"
            pl, why = st.player(gc)
        except Exception as e:  # noqa: BLE001 - navmem's ReadError and the like
            return 0, "the wizard: %s" % (e,)
        o = st.o
        if o.get("gc_elastic_cam") is None or o.get("cam_attached_object") is None:
            return 0, why or "no camera (not in the game world)"
        co = self.u64(self.u64(gc + o["gc_elastic_cam"]) + o["cam_attached_object"])
        tn = self.tname(co)
        if not tn or not tn.endswith("ClientObject"):
            return 0, "the camera follows no wizard (%s)" % (tn or "nothing")
        return co, ""

    def behaviors(self, obj):
        """{type name: behaviour} of an object's m_inactiveBehaviors (the first of each type) - {} when they can't be
        read (the wizard's: its worn items and backpack then aren't found - not whole)"""
        return self.behaviors_sure(obj)[0]

    def behaviors_sure(self, obj):
        """({type name: behaviour}, sure) - sure False when the vector couldn't be read (vec16 None) or a behaviour's
        type name couldn't: the one not seen could be a pet's (an item's: read() counts it as not read, whole False)"""
        vec = self.vec16(obj + self.P["CoreObject"]["m_inactiveBehaviors"])
        if vec is None:
            return {}, False
        out, sure = {}, True
        for k, b in enumerate(vec):
            if k % 4 == 3:
                self.pace()
            tn = self.tname(b)
            if not tn:
                sure = False
            elif tn not in out:
                out[tn] = b
        return out, sure

    def items(self, beh, prop_cls, cap):
        """(size, [WizClientObjectItem], whole, odd) of an inventory / equipment behaviour's m_itemList; whole: every
        entry walked (no more than cap, none cut short) and every one a *ClientObjectItem; odd: the entries walked that
        weren't one (unreadable - the item being freed or moved as it's read: a pet could be one); (None, [], False, 0)
        unreadable"""
        size, nodes = self.slist(beh + self.P[prop_cls]["m_itemList"], cap)
        if size is None:
            return None, [], False, 0
        its = [self.u64(n) for n in nodes]
        ok = [i for i in its if (self.tname(i) or "").endswith("ClientObjectItem")]
        return size, ok, len(its) == size and len(ok) == len(its), len(its) - len(ok)

    def _typed_member(self, key, obj, tname, span=0x78):
        """the first pointer in obj (span bytes) of type tname - the place kept under key, checked by type every time"""
        off = self.o.get(key)
        if off is not None:
            v = self.u64(obj + off)
            if self.tname(v) == tname:
                return v
        raw = self._rd(obj, span) or b""
        for i in range(8, len(raw) - 7, 8):
            v = struct.unpack_from("<Q", raw, i)[0]
            if ptr_ok(v) and self.tname(v) == tname:
                self.o[key] = i
                return v
        return 0

    def item_info(self, tid):
        """{object_name, display_key, display} of an item template (kept: templates don't change)"""
        hit = self.info_cache.get(tid)
        if hit is not None:
            return dict(hit)
        r = {"object_name": None, "display_key": None, "display": None}
        t = self.hm.template(tid) if tid else 0
        GT = self.P["GameObjectTemplate"]
        if not t:
            return r
        if "m_objectName" in GT:
            r["object_name"] = self.string(t + GT["m_objectName"])
        if "m_displayName" in GT:
            r["display_key"] = self.string(t + GT["m_displayName"])
            try:
                r["display"] = self.hm.lang_text(r["display_key"]) if r["display_key"] else None
            except Exception:  # noqa: BLE001
                r["display"] = None
        if r["object_name"] is not None:
            if len(self.info_cache) > 2000:
                self.info_cache.clear()
            self.info_cache[tid] = r
        return dict(r)

    def talent_names(self, vals):
        """talents as names: a list of strings as it is (a name-table key given its words); ids named by the talent_name
        pin through handmem's template map - None when one can't be named (all or nothing: a talent list read in part
        isn't one)"""
        if vals is None:
            return None
        out = []
        for v in vals:
            if isinstance(v, str):
                nm = v
            else:
                t = self.hm.template(v) if v else 0
                nm = self.pinned("talent_name", {"talent": t}) if t else None
            if not nm:
                return None
            if "_" in nm and " " not in nm:
                try:
                    nm = self.hm.lang_text(nm) or nm
                except Exception:  # noqa: BLE001 - the key as it is
                    pass
            out.append(nm)
        return out

    # ------------------------------------------------------------------ the read
    def read(self, pace=None):
        """{pets, energy, energy_max, whole, why, ms, lack} - never raises. pace: a callable invoked every few reads
        (navmem releases its lock there; it raises to stop the read - why says so).
          pets    [{gid, where ('equipped' / 'backpack'), template_id, object_name, display_key, display, level (1-7),
                  level_name, cards [(spell m_name, copies, how)] (its level's power cards; None not read), behavior_class,
                  and the pinned values - None till pinned: xp, xp_next, talents [names], talent_ids, derby [names],
                  derby_ids, stats, max_stats}] - the worn pet first
          energy, energy_max  the wizard's pet energy (pinned only - None till then)
          whole   True: the worn items and the backpack both read whole, every entry an item whose global id and
                  behaviours were read (no pet missed)"""
        t0 = time.perf_counter()
        out = {"pets": [], "energy": None, "energy_max": None, "whole": False, "why": "", "ms": 0.0,
               "lack": list(self.lack)}
        self._pace = pace
        try:
            self._read(out)
        except Exception as e:  # noqa: BLE001 - never into the caller
            out["whole"] = False
            out["why"] = "the pets couldn't be read (%r)" % (e,)
        finally:
            self._pace = None
        out["ms"] = round((time.perf_counter() - t0) * 1000, 1)
        return out

    def _read(self, out):
        co, why = self.player()
        if not co:
            out["why"] = why
            return
        bs = self.behaviors(co)
        eq = next((b for n, b in bs.items() if n.endswith("WizEquipmentBehavior")), 0)
        inv = next((b for n, b in bs.items() if n.endswith("WizInventoryBehavior")), 0)
        notes = []
        # the wizard's pet energy (pinned only)
        if "energy" in self.pins or "energy_max" in self.pins:
            so = self.off("WizClientObject", "m_gameStats")
            gs = self.u64(co + so) if so is not None else 0
            if gs and self.tname(gs) == "WizGameStats":
                out["energy"] = self.pinned("energy", {"stats": gs})
                out["energy_max"] = self.pinned("energy_max", {"stats": gs})
            else:
                notes.append("the wizard's stats (WizGameStats) not found - no energy")
        nothing = (None, [], False, 0)
        esize, worn, ewhole, eodd = self.items(eq, "ClientEquipmentBehavior", EQUIPPED_CAP) if eq else nothing
        bsize, bag, bwhole, bodd = self.items(inv, "InventoryBehaviorBase", ITEMS_CAP) if inv else nothing
        if not eq or esize is None:
            notes.append("the worn items can't be read")
        elif not ewhole:
            notes.append("the worn items read in part (%d of %d%s)" % (
                len(worn), esize, (" - %d not an item" % eodd) if eodd else ""))
        if not inv or bsize is None:
            notes.append("the backpack can't be read")
        elif not bwhole:
            notes.append("the backpack read in part (%d of %d - %s)" % (
                len(bag), bsize, ("%d not an item, changing?" % bodd) if bodd else "changing, or over %d" % ITEMS_CAP))
        CO = self.P["CoreObject"]
        seen = set()
        # (an item whose global id reads 0 or whose behaviours can't all be read - and none seen a pet's - could be a
        # pet missed: counted, said, and whole False - QuickSell.ahk keeps every pet then. A gid seen again: the same
        # item, read already)
        unread = {"equipped": 0, "backpack": 0}
        for where, its in (("equipped", worn), ("backpack", bag)):
            for it in its:
                self.pace()
                gid = self.u64(it + CO["m_globalID.m_full"])
                if not gid:
                    unread[where] += 1
                    continue
                if gid in seen:
                    continue
                seen.add(gid)
                bs_it, sure = self.behaviors_sure(it)
                beh = next((b for n, b in bs_it.items() if n.endswith("PetItemBehavior")), 0)
                if beh:
                    out["pets"].append(self.pet(it, beh, gid, where))
                elif not sure:
                    unread[where] += 1
        for where, what in (("equipped", "worn"), ("backpack", "backpack")):
            if unread[where]:
                notes.append("%d %s item(s) whose id or behaviours couldn't be read - a pet may be missed" % (
                    unread[where], what))
        out["whole"] = bool(eq and inv and ewhole and bwhole) and not any(unread.values())
        bad = [p for p in out["pets"] if p["level"] is None]
        if bad:
            notes.append("%d pet(s) whose level can't be read" % len(bad))
        out["why"] = "; ".join(notes)

    def pet(self, it, beh, gid, where):
        """one pet's reading (read()'s pets entry)"""
        CO, BP = self.P["CoreObject"], self.P["BasePetItemBehavior"]
        tid = self.u32(it + CO["m_templateID.m_full"])
        p = {"gid": gid, "where": where, "template_id": tid, "behavior_class": self.tname(beh), "level": None,
             "level_name": None, "cards": None, "xp": None, "xp_next": None, "talents": None, "talent_ids": None,
             "derby": None, "derby_ids": None, "stats": None, "max_stats": None}
        p.update(self.item_info(tid))
        lv = self.u8(beh + BP["m_level"])
        p["level"] = lv if level_name(lv) else None
        p["level_name"] = level_name(lv)
        bt = self._typed_member("pet_tpl", beh, "PetItemBehaviorTemplate")
        PT, PL = self.P["PetItemBehaviorTemplate"], self.P["PetLevelInfo"]
        ents = None
        if bt and "m_Levels" in PT and "m_level" in PL:
            ents = level_entries(self, bt, PT["m_Levels"], PL["m_level"])
        if ents is not None and p["level"] is not None and all(k in PL for k in OPTIONAL["PetLevelInfo"]):
            p["cards"] = level_cards(self, ents, p["level"], PL)
        bases = {"pet": beh, "template": bt}
        p["xp"] = self.pinned("xp", bases)
        if ents is not None and p["level"] is not None:
            nxt = next((li for lv2, li in ents if lv2 == p["level"] + 1), 0)
            p["xp_next"] = self.pinned("level_xp", {"level": nxt}) if nxt else None
        for field in ("talents", "derby"):
            raw = self.pinned(field, bases)
            p["talent_ids" if field == "talents" else "derby_ids"] = raw
            p[field] = self.talent_names(raw)
        p["stats"] = self.pinned("stats", bases)
        p["max_stats"] = self.pinned("max_stats", bases)
        return p


# ============================================================================ command line
def _main(argv=None):
    import argparse
    ap = argparse.ArgumentParser(description="read-only: the wizard's pets (the worn one and the backpack's)")
    ap.add_argument("-n", type=int, default=1, help="readings (30 at most)")
    ap.add_argument("-i", type=float, default=2.0, help="seconds between them")
    ap.add_argument("--json", action="store_true")
    ap.add_argument("--pin", action="append", default=[], metavar="FIELD=Class.m_prop:KIND",
                    help="read a value not confirmed yet by this name for this run (fields: %s; kinds: %s)" % (
                        ", ".join(sorted(FIELDS)), ", ".join(KINDS)))
    ap.add_argument("--out", help="also write the readings to this file (to send back)")
    a = ap.parse_args(argv)
    pins = dict(PINS)
    for t in a.pin:
        got = parse_pin(t)
        if got is None:
            ap.error("--pin %r: FIELD=Class.m_prop:KIND (xp=BasePetItemBehavior.m_XP:u32)" % t)
        pins[got[0]] = got[1]
    good, bad = check_pins(pins)
    if bad:
        ap.error("--pin: " + "; ".join(bad))
    import navmem as N
    import handmem as H
    pids = N.find_pids()
    if not pids:
        sys.exit("the game is not running")
    fg = N.foreground_pid()
    st = N._Attached(fg if fg in pids else pids[0], lambda m: None)
    lines = ["# python petmem.py %s (%s) - build %s" % (" ".join(argv if argv is not None else sys.argv[1:]),
                                                       time.strftime("%Y-%m-%d %H:%M:%S"), st.m.build)]
    try:
        hm = H.HandMem(st, log=print)
        pm = PetMem(st, hm, log=print, pins=good)
        if pm.lack:
            lines.append("# not in this build: " + ", ".join(pm.lack))
        for k in range(max(1, min(a.n, 30))):
            r = pm.read()
            got = [time.strftime("%H:%M:%S")] + pet_lines(r)
            if a.json:
                got.append(json.dumps(r, default=str))
            print("\n".join(got))
            lines += got
            if k + 1 < a.n:
                time.sleep(max(0.2, min(a.i, 10.0)))
    finally:
        st.close()
    if a.out:
        with open(a.out, "w", encoding="utf-8") as fh:
            fh.write("\n".join(lines) + "\n")
        print("written: " + a.out)
    return 0


if __name__ == "__main__":
    sys.exit(_main())
