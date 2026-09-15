using System;
using System.Diagnostics;
using System.IO;
using System.IO.Pipes;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using System.Windows.Threading;

namespace Snapik.App;

internal sealed class SingleInstanceActivation : IDisposable
{
    private static readonly byte[] ShowCommand = Encoding.ASCII.GetBytes("SHOW\n");
    private const byte Acknowledged = 0x06;
    private static readonly PipeOptions SecureAsyncOptions = PipeOptions.Asynchronous | PipeOptions.CurrentUserOnly;

    private readonly Dispatcher dispatcher;
    private readonly Action showPrimary;
    private readonly CancellationTokenSource shutdown = new();
    private readonly object sync = new();
    private NamedPipeServerStream? activeServer;
    private Task? listener;
    private bool disposed;

    private SingleInstanceActivation(Dispatcher dispatcher, Action showPrimary)
    {
        this.dispatcher = dispatcher;
        this.showPrimary = showPrimary;
    }

    public static SingleInstanceActivation Start(Dispatcher dispatcher, Action showPrimary)
    {
        ArgumentNullException.ThrowIfNull(dispatcher);
        ArgumentNullException.ThrowIfNull(showPrimary);
        if (!dispatcher.CheckAccess()) throw new InvalidOperationException("Start the activation listener on the application dispatcher.");

        var activation = new SingleInstanceActivation(dispatcher, showPrimary);
        activation.listener = Task.Run(activation.ListenAsync);
        return activation;
    }

    public static async Task<bool> TryRequestShowAsync(TimeSpan timeout, CancellationToken cancellationToken = default)
    {
        if (timeout <= TimeSpan.Zero) throw new ArgumentOutOfRangeException(nameof(timeout));
        var stopwatch = Stopwatch.StartNew();
        while (stopwatch.Elapsed < timeout)
        {
            cancellationToken.ThrowIfCancellationRequested();
            var remaining = timeout - stopwatch.Elapsed;
            var attemptTimeout = remaining < TimeSpan.FromMilliseconds(250) ? remaining : TimeSpan.FromMilliseconds(250);
            try
            {
                using var attempt = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
                attempt.CancelAfter(attemptTimeout);
                await using var client = new NamedPipeClientStream(
                    ".", PipeName, PipeDirection.InOut, SecureAsyncOptions);
                await client.ConnectAsync(attempt.Token);
                await client.WriteAsync(ShowCommand, attempt.Token);
                await client.FlushAsync(attempt.Token);
                var acknowledgement = new byte[1];
                if (await client.ReadAsync(acknowledgement, attempt.Token) == 1 && acknowledgement[0] == Acknowledged)
                    return true;
            }
            catch (OperationCanceledException) when (!cancellationToken.IsCancellationRequested)
            {
            }
            catch (IOException)
            {
            }
            catch (UnauthorizedAccessException)
            {
                return false;
            }

            var retryDelay = timeout - stopwatch.Elapsed;
            if (retryDelay <= TimeSpan.Zero) break;
            if (retryDelay > TimeSpan.FromMilliseconds(60)) retryDelay = TimeSpan.FromMilliseconds(60);
            await Task.Delay(retryDelay, cancellationToken);
        }
        return false;
    }

    internal static bool IsShowCommand(ReadOnlySpan<byte> command) => command.SequenceEqual(ShowCommand);
    internal static bool UsesCurrentUserOnly => SecureAsyncOptions.HasFlag(PipeOptions.CurrentUserOnly);

    private async Task ListenAsync()
    {
        while (!shutdown.IsCancellationRequested)
        {
            try
            {
                await using var server = new NamedPipeServerStream(
                    PipeName,
                    PipeDirection.InOut,
                    1,
                    PipeTransmissionMode.Message,
                    SecureAsyncOptions);
                lock (sync) activeServer = server;
                await server.WaitForConnectionAsync(shutdown.Token);

                using var exchange = CancellationTokenSource.CreateLinkedTokenSource(shutdown.Token);
                exchange.CancelAfter(TimeSpan.FromSeconds(1));
                var command = new byte[ShowCommand.Length];
                var read = 0;
                while (read < command.Length)
                {
                    var count = await server.ReadAsync(command.AsMemory(read), exchange.Token);
                    if (count == 0) break;
                    read += count;
                }

                if (read == command.Length && server.IsMessageComplete && IsShowCommand(command))
                {
                    _ = dispatcher.BeginInvoke(showPrimary, DispatcherPriority.Send);
                    await server.WriteAsync(new byte[] { Acknowledged }, exchange.Token);
                    await server.FlushAsync(exchange.Token);
                }
            }
            catch (OperationCanceledException) when (shutdown.IsCancellationRequested)
            {
                break;
            }
            catch (OperationCanceledException)
            {
                // A connected peer did not complete the fixed exchange in time.
            }
            catch (IOException) when (!shutdown.IsCancellationRequested)
            {
            }
            catch (ObjectDisposedException) when (shutdown.IsCancellationRequested)
            {
                break;
            }
            finally
            {
                lock (sync) activeServer = null;
            }
        }
    }

    private static string PipeName => $"Snapik.Desktop.Activation.v1.{Process.GetCurrentProcess().SessionId}";

    public void Dispose()
    {
        if (disposed) return;
        disposed = true;
        shutdown.Cancel();
        lock (sync) activeServer?.Dispose();
        if (listener is null || listener.IsCompleted) shutdown.Dispose();
        else _ = listener.ContinueWith(
            _ => shutdown.Dispose(),
            CancellationToken.None,
            TaskContinuationOptions.ExecuteSynchronously,
            TaskScheduler.Default);
    }
}
