Import-Module ".\scriptUtilities.ps1"

<#
#   Get the history of every category of items found by getItemCategoriesByReferenceCurrecy()
#>
function getItemHistory{
    param (
        [string[]] $currencyArray,
        [int] $bins,
        [string] $targetLeague
    )

    try {

        $endTime = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.ffffff")
        $files = Get-ChildItem -Path ".\categoriesCost" -Filter *.json

        foreach ($currency in $currencyArray) {
            $parameters = @{
                league = $targetLeague
                logCount = $bins
                endTime = $endTime
                referenceCurrency = $currency
            }

            $files | ForEach-Object {
                Write-Host "Gettubg history of categories: $($_.FullName)"
                $file = Get-Content -Path $_.FullName | ConvertFrom-Json

                $file.items | ForEach-Object{
                    
                    $itemId = $_.itemId
                    $uri = "https://poe2scout.com/api/items/$itemId/history"
                    $response = Invoke-WebRequest `
                        -Uri $uri `
                        -Method Get `
                        -ContentType "application/json" `
                        -Body $parameters

                    $response.Content | ConvertFrom-Json | ConvertTo-Json -Depth 100 | Out-File -FilePath ".\itemHistory\$($_.apiId)_$currency.json"
                }

                Start-Sleep -Seconds 5
            }  
        }

    }
    catch {
        outputException `
            -customMessage "ERR: getItemHistory - Error with currencyArray: $currencyArray, bins: $bins, targetLeague: $targetLeague" `
            -exceptionMessage $_.Exception.Message `
            -exceptionStackTrace $_.Exception.StackTrace
    }

}


<#
#   Generate csv of items and their time history
#>
function makeCSV{
    param (
        [string] $outputFile
    )

    try {

        # Remove old csv
        if((Test-Path -Path $outputFile) -eq $true){
            Remove-Item -Path $outputFile
        }

        # Get sample file to create header of csv with releveant timestamps before plugging in all history values for each item
        $files = Get-ChildItem -Path ".\itemHistory" -Filter *.json
        $sample = Get-Content -Path $files[0].FullName | ConvertFrom-Json

        $header = "item"
        $sample.price_history | ForEach-Object {
            $header += ", $($_.time)"
        }

        Write-Output "$header, stochasticOscilator" | Out-File -Append $outputFile

        # Now get price of each item and append to csv file
        $files | ForEach-Object {
            $file = Get-Content -Path $_.FullName | ConvertFrom-Json
            $itemName = $_.BaseName.Split("_")[0]
            $row = "$itemName"
            $file.price_history | ForEach-Object {
                $row += ", $($_.price)"
            }

            Write-Output $row | Out-File -Append $outputFile
        }

    }
    catch {
        outputException `
            -customMessage "ERR: makeCSV - Error with outputFile: $outputFile" `
            -exceptionMessage $_.Exception.Message `
            -exceptionStackTrace $_.Exception.StackTrace
    }

}

<#
#   create a copy of item_history.csv and append to each row the Stochastic Oscillator
#>
function calcStochasticOscillator {
    param (
        [string] $srcCSVFile,
        [string] $destCSVFile,
        [int] $bins
    )

    try {
        # Get-Content to get raw values and avoid working with CSV tuples
        $file = Get-Content -Path $srcCSVFile

        # Overwrite/make file with header
        $file | Select-Object -First 1 | Out-File -FilePath $destCSVFile

        # Skip first row containing headers, then split the first column containing the item name
        $file | Select-Object -Skip 1 | ForEach-Object {
            # Get rid of item name
            $row = ($_ -split ", ", 2)[1]
            # Convert everything else into doubles for new array
            [double[]] $tmp = $row.Split(",") | ForEach-Object { [double]$_ } 
            # Do math
            [double] $minPrice = $tmp | Measure-Object -Minimum | Select-Object -ExpandProperty Minimum
            [double] $maxPrice = $tmp | Measure-Object -Maximum | Select-Object -ExpandProperty Maximum
            [double] $recentPrice = $tmp[0]
            #Write-host "Min price: $minPrice"
            #Write-Host "Max price: $maxPrice"
            #Write-Host "Recent price: $recentPrice"
            $stochasticOscillator = (($recentPrice - $minPrice) / ($maxPrice - $minPrice)) * 100
            #Write-Host "Stochastic Oscillator: $stochasticOscillator"
            
            # append new row with stochastic oscillator to dest csv file
            $_ += ", $stochasticOscillator"
            $_ | Out-File -Append -FilePath $destCSVFile
        }
    }
    catch {
        outputException `
            -customMessage "ERR: calcStochasticOscillator - Error with $srcCSVFile, $destCSVFile and $bins" `
            -exceptionMessage $_.Exception.Message `
            -exceptionStackTrace $_.Exception.StackTrace
    }

}
