using System;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Shapes;
using System.Windows.Threading;

namespace Snapik.App.Controls;

/// <summary>
/// The four how-to slides: a capture into a chat, a package of captures, comments on the markers and
/// the life of the strip. Each of them is one Storyboard of four phases; the control shows one
/// drawing at a time, moves on by a timer of its own and lets the user step through the dots and
/// the chevrons. It is a control of its own so that the wizard window keeps its shape, and so that
/// the tray can open the slides alone. The automatic run goes round; the user does not, and the
/// first move the user makes stops the automatic run for good.
/// </summary>
public partial class HowToSlides : UserControl
{
    internal const int SlideCount = 4;
    // One brush for every dot of every instance of the control, so it is frozen: nobody owns it and
    // nobody may change it under the others.
    private static readonly SolidColorBrush IdleDot = CreateIdleDot();
    // A slide whose storyboard carries no time span of its own still has to move on.
    private static readonly TimeSpan FallbackSlideDuration = TimeSpan.FromSeconds(9);
    // A frame this close to the end of a repeating loop is the finished picture.
    private static readonly TimeSpan FinishedFrame = TimeSpan.FromSeconds(8.9);
    // The name of every slide, in the language the control is shown in.
    private static readonly string[] SlideNames =
        ["Снимок с комментариями", "Несколько снимков сразу", "Открыть снимок снова", "Лента снимков"];
    private readonly Storyboard[] _loops;
    private readonly UIElement[] _scenes;
    private readonly UIElement[] _captions;
    private readonly Button[] _dots;
    private readonly Shape[] _dotMarks;
    // One bit per storyboard whose clock still sits on this control: stopping is not enough, the
    // clock has to be removed as well, and removing one that was never applied is pointless.
    private int _applied;
    private bool _running;
    // The automatic run is a timer of its own rather than the Completed of the storyboard: stopping
    // a clock raises Completed too, and it arrives a tick later, when any flag that guarded against
    // it is already down. That stray event added a step of its own after every move of the user.
    private readonly DispatcherTimer _auto = new();
    private bool _autoAdvancing;
    // The user has taken the slides into their own hands, for as long as this control lives. In the
    // wizard the step with the slides is left and entered again (Back, then Next), and Start runs a
    // second time; without this the carousel began moving on its own under a hand that had already
    // stopped it.
    private bool _steppedByHand;
    private int _slide;
    private string _language = UiLanguage.Current;

    private static SolidColorBrush CreateIdleDot()
    {
        var brush = new SolidColorBrush(Color.FromRgb(70, 80, 94));
        brush.Freeze();
        return brush;
    }

    public HowToSlides()
    {
        InitializeComponent();
        _loops =
        [
            (Storyboard)FindResource("Slide1Loop"), (Storyboard)FindResource("Slide2Loop"),
            (Storyboard)FindResource("Slide3Loop"), (Storyboard)FindResource("Slide4Loop")
        ];
        _auto.Tick += OnAutoAdvance;
        _scenes = [Scene1, Scene2, Scene3, Scene4];
        _captions = [SlideCaptions1, SlideCaptions2, SlideCaptions3, SlideCaptions4];
        _dots = [Dot1, Dot2, Dot3, Dot4];
        _dotMarks = [DotMark1, DotMark2, DotMark3, DotMark4];
        ShowSlide(0);
        RefreshDotTips();
    }

    /// <summary>Which slide is on screen, 0 based.</summary>
    internal int Slide => _slide;

    /// <summary>Whether the slides still move on by themselves; the first move of the user ends it.</summary>
    internal bool AutoAdvancing => _autoAdvancing;

    /// <summary>Starts the slides from the one on screen; calling it twice changes nothing.</summary>
    internal void Start()
    {
        if (_running) return;
        _running = true;
        _autoAdvancing = !_steppedByHand;
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
        _auto.Stop();
        StopApplied();
    }

    /// <summary>Shows one slide and restarts its clock while the slides are running.</summary>
    internal void ShowSlide(int index)
    {
        _slide = Math.Clamp(index, 0, SlideCount - 1);
        SlideTitle.Text = UiLanguage.Text(SlideNames[_slide], _language);
        for (var i = 0; i < SlideCount; i++)
        {
            var visible = i == _slide ? Visibility.Visible : Visibility.Collapsed;
            _scenes[i].Visibility = visible;
            _captions[i].Visibility = visible;
            _dotMarks[i].SetValue(Shape.FillProperty, IdleDot);
            if (i == _slide) _dotMarks[i].SetResourceReference(Shape.FillProperty, "AccentBrush");
        }
        // The chevrons say where the ends are instead of wrapping around silently.
        PreviousSlideButton.IsEnabled = _slide > 0;
        NextSlideButton.IsEnabled = _slide < SlideCount - 1;
        if (_running) Play(_slide);
    }

    /// <summary>
    /// One slide forward or back, on behalf of the user: a chevron, a dot or an arrow key. The ends
    /// hold, there is nothing before the first slide and nothing after the last one, and the
    /// automatic run stops, because the user has said which slide to look at.
    /// </summary>
    internal void Step(int delta)
    {
        StopAutoAdvance();
        var target = Math.Clamp(_slide + delta, 0, SlideCount - 1);
        if (target == _slide) return;
        ShowSlide(target);
    }

    /// <summary>The slide the user picked by its dot; out of range is clamped, as in ShowSlide.</summary>
    internal void GoTo(int index)
    {
        StopAutoAdvance();
        ShowSlide(index);
    }

    // The captions and the tooltips of the chevrons are translated by the sweep over the window, but
    // the tooltip of a dot is built here, so the control is told which language it is shown in.
    internal void ApplyLanguage(string language)
    {
        _language = language;
        Scene1.ApplyLanguage(language);
        SlideTitle.Text = UiLanguage.Text(SlideNames[_slide], language);
        RefreshDotTips();
    }

    private void RefreshDotTips()
    {
        for (var i = 0; i < SlideCount; i++)
            _dots[i].ToolTip = string.Format(UiLanguage.Text("Слайд {0} из {1}", _language), i + 1, SlideCount);
    }

    private void Play(int index)
    {
        StopApplied();
        _loops[index].Begin(this, true);
        _applied |= 1 << index;
        if (index == 0) Scene1.Play();
        // With the animations of the system switched off the slide shows its finished picture and
        // waits for the clock below: the frames change one by one instead of moving.
        if (!SystemParameters.ClientAreaAnimation)
        {
            _loops[index].Seek(this, FinishedFrame, TimeSeekOrigin.BeginTime);
            _loops[index].Pause(this);
        }
        // The wait is always a whole slide long, whichever slide it is and however it was reached.
        _auto.Stop();
        if (!_running || !_autoAdvancing) return;
        var duration = _loops[index].Duration;
        _auto.Interval = duration.HasTimeSpan && duration.TimeSpan > TimeSpan.Zero ? duration.TimeSpan : FallbackSlideDuration;
        _auto.Start();
    }

    private void StopAutoAdvance()
    {
        _autoAdvancing = false;
        _steppedByHand = true;
        _auto.Stop();
    }

    private void StopApplied()
    {
        Scene1.Halt();
        for (var i = 0; i < _loops.Length; i++)
        {
            if ((_applied & (1 << i)) == 0) continue;
            _loops[i].Stop(this);
            _loops[i].Remove(this);
        }
        _applied = 0;
    }

    // Left alone, the slides go round: a carousel that stops on the fourth slide looks broken.
    private void OnAutoAdvance(object? sender, EventArgs e)
    {
        if (!_running || !_autoAdvancing) { _auto.Stop(); return; }
        ShowSlide((_slide + 1) % SlideCount);
    }

    private void OnPreviousSlide(object sender, RoutedEventArgs e) => Step(-1);

    private void OnNextSlide(object sender, RoutedEventArgs e) => Step(1);

    private void OnDot(object sender, RoutedEventArgs e)
    {
        var index = Array.IndexOf(_dots, sender);
        if (index >= 0) GoTo(index);
    }

    // Smoke probe: every slide is built and shown, one drawing at a time, and the clocks are given
    // back — a second Stop over a removed clock is exactly what this has to survive.
    internal static void RunSlidesProbe()
    {
        var slides = new HowToSlides();
        slides.Measure(new Size(480, 620));
        slides.Arrange(new Rect(0, 0, 480, 620));
        // The block of captions has one height for all four slides, so the row of dots under it
        // stands still and the step never grows a scrollbar. Both languages are walked: the lines
        // wrap at different places in each, and a longer translation is exactly what would push the
        // block past the height it is given.
        foreach (var language in new[] { "ru", "en" })
        {
            UiLanguage.Apply(slides, language);
            slides.ApplyLanguage(language);
            for (var index = 0; index < SlideCount; index++)
            {
                slides.ShowSlide(index);
                slides.UpdateLayout();
                var visible = 0;
                foreach (var scene in slides._scenes) if (scene.Visibility == Visibility.Visible) visible++;
                if (slides.Slide != index || visible != 1)
                    throw new InvalidOperationException($"The how-to slides must show exactly one drawing, and it must be slide {index + 1}.");
                // Measured without a ceiling on purpose: asked inside the block, the captions would
                // report the height of the block itself however far past it they went.
                slides._captions[index].Measure(new Size(480, double.PositiveInfinity));
                var asked = slides._captions[index].DesiredSize.Height;
                if (asked > slides.CaptionsBlock.Height)
                    throw new InvalidOperationException(
                        $"The captions of slide {index + 1} in \"{language}\" ask for {asked} px of the {slides.CaptionsBlock.Height} the block has.");
            }
        }
        UiLanguage.Apply(slides, "ru");
        slides.ApplyLanguage("ru");
        slides.ShowSlide(0);
        slides.Start();
        RunSlideNavigationProbe(slides);
        // The step with the slides can be left and entered again, and Start runs a second time. A
        // carousel the user has already stopped must stay stopped.
        slides.Stop();
        slides.Start();
        if (slides.AutoAdvancing)
            throw new InvalidOperationException("Slides the user has stepped through must not start moving by themselves again.");
        slides.Stop();
        slides.Stop();
    }

    // The navigation the user drives: the ends hold, and the first move of the user is the last move
    // the automatic run makes. The probe goes through the way in the chevrons, the dots and the
    // arrow keys use, because the defect was in that way in, not in ShowSlide, which is all the
    // probe above had been calling.
    private static void RunSlideNavigationProbe(HowToSlides slides)
    {
        if (!slides.AutoAdvancing || slides.PreviousSlideButton.IsEnabled)
            throw new InvalidOperationException("Started slides must run by themselves, and the first slide has nothing before it.");
        slides.Step(-1);
        if (slides.Slide != 0 || slides.AutoAdvancing)
            throw new InvalidOperationException("An arrow on the first slide must stay on it and stop the automatic run.");
        for (var i = 0; i < SlideCount + 1; i++) slides.Step(1);
        if (slides.Slide != SlideCount - 1 || slides.NextSlideButton.IsEnabled)
            throw new InvalidOperationException("The slides must stop on the last one instead of wrapping round to the first.");
        slides.GoTo(1);
        if (slides.Slide != 1 || !slides.PreviousSlideButton.IsEnabled || !slides.NextSlideButton.IsEnabled)
            throw new InvalidOperationException("A dot must show its own slide, with both chevrons alive in the middle.");
        slides.GoTo(99);
        if (slides.Slide != SlideCount - 1)
            throw new InvalidOperationException("A slide out of range must be clamped to the last one.");
        slides.ShowSlide(0);
    }
}
