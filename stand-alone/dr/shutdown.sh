#!/bin/bash
#echo "rke remove..."
#rke remove
for node in $(cat cluster.yml | grep ' address:' | awk '{print $3}')
do
  ssh root@"$node" "systemctl stop docker"
done
