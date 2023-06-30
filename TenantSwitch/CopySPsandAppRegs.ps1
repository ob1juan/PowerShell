[CmdletBinding()]
param (
    [Parameter(Mandatory=$true)]
    [string]
    $sourceTenant,
    [Parameter(Mandatory=$true)]
    [string]
    $destTenant
)

$importErrors = @()

$spRolesCsv = ".\EnterpriseApplicationReport.csv"

Write-Host "Connecting to source tenant...." -ForegroundColor Green

#Connect to Source Tenant

try{
    Connect-AzureAD -TenantId $sourceTenant -ErrorAction Stop #MoStateGov2 Tenant
}
catch {
  Write-Host "Could not connect to tenant. An error occurred:"
  Write-Host $_
  exit
}

#get all current app, enterprise, and sso applications
try {$sourceApps = Get-AzureADApplication -All:$true -ErrorAction Stop}
catch {
  Write-Host "Could not connect to tenant. An error occurred:"
  Write-Host $_
  exit
}  

try {
  $sourceSPs = Get-AzureADServicePrincipal -All:$true
 }
catch {
  Write-Host "An error occurred:"
  Write-Host $_
  exit
}

Write-Host "Exporting Role Assignments to CSV...." -ForegroundColor Green
foreach ($servicePrincipal in $sourceSPs) {
    Get-AzureADServiceAppRoleAssignment -ObjectId $ServicePrincipal.objectId | Select-Object ResourceDisplayName, ResourceId, PrincipalDisplayName, PrincipalType | Export-Csv -Path $spRolesCsv -NoTypeInformation -Append
}

##############################################################################################################################################
#Connect to Dest Tenant
write-host "Connecting to destination tenant...." -ForegroundColor Green
try{
    Connect-AzureAD -TenantId $destTenant -ErrorAction Stop #MoGCC Tenant
}
catch {
  Write-Host "Could not connect to tenant. An error occurred:"
  Write-Host $_
  exit
}

#get new tenant app, enterprise, and sso applications
try {$destApps = Get-AzureADApplication -All:$true}
catch {Write-Host "An error occurred:"
  Write-Host $_}

try {$destSPs = Get-AzureADServicePrincipal -All:$true}
catch {Write-Host "An error occurred:"
  Write-Host $_}

#check to see if ad app exists in new tenant....if there, skip. Else, add
foreach($app in $sourceApps){   
  if($app.DisplayName -in $destApps.DisplayName){

      Write-Host "Application $($app.DisplayName) already in new tenant. Skipping...." -ForegroundColor Red
      #continue
  }
  else{
      Write-Host "Application $($app.DisplayName) is not in the new tenant. Adding...." -ForegroundColor Green
      try {
        New-AzureADApplication -DisplayName $app.DisplayName -AddIns $app.AddIns -AllowGuestsSignIn $app.AllowGuestsSignIn `
        -AllowPassthroughUsers $app.AllowPassthroughUsers -AppLogoUrl $app.AppLogoUrl -AvailableToOtherTenants $app.AvailableToOtherTenants `
        -ErrorUrl $app.ErrorUrl -GroupMembershipClaims $app.GroupMembershipClaims -Homepage $app.Homepage -InformationalUrls $app.InformationalUrls `
        -IsDeviceOnlyAuthSupported $app.IsDeviceOnlyAuthSupported -IsDisabled $app.IsDisabled -KnownClientApplications $app.KnownClientApplications `
        -LogoutUrl $app.LogoutUrl -Oauth2AllowImplicitFlow $app.Oauth2AllowImplicitFlow -Oauth2AllowUrlPathMatching $app.Oauth2AllowUrlPathMatching `
        -Oauth2RequirePostResponse $app.Oauth2RequirePostResponse -OrgRestrictions $app.OrgRestrictions -OptionalClaims $app.OptionalClaims `
        -ParentalControlSettings $app.ParentalControlSettings  -PreAuthorizedApplications $app.PreAuthorizedApplications -PublicClient $app.PublicClient `
        -RecordConsentConditions $app.RecordConsentConditions -ReplyUrls $app.ReplyUrls -SamlMetadataUrl $app.SamlMetadataUrl -WwwHomepage $app.WwwHomepage `
        -ErrorAction Stop

        Write-Host -ForegroundColor Green "Added Application $($app.DisplayName) to new tenant.)"
      } #-Oauth2Permissions $new_app_reg.Oauth2Permissions -PasswordCredentials $new_app_reg.PasswordCredentials -IdentifierUris $new_app_reg.IdentifierUris -KeyCredentials $new_app_reg.KeyCredentials
      
      catch {
        Write-Host "An error occurred:"
        Write-Host $_
        $importErrors += $app.DisplayName + " - " + $_
      }    
      #continue      

  }
}

Start-Sleep -seconds 60

foreach($newSp in $sourceSPs){
    if($newSp.DisplayName -in $destSPs.DisplayName){
        Write-Host "Service Principal $($newSp.DisplayName) already in new tenant. Skipping...." -ForegroundColor Red
    }

    else{
      Write-Host "Service Principal $($newSp.DisplayName) not in the new tenant. Adding...." -ForegroundColor Green

      try {
        New-AzureADServicePrincipal -AccountEnabled $newSp.AccountEnabled -AlternativeNames $newSp.AlternativeNames -AppId $newSp.AppId `
        -AppRoleAssignmentRequired $newSp.AppRoleAssignmentRequired -DisplayName $newSp.DisplayName -ErrorUrl $newSp.ErrorUrl -Homepage $newSp.Homepage `
        -KeyCredentials $newSp.KeyCredentials -LogoutUrl $newSp.LogoutUrl -ReplyUrls $newSp.ReplyUrls -SamlMetadataUrl $newSp.SamlMetadataUrl `
        -ServicePrincipalType $newSp.ServicePrincipalType -Tags $newSp.Tags -ErrorAction Stop
        Write-Host -foregroundcolor Green "Added Service Principal $($newSp.DisplayName) to new tenant."
      } #-PasswordCredentials $new_sp.PasswordCredentials
      catch {
        Write-Host "An error occurred:"
        Write-Host $_
        $importErrors += $newSp.DisplayName + " - " + $_
      }          
    }
    foreach($role in $newSp.AppRoles){
        try {
            $roleAssignment = New-AzureADServiceAppRoleAssignment -ObjectId $newSp.ObjectId -Id $role.Id -PrincipalId $newSp.ObjectId -ResourceId $role.ResourceId -ErrorAction Stop
            Write-Host -ForegroundColor Green "Added $($roleAssignment.PrincipalDisplayName) to $($roleAssignment.ResourceDisplayName) with role $($roleAssignment.ResourceDisplayName)"
        }
        catch {
            Write-Host "An error occurred:"
            Write-Host $_
            $importErrors += $newSp.DisplayName + " - " + $_
        }
    }
}

$tenant_app_regs_check = Get-AzureADApplication -All:$true
$tenant_sps_check = Get-AzureADServicePrincipal -All:$true

Write-Host "$((Get-Date).ToString() ): Finished adding applications to new tenant."
write-host "$($sourceApps.count) applications in source tenant."
write-host "$($sourceSPs.count) service principals in source tenant."
Write-Host "$($tenant_app_regs_check.count) applications in new tenant."
Write-Host "$($tenant_sps_check.count) service principals in new tenant."
Write-Host -ForegroundColor Red "Errors: $($importErrors.count)"
Write-Host -ForegroundColor Red "Error details located in importErrors.txt"
$importErrors | Out-File -FilePath ".\importErrors.txt"
