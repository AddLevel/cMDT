﻿$Modules    = @(

    @{
       Name    = "xSmbShare"
       Version = "1.1.0.0"
    },
    
    @{
       Name    = "PowerShellAccessControl"
       Version = "3.0.135.20150413"
    }

)

Configuration DeployMDTServerContract
{
    Param(
        [PSCredential]
        $Credentials
    )

    #NOTE: Every Module must be constant, DSC Bug?!
    Import-DscResource –ModuleName PSDesiredStateConfiguration
    Import-DscResource -ModuleName xSmbShare
    Import-DscResource -ModuleName PowerShellAccessControl
    Import-DscResource -ModuleName cMDT

    node $AllNodes.Where{$_.Role -match "MDT Server"}.NodeName
    {

        $SecurePassword = ConvertTo-SecureString $Node.MDTLocalPassword -AsPlainText -Force
        $UserName       = $Node.MDTLocalAccount
        $Credentials    = New-Object System.Management.Automation.PSCredential -ArgumentList $UserName, $SecurePassword

        [string]$separator = ""
        [bool]$weblink = $false
        If ($Node.SourcePath -like "*/*") { $weblink = $true }

        LocalConfigurationManager          {
            RebootNodeIfNeeded = $AllNodes.RebootNodeIfNeeded            ConfigurationMode  = $AllNodes.ConfigurationMode           }

        cMDTPreReqs MDTPreReqs {
            Ensure       = "Present"            
            DownloadPath = $Node.TempLocation
        }

        User MDTAccessAccount {
            Ensure                 = "Present"
            UserName               = $Node.MDTLocalAccount
            FullName               = $Node.MDTLocalAccount
            Password               = $Credentials
            PasswordChangeRequired = $false
            PasswordNeverExpires   = $true
            Description            = "Managed Client Administrator Account"
            Disabled               = $false
        }

        WindowsFeature NET35 {
            Ensure = "Present"
            Name   = "Net-Framework-Core"
        }

        WindowsFeature WDS {
            Ensure               = "Present"
            Name                 = "WDS"
            IncludeAllSubFeature = $true            LogPath              = "C:\Windows\debug\DSC_WindowsFeature_WindowsDeploymentServices.log"
        }

        cWDSConfiguration wdsConfig {
            Ensure            = "Present"
            RemoteInstallPath = "C:\RemoteInstall"
        }

        Package ADK {            Ensure     = "Present"            Name       = "Windows Assessment and Deployment Kit - Windows 10"            Path       = "$($Node.TempLocation)\Windows Assessment and Deployment Kit\adksetup.exe"            ProductId  = "82daddb6-d4e0-42cb-988d-1e7f5739e155"            Arguments  = "/quiet /features OptionId.DeploymentTools OptionId.WindowsPreinstallationEnvironment"            ReturnCode = 0        }

        Package MDT {
            Ensure     = "Present"
            Name       = "Microsoft Deployment Toolkit 2013 Update 2 (6.3.8330.1000)"
            Path       = "$($Node.TempLocation)\Microsoft Deployment Toolkit\MicrosoftDeploymentToolkit2013_x64.msi"
            ProductId  = "F172B6C7-45DD-4C22-A5BF-1B2C084CADEF"
            ReturnCode = 0
        }

        cMDTDirectory TempFolder
        {
            Ensure = "Present"
            Name   = $Node.TempLocation.Replace("$($Node.TempLocation.Substring(0,2))\","")
            Path   = $Node.TempLocation.Substring(0,2)
        }        cMDTDirectory DeploymentFolder
        {
            Ensure = "Present"
            Name   = $Node.PSDrivePath.Replace("$($Node.PSDrivePath.Substring(0,2))\","")
            Path   = $Node.PSDrivePath.Substring(0,2)
        }

        xSmbShare FolderDeploymentShare
        {
            Ensure                = "Present"
            Name                  = $Node.PSDriveShareName
            Path                  = $Node.PSDrivePath
            FullAccess            = "$env:COMPUTERNAME\$($Node.MDTLocalAccount)"
            FolderEnumerationMode = "AccessBased"
        }

        cAccessControlEntry AssignPermissions
        {
            Path       = $Node.PSDrivePath
            ObjectType = "Directory"
            AceType    = "AccessAllowed"
            Principal  = "$env:COMPUTERNAME\$($Node.MDTLocalAccount)"
            AccessMask = [System.Security.AccessControl.FileSystemRights]::FullControl
        }

        cMDTPersistentDrive DeploymentPSDrive
        {
            Ensure      = "Present"
            Name        = $Node.PSDriveName
            Path        = $Node.PSDrivePath
            Description = $Node.PSDrivePath.Replace("$($Node.PSDrivePath.Substring(0,2))\","")
            NetworkPath = "\\$($env:COMPUTERNAME)\$($Node.PSDriveShareName)"
        }

        ForEach ($OSDirectory in $Node.OSDirectories)   
        {

            [string]$Ensure    = ""
            [string]$OSVersion = ""
            $OSDirectory.GetEnumerator() | % {
                If ($_.key -eq "Ensure")          { $Ensure    = $_.value }
                If ($_.key -eq "OperatingSystem") { $OSVersion = $_.value }
            }

            cMDTDirectory $OSVersion.Replace(' ','')
            {
                Ensure      = $Ensure
                Name        = $OSVersion
                Path        = "$($Node.PSDriveName):\Operating Systems"
                PSDriveName = $Node.PSDriveName
                PSDrivePath = $Node.PSDrivePath
            }

            cMDTDirectory "OOB$($OSVersion.Replace(' ',''))"
            {
                Ensure      = $Ensure
                Name        = "$($OSVersion) x64"
                Path        = "$($Node.PSDriveName):\Out-of-Box Drivers"
                PSDriveName = $Node.PSDriveName
                PSDrivePath = $Node.PSDrivePath
            }

            cMDTDirectory "TS$($OSVersion.Replace(' ',''))"
            {
                Ensure      = $Ensure
                Name        = $OSVersion
                Path        = "$($Node.PSDriveName):\Task Sequences"
                PSDriveName = $Node.PSDriveName
                PSDrivePath = $Node.PSDrivePath
            }

            
            ForEach ($CurrentVendor in $Node.Vendors)
            {

                [string]$EnsureVendor = ""
                [string]$Vendor       = ""
                $CurrentVendor.GetEnumerator() | % {
                    If ($_.key -eq "Ensure") { $EnsureVendor = $_.value }
                    If ($_.key -eq "Vendor") { $Vendor       = $_.value }
                }

                If ($Ensure -eq "Absent")    { $EnsureVendor = "Absent" }

                cMDTDirectory "OOB$($OSVersion.Replace(' ',''))$($Vendor.Replace(' ',''))"
                {
                    Ensure      = $EnsureVendor
                    Name        = $Vendor
                    Path        = "$($Node.PSDriveName):\Out-of-Box Drivers\$OSVersion x64"
                    PSDriveName = $Node.PSDriveName
                    PSDrivePath = $Node.PSDrivePath
                }
            }

        }
        
        cMDTDirectory ApplicationsRef {
            Ensure      = "Present"
            Name        = "Reference Applications"
            Path        = "$($Node.PSDriveName):\Applications"
            PSDriveName = $Node.PSDriveName
            PSDrivePath = $Node.PSDrivePath
        }

        cMDTDirectory ApplicationsCore {
            Ensure      = "Present"
            Name        = "Core Applications"
            Path        = "$($Node.PSDriveName):\Applications"
            PSDriveName = $Node.PSDriveName
            PSDrivePath = $Node.PSDrivePath
        }

        cMDTDirectory ApplicationsDrivers {
            Ensure      = "Present"
            Name        = "Drivers"
            Path        = "$($Node.PSDriveName):\Applications"
            PSDriveName = $Node.PSDriveName
            PSDrivePath = $Node.PSDrivePath
        }

        cMDTDirectory ApplicationsOptional {
            Ensure      = "Present"
            Name        = "Optional"
            Path        = "$($Node.PSDriveName):\Applications"
            PSDriveName = $Node.PSDriveName
            PSDrivePath = $Node.PSDrivePath
        }

        ForEach ($SelectionProfile in $Node.SelectionProfiles)   
        {
            cMDTDirectory "SP$($SelectionProfile.Replace(' ',''))"
            {
                Ensure      = "Present"
                Name        = $SelectionProfile
                Path        = "$($Node.PSDriveName):\Selection Profiles"
                PSDriveName = $Node.PSDriveName
                PSDrivePath = $Node.PSDrivePath
            }
        }

        ForEach ($OperatingSystem in $Node.OperatingSystems)   
        {

            [string]$Ensure     = ""
            [string]$Name       = ""
            [string]$Version    = ""
            [string]$Path       = ""
            [string]$SourcePath = ""

            $OperatingSystem.GetEnumerator() | % {
                If ($_.key -eq "Ensure")     { $Ensure     = $_.value }
                If ($_.key -eq "Name")       { $Name       = $_.value }
                If ($_.key -eq "Version")    { $Version    = $_.value }
                If ($_.key -eq "Path")       { $Path       = "$($Node.PSDriveName):$($_.value)" }
                If ($_.key -eq "SourcePath")
                {
                    If ($weblink)            { $SourcePath = "$($Node.SourcePath)$($_.value.Replace("\","/"))" }
                    Else                     { $SourcePath = "$($Node.SourcePath)$($_.value.Replace("/","\"))" }
                }
            }

            cMDTOperatingSystem $Name.Replace(' ','')
            {
                Ensure       = $Ensure
                Name         = $Name
                Version      = $Version
                Path         = $Path
                SourcePath   = $SourcePath
                PSDriveName  = $Node.PSDriveName
                PSDrivePath  = $Node.PSDrivePath
                TempLocation = $Node.TempLocation
            }
        }

        ForEach ($TaskSequence in $Node.TaskSequences)   
        {

            [string]$Ensure              = ""
            [string]$Name                = ""
            [string]$Path                = ""
            [string]$OperatingSystemPath = ""
            [string]$WIMFileName         = ""
            [string]$ID                  = ""

            $TaskSequence.GetEnumerator() | % {
                If ($_.key -eq "Ensure")              { $Ensure              = $_.value }
                If ($_.key -eq "Name")                { $Name                = $_.value }
                If ($_.key -eq "Path")                { $Path                = "$($Node.PSDriveName):$($_.value)" }
                If ($_.key -eq "OperatingSystemPath") { $OperatingSystemPath = "$($Node.PSDriveName):$($_.value)" }
                If ($_.key -eq "WIMFileName")         { $WIMFileName         = $_.value }
                If ($_.key -eq "ID")                  { $ID                  = $_.value }
            }

            If ($WIMFileName)
            {
                cMDTTaskSequence $Name.Replace(' ','')
                {
                    Ensure      = $Ensure
                    Name        = $Name
                    Path        = $Path
                    WIMFileName = $WIMFileName
                    ID          = $ID
                    PSDriveName = $Node.PSDriveName
                    PSDrivePath = $Node.PSDrivePath
                }
            }
            Else
            {
                cMDTTaskSequence $Name.Replace(' ','')
                {
                    Ensure              = $Ensure
                    Name                = $Name
                    Path                = $Path
                    OperatingSystemPath = $OperatingSystemPath
                    ID                  = $ID
                    PSDriveName         = $Node.PSDriveName
                    PSDrivePath         = $Node.PSDrivePath
                }

            }
        }

        ForEach ($Driver in $Node.Drivers)   
        {

            [string]$Ensure     = ""
            [string]$Name       = ""
            [string]$Version    = ""
            [string]$Path       = ""
            [string]$SourcePath = ""
            [string]$Comment    = ""

            $Driver.GetEnumerator() | % {
                If ($_.key -eq "Ensure")     { $Ensure     = $_.value }
                If ($_.key -eq "Name")       { $Name       = $_.value }
                If ($_.key -eq "Version")    { $Version    = $_.value }
                If ($_.key -eq "Path")       { $Path       = "$($Node.PSDriveName):$($_.value)" }
                If ($_.key -eq "SourcePath")
                {
                    If ($weblink)            { $SourcePath = "$($Node.SourcePath)$($_.value.Replace("\","/"))" }
                    Else                     { $SourcePath = "$($Node.SourcePath)$($_.value.Replace("/","\"))" }
                }
                If ($_.key -eq "Comment")    { $Comment    = $_.value }
            }

            cMDTDriver $Name.Replace(' ','')
            {
                Ensure       = $Ensure
                Name         = $Name
                Version      = $Version
                Path         = $Path
                SourcePath   = $SourcePath
                Comment      = $Comment
                Enabled      = "True"
                PSDriveName  = $Node.PSDriveName
                PSDrivePath  = $Node.PSDrivePath
                TempLocation = $Node.TempLocation
            }
        }

        ForEach ($Application in $Node.Applications)   
        {

            [string]$Ensure                = ""
            [string]$Name                  = ""
            [string]$Version               = ""
            [string]$Path                  = ""
            [string]$ShortName             = ""
            [string]$Publisher             = ""
            [string]$Language              = ""
            [string]$CommandLine           = ""
            [string]$WorkingDirectory      = ""
            [string]$ApplicationSourcePath = ""
            [string]$DestinationFolder     = ""

            $Application.GetEnumerator() | % {
                If ($_.key -eq "Ensure")                { $Ensure                = $_.value }
                If ($_.key -eq "Name")                  { $Name                  = $_.value }
                If ($_.key -eq "Version")               { $Version               = $_.value }
                If ($_.key -eq "Path")                  { $Path                  = "$($Node.PSDriveName):$($_.value)" }
                If ($_.key -eq "ShortName")             { $ShortName             = $_.value }
                If ($_.key -eq "Publisher")             { $Publisher             = $_.value }
                If ($_.key -eq "Language")              { $Language              = $_.value }
                If ($_.key -eq "CommandLine")           { $CommandLine           = $_.value }
                If ($_.key -eq "WorkingDirectory")      { $WorkingDirectory      = $_.value }
                If ($_.key -eq "ApplicationSourcePath")
                {
                    If ($weblink)                       { $ApplicationSourcePath = "$($Node.SourcePath)$($_.value.Replace("\","/"))" }
                    Else                                { $ApplicationSourcePath = "$($Node.SourcePath)$($_.value.Replace("/","\"))" }
                }
                If ($_.key -eq "DestinationFolder")     { $DestinationFolder     = $_.value }
            }

            cMDTApplication $Name.Replace(' ','')
            {
                Ensure                = $Ensure
                Name                  = $Name
                Version               = $Version
                Path                  = $Path
                ShortName             = $ShortName
                Publisher             = $Publisher
                Language              = $Language
                CommandLine           = $CommandLine
                WorkingDirectory      = $WorkingDirectory
                ApplicationSourcePath = $ApplicationSourcePath
                DestinationFolder     = $DestinationFolder
                Enabled               = "True"
                PSDriveName           = $Node.PSDriveName
                PSDrivePath           = $Node.PSDrivePath
                TempLocation          = $Node.TempLocation
            }
        }

        ForEach ($CustomSetting in $Node.CustomSettings)   
        {

            [string]$Ensure     = ""
            [string]$Name       = ""
            [string]$Version    = ""
            [bool]$Protected    = $False
            [string]$SourcePath = ""

            $CustomSetting.GetEnumerator() | % {
                If ($_.key -eq "Ensure")     { $Ensure     = $_.value }
                If ($_.key -eq "Name")       { $Name       = $_.value }
                If ($_.key -eq "Version")    { $Version    = $_.value }
                If ($_.key -eq "Protected")  {
                    If ($_.value)            { $Protected  = $_.value }
                }
                If ($_.key -eq "SourcePath")
                {
                    If ($weblink)            { $SourcePath = "$($Node.SourcePath)$($_.value.Replace("\","/"))" }
                    Else                     { $SourcePath = "$($Node.SourcePath)$($_.value.Replace("/","\"))" }
                }
            }

            cMDTCustomize $Name.Replace(' ','')
            {
                Ensure       = $Ensure
                Name         = $Name
                Version      = $Version
                SourcePath   = $SourcePath
                Path         = $Node.PSDrivePath
                TempLocation = $Node.TempLocation
                Protected    = $Protected
            }
        }

        ForEach ($IniFile in $Node.CustomizeIniFiles)   
        {

            [string]$Ensure     = ""
            [string]$Name       = ""
            [string]$Path       = ""
            [string]$DeployRoot = ""
            [string]$JoinDomain = ""
            [string]$DomainAdmin = ""
            [string]$DomainAdminDomain = ""
            [string]$DomainAdminPassword = ""
            [string]$MachineObjectOU = ""

            $IniFile.GetEnumerator() | % {
                If ($_.key -eq "Ensure")              { $Ensure              = $_.value }
                If ($_.key -eq "Name")                { $Name                = $_.value }
                If ($_.key -eq "Path")                { $Path                = "$($Node.PSDrivePath)$($_.value)" }
                If ($_.key -eq "DeployRoot")          { $DeployRoot          = "$($Node.SourcePath)$($_.value)" }
                If ($_.key -eq "JoinDomain")          { $JoinDomain          = $_.value }
                If ($_.key -eq "DomainAdmin")         { $DomainAdmin         = $_.value }
                If ($_.key -eq "DomainAdminDomain")   { $DomainAdminDomain   = $_.value }
                If ($_.key -eq "DomainAdminPassword") { $DomainAdminPassword = $_.value }
                If ($_.key -eq "MachineObjectOU")     { $MachineObjectOU     = $_.value }
            }

            If ($Name -eq "CustomSettingsIni")
            {
                cMDTCustomSettingsIni ini {
                    Ensure  = $Ensure
                    Path    = $Path
                    Content = @"
[Settings]
Priority=SetModelAlias, Init, ModelAlias, Default
Properties=ModelAlias, ComputerSerialNumber

[SetModelAlias]
UserExit=ModelAliasExit.vbs
ModelAlias=#SetModelAlias()#

[Init]
ComputerSerialNumber=#Mid(Replace(Replace(oEnvironment.Item("SerialNumber")," ",""),"-",""),1,11)#

[Default]
OSInstall=Y
_SMSTSORGNAME=Company
HideShell=YES
DisableTaskMgr=YES
ApplyGPOPack=NO
UserDataLocation=NONE
DoCapture=NO
OSDComputerName=CLI%ComputerSerialNumber%

;Local admin password
AdminPassword=$($Node.MDTLocalPassword)
SLShare=%DeployRoot%\Logs

OrgName=Company
Home_Page=http://companyURL

;Enable or disable options:
SkipAdminPassword=NO
SkipApplications=YES
SkipBitLocker=NO
SkipCapture=YES
SkipComputerBackup=YES
SkipComputerName=NO
SkipDomainMembership=NO
SkipFinalSummary=NO
SkipLocaleSelection=NO
SkipPackageDisplay=YES
SkipProductKey=YES
SkipRoles=YES
SkipSummary=NO
SkipTimeZone=NO
SkipUserData=YES
SkipTaskSequence=NO

;DomainJoin
JoinDomain=$($JoinDomain)
DomainAdmin=$($DomainAdmin)
DomainAdminDomain=$($DomainAdminDomain)
DomainAdminPassword=$($DomainAdminPassword)
MachineObjectOU=$($MachineObjectOU)

;TimeZone settings
TimeZoneName=W. Europe Standard Time

WSUSServer=http://fqdn:port

;Example keyboard layout.
UserLocale=en-US
KeyboardLocale=en-US
UILanguage=en-US

;Drivers
DriverSelectionProfile=Nothing

;DriverInjectionMode=ALL

FinishAction=RESTART
"@
                }
            }

            If ($Name -eq "BootstrapIni")
            {
                cMDTBootstrapIni ini {
                    Ensure  = $Ensure
                    Path    = $Path
                    Content = @"
[Settings]
Priority=Default

[Default]
DeployRoot=\\$($Node.NodeName)\$($Node.PSDriveShareName)
SkipBDDWelcome=YES

;Kundunik lokal användare
UserID=$($Node.MDTLocalAccount)
UserPassword=$($Node.MDTLocalPassword)
UserDomain=$($env:COMPUTERNAME)

;Swedish Keyboard Layout
KeyboardLocalePE=041d:0000041d
"@
                }
            }

        }

        ForEach ($Image in $Node.BootImage)   
        {

            [string]$Ensure     = ""
            [string]$Name       = ""
            [string]$Version    = ""
            [string]$Path       = ""
            [string]$ImageName  = ""

            $Image.GetEnumerator() | % {
                If ($_.key -eq "Ensure")     { $Ensure     = $_.value }
                If ($_.key -eq "Name")       { $Name       = $_.value }
                If ($_.key -eq "Version")    { $Version    = $_.value }
                If ($_.key -eq "Path")       { $Path       = "$($Node.PSDrivePath)$($_.value)" }
                If ($_.key -eq "ImageName")  { $ImageName  = $_.value }
            }

            $ImageName  = "$($ImageName) v$($Version)"

            cMDTUpdateBootImage updateBootImage {
                Version             = $Version
                PSDeploymentShare   = $Node.PSDriveName
                Force               = $true
                Compress            = $true
                DeploymentSharePath = $Node.PSDrivePath

            }                    cWDSBootImage wdsBootImage {
                Ensure    = $Ensure
                Path      = $Path
                ImageName = $ImageName
            }

        }

    }
}

#Get configuration data
$ConfigurationData = Invoke-Expression (Get-Content -Path "$PSScriptRoot\Deploy_MDT_Server_ConfigurationData.psd1" -Raw)

#Create DSC MOF job
DeployMDTServerContract -OutputPath "$PSScriptRoot\MDT-Deploy_MDT_Server" -ConfigurationData $ConfigurationData

#Set DSC LocalConfigurationManager
Set-DscLocalConfigurationManager -Path "$PSScriptRoot\MDT-Deploy_MDT_Server" -Verbose

#Start DSC MOF job
Start-DscConfiguration -Wait -Force -Verbose -ComputerName "$env:computername" -Path "$PSScriptRoot\MDT-Deploy_MDT_Server"

Write-Host ""
Write-Host "AddLevel Deploy MDT Server Builder completed!"