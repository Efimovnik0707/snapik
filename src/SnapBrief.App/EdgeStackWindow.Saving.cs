using System;
using System.Threading.Tasks;
using System.Windows.Forms;

namespace SnapBrief.App;

public partial class EdgeStackWindow
{
    internal void NotifySaved() => Notify("Снимок сохранён");
    private void NotifyCopied() => Notify("Снимки скопированы");
    private void Notify(string message)
    {
        if (_settings.ShowNotifications) _trayIcon.ShowBalloonTip(2000, "SnapBrief", UiLanguage.Text(message), ToolTipIcon.Info);
    }

    private async Task SaveFullscreenAsync()
    {
        await _pasteIntentTransition;
        if (_busy) return;
        _busy = true;
        var wasVisible = IsVisible;
        try
        {
            HideForCapture();
            await Task.Delay(120);
            var frame = CaptureOverlay.CaptureDesktopFrame(_settings.CaptureCursor);
            await LocalImageSave.WriteAsync(frame.Image, LocalImageSave.NewPath(_settings), _settings.SaveFormat, _settings.JpegQuality, false);
            NotifySaved();
        }
        catch (Exception ex) { wasVisible = true; SetStatus($"Не удалось сохранить экран: {ex.Message}", true); }
        finally { _busy = false; if (wasVisible) ShowStackWithoutActivation(); }
    }
}
