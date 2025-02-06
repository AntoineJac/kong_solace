# Base image
FROM kong/kong-gateway:3.9

# Switch to root to install dependencies
USER root

# Install required dependencies
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    gcc \
    g++ \
    make \
    libc6 \
    libssl-dev \
    netcat-openbsd \
    ca-certificates && \
    rm -rf /var/lib/apt/lists/*

# Create directory for Solace libs
RUN mkdir -p /usr/local/kong/solace

# Copy Solace C API
COPY solace-samples-c-master /usr/local/kong/solace

# Set library path
ENV LD_LIBRARY_PATH=/usr/local/kong/solace/lib/linux/x64

# Verify library is accessible and build in the Intro directory
WORKDIR /usr/local/kong/solace/build

RUN ./build_intro_linux_x64.sh && \
    ldd /usr/local/kong/solace/lib/linux/x64/libsolclient.so

# Switch back to Kong user (important for security)
USER root
