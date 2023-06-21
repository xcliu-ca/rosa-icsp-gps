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


if ! $OC api-resources | grep -q machineconfigs; then
   cat << ENDF | $OC apply -f -
kind: CustomResourceDefinition
apiVersion: apiextensions.k8s.io/v1
metadata:
  annotations:
  name: machineconfigs.machineconfiguration.openshift.io
spec:
  group: machineconfiguration.openshift.io
  names:
    plural: machineconfigs
    singular: machineconfig
    shortNames:
      - mc
    kind: MachineConfig
    listKind: MachineConfigList
  scope: Cluster
  versions:
    - name: v1
      served: true
      storage: true
      schema:
        openAPIV3Schema:
          description: MachineConfig defines the configuration for a machine
          type: object
          properties:
            apiVersion:
              description: >-
                APIVersion defines the versioned schema of this representation
                of an object. Servers should convert recognized schemas to the
                latest internal value, and may reject unrecognized values. More
                info:
                https://git.k8s.io/community/contributors/devel/sig-architecture/api-conventions.md#resources
              type: string
            kind:
              description: >-
                Kind is a string value representing the REST resource this
                object represents. Servers may infer this from the endpoint the
                client submits requests to. Cannot be updated. In CamelCase.
                More info:
                https://git.k8s.io/community/contributors/devel/sig-architecture/api-conventions.md#types-kinds
              type: string
            metadata:
              type: object
            spec:
              description: MachineConfigSpec is the spec for MachineConfig
              type: object
              properties:
                config:
                  description: Config is a Ignition Config object.
                  type: object
                  required:
                    - ignition
                  properties:
                    ignition:
                      description: >-
                        Ignition section contains metadata about the
                        configuration itself. We only permit a subsection of
                        ignition fields for MachineConfigs.
                      type: object
                      properties:
                        config:
                          type: object
                          properties:
                            append:
                              type: array
                              items:
                                type: object
                                properties:
                                  source:
                                    type: string
                                  verification:
                                    type: object
                                    properties:
                                      hash:
                                        type: string
                            replace:
                              type: object
                              properties:
                                source:
                                  type: string
                                verification:
                                  type: object
                                  properties:
                                    hash:
                                      type: string
                        security:
                          type: object
                          properties:
                            tls:
                              type: object
                              properties:
                                certificateAuthorities:
                                  type: array
                                  items:
                                    type: object
                                    properties:
                                      source:
                                        type: string
                                      verification:
                                        type: object
                                        properties:
                                          hash:
                                            type: string
                        timeouts:
                          type: object
                          properties:
                            httpResponseHeaders:
                              type: integer
                            httpTotal:
                              type: integer
                        version:
                          description: >-
                            Version string is the semantic version number of the
                            spec
                          type: string
                      x-kubernetes-preserve-unknown-fields: true
                    passwd:
                      type: object
                      properties:
                        users:
                          type: array
                          items:
                            type: object
                            properties:
                              name:
                                description: Name of user. Must be \"core\" user.
                                type: string
                              sshAuthorizedKeys:
                                description: Public keys to be assigned to user core.
                                type: array
                                items:
                                  type: string
                    storage:
                      description: >-
                        Storage describes the desired state of the system's
                        storage devices.
                      type: object
                      properties:
                        directories:
                          description: Directories is the list of directories to be created
                          type: array
                          items:
                            description: Items is list of directories to be written
                            type: object
                            properties:
                              filesystem:
                                description: >-
                                  Filesystem is the internal identifier of the
                                  filesystem in which to write the file. This
                                  matches the last filesystem with the given
                                  identifier.
                                type: string
                              group:
                                description: Group object specifies group of the owner
                                type: object
                                properties:
                                  id:
                                    description: ID is the user ID of the owner
                                    type: integer
                                  name:
                                    description: Name is the user name of the owner
                                    type: string
                              mode:
                                description: >-
                                  Mode is the file's permission mode. Note that
                                  the mode must be properly specified as a
                                  decimal value (i.e. 0644 -> 420)
                                type: integer
                              overwrite:
                                description: >-
                                  Overwrite specifies whether to delete
                                  preexisting nodes at the path
                                type: boolean
                              path:
                                description: Path is the absolute path to the file
                                type: string
                              user:
                                description: User object specifies the file's owner
                                type: object
                                properties:
                                  id:
                                    description: ID is the user ID of the owner
                                    type: integer
                                  name:
                                    description: Name is the user name of the owner
                                    type: string
                        files:
                          description: Files is the list of files to be created/modified
                          type: array
                          items:
                            description: Items is list of files to be written
                            type: object
                            properties:
                              contents:
                                description: >-
                                  Contents specifies options related to the
                                  contents of the file
                                type: object
                                properties:
                                  compression:
                                    description: >-
                                      The type of compression used on the
                                      contents (null or gzip). Compression
                                      cannot be used with S3.
                                    type: string
                                  source:
                                    description: >-
                                      Source is the URL of the file contents.
                                      Supported schemes are http, https, tftp,
                                      s3, and data. When using http, it is
                                      advisable to use the verification option
                                      to ensure the contents haven't been
                                      modified.
                                    type: string
                                  verification:
                                    description: >-
                                      Verification specifies options related to
                                      the verification of the file contents
                                    type: object
                                    properties:
                                      hash:
                                        description: >-
                                          Hash is the hash of the config, in the
                                          form <type>-<value> where type is sha512
                                        type: string
                              filesystem:
                                description: >-
                                  Filesystem is the internal identifier of the
                                  filesystem in which to write the file. This
                                  matches the last filesystem with the given
                                  identifier
                                type: string
                              group:
                                description: Group object specifies group of the owner
                                type: object
                                properties:
                                  id:
                                    description: ID specifies group ID of the owner
                                    type: integer
                                  name:
                                    description: Name is the group name of the owner
                                    type: string
                              mode:
                                description: >-
                                  Mode specifies the file's permission mode.
                                  Note that the mode must be properly specified
                                  as a decimal value (i.e. 0644 -> 420)
                                type: integer
                              overwrite:
                                description: >-
                                  Overwrite specifies whether to delete
                                  preexisting nodes at the path
                                type: boolean
                              path:
                                description: Path is the absolute path to the file
                                type: string
                              user:
                                description: User object specifies the file's owner
                                type: object
                                properties:
                                  id:
                                    description: ID is the user ID of the owner
                                    type: integer
                                  name:
                                    description: Name is the user name of the owner
                                    type: string
                            x-kubernetes-preserve-unknown-fields: true
                      x-kubernetes-preserve-unknown-fields: true
                    systemd:
                      description: systemd describes the desired state of the systemd units
                      type: object
                      properties:
                        units:
                          description: Units is a list of units to be configured
                          type: array
                          items:
                            description: Items describes unit configuration
                            type: object
                            properties:
                              contents:
                                description: Contents is the contents of the unit
                                type: string
                              dropins:
                                description: Dropins is the list of drop-ins for the unit
                                type: array
                                items:
                                  description: Items describes unit dropin
                                  type: object
                                  properties:
                                    contents:
                                      description: Contents is the contents of the drop-in
                                      type: string
                                    name:
                                      description: >-
                                        Name is the name of the drop-in. This
                                        must be suffixed with '.conf'
                                      type: string
                              enabled:
                                description: >-
                                  Enabled describes whether or not the service
                                  shall be enabled. When true, the service is
                                  enabled. When false, the service is disabled.
                                  When omitted, the service is unmodified. In
                                  order for this to have any effect, the unit
                                  must have an install section
                                type: boolean
                              mask:
                                description: >-
                                  Mask describes whether or not the service
                                  shall be masked. When true, the service is
                                  masked by symlinking it to /dev/null"
                                type: boolean
                              name:
                                description: >-
                                  Name is the name of the unit. This must be
                                  suffixed with a valid unit type (e.g.
                                  'thing.service')
                                type: string
                  x-kubernetes-preserve-unknown-fields: true
                extensions:
                  description: List of additional features that can be enabled on host
                  type: array
                  items:
                    type: string
                  nullable: true
                fips:
                  description: FIPS controls FIPS mode
                  type: boolean
                kernelArguments:
                  description: >-
                    KernelArguments contains a list of kernel arguments to be
                    added
                  type: array
                  items:
                    type: string
                  nullable: true
                kernelType:
                  description: >-
                    Contains which kernel we want to be running like default
                    (traditional), realtime
                  type: string
                osImageURL:
                  description: >-
                    OSImageURL specifies the remote location that will be used
                    to fetch the OS
                  type: string
      additionalPrinterColumns:
        - name: GeneratedByController
          type: string
          description: >-
            Version of the controller that generated the machineconfig. This
            will be empty if the machineconfig is not managed by a controller.
          jsonPath: >-
            .metadata.annotations.machineconfiguration\.openshift\.io/generated-by-controller-version
        - name: IgnitionVersion
          type: string
          description: Version of the Ignition Config defined in the machineconfig.
          jsonPath: .spec.config.ignition.version
        - name: Age
          type: date
          jsonPath: .metadata.creationTimestamp
  conversion:
    strategy: None
ENDF
fi