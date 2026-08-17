[CmdletBinding(SupportsShouldProcess = $true)]
param(
  [ValidateSet("Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday")]
  [string]$DayOfWeek = "Monday",
  [ValidateScript({ $_ -ge [TimeSpan]::Zero -and $_ -lt [TimeSpan]::FromDays(1) })]
  [TimeSpan]$At = [TimeSpan]::FromHours(9),
  [string]$TaskName = "CrimeDecomp Weekly Release",
  [switch]$Uninstall
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ($Uninstall) {
  if ($PSCmdlet.ShouldProcess($TaskName, "Remove scheduled task")) {
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction Stop
    Write-Host "Removed scheduled task '$TaskName'."
  }
  return
}

$candidateRoot = [System.IO.Path]::GetFullPath(
  (Join-Path -Path $PSScriptRoot -ChildPath "..")
)
$gitExecutable = (Get-Command git.exe -ErrorAction Stop).Source
$repositoryRootText = & $gitExecutable -C $candidateRoot rev-parse --show-toplevel
if ($LASTEXITCODE -ne 0) {
  throw "Could not resolve the CrimeDecomp repository root."
}
$repositoryRoot = [System.IO.Path]::GetFullPath(
  ([string]$repositoryRootText).Trim().Replace(
    "/", [System.IO.Path]::DirectorySeparatorChar
  )
)
$releaseScript = Join-Path $repositoryRoot "src\run_scheduled_release.ps1"
if (-not (Test-Path -LiteralPath $releaseScript -PathType Leaf)) {
  throw "Scheduled release script does not exist: $releaseScript"
}
$condaExecutable = (Get-Command conda.exe -ErrorAction Stop).Source
$powerShellExecutable = (Get-Command powershell.exe -ErrorAction Stop).Source
$null = Get-Command wsl.exe -ErrorAction Stop
$null = Get-Command pdfinfo.exe -ErrorAction Stop
$null = Get-Command pdftoppm.exe -ErrorAction Stop

$now = Get-Date
$targetDay = [System.DayOfWeek][System.Enum]::Parse(
  [System.DayOfWeek], $DayOfWeek, $true
)
$daysUntilTarget = (([int]$targetDay - [int]$now.DayOfWeek) + 7) % 7
$firstStart = $now.Date.AddDays($daysUntilTarget).Add($At)
if ($firstStart -le $now) {
  $firstStart = $firstStart.AddDays(7)
}
$identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
$userSid = $identity.User.Value
$userName = $identity.Name

function ConvertTo-XmlText {
  param([Parameter(Mandatory = $true)][string]$Value)
  return [System.Security.SecurityElement]::Escape($Value)
}

$actionArguments = @(
  "-NoProfile",
  "-NonInteractive",
  "-ExecutionPolicy Bypass",
  "-File `"$releaseScript`"",
  "-CondaExecutable `"$condaExecutable`""
) -join " "
$xmlCommand = ConvertTo-XmlText $powerShellExecutable
$xmlArguments = ConvertTo-XmlText $actionArguments
$xmlWorkingDirectory = ConvertTo-XmlText $repositoryRoot
$xmlDescription = ConvertTo-XmlText (
  "Refresh the RTCI snapshot and CrimeDecomp models sequentially, render and " +
  "validate the paper, push main, and deploy and verify GitHub Pages."
)
$xmlUserSid = ConvertTo-XmlText $userSid
$startBoundary = $firstStart.ToString("yyyy-MM-dd'T'HH:mm:ss")

$taskXml = @"
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.4" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <RegistrationInfo>
    <Description>$xmlDescription</Description>
  </RegistrationInfo>
  <Triggers>
    <CalendarTrigger>
      <StartBoundary>$startBoundary</StartBoundary>
      <Enabled>true</Enabled>
      <ScheduleByWeek>
        <WeeksInterval>1</WeeksInterval>
        <DaysOfWeek><$DayOfWeek/></DaysOfWeek>
      </ScheduleByWeek>
    </CalendarTrigger>
  </Triggers>
  <Principals>
    <Principal id="Author">
      <UserId>$xmlUserSid</UserId>
      <LogonType>InteractiveToken</LogonType>
      <RunLevel>LeastPrivilege</RunLevel>
    </Principal>
  </Principals>
  <Settings>
    <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>
    <DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>
    <StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>
    <AllowHardTerminate>true</AllowHardTerminate>
    <StartWhenAvailable>true</StartWhenAvailable>
    <RunOnlyIfNetworkAvailable>true</RunOnlyIfNetworkAvailable>
    <IdleSettings>
      <StopOnIdleEnd>false</StopOnIdleEnd>
      <RestartOnIdle>false</RestartOnIdle>
    </IdleSettings>
    <AllowStartOnDemand>true</AllowStartOnDemand>
    <Enabled>true</Enabled>
    <Hidden>false</Hidden>
    <ExecutionTimeLimit>PT8H</ExecutionTimeLimit>
    <Priority>7</Priority>
  </Settings>
  <Actions Context="Author">
    <Exec>
      <Command>$xmlCommand</Command>
      <Arguments>$xmlArguments</Arguments>
      <WorkingDirectory>$xmlWorkingDirectory</WorkingDirectory>
    </Exec>
  </Actions>
</Task>
"@

if ($PSCmdlet.ShouldProcess(
    $TaskName,
    "Register weekly task for $DayOfWeek at $($At.ToString()) as $userName"
  )) {
  Register-ScheduledTask -TaskName $TaskName -Xml $taskXml -Force | Out-Null
  $legacyTaskName = "CrimeDecomp Monthly Release"
  if ($TaskName -ne $legacyTaskName -and
      $null -ne (Get-ScheduledTask -TaskName $legacyTaskName -ErrorAction SilentlyContinue)) {
    Unregister-ScheduledTask -TaskName $legacyTaskName -Confirm:$false
    Write-Host "Removed legacy scheduled task '$legacyTaskName'."
  }
  $task = Get-ScheduledTask -TaskName $TaskName
  $taskInfo = Get-ScheduledTaskInfo -TaskName $TaskName
  Write-Host "Registered scheduled task '$TaskName' for $userName."
  Write-Host "Next run: $($taskInfo.NextRunTime)"
  Write-Host "The task runs only while this user is logged on and will start when possible after a missed run."
  Write-Host "Release log: $(Join-Path $repositoryRoot 'src\data\model\scheduled-release.log')"
  $task | Select-Object TaskName, State
}
