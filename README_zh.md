# 
<p align="center">
<img src="./Logoer/Assets.xcassets/AppIcon.appiconset/icon_128x128@2x.png" width="200" height="200" />
<h1 align="center">Logoer</h1>
<h3 align="center">更换macOS菜单栏苹果logo样式的小工具<br><a href="./README.md">[English Version]</a>
</p>

## 运行截图
<p align="center">
<img alt="Logoer Screenshots" src="./img/preview.png" width="410"/>
<br>
<img alt="Logoer Screenshots2" src="./img/preview2.png" width="410"/>
</p>

## 关于此分支
本仓库是 [`lihaoyun6/Logoer`](https://github.com/lihaoyun6/Logoer) 的 fork.
原作者已停止维护, 因此上游的 Homebrew tap 和更新源都已失效, 请使用本仓库的版本.

相比上游 0.2.2 的变化:

- 修复 macOS 26 上无法打开设置面板的问题
- 电量指示器新增 Linux (Tux) 和 Windows 10 两种图标样式
- 通过 CGS Spaces API 检测全屏空间
- 只需 Command Line Tools 即可构建, 无需安装完整 Xcode

## 安装与使用
### 系统版本要求:
- macOS 11.0 及更高版本  

### 安装:
可[点此前往](../../releases/latest)下载最新版安装文件, 或从源码构建 (见下方"构建").

## 构建
### 仅使用 Command Line Tools
需要 Xcode Command Line Tools (`xcode-select --install`) 和 Python 3.

```bash
./scripts/build.sh            # 输出 build/Logoer.app
./scripts/build.sh --install  # 并覆盖安装到 /Applications/Logoer.app
```

`scripts/build.sh` 先执行 `swift build`, 再手工组装 `.app`, 因为 `actool` 和 `ibtool`
只随 Xcode 提供. 没有 Developer ID 时使用 ad-hoc 签名: 本机可以正常运行, 但 Sparkle
无法向这种签名的版本安装更新.

### 使用完整 Xcode
```bash
xcodebuild -project Logoer.xcodeproj -scheme Logoer -configuration Release build
```

## 致谢
原项目由 [lihaoyun6](https://github.com/lihaoyun6/Logoer) 开发, 采用 GNU AGPL v3 协议.

## 赞助
<img src="./img/donate.png" width="350"/>
