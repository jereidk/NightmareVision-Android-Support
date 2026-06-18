function onEvent(n, v1, v2)
{
	if (n == 'Legacy')
	{
		switch (v1)
		{
			case 'hmm':
				defaultCamZoomAdd = 0.05;
			case 'wmc':
				camSpecialThing([1600, 700], [1600, 700]);
			case 'nc':
				camSpecialThing([1300, 700], [1800, 700]);
			case "slightly worse camera":
				camSpecialThing([1300, 750], [1800, 750]);
		}
	}
}
