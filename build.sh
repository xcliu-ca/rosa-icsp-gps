podman manifest rm lospringliu/roks-enabler:rosa  || true
sleep 3
podman build --platform linux/arm64 --platform linux/amd64 --manifest lospringliu/roks-enabler:rosa .
sleep 3
podman manifest push -f v2s2 lospringliu/roks-enabler:rosa quay.io/cicdtest/roks-enabler:rosa
podman manifest push -f v2s2 lospringliu/roks-enabler:rosa docker.io/lospringliu/roks-sync:rosa
