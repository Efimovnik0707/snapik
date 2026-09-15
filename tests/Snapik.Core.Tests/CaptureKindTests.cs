using System.Text.Json;
using System.Text.Json.Nodes;
using Snapik.Core.Editing;
using Snapik.Core.Exporting;
using Snapik.Core.Models;
using Snapik.Infrastructure.Serialization;

namespace Snapik.Core.Tests;

public sealed class CaptureKindTests
{
    private static readonly DateTimeOffset Start = new(2026, 9, 15, 12, 0, 0, TimeSpan.Zero);

    [Fact]
    public void A_capture_written_before_the_kind_existed_reads_as_a_region()
    {
        var legacy = """
        {
          "id": "7f3b6f2a-0b3a-4f5c-9e1d-2a6c8b4d1e05",
          "sourceImagePath": "source/capture.png",
          "pixelWidth": 1920,
          "pixelHeight": 1080,
          "dpiX": 96,
          "dpiY": 96,
          "title": "",
          "note": "",
          "annotations": [],
          "monitorCount": -4
        }
        """;

        var capture = JsonSerializer.Deserialize<CaptureItem>(legacy, SnapikJson.Options);

        Assert.NotNull(capture);
        Assert.Equal(CaptureKind.Region, capture.Kind);
        // A missing field and a negative one from a foreign file end in the same place, so nothing
        // downstream has to ask whether the number makes sense.
        Assert.Equal(0, capture.MonitorCount);
    }

    [Fact]
    public void A_whole_screen_capture_keeps_its_kind_through_the_file()
    {
        var capture = CaptureItem.Create("source/screen.png", 3840, 1125) with
        {
            Kind = CaptureKind.Fullscreen,
            MonitorCount = 2
        };

        var json = JsonSerializer.Serialize(capture, SnapikJson.Options);
        var restored = JsonSerializer.Deserialize<CaptureItem>(json, SnapikJson.Options);

        Assert.Equal("fullscreen", JsonNode.Parse(json)!["kind"]!.GetValue<string>());
        Assert.NotNull(restored);
        Assert.Equal(CaptureKind.Fullscreen, restored.Kind);
        Assert.Equal(2, restored.MonitorCount);
    }

    [Fact]
    public void The_kind_of_a_capture_speaks_for_it_in_the_prompt()
    {
        var fullscreen = CaptureItem.Create("source/screen.png", 3840, 1125) with { Kind = CaptureKind.Fullscreen };
        var region = CaptureItem.Create("source/region.png", 800, 600);
        var generator = new PromptGenerator();

        var withFullscreen = generator.Generate(SessionOperations.AddCapture(SnapikSession.Create(Start), fullscreen, Start));
        var withRegion = generator.Generate(SessionOperations.AddCapture(SnapikSession.Create(Start), region, Start));

        Assert.Equal("Снимок A — весь экран.", withFullscreen);
        Assert.Equal(string.Empty, withRegion);
    }
}
