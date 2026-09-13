using SnapBrief.App;

namespace SnapBrief.App.Imaging.Tests;

public sealed class SettingsMigrationTests
{
    [Fact]
    public void A_file_without_a_version_is_migrated_and_a_current_one_is_not()
    {
        Assert.True(SettingsMigration.NeedsMigration(0));
        Assert.False(SettingsMigration.NeedsMigration(SettingsMigration.CurrentVersion));
    }

    [Fact]
    public void The_volume_that_used_to_be_the_default_becomes_the_new_default()
    {
        Assert.Equal(40, SettingsMigration.SoundVolume(0, 60));
        Assert.Equal(SettingsMigration.DefaultSoundVolume, SettingsMigration.SoundVolume(0, 60));
    }

    [Fact]
    public void A_volume_the_user_picked_is_left_alone()
    {
        Assert.Equal(75, SettingsMigration.SoundVolume(0, 75));
        Assert.Equal(0, SettingsMigration.SoundVolume(0, 0));
        Assert.Equal(100, SettingsMigration.SoundVolume(0, 100));
    }

    [Fact]
    public void A_file_that_already_carries_the_version_keeps_even_the_old_default()
    {
        Assert.Equal(60, SettingsMigration.SoundVolume(SettingsMigration.CurrentVersion, 60));
    }
}
