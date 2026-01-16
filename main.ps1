. ".\scriptUtilities.ps1"
. ".\stochastic.ps1"

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
            -customMessage "ERR: getItemCostByCurrency - Error with currencyArray: $currencyArray" `
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
#>
function sortCSV {
    param (
        [string] $csvFile,
        [string] $sortColumn
    )

    try {
        $file = Import-Csv -Path $csvFile

        $sorted = $file | Sort-Object -Descending { [double]$_.$sortColumn }

        $sorted | ConvertTo-Csv -NoTypeInformation | ForEach-Object { $_ -replace '"', '' } | Out-File -FilePath $csvFile
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

createDir -path $logPath -logName $outputLog
createDir -path ".\categoriesCost" -logName $outputLog
createDir -path ".\itemHistory" -logName $outputLog

$categoriesFile = ".\item_categories.json"
$itemsCostFile = ".\item_costs.csv"
$histName = "item_history"
$itemHistFile = ".\$histName.csv"
$SOHistFile = ".\SO$histName.csv"


################ ---------------- User Parameters ---------------- ################
# DIVINE DOESN'T WORK. need external source for divine cost.
#[string[]] $currencyArray = "exalted", "chaos"
[string[]] $currencyArray = "exalted"
$targetLeague = "Fate of the Vaal"

# OCR based csv file should be generated separately and placed in the script folder as ocr_output.csv
$ocrFile = ".\ocr_output.csv"

# must be mutiple of 4
[int]$bins = 40
################ ---------------- User Parameters ---------------- ################


################ ---------------- Core ---------------- ################

<#

[string[]] $categoryArray = getItemCategories -outputFile $categoriesFile

getItemCategoriesByReferenceCurrecy -categoryArray $categoryArray `
    -referenceCurrencyArray $currencyArray `
    -targetLeague $targetLeague

getItemCostByCurrency -currencyArray $currencyArray `
    -outputFile $itemsCostFile


mergeCSVFromOCR -csvFile $itemsCostFile `
    -csvOCR $ocrFile


doProfitMath -csvFile $itemsCostFile

sortCSV -csvFile $itemsCostFile `
    -sortColumn "margin"

#>

################ ---------------- Core ---------------- ################

################ ---------------- Stochastic ---------------- ################

getItemHistory -currencyArray $currencyArray `
    -bins $bins `
    -targetLeague $targetLeague

makeCSV -outputFile $itemHistFile

calcStochasticOscillator -srcCSVFile $itemHistFile `
    -destCSVFile $SOHistFile `
    -bins $bins

#sortCSV -csvFile $SOHistFile `
#    -sortColumn "stochasticOscilator"

################ ---------------- Stochastic ---------------- ################

deleteOldFiles -sourcePaths $logPath `
    -includeExtensions $includeExtensions `
    -excludeExtensions $excludeExtensions `
    -expiryDate $expiryDate
    