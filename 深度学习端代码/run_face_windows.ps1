$ErrorActionPreference = "Stop"

Set-Location $PSScriptRoot
$OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
chcp 65001 > $null
$env:PYTHONUTF8 = "1"
$env:PYTHONIOENCODING = "utf-8"
if (-not $env:CAMERA_STREAM_URL) {
    $cameraCache = Join-Path $PSScriptRoot "camera_stream_url.txt"
    if (Test-Path $cameraCache) {
        $env:CAMERA_STREAM_URL = (Get-Content -Path $cameraCache -First 1).Trim()
    }
}
if (-not $env:CAMERA_STREAM_URL) {
    $env:CAMERA_STREAM_URL = "http://192.168.72.30:81/stream"
}
if (-not $env:CAMERA_READ_TIMEOUT) {
    $env:CAMERA_READ_TIMEOUT = "4"
}
if (-not $env:CAMERA_FRAME_TIMEOUT) {
    $env:CAMERA_FRAME_TIMEOUT = "1.8"
}
if (-not $env:CAMERA_PREFER_SINGLE_FRAME) {
    $env:CAMERA_PREFER_SINGLE_FRAME = "0"
}
if (-not $env:FACE_PROCESS_EVERY_N) {
    $env:FACE_PROCESS_EVERY_N = "3"
}
if (-not $env:FACE_SCALE_FACTOR) {
    $env:FACE_SCALE_FACTOR = "0.5"
}
if (-not $env:FACE_DOWNSCALE_MIN_SIDE) {
    $env:FACE_DOWNSCALE_MIN_SIDE = "360"
}
if (-not $env:FACE_LOW_RES_UPSCALE_FACTOR) {
    $env:FACE_LOW_RES_UPSCALE_FACTOR = "2.0"
}
if (-not $env:FACE_UPSCALE_MAX_SIDE) {
    $env:FACE_UPSCALE_MAX_SIDE = "640"
}
& "E:\conda_env\deep_learning\python.exe" ".\face.py"
