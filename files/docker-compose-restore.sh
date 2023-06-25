#!/bin/bash -e

##############################################################
#
# Defining standard variables
#
##############################################################

# Set temporary PATH
export PATH=/bin:/usr/bin:/sbin:/usr/sbin:$PATH

# Get the name of the calling script
FILENAME=$(readlink -f $0)
BASENAME="${FILENAME##*/}"
BASENAME_ROOT=${BASENAME%%.*}
DIRNAME="${FILENAME%/*}"

# Get name of symlink used to execute
FILENAME1=$(realpath -s $0)
BASENAME1="${FILENAME1##*/}"
BASENAME1_ROOT=${BASENAME1%%.*}
DIRNAME1="${FILENAME1%/*}"

# Define temorary files, debug direcotory, config and lock file
TMPDIR=$(mktemp -d)
VARTMPDIR=/var/tmp
TMPFILE=${TMPDIR}/${BASENAME}.${RANDOM}.${RANDOM}
DEBUGDIR=${TMPDIR}/${BASENAME_ROOT}_${USER}
CONFIGFILE=${DIRNAME}/${BASENAME_ROOT}.cfg
LOCKFILE=${VARTMP}/${BASENAME_ROOT}.lck

# Logfile & directory
LOGDIR=$DIRNAME
LOGFILE=${LOGDIR}/${BASENAME_ROOT}.log

# Set date/time related variables
DATESTAMP=$(date "+%Y%m%d")
TIMESTAMP=$(date "+%Y%m%d.%H%M%S")

# Figure out the platform
OS=$(uname -s)

# Get the hostname
HOSTNAME=$(hostname -s)


##############################################################
#
# Defining custom variables
#
##############################################################


##############################################################
#
# Defining standarized functions
#
#############################################################

#FUNCTIONS=${DIRNAME}/functions.sh
#if [[ -f ${FUNCTIONS} ]]
#then
#   . ${FUNCTIONS}
#else
#   echo "Functions file '${FUNCTIONS}' could not be found!" >&2
#   exit 1
#fi


##############################################################
#
# Defining customized functions
#
#############################################################

function Usage
{

  cat << EOF | grep -v "^#"

$BASENAME

Usage : $BASENAME <flags> <arguments>

Flags :

   -d|--debug   : Debug mode (set -x)
   -D|--dry-run : Dry run mode
   -h|--help    : Prints this help message
   -v|--verbose : Verbose output

Arguments:
   \$1:          : Project name
   \$2:          : Backupfile to restore

Examples:

\$BASENAME wordpress /tmp/wordpress-20221231.tar.gz

EOF

}


##############################################################
#
# Main programs
#
#############################################################

# Make sure temporary files are cleaned at exit
trap 'rm -fr ${TMPDIR}' EXIT
trap 'exit 1' HUP QUIT KILL TERM INT

# Set the defaults
Debug_level=0
Verbose=false
Verbose_level=0
Dry_run=false
Echo=

# parse command line into arguments and check results of parsing
while getopts :dDhv-: OPT
do

  # Support long options
  if [[ $OPT = "-" ]] ; then
    OPT="${OPTARG%%=*}"       # extract long option name
    OPTARG="${OPTARG#$OPT}"   # extract long option argument (may be empty)
    OPTARG="${OPTARG#=}"      # if long option argument, remove assigning `=`
  fi

  case $OPT in
    d|debug)
      Verbose=true
      Verbose_level=2
      Verbose1="-v"
      Debug_level=$(( $Debug_level + 1 ))
      export Debug="set -vx"
      $Debug
      eval Debug${Debug_level}=\"set -vx\"
      ;;
    D|dry-run)
      Dry_run=true
      Dry_run1="-D"
      Echo=echo
      ;;
    h|help)
      Usage
      exit 0
      ;;
    v|verbose)
      Verbose=true
      Verbose_level=$(($Verbose_level+1))
      Verbose1="-v"
      ;;
    *)
      echo "Unknown flag -$OPT given!" >&2
      exit 1
      ;;
  esac

  # Set flag to be use by Test_flag
  eval ${OPT}flag=1

done
shift $(($OPTIND -1))

if [[ $# -ne 2 ]]
then
  Usage >&2
  exit 1
fi

Project=$1
File=$2

Tmpdir=$(mktemp -d)

# Extract backup to temporary location
tar -C $Tmpdir -xf $File

# 
Project_dir=/export/docker/${Project}
if [[ ! -d $Project_dir ]]
then
  mkdir -p $Project_dir
  chmod 750 $Project_dir
  chown root:root $Project_dir
fi

rsync -a $Tmpdir/project/ $Project_dir

# for Volume in `ls -d $Tmpdir/*/volumes/* | sed -r "s/.*\/([a-zA-Z0-9\-_]+)$/\\1/" | sort -u`
Volumes=`ls -d $Tmpdir/*/volumes/* 2>/dev/null`
for Volume in $Volumes
do
  echo "Processing volume '$Volume'"
  Vol=`echo $Volume | sed -r "s/.*\/([a-zA-Z0-9\-_]+)$/\\1/"` 
  docker volume create ${Vol}
  Path=$(docker volume inspect $Vol | jq -r '.[].Mountpoint')
  if [[ ! $Path =~ /var/lib/docker ]]
  then
    echo "Volume not in docker space!" >&2
    exit 1
  fi
  rsync -a ${Volume}/ $Path
done

# Delete tmpdir
rm -fr $Tmpdir
