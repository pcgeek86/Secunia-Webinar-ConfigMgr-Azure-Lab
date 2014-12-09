<#

    PREREQUISITES
    =================================

    In order for this script to work, you must first manually create the
    following resources in your Microsoft Azure subscription.

    Virtual Network
        Name: SystemCenter
        Address Space: 10.5.1.0/24
        Subnets:
            Name / Address Space: Hosts / 10.5.1.0/25
        DNS Server: 10.5.1.5

#>
Clear-Host;
$ErrorActionPreference = 'Continue';
$VerbosePreference = 'Continue';
(Get-AzureAccount).ForEach({ Remove-AzureAccount -Name $PSItem.Id -Force; });

$Username = 'trevor@trevorsullivan.net';   #### NOTE: Update with your own user principal name (UPN).
$AzureCredential = Get-Credential -Message 'Please enter your Microsoft Azure password.' -UserName $Username;
Add-AzureAccount -Credential $AzureCredential;

$SubscriptionName = 'Visual Studio Ultimate with MSDN'; #### NOTE: Update with your subscription name. Use Get-AzureSusbcription after calling Add-AzureAccount.
Select-AzureSubscription -SubscriptionName $SubscriptionName -ErrorAction Stop;

#region Azure Virtual Network
$VNetName = 'SystemCenter';
$VNetConfig = [xml](Get-AzureVNetConfig).XMLConfiguration;
$NewVNet = @'

'@;

# Define the subnet that virtual machines will be added to.
$SubnetName = 'Hosts';

Remove-Variable -Name NewVNet, VNetConfig;

#endregion

#region Azure Storage Account
# NOTE: Only a single cloud service will be used to host the virtual machines for this lab.
$StorageAccount = @{
    StorageAccountName = 'systemcentercloud';  #### NOTE: Provide your own, globally unique storage account name.
    Location = 'North Central US';             #### NOTE: Specify the Azure region to create your cloud service in.
    };
$StorageContainer = @{
    Name = 'systemcenter';
    };
$MyStorageAccount = Get-AzureStorageAccount -StorageAccountName $StorageAccount.StorageAccountName -ErrorAction Ignore;
if (!$MyStorageAccount -and !(Test-AzureName -Storage $StorageAccount.StorageAccountName -ErrorAction Stop)) {
    New-AzureStorageAccount @StorageAccount;
}

# Set the "current" storage account
Set-AzureSubscription -SubscriptionName $SubscriptionName -CurrentStorageAccountName $StorageAccount.StorageAccountName;
$StorageKey = Get-AzureStorageKey -StorageAccountName $StorageAccount.StorageAccountName;
$StorageContext = New-AzureStorageContext -StorageAccountName $StorageKey.StorageAccountName -StorageAccountKey $StorageKey.Primary;

#region Storage Share (Azure Files)
$StorageShare = @{
    Name = 'systemcenter';
    Context = $StorageContext;
    };
if (!(Get-AzureStorageShare -Name $StorageShare.Name)) {
    New-AzureStorageShare @StorageShare;
}
#endregion

#region Storage Container for ISOs
$StorageContainerISO = @{
    Name = 'iso';
    Permission = 'Container';
    Context = $StorageContext;
    };
if (!(Get-AzureStorageContainer -Context $StorageContext -Name $StorageContainerISO.Name -ErrorAction SilentlyContinue)) {
    New-AzureStorageContainer @StorageContainerISO;
}
#endregion

Remove-Variable -Name MyStorageAccount, StorageKey;
#endregion

#region Upload SQL Server and ConfigMgr ISOs
$FileList = @(
    @{
        File = '{0}\configmgr.iso' -f $PSScriptRoot;
        BlobType = 'Block';
        Container = $StorageContainerISO.Name;
        Context = $StorageContext;
    };
    @{
        File = '{0}\sql.iso' -f $PSScriptRoot;
        BlobType = 'Block';
        Container = $StorageContainerISO.Name;
        Context = $StorageContext;
    };
    )
foreach ($File in $FileList) {
    if (!(Get-AzureStorageBlob -Context $File.Context -Container $File.Container -Blob (Split-Path -Path $File.File -Leaf) -ErrorAction SilentlyContinue)) {
        Set-AzureStorageBlobContent @File;
    }
}

# Clean up unneeded variables
Remove-Variable -Name FileList;
#endregion

#region Azure Cloud Service
$CloudService = @{
    ServiceName = 'systemcentercloud';       #### NOTE: Provide your own, globally unique cloud service name.
    Location = $StorageAccount.Location;    
    Description = 'This cloud service is used to build a new System Center lab.';
    };
$MyCloudService = Get-AzureService -ServiceName $CloudService.ServiceName -ErrorAction Ignore;
if (!$MyCloudService -and !(Test-AzureName -Service $CloudService.ServiceName -ErrorAction Stop)) {
    New-AzureService @CloudService;
}
Remove-Variable -Name MyCloudService;
#endregion

#region Azure Virtual Machines
$ImageList = Get-AzureVMImage;
$ImageList.Where({ $PSItem.ImageName -match '2012-R2'; }).ImageName;
$ImageName = 'a699494373c04fc0bc8f2bb1389d6106__Windows-Server-2012-R2-201410.01-en.us-127GB.vhd'; #### NOTE: Update this to the appropriate Windows Server image from the gallery.

# Create an empty HashTable to hold the virtual machine configurations
$VMList = @();

# Contains the Windows provisioning configuration for virtual machines
$ProvisioningConfig = @{
    Windows = $true;
    AdminUsername = 'Trevor';  #### NOTE: Update this to your own username.
    Password = 'P@ssw0rd!!';   #### NOTE: Update this to your own password.
    };


#region dc01
$VMConfig = @{
    Name = 'dc01';
    InstanceSize = 'Small';
    ImageName = $ImageName;
    MediaLocation = 'https://{0}.blob.core.windows.net/{1}/dc01.vhd' -f $StorageAccount.StorageAccountName, $StorageContainer.Name;
    };

# Create the new Azure VM configuration
$NewVMConfig = New-AzureVMConfig @VMConfig;

# Configure the provisioning information
$NewVMConfig | Add-AzureProvisioningConfig @ProvisioningConfig;
# Configure a static IP address within the IP address space
$NewVMConfig | Set-AzureStaticVNetIP -IPAddress 10.5.1.5;
# Configure the Azure subnet inside the Virtual Network, to add this VM to
$NewVMConfig | Set-AzureSubnet -SubnetNames $SubnetName;
# Add a data disk to the VM configuration
$DataDisk = @{
    CreateNew = $true;
    DiskSizeInGB = 20;
    LUN = 0;
    DiskLabel = 'Data disk for dc01';
    HostCaching = 'ReadWrite';
    MediaLocation = 'https://{0}.blob.core.windows.net/{1}/dc01-data.vhd' -f $StorageAccount.StorageAccountName, $StorageContainer.Name;
    }
$NewVMConfig | Add-AzureDataDisk @DataDisk;

#region dc01 DSC Configuration
# Add the DSC configuration for the Azure VM
$DscConfig = @{
    ConfigurationPath = '{0}\dc01-dsc.ps1' -f $PSScriptRoot;
    StorageContext = $StorageContext;
    ContainerName = $StorageContainer.Name;
    Force = $true;
    };
Publish-AzureVMDscConfiguration @DscConfig;

$DscExtension = @{
    ReferenceName = 'dc01-DscConfig';
    ContainerName = $StorageContainer.Name;
    StorageContext = $StorageContext;
    ConfigurationArchive = '{0}.zip' -f (Split-Path -Path $DscConfig.ConfigurationPath -Leaf);
    ConfigurationName = 'dc01';
    ConfigurationArgument = @{
        DomainCredential = New-Object -TypeName PSCredential -ArgumentList 'Trevor', (ConvertTo-SecureString -AsPlainText -Force -String P@ssw0rd!!);
        }
    ConfigurationDataPath = '{0}\dc01-dscconfigdata.psd1' -f $PSScriptRoot;
    };
$NewVMConfig | Set-AzureVMDscExtension @DscExtension;
#endregion

#region dc01 Custom Script Extension
# Upload the custom script to blob storage
$CustomScript = @{
    File = '{0}\dc01-CustomScript.ps1' -f $PSScriptRoot;
    Context = $StorageContext;
    Container = $StorageContainer.Name;
    Force = $true;
    };
Set-AzureStorageBlobContent @CustomScript;

# Configure the custom script extension for the Azure VM
$StorageKey = Get-AzureStorageKey -StorageAccountName $StorageContext.StorageAccountName;
$CustomScriptExtension = @{
    FileName = (Split-Path -Path $CustomScript.File -Leaf);
    ReferenceName = 'dc01-CustomScript';
    StorageAccountName = $StorageContext.StorageAccountName;
    ContainerName = $StorageContainer.Name;
    StorageAccountKey = $StorageKey.Primary;
    Argument = '{0} {1} {2}' -f $StorageContext.StorageAccountName, $StorageKey.Primary, $StorageShare;
    };
$NewVMConfig | Set-AzureVMCustomScriptExtension @CustomScriptExtension;
#endregion

# Add the VM config for dc01 to the VM configuration list
$VMList += $NewVMConfig;
Remove-Variable -Name VMConfig,NewVMConfig,DscConfig,DscExtension,CustomScript;
#endregion

#region sccm01
$VMConfig = @{
    Name = 'sccm01';
    InstanceSize = 'Large';
    ImageName = $ImageName;
    MediaLocation = 'https://{0}.blob.core.windows.net/{1}/sccm01-os.vhd' -f $StorageAccount.StorageAccountName, $StorageContainer.Name;
    };

$NewVMConfig = New-AzureVMConfig @VMConfig;
$NewVMConfig | Add-AzureProvisioningConfig @ProvisioningConfig;
$NewVMConfig | Set-AzureStaticVNetIP -IPAddress 10.5.1.10;
$NewVMConfig | Set-AzureSubnet -SubnetNames $SubnetName;

#region sccm01 Azure Data Disks
$SccmDataDiskList = @(
    @{
        CreateNew = $true;
        DiskSizeInGB = 100;
        HostCaching = 'ReadWrite';
        DiskLabel = 'sccm01-data0';
        LUN = 0;
        MediaLocation = 'https://{0}.blob.core.windows.net/{1}/sccm01-data0.vhd' -f $StorageAccount.StorageAccountName, $StorageContainer.Name;
    }
    , @{
        CreateNew = $true;
        DiskSizeInGB = 100;
        HostCaching = 'ReadWrite';
        DiskLabel = 'sccm01-data1';
        LUN = 1;
        MediaLocation = 'https://{0}.blob.core.windows.net/{1}/sccm01-data1.vhd' -f $StorageAccount.StorageAccountName, $StorageContainer.Name;
    }
    , @{
        CreateNew = $true;
        DiskSizeInGB = 100;
        HostCaching = 'ReadWrite';
        DiskLabel = 'sccm01-data2';
        LUN = 2;
        MediaLocation = 'https://{0}.blob.core.windows.net/{1}/sccm01-data2.vhd' -f $StorageAccount.StorageAccountName, $StorageContainer.Name;
    }
    , @{
        CreateNew = $true;
        DiskSizeInGB = 100;
        HostCaching = 'ReadWrite';
        DiskLabel = 'sccm01-data3';
        LUN = 3;
        MediaLocation = 'https://{0}.blob.core.windows.net/{1}/sccm01-data3.vhd' -f $StorageAccount.StorageAccountName, $StorageContainer.Name;
    }
    );
# Add all of the data disks to the SCCM server VM config
foreach ($DataDisk in $SccmDataDiskList) {
    $NewVMConfig | Add-AzureDataDisk @DataDisk;
}
#endregion

#region sccm01 Custom Script Extension
$CustomScriptBlob = @{
    File = '{0}\sccm01-CustomScript.ps1' -f $PSScriptRoot;
    Container = $StorageContainer.Name;
    Context = $StorageContext;
    Force = $true;
    };
Set-AzureStorageBlobContent @CustomScriptBlob;

$StorageKey = Get-AzureStorageKey -StorageAccountName $StorageContext.StorageAccountName;
$CustomScriptExtension = @{
    ReferenceName = 'sccm01-CustomScript';
    StorageAccountName = $StorageContext.StorageAccountName;
    ContainerName = $StorageContainer.Name;
    FileName = (Split-Path -Path $CustomScriptBlob.File -Leaf);

    };
$NewVMConfig | Set-AzureVMCustomScriptExtension @CustomScriptExtension;
#endregion

$VMList += $NewVMConfig; #### NOTE: Uncomment this line to create the SCCM server
Remove-Variable -Name VMConfig,NewVMConfig,SccmDataDiskList,CustomScriptExtension,CustomScriptBlob;
#endregion

#region Create Virtual Machines
$NewVMList = @{
    ServiceName = $CloudService.ServiceName;
    VMs = $VMList;
    VNetName = $VNetName; #### NOTE: Set this to the appropriate virtual network name.
    };
New-AzureVM @NewVMList;
Write-Verbose -Message ('{0} Finished creating Azure virtual machines.' -f (Get-Date));
Remove-Variable -Name NewVMList;
return;
#endregion

#endregion

#region Remote Management

# Wait for virtual machines to become available
while ((Get-AzureVM -ServiceName $CloudService.ServiceName).Status -contains 'Provisioning') {
    Write-Verbose -Message 'Waiting for virtual machines to become available.';
    Start-Sleep -Seconds 15;
}

# Remote Desktop Files for VMs
Get-AzureRemoteDesktopFile -ServiceName $CloudService.ServiceName -Name dc01 -Launch;
Get-AzureRemoteDesktopFile -ServiceName $CloudService.ServiceName -Name sccm01 -Launch;
Restart-AzureVM -ServiceName $CloudService.ServiceName -Name dc01 -Launch;

# PowerShell Remoting example to Domain Controller
$WinRMUri = Get-AzureWinRMUri -ServiceName $CloudService.ServiceName -Name dc01;
$SessionOption = New-PSSessionOption -SkipCACheck -SkipCNCheck -SkipRevocationCheck;
$Credential = New-Object -TypeName PSCredential -ArgumentList $ProvisioningConfig.AdminUsername, (ConvertTo-SecureString -AsPlainText -Force -String $ProvisioningConfig.Password);
Enter-PSSession -URI $WinRMUri -Credential $Credential -SessionOption $SessionOption;
#endregion

#region Cleanup
Remove-AzureService -ServiceName $CloudService.ServiceName -Force -DeleteAll;
Remove-AzureStorageAccount -StorageAccountName $StorageAccount.StorageAccountName;
(Get-AzureDisk).Where({ $PSItem.AttachedTo.HostedServiceName -eq $CloudService.ServiceName; }) | Remove-AzureDisk -DeleteVHD;
#endregion