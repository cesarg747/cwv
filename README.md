# cwv

Script de PowerShell para dejar lista una PC recién formateada. Muestra un menú
y desde ahí instala los programas básicos usando
[winget](https://learn.microsoft.com/windows/package-manager/), abre las Opciones
de rendimiento y abre la activación de Windows.

Si winget no está (caso típico de **Windows 10 LTSC**, que no trae Microsoft Store),
el script lo instala solo antes de seguir.

## Uso

Abrir **PowerShell como administrador** y ejecutar:

```powershell
irm https://cesarg747.github.io/cwv/setup.ps1 | iex
```

Si `irm | iex` da error de política de ejecución, correr antes:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
```

## El menú

```
===========================================
  Setup de PC
===========================================

  1) Instalar programas (Chrome, VLC, WinRAR)
  2) Abrir Opciones de rendimiento
  3) Abrir la activación de Windows
  0) Salir

Elegi una opcion:
```

El menú vuelve a aparecer después de cada acción, así que se pueden encadenar
varias sin volver a correr el script. Si una opción falla, el menú sigue en pie.

| Opción | Qué hace |
|--------|----------|
| 1 | Instala uno por uno los programas de la lista. Si winget falta, lo instala primero. |
| 2 | Abre `SystemPropertiesPerformance.exe`: el cuadro de Propiedades del sistema → Opciones avanzadas → Rendimiento → Configuración. |
| 3 | Abre `ms-settings:activation`, para cargar la clave de producto. |
| 0 | Sale. |

## Instalación de programas (opción 1)

1. Verifica que `winget` esté instalado, y si no lo instala (ver más abajo).
2. Avisa si PowerShell no se está ejecutando como administrador.
3. Instala cada programa de la lista, uno por uno, en modo silencioso.
4. Si una instalación falla, lo informa y **sigue con las siguientes**.
5. Al final muestra un resumen de qué se instaló, qué ya estaba y qué falló,
   con el comando exacto para reintentar los que fallaron.

### Programas incluidos

| Programa | ID de winget |
|----------|--------------|
| Google Chrome | `Google.Chrome` |
| VLC Media Player | `VideoLAN.VLC` |
| WinRAR | `RARLab.WinRAR` |

### Agregar o sacar programas

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

## Agregar opciones al menú

Igual que con los programas: hay una lista `$Menu` arriba de todo. `Accion` es
un bloque de código entre llaves, así que puede ser cualquier cosa.

```powershell
$Menu = @(
    @{ Tecla = '1'; Titulo = 'Instalar programas (Chrome, VLC, WinRAR)'; Accion = { Install-Programas } }
    @{ Tecla = '2'; Titulo = 'Abrir Opciones de rendimiento';            Accion = { Open-OpcionesRendimiento } }
    @{ Tecla = '3'; Titulo = 'Abrir la activacion de Windows';           Accion = { Open-Activacion } }
    @{ Tecla = '4'; Titulo = 'Abrir el Administrador de discos';         Accion = { Start-Process 'diskmgmt.msc' } }
)
```

La opción `0) Salir` la agrega el menú solo, no hace falta ponerla en la lista.

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

## Las URLs

| URL | Largo | Qué trae |
|-----|-------|----------|
| `https://cesarg747.github.io/cwv/setup.ps1` | 41 | siempre lo último de `main` |
| `https://github.com/cesarg747/cwv/raw/main/setup.ps1` | 51 | lo mismo, sin pasar por Pages |
| `https://github.com/cesarg747/cwv/raw/v4/setup.ps1` | 49 | la versión `v4`, congelada |

La de GitHub Pages es la corta y la de todos los días. Sirve la rama `main`, o sea
lo último que haya. **Pages no entiende de tags**: en su URL no hay ningún tramo
donde poner la versión. Para congelar una versión hay que usar la de `raw` con un tag.

Pages tarda alrededor de un minuto en republicar después de cada push. Si editás
el script y corrés la URL corta enseguida, puede que todavía te dé la versión anterior.

### Ojo con los tags viejos

Hasta `v2` este repo se llamaba `pc-setup` y el script `setup-pc.ps1`. Los tags
apuntan a commits, y en esos commits el archivo todavía tiene el nombre viejo,
así que hay que pedirlo como estaba:

| Tag | URL que funciona |
|-----|------------------|
| `v1` | `.../cwv/raw/v1/setup-pc.ps1` — versión que **no** instala winget |
| `v2` | `.../cwv/raw/v2/setup-pc.ps1` — ya instala winget |
| `v3` | `.../cwv/raw/v3/setup.ps1` — nombres nuevos, sin menú |
| `v4` | `.../cwv/raw/v4/setup.ps1` — con menú |

De `v3` en adelante el nombre es siempre `setup.ps1`.

## Notas

- Los programas que ya estén instalados se marcan como *ya instalado* y no se tocan.
- Se usa `--silent`, así que las instalaciones no muestran ventanas. Sacando ese
  flag del script se ven los instaladores.
- Algunos programas pueden pedir reiniciar la PC.
