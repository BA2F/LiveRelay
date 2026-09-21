from __future__ import annotations

import tkinter.messagebox as messagebox
from pathlib import Path
from typing import Dict, List

import customtkinter as ctk

# Use absolute imports so running as a script or frozen EXE works without package context.
from diceware_cn.core import entropy_bits, generate_passphrase
from diceware_cn.wordlist import (
    DEFAULT_WORDLIST_NAME,
    WordEntry,
    available_wordlists,
    load_wordlist,
)


class DicewareApp(ctk.CTk):
    def __init__(self) -> None:
        super().__init__()
        self.title("拼音/五笔 密码生成器")
        self.geometry("520x520")

        ctk.set_appearance_mode("light")

        self.wordlist_paths = self._discover_wordlists()
        self.wordlist_cache: Dict[Path, List[WordEntry]] = {}

        # Controls
        self.wordlist_var = ctk.StringVar(value=self._default_wordlist_name())
        self.count_var = ctk.IntVar(value=6)
        self.sep_var = ctk.StringVar(value="")  # actual separator used
        self.sep_choice_var = ctk.StringVar(value="(无)")  # displayed choice
        self.allow_repeat_var = ctk.BooleanVar(value=False)
        self.entropy_var = ctk.StringVar(value="")

        self._build_layout()
        self._update_entropy_label()

    def _discover_wordlists(self) -> Dict[str, Path]:
        found = available_wordlists()
        if not found:
            messagebox.showerror("错误", "未找到任何词表文件。")
            raise SystemExit(1)
        return {p.name: p for p in found}

    def _default_wordlist_name(self) -> str:
        if DEFAULT_WORDLIST_NAME in self.wordlist_paths:
            return DEFAULT_WORDLIST_NAME
        # Fallback to the first available file.
        return next(iter(self.wordlist_paths))

    def _build_layout(self) -> None:
        self.grid_columnconfigure(0, weight=1)
        self.grid_columnconfigure(1, weight=1)
        self.grid_columnconfigure(2, weight=1)

        # Wordlist selector
        ctk.CTkLabel(self, text="词表:").grid(
            row=0, column=0, padx=12, pady=(12, 6), sticky="e"
        )
        self.wordlist_menu = ctk.CTkOptionMenu(
            self,
            values=list(self.wordlist_paths.keys()),
            variable=self.wordlist_var,
            command=lambda _: self._update_entropy_label(),
        )
        self.wordlist_menu.grid(row=0, column=1, padx=12, pady=(12, 6), sticky="w")

        # Count slider
        ctk.CTkLabel(self, text="词语个数:").grid(
            row=1, column=0, padx=12, pady=6, sticky="e"
        )
        self.count_slider = ctk.CTkSlider(
            self,
            from_=4,
            to=12,
            number_of_steps=8,
            variable=self.count_var,
            command=lambda _: self._update_entropy_label(),
        )
        self.count_slider.grid(row=1, column=1, padx=12, pady=6, sticky="ew")
        self.count_entry = ctk.CTkEntry(self, width=50, textvariable=self.count_var)
        self.count_entry.grid(row=1, column=2, padx=12, pady=6, sticky="w")

        # Separator selection
        ctk.CTkLabel(self, text="分隔符:").grid(
            row=2, column=0, padx=12, pady=6, sticky="e"
        )
        self.sep_menu = ctk.CTkOptionMenu(
            self,
            values=["(无)", "空格", "连字符"],
            variable=self.sep_choice_var,
            command=self._on_sep_change,
        )
        self.sep_menu.grid(row=2, column=1, padx=12, pady=6, sticky="w")

        # Repeat checkbox
        self.repeat_checkbox = ctk.CTkCheckBox(
            self,
            text="允许重复（默认禁用）",
            variable=self.allow_repeat_var,
        )
        self.repeat_checkbox.grid(row=3, column=1, padx=12, pady=6, sticky="w")

        # Generate button
        self.generate_button = ctk.CTkButton(
            self, text="生成密码", command=self._on_generate
        )
        self.generate_button.grid(row=4, column=0, columnspan=3, padx=12, pady=12)

        # Output textbox
        self.output_font = ctk.CTkFont(size=16)
        self.output = ctk.CTkTextbox(self, height=200, font=self.output_font)
        self.output.grid(row=5, column=0, columnspan=3, padx=12, pady=12, sticky="nsew")
        self.grid_rowconfigure(5, weight=1)

        # Entropy label
        self.entropy_label = ctk.CTkLabel(
            self, textvariable=self.entropy_var, anchor="center", justify="center"
        )
        self.entropy_label.grid(row=6, column=0, columnspan=3, padx=12, pady=(0, 12))

    def _on_sep_change(self, choice: str) -> None:
        if choice == "空格":
            self.sep_var.set(" ")
        elif choice == "连字符":
            self.sep_var.set("-")
        else:
            self.sep_var.set("")

    def _update_entropy_label(self) -> None:
        try:
            count = int(self.count_var.get())
        except (TypeError, ValueError):
            return
        name = self.wordlist_var.get()
        path = self.wordlist_paths.get(name)
        if not path:
            return
        try:
            entries = self._get_wordlist(path)
        except Exception:
            return
        bits = entropy_bits(count, len(entries))
        self.entropy_var.set(f"密码强度: {bits:.1f} bits")

    def _get_wordlist(self, path: Path) -> List[WordEntry]:
        if path not in self.wordlist_cache:
            self.wordlist_cache[path] = load_wordlist(path)
        return self.wordlist_cache[path]

    def _on_generate(self) -> None:
        try:
            count = int(self.count_var.get())
        except (TypeError, ValueError):
            messagebox.showerror("错误", "词语个数请输入数字。")
            return

        path = self.wordlist_paths.get(self.wordlist_var.get())
        if not path:
            messagebox.showerror("错误", "未找到所选词表文件。")
            return

        try:
            entries = self._get_wordlist(path)
            phrase = generate_passphrase(
                entries=entries,
                count=count,
                allow_repeat=self.allow_repeat_var.get(),
            )
        except Exception as exc:  # noqa: BLE001
            messagebox.showerror("错误", str(exc))
            return

        custom_sep = self.sep_var.get()
        roman_spaced = " ".join(phrase.keys)
        chinese_spaced = " ".join(phrase.words)
        roman_nosep = "".join(phrase.keys)
        roman_hyphen = "-".join(phrase.keys)
        chinese_hyphen = "-".join(phrase.words)

        lines = [
            roman_spaced,
            chinese_spaced,
            roman_nosep,
            roman_hyphen,
            chinese_hyphen,
        ]

        if custom_sep:
            lines.insert(3, custom_sep.join(phrase.keys))

        self.output.configure(state="normal")
        self.output.delete("1.0", "end")
        self.output.insert("1.0", "\n".join(lines))
        self.output.tag_config("center", justify="center")
        self.output.tag_add("center", "1.0", "end")
        self.output.configure(state="disabled")
        bits = entropy_bits(count, len(entries))
        self.entropy_var.set(f"密码强度: {bits:.1f} bits")


def main() -> None:
    app = DicewareApp()
    app.mainloop()


if __name__ == "__main__":
    main()
