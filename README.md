# VS IMPOSTOR LEGACY 1.1.1b

![](assets/legacy/images/branding/UpdogBlack.png)

Made with [NightmareVision Engine](https://github.com/NMVTeam/NightmareVision)! Read the [VS IMPOSTOR LEGACY changelog](LEGACY.md) here.

To compile with the Security DLC, include the command `-D DLC` when building!!

# Compiling

If compilation errors arise, Ensure your Haxe version is correct and your haxelibs match what is listed in the .hxpkg file

### Prerequisites...

(You can skip this if you already have compiled any fnf or flixel project)

- [Git](https://git-scm.com/downloads)
- [Haxe](https://haxe.org/download/)
	- 4.3.6 or newer is expected!
- [VS Community](https://visualstudio.microsoft.com/vs/community/)
	- Within the VS Community Installer, download **Desktop Development with C++**

### Download the projects required libraries...

> [!TIP]  
> Actually, you can run [this file](projFiles/SETUP.bat) to automate the library setup process!

> [!NOTE]
> This engine **enforces** the use of local libraries with hxpkg/hmm to prevent issues in relation to Hxvlc.<br>
> The expected library versions are listed within the .hxpkg file.

Open a Command Prompt within the project directory and run the following commands...

```cmd
haxelib install hxpkg
haxelib run hxpkg setup
haxelib run hxpkg install
```

You should be able to run `lime test cpp` to start compiling the game now!

You can include `-D ASSET_REDIRECT` in the command for files to update as they're changed in the assets folder.<br>
(Do **not** include this command if you're making a release build)

# Special Thanks

- ShadowMario and Co. for [Psych Engine](https://github.com/ShadowMario/FNF-PsychEngine)
- Nebula_Zorua for the [specific Psych fork](https://github.com/nebulazorua/exe-psych-fork) NMV is built off and for the Modchart backend
- Rozebud for the chart editor little buddies ([Check out FPS Plus too](https://github.com/ThatRozebudDude/FPS-Plus-Public))
- MaybeMaru for [MoonChart](https://github.com/MaybeMaru/moonchart) and [Flixel-animate](https://github.com/MaybeMaru/flixel-animate)
