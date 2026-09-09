using System;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;

namespace SnapBrief.App;

public partial class EdgeStackWindow
{
    private async void OnOpenCaptureClick(object sender, RoutedEventArgs e)
    {
        await _pasteIntentTransition;
        if (_busy || sender is not Button { Tag: CaptureItem capture }) return;

        _busy = true;
        capture.IsSelected = true;
        CaptureList.Items.Refresh();
        var stackHidden = false;
        var requestNext = false;
        try
        {
            var preview = new CapturePreviewWindow(capture, PersistPreviewChangesAsync);
            var editRequested = await preview.ShowForAsync(this);
            if (!editRequested) return;

            HideForCapture();
            stackHidden = true;
            var index = Captures.IndexOf(capture);
            if (index < 0) return;
            var result = await OverlayEditorWindow.EditExistingAsync(_workspace, capture, index);
            if (!result.Cancelled && result.Capture is not null)
            {
                Captures[index] = result.Capture;
                Renumber();
                InvalidatePrepared();
                requestNext = await SaveAndCopyCommittedPackageAsync() && result.AddNext;
            }
        }
        catch (Exception ex) { SetStatus($"Не удалось открыть снимок: {ex.Message}", true); }
        finally
        {
            capture.IsSelected = false;
            CaptureList.Items.Refresh();
            _busy = false;
            if (stackHidden) ShowStackWithoutActivation();
        }
        if (requestNext) await CaptureLoopAsync();
    }

    private async Task PersistPreviewChangesAsync()
    {
        CaptureList.Items.Refresh();
        InvalidatePrepared();
        if (await SaveAsync()) await RefreshOwnedClipboardAsync();
    }

    private void OnCaptureThumbMouseEnter(object sender, MouseEventArgs e) => CaptureFeedbackSound.Tick(_settings.PlaySounds);

    private void OnCaptureListMouseWheel(object sender, MouseWheelEventArgs e)
    {
        CaptureFeedbackSound.Tick(_settings.PlaySounds);
    }
}
