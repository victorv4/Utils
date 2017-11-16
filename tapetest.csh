#!/bin/csh -f

set revision = "1.0"
# TapeTest.csh v1.0
# Determine earliest combination of Tape block size / Read block size [dd]
# at which a tape can be read succesfully, up to reasonalble
# values for each attempted block size.
# Exit and report values upon first success. 
# 	--VEV,IV
# 	20120224 - Initial Version

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

set blk = 0
set blkadd = 1
set device = '/dev/nst0'
#set sleep = "sleep"	# Slow
set sleep = ": "	# Quick
#set upblk = 16384
set upblk = 32768
#set upbsz = 262144
set upbsz = 8388608	# BRU Defaults to 2097152

while($#argv >= 1)
	set opt = ${1}
	switch ( ${opt} )
		case [Hh]:
		case [Hh][Ee][Ll][Pp]:
		case -[Hh]:
		case -[Hh][Ee][Ll][Pp]:
			goto HELP
			breaksw
		case -[Vv][Ee][Rr]:
		case -[Vv][Ee][Rr][Ss][Ii][Oo][Nn]:
			goto VERSION
			breaksw
		case -[Ll][Ii][Cc]:
		case -[Ll][Ii][Cc][Ee][Nn][Ss][Ee]:
			goto LICENSE
			breaksw
		case -[Dd][Ee][Vv]:
		case -[Dd][Ee][Vv][Ii][Cc][Ee]:
			set device = ${2}
			shift
			shift
			breaksw
                default:
                        echo "$opt is an invalid option.  Use renfile -h for help."
                        exit 2
        endsw
end

alias rewind "mt -t $device rewind"
alias rexit "rewind ;exit"
alias tque 'echo "Do you want to continue testing for more valid read settings?";set ans = $<; if ($ans !~ [Yy]{,[Ee][Ss]}) eval rexit'

rewind

# Initial Quick Tests
while ($blk <= $upblk) 
	echo "Block Size $blk"
	mt -t $device setblk $blk
	# Initial test with no blocking factor supplied:
	foreach bs ( 20 40 60 80 3 5 6 7 9 10 ) # Most likely/low factors first...
		echo "BS: $bs (blk:$blk)"
		rewind
		dd if=$device bs=$bs of=/dev/null count=1
		if ($status == 0) then
			echo "Clean exit status with dd using read bs of $bs and tape block size of $blk"
			tque
		endif
	end
	set bs = 1
	while ($bs <= $upbsz) # Factors at values 2^(n<=18) <--[positive integers only]
		echo "BS: $bs (blk:$blk)"
		rewind
		dd if=$device bs=$bs of=/dev/null count=1
		if ($status == 0) then
			echo "Clean exit status with dd using read bs of $bs and tape block size of $blk"
			tque
		endif
		@ bs += $bs
		$sleep 1
	end
	@ blk += $blkadd
	set blkadd = $blk
end

echo "Brief tests completed with no valid reads.  Trying Exhaustive tests in 10 seconds."
echo "Block and factor powers of 2 <= $upblk"
sleep 8
echo "Single increment read sizes first)"
sleep 2

# single increment Read Size, 2^(n<=14) Block Size
set blk = 0
set blkadd = 1
#set upbsz = 262144
while ($blk <= $upblk) 
	echo "Block Size $blk"
	mt -t $device setblk $blk
	# Initial test with no blocking factor supplied:
	set bs = 1
	while ($bs <= $upbsz) # Factors at values 2^(n<=18) <--[positive integers only]
		echo "BS: $bs (blk:$blk)"
		rewind
		dd if=$device bs=$bs of=/dev/null count=1
		if ($status == 0) then
			echo "Clean exit status with dd using read bs of $bs and tape block size of $blk"
			tque
		endif
		@ bs += 1
		$sleep 1
	end
	@ blk += $blkadd
	set blkadd = $blk
end

echo "Now, Single increment Block sizes"
sleep 2
# single increment Block Size, 2^(n<=18) Read Size
#set upbsz = 8388608
set blk = 0
while ($blk <= $upblk) 
	echo "Block Size $blk"
	mt -t $device setblk $blk
	# Initial test with no blocking factor supplied:
	set bs = 1
	while ($bs <= $upbsz) # Factors at values 2^(n<=18) <--[positive integers only]
		echo "BS: $bs (blk:$blk)"
		rewind
		dd if=$device bs=$bs of=/dev/null count=1
		if ($status == 0) then
			echo "Clean exit status with dd using read bs of $bs and tape block size of $blk"
			tque
		endif
		@ bs += $bs
		$sleep 1
	end
	@ blk += 1
end

echo "Still No luck.  Trying Very Exhaustive tests in 10 seconds."
#set upbsz = 262144
sleep 10
set blk = 0
while ($blk <= $upblk) # blocksizes 0-$upblk
	echo "Block Size $blk"
	mt -t $device setblk $blk
	# Initial test with no blocking factor supplied:
	set bs = 1
	while ($bs <= $upbsz) # Factors at values 1-$upbsz
		echo "BS: $bs (blk:$blk)"
		rewind
		dd if=$device bs=$bs of=/dev/null count=1
		if ($status == 0) then
			echo "Clean exit status with dd using read bs of $bs and tape block size of $blk"
			tque
		endif
		@ bs += 1
		$sleep 1
	end
	@ blk += 1
end

echo "Sorry, no valid reads from block values tested."
exit


VERSION:
	printf "\n$0 - tape test utility (v.${revision} VEV,IV )\n\n";\
exit 0

HELP:
(	echo "";\
	echo "$0 - tape test utility (v.${revision} VEV,IV )";\
	echo "";\
	echo "usage: $0 [options]";\
	echo "";\
	echo "options: -h,-help	Display this help Dialogue.";\
	echo "";\
	echo "	 -m maxblk	Set max block to maxblk";\
	echo "";\
	echo "	 -d,-debug	Debug option.  Prints output without moving files.";\
	echo "	";\
	echo "	 -version	Display Software Version and exit";\
	echo "	";\
	echo "	 -license	Display Software License and exit";\
	echo "	";\
	echo "			Created 2000.06.04";\
	echo "			Last Revised ${revdate}";\
	echo "	";\
) | gmore
exit 0

LICENSE:
	printf "Copyright © 2008-2013 Victor E. Vaile, IV. All Rights Reserved.\n\n";
	printf "Redistribution and use in source and binary forms, with or without modification,\n";
	printf "are permitted provided that the following conditions are met:\n\n";
	printf "1. Redistributions of source code must retain the above copyright notice, this\n";
	printf "   list of conditions and the following disclaimer.\n\n";
	printf "2. Redistributions in binary form must reproduce the above copyright notice,\n";
	printf "   this list of conditions and the following disclaimer in the documentation\n";
	printf "   and/or other materials provided with the distribution.\n\n";
	printf "3. The name of the author may not be used to endorse or promote products derived\n";
	printf "   from this software without specific prior written permission.\n\n";
	printf 'THIS SOFTWARE IS PROVIDED BY THE AUTHOR \"AS IS\" AND ANY EXPRESS OR IMPLIED\n';
	printf "WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF\n";
	printf "MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT\n";
	printf "SHALL THE AUTHOR BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,\n";
	printf "EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT\n";
	printf "OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS\n";
	printf "INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN\n";
	printf "CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING\n";
	printf "IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY\n";
	printf "OF SUCH DAMAGE.\n\n";
	printf "* That being said, if you find a bug, feel free to report it to the author. :)\n\n";
exit 0;

