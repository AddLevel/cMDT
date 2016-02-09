@{

# Script module or binary module file associated with this manifest.
RootModule = 'cMDT.psm1'

DscResourcesToExport = @('cMDTApplication','cMDTBootstrapIni','cMDTCustomize','cMDTCustomSettingsIni','cMDTDirectory','cMDTDriver','cMDTOperatingSystem','cMDTPersistentDrive','cMDTPreReqs','cMDTTaskSequence','cMDTUpdateBootImage','cWDSBootImage','cWDSConfiguration')

# Version number of this module.
ModuleVersion = '1.0.0.0'

# ID used to uniquely identify this module
GUID = '81624038-5e71-40f8-8905-b1a87afe22d7'

# Author of this module
Author = 'Addlevel Automation Team'

# Company or vendor of this module
CompanyName = 'Addlevel'

# Copyright statement for this module
Copyright = '2016 MIT License'

# Description of the functionality provided by this module
Description = 'A DSC Module for configuring Microsoft Deployment Toolkit (MDT)'

# Minimum version of the Windows PowerShell engine required by this module
PowerShellVersion = '5.0'

CmdletsToExport   = "*"
FunctionsToExport = "*"

# Name of the Windows PowerShell host required by this module
# PowerShellHostName = ''
}