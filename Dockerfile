FROM redhat/ubi9-minimal

RUN du -sh /usr /var /root; microdnf install -y nodejs tar gzip; du -sh /usr /var /root

ENV FILE_VERSION=/host/etc/version
ENV FILE_REGIATRIES=/host/etc/containers/registries.conf

ENV FILE_DOCKERCONFIG=/host/var/lib/kubelet/config.json

RUN curl  https://mirror.openshift.com/pub/openshift-v4/$(uname -m | sed -e 's/aarch/arm/')/clients/ocp/latest/openshift-client-$(uname -s | tr /A-Z/ /a-z/).tar.gz | tar zxf - -C /usr/local/bin; rm -fv /usr/local/bin/kubectl

WORKDIR /workdir
COPY Dockerfile .
COPY in-pod-kubeconfig.sh .
COPY enabler.sh .
COPY entry-point.sh .
COPY package.json .
COPY app.js .

ENTRYPOINT ["./entry-point.sh"]

