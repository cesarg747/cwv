# cwv

Script de PowerShell para dejar lista una PC recién formateada: instala los
programas básicos de una sola pasada usando [winget](https://learn.microsoft.com/windows/package-manager/).

Si winget no está (caso típico de **Windows 10 LTSC**, que no trae Microsoft Store),
el script lo instala solo antes de seguir.

## Uso

Abrir **PowerShell como administrador** y ejecutar:

```powershell
irm https://raw.githubusercontent.com/cesarg747/cwv/main/setup.ps1 | iex
```

Si `irm | iex` da error de política de ejecución, correr antes:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
```

## Qué hace

1. Verifica que `winget` esté instalado.
2. Si no está, **lo instala automáticamente** (ver abajo). Si tampoco se puede,
   explica por qué y corta.
3. Avisa si PowerShell no se está ejecutando como administrador.
4. Instala cada programa de la lista, uno por uno, en modo silencioso.
5. Si una instalación falla, lo informa y **sigue con las siguientes**.
6. Al final muestra un resumen de qué se instaló, qué ya estaba y qué falló,
   con el comando exacto para reintentar los que fallaron.

## Programas incluidos

| Programa | ID de winget |
|----------|--------------|
| Google Chrome | `Google.Chrome` |
| VLC Media Player | `VideoLAN.VLC` |
| WinRAR | `RARLab.WinRAR` |

## Agregar o sacar programas

Editar **solamente** la lista `$Programas` que está arriba de todo en
[`setup.ps1`](setup.ps1):

```powershell
$Programas = @(
    @{ Id = 'Google.Chrome'; Nombre = 'Google Chrome' }
    @{ Id = 'VideoLAN.VLC';  Nombre = 'VLC Media Player' }
    @{ Id = 'RARLab.WinRAR'; Nombre = 'WinRAR' }
    @{ Id = 'Notepad++.Notepad++'; Nombre = 'Notepad++' }   # <- nuevo
)
```

Para averiguar el ID de un programa:

```powershell
winget search "nombre del programa"
```

## Windows 10 LTSC (y cualquier PC sin winget)

Las ediciones LTSC de Windows 10 no traen Microsoft Store, así que tampoco traen
el "Instalador de aplicación" que provee `winget`. El script se da cuenta y lo
instala solo:

1. Consulta la última versión publicada en
   [microsoft/winget-cli](https://github.com/microsoft/winget-cli/releases/latest).
2. Baja el `.msixbundle`, el zip de dependencias y el archivo de licencia.
3. Instala las dependencias de la arquitectura de esa PC (VCLibs, VCLibs UWPDesktop
   y WindowsAppRuntime) y después App Installer.
4. Lo provisiona para todos los usuarios, así también lo tienen las cuentas que se
   creen después.
5. Recarga el PATH y sigue con la instalación de los programas.

**Requisitos:**

- Windows 10 build **17763** (versión 1809) o superior. Por debajo de eso winget
  no se puede instalar de ninguna forma: depende de MSIX y de `IsWow64Process2`,
  que no existen en versiones anteriores. LTSC 2019, 2021 y 2024 cumplen.
- PowerShell **como administrador** (sin eso no se puede instalar App Installer).
- Unos **300 MB de descarga**, una sola vez por PC.

Para saber qué build tenés:

```powershell
[Environment]::OSVersion.Version.Build
```

## Versión fija

La URL de arriba apunta a `main`: siempre trae la última versión del script.
Si querés una URL que no cambie aunque se edite `main` (por ejemplo para usar en
PCs de clientes), usá un tag:

```powershell
irm https://raw.githubusercontent.com/cesarg747/cwv/v3/setup.ps1 | iex
```

### Ojo con los tags viejos

Hasta `v2` este repo se llamaba `pc-setup` y el script `setup-pc.ps1`. Los tags
apuntan a commits, y en esos commits el archivo todavia tiene el nombre viejo,
asi que hay que pedirlo como estaba:

| Tag | URL que funciona |
|-----|------------------|
| `v1` | `.../cwv/v1/setup-pc.ps1` — version que **no** instala winget |
| `v2` | `.../cwv/v2/setup-pc.ps1` — ya instala winget |
| `v3` | `.../cwv/v3/setup.ps1` — nombres nuevos |

De `v3` en adelante el nombre es siempre `setup.ps1`.

## Notas

- Los programas que ya estén instalados se marcan como *ya instalado* y no se tocan.
- Se usa `--silent`, así que las instalaciones no muestran ventanas. Sacando ese
  flag del script se ven los instaladores.
- Algunos programas pueden pedir reiniciar la PC.
