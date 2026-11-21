Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

function Mostrar-Aviso($informe) {
    $w = [Windows.Forms.Form]::new(); $w.Text = 'Mantenimiento PC — avisos nuevos o empeorados'
    $w.Size = [Drawing.Size]::new(560,280); $w.StartPosition = 'CenterScreen'; $w.TopMost = $true
    $w.Font = [Drawing.Font]::new('Segoe UI',10)
    $t = [Windows.Forms.TextBox]::new(); $t.Dock = 'Fill'; $t.Multiline = $true; $t.ReadOnly = $true; $t.ScrollBars = 'Vertical'
    $t.Text = (($informe.Avisos | ForEach-Object { "$($_.Nombre) — $($_.Estado)`r`n$($_.Detalle)`r`n" }) -join "`r`n") + "`r`nConsulta el historial para ver el informe completo. Este aviso se cierra tras 25 segundos."
    $b = [Windows.Forms.Button]::new(); $b.Text = '&Cerrar'; $b.Dock = 'Bottom'; $b.Height = 38
    $b.Add_Click({ $w.Close() }.GetNewClosure()); $w.AcceptButton = $b; $w.CancelButton = $b
    $w.Controls.Add($t); $w.Controls.Add($b)
    $timer = [Windows.Forms.Timer]::new(); $timer.Interval = 25000; $timer.Add_Tick({ $w.Close() }.GetNewClosure())
    try { $timer.Start(); $w.ShowDialog() | Out-Null } finally { $timer.Dispose(); $w.Dispose() }
}

function Boton($padre,[string]$texto) {
    $b = [Windows.Forms.Button]::new(); $b.Text = $texto; $b.AutoSize = $true
    $b.MinimumSize = [Drawing.Size]::new(0,34); $b.Padding = [Windows.Forms.Padding]::new(8,0,8,0)
    $padre.Controls.Add($b); $b
}
function Fila($padre) {
    $f = [Windows.Forms.FlowLayoutPanel]::new(); $f.Dock = 'Top'; $f.AutoSize = $true
    $f.Padding = [Windows.Forms.Padding]::new(8,4,8,4); $padre.Controls.Add($f); $f
}
function Texto-Lectura($padre,[string]$nombre) {
    $box = [Windows.Forms.TextBox]::new(); $box.Dock = 'Fill'; $box.Multiline = $true; $box.ReadOnly = $true
    $box.ScrollBars = 'Vertical'; $box.BackColor = [Drawing.SystemColors]::Window; $box.AccessibleName = $nombre
    $padre.Controls.Add($box); $box
}
function Etiqueta($padre,[string]$texto) {
    $l = [Windows.Forms.Label]::new(); $l.Text = $texto; $l.AutoSize = $true
    $l.Margin = [Windows.Forms.Padding]::new(6,10,6,3); $padre.Controls.Add($l)
}
function Mensaje-Error($mensaje) {
    if ($script:EnPruebaUI) { $script:ErrorPruebaUI = $mensaje; return }
    [Windows.Forms.MessageBox]::Show($script:Ventana,$mensaje,'Mantenimiento PC',0,16) | Out-Null
}
function Confirmar($mensaje, $titulo) {
    if ($script:EnPruebaUI) { return $script:ConfirmacionPruebaUI }
    [Windows.Forms.MessageBox]::Show($script:Ventana,$mensaje,$titulo,4,48,256) -eq 'Yes'
}

function Actualizar-ProgramaUI {
    $script:BotonPausa.Enabled = $false
    try {
        $t = Tarea-Propia
        if (!$t) { $script:EstadoPrograma.Text = "Sin tarea semanal instalada.`r`nGuarda un horario para activarla. La tarea se ejecuta en tu sesión, sin administrador."; return }
        $script:BotonPausa.Enabled = $true
        $script:BotonPausa.Text = if ($t.State -eq 'Disabled') { '&Reanudar' } else { '&Pausar' }
        $info = $t | Get-ScheduledTaskInfo -ErrorAction Stop
        $estado = switch ($t.State) { Disabled {'Pausada'} Running {'En ejecución'} Ready {'Activa'} default {"Estado de Windows: $($t.State)"} }
        $ultima = if ($info.LastRunTime.Year -gt 2000) { "$($info.LastRunTime) (código $($info.LastTaskResult))" } else { 'Sin ejecución registrada' }
        $proxima = if ($info.NextRunTime.Year -gt 2000 -and $t.State -ne 'Disabled') { "$($info.NextRunTime)" } else { 'No disponible' }
        $script:EstadoPrograma.Text = "$estado`r`nPróxima: $proxima`r`nÚltima: $ultima`r`nRevisión semanal y primer inventario de cada mes si aún no existe. No despierta el equipo ni borra archivos."
    } catch { $script:EstadoPrograma.Text = "No disponible: $($_.Exception.Message)" }
}
function Actualizar-HistorialUI {
    $script:SelectorHist.Items.Clear()
    try {
        $script:HistUI = @(Leer-Historial)
        foreach ($i in $script:HistUI) {
            $null = $script:SelectorHist.Items.Add("$(([datetimeoffset]$i.Fecha).LocalDateTime.ToString('g')) · $($i.Tipo) · $($i.Origen)")
        }
        if ($script:HistUI.Count) { $script:SelectorHist.SelectedIndex = 0 } else { $script:InformeBox.Text = 'Todavía no hay revisiones. Ejecuta una comprobación para crear el primer informe.' }
    } catch { $script:InformeBox.Text = $_.Exception.Message }
}
function Lanzar-Trabajo($codigo, $argumentos, $fin, $estado) {
    if ($script:Trabajo) { return }
    $p = [PowerShell]::Create()
    try {
        $null = $p.AddScript('param($dir,$datos,$codigo,$a)
            $ErrorActionPreference = "Stop"
            $script:Datos = $datos
            . "$dir\Revision.ps1"; . "$dir\Diagnostico.ps1"; . "$dir\Estado.ps1"
            if (!("ArchivosMpc" -as [type])) { Add-Type -Path "$dir\Archivos.cs" }
            & ([scriptblock]::Create($codigo)) @a').AddArgument($PSScriptRoot).AddArgument($script:Datos).AddArgument($codigo).AddArgument($argumentos)
        $script:Trabajo = @{ Motor=$p; Asincrono=$p.BeginInvoke(); Fin=$fin }
        foreach ($b in $script:TrabajoBotones) { $b.Enabled = $false }
        $script:Pie.Text = $estado
        $script:Pulso.Start()
    } catch { $p.Dispose(); Mensaje-Error $_.Exception.Message }
}

function Mostrar-Interfaz([string]$CarpetaPruebaUI) {
    [Windows.Forms.Application]::EnableVisualStyles()
    $script:EnPruebaUI = [bool]$CarpetaPruebaUI
    $script:RaizPruebaUI = $CarpetaPruebaUI
    $script:Trabajo = $null; $script:Candidatos = @(); $script:RaicesElegidas = @()
    $script:Ventana = [Windows.Forms.Form]::new(); $w = $script:Ventana
    $w.Text = 'Mantenimiento PC'; $w.StartPosition = 'CenterScreen'; $w.Size = [Drawing.Size]::new(1030,710)
    $w.MinimumSize = [Drawing.Size]::new(790,540); $w.Font = [Drawing.Font]::new('Segoe UI',10)
    $w.AutoScaleMode = 'Dpi'
    $cab = [Windows.Forms.Label]::new(); $cab.Dock = 'Top'; $cab.Height = 69
    $cab.Padding = [Windows.Forms.Padding]::new(15,11,8,0); $cab.Font = [Drawing.Font]::new('Segoe UI',17)
    $cab.Text = 'Mantenimiento PC'; $cab.BackColor = [Drawing.SystemColors]::Control
    $script:Pie = [Windows.Forms.Label]::new(); $script:Pie.Dock = 'Bottom'; $script:Pie.Height = 30; $script:Pie.Padding = [Windows.Forms.Padding]::new(10,5,0,0)
    $script:Pie.Text = 'Las revisiones son de solo lectura. Ninguna limpieza se ejecuta en segundo plano.'
    $tabs = [Windows.Forms.TabControl]::new(); $tabs.Dock = 'Fill'; $tabs.Padding = [Drawing.Point]::new(12,6)
    $w.Controls.Add($tabs); $w.Controls.Add($script:Pie); $w.Controls.Add($cab)
    $p = @{}; foreach ($nombre in 'Revisiones','Lentitud','Limpieza','Duplicados','Programa y herramientas') {
        $tab = [Windows.Forms.TabPage]::new($nombre); $tab.UseVisualStyleBackColor = $true
        $tabs.TabPages.Add($tab); $p[$nombre] = $tab
    }
    $script:InformeBox = Texto-Lectura $p.Revisiones 'Informe de revisión'; $script:InformeBox.TabIndex = 2
    $script:SelectorHist = [Windows.Forms.ComboBox]::new(); $script:SelectorHist.Dock = 'Top'; $script:SelectorHist.DropDownStyle = 'DropDownList'
    $script:SelectorHist.AccessibleName = 'Seleccionar informe del historial'; $script:SelectorHist.TabIndex = 1
    $p.Revisiones.Controls.Add($script:SelectorHist)
    $script:SelectorHist.Add_SelectedIndexChanged({ if ($script:SelectorHist.SelectedIndex -ge 0) { $script:InformeBox.Text = Texto-Informe $script:HistUI[$script:SelectorHist.SelectedIndex] } })
    $r = Fila $p.Revisiones; $r.TabIndex = 0
    $sem = Boton $r 'Revisar &semana'; $mes = Boton $r 'Revisar &mes'; $hist = Boton $r 'Recargar &historial'
    $sem.Add_Click({ Lanzar-Trabajo 'Ejecutar-Revision Semanal Manual' @() { Actualizar-HistorialUI } 'Consultando señales de Windows…' })
    $mes.Add_Click({ Lanzar-Trabajo 'Ejecutar-Revision Mensual Manual' @() { Actualizar-HistorialUI } 'Inventariando carpetas, aplicaciones y batería…' })
    $hist.Add_Click({ Actualizar-HistorialUI })

    $script:LentoBox = Texto-Lectura $p.Lentitud 'Resultados del diagnóstico'; $script:LentoBox.TabIndex = 1
    $script:LentoBox.Text = 'Si el equipo está lento ahora, inicia el muestreo y sigue usando el programa que notas lento. No se cierran procesos.'
    $r = Fila $p.Lentitud; $r.TabIndex = 0
    $medir = Boton $r '¿Por qué está &lento ahora?'
    $medir.Add_Click({ Lanzar-Trabajo 'Medir-Lentitud' @() { param($o) $script:LentoBox.Text = ($o -join "`r`n") } 'Midiendo CPU, memoria y discos; espera unos segundos…' })

    $script:ResultadoLimpieza = Texto-Lectura $p.Limpieza 'Criterios y resultado de limpieza'; $script:ResultadoLimpieza.Dock = 'Bottom'; $script:ResultadoLimpieza.Height = 118; $script:ResultadoLimpieza.TabIndex = 2
    $script:ResultadoLimpieza.Text = 'Solo se ofrecen archivos .tmp y .temp de más de 14 días directamente en la carpeta temporal local. Nada está seleccionado. La eliminación es permanente.'
    $script:ListaLimpieza = [Windows.Forms.CheckedListBox]::new(); $script:ListaLimpieza.Dock = 'Fill'; $script:ListaLimpieza.HorizontalScrollbar = $true
    $script:ListaLimpieza.AccessibleName = 'Vista previa: marca los temporales que quieres eliminar'; $script:ListaLimpieza.TabIndex = 1
    $p.Limpieza.Controls.Add($script:ListaLimpieza)
    $r = Fila $p.Limpieza; $r.TabIndex = 0
    $script:ListaLimpieza.BringToFront()
    $buscar = Boton $r 'Buscar &temporales'; $quitar = Boton $r '&Eliminar selección'; $script:BotonEliminar = $quitar; $quitar.Enabled = $false
    $buscar.Add_Click({
        Lanzar-Trabajo 'param($prueba) if ($prueba) { [ArchivosMpc]::Buscar($prueba,[datetime]::UtcNow.AddDays(-14)) } else { Temporales }' @($script:RaizPruebaUI) {
            param($o) $t = $o[0]; $script:Candidatos = @($t.Archivos); $script:ListaLimpieza.Items.Clear()
            foreach ($i in $script:Candidatos) { $null = $script:ListaLimpieza.Items.Add("$(Tamano $i.Bytes) | $($i.Modificado.ToLocalTime().ToString('g')) | $($i.Ruta)", $false) }
            $script:BotonEliminar.Enabled = $false
            $c = if ($t.Limitada -or $t.Inaccesibles) { " Vista parcial; inaccesibles: $($t.Inaccesibles)." } else { '' }
            $script:ResultadoLimpieza.Text = "$($script:Candidatos.Count) candidatos.$c Marca individualmente los que quieras eliminar."
        } 'Preparando una vista previa de solo lectura…'
    })
    $script:ListaLimpieza.Add_ItemCheck({
        param($sender,$e)
        $cuenta = $sender.CheckedIndices.Count
        if ($e.CurrentValue -eq 'Checked') { $cuenta-- }; if ($e.NewValue -eq 'Checked') { $cuenta++ }
        $script:BotonEliminar.Enabled = !$script:Trabajo -and $cuenta -gt 0
    })
    $quitar.Add_Click({
        $elegidos = @($script:ListaLimpieza.CheckedIndices | ForEach-Object { $script:Candidatos[$_] })
        if (!$elegidos.Count) { return }
        $total = 0L; foreach ($i in $elegidos) { $total += $i.Bytes }
        if (!(Confirmar "¿Eliminar permanentemente solo los $($elegidos.Count) archivos marcados en la vista previa ($(Tamano $total) de tamaño lógico)? No irán a la papelera." 'Confirmar eliminación')) { return }
        Lanzar-Trabajo 'param($lista,$prueba) $raiz = if ($prueba) { $prueba } else { Raiz-Temporal }; Quitar-Seleccion $raiz $lista' (@(,@($elegidos)) + @($script:RaizPruebaUI)) {
            param($o) $script:Candidatos = @(); $script:ListaLimpieza.Items.Clear(); $script:BotonEliminar.Enabled = $false
            $ok = @($o | Where-Object { $_ -like 'Eliminado y verificado:*' }).Count
            $script:ResultadoLimpieza.Text = "Eliminados y verificados: $ok de $($o.Count). El tamaño lógico no garantiza espacio liberado.`r`n" + ($o -join "`r`n")
        } 'Eliminando solo la selección confirmada y verificando cada resultado…'
    })

    $script:DupBox = Texto-Lectura $p.Duplicados 'Resultados de duplicados'; $script:DupBox.TabIndex = 2
    $script:DupBox.Text = 'Opcional, de solo lectura. Elige hasta tres carpetas locales. Compara contenido de archivos del mismo tamaño y no borra nada.'
    $script:DupRaices = [Windows.Forms.Label]::new(); $script:DupRaices.Dock = 'Top'; $script:DupRaices.Height = 58
    $script:DupRaices.Text = 'Ninguna carpeta elegida.'; $p.Duplicados.Controls.Add($script:DupRaices)
    $r = Fila $p.Duplicados; $r.TabIndex = 0
    $agregar = Boton $r '&Elegir carpeta'; $limpiar = Boton $r '&Quitar carpetas de la lista'; $dup = Boton $r '&Buscar duplicados'
    $script:BotonDup = $dup; $dup.Enabled = $false
    $agregar.Add_Click({
        if ($script:RaicesElegidas.Count -ge 3) { Mensaje-Error 'El límite es de tres carpetas.'; return }
        $d = [Windows.Forms.FolderBrowserDialog]::new(); $d.Description = 'Elige una carpeta local para comparar archivos'; $d.ShowNewFolderButton = $false
        try { if ($d.ShowDialog($script:Ventana) -eq 'OK' -and $d.SelectedPath -notin $script:RaicesElegidas) { $script:RaicesElegidas += $d.SelectedPath } } finally { $d.Dispose() }
        if ($script:RaicesElegidas.Count) { $script:DupRaices.Text = $script:RaicesElegidas -join "`r`n"; $script:BotonDup.Enabled = $true }
    })
    $limpiar.Add_Click({ $script:RaicesElegidas = @(); $script:DupRaices.Text = 'Ninguna carpeta elegida.'; $script:BotonDup.Enabled = $false })
    $dup.Add_Click({ Lanzar-Trabajo 'param($r) Buscar-Duplicados $r' (,@($script:RaicesElegidas)) { param($o) $script:DupBox.Text = ($o -join "`r`n") -replace '(?<!\r)\n',"`r`n" } 'Comparando únicamente archivos de las carpetas elegidas…' })

    $pag = $p['Programa y herramientas']
    $script:EstadoPrograma = Texto-Lectura $pag 'Estado de la tarea semanal'; $script:EstadoPrograma.TabIndex = 3
    $herr = Fila $pag; $herr.TabIndex = 2
    foreach ($h in 'Inicio','Aplicaciones','Windows Update','Seguridad','Copias','Optimizar unidades') {
        $b = Boton $herr $h; $b.Tag = $h
        $b.Add_Click({ param($sender,$e) try { Abrir-Herramienta $sender.Tag } catch { Mensaje-Error $_.Exception.Message } })
    }
    $r = Fila $pag; $r.TabIndex = 1
    $ac = Boton $r 'Crear acceso en &escritorio'; $des = Boton $r '&Desinstalar integración'
    $ac.Add_Click({ try { Crear-Acceso; $script:Pie.Text = 'Acceso directo disponible en el escritorio.' } catch { Mensaje-Error $_.Exception.Message } })
    $des.Add_Click({
        if (Confirmar '¿Quitar el acceso directo y la tarea de esta carpeta? El historial se conserva.' 'Desinstalar integración') {
            try { Quitar-Integracion; Actualizar-ProgramaUI; $script:Pie.Text = 'Acceso directo y tarea retirados. Historial conservado.' } catch { Mensaje-Error $_.Exception.Message }
        }
    })
    $r = Fila $pag; $r.TabIndex = 0
    Etiqueta $r '&Día semanal:'
    $script:DiaUI = [Windows.Forms.ComboBox]::new(); $script:DiaUI.DropDownStyle = 'DropDownList'; $script:DiaUI.Width = 117; $script:DiaUI.AccessibleName = 'Día semanal'
    $script:DiaUI.Items.AddRange(@('Domingo','Lunes','Martes','Miércoles','Jueves','Viernes','Sábado')); $script:DiaUI.SelectedIndex = 0; $r.Controls.Add($script:DiaUI)
    Etiqueta $r 'H&ora local:'
    $script:HoraUI = [Windows.Forms.DateTimePicker]::new(); $script:HoraUI.Format = 'Custom'; $script:HoraUI.CustomFormat = 'HH:mm'; $script:HoraUI.ShowUpDown = $true
    $script:HoraUI.Value = [datetime]::Today.AddHours(18); $script:HoraUI.Width = 82; $script:HoraUI.AccessibleName = 'Hora local'; $r.Controls.Add($script:HoraUI)
    $g = Boton $r '&Guardar horario'; $script:BotonPausa = Boton $r '&Pausar'; $ref = Boton $r '&Ver estado'
    $g.Add_Click({ try { Guardar-Programa ([DayOfWeek]$script:DiaUI.SelectedIndex) $script:HoraUI.Value; Actualizar-ProgramaUI } catch { Mensaje-Error $_.Exception.Message } })
    $script:BotonPausa.Add_Click({ try { Cambiar-Pausa; Actualizar-ProgramaUI } catch { Mensaje-Error $_.Exception.Message } })
    $ref.Add_Click({ Actualizar-ProgramaUI })
    try {
        $t = Tarea-Propia
        if ($t -and $t.Triggers[0].DaysOfWeek) {
            $script:DiaUI.SelectedIndex = [int][math]::Log([double]$t.Triggers[0].DaysOfWeek,2)
            $script:HoraUI.Value = [datetime]::Today.Add(([datetime]$t.Triggers[0].StartBoundary).TimeOfDay)
        }
    } catch { }

    $script:TrabajoBotones = @($sem,$mes,$medir,$buscar,$quitar,$agregar,$limpiar,$dup)
    $script:Pulso = [Windows.Forms.Timer]::new(); $script:Pulso.Interval = 180
    $script:Pulso.Add_Tick({
        if (!$script:Trabajo -or !$script:Trabajo.Asincrono.IsCompleted) { return }
        $script:Pulso.Stop(); $j = $script:Trabajo; $script:Trabajo = $null
        foreach ($b in $script:TrabajoBotones) { $b.Enabled = $true }
        $script:BotonEliminar.Enabled = $script:ListaLimpieza.CheckedIndices.Count -gt 0
        $script:BotonDup.Enabled = $script:RaicesElegidas.Count -gt 0
        try { $o = @($j.Motor.EndInvoke($j.Asincrono)); & $j.Fin $o; $script:Pie.Text = 'Operación terminada. Consulta el resultado en esta pestaña.' }
        catch { $script:Pie.Text = 'Operación no completada.'; Mensaje-Error $_.Exception.GetBaseException().Message }
        finally { $j.Motor.Dispose() }
    })
    $w.Add_FormClosing({ param($s,$e) if ($script:Trabajo) { $e.Cancel = $true; $script:Pie.Text = 'Espera a que termine la operación antes de cerrar.' } })
    Actualizar-HistorialUI; Actualizar-ProgramaUI
    $tmp = $null
    if ($script:EnPruebaUI) {
        $script:ErrorPruebaUI = $null; $script:FasePruebaUI = 0
        $script:CronometroPruebaUI = [Diagnostics.Stopwatch]::StartNew()
        $script:ControlesPruebaUI = @{ Revisar=$mes; Buscar=$buscar; Quitar=$quitar; Tabs=$tabs; Pagina=$p.Limpieza }
        $tmp = [Windows.Forms.Timer]::new(); $tmp.Interval = 200
        $tmp.Add_Tick({
            try {
                if ($script:ErrorPruebaUI) { throw $script:ErrorPruebaUI }
                if ($script:CronometroPruebaUI.Elapsed.TotalSeconds -ge 45) { throw 'La interfaz excedió el límite de prueba.' }
                if ($script:Trabajo) { return }
                $c = $script:ControlesPruebaUI
                $objetivo = Join-Path $script:RaizPruebaUI 'elegir.tmp'
                switch ($script:FasePruebaUI++) {
                    0 { $c.Revisar.PerformClick() }
                    1 {
                        if ($script:HistUI.Count -ne 3 -or $script:InformeBox.Text -notlike 'Mensual*') { throw 'La revisión no llegó al historial visible.' }
                        $c.Tabs.SelectedTab = $c.Pagina; $c.Buscar.PerformClick()
                    }
                    2 {
                        if ($script:ListaLimpieza.Items.Count -ne 2 -or $script:ListaLimpieza.CheckedIndices.Count -or $c.Quitar.Enabled) { throw 'Vista previa inesperada o selección automática.' }
                        for ($i=0; $i -lt $script:Candidatos.Count; $i++) { if ($script:Candidatos[$i].Ruta -eq $objetivo) { $script:ListaLimpieza.SetItemChecked($i,$true) } }
                        if (!$c.Quitar.Enabled) { throw 'No se habilitó el botón al marcar un candidato.' }
                        $script:ConfirmacionPruebaUI = $false; $c.Quitar.PerformClick()
                        if ($script:Trabajo -or ![IO.File]::Exists($objetivo)) { throw 'Cancelar la confirmación no fue inocuo.' }
                        $script:ConfirmacionPruebaUI = $true; $c.Quitar.PerformClick()
                    }
                    3 {
                        if ($script:ResultadoLimpieza.Text -notlike 'Eliminados y verificados: 1 de 1.*' -or [IO.File]::Exists($objetivo) -or
                            ![IO.File]::Exists((Join-Path $script:RaizPruebaUI 'conservar.tmp'))) { throw 'Resultado de limpieza inesperado.' }
                        $script:Ventana.Close()
                    }
                }
            } catch {
                $script:ErrorPruebaUI = $_.Exception.GetBaseException().Message
                if ($script:Trabajo) {
                    $j = $script:Trabajo; $script:Trabajo = $null
                    $script:Pulso.Stop(); $j.Motor.Stop(); $j.Motor.Dispose()
                }
                $script:Ventana.Close()
            }
        }); $tmp.Start()
    }
    try { $w.ShowDialog() | Out-Null }
    finally { if ($tmp) { $tmp.Dispose() }; $script:Pulso.Dispose(); $w.Dispose() }
    $script:EnPruebaUI = $false
    if ($CarpetaPruebaUI -and $script:ErrorPruebaUI) { throw $script:ErrorPruebaUI }
}
