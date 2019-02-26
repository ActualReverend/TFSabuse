<#PSScriptInfo

.VERSION 1.0

.GUID 1278246e-3486-4f83-9b2a-8efa60d952dd

.AUTHOR Bryan.Loveless@gmail.com

.COMPANYNAME 

.COPYRIGHT 2018

.TAGS Web TFS

.LICENSEURI 

.PROJECTURI 

.ICONURI 

.EXTERNALMODULEDEPENDENCIES 

.REQUIREDSCRIPTS 

.EXTERNALSCRIPTDEPENDENCIES 

.RELEASENOTES


.PRIVATEDATA 

#>

<# 

.DESCRIPTION 
 Modifies the XML on a site to turn on debugging.  TFS can send "$(SiteName)" as a variable. Also sends a boolean for "EnableLogging".

example: 
.\Modify-DebugLogging.ps1 -SiteName blahgooglecom -EnableLogging $true

#> 



param (
	[Parameter(Mandatory=$True,Position=1)]
	[string[]]$SiteName = $null,
	[Parameter(Mandatory=$True,Position=2)]
	[boolean[]]$EnableLogging = $true
)


#for testing:
#$SiteName = "blahgooglecom"


$path = ('C:\inetpub\' + $SiteName+ '\logs')

if (!(test-path $path))
			    {
					    New-Item -ItemType Directory -Force -Path $path -ea inquire
			    }


#allow app pool user to write to that folder

# ref: https://dejanstojanovic.net/powershell/2018/january/setting-permissions-for-aspnet-application-on-iis-with-powershell/
$User = "IIS AppPool\" + $SiteName  
$Acl = Get-Acl $Path  
$Ar = New-Object  system.security.accesscontrol.filesystemaccessrule($User,"Modify", "ContainerInherit,ObjectInherit", "None", "Allow")  
$Acl.SetAccessRule($Ar)  
Set-Acl $Path $Acl  


# allow "weblogviewers" local group to read this new directory
$LocalGroup = "WebLogViewers"
If(!(Get-LocalGroup -Name $LocalGroup)){
	New-LocalGroup -Name $LocalGroup -Description "Allows Developers to View website logs"
}
$Acl = Get-Acl $Path  
$Ar = New-Object  system.security.accesscontrol.filesystemaccessrule($LocalGroup,"ReadAndExecute", "ContainerInherit,ObjectInherit", "None", "Allow")  
$Acl.SetAccessRule($Ar)  
Set-Acl $Path $Acl 



#Change the webconfig to write to the log directory
#using xml
$xmllocation = ('C:\inetpub\' + $SiteName+ '\web.config')

$xml = [xml] (Get-Content $xmllocation)

if ($EnableLogging -eq $False) {
    write-host "Setting to False now"
    $xml.configuration.'system.webServer'.aspNetCore.stdoutLogEnabled = 'False'
    $xml.Save($xmllocation)
}

elseif ($EnableLogging -eq $True) {
    write-host "Setting to True now"
    $xml.configuration.'system.webServer'.aspNetCore.stdoutLogEnabled = 'True'
    $xml.Save($xmllocation)
}

# set scheduled task to remove it later, 30 min 
#ref: https://docs.microsoft.com/en-us/powershell/module/scheduledtasks/new-scheduledtask?view=win10-ps
#https://blogs.technet.microsoft.com/heyscriptingguy/2015/01/13/use-powershell-to-create-scheduled-tasks/
$scriptpath = "c:\scripts\Modify-DebugLogging.ps1 -Sitename $Sitename -EnableLogging `$False"
$futuretime = (get-date).AddMinutes(30)
$futuretimeText = ($futuretime.hour).tostring() + '-' + ($futuretime.Minute).tostring()  # register later does NOT like ":", so made it "-"
$Action = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument "-executionpolicy bypass -noprofile -file $scriptPath"
$Trigger = New-ScheduledTaskTrigger -Once -At $futuretime
$Principal = New-ScheduledTaskPrincipal -UserID "NT AUTHORITY\SYSTEM" -RunLevel Highest -LogonType ServiceAccount 
$SettingsSet = New-ScheduledTaskSettingsSet # -DeleteExpiredTaskAfter (New-TimeSpan -Hours 8) -ExecutionTimeLimit (New-Timespan -minutes 5) -Priority 7
$TaskObject = New-ScheduledTask -Action $Action  -Trigger $Trigger -Settings $SettingsSet -Principal $Principal
$random = (get-random -Maximum 99)
Register-ScheduledTask "ModifyWebfolderacess for site $SiteName until $futuretimeText for $userid - $random" -InputObject $TaskObject 

