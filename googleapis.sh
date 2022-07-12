#!/usr/bin/env sh

###################################################################################
# Google Endpoint Scanner (GES)
# - Use this script to blacklist GDrive endpoints that have slow connections
# - This is done by adding one or more Google servers available at the time of
#   testing to this host's /etc/hosts file.
# - Run this script as a cronjob or any other way of automation that you feel
#   comfortable with.
###################################################################################
# Installation and usage:
# - install 'dig' and 'git';
# - in a dir of your choice, clone the repo that contains this script:
#   'git clone https://github.com/cgomesu/mediscripts-shared.git'
#   'cd mediscripts-shared/'
# - go over the non-default variables at the top of the script (e.g., REMOTE,
#   REMOTE_TEST_DIR, REMOTE_TEST_FILE, etc.) and edit them to your liking:
#   'nano googleapis.sh'
# - if you have not selected or created a dummy file to test the download
#   speed from your remote, then do so now. a file between 50MB-100MB should
#   be fine;
# - manually run the script at least once to ensure it works. using the shebang:
#   './googleapis.sh' (or 'sudo ./googleapis.sh' if not root)
#   or by calling 'sh' (or bash or whatever POSIX shell) directly:
#   'sh googleapis.sh' (or 'sudo sh googleapis.sh' if not root)
###################################################################################
# Noteworthy requirements:
# - rclone;
# - dig: in apt-based distros, install it via 'apt install dnsutils';
# - a dummy file on the remote: you can point to an existing file or create an
#                              empty one via 'fallocate -l 50M dummyfile' and
#                              then copying it to your remote.
###################################################################################
# Author: @cgomesu (this version is a rework of the original script by @Nebarik)
# Repo: https://github.com/cgomesu/mediscripts-shared
###################################################################################
# This script is POSIX shell compliant. Keep it that way.
###################################################################################

# uncomment and edit to set a custom name for the remote.
#REMOTE=""

# uncomment and edit to set a custom path to a config file. Default uses
# rclone's default ("$HOME/.config/rclone/rclone.conf").
#CONFIG=""

# uncomment to set the full path to the REMOTE directory containing a test file.
#REMOTE_TEST_DIR=""

# uncomment to set the name of a REMOTE file to test download speed.
#REMOTE_TEST_FILE=""

# Warning: be careful where you point the LOCAL_TMP dir because this script will
# delete it automatically before exiting!
# uncomment to set the LOCAL temporary root directory.
#LOCAL_TMP_ROOT=""

# uncomment to set the LOCAL temporary application directory.
#TMP_DIR=""

# uncomment to set a default criterion. this refers to the integer (in mebibyte/s, MiB/s) of the download
# rate reported by rclone. lower or equal values are blacklisted, while higher values are whitelisted.
# by default, script whitelists any connection that reaches any MiB/s speed above 0 (e.g., 1, 2, 3, ...).
#SPEED_CRITERION=5

# uncomment to append to the hosts file ONLY THE BEST whitelisted endpoint IP to the API address (single host entry).
# by default, the script appends ALL whitelisted IPs to the host file.
#USE_ONLY_BEST_ENDPOINT="true"

# uncomment to indicate the application to store blacklisted ips PERMANENTLY and use them to filter
# future runs. by default, blacklisted ips are NOT permanently stored to allow the chance that a bad server
# might become good in the future.
#USE_PERMANENT_BLACKLIST="true"

# uncomment and edit if using a permanent blacklist
#PERMANENT_BLACKLIST_DIR=""
#PERMANENT_BLACKLIST_FILE=""

# uncomment this option if you only want the script to edit the hosts file when the current host is unable
# to meet the speed criterion. this is useful to prevent the script from trying all possible IPs when the current
# one is still a valid (fast) server.
#USE_PRECHECK='true'

# uncomment to set a custom API address.
#CUSTOM_API=""

# full path to hosts file.
HOSTS_FILE="/etc/hosts"

# do NOT edit these variables.
DEFAULT_REMOTE="gcrypt"
DEFAULT_REMOTE_TEST_DIR="/tmp/"
DEFAULT_REMOTE_TEST_FILE="dummyfile"
DEFAULT_LOCAL_TMP_ROOT="/tmp/"
DEFAULT_LOCAL_TMP_DIR="ges/"
DEFAULT_SPEED_CRITERION=0
DEFAULT_PERMANENT_BLACKLIST_DIR="$HOME/"
DEFAULT_PERMANENT_BLACKLIST_FILE="blacklisted_google_ips"
DEFAULT_API="www.googleapis.com"
TEST_FILE="${REMOTE:-$DEFAULT_REMOTE}:${REMOTE_TEST_DIR:-$DEFAULT_REMOTE_TEST_DIR}${REMOTE_TEST_FILE:-$DEFAULT_REMOTE_TEST_FILE}"
API="${CUSTOM_API:-$DEFAULT_API}"
LOCAL_TMP="${LOCAL_TMP_ROOT:-$DEFAULT_LOCAL_TMP_ROOT}${TMP_DIR:-$DEFAULT_LOCAL_TMP_DIR}"
PERMANENT_BLACKLIST="${PERMANENT_BLACKLIST_DIR:-$DEFAULT_PERMANENT_BLACKLIST_DIR}${PERMANENT_BLACKLIST_FILE:-$DEFAULT_PERMANENT_BLACKLIST_FILE}"


# takes a status ($1) as arg. used to indicate whether to restore hosts file from backup or not.
cleanup () {
  # restore hosts file from backup before exiting with error
  if [ "$1" -ne 0 ] && check_root && [ -f "$HOSTS_FILE_BACKUP" ]; then
    cp "$HOSTS_FILE_BACKUP" "$HOSTS_FILE" > /dev/null 2>&1
  fi
  # append new blacklisted IPs to permanent list if using it and exiting wo error
  if [ "$1" -eq 0 ] && [ "$USE_PERMANENT_BLACKLIST" = 'true' ] && [ -f "$BLACKLIST" ]; then
    if [ -f "$PERMANENT_BLACKLIST" ]; then tee -a "$PERMANENT_BLACKLIST" < "$BLACKLIST" > /dev/null 2>&1; fi
  fi
  # remove local tmp dir and its files if the dir exists
  if [ -d "$LOCAL_TMP" ]; then
    rm -rf "$LOCAL_TMP" > /dev/null 2>&1
  fi
}

# takes msg ($1) and status ($2) as args
end () {
  cleanup "$2"
  echo '***********************************************'
  echo '* Finished Google Endpoint Scanner (GES)'
  echo "* Message: $1"
  echo '***********************************************'
  exit "$2"
}

start () {
  echo '***********************************************'
  echo '******** Google Endpoint Scanner (GES) ********'
  echo '***********************************************'
  msg "The application started on $(date)." 'INFO'
}

# takes message ($1) and level ($2) as args
msg () {
  echo "[GES] [$2] $1"
}

# checks user is root
check_root () {
  if [ "$(id -u)" -eq 0 ]; then return 0; else return 1; fi
}

# create temporary dir and files
create_local_tmp () {
  LOCAL_TMP_SPEEDRESULTS_DIR="$LOCAL_TMP""speedresults/"
  LOCAL_TMP_TESTFILE_DIR="$LOCAL_TMP""testfile/"
  mkdir -p "$LOCAL_TMP_SPEEDRESULTS_DIR" "$LOCAL_TMP_TESTFILE_DIR" > /dev/null 2>&1
  BLACKLIST="$LOCAL_TMP"'blacklist_api_ips'
  API_IPS="$LOCAL_TMP"'api_ips'
  touch "$BLACKLIST" "$API_IPS"
  RCLONE_LOG="$LOCAL_TMP"'rclone.log'
}

# hosts file backup
hosts_backup () {
  if [ -f "$HOSTS_FILE" ]; then
    HOSTS_FILE_BACKUP="$HOSTS_FILE"'.backup'
    if [ -f "$HOSTS_FILE_BACKUP" ]; then
      msg "Hosts backup file found. Restoring it." 'INFO'
      if ! cp "$HOSTS_FILE_BACKUP" "$HOSTS_FILE"; then return 1; fi
    else
      msg "Hosts backup file not found. Backing it up." 'WARNING'
      if ! cp "$HOSTS_FILE" "$HOSTS_FILE_BACKUP"; then return 1; fi
    fi
    return 0;
  else
    msg "The hosts file at $HOSTS_FILE does not exist." 'ERROR'
    return 1;
  fi
}

# takes a command as arg ($1)
check_command () {
  if command -v "$1" > /dev/null 2>&1; then return 0; else return 1; fi
}

# add/parse bad IPs to/from a permanent blacklist
blacklisted_ips () {
  API_IPS_PROGRESS="$LOCAL_TMP"'api-ips-progress'
  mv "$API_IPS_FRESH" "$API_IPS_PROGRESS"
  if [ -f "$PERMANENT_BLACKLIST" ]; then
    msg "Found permanent blacklist. Parsing it." 'INFO'
    while IFS= read -r line; do
      if validate_ipv4 "$line"; then
        # grep with inverted match
        grep -v "$line" "$API_IPS_PROGRESS" > "$API_IPS" 2>/dev/null
        mv "$API_IPS" "$API_IPS_PROGRESS"
      fi
    done < "$PERMANENT_BLACKLIST"
  else
    msg "Did not find a permanent blacklist at $PERMANENT_BLACKLIST. Creating a new one." 'WARNING'
    mkdir -p "$PERMANENT_BLACKLIST_DIR" 2>/dev/null
    touch "$PERMANENT_BLACKLIST" 2>/dev/null
  fi
  mv "$API_IPS_PROGRESS" "$API_IPS"
}

# copy file from remote to local and saves a log file of the operation
# returns error if unable to use rclone
rclone_copy () {
  if check_command "rclone"; then
    if [ -n "$CONFIG" ]; then
      rclone copy --config "$CONFIG" --log-file "$RCLONE_LOG" -v "${TEST_FILE}" "$LOCAL_TMP_TESTFILE_DIR"
    else
      rclone copy --log-file "$RCLONE_LOG" -v "${TEST_FILE}" "$LOCAL_TMP_TESTFILE_DIR"
    fi
  else
    msg "Rclone is not installed or is not reachable in this user's \$PATH." 'ERROR'
    return 1
  fi
  return 0
}

# parse rclone's log file for speed and update local files accordingly
rclone_parse_log () {
  if [ -f "$RCLONE_LOG" ]; then
    if grep -qi "failed" "$RCLONE_LOG"; then
      msg "Unable to connect with $IP." 'WARNING'
      return 1
    else
      msg "Parsing connection with $IP." 'INFO'
      SPEED_REGEX="[[:digit:]]+[[:punct:]]+[[:digit:]]+[[:space:]][[:alpha:]]*\/s"
      if grep -oE "$SPEED_REGEX" < "$RCLONE_LOG" > /dev/null 2>&1; then
        # found a valid speed transfer metric in the log
        SPEED=$(grep -oE "$SPEED_REGEX" < "$RCLONE_LOG")
        SPEED_METRIC=$(echo "$SPEED" | cut -f 2 -d ' ')
        SPEED_REAL=$(echo "$SPEED" | cut -f 1 -d ' ')
        # assume decimals separated by a dot
        SPEED_INT=$(echo "$SPEED" | cut -f 1 -d '.')
        # only whitelist M/Mi B/Bytes per second connections
        if [ "$SPEED_METRIC" = 'MiB/s' ] || [ "$SPEED_METRIC" = 'MiBytes/s' ] || [ "$SPEED_METRIC" = 'MB/s' ] || [ "$SPEED_METRIC" = 'MBytes/s' ]; then
          # use speed criterion to decide whether to whilelist or not
          if [ "$SPEED_INT" -gt "${SPEED_CRITERION:-$DEFAULT_SPEED_CRITERION}" ]; then
            # good endpoint
            msg "$SPEED. Above criterion endpoint. Whitelisting IP '$IP'." 'INFO'
            echo "$IP" | tee -a "$LOCAL_TMP_SPEEDRESULTS_DIR$SPEED_REAL" > /dev/null
            return 0
          else
            # below criterion endpoint
            msg "$SPEED. Below criterion endpoint. Blacklisting IP '$IP'." 'INFO'
            echo "$IP" | tee -a "$BLACKLIST" > /dev/null
            return 1
          fi
        elif [ "$SPEED_METRIC" = 'KiB/s' ] || [ "$SPEED_METRIC" = 'KiBytes/s' ] || [ "$SPEED_METRIC" = 'KB/s' ] || [ "$SPEED_METRIC" = 'KiBytes/s' ]; then
          msg "$SPEED. Abnormal endpoint. Blacklisting IP '$IP'." 'WARNING'
          echo "$IP" | tee -a "$BLACKLIST" > /dev/null
          return 1
        else
          # assuming it's either K/Kibi or M/Mi; else, parses as error and do nothing
          msg "Could not parse the transfer speed metric '$SPEED_METRIC'. Skipping IP '$IP'." 'WARNING'
          return 1
        fi
      else
        msg "Could not parse the IP '$IP'. Skipping it." 'WARNING'
        return 1
      fi
    fi
  else
    msg "Unable to find rclone's log file at '$RCLONE_LOG'." 'WARNING'
    return 1
  fi
}

# ip checker that tests Google endpoints for download speed.
# takes an IP addr ($1) and its name ($2) as args.
ip_checker () {
  IP="$1"
  NAME="$2"
  HOST="$IP $NAME"

  echo "$HOST" | tee -a "$HOSTS_FILE" > /dev/null 2>&1
  msg "Please wait. Downloading the test file from $IP... " 'INFO'

  # rclone download command
  if ! rclone_copy; then end 'Cannot continue. Fix the rclone issue and try again.' 1; fi

  # parse log file and ignore return status
  rclone_parse_log

  # local cleanup of tmp file and log
  rm "$LOCAL_TMP_TESTFILE_DIR${REMOTE_TEST_FILE:-$DEFAULT_REMOTE_TEST_FILE}" > /dev/null 2>&1
  rm "$RCLONE_LOG" > /dev/null 2>&1
  # restore hosts file from backup
  cp "$HOSTS_FILE_BACKUP" "$HOSTS_FILE" > /dev/null 2>&1
}

# precheck procedure
precheck () {
  if grep "$API" "$HOSTS_FILE" > /dev/null 2>&1; then
    # process host and test it
    IP=$(grep "$API" "$HOSTS_FILE" | cut -f 1 -d ' ' | head -1)
    msg "Please wait. Pre-checking download from '$IP'... " 'INFO'
    if ! rclone_copy; then end 'Cannot continue. Fix the rclone issue and try again.' 1; fi
    if rclone_parse_log; then
      msg "Precheck passed. Current host is still valid." 'INFO'
      return 0
    else
      msg "Precheck failed. Current host is no longer valid." 'WARNING'
      return 1
    fi
  else
    msg "Unable to find '$API' in the current hosts file. Skipping precheck." 'WARNING'
    return 1
  fi
}

# returns the fastest IP from speedresults
fastest_host () {
  LOCAL_TMP_SPEEDRESULTS_COUNT="$LOCAL_TMP"'speedresults_count'
  ls "$LOCAL_TMP_SPEEDRESULTS_DIR" > "$LOCAL_TMP_SPEEDRESULTS_COUNT"
  MAX=$(sort -nr "$LOCAL_TMP_SPEEDRESULTS_COUNT" | head -1)
  # same speed file can contain multiple IPs, so get whatever is at the top
  MACS=$(head -1 "$LOCAL_TMP_SPEEDRESULTS_DIR$MAX" 2>/dev/null)
  echo "$MACS"
}

# takes an address as arg ($1)
validate_ipv4 () {
  # lack of match in grep should return an exit code other than 0
  if echo "$1" | grep -oE "[[:digit:]]{1,3}.[[:digit:]]{1,3}.[[:digit:]]{1,3}.[[:digit:]]{1,3}" > /dev/null 2>&1; then
    return 0
  else
    return 1
  fi
}

# parse results and append only the best whitelisted IP to hosts
append_best_whitelisted_ip () {
  BEST_IP=$(fastest_host)
  if validate_ipv4 "$BEST_IP"; then
    msg "The fastest IP is $BEST_IP. Putting into the hosts file." 'INFO'
    echo "$BEST_IP $API" | tee -a "$HOSTS_FILE" > /dev/null 2>&1
  else
    msg "The selected '$BEST_IP' address is not a valid IP number." 'ERROR'
    end "Unable to find the best IP address. Original hosts file will be restored." 1
  fi
}

# parse results and append all whitelisted IPs to hosts
append_all_whitelisted_ips () {
  for file in "$LOCAL_TMP_SPEEDRESULTS_DIR"*; do
    if [ -f "$file" ]; then
      # same speed file can contain multiple IPs
      while IFS= read -r line; do
        WHITELISTED_IP="$line"
        if validate_ipv4 "$WHITELISTED_IP"; then
          msg "The whitelisted IP '$WHITELISTED_IP' will be added to the hosts file." 'INFO'
          echo "$WHITELISTED_IP $API" | tee -a "$HOSTS_FILE" > /dev/null 2>&1
        else
          msg "The whitelisted IP '$WHITELISTED_IP' address is not a valid IP number. Skipping it." 'WARNING'
        fi
      done < "$file"
    else
      msg "Did not find any whitelisted IP at '$LOCAL_TMP_SPEEDRESULTS_DIR'." 'ERROR'
      end "Unable to find whitelisted IP addresses. Original hosts file will be restored." 1
    fi
  done
}

############
# main logic
start

trap "end 'Received a signal to stop' 1" INT HUP TERM

# need root permission to write hosts
if ! check_root; then end "User is not root but this script needs root permission. Run as root or append 'sudo'." 1; fi

# prepare local files
create_local_tmp

if [ "$USE_PRECHECK" = 'true' ]; then
  if precheck; then end 'Skipping the more comprehensive endpoint scans because the current host is valid.' 0; fi
fi

# backup hosts file
if ! hosts_backup; then end "Unable to backup the hosts file. Check its path and continue." 1; fi

# prepare remote file
# TODO: (cgomesu) add function to allocate a dummy file in the remote

# start running test
if check_command "dig"; then
  # redirect dig output to tmp file to be parsed later
  API_IPS_FRESH="$LOCAL_TMP"'api-ips-fresh'
  dig +answer "$API" +short 1> "$API_IPS_FRESH" 2>/dev/null
else
  msg "The command 'dig' is not installed or not reachable in this user's \$PATH." 'ERROR'
  end "Install dig or make sure its executable is reachable, then try again." 1
fi

if [ "$USE_PERMANENT_BLACKLIST" = 'true' ]; then
  # bad IPs are permanently blacklisted
  blacklisted_ips
else
  # bad IPs are blacklisted on a per-run basis
  mv "$API_IPS_FRESH" "$API_IPS"
fi

while IFS= read -r line; do
  # checking each ip in API_IPS
  if validate_ipv4 "$line"; then ip_checker "$line" "$API"; fi
done < "$API_IPS"

# parse whitelisted IPs and edit hosts file accordingly
if [ "$USE_ONLY_BEST_ENDPOINT" = 'true' ]; then
  append_best_whitelisted_ip
else
  append_all_whitelisted_ips
fi

# end the script wo errors
end "Reached EOF without errors" 0
