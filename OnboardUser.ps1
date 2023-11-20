param(
    [Parameter(Mandatory = $true)]
    [string]$AppId,

    [Parameter(Mandatory = $true)]
    [string]$TenantId,

    [Parameter(Mandatory = $true)]
    [string]$CertificateThumbprint,

    [Parameter(Mandatory = $true)]
    [string]$CompanyName,

    [Parameter(Mandatory = $true)]
    [string]$Domain,
    
    [Parameter(Mandatory = $true)]
    [string]$SpSiteName,

    [Parameter(Mandatory = $true)]
    [string]$SpListName,
    
    [Parameter(Mandatory = $true)]
    [string]$FirstName,

    [Parameter(Mandatory = $true)]
    [string]$LastName,

    [Parameter(Mandatory = $true)]
    [string[]]$Location,
    
    [Parameter(Mandatory = $true)]
    [string]$JobTitle,
    
    [Parameter(Mandatory = $false)]
    [string[]]$Equipment,
    
    [Parameter(Mandatory = $true)]
    [string]$CreatedBy,
    
    [Parameter(Mandatory = $true)]
    [string]$PasswordSender,
    
    [Parameter(Mandatory = $true)]
    [string]$LicenseName,

    [Parameter(Mandatory = $true)]
    [string]$ApprovalWebhookUrl
)

Import-Module OnboardingUtilities

Connect-AzAccount -Identity -Subscription "Integrid Development" | Out-Null
Connect-MgGraph -AppId $AppId -TenantId $TenantId -CertificateThumbprint $CertificateThumbprint -NoWelcome

# API Credentials ===============
$atSecretNames = @("Autotask-ApiIntegrationCode", "Autotask-UserName", "Autotask-Secret")
$atCredentials = @{}
foreach ($sn in $atSecretNames) {
    $name = $sn.Replace("Autotask-", "")
    $secret = Get-AzKeyVaultSecret -VaultName "IntegridAPIKeys" -Name $sn
    $value = ConvertFrom-SecureString $secret.SecretValue -AsPlainText
    $atCredentials.Add($name, $value)
}
if ($atCredentials.Count -eq 0) {
    throw "Autotask API credentials not found"
}

$huduCredentials = @{}
$secret = Get-AzKeyVaultSecret -VaultName "IntegridAPIKeys" -Name "Hudu-ApiKey"
$value = ConvertFrom-SecureString $secret.SecretValue -AsPlainText
$huduCredentials.Add("x-api-key", $value)
if ($huduCredentials.Count -eq 0) {
    throw "Hudu API credentials not found"
}

$otsSecretNames = @("OneTimeSecret-Username", "OneTimeSecret-ApiKey")
$otsCredentials = @{}
foreach ($sn in $otsSecretNames) {
    $name = $sn.Replace("OneTimeSecret-", "")
    $secret = Get-AzKeyVaultSecret -VaultName "IntegridAPIKeys" -Name $sn
    $value = ConvertFrom-SecureString $secret.SecretValue -AsPlainText
    $otsCredentials.Add($name, $value)
}
if ($otsCredentials.Count -eq 0) {
    throw "OneTimeSecret API credentials not found"
}

$pax8SecretNames = @("Pax8-client-id", "Pax8-client-secret")
$pax8Credentials = @{}
foreach ($sn in $pax8SecretNames) {
    $name = $sn.Replace("Pax8-", "")
    $name = $name.Replace("-", "_")
    $secret = Get-AzKeyVaultSecret -VaultName "IntegridAPIKeys" -Name $sn
    $value = ConvertFrom-SecureString $secret.SecretValue -AsPlainText
    $pax8Credentials.Add($name, $value)
}
if ($pax8Credentials.Count -eq 0) {
    throw "Pax8 API credentials not found"
}



# Variables =================
$atPicklist = Get-AutoTaskTicketPicklist $atCredentials
if ($atPicklist.Count -eq 0) {
    throw "Autotask ticket picklist not found"
}


$atCompanyId = Get-AutoTaskCompanyId $CompanyName -Credentials $atCredentials
if ($null -eq $atCompanyId) {
    throw "Failed to retrieve Autotask company ID"
}


$huduCompanyId = Get-HuduCompanyId $CompanyName -Credentials $huduCredentials
if ($null -eq $huduCompanyId) {
    throw "Failed to retrieve Hudu company ID"
}


$locationList = Get-SPListItems -SiteName $SpSiteName -ListName $SpListName
if (($locationList.Count -eq 0) -or ($null -eq $locationList)) {
    throw "Failed to retrieve SharePoint location list"
}
$locationList = Format-LocationList $locationList


$m365Location = if ($Location.Count -gt 1) {
    "Multiple locations"
}
else {
    $Location[0]
}


$companyLocationId = if ($Location.Count -gt 1) {
    $locationList | Where-Object { $_.Name -eq "Multiple - ASK BEFORE ONSITE" } `
    | Select-Object -ExpandProperty LocationId
}
else {
    $locationList | Where-Object { $_.Name -eq $Location[0] } `
    | Select-Object -ExpandProperty LocationId
}
if ($null -eq $companyLocationId) {
    Write-Warning "Failed to retrieve AutoTask Company Location ID. Assigning to Main Office by default."
    $companyLocationId = $locationList | Where-Object { $_.Name -eq "Main Office" } `
    | Select-Object -ExpandProperty LocationId
}


$communityEmails = @()
foreach ($l in $Location) {
    $communityEmails += $locationList | Where-Object { $_.Name -eq $l } | Select-Object -ExpandProperty Email
}


$upn = "$FirstName.$LastName@$Domain"
$pwProfile = New-PasswordProfile


# Main script =================
$newTicketParams = @{
    CreateDate   = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssZ")
    DueDate      = (Get-Date).AddDays(1).ToString("yyyy-MM-ddTHH:mm:ssZ")
    CompanyId    = $atCompanyId
    Priority     = Get-AutoTaskPicklistValue -Picklist $atPicklist -Field "priority" -Label "PIII Normal Response"
    QueueId      = Get-AutoTaskPicklistValue -Picklist $atPicklist -Field "queueid" -Label "Triage"
    Status       = Get-AutoTaskPicklistValue -Picklist $atPicklist -Field "status" -Label "New(Portal)~"
    TicketType   = Get-AutoTaskPicklistValue -Picklist $atPicklist -Field "ticketType" -Label "Change Request"
    IssueType    = Get-AutoTaskPicklistValue -Picklist $atPicklist -Field "issueType" -Label "HD-Email"
    SubIssueType = Get-AutoTaskPicklistValue -Picklist $atPicklist -Field "subIssueType" -Label "Microsoft 365"
    Title        = "**Test** - Onboarding New Employee $FirstName $LastName"
    Description  = "Automatic onboarding ticket for new employee $FirstName $LastName."
}
$respNewTicket = New-AutoTaskTicket -Credentials $atCredentials @newTicketParams
if ($null -eq $respNewTicket) {
    Write-Output "=> Failed to create ticket"
}
else {
    Write-Output "=> AutoTask ticket created with Id: $($respNewTicket.ItemId)"
}


$respNewUser = New-MgUser -AccountEnabled -DisplayName "$FirstName $LastName" -MailNickname "$FistName$LastName" `
    -UserPrincipalName $upn -PasswordProfile $pwProfile -GivenName $FirstName -Surname $LastName `
    -JobTitle $JobTitle -OfficeLocation $m365Location -UsageLocation "US"
if ($null -eq $respNewUser) {
    Write-Output "=> Failed to create user"
}
else {
    Write-Output "=> User created with Id: $($respNewUser.Id)"
}


$respNewContact = New-AutoTaskContact -Credentials $atCredentials `
    -CompanyId $atCompanyId -CompanyLocationId $companyLocationId `
    -FirstName $FirstName -LastName $LastName -EmailAddress $upn
if ($null -eq $respNewContact) {
    Write-Output "=> Failed to create contact"
}
else {
    Write-Output "=> AutoTask Contact created with Id: $($respNewContact.itemId)"
}


$respHuduPw = New-HuduPassword -Credentials $huduCredentials -CompanyId $huduCompanyId `
    -Name "$FirstName $LastName" -Email $upn -Password $pwProfile.Password
if ($null -eq $respHuduPw) {
    Write-Output "=> Failed to create Hudu password"
}
else {
    Write-Output "=> Hudu password created with Id: $($respHuduPw.asset_password.id)"
}


$respOts = Send-OTSPassword -EmployeeName "$FirstName $LastName" -Secret $pwProfile.Password `
    -SenderEmail $PasswordSender -RecipientEmail $CreatedBy -Credentials $otsCredentials
if ($respOts) {
    Write-Output "=> OneTimeSecret password sent to $CreatedBy"
}
else {
    Write-Output "=> Failed to send OneTimeSecret password notification to $CreatedBy"
}

# License provisioning and JobTitleTasks scheduling ================
$jobTitleParams = [System.Collections.IDictionary]@{
    AppId                 = $AppId
    TenantId              = $TenantId
    CertificateThumbprint = $CertificateThumbprint
    FirstName             = $FirstName
    LastName              = $LastName
    JobTitle              = $JobTitle
    Location              = $Location
    Equipment             = $Equipment
    UPN                   = $upn
    CommunityEmails       = $communityEmails
    AutoTaskTicketId      = $respNewTicket.ItemId
    CreatedBy             = $CreatedBy
    LicenseName           = $LicenseName
    CompanyName           = $CompanyName
    AddPax8License        = $licenseApprovalRequired
}

$licenseData = Get-LicenseData $LicenseName
if ($licenseData.ConsumedUnits -lt $licenseData.PrepaidUnits.Enabled) {
    $licenseApprovalRequired = $false
    $respAssignLicense = Set-MgUserLicense -UserId $upn -AddLicenses @{SkuId = $licenseData.SkuId } -RemoveLicenses @()
    if ($null -eq $respAssignLicense) {
        Write-Error "Failed to assign license `"$($LicenseName)`" to $($upn)" -ErrorAction Stop
    }
    else {
        Write-Output "=> License `"$($LicenseName)`" assigned to $($respAssignLicense.DisplayName)"
    }

    # Schedule JobTitleTasks ================
    Write-Output ("`nScheduling JobTitleTasks runbook with parameters:`n" + ("=" * 48))
    Write-Output $jobTitleParams
    
    $resourceGroupName = "RG-Dev"
    $automationAccountName = "Onboarding-Wynnefield"
    $startTime = (Get-Date).AddMinutes(10).ToString("yyyy-MM-ddTHH:mm:ss")
    $scheduleName = $FirstName + $LastName
    $schedule = New-AzAutomationSchedule -Name $scheduleName -StartTime $startTime -TimeZone "America/New_York" -OneTime `
        -ResourceGroupName $resourceGroupName -AutomationAccountName $automationAccountName 
    Write-Output ("One-Time Schedule`n" + ("=" * 32))
    Write-Output $schedule
    
    $runbookName = "JobTitleTasks"
    $scheduleJob = Register-AzAutomationScheduledRunbook -RunbookName $runbookName -ScheduleName $scheduleName `
        -Parameters $jobTitleParams -ResourceGroupName $resourceGroupName -AutomationAccountName $automationAccountName
    Write-Output ("Scheduled Runbook Job`n" + ("=" * 32))
    Write-Output $scheduleJob
}
else {
    $licenseApprovalRequired = $true
    $approvalHeaders = @{
        "Content-Type" = "application/json"
    }
    $approvalBody = ConvertTo-Json $jobTitleParams
    Invoke-RestMethod -Uri $ApprovalWebhookUrl -Method Post -Headers $approvalHeaders -Body $approvalBody
}

# Summary Output ==================
$InputParameters = @{
    AppId                 = $AppId
    TenantId              = $TenantId
    CertificateThumbprint = $CertificateThumbprint
    CompanyName           = $CompanyName
    Domain                = $Domain
    SpSiteName            = $SpSiteName
    SpListName            = $SpListName
    FirstName             = $FirstName
    LastName              = $LastName
    Location              = $Location
    JobTitle              = $JobTitle
    Equipment             = $Equipment
    CreatedBy             = $CreatedBy
    PasswordSender        = $PasswordSender
    LicenseName           = $LicenseName
    ApprovalWebhookUrl    = $ApprovalWebhookUrl
}

$Outputs = @{
    UserPrincipalName       = $upn
    AutoTaskCompanyId       = $atCompanyId
    HuduCompanyId           = $huduCompanyId
    M365Location            = $m365Location
    AutoTaskLocationId      = $companyLocationId
    CommunityEmailList      = $communityEmails
    UserData                = $respNewUser
    AutoTaskTicketId        = $respNewTicket.ItemId
    AutoTaskContactId       = $respNewContact.itemId
    HuduPasswordId          = $respHuduPw.asset_password.id
    OneTimeSecretSuccess    = $respOts
    LicenseData             = $licenseData
    LicenseApprovalRequired = $licenseApprovalRequired
}

Write-Output ("`nInput Parameters`n" + ("=" * 32))
Write-Output $InputParameters
Write-Output ("`nOutputs`n" + ("=" * 32))
Write-Output $Outputs
Write-Output ("`nLicense Approval Required`n" + ("=" * 32))
Write-Output $Outputs.LicenseApprovalRequired
Write-Output ("`nUser Data`n" + ("=" * 32))
Write-Output $Outputs.UserData

Disconnect-MgGraph | Out-Null
Disconnect-AzAccount | Out-Null