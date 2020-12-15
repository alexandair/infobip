# A virtual machine network traffic (Network Watcher's IP Flow Verify)

#region Define variables

$resourceGroupName = 'infobip-vms-NN-rg' # replace NN with the same numbers
$location = 'westeurope'

#endregion

# If you don't already have a network watcher enabled in the West Europe region,
# use New-AzNetworkWatcher to create a network watcher in the West Europe region
# All network watchers are usually deployed in the NetworkWatcherRG resource group

# THIS IS A REGIONAL SERVICE. YOU ARE WORKING IN THE SAME SUBSCRIPTION, SO ONLY ONE OF YOU SHOULD CREATE THE NETWORK WATCHER
$networkWatcher = New-AzNetworkWatcher -Name "NetworkWatcher_$location" -ResourceGroupName 'NetworkWatcherRG' -Location $location

# If you already have a network watcher enabled in the West Europe region,
# use Get-AzNetworkWatcher to retrieve the network watcher

$networkWatcher = Get-AzNetworkWatcher -Name 'networkwatcher_westeurope' -ResourceGroupName 'NetworkWatcherRG'

# To test whether traffic is allowed or denied to different destinations and from a source IP address,
# use the Test-AzNetworkWatcherIPFlow command

$JumpboxVM = Get-AzVM -ResourceGroupName $resourceGroupName -Name linuxjumpbox

# Test access to port 22 on the linuxjumpbox VM from your computer
Test-AzNetworkWatcherIPFlow `
  -NetworkWatcher $networkWatcher `
  -TargetVirtualMachineId $JumpboxVM.Id `
  -Direction Inbound `
  -Protocol TCP `
  -LocalIPAddress 192.168.1.4 `
  -LocalPort 22 `
  -RemoteIPAddress <yourPublicIP> `
  -RemotePort 60000

$ManagementVM = Get-AzVM -ResourceGroupName $resourceGroupName -Name windowsmgmt

# Test access to port 3389 on windowsmgmt VM from linuxjumpbox VM
Test-AzNetworkWatcherIPFlow `
  -NetworkWatcher $networkWatcher `
  -TargetVirtualMachineId $ManagementVM.Id `
  -Direction Inbound `
  -Protocol TCP `
  -LocalIPAddress 192.168.2.4 `
  -LocalPort 3389 `
  -RemoteIPAddress 192.168.1.4 `
  -RemotePort 6000

  # Test access from the windowmsgmt VM to the VM Scale Set instance 
  Test-AzNetworkWatcherIPFlow `
  -NetworkWatcher $networkWatcher `
  -TargetVirtualMachineId $ManagementVM.Id `
  -Direction Outbound `
  -Protocol TCP `
  -LocalIPAddress 192.168.2.4 `
  -LocalPort 6000 `
  -RemoteIPAddress 192.168.3.6 `
  -RemotePort 3389

  Test-AzNetworkWatcherIPFlow `
  -NetworkWatcher $networkWatcher `
  -TargetVirtualMachineId $ManagementVM.Id `
  -Direction Outbound `
  -Protocol TCP `
  -LocalIPAddress 192.168.2.4 `
  -LocalPort 6000 `
  -RemoteIPAddress 192.168.3.6 `
  -RemotePort 80



# To determine why the rules are allowing or preventing communication,
# review the effective security rules for the network interface with Get-AzEffectiveNetworkSecurityGroup

# First, find the names of your VM NICs
Get-AzResource -ResourceGroupName $resourceGroupName -ResourceType 'Microsoft.Network/networkInterfaces' |
Select-Object Name

# review the effective security rules for both network interfaces 
Get-AzEffectiveNetworkSecurityGroup -NetworkInterfaceName <NICname> -ResourceGroupName $resourceGroupName

# The following output is more user-friendly
Get-AzEffectiveNetworkSecurityGroup -ResourceGroupName $resourceGroupName -NetworkInterfaceName <NICname> |
Select-Object -ExpandProperty EffectiveSecurityRules | Format-Table