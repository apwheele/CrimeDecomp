[CmdletBinding()]
param(
  [switch]$CheckOnly,
  [string]$Remote = "origin"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repositoryRoot = [System.IO.Path]::GetFullPath(
  (Join-Path -Path $PSScriptRoot -ChildPath "..")
)
$temporaryParent = Join-Path $repositoryRoot "tmp"
$stagingRoot = Join-Path (
  $temporaryParent
) ("github-pages-deploy-" + [guid]::NewGuid().ToString("N"))
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)
$worktreeAdded = $false

function Invoke-GitCapture {
  param(
    [Parameter(Mandatory = $true)]
    [string]$WorkingDirectory,
    [Parameter(Mandatory = $true)]
    [string[]]$Arguments
  )

  $previousErrorActionPreference = $ErrorActionPreference
  try {
    # Windows PowerShell 5 wraps ordinary native stderr (including Git progress)
    # as ErrorRecord objects when the caller uses Stop. Git's exit code remains
    # the authoritative success signal.
    $ErrorActionPreference = "Continue"
    $output = & git -C $WorkingDirectory @Arguments 2>&1
    $exitCode = $LASTEXITCODE
  } finally {
    $ErrorActionPreference = $previousErrorActionPreference
  }
  if ($exitCode -ne 0) {
    $detail = [string]::Join([Environment]::NewLine, @($output))
    throw "git $($Arguments -join ' ') failed:`n$detail"
  }
  return [string]::Join([Environment]::NewLine, @($output)).Trim()
}

function Assert-GitQuiet {
  param(
    [Parameter(Mandatory = $true)]
    [string[]]$Arguments,
    [Parameter(Mandatory = $true)]
    [string]$FailureMessage
  )

  & git -C $repositoryRoot @Arguments
  if ($LASTEXITCODE -eq 1) {
    throw $FailureMessage
  }
  if ($LASTEXITCODE -ne 0) {
    throw "git $($Arguments -join ' ') failed with exit code $LASTEXITCODE."
  }
}

$crimeTypes = @(
  "murder", "rape", "robbery", "assault", "burglary", "theft", "motor"
)
$appFiles = @("app.js", "index.html", "styles.css")
$dataFiles = @("cities.csv", "global_stl.csv")
foreach ($crime in $crimeTypes) {
  $dataFiles += @(
    "decomposition_$crime.csv",
    "city_trends_$crime.csv",
    "city_seasons_$crime.csv",
    "residual_se_$crime.csv"
  )
}

$bundleFiles = @()
foreach ($file in $appFiles) {
  $bundleFiles += [PSCustomObject]@{
    Source = Join-Path $repositoryRoot "src\app\$file"
    SourceRelative = "src/app/$file"
    TargetRelative = "app/$file"
  }
}
foreach ($file in $dataFiles) {
  $bundleFiles += [PSCustomObject]@{
    Source = Join-Path $repositoryRoot "src\data\app\$file"
    SourceRelative = "src/data/app/$file"
    TargetRelative = "data/app/$file"
  }
}

foreach ($item in $bundleFiles) {
  if (-not (Test-Path -LiteralPath $item.Source -PathType Leaf)) {
    throw "Missing GitHub Pages input: $($item.Source)"
  }
  if ((Get-Item -LiteralPath $item.Source).Length -eq 0) {
    throw "GitHub Pages input is empty: $($item.Source)"
  }
}

$currentBranch = Invoke-GitCapture -WorkingDirectory $repositoryRoot `
  -Arguments @("branch", "--show-current")
if ($currentBranch -ne "main") {
  throw "Check out main before deploying GitHub Pages (current branch: $currentBranch)."
}

Assert-GitQuiet -Arguments @("diff", "--quiet", "--", "src/app") `
  -FailureMessage "Commit or discard the unstaged src/app changes before deploying."
Assert-GitQuiet -Arguments @("diff", "--cached", "--quiet", "--", "src/app") `
  -FailureMessage "Commit the staged src/app changes before deploying."

$mainCommit = Invoke-GitCapture -WorkingDirectory $repositoryRoot `
  -Arguments @("rev-parse", "HEAD")

Write-Host "Fetching $Remote/main and $Remote/gh-pages..."
$fetchOutput = Invoke-GitCapture -WorkingDirectory $repositoryRoot -Arguments @(
  "fetch",
  "--prune",
  $Remote,
  "refs/heads/main:refs/remotes/$Remote/main",
  "refs/heads/gh-pages:refs/remotes/$Remote/gh-pages"
)
if ($fetchOutput) {
  Write-Host $fetchOutput
}

$remoteMainCommit = Invoke-GitCapture -WorkingDirectory $repositoryRoot `
  -Arguments @("rev-parse", "refs/remotes/$Remote/main")
if ($mainCommit -ne $remoteMainCommit) {
  throw @"
Local main is not identical to $Remote/main.
Local:  $mainCommit
Remote: $remoteMainCommit
Push or synchronize main before deploying GitHub Pages.
"@
}

$stagingFullPath = [System.IO.Path]::GetFullPath($stagingRoot)
$temporaryPrefix = [System.IO.Path]::GetFullPath($temporaryParent) + `
  [System.IO.Path]::DirectorySeparatorChar
if (-not $stagingFullPath.StartsWith(
    $temporaryPrefix,
    [System.StringComparison]::OrdinalIgnoreCase
  )) {
  throw "Refusing to use an unexpected staging path: $stagingFullPath"
}

try {
  New-Item -ItemType Directory -Path $temporaryParent -Force | Out-Null
  $worktreeOutput = Invoke-GitCapture -WorkingDirectory $repositoryRoot `
    -Arguments @(
      "worktree", "add", "--detach", $stagingRoot,
      "refs/remotes/$Remote/gh-pages"
    )
  $worktreeAdded = $true
  if ($worktreeOutput) {
    Write-Host $worktreeOutput
  }

  $removeOutput = Invoke-GitCapture -WorkingDirectory $stagingRoot -Arguments @(
    "rm", "-r", "--ignore-unmatch", "--",
    "app", "data", "index.html", ".nojekyll", "deployment.json"
  )
  if ($removeOutput) {
    Write-Host $removeOutput
  }

  foreach ($directory in @("app", "data\app")) {
    New-Item -ItemType Directory -Path (
      Join-Path $stagingRoot $directory
    ) -Force | Out-Null
  }

  foreach ($item in $bundleFiles) {
    $nativeTarget = $item.TargetRelative.Replace(
      "/", [System.IO.Path]::DirectorySeparatorChar
    )
    Copy-Item -LiteralPath $item.Source `
      -Destination (Join-Path $stagingRoot $nativeTarget)
  }

  $rootIndex = @'
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Crime decomposition explorer</title>
  <meta http-equiv="refresh" content="0; url=app/">
  <link rel="canonical" href="app/">
</head>
<body>
  <p><a href="app/">Open the crime decomposition explorer</a>.</p>
</body>
</html>
'@
  [System.IO.File]::WriteAllText(
    (Join-Path $stagingRoot "index.html"),
    ($rootIndex.Replace("`r`n", "`n") + "`n"),
    $utf8NoBom
  )
  [System.IO.File]::WriteAllText(
    (Join-Path $stagingRoot ".nojekyll"),
    "# Serve the static application without Jekyll processing.`n",
    $utf8NoBom
  )

  $fileManifest = foreach ($item in $bundleFiles) {
    [ordered]@{
      source = $item.SourceRelative
      deployed_as = $item.TargetRelative
      sha256 = (Get-FileHash -LiteralPath $item.Source -Algorithm SHA256).Hash.ToLowerInvariant()
    }
  }
  $deploymentManifest = [ordered]@{
    main_commit = $mainCommit
    files = @($fileManifest)
  }
  $manifestJson = $deploymentManifest | ConvertTo-Json -Depth 5
  [System.IO.File]::WriteAllText(
    (Join-Path $stagingRoot "deployment.json"),
    ($manifestJson.Replace("`r`n", "`n") + "`n"),
    $utf8NoBom
  )

  $addOutput = Invoke-GitCapture -WorkingDirectory $stagingRoot `
    -Arguments @("-c", "core.autocrlf=input", "add", "--all")
  if ($addOutput) {
    Write-Host $addOutput
  }

  & git -C $stagingRoot diff --cached --quiet
  $hasChanges = $LASTEXITCODE -eq 1
  if ($LASTEXITCODE -notin @(0, 1)) {
    throw "Unable to compare the staged GitHub Pages bundle."
  }

  if (-not $hasChanges) {
    Write-Host "GitHub Pages is up to date with main $mainCommit."
    return
  }

  Write-Host "GitHub Pages differs from the current main deployment bundle:"
  & git -C $stagingRoot diff --cached --stat
  if ($LASTEXITCODE -ne 0) {
    throw "Unable to summarize the GitHub Pages differences."
  }

  if ($CheckOnly) {
    throw "GitHub Pages is not up to date. Run this script without -CheckOnly to deploy it."
  }

  $shortCommit = $mainCommit.Substring(0, 7)
  $commitOutput = Invoke-GitCapture -WorkingDirectory $stagingRoot `
    -Arguments @("commit", "-m", "Deploy main $shortCommit")
  if ($commitOutput) {
    Write-Host $commitOutput
  }
  $deploymentCommit = Invoke-GitCapture -WorkingDirectory $stagingRoot `
    -Arguments @("rev-parse", "HEAD")

  $pushOutput = Invoke-GitCapture -WorkingDirectory $stagingRoot `
    -Arguments @("push", $Remote, "HEAD:refs/heads/gh-pages")
  if ($pushOutput) {
    Write-Host $pushOutput
  }

  $remotePagesLine = Invoke-GitCapture -WorkingDirectory $repositoryRoot `
    -Arguments @("ls-remote", "--heads", $Remote, "refs/heads/gh-pages")
  $remotePagesCommit = ($remotePagesLine -split "\s+")[0]
  if ($remotePagesCommit -ne $deploymentCommit) {
    throw @"
The push completed, but the remote verification did not match.
Expected: $deploymentCommit
Remote:   $remotePagesCommit
"@
  }

  Write-Host "Deployed main $mainCommit to $Remote/gh-pages."
  Write-Host "GitHub Pages commit: $deploymentCommit"
} finally {
  if ($worktreeAdded) {
    & git -C $repositoryRoot worktree remove --force -- $stagingRoot
    if ($LASTEXITCODE -ne 0) {
      Write-Warning "Could not remove temporary worktree: $stagingRoot"
    }
  } elseif (Test-Path -LiteralPath $stagingRoot) {
    Remove-Item -LiteralPath $stagingRoot -Recurse -Force
  }
}
