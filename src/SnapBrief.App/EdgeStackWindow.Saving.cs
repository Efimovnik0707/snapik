using System;
using System.Threading.Tasks;
using System.Windows.Forms;
using SnapBrief.App.Controls;

namespace SnapBrief.App;

public partial class EdgeStackWindow
{
    internal void NotifySaved() => Notify("Снимок сохранён");
    private void NotifyCopied()
    {
        UiSoundService.Copied(_settings);
        Notify("Снимки скопированы");
    }
    private void Notify(string message)
    {
        if (_settings.ShowNotifications) _trayIcon.ShowBalloonTip(2000, "SnapBrief", UiLanguage.Text(message), ToolTipIcon.Info);
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
