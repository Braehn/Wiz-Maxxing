"""bagmem - READ-ONLY reader of the wizard's BACKPACK (how many items, how many it holds, the gold and the gold pouch, the
Equipment Sets and which of their items are in the backpack, each item's kind from its template's adjectives), the HUD's
right-side TIP icons (Prospector Zeke's portrait: "your backpack is full" - or "your gold bag is nearly full"), and the
GAME'S WINDOWS by name (shown, where in GUI units, checked / greyed, their text or label, the message box that's up) - for
quick selling the backpack when it's full (AutoFarmer's QuickSell.ahk: every click target from here, nothing guessed off
the screen). navmem.py makes one per game (in a thread, like the hand's, the quest's and the mobs' readers) for the vision
helper's /bag and /gui - and its /guitree: EVERY window under one, one a line (tree: the discovery tool for the windows
nobody has looked at yet - a battle's Pass / Flee buttons, a trainer's spell list, a pet's window - and the rows of a list).

    bm = BagMem(st, log=print)            # st: navmem's attached game (navmem._Attached); about half a second, once a game
    r, why = bm.bag(hm)                   # hm: handmem.HandMem (the GUI's root, the template map)
    g, why = bm.gui(hm, ["buyWindow/AllAction", "QuickSellConfirmationWindow/SellButton"])
    lines = bag_lines(*navmem.NavMem().bag())          # the helper's /bag answer
    lines = gui_lines(*navmem.NavMem().gui(paths), paths)
    t, why = bm.tree(hm, "CombatPlanningPhaseWindow", shown_only=True)   # every window under one (discovery)
    lines = tree_lines(*nav_tree(navmem.NavMem(), "Anc/Name"))         # the helper's /guitree answer

    python bagmem.py [--gui Anc/Name,...]              readings from the command line
    python bagmem.py --tree [--under Anc/Name] [--all] [--depth N] [--indent] [--out tree.txt]
                                                       every shown window (--all: hidden too), one a line - the names
                                                       of a window's buttons, lists and a box's keys, to send back

SAFETY. The game is opened by navmem.py's Proc - PROCESS_VM_READ | PROCESS_QUERY_INFORMATION (falling back to
PROCESS_VM_READ | PROCESS_QUERY_LIMITED_INFORMATION) and nothing else - and only read: ReadProcessMemory, plus
VirtualQueryEx / QueryWorkingSetEx and the module / toolhelp enumeration navmem.py uses. Nothing is ever written,
allocated, injected, hooked, suspended or debugged; no window is touched and no input is sent - this only says where the
game's windows are; AutoFarmer decides what to click. Every class and property offset is found by NAME in a copy of the
game's code (its reflection registration: handmem.Image / questmem.class_props); every object is checked by its type name
before it's used.

FAILS SOFT. bag() and gui() never raise: (None, why) when it can't be read; a value that can't be read for sure is None,
never a guess. The constructor raises LookupError when a needed reflected class or property isn't in this build (navmem
answers (None, why) then, and tries again after a while).

WHAT IS READ (build 6A9721E9-370E000, 2026-10-25 - every offset found by name each attach; the numbers are what they were):

  the wizard   the camera's object (navmem's gc_elastic_cam / cam_attached_object: a WizClientObject)
                 CoreObject.m_globalID.m_full +0x48 (the character's id - quicksell.ini's section), m_inactiveBehaviors +0xE0
                 (std::vector<SharedPointer<BehaviorInstance>>, 16 bytes each)
                 WizClientObject.m_gameStats +0x230 -> WizGameStats: m_currentGold +0x74, m_baseGoldPouch +0x58,
                 m_extraInventorySpace +0x398
  backpack     ClientWizInventoryBehavior: m_numItemsAllowed +0xA0 (150); InventoryBehaviorBase.m_itemList +0x70 - an MSVC
                 std::list {head, size} of SharedPointer<WizClientObjectItem> (node: next, prev, the item at +0x10)
                 each item: CoreObject.m_globalID.m_full, m_templateID.m_full -> handmem's template map -> the
                 WizItemTemplate: GameObjectTemplate.m_objectName +0x60 ("Deck-Purchased-50-E01-Balance"),
                 m_adjectiveList +0xF8 (std::list<std::string>: "Deck", "FLAG_NoTrade"... - its kind: Hat, Robe, Shoes,
                 Weapon, Athame, Amulet, Ring, Deck, Pet, Mount, Jewel, Emote, Elixir...; FLAG_CrownsOnly a Crowns item -
                 so is a Crown-shop template, "Crown-S05-Robe-093" or "Crowns-S67-Robe-L50-DS-010-01", which may have
                 no such flag live; FLAG_NoSell one that can't be sold). The 22 emotes and teleport effects are items
                 too - the game's own N/M on the backpack page may leave them out (m_numCEEmotesAllowed): the bot
                 calibrates by it
  sets         ClientWizEquipmentBehavior.m_equipmentSets +0xE8: std::list {head, size} of EquipmentSet (node +0x10):
                 m_serializedItems +0x60 (a std::string of bytes: u16 n, then n u64 global ids), m_isEquipped +0x80
                 (m_equipmentSetName +0x58 is 8 bytes - not a string: not read). sets_ok only when every set and its
                 items were read and every backpack item walked - QuickSell.ahk sells nothing without it
  windows      the GUI's root (handmem.root(): the window whose children hold the HUD); Window: m_sName +0x50,
                 m_Children +0x70 (16-byte SharedPointers), m_Flags +0x9C (bit 0 VISIBLE), m_Window +0xA0 (l, t, r, b -
                 relative to its parent and already laid out: a window's place in the root = its ancestors' lefts / tops
                 added to its own; the root is the game's client area in GUI units, 1827x1027 at 2560x1440)
                 ControlText.m_sText +0x2C8 (a std::wstring); ControlButton.m_sLabel +0x2E0, m_bGreyed +0x328, m_pButton
                 +0x308; ControlCheckBox.m_bChecked +0x40C; ControlSprite.m_pMaterial +0x2D0 -> Material.m_pDiffuseMap
                 +0x78 -> Texture.m_sFilename +0x68. A text that's still the .gui file's "<string;KEY>" is given as its
                 key and its words from Root.wad's name tables (handmem.lang_text) - outside navmem's lock
  tips         windowHUD -> TipWindow [TipFrame] (the right-hand column: 1807,128-1827,799 in the root): its children
                 (TipWindowButton 75x75: image [ControlSprite] - Zeke's portrait GUI/NpcPortraits/
                 Portrait_Human_Zeke_A_NPC.dds - and button [ControlButton])
  N/M          InventorySpellbookPage/inventorySpace [ControlText] ("150/150"), while the backpack page is shown
"""
import os
import re
import struct
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.insert(0, HERE)
import navmem as N                   # noqa: E402

NEED = {"Window": ("m_sName", "m_Children", "m_Flags", "m_Window"),
        "ControlText": ("m_sText",),
        "ControlButton": ("m_sLabel", "m_bGreyed"),
        "ControlCheckBox": ("m_bChecked",),
        "CoreObject": ("m_inactiveBehaviors", "m_globalID.m_full", "m_templateID.m_full"),
        "WizClientObject": ("m_gameStats",),
        "WizGameStats": ("m_currentGold", "m_baseGoldPouch"),
        "InventoryBehaviorBase": ("m_itemList",),
        "ClientWizInventoryBehavior": ("m_numItemsAllowed",)}
# (read when found: without them that part's left out - no textures, no sets, no kinds)
OPTIONAL = {"ControlSprite": ("m_pMaterial",), "Material": ("m_pDiffuseMap",), "Texture": ("m_sFilename",),
            "ClientWizEquipmentBehavior": ("m_equipmentSets",),
            "EquipmentSet": ("m_serializedItems", "m_isEquipped"),
            "GameObjectTemplate": ("m_objectName", "m_adjectiveList")}
CLASSES = tuple(sorted(set(NEED) | set(OPTIONAL)))
ITEMS_CAP = 400          # backpack items walked at most (150 slots + emotes; the list's own size is always given)
SETS_CAP = 20            # Equipment Sets read at most
SET_IDS_CAP = 64         # global ids in one set at most
WIN_CAP = 30000          # windows walked at most
DEPTH = 14               # how deep under the root
PATHS_CAP = 40           # /gui window paths at most
# tree(): how deep it walks - under the root finding the window asked for, then under that one (deeper than gui()'s: a
# list's rows sit low) unless a depth is asked; windows left deeper: capped
TREE_DEPTH = 24
TREE_ROWS = 6000         # tree(): windows listed at most (each one described: its type, text, texture - more reads)
# an item's kind from its template's adjectives, the first of these it has (the Quick Sell window's categories first)
KINDS = (("Deck", "deck"), ("Hat", "hat"), ("Robe", "robe"), ("Shoes", "shoes"), ("Weapon", "weapon"),
         ("Athame", "athame"), ("Amulet", "amulet"), ("Ring", "ring"), ("Pet", "pet"), ("Mount", "mount"),
         ("Jewel", "jewel"), ("Emote", "emote"), ("Elixir", "elixir"), ("TreasureCard", "treasurecard"),
         ("Reagent", "reagent"), ("Housing", "housing"), ("Structure", "housing"))
GEAR = ("hat", "robe", "shoes", "weapon", "athame", "amulet", "ring", "deck")
BOX_PARTS = ("TitleText", "CaptionText", "centerButton", "leftButton", "rightButton")
TOKEN = re.compile(r"<string;([A-Za-z0-9_]+)>")
PATH_RE = re.compile(r"^[A-Za-z0-9_]+(?:/[A-Za-z0-9_]+)*$")
ZEKE = "Portrait_Human_Zeke"


# ============================================================================ pure helpers
def cell(v):
    """a field of a /bag or /gui line: no | or line breaks in it; None as empty; a flag as 1/0"""
    if v is None:
        return ''
    if isinstance(v, bool):
        return '1' if v else '0'
    return re.sub(r'[|\r\n]+', ' ', str(v)).strip()


def strip_markup(s):
    """<center>150/150</center> -> 150/150 (questmem's), white space made single"""
    return re.sub(r"\s+", " ", re.sub(r"<[^>]*>", "", s or "")).strip()


def clean_text(raw, lang=None):
    """(the words, key) of a window's raw text: each "<string;KEY>" the .gui file left in it given its words from the name
    tables (lang(KEY) -> text or None; "{KEY}" when not found), the markup taken out; key: KEY when the raw text is one
    such token and nothing else, else "". (None, "") for None"""
    if raw is None:
        return None, ""
    m = TOKEN.fullmatch(raw.strip())
    key = m.group(1) if m else ""

    def sub(mm):
        t = None
        if lang is not None:
            try:
                t = lang(mm.group(1))
            except Exception:  # noqa: BLE001 - the key then
                t = None
        return t if t is not None else "{" + mm.group(1) + "}"
    return strip_markup(TOKEN.sub(sub, raw)), key


def item_kind(adjs):
    """an item's kind ("deck", "hat"... - KINDS) from its template's adjectives; another adjective lower-cased when none of
    those; "" none; None not read"""
    if adjs is None:
        return None
    have = set(adjs)
    for adj, kind in KINDS:
        if adj in have:
            return kind
    for a in adjs:
        if a and not a.endswith(".AdjRef") and not a.startswith("FLAG_"):
            return a.lower()
    return ""


def parse_set_ids(data):
    """the global ids in an EquipmentSet's m_serializedItems bytes (u16 n, then n u64s) - None when they don't add up (an
    empty set: [])"""
    if data is None:
        return None
    if len(data) < 2:
        return [] if not data else None
    n = struct.unpack_from("<H", data, 0)[0]
    if n > SET_IDS_CAP or 2 + 8 * n > len(data):
        return None
    return [struct.unpack_from("<Q", data, 2 + 8 * i)[0] for i in range(n)]


def parse_space(text):
    """(N, M) of the backpack page's "150/150" (markup and spaces allowed), else None"""
    m = re.search(r"(\d{1,4})\s*/\s*(\d{1,4})", strip_markup(text or ""))
    return (int(m.group(1)), int(m.group(2))) if m else None


def gui_paths(s):
    """the window paths of a /gui ask ("Anc/Name,Name,..."): a list, or None when one isn't letters, digits and _ split
    by /, or there are more than PATHS_CAP"""
    paths = [p.strip() for p in (s or "").split(",") if p.strip()]
    if len(paths) > PATHS_CAP or any(not PATH_RE.match(p) for p in paths):
        return None
    return paths


def tree_under(s):
    """the window path of a /guitree ask (under=Anc/Name - one path, gui_paths' letters, digits and _ split by /): "" for
    none (the GUI root), None when it isn't one"""
    s = (s or "").strip()
    if not s:
        return ""
    return s if PATH_RE.match(s) else None


def anc_match(anc, chain):
    """the names anc are all among chain's (its ancestors' names, the root first), in that order"""
    i = 0
    for nm in chain:
        if i < len(anc) and nm == anc[i]:
            i += 1
    return i == len(anc)


def zeke_up(tips):
    """a shown tip whose portrait (or button) is Prospector Zeke's"""
    return any(t.get("shown") and ZEKE.lower() in ((t.get("image") or "") + " " + (t.get("button") or "")).lower()
               for t in tips or [])


def subtree(found, top, shown_only=True, depth=None, cap=TREE_ROWS):
    """([(f, its depth below top, its parent's row number - 1 the first row, 0 for top)], capped) of walk()'s list found:
    top (one of its windows) and every window under it (top's address among its ancestors'), in found's order - depth
    first, an ancestor before its windows; shown_only: only the shown ones (a hidden window's windows are hidden too: no
    row loses its parent); depth: that many levels below top at most; cap rows at most (capped True when one more was
    left out)"""
    tw, base = top["w"], len(top["chain"])
    rows, at, capped = [], {}, False
    for f in found:
        if f is not top and tw not in f["chain_w"]:
            continue
        d = len(f["chain"]) - base
        if (depth is not None and d > depth) or (shown_only and not f["shown"]):
            continue
        if len(rows) >= cap:
            capped = True
            break
        rows.append((f, d, 0 if f is top else at.get(f["chain_w"][-1], 0)))
        at[f["w"]] = len(rows)
    return rows, capped


# ============================================================================ the reader
class BagMem:
    """the backpack, the tips and the game's windows - see the top. Not thread-safe: call it under navmem's lock (as
    handmem / questmem / bossmem)"""

    def __init__(self, st, log=None, props=None):
        """props: {class: {property: offset}} - tests only (no code copy read)"""
        self.log = log or (lambda msg: None)
        t0 = time.perf_counter()
        self.st, self.p, self.build = st, st.p, st.m.build
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
        W = self.P["Window"]
        offs = [(W["m_sName"], 0x20), (W["m_Children"], 16), (W["m_Flags"], 4), (W["m_Window"], 16)]
        self._wlo = min(o for o, _ in offs)
        self._whi = max(o + n for o, n in offs)
        self.tpl = {}                # template id -> (object name, adjectives) - templates don't change while it runs
        self.attach_s = time.perf_counter() - t0
        self.log("bagmem: ready in %.2f s%s" % (self.attach_s, (" - not in this build: " + ", ".join(self.lack))
                                                if self.lack else ""))

    # ------------------------------------------------------------------ small readers
    def off(self, cls, prop):
        return self.P.get(cls, {}).get(prop)

    def u64(self, a):
        b = self.p.try_read(a, 8) if N.ptr_ok(a) else None
        return struct.unpack("<Q", b)[0] if b else 0

    def u32(self, a):
        b = self.p.try_read(a, 4) if N.ptr_ok(a) else None
        return struct.unpack("<I", b)[0] if b else None

    def i32(self, a):
        b = self.p.try_read(a, 4) if N.ptr_ok(a) else None
        return struct.unpack("<i", b)[0] if b else None

    def u8(self, a):
        b = self.p.try_read(a, 1) if N.ptr_ok(a) else None
        return b[0] if b else None

    def flag(self, a):
        """a bool member: True / False, None when it's neither 0 nor 1 (not one)"""
        v = self.u8(a)
        return None if v not in (0, 1) else bool(v)

    def tname(self, obj):
        return self.st.tn.of(obj) if N.ptr_ok(obj) else None

    def string(self, a):
        return self.p.try_string(a) if N.ptr_ok(a) else None

    def raw_string(self, a, limit=0x1000):
        """an MSVC x64 std::string's bytes as they are (16-byte inline buffer or a pointer, size @+0x10, capacity
        @+0x18), or None"""
        raw = self.p.try_read(a, 0x20) if N.ptr_ok(a) else None
        if not raw:
            return None
        size, cap = struct.unpack_from("<QQ", raw, 0x10)
        if size > limit or cap < size or cap > 0x100000:
            return None
        if cap < 16:
            return raw[:size]
        return self.p.try_read(struct.unpack_from("<Q", raw)[0], size) if size else b""

    def wstr(self, a):
        """an MSVC x64 std::wstring (8-wchar inline buffer or a pointer, size @+0x10, capacity @+0x18), or None"""
        raw = self.p.try_read(a, 0x20) if N.ptr_ok(a) else None
        if not raw:
            return None
        size, cap = struct.unpack_from("<QQ", raw, 0x10)
        if size > 0x2000 or cap < size or cap > 0x100000:
            return None
        if cap < 8:
            data = raw[:size * 2]
        else:
            data = self.p.try_read(struct.unpack_from("<Q", raw)[0], size * 2) if size else b""
        try:
            return data.decode("utf-16-le") if data is not None else None
        except UnicodeDecodeError:
            return None

    def text(self, a):
        """a text member: as a std::wstring (the GUI's); one that reads as CJK there is an 8-bit std::string - read as one"""
        s = self.wstr(a)
        if s is not None and all(ord(ch) < 0x2E80 for ch in s):
            return s
        s2 = self.string(a)
        return s2 if s2 is not None else None

    def slist(self, a, cap):
        """(its size, [the pointer at each node's +0x10]) of an MSVC std::list<SharedPointer<T>> at a ({head, size}; node:
        next, prev, value) - walked to cap nodes at most; (None, []) unreadable"""
        b = self.p.try_read(a, 16) if N.ptr_ok(a) else None
        if not b:
            return None, []
        head, size = struct.unpack("<QQ", b)
        if not N.ptr_ok(head) or size > 1000000:
            return None, []
        out, n = [], self.u64(head)
        while N.ptr_ok(n) and n != head and len(out) < min(size, cap):
            out.append(self.u64(n + 0x10))
            n = self.u64(n)
        return size, out

    def str_list(self, a, cap=40):
        """the strings of an MSVC std::list<std::string> at a (node: next, prev, the string at +0x10), [] none - None
        unreadable, longer than cap, or not read whole (a node or a string that can't be read: a list read in part could
        leave out the adjective that says an item's kind)"""
        b = self.p.try_read(a, 16) if N.ptr_ok(a) else None
        if not b:
            return None
        head, size = struct.unpack("<QQ", b)
        if not N.ptr_ok(head) or size > cap:
            return None
        out, n = [], self.u64(head)
        while N.ptr_ok(n) and n != head and len(out) < size:
            s = self.string(n + 0x10)
            if s is None:
                return None
            out.append(s)
            n = self.u64(n)
        return out if len(out) == size else None

    def vec16(self, a, limit=256):
        """the objects of a std::vector<SharedPointer<T>> at a (begin, end: 16-byte elements)"""
        b = self.p.try_read(a, 16) if N.ptr_ok(a) else None
        if not b:
            return []
        x, y = struct.unpack("<QQ", b)
        if not (N.ptr_ok(x) and x <= y <= x + 16 * limit and (y - x) % 16 == 0):
            return []
        raw = self.p.try_read(x, y - x) or b""
        return [v for v in (struct.unpack_from("<Q", raw, i)[0] for i in range(0, len(raw) - 7, 16)) if N.ptr_ok(v)]

    # ------------------------------------------------------------------ windows
    def winfo(self, w):
        """(name, [children], flags, (l, t, r, b)) of window w - its members in one read; None unreadable"""
        if not N.ptr_ok(w):
            return None
        raw = self.p.try_read(w + self._wlo, self._whi - self._wlo)
        if not raw:
            return None
        W, lo = self.P["Window"], self._wlo
        o = W["m_sName"] - lo
        size, cap = struct.unpack_from("<QQ", raw, o + 0x10)
        name = None
        if size <= 0x200 and cap >= size:
            data = raw[o:o + size] if cap < 16 else (self.p.try_read(struct.unpack_from("<Q", raw, o)[0], size)
                                                     if size else b"")
            if data is not None:
                s = data.decode("latin-1")
                name = s if all(32 <= ord(ch) < 127 for ch in s) else None
        o = W["m_Children"] - lo
        x, y = struct.unpack_from("<QQ", raw, o)
        kids = []
        if N.ptr_ok(x) and x <= y <= x + 0x8000 and (y - x) % 16 == 0 and y > x:
            vr = self.p.try_read(x, y - x) or b""
            kids = [v for v in (struct.unpack_from("<Q", vr, i)[0] for i in range(0, len(vr) - 7, 16)) if N.ptr_ok(v)]
        flags = struct.unpack_from("<I", raw, W["m_Flags"] - lo)[0]
        rect = struct.unpack_from("<4i", raw, W["m_Window"] - lo)
        return name, kids, flags, rect

    def walk(self, root, want, depth=DEPTH, cap=WIN_CAP):
        """([{w, name, chain (ancestors' names, the root first), chain_w (their addresses), shown (VISIBLE on it and every
        ancestor), rect (in the root: its ancestors' lefts / tops added), prect (its parent's, None for the root), kids,
        flags (its m_Flags as read), up (every ancestor shown)}] of the windows under root - root too - whose name is in
        want (want None: every window - tree()'s), depth first in the game's order (an ancestor always before its
        windows); windows walked)"""
        found, n, _deep = self._walk(root, want, depth, cap)
        return found, n

    def _walk(self, root, want, depth=DEPTH, cap=WIN_CAP, start=None, prune=False):
        """(walk()'s list, windows walked, deep - how many of them had windows the depth limit left out: tree()'s capped).
        start: root's (chain, chain_w, up, its parent's left and top in the GUI root, prect) - tree()'s walk under a
        window a first walk found, its rows' chains, shown and rects as from the GUI root (None: root is the GUI root);
        prune: a hidden window's windows not walked (tree()'s shown rows: they're hidden too - often most of the GUI,
        every closed window's)"""
        found, n, deep, seen = [], 0, 0, set()
        stack = [(root, 0) + (tuple(start) if start else ((), (), True, 0, 0, None))]
        while stack and n < cap:
            w, d, chain, chain_w, up, ox, oy, prect = stack.pop()
            if w in seen:
                continue
            seen.add(w)
            info = self.winfo(w)
            if info is None:
                continue
            n += 1
            name, kids, flags, (l, t, r, b) = info
            shown = up and bool(flags & 1)
            rect = (ox + l, oy + t, ox + r, oy + b)
            if want is None or name in want:
                found.append({"w": w, "name": name, "chain": chain, "chain_w": chain_w, "shown": shown, "rect": rect,
                              "prect": prect, "kids": kids, "flags": flags, "up": up})
            if prune and not shown:
                continue
            if d < depth:
                for k in reversed(kids):
                    stack.append((k, d + 1, chain + (name,), chain_w + (w,), shown, rect[0], rect[1], rect))
            elif kids:
                deep += 1
        return found, n, deep

    def is_text(self, tn):
        return bool(tn) and tn.endswith("Text")

    def is_button(self, tn):
        return bool(tn) and (tn.endswith("Button") or tn.endswith("CheckBox"))

    def is_check(self, tn):
        return bool(tn) and tn.endswith("CheckBox")

    def root_of(self, hm, names):
        """the GUI's root for windows named names: hm.root() - but when a LoginWindow is among the names, the login
        screen's first (hm.login_root - the root with a LoginWindow in it; looked for further only when root() has none,
        no windowHUD): the login box's fields, where AutoFarmer's Reconnect.ahk clicks to log in (its OCR'd labels put
        the Account field 12 px too low at 1920x1080, 2026-11-13) - also after a disconnect, should the GUI manager still
        hold a windowHUD then. Never the text typed in them: a ControlEdit's isn't read (describe). 0 none"""
        root = hm.root()
        if "LoginWindow" in names and hasattr(hm, "login_root"):
            login = hm.login_root(scan=not root)
            if login:
                return login
        return root

    def describe(self, f):
        """{type, shown, rect, prect, checked, greyed, raw} of a found window f (walk's)"""
        w = f["w"]
        tn = self.tname(w)
        raw = None
        if self.is_text(tn):
            raw = self.text(w + self.P["ControlText"]["m_sText"])
        elif self.is_button(tn) or (tn and "InventoryItem" in tn):
            raw = self.text(w + self.P["ControlButton"]["m_sLabel"])
        return {"type": tn or "", "shown": f["shown"], "rect": f["rect"], "prect": f["prect"],
                "checked": self.flag(w + self.P["ControlCheckBox"]["m_bChecked"]) if self.is_check(tn) else None,
                "greyed": self.flag(w + self.P["ControlButton"]["m_bGreyed"]) if self.is_button(tn) else None,
                "raw": raw}

    def texture(self, w):
        """the file name of a sprite's or a button's texture (m_pMaterial / m_pButton -> m_pDiffuseMap ->
        m_sFilename), or None"""
        tn = self.tname(w)
        mat = 0
        if tn == "ControlSprite" and self.off("ControlSprite", "m_pMaterial") is not None:
            mat = self.u64(w + self.P["ControlSprite"]["m_pMaterial"])
        elif self.is_button(tn) and self.off("ControlButton", "m_pButton") is not None:
            mat = self.u64(w + self.P["ControlButton"]["m_pButton"])
        if not mat or self.off("Material", "m_pDiffuseMap") is None or self.off("Texture", "m_sFilename") is None:
            return None
        dm = self.u64(mat + self.P["Material"]["m_pDiffuseMap"])
        return self.string(dm + self.P["Texture"]["m_sFilename"]) if dm else None

    def root_rect(self, root):
        info = self.winfo(root)
        if not info:
            return None
        l, t, r, b = info[3]
        return (r - l, b - t) if 0 < r - l < 20000 and 0 < b - t < 20000 else None

    # ------------------------------------------------------------------ the wizard and the backpack
    def player(self):
        """(the wizard's WizClientObject - the camera's object, "") or (0, why)"""
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

    def template_info(self, tid, hm):
        """(object name, [adjectives]) of template id tid - None each when it can't be read; kept (templates don't change)
        only when both were read whole - a read in part is tried again next time"""
        if tid in self.tpl:
            return self.tpl[tid]
        name, adjs = None, None
        t = hm.template(tid) if tid else 0
        if t and (self.tname(t) or "").endswith("Template"):
            if self.off("GameObjectTemplate", "m_objectName") is not None:
                name = self.string(t + self.P["GameObjectTemplate"]["m_objectName"])
            if self.off("GameObjectTemplate", "m_adjectiveList") is not None:
                adjs = self.str_list(t + self.P["GameObjectTemplate"]["m_adjectiveList"])
                if adjs is not None:
                    adjs = [a for a in adjs if a]
        if name is not None and adjs is not None:
            if len(self.tpl) > 5000:
                self.tpl.clear()
            self.tpl[tid] = (name, adjs)
        return name, adjs

    def bag(self, hm):
        """({items, allowed, extra, gold, gold_max, player_gid, walked, emotes, cats {kind: [n, crowns, nosell]}, sets
        [{n, equipped, name, ids}], set_items [{set, equipped, gid, template, name, kind, crowns}], tips [{name, shown,
        rect, image, button}], space (N, M) or None, space_raw, root (w, h)}, "") - or (None, why). Never raises"""
        try:
            return self._bag(hm)
        except Exception as e:  # noqa: BLE001 - never into navmem
            return None, "reading the backpack failed (%r)" % (e,)

    def _bag(self, hm):
        CO, P = self.P["CoreObject"], self.P
        co, why = self.player()
        if not co:
            return None, why
        r = {"items": None, "allowed": None, "extra": None, "gold": None, "gold_max": None, "walked": 0, "emotes": 0,
             "player_gid": self.u64(co + CO["m_globalID.m_full"]) or None, "cats": {}, "sets": [], "set_items": [],
             "sets_ok": False, "tips": [], "space": None, "space_raw": None, "root": None, "crownshop": []}
        gs = self.u64(co + P["WizClientObject"]["m_gameStats"])
        if gs and self.tname(gs) == "WizGameStats":
            r["gold"] = self.i32(gs + P["WizGameStats"]["m_currentGold"])
            r["gold_max"] = self.i32(gs + P["WizGameStats"]["m_baseGoldPouch"])
            if self.off("WizGameStats", "m_extraInventorySpace") is not None:
                r["extra"] = self.i32(gs + P["WizGameStats"]["m_extraInventorySpace"])
        inv = eq = 0
        for beh in self.vec16(co + CO["m_inactiveBehaviors"]):
            tn = self.tname(beh)
            if tn == "ClientWizInventoryBehavior" and not inv:
                inv = beh
            elif tn == "ClientWizEquipmentBehavior" and not eq:
                eq = beh
        if not inv:
            return None, "no backpack on the wizard (its inventory behavior wasn't found)"
        r["allowed"] = self.u32(inv + P["ClientWizInventoryBehavior"]["m_numItemsAllowed"])
        size, items = self.slist(inv + P["InventoryBehaviorBase"]["m_itemList"], ITEMS_CAP)
        if size is None:
            return None, "the backpack's item list can't be read"
        r["items"] = size
        # (the list broke off before its end - the game changing it as it's read: not given at all - an Equipment Set's
        # item in the part not read would be missed)
        if len(items) < min(size, ITEMS_CAP):
            return None, "the backpack's item list broke off after %d of %d (read again in a moment)" % (len(items), size)
        gids = {}
        for it in items:
            gid = self.u64(it + CO["m_globalID.m_full"])
            tid = self.u32(it + CO["m_templateID.m_full"])
            name, adjs = self.template_info(tid, hm)
            kind = item_kind(adjs)
            flagged = adjs is not None and "FLAG_CrownsOnly" in adjs
            # (a Crown-shop template - "Crown-S05-Robe-093" or the game's own "Crowns-S67-Robe-L50-DS-010-01" - is a
            # Crowns item to the bot even without the game's flag: the live Crown-S05 gear and some Crowns-S67 / S63 / S53
            # gear have none - never counted as plain gear that may be sold)
            # (its name not read: it could be one - counted as one, its group not sold this time)
            shop = name is None or name.startswith(("Crown-", "Crowns-"))
            crowns = flagged or shop
            nosell = adjs is not None and "FLAG_NoSell" in adjs
            # (every kind with one listed - the list's cut short only after that: QuickSell.ahk keeps those groups out)
            ck = kind if kind is not None else "?"
            if shop and not flagged and (len(r["crownshop"]) < 40 or all(ck != k for k, _ in r["crownshop"])):
                r["crownshop"].append((ck, name if name is not None else "template %s (its name not read)" % tid))
            # (its global id not read: it isn't walked - an Equipment Set's item could go unnoticed - sets_ok stays off)
            if gid:
                gids[gid] = (tid, name, kind, crowns)
                r["walked"] += 1
            k = kind if kind is not None else "?"
            c = r["cats"].setdefault(k, [0, 0, 0, 0])
            c[0] += 1
            c[1] += 1 if crowns else 0
            c[2] += 1 if nosell else 0
            c[3] += 1 if not crowns and not nosell else 0
            r["emotes"] += 1 if kind == "emote" else 0
        # the Equipment Sets and their items in the backpack - sets_ok only when every set and its items were read (and
        # every backpack item was walked): else an item of a set could be missed, and nothing's sold
        so = self.off("ClientWizEquipmentBehavior", "m_equipmentSets")
        ES = P["EquipmentSet"]
        if eq and so is not None and all(k in ES for k in ("m_serializedItems", "m_isEquipped")):
            ssize, sets = self.slist(eq + so, SETS_CAP)
            ok = ssize is not None and len(sets) == ssize
            for i, es in enumerate(sets, 1):
                if self.tname(es) != "EquipmentSet":
                    ok = False
                    continue
                ids = parse_set_ids(self.raw_string(es + ES["m_serializedItems"]))
                if ids is None:
                    ok, ids = False, []
                # (its name, m_equipmentSetName, isn't a string in this build - 8 bytes before the items: not read)
                equipped = self.flag(es + ES["m_isEquipped"])
                r["sets"].append({"n": i, "equipped": equipped, "name": None, "ids": ids})
                for g in ids:
                    if g in gids:
                        tid, name, kind, crowns = gids[g]
                        r["set_items"].append({"set": i, "equipped": equipped, "gid": g, "template": tid, "name": name,
                                               "kind": kind, "crowns": crowns})
            r["sets_ok"] = ok and r["walked"] == size
        # the tips and the backpack page's N/M
        root = hm.root()
        if root:
            r["root"] = self.root_rect(root)
            found, _ = self.walk(root, {"TipWindow", "inventorySpace"})
            for f in found:
                if f["name"] == "TipWindow" and "windowHUD" in f["chain"] and not r["tips"]:
                    r["tips"] = self.tips(f)
                elif f["name"] == "inventorySpace" and "InventorySpellbookPage" in f["chain"] and f["shown"] \
                        and r["space"] is None:
                    raw = self.text(f["w"] + P["ControlText"]["m_sText"])
                    r["space_raw"], r["space"] = raw, parse_space(raw)
        return r, ""

    def tips(self, f):
        """[{name, shown, rect, image, button}] of the TipWindow f's children (the right-hand column's icons)"""
        out = []
        for c in f["kids"][:24]:
            info = self.winfo(c)
            if info is None:
                continue
            name, kids, flags, (l, t, rr, b) = info
            ox, oy = f["rect"][0], f["rect"][1]
            tip = {"name": name, "shown": f["shown"] and bool(flags & 1), "rect": (ox + l, oy + t, ox + rr, oy + b),
                   "image": None, "button": None}
            for k in kids[:8]:
                ki = self.winfo(k)
                if ki and ki[0] in ("image", "button") and tip[ki[0]] is None:
                    tip[ki[0]] = self.texture(k)
            out.append(tip)
        return out

    # ------------------------------------------------------------------ the windows by name
    def gui(self, hm, paths):
        """({root (w, h), wins {path: {type, shown, rect, prect, checked, greyed, raw, dups (shown matches), matches} or
        None}, box {shown, title_raw, caption_raw, btns [{name, rect, greyed, raw}]} or None, walked}, "") - or (None,
        why). A path "Anc/Name" (more ancestors allowed): the first window named Name with those ancestors, in that order
        - the first shown one when there are several. Never raises"""
        try:
            return self._gui(hm, paths)
        except Exception as e:  # noqa: BLE001 - never into navmem
            return None, "reading the game's windows failed (%r)" % (e,)

    def _gui(self, hm, paths):
        parsed = [(p, p.split("/")) for p in paths]
        root = self.root_of(hm, [n for _, parts in parsed for n in parts])
        if not root:
            return None, "no GUI root (not in the game world)"
        rr = self.root_rect(root)
        if rr is None:
            return None, "the GUI root's size can't be read"
        want = {parts[-1] for _, parts in parsed} | set(BOX_PARTS) | {"MessageBoxModalWindow"}
        found, n = self.walk(root, want)
        wins = {}
        for p, parts in parsed:
            cands = [f for f in found if f["name"] == parts[-1] and anc_match(parts[:-1], f["chain"])]
            shown = [f for f in cands if f["shown"]]
            pick = shown[0] if shown else (cands[0] if cands else None)
            if pick is None:
                wins[p] = None
                continue
            d = self.describe(pick)
            d["dups"], d["matches"] = len(shown), len(cands)
            wins[p] = d
        box = None
        boxes = [f for f in found if f["name"] == "MessageBoxModalWindow" and f["shown"]]
        if boxes:
            bw = boxes[0]["w"]
            inside = [f for f in found if bw in f["chain_w"]]
            # (count: how many are up - the first one read may not be the one on top: QuickSell.ahk clicks none then)
            box = {"shown": True, "count": len(boxes), "title_raw": None, "caption_raw": None, "btns": []}
            for f in inside:
                if f["name"] == "TitleText" and box["title_raw"] is None:
                    box["title_raw"] = self.describe(f)["raw"]
                elif f["name"] == "CaptionText" and box["caption_raw"] is None:
                    box["caption_raw"] = self.describe(f)["raw"]
                elif f["name"] in ("centerButton", "leftButton", "rightButton") and f["shown"]:
                    d = self.describe(f)
                    box["btns"].append({"name": f["name"], "rect": d["rect"], "greyed": d["greyed"], "raw": d["raw"]})
        return {"root": rr, "wins": wins, "box": box, "walked": n}, ""

    # ------------------------------------------------------------------ every window under one (discovery)
    def tree(self, hm, under=None, shown_only=True, depth=None, cap=TREE_ROWS):
        """({root (w, h), under, matches, dups, rows [{depth, parent, name, type, shown, rect, prect, checked, greyed, raw,
        tex, kids, flags}], walked, capped, all}, "") - or (None, why). Every window under the one under names
        ("Anc/Name" as gui()'s paths - the first shown match, else the first; None / "": the GUI root) - that one too,
        depth 0 - in the game's order, an ancestor before its windows: shown_only only those shown (VISIBLE on it and
        every ancestor: a hidden one's windows are hidden too - not walked), else every one (all: not shown_only); depth
        that many levels below it at most (None: TREE_DEPTH). Two walks when under is given: the GUI root's windows
        for its name (as gui()'s: one read a window - TREE_DEPTH levels, WIN_CAP windows), then the windows under the
        one found alone, with their own depth and WIN_CAP - asking under a window gets past a cap the whole tree hits.
        cap rows at most. capped: something was cut short - cap rows listed, WIN_CAP windows walked, or windows deeper
        than TREE_DEPTH left out (a depth asked for isn't a cut) - under it, or finding it when no shown match was found
        (with matches 0: the window asked for may sit where that walk didn't reach - not "no such window"). rows: depth
        below the top one, parent its parent's row number (1 the first row, 0 the top one), describe()'s type, shown,
        rect (in the root), prect, checked, greyed and raw text, tex (texture()'s file), kids (how many children -
        hidden ones too), flags (m_Flags as read). walked: windows read by both walks. matches: the windows under names
        among those walked (shown_only: a hidden window's windows aren't, so a hidden match inside one isn't counted),
        dups the shown ones; under not found: matches 0 and no rows. Read-only discovery - the names of a window's
        buttons, lists and a box's keys (bagmem.py --tree, the helper's /guitree) - and the rows of a list. Never
        raises"""
        try:
            return self._tree(hm, under, shown_only, depth, cap)
        except Exception as e:  # noqa: BLE001 - never into navmem
            return None, "reading the game's window tree failed (%r)" % (e,)

    def _tree(self, hm, under, shown_only, depth, cap):
        root = self.root_of(hm, (under or "").split("/"))
        if not root:
            return None, "no GUI root (not in the game world)"
        rr = self.root_rect(root)
        if rr is None:
            return None, "the GUI root's size can't be read"
        out = {"root": rr, "under": under or "", "matches": 0, "dups": 0, "rows": [], "walked": 0, "capped": False,
               "all": not shown_only}
        top_w, start = root, None
        if under:
            # (first the window asked for: the root's windows read for its name only, as gui() does - one read a window,
            # none described; with shown_only a hidden window's windows aren't walked: none of them could be a row)
            parts = under.split("/")
            found, n, deep = self._walk(root, {parts[-1]}, TREE_DEPTH, WIN_CAP, None, shown_only)
            cands = [f for f in found if f["name"] == parts[-1] and anc_match(parts[:-1], f["chain"])]
            shown = [f for f in cands if f["shown"]]
            top = shown[0] if shown else (cands[0] if cands else None)
            # (this walk cut short - WIN_CAP windows, TREE_DEPTH levels - is a cut only when no shown match was found:
            # one may sit past where it stopped; the first shown one found is the first in the game's order anyway)
            out["matches"], out["dups"], out["walked"] = len(cands), len(shown), n
            out["capped"] = not shown and (n >= WIN_CAP or deep > 0)
            if top is None or (shown_only and not top["shown"]):
                return out, ""
            # (then its windows alone - their own depth and WIN_CAP -, their chains, shown and rects as from the root)
            p = top["prect"]
            top_w, start = top["w"], (top["chain"], top["chain_w"], top["up"], p[0] if p else 0, p[1] if p else 0, p)
        # (only the rows listed are described - their type, text and texture are the reads that cost)
        depth = None if depth is None else max(0, depth)
        found, n, deep = self._walk(top_w, None, TREE_DEPTH if depth is None else depth, WIN_CAP, start, shown_only)
        out["walked"] += n
        out["capped"] = out["capped"] or n >= WIN_CAP or (depth is None and deep > 0)
        top = found[0] if found and found[0]["w"] == top_w else None
        if not under:
            out["matches"] = 1 if top else 0
            out["dups"] = 1 if top and top["shown"] else 0
        if top is None:
            return out, ""
        rows, capped = subtree(found, top, shown_only, depth, cap)
        out["capped"] = out["capped"] or capped
        for f, d, parent in rows:
            desc = self.describe(f)
            desc.update(depth=d, parent=parent, name=f["name"], tex=self.texture(f["w"]), kids=len(f["kids"]),
                        flags=f["flags"])
            out["rows"].append(desc)
        return out, ""


# ============================================================================ answers
def finish_gui(g, lang):
    """each raw text of a gui() reading given its words and key (clean_text) - outside navmem's lock (the name tables are
    read from Root.wad the first time)"""
    if not g:
        return g
    for d in (g.get("wins") or {}).values():
        if d is not None:
            d["text"], d["key"] = clean_text(d.get("raw"), lang)
    box = g.get("box")
    if box:
        box["title"], box["title_key"] = clean_text(box.get("title_raw"), lang)
        box["caption"], box["caption_key"] = clean_text(box.get("caption_raw"), lang)
        for b in box["btns"]:
            b["label"], b["key"] = clean_text(b.get("raw"), lang)
    return g


def _r(rect):
    return [cell(v) for v in (rect or (None, None, None, None))]


def bag_lines(r, why=""):
    """/bag's answer for bag()'s reading (r None: none|<why>):
    bag|items|allowed|extra|gold|goldmax|player gid hex|walked|emotes|sets read (1: every set and its items read)
    space|N|M|raw text                                       (only while the backpack page is shown)
    cat|kind|n|crowns|nosell|plain                           (each kind in the backpack; ? not read; crowns: Crowns
                                                              items and Crown-shop templates; plain: neither nor nosell)
    crownshop|kind|object name                               (Crown-shop templates without the game's Crowns flag, and
                                                              items whose name wasn't read - every kind with one listed)
    tip|i|shown|l|t|r|b|image texture|button texture|name    (the HUD's right-hand column, its rect in the root)
    set|n|equipped|ids|name                                  (each Equipment Set)
    setitem|set n|set equipped|gid hex|template id|object name|kind|crowns
    root|w|h"""
    if not r:
        return ['none|' + cell(why or "the backpack can't be read")]
    out = ['|'.join(['bag', cell(r.get('items')), cell(r.get('allowed')), cell(r.get('extra')), cell(r.get('gold')),
                     cell(r.get('gold_max')), '%x' % r['player_gid'] if r.get('player_gid') else '',
                     cell(r.get('walked')), cell(r.get('emotes')), cell(bool(r.get('sets_ok')))])]
    if r.get('space'):
        out.append('space|%d|%d|%s' % (r['space'][0], r['space'][1], cell(strip_markup(r.get('space_raw') or ''))))
    for k in sorted(r.get('cats') or {}):
        c = r['cats'][k]
        n, crowns, nosell = c[:3]
        plain = c[3] if len(c) > 3 else max(0, n - crowns - nosell)
        out.append('cat|%s|%d|%d|%d|%d' % (cell(k), n, crowns, nosell, plain))
    for kind, name in r.get('crownshop') or []:
        out.append('crownshop|%s|%s' % (cell(kind), cell(name)))
    for i, t in enumerate(r.get('tips') or [], 1):
        out.append('|'.join(['tip', str(i), cell(bool(t.get('shown')))] + _r(t.get('rect'))
                            + [cell(t.get('image')), cell(t.get('button')), cell(t.get('name'))]))
    for s in r.get('sets') or []:
        out.append('|'.join(['set', str(s['n']), cell(s.get('equipped')), str(len(s.get('ids') or [])), cell(s.get('name'))]))
    for si in r.get('set_items') or []:
        out.append('|'.join(['setitem', str(si['set']), cell(si.get('equipped')), '%x' % si['gid'], cell(si.get('template')),
                             cell(si.get('name')), cell(si.get('kind') if si.get('kind') is not None else '?'),
                             cell(bool(si.get('crowns')))]))
    if r.get('root'):
        out.append('root|%d|%d' % r['root'])
    return out


def gui_lines(g, why="", paths=()):
    """/gui's answer for gui()'s reading, finished (finish_gui) - g None: none|<why>:
    root|w|h
    win|path|type|shown|l|t|r|b|checked|greyed|text|key|dups|pl|pt|pr|pb|matches   (each path asked; one not found:
        its type empty, shown 0, matches 0; l..b in the root, pl..pb its parent's; dups: its shown matches)
    box|shown|title|caption|title key|caption key|count      (the message box up - box|0 none; count: how many are up)
    btn|name|label|l|t|r|b|key|greyed                        (its shown buttons)"""
    if not g:
        return ['none|' + cell(why or "the game's windows can't be read")]
    out = ['root|%d|%d' % g['root']]
    for p in paths:
        d = (g.get('wins') or {}).get(p)
        if d is None:
            out.append('|'.join(['win', cell(p), '', '0'] + [''] * 4 + ['', '', '', '', '0'] + [''] * 4 + ['0']))
            continue
        out.append('|'.join(['win', cell(p), cell(d.get('type')), cell(bool(d.get('shown')))] + _r(d.get('rect'))
                            + [cell(d.get('checked')), cell(d.get('greyed')), cell(d.get('text')), cell(d.get('key')),
                               cell(d.get('dups'))] + _r(d.get('prect')) + [cell(d.get('matches'))]))
    box = g.get('box')
    if not box:
        out.append('box|0|||||0')
    else:
        out.append('|'.join(['box', '1', cell(box.get('title')), cell(box.get('caption')), cell(box.get('title_key')),
                             cell(box.get('caption_key')), cell(box.get('count'))]))
        for b in box.get('btns') or []:
            out.append('|'.join(['btn', cell(b['name']), cell(b.get('label'))] + _r(b.get('rect'))
                                + [cell(b.get('key')), cell(b.get('greyed'))]))
    return out


def finish_tree(t, lang):
    """each row's raw text of a tree() reading given its words and key (clean_text) - outside navmem's lock, as
    finish_gui"""
    for d in (t or {}).get("rows") or []:
        d["text"], d["key"] = clean_text(d.get("raw"), lang)
    return t


def tree_lines(t, why="", indent=False):
    """/guitree's answer (and bagmem.py --tree's) for tree()'s reading, finished (finish_tree) - t None: none|<why>:
    root|w|h
    tree|under|matches|dups|rows|walked|capped|all     (under: the path asked, "" the GUI root; matches: the windows it
        names that were walked - 0 none, no rows then; dups: its shown matches; rows: the window lines below; walked:
        windows read - finding the one asked for, then under it; capped 1: cut short - under it TREE_ROWS rows listed,
        WIN_CAP windows walked or windows more than TREE_DEPTH levels down left out (a depth asked for isn't a cut):
        ask under a window lower down; or finding it, when no shown match was found (WIN_CAP windows, TREE_DEPTH levels
        below the root): with matches 0 the window asked for may be past where that walk stopped - not "no such
        window"; all 1: hidden windows too)
    depth|name|type|shown|l|t|r|b|text|key|greyed|checked|texture|kids|parent|flags     (one a window, in the game's
        order - an ancestor before its windows; depth 0 the window asked for; l..b in the root; text its words - the
        markup out, a "<string;KEY>" given its words ("{KEY}" when the name tables haven't it); key that KEY when it's
        all the text; greyed / checked 1/0 ("" not a button / check box); texture a sprite's or a button's file; kids
        its children, hidden ones too; parent the row number of its parent window - 1 the first window line, 0 the top
        one; flags its m_Flags in hex - bit 0 VISIBLE)
    indent: each name led by two spaces a level - to read it, not to parse it (bagmem.py --tree --indent)"""
    if not t:
        return ['none|' + cell(why or "the game's windows can't be read")]
    rows = t.get('rows') or []
    out = ['root|%d|%d' % t['root'],
           '|'.join(['tree', cell(t.get('under')), cell(t.get('matches')), cell(t.get('dups')), str(len(rows)),
                     cell(t.get('walked')), cell(bool(t.get('capped'))), cell(bool(t.get('all')))])]
    for d in rows:
        name = cell(d.get('name'))
        out.append('|'.join([str(d.get('depth', 0)), ('  ' * d.get('depth', 0) + name) if indent else name,
                             cell(d.get('type')), cell(bool(d.get('shown')))] + _r(d.get('rect'))
                            + [cell(d.get('text')), cell(d.get('key')), cell(d.get('greyed')), cell(d.get('checked')),
                               cell(d.get('tex')), cell(d.get('kids')), cell(d.get('parent')),
                               '%x' % d['flags'] if d.get('flags') is not None else '']))
    return out


def nav_tree(nm, under=None, shown_only=True, depth=None, wait=0.3):
    """(t, why): tree() through navmem's NavMem nm - its attached game, its backpack and hand readers (the GUI's root, the
    name tables) and its lock, the same way as NavMem.gui (kept here so navmem.py needn't change for a discovery tool),
    the texts finished outside the lock (finish_tree). None and why when the game can't be read. Never raises"""
    try:
        st, bm, hm, why = nm._bag_readers(wait)
        if st is None:
            return None, why
        with nm.lock:
            if nm.st is not st or hm.st is not st or bm.st is not st:
                return None, "the game changed"
            t, why = bm.tree(hm, under, shown_only, depth)
        return finish_tree(t, hm.lang_text), why
    except Exception as e:  # noqa: BLE001 - never into the server
        return None, "reading the game's window tree failed (%r)" % (e,)


# ============================================================================ the command line
def _main():
    import argparse
    ap = argparse.ArgumentParser(description="the backpack, the tips and the game's windows - read-only")
    ap.add_argument("--gui", default="", help="window paths, Anc/Name,...")
    ap.add_argument("--tree", action="store_true",
                    help="every shown window, one a line (discovery: the names of buttons, lists, a box's keys) - "
                         "instead of the backpack")
    ap.add_argument("--under", default="", help="with --tree: only the window Anc/Name and those under it")
    ap.add_argument("--all", action="store_true", help="with --tree: the hidden windows too")
    ap.add_argument("--depth", type=int, default=None,
                    help="with --tree: this many levels below it at most (else %d - deeper ones left out: capped 1)"
                         % TREE_DEPTH)
    ap.add_argument("--indent", action="store_true", help="with --tree: names indented by depth (to read, not to parse)")
    ap.add_argument("--out", default="", help="also write the answer to this file (to send)")
    a = ap.parse_args()
    under = tree_under(a.under)
    paths = gui_paths(a.gui)
    if under is None or paths is None:
        sys.exit("--under / --gui: window paths are Anc/Name - letters, digits and _ split by / (%d paths at most)"
                 % PATHS_CAP)
    lines = []
    nm = N.NavMem(log=print)
    try:
        if a.tree:
            # (the readers are made in threads the first time - the game attached, the classes looked up: asked again
            # while they're on their way)
            t, why = None, ""
            for _ in range(6):
                t, why = nav_tree(nm, under, not a.all, a.depth, wait=5.0)
                if t is not None or "not running" in why:
                    break
            lines += ["# python bagmem.py --tree%s%s%s (%s)" % (" --under " + under if under else "",
                                                               " --all" if a.all else "",
                                                               " --depth %d" % a.depth if a.depth is not None else "",
                                                               time.strftime("%Y-%m-%d %H:%M:%S"))]
            lines += tree_lines(t, why, a.indent)
        else:
            r, why = nm.bag(wait=5.0)
            lines += bag_lines(r, why)
        if paths:
            g, why = nm.gui(paths, wait=5.0)
            lines += gui_lines(g, why, paths)
    finally:
        nm.close()
    print("\n".join(lines))
    if a.out:
        with open(a.out, "w", encoding="utf-8") as f:
            f.write("\n".join(lines) + "\n")
        print("(written to %s - %d lines)" % (os.path.abspath(a.out), len(lines)))


if __name__ == "__main__":
    _main()
