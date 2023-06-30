[CmdletBinding()]
param (
    [Parameter(Mandatory=$true)]
    [string]
    $sourceTenant,
    [Parameter(Mandatory=$true)]
    [string]
    $destTenant
)
function checkIDexists {
    param (
        [string]
        $displayName,
        [string]
        $signInName,
        [Parameter(Mandatory=$true)]
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
