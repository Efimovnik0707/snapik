using System;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media.Animation;

namespace Snapik.App.Controls;

/// <summary>
/// The scene of the first step and of the first slide: a capture is framed, two comments are typed
/// on it, and the whole thing lands in a chat. The two places show the same drawing with the same
/// timings and differ only in what is around them, so there is one control and not two copies.
/// The loop runs while the scene is on screen and is taken off it when it is not: an animation clock
/// left on a control keeps the control alive and keeps repainting it behind a hidden step.
/// </summary>
public partial class CaptureSceneSmall : UserControl
{
    // A frame this close to the end of the loop is the finished picture; seeking to the duration
    // itself would wrap a repeating storyboard back to its beginning.
    private static readonly TimeSpan FinishedFrame = TimeSpan.FromSeconds(8.9);
    private readonly Storyboard _loop;
    private bool _applied;

    public CaptureSceneSmall()
    {
        InitializeComponent();
        _loop = (Storyboard)FindResource("SceneLoop");
        ApplyLanguage(UiLanguage.Current);
    }

    /// <summary>
    /// Runs the scene from its beginning. With the animations of the system switched off it shows the
    /// finished picture instead of moving: the step still explains itself, and nothing flickers.
    /// </summary>
    internal void Play()
    {
        Halt();
        _loop.Begin(this, true);
        _applied = true;
        if (SystemParameters.ClientAreaAnimation) return;
        _loop.Seek(this, FinishedFrame, TimeSeekOrigin.BeginTime);
        _loop.Pause(this);
    }

    /// <summary>Gives the animated properties back; calling it twice is allowed and does nothing.</summary>
    internal void Halt()
    {
        if (!_applied) return;
        _loop.Stop(this);
        _loop.Remove(this);
        _applied = false;
    }

    /// <summary>
    /// The two lines of the message are built here out of the badge, a dash and the translated text,
    /// so the sweep over the window does not have to know about strings that are put together.
    /// </summary>
    internal void ApplyLanguage(string language)
    {
        BubbleLine1.Text = $"A1 — {UiLanguage.Text("Кнопку ярче", language)}";
        BubbleLine2.Text = $"A2 — {UiLanguage.Text("Убрать блок", language)}";
    }
}
