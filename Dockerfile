FROM rocker/r2u:24.04

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
        curl \
        rsync \
        unzip \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Copy local source (only used in develop mode)
COPY . /package

# Install RBCFTools based on BUILD_MODE
RUN if [ "$BUILD_MODE" = "develop" ]; then \
        echo "Installing RBCFTools from local source..." && \
        Rscript -e "install.packages('remotes')" && \
        Rscript -e "remotes::install_deps('/package', dependencies = TRUE)" && \
        R CMD INSTALL /package; \
    else \
        echo "Installing RBCFTools from R-universe..." && \
        Rscript -e "install.packages('RBCFTools', repos = c('https://rgenomicsetl.r-universe.dev', 'https://cloud.r-project.org'))"; \
    fi
# INSTALL TInytest for testing
RUN Rscript -e "install.packages(c('tinytest','vctrs', 'rlang','duckdb'))"
# Run the tinytest tests to verify installation
RUN Rscript -e "tinytest::test_package('RBCFTools')"

# clean up apt cache
RUN apt-get clean && rm -rf /var/lib/apt/lists/*