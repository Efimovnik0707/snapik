using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Threading;
using SnapBrief.Core.Exporting;
using SnapBrief.Core.Editing;
using WinForms = System.Windows.Forms;

namespace SnapBrief.App;

public sealed record OverlayEditResult(CaptureItem? Capture, bool AddNext, bool Cancelled);

public partial class OverlayEditorWindow : Window
{
    private static OverlayEditorWindow? _active;

    private readonly SessionWorkspace _workspace;
    private readonly DesktopFrame _frame;
    private readonly int _captureIndex;
    private readonly bool _isNew;
    private readonly Stack<OverlaySnapshot> _undo = [];
    private readonly Stack<OverlaySnapshot> _redo = [];
    private readonly Dictionary<Guid, TextBlock> _chipLabels = [];
    private readonly Dictionary<Guid, Border> _chipBorders = [];
    private readonly Dictionary<Guid, Action<bool>> _chipExpanders = [];
    private readonly Dictionary<Guid, Action> _chipFinishers = [];
    private readonly HashSet<Guid> _visibleChipIds = [];
    private readonly HashSet<string> _createdSourcePaths = new(StringComparer.OrdinalIgnoreCase);
    private readonly RectangleGeometry _shadeOuter = new();
    private readonly RectangleGeometry _shadeHole = new();
    private bool _closed;
    private Point? _selectionStart;
    private Rect _cropRect;
    private CaptureItem? _capture;
    private OverlaySnapshot? _lastSnapshot;
    private Color _activeColor = DefaultAnnotationColor;
    private double _activeThickness = DefaultAnnotationThickness;
    private double _activeHighlightThickness = DefaultHighlightThickness;
    private double _activeFontSize = TextMarkMetrics.DefaultFontSize;
    private SnapBrief.Core.Models.AnnotationShape _activeShape = SnapBrief.Core.Models.AnnotationShape.Rectangle;
    private SnapBrief.Core.Models.AnnotationFill _activeFill = SnapBrief.Core.Models.AnnotationFill.None;
    private Color? _activeFillColor;
    private bool _activeHasOutline = true;
    private PaletteSet _activePalette = Palettes[0];
    private EditorTool _activePencil = EditorTool.Pen;
    private Guid? _commentParentId;
    private Guid? _expandedChipId;
    private AnnotationItem? _chipDragAnnotation;
    private Point _chipDragStart;
    private Point? _chipDragOrigin;
    private bool _chipDragMoved;
    private bool _settingUp;
    private bool _busyCrop;
    // This press has already been spent on closing an editor beside the capture (the pill of a
    // note), so the release that follows must not finish the shot on top of it: one click, one thing.
    private bool _outsideClickConsumed;
    private readonly bool _commentsPanelVisible;

    private OverlayEditorWindow(SessionWorkspace workspace, DesktopFrame frame, int captureIndex, CaptureItem? existing)
    {
        _workspace = workspace;
        _frame = frame;
        _captureIndex = captureIndex;
        var preferences = workspace.Preferences;
        _activeColor = ParseAnnotationColor(preferences.AnnotationColor);
        _activeThickness = Math.Clamp(preferences.AnnotationThickness, 1, 16);
        _activeHighlightThickness = Math.Clamp(preferences.AnnotationHighlightThickness, MinimumHighlightThickness, MaximumHighlightThickness);
        _activeFontSize = TextMarkMetrics.Clamp(preferences.AnnotationFontSize);
        _activeShape = ParseAnnotationShape(preferences.AnnotationShape);
        _activeFill = ParseAnnotationFill(preferences.AnnotationFill);
        _activeFillColor = ParseAnnotationFillColor(preferences.AnnotationFillColor);
        _activeHasOutline = preferences.AnnotationOutline;
        _activePalette = ParseAnnotationPalette(preferences.AnnotationPalette);
        _activePencil = ParseAnnotationPencil(preferences.AnnotationPencil);
        _capture = existing?.DeepClone();
        _isNew = existing is null;
        if (_capture is not null && !string.IsNullOrWhiteSpace(_capture.Note))
        {
            _capture.Annotations.Add(new AnnotationItem { Kind = EditorTool.Comment, Note = _capture.Note, Points = [new Point(24, 24), new Point(32, 32)] });
            _capture.Note = string.Empty;
        }
        // The comments panel belongs to a capture reopened from the strip that already carries
        // notes. The decision is taken here, before the layout is measured against it, and it does
        // not change while the window is open.
        _commentsPanelVisible = !_isNew && _capture is not null &&
            _capture.Annotations.Any(annotation => !string.IsNullOrWhiteSpace(annotation.Note));
        InitializeComponent();
        // The crosshair belongs to the phase where an area is being selected; once there is a
        // capture to mark up, the pointer says what it will do where it stands.
        Cursor = existing is null ? Cursors.Cross : Cursors.Arrow;
        InitializeCaptureHandles();
        InitializeNoteButton();
        InitializeTextEditor();
        BuildColorDots();
        AttachLongPress(RectangleTool, () => BuildShapeMenu(RectangleTool));
        AttachLongPress(ArrowTool, () => BuildArrowMenu(ArrowTool));
        AttachLongPress(PenTool, () => BuildPencilMenu(PenTool));
        SetPencilMode(_activePencil);
        ApplyShortcutHints();
        DesktopImage.Source = frame.Image;
        var shadeGeometry = new GeometryGroup { FillRule = FillRule.EvenOdd };
        shadeGeometry.Children.Add(_shadeOuter);
        shadeGeometry.Children.Add(_shadeHole);
        Shade.Data = shadeGeometry;
        SourceInitialized += OnSourceInitialized;
        Loaded += OnLoaded;
        Closing += OnClosing;
    }

    public OverlayEditResult Result { get; private set; } = new(null, false, true);

    public static async Task<OverlayEditResult> CaptureNewAsync(SessionWorkspace workspace, int captureIndex)
    {
        await Task.Delay(120);
        var frame = CaptureOverlay.CaptureDesktopFrame(workspace.Preferences.CaptureCursor);
        var window = new OverlayEditorWindow(workspace, frame, captureIndex, null);
        _active = window;
        try { window.ShowDialog(); return window.Result; }
        finally { if (ReferenceEquals(_active, window)) _active = null; }
    }

    public static async Task<OverlayEditResult> EditExistingAsync(SessionWorkspace workspace, CaptureItem capture, int captureIndex)
    {
        await Task.Delay(120);
        var frame = CaptureOverlay.CaptureDesktopFrame(workspace.Preferences.CaptureCursor);
        var window = new OverlayEditorWindow(workspace, frame, captureIndex, capture);
        _active = window;
        try { window.ShowDialog(); return window.Result; }
        finally { if (ReferenceEquals(_active, window)) _active = null; }
    }

    public static bool TryCommitAndRequestNext()
    {
        var active = _active;
        if (active?._capture is null || active._busyCrop || active._captureResizeCorner >= 0 || active.Surface.IsMouseCaptured) return false;
        active.Dispatcher.BeginInvoke(() => active.Complete(true), DispatcherPriority.Input);
        return true;
    }

    // The panel is built from EditorShortcuts and translated by UiLanguage: in English nothing
    // written on it (tooltip, caption, cheat sheet row) may stay Russian.
    internal static void RunShortcutHintProbe(CaptureItem source)
    {
        var capture = source.DeepClone();
        var root = Path.Combine(Path.GetTempPath(), "SnapBrief", $"hint-probe-{Guid.NewGuid():N}");
        var workspace = new SessionWorkspace(root);
        var frame = new DesktopFrame(capture.Image, 0, 0, capture.Image.PixelWidth, capture.Image.PixelHeight);
        var window = new OverlayEditorWindow(workspace, frame, 0, capture) { Width = 1280, Height = 720 };
        window.Measure(new Size(1280, 720));
        window.Arrange(new Rect(0, 0, 1280, 720));
        window._cropRect = new Rect(120, 90, 900, 506);
        window.SetupEditor();
        var language = UiLanguage.Current;
        try
        {
            // Both are needed: Apply translates what the panel carries, SyncAppearance rebuilds the
            // captions the code composes (the caption of the "•••" button among them).
            UiLanguage.Current = "en";
            UiLanguage.Apply(window, "en");
            window.SelectToolMode(EditorTool.Pen);
            window.SyncAppearance();
            var cyrillic = new System.Text.RegularExpressions.Regex("[А-Яа-яЁё]");
            // The panel, the palette popover and the cheat sheet: everything written in the dark of
            // the editor, including the two popups that are built but never opened in a smoke run.
            foreach (var panel in new DependencyObject?[] { window.Toolbar, window.AppearancePopup.Child, window.ThicknessPopup.Child, window.FillPopup.Child, window.ShortcutSheetPopup.Child })
                foreach (var text in PanelStrings(panel))
                    if (cyrillic.IsMatch(text))
                        throw new InvalidOperationException($"The English markup panel still shows Russian text: \"{text}\".");
            if (EditorShortcuts.Caption(EditorTool.Pen) != "Pencil (P)" || (string?)window.SelectTool.ToolTip != "Select" ||
                window.SelectTool.Uid != "V")
                throw new InvalidOperationException("The panel must show the translated name and the key from EditorShortcuts.");
            var capsule = ShortcutCapsuleText(window, window.SelectTool);
            if (capsule != "V")
                throw new InvalidOperationException($"The tooltip of the select tool must carry the capsule \"V\", it carried \"{capsule}\".");
            // The menus of the three split buttons are built, read and used without a popup on screen.
            var shapeMenu = window.BuildShapeMenu(window.ShapeMenuButton);
            var arrowMenu = window.BuildArrowMenu(window.ArrowMenuButton);
            var pencilMenu = window.BuildPencilMenu(window.PenMenuButton);
            foreach (var menu in new[] { shapeMenu, arrowMenu, pencilMenu })
                foreach (var text in PanelStrings(menu))
                    if (cyrillic.IsMatch(text))
                        throw new InvalidOperationException($"The English split button menu still shows Russian text: \"{text}\".");
            MenuItem Row(ContextMenu menu, string caption) => menu.Items.OfType<MenuItem>().Single(item =>
                item.Header is StackPanel panel && panel.Children.OfType<TextBlock>().Any(text => text.Text == caption));
            Row(shapeMenu, "Ellipse").RaiseEvent(new RoutedEventArgs(MenuItem.ClickEvent));
            Row(arrowMenu, "Curved arrow").RaiseEvent(new RoutedEventArgs(MenuItem.ClickEvent));
            if (window.Surface.ActiveShape != SnapBrief.Core.Models.AnnotationShape.Ellipse || window.Surface.ActiveArrowStyle != "curved")
                throw new InvalidOperationException("A pick in a split button menu must reach the active shape and the active arrow style.");
            // The arrow menu is about the style of the arrow and nothing else: the thickness left it
            // for a button of its own, and the conceal tool left the editor altogether.
            if (arrowMenu.Items.Count != 3 || EditorShortcuts.Tools.Any(shortcut => shortcut.Key == Key.X))
                throw new InvalidOperationException("The arrow menu must hold three styles and no thickness, and the X key must be free.");
            if (EditorShortcuts.Find(EditorTool.Eraser) is not { Key: Key.E } || EditorShortcuts.Caption(EditorTool.Eraser) != "Eraser (E)")
                throw new InvalidOperationException("The eraser must sit on the E key, with a name of its own in both languages.");
            // The comments panel is checked by its own two captions rather than by walking it: every
            // other line in it is what the user wrote, and that stays in the language they wrote it.
            if (window.CommentsTitle.Text != "Comments" || window.CommentsEmpty.Text != "No comments yet")
                throw new InvalidOperationException("The comments panel must carry its captions in the language of the window.");
            // The pencil capsule stands for both modes: the H key arms the highlighter, and the
            // capsule starts carrying it, glyph, tag and all.
            Row(pencilMenu, "Highlight (H)").RaiseEvent(new RoutedEventArgs(MenuItem.ClickEvent));
            if (window.Surface.Tool != EditorTool.Highlight || (string?)window.PenTool.Tag != "Highlight" ||
                window.PencilCapsuleGlyph.Data.ToString() != window.FindResource("HighlightGlyph").ToString() || window.PenTool.IsChecked != true)
                throw new InvalidOperationException("A pick in the pencil menu must arm the mode and show it on the capsule.");
            window.SelectToolMode(EditorTool.Pen);
            if ((string?)window.PenTool.Tag != "Pen" || window.PencilCapsuleGlyph.Data.ToString() != window.FindResource("PencilGlyph").ToString())
                throw new InvalidOperationException("The P key must put the capsule back on the pencil.");
        }
        finally
        {
            UiLanguage.Current = language;
            UiLanguage.Apply(window, language);
            window.Close();
            if (Directory.Exists(root)) Directory.Delete(root, true);
        }
    }

    // The tooltip of a button is built for real here, template and all: the capsule reads the letter
    // through PlacementTarget, a path nothing else in a smoke run walks, and an empty capsule means
    // the binding fell off, which it does without a word in the binding trace.
    private static string? ShortcutCapsuleText(OverlayEditorWindow window, FrameworkElement target)
    {
        var tooltip = new ToolTip
        {
            Style = (Style)window.FindResource(typeof(ToolTip)),
            PlacementTarget = target,
            Content = target.ToolTip
        };
        tooltip.ApplyTemplate();
        tooltip.Measure(new Size(400, 200));
        var capsule = tooltip.Template?.FindName("KeyCap", tooltip) as Border;
        return (capsule?.Child as TextBlock)?.Text;
    }

    private static IEnumerable<string> PanelStrings(DependencyObject? root)
    {
        var visited = new HashSet<DependencyObject>();
        var found = new List<string>();
        if (root is null) return found;
        void Walk(DependencyObject item)
        {
            if (!visited.Add(item)) return;
            if (item is FrameworkElement { ToolTip: string tip }) found.Add(tip);
            if (item is ContentControl { Content: string caption }) found.Add(caption);
            if (item is TextBlock text) found.Add(text.Text);
            foreach (var child in LogicalTreeHelper.GetChildren(item)) if (child is DependencyObject dependency) Walk(dependency);
            if (item is Visual)
                for (var i = 0; i < VisualTreeHelper.GetChildrenCount(item); i++) Walk(VisualTreeHelper.GetChild(item, i));
        }
        Walk(root);
        return found;
    }

    // The panel itself: the palettes and the five dots that follow them, the thickness button with
    // its presets, and the four ways the inside of a region can be filled. Everything here is
    // pressed the way a hand would press it, without a mouse.
    internal static void RunPanelProbe(CaptureItem source)
    {
        var capture = source.DeepClone();
        var root = Path.Combine(Path.GetTempPath(), "SnapBrief", $"panel-probe-{Guid.NewGuid():N}");
        var workspace = new SessionWorkspace(root);
        var frame = new DesktopFrame(capture.Image, 0, 0, capture.Image.PixelWidth, capture.Image.PixelHeight);
        var window = new OverlayEditorWindow(workspace, frame, 0, capture) { Width = 1280, Height = 720 };
        window.Measure(new Size(1280, 720));
        window.Arrange(new Rect(0, 0, 1280, 720));
        window._cropRect = new Rect(120, 90, 900, 506);
        window.SetupEditor();
        try { PanelChecks(window); }
        finally
        {
            window.AppearancePopup.IsOpen = false;
            window.ThicknessPopup.IsOpen = false;
            window.FillPopup.IsOpen = false;
            window.Close();
            if (Directory.Exists(root)) Directory.Delete(root, true);
        }
    }

    private static void PanelChecks(OverlayEditorWindow window)
    {
        window.SelectToolMode(EditorTool.Rectangle);
        window.OpenAppearance();
        Color Parse(string hex) => (Color)ColorConverter.ConvertFromString(hex);
        void CheckPalette(PaletteSet palette)
        {
            if (window.ColorPalette.Children.OfType<Button>().Select(swatch => (Color)swatch.Tag).SequenceEqual(palette.Colors.Select(Parse)) &&
                window.ColorDots.Children.OfType<Button>().Select(dot => (Color)dot.Tag).SequenceEqual(palette.Quick.Select(Parse))) return;
            throw new InvalidOperationException($"The swatches and the quick dots must both come from the \"{palette.Id}\" palette.");
        }
        // A clean workspace holds no settings file, so the panel starts on the standard palette, and
        // the colour it starts with belongs to it.
        if (window._activePalette.Id != "standard" || !Palettes[0].Colors.Contains($"#{window._activeColor.R:X2}{window._activeColor.G:X2}{window._activeColor.B:X2}"))
            throw new InvalidOperationException("The editor must start on the standard palette with a colour that belongs to it.");
        CheckPalette(Palettes[0]);
        window.SelectPalette(ParseAnnotationPalette("neon"));
        CheckPalette(Palettes.Single(palette => palette.Id == "neon"));
        if (window.NeonPaletteSegment.IsChecked != true || window.StandardPaletteSegment.IsChecked != false)
            throw new InvalidOperationException("The palette segments must show which set is in use.");
        window.SelectPalette(Palettes[0]);

        // The thickness lives on its own button now: a preset reaches the canvas and the button.
        window.OnThicknessPresetClick(window.ThicknessPreset3Segment, new RoutedEventArgs());
        if (window.Surface.ActiveThickness != 6 || (string?)window.ThicknessButton.Content != "6 px" || window.ThicknessPreset3Segment.IsChecked != true)
            throw new InvalidOperationException("A thickness preset must reach the canvas and the button that opens it.");
        double[] PresetRow() => [.. window.ThicknessPresetRow.Children.OfType<System.Windows.Controls.Primitives.ToggleButton>()
            .Select(preset => double.Parse((string)preset.Tag, System.Globalization.CultureInfo.InvariantCulture))];
        if (!ThicknessPresets.SequenceEqual(PresetRow()))
            throw new InvalidOperationException("The thickness popover must offer the four presets.");

        // The highlighter counts in tens of pixels and keeps a width of its own: the button shows the
        // one of the tool in the hand, and switching between the two does not mix them.
        window.SelectToolMode(EditorTool.Highlight);
        window.OnThicknessPresetClick(window.ThicknessPreset4Segment, new RoutedEventArgs());
        if (window.Surface.ActiveThickness != 24 || (string?)window.ThicknessButton.Content != "24 px" ||
            !HighlightThicknessPresets.SequenceEqual(PresetRow()) || window.StrokeSlider.Maximum != MaximumHighlightThickness)
            throw new InvalidOperationException("The highlighter must carry presets, a range and a width of its own.");
        window.SelectToolMode(EditorTool.Pen);
        if (window.Surface.ActiveThickness != 6 || (string?)window.ThicknessButton.Content != "6 px" ||
            !ThicknessPresets.SequenceEqual(PresetRow()) || window.StrokeSlider.Maximum != 16)
            throw new InvalidOperationException("The pencil must keep the thickness it shares with every other stroke.");
        window.SelectToolMode(EditorTool.Highlight);
        if (window.Surface.ActiveThickness != 24)
            throw new InvalidOperationException("Arming the highlighter again must bring its own width back.");
        window.SelectToolMode(EditorTool.Rectangle);

        // The fill has a button and a popover of its own now: the four fills, the twelve swatches of
        // the fill colour, and the switch that hides the outline in the colour popover beside it.
        window.SelectToolMode(EditorTool.Arrow);
        window.OnFillButtonClick(window.FillButton, new RoutedEventArgs());
        // The swatches of the fill are built as the popover opens, the way the colour popover builds
        // its own: a window that was never shown has no surface for the popup itself to appear on.
        if (window.Surface.Tool != EditorTool.Rectangle || window.FillPalette.Children.Count != 12)
            throw new InvalidOperationException("The fill button must arm the region when the fill has nothing to belong to.");
        window.OnFillClick(window.FillBlurSegment, new RoutedEventArgs());
        if (window.Surface.ActiveFill != SnapBrief.Core.Models.AnnotationFill.Blur || window.FillPalette.IsEnabled)
            throw new InvalidOperationException("A region filled with blur must not offer a colour of its own.");
        window.OnFillClick(window.FillSolidSegment, new RoutedEventArgs());
        if (window.Surface.ActiveFill != SnapBrief.Core.Models.AnnotationFill.Solid || !window.FillPalette.IsEnabled)
            throw new InvalidOperationException("A region with a solid fill must offer the colour of that fill.");
        var outlineColor = window.Surface.ActiveColor;
        var blackSwatch = window.FillPalette.Children.OfType<Button>().Single(swatch => (Color)swatch.Tag == Colors.Black);
        blackSwatch.RaiseEvent(new RoutedEventArgs(System.Windows.Controls.Primitives.ButtonBase.ClickEvent));
        if (window.Surface.ActiveFillColor != Colors.Black || window.Surface.ActiveColor != outlineColor ||
            blackSwatch.BorderBrush != Brushes.White)
            throw new InvalidOperationException("A swatch of the fill popover must paint the fill and leave the outline alone.");
        window.FillPopup.IsOpen = false;
        window.OpenAppearance();
        window.OutlineSegment.IsChecked = false;
        window.OnOutlineClick(window.OutlineSegment, new RoutedEventArgs());
        if (window.Surface.ActiveHasOutline || ((SolidColorBrush)window.ColorSwatch.Fill).Color != Colors.Black)
            throw new InvalidOperationException("A region without an outline must show the colour of its fill on the panel.");
        // One click on a panel dot now paints what is actually seen: the fill of a frame without an outline.
        window.ApplyQuickColor(Colors.White);
        if (window.Surface.ActiveFillColor != Colors.White || window.Surface.ActiveColor != outlineColor)
            throw new InvalidOperationException("A dot on the panel must paint the colour the mark actually shows.");
        window.OutlineSegment.IsChecked = true;
        window.OnOutlineClick(window.OutlineSegment, new RoutedEventArgs());
        window.OnFillClick(window.FillNoneSegment, new RoutedEventArgs());

        // A colour reaches a mark only while it is selected; with nothing selected it belongs to the
        // next one and leaves what is already drawn alone.
        if (window._capture!.Annotations.FirstOrDefault(annotation => annotation.Kind == EditorTool.Arrow) is { } drawn)
        {
            window.Surface.SelectAnnotation(drawn.Id);
            window.ApplyPickedColor(Colors.Lime);
            window.Surface.SelectAnnotation(null);
            window.ApplyPickedColor(Colors.Magenta);
            if (drawn.Color != Colors.Lime || window.Surface.ActiveColor != Colors.Magenta)
                throw new InvalidOperationException("A colour picked with nothing selected must belong to the next mark only.");

            // Escape gives up one thing at a time, and the capture is the last of them. The step
            // before these two, an open popover, cannot be reached here: a window that was never
            // shown has no surface for a popup to open on.
            window.Surface.SelectAnnotation(drawn.Id);
            if (window.NextEscapeStep() != EscapeStep.Selection)
                throw new InvalidOperationException("Escape must drop the selection instead of cancelling the capture.");
            window.Surface.SelectAnnotation(null);
            if (window.NextEscapeStep() != EscapeStep.Capture)
                throw new InvalidOperationException("With nothing selected and nothing open, Escape must cancel the capture.");

            // What the eraser does to the window: the canvas removes the mark and reports it, the
            // window turns that into one history entry, and one undo brings the mark back.
            window._capture.Annotations.Remove(drawn);
            window.OnAnnotationChanged(window, EventArgs.Empty);
            if (window._capture.Annotations.Any(annotation => annotation.Id == drawn.Id))
                throw new InvalidOperationException("An erased mark must leave the capture.");
            window.OnUndoClick(window, new RoutedEventArgs());
            if (window._capture.Annotations.All(annotation => annotation.Id != drawn.Id))
                throw new InvalidOperationException("One undo must bring an erased mark back.");
        }

        // The panel keeps its width whatever tool is armed: the thickness button never blanks its
        // caption, and it and the colour circle are both a fixed size.
        var widths = new List<double>();
        foreach (var tool in new[] { EditorTool.Rectangle, EditorTool.Text, EditorTool.Blur, EditorTool.Select, EditorTool.Arrow })
        {
            window.SelectToolMode(tool);
            if (string.IsNullOrWhiteSpace((string?)window.ThicknessButton.Content))
                throw new InvalidOperationException($"The thickness button showed nothing while the {tool} tool was armed.");
            // The fill button carries a word of its own and never blanks either, whatever is armed.
            if (string.IsNullOrWhiteSpace(window.FillButtonLabel.Text) || window.FillButton.Visibility != Visibility.Visible)
                throw new InvalidOperationException($"The fill button showed nothing while the {tool} tool was armed.");
            // The width the panel asks for, not the width it was given: a window that was never
            // shown has no arranged size to read.
            window.Toolbar.InvalidateMeasure();
            window.Toolbar.Measure(new Size(double.PositiveInfinity, double.PositiveInfinity));
            widths.Add(window.Toolbar.DesiredSize.Width);
        }
        if (widths[0] < 100 || widths.Distinct().Count() != 1)
            throw new InvalidOperationException($"The markup panel changed width with the tool: {string.Join(", ", widths)}.");

        // And on a working area narrower than the row, the row wraps instead of running past it:
        // the panel grew by a fill button and a size button, and a tail off the screen takes
        // "Сохранить" and "Готово" with it.
        var oneRow = window.Toolbar.DesiredSize.Height;
        var narrow = Math.Max(200, widths[0] - 120);
        window.Toolbar.MaxWidth = narrow;
        window.Toolbar.InvalidateMeasure();
        window.Toolbar.Measure(new Size(narrow, double.PositiveInfinity));
        var wrapped = window.Toolbar.DesiredSize;
        window.Toolbar.MaxWidth = double.PositiveInfinity;
        window.Toolbar.InvalidateMeasure();
        if (wrapped.Width > narrow + 0.5 || wrapped.Height <= oneRow)
            throw new InvalidOperationException($"The markup panel must wrap into a working area of {narrow}, not run past it: {wrapped}.");
    }

    // The two rules of a click that landed on nothing: beside the capture it finishes the markup,
    // and a press already spent on closing the pill of a note finishes nothing on top of it.
    internal static void RunOutsideClickProbe(CaptureItem source)
    {
        var capture = source.DeepClone();
        var root = Path.Combine(Path.GetTempPath(), "SnapBrief", $"outside-probe-{Guid.NewGuid():N}");
        var workspace = new SessionWorkspace(root);
        var frame = new DesktopFrame(capture.Image, 0, 0, capture.Image.PixelWidth, capture.Image.PixelHeight);
        var window = new OverlayEditorWindow(workspace, frame, 0, capture) { Width = 1280, Height = 720 };
        window.Measure(new Size(1280, 720));
        window.Arrange(new Rect(0, 0, 1280, 720));
        window._cropRect = new Rect(120, 90, 900, 506);
        window.SetupEditor();
        try { OutsideClickChecks(window); }
        finally
        {
            window.Close();
            if (Directory.Exists(root)) Directory.Delete(root, true);
        }
    }

    private static void OutsideClickChecks(OverlayEditorWindow window)
    {
        var beside = new Point(40, 40);
        var inside = new Point(400, 300);
        if (window.TakeOutsideClick(window.DesktopImage, beside) != OutsideClick.Finish)
            throw new InvalidOperationException("A click beside the capture must finish the markup.");
        if (window.TakeOutsideClick(window.DesktopImage, inside) != OutsideClick.Ignore)
            throw new InvalidOperationException("A click on the capture must be left to the canvas.");
        if (window.TakeOutsideClick(window.Surface, beside) != OutsideClick.Ignore)
            throw new InvalidOperationException("Only a click on the desktop behind the capture finishes the markup.");

        // The pill of a note is open: the press beside it closes the pill and is spent on that, and
        // only the next click finishes the markup.
        var annotation = new AnnotationItem { Kind = EditorTool.Rectangle, Points = [new Point(120, 120), new Point(260, 220)], Note = "Заметка" };
        window._capture!.Annotations.Add(annotation);
        window._visibleChipIds.Add(annotation.Id);
        window.AddChip(annotation, focus: true);
        window.PressBesideEditors(window.DesktopImage);
        if (window._expandedChipId is not null)
            throw new InvalidOperationException("A press beside an open note pill must finish what is being typed in it.");
        if (window.TakeOutsideClick(window.DesktopImage, beside) != OutsideClick.Spent)
            throw new InvalidOperationException("The click that closed a note pill must not finish the markup as well.");
        if (window.TakeOutsideClick(window.DesktopImage, beside) != OutsideClick.Finish)
            throw new InvalidOperationException("The next click beside the capture must finish the markup again.");
    }

    // The comments panel of a capture reopened from the strip, with the checks that used to live in
    // the preview window: an empty note claims no number, the numbers close the gap after a
    // deletion and match the export, the list carries a large capture, and a click on a row selects
    // the same mark on the picture.
    internal static void RunCommentsPanelProbe(CaptureItem source)
    {
        var capture = new CaptureItem
        {
            Id = source.Id, Image = source.Image, SourcePath = source.SourcePath, DisplayLabel = source.DisplayLabel
        };
        capture.Annotations.Add(new AnnotationItem
        {
            Kind = EditorTool.Rectangle, Points = [new Point(10, 10), new Point(80, 80)], Note = "Первый"
        });
        capture.Annotations.Add(new AnnotationItem
        {
            Kind = EditorTool.Comment, Points = [new Point(40, 40), new Point(48, 48)]
        });
        var root = Path.Combine(Path.GetTempPath(), "SnapBrief", $"comments-probe-{Guid.NewGuid():N}");
        var workspace = new SessionWorkspace(root);
        var frame = new DesktopFrame(capture.Image, 0, 0, capture.Image.PixelWidth, capture.Image.PixelHeight);
        var window = new OverlayEditorWindow(workspace, frame, 0, capture) { Width = 1280, Height = 720 };
        window.Measure(new Size(1280, 720));
        window.Arrange(new Rect(0, 0, 1280, 720));
        window._cropRect = new Rect(120, 90, 900, 506);
        window.SetupEditor();
        // A capture taken just now has no notes and no panel: the same window, the other case.
        var fresh = new OverlayEditorWindow(workspace, frame, 0, null) { Width = 1280, Height = 720 };
        try
        {
            if (fresh._commentsPanelVisible || fresh.CommentsPanel.Visibility != Visibility.Collapsed)
                throw new InvalidOperationException("A freshly taken capture must not show the comments panel.");
            CommentsPanelChecks(window);
        }
        finally
        {
            fresh.Close();
            window.Close();
            if (Directory.Exists(root)) Directory.Delete(root, true);
        }
    }

    private static void CommentsPanelChecks(OverlayEditorWindow window)
    {
        var capture = window._capture!;
        if (!window._commentsPanelVisible || window.CommentsPanel.Visibility != Visibility.Visible)
            throw new InvalidOperationException("A capture reopened with notes must show the comments panel.");
        if (window.Surface.Tool != EditorTool.Select || window.SelectTool.IsChecked != true || window.RectangleTool.IsChecked == true)
            throw new InvalidOperationException("A capture reopened from the strip must open on the select tool.");
        var monitor = window.GetCropMonitorWorkArea();
        if (monitor.Width > 900 && window.LayoutWorkArea().Right > monitor.Right - CommentsPanelWidth)
            throw new InvalidOperationException("The markup must be laid out to the left of the comments panel.");

        Controls.CommentListEntry Row(Guid id) =>
            window.CommentsList.Children.OfType<Controls.CommentListEntry>().Single(entry => entry.AnnotationId == id);
        var blank = capture.Annotations.Single(annotation => annotation.Kind == EditorTool.Comment);
        var marked = capture.Annotations.Single(annotation => annotation.Kind == EditorTool.Rectangle);
        if (Row(blank.Id).Label != "+")
            throw new InvalidOperationException("An empty comment must not claim an export label.");
        blank.Note = "Второй";
        window.RefreshLabels();
        var expectedSecond = CaptureLabels.ForNotedAnnotations(capture.DisplayLabel, capture.ToCore()).Last().DisplayLabel;
        if (Row(blank.Id).Label != expectedSecond || Row(blank.Id).Text != "Второй")
            throw new InvalidOperationException("The panel and the export must number the notes alike.");

        window.DeleteAnnotationNote(marked);
        var expectedFirst = CaptureLabels.ForNotedAnnotations(capture.DisplayLabel, capture.ToCore()).Single().DisplayLabel;
        var remaining = window.CommentsList.Children.OfType<Controls.CommentListEntry>().Single();
        if (remaining.Label != expectedFirst)
            throw new InvalidOperationException("The numbers of the panel must close the gap after a deletion.");

        window.ActivateCommentRow(remaining.AnnotationId);
        if (window.Surface.SelectedAnnotation?.Id != blank.Id || !remaining.IsCurrent)
            throw new InvalidOperationException("A click on a row must select the same mark and mark the row.");
        window.Surface.SelectAnnotation(null);
        if (remaining.IsCurrent)
            throw new InvalidOperationException("The highlight of the panel must follow the selection both ways.");

        for (var i = 0; i < 299; i++)
            capture.Annotations.Add(new AnnotationItem
            {
                Kind = EditorTool.Comment, Points = [new Point(50, 50), new Point(58, 58)], Note = $"Комментарий {i + 2}"
            });
        window.RefreshLabels();
        if (window.CommentsList.Children.Count != 300 || window.CommentsEmpty.Visibility != Visibility.Collapsed)
            throw new InvalidOperationException("The comments panel truncated a large capture.");
    }

    // A caption on the capture: placed by one click with the word of the interface selected whole,
    // typed over, finished, given up on, retyped by a double click and sized by the panel. The pill
    // of a comment has nothing to do with it any more.
    internal static void RunTextMarkProbe(CaptureItem source)
    {
        var capture = source.DeepClone();
        capture.Annotations.Clear();
        var root = Path.Combine(Path.GetTempPath(), "SnapBrief", $"text-probe-{Guid.NewGuid():N}");
        var workspace = new SessionWorkspace(root);
        var frame = new DesktopFrame(capture.Image, 0, 0, capture.Image.PixelWidth, capture.Image.PixelHeight);
        var window = new OverlayEditorWindow(workspace, frame, 0, capture) { Width = 1280, Height = 720 };
        window.Measure(new Size(1280, 720));
        window.Arrange(new Rect(0, 0, 1280, 720));
        window._cropRect = new Rect(120, 90, 900, 506);
        window.SetupEditor();
        try { TextMarkChecks(window); }
        finally
        {
            window.FontSizePopup.IsOpen = false;
            window.Close();
            if (Directory.Exists(root)) Directory.Delete(root, true);
        }
    }

    private static void TextMarkChecks(OverlayEditorWindow window)
    {
        var capture = window._capture!;
        var word = UiLanguage.Text("Текст");
        AnnotationItem Place(double x, double y)
        {
            var mark = new AnnotationItem { Kind = EditorTool.Text, Points = [new Point(x, y)], Text = word, FontSize = 20 };
            TextMarkMetrics.Fit(mark);
            capture.Annotations.Add(mark);
            window.OnAnnotationCreated(window, mark);
            return mark;
        }

        window.SelectToolMode(EditorTool.Text);
        if (!window.FontSizeButton.IsEnabled || string.IsNullOrWhiteSpace((string?)window.FontSizeButton.Content))
            throw new InvalidOperationException("The size of the letters must be offered while the text tool is armed.");
        var caption = Place(100, 100);
        if (!window.IsEditingText || window._textEditor.Visibility != Visibility.Visible || window._textEditor.SelectedText != word)
            throw new InvalidOperationException("Placing a caption must open a text box on the capture with the word selected whole.");
        if (window.ChipLayer.Children.Count != 0)
            throw new InvalidOperationException("A caption must be typed on the capture, not in the pill of a comment.");
        window._textEditor.Text = "Привет";
        if (caption.Text != "Привет" || caption.Points[1].X - caption.Points[0].X < 10)
            throw new InvalidOperationException("What is typed must reach the mark and the box its letters take.");
        window.CommitTextEdit();
        if (window.IsEditingText || !capture.Annotations.Contains(caption) || window.Surface.EditingTextId is not null)
            throw new InvalidOperationException("Finishing a caption must close the text box and leave the words on the capture.");

        // The size comes from the panel, and the box of the mark follows it.
        window.Surface.SelectAnnotation(caption.Id);
        var height = caption.Points[1].Y - caption.Points[0].Y;
        window.OnFontSizePresetClick(window.FontSize5Segment, new RoutedEventArgs());
        if (caption.FontSize != 32 || caption.Points[1].Y - caption.Points[0].Y <= height ||
            (string?)window.FontSizeButton.Content != "32 px")
            throw new InvalidOperationException("A size picked on the panel must reach the caption and the box it takes.");
        window.Surface.SelectAnnotation(null);

        // A caption given up on leaves nothing behind: neither the mark nor an entry in the history.
        var undoDepth = window._undo.Count;
        var abandoned = Place(300, 200);
        window.CancelTextEdit();
        if (window.IsEditingText || capture.Annotations.Contains(abandoned) || window._undo.Count != undoDepth)
            throw new InvalidOperationException("Escape on a fresh caption must take the mark and its history entry with it.");
        // And neither does one finished with nothing in it.
        var blank = Place(320, 240);
        window._textEditor.Text = "   ";
        window.CommitTextEdit();
        if (capture.Annotations.Contains(blank) || window._undo.Count != undoDepth)
            throw new InvalidOperationException("A caption finished with nothing in it must not stay on the capture.");

        // A capture reopened from the strip: the caption carries its words without a pill, and a
        // double click on the letters opens it for retyping instead of placing a second one.
        window.RebuildChips();
        if (window.ChipLayer.Children.Count != 0 || capture.Annotations.Single().Text != "Привет")
            throw new InvalidOperationException("A caption read back must keep its words and claim no pill.");
        window.OnAnnotationActivated(window, caption);
        if (!window.IsEditingText || window._textEditor.Text != "Привет" || window._textEditor.SelectedText.Length != 0)
            throw new InvalidOperationException("A double click on a caption must open it with the caret in it, not over the whole word.");
        window.CommitTextEdit();

        // Retyping a caption that was already there is one entry of the history, and one Ctrl+Z
        // brings the old words back instead of undoing whatever was done before the caption.
        var depthBeforeRetyping = window._undo.Count;
        window.OnAnnotationActivated(window, caption);
        window._textEditor.Text = "Пока";
        window.CommitTextEdit();
        if (window._undo.Count != depthBeforeRetyping + 1 || caption.Text != "Пока")
            throw new InvalidOperationException("Retyping a caption must leave one entry in the history.");
        window.OnUndoClick(window, new RoutedEventArgs());
        if (window._capture!.Annotations.Single().Text != "Привет" || window._undo.Count != depthBeforeRetyping)
            throw new InvalidOperationException("One undo after retyping a caption must bring the old words back.");
        // And retyping it into the same words is nothing to undo at all.
        window.OnAnnotationActivated(window, window._capture.Annotations.Single());
        window.CommitTextEdit();
        if (window._undo.Count != depthBeforeRetyping)
            throw new InvalidOperationException("A caption opened and left as it was must not fill the history.");

        window.SelectToolMode(EditorTool.Rectangle);
        if (window.FontSizeButton.IsEnabled || string.IsNullOrWhiteSpace((string?)window.FontSizeButton.Content))
            throw new InvalidOperationException("The size of the letters belongs to captions alone, and its caption never blanks.");
    }

    internal static CaptureItem RunNoteAffordanceProbe(CaptureItem source)
    {
        var capture = source.DeepClone();
        capture.Annotations.Clear();
        var annotation = new AnnotationItem
        {
            Kind = EditorTool.Arrow,
            Points = [new Point(source.Image.PixelWidth * .2, source.Image.PixelHeight * .2), new Point(source.Image.PixelWidth * .55, source.Image.PixelHeight * .48)],
            Color = Color.FromRgb(47, 140, 255),
            Thickness = 4
        };
        capture.Annotations.Add(annotation);
        var root = Path.Combine(Path.GetTempPath(), "SnapBrief", $"note-probe-{Guid.NewGuid():N}");
        var workspace = new SessionWorkspace(root);
        var frame = new DesktopFrame(capture.Image, 0, 0, capture.Image.PixelWidth, capture.Image.PixelHeight);
        var window = new OverlayEditorWindow(workspace, frame, 0, capture) { Width = 1280, Height = 720 };
        window.Measure(new Size(1280, 720));
        window.Arrange(new Rect(0, 0, 1280, 720));
        window._cropRect = new Rect(120, 90, 900, 506);
        window.SetupEditor();
        // The window and its temporary workspace belong to the probe alone: both go away even when a
        // check below throws, so a failed smoke run leaves nothing behind either.
        try { return NoteAffordanceChecks(window); }
        finally
        {
            window.Close();
            if (Directory.Exists(root)) Directory.Delete(root, true);
        }
    }

    private static CaptureItem NoteAffordanceChecks(OverlayEditorWindow window)
    {
        var workingAnnotation = window._capture!.Annotations[0];
        window.Surface.SelectAnnotation(workingAnnotation.Id);
        window.OnCommentClick(window.CommentToolButton, new RoutedEventArgs());
        if (window.Surface.Tool != EditorTool.Comment)
            throw new InvalidOperationException("The comment command did not arm placement.");
        var comment = new AnnotationItem { Kind = EditorTool.Comment, Points = [new Point(200, 150), new Point(208, 158)] };
        window._capture.Annotations.Add(comment);
        window.OnAnnotationCreated(window, comment);
        if (window.Surface.Tool != EditorTool.Select || window.SelectTool.IsChecked != true)
            throw new InvalidOperationException("Comment placement remained armed after creating one pin.");
        var note = window.ChipLayer.Children.OfType<Border>()
            .Select(border => border.Child).OfType<Grid>()
            .SelectMany(grid => grid.Children.OfType<TextBox>()).Single();
        note.Text = "Контекстная заметка";
        if (comment.Note != note.Text || comment.ParentAnnotationId != workingAnnotation.Id || window.ChipLayer.Children.Count != 1)
            throw new InvalidOperationException("The one-shot comment did not bind its editor to the selected annotation.");

        window.Surface.SelectAnnotation(workingAnnotation.Id);
        window.OnCommentClick(window.CommentToolButton, new RoutedEventArgs());
        var secondComment = new AnnotationItem { Kind = EditorTool.Comment, Points = [new Point(200, 150), new Point(208, 158)] };
        window._capture.Annotations.Add(secondComment);
        window.OnAnnotationCreated(window, secondComment);
        var secondChip = window.ChipLayer.Children.OfType<Border>().Single(border => border.Tag is Guid id && id == secondComment.Id);
        ((Grid)secondChip.Child).Children.OfType<TextBox>().Single().Text = "Второй комментарий";
        window.Root.UpdateLayout();
        window.RepositionChips();
        var firstChip = window.ChipLayer.Children.OfType<Border>().Single(border => border.Tag is Guid id && id == comment.Id);
        if (firstChip.Width != 43 || secondChip.Width != 270 || Panel.GetZIndex(secondChip) <= Panel.GetZIndex(firstChip))
            throw new InvalidOperationException("Opening a comment did not collapse and lower the other chips.");
        var firstRect = new Rect(Canvas.GetLeft(firstChip), Canvas.GetTop(firstChip), firstChip.Width, Math.Max(40, firstChip.ActualHeight));
        var secondRect = new Rect(Canvas.GetLeft(secondChip), Canvas.GetTop(secondChip), secondChip.Width, Math.Max(40, secondChip.ActualHeight));
        if (firstRect.IntersectsWith(secondRect))
            throw new InvalidOperationException("Overlapping comment anchors produced overlapping chip controls.");
        window.DeleteAnnotationNote(secondComment);

        _ = window.Surface.RenderAnnotated();
        window.Surface.SelectAnnotation(workingAnnotation.Id);
        var oldColor = workingAnnotation.Color;
        var oldThickness = workingAnnotation.Thickness;
        window._appearanceBefore = window.SnapshotState();
        window.ApplyAppearance(Colors.Red, 14);
        window.ApplyAppearance(null, 2);
        if (workingAnnotation.Color != Colors.Red || workingAnnotation.Thickness != 2)
            throw new InvalidOperationException("Appearance changes must update the selected annotation in both slider directions.");
        window.OnAppearanceClosed(window, EventArgs.Empty);
        window.OnUndoClick(window, new RoutedEventArgs());
        var restoredAnnotation = window._capture.Annotations.Single(a => a.Id == workingAnnotation.Id);
        if (restoredAnnotation.Color != oldColor || restoredAnnotation.Thickness != oldThickness)
            throw new InvalidOperationException("One undo must restore the appearance from before the property edit.");
        var reopenedNoteChip = window.ChipLayer.Children.OfType<Border>().Single(b => b.Tag is Guid id && id == comment.Id);
        var reopenedNoteInput = ((Grid)reopenedNoteChip.Child).Children.OfType<TextBox>().Single();
        if (reopenedNoteInput.Text != "Контекстная заметка" || reopenedNoteInput.Visibility != Visibility.Collapsed)
            throw new InvalidOperationException("Restored comments must retain their text in a collapsed chip.");

        // The pill of a note is dragged by its badge: the badge on the picture follows it, one undo
        // puts both back, and the capture the probe returns carries a moved badge for the export.
        var noteComment = window._capture.Annotations.Single(a => a.Id == comment.Id);
        window.BeginNoteDrag(noteComment, new Point(0, 0));
        window.DragNoteTo(new Point(60, -40));
        if (!window.EndNoteDrag() || noteComment.NoteOffset is null)
            throw new InvalidOperationException("Dragging a note pill did not move the badge of its comment.");
        window.OnUndoClick(window, new RoutedEventArgs());
        var afterUndo = window._capture.Annotations.Single(a => a.Id == comment.Id);
        if (afterUndo.NoteOffset is not null)
            throw new InvalidOperationException("One undo must put a dragged note pill back where it was.");
        window.BeginNoteDrag(afterUndo, new Point(0, 0));
        window.DragNoteTo(new Point(60, -40));
        window.EndNoteDrag();

        window.SelectToolMode(EditorTool.Rectangle);
        var blankRectangle = new AnnotationItem { Kind = EditorTool.Rectangle, Points = [new Point(320, 200), new Point(460, 300)] };
        window._capture.Annotations.Add(blankRectangle);
        window.OnAnnotationCreated(window, blankRectangle);
        if (!window._chipFinishers.TryGetValue(blankRectangle.Id, out var finishBlank))
            throw new InvalidOperationException("A new rectangle did not open its optional note editor.");
        finishBlank();
        if (!window._capture.Annotations.Contains(blankRectangle) || window.ChipLayer.Children.OfType<Border>().Any(border => border.Tag is Guid id && id == blankRectangle.Id))
            throw new InvalidOperationException("Leaving an optional rectangle note blank did not remove only its extra chip.");

        var result = window._capture.DeepClone();
        if (result.Annotations.Count(item => item.Kind == EditorTool.Comment && !string.IsNullOrWhiteSpace(item.Note)) != 1)
            throw new InvalidOperationException("The comment probe left an unintended extra comment.");
        return result;
    }

    private void OnSourceInitialized(object? sender, EventArgs e)
    {
        var handle = new WindowInteropHelper(this).Handle;
        SetWindowPos(handle, new IntPtr(-1), _frame.Left, _frame.Top, _frame.PixelWidth, _frame.PixelHeight, 0x0010 | 0x0040);
    }

    private void OnLoaded(object sender, RoutedEventArgs e)
    {
        UpdateShade();
        UiLanguage.Apply(this, _workspace.Preferences.Language);
        Activate();
        Focus();
        if (_capture is null) { RestoreLastRegion(); return; }
        var monitor = WinForms.Screen.FromPoint(WinForms.Cursor.Position).WorkingArea;
        var work = WithoutCommentsStrip(new Rect(
            (monitor.Left - _frame.Left) * ActualWidth / _frame.PixelWidth, (monitor.Top - _frame.Top) * ActualHeight / _frame.PixelHeight,
            monitor.Width * ActualWidth / _frame.PixelWidth, monitor.Height * ActualHeight / _frame.PixelHeight), _commentsPanelVisible);
        var maxWidth = work.Width * .78;
        var maxHeight = work.Height * .72;
        var scale = Math.Min(maxWidth / _capture.Image.PixelWidth, maxHeight / _capture.Image.PixelHeight);
        var width = _capture.Image.PixelWidth * scale;
        var height = _capture.Image.PixelHeight * scale;
        _cropRect = new Rect(work.Left + (work.Width - width) / 2, work.Top + (work.Height - height) / 2, width, height);
        SetupEditor();
    }

    // What a release of the button means for the shot: nothing at all, a press that was already
    // spent on closing something beside the capture, or "Done". A click on an empty part of the
    // capture never gets here, it belongs to the canvas, which drops the selection and draws nothing.
    internal enum OutsideClick { Ignore, Spent, Finish }

    internal OutsideClick TakeOutsideClick(object? source, Point point)
    {
        // Only the desktop behind the capture answers here: the shade is not hit testable and the
        // markup layer has no background of its own, so anything else means the press landed
        // somewhere with a meaning of its own.
        var click = _capture is null || _busyCrop || source is not Image || _cropRect.Contains(point)
            ? OutsideClick.Ignore
            : _outsideClickConsumed ? OutsideClick.Spent : OutsideClick.Finish;
        _outsideClickConsumed = false;
        return click;
    }

    // A press beside the capture finishes what is being typed there first, and is spent on that:
    // the release that follows it must not close the editor on top of it.
    internal void PressBesideEditors(DependencyObject? source)
    {
        _outsideClickConsumed = (_expandedChipId is not null || IsEditingText) &&
            !IsInsideChipLayer(source) && !IsInside(source, _textEditor);
        CommitTextEditIfOutside(source);
        FinishExpandedChipIfOutside(source);
    }

    private void OnWindowMouseDown(object sender, MouseButtonEventArgs e)
    {
        PressBesideEditors(e.OriginalSource as DependencyObject);
        if (_busyCrop || _closed || _capture is not null) return;
        if (!_isNew || _capture is not null || e.OriginalSource is not Image) return;
        _selectionStart = e.GetPosition(this);
        _cropRect = new Rect(_selectionStart.Value, _selectionStart.Value);
        CaptureMouse();
        UpdateCropVisual();
    }

    private void OnWindowMouseMove(object sender, MouseEventArgs e)
    {
        if (_selectionStart is null || e.LeftButton != MouseButtonState.Pressed) return;
        var point = e.GetPosition(this);
        _cropRect = Normalize(_selectionStart.Value, point);
        UpdateCropVisual();
    }

    private async void OnWindowMouseUp(object sender, MouseButtonEventArgs e)
    {
        if (_selectionStart is null)
        {
            // A click beside the capture finishes the markup again. A click on an empty part of the
            // capture drops the selection instead, and that one belongs to the canvas: it never
            // reaches this handler.
            var click = TakeOutsideClick(e.OriginalSource, e.GetPosition(this));
            if (click == OutsideClick.Ignore) return;
            e.Handled = true;
            if (click == OutsideClick.Finish) { ClosePopovers(); Complete(false); }
            return;
        }
        _cropRect = Normalize(_selectionStart.Value, e.GetPosition(this));
        UpdateCropVisual();
        ReleaseMouseCapture();
        _selectionStart = null;
        if (_cropRect.Width < 12 || _cropRect.Height < 12) { _cropRect = Rect.Empty; UpdateCropVisual(); return; }
        try
        {
            _busyCrop = true;
            var scaleX = _frame.Image.PixelWidth / ActualWidth;
            var scaleY = _frame.Image.PixelHeight / ActualHeight;
            var rect = new Int32Rect(
                Math.Clamp((int)Math.Round(_cropRect.X * scaleX), 0, _frame.Image.PixelWidth - 1),
                Math.Clamp((int)Math.Round(_cropRect.Y * scaleY), 0, _frame.Image.PixelHeight - 1),
                Math.Max(1, (int)Math.Round(_cropRect.Width * scaleX)),
                Math.Max(1, (int)Math.Round(_cropRect.Height * scaleY)));
            if (rect.X + rect.Width > _frame.Image.PixelWidth) rect.Width = _frame.Image.PixelWidth - rect.X;
            if (rect.Y + rect.Height > _frame.Image.PixelHeight) rect.Height = _frame.Image.PixelHeight - rect.Y;
            var crop = new CroppedBitmap(_frame.Image, rect);
            crop.Freeze();
            _capture = await _workspace.AddImageAsync(crop);
            _createdSourcePaths.Add(_capture.SourcePath);
            if (_closed) { DeleteCreatedSourcesExcept(null); return; }
            _capture.DisplayLabel = CaptureLabels.ForIndex(_captureIndex);
            SetupEditor();
        }
        catch (Exception ex)
        {
            Hint.Visibility = Visibility.Visible;
            ((TextBlock)Hint.Child).Text = $"Не удалось сохранить снимок: {ex.Message}";
        }
        finally { _busyCrop = false; }
    }

    private void SetupEditor()
    {
        if (_capture is null) return;
        _settingUp = true;
        Cursor = Cursors.Arrow;
        CropBorder.Visibility = Visibility.Visible;
        Canvas.SetLeft(CropBorder, _cropRect.Left);
        Canvas.SetTop(CropBorder, _cropRect.Top);
        CropBorder.Width = _cropRect.Width;
        CropBorder.Height = _cropRect.Height;
        Surface.Image = _capture.Image;
        Surface.Annotations = _capture.Annotations;
        // A fresh capture opens ready to draw a region; a capture reopened from the strip opens on
        // the select tool, because its marks are there to be read and adjusted.
        Surface.Tool = _isNew ? EditorTool.Rectangle : EditorTool.Select;
        foreach (var button in ToolButtons)
            button.IsChecked = string.Equals(button.Tag?.ToString(), Surface.Tool.ToString(), StringComparison.Ordinal);
        // The whole panel starts from the settings file, so the sync below shows what the next mark
        // will really look like.
        Surface.ActiveColor = _activeColor;
        Surface.ActiveThickness = ActiveThicknessFor(Surface.Tool);
        Surface.ActiveShape = _activeShape;
        Surface.ActiveFill = _activeFill;
        Surface.ActiveFillColor = _activeFillColor;
        Surface.ActiveHasOutline = _activeHasOutline;
        Surface.ActiveFontSize = _activeFontSize;
        // A caption read out of a session carries the anchor and the size, and the box it takes is
        // measured from them here, once, before anything asks what it covers.
        foreach (var annotation in _capture.Annotations) TextMarkMetrics.Fit(annotation);
        SyncAppearance();
        Hint.Visibility = Visibility.Collapsed;
        Toolbar.Visibility = Visibility.Visible;
        ShotNoteChip.Visibility = Visibility.Collapsed;
        ShotNoteBox.Text = _capture.Note;
        ShotLabel.Text = string.Format(UiLanguage.Text("СНИМОК {0}"), _capture.DisplayLabel);
        UpdateCaptureHandles();
        PositionShotNote();
        foreach (var annotation in _capture.Annotations) annotation.PropertyChanged += OnAnnotationPropertyChanged;
        _lastSnapshot = SnapshotState();
        RefreshLabels();
        RebuildChips();
        UpdateShade();
        PositionCommentsPanel();
        SyncCommentsPanel();
        _settingUp = false;
        Dispatcher.BeginInvoke(() => { PositionCommentsPanel(); PositionToolbar(); PositionShotNote(); RepositionChips(); ResizeTextEditor(); }, DispatcherPriority.Loaded);
    }

    private void UpdateCropVisual()
    {
        if (_cropRect.Width > 0)
        {
            CropBorder.Visibility = Visibility.Visible;
            Canvas.SetLeft(CropBorder, _cropRect.Left);
            Canvas.SetTop(CropBorder, _cropRect.Top);
            CropBorder.Width = _cropRect.Width;
            CropBorder.Height = _cropRect.Height;
        }
        else CropBorder.Visibility = Visibility.Collapsed;
        UpdateCaptureHandles();
        UpdateShade();
    }

    private void UpdateShade()
    {
        _shadeOuter.Rect = new Rect(0, 0, ActualWidth, ActualHeight);
        _shadeHole.Rect = _cropRect.Width > 0 && _cropRect.Height > 0 ? _cropRect : Rect.Empty;
    }

    private System.Windows.Controls.Primitives.ToggleButton[] ToolButtons =>
        [SelectTool, RectangleTool, ArrowTool, PenTool, TextTool, EraserTool, BlurTool, CropTool];

    // Every letter on the panel comes from EditorShortcuts: the name goes to the tooltip (and is
    // translated with the rest of the window), the key goes to the capsule of the tooltip template.
    private void ApplyShortcutHints()
    {
        foreach (var button in ToolButtons)
            if (Enum.TryParse<EditorTool>(button.Tag?.ToString(), out var tool) && EditorShortcuts.Find(tool) is { } shortcut)
                Hint(button, shortcut.Name, shortcut.Caption);
        if (EditorShortcuts.Find(EditorTool.Comment) is { } comment) Hint(CommentToolButton, comment.Name, comment.Caption);
        foreach (var (element, name) in new (FrameworkElement Element, string Name)[]
                 { (UndoButton, "Отменить"), (RedoButton, "Повторить"), (SaveImageButton, "Сохранить на компьютер"), (DoneButton, "Готово") })
            // A renamed action leaves the button without a capsule instead of throwing the editor
            // window away in its constructor.
            Hint(element, name, EditorShortcuts.Actions.FirstOrDefault(action => action.Name == name).Caption);
        foreach (var shortcut in EditorShortcuts.Tools) SheetTools.Children.Add(SheetRow(shortcut.Name, shortcut.Caption));
        foreach (var (caption, name) in EditorShortcuts.Actions) SheetActions.Children.Add(SheetRow(name, caption));

        // Uid carries the letter to the capsule of the tooltip template; the app has no other use
        // for it, and a path without a prefix is the only one a style of a resource dictionary can
        // still resolve when the tooltip is built.
        static void Hint(FrameworkElement element, string name, string? key)
        {
            element.ToolTip = name;
            element.Uid = key ?? string.Empty;
        }
    }

    private static Grid SheetRow(string name, string key)
    {
        var row = new Grid { Margin = new Thickness(0, 0, 0, 6) };
        row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        var title = new TextBlock { Text = name, VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(0, 0, 18, 0) };
        var capsule = new Border
        {
            Padding = new Thickness(6, 1, 6, 1), CornerRadius = new CornerRadius(5),
            Background = new SolidColorBrush(Color.FromRgb(37, 44, 54)),
            BorderBrush = new SolidColorBrush(Color.FromRgb(70, 83, 102)), BorderThickness = new Thickness(1),
            VerticalAlignment = VerticalAlignment.Center,
            Child = new TextBlock { Text = key, FontSize = 11, FontWeight = FontWeights.SemiBold, Foreground = new SolidColorBrush(Color.FromRgb(185, 195, 209)) }
        };
        Grid.SetColumn(capsule, 1);
        row.Children.Add(title);
        row.Children.Add(capsule);
        return row;
    }

    private void OnShortcutSheetClick(object sender, RoutedEventArgs e) => ShortcutSheetPopup.IsOpen = !ShortcutSheetPopup.IsOpen;

    private void OnToolClick(object sender, RoutedEventArgs e)
    {
        if (sender is not System.Windows.Controls.Primitives.ToggleButton selected || !Enum.TryParse<EditorTool>(selected.Tag?.ToString(), out var tool)) return;
        Surface.SelectAnnotation(null);
        Surface.Tool = tool;
        SyncAppearance();
        foreach (var button in ToolButtons)
            button.IsChecked = ReferenceEquals(button, selected);
    }

    private void OnColorClick(object sender, RoutedEventArgs e) => OpenAppearance();
    private void OnThicknessClick(object sender, RoutedEventArgs e) => OpenThickness();

    private void SelectToolMode(EditorTool tool)
    {
        if (tool is EditorTool.Pen or EditorTool.Highlight) SetPencilMode(tool);
        Surface.SelectAnnotation(null);
        Surface.Tool = tool;
        SyncAppearance();
        foreach (var button in ToolButtons)
            button.IsChecked = string.Equals(button.Tag?.ToString(), tool.ToString(), StringComparison.Ordinal);
        Surface.Focus();
    }

    // The capsule carries the mode in its own Tag, so one button stands for both the pen and the
    // highlighter: the tool click, the P and H keys and the menu all come through here.
    private void SetPencilMode(EditorTool tool)
    {
        _appearanceDefaultsChanged |= tool != _activePencil;
        _activePencil = tool;
        PenTool.Tag = tool.ToString();
        PencilCapsuleGlyph.Data = (Geometry)FindResource(tool == EditorTool.Highlight ? "HighlightGlyph" : "PencilGlyph");
        if (EditorShortcuts.Find(tool) is { } shortcut)
        {
            PenTool.ToolTip = UiLanguage.Text(shortcut.Name);
            PenTool.Uid = shortcut.Caption;
        }
    }

    private void OnAnnotationCreated(object sender, AnnotationItem annotation)
    {
        if (_capture is null) return;
        if (annotation.Kind == EditorTool.Comment)
        {
            annotation.ParentAnnotationId = _commentParentId;
            _commentParentId = null;
            annotation.Points[1] = new Point(Math.Min(_capture.Image.PixelWidth, annotation.Points[0].X + 8), Math.Min(_capture.Image.PixelHeight, annotation.Points[0].Y + 8));
            SelectToolMode(EditorTool.Select);
        }
        PushHistory();
        annotation.PropertyChanged += OnAnnotationPropertyChanged;
        RefreshLabels();
        // A caption is typed on the capture itself; everything else that carries a note opens a pill.
        if (annotation.Kind == EditorTool.Text) BeginTextEdit(annotation, selectAll: true, isNew: true);
        else if (annotation.Kind is EditorTool.Rectangle or EditorTool.Comment)
        {
            _visibleChipIds.Add(annotation.Id);
            AddChip(annotation, focus: true);
        }
    }

    private void OnSelectionChanged(object sender, AnnotationItem? annotation)
    {
        SyncAppearance();
        UpdateNoteButton();
        HighlightCommentRow(annotation?.Id);
        if (Mouse.LeftButton == MouseButtonState.Pressed) return;
        RepositionChips();
    }

    // A double click on a caption opens it for retyping, with the caret where the word already is
    // rather than over the whole of it: it is being corrected, not replaced.
    private void OnAnnotationActivated(object sender, AnnotationItem annotation)
    {
        if (annotation.Kind == EditorTool.Text) BeginTextEdit(annotation, selectAll: false, isNew: false);
        else OpenAnnotationNote(annotation);
    }

    // One double click too many opens the note of a mark: the text editor of a text mark, the note
    // pill of anything else. The compact "+" beside a selected mark takes the same path.
    private void OpenAnnotationNote(AnnotationItem annotation)
    {
        if (_capture is null || !_capture.Annotations.Contains(annotation)) return;
        Surface.SelectAnnotation(annotation.Id);
        if (ChipLayer.Children.OfType<Border>().FirstOrDefault(border => border.Tag is Guid id && id == annotation.Id) is { Child: Grid grid } chip)
        {
            chip.Visibility = Visibility.Visible;
            if (_chipExpanders.TryGetValue(annotation.Id, out var expand)) expand(true);
            grid.Children.OfType<TextBox>().First().Focus();
        }
        else
        {
            _visibleChipIds.Add(annotation.Id);
            AddChip(annotation, focus: true);
        }
        UpdateNoteButton();
    }

    // A note is one click away from a selected mark, without hunting for an icon on the panel.
    private void InitializeNoteButton()
    {
        _addNoteButton.Style = (Style)FindResource("OverlayButton");
        _addNoteButton.Width = _addNoteButton.Height = _addNoteButton.MinWidth = 24;
        _addNoteButton.Padding = new Thickness(0);
        _addNoteButton.Margin = new Thickness(0);
        _addNoteButton.Background = new SolidColorBrush(Color.FromArgb(244, 23, 26, 32));
        _addNoteButton.Visibility = Visibility.Collapsed;
        _addNoteButton.ToolTip = UiLanguage.Text("Добавить комментарий");
        _addNoteButton.Content = new System.Windows.Shapes.Path
        {
            Stroke = new SolidColorBrush(Color.FromRgb(217, 222, 232)), StrokeThickness = 1.6,
            StrokeStartLineCap = PenLineCap.Round, StrokeEndLineCap = PenLineCap.Round,
            Data = Geometry.Parse("M5,0 L5,10 M0,5 L10,5")
        };
        System.Windows.Automation.AutomationProperties.SetName(_addNoteButton, UiLanguage.Text("Добавить комментарий"));
        _addNoteButton.Click += (_, _) => { if (Surface.SelectedAnnotation is { } selected) OpenAnnotationNote(selected); };
        CaptureHandleLayer.Children.Add(_addNoteButton);
    }

    private void UpdateNoteButton()
    {
        var selected = Surface.SelectedAnnotation;
        var show = _capture is not null && Toolbar.Visibility == Visibility.Visible
            && selected is not null && !_visibleChipIds.Contains(selected.Id);
        _addNoteButton.Visibility = show ? Visibility.Visible : Visibility.Collapsed;
        if (!show || selected is null) return;
        var bounds = Surface.GetDisplayBounds(selected);
        Canvas.SetLeft(_addNoteButton, Math.Clamp(_cropRect.Left + bounds.Right + 4, 0, Math.Max(0, ActualWidth - 24)));
        Canvas.SetTop(_addNoteButton, Math.Clamp(_cropRect.Top + bounds.Top - 12, 0, Math.Max(0, ActualHeight - 24)));
    }

    // Dragging the pill of a note moves the badge of its mark with it, on screen and in the export.
    // The offset is written straight to the model, without a property notification, so the whole
    // drag becomes one history entry when the pill is let go.
    private void BeginNoteDrag(AnnotationItem annotation, Point start)
    {
        _chipDragAnnotation = annotation;
        _chipDragStart = start;
        _chipDragOrigin = annotation.NoteOffset;
        _chipDragMoved = false;
    }

    private void DragNoteTo(Point current)
    {
        if (_chipDragAnnotation is not { } annotation || _capture is null || _cropRect.Width <= 0 || _cropRect.Height <= 0) return;
        var delta = current - _chipDragStart;
        if (!_chipDragMoved && delta.Length < 4) return;
        _chipDragMoved = true;
        var origin = _chipDragOrigin ?? default;
        annotation.NoteOffset = new Point(
            origin.X + delta.X * _capture.Image.PixelWidth / _cropRect.Width,
            origin.Y + delta.Y * _capture.Image.PixelHeight / _cropRect.Height);
        Surface.InvalidateVisual();
        RepositionChips();
    }

    private bool EndNoteDrag()
    {
        var moved = _chipDragMoved;
        _chipDragAnnotation = null;
        _chipDragMoved = false;
        if (!moved) return false;
        PushHistory();
        RepositionChips();
        PositionToolbar();
        return true;
    }

    private void OnAnnotationChanged(object sender, EventArgs e)
    {
        MoveLinkedComments();
        PushHistory();
        RefreshLabels();
        if (_capture is not null && ChipLayer.Children.Count != _capture.Annotations.Count) RebuildChips();
        else RepositionChips();
        SyncAppearance();
    }

    private void OnAnnotationPropertyChanged(object? sender, PropertyChangedEventArgs e)
    {
        if (e.PropertyName == nameof(AnnotationItem.IsSelected)) return;
        RefreshLabels();
        if (_capture is not null)
        {
            _redo.Clear();
            // Every character typed into a caption comes through here, and a snapshot is a deep copy
            // of the whole capture with every mark on it. While the text box is open there is one
            // snapshot instead, taken when the caption is finished.
            if (_editingText is null) _lastSnapshot = SnapshotState();
        }
        Surface.InvalidateVisual();
    }

    private void RebuildChips()
    {
        ChipLayer.Children.Clear();
        _chipLabels.Clear();
        _chipBorders.Clear();
        _chipExpanders.Clear();
        _chipFinishers.Clear();
        _expandedChipId = null;
        if (_capture is null) return;
        foreach (var item in _capture.Annotations.Where(a => !string.IsNullOrWhiteSpace(a.Note))) _visibleChipIds.Add(item.Id);
        _visibleChipIds.RemoveWhere(id => _capture.Annotations.All(annotation => annotation.Id != id));
        foreach (var annotation in _capture.Annotations.Where(annotation => _visibleChipIds.Contains(annotation.Id))) AddChip(annotation, false);
    }

    private void AddChip(AnnotationItem annotation, bool focus)
    {
        var badge = new TextBlock { Foreground = Brushes.White, FontSize = 11, FontWeight = FontWeights.Bold, HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center };
        _chipLabels[annotation.Id] = badge;
        var badgeHost = new Border { Width = 25, Height = 25, CornerRadius = new CornerRadius(13), Background = new SolidColorBrush(Color.FromRgb(47, 140, 255)), Child = badge, VerticalAlignment = VerticalAlignment.Center };
        var note = new TextBox
        {
            MinHeight = 32, MaxHeight = 78, Text = annotation.Note, AcceptsReturn = true, TextWrapping = TextWrapping.Wrap,
            Background = Brushes.Transparent, Foreground = Brushes.White, BorderThickness = new Thickness(0), CaretBrush = Brushes.White,
            SelectionBrush = new SolidColorBrush(Color.FromRgb(47, 140, 255)), Padding = new Thickness(7, 5, 7, 5), Tag = annotation
        };
        note.TextChanged += (_, _) =>
        {
            if (_settingUp) return;
            annotation.Note = note.Text;
            RefreshLabels();
        };
        note.GotKeyboardFocus += (_, _) => Surface.SelectAnnotation(annotation.Id);
        var closePath = new System.Windows.Shapes.Path
        {
            Stroke = new SolidColorBrush(Color.FromRgb(217, 222, 232)), StrokeThickness = 1.5,
            StrokeStartLineCap = PenLineCap.Round, StrokeEndLineCap = PenLineCap.Round,
            Data = Geometry.Parse("M1,1 L9,9 M9,1 L1,9")
        };
        var close = new Button
        {
            Width = 27, Height = 27, Padding = new Thickness(7), Background = Brushes.Transparent,
            BorderThickness = new Thickness(0), Content = closePath, ToolTip = UiLanguage.Text("Удалить комментарий"), Tag = annotation
        };
        close.Click += OnDeleteAnnotationNoteClick;
        var grid = new Grid();
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(31) });
        grid.ColumnDefinitions.Add(new ColumnDefinition());
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(29) });
        grid.Children.Add(badgeHost);
        Grid.SetColumn(note, 1); grid.Children.Add(note);
        Grid.SetColumn(close, 2); grid.Children.Add(close);
        var border = new Border
        {
            Tag = annotation.Id, Width = 226, MinHeight = 40, Padding = new Thickness(6), CornerRadius = new CornerRadius(13),
            Background = new SolidColorBrush(Color.FromArgb(244, 23, 26, 32)), Child = grid,
            Effect = new System.Windows.Media.Effects.DropShadowEffect { Color = Colors.Black, BlurRadius = 14, ShadowDepth = 4, Opacity = .42 }
        };
        void Expand(bool expanded)
        {
            if (expanded)
            {
                CollapseOtherChips(annotation.Id);
                _expandedChipId = annotation.Id;
            }
            else if (_expandedChipId == annotation.Id) _expandedChipId = null;
            border.Visibility = Visibility.Visible;
            border.Width = expanded ? 270 : 43;
            note.Visibility = close.Visibility = expanded ? Visibility.Visible : Visibility.Collapsed;
            grid.ColumnDefinitions[2].Width = new GridLength(expanded ? 29 : 0);
            Panel.SetZIndex(border, expanded ? (border.IsKeyboardFocusWithin ? 1200 : 1000) : 0);
            RepositionChips();
            PositionToolbar();
        }
        void Finish()
        {
            if (string.IsNullOrWhiteSpace(annotation.Note))
            {
                _visibleChipIds.Remove(annotation.Id);
                _chipLabels.Remove(annotation.Id);
                _chipBorders.Remove(annotation.Id);
                _chipExpanders.Remove(annotation.Id);
                _chipFinishers.Remove(annotation.Id);
                if (_expandedChipId == annotation.Id) _expandedChipId = null;
                ChipLayer.Children.Remove(border);
                if (annotation.Kind == EditorTool.Comment)
                {
                    if (ReferenceEquals(Surface.SelectedAnnotation, annotation)) Surface.SelectAnnotation(null);
                    _capture?.Annotations.Remove(annotation);
                }
                if (_capture is not null) _lastSnapshot = SnapshotState();
                RefreshLabels();
                RepositionChips();
                PositionToolbar();
                return;
            }
            Expand(false);
        }
        _chipBorders[annotation.Id] = border;
        _chipExpanders[annotation.Id] = Expand;
        _chipFinishers[annotation.Id] = Finish;
        note.GotKeyboardFocus += (_, _) => Expand(true);
        border.MouseEnter += (_, _) =>
        {
            if (_chipDragAnnotation is null && !HasFocusedChipOtherThan(annotation.Id)) Expand(true);
        };
        border.MouseLeave += (_, _) => { if (_chipDragAnnotation is null && !border.IsKeyboardFocusWithin) Finish(); };
        badgeHost.Cursor = Cursors.SizeAll;
        badgeHost.ToolTip = UiLanguage.Text("Переместить заметку");
        badgeHost.MouseLeftButtonDown += (_, e) =>
        {
            BeginNoteDrag(annotation, e.GetPosition(Root));
            badgeHost.CaptureMouse();
            e.Handled = true;
        };
        badgeHost.MouseMove += (_, e) => { if (badgeHost.IsMouseCaptured) DragNoteTo(e.GetPosition(Root)); };
        badgeHost.MouseLeftButtonUp += (_, e) =>
        {
            // The drag is closed before the capture is released, because releasing it runs the
            // handler below, and after that a real drag would read as a click.
            var dragged = EndNoteDrag();
            if (badgeHost.IsMouseCaptured) badgeHost.ReleaseMouseCapture();
            // A press that did not travel is still a click: it opens the note.
            if (!dragged) { note.Focus(); Expand(true); }
            e.Handled = true;
        };
        // Alt+Tab, a dialog or anything else that takes the capture away ends the drag too:
        // otherwise the editor stays inside a drag that never finishes and no chip expands again.
        badgeHost.LostMouseCapture += (_, _) => EndNoteDrag();
        ChipLayer.Children.Add(border);
        note.LostKeyboardFocus += (_, _) => Dispatcher.BeginInvoke(() => { if (!border.IsKeyboardFocusWithin && !border.IsMouseOver) Finish(); }, DispatcherPriority.Input);
        note.PreviewKeyDown += (_, e) =>
        {
            if (e.Key != Key.Enter || Keyboard.Modifiers != ModifierKeys.None) return;
            Finish();
            Surface.Focus();
            e.Handled = true;
        };
        Expand(focus);
        RefreshLabels();
        if (focus) Dispatcher.BeginInvoke(() => { note.Focus(); note.SelectAll(); }, DispatcherPriority.Input);
    }

    private void RefreshLabels()
    {
        if (_capture is null) return;
        var labels = CaptureLabels.ForNotedAnnotations(_capture.DisplayLabel, _capture.ToCore()).ToDictionary(x => x.Annotation.Id, x => x.DisplayLabel);
        foreach (var annotation in _capture.Annotations)
        {
            annotation.Label = labels.GetValueOrDefault(annotation.Id) ?? string.Empty;
            if (_chipLabels.TryGetValue(annotation.Id, out var text))
            {
                text.Text = string.IsNullOrEmpty(annotation.Label) ? "+" : annotation.Label;
            }
        }
        SyncCommentsPanel();
        Surface.InvalidateVisual();
    }

    private void RepositionChips()
    {
        if (_capture is null) return;
        var work = LayoutWorkArea();
        var occupied = new List<Rect>();
        var chips = ChipLayer.Children.OfType<Border>()
            .Where(chip => chip.Visibility == Visibility.Visible && chip.Tag is Guid)
            .OrderByDescending(chip => chip.Tag is Guid id && id == _expandedChipId)
            .ThenByDescending(chip => chip.Tag is Guid id && _capture.Annotations.FirstOrDefault(item => item.Id == id)?.NoteOffset is not null)
            .ThenBy(chip =>
            {
                var annotation = _capture.Annotations.FirstOrDefault(item => item.Id == (Guid)chip.Tag);
                return annotation is null ? int.MaxValue : _capture.Annotations.IndexOf(annotation);
            })
            .ToArray();
        foreach (var chip in chips)
        {
            var id = (Guid)chip.Tag;
            if (_capture.Annotations.FirstOrDefault(item => item.Id == id) is not { } annotation) continue;
            var annotationBounds = Surface.GetDisplayBounds(annotation);
            var isExpanded = id == _expandedChipId;
            var width = chip.Width;
            var height = isExpanded ? Math.Max(90, chip.ActualHeight) : 40;
            var currentLeft = Canvas.GetLeft(chip);
            var currentTop = Canvas.GetTop(chip);
            // A pill the user placed by hand stays where it was put, and the others go around it.
            if (annotation.NoteOffset is not null)
            {
                var badge = Surface.GetBadgeCenter(annotation);
                var manual = ClampChip(
                    new Point(_cropRect.Left + badge.X - 21.5, _cropRect.Top + badge.Y - height / 2),
                    new Size(width, height), work);
                Canvas.SetLeft(chip, manual.Left);
                Canvas.SetTop(chip, manual.Top);
                occupied.Add(manual);
                continue;
            }
            var keepExpandedPosition = isExpanded
                && !double.IsNaN(currentLeft) && !double.IsInfinity(currentLeft)
                && !double.IsNaN(currentTop) && !double.IsInfinity(currentTop);
            var preferred = keepExpandedPosition
                ? new Point(currentLeft, currentTop)
                : new Point(_cropRect.Left + annotationBounds.Left, _cropRect.Top + annotationBounds.Bottom + 8);
            var placement = FindChipPlacement(preferred, new Size(width, height), work, occupied);
            Canvas.SetLeft(chip, placement.Left);
            Canvas.SetTop(chip, placement.Top);
            occupied.Add(placement);
        }
        UpdateNoteButton();
    }

    private void PositionShotNote()
    {
        var work = LayoutWorkArea();
        var left = Math.Clamp(_cropRect.Right - 250, work.Left + 8, Math.Max(work.Left + 8, work.Right - 258));
        var top = Math.Clamp(_cropRect.Top, work.Top + 8, Math.Max(work.Top + 8, work.Bottom - 132));
        ShotNoteChip.HorizontalAlignment = HorizontalAlignment.Left;
        ShotNoteChip.Margin = new Thickness(left, top, 0, 0);
    }

    private void PositionToolbar()
    {
        var work = LayoutWorkArea();
        // The width the panel may ask for, which is what makes its row wrap: PlaceToolbar keeps 8 px
        // at each side of the working area, and a panel wider than what is left loses its tail, from
        // "Комментарий" to "Готово", off the screen. The floor is the width the placement already
        // assumes, so a working area narrower than that changes nothing that was not broken anyway.
        Toolbar.MaxWidth = Math.Max(380, work.Width - 16);
        Toolbar.UpdateLayout();
        var width = Math.Max(Toolbar.ActualWidth, 380);
        var height = Math.Max(Toolbar.ActualHeight, 50);
        var placement = PlaceToolbar(_cropRect, work, new Size(width, height), VisibleNoteRects().ToArray());
        Toolbar.Margin = new Thickness(placement.Left, placement.Top, 0, 0);

        IEnumerable<Rect> VisibleNoteRects()
        {
            foreach (Border chip in ChipLayer.Children)
            {
                var x = Canvas.GetLeft(chip); var y = Canvas.GetTop(chip);
                if (!double.IsNaN(x) && !double.IsNaN(y)) yield return new Rect(x, y, Math.Max(chip.ActualWidth, chip.Width), Math.Max(chip.ActualHeight, 40));
            }
            if (ShotNoteChip.Visibility == Visibility.Visible)
                yield return new Rect(ShotNoteChip.Margin.Left, ShotNoteChip.Margin.Top, ShotNoteChip.Width, Math.Max(ShotNoteChip.ActualHeight, 60));
        }
    }

    private void OnCommentClick(object sender, RoutedEventArgs e)
    {
        if (_capture is null) return;
        _commentParentId = Surface.SelectedAnnotation is { } selected ? (selected.Kind == EditorTool.Comment ? selected.ParentAnnotationId : selected.Id) : null;
        SelectToolMode(EditorTool.Comment);
    }
    private void OnDeleteAnnotationNoteClick(object sender, RoutedEventArgs e)
    {
        if (_capture is null || sender is not Button { Tag: AnnotationItem annotation }) return;
        DeleteAnnotationNote(annotation);
        e.Handled = true;
    }

    private void DeleteAnnotationNote(AnnotationItem annotation)
    {
        if (_capture is null) return;
        if (!string.IsNullOrEmpty(annotation.Note)) _undo.Push(SnapshotState());
        _redo.Clear();
        if (annotation.Kind == EditorTool.Comment) _capture.Annotations.Remove(annotation);
        else annotation.Note = string.Empty;
        _lastSnapshot = SnapshotState();
        _visibleChipIds.Remove(annotation.Id);
        _chipBorders.Remove(annotation.Id);
        _chipExpanders.Remove(annotation.Id);
        _chipFinishers.Remove(annotation.Id);
        if (_expandedChipId == annotation.Id) _expandedChipId = null;
        if (ChipLayer.Children.OfType<Border>().FirstOrDefault(border => border.Tag is Guid id && id == annotation.Id) is { } chip)
            ChipLayer.Children.Remove(chip);
        RefreshLabels();
        RepositionChips();
        PositionToolbar();
    }

    private void OnCloseShotNoteClick(object sender, RoutedEventArgs e)
    {
        if (_capture is null) return;
        if (!string.IsNullOrEmpty(_capture.Note)) _undo.Push(SnapshotState());
        _redo.Clear();
        _settingUp = true;
        ShotNoteBox.Clear();
        _capture.Note = string.Empty;
        _settingUp = false;
        _lastSnapshot = SnapshotState();
        ShotNoteChip.Visibility = Visibility.Collapsed;
        PositionToolbar();
        Surface.Focus();
        e.Handled = true;
    }

    private Rect GetCropMonitorWorkArea()
    {
        var layoutWidth = ActualWidth > 0 ? ActualWidth : !double.IsNaN(Width) && Width > 0 ? Width : _frame.PixelWidth;
        var layoutHeight = ActualHeight > 0 ? ActualHeight : !double.IsNaN(Height) && Height > 0 ? Height : _frame.PixelHeight;
        var scaleToPixelX = _frame.PixelWidth / Math.Max(1, layoutWidth);
        var scaleToPixelY = _frame.PixelHeight / Math.Max(1, layoutHeight);
        var centerPixel = new System.Drawing.Point(
            _frame.Left + (int)Math.Round((_cropRect.Left + _cropRect.Width / 2) * scaleToPixelX),
            _frame.Top + (int)Math.Round((_cropRect.Top + _cropRect.Height / 2) * scaleToPixelY));
        var area = WinForms.Screen.FromPoint(centerPixel).WorkingArea;
        return new Rect(
            (area.Left - _frame.Left) / scaleToPixelX,
            (area.Top - _frame.Top) / scaleToPixelY,
            area.Width / scaleToPixelX,
            area.Height / scaleToPixelY);
    }

    private void OnShotNoteChanged(object sender, TextChangedEventArgs e)
    {
        if (_settingUp || _capture is null) return;
        _capture.Note = ShotNoteBox.Text;
        _redo.Clear();
        _lastSnapshot = SnapshotState();
        SyncAppearance();
    }

    private void PushHistory()
    {
        if (_capture is null || _lastSnapshot is null) return;
        _undo.Push(_lastSnapshot);
        _redo.Clear();
        _lastSnapshot = SnapshotState();
        SyncAppearance();
    }

    private void OnUndoClick(object sender, RoutedEventArgs e)
    {
        if (_busyCrop || _captureResizeCorner >= 0 || _capture is null || _undo.Count == 0) return;
        _redo.Push(SnapshotState());
        RestoreState(_undo.Pop());
    }

    private void OnRedoClick(object sender, RoutedEventArgs e)
    {
        if (_busyCrop || _captureResizeCorner >= 0 || _capture is null || _redo.Count == 0) return;
        _undo.Push(SnapshotState());
        RestoreState(_redo.Pop());
    }

    private OverlaySnapshot SnapshotState() => new(_capture!.Snapshot(), _cropRect, new HashSet<Guid>(_visibleChipIds), ShotNoteChip.Visibility == Visibility.Visible);

    private void RestoreState(OverlaySnapshot state)
    {
        if (_capture is null) return;
        // The marks are replaced wholesale, so the caption being typed is not among them any more.
        CloseTextEditor();
        _capture.Restore(state.Capture);
        _cropRect = state.CropRect;
        _visibleChipIds.Clear();
        _visibleChipIds.UnionWith(state.VisibleChipIds);
        foreach (var annotation in _capture.Annotations) annotation.PropertyChanged += OnAnnotationPropertyChanged;
        Surface.Image = _capture.Image;
        Surface.Annotations = _capture.Annotations;
        _settingUp = true;
        ShotNoteBox.Text = _capture.Note;
        ShotNoteChip.Visibility = state.ShotNoteVisible ? Visibility.Visible : Visibility.Collapsed;
        _settingUp = false;
        _lastSnapshot = SnapshotState();
        UpdateCropVisual();
        RebuildChips();
        SyncAppearance();
        PositionToolbar();
        PositionShotNote();
        Surface.InvalidateVisual();
    }

    private async void OnCropRequested(Rect pixelBounds)
    {
        if (_capture is null || _busyCrop || _captureResizeCorner >= 0 || Surface.IsMouseCaptured) return;
        var width = _capture.Image.PixelWidth;
        var height = _capture.Image.PixelHeight;
        var left = Math.Clamp((int)Math.Floor(pixelBounds.Left), 0, width - 1);
        var top = Math.Clamp((int)Math.Floor(pixelBounds.Top), 0, height - 1);
        var right = Math.Clamp((int)Math.Ceiling(pixelBounds.Right), left + 1, width);
        var bottom = Math.Clamp((int)Math.Ceiling(pixelBounds.Bottom), top + 1, height);
        if (right - left < 8 || bottom - top < 8) return;

        _busyCrop = true;
        try
        {
            var before = SnapshotState();
            var pixelRect = new Int32Rect(left, top, right - left, bottom - top);
            var bitmap = new CroppedBitmap(_capture.Image, pixelRect);
            bitmap.Freeze();
            var relativePath = await _workspace.SaveDerivedImageAsync(bitmap);
            _createdSourcePaths.Add(relativePath);
            var normalized = new NormalizedRect((double)left / width, (double)top / height, (double)pixelRect.Width / width, (double)pixelRect.Height / height);
            var result = CaptureCropper.Crop(_capture.ToCore(), normalized, relativePath, pixelRect.Width, pixelRect.Height);
            var cropped = CaptureItem.FromCore(result.CroppedCapture, bitmap);
            cropped.DisplayLabel = _capture.DisplayLabel;
            cropped.IsSelected = _capture.IsSelected;

            var oldRect = _cropRect;
            _cropRect = new Rect(
                oldRect.Left + oldRect.Width * left / width,
                oldRect.Top + oldRect.Height * top / height,
                oldRect.Width * pixelRect.Width / width,
                oldRect.Height * pixelRect.Height / height);
            _capture = cropped;
            _undo.Push(before);
            _redo.Clear();
            SetupEditor();
            Surface.Tool = EditorTool.Select;
            SelectTool.IsChecked = true;
            CropTool.IsChecked = false;
        }
        catch (Exception ex)
        {
            Hint.Visibility = Visibility.Visible;
            ((TextBlock)Hint.Child).Text = $"Не удалось обрезать снимок: {ex.Message}";
        }
        finally { _busyCrop = false; }
    }

    private void OnDoneClick(object sender, RoutedEventArgs e) => Complete(false);
    private void OnAddNextClick(object sender, RoutedEventArgs e) => Complete(true);

    private void Complete(bool addNext)
    {
        if (_capture is null || _busyCrop || _captureResizeCorner >= 0 || Surface.IsMouseCaptured) return;
        CommitTextEdit();
        RememberCurrentRegion();
        _capture.Note = ShotNoteBox.Text;
        DeleteCreatedSourcesExcept(_capture.SourcePath);
        Result = new OverlayEditResult(_capture, addNext, false);
        DialogResult = true;
    }

    private void OnWindowKeyDown(object sender, KeyEventArgs e)
    {
        if (Keyboard.Modifiers == ModifierKeys.Control && e.Key == Key.S) { e.Handled = true; OnSaveImageClick(this, e); return; }
        if (Keyboard.FocusedElement is TextBox)
        {
            if (e.Key == Key.Escape) { Surface.Focus(); e.Handled = true; }
            return;
        }
        // Enter is "Done", the way the button, Ctrl+C and the capture shortcut are. Text that is
        // being edited takes it first (a focused TextBox has already returned above), and an open
        // popover belongs to Escape, not to finishing the capture.
        if (e.Key == Key.Enter && Keyboard.Modifiers == ModifierKeys.None && _capture is not null && NextEscapeStep() != EscapeStep.Popover)
        {
            e.Handled = true;
            Complete(false);
            return;
        }
        if (e.Key == Key.Escape && NextEscapeStep() == EscapeStep.Popover)
        {
            ClosePopovers();
            e.Handled = true;
            return;
        }
        if (e.Key == Key.Escape && NextEscapeStep() == EscapeStep.Selection)
        {
            Surface.SelectAnnotation(null);
            e.Handled = true;
            return;
        }
        if (e.Key == Key.Escape)
        {
            CancelEdit();
            Result = new OverlayEditResult(_isNew ? null : _capture, false, true);
            DialogResult = false;
        }
        else if (Keyboard.Modifiers == ModifierKeys.Control && e.Key == Key.S) { e.Handled = true; OnSaveImageClick(this, e); }
        else if (Keyboard.Modifiers == ModifierKeys.Control && e.Key == Key.Z) { OnUndoClick(this, e); e.Handled = true; }
        else if (Keyboard.Modifiers == ModifierKeys.Control && e.Key == Key.Y) { OnRedoClick(this, e); e.Handled = true; }
        else if (Keyboard.Modifiers == ModifierKeys.Control && e.Key == Key.C && _capture is not null) { e.Handled = true; Complete(false); }
        else if (Keyboard.Modifiers == ModifierKeys.None)
        {
            var tool = EditorShortcuts.ToolFor(e.Key);
            if (tool == EditorTool.Comment) { OnCommentClick(this, e); e.Handled = true; }
            else if (tool is not null) { SelectToolMode(tool.Value); e.Handled = true; }
        }
    }

    private static Rect Normalize(Point a, Point b) => new(new Point(Math.Min(a.X, b.X), Math.Min(a.Y, b.Y)), new Point(Math.Max(a.X, b.X), Math.Max(a.Y, b.Y)));

    private void OnClosing(object? sender, CancelEventArgs e)
    {
        _closed = true;
        FlushAppearanceDefaults();
        if (Result.Cancelled) CancelEdit();
    }

    private void CancelEdit()
    {
        if (_capture is null) return;
        DeleteCreatedSourcesExcept(null);
    }

    private void DeleteCreatedSourcesExcept(string? keepRelativePath)
    {
        var root = Path.GetFullPath(_workspace.SessionDirectory) + Path.DirectorySeparatorChar;
        foreach (var relativePath in _createdSourcePaths)
        {
            if (string.Equals(relativePath, keepRelativePath, StringComparison.OrdinalIgnoreCase)) continue;
            var source = Path.GetFullPath(Path.Combine(_workspace.SessionDirectory, relativePath));
            if (source.StartsWith(root, StringComparison.OrdinalIgnoreCase) && File.Exists(source)) File.Delete(source);
        }
    }

    private readonly Button _addNoteButton = new();

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool SetWindowPos(IntPtr hwnd, IntPtr insertAfter, int x, int y, int cx, int cy, uint flags);

    private sealed record OverlaySnapshot(CaptureSnapshot Capture, Rect CropRect, IReadOnlySet<Guid> VisibleChipIds, bool ShotNoteVisible);
}
