from __future__ import annotations

from dataclasses import dataclass
from importlib import resources
from pathlib import Path
from typing import Iterable, List, Sequence

DEFAULT_WORDLIST_NAME = "new-default-pinyin.wordlist"
KNOWN_WORDLISTS = [
    "new-default-pinyin.wordlist",
    "pinyin.wordlist",
    "pinyin8k.wordlist",
    "wubi.wordlist",
    "wubi8k.wordlist",
]


@dataclass(frozen=True)
class WordEntry:
    key: str
    word: str


def resolve_wordlist_path(name_or_path: str | Path) -> Path:
    path = Path(name_or_path)
    if path.exists():
        return path

    # Try relative to common roots: CWD and this file's parent chain.
    for base in [Path.cwd(), *Path(__file__).resolve().parents]:
        candidate = base / path
        if candidate.exists():
            return candidate

    # Try packaged data (works for installed package / PyInstaller)
    data_pkg = "diceware_cn.data"
    try:
        data_root = resources.files(data_pkg)
        candidate = data_root / str(path.name)
        if candidate.is_file():
            with resources.as_file(candidate) as extracted:
                return extracted
    except ModuleNotFoundError:
        pass

    raise FileNotFoundError(f"Wordlist not found: {name_or_path}")


def load_wordlist(path: str | Path) -> List[WordEntry]:
    p = resolve_wordlist_path(path)
    entries: List[WordEntry] = []
    with p.open("r", encoding="utf-8-sig") as fh:
        for line in fh:
            stripped = line.strip()
            if not stripped:
                continue
            parts = stripped.split()
            if len(parts) == 1:
                key = parts[0]
                word = parts[0]
            else:
                key = parts[0]
                word = parts[-1]
            entries.append(WordEntry(key=key, word=word))

    if not entries:
        raise ValueError(f"Wordlist is empty: {p}")
    return entries


def available_wordlists(names: Sequence[str] = KNOWN_WORDLISTS) -> List[Path]:
    """Return paths for wordlists that exist among the provided names."""
    found: List[Path] = []
    for name in names:
        try:
            found.append(resolve_wordlist_path(name))
        except FileNotFoundError:
            continue
    return found
