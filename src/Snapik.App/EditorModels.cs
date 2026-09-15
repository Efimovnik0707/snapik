using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Linq;
using System.Runtime.CompilerServices;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Collections.Immutable;
using Snapik.Core.Models;
using CoreAnnotation = Snapik.Core.Models.AnnotationItem;
using CoreCapture = Snapik.Core.Models.CaptureItem;

namespace Snapik.App;

public enum EditorTool
{
    Select,
    Arrow,
    Rectangle,
    Pen,
    Highlight,
    Text,
    Conceal,
    Blur,
    Crop,
    Comment,
    // A mode of the panel and never the kind of a mark: the eraser removes what it is clicked on and
    // nothing carries this value into a session.
    Eraser
}

public sealed class AnnotationItem : INotifyPropertyChanged
{
    private string _note = string.Empty;
    private string _text = string.Empty;
    private bool _isSelected;

    public Guid Id { get; init; } = Guid.NewGuid();
    public EditorTool Kind { get; init; }
    public List<Point> Points { get; init; } = [];
    public List<List<Point>> AdditionalPathSegments { get; init; } = [];
    public Color Color { get; set; } = Color.FromRgb(49, 92, 245);
    public double Thickness { get; set; } = 4;
    public string Label { get; set; } = string.Empty;
    public Guid? ParentAnnotationId { get; set; }
    public string ArrowStyle { get; set; } = "straight";

    // The shift of the numbered badge from its automatic place, in image pixels; null is automatic.
    // A plain property on purpose: the drag of a note pill must not push a history entry per pixel.
    public Point? NoteOffset { get; set; }

    public AnnotationShape Shape { get; set; } = AnnotationShape.Rectangle;
    public AnnotationFill Fill { get; set; } = AnnotationFill.None;

    // The pattern of the stroke: solid, dashed or dotted. A mark without a stroke keeps the default
    // and writes it, so a highlighter or a caption reads back the same whatever was armed.
    public AnnotationLineStyle LineStyle { get; set; } = AnnotationLineStyle.Solid;

    // The colour inside the box; null means "the colour of the outline", which is how every mark
    // drawn before the fill had a colour of its own still reads.
    public Color? FillColor { get; set; }

    // A frame without an outline: a solid fill and no outline is what the conceal tool used to draw.
    public bool HasOutline { get; set; } = true;

    // The size a text mark is typed in, in the pixels of the capture.
    public double FontSize { get; set; } = TextMarkMetrics.DefaultFontSize;

    public string Note
    {
        get => _note;
        set { if (_note == value) return; _note = value; OnPropertyChanged(); }
    }

    public string Text
    {
        get => _text;
        set { if (_text == value) return; _text = value; OnPropertyChanged(); }
    }

    public bool IsSelected
    {
        get => _isSelected;
        set { if (_isSelected == value) return; _isSelected = value; OnPropertyChanged(); }
    }

    public AnnotationItem Clone() => new()
    {
        Id = Id,
        Kind = Kind,
        ParentAnnotationId = ParentAnnotationId, ArrowStyle = ArrowStyle, NoteOffset = NoteOffset,
        Shape = Shape, Fill = Fill, FillColor = FillColor, HasOutline = HasOutline, FontSize = FontSize,
        LineStyle = LineStyle,
        Points = [.. Points],
        AdditionalPathSegments = AdditionalPathSegments.Select(segment => segment.ToList()).ToList(),
        Color = Color,
        Thickness = Thickness,
        Label = Label,
        Note = Note,
        Text = Text,
        IsSelected = IsSelected
    };

    public CoreAnnotation ToCore(int imageWidth, int imageHeight) => new(
        Id,
        Kind switch
        {
            EditorTool.Comment => AnnotationKind.Comment,
            EditorTool.Arrow => AnnotationKind.Arrow,
            EditorTool.Rectangle => AnnotationKind.Rectangle,
            EditorTool.Pen => AnnotationKind.Freehand,
            EditorTool.Highlight => AnnotationKind.Highlight,
            EditorTool.Text => AnnotationKind.Text,
            EditorTool.Blur => AnnotationKind.Blur,
            _ => AnnotationKind.Rectangle
        },
        Points.Select(p => new NormalizedPoint(
            Math.Clamp(p.X / imageWidth, 0, 1),
            Math.Clamp(p.Y / imageHeight, 0, 1))).ToImmutableArray(),
        $"#{Color.A:X2}{Color.R:X2}{Color.G:X2}{Color.B:X2}",
        Thickness,
        Text,
        Note)
    {
        ParentAnnotationId = ParentAnnotationId, ArrowStyle = ArrowStyle,
        NoteOffset = NoteOffset is { } offset ? new NormalizedPoint(offset.X / imageWidth, offset.Y / imageHeight) : null,
        Shape = Shape, Fill = Fill, HasOutline = HasOutline, FontSize = FontSize, LineStyle = LineStyle,
        FillColor = FillColor is { } fillColor ? $"#{fillColor.A:X2}{fillColor.R:X2}{fillColor.G:X2}{fillColor.B:X2}" : null,
        PathSegments = AdditionalPathSegments.Count == 0 ? [] : new[] { Points }.Concat(AdditionalPathSegments)
            .Select(segment => segment.Select(p => new NormalizedPoint(Math.Clamp(p.X / imageWidth, 0, 1), Math.Clamp(p.Y / imageHeight, 0, 1))).ToImmutableArray())
            .ToImmutableArray()
    };

    public static AnnotationItem FromCore(CoreAnnotation item, int imageWidth, int imageHeight)
    {
        var segments = item.GetPathSegments()
            .Select(segment => segment.Select(p => new Point(p.X * imageWidth, p.Y * imageHeight)).ToList()).ToList();
        // A session written by a build that still had the conceal tool carries "redaction" marks.
        // The tool is gone; what it drew is a region with a solid black fill and no outline, and it
        // is written back in that shape the next time the session is saved.
        var redaction = item.Kind == AnnotationKind.Redaction;
        return new()
        {
        Id = item.Id,
        ParentAnnotationId = item.ParentAnnotationId, ArrowStyle = item.ArrowStyle,
        NoteOffset = item.NoteOffset is { } offset ? new Point(offset.X * imageWidth, offset.Y * imageHeight) : null,
        Shape = item.Shape,
        Fill = redaction ? AnnotationFill.Solid : item.Fill,
        FillColor = redaction ? Colors.Black : ParseFillColor(item.FillColor),
        HasOutline = !redaction && item.HasOutline,
        FontSize = item.FontSize,
        LineStyle = item.LineStyle,
        Kind = item.Kind switch
        {
            AnnotationKind.Comment => EditorTool.Comment,
            AnnotationKind.Arrow => EditorTool.Arrow,
            AnnotationKind.Rectangle => EditorTool.Rectangle,
            AnnotationKind.Freehand => EditorTool.Pen,
            AnnotationKind.Highlight => EditorTool.Highlight,
            AnnotationKind.Text => EditorTool.Text,
            AnnotationKind.Blur => EditorTool.Blur,
            _ => EditorTool.Rectangle
        },
        Points = segments.Count > 0 ? segments[0] : item.Points.Select(p => new Point(p.X * imageWidth, p.Y * imageHeight)).ToList(),
        AdditionalPathSegments = segments.Skip(1).ToList(),
        Color = (Color)ColorConverter.ConvertFromString(item.StrokeColor),
        Thickness = item.Thickness,
        Text = item.Text,
        Note = item.Note
        };
    }

    // A colour written by hand, or by a build that knew another format, means "the colour of the
    // outline" rather than a broken mark.
    private static Color? ParseFillColor(string? value)
    {
        if (string.IsNullOrWhiteSpace(value)) return null;
        try { return ColorConverter.ConvertFromString(value) is Color color ? color : null; }
        catch (Exception) { return null; }
    }

    public event PropertyChangedEventHandler? PropertyChanged;
    private void OnPropertyChanged([CallerMemberName] string? name = null) => PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name));
}

public sealed class CaptureItem : INotifyPropertyChanged
{
    private string _note = string.Empty;
    private bool _isSelected;
    private bool _isSent;
    private string _title = string.Empty;
    private CaptureKind _kind = CaptureKind.Region;
    private int _monitorCount;

    public Guid Id { get; init; } = Guid.NewGuid();
    public required BitmapSource Image { get; set; }
    public required string SourcePath { get; set; }
    public ObservableCollection<AnnotationItem> Annotations { get; } = [];
    public string DisplayLabel { get; set; } = "A";

    public string Note
    {
        get => _note;
        set { if (_note == value) return; _note = value; OnPropertyChanged(); }
    }

    public bool IsSelected
    {
        get => _isSelected;
        set { if (_isSelected == value) return; _isSelected = value; OnPropertyChanged(); }
    }

    // The capture was pasted with a package: it stays in the strip, dimmed and out of the next package.
    public bool IsSent
    {
        get => _isSent;
        set { if (_isSent == value) return; _isSent = value; OnPropertyChanged(); }
    }

    // Where the capture came from, how many monitors it covered and the name of the file it was
    // imported from: the chip of the card and the caption of the editor are bound to all three.
    public CaptureKind Kind
    {
        get => _kind;
        set { if (_kind == value) return; _kind = value; OnPropertyChanged(); }
    }

    public int MonitorCount
    {
        get => _monitorCount;
        set { var clamped = Math.Max(0, value); if (_monitorCount == clamped) return; _monitorCount = clamped; OnPropertyChanged(); }
    }

    public string Title
    {
        get => _title;
        set { if (_title == value) return; _title = value; OnPropertyChanged(); }
    }

    public int NoteCount => Annotations.Count(a => !string.IsNullOrWhiteSpace(a.Note)) + (string.IsNullOrWhiteSpace(Note) ? 0 : 1);

    public CaptureSnapshot Snapshot() => new(Id, Image, SourcePath, DisplayLabel, Note, Kind, MonitorCount, Title, Annotations.Select(a => a.Clone()).ToList());

    public CaptureItem DeepClone()
    {
        // The sent flag travels with the copy: a capture restored through "Undo" must not come back
        // as unsent and land in the next package a second time.
        var clone = new CaptureItem { Id = Id, Image = Image, SourcePath = SourcePath, DisplayLabel = DisplayLabel, Note = Note, IsSelected = IsSelected, IsSent = IsSent, Kind = Kind, MonitorCount = MonitorCount, Title = Title };
        foreach (var annotation in Annotations.Select(a => a.Clone())) clone.Annotations.Add(annotation);
        return clone;
    }

    public CoreCapture ToCore() => new(
        Id,
        SourcePath,
        Image.PixelWidth,
        Image.PixelHeight,
        Image.DpiX > 0 ? Image.DpiX : 96,
        Image.DpiY > 0 ? Image.DpiY : 96,
        Title,
        Note,
        Annotations.Select(a => a.ToCore(Image.PixelWidth, Image.PixelHeight)).ToImmutableArray())
    {
        Sent = IsSent,
        Kind = Kind,
        MonitorCount = MonitorCount
    };

    public static CaptureItem FromCore(CoreCapture item, BitmapSource image)
    {
        var capture = new CaptureItem
        {
            Id = item.Id, SourcePath = item.SourceImagePath, Image = image, Note = item.Note, IsSent = item.Sent,
            Kind = item.Kind, MonitorCount = item.MonitorCount, Title = item.Title
        };
        foreach (var annotation in item.Annotations)
            capture.Annotations.Add(AnnotationItem.FromCore(annotation, image.PixelWidth, image.PixelHeight));
        return capture;
    }

    public void Restore(CaptureSnapshot snapshot)
    {
        Image = snapshot.Image;
        SourcePath = snapshot.SourcePath;
        DisplayLabel = snapshot.DisplayLabel;
        Note = snapshot.Note;
        Kind = snapshot.Kind;
        MonitorCount = snapshot.MonitorCount;
        Title = snapshot.Title;
        Annotations.Clear();
        foreach (var annotation in snapshot.Annotations.Select(a => a.Clone())) Annotations.Add(annotation);
    }

    public event PropertyChangedEventHandler? PropertyChanged;
    private void OnPropertyChanged([CallerMemberName] string? name = null) => PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name));
}

public sealed record CaptureSnapshot(Guid CaptureId, BitmapSource Image, string SourcePath, string DisplayLabel, string Note, CaptureKind Kind, int MonitorCount, string Title, IReadOnlyList<AnnotationItem> Annotations);

public sealed record PreparedPackage(Guid ExportId, IReadOnlyList<string> ImagePaths, string PromptText, string DirectoryPath);
