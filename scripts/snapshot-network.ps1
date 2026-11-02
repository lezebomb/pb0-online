param([Parameter(Mandatory=$true)][string]$OutputPath)
$ErrorActionPreference='Stop'
$snapshot=[ordered]@{
  Adapters=@(Get-NetAdapter -IncludeHidden -ErrorAction Stop | Sort-Object InterfaceGuid | Select-Object InterfaceGuid,Name,InterfaceDescription,AdminStatus)
  Addresses=@(Get-NetIPAddress -ErrorAction Stop | Sort-Object InterfaceIndex,IPAddress | Select-Object InterfaceIndex,IPAddress,PrefixLength,PrefixOrigin)
  Dns=@(Get-DnsClientServerAddress -ErrorAction Stop | Sort-Object InterfaceIndex,AddressFamily | Select-Object InterfaceIndex,AddressFamily,ServerAddresses)
  Routes=@(Get-NetRoute -PolicyStore PersistentStore -ErrorAction Stop | Sort-Object InterfaceIndex,DestinationPrefix,NextHop | Select-Object InterfaceIndex,DestinationPrefix,NextHop,RouteMetric)
}
$snapshot | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $OutputPath -Encoding UTF8
Write-Output "Network snapshot saved. Adapter count: $($snapshot.Adapters.Count)"
