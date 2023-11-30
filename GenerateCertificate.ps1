param (
    [Parameter(Mandatory = $true)]
    [ValidateScript({
            if (-Not ($_ | Test-Path) ) {
                throw "Directory does not exist"
            }
            if (-Not ($_ | Test-Path -PathType Container) ) {
                throw "The -Directory argument point to a directory (folder). File paths are not allowed."
            }
            return $true
        })]
    [System.IO.FileInfo]$Directory = (Get-Location).Path,

    [Parameter(Mandatory = $true)]
    [int]$DaysValid = 365,

    [Parameter(Mandatory = $true)]
    [string]$FriendlyName,

    [Parameter(Mandatory = $true)]
    [string]$Subject
)

$endDate = (Get-Date).AddDays($DaysValid)
$pathPrefix = "$Directory\$FriendlyName - Expires$($endDate.ToString("yyyy-MM-dd"))"
$cert = New-SelfSignedCertificate -FriendlyName $FriendlyName -Subject $Subject -CertStoreLocation Cert:\CurrentUser\My\ -NotAfter $endDate
Export-Certificate -Cert $cert -FilePath "$pathPrefix.cer"
Export-PfxCertificate -Cert $cert -FilePath "$pathPrefix.pfx" -Password (Get-Credential).password