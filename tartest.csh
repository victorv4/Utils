#!/bin/csh -f

# TarTest.csh v1.2
# Determine earliest combination of block size / blocking factor
# at which a tape can be extracted succesfully, up to reasonalble
# values for each attempted block size, then try dd for extraction.
# Exit and report values upon first success. 
# 	--VEV,IV
# 	20110623 - Initial Version
# 	20110816 - Added Exhaustive Tests

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
alias sitrep eval 'echo "" ; echo "Clean exit status with tar using blocking factor of $factor and block size of $blk"; echo ""'
alias tque 'echo "Do you want to continue testing for more valid read settings?";set ans = $<; if ($ans =~ [Yy]{,[Ee][Ss]}) exit'

mt -t $device rewind

while ($blk <= 16384) 
	echo "Block Size $blk"
	mt -t $device setblk $blk
	# Initial test with no blocking factor supplied:
	set factor = "[System Default]"
	echo "Factor $factor (blk:$blk)"
	tar -tvf $device
	if ($status == 0) then
		sitrep
		tque
	endif
	$sleep 1
	#foreach factor ( 3 5 7 9 10 20 40 60 80 ) # Possible/Probable low value factors !=2^(n>0)
	foreach factor ( 20 40 60 80 1 2 3 4 5 6 7 8 9 10 ) # Most likely/low factors first...
		echo "Factor $factor (blk:$blk)"
		mt -t $device rewind
		tar -b $factor -tvf $device
		if ($status == 0) then
			sitrep
			tque
		endif
		$sleep 1
	end
	#set factor = 1
	set factor = 16 # Now we're starting at 16--v
	while ($factor <= 8192) # Factors at values 2^(n<=13) <--[positive integers only]
		echo "Factor $factor (blk:$blk)"
		mt -t $device rewind
		tar -b $factor -tvf $device
		if ($status == 0) then
			sitrep
			tque
		endif
		@ factor += $factor
		$sleep 1
	end
	set bs = 1
	while ($bs <= 262144) # Factors at values 2^(n<=18) <--[positive integers only]
		echo "BS: $bs (blk:$blk)"
		mt -t $device rewind
		dd if=$device bs=$bs | tar tvf -
		if ($status == 0) then
			echo "Clean exit status with dd using bs of $bs and block size of $blk"
			tque
		endif
		@ bs += $bs
		$sleep 1
	end
	@ blk += $blkadd
	set blkadd = $blk
end

echo "Brief tests completed with no valid reads.  Trying Exhaustive tests in 10 seconds."
echo "Block and factor powers of 2 <= 16384"
sleep 10

set blk = 0
set blkadd = 1
while ($blk <= 16384) 
	echo "Block Size $blk"
	mt -t $device setblk $blk
	# Initial test with no blocking factor supplied:
	set factor = "[System Default]"
	echo "Factor $factor (blk:$blk)"
	tar -tvf $device
	if ($status == 0) then
		sitrep
		tque
	endif
	$sleep 1
	set factor = 1
	while ($factor <= 8192) # Factors at values 2^(n<=13) <--[positive integers only]
		echo "Factor $factor (blk:$blk)"
		mt -t $device rewind
		tar -b $factor -tvf $device
		if ($status == 0) then
			sitrep
			tque
		endif
		@ factor += $factor
		$sleep 1
	end
	set bs = 1
	while ($bs <= 262144) # Factors at values 2^(n<=18) <--[positive integers only]
		echo "BS: $bs (blk:$blk)"
		mt -t $device rewind
		dd if=$device bs=$bs | tar tvf -
		if ($status == 0) then
			echo "Clean exit status with dd using bs of $bs and block size of $blk"
			tque
		endif
		@ bs += $bs
		$sleep 1
	end
	@ blk += $blkadd
	set blkadd = $blk
end

echo "Still No luck.  Trying Very Exhaustive tests in 10 seconds."
sleep 10
set blk = 0
while ($blk <= 16384) # blocksizes 0-16384
	echo "Block Size $blk"
	mt -t $device setblk $blk
	# Initial test with no blocking factor supplied:
	set factor = "[System Default]"
	echo "Factor $factor (blk:$blk)"
	tar -tvf $device
	if ($status == 0) then
		sitrep
		tque
	endif
	$sleep 1
	set factor = 1
	while ($factor <= 8192) # Factors at values 1-8192
		echo "Factor $factor (blk:$blk)"
		mt -t $device rewind
		tar -b $factor -tvf $device
		if ($status == 0) then
			sitrep
			tque
		endif
		@ factor += 1
		$sleep 1
	end
	set bs = 1
	while ($bs <= 262144) # Factors at values 1-262144
		echo "BS: $bs (blk:$blk)"
		mt -t $device rewind
		dd if=$device bs=$bs | tar tvf -
		if ($status == 0) then
			echo "Clean exit status with dd using bs of $bs and block size of $blk"
			tque
		endif
		@ bs += 1
		$sleep 1
	end
	@ blk += 1
end

echo "Sorry, no valid reads from tar or dd."
exit

