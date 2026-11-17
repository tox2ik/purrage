<#
.SYNOPSIS
  Print the timings the app recorded (%APPDATA%/Purrage/ui-timing.json), ms per action.
.PARAMETER Which
  last (default): the newest session; totals: all kept sessions; a number: that many sessions back (1 = last).
.PARAMETER Filter
  Only actions whose name contains this text (changes, browse.scan, ignorePane).
#>
param([string]$Which = 'last', [string]$Filter = '')

if (-not $Which) { $Which = 'last' }
$file = Join-Path $env:APPDATA 'Purrage/ui-timing.json'
if (-not (Test-Path $file)) { Write-Error "no timings yet: $file (run a debug build: make run)"; exit 1 }
$data = Get-Content $file -Raw | ConvertFrom-Json -DateKind String
$sessions = @($data.sessions)

if ($Which -eq 'totals') {
  $actions = $data.totals
} else {
  $back = if ($Which -eq 'last') { 1 } else { [int]$Which }
  if ($back -lt 1 -or $back -gt $sessions.Count) { Write-Error "only $($sessions.Count) sessions kept"; exit 1 }
  $actions = $sessions[$sessions.Count - $back].actions
}

$rows = @($actions.PSObject.Properties | Where-Object { $_.Name -like "*$Filter*" })
if (-not $rows) { exit 0 }
$w = ($rows.Name | Measure-Object -Maximum -Property Length).Maximum
$fmt = "{0,-$w} {1,6} {2,8} {3,8} {4,8}"
$fmt -f 'action', 'n', 'p50', 'p95', 'max'
foreach ($r in $rows) {
  $v = $r.Value
  $p50 = if ($null -ne $v.p50) { $v.p50 } else { '' }
  $fmt -f $r.Name, $v.n, $p50, $v.p95, $v.max
}
