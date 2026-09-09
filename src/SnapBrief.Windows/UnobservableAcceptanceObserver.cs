namespace SnapBrief.Windows;

public sealed class UnobservableAcceptanceObserver(IForegroundTargetService foreground) : IPasteAcceptanceObserver
{
    public async Task<PackageAcceptanceOutcome> WaitForPackageAsync(
        TargetSnapshot target,
        TargetProfile profile,
        CancellationToken cancellationToken)
    {
        var outcome = await WaitAsync(target, profile, cancellationToken);
        return new(outcome, outcome);
    }

    public Task<AcceptanceOutcome> WaitForImageAsync(
        TargetSnapshot target,
        int imageIndex,
        TargetProfile profile,
        CancellationToken cancellationToken) => WaitAsync(target, profile, cancellationToken);

    public Task<AcceptanceOutcome> WaitForTextAsync(
        TargetSnapshot target,
        TargetProfile profile,
        CancellationToken cancellationToken) => WaitAsync(target, profile, cancellationToken);

    private async Task<AcceptanceOutcome> WaitAsync(
        TargetSnapshot target,
        TargetProfile profile,
        CancellationToken cancellationToken)
    {
        await Task.Delay(profile.UnobservableSettlementDelay, cancellationToken);
        return foreground.IsSame(target) ? AcceptanceOutcome.NotObservable : AcceptanceOutcome.TargetLost;
    }
}
