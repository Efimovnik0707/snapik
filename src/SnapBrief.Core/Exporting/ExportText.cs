namespace SnapBrief.Core.Exporting;

public static class ExportText
{
    public static bool HasContent(string? value) => !string.IsNullOrWhiteSpace(value);
}

