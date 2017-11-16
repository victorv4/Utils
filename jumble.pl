#!/usr/bin/perl -w 

my $Revision = '1.04';
# Return possible combinations of character strings
# optionally only matching unique or dictionary words.
# Created by Victor E. Vaile, IV on 20100602
# 1.00 20100602 Initial Version
# 1.01 20120406 Added Compbos() to limit search to subgroup
# 		of main search pattern, with less chance of 
# 		running out of memory for large patterns
# 1.02 20120406 Neatened output, option to only print combos
# 1.03 20120407 UniqeList() for unique substring groups
# 1.04 20130414	Added ShowVersion() ShowLicense()

my @readlist = ();
my $numletters = 0;
my $dictionary = "/usr/share/dict/words";
my $retfull = 0;
my $retuniq = 0;
my $retdict = 1;
my $nocase = 0;
my $quiet = 0;
my $limit = 0;
my $indep = 0;
my $verbose = 0;
my $conly = 0;
select((select(STDOUT), $| = 1)[0]);   # AutoFlush STDOUT (for '.' progress output)

sub UniqeList(@) { # Output array containing  unique values from input array
	my %uhash = ();
	my @uniqs = ();
	for (@_) {
		if (!defined($uhash{$_})) {
			$uhash{$_} = $_;
			push(@uniqs,$_);
		}
	}
	return @uniqs;
}

sub Factorial($) { # Return factorial of a given number
	my $n = $_[0];
	if ($n !~ /^[0-9]+$/) { die "ERROR $n is not a valid numeric value\n"; }
	my $pn = 1;
	while ($n > 0) {
		$pn *= $n;
		$n -= 1;
	}
	return $pn;
}

sub Combos(@) { # (Recursive) ultimately returns list of combinations of subgroup size $vl for provided @vars
	my $vl = shift @_;
	my @vars = @_;
	my $kv;
	my @newvars = ();
	if ($vl > 1) {
		while ($#vars + 1 >= $vl) {
			$kv = shift(@vars);
			for my $rvs (&Combos($vl - 1,@vars)) {
				push(@newvars,"${kv}${rvs}");
			}
		}
	} else {
		for my $lvs (@vars){
			push(@newvars,$lvs);
		}
	}
	return(@newvars);
}

sub LoopLetters(@) { # Pass a string, returns an array.
	my @letters = split(//,$_[0]);
	my $iters = $#letters + 1;
	my @retval = ();
	if ($iters > 1) {
		while ($iters > 0 ) {
			my $letter = shift(@letters);
			my $others = join("",@letters);
			for my $result (&LoopLetters($others)) {
				push(@retval,"${letter}${result}");
			}
			push(@letters,$letter);
			$iters -= 1;
		}
	} else {
		push(@retval,"$_[0]");
	}
	return(@retval);
}

sub ReadDict() {
	open(DATA, "< $dictionary") or die "Failed to read '$dictionary': $!\n";
	while (defined(my $lin = <DATA>)) {
		chomp $lin;
		if (length($lin) == $numletters) {
			if ($nocase) {
				$dicthash{"\L$lin"} = $lin;
			} else {
				$dicthash{$lin} = $lin;
			}
		}
	}
	close(DATA);
}

sub ShowVersion() { # File sequence listing tool with compact sequence notation
	my @bpath = split /\//,$0;
	my $bfil = pop(@bpath);
	print STDOUT "\n$bfil: -\tDictionary word match Utility\n\nVersion $Revision\n\n";
	exit 0;
}

sub ShowHelp() { # Usage information:
	my @bpath = split /\//,$0;
	my $bfil = pop(@bpath);
	print STDOUT "\nReturn combinations of character strings.\n";
	print STDOUT "\nUsage: $bfil [option] pattern [pattern2...] \n";
	print STDOUT "\t-a\tReturn all possible permutations\n";
	print STDOUT "\t-u\tReturn only unique permutations\n";
	print STDOUT "\t-d\tReturn only permutations that are dictionary words. (Default Behavior)\n";
	print STDOUT "\t-c\tReturn only unique combinations of specified sub-group (do not permute these)\n";
	print STDOUT "\t-i\tCompare matches as case insensitive\n";
	print STDOUT "\t-n \$l\tReturn only results for sub group combinations of length \$l from pattern[s]\n";
	print STDOUT "\t-s\tSeparate output results for independent sub groups (Uses less RAM)\n";
	print STDOUT "\t-v\tVerbose output. Prints .'s when not separating sub-group output.\n";
	print STDOUT "\t\tPrint summaries when separating sub-group output.\n";
	print STDOUT "\t-h\tDisplay this help text.\n";
	print STDOUT "\t\tExample: $bfil nooni otto trhee tapeodr carephuta\n";
	exit 0;
}

sub ShowLicense() { # Copyright / License (Limit to 80 column output)
	print STDOUT "Copyright © 2010-2013 Victor E. Vaile, IV. All Rights Reserved.\n\n";
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
			if ($ARGV[0] =~ /^-a$/ ) {
				$retfull = 1;
				$retuniq = 0;
				$retdict = 0;
				shift(@ARGV);
			} elsif ($ARGV[0] =~ /^-u$/ ) {
				$retfull = 0;
				$retuniq = 1;
				$retdict = 0;
				shift(@ARGV);
			} elsif ($ARGV[0] =~ /^-d$/ ) {
				$retfull = 0;
				$retuniq = 0;
				$retdict = 1;
				shift(@ARGV);
			} elsif ($ARGV[0] =~ /^-c$/ ) {
				$conly = 1;
				shift(@ARGV);
			} elsif ($ARGV[0] =~ /^-i$/ ) {
				$nocase = 1;
				shift(@ARGV);
			} elsif ($ARGV[0] =~ /^-q$/ ) {
				$quiet = 1;
				shift(@ARGV);
			} elsif ($ARGV[0] =~ /^-v$/ ) {
				$verbose = 1;
				shift(@ARGV);
			} elsif ($ARGV[0] =~ /^-n$/ ) {
				shift(@ARGV);
				if (defined($ARGV[0]) && "$ARGV[0]" =~ /^[0-9]+$/ ) {
					$limit = $ARGV[0];
					shift(@ARGV);
				} else {
					print STDERR "";
				}
			} elsif ($ARGV[0] =~ /^-s$/ ) {
				$indep = 1;
				shift(@ARGV);
			} elsif ($ARGV[0] =~ /^--?ver(sion)?$/i) {
				shift(@ARGV);
				&ShowVersion();
			} elsif ($ARGV[0] =~ /^--?(copy|lic(ense)?)$/i) {
				shift(@ARGV);
				&ShowLicense();
			} elsif ($ARGV[0] =~ /^-(-){0,1}([Hh]|[Hh][Ee][Ll][Pp])$/ ) {
				&ShowHelp();
				shift(@ARGV);
			} else {
				push(@readlist,$ARGV[0]);
				shift(@ARGV);
			}
		}
	}
}

# main()
&ParseCommandLine;

if (! @readlist) {
	print STDERR "Nothing to process.\n";
	exit(1);
}

for my $jumble (@readlist) {
	my %seenhash = ();
	if ($nocase) {
		$jumble = "\L$jumble";
	}
	my $fullpatterns = 0;
	my $uniquepatterns = 0;
	my $realwords = 0;
	my $itfullpatterns = 0;
	my $ituniquepatterns = 0;
	my $itrealwords = 0;
	my $thislen = length($jumble);
	my $mjlen = $thislen;
	my @combolist = ($jumble);
	my $cn = "";
	if (($limit) && ($limit < $thislen)) {
		@combolist = &Combos(${limit},sort(split(//,$jumble)));
		$thislen = $limit;
		my $nums = $#combolist + 1;
		@combolist = &UniqeList(@combolist);
		if (($#combolist + 1) != $nums) {
			$cn = " (" . ($#combolist + 1) . " unique)";
		}
		if ((!$quiet) || ($conly)) {
			if ($conly) {
				if (!$quiet) {
					print STDOUT "Listing ${limit}-character combinations for string '$jumble':\n\n";
				}
			} else  {
				print STDOUT "Processing ${nums}${cn} ${limit}-character combinations for string '$jumble'\n";
			}
		}
	}
	if (($retdict) && ($thislen != $numletters)) {
		$numletters = $thislen;
		&ReadDict();
	}
	for my $jumblesub (@combolist){
		if ($conly) {
			print STDOUT "$jumblesub\n";
		} else {
			my $nlp = 0;
			if ((! $quiet) && ((!$limit) || ($limit >= $mjlen) || ($indep))) {
				print STDOUT "Processing '$jumblesub'\n";
			} elsif ((($limit) && ($limit < $mjlen)) && ($verbose) && (!$indep)) {
				print STDOUT ".";
				$nlp = 1;
			}
			for my $endresult (&LoopLetters($jumblesub)) {
				$fullpatterns += 1;
				if ($retfull) {
					if ($nlp) {
						print STDOUT "\n";
						$nlp = 0;
					}
					print STDOUT "$endresult\n";
				}
				if (! defined($seenhash{$endresult})) {
					$uniquepatterns += 1;
					$seenhash{$endresult} = $endresult;
					if ($retuniq) {
						if ($nlp) {
							print STDOUT "\n";
							$nlp = 0;
						}
						print STDOUT "$endresult\n";
					}
					if ($retdict) {
						if (defined($dicthash{$endresult})) {
							$realwords += 1;
							if ($nlp) {
								print STDOUT "\n";
								$nlp = 0;
							}
							print STDOUT "$dicthash{$endresult}\n";
						}
					}
				}
			}
			if ((!$quiet) && ($indep) && ($limit < $mjlen) ) {
				%seenhash = (); # Can make substantial difference in mem usage here.
				if ($verbose) {
					print STDOUT "\nSubgroup Patterns: $fullpatterns\nUnique Patterns: $uniquepatterns\n";
					if ($retdict) { print STDOUT "Real Words: $realwords\n\n";}
				}
				$itfullpatterns += $fullpatterns ;
				$ituniquepatterns += $uniquepatterns;
				$itrealwords += $realwords;
				$fullpatterns = 0;
				$uniquepatterns = 0;
				$realwords = 0;
			}
		}
	}
	if (($conly) && ($limit) && ($limit < $mjlen)) { # A little math, since we're not counting any output
		if (!$quiet) {
			my $pn = &Factorial($mjlen);
			my $pnk = $pn / &Factorial($mjlen - $limit);
			my $cnk = $pnk / &Factorial($limit); # Yes, we do know this already.
			print STDOUT "\n";
			print STDOUT "Permutations of $jumble ($mjlen):\t${pn}\n";
			print STDOUT "Permutations of $jumble, sub $limit:\t${pnk}\n";
			print STDOUT "Combinations of $jumble, sub $limit:\t${cnk}${cn}\n\n";
		}
		next;
	} elsif ($conly) {
		if ($limit == length($jumble)) {
			print STDOUT "The length of string '$jumble' is the same as the substring size requested ($limit).\n\n";
		} else {
			print STDOUT "There are no substrings of length $limit in string '$jumble'\n\n";
		}
		next;
	}
	if ((! $quiet) && ((!$indep) || ((!$limit) || ($limit >= $mjlen)))) {
		print STDOUT "\nTotal Patterns: $fullpatterns\nUnique Patterns: $uniquepatterns\n";
		if ($retdict) { print STDOUT "Real Words: $realwords\n";}
	} elsif ((!$quiet) && ($indep)) {
		print STDOUT "\n'$jumble' (Sub $limit) Stats:\nTotal Patterns: $itfullpatterns\nUnique Patterns: $ituniquepatterns\n";
		if ($retdict) { print STDOUT "Real Words: $itrealwords\n";}
	}
	print STDOUT "\n\n";
}

exit(0);

