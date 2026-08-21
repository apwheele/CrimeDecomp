[CmdletBinding()]
param(
  [string]$Remote = "origin",
  [string]$CondaEnvironment = "r2026",
  [string]$CondaExecutable = "",
  [switch]$PreflightOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Resolve-Executable {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Name,
    [string[]]$FallbackPaths = @()
  )

  $command = Get-Command $Name -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandType -eq "Application" } |
    Select-Object -First 1
  if ($null -ne $command) {
    return $command.Source
  }
  foreach ($path in $FallbackPaths) {
    if ($path -and (Test-Path -LiteralPath $path -PathType Leaf)) {
      return [System.IO.Path]::GetFullPath($path)
    }
  }
  throw "Required executable was not found: $Name"
}

function Invoke-External {
  param(
    [Parameter(Mandatory = $true)]
    [string]$FilePath,
    [string[]]$Arguments = @()
  )

  & $FilePath @Arguments
  if ($LASTEXITCODE -ne 0) {
    throw "$FilePath $($Arguments -join ' ') failed with exit code $LASTEXITCODE."
  }
}

function Invoke-ExternalCapture {
  param(
    [Parameter(Mandatory = $true)]
    [string]$FilePath,
    [string[]]$Arguments = @(),
    [switch]$StandardOutputOnly
  )

  $previousErrorActionPreference = $ErrorActionPreference
  try {
    $ErrorActionPreference = "Continue"
    if ($StandardOutputOnly) {
      $output = & $FilePath @Arguments 2>$null
    } else {
      $output = & $FilePath @Arguments 2>&1
    }
    $exitCode = $LASTEXITCODE
  } finally {
    $ErrorActionPreference = $previousErrorActionPreference
  }
  if ($exitCode -ne 0) {
    $detail = [string]::Join([Environment]::NewLine, @($output))
    throw "$FilePath $($Arguments -join ' ') failed:`n$detail"
  }
  return [string]::Join([Environment]::NewLine, @($output)).Trim()
}

function Test-AllowedReleasePath {
  param([Parameter(Mandatory = $true)][string]$Path)

  $normalized = $Path.Replace("\", "/")
  return $normalized -in @("paper.pdf", "paper.docx", "paper.md") -or
    $normalized.StartsWith("output/markdown/images/") -or
    $normalized.StartsWith("src/data/raw/")
}

function Convert-WindowsPathToWsl {
  param([Parameter(Mandatory = $true)][string]$Path)

  $fullPath = [System.IO.Path]::GetFullPath($Path)
  if ($fullPath -match "^[A-Za-z]:\\") {
    $drive = $fullPath.Substring(0, 1).ToLowerInvariant()
    $remainder = $fullPath.Substring(3).Replace("\", "/")
    return "/mnt/$drive/$remainder"
  }
  throw "Could not convert the repository path to WSL format: $fullPath"
}

$candidateRoot = [System.IO.Path]::GetFullPath(
  (Join-Path -Path $PSScriptRoot -ChildPath "..")
)
$gitExecutable = Resolve-Executable -Name "git.exe"
$rootText = Invoke-ExternalCapture -FilePath $gitExecutable -Arguments @(
  "-C", $candidateRoot, "rev-parse", "--show-toplevel"
)
$repositoryRoot = [System.IO.Path]::GetFullPath(
  $rootText.Replace("/", [System.IO.Path]::DirectorySeparatorChar)
)
$wslExecutable = Resolve-Executable -Name "wsl.exe"
$pdfInfoExecutable = Resolve-Executable -Name "pdfinfo.exe" -FallbackPaths @(
  (Join-Path $env:LOCALAPPDATA "Programs\MiKTeX\miktex\bin\x64\pdfinfo.exe")
)
$pdfToPpmExecutable = Resolve-Executable -Name "pdftoppm.exe" -FallbackPaths @(
  (Join-Path $env:LOCALAPPDATA "Programs\MiKTeX\miktex\bin\x64\pdftoppm.exe")
)
if (-not $CondaExecutable) {
  $CondaExecutable = Resolve-Executable -Name "conda.exe" -FallbackPaths @(
    (Join-Path $env:USERPROFILE "miniconda3\Scripts\conda.exe"),
    (Join-Path $env:USERPROFILE "anaconda3\Scripts\conda.exe")
  )
} elseif (-not (Test-Path -LiteralPath $CondaExecutable -PathType Leaf)) {
  throw "Conda executable does not exist: $CondaExecutable"
} else {
  $CondaExecutable = [System.IO.Path]::GetFullPath($CondaExecutable)
}

$modelDirectory = Join-Path $repositoryRoot "src\data\model"
New-Item -ItemType Directory -Path $modelDirectory -Force | Out-Null
$lockPath = Join-Path $modelDirectory "scheduled-release.lock"
$logPath = Join-Path $modelDirectory "scheduled-release.log"
$releaseLock = $null
$transcriptStarted = $false

try {
  try {
    $releaseLock = [System.IO.File]::Open(
      $lockPath,
      [System.IO.FileMode]::OpenOrCreate,
      [System.IO.FileAccess]::ReadWrite,
      [System.IO.FileShare]::None
    )
  } catch {
    throw "Another scheduled release is already running (lock: $lockPath)."
  }

  Start-Transcript -Path $logPath -Append | Out-Null
  $transcriptStarted = $true
  Set-Location -LiteralPath $repositoryRoot
  Write-Host "Scheduled CrimeDecomp release started at $([DateTime]::Now.ToString('s'))."
  Write-Host "Repository: $repositoryRoot"

  $branch = Invoke-ExternalCapture -FilePath $gitExecutable -Arguments @(
    "-C", $repositoryRoot, "branch", "--show-current"
  )
  if ($branch -ne "main") {
    throw "The scheduled release requires branch main (current branch: $branch)."
  }
  $initialStatus = Invoke-ExternalCapture -FilePath $gitExecutable -Arguments @(
    "-C", $repositoryRoot, "status", "--porcelain=v1", "--untracked-files=all"
  )
  if ($initialStatus) {
    throw "The worktree must be clean before the scheduled release:`n$initialStatus"
  }

  Invoke-External -FilePath $gitExecutable -Arguments @(
    "-C", $repositoryRoot, "fetch", "--prune", $Remote, "main"
  )
  $localCommit = Invoke-ExternalCapture -FilePath $gitExecutable -Arguments @(
    "-C", $repositoryRoot, "rev-parse", "HEAD"
  )
  $remoteRef = "refs/remotes/$Remote/main"
  $remoteCommit = Invoke-ExternalCapture -FilePath $gitExecutable -Arguments @(
    "-C", $repositoryRoot, "rev-parse", $remoteRef
  )
  if ($localCommit -ne $remoteCommit) {
    Invoke-External -FilePath $gitExecutable -Arguments @(
      "-C", $repositoryRoot, "merge", "--ff-only", $remoteRef
    )
    $localCommit = Invoke-ExternalCapture -FilePath $gitExecutable -Arguments @(
      "-C", $repositoryRoot, "rev-parse", "HEAD"
    )
    if ($localCommit -ne $remoteCommit) {
      throw "Local main contains commits that are not on $Remote/main; refusing an unattended release."
    }
  }

  $wslProcessCommand = @(
    "pgrep -a -x R || true",
    "pgrep -a -x Rscript || true",
    "pgrep -af 'bash src/run_models_sequential[.]sh' || true"
  ) -join "; "
  $modelProcesses = Invoke-ExternalCapture -FilePath $wslExecutable `
    -StandardOutputOnly -Arguments @(
      "-d", "Ubuntu", "--", "bash", "--noprofile", "--norc", "-c",
      $wslProcessCommand
    )
  if ($modelProcesses) {
    throw "A WSL R/model process is already active; refusing to start a duplicate:`n$modelProcesses"
  }

  Write-Host "Preflight checks passed; main matches $Remote/main and no model process is active."
  if ($PreflightOnly) {
    Write-Host "Preflight-only run completed successfully."
    return
  }

  Invoke-External -FilePath $CondaExecutable -Arguments @(
    "run", "--no-capture-output", "-n", $CondaEnvironment,
    "quarto", "render", "paper.qmd", "--to", "all"
  )

  $wslRoot = Convert-WindowsPathToWsl -Path $repositoryRoot
  $escapedWslRoot = $wslRoot.Replace("'", "'\''")
  $validationCommand = "cd '$escapedWslRoot' && Rscript src/validate_outputs.R"
  Invoke-External -FilePath $wslExecutable -Arguments @(
    "-d", "Ubuntu", "--", "bash", "--noprofile", "--norc", "-c",
    $validationCommand
  )

  foreach ($artifact in @("paper.pdf", "paper.docx", "paper.md")) {
    if (-not (Test-Path -LiteralPath $artifact -PathType Leaf) -or
        (Get-Item -LiteralPath $artifact).Length -eq 0) {
      throw "Rendered artifact is missing or empty: $artifact"
    }
  }
  $pdfInfo = Invoke-ExternalCapture -FilePath $pdfInfoExecutable -Arguments @("paper.pdf")
  $pageMatch = [regex]::Match($pdfInfo, "(?m)^Pages:\s+(\d+)\s*$")
  if (-not $pageMatch.Success -or [int]$pageMatch.Groups[1].Value -lt 1) {
    throw "Could not verify the page count in paper.pdf."
  }
  $pageCount = [int]$pageMatch.Groups[1].Value
  # Keep disposable rasterized pages outside the Dropbox-synced repository.
  # Sync clients can briefly hold directory handles after pdftoppm exits.
  $temporaryParent = [System.IO.Path]::GetFullPath((Join-Path (
    [System.IO.Path]::GetTempPath()
  ) "CrimeDecomp"))
  $qaDirectory = [System.IO.Path]::GetFullPath((Join-Path $temporaryParent (
    "scheduled-paper-qa-" + [guid]::NewGuid().ToString("N")
  )))
  $temporaryPrefix = $temporaryParent + [System.IO.Path]::DirectorySeparatorChar
  if (-not $qaDirectory.StartsWith(
      $temporaryPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Refusing to use an unexpected PDF QA directory: $qaDirectory"
  }
  try {
    New-Item -ItemType Directory -Path $qaDirectory -Force | Out-Null
    $qaPrefix = Join-Path $qaDirectory "paper-page"
    Invoke-External -FilePath $pdfToPpmExecutable -Arguments @(
      "-png", "-r", "110", "paper.pdf", $qaPrefix
    )
    $pageImages = @(Get-ChildItem -LiteralPath $qaDirectory -Filter "paper-page-*.png" -File)
    if ($pageImages.Count -ne $pageCount -or
        @($pageImages | Where-Object { $_.Length -eq 0 }).Count -gt 0) {
      throw "PDF rasterization produced $($pageImages.Count) valid pages; expected $pageCount."
    }
    Write-Host "Verified and rasterized all $pageCount pages of paper.pdf."
  } finally {
    if (Test-Path -LiteralPath $qaDirectory) {
      for ($cleanupAttempt = 1; $cleanupAttempt -le 5; $cleanupAttempt++) {
        try {
          Remove-Item -LiteralPath $qaDirectory -Recurse -Force -ErrorAction Stop
          break
        } catch {
          if ($cleanupAttempt -eq 5) {
            Write-Warning (
              "Could not remove disposable PDF QA directory after 5 attempts: " +
              "$qaDirectory. Release processing will continue. $($_.Exception.Message)"
            )
          } else {
            Start-Sleep -Milliseconds (250 * $cleanupAttempt)
          }
        }
      }
    }
  }

  $changedText = Invoke-ExternalCapture -FilePath $gitExecutable -Arguments @(
    "-C", $repositoryRoot, "diff", "--name-only", "HEAD", "--"
  )
  $changedPaths = @($changedText -split "`r?`n" | Where-Object { $_ })
  $untrackedText = Invoke-ExternalCapture -FilePath $gitExecutable -Arguments @(
    "-C", $repositoryRoot, "ls-files", "--others", "--exclude-standard"
  )
  $untrackedPaths = @($untrackedText -split "`r?`n" | Where-Object { $_ })
  $unexpectedPaths = @($changedPaths + $untrackedPaths | Sort-Object -Unique |
    Where-Object { -not (Test-AllowedReleasePath -Path $_) })
  if ($unexpectedPaths.Count -gt 0) {
    throw "Unexpected worktree changes were produced; nothing was committed:`n$($unexpectedPaths -join "`n")"
  }

  Invoke-External -FilePath $gitExecutable -Arguments @(
    "-C", $repositoryRoot, "add", "-A", "--",
    "src/data/raw", "paper.pdf", "paper.docx", "paper.md",
    "output/markdown/images"
  )
  & $gitExecutable -C $repositoryRoot diff --cached --quiet
  $hasReleaseChanges = $LASTEXITCODE -eq 1
  if ($LASTEXITCODE -notin @(0, 1)) {
    throw "Unable to inspect the staged scheduled-release changes."
  }
  if ($hasReleaseChanges) {
    Invoke-External -FilePath $gitExecutable -Arguments @(
      "-C", $repositoryRoot, "diff", "--cached", "--check"
    )
    $commitMessage = "Refresh RTCI outputs $([DateTime]::Now.ToString('yyyy-MM-dd'))"
    Invoke-External -FilePath $gitExecutable -Arguments @(
      "-C", $repositoryRoot, "commit", "-m", $commitMessage
    )
  } else {
    Write-Host "The RTCI snapshot and rendered paper are unchanged; no release commit is needed."
  }

  Invoke-External -FilePath $gitExecutable -Arguments @(
    "-C", $repositoryRoot, "push", $Remote, "main"
  )
  Invoke-External -FilePath "powershell.exe" -Arguments @(
    "-NoProfile", "-ExecutionPolicy", "Bypass", "-File",
    (Join-Path $repositoryRoot "src\deploy_github_pages.ps1"),
    "-Remote", $Remote
  )
  Invoke-External -FilePath "powershell.exe" -Arguments @(
    "-NoProfile", "-ExecutionPolicy", "Bypass", "-File",
    (Join-Path $repositoryRoot "src\deploy_github_pages.ps1"),
    "-CheckOnly", "-Remote", $Remote
  )

  $finalCommit = Invoke-ExternalCapture -FilePath $gitExecutable -Arguments @(
    "-C", $repositoryRoot, "rev-parse", "HEAD"
  )
  Write-Host "Scheduled release completed at $([DateTime]::Now.ToString('s'))."
  Write-Host "Published main commit: $finalCommit"
} finally {
  if ($transcriptStarted) {
    Stop-Transcript | Out-Null
  }
  if ($null -ne $releaseLock) {
    $releaseLock.Dispose()
  }
}
