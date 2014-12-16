#region Globals
$LogFilePath = '{0}\temp\SCCM01 Custom Script.txt' -f $env:windir;
$Username = 'Trevor';
$Password = ConvertTo-SecureString -String 'P@ssw0rd!!' -AsPlainText -Force;
$InstallCredential = New-Object -TypeName pscredential -ArgumentList $Username, $Password;
Remove-Variable -Name Username,Password;
#endregion

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

$DriveLetter = 's'; #### NOTE: Set the drive letter
$Partition = New-Partition -DiskNumber 6 -UseMaximumSize -DriveLetter $DriveLetter;

Format-Volume -Partition $Partition -FileSystem NTFS -Force -Confirm:$false -NewFileSystemLabel ConfigMgr;
#endregion Storage Pool

#region Download ISOs
$WebClient = New-Object -TypeName System.Net.WebClient;
$FileList = @(
    @{
        Uri = 'https://systemcentercloud.blob.core.windows.net/iso/configmgr.iso';
        OutFile = '{0}:\iso\configmgr.iso' -f $DriveLetter;
    }
    , @{
        Uri = 'https://systemcentercloud.blob.core.windows.net/iso/sql.iso';
        OutFile = '{0}:\iso\sql.iso' -f $DriveLetter;
    }
    );
New-Item -Path s:\iso -ItemType Directory -ErrorAction SilentlyContinue;
foreach ($File in $FileList) {
    $WebClient.DownloadFile($File.Uri, $File.OutFile);
    #Invoke-WebRequest @File;
}
#endregion

#region Windows Features
Install-WindowsFeature -Name UpdateServices,RDC,Web-Server,Web-Metabase,Web-WMI,Web-Asp-Net,Web-Asp-Net45,Web-Windows-Auth,BITS,RSAT-AD-PowerShell;
#endregion

#region Microsoft SQL Server install
#region SQL Server Answer File
$SqlAnswerFile = @{
    Path = '{0}:\iso\sccm01-sqlconfigurationfile.ini' -f $DriveLetter;
    Value =  @'
;SQL Server 2012 Configuration File
[OPTIONS]

IAcceptSQLServerLicenseTerms = "True"

; Specifies a Setup work flow, like INSTALL, UNINSTALL, or UPGRADE. This is a required parameter. 

ACTION="Install"

; Detailed help for command line argument ENU has not been defined yet. 

ENU="True"

; Parameter that controls the user interface behavior. Valid values are Normal for the full UI,AutoAdvance for a simplied UI, and EnableUIOnServerCore for bypassing Server Core setup GUI block. 

;UIMODE="Normal"

; Setup will not display any user interface. 

QUIET="True"

; Setup will display progress only, without any user interaction. 

QUIETSIMPLE="False"

; Specify whether SQL Server Setup should discover and include product updates. The valid values are True and False or 1 and 0. By default SQL Server Setup will include updates that are found. 

UpdateEnabled="True"

; Specifies features to install, uninstall, or upgrade. The list of top-level features include SQL, AS, RS, IS, MDS, and Tools. The SQL feature will install the Database Engine, Replication, Full-Text, and Data Quality Services (DQS) server. The Tools feature will install Management Tools, Books online components, SQL Server Data Tools, and other shared components. 

FEATURES=SQLENGINE,REPLICATION,RS,BIDS,SSMS,ADV_SSMS

; Specify the location where SQL Server Setup will obtain product updates. The valid values are "MU" to search Microsoft Update, a valid folder path, a relative path such as .\MyUpdates or a UNC share. By default SQL Server Setup will search Microsoft Update or a Windows Update service through the Window Server Update Services. 

UpdateSource="MU"

; Displays the command line parameters usage 

HELP="False"

; Specifies that the detailed Setup log should be piped to the console. 

INDICATEPROGRESS="False"

; Specifies that Setup should install into WOW64. This command line argument is not supported on an IA64 or a 32-bit system. 

X86="False"

; Specify the root installation directory for shared components.  This directory remains unchanged after shared components are already installed. 

INSTALLSHAREDDIR="{0}:\Program Files\Microsoft SQL Server"

; Specify the root installation directory for the WOW64 shared components.  This directory remains unchanged after WOW64 shared components are already installed. 

INSTALLSHAREDWOWDIR="{0}:\Program Files (x86)\Microsoft SQL Server"

; Specify a default or named instance. MSSQLSERVER is the default instance for non-Express editions and SQLExpress for Express editions. This parameter is required when installing the SQL Server Database Engine (SQL), Analysis Services (AS), or Reporting Services (RS). 

INSTANCENAME="MSSQLSERVER"

; Specify the Instance ID for the SQL Server features you have specified. SQL Server directory structure, registry structure, and service names will incorporate the instance ID of the SQL Server instance. 

INSTANCEID="MSSQLSERVER"

; Specify that SQL Server feature usage data can be collected and sent to Microsoft. Specify 1 or True to enable and 0 or False to disable this feature. 

SQMREPORTING="True"

; RSInputSettings_RSInstallMode_Description 

RSINSTALLMODE="DefaultNativeMode"

; Specify if errors can be reported to Microsoft to improve future SQL Server releases. Specify 1 or True to enable and 0 or False to disable this feature. 

ERRORREPORTING="True"

; Specify the installation directory. 

INSTANCEDIR="{0}:\Program Files\Microsoft SQL Server"

; Agent account name 

AGTSVCACCOUNT="NT Service\SQLSERVERAGENT"

; Auto-start service after installation.  

AGTSVCSTARTUPTYPE="Manual"

; CM brick TCP communication port 

COMMFABRICPORT="0"

; How matrix will use private networks 

COMMFABRICNETWORKLEVEL="0"

; How inter brick communication will be protected 

COMMFABRICENCRYPTION="0"

; TCP port used by the CM brick 

MATRIXCMBRICKCOMMPORT="0"

; Startup type for the SQL Server service. 

SQLSVCSTARTUPTYPE="Automatic"

; Level to enable FILESTREAM feature at (0, 1, 2 or 3). 

FILESTREAMLEVEL="0"

; Set to "1" to enable RANU for SQL Server Express. 

ENABLERANU="False"

; Specifies a Windows collation or an SQL collation to use for the Database Engine. 

SQLCOLLATION="SQL_Latin1_General_CP1_CI_AS"

; Account for SQL Server service: Domain\User or system account. 

SQLSVCACCOUNT="NT AUTHORITY\System"

; Windows account(s) to provision as SQL Server system administrators. 

SQLSYSADMINACCOUNTS= "BUILTIN\Administrators"

; Provision current user as a Database Engine system administrator for SQL Server 2012 Express. 

ADDCURRENTUSERASSQLADMIN="False"

; Specify 0 to disable or 1 to enable the TCP/IP protocol. 

TCPENABLED="1"

; Specify 0 to disable or 1 to enable the Named Pipes protocol. 

NPENABLED="0"

; Startup type for Browser Service. 

BROWSERSVCSTARTUPTYPE="Disabled"

; Specifies which account the report server NT service should execute under.  When omitted or when the value is empty string, the default built-in account for the current operating system.
; The username part of RSSVCACCOUNT is a maximum of 20 characters long and
; The domain part of RSSVCACCOUNT is a maximum of 254 characters long. 

RSSVCACCOUNT="NT Service\ReportServer"

; Specifies how the startup mode of the report server NT service.  When 
; Manual - Service startup is manual mode (default).
; Automatic - Service startup is automatic mode.
; Disabled - Service is disabled 

RSSVCSTARTUPTYPE="Automatic"
'@ -f $DriveLetter;
    }
Set-Content @SqlAnswerFile;
Add-Content -Path $LogFilePath -Value ('Created SQL Server answer file at: {0}' -f $AnswerFile.Path);
#endregion

$SqlMount = @{
    ImagePath = '{0}:\iso\sql.iso' -f $DriveLetter;
    StorageType = 'ISO';
    };
Mount-DiskImage @SqlMount;
$SqlVolume = (Get-Volume).Where({ $PSItem.FileSystemLabel -match 'SQLServer'; }, 'First');
$SqlInstall = @{
    FilePath = '{0}:\setup.exe' -f $SqlVolume.DriveLetter;
    ArgumentList = '/ConfigurationFile="{0}"' -f 's:\iso\sccm01-sqlconfigurationfile.ini';
    Wait = $true;
    };
Start-Process @SqlInstall;
Remove-Variable -Name SqlVolume,SqlInstall;
#endregion

#region Install Microsoft Windows 8.1 ADK with Update
$AdkDownload = @{
    Uri = 'http://download.microsoft.com/download/6/A/E/6AEA92B0-A412-4622-983E-5B305D2EBE56/adk/adksetup.exe';
    OutFile = '{0}\temp\adksetup.exe' -f $env:windir;
    };
Invoke-WebRequest @AdkDownload

$AdkLayout = @{
    FilePath = $AdkDownload.OutFile;
    ArgumentList = '/layout s:\iso\adksetup81 /quiet';
    Wait = $true;
    };
Start-Process @AdkLayout;

$AdkInstall = @{
    FilePath = 's:\iso\adksetup81\adksetup.exe';
    ArgumentList = '/features + /quiet /norestart';
    Wait = $true;
    };
Start-Process @AdkInstall;
Remove-Variable -Name AdkDownload,AdkInstall;
#endregion

#region Microsoft System Center 2012 R2 Configuration Manager install
#region Configuration Manager Answer File
$AnswerFile = @{
    Path = 's:\iso\sccm01-sccm2012-unattend.ini';
    Value =  @'
[Identification]
Action = "InstallPrimarySite"

[Options]
ProductID = "Eval"
SiteCode = "LAB"
SiteName = "Lab Environment"
SMSInstallDir = "S:\ConfigMgr"
SDKServer = "sccm01.trevorsullivan.net"
PrerequisiteComp = "1"
PrerequisitePath = "s:\sccm2012r2prereq"
AdminConsole = "1"
JoinCEIP = "1"
RoleCommunicationProtocol = "HTTPorHTTPS"
ClientsUsePKICertificate = "0"
MobileDeviceLanguage = "0"

[SQLConfigOptions]
SQLServerName = "sccm01.trevorsullivan.net"
DatabaseName = "SMS_LAB"
'@
    }
Set-Content @AnswerFile;
Add-Content -Path $LogFilePath -Value ('Created Configuration Manager answer file at: {0}' -f $AnswerFile.Path);
#endregion

Mount-DiskImage -ImagePath s:\iso\configmgr.iso -StorageType ISO;
$SccmVolume = (Get-Volume).Where({ $PSItem.FileSystemLabel -match 'SCCMSCEP'; }, 'First');
Add-Content -Path $LogFilePath -Value ('Mounted Configuration Manager ISO to drive letter "{0}"' -f $SccmVolume.DriveLetter);

#region Download prerequisite files
$SccmPrereq = @{
    FilePath = '{0}:\smssetup\bin\x64\setupdl.exe' -f $SccmVolume.DriveLetter;
    ArgumentList = 's:\sccm2012r2prereq';
    Wait = $true;
    };
Start-Process @SccmPrereq;
#endregion

$SccmInstall = @{
    FilePath = '{0}:\smssetup\bin\x64\setup.exe' -f $SccmVolume.DriveLetter;
    ArgumentList = '/script "{0}"' -f $AnswerFile.Path;
    Wait = $true;
    };
Add-Content -Path $LogFilePath -Value ('Executing file {0} with arguments: {1}' -f $SccmInstall.FilePath, $SccmInstall.ArgumentList);
Start-Process @SccmInstall;
Remove-Variable -Name SccmVolume,SccmPrereq,SccmInstall;
#endregion