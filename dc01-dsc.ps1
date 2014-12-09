configuration dc01 {
    param (
        [Parameter(Mandatory = $true)]
        [pscredential] $DomainCredential
    )

    Import-DscResource -ModuleName xActiveDirectory,xPendingReboot;

    node $AllNodes.Where({ $PSItem.NodeName -eq 'dc01'; }).NodeName {
        WindowsFeature ADDS {
            Name = 'AD-Domain-Services';
            Ensure = 'Present';     
        }

        WindowsFeature ADDSRSAT {
            Name = 'RSAT-ADDS';
            Ensure = 'Present';
        }

        LocalConfigurationManager {
            RefreshFrequencyMins = 30;
            ConfigurationModeFrequencyMins = 15;
            RebootNodeIfNeeded = 'True';
            ActionAfterReboot = 'ContinueConfiguration';
        }

        xADDomain Domain {
            DependsOn = '[WindowsFeature]ADDS';
            DomainName = 'trevorsullivan.net';
            SafemodeAdministratorPassword = $DomainCredential;
            DomainAdministratorCredential = $DomainCredential;
        }

        xPendingReboot RebootAfterDomain {
            DependsOn = '[xADDomain]Domain';
            Name = 'RebootAfterDomain';
        }
    }
}
