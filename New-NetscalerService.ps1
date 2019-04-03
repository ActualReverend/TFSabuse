
<#PSScriptInfo

.VERSION 0.9

.GUID e902b870-45ee-4386-9641-771d499e6416

.AUTHOR Bryan Loveless 

.COMPANYNAME 

.COPYRIGHT 2019

.TAGS Netscaler

.LICENSEURI 

.PROJECTURI 

.ICONURI 

.EXTERNALMODULEDEPENDENCIES 

.REQUIREDSCRIPTS 

.EXTERNALSCRIPTDEPENDENCIES 

.RELEASENOTES
    Requires powershell core (powershell v6+).  REF: https://github.com/PowerShell/PowerShell/releases
    
.PRIVATEDATA 
#>

<# 
.DESCRIPTION 
 Create a new netscaler service, from scratch

 Example: .\New-NetscalerService.ps1 -AppName itsproxy -AppType proxy -RealServerNames "blah1.blah.com","blah1.blah.com" -Environment dev -BackendPort 38 -FrontendPort 38 -NSExternalIP 1.2.3.42 -Traffictype TCP
          .\New-NetscalerService.ps1 -AppName itsproxy -AppType proxy -RealServerNames "blah1.blah.com","blah1.blah.com" -Environment prod -BackendPort 31 -FrontendPort 31 -NSExternalIP 1.2.4.4 -Traffictype TCP
 #>          
#function New-NetscalerService{
    Param(
		[Parameter(Mandatory=$True,
			HelpMessage="Enter Application Name NOT Fully Qualified. Camel case example: ITSproxy")]
            [string]$AppName,
        [Parameter(Mandatory=$True,
			HelpMessage="Enter Applicaiton type. Common examples: web, mail, proxy")]
			[string]$AppType,     
		[Parameter(Mandatory=$True,
            HelpMessage="example: ")]
            <#[ValidateScript({Resolve-DNSName -Name $_})]#>
			[string[]]$RealServerNames, 
		[Parameter(Mandatory=$true,
			HelpMessage="Valid entries are dev, test, prod, staging, training")]
            [string][ValidateSet("dev", "test", "prod", "staging", "training")]$Environment,
		[Parameter(Mandatory=$true)][int]$BackendPort,
        [Parameter(Mandatory=$true)][int]$FrontendPort,
        [Parameter(Mandatory=$false)][string]$NSCertifcateName,
        [Parameter(Mandatory=$true,
            HelpMessage="What is the IP address the netscaler will use to listen?")]
            [ValidateScript({$_ -match [IPAddress]$_ })]
            [string]$NSExternalIP,
        [Parameter(Mandatory=$false)][string]$NSCertificatePassword,
		[Parameter(Mandatory=$false,
			HelpMessage="Type of traffic.  Common examples: SSL, TCP, ANY")]
            [string][ValidateSet("SSL","TCP","ANY")]$Traffictype = "SSL" #this must match actual traffic types on the netscaler  SSL for web

    )
    
    # Simplistlicaly, this is how traffic flows:  external client https or ssl -> netscaler public IP -> Netscaler Content switching virtual server (CSVS) if http,
    #   redirects to SSL -> Load balancing virtual server (LBVS) HTTP only to save resources --> Load balanced service group (SG) 
    #   -> Load balanced service group member (LBS), this is where the real servers are listed, and the NS decides where to send traffic, but uses SSL here for backend 
    #   see diagram:  https://www.rhipe.com/wp-content/uploads/2016/12/content-switching.png
    

    # set what netscaler to talk to:
    
	if ($Environment -eq "dev") {
		$netscalerName = 'YOURFQDNNS'
		}
	elseif ($Environment -eq "test") {
		$netscalerName = 'YOURFQDNNS'
		}
	elseif ($Environment -eq "prod") {
        # if environment is prod, we want it to be blank now:
        $netscalerName = 'YOURFQDNNS'
		}
	elseif ($Environment -eq "staging") {
		exit # reserved for future use
		}
	elseif ($Environment -eq "training") {
		exit # reserved for future use
		}
    #ssh in powershell with the built in one is as easy as ssh username@hostname -p port or new-pssession, but neither accept a password, only identity files
    write-host "in the interest of time, it will only spit out the commands to run on the netscaler at this time.  Once there is more time to get the automation of the ssh connectionto work, this can be revisited"
    #create the list to hold the commands
    $commandlist = New-Object 'System.Collections.Generic.List[string]'
    # assign public IP to netscaler
    $commandlist.Add( "add ns ip $NSExternalIP 255.255.255.255 -type VIP -mgmtAccess ENABLED -icmpResponse ONE_VSERVER -arpResponse ONE_VSERVER")
    #add content switching virtual server ref: https://developer-docs.citrix.com/projects/netscaler-command-reference/en/12.0/cs/cs-vserver/cs-vserver/#add-cs-vserver
    $commandlist.Add( "add cs vserver csvs-$AppName-$AppType-$FrontendPort $Traffictype $NSExternalIP $FrontendPort -cltTimeout 180")
    

    if($Traffictype -eq "SSL"){
        # need a "dummy" CSVS to redirect to the other csvs with ssl if web traffic
        $commandlist.Add( "add cs vserver csvs-$AppName-$AppType-HTTP HTTP $NSExternalIP 80 -cltTimeout 180")
        $commandlist.Add( "bind cs vserver vserver csvs-$AppName-$AppType-HTTP -policyName rs_pol_senttossl -priority 100 -gotoPriorityExpression END -type REQUEST")
        #add service group with $AppType 
        $commandlist.Add( "add serviceGroup sg-$AppName-$AppType $Traffictype -maxClient 0 -maxReq 0 -cacheable YES -cip ENABLED X-Forwarded-For -usip NO -useproxyport YES -cltTimeout 180 -svrTimeout 360 -CKA NO -TCPB NO -CMP YES")
        #add Load balanced virtual server with non ssl to save computing cycles
        $commandlist.Add( "add lb vserver lbvs-$AppName-$AppType-NoIP HTTP 0.0.0.0 0 -persistenceType NONE -cltTimeout 180")
        #bind WAF?  add appfw profile
        #add appfw profile lah_waf_p -startURLAction learn log stats -contentTypeAction learn log stats -startURLClosure ON -denyURLAction log stats -RefererHeaderCheck if_present -cookieConsistencyAction learn log stats -fieldConsistencyAction learn log stats -CSRFtagAction learn log stats -crossSiteScriptingAction learn log stats -SQLInjectionAction learn log stats -fieldFormatAction learn log stats -bufferOverflowAction log stats -creditCardAction learn log stats -responseContentType "application/octet-stream" -XMLDoSAction learn log stats -XMLFormatAction log stats -XMLSQLInjectionAction log stats -XMLXSSAction learn log stats -XMLWSIAction learn log stats -XMLAttachmentAction learn log stats -XMLValidationAction log stats -XMLSOAPFaultAction log stats -type HTML XML
        #turn off ssl and tls for csvs
        $commandlist.Add( "set ssl vserver csvs-$AppName-$AppType-$FrontendPort -dh ENABLED -dhFile `"/nsconfig/ssl/blah-dh5-1024.key`" -ssl3 DISABLED -tls1 DISABLED -tls12 DISABLED")
        #bind rewrite policies to the new system  (only on web based systems)

        # bind the ssl to the service group:
        $commandlist.Add( "set ssl serviceGroup sg-$AppName-$AppType $Traffictype -ssl3 DISABLED -tls12 DISABLED")
    }
    else {
        #add service group with $AppType  NEEDS TO BE ANY IF NOT SSL
        $commandlist.Add( "add serviceGroup sg-$AppName-$AppType ANY -maxClient 0 -maxReq 0 -usip NO -useproxyport YES -cltTimeout 180 -svrTimeout 360 -CKA NO")
        #add Load balanced virtual server with whatever traffic type is needed, if not web/ssl traffic type
        $commandlist.Add( "add lb vserver lbvs-$AppName-$AppType-NoIP $Traffictype 0.0.0.0 0 -persistenceType NONE -cltTimeout 180" )

    }
     
    #bind content switching vserver to lbvserver
    $commandlist.Add( "bind cs vserver csvs-$AppName-$AppType-$FrontendPort -lbvserver lbvs-$AppName-$AppType-NoIP")

    Foreach ($realserver in $RealServerNames){
        #add real server
        $commandlist.Add( "add server $realserver $realserver") #-comment `"commenthereifyouneed`")
                
        if($Traffictype -eq "SSL"){
            # setup monitoring 
            $commandlist.Add( "bind service lbservice-$realserver-$traffictype-$backendport -monitorName http-ecv")
            #bind lb vserver
            $commandlist.Add( "bind lb vserver lbvs-$AppName-$AppType-NoIP lbservice-$realserver-$traffictype-$backendport")
            $commandlist.Add( "add service lbservice-$realserver-$traffictype-$backendport $realserver $traffictype $backendport -gslb NONE -maxClient 0 -maxReq 0 -cip ENABLED X-Forwarded-For -usip NO -useproxyport YES -sp ON -cltTimeout 180 -svrTimeout 360 -CKA NO -TCPB NO -CMP YES")
    
            #turn off ssl and tls for lbservice, including tls 1.2 for backend systems, as the dev netscalers cannot handle it
            $commandlist.Add( "set ssl service lbservice-$realserver-$traffictype-$backendport -ssl3 DISABLED -tls1 DISABLED -tls12 DISABLED")
            #Bind ssl to the service
            $commandlist.Add( "bind ssl service lbservice-$realserver-$traffictype-$backendport -eccCurveName P_256")
            $commandlist.Add( "bind ssl service lbservice-$realserver-$traffictype-$backendport -eccCurveName P_384")
            $commandlist.Add( "bind ssl service lbservice-$realserver-$traffictype-$backendport -eccCurveName P_224")
            $commandlist.Add( "bind ssl service lbservice-$realserver-$traffictype-$backendport -eccCurveName P_521")
        }
        else {
            #add service
            $commandlist.Add( "add service lbservice-$realserver-$traffictype-$backendport $realserver $traffictype $backendport -gslb NONE -maxClient 0 -maxReq 0 -usip NO -useproxyport YES -sp ON -cltTimeout 180 -svrTimeout 360 -CKA NO")
            #setup monitoring
            $commandlist.Add( "bind service lbservice-$realserver-$traffictype-$backendport -monitorName tcp")
            #bind lb vserver
            $commandlist.Add( "bind lb vserver lbvs-$AppName-$AppType-NoIP lbservice-$realserver-$traffictype-$backendport")
        }

        #bind servicegroup to backend real servers
        $commandlist.Add( "bind serviceGroup sg-$AppName-$AppType $Realserver $backendport")

    }

    if($NSCertifcateName){
        #add ssl certKey BLAH.COM -cert BLAH.cer -key BLAH.key -passcrypt $NSCertificatePassword
    }
#}




write-host "Here are the commands to run on $netscalerName :" -ForegroundColor Green
write-host "ssh USERID@$netscalerName" 
$commandlist
write-host "save config"

