$subs = get-azsubscription | where-object {$_.State -eq 'Enabled'}
$log = @()
Write-Host "Starting resource provider registration for all enabled subscriptions..."

foreach ($sub in $subs) {
    Write-Host "Setting resource providers for subscription: $($sub.Name)"
    Set-AzContext -SubscriptionId $sub.Id

    $logObj = [PSCustomObject]@{
        Timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        SubscriptionId = ""
        ProviderNamespace = ""
        Status = ""
        ErrorMessage = ""
    }
    # List of resource providers to register
    $resourceProviders = @(
        "Microsoft.Compute",
        "Microsoft.Storage",
        "Microsoft.Network",
        "Microsoft.KeyVault",
        "Microsoft.Sql",
        "Microsoft.Insights",
        "Microsoft.AlertsManagement",
        "Microsoft.OperationalInsights",
        "Microsoft.OperationsManagement",
        "Microsoft.Automation",
        "Microsoft.Security",
        "Microsoft.Network",
        "Microsoft.EventGrid",
        "Microsoft.ManagedIdentity",
        "Microsoft.GuestConfiguration",
        "Microsoft.Advisor",
        "Microsoft.PolicyInsights",
        "Microsoft.ResourceHealth",
        "Microsoft.Capacity",
        "Microsoft.ManagedServices",
        "Microsoft.Management",
        "Microsoft.SecurityInsights",
        "Microsoft.Blueprint",
        "Microsoft.Cache",
        "Microsoft.RecoveryServices",
        "Microsoft.HybridCompute",
        "Microsoft.HybridConnectivity",
        "Microsoft.AzureArcData"
    )

    foreach ($provider in $resourceProviders) {
        $logObj.Timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        $logObj.SubscriptionId = $sub.Id
        $logObj.ProviderNamespace = $provider
        try {
            Write-Host "Registering resource provider: $provider"
            Register-AzResourceProvider -ProviderNamespace $provider -ErrorAction Stop
            Write-Host -ForegroundColor Green "$provider registered successfully."
            $logObj.Status = "Success"
        } catch {
            Write-Host -ForegroundColor Red "Failed to register ($provider): $_"
            $logObj.ErrorMessage = $_.Exception.Message
            $logObj.Status = "Failed"
        }
        finally {
                $log += $logObj
        }
    }
}

$successCount = ($log | Where-Object { $_.Status -eq "Success" }).Count
$failureCount = ($log | Where-Object { $_.Status -eq "Failed" }).Count
Write-Host "Resource provider registration completed."
Write-Host "Total providers registered successfully: $successCount"
Write-Host "Total providers failed to register: $failureCount"
foreach ($failed in $log | Where-Object { $_.Status -eq "Failed" }) {
    Write-Host "Failed to register provider: $($failed.ProviderNamespace) in subscription: $($failed.SubscriptionId) - Error: $($failed.ErrorMessage)"
}