@echo off
echo [DUTCH QA] Starting Headless Logic Verification...
C:\Users\emiso\Downloads\godot.exe --headless -s qa_pipeline.gd %*
if %ERRORLEVEL% EQU 0 (
    echo [DUTCH QA] SUCCESS: All logic phases verified.
) else (
    echo [DUTCH QA] FAILURE: Logic verification failed with exit code %ERRORLEVEL%.
)
pause
