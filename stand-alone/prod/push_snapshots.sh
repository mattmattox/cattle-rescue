#!/bin/bash

echo "Pushing snapshots..."
COUNTER=0
for node in $(cat cluster.yml | grep ' address:' | awk '{print $3}')
do
  echo "Node $node"
  ssh root@"$node" "mkdir -p /opt/rke/etcd-snapshots"
  rsync -avz --delete /root/RancherClusters/etcd-snapshots/"$COUNTER"/ root@"$node":/opt/rke/etcd-snapshots/
  let COUNTER=COUNTER+1
done

