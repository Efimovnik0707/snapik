namespace SnapBrief.Windows.Tests;

public sealed class ClipboardEchoDetectorTests
{
    private const string PromptText = "Снимок A.\r\n  A1: тест1";

    [Fact]
    public void ReceiverEchoWithImagePlaceholder_IsDetected()
    {
        var snapshot = TextOnly("[Image #2]Снимок A.\r\n  A1: тест1");

        Assert.True(ClipboardEchoDetector.IsReceiverEcho(snapshot, PromptText));
    }

    [Fact]
    public void ReceiverEchoWithExtraWhitespaceAndCrlf_IsDetected()
    {
        var snapshot = TextOnly("  Снимок   A.\n\n  A1:   тест1  \r\n");

        Assert.True(ClipboardEchoDetector.IsReceiverEcho(snapshot, PromptText));
    }

    [Fact]
    public void UnrelatedForeignText_IsNotAnEcho()
    {
        var snapshot = TextOnly("Совсем другой текст, скопированный пользователем");

        Assert.False(ClipboardEchoDetector.IsReceiverEcho(snapshot, PromptText));
    }

    [Fact]
    public void ForeignTextWithFiles_IsNotAnEcho()
    {
        var data = new Dictionary<string, object>(StringComparer.Ordinal)
        {
            ["FileDrop"] = new[] { @"C:\shots\0.png" },
            ["UnicodeText"] = "Совсем другой текст"
        };
        var snapshot = new ClipboardSnapshot(99, data, true);

        Assert.False(ClipboardEchoDetector.IsReceiverEcho(snapshot, PromptText));
    }

    [Fact]
    public void ClipboardWithImage_IsNotAnEcho()
    {
        var data = new Dictionary<string, object>(StringComparer.Ordinal)
        {
            ["Bitmap"] = new object(),
            ["UnicodeText"] = PromptText
        };
        var snapshot = new ClipboardSnapshot(99, data, true);

        Assert.False(ClipboardEchoDetector.IsReceiverEcho(snapshot, PromptText));
    }

    private static ClipboardSnapshot TextOnly(string text)
    {
        var data = new Dictionary<string, object>(StringComparer.Ordinal) { ["UnicodeText"] = text };
        return new ClipboardSnapshot(99, data, true);
    }
}
