<#
.SYNOPSIS
    Instalacion desatendida de programas basicos en una PC nueva, usando winget.

.DESCRIPTION
    Pensado para correr en una PC recien formateada, desde PowerShell como
    administrador:

        irm https://cesarg747.github.io/cwv/setup.ps1 | iex

    Muestra un menu: 1 instala los programas, 2 abre las Opciones de
    rendimiento, 3 abre la activacion de Windows, 0 sale.

    Si winget no esta instalado (caso tipico de Windows 10 LTSC, que no trae
    Microsoft Store), el script lo instala solo bajando el paquete oficial de
    Microsoft antes de seguir.

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
# OPCIONES DEL MENU  <-- y esto
#
# Tecla   = lo que hay que apretar
# Titulo  = lo que se muestra en pantalla
# Accion  = el bloque de codigo que se ejecuta, entre llaves
#
# La opcion 0 (Salir) la agrega el menu solo, no hace falta ponerla aca.
# ---------------------------------------------------------------------------
$Menu = @(
    @{ Tecla = '1'; Titulo = 'Instalar programas (Chrome, VLC, WinRAR)'; Accion = { Install-Programas } }
    @{ Tecla = '2'; Titulo = 'Abrir Opciones de rendimiento';            Accion = { Open-OpcionesRendimiento } }
    @{ Tecla = '3'; Titulo = 'Abrir la activacion de Windows';           Accion = { Open-Activacion } }
)

# ---------------------------------------------------------------------------
# De aca para abajo no hace falta tocar nada
# ---------------------------------------------------------------------------

# Build minimo que soporta winget: Windows 10 1809. Por debajo de eso no hay
# forma de instalarlo (winget depende de MSIX y de IsWow64Process2).
$BuildMinimo = 17763

function Test-Administrador {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    return ([Security.Principal.WindowsPrincipal]$id).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Test-Winget {
    # Al instalar App Installer, el alias de winget aparece en WindowsApps, que
    # ya esta en el PATH del usuario, pero la sesion actual tiene la copia vieja
    # del PATH en memoria. Por eso lo recargamos antes de buscar.
    $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' +
                [Environment]::GetEnvironmentVariable('Path', 'User')
    return [bool](Get-Command winget -ErrorAction SilentlyContinue)
}

function Install-Winget {
    <#
        Instala App Installer (winget) bajando los paquetes oficiales desde el
        repositorio microsoft/winget-cli. Devuelve $true si winget quedo usable.

        Los nombres de los archivos cambian en cada version (el de la licencia
        lleva un hash adelante), asi que se consultan por API en vez de
        hardcodearlos.
    #>

    Write-Host ''
    Write-Host 'winget no esta instalado. Intento instalarlo automaticamente.' -ForegroundColor Yellow
    Write-Host ''

    $build = [Environment]::OSVersion.Version.Build
    if ($build -lt $BuildMinimo) {
        Write-Host "ERROR: esta PC es build $build y winget necesita $BuildMinimo (Windows 10 1809) o mayor." -ForegroundColor Red
        Write-Host 'En esta version de Windows winget no se puede instalar. Hay que instalar los programas a mano.' -ForegroundColor Red
        return $false
    }

    if (-not (Test-Administrador)) {
        Write-Host 'ERROR: para instalar winget hace falta PowerShell como administrador.' -ForegroundColor Red
        Write-Host 'Cerra esta ventana, abri PowerShell con "Ejecutar como administrador" y volve a correr el script.' -ForegroundColor Red
        return $false
    }

    # Windows 10 1809 no negocia TLS 1.2 por defecto en .NET, y sin esto las
    # descargas desde GitHub fallan con "conexion cerrada inesperadamente".
    try {
        [Net.ServicePointManager]::SecurityProtocol =
            [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    } catch { }

    # La barra de progreso de Invoke-WebRequest en PowerShell 5.1 hace que las
    # descargas grandes tarden muchisimo mas. Se apaga y se restaura al final.
    $progresoOriginal = $ProgressPreference
    $ProgressPreference = 'SilentlyContinue'

    $carpeta = Join-Path $env:TEMP 'winget-bootstrap'
    New-Item -ItemType Directory -Force -Path $carpeta | Out-Null

    try {
        Write-Host 'Consultando la ultima version de winget...' -ForegroundColor Cyan
        $release = Invoke-RestMethod 'https://api.github.com/repos/microsoft/winget-cli/releases/latest' `
            -Headers @{ 'User-Agent' = 'cwv' } -ErrorAction Stop

        Write-Host "Version encontrada: $($release.tag_name)" -ForegroundColor Green

        $aBundle  = $release.assets | Where-Object { $_.name -like '*.msixbundle' } | Select-Object -First 1
        $aDeps    = $release.assets | Where-Object { $_.name -eq 'DesktopAppInstaller_Dependencies.zip' } | Select-Object -First 1
        $aLicense = $release.assets | Where-Object { $_.name -like '*_License1.xml' } | Select-Object -First 1

        if (-not $aBundle -or -not $aDeps) {
            Write-Host 'ERROR: no encontre los archivos esperados en la release de winget.' -ForegroundColor Red
            return $false
        }

        # Arquitectura de la PC, para sacar del zip solo los appx que sirven.
        switch ($env:PROCESSOR_ARCHITECTURE) {
            'AMD64' { $arch = 'x64' }
            'ARM64' { $arch = 'arm64' }
            default { $arch = 'x86' }
        }
        Write-Host "Arquitectura detectada: $arch" -ForegroundColor Green

        $rutaBundle  = Join-Path $carpeta $aBundle.name
        $rutaDeps    = Join-Path $carpeta $aDeps.name
        $rutaLicense = if ($aLicense) { Join-Path $carpeta $aLicense.name } else { $null }

        $descargas = @(
            @{ Url = $aDeps.browser_download_url;   Destino = $rutaDeps;   Nombre = 'dependencias';  Tam = $aDeps.size }
            @{ Url = $aBundle.browser_download_url; Destino = $rutaBundle; Nombre = 'App Installer'; Tam = $aBundle.size }
        )
        if ($aLicense) {
            $descargas += @{ Url = $aLicense.browser_download_url; Destino = $rutaLicense; Nombre = 'licencia'; Tam = $aLicense.size }
        }

        foreach ($d in $descargas) {
            $mb = [math]::Round($d.Tam / 1MB, 1)
            Write-Host "Descargando $($d.Nombre) ($mb MB)... esto puede tardar varios minutos." -ForegroundColor Cyan
            Invoke-WebRequest -Uri $d.Url -OutFile $d.Destino -UseBasicParsing -ErrorAction Stop
        }

        Write-Host 'Descomprimiendo dependencias...' -ForegroundColor Cyan
        $carpetaDeps = Join-Path $carpeta 'deps'
        if (Test-Path $carpetaDeps) { Remove-Item $carpetaDeps -Recurse -Force }
        Expand-Archive -Path $rutaDeps -DestinationPath $carpetaDeps -Force

        $appxDeps = Get-ChildItem -Path (Join-Path $carpetaDeps $arch) -Filter '*.appx' -ErrorAction Stop

        foreach ($dep in $appxDeps) {
            Write-Host "  Instalando dependencia $($dep.Name)..." -ForegroundColor DarkGray
            try {
                Add-AppxPackage -Path $dep.FullName -ErrorAction Stop
            }
            catch {
                # Si ya hay una version igual o mas nueva, Windows tira error.
                # No es un problema: la dependencia esta cubierta igual.
                Write-Host "  (se omite: ya hay una version igual o mas nueva)" -ForegroundColor DarkGray
            }
        }

        Write-Host 'Instalando App Installer (winget)...' -ForegroundColor Cyan
        Add-AppxPackage -Path $rutaBundle -ErrorAction Stop

        # Provisionar deja winget disponible tambien para los usuarios que se
        # creen despues. Es lo que corresponde en una PC que se va a entregar.
        if ($rutaLicense) {
            try {
                Add-AppxProvisionedPackage -Online -PackagePath $rutaBundle `
                    -DependencyPackagePath ($appxDeps.FullName) -LicensePath $rutaLicense `
                    -ErrorAction Stop | Out-Null
                Write-Host 'winget provisionado para todos los usuarios.' -ForegroundColor Green
            }
            catch {
                Write-Host 'Aviso: quedo instalado para este usuario, pero no se pudo provisionar para todos.' -ForegroundColor Yellow
            }
        }

        # El alias de winget tarda unos segundos en registrarse.
        for ($intento = 1; $intento -le 10; $intento++) {
            if (Test-Winget) {
                Write-Host 'winget instalado correctamente.' -ForegroundColor Green
                return $true
            }
            Start-Sleep -Seconds 2
        }

        Write-Host 'winget se instalo pero todavia no responde en esta ventana.' -ForegroundColor Yellow
        Write-Host 'Cerra PowerShell, abrilo de nuevo como administrador y volve a correr el script.' -ForegroundColor Yellow
        return $false
    }
    catch {
        Write-Host "ERROR instalando winget: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host ''
        Write-Host 'Alternativa a mano:' -ForegroundColor Yellow
        Write-Host '  1) Bajar https://github.com/microsoft/winget-cli/releases/latest'
        Write-Host '     (el .msixbundle y DesktopAppInstaller_Dependencies.zip)'
        Write-Host '  2) Instalar primero los .appx de tu arquitectura y despues el .msixbundle'
        Write-Host ''
        return $false
    }
    finally {
        $ProgressPreference = $progresoOriginal
    }
}

function Install-Programas {

    Write-Host ''
    Write-Host '--- Instalacion de programas ---------------' -ForegroundColor Cyan
    Write-Host ''

    # --- 1. Verificar winget, y si falta instalarlo ------------------------
    if (-not (Test-Winget)) {
        if (-not (Install-Winget)) {
            Write-Host 'No se puede continuar sin winget.' -ForegroundColor Red
            Write-Host ''
            return
        }
    }

    $version = (winget --version) 2>$null
    Write-Host "winget detectado (version $version)" -ForegroundColor Green

    # --- 2. Avisar si no se corre como administrador -----------------------
    if (-not (Test-Administrador)) {
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

function Open-OpcionesRendimiento {
    # SystemPropertiesPerformance.exe abre directo el cuadro "Opciones de
    # rendimiento", el que esta en Propiedades del sistema > Opciones
    # avanzadas > Rendimiento > Configuracion.
    Write-Host ''
    Write-Host 'Abriendo Opciones de rendimiento...' -ForegroundColor Cyan
    try {
        Start-Process 'SystemPropertiesPerformance.exe' -ErrorAction Stop
        Write-Host 'Listo: la ventana se abrio aparte de esta consola.' -ForegroundColor Green
    }
    catch {
        Write-Host "ERROR: no se pudo abrir ($($_.Exception.Message))" -ForegroundColor Red
    }
    Write-Host ''
}

function Open-Activacion {
    Write-Host ''
    Write-Host 'Abriendo la configuracion de activacion de Windows...' -ForegroundColor Cyan
    try {
        Start-Process 'ms-settings:activation' -ErrorAction Stop
        Write-Host 'Listo: desde ahi se carga la clave de producto.' -ForegroundColor Green
    }
    catch {
        Write-Host "ERROR: no se pudo abrir ($($_.Exception.Message))" -ForegroundColor Red
    }
    Write-Host ''
}

function Invoke-Menu {
    while ($true) {
        Write-Host ''
        Write-Host '===========================================' -ForegroundColor Cyan
        Write-Host '  Setup de PC' -ForegroundColor Cyan
        Write-Host '===========================================' -ForegroundColor Cyan
        Write-Host ''

        foreach ($op in $Menu) {
            Write-Host ("  {0}) {1}" -f $op.Tecla, $op.Titulo)
        }
        Write-Host '  0) Salir'
        Write-Host ''

        $tecla = (Read-Host 'Elegi una opcion').Trim()

        if ($tecla -eq '0') {
            Write-Host ''
            Write-Host 'Chau.' -ForegroundColor Cyan
            Write-Host ''
            return
        }

        $elegida = $Menu | Where-Object { $_.Tecla -eq $tecla } | Select-Object -First 1

        if (-not $elegida) {
            Write-Host ''
            Write-Host "Opcion '$tecla' invalida. Proba de nuevo." -ForegroundColor Yellow
            continue
        }

        try {
            & $elegida.Accion
        }
        catch {
            # Que un error dentro de una opcion no tire abajo el menu entero.
            Write-Host ''
            Write-Host "ERROR en '$($elegida.Titulo)': $($_.Exception.Message)" -ForegroundColor Red
            Write-Host ''
        }

        Read-Host 'Presiona Enter para volver al menu' | Out-Null
    }
}

Invoke-Menu
