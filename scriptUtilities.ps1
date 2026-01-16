################ ---------------- Start of utilities ---------------- ################
function outputException{
    param (
        [string] $customMessage,
        $exceptionMessage,
        $exceptionStackTrace
    )

    writeToFile -message "ERR: CM - $customMessage" -fileName $outputLog
    writeToFile -message "ERR: EM - $exceptionMessage" -fileName $outputLog
    writeToFile -message "ERR: ST - $exceptionStackTrace" -fileName $outputLog

}

function createDir{
    param(
        [string] $path,
        [string] $logName
    )

    try {
        if((Test-Path -Path $path) -eq $false){
            New-Item -Path $path -ItemType Directory
            writeToFile -message "Created directory: $path" -fileName $logName
        } else {
            writetoFile -message "Directory already exists: $path" -fileName $logName
        }
    }
    catch {
        outputException `
            -customMessage "ERR: createDir - Error encounter with path: $path and logName $logName" `
            -exceptionMessage $_.Exception.Message `
            -exceptionStackTrace $_.Exception.StackTrace

    }
}

function getTimeStamp {
    return (Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff K - ")
}

function writeToFile {
    param (
        [string] $message,
        [string] $fileName
    )

    Write-Output "$(getTimeStamp)$message" | Out-File -Append $fileName

}

function deleteOldFiles {
    param (
        [string[]] $sourcePaths,
        [string[]] $includeExtensions,
        [string[]] $excludeExtensions,
        [datetime] $expiryDate
    )

    try {
        $sourcePaths | ForEach-Object {
            writeToFile -message "deleteOldFiles - Search path: $_" -fileName $outputLog
            writeToFile -message "deleteOldFiles - Include extensions: $includeExtensions" -fileName $outputLog
            writeToFile -message "deleteOldFiles - Exclude extensions: $excludeExtensions" -fileName $outputLog
            writeToFile -message "deleteOldFiles - Expiry date: $expiryDate" -fileName $outputLog

            $files = Get-ChildItem -File -Recurse -Depth 1 -Include $includeExtensions -exclude $excludeExtensions `
                | Where-Object { $_.CreationTime -lt $expiryDate} | Select-Object FullName, CreationTime

            $files | ForEach-Object -Process {
                    writeToFile -message "deleteOldFiles - Deleting $($_.Name) with CTime: $($_.CreationTime)" -fileName $outputLog
                    $_.FullName | Remove-Item
            } 

            if ($null -eq $files) {
                writeToFile -message "deleteOldFiles - WRN - No files found in $_" -fileName $outputLog
            }
        }
    }
    catch {
        outputException `
            -customMessage "ERR: deleteOldFiles - Error with sourcePaths: $sourcePaths, includeExtensions: $includeExtensions, excludeExtensions: $excludeExtensions, expiryDate: $expiryDate" `
            -exceptionMessage $_.Exception.Message `
            -exceptionStackTrace $_.Exception.StackTrace
    }
}

################ ---------------- End of utilities ---------------- ################