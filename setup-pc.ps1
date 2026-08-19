<#
.SYNOPSIS
    Instalacion desatendida de programas basicos en una PC nueva, usando winget.

.DESCRIPTION
    Pensado para correr en una PC recien formateada, desde PowerShell como
    administrador:

        irm https://raw.githubusercontent.com/USUARIO/pc-setup/main/setup-pc.ps1 | iex

    Para agregar o sacar programas, editar UNICAMENTE la lista $Programas de
    mas abajo. El resto del script no hace falta tocarlo.

    Los IDs de winget se buscan con:  winget search "nombre del programa"
#>

# ---------------------------------------------------------------------------
# LISTA DE PROGRAMAS A INSTALAR  <-- editar solo esto
# ---------------------------------------------------------------------------
$Programas = @(
    @{ Id = 'Google.Chrome'; Nombre = 'Google Chrome' }
    @{ Id = 'VideoLAN.VLC';  Nombre = 'VLC Media Player' }
    @{ Id = 'RARLab.WinRAR'; Nombre = 'WinRAR' }
)

# ---------------------------------------------------------------------------
# De aca para abajo no hace falta tocar nada
# ---------------------------------------------------------------------------

function Invoke-SetupPC {

    Write-Host ''
    Write-Host '===========================================' -ForegroundColor Cyan
    Write-Host '  Setup de PC - instalacion via winget' -ForegroundColor Cyan
    Write-Host '===========================================' -ForegroundColor Cyan
    Write-Host ''

    # --- 1. Verificar que winget exista -----------------------------------
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        Write-Host 'ERROR: winget no esta instalado en esta PC.' -ForegroundColor Red
        Write-Host ''
        Write-Host 'winget viene dentro del "Instalador de aplicacion" (App Installer).' -ForegroundColor Yellow
        Write-Host 'Para instalarlo tenes dos opciones:' -ForegroundColor Yellow
        Write-Host ''
        Write-Host '  1) Microsoft Store -> buscar "Instalador de aplicacion" -> Instalar/Actualizar'
        Write-Host '     (link directo: https://apps.microsoft.com/detail/9nblggh4nns1)'
        Write-Host ''
        Write-Host '  2) Descargar el .msixbundle desde:'
        Write-Host '     https://github.com/microsoft/winget-cli/releases/latest'
        Write-Host '     y ejecutarlo con doble clic.'
        Write-Host ''
        Write-Host 'Despues de instalarlo, cerra y volve a abrir PowerShell y corre este script otra vez.' -ForegroundColor Yellow
        Write-Host ''
        return
    }

    $version = (winget --version) 2>$null
    Write-Host "winget detectado (version $version)" -ForegroundColor Green

    # --- 2. Avisar si no se corre como administrador -----------------------
    $identidad = [Security.Principal.WindowsIdentity]::GetCurrent()
    $esAdmin = ([Security.Principal.WindowsPrincipal]$identidad).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)

    if (-not $esAdmin) {
        Write-Host ''
        Write-Host 'AVISO: no estas corriendo PowerShell como administrador.' -ForegroundColor Yellow
        Write-Host 'Algunas instalaciones pueden fallar o pedir confirmacion (UAC).' -ForegroundColor Yellow
        Write-Host 'Recomendado: cerrar y abrir PowerShell con "Ejecutar como administrador".' -ForegroundColor Yellow
    }

    # --- 3. Instalar cada programa ----------------------------------------
    $resultados = @()
    $total = $Programas.Count
    $i = 0

    foreach ($prog in $Programas) {
        $i++
        Write-Host ''
        Write-Host "--- [$i/$total] Instalando $($prog.Nombre)... ---" -ForegroundColor Cyan

        $estado  = 'ERROR'
        $detalle = ''

        try {
            # 2>&1 junta stderr con stdout para que un error de winget no
            # dispare una excepcion de PowerShell y corte el foreach.
            winget install --id $prog.Id -e --silent `
                --accept-package-agreements --accept-source-agreements 2>&1 |
                ForEach-Object { Write-Host "    $_" -ForegroundColor DarkGray }

            $codigo = $LASTEXITCODE

            if ($codigo -eq 0) {
                $estado = 'OK'
            }
            else {
                # winget devuelve codigos distintos de cero cuando el paquete
                # ya estaba instalado. En vez de adivinar cada codigo,
                # preguntamos si el paquete figura instalado.
                winget list --id $prog.Id -e 2>&1 | Out-Null
                if ($LASTEXITCODE -eq 0) {
                    $estado  = 'YA INSTALADO'
                    $detalle = 'ya estaba en la PC, no se toco nada'
                }
                else {
                    $detalle = "winget devolvio el codigo $codigo"
                }
            }
        }
        catch {
            $detalle = $_.Exception.Message
        }

        switch ($estado) {
            'OK' {
                Write-Host "OK: $($prog.Nombre) instalado correctamente." -ForegroundColor Green
            }
            'YA INSTALADO' {
                Write-Host "OK: $($prog.Nombre) $detalle." -ForegroundColor Green
            }
            default {
                Write-Host "ERROR: fallo la instalacion de $($prog.Nombre) -> $detalle" -ForegroundColor Red
                Write-Host '       Se continua con el resto de los programas.' -ForegroundColor Red
            }
        }

        $resultados += [pscustomobject]@{
            Nombre  = $prog.Nombre
            Id      = $prog.Id
            Estado  = $estado
            Detalle = $detalle
        }
    }

    # --- 4. Resumen final --------------------------------------------------
    $ok      = @($resultados | Where-Object { $_.Estado -ne 'ERROR' })
    $fallado = @($resultados | Where-Object { $_.Estado -eq 'ERROR' })

    Write-Host ''
    Write-Host '===========================================' -ForegroundColor Cyan
    Write-Host '  RESUMEN' -ForegroundColor Cyan
    Write-Host '===========================================' -ForegroundColor Cyan
    Write-Host ''

    if ($ok.Count -gt 0) {
        Write-Host "Correctos ($($ok.Count)/$total):" -ForegroundColor Green
        foreach ($r in $ok) {
            $extra = if ($r.Estado -eq 'YA INSTALADO') { ' (ya estaba instalado)' } else { '' }
            Write-Host "  [OK]    $($r.Nombre)$extra" -ForegroundColor Green
        }
        Write-Host ''
    }

    if ($fallado.Count -gt 0) {
        Write-Host "Fallaron ($($fallado.Count)/$total):" -ForegroundColor Red
        foreach ($r in $fallado) {
            Write-Host "  [FALLO] $($r.Nombre) -> $($r.Detalle)" -ForegroundColor Red
        }
        Write-Host ''
        Write-Host 'Podes reintentar los que fallaron a mano con:' -ForegroundColor Yellow
        foreach ($r in $fallado) {
            Write-Host "  winget install --id $($r.Id) -e --accept-package-agreements --accept-source-agreements" -ForegroundColor Yellow
        }
        Write-Host ''
    }
    else {
        Write-Host 'No fallo ninguna instalacion.' -ForegroundColor Green
        Write-Host ''
    }

    Write-Host 'Listo. Puede que algunos programas necesiten reiniciar la PC.' -ForegroundColor Cyan
    Write-Host ''
}

Invoke-SetupPC
