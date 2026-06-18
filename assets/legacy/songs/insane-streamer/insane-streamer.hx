function onCreatePost() {
	game.boyfriend.cameraPosition[0] = 280;
	game.boyfriend.cameraPosition[1] = -130; 
}

function onMoveCamera(isDad) {
	if (isDad == 'boyfriend') {
		
		game.defaultCamZoom = 0.8;
		
	} else {
		game.defaultCamZoom = 0.9;
	}
    
}