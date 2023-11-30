## Integrid User Onboarding

### Environment Setup

1. Create a new Azure Automation Account in the **provider's** tenant. For example, `Onboarding-ExampleCorp`
    - Install the [Integrid OnboardingUtilities PowerShell module](https://github.com/Integrid-LLC/OnboardingUtilities) for PowerShell runtime version 7.2
    - Install the following modules from PowerShell Gallery for runtime version 7.2:
        - Microsoft.Graph.Authentication (**NOTE:** Must be installed prior to other Microsoft Graph modules)
        - Microsoft.Graph.Groups
        - Microsoft.Graph.Identity.DirectoryManagement
        - Microsoft.Graph.Sites
        - Microsoft.Graph.Users
        - Microsoft.Graph.Users.Actions
        - ExchangeOnlineManagement
        - OneTimeSecret
    - Install any other modules necessary for custom tenant actions

1. Navigate to the _Automation Accounts => \[Automation Account name\] => Identity_ tab
    - Enable the system assigned managed identity for the account
    - Click the _Azure role assignments_ button and enable the following Azure RBAC role assignments for the resource group to which the Automation Account belongs:
        - Virtual Machine Contributor
        - Automation Contributor
        - Key Vault Secrets User

1. Create a new App registration in **client's** tenant. For example `OnboardingApp`
    - Create the app as single-tenant ("Accounts in this organizational directory only (\[Organization name\] only - Single tenant)")
    - After creating the app, note down the **Application (client) ID** and **Directory (tenant) ID**. These IDs are used extensively by various functions.

1. Navigate to the _App registration => API permissions_ tab
    - Click "Add a permission" => click "Microsoft Graph"
        - Click "Application permissions"
        - Add the following Microsoft Graph API application permissions:
            - Directory.ReadWrite.All
            - Group.ReadWrite.All
            - Mail.ReadWrite
            - Mail.Send
            - Organization.Read.All
            - Sites.Manage.All
            - User.ReadWrite.All 
            - UserAuthenticationMethod.ReadWrite.All
    - Click "Add a permission" => click "APIs my organization uses"
        - Search for and select "Office 365 Exchange Online"
        - Click "Application permissions"
        - Add the "Exchange.ManageAsApp" application permissions
    - On the main API permissions tab, click "Grant admin consent for \[Organization name\]" consent to the added API permssions on behalf of the client

1. Run the `SetupGraph.ps1` script on a local machine, supplying the Automation Account name
    - Example: `.\SetupGraph.ps1 'Onboarding-ExampleCorp'`
    - When prompted with a web-based Entra ID login, sign in as a Global Administrator in the **client's** tenant
    - This script will authorize the Automation Account's Managed Identity to use the Microsoft Graph API as an application

1. Navigate to the _App registration => Manifest_ tab
    - In the JSON manifest, locate the `"requiredResourceAccess"` array
        - This array should already have one top-level object with several nested objects. These were added by the `SetupGraph.ps1` script in the previous step.
        - Add the following JSON object to the `"requiredResourceAccess"` array, either before or after the existing object:
            ```
            {
                "resourceAppId": "00000002-0000-0ff1-ce00-000000000000",
                "resourceAccess": [
                    {
                        "id": "dc50a0fb-09a3-484d-be87-e023b12c6440",
                        "type": "Role"
                    }
                ]
            }
            ```
        - Click "Save"

1. Run the `GenerateCertificate.ps1` script
    - When prompted for credentials:
        - Theoretically, any username and password will work. However, it is strongly recommended to enter a username matching an administrator in the client organization.
        - Note the password and store the credentials securely. The password will be used in firther steps.
    - The script generates public (`.cer`) and private (`.pfx`) security certificates in the supplied directory.

1. In the client's Azure tenant, navigate to the _App registrations => Certificates & secrets_ tab
    - On the "Certificates" display tab, click "Upload certificate"
    - Upload the public `.cer` security certificate generated above by `GenerateCertificate.ps1`
    - Note down the certificate's Thumbprint. This is used along with the app registration's Application ID and Tenant ID to allow secure programmatic access by the Automation Account's Managed Identity.

1. In the client's Azure tenant, navigate to the _Automation Accounts => OnboardingAutomation => Certificates_ tab
    - Click "Add a certificate"
    - Upload the private `.pfx` security certificate generated above by `GenerateCertificate.ps1` and enter the password you noted when prompted
    - Pairing the public `.cer` certificate in the App Registration and the private `.pfx` certificate in the Automation Account is 

1. In the client's Azure tenant, navigate to the _Entra ID => Roles and administrators_ tab
    - Locate and click on the "Exchange Administrator" role
    - Click the "Add assignments" button
    - Add the Azure registered application (for example, `OnboardingApp`)

### Usage

`OnboardUser.ps1` is intended to be run in Azure as a runbook by the Azure Automation account created in step 1 of the Enviroment Setup. In this scenario, parameters are typically passed to runbook from Azure Logic Apps or another user input pre-processor.

However, the script can be also be run manually from the command line. For this to work, the Azure authentication line should be modified to authenticate a user directly instead of using a managed identity. The Integrid OnboardingUtilities PowerShell module should also be installed locally. A local usage example is:
```
.\OnboardingScript.ps1 -AppId '6c2215a7-39de-4df2-9a0f-5ce814f87e9f' `
    -TenantId '315e5c10-3b21-4914-9b83-37bdf68e67ec' `
    -CertificateThumbprint 1234ABCD5678EFGH9012IJKL3456MNOP7890QRST `
    -CompanyName ExampleCorp `
    -Domain 'example.com' `
    -SpSiteName OnboardingData `
    -SpListName Location `
    -FirstName John `
    -LastName Doe `
    -Location 'Main Office' `
    -JobTitle 'Software Engineer II' `
    -Equipment 'Laptop, Dock, Monitor' ` 
    -CreatedByEmail 'hiring.manager@example.com' `
    -CreatedByDisplayName 'Hiring Manager' `
    -PasswordSender 'onboarding@example.com' ` 
    -LicenseName 'Business Premium' `
    -ApprovalWebhookUrl 'https://prod-90.eastus.logic.azure.com:443/workflows/5b20125ee5c6404fa8132623130bae43/triggers/manual/paths/invoke?api-version=2016-10-01&sp=%2Ftriggers%2Fmanual%2Frun&sv=1.0&sig=hgNJehZVJHP0ieYtv1b_vthRvi-FXt8VI06vMWQOLao'
```
