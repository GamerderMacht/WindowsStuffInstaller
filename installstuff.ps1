Add-Type -AssemblyName PresentationFramework

function ProgramIsInstalled($programId) {
    $result = winget list --id $programId 2>&1
    return ($result -notmatch "No installed package found")
}

function InstallProgramIfNeeded($programId, $name) {
    if (-not (ProgramIsInstalled $programId)) {
        Write-Host "Installing $name..."
        Start-Process winget -ArgumentList "install --id $programId -e --accept-source-agreements --accept-package-agreements --silent" -Wait -NoNewWindow
    }
    else {
        Write-Host "$name is already installed."
    }
}

function DetectGPUVendor {
    $gpuInfo = Get-WmiObject Win32_VideoController | Select-Object -ExpandProperty Name
    if ($gpuInfo -match "NVIDIA") { return "NVIDIA" }
    elseif ($gpuInfo -match "AMD") { return "AMD" }
    else { return "Unknown" }
}

# XAML for GUI
[xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        Title="Post-Install Setup" Height="300" Width="300">
    <StackPanel Margin="10">
        <TextBlock FontWeight="Bold" Margin="0,0,0,10">Select programs to install:</TextBlock>
        <CheckBox Name="chkChrome">Google Chrome</CheckBox>
        <CheckBox Name="chkFirefox">Mozilla Firefox</CheckBox>
        <CheckBox Name="chkOpera">Opera Browser</CheckBox>
        <CheckBox Name="chkSteam" IsChecked="True">Steam</CheckBox>
        <CheckBox Name="chkDiscord" IsChecked="True">Discord</CheckBox>
        <Button Name="btnInstall" Margin="0,20,0,0" Width="100" HorizontalAlignment="Center">Install</Button>
    </StackPanel>
</Window>
"@

$reader = (New-Object System.Xml.XmlNodeReader $xaml)
$window = [Windows.Markup.XamlReader]::Load($reader)

$chkChrome = $window.FindName("chkChrome")
$chkFirefox = $window.FindName("chkFirefox")
$chkOpera = $window.FindName("chkOpera")
$chkSteam = $window.FindName("chkSteam")
$chkDiscord = $window.FindName("chkDiscord")
$btnInstall = $window.FindName("btnInstall")

$btnInstall.Add_Click({
    $window.Close()

    if ($chkChrome.IsChecked)  { InstallProgramIfNeeded "Google.Chrome" "Google Chrome" }
    if ($chkFirefox.IsChecked) { InstallProgramIfNeeded "Mozilla.Firefox" "Mozilla Firefox" }
    if ($chkOpera.IsChecked)   { InstallProgramIfNeeded "Opera.Opera" "Opera Browser" }
    if ($chkSteam.IsChecked)   { InstallProgramIfNeeded "Valve.Steam" "Steam" }
    if ($chkDiscord.IsChecked) { InstallProgramIfNeeded "Discord.Discord" "Discord" }

    $gpu = DetectGPUVendor
    Write-Host "Detected GPU: $gpu"
    switch ($gpu) {
        "NVIDIA" { InstallProgramIfNeeded "Nvidia.GeForceExperience" "NVIDIA Driver" }
        "AMD"    { InstallProgramIfNeeded "AdvancedMicroDevices.AMDSoftware" "AMD Driver" }
        default  { Write-Host "Unknown GPU vendor." }
    }

    Write-Host "`nAll installations complete. Rebooting in 15 seconds..."
    Start-Sleep -Seconds 15
    Restart-Computer -Force
})

$window.ShowDialog() | out-null
