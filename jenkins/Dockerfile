FROM jenkins/jenkins:lts
USER root
RUN apt-get update && apt-get install -y bash curl jq && rm -rf /var/lib/apt/lists/*
USER jenkins