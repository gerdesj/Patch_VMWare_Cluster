# Patch VMWare Cluster
Patch a VMware esxi cluster without DRS, using PowerCLI.

## Prerequisites
### Linux
Install Powershell
  https://learn.microsoft.com/en-us/powershell/scripting/install/installing-powershell-on-linux?view=powershell-7.3

Install PowerCLI
  PS> Install-Module -Name VMware.PowerCLI

You may find these settings useful:
  PS> Set-PowerCLIConfiguration -Scope User -ParticipateInCEIP $false
  PS> Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -Confirm:$false
  PS> Set-PowerCLIConfiguration -Scope User -WebOperationTimeoutSeconds 1200
