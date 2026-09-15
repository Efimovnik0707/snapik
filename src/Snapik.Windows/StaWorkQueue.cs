using System.Windows.Threading;

namespace Snapik.Windows;

internal sealed class StaWorkQueue : IDisposable
{
    private readonly TaskCompletionSource<Dispatcher> dispatcherReady =
        new(TaskCreationOptions.RunContinuationsAsynchronously);
    private readonly Thread thread;
    private readonly Dispatcher dispatcher;
    private bool disposed;

    public StaWorkQueue(string name)
    {
        thread = new Thread(Run) { IsBackground = true, Name = name };
        thread.SetApartmentState(ApartmentState.STA);
        thread.Start();
        dispatcher = dispatcherReady.Task.GetAwaiter().GetResult();
    }

    public Task<T> InvokeAsync<T>(Func<T> action, CancellationToken cancellationToken)
    {
        ObjectDisposedException.ThrowIf(disposed, this);
        cancellationToken.ThrowIfCancellationRequested();
        var completion = new TaskCompletionSource<T>(TaskCreationOptions.RunContinuationsAsynchronously);
        _ = dispatcher.BeginInvoke(DispatcherPriority.Send, new Action(() =>
        {
            if (cancellationToken.IsCancellationRequested)
            {
                completion.TrySetCanceled(cancellationToken);
                return;
            }
            try { completion.TrySetResult(action()); }
            catch (Exception ex) { completion.TrySetException(ex); }
        }));
        return completion.Task;
    }

    private void Run()
    {
        var current = Dispatcher.CurrentDispatcher;
        dispatcherReady.TrySetResult(current);
        Dispatcher.Run();
    }

    public void Dispose()
    {
        if (disposed) return;
        disposed = true;
        dispatcher.BeginInvokeShutdown(DispatcherPriority.Send);
        if (Thread.CurrentThread != thread) thread.Join(TimeSpan.FromSeconds(2));
    }
}
