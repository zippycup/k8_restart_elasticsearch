if [ "$#" -gt 0 ]
then
  namespace=$1
else
  namespace=default
fi

# apply master cluster
item='es-master'
kubectl apply -f ${item}-svc.yaml -n ${namespace}
kubectl get sts ${item} -n ${namespace} > /dev/null 2>&1
if [ "$?" -eq 0 ]
then
  kubectl delete sts --cascade=false ${item} -n ${namespace}
  kubectl apply --dry-run --validate -f ${item}.yaml -n ${namespace}
  kubectl apply -f ${item}.yaml -n ${namespace}
  sh es-util.sh -m resize -n ${namespace} -t master
else
  kubectl apply --dry-run --validate -f ${item}.yaml -n ${namespace}
  kubectl apply -f ${item}.yaml -n ${namespace}
  kubectl rollout status -f ${item}.yaml -n ${namespace}
fi

sleep=10
echo sleep ${sleep}
sleep ${sleep}

# apply data cluster
item='es-data'
kubectl apply -f ${item}-svc.yaml -n ${namespace}
kubectl get sts ${item} -n ${namespace} > /dev/null 2>&1
if [ "$?" -eq 0 ]
then
  kubectl delete sts --cascade=false ${item} -n ${namespace}
  kubectl apply --dry-run --validate -f ${item}.yaml -n ${namespace}
  kubectl apply -f ${item}.yaml -n ${namespace}
  sh es-util.sh -m resize -n ${namespace} -t data
else
  kubectl apply --dry-run --validate -f ${item}.yaml -n ${namespace}
  kubectl apply -f ${item}.yaml -n ${namespace}
  kubectl rollout status -f ${item}.yaml -n ${namespace}
fi
