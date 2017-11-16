#!/usr/bin/perl -w

my $Revision = '1.16';
# Process tree display utility
# Created by Victor E. Vaile, IV on 20060802
# 1.00 20060802	Initial Version
# 1.01 20060803	Added %myppid has to report parent of initial 
# 		user defined process
# 1.02 20060927	Added space between tree structure tokens and pid
# 		Changed tree structure for parents with only one
# 		or multiple child processes
# 		Unified process for user and script defined start pids
# 1.03 20080228	Added variables for Darwin (Mac OS X)
# 1.10 20120609 Changed vars, subs to be properly declared, called
#		Added BackTrack() sub to return parent pids up to 
#		system start pid for specified processes
#		Changed boolean values to boolean, All caps vars to lower
# 1.11 20120617	Added PreWalk() and MultiPrune() for producing tree with
#		more than one branch of interest (multiple pids identified)
#		Added ColorString() to highlight string as matched from
#		command line argument
#		Default behavior for string match is to not match current 
#		process unless it is the only process for which the command
#		matches the given string
#		Changed GetProcesses() to match strings and push to @pidlist
#		Main() tests @pidlist, then populates %mandatory, defines
#		value for $startpid, applies colors to pids, strings as needed
#		Changed to standard ShowHelp() ShowVersion() ParseCommandLine()
#		Added options for specifying pid, body, string highlight colors
#		Added functionality to match multiple strings
#		Changed -s to look for explicit string (so a number can be used)
# 1.12 20120621	Var $startpid now defined within GetProcesses(), except that on 
#		Linux systems, it's set to 1 so kthreads will not fill output
#		Default behavior for single pid on cmd line is to call BackTrack()
#		Added flags for verbose (Linux kthreads) and debug (internal)
#		Cleaned vars like @strmatches, and superflous colors in %clrs hash
#		ListChild() prints error but does not exit if user req pid invalid
#		Warn on PreWalk() for possible multiple bad user suppplied pids
#		Commented 'never should' blocks.  String search args more lenient 
#		GetProcesses() now filters header instead of pipe to grep
# 1.13 20120628	Changed default behavior to look for strings on command line
#		If a pid and string given on cmd line match a given process
#		it will be highlighted for pid body and strings as well
#		Self match on strings will now highlight matched strings
#		Help text updated for changes, and color explanation
# 1.14 20130414	Added more process pid tree info in debugging output
#		Added missing case insensitivity processing updated license
# 1.15 20150806	Added support for Cygwin ps, which required additional processing
#		because the output mode '-o' is not supported like the others
#		Additionally, the field order was different so the other outputs
#		have been changed to match for easier processing.  Lastly,
#		The cygwin process has a pid 1 that doesn't exist, so it's added
#		during processing of the title line.
#		Changed split for output to use /\s+/, instead of explicit " ".
# 1.15 20150828	Fixed comparison bug: Swapped out binding operator for comparison
#		operator in PID PPID comparison test
#		Added option to specify file for input


use strict 'vars';
use strict 'subs';

my $spc = "";
my $uname = `uname`;
my $prune = 0;
my $pwprune = 0;
my $startpid; # Should theoretically always be zero...
my $walkback = 1;
my $dostrings = 1;
my $flaggedme = 0;
my @strtests = ();
my %matchhash = ();
my %flagdhash = ();
my $notthis = 1;
my $nochildren = 0;
my $pscmd = "ps -axwwo user,pid,ppid,command";
my $multiprune = 0;
my %myppid = ();
my %body = ();
my %mandatory = ();
my %cpids = ();
my $docolors = 1;
my @pidlist = ();
my %poi = ();
my $mi = "";
my $allcolor = 0;
my $verbose = 0;
my $debug = 0;
my $esc = "[";
my %clrs = (
	"none"    => "${esc}0m",
	"black"   => "${esc}30m",
	"red"     => "${esc}31m",
	"green"   => "${esc}32m",
	"yellow"  => "${esc}33m",
	"blue"    => "${esc}34m",
	"magenta" => "${esc}35m",
	"cyan"    => "${esc}36m",
	"white"   => "${esc}37m",
	"grey"          => "${esc}1;30m",
	"brightred"     => "${esc}1;31m",
	"brightgreen"   => "${esc}1;32m",
	"brightyellow"  => "${esc}1;33m",
	"brightblue"    => "${esc}1;34m",
	"brightmagenta" => "${esc}1;35m",
	"brightcyan"    => "${esc}1;36m",
	"brightwhite"   => "${esc}1;37m",
	);
my $pclr = ${clrs}{"yellow"};
my $bclr = ${clrs}{"white"};
my $sclr = ${clrs}{"brightgreen"};
my $eclr = ${clrs}{"none"};

if ($uname =~ /IRIX(:?64)?/) {
	$pscmd = "ps -eo user,pid,ppid,args";
} elsif ($uname =~ /Linux/) {
	$pscmd = "ps axwwo user,pid,ppid,command";
} elsif ($uname =~ /Darwin/) {
	$pscmd = "ps -axwwo user,pid,ppid,command";
} elsif ($uname =~ /CYGWIN/) { # Cygwin output need a bit of massaging
	$pscmd = 'ps -efW | awk \'{if($5 !~ /(:|STIME)/){$6=""}$4=$5="";print $0}\'';
}

sub BackTrack($) {
	my $btpid = $_[0];
	my @grandpids = ();
	push(@grandpids,$btpid);
	while (defined($myppid{$btpid})) {
		push(@grandpids,$myppid{$btpid});
		$btpid = $myppid{$btpid};
	}
	@grandpids = reverse(@grandpids);
	return @grandpids;
}

sub ColorString($) {
	my $clrpid = $_[0];
	my $cpstr = $body{$clrpid};
	$cpstr =~ s/^${clrpid}/${pclr}${clrpid}${eclr}/; # Color the pid first
	for my $strmatch (keys(%matchhash)) { # Now string matches
		if (($allcolor)  || (defined($poi{$clrpid}))) { # pid is explicit match (cmdline) or we're coloring body for all strings
			$cpstr =~ s/\Q$strmatch\E/${eclr}${sclr}${strmatch}${eclr}${bclr}/g;
		} else { # Just coloring matching bits
			$cpstr =~ s/\Q$strmatch\E/${sclr}${strmatch}${eclr}/g;
		}
	}
	if (($allcolor) || (defined($poi{$clrpid}))) { # pid is cmdline match, or we're coloring allbodies
	 	$cpstr =~ s/^\Q${pclr}${clrpid}${eclr}\E/${pclr}${clrpid}${eclr}${bclr}/; # Color the pid first
	 	$cpstr .= ${eclr};
	}
	return $cpstr;
}

sub ListChild($) {
	my $prnlin = "";
	if ($_[0] == "$startpid" ) {
		if (defined($myppid{$_[0]})) { # Don't bother looking if no parent data is defined.
			if (defined($body{$myppid{$_[0]}})) {
				if ($walkback) { # Display information for parents tree backward...
					my $didone = 0;
					for my $wbp (&BackTrack($_[0])) { # This could potentially make a very long $prnlin value...
						if (defined($body{$wbp})) {
							if ($didone) {
								$prnlin .= "${spc}\\_ $body{$wbp}\n";
								$spc .= "  ";
							} else {
								$didone = 1;
								$prnlin .= "${spc}$body{$wbp}\n";
								$spc .= " ";
							}
						} else { # Should never arrive here as GetProcesses() already adds a body to core system kernel process
							print STDERR "ERROR: Failed to find information for pid $wbp\n";
						}
					}
					$spc =~ s/..$//g; # Tidy up spacing for remaining tree walking (forwards)
				} else { # Just display Parents process info
					$spc = " ";
					$prnlin = "$body{$myppid{$_[0]}}\n";
					$prnlin .= "$spc\\_ $body{$_[0]}\n";
				}
			} else { # Nothing above current pid
				$prnlin = "$spc  $body{$_[0]}\n";
			}
		} else {
			if ($body{$_[0]}) {
				$prnlin = "$spc  $body{$_[0]}\n";
			}
		}
	} else {
		$prnlin = "$spc\\_ $body{$_[0]}\n";
	}
	if ($body{$_[0]}) {
		print STDOUT "$prnlin";
	} else {
		print STDOUT "Error: '$_[0]': No such process.\n";
	}
}

sub MultiPrune(@) {
	my @inlist = @_;
	my @outlist = ();
	for my $li (@inlist) {
		if (defined($mandatory{$li})) {
			push(@outlist,$li);
		}
	}
	return @outlist;
}

sub ProcessChild($) {
	my $test = $_[0];
	&ListChild($test);
	if ($multiprune) { # Don't  list non-mandatory pids
		@{$test} = &MultiPrune(@{$test});
	}
	my $glong = 1;
	my $sln;
	if (! @$test[1]) {
		$glong = 0;
	}
	while(@$test[0]) {
		my $pre = $spc;
		if (@$test[1]) { # Still more to come after this child
			$spc = "${pre}  |";
			$sln = 3;
		} else {
			if ($glong) { # Last child of a list of more than one
				$spc = "${pre}   ";
				$sln = 3;
			} else { # Only child
				$spc = "${pre}  ";
				$sln = 2;
			}
		}
		my $testchild = shift(@$test);
		if ($nochildren && ! $multiprune) { # If we're doing multiprune, trimming must be done elsewhere
			$prune += 1;
		}
		if ($prune < 2 ) {
			&ProcessChild($testchild);
		}
		if ($nochildren && ! $multiprune) {
			$prune -= 1;
		}
		if ( $sln != 2 ) {
			$spc =~ s/...$//g;
		} else {
			$spc =~ s/..$//g;
		}
	}
}

sub PreWalk($) { # Populate %mandatory hash for MultiPrune
	my $pwpid = $_[0];
	if (! defined $body{$pwpid}) { # Should only get here if cmd line supplies invalid pid.
		print STDOUT "Warning: '$pwpid': No such process.\n";
		return;
	}
	$mandatory{$pwpid} = $pwpid;
	for my $gpid (&BackTrack($pwpid)) {
		if (! defined $mandatory{$gpid}) {
			if ($debug) { print STDOUT "Mandatory: $gpid\n"; }
		}
		$mandatory{$gpid} = $gpid;
	}
	for my $testchpid (@$pwpid) {
		if ($nochildren) {
			$pwprune += 1;
		}
		if ($pwprune < 2 ) {
			&PreWalk($testchpid);
		}
		if ($nochildren) {
			$pwprune -= 1;
		}
	}
}

sub GetProcesses() {
	if ($debug) { print STDOUT "Running $pscmd\n"; }
	my @pidslist = ();
	open(DATA, "$pscmd |" );
	while(defined(my $lin = <DATA>)) {
		chomp $lin;
		if ($lin =~ /PPID/) {
			if ($uname =~ /CYGWIN/) { # Fake a pid 1 line for cygwin
				$lin = "Cygwin 1 0 Cygwin Psuedo-Thread";
			} else {
				next;
			}
		}
		my @linvars = split(/\s+/,$lin);
		my $user = shift(@linvars);
		my $pid = shift(@linvars);
		my $ppid = shift(@linvars);
		my $cmd = shift(@linvars);
		while ($linvars[0]) {
			$cmd .= " ";
			$cmd .= shift(@linvars);
		}
		push(@pidslist,$pid);
		if ($dostrings) {
			for my $tstring (@strtests) {
				my @tmatches = ();
				if ($mi) { # Test with case insensitivity
					my %already = ();
					while ($cmd =~ /(\Q$tstring\E)/gi) {
						my $this = $1;
						#if ($debug) { print STDOUT "This Match:\t${this}\n"; }
						if (! defined($already{$this})) {
							push(@tmatches,$this);
							$already{$1} = $this;
						}
					}
				} else {
					if ($cmd =~ /\Q$tstring\E/) {
						push(@tmatches,$tstring);
					}
				}
				for my $mstring (@tmatches) {
					if ($debug) { print STDOUT "Matching String '$mstring' in process $pid ($cmd)\n"; }
					if ($pid =~ /$$/) {
						if ($notthis) { # Don't flag current pid
							$flaggedme = 1; # In case this is the only pid that matches
							$flagdhash{$mstring} = $mstring; # Also keep track of what we flagged
						} else {
							push(@pidlist,$pid);
							if (! defined($matchhash{$mstring})) {
								$matchhash{$mstring} = $mstring;
							}
						}
					} else {
						push(@pidlist,$pid);
						if (! defined($matchhash{$mstring})) {
							$matchhash{$mstring} = $mstring;
						}
					}
				}
			}
		}
		$body{$pid} = "$pid ($user) $cmd";
		if ("$ppid" ne "$pid" ) {
			push(@{$ppid}, $pid);
			$myppid{$pid} = "$ppid";
		} else {
			if (! defined($startpid)) {
				if ($debug) {
					print STDOUT "Setting start pid to $pid\n";
					print STDOUT "\$body{\$pid} = \$pid (\$user) \$cmd";
					print STDOUT "$body{$pid} = $pid ($user) $cmd";
				}
				$startpid = $pid;
			} else { # We should not see this
				print STDOUT "ERROR: Start pid already set to $startpid\n";
			}
			if ($debug) { print STDOUT "Not Pushing pid $pid to ppid $ppid\n"; }
		}
	}
	close(DATA);
	for my $plitem (@pidslist) {
		if ($debug) { print STDOUT "Checking parent of pid $plitem ($myppid{$plitem})\n"; }
		if (! defined($myppid{$plitem})) { # Process has no parent defined (system pid)
			if ($debug) { print STDOUT "Skipping $plitem\n"; }
			next;
		} elsif (! defined($body{$myppid{$plitem}})) { # Parent of $plitem does not have a body
			if ($debug) { print STDOUT "Parent of Process $plitem does not have a body defined\n"; }
			if (! defined($startpid)) {
				if ($debug) { print STDOUT "Setting start pid to $myppid{$plitem}\n"; }
				$body{$myppid{$plitem}} = "$myppid{$plitem} (root) [kernel process]";
				$startpid = $myppid{$plitem};
			} else { # We should not see this
				if ($startpid != $myppid{$plitem}) {
					print STDOUT "ERROR: start -> $myppid{$plitem}: Start pid already set to $startpid\n";
				} else {
					print STDOUT "Warning: Start pid is already set. to $myppid{$plitem}\n";
				}
			}
		} else {
			if ($debug) { print STDOUT "$body{$myppid{$plitem}}\n"; }
		}
	}
}

sub ShowVersion() { # File sequence listing tool with compact sequence notation
	my @bpath = split /\//,$0;
	my $bfil = pop(@bpath);
	print STDOUT "\n$bfil: -\tProcess tree display Utility\n\nVersion $Revision\n\n";
	exit 0;
}

sub ShowHelp() { # Usage information:
	my @bpath = split /\//,$0;
	my $bfil = pop(@bpath);
	print STDOUT "\n$bfil: Arranges output of ps into nice looking tree.\n\n";
	print STDOUT "Usage: $bfil [options] (pid [pid2...]|-s string [string2...])\n\n";
	print STDOUT "Options:\n";
	printf STDOUT "   %-11s%-10s   %s\n","-nc"       ,"    ","(No Children) Do not descend into child pids.";
	printf STDOUT "   %-11s%-10s   %s\n",""          ,"    ","(i.e.: only show children of initial pid.)";
	printf STDOUT "   %-11s%-10s   %s\n","\$pid"     ,"    ","Prints tree starting at \$pid";
	printf STDOUT "   %-11s%-10s   %s\n",""          ,"    ","(if multiple pids, are specified prints tree including all pids from starting process)";
	#printf STDOUT "   %-11s%-10s   %s\n","-s"        ,"    ","Strings given in the command line will be searched for in the process list.";
	printf STDOUT "   %-11s%-10s   %s\n","-s"        ,"    ","Treat the next value on the command line explicitly as a string match.";
	printf STDOUT "   %-11s%-10s   %s\n","-nos"      ,"    ","Do not search further for strings on the command line for matching.";
	#printf STDOUT "   %-11s%-10s   %s\n","-si"       ,"    ","Strings matches will be case insensitive";
	printf STDOUT "   %-11s%-10s   %s\n","-si"       ,"    ","Treat next value explicitly as a string match; treat matches as case insensitive.";
	printf STDOUT "   %-11s%-10s   %s\n","-i"        ,"    ","Strings matches if requested/given will be case insensitive";
	printf STDOUT "   %-11s%-10s   %s\n","-noi"      ,"    ","Strings matches if requested/given will be case sensitive";
	printf STDOUT "   %-11s%-10s   %s\n","\$str"     ,"    ","Once -s has been given $bfil will search process comands for matching strings";
	printf STDOUT "   %-11s%-10s   %s\n",""          ,"    ","A numeric value immediatey following -s[i] will be treated explicity as a string";
	printf STDOUT "   %-11s%-10s   %s\n","-bt"       ,"    ","(BackTrack) When only one pid is matched, traverse back to initial system pid (default)";
	printf STDOUT "   %-11s%-10s   %s\n","-nobt"     ,"    ","When only one pid is matched, list only from it's parent and below";
	printf STDOUT "   %-11s%-10s   %s\n","-c"        ,"    ","Highlight matched pids and strings with color in output (default)";
	printf STDOUT "   %-11s%-10s   %s\n","-noc"      ,"    ","Do not highlight matched pids and strings with color in output";
	printf STDOUT "   %-11s%-10s   %s\n","-verbose"  ,"    ","When no pids are given on Linux hosts, do not list kernel threads in output";
	if ($_[0]) {
		printf STDOUT "   %-11s%-10s   %s\n","-clrp"     ,"\$clr","Specify highlight color \$clr for matching pids in output";
		printf STDOUT "   %-11s%-10s   %s\n","-clrb"     ,"\$clr","Specify highlight color \$clr to color cmd body for matched pids in output";
		printf STDOUT "   %-11s%-10s   %s\n","-clrs"     ,"\$clr","Specify highlight color \$clr for matching strings in output";
		printf STDOUT "   %-11s%-10s   %s\n",""          ,"     ","Colors can be one of: red, blue, green, cyan, magenta, yellow, white, grey, black,";
		printf STDOUT "   %-11s%-10s   %s\n",""          ,"     ","or bright (red, blue, green, cyan, magenta, yellow, white)";
		printf STDOUT "   %-11s%-10s   %s\n","-allcolor" ,"     ","Remaining body of proceses with matched strings will be highlighted";
		printf STDOUT "   %-11s%-10s   %s\n","-noac"     ,"     ","Remaining body of proceses with matched strings will not be highlighted";
		printf STDOUT "   %-11s%-10s   %s\n","-d"        ,"     ","Display (lots of) debugging information about processing pid tree data";
		printf STDOUT "   %-11s%-10s   %s\n","-[-]version","   " ,"Display Software Version and exit.";
		printf STDOUT "   %-11s%-10s   %s\n","-[-]license","   " ,"Display Software License and exit.";
		printf STDOUT "   %-11s%-10s   %s\n","-[-]h[elp]","    " ,"Display [this]/brief help text and exit.\n";
	} else {
		printf STDOUT "   %-11s%-10s   %s\n","-[-]h[elp]","    " ,"Display [verbose]/this help text and exit.\n";
	}
	exit 0;
}

sub ShowLicense() { # Copyright / License (Limit to 80 column output)
	print STDOUT "Copyright © 2006-2013 Victor E. Vaile, IV. All Rights Reserved.\n\n";
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
			if ($ARGV[0] =~  /^-nc$/i){
				$nochildren = 1;
				shift(@ARGV);
			} elsif ($ARGV[0] =~  /^-it$/i){
				$notthis = 0;
				shift(@ARGV);
			} elsif ($ARGV[0] =~  /^-nt$/i){
				$notthis = 1;
				shift(@ARGV);
			} elsif ($ARGV[0] =~  /^-(bt|walkback|backtrack)$/i) {
				$walkback = 1;
				shift(@ARGV);
			} elsif ($ARGV[0] =~  /^-no(bt|walkback|backtrack)$/i) {
				$walkback = 0;
				shift(@ARGV);
			} elsif ($ARGV[0] =~  /^-nos(tring(s)?)?$/i) {
				$dostrings = 0;
				shift(@ARGV);
			} elsif ($ARGV[0] =~  /^-s$/i) { # Neaten this up...
				$dostrings = 1;
				shift(@ARGV);
				if (defined($ARGV[0]) && "$ARGV[0]" !~ /^$/ ) {
					push(@strtests,$ARGV[0]);
					shift(@ARGV);
				}
			} elsif ($ARGV[0] =~  /^-(si|is)$/i) { # Case insensitive
				$dostrings = 1;
				$mi = "i";
				shift(@ARGV);
				if (defined($ARGV[0]) && "$ARGV[0]" !~ /^$/ ) {
					push(@strtests,$ARGV[0]);
					shift(@ARGV);
				}
			} elsif ($ARGV[0] =~  /^-no(s(tring(s)?)?i|is)$/i) {
				$dostrings = 0;
				$mi = "";
				shift(@ARGV);
			} elsif ($ARGV[0] =~  /^-i$/i) {
				$mi = "i";
				shift(@ARGV);
			} elsif ($ARGV[0] =~  /^-noi$/i) {
				$mi = "";
				shift(@ARGV);
			} elsif ($ARGV[0] =~  /^-c$/i) {
				$docolors = "1";
				shift(@ARGV);
			} elsif ($ARGV[0] =~  /^-(noc|nofruitycolors)$/i) {
				$docolors = "0";
				shift(@ARGV);
			} elsif ($ARGV[0] =~ /^-(-)?h(elp)?$/i ) {
				if (($ARGV[0] =~ /--/) || ($ARGV[0] =~ /elp/i)) {
					&ShowHelp("Undoc");
				} else {
					&ShowHelp();
				}
				shift(@ARGV);
			} elsif ($ARGV[0] =~ /^-(-)?ver(sion)?$/i ) {
				shift(@ARGV);
				&ShowVersion();
			} elsif ($ARGV[0] =~ /^-(-)?lic(ense)?$/i ) {
				shift(@ARGV);
				&ShowLicense();
			} elsif ($ARGV[0] =~ /^-clrp$/ ) { # PID Color
				shift(@ARGV);
				if (defined($ARGV[0]) && "$ARGV[0]" !~ /^$/ ) {
					if ($ARGV[0] =~ /(grey|black|none|(bright)?(red|blue|green|cyan|magenta|yellow|white))/i) {
						$pclr = $clrs{"$ARGV[0]"};
					} else {
						print STDERR "Warning -clrp: Invalid highlight color '$ARGV[0]' specified.\n";
					}
					shift(@ARGV);
				} else {
					print STDERR "Warning -clrp: No pid highlight color specified.\n";
				}
			} elsif ($ARGV[0] =~ /^-clrb$/ ) { # Body Color
				shift(@ARGV);
				if (defined($ARGV[0]) && "$ARGV[0]" !~ /^$/ ) {
					if ($ARGV[0] =~ /(grey|black|none|(bright)?(red|blue|green|cyan|magenta|yellow|white))/i) {
						$bclr = $clrs{"$ARGV[0]"};
					} else {
						print STDERR "Warning -clrb: Invalid highlight color '$ARGV[0]' specified.\n";
					}
					shift(@ARGV);
				} else {
					print STDERR "Warning -clrb: No body highlight color specified.\n";
				}
			} elsif ($ARGV[0] =~ /^-clrs$/ ) { # String Color
				shift(@ARGV);
				if (defined($ARGV[0]) && "$ARGV[0]" !~ /^$/ ) {
					if ($ARGV[0] =~ /(grey|black|none|(bright)?(red|blue|green|cyan|magenta|yellow|white))/i) {
						$sclr = $clrs{"$ARGV[0]"};
					} else {
						print STDERR "Warning -clrs: Invalid highlight color '$ARGV[0]' specified.\n";
					}
					shift(@ARGV);
				} else {
					print STDERR "Warning -clrs: No string highlight color specified.\n";
				}
			} elsif ($ARGV[0] =~  /^-(allcolor|ac)$/i) {
				$allcolor = 1;
				shift(@ARGV);
			} elsif ($ARGV[0] =~  /^-no(allcolor|ac)$/i) {
				$allcolor = 0;
				shift(@ARGV);
			} elsif ($ARGV[0] =~  /^-verbose$/i) {
				$verbose = 1;
				shift(@ARGV);
			} elsif ($ARGV[0] =~  /^-d(ebug)?$/i) {
				$debug = 1;
				shift(@ARGV);
			} elsif ($ARGV[0] =~  /^-f(ile)?$/i) {
				shift(@ARGV);
				if ($ARGV[0] !~ /^$/) {
					if ($ARGV[0] =~ /^-$/) {
						$pscmd = "cat $ARGV[0]";
					} elsif ( -f $ARGV[0]) {
						$pscmd = "cat $ARGV[0]";
					} else {
						die("Cannot find file $ARGV[0]\n");
					}
				} else { 
					print STDERR "File argument $ARGV[0] cannot be empty.\n";
					exit(1);
				}
				shift(@ARGV);
			} else {
				if ($ARGV[0] =~ /^[0-9][0-9]*$/) {
					push(@pidlist,$ARGV[0]);
				} elsif ($dostrings) {
					push(@strtests,$ARGV[0]);
				} else {
					print STDOUT "pid must be a numerical value.\n";
					exit 1;
				}
				shift(@ARGV);
			}
		}
	}
}

# main()
&ParseCommandLine;
if (@pidlist) {
	for my $mpid (@pidlist) {
		$poi{$mpid} = $mpid;
	}
}
&GetProcesses;
if (@pidlist) {
	if ($#pidlist) {
		$multiprune = 1;
		for my $prepid (@pidlist) {
			if ($debug) { print STDOUT "Walking pid $prepid\n"; }
			&PreWalk($prepid);
		}
	} else {
		$startpid = $pidlist[0];
	}
} elsif (($dostrings) && ($flaggedme)) {
	%matchhash = (%flagdhash);
	push(@pidlist,$$);
	$startpid = $$;
} elsif (($uname =~ /Linux/) && (! $verbose)) { # Do not list Linux kthreads unless we want them
	$startpid = 1;
}
if (@pidlist) {
	for my $cpid (@pidlist) {
		$cpids{$cpid} = $cpid;
	}
} else { # Colors Main system pid.  ...Maybe turn this off?
	$cpids{$startpid} = $startpid;
	#$poi{$startpid} = $startpid;
}
if ($docolors) {
	for my $ky (keys(%cpids)) { # Update Colors here
		if (defined($body{$ky})) {
			$body{$ky} = &ColorString(${ky});
		}
	}
}
&ProcessChild($startpid);

exit 0;

##  PROTO: 0 (no args)   ##  PROTO: 5    ##  PROTO: 5 (walkback)
##  0                    ##  4           ##  0
##   \_1                 ##   \_5        ##   \_1
##     |\_2              ##    |\_11     ##     |
##     |\_3              ##    |  |\_14  ##      \_3
##     |   \_4           ##    |   \_15  ##         \_4
##     |     |\_5        ##    |\_12     ##            \_5
##     |     | |\_11     ##    |   \_16  ##             |\_11
##     |     | |  |\_14  ##     \_13#    ##             |  |\_14
##     |     | |   \_15                  ##             |   \_15
##     |     | |\_12                     ##             |\_12
##     |     | |   \_16                  ##             |   \_16
##     |     |  \_13                     ##              \_13
##     |     |\_6
##     |      \_7
##     |\_8
##     |\_17
##     |\_9
##      \_10

