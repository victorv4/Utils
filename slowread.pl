#!/usr/bin/perl -w

my $Revision = '1.02';
# Slowly output contents of input file
# Useful for playback of script captures of
# terminal sessions where control characters
# make contents difficult to read, and cat plays 
# back erase characters such that data is over-
# written in the terminal
# Created by Victor E. Vaile, IV on 20120302
# 1.00 20120302	Initial Version
# 1.01 20120518	Added keyboard input/control Subroutines
# 1.02 20130414	Updated Version Header

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

my $filname = "/etc/motd";
#my $stime = 0.2; # Sleep time of 200 milliseconds
my $stime = 0.1; # Sleep time of 100 milliseconds
my $pause = 0;
my $bsdstyle = 1;
#my $system = `uname`;
# if ( "$system" =~ "FreeBSD" ) {
# 	$bsdstyle = 1;
# }
my @allkeys = ();
my $cpid = 0;

sub SetUp() { # Unbuffer keyboard, and do not print to the terminal
	if ($bsdstyle) {
		system("stty cbreak </dev/tty >/dev/tty 2>&1");
	} else {
		system("stty", "-icanon", "eol", "\001");
	}
	system("stty", "-echo");
}

sub CleanUp() {
	print STDOUT "\n";
	if ($bsdstyle) {
		system("stty -cbreak </dev/tty >/dev/tty 2>&1");
	} else {
		system("stty", "icanon", "eol", "^@");
	}
	system("stty", "echo");
}

sub CatchIntr() {
	my $sname = shift;
	print STDERR "\n\nCaught SIG$sname.\n";
	&CleanUp;
	if ($cpid) {
		kill(9,$cpid);
	}
	print STDERR "\nBailing.\n";
	exit 1;
}

sub SlowPrint($) {
	my $fil = $_[0];
	open(FH, "<  $fil") or die "ERROR: $fil: $!\n";
	while (defined(my $lin = <FH>)) {
		&GetKey();
		if ($pause) {
			if ($pause == 2) { # Print One line only
				$pause = 1;
			} else {
				while (($pause) && ($pause != 2)) {
					sleep 1;
					&GetKey();
				}
				if ($pause == 2) { # Print One line only
					$pause = 1;
				}
			}
		}
		print STDOUT $lin;
		if ($stime > 0) { # Behave like cat if we're not waiting...
			select(undef, undef, undef, $stime); # Hack for a more refined sleep effect
		}
	}
	close(FH);
}

sub Longer() {
	if ($stime <= 5) {
		$stime += .1;
	}
}

sub Shorter() {
	if ($stime > 0) {
		$stime -= .1;
	}
}

sub unorpause() {
	if ($pause) {
		$pause = 0;
	} else {
		$pause = 1;
	}
}

sub GetKey() {
	my @keys = ();
	my $nfound = 1; # Defined affirmatively once just to start the loop
	while ($nfound) {
		my $rin = '';
		vec($rin, fileno(FROM_CHILD), 1) = 1;
		$nfound = select($rin, undef, undef, 0);	# Just Poll ($nfound defined for real)
		if ($nfound) {
			my $lin = <FROM_CHILD>;
			push (@keys,$lin);
		}
	}
	for my $key (@keys) {
		if ("$key"  =~ / /) {
			&unorpause();
		} elsif ("$key"  =~ /\./) {
			$pause = 2;
		} elsif ("$key"  =~ /l/) {
			&Longer();
		} elsif ("$key"  =~ /s/) {
			&Shorter();
		} elsif ("$key"  =~ /q/) {
			&CleanUp();
			if ($cpid) {
				kill(9,$cpid);
			}
			exit;
		}
		push(@allkeys,$key);
	}
}

&SetUp();
pipe(FROM_CHILD,  TO_PARENT)    or die "pipe: $!";
select((select(TO_PARENT), $| = 1)[0]);  # autoflush
if (my $pid = fork) { # Parent Processes here:
	$cpid = $pid;
	$SIG{INT} = \&CatchIntr; # Clean logs first...
	$SIG{CHLD} = 'IGNORE'; # Hopefully it doesn't die...
	close(TO_PARENT); # We don't need these here.
	if (defined($ARGV[0])) {
		while (defined($ARGV[0]) && "$ARGV[0]" !~ /^$/ ) {
			if (-f $ARGV[0]) {
				&SlowPrint($ARGV[0]);
				shift @ARGV;
			} else {
				print STDOUT "ERROR: $ARGV[0] is not a file.\n";
			}
		}
	} else {
		&SlowPrint($filname);
	}
	close FROM_CHILD;
	kill(9, $pid);
} elsif (defined($pid)) { # Child Processes here.
	close(FROM_CHILD); # Not using these either.
	while (1) {
		my $klin = getc;
		print TO_PARENT "$klin\n";
	}
	exit 3; # Should not get here...
} else { # Failed outright...
	die "ERROR: fork failed. $!\n";
}
&CleanUp();
#print STDOUT "Done.\n";
#print STDOUT "@allkeys.\n";
exit 0;

