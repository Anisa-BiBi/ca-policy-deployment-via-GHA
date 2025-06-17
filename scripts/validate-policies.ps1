# Validate policy naming conventions
Write-Host "Starting policy validation..." -ForegroundColor Cyan

# Check if policies directory exists
if (-not (Test-Path -Path "./policies")) {
  Write-Host "Policies directory not found!" -ForegroundColor Red
  exit 1
}

# Find JSON files
$jsonFiles = Get-ChildItem -Path "./policies" -Filter "*.json" -File

if ($jsonFiles.Count -eq 0) {
  Write-Host "No policy files found in the policies directory." -ForegroundColor Yellow
  exit 0
}

Write-Host "Found $($jsonFiles.Count) policy files. Validating naming conventions..." -ForegroundColor Cyan

$fileNamingErrors = 0
$displayNameErrors = 0
$jsonFormatErrors = 0

foreach ($file in $jsonFiles) {
  # Check file name
  if (-not $file.Name.StartsWith("GH - ")) {
    Write-Host "File $($file.Name) does not follow the naming convention 'GH - '" -ForegroundColor Red
    $fileNamingErrors++
  }
  
  # Check display name in JSON
  try {
    $policyContent = Get-Content -Path $file.FullName | ConvertFrom-Json
    $displayName = $policyContent.displayName
    
    if (-not $displayName.StartsWith("GH - ")) {
      Write-Host "Policy in $($file.Name) has displayName '$displayName' which does not follow the naming convention 'GH - '" -ForegroundColor Red
      $displayNameErrors++
    }
  } catch {
    Write-Host "Failed to parse JSON in file $($file.Name): $_" -ForegroundColor Red
    $jsonFormatErrors++
  }
}

# Report results
Write-Host "`nValidation complete." -ForegroundColor Cyan
Write-Host "File naming errors: $fileNamingErrors" -ForegroundColor $(if ($fileNamingErrors -gt 0) { "Red" } else { "Green" })
Write-Host "Display name errors: $displayNameErrors" -ForegroundColor $(if ($displayNameErrors -gt 0) { "Red" } else { "Green" })
Write-Host "JSON format errors: $jsonFormatErrors" -ForegroundColor $(if ($jsonFormatErrors -gt 0) { "Red" } else { "Green" })

# Fail if any errors were found
if ($fileNamingErrors -gt 0 -or $displayNameErrors -gt 0 -or $jsonFormatErrors -gt 0) {
  Write-Host "`nValidation failed. Please fix the issues above." -ForegroundColor Red
  exit 1
} else {
  Write-Host "`nAll policy files and display names follow the naming convention!" -ForegroundColor Green
  exit 0
}
