@echo off
setlocal enabledelayedexpansion
rem Get the current directory
set dir="\\JUAN-DESKTOP\Recover"
rem Loop through each file in the directory
for %%f in (%dir%\*) do (
  rem Get the file name
  set name=%%~nxf
  rem Check if the first character is [
  if "!name:~0,1!"=="[" (
    rem Remove the first character
    set newname=!name:~1!
    rem Rename the file
    ren "%%f" "!newname!"
  )
)
