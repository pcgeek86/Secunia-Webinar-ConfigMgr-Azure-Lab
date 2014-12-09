@{
    AllNodes = @(
        @{
            NodeName = '*';
            PSDscAllowPlainTextPassword = $true;
        }
        @{
            NodeName = 'dc01';
        }
    );
    NonNodeData = @{
    }
}
