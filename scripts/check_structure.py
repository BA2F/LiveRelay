from pathlib import Path

root = Path(__file__).resolve().parents[1]
required = [
    "README.md",
    "AGENTS.md",
    "docs/00_governance",
    "docs/10_overview",
    "docs/20_product",
    "docs/30_design",
    "docs/40_modules/00_模块索引.md",
    "docs/50_interfaces/00_接口总览.md",
    "records/adr",
    "memory/当前项目上下文.md",
    "tasks/看板.md",
    "work",
    "archive/workspace-template",
]
missing = [x for x in required if not (root / x).exists()]
if missing:
    print("缺少必要路径：")
    for x in missing:
        print("-", x)
    raise SystemExit(1)

# Anti-placeholder check in active execution layers.
bad = []
for base in ["docs/40_modules", "docs/50_interfaces"]:
    for p in (root / base).rglob("*.md"):
        text = p.read_text(encoding="utf-8", errors="ignore")
        if "本文件将在对应模块专题会话中完成" in text:
            bad.append(str(p.relative_to(root)))

if bad:
    print("发现活跃执行层占位文档：")
    for x in bad:
        print("-", x)
    raise SystemExit(2)

print("核心结构与占位检查通过。")
