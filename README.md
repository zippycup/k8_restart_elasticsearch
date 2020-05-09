# k8_restart_elasticsearch
Perform rolling restart elasticsearch cluster 

## Description

This script implements as an automated script the following : https://www.elastic.co/guide/en/elasticsearch/reference/current/restart-cluster.html in a kubernetes cluster. This allows for automated of the following steps

- check health before starting rolling restart
- disable sharding
- stops indexing and forces sync
- stops node
- checks restart
- check node back in cluster
- re-enable sharding
- checks health
- move on to the next node and repeats the above stops

## Requirements
* kubectl installed
* ~/.kube/config configured
* jq fromi https://stedolan.github.io/jq/download/
* linux / mac bash environment ( e.g. sed, awk, grep )

## Installation

- Copy es-util.sh to your computer
- Edit node_regex. Default is '^es-'. My elasticsearch nodes are named 'es-master-0, es-data-0, es-[role]-[x]' where x is incremented in a kubernetes stateful set.
 
## Run utility

```
 sh es-util.sh -m [mode] -n [namespace]
 mode: restart|enable_shard|disable_shard|get_nodes|node_status|health
```
