FROM debian:bookworm-slim

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    racket \
    swi-prolog \
    gcc \
    g++ \
    libc6-dev \
    make \
    git \
    ca-certificates && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app
