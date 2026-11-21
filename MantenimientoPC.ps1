#requires -Version 5.1
param(
    [ValidateSet('Interfaz','Semanal','Mensual','Programada','Instalar','Desinstalar')][string]$Modo = 'Interfaz',
    [DayOfWeek]$Dia = 'Sunday',
    [ValidatePattern('^(?:[01][0-9]|2[0-3]):[0-5][0-9]$')][string]$Hora = '18:00'
)
$ErrorActionPreference = 'Stop'
$script:Datos = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'MantenimientoPC'
. "$PSScriptRoot\Revision.ps1"
. "$PSScriptRoot\Diagnostico.ps1"
. "$PSScriptRoot\Estado.ps1"
. "$PSScriptRoot\Integracion.ps1"
try {
    switch ($Modo) {
        'Instalar' {
            $acceso = Acceso-Propio (Ruta-Acceso)
            $null = Tarea-Propia
            $creado = $false
            try {
                if (!$acceso) { Crear-Acceso; $creado = $true }
                Guardar-Programa $Dia ([datetime]::Today.Add([timespan]::Parse($Hora)))
            } catch {
                if ($creado -and (Acceso-Propio (Ruta-Acceso))) { [IO.File]::Delete((Ruta-Acceso)) }
                throw
            }
            'Acceso directo y horario registrados para este usuario. Abre Mantenimiento PC desde el escritorio.'
        }
        'Desinstalar' { Quitar-Integracion; 'Acceso directo y tarea retirados. Se conserva el historial local.' }
        'Interfaz' { . "$PSScriptRoot\Interfaz.ps1"; Mostrar-Interfaz }
        default {
            Add-Type -Path "$PSScriptRoot\Archivos.cs"
            if ($Modo -eq 'Programada') {
                $informes = @(Ejecutar-Revision Semanal Programada)
                $semanal = $informes | Where-Object Tipo -EQ 'Semanal' | Select-Object -First 1
                if ($semanal.Avisos.Count) { . "$PSScriptRoot\Interfaz.ps1"; Mostrar-Aviso $semanal }
            } else {
                Ejecutar-Revision $Modo Manual | ForEach-Object { Texto-Informe $_ }
            }
        }
    }
} catch {
    if ($Modo -eq 'Interfaz') {
        Add-Type -AssemblyName System.Windows.Forms
        [Windows.Forms.MessageBox]::Show($_.Exception.Message,'Mantenimiento PC',0,16) | Out-Null
    } else { [Console]::Error.WriteLine($_.Exception.Message) }
    exit 1
}
