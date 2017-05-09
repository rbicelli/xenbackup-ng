#!/usr/bin/perl

# XenBackup-ng by Riccardo Bicelli - https://think-brick.blogspot.com
#
# This program is released under the MIT License
# 
# built on "XEN Server backup by Filippo Zanardo - http://pipposan.wordpress.com"
#
# Usage: "perl xenbackup.pl <job name>", where job name is the name of the job file located in subfolder "jobs", without ".conf" suffix.
#
# Difference between this and Xenbackup
# 1. Subroutines
# 2. Separation of configuration files and hierarchy:
#     - conf/strings.conf -> Where strings of log and mail notification can be localized
#     - conf/xenbackup.conf -> global configuration file, where you can specify also default parameters if you are not using jobs
#     - jobs/job.conf -> Job File, loaded after xenbackup.conf
# 3. Now backup is possible with VM Selection
# 4. Quiesce snapshot for Windows VM (Only if guest has Xenserver VSS provider installed)
# 5. Mail Notification now comes with a head Section with a checklist of backed up VM and verbose log attached, if wanted
# 6. More controls on commands executed (e.g. Exit codes checked after some command execution)
# 7. Keeps care of running state of the VM (e.g if a VM in in state halted it is not started after backup job)
# 8. Versioning (deletion of files) executed only if backup process went fine


#SCRIPT_VERSION = "1.1.0";

use Switch;

#Load Strings File
loadFile("./conf/strings.conf");

#Load Default Config File
loadFile("./conf/xenbackup.conf");

#Load Job File
loadFile("./jobs/".$ARGV[0].".conf");

#Init Some variables

$hostname = `hostname`;
$hostname  =~ s/\r|\n//g;

$tstarted = `date`; 				# Get the starting date
$gstarttime = time();

$backupResult = $OK;

#Open Log Files
if ($appendLog eq true) {                        # If Verbose Logging is Selected, then open job's log file, that will be appended to mail notification.
	open (F_LOG_A, '>/tmp/emaillog');
	print F_LOG_A "$Line\n";
	print F_LOG_A "$BackupLog\n";
	print F_LOG_A "$Line\n";
}

if ($logging eq true) {                          # Open Log File
	open (F_LOG, ">>$logfile");
}



logLine("$Beginning $hostname, $Job: [$jobName]");

$b=substr($backupdir, 0, -1);


# Mount Backup Media
if ($Automount eq true ){
	$ismounted=`mount |grep $b`;
	if ($ismounted == "") {
		$mount = `$MountCommand`;
		logLine("$Executing: $MountCommand\n");
	}else{
		logLine("$NotMount\n");
	}
}


# Check Space: check prior size of the VM, then check the space of the backup media.
if ($checkspace eq true) {
	$actualspace = `df -B M | grep $b`;

	@spaceman = split(' ', $actualspace);
	$i = 0;
	foreach my $val (@spaceman) {	
		
		if ($val eq $b ) {
			$k = $i -2;
			$aspace = @spaceman[$k];
			$aspace=substr($aspace, 0, -1);
		}
		$i = $i +1;
	}
	
	if ($aspace <= $spacerequired) {
		logLine("$backerror $nospace");

		
		if ($Automount eq true ){
			logLine("$Executing: $UMountCommand");
			$mount = `$UMountCommand`;			
		}
		
		if ($mailNotification){
			sendLogMail();
		}
		
		die "$backerror $nospace";
	}
}


# Expand Selection

$vmlist = `xe vm-list`;                             # Get the formatted list of guests
@lineList = split(/\n/,$vmlist);                    # Split the list of guests into and array of lines
@uuid = ();                                         # Array to store uuid's in

foreach $line(@lineList){                           #for each line in the array
	if (substr($line,0,4) eq "uuid"){           #look for the word uuid at the beginning of the line
	push(@uuid, substr($line,23,36));           #if its there add the uuid to the array
	}
}

@uuid_b = ();					  #Array to store uuids to save


if ($fullbackup eq true) {                		  #Full backup
	logLine("$FullBackup $Selected");
	foreach $guest(@uuid){                            #Populate the array of guests to backup
	$VMName = getVMName($guest);
	
	$backupType = $FullBackup;

	if (grep $_ eq $guest, @dom0){
		logLine("$Skipping Dom0 $VMName ($guest)");
	} else {						
		if (grep $_ eq $guest, @Selected) {	#Skip VM in selection	
		logLine("$Skipping $SVMName ($guest)");			
		} else {
		push(@uuid_b, $guest);
		}
	}		
 	}
} else {						#Selective Backup
	logLine("$SelectiveBackup $Selected");
	$backupType = $SelectiveBackup;	
			
	foreach $tags(@Selected_Tags) { #Add Tags to Selection

        	@vm_tag = vmList('tags:contains="' . $tags . '"');

        	@Selected = mergeSelection(\@Selected, \@vm_tag);

	}
	
	foreach $app(@Selected_vApps) { #Add Virtual Appliances to Selection

        	@app = vmAppliance($app);

        	@Selected = mergeSelection(\@Selected, \@app);
	
	}

	foreach $guest(@Selected) {			#Cycle Selection of VM to backup
		if (grep $_ eq $guest, @uuid) { 	#If guest exists in pool then add it to array of UUIDs to backup
			$VMName = getVMName($guest);
			push(@uuid_b, $guest);
		} else {
			logLine("$Selected $Guest $NonExistent: $guest");
		}
	}


	
}                    

if ($usesnap eq true) {
	$backupMode = "Snapshot";
	
	if ($quiesce eq true) {
		$backupMode = "Snapshot/Quiesce";
	}

} else {

		$backupMode = "$ShutdownRestart";	

}
	
foreach $guest(@uuid_b){
												   #otherwise
		$tcurrent = `date`;                                                                #get the current date
		$starttime=time();

		$VMName=getVMName($guest);
		
		logLine("$StartBackup $VMName: $guest");
		
		$powerstate = getVMPowerstate($guest);

		$VMResult = $OK;

		if ($usesnap eq true){
			#Begin Of Snapshot Backup

			if ($removable eq true) {
				detachRemovableDevices();
			}
			
			$SnapResult = 1;			
			if ($quiesce eq true) {
				# Try Quiesce First
				logLine("$TakingSnap $guest $Name $VMName $WithQuiesce");
				$snapshotUUID= `xe vm-snapshot-with-quiesce vm=$guest new-name-label=$VMName-backup_vm`;
				if ($? > 0) {
				#If snapshot failed try with normal method
				logLine("$QuiesceFailed");
				$snapshotUUID= `xe vm-snapshot vm=$guest new-name-label=$VMName-backup_vm`;				
				}
			} else {
				logLine("$TakingSnap $guest $Name $VMName"); 			
				$snapshotUUID= `xe vm-snapshot vm=$guest new-name-label=$VMName-backup_vm`; #Snapshot the VM
			}
			$snapResult = $?;

			#Reattach removable devices, anyway
			if ($removable eq true) {
				reattachRemovableDevices();
			}

			if ($snapResult eq 0) {			
				$snapshotUUID=~ s/\n//g;                                    #remove the carrier return/linefeed
				$snapshotUUID=~ s/\r//g;
			
			
				logLine("$Snapshot $snapshotUUID $Created");
			
				logLine("$Turning $snapshotUUID $Snap2Vm");			
				$status= `xe template-param-set is-a-template=false ha-always-run=false uuid=$snapshotUUID`;
			
				logLine("$status");
			
				$fdate = `date +%y%m%d-%H%M`;
				$fdate=~ s/\n//g;                                    #get the current date in a format we can write
				$fdate=~ s/\r//g;                                    #get the current date in a format we can write

				logLine("$Exporting $snapshotUUID"); #export the snapshot
				#End Of Snapshot Mode
			} else {
				logLine("$SnapshotFailed");			
				$VMResult = $Error;
			}
		}else{
			#Shutdown-Export mode selected
			
			if ($powerstate eq "running") {			
				logLine("$Shutting $VMName"); #export the snapshot
				$shut = `xe vm-shutdown uuid=$guest`;
			}
			
			if ($removable eq true) {
				detachRemovableDevices();
			}
			
			$fdate = `date +%y%m%d-%H%M`;
			$fdate=~ s/\n//g;                                    #get the current date in a format we can write
			$fdate=~ s/\r//g;                                    #get the current date in a format we can write
		}

		if ($subfolder eq true ){				     #create folder structure
			if (-d $backupdir.$VMName) {
			}else {
				mkdir($backupdir.$VMName,0777);
			}
			$exportstring = $backupdir.$VMName."/".$VMName."-".$fdate.".xvatmp";
			$finalname = $backupdir.$VMName."/".$VMName."-".$fdate.".xva";
			$versiondir = $backupdir.$VMName;
		}else{
			$exportstring = $backupdir.$VMName."-".$fdate.".xvatmp";
			$finalname = $backupdir.$VMName."-".$fdate.".xva";
			$versiondir = $backupdir;
		}

		
		
		logLine("$Exporting $exportstring - $finalname");

		if ($compress eq true) {
			$compressstring = "compress=true";
			logLine("$Compression $Enabled");		
		} else {
			$compressstring = "";
			logLine("$Compression $Not $Enabled");		
		}		

		if ($usesnap eq true){
			$status= `xe vm-export vm=$snapshotUUID filename=$exportstring $compressstring`;
		}else{
			$status= `xe vm-export uuid=$guest filename=$exportstring $compressstring`;
		}
		
		logLine("$status");				
		logLine("$Rename");
				
		$status= `mv -vf $exportstring $finalname`;
		
		logLine("$status");
				
				
		if ($compress_after eq true) {
			#Compress backup
			if (substr($compressext,0,1) eq ".") {
				logLine("$Executing $compresscmd $finalname$compressext $finalname");
				$status= `$compresscmd $finalname$compressext $finalname`;
		
				#logLine("$status");
								
				$status =`rm -f $finalname`;
				
				$finalname = $finalname.$compressext;
				
				logLine("$logdate $finalname");
			
			}else{

				logLine("$logdate $Executing $compresscmd $finalname.$compressext $finalname");
	
				$status= `$compresscmd $finalname.$compressext $finalname`;				
				#logLine("$status");
								
				$finalname = $finalname.".".$compressext;
				logLine("$finalname");
				}
		}
		
		
		if ($usesnap eq true) {
			#Uninstall Snapshot
			$status= `xe vm-uninstall uuid=$snapshotUUID  force=true`;
			if ($? eq 0) {
				logLine("$DoneR $snapshotUUID");
			} else {
				$VMResult = "!?";
				$backupResult = "!?";
				logLine("$UnDoneR $snapshotUUID");
			}
		}else{
		
			if ($removable eq true) {
				reattachRemovableDevices();				
			}
			
			if ($powerstate eq "running") {
				logLine ("$Restarting $guest");
				$status = `xe vm-start uuid=$guest`;
			}
		}
		
		logLine ("$status");
				
		if (-e $finalname){
			
			if ($versioning eq true ){
			switch ($delmethod) {
				case "numbers" { 
						@files = <$versiondir/*>;
						$count = @files;
						$count = $count - $delnumber;
						
						my @sorted_files = sort { -M $a < -M $b } @files;
						
						for($i = 0; $i < $count; $i++) {
							# PRINT A NEW ROW EACH TIME DELETING A FILE
							logLine("$Deleting".@sorted_files[$i]);
							unlink(@sorted_files[$i]);
						}
				}
				case "hours" { 
					opendir(DIR, $versiondir);
					@files = readdir(DIR);
					closedir(DIR);

					foreach $file (@files) {
					   if (-M $versiondir."/".$file > $delnumber/24){
						logLine($Deleting.$versiondir."/".$file);
						unlink($versiondir."/".$file);	
					   }
					} 
				}
				case "days" { 
					opendir(DIR, $versiondir);
					@files = readdir(DIR);
					closedir(DIR);

					foreach $file (@files) {
					   if (-M $versiondir."/".$file > $delnumber){
						logLine ($Deleting.$versiondir."/".$file);
						unlink($versiondir."/".$file);
					   }
					}
				}
			}
		}
				
			$tcurrent = `date`;                                                           #get the current date
			$finishtime=time();
			$minutes=($finishtime-$starttime)/60;			
			logLine("$Completed $VMName $Elapsed $minutes");
			
		}else{
		
			logLine("$backerror $nofile");
			$VMResult = "!!";
			$backupResult = "!!";
		}
		$finishtime=time();
		$minutes=($finishtime-$starttime)/60;			
		$mailString .= "[$VMResult] VM: $VMName {$guest}, $Elapsed $minutes\n";
		
}


if ($Automount eq true ){
	logLine("$Executing: $UMountCommand");
	$mount = `$UMountCommand`;
}

$tfinished = `date`;
$gfinishtime = time();
$gminutes = ($gfinishtime - $gstarttime)/60;

logLine ("$Finished $tfinished");



#Init mail File

if ($appendLog eq true) {
	close (F_LOG_A);
}

if ($logging eq true) {
	close (F_LOG);
}

if ($mailNotification eq true){
	sendLogMail();	
}


################################################################################################
# 				Functions/Sub Library
################################################################################################

sub logLine {
	# Logs a line to the log file, requires log file to be opened before
	# 
	local $logdate;
	
	$logdate=localtime();

	if ($logging eq true) {
		print F_LOG "$logdate $_[0]\n";
	}
	if ($appendLog eq true) {
		print F_LOG_A "$logdate $_[0]\n";		
	}
}

sub loadFile {
	# This function loads and evals a file,relative to script directory
	# Get script Directory
	
	$0=~/^(.+[\\\/])[^\\\/]+[\\\/]*$/;
	$scriptdir= $1 || "./";
	
	$filename = $scriptdir . $_[0];	
	open L_FILE, $filename or die "Program stopping, couldn't open the file '$filename'.\n";
	my $lfile = join "", <L_FILE>;
	close L_FILE;
	eval $lfile;
	die "Couldn't interpret the file ($filename) that was given.\nError details follow: $@\n" if $@;
}


sub  vmList {

	$vmlist = `xe vm-list $_[0]`;                       # Get the formatted list of guests

        @lineList = split(/\n/,$vmlist);                    # Split the list of guests into and array of lines

        local @uuid = ();                                   # Array to store uuid's in

	foreach $line(@lineList){                           #for each line in the array

                if (substr($line,0,4) eq "uuid"){           #look for the word uuid at the beginning of the line

                push(@uuid, substr($line,23,36));           #if its there add the uuid to the array

        }

	}

        return @uuid;
}


sub getVMName {
	local $rval;
	# This Function gets a VM name given uuid in $1	
	$rval = `xe vm-list uuid=$_[0] | grep name-label | cut -b24-`;
	$rval=~ s/\n//g;
	$rval=~ s/\r//g;
	$rval =~ s/ /_/g;
	return($rval);	
}

sub getVMPowerstate {
	local $rval;
	# This Function gets a VM name given uuid in $1	
	$rval = `xe vm-list uuid=$_[0] | grep power-state | cut -b24-`;
	$rval=~ s/\n//g;
	$rval=~ s/\r//g;
	$rval =~ s/ /_/g;
	return($rval);	
}


sub detachRemovableDevices {
	@toreattach = ();
	@device = ();	
	foreach $rid(@removableuuid) {
		#logLine("xe vdi-list sr-uuid=$rid params=vbd-uuids --minimal");
		$srvbduuid = `xe vdi-list sr-uuid=$rid params=vbd-uuids --minimal`;
		
		if ($srvbduuid) {
			foreach $char (split //, $srvbduuid) {
				
				if ($char eq ",") {
					@srvbduuid = split(/,/,$srvbduuid);
					last;
				}else{
					@srvbduuid = $srvbduuid;
				}
			}
						
			foreach $mline(@srvbduuid){
				$e = `xe vbd-list vm-uuid=$guest uuid=$mline`;
				
				if ($e) {
					@mlineList = split(/\n/,$e);
					foreach $xline(@mlineList){
						if (substr($xline,9,4) eq "vdi-"){
							push(@toreattach, substr($xline,25,36));
							}
						if (substr($xline,11,6) eq "device"){
							push(@device, substr($xline,25,4));
						}
					}
					
					$unplug = `xe vbd-unplug uuid=$mline`;
					$dest = `xe vbd-destroy uuid=$mline`;
				}
				
			}
		}
	}
	
			
}

sub reattachRemovableDevices {
	logLine("$Reattaching $RemovableDevices");
	if (@toreattach) {
		$i = 0;
		foreach $zline(@toreattach){
			$create = `xe vbd-create vm-uuid=$guest vdi-uuid=$zline device=@device[$i] --minimal`;
			$plug = `xe vbd-plug uuid=$create`;
			$i=$i+1;
		}
	}
}

sub sendLogMail {
	open (F_MAIL, '>/tmp/emailmsg');
	print F_MAIL "To:$MailTo\n";
	print F_MAIL "From:$MailFrom\n";
	print F_MAIL "Subject: [$backupResult] $SubjectHeader [$jobName]\n";
	print F_MAIL "\n";
	print F_MAIL "$MailIntro\n\n";
	print F_MAIL "$HostName $hostname\n";	
	print F_MAIL "$JobName $jobName\n";
	print F_MAIL "$BackupMode $backupType, $backupMode\n";
	print F_MAIL "\n$JobDetails\n\n"; 

	print F_MAIL "$mailString\n";

	print F_MAIL "\n$TotalElapsed $gminutes min\n";

	close (F_MAIL);
	if ($appendLog eq true) {
		close F_LOG_A;
		$send = `cat /tmp/emailmsg /tmp/emaillog > /tmp/emailmsg_1`;
		$send = `ssmtp $MailTo </tmp/emailmsg_1`;
	} else { 
	$send = `ssmtp $MailTo </tmp/emailmsg`;
	}
}

sub mergeSelection {

	@A = @{$_[0]};
	@B = @{$_[1]};

	@seen{@A} = ();

	@merged = (@A, grep{!exists $seen{$_}} @B);

	return @merged;

}

sub vmAppliance {

	local $line = `xe appliance-list name-label=$_[0]  | grep VMs | cut -b30-`;

	local @ret = split ';', $line;

	return @ret;
}


sub  trim { 
	my $s = shift; 
	$s =~ s/^\s+|\s+$//g;
	return $s 
};



