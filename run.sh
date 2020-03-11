#!/bin/bash

function flip_provider_cloudflare () {
  pair=$1
  SourceCluster=$2
  TargetCluster=$3
  cloudflare_auth_email=`kubectl get configmaps "$pair" -o json | jq .data.flip_provider_data.cloudflare_auth_email | tr -d '"'`
  cloudflare_auth_key=`kubectl get configmaps "$pair" -o json | jq .data.flip_provider_data.cloudflare_auth_key | tr -d '"'`
  zone=`kubectl get configmaps "$pair" -o json | jq .data.flip_provider_data.zone | tr -d '"'`
  dnsrecord=`kubectl get configmaps "$pair" -o json | jq .data.flip_provider_data.dnsrecord | tr -d '"'`
  ip=`kubectl get configmaps "$TargetCluster" -o json | jq .data.flip_provider_data.cloudflare_record | tr -d '"'`
  if [ "$LOGLEVEL" -ge 3 ]
  then
    echo "pair: $pair"
    echo "SourceCluster: $SourceCluster"
    echo "TargetCluster: $TargetCluster"
    echo "cloudflare_auth_email: $cloudflare_auth_email"
    echo "cloudflare_auth_key: $cloudflare_auth_key"
    echo "zone: $zone"
    echo "dnsrecord: $dnsrecord"
    echo "ip: $ip"
  fi
  # get the zone id for the requested zone
  zoneid=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones?name=$zone&status=active" \
  -H "X-Auth-Email: $cloudflare_auth_email" \
  -H "X-Auth-Key: $cloudflare_auth_key" \
  -H "Content-Type: application/json" | jq -r '{"result"}[] | .[0] | .id')
  echo "Zoneid for $zone is $zoneid"
  # get the dns record id
  dnsrecordid=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$zoneid/dns_records?type=CNAME&name=$dnsrecord" \
    -H "X-Auth-Email: $cloudflare_auth_email" \
    -H "X-Auth-Key: $cloudflare_auth_key" \
    -H "Content-Type: application/json" | jq -r '{"result"}[] | .[0] | .id')
  echo "DNSrecordid for $dnsrecord is $dnsrecordid"
  # update the record
  curl -s -X PUT "https://api.cloudflare.com/client/v4/zones/$zoneid/dns_records/$dnsrecordid" \
    -H "X-Auth-Email: $cloudflare_auth_email" \
    -H "X-Auth-Key: $cloudflare_auth_key" \
    -H "Content-Type: application/json" \
    --data "{\"type\":\"CNAME\",\"name\":\"$dnsrecord\",\"content\":\"$ip\",\"ttl\":1,\"proxied\":false}" | jq
}

function flip_dns () {
  pair=$1
  SourceCluster=$2
  TargetCluster=$3
  FlipProvider=`kubectl get configmaps "$pair" -o json | jq .data.flip_provider | tr -d '"'`
  if [ "$LOGLEVEL" -ge 3 ]
  then
    echo "pair: $pair"
    echo "SourceCluster: $SourceCluster"
    echo "TargetCluster: $TargetCluster"
    echo "FlipProvider: $FlipProvider"
  fi
  if [[ "$FlipProvider" == "cloudflare" ]]
  then
    echo "Using CloudFlare are Flip Provider"
    flip_provider_cloudflare $pair $SourceCluster $TargetCluster
  fi
}

function update_health_status () {
  TIMESTAMP="$(date +%s)"
  if [[ "$Preferred" == 'primary' ]]
  then
DATA="$(cat <<EOF
"data": {
  "primary_health_status": "$1",
  "primary_health_timestamp": "$TIMESTAMP"
}
EOF
)"
    kubectl -n cattle-rescue patch configmap "$pair" --type merge -p "$DATA"
  else [[ "$Preferred" == 'secondary' ]]
DATA="$(cat <<EOF
"data": {
  "primary_health_status": "$1",
  "primary_health_timestamp": "$TIMESTAMP"
}
EOF
)"
    kubectl -n cattle-rescue patch configmap "$pair" --type merge -p "$DATA"
  fi
}

function check_cluster_health () {
  echo "Checking cluster health..."
  kubectl --kubeconfig /tmp/"$pair"/"$1"/kube_config_cluster.yml get nodes
}

function bring_up_target_cluster () {
  pair=$1
  SourceCluster=$2
  TargetCluster=$3
  snapshot_name=$4
  if [ "$LOGLEVEL" -ge 3 ]
  then
    echo "pair: $pair"
    echo "SourceCluster: $SourceCluster"
    echo "TargetCluster: $TargetCluster"
    echo "snapshot_name: $snapshot_name"
  fi
  cd /tmp/"$pair"/"$TargetCluster"/
  DIR=$(echo /tmp/"$pair"/"$TargetCluster"/)
  if [[ ! "$(pwd)" == "$DIR" ]]
  then
    if [ "$LOGLEVEL" -ge 3 ]
    then
      echo "Requested dir: $DIR"
      echo "Current dir:" `pwd`
      sleep 60
    fi
    echo "Problem, TargetCluster dir is not right. Exiting"
    exit 2
  fi
  echo "Setting SSH access..."
  SSH_USER=`cat ./ssh-user`
  unlink /root/.ssh/id_rsa
  ln -s ./ssh-key /root/.ssh/id_rsa
  echo "Starting docker on $TargetCluster"
  for node in $(cat cluster.yml | grep ' address:' | awk '{print $3}')
  do
    echo "Node: $node"
    ssh "$SSH_USER"@$node "systemctl enable docker; systemctl start docker"
  done
  echo "Cleaning cluster..."
  for node in $(cat cluster.yml | grep ' address:' | awk '{print $3}')
  do
    ssh "$SSH_USER"@"$node" "curl https://raw.githubusercontent.com/rancherlabs/support-tools/master/extended-rancher-2-cleanup/extended-cleanup-rancher2.sh | bash"
  done
  echo "Rolling docker restart..."
  for node in $(cat cluster.yml | grep ' address:' | awk '{print $3}')
  do
    echo "Node: $node"
    ssh "$SSH_USER"@"$node" "systemctl restart docker"
    echo "Waiting for docker is to start..."
    while ! ssh "$SSH_USER"@"$node" "docker ps"
    do
      echo "Sleeping..."
    done
  done

  if [ "$LOGLEVEL" -ge 3 ]
    echo "Sleeping for 60..."
    sleep 60
  fi

  echo "Staring etcd restore..."
  rke etcd snapshot-restore --name "$snapshot_name"

  echo "Fixing tokens..."
  for namespace in kube-system cattle-system ingress-nginx
  do
    echo "namespace: $namespace"
    for token in $(kubectl --kubeconfig /tmp/"$pair"/"$TargetCluster"/kube_config_cluster.yml get secret -n $namespace | grep 'kubernetes.io/service-account-token' | awk '{print $1}')
    do
      kubectl --kubeconfig /tmp/"$pair"/"$TargetCluster"/kube_config_cluster.yml delete secret -n $namespace $token
    done
  done

  echo "Fixing canal..."
  for pod in $(kubectl --kubeconfig /tmp/"$pair"/"$TargetCluster"/kube_config_cluster.yml get pods -n kube-system -l k8s-app=canal -o name)
  do
    kubectl --kubeconfig /tmp/"$pair"/"$TargetCluster"/kube_config_cluster.yml -n kube-system delete --grace-period=0 --force $pod
  done

  echo "Fixing coredns..."
  for pod in $(kubectl --kubeconfig /tmp/"$pair"/"$TargetCluster"/kube_config_cluster.yml get pods -n kube-system -l k8s-app=kube-dns -o name)
  do
    kubectl --kubeconfig /tmp/"$pair"/"$TargetCluster"/kube_config_cluster.yml -n kube-system delete --grace-period=0 --force $pod
  done

  echo "Fixing coredns-autoscaler..."
  for pod in $(kubectl --kubeconfig /tmp/"$pair"/"$TargetCluster"/kube_config_cluster.yml get pods -n kube-system -l k8s-app=coredns-autoscaler -o name)
  do
    kubectl --kubeconfig /tmp/"$pair"/"$TargetCluster"/kube_config_cluster.yml -n kube-system delete --grace-period=0 --force $pod
  done

  echo "Fixing metrics-server..."
  for pod in $(kubectl --kubeconfig /tmp/"$pair"/"$TargetCluster"/kube_config_cluster.yml get pods -n kube-system -l k8s-app=metrics-server -o name)
  do
    kubectl --kubeconfig /tmp/"$pair"/"$TargetCluster"/kube_config_cluster.yml -n kube-system delete --grace-period=0 --force $pod
  done

  echo "Fixing rke jobs..."
  for job in $(kubectl --kubeconfig /tmp/"$pair"/"$TargetCluster"/kube_config_cluster.yml get job -n kube-system -o name | grep rke-)
  do
    kubectl --kubeconfig /tmp/"$pair"/"$TargetCluster"/kube_config_cluster.yml -n kube-system delete --grace-period=0 --force $job
  done

  echo "Fixing nginx-ingress..."
  for pod in $(kubectl --kubeconfig /tmp/"$pair"/"$TargetCluster"/kube_config_cluster.yml get pods -n ingress-nginx -l app=ingress-nginx -o name)
  do
    kubectl --kubeconfig /tmp/"$pair"/"$TargetCluster"/kube_config_cluster.yml -n ingress-nginx delete --grace-period=0 --force $pod
  done

  echo "Fixing rancher..."
  for pod in $(kubectl --kubeconfig /tmp/"$pair"/"$TargetCluster"/kube_config_cluster.yml get pods -n cattle-system -l app=rancher -o name)
  do
    kubectl --kubeconfig /tmp/"$pair"/"$TargetCluster"/kube_config_cluster.yml -n cattle-system delete --grace-period=0 --force $pod
  done

  echo "Fixing cattle-node-agent..."
  for pod in $(kubectl --kubeconfig /tmp/"$pair"/"$TargetCluster"/kube_config_cluster.yml get pods -n cattle-system -l app=cattle-agent -o name)
  do
    kubectl --kubeconfig /tmp/"$pair"/"$TargetCluster"/kube_config_cluster.yml -n cattle-system delete --grace-period=0 --force $pod
  done

  echo "Fixing cattle-cluster-agent..."
  for pod in $(kubectl --kubeconfig /tmp/"$pair"/"$TargetCluster"/kube_config_cluster.yml get pods -n cattle-system -l app=cattle-cluster-agent -o name)
  do
    kubectl --kubeconfig /tmp/"$pair"/"$TargetCluster"/kube_config_cluster.yml -n cattle-system delete --grace-period=0 --force $pod
  done

  echo "Rolling docker restart..."
  for node in $(cat cluster.yml | grep ' address:' | awk '{print $3}')
  do
    echo "Node: $node"
    ssh "$SSH_USER"@"$node" "systemctl restart docker"
    echo "Waiting for etcd is to start..."
    while ! ssh "$SSH_USER"@"$node" "docker inspect -f '{{.State.Running}}' etcd"
    do
      echo "Sleeping..."
    done
    echo "Sleeping for 5 seconds before moving to next node"
    sleep 5
  done

  echo "Running final rke up..."
  rke up

  echo "Updating kubeconfig in configmap..."
DATA="$(cat <<EOF
"data": {
  "kube_config_cluster.yml": "$(cat kube_config_cluster.yml)"
}
EOF
)"
  kubectl -n cattle-rescue patch configmap "$TargetCluster" --type merge -p "$DATA"

  check_cluster_health "$TargetCluster"
  if [ $? -eq 0 ]
  then
    echo "Cluster $TargetCluster is healthy"
  else
    echo "Cluster $TargetCluster is unhealthy"
  fi

echo "Updating configmap for active and preferred cluster in pair map"
DATA="$(cat <<EOF
"data": {
  "active": "$TargetCluster",
  "preferred": "$TargetCluster"
}
EOF
)"
  kubectl -n cattle-rescue patch configmap "$pair" --type merge -p "$DATA"

  echo "Failover completed successfully"
}

function soft_cluster_failover () {
  DATE=`date +%s`
  SourceCluster=$1
  TargetCluster=$2
  echo "Starting soft failover from $SourceCluster to $TargetCluster"
  cd /tmp/"$pair"/"$SourceCluster"/
  echo "Setting SSH access..."
  SSH_USER=`cat ./ssh-user`
  unlink /root/.ssh/id_rsa
  ln -s ./ssh-key /root/.ssh/id_rsa
  echo "Taking snapshot of $SourceCluster"
  snapshot_name=`echo CattleRescue-"$DATE"`
  rke etcd snapshot-save --name "$snapshot_name"
  echo "Shutting down docker on $SourceCluster"
  for node in $(cat cluster.yml | grep ' address:' | awk '{print $3}')
  do
    echo "Node: $node"
    ssh "$SSH_USER"@$node "systemctl disable docker; systemctl stop docker"
  done
  echo "Calling Flip Provider..."
  flip_dns $pair $SourceCluster $TargetCluster
  echo "Bring up target cluster..."
  bring_up_target_cluster $pair $SourceCluster $TargetCluster $snapshot_name
}

function hard_cluster_failover () {
  SourceCluster=$1
  TargetCluster=$2
  echo "Starting hard failover from $SourceCluster to $TargetCluster"
}

if [[ -z $CLUSTER_TIMEOUT ]]
then
	CLUSTER_TIMEOUT=360
  if [ "$LOGLEVEL" -ge 3 ]
  then
    echo "Cluster timeout: $CLUSTER_TIMEOUT"
  fi
fi

mkdir -p /root/.ssh

while true
do
  echo "Getting pairs..."
  for pair in $(kubectl get configmaps -o name | grep 'configmap/replication-' | awk -F '/' '{print $2}')
  do
    echo "Pair: $pair"
    mkdir -p /tmp/"$pair"

    if [ "$LOGLEVEL" -ge 3 ]
    then
      echo "Dumping configmap pair - Start"
      kubectl get configmaps "$pair" -o json
      echo "Dumping configmap pair - End"
    fi

    echo "Getting current active Cluster..."
    Preferred=`kubectl get configmaps "$pair" -o json | jq .data.preferred | tr -d '"'`
    if [[ "$Preferred" == 'primary' ]]
    then
      ActiveCluster=`kubectl get configmaps "$pair" -o json | jq .data.primary | tr -d '"'`
    fi

    if [[ "$Preferred" == 'secondary' ]]
    then
      ActiveCluster=`kubectl get configmaps "$pair" -o json | jq .data.secondary | tr -d '"'`
    fi

    echo "Current Active cluster: $ActiveCluster"

    if [ "$LOGLEVEL" -ge 3 ]
    then
      echo "Dumping configmap ActiveCluster - Start"
      kubectl get configmaps "$ActiveCluster" -o json
      echo "Dumping configmap ActiveCluster - End"
    fi

    mkdir -p /tmp/"$pair"/"$ActiveCluster"

    echo "Getting SSH User..."
    kubectl get configmaps "$ActiveCluster" -o json | jq -r .data.ssh_user > /tmp/"$pair"/"$ActiveCluster"/ssh-user

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
      count=0
      while true
      do
        check_cluster_health "$ActiveCluster"
        if [ $? -ne 0 ]
        then
          echo "Sleeping for $count seconds"
					sleep 1
					count=$((count+1))
        fi
        if [ $count -gt $CLUSTER_TIMEOUT ]
        then
          echo "Starting hard failover"
          hard_cluster_failover $ActiveCluster $PreferredCluster
          break
        fi
      done
    fi

    PreferredCluster=`kubectl get configmaps "$pair" -o json | jq .data.preferred | tr -d '"'`
    ActiveCluster=`kubectl get configmaps "$pair" -o json | jq .data.active | tr -d '"'`

    if [[ "$PreferredCluster" == "$ActiveCluster" ]]
    then
      echo "Preferred and Active match, no failover required"
    else
      echo "Preferred and Active do not match, need to do a soft failover."
      soft_cluster_failover $ActiveCluster $PreferredCluster
    fi

  done
  echo "Sleeping..."
  sleep 60
done
