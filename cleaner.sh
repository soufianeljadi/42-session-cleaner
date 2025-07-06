#!/bin/bash

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Function to get total disk free space
get_disk_free_space() {
    df -h ~ | awk 'NR==2 {print $4}'
}

# Function to get total cache size
get_cache_size() {
    du -sb ~/.cache/BraveSoftware ~/.var/app/com.brave.Browser/cache \
          ~/.config/Code/Cache ~/.config/Code/CachedData ~/.config/Code/User/workspaceStorage \
          ~/.config/Code/Service\ Worker/CacheStorage ~/.var/app/com.visualstudio.code/cache \
          ~/.cache/spotify ~/.var/app/com.spotify.Client/cache \
          ~/.var/app/com.discordapp.Discord/cache 2>/dev/null | awk '{total += $1} END {print total}'
}

# ASCII Art
echo -e "${YELLOW}"
cat << "EOF"
            _                    _  __
           | |_  ___ ._ _       / ||   |
           | . \/ ._>| ' |      | || / |
           |___/\___.|_|_|      |_|`___'

EOF
echo -e "${NC}"

# Save disk and cache size before
disk_before=$(get_disk_free_space)
cache_before=$(get_cache_size)


echo -e "${RED}✔ Storage before : ${NC}$disk_before ${RED}free ${BLUE}"

rm -rf ~/.cache/BraveSoftware
rm -rf ~/.var/app/com.brave.Browser/cache

rm -rf ~/.config/Code/Cache
rm -rf ~/.config/Code/CachedData
rm -rf ~/.config/Code/User/workspaceStorage
rm -rf ~/.config/Code/Service\ Worker/CacheStorage
rm -rf ~/.var/app/com.visualstudio.code/cache

rm -rf ~/.cache/spotify
rm -rf ~/.var/app/com.spotify.Client/cache

rm -rf ~/.var/app/com.discordapp.Discord/cache/*
rm -rf ~/.var/app/com.discordapp.Discord/cache

# Save disk and cache size after
disk_after=$(get_disk_free_space)
cache_after=$(get_cache_size)

# Calculate difference
cache_cleared=$((cache_before - cache_after))
cache_cleared_mb=$(echo "scale=2; $cache_cleared/1024/1024" | bc)

echo -e "${GREEN}✔ Storage after  : ${NC}$disk_after ${GREEN}free ${BLUE}"
