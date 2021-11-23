#!/bin/bash

# implementation of : https://www.elastic.co/guide/en/elasticsearch/reference/current/restart-cluster.html

auth_user=elastic
es_util_file=secret/current/es-util.txt
initial_host=es-master-0
master_regex='^es-master-'
data_regex='^es-data-'
default_regex='^es-'
master_pvc=50Gi
data_pvc=100Gi
http=https


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
  echo "usage: sh $0 -m [mode] -n [namespace] -s [http|https]"
  echo  "                 mode: restart|enable_shard|disable_shard|get_nodes|health|check_cluster"
  echo
  exit 0
}

set_nodes() {
  echo "get nodes ..."
  nodes=`kubectl -n ${namespace} get pod | grep ${node_regex} | awk '{print $1}'| sort`
  
  active_host
}

active_host() {

  echo "set active node as host ..."

  if [ x"${host}" == "x" ]
  then
    host=${initial_host}
  fi

  ((i=0))
  while true
  do
    sleep 5
    ((i++))
    echo "[${i}] Waiting for active node ..."
    kubectl -n ${namespace} exec -it ${host} -- curl ${auth} ${curl_parm} ${http}://localhost:9200/_cat/nodes | grep '\*' > /dev/null 2>&1

    if [ "$?" -eq 0 ]
    then
      break
    fi
  done

  tmphost=`kubectl -n ${namespace} exec -it ${host} -- curl ${auth} ${curl_parm} ${http}://localhost:9200/_cat/nodes | grep '\*' | awk '{print $10}' | sed 's/\r$//g'`
  host=${tmphost::${#tmphost}-1}

  echo "set initial node: ${host}"
  if [ x"${host}" == "x" ]
  then
    echo "initial host not found in ${nodes}"
    exit 1
  fi
}

get_health() {
  kubectl -n ${namespace} exec -it ${host} -- curl ${auth} ${curl_parm} ${http}://localhost:9200/_cluster/health?pretty
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
  health_value=`kubectl -n ${namespace} exec -it ${host} -- curl ${auth} ${curl_parm} ${http}://localhost:9200/_cluster/health?pretty | jq ".${parm1}"`

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
  kubectl -n ${namespace} exec -it ${host} -- curl ${auth} ${curl_parm} ${http}://localhost:9200/_cat/nodes
}

indices () {
  kubectl -n ${namespace} exec -it ${host} -- curl ${auth} ${curl_parm} ${http}://localhost:9200/_cat/indices
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
     curl ${auth} ${curl_parm} ${http}://localhost:9200/_cat/nodes | grep ${pod}
    if [ "$?" -eq 0 ]
    then
      break
    fi
  done
}

restart_pod() {
  pod=$1

  echo
  echo '-------------------------------'
  echo " current pod: ${pod}"
  echo '-------------------------------'

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
    active_host
  fi

  echo "check node:${pod} in cluster"
  node_in_cluster ${pod}
  enable_shard
}

disable_shard() {
  echo "disable sharding"
  kubectl -n ${namespace} exec -it ${host} -- \
   curl ${auth} ${curl_parm} -XPUT -H 'Content-Type: application/json' ${http}://localhost:9200/_cluster/settings -d "${disable_shard}"

  echo "stop indexing and perform a synced flush"
  kubectl -n ${namespace} exec -it ${host} -- \
   curl ${auth} ${curl_parm} -XPOST -H 'Content-Type: application/json' ${http}://localhost:9200/_flush/synced

  echo "stop learning jobs and datafeeds"
  kubectl -n ${namespace} exec -it ${host} -- \
   curl ${auth} ${curl_parm} -XPOST -H 'Content-Type: application/json' ${http}://localhost:9200/_ml/set_upgrade_mode?enabled=true
}

enable_shard() {
  echo "enable sharding"
  kubectl -n ${namespace} exec -it ${host} -- \
   curl ${auth} ${curl_parm} -XPUT -H 'Content-Type: application/json' ${http}://localhost:9200/_cluster/settings -d "${enable_shard}"

  echo "Start learning jobs and datafeeds"
  kubectl -n ${namespace} exec -it ${host} -- \
   curl ${auth} ${curl_parm} -XPOST -H 'Content-Type: application/json' ${http}://localhost:9200/_ml/set_upgrade_mode?enabled=false

  check_cluster
}

resize() {
  for i in ${nodes}
  do
    nodetype=`echo ${i} | awk '{split($0,a,"-");print a[2]}'`
    case ${nodetype} in
      master) capacity=${master_pvc};;
        data) capacity=${data_pvc};;
    esac
    claim=`kubectl get pod ${i} -n ${namespace} -oyaml | grep 'claimName:' | grep -v 'f.claimName' | awk '{print $2}'`
    echo "pvc      : ${claim}"
    echo "capacity : ${capacity}"
    kubectl patch pvc ${claim} -p "{ \"spec\": { \"resources\": { \"requests\": { \"storage\": \"${capacity}\" }}}}" -n ${namespace}
  done
}

options='m:n:t:s:'
while getopts ${options} option
do
  case $option in
    m) mode=${OPTARG};;
    n) namespace=${OPTARG};;
    t) type=${OPTARG};;
    s) http=${OPTARG};;
    *) usage;;
  esac
done

if [ "${http}" == "https" ]
then
  curl_parm="-k"
else
  curl_parm=""
fi

if [ -z "${mode}" ] || [ -z "${namespace}" ]
then
  usage
fi

case ${type} in
  master) node_regex=${master_regex};;
    data) node_regex=${data_regex};;
       *) node_regex=${default_regex};;
esac

if [ -f ${es_util_file} ]
then
  source ${es_util_file}
  auth="-u ${auth_user}:${auth_pass::${#auth_pass}-1}"
else
  auth=''
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
  resize)  set_nodes
           health status init_check
           health unassigned_shards
           resize
           for i in ${nodes};do restart_pod ${i};done
           kubectl -n ${namespace} get pvc
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
  check_cluster) set_nodes
                 check_cluster
  ;;
  indices) set_nodes
           indices
  ;;
  *) usage
  ;;
esac
