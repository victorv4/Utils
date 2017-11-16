#!/usr/bin/perl -w

my $Revision = "1.02";
# IRIX style banner tool. Prints 8x8 block text
# representations of args or stdin with optional 
# terminal width specification. (8x8 includes spacing,
# although newlines are not actually space padded.)
# Text 'font' is theoretically 7x7 per character.
# Created by Victor E. Vaile, IV on 20101104
# 1.00 20101104	Initial Version
# 1.01 20101104	Added option to change character printed for 
# 		Matrix filler.
# 1.02 20130412	Added stty query for terminal width
#		Added option for explicit no query
#		Added option for version, license

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

my $tw = 120;
my %ar = ();
my $h = '#';
my $pm = "";
my $doletters = 0;
my @wordlist = ();
my $noquery = 0;
my @bpath = split /\//,$0;
my $bfil = pop(@bpath);

@{$ar{'0'}} = ("  ###   "," #   #  ","#     # ","#     # ","#     # "," #   #  ","  ###   ");
@{$ar{'1'}} = ("   #    ","  ##    "," # #    ","   #    ","   #    ","   #    "," #####  ");
@{$ar{'2'}} = (" #####  ","#     # ","      # "," #####  ","#       ","#       ","####### "); 
@{$ar{'3'}} = (" #####  ","#     # ","      # "," #####  ","      # ","#     # "," #####  "); 
@{$ar{'4'}} = ("#       ","#    #  ","#    #  ","#    #  ","####### ","     #  ","     #  "); 
@{$ar{'5'}} = ("####### ","#       ","#       ","######  ","      # ","#     # "," #####  "); 
@{$ar{'6'}} = (" #####  ","#     # ","#       ","######  ","#     # ","#     # "," #####  "); 
@{$ar{'7'}} = ("####### ","#    #  ","    #   ","   #    ","  #     ","  #     ","  #     "); 
@{$ar{'8'}} = (" #####  ","#     # ","#     # "," #####  ","#     # ","#     # "," #####  "); 
@{$ar{'9'}} = (" #####  ","#     # ","#     # "," ###### ","      # ","#     # "," #####  ");
@{$ar{'a'}} = (" "x8,"   ##   ","  #  #  "," #    # "," ###### "," #    # "," #    # ");
@{$ar{'b'}} = (" "x8," #####  "," #    # "," #####  "," #    # "," #    # "," #####  ");
@{$ar{'c'}} = (" "x8,"  ####  "," #    # "," #      "," #      "," #    # ","  ####  ");
@{$ar{'d'}} = (" "x8," #####  "," #    # "," #    # "," #    # "," #    # "," #####  ");
@{$ar{'e'}} = (" "x8," ###### "," #      "," #####  "," #      "," #      "," ###### ");
@{$ar{'f'}} = (" "x8," ###### "," #      "," #####  "," #      "," #      "," #      ");
@{$ar{'g'}} = (" "x8,"  ####  "," #    # "," #      "," #  ### "," #    # ","  ####  ");
@{$ar{'h'}} = (" "x8," #    # "," #    # "," ###### "," #    # "," #    # "," #    # ");
@{$ar{'i'}} = (" "x8,"    #   ","    #   ","    #   ","    #   ","    #   ","    #   ");
@{$ar{'j'}} = (" "x8,"      # ","      # ","      # ","      # "," #    # ","  ####  ");
@{$ar{'k'}} = (" "x8," #    # "," #   #  "," ####   "," #  #   "," #   #  "," #    # ");
@{$ar{'l'}} = (" "x8," #      "," #      "," #      "," #      "," #      "," ###### ");
@{$ar{'m'}} = (" "x8," #    # "," ##  ## "," # ## # "," #    # "," #    # "," #    # ");
@{$ar{'n'}} = (" "x8," #    # "," ##   # "," # #  # "," #  # # "," #   ## "," #    # ");
@{$ar{'o'}} = (" "x8,"  ####  "," #    # "," #    # "," #    # "," #    # ","  ####  ");
@{$ar{'p'}} = (" "x8," #####  "," #    # "," #    # "," #####  "," #      "," #      ");
@{$ar{'q'}} = (" "x8,"  ####  "," #    # "," #    # "," #  # # "," #   #  ","  ### # ");
@{$ar{'r'}} = (" "x8," #####  "," #    # "," #    # "," #####  "," #   #  "," #    # ");
@{$ar{'s'}} = (" "x8,"  ####  "," #      ","  ####  ","      # "," #    # ","  ####  ");
@{$ar{'t'}} = (" "x8,"  ##### ","    #   ","    #   ","    #   ","    #   ","    #   ");
@{$ar{'u'}} = (" "x8," #    # "," #    # "," #    # "," #    # "," #    # ","  ####  ");
@{$ar{'v'}} = (" "x8," #    # "," #    # "," #    # "," #    # ","  #  #  ","   ##   ");
@{$ar{'w'}} = (" "x8," #    # "," #    # "," #    # "," # ## # "," ##  ## "," #    # ");
@{$ar{'x'}} = (" "x8," #    # ","  #  #  ","   ##   ","   ##   ","  #  #  "," #    # ");
@{$ar{'y'}} = (" "x8,"  #   # ","   # #  ","    #   ","    #   ","    #   ","    #   ");
@{$ar{'z'}} = (" "x8," ###### ","     #  ","    #   ","   #    ","  #     "," ###### ");
@{$ar{'A'}} = ("   #    ","  # #   "," #   #  ","#     # ","####### ","#     # ","#     # ");
@{$ar{'B'}} = ("######  ","#     # ","#     # ","######  ","#     # ","#     # ","######  ");
@{$ar{'C'}} = (" #####  ","#     # ","#       ","#       ","#       ","#     # "," #####  ");
@{$ar{'D'}} = ("######  ","#     # ","#     # ","#     # ","#     # ","#     # ","######  ");
@{$ar{'E'}} = ("####### ","#       ","#       ","#####   ","#       ","#       ","####### ");
@{$ar{'F'}} = ("####### ","#       ","#       ","#####   ","#       ","#       ","#       ");
@{$ar{'G'}} = (" #####  ","#     # ","#       ","#  #### ","#     # ","#     # "," #####  ");
@{$ar{'H'}} = ("#     # ","#     # ","#     # ","####### ","#     # ","#     # ","#     # ");
@{$ar{'I'}} = ("  ###   ","   #    ","   #    ","   #    ","   #    ","   #    ","  ###   ");
@{$ar{'J'}} = ("      # ","      # ","      # ","      # ","#     # ","#     # "," #####  ");
@{$ar{'K'}} = ("#    #  ","#   #   ","#  #    ","###     ","#  #    ","#   #   ","#    #  ");
@{$ar{'L'}} = ("#       ","#       ","#       ","#       ","#       ","#       ","####### ");
@{$ar{'M'}} = ("#     # ","##   ## ","# # # # ","#  #  # ","#     # ","#     # ","#     # ");
@{$ar{'N'}} = ("#     # ","##    # ","# #   # ","#  #  # ","#   # # ","#    ## ","#     # ");
@{$ar{'O'}} = (" #####  ","#     # ","#     # ","#     # ","#     # ","#     # "," #####  ");
@{$ar{'P'}} = ("######  ","#     # ","#     # ","######  ","#       ","#       ","#       ");
@{$ar{'Q'}} = (" #####  ","#     # ","#     # ","#     # ","#   # # ","#    #  "," #### # ");
@{$ar{'R'}} = ("######  ","#     # ","#     # ","######  ","#   #   ","#    #  ","#     # ");
@{$ar{'S'}} = (" #####  ","#     # ","#       "," #####  ","      # ","#     # "," #####  ");
@{$ar{'T'}} = ("####### ","   #    ","   #    ","   #    ","   #    ","   #    ","   #    ");
@{$ar{'U'}} = ("#     # ","#     # ","#     # ","#     # ","#     # ","#     # "," #####  ");
@{$ar{'V'}} = ("#     # ","#     # ","#     # ","#     # "," #   #  ","  # #   ","   #    ");
@{$ar{'W'}} = ("#     # ","#  #  # ","#  #  # ","#  #  # ","#  #  # ","#  #  # "," ## ##  ");
@{$ar{'X'}} = ("#     # "," #   #  ","  # #   ","   #    ","  # #   "," #   #  ","#     # ");
@{$ar{'Y'}} = ("#     # "," #   #  ","  # #   ","   #    ","   #    ","   #    ","   #    ");
@{$ar{'Z'}} = ("####### ","     #  ","    #   ","   #    ","  #     "," #      ","####### ");
@{$ar{'!'}} = ("  ###   ","  ###   ","  ###   ","   #    ","        ","  ###   ","  ###   ");
@{$ar{'@'}} = (" #####  ","#     # ","# ### # ","# ### # ","# ####  ","#       "," #####  ");
@{$ar{'#'}} = ("  # #   ","  # #   ","####### ","  # #   ","####### ","  # #   ","  # #   ");
@{$ar{'$'}} = (" #####  ","#  #  # ","#  #    "," #####  ","   #  # ","#  #  # "," #####  ");
@{$ar{'%'}} = ("###   # ","# #  #  ","### #   ","   #    ","  # ### "," #  # # ","#   ### ");
@{$ar{'^'}} = ("   #    ","  # #   "," #   #  ","        ","        ","        ","        ");
@{$ar{'&'}} = ("  ##    "," #  #   ","  ##    "," ###    ","#   # # ","#    #  "," ###  # ");
@{$ar{'*'}} = ("        "," #   #  ","  # #   ","####### ","  # #   "," #   #  ","        ");
@{$ar{'('}} = ("   ##   ","  #     "," #      "," #      "," #      ","  #     ","   ##   ");
@{$ar{')'}} = ("  ##    ","    #   ","     #  ","     #  ","     #  ","    #   ","  ##    ");
@{$ar{' '}} = (" "x8," "x8," "x8," "x8," "x8," "x8," "x8);
@{$ar{"'"}} = ("  ###   ","  ###   ","   #    ","  #     ","        ","        ","        ");
@{$ar{'"'}} = ("### ### ","### ### "," #   #  ","        ","        ","        ","        ");
@{$ar{';'}} = ("  ###   ","  ###   ","        ","  ###   ","  ###   ","   #    ","  #     ");
@{$ar{':'}} = ("   #    ","  ###   ","   #    ","        ","   #    ","  ###   ","   #    ");
@{$ar{','}} = ("        ","        ","        ","  ###   ","  ###   ","   #    ","  #     ");
@{$ar{'.'}} = ("        ","        ","        ","        ","  ###   ","  ###   ","  ###   ");
@{$ar{'/'}} = ("      # ","     #  ","    #   ","   #    ","  #     "," #      ","#       ");
@{$ar{'?'}} = (" #####  ","#     # ","      # ","   ###  ","   #    ","        ","   #    ");
@{$ar{'<'}} = ("    #   ","   #    ","  #     "," #      ","  #     ","   #    ","    #   ");
@{$ar{'>'}} = ("  #     ","   #    ","    #   ","     #  ","    #   ","   #    ","  #     ");
@{$ar{'`'}} = ("  ###   ","  ###   ","   #    ","    #   ","        ","        ","        ");
@{$ar{'~'}} = (" ##     ","#  #  # ","    ##  ","        ","        ","        ","        ");
@{$ar{'-'}} = ("        ","        ","        "," #####  ","        ","        ","        ");
@{$ar{'_'}} = ("        ","        ","        ","        ","        ","        ","####### ");
@{$ar{'='}} = ("        ","        "," #####  ","        "," #####  ","        ","        ");
@{$ar{'+'}} = ("        ","   #    ","   #    "," #####  ","   #    ","   #    ","        ");
@{$ar{'['}} = (" #####  "," #      "," #      "," #      "," #      "," #      "," #####  ");
@{$ar{']'}} = (" #####  ","     #  ","     #  ","     #  ","     #  ","     #  "," #####  ");
@{$ar{'{'}} = ("  ###   "," #      "," #      ","##      "," #      "," #      ","  ###   ");
@{$ar{'}'}} = ("  ###   ","     #  ","     #  ","     ## ","     #  ","     #  ","  ###   ");
@{$ar{'\\'}} = ("#       "," #      ","  #     ","   #    ","    #   ","     #  ","      # ");
@{$ar{'|'}} = ("   #    ","   #    ","   #    ","        ","   #    ","   #    ","   #    ");

sub PrintString(@) {
	my @print = ();
	my $string = $_[0];
	for my $char (split(//,$string)) {
		if (defined($ar{$char})) {
			for my $n (0..6) {
				if ($doletters) {
					my $rc = $char;
					my $tmpch = "$ar{$char}[$n]";
					if ($pm) { $rc = $pm; }
					$tmpch =~ s/#/$rc/g;
					$print[$n] .= "$tmpch";
				} else {
					$print[$n] .= "$ar{$char}[$n]";
				}
			}
		} else {
			for my $x (0..6) {
				$print[$x] .= "."x8;
			}
		}
	}
	for my $l (@print) {
		print STDOUT "$l\n";
	}
	print STDOUT "\n";
}

sub Printer(@) {
	my $dostring = "";
	my $cw = $tw;
	my $docheck = 0;
	if (! $_[1]) {$docheck = 1;}
	for my $i (@_) {
		my $stl = length($i);
		$stl += 1;
		$stl *= 8;
		if (($docheck) && ($stl > $tw)) { #In case we get a single arg with spaces...
			if ($i =~ /\s/) {
				my @newprint = split(/\s/,$i);
				&Printer(@newprint);
				return 0;
			}
		}
		#print STDOUT "$i: $stl ($cw)\n";
		if ($cw >= $stl) {
			$cw -= $stl;
			$dostring.= "$i ";
		} else {
			$cw = $tw;
			&PrintString("$dostring");
			if ($stl > $tw) {
				&PrintString("$i ");
				$dostring = "";
			} else {
				$cw -= $stl;
				$dostring = "$i ";
			}
		}
	}
	if ($dostring) {
		&PrintString("$dostring");
	}
}

sub GetSTDIN() {
	while (defined(my $lin = <STDIN>)) {
		chomp $lin;
		my @words = split(/\s/,$lin);
		&Printer(@words);
	}
}

sub OptPrint(@) {
	my @opts = @_;
	my $fmt = "\t%-14s %s\n";
	printf STDOUT $fmt,@opts;
}

sub ShowVersion() { # Something to do...
	warn("$bfil Version $Revision\n");
	exit;
}

sub ShowHelp() { # Usage information:
	print STDOUT "\nUsage: $bfil [options] (text|STDIN)\n";
	&OptPrint("","Prints SGI IRIX style banner text, breaking lines");
	&OptPrint("","When possible at \$width characters.");
	&OptPrint("--w \$width","Specify \$w as width for terminal to break lines (implies --nq)");
	&OptPrint("--c [\$char]","Print \$char (if specified), or actual characters instead of '#'");
	&OptPrint("--nq","Do not query the terminal (stty)");
	&OptPrint("--h","Display this help text");
	&OptPrint("--version","Display Version.");
	&OptPrint("--license","Display Software License.");
	print STDOUT "\n\n";
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

sub ParseCommandLine() { # Options here will require explicit '--' so as not to limit possible banner text unnecessarily
	if (defined($ARGV[0])) {
		while (defined($ARGV[0]) && "$ARGV[0]" !~ /^$/ ) {
			if ($ARGV[0] =~ /^--w$/) {
				shift(@ARGV);
				if ($ARGV[0] =~ /^[0-9]+$/) {
					$tw = $ARGV[0];
					$noquery = 1;
					shift(@ARGV);
				} else {
					print STDERR "WARNING: Did not understand width $ARGV[0]\n";
					push(@wordlist,"--w"); #put it back...
				}
			} elsif ($ARGV[0] =~ /^--c$/ ) {
				shift(@ARGV);
				$doletters = 1;
				if ((defined($ARGV[0])) && ("$ARGV[0]" =~ /^.$/ )) { # A single character
					$pm = $ARGV[0];
					shift(@ARGV);
				}
			} elsif ($ARGV[0] =~ /^--n(o)?q(uery)?$/) {
				shift(@ARGV);
				$noquery = 1;
			} elsif ($ARGV[0] =~ /^--h(elp)?$/i) {
				if (($ARGV[0] =~ /^--/) || ($ARGV[0] =~ /elp/i)) {
					&ShowHelp("Undoc");
				} else {
					&ShowHelp();
				}
				shift(@ARGV);
			} elsif ($ARGV[0] =~ /^--lic(ense)?$/i) {
				shift(@ARGV);
				&ShowLicense();
			} elsif ($ARGV[0] =~ /^--version$/i) {
				shift(@ARGV);
				&ShowVersion();
			} else { # push to the array corresponding to set flag ( src rng lst vfy )
				push(@wordlist,$ARGV[0]);
				shift(@ARGV);
			}
		}
	}
}

&ParseCommandLine();
if (!$noquery) {
	$tw = &GetColSize();
}

if (@wordlist) {
	&Printer(@wordlist);
} elsif (! -t STDIN) {
	&GetSTDIN();
} else {
	print STDOUT "No Input!\n";
}

exit 0;

