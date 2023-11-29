$Cert = New-SelfSignedCertificate -FriendlyName "Wynnefield Onboarding Certificate" `
    -Subject "Graph certificate for Wynnefield Onboarding App" `
    -CertStoreLocation Cert:\CurrentUser\My\ `
    -NotAfter (Get-Date).AddYears(1)
$PathPrefix = "C:\Users\DavidLambert\OneDrive - Integrid LLC\onboard\Wynnefield-Onboarding-Expires-" `
    + (Get-Date).AddYears(1).ToString("yyyy-MM-dd")
Export-Certificate -Cert $Cert -FilePath "$PathPrefix.cer"
Export-PfxCertificate -Cert $Cert -FilePath "$PathPrefix.pfx" -Password (Get-Credential).password