# This Scripts is intended to use auto-configuration of vSphere

# Initialization of Environment
Clear-Host
$ScriptName = $MyInvocation.MyCommand.Name
Write-Host "ScriptName:$ScriptName`nVersion:$Version`n"

# Set configuration file name(User defined)
$DEFAULT_CSV_CONFIG_FILE="vsphere_configurations.csv"


# ///// Functions
# PowerCLI Snap-in Load
function LoadPowerCLI {
    Param([String]$pssnapin)
    Write-Host "Load PowerCLI .."

    # Check existence
    Get-PSSnapin -Registered $pssnapin -ErrorAction Stop | Out-Null

    # Check loading PowerCLI
    Add-PSSnapin $pssnapin 2>&1 | Out-Null
    Write-Host "Load PowerCLI Done.`n"
}

# Prompt waiting Enter Key
function Wait ()
{
    Write-Host "Press Enter..." 
    [Console]::ReadKey() | Out-Null
}

# Functions awaiting user-input
function  DoCommand-WithConfirm([string]$command, [string]$addMessage = "", [bool]$isDefaultYes=$false)
{
    # Selection to choose
    $CollectionType = [System.Management.Automation.Host.ChoiceDescription]
    $ChoiceType = "System.Collections.ObjectModel.Collection"
    # Generate collections
    $descriptions = New-Object "$ChoiceType``1[$CollectionType]"
    $questions = (("&Yes","Execute"), ("&No","Not execute"))
    $questions | %{$descriptions.Add((New-Object $CollectionType $_))} 

    # Confirmation messages
    $message = "Are you sure to run command [" + $command + "] ??"
    if( -not [string]::IsNullOrEmpty($addMessage))
    {
        $message += [System.Environment]::NewLine + $addMessage
    }

    # Set default value
    $defaultType = 1;
    if($isDefaultYes -eq $true)
    {
        $defaultType = 0;
    }

    # If user enter 'yes', execute command.
    $answer = $host.ui.PromptForChoice("[Confirmation]",$message ,$descriptions,$defaultType)
    if($answer -eq 0)
    {
        Invoke-Expression "$command"
    }
}

# ///// Filters
# Exception Filter
filter Exclude-Object($list) {
    $array = New-Object System.Collections.ArrayList
    foreach ($obj in $_) {
        If ($list -notcontains $obj.Name) {
            [void] $array.Add($obj)
        }
    }
    return $array
}

# ///// Pre-Task
# Create collections of choice
$typename = "System.Management.Automation.Host.ChoiceDescription"
$yes = new-object $typename("&Yes","Execute")
$no  = new-object $typename("&No","Not Execute")

$assembly= $yes.getType().AssemblyQualifiedName
$choice = new-object "System.Collections.ObjectModel.Collection``1[[$assembly]]"
$choice.add($yes)
$choice.add($no)

# Load PowerCLI Snap-in to PowerShell
LoadPowerCLI VMware.VimAutomation.Core

# Get Script folder path
$ScriptPath = Split-Path $MyInvocation.MyCommand.Path -Parent

# Case if config file not specified, use default configuration file
if(!"$FILE") 
{
	$FILE = ("$ScriptPath\$DEFAULT_CSV_CONFIG_FILE")
}

# Check if configuration file exist or not
if(Test-Path "$FILE") 
{
    Write-Host "Configuration file found. [$FILE]."
}
else
{
    Write-Host "Configuration file [$FILE] not found. Check the file path and re-run this script."
    Write-Host "Nothing to do, exit the program..."
    exit 1
}

# Create log directory
mkdir "$ScriptPath\logs"

# For escape dupliation of configuraiton filename, generate random value to add filename of Unicode.
# Unicode filename would be expected such as '_Config.344'.
$RANDOM = Get-Random 1000
$FILE_UNI = "$FILE.$RANDOM"

# Convert Charactor code to Unicode(SJIS would be not acceptable.)
Get-Content "$FILE" | Out-File "$FILE_UNI" -Encoding UNICODE

# Import configuration CSV file
$vms = Import-CSV "$FILE_UNI"


# ///// Main
DoCommand-WithConfirm "start-transcript $ScriptPath\logs\auto_conf_vsphere.log" "Start to logging ??" $true

# Connect to vCenter
### Read credentials from configuration file
$VIServer=$vms[0].VCenterServer_Connect_Target
$VIUser=$vms[0].vCenterUserName
$VIPassword=$vms[0].vCenterUserPassword

### If credentials are in configuration file, use them to connect.
if( ($VIServer) -And ($VIUser) -And ($VIPassword))
{
	Write-Host "Connect to vCenter Server [$VIServer]`n`n..."
	$vi = Connect-VIServer -Server $VIServer -user $VIUser -password $VIPassword

	$i = 1
	while (1) 
	{
	    If ($vi.IsConnected) 
	    {
        	Write-Host "Connection complete vCenter Server [$VIServer] ...`n"
        	break
    	}
	
	    trap [System.Management.Automation.RuntimeException]
	    {
        	Write-Warning "Connection failed vCenter Server ..."
        	break
    	}
    	If ($i -ge 3) 
    	{
	        Throw "vCenter Server Authentication less than $i times."
        	break
    	}
    	$i++
	}
    
    
}
### If credentials are not in file, awaiting for user-input
elseif($VIServer)
{
	Write-Host "Connect to vCenter Server [$VIServer] `n`nInput User and Password ..."
	$i = 1
	$vi = $null
	while (1) 
	{
	    $cred = $host.ui.PromptForCredential("Connection established to vCenter Server", "Enter username/password of vCenter Server...", "", "")
	    $vi = Connect-VIServer -Server $VIServer -Credential $cred 2>&1
	    If ($vi.IsConnected) 
	    {
        	Write-Host "Connection complete vCenter Server [$VIServer] ...`n"
        	break
    	}
	
	    trap [System.Management.Automation.RuntimeException]
	    {
        	Write-Warning "Connection failed vCenter Server ..."
        	break
    	}
    	If ($i -ge 3) 
    	{
	        Throw "vCenter Server Authentication less than $i times."
        	break
    	}
    	$i++
	}
}
else
{
	Write-Host "Failed to connect vCenter Server, exiting..."
	exit
}

	

# Load paramters of vSphere
### DataCenter
$DatacenterName=$vms[0].DatacenterName
### ESXi Hosts(Note that username/password of each hosts are same)
$vSphereHostUserName = $vms[0].vSphereHostUserName
$vSphereHostPassword = $vms[0].vSphereHostPassword
### Clusters
$ClusterName_1=$vms[0].ClusterName
$ClusterName_2=$vms[1].ClusterName
$ClusterName_3=$vms[2].ClusterName
	

# Starting operations interactively
Write-Host "---------------Create DataCenter---------------"

$result_1=Get-Datacenter "$DatacenterName"

if(!"$DatacenterName") 
{
	Write-Host "No DataCenter defined in configuration file, please enter the DataCenter name to create." -fore Red
    exit 1
}
elseif ( ("$DatacenterName") -And ( !"$result_1" ) ) 
{
	Write-Host "No DataCenter found, Create new DataCenter[ $DatacenterName ]..."
	$answer = $host.ui.PromptForChoice("[Confirmation]","`nAre you sure to create Datacenter[ $DatacenterName ] ??",$choice,0)
	if ("$answer".Equals("0"))
	{
		$LOCATION = Get-Folder -NoRecursion
		New-Datacenter -Location "$LOCATION" -Name "$DatacenterName"
	}
	else
	{
		Write-Host "`nSkipped to create DataCenter [ $DatacenterName ]" -fore Red
	}	
} 
else 
{
	Write-Host "DataCenter[ $DatacenterName ] already exists. Skipped to create it."
}

Write-Host "---------------Create Clusters---------------"
Write-Host "Note: "
Write-Host "- If EVC settings defined, configure them."
Write-Host "- HA Settings would be done in last part of this step."

# Load parameter of EVC mode
$EVC_Mode=$vms[0].EVC_Mode

foreach ($cl in $vms) 
{
	$ClusterName = $cl.ClusterName

	if("$ClusterName") 
	{
		if($EVC_Mode)
		{
			$answer = $host.ui.PromptForChoice("[Confirmation]","`n`Are you sure to create Cluster[ $ClusterName ] under [ $DatacenterName ] with EVC mode:[ $EVC_Mode ] ??",$choice,0)
			if ("$answer".Equals("0"))
			{
				New-Cluster -Location $DatacenterName -Name $ClusterName -EVCMode $EVC_Mode
			}
			else
			{
				Write-Host "`nSkipped to create Cluster[ $ClusterName ]" -fore Red
			}	
		}
		else
		{
			$answer = $host.ui.PromptForChoice("[Confirmation]","`n`Are you sure to create Cluster[ $ClusterName ] under [ $DatacenterName ] ??",$choice,0)
			if ("$answer".Equals("0"))
			{
				New-Cluster -Location $DatacenterName -Name $ClusterName
			}
			else
			{
				Write-Host "`nSkipped to create Cluster[ $ClusterName ]" -fore Red
			}	
		}
	}
}


Write-Host "---------------Register ESXi Hosts to Cluster---------------"
## Join hosts to Cluster1
if ("$ClusterName_1")
{
	$answer = $host.ui.PromptForChoice("[Confirmation]","`nAre you sure to join each Host to Cluster[ $ClusterName_1 ] ??",$choice,0)
	if ("$answer".Equals("0"))
	{	
		foreach ($vm in $vms) 
		{
			$vSphereHost = $vm.vSphereHost_Cluster1
			if("$vSphereHost") 
			{
    			Add-VMHost -Name "$vSphereHost" -Location "$ClusterName_1" -User "$vSphereHostUserName" -Password "$vSphereHostPassword" -RunAsync -Force
    			timeout 2
			}
		}
	}
	else
	{
		Write-Host "`nSkipped to register hosts to Cluster[ $ClusterName_1 ]" -fore Red
	}	
}

## Join hosts to Cluster2
if ("$ClusterName_2")
{
	$answer = $host.ui.PromptForChoice("[Confirmation]","`nAre you sure to join each Host to Cluster[ $ClusterName_2 ] ??",$choice,0)
	if ("$answer".Equals("0"))
	{	
		foreach ($vm in $vms) 
		{
			$vSphereHost = $vm.vSphereHost_Cluster2
			if("$vSphereHost") 
			{
    			Add-VMHost -Name "$vSphereHost" -Location "$ClusterName_2" -User "$vSphereHostUserName" -Password "$vSphereHostPassword" -RunAsync -Force
    			timeout 2
			}
		}
	}
	else
	{
		Write-Host "`nSkipped to register hosts to Cluster[ $ClusterName_2 ]" -fore Red
	}	
}

## Join hosts to Cluster3
if ("$ClusterName_3")
{
	$answer = $host.ui.PromptForChoice("[Confirmation]","`nAre you sure to join each Host to Cluster[ $ClusterName_3 ] ??",$choice,0)
	if ("$answer".Equals("0"))
	{	
		foreach ($vm in $vms) 
		{
			$vSphereHost = $vm.vSphereHost_Cluster3
			if("$vSphereHost") 
			{
    			Add-VMHost -Name "$vSphereHost" -Location "$ClusterName_3" -User "$vSphereHostUserName" -Password "$vSphereHostPassword" -RunAsync -Force
    			timeout 2
			}
		}
	}
	else
	{
		Write-Host "`nSkipped to register hosts to Cluster[ $ClusterName_3 ]" -fore Red
	}	
}

# Moved to Maintenace mode
Write-Host "---------------Move to Maintenace mode---------------"
Write-Host "Please wait 60 seconds to finish joining hosts to cluster...." -fore Red
timeout 60

$answer = $host.ui.PromptForChoice("[Confirmation]","`nAre you sure to set host Maintenace mode ??",$choice,0)
if ("$answer".Equals("0"))
{	
	foreach ($cl in $vms)
	{
		$ClusterName=$cl.ClusterName
		if ($ClusterName)
		{
			# Except hosts on which are running VMs
			$EXCLUDE_ESXHOST = Get-VM -Location $ClusterName | Where-Object {$_.PowerState -eq 'PoweredOn'} | ForEach-Object {$_.Host}
			$EXCLUDE_ESXHOST = $EXCLUDE_ESXHOST -join ","
			$EXCLUDE_ESXHOST = $EXCLUDE_ESXHOST.Split(",")
			Get-VMHost -Location $ClusterName | Exclude-Object($EXCLUDE_ESXHOST) | Set-VMHost -State 'Maintenance' -RunAsync -Confirm:$false
		}
	}
}

Write-Host "---------------NTP Server Settings---------------"
timeout 60

## NTP settiing for Cluster1
if ("$ClusterName_1")
{
	$answer = $host.ui.PromptForChoice("[Confirmation]","`nAre you sure to add NTP Server to Cluster[ $ClusterName_1 ],`nwith auto-starting settings ??",$choice,0)
	if ("$answer".Equals("0"))
	{
		# Load NTP Server address from configuration file
		foreach ($ntp in $vms)
		{
			$NTP_Server=$ntp.NTP_Server_Cluster1
			if("$NTP_Server") 
			{
				Get-VMHost -Location "$ClusterName_1" | Add-VmHostNtpServer -NtpServer "$NTP_Server"
			}
		}
			
	Get-VMHost -Location "$ClusterName_1" | Get-VMHostService | where {$_.key -eq "ntpd"} | Set-VMHostService -Policy On
	Get-VMHost -Location "$ClusterName_1" | Get-VMHostService | where {$_.key -eq "ntpd"} | Start-VMHostService

	}
	else
	{
		Write-Host "`nSkipped to configure NTP address to Cluster[ $ClusterName_1 ]." -fore Red
	}
}

## NTP settiing for Cluster2
if ("$ClusterName_2")
{
	$answer = $host.ui.PromptForChoice("[Confirmation]","`nAre you sure to add NTP Server to Cluster[ $ClusterName_2 ],`nwith auto-starting settings ??",$choice,0)
	if ("$answer".Equals("0"))
	{
		# Load NTP Server address from configuration file
		foreach ($ntp in $vms)
		{
			$NTP_Server=$ntp.NTP_Server_Cluster2
			if("$NTP_Server") 
			{
				Get-VMHost -Location "$ClusterName_2" | Add-VmHostNtpServer -NtpServer "$NTP_Server"
			}
		}
			
	Get-VMHost -Location "$ClusterName_2" | Get-VMHostService | where {$_.key -eq "ntpd"} | Set-VMHostService -Policy On
	Get-VMHost -Location "$ClusterName_2" | Get-VMHostService | where {$_.key -eq "ntpd"} | Start-VMHostService

	}
	else
	{
		Write-Host "`nSkipped to configure NTP address to Cluster[ $ClusterName_2 ]." -fore Red
	}
}


## NTP settiing for Cluster3
if ("$ClusterName_3")
{
	$answer = $host.ui.PromptForChoice("[Confirmation]","`nAre you sure to add NTP Server to Cluster[ $ClusterName_3 ],`nwith auto-starting settings ??",$choice,0)
	if ("$answer".Equals("0"))
	{
		# Load NTP Server address from configuration file
		foreach ($ntp in $vms)
		{
			$NTP_Server=$ntp.NTP_Server_Cluster3
			if("$NTP_Server") 
			{
				Get-VMHost -Location "$ClusterName_3" | Add-VmHostNtpServer -NtpServer "$NTP_Server"
			}
		}
			
	Get-VMHost -Location "$ClusterName_3" | Get-VMHostService | where {$_.key -eq "ntpd"} | Set-VMHostService -Policy On
	Get-VMHost -Location "$ClusterName_3" | Get-VMHostService | where {$_.key -eq "ntpd"} | Start-VMHostService

	}
	else
	{
		Write-Host "`nSkipped to configure NTP address to Cluster[ $ClusterName_3 ]." -fore Red
	}
}


Write-Host "---------------Syslog Server Settings---------------"
## Syslog Server settings for Cluster1
if ("$ClusterName_1")
{
	# Load syslog Server address from configuration file
	$Syslog_Server=$vms[0].Syslog_Server_Cluster1

	if("$Syslog_Server") 
	{
		$answer = $host.ui.PromptForChoice("[Confirmation]","`nAre you sure to configure syslog server:[ $Syslog_Server ] to Cluster[ $ClusterName_1 ],`n with Paremeters:: Syslog.global.defaultRotate==90`nSyslog.global.defaultSize==10240`nand Firewall settings of [ syslog ] and [ VM serial port connected over network ] ??",$choice,0)
		if ("$answer".Equals("0"))
		{
			Get-VMHost -Location "$ClusterName_1" | Set-VMHostSysLogServer -SysLogServer "$Syslog_Server"
			# Set parameters
			Get-VMHost -Location "$ClusterName_1" | Get-AdvancedSetting -Name "Syslog.global.defaultRotate" | Set-AdvancedSetting -Value "90" -Confirm:$false
			Get-VMHost -Location "$ClusterName_1" | Get-AdvancedSetting -Name "Syslog.global.defaultSize" | Set-AdvancedSetting -Value "10240" -Confirm:$false
			# Firewall configurations
			Get-VMHost -Location $ClusterName_1 | Get-VMHostFirewallException | where {$_.Name.StartsWith('syslog')} | Set-VMHostFirewallException -Enabled $true 
			Get-VMHost -Location $ClusterName_1 | Get-VMHostFirewallException | where {$_.Name.StartsWith('VM serial port connected over network')} | Set-VMHostFirewallException -Enabled $true
		}
		else
		{
			Write-Host "`nSkipped to connfiguration of Cluster[ $ClusterName_1 ]." -fore Red
		}
	}
}

## Syslog Server settings for Cluster2
if ("$ClusterName_2")
{
	# Load syslog Server address from configuration file
	$Syslog_Server=$vms[0].Syslog_Server_Cluster2

	if("$Syslog_Server") 
	{
		$answer = $host.ui.PromptForChoice("[Confirmation]","`nAre you sure to configure syslog server:[ $Syslog_Server ] to Cluster[ $ClusterName_2 ],`n with Paremeters:: Syslog.global.defaultRotate==90`nSyslog.global.defaultSize==10240`nand Firewall settings of [ syslog ] and [ VM serial port connected over network ] ??",$choice,0)
		if ("$answer".Equals("0"))
		{
			Get-VMHost -Location "$ClusterName_2" | Set-VMHostSysLogServer -SysLogServer "$Syslog_Server"
			# Set parameters
			Get-VMHost -Location "$ClusterName_2" | Get-AdvancedSetting -Name "Syslog.global.defaultRotate" | Set-AdvancedSetting -Value "90" -Confirm:$false
			Get-VMHost -Location "$ClusterName_2" | Get-AdvancedSetting -Name "Syslog.global.defaultSize" | Set-AdvancedSetting -Value "10240" -Confirm:$false
			# Firewall configurations
			Get-VMHost -Location $ClusterName_2 | Get-VMHostFirewallException | where {$_.Name.StartsWith('syslog')} | Set-VMHostFirewallException -Enabled $true 
			Get-VMHost -Location $ClusterName_2 | Get-VMHostFirewallException | where {$_.Name.StartsWith('VM serial port connected over network')} | Set-VMHostFirewallException -Enabled $true
		}
		else
		{
			Write-Host "`nSkipped to connfiguration of Cluster[ $ClusterName_2 ]." -fore Red
		}
	}
}

## Syslog Server settings for Cluster3
if ("$ClusterName_3")
{
	# Load syslog Server address from configuration file
	$Syslog_Server=$vms[0].Syslog_Server_Cluster3

	if("$Syslog_Server") 
	{
		$answer = $host.ui.PromptForChoice("[Confirmation]","`nAre you sure to configure syslog server:[ $Syslog_Server ] to Cluster[ $ClusterName_3 ],`n with Paremeters:: Syslog.global.defaultRotate==90`nSyslog.global.defaultSize==10240`nand Firewall settings of [ syslog ] and [ VM serial port connected over network ] ??",$choice,0)
		if ("$answer".Equals("0"))
		{
			Get-VMHost -Location "$ClusterName_3" | Set-VMHostSysLogServer -SysLogServer "$Syslog_Server"
			# Set parameters
			Get-VMHost -Location "$ClusterName_3" | Get-AdvancedSetting -Name "Syslog.global.defaultRotate" | Set-AdvancedSetting -Value "90" -Confirm:$false
			Get-VMHost -Location "$ClusterName_3" | Get-AdvancedSetting -Name "Syslog.global.defaultSize" | Set-AdvancedSetting -Value "10240" -Confirm:$false
			# Firewall configurations
			Get-VMHost -Location $ClusterName_3 | Get-VMHostFirewallException | where {$_.Name.StartsWith('syslog')} | Set-VMHostFirewallException -Enabled $true 
			Get-VMHost -Location $ClusterName_3 | Get-VMHostFirewallException | where {$_.Name.StartsWith('VM serial port connected over network')} | Set-VMHostFirewallException -Enabled $true
		}
		else
		{
			Write-Host "`nSkipped to connfiguration of Cluster[ $ClusterName_3 ]." -fore Red
		}
	}
}




# Run TeraTerm Macro with esxcli
## For Cluster1
if ("$ClusterName_1")
{
	$answer = $host.ui.PromptForChoice("[Confirmation]","`nAre you sure to run TeraTeram Macro to Cluster[ $ClusterName_1 ] ??",$choice,0)
	if ("$answer".Equals("0"))
	{	
		# TeraTerm execution program
		[System.String]$teraMacroExe = $vms[0].Teraterm_Path
		foreach ($vm in $vms) 
		{
			# Get ESXi host lists of Cluster
			$vSphereHost = $vm.vSphereHost_Cluster1
			if("$vSphereHost") 
			{
				[System.String]$teraTTLFile = "$ScriptPath\$vSphereHost.ttl"
				Start-Process -FilePath $teraMacroExe -ArgumentList $teraTTLFile
				Start-Sleep -s 3
			}
		}
	}
}

## For Cluster2
if ("$ClusterName_2")
{
	$answer = $host.ui.PromptForChoice("[Confirmation]","`nAre you sure to run TeraTeram Macro to Cluster[ $ClusterName_2 ] ??",$choice,0)
	if ("$answer".Equals("0"))
	{	
		# TeraTerm execution program
		[System.String]$teraMacroExe = $vms[0].Teraterm_Path
		foreach ($vm in $vms) 
		{
			# Get ESXi host lists of Cluster
			$vSphereHost = $vm.vSphereHost_Cluster2
			if("$vSphereHost") 
			{
				[System.String]$teraTTLFile = "$ScriptPath\$vSphereHost.ttl"
				Start-Process -FilePath $teraMacroExe -ArgumentList $teraTTLFile
				Start-Sleep -s 3
			}
		}
	}
}

## For Cluster3
if ("$ClusterName_3")
{
	$answer = $host.ui.PromptForChoice("[Confirmation]","`nAre you sure to run TeraTeram Macro to Cluster[ $ClusterName_3 ] ??",$choice,0)
	if ("$answer".Equals("0"))
	{	
		# TeraTerm execution program
		[System.String]$teraMacroExe = $vms[0].Teraterm_Path
		foreach ($vm in $vms) 
		{
			# Get ESXi host lists of Cluster
			$vSphereHost = $vm.vSphereHost_Cluster3
			if("$vSphereHost") 
			{
				[System.String]$teraTTLFile = "$ScriptPath\$vSphereHost.ttl"
				Start-Process -FilePath $teraMacroExe -ArgumentList $teraTTLFile
				Start-Sleep -s 3
			}
		}
	}
}


# Domain Configurations
## Get name of Domain from configuration file
$Domain=$vms[0].Domain

if($Domain)
{
Write-Host "---------------Domain Authentication Settings---------------"
$DomainUserName=$vms[0].DomainUserName
$DomainUserPassword=$vms[0].DomainUserPassword
    # For Cluster1
	if ("$ClusterName_1")
	{
		foreach ($vm in $vms) 
		{
			# Get ESXi host lists of Cluster
			$vSphereHost = $vm.vSphereHost_Cluster1
			if("$vSphereHost")
			{
				DoCommand-WithConfirm "Get-VMHost `"$vSphereHost`" | Get-VMHostAuthentication | Set-VMHostAuthentication -JoinDomain -Domain `"$Domain`" -User `"$DomainUserName`" -Password `"$DomainUserPassword`" "    " Are you sure to join `"$vSphereHost`" to domain[`"$Domain`"] ??" $true
			}
		}
	}

    # For Cluster2
	if ("$ClusterName_2")
	{
		foreach ($vm in $vms) 
		{
			# Get ESXi host lists of Cluster
			$vSphereHost = $vm.vSphereHost_Cluster2
			if("$vSphereHost")
			{
				DoCommand-WithConfirm "Get-VMHost `"$vSphereHost`" | Get-VMHostAuthentication | Set-VMHostAuthentication -JoinDomain -Domain `"$Domain`" -User `"$DomainUserName`" -Password `"$DomainUserPassword`" "    " Are you sure to join `"$vSphereHost`" to domain[`"$Domain`"] ??" $true
			}
		}
	}

    # For Cluster3
	if ("$ClusterName_3")
	{
		foreach ($vm in $vms) 
		{
			# Get ESXi host lists of Cluster
			$vSphereHost = $vm.vSphereHost_Cluster3
			if("$vSphereHost")
			{
				DoCommand-WithConfirm "Get-VMHost `"$vSphereHost`" | Get-VMHostAuthentication | Set-VMHostAuthentication -JoinDomain -Domain `"$Domain`" -User `"$DomainUserName`" -Password `"$DomainUserPassword`" "    " Are you sure to join `"$vSphereHost`" to domain[`"$Domain`"] ??" $true
			}
		}
	}

    Write-Host "---------------Move to Maintenace mode---------------"
	$answer = $host.ui.PromptForChoice("[Confirmation]","`nAre you sure to set host Maintenace mode ??",$choice,0)
	if ("$answer".Equals("0"))
	{	
		foreach ($cl in $vms)
		{
			$ClusterName=$cl.ClusterName
			if ($ClusterName)
			{
    			# Except hosts on which are running VMs
				$EXCLUDE_ESXHOST = Get-VM -Location $ClusterName | Where-Object {$_.PowerState -eq 'PoweredOn'} | ForEach-Object {$_.Host}
				$EXCLUDE_ESXHOST = $EXCLUDE_ESXHOST -join ","
				$EXCLUDE_ESXHOST = $EXCLUDE_ESXHOST.Split(",")
				Get-VMHost -Location $ClusterName | Exclude-Object($EXCLUDE_ESXHOST) | Set-VMHost -State 'Maintenance' -RunAsync -Confirm:$false
			}
		}
	}
}


# Execute PowerShell for creating user 'ssmon' in ESXi hosts
## Note that this would be done before disable Root-Login
## Load Scripts path 
$USERADD_SCRIPT = ("$ScriptPath\create-localuser.ps1")
if(Test-Path "$USERADD_SCRIPT") 
{
	Write-Host "---------------Added user to ESXi hosts---------------"
    invoke-expression -Command .\$USERADD_SCRIPT
}


# Reboot
Write-Host "---------------Reboot ESXi hosts---------------"
timeout 60
$answer = $host.ui.PromptForChoice("[Confirmation]","`nAre you sure to reboot ESXi Hosts ??",$choice,0)
if ("$answer".Equals("0"))
{	
	foreach ($cl in $vms)
	{
		$ClusterName=$cl.ClusterName
		if ($ClusterName)
		{
    		# Except hosts on which are running VMs
			$EXCLUDE_RESTERTESXHOST = Get-VM -Location $ClusterName | Where-Object {$_.PowerState -eq 'PoweredOn'} | ForEach-Object {$_.Host}
			$EXCLUDE_RESTERTESXHOST = $EXCLUDE_RESTERTESXHOST -join ","
			$EXCLUDE_RESTERTESXHOST = $EXCLUDE_RESTERTESXHOST.Split(",")
			Get-VMHost -Location $ClusterName | Exclude-Object($EXCLUDE_RESTERTESXHOST) | Restart-VMHost -RunAsync -Confirm:$false
		}
	}
}



# Execute TeraTerm Macro to disable Root-Login to ESXi hosts
$answer = $host.ui.PromptForChoice("[Confirmation]","`nAre you sure to run TeraTerm macro to disable Root-Login ??",$choice,0)
if ("$answer".Equals("0"))
{	
[System.String]$teraTTLFile = "$ScriptPath\teraTarmMacroTTL.ttl"
[System.String]$teraMacroExe = $vms[0].Teraterm_Path
    # For Cluster1
	foreach ($vm in $vms) 
	{
		$vSphereHost = $vm.vSphereHost_Cluster1
		if("$vSphereHost") 
		{
			[System.String]$teraLog = "$ScriptPath\logs\Auto-Configuration_$vSphereHost.rootpermit.log"
			Write-Output ("Strconcat MSG `'$vSphereHost /ssh /2 /nosecuritywarning /auth=challenge /user=ssmon /passwd=$vSphereHostPassword`' ")                  | out-file $teraTTLFile Default
			Write-Output ("Connect MSG")                                                                                                                          | out-file $teraTTLFile Default -append
			Write-Output "wait `'#`'"                                                                                                                             | out-file $teraTTLFile Default -append
			Write-Output ("logopen `'" + $teraLog + "`' 0 1")                                                                                                     | out-file $teraTTLFile Default -append
			Write-Output "sendln `'uname -n`'"                                                                                                                    | out-file $teraTTLFile Default -append
			Write-Output "wait `'#`'"                                                                                                                             | out-file $teraTTLFile Default -append
			Write-Output "sendln `'sed -i -e `"s/PermitRootLogin yes/PermitRootLogin no/g`" /etc/ssh/sshd_config`'"                                               | out-file $teraTTLFile Default -append
			Write-Output "wait `'#`'"                                                                                                                             | out-file $teraTTLFile Default -append
			Write-Output "sendln `'/etc/init.d/SSH restart`'"                                                                                                     | out-file $teraTTLFile Default -append
			Write-Output ("logclose")                                                                                                                             | out-file $teraTTLFile Default -append
			Write-Output "sendln `'exit`'"                                                                                                                        | out-file $teraTTLFile Default -append

			Start-Process -FilePath $teraMacroExe -ArgumentList $teraTTLFile -Wait
			
			Remove-Item "$ScriptPath\teraTarmMacroTTL.ttl"

		}
	}

    # For Cluster2
	foreach ($vm in $vms) 
	{
		$vSphereHost = $vm.vSphereHost_Cluster2
		if("$vSphereHost") 
		{
			[System.String]$teraLog = "$ScriptPath\logs\Auto-Configuration_$vSphereHost.rootpermit.log"
			Write-Output ("Strconcat MSG `'$vSphereHost /ssh /2 /nosecuritywarning /auth=challenge /user=ssmon /passwd=$vSphereHostPassword`' ")                  | out-file $teraTTLFile Default
			Write-Output ("Connect MSG")                                                                                                                          | out-file $teraTTLFile Default -append
			Write-Output "wait `'#`'"                                                                                                                             | out-file $teraTTLFile Default -append
			Write-Output ("logopen `'" + $teraLog + "`' 0 1")                                                                                                     | out-file $teraTTLFile Default -append
			Write-Output "sendln `'uname -n`'"                                                                                                                    | out-file $teraTTLFile Default -append
			Write-Output "wait `'#`'"                                                                                                                             | out-file $teraTTLFile Default -append
			Write-Output "sendln `'sed -i -e `"s/PermitRootLogin yes/PermitRootLogin no/g`" /etc/ssh/sshd_config`'"                                               | out-file $teraTTLFile Default -append
			Write-Output "wait `'#`'"                                                                                                                             | out-file $teraTTLFile Default -append
			Write-Output "sendln `'/etc/init.d/SSH restart`'"                                                                                                     | out-file $teraTTLFile Default -append
			Write-Output ("logclose")                                                                                                                             | out-file $teraTTLFile Default -append
			Write-Output "sendln `'exit`'"                                                                                                                        | out-file $teraTTLFile Default -append

			Start-Process -FilePath $teraMacroExe -ArgumentList $teraTTLFile -Wait
			
			Remove-Item "$ScriptPath\teraTarmMacroTTL.ttl"
		}
	}	
	
    # For Cluster3	
	foreach ($vm in $vms) 
	{
		$vSphereHost = $vm.vSphereHost_Cluster3
		if("$vSphereHost") 
		{
			[System.String]$teraLog = "$ScriptPath\logs\Auto-Configuration_$vSphereHost.rootpermit.log"
			Write-Output ("Strconcat MSG `'$vSphereHost /ssh /2 /nosecuritywarning /auth=challenge /user=ssmon /passwd=$vSphereHostPassword`' ")                  | out-file $teraTTLFile Default
			Write-Output ("Connect MSG")                                                                                                                          | out-file $teraTTLFile Default -append
			Write-Output "wait `'#`'"                                                                                                                             | out-file $teraTTLFile Default -append
			Write-Output ("logopen `'" + $teraLog + "`' 0 1")                                                                                                     | out-file $teraTTLFile Default -append
			Write-Output "sendln `'uname -n`'"                                                                                                                    | out-file $teraTTLFile Default -append
			Write-Output "wait `'#`'"                                                                                                                             | out-file $teraTTLFile Default -append
			Write-Output "sendln `'sed -i -e `"s/PermitRootLogin yes/PermitRootLogin no/g`" /etc/ssh/sshd_config`'"                                               | out-file $teraTTLFile Default -append
			Write-Output "wait `'#`'"                                                                                                                             | out-file $teraTTLFile Default -append
			Write-Output "sendln `'/etc/init.d/SSH restart`'"                                                                                                     | out-file $teraTTLFile Default -append
			Write-Output ("logclose")                                                                                                                             | out-file $teraTTLFile Default -append
			Write-Output "sendln `'exit`'"                                                                                                                        | out-file $teraTTLFile Default -append

			Start-Process -FilePath $teraMacroExe -ArgumentList $teraTTLFile -Wait
			
			Remove-Item "$ScriptPath\teraTarmMacroTTL.ttl"
		}
	}		
	
	
}


Write-Host "---------------Create vDS---------------"
$answer = $host.ui.PromptForChoice("[Confirmation]","`nAre you sure to configure vDS(Distributed Switch) ??",$choice,0)
if ("$answer".Equals("0"))
{
	$dvSwitchName=$vms[0].dvSwitchName
	if("$dvSwitchName")
	{
        # Create vDS
		$dvSwitch_Version=$vms[0].dvSwitch_Version
		$dvSwitch_Discovery_Protocol=$vms[0].dvSwitch_Discovery_Protocol
		$dvSwitchUplinkName=$vms[0].dvSwitchUplinkName
		$dvSwitch_MTU=$vms[0].dvSwitch_MTU


		$dvSwitch_Uplink_Number=$vms[0].dvSwitch_Uplink_Number
		$target_vmnic=$vms[0].dvSwitch_vmnic -split ","
		$target_vmnic_1=$target_vmnic[0]
		$target_vmnic_2=$target_vmnic[1]

		$answer = $host.ui.PromptForChoice("Are you sure to create ","`vDS[ $dvSwitchName ] with :version[ $dvSwitch_Version ]:MTU[ $dvSwitch_MTU ] on DataCenter[ $DatacenterName ] ??",$choice,0)
		if ("$answer".Equals("0"))
		{
			if( ($dvSwitch_MTU) -And ($dvSwitch_Discovery_Protocol) -And ($dvSwitch_Uplink_Number) -And ($dvSwitch_Version) )
			{
				New-VDSwitch -Name $dvSwitchName -Location $DatacenterName -NumUplinkPorts $dvSwitch_Uplink_Number -LinkDiscoveryProtocol $dvSwitch_Discovery_Protocol -LinkDiscoveryProtocolOperation Listen -Mtu $dvSwitch_MTU -Version $dvSwitch_Version
			}
			elseif( (!$dvSwitch_MTU) -And ($dvSwitch_Discovery_Protocol) -And ($dvSwitch_Uplink_Number) -And ($dvSwitch_Version) )
			{
				New-VDSwitch -Name $dvSwitchName -Location $DatacenterName -NumUplinkPorts $dvSwitch_Uplink_Number -LinkDiscoveryProtocol $dvSwitch_Discovery_Protocol -LinkDiscoveryProtocolOperation Listen -Version $dvSwitch_Version
			}
			elseif( (!$dvSwitch_Discovery_Protocol) -And ($dvSwitch_Uplink_Number) -And ($dvSwitch_Version) )
			{
				New-VDSwitch -Name $dvSwitchName -Location $DatacenterName -NumUplinkPorts $dvSwitch_Uplink_Number -Version $dvSwitch_Version
			}
			else
			{
				New-VDSwitch -Name $dvSwitchName -Location $DatacenterName -NumUplinkPorts $dvSwitch_Uplink_Number
			}
		}
		else
		{
			Write-Host "`nSkipped to create vDS[ $dvSwitchName ]." -fore Red
		}
		
		# vDS UpLink Name
		if($dvSwitchUplinkName)
		{		
			$answer = $host.ui.PromptForChoice("[Confirmation]","`nAre you sure to configure UpLink [ $dvSwitchUplinkName ] to vDS[ $dvSwitchName ] ??",$choice,0)
			if ("$answer".Equals("0"))
			{
				# Modify vDS UpLink Name
				Get-VDPortgroup -Name "dvSwitch0-DVUplinks-*" | Set-VDPortgroup -Name $dvSwitchUplinkName 
			}
			else
			{
				Write-Host "`n Skipped to configure vDS UpLink Name." -fore Red
			}
		}

		# vDS Sharing Policy
		$dvSwitch_ShapingPolicy_In=$vms[0].dvSwitch_ShapingPolicy_In
		$dvSwitch_ShapingPolicy_In_check=$vms[0].dvSwitch_ShapingPolicy_In
		[System.Int64]$dvSwitch_ShapingPolicy_In_AverageBandwidth=([System.Int64]$vms[0].dvSwitch_ShapingPolicy_In_AverageBandwidth * 1000)
		[System.Int64]$dvSwitch_ShapingPolicy_In_PeakBandwidth=([System.Int64]$vms[0].dvSwitch_ShapingPolicy_In_PeakBandwidth * 1000)
		[System.Int64]$dvSwitch_ShapingPolicy_In_BurstSize=([System.Int64]$vms[0].dvSwitch_ShapingPolicy_In_BurstSize * 1024)

		if( ($dvSwitch_ShapingPolicy_In.Equals("FALSE")) -Or ($dvSwitch_ShapingPolicy_In.Equals("false")) )
		{	$dvSwitch_ShapingPolicy_In=$false	}
		else
		{	$dvSwitch_ShapingPolicy_In=$true	}

		$dvSwitch_ShapingPolicy_Out=$vms[0].dvSwitch_ShapingPolicy_Out
		$dvSwitch_ShapingPolicy_Out_check=$vms[0].dvSwitch_ShapingPolicy_Out
		[System.Int64]$dvSwitch_ShapingPolicy_Out_AverageBandwidth=([System.Int64]$vms[0].dvSwitch_ShapingPolicy_Out_AverageBandwidth * 1000)
		[System.Int64]$dvSwitch_ShapingPolicy_Out_PeakBandwidth=([System.Int64]$vms[0].dvSwitch_ShapingPolicy_Out_PeakBandwidth * 1000)
		[System.Int64]$dvSwitch_ShapingPolicy_Out_BurstSize=([System.Int64]$vms[0].dvSwitch_ShapingPolicy_Out_BurstSize * 1024)
		if( ($dvSwitch_ShapingPolicy_Out.Equals("FALSE")) -Or ($dvSwitch_ShapingPolicy_Out.Equals("false")) )
		{	$dvSwitch_ShapingPolicy_Out=$false	}
		else
		{	$dvSwitch_ShapingPolicy_Out=$true	}

		
		if( ($dvSwitch_ShapingPolicy_Out_check) -And ($dvSwitch_ShapingPolicy_Out_AverageBandwidth) -And ($dvSwitch_ShapingPolicy_Out_PeakBandwidth) -And ($dvSwitch_ShapingPolicy_Out_BurstSize) )
		{
			$answer = $host.ui.PromptForChoice("[Confirmation]","`nAre you sure to modify OutBand Traffic of vDS [ $dvSwitchName ] ??",$choice,0)
			if ("$answer".Equals("0"))
			{
				Get-VDSwitch $dvSwitchName | Get-VDTrafficShapingPolicy -Direction Out | Set-VDTrafficShapingPolicy -Enabled $dvSwitch_ShapingPolicy_Out -AverageBandwidth $dvSwitch_ShapingPolicy_Out_AverageBandwidth -PeakBandwidth $dvSwitch_ShapingPolicy_Out_PeakBandwidth -BurstSize $dvSwitch_ShapingPolicy_Out_BurstSize
		 	}
		 }
		 
		if( ($dvSwitch_ShapingPolicy_In_check) -And ($dvSwitch_ShapingPolicy_In_AverageBandwidth) -And ($dvSwitch_ShapingPolicy_In_PeakBandwidth) -And ($dvSwitch_ShapingPolicy_In_BurstSize) )
		{
			$answer = $host.ui.PromptForChoice("[Confirmation]","`nAre you sure to modify InBand Traffic of vDS [ $dvSwitchName ] ??",$choice,0)
			if ("$answer".Equals("0"))
			{
				Get-VDSwitch $dvSwitchName | Get-VDTrafficShapingPolicy -Direction In | Set-VDTrafficShapingPolicy -Enabled $dvSwitch_ShapingPolicy_In -AverageBandwidth $dvSwitch_ShapingPolicy_In_AverageBandwidth -PeakBandwidth $dvSwitch_ShapingPolicy_In_PeakBandwidth -BurstSize $dvSwitch_ShapingPolicy_In_BurstSize
		 	}
		 }

		# vDS NIC Teaming Policy
		$dvSwitch_NicTeamingPolicy_LoadBalancingPolicy=$vms[0].dvSwitch_NicTeamingPolicy_LoadBalancingPolicy
		$dvSwitch_NicTeamingPolicy_NetworkFailoverDetectionPolicy=$vms[0].dvSwitch_NicTeamingPolicy_NetworkFailoverDetectionPolicy
		$dvSwitch_NicTeamingPolicy_NotifySwitches=$vms[0].dvSwitch_NicTeamingPolicy_NotifySwitches
		$dvSwitch_NicTeamingPolicy_FailbackEnabled=$vms[0].dvSwitch_NicTeamingPolicy_FailbackEnabled
		$dvSwitch_NicTeamingPolicy_NotifySwitches_check=$vms[0].dvSwitch_NicTeamingPolicy_NotifySwitches
		$dvSwitch_NicTeamingPolicy_FailbackEnabled_check=$vms[0].dvSwitch_NicTeamingPolicy_FailbackEnabled
		if( ($dvSwitch_NicTeamingPolicy_NotifySwitches.Equals("FALSE")) -Or ($dvSwitch_NicTeamingPolicy_NotifySwitches.Equals("false")) )
		{	$dvSwitch_NicTeamingPolicy_NotifySwitches=$false	}
		else
		{	$dvSwitch_NicTeamingPolicy_NotifySwitches=$true	}

		if( ($dvSwitch_NicTeamingPolicy_FailbackEnabled.Equals("FALSE")) -Or ($dvSwitch_NicTeamingPolicy_FailbackEnabled.Equals("false")) )
		{	$dvSwitch_NicTeamingPolicy_FailbackEnabled=$false	}
		else
		{	$dvSwitch_NicTeamingPolicy_FailbackEnabled=$true	}

		$answer = $host.ui.PromptForChoice("[Confirmation]","`nAre you sure to modify NIC-Teaming of vDS [ $dvSwitchName ]",$choice,0)
		if ("$answer".Equals("0"))
		{
			if($dvSwitch_NicTeamingPolicy_LoadBalancingPolicy)
			{
			 	Get-VDSwitch $dvSwitchName  | Get-VDUplinkTeamingPolicy | Set-VDUplinkTeamingPolicy -LoadBalancingPolicy $dvSwitch_NicTeamingPolicy_LoadBalancingPolicy -ActiveUplinkPort dvUplink1,dvUplink2 
		 	}
		 	
			if($dvSwitch_NicTeamingPolicy_NetworkFailoverDetectionPolicy)
			{
			 	Get-VDSwitch $dvSwitchName  | Get-VDUplinkTeamingPolicy | Set-VDUplinkTeamingPolicy -FailoverDetectionPolicy $dvSwitch_NicTeamingPolicy_NetworkFailoverDetectionPolicy  -ActiveUplinkPort dvUplink1,dvUplink2 
		 	}

			if($dvSwitch_NicTeamingPolicy_NotifySwitches_check)
			{
			 	Get-VDSwitch $dvSwitchName  | Get-VDUplinkTeamingPolicy | Set-VDUplinkTeamingPolicy -NotifySwitches $dvSwitch_NicTeamingPolicy_NotifySwitches -ActiveUplinkPort dvUplink1,dvUplink2 
		 	}

			if($dvSwitch_NicTeamingPolicy_FailbackEnabled_check)
			{
			 	Get-VDSwitch $dvSwitchName  | Get-VDUplinkTeamingPolicy | Set-VDUplinkTeamingPolicy -FailBack $dvSwitch_NicTeamingPolicy_FailbackEnabled -ActiveUplinkPort dvUplink1,dvUplink2
		 	}
		 	
		 }

        # vDS Security Policy
		$dvSwitch_Security_AllowPromiscuous=$vms[0].dvSwitch_Security_AllowPromiscuous
		$dvSwitch_Security_MacChanges=$vms[0].dvSwitch_Security_MacChanges
		$dvSwitch_Security_ForgedTransmits=$vms[0].dvSwitch_Security_ForgedTransmits
		$dvSwitch_Security_AllowPromiscuous_check=$vms[0].dvSwitch_Security_AllowPromiscuous
		$dvSwitch_Security_MacChanges_check=$vms[0].dvSwitch_Security_MacChanges
		$dvSwitch_Security_ForgedTransmits_check=$vms[0].dvSwitch_Security_ForgedTransmits

		if( ($dvSwitch_Security_AllowPromiscuous.Equals("FALSE")) -Or ($dvSwitch_Security_AllowPromiscuous.Equals("false")) )
		{	$dvSwitch_Security_AllowPromiscuous=$false	}
		else
		{	$dvSwitch_Security_AllowPromiscuous=$true	}

		if( ($dvSwitch_Security_MacChanges.Equals("FALSE")) -Or ($dvSwitch_Security_MacChanges.Equals("false")) )
		{	$dvSwitch_Security_MacChanges=$false	}
		else
		{	$dvSwitch_Security_MacChanges=$true	}

		if( ($dvSwitch_Security_ForgedTransmits.Equals("FALSE")) -Or ($dvSwitch_Security_ForgedTransmits.Equals("false")) )
		{	$dvSwitch_Security_ForgedTransmits=$false	}
		else
		{	$dvSwitch_Security_ForgedTransmits=$true	}


		$answer = $host.ui.PromptForChoice("[Confirmation]","`nAre you sure to modify security of vDS [ $dvSwitchName ] ??",$choice,0)
		if ("$answer".Equals("0"))
		{
			if($dvSwitch_Security_AllowPromiscuous_check)
			{
				Get-VDSwitch $dvSwitchName | Get-VDSecurityPolicy | Set-VDSecurityPolicy -AllowPromiscuous $dvSwitch_Security_AllowPromiscuous
			}
			if($dvSwitch_Security_MacChanges_check)
			{
				Get-VDSwitch $dvSwitchName | Get-VDSecurityPolicy | Set-VDSecurityPolicy -MacChanges $dvSwitch_Security_MacChanges
			}
			if($dvSwitch_Security_ForgedTransmits_check)
			{
				Get-VDSwitch $dvSwitchName | Get-VDSecurityPolicy | Set-VDSecurityPolicy -ForgedTransmits $dvSwitch_Security_ForgedTransmits
			}
		 }

		
		# Add hosts to vDS
        ## For Cluster1
		if ("$ClusterName_1")
		{
			$answer = $host.ui.PromptForChoice("[Confirmation]","`nAre you sure to join hosts of Cluster[ $ClusterName_1 ] to vDS [ $dvSwitchName ] ??",$choice,0)
			if ("$answer".Equals("0"))
			{
				foreach ($vm in $vms) 
				{
					$vSphereHost = $vm.vSphereHost_Cluster1				
					if($vSphereHost) 
					{
						Get-VDSwitch -Name $dvSwitchName | Add-VDSwitchVMHost -VMHost $vSphereHost 
					}
				}
			}
			else
			{
				Write-Host "`nSkipped to configurations of hosts in Cluster[ $ClusterName_1 ]." -fore Red
			}

			$answer = $host.ui.PromptForChoice("[Confirmation]","`nAre you sure to add [ $target_vmnic_1 ] and [ $target_vmnic_2 ] of [ $ClusterName_1 ] to vDS[ $dvSwitchName ] ??",$choice,0)
			if ("$answer".Equals("0"))
			{
				$vmhostNetworkAdapter = Get-VMHost -Location "$ClusterName_1" | Get-VMHostNetworkAdapter -Physical -Name "$target_vmnic_1"
				Get-VDSwitch $dvSwitchName | Add-VDSwitchPhysicalNetworkAdapter -VMHostNetworkAdapter $vmhostNetworkAdapter -Confirm:$false

				$vmhostNetworkAdapter = Get-VMHost -Location "$ClusterName_1" | Get-VMHostNetworkAdapter -Physical -Name "$target_vmnic_2"
				Get-VDSwitch $dvSwitchName | Add-VDSwitchPhysicalNetworkAdapter -VMHostNetworkAdapter $vmhostNetworkAdapter -Confirm:$false
			}
			else
			{
				Write-Host "`nSkipped to configurations of hosts in Cluster[ $ClusterName_1 ]." -fore Red
			}
		}

        ## For Cluster2
		if ("$ClusterName_2")
		{
			$answer = $host.ui.PromptForChoice("[Confirmation]","`nAre you sure to join hosts of Cluster[ $ClusterName_2 ] to vDS [ $dvSwitchName ] ??",$choice,0)
			if ("$answer".Equals("0"))
			{
				foreach ($vm in $vms) 
				{
					$vSphereHost = $vm.vSphereHost_Cluster2
					if($vSphereHost) 
					{
						Get-VDSwitch -Name $dvSwitchName | Add-VDSwitchVMHost -VMHost $vSphereHost 
					}
				}
			}
			else
			{
				Write-Host "`nSkipped to configurations of hosts in Cluster[ $ClusterName_2 ]." -fore Red
			}

			$answer = $host.ui.PromptForChoice("[Confirmation]","`nAre you sure to add [ $target_vmnic_1 ] and [ $target_vmnic_2 ] of [ $ClusterName_2 ] to vDS[ $dvSwitchName ] ??",$choice,0)
			if ("$answer".Equals("0"))
			{
				$vmhostNetworkAdapter = Get-VMHost -Location "$ClusterName_2" | Get-VMHostNetworkAdapter -Physical -Name "$target_vmnic_1"
				Get-VDSwitch $dvSwitchName | Add-VDSwitchPhysicalNetworkAdapter -VMHostNetworkAdapter $vmhostNetworkAdapter -Confirm:$false

				$vmhostNetworkAdapter = Get-VMHost -Location "$ClusterName_2" | Get-VMHostNetworkAdapter -Physical -Name "$target_vmnic_2"
				Get-VDSwitch $dvSwitchName | Add-VDSwitchPhysicalNetworkAdapter -VMHostNetworkAdapter $vmhostNetworkAdapter -Confirm:$false
			}
			else
			{
				Write-Host "`nSkipped to configurations of hosts in Cluster[ $ClusterName_2 ]." -fore Red
			}
		}

        ## For Cluster3
		if ("$ClusterName_3")
		{
			$answer = $host.ui.PromptForChoice("[Confirmation]","`nAre you sure to join hosts of Cluster[ $ClusterName_3 ] to vDS [ $dvSwitchName ] ??",$choice,0)
			if ("$answer".Equals("0"))
			{
				foreach ($vm in $vms) 
				{
					$vSphereHost = $vm.vSphereHost_Cluster3		
					if($vSphereHost) 
					{
						Get-VDSwitch -Name $dvSwitchName | Add-VDSwitchVMHost -VMHost $vSphereHost 
					}
				}
			}
			else
			{
				Write-Host "`nSkipped to configurations of hosts in Cluster[ $ClusterName_3 ]." -fore Red
			}

			$answer = $host.ui.PromptForChoice("[Confirmation]","`nAre you sure to add [ $target_vmnic_1 ] and [ $target_vmnic_2 ] of [ $ClusterName_3 ] to vDS[ $dvSwitchName ] ??",$choice,0)
			if ("$answer".Equals("0"))
			{
				$vmhostNetworkAdapter = Get-VMHost -Location "$ClusterName_3" | Get-VMHostNetworkAdapter -Physical -Name "$target_vmnic_1"
				Get-VDSwitch $dvSwitchName | Add-VDSwitchPhysicalNetworkAdapter -VMHostNetworkAdapter $vmhostNetworkAdapter -Confirm:$false

				$vmhostNetworkAdapter = Get-VMHost -Location "$ClusterName_3" | Get-VMHostNetworkAdapter -Physical -Name "$target_vmnic_2"
				Get-VDSwitch $dvSwitchName | Add-VDSwitchPhysicalNetworkAdapter -VMHostNetworkAdapter $vmhostNetworkAdapter -Confirm:$false
			}
			else
			{
				Write-Host "`nSkipped to configurations of hosts in Cluster[ $ClusterName_1 ]." -fore Red
			}
		}
		
		
		# Create PortGroup in vDS
		foreach ($dvs in $vms) 
			{
			$dvSwitch_Portgroup_Name=$dvs.dvSwitch_Portgroup_Name
			$dvSwitch_Portgroup_VLAN_ID=$dvs.dvSwitch_Portgroup_VLAN_ID

			if("$dvSwitch_Portgroup_Name")
			{
				$answer = $host.ui.PromptForChoice("[Confirmation]","`nAre you sure to add [ $dvSwitch_Portgroup_Name ] to vDS[ $dvSwitchName ] ??",$choice,0)
				if ("$answer".Equals("0"))
				{
					if("$dvSwitch_Portgroup_VLAN_ID")
					{
						New-VDPortgroup -Name $dvSwitch_Portgroup_Name -VDSwitch $dvSwitchName -VlanId $dvSwitch_Portgroup_VLAN_ID 
					}
					else
					{
						New-VDPortgroup -Name $dvSwitch_Portgroup_Name -VDSwitch $dvSwitchName
					}
				}
				
				# Add configuration of vDS PortGroup to ESXi hosts
                ## For Cluster1
				foreach ($vm in $vms) 
				{
					$vSphereHost = $vm.vSphereHost_Cluster1
					$dvSwitch_Portgroup_vmk=$dvs.dvSwitch_Portgroup_vmk					
					if("$vSphereHost") 
					{
						switch($dvSwitch_Portgroup_vmk)
						{
							"vmk0" { 
								$VMK_IP_Address=$vm.VMK0_IP_Address_Cluster1
								$VMK_IP_Subnet=$vm.VMK0_IP_Subnet_Cluster1
							}
							"vmk1" { 
								$VMK_IP_Address=$vm.VMK1_IP_Address_Cluster1
								$VMK_IP_Subnet=$vm.VMK1_IP_Subnet_Cluster1
							}
							"vmk2" { 
								$VMK_IP_Address=$vm.VMK2_IP_Address_Cluster1
								$VMK_IP_Subnet=$vm.VMK2_IP_Subnet_Cluster1
							}
							"vmk3" { 
								$VMK_IP_Address=$vm.VMK3_IP_Address_Cluster1
								$VMK_IP_Subnet=$vm.VMK3_IP_Subnet_Cluster1
							}
							"vmk4" { 
								$VMK_IP_Address=$vm.VMK4_IP_Address_Cluster1
								$VMK_IP_Subnet=$vm.VMK4_IP_Subnet_Cluster1
							}
							"vmk5" { 
								$VMK_IP_Address=$vm.VMK5_IP_Address_Cluster1
								$VMK_IP_Subnet=$vm.VMK5_IP_Subnet_Cluster1
							}
							"vmk6" { 
								$VMK_IP_Address=$vm.VMK6_IP_Address_Cluster1
								$VMK_IP_Subnet=$vm.VMK6_IP_Subnet_Cluster1
							}
							"vmk7" { 
								$VMK_IP_Address=$vm.VMK7_IP_Address_Cluster1
								$VMK_IP_Subnet=$vm.VMK7_IP_Subnet_Cluster1
							}
							"vmk8" { 
								$VMK_IP_Address=$vm.VMK8_IP_Address_Cluster1
								$VMK_IP_Subnet=$vm.VMK8_IP_Subnet_Cluster1
							}
							"vmk9" { 
								$VMK_IP_Address=$vm.VMK9_IP_Address_Cluster1
								$VMK_IP_Subnet=$vm.VMK9_IP_Subnet_Cluster1
							}
							"vmk10" { 
								$VMK_IP_Address=$vm.VMK10_IP_Address_Cluster1
								$VMK_IP_Subnet=$vm.VMK10_IP_Subnet_Cluster1
							}	
							default {Write-Output 'Provided paramters wrong, exiting the programs..' ; exit 0}
						}
												
						$answer = $host.ui.PromptForChoice("[Confirmation]","`nAre you sure to add [ $VMK_IP_Address ] and [ $VMK_IP_Subnet ] to [ $dvSwitch_Portgroup_Name ] in [ $vSphereHost ] ??",$choice,0)
						if ("$answer".Equals("0"))
						{
							Get-VMHost $vSphereHost | New-VMHostNetworkAdapter -PortGroup $dvSwitch_Portgroup_Name -VirtualSwitch $dvSwitchName -IP $VMK_IP_Address -SubnetMask $VMK_IP_Subnet 
						}
												
						$dvSwitch_Portgroup_vMotion=$dvs.dvSwitch_Portgroup_vMotion
						$dvSwitch_Portgroup_FaultToleranceLogging=$dvs.dvSwitch_Portgroup_FaultToleranceLogging
						$dvSwitch_Portgroup_Management=$dvs.dvSwitch_Portgroup_Management
						$dvSwitch_Portgroup_vMotion_check=$dvs.dvSwitch_Portgroup_vMotion
						$dvSwitch_Portgroup_FaultToleranceLogging_check=$dvs.dvSwitch_Portgroup_FaultToleranceLogging
						$dvSwitch_Portgroup_Management_check=$dvs.dvSwitch_Portgroup_Management
						if( ($dvSwitch_Portgroup_vMotion.Equals("FALSE")) -Or ($dvSwitch_Portgroup_vMotion.Equals("false")) )
						{	$dvSwitch_Portgroup_vMotion=$false	}
						else
						{	$dvSwitch_Portgroup_vMotion=$true	}
					
						if( ($dvSwitch_Portgroup_FaultToleranceLogging.Equals("FALSE")) -Or ($dvSwitch_Portgroup_FaultToleranceLogging.Equals("false")) )
						{	$dvSwitch_Portgroup_FaultToleranceLogging=$false	}
						else
						{	$dvSwitch_Portgroup_FaultToleranceLogging=$true	}
						if( ($dvSwitch_Portgroup_Management.Equals("FALSE")) -Or ($dvSwitch_Portgroup_Management.Equals("false")) )
						{	$dvSwitch_Portgroup_Management=$false	}
						else
						{	$dvSwitch_Portgroup_Management=$true	}

						# vMotion,FT,Management Tag Configurations
						if($dvSwitch_Portgroup_vMotion_check)
						{
							# PortGroup vMotion Tag
							Get-VMHost $vSphereHost | Get-VMHostNetworkAdapter -vmkernel -Name $dvSwitch_Portgroup_vmk | Set-VMHostNetworkAdapter -VMotionEnabled $dvSwitch_Portgroup_vMotion -Confirm:$false 
						}
						if($dvSwitch_Portgroup_FaultToleranceLogging_check)
						{
							Get-VMHost $vSphereHost | Get-VMHostNetworkAdapter -vmkernel -Name $dvSwitch_Portgroup_vmk | Set-VMHostNetworkAdapter -FaultToleranceLoggingEnabled $dvSwitch_Portgroup_FaultToleranceLogging  -Confirm:$false
						}
						if($dvSwitch_Portgroup_Management_check)
						{
							Get-VMHost $vSphereHost | Get-VMHostNetworkAdapter -vmkernel -Name $dvSwitch_Portgroup_vmk | Set-VMHostNetworkAdapter -ManagementTrafficEnabled $dvSwitch_Portgroup_Management -Confirm:$false 
						}
					}
				}
				
                ## For Cluster2
				foreach ($vm in $vms) 
				{
					$vSphereHost = $vm.vSphereHost_Cluster2
					$dvSwitch_Portgroup_vmk=$dvs.dvSwitch_Portgroup_vmk					
					if("$vSphereHost") 
					{
						switch($dvSwitch_Portgroup_vmk)
						{
							"vmk0" { 
								$VMK_IP_Address=$vm.VMK0_IP_Address_Cluster2
								$VMK_IP_Subnet=$vm.VMK0_IP_Subnet_Cluster2
							}
							"vmk1" { 
								$VMK_IP_Address=$vm.VMK1_IP_Address_Cluster2
								$VMK_IP_Subnet=$vm.VMK1_IP_Subnet_Cluster2
							}
							"vmk2" { 
								$VMK_IP_Address=$vm.VMK2_IP_Address_Cluster2
								$VMK_IP_Subnet=$vm.VMK2_IP_Subnet_Cluster2
							}
							"vmk3" { 
								$VMK_IP_Address=$vm.VMK3_IP_Address_Cluster2
								$VMK_IP_Subnet=$vm.VMK3_IP_Subnet_Cluster2
							}
							"vmk4" { 
								$VMK_IP_Address=$vm.VMK4_IP_Address_Cluster2
								$VMK_IP_Subnet=$vm.VMK4_IP_Subnet_Cluster2
							}
							"vmk5" { 
								$VMK_IP_Address=$vm.VMK5_IP_Address_Cluster2
								$VMK_IP_Subnet=$vm.VMK5_IP_Subnet_Cluster2
							}
							"vmk6" { 
								$VMK_IP_Address=$vm.VMK6_IP_Address_Cluster2
								$VMK_IP_Subnet=$vm.VMK6_IP_Subnet_Cluster2
							}
							"vmk7" { 
								$VMK_IP_Address=$vm.VMK7_IP_Address_Cluster2
								$VMK_IP_Subnet=$vm.VMK7_IP_Subnet_Cluster2
							}
							"vmk8" { 
								$VMK_IP_Address=$vm.VMK8_IP_Address_Cluster2
								$VMK_IP_Subnet=$vm.VMK8_IP_Subnet_Cluster2
							}
							"vmk9" { 
								$VMK_IP_Address=$vm.VMK9_IP_Address_Cluster2
								$VMK_IP_Subnet=$vm.VMK9_IP_Subnet_Cluster2
							}
							"vmk10" { 
								$VMK_IP_Address=$vm.VMK10_IP_Address_Cluster2
								$VMK_IP_Subnet=$vm.VMK10_IP_Subnet_Cluster2
							}
							default {Write-Output 'Provided paramters wrong, exiting the programs..' ; exit 0}
						}

						$answer = $host.ui.PromptForChoice("[Confirmation]","`nAre you sure to add [ $VMK_IP_Address ] and [ $VMK_IP_Subnet ] to [ $dvSwitch_Portgroup_Name ] in [ $vSphereHost ] ??",$choice,0)
						if ("$answer".Equals("0"))
						{
							Get-VMHost $vSphereHost | New-VMHostNetworkAdapter -PortGroup $dvSwitch_Portgroup_Name -VirtualSwitch $dvSwitchName -IP $VMK_IP_Address -SubnetMask $VMK_IP_Subnet 
						}

						$dvSwitch_Portgroup_vMotion=$dvs.dvSwitch_Portgroup_vMotion
						$dvSwitch_Portgroup_FaultToleranceLogging=$dvs.dvSwitch_Portgroup_FaultToleranceLogging
						$dvSwitch_Portgroup_Management=$dvs.dvSwitch_Portgroup_Management
						$dvSwitch_Portgroup_vMotion_check=$dvs.dvSwitch_Portgroup_vMotion
						$dvSwitch_Portgroup_FaultToleranceLogging_check=$dvs.dvSwitch_Portgroup_FaultToleranceLogging
						$dvSwitch_Portgroup_Management_check=$dvs.dvSwitch_Portgroup_Management
						if( ($dvSwitch_Portgroup_vMotion.Equals("FALSE")) -Or ($dvSwitch_Portgroup_vMotion.Equals("false")) )
						{	$dvSwitch_Portgroup_vMotion=$false	}
						else
						{	$dvSwitch_Portgroup_vMotion=$true	}
					
						if( ($dvSwitch_Portgroup_FaultToleranceLogging.Equals("FALSE")) -Or ($dvSwitch_Portgroup_FaultToleranceLogging.Equals("false")) )
						{	$dvSwitch_Portgroup_FaultToleranceLogging=$false	}
						else
						{	$dvSwitch_Portgroup_FaultToleranceLogging=$true	}
						if( ($dvSwitch_Portgroup_Management.Equals("FALSE")) -Or ($dvSwitch_Portgroup_Management.Equals("false")) )
						{	$dvSwitch_Portgroup_Management=$false	}
						else
						{	$dvSwitch_Portgroup_Management=$true	}

						#vMotion,FT,Management Tag Configurations
						if($dvSwitch_Portgroup_vMotion_check)
						{
							# PortGroup vMotion Tag
							Get-VMHost $vSphereHost | Get-VMHostNetworkAdapter -vmkernel -Name $dvSwitch_Portgroup_vmk | Set-VMHostNetworkAdapter -VMotionEnabled $dvSwitch_Portgroup_vMotion -Confirm:$false 
						}
						if($dvSwitch_Portgroup_FaultToleranceLogging_check)
						{
							Get-VMHost $vSphereHost | Get-VMHostNetworkAdapter -vmkernel -Name $dvSwitch_Portgroup_vmk | Set-VMHostNetworkAdapter -FaultToleranceLoggingEnabled $dvSwitch_Portgroup_FaultToleranceLogging  -Confirm:$false 
						}
						if($dvSwitch_Portgroup_Management_check)
						{
							Get-VMHost $vSphereHost | Get-VMHostNetworkAdapter -vmkernel -Name $dvSwitch_Portgroup_vmk | Set-VMHostNetworkAdapter -ManagementTrafficEnabled $dvSwitch_Portgroup_Management -Confirm:$false 
						}
					}
				}

                # For Cluster3
				foreach ($vm in $vms) 
				{
					$vSphereHost = $vm.vSphereHost_Cluster3
					$dvSwitch_Portgroup_vmk=$dvs.dvSwitch_Portgroup_vmk					
					if("$vSphereHost") 
					{
						switch($dvSwitch_Portgroup_vmk)
						{
							"vmk0" { 
								$VMK_IP_Address=$vm.VMK0_IP_Address_Cluster3
								$VMK_IP_Subnet=$vm.VMK0_IP_Subnet_Cluster3
							}
							"vmk1" { 
								$VMK_IP_Address=$vm.VMK1_IP_Address_Cluster3
								$VMK_IP_Subnet=$vm.VMK1_IP_Subnet_Cluster3
							}
							"vmk2" { 
								$VMK_IP_Address=$vm.VMK2_IP_Address_Cluster3
								$VMK_IP_Subnet=$vm.VMK2_IP_Subnet_Cluster3
							}
							"vmk3" { 
								$VMK_IP_Address=$vm.VMK3_IP_Address_Cluster3
								$VMK_IP_Subnet=$vm.VMK3_IP_Subnet_Cluster3
							}
							"vmk4" { 
								$VMK_IP_Address=$vm.VMK4_IP_Address_Cluster3
								$VMK_IP_Subnet=$vm.VMK4_IP_Subnet_Cluster3
							}
							"vmk5" { 
								$VMK_IP_Address=$vm.VMK5_IP_Address_Cluster3
								$VMK_IP_Subnet=$vm.VMK5_IP_Subnet_Cluster3
							}
							"vmk6" { 
								$VMK_IP_Address=$vm.VMK6_IP_Address_Cluster3
								$VMK_IP_Subnet=$vm.VMK6_IP_Subnet_Cluster3
							}
							"vmk7" { 
								$VMK_IP_Address=$vm.VMK7_IP_Address_Cluster3
								$VMK_IP_Subnet=$vm.VMK7_IP_Subnet_Cluster3
							}
							"vmk8" { 
								$VMK_IP_Address=$vm.VMK8_IP_Address_Cluster3
								$VMK_IP_Subnet=$vm.VMK8_IP_Subnet_Cluster3
							}
							"vmk9" { 
								$VMK_IP_Address=$vm.VMK9_IP_Address_Cluster3
								$VMK_IP_Subnet=$vm.VMK9_IP_Subnet_Cluster3
							}
							"vmk10" { 
								$VMK_IP_Address=$vm.VMK10_IP_Address_Cluster3
								$VMK_IP_Subnet=$vm.VMK10_IP_Subnet_Cluster3
							}
							default {Write-Output 'Provided paramters wrong, exiting the programs..' ; exit 0}
						}

						$answer = $host.ui.PromptForChoice("[Confirmation]","`nAre you sure to add [ $VMK_IP_Address ] and [ $VMK_IP_Subnet ] to [ $dvSwitch_Portgroup_Name ] in [ $vSphereHost ] ??",$choice,0)
						if ("$answer".Equals("0"))
						{
							Get-VMHost $vSphereHost | New-VMHostNetworkAdapter -PortGroup $dvSwitch_Portgroup_Name -VirtualSwitch $dvSwitchName -IP $VMK_IP_Address -SubnetMask $VMK_IP_Subnet 
						}

						$dvSwitch_Portgroup_vMotion=$dvs.dvSwitch_Portgroup_vMotion
						$dvSwitch_Portgroup_FaultToleranceLogging=$dvs.dvSwitch_Portgroup_FaultToleranceLogging
						$dvSwitch_Portgroup_Management=$dvs.dvSwitch_Portgroup_Management
						$dvSwitch_Portgroup_vMotion_check=$dvs.dvSwitch_Portgroup_vMotion
						$dvSwitch_Portgroup_FaultToleranceLogging_check=$dvs.dvSwitch_Portgroup_FaultToleranceLogging
						$dvSwitch_Portgroup_Management_check=$dvs.dvSwitch_Portgroup_Management
						if( ($dvSwitch_Portgroup_vMotion.Equals("FALSE")) -Or ($dvSwitch_Portgroup_vMotion.Equals("false")) )
						{	$dvSwitch_Portgroup_vMotion=$false	}
						else
						{	$dvSwitch_Portgroup_vMotion=$true	}
					
						if( ($dvSwitch_Portgroup_FaultToleranceLogging.Equals("FALSE")) -Or ($dvSwitch_Portgroup_FaultToleranceLogging.Equals("false")) )
						{	$dvSwitch_Portgroup_FaultToleranceLogging=$false	}
						else
						{	$dvSwitch_Portgroup_FaultToleranceLogging=$true	}
						if( ($dvSwitch_Portgroup_Management.Equals("FALSE")) -Or ($dvSwitch_Portgroup_Management.Equals("false")) )
						{	$dvSwitch_Portgroup_Management=$false	}
						else
						{	$dvSwitch_Portgroup_Management=$true	}

						# vMotion,FT,Management Tag Configurations
						if($dvSwitch_Portgroup_vMotion_check)
						{
							# PortGroup vMotion Tag
							Get-VMHost $vSphereHost | Get-VMHostNetworkAdapter -vmkernel -Name $dvSwitch_Portgroup_vmk | Set-VMHostNetworkAdapter -VMotionEnabled $dvSwitch_Portgroup_vMotion -Confirm:$false 
						}
						if($dvSwitch_Portgroup_FaultToleranceLogging_check)
						{
							Get-VMHost $vSphereHost | Get-VMHostNetworkAdapter -vmkernel -Name $dvSwitch_Portgroup_vmk | Set-VMHostNetworkAdapter -FaultToleranceLoggingEnabled $dvSwitch_Portgroup_FaultToleranceLogging  -Confirm:$false 
						}
						if($dvSwitch_Portgroup_Management_check)
						{
							Get-VMHost $vSphereHost | Get-VMHostNetworkAdapter -vmkernel -Name $dvSwitch_Portgroup_vmk | Set-VMHostNetworkAdapter -ManagementTrafficEnabled $dvSwitch_Portgroup_Management -Confirm:$false 
						}
					}
				}

				$dvSwitch_Portgroup_NicTeamingPolicy_LoadBalancingPolicy=$dvs.dvSwitch_Portgroup_NicTeamingPolicy_LoadBalancingPolicy
				$dvSwitch_Portgroup_NicTeamingPolicy_NetworkFailoverDetectionPolicy=$dvs.dvSwitch_Portgroup_NicTeamingPolicy_NetworkFailoverDetectionPolicy
				$dvSwitch_Portgroup_NicTeamingPolicy_NotifySwitches=$dvs.dvSwitch_Portgroup_NicTeamingPolicy_NotifySwitches
				$dvSwitch_Portgroup_NicTeamingPolicy_FailbackEnabled=$dvs.dvSwitch_Portgroup_NicTeamingPolicy_FailbackEnabled
				$dvSwitch_Portgroup_NicTeamingPolicy_NotifySwitches_check=$dvs.dvSwitch_Portgroup_NicTeamingPolicy_NotifySwitches
				$dvSwitch_Portgroup_NicTeamingPolicy_FailbackEnabled_check=$dvs.dvSwitch_Portgroup_NicTeamingPolicy_FailbackEnabled
				if( ($dvSwitch_Portgroup_NicTeamingPolicy_NotifySwitches.Equals("FALSE")) -Or ($dvSwitch_Portgroup_NicTeamingPolicy_NotifySwitches.Equals("false")) )
				{	$dvSwitch_Portgroup_NicTeamingPolicy_NotifySwitches=$false	}
				else
				{	$dvSwitch_Portgroup_NicTeamingPolicy_NotifySwitches=$true	}
			

				if( ($dvSwitch_Portgroup_NicTeamingPolicy_FailbackEnabled.Equals("FALSE")) -Or ($dvSwitch_Portgroup_NicTeamingPolicy_FailbackEnabled.Equals("false")) )
				{	$dvSwitch_Portgroup_NicTeamingPolicy_FailbackEnabled=$true	}
				else
				{	$dvSwitch_Portgroup_NicTeamingPolicy_FailbackEnabled=$false	}

				# Override of PortGroup NIC Teaming (Load-Balancing Policy)
				if($dvSwitch_Portgroup_NicTeamingPolicy_LoadBalancingPolicy)
				{
					Get-VDPortgroup $dvSwitch_Portgroup_Name | Get-VDUplinkTeamingPolicy | Set-VDUplinkTeamingPolicy -LoadBalancingPolicy $dvSwitch_Portgroup_NicTeamingPolicy_LoadBalancingPolicy
				}

                # Override of PortGroup Failover detechtiion
				if($dvSwitch_Portgroup_NicTeamingPolicy_NetworkFailoverDetectionPolicy)
				{
					Get-VDPortgroup $dvSwitch_Portgroup_Name | Get-VDUplinkTeamingPolicy | Set-VDUplinkTeamingPolicy -FailoverDetectionPolicy $dvSwitch_Portgroup_NicTeamingPolicy_NetworkFailoverDetectionPolicy
				}

                # Override of PortGroup Switch Notifications
				if($dvSwitch_Portgroup_NicTeamingPolicy_NotifySwitches_check)
				{
					Get-VDPortgroup $dvSwitch_Portgroup_Name | Get-VDUplinkTeamingPolicy | Set-VDUplinkTeamingPolicy -NotifySwitches $dvSwitch_Portgroup_NicTeamingPolicy_NotifySwitches 
				}

                # Override of PortGroup Fail-back
				if($dvSwitch_Portgroup_NicTeamingPolicy_FailbackEnabled_check)
				{
					Get-VDPortgroup $dvSwitch_Portgroup_Name | Get-VDUplinkTeamingPolicy | Set-VDUplinkTeamingPolicy -Failback $dvSwitch_Portgroup_NicTeamingPolicy_FailbackEnabled
				}

				
				
				$dvSwitch_Portgroup_Security_AllowPromiscuous=$dvs.dvSwitch_Portgroup_Security_AllowPromiscuous
				$dvSwitch_Portgroup_Security_MacChanges=$dvs.dvSwitch_Portgroup_Security_MacChanges
				$dvSwitch_Portgroup_Security_ForgedTransmits=$dvs.dvSwitch_Portgroup_Security_ForgedTransmits
				$dvSwitch_Portgroup_Security_AllowPromiscuous_check=$dvs.dvSwitch_Portgroup_Security_AllowPromiscuous
				$dvSwitch_Portgroup_Security_MacChanges_check=$dvs.dvSwitch_Portgroup_Security_MacChanges
				$dvSwitch_Portgroup_Security_ForgedTransmits_check=$dvs.dvSwitch_Portgroup_Security_ForgedTransmits

				if( ($dvSwitch_Portgroup_Security_AllowPromiscuous.Equals("FALSE")) -Or ($dvSwitch_Portgroup_Security_AllowPromiscuous.Equals("false")) )
				{	$dvSwitch_Portgroup_Security_AllowPromiscuous=$false	}
				else
				{	$dvSwitch_Portgroup_Security_AllowPromiscuous=$true	}
			
				if( ($dvSwitch_Portgroup_Security_MacChanges.Equals("FALSE")) -Or ($dvSwitch_Portgroup_Security_MacChanges.Equals("false")) )
				{	$dvSwitch_Portgroup_Security_MacChanges=$false	}
				else
				{	$dvSwitch_Portgroup_Security_MacChanges=$true	}
			
				if( ($dvSwitch_Portgroup_Security_ForgedTransmits.Equals("FALSE")) -Or ($dvSwitch_Portgroup_Security_ForgedTransmits.Equals("false")) )
				{	$dvSwitch_Portgroup_Security_ForgedTransmits=$false	}
				else
				{	$dvSwitch_Portgroup_Security_ForgedTransmits=$true	}


				# Configuration of Security Override
				if($dvSwitch_Portgroup_Security_AllowPromiscuous_check)
				{
					Get-VDPortgroup $dvSwitch_Portgroup_Name | Get-VDSecurityPolicy | Set-VDSecurityPolicy -AllowPromiscuous $dvSwitch_Portgroup_Security_AllowPromiscuous
				}

				if($dvSwitch_Portgroup_Security_MacChanges_check)
				{
					Get-VDPortgroup $dvSwitch_Portgroup_Name | Get-VDSecurityPolicy | Set-VDSecurityPolicy -MacChanges $dvSwitch_Portgroup_Security_MacChanges
				}

				if($dvSwitch_Portgroup_Security_ForgedTransmits_check)
				{
					Get-VDPortgroup $dvSwitch_Portgroup_Name | Get-VDSecurityPolicy | Set-VDSecurityPolicy -ForgedTransmits $dvSwitch_Portgroup_Security_ForgedTransmits
				}

				$dvSwitch_Portgroup_ShapingPolicy_In=$dvs.dvSwitch_Portgroup_ShapingPolicy_In
				$dvSwitch_Portgroup_ShapingPolicy_In_check=$dvs.dvSwitch_Portgroup_ShapingPolicy_In
				if( ($dvSwitch_Portgroup_ShapingPolicy_In.Equals("FALSE")) -Or ($dvSwitch_Portgroup_ShapingPolicy_In.Equals("false")) )
				{	$dvSwitch_Portgroup_ShapingPolicy_In=$false	}
				else
				{	$dvSwitch_Portgroup_ShapingPolicy_In=$true	}
				[System.Int64]$dvSwitch_Portgroup_ShapingPolicy_In_AverageBandwidth=([System.Int64]$dvs.dvSwitch_Portgroup_ShapingPolicy_In_AverageBandwidth * 1000)
				[System.Int64]$dvSwitch_Portgroup_ShapingPolicy_In_PeakBandwidth=([System.Int64]$dvs.dvSwitch_Portgroup_ShapingPolicy_In_PeakBandwidth * 1000)
				[System.Int64]$dvSwitch_Portgroup_ShapingPolicy_In_BurstSize=([System.Int64]$dvs.dvSwitch_Portgroup_ShapingPolicy_In_BurstSize * 1024)

				
				if( ($dvSwitch_Portgroup_ShapingPolicy_In_check) -And ($dvSwitch_Portgroup_ShapingPolicy_In_AverageBandwidth) -And ($dvSwitch_Portgroup_ShapingPolicy_In_PeakBandwidth) -And ($dvSwitch_Portgroup_ShapingPolicy_In_BurstSize) )
				{
					Get-VDSwitch $dvSwitchName | Get-VDPortgroup $dvSwitch_Portgroup_Name | Get-VDTrafficShapingPolicy -Direction In | Set-VDTrafficShapingPolicy -Enabled $dvSwitch_Portgroup_ShapingPolicy_In -AverageBandwidth $dvSwitch_Portgroup_ShapingPolicy_In_AverageBandwidth -PeakBandwidth $dvSwitch_Portgroup_ShapingPolicy_In_PeakBandwidth -BurstSize $dvSwitch_Portgroup_ShapingPolicy_In_BurstSize
				}


				$dvSwitch_Portgroup_ShapingPolicy_Out=$dvs.dvSwitch_Portgroup_ShapingPolicy_Out
				$dvSwitch_Portgroup_ShapingPolicy_Out_check=$dvs.dvSwitch_Portgroup_ShapingPolicy_Out
				if( ($dvSwitch_Portgroup_ShapingPolicy_Out.Equals("FALSE")) -Or ($dvSwitch_Portgroup_ShapingPolicy_Out.Equals("false")) )
				{	$dvSwitch_Portgroup_ShapingPolicy_Out=$false	}
				else
				{	$dvSwitch_Portgroup_ShapingPolicy_Out=$true	}
				[System.Int64]$dvSwitch_Portgroup_ShapingPolicy_Out_AverageBandwidth=([System.Int64]$dvs.dvSwitch_Portgroup_ShapingPolicy_Out_AverageBandwidth * 1000)
				[System.Int64]$dvSwitch_Portgroup_ShapingPolicy_Out_PeakBandwidth=([System.Int64]$dvs.dvSwitch_Portgroup_ShapingPolicy_Out_PeakBandwidth * 1000)
				[System.Int64]$dvSwitch_Portgroup_ShapingPolicy_Out_BurstSize=([System.Int64]$dvs.dvSwitch_Portgroup_ShapingPolicy_Out_BurstSize * 1024)


				if( ($dvSwitch_Portgroup_ShapingPolicy_Out_check) -And ($dvSwitch_Portgroup_ShapingPolicy_Out_AverageBandwidth) -And ($dvSwitch_Portgroup_ShapingPolicy_Out_PeakBandwidth) -And ($dvSwitch_Portgroup_ShapingPolicy_Out_BurstSize) )
				{
					Get-VDSwitch $dvSwitchName | Get-VDPortgroup $dvSwitch_Portgroup_Name | Get-VDTrafficShapingPolicy -Direction Out | Set-VDTrafficShapingPolicy -Enabled $dvSwitch_Portgroup_ShapingPolicy_Out -AverageBandwidth $dvSwitch_Portgroup_ShapingPolicy_Out_AverageBandwidth -PeakBandwidth $dvSwitch_Portgroup_ShapingPolicy_Out_PeakBandwidth -BurstSize $dvSwitch_Portgroup_ShapingPolicy_Out_BurstSize
				}
			}
		}
	}

}


# Enable Software iSCSI
$SoftwareISCSI=$vms[0].SoftwareISCSI	
if( ($SoftwareISCSI.Equals("TRUE")) -Or ($SoftwareISCSI.Equals("true")) )
{
	Write-Host "---------------Enabling Software iSCSI---------------"
		foreach ($cl in $vms) 
	{
		$ClusterName = $cl.ClusterName
			if("$ClusterName") 
		{
			$answer = $host.ui.PromptForChoice("[Confirmation]","`nAre you sure to Enable Software iSCSI on hosts in Cluster[ $ClusterName ] ??",$choice,0)
			if ("$answer".Equals("0"))
			{
				Get-VMHost -Location $ClusterName | Get-VMHostStorage | Set-VMHostStorage -SoftwareIScsiEnabled $true 
			}
			else
			{
				Write-Host "`n`Skipped to enable Software iSCSI of the hosts." -fore Red
			}
		}
	}
}



# Scheduler Settings
$SchedulerWithReservation=$vms[0].SchedulerWithReservation

if( ($SchedulerWithReservation.Equals("TRUE")) -Or ($SchedulerWithReservation.Equals("true")) )
{
Write-Host "---------------/Disk/SchedulerWithReservation Settings---------------"
	foreach ($cl in $vms)
	{
		$ClusterName=$cl.ClusterName
		if ("$ClusterName")
		{
			$answer = $host.ui.PromptForChoice("[Confirmation]","`nAre you sure to configure /Disk/SchedulerWithReservation==0 to Cluster[ $ClusterName ] ??",$choice,0)
			if ("$answer".Equals("0"))
			{
				Get-VMHost -Location $ClusterName | Get-AdvancedSetting -Name "Disk.SchedulerWithReservation" | Set-AdvancedSetting -Value 0 -Confirm:$false
			}
			else
			{
				Write-Host "`nSkipped to configurations of hosts in Cluster[ $ClusterName ]" -fore Red
			}	
		}
	}
}




# VMFS capacity settings
$MaxAddressableSpaceTB=$vms[0].MaxAddressableSpaceTB

if( ($MaxAddressableSpaceTB.Equals("TRUE")) -Or ($MaxAddressableSpaceTB.Equals("true")) )
{
Write-Host "---------------VMFS3.MaxAddressableSpaceTB Settings---------------"
    ## For Cluster1
	if ("$ClusterName_1")
	{
		$answer = $host.ui.PromptForChoice("[Confirmation]","`nAre you sure to configure VMFS3.MaxAddressableSpaceTB==128 to Cluster[ $ClusterName_1 ] ??",$choice,0)
		if ("$answer".Equals("0"))
		{
			Get-VMHost -Location "$ClusterName_1" | Get-AdvancedSetting -Name "VMFS3.MaxAddressableSpaceTB" | Set-AdvancedSetting -Value 128 -Confirm:$false
		}
		else
		{
			Write-Host "`nSkipped to configurations of VMFS3.MaxAddressableSpaceTB to hosts in Cluster[ $ClusterName_1 ]." -fore Red
		}
	}
    ## For Cluster2
	if ("$ClusterName_2")
	{
		$answer = $host.ui.PromptForChoice("[Confirmation]","`nAre you sure to configure VMFS3.MaxAddressableSpaceTB==128 to Cluster[ $ClusterName_2 ] ??",$choice,0)
		if ("$answer".Equals("0"))
		{
			Get-VMHost -Location "$ClusterName_2" | Get-AdvancedSetting -Name "VMFS3.MaxAddressableSpaceTB" | Set-AdvancedSetting -Value 128 -Confirm:$false
		}
		else
		{
			Write-Host "`nSkipped to configurations of VMFS3.MaxAddressableSpaceTB to hosts in Cluster[ $ClusterName_2 ]." -fore Red
		}
	}

    ## For Cluster3
	if ("$ClusterName_3")
	{
		$answer = $host.ui.PromptForChoice("[Confirmation]","`nAre you sure to configure VMFS3.MaxAddressableSpaceTB==128 to Cluster[ $ClusterName_3 ] ??",$choice,0)
		if ("$answer".Equals("0"))
		{
			Get-VMHost -Location "$ClusterName_3" | Get-AdvancedSetting -Name "VMFS3.MaxAddressableSpaceTB" | Set-AdvancedSetting -Value 128 -Confirm:$false
		}
		else
		{
			Write-Host "`nSkipped to configurations of VMFS3.MaxAddressableSpaceTB to hosts in Cluster[ $ClusterName_3 ]." -fore Red
		}
	}

Write-Host "---------------Move to Maintenace mode before Host Reboot to get HostProfile---------------"
$answer = $host.ui.PromptForChoice("[Confirmation]","`nAre you sure to set host Maintenace mode ??",$choice,0)
if ("$answer".Equals("0"))
{	
	foreach ($cl in $vms)
	{
		$ClusterName=$cl.ClusterName
		if ($ClusterName)
		{
			# Except hosts on which are running VMs
			$EXCLUDE_ESXHOST = Get-VM -Location $ClusterName | Where-Object {$_.PowerState -eq 'PoweredOn'} | ForEach-Object {$_.Host}
			$EXCLUDE_ESXHOST = $EXCLUDE_ESXHOST -join ","
			$EXCLUDE_ESXHOST = $EXCLUDE_ESXHOST.Split(",")		
			Get-VMHost -Location $ClusterName | Exclude-Object($EXCLUDE_ESXHOST) | Set-VMHost -State 'Maintenance' -RunAsync -Confirm:$false
		}
	}

}

Write-Host "---------------Reboot ESXi Hosts---------------"
Write-Host "Please wait for a minute to complete entering Maintenace mode..." -fore Red
timeout 60

$answer = $host.ui.PromptForChoice("[Confirmation]","`nAre you sure to reboot ESXi Hosts ??",$choice,0)
if ("$answer".Equals("0"))
{	
	foreach ($cl in $vms)
	{
		$ClusterName=$cl.ClusterName
		if ($ClusterName)
		{
			# Except hosts on which are running VMs
			$EXCLUDE_RESTERTESXHOST = Get-VM -Location $ClusterName | Where-Object {$_.PowerState -eq 'PoweredOn'} | ForEach-Object {$_.Host}
			$EXCLUDE_RESTERTESXHOST = $EXCLUDE_RESTERTESXHOST -join ","
			$EXCLUDE_RESTERTESXHOST = $EXCLUDE_RESTERTESXHOST.Split(",")
			Get-VMHost -Location $ClusterName | Exclude-Object($EXCLUDE_RESTERTESXHOST) | Restart-VMHost -RunAsync -Confirm:$false
		}
	}
}


Write-Host "---------------Cluster HA Settings---------------"
foreach ($cl in $vms) 
{
	$ClusterName = $cl.ClusterName
	if("$ClusterName") 
	{
		$answer = $host.ui.PromptForChoice("[Confirmation]","`n`Are you sure to enable HA of Cluster[ $ClusterName ] ??",$choice,0)
		if ("$answer".Equals("0"))
		{		
			$HAAdmissionControlEnabled=$vms[0].HAAdmissionControlEnabled
			if( ($HAAdmissionControlEnabled.Equals("TRUE")) -Or ($HAAdmissionControlEnabled.Equals("true")) )
			{	
				Set-Cluster -Cluster $ClusterName -HAEnabled:$true -HAAdmissionControlEnabled:$true -HARestartPriority Medium -HAIsolationResponse DoNothing -HAFailoverLevel 1 -VMSwapfilePolicy WithVM
			}
			else
			{	
				# Disable Admission Controls
				Set-Cluster -Cluster $ClusterName -HAEnabled:$true -HAAdmissionControlEnabled:$false -HARestartPriority Medium -HAIsolationResponse DoNothing -VMSwapfilePolicy WithVM
			}

			# Disable VM-Monitoring and set 'High'
			$spec = New-Object VMware.Vim.ClusterConfigSpecEx
			$spec.dasConfig = New-Object VMware.Vim.ClusterDasConfigInfo
			$spec.dasConfig.vmMonitoring = "vmMonitoringDisabled"
			$spec.dasConfig.defaultVmSettings = New-Object VMware.Vim.ClusterDasVmSettings
			$spec.dasConfig.defaultVmSettings.vmToolsMonitoringSettings = New-Object VMware.Vim.ClusterVmToolsMonitoringSettings
			$spec.dasConfig.defaultVmSettings.vmToolsMonitoringSettings.enabled = $true
			$spec.dasConfig.defaultVmSettings.vmToolsMonitoringSettings.vmMonitoring = "vmMonitoringDisabled"
			$spec.dasConfig.defaultVmSettings.vmToolsMonitoringSettings.failureInterval = 30
			$spec.dasConfig.defaultVmSettings.vmToolsMonitoringSettings.minUpTime = 120
			$spec.dasConfig.defaultVmSettings.vmToolsMonitoringSettings.maxFailures = 3
			$spec.dasConfig.defaultVmSettings.vmToolsMonitoringSettings.maxFailureWindow = 3600
			$cluster = Get-Cluster -Name "$ClusterName"
			$_this = Get-View -Id $cluster.Id
			$_this.ReconfigureComputeResource_Task($spec, $true)
		}
		else
		{
			Write-Host "`nSkipped to configurations to Cluster[ $ClusterName ]" -fore Red
		}
	}
}



Write-Host "---------------Create HostProfile---------------"
Write-Host "Please wait for rebooting ESXi hosts. It would take some time..." -fore Red
timeout 600

$answer = $host.ui.PromptForChoice("[Confirmation]","`nAre you sure to start creating HostProfile of each ESXi host ??",$choice,0)
if ("$answer".Equals("0"))
{
    ## For Cluster1
	if ("$ClusterName_1")
	{
		$vmhost=$vms[0].vSphereHost_Cluster1
		$profile_name=$ClusterName_1 + "_Profile"
		DoCommand-WithConfirm "New-VMHostProfile -Name `"$profile_name`" -ReferenceHost `"$vmhost`" "    " Are you sure to create HostProfile of `"$ClusterName_1`" with `"$vmhost`" ??" $true
	}
    ## For Cluster2
	if ("$ClusterName_2")
	{
		$vmhost=$vms[0].vSphereHost_Cluster2
		$profile_name=$ClusterName_2 + "_Profile"
		DoCommand-WithConfirm "New-VMHostProfile -Name `"$profile_name`" -ReferenceHost `"$vmhost`" "    " Are you sure to create HostProfile of `"$ClusterName_2`" with `"$vmhost`" ??" $true
	}
    ## For Cluster3
	if ("$ClusterName_3")
	{
		$vmhost=$vms[0].vSphereHost_Cluster3
		$profile_name=$ClusterName_3 + "_Profile"
		DoCommand-WithConfirm "New-VMHostProfile -Name `"$profile_name`" -ReferenceHost `"$vmhost`" "    " Are you sure to create HostProfile of `"$ClusterName_3`" with `"$vmhost`" ??" $true
	}
}


Write-Host "---------------Exporting HostProfiles---------------"
$answer = $host.ui.PromptForChoice("[Confirmation]","`nAre you sure to export HostProfiles ??",$choice,0)
if ("$answer".Equals("0"))
{
    ## For Cluster1
	if ("$ClusterName_1")
	{
		$profile_name=$ClusterName_1 + "_Profile"
		$profile_export_name="C:\" + $ClusterName_1 + "_Profile.vpf"
		DoCommand-WithConfirm "Export-VMHostProfile -FilePath `"$profile_export_name`" -Profile `"$profile_name`" -Force "    " Are you sure to export HostProfile of `"$ClusterName_1`" to `"$profile_export_name`" ??" $true
	}
    ## For Cluster2
	if ("$ClusterName_2")
	{
		$profile_name=$ClusterName_2 + "_Profile"
		$profile_export_name="C:\" + $ClusterName_2 + "_Profile.vpf"
		DoCommand-WithConfirm "Export-VMHostProfile -FilePath `"$profile_export_name`" -Profile `"$profile_name`" -Force "    " Are you sure to export HostProfile of `"$ClusterName_1`" to `"$profile_export_name`" ??" $true
	}
    ## For Cluster3
	if ("$ClusterName_3")
	{
		$profile_name=$ClusterName_3 + "_Profile"
		$profile_export_name="C:\" + $ClusterName_3 + "_Profile.vpf"
		DoCommand-WithConfirm "Export-VMHostProfile -FilePath `"$profile_export_name`" -Profile `"$profile_name`" -Force "    " Are you sure to export HostProfile of `"$ClusterName_1`" to `"$profile_export_name`" ??" $true
	}
}


Write-Host "---------------Exiting Maintenance mode---------------"
$answer = $host.ui.PromptForChoice("[Confirmation]","`n Are you sure to exit Maintenace mode ??",$choice,0)
if ("$answer".Equals("0"))
{	
	foreach ($cl in $vms)
	{
		$ClusterName=$cl.ClusterName
		if ($ClusterName)
		{
			Get-VMHost -Location $ClusterName | Set-VMHost -State 'Connected' -RunAsync -Confirm:$false
		}
	}
}


Write-Host "---------------Software iSCSI storage target settings---------------"
$answer = $host.ui.PromptForChoice("[Confirmation]","`nAre you sure to register Software iSCSI storage targets ??",$choice,0)
if ("$answer".Equals("0"))
{	
    ## For Cluster1
	foreach ($vm in $vms) 
	{
		$vSphereHost = $vm.vSphereHost_Cluster1
		if("$vSphereHost") 
		{
			foreach ($target in $vms) 
			{
				$target_ip=$target.iSCSI_Target_Address_Cluster1
				if("$target_ip")
				{
					$hba = Get-VMHost $vSphereHost | Get-VMHostHba -Type iScsi
					New-IScsiHbaTarget -IScsiHba $hba -Address $target_ip
				}
			}
		Get-VMHost $vSphereHost | Get-VmHostStorage -RescanAllHba
		}
	}
	## For Cluster2	
	foreach ($vm in $vms) 
	{
		$vSphereHost = $vm.vSphereHost_Cluster2
		if("$vSphereHost") 
		{
			foreach ($target in $vms) 
			{
				$target_ip=$target.iSCSI_Target_Address_Cluster2
				if("$target_ip")
				{
					$hba = Get-VMHost $vSphereHost | Get-VMHostHba -Type iScsi
					New-IScsiHbaTarget -IScsiHba $hba -Address $target_ip
				}
			}
		Get-VMHost $vSphereHost | Get-VmHostStorage -RescanAllHba
		}
	}
    ## For Cluster3
	foreach ($vm in $vms) 
	{
		$vSphereHost = $vm.vSphereHost_Cluster3
		if("$vSphereHost") 
		{
			foreach ($target in $vms) 
			{
				$target_ip=$target.iSCSI_Target_Address_Cluster3
				if("$target_ip")
				{
					$hba = Get-VMHost $vSphereHost | Get-VMHostHba -Type iScsi
					New-IScsiHbaTarget -IScsiHba $hba -Address $target_ip
				}
			}
		Get-VMHost $vSphereHost | Get-VmHostStorage -RescanAllHba
		}
	}

}
else
{
	Write-Host "`nSkipped to configuration of Software iSCSI storage targets." -fore Red
}




Write-Host "---------------Create VMFS DataStore---------------"
$answer = $host.ui.PromptForChoice("[Confirmation]","`n Are you sure to create VMFS DataStore ??",$choice,0)

if ("$answer".Equals("0"))
{
$FileSystemVersion=$vms[0].FileSystemVersion
	## For Cluster1
    if ("$ClusterName_1")
	{
		$vSphereHost = $vms[0].vSphereHost_Cluster1	
		foreach ($vmfs in $vms) 
		{
			$datastore_name=$vmfs.Datastore_Name_Cluster1
			$canonical_name=$vmfs.Datastore_CanonicalName_Cluster1	
			if("$datastore_name") 
			{
				New-Datastore -VMHost $vSphereHost -Name $datastore_name -Path $canonical_name -FileSystemVersion $FileSystemVersion
			}
		}
	}
	## For Cluster2
	if ("$ClusterName_2")
	{
		$vSphereHost = $vms[0].vSphereHost_Cluster2	
		foreach ($vmfs in $vms) 
		{
			$datastore_name=$vmfs.Datastore_Name_Cluster2
			$canonical_name=$vmfs.Datastore_CanonicalName_Cluster2	
			if("$datastore_name") 
			{
				New-Datastore -VMHost $vSphereHost -Name $datastore_name -Path $canonical_name -FileSystemVersion $FileSystemVersion
			}
		}
	}
	## For Cluster3
	if ("$ClusterName_3")
	{
		$vSphereHost = $vms[0].vSphereHost_Cluster3	
		foreach ($vmfs in $vms) 
		{
			$datastore_name=$vmfs.Datastore_Name_Cluster3
			$canonical_name=$vmfs.Datastore_CanonicalName_Cluster3	
			if("$datastore_name") 
			{
				New-Datastore -VMHost $vSphereHost -Name $datastore_name -Path $canonical_name -FileSystemVersion $FileSystemVersion
			}
		}
	}	
}


Write-Host "---------------Enable Storage I/O Controll---------------"
$answer = $host.ui.PromptForChoice("[Confirmation]","`n Are you sure to enable DataStore SIOC ??",$choice,0)

if ("$answer".Equals("0"))
{
	$StorageIOControl=$vms[0].StorageIOControl	
    ## For Cluster1
	if( ("$StorageIOControl".Equals("TRUE")) -Or ("$StorageIOControl".Equals("true")) )
	{
		if ("$ClusterName_1")
		{	
			foreach ($vmfs in $vms) 
			{		
				$datastore_name=$vmfs.Datastore_Name_Cluster1
				if("$datastore_name") 
				{
					Set-Datastore $datastore_name -StorageIOControlEnabled $true
				}
			}
		}
	}
    ## For Cluster2
	if( ("$StorageIOControl".Equals("TRUE")) -Or ("$StorageIOControl".Equals("true")) )
	{
		if ("$ClusterName_2")
		{	
			foreach ($vmfs in $vms) 
			{		
				$datastore_name=$vmfs.Datastore_Name_Cluster2	
				if("$datastore_name") 
				{
					Set-Datastore $datastore_name -StorageIOControlEnabled $true
				}
			}
		}
	}
    ## For Cluster3
	if( ("$StorageIOControl".Equals("TRUE")) -Or ("$StorageIOControl".Equals("true")) )
	{
		if ("$ClusterName_3")
		{
			foreach ($vmfs in $vms) 
			{		
				$datastore_name=$vmfs.Datastore_Name_Cluster3	
				if("$datastore_name") 
				{
					Set-Datastore $datastore_name -StorageIOControlEnabled $true
				}
			}
		}
	}	
}


Write-Host "---------------Disabale Delayed ACK---------------"
$answer = $host.ui.PromptForChoice("[Confirmation]","`nAre you sure to disable Delayed ACK ??",$choice,0)
if ("$answer".Equals("0"))
{	
	$Delayed_ACK_Disabled=$vms[0].Delayed_ACK_Disabled	
	if( ("$Delayed_ACK_Disabled".Equals("TRUE")) -Or ("$Delayed_ACK_Disabled".Equals("true")) )
	{
        ## For Cluster1
		foreach ($vm in $vms) 
		{
			$vSphereHost = $vm.vSphereHost_Cluster1
			if("$vSphereHost") 
			{
				#This section will get host information needed
				$HostView = Get-VMHost $vSphereHost | Get-View
				$HostStorageSystemID = $HostView.configmanager.StorageSystem
				$HostiSCSISoftwareAdapterHBAID = ($HostView.config.storagedevice.HostBusAdapter | where {$_.Model -match "iSCSI Software"}).device
				#This section sets the option you want.
				$options = New-Object VMWare.Vim.HostInternetScsiHbaParamValue[] (1)
				$options[0] = New-Object VMware.Vim.HostInternetScsiHbaParamValue
				$options[0].key = "DelayedAck"
				$options[0].value = $false		   
				#This section applies the options above to the host you got the information from.
				$HostStorageSystem = Get-View -ID $HostStorageSystemID
				$HostStorageSystem.UpdateInternetScsiAdvancedOptions($HostiSCSISoftwareAdapterHBAID, $null, $options)
			}
		}
        ## For Cluster2		
		foreach ($vm in $vms) 
		{
			$vSphereHost = $vm.vSphereHost_Cluster2
			if("$vSphereHost") 
			{
				#This section will get host information needed
				$HostView = Get-VMHost $vSphereHost | Get-View
				$HostStorageSystemID = $HostView.configmanager.StorageSystem
				$HostiSCSISoftwareAdapterHBAID = ($HostView.config.storagedevice.HostBusAdapter | where {$_.Model -match "iSCSI Software"}).device
				#This section sets the option you want.
				$options = New-Object VMWare.Vim.HostInternetScsiHbaParamValue[] (1)				
				$options[0] = New-Object VMware.Vim.HostInternetScsiHbaParamValue
				$options[0].key = "DelayedAck"
				$options[0].value = $false		   
				#This section applies the options above to the host you got the information from.
				$HostStorageSystem = Get-View -ID $HostStorageSystemID
				$HostStorageSystem.UpdateInternetScsiAdvancedOptions($HostiSCSISoftwareAdapterHBAID, $null, $options)
			}
		}
        ## For Cluster3		
		foreach ($vm in $vms) 
		{
			$vSphereHost = $vm.vSphereHost_Cluster3
			if("$vSphereHost") 
			{
				#This section will get host information needed
				$HostView = Get-VMHost $vSphereHost | Get-View
				$HostStorageSystemID = $HostView.configmanager.StorageSystem
				$HostiSCSISoftwareAdapterHBAID = ($HostView.config.storagedevice.HostBusAdapter | where {$_.Model -match "iSCSI Software"}).device
				#This section sets the option you want.
				$options = New-Object VMWare.Vim.HostInternetScsiHbaParamValue[] (1)				
				$options[0] = New-Object VMware.Vim.HostInternetScsiHbaParamValue
				$options[0].key = "DelayedAck"
				$options[0].value = $false		   
				#This section applies the options above to the host you got the information from.
				$HostStorageSystem = Get-View -ID $HostStorageSystemID
				$HostStorageSystem.UpdateInternetScsiAdvancedOptions($HostiSCSISoftwareAdapterHBAID, $null, $options)
			}
		}		
	}
}
# ///// Main End


# ///// Post Task
#  Disconnect from vCenter Server
Write-Host "Disconnect vCenter Server [$VIServer]"
Disconnect-VIServer -Server $VIServer -Confirm:$False

# Removed tmp Unicode configuration file
Remove-Item $FILE_UNI

# Stop logging
stop-transcript

Write-Host "Finished all tasks !!"
