function onCreatePost()
{
	if (curSong == 'Pinkwave' || curSong == 'Heartbeat')
	{
		greymira.alpha = 0.001;
	}
	if (curSong == 'Sauces Moogus')
	{
		gray.alpha = 0.001;
	}
	if (curSong == 'Delusion' || curSong == 'Blackout' || curSong == 'Neurotic')
	{
		triggerEventNote('Change Character', '0', 'minigreyscary');
	}
}
