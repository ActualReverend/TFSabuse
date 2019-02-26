<#PSScriptInfo

.VERSION 1.0

.GUID 97091199-5691-4b03-b3b3-bbf184f12cf9

.AUTHOR Bryan.Loveless@gmail.com

.COMPANYNAME 

.COPYRIGHT 2019

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
 Changes the web folder access to allow a local group to be able to list and read the contents of the directory.
 If run with no userid parameter, it will clear out the local group.
 TFS can pass this variable, if you use the build varialbe "UserID" :  $(Build.RequestedForEmail)
 Also use TFS variables "SiteName" and "Webenvironment"

 NOTE:  "-Enableaccess" is a string value, not a boolean, becuase of a bug in scheduled tasks.  Ref: https://github.com/Microsoft/azure-pipelines-tasks/issues/836

example: 
.\Modify-WebfolderAccess.ps1 -SiteName NameOfSiteInIIS -EnableAccess yes -Userid "bryan.loveless@gmail.com" -WebEnvironment "dev"

#> 

param (
	[Parameter(Mandatory=$True,Position=1,
	 	HelpMessage="FQDN of website with NO periods:  Like BlahGoogleCom")]
	[string]$SiteName,

	[Parameter(Mandatory=$False,Position=2)]
	[string][ValidateSet("Yes", "No")]$EnableAccess = "No",

	[Parameter(Mandatory=$False,Position=3)]
	[string]$UserID = "nobody",

	[Parameter(Mandatory=$false,Position=4,
		HelpMessage="Valid entries are dev, test, prod, qa")]
	[string][ValidateSet("dev", "test", "prod", "qa")]$WebEnvironment,

    [Parameter(Mandatory=$False,Position=5)]
	[string]$Taskname

)
<#
 temporary variables for testing:

 $SiteName = "lahGoogleCom"
 $enableaccess = "Yes"
 $webenvironment = "dev"
 $userid = "bryan.loveless@gmail.com"

ref:  https://docs.microsoft.com/en-us/azure/devops/pipelines/release/variables?view=azdevops&tabs=powershell
 Write-Host $env:SITENAME $env:UserID $env:WebEnvironment
#>
$ErrorActionPreference = "Stop"
$LocalGroup = "WebLogViewers"
$path = ('C:\inetpub\' + $SiteName)

# ensure $userid is memeber of one of the dev groups

# ensure the local group is created, create it if it isn't
try {
	If(!(Get-LocalGroup -Name $LocalGroup)){
		New-LocalGroup -Name $LocalGroup -Description "Allows Developers to View website logs"
	}
}
catch {
	"Group already exists, creating new group"
}
#finally {
	
#}

write-host "Starting to change/reset permissions on folder"
# ensure the local group has correct access, reset it to what we expect
$Acl = Get-Acl $Path  
if ($WebEnvironment = "dev") {
	$Ar = New-Object  system.security.accesscontrol.filesystemaccessrule($LocalGroup,"ReadAndExecute", "ContainerInherit,ObjectInherit", "None", "Allow")
}  
elseif ($WebEnvironment = "test") {
	$Ar = New-Object  system.security.accesscontrol.filesystemaccessrule($LocalGroup,"ReadAndExecute", "ContainerInherit,ObjectInherit", "None", "Allow")
}
elseif ($WebEnvironment = "qa") {
	$Ar = New-Object  system.security.accesscontrol.filesystemaccessrule($LocalGroup,"ReadAndExecute", "ContainerInherit,ObjectInherit", "None", "Allow")
}
else {  # assuming prod, or anything else, so least priv
	$Ar = New-Object  system.security.accesscontrol.filesystemaccessrule($LocalGroup,"List", "ContainerInherit,ObjectInherit", "None", "Allow")	
}
$Acl.SetAccessRule($Ar)  
Set-Acl $Path $Acl 

write-host "Done change/reset permissions on folder"

write-host "adding user to the local group"
# if enable access, put a domain user in that local group
# if "not enable" , remove the user from the group
if ($EnableAccess -like "Yes"){
	try{
        Add-LocalGroupMember -Group $LocalGroup -Member $UserID -ErrorAction Stop
        } catch [Microsoft.PowerShell.Commands.MemberExistsException] {
            Write-Warning "$member already in $group"
        }
}
else {
	try{
		Remove-LocalGroupMember -Group $LocalGroup -Member $UserID -ErrorAction Stop
		        } catch [Microsoft.PowerShell.Commands.MemberExistsException] {
            Write-Warning "$member not in $group"
        }
}
if ($userId -eq "nobody") { # if run with no userid, it will clear out the local group completely
	Get-LocalgroupMember $LocalGroup | ForEach-Object {Remove-LocalGroupMember $LocalGroup $_ -Confirm:$false}
}
write-host "done adding user to the local group"


# ensure share is correct


if ($EnableAccess -like "Yes") {
	write-host "starting to create the scheduled task"
	$random = (get-random -Maximum 999)
	# set scheduled task to remove it later, 15 min
	#ref: https://docs.microsoft.com/en-us/powershell/module/scheduledtasks/new-scheduledtask?view=win10-ps
	#https://blogs.technet.microsoft.com/heyscriptingguy/2015/01/13/use-powershell-to-create-scheduled-tasks/
    $ScheduledTaskName = "ModifyWebfolderacess for site $SiteName until $futuretimeText for $userid - $random"	
    $scriptpath = "c:\scripts\Modify-WebFolderAccess.ps1 -Sitename $Sitename -EnableAccess No -UserId $userID -Taskname `"$ScheduledTaskName`""
	$futuretime = (get-date).AddMinutes(15)
	$futuretimeText = ($futuretime.hour).tostring() + '-' + ($futuretime.Minute).tostring()  # register later does NOT like ":", so made it "-"
	$Action = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument "-executionpolicy bypass -noprofile -file $scriptPath"
	$Trigger = New-ScheduledTaskTrigger -Once -At $futuretime
	$Principal = New-ScheduledTaskPrincipal -UserID "NT AUTHORITY\SYSTEM" -RunLevel Highest -LogonType ServiceAccount 
	# appears to be another bug in scheduled tasks that they will not remove themselves, so leaving the "delete" out of it. 
	#    ref: https://stackoverflow.com/questions/52783683/powershell-scheduled-task-not-deleting/52786886
	$SettingsSet = New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-Timespan -minutes 5)  #-DeleteExpiredTaskAfter (New-TimeSpan -Days 30) # -Priority 7
	$TaskObject = New-ScheduledTask -Action $Action  -Trigger $Trigger -Settings $SettingsSet -Principal $Principal

	Register-ScheduledTask -Taskname $ScheduledTaskName -InputObject $TaskObject 
	write-host "done creating the scheduled task"
	}

if ($Taskname) {
	# when the scheduled task is run, it will pass the param with the name, and here is where it removes (unregisters) itself.
    Unregister-ScheduledTask -TaskName $Taskname -Confirm:$false
    # $taskname = $scheduledtaskname
}
