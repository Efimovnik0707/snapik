using System;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Shapes;

namespace SnapBrief.App.Controls;

/// <summary>
/// The four how-to slides: a capture into a chat, a package of captures, comments on the markers and
/// the life of the strip. Each of them is one Storyboard of four phases; the control shows one
/// drawing at a time, moves on when the clock is done and lets the user step through the dots and
/// the chevrons. It is a control of its own so that the wizard window keeps its shape, and so that
/// the tray can open the slides alone.
/// </summary>
public partial class HowToSlides : UserControl
{
    internal const int SlideCount = 4;
    private static readonly SolidColorBrush IdleDot = new(Color.FromRgb(70, 80, 94));
    private readonly Storyboard[] _loops;
    private readonly Canvas[] _canvases;
    private readonly UIElement[] _captions;
    private readonly Button[] _dots;
    private readonly Shape[] _dotMarks;
    // One bit per storyboard whose clock still sits on this control: stopping is not enough, the
    // clock has to be removed as well, and removing one that was never applied is pointless.
    private int _applied;
    private bool _running;
    private bool _ignoreCompleted;
    private int _slide;
    private string _language = UiLanguage.Current;

    public HowToSlides()
    {
        InitializeComponent();
        _loops =
        [
            (Storyboard)FindResource("Slide1Loop"), (Storyboard)FindResource("Slide2Loop"),
            (Storyboard)FindResource("Slide3Loop"), (Storyboard)FindResource("Slide4Loop")
        ];
        foreach (var loop in _loops) loop.Completed += OnSlideCompleted;
        _canvases = [SlideCanvas1, SlideCanvas2, SlideCanvas3, SlideCanvas4];
        _captions = [SlideCaptions1, SlideCaptions2, SlideCaptions3, SlideCaptions4];
        _dots = [Dot1, Dot2, Dot3, Dot4];
        _dotMarks = [DotMark1, DotMark2, DotMark3, DotMark4];
        ShowSlide(0);
        RefreshDotTips();
    }

    /// <summary>Which slide is on screen, 0 based.</summary>
    internal int Slide => _slide;

    /// <summary>The shortcut shown on the key capsule of the first two slides.</summary>
    internal string KeyLabel
    {
        get => HintKeyText.Text;
        set { HintKeyText.Text = value; PackKeyText.Text = value; }
    }

    /// <summary>Starts the slides from the one on screen; calling it twice changes nothing.</summary>
    internal void Start()
    {
        if (_running) return;
        _running = true;
        Play(_slide);
    }

    /// <summary>
    /// Stops the slides and hands the animated properties back to the control. It runs whenever the
    /// step goes off screen and when the window closes, and it has to survive being called twice:
    /// a clock removed once must not be removed again.
    /// </summary>
    internal void Stop()
    {
        _running = false;
        StopApplied();
    }

    /// <summary>Shows one slide and restarts its clock while the slides are running.</summary>
    internal void ShowSlide(int index)
    {
        _slide = Math.Clamp(index, 0, SlideCount - 1);
        for (var i = 0; i < SlideCount; i++)
        {
            var visible = i == _slide ? Visibility.Visible : Visibility.Collapsed;
            _canvases[i].Visibility = visible;
            _captions[i].Visibility = visible;
            _dotMarks[i].SetValue(Shape.FillProperty, IdleDot);
            if (i == _slide) _dotMarks[i].SetResourceReference(Shape.FillProperty, "AccentBrush");
        }
        if (_running) Play(_slide);
    }

    internal void NextSlide() => ShowSlide((_slide + 1) % SlideCount);

    internal void PreviousSlide() => ShowSlide((_slide + SlideCount - 1) % SlideCount);

    // The captions and the tooltips of the chevrons are translated by the sweep over the window, but
    // the tooltip of a dot is built here, so the control is told which language it is shown in.
    internal void ApplyLanguage(string language)
    {
        _language = language;
        RefreshDotTips();
    }

    private void RefreshDotTips()
    {
        for (var i = 0; i < SlideCount; i++)
            _dots[i].ToolTip = string.Format(UiLanguage.Text("Слайд {0} из {1}", _language), i + 1, SlideCount);
    }

    private void Play(int index)
    {
        // Stopping a clock raises Completed as well, and that must not be read as "the slide is over".
        _ignoreCompleted = true;
        StopApplied();
        _ignoreCompleted = false;
        _loops[index].Begin(this, true);
        _applied |= 1 << index;
    }

    private void StopApplied()
    {
        for (var i = 0; i < _loops.Length; i++)
        {
            if ((_applied & (1 << i)) == 0) continue;
            _loops[i].Stop(this);
            _loops[i].Remove(this);
        }
        _applied = 0;
    }

    // The slides go round on their own; a slide the user has just picked starts its own clock, so
    // the wait is always a whole slide long.
    private void OnSlideCompleted(object? sender, EventArgs e)
    {
        if (_ignoreCompleted || !_running) return;
        NextSlide();
    }

    private void OnPreviousSlide(object sender, RoutedEventArgs e) => PreviousSlide();

    private void OnNextSlide(object sender, RoutedEventArgs e) => NextSlide();

    private void OnDot(object sender, RoutedEventArgs e)
    {
        var index = Array.IndexOf(_dots, sender);
        if (index >= 0) ShowSlide(index);
    }

    // Smoke probe: every slide is built and shown, one drawing at a time, and the clocks are given
    // back — a second Stop over a removed clock is exactly what this has to survive.
    internal static void RunSlidesProbe()
    {
        var slides = new HowToSlides();
        slides.Measure(new Size(360, 260));
        slides.Arrange(new Rect(0, 0, 360, 260));
        for (var index = 0; index < SlideCount; index++)
        {
            slides.ShowSlide(index);
            slides.UpdateLayout();
            var visible = 0;
            foreach (var canvas in slides._canvases) if (canvas.Visibility == Visibility.Visible) visible++;
            if (slides.Slide != index || visible != 1)
                throw new InvalidOperationException($"The how-to slides must show exactly one drawing, and it must be slide {index + 1}.");
        }
        slides.ShowSlide(0);
        slides.Start();
        slides.Stop();
        slides.Stop();
    }
}
