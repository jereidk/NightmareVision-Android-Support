#pragma header

uniform float depth;

void main(){
	float dx = distance(openfl_TextureCoordv.x, 0.5);
    float dy = distance(openfl_TextureCoordv.y, 0.5);
    
    float offset = (dx * 0.2) * dy;
    float dir = (openfl_TextureCoordv.y <= .5) ? 1.0 : -1.0;
    vec2 coords = vec2(openfl_TextureCoordv.x, openfl_TextureCoordv.y + dx * (offset * depth * dir));

    gl_FragColor = flixel_texture2D(bitmap, coords);
}