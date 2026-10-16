FROM mcr.microsoft.com/devcontainers/base:ubuntu-24.04

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
       ca-certificates curl git unzip xz-utils zip libglu1-mesa python3 nodejs \
       openjdk-17-jdk-headless \
    && rm -rf /var/lib/apt/lists/*
