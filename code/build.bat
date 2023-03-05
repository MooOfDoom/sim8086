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
..\build\sim8086.exe listing_0038_many_register_mov > output_0038_many_register_mov.asm
..\build\nasm.exe output_0037_single_register_mov.asm
..\build\nasm.exe output_0038_many_register_mov.asm
fc output_0037_single_register_mov listing_0037_single_register_mov
fc output_0038_many_register_mov listing_0038_many_register_mov
popd