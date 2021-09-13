#!/bin/bash

# For keeping multiple versions of movies and shows in their folders. 
# Enable recycling bin in Sonarr and Radarr, fill in the folders below and run.
# Script checks if folder in recycling folder matches one in the media directories then copies the contents over to it. 

# Modify folder names for the below
recycling="/media/gcrypt2/temp"
movies="/media/gcrypt2/Movies/"
animemovies="/media/gcrypt2/Anime-Movies/"
anime="/media/gcrypt2/Anime/"
documentaryfilms="/media/gcrypt2/Documentary-Films/"
nonfiction="/media/gcrypt2/Non-Fiction-Shows/"
standupspecials="/media/gcrypt2/Standup-Specials/"
comedianshows="/media/gcrypt2/Comedian-Shows/"
tvshows="/media/gcrypt2/TV Shows/"
skip1="temp"
skip2="Emby-backups"


# Colours!

RED='\033[1;31m'
YEL='\033[0;33m'
GRN='\033[0;32m'
ORN='\033[0;33m'
NC='\033[0m'
BLK='\033[0;30m'
BLE='\033[0;34m'
PLP='\033[0;35m'
CYN='\033[0;36m'
WHT='\033[0;37m'


# Where the magic happens

find $recycling -maxdepth 1 -type d | while read f

do
for d in ...
  do
      foldernames=${f##*/}
# Known ignore
      if [[ "${foldernames}" == "${skip1}" ]]
      then
      printf "${RED}[Skipping]:${NC} ${foldernames}\n"
      elif [[ "${foldernames}" == "${skip2}" ]]
      then
      printf "${RED}[Skipping]:${NC} ${foldernames}\n"
# Standard
      elif [ -d "${movies}${foldernames}" ]
      then
      printf "${GRN}[Moving to Movies]:${NC} ${foldernames}\n"
      rclone move gcrypt2:/temp/"${foldernames}" gcrypt2:/Movies/"${foldernames}"
      elif [ -d "${tvshows}${foldernames}" ]
      then
      printf "${GRN}[Moving to TV Shows]:${NC} ${foldernames}\n"
      rclone move gcrypt2:/temp/"${foldernames}" gcrypt:/TV\ Shows/"${foldernames}"
# Anime
      elif [ -d "${animemovies}${foldernames}" ]
      then
      printf "${ORN}[Moving to Anime-Movies]:${NC} ${foldernames}\n"
      rclone move gcrypt2:/temp/"${foldernames}" gcrypt2:/Anime-Movies/"${foldernames}"
      elif [ -d "${anime}${foldernames}" ]
      then
      printf "${ORN}[Moving to Anime]:${NC} ${foldernames}\n"
      rclone move gcrypt2:/temp/"${foldernames}" gcrypt2:/Anime/"${foldernames}"
# Docus
      elif [ -d "${documentaryfilms}${foldernames}" ]
      then
      printf "${PLP}[Moving to Documentary-Films]:${NC} ${foldernames}\n"
      rclone move gcrypt2:/temp/"${foldernames}" gcrypt2:/Documentary-Films/"${foldernames}"
      elif [ -d "${nonfiction}${foldernames}" ]
      then
      printf "${PLP}[Moving to Non-Fiction Shows]:${NC} ${foldernames}\n"
      rclone move gcrypt2:/temp/"${foldernames}" gcrypt2:/Non-Fiction-Shows/"${foldernames}"
# Comedy
      elif [ -d "${standupspecials}${foldernames}" ]
      then
      printf "${CYN}[Moving to Standup-Specials]:${NC} ${foldernames}\n"
      rclone move gcrypt2:/temp/"${foldernames}" gcrypt2:/Standup-Specials/"${foldernames}"
      elif [ -d "${comedianshows}${foldernames}" ]
      then
      printf "${CYN}[Moving to Comedian-Shows]:${NC} ${foldernames}\n"
      rclone move gcrypt2:/temp/"${foldernames}" gcrypt2:/Comedian-Shows/"${foldernames}"
# Unknown ignore
      else
      printf "${RED}[Not Found]:${NC} ${foldernames}\n"
      fi
  done
done
exit
