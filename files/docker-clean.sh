#!/bin/bash

# Get the name of the calling script
BASENAME="${0##*/}"
BASENAME_ROOT=${BASENAME%%.*}
DIRNAME=`dirname $0`

export PATH=/bin:/usr/bin:/sbin:/usr/sbin:$PATH:$DIRNAME

DOCKER_HOST=${DOCKER_HOST:-127.0.0.1}
DOCKER_PORT=${DOCKER_PORT:-2375}

DOCKER_PROTECT="zabbix-agent2"


function Usage
{

  cat << EOF | grep -v "^#"

$BASENAME

Usage : $BASENAME <flags>

Flags :

   -d          : Debug mode (set -x)
   -D          : Dry run mode
   -h          : Prints this help message
   -v          : Verbose output

   -c          : Clean all docker containers
   -i          : Clean all docker images
   -V          : Clean all volumes
   -p          : Execute system & network prune
   -s          : Use sudo

   -f <filter> : Only remove containers that have this string in the name
                 It will find containers that meet the requirements of this regex filter.
   -r          : Delete containers/images from remote host ($DOCKER_HOST)
   -R <host>   : Delete containers/images from remote host specified


Examples:

Clean all containers locally
\$ $BASENAME

Delete all containers & images remotely
\$ $BASENAME -r -c

Delete all containers remotely that have string 'abc123' in their name
\$ $BASENAME -r -f 'abc123'

EOF

}


Delete_containers=false
Delete_images=false
Delete_volumes=false
System_prune=false
Remote=false
Filter=""
Docker=docker
Tries=3
Sudo=
Verbose=true

# parse command line into arguments and check results of parsing
while getopts :cdDf:hirpR:svV OPT
do
   case $OPT in
     c) Delete_containers=true
        ;;
     d) set -vx
        ;;
     D) Dry_run=true
        Echo=echo
        ;;
     f) Filter="$OPTARG"
        ;;
     h) Usage >&2
        exit 0
        ;;
     i) Delete_images=true
        ;;
     p) System_prune=true
        ;;
     r) Remote=true
        Docker="docker --host tcp://${DOCKER_HOST}:${DOCKER_PORT}"
        ;;
     R) Remote=true
        Docker="docker --host tcp://${OPTARG}"
        ;;
     s) Sudo=sudo
        ;;
     v) Verbose=true
        ;;
     V) Delete_volumes=true
        ;;
     *) echo "Unknown flag -$OPT given!" >&2
        exit 1
        ;;
   esac

   # Set flag to be use by Test_flag
   eval ${OPT}flag=1

done
shift $(($OPTIND -1))

# Containers
if [[ $Delete_containers == true ]]
then
  echo "Show all running containers"
  $Sudo $Docker container ls

  echo "Stop all running containers"
  Containers=$($Sudo $Docker container ls -a | awk 'NR>1' | grep -E "$Filter" | grep -v -E "$DOCKER_PROTECT" | awk '{print $1}')
  [[ -n $Containers ]] && echo "$Containers" | xargs $Echo $Sudo $Docker container kill

  echo "Delete all containers"
  [[ -n $Containers ]] && echo "$Containers" | xargs $Echo $Sudo $Docker container rm
else
  echo "Skipping containers"
fi

# Images
if [[ $Delete_images == true ]]
then
  Try=1
  while [[ $Try -le $Tries ]]
  do
    echo "Delete all dockers images (attempt $Try)"
    Images=$($Sudo $Docker image ls -a | awk 'NR>1 {print $3}')
    [[ -n $Images ]] && echo "$Images" | xargs $Echo $Sudo $Docker image rm
    Try=$(($Try+1))
  done
else
  echo "Skipping images"
fi

# Volumes
if [[ $Delete_volumes == true ]]
then
  Try=1
  while [[ $Try -le $Tries ]]
  do
    echo "Delete all dockers volumes (attempt $Try)"
    Volumes=$($Sudo $Docker volume ls | awk 'NR>1 {print $2}')
    [[ -n $Volumes ]] && echo "$Volumes" | xargs $Echo $Sudo $Docker volume rm
    Try=$(($Try+1))
  done
else
  echo "Skipping volumes"
fi

# System / network prune
if [[ $System_prune == true ]]
then
  echo "Performing system prune"
  $Echo $Sudo $Docker system prune -a -f

  echo "Performing network prune"
  $Echo $Sudo $Docker network prune -f

else
  echo "Skipping system/network prune"
fi

if [[ $Verbose == true ]]
then
  echo "Current situtation:"
  echo "Containers"
  $Sudo $Docker container ls -a
  echo
  echo "Images"
  $Sudo $Docker image ls -a
  echo
  echo "Volumes"
  $Sudo $Docker volume ls
fi
