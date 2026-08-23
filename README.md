<p align="center">
	<a href="https://github.com/NMVTeam/NightmareVision">
		<img src="assets/legacy/images/branding/UpdogBlack.png" alt="Made with NightmareVision Engine" width="325"/>
	</a>
</p>

<h1 align="center">VS Impostor Legacy — Android Port</h1>

<p align="center"><b>Current version:</b> 1.1.2 &nbsp;·&nbsp; unofficial Android port, built on the <a href="https://github.com/NMVTeam/NightmareVision">NightmareVision engine</a></p>

<p align="center">
	Original PC mod available on
	<a href="https://gamejolt.com/games/vsimpostor/643430">
		<img src="https://s.gjcdn.net/img/favicon.png" width="16"/>
		GameJolt
	</a>
	 and
	<a href="https://gamebanana.com/mods/55652">
		<img src="https://images.gamebanana.com/static/img/favicon/32x32.png" width="16"/>
		GameBanana
	</a>
</p>

> [!NOTE]
> APKs for this port are generated automatically via GitHub Actions on every push — check the [Actions tab](../../actions) for the latest build artifacts.

---

A total-conversion mod for **Friday Night Funkin'**, in which you face off against colorful Among Us characters, across over 10 weeks and 57 songs. **VS Impostor: Legacy** is a from-the-ground-up remaster of the original 2023 mod, faithful to the original experience while adding new tweaks, features, awards, and cosmetics to collect — and maybe a few secrets to discover along the way.

This repository adapts the mod to run natively on **Android**, on top of NightmareVision's existing mobile backend.

---

## Credits

**Mod (VS Impostor Legacy)**
* inky03 / motorfrog — original mod creator

**Android Port**
* jereidk — port maintainer

**NightmareVision Engine**
* NMVTeam — engine authors
* FNF BR (LumiCoder) — original mobile port base
* StarNovaBR (StarNova) — mobile port contributions

**Engine upstream credits**
* ShadowMario and Co. — [Psych Engine](https://github.com/ShadowMario/FNF-PsychEngine)
* Nebula_Zorua — Modchart backend and the [Psych Engine fork](https://github.com/nebulazorua/exe-psych-fork) NMV is built off
* Rozebud — chart editor ([FPS Plus](https://github.com/ThatRozebudDude/FPS-Plus-Public))
* Codename Engine crew — camera rotation support
* FunkinCrew — [Lime](https://github.com/FunkinCrew/lime), [OpenFL](https://github.com/FunkinCrew/openfl), [hxcpp](https://github.com/FunkinCrew/hxcpp) forks
* MaybeMaru — [MoonChart](https://github.com/MaybeMaru/moonchart) and [flixel-animate](https://github.com/MaybeMaru/flixel-animate)

---

## How to compile locally

### Prerequisites

**All platforms:**
* [Haxe 4.3.6+](https://haxe.org/download/) and Haxelib 4.2.0+
* [Git](https://git-scm.com/downloads)

**Windows (PC build):**
* [VS Community Build Tools](https://aka.ms/vs/17/release/vs_BuildTools.exe) — install `Desktop development with C++`

**Android build:**
* [Android Studio](https://developer.android.com/studio) — for SDK/NDK setup

> [!NOTE]
> This project uses **hxpkg** to manage library versions. The expected versions are listed in `.hxpkg`.

---

### 1. Install libraries

```sh
haxelib git hxpkg https://github.com/ADA-Funni/hxpkg add-hmm-compatibility
haxelib run hxpkg install
```

<details>
<summary>Faster method (requires Rust)</summary>

```sh
haxelib git hxpkg https://github.com/ADA-Funni/hxpkg add-hmm-compatibility
haxelib run hxpkg to-hmm

cargo install --git https://github.com/ninjamuffin99/hmm-rs hmm-rs
hmm-rs clean
hmm-rs install

haxelib fixrepo

haxelib install hmm
haxelib remove grig.audio
haxelib run hmm reinstall grig.audio

haxelib fixrepo
```
</details>

---

### 2. Compile

#### Windows
```sh
haxelib run lime rebuild cpp -release
haxelib run lime build windows -release
```

#### Android

First, configure your SDK/NDK paths:
```sh
lime setup android
```
Provide absolute paths to your Android SDK, NDK, and JDK. Leave Apache Ant blank.

Then go to **Android Studio → SDK Manager → SDK Tools** and install:
- Android SDK Build-Tools
- NDK (Side by side) — r21e recommended
- Android SDK Platform-Tools

Then build:
```sh
haxelib run lime build android -release
```

To install directly on a connected device via USB debugging:
```sh
haxelib run lime test android -release
```

> [!TIP]
> You can add `-D ASSET_REDIRECT` to either build command so in-game assets update live as they're changed in the `assets` folder. Do **not** include this flag when making a release build.
