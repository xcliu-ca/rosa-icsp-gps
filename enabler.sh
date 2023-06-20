#!/bin/bash

### daemonset suppose to synchronize imagecontentsourcepolicy and global pull secert to workers in 1 minute
# The daemonset runs on every worker node, converting on fly
#   imagecontentsourcepolicy to worker file /etc/containers/registries.conf
#   global pull secert to worker file /.docker/config.json
#   version (icsp and global pull secret) to worker file /version
### to improve: rbac

export AWS_ACCESS_KEY=${AWS_ACCESS_KEY}
export AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY}
if [ -z "$AWS_ACCESS_KEY" -o -z "$AWS_SECRET_ACCESS_KEY" ]; then
  echo "!!! aws access and secret keys are required to enable"
  exit
fi

[ -n "$OC" ] || OC=$(which oc)
[ -n "$JQ" ] || JQ=$(which jq)
if ! $OC get nodes 2>/dev/null; then
  echo "!!! configure your cluster access to enable"
  exit
fi
if [ -z "$JQ" ]; then
  echo "!!! jq is required to configure"
  exit
fi

export AWS_REGION=${AWS_REGION}
if [ -z "$AWS_REGION" ]; then
  export AWS_REGION=$($OC get nodes -o jsonpath="{.items[*].metadata.labels}" | jq | grep "topology.kubernetes.io.region" | sort -u | sed -e 's/"//g' -e 's/,//g' | awk '{print $NF}')
  if [ $(echo $AWS_REGION | wc -l) -gt 2 ]; then
    echo "!!! your worker pool seems to span in multiple regions, provide AWS_REGION for your control plane"
    exit
  fi
fi
if [ -z "$AWS_REGION" ]; then
  echo "!!! can not figure out aws region, please provide AWS_REGION envirnoment"
  exit
fi

$OC -n kube-system delete svc svc-roks-icsp 2>/dev/null
$OC -n kube-system delete ds roks-icsp-ds 2>/dev/null

ACTION=${1:-create}
$OC $ACTION -f- << ENDF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: sa-roks-sync
  namespace: kube-system
ENDF
sleep 3
$OC adm policy add-cluster-role-to-user cluster-admin system:serviceaccount:kube-system:sa-roks-sync

$OC $ACTION -f- << ENDF
apiVersion: apps/v1
kind: DaemonSet
metadata:
  labels:
    app: roks-icsp
  name: roks-icsp-ds
  namespace: kube-system
spec:
  selector:
    matchLabels:
      app: roks-icsp
  template:
    metadata:
      labels:
        app: roks-icsp
    spec:
      containers:
      - image: quay.io/cicdtest/roks-enabler:rosa
        imagePullPolicy: Always
        name: roks-icsp
        priorityClassName: openshift-user-critical
        env:
        - name: AWS_ACCESS_KEY
          value: ${AWS_ACCESS_KEY}
        - name: AWS_SECRET_ACCESS_KEY
          value: ${AWS_SECRET_ACCESS_KEY}
        - name: AWS_REGION
          value: ${AWS_REGION}
        volumeMounts:
        - name: host
          mountPath: /host
        securityContext:
          privileged: true
          runAsUser: 0
        resources: {}
        terminationMessagePath: /dev/termination-log
        terminationMessagePolicy: File
      serviceAccountName: sa-roks-sync
      volumes:
      - name: host
        hostPath:
          path: /
      dnsPolicy: ClusterFirst
      restartPolicy: Always
      schedulerName: default-scheduler
      securityContext: {}
      terminationGracePeriodSeconds: 5
      nodeSelector:
        node-role.kubernetes.io/worker: ""
---
apiVersion: v1
kind: Service
metadata:
  labels:
    app: roks-icsp
  name: svc-roks-icsp
  namespace: kube-system
spec:
  ports:
  - port: 80
    protocol: TCP
    targetPort: 3000
  selector:
    app: roks-icsp
  sessionAffinity: None
  type: ClusterIP
ENDF

