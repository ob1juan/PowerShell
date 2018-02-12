<#
    .TITLE
    Update-Users.ps1
    
    .SYNOPSIS
    Updates Active Directory with employee information from source file. Source file would be created from HR system output.
    
    Juan Rhodes
    obijuan@obijuan.com

    THIS CODE IS MADE AVAILABLE AS IS, WITHOUT WARRANTY OF ANY KIND. THE ENTIRE
    RISK OF THE USE OR THE RESULTS FROM THE USE OF THIS CODE REMAINS WITH THE USER.
    
    Version 1.0, February 6, 2018

    .DESCRIPTION
    This script will read from source file to update Active Directory information. The script will report output into an in-path
    log directory, and send an email with status to the email address specified. The script can be run as a schedulded task to
    automate the process. 

    .EXAMPLE
    .\Update-Users.ps1

    -Modify the options noted as appropriate for the run environment.

    .OUTPUT
    -.\Log
    -  <DATE>-FoundUsers.csv : Contains report of users found in Active Directory and columns for each attribute updated
    -  <DATE>-MissingUsers.csv : Contains report of users not found in Active Directory
    
    .GITHUB
    https://github.com/ob1juan

    .NOTES
    
    Revision History
    ------------------------------------------------------------------------------------
    1.0 Initial community release

#>

Import-Module ActiveDirectory

$path = ".\Log"
If(!(test-path $path)){
    New-Item -ItemType Directory -Force -Path $path
}

$global:logDate = (Get-Date).Year.ToString() + "-" + (Get-Date).Month.ToString() + "-" + (Get-Date).Day.ToString() + "-" + (Get-Date).Hour.ToString() + "-" + (Get-Date).Minute.ToString() + "-" + (Get-Date).Second.ToString()
$tSrcriptPath = ".\Log\" + $global:logDate + "-Update-Users.txt"
Start-Transcript -Path $tSrcriptPath -NoClobber

try{
    $usersSource = Import-Csv ".\Input\AD & Fusion Match Sync Data.csv" -ErrorAction Stop
    #$usersSource = Import-Csv ".\users.csv" -ErrorAction Stop

}catch{
    Write-Host -ForegroundColor Red "Input File Missing"
    exit
}

### Modfiy Options ##

$global:smtpServer = "smtp-server"
$global:emailFrom = "sender"
$global:emailTo = "recipient"
$emailReports = $false # set to true to send an email with the reports to recipients specified above

### End Modify ######

$global:adDomain = $null
[String]$global:gc = $null
[String]$global:dc = $null

function getDomain{
    $global:adDomain = Get-ADDomain
    getGC
}

function getGC{
    $global:gc = (Get-ADDomainController -Discover -Service GlobalCatalog).HostName
    Write-Host "Using Global Catalog Server:" $global:gc
}

function getDCfromDN($dn){
    $a= $dn.IndexOf("DC=")
    $searchBase = $dn.Substring($a)
    $userDomain = (get-adforest).domains|%{Get-ADDomain $_}|where {$_.Distinguishedname -eq $searchBase}
    $userDC = getDC $userDomain.DNSRoot
    return $userDC
}

function getDC($domain){
    [String]$dc = (Get-ADDomainController -Discover -DomainName $domain).HostName
    return $dc
}

getDomain
$i = 1

$usersCount = $usersSource.count

$global:foundUsers = New-Object System.Collections.ArrayList
$global:missingUsers = New-Object System.Collections.ArrayList

    function setADUser($adUser, $sourceObj){
        try{
            
            $adPropTable = New-Object HashTable
            $adPropTable.Add("title", $sourceUser.title)
            $adPropTable.Add("division", $sourceUser.division)
            $adPropTable.Add("department", $sourceUser.department)

            $replace = @{}
            $add = @{}
            
            foreach( $adProp in $adPropTable.Keys ){
                $val = $adPropTable.$adProp
                write-host "`t Source prop: $adProp val: $val"
                write-host "`t User Prop:" $adUser.$adProp
                if(($adUser.$adProp) -and ($adUser.$adProp -ne $val) -and ($val)){
                    $replace.Add( $adProp, $val )
                    Write-Host "`t Replacing :" $adProp ":" $val
                }elseif (($val) -and (!$adUser.$adProp)) {
                    $add.Add( $adProp, $val )
                    Write-Host "`t Adding :" $adProp ":" $val
                }
            }

            $adUserCN = $adUser.CanonicalName
            $adUserDomain = $adUserCN.split("/")[0]
            $adUserDC = getDC $adUserDomain

            $setADUserParams = @{
                Identity = $adUser.distinguishedName
                Server = $adUserDC
                ErrorAction = "Stop"
            }

            if ($replace.Count -gt 0){
                $setADUserParams.Add("Replace", $replace)
            }

            if ($add.Count -gt 0){
                $setADUserParams.Add("Add", $add)
            }

            if (($add.Count -gt 0) -or ($add.Count -gt 0)){
                Write-Host "`t Using domain controller:" $adUserDC
                Set-ADUser @setADUserParams -WhatIf
                Write-Host -ForegroundColor Green "`t Updated User.`r`n"
            }else{
                Write-Host -ForegroundColor Gray "`t User unchanged. `r`n"
            }
            
        }catch{
            Write-Host -ForegroundColor Red "`t Could not update user." $_.Exception.Message "`r`n"
        }    
    }

    function getADUser($sourceUser){
        $distinguishedName = $sourceUser.distinguishedName
        $userDC = getDCfromDN $distinguishedName

        Write-Host "Finding $distinguishedName"

        try{
            $adUser = Get-ADUser -Identity $distinguishedName -Properties * -Server $userDC -ErrorAction Stop
            if ($adUser){

                $global:foundUsers.Add($sourceUser)
                setADUser $adUser $sourceUser
           
            }else{
                Write-Host -ForegroundColor Red "`t Could not find AD user." $_.Exception.Message "`r`n"
                $global:missingUsers.Add($sourceUser) 
            }

        }catch{
            Write-Host -ForegroundColor Red "`t Could not find AD user." $_.Exception.Message "`r`n"
            $global:missingUsers.Add($sourceUser)   
        }
    }

### Function to create .csv files ###
function createReport (){
    $foundUsersLogFile = ".\Log\" + $global:logDate + "-FoundUsers.csv"
    $foundUsers |Export-Csv .\$foundUsersLogFile -NoTypeInformation

    $missingUsersLogFile = ".\Log\" + $global:logDate + "-MissingUsers.csv"
    $missingUsers |Export-Csv .\$missingUsersLogFile -NoTypeInformation
}


### Function to send email report ###
function sendEmail(){
    $Userresultmsg = ""
    $ErrorMsg = ""

    $smtpbody = "<!DOCTYPE html PUBLIC `"-//W3C//DTD XHTML 1.0 Strict//EN`" `"http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd`">"
    $smtpbody += "<html xmlns=`"http://www.w3.org/1999/xhtml`"><head>"
    $smtpbody += "<title>Scheduled Task: Update Employees</title></head><body>"
    $smtpbody += "<br> The following users were missing in AD:<br>"
    $smtpbody += "<table border=1><tr><td>User</td><td>Status</td></tr>"
       
    foreach ($missingUser in $global:missingUsers){

        $smtpbody += "<td>" + $missingUser.displayName + "</td><td>" + $($missingUser.status) + "</td></tr>"
    }

    $smtpbody += "</table><br><br>"

    $smtpbody += $Global:Userresultmsg + "<br><br></body></html>"

    Write-Output "Sending email to $emailTo"

    try{
        Send-MailMessage -UseSsl -From $emailFrom -To $emailTo -Subject "Scheduled Task: Disable Office 365 Accounts:" -SmtpServer $smtpServer -BodyAsHtml -Body $smtpbody -ErrorAction Stop
        Write-Output "Email Sent"
    }
    catch{
        Write-Host -ForegroundColor Red "Could send email :Exception Message: " $($_.Exception.Message)
    }
}


### Starting Loop Through Source File ###
Write-Host "$usersCount users in source."

foreach ($sourceUser in $usersSource){

    $distinguishedName = $sourceUser.DistinguishedName
    
    $division = $sourceUser."Division (F)"
    $title = $sourceUser."Job Title (F)"
    $department = $sourceUser."Department (F)"
     
    #$division = $sourceUser.division
    #$title = $sourceUser.title
    #$department = $sourceUser.department
      
    $userobj = New-Object PSObject
	$userobj | Add-Member NoteProperty "distinguishedName" $distinguishedName
	$userobj | Add-Member NoteProperty "title" $title
    $userobj | Add-Member NoteProperty "division" $division
    $userobj | Add-Member NoteProperty "department" $department
        
    getADUser($userObj)
    
    write-host
    
    $i++
    
}

createReport

if ($emailReports){
    sendEmail
}

Write-Host "Done. " $global:foundUsers.Count " found. " $global:missingUsers.count " not found. "
Stop-Transcript