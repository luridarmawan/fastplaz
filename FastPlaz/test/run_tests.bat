@echo off
rem Compile and run the FastPlaz library unit tests with instantfpc.
rem Usage: run_tests.bat [runner options]   (default: -a)

setlocal
cd /d "%~dp0"

where instantfpc >nul 2>nul
if errorlevel 1 set "PATH=C:\lazarus\fpc\3.2.2\bin\x86_64-win64;%PATH%"

rem instantfpc does not accept -Fu paths on its command line, pass them here.
rem -B: always rebuild, the cache only tracks the main program source.
rem The unit paths mirror tools\fastplaz_runtime.lpk.
set "INSTANTFPCOPTIONS=-B -Fi.. -Fu..\..\tools\src -Fu..\src\systems -Fu..\src\library -Fu..\src\vendor -Fu..\src\app\about -Fu..\src\model -Fu..\src\util -Fu..\src\helper"

if "%~1"=="" (
  instantfpc fastplaz_test.lpr -a
) else (
  instantfpc fastplaz_test.lpr %*
)
exit /b %errorlevel%
