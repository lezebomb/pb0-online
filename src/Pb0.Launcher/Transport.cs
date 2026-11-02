using System.Diagnostics;
using System.Net;
using System.Net.Sockets;
using System.Security.Cryptography;
using System.Text.Json;

namespace Pb0;

public record TransportState(string State, string Path, string? PeerIp, double? RttMs);
public interface ITransport : IAsyncDisposable
{
    Task Completion {get;}
    event Action<TransportState>? Status;
    event Action<string>? Message;
    event Action<string>? Delivered;
    Task StartAsync(CancellationToken ct);
    Task SendAsync(string text);
}

public sealed class EasyTierTransport(Room room, bool host, string root, string runDir,
    int listenerPort, Action<string,object?> emit, bool forceRelay=false) : ITransport
{
    public event Action<TransportState>? Status;
    public event Action<string>? Message;
    public event Action<string>? Delivered;
    readonly UdpClient udp=new(new IPEndPoint(IPAddress.Loopback,room.Port(host)));
    readonly int forwardPort=Room.FreeUdp(room.HostPort,room.GuestPort,room.GamePort,room.GuestGamePort,listenerPort), rpcPort=Room.FreeTcp(listenerPort);
    readonly byte[] key=Convert.FromHexString(room.Secret);
    readonly string epoch=Guid.NewGuid().ToString("N"), sender=host?"host":"guest";
    readonly Dictionary<long,(byte[] Bytes,long Last,int Attempts,string Text)> pending=[];
    readonly HashSet<string> seen=[];
    readonly Queue<string> seenOrder=[];
    readonly Dictionary<long,long> pings=[];
    readonly object gate=new();
    readonly CancellationTokenSource stop=new();
    OwnedProcess? core;
    Task? receiveTask, pollTask;
    long seq, lastReceived, started;
    string path="unknown", peerIp="", lastState="", remoteEpoch="";
    double? rtt;
    bool ready;
    int disposed;
    public int CorePid => core?.Process.Id ?? 0;
    public Task Completion => pollTask ?? Task.CompletedTask;
    string CoreDir => Path.Combine(root,"tools","easytier","easytier-windows-x86_64");
    record Packet(int V,string Room,string Sender,string Epoch,long Seq,string Kind,long Ref,string Text);
    record Envelope(string Data,string Mac);

    public async Task StartAsync(CancellationToken ct)
    {
        Directory.CreateDirectory(runDir);
        ct.Register(stop.Cancel);
        started=Environment.TickCount64;
        StartCore();
        receiveTask=ReceiveLoop(stop.Token); pollTask=PollLoop(stop.Token);
        await Task.CompletedTask;
    }
    void StartCore()
    {
        var coreExe=Path.Combine(CoreDir,"easytier-core.exe");
        if(!File.Exists(coreExe)) throw new FileNotFoundException("缺少 EasyTier，请运行 scripts/setup.ps1",coreExe);
        var info=new ProcessStartInfo(coreExe) {WorkingDirectory=runDir};
        // Secrets are inherited through the child's environment, never placed on its command line.
        foreach(var k in info.Environment.Keys.Where(k=>k.StartsWith("ET_",StringComparison.OrdinalIgnoreCase)).ToArray()) info.Environment.Remove(k);
        info.Environment["ET_NETWORK_NAME"]=room.NetworkName;
        info.Environment["ET_NETWORK_SECRET"]=room.Secret;
        string own=room.Ip(host),remote=room.Ip(!host);
        string[] args=["--ipv4",own,"--no-tun","--use-smoltcp","true","--bind-device","false",
            "--proxy-networks",$"127.0.0.1/32->{own}/32","--hostname",$"pb0-{room.Id[..16]}-{sender}",
            "--instance-name",$"pb0-{room.Id}-{sender}","--listeners",$"tcp://{(room.Local?"127.0.0.1":"0.0.0.0")}:{listenerPort}",
            $"udp://{(room.Local?"127.0.0.1":"0.0.0.0")}:{listenerPort}","--rpc-portal",$"127.0.0.1:{rpcPort}",
            "--latency-first","true","--accept-dns","false","--disable-upnp","true",
            "--console-log-level","error","--file-log-level","off",
            "--port-forward",$"udp://127.0.0.1:{forwardPort}/{remote}:{room.Port(!host)}"];
        foreach(var a in args) info.ArgumentList.Add(a);
        if(forceRelay)foreach(var a in new[]{"--disable-p2p","true","--disable-udp-hole-punching","true","--disable-tcp-hole-punching","true"}) info.ArgumentList.Add(a);
        if(!host)
        {info.ArgumentList.Add("--port-forward"); info.ArgumentList.Add($"udp://127.0.0.1:{room.GuestGamePort}/{remote}:{room.GamePort}");}
        if(!room.Local || !host) {info.ArgumentList.Add("--peers");foreach(var peer in room.Peers) info.ArgumentList.Add(peer);}
        core=new OwnedProcess(info,Path.Combine(runDir,"easytier.log"));
        emit("core_started",new {pid=CorePid,rpcPort,virtualIp=own,mode="userspace-udp"});
        File.WriteAllText(Path.Combine(runDir,"process.json"),JsonSerializer.Serialize(new {launcherPid=Environment.ProcessId,corePid=CorePid,rpcPort,forwardPort}));
    }
    byte[] Encode(Packet p)
    {
        byte[] body=JsonSerializer.SerializeToUtf8Bytes(p);
        return JsonSerializer.SerializeToUtf8Bytes(new Envelope(Convert.ToBase64String(body),Convert.ToHexStringLower(HMACSHA256.HashData(key,body))));
    }
    async Task SendWire(byte[] bytes)
    {try {await udp.SendAsync(bytes,new IPEndPoint(IPAddress.Loopback,forwardPort),stop.Token);} catch(SocketException) { } }
    Packet NewPacket(string kind,long reference=0,string text="") => new(1,room.Id,sender,epoch,Interlocked.Increment(ref seq),kind,reference,text);
    public async Task SendAsync(string text)
    {
        if(string.IsNullOrWhiteSpace(text)||System.Text.Encoding.UTF8.GetByteCount(text)>300) throw new ArgumentException("消息限 300 字节");
        var p=NewPacket("message",text:text);var bytes=Encode(p);
        lock(gate) pending[p.Seq]=(bytes,Environment.TickCount64,1,text);
        await SendWire(bytes);
    }
    async Task ReceiveLoop(CancellationToken ct)
    {
        while(!ct.IsCancellationRequested)
        {
            try
            {
                var data=await udp.ReceiveAsync(ct);
                if(!IPAddress.IsLoopback(data.RemoteEndPoint.Address)||data.Buffer.Length>1400) continue;
                Envelope? envelope=JsonSerializer.Deserialize<Envelope>(data.Buffer);
                if(envelope is null||envelope.Data is null||envelope.Mac is null) continue;
                byte[] body=Convert.FromBase64String(envelope.Data),signature=Convert.FromHexString(envelope.Mac);
                if(!CryptographicOperations.FixedTimeEquals(signature,HMACSHA256.HashData(key,body))) continue;
                var p=JsonSerializer.Deserialize<Packet>(body);
                if(p is null||p.V!=1||p.Room!=room.Id||p.Sender!=(host?"guest":"host")||
                    p.Epoch is null||p.Epoch.Length!=32||p.Seq<=0||p.Kind is not ("ping" or "pong" or "message" or "ack")) continue;
                bool isAck=false; string? delivered=null; bool fresh=false;
                lock(gate)
                {
                    if(p.Kind=="pong")
                    {
                        // Require a response to this process's fresh ping before accepting a new remote epoch.
                        if(p.Text!=epoch||!pings.Remove(p.Ref,out long sent)) continue;
                        var sample=(double)(Environment.TickCount64-sent);rtt=rtt is null?sample:rtt*0.8+sample*0.2;
                        remoteEpoch=p.Epoch;lastReceived=Environment.TickCount64;ready=true;
                    }
                    else if(p.Kind!="ping")
                    {
                        if(p.Epoch!=remoteEpoch||!ready) continue;
                        lastReceived=Environment.TickCount64;
                    }
                    if(p.Kind=="ack"&&p.Text==epoch&&pending.Remove(p.Ref,out var sentMessage)) {isAck=true;delivered=sentMessage.Text;}
                    if(p.Kind=="message")
                    {
                        fresh=seen.Add(p.Epoch+":"+p.Seq);
                        if(fresh){seenOrder.Enqueue(p.Epoch+":"+p.Seq);if(seenOrder.Count>512)seen.Remove(seenOrder.Dequeue());}
                    }
                }
                if(p.Kind=="ping") await SendWire(Encode(NewPacket("pong",p.Seq,p.Epoch)));
                if(p.Kind=="message") {await SendWire(Encode(NewPacket("ack",p.Seq,p.Epoch))); if(fresh) Message?.Invoke(p.Text);}
                if(isAck) Delivered?.Invoke(delivered!);
            }
            catch(OperationCanceledException) {break;}
            catch(SocketException) {if(ct.IsCancellationRequested)break;await Task.Delay(50,ct);}
            catch(Exception e) when(e is JsonException or FormatException or ArgumentException) { }
        }
    }
    async Task PollLoop(CancellationToken ct)
    {
        long nextRoute=0;int restarts=0;
        try
        {
            while(!ct.IsCancellationRequested)
            {
                long now=Environment.TickCount64;
                if(core!.Process.HasExited)
                {
                    if(++restarts>3) throw new IOException("EasyTier 连续退出，请查看本次 runs 目录中的 easytier.log");
                    emit("core_restarting",new {attempt=restarts});core.Dispose();core=null;
                    await Task.Delay(1000,ct);StartCore();
                }
                if(now>=nextRoute)
                {
                    nextRoute=now+2000;
                    try {await ReadRoute(ct);} catch(Exception e) when(e is IOException or JsonException or TimeoutException or SocketException) { }
                }
                var ping=NewPacket("ping");
                List<byte[]> retry=[];List<string> failed=[];
                TransportState state;
                lock(gate)
                {
                    pings[ping.Seq]=now;
                    foreach(var id in pings.Where(k=>now-k.Value>8000).Select(k=>k.Key).ToArray())pings.Remove(id);
                    foreach(var item in pending.ToArray())
                    {
                        var value=item.Value;
                        if(now-value.Last<500)continue;
                        if(value.Attempts>=16) {pending.Remove(item.Key);failed.Add(value.Text);continue;}
                        retry.Add(value.Bytes);pending[item.Key]=(value.Bytes,now,value.Attempts+1,value.Text);
                    }
                    var s=ready&&now-lastReceived<3500?"connected":ready?"reconnecting":now-started<45000?"connecting":"unreachable";
                    state=new(s,path,string.IsNullOrEmpty(peerIp)?null:peerIp,rtt);
                }
                await SendWire(Encode(ping));foreach(var bytes in retry)await SendWire(bytes);
                foreach(var text in failed)emit("delivery_failed",new {text});
                Status?.Invoke(state);
                if(state.State!=lastState) {lastState=state.State;emit("state",state);}
                File.WriteAllText(Path.Combine(runDir,"status.json"),JsonSerializer.Serialize(state));
                await Task.Delay(500,ct);
            }
        }
        catch(OperationCanceledException) { }
        catch(Exception e) {emit("transport_error",new {error=e.Message});stop.Cancel();}
    }
    async Task ReadRoute(CancellationToken ct)
    {
        var info=new ProcessStartInfo(Path.Combine(CoreDir,"easytier-cli.exe")) {UseShellExecute=false,CreateNoWindow=true,RedirectStandardOutput=true,RedirectStandardError=true};
        foreach(var a in new[]{"-p",$"127.0.0.1:{rpcPort}","--no-trunc","-o","json","route"}) info.ArgumentList.Add(a);
        using var p=Process.Start(info)!;
        using var timeout=CancellationTokenSource.CreateLinkedTokenSource(ct);timeout.CancelAfter(2500);
        var output=p.StandardOutput.ReadToEndAsync(ct);var error=p.StandardError.ReadToEndAsync(ct);
        try {await p.WaitForExitAsync(timeout.Token);}
        catch(OperationCanceledException) {try{p.Kill(true);}catch(InvalidOperationException){} if(ct.IsCancellationRequested)throw;throw new TimeoutException();}
        var json=await output;await error;if(p.ExitCode!=0)return;
        using var doc=JsonDocument.Parse(json);
        if(doc.RootElement.ValueKind!=JsonValueKind.Array)return;
        foreach(var row in doc.RootElement.EnumerateArray())
        {
            if(!row.TryGetProperty("hostname",out var name)||name.GetString()!=$"pb0-{room.Id[..16]}-{(host?"guest":"host")}")continue;
            var ip=row.GetProperty("ipv4").GetString()?.Split('/')[0];
            if(ip!=room.Ip(!host))continue;
            int hops=row.TryGetProperty("path_len_lat_first",out var best)?best.GetInt32():row.GetProperty("path_len").GetInt32();
            lock(gate) {peerIp=ip;path=hops>1?"relay":"p2p";}
            return;
        }
        lock(gate){path="unknown";peerIp="";}
    }
    public async ValueTask DisposeAsync()
    {
        if(Interlocked.Exchange(ref disposed,1)!=0)return;
        stop.Cancel();udp.Dispose();
        if(receiveTask!=null)try{await receiveTask;}catch(OperationCanceledException){}
        if(pollTask!=null)try{await pollTask;}catch(OperationCanceledException){}
        core?.Dispose();stop.Dispose();
    }
}
