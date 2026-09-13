using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Linq;
using System.Windows;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using SnapBrief.App.Imaging;
using SnapBrief.Core.Models;
using System.Runtime.CompilerServices;

namespace SnapBrief.App.Controls;

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
    private int _blurCacheKey;
    private BitmapSource? _blurCache;

    public static readonly DependencyProperty ImageProperty = DependencyProperty.Register(
        nameof(Image), typeof(BitmapSource), typeof(AnnotationCanvas), new FrameworkPropertyMetadata(null, FrameworkPropertyMetadataOptions.AffectsRender));

    public static readonly DependencyProperty ToolProperty = DependencyProperty.Register(
        nameof(Tool), typeof(EditorTool), typeof(AnnotationCanvas), new FrameworkPropertyMetadata(EditorTool.Select));

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
    public bool ActiveHasOutline { get; set; } = true;
    public double ImagePadding { get; set; } = 28;

    public event EventHandler<AnnotationItem>? AnnotationCreated;
    public event EventHandler<AnnotationItem>? AnnotationActivated;
    public event EventHandler<AnnotationItem?>? SelectionChanged;
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
    public AnnotationCanvas()
    {
        Focusable = true;
        // The crosshair is not the cursor of the whole surface any more: it appears over the capture
        // while a drawing tool is armed, and nowhere else.
        Cursor = Cursors.Arrow;
        ClipToBounds = true;
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

        _imageRect = FitRect(Image.PixelWidth, Image.PixelHeight, ActualWidth, ActualHeight, ImagePadding);
        dc.DrawRectangle(Brushes.White, null, _imageRect);
        dc.DrawImage(ApplyBlurAnnotations(Image), _imageRect);

        if (Annotations is not null)
        {
            foreach (var annotation in Annotations.Where(a => a.Kind != EditorTool.Blur && !HasOpaqueFill(a))) DrawAnnotation(dc, annotation, _imageRect, includeSelection: false, drawLabel: false);
            foreach (var annotation in Annotations.Where(HasOpaqueFill)) DrawAnnotation(dc, annotation, _imageRect, includeSelection: false, drawLabel: false);
            foreach (var annotation in Annotations) DrawAnnotation(dc, annotation, _imageRect, includeSelection: true, drawShape: false);
        }
        if (_manipulating && SelectedAnnotation is { Kind: EditorTool.Blur } movingBlur)
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
        if (!_imageRect.Contains(point)) return;

        // A double click opens the note of whatever it lands on: the text editor for a text mark,
        // the note pill for everything else. The editor window listens for it.
        if (clickCount == 2 && HitTestAnnotation(ToImage(point)) is { } activated)
        {
            Select(activated);
            AnnotationActivated?.Invoke(this, activated);
            return;
        }
        var handleHit = FindResizeHandle(point);
        if (Tool != EditorTool.Comment && (Tool == EditorTool.Select || handleHit.Annotation is not null || FindMoveHandle(point) is not null))
        {
            var imagePoint = ToImage(point);
            var hit = handleHit.Annotation ?? FindMoveHandle(point) ?? HitTestAnnotation(imagePoint);
            Select(hit);
            if (hit is not null)
            {
                _gestureStart = imagePoint;
                _originalPoints = [.. hit.Points];
                _originalAdditionalSegments = hit.AdditionalPathSegments.Select(segment => segment.ToList()).ToList();
                var bounds = BoundsOf(hit);
                _originalBounds = bounds;
                _resizeCorner = handleHit.Corner;
                _resizing = _resizeCorner >= 0;
                _manipulating = true;
                _manipulationChanged = false;
                CaptureMouse();
            }
            return;
        }

        // A press with a drawing tool armed drops the selection at once: whatever the hand does
        // next, the colour and the thickness on the panel belong to the next mark from now on.
        Select(null);
        _gestureStart = ToImage(point);
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
            HasOutline = Tool != EditorTool.Rectangle || ActiveHasOutline,
            Color = ActiveColor,
            Thickness = ActiveThickness,
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
        if (_manipulating && SelectedAnnotation is not null && _gestureStart is not null && _originalPoints is not null && pressed)
        {
            var current = ClampToImage(ToImage(displayPoint));
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
        var handle = FindResizeHandle(displayPoint);
        if (handle.Corner >= 0) { Cursor = handle.Corner is 0 or 2 ? Cursors.SizeNWSE : Cursors.SizeNESW; return; }
        var movablePin = Tool == EditorTool.Select && HitTestAnnotation(ToImage(displayPoint)) is { Kind: EditorTool.Comment };
        Cursor = FindMoveHandle(displayPoint) is not null || movablePin ? Cursors.Hand
            : IsDrawingTool(Tool) && _imageRect.Contains(displayPoint) ? Cursors.Cross
            : Cursors.Arrow;
    }

    private static bool IsDrawingTool(EditorTool tool) => tool != EditorTool.Select;

    protected override void OnMouseLeftButtonUp(MouseButtonEventArgs e)
    {
        base.OnMouseLeftButtonUp(e);
        EndGesture();
    }

    internal void EndGesture()
    {
        if (_manipulating)
        {
            ReleaseMouseCapture();
            _manipulating = false;
            _resizing = false;
            _gestureStart = null;
            _originalPoints = null;
            _originalAdditionalSegments = null;
            if (_manipulationChanged) AnnotationChanged?.Invoke(this, EventArgs.Empty);
            InvalidateVisual();
            return;
        }
        if (_draft is null) return;
        ReleaseMouseCapture();
        if (GestureHasSize(_draft))
        {
            if (_draft.Kind == EditorTool.Crop)
                CropRequested?.Invoke(BoundsOf(_draft));
            else
            {
                _draft.Label = string.Empty;
                Annotations?.Add(_draft);
                // A stroke of the pen or the highlighter is not selected after the hand lets go: it
                // is drawing, not an object to adjust. Everything else is selected, as before.
                if (_draft.Kind is not (EditorTool.Pen or EditorTool.Highlight)) Select(_draft);
                AnnotationCreated?.Invoke(this, _draft);
            }
        }
        _draft = null;
        _gestureStart = null;
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

    private (AnnotationItem? Annotation, int Corner) FindResizeHandle(Point displayPoint)
    {
        if (Image is null || Annotations is null) return (null, -1);
        // The selected mark owns overlapping handles; corners remain draggable with any tool active.
        if (SelectedAnnotation is { } selected && HasResizeHandles(selected))
        {
            var corner = ResizeGeometry.HitCorner(GetDisplayBounds(selected), displayPoint, 10);
            if (corner >= 0) return (selected, corner);
        }
        for (var i = Annotations.Count - 1; i >= 0; i--)
        {
            var annotation = Annotations[i];
            if (!HasResizeHandles(annotation)) continue;
            var corner = ResizeGeometry.HitCorner(GetDisplayBounds(annotation), displayPoint, 10);
            if (corner >= 0) return (annotation, corner);
        }
        return (null, -1);
    }
    private AnnotationItem? HitTestAnnotation(Point imagePoint)
    {
        if (Annotations is null) return null;
        for (var i = Annotations.Count - 1; i >= 0; i--)
        {
            var bounds = BoundsOf(Annotations[i]);
            bounds.Inflate(Math.Max(8, Annotations[i].Thickness * 2), Math.Max(8, Annotations[i].Thickness * 2));
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
        var pen = new Pen(brush, thickness) { StartLineCap = PenLineCap.Round, EndLineCap = PenLineCap.Round, LineJoin = PenLineJoin.Round };
        pen.Freeze();

        if (drawShape && item.Kind is (EditorTool.Pen or EditorTool.Highlight))
        {
            var opacity = item.Kind == EditorTool.Highlight ? 0.35 : 1;
            var pathPen = new Pen(new SolidColorBrush(Color.FromArgb((byte)(opacity * 255), item.Color.R, item.Color.G, item.Color.B)), item.Kind == EditorTool.Highlight ? thickness * 4 : thickness)
            { StartLineCap = PenLineCap.Round, EndLineCap = PenLineCap.Round, LineJoin = PenLineJoin.Round };
            foreach (var segment in new[] { item.Points }.Concat(item.AdditionalPathSegments))
                for (var i = 1; i < segment.Count; i++) dc.DrawLine(pathPen, Map(segment[i - 1]), Map(segment[i]));
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
                        new Pen(new SolidColorBrush(Color.FromRgb(47, 140, 255)), 1.5), item.Shape, rect, scale);
                    break;
                case EditorTool.Crop:
                    dc.DrawRectangle(new SolidColorBrush(Color.FromArgb(24, 47, 140, 255)), new Pen(new SolidColorBrush(Color.FromRgb(47, 140, 255)), 1.5) { DashStyle = DashStyles.Dash }, rect);
                    break;
                case EditorTool.Text:
                    var formatted = new FormattedText(item.Text, System.Globalization.CultureInfo.CurrentUICulture,
                        FlowDirection.LeftToRight, new Typeface("Segoe UI Variable Text"), Math.Max(14, 18 * scale), brush, VisualTreeHelper.GetDpi(this).PixelsPerDip);
                    dc.DrawText(formatted, start);
                    break;
                case EditorTool.Arrow:
                    SnapBrief.App.Imaging.ArrowDrawing.Draw(dc, start, end, brush, thickness, item.ArrowStyle);
                    break;
            }
        }

        if (drawLabel && !string.IsNullOrEmpty(item.Label))
        {
            var badgeBrush = new SolidColorBrush(Color.FromRgb(47, 140, 255));
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

            dc.DrawRectangle(null, new Pen(new SolidColorBrush(Color.FromRgb(49, 92, 245)), 1) { DashStyle = DashStyles.Dash }, selectedRect);
            foreach (var corner in ResizeGeometry.Corners(selectedRect))
                dc.DrawRectangle(Brushes.White, new Pen(new SolidColorBrush(Color.FromRgb(47, 140, 255)), 1.5), new Rect(corner.X - 4, corner.Y - 4, 8, 8));
        }
    }

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

    private static void DrawBoxShape(DrawingContext dc, AnnotationItem item, Rect rect, Pen pen, double scale) =>
        DrawBoxShape(dc, ShapeFillBrush(item.FillColor ?? item.Color, item.Fill), item.HasOutline ? pen : null, item.Shape, rect, scale);

    private static bool HasResizeHandles(AnnotationItem item) => item.Kind != EditorTool.Comment;

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
    private AnnotationItem? FindMoveHandle(Point point)
    {
        if (Annotations is null || Image is null || Tool == EditorTool.Comment) return null;
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
                var width = item.Kind == EditorTool.Highlight ? band * 2 : band;
                foreach (var segment in new[] { item.Points }.Concat(item.AdditionalPathSegments))
                    if (DistanceToPolyline(segment.Select(ToDisplay).ToArray(), point) <= width) return true;
                return false;
            }
            default:
            {
                var bounds = GetDisplayBounds(item);
                var outer = bounds; outer.Inflate(6, 6);
                if (!outer.Contains(point)) return false;
                // An opaque mark has no free interior, and a small one has no room for a band.
                if (HasInteriorGrab(item) || bounds.Width < 24 || bounds.Height < 24) return true;
                var inner = bounds;
                inner.Inflate(-Math.Min(6, inner.Width / 2), -Math.Min(6, inner.Height / 2));
                return !inner.Contains(point);
            }
        }
    }

    // Opaque marks are grabbed anywhere inside, and so is a filled frame; the fill of any other
    // kind means nothing on screen, so its interior stays free for a new mark.
    private static bool HasInteriorGrab(AnnotationItem item) =>
        item.Kind is EditorTool.Blur || (item.Kind == EditorTool.Rectangle && item.Fill != AnnotationFill.None);

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

    // Where the pill of a note has to sit for its own badge to cover the badge on the picture.
    public Point GetBadgeCenter(AnnotationItem annotation) =>
        Image is null || annotation.Points.Count == 0 ? default : BadgeOf(annotation, _imageRect).Center;

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
        if (_manipulating && SelectedAnnotation?.Kind == EditorTool.Blur && _blurCache is not null) return _blurCache;
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

        var bounds = canvas.GetDisplayBounds(annotations[0]);
        canvas.UpdateGesture(new Point(bounds.Left, bounds.Top + bounds.Height / 2), pressed: false);
        if (canvas.Cursor != Cursors.Hand) throw new InvalidOperationException("The edge of a mark must show the hand cursor.");
        canvas.UpdateGesture(new Point(430, 60), pressed: false);
        if (canvas.Cursor != Cursors.Cross) throw new InvalidOperationException("The capture with a drawing tool armed must show the crosshair.");
        canvas.Tool = EditorTool.Select;
        canvas.UpdateGesture(new Point(430, 60), pressed: false);
        if (canvas.Cursor != Cursors.Arrow) throw new InvalidOperationException("The select tool must show the ordinary arrow over the capture.");
        canvas.Tool = EditorTool.Rectangle;
        canvas.UpdateGesture(new Point(240, 5), pressed: false);
        if (canvas.Cursor != Cursors.Arrow) throw new InvalidOperationException("Outside the capture the pointer must be the ordinary arrow.");
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

        // A frame and a text mark keep their interior free for the next drawing; a blur is opaque,
        // there is nothing to draw inside it, so it is grabbed anywhere within.
        Verify(rectangle, EditorTool.Blur, interiorGrabs: false);
        Verify(blur, EditorTool.Rectangle, interiorGrabs: true);
        Verify(text, EditorTool.Arrow, interiorGrabs: false);

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

        void Verify(AnnotationItem target, EditorTool activeTool, bool interiorGrabs)
        {
            canvas.Tool = activeTool;
            var bounds = canvas.GetDisplayBounds(target);
            var edge = new Point(bounds.Left, bounds.Top + bounds.Height / 2);
            var corner = bounds.TopLeft;
            var inside = new Point(bounds.Left + bounds.Width / 2, bounds.Top + bounds.Height / 2);

            if (!ReferenceEquals(canvas.FindMoveHandle(edge), target))
                throw new InvalidOperationException("The edge of a mark is not movable while another drawing tool is active.");
            var resizeHit = canvas.FindResizeHandle(corner);
            if (!ReferenceEquals(resizeHit.Annotation, target) || resizeHit.Corner != 0)
                throw new InvalidOperationException("The corner of a mark is not resizable while another drawing tool is active.");
            if (interiorGrabs != ReferenceEquals(canvas.FindMoveHandle(inside), target))
                throw new InvalidOperationException("The interior of a mark did not follow the rule for its kind.");
            if (!interiorGrabs && canvas.FindResizeHandle(inside).Annotation is not null)
                throw new InvalidOperationException("The interior of a mark was mistaken for a resize handle.");
            if (canvas.Tool != activeTool)
                throw new InvalidOperationException("Hover manipulation changed the selected drawing tool.");
        }
    }
}
