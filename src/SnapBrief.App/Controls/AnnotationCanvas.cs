using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Linq;
using System.Windows;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using SnapBrief.App.Imaging;
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
    public double ImagePadding { get; set; } = 28;

    public event EventHandler<AnnotationItem>? AnnotationCreated;
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
        Cursor = Cursors.Cross;
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
            foreach (var annotation in Annotations.Where(a => a.Kind is not (EditorTool.Blur or EditorTool.Conceal))) DrawAnnotation(dc, annotation, _imageRect, includeSelection: false, drawLabel: false);
            foreach (var annotation in Annotations.Where(a => a.Kind == EditorTool.Conceal)) DrawAnnotation(dc, annotation, _imageRect, includeSelection: false, drawLabel: false);
            foreach (var annotation in Annotations) DrawAnnotation(dc, annotation, _imageRect, includeSelection: true, drawShape: false);
        }
        if (_manipulating && SelectedAnnotation is { Kind: EditorTool.Blur } movingBlur)
            dc.DrawRectangle(Brushes.Black, new Pen(Brushes.DodgerBlue, 1.5), GetDisplayBounds(movingBlur));
        if (_draft is not null) DrawAnnotation(dc, _draft, _imageRect);
    }

    protected override void OnMouseLeftButtonDown(MouseButtonEventArgs e)
    {
        base.OnMouseLeftButtonDown(e);
        Focus();
        if (Image is null) return;
        var point = e.GetPosition(this);
        if (!_imageRect.Contains(point)) return;

        var handleHit = FindResizeHandle(point);
        if (Tool == EditorTool.Select || handleHit.Annotation is not null)
        {
            var imagePoint = ToImage(point);
            var hit = handleHit.Annotation ?? HitTestAnnotation(imagePoint);
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

        _gestureStart = ToImage(point);
        _draft = new AnnotationItem
        {
            Kind = Tool,
            Color = Tool == EditorTool.Conceal ? Colors.Black : ActiveColor,
            Thickness = ActiveThickness,
            Points = [_gestureStart.Value, _gestureStart.Value]
        };
        CaptureMouse();
        InvalidateVisual();
    }

    protected override void OnMouseMove(MouseEventArgs e)
    {
        base.OnMouseMove(e);
        if (_manipulating && SelectedAnnotation is not null && _gestureStart is not null && _originalPoints is not null && e.LeftButton == MouseButtonState.Pressed)
        {
            var current = ClampToImage(ToImage(e.GetPosition(this)));
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
        if (_draft is null || _gestureStart is null || e.LeftButton != MouseButtonState.Pressed)
        {
            var handle = FindResizeHandle(e.GetPosition(this));
            Cursor = handle.Corner < 0 ? (Tool == EditorTool.Select ? Cursors.Arrow : Cursors.Cross)
                : handle.Corner is 0 or 2 ? Cursors.SizeNWSE : Cursors.SizeNESW;
            return;
        }
        var point = ClampToImage(ToImage(e.GetPosition(this)));
        if (_draft.Kind is EditorTool.Pen or EditorTool.Highlight)
            _draft.Points.Add(point);
        else if (_draft.Points.Count > 1)
            _draft.Points[1] = point;
        InvalidateVisual();
    }

    protected override void OnMouseLeftButtonUp(MouseButtonEventArgs e)
    {
        base.OnMouseLeftButtonUp(e);
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
                Select(_draft);
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
        else if (e.Key == Key.Escape && _draft is not null)
        {
            _draft = null;
            _gestureStart = null;
            ReleaseMouseCapture();
            InvalidateVisual();
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
                foreach (var annotation in Annotations.Where(a => a.Kind is not (EditorTool.Blur or EditorTool.Conceal))) DrawAnnotation(dc, annotation, pixelRect, includeSelection: false, drawLabel: false);
                foreach (var annotation in Annotations.Where(a => a.Kind == EditorTool.Conceal)) DrawAnnotation(dc, annotation, pixelRect, includeSelection: false, drawLabel: false);
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
        if (SelectedAnnotation is { } selected)
        {
            var corner = ResizeGeometry.HitCorner(GetDisplayBounds(selected), displayPoint, 10);
            if (corner >= 0) return (selected, corner);
        }
        for (var i = Annotations.Count - 1; i >= 0; i--)
        {
            var corner = ResizeGeometry.HitCorner(GetDisplayBounds(Annotations[i]), displayPoint, 10);
            if (corner >= 0) return (Annotations[i], corner);
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
                    dc.DrawRectangle(null, pen, rect);
                    break;
                case EditorTool.Conceal:
                    dc.DrawRectangle(Brushes.Black, null, rect);
                    break;
                case EditorTool.Blur:
                    dc.DrawRectangle(new SolidColorBrush(Color.FromArgb(54, 255, 255, 255)), new Pen(new SolidColorBrush(Color.FromRgb(47, 140, 255)), 1.5), rect);
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
                    dc.DrawLine(pen, start, end);
                    var vector = start - end;
                    if (vector.Length > 0)
                    {
                        vector.Normalize();
                        var side = new Vector(-vector.Y, vector.X);
                        var size = Math.Max(10, thickness * 3.2);
                        var geometry = new StreamGeometry();
                        using (var ctx = geometry.Open())
                        {
                            ctx.BeginFigure(end, true, true);
                            ctx.LineTo(end + vector * size + side * size * .45, true, false);
                            ctx.LineTo(end + vector * size - side * size * .45, true, false);
                        }
                        geometry.Freeze();
                        dc.DrawGeometry(brush, null, geometry);
                    }
                    break;
            }
        }

        if (drawLabel && !string.IsNullOrEmpty(item.Label))
        {
            var anchor = Map(item.Points[0]);
            var diameter = Math.Max(26, item.Label.Length * 7 + 12);
            var center = new Point(anchor.X, anchor.Y - diameter / 2 - 3);
            dc.DrawEllipse(new SolidColorBrush(Color.FromRgb(47, 140, 255)), null, center, diameter / 2, diameter / 2);
            var label = new FormattedText(item.Label, System.Globalization.CultureInfo.InvariantCulture, FlowDirection.LeftToRight,
                new Typeface(new FontFamily("Segoe UI Variable Text"), FontStyles.Normal, FontWeights.SemiBold, FontStretches.Normal), 11, Brushes.White, VisualTreeHelper.GetDpi(this).PixelsPerDip);
            dc.DrawText(label, new Point(center.X - label.Width / 2, center.Y - label.Height / 2));
        }

        if (includeSelection && item.IsSelected)
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

    private bool GestureHasSize(AnnotationItem item)
    {
        if (item.Points.Count < 2) return false;
        if (item.Kind is EditorTool.Pen or EditorTool.Highlight) return item.Points.Count > 2;
        return (item.Points[1] - item.Points[0]).Length >= 3;
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
            foreach (var annotation in Annotations.Where(a => a.Kind == EditorTool.Blur))
            {
                hash.Add(annotation.Id); hash.Add(annotation.Thickness);
                foreach (var point in annotation.Points) { hash.Add(point.X); hash.Add(point.Y); }
            }
        var key = hash.ToHashCode();
        if (_blurCache is not null && key == _blurCacheKey) return _blurCache;
        BitmapSource result = source;
        if (Annotations is not null)
            foreach (var annotation in Annotations.Where(a => a.Kind == EditorTool.Blur && a.Points.Count > 1))
                result = RegionBlur.Apply(result, ToPixelRect(BoundsOf(annotation), source.PixelWidth, source.PixelHeight), BlurRadius(annotation));
        _blurCacheKey = key;
        _blurCache = result;
        return _blurCache;
    }

    private static int BlurRadius(AnnotationItem annotation) => Math.Clamp((int)Math.Round(annotation.Thickness * 3), 4, 36);

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
}
