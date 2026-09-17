using System;
using System.Threading;
using System.Threading.Tasks;
using System.Windows.Forms;
using Snapik.App.Controls;
using Snapik.Core.Models;

namespace Snapik.App;

public partial class EdgeStackWindow
{
    internal void NotifySaved() => Notify("Снимок сохранён");
    // The balloon travels with every clipboard refresh, the sound does not: it belongs to the
    // explicit "Copy package" command only, see CopyPackageAsync.
    private void NotifyCopied() => Notify("Снимки скопированы");
    private void Notify(string message)
    {
        if (_settings.ShowNotifications) _trayIcon.ShowBalloonTip(2000, "Snapik", UiLanguage.Text(message), ToolTipIcon.Info);
    }

    internal async Task AutoSaveCaptureAsync(CaptureItem capture)
    {
        if (!_settings.AutoSaveCaptures) return;
        try
        {
            var canvas = new AnnotationCanvas { Image = capture.Image, Annotations = capture.Annotations };
            await LocalImageSave.WriteAsync(
                canvas.RenderAnnotated(),
                LocalImageSave.NewPath(_settings),
                _settings.SaveFormat,
                _settings.JpegQuality,
                false);
            NotifySaved();
        }
        catch (Exception ex)
        {
            SetStatus($"{UiLanguage.Text("Автосохранение не выполнено")}: {ex.Message}", true);
        }
    }

    /// <summary>
    /// One capture on the clipboard: the same export and the same formats a package gets, because
    /// SetPackageGuardedAsync with a single path lays out the PNG, the DIB, the Bitmap, the FileDrop
    /// and the text by itself. It becomes the published package, so a paste that is noticed marks
    /// that one capture as sent and nothing else. `_prepared` is left alone: the paste button still
    /// sends everything that waits, and it rebuilds itself on the next capture anyway.
    /// </summary>
    internal async Task CopySingleCaptureAsync(CaptureItem capture, string label)
    {
        await _pasteIntentTransition;
        CancelReceiverEchoWatch();
        await _clipboardPublicationGate.WaitAsync();
        try
        {
            var export = await _workspace.ExportSingleAsync(capture, label);
            var current = await _clipboard.CaptureAsync(CancellationToken.None);
            _ownedClipboardReceipt = await _clipboard.SetPackageGuardedAsync(
                export.GetImagePathsInOrder(), export.Manifest.PromptText, current.SequenceNumber, CancellationToken.None);
            SetPublished(Published(export));
            UiSoundService.Copied(_settings);
            ShowToast(string.Format(UiLanguage.Text("Снимок {0} скопирован"), label));
        }
        catch (Exception ex)
        {
            SetStatus($"{UiLanguage.Text("Не удалось скопировать снимок")}: {ex.Message}", true);
        }
        finally { _clipboardPublicationGate.Release(); }
    }

    // The whole screen goes into the strip like any other capture, and the folder gets it from the
    // autosave the rest of them go through: it used to be written straight to disk and never shown,
    // which is how three files of five megabytes each appeared in Pictures while the strip stayed
    // empty. The tail below is the tail of an ordinary capture, minus the editor: the shortcut is
    // "take everything right now", and a full-screen editor over a picture 3840 px wide is not that.
    private async Task CaptureFullscreenAsync()
    {
        await _pasteIntentTransition;
        // This hides every window too, so the rule of the capture holds for it word for word.
        if (CaptureIsBlockedByADialog("fullscreen capture")) return;
        if (_busy) return;
        // Asked before anything is hidden, exactly as in the capture of a region: a press on a full
        // strip must not black the screen out for a capture that has nowhere to go.
        if (StripIsFull()) return;
        _busy = true;
        try
        {
            HideForCapture();
            await Task.Delay(120);
            var frame = CaptureOverlay.CaptureDesktopFrame(_settings.CaptureCursor);
            var capture = await _workspace.AddImageAsync(frame.Image);
            capture.Kind = CaptureKind.Fullscreen;
            capture.MonitorCount = Screen.AllScreens.Length;
            Captures.Add(capture);
            Renumber();
            NoteStripGrowth();
            InvalidatePrepared();
            UiSoundService.Capture(_settings);
            await SaveAndCopyCommittedPackageAsync();
            await AutoSaveCaptureAsync(capture);
        }
        catch (Exception ex) { SetStatus($"{UiLanguage.Text("Не удалось снять экран")}: {ex.Message}", true); }
        finally { _busy = false; ShowStackWithoutActivation(); }
    }
}
