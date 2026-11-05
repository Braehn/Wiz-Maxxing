"""test_vision_start.py - the vision helper says in vision.log why it stops at start (pythonw has no console, and
AutoFarmer's VisionStart puts that line in debug.log): numpy or Pillow missing, an error before it serves, its port
taken. Each runs vision.py as the bot does, in a Python of its own, its log in a temp file (WIZ_VISION_LOG) - no
Windows:  python3 -m unittest test_vision_start   (from AutoFarmer\\vision)"""
import ast
import importlib.util
import os
import re
import socket
import subprocess
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
VISION = os.path.join(HERE, 'vision.py')
HAVE_NP = all(importlib.util.find_spec(m) is not None for m in ('numpy', 'PIL'))


def run_vision(code, log_path):
    """code run in a new Python (vision.py run as __main__ by it), its vision.log at log_path: (exit code, the log's
    lines without their time)"""
    env = dict(os.environ, WIZ_VISION_LOG=log_path)
    r = subprocess.run([sys.executable, '-c', code], cwd=HERE, env=env, capture_output=True, text=True, timeout=120)
    lines = []
    if os.path.exists(log_path):
        with open(log_path, encoding='utf-8') as f:
            lines = [ln.rstrip('\n') for ln in f]
    for ln in lines:
        assert re.match(r'\d\d:\d\d:\d\d ', ln), ln
    return r.returncode, [ln[9:] for ln in lines]


def as_main(before='', args=('--port', '0')):
    """the code for run_vision: before, then vision.py with args as if started by the bot"""
    return (f'import runpy, sys\n{before}\nsys.argv = [{VISION!r}] + {list(args)!r}\n'
            f'runpy.run_path({VISION!r}, run_name="__main__")\n')


class LogFirst(unittest.TestCase):
    """log is there before numpy and Pillow are imported"""

    def test_log_made_before_numpy_import(self):
        with open(VISION, encoding='utf-8') as f:
            tree = ast.parse(f.read())

        def first(test):
            return next((i for i, node in enumerate(tree.body) if any(test(n) for n in ast.walk(node))), None)

        imports_np = first(lambda n: isinstance(n, ast.Import) and any(a.name == 'numpy' for a in n.names))
        imports_pil = first(lambda n: isinstance(n, ast.ImportFrom) and n.module == 'PIL')
        log_def = first(lambda n: isinstance(n, ast.FunctionDef) and n.name == 'log')
        log_path = first(lambda n: isinstance(n, ast.Assign) and any(isinstance(t, ast.Name) and t.id == 'LOG'
                                                                    for t in n.targets))
        self.assertIsNotNone(imports_np)
        self.assertIsNotNone(imports_pil)
        self.assertIsNotNone(log_def)
        self.assertIsNotNone(log_path)
        self.assertLess(log_def, min(imports_np, imports_pil))
        self.assertLess(log_path, min(imports_np, imports_pil))


class WhyItStops(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.log = os.path.join(self.tmp.name, 'vision.log')

    def tearDown(self):
        self.tmp.cleanup()

    def test_numpy_or_pillow_missing(self):
        for missing in ('numpy', 'PIL'):
            with self.subTest(missing=missing):
                if missing == 'PIL' and not HAVE_NP:
                    self.skipTest('no numpy here: the PIL import is never reached')
                if os.path.exists(self.log):
                    os.remove(self.log)
                code, lines = run_vision(as_main(f'sys.modules[{missing!r}] = None'), self.log)
                self.assertNotEqual(code, 0)
                self.assertEqual(len(lines), 1, lines)
                line = lines[0]
                self.assertTrue(line.startswith("can't start: numpy and Pillow didn't load in Python "), line)
                self.assertIn(sys.version.split()[0], line)
                self.assertIn(sys.executable, line)
                self.assertRegex(line, rf'\(ModuleNotFoundError: [^()]*\b{missing}\b[^()]*\) - ')
                self.assertIn('Setup.exe\'s "numpy and Pillow" installs them', line)

    @unittest.skipUnless(HAVE_NP, 'needs numpy and Pillow')
    def test_error_before_serving(self):
        boom = ('import http.server\n'
                'class Boom(http.server.ThreadingHTTPServer):\n'
                '    def __init__(self, *a, **kw):\n'
                '        raise RuntimeError("no server today")\n'
                'http.server.ThreadingHTTPServer = Boom')
        code, lines = run_vision(as_main(boom), self.log)
        self.assertNotEqual(code, 0)
        self.assertTrue(lines, 'nothing in vision.log')
        self.assertRegex(lines[-1], r"^can't start: RuntimeError: no server today - in __init__ \(<string>:\d+\) "
                                    r"<- main \(vision\.py:\d+\)")
        self.assertFalse([ln for ln in lines if ln.startswith('started')], lines)

    @unittest.skipUnless(HAVE_NP, 'needs numpy and Pillow')
    def test_port_taken(self):
        with socket.socket() as s:
            s.bind(('127.0.0.1', 0))
            s.listen(1)
            port = s.getsockname()[1]
            code, lines = run_vision(as_main(args=('--port', str(port))), self.log)
        self.assertEqual(code, 0)
        self.assertTrue(lines, 'nothing in vision.log')
        self.assertRegex(lines[-1], rf'^port {port} taken \(.+\) - another copy is running$')


if __name__ == '__main__':
    unittest.main()
