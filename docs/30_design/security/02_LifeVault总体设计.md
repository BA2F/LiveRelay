# LifeVault 总体设计

> 状态：讨论中  
> 版本：0.4  
> 最后更新：2026-09-06  
> 依赖文档：security/00_安全设计总览.md, data/00_数据架构总览.md


## 当前定义

LifeVault 由以下部分组成：

- 加密 SQLite：结构化数据与 Blob 索引；
- 加密 Blob：照片、PDF、音频、视频；
- 必要的格式/密码元数据；
- 单体导出封装。

Vault Core 不理解 Asset、Relationship、Death 等业务语义。

## 运行时方向

倾向目录式运行：

```text
encrypted database
encrypted blobs/
必要非敏感格式头
```

需要支持：

- 大文件；
- 流式处理；
- 增量操作。

## 导出方向

用户导出单个 `.lvault`。

内部数据库和 Blob 本身已经加密；外层可以进一步封装/整体认证以降低元数据泄露。

格式必须：

- 开放；
- 可版本化；
- 可迁移；
- 能脱离原 App 恢复。

## 当前开放问题

- `.lvault` 外层容器具体格式；
- 最小公开 Header；
- Manifest 是否独立加密；
- 完整性认证粒度；
- Blob 大文件流式格式。

## 历史来源

- `docs/05_security/03_LifeVault总体设计.md`
- `docs/05_security/04_LifeVault运行时结构.md`
- `docs/05_security/05_LifeVault导出格式.md`
- `docs/05_security/16_大文件流式加密.md`
