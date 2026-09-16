namespace Snapik.Core.Models;

/// <summary>Where a capture came from. The value is written into session.json in English
/// ("region", "fullscreen", "import"), so the file never carries an interface word.</summary>
public enum CaptureKind
{
    Region,
    Fullscreen,
    Import
}
