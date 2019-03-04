@{
	SCOM = @{
		ConnectorNode = 'SCOMMS-001.Contoso.com'

	}
	Rubrik =@{
		ManagedClusters = @(
			@{
				id='RubrikCluster-001'
				server='RubrikCluster-001.Contoso.com'
			},
			@{
				id='RubrikCluster-002'
				server='RubrikCluster-002.Contoso.com'
			}
		)
        SLADomainsToExclude = @('Decommission Pending','Testing Scenarios')
        ObjectTypesToExclude = @('WindowsVolumeGroup','ShareFileset')
		Login = @{
			UserName = 'Contoso\RubrikAdmin'
			Password = 'B4ck!tUp12#4'
		}
	}
}