[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repositoryRoot = [System.IO.Path]::GetFullPath(
  (Join-Path -Path $PSScriptRoot -ChildPath "..")
)
$sourceMarkdown = Join-Path $repositoryRoot "paper.md"
$sourceImageDirectory = Join-Path $repositoryRoot "output\markdown\images"
$packageRoot = Join-Path $repositoryRoot "crimrxiv"
$packageImageDirectory = Join-Path $packageRoot "output\markdown\images"
$stagingRoot = Join-Path (
  Join-Path $repositoryRoot "tmp"
) ("crimrxiv-build-" + [guid]::NewGuid().ToString("N"))
$stagingImageDirectory = Join-Path $stagingRoot "output\markdown\images"

if (-not (Test-Path -LiteralPath $sourceMarkdown -PathType Leaf)) {
  throw "Missing rendered Markdown file: $sourceMarkdown"
}
if (-not (Test-Path -LiteralPath $sourceImageDirectory -PathType Container)) {
  throw "Missing rendered image directory: $sourceImageDirectory"
}

$expectedPackageRoot = [System.IO.Path]::GetFullPath(
  (Join-Path $repositoryRoot "crimrxiv")
)
if (-not [string]::Equals(
    [System.IO.Path]::GetFullPath($packageRoot),
    $expectedPackageRoot,
    [System.StringComparison]::OrdinalIgnoreCase
  )) {
  throw "Refusing to replace an unexpected package directory: $packageRoot"
}

$gifAssets = [ordered]@{
  "https://crimede-coder.com/images/Philly.gif" = "Philly.gif"
  "https://crimede-coder.com/images/Curve.gif" = "Curve.gif"
  "https://crimede-coder.com/images/Outlier.gif" = "Outlier.gif"
}

try {
  New-Item -ItemType Directory -Path $stagingImageDirectory -Force | Out-Null

  Get-ChildItem -LiteralPath $sourceImageDirectory -File | ForEach-Object {
    Copy-Item -LiteralPath $_.FullName -Destination $stagingImageDirectory
  }

  $markdown = [System.IO.File]::ReadAllText($sourceMarkdown)
  foreach ($entry in $gifAssets.GetEnumerator()) {
    $gifDestination = Join-Path $stagingImageDirectory $entry.Value
    Invoke-WebRequest -Uri $entry.Key -OutFile $gifDestination -UseBasicParsing

    $gifBytes = [System.IO.File]::ReadAllBytes($gifDestination)
    if ($gifBytes.Length -lt 6) {
      throw "Downloaded GIF is empty or truncated: $($entry.Key)"
    }
    $gifHeader = [System.Text.Encoding]::ASCII.GetString($gifBytes, 0, 6)
    if ($gifHeader -notin @("GIF87a", "GIF89a")) {
      throw "Downloaded file is not a valid GIF: $($entry.Key)"
    }

    $relativeGifPath = "output/markdown/images/$($entry.Value)"
    $markdown = $markdown.Replace($entry.Key, $relativeGifPath)
  }

  $stagingMarkdown = Join-Path $stagingRoot "paper.md"
  [System.IO.File]::WriteAllText(
    $stagingMarkdown,
    $markdown,
    [System.Text.UTF8Encoding]::new($false)
  )

  $imageReferences = [regex]::Matches(
    $markdown,
    'output/markdown/images/[^\s\)"''>}]+'
  ) | ForEach-Object { $_.Value } | Sort-Object -Unique

  if (-not $imageReferences) {
    throw "The packaged Markdown does not contain any local image references."
  }

  $missingImages = foreach ($reference in $imageReferences) {
    $nativeReference = $reference.Replace(
      "/", [System.IO.Path]::DirectorySeparatorChar
    )
    $referencedPath = Join-Path $stagingRoot $nativeReference
    if (-not (Test-Path -LiteralPath $referencedPath -PathType Leaf)) {
      $reference
    }
  }
  if ($missingImages) {
    throw "Missing packaged image files: $($missingImages -join ', ')"
  }

  if (Test-Path -LiteralPath $packageRoot) {
    Remove-Item -LiteralPath $packageRoot -Recurse -Force
  }
  Move-Item -LiteralPath $stagingRoot -Destination $packageRoot

  $imageCount = (Get-ChildItem -LiteralPath $packageImageDirectory -File).Count
  Write-Host "Created CrimRxiv package: $packageRoot"
  Write-Host "Markdown: paper.md"
  Write-Host "Images: $imageCount files under output/markdown/images"
  Write-Host "Verified local references: $($imageReferences.Count)"
} finally {
  if (Test-Path -LiteralPath $stagingRoot) {
    Remove-Item -LiteralPath $stagingRoot -Recurse -Force
  }
}
