$global:OS
$global:dngConverter

if ($IsMacOS){
    Write-Host "MacOS"
    $OS = "MacOS"
    $global:dngConverter = "open -a '/Applications/Adobe DNG Converter.app/Contents/MacOS/Adobe DNG Converter' --args -c "
}elseif ($IsWindows){
    Write-Host "Windows"
    $OS = "Windows"
    $global:dngConverter = "'C:\Program Files\Adobe DNG Converter.exe' -c "
}elseif ($IsLinux){
    Write-Host "Linux"
    $OS = "Linux"
}else{
    Write-Host "What is this running on?"
}

