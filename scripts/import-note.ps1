param(
    [Parameter(Mandatory = $true)]
    [string]$Source,

    [string]$Title = "",

    [string]$Date = (Get-Date -Format "yyyy-MM-dd"),
    [string]$Status = "进行中",
    [string]$Tags = "",
    [ValidateSet("notes", "experiments", "resources", "paths")]
    [string]$Category = "notes",
    [int]$MaxImageWidth = 1400,
    [int]$JpegQuality = 78,
    [int]$TargetImageKB = 350,
    [int]$MinJpegQuality = 52,
    [switch]$Commit,
    [switch]$Push
)

$ErrorActionPreference = "Stop"

function Get-RepoRoot {
    $scriptDir = Split-Path -Parent $MyInvocation.ScriptName
    if ($scriptDir) {
        $rootFromScript = Split-Path -Parent $scriptDir
        if ((Test-Path -LiteralPath (Join-Path $rootFromScript ".git")) -or (Test-Path -LiteralPath (Join-Path $rootFromScript "README.md"))) {
            Set-Location -LiteralPath $rootFromScript
            return $rootFromScript
        }
    }

    $root = git rev-parse --show-toplevel 2>$null
    if (-not $root) {
        throw "请在 Git 仓库中运行此脚本。"
    }
    return $root.Trim()
}

function Convert-ToSlug {
    param([string]$Text)

    $slug = $Text.ToLowerInvariant()
    $slug = $slug -replace "[^\p{L}\p{Nd}]+", "-"
    $slug = $slug.Trim("-")
    if ($slug.Length -gt 48) {
        $slug = $slug.Substring(0, 48).Trim("-")
    }
    if ([string]::IsNullOrWhiteSpace($slug)) {
        $slug = "untitled-note"
    }
    return $slug
}

function Get-TitleFromMarkdown {
    param(
        [string]$MarkdownPath,
        [string]$Fallback
    )

    $lines = Get-Content -LiteralPath $MarkdownPath -Encoding UTF8
    foreach ($line in $lines) {
        if ($line -match '^\s*#\s+(.+?)\s*$') {
            return $matches[1].Trim()
        }
    }

    $name = [System.IO.Path]::GetFileNameWithoutExtension($Fallback)
    $name = $name -replace "\s+[0-9a-f]{32}$", ""
    return $name.Trim()
}

function Convert-ToSafeFileName {
    param(
        [string]$Name,
        [int]$Index
    )

    $base = [System.IO.Path]::GetFileNameWithoutExtension($Name).ToLowerInvariant()
    $ext = [System.IO.Path]::GetExtension($Name).ToLowerInvariant()
    $base = $base -replace "[^\p{L}\p{Nd}]+", "-"
    $base = $base.Trim("-")
    if ([string]::IsNullOrWhiteSpace($base)) {
        $base = "image"
    }
    if ($base.Length -gt 36) {
        $base = $base.Substring(0, 36).Trim("-")
    }
    return ("{0:D2}-{1}{2}" -f $Index, $base, $ext)
}

function Save-CompressedImage {
    param(
        [string]$InputPath,
        [string]$OutputPath,
        [int]$MaxWidth,
        [int]$Quality
    )

    Add-Type -AssemblyName System.Drawing

    $image = [System.Drawing.Image]::FromFile($InputPath)
    try {
        $targetWidth = $image.Width
        $targetHeight = $image.Height
        if ($image.Width -gt $MaxWidth) {
            $targetWidth = $MaxWidth
            $targetHeight = [int]([double]$image.Height * ($MaxWidth / [double]$image.Width))
        }

        $currentWidth = $targetWidth
        $currentHeight = $targetHeight
        $currentQuality = $Quality
        $targetBytes = $TargetImageKB * 1024
        $codec = [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() |
            Where-Object { $_.MimeType -eq "image/jpeg" } |
            Select-Object -First 1

        while ($true) {
            $bitmap = New-Object System.Drawing.Bitmap($currentWidth, $currentHeight)
            try {
                $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
                try {
                    $graphics.Clear([System.Drawing.Color]::White)
                    $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
                    $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
                    $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
                    $graphics.DrawImage($image, 0, 0, $currentWidth, $currentHeight)
                }
                finally {
                    $graphics.Dispose()
                }

                $encoder = [System.Drawing.Imaging.Encoder]::Quality
                $encoderParams = New-Object System.Drawing.Imaging.EncoderParameters(1)
                $encoderParams.Param[0] = New-Object System.Drawing.Imaging.EncoderParameter($encoder, [long]$currentQuality)
                $bitmap.Save($OutputPath, $codec, $encoderParams)
                $encoderParams.Dispose()

                $size = (Get-Item -LiteralPath $OutputPath).Length
                if ($size -le $targetBytes -or ($currentQuality -le $MinJpegQuality -and $currentWidth -le 900)) {
                    break
                }
                if ($currentQuality -gt $MinJpegQuality) {
                    $currentQuality = [Math]::Max($MinJpegQuality, $currentQuality - 8)
                }
                else {
                    $currentWidth = [Math]::Max(900, [int]($currentWidth * 0.85))
                    $currentHeight = [int]([double]$image.Height * ($currentWidth / [double]$image.Width))
                }
            }
            finally {
                $bitmap.Dispose()
            }
        }
    }
    finally {
        $image.Dispose()
    }
}

function Copy-NoteImage {
    param(
        [string]$ImagePath,
        [string]$AssetsDir,
        [hashtable]$Copied,
        [ref]$Counter
    )

    $resolved = (Resolve-Path -LiteralPath $ImagePath).Path
    if ($Copied.ContainsKey($resolved)) {
        return $Copied[$resolved]
    }

    $ext = [System.IO.Path]::GetExtension($resolved).ToLowerInvariant()
    if ($ext -in @(".png", ".jpg", ".jpeg")) {
        $safeName = Convert-ToSafeFileName -Name (Split-Path -Leaf $resolved) -Index $Counter.Value
        $safeName = [System.IO.Path]::ChangeExtension($safeName, ".jpg")
        $Counter.Value++
        $dest = Join-Path $AssetsDir $safeName
        Save-CompressedImage -InputPath $resolved -OutputPath $dest -MaxWidth $MaxImageWidth -Quality $JpegQuality
    }
    else {
        $safeName = Convert-ToSafeFileName -Name (Split-Path -Leaf $resolved) -Index $Counter.Value
        $Counter.Value++
        $dest = Join-Path $AssetsDir $safeName
        Copy-Item -LiteralPath $resolved -Destination $dest -Force
    }

    $Copied[$resolved] = "assets/$safeName"
    return $Copied[$resolved]
}

function Update-IndexFile {
    param(
        [string]$Path,
        [string]$Header,
        [string]$Row
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        Set-Content -LiteralPath $Path -Value $Header -Encoding UTF8
    }

    $content = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    if ($content -notmatch [regex]::Escape($Row)) {
        if ($content.Trim().Length -eq 0) {
            $content = $Header
        }
        $content = $content.TrimEnd() + "`n" + $Row + "`n"
        Set-Content -LiteralPath $Path -Value $content -Encoding UTF8
    }
}

function Update-NotesIndex {
    param(
        [string]$Path,
        [string]$Year,
        [string]$Row
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        $initial = @"
# Notes

这里存放地理可视化学习过程中的笔记、实验复盘和问题记录。
"@
        Set-Content -LiteralPath $Path -Value $initial -Encoding UTF8
    }

    $content = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    if ($content -match [regex]::Escape($Row)) {
        return
    }

    if ($content -notmatch "(?m)^##\s+$Year\s*$") {
        $section = @"

## $Year

| 日期 | 标题 | 状态 | 主题 |
|---|---|---|---|
"@
        $content = $content.TrimEnd() + $section
    }

    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.AddRange(($content -split "`r?`n"))
    $yearLine = -1
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match "^##\s+$([regex]::Escape($Year))\s*$") {
            $yearLine = $i
            break
        }
    }

    if ($yearLine -ge 0) {
        $insertAt = $yearLine + 1
        while ($insertAt -lt $lines.Count -and $lines[$insertAt] -notmatch '^\|---\|---\|---\|---\|') {
            $insertAt++
        }
        if ($insertAt -lt $lines.Count) {
            $lines.Insert($insertAt + 1, $Row)
        }
    }

    Set-Content -LiteralPath $Path -Value ($lines -join "`n") -Encoding UTF8
}

function Update-DatedCategoryIndex {
    param(
        [string]$Path,
        [string]$CategoryTitle,
        [string]$Year,
        [string]$Row
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        $initial = @"
# $CategoryTitle

| 日期 | 标题 | 状态 | 主题 |
|---|---|---|---|
"@
        Set-Content -LiteralPath $Path -Value $initial -Encoding UTF8
    }

    $content = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    if ($content -match [regex]::Escape($Row)) {
        return
    }
    if ($content -notmatch "\| 日期 \| 标题 \| 状态 \| 主题 \|") {
        $content = $content.TrimEnd() + @"

| 日期 | 标题 | 状态 | 主题 |
|---|---|---|---|
"@
    }
    $pattern = "(?ms)(\| 日期 \| 标题 \| 状态 \| 主题 \|`r?`n\|---\|---\|---\|---\|`r?`n)"
    $newContent = [regex]::Replace($content, $pattern, "`${1}$Row`n", 1)
    Set-Content -LiteralPath $Path -Value $newContent -Encoding UTF8
}

function New-ShortImportTempDir {
    $base = "C:\tmp"
    try {
        if (-not (Test-Path -LiteralPath $base)) {
            New-Item -ItemType Directory -Force -Path $base | Out-Null
        }
    }
    catch {
        $base = $env:TEMP
    }

    $dir = Join-Path $base ("gli-" + [guid]::NewGuid().ToString("N").Substring(0, 8))
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    return $dir
}

function Expand-ZipSafely {
    param(
        [string]$ZipPath,
        [string]$Destination
    )

    New-Item -ItemType Directory -Force -Path $Destination | Out-Null

    try {
        Expand-Archive -LiteralPath $ZipPath -DestinationPath $Destination -Force
    }
    catch {
        Write-Warning "Expand-Archive failed; falling back to tar for: $ZipPath"
        & tar -xf $ZipPath -C $Destination
        if ($LASTEXITCODE -ne 0) {
            throw "解压失败: $ZipPath"
        }
    }
}

function Expand-NestedZipFiles {
    param(
        [string]$Root
    )

    $round = 0
    while ($round -lt 5) {
        $round++
        $zipFiles = Get-ChildItem -LiteralPath $Root -Recurse -File -Filter *.zip | Sort-Object FullName

        if (-not $zipFiles -or $zipFiles.Count -eq 0) {
            return
        }

        $index = 0
        foreach ($zip in $zipFiles) {
            $index++
            $target = Join-Path $zip.DirectoryName ("__z" + $round + "_" + $index)
            if (Test-Path -LiteralPath $target) {
                continue
            }
            Expand-ZipSafely -ZipPath $zip.FullName -Destination $target
        }
    }
}

$repoRoot = Get-RepoRoot
Set-Location -LiteralPath $repoRoot
$sourcePath = Resolve-Path -LiteralPath $Source
$cleanupDir = $null

if (-not (Test-Path -LiteralPath $sourcePath.Path -PathType Container)) {
    $ext = [System.IO.Path]::GetExtension($sourcePath.Path).ToLowerInvariant()
    if ($ext -ne ".zip") {
        throw "Source 必须是 Notion 导出的 .zip、或包含 Markdown 的文件夹。"
    }
    $cleanupDir = New-ShortImportTempDir
    Expand-ZipSafely -ZipPath $sourcePath.Path -Destination $cleanupDir
    Expand-NestedZipFiles -Root $cleanupDir
    $sourceDir = $cleanupDir
}
else {
    $sourceDir = $sourcePath.Path
    Expand-NestedZipFiles -Root $sourceDir
}

$year = ([datetime]::ParseExact($Date, "yyyy-MM-dd", $null)).ToString("yyyy")

$markdown = Get-ChildItem -LiteralPath $sourceDir -Recurse -File |
    Where-Object { $_.Extension.ToLowerInvariant() -in @(".md", ".markdown") } |
    Where-Object { $_.FullName -notmatch "\\assets\\" } |
    Sort-Object FullName |
    Select-Object -First 1

if (-not $markdown) {
    throw "没有在 Source 中找到 Markdown 文件。"
}

if ([string]::IsNullOrWhiteSpace($Title)) {
    $Title = Get-TitleFromMarkdown -MarkdownPath $markdown.FullName -Fallback $markdown.Name
}

$slug = Convert-ToSlug -Text $Title
$entryDir = Join-Path $repoRoot "$Category\$year\$Date-$slug"
$assetsDir = Join-Path $entryDir "assets"

New-Item -ItemType Directory -Force -Path $assetsDir | Out-Null

$copiedImages = @{}
$imageCounter = 1

$content = Get-Content -LiteralPath $markdown.FullName -Raw -Encoding UTF8
$markdownDir = Split-Path -Parent $markdown.FullName

$content = [regex]::Replace($content, '!\[([^\]]*)\]\(([^)]+)\)', {
    param($match)
    $alt = $match.Groups[1].Value
    $rawLink = $match.Groups[2].Value.Trim()

    if ($rawLink -match "^(https?:|data:|#)") {
        return $match.Value
    }

    $decoded = [System.Uri]::UnescapeDataString($rawLink)
    $decoded = $decoded -replace "/", [System.IO.Path]::DirectorySeparatorChar
    $candidate = Join-Path $markdownDir $decoded
    if (-not (Test-Path -LiteralPath $candidate)) {
        $candidate = Join-Path $sourceDir $decoded
    }
    if (-not (Test-Path -LiteralPath $candidate)) {
        $leaf = Split-Path -Leaf $decoded
        $candidateFile = Get-ChildItem -LiteralPath $sourceDir -Recurse -File |
            Where-Object { $_.Name -eq $leaf } |
            Select-Object -First 1
        if ($candidateFile) {
            $candidate = $candidateFile.FullName
        }
    }
    if (-not (Test-Path -LiteralPath $candidate)) {
        Write-Warning "找不到图片: $rawLink"
        return $match.Value
    }

    $newPath = Copy-NoteImage -ImagePath $candidate -AssetsDir $assetsDir -Copied $copiedImages -Counter ([ref]$imageCounter)
    return "![${alt}]($newPath)"
})

$frontMatter = @"
---
title: "$Title"
date: "$Date"
status: "$Status"
tags: "$Tags"
---

"@

if ($content -notmatch "^\s*---\s*`r?`n") {
    $content = $frontMatter + $content.TrimStart()
}

Set-Content -LiteralPath (Join-Path $entryDir "README.md") -Value $content -Encoding UTF8

$allImages = Get-ChildItem -LiteralPath $sourceDir -Recurse -File |
    Where-Object { $_.Extension.ToLowerInvariant() -in @(".png", ".jpg", ".jpeg", ".gif", ".webp") } |
    Sort-Object FullName

foreach ($img in $allImages) {
    if (-not $copiedImages.ContainsKey((Resolve-Path -LiteralPath $img.FullName).Path)) {
        Copy-NoteImage -ImagePath $img.FullName -AssetsDir $assetsDir -Copied $copiedImages -Counter ([ref]$imageCounter) | Out-Null
    }
}

$entryRel = "$Category/$year/$Date-$slug/"
$rowForMain = "| $Date | [$Title]($year/$Date-$slug/) | $Status | $Tags |"
$rowForRoot = "| $Date | [$Title](notes/$year/$Date-$slug/) | $Status | $Tags |"
$rowForYear = "| $Date | [$Title]($Date-$slug/) | $Status | $Tags |"

$notesHeader = @"
# Notes

这里存放地理可视化学习过程中的笔记、实验复盘和问题记录。

## $year

| 日期 | 标题 | 状态 | 主题 |
|---|---|---|---|
"@

$yearHeader = @"
# $year

| 日期 | 标题 | 状态 | 主题 |
|---|---|---|---|
"@

if ($Category -eq "notes") {
    Update-NotesIndex -Path (Join-Path $repoRoot "README.md") -Year $year -Row $rowForRoot
    Update-NotesIndex -Path (Join-Path $repoRoot "notes\README.md") -Year $year -Row $rowForMain
}
else {
    Update-DatedCategoryIndex -Path (Join-Path $repoRoot "$Category\README.md") -CategoryTitle $Category -Year $year -Row $rowForMain
}
Update-IndexFile -Path (Join-Path $repoRoot "$Category\$year\README.md") -Header $yearHeader -Row $rowForYear

Write-Host "导入完成: $entryRel"
Write-Host "图片数量: $($copiedImages.Count)"

if ($Commit) {
    git add notes experiments resources paths .gitignore inbox scripts README.md
    git commit -m "Add note: $Title"
}

if ($Push) {
    git push
}

if ($cleanupDir -and (Test-Path -LiteralPath $cleanupDir)) {
    Remove-Item -LiteralPath $cleanupDir -Recurse -Force
}




