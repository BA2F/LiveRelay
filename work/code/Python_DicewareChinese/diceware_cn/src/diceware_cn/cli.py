from __future__ import annotations

import argparse
import sys
from typing import List

from .core import entropy_bits, generate_passphrase
from .wordlist import DEFAULT_WORDLIST_NAME, available_wordlists, load_wordlist


def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Chinese Diceware passphrase generator (secure RNG, no repeats by default)."
    )
    parser.add_argument(
        "-c",
        "--count",
        type=int,
        default=6,
        help="number of words (default: 6)",
    )
    parser.add_argument(
        "-l",
        "--wordlist",
        default=DEFAULT_WORDLIST_NAME,
        help=f"wordlist file (default: {DEFAULT_WORDLIST_NAME})",
    )
    parser.add_argument(
        "--allow-repeat",
        action="store_true",
        help="allow repeated words (default: off)",
    )
    parser.add_argument(
        "--sep",
        default="",
        help="custom separator for the primary line (default: '')",
    )
    parser.add_argument(
        "--list-wordlists",
        action="store_true",
        help="list available wordlists and exit",
    )
    return parser


def _format_output(keys: List[str], words: List[str], custom_sep: str) -> str:
    roman_primary = custom_sep.join(keys)
    chinese_primary = (
        custom_sep.join(words) if custom_sep else " ".join(words)
    )
    roman_nosep = "".join(keys)
    roman_spaced = " ".join(keys)
    chinese_spaced = " ".join(words)
    roman_hyphen = "-".join(keys)
    chinese_hyphen = "-".join(words)

    lines = [
        roman_primary,
        chinese_primary,
    ]

    if custom_sep:
        lines.append(roman_nosep)

    lines.extend(
        [
            roman_spaced,
            chinese_spaced,
            roman_hyphen,
            chinese_hyphen,
        ]
    )
    return "\n".join(lines)


def main(argv: list[str] | None = None) -> int:
    parser = _build_parser()
    args = parser.parse_args(argv)

    if args.list_wordlists:
        found = available_wordlists()
        if not found:
            print("No known wordlists found.", file=sys.stderr)
            return 1
        for path in found:
            print(path)
        return 0

    try:
        entries = load_wordlist(args.wordlist)
    except FileNotFoundError as exc:
        print(f"Error: {exc}", file=sys.stderr)
        return 1

    try:
        phrase = generate_passphrase(
            entries=entries, count=args.count, allow_repeat=args.allow_repeat
        )
    except ValueError as exc:
        print(f"Error: {exc}", file=sys.stderr)
        return 1

    bits = entropy_bits(args.count, len(entries))
    print(_format_output(phrase.keys, phrase.words, custom_sep=args.sep))
    print(f"\nEntropy: {bits:.1f} bits")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
