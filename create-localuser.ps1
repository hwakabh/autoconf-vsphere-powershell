# This Scripts is intended to create ESXi local user
# Pre-Requirements :
#   - hostlist.txt should be located in same directories
#   - Write down the target ESXi to create user
#   - Credentials of ESXi should be same.

$ROOTUSER = "root"
$ROOTPASS = "password"
$ADDUSER = "ssmon"
$ADDUSERPW = "password"

# Load list of ESXi from ./hostlist.txt
$esxis = (Get-Content hostlist.txt) -as [string[]]

foreach ($esxi in $esxis) {
  Connect-VIServer $esxi -User $ROOTUSER -Password $ROOTPASS
  New-VMHostAccount -ID $ADDUSER -Password $ADDUSERPW  -UserAccount -GrantShellAccess
  # Create users / Add Admin Permission
  New-VIPermission -Entity $esxi -Principal $ADDUSER -Role Admin -Propagate:$true
  Disconnect-VIServer $esxi -Confirm:$false
}
