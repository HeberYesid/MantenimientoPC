function Inventariar-Archivos([string[]]$Raices) {
    $archivos = [Collections.Generic.List[object]]::new()
    $totales = @{}; $omitidos = 0; $limite = $false; $vistos = 0
    $reloj = [Diagnostics.Stopwatch]::StartNew()
    $pendientes = [Collections.Generic.Stack[object]]::new()
    $visitadas = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($r in $Raices) {
        try {
            $ruta = [IO.Path]::GetFullPath($r).TrimEnd('\'); $unidad = [IO.Path]::GetPathRoot($ruta)
            if ($unidad.Length -ne 3 -or $unidad[1] -ne ':' -or $ruta.Length -le $unidad.Length -or
                ([IO.DriveInfo]::new($unidad)).DriveType -ne 'Fixed') { throw 'Elige una carpeta en una unidad fija.' }
            $a = [IO.DirectoryInfo]::new($ruta)
            while ($a) {
                if (!$a.Exists -or ($a.Attributes -band (1024 -bor 4096 -bor 0x40000 -bor 0x400000))) { throw 'Carpeta no accesible o enlazada.' }
                $a = $a.Parent
            }
            $pendientes.Push(@{ Ruta=$ruta; Grupo=$null })
        } catch { $omitidos++ }
    }
    $validas = $pendientes.Count
    while ($pendientes.Count) {
        if ($vistos -ge 30000 -or $reloj.Elapsed.TotalSeconds -ge 12) { $limite = $true; break }
        $dir = $pendientes.Pop()
        if (!$visitadas.Add($dir.Ruta)) { continue }
        try {
            $info = [IO.DirectoryInfo]::new($dir.Ruta)
            if (!$info.Exists -or ($info.Attributes -band (1024 -bor 4096 -bor 0x40000 -bor 0x400000))) { $omitidos++; continue }
            foreach ($e in $info.EnumerateFileSystemInfos()) {
                if (++$vistos -gt 30000 -or $reloj.Elapsed.TotalSeconds -ge 12) { $limite = $true; break }
                if ($e.Attributes -band (1024 -bor 4096 -bor 0x40000 -bor 0x400000)) { $omitidos++; continue }
                if ($e -is [IO.DirectoryInfo]) {
                    $grupo = if ($dir.Grupo) { $dir.Grupo } else { $e.FullName }
                    $pendientes.Push(@{ Ruta=$e.FullName; Grupo=$grupo })
                } else {
                    $bytes = $e.Length; $archivos.Add([pscustomobject]@{ Ruta=$e.FullName; Bytes=$bytes; Modificado=$e.LastWriteTimeUtc })
                    if ($dir.Grupo) { $totales[$dir.Grupo] += $bytes }
                }
            }
        } catch { $omitidos++ }
    }
    [pscustomobject]@{ Archivos=$archivos; Carpetas=$totales; Parcial=($limite -or $omitidos -gt 0); Omitidos=$omitidos; Vistas=$validas }
}

function Revisar-Mes {
    try {
        $raices = @(foreach ($f in 'DesktopDirectory','MyDocuments','MyPictures','MyMusic','MyVideos') { [Environment]::GetFolderPath($f) }
            Join-Path ([Environment]::GetFolderPath('UserProfile')) 'Downloads') | Where-Object { $_ -and [IO.Directory]::Exists($_) } | Select-Object -Unique
        $i = Inventariar-Archivos $raices
        if (!$i.Vistas) { throw 'No hay carpetas accesibles' }
        $estado = if ($i.Parcial) { 'Parcial' } else { 'Medido' }
        $info = "Carpetas consultadas: $($i.Vistas); entradas omitidas: $($i.Omitidos). Tamaños lógicos, no espacio recuperable."
        $f = @($i.Archivos | Where-Object Bytes -GE 100MB | Sort-Object Bytes -Descending | Select-Object -First 20)
        $d = @($i.Carpetas.GetEnumerator() | Where-Object Value -GE 100MB | Sort-Object Value -Descending | Select-Object -First 20)
        $detalle = if ($f.Count) { ($f | ForEach-Object { "$(Tamano $_.Bytes)  $($_.Ruta)" }) -join "`n" } else { 'Sin coincidencias observadas de 100 MiB o más.' }
        Hallazgo grandes-archivos 'Archivos grandes' $estado "$info`n$detalle"
        $detalle = if ($d.Count) { ($d | ForEach-Object { "$(Tamano $_.Value)  $($_.Key)" }) -join "`n" } else { 'Sin coincidencias observadas de 100 MiB o más.' }
        Hallazgo grandes-carpetas 'Carpetas grandes' $estado "$info`nSubcarpetas directas de las ubicaciones consultadas:`n$detalle"
    } catch {
        NoDisponible grandes-archivos 'Archivos grandes' 'No se pudieron revisar las carpetas personales locales.'
        NoDisponible grandes-carpetas 'Carpetas grandes' 'No se pudieron revisar las carpetas personales locales.'
    }
    try {
        $apps = @( @(foreach ($scope in 'HKLM','HKCU') {
            foreach ($rama in 'SOFTWARE','SOFTWARE\Wow6432Node') {
                $p = "${scope}:\$rama\Microsoft\Windows\CurrentVersion\Uninstall"
                if (Test-Path -LiteralPath $p -ErrorAction Stop) {
                    foreach ($item in Get-ChildItem -LiteralPath $p -ErrorAction Stop) {
                        $a = Get-ItemProperty -LiteralPath $item.PSPath -ErrorAction Stop
                        if ($a.DisplayName -and $a.SystemComponent -ne 1) { "$($a.DisplayName) $($a.DisplayVersion)".Trim() }
                    }
                }
            }
        }) | Sort-Object -Unique)
        Hallazgo apps 'Aplicaciones instaladas' 'Inventario parcial' "$($apps.Count) entradas clásicas visibles. La lista no incluye todas las apps de Microsoft Store.`n$($apps -join "`n")"
    } catch { NoDisponible apps 'Aplicaciones instaladas' 'No se pudo completar la lectura del inventario clásico.' }
    try {
        $b = @(Get-CimInstance Win32_Battery -OperationTimeoutSec 8 -ErrorAction Stop)
        if (!$b.Count) { NoDisponible bateria 'Batería' 'Windows no informa ninguna batería mediante Win32_Battery.' }
        else {
            $texto = @($b | ForEach-Object {
                if ($null -ne $_.EstimatedChargeRemaining -and $_.EstimatedChargeRemaining -le 100) { "$($_.Name): carga $($_.EstimatedChargeRemaining) %." }
                else { "$($_.Name): carga no disponible." }
            })
            try {
                $d = @(Get-CimInstance -Namespace root/WMI BatteryStaticData -OperationTimeoutSec 6 -ErrorAction Stop)
                $f = @(Get-CimInstance -Namespace root/WMI BatteryFullChargedCapacity -OperationTimeoutSec 6 -ErrorAction Stop)
                $salud = @(foreach ($x in $d) {
                    $y = $f | Where-Object InstanceName -EQ $x.InstanceName | Select-Object -First 1
                    if ($x.DesignedCapacity -gt 0 -and $x.DesignedCapacity -lt 4294967295 -and $y.FullChargedCapacity -gt 0 -and $y.FullChargedCapacity -lt 4294967295) {
                        '{0} / {1} mWh ({2:N0} % de capacidad de diseño).' -f $y.FullChargedCapacity,$x.DesignedCapacity,(100*$y.FullChargedCapacity/$x.DesignedCapacity)
                    }
                })
            } catch { $salud = @() }
            $texto += if ($salud.Count) { $salud } else { 'Capacidad de diseño/carga completa: no disponible.' }
            $estado = if ($salud.Count -ne $b.Count -or ($b | Where-Object { $null -eq $_.EstimatedChargeRemaining -or $_.EstimatedChargeRemaining -gt 100 })) { 'Parcial' } else { 'Medido' }
            Hallazgo bateria 'Batería' $estado ($texto -join "`n")
        }
    } catch { NoDisponible bateria 'Batería' 'No se pudo consultar la batería.' }
}

function Buscar-Duplicados([string[]]$Raices) {
    $i = Inventariar-Archivos $Raices
    if (!$i.Vistas) { return 'No disponible: no se pudo abrir ninguna carpeta elegida de forma segura.' }
    $grupos = @{}; $bytes = 0L; $n = 0; $parcial = $i.Parcial
    $reloj = [Diagnostics.Stopwatch]::StartNew()
    :grupos foreach ($g in ($i.Archivos | Where-Object Bytes -GT 0 | Group-Object Bytes | Where-Object Count -GT 1)) {
        foreach ($f in $g.Group) {
            if ($reloj.Elapsed.TotalSeconds -ge 10 -or $n -ge 200 -or $bytes -ge 512MB) { $parcial = $true; break grupos }
            if ($f.Bytes -gt 64MB -or ($bytes + $f.Bytes -gt 512MB)) { $parcial = $true; continue }
            $n++; $bytes += $f.Bytes
            try {
                $huella = [ArchivosMpc]::HashLectura($Raices, $f.Ruta, $f.Bytes, $f.Modificado)
                if (!$grupos.ContainsKey($huella)) { $grupos[$huella] = [Collections.Generic.List[string]]::new() }
                $grupos[$huella].Add($f.Ruta)
            } catch { $parcial = $true }
        }
    }
    $dupes = @($grupos.Values | Where-Object Count -GT 1)
    $detalle = if ($dupes.Count) { ($dupes | ForEach-Object { "`nGrupo SHA-256:`n" + ($_ -join "`n") }) -join "`n" } else { 'Sin duplicados observados dentro del alcance analizado.' }
    $alcance = if ($parcial) { 'Resultado parcial: hubo exclusiones, archivos inaccesibles o límites alcanzados.' } else { 'Se analizaron los archivos no vacíos de tamaños coincidentes.' }
    "$alcance Ningún archivo fue borrado. No se guarda este resultado.`n$detalle"
}

function Medir-Lentitud([int]$Muestras = 6, [int]$PausaMs = 1800) {
    $reloj = [Diagnostics.Stopwatch]::StartNew()
    $m = @(for ($i = 0; $i -lt $Muestras; $i++) {
        $cpu = $null; $ram = $null; $discos = @(); $proc = @()
        try { $x = Get-CimInstance Win32_PerfFormattedData_PerfOS_Processor -Filter "Name='_Total'" -OperationTimeoutSec 5 -ErrorAction Stop; if ($null -ne $x.PercentProcessorTime) { $cpu = [double]$x.PercentProcessorTime } } catch {}
        try { $x = Get-CimInstance Win32_OperatingSystem -OperationTimeoutSec 5 -ErrorAction Stop; if ($x.TotalVisibleMemorySize -gt 0 -and $null -ne $x.FreePhysicalMemory) { $ram = 100 * (1 - $x.FreePhysicalMemory / $x.TotalVisibleMemorySize) } } catch {}
        try { $discos = @(Get-CimInstance Win32_PerfFormattedData_PerfDisk_PhysicalDisk -OperationTimeoutSec 5 -ErrorAction Stop | Where-Object { $_.Name -ne '_Total' -and $null -ne $_.PercentIdleTime }) } catch {}
        try { $proc = @(Get-CimInstance Win32_PerfFormattedData_PerfProc_Process -OperationTimeoutSec 5 -ErrorAction Stop | Where-Object { $_.IDProcess -gt 0 -and $_.Name -ne '_Total' }) } catch {}
        [pscustomobject]@{ CPU=$cpu; RAM=$ram; Discos=$discos; Procesos=$proc }
        if ($i -lt $Muestras-1) { Start-Sleep -Milliseconds $PausaMs }
    })
    "Ventana observada: $([math]::Round($reloj.Elapsed.TotalSeconds,1)) s, $Muestras muestras. Los programas coinciden en el tiempo; no prueban la causa. No se cerró nada.`n"
    foreach ($tipo in 'CPU','RAM','Disco') {
        $datos = @(foreach ($s in $m) {
            $prop = switch ($tipo) { CPU {'PercentProcessorTime'} RAM {'WorkingSetPrivate'} Disco {'IODataBytesPersec'} }
            $v = switch ($tipo) {
                CPU { $s.CPU }
                RAM { $s.RAM }
                Disco { if ($s.Discos.Count) { ($s.Discos | ForEach-Object { [Math]::Max(0,100-[double]$_.PercentIdleTime) } | Measure-Object -Maximum).Maximum } }
            }
            if ($null -ne $v) {
                $top = @($s.Procesos | Where-Object { [double]($_.$prop) -gt 0 } | Sort-Object -Property @{Expression={ [double]($_.$prop) }} -Descending | Select-Object -First 3)
                $detalle = ($top | ForEach-Object {
                    $nombre = "$($_.Name) (PID $($_.IDProcess))"
                    switch ($tipo) {
                        CPU { '{0}: {1:N1} % del equipo' -f $nombre, ([double]$_.$prop/[Environment]::ProcessorCount) }
                        RAM { "$nombre`: $(Tamano $_.$prop) privados residentes" }
                        Disco { "$nombre`: $(Tamano $_.$prop)/s de E/S total (no solo disco)" }
                    }
                }) -join '; '
                $d = if ($tipo -eq 'Disco') { ' [' + (($s.Discos | ForEach-Object { "$($_.Name): $([Math]::Max(0,100-[double]$_.PercentIdleTime)) % activo, cola $($_.CurrentDiskQueueLength)" }) -join '; ') + ']' } else { '' }
                [pscustomobject]@{ Valor=[double]$v; Detalle=$detalle; Discos=$d }
            }
        })
        if (!$datos.Count) { "$tipo`: No disponible.`n"; continue }
        $umbral = if ($tipo -eq 'CPU') { 85 } else { 90 }
        $altas = @($datos | Where-Object Valor -GE $umbral)
        $c = if ($altas.Count -ge [Math]::Max(2,[Math]::Ceiling($Muestras/2))) { 'Saturación sostenida según el umbral' }
             elseif ($altas.Count) { 'Picos observados' } elseif ($datos.Count -ne $Muestras) { 'Sin saturación en muestras disponibles (parcial)' } else { 'Sin saturación observada' }
        "${tipo}: $c. Muestras disponibles: $($datos.Count)/$Muestras; a partir de $umbral %: $($altas.Count)."
        foreach ($v in $datos) {
            $detalle = if ($v.Detalle) { $v.Detalle } else { 'programas coincidentes: datos no disponibles o actividad no medible' }
            '  {0:N1} %{1} — {2}' -f $v.Valor,$v.Discos,$detalle
        }
        ''
    }
}
