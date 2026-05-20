param(
    [Parameter(Mandatory = $true)]
    [string]$Source,

    [string]$Title = "",
    [string]$Date = (Get-Date -Format "yyyy-MM-dd"),
    [string]$Status = "进行中",
    [string]$Tags = "",
    [int]$MaxImageWidth = 1400,
    [int]$JpegQuality = 78,
    [int]$TargetImageKB = 350,
    [int]$MinJpegQuality = 52,
    [switch]$NoPush
)

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Split-Path -Parent $scriptDir
Set-Location -LiteralPath $repoRoot

$importScript = Join-Path $scriptDir "import-note.ps1"

Write-Host "Repository: $repoRoot"
Write-Host "Category: notes"

$argsList = @(
    "-ExecutionPolicy", "Bypass",
    "-File", $importScript,
    "-Source", $Source,
    "-Category", "notes",
    "-Date", $Date,
    "-Status", $Status,
    "-MaxImageWidth", $MaxImageWidth,
    "-JpegQuality", $JpegQuality,
    "-TargetImageKB", $TargetImageKB,
    "-MinJpegQuality", $MinJpegQuality
)

if (-not [string]::IsNullOrWhiteSpace($Title)) {
    $argsList += @("-Title", $Title)
}

if (-not [string]::IsNullOrWhiteSpace($Tags)) {
    $argsList += @("-Tags", $Tags)
}

if (-not $NoPush) {
    $argsList += @("-Commit", "-Push")
}

& powershell @argsList
exit $LASTEXITCODE


