@echo off

set project_root=%~dp0%

pushd %project_root%
odin run src/main.odin -file -out:sokol.exe
popd
