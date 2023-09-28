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
### Windows
Install Powershell:
```
https://learn.microsoft.com/en-us/powershell/scripting/install/installing-powershell-on-windows?view=powershell-7.3
```
Install PowerCLI:
```
PS> Install-Module -Name VMware.PowerCLI
```

## Usage
Simply run the script from within Powershell with PowerCLI install.  There are a few parameters which are documented within the script and will be prompted for if not provided on the command line. 

## Notes
You may find these settings useful:
```
PS> Set-PowerCLIConfiguration -Scope User -ParticipateInCEIP $false
PS> Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -Confirm:$false
PS> Set-PowerCLIConfiguration -Scope User -WebOperationTimeoutSeconds 1200
```
The first two avoid a prompt about the customer data collection thingie and a SSL certificate failure if the system that runs the script doesn't have the vCentre's CA cert as trusted.  The third one attempts to avoid a non fatal timeout when actually patching the hosts.  The default is for 300 seconds ie five minutes which is often not enough time to patch a host and reboot it.  The timeout doesn't seem to stop the PowerCLI cmdlet but you do get an error reported.  You may have to restart pwsh to actually enforce the timeout, according to the docs. 

Usefull PowerCLI docs for vSphere - https://developer.vmware.com/docs/powercli/latest/products/vmwarevsphereandvsan/
