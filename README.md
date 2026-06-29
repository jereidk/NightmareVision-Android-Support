# VS IMPOSTOR LEGACY 1.1.1b

![](assets/legacy/images/branding/UpdogBlack.png)

Made with [NightmareVision Engine](https://github.com/NMVTeam/NightmareVision)!

### Read the [VS IMPOSTOR LEGACY changelog](LEGACY.md) here.

# Compiling

### Prerequisites

(You can skip this if you already have compiled any fnf or flixel project)

- [Git](https://git-scm.com/downloads)
- [Haxe](https://haxe.org/download/)
	- 4.3.6 or newer is expected!

### Additional platform setup
(excerpts from [Funkin compiling documentation](https://github.com/FunkinCrew/Funkin/blob/main/docs/COMPILING.md))
- If you're compiling for Windows, download the [Visual Studio Build Tools](https://aka.ms/vs/17/release/vs_BuildTools.exe).
	- When prompted, select "Individual Components" and make sure to download the following:
        - MSVC v143 VS 2022 C++ x64/x86 build tools
        - Windows 10/11 SDK
- For Mac, read the [macOS setup Lime documentation](https://lime.openfl.org/docs/advanced-setup/macos/).
- For Linux, read the [Linux setup Lime documentation](https://lime.openfl.org/docs/advanced-setup/linux/) first.
	- Hxvlc uses libVLC, which requires you to install some development packages to be able to compile.<br>
	For Ubuntu/Debian based systems, you can execute `sudo apt install libvlc-dev libvlccore-dev libvlccore9`.<br>For other distros, please refer to [Hxvlc's documentation](https://github.com/MAJigsaw77/hxvlc?tab=readme-ov-file#dependencies).

### Installing libraries

> [!TIP]  
> Actually, you can run [this file](projFiles/SETUP.bat) to handle library setup automatically!

> [!NOTE]
> This engine **enforces** the use of local libraries with hxpkg to prevent issues in relation to Hxvlc.<br>
> The expected library versions are listed within the .hxpkg file.
>
> If any compilation errors arise, ensure your Haxe version is correct and your libraries match those expected versions.

Open a Command Prompt within the project directory and run the following commands...

```cmd
haxelib install hxpkg
haxelib run hxpkg setup
haxelib run hxpkg install
```

You should be able to run `lime test cpp` to start compiling the game now!

- You can include `-D ASSET_REDIRECT` in the command for ingame assets to update as they're changed in the `assets` folder.<br>
	(Do **not** include this command if you're making a release build)

	Otherwise, to compile with the Security DLC, include the command `-D DLC` when building!!

# Special Thanks

- ShadowMario and Co. for [Psych Engine](https://github.com/ShadowMario/FNF-PsychEngine)
- Nebula_Zorua for the [specific Psych fork](https://github.com/nebulazorua/exe-psych-fork) NMV is built off and for the Modchart backend
- Rozebud for the chart editor little buddies ([Check out FPS Plus too](https://github.com/ThatRozebudDude/FPS-Plus-Public))
- MaybeMaru for [MoonChart](https://github.com/MaybeMaru/moonchart) and [Flixel-animate](https://github.com/MaybeMaru/flixel-animate)
