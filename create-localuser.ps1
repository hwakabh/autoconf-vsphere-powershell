# hostlist.txt(ホストのIPリスト)が同一ディレクトリに存在している必要あり。

$ROOTUSER = "root"
$ROOTPASS = "password"
$ADDUSER = "ssmon"
$ADDUSERPW = "password"


#$esxisが配列としてESXiのIP情報を所持
$esxis = (Get-Content hostlist.txt) -as [string[]]

#配列内から1つずつ取り出してループ
#処理内容はユーザ作成およびAdmin権限の付与
foreach ($esxi in $esxis) {
  Connect-VIServer $esxi -User $ROOTUSER -Password $ROOTPASS
  New-VMHostAccount -ID $ADDUSER -Password $ADDUSERPW  -UserAccount -GrantShellAccess
  New-VIPermission -Entity $esxi -Principal $ADDUSER -Role Admin -Propagate:$true
  Disconnect-VIServer $esxi -Confirm:$false
}
