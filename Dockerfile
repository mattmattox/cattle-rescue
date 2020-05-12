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
ADD https://storage.googleapis.com/kubernetes-release/release/v1.18.2/bin/linux/amd64/kubectl /usr/local/bin/kubectl
RUN chmod +x /usr/local/bin/kubectl

## Install RKE
ADD https://github.com/rancher/rke/releases/download/v1.1.0/rke_linux-amd64 /usr/local/bin/rke
RUN chmod +x /usr/local/bin/rke

## Install Helm
ADD https://get.helm.sh/helm-v3.2.1-linux-amd64.tar.gz /usr/local/bin/helm
RUN chmod +x /usr/local/bin/helm

## Adding scripts
RUN mkdir -p /opt/cattle-rescue/
ADD *.sh /opt/cattle-rescue/
RUN chmod +x /opt/cattle-rescue/*.sh

## Setup run script
WORKDIR /opt/cattle-rescue/
CMD /opt/cattle-rescue/run.sh
