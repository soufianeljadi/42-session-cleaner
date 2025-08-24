#!/bin/bash
#Author Omar BOUYKOURNE
#42login : obouykou

#banner
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

echo -e "${YELLOW}"
cat << "EOF"
            _                    _  __
           | |_  ___ ._ _       / ||   |
           | . \/ ._>| ' |      | || / |
           |___/\___.|_|_|      |_|`___'

EOF
echo -e "${NC}"

sleep 2
#!/bin/bash

# Get console session info
session_info=$(who | grep "console" | head -1)

if [ -z "$session_info" ]; then
    echo "0h 0m"
    exit 0
fi

# Parse: "sel-jadi console  Aug 24 10:58"
month=$(echo "$session_info" | awk '{print $3}')
day=$(echo "$session_info" | awk '{print $4}')
time_str=$(echo "$session_info" | awk '{print $5}')
year=$(date +%Y)

# Convert to epoch
session_start=$(date -j -f "%b %d %H:%M %Y" "$month $day $time_str $year" "+%s")

# Calculate
current_time=$(date +%s)
total_seconds=$((current_time - session_start))
idle_seconds=$(ioreg -c IOHIDSystem | awk '/HIDIdleTime/ {print int($NF/1000000000); exit}')
active_seconds=$((total_seconds - idle_seconds))
[ $active_seconds -lt 0 ] && active_seconds=0

# Output active time only
echo -e "${CYAN}logged about : ${NC} $((active_seconds / 3600))h $(( (active_seconds % 3600) / 60 ))m \n"
#update
if [ "$1" == "update" ];
then
	tmp_dir=".issent_wakha_daguis_t9ddart_ghina_ard_trmit_orra_tskert_zond_ism_yad_ikan_repo_gh_desktop_nk_achko_awldi_4ayad_yogguer_l'encrypting_n_2^10000_ghayad_aras_tinin_t''a.*\l7i?t_agmano_mohmad"
	if ! git clone --quiet https://github.com/ombhd/Cleaner_42.git "$HOME"/"$tmp_dir" &>/dev/null;
	then
		sleep 0.5
		echo -e "\033[31m\n           -- Couldn't update CCLEAN! :( --\033[0m"
		echo -e "\033[33m\n   -- Maybe you need to change your bad habits XD --\n\033[0m"
		exit 1
	fi
	sleep 1
	if [ "" == "$(diff "$HOME"/Cleaner_42.sh "$HOME"/"$tmp_dir"/Cleaner_42.sh)" ];
	then
		echo -e "\033[33m\n -- You already have the latest version of cclean --\n\033[0m"
		/bin/rm -rf "$HOME"/"${tmp_dir:?}"
		exit 0
	fi
	cp -f "$HOME"/"$tmp_dir"/Cleaner_42.sh "$HOME" &>/dev/null
	/bin/rm -rf "$HOME"/"${tmp_dir:?}" &>/dev/null
	echo -e "\033[33m\n -- cclean has been updated successfully --\n\033[0m"
	exit 0
fi
#calculating the current available storage
Storage=$(df -h "$HOME" | grep "$HOME" | awk '{print($4)}' | tr 'i' 'B')
if [ "$Storage" == "0BB" ];
then
	Storage="0B"
fi
echo -e "${RED}Before cleaning : ${NC}$Storage free\033[0m"


should_log=0
if [[ "$1" == "-p" || "$1" == "--print" ]]; then
	should_log=1
fi

function clean_glob {
	# don't do anything if argument count is zero (unmatched glob).
	if [ -z "$1" ]; then
		return 0
	fi

	if [ $should_log -eq 1 ]; then
		for arg in "$@"; do
			du -sh "$arg" 2>/dev/null
		done
	fi

	/bin/rm -rf "$@" &>/dev/null

	return 0
}

function clean {
	# to avoid printing empty lines
	# or unnecessarily calling /bin/rm
	# we resolve unmatched globs as empty strings.
	shopt -s nullglob

	echo -ne "\033[38;5;208m"

	#42 Caches
	clean_glob "$HOME"/Library/*.42*
	clean_glob "$HOME"/*.42*
	clean_glob "$HOME"/.zcompdump*
	clean_glob "$HOME"/.cocoapods.42_cache_bak*

	#Trash
	clean_glob "$HOME"/.Trash/*

	#General Caches files
	#giving access rights on Homebrew caches, so the script can delete them
	/bin/chmod -R 777 "$HOME"/Library/Caches/Homebrew &>/dev/null
	clean_glob "$HOME"/Library/Caches/*
	clean_glob "$HOME"/Library/Application\ Support/Caches/*

	#Slack, VSCode, Discord and Chrome Caches
	clean_glob "$HOME"/Library/Application\ Support/Slack/Service\ Worker/CacheStorage/*
	clean_glob "$HOME"/Library/Application\ Support/Slack/Cache/*
	clean_glob "$HOME"/Library/Application\ Support/discord/Cache/*
	clean_glob "$HOME"/Library/Application\ Support/discord/Code\ Cache/js*
	clean_glob "$HOME"/Library/Application\ Support/discord/Crashpad/completed/*
	clean_glob "$HOME"/Library/Application\ Support/Code/Cache/*
	clean_glob "$HOME"/Library/Application\ Support/Code/CachedData/*
	clean_glob "$HOME"/Library/Application\ Support/Code/Crashpad/completed/*
	clean_glob "$HOME"/Library/Application\ Support/Code/User/workspaceStorage/*
	clean_glob "$HOME"/Library/Application\ Support/Google/Chrome/Profile\ [0-9]/Service\ Worker/CacheStorage/*
	clean_glob "$HOME"/Library/Application\ Support/Google/Chrome/Default/Service\ Worker/CacheStorage/*
	clean_glob "$HOME"/Library/Application\ Support/Google/Chrome/Profile\ [0-9]/Application\ Cache/*
	clean_glob "$HOME"/Library/Application\ Support/Google/Chrome/Default/Application\ Cache/*
	clean_glob "$HOME"/Library/Application\ Support/Google/Chrome/Crashpad/completed/*

	#.DS_Store files
	clean_glob "$HOME"/Desktop/**/*/.DS_Store

	#tmp downloaded files with browsers
	clean_glob "$HOME"/Library/Application\ Support/Chromium/Default/File\ System
	clean_glob "$HOME"/Library/Application\ Support/Chromium/Profile\ [0-9]/File\ System
	clean_glob "$HOME"/Library/Application\ Support/Google/Chrome/Default/File\ System
	clean_glob "$HOME"/Library/Application\ Support/Google/Chrome/Profile\ [0-9]/File\ System

	#things related to pool (piscine)
	clean_glob "$HOME"/Desktop/Piscine\ Rules\ *.mp4
	clean_glob "$HOME"/Desktop/PLAY_ME.webloc

	echo -ne "\033[0m"
}
clean

if [ $should_log -eq 1 ]; then
	echo
fi

#calculating the new available storage after cleaning
Storage=$(df -h "$HOME" | grep "$HOME" | awk '{print($4)}' | tr 'i' 'B')
if [ "$Storage" == "0BB" ];
then
	Storage="0B"
fi
sleep 1
echo -e "\033[32mAfter cleaning : ${NC}$Storage free\n\033[0m"


#installer
