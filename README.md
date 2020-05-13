# k8_restart_elasticsearch
Perform rolling restart elasticsearch cluster 

## Description

This implements as an automated script for the following : https://www.elastic.co/guide/en/elasticsearch/reference/current/restart-cluster.html in a kubernetes cluster. This allows for automation of the following steps:

- check health before starting rolling restart
- disable sharding
- stops indexing and forces sync
- stops node
- checks restart
- if mode is resize. Restart will resize the persisent volume
- check node back in cluster
- re-enable sharding
- checks cluster health
- move on to the next node and repeats the above stops

The steps ensure that the cluster is healthy at each node restart preventing corrupting the cluster ( data loss )

## Requirements
* kubectl installed
* ~/.kube/config configured
* jq fromi https://stedolan.github.io/jq/download/
* linux / mac bash environment ( e.g. sed, awk, grep )

## Installation

The utility makes the assumption that the cluster has 2 types of nodes:
- master
- data 

These nodes types are deployed via a statefulset es-master and es-data.

- Copy es-util.sh to your computer
- Edit these settings:

  initial_host=es-master-0
  master_regex='^es-master-'
  data_regex='^es-data-'
  default_regex='^es-'
  master_pvc=50Gi
  data_pvc=100Gi

- if you desire to resize persistent volume, update and deploy the statefulset first before running utility  with the updated volumeclaim size. The pattern for this is:
  - delete statefulset
  - deploy new statefulset
  - run resize script

You do not want to run 'kubectl rollout status' after 'kubectl apply' The rollout restart will not give enough time for the cluster to become healthy causing cluster corruption.
Please refer the the sample wrapper script to the restart/resize script called: install-es.sh

```
  volumeClaimTemplates:
  - metadata:
      name: storage
    spec:
      storageClassName: encrypted-gp2
      accessModes: [ ReadWriteOnce ]
      resources:
        requests:
          storage: 50Gi
```

 
## Run utility


```
 sh es-util.sh -m [mode] -n [namespace] -t [type: master|data]
 mode: restart|enable_shard|disable_shard|get_nodes|node_status|health|resize
```

examples
```
# restart all
sh es-util.sh -m restart -n default

# resize data
sh es-util.sh -m resize -n default -t data

# enable sharding
sh es-util.sh -m enable_shard -n default

# check health
sh es-util.sh -m health -n default

# show node status
sh es-util.sh -m node_status -n default
```

If the script exits abnormally, The cluster maybe unhealthy ( yellow ). Just run 'enable_shard' and give it some time to sync.

Normally it will take about 5 cycles for 'Waiting for ${pod} running status ...'. If it seems to be stuck, this maybe due to 'timeout expired waiting for volumes to attach or mount for pod'. Wait about 15 minutes, the volumeMount will eventually reset.
