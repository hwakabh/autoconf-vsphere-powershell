# hostlist.txt(�z�X�g��IP���X�g)������f�B���N�g���ɑ��݂��Ă���K�v����B

$ROOTUSER = "root"
$ROOTPASS = "password"
$ADDUSER = "ssmon"
$ADDUSERPW = "password"


#$esxis���z��Ƃ���ESXi��IP��������
$esxis = (Get-Content hostlist.txt) -as [string[]]

#�z�������1�����o���ă��[�v
#�������e�̓��[�U�쐬�����Admin�����̕t�^
foreach ($esxi in $esxis) {
  Connect-VIServer $esxi -User $ROOTUSER -Password $ROOTPASS
  New-VMHostAccount -ID $ADDUSER -Password $ADDUSERPW  -UserAccount -GrantShellAccess
  New-VIPermission -Entity $esxi -Principal $ADDUSER -Role Admin -Propagate:$true
  Disconnect-VIServer $esxi -Confirm:$false
}
