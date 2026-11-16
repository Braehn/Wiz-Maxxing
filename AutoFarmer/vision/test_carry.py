"""test_carry.py - carry mode's two wizards (AutoFarmer\\Carry.ahk), static checks on the scripts, no AutoHotkey:
    python -m unittest test_carry      (from AutoFarmer\\vision)

Each wizard's battle is kept aside while the other plays (CarrySwap): every global ResetVariables starts a battle with has
to be in CarryStateNames (the wizard's own) or CarryShared (the battle's) - a new one left out would carry the main's
blades or deck into the carry's round. Every name swapped has to be declared global somewhere (a dynamic %name% can't make
one). And with a main client picked (Alt+M) every window the bot works on is found by GameWT - only the
places that look at every client (or what you pressed on) may name the game's window class themselves."""
import os
import re
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
AF = os.path.dirname(HERE)
ROOT = os.path.dirname(AF)


def read(path):
    with open(path, encoding='utf-8-sig') as f:
        return f.read().replace('\r\n', '\n')


def func_body(text, name):
    m = re.search(r'^' + name + r'\(\)[^\n]*\n\t?\{\n(.*?)\n\t?\}\n', text, re.S | re.M)
    if not m:
        raise AssertionError(name + ' not found')
    return m.group(1)


def assigned(body):
    out = []
    for line in body.split('\n'):
        code = line.split(';')[0]
        for m in re.finditer(r'(?:^|,)\s*([A-Za-z_]\w*)\s*:=', code):
            if m.group(1).lower() not in [x.lower() for x in out]:
                out.append(m.group(1))
    return out


def ahk_list(body):
    return re.findall(r'"([A-Za-z_]\w*)"', body)


def reset_body(af):
    return re.search(r'^ResetVariables\(\)\s*\n\t\{\n(.*?)\n\}\n', af, re.S | re.M).group(1)


class Swap(unittest.TestCase):
    def setUp(self):
        self.af = read(os.path.join(AF, 'Autofarmer.ahk'))
        self.carry = read(os.path.join(AF, 'Carry.ahk'))

    def test_every_battle_global_is_kept_or_shared(self):
        reset = assigned(reset_body(self.af))
        self.assertIn('AppliedBlades', reset)
        own = set(n.lower() for n in ahk_list(func_body(self.carry, 'CarryStateNames')))
        shared = set(n.lower() for n in ahk_list(func_body(self.carry, 'CarryShared')))
        self.assertFalse(own & shared, 'both kept and shared: %s' % sorted(own & shared))
        missing = [n for n in reset if n.lower() not in own | shared]
        self.assertEqual(missing, [], 'ResetVariables sets these - add them to CarryStateNames or CarryShared')

    def test_every_swapped_name_is_a_declared_global(self):
        declared = set()
        for d in (AF, os.path.join(ROOT, 'AutoQuester')):
            for fn in os.listdir(d):
                if fn.lower().endswith('.ahk'):
                    for line in read(os.path.join(d, fn)).split('\n'):
                        if line.lstrip().startswith('global '):
                            for m in re.finditer(r'(?:global\s+|,)\s*([A-Za-z_]\w*)', line.split(';')[0]):
                                declared.add(m.group(1).lower())
        # (ResetVariables assumes globals: whatever it sets is one - bladetype, traptype are made only so)
        declared |= set(n.lower() for n in assigned(reset_body(self.af)))
        names = ahk_list(func_body(self.carry, 'CarryStateNames')) + ahk_list(func_body(self.carry, 'CarryShared'))
        # ("used" N: the boost flags used0-52 - ResetUsed declares each)
        names = [n for n in names if n != 'used'] + ['used%d' % i for i in range(53)]
        undeclared = [n for n in names if n.lower() not in declared]
        self.assertEqual(undeclared, [])


class MainClient(unittest.TestCase):
    # (the places that look at every client, or at the window you pressed a key in, as they should)
    ALLOWED = {
        'Autofarmer.ahk': ['GameTrayAltF4', 'GameTrayNo'],
        'Carry.ahk': ['CarryGameWins', 'CarryStart', 'HkMain', 'GameWT'],
        'Vision.ahk': ['VisionGameClients'],
        'Walker.ahk': ['WkGameWT'],
    }

    def test_windows_found_by_gamewt(self):
        bad = []
        for d in (AF, os.path.join(ROOT, 'AutoQuester')):
            for fn in os.listdir(d):
                # (the stats reader and the quester alone are programs of their own - one client)
                if not fn.lower().endswith('.ahk') or fn in ('StatsReader.ahk', 'AutoQuester.ahk'):
                    continue
                func = ''
                for i, line in enumerate(read(os.path.join(d, fn)).split('\n'), 1):
                    m = re.match(r'^([A-Za-z_]\w*)\(.*\)\s*$', line)
                    if m:
                        func = m.group(1)
                    if '"ahk_class " GameClass' in line.split(';')[0] and func not in self.ALLOWED.get(fn, []):
                        bad.append('%s:%d %s' % (fn, i, func))
        self.assertEqual(bad, [])

    def test_reconnect_closes_only_the_picked_client(self):
        rc = read(os.path.join(AF, 'Reconnect.ahk'))
        self.assertNotIn('ProcessExist(GameExe)', rc)
        body = func_body(rc, 'RcCloseGame')
        self.assertNotIn('ProcessClose(GameExe)', body)
        self.assertIn('GamePid()', body)


if __name__ == '__main__':
    unittest.main()
