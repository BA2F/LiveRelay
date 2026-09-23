# LifeVault 总体设计

> 状态：已确认  
> 版本：0.5  
> 最后更新：2026-09-23  
> 依赖文档：security/00_安全设计总览.md, data/00_数据架构总览.md


## 当前定义

LifeVault 由以下部分组成：

- 加密 SQLite：结构化数据与 Blob 索引；
- 加密 Blob：照片、PDF、音频、视频；
- 必要的格式/密码元数据；
- 单体导出封装。

Vault Core 不理解 Asset、Relationship、Death 等业务语义。

## MVP 运行时结构

采用目录式运行：

```text
vault-header.json
vault.sqlite
blobs/<uuid>.blob
```

`vault-header.json` 包含格式/KDF 参数和被封装的 VMK，不含主密码或明文 VMK。`vault.sqlite` 是 SQLCipher 数据库；Blob 文件名为随机 ID，真实名称和索引只在加密数据库中。

当前边界：

- 数据库和 Blob 支持增量操作；
- 单个 Blob 限制 256 MB，当前不是流式加密；
- 运行时 sidecar 文件不进入导出容器。

## 导出方向

用户导出单个 `.lvault`。MVP 格式版本为 1，外层是无压缩 ZIP 容器：

```text
container.json
manifest.json
manifest.mac
vault/vault-header.json
vault/vault.sqlite
vault/blobs/...
```

内部数据库和 Blob 本身已经加密；外层不重复加密。`manifest.json` 记录每项大小和 SHA-256，`manifest.mac` 使用由 VMK 经 HKDF 派生的 HMAC-SHA256 认证整个清单。容器格式、版本、创建时间、文件数量/大小等外层元数据不是秘密。

格式必须：

- 开放；
- 可版本化；
- 可迁移；
- 能脱离原 App 恢复。

## 当前开放问题

- Blob 和 `.lvault` 的大文件流式格式；
- 独立恢复工具和格式规范发布；
- 外层元数据最小化是否值得引入第二层加密；
- 未来格式升级、局部损坏恢复和跨平台兼容样本。

## 历史来源

- `docs/05_security/03_LifeVault总体设计.md`
- `docs/05_security/04_LifeVault运行时结构.md`
- `docs/05_security/05_LifeVault导出格式.md`
- `docs/05_security/16_大文件流式加密.md`
