using Snapik.App;

namespace Snapik.App.Imaging.Tests;

public sealed class SaveNamingTests
{
    [Fact]
    public void A_free_name_is_taken_as_it_is() =>
        Assert.Equal("Snapik-20260912-171827", SaveNaming.FreeName("Snapik-20260912-171827", _ => false));

    [Fact]
    public void A_taken_name_gets_the_next_number()
    {
        var taken = new HashSet<string> { "package", "package-2" };

        Assert.Equal("package-2", SaveNaming.FreeName("package", name => name == "package"));
        Assert.Equal("package-3", SaveNaming.FreeName("package", taken.Contains));
    }

    [Fact]
    public void A_folder_where_every_name_is_taken_gives_nothing() =>
        Assert.Null(SaveNaming.FreeName("package", _ => true));

    [Theory]
    [InlineData("png", "*.png;*.jpg;*.jpeg")]
    [InlineData("jpeg", "*.jpg;*.jpeg;*.png")]
    public void The_first_filter_line_starts_with_the_preferred_format(string saveFormat, string expected)
    {
        var filter = SaveNaming.ImageFilter(saveFormat, "All supported");

        Assert.Equal($"All supported ({expected})", filter.Split('|')[0]);
        Assert.Equal(expected, filter.Split('|')[1]);
        Assert.EndsWith("PNG (*.png)|*.png|JPEG (*.jpg;*.jpeg)|*.jpg;*.jpeg", filter);
    }
}
