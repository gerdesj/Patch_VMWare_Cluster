# Patch VMWare Cluster
Patch a VMware esxi cluster without DRS, using PowerCLI.  If you don't have an Enterprise Plus license or a "powerup" license for DRS, then patching an ESXi cluster is a bit of a pain.  This script saves a list of VMs to hosts in memory and to a .csv file and then evacuates the hosts one by one and attempts to patch them.  Finally it puts the VMs back again as they were.

There are more notes in the header of the script.

## Prerequisites
### Linux
Install Powershell:
```
https://learn.microsoft.com/en-us/powershell/scripting/install/installing-powershell-on-linux?view=powershell-7.3
```

Install PowerCLI:
```
PS> Install-Module -Name VMware.PowerCLI
```
### Windows and MacOS
You do you!

## Notes
You may find these settings useful:
```
PS> Set-PowerCLIConfiguration -Scope User -ParticipateInCEIP $false
PS> Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -Confirm:$false
PS> Set-PowerCLIConfiguration -Scope User -WebOperationTimeoutSeconds 1200
```
Usefull PowerCLI docs for vSphere - https://developer.vmware.com/docs/powercli/latest/products/vmwarevsphereandvsan/
