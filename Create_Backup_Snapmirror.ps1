############### Creating Snapmirror Relationship to desire cluster
Param([parameter(Mandatory = $true)] $SourceClusterIP,
      [parameter(Mandatory = $true)] $SourceVserver,
      [parameter(Mandatory = $true)] $DestinationClusterIP,
      [parameter(Mandatory = $true)] $DestinationVserver)
function GetMostAvailableAggr($ncCluster){
    $MostAvilableAggr = (Get-NcAggr -Controller $ncCluster | ?{$_.AggrRaidAttributes.HasLocalRoot -like 'False'} | Sort-Object -Property Available -Descending)[0]
    return $MostAvilableAggr
}
$cred = Get-Credential
try{
    Import-Module dataontap -ErrorAction stop
    $ncSource = Connect-NcController $SourceClusterIP -Credential $cred
    $ncSourceName = (Get-NcCluster -Controller $ncSource).ClusterName
    $ncDestination = Connect-NcController $DestinationClusterIP -Credential $cred
    $ncDestinationName = (Get-NcCluster -Controller $ncDestination).ClusterName
}catch{Write-Host $_}
### Checking Cluster Peer and show current relationship
$srcVols = Get-NcVol -Controller $ncSource |?{$_.name -notlike "vol0" -and $_.name -notlike "*_root"} | select Name,vserver,@{n="TotalSize";e={$($_.totalsize/1gb)}},@{n="Language";e={$($_.VolumeLanguageAttributes.LanguageCode)}}
$srcVols | Add-Member -NotePropertyName HasSnapmirror -NotePropertyValue $false
foreach ($vol in $srcVols){
    if (Get-NcSnapmirrorDestination -Controller $ncSource -SourceVolume $vol.name -SourceVserver $vol.Vserver -DestinationVserver $DestinationVserver) {$vol.HasSnapmirror = $true}
}
$CreateSnapmirror = $srcVols | Out-GridView -Title "Select Volumes to create snapmirror" -PassThru
foreach ($vol in $CreateSnapmirror){
    try{
        Write-Host "Creating Volume $($vol.name) on cluster $ncDestinationNames..." -ForegroundColor Cyan
        $AvailableAggr = GetMostAvailableAggr -ncCluster $ncDestination
        New-NcVol -Controller $ncDestination -Aggregate $AvailableAggr.name -Name $vol.name -Language $vol.Language -JunctionPath $null -size 20mb -Type dp -VserverContext $DestinationVserver -ErrorAction stop
        New-NcSnapmirror -SourceVolume $vol.name -SourceVserver $vol.Vserver -SourceCluster $ncSourceName -Controller $ncDestination -DestinationVserver $DestinationVserver -DestinationVolume $vol.name -Policy DPDefault -DestinationCluster $ncDestinationName -Type XDP -ErrorAction stop | Out-Null 
    }catch{Write-Host $_ -ForegroundColor red; Read-Host "press any key co continue, otherwise press Ctrl+C"; continue}
}

Write-Host "Volumes been created at destination $ncDestinationName :"
foreach($vol in $CreateSnapmirror){
    Write-Host $vol.name
}
Read-Host "press any key to start initialize snapmirror for those volumes"

foreach ($vol in $CreateSnapmirror){
    try{
        Invoke-NcSnapmirrorInitialize -SourceVolume $vol.name -SourceVserver $vol.Vserver -SourceCluster $ncSourceName -Controller $ncDestination -DestinationVserver $DestinationVserver -DestinationVolume $vol.name -DestinationCluster $ncDestinationName
    }catch{Write-Host $_ -ForegroundColor red}
}