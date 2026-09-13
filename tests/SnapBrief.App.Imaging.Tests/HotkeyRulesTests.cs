namespace SnapBrief.App.Imaging.Tests;

public sealed class HotkeyRulesTests
{
    [Theory]
    // A bare left arrow: what an older build recorded when a stray Tab put the focus on the field.
    // Registered globally, it never reached the window it was pressed in again.
    [InlineData("custom:0:37")]
    // A bare letter and a bare Escape: the same rule, whatever the key is.
    [InlineData("custom:0:83")]
    [InlineData("custom:0:27")]
    public void A_stored_shortcut_without_a_modifier_is_refused(string stored) =>
        Assert.False(HotkeyRules.TryParseCustom(stored, out _, out _));

    [Theory]
    // A modifier where the key of the shortcut belongs: "Ctrl + LeftShift" is what an older build
    // wrote when Shift was let go of with Ctrl still down, and it answered every Ctrl+Shift there is.
    [InlineData("custom:2:161")]
    [InlineData("custom:6:17")]
    [InlineData("custom:1:18")]
    [InlineData("custom:2:91")]
    public void A_stored_shortcut_that_ends_with_a_modifier_is_refused(string stored) =>
        Assert.False(HotkeyRules.TryParseCustom(stored, out _, out _));

    [Theory]
    // Print Screen and Pause are shortcuts on their own, and Print Screen is offered as a preset.
    [InlineData("custom:0:44", 0x2C)]
    [InlineData("custom:0:19", 0x13)]
    public void Print_screen_and_pause_stand_on_their_own(string stored, int virtualKey)
    {
        Assert.True(HotkeyRules.TryParseCustom(stored, out var modifiers, out var key));
        Assert.Equal(0u, modifiers);
        Assert.Equal(virtualKey, key);
    }

    [Theory]
    // Ctrl + Left, the arrow the user meant, and Ctrl + Shift + S, which has always been read.
    [InlineData("custom:2:37", 2, 37)]
    [InlineData("custom:6:83", 6, 83)]
    public void A_shortcut_with_a_modifier_is_read_as_it_was_stored(string stored, int expectedModifiers, int expectedKey)
    {
        Assert.True(HotkeyRules.TryParseCustom(stored, out var modifiers, out var key));
        Assert.Equal((uint)expectedModifiers, modifiers);
        Assert.Equal(expectedKey, key);
    }

    [Theory]
    // The name of a preset is not a custom id, a modifier bit nothing maps to is not one either,
    // and a key outside the range never was.
    [InlineData("ctrl-alt-s")]
    [InlineData("custom:16:83")]
    [InlineData("custom:2:255")]
    [InlineData("custom:2:0")]
    [InlineData("custom:2")]
    [InlineData("custom:two:83")]
    public void Anything_else_is_not_a_custom_shortcut(string stored) =>
        Assert.False(HotkeyRules.TryParseCustom(stored, out _, out _));
}
