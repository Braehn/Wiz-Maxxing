"""deckmem - READ-ONLY reader of the wizard's DECKS (every deck item it owns: the equipped one and those in the backpack),
each deck's cards (main side, treasure-card side, the item cards it takes from the gear of its Equipment Set and those it
leaves out), its limits, which deck is equipped and in which Equipment Set each one is - plus the spellbook (the spells
the wizard knows) and the treasure-card book. The vision helper's (navmem.NavMem.deck / deck_sig - the battle recorder,
vision\\battlerec.py, and /deck), navmem / handmem / bagmem's way.

    dm = DeckMem(st, hm, log=print)   # st: navmem's attached game (navmem._Attached), hm: handmem.HandMem (template map,
                                      # names); about half a second once a game (the reflection lookup)
    r = dm.read()                     # {decks: [...], equipped: gid or None, why, ...} - never raises (see DeckMem.read)
    r = dm.read(kinds=False, only_equipped=True, pace=f)   # the recorder's: the worn deck only, no effects, f() called
                                      # between decks, between cards and every 500 names (navmem releases its lock there)
    sig = dm.signature()              # (worn items, the worn deck's gid, its card list's size, the set on, a checksum
                                      # of its cards) - ~2 ms
    print("\n".join(deck_lines(r)))   # one line a deck, one a card
    r = dm.read(books=True)           # the spellbook and the treasure book too (each spell's name, school, type, pips;
    print("\n".join(book_lines(r)))   # kinds=True: its kind and value as well) - one line a spell (/book)

    python deckmem.py [--json] [--book] [--hand] [-n 1] [-i 2]     readings from the command line

SAFETY. The game is opened by navmem.py's Proc - PROCESS_VM_READ | PROCESS_QUERY_INFORMATION (falling back to
PROCESS_VM_READ | PROCESS_QUERY_LIMITED_INFORMATION) and nothing else - and only read: ReadProcessMemory (plus the
toolhelp / module enumeration navmem uses to find the game). Nothing is ever written, allocated, injected, hooked,
suspended or debugged; no window is touched and no input is sent. Every class and property offset is found by NAME in a
copy of the game's code (its reflection registration: handmem.Image / questmem.class_props); every object is checked by
its type name before it's used. No memory scan: everything is followed from the wizard's own object (the camera's).

FAILS SOFT. read() never raises: whatever goes wrong comes back as why (a deck that can't be read: its own why, the others
still read). A value that can't be read for sure is None, never a guess. A deck's card list is read twice and kept only
when both reads agree (the game may be changing it: deck window open). The constructor raises LookupError when a needed
reflected class or property isn't in this build.

WHAT IS READ (build 6A9721E9-370E000, 2026-10-26 - every offset found by name each attach; the numbers are what they were):

  the wizard    the camera's object (navmem: GameClient -> ElasticCamController -> its ClientObject: a WizClientObject)
                  CoreObject.m_inactiveBehaviors +0xE0 (std::vector<SharedPointer<BehaviorInstance>>, 16 bytes each):
                  ClientWizEquipmentBehavior, ClientWizInventoryBehavior, ClientSpellbookBehavior,
                  ClientTreasureBookBehavior (by type name)
  equipped      ClientEquipmentBehavior.m_itemList +0x78 - std::list {head, size} of SharedPointer<WizClientObjectItem>
                  (node: next, prev, the item at +0x10): the items worn now - hat, robe, shoes, wand, athame, amulet, ring,
                  deck, mount... (m_slotList +0x88: EquippedSlotInfo, m_publicItemList +0x98: WizardEquippedItemInfo)
  backpack      InventoryBehaviorBase.m_itemList +0x70 of the ClientWizInventoryBehavior (bagmem's)
  sets          ClientWizEquipmentBehavior.m_equipmentSets +0xE8: std::list of EquipmentSet: m_serializedItems +0x60
                  (u16 n, n u64 global ids - the set's deck among them), m_isEquipped +0x80 (bagmem's)
  a deck        an item whose behaviors (CoreObject.m_inactiveBehaviors) hold a ClientDeckBehavior (: DeckBehavior):
                  DeckBehavior.m_spellList +0x78 - std::list of SharedPointer<SpellData>: SpellData.m_templateID +0x48,
                  m_enchantment +0x4C, m_quantity +0x50 (the copies) - main spells and treasure cards in one list;
                  m_serializedExclusionList +0x98 - a std::string of bytes: u16 n, then n x (u32 template id, u16 copies):
                  the ITEM CARDS left out of this deck (a deck can leave out its gear's / pet's cards - the unnamed list
                  at +0x88 holds the same, parsed); m_archmasterySchool +0xB8
                  the behavior's template (the first pointer in it typed DeckBehaviorTemplate - +0x58 now):
                  m_primarySchoolName +0x98, m_genericMaxRank +0xBC, m_schoolMaxRank +0xC0, m_genericMaxInstances +0xC4
                  (most copies of a spell of another school), m_schoolMaxInstances +0xC8 (of the deck's school),
                  m_maxSpells +0xCC (the main side's size), m_maxTreasureCards +0xD0, m_maxArchmasteryPoints +0xD4
                  (a float)
                the item's template (handmem's template map): GameObjectTemplate.m_objectName +0x60
                  ("Deck-Purchased-50-E01-Balance"), m_displayName +0xA8 (a name-table key)
  a card        its template (handmem's template map): SpellTemplate.m_name, m_displayName (-> Root.wad .lang),
                  m_sMagicSchoolName, m_sTypeName, m_Treasure +0x19D (a treasure card's template: "Monstrous TC"),
                  m_maxCopies +0x2D4, m_spellRank +0x310 -> SpellRank (m_spellRank +0x50 the pips, m_<school>Pips,
                  m_shadowPips, m_xPipSpell) - and handmem's effects / kind / value (finish) for its damage
                  side: "treasure" when its template says m_Treasure or the spellbook doesn't hold it; else "main"
  item cards    the gear of the deck's Equipment Set (the equipped items for the equipped deck): each item template's
                  ItemTemplate.m_equipEffects +0x128 (std::list of SharedPointer<GameEffectInfo>): ProvideSpellEffectInfo
                  m_spellName +0x68 (a SpellTemplate's m_name: "Wand-Balance-T4-001" = Minor Crusade), m_numSpells +0x88;
                  a pet (the worn item with a ClientPetItemBehavior : BasePetItemBehavior - "SwordShield" here):
                  BasePetItemBehavior.m_level +0x70 (u8: 7 Ultra), its template (the first pointer typed
                  PetItemBehaviorTemplate, +0x58 now) .m_Levels +0x130 - a std::list holding PetLevelInfo BY VALUE (the
                  object at node +0x10): m_level +0x48 (u8), m_powerCardCount +0x54, m_powerCardName +0x58 ("Pet -
                  Sharpened Blade"), m_powerCardName2 +0x78, m_powerCardName3 +0x98 - the entry of the pet's level;
                  the copies in the deck's exclusion list are taken off (by template id; a name -> id from the
                  exclusions, else the template map's SpellTemplate names walked once, about 0.9 s)
  spellbook     ClientSpellbookBehavior.m_spellIDList +0x80: std::list of SharedPointer<SpellIDTracker>:
                  m_spellID +0x48 (a template id), m_isRetired +0x4C, m_tieredSpellGroupIndex +0x50
  treasure book TreasureBookBehavior.m_spellList +0x78: std::list of SharedPointer<SpellData> (template id, copies)
"""
import json
import struct
import sys
import time
import zlib

import navmem as N
import petmem as PM

NEED = {"CoreObject": ("m_inactiveBehaviors", "m_globalID.m_full", "m_templateID.m_full"),
        "InventoryBehaviorBase": ("m_itemList",),
        "ClientEquipmentBehavior": ("m_itemList",),
        "DeckBehavior": ("m_spellList",),
        "SpellData": ("m_templateID", "m_quantity"),
        "GameObjectTemplate": ("m_objectName",)}
# (read when found: without them that part's left out - None)
OPTIONAL = {"ClientWizEquipmentBehavior": ("m_equipmentSets",),
            "EquipmentSet": ("m_serializedItems", "m_isEquipped"),
            "DeckBehavior": ("m_serializedExclusionList", "m_archmasterySchool"),
            "DeckBehaviorTemplate": ("m_primarySchoolName", "m_genericMaxRank", "m_schoolMaxRank",
                                     "m_genericMaxInstances", "m_schoolMaxInstances", "m_maxSpells",
                                     "m_maxTreasureCards", "m_maxArchmasteryPoints"),
            "SpellData": ("m_enchantment",),
            "ClientSpellbookBehavior": ("m_spellIDList",),
            "SpellIDTracker": ("m_spellID", "m_isRetired", "m_tieredSpellGroupIndex"),
            "TreasureBookBehavior": ("m_spellList",),
            "ItemTemplate": ("m_equipEffects",),
            "ProvideSpellEffectInfo": ("m_spellName", "m_numSpells"),
            "GameObjectTemplate": ("m_displayName",),
            "BasePetItemBehavior": ("m_level",),
            "PetItemBehaviorTemplate": ("m_Levels",),
            "PetLevelInfo": ("m_level", "m_powerCardCount", "m_powerCardName", "m_powerCardName2", "m_powerCardName3"),
            "SpellTemplate": ("m_name", "m_displayName", "m_sMagicSchoolName", "m_sTypeName", "m_Treasure",
                              "m_maxCopies", "m_spellRank"),
            "SpellRank": ("m_spellRank", "m_shadowPips", "m_xPipSpell") + tuple("m_%sPips" % s for s in
                                                                                 ("balance", "death", "fire", "ice",
                                                                                  "life", "myth", "storm"))}
CLASSES = tuple(sorted(set(NEED) | set(OPTIONAL)))
SCHOOL_PIPS = ("balance", "death", "fire", "ice", "life", "myth", "storm")
ITEMS_CAP = 400          # backpack items walked at most
EQUIPPED_CAP = 64        # equipped items at most
SETS_CAP = 20
SET_IDS_CAP = 64
CARDS_CAP = 200          # distinct spells in a deck at most (a deck holds 60 + 25 cards)
EXCL_CAP = 64
BOOK_CAP = 3000          # spellbook / treasure book entries at most
BOOK_KEYS = ("name", "display", "school", "type", "pips", "x_pips")   # what a book entry gets from its template (brief)
EFFECTS_CAP = 50
NAME_WALK_S = 3.0        # s of reading at most a read for the template map's names (an item card that isn't left out,
                         # once a game): the paced waits off navmem's lock not counted; a walk stopped goes on next read


# ============================================================================ pure helpers
def parse_set_ids(data):
    """the global ids in an EquipmentSet's m_serializedItems bytes (u16 n, then n u64s) - None when they don't add up"""
    if data is None:
        return None
    if len(data) < 2:
        return [] if not data else None
    n = struct.unpack_from("<H", data, 0)[0]
    if n > SET_IDS_CAP or 2 + 8 * n > len(data):
        return None
    return [struct.unpack_from("<Q", data, 2 + 8 * i)[0] for i in range(n)]


def parse_exclusions(data):
    """[(template id, copies)] of a DeckBehavior's m_serializedExclusionList bytes (u16 n, then n x (u32, u16)) - None when
    they don't add up ([] an empty one)"""
    if data is None:
        return None
    if len(data) < 2:
        return [] if not data else None
    n = struct.unpack_from("<H", data, 0)[0]
    if n > EXCL_CAP or 2 + 6 * n > len(data):
        return None
    return [struct.unpack_from("<IH", data, 2 + 6 * i) for i in range(n)]


def side_of(tc_flag, known):
    """a deck card's side: 'treasure' (its template is a treasure card's, or the spellbook doesn't hold it), 'main' (a
    spell the wizard knows), None not told (neither read)"""
    if tc_flag:
        return "treasure"
    if known is False:
        return "treasure"
    if known is True:
        return "main"
    return None if tc_flag is None else "main"


def _f(v):
    return "" if v is None else str(v).replace("|", "/").replace("\r", " ").replace("\n", " ")


# ============================================================================ the reader
class DeckMem:
    """the wizard's decks - see the top. Not thread-safe: call it under navmem's lock (as handmem / bagmem)"""

    def __init__(self, st, hm, log=None, props=None):
        """props: {class: {property: offset}} - tests only (no code copy read)"""
        self.log = log or (lambda msg: None)
        t0 = time.perf_counter()
        self.st, self.p, self.hm, self.build = st, st.p, hm, st.m.build
        if props is None:
            import handmem as H
            import questmem as Q
            img = H.Image(st)
            props = {c: {k: v[0] for k, v in Q.class_props(img, c)[0].items()} for c in CLASSES}
            del img
        self.P = {c: dict(props.get(c, {})) for c in CLASSES}
        missing = [c + "." + k for c, ks in NEED.items() for k in ks if k not in self.P[c]]
        if missing:
            raise LookupError("reflected properties not found in this build (%s): %s" % (self.build, ", ".join(missing)))
        self.lack = [c + "." + k for c, ks in OPTIONAL.items() for k in ks if k not in self.P[c]]
        self.o = {}              # places found by type (checked at every read): the deck behavior's template
        self.brief_cache = {}    # template id -> brief (templates don't change while the game runs)
        self.card_cache = {}     # template id -> card info (handmem's kind / value)
        self.by_name = None      # SpellTemplate m_name -> template id (walked once, when wanted; set when walked WHOLE)
        self._walk = None        # (the names' walk not done: {head, out, stack, n, k, s, reads} - it goes on next time)
        self._walk_left = NAME_WALK_S   # (s of walking left in this read)
        self._pace = None        # (read's pace: called between decks, between cards and every 500 names)
        self._paced = 0.0        # (s spent in pace calls - off navmem's lock: not reading)
        self._k = 0              # (reads since the read began - _tick)
        self.pet_unread = []     # (the pets whose cards _item_cards couldn't read - its last call's)
        self.attach_s = time.perf_counter() - t0
        self.log("deckmem: ready in %.2f s%s" % (self.attach_s, (" - not in this build: " + ", ".join(self.lack))
                                                 if self.lack else ""))

    # ------------------------------------------------------------------ small readers
    def pace(self):
        """read's pace (navmem releases its lock there when it has held it long enough) - raises to stop the read"""
        if self._pace is not None:
            self._paced_call()

    def _paced_call(self):
        t = time.monotonic()
        try:
            self._pace()
        finally:
            self._paced += time.monotonic() - t

    def _tick(self):
        """every 4th read while a read is paced: its pace (a clock check - it lets go only after 12 ms held): no stretch
        of a read holds navmem's lock long, whatever the code between the explicit pace points"""
        if self._pace is not None:
            self._k += 1
            if not self._k & 3:
                self._paced_call()

    def _rd(self, a, n):
        self._tick()
        return self.p.try_read(a, n)

    def off(self, cls, prop):
        return self.P.get(cls, {}).get(prop)

    def u64(self, a):
        b = self._rd(a, 8) if N.ptr_ok(a) else None
        return struct.unpack("<Q", b)[0] if b else 0

    def u32(self, a):
        b = self._rd(a, 4) if N.ptr_ok(a) else None
        return struct.unpack("<I", b)[0] if b else None

    def i32(self, a):
        b = self._rd(a, 4) if N.ptr_ok(a) else None
        return struct.unpack("<i", b)[0] if b else None

    def f32(self, a):
        b = self._rd(a, 4) if N.ptr_ok(a) else None
        return round(struct.unpack("<f", b)[0], 3) if b else None

    def u8(self, a):
        b = self._rd(a, 1) if N.ptr_ok(a) else None
        return b[0] if b else None

    def flag(self, a):
        v = self.u8(a)
        return None if v not in (0, 1) else bool(v)

    def tname(self, obj):
        if not N.ptr_ok(obj):
            return None
        self._tick()
        return self.st.tn.of(obj)

    def string(self, a):
        if not N.ptr_ok(a):
            return None
        self._tick()
        return self.p.try_string(a)

    def raw_string(self, a, limit=0x1000):
        """an MSVC x64 std::string's bytes (16-byte inline buffer or a pointer, size @+0x10, capacity @+0x18), or None"""
        raw = self._rd(a, 0x20) if N.ptr_ok(a) else None
        if not raw:
            return None
        size, cap = struct.unpack_from("<QQ", raw, 0x10)
        if size > limit or cap < size or cap > 0x100000:
            return None
        if cap < 16:
            return raw[:size]
        return self._rd(struct.unpack_from("<Q", raw)[0], size) if size else b""

    def slist(self, a, cap):
        """(its size, [the pointer at each node's +0x10]) of an MSVC std::list<SharedPointer<T>> at a ({head, size}; node:
        next, prev, value) - walked to cap nodes at most; (None, []) unreadable. A list cut short (it changed while read)
        gives fewer than its size: callers check"""
        b = self._rd(a, 16) if N.ptr_ok(a) else None
        if not b:
            return None, []
        head, size = struct.unpack("<QQ", b)
        if not N.ptr_ok(head) or size > 1000000:
            return None, []
        out, n = [], self.u64(head)
        while N.ptr_ok(n) and n != head and len(out) < min(size, cap):
            out.append(self.u64(n + 0x10))
            n = self.u64(n)
            if len(out) % 4 == 0:
                self.pace()
        return size, out

    def vec16(self, a, limit=256):
        b = self._rd(a, 16) if N.ptr_ok(a) else None
        if not b:
            return []
        x, y = struct.unpack("<QQ", b)
        if not (N.ptr_ok(x) and x <= y <= x + 16 * limit and (y - x) % 16 == 0):
            return []
        raw = self._rd(x, y - x) or b""
        return [v for v in (struct.unpack_from("<Q", raw, i)[0] for i in range(0, len(raw) - 7, 16)) if N.ptr_ok(v)]

    # ------------------------------------------------------------------ the wizard
    def player(self):
        """(the wizard's WizClientObject - the camera's object, "") or (0, why) - bagmem's way"""
        st = self.st
        try:
            gc = st.gameclient()
        except N.ReadError as e:
            return 0, "no GameClient (%s)" % e
        if not N.ptr_ok(gc):
            return 0, "no GameClient yet (not in the game world)"
        try:
            pl, why = st.player(gc)
        except N.ReadError as e:
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
        for k, b in enumerate(self.vec16(obj + self.P["CoreObject"]["m_inactiveBehaviors"])):
            if k % 4 == 3:
                self.pace()
            tn = self.tname(b)
            if tn and tn not in out:
                out[tn] = b
        return out

    # ------------------------------------------------------------------ templates
    def template(self, tid):
        return self.hm.template(tid) if tid else 0

    def item_info(self, tid):
        """{object_name, display_key, display, school} of an item template"""
        self.pace()
        t = self.template(tid)
        if not t:
            return {"object_name": None, "display_key": None, "display": None}
        key = None
        if self.off("GameObjectTemplate", "m_displayName") is not None:
            key = self.string(t + self.P["GameObjectTemplate"]["m_displayName"])
        disp = None
        try:
            disp = self.hm.lang_text(key) if key else None
        except Exception:  # noqa: BLE001
            disp = None
        return {"object_name": self.string(t + self.P["GameObjectTemplate"]["m_objectName"]), "display_key": key,
                "display": disp}

    def brief(self, tid):
        """{template_id, name, display, school, type, tc_flag, max_copies, pips, x_pips, shadow_pips, school_pips,
        template_class} of a spell template - no effects (kept: templates don't change)"""
        hit = self.brief_cache.get(tid)
        if hit is not None:
            return hit
        self.pace()
        r = {"template_id": tid, "name": None, "display": None, "school": None, "type": None, "tc_flag": None,
             "max_copies": None, "pips": None, "x_pips": None, "shadow_pips": None, "school_pips": None,
             "template_class": None}
        t = self.template(tid)
        if not t:
            return r
        r["template_class"] = self.tname(t)
        ST = self.P["SpellTemplate"]
        g = lambda k: ST.get(k)   # noqa: E731
        if g("m_name") is not None:
            r["name"] = self.string(t + ST["m_name"])
        if g("m_displayName") is not None:
            key = self.string(t + ST["m_displayName"])
            try:
                r["display"] = self.hm.lang_text(key) if key else None
            except Exception:  # noqa: BLE001
                r["display"] = None
        if g("m_sMagicSchoolName") is not None:
            r["school"] = self.string(t + ST["m_sMagicSchoolName"])
        if g("m_sTypeName") is not None:
            r["type"] = self.string(t + ST["m_sTypeName"])
        if g("m_Treasure") is not None:
            r["tc_flag"] = self.flag(t + ST["m_Treasure"])
        if g("m_maxCopies") is not None:
            r["max_copies"] = self.i32(t + ST["m_maxCopies"])
        SR = self.P["SpellRank"]
        if g("m_spellRank") is not None and all(k in SR for k in OPTIONAL["SpellRank"]):
            rank = self.u64(t + ST["m_spellRank"])
            if N.ptr_ok(rank) and self.tname(rank) == "SpellRank":
                lo = SR["m_spellRank"]
                hi = max(SR[k] for k in OPTIONAL["SpellRank"]) + 1
                rr = self._rd(rank + lo, hi - lo)
                if rr:
                    r["pips"] = rr[0]
                    r["x_pips"] = bool(rr[SR["m_xPipSpell"] - lo])
                    r["shadow_pips"] = rr[SR["m_shadowPips"] - lo]
                    r["school_pips"] = {s: rr[SR["m_%sPips" % s] - lo] for s in SCHOOL_PIPS if rr[SR["m_%sPips" % s] - lo]}
        if r["name"] is not None:
            if len(self.brief_cache) > 6000:
                self.brief_cache.clear()
            self.brief_cache[tid] = r
        return r

    def card(self, tid):
        """brief(tid) plus handmem's kind, value, value_text, heads_text, boosts_text, text (its effects' reading -
        finish), kept"""
        hit = self.card_cache.get(tid)
        if hit is not None:
            return dict(hit)
        c = dict(self.brief(tid))
        # (the hand's reader made without the effect names - this build's enum not read, handmem's cards_why: no kind,
        # rather than one guessed from effect numbers; the brief - name, school, type, pips - still read)
        cwhy = getattr(self.hm, "cards_why", "")
        try:
            import handmem as H
            info = self.hm.tpl_info(tid) if not cwhy else None
            if cwhy:
                c["kind_why"] = cwhy
            if info:
                c.update({k: v for k, v in info.items() if k not in ("display",) or c.get("display") is None})
                c["treasure"] = bool(c.get("tc_flag"))
                c["item_card"] = False
                H.finish(c, want_effects=False)
        except Exception as e:  # noqa: BLE001 - the brief then
            c["kind_why"] = "its effects couldn't be read (%r)" % (e,)
        c.pop("effects", None)
        c.pop("ench_effects", None)
        if c.get("name") is not None:
            if len(self.card_cache) > 3000:
                self.card_cache.clear()
            self.card_cache[tid] = c
        return dict(c)

    def tid_by_name(self, name):
        """the template id of the SpellTemplate whose m_name is name - the template map walked once and kept; None not
        found, or not reached yet (by_name still None: the walk not done - NAME_WALK_S of reading at most a read, the
        paced waits not counted; a walk stopped there or by the read's pace raising goes on where it was next time)"""
        if self.by_name is None:
            self._walk_names()
        if self.by_name is not None:
            return self.by_name.get(name)
        return self._walk["out"].get(name) if self._walk else None

    def _walk_names(self):
        w = self._walk
        if w is None:
            head = self.hm.tm
            if not head or self.P["SpellTemplate"].get("m_name") is None:
                self.by_name = {}
                return
            # (in-order walk of the std::map: node +0 left, +8 parent, +0x10 right, +0x19 isnil, +0x20 key, +0x28 the
            # template - each step kept whole or not at all, so a pace that raises leaves the walk where it was)
            root = self.u64(head + 8)
            w = self._walk = {"head": head, "out": {}, "stack": [], "n": root, "k": 0, "s": 0.0, "reads": 0}
        if self._walk_left <= 0:
            return
        head, out, stack, m_name = w["head"], w["out"], w["stack"], self.P["SpellTemplate"]["m_name"]
        t0, p0 = time.monotonic(), self._paced
        w["reads"] += 1
        done = False
        try:
            while w["k"] < 200000 and time.monotonic() - t0 - (self._paced - p0) < self._walk_left:
                n = w["n"]
                if N.ptr_ok(n) and n != head and self.u8(n + 0x19) == 0:
                    left = self.u64(n)
                    stack.append(n)
                    w["n"] = left
                    continue
                if not stack:
                    done = True
                    break
                top = stack[-1]
                if (w["k"] + 1) % 500 == 0:
                    self.pace()
                t = self.u64(top + 0x28)
                if (self.tname(t) or "").endswith("SpellTemplate"):
                    nm = self.string(t + m_name)
                    if nm and nm not in out:
                        out[nm] = self.u32(top + 0x20)
                right = self.u64(top + 0x10)
                stack.pop()
                w["n"] = right
                w["k"] += 1
        finally:
            spent = time.monotonic() - t0 - (self._paced - p0)
            w["s"] += spent
            self._walk_left -= spent
        if done or w["k"] >= 200000:
            self.by_name, self._walk = out, None
            self.log("deckmem: %d spell template names read in %.2f s%s%s" % (
                len(out), w["s"], (" (in %d reads)" % w["reads"]) if w["reads"] > 1 else "",
                "" if done else " - cut at %d entries" % w["k"]))
        else:
            self.log("deckmem: the spell template names' walk stopped at %d names (%.2f s of reading) - it goes on at "
                     "the next read" % (len(out), w["s"]))

    # ------------------------------------------------------------------ items
    def items(self, beh, prop_cls, cap):
        """(size, [WizClientObjectItem]) of an inventory / equipment behavior's m_itemList; (None, []) unreadable"""
        size, its = self.slist(beh + self.P[prop_cls]["m_itemList"], cap)
        return size, [i for i in its if (self.tname(i) or "").endswith("ClientObjectItem")]

    def item_cards_of(self, it, tpl):
        """[(spell m_name, copies, how)] the cards an item gives: its template's equip effects (ProvideSpellEffectInfo -
        gear) and, for a pet, its level's power cards (PetLevelInfo); None unreadable. A pet whose cards can't be read
        (its classes not in this build, its level or template unreadable) loses only ITS cards: the item's equip effects
        are kept and the item goes on self.pet_unread (_read's why says so) - before v1.0.0 the whole deck's item cards
        went None with it"""
        if not tpl or self.off("ItemTemplate", "m_equipEffects") is None or \
                any(self.off("ProvideSpellEffectInfo", k) is None for k in ("m_spellName", "m_numSpells")):
            return None
        a = tpl + self.P["ItemTemplate"]["m_equipEffects"]
        size, effs = self.slist(a, EFFECTS_CAP)
        if size is None or len(effs) != size:
            return None
        out = []
        for e in effs:
            if self.tname(e) == "ProvideSpellEffectInfo":
                out.append((self.string(e + self.P["ProvideSpellEffectInfo"]["m_spellName"]),
                            self.i32(e + self.P["ProvideSpellEffectInfo"]["m_numSpells"]), "equip effect"))
        pet = self.pet_cards(it)
        if pet is None:
            self.pet_unread.append(it)
            return out
        return out + pet

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
            if N.ptr_ok(v) and self.tname(v) == tname:
                self.o[key] = i
                return v
        return 0

    def pet_cards(self, it):
        """[(spell m_name, copies, 'pet level N')] of a pet item at its level (BasePetItemBehavior.m_level -> its
        PetItemBehaviorTemplate.m_Levels: a std::list of PetLevelInfo held in the nodes (+0x10) - m_powerCardName(2, 3),
        m_powerCardCount - each name taken that many times: whether the count is for each name isn't known, only one name
        was seen); [] not a pet; None a pet that can't be read. The list's walk is petmem's (level_entries /
        level_cards - the pets reader's too)"""
        beh = next((b for n, b in self.behaviors(it).items() if n.endswith("PetItemBehavior")), 0)
        if not beh:
            return []
        BP, PT, PL = self.P["BasePetItemBehavior"], self.P["PetItemBehaviorTemplate"], self.P["PetLevelInfo"]
        if "m_level" not in BP or "m_Levels" not in PT or any(k not in PL for k in OPTIONAL["PetLevelInfo"]):
            return None
        level = self.u8(beh + BP["m_level"])
        bt = self._typed_member("pet_tpl", beh, "PetItemBehaviorTemplate")
        if level is None or not bt:
            return None
        ents = PM.level_entries(self, bt, PT["m_Levels"], PL["m_level"])
        if ents is None:
            return None
        return PM.level_cards(self, ents, level, PL)

    def deck_template(self, beh):
        """the DeckBehaviorTemplate of a deck behavior: the first pointer in it of that type (the place kept, checked by
        type every time)"""
        return self._typed_member("deck_tpl", beh, "DeckBehaviorTemplate")

    def deck_list(self, beh):
        """[(template id, copies, enchantment)] of a deck behavior's m_spellList, or (None, why) - read twice, kept when
        both reads agree"""
        SD = self.P["SpellData"]
        a = beh + self.P["DeckBehavior"]["m_spellList"]
        reads = []
        for _ in range(2):
            size, sds = self.slist(a, CARDS_CAP)
            if size is None:
                return None, "its card list can't be read"
            if size > CARDS_CAP:
                return None, "its card list says %d spells (more than %d)" % (size, CARDS_CAP)
            if len(sds) != size:
                return None, "its card list broke off after %d of %d (changing?)" % (len(sds), size)
            got = []
            for sd in sds:
                self.pace()
                if self.tname(sd) != "SpellData":
                    return None, "an entry of its card list isn't a SpellData (%s)" % (self.tname(sd) or "unreadable")
                tid, q = self.u32(sd + SD["m_templateID"]), self.i32(sd + SD["m_quantity"])
                ench = self.u32(sd + SD["m_enchantment"]) if "m_enchantment" in SD else None
                if tid is None or q is None:
                    return None, "an entry of its card list can't be read"
                got.append((tid, q, ench))
            reads.append(got)
        if reads[0] != reads[1]:
            return None, "its card list changed while it was read (the deck window open?)"
        return reads[0], ""

    # ------------------------------------------------------------------ the books
    def spellbook(self, sb):
        """[{template_id, retired, tier_group}] of the spellbook, or None"""
        o, T = self.off("ClientSpellbookBehavior", "m_spellIDList"), self.P["SpellIDTracker"]
        if not sb or o is None or "m_spellID" not in T:
            return None
        size, trs = self.slist(sb + o, BOOK_CAP)
        if size is None or len(trs) != size:
            return None
        out = []
        for k, t in enumerate(trs):
            self.pace()
            if self.tname(t) != "SpellIDTracker":
                return None
            out.append({"template_id": self.u32(t + T["m_spellID"]),
                        "retired": self.flag(t + T["m_isRetired"]) if "m_isRetired" in T else None,
                        "tier_group": self.i32(t + T["m_tieredSpellGroupIndex"]) if "m_tieredSpellGroupIndex" in T else None})
        return out

    def treasure_book(self, tb):
        """[{template_id, count}] of the treasure-card book, or None"""
        o, SD = self.off("TreasureBookBehavior", "m_spellList"), self.P["SpellData"]
        if not tb or o is None:
            return None
        size, sds = self.slist(tb + o, BOOK_CAP)
        if size is None or len(sds) != size:
            return None
        out = []
        for k, sd in enumerate(sds):
            self.pace()
            if self.tname(sd) != "SpellData":
                return None
            out.append({"template_id": self.u32(sd + SD["m_templateID"]), "count": self.i32(sd + SD["m_quantity"])})
        return out

    # ------------------------------------------------------------------ the read
    def read(self, books=False, kinds=True, only_equipped=False, pace=None):
        """{decks, equipped, equipped_set, why, ms, sets, spellbook_n, treasure_book_n, player_gid[, spellbook,
        treasure_book]} - never raises. only_equipped: the backpack's decks left out (the battle recorder's); pace: a
        callable invoked between decks, between cards and every 500 names (navmem releases its lock there; it raises to
        stop the read - why says so).
          books     the spellbook [{template_id, retired, tier_group, name, display, school, type, pips, x_pips}] and
                    the treasure book [{template_id, count, the same}] (None: not read) - with kinds each entry's kind
                    and value_text too (handmem's reading of its effects, as a deck card's: slower the first time)
          player_gid  the wizard's own global id (CoreObject.m_globalID of the camera's object - bagmem's player gid:
                    whose spellbook it is), None not read
          decks     [{gid, where ('equipped' / 'backpack'), equipped, sets [n...], template_id, object_name, display,
                    school, limits {max_spells, max_treasure, generic_max_copies, school_max_copies, generic_max_rank,
                    school_max_rank, max_archmastery}, cards [{template_id, name, display, school, type, pips, x_pips,
                    shadow_pips, school_pips, count, enchantment_id, side ('main' / 'treasure'), known, tc_flag,
                    max_copies, kind, value, value_text, heads_text, boosts_text}], main_n, treasure_n, excluded
                    [{template_id, count, name, display}], item_cards [{name, template_id, count, display, from}] (the
                    gear's cards the deck takes - its set's gear; excluded left out), item_n, ok, why}]
          equipped  the equipped deck's global id (it's in the worn items - ClientEquipmentBehavior.m_itemList), None
          equipped_set  the Equipment Set (1...) whose m_isEquipped is on, None
          why       '' or what couldn't be read (and how the equipped deck is known)
          names_cut True when an item card's template id is None because the spell names aren't all read yet (that
                    deck's why says so; read again later - the walk goes on)"""
        t0 = time.perf_counter()
        out = {"decks": [], "equipped": None, "equipped_set": None, "why": "", "ms": 0.0, "sets": [],
               "spellbook_n": None, "treasure_book_n": None, "player_gid": None}
        self._walk_left = NAME_WALK_S
        self._pace = pace
        # (kinds asked for, the hand's reader made without the effect names - handmem's cards_why: not read at all, why
        # says so - a reading whose cards have no kinds would teach the deck profiles (battlesim.learn_decks) no hits,
        # heals or blades; kinds=False - the recorder's worn deck, /book - still reads)
        cwhy = getattr(self.hm, "cards_why", "") if kinds else ""
        try:
            if cwhy:
                out["why"] = cwhy
            else:
                self._read(out, books, kinds, only_equipped)
        except Exception as e:  # noqa: BLE001 - never into the caller
            out["why"] = "the decks couldn't be read (%r)" % (e,)
        finally:
            self._pace = None
        out["ms"] = round((time.perf_counter() - t0) * 1000, 1)
        return out

    def signature(self, pace=None):
        """(worn items, the worn deck's global id, its card list's size, the Equipment Set on, a checksum of its card
        list) - the worn list only (16 items at most, about 2 ms): it changes when another deck is put on, the deck's
        cards are changed (a copy more of a card too - the checksum: each SpellData's template id, enchantment and
        copies, one read each) or another set is worn. None when it can't be read. pace: as read's"""
        old = self._pace
        if pace is not None:
            self._pace = pace
        try:
            return self._signature()
        finally:
            self._pace = old

    def _signature(self):
        co, _why = self.player()
        if not co:
            return None
        bs = self.behaviors(co)
        eq = next((b for n, b in bs.items() if n.endswith("WizEquipmentBehavior")), 0)
        if not eq:
            return None
        esize, worn = self.items(eq, "ClientEquipmentBehavior", 16)
        if esize is None:
            return None
        CO = self.P["CoreObject"]
        gid = size = crc = None
        for it in worn:
            beh = next((b for n, b in self.behaviors(it).items() if n.endswith("DeckBehavior")), 0)
            if beh:
                gid = self.u64(it + CO["m_globalID.m_full"])
                SD = self.P["SpellData"]
                size, sds = self.slist(beh + self.P["DeckBehavior"]["m_spellList"], CARDS_CAP)
                if size is not None and len(sds) == size:
                    lo, hi = min(SD.values()), max(SD.values()) + 4
                    h = 0
                    for sd in sds:
                        raw = self._rd(sd, hi) if N.ptr_ok(sd) else None
                        h = zlib.crc32(raw[lo:hi] if raw else b"?", h)
                    crc = h
                break
        set_n = None
        so, ES = self.off("ClientWizEquipmentBehavior", "m_equipmentSets"), self.P["EquipmentSet"]
        if so is not None and "m_isEquipped" in ES:
            _ssize, ess = self.slist(eq + so, SETS_CAP)
            on = [i for i, es in enumerate(ess, 1) if self.tname(es) == "EquipmentSet" and
                  self.flag(es + ES["m_isEquipped"])]
            set_n = on[0] if len(on) == 1 else None
        return (esize, gid, size, set_n, crc)

    def _read(self, out, books, kinds, only_equipped=False):
        co, why = self.player()
        if not co:
            out["why"] = why
            return
        # (whose books these are: the wizard's own global id - a per-character record's key, /book's books| line)
        out["player_gid"] = self.u64(co + self.P["CoreObject"]["m_globalID.m_full"]) or None
        bs = self.behaviors(co)
        eq = next((b for n, b in bs.items() if n.endswith("WizEquipmentBehavior")), 0)
        inv = next((b for n, b in bs.items() if n.endswith("WizInventoryBehavior")), 0)
        sb = bs.get("ClientSpellbookBehavior", 0)
        tb = bs.get("ClientTreasureBookBehavior", 0)
        if not eq:
            out["why"] = "no equipment on the wizard (its equipment behavior wasn't found)"
            return
        notes = []
        # the books (a deck card the spellbook doesn't hold is a treasure card)
        book = self.spellbook(sb)
        known = {e["template_id"] for e in book} if book is not None else None
        tbook = self.treasure_book(tb)
        out["spellbook_n"] = len(book) if book is not None else None
        out["treasure_book_n"] = len(tbook) if tbook is not None else None
        if books:
            # (each entry's name, school, type and pips from its template - brief, kept: templates don't change; kinds:
            # its kind and value too - card, handmem's reading of its effects, as a deck card's)
            look, keys = (self.card, BOOK_KEYS + ("kind", "value_text")) if kinds else (self.brief, BOOK_KEYS)

            def entry(e):
                b = look(e["template_id"]) if e.get("template_id") is not None else {}
                return dict(e, **{k: b.get(k) for k in keys})
            out["spellbook"] = [entry(e) for e in book] if book is not None else None
            out["treasure_book"] = [entry(e) for e in tbook] if tbook is not None else None
        if book is None:
            notes.append("the spellbook can't be read (a card's side then by its template only)")
        # the Equipment Sets
        sets, set_ok = [], False
        so, ES = self.off("ClientWizEquipmentBehavior", "m_equipmentSets"), self.P["EquipmentSet"]
        if so is not None and all(k in ES for k in ("m_serializedItems", "m_isEquipped")):
            ssize, ess = self.slist(eq + so, SETS_CAP)
            set_ok = ssize is not None and len(ess) == ssize
            for i, es in enumerate(ess, 1):
                self.pace()
                if self.tname(es) != "EquipmentSet":
                    set_ok = False
                    continue
                ids = parse_set_ids(self.raw_string(es + ES["m_serializedItems"]))
                sets.append({"n": i, "equipped": self.flag(es + ES["m_isEquipped"]), "ids": ids})
                if ids is None:
                    set_ok = False
        out["sets"] = sets
        on = [s["n"] for s in sets if s["equipped"]]
        out["equipped_set"] = on[0] if len(on) == 1 else None
        # the items: worn ones, then the backpack's
        esize, worn = self.items(eq, "ClientEquipmentBehavior", EQUIPPED_CAP)
        if esize is None:
            out["why"] = "the worn items can't be read"
            return
        if only_equipped:
            bsize, bag = 0, []
        else:
            bsize, bag = self.items(inv, "InventoryBehaviorBase", ITEMS_CAP) if inv else (None, [])
        if bsize is None:
            notes.append("the backpack can't be read (only the equipped deck)")
        CO = self.P["CoreObject"]
        objs = {}                                   # gid -> (item, where, template id)
        for where, its in (("equipped", worn), ("backpack", bag)):
            for k, it in enumerate(its):
                self.pace()
                gid = self.u64(it + CO["m_globalID.m_full"])
                if gid and gid not in objs:
                    objs[gid] = (it, where, self.u32(it + CO["m_templateID.m_full"]))
        worn_gids = [g for g, v in objs.items() if v[1] == "equipped"]
        for gid, (it, where, tid) in objs.items():
            beh = next((b for n, b in self.behaviors(it).items() if n.endswith("DeckBehavior")), 0)
            if not beh:
                continue
            self.pace()
            d = {"gid": gid, "where": where, "equipped": where == "equipped",
                 "sets": [s["n"] for s in sets if s["ids"] and gid in s["ids"]], "template_id": tid}
            d.update(self.item_info(tid))
            d.update(self._deck(beh, known, kinds))
            # the item cards it takes: its set's gear (the worn items for the worn deck), its exclusions left out
            if d["equipped"]:
                gear = [g for g in worn_gids if g != gid]
                d["gear_from"] = "worn items"
            elif d["sets"]:
                s = next(s for s in sets if s["n"] == d["sets"][0])
                gear = [g for g in s["ids"] if g != gid]
                d["gear_from"] = "Equipment Set %d" % s["n"]
            else:
                gear, d["gear_from"] = None, "in no Equipment Set: its gear isn't known"
            d["item_cards"], d["item_n"] = self._item_cards(gear, objs, d.get("excluded"))
            if self.pet_unread and d["item_cards"] is not None:
                d["why"] = "; ".join(x for x in (d.get("why"), "the pet's cards couldn't be read (its level or template "
                                                 "- BasePetItemBehavior / PetLevelInfo) - the gear's are there") if x)
            if self.by_name is None and any(c.get("template_id") is None for c in d["item_cards"] or []):
                out["names_cut"] = True
                d["why"] = "; ".join(x for x in (d.get("why"), "an item card's template isn't known yet (the spell "
                                                 "names not all read - read again later)") if x)
            out["decks"].append(d)
        eqd = [d for d in out["decks"] if d["equipped"]]
        if len(eqd) == 1:
            out["equipped"] = eqd[0]["gid"]
            sn = out["equipped_set"]
            if sn is not None and eqd[0]["sets"] and sn in eqd[0]["sets"]:
                notes.append("equipped: the deck worn (ClientEquipmentBehavior.m_itemList), in Equipment Set %d, the set on"
                             % sn)
            elif sn is not None:
                notes.append("equipped: the deck worn (ClientEquipmentBehavior.m_itemList) - NOT in Equipment Set %d (the "
                             "set on): a deck put on by hand since?" % sn)
            else:
                notes.append("equipped: the deck worn (ClientEquipmentBehavior.m_itemList); no set reads as on")
        elif not eqd:
            notes.append("no deck worn")
        else:
            notes.append("%d decks read as worn - none taken" % len(eqd))
        if not set_ok and sets:
            notes.append("an Equipment Set couldn't be read whole")
        out["why"] = "; ".join(notes)

    def _deck(self, beh, known, kinds):
        r = {"behavior_class": self.tname(beh), "cards": [], "main_n": None, "treasure_n": None, "excluded": None,
             "limits": None, "school": None, "ok": False, "why": ""}
        bt = self.deck_template(beh)
        DT = self.P["DeckBehaviorTemplate"]
        if bt:
            g = lambda k, rd: rd(bt + DT[k]) if k in DT else None   # noqa: E731
            r["school"] = g("m_primarySchoolName", self.string)
            r["limits"] = {"max_spells": g("m_maxSpells", self.i32), "max_treasure": g("m_maxTreasureCards", self.i32),
                           "generic_max_copies": g("m_genericMaxInstances", self.i32),
                           "school_max_copies": g("m_schoolMaxInstances", self.i32),
                           "generic_max_rank": g("m_genericMaxRank", self.i32),
                           "school_max_rank": g("m_schoolMaxRank", self.i32),
                           "max_archmastery": g("m_maxArchmasteryPoints", self.f32)}
        DB = self.P["DeckBehavior"]
        if "m_serializedExclusionList" in DB:
            ex = parse_exclusions(self.raw_string(beh + DB["m_serializedExclusionList"]))
            if ex is not None:
                r["excluded"] = []
                for tid, q in ex:
                    b = self.brief(tid)
                    r["excluded"].append({"template_id": tid, "count": q, "name": b["name"], "display": b["display"]})
        lst, why = self.deck_list(beh)
        if lst is None:
            r["why"] = why
            return r
        main = tc = 0
        for tid, q, ench in lst:
            self.pace()
            c = self.card(tid) if kinds else dict(self.brief(tid))
            kn = (tid in known) if known is not None else None
            c.update(count=q, enchantment_id=ench or 0, known=kn, side=side_of(c.get("tc_flag"), kn))
            if c["side"] == "main":
                main += q
            elif c["side"] == "treasure":
                tc += q
            r["cards"].append(c)
        r["main_n"], r["treasure_n"] = main, tc
        r["ok"] = all(c.get("name") for c in r["cards"]) and all(c.get("side") for c in r["cards"])
        if not r["ok"]:
            r["why"] = "a card's template or side couldn't be read"
        return r

    def _item_cards(self, gear, objs, excluded):
        """([{name, template_id, count, display, from}], their count) of the gear gids' item cards, excluded left out;
        (None, None) not known"""
        if gear is None:
            return None, None
        ex = {}
        for e in excluded or []:
            ex[e["template_id"]] = ex.get(e["template_id"], 0) + (e["count"] or 0)
        ex_names = {e["name"]: e["template_id"] for e in excluded or [] if e.get("name")}
        out, n = [], 0
        self.pet_unread = []
        for g in gear:
            if g not in objs:
                continue                      # (a set's item no longer owned)
            self.pace()
            it, _, tid = objs[g]
            t = self.template(tid)
            got = self.item_cards_of(it, t)
            if got is None:
                return None, None
            src0 = self.string(t + self.P["GameObjectTemplate"]["m_objectName"]) if t else None
            for nm, q, how in got:
                src = "%s (%s)" % (src0, how)
                if not nm or not q:
                    continue
                stid = ex_names.get(nm)
                if stid is None:
                    stid = self.tid_by_name(nm)
                left = q
                if stid is not None and ex.get(stid):
                    cut = min(ex[stid], left)
                    ex[stid] -= cut
                    left -= cut
                if left <= 0:
                    continue
                b = self.brief(stid) if stid else {}
                out.append({"name": nm, "template_id": stid, "count": left, "display": b.get("display"), "from": src})
                n += left
        return out, n


# ============================================================================ answers
def deck_lines(r):
    """deck|gid hex|where|equipped|sets|object name|display|school|main n|treasure n|item n|max spells|max treasure|
    generic max copies|school max copies|ok|why
    card|gid hex|side|count|template id|name|display|school|type|pips|xpip|kind|value|known|tc flag
    item|gid hex|count|template id|name|display|from
    excl|gid hex|count|template id|name|display
    decks|n|equipped gid hex|equipped set|spellbook n|treasure book n|ms|why"""
    out = []
    for d in r.get("decks") or []:
        L = d.get("limits") or {}
        out.append("|".join(["deck", "%x" % d["gid"], d["where"], "1" if d["equipped"] else "0",
                             ",".join(str(s) for s in d.get("sets") or []), _f(d.get("object_name")), _f(d.get("display")),
                             _f(d.get("school")), _f(d.get("main_n")), _f(d.get("treasure_n")), _f(d.get("item_n")),
                             _f(L.get("max_spells")), _f(L.get("max_treasure")), _f(L.get("generic_max_copies")),
                             _f(L.get("school_max_copies")), "1" if d.get("ok") else "0", _f(d.get("why"))]))
        for c in d.get("cards") or []:
            out.append("|".join(["card", "%x" % d["gid"], _f(c.get("side")), _f(c.get("count")), _f(c.get("template_id")),
                                 _f(c.get("name")), _f(c.get("display")), _f(c.get("school")), _f(c.get("type")),
                                 _f(c.get("pips")), "1" if c.get("x_pips") else "0", _f(c.get("kind")),
                                 _f(c.get("value_text")), _f(c.get("known")), _f(c.get("tc_flag"))]))
        for c in d.get("item_cards") or []:
            out.append("|".join(["item", "%x" % d["gid"], _f(c.get("count")), _f(c.get("template_id")), _f(c.get("name")),
                                 _f(c.get("display")), _f(c.get("from"))]))
        for c in d.get("excluded") or []:
            out.append("|".join(["excl", "%x" % d["gid"], _f(c.get("count")), _f(c.get("template_id")), _f(c.get("name")),
                                 _f(c.get("display"))]))
    out.append("|".join(["decks", str(len(r.get("decks") or [])), "%x" % r["equipped"] if r.get("equipped") else "",
                         _f(r.get("equipped_set")), _f(r.get("spellbook_n")), _f(r.get("treasure_book_n")),
                         _f(r.get("ms")), _f(r.get("why"))]))
    return out


def book_lines(r):
    """the books of a read(books=True) - /book's answer, one line a spell, in the game's own order:
    book|template id|name|display|school|type|pips|x pip (1/0)|retired (1/0)|tier group|kind|value
    tcbook|template id|count|name|display|school|type|pips|kind|value
    books|spellbook n|treasure book n|wizard gid hex|ms|why
    (a field not read: empty; kind and value only in a read with kinds). none|why when the books weren't read at all -
    a read without books, or the wizard not found"""
    if "spellbook" not in r:
        return ["none|" + _f(r.get("why") or "the books weren't read (read(books=True))")]
    out = []
    flag = lambda v: "" if v is None else ("1" if v else "0")   # noqa: E731
    for e in r.get("spellbook") or []:
        out.append("|".join(["book", _f(e.get("template_id")), _f(e.get("name")), _f(e.get("display")), _f(e.get("school")),
                             _f(e.get("type")), _f(e.get("pips")), flag(e.get("x_pips")), flag(e.get("retired")),
                             _f(e.get("tier_group")), _f(e.get("kind")), _f(e.get("value_text"))]))
    for e in r.get("treasure_book") or []:
        out.append("|".join(["tcbook", _f(e.get("template_id")), _f(e.get("count")), _f(e.get("name")),
                             _f(e.get("display")), _f(e.get("school")), _f(e.get("type")), _f(e.get("pips")),
                             _f(e.get("kind")), _f(e.get("value_text"))]))
    notes = [r["why"]] if r.get("why") else []
    if r.get("treasure_book") is None:
        notes.insert(0, "the treasure book couldn't be read")
    if r.get("spellbook") is None:
        notes.insert(0, "the spellbook couldn't be read")
    gid = r.get("player_gid")
    out.append("|".join(["books", _f(len(r["spellbook"]) if r.get("spellbook") is not None else None),
                         _f(len(r["treasure_book"]) if r.get("treasure_book") is not None else None),
                         "%x" % gid if gid else "", _f(r.get("ms")), _f("; ".join(notes))]))
    return out


def hand_check(r, hand):
    """(ok, [lines]) - every settled hand card (the pet's left out) in the EQUIPPED deck: a plain card on its main side, a
    treasure card on its treasure side, an item card among its item cards (by template id; an item card by name too).
    ok None when there's no settled hand or no equipped deck to check against"""
    if not hand or not hand.get("settled") or not hand.get("cards"):
        return None, ["hand: none to check (%s)" % ((hand or {}).get("why") or "no hand")]
    d = next((d for d in r.get("decks") or [] if d["equipped"]), None)
    if d is None:
        return None, ["hand: no equipped deck read"]
    main = {c["template_id"] for c in d["cards"] if c.get("side") == "main"}
    tcs = {c["template_id"] for c in d["cards"] if c.get("side") == "treasure"}
    items = {c.get("template_id") for c in d.get("item_cards") or []} | {c.get("name") for c in d.get("item_cards") or []}
    lines, ok = [], True
    for c in hand["cards"]:
        if c.get("slot") == "PetCard":
            lines.append("hand: %s (pet card) - not checked" % c.get("display"))
            continue
        tid = c.get("template_id")
        if c.get("item_card"):
            good = tid in items or c.get("name") in items
            where = "item cards"
        elif c.get("treasure"):
            good = tid in tcs
            where = "treasure side"
        else:
            good = tid in main
            where = "main side"
        ok = ok and good
        lines.append("hand: %-22s tid %-10s tc %d item %d -> %s the equipped deck's %s" % (
            c.get("display") or c.get("name"), tid, bool(c.get("treasure")), bool(c.get("item_card")),
            "IN" if good else "NOT IN", where))
    return ok, lines


# ============================================================================ command line
def _main():
    import argparse
    ap = argparse.ArgumentParser(description="read-only: the wizard's decks and their cards")
    ap.add_argument("-n", type=int, default=1)
    ap.add_argument("-i", type=float, default=2.0)
    ap.add_argument("--json", action="store_true")
    ap.add_argument("--book", action="store_true", help="the spellbook and the treasure book too")
    ap.add_argument("--hand", action="store_true", help="check the battle hand against the equipped deck")
    ap.add_argument("--nokinds", action="store_true", help="no effects / kinds (faster)")
    a = ap.parse_args()
    pids = N.find_pids()
    if not pids:
        sys.exit("the game is not running")
    fg = N.foreground_pid()
    st = N._Attached(fg if fg in pids else pids[0], lambda m: None)
    import handmem as H
    hm = H.HandMem(st, log=print)
    dm = DeckMem(st, hm, log=print)
    for k in range(max(1, min(a.n, 30))):
        r = dm.read(books=a.book, kinds=not a.nokinds)
        print(time.strftime("%H:%M:%S"))
        print("\n".join(deck_lines(r)))
        if a.book:
            print("\n".join(book_lines(r)))
        if a.json:
            print(json.dumps(r, default=str))
        if a.hand:
            hand = hm.read(want_effects=False)
            ok, lines = hand_check(r, hand)
            print("\n".join(lines))
            print("hand check: %s (hand state %s)" % ({True: "PASS", False: "FAIL", None: "nothing to check"}[ok],
                                                       hand.get("state")))
        if k + 1 < a.n:
            time.sleep(max(0.2, min(a.i, 10.0)))
    st.close()


if __name__ == "__main__":
    _main()
