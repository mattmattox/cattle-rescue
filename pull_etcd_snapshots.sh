#!/bin/bash

Cluster=$1
for node in $(kubectl --kubeconfig kube_config_cluster.yml get nodes -l "node-role.kubernetes.io/etcd = true" -o name | awk -F'/' '{print $2}')
do
  echo "Node: $node"
  mkdir -p /opt/cattle-rescue/config/"$Cluster"/etcd-snapshots/"$node"/
  rsync -avz --progress --delete $node:/opt/rke/etcd-snapshots/ /opt/cattle-rescue/config/"$Cluster"/etcd-snapshots/"$node"/
done
