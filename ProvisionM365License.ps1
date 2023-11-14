param(
    [Parameter(Mandatory = $true)]
    [object]$InputParameters,

    [Parameter(Mandatory = $true)]
    [object]$Returns
)

Import-Module OnboardingUtilities

# Connect-AzAccount -Identity -Subscription "Integrid Development" | Out-Null
# Connect-MgGraph -AppId $AppId -TenantId $TenantId -CertificateThumbprint $CertificateThumbprint -NoWelcome

foreach ($key in $InputParameters.Keys) {
    if (Test-Path variable:$key) {
        Remove-Variable -Name $key
    }
    New-Variable -Name $key -Value $InputParameters[$key]
    Write-Output $key
}



# if ($licenseData.ConsumedUnits -lt $licenseData.PrepaidUnits.Enabled) {
#     $respAssignLicense = Set-MgUserLicense -UserId $upn -AddLicenses @{SkuId = $licenseData.SkuId } -RemoveLicenses @()
#     if ($null -eq $respAssignLicense) {
#         Write-Output "=> Failed to assign license"
#     }
#     else {
#         Write-Output "=> License assigned to user $($respAssignLicense.DisplayName)"
#     }
# }
# else {
#     $token = Get-Pax8Token $Pax8Credentials
#     $companyId = Get-Pax8CompanyId -CompanyName "$CompanyName" -Token $token
#     $productId = Search-Pax8ProductIds $LicenseName
#     $subscription = Get-Pax8Subscription -CompanyId $companyId -ProductId $productId -Token $token
#     $qtyIncremented = $subscription.quantity + 1
#     $respAddLicense = Add-Pax8Subscription -SubscriptionId $subscription.id -Quantity $qtyIncremented -Token $token
#     if ($null -eq $respAddLicense) {
#         Write-Output "=> Failed to add license to PAX8 subscription"
#     }
#     else {
#         Write-Output "=> License added to PAX8 subscription id: $($respAddLicense.id)"d
#     }
    
#     # Check license quantities in M365 every 30 seconds until new one shows up.
#     do {
#         Start-Sleep -Seconds 30
#         $l = Get-LicenseData $LicenseName
#     }
#     while ($l.ConsumedUnits -ge $l.PrepaidUnits.Enabled)
#     $respAssignLicense = Set-MgUserLicense -UserId $upn -AddLicenses @{SkuId = $licenseData.SkuId } -RemoveLicenses @()
#     if ($null -eq $respAssignLicense) {
#         Write-Output "=> Failed to assign license"
#     }
#     else {
#         Write-Output "=> License assigned to user $($respAssignLicense.DisplayName)"
#     }
# }


# # Pass selected output as parameters to separate client-specific runbook
# $jobTitleParams = [System.Collections.IDictionary]@{
#     AppId                 = $AppId
#     TenantId              = $TenantId
#     CertificateThumbprint = $CertificateThumbprint
#     FirstName             = $FirstName
#     LastName              = $LastName
#     UPN                   = $upn
#     JobTitle              = $JobTitle
#     Location              = $Location
#     CommunityEmails       = $communityEmails
#     Equipment             = $Equipment
#     AutoTaskTicketId      = $respNewTicket.ItemId
# }
# Write-Output ("`nStarting JobTitleTasks runbook with parameters:`n" + ("=" * 48))
# Write-Output $jobTitleParams

# # Schedule JobTitleTasks ================
# $resourceGroupName = "RG-Dev"
# $automationAccountName = "Onboarding-Wynnefield"
# $startTime = (Get-Date).AddMinutes(7).ToString("yyyy-MM-ddTHH:mm:ss")

# $scheduleName = "$FirstName$LastName"
# $schedule = New-AzAutomationSchedule -Name $scheduleName -StartTime $startTime -TimeZone "America/New_York" -OneTime `
#     -ResourceGroupName $resourceGroupName -AutomationAccountName $automationAccountName 
# Write-Output ("One-Time Schedule`n" + ("=" * 24))
# Write-Output $schedule

# $runbookName = "JobTitleTasks"
# $scheduleJob = Register-AzAutomationScheduledRunbook -RunbookName $runbookName -ScheduleName $scheduleName `
#     -Parameters $jobTitleParams -ResourceGroupName $resourceGroupName -AutomationAccountName $automationAccountName
# Write-Output ("Scheduled Runbook Job`n" + ("=" * 24))
# Write-Output $scheduleJob