function Hallazgo($id, $nombre, $estado, $detalle, $nivel = 0, $valor = 0) {
    [pscustomobject]@{ Id = $id; Nombre = $nombre; Estado = $estado; Detalle = $detalle; Nivel = $nivel; Valor = $valor }
}
function NoDisponible($id, $nombre, $detalle) { Hallazgo $id $nombre 'No disponible' $detalle }
function Huella([string]$texto) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try { [BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($texto))).Replace('-', '') }
    finally { $sha.Dispose() }
}
function Tamano([long]$bytes) {
    if ($bytes -ge 1GB) { '{0:N2} GiB' -f ($bytes / 1GB) }
    elseif ($bytes -ge 1MB) { '{0:N1} MiB' -f ($bytes / 1MB) }
    elseif ($bytes -ge 1KB) { '{0:N1} KiB' -f ($bytes / 1KB) }
    else { "$bytes bytes" }
}
function LeerEventos($filtro, [int]$limite = 1000) {
    try { Get-WinEvent -FilterHashtable $filtro -MaxEvents $limite -ErrorAction Stop }
    catch { if ($_.FullyQualifiedErrorId -notlike 'NoMatchingEventsFound,*') { throw } }
}
function Raiz-Temporal {
    $perfil = [Environment]::GetFolderPath('UserProfile')
    $local = [Environment]::GetFolderPath('LocalApplicationData')
    if (!$perfil -or !$local -or $local -ne (Join-Path $perfil 'AppData\Local')) { throw 'La carpeta temporal estándar del perfil no está disponible.' }
    Join-Path $local 'Temp'
}
function Temporales { [ArchivosMpc]::Buscar((Raiz-Temporal), [datetime]::UtcNow.AddDays(-14)) }
function Quitar-Seleccion([string]$Raiz,$Lista) {
    $limite = [datetime]::UtcNow.AddDays(-14)
    foreach ($i in $Lista) {
        try { $r = [ArchivosMpc]::Quitar($Raiz,$i,$limite) }
        catch { $r = 'Omitido: ' + $_.Exception.GetBaseException().Message }
        "${r}: $($i.Ruta)"
    }
}

function Comparar($actual, $anteriores) {
    $previo = @{}
    $fallosConReferencia = $false
    foreach ($informe in $anteriores) {
        foreach ($h in $informe.Hallazgos) {
            if ($h.Estado -eq 'No disponible' -or $previo.ContainsKey($h.Id)) { continue }
            if ($h.Id -like 'fallo-*' -and $fallosConReferencia) { continue }
            $previo[$h.Id] = $h
        }
        # Una lectura completa posterior sin ese grupo indica que ya no era un fallo repetido.
        if ($informe.Hallazgos | Where-Object { $_.Id -eq 'fallos' -and $_.Completo -eq $true }) { $fallosConReferencia = $true }
    }
    foreach ($h in $actual) {
        if ($h.Nivel -le 0 -or $h.Estado -eq 'No disponible') { continue }
        if (-not $previo.ContainsKey($h.Id) -or $previo[$h.Id].Nivel -lt $h.Nivel -or
            ($previo[$h.Id].Nivel -eq $h.Nivel -and $previo[$h.Id].Valor -lt $h.Valor)) { $h }
    }
}

function Revisar-Semana($anterior, [switch]$SinConsultaActualizaciones) {
    try {
        $vols = @(Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3' -OperationTimeoutSec 8 -ErrorAction Stop)
        if (!$vols.Count) { throw 'Sin volúmenes' }
        foreach ($d in $vols) {
            $id = 'espacio-' + $d.DeviceID; $n = 'Espacio ' + $d.DeviceID
            if (!$d.Size -or $null -eq $d.FreeSpace) { NoDisponible $id $n 'Windows no informó capacidad y espacio libre.'; continue }
            $pct = 100 * $d.FreeSpace / $d.Size
            $nivel = if ($pct -lt 5 -or $d.FreeSpace -lt 2GB) { 2 } elseif ($pct -lt 12 -or $d.FreeSpace -lt 5GB) { 1 } else { 0 }
            $estado = if ($nivel) { 'Poco espacio' } else { 'Medido' }
            Hallazgo $id $n $estado ('{0} libres de {1} ({2:N1} %).' -f (Tamano $d.FreeSpace), (Tamano $d.Size), $pct) $nivel
        }
    } catch { NoDisponible espacio 'Espacio' 'No se pudieron consultar las unidades fijas.' }
    try {
        $t = Temporales
        $total = 0L; foreach ($f in $t.Archivos) { $total += $f.Bytes }
        $cobertura = if ($t.Limitada -or $t.Inaccesibles) { " Resultado parcial; inaccesibles: $($t.Inaccesibles)." } else { '' }
        $estado = if ($cobertura) { 'Parcial' } else { 'Medido' }
        Hallazgo temp 'Temporales antiguos' $estado "$($t.Archivos.Count) candidatos en LocalAppData\Temp, $(Tamano $total).$cobertura No se borró nada."
    } catch { NoDisponible temp 'Temporales antiguos' 'No se pudo revisar de forma segura la carpeta temporal local.' }
    try {
        $inicio = @(Get-CimInstance Win32_StartupCommand -OperationTimeoutSec 8 -ErrorAction Stop | ForEach-Object {
            [pscustomobject]@{ Nombre = $_.Name; Origen = $_.Location; Huella = (Huella "$($_.Location)|$($_.User)|$($_.Name)|$($_.Command)") }
        } | Sort-Object Huella -Unique)
        $referencia = @($anterior | Where-Object { $_.Id -eq 'inicio' -and $_.Estado -ne 'No disponible' } | Select-Object -First 1)
        $detalle = "$($inicio.Count) entradas visibles en Win32_StartupCommand. No incluye todos los mecanismos de inicio."
        if ($referencia.Count) {
            $altas = @($inicio | Where-Object { $_.Huella -notin $referencia[0].Datos.Huella })
            $bajas = @($referencia[0].Datos | Where-Object { $_ -and $_.Huella -notin $inicio.Huella })
            if ($altas.Count) { $detalle += "`nNuevas o modificadas: " + ($altas.Nombre -join ', ') }
            if ($bajas.Count) { $detalle += "`nYa no visibles o modificadas: " + ($bajas.Nombre -join ', ') }
        } else { $altas = @(); $detalle += ' Primera referencia.' }
        $h = Hallazgo inicio 'Inicio de Windows' 'Inventario' $detalle
        $h | Add-Member NoteProperty Datos $inicio
        $h | Add-Member NoteProperty Cambio ($altas.Count -gt 0)
        $h
    } catch { NoDisponible inicio 'Inicio de Windows' 'No se pudieron inventariar las entradas de inicio.' }
    try {
        $discos = @(Get-CimInstance -Namespace root/Microsoft/Windows/Storage MSFT_PhysicalDisk -OperationTimeoutSec 8 -ErrorAction Stop)
        if (!$discos.Count) { throw 'Sin discos' }
        foreach ($d in $discos) {
            $id = 'disco-' + (Huella "$($d.DeviceId)|$($d.UniqueId)")
            $nombre = 'Disco: ' + $d.FriendlyName
            if ($null -eq $d.HealthStatus -or $d.HealthStatus -notin 0,1,2) { NoDisponible $id $nombre 'El controlador no informó salud reconocible.'; continue }
            $ops = @($d.OperationalStatus | Where-Object { $null -ne $_ })
            $nivel = [int]$d.HealthStatus
            if ($ops | Where-Object { $_ -in 3,4,5,6,7,12,13,16 }) { $nivel = [Math]::Max(1,$nivel) }
            $estado = if ($nivel) { 'Alerta del controlador' } else { 'Sin alerta de salud reportada' }
            Hallazgo $id $nombre $estado "Salud: $($d.HealthStatus); códigos operativos: $($ops -join ', '). No equivale a una prueba SMART completa." $nivel
        }
    } catch { NoDisponible discos 'Salud de discos' 'La fuente de almacenamiento no respondió o no tiene permisos.' }
    $desde = (Get-Date).AddDays(-7)
    try {
        $sys = @(LeerEventos @{LogName='System'; Id=7,11,51,55,129,153,157; StartTime=$desde})
        $e = @($sys | Where-Object ProviderName -Match '^(disk|Ntfs|Microsoft-Windows-Ntfs|storahci|stornvme|storport|iaStor.*|Microsoft-Windows-Storage-Storport)$')
        $nivel = if ($e.Count) { 1 } else { 0 }
        $grupos = ($e | Group-Object ProviderName,Id | ForEach-Object { "$($_.Name): $($_.Count)" }) -join '; '
        $estado = if ($nivel) { 'Eventos de almacenamiento' } elseif ($sys.Count -ge 1000) { 'Parcial' } else { 'Sin coincidencias' }
        $detalle = if ($sys.Count -ge 1000) { ' Consulta limitada a 1.000 coincidencias de origen.' } else { '' }
        Hallazgo eventos-disco 'Alertas de almacenamiento' $estado "Últimos 7 días: $($e.Count) coincidencias en System. $grupos.$detalle" $nivel $e.Count
    } catch { NoDisponible eventos-disco 'Alertas de almacenamiento' 'No se pudo leer el registro System.' }
    try {
        $e = @(LeerEventos @{LogName='Application'; Id=1000,1002; ProviderName='Application Error','Application Hang'; StartTime=$desde})
        $g = @($e | Group-Object { $primera = $_.Properties | Select-Object -First 1; "$($_.Id) / $($primera.Value)" } | Where-Object Count -GE 2)
        $estado = if ($g.Count) { 'Fallos repetidos' } elseif ($e.Count -ge 1000) { 'Parcial' } else { 'Sin repeticiones observadas' }
        $det = ($g | ForEach-Object { "$($_.Name): $($_.Count)" }) -join '; '
        $cobertura = if ($e.Count -ge 1000) { ' Consulta limitada a 1.000 eventos.' } else { '' }
        $resumen = Hallazgo fallos 'Fallos de aplicaciones' $estado "Últimos 7 días: $($e.Count) eventos 1000/1002. $det.$cobertura"
        $resumen | Add-Member NoteProperty Completo ($e.Count -lt 1000)
        $resumen
        foreach ($x in $g) { Hallazgo ('fallo-' + (Huella $x.Name)) 'Fallo repetido' 'Repetido' "$($x.Name): $($x.Count) eventos en los últimos 7 días." 1 $x.Count }
    } catch { NoDisponible fallos 'Fallos de aplicaciones' 'No se pudo leer el registro Application.' }
    try {
        $si = New-Object -ComObject Microsoft.Update.SystemInfo -ErrorAction Stop
        if ($si.RebootRequired) { Hallazgo reinicio 'Reinicio' 'Pendiente según Windows Update' 'La aplicación no reinicia el equipo.' 1 }
        else { Hallazgo reinicio 'Reinicio' 'Sin reinicio pendiente según Windows Update' 'Esta fuente no cubre todos los instaladores.' }
    } catch { NoDisponible reinicio 'Reinicio' 'No se pudo consultar Windows Update SystemInfo.' }
    if ($SinConsultaActualizaciones) { NoDisponible update 'Windows Update' 'Consulta omitida en la prueba controlada.' }
    else {
        try {
            $session = New-Object -ComObject Microsoft.Update.Session -ErrorAction Stop
            $searcher = $session.CreateUpdateSearcher(); $searcher.Online = $false
            $resultado = $searcher.Search("IsInstalled=0 and IsHidden=0 and Type='Software'")
            if ($resultado.ResultCode -ne 2) { throw 'Resultado parcial' }
            $cantidad = $resultado.Updates.Count
            $estado = if ($cantidad) { 'Encontradas en caché' } else { 'Ninguna encontrada en caché' }
            Hallazgo update 'Windows Update' $estado "$cantidad actualizaciones de software visibles en la caché local. Puede estar desactualizada; confirma en Configuración." ([int]($cantidad -gt 0)) $cantidad
        } catch { NoDisponible update 'Windows Update' 'No se pudo consultar la caché local; confirma en Configuración.' }
    }
    try {
        $mp = Get-MpComputerStatus -ErrorAction Stop
        if ($null -eq $mp.RealTimeProtectionEnabled -or $null -eq $mp.AntivirusEnabled) { throw 'Sin datos' }
        $activa = $mp.RealTimeProtectionEnabled -and $mp.AntivirusEnabled
        $estado = if ($activa) { 'Protección en tiempo real activa' } else { 'Defender no confirma protección activa' }
        Hallazgo defender 'Microsoft Defender' $estado 'No verifica antivirus de terceros. Confirma los proveedores en Seguridad de Windows.' ([int](-not $activa))
    } catch { NoDisponible defender 'Microsoft Defender' 'No se pudo leer Defender. Confirma en Seguridad de Windows.' }
    try {
        $firewalls = @(Get-NetFirewallProfile -PolicyStore ActiveStore -ErrorAction Stop)
        if ($firewalls.Count -ne 3) { throw 'Resultado parcial' }
        $des = @($firewalls | Where-Object { $_.Enabled.ToString() -eq 'False' })
        $inc = @($firewalls | Where-Object { $_.Enabled.ToString() -notin 'True','False' })
        $estado = if ($des.Count) { 'Perfiles desactivados' } elseif ($inc.Count) { 'Parcial' } else { 'Perfiles habilitados' }
        Hallazgo firewall 'Firewall de Windows' $estado (($firewalls | ForEach-Object { "$($_.Name): $($_.Enabled)" }) -join '; ') ([int]($des.Count -gt 0)) $des.Count
    } catch { NoDisponible firewall 'Firewall de Windows' 'No se pudieron consultar los perfiles efectivos.' }
    try {
        $e = @(LeerEventos @{LogName='Microsoft-Windows-Backup'; ProviderName='Microsoft-Windows-Backup'; Id=4,5} 1)
        if (!$e.Count) { NoDisponible backup 'Copia de seguridad de Windows' 'Sin respaldo verificable en este registro. No se comprueban servicios externos ni restaurabilidad.' }
        elseif ($e[0].Id -eq 5) { Hallazgo backup 'Copia de seguridad de Windows' 'Último resultado: fallo' "$($e[0].TimeCreated), evento 5. No se comprueban servicios externos." 2 }
        else {
            $dias = ((Get-Date) - $e[0].TimeCreated).TotalDays
            $estado = if ($dias -gt 30) { 'Último éxito registrado hace más de 30 días' } else { 'Éxito registrado' }
            Hallazgo backup 'Copia de seguridad de Windows' $estado "$($e[0].TimeCreated), evento 4. No se comprueba restaurabilidad ni servicios externos." ([int]($dias -gt 30))
        }
    } catch { NoDisponible backup 'Copia de seguridad de Windows' 'Registro no accesible. No se comprueban proveedores externos.' }
    try {
        $e = @(LeerEventos @{LogName='Microsoft-Windows-FileHistory-Core/WHC'; ProviderName='Microsoft-Windows-FileHistory-Core'; Id=201,202,203; StartTime=$desde})
        if ($e.Count) { Hallazgo filehistory 'Historial de archivos' 'Incidencias registradas' "$($e.Count) eventos en 7 días; último: $($e[0].TimeCreated). No se verificó si fueron resueltos." 1 $e.Count }
        else { NoDisponible filehistory 'Historial de archivos' 'Sin incidencias coincidentes en 7 días, pero la fuente no confirma que haya una copia utilizable.' }
    } catch { NoDisponible filehistory 'Historial de archivos' 'Registro no accesible.' }
}
