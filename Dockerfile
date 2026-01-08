FROM rocker/r2u:24.04

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
        libcurl4-openssl-dev --fix-broken \
        curl \
        rsync \
        unzip \
    && apt-get clean && apt-get purge
   
# Install 'RBCFTools' in R:
RUN Rscript -e "install.packages('RBCFTools', repos = c('https://rgenomicsetl.r-universe.dev', 'https://cloud.r-project.org'))"
RUN  && rm -rf /var/lib/apt/lists/*