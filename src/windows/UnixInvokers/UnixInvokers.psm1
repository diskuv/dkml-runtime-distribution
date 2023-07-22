# ================================
# UnixInvokers.psm1
#
# PowerShell Module to invoke a Cygwin or a MSYS2 command.
#

$ErrorActionPreference = "Stop"
$InvokerTailRefreshSeconds = 0.25
$InvokerTailLines = 1
Export-ModuleMember -Variable InvokerTailLines
Export-ModuleMember -Variable InvokerTailRefreshSeconds

$PSDefaultParameterValues = @{'Out-File:Encoding' = 'utf8'} # for Tee-Object. https://stackoverflow.com/a/58920518

function Invoke-CygwinCommand {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '',
    Justification='Unread $handle is a fix to a Powershell bug')]
    param (
        [Parameter(Mandatory=$true)]
        $Command,
        [Parameter(Mandatory=$true)]
        $CygwinDir,
        $AuditLog,
        $TailFunction
    )
    $arglist = @("-l",
        "-c",
        ('" { set -x; PATH=/usr/bin:\"$PATH\"; ' + ($Command -replace '"', '\"') + '; } 2>&1 "'))
    if ($TailFunction) {
        $RedirectStandardOutput = New-TemporaryFile
        $RedirectStandardError = New-TemporaryFile
        try {
            $proc = Start-Process -NoNewWindow -FilePath $CygwinDir\bin\bash.exe -PassThru `
                -RedirectStandardOutput $RedirectStandardOutput `
                -RedirectStandardError $RedirectStandardError `
                -ArgumentList $arglist
            $handle = $proc.Handle # cache proc.Handle https://stackoverflow.com/a/23797762/1479211
            while (-not $proc.HasExited) {
                if ($AuditLog) {
                    $tail = Get-Content -Path $RedirectStandardOutput -Tail $InvokerTailLines -ErrorAction Ignore
                    if ($tail -is [array]) { $tail = $tail -join "`n" }
                    if ($null -ne $tail) {
                        Invoke-Command $TailFunction -ArgumentList @($tail)
                    }
                }
                Start-Sleep -Seconds $InvokerTailRefreshSeconds
            }
            $proc.WaitForExit()
            $exitCode = $proc.ExitCode
            if ($exitCode -ne 0) {
                $err = Get-Content -Path $RedirectStandardError -Raw
                if ($null -eq $err -or "" -eq $err) { $err = Get-Content -Path $RedirectStandardOutput -Tail 5 -ErrorAction Ignore }
                throw "Cygwin command failed! Exited with $exitCode. Command was: $Command`nError was: $err"
            }
        }
        finally {
            if ($null -ne $RedirectStandardOutput -and (Test-Path $RedirectStandardOutput)) {
                if ($AuditLog) { Add-Content -Path $AuditLog -Value (Get-Content -Path $RedirectStandardOutput -Raw) -Encoding UTF8 }
                Remove-Item $RedirectStandardOutput -Force -ErrorAction Continue
            }
            if ($null -ne $RedirectStandardError -and (Test-Path $RedirectStandardError)) {
                if ($AuditLog) { Add-Content -Path $AuditLog -Value (Get-Content -Path $RedirectStandardError -Raw) -Encoding UTF8 }
                Remove-Item $RedirectStandardError -Force -ErrorAction Continue
            }
        }
    } else {
        $oldeap = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        if ($AuditLog) {
            & $CygwinDir\bin\bash.exe @arglist 2>&1 | ForEach-Object ToString | Tee-Object -Append -FilePath $AuditLog
        } else {
            & $CygwinDir\bin\bash.exe @arglist
        }
        $ErrorActionPreference = $oldeap
        if ($LastExitCode -ne 0) {
            throw "Cygwin command failed! Exited with $LastExitCode. Command was: $Command"
        }
    }
}
Export-ModuleMember -Function Invoke-CygwinCommand

$INVOKER_MSYSTEM_PREFIX = "/clang64"
$INVOKER_MSYSTEM_CARCH = "x86_64"
$INVOKER_MSYSTEM_CHOST = "x86_64-w64-mingw32"
$INVOKER_MINGW_CHOST = "x86_64-w64-mingw32"
$INVOKER_MINGW_PACKAGE_PREFIX = "mingw-w64-clang-x86_64"
$INVOKER_MINGW_PREFIX = "/clang64"
Export-ModuleMember -Variable INVOKER_MSYSTEM_PREFIX
Export-ModuleMember -Variable INVOKER_MSYSTEM_CARCH
Export-ModuleMember -Variable INVOKER_MSYSTEM_CHOST
Export-ModuleMember -Variable INVOKER_MINGW_CHOST
Export-ModuleMember -Variable INVOKER_MINGW_PACKAGE_PREFIX
Export-ModuleMember -Variable INVOKER_MINGW_PREFIX

function Invoke-MSYS2Command {
    <#
        .SYNOPSIS
            Run an MSYS command.

        .DESCRIPTION
            Run a shell command.

        .PARAMETER Command
            The command to execute, like "sh" or "ls".

        .PARAMETER Arguments
            An array of Command arguments.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '',
    Justification='Unread $handle is a fix to a Powershell bug')]
    param (
        [Parameter(Mandatory=$true)]
        $Command,
        [Parameter(Mandatory=$true)]
        $MSYS2Dir,
        [Parameter()]
        [string[]]
        $ArgumentList,
        $AuditLog,
        $TailFunction,
        [switch]
        $IgnoreErrors
    )
    $arglist = @("MSYSTEM=CLANG64",
        "MSYSTEM_PREFIX=$INVOKER_MSYSTEM_PREFIX",
        "MSYSTEM_CARCH=$INVOKER_MSYSTEM_CARCH"
        "MSYSTEM_CHOST=$INVOKER_MSYSTEM_CHOST"
        "MINGW_CHOST=$INVOKER_MINGW_CHOST"
        "MINGW_PACKAGE_PREFIX=$INVOKER_MINGW_PACKAGE_PREFIX"
        "MINGW_PREFIX=$INVOKER_MINGW_PREFIX"
        "HOME=/home/$env:USERNAME",
        "PATH=$INVOKER_MSYSTEM_PREFIX/bin:/usr/bin:/bin"
        $Command) + $ArgumentList
    if ($TailFunction) {
        $RedirectStandardOutput = New-TemporaryFile
        $RedirectStandardError = New-TemporaryFile
        try {
            $proc = Start-Process -NoNewWindow -FilePath $MSYS2Dir\usr\bin\env.exe -PassThru `
                -RedirectStandardOutput $RedirectStandardOutput `
                -RedirectStandardError $RedirectStandardError `
                -ArgumentList $arglist
            $handle = $proc.Handle # cache proc.Handle https://stackoverflow.com/a/23797762/1479211
            while (-not $proc.HasExited) {
                if ($AuditLog) {
                    $tail = Get-Content -Path $RedirectStandardOutput -Tail $InvokerTailLines -ErrorAction Ignore
                    if ($tail -is [array]) { $tail = $tail -join "`n" }
                    if ($null -ne $tail) {
                        Invoke-Command $TailFunction -ArgumentList @($tail)
                    }
                }
                Start-Sleep -Seconds $InvokerTailRefreshSeconds
            }
            $proc.WaitForExit()
            $exitCode = $proc.ExitCode
            if (-not $IgnoreErrors -and $exitCode -ne 0) {
                $err = Get-Content -Path $RedirectStandardError -Raw
                if ($null -eq $err -or "" -eq $err) { $err = Get-Content -Path $RedirectStandardOutput -Tail 5 -ErrorAction Ignore }
                throw "MSYS2 command failed! Exited with $exitCode. Command was: $Command $($arglist -join ' ')`nError was: $err"
            }
        } finally {
            if ($null -ne $RedirectStandardOutput -and (Test-Path $RedirectStandardOutput)) {
                if ($AuditLog) { Add-Content -Path $AuditLog -Value (Get-Content -Path $RedirectStandardOutput -Raw) -Encoding UTF8 }
                Remove-Item $RedirectStandardOutput -Force -ErrorAction Continue
            }
            if ($null -ne $RedirectStandardError -and (Test-Path $RedirectStandardError)) {
                if ($AuditLog) { Add-Content -Path $AuditLog -Value (Get-Content -Path $RedirectStandardError -Raw) -Encoding UTF8 }
                Remove-Item $RedirectStandardError -Force -ErrorAction Continue
            }
        }
    } else {
        $oldeap = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        if ($AuditLog) {
            & $MSYS2Dir\usr\bin\env.exe @arglist 2>&1 | ForEach-Object ToString | Tee-Object -Append -FilePath $AuditLog
        } else {
            & $MSYS2Dir\usr\bin\env.exe @arglist
        }
        $ErrorActionPreference = $oldeap
        if (-not $IgnoreErrors -and $LastExitCode -ne 0) {
            throw "MSYS2 command failed! Exited with $LastExitCode. Command was: $Command $($arglist -join ' ')"
        }
    }
}
Export-ModuleMember -Function Invoke-MSYS2Command
