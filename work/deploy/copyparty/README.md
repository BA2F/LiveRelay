# LiveRelay 云端 WebDAV 云盘（copyparty）

> 状态：部署资产与实测说明；App 内"连接 WebDAV"页尚未开始
> 日期：2026-10-14
> 依赖：Docker 与 Docker Compose；云服务模式另需一个指向服务器的域名

这份目录把 [copyparty](https://github.com/9001/copyparty)（MIT，单文件 Python 服务端）配置成 LiveRelay 的云端介质：手机的采集包、桌面的整理结果都通过它往来，App 把 WebDAV 挂载目录或直连地址当普通介质目录使用。

两种模式，同一套软件：

| | 自建（1:1） | 云服务（1:N） |
| --- | --- | --- |
| 场景 | 自己一台小服务器/家里 NAS，只有本人用 | 公网服务，多个客户各用各的空间 |
| 目录 | `selfhost/` | `cloud/` |
| 端口 | 3923 直接对外（局域网内 HTTP） | 只绑 127.0.0.1，对外由 Caddy 出 HTTPS |
| 账号 | 一个 `owner` | `owner`（管理员）+ 每客户一个账号 |

资源占用：copyparty 本身很轻，2C2G 的机器足够；compose 里给了 512MB 内存上限兜底。

## 自建（1:1）部署

```bash
cd selfhost
# 1. 改密码：编辑 copyparty.conf 里的 owner 密码，然后把权限收紧
$EDITOR copyparty.conf && chmod 600 copyparty.conf
# 2. 启动
docker compose up -d
```

浏览器打开 `http://<服务器IP>:3923/`，用 owner 登录；管理面板在 `http://<服务器IP>:3923/?h`。之后所有数据都在 `selfhost/data/` 目录里。

## 云服务（1:N）部署

```bash
cd cloud
# 1. 改管理员密码与域名
$EDITOR copyparty.conf        # owner 密码；并把 [global] 里 xff-src、rp-loc 的注释打开改成实际值
$EDITOR Caddyfile             # drive.example.com 换成你的域名
chmod 600 copyparty.conf
# 2. 启动
docker compose up -d
```

Caddy 会自动为域名申请 HTTPS 证书（需要 80/443 可从公网访问、域名 A 记录已指向本机）。

每加一个客户：

```bash
mkdir -p data/users/新客户名
# 在 copyparty.conf 里复制 [alice] 那段 6 行，把 alice 全部替换成新客户名
docker compose restart copyparty     # 或管理员在管理面板点 [reload cfg]
```

然后把两样东西给客户：网址 `https://drive.example.com/新客户名/`、账号密码——正好就是 App 连接页要填的三项。

## 本机验证记录（2026-10-14，copyparty v1.20.25 直跑实测）

用同一个 `cloud/copyparty.conf` 的结构在 127.0.0.1 上真跑，用 curl 逐项验证：

- 配置格式（[global]/[accounts]/[groups]/[/路径]+accs+flags、注释前两个空格）解析正确，权限 `rwmd`、`A` 展开符合预期；
- 卷里引用的账号没在 [accounts] 里定义时，服务拒绝启动并报出缺谁——加客户漏改账号时这一步就会拦住；
- WebDAV：PROPFIND 列目录（含文件长度）、PUT 新建（201）、**PUT 同名覆写**（卷标志 `daw`，内容整文件替换）、MOVE 改名、**MOVE 覆盖已存在目标**（`Overwrite: T`，201，目标被替换）、Range 断点下载（206）；
- 客户隔离：alice 的 PROPFIND 根目录只出现 `/alice/`，访问 `/bob/` 得 403；
- 密码错误返回 403（不是 401；客户端两种都应当认作认证失败）；
- 管理面板：浏览器打开 `/?h` 正常渲染（curl 不带浏览器 UA 时只回文本摘要）；
- 密码防爆破为默认开启（一小时 9 次失败封 24 小时，按真实客户端 IP，所以反代接入必须配 `xff-src`）。

## 注意事项

- **数据别放在内存盘上**：数据目录若落在 tmpfs，copyparty 会直接剥掉写入权限（防止误以为已落盘）；本机测试时用 `--wram` 才能写。生产把 `data/` 放在真实磁盘。
- **`daw` 卷标志的含义**：普通模式上传同名文件会被改名保全（`名字-时间-随机.txt`），打开 `daw` 后 PUT 同名直接覆写。LiveRelay 靠它实现"数据库包每趟覆写"，因此客户卷带 `daw`，且客户对自己卷有删除权（编辑既有文件也需要删除权）。介质的原件卷只增不改，不受影响。
- **备份**：全部数据就是 `data/` 目录（里面是加密后的 .lvault 包，服务器看不到明文），直接拷贝即可；连同 `copyparty.conf` 一起备份。
- **升级**：改 compose 里的镜像版本号后 `docker compose up -d`。
- **不用 Docker** 也可以：`pip install copyparty` 后 `copyparty -c copyparty.conf`，或直接下单个 sfx 文件跑。

## 未验证与后续

- 本机没有 Docker，`compose.yml` 与 Caddy 配置**没有实跑过**（跑过的是等价的 pip 直跑实例）；服务器主首次部署时按上面步骤走一遍即可确认。
- 镜像版本钉在 `copyparty/ac:1.20.25`（本机验证所用版本）；若拉取失败改成 `:latest`。
- App 内"连接 WebDAV"页（填网址＋账号＋密码，手机端没有系统挂载 WebDAV 的能力，这页是手机走云端的必需件）是下一步；在那之前，手机可以用浏览器页面存取，桌面可以用系统挂载。
- 断点续传：介质的原件卷本身是分文件小块，传失败重跑只补缺失文件；浏览器页面用 copyparty 自带的可续传上传器。App 直连后按同样的分卷+文件级跳过策略，不依赖服务器扩展。
