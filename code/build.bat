@echo off

IF NOT EXIST C:\development\performance-aware\sim8086\build mkdir C:\development\performance-aware\sim8086\build
pushd C:\development\performance-aware\sim8086\build
odin build ..\code -out=sim8086.exe -o:speed
if %errorlevel% neq 0 (
	echo Error building sim8086: %errorlevel%
	popd
	exit /b 1
)
popd

pushd C:\development\performance-aware\sim8086\data

rem Test disasm

echo === DISASM TEST ===

..\build\sim8086.exe -disasm listing_0037_single_register_mov  > output_0037_single_register_mov.asm
..\build\sim8086.exe -disasm listing_0038_many_register_mov    > output_0038_many_register_mov.asm
..\build\sim8086.exe -disasm listing_0039_more_movs            > output_0039_more_movs.asm
..\build\sim8086.exe -disasm listing_0040_challenge_movs       > output_0040_challenge_movs.asm
..\build\sim8086.exe -disasm listing_0041_add_sub_cmp_jnz      > output_0041_add_sub_cmp_jnz.asm
..\build\sim8086.exe -disasm listing_0042_completionist_decode > output_0042_completionist_decode.asm

..\build\nasm.exe output_0037_single_register_mov.asm
..\build\nasm.exe output_0038_many_register_mov.asm
..\build\nasm.exe output_0039_more_movs.asm
..\build\nasm.exe output_0040_challenge_movs.asm
..\build\nasm.exe output_0041_add_sub_cmp_jnz.asm
..\build\nasm.exe output_0042_completionist_decode.asm

fc output_0037_single_register_mov  listing_0037_single_register_mov
fc output_0038_many_register_mov    listing_0038_many_register_mov
fc output_0039_more_movs            listing_0039_more_movs
fc output_0040_challenge_movs       listing_0040_challenge_movs
fc output_0041_add_sub_cmp_jnz      listing_0041_add_sub_cmp_jnz
fc output_0042_completionist_decode listing_0042_completionist_decode

echo === END DISASM TEST ===

rem Test exec

rem ..\build\sim8086.exe -exec listing_0043_immediate_movs
rem ..\build\sim8086.exe -exec listing_0044_register_movs
rem ..\build\sim8086.exe -exec listing_0045_challenge_register_movs
rem ..\build\sim8086.exe -exec listing_0046_add_sub_cmp
rem ..\build\sim8086.exe -exec listing_0047_challenge_flags
rem ..\build\sim8086.exe -exec listing_0048_ip_register
rem ..\build\sim8086.exe -exec listing_0049_conditional_jumps
rem ..\build\sim8086.exe -exec listing_0050_challenge_jumps
rem ..\build\sim8086.exe -exec listing_0051_memory_mov
rem ..\build\sim8086.exe -exec listing_0052_memory_add_loop
rem ..\build\sim8086.exe -exec listing_0053_add_loop_challenge

popd