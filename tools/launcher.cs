using System;
using System.IO;
using System.Diagnostics;
using System.Windows.Forms;
internal static class MountainMarkLauncher {
    [STAThread] static void Main(string[] args) {
        string root = AppDomain.CurrentDomain.BaseDirectory;
        string runtime = Path.Combine(root, ".runtime");
        string engine = Path.Combine(root, "engine", "Godot.exe");
        string pack = Path.Combine(root, "MountainMark.pck");
        try {
            Directory.CreateDirectory(runtime);
            string appdata = Path.Combine(runtime, "AppData");
            string local = Path.Combine(runtime, "LocalAppData");
            string temp = Path.Combine(runtime, "Temp");
            Directory.CreateDirectory(appdata); Directory.CreateDirectory(local); Directory.CreateDirectory(temp);
            if (!File.Exists(engine) || !File.Exists(pack)) {
                File.WriteAllText(Path.Combine(runtime, "launcher-error.log"), "Missing engine=" + engine + " pack=" + pack); MessageBox.Show("Please keep MountainMark.exe, MountainMark.pck and the engine folder together.", "Mountain Mark");
                return;
            }
            ProcessStartInfo start = new ProcessStartInfo(engine);
            start.WorkingDirectory = root;
            start.UseShellExecute = false;
            start.CreateNoWindow = true;
            start.Arguments = "--path \"" + root.TrimEnd(Path.DirectorySeparatorChar) + "\" --main-pack \"" + pack + "\" --log-file \"" + Path.Combine(runtime, "game.log") + "\"";
            Environment.SetEnvironmentVariable("APPDATA", appdata, EnvironmentVariableTarget.Process);
            Environment.SetEnvironmentVariable("LOCALAPPDATA", local, EnvironmentVariableTarget.Process);
            Environment.SetEnvironmentVariable("TEMP", temp, EnvironmentVariableTarget.Process);
            Environment.SetEnvironmentVariable("TMP", temp, EnvironmentVariableTarget.Process);
            Environment.SetEnvironmentVariable("MOUNTAINMARK_DATA_DIR", runtime, EnvironmentVariableTarget.Process);
                        bool smoke = Array.IndexOf(args, "--smoke-test") >= 0;
            bool route = Array.IndexOf(args, "--qa-route") >= 0;
            if (smoke) start.Arguments += " --headless --quit-after 60";
            if (route) start.Arguments += " --headless -- --qa-route";
            Process process = Process.Start(start);
            if (smoke || route) { process.WaitForExit(); Environment.Exit(process.ExitCode); }
        } catch (Exception e) { try { File.WriteAllText(Path.Combine(root, "launcher-error.log"), e.ToString()); } catch {} if (args.Length == 0) MessageBox.Show(e.Message, "Mountain Mark"); Environment.Exit(1); }
    }
}



