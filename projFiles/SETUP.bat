@echo off
cd ../
haxelib install hxpkg
haxelib run hxpkg install

cd .haxelib/lime/git/
git submodule sync --recursive
git submodule update --init --recursive --force
cd ../../../
haxelib run lime rebuild cpp -release
pause
