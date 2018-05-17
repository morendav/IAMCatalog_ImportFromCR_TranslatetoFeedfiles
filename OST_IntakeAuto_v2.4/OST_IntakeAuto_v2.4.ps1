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
###			Directory Operations
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

##########################################################
###			Initialize Variables
##########################################################
### Find .txt and .csv files & Import
###     assign as variables for SN CR
$AllTextFiles = get-childitem -Path ($inputDir + '*.txt') | select-object name
$TenCR=@{}

###     BUILD SQL STRINGS
### set UDF for int vs prod values
    ### These will change for PROD vs INT               *UDF_lower*
    $sql_parentEntityKey = "1941 "
### These are static values
$sqlString=@{}
$sqlOutputObj=@{}
$sqlString.Entity_Beg = "Select entity_display_name, entity_key, entity_name from <ProductionReadOnlyAccountHere>.catalog where parent_entity_key = "
$sqlString.Entity_Mid = "and entity_display_name like '"
$sqlString.Entity_End = "%' and is_deleted = 0 and entity_type='Entitlement'"
$sqlString.User_Beg = "Select usr_key, usr_login from <ProductionReadOnlyAccountHere>.usr where usr_login = '"
$sqlString.User_End = "' and usr_status = 'Active'"
$sqlString.MembRole_Beg = "select ugp_name,usr_login from <ProductionReadOnlyAccountHere>.ugp left join <ProductionReadOnlyAccountHere>.usg on usg.ugp_key = ugp.ugp_key left join <ProductionReadOnlyAccountHere>.usr on usr.usr_key = usg.usr_key where ugp_name like '%"
$sqlString.MembRole_End = "%'"
$sqlString.MembAppRole_beg = "select ugp_name,usr_login from <ProductionReadOnlyAccountHere>.ugp left join <ProductionReadOnlyAccountHere>.usg on usg.ugp_key = ugp.ugp_key left join <ProductionReadOnlyAccountHere>.usr on usr.usr_key = usg.usr_key where ugp_name like '%pprover%' and ugp_name like '%"
$sqlString.RoleEntData_beg = "select entity_display_name, entity_key from <ProductionReadOnlyAccountHere>.catalog where entity_type = 'Role' and is_deleted=0 and entity_display_name like '%"
$sqlString.RoleEntData_Mid = "%'"

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

"`rInput Files Read Successfully`r`nBegin File Processing`r`n" >> $logFile

##########################################################
###			Define Global Functions
##########################################################
function WriteToFileObjects_Inner ($CurrentCR, $catalogEntity, $ownerObj, $i, $TenCR) {
### funciton for inner loop to write to temporary file objects =@{}
### Input: CurrentCR from the text file - the current CR data including owner, tenant name, blossom info
###        CatalogEntity - from the catalog SQL call, the entity whose display name matches the current CR tenant name
###        OwnerObj - from usr table SQL call, the current owner user id and user key for metadata updates
###        i - for hte iteration of current for loop (for i 1 to number of OST roles in current CR text file)
###        TenCR - if delete has relevant key info for approver group and tenant info
    $FuncObj =@{}
    $projName = ($CurrentCR | where-object -property Attr -eq "project_name").Val
    $BlossID = ($CurrentCR | where-object -property Attr -eq "blossom_id").Val
    $BlossName =($CurrentCR | where-object -property Attr -eq "blossom_name").VAl
    ### Based on operation: define some values, and perform run for OST role creation if applicable
    if($TenCR.operation -ne "Delete"){ ### if not deleted then assign following values
        $Desc = ($CurrentCR.Val[$i] -replace ',','')
        $roleDesc = ("Application level requestable role that " + ($CurrentCR.Val[$i] -replace ',','') + " for any user in the project")
        $isReq = 1
        $isDel = 0
        $roleKey = ("NeedInput-ConvertToKey-" + ("OST-d1-" + $projName + "-" + $CurrentCR.Attr[$i]))
        $ApproverRoleKey2 = ("NeedInput-ConvertToKey-" + ("Approvers_OpenStack_" + $projName))
        ###    Create OST Role creation form only if ADD:
        $obj = New-Object -TypeName PSObject
        $obj | Add-Member -MemberType NoteProperty -Name "Business Role" -Value ("OST-d1-" + $projName + "-" + $CurrentCR.Attr[$i])
        $obj | Add-Member -MemberType NoteProperty -Name "Business Role Description" -Value ("Application level requestable role that " + ($CurrentCR.Val[$i] -replace ',','') + " for any user in the project")
        $obj | Add-Member -MemberType NoteProperty -Name "System" -Value "OpenStack_Prod"
        $obj | Add-Member -MemberType NoteProperty -Name "Task Role Technical Name" -Value $catalogEntity.ENTITY_NAME
        $FuncObj.OSTrole_CreationForm += $obj
        clear-variable obj
        ###     Create EntEnrichment Object for Description CSV
        $obj = New-Object -TypeName PSObject
        $obj | Add-Member -MemberType NoteProperty -Name "Type" -Value "Entitlement"
        $obj | Add-Member -MemberType NoteProperty -Name "Role Name" -Value ""
        $obj | Add-Member -MemberType NoteProperty -Name "Application" -Value "OpenStackProd"
        $obj | Add-Member -MemberType NoteProperty -Name "Entitlement" -Value $catalogEntity.ENTITY_NAME
        $obj | Add-Member -MemberType NoteProperty -Name "Attribute Name" -Value "Description"
        $obj | Add-Member -MemberType NoteProperty -Name "Value" -Value $Desc
        $FuncObj.entEnrich_Desc += $obj
        clear-variable obj
        ###     Create EntEnrichment Object for Metadata CSV
        $obj = New-Object -TypeName PSObject
        $obj | Add-Member -MemberType NoteProperty -Name "ENTITY_KEY" -Value $catalogEntity.ENTITY_KEY
        $obj | Add-Member -MemberType NoteProperty -Name "ENTITY_TYPE" -Value "Entitlement"
        $obj | Add-Member -MemberType NoteProperty -Name "ENTITY_NAME" -Value $catalogEntity.ENTITY_NAME
        $obj | Add-Member -MemberType NoteProperty -Name "IS_REQUESTABLE" -Value "0"
        #$obj | Add-Member -MemberType NoteProperty -Name "IS_DELETED" -Value $isDel
        $obj | Add-Member -MemberType NoteProperty -Name "CATEGORY" -Value "Entitlement"
        $obj | Add-Member -MemberType NoteProperty -Name "APPROVER_ROLE" -Value ""
        $obj | Add-Member -MemberType NoteProperty -Name "CERTIFIER_USER" -Value ($ownerObj.USR_KEY.Value)
        $obj | Add-Member -MemberType NoteProperty -Name "ENTITLEMENTAPPROVERGROUPREQUIR" -Value "FALSE"
        $obj | Add-Member -MemberType NoteProperty -Name "BLOSSOMCIID" -Value $BlossID
        $obj | Add-Member -MemberType NoteProperty -Name "BLOSSOMAPPLICATIONNAME" -Value $BlossName
        $FuncObj.MetaDataEnrich_CatSync += $obj
        clear-variable obj
        }
    else{ ### if it is delete, assign following values
        $Desc = "Is Deleted Tenant Do Not Make Requestable  " + ($CurrentCR.Val[$i] -replace ',','')
        $roleDesc = "Is Deleted Tenant Do Not Make Requestable  "
        $isReq = 0
        $isDel = 1
        $ApproverRoleKey2 = ($TenCR.RoleKey | where-object -property ENTITY_DISPLAY_NAME -like ("Approvers_OpenStack_" + $projName)).ENTITY_KEY.VALUE
        $roleKey = ($TenCR.RoleKey | where-object -property ENTITY_DISPLAY_NAME -like ("*" + $projName + "-" + $CurrentCR.Attr[$i])).ENTITY_KEY.VALUE
        $roleName = (($TenCR.RoleKey | where-object -property ENTITY_DISPLAY_NAME -like ("*" + $projName + "-" + $CurrentCR.Attr[$i])).ENTITY_DISPLAY_NAME.VALUE)
        ###     If delete- update the description for the role as well.
        $obj = New-Object -TypeName PSObject
        $obj | Add-Member -MemberType NoteProperty -Name "Type" -Value "Role"
        $obj | Add-Member -MemberType NoteProperty -Name "Role Name" -Value $roleName
        $obj | Add-Member -MemberType NoteProperty -Name "Application" -Value "OpenStackProd"
        $obj | Add-Member -MemberType NoteProperty -Name "Entitlement" -Value ""
        $obj | Add-Member -MemberType NoteProperty -Name "Attribute Name" -Value "Description"
        $obj | Add-Member -MemberType NoteProperty -Name "Value" -Value $roleDesc
        $FuncObj.entEnrich_Desc2 += $obj
        clear-variable obj}
    # ###     Create EntEnrichment Object for Description CSV
    # $obj = New-Object -TypeName PSObject
    # $obj | Add-Member -MemberType NoteProperty -Name "Type" -Value "Entitlement"
    # $obj | Add-Member -MemberType NoteProperty -Name "Role Name" -Value ""
    # $obj | Add-Member -MemberType NoteProperty -Name "Application" -Value "OpenStackProd"
    # $obj | Add-Member -MemberType NoteProperty -Name "Entitlement" -Value $catalogEntity.ENTITY_NAME
    # $obj | Add-Member -MemberType NoteProperty -Name "Attribute Name" -Value "Description"
    # $obj | Add-Member -MemberType NoteProperty -Name "Value" -Value $Desc
    # $FuncObj.entEnrich_Desc += $obj
    # clear-variable obj
    # ###     Create EntEnrichment Object for Metadata CSV
    # $obj = New-Object -TypeName PSObject
    # $obj | Add-Member -MemberType NoteProperty -Name "ENTITY_KEY" -Value $catalogEntity.ENTITY_KEY
    # $obj | Add-Member -MemberType NoteProperty -Name "ENTITY_TYPE" -Value "Entitlement"
    # $obj | Add-Member -MemberType NoteProperty -Name "ENTITY_NAME" -Value $catalogEntity.ENTITY_NAME
    # $obj | Add-Member -MemberType NoteProperty -Name "IS_REQUESTABLE" -Value "0"
    # #$obj | Add-Member -MemberType NoteProperty -Name "IS_DELETED" -Value $isDel
    # $obj | Add-Member -MemberType NoteProperty -Name "CATEGORY" -Value "Entitlement"
    # $obj | Add-Member -MemberType NoteProperty -Name "APPROVER_ROLE" -Value ""
    # $obj | Add-Member -MemberType NoteProperty -Name "CERTIFIER_USER" -Value ($ownerObj.USR_KEY.Value)
    # $obj | Add-Member -MemberType NoteProperty -Name "ENTITLEMENTAPPROVERGROUPREQUIR" -Value "FALSE"
    # $obj | Add-Member -MemberType NoteProperty -Name "BLOSSOMCIID" -Value $BlossID
    # $obj | Add-Member -MemberType NoteProperty -Name "BLOSSOMAPPLICATIONNAME" -Value $BlossName
    # $FuncObj.MetaDataEnrich_CatSync += $obj
    # clear-variable obj
    ###     Create Role enrichment Object for Metadata CSV
    $obj = New-Object -TypeName PSObject
    $obj | Add-Member -MemberType NoteProperty -Name "ENTITY_KEY" -Value $roleKey
    $obj | Add-Member -MemberType NoteProperty -Name "ENTITY_TYPE" -Value "Role"
    $obj | Add-Member -MemberType NoteProperty -Name "ENTITY_NAME" -Value ("OST-d1-" + $projName + "-" + $CurrentCR.Attr[$i])
    $obj | Add-Member -MemberType NoteProperty -Name "IS_REQUESTABLE" -Value $isReq
    #$obj | Add-Member -MemberType NoteProperty -Name "IS_DELETED" -Value $isDel
    $obj | Add-Member -MemberType NoteProperty -Name "CATEGORY" -Value "Requestable Role"
    $obj | Add-Member -MemberType NoteProperty -Name "APPROVER_ROLE" -Value $ApproverRoleKey2
    $obj | Add-Member -MemberType NoteProperty -Name "CERTIFIER_USER" -Value ($ownerObj.USR_KEY.Value)
    $obj | Add-Member -MemberType NoteProperty -Name "ENTITLEMENTAPPROVERGROUPREQUIR" -Value "TRUE"
    $obj | Add-Member -MemberType NoteProperty -Name "BLOSSOMCIID" -Value $BlossID
    $obj | Add-Member -MemberType NoteProperty -Name "BLOSSOMAPPLICATIONNAME" -Value $BlossName
    $FuncObj.MetaDataEnrich_CatSync2 += $obj
    clear-variable obj
    return $FuncObj
}
function Add_WriteToFileObjects_Outer ($CurrentCR, $ownerObj, $TenCR) {
    $projName = ($CurrentCR | where-object -property Attr -eq "project_name").Val
    $BlossID = ($CurrentCR | where-object -property Attr -eq "blossom_id").Val
    $BlossName =($CurrentCR | where-object -property Attr -eq "blossom_name").VAl
    $FuncObj =@{}

    if($TenCR.operation -ne "Delete"){ ### if not deleted then assign following values
        $isReq = 1
        $isDel = 0
        $bulkOp = "ADD"
        $AppRoleJustification ="New approver role for openstack"
        $appRoleKey = ("NeedInput-ConvertToKey-" + ("Approvers_OpenStack_" + $projName))
            ###     Create ApproverGroup Creation Form ONLY IF ADD
            $obj = New-Object -TypeName PSObject
            $obj | Add-Member -MemberType NoteProperty -Name "Role Name" -Value ("Approvers_OpenStack_" + $projName)
            $obj | Add-Member -MemberType NoteProperty -Name "Role Display Name" -Value ("Approvers_OpenStack" + $projName)
            $obj | Add-Member -MemberType NoteProperty -Name "Role E-Mail" -Value ""
            $obj | Add-Member -MemberType NoteProperty -Name "Role Description" -Value "Provides access to approve requests for the OpenStack requestable roles for the project name listed in this approver role name"
            $obj | Add-Member -MemberType NoteProperty -Name "Role Category" -Value "Approver Role"
            $obj | Add-Member -MemberType NoteProperty -Name "OwnedBy" -Value ($ownerObj.USR_LOGIN.Value)
            $FuncObj.ApproverRole_CreationForm += $obj
            clear-variable obj}
    else{ ### if it is delete, assign following values
        $roleDesc = ("Application level requestable role that " + ($CurrentCR.Val[$i] -replace ',','') + " for any user in the project")
        $isReq = 1
        $isDel = 0
        $AppRoleJustification ="Remove owner from openstack approver group"
        $bulkOp = "REMOVE"
        $appRoleKey = ($TenCR.RoleKey | where-object -property ENTITY_DISPLAY_NAME -like ("Approvers_OpenStack_" + $projName)).ENTITY_KEY.VALUE
        }

    ###     Create ApproverGroup BulkAddUser Form
    $obj = New-Object -TypeName PSObject
    $obj | Add-Member -MemberType NoteProperty -Name "USERLOGIN" -Value ($ownerObj.USR_LOGIN.Value)
    $obj | Add-Member -MemberType NoteProperty -Name "ACCESSTYPE" -Value "ROLE"
    $obj | Add-Member -MemberType NoteProperty -Name "ACCESS" -Value ("Approvers_OpenStack_" + $projName)
    $obj | Add-Member -MemberType NoteProperty -Name "APPINSTANCE" -Value ""
    $obj | Add-Member -MemberType NoteProperty -Name "JUSTIFICATION" -Value $AppRoleJustification
    $obj | Add-Member -MemberType NoteProperty -Name "OPERATION" -Value $bulkOp
    $FuncObj.ApproverRole_UserAddForm += $obj
    clear-variable obj
    ###     Create ApproverGroup enrichment Object for Metadata CSV
    $obj = New-Object -TypeName PSObject
    $obj | Add-Member -MemberType NoteProperty -Name "ENTITY_KEY" -Value  $appRoleKey
    $obj | Add-Member -MemberType NoteProperty -Name "ENTITY_TYPE" -Value "Role"
    $obj | Add-Member -MemberType NoteProperty -Name "ENTITY_NAME" -Value ("Approvers_OpenStack_" + $projName)
    $obj | Add-Member -MemberType NoteProperty -Name "IS_REQUESTABLE" -Value $isReq
    #$obj | Add-Member -MemberType NoteProperty -Name "IS_DELETED" -Value $isDel
    $obj | Add-Member -MemberType NoteProperty -Name "CATEGORY" -Value "Approver Role"
    $obj | Add-Member -MemberType NoteProperty -Name "APPROVER_ROLE" -Value  $appRoleKey
    $obj | Add-Member -MemberType NoteProperty -Name "CERTIFIER_USER" -Value ($ownerObj.USR_KEY.Value)
    $obj | Add-Member -MemberType NoteProperty -Name "ENTITLEMENTAPPROVERGROUPREQUIR" -Value "TRUE"
    $obj | Add-Member -MemberType NoteProperty -Name "BLOSSOMCIID" -Value $BlossID
    $obj | Add-Member -MemberType NoteProperty -Name "BLOSSOMAPPLICATIONNAME" -Value $BlossName
    $FuncObj.MetaDataEnrich_CatSync += $obj
    clear-variable obj
    return $FuncObj
}
function RemoveMembershipFile ($membershipSQLOutput) {
    $FuncObj =@{}
    ###     Create ApproverGroup BulkAddUser Form
    $obj = New-Object -TypeName PSObject
    $obj | Add-Member -MemberType NoteProperty -Name "USERLOGIN" -Value ($membershipSQLOutput.USR_LOGIN.VALUE)
    $obj | Add-Member -MemberType NoteProperty -Name "ACCESSTYPE" -Value "ROLE"
    $obj | Add-Member -MemberType NoteProperty -Name "ACCESS" -Value ($membershipSQLOutput.UGP_NAME.VALUE)
    $obj | Add-Member -MemberType NoteProperty -Name "APPINSTANCE" -Value ""
    $obj | Add-Member -MemberType NoteProperty -Name "JUSTIFICATION" -Value "Decom openstack tenant remove this user from this role"
    $obj | Add-Member -MemberType NoteProperty -Name "OPERATION" -Value "REMOVE"
    $FuncObj.RemoveUsers += $obj
    clear-variable obj
    return $FuncObj
}
Function executeSQL($sqlString, $cmd) {
	$columnNames=[ordered]@{}
	$outputArray = @()
	## Read SQL Output ##
	$cmd.CommandText= $sqlString
	Try{
		$rdr=$cmd.ExecuteReader()
		$columnNames=$rdr.GetSchemaTable() | Select-Object -ExpandProperty ColumnName
		##    Format Output     ##
		while ($rdr.Read()) {
			$myRow =""|Select $columnNames    							## object myRow, set headers to columnNames-queryInd for query cycling
			for ($i=0; $i -lt $rdr.FieldCount; $i++) {	     			## (i is less than rdr.FieldCount)
				$myRow.($columnNames.Item($i)) =($rdr.GetOracleValue($i))} ## set index i of myRow.Column = Read Oracle Value
			$outputArray += $myRow										## grow the output array by a single row per while iteration
			$myRow = $null}											## reset temp variable myRow to null
	}
	catch [System.Exception]{
		$outputArray ="ConnectionError"
	}
  write-output $outputArray
  $columnNames= $null
  $outputArray= $null
  Remove-Variable columnNames
  Remove-Variable outputArray
}
function Get-EncryptData {
###############################
### Get-EncryptData
#     Take in encrypted 32bit key saved in script, and the padded 32 bit key
#     Output plain text password to be used in the script
###############################
param($key,$EncryptData)
$EncryptData | ConvertTo-SecureString -key $key |
ForEach-Object {[Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($_))}
}
function Convert-UDFKeytoEncryptKey {
###############################
### Convert-UDFKeytoEncryptKey
#     Take in a UDF string
#     Output a 32 bit key for encryption
###############################
param([string]$UDFkey)
if ((($UDFkey.length) -lt 16) -or (($UDFkey.length) -gt 32)) {Throw "String length Requirement not met"}
$pad = 32-($UDFkey.length)
$encoding = New-Object System.Text.ASCIIEncoding
$bytes = $encoding.GetBytes($UDFkey + "0" * $pad)
return $bytes
}

##########################################################
###			Establish OIM DB Connection & ExecuteSQL FUnction
##########################################################
## Init Auth Variables ##
$user="<ProductionReadOnlyAccountNameHere>"; $datasource="<SecureOIMDBConnectionStringHere>"
$EncryptedText = "<ecnryptedPassWordHereForREadOnlyAccount-Production>"
$oracleDir = $curDir + "\Library\oracle\odp.net\managed\common\Oracle.ManagedDataAccess.dll"	# UDF Oracle .dll
## Prompt for usr input (key for decryption) ##
[System.Reflection.Assembly]::LoadWithPartialName('Microsoft.VisualBasic') | Out-Null
$usrKey = [Microsoft.VisualBasic.Interaction]::InputBox("Enter OST-OIM Script Connect Key v2.2", "Key", "enter key here")
$key = Convert-UDFKeytoEncryptKey  $usrKey
$DecryptedText = Get-EncryptData -EncryptData $EncryptedText -key $key
## Establish Connection ##
Add-Type -Path $oracleDir
$con = New-Object Oracle.ManagedDataAccess.Client.OracleConnection("User Id=$user;Password=$DecryptedText;Data Source=$datasource")
$cmd=$con.CreateCommand()
$cmd.CommandText= "alter session set current_schema=<ProductionReadOnlyAccountHere>"
try{$con.Open()}
catch{
    $con.Close
    "Critical error detected during processing`r`nConnection to OIM DB Terminated" >> $logFile
}


##########################################################
###			Flat Feed File Creator
##########################################################
for ($ii=0; $ii+1 -le($AllTextFiles | select-object name | Measure-Object).count; $ii++){
    ### Define CR for Run & Entity Data from Catalog
    $descDir = $inputDir + ($allTextFiles[$ii]).Name
    $Obj_desc = import-csv ($descDir) -delimiter ':'
    ### Run SQL To gather all OST entitlements for current CR (ie tenant name space)
    $sqlOutputObj=@{}
    $sqlOutputObj.Current_CR_Entity = executeSQL ($sqlString.Entity_Beg + $sql_parentEntityKey +  $sqlString.Entity_Mid + (($Obj_desc | where-object -property Attr -eq "project_name").Val) +  $sqlString.Entity_End)  $cmd
    $sqlOutputObj.Current_CR_User = executeSQL ($sqlString.User_Beg + ($Obj_desc | where-object -property Attr -eq "owner").Val.ToUpper() + $sqlString.User_End)  $cmd


    ##########################################################
    ###			Logging in current CR Iteration
    ##########################################################
    "`r`n############################################">> $logFile
    "File Read: "+$descDir >> $logFile
    if (($Obj_desc -match 'project_name').Val -eq $null -Or ($Obj_desc -match 'blossom_id').Val -eq $null -or ($Obj_desc -match 'blossom_name').Val -eq $null -or ($Obj_desc -match 'owner').Val -eq $null)
    {
        "Critical error detected during processing" >> $logFile
        "Error: Attributes missing from CR Description file">> $logFile
        "`tProjectName, BlossomID, BlossomName, Owner">> $logFile
        "File Not Processed" >> $logFile
        "############################################`r`n">> $logFile
        continue}

    ##########################################################
    ###			Set Current CR Iteration Operaiton (Add, Delete)
    ##########################################################
    if (($Obj_desc | where-object -property Attr -eq "Operation").Val -ne "Delete"){ ### if not delete then pass variables
            $TenCR.operation = "Add"
            $TenCR.RoleKey= ""}
    else{ # if it is for a delete then do the following:
        $TenCR.operation = "Delete"
        $TenCR.RoleKey = executeSQL ($sqlString.RoleEntData_beg + (($Obj_desc | where-object -property Attr -eq "project_name").Val) + $sqlString.MembRole_End)  $cmd
        ### Captures all roles with name like '<project_name>'
    }

    ##########################################################
    ###     For each OST role to be enriched and onboarded in current CR
    ##########################################################
    for ($i=$Obj_desc.Attr.IndexOf("roles")+1; $i -le $Obj_desc.Attr.count -1; $i++){
        ###     Find associated OST Catalog entity for the this run
        $catalogEntity = $sqlOutputObj.Current_CR_Entity  |  Where-Object {($_.ENTITY_DISPLAY_NAME -eq  ((($Obj_desc -match 'project_name').Val) + "::" + $Obj_desc.Attr[$i]))}
        ###     Log error if no match found ins Catalog for current CR-Role iteration
        if ($catalogEntity.ENTITY_KEY -eq $null -and $TenCR.operation -eq "Add") {
            "Processing error detected" >> $logFile
            "Error: No Entitlement Match Found">> $logFile
            "`tError detected for Entity without match in OIM connection: "+((($Obj_desc -match 'project_name').Val) + "::" + $Obj_desc.Attr[$i])>> $logFile
            "Processing of entity skipped`r`n" >> $logFile
            continue}
        ##########################################################
        ###			If current CR is delete:
        ###   add memberships as removes to bulk add file
        ##########################################################
        if ($TenCR.operation -eq "Delete") {
            $memb = executeSQL ($sqlString.MembRole_Beg + ($Obj_desc | where-object -property Attr -eq "project_name").Val + "-" + $Obj_desc.Attr[$i] +"'") $cmd   ####*UDF_lower* the "%" needs to be "-" in PROD
            if ($memb.USR_LOGIN.Value -ne $Null){
            for ($iii=0; $iii+1 -le($memb | select-object UGP_NAME | Measure-Object).count; $iii++){
                $membRemoval_output = RemoveMembershipFile $memb[$iii]
                $ApproverRole_UserAddForm += $membRemoval_output.RemoveUsers}}}

        ##########################################################
        ###    Write current CR files to file temp objs
        ##########################################################
        $CR_RoleIteration_Output = WriteToFileObjects_Inner $Obj_desc $catalogEntity ($sqlOutputObj.Current_CR_User) $i $TenCR
        # $entEnrich_Desc += $CR_RoleIteration_Output.entEnrich_Desc ##these throw error because not all runs will containt atleast one addd
        # $MetaDataEnrich_CatSync += $CR_RoleIteration_Output.MetaDataEnrich_CatSync
        $MetaDataEnrich_CatSync += $CR_RoleIteration_Output.MetaDataEnrich_CatSync2
        ### Only Add the following pages to working files if NOT NULL
        if($CR_RoleIteration_Output.MetaDataEnrich_CatSync -ne $null -And $CR_RoleIteration_Output.entEnrich_Desc  -ne $null){
            $entEnrich_Desc += $CR_RoleIteration_Output.entEnrich_Desc ##these throw error because not all runs will containt atleast one addd
            $MetaDataEnrich_CatSync += $CR_RoleIteration_Output.MetaDataEnrich_CatSync
        }
        if($CR_RoleIteration_Output.entEnrich_Desc2 -ne $null){$entEnrich_Desc += $CR_RoleIteration_Output.entEnrich_Desc2}
        if($CR_RoleIteration_Output.OSTrole_CreationForm -ne $null){$OSTrole_CreationForm += $CR_RoleIteration_Output.OSTrole_CreationForm}
    }


    ##########################################################
    ###     Foreach tenant (ie text file in input)
    ##########################################################
    $CR_Output =@{}
    $CR_Output = Add_WriteToFileObjects_Outer $Obj_desc ($sqlOutputObj.Current_CR_User) $TenCR
    $ApproverRole_UserAddForm += $CR_Output.ApproverRole_UserAddForm
    $MetaDataEnrich_CatSync += $CR_Output.MetaDataEnrich_CatSync
    ### Only Add the following pages to working files if NOT NULL
    if($CR_Output.ApproverRole_CreationForm -ne $null){$ApproverRole_CreationForm += $CR_Output.ApproverRole_CreationForm}

    ### Log completion
    "File Processing Complete" >> $logFile
    "############################################`r`n">> $logFile
}

##########################################################
###			Export to Output Dir
##########################################################
###  Log completion
"OST Role Intake Automation Run Completed: " >> $logFile
Add-Content -Path $logFile -Value (Get-Date)
$con.Close()
$cmd = $null

$entEnrich_Desc | Export-Csv ($outputDir + $dateText + "-Description.csv") -NoTypeInformation
$MetaDataEnrich_CatSync | Export-Csv ($outputDir + $dateText + "-CatalogSync.csv") -NoTypeInformation
$OSTrole_CreationForm | Export-Csv ($outputDir + $dateText + "-OSTroleCreation.csv") -NoTypeInformation
$ApproverRole_CreationForm | Export-Csv ($outputDir + $dateText + "-ApprGroupCreation.csv") -NoTypeInformation
$ApproverRole_UserAddForm | Export-Csv ($outputDir + $dateText + "-ApproGroupBulkAddUser.csv") -NoTypeInformation


(gc ($outputDir + $dateText + "-Description.csv")) | % {$_ -replace '"', ""} | out-file ($outputDir + $dateText + "-Description.csv") -Fo -En ascii
(gc ($outputDir + $dateText + "-CatalogSync.csv")) | % {$_ -replace '"', ""} | out-file ($outputDir + $dateText + "-CatalogSync.csv") -Fo -En ascii
(gc ($outputDir + $dateText + "-OSTroleCreation.csv")) | % {$_ -replace '"', ""} | out-file ($outputDir + $dateText + "-OSTroleCreation.csv") -Fo -En ascii
(gc ($outputDir + $dateText + "-ApprGroupCreation.csv")) | % {$_ -replace '"', ""} | out-file ($outputDir + $dateText + "-ApprGroupCreation.csv") -Fo -En ascii
(gc ($outputDir + $dateText + "-ApproGroupBulkAddUser.csv")) | % {$_ -replace '"', ""} | out-file ($outputDir + $dateText + "-ApproGroupBulkAddUser.csv") -Fo -En ascii
