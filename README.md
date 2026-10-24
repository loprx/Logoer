# 
<p align="center">
<img src="./Logoer/Assets.xcassets/AppIcon.appiconset/icon_128x128@2x.png" width="200" height="200" />
<h1 align="center">Logoer</h1>
<h3 align="center">Change the style of the Apple logo in macOS menu bar<br><a href="./README_zh.md">[中文版本]</a></h3> 
</p>

## Screenshots
<p align="center">
<img alt="Logoer Screenshots" src="./img/preview.png" width="410"/>
<br>
<img alt="Logoer Screenshots2" src="./img/preview2.png" width="410"/>
</p>

## This fork
This repository is a fork of [`lihaoyun6/Logoer`](https://github.com/lihaoyun6/Logoer).
The original author no longer maintains the project, so the Homebrew tap and the
upstream release feed are stale — please use this repository instead.

Changes over upstream 0.2.2:

- The settings panel opens reliably again on macOS 26
- The battery indicator can use a Linux (Tux) or Windows 10 logo shape
- Native full-screen Spaces are detected through the CGS Spaces API
- Builds with the Command Line Tools alone, no full Xcode install required

## Installation and Usage
### System Requirements:
- macOS 11.0 and Later  

### Installation:
Download the latest installation file [here](../../releases/latest), or use Homebrew:

```bash
brew install --cask loprx/tap/logoer
```

The bundled app is ad-hoc signed and arm64-only. If macOS blocks the first launch,
allow it under System Settings → Privacy & Security → Open Anyway.

You can also build from source (see [Building](#building)).

## Building
### Command Line Tools only
Requires the Xcode Command Line Tools (`xcode-select --install`) and Python 3.

```bash
./scripts/build.sh            # -> build/Logoer.app
./scripts/build.sh --install  # also replace /Applications/Logoer.app
```

`scripts/build.sh` runs `swift build` and then assembles the `.app` by hand, because
`actool` and `ibtool` only ship with Xcode. Without a Developer ID the bundle is
ad-hoc signed: it runs locally, but Sparkle cannot install updates into it.

### Full Xcode
```bash
xcodebuild -project Logoer.xcodeproj -scheme Logoer -configuration Release build
```

## Credits
Original project by [lihaoyun6](https://github.com/lihaoyun6/Logoer), licensed under
the GNU AGPL v3.

## Donate
<img src="./img/donate.png" width="350"/>
