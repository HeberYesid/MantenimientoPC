#requires -Version 5.1
param([switch]$Programador,[switch]$Interfaz,[switch]$Trabajador,[string]$CarpetaPrueba)
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\Revision.ps1"
. "$PSScriptRoot\Diagnostico.ps1"
. "$PSScriptRoot\Estado.ps1"
. "$PSScriptRoot\Integracion.ps1"
Add-Type -Path "$PSScriptRoot\Archivos.cs"
function Afirmar($condicion,[string]$mensaje) { if (!$condicion) { throw $mensaje } }
if ($Trabajador) {
    $script:Datos = $CarpetaPrueba
    try { Ejecutar-Revision Semanal Programada | Out-Null } catch {
        [IO.File]::WriteAllText((Join-Path $CarpetaPrueba 'error.txt'), $_.ToString()); exit 1
    }
    exit 0
}
$archivosProyecto = @(Get-ChildItem $PSScriptRoot -Filter '*.ps1')
foreach ($archivo in $archivosProyecto) {
    $tokens = $errores = $null
    $null = [Management.Automation.Language.Parser]::ParseFile($archivo.FullName,[ref]$tokens,[ref]$errores)
    Afirmar (!$errores.Count) "Sintaxis inválida: $($archivo.Name): $errores"
}
"PASA: sintaxis de $($archivosProyecto.Count) scripts y compilación de Archivos.cs."
$base = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'Temp\opencode'
$raiz = Join-Path $base ('mpc-prueba-' + [guid]::NewGuid().ToString('N'))
$script:Datos = Join-Path $raiz 'datos'
$sandbox = Join-Path $raiz 'archivos'; $fuera = Join-Path $raiz 'fuera'; $enlace = Join-Path $sandbox 'atajo'
$nombre = 'MantenimientoPC-Prueba-' + [guid]::NewGuid().ToString('N')
$atajo = Join-Path $raiz 'Prueba.lnk'; $tareaCreada = $false
function Crear-Falso($dir,$nombre,$contenido='ficticio',[switch]$Nuevo) {
    $p = Join-Path $dir $nombre; [IO.File]::WriteAllText($p,$contenido)
    if (!$Nuevo) { [IO.File]::SetCreationTimeUtc($p,[datetime]::UtcNow.AddDays(-22)); [IO.File]::SetLastWriteTimeUtc($p,[datetime]::UtcNow.AddDays(-20)) }
    $p
}
try {
    [IO.Directory]::CreateDirectory($sandbox) | Out-Null
    [IO.Directory]::CreateDirectory($fuera) | Out-Null
    [IO.Directory]::CreateDirectory($script:Datos) | Out-Null
    $elegido = Crear-Falso $sandbox 'borrar.tmp'; $guardar = Crear-Falso $sandbox 'conservar.temp'
    $nuevo = Crear-Falso $sandbox 'nuevo.tmp' -Nuevo; $personal = Crear-Falso $sandbox 'documento.docx'
    $cookie = Crear-Falso $sandbox 'cookies.tmp'; $cambio = Crear-Falso $sandbox 'cambio.tmp'
    $bloqueado = Crear-Falso $sandbox 'bloqueado.tmp'; $externo = Crear-Falso $fuera 'externo.tmp' 'contenido externo'
    $hard = Join-Path $sandbox 'hard.tmp'
    New-Item -ItemType HardLink -Path $hard -Target $externo | Out-Null
    New-Item -ItemType Junction -Path $enlace -Target $fuera | Out-Null
    $v = [ArchivosMpc]::Buscar($sandbox,[datetime]::UtcNow.AddDays(-14))
    Afirmar ($v.Archivos.Count -eq 4) 'Vista previa no filtró los archivos correctamente.'
    Afirmar (Test-Path -LiteralPath $elegido) 'Una vista previa modificó archivos.'
    Afirmar (@(Quitar-Seleccion $sandbox @()).Count -eq 0) 'La selección vacía no es inocua.'
    $antes = $v.Archivos | Where-Object Ruta -EQ $cambio
    [IO.File]::AppendAllText($cambio, ' (cambió después de la vista previa)')
    $r = @(Quitar-Seleccion $sandbox @($v.Archivos | Where-Object Ruta -EQ $elegido))
    Afirmar ($r.Count -eq 1 -and $r[0] -like 'Eliminado y verificado:*' -and !(Test-Path -LiteralPath $elegido)) 'Eliminación/fallo de verificación.'
    $r = Quitar-Seleccion $sandbox @($antes)
    Afirmar ($r -like 'Omitido:*' -and (Test-Path -LiteralPath $cambio)) 'Se quitó un archivo cambiado.'
    $h = [IO.File]::Open($bloqueado,'Open','Read','Read')
    try { $r = Quitar-Seleccion $sandbox @($v.Archivos | Where-Object Ruta -EQ $bloqueado); Afirmar ($r -like 'Omitido:*') 'Se eliminó un archivo en uso.' }
    finally { $h.Dispose() }
    Afirmar (($r = Quitar-Seleccion $enlace @($v.Archivos | Where-Object Ruta -EQ $guardar)) -like 'Omitido:*') 'Se aceptó una raíz enlazada.'
    foreach ($p in $guardar,$nuevo,$personal,$cookie,$bloqueado,$externo,$hard) { Afirmar (Test-Path -LiteralPath $p) 'Archivo no seleccionado o inelegible eliminado.' }
    'PASA: vista previa, selección vacía, solo selección, archivo cambiado/en uso, archivo personal, cookie, reciente, unión y enlace duro.'

    $null = Crear-Falso $sandbox 'igual-a.txt' 'solo duplicado ficticio'
    $null = Crear-Falso $sandbox 'igual-b.txt' 'solo duplicado ficticio'
    $null = Crear-Falso $fuera 'no-analizado.txt' 'solo duplicado ficticio'
    $dup = Buscar-Duplicados @($sandbox)
    Afirmar ($dup -like '*igual-a.txt*' -and $dup -like '*igual-b.txt*' -and $dup -notlike '*no-analizado.txt*') 'El análisis de duplicados no respeta contenido/alcance.'
    'PASA: duplicados por contenido y aislamiento de carpetas elegidas.'

    $h1 = Hallazgo prueba 'Prueba comparativa' 'Alerta' 'Ficticia' 1 2
    $h2 = Hallazgo prueba 'Prueba comparativa' 'Alerta' 'Ficticia' 1 3
    $ref = @(@{Hallazgos=@($h1)})
    Afirmar (@(Comparar @($h1) @()).Count -eq 1) 'Alerta nueva omitida.'
    Afirmar (@(Comparar @($h1) $ref).Count -eq 0) 'Alerta sin cambios repetida.'
    Afirmar (@(Comparar @($h2) $ref).Count -eq 1) 'Alerta empeorada omitida.'
    Afirmar (@(Comparar @($h1) (@(@{Hallazgos=@((NoDisponible prueba 'Prueba' 'Sin fuente'))}) + $ref)).Count -eq 0) 'Se olvidó la referencia al perder datos temporalmente.'
    $fallo = Hallazgo fallo-prueba 'Fallo de prueba' 'Repetido' 'Ficticio' 1 2
    $sinFallo = Hallazgo fallos 'Fallos' 'Sin repeticiones observadas' 'Ficticio'
    $sinFallo | Add-Member NoteProperty Completo $true
    Afirmar (@(Comparar @($fallo) @(@{Hallazgos=@($sinFallo)},@{Hallazgos=@($fallo)})).Count -eq 1) 'Reaparición tras una lectura completa omitida.'
    'PASA: alerta nueva, sin cambios, empeorada, fuente intermitente y reaparición tras una lectura completa.'

    $r = @(Ejecutar-Revision Semanal Manual)
    Afirmar ($r.Count -eq 1 -and $r[0].Origen -eq 'Manual' -and $r[0].Hallazgos.Count -ge 10) 'No se produjo el informe semanal manual.'
    foreach ($id in 'temp','inicio','eventos-disco','fallos','reinicio','update','defender','firewall','backup','filehistory') {
        Afirmar ($id -in $r[0].Hallazgos.Id) "Falta el indicador $id."
    }
    $r = @(Ejecutar-Revision Mensual Manual)
    Afirmar ($r.Count -eq 1 -and $r[0].Tipo -eq 'Mensual' -and $r[0].Hallazgos.Count -eq 4) 'No se produjo el informe mensual manual.'
    Afirmar (@(Leer-Historial).Count -eq 2) 'El historial aislado no contiene ambos informes.'
    $m = (Medir-Lentitud 3 1000) -join "`n"
    foreach ($tipo in 'CPU','RAM','Disco') { Afirmar ($m -match "${tipo}: .*3/3") "No se midió $tipo en las tres muestras de este equipo." }
    'PASA: pasada manual semanal/mensual, historial aislado y diagnóstico real con tres muestras por recurso.'

    Crear-Acceso $atajo
    Afirmar (Acceso-Propio $atajo) 'No se pudo validar el acceso directo temporal.'
    [IO.File]::Delete($atajo)
    Afirmar (!(Test-Path -LiteralPath $atajo)) 'El acceso directo temporal permanece.'
    'PASA: creación, destino y retirada de acceso en carpeta temporal (no se tocó el escritorio).'

    if ($Interfaz) {
        . "$PSScriptRoot\Interfaz.ps1"
        $arenaUI = Join-Path $raiz 'interfaz'; [IO.Directory]::CreateDirectory($arenaUI) | Out-Null
        $null = Crear-Falso $arenaUI 'elegir.tmp'; $null = Crear-Falso $arenaUI 'conservar.tmp'
        Mostrar-Interfaz -CarpetaPruebaUI $arenaUI
        'PASA: WinForms, botón de revisión mensual, historial visible, vista previa de limpieza, cancelación, confirmación simulada y verificación de solo la selección.'
    }
    if ($Programador) {
        $argumentos = '-NoProfile -NonInteractive -STA -WindowStyle Hidden -File "' + $PSCommandPath + '" -Trabajador -CarpetaPrueba "' + $script:Datos + '"'
        $ahora = Get-Date
        Crear-Tarea $ahora.DayOfWeek $ahora.AddMinutes(5) -nombre $nombre -argumentos $argumentos
        $tareaCreada = $true
        "Recurso temporal: $nombre; inicio $($ahora.ToString('o')); comando $(Motor-Windows) $argumentos"
        $t = Buscar-Tarea $nombre
        Afirmar ($t.Triggers[0].WeeksInterval -eq 1 -and $t.Principal.RunLevel -eq 'Limited' -and $t.Principal.LogonType -eq 'Interactive') 'Principal o frecuencia semanal inesperada.'
        $t | Disable-ScheduledTask | Out-Null
        Afirmar ((Buscar-Tarea $nombre).State -eq 'Disabled') 'No se pudo pausar la tarea de prueba.'
        $t | Enable-ScheduledTask | Out-Null
        Afirmar ((Buscar-Tarea $nombre).State -eq 'Ready') 'No se pudo reanudar la tarea de prueba.'
        # Disparador real por reloj, sin esperar una semana, con el mismo principal y acción que la tarea recurrente.
        $hora = (Get-Date).AddSeconds(12)
        Crear-Tarea $hora.DayOfWeek $hora -nombre $nombre -argumentos $argumentos -UnaVez $hora -Reemplazar
        $reloj = [Diagnostics.Stopwatch]::StartNew(); $hecho = $false
        do {
            Start-Sleep -Milliseconds 500
            $t = Buscar-Tarea $nombre; $ti = $t | Get-ScheduledTaskInfo
            # Windows puede publicar LastRunTime antes de actualizar State y LastTaskResult.
            if ($ti.LastRunTime -ge $hora.AddSeconds(-2) -and $t.State -ne 'Running' -and $ti.LastTaskResult -ne 0x41301) { $hecho = $true; break }
        } while ($reloj.Elapsed.TotalSeconds -lt 95)
        if ([IO.File]::Exists((Join-Path $script:Datos 'error.txt'))) { throw [IO.File]::ReadAllText((Join-Path $script:Datos 'error.txt')) }
        Afirmar ($hecho -and $ti.LastTaskResult -eq 0) "Tarea no completada con éxito; último código: $($ti.LastTaskResult)."
        $h = @(Leer-Historial)
        $esperados = if ($Interfaz) { 4 } else { 3 }
        Afirmar ($h.Count -eq $esperados -and $h[0].Origen -eq 'Programada' -and $h[0].Tipo -eq 'Semanal') 'No se persistió el resultado programado o se duplicó el inventario del mes.'
        $archHist = Join-Path $script:Datos 'historial.json'
        [IO.File]::Delete($archHist)
        $r = @(Ejecutar-Revision Semanal Programada -SinConsultaActualizaciones)
        Afirmar ($r.Count -eq 2 -and $r[0].Tipo -eq 'Mensual') 'No se generó el inventario mensual en la primera revisión programada.'
        'PASA: definición semanal limitada, pausa, reanudación, disparo real por reloj con código 0 e historial, cadencia mensual.'
    }
} finally {
    if ($tareaCreada -and ($t = Buscar-Tarea $nombre)) {
        if ($t.State -eq 'Running') { $t | Stop-ScheduledTask }
        $t | Unregister-ScheduledTask -Confirm:$false
        Afirmar (!(Buscar-Tarea $nombre)) 'No se confirmó la retirada de la tarea temporal.'
    }
    if ([IO.Directory]::Exists($enlace)) { [IO.Directory]::Delete($enlace,$false) }
    if ([IO.Directory]::Exists($raiz)) { [IO.Directory]::Delete($raiz,$true) }
    Afirmar (!(Test-Path -LiteralPath $raiz)) 'No se confirmó que la carpeta temporal se haya retirado.'
    'Limpieza verificada: no quedó la carpeta temporal ni la tarea registrada por la prueba.'
}
