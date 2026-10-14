$ErrorActionPreference = "Stop"

try {
    # Configure Firewall
    $ruleName = "OpenSSH-Server-In-TCP"

    if (-not (Get-NetFirewallRule -Name $ruleName -ErrorAction SilentlyContinue)) {
        New-NetFirewallRule -Name $ruleName `
            -DisplayName "OpenSSH Server (sshd)" `
            -Enabled True -Direction Inbound `
            -Protocol TCP -Action Allow -LocalPort 22 | Out-Null
    } else {
        Set-NetFirewallRule -Name $ruleName -Enabled True
    }

    # Find or install Tailscale
    $tailscaleExe = @(
        "$env:ProgramFiles\Tailscale\tailscale.exe"
        "${env:ProgramFiles(x86)}\Tailscale\tailscale.exe"
    ) | Where-Object { $_ -and (Test-Path $_) } |
        Select-Object -First 1

    if (-not $tailscaleExe) {
        winget install --id Tailscale.Tailscale --exact `
            --accept-source-agreements --accept-package-agreements --silent

        if ($LASTEXITCODE -ne 0) {
            throw "Tailscale installation failed."
        }

        $tailscaleExe = @(
            "$env:ProgramFiles\Tailscale\tailscale.exe"
            "${env:ProgramFiles(x86)}\Tailscale\tailscale.exe"
        ) | Where-Object { $_ -and (Test-Path $_) } |
            Select-Object -First 1
    }

    if (-not $tailscaleExe) {
        throw "Tailscale executable not found."
    }

    Write-Host "[OK] Tailscale installed and detected." -ForegroundColor Green

    # Start Tailscale
    Set-Service -Name Tailscale -StartupType Automatic
    Start-Service -Name Tailscale

    $authKey = "tskey-auth-kz1FyVbCF221CNTRL-oCzcAHaV7nhuCFRBr4evmh2CroKFTn8sW"

    & $tailscaleExe up "--auth-key=$authKey" --accept-routes
    $result = $LASTEXITCODE
    $authKey = $null

    if ($result -ne 0) {
        throw "Tailscale authentication failed."
    }

    $tailscaleIp = $null

    for ($i = 0; $i -lt 5 -and -not $tailscaleIp; $i++) {
        Start-Sleep -Seconds 2
        $ipResult = & $tailscaleExe ip -4 2>$null

        if ($LASTEXITCODE -eq 0 -and $ipResult) {
            $tailscaleIp = ($ipResult | Select-Object -First 1).Trim()
        }
    }

    if (-not $tailscaleIp) {
        throw "Could not retrieve the Tailscale IP address."
    }

    Write-Host "[OK] Tailscale connected: $tailscaleIp" -ForegroundColor Green

    # Install OpenSSH Server
    $capName = "OpenSSH.Server~~~~0.0.1.0"
    $cap = Get-WindowsCapability -Online |
        Where-Object Name -eq $capName

    if (-not $cap -or $cap.State -ne "Installed") {
        Add-WindowsCapability -Online -Name $capName | Out-Null

        $cap = Get-WindowsCapability -Online |
            Where-Object Name -eq $capName

        if ($cap.State -ne "Installed") {
            throw "OpenSSH Server installation failed."
        }
    }

    Write-Host "[OK] OpenSSH Server installed." -ForegroundColor Green

    # Add SSH public key
    $sshDir = "$env:ProgramData\ssh"
    $authKeysPath = Join-Path $sshDir "administrators_authorized_keys"

    if (-not (Test-Path $sshDir)) {
        New-Item -ItemType Directory -Path $sshDir -Force | Out-Null
    }

    $sshKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIP3qm1ZgrKCjKUJT53SZP03zL/t1z/gGjBbQD+7lc4g4 root@NIGHTMARE"

    if (-not (Test-Path $authKeysPath)) {
        New-Item -ItemType File -Path $authKeysPath -Force | Out-Null
    }

    $keys = @(Get-Content $authKeysPath -ErrorAction SilentlyContinue)

    if ($keys -notcontains $sshKey) {
        Add-Content -Path $authKeysPath -Value $sshKey
    }

    icacls $authKeysPath /inheritance:r `
        /grant:r "*S-1-5-32-544:F" "*S-1-5-18:F" | Out-Null

    if ($LASTEXITCODE -ne 0) {
        throw "Failed to configure SSH key permissions."
    }

    Write-Host "[OK] SSH public key configured." -ForegroundColor Green

    # Start SSH service
    Set-Service -Name sshd -StartupType Automatic
    Start-Service -Name sshd

    if ((Get-Service sshd).Status -ne "Running") {
        throw "OpenSSH service failed to start."
    }

    Write-Host "[OK] SSH service running." -ForegroundColor Green
    Write-Host "[OK] Firewall configured." -ForegroundColor Green

    # Final connection details
    $username = (whoami).Trim()

    Write-Host ""
    Write-Host "============================================" -ForegroundColor Green
    Write-Host "SETUP COMPLETED SUCCESSFULLY" -ForegroundColor Green
    Write-Host "Tailscale IP : $tailscaleIp" -ForegroundColor Cyan
    Write-Host "Username     : $username" -ForegroundColor Cyan
    Write-Host "SSH Command  : ssh $username@$tailscaleIp" -ForegroundColor Yellow
    Write-Host "============================================" -ForegroundColor Green
}
catch {
    $authKey = $null
    Write-Host "[ERROR] $($_.Exception.Message)" -ForegroundColor Red
    throw
}
