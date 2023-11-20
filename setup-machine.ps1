<#
.Synopsis
    Set up all programs and data folders that are shared across
    all users on the machine.
.Description
    Installs the MSBuild component of Visual Studio.

    Interactive Terminals
    ---------------------

    If you are running from within a continuous integration (CI) scenario you may
    encounter `Exception setting "CursorPosition"`. That means a command designed
    for user interaction was run in this script; use -SkipProgress to disable
    the need for an interactive terminal.

.Parameter ParentProgressId
    The PowerShell progress identifier. Optional, defaults to -1.
    Use when embedding this script within another setup program
    that reports its own progress.
.Parameter TempParentPath
    Temporary directory. A subdirectory will be created within -TempParentPath.
    Defaults to $env:temp\diskuvocaml\setupmachine.

.Parameter AuditOnly
    Do not automatically install Visual Studio Build Tools.

    Even with this switch is selected a compatibility check is
    performed to make sure there is a version of Visual Studio
    installed that has all the components necessary for DkML.
.Parameter SilentInstall
    When specified no user interface should be shown.
    We do not recommend you do this unless you are in continuous
    integration (CI) scenarios.
.Parameter VcpkgCompatibility
    Install a version of Visual Studio that is compatible with Microsoft's
    vcpkg (the C package manager).
.Parameter SkipProgress
    Do not use the progress user interface.
#>

[CmdletBinding()]
param (
    [Parameter()]
    [int]
    $ParentProgressId = -1,
    [string]
    $TempParentPath,
    [switch]
    $AuditOnly,
    [switch]
    $SilentInstall,
    [switch]
    $AllowRunAsAdmin,
    [switch]
    $VcpkgCompatibility,
    [switch]
    $SkipProgress
)

$ErrorActionPreference = "Stop"
$InformationPreference = "Continue"

$HereScript = $MyInvocation.MyCommand.Path
$HereDir = (get-item $HereScript).Directory

$dsc = [System.IO.Path]::DirectorySeparatorChar
$env:PSModulePath += "$([System.IO.Path]::PathSeparator)$HereDir${dsc}src${dsc}windows"
Import-Module Machine

# Older versions of PowerShell and Windows Server use SSL 3 / TLS 1.0 while our sites
# (especially gitlab assets) may require the use of TLS 1.2
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# ----------------------------------------------------------------
# Progress Reporting

$global:ProgressStep = 0
$global:ProgressActivity = $null
$ProgressTotalSteps = 2
$ProgressId = $ParentProgressId + 1
function Write-ProgressStep {
    if (!$SkipProgress) {
        Write-Progress -Id $ProgressId `
            -ParentId $ParentProgressId `
            -Activity $global:ProgressActivity `
            -PercentComplete (100 * ($global:ProgressStep / $ProgressTotalSteps))
    } else {
        Write-Host -ForegroundColor DarkGreen "[$(1 + $global:ProgressStep) of $ProgressTotalSteps]: $($global:ProgressActivity)"
    }
    $global:ProgressStep += 1
}

function Write-Error($message) {
    # https://stackoverflow.com/questions/38064704/how-can-i-display-a-naked-error-message-in-powershell-without-an-accompanying
    [Console]::ForegroundColor = 'red'
    [Console]::Error.WriteLine($message)
    [Console]::ResetColor()
}

# ----------------------------------------------------------------
# QUICK EXIT if already current version already deployed


# ----------------------------------------------------------------
# BEGIN Start deployment

$global:ProgressActivity = "Starting ..."
$global:ProgressStatus = "Starting ..."

# CODE DUPLICATION ALERT: Originally from dkml-component-ocamlcompiler-src/assets/staging-files/win32/SingletonInstall/Deployers/Deployers.psm1
#
# Remove-DirectoryFully
#
# Remove a directory and all of its contents. Unlike Remove-Item -Recurse this will work in
# all versions of Windows.
# Will not fail if the path does not already exist.
#
# This behaves like the DKML Install API's [uninstall_directory] function that
# tells you and waits for you to close any open files.
function Remove-DirectoryFully {
    param(
        [Parameter(Mandatory = $true)] $Path,
        [int] $WaitSecondsIfStuck = -1,
        [string] $StuckMessageFormatInfo = "Stuck during removal of directory after {0} seconds.`n`t{1}",
        [string] $StuckMessageFormatCritical = "`t{1}"
    )

    if (Test-Path -Path $Path) {
        # On Windows 11 Build 22478.1012 with Powershell 5.1, even though `Remove-Item -Force`
        # should delete ReadOnly files (which are typical for Opam installed executables), it
        # fails with: "You do not have sufficient access rights to perform this operation".
        # Instead we have to remove the ReadOnly attribute.
        $firstFailure = $null
        Get-ChildItem $Path -Recurse -Force | Where-Object { $_.Attributes -band [io.fileattributes]::ReadOnly } | ForEach-Object {
            # $_ is now the file object
            $currentFile = $_
            try {
                Set-ItemProperty -Path $_.FullName -Name Attributes -Value ($_.Attributes -band (-bnot [io.fileattributes]::ReadOnly))
            } catch {
                # Handle drives that do not support setting attributes, even though we are not adding any!
                # https://github.com/diskuv/dkml-installer-ocaml/issues/38.
                # $_ is now the error object
                if ($null -eq $firstFailure) {
                    $firstFailure = (
                        "The drive containing $Path does not support setting attributes on some or all of its files. " +
                        "Here is one file that could not be set: $($currentFile.FullName). $_")
                }
            }
        }
        if ($firstFailure) {
            Write-Warning "$firstFailure"
        }

        # We want to do `Remove-Item -Path $Path -Recurse -Force`. However the docs for Remove-Item
        # https://docs.microsoft.com/en-us/powershell/module/microsoft.powershell.management/remove-item?view=powershell-7.2#parameters
        # say:
        # > The Recurse parameter might not delete all subfolders or all child items. This is a known issue.
        # > ! Note
        # > This behavior was fixed in Windows versions 1909 and newer.
        # So we use the Command Prompt instead (with COMSPEC so that MSYS2 "cmd" does not get run).
        $timer = [Diagnostics.Stopwatch]::StartNew()
        if ("$env:COMSPEC" -eq "") {
            # not Windows

            # TODO: We have no "STUCK" logic to check if process needs to be stopped!
            # On Linux systems we can remove the file while it is being
            # used... the inode lives on.
            # Don't know if the same goes for macOS.

            Remove-Item -Path $Path -Recurse -Force
            $success = $true
        } else {
            # Windows

            # We have "STUCK" logic where ... if a file can't be deleted
            # because it was in use by another porcess ... we say so and
            # wait. This logic only occurs when $WaitSecondsIfStuck >= 0.

            # Sigh ... we won't get any error codes from `rd`. But we will get:
            #   C:\Users\beckf\AppData\Local\Temp\f46f0508-df03-40e8-8661-728f1be41647\UninstallBlueGreenDeploy2\0\cmd.exe - Access is denied.
            # So any output on the error console indicates a problem
            $success = $false
            $stderr = New-TemporaryFile
            do {
                Start-Process `
                    -Wait `
                    -NoNewWindow `
                    -RedirectStandardError $stderr `
                    -FilePath "$env:COMSPEC" `
                    -ArgumentList @("/c", "rd /s /q `"$Path`"")
                $errlen = (Get-Item -Path $stderr).Length
                if ($errlen -eq 0) {
                    # no errors means success
                    $success = $true
                    break
                }

                # If not explicit that we want to wait, immediately exit
                # and say what the problem was.
                if ($WaitSecondsIfStuck -lt 0) {
                    throw (Get-Content $stderr)
                }

                # We are waiting until unstuck!
                $sofar = $timer.elapsed.totalseconds
                #   don't overwhelm display or PowerShell if lots of errors
                $errcontent = Get-Content -TotalCount 5 $stderr | Out-String
		#   Write-Information is missing -NoNewline and -ForegroundColor
		#   so we use Write-Host
                Write-Host ($StuckMessageFormatInfo -f @($sofar, $errcontent)) -NoNewline
                Write-Host ($StuckMessageFormatCritical -f @($sofar, $errcontent)) -ForegroundColor Red -BackgroundColor Black
                Start-Sleep -Seconds 5
            } while ($timer.elapsed.totalseconds -lt $WaitSecondsIfStuck)
            Remove-Item $stderr
        }
        if (!$success -and ($WaitSecondsIfStuck -ge 0)) {
            throw "Could not remove the directory $Path after waiting $WaitSecondsIfStuck seconds"
        }
    }
}

if (!$TempParentPath) {
    $TempParentPath = "$Env:temp\DkML\setupmachine"
}

# END Start deployment
# ----------------------------------------------------------------

# ----------------------------------------------------------------
# BEGIN Visual Studio Setup PowerShell Module
$global:ProgressActivity = "Install Visual Studio Setup PowerShell Module"
Write-ProgressStep
# only error if user said $AuditOnly but there was no visual studio found
Remove-DirectoryFully -Path "$TempParentPath\vssetup"
Import-VSSetup -TempPath "$TempParentPath\vssetup"
# magic exit code = 17 needed for `network_ocamlcompiler.ml:needs_install_admin`
$CompatibleVisualStudios = Get-CompatibleVisualStudios -ErrorIfNotFound:$AuditOnly -ExitCodeIfNotFound:17 -VcpkgCompatibility:$VcpkgCompatibility
# END Visual Studio Setup PowerShell Module
# ----------------------------------------------------------------

# ----------------------------------------------------------------
# BEGIN Visual Studio Build Tools

# MSBuild 2015+ is the command line tools of Visual Studio.
#
# > Visual Studio Code is a very different product from Visual Studio 2015+. Do not confuse
# > the products if you need to install it! They can both be installed, but for this section
# > we are talking abobut Visual Studio 2015+ (ex. Visual Studio Community 2019).
#
# > Why MSBuild / Visual Studio 2015+? Because [vcpkg](https://vcpkg.io/en/getting-started.html) needs
# > Visual Studio 2015 Update 3 or newer as of July 2021.
#
# It is generally safe to run multiple MSBuild and Visual Studio installations on the same machine.
# The one in `C:\DiskuvOCaml\BuildTools` is **reserved** for our build system as it has precise
# versions of the tools we need.
#
# You can **also** install Visual Studio 2015+ which is the full GUI.
#
# Much of this section was adapted from `C:\Dockerfile.opam` while running
# `docker run --rm -it ocaml/opam:windows-msvc`.
#
# Key modifications:
# * We do not use C:\BuildTools but $env:SystemDrive\DiskuvOCaml\BuildTools instead
#   because C:\ may not be writable and avoid "BuildTools" since it is a known directory
#   that can create conflicts with other
#   installations (confer https://docs.microsoft.com/en-us/visualstudio/install/build-tools-container?view=vs-2019)
# * This is meant to be idempotent so we "modify" and not just install.
# * We've added/changed some components especially to get <stddef.h> C header (actually, we should inform
#   ocaml-opam so they can mimic the changes)

$global:ProgressActivity = "Install Visual Studio Build Tools"
Write-ProgressStep

if ((-not $AuditOnly) -and ($CompatibleVisualStudios | Measure-Object).Count -eq 0) {
    # Create BuildTools directory
    $BuildToolsPath = "$env:SystemDrive\DiskuvOCaml\BuildTools"
    if (!(Test-Path -Path $BuildToolsPath)) { New-Item -Path $BuildToolsPath -ItemType Directory | Out-Null }

    # Wipe installation directory so previous installs don't leak into the current install. We re-use
    # a stable directory because we want all the Visual Studio installation error reporting to be
    # in non-temporary directories.
    $VsInstallPath = "$env:SystemDrive\DiskuvOCaml\vsinstall"
    New-CleanDirectory -Path $VsInstallPath

    # Get components to install
    $VsComponents = Get-VisualStudioComponents -VcpkgCompatibility:$VcpkgCompatibility

    Invoke-WebRequest -Uri https://aka.ms/vscollect.exe   -OutFile $VsInstallPath\collect.exe
    Invoke-WebRequest -Uri "$VsBuildToolsInstallChannel"  -OutFile $VsInstallPath\VisualStudio.chman
    Invoke-WebRequest -Uri "$VsBuildToolsInstaller"       -OutFile $VsInstallPath\vs_buildtools.exe
    Invoke-WebRequest -Uri https://raw.githubusercontent.com/MisterDA/Windows-OCaml-Docker/d3a107132f24c05140ad84f85f187e74e83e819b/Install.cmd -OutFile $VsInstallPath\Install.orig.cmd
    $content = Get-Content -Path $VsInstallPath\Install.orig.cmd -Raw
    $content = $content -replace "C:\\TEMP", "$VsInstallPath"
    $content = $content -replace "C:\\vslogs.zip", "$VsInstallPath\vslogs.zip"
    $content | Set-Content -Path $VsInstallPath\Install.cmd

    # See how to use vs_buildtools.exe at
    # https://docs.microsoft.com/en-us/visualstudio/install/use-command-line-parameters-to-install-visual-studio?view=vs-2019
    # and automated installations at
    # https://docs.microsoft.com/en-us/visualstudio/install/build-tools-container?view=vs-2019
    #
    # Channel Uri
    # -----------
    #   --channelUri is sticky. The channel URI of the first Visual Studio on the machine is used for all next installs.
    #   That makes sense for enterprise installations where Administrators need to have control.
    #   Confer: https://github.com/MicrosoftDocs/visualstudio-docs/issues/3425
    #   Can change with https://docs.microsoft.com/en-us/visualstudio/install/update-servicing-baseline?view=vs-2019
    $CommonArgs = @(
        "--wait",
        "--nocache",
        "--norestart",
        "--installPath", "$BuildToolsPath",

        # a) We don't want unreproducible channel updates!
        #    https://docs.microsoft.com/en-us/visualstudio/install/use-command-line-parameters-to-install-visual-studio?view=vs-2019#layout-command-and-command-line-parameters
        #    So always use the specific versioned installation channel for reproducibility.
        #    "--channelUri", "$env:SystemDrive\doesntExist.chman"
        # b) the normal release channel:
        "--channelUri", "https://aka.ms/vs/$VsBuildToolsMajorVer/release/channel"
        # c) mistaken sticky value from DkML 0.1.x: "--channelUri", "$VsInstallPath\VisualStudio.chman"
    ) + $VsComponents.Add
    if ($SilentInstall) {
        $CommonArgs += @("--quiet")
    } else {
        $CommonArgs += @("--passive")
    }
    $AlreadyInstalledButIncompatible = Get-VSSetupInstance | Where-Object { $_.InstallationPath -eq "$BuildToolsPath" }
    if ($AlreadyInstalledButIncompatible) {
        # Modify the previous incompatible Visual Studio installation. Aka an upgrade or a downgrade.
        $CommonArgs = @("modify") + $CommonArgs
    } else {
        # First time installation. However we may have had an aborted prior installation, and
        # Visual Studio Installer (in dd_installer_TIMESTAMP.log) will give a:
        #   Warning: Visual Studio cannot be installed to a nonempty directory '...\BuildTools'.
        # if we don't empty the directory first
        New-CleanDirectory -Path $BuildToolsPath
    }
    $proc = Start-Process -FilePath $VsInstallPath\Install.cmd -NoNewWindow -Wait -PassThru `
        -ArgumentList (@("$VsInstallPath\vs_buildtools.exe") + $CommonArgs)
    $exitCode = $proc.ExitCode
    if ($exitCode -eq 3010) {
        Write-Warning "Microsoft Visual Studio Build Tools installation succeeded but a reboot is required!"
        Start-Sleep 5
        Write-Information ''
        Write-Information 'Press any key to exit this script... You must reboot!';
        $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown');
        # Dkml_install_api.Forward_progress.Exit_code.Exit_reboot_needed = 23
        exit 23
    }
    elseif ($exitCode -ne 0) {
        # collect.exe has already collected troubleshooting logs
        $ErrorActionPreference = "Continue"
        Write-Error (
            "`n`nMicrosoft Visual Studio Build Tools installation failed! Exited with $exitCode.!`n`n" +
            "FIRST you can retry this script which can resolve intermittent network failures or (rarer) Visual Studio installer bugs.`n"+
            "SECOND you can run the following (all on one line) to manually install Visual Studio Build Tools:`n`n`t$VsInstallPath\vs_buildtools.exe $($VsComponents.Add)`n`n"+
            "Make sure the following components are installed:`n"+
            "$($VsComponents.Describe)`n" +
            "THIRD, if everything else failed, you can file a Bug Report at https://github.com/diskuv/dkml-installer-ocaml/issues and attach $VsInstallPath\vslogs.zip`n"
        )
        exit 1
    }

    # Reconfirm the install was detected
    $CompatibleVisualStudios = Get-CompatibleVisualStudios -ErrorIfNotFound:$false -VcpkgCompatibility:$VcpkgCompatibility
    if (($CompatibleVisualStudios | Measure-Object).Count -eq 0) {
        $ErrorActionPreference = "Continue"
        & $VsInstallPath\collect.exe "-zip:$VsInstallPath\vslogs.zip"
        if (-not $SkipProgress) {
            Clear-Host
        }
        Write-Error (
            ". . . `n`n"+
            ". . . `n`n"+
            "`n`nNo compatible Visual Studio installation detected after the Visual Studio installation!`n" +
            "Often this is because a reboot is required or your system has a component that needs upgrading.`n`n" +
            ". . . `n`n"+
            ". . . `n`n"+
            "FIRST you should reboot and try again.`n`n"+
            ". . . `n`n"+
            ". . . `n`n"+
            "SECOND you can run the following (all on one line) to manually install Visual Studio Build Tools:`n`n`t$VsInstallPath\vs_buildtools.exe $($VsComponents.Add)`n`n"+
            "Make sure the following components are installed:`n"+
            "$($VsComponents.Describe)`n" +
            ". . .`n`n"+
            ". . .`n`n"+
            "THIRD, if everything else failed, you can file a Bug Report at https://github.com/diskuv/dkml-installer-ocaml/issues and attach $VsInstallPath\vslogs.zip`n" +
            ". . . `n`n"+
            ". . . `n`n"
        )
        # Dkml_install_api.Forward_progress.Exit_code.Exit_reboot_needed = 23
        exit 23
    }
}

if ($SkipProgress) {
    Write-Information "`n`nBEGIN Visual Studio(s) compatible with DkML"
} else {
    Write-Host -ForegroundColor White -BackgroundColor DarkGreen "`n`nBEGIN Visual Studio(s) compatible with DkML"
}
Write-Information ($CompatibleVisualStudios | ConvertTo-Json -Depth 1) # It is fine if we truncate at level 1 ... this is just meant to be a summary
if ($SkipProgress) {
    Write-Information "END Visual Studio(s) compatible with DkML`n`n"
} else {
    Write-Host -ForegroundColor White -BackgroundColor DarkGreen "END Visual Studio(s) compatible with DkML`n`n"
}

# END Visual Studio Build Tools
# ----------------------------------------------------------------

if (-not $SkipProgress) { Write-Progress -Id $ProgressId -ParentId $ParentProgressId -Activity $global:ProgressActivity -Completed }
