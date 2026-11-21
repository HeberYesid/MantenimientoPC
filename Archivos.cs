using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.IO;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;
using Microsoft.Win32.SafeHandles;

public static class ArchivosMpc {
    private const uint Excluir = 1 | 2 | 4 | 16 | 1024 | 4096 | 0x40000 | 0x400000;

    [StructLayout(LayoutKind.Sequential)]
    private struct Datos {
        public uint A, CreadoLo, CreadoHi, AccesoLo, AccesoHi, EditadoLo, EditadoHi;
        public uint Volumen, PesoHi, PesoLo, Enlaces, IdHi, IdLo;
    }
    public sealed class Candidato {
        public string Ruta { get; internal set; }
        public long Bytes { get; internal set; }
        public DateTime Modificado { get; internal set; }
        internal string Identidad;
    }

    [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
    private static extern SafeFileHandle CreateFile(string name, uint access, uint share, IntPtr security,
        uint disposition, uint flags, IntPtr template);
    [DllImport("kernel32.dll", SetLastError=true)]
    private static extern bool GetFileInformationByHandle(SafeFileHandle handle, out Datos data);
    [DllImport("kernel32.dll", SetLastError=true)]
    private static extern bool SetFileInformationByHandle(SafeFileHandle handle, int cls, ref byte delete, uint size);
    [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
    private static extern uint GetFileAttributes(string name);
    [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
    private static extern uint GetFinalPathNameByHandle(SafeFileHandle handle, StringBuilder path, uint capacity, uint flags);

    private static Datos Info(SafeFileHandle h) {
        Datos d;
        if (!GetFileInformationByHandle(h, out d)) throw new Win32Exception();
        return d;
    }

    private static SafeFileHandle Abrir(string p, uint access, uint share) {
        // OPEN_REPARSE_POINT y BACKUP_SEMANTICS (para poder abrir directorios sin seguir enlaces).
        var h = CreateFile(p, access, share, IntPtr.Zero, 3, 0x02200000, IntPtr.Zero);
        if (!h.IsInvalid) return h;
        int error = Marshal.GetLastWin32Error();
        h.Dispose();
        throw new Win32Exception(error);
    }

    private static bool NombreSeguro(string nombre) {
        string n = nombre.ToLowerInvariant();
        return (n.EndsWith(".tmp") || n.EndsWith(".temp")) && !n.Contains("cookie") &&
            n.IndexOfAny(new [] { ':', '\\', '/', '~' }) < 0;
    }

    private static void VerificarRuta(SafeFileHandle h, string p) {
        var real = new StringBuilder(32768);
        uint n = GetFinalPathNameByHandle(h, real, (uint)real.Capacity, 0);
        if (n == 0 || n >= real.Capacity || !String.Equals(real.ToString(), @"\\?\" + p, StringComparison.OrdinalIgnoreCase))
            throw new IOException("El archivo no corresponde a la ruta local esperada.");
    }

    private static Candidato Leer(string p, SafeFileHandle h, DateTime limite) {
        Datos d = Info(h);
        DateTime creado = DateTime.FromFileTimeUtc(((long)d.CreadoHi << 32) | d.CreadoLo);
        DateTime editado = DateTime.FromFileTimeUtc(((long)d.EditadoHi << 32) | d.EditadoLo);
        if ((d.A & Excluir) != 0 || d.Enlaces != 1 || creado > limite || editado > limite) return null;
        return new Candidato { Ruta = p, Bytes = ((long)d.PesoHi << 32) | d.PesoLo, Modificado = editado,
            Identidad = String.Join(":", new[] {d.Volumen,d.IdHi,d.IdLo,d.CreadoHi,d.CreadoLo,d.EditadoHi,d.EditadoLo,d.PesoHi,d.PesoLo}) };
    }

    private static T ConRaiz<T>(string root, Func<string,T> action) {
        string full = Path.GetFullPath(root).TrimEnd('\\');
        string unidad = Path.GetPathRoot(full);
        if (unidad == null || unidad.Length != 3 || unidad[1] != ':' ||
            new DriveInfo(unidad).DriveType != DriveType.Fixed || new DriveInfo(unidad).DriveFormat != "NTFS" ||
            full.Length <= unidad.Length || full.Contains("~") || full.Substring(2).Contains(":"))
            throw new IOException("La carpeta temporal no es una ruta local NTFS admitida.");
        var locks = new List<SafeFileHandle>();
        try {
            string current = unidad;
            foreach (string s in full.Substring(unidad.Length).Split('\\')) {
                if (s.EndsWith(".") || s.EndsWith(" ")) throw new IOException("Ruta no admitida.");
                current = Path.Combine(current,s);
                var h = Abrir(current, 0x80, 3); // durante la operacion no permitir que se renombre el ancestro
                locks.Add(h);
                uint a = Info(h).A;
                if ((a & 16) == 0 || (a & (1024 | 4096 | 0x40000 | 0x400000)) != 0)
                    throw new IOException("La carpeta temporal o un ancestro es un enlace o no está disponible.");
            }
            return action(full);
        } finally {
            for (int i = locks.Count - 1; i >= 0; i--) locks[i].Dispose();
        }
    }

    public sealed class Vista {
        public List<Candidato> Archivos = new List<Candidato>();
        public int Inaccesibles;
        public bool Limitada;
    }

    public static Vista Buscar(string root, DateTime limite) {
        return ConRaiz(root, full => {
            var vista = new Vista();
            int vistos = 0;
            foreach (string p in Directory.EnumerateFiles(full)) {
                if (++vistos > 12000 || vista.Archivos.Count == 500) { vista.Limitada = true; break; }
                if (!NombreSeguro(Path.GetFileName(p))) continue;
                try {
                    using (var h = Abrir(p, 0x80, 7)) {
                        var item = Leer(p,h,limite);
                        if (item != null) vista.Archivos.Add(item);
                    }
                } catch (Win32Exception) { vista.Inaccesibles++; }
            }
            return vista;
        });
    }

    public static string Quitar(string root, Candidato elegido, DateTime limite) {
        return ConRaiz(root, full => {
            string nombre = Path.GetFileName(elegido.Ruta);
            string p = Path.Combine(full,nombre);
            if (!String.Equals(p,elegido.Ruta,StringComparison.OrdinalIgnoreCase) || !NombreSeguro(nombre))
                return "Omitido: fuera del alcance permitido.";
            using (var h = Abrir(p,0x10080,0)) { // DELETE + READ_ATTRIBUTES; acceso exclusivo
                VerificarRuta(h,p);
                var ahora = Leer(p,h,limite);
                if (ahora == null || ahora.Identidad != elegido.Identidad) return "Omitido: cambió desde la vista previa.";
                byte eliminar = 1;
                if (!SetFileInformationByHandle(h,4,ref eliminar,1)) throw new Win32Exception();
            }
            if (GetFileAttributes(p) == UInt32.MaxValue && Marshal.GetLastWin32Error() == 2)
                return "Eliminado y verificado";
            return "No se pudo confirmar que la ruta desapareció.";
        });
    }

    public static string HashLectura(string[] roots, string ruta, long bytes, DateTime editado) {
        string p = Path.GetFullPath(ruta);
        foreach (string root in roots) {
            string full = Path.GetFullPath(root).TrimEnd('\\');
            if (!p.StartsWith(full + "\\", StringComparison.OrdinalIgnoreCase)) continue;
            return ConRaiz(Path.GetDirectoryName(p), parent => {
                using (var h = Abrir(Path.Combine(parent,Path.GetFileName(p)),0x80000000,1)) {
                    VerificarRuta(h,p);
                    var d = Info(h);
                    if ((d.A & (16 | 1024 | 4096 | 0x40000 | 0x400000)) != 0 || d.Enlaces != 1 ||
                        (((long)d.PesoHi << 32) | d.PesoLo) != bytes ||
                        DateTime.FromFileTimeUtc(((long)d.EditadoHi << 32) | d.EditadoLo) != editado)
                        throw new IOException("Archivo enlazado o cambiado.");
                    using (var s = new FileStream(h,FileAccess.Read))
                    using (var sha = SHA256.Create()) return Convert.ToBase64String(sha.ComputeHash(s));
                }
            });
        }
        throw new IOException("Ruta fuera de las carpetas elegidas.");
    }
}
