#!/bin/bash +x

function update_health_status () {
  TIMESTAMP="$(date +%s)"
  if [[ "$Preferred" == 'primary' ]]
  then
    kubectl -n cattle-rescue patch configmap "$pair" --type merge -p '{"data":{"primary_health_status":"$1"},{"primary_health_timestamp":"$TIMESTAMP"}}'
  else [[ "$Preferred" == 'secondary' ]]
    kubectl -n cattle-rescue patch configmap "$pair" --type merge -p '{"data":{"secondary_health_status":"$1"},{"secondary_health_timestamp":"$TIMESTAMP"}}'
  fi
}

function check_cluster_health () {
  echo "Checking cluster health..."
  kubectl --kubeconfig /tmp/"$pair"/"$1"/kube_config_cluster.yml cluster-info
}

function cluster_failover () {
  SourceCluster=$1
  TargetCluster=$2
  echo "Starting failover from $SourceCluster to $TargetCluster"
}

mkdir -p /root/.ssh

while true
do
  echo "Getting pairs..."
  for pair in $(kubectl get configmaps -o name | grep 'configmap/replication-' | awk -F '/' '{print $2}')
  do
    echo "Pair: $pair"
    mkdir -p /tmp/"$pair"

    echo "Getting current active Cluster..."
    Preferred=`kubectl get configmaps "$pair" -o json | jq .data.preferred | tr -d '"'`
    if [[ "$Preferred" == 'primary' ]]
    then
      ClusterActive=`kubectl get configmaps "$pair" -o json | jq .data.primary | tr -d '"'`
    fi

    if [[ "$Preferred" == 'secondary' ]]
    then
      ClusterActive=`kubectl get configmaps "$pair" -o json | jq .data.secondary | tr -d '"'`
    fi

    if [[ -z "$ClusterActive" ]]
    then
      echo "Error"
      continue
    fi
    echo "Current Active cluster: $ActiveCluster"

    echo "Getting SSH Key..."
    kubectl get configmaps "$ActiveCluster" -o json | jq -r .data.ssh_key > /tmp/"$pair"/"$ActiveCluster"/ssh-key
    chmod 400 /tmp/"$pair"/"$ActiveCluster"/ssh-key
    unlink /root/.ssh/id_rsa
    ln -s /tmp/"$pair"/"$ActiveCluster"/ssh-key /root/.ssh/id_rsa

    echo "Getting cluster.yml..."
    kubectl get configmaps "$ActiveCluster" -o json | jq -r .data.cluster_yml > /tmp/"$pair"/"$ActiveCluster"/cluster.yml

    echo "Getting cluster.rkestate..."
    kubectl get configmaps "$ActiveCluster" -o json | jq -r .data.cluster_rkestate > /tmp/"$pair"/"$ActiveCluster"/cluster.rkestate

    echo "Getting kube_config_cluster.yml..."
    kubectl get configmaps "$ActiveCluster" -o json | jq -r .data.kube_config_cluster_yml > /tmp/"$pair"/"$ActiveCluster"/kube_config_cluster.yml

    echo "Checking cluster health..."
    ActiveClusterStatus="UNKNOWN"
    check_cluster_health "$ActiveCluster"
    if [ $? -eq 0 ]
    then
      echo "Cluster $ActiveCluster is healthy"
      ActiveClusterStatus="OK"
      update_health_status "OK"
    else
      echo "Cluster $ActiveCluster is unhealthy"
      ActiveClusterStatus="CRITICAL"
      update_health_status "CRITICAL"
      #check_cluster_health "$ActiveCluster"
      #Need to setup hard failover
    fi

    ##Looking for soft failover event by comparing ActiveCluster and Preferred
    PreferredCluster=`kubectl get configmaps "$pair" -o json | jq .data.preferred | tr -d '"'`
    ActiveCluster=`kubectl get configmaps "$pair" -o json | jq .data.active | tr -d '"'`

    if [[ "$PreferredCluster" == "$ActiveCluster" ]]
    then
      echo "Preferred and Active match, no failover required"
    else
      echo "Preferred and Active do not match, need to failover."
      cluster_failover ()
    fi

    #echo "Running rke up..."
    #cd /tmp/"$pair"/"$ActiveCluster"/
    #rke up
    #cd ../

  done
  echo "Sleeping..."
  sleep 60
done