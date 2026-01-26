FROM rocker/r2u:24.04
LABEL maintainer="Sounkou Mahamane Toure <sounkoutoure@gmail.com>"
LABEL description="Docker image for RBCFTools R package"
# Build argument to switch between release and develop mode
# Usage: docker build --build-arg BUILD_MODE=develop .
ARG BUILD_MODE=release

# Install system dependencies for RBCFTools
# GNU make, pkg-config, libcurl, libgsl, libdeflate, libbzip2, libzlib, libssl-dev (or other ssl library), liblzma-dev, libxml2-dev, git, rsync
RUN apt-get update \
    && apt-get -y upgrade \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y \
        build-essential \
        libboost-all-dev \
        libgtest-dev \
        libz-dev \
        git \
        locales \
        cmake \
        make \
        wget \
        liblzma-dev \
        libdeflate-dev \
        libbz2-dev \
        libssl-dev \
        libcurl4-openssl-dev \
        libgsl-dev \
        libxml2-dev \
        curl \
        rsync \
        unzip \
        golang \
        libsuitesparse-dev \
        libcholmod5 \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

RUN mkdir /package
WORKDIR /package
# Copy local source (only used in develop mode)
COPY ./DESCRIPTION /package

# Install remotes
RUN R -e 'install.packages("remotes")'
# Install RBCFTools based on BUILD_MODE

RUN R -e "remotes::install_deps('.', dependencies = TRUE)"
# Run the tinytest tests to verify installation
COPY . /package
WORKDIR /package

RUN R -e 'install.packages("tinytest")'
RUN R -e 'install.packages("/package", repos = NULL)'
#RUN R -e "library('RBCFTools');tinytest::test_package('RBCFTools')"

# clean up apt cache
RUN apt-get clean && rm -rf /var/lib/apt/lists/*