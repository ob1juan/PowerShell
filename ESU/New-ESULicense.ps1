# Install the Azure PowerShell module if not already installed
Install-Module -Name Az -Scope CurrentUser -Repository PSGallery -Force

# Import the Azure PowerShell module
Import-Module -Name Az

# Connect to your Azure account
Connect-AzAccount

# Get an authentication token
$token = (Get-AzAccessToken).Token

# Set the subscription ID, resource group name, and license name
$subscriptionId = "<your-subscription-id>"
$resourceGroupName = "<your-resource-group-name>"
$licenseName = "<your-license-name>"

# Construct the API URL
$url = "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$resourceGroupName/providers/Microsoft.HybridCompute/licenses/$licenseName?api-version=2023-06-20-preview"

# Create a header with the authorization token
$headers = @{'Authorization' = "Bearer $token"}

# Define the body as a JSON string
$body = @"
    { 
    "location": "ENTER-REGION",
        "properties": {
            "licenseDetails": {
            "state": "Activated",
            "target": "Windows Server 2012",
            "Edition": "Standard",
            "Type": "vCore",
            "Processors": 12
            }
        }
    }      
"@

# Invoke the REST API to create a license
Invoke-RestMethod -Method PUT -Uri $url -Headers $headers -Body $body
