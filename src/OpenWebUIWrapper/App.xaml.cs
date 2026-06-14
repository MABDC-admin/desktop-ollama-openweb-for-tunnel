// Application bootstrap + single-instance gate.
//
// This is the Windows counterpart to the bottom of wrapper.swift (the argv
// parse + NSApplication.run section). It parses the launch config, enforces
// single-instance, and shows the one window. ShutdownMode is set in App.xaml
// to OnExplicitShutdown — closing the window must NOT terminate the app, or the
// warm dev server dies (ADR 0005 lifecycle row 3).

using System;
using System.Diagnostics;
using System.IO;
using System.Windows;

namespace AppItWindows;

public partial class App : Application
{
    private SingleInstanceGate? _gate;
    private MainWindow? _mainWindow;

    public HostConfig Config { get; private set; } = null!;

    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);

        Config = HostConfig.Resolve(e.Args);
        if (string.IsNullOrWhiteSpace(Config.Url))
        {
            if (TryDelegateDirectExeLaunch())
            {
                Shutdown(0);
                return;
            }

            MessageBox.Show(
                "app-it host: no URL supplied.\n\n" +
                "Pass --url http://127.0.0.1:<PORT> (or set APP_IT_URL).\n" +
                "This host is normally launched by run.ps1. If this came from a direct .exe click, rebuild the launcher so run.ps1 sits next to the .exe.",
                "app-it (Windows beta)",
                MessageBoxButton.OK, MessageBoxImage.Warning);
            Shutdown(2);
            return;
        }

        // Single-instance, keyed by slug so two different app-it apps can both
        // be resident. If another host for this slug already holds the mutex
        // (it went tray-hidden after a soft-close), signal it to re-show and
        // exit — the resident server never left its Job Object, so re-show is
        // instant. This is the Windows reading of macOS warm relaunch (ADR 0005
        // lifecycle row 5); the open question of whether it *feels* instant on
        // real hardware is deferred to a maintainer.
        _gate = new SingleInstanceGate(Config.Slug);
        if (!_gate.IsPrimary)
        {
            _gate.SignalExistingInstance();
            Shutdown(0);
            return;
        }

        _mainWindow = new MainWindow(Config);
        _gate.ReShowRequested += () => Dispatcher.Invoke(() => _mainWindow!.ReShow());
        _gate.BeginListening();

        _mainWindow.Show();
    }

    private static bool TryDelegateDirectExeLaunch()
    {
        var exePath = Environment.ProcessPath;
        if (string.IsNullOrWhiteSpace(exePath)) return false;

        var appDir = Path.GetDirectoryName(exePath);
        if (string.IsNullOrWhiteSpace(appDir)) return false;

        var runScript = Path.Combine(appDir, "run.ps1");
        if (!File.Exists(runScript)) return false;

        var powerShell = ResolvePowerShell();
        if (powerShell is null) return false;

        try
        {
            Process.Start(new ProcessStartInfo
            {
                FileName = powerShell,
                Arguments = $"-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File \"{runScript}\"",
                WorkingDirectory = appDir,
                UseShellExecute = false,
                CreateNoWindow = true,
            });
            return true;
        }
        catch
        {
            return false;
        }
    }

    private static string? ResolvePowerShell()
    {
        var windir = Environment.GetFolderPath(Environment.SpecialFolder.Windows);
        var windowsPowerShell = Path.Combine(
            windir, "System32", "WindowsPowerShell", "v1.0", "powershell.exe");

        if (File.Exists(windowsPowerShell)) return windowsPowerShell;

        var path = Environment.GetEnvironmentVariable("PATH") ?? "";
        foreach (var dir in path.Split(Path.PathSeparator, StringSplitOptions.RemoveEmptyEntries))
        {
            try
            {
                var candidate = Path.Combine(dir.Trim(), "pwsh.exe");
                if (File.Exists(candidate)) return candidate;
            }
            catch
            {
                // Ignore malformed PATH entries.
            }
        }

        return null;
    }

    protected override void OnExit(ExitEventArgs e)
    {
        _gate?.Dispose();
        base.OnExit(e);
    }
}
