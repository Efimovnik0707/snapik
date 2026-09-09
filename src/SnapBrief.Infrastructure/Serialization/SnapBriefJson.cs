using System.Text.Json;
using System.Text.Json.Serialization;

namespace SnapBrief.Infrastructure.Serialization;

public static class SnapBriefJson
{
    public static JsonSerializerOptions Options { get; } = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        WriteIndented = true,
        Converters = { new JsonStringEnumConverter(JsonNamingPolicy.CamelCase) }
    };
}

