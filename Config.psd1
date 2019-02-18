@{
	SCOM = @{
		ConnectorNode = <NameOfSCOMManagementServer>

	}
	Rubrik =@{
		ManagedClusters = @(
			@{
				id=<UniqueIDForCluster1>
				server=<IPorFQDNofCluster1>
			},
			@{
				id=<UniqueIDForCluster2>
				server=<IPorFQDNofCluster2>
			}
		)
        SLADomainsToExclude = <ArrayOfStringsOfSLADomainsToExclude>
        ObjectTypesToExclude = <ArrayOfStringsOfObjectTypesToExclude>
		Login = @{
			UserName = <AliasUsedToLoginToRubrik>
			Password = <ThePasswordForTheAboveLogon>
		} 
		<#This can be many things: 
			-left blank if $SecurityContext is set outside of the script
			-UserName only set, to have an interactive Get-Credential window pop-up to manually enter in password
			-Both UserName and Password set to create the PSCredential on execution of script
			-completely removed to have an interactive logon pop-up at runtime of script
		#>
	}
}