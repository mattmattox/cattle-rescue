#!/bin/bash

DATE=`date +%s`

Source=$1
Target=$2

read -p "Are you sure you want to failover from $Source to $Target ? " -n 1 -r
echo    # (optional) move to a new line
if [[ ! $REPLY =~ ^[Yy]$ ]]
then
  echo "Exited"
  exit 1
fi

echo "Taking snapshot of $Source..."
cd ./"$Source"/
rke etcd snapshot-save --name Cattle-DR-"$DATE"

echo "Shutting down "$Source"..."
./shutdown.sh
cd ../

echo "Flipping DNS to"$Target "..."
if [[ "$Target" == "dr" ]]
then
  ./cloudflare.sh "mmattox-dr-c734ba40bee15408.elb.us-west-1.amazonaws.com"
fi
if [[ "$Target" == "prod" ]]
then
  ./cloudflare.sh "mmattox-prod-00a56022affbac08.elb.us-east-1.amazonaws.com"
fi

echo "Starting up "$Target "..."
cd ./"$Target"/
./startup.sh Cattle-DR-"$DATE"
