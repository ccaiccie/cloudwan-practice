#!/usr/bin/env pwsh
# Runs every case in tests/cases.txt through bin/cwsim.ps1 and compares the output with tests/expected/<name>.txt.
Set-Location (Join-Path $PSScriptRoot '..')
$map = @{ '--policy' = '-Policy'; '--routes' = '-Routes'; '--names' = '-Names'; '--label' = '-Label'; '--edge' = '-Edge'; '--direction' = '-Direction'; '--via-dx' = '-ViaDx'; '--via-dx-before' = '-ViaDxBefore'; '--lint' = '-Lint' }
$pass = 0; $fail = 0
foreach ($line in Get-Content tests/cases.txt) {
  if (-not $line.Trim() -or $line.TrimStart().StartsWith('#')) { continue }
  $name, $args0 = $line.Split('|', 2); $name = $name.Trim()
  $toks = @($args0.Trim() -split '\s+' | ForEach-Object { if ($map.ContainsKey($_)) { $map[$_] } else { $_ } })
  $got = (& pwsh -NoProfile -File bin/cwsim.ps1 @toks 2>&1 | Out-String).TrimEnd() -replace "`r", ''
  $want = (Get-Content -Raw "tests/expected/$name.txt").TrimEnd() -replace "`r", ''
  if ($got -ceq $want) { $pass++; "PASS $name" }
  else { $fail++; "FAIL $name"; Compare-Object ($want -split "`n") ($got -split "`n") | ForEach-Object { "     $($_.SideIndicator) $($_.InputObject)" } }
}
"pwsh: $pass passed, $fail failed"
exit [int]($fail -gt 0)
