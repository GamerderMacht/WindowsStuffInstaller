#
# Windows Stuff Installer - A PowerShell GUI for batch-installing applications with Winget.
#

#region SETUP AND CHECKS

# Load required assemblies for the GUI.
Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName System.Windows.Forms

# Set a log file for debugging purposes.
$logFile = "$env:TEMP\installing_debug.log"
"Starting script at $(Get-Date)" | Out-File -FilePath $logFile -Append

# --- Main Script Body ---
try {
    # -----------------------------------------------------------------------------------
    # STEP 1: Ensure the script is running with Administrator privileges.
    # This is required for installing applications system-wide.
    # -----------------------------------------------------------------------------------
    $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    "Admin check: IsAdmin=$isAdmin" | Out-File -FilePath $logFile -Append
    if (-not $isAdmin) {
        "Not running as admin, attempting to relaunch..." | Out-File -FilePath $logFile -Append
        # Relaunch the script with elevated privileges and exit the current one.
        Start-Process powershell -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
        exit
    }
    "Admin privileges confirmed." | Out-File -FilePath $logFile -Append

    # -----------------------------------------------------------------------------------
    # STEP 2: Find the correct Winget installation and fix the PATH.
    # This handles cases where multiple versions of Winget are installed and the PATH is incorrect.
    # -----------------------------------------------------------------------------------
    Write-Host "Searching for a modern Winget installation..."
    # Find the newest installed version of Winget (App Installer) that is not an old, broken preview.
    $package = Get-AppxPackage Microsoft.DesktopAppInstaller | Where-Object { $_.Version -notlike '1.12*' } | Sort-Object -Property Version -Descending | Select-Object -First 1

    if ($null -eq $package) {
        [System.Windows.Forms.MessageBox]::Show("CRITICAL ERROR: Could not find a modern Winget (Microsoft.DesktopAppInstaller) package. Please make sure you are logged into a Microsoft Account in the OS and that the 'App Installer' is updated in the Microsoft Store.", "Winget Not Found", "OK", "Error")
        exit
    }

    $installDir = $package.InstallLocation
    "Found Winget version $($package.Version) in: $installDir" | Out-File -FilePath $logFile -Append
    
    # Prepend the correct directory to the PATH for this PowerShell session.
    "Temporarily fixing PATH for this session..." | Out-File -FilePath $logFile -Append
    $env:PATH = "$installDir;$env:PATH"
    "PATH fixed. Winget version is now: $(winget --version)" | Out-File -FilePath $logFile -Append

    #endregion

    #region CORE FUNCTIONS

    # -----------------------------------------------------------------------------------
    # Initializes Winget to ensure the source agreements are accepted.
    # -----------------------------------------------------------------------------------
    function Initialize-Winget {
        "Initializing Winget to ensure sources are configured..." | Out-File -FilePath $logFile -Append
        try {
            # Run a harmless command to trigger the first-time setup and accept agreements.
            $process = Start-Process winget -ArgumentList "source list --accept-source-agreements" -Wait -NoNewWindow -PassThru
            if ($process.ExitCode -eq 0) {
                "Winget initialized successfully." | Out-File -FilePath $logFile -Append
            } else {
                "Winget initialization command finished with non-zero exit code." | Out-File -FilePath $logFile -Append
            }
        } catch {
            "FATAL: Failed to initialize Winget. Error: $_" | Out-File -FilePath $logFile -Append
            [System.Windows.Forms.MessageBox]::Show("Winget could not be initialized. Please ensure it is installed and working correctly. The script will now exit.", "Critical Error", "OK", "Error")
            exit
        }
    }

    # -----------------------------------------------------------------------------------
    # Checks if a specific Winget package is already installed.
    # -----------------------------------------------------------------------------------
    function ProgramIsInstalled($programId) {
        "Checking if $programId is installed..." | Out-File -FilePath $logFile -Append
        $result = winget list --id $programId --exact 2>&1
        $isInstalled = ($result -match "^$([regex]::Escape($programId))\s")
        "Result for $programId IsInstalled=$isInstalled" | Out-File -FilePath $logFile -Append
        return $isInstalled
    }

    # -----------------------------------------------------------------------------------
    # Installs a program using Winget if it is not already installed.
    # -----------------------------------------------------------------------------------
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
                } else {
                    $consoleTextBox.AppendText("Error installing $name. Exit code: $($process.ExitCode)`n")
                }
            } catch {
                $consoleTextBox.AppendText("Error installing $name - $_`n")
            }
        } else {
            $consoleTextBox.AppendText("$name is already installed.`n")
        }
        $consoleTextBox.ScrollToEnd()
        $progressBar.Dispatcher.Invoke([Action]{}, "Render")
    }

    # -----------------------------------------------------------------------------------
    # Updates all installed Winget packages.
    # -----------------------------------------------------------------------------------
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
            } else {
                $consoleTextBox.AppendText("Error updating programs. Exit code: $($process.ExitCode)`n")
            }
        } catch {
            $consoleTextBox.AppendText("Error updating programs: $_`n")
        }
        $consoleTextBox.ScrollToEnd()
        $progressBar.Dispatcher.Invoke([Action]{}, "Render")
    }

    # -----------------------------------------------------------------------------------
    # Gathers basic system information for display in the GUI.
    # -----------------------------------------------------------------------------------
    function Get-SystemInfo {
        $gpu = (Get-WmiObject Win32_VideoController | Where-Object { $_.Name -notmatch "Meta|Virtual|Remote|DisplayLink" } | Select-Object -First 1 -ExpandProperty Name)
        $cpu = (Get-WmiObject Win32_Processor | Select-Object -First 1 -ExpandProperty Name)
        $ramModules = Get-CimInstance Win32_PhysicalMemory
        $ramTotal = [math]::Round(($ramModules | Measure-Object -Property Capacity -Sum).Sum / 1GB)
        $ramSpeeds = ($ramModules | Select-Object -ExpandProperty Speed | Sort-Object -Unique) -join ", "
        $drives = Get-PSDrive | Where-Object { $_.Provider -like '*FileSystem*' -and $null -ne $_.Used }
        $diskInfo = foreach ($drive in $drives) { "$($drive.Name): $([math]::Round($drive.Free / 1GB)) GB frei `n" }

        return @{
            GPU  = $gpu
            CPU  = $cpu
            RAM  = "$ramTotal GB ($ramSpeeds MT/s)"
            DISK = $diskInfo -join "`n"
        }
    }

    # -----------------------------------------------------------------------------------
    # Detects the primary GPU vendor (NVIDIA or AMD).
    # -----------------------------------------------------------------------------------
    function DetectGPUVendor {
        $gpus = Get-WmiObject Win32_VideoController | Where-Object { $_.Name -notmatch "Meta|Virtual|Remote|DisplayLink" }
        foreach ($gpu in $gpus) {
            if ($gpu.Name -match "NVIDIA") { return "NVIDIA" }
            elseif ($gpu.Name -match "AMD") { return "AMD" }
        }
        return "Unknown"
    }
    
    #endregion

    #region GUI AND MAIN LOGIC

    # Initialize Winget before building the GUI.
    Initialize-Winget

    # Get system info to display.
    $info = Get-SystemInfo

    # -----------------------------------------------------------------------------------
    # XAML definition for the main GUI window.
    # -----------------------------------------------------------------------------------
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
                <CheckBox Name="chkLoL">League of Legends (EUW)</CheckBox>
                <CheckBox Name="chkGOG">GOG Galaxy</CheckBox>
                <CheckBox Name="chkEpic">Epic Games Launcher</CheckBox>
                <CheckBox Name="chkBattleNet">Battle.net</CheckBox>
            </StackPanel>

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
    
    $reader = (New-Object System.Xml.XmlNodeReader $xaml)
    $window = [Windows.Markup.XamlReader]::Load($reader)

    # Map the checkbox elements from the GUI to their corresponding Winget package IDs.
    $programMap = @{
        $window.FindName("chkChrome")     = @{ ID = "Google.Chrome"; Name = "Google Chrome" }
        $window.FindName("chkFirefox")    = @{ ID = "Mozilla.Firefox"; Name = "Mozilla Firefox" }
        $window.FindName("chkOpera")      = @{ ID = "Opera.Opera"; Name = "Opera" }
        $window.FindName("chkOperaGx")    = @{ ID = "Opera.OperaGX"; Name = "OperaGX" }
        $window.FindName("chkBrave")      = @{ ID = "Brave.Brave"; Name = "Brave Browser" }
        $window.FindName("chkSteam")      = @{ ID = "Valve.Steam"; Name = "Steam" }
        $window.FindName("chkDiscord")    = @{ ID = "Discord.Discord"; Name = "Discord" }
        $window.FindName("chkCurseForge") = @{ ID = "Overwolf.CurseForge"; Name = "CurseForge" }
        $window.FindName("chkLoL")        = @{ ID = "RiotGames.LeagueOfLegends.EUW"; Name = "League of Legends (EUW)" }
        $window.FindName("chkGOG")        = @{ ID = "GOG.Galaxy"; Name = "GOG Galaxy" }
        $window.FindName("chkEpic")       = @{ ID = "EpicGames.EpicGamesLauncher"; Name = "Epic Games Launcher" }
        $window.FindName("chkBattleNet")  = @{ ID = "Blizzard.BattleNet"; Name = "Battle.net" }
        $window.FindName("chkVSC")        = @{ ID = "Microsoft.VisualStudioCode"; Name = "Visual Studio Code" }
        $window.FindName("chkUnity")      = @{ ID = "Unity.UnityHub"; Name = "Unity Hub" }
        $window.FindName("chkGitHub")     = @{ ID = "GitHub.GitHubDesktop"; Name = "GitHub Desktop" }
        $window.FindName("chkGit")        = @{ ID = "Git.Git"; Name = "Git" }
        $window.FindName("chkPython")     = @{ ID = "Python.Python.3.12"; Name = "Python 3.12" }
        $window.FindName("chkObsidian")   = @{ ID = "Obsidian.Obsidian"; Name = "Obsidian" }
        $window.FindName("chkDrive")      = @{ ID = "Google.GoogleDrive"; Name = "Google Drive" }
        $window.FindName("chkVLC")        = @{ ID = "VideoLAN.VLC"; Name = "VLC Media Player" }
        $window.FindName("chkNord")       = @{ ID = "NordSecurity.NordVPN"; Name = "NordVPN" }
        $window.FindName("chkJava")       = @{ ID = "Oracle.JavaRuntimeEnvironment"; Name = "Java Runtime Environment" }
        $window.FindName("chkKeePassXC")  = @{ ID = "KeePassXCTeam.KeePassXC"; Name = "KeePassXC" }
        $window.FindName("chkAudacity")   = @{ ID = "Audacity.Audacity"; Name = "Audacity" }
        $window.FindName("chkShareX")     = @{ ID = "ShareX.ShareX"; Name = "ShareX" }
        $window.FindName("chkOBS")        = @{ ID = "OBSProject.OBSStudio"; Name = "OBS Studio" }
        $window.FindName("chkZoom")       = @{ ID = "Zoom.Zoom"; Name = "Zoom" }
        $window.FindName("chkTeams")      = @{ ID = "Microsoft.Teams"; Name = "Microsoft Teams" }
        $window.FindName("chkHWInfo")     = @{ ID = "REALiX.HWiNFO"; Name = "HWInfo" }
        $window.FindName("chkGPUZ")       = @{ ID = "TechPowerUp.GPU-Z"; Name = "GPU-Z" }
        $window.FindName("chkCPUZ")       = @{ ID = "CPUID.CPU-Z"; Name = "CPU-Z" }
        $window.FindName("chkCinebench")  = @{ ID = "Maxon.CinebenchR23"; Name = "Cinebench R23" }
        $window.FindName("chkFurMark")    = @{ ID = "Geeks3D.FurMark.2"; Name = "FurMark" }
    }
    $chkUpdateAll = $window.FindName("chkUpdateAll")

    # -----------------------------------------------------------------------------------
    # Main installation logic, triggered by the "Install" button.
    # -----------------------------------------------------------------------------------
    $window.FindName("btnInstall").Add_Click({
        $window.Visibility = 'Hidden'

        # Define and show the progress window.
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
        $progressReader = (New-Object System.Xml.XmlNodeReader $progressXaml)
        $progressWindow = [Windows.Markup.XamlReader]::Load($progressReader)
        $progressBar = $progressWindow.FindName("progressBar")
        $consoleTextBox = $progressWindow.FindName("consoleOutput")
        $progressWindow.Show()

        # Calculate total steps for the progress bar.
        $currentStep = 0
        $totalSteps = ($programMap.Keys | Where-Object { $_.IsChecked }).Count
        if ($chkUpdateAll.IsChecked) { $totalSteps++ }
        $gpu = DetectGPUVendor
        if ($gpu -ne "Unknown") { $totalSteps++ }
        
        if ($totalSteps -eq 0) { 
            $consoleTextBox.AppendText("No programs selected for installation.`n")
            Start-Sleep -Seconds 5
        } else {
            # Loop through the program map and install checked items.
            foreach ($checkbox in $programMap.Keys) {
                if ($checkbox.IsChecked) {
                    $currentStep++
                    $programInfo = $programMap[$checkbox]
                    InstallProgramIfNeeded $programInfo.ID $programInfo.Name $progressBar $consoleTextBox $totalSteps $currentStep
                }
            }

            # Handle special cases like updating all programs.
            if ($chkUpdateAll.IsChecked) {
                $currentStep++
                UpdateAllPrograms $progressBar $consoleTextBox $totalSteps $currentStep
            }

            # Handle GPU driver suggestions.
            $consoleTextBox.AppendText("Detected GPU: $gpu`n")
            $consoleTextBox.ScrollToEnd()
            switch ($gpu) {
                "NVIDIA" { 
                    $currentStep++
                    InstallProgramIfNeeded "TechPowerUp.NVCleanstall" "NVIDIA Driver NVCleaninstaller" $progressBar $consoleTextBox $totalSteps $currentStep 
                }
                "AMD" {
                    $currentStep++
                    $progressBar.Value = ($currentStep / $totalSteps) * 100
                    $progressBar.Dispatcher.Invoke([Action]{}, "Render")
                    # Use ASCII-safe string to prevent encoding errors.
                    $consoleTextBox.AppendText("AMD GPU erkannt - oeffne Support-Seite fuer manuelle Treiberwahl...`n")
                    Start-Process "https://www.amd.com/en/support"
                }
                default { 
                    $consoleTextBox.AppendText("Unknown GPU vendor or no specific action required.`n") 
                }
            }
            $consoleTextBox.ScrollToEnd()

            $consoleTextBox.AppendText("All tasks complete. Closing in 15 seconds...`n")
            $progressBar.Value = 100
            Start-Sleep -Seconds 15
        }
        
        $progressWindow.Close()
        $window.Close()
    })

    # -----------------------------------------------------------------------------------
    # Quicklink button handlers.
    # -----------------------------------------------------------------------------------
    $window.FindName("btnTaskmgr").Add_Click({ Start-Process taskmgr })
    $window.FindName("btnExplorer").Add_Click({ Start-Process explorer })
    $window.FindName("btnDiskMgmt").Add_Click({ Start-Process diskmgmt.msc })
    
    # Show the main window to the user.
    "Showing GUI" | Out-File -FilePath $logFile -Append
    $window.ShowDialog() | Out-Null

    #endregion

} catch {
    # Global error handler to log any exceptions.
    "FATAL ERROR: $_" | Out-File -FilePath $logFile -Append
    # Also show the error to the user in a message box.
    [System.Windows.Forms.MessageBox]::Show("An unexpected error occurred: $_", "Fatal Error", "OK", "Error")
    throw
}
