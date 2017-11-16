#!/usr/bin/perl -w

my $Revision = "1.12";
# Print human readable sizes and/or column ouptut from supplied input/command
# Created by Victor E. Vaile, IV on 20101020
# 1.00 20101020	Initial Version
# 1.01 20110729	Complete re-write, adding Command line parsing, process
#		execution, user-defineable sorting, New AddSpec function, for
#		handling data in hash (instead of array), header detection and
#		process name detection for common data types (df and du so far)
#		read from and/or write to files, stdin, or run a command. 
#		New version of Niceprint parses input more gracefully for tags.
# 1.02 20110729	Added option to expand output up to width of curent terminal,
#		or supplied width. Cleaned up commented lines.
# 1.03 20110802	Changed sort to handle hash, so that it could be done after all
#		headers are detected.  Added options for user to prefer alpha
#		vs numerical sort for mixed fields. Added detection of ifs to 
#		input on file and command subs (now tainted, but effecient).
#		Added test for terminal on STDIN to specify stty to tty if not.
#		Option to ignore field lengths of comment lines. Better handling
#		for column totals when using $lastalign to neaten extaneous data.
#		Default test to read file given on cmd without -f flag.
#		Fix for size value from non-header row not combined with fszhash
# 1.04 20110809	Changed handling of lastalign to behave differently if field is 
#		meant to be right justified. Saved data about field sizes to place
#		back into the fszhash if needed, and adjust the output to use the
#		$ifs instead of the padded $setofs after the aligned field.  Left
#		in debugging data until next version.
# 1.05 20120316	Fix for match errors on empty lines.
#		Option to skip rows for all formatting and field detection
#		Remove carriage returns, form feeds from end of lines.
# 1.06 20120316	Preset tweaks for BSD df
#		Populate fsthash values with any missing fields from existing hsthash
# 1.07 20120316	Change to field width formatting for ShowHelp()
#		Added option to reverse sort
#		Remove whitespace at end of field for numeric sorting
# 1.08 20120329	Bug fix for error on processing empty string, and missing ampersand.
# 1.09 20120621	Added missing handling for SIGALRM, Offsets and lastalign for df headers
#		Added handling for a bit more debugging
# 1.10 20130414	Updated license
# 1.11 20140303	Added ldata flag to pass args for easy math on the command line
# 1.12 20140305	Changed ldata output to not pad last left justified field
# TODO: Option to Output tab delimited, Check on field lengths for converted number strings

use strict 'vars';
use strict 'subs';

my @bpath = split /\//,$0;
my $bfil = pop(@bpath);
my @printarray = ();
my @nicetags = ("B", "K", "M", "G", "T", "P", "E", "Z", "Y");
my $nicetagstr = join("",@nicetags);
my $niceidx = "";
my $headerpad = 1; # If there's a header row, treat it as 1:1 with the data rows for alignment, else don't pad at all
my %datastor = (); # Hash to store complete set of separated data (index for anonymous arrays)
my %fszhash = (); # Hash to store max field lengths
my %hszhash = (); # Hash to store max field lengths for headers only
my %fsthash = (); # Hash to store Data field type status (0 = data; 1 = number types; 2 = [convertable] signed digits; 3 = [convertible] unsigned digits )
my %csthash = (); # Hash to store Data field character status (non digit)  0 = has digits; 1 = no digits; 2 = Only Alpha
my @rjfields = (); # (); For du,df : (1,6,7); # For ls
my @hpfields = (); # For du,df
my %hphash = (); # To store fields for easy access
my $lastalign = 0; # Last Field to align
my $savflast = 0; # Save Last Field size in case of right justification
my $savhlast = 0; # Save Last Field (header) size in case of right justification
my $savfrem = 0; # Save Last Field size in case of right justification
my $savhrem = 0; # Save Last Field (header) size in case of right justification
# TODO: Auto decimal print for ($) fields,
my $header = 0; # Ignore sizing, number status, num fields of first row
my $skiprows = 0; # Ignore sizing, number status, num fields of first rows specified, and don't alter (pad)
my $runcmd = ""; # Command to get list from (allows vars to be set explicitly based on the command [du, df, etc.])
my $sort = 0; # Sort array before processing to hash (simple).
my $debug = 0;
my $autodetect = 1;
my $autoconvert = 0; # Only use if ALL numbers are data sizes in bytes, or tagged
my $termexp = 0; # Expand output to match terminal width
my $alarmsecs = 5;
my @alarmbuffer = ();
my $runningalarm = 0; # In case ForkSpawn input takes too long.
my @indata = (); # Input data to be sent to ForkSpawn
my $stuff = ""; # Shifted data from array sent to ForkSpawn
my $logfil = "/tmp/$bfil.log";
my $ifs = 0;	# Field separator present for data
my $setifs = '\t';	# Specified Input Field Separator
my $setofs = " ";	# Specified Output Field Separator
my $inputfil = "";
my $outfile = "";
my $sortfld = 0;
my $allcommas = 1;
my $alltabs = 1;
my $numspref = 0;
my $ignorecom = 0;
my $swap = 0;
my $ldata = 0;
my $cleanout = 0;

$SIG{ALRM} = \&DoAlarm; # Fix for blocking process input

sub GetColSize() {
	my $cols = 80; # Default width, just in case
	my $size;
	if (-t STDIN ) {
		$size = `stty size`;
	} else { # In use.  Hope the tty works then
		$size = `stty size </dev/tty`;
	}
	my $exstat = $? >> 8;
	if ($exstat) {
		print STDERR "WARNING: Failed to get tty size.\n$!\n";
	} else {
		my @szz = split(/[\s]+/,$size);
		$cols = $szz[1];
	}
	return $cols;
}

sub PrintSpec(@) {
	for my $lin (@_) {
		print STDOUT "$lin\n";
	}
}

sub NicePrint($$) { # Return Human Tagged format string for size using Global @nicetags array
	my %nth;
	my $out;
	my $count = 0;
	my $mnum = $_[0];
	my $ct = "";
	my $sign = "";
	if ($_[1]) {
		$ct = $_[1];
	} elsif ($mnum =~ /(-?\d+)([$nicetagstr])/i ) { # (aka: NiceTags Array vals)
		$mnum = $1;
		$ct = "\U$2";
	} elsif ($mnum =~ /(-?\d+)/ ) {
		$mnum = $1; # Should only be digits anyway
	}
	if ($ct) {	# If there's a tag, count down from there...
		for (0..$#nicetags) {	# Index the nicetags array
			$nth{$nicetags[$_]} = "$_";
		}
		$count = $nth{$ct};
	}
	if ( $mnum =~ /([-+])(\d+)/ ) {	# Not dividing signed values
		$sign = $1;
		$mnum = $2;
	}
	while ( $mnum >= 1024) {
		$mnum = sprintf("%.9f", $mnum/1024 );
		$count += 1;
	}
	if ($mnum < 10) {
		if ($mnum =~  /^[0-9]$/ ) {
			$out = "$mnum";
		} else {
			$out = sprintf("%.1f", $mnum );
		}
	} else {
		$out = sprintf("%.0f", $mnum );
	}
	return "${sign}${out}$nicetags[$count]"
}

sub CondSrt { # Sort by number if possible, else string compare
	my $sa = "a";
	my $sb = "b";
	if ($swap) {
		$sa = "b";
		$sb = "a";
	}
	if (($a->[0] =~ /^(\d+)$/) && ($b->[0] =~ /^(\d+)$/)) {
		$$sa->[0] <=> $$sb->[0];
	} else {
		if ((! $csthash{$sortfld}) && ($numspref)) { # Some fields contain numbers
			$$sa->[1] <=> $$sb->[1] || 
			$$sa->[0] cmp $$sb->[0];
		} else {
			$$sa->[0] cmp $$sb->[0];
		}
	}
}

sub HashMap(@) {
	if (! $_[0]) { 
		return(0,0);
	}
	my $rta = "\L$_[0]";
	if ($numspref) {
		$rta =~ s/\s*$//;
	}
	my $rtb = length($rta);
	#print STDOUT "Sort: $rta,$rtb\n";
	return($rta,$rtb);
}

sub HashSort(@) {
	my %inhash = @_;
	my %outhash = ();
	my @preorder = ();
	my @ordered = ();
	my $cidx = 1;
	for my $hidx (sort { $a <=> $b } keys(%inhash)) {
		if ($hidx > $header + $skiprows) {
			push(@preorder,$hidx);
		} else {
			#print STDOUT "Skipping sort for index $hidx\n";
			push(@ordered,$hidx);
		}
	}
	@preorder = map { $_->[2] }
		sort { CondSrt }
		map { [&HashMap(${$inhash{$_}}[$sortfld]),$_] }
		@preorder;
	push(@ordered,@preorder);
	for my $oidx (@ordered) {
		@{ $outhash{$cidx} } = @{ $inhash{$oidx} };
		$cidx += 1;
	}
	return(%outhash);
}

sub AddSpec(@) {
	my %input = @_;
	my @output = ();
	my $js = " ";
	if ($ifs) {
		$js = "$setifs";
	}
	for my $idx (sort {$a <=> $b} (keys(%input))) {
		my @current = @{ $input{$idx} };
		my $linval = "";
		my $lastval = (($lastalign) && ($fsthash{$lastalign} > 0)) ? $lastalign + 1 : $lastalign;
		my $endval = (($lastval) && ($lastval <= $#current)) ? $lastval : $#current;
		for my $aid (0..$endval) {
			my $thisval;
			if (($lastalign) && ($aid >= $lastval)) {
				$thisval = join("$js",@current);
			} else {
				$thisval = shift(@current);
			}
			if (($idx > $header + $skiprows) && (defined($hphash{$aid}))) { # Convert matching values from Bytes
				$thisval = &NicePrint("${thisval}${niceidx}");
			}
			if ((($idx > $header) || ($headerpad)) && (($aid == 0)|| (! $fsthash{$aid})) && ($idx > $skiprows)) { # Left Justify item
				if ((!$cleanout) || ($aid != $endval)) {
					$thisval = sprintf("%-$fszhash{$aid}s",$thisval);
				}
				if ($aid > 0) {
					if (($lastalign) && ($fsthash{$lastalign} > 0) && ($aid >= $lastval)) {
						$thisval = "${js}${thisval}";
					} else {
						$thisval = "${setofs}${thisval}";
					}
				}
			} elsif ((($idx > $header) || ($headerpad)) && ($aid > 0) && ($fsthash{$aid}) && ($idx > $skiprows)) { # Right Justify
				$thisval = sprintf("%$fszhash{$aid}s",$thisval);
				$thisval = "${setofs}${thisval}";
			}
			$linval .= "$thisval";
		}
		push(@output,$linval);
	}
	return(@output);
}

sub ReadFileList($) { # Read file or STDIN contents into array
	my $readfil = $_[0];
	my @rtarray = ();
	my $FH = "STDIN";
	if (($readfil) && ($readfil !~ /^-$/)) {
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
		$lin =~ s/(\r|\n|\f)$//;
		if ($lin !~ /\,.+\,/) { $allcommas = 0; }
		if ($lin !~ /\t.+\t/) { $alltabs = 0; }
		push(@rtarray,$lin);
	}
	if ($readfil !~ /^-$/) {
		close(FH);
	}
	return(@rtarray);
}

sub WriteFile($@) {
	my ($name,@tdata) = @_;
	open(FH, "> $name") or die "Failed to write file $name $!\n";
	for my $lin (@tdata) {
		print FH "$lin\n";
	}
	close(FH);
}

sub CDetect(@) { # Define a couple command string patterns with accompanying settings
	if ($_[0] =~ /^du(\s+-[a-jl-zA-Z]*k|$)/) { # du with sizes in Kb
		shift(@nicetags);
		push(@hpfields,1);
		if (! $lastalign) { $lastalign = 1; }
	} elsif ($_[0] =~ /^du\s+-[a-ln-zA-Z]*m/) { # du with sizes in Mb
		shift(@nicetags);
		shift(@nicetags);
		push(@hpfields,1);
		if (! $lastalign) { $lastalign = 1; }
	} elsif ($_[0] =~ /^ls\s+-[a-km-zA-Z]*l/) { # Unaliased ls -l with sizes in bytes
		push(@hpfields,5);
		if (! $lastalign) { $lastalign = 8; }
	}
}

sub HDetect(@) { # Define a couple common header patterns, with accompanying settings
	if (! @_) { return; }
	my $rt = shift;
	my @outarray = @_;
	if ($rt =~ /^([Ff]ilesystem\s+Type\s+)(kbytes)(\s+use\s+avail\s+\%use\s+Mounted\s+on)$/) { # IRIX Version of df -k
		shift(@nicetags);
		$header = 1;
		$rt = "${1}size${3}";
		push(@hpfields,3,4,5);
		push(@rjfields,6);
		$sort = 1;
		$lastalign = 6;
		$setofs = "   ";
	} elsif ($rt =~ /^(Filesystem\s+Type\s+blocks\s+use\s+avail\s+\%use\s+Mounted\s+on)$/) { #IRIX Version of df (size in 512b blocks)
		$header = 1;
		$sort = 1;
		$lastalign = 6;
	# TODO: Make calc to convert from 512b blocks -> Kb -> Variable Tagged Binary
	} elsif ($rt =~ /^(Filesystem\s+Type\s+)(1024-blocks)(\s+Used\s+Available\s+Capacity\s+Mounted\s+on)$/) { # SLES 10.3 df
		shift(@nicetags);
		$header = 1;
		$rt = "${1}Size${3}";
		push(@hpfields,3,4,5);
		push(@rjfields,6);
		$sort = 1;
		$lastalign = 6;
		$setofs = "   ";
	} elsif ($rt =~ /^(Filesystem\s+)(1K-blocks|1024-blocks)(\s+Used\s+Avail\s+Capacity\s+Mounted\s+on)$/) { # BSD df
		shift(@nicetags);
		$header = 1;
		$rt = "${1}Size${3}";
		push(@hpfields,2,3,4);
		push(@rjfields,5);
		$sort = 1;
		$lastalign = 5;
		$setofs = "   ";
	} elsif ($ldata) { # Special case to do easy binary maths on command line strings
		my $cnt = 1;
		for my $cval (split(/\s+/,$rt)) {
			if ($cval =~ /^-?\d+[$nicetagstr]?$/i) {
				push (@hpfields,$cnt);
			}
			$cnt += 1;
		}
	}
	if (@outarray) {
		return($rt,@outarray);
	} else {
		return($rt);
	}
}

sub PopHash(@) { # Populate hash with field separated data from input array, collecting stats as we go.
	my %rthash = ();
	my %hsthash = (); # Header status hash
	my %debug = ();
	my $inc = 1; # (For sorting later)
	my $dcnt = 0; # (For nicer debugging)
	my $spc = '\s+';
	if ($ifs) { # Use explicitly set field separator
		$spc = "$setifs";
	}
	my $htst = ($header)? $header : 1;
	$htst += $skiprows;
	for my $lin (@_) {
		my $remline = 0;
		my $remsline = 0;
		if (($inc <= $header + $skiprows) && ((! $headerpad) || ($inc <= $skiprows))) {
			@{ $rthash{$inc}} = ($lin);
		} elsif ($lin =~ /^$/) {
			@{ $rthash{$inc}} = ($lin);
		} elsif (($ignorecom) && ($lin =~ /^([;:#*]+|rem)(\s+|$)/)) {
			@{ $rthash{$inc}} = ($lin);
		} else {
			my @fields = split(/$spc/,$lin);
			if ((! $ifs) && (defined($fields[0])) && ($fields[0] =~ /^$/) && (defined($fields[1])) && ($fields[1] =~ /^\d+/) ) { 
				shift(@fields); # Discard empty fields from right justified numbers in first input field
				if (($debug) && (! $dcnt)) { print STDOUT "Removing empty first field detected\n"; }
				$dcnt += 1;
			}
			@{ $rthash{$inc}} = @fields;
			for my $idx (0..$#fields) {
				if ($debug) {
					if (! defined($debug{$idx})) {
						$debug{$idx} = $idx;
						print STDOUT "\nStarting Index $idx for Line with $#fields fields, spaced by '$spc' ('$setifs'):\n'$lin'\n";
					}
				}
				my $flen = length($fields[$idx]);
				if (($lastalign) && ($idx >=  $lastalign)) { # Keep the data separate, but adjust the value of the last used field.
					$remline += $flen;
					if ($idx == $lastalign) {
						if ($inc > $htst) {
							if ($flen > $savflast) {
								$savflast = $flen;
							}
						} else {
							if ($flen > $savhlast) {
								$savhlast = $flen;
							}
						}
					} else {
						$remsline += $flen;
					}
					if ($idx == $#fields) { # Last field add the totals for this row, and adjust $fszhash{$lastalign} if necessary
						if ($inc > $htst) {
							if (! defined($fszhash{$idx})) {
								$fszhash{$idx} = 0; # Make sure we're set to something here.
								#print STDOUT "Set Size (lastalign) for field $idx in row $inc is $remline\n";
							}
							# TODO: Fix chicken/egg issue lastalign fszhash
							if (! defined($fszhash{$lastalign})) {
								$fszhash{$lastalign} = $remline;
							} elsif ($remline > $fszhash{$lastalign}) {
								$fszhash{$lastalign} = $remline;
							}
							if ($remsline > $savfrem) {
								$savfrem = $remsline;
								#print STDOUT "Setting Saved [lastalign] reminder to $savfrem at row $inc, field $idx\n";
							}
						} else {
							if (! defined($hszhash{$idx})) {
								$hszhash{$idx} = 0; # (Here too.)
								#print STDOUT "Set Size (lastalign_H) for field $idx in row $inc is $hszhash{$idx}\n";
							}
							if (! defined($hszhash{$lastalign})) {
								$hszhash{$lastalign} = $remline;
							} elsif ($remline > $hszhash{$lastalign}) {
								$hszhash{$lastalign} = $remline;
							}
							if ($remsline > $savhrem) {
								$savhrem = $remsline;
							}
						}
					} else {
						if (! defined($fszhash{$idx})) {
							#print STDOUT "Set Size (lastalign_E) for field $idx in row $inc is $flen\n";
							$fszhash{$idx} = 0; # Make sure we're set to something here.
						}
					}
				} elsif ($inc > $htst) { # We're past the defined, and test header, values go to data part of the array
					if (! defined($fszhash{$idx})) { # Niceprint will make this value ($signed)? 5 : 4
						#print STDOUT "Set Size (Normal) for field $idx in row $inc is $flen\n";
						$fszhash{$idx} = $flen;
					} elsif ($flen > $fszhash{$idx}) {
						$fszhash{$idx} = $flen;
					}
				} else {
					if (! defined($hszhash{$idx})) { # Separate header field lengths from data field lengths.
						#print STDOUT "Set Size (Normal_H) for field $idx in row $inc is $flen\n";
						$hszhash{$idx} = $flen;
					} elsif ($flen > $hszhash{$idx}) {
						$hszhash{$idx} = $flen;
					}
				}
				my $fstat = 0; # General Text
				my $cstat = 0; # General Text
				if ($fields[$idx] =~ /^\d+$/ ) { # Unsigned Digits
					$fstat = 3; # Candidate for Niceprint, field length 5
				} elsif ($fields[$idx] =~ /^\-\d+$/ ) { # Signed Digits
					$fstat = 2; # Candidate for Niceprint, field length 6
				} elsif ($fields[$idx] =~ /^\$?[0-9\-\.:]+[\$\%]?$/ ) { # Formatted Numbers
					$fstat = 1; # Right Justify this value
				} elsif ($fields[$idx] =~ /^[a-zA-Z]+$/ ) { # Alphas only
					$cstat = 2; # Alpha sort this field
				} elsif ($fields[$idx] =~ /^\D+$/ ) { # Non-Digits only
					$cstat = 1; # Alpha sort this field
				}
				if ($autodetect) {
					if ($inc > $htst) { # We're past the defined, and test header, values go to data part of the array
						#print STDOUT "Processing Line $inc  index $idx (Post Header)\n";
						if (! defined($fsthash{$idx})) {
							$fsthash{$idx} = $fstat;
						} elsif ($fstat < $fsthash{$idx}) {
							$fsthash{$idx} = $fstat;
						}
					} else {
						#print STDOUT "Processing Line $inc index $idx (Pre Header)\n";
						if (! defined($hsthash{$idx})) {
							$hsthash{$idx} = $fstat;
						} elsif ($fstat < $hsthash{$idx}) {
							$hsthash{$idx} = $fstat;
						}
					}
					if (! defined($csthash{$idx})) {
						$csthash{$idx} = $cstat;
					} elsif ($cstat < $csthash{$idx}) {
						$csthash{$idx} = $cstat;
					}
				} else {
					if (! defined($fsthash{$idx})) {
						$fsthash{$idx} = 0;
					}
				}
			}
		}
		$inc += 1;
	}
	if (($autodetect) && (! $header)) { # Header hasn't been explicitly specified
		# TODO: Maybe... report a header if the first row field count is significantly different than remainder.
		if ($inc > 2 + $skiprows ) {
			my $notsame = 0;
			for my $cmp (keys(%fsthash)) {
				if ((! defined($hsthash{$cmp})) || ($fsthash{$cmp} ne $hsthash{$cmp})) {
					$notsame += 1;
				}
			}
			for my $cmp (keys(%hsthash)) {
				if ((! defined($fsthash{$cmp})) || ($fsthash{$cmp} ne $hsthash{$cmp})) {
					$notsame += 1;
				}
			}
			if ($notsame) {
				for my $v (keys %hsthash) {
					if ((defined($fsthash{$v})) && ($hsthash{$v} < $fsthash{$v})) { # Data segment has more refined data than header
						$header = 1;
					}
				}
			}
			if (($debug) && ($header)) { print STDOUT "Header Auto Detected\n"; }
		}
	}
	for my $hk (keys(%hsthash)) { # If header had more fields, add values to fsthash
		if (!defined($fsthash{$hk})) {
			#print STDOUT "Adding Header index $hk value for fsthash\n";
			$fsthash{$hk} = $hsthash{$hk};
		}
	}
	if ($inc == 2 + $skiprows) { # Only 2 data rows, First row rules.
		%fsthash = %hsthash;
		%fszhash = %hszhash;
	}
	return %rthash;
}

sub AssignFVars() { # Organize vars based on collected data (Doesn't technically need to be a subroutine)
	for my $n (@rjfields) { # These lists start at 1
		$n -= 1;
		$fsthash{$n} = 1;
	}
	if ($lastalign) { # Final field should not be right justified
		$fsthash{($lastalign + 1)} = 0;
	}
	for my $n (@hpfields) { # These lists start at 1
		$n -= 1;
		if ($fsthash{$n} > 2) {
			$fszhash{$n} = 5;
		} else {
			$fsthash{$n} = 2;
			$fszhash{$n} = 6;
		}
		if (($lastalign) && ($n == $lastalign)) { # Update $lastalign's saved field size value if we're changing it.
			$savflast = $fszhash{$n};
		} elsif (($lastalign) && ($n > $lastalign)) { # Set the size back to zero (Currently no way to identify the field size from saved remainder data)
			$fszhash{$n} = 0;
		}
		$hphash{$n} = $n; # We're converting this data, since user asked, but we have no way to reconcile the alignment for the new data length.
	}
	if ($autoconvert) { # Automatically convert fields matching number spec
		for my $d (keys(%fsthash)) {
			if ($fsthash{$d} > 1) {
				if ((! $lastalign) || ($d <= $lastalign)) { # Not automatcially altering data past the lastalign column
					$hphash{$d} = $d;
				}
				$fszhash{$d} = 6;
				if ($fsthash{$d} > 2) {
					$fszhash{$d} = 5;
				}
				if (($lastalign) && ($d == $lastalign)) { # Update $lastalign's saved field size value. We have to use our saved remainder for the rest
					$savflast = $fszhash{$d};
				} elsif (($lastalign) && ($d > $lastalign)) { # Set the size back to zero, field won't be changed.
					$fszhash{$d} = 0;
				}
			}
		}
	}
	# TODO: check on the status of header auto detection here...
	if ((! $header) || ($headerpad)) { # Neaten up field padding for newly shortened columns
		my @fszarr = keys(%fszhash);
		my @hszarr = keys(%hszhash);
		if (! $lastalign) {
			if ($#hszarr > $#fszarr) {
				$lastalign =  $#fszarr + 1;
			}
		} else {
			if ($savhlast > $savflast) {
				$savflast = $savhlast;
			}
			if ($savhrem > $savfrem) {
				$savfrem = $savhrem;
			}
		}
		for my $h (keys(%hszhash)) { # If the header (or test header) was longer add the sizes to the normal hash
			if (! defined($fszhash{$h})) {
				$fszhash{$h} = $hszhash{$h};
			} elsif ($hszhash{$h} > $fszhash{$h} ) {
				$fszhash{$h} = $hszhash{$h};
			}
		}
	}
	if (($lastalign) && ($fsthash{$lastalign} > 0)) { 
		#print STDOUT "Last Align is $lastalign\n";
		#print STDOUT "Last Align + 1  is " . ($lastalign + 1) . "\n";
		$fszhash{$lastalign} = $savflast;
		$fszhash{($lastalign + 1)} = $savfrem;
		#$lastalign += 1;
	}
	if ($termexp) { #
		my $coltotl = 0;
		my @szarr = sort { $a <=> $b }keys(%fszhash);
		my $pinst = $#szarr;
		my $fplen = 0; # Size of total padding needed
		my $fslen = 0; # Size of padding per field separator
		if ($lastalign) {
			$pinst = $lastalign;
			my $js = " ";
			if ($ifs) {
				$js = "$setifs";
			}
			my $laadd = (($#szarr - $pinst) * (length($js))); 
			$coltotl += $laadd;
			if ($debug) { print STDOUT "Adding $laadd to Col Total\n"; }
		}
		if ($termexp == 1 ) { # No value specified. Set it to the terminal width
			$termexp = &GetColSize();
		}
		for my $v (@szarr) {
			$coltotl += $fszhash{$v};
			if ($debug) { print STDOUT "Field $v is $fszhash{$v}\n"; }
		}
		if ($termexp > $coltotl) {
			$fplen = $termexp - $coltotl;
			$fslen = $fplen / $pinst;
			$fslen = int($fslen); # Just get rid of the decimals
			my $curlen = length($setofs);
			if ($fslen > $curlen) {
				my $addlen = $fslen - $curlen;
				my $addstr = " " x $addlen;
				$setofs = "${addstr}${setofs}";
			}
		}
		if ($debug) { print STDOUT "\nTerm is $termexp chars wide, data is $coltotl already, adding up to $fplen chars ($fslen * $pinst)\n\n"; }
	}
}

sub DoAlarm() { # For now, just pull from the child buffer...
	print STDOUT "Alarm Called...\n";
	print STDOUT "Buffering command output until child finishes reading from our pipe via [its] STDIN\n";
	if ($runningalarm) { # Go back to what we were doing before...
		print STDOUT "Resetting Alarm while child reads.\n";
		$runningalarm = 0; # Reset state for next time...
	} else {
		$runningalarm = 1;
		if ((@indata) || ($stuff)) { # There's data pending to write, skim data from the child buffer to unblock...
			print STDOUT "Found Pending data...\n";
			alarm($alarmsecs); # Set this here incase we take too long
			my $nfound = 1; # Defined affirmatively once just to start the loop
			while ($nfound) { # Read from filehandle such that we don't block...
				my $rin = '';
				vec($rin, fileno(FROM_CHILD), 1) = 1;
				$nfound = select($rin, undef, undef, 0);	# Just Poll ($nfound defined for real)
				if ($nfound) {
					my $lin = <FROM_CHILD>;
					push (@alarmbuffer,$lin);
				}
			}
		} else {
			print STDOUT "Strange: No Data Pending...\n";
		}
		$runningalarm = 0; # We finished reading, okay to read again next time.
	}
	alarm($alarmsecs); # Until Next time...
}

sub ProcExStat($$$$) { # Report on the exit status of a named process, optionally warn & return simple stat, or error/die
	my $estat = shift;
	my $pname = shift;
	my $warn = shift;
	my $label = shift;
	my $rtval = 0;
	my $tag = $warn ? "WARNING" : "ERROR";
	my $exit_stat = $estat >> 8;
	my $kild_with = $estat & 127;    # or 0x7f, or 0177, or 0b0111_1111
	my $dmpd_core = $estat & 128;    # or 0x80, or 0200, or 0b1000_0000
	if ($exit_stat) { # command did not exit with non-zero status
		$rtval = 1;
		print STDOUT "\n$tag:\n$tag: $pname command exited with status $exit_stat.\n";
		if ($kild_with) { print STDOUT "$tag: command was killed with signal $kild_with.\n"; }
		if ($dmpd_core) { print STDOUT "$tag: And created a core file.\n"; }
		if (! $warn) { # We're serious here...
			print STDOUT "$tag: Something has gone wrong. Aborting $label.\n$tag:\n";
			die("$pname failed.\n");
		}
	}
	return($rtval);
}

sub ForkSpawn($$$$$$$@) { # Fork and spawn a process that we can read from, write to  # Usage:  ForkSpawn($procstring,$outfile,$dataout,$dolog,$doprint,$warnonly,$skipstdin,@indata)
	my $procstring = shift;	# Process and args
	my $outfile = shift;	# Output File name (if any)
	my $dataout = shift;	# Explicit Output data to array (only if (! $outfile))
	my $dolog = shift;	# Print to log?
	my $doprint = shift;	# Print to STDOUT?
	my $warnonly = shift;	# Don't die on error, prepend status to output array
	my $skipstdin = shift;	# Don't send any data to exec'd process (@indata should be empty)
	@indata = @_;		# Stuff we're feeding to the process (Now Global for Alarm)
	my $shortproc = $procstring; # For error messages...
	$shortproc =~ s/\s+.*//;
	my @outdata = ();	# Where if we keep stuff from the process
	if (! $skipstdin) {
		pipe(FROM_PARENT, TO_CHILD)     or die "pipe: $!";
	}
	pipe(FROM_CHILD,  TO_PARENT)    or die "pipe: $!";
	if (! $skipstdin) {
		select((select(TO_CHILD), $| = 1)[0]);   # autoflush
	}
	select((select(TO_PARENT), $| = 1)[0]);  # autoflush
	if ($debug) {
		print STDOUT "Executing: '$procstring'\n"; # DEBUG
	}
	FORK: { # Name this block so the redo can work below
		if (my $pid = fork) { # Parent Processes here:
			@alarmbuffer = ();
			close(TO_PARENT); # We don't need these here.
			if (! $skipstdin) {
				close(FROM_PARENT); # We don't need these here.
				alarm $alarmsecs;
				while ($stuff = shift (@indata)) { # $stuff now global for Alarm
					print TO_CHILD "$stuff\n";
				}
				close(TO_CHILD);
				alarm 0;
			}
			if ($dolog) {
				open(LOGFIL, ">> $logfil") or die "Failed to append to $logfil:\n$!\n";
			}
			while ($runningalarm) { sleep 1; }
			for my $lin (@alarmbuffer) { # In Case we had to grab data from the child buffer early..
				chomp $lin;
				if ($lin !~ /\,.+\,/) { $allcommas = 0; }
				if ($lin !~ /\t.+\t/) { $alltabs = 0; }
				if (($dolog) && ($doprint)) { # verbose output
					&PrintAndLog("$lin");
				} elsif ($dolog) { # log only
					print LOGFIL "$lin\n";
				} elsif ($doprint) { # log only
					print STDOUT "$lin\n";
				}
				if (($dataout) || ($outfile)) { # We're writing a file returning an array
					push(@outdata,$lin);
				}
			} # Okay, now back to the child filehandle
			while (defined(my $lin = <FROM_CHILD>)) {
				chomp $lin;
				if ($lin !~ /\,.+\,/) { $allcommas = 0; }
				if ($lin !~ /\t.+\t/) { $alltabs = 0; }
				if (($dolog) && ($doprint)) { # verbose output
					&PrintAndLog("$lin");
				} elsif ($dolog) { # log only
					print LOGFIL "$lin\n";
				} elsif ($doprint) { # log only
					print STDOUT "$lin\n";
				}
				if (($dataout) || ($outfile)) { # We're writing a file returning an array
					push(@outdata,$lin);
				}
			}
			close FROM_CHILD;
			waitpid($pid,0);
			my $exstat = &ProcExStat($?,$shortproc,$warnonly,"write"); # handle tar command exiting with non-zero status
			if ($warnonly) { # (We're only warning, but we're prepending the output array with the command exit status)
				unshift(@outdata,$exstat);
			}
		} elsif (defined($pid)) { # Child Processes here.
			if (! $skipstdin) {
				close(TO_CHILD); # Not using these either.
			}
			close(FROM_CHILD); # Not using these either.
			open(STDOUT,">&TO_PARENT"); # Re-Open STDOUT for this fork to go to the parent pipe
			if (! $skipstdin) {
				open(STDIN,"<&FROM_PARENT"); # Re-Open STDIN for this fork to come from the parent pipe
			}
			exec("$procstring");
			exit 3; # Should not get here...
		} else { # Failed outright...
			die "ERROR: $shortproc: fork failed. $!\n";
		}
	}
	if ($outfile) {
		&WriteFile($outfile,@outdata);
	}
	if ($dataout) {
		return(@outdata);
	}
}

sub ShowVersion() { # Something to do...
	print STDOUT "\n$bfil: - Print human readable output tool\n\nVersion $Revision\n\n";
	exit 0;
}

sub ShowHelp() {
	print STDOUT "\nUsage:\t$bfil: [options... ]\n";
	printf STDOUT "   %-12s%-6s   %s\n","-[-]c"      ,"\$cmd"  ,"Specify command \$cmd to run for input.";
	printf STDOUT "   %-12s%-6s   %s\n","-[-]f"      ,"\$fil"  ,"Specify file \$fil to read for input.";
	printf STDOUT "   %-12s%-6s   %s\n","-[-]o"      ,"\$fil"  ,"Specify file \$fil to write for output.";
	printf STDOUT "   %-12s%-6s   %s\n","-[-]j"      ,"\$flds" ,"Explicitly specify \$flds (comma separated) to be right justified";
	printf STDOUT "   %-12s%-6s   %s\n","-[-]p"      ,"\$flds" ,"Specify \$flds (comma separated) to be printed as human readable binary sizes";
	printf STDOUT "   %-12s%-6s   %s\n","-[-]l"      ,"\$fld"  ,"Specify \$fld as last field to be aligned";
	printf STDOUT "   %-12s%-6s   %s\n","-[-]x"      ," "      ,"Don't auto detect field types, only align and print";
	printf STDOUT "   %-12s%-6s   %s\n","-[-]ap"     ," "      ,"Automatically treat numeric fields as bytes and convert";
	printf STDOUT "   %-12s%-6s   %s\n","-[-]z"      ,"\$i"    ,"Specify \$i as the binary increment to start from when auto converting ($nicetagstr)";
	printf STDOUT "   %-12s%-6s   %s\n","-[-]sr"     ,"\$n"    ,"Specify \$n [if set, else 1] lines as rows to ignore for all formatting, and field types";
	printf STDOUT "   %-12s%-6s   %s\n","-[-]hr"     ,"\$n"    ,"Specify \$n [if set, else 1] lines as header lines (skipped when determining field types";
	printf STDOUT "   %-12s%-6s   %s\n","-[-]ih"     ," "      ,"Ignore Header row for field lengths:";
	printf STDOUT "   %-12s%-6s   %s\n","-[-]ic"     ," "      ,"Ignore comments (lines starting with [#:;]";
	printf STDOUT "   %-12s%-6s   %s\n","-[-]ifs"    ,"\$sep"  ,"Specify \$sep to be used as field separator for input data.";
	printf STDOUT "   %-12s%-6s   %s\n","-[-]ofs"    ,"\$sep"  ,"Specify \$sep to be used as field separator for output data.";
	printf STDOUT "   %-12s%-6s   %s\n","-[-]ex"     ,"\$w"    ,"Expand output to fill terminal width (or \$w chars if specified)";
	printf STDOUT "   %-12s%-6s   %s\n","-[-]ldata"  ," "      ,"Specify that remaining args are a single line to parse agressively for NicePrint calculation";
	if ($_[0]) {
		printf STDOUT "   %-12s%-6s   %s\n","-[-]s"      ,"\$n"    ,"Sort incoming array data (by optional field number)";
		printf STDOUT "   %-12s%-6s   %s\n","-[-]sn"     ,"\$n"    ,"Sort as above, but prefer numerical sort";
		printf STDOUT "   %-12s%-6s   %s\n","-[-]rv"     ,"\$n"    ,"Reverse output for sorted data";
		printf STDOUT "   %-12s%-6s   %s\n","-debug"     ," "      ,"Print debugging text for commands executed";
	}
	printf STDOUT "   %-12s%-6s   %s\n","-[-]version"," "      ,"Print Version exit.";
	printf STDOUT "   %-12s%-6s   %s\n","-[-]help"   ," "      ,"Print help text and exit.";
	print STDOUT "\n";
	exit 0;
}

sub ShowLicense() { # Copyright / License (Limit to 80 column output)
	print STDOUT "Copyright © 2008-2013 Victor E. Vaile, IV. All Rights Reserved.\n\n";
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
		while (defined($ARGV[0]) && "$ARGV[0]" !~ /^$/ && (! $ldata)) {
			if ($ARGV[0] =~ /^--?d(ebug)$/i ) {
				shift(@ARGV);
				$debug = 1;
			} elsif ($ARGV[0] =~ /^-?h$/i ) {
				&ShowHelp();
				shift(@ARGV);
			} elsif ($ARGV[0] =~ /^--?h(elp)?$/i ) {
				&ShowHelp(1);
				shift(@ARGV);
			} elsif ($ARGV[0] =~ /^--?v(ersion)?$/i) {
				shift(@ARGV);
				&ShowVersion();
			} elsif ($ARGV[0] =~ /^--?(copy|lic(ense)?)$/i) {
				shift(@ARGV);
				&ShowLicense();
			} elsif ($ARGV[0] =~ /^--?x$/i) {
				shift(@ARGV);
				$autodetect = 0;
			} elsif ($ARGV[0] =~ /^--?ap$/i) {
				shift(@ARGV);
				$autoconvert = 1;
			} elsif ($ARGV[0] =~ /^--?ih$/i) {
				shift(@ARGV);
				$headerpad = 0;
				if (! $header) {
					$header = 1;
				}
			} elsif ($ARGV[0] =~ /^--?ic$/i) {
				shift(@ARGV);
				$ignorecom = 1;
			} elsif ($ARGV[0] =~ /^--?j$/i) {
				shift(@ARGV);
				if (defined($ARGV[0]) && "$ARGV[0]" !~ /^$/ ) {
					if ($ARGV[0] =~ /^\d+(\,\d+)*$/) {
						my @nums = split(",",$ARGV[0]);
						push(@rjfields,@nums);
					} else {
						print STDOUT "WARNING: $ARGV[0] is not a valid Right-Justify field list.\n";
					}
					shift(@ARGV);
				} else {
					print STDERR "Right-Justify fields list cannot be empty\n";
				}
			} elsif ($ARGV[0] =~ /^--?ph?$/i) {
				shift(@ARGV);
				if (defined($ARGV[0]) && "$ARGV[0]" !~ /^$/ ) {
					if ($ARGV[0] =~ /^\d+(\,\d+)*$/) {
						my @nums = split(",",$ARGV[0]);
						push(@hpfields,@nums);
					} else {
						print STDOUT "WARNING: $ARGV[0] is not a valid Human Binary field list.\n";
					}
					shift(@ARGV);
				} else {
					print STDERR "Human Binary fields list cannot be empty\n";
				}
			} elsif ($ARGV[0] =~ /^--?l$/i) {
				shift(@ARGV);
				if (defined($ARGV[0]) && "$ARGV[0]" !~ /^$/ ) {
					if ($ARGV[0] =~ /^\d+$/) {
						$lastalign = $ARGV[0] - 1; # Make this the array index value
					} else {
						print STDOUT "WARNING: $ARGV[0] is not a valid last align field.\n";
					}
					shift(@ARGV);
				} else {
					print STDERR "last align field cannot be empty\n";
				}
			} elsif ($ARGV[0] =~ /^--?z$/i) {
				shift(@ARGV);
				if (defined($ARGV[0]) && "$ARGV[0]" !~ /^$/ ) {
					if ($ARGV[0] =~ /^[bkmgpezy]$/i) {
						$niceidx = "\U$ARGV[0]";
					} else {
						print STDOUT "WARNING: $ARGV[0] is not a valid binary size index value.\n";
					}
					shift(@ARGV);
				} else {
					print STDERR "binary size index value cannot be empty\n";
				}
			} elsif ($ARGV[0] =~ /^--?c$/i) {
				shift(@ARGV);
				if (defined($ARGV[0]) && "$ARGV[0]" !~ /^$/ ) {
					$runcmd = $ARGV[0];
					shift(@ARGV);
				} else {
					print STDERR "Command cannot be empty\n";
				}
			} elsif ($ARGV[0] =~ /^--?(ldata)?$/i) { # Also allow '--' as and end of arg marker...
				shift(@ARGV);
				$ldata = 1;
				$cleanout = 1; # Don't pad left justified output for last field
				$allcommas = 0;
			} elsif ($ARGV[0] =~ /^--?f$/i) {
				shift(@ARGV);
				if (defined($ARGV[0]) && "$ARGV[0]" !~ /^$/ ) {
					if (-f $ARGV[0]) {
						$inputfil = $ARGV[0];
					} else {
						print STDERR "Cannot read file $ARGV[0]\n";
					}
					shift(@ARGV);
				} else {
					print STDERR "File not specified\n";
				}
			} elsif ($ARGV[0] =~ /^--?o$/i) {
				shift(@ARGV);
				if (defined($ARGV[0]) && "$ARGV[0]" !~ /^$/ ) {
					$outfile = $ARGV[0];
					shift(@ARGV);
				} else {
					print STDERR "File not specified\n";
				}
			} elsif ($ARGV[0] =~ /^--?sc$/i) {
				$sort = 1;
				$numspref = 0;
				shift(@ARGV);
				if (defined($ARGV[0]) && "$ARGV[0]" =~ /^\d+$/ ) {
					$sortfld = $ARGV[0] - 1; # Users expect to start at 1
					shift(@ARGV);
				}
			} elsif ($ARGV[0] =~ /^--?sn$/i) {
				$sort = 1;
				$numspref = 1;
				shift(@ARGV);
				if (defined($ARGV[0]) && "$ARGV[0]" =~ /^\d+$/ ) {
					$sortfld = $ARGV[0] - 1; # Users expect to start at 1
					shift(@ARGV);
				}
			} elsif ($ARGV[0] =~ /^--?rv$/i) {
				shift(@ARGV);
				$swap = 1;
			} elsif ($ARGV[0] =~ /^--?s$/i) {
				$sort = 1;
				shift(@ARGV);
				if (defined($ARGV[0]) && "$ARGV[0]" =~ /^\d+$/ ) {
					$sortfld = $ARGV[0] - 1; # Users expect to start at 1
					shift(@ARGV);
				}
			} elsif ($ARGV[0] =~ /^--?hr$/i) {
				##print STDOUT "Header Spec\n";
				shift(@ARGV);
				if (defined($ARGV[0]) && "$ARGV[0]" =~ /^\d+$/ ) {
					$header = $ARGV[0];
					shift(@ARGV);
				} else {
					$header = 1;
				}
			} elsif ($ARGV[0] =~ /^--?sr$/i) {
				#print STDOUT "Skip Rows\n";
				shift(@ARGV);
				if (defined($ARGV[0]) && "$ARGV[0]" =~ /^\d+$/ ) {
					$skiprows = $ARGV[0];
					shift(@ARGV);
				} else {
					$skiprows = 1;
				}
			} elsif ($ARGV[0] =~ /^--?ex$/i) {
				shift(@ARGV);
				$termexp = 1;
				if (defined($ARGV[0]) && "$ARGV[0]" =~ /^\d+$/ ) {
					$termexp = $ARGV[0];
					shift(@ARGV);
				}
			} elsif ($ARGV[0] =~ /^--?tab$/i) {
				shift(@ARGV);
				$ifs = 1;
			} elsif ($ARGV[0] =~ /^--?ifs$/i) {
				shift(@ARGV);
				$ifs = 1;
				if (defined($ARGV[0]) && "$ARGV[0]" !~ /^$/ ) {
					$setifs = $ARGV[0];
					shift(@ARGV);
				} else {
					print STDERR "Input Field Separator not specified.  Defaulting to tab.\n";
				}
			} elsif ($ARGV[0] =~ /^--?ofs$/i) {
				shift(@ARGV);
				if (defined($ARGV[0]) && "$ARGV[0]" !~ /^$/ ) {
					$setofs = $ARGV[0];
					shift(@ARGV);
				} else {
					print STDERR "Output Field Separator not specified.  Defaulting to space.\n";
				}
			} else {
				if (-f $ARGV[0]) {
					$inputfil = $ARGV[0];
					if ($debug) { print STDOUT "Will try to read: $ARGV[0] for input.\n"; }
				} else {
					print STDERR "Unknown Option: $ARGV[0]\n";
				}
				shift(@ARGV);
			}
		}
		if (defined($ARGV[0])) { # We should only have data here if $ldata is set
			@printarray = join(" ",@ARGV);
		}
	}
}

&ParseCommandLine;

if ($runcmd) { 
	&CDetect($runcmd);
	@printarray = &HDetect(&ForkSpawn($runcmd,0,1,0,0,0,1,0));
} elsif ($ldata) {
	@printarray = &HDetect(@printarray);
} else {
	@printarray = &HDetect(&ReadFileList($inputfil));
}

if (($autodetect) && (! $ifs)) {
	if ($allcommas) {
		$ifs = 1;
		$setifs = ',';
	#} elsif ($alltabs) {
	#	$ifs = 1;
	}
}

%datastor = &PopHash(@printarray);

if ($sort) {
	%datastor = &HashSort(%datastor);
}

&AssignFVars;

@printarray = &AddSpec(%datastor);

if (@printarray) {
	if ($outfile) {
		&WriteFile($outfile,@printarray);
	} else {
		&PrintSpec(@printarray);
	}
}

exit 0;

