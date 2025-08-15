@echo off
setlocal ENABLEDELAYEDEXPANSION

:: ==========================================================
:: Qwen2.5-7B-Instruct -> MLC 양자화 -> Android APK 원클릭
:: 앱 이름: QWEN, 아이콘: 흰색 배경 + 검은 Q
:: ==========================================================

:: -------- 기본 경로 설정 --------
set "WORKDIR=%~dp0"
set "LOG=%WORKDIR%oneclick_qwen.log"
set "VENV=%WORKDIR%.venv_mlc"
set "SDKROOT=%WORKDIR%android_sdk"
set "NDKVER=26.3.11579264"
set "API_LEVEL=34"
set "BUILD_TOOLS=34.0.0"
set "MODEL_HF=Qwen/Qwen2.5-7B-Instruct"
set "APK_OUT=%WORKDIR%apk_out"

:: -------- 관리자 권한 확인 --------
whoami /groups | find "S-1-16-12288" >nul
if not %errorlevel%==0 (
  echo [!] 관리자 권한으로 다시 실행 중...
  powershell -NoP -NonI -W Hidden -Command "Start-Process -Verb RunAs -FilePath '%~f0'"
  exit /b
)

:: -------- 로깅 시작 --------
echo ===== START: %date% %time% ===== > "%LOG%"

:: -------- Python 설치 확인 --------
where python >nul 2>&1
if %errorlevel%==0 (
  echo [OK] Python 설치 확인>>"%LOG%"
) else (
  echo [i] Python 미설치. winget으로 설치 시도...
  where winget >nul 2>&1
  if %errorlevel%==0 (
    winget install -e --id Python.Python.3.11 -h --accept-package-agreements --accept-source-agreements >>"%LOG%" 2>&1
  ) else (
    echo [ERR] winget 없음. 수동 설치 필요>>"%LOG%"
    pause
    exit /b
  )
)

:: -------- 가상환경 생성 --------
%PYTHON% -3 -m venv "%VENV%"
call "%VENV%\Scripts\activate.bat"
python -m pip install --upgrade pip >>"%LOG%" 2>&1

:: -------- JDK 설치 --------
where javac >nul 2>&1
if %errorlevel%==0 (
  echo [OK] JDK 확인>>"%LOG%"
) else (
  winget install -e --id Microsoft.OpenJDK.17 -h --accept-package-agreements --accept-source-agreements >>"%LOG%" 2>&1
)

:: -------- Android SDK/NDK 설치 --------
setx ANDROID_HOME "%SDKROOT%" >nul
setx ANDROID_SDK_ROOT "%SDKROOT%" >nul
set "TOOLS_ZIP=%WORKDIR%cmdline-tools.zip"
set "TOOLS_DIR=%SDKROOT%\cmdline-tools\latest"
if not exist "%TOOLS_DIR%\bin\sdkmanager.bat" (
  set "TOOLS_URL=https://dl.google.com/android/repository/commandlinetools-win-11076708_latest.zip"
  powershell -NoP -Command "Invoke-WebRequest -Uri '%TOOLS_URL%' -OutFile '%TOOLS_ZIP%'"
  mkdir "%SDKROOT%\cmdline-tools" 2>nul
  powershell -NoP -Command "Expand-Archive -Force '%TOOLS_ZIP%' '%SDKROOT%\cmdline-tools\_tmp'"
  xcopy /e /y "%SDKROOT%\cmdline-tools\_tmp\cmdline-tools\*" "%TOOLS_DIR%\"
  rmdir /s /q "%SDKROOT%\cmdline-tools\_tmp"
)
set "PATH=%TOOLS_DIR%\bin;%SDKROOT%\platform-tools;%PATH%"
call "%TOOLS_DIR%\bin\sdkmanager.bat" --sdk_root="%SDKROOT%" --licenses < NUL
call "%TOOLS_DIR%\bin\sdkmanager.bat" --sdk_root="%SDKROOT%" "platform-tools" "build-tools;%BUILD_TOOLS%" "platforms;android-%API_LEVEL%" "ndk;%NDKVER%" "cmake;3.22.1"

:: -------- 환경변수 NDK --------
for /f "delims=" %%d in ('dir /b /ad "%SDKROOT%\ndk" 2^>nul') do set "NDK_DETECT=%%d"
set "ANDROID_NDK_HOME=%SDKROOT%\ndk\%NDK_DETECT%"
setx ANDROID_NDK_HOME "%ANDROID_NDK_HOME%" >nul

:: -------- Python 패키지 설치 --------
pip install --upgrade "mlc-ai-nightly" "mlc-llm-nightly" "tvmc-nightly" --extra-index-url https://mlc.ai/wheels

:: -------- 모델 다운로드 및 양자화 --------
mlc_llm download --model "%MODEL_HF%"
mlc_llm convert --model "%MODEL_HF%" --quantization q4f16_1

:: -------- Android 빌드 --------
mlc_llm build android --model "%MODEL_HF%" --quantization q4f16_1

:: -------- 앱 이름 변경 --------
set "MANIFEST=%WORKDIR%\mlc_build\app\src\main\AndroidManifest.xml"
if exist "%MANIFEST%" (
  powershell -Command "(Get-Content '%MANIFEST%') -replace '<application android:label=\".*?\"','<application android:label=\"QWEN\"' | Set-Content '%MANIFEST%'"
)

:: -------- 아이콘 자동 생성 --------
set ICON_DIR=%WORKDIR%\mlc_build\app\src\main\res
for %%size in (48 72 96 144 192) do (
  set "FILE=%ICON_DIR%\mipmap-%%size\ic_launcher.png"
  powershell -Command ^
    "$bmp = New-Object System.Drawing.Bitmap(%%size,%%size);$g=[System.Drawing.Graphics]::FromImage($bmp);$g.Clear([System.Drawing.Color]::White);$font=New-Object System.Drawing.Font('Arial',%%size*0.6);$brush=[System.Drawing.Brushes]::Black;$g.DrawString('Q',$font,[System.Drawing.Brushes]::Black,0,0);$bmp.Save('%FILE%');$g.Dispose();$bmp.Dispose()"
)

:: -------- APK 패키징 --------
mkdir "%APK_OUT%" 2>nul
mlc_llm package android --model "%MODEL_HF%" --quantization q4f16_1 --output "%APK_OUT%"

:: -------- 완료 --------
echo ==========================================================
echo [완료] APK 출력 폴더: %APK_OUT%
echo 로그 파일: %LOG%
pause