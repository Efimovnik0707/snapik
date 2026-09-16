using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Linq;
using System.Windows;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using Snapik.App.Imaging;
using Snapik.Core.Models;
using System.Runtime.CompilerServices;

namespace Snapik.App.Controls;

public sealed class AnnotationCanvas : FrameworkElement
{
    private Point? _gestureStart;
    private AnnotationItem? _draft;
    private Rect _imageRect;
    private List<Point>? _originalPoints;
    private List<List<Point>>? _originalAdditionalSegments;
    private bool _manipulating;
    private bool _resizing;
    private int _resizeCorner = -1;
    private Rect _originalBounds;
    private bool _manipulationChanged;
    // The press on a mark travelled far enough to be a drag: below the threshold it is a click.
    private bool _manipulationMoved;
    private AnnotationItem? _eraseHover;
    // The anchor of a leader: the circle at the point a comment is attached to, and the drag of it.
    private AnnotationItem? _anchorDrag;
    private List<Point>? _anchorOriginPoints;
    private Point? _anchorOriginOffset;
    private Point _anchorDragStart;
    private bool _anchorMoved;
    // The badge of a comment, dragged by itself: the point it is attached to stays where it is, and
    // the leader grows between the two. It is not held inside the capture — a badge taken out onto
    // the dark beside the picture is exactly what the margin of the export is for.
    private AnnotationItem? _badgeDrag;
    private Point? _badgeOriginOffset;
    private Point _badgeDragStart;
    private bool _badgeMoved;
    private Guid? _anchorHover;
    private Guid? _badgeHover;
    private int _blurCacheKey;
    private BitmapSource? _blurCache;
    private double? _viewScale;
    private Point? _panStart;
    private Vector _panOrigin;

    public static readonly DependencyProperty ImageProperty = DependencyProperty.Register(
        nameof(Image), typeof(BitmapSource), typeof(AnnotationCanvas), new FrameworkPropertyMetadata(null, FrameworkPropertyMetadataOptions.AffectsRender));

    public static readonly DependencyProperty ToolProperty = DependencyProperty.Register(
        nameof(Tool), typeof(EditorTool), typeof(AnnotationCanvas),
        new FrameworkPropertyMetadata(EditorTool.Select, OnToolChanged));

    public static readonly DependencyProperty AnnotationsProperty = DependencyProperty.Register(
        nameof(Annotations), typeof(ObservableCollection<AnnotationItem>), typeof(AnnotationCanvas),
        new FrameworkPropertyMetadata(null, FrameworkPropertyMetadataOptions.AffectsRender, OnAnnotationsChanged));

    public BitmapSource? Image { get => (BitmapSource?)GetValue(ImageProperty); set => SetValue(ImageProperty, value); }
    public EditorTool Tool { get => (EditorTool)GetValue(ToolProperty); set => SetValue(ToolProperty, value); }
    public ObservableCollection<AnnotationItem>? Annotations { get => (ObservableCollection<AnnotationItem>?)GetValue(AnnotationsProperty); set => SetValue(AnnotationsProperty, value); }
    public AnnotationItem? SelectedAnnotation { get; private set; }
    public Color ActiveColor { get; set; } = Color.FromRgb(49, 92, 245);
    public double ActiveThickness { get; set; } = 4;
    public string ActiveArrowStyle { get; set; } = "straight";
    public AnnotationShape ActiveShape { get; set; } = AnnotationShape.Rectangle;
    public AnnotationFill ActiveFill { get; set; } = AnnotationFill.None;
    public Color? ActiveFillColor { get; set; }
    public double ActiveFontSize { get; set; } = TextMarkMetrics.DefaultFontSize;
    public AnnotationLineStyle ActiveLineStyle { get; set; } = AnnotationLineStyle.Solid;
    // The mark whose letters are being typed on the capture right now: the canvas leaves it to the
    // text box standing over it, otherwise the caption is drawn twice.
    public Guid? EditingTextId { get; set; }
    public double ImagePadding { get; set; } = 28;

    /// <summary>
    /// Null is "fit": the picture is scaled down to the canvas and centred, the way it always was.
    /// Anything else is the scale in canvas units per pixel of the picture, and the picture stands
    /// where <see cref="ViewOffset"/> holds it. Everything the canvas measures is counted from the
    /// rectangle those two decide, so the marks follow without a line of their own.
    /// </summary>
    public double? ViewScale
    {
        get => _viewScale;
        set
        {
            if (Nullable.Equals(_viewScale, value)) return;
            _viewScale = value;
            // At its own size the picture must show its own pixels: with smoothing on, the seam
            // between two monitors is spread over two of them.
            RenderOptions.SetBitmapScalingMode(this, value is null ? BitmapScalingMode.Unspecified : BitmapScalingMode.NearestNeighbor);
            InvalidateVisual();
            ViewChanged?.Invoke(this, EventArgs.Empty);
        }
    }

    /// <summary>How far the picture is scrolled, in canvas units. Ignored while fitting.</summary>
    public Vector ViewOffset { get; set; }

    /// <summary>The scale the picture is shown at while fitting: the floor of Ctrl and the wheel.</summary>
    public double FitScale => Image is null || Image.PixelWidth <= 0 || Image.PixelHeight <= 0
        ? 1
        : Math.Min(Math.Max(1, ActualWidth - ImagePadding * 2) / Image.PixelWidth,
                   Math.Max(1, ActualHeight - ImagePadding * 2) / Image.PixelHeight);

    /// <summary>Space is held down: the next press drags the picture instead of drawing on it.</summary>
    public bool Panning { get; set; }

    public event EventHandler<AnnotationItem>? AnnotationCreated;
    /// <summary>The scale or the offset changed: the switch beside the panel says which is in force.</summary>
    public event EventHandler? ViewChanged;
    public event EventHandler<AnnotationItem>? AnnotationActivated;
    public event EventHandler<AnnotationItem?>? SelectionChanged;
    /// <summary>The badge of a comment came under the pointer, or left it: the window opens the
    /// pill of that note, so the text is read by pointing at the number on the picture.</summary>
    public event EventHandler<AnnotationItem?>? NoteHovered;
    public event EventHandler? AnnotationChanged;
    public event Action<Rect>? CropRequested;

    internal static void VerifyBlurPreview(BitmapSource source)
    {
        var canvas = new AnnotationCanvas { Image = source, Width = 320, Height = 180 };
        canvas.Measure(new Size(320, 180));
        canvas.Arrange(new Rect(0, 0, 320, 180));
        byte[] Render()
        {
            canvas.UpdateLayout();
            var bitmap = new RenderTargetBitmap(320, 180, 96, 96, PixelFormats.Pbgra32);
            bitmap.Render(canvas);
            var pixels = new byte[320 * 180 * 4];
            bitmap.CopyPixels(pixels, 320 * 4, 0);
            return pixels;
        }
        var before = Render();
        canvas._draft = new AnnotationItem
        {
            Kind = EditorTool.Blur,
            Points = [new Point(source.PixelWidth * .2, source.PixelHeight * .2), new Point(source.PixelWidth * .7, source.PixelHeight * .7)]
        };
        canvas.InvalidateVisual();
        var after = Render();
        if (before.SequenceEqual(after)) throw new InvalidOperationException("The blur selection preview is invisible before mouse release.");
    }
    // A frame filled with blur bakes the same pixels as the blur tool, so it has to reach the same
    // cache: without it every movement of the mouse converts, copies and rebuilds the whole frame,
    // and dragging such a region over a 4K capture stops being possible.
    internal static void VerifyBlurCache(BitmapSource source)
    {
        var filled = new AnnotationItem
        {
            Kind = EditorTool.Rectangle,
            Fill = AnnotationFill.Blur,
            Points = [new Point(source.PixelWidth * .2, source.PixelHeight * .2), new Point(source.PixelWidth * .6, source.PixelHeight * .6)]
        };
        var canvas = new AnnotationCanvas { Image = source, Annotations = [filled] };
        var baked = canvas.ApplyBlurAnnotations(source);
        if (ReferenceEquals(baked, source))
            throw new InvalidOperationException("A region filled with blur must be baked into the preview.");
        // What a drag does: the region moves, the key of the cache changes, and the frame under it
        // stays the one that was built before the drag began.
        canvas.SelectedAnnotation = filled;
        canvas._manipulating = true;
        filled.Points[1] = new Point(source.PixelWidth * .7, source.PixelHeight * .7);
        if (!ReferenceEquals(canvas.ApplyBlurAnnotations(source), baked))
            throw new InvalidOperationException("Dragging a region filled with blur must reuse the cached frame instead of rebuilding it.");
    }

    public AnnotationCanvas()
    {
        Focusable = true;
        // The crosshair is not the cursor of the whole surface any more: it appears over the capture
        // while a drawing tool is armed, and nowhere else.
        Cursor = Cursors.Arrow;
        ClipToBounds = true;
    }

    // Another tool was armed from a button or a key without the pointer moving: what the eraser was
    // pointing at is not its target any more.
    private static void OnToolChanged(DependencyObject d, DependencyPropertyChangedEventArgs e)
    {
        if ((EditorTool)e.NewValue != EditorTool.Eraser) ((AnnotationCanvas)d).ClearEraseHover();
    }

    private static void OnAnnotationsChanged(DependencyObject d, DependencyPropertyChangedEventArgs e)
    {
        var canvas = (AnnotationCanvas)d;
        if (e.OldValue is ObservableCollection<AnnotationItem> old) old.CollectionChanged -= canvas.OnCollectionChanged;
        if (e.NewValue is ObservableCollection<AnnotationItem> current) current.CollectionChanged += canvas.OnCollectionChanged;
        canvas.SelectedAnnotation = null;
        canvas.InvalidateVisual();
    }

    private void OnCollectionChanged(object? sender, System.Collections.Specialized.NotifyCollectionChangedEventArgs e) => InvalidateVisual();

    protected override void OnRender(DrawingContext dc)
    {
        base.OnRender(dc);
        if (Image is null) return;

        _imageRect = ViewScale is { } viewScale ? ScaledRect(viewScale) : FitRect(Image.PixelWidth, Image.PixelHeight, ActualWidth, ActualHeight, ImagePadding);
        dc.DrawRectangle(Brushes.White, null, _imageRect);
        dc.DrawImage(ApplyBlurAnnotations(Image), _imageRect);

        if (Annotations is not null)
        {
            foreach (var annotation in Annotations.Where(a => a.Kind != EditorTool.Blur && !HasOpaqueFill(a))) DrawAnnotation(dc, annotation, _imageRect, includeSelection: false, drawLabel: false);
            foreach (var annotation in Annotations.Where(HasOpaqueFill)) DrawAnnotation(dc, annotation, _imageRect, includeSelection: false, drawLabel: false);
            foreach (var annotation in Annotations) DrawAnnotation(dc, annotation, _imageRect, includeSelection: true, drawShape: false);
        }
        // The mark the eraser is about to take is outlined in red, so a click is never a surprise.
        if (_eraseHover is { } erasing && Annotations?.Contains(erasing) == true)
            dc.DrawRectangle(null, new Pen(new SolidColorBrush(Color.FromRgb(255, 59, 48)), 1.5), GetDisplayBounds(erasing));
        // While a blurred region travels the frame under it is the cached one, so the region itself
        // is drawn as a cheap placeholder: the same for the blur tool and for a frame filled with blur.
        if (_manipulating && SelectedAnnotation is { } movingBlur && IsBlurred(movingBlur))
            DrawBoxShape(dc, Brushes.Black, new Pen(Brushes.DodgerBlue, 1.5), movingBlur.Shape,
                GetDisplayBounds(movingBlur), _imageRect.Width / Image.PixelWidth);
        if (_draft is not null) DrawAnnotation(dc, _draft, _imageRect);
    }

    protected override void OnMouseLeftButtonDown(MouseButtonEventArgs e)
    {
        base.OnMouseLeftButtonDown(e);
        Focus();
        if (Image is null) return;
        BeginGesture(e.GetPosition(this), e.ClickCount);
    }

    // The three halves of a gesture, apart from the mouse that usually drives them: a smoke run
    // presses, drags and lets go through these without a pointer on screen.
    internal void BeginGesture(Point point, int clickCount = 1)
    {
        if (Image is null) return;
        // Space held down turns the press into a drag of the picture itself, wherever it lands.
        var panning = Panning && ViewScale is not null;
        if (!panning && !_imageRect.Contains(point)) return;
        var imagePoint = ToImage(point);
        var anchored = FindLeaderAnchor(point);
        var handleHit = FindResizeHandle(point);
        var grabbed = FindMoveHandle(point) ?? HitTestAnnotation(imagePoint);
        var under = HitTestAnnotation(imagePoint);
        // One order for every tool, and no branch per tool: whatever is in the hand, the corners of
        // the selected mark, the anchor of a comment and the mark under the cursor answer before a
        // new mark is begun. The rule itself lives in AnnotationRules, where a test can reach it.
        switch (AnnotationRules.PressTargetOf(Tool, panning, clickCount,
            onAnchor: anchored is not null, onSelectedHandle: handleHit.Annotation is not null,
            onObject: grabbed is not null, activatable: under is { Kind: EditorTool.Text or EditorTool.Comment }))
        {
            case AnnotationRules.PressTarget.Pan:
                _panStart = point;
                _panOrigin = ViewOffset;
                CaptureMouse();
                return;

            // The eraser draws nothing: it removes the mark under the pointer and tells the window,
            // which turns that into one history entry, exactly as the Delete key does.
            case AnnotationRules.PressTarget.Erase:
                if (EraseTarget(point) is not { } target || Annotations is null) return;
                Select(null);
                Annotations.Remove(target);
                _eraseHover = null;
                AnnotationChanged?.Invoke(this, EventArgs.Empty);
                InvalidateVisual();
                return;

            // A double click opens what can be typed into: the text editor for a caption, the note
            // pill for a comment. On a frame or an arrow it is two single clicks, that is, a
            // selection, and it falls through to the branches below.
            case AnnotationRules.PressTarget.Activate:
                Select(under);
                AnnotationActivated?.Invoke(this, under!);
                return;

            // The anchor of a leader is taken before the resize handles: it sits on the point of a
            // comment, a place where the handle of a neighbouring mark may lie as well.
            case AnnotationRules.PressTarget.CommentAnchor:
                Select(anchored);
                _anchorDrag = anchored;
                _anchorOriginPoints = [.. anchored!.Points];
                _anchorOriginOffset = anchored.NoteOffset;
                _anchorDragStart = imagePoint;
                _anchorMoved = false;
                CaptureMouse();
                return;

            case AnnotationRules.PressTarget.ResizeHandle:
            case AnnotationRules.PressTarget.Object:
                var hit = handleHit.Annotation ?? grabbed;
                Select(hit);
                if (hit is null) return;
                // The badge of a comment travels on its own and the point it is attached to stays:
                // that is what the leader is for. Moving the two together is what the anchor does.
                if (hit.Kind == EditorTool.Comment && handleHit.Annotation is null)
                {
                    _badgeDrag = hit;
                    _badgeOriginOffset = hit.NoteOffset;
                    _badgeDragStart = imagePoint;
                    _badgeMoved = false;
                    CaptureMouse();
                    return;
                }
                _gestureStart = imagePoint;
                _originalPoints = [.. hit.Points];
                _originalAdditionalSegments = hit.AdditionalPathSegments.Select(segment => segment.ToList()).ToList();
                _originalBounds = BoundsOf(hit);
                _resizeCorner = handleHit.Corner;
                _resizing = _resizeCorner >= 0;
                _manipulating = true;
                _manipulationChanged = false;
                _manipulationMoved = false;
                CaptureMouse();
                return;

            // The pointer over an empty place: the selection goes and nothing is begun. It draws no
            // mark of its own, and a draft of its kind would reach session.json and the export.
            case AnnotationRules.PressTarget.Deselect:
                Select(null);
                return;
        }

        // A press on an empty part of the capture, or the frame of a crop over whatever lies under
        // it: the selection is dropped at once, and from now on the panel belongs to the next mark.
        Select(null);
        _gestureStart = imagePoint;
        _draft = new AnnotationItem
        {
            Kind = Tool, ArrowStyle = ActiveArrowStyle,
            // The shape and the fill belong to the frame: on a text or a pen mark they would only
            // travel into session.json and change what a later build draws there.
            // A region and a blur share the frame the user picked; on a text or a pen mark the shape
            // would only travel into session.json and change what a later build draws there.
            Shape = Tool is EditorTool.Rectangle or EditorTool.Blur ? ActiveShape : AnnotationShape.Rectangle,
            Fill = Tool == EditorTool.Rectangle ? ActiveFill : AnnotationFill.None,
            FillColor = Tool == EditorTool.Rectangle ? ActiveFillColor : null,
            Color = ActiveColor,
            Thickness = ActiveThickness,
            LineStyle = ActiveLineStyle,
            // The word a new caption starts with comes from the table of the interface: an English
            // window must not get a Russian one.
            Text = Tool == EditorTool.Text ? UiLanguage.Text("Текст") : string.Empty,
            FontSize = ActiveFontSize,
            Points = [_gestureStart.Value, _gestureStart.Value]
        };
        CaptureMouse();
        InvalidateVisual();
    }

    protected override void OnMouseMove(MouseEventArgs e)
    {
        base.OnMouseMove(e);
        UpdateGesture(e.GetPosition(this), e.LeftButton == MouseButtonState.Pressed);
    }

    internal void UpdateGesture(Point displayPoint, bool pressed)
    {
        // The picture travels under the pointer, and nothing else moves: the marks keep the pixels
        // of the capture they were put on.
        if (_panStart is { } panStart && pressed)
        {
            ViewOffset = _panOrigin - (displayPoint - panStart);
            InvalidateVisual();
            return;
        }
        // The anchor travels and its badge stays: the note keeps the place it was put in, so the
        // offset of the badge gives back exactly what the anchor takes, and the leader grows between
        // the two. A note that was never moved has no offset to compensate, and its badge follows.
        if (_anchorDrag is { } anchored && _anchorOriginPoints is not null && pressed)
        {
            var moved = ClampToImage(ToImage(displayPoint)) - _anchorDragStart;
            if (!_anchorMoved && moved.Length * (_imageRect.Width / Image!.PixelWidth) < 4) return;
            _anchorMoved = true;
            for (var i = 0; i < anchored.Points.Count && i < _anchorOriginPoints.Count; i++)
                anchored.Points[i] = ClampToImage(_anchorOriginPoints[i] + moved);
            if (_anchorOriginOffset is { } offset)
                anchored.NoteOffset = new Point(offset.X - moved.X, offset.Y - moved.Y);
            InvalidateVisual();
            return;
        }
        // The badge travels and the point stays: no clamp to the picture here on purpose, a badge
        // carried out beyond its edge is what the margin of the exported PNG is made for.
        if (_badgeDrag is { } badged && pressed)
        {
            var moved = ToImage(displayPoint) - _badgeDragStart;
            if (!_badgeMoved && moved.Length * (_imageRect.Width / Image!.PixelWidth) < GestureThreshold) return;
            _badgeMoved = true;
            var origin = _badgeOriginOffset ?? default;
            badged.NoteOffset = new Point(origin.X + moved.X, origin.Y + moved.Y);
            InvalidateVisual();
            return;
        }
        if (_manipulating && SelectedAnnotation is not null && _gestureStart is not null && _originalPoints is not null && pressed)
        {
            var current = ClampToImage(ToImage(displayPoint));
            // A click on a mark with a pixel of tremor in it is a click and not a drag: without the
            // gate below every press on a selected mark wrote an entry of the history. The threshold
            // is the one the anchor and a new mark are both measured by, and it is measured on
            // screen, not in the pixels of the capture.
            if (!_manipulationMoved && (current - _gestureStart.Value).Length * (_imageRect.Width / Image!.PixelWidth) < GestureThreshold) return;
            _manipulationMoved = true;
            if (_resizing)
            {
                var resized = ResizeGeometry.Resize(_originalBounds, _resizeCorner, current,
                    new Rect(0, 0, Image!.PixelWidth, Image.PixelHeight), 2);
                for (var i = 0; i < SelectedAnnotation.Points.Count; i++)
                    SelectedAnnotation.Points[i] = ResizeGeometry.Map(_originalPoints[i], _originalBounds, resized);
                for (var segmentIndex = 0; segmentIndex < SelectedAnnotation.AdditionalPathSegments.Count; segmentIndex++)
                    for (var pointIndex = 0; pointIndex < SelectedAnnotation.AdditionalPathSegments[segmentIndex].Count; pointIndex++)
                        SelectedAnnotation.AdditionalPathSegments[segmentIndex][pointIndex] = ResizeGeometry.Map(
                            _originalAdditionalSegments![segmentIndex][pointIndex], _originalBounds, resized);
            }
            else
            {
                var delta = current - _gestureStart.Value;
                delta.X = Math.Clamp(delta.X, -_originalBounds.Left, Image!.PixelWidth - _originalBounds.Right);
                delta.Y = Math.Clamp(delta.Y, -_originalBounds.Top, Image.PixelHeight - _originalBounds.Bottom);
                for (var i = 0; i < SelectedAnnotation.Points.Count; i++) SelectedAnnotation.Points[i] = _originalPoints[i] + delta;
                for (var segmentIndex = 0; segmentIndex < SelectedAnnotation.AdditionalPathSegments.Count; segmentIndex++)
                    for (var pointIndex = 0; pointIndex < SelectedAnnotation.AdditionalPathSegments[segmentIndex].Count; pointIndex++)
                        SelectedAnnotation.AdditionalPathSegments[segmentIndex][pointIndex] = _originalAdditionalSegments![segmentIndex][pointIndex] + delta;
            }
            InvalidateVisual();
            _manipulationChanged = true;
            return;
        }
        if (_draft is null || _gestureStart is null || !pressed)
        {
            UpdateCursor(displayPoint);
            return;
        }
        // A comment is put down by "press and drag": the press fixes the point, and what the hand
        // drags away is the badge, not the second point of the mark. No clamp, as above.
        if (_draft.Kind == EditorTool.Comment)
        {
            var carried = ToImage(displayPoint) - _gestureStart.Value;
            _draft.NoteOffset = new Point(carried.X, carried.Y);
            InvalidateVisual();
            return;
        }
        var point = ClampToImage(ToImage(displayPoint));
        if (_draft.Kind is EditorTool.Pen or EditorTool.Highlight)
            _draft.Points.Add(point);
        else if (_draft.Points.Count > 1)
            _draft.Points[1] = point;
        InvalidateVisual();
    }

    // The pointer says what the next press will do: arrows on the corners of a selected mark, a hand
    // where a mark can be grabbed, a crosshair over the capture with a drawing tool armed, and the
    // ordinary arrow everywhere else.
    private void UpdateCursor(Point displayPoint)
    {
        // Space is held: whatever stands under the pointer, the next press drags the picture.
        if (Panning && ViewScale is not null) { Cursor = Cursors.Hand; return; }
        if (Tool == EditorTool.Eraser)
        {
            var hover = EraseTarget(displayPoint);
            if (!ReferenceEquals(hover, _eraseHover)) { _eraseHover = hover; InvalidateVisual(); }
            Cursor = hover is null ? Cursors.Arrow : Cursors.Hand;
            return;
        }
        if (_eraseHover is not null) { _eraseHover = null; InvalidateVisual(); }
        // The anchor is asked first here for the same reason it is asked first on a press: it has to
        // answer for the pixels it covers, handles of neighbouring marks included.
        var anchorHover = FindLeaderAnchor(displayPoint)?.Id;
        if (anchorHover != _anchorHover) { _anchorHover = anchorHover; InvalidateVisual(); }
        if (anchorHover is not null) { Cursor = Cursors.Hand; return; }
        var handle = FindResizeHandle(displayPoint);
        if (handle.Corner >= 0) { Cursor = handle.Corner is 0 or 2 ? Cursors.SizeNWSE : Cursors.SizeNESW; return; }
        // A pin is grabbed whatever tool is in the hand now, and the pointer says so. The badge
        // under the pointer is told to the window as well: pointing at a number opens its note.
        var grabbed = FindMoveHandle(displayPoint);
        var badge = grabbed is { Kind: EditorTool.Comment } ? grabbed : null;
        if (badge?.Id != _badgeHover) { _badgeHover = badge?.Id; NoteHovered?.Invoke(this, badge); }
        Cursor = grabbed is not null ? Cursors.Hand
            : IsDrawingTool(Tool) && _imageRect.Contains(displayPoint) ? Cursors.Cross
            : Cursors.Arrow;
    }

    private static bool IsDrawingTool(EditorTool tool) => tool is not (EditorTool.Select or EditorTool.Eraser);

    // The eraser takes whatever the hand can already grab: the edge of a frame, the line of an
    // arrow, the stroke of a pen, the badge of a comment, the inside of a filled or blurred region.
    private AnnotationItem? EraseTarget(Point displayPoint) =>
        FindMoveHandle(displayPoint) ?? HitTestAnnotation(ToImage(displayPoint));

    protected override void OnMouseLeftButtonUp(MouseButtonEventArgs e)
    {
        base.OnMouseLeftButtonUp(e);
        EndGesture();
    }

    // The gesture is closed before the capture is given back, and never the other way round:
    // releasing it raises LostMouseCapture, and the handler there drops whatever a gesture has
    // left behind. A gesture that ends properly must have nothing left for it to drop.
    internal void EndGesture()
    {
        if (_panStart is not null)
        {
            _panStart = null;
            ReleaseMouseCapture();
            return;
        }
        if (_anchorDrag is not null)
        {
            var moved = _anchorMoved;
            _anchorDrag = null;
            _anchorOriginPoints = null;
            _anchorOriginOffset = null;
            _anchorMoved = false;
            ReleaseMouseCapture();
            // One entry of history for one drag, the way a moved note writes one.
            if (moved) AnnotationChanged?.Invoke(this, EventArgs.Empty);
            InvalidateVisual();
            return;
        }
        if (_badgeDrag is not null)
        {
            var carried = _badgeMoved;
            _badgeDrag = null;
            _badgeOriginOffset = null;
            _badgeMoved = false;
            ReleaseMouseCapture();
            // One entry of the history for one drag, the way the anchor writes one.
            if (carried) AnnotationChanged?.Invoke(this, EventArgs.Empty);
            InvalidateVisual();
            return;
        }
        if (_manipulating)
        {
            _manipulating = false;
            _resizing = false;
            _gestureStart = null;
            _originalPoints = null;
            _originalAdditionalSegments = null;
            ReleaseMouseCapture();
            if (_manipulationChanged) AnnotationChanged?.Invoke(this, EventArgs.Empty);
            InvalidateVisual();
            return;
        }
        if (_draft is null) return;
        var finished = _draft;
        _draft = null;
        _gestureStart = null;
        ReleaseMouseCapture();
        // A press that did not travel is a click, and a click puts the badge on the point it was
        // put down at: an offset shorter than the threshold is no offset at all.
        if (finished.Kind == EditorTool.Comment && finished.NoteOffset is { } carriedTo &&
            new Vector(carriedTo.X, carriedTo.Y).Length * (_imageRect.Width / Image!.PixelWidth) < GestureThreshold)
            finished.NoteOffset = null;
        if (GestureHasSize(finished))
        {
            if (finished.Kind == EditorTool.Crop)
                CropRequested?.Invoke(BoundsOf(finished));
            else
            {
                finished.Label = string.Empty;
                // A caption owns the box its letters take, from the moment it is placed.
                TextMarkMetrics.Fit(finished);
                Annotations?.Add(finished);
                // A stroke of the pen or the highlighter is not selected after the hand lets go: it
                // is drawing, not an object to adjust. Everything else is selected, as before.
                if (finished.Kind is not (EditorTool.Pen or EditorTool.Highlight)) Select(finished);
                AnnotationCreated?.Invoke(this, finished);
            }
        }
        InvalidateVisual();
    }

    // The capture can be taken away in the middle of a gesture: Alt+Tab, the capture shortcut, a
    // dialog of another application. What was being drawn or dragged is dropped there and then —
    // a draft left behind is painted as a ghost until the next press, and a manipulation left
    // behind reports a change on the next mouse up and writes one history entry for a gesture that
    // nobody finished.
    protected override void OnLostMouseCapture(MouseEventArgs e)
    {
        base.OnLostMouseCapture(e);
        _panStart = null;
        if (_anchorDrag is not null)
        {
            _anchorDrag = null;
            _anchorOriginPoints = null;
            _anchorOriginOffset = null;
            _anchorMoved = false;
        }
        if (_badgeDrag is not null)
        {
            _badgeDrag = null;
            _badgeOriginOffset = null;
            _badgeMoved = false;
        }
        if (_draft is null && !_manipulating) return;
        _draft = null;
        _gestureStart = null;
        _manipulating = false;
        _resizing = false;
        _manipulationChanged = false;
        _manipulationMoved = false;
        _originalPoints = null;
        _originalAdditionalSegments = null;
        InvalidateVisual();
    }

    // The red outline of the eraser belongs to where the pointer is, and the pointer is gone:
    // UpdateCursor only runs over the canvas, so it would leave the outline on the capture until
    // the next movement over it.
    protected override void OnMouseLeave(MouseEventArgs e)
    {
        base.OnMouseLeave(e);
        ClearEraseHover();
    }

    private void ClearEraseHover()
    {
        if (_eraseHover is null) return;
        _eraseHover = null;
        InvalidateVisual();
    }

    protected override void OnKeyDown(KeyEventArgs e)
    {
        if (e.Key == Key.Delete && SelectedAnnotation is not null && Annotations is not null)
        {
            var removed = SelectedAnnotation;
            Select(null);
            Annotations.Remove(removed);
            AnnotationChanged?.Invoke(this, EventArgs.Empty);
            e.Handled = true;
        }
        // Escape gives up what is going on, one step at a time: the mark being drawn first, the
        // selection after it. Only with neither of them does the window itself hear the key.
        else if (e.Key == Key.Escape && _draft is not null)
        {
            _draft = null;
            _gestureStart = null;
            ReleaseMouseCapture();
            InvalidateVisual();
            e.Handled = true;
        }
        else if (e.Key == Key.Escape && SelectedAnnotation is not null)
        {
            Select(null);
            e.Handled = true;
        }
        base.OnKeyDown(e);
    }

    public void SelectAnnotation(Guid? id) => Select(id is null ? null : Annotations?.FirstOrDefault(a => a.Id == id));

    public Rect GetDisplayBounds(AnnotationItem annotation)
    {
        if (Image is null) return Rect.Empty;
        var bounds = BoundsOf(annotation);
        return new Rect(
            _imageRect.X + bounds.X * _imageRect.Width / Image.PixelWidth,
            _imageRect.Y + bounds.Y * _imageRect.Height / Image.PixelHeight,
            bounds.Width * _imageRect.Width / Image.PixelWidth,
            bounds.Height * _imageRect.Height / Image.PixelHeight);
    }

    public BitmapSource RenderAnnotated()
    {
        if (Image is null) throw new InvalidOperationException("No image is loaded.");
        var visual = new DrawingVisual();
        using (var dc = visual.RenderOpen())
        {
            var pixelRect = new Rect(0, 0, Image.PixelWidth, Image.PixelHeight);
            dc.DrawImage(ApplyBlurAnnotations(Image), pixelRect);
            if (Annotations is not null)
            {
                foreach (var annotation in Annotations.Where(a => a.Kind != EditorTool.Blur && !HasOpaqueFill(a))) DrawAnnotation(dc, annotation, pixelRect, includeSelection: false, drawLabel: false);
                foreach (var annotation in Annotations.Where(HasOpaqueFill)) DrawAnnotation(dc, annotation, pixelRect, includeSelection: false, drawLabel: false);
                foreach (var annotation in Annotations) DrawAnnotation(dc, annotation, pixelRect, includeSelection: false, drawShape: false);
            }
        }
        var bitmap = new RenderTargetBitmap(Image.PixelWidth, Image.PixelHeight, 96, 96, PixelFormats.Pbgra32);
        bitmap.Render(visual);
        bitmap.Freeze();
        return bitmap;
    }

    private void Select(AnnotationItem? annotation)
    {
        if (Annotations is not null)
            foreach (var item in Annotations) item.IsSelected = ReferenceEquals(item, annotation);
        SelectedAnnotation = annotation;
        SelectionChanged?.Invoke(this, annotation);
        InvalidateVisual();
    }

    // The corners belong to the selected mark and to no other: they are drawn on it alone, and a
    // corner that answers where nothing is drawn promises a resize the press will not make. Every
    // tool is offered them, the comment included — one order of the press for all of them.
    private (AnnotationItem? Annotation, int Corner) FindResizeHandle(Point displayPoint)
    {
        if (Image is null || Annotations is null) return (null, -1);
        if (SelectedAnnotation is not { } selected || !HasResizeHandles(selected)) return (null, -1);
        var corner = ResizeGeometry.HitCorner(GetDisplayBounds(selected), displayPoint, 10);
        return corner >= 0 ? (selected, corner) : (null, -1);
    }
    private AnnotationItem? HitTestAnnotation(Point imagePoint)
    {
        if (Annotations is null) return null;
        for (var i = Annotations.Count - 1; i >= 0; i--)
        {
            var bounds = BoundsOf(Annotations[i]);
            // The box is drawn through the middle of the stroke, so it is widened by half of it and
            // a little to grab by. Twice the whole width was the same thing while the thickness of
            // the highlighter meant a quarter of its real one; with the real width it reached 96 px,
            // and the eraser took strokes the hand was nowhere near. A caption is the exception: its
            // thickness has nothing to do with the size of its letters, so a caption of twelve
            // pixels would be caught by a band of eight all round it and cover its neighbours.
            var reach = Annotations[i].Kind == EditorTool.Text ? 4 : Math.Max(8, Annotations[i].Thickness / 2 + 4);
            bounds.Inflate(reach, reach);
            if (bounds.Contains(imagePoint)) return Annotations[i];
        }
        return null;
    }

    private void DrawAnnotation(DrawingContext dc, AnnotationItem item, Rect target, bool includeSelection = true, bool drawShape = true, bool drawLabel = true)
    {
        if (Image is null || item.Points.Count == 0) return;
        Point Map(Point p) => new(target.X + p.X * target.Width / Image.PixelWidth, target.Y + p.Y * target.Height / Image.PixelHeight);
        var scale = target.Width / Image.PixelWidth;
        var thickness = Math.Max(1.5, item.Thickness * scale);
        var brush = new SolidColorBrush(item.Color);
        brush.Freeze();
        var pen = StrokePattern.Apply(
            new Pen(brush, thickness) { StartLineCap = PenLineCap.Round, EndLineCap = PenLineCap.Round, LineJoin = PenLineJoin.Round },
            StrokePattern.Of(item.Kind, item.LineStyle));
        pen.Freeze();

        if (drawShape && item.Kind is (EditorTool.Pen or EditorTool.Highlight))
        {
            var stroke = StrokeGeometry(PathSegmentsOf(item), Map);
            if (item.Kind == EditorTool.Highlight) DrawHighlightStroke(dc, stroke, brush, thickness);
            else dc.DrawGeometry(null, pen, stroke);
        }
        else if (drawShape && item.Points.Count > 1)
        {
            var start = Map(item.Points[0]);
            var end = Map(item.Points[1]);
            var rect = new Rect(start, end);
            switch (item.Kind)
            {
                case EditorTool.Rectangle:
                    DrawBoxShape(dc, item, rect, pen, scale);
                    break;
                case EditorTool.Blur:
                    // The preview of a blur that is still being drawn shows the shape it will take.
                    DrawBoxShape(dc, new SolidColorBrush(Color.FromArgb(54, 255, 255, 255)),
                        AccentPalette.Pen(1.5), item.Shape, rect, scale);
                    break;
                case EditorTool.Crop:
                    dc.DrawRectangle(AccentPalette.Wash(24), new Pen(AccentPalette.Brush, 1.5) { DashStyle = DashStyles.Dash }, rect);
                    break;
                case EditorTool.Text:
                    // The mark being typed is drawn by the text box on top of it, not here.
                    if (EditingTextId == item.Id) break;
                    var formatted = new FormattedText(item.Text, System.Globalization.CultureInfo.CurrentUICulture,
                        FlowDirection.LeftToRight, new Typeface(TextMarkMetrics.FamilyName),
                        TextMarkMetrics.Clamp(item.FontSize) * scale, brush, VisualTreeHelper.GetDpi(this).PixelsPerDip);
                    dc.DrawText(formatted, start);
                    break;
                case EditorTool.Arrow:
                    Snapik.App.Imaging.ArrowDrawing.Draw(dc, start, end, brush, thickness, item.ArrowStyle, StrokePattern.Of(item.Kind, item.LineStyle));
                    break;
            }
        }

        if (drawLabel && !string.IsNullOrEmpty(item.Label))
        {
            var badgeBrush = AccentPalette.Brush;
            var badge = BadgeOf(item, target);
            // A badge dragged away from its mark keeps one hair line back to it.
            if (item.NoteOffset is not null)
            {
                var badgeBounds = BoundsOf(item);
                var outline = new Rect(Map(badgeBounds.TopLeft), Map(badgeBounds.BottomRight));
                if (NoteBadgeGeometry.TryLeader(outline, badge, out var from, out var to))
                    dc.DrawLine(new Pen(badgeBrush, 1), from, to);
            }
            dc.DrawEllipse(badgeBrush, null, badge.Center, badge.Radius, badge.Radius);
            // The anchor of the leader, on screen only: includeSelection is what separates the canvas
            // from RenderAnnotated, and a circle without a number explains nothing to whoever receives
            // the picture. The export draws the leader and the badge, and neither needs a handle.
            // While the note sits on its mark there is no leader, and the anchor would only cover the
            // number in the badge, so it is drawn for a note dragged away.
            if (includeSelection && item.Kind == EditorTool.Comment && item.NoteOffset is not null)
            {
                var anchor = Map(item.Points[0]);
                var radius = _anchorHover == item.Id ? AnchorHoverRadius : AnchorRadius;
                dc.DrawEllipse(badgeBrush, new Pen(Brushes.White, 1.5), anchor, radius, radius);
            }
            var label = new FormattedText(item.Label, System.Globalization.CultureInfo.InvariantCulture, FlowDirection.LeftToRight,
                new Typeface(new FontFamily("Segoe UI Variable Text"), FontStyles.Normal, FontWeights.SemiBold, FontStretches.Normal), 11, Brushes.White, VisualTreeHelper.GetDpi(this).PixelsPerDip);
            dc.DrawText(label, new Point(badge.Center.X - label.Width / 2, badge.Center.Y - label.Height / 2));
        }

        if (includeSelection && item.IsSelected && HasResizeHandles(item))
        {
            var bounds = BoundsOf(item);
            var topLeft = Map(bounds.TopLeft);
            var bottomRight = Map(bounds.BottomRight);
            var selectedRect = new Rect(topLeft, bottomRight);

            dc.DrawRectangle(null, new Pen(AccentPalette.Brush, 1) { DashStyle = DashStyles.Dash }, selectedRect);
            foreach (var corner in ResizeGeometry.Corners(selectedRect))
                dc.DrawRectangle(Brushes.White, AccentPalette.Pen(1.5), new Rect(corner.X - 4, corner.Y - 4, 8, 8));
        }
    }

    // How transparent a highlighter is. One number for both renderers, applied to the whole stroke
    // at once rather than to the brush: transparent ink laid segment by segment piles up at every
    // joint, and a highlighter drawn that way came out as a ragged pen.
    internal const double HighlightOpacity = 0.4;

    // A stroke is one geometry, not a line per pair of points: the points of a freehand mark are
    // dense, so a hundred round caps used to be painted over each other.
    internal static Geometry StrokeGeometry<TPoint>(IEnumerable<IReadOnlyList<TPoint>> segments, Func<TPoint, Point> map)
    {
        var geometry = new StreamGeometry();
        using (var context = geometry.Open())
            foreach (var segment in segments.Where(points => points.Count > 1))
            {
                context.BeginFigure(map(segment[0]), false, false);
                context.PolyLineTo(segment.Skip(1).Select(map).ToArray(), true, false);
            }
        geometry.Freeze();
        return geometry;
    }

    // Square ends and flat joints, and the whole stroke made transparent once: that is what makes a
    // highlighter read as a highlighter beside the pencil.
    internal static void DrawHighlightStroke(DrawingContext dc, Geometry stroke, Brush brush, double thickness)
    {
        var pen = new Pen(brush, thickness)
        {
            StartLineCap = PenLineCap.Square, EndLineCap = PenLineCap.Square, LineJoin = PenLineJoin.Bevel
        };
        pen.Freeze();
        dc.PushOpacity(HighlightOpacity);
        dc.DrawGeometry(null, pen, stroke);
        dc.Pop();
    }

    private static IEnumerable<IReadOnlyList<Point>> PathSegmentsOf(AnnotationItem item) =>
        new[] { (IReadOnlyList<Point>)item.Points }.Concat(item.AdditionalPathSegments);

    // The frame of a region: the outline follows Shape, what stands inside it follows Fill. The
    // export renderer draws the same three shapes from the same numbers, in image pixels.
    internal static void DrawBoxShape(DrawingContext dc, Brush? fill, Pen? pen, AnnotationShape shape, Rect rect, double scale)
    {
        switch (shape)
        {
            case AnnotationShape.Ellipse:
                dc.DrawEllipse(fill, pen, new Point(rect.X + rect.Width / 2, rect.Y + rect.Height / 2), rect.Width / 2, rect.Height / 2);
                break;
            case AnnotationShape.Rounded:
                // The same corner the blur mask rounds, so an outline and the blur inside it agree.
                var radius = Math.Min(ShapeMask.MaximumCornerRadius * scale, Math.Min(rect.Width, rect.Height) / 4);
                dc.DrawRoundedRectangle(fill, pen, rect, radius, radius);
                break;
            default:
                dc.DrawRectangle(fill, pen, rect);
                break;
        }
    }

    // The blur fill is baked into the picture before the marks are drawn, so nothing is painted over
    // the region here: only its outline, if it has one.
    internal static Brush? ShapeFillBrush(Color color, AnnotationFill fill) => fill switch
    {
        AnnotationFill.Solid => new SolidColorBrush(color),
        AnnotationFill.Translucent => new SolidColorBrush(Color.FromArgb(64, color.R, color.G, color.B)),
        _ => null
    };

    // An opaque fill is drawn after every other mark, because it hides whatever stands under it;
    // that is what the conceal tool used to do, and a solid region does the same.
    internal static bool HasOpaqueFill(AnnotationItem item) =>
        item.Kind == EditorTool.Rectangle && item.Fill == AnnotationFill.Solid;

    private static void DrawBoxShape(DrawingContext dc, AnnotationItem item, Rect rect, Pen pen, double scale)
    {
        // The pen arrives painted with the colour of the mark, so the outline of a filled box is
        // rebuilt here; the thickness and the pattern of the stroke come from that pen unchanged.
        var outline = AnnotationRules.OutlineColorOf(item.Fill, item.Color);
        var outlinePen = outline is { } oc ? new Pen(new SolidColorBrush(oc), pen.Thickness) { DashStyle = pen.DashStyle } : null;
        DrawBoxShape(dc, ShapeFillBrush(item.FillColor ?? item.Color, item.Fill), outlinePen, item.Shape, rect, scale);
    }

    // A caption is not stretched by its corners: the box around it is the letters, and their size
    // is set by the button on the panel. It is moved and it is retyped, like a comment pin.
    private static bool HasResizeHandles(AnnotationItem item) => item.Kind is not (EditorTool.Comment or EditorTool.Text);

    // "Press and drag" is measured on screen, not in the pixels of the capture: at the scale a
    // 1920 px capture is shown with, three image pixels are under two pixels of hand tremor.
    private const double GestureThreshold = 4;

    private bool GestureHasSize(AnnotationItem item)
    {
        // A text mark and a comment pin are placed by a single click, as they always were.
        if (item.Kind is EditorTool.Comment or EditorTool.Text) return true;
        if (item.Points.Count < 2) return false;
        if (item.Kind is EditorTool.Pen or EditorTool.Highlight) return item.Points.Count > 2;
        var scale = Image is null || _imageRect.Width <= 0 ? 1 : _imageRect.Width / Image.PixelWidth;
        return (item.Points[1] - item.Points[0]).Length * scale >= GestureThreshold;
    }

    // Every mark can be grabbed and moved whatever tool is armed: a box by the band along its
    // outline, a line by the line itself, a comment by its badge. The interior of a frame stays
    // free for the next drawing, except where the mark is opaque and there is nothing to draw into.
    // The circle at the point a comment is attached to: the visible end of the leader, and the only
    // way to move that end without moving the note with it. A comment without a number has no badge
    // and no leader yet, so it has no anchor either. It answers whatever is in the hand: one order
    // of the press for every tool, and what is already drawn answers before a new mark is begun.
    private AnnotationItem? FindLeaderAnchor(Point point)
    {
        if (Annotations is null || Image is null) return null;
        return Annotations.Reverse().FirstOrDefault(item =>
            item.Kind == EditorTool.Comment && !string.IsNullOrEmpty(item.Label) && item.Points.Count > 0 &&
            (point - ToDisplay(item.Points[0])).Length <= AnchorHoverRadius);
    }

    // Five pixels of circle and seven of reach: the circle grows to the reach under the pointer, so
    // what answers the press is what is seen at that moment.
    private const double AnchorRadius = 5;
    private const double AnchorHoverRadius = 7;

    private AnnotationItem? FindMoveHandle(Point point)
    {
        if (Annotations is null || Image is null) return null;
        return Annotations.Reverse().FirstOrDefault(a => IsMoveHandle(a, point));
    }

    private bool IsMoveHandle(AnnotationItem item, Point point)
    {
        if (item.Points.Count == 0 || Image is null) return false;
        var scale = _imageRect.Width / Image.PixelWidth;
        var band = Math.Max(6, item.Thickness * scale);
        switch (item.Kind)
        {
            case EditorTool.Comment:
                return BadgeOf(item, _imageRect).Contains(point, 4);
            case EditorTool.Arrow:
            {
                if (item.Points.Count < 2) return false;
                var shaft = ArrowDrawing.Shaft(ToDisplay(item.Points[0]), ToDisplay(item.Points[1]), item.ArrowStyle);
                return DistanceToPolyline(shaft, point) <= band;
            }
            case EditorTool.Pen:
            case EditorTool.Highlight:
            {
                // Half the stroke plus a little slack: the thickness of a mark is the width it is
                // really drawn with now, for the highlighter as well as for the pencil.
                var width = Math.Max(6, item.Thickness * scale / 2 + 4);
                foreach (var segment in PathSegmentsOf(item))
                    if (DistanceToPolyline(segment.Select(ToDisplay).ToArray(), point) <= width) return true;
                return false;
            }
            default:
            {
                // One band for every mark and every tool: eight pixels, which is what a hand hits.
                // A band that changed width with the tool in the hand made the same press mean two
                // things on the same pixel. The interior of an empty frame stays free to draw into.
                const double reach = 8;
                var bounds = GetDisplayBounds(item);
                var outer = bounds; outer.Inflate(reach, reach);
                if (!outer.Contains(point)) return false;
                // An opaque mark has no free interior, and a small one has no room for a band.
                if (HasInteriorGrab(item) || bounds.Width < 24 || bounds.Height < 24) return true;
                var inner = bounds;
                inner.Inflate(-Math.Min(reach, inner.Width / 2), -Math.Min(reach, inner.Height / 2));
                return !inner.Contains(point);
            }
        }
    }

    // Opaque marks are grabbed anywhere inside, and so is a filled frame; the fill of any other
    // kind means nothing on screen, so its interior stays free for a new mark. A text mark is its
    // own interior — the box around it is the letters, not an empty frame to draw into.
    private static bool HasInteriorGrab(AnnotationItem item) =>
        item.Kind is EditorTool.Blur or EditorTool.Text || (item.Kind == EditorTool.Rectangle && item.Fill != AnnotationFill.None);

    private NoteBadge BadgeOf(AnnotationItem item, Rect target)
    {
        var anchor = new Point(
            target.X + item.Points[0].X * target.Width / Image!.PixelWidth,
            target.Y + item.Points[0].Y * target.Height / Image.PixelHeight);
        // A pin without a note carries no badge yet, but it still has to be grabbable.
        if (item.Kind == EditorTool.Comment && string.IsNullOrEmpty(item.Label)) return new NoteBadge(anchor, 13);
        var offset = item.NoteOffset is { } shift
            ? new Vector(shift.X * target.Width / Image.PixelWidth, shift.Y * target.Height / Image.PixelHeight)
            : default;
        return NoteBadgeGeometry.Screen(anchor, item.Label, offset);
    }

    // Where the badge of a note is on the picture, and how large it is: the pill of that note stands
    // beside the circle now, so it needs the middle of it and its edge both.
    public Point GetBadgeCenter(AnnotationItem annotation) =>
        Image is null || annotation.Points.Count == 0 ? default : BadgeOf(annotation, _imageRect).Center;

    public double GetBadgeRadius(AnnotationItem annotation) =>
        Image is null || annotation.Points.Count == 0 ? 13 : BadgeOf(annotation, _imageRect).Radius;

    private Point ToDisplay(Point imagePoint) => new(
        _imageRect.X + imagePoint.X * _imageRect.Width / Image!.PixelWidth,
        _imageRect.Y + imagePoint.Y * _imageRect.Height / Image.PixelHeight);

    private static double DistanceToPolyline(IReadOnlyList<Point> points, Point target)
    {
        if (points.Count == 0) return double.PositiveInfinity;
        if (points.Count == 1) return (target - points[0]).Length;
        var best = double.PositiveInfinity;
        for (var i = 1; i < points.Count; i++) best = Math.Min(best, DistanceToSegment(points[i - 1], points[i], target));
        return best;
    }

    private static double DistanceToSegment(Point start, Point end, Point target)
    {
        var line = end - start;
        var lengthSquared = line.LengthSquared;
        if (lengthSquared <= double.Epsilon) return (target - start).Length;
        var position = Math.Clamp((target - start) * line / lengthSquared, 0, 1);
        return (target - (start + line * position)).Length;
    }
    private static Rect BoundsOf(AnnotationItem item)
    {
        if (item.Points.Count == 0) return Rect.Empty;
        var allPoints = item.Points.Concat(item.AdditionalPathSegments.SelectMany(segment => segment)).ToList();
        var minX = allPoints.Min(p => p.X); var minY = allPoints.Min(p => p.Y);
        var maxX = allPoints.Max(p => p.X); var maxY = allPoints.Max(p => p.Y);
        return new Rect(new Point(minX, minY), new Point(maxX, maxY));
    }

    private Point ToImage(Point point)
    {
        if (Image is null || _imageRect.Width <= 0 || _imageRect.Height <= 0) return default;
        return new Point((point.X - _imageRect.X) * Image.PixelWidth / _imageRect.Width, (point.Y - _imageRect.Y) * Image.PixelHeight / _imageRect.Height);
    }

    private Point ClampToImage(Point point) => Image is null ? point : new Point(Math.Clamp(point.X, 0, Image.PixelWidth), Math.Clamp(point.Y, 0, Image.PixelHeight));

    private BitmapSource ApplyBlurAnnotations(BitmapSource source)
    {
        // A region filled with blur is dragged as often as the blur tool itself, and rebuilding the
        // whole frame on every movement of the mouse freezes a 4K capture: both take the cache.
        if (_manipulating && SelectedAnnotation is { } dragged && IsBlurred(dragged) && _blurCache is not null) return _blurCache;
        var hash = new HashCode();
        hash.Add(RuntimeHelpers.GetHashCode(source));
        if (Annotations is not null)
            foreach (var annotation in Annotations.Where(IsBlurred))
            {
                hash.Add(annotation.Id); hash.Add((int)annotation.Shape);
                foreach (var point in annotation.Points) { hash.Add(point.X); hash.Add(point.Y); }
            }
        var key = hash.ToHashCode();
        if (_blurCache is not null && key == _blurCacheKey) return _blurCache;
        BitmapSource result = source;
        if (Annotations is not null)
            foreach (var annotation in Annotations.Where(a => IsBlurred(a) && a.Points.Count > 1))
            {
                var region = ToPixelRect(BoundsOf(annotation), source.PixelWidth, source.PixelHeight);
                result = RegionBlur.Apply(result, region, RegionBlur.RadiusFor(region.Width, region.Height), annotation.Shape);
            }
        _blurCacheKey = key;
        _blurCache = result;
        return _blurCache;
    }

    // The blur tool and a region filled with blur bake the same pixels into the picture, so one rule
    // decides what is blurred and both take the same code below.
    internal static bool IsBlurred(AnnotationItem item) =>
        item.Kind == EditorTool.Blur || (item.Kind == EditorTool.Rectangle && item.Fill == AnnotationFill.Blur);

    private static Int32Rect ToPixelRect(Rect bounds, int width, int height)
    {
        var left = Math.Clamp((int)Math.Floor(bounds.Left), 0, width);
        var top = Math.Clamp((int)Math.Floor(bounds.Top), 0, height);
        var right = Math.Clamp((int)Math.Ceiling(bounds.Right), left, width);
        var bottom = Math.Clamp((int)Math.Ceiling(bounds.Bottom), top, height);
        return new Int32Rect(left, top, right - left, bottom - top);
    }

    // The picture at a scale of its own: the offset is held first, so no edge of it ever comes
    // inside the canvas, and a picture shorter than the canvas is centred along that axis.
    private Rect ScaledRect(double scale)
    {
        var image = new Size(Image!.PixelWidth, Image.PixelHeight);
        ViewOffset = EditorGeometry.ClampOffset(image, scale, new Size(ActualWidth, ActualHeight), ViewOffset);
        return new Rect(-ViewOffset.X, -ViewOffset.Y, image.Width * scale, image.Height * scale);
    }

    // The wheel scrolls the picture only while it is shown at a scale of its own: fitted, there is
    // nothing to scroll. Ctrl and the wheel answer from either state — with the switch beside the
    // panel gone, this is the one way into a scale of one's own.
    protected override void OnMouseWheel(MouseWheelEventArgs e)
    {
        base.OnMouseWheel(e);
        if (Image is null) return;
        if (ViewScale is null && !Keyboard.Modifiers.HasFlag(ModifierKeys.Control)) return;
        if (Keyboard.Modifiers.HasFlag(ModifierKeys.Control)) ZoomByNotches(e.Delta, e.GetPosition(this));
        else
        {
            var travel = e.Delta * -0.6;
            ViewOffset += Keyboard.Modifiers.HasFlag(ModifierKeys.Shift) ? new Vector(travel, 0) : new Vector(0, travel);
            InvalidateVisual();
        }
        // The wheel must not reach the window behind the canvas, which would scroll something else.
        e.Handled = true;
    }

    /// <summary>
    /// Ctrl and one notch of the wheel, apart from the modifier that carries it: a smoke run has no
    /// keyboard to hold Control down with, and this is the one way into a scale of the canvas's own
    /// now that the switch beside the panel is gone.
    /// </summary>
    internal void ZoomByNotches(double delta, Point cursor)
    {
        if (Image is null) return;
        // The scale the picture stands at right now, a scale of its own or the one it was fitted
        // with. FitScale counts from ActualWidth less ImagePadding twice, and the editor hands the
        // canvas ImagePadding="0", so the seed is the picture on screen to the pixel and the first
        // notch does not make it jump. Put the padding back and it will.
        var scale = ViewScale ?? FitScale;
        // Fitted, the picture is centred by FitRect and ViewOffset is never read; scaled, that
        // offset is what holds it. The centred picture written as an offset is the seed, so the
        // point under the cursor stays where it is on the very first notch.
        var offset = ViewScale is null
            ? new Vector(-(ActualWidth - Image.PixelWidth * scale) / 2, -(ActualHeight - Image.PixelHeight * scale) / 2)
            : ViewOffset;
        // A tenth of the scale per notch, between "fit" and the picture at its own size: those two
        // ends and nothing beyond them. A capture small enough to stand at its own size is fitted at
        // a scale of one or above, and the floor and the ceiling meet there — without the floor held
        // down to one, the clamp is asked for a range that runs backwards.
        var floor = Math.Min(FitScale, 1);
        var wanted = Math.Clamp(scale * Math.Pow(1.1, delta / 120.0), floor, 1);
        // Back at the scale the picture is fitted with, the view goes back to fitting.
        if (wanted <= floor) { ViewOffset = default; ViewScale = null; return; }
        ViewOffset = EditorGeometry.ZoomAround(cursor, offset, scale, wanted);
        ViewScale = wanted;
        InvalidateVisual();
    }

    private static Rect FitRect(double imageWidth, double imageHeight, double width, double height, double padding)
    {
        var availableWidth = Math.Max(1, width - padding * 2);
        var availableHeight = Math.Max(1, height - padding * 2);
        var scale = Math.Min(availableWidth / imageWidth, availableHeight / imageHeight);
        var w = imageWidth * scale; var h = imageHeight * scale;
        return new Rect((width - w) / 2, (height - h) / 2, w, h);
    }

    // The rules of a gesture, driven without a mouse: a press that did not travel draws nothing and
    // drops the selection, a real drag makes one mark, a stroke of the pen is not selected after it,
    // and the pointer says what the next press will do wherever it stands.
    internal static void VerifyGestureRules(BitmapSource source)
    {
        var annotations = new ObservableCollection<AnnotationItem>();
        var canvas = new AnnotationCanvas { Image = source, Annotations = annotations, ImagePadding = 0, Width = 480, Height = 300 };
        canvas.Measure(new Size(480, 300));
        canvas.Arrange(new Rect(0, 0, 480, 300));
        // The picture is laid out inside OnRender, and the rules below are measured against it.
        new RenderTargetBitmap(480, 300, 96, 96, PixelFormats.Pbgra32).Render(canvas);

        void Gesture(Point from, params Point[] path)
        {
            canvas.BeginGesture(from);
            foreach (var point in path) canvas.UpdateGesture(point, pressed: true);
            canvas.EndGesture();
        }

        canvas.Tool = EditorTool.Rectangle;
        Gesture(new Point(100, 100));
        if (annotations.Count != 0 || canvas.SelectedAnnotation is not null)
            throw new InvalidOperationException("A click that did not travel must draw nothing and leave nothing selected.");
        Gesture(new Point(100, 100), new Point(102, 100));
        if (annotations.Count != 0)
            throw new InvalidOperationException("Two pixels of tremor must not become a mark.");
        Gesture(new Point(100, 100), new Point(160, 160));
        if (annotations.Count != 1 || !ReferenceEquals(canvas.SelectedAnnotation, annotations[0]))
            throw new InvalidOperationException("A gesture over the threshold must draw one mark and select it.");

        canvas.Tool = EditorTool.Pen;
        Gesture(new Point(200, 200), new Point(220, 215), new Point(250, 240));
        if (annotations.Count != 2 || canvas.SelectedAnnotation is not null)
            throw new InvalidOperationException("A stroke of the pen must be drawn and must not stay selected.");

        // A click on an empty part of the capture drops the selection and draws nothing at all.
        canvas.Tool = EditorTool.Rectangle;
        canvas.SelectAnnotation(annotations[0].Id);
        Gesture(new Point(430, 60));
        if (canvas.SelectedAnnotation is not null || annotations.Count != 2)
            throw new InvalidOperationException("A click on an empty part of the capture must only drop the selection.");

        // And a drag of the pointer over an empty place draws nothing either: the pointer has no
        // mark of its own, and a draft of its kind would reach the session and the exported picture.
        canvas.Tool = EditorTool.Select;
        canvas.SelectAnnotation(annotations[0].Id);
        Gesture(new Point(380, 40), new Point(430, 90));
        if (canvas.SelectedAnnotation is not null || annotations.Count != 2)
            throw new InvalidOperationException("A drag of the pointer over an empty place must draw nothing.");

        var bounds = canvas.GetDisplayBounds(annotations[0]);
        canvas.UpdateGesture(new Point(bounds.Left, bounds.Top + bounds.Height / 2), pressed: false);
        if (canvas.Cursor != Cursors.Hand) throw new InvalidOperationException("The edge of a mark must show the hand cursor.");

        // The eraser: it points at what it will take, takes it on a click, and says so once.
        var changes = 0;
        void Count(object? sender, EventArgs args) => changes++;
        canvas.AnnotationChanged += Count;
        canvas.Tool = EditorTool.Eraser;
        var edge = new Point(bounds.Left, bounds.Top + bounds.Height / 2);
        canvas.UpdateGesture(edge, pressed: false);
        if (canvas.Cursor != Cursors.Hand || !ReferenceEquals(canvas._eraseHover, annotations[0]))
            throw new InvalidOperationException("The eraser must point at the mark under it.");
        canvas.UpdateGesture(new Point(430, 60), pressed: false);
        if (canvas.Cursor != Cursors.Arrow || canvas._eraseHover is not null)
            throw new InvalidOperationException("The eraser must point at nothing over an empty part of the capture.");
        var kept = annotations[1];
        Gesture(edge);
        canvas.AnnotationChanged -= Count;
        if (annotations.Count != 1 || !ReferenceEquals(annotations[0], kept) || changes != 1)
            throw new InvalidOperationException("A click of the eraser must remove one mark and report it once.");
        canvas.Tool = EditorTool.Rectangle;
        canvas.UpdateGesture(new Point(430, 60), pressed: false);
        if (canvas.Cursor != Cursors.Cross) throw new InvalidOperationException("The capture with a drawing tool armed must show the crosshair.");
        canvas.Tool = EditorTool.Select;
        canvas.UpdateGesture(new Point(430, 60), pressed: false);
        if (canvas.Cursor != Cursors.Arrow) throw new InvalidOperationException("The select tool must show the ordinary arrow over the capture.");
        canvas.Tool = EditorTool.Rectangle;
        canvas.UpdateGesture(new Point(240, 5), pressed: false);
        if (canvas.Cursor != Cursors.Arrow) throw new InvalidOperationException("Outside the capture the pointer must be the ordinary arrow.");

        // How far from a mark a click still lands on it, in the pixels of the capture: half the
        // stroke and a little to grab by. The highlighter counts its thickness in real pixels now,
        // and twice the whole width took strokes 96 px away from where the hand was.
        var wide = new AnnotationItem { Kind = EditorTool.Highlight, Thickness = 48 };
        wide.Points.Add(new Point(40, 40));
        wide.Points.Add(new Point(140, 40));
        // The stroke stands alone on the capture, so what the hit test answers is about its reach
        // and about nothing else that was drawn above.
        annotations.Clear();
        annotations.Add(wide);
        if (!ReferenceEquals(canvas.HitTestAnnotation(new Point(90, 40)), wide))
            throw new InvalidOperationException("A stroke of the highlighter must be found where it is drawn.");
        if (canvas.HitTestAnnotation(new Point(90, 80)) is not null)
            throw new InvalidOperationException("A click 40 px away from a highlighter stroke must find nothing.");
        annotations.Remove(wide);

        // The comment tool takes what is already there: a press on the badge of a pin, or on the
        // anchor of its leader, grabs that pin instead of putting a second one beside it, and the
        // tool stays in the hand. A press beside the corner of a selected frame is a new pin, not
        // the corner of that frame.
        // Every point below is taken inside the picture as it is laid out on the canvas: outside it
        // a press is not a gesture at all.
        var area = canvas._imageRect;
        Point In(double x, double y) => new(area.X + area.Width * x, area.Y + area.Height * y);
        canvas.Tool = EditorTool.Comment;
        Gesture(In(.4, .35));
        if (annotations.Count != 1 || annotations[0].Kind != EditorTool.Comment)
            throw new InvalidOperationException("One press with the comment tool must put one pin down.");
        var pinned = annotations[0];
        // A pin answers for its anchor only once it carries a number, and the badge is dragged away
        // from the anchor so that the two are told apart by the press that lands on them.
        pinned.Label = "A1";
        pinned.NoteOffset = new Point(source.PixelWidth * .15, -source.PixelHeight * .1);
        Gesture(canvas.GetBadgeCenter(pinned));
        if (annotations.Count != 1 || !ReferenceEquals(canvas.SelectedAnnotation, pinned) || canvas.Tool != EditorTool.Comment)
            throw new InvalidOperationException("A press on the badge of a pin must select it instead of placing a second one.");
        canvas.SelectAnnotation(null);
        Gesture(canvas.ToDisplay(pinned.Points[0]));
        if (annotations.Count != 1 || !ReferenceEquals(canvas.SelectedAnnotation, pinned) || canvas.Tool != EditorTool.Comment)
            throw new InvalidOperationException("A press on the anchor of a pin must take the anchor instead of placing a second pin.");

        canvas.Tool = EditorTool.Rectangle;
        Gesture(In(.1, .6), In(.45, .9));
        var frame = annotations.Single(item => item.Kind == EditorTool.Rectangle);
        canvas.SelectAnnotation(frame.Id);
        canvas.Tool = EditorTool.Comment;
        // Away from everything drawn: the corners of the selected frame answer to every tool now,
        // and so does the frame itself, so a new pin goes where there is nothing.
        Gesture(In(.8, .12));
        if (annotations.Count(item => item.Kind == EditorTool.Comment) != 2)
            throw new InvalidOperationException("A press on an empty part of the capture with the comment tool must put a pin down.");

        // Rule 1: a click takes what is already drawn, whatever tool is in the hand. With the frame
        // armed, a press on an existing frame selects it instead of beginning a second one; a drag
        // by its outline moves it and writes one entry of the history; and a press that did not
        // travel writes none at all.
        annotations.Clear();
        canvas.SelectAnnotation(null);
        canvas.Tool = EditorTool.Rectangle;
        Gesture(In(.1, .1), In(.45, .45));
        var only = annotations.Single();
        var entries = 0;
        void CountEntries(object? sender, EventArgs args) => entries++;
        canvas.AnnotationChanged += CountEntries;
        var outline = canvas.GetDisplayBounds(only);
        var onOutline = new Point(outline.Left, outline.Top + outline.Height / 2);
        Gesture(onOutline);
        if (annotations.Count != 1 || !ReferenceEquals(canvas.SelectedAnnotation, only) || entries != 0)
            throw new InvalidOperationException("A click on a frame with the frame in the hand must select it and write nothing.");
        var wasAt = only.Points[0];
        Gesture(onOutline, new Point(onOutline.X + 30, onOutline.Y + 20));
        if (entries != 1 || only.Points[0] == wasAt)
            throw new InvalidOperationException($"A drag of a frame by its outline must move it and write one entry of the history: {entries}.");
        canvas.AnnotationChanged -= CountEntries;
        annotations.Clear();
    }

    // A caption is placed by one click, it carries the word of the interface and the size the panel
    // holds, and from that moment its box is the letters: a double click into the middle of the word
    // opens the one that is there instead of making a second one beside it.
    internal static void VerifyTextMarkGeometry(BitmapSource source)
    {
        var annotations = new ObservableCollection<AnnotationItem>();
        var canvas = new AnnotationCanvas
        {
            Image = source, Annotations = annotations, ImagePadding = 0, Width = 480, Height = 300,
            Tool = EditorTool.Text, ActiveFontSize = 32
        };
        canvas.Measure(new Size(480, 300));
        canvas.Arrange(new Rect(0, 0, 480, 300));
        new RenderTargetBitmap(480, 300, 96, 96, PixelFormats.Pbgra32).Render(canvas);

        AnnotationItem? activated = null;
        canvas.AnnotationActivated += (_, item) => activated = item;
        canvas.BeginGesture(new Point(100, 100));
        canvas.EndGesture();
        if (annotations.Count != 1 || annotations[0].Kind != EditorTool.Text ||
            annotations[0].Text != UiLanguage.Text("Текст") || annotations[0].FontSize != 32)
            throw new InvalidOperationException("One click with the text tool must place one caption with the word and the size of the panel.");
        var caption = annotations[0];
        // Measured in the pixels of the capture: on screen the same box is as small as the capture
        // is scaled down to fit the canvas.
        if (caption.Points.Count != 2 || caption.Points[1].X - caption.Points[0].X < caption.FontSize ||
            caption.Points[1].Y - caption.Points[0].Y < caption.FontSize)
            throw new InvalidOperationException("The box of a caption must be the letters it is made of.");
        var box = canvas.GetDisplayBounds(caption);

        canvas.BeginGesture(new Point(box.Left + box.Width / 2, box.Top + box.Height / 2), clickCount: 2);
        canvas.EndGesture();
        if (annotations.Count != 1 || !ReferenceEquals(activated, caption))
            throw new InvalidOperationException("A double click into a caption must open it instead of placing a second one.");
        // Longer letters take a wider box, and the anchor of the mark does not move with them.
        var anchor = caption.Points[0];
        caption.Text = "Привет, мир";
        TextMarkMetrics.Fit(caption);
        if (caption.Points[0] != anchor || canvas.GetDisplayBounds(caption).Width <= box.Width)
            throw new InvalidOperationException("A longer caption must take a wider box without moving its anchor.");
    }

    internal static void VerifyHoverManipulation(BitmapSource source)
    {
        Point At(double x, double y) => new(source.PixelWidth * x, source.PixelHeight * y);
        var rectangle = new AnnotationItem { Kind = EditorTool.Rectangle, Points = [At(.08, .12), At(.42, .48)] };
        var blur = new AnnotationItem { Kind = EditorTool.Blur, Points = [At(.56, .3), At(.9, .78)] };
        var arrow = new AnnotationItem { Kind = EditorTool.Arrow, Points = [At(.1, .62), At(.44, .92)] };
        var text = new AnnotationItem { Kind = EditorTool.Text, Points = [At(.62, .05), At(.86, .2)] };
        var annotations = new ObservableCollection<AnnotationItem> { rectangle, blur, arrow, text };
        var canvas = new AnnotationCanvas { Image = source, Annotations = annotations, ImagePadding = 0, Width = 480, Height = 300 };
        canvas.Measure(new Size(480, 300));
        canvas.Arrange(new Rect(0, 0, 480, 300));
        var rendered = new RenderTargetBitmap(480, 300, 96, 96, PixelFormats.Pbgra32);
        rendered.Render(canvas);

        // An empty frame keeps its interior free for the next drawing; a blur is opaque, so it is
        // grabbed anywhere within.
        Verify(rectangle, EditorTool.Blur, interiorGrabs: false);
        Verify(blur, EditorTool.Rectangle, interiorGrabs: true);
        // A caption is the letters themselves: grabbed anywhere within, resized by nothing.
        canvas.Tool = EditorTool.Arrow;
        var textBounds = canvas.GetDisplayBounds(text);
        if (!ReferenceEquals(canvas.FindMoveHandle(new Point(textBounds.Left + textBounds.Width / 2, textBounds.Top + textBounds.Height / 2)), text))
            throw new InvalidOperationException("A caption must be movable by the letters themselves.");
        canvas.SelectAnnotation(text.Id);
        foreach (var corner in ResizeGeometry.Corners(textBounds))
            if (canvas.FindResizeHandle(corner).Annotation is not null)
                throw new InvalidOperationException("A caption exposed geometry resize handles.");
        canvas.SelectAnnotation(null);

        // An arrow is grabbed by its line, not by the rectangle its two ends span.
        canvas.Tool = EditorTool.Rectangle;
        var arrowBounds = canvas.GetDisplayBounds(arrow);
        var onTheLine = new Point(arrowBounds.Left + arrowBounds.Width / 2, arrowBounds.Top + arrowBounds.Height / 2);
        var besideTheLine = new Point(onTheLine.X + 40, onTheLine.Y - 40);
        if (!ReferenceEquals(canvas.FindMoveHandle(onTheLine), arrow))
            throw new InvalidOperationException("An arrow is not movable by its own line while another drawing tool is active.");
        if (canvas.FindMoveHandle(besideTheLine) is not null)
            throw new InvalidOperationException("The empty corner of the bounding box of an arrow was mistaken for a move handle.");

        var comment = new AnnotationItem
        {
            Kind = EditorTool.Comment,
            Points = [At(.48, .18), new Point(source.PixelWidth * .48 + 8, source.PixelHeight * .18 + 8)]
        };
        annotations.Add(comment);
        canvas.SelectAnnotation(comment.Id);
        var commentBounds = canvas.GetDisplayBounds(comment);
        foreach (var corner in ResizeGeometry.Corners(commentBounds))
            if (canvas.FindResizeHandle(corner).Annotation is not null)
                throw new InvalidOperationException("A comment pin exposed geometry resize handles.");
        if (HasResizeHandles(comment)) throw new InvalidOperationException("Comment pins must not render a selection box.");
        // The pin travels with any tool armed, and it is grabbed by its badge, not by the whole area.
        var pin = new Point(480 * .48, 300 * .18);
        if (!ReferenceEquals(canvas.FindMoveHandle(pin), comment))
            throw new InvalidOperationException("A comment pin is not movable while another drawing tool is active.");
        if (canvas.FindMoveHandle(new Point(pin.X + 40, pin.Y)) is not null)
            throw new InvalidOperationException("The empty space next to a comment pin was mistaken for a move handle.");

        // One order of the press for every tool: with the comment in the hand the edge of a drawn
        // frame answers as it does to any other, and so do the badge and the anchor of a pin.
        comment.Label = "A1";
        canvas.Tool = EditorTool.Comment;
        var frameBounds = canvas.GetDisplayBounds(rectangle);
        if (!ReferenceEquals(canvas.FindMoveHandle(new Point(frameBounds.Left, frameBounds.Top + frameBounds.Height / 2)), rectangle))
            throw new InvalidOperationException("The edge of a frame must answer to the comment tool as it does to every other.");
        if (!ReferenceEquals(canvas.FindMoveHandle(canvas.GetBadgeCenter(comment)), comment))
            throw new InvalidOperationException("The badge of a pin must be grabbable with the comment tool in the hand.");
        var anchor = canvas.ToDisplay(comment.Points[0]);
        if (!ReferenceEquals(canvas.FindLeaderAnchor(new Point(anchor.X + 5, anchor.Y)), comment))
            throw new InvalidOperationException("The anchor of a pin must answer to the comment tool.");
        // And with a frame in the hand it answers just the same, instead of being drawn over.
        canvas.Tool = EditorTool.Rectangle;
        if (!ReferenceEquals(canvas.FindLeaderAnchor(new Point(anchor.X + 5, anchor.Y)), comment))
            throw new InvalidOperationException("The anchor of a pin must answer whatever tool is in the hand.");
        canvas.SelectAnnotation(null);

        void Verify(AnnotationItem target, EditorTool activeTool, bool interiorGrabs)
        {
            canvas.Tool = activeTool;
            var bounds = canvas.GetDisplayBounds(target);
            var edge = new Point(bounds.Left, bounds.Top + bounds.Height / 2);
            var corner = bounds.TopLeft;
            var inside = new Point(bounds.Left + bounds.Width / 2, bounds.Top + bounds.Height / 2);

            if (!ReferenceEquals(canvas.FindMoveHandle(edge), target))
                throw new InvalidOperationException("The edge of a mark is not movable while another drawing tool is active.");
            // The corners belong to the mark that is selected and to that one alone: they are drawn
            // on it and nowhere else, so nowhere else may they answer.
            canvas.SelectAnnotation(null);
            if (canvas.FindResizeHandle(corner).Annotation is not null)
                throw new InvalidOperationException("The corner of a mark that is not selected must answer with nothing.");
            canvas.SelectAnnotation(target.Id);
            var resizeHit = canvas.FindResizeHandle(corner);
            if (!ReferenceEquals(resizeHit.Annotation, target) || resizeHit.Corner != 0)
                throw new InvalidOperationException("The corner of the selected mark is not resizable while another drawing tool is active.");
            if (interiorGrabs != ReferenceEquals(canvas.FindMoveHandle(inside), target))
                throw new InvalidOperationException("The interior of a mark did not follow the rule for its kind.");
            if (!interiorGrabs && canvas.FindResizeHandle(inside).Annotation is not null)
                throw new InvalidOperationException("The interior of a mark was mistaken for a resize handle.");
            if (canvas.Tool != activeTool)
                throw new InvalidOperationException("Hover manipulation changed the selected drawing tool.");
            canvas.SelectAnnotation(null);
        }
    }
}
