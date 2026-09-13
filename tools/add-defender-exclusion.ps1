# hunter 项目目录加 Defender 排除（仅此一文件夹，不碰全盘）
# 需管理员 PowerShell；非管理员会报错，照下方"非管理员"提示手动跑
$ErrorActionPreference = "Continue"
# 项目根 = 本脚本所在 tools/ 目录的上一级（clone 到哪就在哪，不写死机器路径）
$dir = Split-Path $PSScriptRoot
try {
    Add-MpPreference -ExclusionPath $dir -Force
    Write-Host "ADDED_OK: $dir"
} catch {
    Write-Host ("ADD_FAIL: " + $_.Exception.Message)
    Write-Host "  非管理员时: 右键'以管理员身份运行' PowerShell，再执行: Add-MpPreference -ExclusionPath '$dir' -Force"
}
# 复核现存排除项
Get-MpPreference | Select-Object -ExpandProperty ExclusionPath | Where-Object { $_ -like "*hunter*" } | ForEach-Object { Write-Host ("CONFIRM: " + $_) }