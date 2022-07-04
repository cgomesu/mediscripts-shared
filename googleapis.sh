
#!/bin/bash

#---------#
# Read me #
#---------#

# This script will check the download speed from the different Google endpoints and then set your Hosts file with it.
# For the testfile, if it's too small it will download too quickly for the rclone.log to get a good read on it.
# Bigger the better as Google Drive ramps up speed as it goes, however slow endpoints will take forever. I recommend roughly 50MB.
# Create a file with this command: "fallocate -l 50M dummythicc"
# If you get the error "tmpapi/speedresults is a directory", this means the didn't find a speed measured in MiB/s, generally safe to ignore unless you are expecting GiB/s.

#-----------------#
# Edit these bits #
#-----------------#

testfile='gcrypt2:/temp/dummythicc'
api=www.googleapis.com

#-------------------#
# Hosts file backup #
#-------------------#

for f in /etc/hosts.backup; do
	if [ -f "$f" ]; then
		printf "Hosts backup file found - restoring\n"
		sudo cp $f /etc/hosts
		break
	else
		printf "Hosts backup file not found - backing up\n"
		sudo cp /etc/hosts $f
		break
	fi
done

#-----------------#
# Diggity dig dig #
#-----------------#

mkdir tmpapi
mkdir tmpapi/speedresults/
mkdir tmpapi/testfile/
dig +answer $api +short > tmpapi/api-ips-fresh


#------------------------#
# Backlist Known Bad IPs #
#------------------------#

mv tmpapi/api-ips-fresh tmpapi/api-ips-progress
touch .blacklist-apis
blacklist=.blacklist-apis
while IFS= read -r bip; do
        grep -v "$bip" tmpapi/api-ips-progress > tmpapi/api-ips
        mv tmpapi/api-ips tmpapi/api-ips-progress
done < "$blacklist"
mv tmpapi/api-ips-progress tmpapi/api-ips

#--------------#
# Colour codes #
#--------------#

RED='\033[1;31m'
YEL='\033[1;33m'
GRN='\033[0;32m'
NC='\033[0m'

#------------------#
# Checking each ip #
#------------------#

input=tmpapi/api-ips
while IFS= read -r ip; do
	hostsline="$ip\t$api"
	sudo -- sh -c -e "echo '$hostsline' >> /etc/hosts"
	printf "Please wait, downloading the test file from $ip... "
	rclone copy --log-file tmpapi/rclone.log -v "${testfile}" tmpapi/testfile
		if grep -q "KiB/s" tmpapi/rclone.log; then
		speed=$(grep "KiB/s" tmpapi/rclone.log | cut -d, -f3 | cut -c 2- | cut -c -5 | tail -1)
	        printf "${RED}$speed KiB/s${NC} - Blacklisting\n"
        	rm -r tmpapi/testfile
	        rm tmpapi/rclone.log
		echo "$ip" >> .blacklist-apis
		sudo cp /etc/hosts.backup /etc/hosts
		else
	speed=$(grep "MiB/s" tmpapi/rclone.log | cut -d, -f3 | cut -c 2- | cut -c -5 | tail -1)
	printf "${GRN}$speed MiB/s${NC}\n"
	echo "$ip" >> tmpapi/speedresults/$speed
	rm -r tmpapi/testfile
	rm tmpapi/rclone.log
	sudo cp /etc/hosts.backup /etc/hosts
	fi
done < "$input"

#-----------------#
# Use best result #
#-----------------#

ls tmpapi/speedresults > tmpapi/count
max=$(sort -nr tmpapi/count | head -1)
macs=$(cat tmpapi/speedresults/$max)
printf "${YEL}The fastest IP is $macs at a speed of $max | putting into hosts file\n"
hostsline="$macs\t$api"
sudo -- sh -c -e "echo '$hostsline' >> /etc/hosts"

#-------------------#
# Cleanup tmp files #
#-------------------#

rm -r tmpapi
