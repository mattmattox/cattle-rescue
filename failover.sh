#!/bin/bash

DATE=`date +%s`
snapshot=`echo Cattle-Rescue-"$DATE"`

usage()
{
cat << EOF
usage: $0 options
OPTIONS:
   -h      Show this message
   -S      Source Cluster
   -T      Target Cluster
EOF
}

VERBOSE=
InfraOnly=
Namespace=
while getopts .h:S.T:v. OPTION
do
     case $OPTION in
         h)
             usage
             exit 1
             ;;
         S)
             Source=$OPTARG
             ;;
         T)
             Target=$OPTARG
             ;;
         ?)
             usage
             exit
             ;;
     esac
done

read -p "Are you sure you want to failover from $Source to $Target ? " -n 1 -r
echo    # (optional) move to a new line
if [[ ! $REPLY =~ ^[Yy]$ ]]
then
  echo "Exited"
  exit 1
fi

echo "Taking snapshot of $Source..."
./snapshot.sh "$Source" "$snapshot"

echo "Shutting down "$Source"..."
./shutdown.sh "$Source"

echo "DNS Failover..."
./dns_failover.sh "$Source" "$Target"

echo "Starting up "$Target "..."
./startup.sh "$Target" Cattle-Rescue-"$DATE"
