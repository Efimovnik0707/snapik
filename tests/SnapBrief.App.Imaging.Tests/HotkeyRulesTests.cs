using System.Windows.Input;

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

    [Theory]
    // What Windows answers before any application does. Win+S is the search, and every other Win
    // combination goes the same way, Win+Shift+S included.
    [InlineData(ModifierKeys.Windows, 0x53)]
    [InlineData(ModifierKeys.Windows | ModifierKeys.Shift, 0x53)]
    [InlineData(ModifierKeys.Alt, 0x09)]
    [InlineData(ModifierKeys.Alt, 0x73)]
    [InlineData(ModifierKeys.Control, 0x1B)]
    [InlineData(ModifierKeys.Control | ModifierKeys.Alt, 0x2E)]
    public void A_combination_windows_answers_first_is_reserved(ModifierKeys modifiers, int virtualKey) =>
        Assert.True(HotkeyRules.IsSystemReserved(modifiers, virtualKey));

    [Theory]
    // Print Screen on its own is what the wizard offers for "save the whole screen": refusing it
    // here would make the suggestion one the user cannot accept. Pause stands alone too, and the
    // combinations the application itself ships with are nobody else's.
    [InlineData(ModifierKeys.None, 0x2C)]
    [InlineData(ModifierKeys.None, 0x13)]
    [InlineData(ModifierKeys.Control | ModifierKeys.Alt, 0x53)]
    [InlineData(ModifierKeys.Control | ModifierKeys.Alt | ModifierKeys.Shift, 0x53)]
    [InlineData(ModifierKeys.Alt, 0x53)]
    [InlineData(ModifierKeys.Control, 0x2E)]
    public void A_combination_nothing_holds_is_free(ModifierKeys modifiers, int virtualKey) =>
        Assert.False(HotkeyRules.IsSystemReserved(modifiers, virtualKey));

    [Theory]
    // The preset and the custom id are one shortcut written two ways; comparing the strings would
    // let the same combination be assigned to two actions at once.
    [InlineData("print-screen", "custom:0:44")]
    [InlineData("ctrl-alt-s", "custom:3:83")]
    [InlineData("alt-v", "custom:1:86")]
    public void Two_ids_for_one_combination_are_the_same_gesture(string a, string b)
    {
        Assert.True(HotkeyRules.SameGesture(a, b));
        Assert.True(HotkeyRules.SameGesture(b, a));
    }

    [Theory]
    // Different keys, different modifiers, and an id that parses to nothing at all.
    [InlineData("print-screen", "custom:0:19")]
    [InlineData("ctrl-alt-s", "ctrl-shift-s")]
    [InlineData("ctrl-alt-s", "custom:0:37")]
    [InlineData("nothing-like-a-shortcut", "ctrl-alt-s")]
    public void Anything_else_is_a_different_gesture(string a, string b) =>
        Assert.False(HotkeyRules.SameGesture(a, b));

    [Fact]
    public void The_suggestion_is_the_first_combination_nothing_holds()
    {
        Assert.Equal("print-screen", HotkeyRules.SuggestFree([]));
        // Held under its other name: the queue still has to skip it.
        Assert.Equal("custom:7:83", HotkeyRules.SuggestFree(["custom:0:44"]));
        Assert.Equal("ctrl-shift-s", HotkeyRules.SuggestFree(["print-screen", "custom:7:83"]));
        Assert.Equal("alt-s", HotkeyRules.SuggestFree(["print-screen", "custom:7:83", "ctrl-shift-s"]));
    }

    [Fact]
    // Nothing left to offer means no chip beside the field, not a chip offering something taken.
    public void With_every_candidate_held_there_is_nothing_to_suggest() =>
        Assert.Null(HotkeyRules.SuggestFree(["print-screen", "custom:7:83", "ctrl-shift-s", "alt-s"]));
}
