using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Threading.Tasks;
using System.Threading;
using System.Windows;
using Application = System.Windows.Application;
using StartupEventArgs = System.Windows.StartupEventArgs;

namespace Snapik.App;

public partial class App : Application
{
    private Mutex? _singleInstance;
    private SingleInstanceActivation? _activation;

    protected override async void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);
        var options = LaunchOptions.Parse(e.Args);
        StartupTrace.Write(options, "App.OnStartup entered");
        // Before any window exists: the shortcuts of the installer carry the same identity, and the
        // taskbar only puts the pinned icon and the running window together when the two agree.
        TaskbarPinService.NameThisProcess(message => StartupTrace.Write(options, message));
        if (!options.SmokeTest)
        {
            _singleInstance = new Mutex(true, "Local\\Snapik.Desktop.SingleInstance", out var createdNew);
            if (!createdNew)
            {
                var requested = await SingleInstanceActivation.TryRequestShowAsync(TimeSpan.FromSeconds(2));
                StartupTrace.Write(options, requested ? "Second instance requested SHOW" : "Second instance could not reach primary activation listener");
                Shutdown(0);
                return;
            }
        }
        if (options.SmokeTest)
        {
            try
            {
                var result = await SmokeTestRunner.RunAsync(options.DataDirectory);
                Environment.ExitCode = result ? 0 : 1;
            }
            catch (Exception ex)
            {
                Environment.ExitCode = 1;
                var root = options.DataDirectory ?? Path.Combine(Path.GetTempPath(), "Snapik", "smoke-failure");
                Directory.CreateDirectory(root);
                File.WriteAllText(Path.Combine(root, "smoke-test-error.txt"), ex.ToString());
                Console.Error.WriteLine(ex);
            }
            Shutdown(Environment.ExitCode);
            return;
        }

        try
        {
            StartupTrace.Write(options, "Constructing EdgeStackWindow");
            System.Windows.Window window = new EdgeStackWindow(options);
            StartupTrace.Write(options, "Primary window constructed");
            MainWindow = window;
            _activation = SingleInstanceActivation.Start(Dispatcher, ShowExistingMainWindow);
            window.Show();
            StartupTrace.Write(options, "MainWindow.Show returned");
        }
        catch (Exception ex)
        {
            StartupTrace.Write(options, $"Fatal startup exception: {ex}");
            Shutdown(1);
        }
    }

    protected override void OnExit(System.Windows.ExitEventArgs e)
    {
        _activation?.Dispose();
        _singleInstance?.Dispose();
        base.OnExit(e);
    }

    private void ShowExistingMainWindow()
    {
        var window = MainWindow;
        if (window is null) return;
        if (window is EdgeStackWindow stack) stack.RevealStack();
        else if (!window.IsVisible) window.Show();
        if (window.WindowState == WindowState.Minimized) window.WindowState = WindowState.Normal;
        _ = window.Activate();
    }
}

public static class StartupTrace
{
    public static string GetDataRoot(LaunchOptions options) => options.DataDirectory
        ?? (options.Demo ? Path.Combine(Path.GetTempPath(), "Snapik", $"demo-{Environment.ProcessId}") : Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Snapik", "sessions"));

    public static void Write(LaunchOptions options, string message)
    {
        try
        {
            var root = GetDataRoot(options);
            Directory.CreateDirectory(root);
            File.AppendAllText(Path.Combine(root, "startup.log"), $"{DateTimeOffset.Now:O} {message}{Environment.NewLine}");
        }
        catch { }
    }
}

public sealed record LaunchOptions(bool Demo, bool SmokeTest, string? DataDirectory)
{
    public static LaunchOptions Parse(IReadOnlyList<string> args)
    {
        var demo = args.Any(a => a.Equals("--demo", StringComparison.OrdinalIgnoreCase));
        var smoke = args.Any(a => a.Equals("--smoke-test", StringComparison.OrdinalIgnoreCase));
        string? data = null;
        for (var i = 0; i < args.Count - 1; i++)
            if (args[i].Equals("--data-dir", StringComparison.OrdinalIgnoreCase)) data = args[i + 1];
        data ??= Environment.GetEnvironmentVariable("SNAPIK_DATA_DIR");
        return new LaunchOptions(demo, smoke, data);
    }
}
