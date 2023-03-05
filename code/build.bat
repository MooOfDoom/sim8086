@echo off

IF NOT EXIST C:\development\performance-aware\sim8086\build mkdir C:\development\performance-aware\sim8086\build
pushd C:\development\performance-aware\sim8086\build
odin build ..\code -out=sim8086.exe -debug
if %errorlevel% neq 0 (
	echo Error building sim8086: %errorlevel%
	popd
	exit /b 1
)
popd

pushd C:\development\performance-aware\sim8086\data
..\build\sim8086.exe listing_0037_single_register_mov > output_0037_single_register_mov.asm
..\build\sim8086.exe listing_0038_many_register_mov   > output_0038_many_register_mov.asm
..\build\sim8086.exe listing_0039_more_movs           > output_0039_more_movs.asm
..\build\sim8086.exe listing_0040_challenge_movs      > output_0040_challenge_movs.asm
..\build\nasm.exe output_0037_single_register_mov.asm
..\build\nasm.exe output_0038_many_register_mov.asm
..\build\nasm.exe output_0039_more_movs.asm
..\build\nasm.exe output_0040_challenge_movs.asm
fc output_0037_single_register_mov listing_0037_single_register_mov
fc output_0038_many_register_mov   listing_0038_many_register_mov
fc output_0039_more_movs           listing_0039_more_movs
fc output_0040_challenge_movs      listing_0040_challenge_movs
popd