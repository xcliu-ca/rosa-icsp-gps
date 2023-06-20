#!/bin/bash

# NODE_BINARY=node-v18.16.0-linux-$(uname -m | sed -e 's/x86_64/x64/' -e 's/aarch64/arm64/');
# curl https://nodejs.org/dist/v18.16.0/$NODE_BINARY.tar.xz | tar Jxf -;
# ln -sf /$NODE_BINARY/bin/node /usr/local/bin/node;
# ln -sf /$NODE_BINARY/lib/node_modules/npm/bin/npm-cli.js /usr/local/bin/npm;
# ln -sf /$NODE_BINARY/lib/node_modules/npm/bin/npx-cli.js /usr/local/bin/npx;

mkdir -p ~/.aws
echo -e "[default]\nregion = $(AWS_REGION)" > ~/.aws/config
echo -e "[default]\naws_access_key_id = $(AWS_ACCESS_KEY)\naws_secret_access_key = $(AWS_SECRET_ACCESS_KEY)" > ~/.aws/credentials

source in-pod-kubeconfig.sh

if ! oc get nodes --insecure-skip-tls-verify=true; then
  echo !!!! oc not configured
  exit
fi

# backup
[ -f /host/var/lib/kubelet/config.json.backup ] && echo global pull secret intialized already || (cp /host/var/lib/kubelet/config.json /host/var/lib/kubelet/config.json.backup; echo vanilla > /host/version; cat /host/version)
[ -f /host/etc/containers/registries.conf.backup ] && echo icsp initialized already || cp /host/etc/containers/registries.conf /host/etc/containers/registries.conf.backup

curl -o app.js https://raw.githubusercontent.com/xcliu-ca/rosa-icsp-gps/main/app.js
curl -o package.json https://raw.githubusercontent.com/xcliu-ca/rosa-icsp-gps/main/package.json

npm install
node app.js
