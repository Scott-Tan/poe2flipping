################ ---------------- Start of scripting management ---------------- ################
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

################ ---------------- End of scripting management ---------------- ################

<#
#   Get exchange rate of a currency to divine 
#>
function getDivineCost{
    param (
        [string] $baseCurrency
    )

    $file = Get-Content -Path ".\categoriesCost\currency_$baseCurrency.json" | ConvertFrom-Json
    $tmp = $file.items | Where-Object { $_.apiId -eq "divine"}

    return $tmp.currentPrice
}

<#
#   Get all types of currency categories that are tradable in the currency exchange
#>
function getItemCategories {
    param (
        [string] $outputFile
    )

    try {
        $response = Invoke-WebRequest `
            -Uri "https://poe2scout.com/api/items/categories" `
            -Method Get `
            -ContentType "application/json" `

        $response.Content | ConvertFrom-Json | ConvertTo-Json -Depth 100 | Out-File -FilePath $outputFile

        $file = Get-Content -Path $outputFile | ConvertFrom-Json
        [string[]] $categoryArray = @()
        foreach ($tmp in $file.currency_categories) {
            $categoryArray += $tmp.apiId
        }

        return $categoryArray
    }
    catch {
        outputException `
            -customMessage "ERR: getItemCategories - Error with outputFile: $outputFile" `
            -exceptionMessage $_.Exception.Message `
            -exceptionStackTrace $_.Exception.StackTrace
    }

}

<#
#   Get jsons of all items within a category, their properties, and notably their cost based on a reference currency
#>
function getItemCategoriesByReferenceCurrecy{
    param (
        [string[]] $categoryArray,
        [string[]] $referenceCurrencyArray,
        [string] $targetLeague
    )
    
    try {
        foreach ($category in $categoryArray) {
            foreach ($currency in $referenceCurrencyArray) {

                $parameters = @{
                    referenceCurrency = $currency
                    page = 1
                    pageSize = 250
                    league = $targetLeague
                }
                
                $uri = "https://poe2scout.com/api/items/currency/" + $category + "?"
                
                $response = Invoke-WebRequest `
                    -Uri $uri `
                    -Method Get `
                    -ContentType "application/json" `
                    -Body $parameters

                $response.Content | ConvertFrom-Json | ConvertTo-Json -Depth 100 | Out-File -FilePath ".\categoriesCost\$category`_$currency.json"
                
            }
        }
    }
    catch {
        outputException `
            -customMessage "ERR: getItemsCurrencyByCategory - Error with categoryArray: $categoryArray and referenceCurrencyArray: $referenceCurrencyArray" `
            -exceptionMessage $_.Exception.Message `
            -exceptionStackTrace $_.Exception.StackTrace
    }

}

<#
#   Generate csv of item costs by currency
#>
function getItemCostByCurrency{
    param (
        [string[]] $categoryArray,
        [string[]] $currencyArray,
        [string] $outputFile
    )

    try {

        # Remove old csv
        if((Test-Path -Path $outputFile) -eq $true){
            Remove-Item -Path $outputFile
        }

        # Add headers
        Write-Output "text, ref currency, currentPrice, diveqvalue, realdivcost, profit, margin" | Out-File -Append $outputFile


        $files = Get-ChildItem -Path ".\categoriesCost" -Filter *.json
        
        $files | ForEach-Object {
            $fileContent = Get-Content -Path $_.FullName | ConvertFrom-Json
            $items = $fileContent.items

            $currency = $_.BaseName.Split("_")[1]
            $divineCost = getDivineCost -baseCurrency $currency

            $items | ForEach-Object {
                $divEquivalent = [math]::Round($_.currentPrice / $divineCost, 4)
                Write-Output "$($_.text), $currency, $($_.currentPrice), $divEquivalent, 0, 0, 0" | Out-File -Append $outputFile
            }
        }

    }
    catch {
        outputException `
            -customMessage "ERR: getItemCostByCurrency - Error with categoryArray: $categoryArray and currencyArray: $currencyArray" `
            -exceptionMessage $_.Exception.Message `
            -exceptionStackTrace $_.Exception.StackTrace
    }

}

<#
#   Add real divine cost found from OCR to csv generated based on POE2 Scout data
#>
function mergeCSVFromOCR {
    param (
        [string] $csvFile,
        [string] $csvOCR
    )

    try {
        $file = Import-Csv -Path $csvFile 
        $ocrFile = Import-Csv -Path $csvOCR 

        foreach ($row in $file) {
            $ocrRow = $ocrFile | Where-Object { $_.text -eq $row.text }
            if ($null -ne $ocrRow) {
                $row.realdivcost = $ocrRow.realdivcost
            }
        }

        $file | ConvertTo-Csv -NoTypeInformation | ForEach-Object { $_ -replace '"', '' } | Out-File -FilePath $csvFile
    }
    catch {
        outputException `
            -customMessage "ERR: mergeCSVFromOCR - Error with $csvFile and $csvOCR" `
            -exceptionMessage $_.Exception.Message `
            -exceptionStackTrace $_.Exception.StackTrace
    }

}

<#
#   Math
#>
function doProfitMath {
    param (
        [string] $csvFile
    )

    try {
        $file = Import-Csv -Path $csvFile 
        
        foreach ($row in $file) {
            $row.profit = [double]$row.realdivcost - [double]$row.diveqvalue
            $row.margin = [double]$row.profit / [double]$row.diveqvalue * 100
        }

        $file | ConvertTo-Csv -NoTypeInformation | ForEach-Object { $_ -replace '"', '' } | Out-File -FilePath $csvFile
    }
    catch {
        outputException `
            -customMessage "ERR: doProfitMath - Error with $csvFile" `
            -exceptionMessage $_.Exception.Message `
            -exceptionStackTrace $_.Exception.StackTrace
    }

}

<#
#   Filter out records that were not OCRed and sort in descending order based on a column
#    columns should be profit or margin
#>
function sortCSV {
    param (
        [string] $csvFile,
        [string] $sortColumn
    )

    try {
        $file = Import-Csv -Path $csvFile | Where-Object { [double]$_."realdivcost" -ne 0 }

        $sorted = $file | Sort-Object -Descending { [double]$_.$sortColumn }

        $sorted | ConvertTo-Csv -NoTypeInformation | ForEach-Object { $_ -replace '"', '' } | Out-File -FilePath ".\sorted.csv"
    }
    catch {
        outputException `
            -customMessage "ERR: sortCSV - Error with $csvFile and $sortColumn" `
            -exceptionMessage $_.Exception.Message `
            -exceptionStackTrace $_.Exception.StackTrace
    }

}

$currDateTime = Get-Date -f yyyyMMddhhmm
$expiryDate = (Get-Date).AddMinutes(-1)
$includeExtensions = @("*.log")
$excludeExtensions = @("*.json", "*.csv")

$logPath = ".\logs"
$outputLog = "$logPath\$currDateTime" + "Output.log"
createDir -path ".\logs" -logName $outputLog
createDir -path ".\categoriesCost" -logName $outputLog

$categoriesFile = ".\item_categories.json"
$itemsCostFile = ".\item_costs.csv"


<# user parameters#>
# DIVINE DOESN'T WORK. need external source for divine cost.
[string[]] $currencyArray = "exalted", "chaos"
$targetLeague = "Fate of the Vaal"

# OCR based csv file should be generated separately and placed in the script folder as ocr_output.csv
$ocrFile = ".\ocr_output.csv"
<# user parameters#>



[string[]] $categoryArray = getItemCategories -outputFile $categoriesFile

getItemCategoriesByReferenceCurrecy -categoryArray $categoryArray `
    -referenceCurrencyArray $currencyArray `
    -targetLeague $targetLeague

getItemCostByCurrency -categoryArray $categoryArray `
    -currencyArray $currencyArray `
    -outputFile $itemsCostFile

mergeCSVFromOCR -csvFile $itemsCostFile `
    -csvOCR $ocrFile

doProfitMath -csvFile $itemsCostFile

sortCSV -csvFile $itemsCostFile `
    -sortColumn "margin"

deleteOldFiles -sourcePaths $logPath `
    -includeExtensions $includeExtensions `
    -excludeExtensions $excludeExtensions `
    -expiryDate $expiryDate
    