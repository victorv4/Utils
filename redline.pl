#!/usr/bin/perl -w

my $Revision = "1.01";
# Print a colored line across the terminal
# Since the terminal behaves differently 
# when printing a newline character
# depending on the status of the scrollback
# buffer, we're querying the terminal to 
# specify how many spaces to print.
# 1.00 20110719	Initial Version
# 1.01 20120412	Subroutines full rewrite

use strict 'vars';
use strict 'subs';

my %clrs = (
	"black"   => "0",
	"red"     => "1",
	"green"   => "2",
	"yellow"  => "3",
	"blue"    => "4",
	"magenta" => "5",
	"cyan"    => "6",
	"white"   => "7"
);

my $debug = 0;
my $bld = 0;
my $esc = "[";
my $fgclr = "3$clrs{red}";
my $bgclr = "";
my $linchar = "_";
my $dopad = 0;
my $padchar = " ";
my $pval = 1;
my $plin = "";
my @bpath = split /\//,$0;
my $bfil = pop(@bpath);
my $fgset = 0;
my $bgset = 0;

sub GetColSize() {
	my $size = `stty size`;
	my $exstat = $? >> 8;
	if ($exstat) {
		die "Failed to get tty size.\n$!\n";
	}
	my @szz = split(/[\s]+/,$size);
	my $cols = $szz[1];
	return $cols;
}

sub ShowVersion() { # Something to do...
	warn("$bfil Version $Revision\n");
	exit;
}

sub ShowHelp() {
	print STDOUT "\nUsage:\t$bfil: [options... ]\n";
	printf STDOUT "   %-12s%-10s   %s\n","-[-]fg"     ,"\$c"    ,"Specify color \$c for foreground";
	printf STDOUT "   %-12s%-10s   %s\n","-[-]bg"     ,"\$c"    ,"Specify color \$c for background";
	printf STDOUT "   %-12s%-10s   %s\n","-[-]bold"   ," "      ,"Use bold colors";
	printf STDOUT "   %-12s%-10s   %s\n","-[-]padval" ,"\$n"    ,"Specify value \$n to pad ends of line";
	printf STDOUT "   %-12s%-10s   %s\n","-[-]padchar","\$s"    ,"Specify character \$c for end of line padding";
	printf STDOUT "   %-12s%-10s   %s\n","-[-]linchar","\$s"    ,"Specify character \$c to repeat for line";
	if ($_[0]) {
		printf STDOUT "   %-12s%-10s   %s\n","-[-]debug"     ," "      ,"Print debugging output";
	}
	printf STDOUT "   %-12s%-10s   %s\n","-[-]version"," "      ,"Print Version exit.";
	printf STDOUT "   %-12s%-10s   %s\n","-[-]help"   ," "      ,"Print help text and exit.";
	printf STDOUT "   %-12s%-10s   %s\n","-[-]license"," "      ,"Display Software License.";
	print STDOUT "\n";
	exit 0;
}

sub ShowLicense() { # Copyright / License (Limit to 80 column output)
	print STDOUT "Copyright © 2011-2013 Victor E. Vaile, IV. All Rights Reserved.\n\n";
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

sub eDie(@) {
	print STDOUT "@_";
	exit 1;
}

sub ParseCommandLine() {
	if (defined($ARGV[0])) {
		while (defined($ARGV[0]) && "$ARGV[0]" !~ /^$/ ) {
			if ($ARGV[0] =~ /^--?debug$/i ) {
				$debug = 1;
				shift(@ARGV);
			} elsif ($ARGV[0] =~ /^--?h(elp)?$/i) {
				if (($ARGV[0] =~ /^--/) || ($ARGV[0] =~ /elp/i)) {
					&ShowHelp("Undoc");
				} else {
					&ShowHelp();
				}
				shift(@ARGV);
			} elsif ($ARGV[0] =~ /^--?v(ersion)?$/i) {
				shift(@ARGV);
				&ShowVersion();
			} elsif ($ARGV[0] =~ /^-?-?bold$/i) {
				shift(@ARGV);
				$bld = "1";
			} elsif ($ARGV[0] =~ /^--?pad$/i) {
				shift(@ARGV);
				$dopad = 1;
			} elsif ($ARGV[0] =~ /^--?nopad$/i) {
				shift(@ARGV);
				$dopad = 0;
			} elsif ($ARGV[0] =~ /^--?f(ore)?g(round)?$/i) {
				shift(@ARGV);
				$fgset = 1;
				if (defined($clrs{"\L$ARGV[0]"})) {
					$fgclr = "3" . $clrs{"\L$ARGV[0]"};
				} elsif ("$ARGV[0]" =~ /^none/i) {
					$fgclr = 0;
				} else {
					die "ERROR: $ARGV[0] is not a valid color (foreground)";
				}
				shift(@ARGV);
			} elsif ($ARGV[0] =~ /^--?b(ack)?g(round)?$/i) {
				shift(@ARGV);
				$bgset = 1;
				if (defined($clrs{"\L$ARGV[0]"})) {
					$bgclr = "4" . $clrs{"\L$ARGV[0]"};
				} elsif ("$ARGV[0]" =~ /^none/i) {
					$bgclr = 0;
				} else {
					die "ERROR: $ARGV[0] is not a valid color (background)";
				}
				shift(@ARGV);
			} elsif ($ARGV[0] =~ /^--?l(in)?c(har)?$/i) {
				shift(@ARGV);
				if ($ARGV[0] =~ /^.$/) {
					$linchar = "$ARGV[0]";
				} else {
					die "ERROR: Invalid option '$ARGV[0]' for Line Character.\n";
				}
				shift(@ARGV);
			} elsif ($ARGV[0] =~ /^--?p(ad)?c(har)?$/i) {
				shift(@ARGV);
				if ($ARGV[0] =~ /^.$/) {
					$padchar = "$ARGV[0]";
				} else {
					die "ERROR: Invalid option '$ARGV[0]' for Pad Character.\n";
				}
				shift(@ARGV);
			} elsif ($ARGV[0] =~ /^--?p(ad)?v(al)?$/i) {
				$dopad = 1;
				shift(@ARGV);
				if ($ARGV[0] =~ /^\d+$/) {
					$pval = $ARGV[0];
				} else {
					die "ERROR: Invalid value for Pad Value\n";
				}
				shift(@ARGV);
			} elsif (defined($clrs{"\L$ARGV[0]"})) {
				if (! $fgset) {
					$fgset = 1;
					$fgclr = "3" . $clrs{"\L$ARGV[0]"};
				} elsif (! $bgset) {
					$bgset = 1;
					$bgclr = "4" . $clrs{"\L$ARGV[0]"};
				} else {
					if ($debug) { print STDOUT "WARNING: Setting Foreground again.\n"; }
					$fgclr = "3" . $clrs{"\L$ARGV[0]"};
				}
				shift(@ARGV);
			} elsif ("$ARGV[0]" =~ /^none/i) {
				shift(@ARGV);
				if (! $fgset) {
					$fgset = 1;
					$fgclr = 0;
				} elsif (! $bgset) {
					$bgset = 1;
					$bgclr = 0;
				} else {
					if ($debug) { print STDOUT "WARNING: Setting Foreground again.\n"; }
					$fgclr = 0;
				}
			} elsif ($ARGV[0] =~ /^--?(copy|lic(ense)?)$/i) {
				shift(@ARGV);
				&ShowLicense();
			} else {
				print STDERR "Unknown Option: $ARGV[0]\n";
				shift(@ARGV);
			}
		}
	}
}

&ParseCommandLine();
my $cols = &GetColSize();
if ($dopad) {
	if (($pval * 2) >= $cols) {
		if ($debug) { print STDOUT "WARNING: All pad, no line\n"; }
		$pval = (($cols - 1) / 2) - .5;
		if ($debug) { print STDOUT "Temp PVAL is $pval\n"; }
		$pval = sprintf("%.0f",$pval);
		if ($debug) { print STDOUT "New PVAL is $pval\n"; }
	}
	$plin = $padchar x $pval;
	$cols -= (length($plin)*2); # We're padding the begin/end with spaces
}
my $clin = "$linchar" x $cols;
my $prn = "${plin}" . "${esc}${bld}";
if ($bgclr) {
	$prn .= ";$bgclr";
}
if ($fgclr) {
	$prn .= ";$fgclr";
}
$prn .= "m" . "${clin}${esc}0m${plin}\n";

if ($debug) {
	if ($dopad) { print STDOUT "('$padchar' x $pval)"; }
	print STDOUT "^[[";
	print STDOUT "$bld";
	if ($bgclr) { print STDOUT ";$bgclr"; }
	if ($fgclr) { print STDOUT ";$fgclr"; }
	print STDOUT "m";
	print STDOUT "('$linchar' x $cols)";
	print STDOUT "^[[0m";
	if ($dopad) { print STDOUT "('$padchar' x $pval)"; }
	print STDOUT "\\n\n";
}
print STDOUT "$prn";

exit 0;

