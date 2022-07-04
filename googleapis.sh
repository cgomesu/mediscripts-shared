#!/usr/bin/env sh

###################################################################################
# Google Endpoint Scanner (GES)
# - Use this script to blacklist GDrive endpoints that have slow connections
# - This is done by adding the best GDrive server available at the time of testing
#   to this hosts /etc/hosts file.
# - Run this script as a cronjob or any other way of automation that you feel
#   comfortable with.
###################################################################################
# Noteworthy requirements:
# - rclone
# - dig
###################################################################################
# Author: @cgomesu (this version is a rework of the original script by @Nebarik)
# Repo: https://github.com/cgomesu/mediscripts-shared
###################################################################################
# This script is POSIX shell compliant. Keep it that way.
###################################################################################

# uncomment and edit to set a custom name for the remote.
#REMOTE="gcrypt-remote"
DEFAULT_REMOTE="gcrypt2"

# uncomment and edit to set a custom path to a config file. Default uses
# rclone's default ("$HOME/.config/rclone/rclone.conf").
#CONFIG="/home/cgomes/.config/rclone/rclone.conf"

# uncomment to set the full path to the REMOTE directory containing a test file.
#REMOTE_TEST_DIR="/"
DEFAULT_REMOTE_TEST_DIR="/temp/"

# uncomment to set the name of a REMOTE file to test download speed.
#REMOTE_TEST_FILE="dummyfile"
DEFAULT_REMOTE_TEST_FILE="dummythicc"

TEST_FILE="${REMOTE:-$DEFAULT_REMOTE}:${REMOTE_TEST_DIR:-$DEFAULT_REMOTE_TEST_DIR}${REMOTE_TEST_FILE:-$DEFAULT_REMOTE_TEST_FILE}"

# uncomment to set a custom API address.
#CUSTOM_API=""
DEFAULT_API="www.googleapis.com"

API="${CUSTOM_API:-$DEFAULT_API}"

# Warning: be careful where you point the LOCAL_TMP dir because this script will
# delete it automatically before exiting!
# uncomment to set the LOCAL temporary root directory.
#LOCAL_TMP_ROOT=""
DEFAULT_LOCAL_TMP_ROOT="/tmp/"

# uncomment to set the LOCAL temporary application directory.
#TMP_DIR=""
DEFAULT_LOCAL_TMP_DIR="ges/"

LOCAL_TMP="${LOCAL_TMP_ROOT:-$DEFAULT_LOCAL_TMP_ROOT}${TMP_DIR:-$DEFAULT_LOCAL_TMP_DIR}"

# full path to hosts file.
HOSTS_FILE="/etc/hosts"

# uncomment to set a default criterion. this refers to the integer (in MiB/s) of the download
# rate reported by rclone. lower or equal values are blacklisted, while higher values are whitelisted.
# by default, script whitelists any connection that reaches any MiB/s speed above 0 (e.g., 1, 2, 3, ...).
#SPEED_CRITERION='20'
DEFAULT_SPEED_CRITERION=0

# takes a status ($1) as arg. used to indicate whether to restore hosts file from backup or not.
cleanup () {
  if [ "$1" -ne 0 ] && check_root && [ -f "$HOSTS_FILE_BACKUP" ]; then
    # restore hosts file from backup before exiting with error
    cp "$HOSTS_FILE_BACKUP" "$HOSTS_FILE"
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

# blacklist IPs
blacklisted_ips () {
  API_IPS_PROGRESS="$LOCAL_TMP"'api-ips-progress'
  BLACKLIST="$LOCAL_TMP"'blacklist_apis'
  API_IPS="$LOCAL_TMP"'api_ips'
  mv "$API_IPS_FRESH" "$API_IPS_PROGRESS"
  touch "$BLACKLIST"
  while IFS= read -r bip; do
    grep -v "$bip" "$API_IPS_PROGRESS" > "$API_IPS" 2>/dev/null
    mv "$API_IPS" "$API_IPS_PROGRESS"
  done < "$BLACKLIST"
  mv "$API_IPS_PROGRESS" "$API_IPS"
}

# ip checker that tests Google endpoints for download speed.
# takes an IP addr ($1) and its name ($2) as args.
ip_checker () {
  IP="$1"
  NAME="$2"
  HOST="$IP $NAME"
  RCLONE_LOG="$LOCAL_TMP"'rclone.log'
  BLACKLIST="$LOCAL_TMP"'blacklist_apis'

  echo "$HOST" | tee -a "$HOSTS_FILE" > /dev/null 2>&1
  msg "Please wait. Downloading the test file from $IP... " 'INFO'

  # rclone download command
  if check_command "rclone"; then
    if [ -n "$CONFIG" ]; then
      rclone copy --config "$CONFIG" --log-file "$RCLONE_LOG" -v "${TEST_FILE}" "$LOCAL_TMP_TESTFILE_DIR"
    else
      rclone copy --log-file "$RCLONE_LOG" -v "${TEST_FILE}" "$LOCAL_TMP_TESTFILE_DIR"
    fi
  else
    msg "Rclone is not installed or is not reachable in this user's \$PATH." 'ERROR'
    end 'Cannot conitnue. Fix Rclone issue and try again.' 1
  fi

  # parse log file
  if [ -f "$RCLONE_LOG" ]; then
    if grep -qi "failed" "$RCLONE_LOG"; then
      msg "Unable to connect with $IP." 'WARNING'
    else
      msg "Parsing connection with $IP." 'INFO'
      # only whitelist MiB/s connections
      if grep -qi "MiB/s" "$RCLONE_LOG"; then
        SPEED=$(grep "MiB/s" "$RCLONE_LOG" | cut -d, -f3 | cut -c 2- | cut -c -5 | tail -1)
        # use speed criterion to decide whether to whilelist or not
        SPEED_INT="$(echo "$SPEED" | cut -f 1 -d '.')"
        if [ "$SPEED_INT" -gt "${SPEED_CRITERION:-$DEFAULT_SPEED_CRITERION}" ]; then
          # good endpoint
          msg "$SPEED MiB/s. Above criterion endpoint. Whitelisting IP '$IP'." 'INFO'
          echo "$IP" | tee -a "$LOCAL_TMP_SPEEDRESULTS_DIR$SPEED" > /dev/null
        else
          # below criterion endpoint
          msg "$SPEED MiB/s. Below criterion endpoint. Blacklisting IP '$IP'." 'INFO'
          echo "$IP" | tee -a "$BLACKLIST" > /dev/null
        fi
      elif grep -qi "KiB/s" "$RCLONE_LOG"; then
        SPEED=$(grep "KiB/s" "$RCLONE_LOG" | cut -d, -f3 | cut -c 2- | cut -c -5 | tail -1)
        msg "$SPEED KiB/s. Abnormal endpoint. Blacklisting IP '$IP'." 'WARNING'
        echo "$IP" | tee -a "$BLACKLIST" > /dev/null
      else
        # assuming it's either KiB/s or MiB/s, else parses as error and do nothing
        msg "Could not parse connection with IP '$IP'." 'WARNING'
      fi
    fi
    # local cleanup of tmp file and log
    rm "$LOCAL_TMP_TESTFILE_DIR${REMOTE_TEST_FILE:-$DEFAULT_REMOTE_TEST_FILE}" > /dev/null 2>&1
    rm "$RCLONE_LOG" > /dev/null 2>&1
  fi
  # restore hosts file from backup
  cp "$HOSTS_FILE_BACKUP" "$HOSTS_FILE" > /dev/null 2>&1
}

# returns the fastest IP from speedresults
fastest_host () {
  LOCAL_TMP_SPEEDRESULTS_COUNT="$LOCAL_TMP"'speedresults_count'
  ls "$LOCAL_TMP_SPEEDRESULTS_DIR" > "$LOCAL_TMP_SPEEDRESULTS_COUNT"
  MAX=$(sort -nr "$LOCAL_TMP_SPEEDRESULTS_COUNT" | head -1)
  MACS=$(cat "$LOCAL_TMP_SPEEDRESULTS_DIR$MAX" 2> /dev/null)
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

############
# main logic
start

trap "end 'Received a signal to stop' 1" INT HUP TERM

# need root permission to write hosts
if ! check_root; then end "User is not root but this script needs root permission. Run as root or append 'sudo'." 1; fi

# prepare local files
create_local_tmp
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

# backlist known bad IPs
blacklisted_ips

# checking each ip in API_IPS
while IFS= read -r line; do
  if validate_ipv4 "$line"; then ip_checker "$line" "$API"; fi
done < "$API_IPS"

# parse results and use the best endpoint
BEST_IP=$(fastest_host)
if validate_ipv4 "$BEST_IP"; then
  msg "The fastest IP is $BEST_IP. Putting into the hosts file." 'INFO'
  echo "$BEST_IP $API" | tee -a "$HOSTS_FILE" > /dev/null 2>&1
else
  msg "The selected '$BEST_IP' address is not a valid IP number." 'ERROR'
  end "Unable to find the best IP address. Original hosts file will be restored." 1
fi

# end the script wo errors
end "Reached EOF without errors" 0
