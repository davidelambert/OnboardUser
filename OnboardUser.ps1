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
    [string]$CreatedByEmail,

    [Parameter(Mandatory = $true)]
    [string]$CreatedByDisplayName,
    
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
    Write-Error "Autotask API credentials not found" -ErrorAction Stop
}

$huduCredentials = @{}
$secret = Get-AzKeyVaultSecret -VaultName "IntegridAPIKeys" -Name "Hudu-ApiKey"
$value = ConvertFrom-SecureString $secret.SecretValue -AsPlainText
$huduCredentials.Add("x-api-key", $value)
if ($huduCredentials.Count -eq 0) {
    Write-Error "Hudu API credentials not found" -ErrorAction Stop
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
    Write-Error "OneTimeSecret API credentials not found" -ErrorAction Stop
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
    Write-Error "Pax8 API credentials not found" -ErrorAction Stop
}



# Variables =================
$atPicklist = Get-AutoTaskTicketPicklist $atCredentials
if ($atPicklist.Count -eq 0) {
    Write-Error "Autotask ticket picklist not found" -ErrorAction Stop
}


$atCompanyId = Get-AutoTaskCompanyId $CompanyName -Credentials $atCredentials
if ($null -eq $atCompanyId) {
    Write-Error "Failed to retrieve Autotask company ID" -ErrorAction Stop
}

$huduCompanyId = Get-HuduCompanyId $CompanyName -Credentials $huduCredentials
if ($null -eq $huduCompanyId) {
    Write-Error "Failed to retrieve Hudu company ID" -ErrorAction Stop
}


$locationList = Get-SPListItems -SiteName $SpSiteName -ListName $SpListName
if (($locationList.Count -eq 0) -or ($null -eq $locationList)) {
    Write-Error "Failed to retrieve SharePoint location list" -ErrorAction Stop
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

$respTicketContact = Get-AutoTaskContact $CreatedByEmail -CompanyId $atCompanyId -Credentials $atCredentials
if ($respTicketContact.pageDetails.count -eq 0) {
    $newCreatorContactParams = @{
        Credentials       = $atCredentials
        CompanyId         = $atCompanyId
        CompanyLocationId = $locationList | Where-Object { $_.Name -eq "Main Office" } | Select-Object -ExpandProperty LocationId
        FirstName         = $CreatedByDisplayName.Split(" ")[0]
        LastName          = $CreatedByDisplayName.Split(" ")[0]
        EmailAddress      = $CreatedByEmail
    }
    $respNewCreatorContact = New-AutoTaskContact @newCreatorContactParams
    if ($null -eq $respNewCreatorContact) {
        $ticketContactId = $null
        Write-Warning "Failed to create AutoTask contact for SharePoint list editor $CreatedByEmail. Ticket will be created with no contact."
    }
    else {
        $ticketContactId = $respNewCreatorContact.itemId
        Write-Output "=> AutoTask contact created for $CreatedByDisplayName with id: $ticketContactId"
    }
}
else {
    $ticketContactId = $respTicketContact.items[0].id
    Write-Output "=> AutoTask contact found for $CreatedByDisplayName with id: $ticketContactId"
}


$upn = "$FirstName.$LastName@$Domain"
$pwProfile = New-PasswordProfile


# Ticket, User, AT Contact, and Hudu Password =================
$issueType = (Get-AutoTaskPicklistItem -Picklist $atPicklist -Field "issueType" -Label "IMP-USER CHANGES").value
$subIssueType = Get-AutoTaskPicklistItem -Picklist $atPicklist -Field "subIssueType" -Label "Onboarding" | `
    Where-Object { $_.parentValue -eq $issueType } | Select-Object -ExpandProperty value

$newTicketParams = @{
    CreateDate     = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssZ")
    DueDate        = (Get-Date).AddDays(1).ToString("yyyy-MM-ddTHH:mm:ssZ")
    CompanyId      = $atCompanyId
    ContactId      = $ticketContactId
    Priority       = (Get-AutoTaskPicklistItem -Picklist $atPicklist -Field "priority" -Label "PIII Normal Response").value
    QueueId        = (Get-AutoTaskPicklistItem -Picklist $atPicklist -Field "queueid" -Label "Triage").value
    Status         = (Get-AutoTaskPicklistItem -Picklist $atPicklist -Field "status" -Label "Pre-Process").value
    TicketCategory = (Get-AutoTaskPicklistItem -Picklist $atPicklist -Field "ticketCategory" -Label "Implementation MS").value
    TicketType     = (Get-AutoTaskPicklistItem -Picklist $atPicklist -Field "ticketType" -Label "Change Request").value
    IssueType      = $issueType
    SubIssueType   = $subIssueType
    Title          = "**Test** - Onboarding New Employee $FirstName $LastName"
    Description    = "Automatic onboarding ticket for new employee $FirstName $LastName."
}
$respNewTicket = New-AutoTaskTicket -Credentials $atCredentials @newTicketParams
if ($null -eq $respNewTicket) {
    Write-Error "Failed to create AutoTask ticket" -ErrorAction Stop
}
else {
    $ticketContent = (Get-AutoTaskTicket -Credentials $atCredentials -TicketId $respNewTicket.ItemId).item
    Write-Output "=> Created AutoTask ticket number: $($ticketContent.ticketNumber)"
}


$respNewUser = New-MgUser -AccountEnabled -DisplayName "$FirstName $LastName" -MailNickname "$FistName$LastName" `
    -UserPrincipalName $upn -PasswordProfile $pwProfile -GivenName $FirstName -Surname $LastName `
    -JobTitle $JobTitle -OfficeLocation $m365Location -UsageLocation "US"
if ($null -eq $respNewUser) {
    Write-Error "Failed to create Entra ID user" -ErrorAction Stop
}
else {
    Write-Output "=> User created with Id: $($respNewUser.Id)"
}


$respNewContact = New-AutoTaskContact -Credentials $atCredentials `
    -CompanyId $atCompanyId -CompanyLocationId $companyLocationId `
    -FirstName $FirstName -LastName $LastName -EmailAddress $upn
if ($null -eq $respNewContact) {
    Write-Warning "Failed to create AutoTask Contact for $upn."
}
else {
    Write-Output "=> AutoTask Contact created with Id: $($respNewContact.itemId)"
}


$respHuduPw = New-HuduPassword -Credentials $huduCredentials -CompanyId $huduCompanyId `
    -Name "$FirstName $LastName" -Email $upn -Password $pwProfile.Password
if ($null -eq $respHuduPw) {
    Write-Warning "Failed to add password for $upn to Hudu. User has been created, but password is undocumented."
}
else {
    Write-Output "=> Hudu password created with Id: $($respHuduPw.asset_password.id)"
}


$respOts = Send-OTSPassword -EmployeeName "$FirstName $LastName" -Secret $pwProfile.Password `
    -SenderEmail $PasswordSender -RecipientEmail $CreatedByEmail -Credentials $otsCredentials
if ($respOts) {
    Write-Output "=> OneTimeSecret password notification sent to $CreatedByEmail for new user $upn"
}
else {
    Write-Warning "Failed to send OneTimeSecret password notification to $CreatedByEmail for new user $upn. Password will need to be reset manually and sent to $CreatedByEmail."
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
    UserPrincipalName     = $upn
    CommunityEmails       = $communityEmails
    AutoTaskTicketId      = $respNewTicket.ItemId
    AutoTaskTicketNumber  = $ticketContent.ticketNumber
    CreatedByEmail        = $CreatedByEmail
    CreatedByDisplayName  = $CreatedByDisplayName
    LicenseName           = $LicenseName
    CompanyName           = $CompanyName
}

$licenseData = Get-LicenseData $LicenseName
if ($licenseData.ConsumedUnits -lt $licenseData.PrepaidUnits.Enabled) {
    $licenseApprovalRequired = $false
    $jobTitleParams.Add("AddPax8License", $licenseApprovalRequired)

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
    # Call license approval Logic App, call JobTitle from there
    $licenseApprovalRequired = $true
    $jobTitleParams.Add("AddPax8License", $licenseApprovalRequired)
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
    CreatedByEmail        = $CreatedByEmail
    CreatedByDisplayName  = $CreatedByDisplayName
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
    AutoTaskTicketNumber    = $ticketContent.ticketNumber
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
Write-Output ("`nUser Data`n" + ("=" * 32))
Write-Output $Outputs.UserData

Disconnect-MgGraph | Out-Null
Disconnect-AzAccount | Out-Null