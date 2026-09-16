using Snapik.App;

namespace Snapik.App.Imaging.Tests;

// The pinned icon left by SnapBrief 1.4.0: which one is carried over, and which pinned shortcut
// counts as ours once one has been. Both are pure rules; the COM beside them is not tested here.
public sealed class TaskbarPinLegacyTests
{
    private const string Folder = @"C:\Users\kate\AppData\Roaming\Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar\";
    private const string Legacy = Folder + "SnapBrief.lnk";
    private const string Current = Folder + "Snapik.lnk";

    private static string? Chosen(params string[] pinned) =>
        TaskbarPinLegacy.ChooseLegacyPin(pinned, "Snapik.lnk", "SnapBrief.lnk");

    [Fact]
    public void A_taskbar_without_pins_has_nothing_to_carry_over() => Assert.Null(Chosen());

    [Fact]
    public void The_old_pin_alone_is_the_one_carried_over() =>
        Assert.Equal(Legacy, Chosen(Folder + "Explorer.lnk", Legacy));

    [Fact]
    public void Our_own_pin_alone_needs_no_carrying_over() => Assert.Null(Chosen(Current));

    [Fact]
    public void Two_pins_side_by_side_are_left_alone_for_the_user_to_unpin() =>
        Assert.Null(Chosen(Legacy, Current));

    [Fact]
    public void A_pin_under_a_name_of_its_own_is_not_taken_for_the_old_one() =>
        Assert.Null(Chosen(Folder + "SnapBrief (2).lnk"));

    [Fact]
    public void A_pin_named_after_this_application_is_ours() =>
        Assert.True(TaskbarPinLegacy.IsOurs("Snapik.lnk", null, null, @"C:\Programs\Snapik\Snapik.exe"));

    [Fact]
    public void A_pin_under_the_old_name_that_opens_this_application_is_ours() =>
        Assert.True(TaskbarPinLegacy.IsOurs("SnapBrief.lnk", @"C:\Programs\Snapik\Snapik.exe", null, @"C:\Programs\Snapik\Snapik.exe"));

    [Fact]
    public void A_pin_under_the_old_name_that_carries_our_identity_is_ours() =>
        Assert.True(TaskbarPinLegacy.IsOurs("SnapBrief.lnk", null, "YesWorkflow.Snapik", @"C:\Programs\Snapik\Snapik.exe"));

    [Fact]
    public void A_pin_of_another_application_stays_another_application() =>
        Assert.False(TaskbarPinLegacy.IsOurs("Explorer.lnk", @"C:\Windows\explorer.exe", "Microsoft.Windows.Explorer", @"C:\Programs\Snapik\Snapik.exe"));
}
