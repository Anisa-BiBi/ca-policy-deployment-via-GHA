# Connect to Microsoft Graph
$ApplicationId = $env:AZURE_CLIENT_ID
$SecuredPassword = $env:AZURE_CLIENT_SECRET
$tenantID = $env:AZURE_TENANT_ID
$ntfyUrl = $env:NTFY_URL
$workflowName = $env:WORKFLOW_NAME
$runId = $env:RUN_ID

# Create secure credential
$SecuredPasswordPassword = ConvertTo-SecureString -String $SecuredPassword -AsPlainText -Force
$ClientSecretCredential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $ApplicationId, $SecuredPasswordPassword

# Connect to Microsoft Graph
Connect-MgGraph -TenantId $tenantID -ClientSecretCredential $ClientSecretCredential | Out-Null

# Define the path to the directory containing your JSON files
$jsonFilesDirectory = "./policies/"

# Get all JSON files in the directory
$jsonFiles = Get-ChildItem -Path $jsonFilesDirectory -Filter *.json

# Initialize counters for summary
$created = 0
$updated = 0
$removed = 0
$failed = 0
$summary = @()

# Get existing policies
Write-Host "Retrieving existing policies..." -ForegroundColor Cyan
$existingPolicies = Get-MgIdentityConditionalAccessPolicy

# Create a hashtable of policies defined in JSON files
$definedPolicies = @{}
if ($jsonFiles.Count -gt 0) {
    foreach ($jsonFile in $jsonFiles) {
        try {
            $policyJson = Get-Content -Path $jsonFile.FullName | ConvertFrom-Json
            $definedPolicies[$policyJson.displayName] = $jsonFile.FullName
        } catch {
            Write-Host "Error reading policy file $($jsonFile.FullName): $_" -ForegroundColor Red
            $failed++
            $summary += "FAILED TO READ: $($jsonFile.FullName) - Error: $_"
        }
    }
}

# First, process existing policies that need to be updated or removed
foreach ($existingPolicy in $existingPolicies) {
    # Skip policies that don't follow our managed naming convention
    if (!$existingPolicy.DisplayName.StartsWith("GH - ")) { continue }
    
    if ($definedPolicies.ContainsKey($existingPolicy.DisplayName)) {
        # Policy exists in repo - it will be processed in the next loop
        continue
    } else {
        # Policy exists in Azure but not in repo - delete it
        try {
            Write-Host "Removing policy no longer in repository: $($existingPolicy.DisplayName)" -ForegroundColor Magenta
            Remove-MgIdentityConditionalAccessPolicy -ConditionalAccessPolicyId $existingPolicy.Id
            Write-Host "Policy removed successfully: $($existingPolicy.DisplayName)" -ForegroundColor Green
            $removed++
            $summary += "REMOVED: $($existingPolicy.DisplayName)"
        } catch {
            Write-Host "Error removing policy $($existingPolicy.DisplayName): $_" -ForegroundColor Red
            $failed++
            $summary += "FAILED TO REMOVE: $($existingPolicy.DisplayName) - Error: $_"
        }
    }
}

# Now process the JSON files for creation/update
foreach ($jsonFile in $jsonFiles) {
    try {
        # Read the content of the JSON file and convert it to a PowerShell object
        $policyJson = Get-Content -Path $jsonFile.FullName | ConvertFrom-Json

        # Create a custom object
        $policyObject = [PSCustomObject]@{
            displayName     = $policyJson.displayName
            conditions      = $policyJson.conditions
            grantControls   = $policyJson.grantControls
            sessionControls = $policyJson.sessionControls
            state           = $policyJson.state
        }

        # Convert the custom object to JSON with a depth of 10
        $policyJsonString = $policyObject | ConvertTo-Json -Depth 10

        # Check if a policy with the same display name already exists
        $existingPolicy = $existingPolicies | Where-Object { $_.DisplayName -eq $policyJson.displayName }

        if ($existingPolicy) {
            # Update the existing policy
            Write-Host "Policy already exists: $($policyJson.displayName) - Updating..." -ForegroundColor Yellow
            $null = Update-MgIdentityConditionalAccessPolicy -ConditionalAccessPolicyId $existingPolicy.Id -Body $policyJsonString
            Write-Host "Policy updated successfully: $($policyJson.displayName)" -ForegroundColor Green
            $updated++
            $summary += "UPDATED: $($policyJson.displayName)"
        } else {
            # Create a new policy
            Write-Host "Creating new policy: $($policyJson.displayName)" -ForegroundColor Cyan
            $null = New-MgIdentityConditionalAccessPolicy -Body $policyJsonString
            Write-Host "Policy created successfully: $($policyJson.displayName)" -ForegroundColor Green
            $created++
            $summary += "CREATED: $($policyJson.displayName)"
        }
    }
    catch {
        # Print an error message if an exception occurs
        Write-Host "An error occurred while processing the policy file '$($jsonFile.FullName)': $_" -ForegroundColor Red
        $failed++
        $summary += "FAILED: $($jsonFile.Name) - Error: $_"
    }
}

# Print summary
Write-Host "`nDEPLOYMENT SUMMARY:" -ForegroundColor Cyan
Write-Host "Policies Created: $created" -ForegroundColor Green
Write-Host "Policies Updated: $updated" -ForegroundColor Yellow
Write-Host "Policies Removed: $removed" -ForegroundColor Magenta
Write-Host "Operations Failed: $failed" -ForegroundColor $(if ($failed -gt 0) { "Red" } else { "Green" })
Write-Host "`nDetailed Results:" -ForegroundColor Cyan
$summary | ForEach-Object { Write-Host $_ }

# Send notification
Write-Host "`nSending notification..." -ForegroundColor Cyan

# Build detailed message
if ($failed -gt 0) {
    $title = "CA Policy Deployment Completed with Errors"
    $priority = "high"
    $tags = "warning"
} else {
    $title = "CA Policy Deployment Successful"
    $priority = "default"
    $tags = "white_check_mark"
}

$timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")

$message = @"
## Conditional Access Policy Deployment Summary

**Time**: $timestamp
**Workflow**: $workflowName
**Run ID**: $runId

### Results:
- ✅ Created: $created
- 🔄 Updated: $updated
- 🗑️ Removed: $removed
- ❌ Failed: $failed

"@

# Add details if there are any
if ($summary.Count -gt 0) {
    $message += "### Details:`n"
    foreach ($detail in $summary) {
        $message += "- $detail`n"
    }
}

# Send notification
$headers = @{
    "Title" = $title
    "Priority" = $priority
    "Tags" = $tags
}

try {
    Write-Host "Sending notification to $ntfyUrl" -ForegroundColor Cyan
    Invoke-RestMethod -Method Post -Uri $ntfyUrl -Headers $headers -Body $message
    Write-Host "Notification sent successfully" -ForegroundColor Green
} catch {
    Write-Host "Failed to send notification: $_" -ForegroundColor Red
    # Continue execution even if notification fails
}
