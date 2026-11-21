function Motor-Windows { Join-Path ([Environment]::SystemDirectory) 'WindowsPowerShell\v1.0\powershell.exe' }
function Nombre-Tarea { 'MantenimientoPC-' + ([Security.Principal.WindowsIdentity]::GetCurrent()).User.Value }
function Ruta-Acceso { Join-Path ([Environment]::GetFolderPath('DesktopDirectory')) 'Mantenimiento PC.lnk' }
function Argumentos-App([string]$modo) { '-NoProfile -NonInteractive -STA -WindowStyle Hidden -File "' + (Join-Path $PSScriptRoot 'MantenimientoPC.ps1') + '" -Modo ' + $modo }

function Buscar-Tarea($nombre = (Nombre-Tarea)) {
    try { Get-ScheduledTask -TaskPath '\' -TaskName $nombre -ErrorAction Stop }
    catch { if ($_.FullyQualifiedErrorId -notlike 'CmdletizationQuery_NotFound*') { throw } }
}
function Tarea-Propia($nombre = (Nombre-Tarea)) {
    $t = Buscar-Tarea $nombre
    if ($t -and ($t.Actions.Count -ne 1 -or $t.Actions[0].Arguments -ne (Argumentos-App Programada) -or $t.Actions[0].Execute -ne (Motor-Windows))) {
        throw 'Ya hay una tarea con ese nombre que no pertenece a esta carpeta. No se modificó.'
    }
    $t
}
function Crear-Tarea([DayOfWeek]$Dia, [datetime]$Hora, [string]$nombre = (Nombre-Tarea), [string]$argumentos = (Argumentos-App Programada), [switch]$Reemplazar, [datetime]$UnaVez = [datetime]::MinValue) {
    $user = [Security.Principal.WindowsIdentity]::GetCurrent().Name
    $principal = New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive -RunLevel Limited -ErrorAction Stop
    $action = New-ScheduledTaskAction -Execute (Motor-Windows) -Argument $argumentos -WorkingDirectory $PSScriptRoot -ErrorAction Stop
    $trigger = if ($UnaVez -gt [datetime]::MinValue) { New-ScheduledTaskTrigger -Once -At $UnaVez -ErrorAction Stop } else { New-ScheduledTaskTrigger -Weekly -WeeksInterval 1 -DaysOfWeek $Dia -At $Hora -ErrorAction Stop }
    $settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Seconds 120) -ErrorAction Stop
    Register-ScheduledTask -TaskName $nombre -TaskPath '\' -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Description 'Mantenimiento PC: comprobaciones de solo lectura, sin servicio residente.' -Force:$Reemplazar -ErrorAction Stop | Out-Null
}
function Guardar-Programa([DayOfWeek]$Dia, [datetime]$Hora) {
    $t = Tarea-Propia
    if ($t -and $t.State -eq 'Running') { throw 'Espera a que termine la revisión programada antes de reconfigurarla.' }
    Crear-Tarea $Dia $Hora -Reemplazar:([bool]$t)
    if ($t -and $t.State -eq 'Disabled') { Disable-ScheduledTask -TaskName (Nombre-Tarea) -TaskPath '\' -ErrorAction Stop | Out-Null }
}
function Cambiar-Pausa {
    $t = Tarea-Propia
    if (!$t) { throw 'Primero guarda un horario semanal.' }
    if ($t.State -eq 'Disabled') { $t | Enable-ScheduledTask -ErrorAction Stop | Out-Null }
    else { $t | Disable-ScheduledTask -ErrorAction Stop | Out-Null }
}
function Acceso-Propio($ruta) {
    if (![IO.File]::Exists($ruta)) { return $false }
    $s = (New-Object -ComObject WScript.Shell).CreateShortcut($ruta)
    if ($s.TargetPath -ne (Motor-Windows) -or $s.Arguments -ne (Argumentos-App Interfaz)) {
        throw 'Ya existe un acceso directo con ese nombre que no pertenece a esta carpeta. No se modificó.'
    }
    $true
}
function Crear-Acceso([string]$ruta = (Ruta-Acceso)) {
    if (Acceso-Propio $ruta) { return }
    $s = (New-Object -ComObject WScript.Shell).CreateShortcut($ruta)
    $s.TargetPath = Motor-Windows; $s.Arguments = Argumentos-App Interfaz
    $s.WorkingDirectory = $PSScriptRoot; $s.Description = 'Abrir Mantenimiento PC'; $s.Save()
}
function Quitar-Integracion([string]$ruta = (Ruta-Acceso)) {
    $t = Tarea-Propia
    $s = Acceso-Propio $ruta
    if ($t) {
        if ($t.State -eq 'Running') { throw 'Espera a que termine la revisión programada antes de desinstalar.' }
        $t | Unregister-ScheduledTask -Confirm:$false -ErrorAction Stop
    }
    if ($s) { [IO.File]::Delete($ruta) }
    if ((Tarea-Propia) -or (Acceso-Propio $ruta)) { throw 'No se pudo verificar la retirada.' }
}
function Abrir-Herramienta([string]$tipo) {
    switch ($tipo) {
        'Inicio' { Start-Process 'ms-settings:startupapps' -ErrorAction Stop }
        'Aplicaciones' { Start-Process 'ms-settings:appsfeatures' -ErrorAction Stop }
        'Windows Update' { Start-Process 'ms-settings:windowsupdate' -ErrorAction Stop }
        'Seguridad' { Start-Process 'windowsdefender:' -ErrorAction Stop }
        'Copias' { Start-Process (Join-Path ([Environment]::SystemDirectory) 'control.exe') -ArgumentList '/name Microsoft.FileHistory' -ErrorAction Stop }
        'Optimizar unidades' { Start-Process (Join-Path ([Environment]::SystemDirectory) 'dfrgui.exe') -ErrorAction Stop }
    }
}
