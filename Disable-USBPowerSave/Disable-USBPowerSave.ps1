# Disable PowerSave for USB Devices
$USBHubs = Get-WmiObject -Class Win32_USBHub
$PowerMgmt = Get-WmiObject -Class MSPower_DeviceEnable -Namespace root\wmi

foreach ($Hub in $USBHubs) {
    Write-Host "Checking USB Hub '$($Hub.Name)'..."
    $VarPowerSettings = $PowerMgmt | Where {$_.InstanceName -like "*$($Hub.DeviceID)*"}
    if (($VarPowerSettings | Measure).Count -eq 1) {
        $VarPowerSettings.Enable = $False
        #$VarPowerSettings
    }
}