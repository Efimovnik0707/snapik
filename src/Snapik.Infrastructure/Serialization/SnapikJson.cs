using System.Text.Json;
using System.Text.Json.Serialization;

namespace Snapik.Infrastructure.Serialization;

public static class SnapikJson
{
    public static JsonSerializerOptions Options { get; } = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        WriteIndented = true,
        Converters = { new JsonStringEnumConverter(JsonNamingPolicy.CamelCase) }
    };
}

