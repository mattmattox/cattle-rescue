#!/bin/bash
cluster=$1

echo "Cluster: $cluster"
echo "Snapshot: $snapshot"

CPWD=`pwd`
cd /opt/cattle-rescue/config/"$cluster"/

rke etcd snapshot-save --name "$snapshot"

cd $CPWD
