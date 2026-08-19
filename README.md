# pc-setup

Script de PowerShell para dejar lista una PC recién formateada: instala los
programas básicos de una sola pasada usando [winget](https://learn.microsoft.com/windows/package-manager/).

## Uso

Abrir **PowerShell como administrador** y ejecutar:

```powershell
irm https://raw.githubusercontent.com/cesarg747/pc-setup/main/setup-pc.ps1 | iex
```

Si `irm | iex` da error de política de ejecución, correr antes:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
```

## Qué hace

1. Verifica que `winget` esté instalado. Si no está, explica cómo instalarlo y corta.
2. Avisa si PowerShell no se está ejecutando como administrador.
3. Instala cada programa de la lista, uno por uno, en modo silencioso.
4. Si una instalación falla, lo informa y **sigue con las siguientes**.
5. Al final muestra un resumen de qué se instaló, qué ya estaba y qué falló,
   con el comando exacto para reintentar los que fallaron.

## Programas incluidos

| Programa | ID de winget |
|----------|--------------|
| Google Chrome | `Google.Chrome` |
| VLC Media Player | `VideoLAN.VLC` |
| WinRAR | `RARLab.WinRAR` |

## Agregar o sacar programas

Editar **solamente** la lista `$Programas` que está arriba de todo en
[`setup-pc.ps1`](setup-pc.ps1):

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

## Versión fija

La URL de arriba apunta a `main`: siempre trae la última versión del script.
Si querés una URL que no cambie aunque se edite `main` (por ejemplo para usar en
PCs de clientes), usá el tag `v1`:

```powershell
irm https://raw.githubusercontent.com/cesarg747/pc-setup/v1/setup-pc.ps1 | iex
```

## Notas

- Los programas que ya estén instalados se marcan como *ya instalado* y no se tocan.
- Se usa `--silent`, así que las instalaciones no muestran ventanas. Sacando ese
  flag del script se ven los instaladores.
- Algunos programas pueden pedir reiniciar la PC.
