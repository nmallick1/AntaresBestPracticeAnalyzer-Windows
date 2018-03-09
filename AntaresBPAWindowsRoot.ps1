param(
[parameter(Mandatory=$true)]
[string]
$subscriptionId
) #Must be the first statement in the script




Function DisplayMessage
{
    Param(
    [String]
    $Message,

    [parameter(Mandatory=$true)]
    [ValidateSet("Error","Warning","Info")]
    $Level
    )
    Process
    {
        if($Level -eq "Info"){
            Write-Host -BackgroundColor White -ForegroundColor Black $Message `n
            }
        if($Level -eq "Warning"){
        Write-Host -BackgroundColor Yellow -ForegroundColor Black $Message `n
        }
        if($Level -eq "Error"){
        Write-Host -BackgroundColor Red -ForegroundColor White $Message `n
        }
    }
}


#region Make sure to check for the presence of ArmClient here. If not, then install using choco install
    $chocoInstalled = Test-Path -Path "$env:ProgramData\Chocolatey"
    if (-not $chocoInstalled)
    {
        DisplayMessage -Message "Installing Chocolatey" -Level Info
        Set-ExecutionPolicy Bypass -Scope Process -Force; iex ((New-Object System.Net.WebClient).DownloadString('https://chocolatey.org/install.ps1'))
    }

    $armClientInstalled = Test-Path -Path "$env:ProgramData\chocolatey\lib\ARMClient"

    if (-not $armClientInstalled)
    {
        DisplayMessage -Message "Installing ARMClient" -Level Info
        choco install armclient
    }

    <#
    NOTE: Please inspect all the powershell scripts prior to running any of these scripts to ensure safety.
    This is a community driven script library and uses your credentials to access resources on Azure and will have all the access to your Azure resources that you have.
    All of these scripts download and execute PowerShell scripts contributed by the community.
    We know it's safe, but you should verify the security and contents of any script from the internet you are not familiar with.
    #>

#endregion


$scriptPath = Split-Path -parent $MyInvocation.MyCommand.Definition


$outputDirectory = $scriptPath  + "\Output"
$sitesDirectory = $outputDirectory + "\" + $subscriptionId + "\Sites"
$aspsDirectory = $outputDirectory + "\" + $subscriptionId + "\ASPs"

$detectorsDirectory = $scriptPath  + "\Detectors"
$sitesDetectorsDirectory = $detectorsDirectory + "\Sites"
$aspsDetectorsDirectory = $detectorsDirectory + "\ASPs"






#Do any work only if we are able to login into Azure. Ask to login only if the cached login user does not have token for the target subscription else it works as a single sign on


if(@(ARMClient.exe listcache| Where-Object {$_.Contains($subscriptionId)}).Count -lt 1){
    ARMClient.exe login >$null
}

if(@(ARMClient.exe listcache | Where-Object {$_.Contains($subscriptionId)}).Count -lt 1){
    #Either the login attempt failed or this user does not have access to this subscriptionId. Stop the script
    DisplayMessage -Message ("Login Failed or You do not have access to subscription : " + $subscriptionId) -Level Error
    return
}
else
{
    DisplayMessage -Message ("User Logged in") -Level Info
}


#region Create Output Folder Structure
    if(Test-Path -Path $outputDirectory\$subscriptionId)
    {
        Remove-Item -Path $outputDirectory\$subscriptionId -Recurse -Force
    }


    #Create a folder to hold information of WebApps and ignore the output of this command
    New-Item -ItemType Directory -Path $sitesDirectory -Force >$null

    #Create a folder to hold the metrics for ASPs and ignore the output of this command
    New-Item -ItemType Directory -Path $aspsDirectory -Force  > $null
#endregion



#region Fetch Web Site Info and PublishSettings for each Site
    $sitesArr = @()
    DisplayMessage -Message "Fetching Sites information..." -Level Info

    $sitesJSON = ARMClient.exe get /subscriptions/$subscriptionId/providers/Microsoft.Web/sites/?api-version=2016-08-01
    DisplayMessage -Message "Saving Sites information..." -Level Info


    #Convert the string representation of JSON into PowerShell objects for easy manipulation
    $sites = $sitesJSON | ConvertFrom-Json


    $sites.value.GetEnumerator() | foreach {
        #Kept here for debugging purposes. Uncomment the next line to examine the properties of a given entry
        #$currSite = $_



        If(($_.kind -eq "app") -and ($_.properties.sku -ne "Free")){
        #Process only Windows WebApps and make sure that they are not Free. There are a bunch of settings that are not applicable to the Free tier and hence not all detectors can work for them
        #Linux webapps have kind = linux and Function Apps have kind = functionapp
            # -------------------------------------------

            $siteObj = New-Object System.Object
            $siteObj | Add-Member -MemberType NoteProperty -Name Subscription -Value $_.id.Split('/')[2]
            $siteObj | Add-Member -MemberType NoteProperty -Name ResourceGroup -Value $_.id.Split('/')[4]
            $siteObj | Add-Member -MemberType NoteProperty -Name SiteName -Value $_.id.Split('/')[8]
            #$_.properties.serverFarmId.Split('/')[8] will have the server farm name
            $siteObj | Add-Member -MemberType NoteProperty -Name ServerFarm -Value $_.properties.serverFarmId

            #Initialize this member. It will later hold all the detectors that were fired against the site
            $siteObj | Add-Member -MemberType NoteProperty -Name DetectorsTrigerred -Value @()

            #Keeping the sites in memory for later retrieval. Can fetch it using the following syntax
            #$sitesArr | Where-Object SiteName -EQ XXXXX
            $sitesArr+= $siteObj


            #$currSiteOutputName = $_.id.Split('/')[2] + "_" + $_.id.Split('/')[4] + "_" + $_.id.Split('/')[8]
            $currSiteOutputDirName = $siteObj.Subscription + "_" + $siteObj.ResourceGroup + "_" +  $siteObj.SiteName


            #File name format is SiteName.json


            DisplayMessage -Message ("Info for " + $_.name + " in file " +  $siteObj.SiteName + ".json") -Level Info

            #Create a placeholder file
            New-Item -ItemType File -Path ($sitesDirectory + "\" + $currSiteOutputDirName + "\" + $siteObj.SiteName + ".json") -Force >$null

            #Write the properties of this website into its corresponding file
            $_.properties| ConvertTo-Json | Out-File -FilePath ($sitesDirectory + "\" + $currSiteOutputDirName + "\" + $siteObj.SiteName + ".json") -Append  -Force


            #region GetPublishSettings for each of the webapps for use by detectors later
                $publishSettingsURL = "/subscriptions/" + $siteObj.Subscription + "/resourcegroups/" + $siteObj.ResourceGroup + "/providers/Microsoft.Web/sites/" + $siteObj.SiteName + "/publishxml?api-version=2016-03-01"
                $publishSettings = ARMClient.exe POST $publishSettingsURL
                New-Item -ItemType File -Path ($sitesDirectory + "\" + $currSiteOutputDirName + "\" + $siteObj.SiteName + ".PublishSettings") -Force >$null
                $publishSettings | Out-File -FilePath ($sitesDirectory + "\" + $currSiteOutputDirName + "\" + $siteObj.SiteName + ".PublishSettings") -Append  -Force
            #endregion


            #-------------------------------------------
        }
    }
#endregion



#region Fetch ASP (App Service Plan) Info
    $aspArr = @()
    DisplayMessage -Message "Fetching App Service Plan information..." -Level Info
    $aspsJSON= ARMClient.exe get /subscriptions/$subscriptionId/providers/Microsoft.Web/serverfarms/?api-version=2016-09-01
    DisplayMessage -Message "Saving App Service Plan information..." -Level Info

    $asps = $aspsJSON | ConvertFrom-Json
    $asps.value.GetEnumerator() | foreach{
        #Kept here for debugging purposes. Uncomment the next line to examine the properties of a given entry
        $currASP = $_

        If(($_.sku.tier -ne "Free") -and ($_.sku.tier -ne "Dynamic") -and ($_.kind -eq "app")) {
        #Process only those app service plans that are not Free and do not belong to consumption plan for function apps
            $aspObj = New-Object System.Object
            $aspObj | Add-Member -MemberType NoteProperty -Name Subscription -Value $_.id.Split('/')[2]
            $aspObj | Add-Member -MemberType NoteProperty -Name ResourceGroup -Value $_.id.Split('/')[4]
            $aspObj | Add-Member -MemberType NoteProperty -Name ServerFarmName -Value $_.name
            #Maintaining ServerFarmNameId is so that, if required, you can later look up sites that belong to this Server Farm and if a site exists in this Server Farm
            $aspObj | Add-Member -MemberType NoteProperty -Name ServerFarmNameId -Value $_.id

            #Initialize this member. It will later hold all the detectors that were fired against the ASP
            $aspObj | Add-Member -MemberType NoteProperty -Name DetectorsTrigerred -Value @()

            $aspArr+= $aspObj
            $currASPOutputDirName = $aspObj.Subscription + "_" + $aspObj.ResourceGroup + "_" +  $aspObj.ServerFarmName

            #File name format is SUB_RG_ASPName.json

            DisplayMessage -Message ("Info for ASP " + $_.name + " in file " + $aspObj.ServerFarmName + ".json") -Level Info

            #Create a placeholder file
            New-Item -ItemType File -Path ($aspsDirectory + "\" + $currASPOutputDirName + "\" + $aspObj.ServerFarmName + ".json") -Force >$null

            #Write the properties of this website into its corresponding file
            $_ | ConvertTo-Json | Out-File -FilePath ($aspsDirectory + "\" + $currASPOutputDirName + "\" + $aspObj.ServerFarmName + ".json") -Append  -Force

        }
    }

    #Do not process ASP's that are Free / Dynamic

#endregion



#Now that we have settings for all the non-free webapps and app service plans, it is time to start running detectors against them in parallel to fetch metrics for ASP's.
#Once all the metrics for ASP's are available, we can start detectors against them


#region Execute detectors for Sites and Asp's



$maxConcurrency = 10
$maxSitesConcurrency = 8
$maxASPConcurrency = $maxConcurrency - $maxSitesConcurrency

$timesToInvokeEachSitesDectector = @(Get-ChildItem -Path $sitesDirectory).count
$timesToInvokeEachASPDectector = @(Get-ChildItem -Path $aspsDirectory).count
$continueExecutingSiteDetectors = $true
$continueExecutingASPDetectors = $true
$timeToWaitBetweenEachExecutionAttemptInMs = 500

$executionTimeOutPerSiteDetectorInMs = [timespan]::FromMilliseconds(360000) #A Site detector is allowed to run for 6 minutes max and then killed
$executionTimeOutPerASPDetectorInMs =  [timespan]::FromMilliseconds(600000) #An ASP detector is allowed to run for 10 minutes max and then killed

#region Initialize a list of all the Detectors
    #region Initialize a list of all the Site Detectors
        $siteDetectorsArr = @()
        Get-ChildItem -Path $sitesDetectorsDirectory -Recurse -Filter "*.ps1" | foreach {
            if($_.Name -ne "PlaceHolderDetector.ps1")
            {
                $currDetector = New-Object System.Object
                $currDetector | Add-Member -MemberType NoteProperty -Name Name -Value $_.Name.Replace($_.Extension, '')
                $currDetector | Add-Member -MemberType NoteProperty -Name FullPath -Value $_.FullName
                $currDetector | Add-Member -MemberType NoteProperty -Name TimesInvoked -Value 0
                $siteDetectorsArr+= $currDetector
            }
        }
    #endregion
    #region Initialize a list of all the ASP Detectors
        $aspDetectorsArr = @()
        Get-ChildItem -Path $aspsDetectorsDirectory -Recurse -Filter "*.ps1" | foreach {
            if($_.Name -ne "PlaceHolderDetector.ps1")
            {
                $currDetector = New-Object System.Object
                $currDetector | Add-Member -MemberType NoteProperty -Name Name -Value $_.Name.Replace($_.Extension, '')
                $currDetector | Add-Member -MemberType NoteProperty -Name FullPath -Value $_.FullName
                $currDetector | Add-Member -MemberType NoteProperty -Name TimesInvoked -Value 0
                $aspDetectorsArr += $currDetector
            }
        }
    #endregion

#endregion

while($continueExecutingSiteDetectors -or $continueExecutingASPDetectors ){

    if($continueExecutingSiteDetectors)
    {
        #Decided to run same detector against multiple sites so as to minimize the impact of running multiple operations against any given site
        Remove-Job -State Completed
        $currSitesJobs =  @(Get-Job | Where-Object {$_.Name.Contains("_Site_")}).count
        if ($currSitesJobs -lt $maxSitesConcurrency){
            #Attempt to execute a Job only if there is scope for it given the current concurrency

            $siteDetectorsArr | Where-Object TimesInvoked -lt $timesToInvokeEachSitesDectector | foreach {
                #This loop will have every detector that is yet to be invoked at least once for some site
                $currDetector = $_

                Remove-Job -State Completed
                $currSitesJobs =  @(Get-Job | Where-Object {$_.Name.Contains("_Site_")}).count

                $sitesArr | Where-Object DetectorsTrigerred -NotContains $currDetector.Name | foreach{
                    #This loop will have every site against which this detector was not invoked

                    $jobName = $currDetector.Name + "_Site_" + $_.SiteName
                    $jobCmdLine = $currDetector.FullPath
                    $jobArg = @( ($sitesDirectory + "\" + $_.Subscription + "_" + $_.ResourceGroup  + "_" +  $_.SiteName), $currDetector.Name )

                    Remove-Job -State Completed
                    $currSitesJobs =  @(Get-Job | Where-Object {$_.Name.Contains("_Site_")}).count
                    if ($currSitesJobs -lt $maxSitesConcurrency){
                        Start-Job -Name $jobName -FilePath $jobCmdLine -ArgumentList $jobArg
                        $_.DetectorsTrigerred+= $currDetector.Name
                        $currDetector.TimesInvoked++
                    }
                } #end of $sitesArr | Where-Object
            } #end of $siteDetectorsArr | Where-Object

            #If there are still any Site Detectors left that are yet to be invoked for Site, signal the next iteration to continue
            $continueExecutingSiteDetectors = @($siteDetectorsArr | Where-Object TimesInvoked -lt $timesToInvokeEachSitesDectector).Count -gt 0

        }
    }#end of Site detectors execution

    if($continueExecutingASPDetectors)
    {
        Remove-Job -State Completed
        $currASPJobs =  @(Get-Job | Where-Object {$_.Name.Contains("_ASP_")}).count
        $continueExecutingASPDetectors = $false

        <#
        YET TO WRITE THE LOGIC TO PULL ASP METRICS AND THEN RUN ASP DETECTORS
        WILL PULL ASP METRICS IN THIS PARENT SCRIPT WITHOUT A TIMEOUT AS A JOB AND WILL ALSO WRITE AN SAMPLE ASP DETECTOR IN A SEPERATE PS1 FILE AS PER THE FORMAT
        #>

    }

    #region Impose Detector Timeouts
        #Timeout Site Jobs that haven't been cleaned up yet and have hit the timeout limit
        Get-Job | Where-Object {$_.Name.Contains("_Site_") -and (($now - $_.PSBeginTime)-gt $executionTimeOutPerSiteDetectorInMs) } | Stop-Job

        #Timeout ASP Jobs that haven't been cleaned up yet and have hit the timeout limit
        Get-Job | Where-Object {$_.Name.Contains("_ASP_") -and (($now - $_.PSBeginTime)-gt $executionTimeOutPerASPDetectorInMs) } | Stop-Job

    #endregion  Impose Detector Timeouts


    Start-Sleep -Milliseconds $timeToWaitBetweenEachExecutionAttemptInMs

} #end of while($continueExecutingSiteDetectors -or $continueExecutingASPDetectors )
Remove-Job -State Completed

DisplayMessage -Message "Waiting for Jobs to finish and run cleanup..." -Level Info

$continueToWaitForCleanup = @(Get-Job | Where-Object {$_.Name.Contains("_Site_") -or $_.Name.Contains("_ASP_")}).count -gt 0

$maxSecondsToWaitForCleanup = 600 #This is 10 minutes. This is a long enough time to allow all the detectors to run after the last of them have been started
while($continueToWaitForCleanup -and ($maxSecondsToWaitForCleanup -gt 0))
{
    #region Impose Detector Timeouts
        #Timeout Site Jobs that haven't been cleaned up yet and have hit the timeout limit
        Get-Job | Where-Object {$_.Name.Contains("_Site_") -and (($now - $_.PSBeginTime)-gt $executionTimeOutPerSiteDetectorInMs) } | Stop-Job

        #Timeout ASP Jobs that haven't been cleaned up yet and have hit the timeout limit
        Get-Job | Where-Object {$_.Name.Contains("_ASP_") -and (($now - $_.PSBeginTime)-gt $executionTimeOutPerASPDetectorInMs) } | Stop-Job

    #endregion  Impose Detector Timeouts

    Remove-Job -State Completed
    $maxSecondsToWaitForCleanup = $maxSecondsToWaitForCleanup - 1
    DisplayMessage -Message ("Will wait a max " + $maxSecondsToWaitForCleanup + " seconds for Jobs to finish and run cleanup...") -Level Info
    Start-Sleep -Seconds 1
    Remove-Job -State Completed
    $continueToWaitForCleanup = @(Get-Job | Where-Object {$_.Name.Contains("_Site_") -or $_.Name.Contains("_ASP_")}).count -gt 0
}

#Just in case any detector has not completed even after waiting for $maxSecondsToWaitForCleanup time, terminate those detector jobs
Get-Job | Where-Object {$_.Name.Contains("_Site_") -or $_.Name.Contains("_ASP_") } | Stop-Job
Get-Job | Where-Object {$_.Name.Contains("_Site_") -or $_.Name.Contains("_ASP_") } | Remove-Job




#endregion Execute detectors for Sites and Asp's


#region Generate Output Report
DisplayMessage -Message ("Jobs complete. Generating output file.") -Level Info
#endregion Generate Output Report

return
