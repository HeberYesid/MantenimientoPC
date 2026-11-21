# Mantenimiento PC

Aplicación local para Windows 10 y 11. Revisa señales del equipo, guarda un historial y avisa cuando aparece o empeora un problema. No instala un servicio, no requiere permisos de administrador ni se queda activa cuando cierras la ventana. La revisión programada no elimina archivos ni cambia la configuración de Windows.

## Instalar

1. Conserva todos los archivos del proyecto juntos en una carpeta estable de tu usuario. No muevas ni borres esa carpeta mientras la tarea esté instalada.
2. Abre **Windows PowerShell** (5.1, sin «Ejecutar como administrador») en la carpeta del proyecto. Para probar primero sin instalar nada, ejecuta:

   ```powershell
   powershell.exe -NoProfile -STA -File .\MantenimientoPC.ps1
   ```

3. Para crear el acceso **Mantenimiento PC** en el escritorio y programar la revisión semanal, ejecuta:

   ```powershell
   powershell.exe -NoProfile -STA -File .\MantenimientoPC.ps1 -Modo Instalar
   ```

   El horario inicial es **domingo a las 18:00**, hora local. También puedes pasar, por ejemplo, `-Dia Wednesday -Hora 19:30` o configurarlo desde la interfaz. Si Windows o tu organización bloquean los scripts o el Programador de tareas, no cambies sus políticas para forzar esta instalación. La salida indicará el problema.

No necesita Python, paquetes externos ni internet. Windows PowerShell compila el auxiliar de archivos con .NET Framework al iniciar la primera operación que lo necesita. El acceso directo y la tarea apuntan a la carpeta desde la que se instalaron. Si ya existe un acceso o una tarea del mismo nombre apuntando a otra carpeta, la aplicación no los sustituye.

## Usar

| Pestaña | Para qué sirve |
| --- | --- |
| **Revisiones** | **Revisar semana** consulta el espacio de unidades fijas, los temporales elegibles, las entradas visibles de inicio, la salud de los discos, los eventos de almacenamiento y los fallos repetidos de aplicaciones. También consulta las actualizaciones en caché, el reinicio pendiente según Windows Update, Defender, el firewall y los registros de copias. **Revisar mes** inventaría archivos y subcarpetas grandes, aplicaciones clásicas y batería. Selecciona un informe en el desplegable para ver el historial. |
| **Lentitud** | Pulsa **¿Por qué está lento ahora?** mientras ocurre el problema. Toma seis muestras de CPU, RAM y actividad de discos y muestra, por muestra, los programas con mayor uso coincidente. CPU usa un umbral de 85 %; RAM y disco, 90 %. Se marca como sostenida cuando se supera o alcanza el umbral en al menos la mitad de las muestras previstas. La E/S de un programa incluye más que disco; la coincidencia no demuestra la causa. No se cierran aplicaciones. |
| **Limpieza** | **Buscar temporales** muestra ruta, fecha y tamaño sin seleccionar nada. Marca solo los archivos que quieras quitar, pulsa **Eliminar selección** y confirma. La eliminación es permanente y no pasa por la papelera. El resultado distingue lo eliminado y verificado de lo omitido o no verificable. El tamaño lógico no equivale necesariamente al espacio recuperado. |
| **Duplicados** | Elige hasta tres carpetas locales y pulsa **Buscar duplicados**. Se agrupan archivos de igual tamaño y contenido mediante SHA-256. No se borra nada ni se guarda el resultado. Se omiten archivos vacíos, enlaces y archivos no disponibles localmente; se compara un máximo de 200 archivos, 64 MiB por archivo y 512 MiB en total. Si se alcanza un límite o se omiten entradas, el resultado se marca como parcial. |
| **Programa y herramientas** | Cambia el día y la hora, pausa o reanuda sin borrar el historial, o retira la integración. Los accesos a Inicio, Aplicaciones, Windows Update, Seguridad, Historial de archivos y Optimizar unidades abren herramientas de Windows; no aplican cambios por sí mismos. |

La tarea se ejecuta solo en la sesión del usuario, no despierta el equipo y tiene un límite de dos minutos. Si el equipo no está disponible a la hora elegida, Windows puede diferir la ejecución; consulta la última ejecución en la app. La primera ejecución semanal programada de cada mes genera también el inventario mensual si todavía no existe. Las alertas de la tarea aparecen en una ventana que se cierra a los 25 segundos; puedes leerlas después en el historial. La primera revisión establece una referencia de inicio y puede avisar de problemas ya presentes. Se repiten avisos solo cuando una señal es nueva o empeora; no se considera que un problema se resolvió solo porque la fuente dejó de responder.

### Alcance y límites

- **Temporales:** solo `.tmp` y `.temp` creados y modificados hace al menos 14 días, directamente en `AppData\Local\Temp` del usuario y en NTFS local. No se recorren subcarpetas, datos personales, Descargas, papelera ni almacenes de cookies; también se excluyen nombres que contienen `cookie`, archivos ocultos o del sistema, sin conexión, enlaces duros, uniones y otros puntos de redirección. Antes de eliminar, se vuelve a comprobar la identidad y elegibilidad del archivo; si cambió o está abierto, se omite. No se buscan temporales en carpetas del sistema ni se ofrece borrar duplicados, archivos grandes o aplicaciones.
- **Inventario mensual:** revisa ubicaciones personales locales estándar (Escritorio, Documentos, Imágenes, Música, Vídeos y `Downloads` si son visibles), no toda la unidad. Lista hasta 20 archivos y 20 subcarpetas principales de al menos 100 MiB. Un límite de 30.000 entradas o unos 12 segundos evita inventarios extensos. El tamaño de carpetas es la suma lógica observada. La lista de apps de registro no cubre todas las de Microsoft Store. Las capacidades de batería se muestran únicamente si el controlador las publica.
- **Datos de Windows:** «No disponible» o «Parcial» no significan que todo esté bien. La salud del disco no sustituye a una prueba SMART completa. La consulta de actualizaciones usa solo la caché local y no instala nada; confirma en Windows Update. No se comprueban antivirus de terceros, copias externas ni la posibilidad de restaurar. El Historial de archivos puede mostrar incidentes, pero la ausencia de ellos no confirma que haya una copia.
- **Cambios que generan avisos:** el espacio avisa al bajar de 12 % o 5 GiB y empeora al bajar de 5 % o 2 GiB; no avisa por cada variación dentro de la misma franja. Para eventos de almacenamiento y fallos repetidos, se avisa cuando aparecen o aumenta el recuento en la ventana de siete días. En el inicio, se avisa por entradas nuevas o modificadas; las bajas se muestran solo en el informe.
- **Privacidad:** se guardan hasta 64 informes en `%LOCALAPPDATA%\MantenimientoPC\historial.json` (incluidas rutas de archivos grandes e inventario de apps). No se suben datos. El diagnóstico en vivo, la vista previa de limpieza y los resultados de duplicados no se guardan. No se limpia el registro, no se libera RAM, no se instalan controladores y no se reinicia el equipo.

## Pausar o desinstalar

Para conservar la tarea pero detener la programación, abre **Programa y herramientas → Pausar**. Para retirar el acceso y la tarea de esta carpeta, usa **Desinstalar integración** en la misma pestaña o ejecuta:

```powershell
powershell.exe -NoProfile -STA -File .\MantenimientoPC.ps1 -Modo Desinstalar
```

Si la tarea está en curso, espera a que termine. Tras retirar la integración, puedes borrar manualmente la carpeta del proyecto. El historial se conserva; si no lo quieres, cierra la aplicación y elimina manualmente `%LOCALAPPDATA%\MantenimientoPC`. La app no borra archivos de un directorio de instalación ni el historial automáticamente.

## Verificación local

```powershell
powershell.exe -NoProfile -STA -File .\Pruebas.ps1
powershell.exe -NoProfile -STA -File .\Pruebas.ps1 -Interfaz -Programador
```

La suite guarda el historial y los archivos de limpieza en una carpeta temporal aislada; la revisión solo lee fuentes reales de Windows. Con `-Programador` registra una tarea temporal con nombre aleatorio: verifica la definición semanal y pausa/reanudación, y después usa un disparador de una sola vez para comprobar una ejecución real sin esperar una semana. El acceso de prueba se crea en la carpeta temporal, no en el Escritorio. Con `-Interfaz` se abre una ventana WinForms, se activa la revisión mensual y se comprueba el informe visible. También se prueba la vista previa de limpieza y se simulan las respuestas negativa y afirmativa a la confirmación: solo debe desaparecer el archivo ficticio seleccionado. No se instala la app para ejecutar estas pruebas.
