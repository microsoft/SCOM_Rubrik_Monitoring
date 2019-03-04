# SCOM RubrikMonitoring Readme

The SCOM RubrikMonitoring project is a SCOM Management Pack, accompanied by a PowerShell script for externally monitoring a Rubrik Environment. The script utilizes SCOM SDK calls to initialize/update objects within the SCOM MP after connecting to Rubrik Clusters via the Rubrik PowerShell module.

This monitoring includes alerts for the ability to connect to Rubrik Clusters, the health of Cluster Nodes, the health of Disks within each Node, the clients that are connected to managed clusters, and the BackupJobs themselves.


## Prerequisites
The script's use of the SCOM SDK requires two DLL's that are included with the installation of the SCOM SDK. They are not included within this repository, but the config file for the script allows you to point the script to where you have placed them.

The script also requires a SCOM environment, with the provided MP imported into it. The config file has a line to provide the Fully Qualified Domain Name of a Management Server of the SCOM environment.

The script requires version 4.0.0.173 of the Rubrik module for PowerShell. If it is not detected installed at runtime, the script will install it before importing it.


## Installation Notes
Import the MP file into your SCOM environment.

Place the PowerShell script, along with the config file here: 
“C:\Program Files\WindowsPowerShell\Scripts\RubrikMonitoring\” 

This will ensure the script can load the configuration of your environment at runtime.

The config file must also be updated with the proper settings for your environment. Modification of the PowerShell script is not needed if this config file is properly populated. 

## Explanation of config file properties:
### SCOM
1. ConnectorNode - The FQDN of a SCOM Management Server in your SCOM environment. This will be used by the script to connect to SCOM via the SCOM SDK.
2. DLLDirectory - The directory where the Microsoft.EnterpriseManagement.Common.dll and Microsoft.EnterpriseManagement.OperationsManager.dll are located.
### Rubrik
1. ManagedClusters - This is an array of hash tables, including the id and address for each Rubrik Cluster being monitored. You can manage more than one cluster, but at least one is required, and each must have a unique ID.
    * id - A unique ID for the Rubrik cluster being managed. This will be the ID of the cluster within SCOM itself
    * server - The IP address or FQDN of the cluster. This will be used for connecting to the cluster by the script.
2. SLADomainsToExclude - This is an array of comma-delimited SLADomains to exclude from BackupJob monitoring. BackupJobs with these SLADomains will be excluded from monitoring.
3. ObjectTypesToExclude - This is an array of comma-delimited ObjectTypes to exclude from BackupJob monitoring. BackupJobs of these ObjectTypes will be excluded from monitoring.
4. Login - This is the credential used to connect to the Rubrik clusters. It can be local or domain. If $SecurityConext is populated with a PSCredential before the script is ran, this can be left out of the config completely. If only Username is populated or $SecurityConext is not populated, an interactive logon window will pop-up to enter whatever is missing.
    * Username - The logon used to logon to Rubrik clusters. If domain credential, 'Domain\Username' will suffice or just 'Username' if local.
    * Password - The password for the above account. If not included in the config file, an interactive pop-up will open to enter the password for the provided Username

# Contributing
This project welcomes contributions and suggestions.  Most contributions require you to agree to a
Contributor License Agreement (CLA) declaring that you have the right to, and actually do, grant us
the rights to use your contribution. For details, visit https://cla.microsoft.com.

When you submit a pull request, a CLA-bot will automatically determine whether you need to provide
a CLA and decorate the PR appropriately (e.g., label, comment). Simply follow the instructions
provided by the bot. You will only need to do this once across all repos using our CLA.

This project has adopted the [Microsoft Open Source Code of Conduct](https://opensource.microsoft.com/codeofconduct/).
For more information see the [Code of Conduct FAQ](https://opensource.microsoft.com/codeofconduct/faq/) or
contact [opencode@microsoft.com](mailto:opencode@microsoft.com) with any additional questions or comments.
