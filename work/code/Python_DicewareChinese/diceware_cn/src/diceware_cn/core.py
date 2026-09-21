from __future__ import annotations

import math
import secrets
from dataclasses import dataclass
from typing import Iterable, List, Sequence

from .wordlist import WordEntry


@dataclass(frozen=True)
class Passphrase:
    keys: List[str]
    words: List[str]

    def join_keys(self, sep: str = "") -> str:
        return sep.join(self.keys)

    def join_words(self, sep: str = "") -> str:
        return sep.join(self.words)


def entropy_bits(word_count: int, wordlist_size: int) -> float:
    if word_count <= 0:
        raise ValueError("word_count must be positive")
    if wordlist_size <= 0:
        raise ValueError("wordlist_size must be positive")
    return word_count * math.log2(wordlist_size)


def _sample_indices(size: int, count: int, allow_repeat: bool) -> List[int]:
    if count <= 0:
        raise ValueError("count must be positive")
    if size <= 0:
        raise ValueError("wordlist size must be positive")

    if allow_repeat:
        return [secrets.randbelow(size) for _ in range(count)]

    if count > size:
        raise ValueError(
            f"Requested {count} unique words but wordlist only has {size} entries"
        )

    pool = list(range(size))
    selected: List[int] = []
    for i in range(count):
        j = secrets.randbelow(size - i)
        pool_index = j
        chosen = pool[pool_index]
        # Move the last unused element into the chosen slot to avoid O(n^2) removals.
        pool[pool_index], pool[size - 1 - i] = pool[size - 1 - i], pool[pool_index]
        selected.append(chosen)
    return selected


def generate_passphrase(
    entries: Sequence[WordEntry],
    count: int,
    allow_repeat: bool = False,
) -> Passphrase:
    indices = _sample_indices(len(entries), count, allow_repeat)
    keys = [entries[i].key for i in indices]
    words = [entries[i].word for i in indices]
    return Passphrase(keys=keys, words=words)
