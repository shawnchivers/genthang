@echo off
REM Build Gen Thang for the Tang Nano 20K with the Gowin command-line tools.
REM Requires gw_sh.exe (from the Gowin IDE\bin folder) on your PATH.
gw_sh build.tcl
echo.
echo Bitstream (if successful) is under impl\pnr\genthang_nano20k.fs
