[CmdletBinding()]
param (
    [Parameter(Mandatory=$true)]
    [string]
    $sourceTenant,
    [Parameter(Mandatory=$true)]
    [string]
    $destTenant
)
$idLog = @()

function logID {
    param (
        [string]
        $displayName,
        [string]
        $signInName,
        [string]
        $objectType
    )
    $idObj | Add-Member -MemberType NoteProperty -Name "displayName" -Value $displayName
    $idObj | Add-Member -MemberType NoteProperty -Name "signInName" -Value $signInName
    $idObj | Add-Member -MemberType NoteProperty -Name "objectType" -Value $objectType
    $idLog += $idObj
}

function checkIDexists {
    param (
        [string]
        $displayName,
        [string]
        $signInName,
        [string]
        $objectType
    )
    $objectID = ""

    switch ($objectType) {
        "user" {
            $sp = Get-AzADUser -UserPrincipalName $signInName -ErrorAction SilentlyContinue
            if ($sp) {
                $objectID = $sp.Id
            }
          }
        "group" {
            $sp = Get-AzADGroup -DisplayName $displayName -ErrorAction SilentlyContinue
            if ($sp) {
                $objectID = $sp.Id
            }
          }
        "servicePrincipal" {
            $sp = Get-AzADServicePrincipal -DisplayName $displayName -ErrorAction SilentlyContinue
            if ($sp) {
                $objectID = $sp.Id
            }
          }
        Default {}
    }

    return $objectID
}

#Connect to Source Tenant
try {
    Connect-AzAccount -TenantId $sourceTenant -ErrorAction Stop
    Write-Host "Connected to source tenant" -ForegroundColor Green    
}
catch {
    Write-Host -ForegroundColor Red "Could not connect to source tenant. An error occurred:"
    Write-Host $_
    exit
}

#Export all roles from source tenant
$sourceRoles = Get-AzRoleDefinition 
$sourceRoles | Export-Csv -Path ".\sourceRoles.csv" -NoTypeInformation

#Connect to Destination Tenant
try {
    Connect-AzAccount -TenantId $destTenant -ErrorAction Stop
    Write-Host "Connected to destination tenant" -ForegroundColor Green    
}
catch {
    Write-Host -ForegroundColor Red "Could not connect to destination tenant. An error occurred:"
    Write-Host $_
    exit
}

#Import all roles to destination tenant
foreach ($role in $sourceRoles) {
    $objectID = checkIDexists -displayName $role.DisplayName -signInName $role.SignInName -objectType $role.objectType
    if ($objectID -eq "") {
        Write-Host -ForegroundColor Red "$($role.DisplayName) $($role.SignInName) does not exist in destination tenant."
        logID -displayName $role.DisplayName -signInName $role.SignInName -objectType $role.objectType
    }
    else {
        try {
            New-AzRoleAssignment -ObjectId $objectID -RoleDefinitionName $role.RoleDefinitionName -scope $role.Scope -ErrorAction Stop
            Write-Host -ForegroundColor Green "Successfully imported role $($role.RoleDefinitionName) $($role.SignInName) $($role.DisplayName) $($role.Scope)"
        }
        catch {
            Write-Host -ForegroundColor Red "Could not import role $($role.RoleDefinitionName) $($role.SignInName) $($role.DisplayName). An error occurred:"
            Write-Host $_
        }
    }
}
$idLog | Export-Csv -Path ".\idLog.csv" -NoTypeInformation
Write-Host "Done importing roles. See log file for ID that did not exist. .\idLog.csv" -ForegroundColor Green
