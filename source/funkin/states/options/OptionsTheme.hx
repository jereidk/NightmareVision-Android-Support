package funkin.states.options;

/**
 * Shared accent palette for the Options subsystem (OptionsState and the
 * substates it opens). Before this existed, each screen had picked its own
 * "selected"/"accent" colors independently -- TouchOptionList and
 * MobileSettingsSubState had already converged on the same hot-pink/gold
 * pair (see MobileSettingsSubState's own COLOR_ACCENT comment: chosen to
 * match FNF's actual reds/pinks/golds instead of a generic dev-tool cyan),
 * but OptionsState.hx invented an unrelated blue-purple palette plus its own
 * gold shade (0xFFFFE066, inherited from upstream's much older UI), and
 * ControlsSubState still carries that same old upstream gold too. Same
 * screen, three unrelated "this is selected" languages.
 *
 * GOLD is the "selected row in a list" color (TouchOptionList's row
 * highlight/value text already use it). PINK is the "standalone interactive
 * accent" color (arrows, scrollbar thumb, action buttons that jump to a
 * whole different screen rather than adjusting a value in place).
 */
class OptionsTheme
{
	public static inline final GOLD:Int = 0xFFFFD700;
	public static inline final PINK:Int = 0xFFFF6B9D;

	// 0x8C5062 measured at only ~2.16:1 against TouchOptionList's arrow-pill
	// background, failing WCAG's 3:1 large-text minimum -- lightened to clear
	// it (~3.3:1 there, ~4.9:1 against a plain dark screen background).
	// Keep using this exact value anywhere PINK needs a dimmer/inactive
	// variant instead of re-deriving a new one per screen.
	public static inline final PINK_DIM:Int = 0xFFAB6C7F;

	public static inline final TEXT_IDLE:Int = 0xFFC9C9C9;
	public static inline final TEXT_HOVER:Int = 0xFFFFFFFF;
}
