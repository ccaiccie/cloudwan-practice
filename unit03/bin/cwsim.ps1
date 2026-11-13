#!/usr/bin/env pwsh
# cwsim.ps1 - offline simulation of AWS Cloud WAN routing-policy evaluation with BGP communities (PowerShell 7).
# Teaching aid only: it reads JSON files and prints results. It never calls AWS. Output matches cwsim.sh line for line.
[CmdletBinding()]
param(
  [Parameter(Mandatory)][string]$Policy,
  [string]$Routes, [string]$Names, [string]$Label, [string]$Edge,
  [ValidateSet('inbound', 'outbound')][string]$Direction,
  [switch]$ViaDx, [switch]$ViaDxBefore, [switch]$Lint
)
Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
$Doc = Get-Content -Raw -LiteralPath $Policy | ConvertFrom-Json -AsHashtable
$Reserved = @(7224, 10124, 17493, 9059, 4001)

function Get-Prop($o, $k, $default = $null) { if ($null -ne $o -and $o.Contains($k) -and $null -ne $o[$k]) { $o[$k] } else { $default } }
function ConvertTo-N([string]$ip) { $o = $ip.Split('.') | ForEach-Object { [uint64]$_ }; $o[0] * 16777216 + $o[1] * 65536 + $o[2] * 256 + $o[3] }
function Get-Pfx([string]$p) { $a = $p.Split('/'); @{ n = (ConvertTo-N $a[0]); l = [int]$a[1] } }
function Get-Blk([uint64]$n, [int]$l) { if ($l -eq 0) { 0 } else { [math]::Floor($n / [math]::Pow(2, 32 - $l)) } }
function Test-InCidr([string]$prefix, [string]$cidr) { $r = Get-Pfx $prefix; $k = Get-Pfx $cidr; ($r.l -gt $k.l) -and ((Get-Blk $r.n $k.l) -eq (Get-Blk $k.n $k.l)) }
function Test-InCore([int64]$a) {
  foreach ($s in @(Get-Prop (Get-Prop $Doc 'core-network-configuration' @{}) 'asn-ranges' @())) { $r = $s.Split('-'); if ($a -ge [int64]$r[0] -and $a -le [int64]$r[1]) { return $true } }
  $false }
function Get-CKind([string]$c) {
  if ($c -match '^[0-9]+:[0-9]+$') { $v = $c.Split(':') | ForEach-Object { [int64]$_ }; if ($v[0] -le 65535 -and $v[1] -le 65535) { 'standard' } else { 'invalid' } }
  elseif ($c -match '^[0-9]+:[0-9]+:[0-9]+$') { 'large' } else { 'extended' } }
function Get-Vals($v) { if ($v -is [System.Collections.IList]) { @($v) } else { @("$v".Split(',') | ForEach-Object { $_.Trim() }) } }
function Show($x) { if ($null -eq $x) { '-' } else { "$x" } }
function Get-Pols { @(Get-Prop $Doc 'routing-policies' @()) }

function Get-SelectedPolicies {
  if ($Names) { $n = $Names.Split(','); $ps = @(Get-Pols | Where-Object { $n -contains $_['routing-policy-name'] }) }
  else {
    $n = @(); foreach ($r in @(Get-Prop $Doc 'attachment-routing-policy-rules' @()) | Sort-Object { $_['rule-number'] }) {
      if (-not (@($r['conditions']) | Where-Object { $_['type'] -eq 'routing-policy-label' -and $_['value'] -eq $Label })) { continue }
      $el = Get-Prop $r 'edge-locations'; if ($null -ne $el -and -not (@($el) -contains $Edge)) { continue }
      $n += @($r['action']['associate-routing-policies']) }
    $ps = @(Get-Pols | Where-Object { $n -contains $_['routing-policy-name'] -and $_['routing-policy-direction'] -eq $Direction }) }
  @($ps | Sort-Object { $_['routing-policy-number'] })
}
function Test-Cond($c, $r) {
  $v = $c['value']
  switch ($c['type']) {
    'prefix-equals' { return $r.prefix -eq $v }
    'prefix-in-cidr' { return (Test-InCidr $r.prefix $v) }
    'asn-in-as-path' { return $r.path -contains [int64]$v }
    'community-in-list' { foreach ($x in Get-Vals $v) { if ($r.comm -contains $x) { return $true } }; return $false }
    'med-equals' { return $r.med -eq [int64]$v }
    default { throw "match condition $($c['type']) is not simulated" } }
}
function Test-Match($rule, $r) {
  $d = $rule['rule-definition']; $m = @($d['match-conditions'] | ForEach-Object { Test-Cond $_ $r })
  if ((Get-Prop $d 'condition-logic' 'and') -eq 'or') { $m -contains $true } else { -not ($m -contains $false) }
}
function Invoke-Act($a, $r) {
  switch ($a['type']) {
    'set-local-preference' { $r.lp = [int64]$a['value'] }
    'set-med' { $r.med = [int64]$a['value'] }
    'prepend-asn-list' { $r.path = @(@(Get-Vals $a['value'] | ForEach-Object { [int64]$_ }) + $r.path) }
    'remove-asn-list' { $x = @(Get-Vals $a['value'] | ForEach-Object { [int64]$_ }); $r.path = @($r.path | Where-Object { $x -notcontains $_ }) }
    'add-community' { foreach ($c in Get-Vals $a['value']) { if ($r.comm -notcontains $c) { $r.comm = @($r.comm) + $c } } }
    'remove-community' { $x = @(Get-Vals $a['value']); $r.comm = @($r.comm | Where-Object { $x -notcontains $_ }) }
    default { throw "action $($a['type']) is not simulated" } }
}
function Format-Line($s) {
  $r = $s.r
  if ($s.verdict -eq 'DROP') { return "DROP  $($r.prefix) by=$($s.by)" }
  $mods = if ($s.mods.Count) { ' changed-by=' + ($s.mods -join ',') } else { '' }
  $path = if ($r.path.Count) { $r.path -join ' ' } else { '-' }; $comm = if ($r.comm.Count) { $r.comm -join ',' } else { '-' }
  "ALLOW $($r.prefix) by=$($s.by)$mods as-path=$path med=$(Show $r.med) lp=$(Show $r.lp) communities=$comm"
}

if ($Lint) {
  $out = [System.Collections.Generic.List[string]]::new()
  $pols = Get-Pols
  if ($pols.Count -gt 0 -and (Get-Prop $Doc 'version') -ne '2025.11') { $out.Add("ERROR version is $(Get-Prop $Doc 'version' 'missing'); routing policies need 2025.11") }
  foreach ($p in $pols) {
    $n = $p['routing-policy-name']
    if ($n -cnotmatch '^[A-Za-z0-9]{1,100}$') { $out.Add("ERROR policy name ${n}: letters and digits only, max 100") }
    if (@('inbound', 'outbound') -notcontains $p['routing-policy-direction']) { $out.Add("ERROR ${n}: direction must be inbound or outbound") }
    if (-not ($p['routing-policy-number'] -ge 1 -and $p['routing-policy-number'] -le 9999)) { $out.Add("ERROR ${n}: routing-policy-number must be 1-9999") }
    $nums = @($p['routing-policy-rules'] | ForEach-Object { $_['rule-number'] }); if (@($nums | Select-Object -Unique).Count -ne $nums.Count) { $out.Add("ERROR ${n}: duplicate rule-number") }
    $rs = @($p['routing-policy-rules'] | Sort-Object { $_['rule-number'] })
    foreach ($r in $rs) {
      $d = $r['rule-definition']; $vals = @()
      foreach ($c in $d['match-conditions']) { if ($c['type'] -eq 'community-in-list') { $vals += Get-Vals $c['value'] } }
      if (@('add-community', 'remove-community') -contains $d['action']['type']) { $vals += Get-Vals $d['action']['value'] }
      foreach ($c in $vals) {
        if ((Get-CKind $c) -ne 'standard') { $out.Add("ERROR $n#$($r['rule-number']): $c is not a standard community (ASN:value)") }
        elseif (Test-InCore ([int64]$c.Split(':')[0])) { $out.Add("ERROR $n#$($r['rule-number']): $c uses an ASN inside the core network asn-ranges") }
        elseif ($Reserved -contains [int64]$c.Split(':')[0]) { $out.Add("WARN  $n#$($r['rule-number']): $c starts with an AWS-reserved ASN; avoid it (Direct Connect removes these from routes it receives)") } } }
    for ($i = 0; $i -lt $rs.Count - 1; $i++) {
      $d = $rs[$i]['rule-definition']
      if (@('drop', 'allow') -contains $d['action']['type'] -and (@($d['match-conditions']) | Where-Object { $_['type'] -eq 'prefix-in-cidr' -and $_['value'] -eq '0.0.0.0/0' })) {
        $out.Add("WARN  $n#$($rs[$i]['rule-number']): terminal catch-all before later rules; rules after it never run for matched routes") } }
    foreach ($r in $rs) { if ($r['rule-definition']['action']['type'] -eq 'summarize' -and $p['routing-policy-direction'] -ne 'outbound') { $out.Add("ERROR $n#$($r['rule-number']): summarize is outbound only") } }
  }
  $polNames = @($pols | ForEach-Object { $_['routing-policy-name'] })
  $edges = @(@(Get-Prop (Get-Prop $Doc 'core-network-configuration' @{}) 'edge-locations' @()) | ForEach-Object { $_['location'] })
  foreach ($r in @(Get-Prop $Doc 'attachment-routing-policy-rules' @())) {
    foreach ($x in $r['action']['associate-routing-policies']) { if ($polNames -notcontains $x) { $out.Add("ERROR attachment rule references unknown routing policy $x") } }
    foreach ($e in @(Get-Prop $r 'edge-locations' @())) { if ($edges -notcontains $e) { $out.Add("ERROR attachment rule edge-location $e is not in core-network-configuration") } } }
  foreach ($a in @(Get-Prop $Doc 'segment-actions' @())) {
    $refs = @(Get-Prop $a 'routing-policy-names' @()) + @(Get-Prop (Get-Prop $a 'edge-location-association' @{}) 'routing-policy-names' @())
    foreach ($x in $refs) { if ($polNames -notcontains $x) { $out.Add("ERROR segment action references unknown routing policy $x") } } }
  if ($out.Count -eq 0) { 'LINT OK' } else { $out }
  exit ([int](@($out | Where-Object { $_.StartsWith('ERROR') }).Count -gt 0))
}

if (-not $Routes -or (-not $Names -and -not ($Label -and $Edge -and $Direction))) { throw 'Use -Routes with -Names, or with -Label, -Edge and -Direction. See README.md.' }
$RouteDoc = Get-Content -Raw -LiteralPath $Routes | ConvertFrom-Json -AsHashtable
$ps = @(Get-SelectedPolicies)
if ($ps.Count -eq 0) { 'policies: (none)' } else { 'policies: ' + (($ps | ForEach-Object { "$($_['routing-policy-name'])(#$($_['routing-policy-number']) $($_['routing-policy-direction']))" }) -join ' ') }
foreach ($x in $RouteDoc['routes']) {
  $r = [pscustomobject]@{ prefix = $x['prefix']; path = @(Get-Prop $x 'as-path' @() | ForEach-Object { [int64]$_ }); med = (Get-Prop $x 'med'); lp = (Get-Prop $x 'local-pref'); comm = @(Get-Prop $x 'communities' @()) }
  if ($ViaDx -or $ViaDxBefore) {
    $keep = @()
    foreach ($c in $r.comm) {
      if ($ViaDxBefore) { "dx  $($r.prefix) removed $c (before Nov 2026: not carried to Cloud WAN)"; continue }
      $k = Get-CKind $c
      if ($k -eq 'large') { "dx  $($r.prefix) removed $c (large community)" }
      elseif ($k -eq 'extended') { "dx  $($r.prefix) removed $c (extended community)" }
      elseif ($k -eq 'invalid') { "dx  $($r.prefix) removed $c (not a valid community)" }
      elseif ($Reserved -contains [int64]$c.Split(':')[0]) { "dx  $($r.prefix) removed $c (AWS-reserved ASN)" }
      else { $keep += $c } }
    $r.comm = $keep }
  $s = [pscustomobject]@{ r = $r; verdict = $null; by = 'default'; mods = [System.Collections.Generic.List[string]]::new() }
  :outer foreach ($p in $ps) {
    foreach ($rule in @($p['routing-policy-rules'] | Sort-Object { $_['rule-number'] })) {
      if (-not (Test-Match $rule $s.r)) { continue }
      $a = $rule['rule-definition']['action']; $id = "$($p['routing-policy-name'])#$($rule['rule-number'])"
      if ($a['type'] -eq 'drop') { $s.verdict = 'DROP'; $s.by = $id; break outer }
      if ($a['type'] -eq 'allow') { $s.verdict = 'ALLOW'; $s.by = $id; break outer }
      Invoke-Act $a $s.r; $s.mods.Add($id) } }
  Format-Line $s
}
