from pathlib import Path
root=Path(__file__).resolve().parents[1]
errors=[]
for p in root.rglob("*.md"):
    if p.name in {"README.md","AGENTS.md","SKILL.md"}: continue
    if not any("\u4e00" <= ch <= "\u9fff" for ch in p.name): errors.append(str(p))
if errors:
    print("以下自定义 Markdown 文件名未包含中文：")
    print("\n".join(errors))
    raise SystemExit(1)
print("Markdown 命名基础检查通过。")
