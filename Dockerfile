FROM redhat/ubi9

RUN dnf update; du -sh /usr /var /root; dnf install -y nodejs jq xz unzip less groff-base; du -sh /usr /var /root

ENV AWS_ACCESS_KEY=
ENV AWS_SECRET_ACCESS_KEY=
ENV AWS_REGION=

RUN curl  https://mirror.openshift.com/pub/openshift-v4/$(uname -m)/clients/ocp/latest/openshift-client-$(uname -s | tr /A-Z/ /a-z/).tar.gz | tar zxf - -C /usr/local/bin; rm -fv /usr/local/bin/kubectl
RUN curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscliv2.zip; cd /tmp; unzip -q awscliv2.zip; ./aws/install; aws --version; rm -fr aws*

WORKDIR /workdir
COPY Dockerfile .
COPY in-pod-kubeconfig.sh .
COPY enabler.sh .
COPY entry-point.sh .
COPY package.json .
COPY app.js .

ENTRYPOINT ["./entry-point.sh"]

