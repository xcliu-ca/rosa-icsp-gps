podman rmi lospringliu/roks-enabler:rosa
sleep 3
podman build --platform linux/amd64 -t lospringliu/roks-enabler:rosa .
sleep 3
podman push lospringliu/roks-enabler:rosa quay.io/cicdtest/roks-enabler:rosa
podman push lospringliu/roks-enabler:rosa docker.io/lospringliu/roks-sync:rosa 
