package funkin.states.options;

using StringTools;

class LanguageSubState extends BaseOptionsMenu
{
	var langOption:Option;
	var creditsText:FlxText;
	
	public function new()
	{
		title = 'language';
		rpcTitle = 'Language Menu';
		
		var languages:Array<String> = Lang.getAvailableLanguages();
		langOption = new Option(Lang.str('opt_language', 'Language'),
			Lang.str('opt_language_desc', 'Choose your language! Note: All languages besides English (United States) are community translated!'), 'language', 'string', 'english', languages);
		langOption.onChange = onChangeLanguage;
		addOption(langOption);
		
		var option:Option = new Option(Lang.str('opt_subtitles', 'Subtitles'), Lang.str('opt_subtitles_desc', "it ubtitle"), 'subtitles', 'bool', true);
		addOption(option);
		
		super();
		
		creditsText = new FlxText(panelX, optionStartY + optionSpacing * 2 + 6, 618, '');
		creditsText.setFormat(Paths.font('vcr.ttf'), 18, FlxColor.WHITE, FlxTextAlign.LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		creditsText.borderSize = 1;
		creditsText.antialiasing = ClientPrefs.globalAntialiasing;
		add(creditsText);
		
		onChangeLanguage();
	}
	
	function onChangeLanguage()
	{
		Lang.reloadLangFile();
		var displayName = Lang.current?.name ?? '[MISSING ${ClientPrefs.language}.json]';
		if (langOption != null) langOption.text = displayName;
		for (t in grpTexts)
		{
			if (t.ID == 0)
			{
				t.text = displayName;
				break;
			}
		}
		if (creditsText != null)
		{
			var tc:String = Lang.current?.translationCredits ?? '';
			creditsText.text = (tc.length > 0) ? 'Localization Credits: $tc' : '';
		}
	}
}
