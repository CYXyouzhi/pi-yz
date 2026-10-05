# 用脚本自身所在目录，避免写死某个人的绝对路径
$log = Join-Path $PSScriptRoot "dev-mode.log"
"=== run at $(Get-Date -Format o) ===" | Out-File $log -Encoding UTF8

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
"IsAdmin: $isAdmin" | Out-File $log -Append -Encoding UTF8

$keyPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock"
try {
    if (-not (Test-Path $keyPath)) {
        New-Item -Path $keyPath -Force | Out-Null
        "key created" | Out-File $log -Append -Encoding UTF8
    }
    New-ItemProperty -Path $keyPath -Name "AllowDevelopmentWithoutDevLicense" `
        -Value 1 -PropertyType DWord -Force | Out-Null
    $v = (Get-ItemProperty -Path $keyPath -Name "AllowDevelopmentWithoutDevLicense").AllowDevelopmentWithoutDevLicense
    "AllowDevelopmentWithoutDevLicense = $v" | Out-File $log -Append -Encoding UTF8
} catch {
    "ERROR: $_" | Out-File $log -Append -Encoding UTF8
}
