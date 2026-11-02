using System.Diagnostics;
using System.Text.RegularExpressions;

namespace Pb0;

// Uses the installed mod's public INI interface; no upstream Lua/C++ is copied into this launcher.
public sealed class GameBridge(string gameRoot, string runDir) : IDisposable
{
    string? iniPath, previous, written;
    bool existed;
    bool createdAppId;
    FileStream? lease;
    public string Exe => Path.Combine(gameRoot,"platform","steam","PBZ.exe");
    public string Mod => Path.Combine(gameRoot,"platform","steam","ue4ss","Mods","PBZCoop");
    public object Inspect() => new {gameRoot,gameExe=File.Exists(Exe),
        loader=File.Exists(Path.Combine(gameRoot,"platform","steam","dwmapi.dll")),
        ue4ss=Directory.Exists(Path.Combine(gameRoot,"platform","steam","ue4ss")),
        phantomPact=File.Exists(Path.Combine(Mod,"Scripts","main.lua")),
        native=File.Exists(Path.Combine(Mod,"dlls","main.dll")),
        pvp=File.Exists(Path.Combine(Mod,"Scripts","pvp.lua"))};
    public void Configure(Room room,bool host,int instance)
    {
        if(iniPath!=null)return;
        if(!File.Exists(Exe))throw new IOException("未找到游戏程序："+Exe);
        if(!File.Exists(Path.Combine(gameRoot,"platform","steam","dwmapi.dll")) ||
            !File.Exists(Path.Combine(Mod,"dlls","main.dll")) || !File.Exists(Path.Combine(Mod,"Scripts","pvp.lua")))
            throw new IOException("游戏缺少 PBZ 专用 UE4SS 或支持 PvP 的 Phantom Pact。详见 README.md 的游戏接入步骤。");
        string dir=instance==1?Mod:Path.Combine(Mod,"inst"+instance);
        Directory.CreateDirectory(dir);
        lease=new FileStream(Path.Combine(dir,"pb0-session.lock"),FileMode.OpenOrCreate,FileAccess.ReadWrite,FileShare.None);
        iniPath=Path.Combine(dir,"PhantomPact.ini");existed=File.Exists(iniPath);
        previous=existed?File.ReadAllText(iniPath):"";
        File.WriteAllText(Path.Combine(runDir,"PhantomPact.before.ini"),previous);
        string text=previous;
        var changes=new Dictionary<string,string> {
            ["Role"]=host?"Host":"Guest",["Connect"]="Tailscale",["HostAddress"]="127.0.0.1",
            ["Port"]=(host?room.GamePort:room.GuestGamePort).ToString(),["Secret"]=room.Secret,["PvP"]="On",["OnlinePanel"]="Off",
            ["ThisPcOnly"]="On",["CoopEnemyHealth"]="100",["CoopEnemyPosture"]="100",["Language"]="Chinese"};
        foreach(var pair in changes)
        {
            var pattern=@"(?m)^\s*"+Regex.Escape(pair.Key)+@"\s*=.*$";
            var line=pair.Key+" = "+pair.Value;
            text=Regex.IsMatch(text,pattern)?Regex.Replace(text,pattern,_=>line):text.TrimEnd()+"\r\n"+line+"\r\n";
        }
        written=text;File.WriteAllText(iniPath,text);
        var appId=Path.Combine(Path.GetDirectoryName(Exe)!,"steam_appid.txt");
        if(!File.Exists(appId)) {File.WriteAllText(appId,"4115450");createdAppId=true;}
        else if(File.ReadAllText(appId).Trim()!="4115450") throw new IOException("现有 steam_appid.txt 与本游戏不符，不覆盖");
    }
    public Process Launch(int instance,bool isolatedSave)
    {
        if(iniPath==null)throw new InvalidOperationException("请先配置 Mod");
        var info=new ProcessStartInfo(Exe) {WorkingDirectory=Path.GetDirectoryName(Exe)!,UseShellExecute=false};
        info.Environment["PBZCOOP_INSTANCE"]=instance.ToString();
        // Standard UE options only. Steam/DRM remains responsible for normal authorization.
        foreach(var a in new[]{"ProjectPBZ","-basedir="+Path.Combine(gameRoot,"ProjectPBZ","Binaries","Win64"),
            "-pc-platform=Steam","-allowmultipleinstances","-windowed","-ResX=960","-ResY=540","-nosplash",
            "-ExecCmds=sg.ViewDistanceQuality 0,sg.ShadowQuality 0,sg.PostProcessQuality 0,sg.EffectsQuality 0,sg.FoliageQuality 0"}) info.ArgumentList.Add(a);
        if(isolatedSave)
        {
            // A separate user directory must be verified in the game log before two real copies may run together.
            info.ArgumentList.Add("-UserDir="+Path.Combine(runDir,"game-user"));
        }
        return Process.Start(info) ?? throw new IOException("启动游戏失败");
    }
    public void Dispose()
    {
        if(iniPath!=null && File.Exists(iniPath) && File.ReadAllText(iniPath)==written)
        {if(existed)File.WriteAllText(iniPath,previous);else File.Delete(iniPath);}
        lease?.Dispose();
        var appId=Path.Combine(Path.GetDirectoryName(Exe)!,"steam_appid.txt");
        if(createdAppId&&File.Exists(appId)&&File.ReadAllText(appId)=="4115450")File.Delete(appId);
    }
}
