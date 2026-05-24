<#
.SYNOPSIS
  Configure InfluxDB 2.x via REST API (pas de CLI necessaire).
  Cree l'org, le bucket et le token pour le collector.
.NOTES
  Lancer une seule fois apres le premier demarrage d'InfluxDB.
  Necessite que la tache PC-Monitor-InfluxDB tourne (ou que influxd.exe soit lance).
#>

param(
  [string]$InfluxUrl  = "http://localhost:8086",
  [string]$AdminUser  = "admin",
  [string]$AdminPass  = "admin-password-change-me",
  [string]$OrgName    = "home",
  [string]$BucketName = "pc-monitor"
)

$ErrorActionPreference = "Stop"

# ── Attente InfluxDB ──────────────────────────────────────────────────────────
Write-Host "Attente d'InfluxDB sur $InfluxUrl..."
for ($i = 0; $i -lt 20; $i++) {
  try {
    $h = Invoke-RestMethod "$InfluxUrl/health" -TimeoutSec 3
    if ($h.status -eq "pass") { Write-Host "  InfluxDB repond."; break }
  } catch {}
  if ($i -eq 19) { throw "InfluxDB ne repond pas apres 60s. Verifie la tache PC-Monitor-InfluxDB." }
  Write-Host "  Attente... ($([int]($i*3))s)"
  Start-Sleep 3
}

$token = $null
$setupStatus = Invoke-RestMethod "$InfluxUrl/api/v2/setup" -Method GET

# ── Cas 1 : installation vierge ───────────────────────────────────────────────
if ($setupStatus.allowed -eq $true) {
  Write-Host "Premiere configuration (setup initial)..."

  $body = @{
    username              = $AdminUser
    password              = $AdminPass
    org                   = $OrgName
    bucket                = $BucketName
    retentionPeriodSeconds = 2592000   # 30 jours
  } | ConvertTo-Json

  $result = Invoke-RestMethod "$InfluxUrl/api/v2/setup" `
    -Method POST -Body $body -ContentType "application/json"

  $token = $result.auth.token
  Write-Host "  Org '$OrgName', bucket '$BucketName' crees."
  Write-Host "  Token admin obtenu."
}

# ── Cas 2 : deja configure — connexion par session ────────────────────────────
else {
  Write-Host "InfluxDB deja configure. Connexion en cours..."

  $cred   = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("${AdminUser}:${AdminPass}"))
  $signinHeaders = @{ Authorization = "Basic $cred" }

  try {
    $signinResp = Invoke-WebRequest "$InfluxUrl/api/v2/signin" `
      -Method POST -Headers $signinHeaders -UseBasicParsing
  } catch {
    throw "Connexion echouee. Verifie les identifiants AdminUser/AdminPass dans le script."
  }

  $cookie    = ($signinResp.Headers["Set-Cookie"] -split ";")[0]
  $authHdr   = @{ Cookie = $cookie }
  $jsonHdr   = @{ Cookie = $cookie; "Content-Type" = "application/json" }

  # Recupere l'orgID
  $orgs  = Invoke-RestMethod "$InfluxUrl/api/v2/orgs?org=$OrgName" -Headers $authHdr
  $orgId = $orgs.orgs[0].id
  Write-Host "  Org '$OrgName' (id: $orgId)"

  # Cree le bucket si absent
  $bkts = Invoke-RestMethod "$InfluxUrl/api/v2/buckets?org=$OrgName" -Headers $authHdr
  $bkt  = $bkts.buckets | Where-Object { $_.name -eq $BucketName } | Select-Object -First 1
  if (-not $bkt) {
    Write-Host "  Creation du bucket '$BucketName'..."
    $bktBody = @{
      orgID          = $orgId
      name           = $BucketName
      retentionRules = @( @{ type = "expire"; everySeconds = 2592000 } )
    } | ConvertTo-Json
    $bkt = Invoke-RestMethod "$InfluxUrl/api/v2/buckets" -Method POST -Body $bktBody -Headers $jsonHdr
    Write-Host "  Bucket cree."
  } else {
    Write-Host "  Bucket '$BucketName' existe deja (id: $($bkt.id))."
  }

  # Verifie si un token collector existe deja
  $auths     = Invoke-RestMethod "$InfluxUrl/api/v2/authorizations?org=$OrgName" -Headers $authHdr
  $existing  = $auths.authorizations | Where-Object { $_.description -eq "pc-monitor-collector" } | Select-Object -First 1
  if ($existing) {
    Write-Host "  Token 'pc-monitor-collector' deja present, reutilisation."
    $token = $existing.token
  } else {
    Write-Host "  Creation d'un token collector..."
    $tBody = @{
      orgID       = $orgId
      description = "pc-monitor-collector"
      permissions = @(
        @{ action = "read";  resource = @{ type = "buckets"; orgID = $orgId; id = $bkt.id } },
        @{ action = "write"; resource = @{ type = "buckets"; orgID = $orgId; id = $bkt.id } }
      )
    } | ConvertTo-Json -Depth 5
    $auth  = Invoke-RestMethod "$InfluxUrl/api/v2/authorizations" -Method POST -Body $tBody -Headers $jsonHdr
    $token = $auth.token
    Write-Host "  Token cree."
  }
}

# ── Sauvegarde du token ───────────────────────────────────────────────────────
if (-not $token) { throw "Impossible d'obtenir un token. Verifie les logs ci-dessus." }

[System.Environment]::SetEnvironmentVariable("INFLUX_TOKEN", $token, "User")
Write-Host ""
Write-Host "Token sauvegarde dans INFLUX_TOKEN (variable env utilisateur)." -ForegroundColor Green
Write-Host "  Debut : $($token.Substring(0, [Math]::Min(24, $token.Length)))..."
Write-Host ""
Write-Host "Redemarrage du collector..."
Stop-ScheduledTask  -TaskName "PC-Monitor-Collector" -ErrorAction SilentlyContinue
Start-Sleep 2
Start-ScheduledTask -TaskName "PC-Monitor-Collector" -ErrorAction SilentlyContinue
Write-Host "  Collector repart."
Write-Host ""
Write-Host "Configuration terminee." -ForegroundColor Green
Write-Host "  InfluxDB : $InfluxUrl"
Write-Host "  Org      : $OrgName"
Write-Host "  Bucket   : $BucketName (30j retention)"
Write-Host "  Token    : INFLUX_TOKEN"
Write-Host ""
Write-Host "Les graphiques Energie se rempliront dans les prochaines minutes."
