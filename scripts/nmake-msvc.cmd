@echo off
rem Build pgvector with MSVC x64: nmake /F Makefile.win, then record vector.dll's and postgres.exe's imports.
rem Usage: nmake-msvc.cmd <pgvector_src> <pgroot>
setlocal
set "VSWHERE=%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe"
for /f "usebackq delims=" %%i in (`"%VSWHERE%" -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath`) do set "VS=%%i"
if not defined VS (echo no Visual Studio with the x64 C++ tools & exit /b 1)
call "%VS%\VC\Auxiliary\Build\vcvars64.bat" >nul || exit /b 1
cl 2>&1 | findstr /c:"Version"
cd /d "%~1" || exit /b 1
rem Makefile.win reads PGROOT from the environment and quotes the paths it builds from it.
set "PGROOT=%~2"
nmake /nologo /F Makefile.win || exit /b 1
dumpbin /nologo /dependents vector.dll > vector.deps || exit /b 1
dumpbin /nologo /dependents "%~2\bin\postgres.exe" > postgres.deps || exit /b 1
