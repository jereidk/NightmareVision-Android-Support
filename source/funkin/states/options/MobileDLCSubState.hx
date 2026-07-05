package funkin.states.options;

#if mobile

import flixel.FlxG;
import flixel.FlxSprite;
import flixel.math.FlxRect;
import flixel.text.FlxText;
import flixel.util.FlxColor;
import flixel.tweens.FlxTween;
import flixel.tweens.FlxEase;
import flixel.graphics.FlxGraphic;

import openfl.net.FileFilter;
import openfl.display.BitmapData;
import funkin.utils.FileUtil;

import mobile.backend.DLCManager;
import mobile.backend.DLCManager.DLCTaskState;
import mobile.backend.DLCManager.DLCEntry;

/** One entry in the displayed list. */
typedef DLCListItem = {
    id:String,
    label:String,
    sub:String,
    installed:Bool,
    downloadable:Bool
}

/**
 * Mobile DLC management substate.
 * Opened from OptionsState on Android; shows installed DLCs and a browsable
 * community registry that can be downloaded in-app.
 *
 * Navigation (virtual pad / keyboard):
 *   UP / DOWN    — move selection
 *   LEFT / RIGHT — switch tab (Installed ↔ Browse)
 *   ACCEPT       — download / uninstall selected DLC
 *   BACK         — close
 *
 * Touch (default 'Touch' nav mode, no virtual pad on screen):
 *   tap a tab      — switch tab
 *   tap a row      — select it; tap the selected row again to activate it
 *   tap ▲/▼ hints  — scroll selection up / down
 *   (BACK is the Android hardware back key, always available)
 */
class MobileDLCSubState extends MusicBeatSubstate
{
    // ── Layout ─────────────────────────────────────────────────────────────
    static final LIST_X:Float  = 60;
    // List spans LIST_X..LIST_X+LIST_W, i.e. 60..1220 on the 1280 canvas —
    // symmetric 60px margins on both sides. Was `static final`, but that's
    // wrong for a value that needs 'expand' mode's cutout: hxcpp runs static
    // initializers at program startup, before the scale mode has measured
    // the real screen, so gameCutoutSize.x would freeze at 0 forever. Made
    // this a plain instance field (computed fresh each time this substate is
    // constructed) growing by the full cutout, so the right margin stays
    // exactly 60px instead of turning into a growing dead gap. LIST_X itself
    // doesn't need to move — the same left margin is still correct.
    var LIST_W:Float  = 1160 + funkin.backend.FunkinRatioScaleMode.gameCutoutSize.x;
    static final LIST_Y0:Float = 118;
    static final ITEM_H:Float  = 54;
    static final MAX_VIS:Int   = 9;    // 9 × 54px = 486px fits between y=118 and the bottom panel at y=640

    static final TAB_INSTALLED:Int = 0;
    static final TAB_BROWSE:Int    = 1;

    // ── Palette (matches the accent language used across the rest of the app) ──
    static final COL_ACCENT:Int    = 0xFF9D5CFF;
    static final COL_CARD:Int      = 0xFF13131F;
    static final COL_SELECTED:Int  = 0xFF352F73;
    static final COL_INSTALLED:Int = 0xFF22C55E;
    static final COL_DOWNLOAD:Int  = 0xFF38BDF8;
    static final COL_DANGER:Int    = 0xFFEF4444;
    static final COL_AMBER:Int     = 0xFFF59E0B;
    static final COL_NEUTRAL:Int   = 0xFF4B5563;

    // ── UI objects ─────────────────────────────────────────────────────────
    var _tabLabels:Array<FlxText>;
    var _tabPill:FlxSprite;
    var _tabTargetX:Array<Float> = [];

    var _rowCards:Array<FlxSprite>;
    var _rowAccents:Array<FlxSprite>;
    var _rowGlows:Array<FlxSprite>;
    var _nameTexts:Array<FlxText>;
    var _subtexts:Array<FlxText>;
    var _actionTexts:Array<FlxText>;

    var _progressBg:FlxSprite;
    var _progressFill:FlxSprite;
    var _progressPulseTimer:Float = 0.0;
    var _statusText:FlxText;
    var _descText:FlxText;
    var _countBadge:FlxSprite;
    var _countText:FlxText;

    // ── Rounded-graphic cache (built once, reused — same pattern as MobileHitbox) ──
    var _gfxCache:Map<String, FlxGraphic> = new Map();

    // ── State ──────────────────────────────────────────────────────────────
    var _tab:Int         = TAB_INSTALLED;
    var _sel:Int         = 0;
    var _scroll:Int      = 0;
    var _blockInput:Bool = false;

    var _installed:Array<{id:String, name:String, folder:String}> = [];
    var _lastTaskState:DLCTaskState = DLCTaskState.IDLE;
    var _items:Array<DLCListItem>   = [];
    var _pendingUninstallId:Null<String> = null;
	var _pendingReinstallId:Null<String> = null;
    var _successTimer:Float = 0.0;
    var _scrollUpHint:FlxText;
    var _scrollDownHint:FlxText;
    var _clipRect:FlxRect;
    var _uninstallMsg:String = "";
    var _uninstallMsgOk:Bool = false;
    var _uninstallMsgTimer:Float = 0.0;

    // ── Lifecycle ──────────────────────────────────────────────────────────

    public function new()
    {
        super();
    }

    override function create()
    {
        // Semi-transparent overlay
        var bg = new FlxSprite().makeScaledGraphic(FlxG.width, FlxG.height, FlxColor.fromRGB(0, 0, 8, 210));
        add(bg);

        // Title
        var titleTxt = new FlxText(0, 18, FlxG.width, "DLC MANAGER");
        titleTxt.setFormat(Paths.font("vcr.ttf"), 38, FlxColor.WHITE, CENTER,
            FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
        titleTxt.borderSize = 2;
        add(titleTxt);

        // Small stat badge next to the title, e.g. "3 INSTALLED"
        _countBadge = new FlxSprite(FlxG.width - 220, 24);
        _countBadge.loadGraphic(_cachedRounded('dlc_countbadge', 200, 32, COL_ACCENT, 14));
        _countBadge.alpha = 0.25;
        add(_countBadge);

        _countText = new FlxText(FlxG.width - 220, 30, 200, "");
        _countText.setFormat(Paths.font("vcr.ttf"), 16, COL_INSTALLED, CENTER,
            FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
        _countText.borderSize = 1.5;
        add(_countText);

        // Tab labels + a pill that slides beneath whichever tab is active
        _tabPill = new FlxSprite(LIST_X - 10, 60);
        _tabPill.loadGraphic(_cachedRounded('dlc_tabpill', 176, 36, COL_SELECTED, 10));
        add(_tabPill);

        _tabLabels = [];
        var tabNames = ["Installed", "Browse"];
        for (i in 0...tabNames.length) {
            _tabTargetX.push(LIST_X - 10 + i * 230);
            var t = new FlxText(LIST_X + i * 230, 66, 200, tabNames[i]);
            t.setFormat(Paths.font("vcr.ttf"), 24, FlxColor.GRAY, CENTER,
                FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
            t.borderSize = 1.5;
            _tabLabels.push(t);
            add(t);
        }
        _tabPill.x = _tabTargetX[_tab];

        // Top separator
        var sep = new FlxSprite(LIST_X, 105).makeGraphic(Std.int(LIST_W), 2,
            FlxColor.fromRGB(90, 90, 90));
        add(sep);

        // Pre-create fixed pool of list rows (updated in-place — no alloc per frame)
        _rowCards    = [];
        _rowAccents  = [];
        _rowGlows    = [];
        _nameTexts   = [];
        _subtexts    = [];
        _actionTexts = [];

        for (i in 0...MAX_VIS) {
            var rowY = LIST_Y0 + i * ITEM_H;
            var cardH = Std.int(ITEM_H - 6);

            // Base card — always visible once populated, gives each row a defined boundary
            var card = new FlxSprite(LIST_X, rowY);
            card.loadGraphic(_cachedRounded('dlc_card', Std.int(LIST_W), cardH, COL_CARD, 10));
            card.alpha = 0.6;
            card.visible = false;
            _rowCards.push(card);
            add(card);

            // Selection glow — same footprint, alpha-tweened in/out instead of an instant snap
            var glow = new FlxSprite(LIST_X, rowY);
            glow.loadGraphic(_cachedRounded('dlc_glow', Std.int(LIST_W), cardH, COL_SELECTED, 10));
            glow.alpha = 0;
            glow.visible = false;
            _rowGlows.push(glow);
            add(glow);

            // Left accent stripe — colour communicates state at a glance (green/blue/gray)
            var accent = new FlxSprite(LIST_X + 6, rowY + 6);
            accent.loadGraphic(_cachedRounded('dlc_accent', 5, Std.int(cardH - 12), COL_NEUTRAL, 2));
            accent.visible = false;
            _rowAccents.push(accent);
            add(accent);

            var n = new FlxText(LIST_X + 24, rowY + 4, Std.int(LIST_W) - 190, "");
            n.setFormat(Paths.font("vcr.ttf"), 20, FlxColor.WHITE, LEFT,
                FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
            n.borderSize = 1.5;
            n.visible = false;
            _nameTexts.push(n);
            add(n);

            var sub = new FlxText(LIST_X + 24, rowY + 28, Std.int(LIST_W) - 190, "");
            sub.setFormat(Paths.font("vcr.ttf"), 13, FlxColor.fromRGB(160, 160, 160), LEFT,
                FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
            sub.borderSize = 1;
            sub.visible = false;
            _subtexts.push(sub);
            add(sub);

            var act = new FlxText(LIST_X, rowY + 10, Std.int(LIST_W) - 22, "");
            act.setFormat(Paths.font("vcr.ttf"), 17, FlxColor.fromRGB(100, 200, 255), RIGHT,
                FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
            act.borderSize = 1;
            act.visible = false;
            _actionTexts.push(act);
            add(act);
        }

        // Bottom separator + description row
        var botSep = new FlxSprite(LIST_X, FlxG.height - 80)
            .makeGraphic(Std.int(LIST_W), 2, FlxColor.fromRGB(90, 90, 90));
        add(botSep);

        _descText = new FlxText(LIST_X + 4, FlxG.height - 76, Std.int(LIST_W), "");
        _descText.setFormat(Paths.font("vcr.ttf"), 13, FlxColor.fromRGB(180, 180, 180), LEFT,
            FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
        _descText.borderSize = 1;
        add(_descText);

        // Progress bar — rounded, with a soft pulse while a task is running
        _progressBg = new FlxSprite(LIST_X, FlxG.height - 38);
        _progressBg.loadGraphic(_cachedRounded('dlc_progbg', Std.int(LIST_W), 18, 0xFF28282A, 9));
        _progressBg.visible = false;
        add(_progressBg);

        _progressFill = new FlxSprite(LIST_X, FlxG.height - 38);
        _progressFill.loadGraphic(_cachedRounded('dlc_progfill', Std.int(LIST_W), 18, COL_INSTALLED, 9));
        _progressFill.visible = false;
        add(_progressFill);
        _clipRect = new FlxRect(0, 0, 0, 18);

        _statusText = new FlxText(LIST_X, FlxG.height - 19, Std.int(LIST_W), "");
        _statusText.setFormat(Paths.font("vcr.ttf"), 14, FlxColor.GRAY, LEFT,
            FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
        _statusText.borderSize = 1;
        add(_statusText);

        // Scroll position hints — shown when items extend above or below the visible window
        _scrollUpHint = new FlxText(LIST_X + LIST_W - 160, LIST_Y0 - 16, 156, "▲ more above");
        _scrollUpHint.setFormat(Paths.font("vcr.ttf"), 12, FlxColor.fromRGB(120, 120, 120), RIGHT,
            FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
        _scrollUpHint.borderSize = 1;
        _scrollUpHint.visible = false;
        add(_scrollUpHint);

        _scrollDownHint = new FlxText(LIST_X + LIST_W - 160, LIST_Y0 + MAX_VIS * ITEM_H + 2, 156, "▼ more below");
        _scrollDownHint.setFormat(Paths.font("vcr.ttf"), 12, FlxColor.fromRGB(120, 120, 120), RIGHT,
            FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
        _scrollDownHint.borderSize = 1;
        _scrollDownHint.visible = false;
        add(_scrollDownHint);

        super.create();

        #if mobile
        addVirtualPad(LEFT_FULL, A_B);
        addVirtualPadCamera();
        #end

        _refreshInstalled();
        _rebuildItems();
        _updateTabVisuals(true);
        _updateRows();

        // Fetch registry if we don't already have it (don't interrupt an ongoing download)
        if (DLCManager.taskState != DLCTaskState.BUSY && DLCManager.registryData == null)
            DLCManager.fetchRegistryAsync();
    }

    // ── Rounded-graphic helpers (drawn once per size/color, cached like MobileHitbox's buttons) ──

    function _roundedRectBitmap(w:Int, h:Int, color:Int, radius:Int):BitmapData
    {
        var bmp = new BitmapData(w, h, true, 0x00000000);
        var r = radius;

        for (px in 0...w) {
            for (py in 0...h) {
                var inside = true;

                if (px < r && py < r) {
                    var dx = r - px, dy = r - py;
                    if (dx * dx + dy * dy > r * r) inside = false;
                } else if (px >= w - r && py < r) {
                    var dx = px - (w - r - 1), dy = r - py;
                    if (dx * dx + dy * dy > r * r) inside = false;
                } else if (px < r && py >= h - r) {
                    var dx = r - px, dy = py - (h - r - 1);
                    if (dx * dx + dy * dy > r * r) inside = false;
                } else if (px >= w - r && py >= h - r) {
                    var dx = px - (w - r - 1), dy = py - (h - r - 1);
                    if (dx * dx + dy * dy > r * r) inside = false;
                }

                if (inside) bmp.setPixel32(px, py, color);
            }
        }

        return bmp;
    }

    function _cachedRounded(baseKey:String, w:Int, h:Int, color:Int, radius:Int):FlxGraphic
    {
        var key = '${baseKey}_${w}x${h}_${color}_${radius}';
        var g = _gfxCache.get(key);
        if (g == null) {
            g = FlxG.bitmap.add(_roundedRectBitmap(w, h, color, radius), false, key);
            _gfxCache.set(key, g);
        }
        return g;
    }

    // ── Update ─────────────────────────────────────────────────────────────

    override function update(elapsed:Float)
    {
        super.update(elapsed);

        var ts = DLCManager.taskState;
        if (ts != _lastTaskState) {
            _lastTaskState = ts;
            _pendingUninstallId = null; _pendingReinstallId = null;
            if (ts == DLCTaskState.SUCCESS || ts == DLCTaskState.FAILED) {
                _blockInput = false;
                _refreshInstalled();
                _rebuildItems();
                _updateRows();
            } else if (ts == DLCTaskState.BUSY && DLCManager.activeTaskId != "_registry") {
                _updateRows();
            }
        }

        if (ts == DLCTaskState.SUCCESS)
            _successTimer += elapsed;
        else
            _successTimer = 0.0;

        if (_uninstallMsgTimer > 0.0) {
            _uninstallMsgTimer -= elapsed;
            if (_uninstallMsgTimer <= 0.0) _uninstallMsg = "";
        }

        _progressPulseTimer += elapsed;
        _updateProgressBar();
        _updateStatusLine();

        // BACK is always available — player must never be fully trapped
        if (controls.BACK) { close(); return; }

        if (!_blockInput)
            _handleInput();

        #if mobile
        if (!_blockInput)
            _handleTouch();
        #end
    }

    // ── Input ──────────────────────────────────────────────────────────────

    function _handleInput():Void
    {
        var len = _items.length;
        if (len == 0) return;

        if (controls.UI_UP_P) {
            _pendingUninstallId = null; _pendingReinstallId = null;
            _sel = (_sel <= 0) ? len - 1 : _sel - 1;
            _clampScroll();
            FunkinSound.play(Paths.sound('hover'), 0.5);
            _updateRows();
        }

        if (controls.UI_DOWN_P) {
            _pendingUninstallId = null; _pendingReinstallId = null;
            _sel = (_sel >= len - 1) ? 0 : _sel + 1;
            _clampScroll();
            FunkinSound.play(Paths.sound('hover'), 0.5);
            _updateRows();
        }

        if (controls.UI_LEFT_P || controls.UI_RIGHT_P) {
            _pendingUninstallId = null; _pendingReinstallId = null;
            _tab   = (_tab == TAB_INSTALLED) ? TAB_BROWSE : TAB_INSTALLED;
            _sel    = 0;
            _scroll = 0;
            _updateTabVisuals();
            _rebuildItems();
            _updateRows();
            FunkinSound.play(Paths.sound('scrollMenu'));
        }

        if (controls.ACCEPT)
            _handleAccept();
    }

    #if mobile
    /**
     * Direct touch / mouse handling so the menu is fully usable in the default
     * 'Touch' nav mode (where no virtual pad is shown). Runs in addition to the
     * controls-based input above, so it also works alongside the virtual pad.
     */
    function _handleTouch():Void
    {
        if (funkin.data.ClientPrefs.navInputMode == 'Virtual Pad') return;
        if (!FlxG.mouse.justPressed) return;

        var mx = FlxG.mouse.x;
        var my = FlxG.mouse.y;

        // Tabs
        for (i in 0..._tabLabels.length) {
            if (i != _tab && FlxG.mouse.overlaps(_tabLabels[i])) {
                _pendingUninstallId = null; _pendingReinstallId = null;
                _tab    = i;
                _sel    = 0;
                _scroll = 0;
                _updateTabVisuals();
                _rebuildItems();
                _updateRows();
                FunkinSound.play(Paths.sound('scrollMenu'));
                return;
            }
        }

        var len = _items.length;
        if (len == 0) return;

        // Scroll hints
        if (_scrollUpHint.visible && FlxG.mouse.overlaps(_scrollUpHint)) {
            _pendingUninstallId = null; _pendingReinstallId = null;
            _sel = (_sel <= 0) ? len - 1 : _sel - 1;
            _clampScroll();
            FunkinSound.play(Paths.sound('hover'), 0.5);
            _updateRows();
            return;
        }
        if (_scrollDownHint.visible && FlxG.mouse.overlaps(_scrollDownHint)) {
            _pendingUninstallId = null; _pendingReinstallId = null;
            _sel = (_sel >= len - 1) ? 0 : _sel + 1;
            _clampScroll();
            FunkinSound.play(Paths.sound('hover'), 0.5);
            _updateRows();
            return;
        }

        // Rows — tap to select, tap the already-selected row to activate
        if (mx < LIST_X || mx > LIST_X + LIST_W) return;
        for (i in 0...MAX_VIS) {
            if (!_nameTexts[i].visible) continue;
            var realIdx = i + _scroll;
            if (realIdx >= len) continue;

            var rowY = LIST_Y0 + i * ITEM_H;
            if (my >= rowY && my < rowY + ITEM_H) {
                if (realIdx != _sel) {
                    _pendingUninstallId = null; _pendingReinstallId = null;
                    _sel = realIdx;
                    _clampScroll();
                    FunkinSound.play(Paths.sound('hover'), 0.5);
                    _updateRows();
                } else {
                    _handleAccept();
                }
                return;
            }
        }
    }
    #end

    function _handleAccept():Void
    {
        if (DLCManager.taskState == DLCTaskState.BUSY) return;
        var item:Null<DLCListItem> = _items[_sel];
        if (item == null) return;

        // Open native file picker to install a local ZIP
        if (item.id == "__install_local__") {
            _openLocalFilePicker();
            return;
        }

        // Empty placeholder item — retry registry fetch if it previously failed
        if (item.id == "") {
            if (_tab == TAB_BROWSE && DLCManager.taskState == DLCTaskState.FAILED) {
                DLCManager.fetchRegistryAsync();
                _rebuildItems();
                _updateRows();
                FunkinSound.play(Paths.sound('confirmMenu'));
            }
            return;
        }

        if (item.installed) {
            if (_tab == TAB_BROWSE) {
                // Reinstall flow in Browse tab
                if (_pendingReinstallId == item.id) {
                    _pendingReinstallId = null; _pendingUninstallId = null;
                    // Uninstall first
                    DLCManager.uninstallDLC(item.id);
                    _refreshInstalled();
                    // Then download & install
                    var entry:Null<DLCEntry> = null;
                    for (e in DLCManager.registryData.dlcs)
                        if (e.id == item.id) { entry = e; break; }
                    if (entry != null) {
                        _uninstallMsg      = "Reinstalling " + item.label + "...";
                        _uninstallMsgOk    = true;
                        _uninstallMsgTimer = 0.0;
                        DLCManager.downloadAndInstallAsync(entry);
                        _blockInput = true;
                        FunkinSound.play(Paths.sound('confirmMenu'));
                        _updateRows();
                    } else {
                        _uninstallMsg      = "Could not find DLC entry in registry.";
                        _uninstallMsgOk    = false;
                        _uninstallMsgTimer = 5.0;
                        _rebuildItems();
                        _updateRows();
                    }
                } else {
                    _pendingReinstallId = item.id; _pendingUninstallId = null;
                    FunkinSound.play(Paths.sound('scrollMenu'));
                    _updateRows();
                }
            } else {
                if (_pendingUninstallId == item.id) {
                    // Second press confirms — actually uninstall
                    _pendingUninstallId = null; _pendingReinstallId = null;
                    var ok = DLCManager.uninstallDLC(item.id);
                    FunkinSound.play(Paths.sound('cancelMenu'));
                    _refreshInstalled();
                    _rebuildItems();
                    _updateRows();
                    if (ok) {
                        _uninstallMsg      = item.label + " removed.";
                        _uninstallMsgOk    = true;
                        _uninstallMsgTimer = 4.0;
                    } else {
                        _uninstallMsg      = "Could not remove DLC. Check storage permissions.";
                        _uninstallMsgOk    = false;
                        _uninstallMsgTimer = 5.0;
                    }
                } else {
                    // First press — request confirmation
                    _pendingUninstallId = item.id; _pendingReinstallId = null;
                    FunkinSound.play(Paths.sound('scrollMenu'));
                    _updateRows();
                }
            }
        } else if (item.downloadable && DLCManager.registryData != null) {
            var entry:Null<DLCEntry> = null;
            for (e in DLCManager.registryData.dlcs)
                if (e.id == item.id) { entry = e; break; }
            if (entry != null) {
                DLCManager.downloadAndInstallAsync(entry);
                _blockInput = true;
                FunkinSound.play(Paths.sound('confirmMenu'));
                _updateRows();
            }
        }
    }

    // ── Data helpers ───────────────────────────────────────────────────────

    function _refreshInstalled():Void
    {
        _installed = DLCManager.getInstalledDLCs();
    }

    function _rebuildItems():Void
    {
        _items = [];

        if (_tab == TAB_INSTALLED) {
            for (d in _installed) {
                _items.push({
                    id:           d.id,
                    label:        d.name,
                    sub:          "Installed  •  " + d.folder.split("/").pop(),
                    installed:    true,
                    downloadable: false
                });
            }
            if (_items.length == 0) {
                _items.push({
                    id:           "",
                    label:        "No DLCs installed yet.",
                    sub:          "Browse the community tab, or install a ZIP below.",
                    installed:    false,
                    downloadable: false
                });
            }
            // Always show the local install option at the bottom
            _items.push({
                id:           "__install_local__",
                label:        "Install from local ZIP...",
                sub:          "Open your device file picker to select a mod ZIP",
                installed:    false,
                downloadable: false
            });
        } else {
            if (DLCManager.registryData != null) {
                for (e in DLCManager.registryData.dlcs) {
                    var inst = DLCManager.isDLCInstalled(e.id);
                    var sizeStr = e.sizeMb > 0 ? "  •  " + e.sizeMb + " MB" : "";
                    _items.push({
                        id:           e.id,
                        label:        e.name,
                        sub:          "by " + e.author + sizeStr,
                        installed:    inst,
                        downloadable: !inst
                    });
                }
            }
            if (_items.length == 0) {
                var ts  = DLCManager.taskState;
                var msg = ts == DLCTaskState.BUSY      ? "Loading DLC list..."
                        : DLCManager.registryData != null ? "No community DLCs available yet."
                        : "Could not load DLC list. Check your connection.";
                var sub = ts == DLCTaskState.FAILED ? "Press Accept to retry." : "";
                _items.push({id: "", label: msg, sub: sub, installed: false, downloadable: false});
            }
        }

        if (_sel >= _items.length) _sel = Std.int(Math.max(0, _items.length - 1));
        _clampScroll();

        _countText.text = _installed.length + " INSTALLED";
    }

    function _clampScroll():Void
    {
        if (_sel < _scroll) _scroll = _sel;
        if (_sel >= _scroll + MAX_VIS) _scroll = _sel - MAX_VIS + 1;
        if (_scroll < 0) _scroll = 0;
    }

    function _openLocalFilePicker():Void
    {
        #if android
        _blockInput = true;
        FunkinSound.play(Paths.sound('confirmMenu'));
        FileUtil.browseForMultipleFiles(
            { typeFilter: [new FileFilter("ZIP files", "zip")] },
            (paths) -> {
                if (paths != null && paths.length > 0 && paths[0] != null && paths[0] != "")
                    DLCManager.installFromLocalZipAsync(paths[0]);
                // Unblock if task didn't actually start (already BUSY, or empty path)
                if (DLCManager.taskState != DLCTaskState.BUSY)
                    _blockInput = false;
            },
            () -> { _blockInput = false; }
        );
        #end
    }

    // ── Visual refresh ─────────────────────────────────────────────────────

    function _updateTabVisuals(instant:Bool = false):Void
    {
        for (i in 0..._tabLabels.length)
            _tabLabels[i].color = (i == _tab) ? FlxColor.WHITE : FlxColor.GRAY;

        FlxTween.cancelTweensOf(_tabPill);
        if (instant) {
            _tabPill.x = _tabTargetX[_tab];
        } else {
            FlxTween.tween(_tabPill, {x: _tabTargetX[_tab]}, 0.22, {ease: FlxEase.quintOut});
        }
    }

    function _updateRows():Void
    {
        for (i in 0...MAX_VIS) {
            var realIdx = i + _scroll;
            var item:Null<DLCListItem> = _items[realIdx];

            if (item == null) {
                _rowCards[i].visible    = false;
                _rowAccents[i].visible  = false;
                _rowGlows[i].visible    = false;
                _nameTexts[i].visible   = false;
                _subtexts[i].visible    = false;
                _actionTexts[i].visible = false;
                continue;
            }

            var selected = (realIdx == _sel);

            _rowCards[i].visible    = true;
            _rowAccents[i].visible  = (item.id != "");
            _nameTexts[i].visible   = true;
            _subtexts[i].visible    = (item.sub != "");
            _actionTexts[i].visible = (item.id  != "");

            // Smooth cross-fade for the selection glow instead of an instant show/hide.
            _rowGlows[i].visible = true;
            FlxTween.cancelTweensOf(_rowGlows[i]);
            FlxTween.tween(_rowGlows[i], {alpha: selected ? 0.45 : 0}, 0.16, {ease: FlxEase.quadOut});

            _nameTexts[i].text = item.label;
            _subtexts[i].text  = item.sub;

            _nameTexts[i].color =
                selected       ? FlxColor.YELLOW :
                item.installed ? FlxColor.fromRGB(180, 255, 180) :
                                 FlxColor.WHITE;

            // Accent stripe colour: at a glance, green = installed, blue = downloadable, gray = neutral.
            var accentColor = item.installed ? COL_INSTALLED : item.downloadable ? COL_DOWNLOAD : COL_NEUTRAL;
            _rowAccents[i].loadGraphic(_cachedRounded('dlc_accent', 5, Std.int(ITEM_H - 6 - 12), accentColor, 2));

            var activeDown = (DLCManager.taskState == DLCTaskState.BUSY && DLCManager.activeTaskId == item.id)
                          || (item.id == "__install_local__" && DLCManager.taskState == DLCTaskState.BUSY
                              && DLCManager.activeTaskId != "_registry" && DLCManager.activeTaskId != "");
            if (activeDown) {
                _actionTexts[i].text  = "Downloading...";
                _actionTexts[i].color = FlxColor.YELLOW;
            } else if (item.id == "__install_local__") {
                _actionTexts[i].text  = "+ Add ZIP";
                _actionTexts[i].color = FlxColor.fromRGB(200, 200, 100);
            } else if (item.installed) {
                if (_tab == TAB_BROWSE) {
                    if (_pendingReinstallId == item.id) {
                        _actionTexts[i].text  = "Confirm reinstall?";
                        _actionTexts[i].color = COL_AMBER;
                    } else {
                        _actionTexts[i].text  = "Reinstall";
                        _actionTexts[i].color = FlxColor.fromRGB(255, 200, 100);
                    }
                } else {
                    if (_pendingUninstallId == item.id) {
                        _actionTexts[i].text  = "Confirm uninstall!";
                        _actionTexts[i].color = COL_DANGER;
                    } else {
                        _actionTexts[i].text  = "Uninstall";
                        _actionTexts[i].color = FlxColor.fromRGB(255, 110, 110);
                    }
                }
            } else if (item.downloadable) {
                _actionTexts[i].text  = "Download";
                _actionTexts[i].color = COL_DOWNLOAD;
            } else {
                _actionTexts[i].text = "";
            }
        }

        _scrollUpHint.visible   = (_scroll > 0);
        _scrollDownHint.visible = (_scroll + MAX_VIS < _items.length);

        // Show description of selected Browse-tab entry
        if (_tab == TAB_BROWSE && DLCManager.registryData != null && _items.length > 0) {
            var selItem:Null<DLCListItem> = _items[_sel];
            if (selItem != null && selItem.id != "") {
                for (e in DLCManager.registryData.dlcs) {
                    if (e.id == selItem.id) { _descText.text = e.description; break; }
                }
            } else {
                _descText.text = "";
            }
        } else {
            _descText.text = "";
        }
    }

    function _updateProgressBar():Void
    {
        var ts = DLCManager.taskState;
        if (ts == DLCTaskState.BUSY) {
            _clipRect.width = Math.max(0.0, DLCManager.taskProgress / 100.0) * LIST_W;
            _progressBg.visible    = true;
            _progressFill.visible  = true;
            _progressFill.clipRect = _clipRect;
            // Gentle pulse while the download is running so the bar doesn't feel static.
            _progressFill.alpha = 0.85 + Math.sin(_progressPulseTimer * 4.0) * 0.15;
        } else if (ts == DLCTaskState.SUCCESS && _successTimer < 5.0) {
            _clipRect.width = LIST_W;
            _progressBg.visible    = true;
            _progressFill.visible  = true;
            _progressFill.clipRect = _clipRect;
            _progressFill.alpha    = 1.0;
        } else {
            _progressBg.visible   = false;
            _progressFill.visible = false;
        }
    }

    function _updateStatusLine():Void
    {
        var ts = DLCManager.taskState;
        if (ts == DLCTaskState.BUSY) {
            _statusText.text  = DLCManager.taskMessage;
            _statusText.color = FlxColor.WHITE;
        } else if (ts == DLCTaskState.SUCCESS && _successTimer < 5.0) {
            _statusText.text  = DLCManager.taskMessage;
            _statusText.color = FlxColor.fromRGB(100, 255, 100);
        } else if (ts == DLCTaskState.FAILED) {
            _statusText.text  = DLCManager.taskMessage;
            _statusText.color = FlxColor.fromRGB(255, 100, 100);
        } else if (_uninstallMsg != "") {
            _statusText.text  = _uninstallMsg;
            _statusText.color = _uninstallMsgOk ? FlxColor.fromRGB(255, 180, 80) : FlxColor.fromRGB(255, 100, 100);
        } else {
            _statusText.text  = _installed.length + " DLC" + (_installed.length == 1 ? "" : "s") + " installed";
            _statusText.color = FlxColor.fromRGB(120, 120, 120);
        }
    }

    // ── Cleanup ────────────────────────────────────────────────────────────

    override function close()
    {
        #if mobile
        removeVirtualPad();
        #end
        super.close();
    }

    override function destroy()
    {
        // super.destroy() first — it walks every added sprite and nulls their
        // .graphic reference, which decrements each cached FlxGraphic's
        // useCount the normal way. Only once that's done is it safe to
        // actually dispose the cached graphics themselves (same order
        // MobileHitbox uses for its own _cachedGraphics cleanup).
        super.destroy();

        for (key in _gfxCache.keys()) {
            var g = _gfxCache.get(key);
            FlxG.bitmap.remove(g);
            g.destroy();
        }
        _gfxCache.clear();
    }
}

#end
