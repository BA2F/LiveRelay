# Diceware Chinese

Secure diceware-style passphrase generator for Chinese wordlists (拼音/五笔), built with a core library, CLI, and customtkinter GUI. Defaults to the bundled `new-default-pinyin.wordlist`, uses system CSPRNG, and forbids repeats by default.

## Setup
```bash
uv sync
```

## CLI
```bash
# generate (default: 6 words, no separator)
uv run diceware-cn --count 6

# choose wordlist and custom separator (space | - | '')
uv run diceware-cn --wordlist ../wubi8k.wordlist --sep "-"

# allow repeats (off by default)
uv run diceware-cn --allow-repeat

# list detected wordlists
uv run diceware-cn --list-wordlists
```

## GUI
```bash
uv run diceware-cn-gui
```
