#########
# au2mator PS Services
# Type: New Service
#
# Title: SCCM - Assign Primary User to Computer
#
# v 1.0 Initial Release
#
#
# Init Release: 06.04.2021
# Last Update: 06.04.2021
# Code Template V 1.3
#
# URL: https://au2mator.com/new-microsoft-teams-team-�-microsoft-teams-self-service-with-au2mator/?utm_source=github&utm_medium=social&utm_campaign=M365_NewTeamsTeam&utm_content=PS1
# Github: https://github.com/au2mator/TEAMS-New-Teams-Team
#################


#region InputParamaters
##Question in au2mator
param (

    [parameter(Mandatory = $true)]
    [String]$c_Client,

    [parameter(Mandatory = $true)]
    [String]$c_User,

    [parameter(Mandatory = $true)]
    [String]$c_Replace,


    [parameter(Mandatory = $true)]
    [String]$InitiatedBy,

    [parameter(Mandatory = $true)]
    [String]$RequestId,

    [parameter(Mandatory = $true)]
    [String]$Service,

    [parameter(Mandatory = $true)]
    [String]$TargetUserId
)
#endregion  InputParamaters

#region Variables
Set-ExecutionPolicy -ExecutionPolicy Bypass
$DoImportPSSession = $false


## Environment
[string]$PSRemotingServer = "demo01"
[string]$LogPath = "C:\_SCOworkingDir\TFS\PS-Services\SCCM - Assign Primary User to Computer"
[string]$LogfileName = "Assign Primary User to Computer"
[string]$CredentialStorePath = "C:\_SCOworkingDir\TFS\PS-Services\CredentialStore" #see for details: https://click.au2mator.com/PSCreds/?utm_source=github&utm_medium=social&utm_campaign=M365_NewTeamsTeam&utm_content=PS1

$CMSiteCode = "A2M"
$SiteServer = "demo01"

$Modules = @("ActiveDirectory") #$Modules = @("ActiveDirectory", "SharePointPnPPowerShellOnline")


## au2mator Settings
[string]$PortalURL = "http://demo01.au2mator.local"
[string]$au2matorDBServer = "demo01"
[string]$au2matorDBName = "au2mator40Demo2"

## Control Mail
$SendMailToInitiatedByUser = $true #Send a Mail after Service is completed
$SendMailToTargetUser = $true #Send Mail to Target User after Service is completed

## SMTP Settings
$SMTPServer = "smtp.office365.com"
$SMPTAuthentication = $true #When True, User and Password needed
$EnableSSLforSMTP = $true
$SMTPSender = "SelfService@au2mator.com"
$SMTPPort = "587"

# Stored Credentials
# See: https://click.au2mator.com/PSCreds/?utm_source=github&utm_medium=social&utm_campaign=M365_NewTeamsTeam&utm_content=PS1
$SMTPCredential_method = "Stored" #Stored, Manual
$SMTPcredential_File = "SMTPCreds.xml"
$SMTPUser = ""
$SMTPPassword = ""

if ($SMTPCredential_method -eq "Stored") {
    $SMTPcredential = Import-CliXml -Path (Get-ChildItem -Path $CredentialStorePath -Filter $SMTPcredential_File).FullName
}

if ($SMTPCredential_method -eq "Manual") {
    $f_secpasswd = ConvertTo-SecureString $SMTPPassword -AsPlainText -Force
    $SMTPcredential = New-Object System.Management.Automation.PSCredential ($SMTPUser, $f_secpasswd)
}

#endregion Variables


#region CustomVariables


#endregion CustomVariables


#region Functions
function Write-au2matorLog {
    [CmdletBinding()]
    param
    (
        [ValidateSet('DEBUG', 'INFO', 'WARNING', 'ERROR')]
        [string]$Type,
        [string]$Text
    )

    # Set logging path
    if (!(Test-Path -Path $logPath)) {
        try {
            $null = New-Item -Path $logPath -ItemType Directory
            Write-Verbose ("Path: ""{0}"" was created." -f $logPath)
        }
        catch {
            Write-Verbose ("Path: ""{0}"" couldn't be created." -f $logPath)
        }
    }
    else {
        Write-Verbose ("Path: ""{0}"" already exists." -f $logPath)
    }
    [string]$logFile = '{0}\{1}_{2}.log' -f $logPath, $(Get-Date -Format 'yyyyMMdd'), $LogfileName
    $logEntry = '{0}: <{1}> <{2}> <{3}> {4}' -f $(Get-Date -Format dd.MM.yyyy-HH:mm:ss), $Type, $RequestId, $Service, $Text
    Add-Content -Path $logFile -Value $logEntry
}

function ConnectToDB {
    # define parameters
    param(
        [string]
        $servername,
        [string]
        $database
    )
    Write-au2matorLog -Type INFO -Text "Function ConnectToDB"
    # create connection and save it as global variable
    $global:Connection = New-Object System.Data.SQLClient.SQLConnection
    $Connection.ConnectionString = "server='$servername';database='$database';trusted_connection=false; integrated security='true'"
    $Connection.Open()
    Write-au2matorLog -Type INFO -Text 'Connection established'
}

function ExecuteSqlQuery {
    # define parameters
    param(

        [string]
        $sqlquery

    )
    Write-au2matorLog -Type INFO -Text "Function ExecuteSqlQuery"
    #Begin {
    If (!$Connection) {
        Write-au2matorLog -Type WARNING -Text"No connection to the database detected. Run command ConnectToDB first."
    }
    elseif ($Connection.State -eq 'Closed') {
        Write-au2matorLog -Type INFO -Text 'Connection to the database is closed. Re-opening connection...'
        try {
            # if connection was closed (by an error in the previous script) then try reopen it for this query
            $Connection.Open()
        }
        catch {
            Write-au2matorLog -Type INFO -Text "Error re-opening connection. Removing connection variable."
            Remove-Variable -Scope Global -Name Connection
            Write-au2matorLog -Type WARNING -Text "Unable to re-open connection to the database. Please reconnect using the ConnectToDB commandlet. Error is $($_.exception)."
        }
    }
    #}

    #Process {
    #$Command = New-Object System.Data.SQLClient.SQLCommand
    $command = $Connection.CreateCommand()
    $command.CommandText = $sqlquery

    Write-au2matorLog -Type INFO -Text "Running SQL query '$sqlquery'"
    try {
        $result = $command.ExecuteReader()
    }
    catch {
        $Connection.Close()
    }
    $Datatable = New-Object "System.Data.Datatable"
    $Datatable.Load($result)

    return $Datatable

    #}

    #End {
    Write-au2matorLog -Type INFO -Text "Finished running SQL query."
    #}
}

function Get-UserInput ($RequestID) {
    [hashtable]$return = @{ }

    Write-au2matorLog -Type INFO -Text "Function Get-UserInput"
    ConnectToDB -servername $au2matorDBServer -database $au2matorDBName

    $Result = ExecuteSqlQuery -sqlquery "SELECT        RPM.Text AS Question, RP.Value
    FROM            dbo.Requests AS R INNER JOIN
                             dbo.RunbookParameterMappings AS RPM ON R.ServiceId = RPM.ServiceId INNER JOIN
                             dbo.RequestParameters AS RP ON RPM.ParameterName = RP.[Key] AND R.ID = RP.RequestId
    where RP.RequestId = '$RequestID' and rpm.IsDeleted = '0' order by [Order]"

    $html = "<table><tr><td><b>Question</b></td><td><b>Answer</b></td></tr>"
    $html = "<table>"
    foreach ($row in $Result) {
        #$row
        $html += "<tr><td><b>" + $row.Question + ":</b></td><td>" + $row.Value + "</td></tr>"
    }
    $html += "</table>"

    $f_RequestInfo = ExecuteSqlQuery -sqlquery "select InitiatedBy, TargetUserId,[ApprovedBy], [ApprovedTime], Comment from Requests where Id =  '$RequestID'"

    $Connection.Close()
    Remove-Variable -Scope Global -Name Connection

    $f_SamInitiatedBy = $f_RequestInfo.InitiatedBy.Split("\")[1]
    $f_UserInitiatedBy = Get-ADUser -Identity $f_SamInitiatedBy -Properties Mail


    $f_SamTarget = $f_RequestInfo.TargetUserId.Split("\")[1]
    $f_UserTarget = Get-ADUser -Identity $f_SamTarget -Properties Mail

    $return.InitiatedBy = $f_RequestInfo.InitiatedBy.trim()
    $return.MailInitiatedBy = $f_UserInitiatedBy.mail.trim()
    $return.MailTarget = $f_UserTarget.mail.trim()
    $return.TargetUserId = $f_RequestInfo.TargetUserId.trim()
    $return.ApprovedBy = $f_RequestInfo.ApprovedBy.trim()
    $return.ApprovedTime = $f_RequestInfo.ApprovedTime
    $return.Comment = $f_RequestInfo.Comment
    $return.HTML = $HTML

    return $return
}

Function Get-MailContent ($RequestID, $RequestTitle, $EndDate, $TargetUserId, $InitiatedBy, $Status, $PortalURL, $RequestedBy, $AdditionalHTML, $InputHTML) {

    Write-au2matorLog -Type INFO -Text "Function Get-MailContent"
    $f_RequestID = $RequestID
    $f_InitiatedBy = $InitiatedBy

    $f_RequestTitle = $RequestTitle

    try {
        $f_EndDate = (get-Date -Date $EndDate -Format (Get-Culture).DateTimeFormat.ShortDatePattern) + " (" + (get-Date -Date $EndDate -Format (Get-Culture).DateTimeFormat.ShortTimePattern) + ")"
    }
    catch {
        $f_EndDate = $EndDate
    }

    $f_RequestStatus = $Status
    $f_RequestLink = "$PortalURL/requeststatus?id=$RequestID"
    $f_HTMLINFO = $AdditionalHTML
    $f_InputHTML = $InputHTML

    $f_SamInitiatedBy = $f_InitiatedBy.Split("\")[1]
    $f_UserInitiatedBy = Get-ADUser -Identity $f_SamInitiatedBy -Properties DisplayName
    $f_DisplaynameInitiatedBy = $f_UserInitiatedBy.DisplayName


    $HTML = @'
    <table class="MsoNormalTable" style="width: 100.0%; mso-cellspacing: 1.5pt; background: #F7F8F3; mso-yfti-tbllook: 1184;" border="0" width="100%" cellpadding="0">
    <tbody>
    <tr style="mso-yfti-irow: 0; mso-yfti-firstrow: yes; mso-yfti-lastrow: yes;">
    <td style="padding: .75pt .75pt .75pt .75pt;" valign="top">&nbsp;</td>
    <td style="width: 450.0pt; padding: .75pt .75pt .75pt .75pt; box-sizing: border-box;" valign="top" width="600">
    <div style="box-sizing: border-box;">
    <table class="MsoNormalTable" style="width: 100.0%; mso-cellspacing: 0cm; background: white; border: solid #E9E9E9 1.0pt; mso-border-alt: solid #E9E9E9 .75pt; mso-yfti-tbllook: 1184; mso-padding-alt: 0cm 0cm 0cm 0cm;" border="1" width="100%" cellspacing="0" cellpadding="0">
    <tbody>
    <tr style="mso-yfti-irow: 0; mso-yfti-firstrow: yes;">
    <td style="border: none; background: #6ddc36; padding: 15.0pt 0cm 15.0pt 15.0pt;" valign="top">
    <p class="MsoNormal" style="line-height: 19.2pt;"><img src="https://au2mator.com/wp-content/uploads/2018/02/HPLogoau2mator-1.png" alt="" width="198" height="43" /></p>
    </td>
    </tr>
    <tr style="mso-yfti-irow: 1; box-sizing: border-box;">
    <td style="border: none; padding: 15.0pt 15.0pt 15.0pt 15.0pt; box-sizing: border-box;" valign="top">
    <table class="MsoNormalTable" style="width: 100.0%; mso-cellspacing: 0cm; mso-yfti-tbllook: 1184; mso-padding-alt: 0cm 0cm 0cm 0cm; box-sizing: border-box;" border="0" width="100%" cellspacing="0" cellpadding="0">
    <tbody>
    <tr style="mso-yfti-irow: 0; mso-yfti-firstrow: yes; mso-yfti-lastrow: yes; box-sizing: border-box;">
    <td style="padding: 0cm 0cm 15.0pt 0cm; box-sizing: border-box;" valign="top">
    <table class="MsoNormalTable" style="width: 100.0%; mso-cellspacing: 0cm; mso-yfti-tbllook: 1184; mso-padding-alt: 0cm 0cm 0cm 0cm; box-sizing: border-box;" border="0" width="100%" cellspacing="0" cellpadding="0">
    <tbody>
    <tr style="mso-yfti-irow: 0; mso-yfti-firstrow: yes; mso-yfti-lastrow: yes; box-sizing: border-box;">
    <td style="width: 55.0%; padding: 0cm 0cm 0cm 0cm; box-sizing: border-box;" valign="top" width="55%">
    <table class="MsoNormalTable" style="width: 100.0%; mso-cellspacing: 0cm; mso-yfti-tbllook: 1184; mso-padding-alt: 0cm 0cm 0cm 0cm;" border="0" width="100%" cellspacing="0" cellpadding="0">
    <tbody>
    <tr style="mso-yfti-irow: 0; mso-yfti-firstrow: yes;">
    <td style="width: 18.75pt; border-top: solid #E3E3E3 1.0pt; border-left: solid #E3E3E3 1.0pt; border-bottom: none; border-right: none; mso-border-top-alt: solid #E3E3E3 .75pt; mso-border-left-alt: solid #E3E3E3 .75pt; padding: 0cm 0cm 0cm 0cm; box-sizing: border-box;" width="25">
    <p class="MsoNormal" style="text-align: center; line-height: 19.2pt;" align="center">&nbsp;</p>
    </td>
    <td style="border-top: solid #E3E3E3 1.0pt; border-left: none; border-bottom: none; border-right: solid #E3E3E3 1.0pt; mso-border-top-alt: solid #E3E3E3 .75pt; mso-border-right-alt: solid #E3E3E3 .75pt; padding: 0cm 0cm 3.75pt 0cm; font-color: #0000;"><strong>End Date</strong>: ##EndDate</td>
    </tr>
    <tr style="mso-yfti-irow: 1;">
    <td style="border-top: solid #E3E3E3 1.0pt; border-left: solid #E3E3E3 1.0pt; border-bottom: none; border-right: none; mso-border-top-alt: solid #E3E3E3 .75pt; mso-border-left-alt: solid #E3E3E3 .75pt; padding: 0cm 0cm 0cm 0cm;">
    <p class="MsoNormal" style="text-align: center; line-height: 19.2pt;" align="center">&nbsp;</p>
    </td>
    <td style="border-top: solid #E3E3E3 1.0pt; border-left: none; border-bottom: none; border-right: solid #E3E3E3 1.0pt; mso-border-top-alt: solid #E3E3E3 .75pt; mso-border-right-alt: solid #E3E3E3 .75pt; padding: 0cm 0cm 3.75pt 0cm;"><strong>Status</strong>: ##Status</td>
    </tr>
    <tr style="mso-yfti-irow: 2; mso-yfti-lastrow: yes;">
    <td style="border: solid #E3E3E3 1.0pt; border-right: none; mso-border-top-alt: solid #E3E3E3 .75pt; mso-border-left-alt: solid #E3E3E3 .75pt; mso-border-bottom-alt: solid #E3E3E3 .75pt; padding: 0cm 0cm 3.75pt 0cm;">
    <p class="MsoNormal" style="text-align: center; line-height: 19.2pt;" align="center">&nbsp;</p>
    </td>
    <td style="border: solid #E3E3E3 1.0pt; border-left: none; mso-border-top-alt: solid #E3E3E3 .75pt; mso-border-bottom-alt: solid #E3E3E3 .75pt; mso-border-right-alt: solid #E3E3E3 .75pt; padding: 0cm 0cm 3.75pt 0cm;"><strong>Requested By</strong>: ##RequestedBy</td>
    </tr>
    </tbody>
    </table>
    </td>
    <td style="width: 5.0%; padding: 0cm 0cm 0cm 0cm; box-sizing: border-box;" width="5%">
    <p class="MsoNormal" style="line-height: 19.2pt;"><span style="font-size: 9.0pt; font-family: 'Helvetica',sans-serif; mso-fareast-font-family: 'Times New Roman';">&nbsp;</span></p>
    </td>
    <td style="width: 40.0%; padding: 0cm 0cm 0cm 0cm; box-sizing: border-box;" valign="top" width="40%">
    <table class="MsoNormalTable" style="width: 100.0%; mso-cellspacing: 0cm; background: #FAFAFA; mso-yfti-tbllook: 1184; mso-padding-alt: 0cm 0cm 0cm 0cm;" border="0" width="100%" cellspacing="0" cellpadding="0">
    <tbody>
    <tr style="mso-yfti-irow: 0; mso-yfti-firstrow: yes; mso-yfti-lastrow: yes;">
    <td style="width: 100.0%; border: solid #E3E3E3 1.0pt; mso-border-alt: solid #E3E3E3 .75pt; padding: 7.5pt 0cm 1.5pt 3.75pt;" width="100%">
    <p style="text-align: center;" align="center"><span style="font-size: 10.5pt; color: #959595;">au2mator Request ID</span></p>
    <p style="text-align: center;" align="center"><u><span style="font-size: 12.0pt; color: black;"><a href="##RequestLink"><span style="color: black;">##REQUESTID</span></a></span></u></p>
    <p class="MsoNormal" style="text-align: center;" align="center"><span style="mso-fareast-font-family: 'Times New Roman';">&nbsp;</span></p>
    </td>
    </tr>
    </tbody>
    </table>
    </td>
    </tr>
    </tbody>
    </table>
    </td>
    </tr>
    </tbody>
    </table>
    </td>
    </tr>
    <tr style="mso-yfti-irow: 2; box-sizing: border-box;">
    <td style="border: none; padding: 0cm 15.0pt 15.0pt 15.0pt; box-sizing: border-box;" valign="top">
    <table class="MsoNormalTable" style="width: 100.0%; mso-cellspacing: 0cm; mso-yfti-tbllook: 1184; mso-padding-alt: 0cm 0cm 0cm 0cm; box-sizing: border-box;" border="0" width="100%" cellspacing="0" cellpadding="0">
    <tbody>
    <tr style="mso-yfti-irow: 0; mso-yfti-firstrow: yes; box-sizing: border-box;">
    <td style="padding: 0cm 0cm 15.0pt 0cm; box-sizing: border-box;" valign="top">
    <p class="MsoNormal" style="line-height: 19.2pt;"><strong><span style="font-size: 10.5pt; font-family: 'Helvetica',sans-serif; mso-fareast-font-family: 'Times New Roman';">Dear ##UserDisplayname,</span></strong></p>
    </td>
    </tr>
    <tr style="mso-yfti-irow: 1; box-sizing: border-box;">
    <td style="padding: 0cm 0cm 15.0pt 0cm; box-sizing: border-box;" valign="top">
    <p class="MsoNormal" style="line-height: 19.2pt;"><span style="font-size: 10.5pt; font-family: 'Helvetica',sans-serif; mso-fareast-font-family: 'Times New Roman';">We finished the Request <strong>"##RequestTitle"</strong>!<br /> <br /> Here are the Result of the Request:<br /><b>##HTMLINFO&nbsp;</b><br /></span></p>
    <div>&nbsp;</div>
    <div>See the details of the Request</div>
    <div>##InputHTML</div>
    <div>&nbsp;</div>
    <div>&nbsp;</div>
    Kind regards,<br /> au2mator Self Service Team
    <p>&nbsp;</p>
    </td>
    </tr>
    <tr style="mso-yfti-irow: 2; mso-yfti-lastrow: yes; box-sizing: border-box;">
    <td style="padding: 0cm 0cm 15.0pt 0cm; box-sizing: border-box;" valign="top">
    <p class="MsoNormal" style="text-align: center; line-height: 19.2pt;" align="center"><span style="font-size: 10.5pt; font-family: 'Helvetica',sans-serif; mso-fareast-font-family: 'Times New Roman';"><a style="border-radius: 3px; -webkit-border-radius: 3px; -moz-border-radius: 3px; display: inline-block;" href="##RequestLink"><strong><span style="color: white; border: solid #50D691 6.0pt; padding: 0cm; background: #50D691; text-decoration: none; text-underline: none;">View your Request</span></strong></a></span></p>
    </td>
    </tr>
    </tbody>
    </table>
    </td>
    </tr>
    <tr style="mso-yfti-irow: 3; mso-yfti-lastrow: yes; box-sizing: border-box;">
    <td style="border: none; padding: 0cm 0cm 0cm 0cm; box-sizing: border-box;" valign="top">
    <table class="MsoNormalTable" style="width: 100.0%; mso-cellspacing: 0cm; background: #333333; mso-yfti-tbllook: 1184; mso-padding-alt: 0cm 0cm 0cm 0cm;" border="0" width="100%" cellspacing="0" cellpadding="0">
    <tbody>
    <tr style="mso-yfti-irow: 0; mso-yfti-firstrow: yes; mso-yfti-lastrow: yes; box-sizing: border-box;">
    <td style="width: 50.0%; border: none; border-right: solid lightgrey 1.0pt; mso-border-right-alt: solid lightgrey .75pt; padding: 22.5pt 15.0pt 22.5pt 15.0pt; box-sizing: border-box;" valign="top" width="50%">&nbsp;</td>
    <td style="width: 50.0%; padding: 22.5pt 15.0pt 22.5pt 15.0pt; box-sizing: border-box;" valign="top" width="50%">&nbsp;</td>
    </tr>
    </tbody>
    </table>
    </td>
    </tr>
    </tbody>
    </table>
    </div>
    </td>
    <td style="padding: .75pt .75pt .75pt .75pt; box-sizing: border-box;" valign="top">&nbsp;</td>
    </tr>
    </tbody>
    </table>
    <p class="MsoNormal"><span style="mso-fareast-font-family: 'Times New Roman';">&nbsp;</span></p>
'@

    $html = $html.replace('##REQUESTID', $f_RequestID).replace('##UserDisplayname', $f_DisplaynameInitiatedBy).replace('##RequestTitle', $f_RequestTitle).replace('##EndDate', $f_EndDate).replace('##Status', $f_RequestStatus).replace('##RequestedBy', $f_InitiatedBy).replace('##HTMLINFO', $f_HTMLINFO).replace('##InputHTML', $f_InputHTML).replace('##RequestLink', $f_RequestLink)

    return $html
}

Function Send-ServiceMail ($HTMLBody, $ServiceName, $Recipient, $RequestID, $RequestStatus) {
    Write-au2matorLog -Type INFO -Text "Function Send-ServiceMail"
    $f_Subject = "au2mator - $ServiceName Request [$RequestID] - $RequestStatus"
    Write-au2matorLog -Type INFO -Text "Subject:  $f_Subject "
    Write-au2matorLog -Type INFO -Text "Recipient: $Recipient"

    try {
        if ($SMPTAuthentication) {

            if ($EnableSSLforSMTP) {
                Write-au2matorLog -Type INFO -Text "Run SMTP with Authentication and SSL"
                Send-MailMessage -SmtpServer $SMTPServer -To $Recipient -From $SMTPSender -Subject $f_Subject -Body $HTMLBody -BodyAsHtml -Priority high -Credential $SMTPcredential -UseSsl -Port $SMTPPort
            }
            else {
                Write-au2matorLog -Type INFO -Text "Run SMTP with Authentication and no SSL"
                Send-MailMessage -SmtpServer $SMTPServer -To $Recipient -From $SMTPSender -Subject $f_Subject -Body $HTMLBody -BodyAsHtml -Priority high -Credential $SMTPcredential -Port $SMTPPort
            }
        }
        else {

            if ($EnableSSLforSMTP) {
                Write-au2matorLog -Type INFO -Text "Run SMTP without Authentication and SSL"
                Send-MailMessage -SmtpServer $SMTPServer -To $Recipient -From $SMTPSender -Subject $f_Subject -Body $HTMLBody -BodyAsHtml -Priority high -UseSsl -Port $SMTPPort
            }
            else {
                Write-au2matorLog -Type INFO -Text "Run SMTP without Authentication and no SSL"
                Send-MailMessage -SmtpServer $SMTPServer -To $Recipient -From $SMTPSender -Subject $f_Subject -Body $HTMLBody -BodyAsHtml -Priority high -Port $SMTPPort
            }
        }
    }
    catch {
        Write-au2matorLog -Type WARNING -Text "Error on sending Mail"
        Write-au2matorLog -Type WARNING -Text $Error
    }

}
#endregion Functions


#region CustomFunctions

#endregion CustomFunctions

#region Script
Write-au2matorLog -Type INFO -Text "Start Script"


if ($DoImportPSSession) {

    Write-au2matorLog -Type INFO -Text "Import-Pssession"
    $PSSession = New-PSSession -ComputerName $PSRemotingServer
    Import-PSSession -Session $PSSession -DisableNameChecking -AllowClobber
}

#Check for Modules if installed
Write-au2matorLog -Type INFO -Text "Try to install all PowerShell Modules"
foreach ($Module in $Modules) {
    if (Get-Module -ListAvailable -Name $Module) {
        Write-au2matorLog -Type INFO -Text "Module is already installed:  $Module"
    }
    else {
        Write-au2matorLog -Type INFO -Text "Module is not installed, try simple method:  $Module"
        try {

            Install-Module $Module -Force -Confirm:$false
            Write-au2matorLog -Type INFO -Text "Module was installed the simple way:  $Module"

        }
        catch {
            Write-au2matorLog -Type INFO -Text "Module is not installed, try the advanced way:  $Module"
            try {
                [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
                Install-PackageProvider -Name NuGet  -MinimumVersion 2.8.5.201 -Force
                Install-Module $Module -Force -Confirm:$false
                Write-au2matorLog -Type INFO -Text "Module was installed the advanced way:  $Module"

            }
            catch {
                Write-au2matorLog -Type ERROR -Text "could not install module:  $Module"
                $au2matorReturn = "could not install module:  $Module, Error: $Error"
                $AdditionalHTML = "could not install module:  $Module, Error: $Error
                "
                $Status = "ERROR"
            }
        }
    }
    Write-au2matorLog -Type INFO -Text "Import Module:  $Module"
    Import-module $Module
}

#region CustomCode
Write-au2matorLog -Type INFO -Text "Start Custom Code"



try {
    Write-au2matorLog -Type INFO -Text "Find Primary User from AD and Build String"  
    $Sam = (get-ADUser -Identity $c_User).SamAccountName
    $Domain = (Get-ADDomain).NetBIOSName
    $UserString = $Domain + "\" + $Sam
    Write-au2matorLog -Type INFO -Text "Built the following UserString: $($UserString)"  

    
    try {
        $ComputerRessourceID = (Get-WmiObject -Namespace "root\SMS\site_$CMSiteCode" -Class SMS_R_System -ComputerName $SiteServer -Filter "Name like '$c_Client'").ResourceId
        Write-au2matorLog -Type INFO -Text "Found Computer ID: $($ComputerRessourceID)"  


        if ($c_Replace -eq "True") {
            Write-au2matorLog -Type INFO -Text "Replace Switch is true, so delete all Primary Users" 
            [array]$Relations = Get-WmiObject -ComputerName $SiteServer -Namespace "root\SMS\Site_$CMSiteCode" -Query "select * from SMS_UserMachineRelationship WHERE Resourceid = '$ComputerRessourceID' AND IsActive = '1' AND Types = '1'"
            
            foreach ($relation in $Relations) {
                $Relation.psbase.delete()
            }

        }
    
        $UserName = $UserString
        $WMIConnection = [WmiClass]"\\$($SiteServer)\root\SMS\site_$($CMSiteCode):SMS_UserMachineRelationship";  
        $NewRelation = $WMIConnection.psbase.GetMethodParameters("CreateRelationship");
        $NewRelation.MachineResourceId = $ComputerRessourceID;
    
        $NewRelation.SourceId = 2;
        $NewRelation.TypeId = 1;
        $NewRelation.UserAccountName = $UserName;
        $WMIConnection.psbase.InvokeMethod("CreateRelationship", $NewRelation, $null)



        Write-au2matorLog -Type INFO -Text "Status is COMPLETED"

        $au2matorReturn = "Set Primary User $($UserString) for Computer $($c_Client)"
        $AdditionalHTML = "Set Primary User $($UserString) for Computer $($c_Client)
            <br>
                "
        $Status = "COMPLETED"
     
    }
    catch {
        Write-au2matorLog -Type ERROR -Text "Error on setting Primary User, Error: $Error"       
    
        $au2matorReturn = "Error on setting Primary User, Error: $Error"
        $AdditionalHTML = "Error on setting Primary User
            <br>
            Error: $Error
                "
        $Status = "ERROR"
    }

}
catch {
    Write-au2matorLog -Type ERROR -Text "Error to get User and Domain Details, Error: $Error"

    $au2matorReturn = "Error to get User and Domain Details, Error: $Error"
    $AdditionalHTML = "Error to get User and Domain Details
        <br>
        Error: $Error
            "
    $Status = "ERROR"
}


#endregion CustomCode
#endregion Script

#region Return


Write-au2matorLog -Type INFO -Text "Service finished"

if ($SendMailToInitiatedByUser) {
    Write-au2matorLog -Type INFO -Text "Send Mail to Initiated By User"

    $UserInput = Get-UserInput -RequestID $RequestId
    $HTML = Get-MailContent -RequestID $RequestId -RequestTitle $Service -EndDate $UserInput.ApprovedTime -TargetUserId $UserInput.TargetUserId -InitiatedBy $UserInput.InitiatedBy -Status $Status -PortalURL $PortalURL  -AdditionalHTML $AdditionalHTML -InputHTML $UserInput.html
    Send-ServiceMail -HTMLBody $HTML -RequestID $RequestId -Recipient $($UserInput.MailInitiatedBy) -RequestStatus $Status -ServiceName $Service
}

if ($SendMailToTargetUser) {
    Write-au2matorLog -Type INFO -Text "Send Mail to Target User"

    $UserInput = Get-UserInput -RequestID $RequestId
    $HTML = Get-MailContent -RequestID $RequestId -RequestTitle $Service -EndDate $UserInput.ApprovedTime -TargetUserId $UserInput.TargetUserId -InitiatedBy $UserInput.InitiatedBy -Status $Status -PortalURL $PortalURL -AdditionalHTML $AdditionalHTML -InputHTML $UserInput.html
    Send-ServiceMail -HTMLBody $HTML -RequestID $RequestId -Recipient $($UserInput.MailTarget) -RequestStatus $Status -ServiceName $Service
}

return $au2matorReturn
#endregion Return
