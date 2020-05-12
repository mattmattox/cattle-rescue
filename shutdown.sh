#!/bin/bash
cluster=$1

echo "Cluster: $cluster"
echo "Snapshot: $snapshot"

CPWD=`pwd`
cd /opt/cattle-rescue/config/"$cluster"/

echo "Stopping docker..."
for node in $(cat cluster.yml | grep ' address:' | awk '{print $3}')
do
  echo "Node: $node"
  ssh root@"$node" "systemctl stop docker"
done

cd $CPWD
