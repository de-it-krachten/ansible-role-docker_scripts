#!/usr/bin/env bash

### Bash Environment Setup
# http://redsymbol.net/articles/unofficial-bash-strict-mode/
# https://www.gnu.org/software/bash/manual/html_node/The-Set-Builtin.html
# set -o xtrace
#set -o errexit
set -o errtrace
set -o nounset
set -o pipefail
#IFS=$'\n'

umask=027
backup_tool=tar
backup_time=$(date +"%Y%m%dT%H%M%S")
backup_dir="/export/backup"
backup_dir_tmp="/export/backup/tmp/$$"
backup_group=root

save_image=true
save_container_filesystem=true
pause=false
backup_dir_custom=false
period=once
restart=false
filename="\${project_name}.\${backup_time}.tar.gz"

# parse command line into arguments and check results of parsing
while getopts :b:dfg:ihn:pP:rt:u:-: OPT
do

  # Support long options
  if [[ $OPT = "-" ]] ; then
    OPT="${OPTARG%%=*}"       # extract long option name
    OPTARG="${OPTARG#$OPT}"   # extract long option argument (may be empty)
    OPTARG="${OPTARG#=}"      # if long option argument, remove assigning `=`
  fi

  case $OPT in
    b|backup_dir)
      backup_dir_custom=true
      backup_dir="$OPTARG"
      ;;
    d|debug)
      set -vx
      ;;
    f|skip-container-filesystem)
      save_container_filesystem=false
      ;; 
    g|group)
      backup_group=$OPTARG
      ;;
    h|help)
      Usage
      exit 0
      ;;
    i|skip-image)
      save_image=false
      ;;
    n|filename)
      filename="$OPTARG"
      ;;
    p|pause)
      pause=true
      ;;
    P|period)
      period=$OPTARG
      ;; 
    r|restart)
      restart=true
      ;;
    t|tool)
      backup_tool=$OPTARG
      backup_time=$(date +"%Y%m%d")
      ;; 
    u|umask)
      umask=$OPTARG
      ;;
    *)
      echo "Unknown flag -$OPT given!" >&2
      exit 1
      ;;
  esac

done
shift $(($OPTIND -1))

# Set umask
umask $umask

# Decide timestamp to use for duplicity backups
if [[ $backup_tool == duplicity ]]
then
  case $period in
    monthly)
      backup_time=$(date +"%Y-M%m")
      ;;
    weekly)
      backup_time=$(date +"%Y-W%U")
      ;;
    daily)
      backup_time=$(date +"%Y-%m-%d")
      ;;
    once) 
      backup_time=$(date +"%Y%m%dT%H%M%S")
      ;;
  esac
fi

# Fully backup a docker-compose project, including all images, named and unnamed volumes, container filesystems, config, logs, and databases. 
project_dir="${1:-$PWD}"
if [ -f "$project_dir/docker-compose.yml" ]; then
    echo "[i] Found docker-compose config at $project_dir/docker-compose.yml"
else
    echo "[X] Could not find a docker-compose.yml file in $project_dir"
    exit 1
fi

project_name=$(basename "$project_dir")

if [[ $backup_dir_custom == true ]] ; then
  backup_dir=${backup_dir}/${project_name}
else
  backup_dir=$(eval echo $backup_dir)
fi

# Source any needed environment variables
[ -f "$project_dir/docker-compose.env" ] && source "$project_dir/docker-compose.env"
[ -f "$project_dir/.env" ] && source "$project_dir/.env"

if [[ $restart == true ]]
then
  echo "[+] Restarting $project_name"
  cd $project_dir
  docker-compose down
  docker-compose up -d
  sleep 5
fi

echo "[+] Backing up $project_name project to $backup_dir_tmp"
mkdir -p "$backup_dir_tmp"

cd $project_dir

#echo "    - Saving docker-compose.yml config"
#cp "docker-compose.yml" "$backup_dir_tmp/docker-compose.yml"

# Copy all files
echo "    - Copy all files from project into backup directory"
[[ ! -d $backup_dir_tmp/project ]] && mkdir -p $backup_dir_tmp/project
rsync --delete -a $project_dir/ $backup_dir_tmp/project

# Optional: run a command inside the contianer to dump your application's state/database to a stable file
echo "    - Saving application state to ./dumps"
mkdir -p "$backup_dir_tmp/dumps"
# your database/stateful service export commands to run inside docker go here, e.g.
#   docker-compose exec postgres env PGPASSWORD="$POSTGRES_PASSWORD" pg_dump -U "$POSTGRES_USER" "$POSTGRES_DB" | gzip -9 > "$backup_dir/dumps/$POSTGRES_DB.sql.gz"
#   docker-compose exec redis redis-cli SAVE
#   docker-compose exec redis cat /data/dump.rdb | gzip -9 > "$backup_dir/dumps/redis.rdb.gz"

# Optional: pause the containers before backing up to ensure consistency
if [[ $pause == true ]]; then
  docker-compose pause
fi

for service_name in $(docker-compose config --services); do
    image_id=$(docker-compose images -q "$service_name")
    image_name=$(docker image inspect --format '{{json .RepoTags}}' "$image_id" | jq -r '.[0]')
    container_id=$(docker-compose ps -q "$service_name")

    service_dir="${backup_dir_tmp}/${service_name}"
    [[ ! -d service_dir ]] && mkdir -p $service_dir
    echo $service_dir = $service_dir
    echo "[*] Backing up ${project_name}__${service_name} to ./$service_name..."
    mkdir -p "$service_dir"
    
    # save image
    if [[ $save_image == true ]]; then
      echo "    - Saving $image_name image to ./$service_name/image.tar"
      docker save --output "$service_dir/image.tar" "$image_id"
    else
      echo "    - Skip saving $image_name image"
    fi
    
    if [[ -z "$container_id" ]]; then
        echo "    - Warning: $service_name has no container yet."
        echo "         (has it been started at least once?)"
        continue
    fi

    # save config
    echo "    - Saving container config to ./$service_name/config.json"
    docker inspect "$container_id" > "$service_dir/config.json"

    # save logs
    echo "    - Saving stdout/stderr logs to ./$service_name/docker.{out,err}"
    docker logs "$container_id" > "$service_dir/docker.out" 2> "$service_dir/docker.err"

    # save data volumes
    volume_dir=$service_dir/volumes
    mkdir -p "$volume_dir"
    # for source in $(docker inspect -f '{{range .Mounts}}{{println .Name .Source}}{{end}}' "$container_id"); do
    docker inspect -f '{{range .Mounts}}{{println .Name .Source}}{{end}}' "$container_id" | \
    while read name source; do
        [[ $source == "" ]] && continue
        #@# echo "    - Saving volume '$name'"
        echo "    - Saving volume '$name' to '$volume_dir/$name'"
        mkdir -p $(dirname "$volume_dir")
        rsync --delete -a "$source/" "$volume_dir/$name"
        #tar -C $source -zcf $volume_dir/${name}.tar.gz .
    done

    # save container filesystem
    if [[ $save_container_filesystem == true ]]; then
      echo "    - Saving container filesystem to ./$service_name/container.tar"
      docker export --output "$service_dir/container.tar" "$container_id"
    else
      echo "    - Skip saving container filesystem"
    fi

    # save entire container root dir
    #@# echo "    - Saving container root to $service_dir/root"
    echo "    - Saving container root to $service_dir/root"
    rsync --delete -a "/var/lib/docker/containers/$container_id" "$service_dir/root"
done

echo "[*] Ensure backup location is present and hold the correct permissions"
[[ ! -d $backup_dir ]] && mkdir -p $backup_dir
chmod 2750 $backup_dir

case $backup_tool in
  tar)
    eval filename="${filename}"
    echo "[*] Compressing backup folder to ${backup_dir}/${filename}.tar.gz"
    tar -C $backup_dir_tmp -zcf "${backup_dir}/${filename}.tar.gz" --totals .
    ;;
  duplicity)
    echo "[*] Creating bachup using duplicity"
    #duplicity --verbosity info . file://${backup_dir}/${backup_time} --no-encryption
    duplicity . file://${backup_dir}/${project_name}.${backup_time} --no-encryption --volsize 100
    ;;
  *)
    echo "Unsupported backup tool '$backup_tool' specified!" >&2
    exit 1
    ;;
esac

echo "[*] Adjusting group ownership"
chgrp -R $backup_group $backup_dir

echo "[√] Finished Backing up $project_name"

# Resume the containers if paused above
if [[ $pause == true ]]; then
  docker-compose unpause
fi

rm -fr $backup_dir_tmp
