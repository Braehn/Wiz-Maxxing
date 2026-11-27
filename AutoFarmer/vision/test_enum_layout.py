"""test_enum_layout.py - a reflected enum's option names (handmem.read_enum, enum_by_prop) in both of the game's layouts.
Build 6B05FDF0-37BB000 (2026-11-26): the option names no longer run in .rdata after the first one - each option has a copy
of the property's name of its own, the short names are built in place (movups xmm0,[rip+name]; movzx ecx, word
[rip+name+16]...) - and read_enum named 2 of SpellEffect's 152 effect types: "the spell effect names couldn't be read",
the cards, the deck and the GUI root unread from the game's patch on. On a made-up game image (test_reflect's):
    python -m unittest test_enum_layout   (from AutoFarmer\\vision)"""
import os
import struct
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from test_reflect import ADDER, R0, T0, Image, _stub_navmem  # noqa: E402

STRS_AT = 0x1000          # .rdata offset of the strings put by hand (each its own copy: Image.string pools them)
OPTS_AT = 0x900           # .text offset of the options' registration code (SpellEffect's GetType at 0x100)


class Game(Image):
    def __init__(self):
        super().__init__()
        self.hand = STRS_AT

    def copy(self, s, junk=b""):
        """a NUL-led copy of s of its own in .rdata (junk first - another string, so nothing runs on into the next)"""
        if junk:
            self.rdata[self.hand + 1:self.hand + 1 + len(junk) + 1] = junk + b"\0"
            self.hand += 1 + len(junk) + 1
        b = s.encode() + b"\0"
        at = self.hand + 1
        self.rdata[at:at + len(b)] = b
        self.hand = at + len(b)
        return R0 + at


def filler(at, call_to=ADDER["int"]):
    """lea rcx,[rbp+0E98h]; call AddProperty; nop - the options' code between the loads that matter"""
    c = b"\x48\x8D\x8D\x98\x0E\x00\x00"
    return c + Image.rip(at + len(c), b"\xE8", T0 + call_to, 5) + b"\x90"


def store(v, reg=False):
    """mov dword [rsp+30h], v - or mov [rsp+30h], esi (a register kept at 0)"""
    return b"\x89\x74\x24\x30" if reg else b"\xC7\x44\x24\x30" + struct.pack("<i", v)


def new_layout(opts, tail=None):
    """SpellEffect (GetType at .text 0x100) whose m_effectType options are registered the 6B05FDF0 way: for each (value,
    name, how) - a copy of "m_effectType" of its own loaded (lea rdx), filler, the name loaded ('lea': lea rdx,[name];
    'sse': movups xmm0,[name] - and its bytes 16.. by movzx ecx, word [name+16]), the value stored (0: from esi), filler.
    Then the property's own load with no option (its commit), and one more load whose code runs on into another
    property's options (tail: (value, name) - m_disposition's kBoth in the game)"""
    im = Game()
    im.klass("SpellEffect", 0x100, 0x180, [("m_numRounds", 0x48, "int")])
    pos, code = OPTS_AT, b""

    def add(c):
        nonlocal pos, code
        code += c
        pos += len(c)

    for v, name, how in opts:
        add(Image.rip(pos, b"\x48\x8D\x15", im.copy("m_effectType", junk=b"%s junk for " + name.encode())))
        add(filler(pos))
        at = im.copy(name, junk=b"Spell: other words")
        if how == "lea":
            add(Image.rip(pos, b"\x48\x8D\x15", at))
            add(filler(pos))
        else:
            add(Image.rip(pos, b"\x0F\x10\x05", at))                   # movups xmm0, [name]
            add(b"\x0F\x11\x00")                                        # movups [rax], xmm0
            if len(name) > 16:
                add(Image.rip(pos, b"\x0F\xB7\x0D", at + 16))          # movzx ecx, word [name+16] (not its start)
                add(b"\x66\x89\x48\x10")
        add(store(v, reg=(v == 0)))
        add(b"\x48\x8D\x54\x24\x30")                                    # lea rdx, [rsp+30h]
        add(filler(pos))
    add(Image.rip(pos, b"\x48\x8D\x15", im.copy("m_effectType")))     # (the commit: no option)
    add(filler(pos))
    if tail:
        add(Image.rip(pos, b"\x48\x8D\x15", im.copy("m_effectType")))
        add(filler(pos))
        add(Image.rip(pos, b"\x48\x8D\x15", im.copy(tail[1])))
        add(store(tail[0]))
        add(filler(pos))
    im.put(OPTS_AT, code + b"\xC3")
    return im


def old_layout(opts, prop_loads=False):
    """the run: "kFirst\\0m_effectType\\0kNext\\0m_effectType\\0..." in .rdata, each option's code lea rdx,[name] then its
    value stored - prop_loads: each option loads the run's own copy of the property's name first, too"""
    im = Game()
    im.klass("SpellEffect", 0x100, 0x180, [("m_numRounds", 0x48, "int")])
    run, at = [], STRS_AT + 1
    for v, name in opts:
        for s in (name, "m_effectType"):
            b = s.encode() + b"\0"
            im.rdata[at:at + len(b)] = b
            run.append((s, R0 + at))
            at += len(b)
    names = [(s, a) for s, a in run if s != "m_effectType"]
    props = [a for s, a in run if s == "m_effectType"]
    pos, code = OPTS_AT, b""
    for k, (v, name) in enumerate(opts):
        c = b""
        if prop_loads:
            c += Image.rip(pos, b"\x48\x8D\x15", props[k])
            c += filler(pos + len(c))
        c += Image.rip(pos + len(c), b"\x48\x8D\x15", names[k][1])
        c += filler(pos + len(c))
        c += store(v, reg=(v == 0))
        c += filler(pos + len(c))
        code += c
        pos += len(c)
    im.put(OPTS_AT, code + b"\xC3")
    return im


OPTS = [(0, "kInvalidSpellEffect", "sse"), (1, "kDamage", "sse"), (2, "kDamageNoCrit", "sse"), (3, "kHeal", "sse"),
        (4, "kHealPercent", "sse"), (114, "kModifyPipRoundRate", "lea"), (5, "kStealHealth", "lea"),
        (85, "kDamagePerTotalPipPower", "lea"), (87, "kCloakedWardNoRemove", "lea"), (152, "kShadowPact", "lea")]


class EnumLayout(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        _stub_navmem()
        import handmem as H
        cls.H = H

    def read(self, im, first="kInvalidSpellEffect"):
        return self.H.read_enum(self.H.Image(im.st()), first, "m_effectType", "SpellEffect")

    def test_new_layout(self):
        """every option named by the property's own loads - the short names built in place too, the value stored from a
        register 0 - and none in a gap (86: retired)"""
        got = self.read(new_layout(OPTS))
        self.assertEqual(got, {v: s for v, s, _ in OPTS})

    def test_handmem_check(self):
        """what HandMem asks of the effect names before it reads cards: 0 kInvalidSpellEffect, 1 kDamage, 3 kHeal"""
        got = self.read(new_layout(OPTS))
        self.assertTrue(got.get(0) == "kInvalidSpellEffect" and got.get(1) == "kDamage" and got.get(3) == "kHeal")

    def test_no_first(self):
        """the first option's name not found at all: the rest still read by the property's name"""
        got = self.read(new_layout(OPTS), first="kNotInThisBuild")
        self.assertEqual(got, {v: s for v, s, _ in OPTS})

    def test_open_window_not_read(self):
        """the last load of the property's name has no next one to bound it - its code runs on into the next property's
        options (m_disposition's kBoth): never read, even for a value with no name"""
        got = self.read(new_layout(OPTS, tail=(86, "kBoth")))
        self.assertNotIn(86, got)
        self.assertNotIn("kBoth", got.values())
        self.assertEqual(got, {v: s for v, s, _ in OPTS})

    def test_mid_string_load(self):
        """a load of a name's bytes 16 on (movzx word [name+16]) isn't a name: its start has no NUL before it"""
        im = new_layout([(0, "kInvalidSpellEffect", "sse"), (7, "kAbcdefghijklmnokTailName", "sse")])
        self.assertEqual(self.read(im), {0: "kInvalidSpellEffect", 7: "kAbcdefghijklmnokTailName"})

    def test_old_layout(self):
        """the run's way (builds to 6AFBB954) as it was - with and without each option loading the run's own copy of the
        property's name: the same names"""
        opts = [(v, s) for v, s, _ in OPTS]
        want = dict(opts)
        self.assertEqual(self.read(old_layout(opts)), want)
        self.assertEqual(self.read(old_layout(opts, prop_loads=True)), want)

    def test_enum_by_prop_alone(self):
        """enum_by_prop on its own: the new layout's options; the run's (prop_loads) the same"""
        import numpy as np
        H = self.H
        for im in (new_layout(OPTS, tail=(86, "kBoth")), old_layout([(v, s) for v, s, _ in OPTS], prop_loads=True)):
            img = H.Image(im.st())
            t0, text = img.secs[".text"]
            gt = H.class_props(img, "SpellEffect")[1]
            lo = gt - t0
            seg = np.frombuffer(text[lo:lo + 0x10000], dtype=np.uint8).astype(np.int64)
            d = seg[:-3] | (seg[1:-2] << 8) | (seg[2:-1] << 16) | (seg[3:] << 24)
            d = np.where(d >= 1 << 31, d - (1 << 32), d)
            tgt = np.arange(len(d)) + t0 + lo + 4 + d
            got = H.enum_by_prop(img, "m_effectType", lo, tgt)
            # (the run's way: its last option is in the open window - no commit load after it - so not read here)
            want = {v: s for v, s, _ in OPTS}
            if im.hand == STRS_AT:
                del want[152]
            self.assertEqual(got, want)

    def test_unknown_class(self):
        """no such class in this build: {}"""
        H = self.H
        im = new_layout(OPTS)
        self.assertEqual(H.read_enum(H.Image(im.st()), "kInvalidSpellEffect", "m_effectType", "NoSuchEffect"), {})


if __name__ == "__main__":
    unittest.main()
