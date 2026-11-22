<#
.SYNOPSIS
  把 dsh-session-manager 的「全选 200 上限」热修补丁重新打进 node_modules。
.DESCRIPTION
  插件升级 / pnpm install 之后 lib/*.js 会被还原成官方版，全选又会卡在 200 条。
  本脚本把 patched/lib/ 下三个改好的文件覆盖回去，并先断开硬链接（避免污染 pnpm store）。
.NOTES
  目标版本 0.7.8。若插件升级到新版本，先比对上游是否已改动同样的位置再决定是否套用。
#>
param(
  [string]$Target = "C:\Users\duma520\.dsh\profiles\desktop\node_modules\dsh-session-manager"
)
$ErrorActionPreference = "Stop"
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$src  = Join-Path $here "patched\lib"
$dst  = Join-Path $Target "lib"

if (-not (Test-Path $dst)) { throw "找不到插件目录：$dst" }

$ver = (Get-Content (Join-Path $Target "package.json") -Raw | ConvertFrom-Json).version
Write-Host "目标插件版本：$ver"

$files = @("client.js", "index.js", "annotation-store.js")
foreach ($f in $files) {
  $d = Join-Path $dst $f
  $s = Join-Path $src $f
  if (-not (Test-Path $s)) { throw "补丁源缺失：$s" }
  # 断链：先复制到临时文件，删除原文件，再改名覆盖
  $tmp = "$d.patchtmp"
  Copy-Item $s $tmp -Force
  if (Test-Path $d) { Remove-Item $d -Force }
  Move-Item $tmp $d -Force
  Write-Host "已写入 $f"
}

foreach ($f in $files) {
  $d = Join-Path $dst $f
  node --check $d
  if ($LASTEXITCODE -ne 0) { throw "语法检查失败：$f" }
  Write-Host "语法 OK：$f"
}

Write-Host ""
Write-Host "补丁已应用。请在 DSH 界面按 F5 刷新（客户端插件改动需要刷新页面才生效）。"
