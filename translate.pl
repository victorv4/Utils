#!/usr/bin/perl -w

# Read in a tab/newline delimited table, and translate rows/columns

##     Copyright © 2000-2013 Victor E. Vaile, IV. All Rights Reserved.
## 
##     Redistribution and use in source and binary forms, with or without
##     modification, are permitted provided that the following conditions are met:
## 
##     1. Redistributions of source code must retain the above copyright notice,
##     this list of conditions and the following disclaimer.
## 
##     2. Redistributions in binary form must reproduce the above copyright
##     notice, this list of conditions and the following disclaimer in the
##     documentation and/or other materials provided with the distribution.
## 
##     3. The name of the author may not be used to endorse or promote products
##     derived from this software without specific prior written permission.
## 
##     THIS SOFTWARE IS PROVIDED BY THE AUTHOR "AS IS" AND ANY EXPRESS OR IMPLIED
##     WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF
##     MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO
##     EVENT SHALL THE AUTHOR BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
##     SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED
##     TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
##     PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
##     LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
##     NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
##     SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

sub ReadFileList($) { # Read file or STDIN contents into array
	my $readfil = $_[0];
	my @rtarray = ();
	my $FH = "STDIN";
	if ($readfil !~ /^-$/) {
		if (! -T $readfil) {
			print STDERR "ERROR: $readfil does not appear to be a text file.\n\n";
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

sub MaxFields(@) {
	my @input = @_;
	my $outnum = 0;
	for my $lin (@input) {
		my @fields  = split(/\t/,$lin);
		if ($#fields > $outnum) {
			$outnum = $#fields;
		}
	}
	return $outnum;
}

sub Translate(@) {
	my @input = @_;
	my $fields = &MaxFields(@input);
	my %hash = ();
	my @output = ();
	for my $lin (@input) {
		my @lvars = split(/\t/,$lin);
		while ($#lvars < $fields) {
			push (@lvars,"");
		}
		my $num = 0;
		while ($num <= $fields) {
			push (@{$hash{$num}},$lvars[$num]);
			$num ++;
		}
	}
	for my $key (sort { $a <=> $b } keys(%hash)) {
		my $nlin = join("\t",@{$hash{$key}});
		push (@output,$nlin);
	}
	return @output;
}


#main () 
if ($ARGV[0]) {
	my @trin = &ReadFileList($ARGV[0]);
	@trin = &Translate(@trin);
	for my $lin (@trin) {
		print STDOUT "$lin\n";
	}
} else {
	print STDERR "No input specified.\n";
	exit 1;
}

exit 0;

