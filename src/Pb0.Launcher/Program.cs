using System.Diagnostics;
using System.Text;
using System.Text.Json;

namespace Pb0;

public static class Program
{
    static readonly object outputLock=new();
    static bool json;
    static StreamWriter? events;
    public static void Emit(string type,object? data=null)
    {
        lock(outputLock)
        {
            string line=JsonSerializer.Serialize(new {time=DateTimeOffset.UtcNow,type,data});
            events?.WriteLine(line);
            if(json) Console.WriteLine(line);
            else
            {
                string label=type switch {"invite"=>"邀请码", "state"=>"连接状态", "message"=>"收到消息", "delivered"=>"对方已收到", "error"=>"错误", "latency"=>"延迟", _=>type};
                Console.WriteLine($"[{label}] {JsonSerializer.Serialize(data)}");
            }
        }
    }
    static string FindRoot()
    {
        foreach(string seed in new[]{AppContext.BaseDirectory,Environment.CurrentDirectory})
        {
            var d=new DirectoryInfo(seed);
            while(d!=null) {if(Directory.Exists(Path.Combine(d.FullName,"tools","easytier")))return d.FullName;d=d.Parent;}
        }
        return Environment.CurrentDirectory;
    }
    public static async Task<int> Main(string[] args)
    {
        Console.OutputEncoding=Encoding.UTF8;
        try {return await Run(args);} catch(Exception e) {Emit("error",new {error=e.Message});return 1;}
        finally {events?.Dispose();}
    }
    static async Task<int> Run(string[] args)
    {
        json=args.Contains("--json");
        string? Option(string key)
        {int i=Array.IndexOf(args,key);if(i<0)return null;if(i+1>=args.Length||args[i+1].StartsWith("--"))throw new ArgumentException(key+" 缺少参数");return args[i+1];}
        string root=Option("--root")??FindRoot();
        string gameRoot=Option("--game-root")??@"D:\SteamLibrary\steamapps\common\PBZ";
        string command=args.FirstOrDefault()??"menu";
        if(command is "--help" or "help")
        {
            Console.WriteLine("PB0 host [--local] [--invite-out FILE]\nPB0 join CODE | --invite-file FILE\nPB0 doctor\n会话命令: msg 文字 / status / game / quit\n选项: --json --no-input --duration SECONDS --test-message TEXT --run-dir DIR\n游戏: --game-root PATH --instance 1|2 --launch-game\n默认 EasyTier 公共节点；--local 仅用于本机测试。全程不修改物理网卡/IP/DNS/系统路由。");return 0;
        }
        if(command=="doctor") {using var b=new GameBridge(gameRoot,root);Emit("game",b.Inspect());return 0;}
        string? invitation=null;
        if(command=="menu")
        {
            Console.WriteLine("影之刃零 PvP 网络启动器\n1 创建房间\n2 输入邀请码加入\n3 检查游戏 Mod\n0 退出");
            switch(Console.ReadLine()?.Trim())
            {
                case "1":command="host";break;
                case "2":command="join";Console.WriteLine("粘贴邀请码：");invitation=Console.ReadLine();break;
                case "3":using(var b=new GameBridge(gameRoot,root))Emit("game",b.Inspect());return 0;
                default:return 0;
            }
        }
        if(command is not ("host" or "join"))throw new ArgumentException("未知命令，运行 PB0 help 查看用法");
        bool host=command=="host";
        int listener=Room.FreeListener();
        Room room;
        if(host)
        {
            string[]? peers=Option("--peers")?.Split(',',StringSplitOptions.RemoveEmptyEntries);
            do {room=Room.Create(args.Contains("--local"),listener,peers);} while(room.HostPort==room.GuestPort||room.HostPort==room.GamePort||room.GuestPort==room.GamePort);
            room=Room.Decode(room.Encode());
        }
        else
        {
            string? file=Option("--invite-file");
            invitation??=file!=null?File.ReadAllText(file):args.ElementAtOrDefault(1);
            if(string.IsNullOrWhiteSpace(invitation)||invitation.StartsWith("--"))throw new ArgumentException("请提供邀请码或 --invite-file");
            room=Room.Decode(invitation);
        }
        string runDir=Path.GetFullPath(Option("--run-dir")??Path.Combine(root,"runs",$"{DateTime.Now:yyyyMMdd-HHmmss}-{Environment.ProcessId}"));
        Directory.CreateDirectory(runDir);
        events=new StreamWriter(Path.Combine(runDir,"events.jsonl")){AutoFlush=true};
        if(host)
        {
            string code=room.Encode();
            // Invitation is an access secret. Keep it out of routine event logs.
            string inviteFile=Path.GetFullPath(Option("--invite-out")??Path.Combine(runDir,"invite.txt"));
            Directory.CreateDirectory(Path.GetDirectoryName(inviteFile)!);File.WriteAllText(inviteFile,code);
            if(json)Console.WriteLine(JsonSerializer.Serialize(new {type="invite",data=new {code,path=inviteFile}}));
            else Console.WriteLine("\n将下面的完整邀请码发给另一位玩家（24 小时内有效）：\n"+code+"\n");
            Emit("room_created",new {room.Id,inviteFile,local=room.Local});
        }
        else Emit("room_joining",new {room.Id,local=room.Local});
        using var cancel=new CancellationTokenSource();
        Console.CancelKeyPress+=(_,e)=>{e.Cancel=true;cancel.Cancel();};
        if(Option("--duration") is { } duration) cancel.CancelAfter(TimeSpan.FromSeconds(double.Parse(duration)));
        await using var transport=new EasyTierTransport(room,host,root,runDir,listener,Emit,args.Contains("--force-relay"));
        using var bridge=new GameBridge(gameRoot,runDir);
        var connected=new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        TransportState state=new("connecting","unknown",null,null);
        string? testMessage=Option("--test-message"); bool sentTest=false; long lastLatency=0;
        transport.Status+=s=>
        {
            state=s;
            if(s.State=="connected")connected.TrySetResult();
            if(s.State=="connected"&&Environment.TickCount64-lastLatency>5000)
            {lastLatency=Environment.TickCount64;Emit("latency",new {s.RttMs,s.Path,s.PeerIp});}
        };
        transport.Message+=m=>Emit("message",new {text=m});
        transport.Delivered+=m=>Emit("delivered",new {text=m});
        await transport.StartAsync(cancel.Token);
        int instance=int.Parse(Option("--instance")??"1");
        if(instance is <1 or >2)throw new ArgumentException("instance 只支持 1 或 2");
        Process? game=null;
        void LaunchGame()
        {
            if(game is {HasExited:false})return;
            // Multiple games require explicit development mode and independently verified save roots.
            foreach(var other in Process.GetProcessesByName("PBZ"))
            {
                using(other)
                {
                    if(other.HasExited)continue;
                    string otherExe;
                    try {otherExe=other.MainModule?.FileName ?? throw new IOException("不能确认已有游戏路径");}
                    catch(System.ComponentModel.Win32Exception) {throw new IOException("不能确认已有游戏路径，不启动第二实例");}
                    var otherRoot=Path.GetFullPath(Path.Combine(Path.GetDirectoryName(otherExe)!,"..",".."));
                    if(!args.Contains("--allow-isolated-games") || !GameBridge.VerifiedIsolation(gameRoot) || !GameBridge.VerifiedIsolation(otherRoot) ||
                        string.Equals(Path.GetFullPath(gameRoot),otherRoot,StringComparison.OrdinalIgnoreCase))
                        throw new IOException("已有 PBZ 进程；双实例仅允许不同且已实测存档隔离的测试副本。");
                }
            }
            bridge.Configure(room,host,instance);
            game=bridge.Launch(instance,isolatedSave:true);
            Emit("game_started",new {pid=game.Id,instance});
        }
        bool launchWhenReady=args.Contains("--launch-game");
        Task<string?>? input=args.Contains("--no-input")?null:Task.Run(Console.ReadLine);
        if(!json&&!args.Contains("--no-input"))Console.WriteLine("连接后可输入 msg 消息 / status / game / quit");
        try
        {
            while(!cancel.IsCancellationRequested)
            {
                if(transport.Completion.IsCompleted) throw new IOException("网络组件已停止，请查看本次运行的错误日志");
                if(connected.Task.IsCompleted&&!sentTest)
                {sentTest=true;if(testMessage!=null)await transport.SendAsync(testMessage);}
                if(connected.Task.IsCompleted&&launchWhenReady) {launchWhenReady=false;LaunchGame();}
                if(game!=null&&game.HasExited) {Emit("game_exited",new {game.ExitCode});break;}
                if(input is {IsCompleted:true})
                {
                    string? line=await input;
                    if(line==null)input=null;
                    else
                    {
                        try
                        {
                            if(line=="quit"||line=="exit")break;
                            if(line=="status")Emit("state",state);
                            else if(line=="game")LaunchGame();
                            else if(line.StartsWith("msg "))await transport.SendAsync(line[4..]);
                        }
                        catch(Exception e) {Emit("command_error",new {error=e.Message});}
                        input=Task.Run(Console.ReadLine);
                    }
                }
                await Task.Delay(100,cancel.Token);
            }
        }
        catch(OperationCanceledException) { }
        finally {game?.Dispose();}
        await transport.DisposeAsync();
        Emit("stopped",new {coreStopped=true});
        return 0;
    }
}
