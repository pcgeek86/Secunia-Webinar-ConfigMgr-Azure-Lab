#region Storage Pool
$DiskList = Get-PhysicalDisk -CanPool $true;
Initialize-Disk -InputObject $DiskList;

$StorageSubsystem = Get-StorageSubSystem;

$StoragePool = @{
    FriendlyName = 'ConfigMgr Storage Pool';
    StorageSubSystemUniqueId = $StorageSubsystem.UniqueId;
    PhysicalDisks = $DiskList;
    };
New-StoragePool @StoragePool;

$VirtualDisk = @{
    StoragePoolFriendlyName = 'ConfigMgr Storage Pool';
    UseMaximumSize = $true;
    FriendlyName = 'ConfigMgr Volume';
    ProvisioningType = 'Fixed';
    ResiliencySettingName = 'Simple';
    };
$VirtualDisk = New-VirtualDisk @VirtualDisk;

Initialize-Disk -PartitionStyle GPT -VirtualDisk $VirtualDisk;

$Partition = New-Partition -DiskNumber 6 -UseMaximumSize -DriveLetter s;

Format-Volume -Partition $Partition -FileSystem NTFS -Force -Confirm:$false -NewFileSystemLabel ConfigMgr;
#endregion Storage Pool

#region Download ISOs
$WebClient = New-Object -TypeName System.Net.WebClient;
$FileList = @(
    @{
        Uri = 'https://systemcentercloud.blob.core.windows.net/isos/configmgr.iso';
        OutFile = 'c:\isos\configmgr.iso';
    }
    );
New-Item -Path c:\isos -ItemType Directory -ErrorAction SilentlyContinue;
foreach ($File in $FileList) {
    Invoke-WebRequest @File;
}
#endregion

#region Windows Features
Install-WindowsFeature -Name UpdateServices;
#endregion

#region Install Microsoft Windows 8.1 ADK with Update
$AdkDownload = @{
    Uri = 'http://download.microsoft.com/download/6/A/E/6AEA92B0-A412-4622-983E-5B305D2EBE56/adk/adksetup.exe';
    OutFile = '{0}\temp\adksetup.exe' -f $env:windir;
    };
Invoke-WebRequest @AdkDownload

$AdkInstall = @{
    FilePath = $AdkDownload.OutFile;
    ArgumentList = '/quiet /norestart';
    Wait = $true;
    };
Start-Process @AdkInstall;
Remove-Variable -Name AdkDownload,AdkInstall;
#endregion

#region Microsoft SQL Server install
Mount-DiskImage -ImagePath s:\iso\sql.iso -StorageType ISO;
$SqlVolume = (Get-Volume).Where({ $PSItem.FileSystemLabel -match 'SQLServer'; });
$SqlInstall = @{
    FilePath = '{0}:\setup.exe' -f $SqlVolume.DriveLetter;
    ArgumentList = '/ConfigurationFile="{0}"' -f 's:\iso\sccm01-sqlconfigurationfile.ini';
    Wait = $true;
    };
Start-Process @SqlInstall;
Remove-Variable -Name SqlVolume,SqlInstall;
#endregion

#region Microsoft System Center 2012 R2 Configuration Manager install
Mount-DiskImage -ImagePath s:\iso\configmgr.iso -StorageType ISO;
$SccmVolume = (Get-Volume).Where({ $PSItem.FileSystemLabel -match 'SCCMSCEP'; });
$SccmInstall = @{
    FilePath = '{0}:\smssetup\bin\x64\setup.exe' -f $SccmVolume.DriveLetter;
    ArgumentList = '/script "{0}"' -f 's:\iso\sccm01-sccm2012-unattend.ini';
    Wait = $true;
    };
Start-Process @SccmInstall;
Remove-Variable -Name SccmVolume,SccmInstall;
#endregion