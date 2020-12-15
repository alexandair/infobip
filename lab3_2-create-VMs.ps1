# LAB 03: Provisioning an Azure VM and basic management tasks

<#
You've created a Linux jumpbox VM in the Azure portal.
Region "Create a Linux jumpbox VM" shows how to accomplish the same with 2 lines of Azure CLI.
The only step that's skipped is a generation of the SSH keys.
We don't need them, because we will authenticate to VM using the Azure AD credentials.
If you've successfully created a Linux VM in the Azure portal, skip that region and go
directly to "Configure Role-Based Access" region
#>

# NOTE: Azure CLI commands should be executed in Azure Cloud Shell unless you've installed Azure CLI locally

#region Define variables

$resourceGroupName = 'infobip-vms-NN-rg' # replace NN with the same numbers
$vnetResourceGroupName = 'infobip-net-NN-rg'
$vnetName = 'demovnet'
$location = 'westeurope'

#endregion

#region Create a Linux jumpbox VM

# When a VNet and a VM are in the same resource group, you can use --vnet-name $vnetName --subnet jumpbox
az vm create --image UbuntuLTS --location $location --name linuxjumpbox --resource-group $resourceGroupName --size Standard_B1ms --vnet-name $vnetName --subnet jumpbox --nsg '""' --output table

# When a VNet and a VM AREN'T in the same resource group, you need to specify a subnet ID
$vnet = Get-AzVirtualNetwork -Name demovnet -ResourceGroupName $vnetResourceGroupName

$jumpboxSubnetId = $vnet.Subnets.id | Where-Object { $_ -match 'jumpbox' } 

# Get a subnet ID with Azure CLI
az network vnet subnet show --name jumpbox --vnet-name $vnetName --resource-group $vnetResourceGroupName --query id -o tsv

az vm create --image UbuntuLTS --location $location --name linuxjumpbox --resource-group $resourceGroupName --size Standard_B1ms --subnet $jumpboxSubnetId --nsg '""' --output table

<#
Install the Active Directory Linux SSH extension. This extension is responsible for the configuration of the Azure AD integration.
Using Azure AD credentials for accessing Azure Linux Virtual Machines improves security by:

Centrally controlling and enforcing access policies on Azure AD credentials
Reducing the reliance on local access accounts
Integration with multi-factor authentication
#>

az vm extension set --publisher Microsoft.Azure.ActiveDirectory.LinuxSSH --name AADLoginForLinux --resource-group $resourceGroupName --vm-name linuxjumpbox

#endregion

#region Configure Role-Based Access

# Run the following commands in the PowerShell shell in Azure Cloud Shell

$VMID = az vm show --resource-group $resourceGroupName --name linuxjumpbox --query id -o tsv

$AzureADUser = 'username@somedomain.onmicrosoft.com'

az role assignment create --role "Virtual Machine Administrator Login" --assignee $AzureADUser --scope $VMID

# Take a note of the public IP address of the Linux jumpbox VM
$publicIP = az vm show -d --resource-group $resourceGroupName  --name linuxjumpbox --query publicIps -o tsv


ssh username@somedomain.onmicrosoft.com@$publicIP
# or
ssh "$AzureADUser@$publicIP"

#endregion

#region Create a Windows management VM

# Run the following commands in the PowerShell shell in Azure Cloud Shell

$cred = Get-Credential azureuser

$vnet = Get-AzVirtualNetwork -Name demovnet -ResourceGroupName $vnetResourceGroupName

$managementSubnetId = $vnet.Subnets.id.where{$_ -match 'management'} 

az vm create --image Win2019Datacenter --admin-username $cred.UserName --admin-password $cred.GetNetworkCredential().Password --location $location --name windowsmgmt --resource-group $resourceGroupName --size Standard_B1ms --subnet $managementSubnetId --public-ip-address '""' --nsg '""' --output table

# Take a note of the private IP address of the Windows management VM
$privateIP = az vm show -d --resource-group $resourceGroupName  --name windowsmgmt --query privateIps -o tsv
$privateIP

#endregion

#region Establish a RDP connection to Windows management VM thanks to a port forwarding

# Run the following commands in the PowerShell shell LOCALLY

<#
In OpenSSH, local port forwarding is configured using the -L option:

    ssh -L 80:managedvm.example.com:80 jumpboxvm.example.com

This example opens a connection to the jumpboxvm.example.com jump server, 
and forwards any connection to port 80 on the local machine to port 80 on managedvm.example.com.

-N Do not execute a remote command. This is useful for just forwarding ports.
#>
# ssh -L 3388:<privateIPofTargetVM>:3389 <yourAadUser>@<publicIPofJumpbox> -N
# for example:
ssh -L 3388:192.168.2.4:3389 username@somedomain.onmicrosoft.com@$PublicIP -N

<# You will get a message similar to this one

This preview capability is not for production use.
When you sign in, verify the name of the app on the sign-in screen is "Azure Linux VM Sign-in"
 and the IP address of the target VM is correct.

To sign in, use a web browser to open the page https://microsoft.com/devicelogin
 and enter the code C2VX84LNF to authenticate. Press ENTER when ready.
#>

# Open another PowerShell shell
# Run the following command to RDP to a Windows management VM
mstsc.exe /v:localhost:3388

# for people who couldn't enable Azure AD Cred extension
# this is how port forwarding will work with a .pem file
# (in Azure Cloud Shell port forwarding doesn't work)
ssh -i ~\.ssh\linuxjumpbox_key.pem -L 3388:192.168.2.4:3389 azureuser@$PublicIP -N

#endregion

#region Create a Virtual Machine Scale Set

# Our goal is to deploy 2 instances of Windows VMs in a scale set
# and install and configure IIS on them using the Custom Script Extension

# Run the following commands in the PowerShell shell in Azure Cloud Shell

#region Define variables

$resourceGroupName = 'infobip-vms-NN-rg' # replace NN with the same numbers
$vnetResourceGroupName = 'infobip-net-NN-rg'
$vnetName = 'demovnet'
$location = 'westeurope'
$cred = Get-Credential azureuser

#endregion

# Let's get the frontend subnet ID
$vnet = Get-AzVirtualNetwork -Name demovnet -ResourceGroupName $vnetResourceGroupName

$frontendSubnetId = $vnet.Subnets.id | Where-Object { $_ -match 'frontend' } 

<# Unfortunately, the -SubnetName parameter doesn't accept a subnet ID, so we will use Azure CLI again
New-AzVmss `
  -ResourceGroupName $resourceGroupName `
  -VMScaleSetName "demoScaleSet" `
  -Location $location `
  -VirtualNetworkName $vnetName `
  -SubnetName frontend `
  -PublicIpAddressName "demoPublicIPAddress" `
  -LoadBalancerName "demoLoadBalancer" `
  -UpgradePolicyMode "Automatic" `
  -InstanceCount 2 `
  -Credential $cred
#>

az vmss create `
--resource-group $resourceGroupName `
--name 'demoScaleSet' `
--location $location `
--subnet $frontendSubnetId `
--public-ip-address 'demoPublicIPAddress' `
--load-balancer 'demoLoadBalancer' `
--storage-sku 'StandardSSD_LRS' `
--upgrade-policy-mode 'Automatic' `
--instance-count 2 `
--admin-username $cred.UserName `
--admin-password $cred.GetNetworkCredential().Password `
--image Win2019Datacenter

# Azure CLI, by default, doesn't create a load balancing rule to allow access to port 80
# Open the 'demoLoadBalancer' blade in the Azure portal and create the Health probe and Load balancing rule for port 80 

# Configuration parameters for the Custom Script Extension 
  $customConfig = @{
    "fileUris" = (,"https://raw.githubusercontent.com/Azure-Samples/compute-automation-configurations/master/automate-iis.ps1");
    "commandToExecute" = "powershell -ExecutionPolicy Unrestricted -File automate-iis.ps1"
  }

# Get information about the scale set
$vmss = Get-AzVmss -ResourceGroupName $resourceGroupName -VMScaleSetName "demoScaleSet"

# Add the Custom Script Extension to install IIS and configure basic website
$vmss = Add-AzVmssExtension `
-VirtualMachineScaleSet $vmss `
-Name "customScript" `
-Publisher "Microsoft.Compute" `
-Type "CustomScriptExtension" `
-TypeHandlerVersion 1.9 `
-Setting $customConfig

# Update the scale set and apply the Custom Script Extension to the VM instances
Update-AzVmss `
-ResourceGroupName $resourceGroupName `
-Name "demoScaleSet" `
-VirtualMachineScaleSet $vmss

# Test the IIS installation
start ("http://{0}" -f (Get-AzPublicIpAddress -Name demoPublicIpAddress -ResourceGroupName $resourceGroupName).IpAddress)

#endregion