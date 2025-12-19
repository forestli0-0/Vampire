$root = "C:\Users\15291\Desktop\Vampire"
Set-Location $root
$files = Get-ChildItem -Path . -Recurse -Include *.lua | Where-Object { -not ($_.PSIsContainer) }
$out = New-Object System.Text.StringBuilder
$totalFiles=0; $totalLines=0; $blank=0; $comment=0
$out.AppendLine("Per-file counts (path : total / blank / comment):") | Out-Null
foreach ($f in $files) {
  $content = Get-Content $f.FullName -Raw -ErrorAction SilentlyContinue
  if ($null -eq $content) { continue }
  $lines = $content -split "`n"
  $tf = $lines.Count
  $tb=0; $tc=0
  foreach ($line in $lines) {
    $trim = $line.Trim()
    if ($trim -eq "") { $tb++ }
    elseif ($trim.StartsWith("--")) { $tc++ }
  }
  $totalFiles++; $totalLines += $tf; $blank += $tb; $comment += $tc
  $out.AppendLine("$($f.FullName): $tf / $tb / $tc") | Out-Null
}
$code = $totalLines - $blank - $comment
$out.AppendLine("") | Out-Null
$out.AppendLine("SUMMARY:") | Out-Null
$out.AppendLine("Files: $totalFiles") | Out-Null
$out.AppendLine("Total lines: $totalLines") | Out-Null
$out.AppendLine("Blank lines: $blank") | Out-Null
$out.AppendLine("Comment lines (starting with --): $comment") | Out-Null
$out.AppendLine("Approx. code lines: $code") | Out-Null
$out.ToString() | Out-File -FilePath tools/luacount_output.txt -Encoding UTF8
