#!/usr/bin/perl -w

my $Revision = "1.13";
# File tree checksum comparison tool
# Traverses filesystem from specified paths and compares trees
# with the following operating modes:
# 1) Comparison Mode: Compares tree structure and contents of two
# different sources.  Files are compared with chksums on the fly.
# 2) Verification Mode: Reads previously created checksum lists 
# to verify contents of existing source trees (if specified).
# 3) Checksum Mode: Creates output list of checksums for given 
# source trees.
# Optionally, the script can be given file lists or ranges from
# which to compare within the sources specified.
#
# Created by Victor E. Vaile, IV on 20101015
# 1.00 20101015 Initial Version
# 1.01 20101016 Changed ShowHelp() function for clean output,
#		and syntax flow. Added OptPrint() function.
#		Changed ParseCommandLine() function order
#		Used for loop for CleanDups() function calls.
#		Cleaned header and description area (comments)
#		Changed ReadVHash() to strip out superflous 
#		whitespace characters from STDIN
#		Added feature to change interpretation of 
#		unflagged list elements on command line.
# 1.02 20101022 Added CheckLSC(), and lsc output for missing
# 		files in source directories, and CallLSC()
# 		for list output
# 1.03 20101023 Added option to specify range file for passing
# 		multiple ranges via @rangefils()
# 		Changed CheckExist() to use array for missing
# 		data, insted of hash from previous non-sub block
# 		Added check for cygwin.
# 		Moved debug print from ReadFileList() to CheckExist()
# 1.04 20101106	Changed DoChkSums() to output array or hash based
# 		on passed arguments, as well as optionally eval the
# 		file list array with additional path prefix.
# 		Added ForkSums() sub, which does the same task as 
# 		DoChkSums(), except using fork to process with 
# 		4, or user specified number of threads.
# 		Added command line option for explicit assignment
# 		for source elements (for after $setflag usage).
# 		Added command line option to specify threads [count]
# 1.05 20101107	Added reaper() and $SIG{CHLD} handling to get rid
# 		of zombie processes.
# 1.06 20110723	Changed scope our -> my for compatability. Added
# 		Added $fullstat var to track warnings. Debugging
# 		output for verbose mode. Help text for -rev (!= -r).
# 		Output to file with var $STDOUT
# 1.07 20110723	Revision tracking with new variable. Move output
#		file creation to end, so as not to enumerate it 
#		during the directory tree walk. Added OutPrint(),
#		CleanExit(), [imported] WriteFile(). [& used them]
# 1.08 20110727	Added handling for standalone files in @srclist for
#		creating checksums. Added sort for hash, version flag.
#		Conditional md5sum explicit empty dir only on FreeBSD
# 1.09 20110804	When writing out file if $reverse, use '  ' (2 spaces)
#		as delimiter to be compatible with md5sum check files
#		on Linux. -lnx option for same in non file out mode
#		Warning output when verify fails to match any files
# 1.10 20110808	Added check for verify files to swap input assignment
#		if order is reversed.  Comment handling in chkfiles
# 1.11 20111001	Fixed eval of single element as empty dir.
# 1.12 20130414	Updated help and license info
# 1.14 20141023	Parsing for list of directories to chksum

use strict 'vars';
use strict 'subs';
use POSIX ":sys_wait_h";
my @bpath = split /\//,$0;
my $bfil = pop(@bpath);
my $dochksum = 0;
my $doverify = 0;
my @rangelist = ();
my @rangefils = ();
my @dirtelems = ();
my @listelems = ();
my @verifiles = ();
my @srclist = ();
my $thisos = `uname`;	# Determine this at startup...
my $sanitycount = 1;	# For keeping track of depth during traversal
my $sanityctmax = 20;	# Max depth of standard traversal
my $skipsums = 0;	# During compare optionally only report tree differences
my $verbose = 0;
my $reverse = 0;
my $setflag = "src";
my $dolsc = 0;
my $dothread = 0;
my $defthread = 4;
my $threads = $defthread;	# Last index of Threads to spawn; [Real number of threads to spawn]
my $userthreads = 0;
my $zombies = 0;
$SIG{CHLD} = sub { $zombies++ };
my %present = ();
my @chkfileslist = ();
my $fullstat = 0;
my $seenstat = 0;
my $outfile = "";
my $lincompat = 0;
my @outarray = ();
my $STDOUT = "STDOUT";
my $canskip = 1;

sub reaper {
	my $zombie;
	my %Kid_Status;  # store each exit status
	$zombies = 0;  
	while (($zombie = waitpid(-1, WNOHANG)) != -1) {
		$Kid_Status{$zombie} = $?;
	} 
}

sub OddStat() {
	if (! $seenstat) {
		$seenstat ++;
		$fullstat ++;
	}
}

sub CheckLSC() {
	my $lscbin = `which lsc`;
	chomp $lscbin;
	if (-x "$lscbin") {
		$dolsc = 1;
	}
}

sub CallLSC(@) {
	my @fdata = @_;
	open(PH, "| lsc -b -t list") or die "Failed to call LSC\n";
	for my $lin (@fdata) {
		print PH "$lin\n";
	}
	close(PH);
}

## Some Reference Functions borrowed from lsc:
sub RunLS(;$) {
	my $lsdir = $_[0];
	my $dirpre;
	my @rlsout;
	if (! defined $lsdir) {
		$lsdir = ".";
		$dirpre = "";
	} else {
		$dirpre = "$lsdir/";
	}
	if (! opendir(LSOUT, "$lsdir")) {
		warn "\nWARNING:\nWARNING: Could not open $lsdir: $!\nWARNING:\n";
		if ($fullstat < 248 ) { $fullstat += 8; } # Increment an error status > 248 = unknown num read failures...
		push(@rlsout,"$dirpre");
		return @rlsout;
	}
	while (defined(my $lslin = readdir(LSOUT)) ) {
		chomp($lslin);
		if (($lslin ne '.') && ($lslin ne '..')) {
			push(@rlsout,"${dirpre}${lslin}");
		}
	}
	closedir(LSOUT);
	if (! @rlsout) {
		push(@rlsout,"$dirpre");
	}
	return @rlsout;
}

sub WalkDirs(\@) {	# Traverse directories
	my @dirlist = @_;
	my @walklist = ();
	if ( $#dirlist > 0 ) {	# Sort dir elements here, 'cause we don't anywhere else
		@dirlist = sort(@dirlist)
	}
	for my $delem (@dirlist) {
		if ($delem eq ".") {
			$sanitycount += 1;
			push(@walklist,&ProcessLS(&RunLS()));
			$sanitycount -= 1;
		} else {
			push(my @templist,&RunLS($delem));
			if ( $templist[0] !~ /^\Q$delem\E\/$/) { # Fix Traversal bug when dir name looks like regex (e.g.: /dir/named/c++/file.txt)
				$sanitycount += 1;
				push(@walklist,&ProcessLS(@templist));
				$sanitycount -= 1;
				@templist = ();
			} else {
				push(@walklist,@templist);
			}
		}
	}
	return @walklist;
}

sub ProcessLS(\@) { # Determine element type for provided array (@_), and recurse as appropriate, returning resulting array
	my @direlems = ();
	my @filelems = ();
	my @outputlist = ();
  	if ($sanitycount <= $sanityctmax ) {
		for my $lelem (@_) {	# Separate input list into Files and Dirs (arrays)
			if ($lelem !~ /^$/) {
				if (-d $lelem) { # strip the last '/' before adding dir to array
					if ( -l $lelem) { # Skip Links. # TODO: Command Line Option, print links as file list syntax in output (->)
						if ($verbose) { print STDERR "Warning: Skipping Link to directory: '$lelem'.\n"; }
					} else {
						$lelem =~ s/\/$//g;
						push(@direlems,$lelem);
					}
				} elsif (-f _ ) { # ('_' is cached data from $lelem above)
					push(@filelems,$lelem);
				} else { # Not a file or directory...
						if (-e _ ) { # Special Devices?
							push(@filelems,$lelem);
						} elsif (-l $lelem ) { # lstat can't used cached _ from stat above
							print STDERR "Warning: Link with missing target '$lelem'.\n";
						} else {
							print STDERR "Can not determine element type for '$lelem'.\n";
						}
				}
			}
		} # Now push data to @outputlist 
		if (@direlems) {
			push(@outputlist,&WalkDirs(@direlems));
		}
		if (@filelems) {
			push(@outputlist,@filelems);
		}
	} else { # Stop traversing, and return the list back.  (We could run into issues because we'll chkum directories if we hit this though...)
		print STDERR "Warning: Stopping traversal at depth $sanitycount\n";
		push(@outputlist,@_);
	}
	return(@outputlist);
}

sub RangeCalc($) {	# Return list of frames in a sequence
	my @rvals = ();
	my $inc = 1;
	my @nums = split(/[:-]/,$_[0]);
	my $cnum;
	my $fcnum;
	my $pval;
	if (defined($nums[2])) {
		$inc = $nums[2];
	}
	if (defined($nums[1])) {
		$cnum = $nums[0];
		$pval = length($cnum);
		if ($cnum == $nums[1]) {
			push(@rvals,$cnum);
		} elsif ($inc == 0) {
			die "ERROR: $cnum =/= $nums[1], but Inc is $inc\n";
		} else {
			while ($cnum <= $nums[1]) {
				$fcnum = sprintf("%${pval}.${pval}d",$cnum);
				push(@rvals,$fcnum);
				$cnum += $inc;
			}
		}
	} elsif (defined($nums[0])) {
		push(@rvals,$nums[0]);
	}
	return(@rvals);
}

sub LSCunpack(@) {
	my @packdata = @_;
	my @newlist = ();
	for my $lin (@packdata) {
		if ($lin =~ /([-\w\.\s()\/]*)\[([\d]+[-:,]+[\d:,\-]*[\d]+)\]([-\w\.\s()\/]*)/) {
			my $lscpre = $1;
			my $lscnum = $2;
			my $lscext = $3;
			my @ranges = split(",",$lscnum);
			for my $range (@ranges) {
				my @vals = &RangeCalc($range);
				for my $val (@vals) {
					push(@newlist,"${lscpre}${val}${lscext}");
				}
			}
		} else {
			push(@newlist,$lin);
		}
	}
	return(@newlist);
}

sub GetSum($) { # Get MD5 Sums for specified file
	my $fil = $_[0];
	my $sumcmd = 'md5';
	my ($chksum, @parts);
	if ($thisos =~ /IRIX/ ) { # IRIX doesn't have '-q' option
		$chksum = `$sumcmd "$fil"`;
		@parts = split(/\s+/,$chksum); # Last Field
		$chksum = $parts[$#parts];
	} elsif ($thisos =~ /Linux/ ) { # ...Linux also
		$sumcmd = 'md5sum';
		$chksum = `$sumcmd "$fil"`;
		@parts = split(/\s+/,$chksum);
		$chksum = $parts[0]; # First field
	} elsif ($thisos =~ /CYGWIN_NT/ ) { # ...Cygwin too
		$sumcmd = 'md5sum';
		$chksum = `$sumcmd "$fil"`;
		@parts = split(/\s+/,$chksum);
		$chksum = $parts[0]; # First field
	} else { # FreeBSD is coolest
		$chksum = `$sumcmd -q  "$fil"`;
	}
	chomp $chksum;
	return $chksum;
}

sub DoChkSums(@) { # Return an array or hash with chksums for given files
	my ($dohash,$addpath,@files) = @_;
	my $thischk = "";
	my @returna = ();
	my %returnh = ();
	for my $fil (@files) {
		my $cfil = $fil;
		if ($addpath !~ /^$/) {
			$cfil = "$addpath/$fil";
		}
		$thischk = &GetSum("$cfil");
		if ($verbose) { print STDOUT "ChkSum: $thischk\t$fil\n"; }
		if ($dohash) {
			$returnh{$fil} = $thischk;
		} else {
			if ($reverse) {
				if (($outfile) || ($lincompat)) {
					$thischk = "$thischk  $fil";
				} else {
					$thischk = "$thischk\t$fil";
				}
			} else {
				$thischk = "$fil\t$thischk";
			}
			push(@returna,$thischk);
		}
	}
	if ($dohash) {
		return(%returnh);
	} else {
		return(@returna);
	}
}

sub AllocFrames(@) {
	my $tframes = $_[0];
	if ($threads > $tframes) {
		$threads = $tframes;	# Set threads appropriately
		return 1;
	}
	my $batchval = sprintf("%.0d",($tframes/$threads));
	if (($batchval * $threads) < $tframes) {
		$batchval += 1;
	}
	return $batchval;
}

sub AllocHash(@) { # Populate %outhash based on total frames, and number of threads
	my ($batch,@list) = @_;
	my $idx = 0;
	my $cnt = 1;
	my %outhash = ();
	while (my $fil = shift(@list)) {
		if ($cnt > $batch ) {
			$idx += 1;
			$cnt = 1;
		}
		push(@{ $outhash{$idx} },$fil);
		$cnt += 1;
	}
	return(%outhash);
}

sub ForkSums(@) { # Return an array or hash with chksums for given files, forking for quicker processing.
	my ($dohash,$addpath,@sumdata) = @_;
	my $batch = &AllocFrames($#sumdata + 1);
	my %fils = &AllocHash($batch,@sumdata);
	my @children = (0..${threads}); # Start at zero, so we have one extra dummy thread.
	my @returna = ();
	my %returnh = ();
	if ($verbose) {
		print STDOUT "Called ForkSums()\n";
		print STDOUT "DoHash :$dohash\n";
		print STDOUT "AddPath:'$addpath'\n";
		print STDOUT "Threads:$threads\n";
		print STDOUT "SumData:@sumdata\n";
	}
	for my $c  (@children) {
		pipe(*{$c},CHILDWRITE); # Use a typeglob to store child process file handles.
		if (my $pid = fork) {
			# Parent Process...
		} elsif (defined $pid) {
			if ($c == $threads) { # Exit Only Child Process
				exit 0; # This one is un-trustworthy
			}
			for my $idx (@{ $fils{$c} } ) {
				my $cidx = $idx;
				if ($addpath !~ /^$/) {
					$cidx = "$addpath/$idx";
				}
				my $cres = &GetSum("$cidx");
				if (($reverse) && (! $dohash)) {
					if (($outfile) || ($lincompat)) {
						print CHILDWRITE "$cres  $idx\n";
					} else {
						print CHILDWRITE "$cres\t$idx\n";
					}
				} else {
					print CHILDWRITE "$idx\t$cres\n";
				}
			}
			exit 0;
		} else {
			die "ERROR: fork failed: $!\n";
		}
	}
	for my $c  (@children) { # Gather all the data.
		if ($verbose) {
			print STDOUT "Child:$c\n";
		}
		if ($c != $threads) { # Skip the last [lazy] child, or the while() never exits...
			while (defined(my $data = <$c>)) {
				chomp $data;
				if ($verbose) {
					print STDOUT "Child:$c:$data\n";
				}
				if ($dohash) {
					my @elems = split(/\t/,$data);
					if ($reverse) {
						$returnh{$elems[1]} = $elems[0];
					} else {
						$returnh{$elems[0]} = $elems[1];
					}
				} else {
					push(@returna,$data);
				}
			}
		}
	}
	while ($zombies) {
		if ($verbose) { print STDOUT "Calling Reaper for zombies\n"; }
		&reaper();
	}
	$threads = $defthread;
	if ($userthreads) { # Reset this in case we had to change it in AllocFrames()
		$threads = $userthreads;
	}
	if ($dohash) {
		return(%returnh);
	} else {
		return(@returna);
	}
}

sub ReadFileList($) { # Read file or STDIN contents into array
	my $readfil = $_[0];
	my @rtarray = ();
	my $FH = "STDIN";
	if ($readfil !~ /^-$/) {
		if (! -T $readfil) {
			print STDERR "Warning: $readfil does not appear to be a text file.\n\n";
			return;
		}
		open(FH, "< $readfil") or die "Input ERROR: '$readfil' $!\n";
		$FH = "FH";
	} elsif (-t STDIN ) {
		print STDERR "STDIN: No input found.\n";
		return;
	}
	while (defined(my $lin = <$FH>)) {
		chomp($lin);
		push(@rtarray,$lin);
	}
	if ($readfil !~ /^-$/) {
		close(FH);
	}
	return(@rtarray);
}

sub ReadVHash($) { # Read file or STDIN contents into hash
	my $readfil = $_[0];
	my %rthash = ();	# $fil -> $chksum
	my %rvhash = ();	# (in case: $chksum -> $fil)
	my $colonehash = 1;
	my $coltwohash = 1;
	my $FH = "STDIN";
	if ($readfil !~ /^-$/) {
		if (! -T $readfil) {
			print STDERR "Warning: $readfil does not appear to be a text file.\n\n";
			return;
		}
		open(FH, "< $readfil") or die "Input ERROR: '$readfil' $!\n";
		$FH = "FH";
	} elsif (-t STDIN ) {
		print STDERR "STDIN: No input found.\n";
		return;
	}
	while (defined(my $lin = <$FH>)) {
		chomp($lin);
		my $colone;
		my $coltwo;
		my $skiplin = 0;
		if (($canskip) && ($lin =~ /^#/)) {
			$skiplin = 1;
		} elsif ($lin =~ /([^\t]+)\t(.*)/) { # Tab separations given precedence (could cause issues if filenames contain embedded tabs, however unlikely)
			$colone = $1;
			$coltwo = $2;
		} elsif ($lin =~ /^([a-f0-9]{32})  (.+)$/) { # Special case for Linux md5sum compatible check files
			$colone = $1;
			$coltwo = $2;
		} else { 
			print STDERR "WARNING: Could not detect hash or file name from line:\nWARNING: $lin\nWARNING:\n";
			my @elems = split(/\s+/,$lin);	# Explicit tab separated values, in case of spaces in filenames...
			$colone = $elems[0];
			$coltwo = $elems[1];
		}
		if (! $skiplin) {
			if ($colone !~ /^[a-f0-9]{32}$/) { $colonehash = 0; }
			if ($coltwo !~ /^[a-f0-9]{32}$/) { $coltwohash = 0; }
			if ($reverse) {
				$rthash{$coltwo} = $colone;
				$rvhash{$colone} = $coltwo;
			} else {
				$rthash{$colone} = $coltwo;
				$rvhash{$coltwo} = $colone;
			}
		}
	}
	if ($readfil !~ /^-$/) {
		close(FH);
	}
	if ((($reverse) && ($coltwohash) && (! $colonehash)) || ((! $reverse) && ($colonehash) && (! $coltwohash))) {
		print STDOUT "WARNING: Opposite hash/filename order detected. Reversing input assignment.\n";
		%rthash = %rvhash;
	}
	return(%rthash);
}

sub WriteFile($@) {
	my ($name,@tdata) = @_;
	open(FH, "> $name") or die "Failed to write file $name $!\n";
	for my $lin (@tdata) {
		print FH "$lin\n";
	}
	close(FH);
}

sub CheckExist(@) { # Return array of files present (in source if given)
	# check ranges of @srclist, populating %present, @missing, %srcmissing (counter)
	my ($chksrc,@flist) = @_;
	my @existing = ();
	my $mcount = 0;
	my @missing = ();
	my $src = "$chksrc/";
	if ($chksrc =~ /^\/\/NONE\/\/$/) {
		$src = "";
	}
	for my $fil (@flist) {
		$fil =~ s/^\s+|\s+$//g;	# lsc (for example) pads output, so remove any padding...
		if ($verbose) { print STDOUT "Checking File: '${src}${fil}' ... "; }
		if (-f "${src}${fil}") { 
			push(@existing,$fil);
			if ($verbose) { print STDOUT " Exists\n"; }
		} elsif (-d "${src}${fil}") { 
			if ($verbose) { print STDOUT "Skipping. (Directory)\n"; }
		} else {
			if ($verbose) { print STDOUT "Missing.\n"; }
			push(@missing, $fil);
			$mcount ++;
		}
	}
	if (@missing) {
		&OddStat;
		if ($verbose) { print STDOUT "No Missing files found in source $chksrc \n"; }
		if ($dolsc) {
			print STDERR "Missing files from $chksrc ($mcount):\n";
			&CallLSC(@missing);
		} else {
			print STDERR "Missing files from $chksrc ($mcount):\t@missing\n";
		}
	}
	return(@existing);
}

sub StripDirs(\@) {
	my @aray = @_;
	my @return = ();
	for my $val (@aray) {
		if ($val !~ /\/$/) { # We're not chksum'ing directories
			push(@return,$val);
		}
	}
	if ($verbose) {
		for my $cl (@return) {
			print STDOUT "(StripDirs) ${cl}\n";
		}
	}
	return(@return);
}

sub CleanList(\$\@) {
	my $cnam = shift @_;
	$cnam .= "/";
	my @aray = @_;
	my @return = ();
	for my $val (@aray) {
		$val =~ s/^$cnam//;
		if ($val !~ /\/$/) { # We're not chksum'ing directories
			push(@return,$val);
		}
	}
	if ($verbose) {
		for my $cl (@return) {
			print STDOUT "(CleanList) ${cnam}${cl}\n";
		}
	}
	return(@return);
}

sub CompareArrays(\$\$\@\@) {
	my ($s1,$s2,$a1,$a2) = @_;
	my @common = ();
	my %onlyone = ();
	my %onlytwo = ();
	my %fulltwo = ();
	my $congruence = 1;
	for my $a (@$a1) {
		$onlyone{$a} = $a;
	}
	for my $b (@$a2) {
		$fulltwo{$b} = $b;
		if (defined ($onlyone{$b})) {
			push (@common,$b);
			delete $onlyone{$b};
		} else {
			$onlytwo{$b} = $b;
			$congruence = 0;
		}
	}
	for my $c (@$a1) {
		if (! defined($fulltwo{$c})) {
			$congruence = 0;
		}
	}
	return($congruence,\%onlyone,\%onlytwo,\@common);
}

sub ChkSumCompare(@) {
	my ($src1,$src2,@common) = @_;
	my %mdhash = ();
	my @diffsums = ();
	my $congruence = 1;
	if ($dothread) {
		%{ $mdhash{$src1} } = &ForkSums(1,$src1,@common);
		%{ $mdhash{$src2} } = &ForkSums(1,$src2,@common);
	} else {
		%{ $mdhash{$src1} } = &DoChkSums(1,$src1,@common);
		%{ $mdhash{$src2} } = &DoChkSums(1,$src2,@common);
	}
	for my $fil (@common) {
		if ($mdhash{$src1}{$fil} ne $mdhash{$src2}{$fil}) {
			push(@diffsums,$fil);
			$congruence = 0;
		}
	}
	return($congruence,\@diffsums,\%mdhash);
}

sub CleanDups(@) {	# Remove duplicate paths in Source Path Array
	my @toclean = @_;
	my %seen = ();
	my @output = ();
	for my $cdi (@toclean) {
		$cdi =~ s/\/$//;	# Remove trailing slashes on paths
		$cdi =~ s/^\.\///;	# Remove './' on path elements
		if (defined($seen{$cdi})) {
			print STDERR "Removing duplicate instance of '$cdi' in source path set.\n";
		} else {
			$seen{$cdi} = $cdi;
			push(@output,$cdi);
		}
	}
	return(@output);
}

sub OutPrint(@) {
	if ($outfile) {
		push(@outarray,@_);
	} else { 
		print STDOUT "@_\n";
	}
}

sub CleanExit($) {
	if ($outfile) {
		&WriteFile($outfile,@outarray);
	}
	exit $_[0];
}

sub OptPrint(@) {
	my @opts = @_;
	my $fmt = "\t%-14s %s\n";
	printf STDOUT $fmt,@opts;
}

sub ShowVersion() {
	print STDOUT "\n$bfil: -\tFile tree checksum comparison tool\n\nVersion $Revision\n\n";
	exit 0;
}

sub ShowHelp() { # Usage information:
	my @bpath = split /\//,$0;
	my $bfil = pop(@bpath);
	print STDOUT "\nUsage: $bfil [sources] [chksums] [ranges] [lists]\n";
	&OptPrint("-src \$src","Specify src as a source directory");
	&OptPrint("-r \$range","Specify named range for checksums comparison");
	&OptPrint("-rl \$ranges..","Specify multiple named range for checksums comparison (rng read mode)");
	&OptPrint("-rf \$list","Specify file \$list (containing list of ranges) for checksums comparison");
	&OptPrint("-l \$list","Specify file \$list (containing list of files) for checksums comparison");
	&OptPrint("-dl \$list","Specify file \$list (containing list of directories) to traverse for checksums comparison");
	&OptPrint("-ll \$lists..","Specify multiple file \$lists for checksum comparison (lst read mode)");
	&OptPrint("-v \$fil","Verify sources with checksums from \$fil (implies Verify Op mode)");
	&OptPrint("-vl \$files..","Specify multiple \$fils for source checksums (vfy read mode)");
	&OptPrint("-c","Create chksums for contents of sources (Checksum Op Mode)");
	&OptPrint("-t [\$num]","Spawn [\$num] (or, 4 if unspecifed) threads for checksum processing");
	if ($_[0]) {
		&OptPrint("-d","Print debugging output");
		&OptPrint("","Operation Modes Compare, Verify, and Checksum [only] are mutually exlusive.");
		&OptPrint("-cmp","Comparison Mode.  Script will compare data from two sources.");
		&OptPrint("-vfy","Verify Mode.  Script will compare data with source checksums.");
		&OptPrint("-chk","Checksum Mode.  Script will output checksums from sources.");
		&OptPrint("","Read Modes can be one of 'src' [default], 'rng', 'lst', 'vfy'.");
		&OptPrint("-sw \$val","Switch read mode for future unflagged command line items to \$val.");
		&OptPrint("-flag \$val","Same as -sw.");
		&OptPrint("","Remaining bare args are taken to be:");
		&OptPrint("","  src - Source directories for comaparison.");
		&OptPrint("","  rng - Range lists for files to check.");
		&OptPrint("","  lst - List Files (containing file names to check).");
		&OptPrint("","  vfy - Verification files (containing checksums) to compare with source data.");
		&OptPrint("-rev","Reverse order of checksum command output such that checksum values are listed first");
		&OptPrint("-lnx","Output Linux Compatible md5sum check file format data");
		&OptPrint("-nocomm","Don't skip lines appearing to be comments in provided checksum data");
		&OptPrint("-s","Skip generating checksums (source tree comparison only, [for degugging])");
		&OptPrint("-o \$fil","Specify file \$fil to write chksum output.");
		&OptPrint("[-]-version","Display Revision number, and exit");
		&OptPrint("[-]-license","Display Software License, and exit");
		&OptPrint("[-]-h[elp]","Display [this]/brief help text");
	} else {
		&OptPrint("[-]-h","Display [verbose]/this help text");
	}
	print STDOUT "\n\n";
	exit 0;
}

sub ShowLicense() { # Copyright / License (Limit to 80 column output)
	print STDOUT "Copyright © 2010-2014 Victor E. Vaile, IV. All Rights Reserved.\n\n";
	print STDOUT "Redistribution and use in source and binary forms, with or without modification,\n";
	print STDOUT "are permitted provided that the following conditions are met:\n\n";
	print STDOUT "1. Redistributions of source code must retain the above copyright notice, this\n";
	print STDOUT "   list of conditions and the following disclaimer.\n\n";
	print STDOUT "2. Redistributions in binary form must reproduce the above copyright notice,\n";
	print STDOUT "   this list of conditions and the following disclaimer in the documentation\n";
	print STDOUT "   and/or other materials provided with the distribution.\n\n";
	print STDOUT "3. The name of the author may not be used to endorse or promote products derived\n";
	print STDOUT "   from this software without specific prior written permission.\n\n";
	print STDOUT "THIS SOFTWARE IS PROVIDED BY THE AUTHOR \"AS IS\" AND ANY EXPRESS OR IMPLIED\n";
	print STDOUT "WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF\n";
	print STDOUT "MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT\n";
	print STDOUT "SHALL THE AUTHOR BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,\n";
	print STDOUT "EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT\n";
	print STDOUT "OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS\n";
	print STDOUT "INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN\n";
	print STDOUT "CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING\n";
	print STDOUT "IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY\n";
	print STDOUT "OF SUCH DAMAGE.\n\n";
	print STDOUT "* That being said, if you find a bug, feel free to report it to the author. :)\n\n";
	exit 0;
}

sub ParseCommandLine() {
	if (defined($ARGV[0])) {
		while (defined($ARGV[0]) && "$ARGV[0]" !~ /^$/ ) {
			if ($ARGV[0] =~ /^-(-){0,1}[Ss][Rr][Cc]$/ ) {
				shift(@ARGV);
				$setflag="src";
				if ((defined($ARGV[0])) && ("$ARGV[0]" !~ /^$/ )) {
					push(@srclist,$ARGV[0]);
					shift(@ARGV);
				} else {
					print STDERR "src: cannot be an empty string\n";
				}
			} elsif ($ARGV[0] =~ /^-(-){0,1}[Rr]([Aa][Nn][Gg][Ee]){0,1}$/ ) {
				shift(@ARGV);
				if ((defined($ARGV[0])) && ("$ARGV[0]" !~ /^$/ )) {
					push(@rangelist,$ARGV[0]);
				} else {
					print STDERR "r[ange]: cannot be an empty string\n";
				}
				shift(@ARGV);
			} elsif ($ARGV[0] =~ /^-(-){0,1}[Rr][Ll]$/ ) {
				shift(@ARGV);
				$setflag="rng";
			} elsif ($ARGV[0] =~ /^-(-){0,1}[Rr][Ff]([Ii][Ll][Ee]){0,1}$/ ) {
				shift(@ARGV);
				if ((defined($ARGV[0])) && ("$ARGV[0]" !~ /^$/ )) {
					push(@rangefils,$ARGV[0]);
				} else {
					print STDERR "rf[ile]: cannot be an empty string\n";
				}
				shift(@ARGV);
			} elsif ($ARGV[0] =~ /^-(-){0,1}[Dd]([Ii][Rr])?[Ll]([Ii][Ss][Tt]){0,1}$/ ) {
				shift(@ARGV);
				if ((defined($ARGV[0])) && ("$ARGV[0]" !~ /^$/ )) {
					push(@dirtelems,$ARGV[0]);
				} else {
					print STDERR "d[ir]l[ist]: cannot be an empty string\n";
				}
				shift(@ARGV);
			} elsif ($ARGV[0] =~ /^-(-){0,1}[Ll]([Ii][Ss][Tt]){0,1}$/ ) {
				shift(@ARGV);
				if ((defined($ARGV[0])) && ("$ARGV[0]" !~ /^$/ )) {
					push(@listelems,$ARGV[0]);
				} else {
					print STDERR "l[ist]: cannot be an empty string\n";
				}
				shift(@ARGV);
			} elsif ($ARGV[0] =~ /^-(-){0,1}[Ll][Ll]$/ ) {
				shift(@ARGV);
				$setflag="lst";
			} elsif ($ARGV[0] =~ /^-(-){0,1}[Vv]([Ff][Yy]|[Ee][Rr][Ii][Ff][Yy]){0,1}$/ ) {
				$dochksum = 0;
				$doverify = 1;
				shift(@ARGV);
				if ((defined($ARGV[0])) && ("$ARGV[0]" !~ /^$/ )) {
					push(@verifiles,$ARGV[0]);
				} else {
					print STDERR "Verification file cannot be an empty string\n";
				}
				shift(@ARGV);
			} elsif ($ARGV[0] =~ /^-(-){0,1}[Vv][Ll]$/ ) {
				$dochksum = 0;
				$doverify = 1;
				shift(@ARGV);
				$setflag="vfy";
			} elsif ($ARGV[0] =~ /^-(-){0,1}[Cc]([Hh][Kk]([Ss][Uu][Mm]){0,1}){0,1}$/ ) {
				$dochksum = 1;
				$doverify = 0;
				shift(@ARGV);
			} elsif ($ARGV[0] =~ /^-(-){0,1}[Tt]([Hh][Rr][Ee][Aa][Dd][Ss]){0,1}$/ ) {
				shift(@ARGV);
				$dothread = 1;
				if ((defined($ARGV[0])) && ("$ARGV[0]" =~ /^[0-9]+$/)) {
					if ($ARGV[0] > 1) {
						$threads = $ARGV[0];
						$userthreads = $threads;
						print STDOUT "Using $threads threads for checksum processing.\n";
					} else {
						$dothread = 0;
					}
					shift(@ARGV);
				} # Only shift (^) if we got a valid [optional] value for threads.
			} elsif ($ARGV[0] =~ /^-(-){0,1}([Dd]([Ee][Bb][Uu][Gg]){0,1}|[Vv][Ee][Rr][Bb][Oo][Ss][Ee])$/ ) {
				$verbose = 1; # Debug
				shift(@ARGV);
			} elsif ($ARGV[0] =~ /^-(-){0,1}([Cc][Mm][Pp]|[Cc][Oo][Mm][Pp][Aa][Rr][Ee])$/ ) {
				$dochksum = 0;
				$doverify = 0;
				shift(@ARGV);
			} elsif ($ARGV[0] =~ /^-(-){0,1}([Ss][Ww]|[Ff][Ll][Aa][Gg])$/ ) {
				shift(@ARGV);
				if ((defined($ARGV[0])) && ("$ARGV[0]" =~ /^([Ss][Rr][Cc]|[Rr][Nn][Gg]|[Ll][Ss][Tt]|[Vv][Ff][Yy])$/ )) {
					$setflag = $ARGV[0];
				} else {
					print STDERR "sw: '$ARGV[0]' is not a valid flag\n";
				}
				shift(@ARGV);
			} elsif ($ARGV[0] =~ /^-(-){0,1}[Rr][Ee][Vv]([Ee][Rr][Ss][Ee]){0,1}$/ ) {
				$reverse = 1;
				shift(@ARGV);
			} elsif ($ARGV[0] =~ /^--?(lnx|lincompat)$/i) {
				$reverse = 1;
				$lincompat = 1;
				shift(@ARGV);
			} elsif ($ARGV[0] =~ /^--?nocomm$/i) {
				$canskip = 0;
				shift(@ARGV);
			} elsif ($ARGV[0] =~ /^-(-){0,1}[Ss]([Kk][Ii][Pp][Ss][Uu][Mm][Ss]){0,1}$/ ) {
				$skipsums = 1;
				shift(@ARGV);
			} elsif ($ARGV[0] =~ /^-[Oo]$/) {
				shift(@ARGV);
				if (defined($ARGV[0]) && "$ARGV[0]" !~ /^(|-+.*)$/ ) {
					$outfile = $ARGV[0];
					shift(@ARGV);
				} else {
					die("-o: No output file specified.");
				}
			} elsif ($ARGV[0] =~ /^-(-){0,1}([Hh]|[Hh][Ee][Ll][Pp])$/ ) {
				if (($ARGV[0] =~ /--/) || ($ARGV[0] =~ /[Ee][Ll][Pp]/)) {
					&ShowHelp("Undoc");
				} else {
					&ShowHelp();
				}
				shift(@ARGV);
			} elsif ($ARGV[0] =~ /^--?ver(sion)?$/) {
				shift(@ARGV);
				&ShowVersion();
			} elsif ($ARGV[0] =~ /^--?lic(ense)?$/) {
				shift(@ARGV);
				&ShowLicense();
			} else { # push to the array corresponding to set flag ( src rng lst vfy )
				if ($verbose) { print STDOUT "Adding $ARGV[0] to $setflag list\n"; }
				if ($setflag =~ /[Rr][Nn][Gg]/) {
					push(@rangelist,$ARGV[0]);
				} elsif ($setflag =~ /[Ll][Ss][Tt]/) {
					push(@listelems,$ARGV[0]);
				} elsif ($setflag =~ /[Vv][Ff][Yy]/) {
					push(@verifiles,$ARGV[0]);
				} else { # src
					push(@srclist,$ARGV[0]);
				}
				shift(@ARGV);
			}
		}
	}
}

# main()
&ParseCommandLine;
&CheckLSC;

for my $listarray (\@srclist,\@listelems,\@rangelist,\@verifiles) {
	if (@$listarray) { @$listarray = &CleanDups(@$listarray); }
}

if ($dochksum) {	# Return Checksum list (or file, if specified) for (ranges if specified) in all sources (if specified, else explicit ranges)
	my @presentlist = ();
	my @chkarray = ();
	if (@dirtelems) {
		for my $dlfil (@dirtelems) {
			push(@srclist,&ReadFileList($dlfil));
		}
	}
	if (@listelems) {
		for my $lefil (@listelems) {
			push(@chkfileslist,&ReadFileList($lefil));
		}
	}
	if (@rangefils) {
		for my $rgfil (@rangefils) {
			push(@rangelist,&ReadFileList($rgfil));
		}
	}
	if (@rangelist) {
		for my $range (@rangelist) { # Verify ranges exist in both dirs
			push(@chkfileslist,&LSCunpack($range));
		}
	}
	if (@chkfileslist) { # Verify which of the specified files exist in the various src dirs
		if (@srclist) {
			for my $src (@srclist) { # check ranges of @srclist, populating %present
				push(@{ $present{$src} },&CheckExist($src,@chkfileslist));
			}
		} else {
			@presentlist = &CheckExist("//NONE//",@chkfileslist);
		}
	} else { # Just populate %present hash with full trees from @srclist
		if (@srclist) {
			for my $list (@srclist) { # Enumerate files in directories of @srclist, into named arrays (* $list gets changed by ProcessLS() removing trailing '/'.)
				if (-d $list) {
					@{ $present{$list}} = &ProcessLS($list);
					@{ $present{$list}} = &CleanList($list,@{ $present{$list}});
				} else { # We'll handle standalone files for this function
					@{ $present{$list}} = ($list);
				}
			}
		} else {
			die "No Sources to CheckSum.\n";
		}
	}
	if ($skipsums) { &CleanExit($fullstat); } # Bail here for debug testing...
	for my $psrc (sort(keys(%present))) {
		if (! -d $psrc) { # Single file, push to list, and move on (ignoring array for this hash value)
			push(@presentlist,"$psrc");
		} else {
			if ($#{$present{$psrc}}) { # Source contains more than one element
				for my $psitem (@{$present{$psrc}}) {
					push(@presentlist,"${psrc}/$psitem");
				}
			} elsif ((${$present{$psrc}}[0] !~ /^$/) || ($thisos =~ /FreeBSD/)) { # Source contains data (not empty dir) or BSD
				push(@presentlist,"${psrc}/${$present{$psrc}}[0]");
			} else { # (Returned single empty element) It's an empty directory explicitly specified on the command line.
				print STDOUT "ERROR: ${psrc}/: This OS cannot md5sum a directory.\n";
			}
		}
	}
	if ($dothread) {
		@chkarray = &ForkSums(0,"",@presentlist);
	} else {
		@chkarray = &DoChkSums(0,"",@presentlist);
	}
	for my $lin (@chkarray) { &OutPrint("$lin"); }
	&CleanExit($fullstat);
} elsif ($doverify ) {
	my %vfyhash = ();
	my %vcompare = ();
	my %tcompare = ();
	my @srcpresent = ();
	my %chkdiffs = ();
	my $incongruent = 0;
	if (! @verifiles) { die "Cannot Verify without source checksums.\n"; }
	for my $vf (@verifiles) {
		my %tmphash = &ReadVHash($vf);
		for my $key (keys(%tmphash)) {
			if (defined($vfyhash{$key})) {
				&OutPrint("WARNING: Duplicate chksum value for '$key'.");
				if ($vfyhash{$key} ne $tmphash{$key}) {
					&OutPrint("\tOverwriting:\n\tOld: $vfyhash{$key} New:$tmphash{$key}");
				}
			}
			$vfyhash{$key} = $tmphash{$key};
		}
	}
	if (@srclist) {
		my $found = 0;
		for my $src (@srclist) {
			@srcpresent = &CheckExist($src,keys(%vfyhash));
			for my $presitem (@srcpresent) { # Add hash values for present items in this src
				$vcompare{"$src/$presitem"} = $vfyhash{$presitem};
				$found += 1;
			}
		}
		if (! $found) { 
			print STDERR "WARNING: No valid source files found.\n";
			$fullstat += 1;
		}
	} else {
		@srcpresent = &CheckExist("//NONE//",keys(%vfyhash));
		for my $presitem (@srcpresent) { # Add hash values for present items in this src
			$vcompare{$presitem} = $vfyhash{$presitem};
		}
		if (! @srcpresent) { 
			print STDERR "WARNING: No valid source files found.\n";
			$fullstat += 1;
		}
	}
	if ($skipsums) { &CleanExit($fullstat); } # Bail here for debug testing...
	if ($dothread) {
		%tcompare = &ForkSums(1,"",keys(%vcompare));
	} else {
		%tcompare = &DoChkSums(1,"",keys(%vcompare));
	}
	for my $exstfil (keys(%vcompare)) {
		if ($tcompare{$exstfil} ne $vcompare{$exstfil}) {
			$chkdiffs{$exstfil} = $tcompare{$exstfil};
			$incongruent += 1;
		}
	}
	if ($incongruent) {
		for my $dif (keys(%chkdiffs)) { # Display MD5 Differences 
			&OutPrint("$dif:\tVerify String $vcompare{$dif}\tActual $chkdiffs{$dif}");
			&OddStat;
		}
	} else {
		if ($fullstat) { &OutPrint("ERRORS Detected"); }
		&OutPrint("All compared files are the same");
	}
	&CleanExit($fullstat);
} else {
	if (! @srclist) { die "No sources specified for comparison.\n"; }
	my $same;
	my $h1;
	my $h2;
	my $com;
	if ($srclist[2]) {
		print STDERR "WARNING: Received multiple source specifications.  Only Comparing first two sources ('$srclist[0]', '$srclist[1]').\n\n";
		@srclist = ($srclist[0], $srclist[1]);
	}
	if (@listelems) {
		for my $lefil (@listelems) {
			push(@chkfileslist,&ReadFileList($lefil));
		}
	}
	if (@rangefils) {
		for my $rgfil (@rangefils) {
			push(@rangelist,&ReadFileList($rgfil));
		}
	}
	if (@rangelist) {
		for my $range (@rangelist) { # Verify ranges exist in both dirs
			push(@chkfileslist,&LSCunpack($range));
		}
	}
	if (@chkfileslist) { # Verify specified files exist in both dirs
		for my $src (@srclist) { # check ranges of @srclist, populating %present
			push(@{ $present{$src} },&CheckExist($src,@chkfileslist));
		}
		if (!$srclist[1]) { die "ERROR: Cannot make comparison with only one source.  Exiting.\n"; }
		($same,$h1,$h2,$com) = &CompareArrays(@srclist,\@{ $present{$srclist[0]}},\@{ $present{$srclist[1]}}); # Used for @common array
	} else {
		for my $list (@srclist) { # Enumerate files in directories of @srclist, into named arrays (* $list gets changed by ProcessLS() removing trailing '/'.)
			@{ $present{$list}} = &ProcessLS($list);
			@{ $present{$list}} = &CleanList($list,@{ $present{$list}});
		} # Now, compare the resulting arrays, populating unique src hashes, and @common array
		if (!$srclist[1]) { die "ERROR: Cannot make comparison with only one source.  Exiting.\n"; }
		($same,$h1,$h2,$com) = &CompareArrays(@srclist,\@{ $present{$srclist[0]}},\@{ $present{$srclist[1]}});
		if ($same) { # At least present files are the same for both sources...
			&OutPrint("Source files in $srclist[0] and $srclist[1] are the same.");
		} else { # Report any missing files
			my @smissing = ();
			&OutPrint("Source files in $srclist[0] and $srclist[1] differ.");
			&OddStat;
			for my $key (sort keys(%$h1)) {
				push(@smissing,$key);
			}
			if (@smissing) {
				if ($dolsc) {
					&OutPrint("Only $srclist[0]:");
					&CallLSC(@smissing);
				} else {
					&OutPrint("Only $srclist[0]: @smissing");
				}
			}
			@smissing = ();
			for my $key (sort keys(%$h2)) {
				push(@smissing,$key);
			}
			if (@smissing) {
				if ($dolsc) {
					&OutPrint("Only $srclist[1]:");
					&CallLSC(@smissing);
				} else {
					&OutPrint("Only $srclist[1]: @smissing");
				}
			}
			if ($verbose) { for my $com (@$com) {&OutPrint("Common: $com"); } }
		} # chksum @common in $srclist[0] and $srclist[1] to %ckhash
	}
	if ($skipsums) { &CleanExit($fullstat);} # Bail here for debug testing...
	my ($cong,$diffs,$ckhash) = &ChkSumCompare(@srclist,@$com);
	if ($cong) { # Report any hash differences
		&OutPrint("All compared files are the same");
	} else {
		&OutPrint("The following files had differences:");
		&OddStat;
		for my $dif (@$diffs) {
			&OutPrint("$dif:\t$srclist[0]: $$ckhash{$srclist[0]}{$dif} $srclist[1]: $$ckhash{$srclist[1]}{$dif}");
		}
	}
}

&CleanExit($fullstat);

