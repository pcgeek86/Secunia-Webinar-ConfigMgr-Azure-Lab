[CmdletBinding()]
param (
    [Parameter(Position = 0)]
    [string] $StorageAccountName
  , [Parameter(Position = 1)]
    [string] $StorageAccountKey
  , [Parameter(Position = 2)]
    [string] $StorageShareName
)

#region Mount Azure Files Share

# Import credential for Azure Files Share
$FilePath = 'cmdkey';
$ArgumentList = '/add:{0}.file.core.windows.net /user:{0} /pass:{1}' -f $StorageAccountName, $StorageAccountKey;
Start-Process -ArgumentList $ArgumentList -FilePath $FilePath -Wait;

# Mount the Azure Files share
$FilePath = 'net.exe';
$ArgumentList = 'use v: \\{0}.file.core.windows.net\{1}' -f $StorageAccountName, $StorageShareName;
Start-Process -FilePath $FilePath -ArgumentList $ArgumentList -Wait;

Get-ChildItem -Path v:;
#endregion

#region Install DSC Resource Kit
Clear-Host;

$DscResourceKitUrl = 'https://gallery.technet.microsoft.com/scriptcenter/DSC-Resource-Kit-All-c449312d/file/129525/1/DSC%20Resource%20Kit%20Wave%208%2011102014.zip';
$OutFile = '{0}\Temp\DscResourceKit.zip' -f $env:windir;
Invoke-WebRequest -Uri $DscResourceKitUrl -OutFile $OutFile;

$ModuleDirectory = '{0}\WindowsPowerShell\Modules' -f $env:ProgramFiles;
$TempFolder = '{0}\Temp\DscResourceKit\' -f $env:windir;
Add-Type -AssemblyName System.IO.Compression.FileSystem;
[System.IO.Compression.ZipFile]::ExtractToDirectory($OutFile, $TempFolder);

Move-Item -Path "$TempFolder\All Resources\*" -Destination $ModuleDirectory -ErrorAction Ignore;

Remove-Item -Path $TempFolder -ErrorAction Ignore -Force -Recurse;
#endregion 

#region Windows Management Framework Core 5.0
# Download Windows Management Framework Core 5.0
$WMF5Download = @{
    Uri = 'http://download.microsoft.com/download/B/7/0/B7075FF1-E1B7-4CEB-9A55-CA24DEA79478/WindowsBlue-KB3006193-x64.msu';
    OutFile = '{0}\temp\WindowsBlue-KB3006193-x64.msu' -f $env:windir;
    };
Invoke-WebRequest $WMF5Download;

# Install Windows Management Framework Core 5.0
$WMF5Install = @{
    FilePath = 'wusa.exe';
    ArgumentList = '"{0}" /quiet /norestart' -f $WMF5Download.OutFile;
    Wait = $true;
    NoNewWindow = $true;
    };
Start-Process @WMF5Install;

Restart-Computer;
#endregion