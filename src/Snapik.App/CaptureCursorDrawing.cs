using System;
using System.Runtime.InteropServices;

namespace Snapik.App;

internal static class CaptureCursorDrawing
{
    internal static void Draw(System.Drawing.Graphics graphics, int left, int top)
    {
        var cursor = new CursorInfo { Size = Marshal.SizeOf<CursorInfo>() };
        if (!GetCursorInfo(ref cursor) || (cursor.Flags & 1) == 0) return;
        var icon = CopyIcon(cursor.Handle);
        if (icon == IntPtr.Zero) return;
        try
        {
            if (!GetIconInfo(icon, out var info)) return;
            try
            {
                var dc = graphics.GetHdc();
                try { DrawIconEx(dc, cursor.X - left - (int)info.HotspotX, cursor.Y - top - (int)info.HotspotY, icon, 0, 0, 0, IntPtr.Zero, 3); }
                finally { graphics.ReleaseHdc(dc); }
            }
            finally { if (info.Mask != IntPtr.Zero) DeleteObject(info.Mask); if (info.Color != IntPtr.Zero) DeleteObject(info.Color); }
        }
        finally { DestroyIcon(icon); }
    }
    [StructLayout(LayoutKind.Sequential)] private struct CursorInfo { public int Size; public int Flags; public IntPtr Handle; public int X; public int Y; }
    [StructLayout(LayoutKind.Sequential)] private struct IconInfo { public int IsIcon; public uint HotspotX; public uint HotspotY; public IntPtr Mask; public IntPtr Color; }
    [DllImport("user32.dll")] [return: MarshalAs(UnmanagedType.Bool)] private static extern bool GetCursorInfo(ref CursorInfo info);
    [DllImport("user32.dll")] private static extern IntPtr CopyIcon(IntPtr icon);
    [DllImport("user32.dll")] [return: MarshalAs(UnmanagedType.Bool)] private static extern bool GetIconInfo(IntPtr icon, out IconInfo info);
    [DllImport("user32.dll")] [return: MarshalAs(UnmanagedType.Bool)] private static extern bool DestroyIcon(IntPtr icon);
    [DllImport("gdi32.dll")] [return: MarshalAs(UnmanagedType.Bool)] private static extern bool DeleteObject(IntPtr handle);
    [DllImport("user32.dll")] [return: MarshalAs(UnmanagedType.Bool)] private static extern bool DrawIconEx(IntPtr dc, int x, int y, IntPtr icon, int width, int height, uint step, IntPtr brush, uint flags);
}
