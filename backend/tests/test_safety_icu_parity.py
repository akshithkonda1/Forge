"""guidance.py under ICU regex semantics — the engine NSRegularExpression uses.

The phone decides 911 / triage turns offline with the same patterns
(``scripts/generate_aria_safety_swift.py`` copies them into ForgeCore). Python
``re`` and ICU mostly agree, but "mostly" is not good enough on a 911 turn, and
the macOS job that runs ``swift test`` is ten minutes away. This test swaps every
compiled pattern in ``guidance`` for an ICU-backed one (``libicui18n`` via
ctypes) and re-runs the whole shared corpus. Skipped where ICU is absent.
"""

from __future__ import annotations

import ctypes
import ctypes.util
import importlib.util
import json
import re
import unittest
from pathlib import Path

import _bootstrap  # noqa: F401

from services import guidance  # noqa: E402

REPO = Path(__file__).resolve().parents[2]
CORPUS = json.loads((REPO / "shared" / "aria-safety-corpus.json").read_text())


def _load_generator():
    spec = importlib.util.spec_from_file_location(
        "generate_aria_safety_swift", REPO / "scripts" / "generate_aria_safety_swift.py"
    )
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def _icu_candidates() -> list[str]:
    """find_library needs the -dev symlink; runtime images only ship .so.NN."""
    names: list[str] = []
    found = ctypes.util.find_library("icui18n")
    if found:
        names.append(found)
    for folder in ("/usr/lib/x86_64-linux-gnu", "/usr/lib/aarch64-linux-gnu", "/usr/lib", "/usr/local/lib"):
        base = Path(folder)
        if base.is_dir():
            names.extend(sorted((str(p) for p in base.glob("libicui18n.so.*")), reverse=True))
    return names


def _load_icu():
    for name in _icu_candidates():
        try:
            lib = ctypes.CDLL(name)
        except OSError:
            continue
        match = re.search(r"\.so\.(\d+)", name) or re.search(r"(\d+)", Path(name).name)
        suffixes = [""] + ([f"_{match.group(1)}"] if match else [])
        for suffix in suffixes:
            if hasattr(lib, f"uregex_open{suffix}"):
                return lib, suffix
    return None


class _ICU:
    def __init__(self, lib, suffix: str):
        def fn(name, restype, *args):
            f = getattr(lib, f"{name}{suffix}")
            f.restype = restype
            f.argtypes = list(args)
            return f

        status = ctypes.POINTER(ctypes.c_int)
        self.open = fn("uregex_open", ctypes.c_void_p, ctypes.c_void_p, ctypes.c_int32,
                       ctypes.c_uint32, ctypes.c_void_p, status)
        self.set_text = fn("uregex_setText", None, ctypes.c_void_p, ctypes.c_void_p,
                           ctypes.c_int32, status)
        self.find = fn("uregex_find", ctypes.c_byte, ctypes.c_void_p, ctypes.c_int32, status)
        self.find_next = fn("uregex_findNext", ctypes.c_byte, ctypes.c_void_p, status)
        self.start = fn("uregex_start", ctypes.c_int32, ctypes.c_void_p, ctypes.c_int32, status)
        self.end = fn("uregex_end", ctypes.c_int32, ctypes.c_void_p, ctypes.c_int32, status)
        self.close = fn("uregex_close", None, ctypes.c_void_p)


def _utf16(text: str):
    raw = text.encode("utf-16-le")
    return ctypes.create_string_buffer(raw, len(raw) + 2), len(raw) // 2


class _Match:
    def __init__(self, text: str, start16: int, end16: int):
        encoded = text.encode("utf-16-le")
        self._start = len(encoded[: start16 * 2].decode("utf-16-le"))
        self._end = len(encoded[: end16 * 2].decode("utf-16-le"))

    def start(self) -> int:
        return self._start

    def end(self) -> int:
        return self._end


class _ICURegex:
    """The slice of ``re.Pattern`` guidance.py uses, backed by ICU."""

    def __init__(self, icu: _ICU, source: str):
        self._icu = icu
        self.pattern = source
        self._buf, length = _utf16(source)
        status = ctypes.c_int(0)
        self._rx = icu.open(self._buf, length, 0, ctypes.byref((ctypes.c_byte * 64)()),
                            ctypes.byref(status))
        if status.value > 0 or not self._rx:
            raise ValueError(f"ICU cannot compile {source!r} (status {status.value})")

    def __del__(self):
        if getattr(self, "_rx", None):
            self._icu.close(self._rx)

    def finditer(self, text: str):
        buf, length = _utf16(text)
        status = ctypes.c_int(0)
        self._icu.set_text(self._rx, buf, length, ctypes.byref(status))
        found = self._icu.find(self._rx, 0, ctypes.byref(status))
        out = []
        while found:
            out.append(_Match(
                text,
                self._icu.start(self._rx, 0, ctypes.byref(status)),
                self._icu.end(self._rx, 0, ctypes.byref(status)),
            ))
            found = self._icu.find_next(self._rx, ctypes.byref(status))
        return out

    def search(self, text: str):
        matches = self.finditer(text)
        return matches[0] if matches else None

    def split(self, text: str):
        out, last = [], 0
        for match in self.finditer(text):
            out.append(text[last:match.start()])
            last = match.end()
        out.append(text[last:])
        return out


def _row(assessed):
    if assessed is None:
        return {"band": guidance.COACH}
    out = {"band": assessed.band, "prose": assessed.prose}
    if assessed.safety:
        out.update({k: assessed.safety[k] for k in ("phase", "topic", "subject", "voice")})
        if assessed.safety.get("reply_topic"):
            out["reply_topic"] = assessed.safety["reply_topic"]
    return out


class ICUParityTests(unittest.TestCase):
    def setUp(self):
        loaded = _load_icu()
        if loaded is None:
            self.skipTest("libicui18n not available")
        self.icu = _ICU(*loaded)
        self.gen = _load_generator()
        self._saved: dict[str, object] = {}

    def tearDown(self):
        for name, value in getattr(self, "_saved", {}).items():
            setattr(guidance, name, value)

    def _swap(self, name: str, value) -> None:
        self._saved.setdefault(name, getattr(guidance, name))
        setattr(guidance, name, value)

    def _swap_all(self) -> int:
        count = 0
        for name in dir(guidance):
            obj = getattr(guidance, name)
            if isinstance(obj, re.Pattern):
                self._swap(name, _ICURegex(self.icu, self.gen.pattern_source(obj)))
                count += 1
        self._swap("_STROKE_DOMAINS", tuple(
            _ICURegex(self.icu, self.gen.pattern_source(p)) for p in guidance._STROKE_DOMAINS
        ))
        self._swap("_TRIAGE_DANGER", {
            k: _ICURegex(self.icu, self.gen.pattern_source(p))
            for k, p in guidance._TRIAGE_DANGER.items()
        })
        icu = self.icu

        def has_word(text, needles):
            pattern = r"\b(?:" + "|".join(re.escape(n) for n in needles) + r")\b"
            return bool(_ICURegex(icu, pattern).search(text))

        self._swap("_has_word", has_word)
        return count

    def test_every_pattern_compiles_in_icu(self):
        self.assertGreater(self._swap_all(), 20)

    def test_shared_corpus_is_identical_under_icu(self):
        self._swap_all()
        for row in CORPUS["turns"]:
            with self.subTest(text=row["text"]):
                want = {k: v for k, v in row.items() if k != "text"}
                self.assertEqual(_row(guidance.assess(row["text"])), want)
        for row in CORPUS["answers"]:
            with self.subTest(topic=row["reply_topic"], text=row["text"]):
                want = {k: v for k, v in row.items() if k not in ("text", "reply_topic")}
                self.assertEqual(
                    _row(guidance.assess(row["text"], triage_topic=row["reply_topic"])), want
                )

    def test_harness_is_not_vacuous(self):
        self._swap_all()
        self._swap("_CHOKING_RE", _ICURegex(self.icu, "never-matches-zzz"))
        self.assertEqual(guidance.classify_band("he's choking"), guidance.COACH)


if __name__ == "__main__":
    unittest.main()
