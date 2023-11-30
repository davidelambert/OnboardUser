param (
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$AutomationAccountName
)

$graphScopes = @(
    "Directory.ReadWrite.All",
    "Group.ReadWrite.All",
    "Mail.ReadWrite",
    "Mail.Send",
    "Organization.Read.All",
    "Sites.Manage.All",
    "User.ReadWrite.All",
    "UserAuthenticationMethod.ReadWrite.All"
)

# Connect as an Administrator, NOT the Automation account
Connect-MgGraph -Scopes "Application.Read.All", "AppRoleAssignment.ReadWrite.All,RoleManagement.ReadWrite.Directory" -NoWelcome
$managedIdentityId = (Get-MgServicePrincipal -Filter "displayName eq '$AutomationAccountName'").Id
$graphApp = Get-MgServicePrincipal -Filter "AppId eq '00000003-0000-0000-c000-000000000000'" # always this GUID
foreach ($scope in $graphScopes) {
    $appRole = $graphApp.AppRoles | Where-Object { $_.Value -eq $scope }
    New-MgServicePrincipalAppRoleAssignment -PrincipalId $managedIdentityId `
        -ServicePrincipalId $managedIdentityId `
        -ResourceId $graphApp.Id `
        -AppRoleId $appRole.Id
}