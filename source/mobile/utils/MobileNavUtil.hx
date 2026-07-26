package mobile.utils;

import funkin.data.ClientPrefs;

/**
 * Central utilities for mobile navigation mode handling.
 */
class MobileNavUtil
{
	/**
	 * Whether pointer-based navigation (mouse/touch on sprites) should be active.
	 * When nav mode is 'Virtual Pad', direct touch/mouse on sprites should be suppressed
	 * so that only the VirtualPad buttons respond.
	 */
	public static inline function allowPointerNav():Bool
	{
		#if mobile
		return ClientPrefs.navInputMode == 'Touch';
		#else
		return true;
		#end
	}

	/**
	 * Whether the mouse cursor should be visible.
	 *
	 * Purely a visual toggle -- whether the cursor actually interacts with
	 * anything is allowPointerNav()'s job (gated on navInputMode alone), not
	 * this one. This used to also force the cursor off whenever navInputMode
	 * was 'Virtual Pad', which meant enabling Show Cursor did nothing at all
	 * for the majority of players (Virtual Pad is this fork's default nav
	 * mode) -- the option should mean what it says regardless of nav mode.
	 */
	public static inline function shouldShowMouse():Bool
	{
		return ClientPrefs.showCursor;
	}
}
