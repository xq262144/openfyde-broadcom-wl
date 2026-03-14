FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update -o Acquire::Retries=5 \
    && apt-get install -y -o Acquire::Retries=5 --no-install-recommends \
        bash \
        bc \
        bison \
        build-essential \
        ca-certificates \
        curl \
        file \
        flex \
        git \
        kmod \
        libelf-dev \
        libssl-dev \
        make \
        python3 \
        xz-utils \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /work

ENV ARCH=x86_64
ENV KERNEL_BRANCH=release-R126-15886.B-chromeos-5.4
ENV KERNEL_COMMIT=ca5ac6161115cf185683715bc945e8c55bc6a402
ENV LOCALVERSION=-22664-gca5ac6161115
ENV KERNEL_URL_BASE=https://chromium.googlesource.com/chromiumos/third_party/kernel

CMD ["/bin/bash"]
