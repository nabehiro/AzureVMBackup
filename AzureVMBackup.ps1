# Backup Copy Azure Virtual Machine
# 
# This software is no warranty, the author can not be held responsible for any trouble caused by the use.
#
# [Backup Step]
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
$subscriptionName = "<input here>"
$cloudServiceName = "<input here>"
$virtualMachineName = "<input here>"
$remainigBackupCount = 2

function Log($msg)
{
    Write-Host "[" (Get-Date) "]" $msg
}

# Confirm execution
# ================================================================
Write-Host "=================================================="
Write-Host "Subscription Name: $subscriptionName"
Write-Host "Cloud Service Name: $cloudServiceName"
Write-Host "Virtual Machine Name: $virtualMachineName"
Write-Host "Remaining Backup Count: $remainigBackupCount"
Write-Host "=================================================="
Write-Host ""
if((Read-Host "Will you really backup ? :[Y/n]") -ne "Y")
{
    Write-Host "Backup stopped."
    exit
}
Write-Host ""

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

    Log "Start Stop-AzureVM"
	$vm | Stop-AzureVM -StayProvisioned | Out-Null
    Log "End   Stop-AzureVM"

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
$backupDirName = "backup_" + $virtualMachineName
$backupDirUrl = $blobUrl + $containerName + "/" + $backupDirName + "/" + (Get-Date -Format yyyyMMdd_HHmmss) + "/"

$storageContext = New-AzureStorageContext -StorageAccountName $storageAccountName -StorageAccountKey (Get-AzureStorageKey -StorageAccountName $storageAccountName).Primary

$copiedBlobs = @()

## Copy OS disk
$backupOsBlobUrl = $backupDirUrl + $osDisk.MediaLink.Segments[$osDisk.MediaLink.Segments.Length - 1]
Log "Copy OS Disk To: $($osDisk.MediaLink)"
$copiedBlobs += Start-AzureStorageBlobCopy -SrcBlob $osDisk.MediaLink -SrcContainer $containerName -DestBlob $backupOsBlobUrl -DestContainer $containerName -Context $storageContext

## Copy data disks
$dataDisks = $vm | Get-AzureDataDisk
foreach($dataDisk in $dataDisks)
{
    $backupDataBlobUrl = $backupDirUrl + $dataDisk.MediaLink.Segments[$dataDisk.MediaLink.Segments.Length - 1]
    Log "Copy Data Disk To: $($dataDisk.MediaLink)"
    $copiedBlobs += Start-AzureStorageBlobCopy -SrcBlob $dataDisk.MediaLink -SrcContainer $containerName -DestBlob $backupDataBlobUrl -DestContainer $containerName -Context $storageContext
}

## Wait copying complete
do
{
    Start-Sleep -Seconds 10
    $copyDone = $true
    foreach($copiedBlob in $copiedBlobs)
    {
        $state = $copiedBlob | Get-AzureStorageBlobCopyState -Context $storageContext
        Log "Copy Status($($copiedBlob.Name)): $($state.Status)"
        $copyDone = $copyDone -and ($state.Status -eq "Success")
    }
}
until ($copyDone)


# Restart Virtual Machine
# ================================================================
if($wasRunning)
{
    Log "Start Start-AzureVM"
	$vm | Start-AzureVM | Out-Null
    Log "End   Start-AzureVM"
}

# Remove old backup
# ================================================================
if ($remainigBackupCount -gt 0)
{
    $backupBlobs = Get-AzureStorageBlob -Container $containerName -Context $storageContext -Prefix $backupDirName
    $dirs = $backupBlobs | foreach { [Regex]::Replace($_.Name, "[^/]+$", "") } | Select-Object -Unique | Sort-Object
    if ($dirs.Count -gt $remainigBackupCount)
    {
        $delDirs = $dirs | select -First ($dirs.Count - $remainigBackupCount)
        foreach($backupBlob in $backupBlobs)
        {
            $dir = [Regex]::Replace($backupBlob.Name, "[^/]+$", "")
            if ($delDirs -contains $dir)
            {
                Log "Remove Backup: $($backupBlob.Name)"
                $backupBlob | Remove-AzureStorageBlob
            }
        }
    }
}


# End
# ================================================================
Write-Host ""
Write-Host "Backup complete!"
