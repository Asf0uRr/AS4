// AS4 IR Tool launcher. Finds the AS4 folder (the folder this exe sits in) and starts app\Main.ps1 with Windows PowerShell.
// Built three ways from this one file (see scripts\Build-Exe.ps1):  GUI (no console), CLI (console), ADMIN (asks for elevation).
// It installs nothing, touches no network, and changes no system setting. The execution-policy bypass applies to that one process only.
using System;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Text;
using System.Windows.Forms;

[assembly: AssemblyTitle("AS4 IR Tool launcher")]
[assembly: AssemblyProduct("AS4 IR Tool")]
[assembly: AssemblyVersion("1.1.0.0")]
[assembly: AssemblyFileVersion("1.1.0.0")]
[assembly: AssemblyDescription("Starts the AS4 IR Tool from the folder it is in")]

static class Launcher
{
    static string Quote(string s)
    {
        if (s.Length > 0 && s.IndexOfAny(new[] { ' ', '\t', '"' }) < 0) return s;
        return "\"" + s.Replace("\"", "\\\"") + "\"";
    }

    [STAThread]
    static int Main(string[] args)
    {
        string root = AppDomain.CurrentDomain.BaseDirectory.TrimEnd('\\');
        string over = Environment.GetEnvironmentVariable("AS4_ROOT");   // optional override (used by tests and the fallback cmd)
        if (!string.IsNullOrEmpty(over) && File.Exists(Path.Combine(Path.Combine(over, "app"), "Main.ps1"))) root = over.TrimEnd('\\');
        string main = Path.Combine(Path.Combine(root, "app"), "Main.ps1");
        string ps = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System), @"WindowsPowerShell\v1.0\powershell.exe");
        // a 32-bit launcher on 64-bit Windows would see SysWOW64; ask for the native one
        string native = Path.Combine(Environment.GetEnvironmentVariable("SystemRoot") ?? @"C:\Windows", @"Sysnative\WindowsPowerShell\v1.0\powershell.exe");
        if (!Environment.Is64BitProcess && Environment.Is64BitOperatingSystem && File.Exists(native)) ps = native;

        if (!File.Exists(main))
            return Fail("The AS4 folder is incomplete:\n" + main + " was not found.\nKeep the exe next to the app, tasks, tools and config folders.", 2);
        if (!File.Exists(ps))
            return Fail("Windows PowerShell was not found at\n" + ps, 2);

        var sb = new StringBuilder();
        sb.Append("-NoProfile ");
#if CLI
        sb.Append("-ExecutionPolicy Bypass -File " + Quote(main));
        if (args.Length == 0) sb.Append(" -Cli");
        foreach (string a in args) sb.Append(" " + Quote(a));
#else
        sb.Append("-STA -ExecutionPolicy Bypass -File " + Quote(main) + " -Gui");
        foreach (string a in args) sb.Append(" " + Quote(a));
#endif
        var psi = new ProcessStartInfo(ps, sb.ToString());
        psi.UseShellExecute = false;
        psi.WorkingDirectory = root;
#if !CLI
        psi.CreateNoWindow = true;
#endif
        try
        {
            using (Process p = Process.Start(psi))
            {
                p.WaitForExit();
#if !CLI
                if (p.ExitCode != 0 && p.ExitCode != 255)
                    return Fail("AS4 IR Tool stopped with code " + p.ExitCode + ".\nRun scripts\\Start-Without-Exe.cmd -Check to see what is missing.", p.ExitCode);
#endif
                return p.ExitCode;
            }
        }
        catch (Exception ex) { return Fail("AS4 IR Tool could not start:\n" + ex.Message, 3); }
    }

    static int Fail(string text, int code)
    {
#if CLI
        Console.Error.WriteLine(text);
#else
        MessageBox.Show(text, "AS4 IR Tool", MessageBoxButtons.OK, MessageBoxIcon.Warning);
#endif
        return code;
    }
}
