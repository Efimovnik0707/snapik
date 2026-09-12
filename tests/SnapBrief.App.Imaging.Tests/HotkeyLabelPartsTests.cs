using SnapBrief.App.Controls;

namespace SnapBrief.App.Imaging.Tests;

public sealed class HotkeyLabelPartsTests
{
    [Theory]
    [InlineData("Ctrl + Alt + S", new[] { "Ctrl", "Alt", "S" })]
    [InlineData("Alt + S", new[] { "Alt", "S" })]
    [InlineData("Pause / Break", new[] { "Pause / Break" })]
    [InlineData("Print Screen", new[] { "Print Screen" })]
    public void EveryPlusSignStartsAnotherCapsule(string label, string[] expected) =>
        Assert.Equal(expected, HotkeyLabelParts.Split(label));

    [Fact]
    public void AnEmptyLabelHasNoCapsules() => Assert.Empty(HotkeyLabelParts.Split("   "));
}
