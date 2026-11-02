using System.Net;
using System.Net.Sockets;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;

namespace Pb0;

public sealed record Room(int Version, string Id, string Secret, string Subnet,
    int HostPort, int GuestPort, int GamePort, int GuestGamePort, string[] Peers, bool Local, long Expires)
{
    public string NetworkName => "pb0-" + Id;
    public string Ip(bool host) => Subnet + (host ? ".1" : ".2");
    public int Port(bool host) => host ? HostPort : GuestPort;
    public static Room Create(bool local, int listener, string[]? peers = null)
    {
        var used=new List<int>{listener};
        int Pick(){int p=FreeUdp(used.ToArray());used.Add(p);return p;}
        return new(
        2, Guid.NewGuid().ToString("N"), Convert.ToHexStringLower(RandomNumberGenerator.GetBytes(32)),
        $"10.{RandomNumberGenerator.GetInt32(64,224)}.{RandomNumberGenerator.GetInt32(1,255)}",
        Pick(), Pick(), Pick(), Pick(),
        local ? [$"tcp://127.0.0.1:{listener}"] : peers ?? ["tcp://107.150.25.187:11010", "udp://107.150.25.187:11010", "tcp://161.33.207.13:51010", "udp://161.33.207.13:51010"],
        local, DateTimeOffset.UtcNow.AddDays(1).ToUnixTimeSeconds());
    }
    public string Encode()
    {
        var bytes = JsonSerializer.SerializeToUtf8Bytes(this);
        return "PB0." + B64(bytes) + "." + Convert.ToHexStringLower(SHA256.HashData(bytes))[..12];
    }
    public static Room Decode(string code)
    {
        if (code.Length > 8192) throw new ArgumentException("邀请码过长");
        var parts = code.Trim().Split('.');
        if (parts.Length != 3 || parts[0] != "PB0") throw new ArgumentException("邀请码格式错误");
        var bytes = UnB64(parts[1]);
        if (Convert.ToHexStringLower(SHA256.HashData(bytes))[..12] != parts[2])
            throw new ArgumentException("邀请码校验失败，请完整复制");
        var r = JsonSerializer.Deserialize<Room>(bytes) ?? throw new ArgumentException("邀请码无效");
        if (r.Version != 2 || !Regex.IsMatch(r.Id ?? "", "^[0-9a-f]{32}$") ||
            !Regex.IsMatch(r.Secret ?? "", "^[0-9a-f]{64}$") ||
            !Regex.IsMatch(r.Subnet ?? "", @"^10\.(\d{1,3})\.(\d{1,3})$") ||
            !IPAddress.TryParse(r.Ip(true), out _) || r.HostPort is < 1024 or > 65535 ||
            r.GuestPort is < 1024 or > 65535 || r.GamePort is < 1024 or > 65535 ||
            r.GuestGamePort is < 1024 or > 65535 ||
            new[]{r.HostPort,r.GuestPort,r.GamePort,r.GuestGamePort}.Distinct().Count()!=4 ||
            r.Peers is null || r.Peers.Length is < 1 or > 4)
            throw new ArgumentException("邀请码参数无效");
        foreach (var p in r.Peers)
            if (p is null || p.Length > 240 || p.Any(char.IsControl) || !Uri.TryCreate(p,UriKind.Absolute,out var u) ||
                u.Scheme is not ("tcp" or "udp" or "ws" or "wss") || string.IsNullOrEmpty(u.Host) || u.Port < 1)
                throw new ArgumentException("邀请码中的节点地址无效");
        if (r.Expires < DateTimeOffset.UtcNow.ToUnixTimeSeconds()) throw new ArgumentException("邀请码已过期，请重新创建房间");
        return r;
    }
    public static int FreeUdp(params int[] excluded)
    {
        while(true){using var s=new UdpClient(new IPEndPoint(IPAddress.Any,0));
        int port=((IPEndPoint)s.Client.LocalEndPoint!).Port;if(!excluded.Contains(port))return port;}
    }
    public static int FreeTcp(params int[] excluded)
    {
        while(true){var l=new TcpListener(IPAddress.Loopback,0);l.Start();
        int port=((IPEndPoint)l.LocalEndpoint).Port;l.Stop();if(!excluded.Contains(port))return port;}
    }
    public static int FreeListener()
    {
        while(true)
        {
            var l=new TcpListener(IPAddress.Any,0);l.Start();
            int port=((IPEndPoint)l.LocalEndpoint).Port;
            try {using var s=new UdpClient(new IPEndPoint(IPAddress.Any,port));return port;}
            catch(SocketException) { }
            finally {l.Stop();}
        }
    }
    static string B64(byte[] bytes) => Convert.ToBase64String(bytes).TrimEnd('=').Replace('+','-').Replace('/','_');
    static byte[] UnB64(string value)
    {
        value=value.Replace('-','+').Replace('_','/');
        return Convert.FromBase64String(value.PadRight((value.Length+3)/4*4,'='));
    }
}
