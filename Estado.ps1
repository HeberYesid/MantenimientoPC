function Con-Exclusion($accion) {
    $clave = Huella ([IO.Path]::GetFullPath($script:Datos).ToUpperInvariant())
    $mutex = [Threading.Mutex]::new($false, "Global\MantenimientoPC-$clave")
    $adquirido = $false
    try {
        try { $adquirido = $mutex.WaitOne(1000) } catch [Threading.AbandonedMutexException] { $adquirido = $true }
        if (!$adquirido) { throw 'Otra revisión está en curso. Intenta nuevamente cuando termine.' }
        & $accion
    } finally {
        if ($adquirido) { $mutex.ReleaseMutex() }
        $mutex.Dispose()
    }
}
function Leer-Historial {
    $ruta = Join-Path $script:Datos 'historial.json'
    if (![IO.File]::Exists($ruta)) { return }
    try {
        $doc = ConvertFrom-Json ([IO.File]::ReadAllText($ruta, [Text.Encoding]::UTF8)) -ErrorAction Stop
        if ($doc.Version -ne 1 -or $null -eq $doc.Informes) { throw 'Formato desconocido' }
        $doc.Informes
    } catch { throw 'No se pudo leer el historial; se conserva sin sobrescribir. Revisa historial.json.' }
}
function Guardar-Historial($informes) {
    [IO.Directory]::CreateDirectory($script:Datos) | Out-Null
    $ruta = Join-Path $script:Datos 'historial.json'; $tmp = "$ruta.$([guid]::NewGuid()).tmp"
    try {
        $json = ConvertTo-Json -InputObject @{ Version=1; Informes=@($informes | Select-Object -First 64) } -Depth 9
        [IO.File]::WriteAllText($tmp,$json,[Text.UTF8Encoding]::new($false))
        if ([IO.File]::Exists($ruta)) { [IO.File]::Replace($tmp,$ruta,[NullString]::Value) } else { [IO.File]::Move($tmp,$ruta) }
    } finally { if ([IO.File]::Exists($tmp)) { [IO.File]::Delete($tmp) } }
}
function Ejecutar-Revision([string]$Tipo, [string]$Origen, [switch]$SinConsultaActualizaciones) {
    Con-Exclusion {
        $hist = @(Leer-Historial)
        $ahora = Get-Date
        $semana = @($hist | Where-Object Tipo -EQ 'Semanal')
        $mes = @($hist | Where-Object Tipo -EQ 'Mensual' | Select-Object -First 1)
        $nuevos = [Collections.Generic.List[object]]::new()
        if ($Tipo -eq 'Semanal') {
            $previo = @($semana | ForEach-Object { $_.Hallazgos })
            $h = @(Revisar-Semana $previo -SinConsultaActualizaciones:$SinConsultaActualizaciones)
            $avisos = @(Comparar $h $semana)
            $avisos += @($h | Where-Object { $_.Id -eq 'inicio' -and $_.Cambio })
            $nuevos.Add([pscustomobject]@{ Fecha=$ahora.ToString('o'); Tipo='Semanal'; Origen=$Origen; Hallazgos=$h; Avisos=$avisos })
            # Persistir la revisión semanal antes de empezar el inventario mensual.
            Guardar-Historial (@($nuevos.ToArray()) + $hist)
        }
        if ($Tipo -eq 'Mensual' -or ($Origen -eq 'Programada' -and (!$mes.Count -or ([datetimeoffset]$mes[0].Fecha).LocalDateTime.ToString('yyyy-MM') -ne $ahora.ToString('yyyy-MM')))) {
            $hallazgos = @(Revisar-Mes)
            $nuevos.Insert(0,[pscustomobject]@{ Fecha=$ahora.ToString('o'); Tipo='Mensual'; Origen=$Origen; Hallazgos=$hallazgos; Avisos=@() })
            Guardar-Historial (@($nuevos.ToArray()) + $hist)
        }
        $nuevos.ToArray()
    }
}

function Texto-Informe($informe) {
    $r = [Collections.Generic.List[string]]::new()
    $r.Add("$($informe.Tipo) · $($informe.Origen) · $(([datetimeoffset]$informe.Fecha).LocalDateTime.ToString('g'))")
    if ($informe.Tipo -eq 'Semanal') {
        if ($informe.Avisos.Count) { $r.Add("Avisos nuevos o empeorados ($($informe.Avisos.Count)): " + (($informe.Avisos | ForEach-Object { "$($_.Nombre): $($_.Estado)" }) -join '; ')) }
        else { $r.Add('Sin avisos nuevos o empeorados entre las señales disponibles.') }
    }
    foreach ($h in $informe.Hallazgos) { $r.Add("`r`n$($h.Nombre) — $($h.Estado)`r`n$($h.Detalle -replace '(?<!\r)\n',"`r`n")") }
    $r -join "`r`n"
}
