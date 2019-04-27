@echo off

set    zip=pengo.zip
set ifiles=ep1689c.8+ep1690b.7+ep1691b.15+ep1692b.14+ep1693b.21+ep1694b.20+ep5118b.32+ep5119c.31+ep1640.92+ep1695.105+pr1634.88+pr1635.51+pr1636.70+pr1633.78

set  ofile=a.pengo.rom

rem =====================================
setlocal ENABLEDELAYEDEXPANSION

set pwd=%~dp0
echo.
echo.

if EXIST %zip% (

	!pwd!7za x -otmp %zip%
	if !ERRORLEVEL! EQU 0 ( 
		cd tmp

		copy /b/y %ifiles% !pwd!%ofile%
		if !ERRORLEVEL! EQU 0 ( 
			echo.
			echo ** done **
			echo.
			echo Copy "%ofile%" into root of SD card
		)
		cd !pwd!
		rmdir /s /q tmp
	)

) else (

	echo Error: Cannot find "%zip%" file
	echo.
	echo Put "%zip%", "7za.exe" and "%~nx0" into the same directory
)

echo.
echo.
pause
