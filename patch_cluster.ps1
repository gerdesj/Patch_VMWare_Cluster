<#
Copyright © Jon Gerdes, Blueloop Ltd (UK) 05 Sep 2023

This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.
This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
You should have received a copy of the GNU General Public License along with this program. If not, see https://www.gnu.org/licenses/. 
#>

<#
.SYNOPSIS
Patch a VMware cluster using PowerCLI without DRS

.DESCRIPTION
This script will connect to a named cluster and attempt to patch all of its hosts, one by one. It saves a list of which VMs are running on which host (.csv) and then attempts to shuffle them around via vMotion, to evacuate a host, then patch the host and move on to the next.  Finally it runs through the list of VMs and puts them back again where they were. 

.EXAMPLE
PS> ./patch_cluster.ps1 -vcName vcentre.example.com -user myname -clusterName Cluster1 -baselines '*Predefined*' -makeChanges $false

Goes through the motions but does not make changes

.EXAMPLE
PS> ./patch_cluster.ps1 -vcName vcentre.example.com -user myname -clusterName Cluster1 -baselines '*Predefined*' -makeChanges $true

Tries to patch the named cluster

.NOTES
Make sure that suitable baselines are attached. By default the predefined baselines are assumed. You can override this with the baselines parameter.  An initial check is made to attempt to avoid RAM over commit.  There are plenty of pauses to allow you to fix any problems found as the script progresses

Increase Timeout from default 300 seconds if necessary - remediation often takes longer than five minutes
PS> Set-PowerCLIConfiguration -Scope User -WebOperationTimeoutSeconds 1200

Until this script gets rather more sophisticated, you need to ensure that you don't have vms that can't be moved and other factors that will stop esxi hosts from being put into maint mode and patched

There are quite a few "Press any key ..." points to allow the sysadmin to fix any unforseen issues.  These will be removed as the script is improved.

#>

param (
    [Parameter(
        Mandatory,
        HelpMessage='vCentre to connect to'
    )][string]$vcName,
    [Parameter(
        Mandatory,
        HelpMessage='Cluster to try and remediate'
    )] [string]$clusterName,
    [Parameter(
        HelpMessage='Baseline(s) to use, defaults to *Predefined*'
    )][string]$baselines = "*Predefined*",
    [Parameter(
        Mandatory,
        HelpMessage='Username to connect with to the vCentre'
    )][string]$user,
    [Parameter(
        Mandatory,
        HelpMessage='This script defaults to not doing any updating, set to $true if you want it to'
    )][bool]$makeChanges = $false
)

# Enable/disable Debug (SilentlyContinue or Continue)
# "Continue" - will show would would be done - don't make changes
# "SilentlyContinue" - do the job - make changes
if ($makeChanges -eq $true){ $DebugPreference = "SilentlyContinue"}
else { $DebugPreference = "Continue"}

# Get the password from the console
$pass = Read-Host "Enter password for $user" -AsSecureString
$passPlainText = ConvertFrom-SecureString -SecureString $pass -AsPlainText
Write-Debug "$vcName $user, $pass"

# Connect to vcentre, save the session for eventual disconnect 
# try/catch block to avoid script carrying on despite bad creds if already authenticated in this session
try {
    $vc = Connect-VIServer -Server $vcName -User $user -Password $passPlainText -ErrorAction Stop | Out-Null
}
catch [Exception]{
    "Could not connect to vCenter $vcName as $user"
    Exit 1
}

"Started: $(Get-Date)"

# Connect to the specified cluster
## TODO: T/C
$cluster = Get-Cluster -Name $clusterName

# Get the cluster hosts to check for all baseline compliance and get any NotCompliant
"Check cluster $($cluster.Name) compliance ..."
Get-Cluster $cluster | Get-VMHost | Test-Compliance

$Compliance = Get-Cluster $cluster | Get-VMHost | Get-Compliance -Baseline (Get-Baseline -Name $baselines -TargetType "Host") -ComplianceStatus "NotCompliant"

# Exit if there is nothing to do, continue anyway if in debug mode
if (([array]($compliance)).Count -eq 0) {
    "Cluster $($cluster.Name) is already compliant, nothing to do"
    if ($DebugPreference -ne 'Continue') {
        "Finished: $(Get-Date)"
        Exit 0
    }
}

# Calculate cluster minimum RAM avalable ie when the host with the most RAM is shutdown
$numHosts = (Get-Cluster $cluster | Get-VMHost).Count
$clusterTotalRam = (Get-VMHost | Measure-Object MemoryTotalGB -Sum).Sum
$clusterTotalRam = [int][Math]::Floor($clusterTotalRam)
$hostLargestRam = (Get-VMHost | Measure-Object MemoryTotalGB -Maximum).Maximum
$hostLargestRam = [int][Math]::Floor($hostLargestRam)
$clusterMinRam = $clusterTotalRam - $hostLargestRam
$clusterMinRam = [int][Math]::Floor($clusterMinRam)

# Calculate total RAM usage by running VMs in the cluster
$totalRamUsage = ((Get-VM).where{$_.PowerState -eq 'PoweredOn'} | Measure-Object MemoryGB -Sum).Sum
$totalRamUsage = [int][Math]::Floor($totalRamUsage)

Write-Debug "-----------------------------------------------------------------"
Write-Debug "numHosts        = $numHosts"
Write-Debug "clusterTotalRam = $clusterTotalRam GB"
Write-Debug "hostLargestRam  = $hostLargestRam GB"
Write-Debug "clusterMinRam   = $clusterMinRam GB"
Write-Debug "totalRamUsage   = $totalRamUsage GB" 
Write-Debug "-----------------------------------------------------------------"

# Compare RAM usage to cluster minimum RAM and exit with an error message if overcommit likely
if ($totalRamUsage -gt $clusterMinRam) {
    "Cluster RAM usage is greater than the suggested cluster minimum RAM."
    Disconnect-VIServer -Server $vcName -Confirm:$false
    Exit 1
}

# Create array to store current VM to host relationships, to use later
$vmsToHost = @()

# Hosts sorted on name
$esxiHosts = Get-Cluster $cluster | Get-VMHost | Sort-Object -Property "Name"

# For each host get the VMs of interest
foreach ($esxiHost in $esxiHosts) {
    $vmsOnHost = ( (Get-VM).where{$_.PowerState -eq "PoweredOn" -and $_.VMHost.Name -eq $esxiHost -and $_.Folder.Name -cne "vCLS"} )

    foreach ($vmOnHost in $vmsOnHost) {
        $vm = "" | Select-Object name,host
        $vm.name = $vmOnHost.Name
        $vm.host = $vmOnHost.VMHost.Name
        $vmsToHost += $vm
    }
}

# Save the array to disc as a .csv file
$vmsToHost | ForEach-Object{ [pscustomobject]$_ } | Export-CSV -Path '.\vmsToHost-Before.csv'

# Debug write out the vms to hosts
if ($DebugPreference -eq 'Continue') {
    $vmsToHost | Format-Table | Out-String -Stream | Write-Debug
}

# --------------------------------------------------------------------------------------------
# Migrate VMs to other hosts and apply updates
foreach ($esxiHost in $esxiHosts) {
    # If there is nothing to do for this host, break to next host. Carry on in debug mode
    if ($DebugPreference -ne 'Continue') {
        $compliance = Get-Compliance -Entity $esxiHost -ComplianceStatus "NotCompliant"
        if (([array]($compliance)).Count -eq 0) { break }
    }

    "This script will now attempt to evacuate $esxiHost"
    Read-Host “Press ENTER to continue...”

    # Find all VMs running on this host
    $vmsOnHost = ((Get-VM).where{$_.PowerState -eq "PoweredOn" -and $_.VMHost.Name -eq  $esxiHost -and $_.Folder.Name -cne "vCLS"})

    # Migrate VMs one by one to the current least loaded (RAM) host
    foreach ($vm in $vmsOnHost) {
        # Find all other hosts in the cluster, sort by RAM and select least loaded
        $otherHosts = Get-VMHost -Location $cluster | Where-Object { $_.Name -ne $esxiHost.Name }
        $leastLoadedHost = $otherHosts | Sort-Object -Property MemoryUsageGB | Select-Object -First 1

        # Move the VM to that host
        if ($DebugPreference -eq 'Continue') {
            Write-Debug "Move $vm from $esxiHost to $leastLoadedHost"
        } 
        else {
            Move-VM -VM $vm -Destination $leastLoadedHost
        }
    }

    "This script will now attempt to patch $esxiHost"
    Read-Host  “Press ENTER to continue...”

    if ($DebugPreference -eq 'Continue') {
        Write-Debug "---------------------------------------------------------------------"
        Write-Debug "Host $esxiHost - Compliance status"
        $compliance = Get-Compliance -Entity $esxiHost -Detailed |  Out-String
        Write-Debug $compliance
        Write-Debug "---------------------------------------------------------------------"
    } 
    else {
        # Put the host into maintenance mode
        Set-VMHost -VMHost $esxiHost -State "Maintenance"

        # Stage patches
        Copy-Patch -Entity $esxiHost

        # Apply patches, switching off HA access control etc.  They turn back on afterwards
        $BaselineParam = (Get-Baseline -Name $baselines -TargetType "Host")
        $UpdateEntityParams = @{
            Entity                                   = $esxiHost
            Baseline                                 = $BaselineParam
            ClusterDisableHighAvailability           = $true
            ClusterDisableDistributedPowerManagement = $true
            ClusterDisableFaultTolerance             = $true
            Confirm                                  = $false
        }
        Update-Entity @UpdateEntityParams 

        # Exit maintenance mode
        Set-VMHost -VMHost $esxiHost -State "Connected"
    }
}

"This script will now return the VMs to where they were originally"
Read-Host “Press ENTER to continue...”

# The last host patched will have the lowest RAM in use, so sort the list of hosts by RAM usage (ascending - default)
$esxiHosts = Get-VMHost -Location $cluster | Sort-Object -Property MemoryUsageGB

foreach ($esxiHost in $esxiHosts) {
    foreach ($vm in $vmsToHost) {

        # Which host should the vm be running on?
        $vmHostBefore = $vm.host

        # Only move vms to the current esxiHost in question
        if ($vmHostBefore -eq $esxiHost) {

            # Move vm or show what would be done
            if ($DebugPreference -eq 'Continue') {
                Write-Debug "Move $($vm.name) to $esxiHost"
            }
            else {
                Move-VM -VM $vm.name -Destination $esxiHost
            }
        }
    }
}

"Finished moving VMs back to their original hosts"
"Finished: $(Get-Date)"

Disconnect-VIServer -Server $vc -Confirm:$false
