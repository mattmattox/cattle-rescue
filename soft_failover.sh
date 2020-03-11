#!/bin/bash

pair=$1
TargetCluster=$2

if [[ -z $pair ]] || [[ -z $TargetCluster ]]
then
  echo "Missing pair and/or TargetCluster"
  exit 1
fi
DATA="$(cat <<EOF
"data": {
  "preferred": "$TargetCluster"
}
EOF
)"
kubectl -n cattle-rescue patch configmap "$pair" --type merge -p "$DATA"
