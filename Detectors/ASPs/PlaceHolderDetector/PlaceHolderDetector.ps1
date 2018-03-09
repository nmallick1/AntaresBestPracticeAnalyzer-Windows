param([string]$resourceToProcess, [string]$currDetectorName) #Must be the first statement in the script

<#
1. Make sure there are no spaces in the Detector script name. Place your Detector script within a folder with the same name as your Detector script. You can then put this folder inside the Detectors\ASPs directory
For e.g.. The sample SlotsDetector.ps1 is a Sites Detector and its script is placed inside \Detectors\Sites\SlotsDetector\SlotsDetector.ps1

2. No individual Detector should take more than a few minutes to complete. It runs a risk of being terminated if it runs for a long time
Timeout for a Site detector is 6 minutes and for an ASP detector is 10 minutes

3. As a rule of thumb, if you are downloading any file that you need for your detector to function, download it in the directory respresnted by $resourceToProcess instead of the directory in which your Detector resides.
You may choose to clean up / leave the downloaded data as is. Just in case any other detectory needs it, it will already have it there.
Simillarly, if you need a file downloaded / some data, check for its presence. Chances are, some other detector might have already done the work for you


4. $resourceToProcess will have input in the following format
    C:\Projects\AntaresBestPracticeAnalyzer-Windows\Output\da511dea-6e00-4728-93ff-6302ad7fe284\ASPs\da511dea-6e00-4728-93ff-6302ad7fe284_nmallickWebAppRG_nmallick-S3-ASP

5. Once done with the detector logic, create a file with the following naming convention and place it in the same folder as $resourceToProcess
    DetectorName.out.

    For e.g. If the detector's name is SlotsDetector, the output file generated by this detector should be SlotsDetector.out and should be placed at $resourceToProcess +"\SlotsDetector.out".
    $detectorOutputFile valiable already creates the complete file path for you.

    The output file should contain and output in the following JSON format

    {
    "SubscriptionId": "This should be the Subscription ID under which the current site resides",
    "ResourceGroupName": "This should be the resource grop name under which the current site resides",
    "ResourceName": "This should be either the name of the webapp or ASP that the detector is currently processing",
    "Kind": "Make sure value is ASPDetector",
    "DetectorName": "SlotsDetector",
    "Author": "Feel free to addd your name and/or email address or simply state Anonymous"
    "Description": "In short, state which best practice does your detector checks against",
    "Result":{
        "Value": "Make sure value is one out of Pass | Fail | Warning",
        "Details": "Any string decribing what is the conclusion of your detector",
        "Recommendation": "What is your recommendation for this site and why",
        "AdditionalInfo":"Anything else that you want to point out goes here"
        }
    }

6. Add a small description of what your detector checks for / which best practice is it trying to look for in the corresponding ReadMe.txt. It will help people understand the intent of this detector.

7. There is a return statement in PlaceHolderDetector.ps1. Remove / Comment it before working on your detector. It is placed to ensure that the PlaceHolderDetecor does not run any logic if trigerred

8. The order in which Detectors will be invoked is not guaranteed, however they are certain to be invoked ONLY once per Site / ASP.
#>


#region Delete this section
    #Comment out / Remove the following return statement when you write your detector.
    #This return is placed just to make sure that the PlaceHolderDetecor does not end up creating an output file
    #----------------------------------------
        return
    #----------------------------------------
#endregion  Delete this section


#region Do not change anything in this section
    $detectorOutputFile = $resourceToProcess + "\" + $currDetectorName  + ".out"

    if(Test-Path -Path $detectorOutputFile){
        #Output for this detector already exists. Must have been trigerred due to some bug / error. Do not run the detector logic again
        return
    }

    $temp = $resourceToProcess.Split('\')[$resourceToProcess.Split('\').Length-1]

    $subscriptionId = $temp.Split('_')[0]
    $resourceGroup = $temp.Split('_')[1]
    $resourceName = $temp.Split('_')[2]

    #The complete path of the JSON file that contains settings for this resource is $resourceToProcess + "\" + $settingsFileName
    $settingsFileName = $resourceName + ".json"

    #Initialize
    $adheringToBestPractice = $true
#endregion Do not change anything in this section

#region Code for your detector goes here
    <#
    ........................................
    ........................................
    ........................................
    LOGIC FOR YOUR DETECTOR GOES HERE.

    REST ALL OF THE PRE-EXISTING CODE IN THIS SCRIPT IS TO MAKE SURE THE SAME PATTEN IS FOLLOWED ACROSS DETECTORS
    ........................................
    ........................................
    ........................................
    #>

#endregion  Code for your detector goes here

#region Generate output for the detector
    #region Modify the text in variables as appropriate
        If($adheringToBestPractice){
            #Enter this block if you logic found that the best practice you are checking for is already being adhered to
            $detectorResult = @{
                'Value'='Pass';
                'Details'=('Any SUCCESS message you want to emit');
                'Recommendation'='What is your recommendation for this resource and why';
                'AdditionalInfo'='Anything else that you want to point out goes here'
                }
        }
        else
        {
            #Enter this block if you logic found that the best practice you are checking for is already being adhered to
            $detectorResult = @{
                'Value'='Fail';
                'Details'="Any FAILURE message you want to emit";
                'Recommendation'='What is your recommendation for this resource and why';
                'AdditionalInfo'='Anything else that you want to point out goes here. Can even include a powershell script / link to blog / instructions in order to guide a user to have this site follow best practice.'
                }
        }




        #region Generating output for the detector
        $outputObj = New-Object System.Object
        $outputObj  | Add-Member -MemberType NoteProperty -Name SubscriptionId -Value $subscriptionId
        $outputObj  | Add-Member -MemberType NoteProperty -Name ResourceGroupName -Value $resourceGroup
        $outputObj  | Add-Member -MemberType NoteProperty -Name ResourceName -Value $resourceName
        $outputObj  | Add-Member -MemberType NoteProperty -Name Kind -Value "ASPDetector"
        $outputObj  | Add-Member -MemberType NoteProperty -Name DetectorName -Value $currDetectorName
        $outputObj  | Add-Member -MemberType NoteProperty -Name Author -Value "Anonymous"
        $outputObj  | Add-Member -MemberType NoteProperty -Name Description -Value "In short, state which best practice does your detector checks against."
        $outputObj  | Add-Member -MemberType NoteProperty -Name Result -Value $detectorResult



    #endregion  Modify the text in variables as appropriate

    #region Write output to .out file
        #Create a placeholder file
        New-Item -ItemType File -Path $detectorOutputFile -Force >$null

        #Write the properties of this website into its corresponding file
        $outputObj | ConvertTo-Json | Out-File -FilePath $detectorOutputFile -Append  -Force
    #endregion Write output to .out file
#endregion  Generate output for the detector