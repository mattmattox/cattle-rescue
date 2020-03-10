FROM ubuntu:18.04

MAINTAINER matthew.mattox@rancher.com

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -yq --no-install-recommends \
    apt-utils \
    curl \
    jq \
    openssh-client \
    nano \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

## Install kubectl
ADD https://storage.googleapis.com/kubernetes-release/release/v1.17.2/bin/linux/amd64/kubectl /usr/local/bin/kubectl
RUN chmod +x /usr/local/bin/kubectl

## Install RKE
ADD https://github.com/rancher/rke/releases/download/v1.0.4/rke_linux-amd64 /usr/local/bin/rke
RUN chmod +x /usr/local/bin/rke

## Setup run script
WORKDIR /root
ADD run.sh /root/run.sh
RUN chmod +x /root/run.sh

CMD /root/run.sh
