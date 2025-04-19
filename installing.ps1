Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName System.Windows.Forms

# Log file for debugging
$logFile = "$env:TEMP\installing_debug.log"
"Starting script at $(Get-Date)" | Out-File -FilePath $logFile -Append

try {
    # Check if running as Administrator
    $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    "Admin check: IsAdmin=$isAdmin" | Out-File -FilePath $logFile -Append
    if (-not $isAdmin) {
        "Not running as admin, attempting to relaunch..." | Out-File -FilePath $logFile -Append
        Start-Process powershell -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
        "Relaunch command issued" | Out-File -FilePath $logFile -Append
        exit
    }

    "Admin privileges confirmed" | Out-File -FilePath $logFile -Append

    function ProgramIsInstalled($programId) {
        "Checking if $programId is installed..." | Out-File -FilePath $logFile -Append
        $result = winget list --id $programId --exact 2>&1
        "Raw winget list output for $programId`: $result" | Out-File -FilePath $logFile -Append
        $isInstalled = ($result -match "^$([regex]::Escape($programId))\s")
        "Result for $programId IsInstalled=$isInstalled" | Out-File -FilePath $logFile -Append
        return $isInstalled
    }

    function InstallProgramIfNeeded($programId, $name, $progressBar, $consoleTextBox, $totalSteps, $currentStep) {
        "Starting installation for $name ($programId), Step $currentStep/$totalSteps" | Out-File -FilePath $logFile -Append
        $consoleTextBox.AppendText("Installing $name...`n")
        $consoleTextBox.ScrollToEnd()
        $progressBar.Value = ($currentStep / $totalSteps) * 100
        $progressBar.Dispatcher.Invoke([Action]{}, "Render")

        if (-not (ProgramIsInstalled $programId)) {
            "Running winget install for $programId..." | Out-File -FilePath $logFile -Append
            try {
                $process = Start-Process winget -ArgumentList "install --id $programId -e --accept-source-agreements --accept-package-agreements --silent" -Wait -NoNewWindow -PassThru
                if ($process.ExitCode -eq 0) {
                    $consoleTextBox.AppendText("$name installed successfully.`n")
                    "Installation of $name succeeded." | Out-File -FilePath $logFile -Append
                } else {
                    $consoleTextBox.AppendText("Error installing $name. Exit code: $($process.ExitCode)`n")
                    "Installation of $name failed with exit code: $($process.ExitCode)" | Out-File -FilePath $logFile -Append
                }
            } catch {
                $consoleTextBox.AppendText("Error installing $name - $_`n")
                "Exception installing $name - $_" | Out-File -FilePath $logFile -Append
            }
        } else {
            $consoleTextBox.AppendText("$name is already installed.`n")
            "$name is already installed." | Out-File -FilePath $logFile -Append
        }
        $consoleTextBox.ScrollToEnd()
        $progressBar.Dispatcher.Invoke([Action]{}, "Render")
    }

    function UpdateAllPrograms($progressBar, $consoleTextBox, $totalSteps, $currentStep) {
        "Starting update for all programs, Step $currentStep/$totalSteps" | Out-File -FilePath $logFile -Append
        $consoleTextBox.AppendText("Updating all installed winget packages...`n")
        $consoleTextBox.ScrollToEnd()
        $progressBar.Value = ($currentStep / $totalSteps) * 100
        $progressBar.Dispatcher.Invoke([Action]{}, "Render")

        try {
            $process = Start-Process winget -ArgumentList "upgrade --all --accept-source-agreements --accept-package-agreements --silent" -Wait -NoNewWindow -PassThru
            if ($process.ExitCode -eq 0) {
                $consoleTextBox.AppendText("Update complete.`n")
                "Update completed successfully." | Out-File -FilePath $logFile -Append
            } else {
                $consoleTextBox.AppendText("Error updating programs. Exit code: $($process.ExitCode)`n")
                "Update failed with exit code: $($process.ExitCode)" | Out-File -FilePath $logFile -Append
            }
        } catch {
            $consoleTextBox.AppendText("Error updating programs: $_`n")
            "Exception updating programs: $_" | Out-File -FilePath $logFile -Append
        }
        $consoleTextBox.ScrollToEnd()
        $progressBar.Dispatcher.Invoke([Action]{}, "Render")
    }

    function Get-SystemInfo {
        "Retrieving system info..." | Out-File -FilePath $logFile -Append
        $gpu = (Get-WmiObject Win32_VideoController | Where-Object { $_.Name -notmatch "Meta|Virtual|Remote|DisplayLink" } | Select-Object -First 1 -ExpandProperty Name)
        $cpu = (Get-WmiObject Win32_Processor | Select-Object -First 1 -ExpandProperty Name)
        $ramModules = Get-CimInstance Win32_PhysicalMemory
        $ramTotal = [math]::Round(($ramModules | Measure-Object -Property Capacity -Sum).Sum / 1GB)
        $ramSpeeds = ($ramModules | Select-Object -ExpandProperty Speed | Sort-Object -Unique) -join ", "
        $drives = Get-PSDrive | Where-Object { $_.Provider -like '*FileSystem*' -and $null -ne $_.Used }
        $diskInfo = foreach ($drive in $drives) { "$($drive.Name): $([math]::Round($drive.Free / 1GB)) GB frei `n" }

        $info = @{
            GPU = $gpu
            CPU = $cpu
            RAM = "$ramTotal GB ($ramSpeeds MT/s)"
            DISK = $diskInfo -join "`n"
        }
        "System info: GPU=$($info.GPU), CPU=$($info.CPU)" | Out-File -FilePath $logFile -Append
        return $info
    }

    function DetectGPUVendor {
        "Detecting GPU vendor..." | Out-File -FilePath $logFile -Append
        $gpus = Get-WmiObject Win32_VideoController | Where-Object { $_.Name -notmatch "Meta|Virtual|Remote|DisplayLink" }
        foreach ($gpu in $gpus) {
            if ($gpu.Name -match "NVIDIA") { return "NVIDIA" }
            elseif ($gpu.Name -match "AMD") { return "AMD" }
        }
        return "Unknown"
    }

    $info = Get-SystemInfo

    [xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        Title="Post-Install Setup" Height="720" Width="880" ResizeMode="NoResize" WindowStartupLocation="CenterScreen">
    <Border BorderThickness="2" BorderBrush="Gray" Padding="10" Margin="10">
        <Grid>
            <Grid.RowDefinitions>
                <RowDefinition Height="*"/>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="100"/>
            </Grid.RowDefinitions>
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width="*" />
                <ColumnDefinition Width="*" />
                <ColumnDefinition Width="250" />
            </Grid.ColumnDefinitions>

            <!-- Spalte 1: Browser / Gaming -->
            <StackPanel Grid.Column="0" Margin="10">
                <TextBlock FontSize="14" FontWeight="Bold">Browser</TextBlock>
                <CheckBox Name="chkChrome">Google Chrome</CheckBox>
                <CheckBox Name="chkFirefox">Mozilla Firefox</CheckBox>
                <CheckBox Name="chkOpera">Opera</CheckBox>
                <CheckBox Name="chkOperaGx">OperaGX</CheckBox>
                <CheckBox Name="chkBrave">Brave Browser</CheckBox>

                <TextBlock FontSize="14" FontWeight="Bold" Margin="0,15,0,0">Gaming</TextBlock>
                <CheckBox Name="chkSteam">Steam</CheckBox>
                <CheckBox Name="chkDiscord">Discord</CheckBox>
                <CheckBox Name="chkCurseForge">CurseForge</CheckBox>
                <CheckBox Name="chkRiot">Riot Games Client</CheckBox>
                <CheckBox Name="chkLoL">League of Legends (EUW)</CheckBox>
                <CheckBox Name="chkGOG">GOG Galaxy</CheckBox>
                <CheckBox Name="chkEpic">Epic Games Launcher</CheckBox>
                <CheckBox Name="chkBattleNet">Battle.net</CheckBox>
                <CheckBox Name="chkOverwolf">Overwolf</CheckBox>
            </StackPanel>

            <!-- Spalte 2: Coding / Tools / Benchmarks -->
            <StackPanel Grid.Column="1" Margin="10">
                <TextBlock FontSize="14" FontWeight="Bold">Code Stuff</TextBlock>
                <CheckBox Name="chkVSC">Visual Studio Code</CheckBox>
                <CheckBox Name="chkUnity">Unity Hub</CheckBox>
                <CheckBox Name="chkGitHub">GitHub Desktop</CheckBox>
                <CheckBox Name="chkGit">Git</CheckBox>
                <CheckBox Name="chkPython">Python 3.12</CheckBox>
                <CheckBox Name="chkObsidian">Obsidian</CheckBox>

                <TextBlock FontSize="14" FontWeight="Bold" Margin="0,15,0,0">Tools</TextBlock>
                <CheckBox Name="chkDrive">Google Drive</CheckBox>
                <CheckBox Name="chkVLC">VLC Media Player</CheckBox>
                <CheckBox Name="chkNord">NordVPN</CheckBox>
                <CheckBox Name="chkJava">Java Runtime Environment</CheckBox>
                <CheckBox Name="chkKeePassXC">KeePassXC</CheckBox>
                <CheckBox Name="chkAudacity">Audacity</CheckBox>
                <CheckBox Name="chkShareX">ShareX</CheckBox>
                <CheckBox Name="chkFileZilla">FileZilla</CheckBox>
                <CheckBox Name="chkOBS">OBS Studio</CheckBox>
                <CheckBox Name="chkZoom">Zoom</CheckBox>
                <CheckBox Name="chkTeams">Microsoft Teams</CheckBox>

                <TextBlock FontSize="14" FontWeight="Bold" Margin="0,15,0,0">Benchmarks</TextBlock>
                <CheckBox Name="chkHWInfo">HWInfo</CheckBox>
                <CheckBox Name="chkGPUZ">GPU-Z</CheckBox>
                <CheckBox Name="chkCPUZ">CPU-Z</CheckBox>
                <CheckBox Name="chkCinebench">Cinebench R23</CheckBox>
                <CheckBox Name="chkFurMark">FurMark</CheckBox>

                <TextBlock FontSize="14" FontWeight="Bold" Margin="0,15,0,0">System</TextBlock>
                <CheckBox Name="chkUpdateAll">Alle Programme aktualisieren</CheckBox>

                <Button Name="btnInstall" Content="Installieren" Margin="0,20,0,0" Width="160" HorizontalAlignment="Left" />
            </StackPanel>

            <!-- Spalte 3: Systeminfo + Quicklinks -->
            <StackPanel Grid.Column="2" Margin="10">
                <TextBlock FontSize="14" FontWeight="Bold" Margin="0,0,0,5">Systeminfo</TextBlock>
                <TextBlock Text="GPU: $($info.GPU)" Margin="0,0,0,5"/>
                <TextBlock Text="CPU: $($info.CPU)" Margin="0,0,0,5"/>
                <TextBlock Text="RAM: $($info.RAM)" Margin="0,0,0,5"/>
                <TextBlock Text="Disk: $($info.DISK)" Margin="0,0,0,15"/>

                <TextBlock FontSize="14" FontWeight="Bold" Margin="0,0,0,5">Quicklinks</TextBlock>
                <Button Name="btnTaskmgr" Content="Taskmanager" Margin="0,0,0,5"/>
                <Button Name="btnExplorer" Content="Explorer" Margin="0,0,0,5"/>
                <Button Name="btnDiskMgmt" Content="Datentraegerverwaltung"/>
            </StackPanel>

            </Grid>
    </Border>
</Window>
"@

    "XAML defined" | Out-File -FilePath $logFile -Append
    $reader = (New-Object System.Xml.XmlNodeReader $xaml)
    "XAML reader created" | Out-File -FilePath $logFile -Append
    $window = [Windows.Markup.XamlReader]::Load($reader)
    "Window loaded" | Out-File -FilePath $logFile -Append

    $controls = @{
        Chrome      = $window.FindName("chkChrome")
        Firefox     = $window.FindName("chkFirefox")
        Opera       = $window.FindName("chkOpera")
        OperaGx     = $window.FindName("chkOperaGx")
        Brave       = $window.FindName("chkBrave")
        Steam       = $window.FindName("chkSteam")
        Discord     = $window.FindName("chkDiscord")
        CurseForge  = $window.FindName("chkCurseForge")
        Riot        = $window.FindName("chkRiot")
        LoL         = $window.FindName("chkLoL")
        GOG         = $window.FindName("chkGOG")
        Epic        = $window.FindName("chkEpic")
        BattleNet   = $window.FindName("chkBattleNet")
        Overwolf    = $window.FindName("chkOverwolf")
        VSC         = $window.FindName("chkVSC")
        Unity       = $window.FindName("chkUnity")
        GitHub      = $window.FindName("chkGitHub")
        Git         = $window.FindName("chkGit")
        Python      = $window.FindName("chkPython")
        Obsidian    = $window.FindName("chkObsidian")
        Drive       = $window.FindName("chkDrive")
        VLC         = $window.FindName("chkVLC")
        Nord        = $window.FindName("chkNord")
        Java        = $window.FindName("chkJava")
        KeePassXC   = $window.FindName("chkKeePassXC")
        Audacity    = $window.FindName("chkAudacity")
        ShareX      = $window.FindName("chkShareX")
        FileZilla   = $window.FindName("chkFileZilla")
        OBS         = $window.FindName("chkOBS")
        Zoom        = $window.FindName("chkZoom")
        Teams       = $window.FindName("chkTeams")
        HWInfo      = $window.FindName("chkHWInfo")
        GPUZ        = $window.FindName("chkGPUZ")
        CPUZ        = $window.FindName("chkCPUZ")
        Cinebench   = $window.FindName("chkCinebench")
        FurMark     = $window.FindName("chkFurMark")
        UpdateAll   = $window.FindName("chkUpdateAll")
    }
    "Controls initialized" | Out-File -FilePath $logFile -Append

    # Install-Button-Handler
    $window.FindName("btnInstall").Add_Click({
        "Install button clicked" | Out-File -FilePath $logFile -Append
        $window.Close()

        # Create a new window for progress
        [xml]$progressXaml = @"
        <Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
                Title="Installation Progress" Height="300" Width="500" ResizeMode="NoResize" WindowStartupLocation="CenterScreen">
            <Grid>
                <Grid.RowDefinitions>
                    <RowDefinition Height="*"/>
                    <RowDefinition Height="Auto"/>
                </Grid.RowDefinitions>
                <TextBox Name="consoleOutput" Grid.Row="0" Margin="10" IsReadOnly="True" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Auto" AcceptsReturn="True"/>
                <ProgressBar Name="progressBar" Grid.Row="1" Height="20" Margin="10,0,10,10" Minimum="0" Maximum="100" Value="0"/>
            </Grid>
        </Window>
"@
        "Progress XAML defined" | Out-File -FilePath $logFile -Append
        $progressReader = (New-Object System.Xml.XmlNodeReader $progressXaml)
        $progressWindow = [Windows.Markup.XamlReader]::Load($progressReader)
        $progressBar = $progressWindow.FindName("progressBar")
        $consoleTextBox = $progressWindow.FindName("consoleOutput")
        "Progress window loaded" | Out-File -FilePath $logFile -Append

        # Calculate total steps for progress bar
        $currentStep = 0
        $totalSteps = ($controls.GetEnumerator() | Where-Object { $_.Value.IsChecked }).Count
        if ($controls.UpdateAll.IsChecked) { $totalSteps++ }
        $gpu = DetectGPUVendor
        if ($gpu -eq "NVIDIA" -or $gpu -eq "AMD") { $totalSteps++ }
        if ($totalSteps -eq 0) { 
            $totalSteps = 1
            $consoleTextBox.AppendText("No programs selected for installation.`n")
            $consoleTextBox.ScrollToEnd()
            "No programs selected, waiting before closing" | Out-File -FilePath $logFile -Append
            Start-Sleep -Seconds 5
            $progressWindow.Close()
            return
        }
        "Total steps: $totalSteps" | Out-File -FilePath $logFile -Append

        # Show progress window
        $progressWindow.Show()
        "Progress window shown" | Out-File -FilePath $logFile -Append

        # Installation logic
        if ($controls.Chrome.IsChecked)     { $currentStep++; InstallProgramIfNeeded "Google.Chrome" "Google Chrome" $progressBar $consoleTextBox $totalSteps $currentStep }
        if ($controls.Firefox.IsChecked)    { $currentStep++; InstallProgramIfNeeded "Mozilla.Firefox" "Mozilla Firefox" $progressBar $consoleTextBox $totalSteps $currentStep }
        if ($controls.Opera.IsChecked)      { $currentStep++; InstallProgramIfNeeded "Opera.Opera" "Opera Browser" $progressBar $consoleTextBox $totalSteps $currentStep }
        if ($controls.OperaGx.IsChecked)    { $currentStep++; InstallProgramIfNeeded "Opera.OperaGX" "OperaGx Browser" $progressBar $consoleTextBox $totalSteps $currentStep }
        if ($controls.Brave.IsChecked)      { $currentStep++; InstallProgramIfNeeded "Brave.Brave" "Brave Browser" $progressBar $consoleTextBox $totalSteps $currentStep }
        if ($controls.Steam.IsChecked)      { $currentStep++; InstallProgramIfNeeded "Valve.Steam" "Steam" $progressBar $consoleTextBox $totalSteps $currentStep }
        if ($controls.Discord.IsChecked)    { $currentStep++; InstallProgramIfNeeded "Discord.Discord" "Discord" $progressBar $consoleTextBox $totalSteps $currentStep }
        if ($controls.CurseForge.IsChecked) { $currentStep++; InstallProgramIfNeeded "Overwolf.CurseForge" "CurseForge" $progressBar $consoleTextBox $totalSteps $currentStep }
        if ($controls.Riot.IsChecked)       { $currentStep++; InstallProgramIfNeeded "RiotGames.RiotClient" "Riot Client" $progressBar $consoleTextBox $totalSteps $currentStep }
        if ($controls.LoL.IsChecked)        { $currentStep++; InstallProgramIfNeeded "RiotGames.LeagueOfLegends.EUW" "League of Legends EUW" $progressBar $consoleTextBox $totalSteps $currentStep }
        if ($controls.GOG.IsChecked)        { $currentStep++; InstallProgramIfNeeded "GOG.Galaxy" "GOG Galaxy" $progressBar $consoleTextBox $totalSteps $currentStep }
        if ($controls.Epic.IsChecked)       { $currentStep++; InstallProgramIfNeeded "EpicGames.EpicGamesLauncher" "Epic Games Launcher" $progressBar $consoleTextBox $totalSteps $currentStep }
        if ($controls.BattleNet.IsChecked)  { $currentStep++; InstallProgramIfNeeded "Blizzard.BattleNet" "Battle.net" $progressBar $consoleTextBox $totalSteps $currentStep }
        if ($controls.Overwolf.IsChecked)   { $currentStep++; InstallProgramIfNeeded "Overwolf.Overwolf" "Overwolf" $progressBar $consoleTextBox $totalSteps $currentStep }
        if ($controls.VSC.IsChecked)        { $currentStep++; InstallProgramIfNeeded "Microsoft.VisualStudioCode" "Visual Studio Code" $progressBar $consoleTextBox $totalSteps $currentStep }
        if ($controls.Unity.IsChecked)      { $currentStep++; InstallProgramIfNeeded "UnityTechnologies.UnityHub" "Unity Hub" $progressBar $consoleTextBox $totalSteps $currentStep }
        if ($controls.GitHub.IsChecked)     { $currentStep++; InstallProgramIfNeeded "GitHub.GitHubDesktop" "GitHub Desktop" $progressBar $consoleTextBox $totalSteps $currentStep }
        if ($controls.Git.IsChecked)        { $currentStep++; InstallProgramIfNeeded "Git.Git" "Git" $progressBar $consoleTextBox $totalSteps $currentStep }
        if ($controls.Python.IsChecked)     { $currentStep++; InstallProgramIfNeeded "Python.Python.3.12" "Python 3.12" $progressBar $consoleTextBox $totalSteps $currentStep }
        if ($controls.Obsidian.IsChecked)   { $currentStep++; InstallProgramIfNeeded "Obsidian.Obsidian" "Obsidian" $progressBar $consoleTextBox $totalSteps $currentStep }
        if ($controls.Drive.IsChecked)      { $currentStep++; InstallProgramIfNeeded "Google.Drive" "Google Drive" $progressBar $consoleTextBox $totalSteps $currentStep }
        if ($controls.VLC.IsChecked)        { $currentStep++; InstallProgramIfNeeded "VideoLAN.VLC" "VLC Media Player" $progressBar $consoleTextBox $totalSteps $currentStep }
        if ($controls.Nord.IsChecked)       { $currentStep++; InstallProgramIfNeeded "NordSecurity.NordVPN" "NordVPN" $progressBar $consoleTextBox $totalSteps $currentStep }
        if ($controls.Java.IsChecked)       { $currentStep++; InstallProgramIfNeeded "Oracle.JavaRuntimeEnvironment" "Java Runtime Environment" $progressBar $consoleTextBox $totalSteps $currentStep }
        if ($controls.KeePassXC.IsChecked)  { $currentStep++; InstallProgramIfNeeded "KeePassXC.KeePassXC" "KeePassXC" $progressBar $consoleTextBox $totalSteps $currentStep }
        if ($controls.Audacity.IsChecked)   { $currentStep++; InstallProgramIfNeeded "Audacity.Audacity" "Audacity" $progressBar $consoleTextBox $totalSteps $currentStep }
        if ($controls.ShareX.IsChecked)     { $currentStep++; InstallProgramIfNeeded "ShareX.ShareX" "ShareX" $progressBar $consoleTextBox $totalSteps $currentStep }
        if ($controls.FileZilla.IsChecked)  { $currentStep++; InstallProgramIfNeeded "FileZilla.FileZilla" "FileZilla" $progressBar $consoleTextBox $totalSteps $currentStep }
        if ($controls.OBS.IsChecked)        { $currentStep++; InstallProgramIfNeeded "OBSProject.OBSStudio" "OBS Studio" $progressBar $consoleTextBox $totalSteps $currentStep }
        if ($controls.Zoom.IsChecked)       { $currentStep++; InstallProgramIfNeeded "Zoom.Zoom" "Zoom" $progressBar $consoleTextBox $totalSteps $currentStep }
        if ($controls.Teams.IsChecked)      { $currentStep++; InstallProgramIfNeeded "Microsoft.Teams" "Microsoft Teams" $progressBar $consoleTextBox $totalSteps $currentStep }
        if ($controls.HWInfo.IsChecked)     { $currentStep++; InstallProgramIfNeeded "REALiX.HWinfo" "HWInfo" $progressBar $consoleTextBox $totalSteps $currentStep }
        if ($controls.GPUZ.IsChecked)       { $currentStep++; InstallProgramIfNeeded "TechPowerUp.GPU-Z" "GPU-Z" $progressBar $consoleTextBox $totalSteps $currentStep }
        if ($controls.CPUZ.IsChecked)       { $currentStep++; InstallProgramIfNeeded "CPUID.CPU-Z" "CPU-Z" $progressBar $consoleTextBox $totalSteps $currentStep }
        if ($controls.Cinebench.IsChecked)  { $currentStep++; InstallProgramIfNeeded "Maxon.CinebenchR23" "Cinebench R23" $progressBar $consoleTextBox $totalSteps $currentStep }
        if ($controls.FurMark.IsChecked)    { $currentStep++; InstallProgramIfNeeded "Geeks3D.FurMark" "FurMark" $progressBar $consoleTextBox $totalSteps $currentStep }
        if ($controls.UpdateAll.IsChecked)  { $currentStep++; UpdateAllPrograms $progressBar $consoleTextBox $totalSteps $currentStep }

        $consoleTextBox.AppendText("Detected GPU: $gpu`n")
        $consoleTextBox.ScrollToEnd()
        switch ($gpu) {
            "NVIDIA" { 
                $currentStep++; 
                InstallProgramIfNeeded "TechPowerUp.NVCleanstall" "NVIDIA Driver NVCleaninstaller" $progressBar $consoleTextBox $totalSteps $currentStep 
            }
           "AMD" {
                $currentStep++
                $consoleTextBox.AppendText("AMD GPU erkannt – öffne Support-Seite für manuelle Treiberwahl...`n")
                Start-Process "https://www.amd.com/en/support"
                $consoleTextBox.ScrollToEnd()
            }
            default  { 
                $consoleTextBox.AppendText("Unknown GPU vendor.`n") 
                $consoleTextBox.ScrollToEnd()
            }
        }

        $consoleTextBox.AppendText("All installations complete. Waiting 15 seconds before closing...`n")
        $consoleTextBox.ScrollToEnd()
        $progressBar.Value = 100
        $progressBar.Dispatcher.Invoke([Action]{}, "Render")
        "Installations complete, waiting before closing" | Out-File -FilePath $logFile -Append
        Start-Sleep -Seconds 15
        $progressWindow.Close()
        "Closing progress window" | Out-File -FilePath $logFile -Append
        "Reboot skipped for testing" | Out-File -FilePath $logFile -Append
    })

    # Quicklinks
    $window.FindName("btnTaskmgr").Add_Click({ Start-Process taskmgr })
    $window.FindName("btnExplorer").Add_Click({ Start-Process explorer })
    $window.FindName("btnDiskMgmt").Add_Click({ Start-Process diskmgmt.msc })
    "Quicklinks initialized" | Out-File -FilePath $logFile -Append

    "Showing GUI" | Out-File -FilePath $logFile -Append
    $window.ShowDialog() | Out-Null
} catch {
    "Error: $_" | Out-File -FilePath $logFile -Append
    throw
}