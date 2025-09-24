# Windows Stuff Installer

Simple PowerShell GUI tool to batch-install some apps on a fresh Windows system using the Windows Package Manager (Winget).


## Features

- Simple, user-friendly graphical interface.
- A categorized list of popular software (Browsers, Gaming, Developer Tools, etc.).
- Automatically finds the correct Winget installation, avoiding common PATH issues.
- Displays basic system information (GPU, CPU, RAM, Disk).
- Includes an option to update all existing applications installed via Winget.

## Requirements

- Windows 10 (2004) or Windows 11.
- PowerShell 5.1 or higher.
- **IMPORTANT:** You must be logged into a **Microsoft Account** in your Windows session. This is required for the Microsoft Store and Winget (`App Installer`) to function correctly. The tool will not work in environments (like some VMs or sandboxes) without an active Microsoft Account login.

## How to Use

1.  Download all files from this repository (`start.bat` and `installing.ps1`).
2.  Place them in the same directory.
3.  Right-click on `start.bat`.
4.  Select **Run as administrator**. A UAC prompt will appear.
5.  The installer window will open. Check the boxes for the applications you wish to install.
6.  Click the **"Installieren"** (Install) button.
7.  A progress window will appear and show the status of the installations.

## Troubleshooting

- **"CRITICAL ERROR: Could not find a modern Winget..."**
  - This error means the script could not find a working Winget installation for your user account.
  - **Solution:** Ensure you are logged into a Microsoft Account in Windows. Then, open the Microsoft Store, go to your Library, and check for updates for the **"App Installer"** package.

- **The script window closes immediately or nothing happens.**
  - **Solution:** Make sure you are running `start.bat` by right-clicking and selecting "Run as administrator", not just double-clicking it.