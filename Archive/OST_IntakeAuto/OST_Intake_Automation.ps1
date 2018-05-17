<#=========================================================================
###			Sandbox for OST Enrichment and Onboarding Automation
###
###	  Prerequisites of Script Operation
#       (1) CR description has the following format, and is copied into working deployment directory as a text file
#            Attr: Val
#            blossom_id: CI02817116
#            blossom_name: OpenStack
#            owner: Z001LQD
#            project_name: openstack-ci
#            roles:
#            project_admin: Add and remove users to the project, modify project quota, or delete the project
#            member: Can view, create, modify, delete resources in the project
#            nuid: NUIDs can view, create, modify, delete resources in the project
#       (2) There is a csv file with the current OpenStack entitlements in the working directory
#       (3) CSV file has format:
#            Beginning first row of content with:
#            CATALOG_ID,ENTITY_TYPE,ENTITY_KEY,PARENT_ENTITY_TYPE,PARENT_ENTITY_K
#       (4) current Powershell is V4 or newer for methods called
#
#==========================================================================#>

##########################################################
###			Directory Ops & Init Var
##########################################################
###			Directory Op
##########################################################
$curDir = $PSSCriptRoot          # set variable to current deployment directory location
$dateText = Get-Date -format yyyyMMdd
$outputDir = $curDir + "\Output_" + $dateText + "\"
$inputDir =  $curDir + "\Input\"
if(test-path $outputDir){ }    ###     test input and output directories
    else{New-Item $outputDir -type Directory}

###	Begin logging file
$logFile = ($outputDir + "LogFile_Run" + $dateText + ".txt")
"OST Role Intake Automation `r`n" + "Log File for Run on: " > $logFile
Add-Content -Path $logFile -Value (Get-Date)
if(test-path $inputDir){ }     ###     test output directory path, if not existent create it.
    else{
        "Critical error detected during processing`r`nError: No Input Directory Found" >> $logFile
        "Exit Process" >> $logFile
        exit}                   #test input directory path, if none then quit program

###			Init Var
##########################################################
### Find .txt and .csv files & Import
###     assign as variables for SN CR
###     description & BI Publisher CSV files
$oimEntDetailDir =  get-childitem -Path ($inputDir + '*.csv') | select-object name
$oimEntDetailDir = $inputDir + $oimEntDetailDir.Name
$AllTextFiles = get-childitem -Path ($inputDir + '*.txt') | select-object name
###     Remove leading empty rows from BiPub csv export
$cont = Get-Content $oimEntDetailDir # read from csv  as if text file
$cont = $cont.Where({ $_ -like "*CATALOG_ID,ENTITY_TYPE*" },'SkipUntil') #skip leading empties until the catalog id header is found
$cont > $oimEntDetailDir #write over csv as new csv with headers as first line
$Obj_oimEnt = import-csv ($oimEntDetailDir)

### Create bulk ent enrichment forms
$entEnrich_Desc=@()
$MetaDataEnrich_CatSync=@()
$OSTrole_CreationForm=@()
$ApproverRole_CreationForm=@()
$ApproverRole_UserAddForm = @()

if((get-childitem -Path ($inputDir + '*.txt') | select-object name | Measure-Object).Count -eq 0){
    "Critical error detected during processing`r`nError: No CR files in Input Folder" >> $logFile
    "Exit Process" >> $logFile
    exit
}
if(($Obj_oimEnt | Measure-Object).Count -eq 0){
    "Critical error detected during processing`r`nError: No BiPub file in Input Folder" >> $logFile
    "Exit Process" >> $logFile
    exit
}

"`rInput Files Read Successfully`r`nBegin File Processing`r`n" >> $logFile

##########################################################
###			Flat Feed File Creator
##########################################################
If ((get-childitem -Path ($inputDir + '*.txt') | select-object name | Measure-Object).Count -eq 1) { ## If there is only one entry then do for one row
    $descDir = $inputDir + $AllTextFiles.Name
    $Obj_desc = import-csv ($descDir) -delimiter ':'
    ###    Assign variables to CR description values from service now form text file
    $projName = $Obj_desc -match 'project_name'; $projName = $projName.Val
    $BlossID = $Obj_desc | where-object -property Attr -eq "blossom_id"; $BlossID = $BlossID.Val
    $BlossName = $Obj_desc | where-object -property Attr -eq "blossom_name"; $BlossName = $BlossName.Val
    $owner = $Obj_desc | where-object -property Attr -eq "owner"; $owner = $owner.Val.ToUpper()

    "`r`n############################################">> $logFile
    "File Read: "+$descDir >> $logFile
    if ($projName -eq $null -Or $BlossID -eq $null -or $BlossName -eq $null -or $owner -eq $null) {
        "Critical error detected during processing" >> $logFile
        "Error: Attributes missing from CR Description file">> $logFile
        "`tProjectName, BlossomID, BlossomName, Owner">> $logFile
        "`t" + $projName +","+ $BlossID +","+ $BlossName +","+ $owner>> $logFile
        "File Not Processed" >> $logFile
        "############################################`r`n">> $logFile
        break
    }

    for ($i=$Obj_desc.Attr.IndexOf("roles")+1; $i -le $Obj_desc.Attr.count -1; $i++){
        ##########################################################
        ###     For each OST role to be enriched and onboarded:
        ###              in the current cycle of CR
        ##########################################################

        ###     Find associated OST Ent_Name for the this run
        $entDisplayName = $projName + "::" + $Obj_desc.Attr[$i]
        $catalogEntity = $Obj_oimEnt  |  Where-Object {
            ($_.IS_DELETED -eq "0") -and ($_.ENTITY_TYPE -eq "Entitlement") -and ($_.ENTITY_DISPLAY_NAME -eq  $entDisplayName)
            }
        if ($catalogEntity.ENTITY_KEY -eq $null) {
            "Processing error detected" >> $logFile
            "Error: No Entitlement Match Found">> $logFile
            "`tError detected for Entity without match in BiPublisher Report: "+$entDisplayName>> $logFile
            "Processing of entity skipped`r`n" >> $logFile
            continue
        }

        ###     Create EntEnrichment Object for Description CSV
        $obj = New-Object -TypeName PSObject
        $obj | Add-Member -MemberType NoteProperty -Name "Type" -Value "Entitlement"
        $obj | Add-Member -MemberType NoteProperty -Name "Role Name" -Value ""
        $obj | Add-Member -MemberType NoteProperty -Name "Application" -Value "OpenStackProd"
        $obj | Add-Member -MemberType NoteProperty -Name "Entitlement" -Value $catalogEntity.ENTITY_NAME
        $obj | Add-Member -MemberType NoteProperty -Name "Attribute Name" -Value "Description"
        $obj | Add-Member -MemberType NoteProperty -Name "Value" -Value ($Obj_desc.Val[$i] -replace ',','')
        $entEnrich_Desc += $obj
        clear-variable obj

        ###     Create EntEnrichment Object for Metadata CSV
        $obj = New-Object -TypeName PSObject
        $obj | Add-Member -MemberType NoteProperty -Name "ENTITY_KEY" -Value $catalogEntity.ENTITY_KEY
        $obj | Add-Member -MemberType NoteProperty -Name "ENTITY_TYPE" -Value "Entitlement"
        $obj | Add-Member -MemberType NoteProperty -Name "ENTITY_NAME" -Value $catalogEntity.ENTITY_NAME
        $obj | Add-Member -MemberType NoteProperty -Name "IS_REQUESTABLE" -Value "0"
        $obj | Add-Member -MemberType NoteProperty -Name "CATEGORY" -Value "Entitlement"
        $obj | Add-Member -MemberType NoteProperty -Name "APPROVER_ROLE" -Value ""
        $obj | Add-Member -MemberType NoteProperty -Name "CERTIFIER_USER" -Value ("NeedInput-ConvertToKey-" + $owner)
        $obj | Add-Member -MemberType NoteProperty -Name "ENTITLEMENTAPPROVERGROUPREQUIR" -Value "FALSE"
        $obj | Add-Member -MemberType NoteProperty -Name "BLOSSOMCIID" -Value $BlossID
        $obj | Add-Member -MemberType NoteProperty -Name "BLOSSOMAPPLICATIONNAME" -Value $BlossName
        $MetaDataEnrich_CatSync += $obj
        clear-variable obj

        ###     Create OST Role creation form
        $obj = New-Object -TypeName PSObject
        $obj | Add-Member -MemberType NoteProperty -Name "Business Role" -Value ("OST-d1-" + $projName + "-" + $Obj_desc.Attr[$i])
        $obj | Add-Member -MemberType NoteProperty -Name "Business Role Description" -Value ("Application level requestable role that " + ($Obj_desc.Val[$i] -replace ',','') + " for any user in the project")
        $obj | Add-Member -MemberType NoteProperty -Name "System" -Value "OpenStack_Prod"
        $obj | Add-Member -MemberType NoteProperty -Name "Task Role Technical Name" -Value $catalogEntity.ENTITY_NAME
        $OSTrole_CreationForm += $obj
        clear-variable obj

        ###     Create Role enrichment Object for Metadata CSV
        $obj = New-Object -TypeName PSObject
        $obj | Add-Member -MemberType NoteProperty -Name "ENTITY_KEY" -Value ("NeedInput-ConvertToKey-" + ("OST-d1-" + $projName + "-" + $Obj_desc.Attr[$i]))
        $obj | Add-Member -MemberType NoteProperty -Name "ENTITY_TYPE" -Value "Role"
        $obj | Add-Member -MemberType NoteProperty -Name "ENTITY_NAME" -Value ("OST-d1-" + $projName + "-" + $Obj_desc.Attr[$i])
        $obj | Add-Member -MemberType NoteProperty -Name "IS_REQUESTABLE" -Value "1"
        $obj | Add-Member -MemberType NoteProperty -Name "CATEGORY" -Value "Requestable Role"
        $obj | Add-Member -MemberType NoteProperty -Name "APPROVER_ROLE" -Value ("NeedInput-ConvertToKey-" + ("Approvers_OpenStack_" + $projName))
        $obj | Add-Member -MemberType NoteProperty -Name "CERTIFIER_USER" -Value ("NeedInput-ConvertToKey-" + $owner)
        $obj | Add-Member -MemberType NoteProperty -Name "ENTITLEMENTAPPROVERGROUPREQUIR" -Value "TRUE"
        $obj | Add-Member -MemberType NoteProperty -Name "BLOSSOMCIID" -Value $BlossID
        $obj | Add-Member -MemberType NoteProperty -Name "BLOSSOMAPPLICATIONNAME" -Value $BlossName
        $MetaDataEnrich_CatSync += $obj
        clear-variable obj
    }
    ##########################################################
    ###     Foreach tenant (ie text file in input)
    ##########################################################
    ###     Create ApproverGroup Creation Form
    $obj = New-Object -TypeName PSObject
    $obj | Add-Member -MemberType NoteProperty -Name "Role Name" -Value ("Approvers_OpenStack_" + $projName)
    $obj | Add-Member -MemberType NoteProperty -Name "Role Display Name" -Value ("Approvers_OpenStack_" + $projName)
    $obj | Add-Member -MemberType NoteProperty -Name "Role E-Mail" -Value ""
    $obj | Add-Member -MemberType NoteProperty -Name "Role Description" -Value "Provides access to approve requests for the OpenStack requestable roles for the project name listed in this approver role name"
    $obj | Add-Member -MemberType NoteProperty -Name "Role Category" -Value "Approver Role"
    $obj | Add-Member -MemberType NoteProperty -Name "OwnedBy" -Value $owner
    $ApproverRole_CreationForm += $obj
    clear-variable obj

    ###     Create ApproverGroup BulkAddUser Form
    $obj = New-Object -TypeName PSObject
    $obj | Add-Member -MemberType NoteProperty -Name "USERLOGIN" -Value $owner
    $obj | Add-Member -MemberType NoteProperty -Name "ACCESSTYPE" -Value "ROLE"
    $obj | Add-Member -MemberType NoteProperty -Name "ACCESS" -Value ("Approvers_OpenStack_" + $projName)
    $obj | Add-Member -MemberType NoteProperty -Name "APPINSTANCE" -Value ""
    $obj | Add-Member -MemberType NoteProperty -Name "JUSTIFICATION" -Value "New approver role for openstack"
    $obj | Add-Member -MemberType NoteProperty -Name "OPERATION" -Value "ADD"
    $ApproverRole_UserAddForm += $obj
    clear-variable obj

    ###     Create ApproverGroup enrichment Object for Metadata CSV
    $obj = New-Object -TypeName PSObject
    $obj | Add-Member -MemberType NoteProperty -Name "ENTITY_KEY" -Value ("NeedInput-ConvertToKey-" + ("Approvers_OpenStack_" + $projName))
    $obj | Add-Member -MemberType NoteProperty -Name "ENTITY_TYPE" -Value "Role"
    $obj | Add-Member -MemberType NoteProperty -Name "ENTITY_NAME" -Value ("Approvers_OpenStack_" + $projName)
    $obj | Add-Member -MemberType NoteProperty -Name "IS_REQUESTABLE" -Value "1"
    $obj | Add-Member -MemberType NoteProperty -Name "CATEGORY" -Value "Approver Role"
    $obj | Add-Member -MemberType NoteProperty -Name "APPROVER_ROLE" -Value ("NeedInput-ConvertToKey-" + ("Approvers_OpenStack_" + $projName))
    $obj | Add-Member -MemberType NoteProperty -Name "CERTIFIER_USER" -Value ("NeedInput-ConvertToKey-" + $owner)
    $obj | Add-Member -MemberType NoteProperty -Name "ENTITLEMENTAPPROVERGROUPREQUIR" -Value "TRUE"
    $obj | Add-Member -MemberType NoteProperty -Name "BLOSSOMCIID" -Value $BlossID
    $obj | Add-Member -MemberType NoteProperty -Name "BLOSSOMAPPLICATIONNAME" -Value $BlossName
    $MetaDataEnrich_CatSync += $obj
    clear-variable obj

    "File Processing Complete" >> $logFile
    "############################################`r`n">> $logFile
} Else {
    for ($ii=0; $ii+1 -le $AllTextFiles.count; $ii++){
        $descDir = $inputDir + $AllTextFiles.Name[$ii]
        $Obj_desc = import-csv ($descDir) -delimiter ':'
        ###    Assign variables to CR description values from service now form text file
        $projName = $Obj_desc -match 'project_name'; $projName = $projName.Val
        $BlossID = $Obj_desc | where-object -property Attr -eq "blossom_id"; $BlossID = $BlossID.Val
        $BlossName = $Obj_desc | where-object -property Attr -eq "blossom_name"; $BlossName = $BlossName.Val
        $owner = $Obj_desc | where-object -property Attr -eq "owner"; $owner = $owner.Val.ToUpper()

        "`r`n############################################">> $logFile
        "File Read: "+$descDir >> $logFile
        if ($projName -eq $null -Or $BlossID -eq $null -or $BlossName -eq $null -or $owner -eq $null) {
            "Critical error detected during processing" >> $logFile
            "Error: Attributes missing from CR Description file">> $logFile
            "`tProjectName, BlossomID, BlossomName, Owner">> $logFile
            "`t" + $projName +","+ $BlossID +","+ $BlossName +","+ $owner>> $logFile
            "File Not Processed" >> $logFile
            "############################################`r`n">> $logFile
            continue
        }

        for ($i=$Obj_desc.Attr.IndexOf("roles")+1; $i -le $Obj_desc.Attr.count -1; $i++){
            ##########################################################
            ###     For each OST role to be enriched and onboarded:
            ###              in the current cycle of CR
            ##########################################################

            ###     Find associated OST Ent_Name for the this run
            $entDisplayName = $projName + "::" + $Obj_desc.Attr[$i]
            $catalogEntity = $Obj_oimEnt  |  Where-Object {
                ($_.IS_DELETED -eq "0") -and ($_.ENTITY_TYPE -eq "Entitlement") -and ($_.ENTITY_DISPLAY_NAME -eq  $entDisplayName)
                }
            if ($catalogEntity.ENTITY_KEY -eq $null) {
                "Processing error detected" >> $logFile
                "Error: No Entitlement Match Found">> $logFile
                "`tError detected for Entity without match in BiPublisher Report: "+$entDisplayName>> $logFile
                "Processing of entity skipped`r`n" >> $logFile
                continue
            }
            ###     Create EntEnrichment Object for Description CSV
            $obj = New-Object -TypeName PSObject
            $obj | Add-Member -MemberType NoteProperty -Name "Type" -Value "Entitlement"
            $obj | Add-Member -MemberType NoteProperty -Name "Role Name" -Value ""
            $obj | Add-Member -MemberType NoteProperty -Name "Application" -Value "OpenStackProd"
            $obj | Add-Member -MemberType NoteProperty -Name "Entitlement" -Value $catalogEntity.ENTITY_NAME
            $obj | Add-Member -MemberType NoteProperty -Name "Attribute Name" -Value "Description"
            $obj | Add-Member -MemberType NoteProperty -Name "Value" -Value ($Obj_desc.Val[$i] -replace ',','')
            $entEnrich_Desc += $obj
            clear-variable obj

            ###     Create EntEnrichment Object for Metadata CSV
            $obj = New-Object -TypeName PSObject
            $obj | Add-Member -MemberType NoteProperty -Name "ENTITY_KEY" -Value $catalogEntity.ENTITY_KEY
            $obj | Add-Member -MemberType NoteProperty -Name "ENTITY_TYPE" -Value "Entitlement"
            $obj | Add-Member -MemberType NoteProperty -Name "ENTITY_NAME" -Value $catalogEntity.ENTITY_NAME
            $obj | Add-Member -MemberType NoteProperty -Name "IS_REQUESTABLE" -Value "0"
            $obj | Add-Member -MemberType NoteProperty -Name "CATEGORY" -Value "Entitlement"
            $obj | Add-Member -MemberType NoteProperty -Name "APPROVER_ROLE" -Value ""
            $obj | Add-Member -MemberType NoteProperty -Name "CERTIFIER_USER" -Value ("NeedInput-ConvertToKey-" + $owner)
            $obj | Add-Member -MemberType NoteProperty -Name "ENTITLEMENTAPPROVERGROUPREQUIR" -Value "FALSE"
            $obj | Add-Member -MemberType NoteProperty -Name "BLOSSOMCIID" -Value $BlossID
            $obj | Add-Member -MemberType NoteProperty -Name "BLOSSOMAPPLICATIONNAME" -Value $BlossName
            $MetaDataEnrich_CatSync += $obj
            clear-variable obj

            ###     Create OST Role creation form
            $obj = New-Object -TypeName PSObject
            $obj | Add-Member -MemberType NoteProperty -Name "Business Role" -Value ("OST-d1-" + $projName + "-" + $Obj_desc.Attr[$i])
            $obj | Add-Member -MemberType NoteProperty -Name "Business Role Description" -Value ("Application level requestable role that " + ($Obj_desc.Val[$i] -replace ',','') + " for any user in the project")
            $obj | Add-Member -MemberType NoteProperty -Name "System" -Value "OpenStack_Prod"
            $obj | Add-Member -MemberType NoteProperty -Name "Task Role Technical Name" -Value $catalogEntity.ENTITY_NAME
            $OSTrole_CreationForm += $obj
            clear-variable obj

            ###     Create Role enrichment Object for Metadata CSV
            $obj = New-Object -TypeName PSObject
            $obj | Add-Member -MemberType NoteProperty -Name "ENTITY_KEY" -Value ("NeedInput-ConvertToKey-" + ("OST-d1-" + $projName + "-" + $Obj_desc.Attr[$i]))
            $obj | Add-Member -MemberType NoteProperty -Name "ENTITY_TYPE" -Value "Role"
            $obj | Add-Member -MemberType NoteProperty -Name "ENTITY_NAME" -Value ("OST-d1-" + $projName + "-" + $Obj_desc.Attr[$i])
            $obj | Add-Member -MemberType NoteProperty -Name "IS_REQUESTABLE" -Value "1"
            $obj | Add-Member -MemberType NoteProperty -Name "CATEGORY" -Value "Requestable Role"
            $obj | Add-Member -MemberType NoteProperty -Name "APPROVER_ROLE" -Value ("NeedInput-ConvertToKey-" + ("Approvers_OpenStack_" + $projName))
            $obj | Add-Member -MemberType NoteProperty -Name "CERTIFIER_USER" -Value ("NeedInput-ConvertToKey-" + $owner)
            $obj | Add-Member -MemberType NoteProperty -Name "ENTITLEMENTAPPROVERGROUPREQUIR" -Value "TRUE"
            $obj | Add-Member -MemberType NoteProperty -Name "BLOSSOMCIID" -Value $BlossID
            $obj | Add-Member -MemberType NoteProperty -Name "BLOSSOMAPPLICATIONNAME" -Value $BlossName
            $MetaDataEnrich_CatSync += $obj
            clear-variable obj
        }

        ##########################################################
        ###     Foreach tenant (ie text file in input)
        ##########################################################
        ###     Create ApproverGroup Creation Form
        $obj = New-Object -TypeName PSObject
        $obj | Add-Member -MemberType NoteProperty -Name "Role Name" -Value ("Approvers_OpenStack_" + $projName)
        $obj | Add-Member -MemberType NoteProperty -Name "Role Display Name" -Value ("Approvers_OpenStack_" + $projName)
        $obj | Add-Member -MemberType NoteProperty -Name "Role E-Mail" -Value ""
        $obj | Add-Member -MemberType NoteProperty -Name "Role Description" -Value "Provides access to approve requests for the OpenStack requestable roles for the project name listed in this approver role name"
        $obj | Add-Member -MemberType NoteProperty -Name "Role Category" -Value "Approver Role"
        $obj | Add-Member -MemberType NoteProperty -Name "OwnedBy" -Value $owner
        $ApproverRole_CreationForm += $obj
        clear-variable obj

        ###     Create ApproverGroup BulkAddUser Form
        $obj = New-Object -TypeName PSObject
        $obj | Add-Member -MemberType NoteProperty -Name "USERLOGIN" -Value $owner
        $obj | Add-Member -MemberType NoteProperty -Name "ACCESSTYPE" -Value "ROLE"
        $obj | Add-Member -MemberType NoteProperty -Name "ACCESS" -Value ("Approvers_OpenStack_" + $projName)
        $obj | Add-Member -MemberType NoteProperty -Name "APPINSTANCE" -Value ""
        $obj | Add-Member -MemberType NoteProperty -Name "JUSTIFICATION" -Value "New approver role for openstack"
        $obj | Add-Member -MemberType NoteProperty -Name "OPERATION" -Value "ADD"
        $ApproverRole_UserAddForm += $obj
        clear-variable obj

        ###     Create ApproverGroup enrichment Object for Metadata CSV
        $obj = New-Object -TypeName PSObject
        $obj | Add-Member -MemberType NoteProperty -Name "ENTITY_KEY" -Value ("NeedInput-ConvertToKey-" + ("Approvers_OpenStack_" + $projName))
        $obj | Add-Member -MemberType NoteProperty -Name "ENTITY_TYPE" -Value "Role"
        $obj | Add-Member -MemberType NoteProperty -Name "ENTITY_NAME" -Value ("Approvers_OpenStack_" + $projName)
        $obj | Add-Member -MemberType NoteProperty -Name "IS_REQUESTABLE" -Value "1"
        $obj | Add-Member -MemberType NoteProperty -Name "CATEGORY" -Value "Approver Role"
        $obj | Add-Member -MemberType NoteProperty -Name "APPROVER_ROLE" -Value ("NeedInput-ConvertToKey-" + ("Approvers_OpenStack_" + $projName))
        $obj | Add-Member -MemberType NoteProperty -Name "CERTIFIER_USER" -Value ("NeedInput-ConvertToKey-" + $owner)
        $obj | Add-Member -MemberType NoteProperty -Name "ENTITLEMENTAPPROVERGROUPREQUIR" -Value "TRUE"
        $obj | Add-Member -MemberType NoteProperty -Name "BLOSSOMCIID" -Value $BlossID
        $obj | Add-Member -MemberType NoteProperty -Name "BLOSSOMAPPLICATIONNAME" -Value $BlossName
        $MetaDataEnrich_CatSync += $obj
        clear-variable obj
        "File Processing Complete" >> $logFile
        "############################################`r`n">> $logFile
    }
}

##########################################################
###			Export to Output Dir
##########################################################
###  Log completion
"OST Role Intake Automation Run Completed: " >> $logFile
Add-Content -Path $logFile -Value (Get-Date)


$entEnrich_Desc | Export-Csv ($outputDir + $dateText + "-Description.csv") -NoTypeInformation
asdfasdfasdf asdfasdfasdf
$MetaDataEnrich_CatSync | Export-Csv ($outputDir + $dateText + "-CatalogSync.csv") -NoTypeInformation
$OSTrole_CreationForm | Export-Csv ($outputDir + $dateText + "-OSTroleCreation.csv") -NoTypeInformation
$ApproverRole_CreationForm | Export-Csv ($outputDir + $dateText + "-ApprGroupCreation.csv") -NoTypeInformation
$ApproverRole_UserAddForm | Export-Csv ($outputDir + $dateText + "-ApproGroupBulkAddUser.csv") -NoTypeInformation


(gc ($outputDir + $dateText + "-Description.csv")) | % {$_ -replace '"', ""} | out-file ($outputDir + $dateText + "-Description.csv") -Fo -En ascii
(gc ($outputDir + $dateText + "-CatalogSync.csv")) | % {$_ -replace '"', ""} | out-file ($outputDir + $dateText + "-CatalogSync.csv") -Fo -En ascii
(gc ($outputDir + $dateText + "-OSTroleCreation.csv")) | % {$_ -replace '"', ""} | out-file ($outputDir + $dateText + "-OSTroleCreation.csv") -Fo -En ascii
(gc ($outputDir + $dateText + "-ApprGroupCreation.csv")) | % {$_ -replace '"', ""} | out-file ($outputDir + $dateText + "-ApprGroupCreation.csv") -Fo -En ascii
(gc ($outputDir + $dateText + "-ApproGroupBulkAddUser.csv")) | % {$_ -replace '"', ""} | out-file ($outputDir + $dateText + "-ApproGroupBulkAddUser.csv") -Fo -En ascii
