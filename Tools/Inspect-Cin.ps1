<#
.SYNOPSIS
  在 Windows 本機檢查 .cin 碼表的格式資訊（Spike 0.13）。
.DESCRIPTION
  只輸出統計數字與檔頭設定，不輸出碼表內容。碼表請勿放進專案資料夾。
.EXAMPLE
  powershell -ExecutionPolicy Bypass -File Tools\Inspect-Cin.ps1 -Path "D:\私人\liu.cin"
#>
param(
    [Parameter(Mandatory = $true)]
    [string]$Path
)

$ErrorActionPreference = 'Stop'
$bytes = [System.IO.File]::ReadAllBytes((Resolve-Path -LiteralPath $Path))

# 判斷編碼：BOM → 嚴格 UTF-8 → Big5
$encodingName = $null
$text = $null
if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
    $encodingName = 'UTF-8 (含 BOM)'
    $text = [System.Text.Encoding]::UTF8.GetString($bytes, 3, $bytes.Length - 3)
} else {
    try {
        $strictUtf8 = New-Object System.Text.UTF8Encoding($false, $true)
        $text = $strictUtf8.GetString($bytes)
        $encodingName = 'UTF-8'
    } catch {
        $text = [System.Text.Encoding]::GetEncoding(950).GetString($bytes)
        $encodingName = 'Big5 (CP950)'
    }
}

$header = @{}
$section = ''
$keynameCount = 0
$chardefCount = 0
$hiraganaCount = 0
$katakanaCount = 0
$maxCodeLength = 0

foreach ($rawLine in ($text -split "`r?`n")) {
    $line = $rawLine.Trim()
    if ($line -eq '' -or $line.StartsWith('#')) { continue }

    if ($line -match '^%(keyname|chardef)\s+begin') { $section = $Matches[1]; continue }
    if ($line -match '^%(keyname|chardef)\s+end')   { $section = ''; continue }

    if ($section -eq '' -and $line -match '^%(\w+)\s+(.+)$') {
        $header[$Matches[1]] = $Matches[2].Trim()
        continue
    }

    $parts = $line -split '\s+', 2
    if ($parts.Count -lt 2) { continue }

    if ($section -eq 'keyname') {
        $keynameCount++
    } elseif ($section -eq 'chardef') {
        $chardefCount++
        $code = $parts[0]
        $value = $parts[1]
        if ($code.Length -gt $maxCodeLength) { $maxCodeLength = $code.Length }
        if ($code.EndsWith(',') -and $value -match '^[\u3041-\u309F]+$') { $hiraganaCount++ }
        if ($code.EndsWith('.') -and $value -match '^[\u30A0-\u30FF]+$') { $katakanaCount++ }
    }
}

Write-Output "檔案大小      : $([math]::Round($bytes.Length / 1KB, 1)) KB"
Write-Output "編碼          : $encodingName"
Write-Output "%ename        : $($header['ename'])"
Write-Output "%cname        : $($header['cname'])"
Write-Output "%selkey       : $($header['selkey'])"
Write-Output "其他檔頭      : $((($header.Keys | Where-Object { $_ -notin 'ename','cname','selkey' }) -join ', '))"
Write-Output "%keyname 數量 : $keynameCount"
Write-Output "%chardef 數量 : $chardefCount"
Write-Output "最長碼長      : $maxCodeLength"
Write-Output "平假名(碼以 , 結尾) : $hiraganaCount"
Write-Output "片假名(碼以 . 結尾) : $katakanaCount"
