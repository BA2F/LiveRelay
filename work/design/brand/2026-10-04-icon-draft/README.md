# 留灯图案与动效草案

日期：2026-10-04。状态：独立设计草案，未确认品牌定稿，未接入应用。

## 母版与尺寸

参考为人类提供的 `ChatGPT生成7暂定稿.png`，仅依据图案人工重绘三条闭合贝塞尔路径：`left-shell`、`right-shell`、`flame`。母版不是原始设计源文件，也不是在 SVG 内嵌 PNG；已去掉背景纹理与文字。轮廓比例近似源图，颜色为本轮建议值，仍可微调。

- `svg/mark-master.svg`：透明背景，统一 `viewBox="0 0 512 512"`。
- `svg/mark-micro.svg`：供 16–24 逻辑像素使用；图案放大 15%，加宽灯芯、拉开右侧间隙、加深金色。它是光学校正版，不是等比缩小。
- `svg/mark-inverse.svg`、`mark-micro-inverse.svg`：深色背景上的反白双色版。
- `svg/mark-monochrome.svg`：单色版，中央灯芯仍为独立形状。
- `svg/sizes/`：16、24、32、48、64、128、256、512 的固定显示尺寸 SVG；均沿用相同 viewBox，16／24 使用小尺寸版。

通常只需母版和小尺寸版。SVG 的 `width`／`height` 控制显示大小；`viewBox` 保留统一坐标。`software/png/` 是平台需要位图时的导出，16／24 使用小尺寸版，其他使用母版；位图按实际像素生成，UI 的逻辑尺寸与显示密度仍需分别处理。

## 软件图标

图案母版与带底色的软件图标分别导出；背景建议为暖白 `#F8F5ED`。导出图标为完整方形，预览中的圆角由外部容器裁切，源文件没有预烘焙圆角／外围阴影。

| 资源 | 文件 | 当前状态 |
| --- | --- | --- |
| 方形软件图标 | `software/icon-square.svg`、`icon-square-dark.svg` | 已导出 |
| PNG | `software/png/icon-{16,24,32,48,64,128,256,512,1024}.png` | 已核对尺寸 |
| Android API 24–25 兼容 PNG | `software/android/res/mipmap-*/ic_launcher.png` | 48／72／96／144／192px |
| Android 自适应资源 | `software/android/res/drawable/`、`mipmap-anydpi-v26/`、`mipmap-anydpi-v33/` | XML 示例，未在 Android 构建或真机验证 |
| Windows | `software/windows/app_icon.ico` | 含 16／24／32／48／64／128／256 帧，已解码核对每帧 |
| Linux | `software/linux/hicolor/` | scalable SVG + 48／64／128／256 PNG |

Android 示例把图案缩放至中央安全区，前景和背景独立，并提供 monochrome 层。系统裁切示意使用相同缩放；实际启动器效果仍需真机核对。Google Play 商店图标可使用 512px 方形 PNG，但商店图标与 APK 自适应图标属于两种资源。Apple 平台的资产目录／Icon Composer／ICNS 未在本轮生成。

参考规范：[Android 自适应图标](https://developer.android.com/develop/ui/compose/system/icon_design_adaptive)、[Google Play 商店图标](https://developer.android.com/distribute/google-play/resources/icon-design-specifications)。

## 动效语言

| 状态 | 运动 | 草案节奏 | 业务触发 |
| --- | --- | --- | --- |
| 加载 | 金色灯芯轻微呼吸，两侧主体稳定 | 1800ms 循环 | 操作仍在进行；结束即停止，不代表百分比进度 |
| 完成 | 灯芯亮起、轻微回落到原尺寸 | 700ms 单次 | 真实操作成功后播放，停在完整图案 |
| 交接 | 光从左侧经过中央灯芯，传到右侧，再停稳 | 1600ms 单次 | 按真实阶段绑定；本地生成包不等于对方收到 |

`animations/*.svg` 为浏览器 SVG/CSS 演示；`preview.html` 提供播放／停止、重播、主题、小尺寸比较和减少动态开关。动效不是业务状态源；不能等动画播完就认定保存或交接成功。减少动态时保持静态图案，用可读状态文字表达结果。

其他动作可以延伸同一语言：解锁用灯芯由暗到亮，备份用一次向内收束的光，失败保持图案并提供原因与重试。它们是后续建议，本轮没有制作对应动画。

## Flutter 接入方向

LiveRelay 当前是 Flutter 单工程，未声明 `flutter_svg` 或独立动画播放器。建议三层使用 `CustomPainter` 绘制，通过 `AnimationController` 驱动灯芯的透明度、缩放和位移；只让相关区域重绘，页面不可见时停用 ticker，释放 controller，遵守系统减少动态设置。

静态 SVG 如需直接显示，可评估引入 SVG 渲染依赖；本轮未新增应用依赖。SVG/CSS 动画需要迁移为 Flutter 动画，不能直接交给 `Image.asset` 播放。三层路径和 timing 已记录在素材及 `manifest.json`。简单的三层动画可优先用 Flutter 原生绘制；有复杂骨骼、交互状态机等新增需求时再评估专用动画格式。

参考：[Flutter 动画 API](https://docs.flutter.dev/ui/animations/overview)。应用接入仍需各平台打包与运行验证，本轮没有替换 launcher／任务栏图标，也没有构建新应用包。

## 再生成

在本目录执行：

```sh
python3 build_assets.py
NODE_PATH=/home/tahzun/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules /home/tahzun/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/bin/node export_png.cjs
python3 package_assets.py
```

导出使用已存在的 Sharp 和 Pillow。母版路径是 `build_assets.py` 顶部的三个变量；修改它们后重新生成所有派生素材。参考 PNG 被原样复制用于对比窗口，其文字在预览中被裁出视野。

`LiveRelay-icon-draft.zip` 包含 SVG、PNG、ICO、Android 示例、预览与生成源码，排除 QA 截图。直接解压并打开 `preview.html` 可离线浏览。也可在本目录运行 `python3 -m http.server 8767 --bind 127.0.0.1` 后访问本机预览。

## 本轮验证边界

已检查 SVG／XML 解析、PNG 尺寸、ICO 每帧内容与尺寸、浏览器播放／停止和单次动画、主题颜色切换及减少动态开关，视觉比对了母版与源图。Android 资源属于导出示例，Windows／Linux 资源未进入平台打包验证；轮廓和品牌色未获人类定稿确认。

开始工作时远端 `main`、`codex/formal-foundation` 与本地均为 `a586349`。既有未跟踪的 `work/diagrams/architecture/` 保持原样，本轮只新增本素材目录。没有提交、推送或修改已发布制品。
