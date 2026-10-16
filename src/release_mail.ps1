# Email for the weekly CrimeDecomp release (src/run_scheduled_release.ps1),
# sent through Titan mail as andrew.wheeler@crimede-coder.com.
#
# One-time setup, in your own PowerShell window. It asks for the mailbox
# password, stores it encrypted for your Windows account only (DPAPI, outside
# the repository), copies it to the SMTP_PASSWORD secret that SynthRTCI's
# GitHub workflow uses, and sends a test email:
#
#   powershell -ExecutionPolicy Bypass -File src\release_mail.ps1 -Setup
#
# Run it again after changing the mailbox password. The release script
# dot-sources this file for Send-ReleaseMail.

[CmdletBinding()]
param(
  [switch]$Setup,
  [string]$GitHubSecretRepo = "apwheele/SynthRTCI"
)

$ReleaseMailAddress = "andrew.wheeler@crimede-coder.com"
$ReleaseMailServer = "smtp.titan.email"
$ReleaseMailPort = 587
$ReleaseMailCredentialPath = Join-Path $env:LOCALAPPDATA "CrimeDecomp\release-mail-credential.xml"

function Send-ReleaseMail {
  param(
    [Parameter(Mandatory = $true)][string]$Subject,
    [Parameter(Mandatory = $true)][string]$Body,
    [string[]]$Attachments = @()
  )
  if (-not (Test-Path -LiteralPath $ReleaseMailCredentialPath)) {
    throw "No saved mail password; run src\release_mail.ps1 -Setup."
  }
  $credential = Import-Clixml -LiteralPath $ReleaseMailCredentialPath
  [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
  $message = @{
    From = $ReleaseMailAddress
    To = $ReleaseMailAddress
    Subject = $Subject
    Body = $Body
    SmtpServer = $ReleaseMailServer
    Port = $ReleaseMailPort
    UseSsl = $true
    Credential = $credential
    Encoding = [System.Text.Encoding]::UTF8
  }
  $files = @($Attachments | Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Leaf) })
  if ($files.Count -gt 0) {
    $message.Attachments = $files
  }
  # Send-MailMessage is marked obsolete but works with Titan's STARTTLS port
  Send-MailMessage @message -WarningAction SilentlyContinue -ErrorAction Stop
}

if ($Setup) {
  $credential = Get-Credential -UserName $ReleaseMailAddress `
    -Message "Mailbox password for $ReleaseMailAddress (Titan mail)"
  if ($null -eq $credential) {
    throw "Cancelled; nothing was saved."
  }
  New-Item -ItemType Directory -Force -Path (Split-Path $ReleaseMailCredentialPath) | Out-Null
  $credential | Export-Clixml -LiteralPath $ReleaseMailCredentialPath
  Send-ReleaseMail -Subject "CrimeDecomp release email: test" `
    -Body "The weekly CrimeDecomp release can send email from $env:COMPUTERNAME."
  Write-Host "Saved the password and sent a test email to $ReleaseMailAddress."
  if ($GitHubSecretRepo) {
    $credential.GetNetworkCredential().Password | gh secret set SMTP_PASSWORD -R $GitHubSecretRepo
    if ($LASTEXITCODE -ne 0) {
      throw "Could not save the SMTP_PASSWORD secret in $GitHubSecretRepo."
    }
    Write-Host "Saved the SMTP_PASSWORD secret in $GitHubSecretRepo."
  }
}
