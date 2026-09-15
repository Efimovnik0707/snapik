using System.IO;
using Snapik.App;

namespace Snapik.App.Imaging.Tests;

public sealed class AppDataPathsTests
{
    [Fact]
    public void The_folder_of_the_old_name_becomes_the_folder_of_the_new_one()
    {
        using var temp = new TempFolder();
        var legacy = Path.Combine(temp.Path, "SnapBrief");
        var root = Path.Combine(temp.Path, "Snapik");
        Directory.CreateDirectory(Path.Combine(legacy, "sessions", "one"));
        File.WriteAllText(Path.Combine(legacy, "settings.json"), "{\"язык\":\"ru\"}");
        File.WriteAllText(Path.Combine(legacy, "sessions", "one", "session.json"), "{}");

        AppDataPaths.CarryOverLegacyData(legacy, root);

        Assert.Equal("{\"язык\":\"ru\"}", File.ReadAllText(Path.Combine(root, "settings.json")));
        Assert.True(File.Exists(Path.Combine(root, "sessions", "one", "session.json")));
        Assert.False(Directory.Exists(legacy));
    }

    [Fact]
    public void A_folder_of_the_new_name_is_never_overwritten()
    {
        using var temp = new TempFolder();
        var legacy = Path.Combine(temp.Path, "SnapBrief");
        var root = Path.Combine(temp.Path, "Snapik");
        Directory.CreateDirectory(legacy);
        Directory.CreateDirectory(root);
        File.WriteAllText(Path.Combine(legacy, "settings.json"), "old");
        File.WriteAllText(Path.Combine(root, "settings.json"), "new");

        AppDataPaths.CarryOverLegacyData(legacy, root);

        Assert.Equal("new", File.ReadAllText(Path.Combine(root, "settings.json")));
        Assert.True(Directory.Exists(legacy));
    }

    [Fact]
    public void Without_a_folder_of_the_old_name_nothing_is_created()
    {
        using var temp = new TempFolder();
        var legacy = Path.Combine(temp.Path, "SnapBrief");
        var root = Path.Combine(temp.Path, "Snapik");

        AppDataPaths.CarryOverLegacyData(legacy, root);

        Assert.False(Directory.Exists(root));
    }

    private sealed class TempFolder : System.IDisposable
    {
        public TempFolder()
        {
            Path = System.IO.Path.Combine(System.IO.Path.GetTempPath(), "snapik-tests-" + System.Guid.NewGuid().ToString("N"));
            Directory.CreateDirectory(Path);
        }

        public string Path { get; }

        public void Dispose()
        {
            try { Directory.Delete(Path, recursive: true); } catch { }
        }
    }
}
