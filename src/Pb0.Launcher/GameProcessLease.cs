using System.ComponentModel;
using System.Diagnostics;
using System.Runtime.InteropServices;
namespace Pb0;
// This job owns only the exact game process started by this launcher.
internal sealed class GameProcessLease : IDisposable
{
    IntPtr job;
    public GameProcessLease(Process process)
    {
        if(!OperatingSystem.IsWindows())return;
        job=CreateJobObject(IntPtr.Zero,null);
        if(job==IntPtr.Zero)throw new Win32Exception();
        var limits=new ExtendedLimit();limits.Basic.Flags=0x2000;
        if(!SetInformationJobObject(job,9,ref limits,Marshal.SizeOf<ExtendedLimit>()) || !AssignProcessToJobObject(job,process.Handle))
        {var error=Marshal.GetLastWin32Error();CloseHandle(job);job=IntPtr.Zero;throw new Win32Exception(error);}
    }
    public void Dispose(){if(job!=IntPtr.Zero){CloseHandle(job);job=IntPtr.Zero;}}
    [StructLayout(LayoutKind.Sequential)] struct BasicLimit {public long ProcessTime,JobTime;public uint Flags;public UIntPtr Min,Max;public uint Active;public UIntPtr Affinity;public uint Priority,Scheduling;}
    [StructLayout(LayoutKind.Sequential)] struct IoCounters {public ulong A,B,C,D,E,F;}
    [StructLayout(LayoutKind.Sequential)] struct ExtendedLimit {public BasicLimit Basic;public IoCounters Io;public UIntPtr ProcessMemory,JobMemory,PeakProcess,PeakJob;}
    [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern IntPtr CreateJobObject(IntPtr attrs,string? name);
    [DllImport("kernel32.dll",SetLastError=true)] static extern bool SetInformationJobObject(IntPtr job,int type,ref ExtendedLimit value,int length);
    [DllImport("kernel32.dll",SetLastError=true)] static extern bool AssignProcessToJobObject(IntPtr job,IntPtr process);
    [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr handle);
}
