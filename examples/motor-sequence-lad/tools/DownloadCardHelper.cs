using System;
using System.IO;
using System.Reflection;
using Siemens.Engineering.Download;
using Siemens.Engineering.Download.Configurations;
public static class DownloadCardHelper {
 public static void Configure(DownloadConfiguration c) {
  Console.WriteLine("DOWNLOAD_CONFIGURATION " + c.GetType().FullName + ": " + c.Message);
  var check=c as DownloadCheckConfiguration;
  if(check!=null)check.Checked=true;
  var target=c as TargetForSoftware;
  if(target!=null)target.CurrentSelection=TargetForSoftwareSelections.PlcSimulationAdvanced;
  var overwrite=c as OverwriteOnMemoryCard;
  if(overwrite!=null)overwrite.CurrentSelection=OverwriteOnMemoryCardSelections.Load;
  var consistent=c as ConsistentBlocksDownload;
  if(consistent!=null)consistent.CurrentSelection=ConsistentBlocksDownloadSelections.ConsistentDownload;
  var alarms=c as AlarmTextLibrariesDownload;
  if(alarms!=null)alarms.CurrentSelection=AlarmTextLibrariesDownloadSelections.ConsistentDownload;
 }
 public static DownloadResult SaveCard(DownloadProvider provider,string path) {
  return provider.Download(new DirectoryInfo(path),Configure);
 }
}
