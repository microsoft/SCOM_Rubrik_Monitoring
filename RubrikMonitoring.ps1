#region Declaring functions and importing Config
$RubrikModules = Get-Module -Name Rubrik -ListAvailable
if ($RubrikModules){
    if (($RubrikModules | Select-Object -ExpandProperty Version | ForEach-Object {$_.ToString()}) -notcontains '4.0.0.173'){
        Install-Module -Name Rubrik -RequiredVersion 4.0.0.173 -Force
    }
}
else{
    Install-Module -Name Rubrik -RequiredVersion 4.0.0.173 -Force
}
Import-Module Rubrik -RequiredVersion 4.0.0.173 -Force
If (!$SCOMMG -or !$MonitoredClusters -or !$SecurityContext -or !$SLADomainsToExclude -or !$ObjectTypesToExclude) {
    $Config = Import-LocalizedData -BaseDirectory 'C:\Program Files\WindowsPowerShell\Scripts\RubrikMonitoring' -FileName 'Config.psd1'
    If (!$SCOMMG)
    {
		$DLLDirectory = $Config.SCOM.DLLDirectory
        Add-Type -Path "$DLLDirectory\Microsoft.EnterpriseManagement.Common.dll"
        Add-Type -Path "$DLLDirectory\Microsoft.EnterpriseManagement.OperationsManager.dll"
        $Global:SCOMMG = [Microsoft.EnterpriseManagement.ManagementGroup]::Connect($Config.SCOM.ConnectorNode)
        if (!$Global:SCOMMG.IsConnected) {
            $Global:SCOMMG.Reconnect()
        }
    }
    If (!$MonitoredClusters)
    {
        $MonitoredClusters = $Config.Rubrik.ManagedClusters
    }
    If (!$SecurityContext)
    {
        If ($Config.Rubrik.UserName -and $Config.Rubrik.Password) 
        {
            $SecurityContext = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $Config.Rubrik.UserName, (ConvertTo-SecureString -String $Config.Rubrik.Password -AsPlainText -Force)
        }
        Else
        {
            $SecurityContext = Get-Credential -UserName $Config.Rubrik.UserName
        }
        
    }
    If (!$SLADomainsToExclude)
    {
            $SLADomainsToExclude = $Config.Rubrik.SLADomainsToExclude
    }
    if (!$ObjectTypesToExclude)
    {
        $ObjectTypesToExclude = $Config.Rubrik.ObjectTypesToExclude
    }
}

function Write-Log 
{
    [CmdletBinding()]
    Param
    (
        # The message to log
        [Alias('m')]
        [Parameter(Mandatory = $true, Position = 0)]
        [string]
        [AllowEmptyString()]
        $Message,
        # Will make the log not append the newline character, allowing for multiple logs on 1 line
        [Alias('nnl')]
        [switch]
        $NoNewLine,
        # Can be used when running in the ISE to make specific things standout
        [Alias('c')]
        [string]
        $Color,
        # Hides the automatically prepended timestamp
        [switch]
        $HideTime
    )
    Process 
    {
        if (!$HideTime) 
        {
            $Now = Get-Date -Format '[HH:mm:ss.fff]'
            $Message = $Now + $Message
        }
        if ($Host.Name -match 'ISE' -or $Host.Name -match 'Visual Studio') 
        {
            if ($NoNewLine) 
            { 
                if ($Color) { Write-Host -NoNewline -ForegroundColor $Color -Object $Message }
                else { Write-Host -NoNewline -Object $Message }
            }
            else 
            { 
                if ($Color) { Write-Host -ForegroundColor $Color -Object $Message }
                else { Write-Host -Object $Message }
            }
        }
        if ($NoNewLine) { $Global:OutputLog += $Message }
        else { $Global:OutputLog += $Message+"`r`n" }
    }
}

Function Get-SCOMSDKClassInstance
{
    Param (
    [Parameter(Mandatory=$true,Position=0)]
    [ValidateNotNullOrEmpty()]
    $Class,
    [Microsoft.EnterpriseManagement.EnterpriseManagementGroup]$ManagementGroup = $Global:SCOMMG,
    [Parameter(Mandatory=$false,Position=2,HelpMessage="Specify Name, Id, Path, FullName, DisplayName, IsManaged, LastModified, HealthState, StateLastModified, IsAvailable, AvailabilityLastModified, InMaintenanceMode, and MaintenanceModeLastModified.  Operators are =, ==, !=, <>, LIKE, MATCHES, IS NULL, NOT, AND, OR, %.")]
    $SearchCriteria=$null
    )

    If(($Class.GetType()).FullName -ne "Microsoft.EnterpriseManagement.Configuration.ManagementPackClass")
    {
        $Class = Get-SCOMSDKClass -ClassName $Class -ManagementGroup $ManagementGroup
    }

    Try
    {
        If($SearchCriteria)
        { 
            $GenericCriteria = [Microsoft.EnterpriseManagement.Monitoring.MonitoringObjectGenericCriteria]$SearchCriteria
            Return $ManagementGroup.GetMonitoringObjects($GenericCriteria,$Class)
        }
        Else
        {
            Return $ManagementGroup.GetMonitoringObjects($Class)
        }
        
    }
    Catch
    {
        return $null
    }

}

Function Search-SCOMSDKInstances
{
    Param(
    [Parameter(Mandatory=$true,Position=0,HelpMessage="Instance array you want to search")]
    [ValidateNotNullOrEmpty()]
    [System.Array]$Instances,
    [Parameter(Mandatory=$true,Position=1,HelpMessage="Property name you want to search by")]
    [ValidateNotNullOrEmpty()]
    $PropertyName,
    [Parameter(Mandatory=$true,Position=2,HelpMessage="The value the property name should equal")]
    [ValidateNotNullOrEmpty()]
    $PropertyValue
    )
    
    $ReturnValue = @()
    ForEach($Instance in $Instances)
    {
        If((($Instance.Values | Where-Object {$_.Type.Name -eq $PropertyName}) | Select-Object -ExpandProperty Value) -eq $PropertyValue)
        {
            $ReturnValue += $Instance
        }
    }
    Return $ReturnValue
}

Function Set-SCOMSDKDiscovery
{
    Param(
    [Parameter(Mandatory=$true,Position=0,HelpMessage="Specify the class you want to discover against")]
    [ValidateNotNullOrEmpty()]
    $Class,
    [Parameter(Mandatory=$true,Position=1,HelpMessage="Specify the properties for the class in a hash table along with their values")]
    [ValidateNotNullOrEmpty()]
    $Properties,
    [Microsoft.EnterpriseManagement.EnterpriseManagementGroup]$ManagementGroup = $Global:SCOMMG
    )

    If($Class.GetType() -ne [Microsoft.EnterpriseManagement.Configuration.ManagementPackClass])
    {
        $Class = Get-SCOMSDKClass $Class -ManagementGroup $ManagementGroup
    }
    If(-NOT $Class)
    {
        Throw "Could not find the class specified"
    }

    $KeyProperty = $Class.GetKeyProperties() | Select-Object -ExpandProperty Name
    $ClassInstances = Get-SCOMSDKClassInstance -Class $Class -ManagementGroup $ManagementGroup
    $Discovery = New-Object Microsoft.EnterpriseManagement.ConnectorFramework.IncrementalDiscoveryData
    $FoundProperty = $false

    
    

    If($ClassInstances)
    {
        $ClassInstance = Search-SCOMSDKInstances -Instances $ClassInstances -PropertyName $KeyProperty -PropertyValue $Properties.$KeyProperty
        If($ClassInstance)
        {
            #TODO - If the instance already exists, check to see if any properties need to be updated.
            Return
        }
        Else
        {
            $NewObject = New-Object Microsoft.EnterpriseManagement.Common.CreatableEnterpriseManagementObject($ManagementGroup,$Class)
            ForEach($Property in $Properties.GetEnumerator())
            {
                $NewObject[$Class.PropertyCollection[$Property.Name]].Value= $Property.Value
            }
            $Discovery.Add($NewObject)
            $Discovery.Commit($ManagementGroup)
         }
    }
    Else
    {
        #There are no existing instances, so create a new instance for this class
        $NewObject = New-Object Microsoft.EnterpriseManagement.Common.CreatableEnterpriseManagementObject($ManagementGroup,$Class)
        ForEach($Property in $Properties.GetEnumerator())
        {
            $NewObject[$Class.PropertyCollection[$Property.Name]].Value= $Property.Value
        }
        $Discovery.Add($NewObject)
        $Discovery.Commit($ManagementGroup)
    }
}

Function Remove-SCOMSDKHostInstance
{
Param(
    [Parameter(Mandatory=$true,Position=0,HelpMessage="Please specify the class")]
    [ValidateNotNullOrEmpty()]
    $Class,
    [Microsoft.EnterpriseManagement.EnterpriseManagementGroup]$ManagementGroup = $Global:SCOMMG,
    [Parameter(Mandatory=$true,Position=2,HelpMessage="Please specify the property name of the class instance you want to search for")]
    [ValidateNotNullOrEmpty()]
    $PropertySearch,
    [Parameter(Mandatory=$true,Position=3,HelpMessage="Please specify the property value of the class instance you want to search for")]
    [ValidateNotNullOrEmpty()]
    $PropertyValue
    )

    $InstanceToRemove = $null
    $HostClass = Get-SCOMSDKClass -ClassName $Class -ManagementGroup $ManagementGroup
    If(-NOT $HostClass)
    {
        Write-Log "Could not find the host class $Class, please be sure it exists and that the management pack for it is imported" -Color Red
        Return
    }
    $HostClassInstances = $ManagementGroup.GetMonitoringObjects($HostClass)
    If(-NOT $HostClassInstances)
    {
        Write-Log "Could not find any instances of the host class $Class.  This class is empty and nothing has been discovered." -Color Red
        Return
    }
    ForEach($HostInstance in $HostClassInstances)
    {
        If(($HostInstance | Select-Object -ExpandProperty 'Values' | Where-Object {$_.Type.Name -eq $PropertySearch} | Select-Object -ExpandProperty "Value") -eq $PropertyValue)
        {
            $InstanceToRemove = $HostClassInstances | Where-Object {$_.Name -eq $PropertyValue}
            Break
        }
    }

    If($InstanceToRemove)
    {
        $Discovery = New-Object Microsoft.EnterpriseManagement.ConnectorFramework.IncrementalDiscoveryData
        $Discovery.Remove($InstanceToRemove)
        $Discovery.Commit($ManagementGroup)
        Write-Log "Instance $($InstanceToRemove.Name) has been removed" -Color Green
    }
    Else
    {
        Write-Log "Could not find device with the property $PropertySearch and the value of $PropertyValue" -Color Red
    }
}

Function Get-SCOMSDKClass
{
    Param (
    [Parameter(Mandatory=$true,Position=0)]
    [ValidateNotNullOrEmpty()]
    [string]$ClassName,
    [Microsoft.EnterpriseManagement.EnterpriseManagementGroup]$ManagementGroup = $Global:SCOMMG
    )
    $ClassID =  $ManagementGroup.EntityTypes.GetClasses($(New-Object Microsoft.EnterpriseManagement.Configuration.ManagementPackClassCriteria("Name = '$ClassName'")))
    $ClassObject =  $ManagementGroup.EntityTypes.GetClass($ClassID.ID)
    return $ClassObject
}

Function Write-SCOMSDKCustomEvent
{
    Param (
    [Parameter(Mandatory=$true,Position=0)]
    [ValidateNotNullOrEmpty()]
    [Microsoft.EnterpriseManagement.Monitoring.PartialMonitoringObject]$TargetClass,
    [Parameter(Mandatory=$true,Position=1)]
    [ValidateNotNullOrEmpty()]
    $Source,
    [Parameter(Mandatory=$true,Position=2)]
    [ValidateNotNullOrEmpty()]
    [int]$EventID,
    [Parameter(Mandatory=$false,Position=3)]
    [ValidateNotNullOrEmpty()]
    [ValidateSet("Information", "Warning", "Error", "Success Audit","Failure Audit")]
    $Level=$null,
    [Parameter(Mandatory=$false,Position=4)]
    [ValidateNotNullOrEmpty()]
    $EventData=$null,
    [Parameter(Mandatory=$false,Position=5)]
    [ValidateNotNullOrEmpty()]
    $Message=$null,
    [Parameter(Mandatory=$false,Position=6)]
    [ValidateNotNullOrEmpty()]
    $Parameters=$null
    )
    
    If($Level -ne $null)
    {
        If($Level -eq 'Information')
        {
            $EventLevel = 4
        }
        ElseIf($Level -eq 'Warning')
        {
            $EventLevel = 2
        }
        ElseIf($Level -eq 'Error')
        {
            $EventLevel = 1
        }
        ElseIf($Level -eq 'Success Audit')
        {
            $EventLevel =8
        }
        ElseIf($Level -eq 'Failure Audit')
        {
            $EventLevel =8
        }
    }
    
    $Event = New-Object Microsoft.EnterpriseManagement.Monitoring.CustomMonitoringEvent($Source,$EventID)
    $Event.LevelId = $EventLevel
    $Event.Message = [Microsoft.EnterpriseManagement.Monitoring.CustomMonitoringEventMessage]$Message
    $Event.Parameters.Add($Parameters)
    
    $TargetClass.InsertCustomMonitoringEvent($Event)
}
#endregion


#region Pull Data from SCOM/Rubrik
$SCOMClusters = Get-SCOMSDKClassInstance -Class 'Rubrik.CDM.Cluster'
$SCOMClusterNodes = Get-SCOMSDKClassInstance -Class 'Rubrik.CDM.ClusterNode'
$SCOMDisks = Get-SCOMSDKClassInstance -Class 'Rubrik.CDM.Disk'
$SCOMClients = Get-SCOMSDKClassInstance -Class 'Rubrik.CDM.RubrikClient'
$SCOMBackupJobs = Get-SCOMSDKClassInstance -Class 'Rubrik.CDM.BackupJob'
$WindowsComputers = Get-SCOMSDKClassInstance -Class 'Microsoft.Windows.Computer'

$RubrikClusters = @()
$RubrikClusterNodes = @()
$RubrikDisks = @()
$RubrikClients = @()
$RubrikBackupJobs = @()

if ($MonitoredClusters)
{
    $ClusterFailedToConnect = @()
    Foreach ($MonitoredCluster in $MonitoredClusters)
    {
        $null = Connect-Rubrik -Server $MonitoredCluster.server -Credential $SecurityContext
        $ThisCluster = Invoke-RubrikRESTCall -Endpoint 'cluster/me' -Method GET
        $RubrikClusters += $ThisCluster
        $ThisClustersNodes = (Invoke-RubrikRESTCall -Endpoint 'cluster/me/node' -api internal -Method GET ).data 
        $ThisClustersNodes | ForEach-Object {
            $_ | Add-Member -Name ClusterID -Value $ThisCluster.id -MemberType NoteProperty
            $_ | Add-Member -Name NodeID -Value "$($_.brikId):$($_.id)" -MemberType NoteProperty
            $RubrikClusterNodes += $_
        }
        $ThisClustersDisks = (Invoke-RubrikRESTCall -Endpoint 'cluster/me/disk' -api internal -Method GET ).data
        $ThisClustersDisks | ForEach-Object {
            $_ | Add-Member -Name ClusterID -Value $ThisCluster.id -MemberType NoteProperty
            $_ | Add-Member -Name DiskID -Value "$($_.nodeid):$($_.id)" -MemberType NoteProperty
            $RubrikDisks += $_
        }
        $ThisClustersClients = (Invoke-RubrikRESTCall -Endpoint 'host' -Method GET ).data
        $ThisClustersClients | ForEach-Object {
            $_ | Add-Member -Name ClusterName -Value $ThisCluster.Name -MemberType NoteProperty
            $RubrikClients += $_
        }
    
        $json = '{"dataSource":"FrequentDataSource","reportTableRequest":{"sortBy":"ObjectName","sortOrder":"asc","requestFilters":{},"limit":9999}}'
        $object = ConvertFrom-Json –InputObject $json
        $ProcessJobs = Invoke-RubrikRESTCall -Endpoint 'report/data_source/table' -api internal -Method POST -Body $object

        foreach ($data in $ProcessJobs.dataGrid) {
            $row = @{}
            for ($i=0;$i -lt $data.Count;$i++) {
                $null = $row.Add($ProcessJobs.columns[$i],$data[$i])
            }
            $row.Add('ClusterID',$ThisCluster.id);
            $row.Add('ClusterName',$ThisCluster.Name);
            $RubrikBackupJobs += $row
        }
    }
    $RubrikBackJobsToExclude = $RubrikBackupJobs | Where-Object {$_.Object_Type -in $ObjectTypesToExclude -or $_.Sla_Domain -in $SLADomainsToExclude}
    $RubrikBackupJobs = $RubrikBackupJobs | Where-Object {$_ -notin $RubrikBackJobsToExclude}
}
#endregion

#region Discovery
if ( $ClusterFailedToConnect )
{
    $SCOMClusterNodes = $SCOMClusterNodes | Where-Object {$_.Values | Where-Object {$_.Type.Name -eq 'ClusterID'} | Select-Object -ExpandProperty Value | Where-Object {$_ -notin $ClusterFailedToConnect}}
    $SCOMDisks = $SCOMDisks | Where-Object {$_.Values | Where-Object {$_.Type.Name -eq 'ClusterID'} | Select-Object -ExpandProperty Value | Where-Object {$_ -notin $ClusterFailedToConnect}}
    $SCOMClients = $SCOMClients | Where-Object {$_.Values | Where-Object {$_.Type.Name -eq 'ClusterID'} | Select-Object -ExpandProperty Value | Where-Object {$_ -notin $ClusterFailedToConnect}}
    $SCOMArchives = $SCOMArchives | Where-Object {$_.Values | Where-Object {$_.Type.Name -eq 'ClusterID'} | Select-Object -ExpandProperty Value | Where-Object {$_ -notin $ClusterFailedToConnect}}
    $SCOMBackupJobs = $SCOMBackupJobs | Where-Object {$_.Values | Where-Object {$_.Type.Name -eq 'ClusterID'} | Select-Object -ExpandProperty Value | Where-Object {$_ -notin $ClusterFailedToConnect}}
}
Write-Log "Processing Cluster Discovery"
$SCOMClustersToRemove = $SCOMClusters.Name | Where-Object {$_ -notin $MonitoredClusters.id}
Write-Log "Found $($SCOMClustersToRemove.Count) Clusters in SCOM that are no longer managed by Rubrik"
if ($SCOMClustersToRemove)
{
    foreach ($SCOMCluster in $SCOMClustersToRemove)
    {
        Remove-SCOMSDKHostInstance -Class 'Rubrik.CDM.Cluster'-PropertySearch ID -PropertyValue $SCOMCluster
    }
}
$RubrikClustersToAdd = $MonitoredClusters | Where-Object {$_.id -notin $SCOMClusters.Name} | Select-Object -Unique
Write-Log "Found $($RubrikClustersToAdd.Count) Clusters in Rubrik that are not yet managed in SCOM"
if ($RubrikClustersToAdd)
{
    foreach ($RubrikCluster in $RubrikClustersToAdd)
    {
        Set-SCOMSDKDiscovery -Class 'Rubrik.CDM.Cluster' -Properties @{"ID"=$RubrikCluster.id;"InstanceID"=$RubrikCluster.server}
    }
}

Write-Log "Processing ClusterNode Discovery"
$SCOMClusterNodesToRemove = $SCOMClusterNodes.Name | Where-Object {$_ -notin $RubrikClusterNodes.NodeID}
Write-Log "Found $($SCOMClusterNodesToRemove.Count) ClusterNodes in SCOM that are no longer managed by Rubrik"
if ($SCOMClusterNodesToRemove)
{
    foreach ($SCOMClusterNode in $SCOMClusterNodesToRemove)
    {
        Remove-SCOMSDKHostInstance -Class 'Rubrik.CDM.ClusterNode' -PropertySearch ID -PropertyValue $SCOMClusterNode
    }
}
$RubrikClusterNodesToAdd = $RubrikClusterNodes | Where-Object {$_.NodeID -notin $SCOMClusterNodes.Name}
Write-Log "Found $($RubrikClusterNodesToAdd.Count) ClusterNodes in Rubrik that are not yet managed in SCOM"
if ($RubrikClusterNodesToAdd)
{
    foreach($RubrikClusterNode in $RubrikClusterNodesToAdd)
    {
        Set-SCOMSDKDiscovery -Class 'Rubrik.CDM.ClusterNode' -Properties @{"ID"=$RubrikClusterNode.NodeID;"ClusterID"=$RubrikClusterNode.ClusterID}
    }
}

Write-Log "Disk Discovery Processing"
$SCOMDisksToRemove = $SCOMDisks.Name | Where-Object {$_ -notin $RubrikDisks.DiskID}
Write-Log "Found $($SCOMDisksToRemove.Count) Disks in SCOM that are no longer managed by Rubrik"
if ($SCOMDisksToRemove)
{
    foreach ($SCOMDisk in $SCOMDisksToRemove)
    {
        Remove-SCOMSDKHostInstance -Class 'Rubrik.CDM.Disk' -PropertySearch ID -PropertyValue $SCOMDisk
    }
}
$RubrikDisksToAdd = $RubrikDisks | Where-Object {$_.DiskID -notin $SCOMDisks.Name}
Write-Log "Found $($RubrikDisksToAdd.Count) Disks in Rubrik that are not yet managed in SCOM"
if ($RubrikDisksToAdd)
{
    foreach($RubrikDisk in $RubrikDisksToAdd)
    {
        Set-SCOMSDKDiscovery -Class 'Rubrik.CDM.Disk' -Properties @{"ID"=$RubrikDisk.DiskID;"ClusterID"=$RubrikDisk.ClusterID}
    }
}

Write-Log "Client Discovery Processing"
$SCOMClientsToRemove = $SCOMClients.Name | Where-Object {$_ -notin $RubrikClients.id}
Write-Log -HideTime "Found $($SCOMClientsToRemove.count) Clients in SCOM that are no longer managed by Rubrik"
$RubrikClientsToAdd = $RubrikClients | Where-Object {$_.id -notin ($SCOMClients.name)}
Write-Log -HideTime "Found $($RubrikClientsToAdd.count) Clients in Rubrik that are not yet managed in SCOM"
if ($SCOMClientsToRemove)
{
    foreach ($SCOMClient in $SCOMClientsToRemove)
    {
        Remove-SCOMSDKHostInstance -Class 'Rubrik.CDM.RubrikClient' -PropertySearch ID -PropertyValue $SCOMClient
    }
}
if ($RubrikClientsToAdd)
{
    foreach($RubrikClient in $RubrikClientsToAdd)
    {
        Set-SCOMSDKDiscovery -Class 'Rubrik.CDM.RubrikClient' -Properties @{"ID"=$RubrikClient.id;"FQDN"=$RubrikClient.hostname;"ClusterID"=$RubrikClient.primaryClusterId}
    }
}

$SCOMClients = $SCOMClients | Where-Object {$_.Name -notin $SCOMClientsToRemove -or $_.Name -notin $RubrikClientsToAdd}


Write-Log "Backup Job Discovery Processing"
$SCOMBackupJobsToRemove = $SCOMBackupJobs.Name | Where-Object {$_ -notin $RubrikBackupJobs.object_linking_id}
Write-Log -HideTime "Found $($SCOMBackupJobsToRemove.Count) Backup Jobs in SCOM that are no longer managed by Rubrik"
if ($SCOMBackupJobsToRemove)
{
    foreach ($SCOMBackupJob in $SCOMBackupJobsToRemove)
    {
        Remove-SCOMSDKHostInstance -Class 'Rubrik.CDM.BackupJob' -PropertySearch ID -PropertyValue $SCOMBackupJob
    }
}

$RubrikBackupJobsToAdd = $RubrikBackupJobs | Where-Object {$_.object_linking_id -notin $SCOMBackupJobs.Name}
Write-Log -HideTime "Found $($RubrikBackupJobsToAdd.Count) Backup Jobs in Rubrik that are not yet managed in SCOM"
if ($RubrikBackupJobsToAdd)
{
    foreach($RubrikBackupJob in $RubrikBackupJobsToAdd)
    {
        Set-SCOMSDKDiscovery -Class 'Rubrik.CDM.BackupJob' -Properties @{"ID"=$RubrikBackupJob.object_linking_id;"ClusterID"=$RubrikBackupJob.ClusterID;"Type"=$RubrikBackupJob.Object_Type}
    }
}

$SCOMBackupJobs = $SCOMBackupJobs | Where-Object {$_.Name -notin $SCOMBackupJobsToRemove -or $_.Name -notin $SCOMBackupJobsToAdd}
#endregion

#region Monitoring
Write-Log "Processing Cluster States"
foreach ($Cluster in $SCOMClusters)
{
    $ClusterID = $Cluster.Name
    if ($ClusterID -in $ClusterFailedToConnect)
    {
        Write-Log -HideTime "System unable to connect to Cluster '$ClusterID'. Triggering an alert."
        Write-SCOMSDKCustomEvent -TargetClass $Cluster -Source "RubrikCDM" -EventID 101 -Level Error -Message "The System was unable to reach this cluster."
    }
    else
    {
        Write-SCOMSDKCustomEvent -TargetClass $Cluster -Source "RubrikCDM" -EventID 100 -Level Information
    }
}

Write-Log "Processing Cluster Node States"
foreach ($ClusterNode in ($RubrikClusterNodes | Where-Object {$_.NodeId -notin $RubrikClusterNodesToAdd.NodeId}))
{
    $SCOMNode = $SCOMClusterNodes | Where-Object {$_.DisplayName -eq $ClusterNode.NodeID}
    if ($ClusterNode.status -ne 'OK')
    {
        Write-Log -HideTime "System unable to connect to Cluster Node '$($ClusterNode.NodeID)'. Triggering an alert."
        Write-SCOMSDKCustomEvent -TargetClass $SCOMNode -Source "RubrikCDM" -EventID 101 -Level Error -Message 'The Cluster Node is not "OK".'
    }
    else
    {
        Write-SCOMSDKCustomEvent -TargetClass $SCOMNode -Source "RubrikCDM" -EventID 100 -Level Information
    }
}

Write-Log "Processing Disk States"
foreach ($Disk in ($RubrikDisks | Where-Object {$_.DiskId -notin $RubrikDisksToAdd.DiskId}))
{
    $SCOMDisk = $SCOMDisks | Where-Object {$_.DisplayName -eq $Disk.DiskID}
    if ($Disk.status -ne 'ACTIVE')
    {
        Write-Log -HideTime "'$($Disk.DiskID)' isn't ACTIVE. Triggering an alert."
        Write-SCOMSDKCustomEvent -TargetClass $SCOMDisk -Source "RubrikCDM" -EventID 101 -Level Error -Message 'The Disk is not "ACTIVE".'
    }
    else
    {
        Write-SCOMSDKCustomEvent -TargetClass $SCOMDisk -Source "RubrikCDM" -EventID 100 -Level Information
    }
}

Write-Log "Processing Agent States"
$ClientsStillHealthy = 0
$ClientsStillUnhealthy = 0
$ClientsInMaintenance = 0
foreach ($Client in $SCOMClients )
{
    $RubrikClient = $RubrikClients | Where-Object {$_.id -eq $Client.Name}
    $WindowsComputer = $WindowsComputers | Where-Object { $_.name -eq $RubrikClient.name}
    If ($RubrikClient)
    {
        if (!($WindowsComputer.InMaintenanceMode))
        {
            if ($Client.HealthState -eq 'Success')
            {
                if ($RubrikClient.status -eq 'Disconnected')
                {
                    Write-Log -HideTime "     '$($Client.Name)' is Disconnected."
                    $AlertMessage = @"
The Rubrik Client on '$($RubrikClient.hostname)' isn't checking in. Please ensure the client is installed/running.
Additional Details:
Client ID: $($RubrikClient.Id)
Rubrik Cluster: $($RubrikClient.ClusterName)            
"@
                    If ($WindowsComputer)
                    {
                        $AlertMessage += @"
WindowsComputer: $($WindowsComputer.Name)
"@              
                    }
                    Write-SCOMSDKCustomEvent -TargetClass $Client -Source "RubrikCDM" -EventID 101 -Level Error -Message $AlertMessage
                }
                else
                {
                    $ClientsStillHealthy++
                }
            }
            else
            {
                if ($RubrikClient.status -eq 'Connected')
                {
                    Write-Log -HideTime "     '$($Client.Name)' is now Connected."
                    Write-SCOMSDKCustomEvent -TargetClass $Client -Source "RubrikCDM" -EventID 100 -Level Information
                }
                else
                {
                    $ClientsStillUnhealthy++
                }
            }
        }
        else 
        {
            Write-Log -HideTime "     Unable to associate a Rubrik Client for '$($Client.Name)' Skipping it this passs."
        }
    }
    else
    {
        $ClientsInMaintenance++
        if ($Client.HealthState -ne 'Success')
        {
            Write-Log -HideTime "     '$($Client.Name)' is in maintenance. Clearing desynced alert"
            Write-SCOMSDKCustomEvent -TargetClass $SCOMClient -Source "RubrikCDM" -EventID 100 -Level Information
        }
    }
}
Write-Log "$ClientsInMaintenance Clients in Maintenance Mode."
Write-Log "$ClientsStillHealthy Clients Healthy with no state change."
Write-Log "$ClientsStillUnhealthy Clients Unhealthy with no state change."

Write-Log "Processing Backup Jobs"
$BackJobsStillHealthy = 0
$BackJobsStillUnhealthy = 0
foreach ($BackupJob in $SCOMBackupJobs )
{
    $RubrikBackupJob = $RubrikBackupJobs | Where-Object {$_.object_linking_id -eq $BackupJob.Name}
    $WindowsComputer = $WindowsComputers | Where-Object { $_.name -match $RubrikBackupJob.Location.trim('\\').split('\')[0] }
    if ($RubrikBackupJob)
    {
        if ($BackupJob.HealthState -eq 'Success')
        {
            if ($RubrikBackupJob.snapshot_24_hour_status -eq 'NonCompliance')
            {
                $AlertMessage = @"
The SLA of the '$($RubrikBackupJob.Object_Name)' Backup Job is currently "Out of Compliance".
It is a '$($RubrikBackupJob.Object_Type)' Job running against the '$($RubrikBackupJob.Location)' client.
It has the following SLA set: "$($RubrikBackupJob.Sla_Domain)", which is currently "$($RubrikBackupJob.Sla_Domain_State)".
Additional Details:
BackupJob ID: $($RubrikBackupJob.ObjectId)
Managed by the '$($RubrikBackupJob.ClusterName)' ($($RubrikBackupJob.ClusterID)) cluster.
"@
                If ($WindowsComputer)
                {
                    $AlertMessage += @"
WindowsComputer: $($WindowsComputer.Name)
"@              
                }
                Write-Log -HideTime "     '$($BackupJob.Name)' is out of Compliance for its SLA."
                Write-SCOMSDKCustomEvent -TargetClass $BackupJob -Source "RubrikCDM" -EventID 101 -Level Error -Message $AlertMessage
            }
            else
            { 
                $BackJobsStillHealthy++
            }
        }
        else
        {
            if ($RubrikBackupJob.snapshot_24_hour_status -eq 'InCompliance')
            {
                Write-Log -HideTime "     '$($BackupJob.Name)' is now in compliance for its SLA."
                Write-SCOMSDKCustomEvent -TargetClass $BackupJob -Source "RubrikCDM" -EventID 100 -Level Information
                $BackJobAlertsResolved++
            }
            else
            {
                 $BackJobsStillUnhealthy++
            }
        }
    }
    else
    {
        Write-Log -HideTime "       No Rubrik Backup Job found for '$($BackupJob.Name)'."
    }
    
    
}
Write-Log "$BackJobsStillHealthy Backup Jobs Healthy with no state change."
Write-Log "$BackJobsStillUnhealthy Backup Job Alerts with no state change."
#endregion