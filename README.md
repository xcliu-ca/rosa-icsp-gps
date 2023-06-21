# Syncing global pull secret and image content source policy in ROSA with hosted control plane 

## Global Pull Secret is supported but does not sync to nodes
- `oc -n openshift-config get secret pull-secret -o jsonpath="{.data.\.dockerconfigjson}" | base64 -d | jq`
- `oc set data secret/pull-secret -n openshift-config --from-file=.dockerconfigjson=dockerconfig.json`
- should be synced to worker:`/var/lib/kubelet/config.json`
- worker nodes reboot needed

## Image Content Source Policy is supported but does not sync to nodes
- `oc get imagecontentsourcepolicy -o yaml` 
- should be synced to worker:`/etc/containers/registries.conf`
- worker nodes reboot required

## Solution
- deploy a `deamonset` to run on worker nodes
- the container mount worker filesystem
- the container sychronizes Global Pull Secret to disk
- the container sychronizes Image Content Source Policy to disk
- worker reboot attempted (with aws cli)

## Benefit
- easy with a `daemonset` deploy
- no difference thereafter with regular openshift env
- flexible (no pre-defined staff)

## Steps
1. have `oc` cli available
2. have `oc` configured
3. export your AWS access key and secret key `export AWS_ACCESS_KEY=replace-with-your-access-key; export AWS_SECRET_ACCESS_KEY=replace-with-your-secret-key`
4. [if prompted] export your rosa cluster region information `export AWS_REGION=replace-with-cluster-region`
5. install `daemonset` by executing [script](enabler.sh) `./enabler.sh` (it also create `CRD/machineconfig` if not present)
6. treat `rosa with hosted control plane` no difference with other `openshift` env

## current limit
- rosa with hosted control plane revert its default `secret/pull-secret`, so use `secret/pull-secret-hcp` for now
- rosa with hosted control plane reverts its default `imagecontentsourcepolicy/cluster`, so create new imagecontentsourcepolicy items
- cluster nodes should be in the same aws region
