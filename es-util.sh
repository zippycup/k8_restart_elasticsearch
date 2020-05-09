#!/bin/bash

# implementation of : https://www.elastic.co/guide/en/elasticsearch/reference/current/restart-cluster.html

node_regex='^es-'

disable_shard=$(cat << EOF
{
  "persistent": {
    "cluster.routing.allocation.enable": "primaries"
  }
}
EOF
)

enable_shard=$(cat << EOF
{
  "persistent": {
    "cluster.routing.allocation.enable": null
  }
}
EOF
)

usage() {
  echo "usage: sh $0 -m [mode] -n [namespace]"
  echo "mode: restart|enable_shard|disable_shard|get_nodes|node_status|health"
  echo
  exit 0
}

set_nodes() {
  echo "get nodes/set host ..."
  nodes=`kubectl -n ${namespace} get pod | grep ${node_regex} | awk '{print $1}'| sort`
  
  tmphost=`kubectl -n ${namespace} exec -it es-master-0 -- curl http://localhost:9200/_cat/nodes | grep '\*' | awk '{print $10}' | sed 's/\r$//g'`
  host=${tmphost::${#tmphost}-1}

  echo "set initial node: ${host}"
  if [ x"${host}" == "x" ]
  then
    echo "initial host not found in ${nodes}"
    exit 1
  fi
}

get_health() {
  kubectl -n ${namespace} exec -it ${host} -- curl http://localhost:9200/_cluster/health?pretty
}

health() {
  parm1=$1
  mode=$2

  case ${parm1} in
    status) good_health='"green"'
    ;;
    unassigned_shards) good_health="0"
    ;;
    *) echo "invalid parameter ${parm1}"
       exit
    ;;
   esac
  health_value=`kubectl -n ${namespace} exec -it ${host} -- curl http://localhost:9200/_cluster/health?pretty | jq ".${parm1}"`

  if [ "${health_value}" == "${good_health}" ]
  then
    return 0
  else
    if [ "x${mode}" == x"init_check" ]
    then
      echo "health check failed: ${parm1} is not ${good_health}"
      exit 1
    fi
  fi 
}

check_cluster() {
  # check cluster status
  ((i=0))
  while true
  do
    sleep 5
    ((i++))
    echo "[${i}] Waiting for health status to return to green ..."
    health status restart_mode

    if [ "$?" -eq 0 ]
    then
      echo "cluster is healthy"
      break
    fi
  done
}

node_status () {
    kubectl -n ${namespace} exec -it ${host} -- curl localhost:9200/_cat/nodes
}

node_in_cluster() { 
  current_pod=$1

  ((i=0))
  while true
  do
    sleep 5
    ((i++))
    echo "[${i}] Waiting for $current_pod in cluster ..."

    kubectl -n ${namespace} exec -it ${host} -- \
    curl localhost:9200/_cat/nodes | grep ${pod}
    if [ "$?" -eq 0 ]
    then
      break
    fi
  done
}

restart_pod() {
  pod=$1

  echo
  echo '-------------------------------
  echo " current pod: ${pod}"
  echo '-------------------------------

  disable_shard
 
  echo "stop pod ${pod}"
  kubectl -n ${namespace} delete pod ${pod}

  echo "check restart pod ${pod}"
  ((i=0))
  while true
  do
    sleep 5
    ((i++))
    echo "[${i}] Waiting for ${pod} running status ..."
    kubectl -n ${namespace} get pod ${pod} | grep Running > /dev/null
    if [ "$?" -eq 0 ]
    then
      break
    fi
  done

  if  [ ${pod} == "${host}" ]
  then
    set_nodes
  fi

  echo "check node:${pod} in cluster"
  node_in_cluster ${pod}
  enable_shard
}

disable_shard() {
  echo "disable sharding"
  kubectl -n ${namespace} exec -it ${host} -- \
  curl -XPUT -H 'Content-Type: application/json' 'localhost:9200/_cluster/settings' -d "${disable_shard}"

  echo "stop indexing and perform a synced flush"
  kubectl -n ${namespace} exec -it ${host} -- \
  curl -XPOST -H 'Content-Type: application/json' 'localhost:9200/_flush/synced'

  echo "stop learning jobs and datafeeds"
  kubectl -n ${namespace} exec -it ${host} -- \
  curl -XPOST -H 'Content-Type: application/json' 'localhost:9200/_ml/set_upgrade_mode?enabled=true'
}

enable_shard() {
  echo "enable sharding"
  kubectl -n ${namespace} exec -it ${host} -- \
  curl -XPUT -H 'Content-Type: application/json' 'localhost:9200/_cluster/settings' -d "${enable_shard}"

  echo "Start learning jobs and datafeeds"
  kubectl -n ${namespace} exec -it ${host} -- \
  curl -XPOST -H 'Content-Type: application/json' 'localhost:9200/_ml/set_upgrade_mode?enabled=false'

  check_cluster
}

options='m:n:'
while getopts ${options} option
do
  case $option in
    m) mode=${OPTARG};;
    n) namespace=${OPTARG};;
    *) usage;;
  esac
done

if [ -z "${mode}" ] || [ -z "${namespace}" ]
then
  usage
fi

echo '==========================='
echo " namespace : ${namespace}"
echo " mode      : ${mode}"
echo '==========================='
echo

case ${mode} in
  restart) set_nodes
           health status init_check
           health unassigned_shards
           for i in ${nodes};do restart_pod ${i};done
  ;;
  enable_shard) set_nodes
               enable_shard
  ;;
  disable_shard) set_nodes 
                disable_shard
  ;;
  get_nodes) set_nodes
             echo " === nodes ==="
             echo "${nodes}"
  ;;
  node_status) set_nodes
               node_status
  ;;
  health) set_nodes
          get_health
  ;;
  *) usage
  ;;
esac
