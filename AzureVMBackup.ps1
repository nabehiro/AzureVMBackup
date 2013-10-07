# Backup Copy Azure Virtual Machine
#
# [Backup Flow]
# 1. Stop Virtual Machine.
# 2. Copy Virtual Machine OS and Data Disks.
# 3. Restart Virtual Machine.
# 4. (*optional) Remove old backup.
#
# [PreRequirement]
# - Install Windows Azure Powershell.
# - Import Azure Publish Setting File.
# See here,
# http://blog.greatrexpectations.com/2013/04/24/using-blob-snapshots-to-backup-azure-virtual-machines/


# Configuration
# ================================================================
$subscriptionName = "input here..."
$cloudServiceName = "input here..."
$virtualMachineName = "input here..."
$remainigBackupCount = 2


# Confirm execution
# ================================================================
Write-Host "Subscription Name: $subscriptionName"
Write-Host "Cloud Service Name: $cloudServiceName"
Write-Host "Virtual Machine Name: $virtualMachineName"
Write-Host "Remaining Backup Count: $remainigBackupCount"
if((Read-Host "Will you really backup ? :[Y/n]") -ne "Y")
{
    Write-Host "[Info ] Stop backup."
    exit
}


$vm = Get-AzureVM -ServiceName $cloudServiceName -Name $virtualMachineName
if($vm -eq $null)
{
    throw "VM is not found."
}

# Pre-require "Import-AzurePublishSettingsFile"
set-AzureSubscription $subscriptionName

[bool]$wasRunning = $false


# Shut down VM
# ================================================================
if(($vm.InstanceStatus -eq 'ReadyRole') -and ($vm.PowerState -eq 'Started'))
{
    $wasRunning = $true

    Write-Host "[Start] Stop-AzureVM:" (Get-Date)
	$vm | Stop-AzureVM -StayProvisioned | Out-Null
    Write-Host "[End  ] Stop-AzureVM:" (Get-Date)

    # WARN: following code may be not required.
	# Wait for the machine to shutdown
	do
	{
		Start-Sleep -Seconds 5
		$vm = Get-AzureVM -ServiceName $cloudServiceName -Name $virtualMachineName
	} while(($vm.InstanceStatus -eq 'ReadyRole') -and ($vm.PowerState -eq 'Started'))
}


# Copy VM disks
# ================================================================
$osDisk = $vm | Get-AzureOSDisk
if($osDisk -eq $null)
{
    throw "VM OS Disk is not found."
}

$storageAccountName = $osDisk.MediaLink.Host.Split('.')[0]
$blobUrl = $osDisk.MediaLink.Scheme + "://" + $osDisk.MediaLink.Host + "/"
$containerName = $osDisk.MediaLink.Segments[1].Substring(0, $osDisk.MediaLink.Segments[1].Length - 1)
# {Container Name}/backup_{Virtual Machine Name}/{yyyyMMdd_HHmmss}/
$backupDirPath = $containerName + "/" + "backup_" + $virtualMachineName + "/" + (Get-Date -Format yyyyMMdd_HHmmss) + "/"
$backupDirUrl = $blobUrl + $backupDirPath
Write-Host "[Info ] Backup Blob Directory:" $backupDirPath

$storageContext = New-AzureStorageContext -StorageAccountName $storageAccountName -StorageAccountKey (Get-AzureStorageKey -StorageAccountName $storageAccountName).Primary

## Copy OS disk
$backupOsBlobUrl = $backupDirUrl + $osDisk.MediaLink.Segments[$osDisk.MediaLink.Segments.Length - 1]
Write-Host "[Start] OS Disk Copy:" $osDisk.MediaLink ":" (Get-Date)
Start-AzureStorageBlobCopy -SrcBlob $osDisk.MediaLink -SrcContainer $containerName -DestBlob $backupOsBlobUrl -DestContainer $containerName -Context $storageContext | Out-Null
Write-Host "[End  ] OS Disk Copy:" $osDisk.MediaLink ":" (Get-Date)

## Copy data disks
$dataDisks = $vm | Get-AzureDataDisk
foreach($dataDisk in $dataDisks)
{
    $backupDataBlobUrl = $backupDirUrl + $dataDisk.MediaLink.Segments[$dataDisk.MediaLink.Segments.Length - 1]
    Write-Host "[Start] Data Disk Copy:" $dataDisk.MediaLink ":" (Get-Date)
    Start-AzureStorageBlobCopy -SrcBlob $dataDisk.MediaLink -SrcContainer $containerName -DestBlob $backupDataBlobUrl -DestContainer $containerName -Context $storageContext | Out-Null
    Write-Host "[End  ] Data Disk Copy:" $dataDisk.MediaLink ":" (Get-Date)
}


# Restart Virtual Machine
# ================================================================
if($wasRunning)
{
    Write-Host "[Start] Start-AzureVM:" (Get-Date)
	$vm | Start-AzureVM | Out-Null
    Write-Host "[End  ] Start-AzureVM:" (Get-Date)
}

# Remove old backup
# ================================================================
if ($remainigBackupCount -gt 0)
{
    
}


# End
# ================================================================
Write-Host "\n\nProcess complete!"
