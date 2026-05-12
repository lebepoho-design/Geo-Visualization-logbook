param(
    [Parameter(Mandatory = $true)]
    [string]$Source,

    [ValidateSet("notes", "experiments", "resources", "paths")]
    [string]$Category = "notes",

    [string]$Title = "",
    [string]$Date = (Get-Date -Format "yyyy-MM-dd"),
    [string]$Status = "进行中",
    [string]$Tags = "",
    [int]$MaxImageWidth = 1800,
    [int]$JpegQuality = 82,
    [switch]$NoPush
)

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$importScript = Join-Path $scriptDir "import-note.ps1"

$argsList = @(
    "-ExecutionPolicy", "Bypass",
    "-File", $importScript,
    "-Source", $Source,
    "-Category", $Category,
    "-Date", $Date,
    "-Status", $Status,
    "-Tags", $Tags,
    "-MaxImageWidth", $MaxImageWidth,
    "-JpegQuality", $JpegQuality,
    "-Commit"
)

if (-not [string]::IsNullOrWhiteSpace($Title)) {
    $argsList += @("-Title", $Title)
}

if (-not $NoPush) {
    $argsList += "-Push"
}

& powershell @argsList

