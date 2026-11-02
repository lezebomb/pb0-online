using System.ComponentModel;
using System.Diagnostics;
using System.Runtime.InteropServices;

namespace Pb0;

// A job contains only children created by this launcher. Closing the launcher also closes this job.
public sealed class OwnedProcess : IDisposable
{
    public Process Process {get;}
    IntPtr job;
    readonly Task stdout, stderr;
    readonly StreamWriter log;
    public OwnedProcess(ProcessStartInfo info, string logPath)
    {
        info.UseShellExecute=false; info.CreateNoWindow=true;
        info.RedirectStandardOutput=true; info.RedirectStandardError=true;
        log=new StreamWriter(logPath,append:true) {AutoFlush=true};
        if (OperatingSystem.IsWindows())
        {
            job=CreateJobObject(IntPtr.Zero,null);
            if (job==IntPtr.Zero) throw new Win32Exception();
            var limits=new ExtendedLimit(); limits.Basic.LimitFlags=0x2000;
            if (!SetInformationJobObject(job,9,ref limits,Marshal.SizeOf<ExtendedLimit>()))
            { CloseHandle(job); job=IntPtr.Zero; log.Dispose(); throw new Win32Exception(); }
        }
        try
        {
            Process=Process.Start(info) ?? throw new IOException("无法启动 EasyTier");
            if (job!=IntPtr.Zero && !AssignProcessToJobObject(job,Process.Handle))
            { Process.Kill(true); throw new Win32Exception(); }
            stdout=Pump(Process.StandardOutput); stderr=Pump(Process.StandardError);
        }
        catch {if(job!=IntPtr.Zero)CloseHandle(job);job=IntPtr.Zero;log.Dispose();throw;}
    }
    async Task Pump(StreamReader reader)
    {
        try {while(await reader.ReadLineAsync() is { } line) lock(log) log.WriteLine(line);}
        catch(ObjectDisposedException) { }
    }
    public void Dispose()
    {
        try {if(!Process.HasExited) Process.Kill(entireProcessTree:true); Process.WaitForExit(3000);} catch(InvalidOperationException) { }
        if(job!=IntPtr.Zero) {CloseHandle(job);job=IntPtr.Zero;}
        try {Task.WaitAll([stdout,stderr],2000);} catch(AggregateException) { }
        log.Dispose(); Process.Dispose();
    }
    [StructLayout(LayoutKind.Sequential)] struct BasicLimit
    {public long ProcessTime,JobTime;public uint LimitFlags;public UIntPtr Min,Max;public uint Active;public UIntPtr Affinity;public uint Priority,Scheduling;}
    [StructLayout(LayoutKind.Sequential)] struct IoCounters {public ulong A,B,C,D,E,F;}
    [StructLayout(LayoutKind.Sequential)] struct ExtendedLimit
    {public BasicLimit Basic;public IoCounters Io;public UIntPtr ProcessMemory,JobMemory,PeakProcess,PeakJob;}
    [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern IntPtr CreateJobObject(IntPtr attrs,string? name);
    [DllImport("kernel32.dll",SetLastError=true)] static extern bool SetInformationJobObject(IntPtr job,int info,ref ExtendedLimit value,int size);
    [DllImport("kernel32.dll",SetLastError=true)] static extern bool AssignProcessToJobObject(IntPtr job,IntPtr process);
    [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr handle);
}
