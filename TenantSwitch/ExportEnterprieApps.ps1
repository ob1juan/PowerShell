$PathCsv = ".\EnterpriseApplicationReport.csv"
$ServicePrincipalList = Get-AzureADServicePrincipal -All $true
foreach ($servicePrincipal in $ServicePrincipalList) {
    Get-AzureADServiceAppRoleAssignment -ObjectId $ServicePrincipal.objectId | Select-Object ResourceDisplayName, ResourceId, PrincipalDisplayName, PrincipalType | Export-Csv -Path $PathCsv -NoTypeInformation -Append
}