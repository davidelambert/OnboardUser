<#
.SYNOPSIS
This script automates the onboarding process for new employees leveraging the REST APIs of common MSP tools.

.DESCRIPTION
This PowerShell script is designed to streamline the onboarding process in an IT environment. It manages user creation,
ticket handling, license assignments, and other essential tasks by connecting with Azure, Microsoft Graph, AutoTask,
Hudu, and OneTimeSecret.

.PARAMETER AppId
The Application (client) ID of the Azure App registration used for the Microsoft Graph and Exchangle Online APIs.
This app should be registered in the client's Azure tenant with API permissions as describedf in the NOTES section.

.PARAMETER TenantId
The client's Azure tenant (directory) ID.

.PARAMETER CertificateThumbprint
The thumbprint of an authentication certificate attached to the Azure registered app and to the Azure Automation 
account that will run this script.

.PARAMETER CompanyName
Client's company name. Name should be identical in AutoTask, Hudu, and Pax8.

.PARAMETER Domain
Domain name in which the new user will be created.

.PARAMETER SpSiteName
Name of a SharePoint site in the client's tenant containing company location data.

.PARAMETER SpListName
Name of the SharePoint list containing company location data. The list should have columns for location name, email, 
and AutoTask location ID.

.PARAMETER FirstName
First name of the new employee.

.PARAMETER LastName
Last name of the new employee.

.PARAMETER Location
Array of locations names where the employee will be working. If multiple locations are provided, the user will be
assigned to the "Multiple - ASK BEFORE ONSITE" location in AutoTask, but all locations will be added to the Entra 
ID profile.

.PARAMETER JobTitle
Job title of the new employee.

.PARAMETER Equipment
Array of equipment to be requested for the new employee (Optional).

.PARAMETER CreatedByEmail
Email of the person initiating the onboarding request. Typically gathered automatically from the user who added the new
employee to the front end SharePoint list.

.PARAMETER CreatedByDisplayName
Display name of the onboarding request initiator. Likewise gathered automatically from the front end SharePoint list editor.

.PARAMETER PasswordSender
Email used for sending password information via OneTimeSecret.

.PARAMETER LicenseName
Name or partial name of the Microsoft 365 license to be assigned to the new user. A list of currently supported 
license names can be found in the OnboardingUtilities module.

.PARAMETER ApprovalWebhookUrl
Webhook URL for the Azure Logic App which conditionally launches an email approval workflow when a new Microsoft 365
license is required.

.EXAMPLE
.\OnboardingScript.ps1 -AppId '6c2215a7-39de-4df2-9a0f-5ce814f87e9f' `
    -TenantId '315e5c10-3b21-4914-9b83-37bdf68e67ec' `
    -CertificateThumbprint 1234ABCD5678EFGH9012IJKL3456MNOP7890QRST `
    -CompanyName ExampleCorp `
    -Domain 'example.com' `
    -SpSiteName OnboardingData `
    -SpListName Location
    -FirstName John `
    -LastName Doe `
    -Location 'Main Office' `
    -JobTitle 'Software Engineer II' `
    -Equipment 'Laptop, Dock, Monitor' `
    -CreatedByEmail 'hiring.manager@example.com'
    -CreatedByDisplayName 'Hiring Manager'
    -PasswordSender 'onboarding@example.com'
    -LicenseName 'Business Premium'
    -ApprovalWebhookUrl 'https://prod-90.eastus.logic.azure.com:443/workflows/5b20125ee5c6404fa8132623130bae43/triggers/manual/paths/invoke?api-version=2016-10-01&sp=%2Ftriggers%2Fmanual%2Frun&sv=1.0&sig=hgNJehZVJHP0ieYtv1b_vthRvi-FXt8VI06vMWQOLao'

.NOTES
- All parameters are required except for `-Equipment`.
- If multiple locations are provided, the user will be assigned to the "Multiple - ASK BEFORE ONSITE" location in
AutoTask, but all locations will be added to the Entra ID profile.

.LINK
https://github.com/Integrid-LLC/OnboardUser
#>

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
    [string]$ApprovalWebhookUrl,

    [Parameter(Mandatory = $true)]
    [string]$FollowUpAutomationAccount,

    [Parameter(Mandatory = $true)]
    [string]$FollowUpResourceGroup,

    [Parameter(Mandatory = $true)]
    [string]$FollowUpRunbook
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


if ($Location.Count -gt 1) {
    $companyLocationId = Get-AutoTaskCompanyLocationId -LocationName "Multiple" `
        -CompanyId $atCompanyId -Credentials $atCredentials
}
else {
    $companyLocationId = Get-AutoTaskCompanyLocationId -LocationName $Location[0] `
        -CompanyId $atCompanyId -Credentials $atCredentials
}
if ($null -eq $companyLocationId) {
    Write-Warning "Failed to retrieve AutoTask Company Location ID. Assigning to principal location by default."
    $companyLocationId = Get-AutoTaskCompanyLocationId -LocationName "Principal" `
        -CompanyId $atCompanyId -Credentials $atCredentials
}


$LocationEmails = @()
foreach ($l in $Location) {
    $LocationEmails += $locationList | Where-Object { $_.Name -eq $l } | Select-Object -ExpandProperty Email
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


# License provisioning and Follow up runbook scheduling ================
$outputParams = [System.Collections.IDictionary]@{
    AppId                     = $AppId
    TenantId                  = $TenantId
    CertificateThumbprint     = $CertificateThumbprint
    CompanyName               = $CompanyName
    Domain                    = $Domain
    SpSiteName                = $SpSiteName
    SpListName                = $SpListName
    FirstName                 = $FirstName
    LastName                  = $LastName
    Location                  = $Location
    JobTitle                  = $JobTitle
    Equipment                 = $Equipment
    CreatedByEmail            = $CreatedByEmail
    CreatedByDisplayName      = $CreatedByDisplayName
    PasswordSender            = $PasswordSender
    LicenseName               = $LicenseName
    ApprovalWebhookUrl        = $ApprovalWebhookUrl
    FollowUpAutomationAccount = $FollowUpAutomationAccount
    FollowUpResourceGroup     = $FollowUpResourceGroup
    FollowUpRunbook           = $FollowUpRunbook
    UserPrincipalName         = $upn
    AutoTaskCompanyId         = $atCompanyId
    HuduCompanyId             = $huduCompanyId
    M365Location              = $m365Location
    AutoTaskLocationId        = $companyLocationId
    LocationEmails            = $LocationEmails
    UserData                  = $respNewUser
    AutoTaskTicketId          = $respNewTicket.ItemId
    AutoTaskTicketNumber      = $ticketContent.ticketNumber
    AutoTaskContactId         = $respNewContact.itemId
    HuduPasswordId            = $respHuduPw.asset_password.id
    OneTimeSecretSuccess      = $respOts
    LicenseData               = $licenseData
    LicenseApprovalRequired   = $licenseApprovalRequired
}

$licenseData = Get-LicenseData $LicenseName
if ($licenseData.ConsumedUnits -lt $licenseData.PrepaidUnits.Enabled) {
    $licenseApprovalRequired = $false
    $outputParams.Add("AddPax8License", $licenseApprovalRequired)

    $respAssignLicense = Set-MgUserLicense -UserId $upn -AddLicenses @{SkuId = $licenseData.SkuId } -RemoveLicenses @()
    if ($null -eq $respAssignLicense) {
        Write-Error "Failed to assign license `"$($LicenseName)`" to $($upn)" -ErrorAction Stop
    }
    else {
        Write-Output "=> License `"$($LicenseName)`" assigned to $($respAssignLicense.DisplayName)"
    }

    # Schedule follow up runbook ================
    $startTime = (Get-Date).AddMinutes(10).ToString("yyyy-MM-ddTHH:mm:ss")
    $scheduleName = $FirstName + $LastName
    $schedule = New-AzAutomationSchedule -Name $scheduleName -StartTime $startTime -TimeZone "America/New_York" -OneTime `
        -ResourceGroupName $FollowUpResourceGroup -AutomationAccountName $FollowUpAutomationAccount 
    if ($null -eq $schedule) {
        Write-Error "Failed to schedule follow up runbook" -ErrorAction Stop
    }
    else {
        Write-Output "=> Follow up runbook schedule `"$scheduleName`" created to run once at $startTime"
    }
    
    $scheduleJob = Register-AzAutomationScheduledRunbook -RunbookName $FollowUpRunbook -ScheduleName $scheduleName `
        -Parameters $outputParams -ResourceGroupName $FollowUpResourceGroup -AutomationAccountName $FollowUpAutomationAccount
    if ($null -eq $scheduleJob) {
        Write-Error "Failed to associate follow up runbook `"$FollowUpRunbook`" with schedule `"$scheduleName`"" -ErrorAction Stop
    }
    else {
        Write-Output "=> Follow up runbook `"$FollowUpRunbook`" succesfullyassociated with schedule `"$scheduleName`""
        Write-Output ("Follow up job details`n" + ("=" * 32))
        Write-Output $scheduleJob
    }
}
else {
    # Call license approval Logic App, call JobTitle from there
    Write-Output "=> Approval required to add `"$($LicenseName)`" license subscription for $upn"
    $licenseApprovalRequired = $true
    $outputParams.Add("AddPax8License", $licenseApprovalRequired)
    $approvalHeaders = @{
        "Content-Type" = "application/json"
    }
    $approvalBody = ConvertTo-Json $outputParams
    $respStartApproval = Invoke-RestMethod -Uri $ApprovalWebhookUrl -Method Post -Headers $approvalHeaders -Body $approvalBody
    if ($null -eq $respStartApproval) {
        Write-Error "Failed to start license approval logic app" -ErrorAction Stop
    }
    else {
        Write-Output "=> Started license approval logic app"
        Write-Output ("License approval job details`n" + ("=" * 32))
        Write-Output $respStartApproval
    }
}

# Summary Output ==================
Write-Output ("`n" + ("=" * 32))
Write-Output ("Job Summary`n" + ("=" * 32))
Write-Output $outputParams
Write-Output ("`nNew User Data`n" + ("=" * 32))
Write-Output $outputParams.UserData

Disconnect-MgGraph | Out-Null
Disconnect-AzAccount | Out-Null