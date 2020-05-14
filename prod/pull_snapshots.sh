#!/bin/bash

echo "Pulling snapshots..."
COUNTER=0
for node in $(cat cluster.yml | grep ' address:' | awk '{print $3}')
do
  echo "Node $node"
  mkdir -p /root/RancherClusters/etcd-snapshots/"$COUNTER"
  rsync -avz --delete root@"$node":/opt/rke/etcd-snapshots/ /root/RancherClusters/etcd-snapshots/"$COUNTER"/
  let COUNTER=COUNTER+1
done

