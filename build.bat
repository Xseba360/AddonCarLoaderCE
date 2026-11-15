@echo off
rem Builds AddonCarLoaderCE.asi (32-bit) for GTA IV Complete Edition 1.2.0.59.
rem Needs Visual Studio 2022 with the C++ x86 tools.
call "C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvarsall.bat" x86 >nul || exit /b 1
cd /d "%~dp0"
cl /nologo /O2 /MT /EHsc /W3 /LD AddonCarLoader.cpp /Fe:AddonCarLoaderCE.asi /link user32.lib version.lib || exit /b 1
del /q *.obj *.exp *.lib 2>nul
echo Built %~dp0AddonCarLoaderCE.asi
