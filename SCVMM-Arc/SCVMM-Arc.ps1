[CmdletBinding()]
Param(
    [switch] $Force
)
# Start Region: Set user inputs

$location = 'eastus'

$applianceSubscriptionId = '21aa5d63-d9d9-4fa0-95a8-d87f592537f4'
$applianceResourceGroupName = 'rg-sharedsvcs-ncus01'
$applianceName = 'rb-sharedsvcs-scvmm-ncus01'

$customLocationSubscriptionId = '21aa5d63-d9d9-4fa0-95a8-d87f592537f4'
$customLocationResourceGroupName = 'rg-sharedsvcs-ncus01'
$customLocationName = 'MainDC'

$vmmserverSubscriptionId = '21aa5d63-d9d9-4fa0-95a8-d87f592537f4'
$vmmserverResourceGroupName = 'rg-sharedsvcs-ncus01'
$vmmserverName = 'opprdscvmm01'

# End Region: Set user inputs

function confirmationPrompt($msg) {
    Write-Host $msg
    while ($true) {
        $inp = Read-Host "Yes(y)/No(n)?"
        $inp = $inp.ToLower()
        if ($inp -eq 'y' -or $inp -eq 'yes') {
            return $true
        }
        elseif ($inp -eq 'n' -or $inp -eq 'no') {
            return $false
        }
    }
}

$logFile = "arcvmm-output.log"
$vmmConnectLogFile = "arcvmm-connect.log"

function logH1($msg) {
    $pattern = '0-' * 40
    $spaces = ' ' * (40 - $msg.length / 2)
    $nl = [Environment]::NewLine
    $msgFull = "$nl $nl $pattern $nl $spaces $msg $nl $pattern $nl"
    Write-Host -ForegroundColor Green $msgFull
    Write-Output $msgFull >> $logFile
}

function logH2($msg) {
    $msgFull = "==> $msg"
    Write-Host -ForegroundColor Magenta $msgFull
    Write-Output $msgFull >> $logFile
}

function logH3($msg) {
    $msgFull = "==> $msg"
    Write-Host -ForegroundColor Red $msgFull
    Write-Output $msgFull >> $logFile
}

function logH4($msg) {
    Write-Host -ForegroundColor Magenta $msg
}

function showSupportMsg($msg) {
    $pattern = '*' * 115
    $nl = [Environment]::NewLine
    $spaces = ' ' * 115
    $msgFull = "$nl $nl $pattern $nl $spaces $msg $nl $spaces $nl $pattern"
    Write-Host -ForegroundColor Green -BackgroundColor Black $msgFull
    Write-Output $msgFull >> $logFile
}

function logText($msg) {
    Write-Host "$msg"
    Write-Output "$msg" >> $logFile
}

function createRG($subscriptionId, $rgName) {
    $group = (az group show --subscription $subscriptionId -n $rgName)
    if (!$group) {
        logText "Resource Group $rgName does not exist in subscription $subscriptionId. Trying to create the resource group"
        az group create --subscription $subscriptionId -l $location -n $rgName
    }
}

function fail($msg) {
    $msg = "Script execution failed with error: " + $msg
    Write-Host -ForegroundColor Red $msg
    Write-Output "$msg" >> $logFile
    logText "The script will terminate shortly"
    Start-Sleep -Seconds 5
    exit 1
}

function VMMConnectInstruction() {
    logH4 "`taz scvmm vmmserver connect --tags `"`" --subscription `"$vmmserverSubscriptionId`" --resource-group `"$vmmserverResourceGroupName`" --name `"$vmmserverName`" --location `"$location`" --custom-location `"$customLocationId`""
}

if ((Get-Host).Name -match "ISE") {
    fail "The script is not supported in PowerShell ISE window, please run it in a regular PowerShell window"
}

$supportMsg = "`nPlease reach out to arc-vmm-feedback@microsoft.com or create a support ticket for Arc enabled SCVMM in Azure portal."
$deployKVATimeoutMsg = "`nPlease reach out to arc-vmm-feedback@microsoft.com or create a support ticket for Arc enabled SCVMM in Azure portal.`nIn case of DeployKvaTimeoutError please run the following steps to collect the logs to send it to arc-vmm-feedback@microsoft.com `n`t`"az arcappliance logs scvmm [Appliance_VM_IP]`"`nwhere Appliance_VM_IP is the IP of the Appliance VM Created in SCVMM"

logH1 "Step 1/5: Setting up the current workstation"

if (!$UseProxy -and (confirmationPrompt -msg "Is the current workstation behind a proxy?")) {
    $UseProxy = $true
}

Write-Host "Setting the TLS Protocol for the current session to TLS 1.2."
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$proxyCA = ""

if ($UseProxy) {
    logH2 "Provide proxy details"
    $proxyURL = Read-Host "Please Enter Proxy URL, Ex) http://[URL]:[PORT] (press enter to skip if you don't use HTTP proxy)"
    if ($proxyURL.StartsWith("http") -ne $true) {
        $proxyURL = "http://$proxyURL"
    }

    $noProxy = Read-Host "No Proxy (comma separated)"

    $env:http_proxy = $proxyURL
    $env:HTTP_PROXY = $proxyURL
    $env:https_proxy = $proxyURL
    $env:HTTPS_PROXY = $proxyURL
    $env:no_proxy = $noProxy
    $env:NO_PROXY = $noProxy

    $proxyCA = Read-Host "Proxy CA cert path (Press enter to skip)"
    if ($proxyCA -ne "") {
        $proxyCA = Resolve-Path -Path $proxyCA
    }

    $credential = $null
    $proxyAddr = $proxyURL

    if ($proxyURL.Contains("@")) {
        $x = $proxyURL.Split("//")
        $proto = $x[0]
        $x = $x[2].Split("@")
        $userPass = $x[0]
        $proxyAddr = $proto + "//" + $x[1]
        $x = $userPass.Split(":")
        $proxyUsername = $x[0]
        $proxyPassword = $x[1]
        $password = ConvertTo-SecureString -String $proxyPassword -AsPlainText -Force
        $credential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $proxyUsername, $password
    }

    [system.net.webrequest]::defaultwebproxy = new-object system.net.webproxy($proxyAddr)
    [system.net.webrequest]::defaultwebproxy.credentials = $credential
    [system.net.webrequest]::defaultwebproxy.BypassProxyOnLocal = $true
}

$forceApplianceRun = ""
if ($Force) { $forceApplianceRun = "--force" }

# Start Region: Create python virtual environment for azure cli

logH2 "Creating a temporary folder in the current directory (.temp)"
New-Item -Force -Path "." -Name ".temp" -ItemType "directory" > $null

$ProgressPreference = 'SilentlyContinue'

logH2 "Validating and installing 64-bit python"
try {
    $bitSize = py -c "import struct; print(struct.calcsize('P') * 8)"
    if ($bitSize -ne "64") {
        throw "Python is not 64-bit"
    }
    logText "64-bit python is already installed"
}
catch {
    logText "Installing python..."
    Invoke-WebRequest -Uri "https://www.python.org/ftp/python/3.8.8/python-3.8.8-amd64.exe" -OutFile ".temp/python-3.8.8-amd64.exe"
    $p = Start-Process .\.temp\python-3.8.8-amd64.exe -Wait -PassThru -ArgumentList '/quiet InstallAllUsers=0 PrependPath=1 Include_test=0'
    $exitCode = $p.ExitCode
    if ($exitCode -ne 0) {
        throw "Python installation failed with exit code $LASTEXITCODE"
    }
}
$ProgressPreference = 'Continue'

logText "Enabling long path support for python..."
Start-Process powershell.exe -verb runas -ArgumentList "Set-ItemProperty -Path HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem -Name LongPathsEnabled -Value 1" -Wait

py -m venv .temp\.env

logH2 "Installing azure cli."
logText "This might take a while..."
if ($proxyCA -ne "") {
    .temp\.env\Scripts\python.exe -m pip install --cert $proxyCA --upgrade pip wheel setuptools >> $logFile
    .temp\.env\Scripts\pip install --cert $proxyCA azure-cli>=2.41.0 >> $logFile
}
else {
    .temp\.env\Scripts\python.exe -m pip install --upgrade pip wheel setuptools >> $logFile
    .temp\.env\Scripts\pip install azure-cli>=2.41.0 >> $logFile
}

.temp\.env\Scripts\Activate.ps1

# End Region: Create python virtual environment for azure cli

try {
    if ($proxyCA -ne "") {
        $env:REQUESTS_CA_BUNDLE = $proxyCA
    }

    $azVersionMinimum = "2.41.0"
    $azVersionInstalled = (az version | ConvertFrom-Json | Select-Object -ExpandProperty 'azure-cli')
    if (!$azVersionInstalled) {
        throw "azure-cli is not installed. Please install the latest version from https://docs.microsoft.com/cli/azure/install-azure-cli"
    }
    if (!([version]$azVersionInstalled -ge [version]$azVersionMinimum)) {
        throw "We recommend to use the latest version of Azure CLI. The minimum required version is $azVersionMinimum.`nPlease upgrade az by running 'az upgrade' or download the latest version from https://docs.microsoft.com/cli/azure/install-azure-cli."
    }

    logH2 "Installing az cli extensions for Arc"
    az extension add --upgrade --name arcappliance
    az extension add --upgrade --name k8s-extension
    az extension add --upgrade --name customlocation
    az extension add --upgrade --name scvmm

    logH2 "Logging into azure"

    $azLoginMsg = "Please login to Azure CLI.`n" +
    "`t* If you're running the script for the first time, select yes.`n" +
    "`t* If you've recently logged in to az while running the script, you can select no.`n" +
    "Confirm login to azure cli?"
    if (confirmationPrompt -msg $azLoginMsg) {
        az login --use-device-code -o table
    }

    az account set -s $applianceSubscriptionId
    if ($LASTEXITCODE) {
        $Error[0] | Out-String >> $logFile
        throw "The default subscription for the az cli context could not be set."
    }

    logH1 "Step 1/5: Workstation was set up successfully"

    createRG "$applianceSubscriptionId" "$applianceResourceGroupName"

    logH1 "Step 2/5: Creating the Arc resource bridge"
    logH2 "Provide VMMServer details to deploy Arc resource bridge VM. The credentials will be used by Arc resource bridge to update and scale itself."

    $applianceStatus = (az arcappliance show --subscription $applianceSubscriptionId --resource-group $applianceResourceGroupName --name $applianceName --query status -o tsv 2>> $logFile)
    if (($forceApplianceRun -ne "") -or ($applianceStatus -ne "Running")) {
    az arcappliance run scvmm --debug --tags "" $forceApplianceRun --subscription $applianceSubscriptionId --resource-group $applianceResourceGroupName --name $applianceName --location $location
    } else {
        logText "The Arc resource bridge is already running. Skipping the creation of resource bridge."
    }

    $applianceId = (az arcappliance show --subscription $applianceSubscriptionId --resource-group $applianceResourceGroupName --name $applianceName --query id -o tsv 2>> $logFile)
    if (!$applianceId) {
        showSupportMsg($deployKVATimeoutMsg)
        throw "Appliance creation has failed. $supportMsg"
    }
    logText "Waiting for the appliance to be ready..."
    for ($i = 1; $i -le 5; $i++) {
        Start-Sleep -Seconds 60
    $applianceStatus = (az resource show --debug --ids "$applianceId" --query 'properties.status' -o tsv 2>> $logFile)
        if ($applianceStatus -eq "Running") {
            break
        }
        logText "Appliance is not ready yet, retrying... ($i/5)"
    }
    if ($applianceStatus -ne "Running") {
        showSupportMsg($deployKVATimeoutMsg)
        throw "Appliance is not in running state. Current state: $applianceStatus. $supportMsg"
    }

    logH1 "Step 2/5: Arc resource bridge is up and running"
    logH1 "Step 3/5: Installing cluster extension"


    az k8s-extension create --debug --subscription $applianceSubscriptionId --resource-group $applianceResourceGroupName --name azure-vmmoperator --extension-type 'Microsoft.scvmm' --scope cluster --cluster-type appliances --cluster-name $applianceName --config Microsoft.CustomLocation.ServiceAccount=azure-vmmoperator 2>> $logFile

    $clusterExtensionId = (az k8s-extension show --subscription $applianceSubscriptionId --resource-group $applianceResourceGroupName --name azure-vmmoperator --cluster-type appliances --cluster-name $applianceName --query id -o tsv 2>> $logFile)
    if (!$clusterExtensionId) {
        logH2 "Cluster Extension Installation failed... Please rerun the script to continue the deployment"
        throw "Cluster extension installation failed."
    }
    $clusterExtensionState = (az resource show --debug --ids "$clusterExtensionId" --query 'properties.provisioningState' -o tsv 2>> $logFile)
    if ($clusterExtensionState -ne "Succeeded") {
        showSupportMsg($supportMsg)
        throw "Provisioning State of cluster extension is not succeeded. Current state: $clusterExtensionState. $supportMsg"
    }

    logH1 "Step 3/5: Cluster extension installed successfully"
    logH1 "Step 4/5: Creating custom location"

    createRG "$customLocationSubscriptionId" "$customLocationResourceGroupName"

    $customLocationNamespace = ("$customLocationName".ToLower() -replace '[^a-z0-9-]', '')
    az customlocation create --debug --tags "" --subscription $customLocationSubscriptionId --resource-group $customLocationResourceGroupName --name $customLocationName --location $location --namespace $customLocationNamespace --host-resource-id $applianceId --cluster-extension-ids $clusterExtensionId 2>> $logFile

    $customLocationId = (az customlocation show --subscription $customLocationSubscriptionId --resource-group $customLocationResourceGroupName --name $customLocationName --query id -o tsv 2>> $logFile)
    if (!$customLocationId) {
        logH2 "Custom location creation failed... Please rerun the same script to continue the deployment"
        throw "Custom location creation failed."
    }
    $customLocationState = (az resource show --debug --ids $customLocationId --query 'properties.provisioningState' -o tsv 2>> $logFile)
    if ($customLocationState -ne "Succeeded") {
        showSupportMsg($supportMsg)
        throw "Provisioning State of custom location is not succeeded. Current state: $customLocationState. $supportMsg"
    }

    logH1 "Step 4/5: Custom location created successfully"
    logH1 "Step 5/5: Connecting to VMMServer"

    createRG "$vmmserverSubscriptionId" "$vmmserverResourceGroupName"

    logH2 "Provide VMMServer details"
    logText "`t* These credentials will be used when you perform SCVMM operations through Azure."
    logText "`t* You can provide the same credentials that you provided for Arc resource bridge earlier."

    for($i=1; $i -le 3; $i++) {
        logText "Attempt to Connect to VMM Server... ($i/3)"
        if(Test-Path -Path $vmmConnectLogFile) {
            Clear-Content $vmmConnectLogFile
        }
        az scvmm vmmserver connect --debug --tags "" --subscription $vmmserverSubscriptionId --resource-group $vmmserverResourceGroupName --name $vmmserverName --location $location --custom-location $customLocationId 2>> $vmmConnectLogFile
        if($LASTEXITCODE -ne 0) {
            if(Select-String -Path $vmmConnectLogFile -Pattern 'RemoteHostUnreachable') {
                logH3 "`t Not able to connect to FQDN or IP Provided. Please retry with correct VMM FQDN or IP and Port..."
                continue
            }
            if(Select-String -Path $vmmConnectLogFile -Pattern 'AuthorizationFailed') {
                logH3 "`t Either User does not have the access or Credentials provided are incorrect. Please try again....."
                continue
            }
        }
        else {
            break
        }
    }

    $vmmserverId = (az scvmm vmmserver show --subscription $vmmserverSubscriptionId --resource-group $vmmserverResourceGroupName --name $vmmserverName --query id -o tsv 2>> $logFile)
    if (!$vmmserverId) {
        logH2 "VMM Server connect failed... Please run the following commands from any az cli to complete the onboarding or rerun the same script"
        VMMConnectInstruction
        throw "Connect VMMServer failed."
    }
    $vmmserverState = (az resource show --debug --ids "$vmmserverId" --query 'properties.provisioningState' -o tsv 2>> $logFile)
    if ($vmmserverState -ne "Succeeded") {
        showSupportMsg($supportMsg)
        throw "Provisioning State of VMMServer is not succeeded. Current state: $vmmserverState. $supportMsg"
    }

    logH1 "Step 5/5: VMMServer was connected successfully"
    logH1 "Your SCVMM has been successfully onboarded to Azure Arc!"
    logText "To continue onboarding and to complete Arc enabling your SCVMM resources, view your VMMServer resource in Azure portal.`nhttps://portal.azure.com/#resource${vmmserverId}/overview"
}
catch {
    $err = $_.Exception | Out-String
    fail $err
}