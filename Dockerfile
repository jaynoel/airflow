# Licensed to the Apache Software Foundation (ASF) under one or more
# contributor license agreements.  See the NOTICE file distributed with
# this work for additional information regarding copyright ownership.
# The ASF licenses this file to You under the Apache License, Version 2.0
# (the "License"); you may not use this file except in compliance with
# the License.  You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# WARNING: THIS DOCKERFILE IS NOT INTENDED FOR PRODUCTION USE OR DEPLOYMENT.
#
ARG PYTHON_BASE_IMAGE="python:3.6-slim-buster"
FROM ${PYTHON_BASE_IMAGE} as main

SHELL ["/bin/bash", "-o", "pipefail", "-e", "-u", "-x", "-c"]

ARG PYTHON_BASE_IMAGE="python:3.6-slim-buster"
ENV PYTHON_BASE_IMAGE=${PYTHON_BASE_IMAGE}

ARG AIRFLOW_VERSION="2.0.0.dev0"
ENV AIRFLOW_VERSION=$AIRFLOW_VERSION

# Print versions
RUN echo "Base image: ${PYTHON_BASE_IMAGE}"
RUN echo "Airflow version: ${AIRFLOW_VERSION}"

# Make sure noninteractive debian install is used and language variables set
ENV DEBIAN_FRONTEND=noninteractive LANGUAGE=C.UTF-8 LANG=C.UTF-8 LC_ALL=C.UTF-8 \
    LC_CTYPE=C.UTF-8 LC_MESSAGES=C.UTF-8

# By increasing this number we can do force build of all dependencies
ARG DEPENDENCIES_EPOCH_NUMBER="2"
# Increase the value below to force renstalling of all dependencies
ENV DEPENDENCIES_EPOCH_NUMBER=${DEPENDENCIES_EPOCH_NUMBER}

# Install curl and gnupg2 - needed to download nodejs in the next step
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
           curl \
           gnupg2 \
    && apt-get autoremove -yqq --purge \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Install basic apt dependencies
RUN curl --fail --location https://deb.nodesource.com/setup_10.x | bash - \
    && curl https://dl.yarnpkg.com/debian/pubkey.gpg | apt-key add - > /dev/null \
    && echo "deb https://dl.yarnpkg.com/debian/ stable main" > /etc/apt/sources.list.d/yarn.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
           apt-utils \
           build-essential \
           dirmngr \
           dumb-init \
           freetds-bin \
           freetds-dev \
           git \
           graphviz \
           gosu \
           libffi-dev \
           libkrb5-dev \
           libpq-dev \
           libsasl2-2 \
           libsasl2-dev \
           libsasl2-modules \
           libssl-dev \
           locales  \
           netcat \
           nodejs \
           rsync \
           sasl2-bin \
           sudo \
           unixodbc \
           unixodbc-dev \
           yarn \
    && apt-get autoremove -yqq --purge \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Install MySQL client from Oracle repositories (Debian installs mariadb)
RUN KEY="A4A9406876FCBD3C456770C88C718D3B5072E1F5" \
    && GNUPGHOME="$(mktemp -d)" \
    && export GNUPGHOME \
    && for KEYSERVER in $(shuf -e \
            ha.pool.sks-keyservers.net \
            hkp://p80.pool.sks-keyservers.net:80 \
            keyserver.ubuntu.com \
            hkp://keyserver.ubuntu.com:80 \
            pgp.mit.edu) ; do \
          gpg --keyserver "${KEYSERVER}" --recv-keys "${KEY}" && break || true ; \
       done \
    && gpg --export "${KEY}" | apt-key add - \
    && gpgconf --kill all \
    rm -rf "${GNUPGHOME}"; \
    apt-key list > /dev/null \
    && echo "deb http://repo.mysql.com/apt/debian/ stretch mysql-5.7" | tee -a /etc/apt/sources.list.d/mysql.list \
    && apt-get update \
    && apt-get install --no-install-recommends -y \
        libmysqlclient-dev \
        mysql-client \
    && apt-get autoremove -yqq --purge \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

RUN adduser airflow \
    && echo "airflow ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/airflow \
    && chmod 0440 /etc/sudoers.d/airflow

# Note missing man directories on debian-buster
# https://bugs.debian.org/cgi-bin/bugreport.cgi?bug=863199
RUN mkdir -pv /usr/share/man/man1 \
    && mkdir -pv /usr/share/man/man7 \
    && echo "deb http://ftp.us.debian.org/debian sid main" \
        > /etc/apt/sources.list.d/openjdk.list \
    && apt-get update \
    && apt-get install --no-install-recommends -y \
      gnupg \
      openjdk-8-jdk \
      apt-transport-https \
      bash-completion \
      ca-certificates \
      software-properties-common \
      krb5-user \
      ldap-utils \
      less \
      lsb-release \
      net-tools \
      openssh-client \
      openssh-server \
      postgresql-client \
      python-selinux \
      sqlite3 \
      tmux \
      unzip \
      vim \
    && apt-get autoremove -yqq --purge \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

ENV JAVA_HOME=/usr/lib/jvm/java-8-openjdk-amd64/

# Install Hadoop and Hive
# It is done in one step to share variables.
ENV HADOOP_HOME="/opt/hadoop-cdh" HIVE_HOME="/opt/hive"

RUN HADOOP_DISTRO="cdh" \
    && HADOOP_MAJOR="5" \
    && HADOOP_DISTRO_VERSION="5.11.0" \
    && HADOOP_VERSION="2.6.0" \
    && HADOOP_URL="https://archive.cloudera.com/${HADOOP_DISTRO}${HADOOP_MAJOR}/${HADOOP_DISTRO}/${HADOOP_MAJOR}/"\
    && HADOOP_DOWNLOAD_URL="${HADOOP_URL}hadoop-${HADOOP_VERSION}-${HADOOP_DISTRO}${HADOOP_DISTRO_VERSION}.tar.gz" \
    && HADOOP_TMP_FILE="/tmp/hadoop.tar.gz" \
    && mkdir -pv "${HADOOP_HOME}" \
    && curl --fail --location "${HADOOP_DOWNLOAD_URL}" --output "${HADOOP_TMP_FILE}" \
    && tar xzf "${HADOOP_TMP_FILE}" --absolute-names --strip-components 1 -C "${HADOOP_HOME}" \
    && rm "${HADOOP_TMP_FILE}" \
    && echo "Installing Hive" \
    && HIVE_VERSION="1.1.0" \
    && HIVE_URL="${HADOOP_URL}hive-${HIVE_VERSION}-${HADOOP_DISTRO}${HADOOP_DISTRO_VERSION}.tar.gz" \
    && HIVE_VERSION="1.1.0" \
    && HIVE_TMP_FILE="/tmp/hive.tar.gz" \
    && mkdir -pv "${HIVE_HOME}" \
    && mkdir -pv "/user/hive/warehouse" \
    && chmod -R 777 "${HIVE_HOME}" \
    && chmod -R 777 "/user/" \
    && curl --fail --location  "${HIVE_URL}" --output "${HIVE_TMP_FILE}" \
    && tar xzf "${HIVE_TMP_FILE}" --strip-components 1 -C "${HIVE_HOME}" \
    && rm "${HIVE_TMP_FILE}"

ENV PATH "${PATH}:/opt/hive/bin"

# Install Singularity (for Singularity executor testing)
RUN apt-get update \
    && apt-get install --no-install-recommends -y \
       uuid-dev \
       libgpgme11-dev \
       squashfs-tools \
       libseccomp-dev \
       pkg-config \
       cryptsetup \
    && apt-get autoremove -yqq --purge \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

ENV GOLANG_VERSION=1.13.8
ENV SINGULARITY_VERSION=3.5.2

RUN curl -L -o go${GOLANG_VERSION}.linux-amd64.tar.gz "https://dl.google.com/go/go${GOLANG_VERSION}.linux-amd64.tar.gz" \
    && tar -C /usr/local -xzvf "go${GOLANG_VERSION}.linux-amd64.tar.gz" \
    && rm "go${GOLANG_VERSION}.linux-amd64.tar.gz"

ENV PATH="${PATH}:/usr/local/go/bin"

WORKDIR /tmp

RUN curl -L -o singularity-${SINGULARITY_VERSION}.tar.gz https://github.com/sylabs/singularity/releases/download/v${SINGULARITY_VERSION}/singularity-${SINGULARITY_VERSION}.tar.gz \
    && tar -xzf singularity-${SINGULARITY_VERSION}.tar.gz

WORKDIR /tmp/singularity

RUN ./mconfig \
    && make -C builddir \
    && make -C builddir install

WORKDIR /

# Install Minicluster
ENV MINICLUSTER_HOME="/opt/minicluster"

RUN MINICLUSTER_BASE="https://github.com/bolkedebruin/minicluster/releases/download/" \
    && MINICLUSTER_VER="1.1" \
    && MINICLUSTER_URL="${MINICLUSTER_BASE}${MINICLUSTER_VER}/minicluster-${MINICLUSTER_VER}-SNAPSHOT-bin.zip" \
    && MINICLUSTER_TMP_FILE="/tmp/minicluster.zip" \
    && mkdir -pv "${MINICLUSTER_HOME}" \
    && curl --fail --location "${MINICLUSTER_URL}" --output "${MINICLUSTER_TMP_FILE}" \
    && unzip "${MINICLUSTER_TMP_FILE}" -d "/opt" \
    && rm "${MINICLUSTER_TMP_FILE}"

# Install Docker
RUN curl --fail --location https://download.docker.com/linux/debian/gpg | apt-key add - \
    && add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/debian stretch stable" \
    && apt-get update \
    && apt-get -y install --no-install-recommends docker-ce \
    && apt-get autoremove -yqq --purge \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Install kubectl
ARG KUBECTL_VERSION="v1.15.3"

RUN KUBECTL_URL="https://storage.googleapis.com/kubernetes-release/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl" \
  && curl --fail --location  "${KUBECTL_URL}" --output "/usr/local/bin/kubectl" \
  && chmod +x /usr/local/bin/kubectl

# Install Kind
ARG KIND_VERSION="v0.6.1"

RUN KIND_URL="https://github.com/kubernetes-sigs/kind/releases/download/${KIND_VERSION}/kind-linux-amd64" \
   && curl --fail --location "${KIND_URL}" --output "/usr/local/bin/kind" \
   && chmod +x /usr/local/bin/kind

# Setup PIP
# By default PIP install run without cache to make image smaller
ARG PIP_NO_CACHE_DIR="true"
ENV PIP_NO_CACHE_DIR=${PIP_NO_CACHE_DIR}
RUN echo "Pip no cache dir: ${PIP_NO_CACHE_DIR}"

# PIP version used to install dependencies
ARG PIP_VERSION="19.0.2"
ENV PIP_VERSION=${PIP_VERSION}
RUN echo "Pip version: ${PIP_VERSION}"

RUN pip install --upgrade pip==${PIP_VERSION}

# Install Google SDK
ENV GCLOUD_HOME="/opt/gcloud"

RUN GCLOUD_VERSION="274.0.1" \
    && GCOUD_URL="https://dl.google.com/dl/cloudsdk/channels/rapid/downloads/google-cloud-sdk-${GCLOUD_VERSION}-linux-x86_64.tar.gz" \
    && GCLOUD_TMP_FILE="/tmp/gcloud.tar.gz" \
    && export CLOUDSDK_CORE_DISABLE_PROMPTS=1 \
    && mkdir -p /opt/gcloud \
    && curl "${GCOUD_URL}" -o "${GCLOUD_TMP_FILE}"\
    && tar xzf "${GCLOUD_TMP_FILE}" --strip-components 1 -C "${GCLOUD_HOME}" \
    && rm -rf "${GCLOUD_TMP_FILE}" \
    && echo '. /opt/gcloud/completion.bash.inc' >> /etc/bash.bashrc

ENV PATH="$PATH:${GCLOUD_HOME}/bin"

# Install AWS CLI
# Unfortunately, AWS does not provide a versioned bundle
ENV AWS_HOME="/opt/aws"

RUN AWS_TMP_DIR="/tmp/awscli/" \
    && AWS_TMP_BUNDLE="${AWS_TMP_DIR}/awscli-bundle.zip" \
    && AWS_URL="https://s3.amazonaws.com/aws-cli/awscli-bundle.zip" \
    && mkdir -pv "${AWS_TMP_DIR}" \
    && curl "${AWS_URL}" -o "${AWS_TMP_BUNDLE}" \
    && unzip "${AWS_TMP_BUNDLE}" -d "${AWS_TMP_DIR}" \
    && "${AWS_TMP_DIR}/awscli-bundle/install" -i "${AWS_HOME}" -b /usr/local/bin/aws \
    && echo "complete -C '${AWS_HOME}/bin/aws_completer' aws" >> /etc/bash.bashrc \
    && rm -rf "${AWS_TMP_DIR}"

ARG HOME=/root
ENV HOME=${HOME}

ARG AIRFLOW_HOME=/root/airflow
ENV AIRFLOW_HOME=${AIRFLOW_HOME}

ARG AIRFLOW_SOURCES=/opt/airflow
ENV AIRFLOW_SOURCES=${AIRFLOW_SOURCES}

WORKDIR ${AIRFLOW_SOURCES}

RUN mkdir -pv ${AIRFLOW_HOME} \
    mkdir -pv ${AIRFLOW_HOME}/dags \
    mkdir -pv ${AIRFLOW_HOME}/logs

# Increase the value here to force reinstalling Apache Airflow pip dependencies
ARG PIP_DEPENDENCIES_EPOCH_NUMBER="3"
ENV PIP_DEPENDENCIES_EPOCH_NUMBER=${PIP_DEPENDENCIES_EPOCH_NUMBER}

# Optimizing installation of Cassandra driver
# Speeds up building the image - cassandra driver without CYTHON saves around 10 minutes
ARG CASS_DRIVER_NO_CYTHON="1"
# Build cassandra driver on multiple CPUs
ARG CASS_DRIVER_BUILD_CONCURRENCY="8"

ENV CASS_DRIVER_BUILD_CONCURRENCY=${CASS_DRIVER_BUILD_CONCURRENCY}
ENV CASS_DRIVER_NO_CYTHON=${CASS_DRIVER_NO_CYTHON}

ARG AIRFLOW_REPO=apache/airflow
ENV AIRFLOW_REPO=${AIRFLOW_REPO}

ARG AIRFLOW_BRANCH=master
ENV AIRFLOW_BRANCH=${AIRFLOW_BRANCH}

# Airflow Extras installed
ARG AIRFLOW_EXTRAS="all"
ENV AIRFLOW_EXTRAS=${AIRFLOW_EXTRAS}

RUN echo "Installing with extras: ${AIRFLOW_EXTRAS}."

ARG AIRFLOW_CONTAINER_CI_OPTIMISED_BUILD="false"
ENV AIRFLOW_CONTAINER_CI_OPTIMISED_BUILD=${AIRFLOW_CONTAINER_CI_OPTIMISED_BUILD}

# By changing the CI build epoch we can force reinstalling Arflow from the current master
# It can also be overwritten manually by setting the AIRFLOW_CI_BUILD_EPOCH environment variable.
ARG AIRFLOW_CI_BUILD_EPOCH="1"
ENV AIRFLOW_CI_BUILD_EPOCH=${AIRFLOW_CI_BUILD_EPOCH}

# In case of CI-optimised builds we want to pre-install master version of airflow dependencies so that
# We do not have to always reinstall it from the scratch.
# This can be reinstalled from latest master by increasing PIP_DEPENDENCIES_EPOCH_NUMBER.
# And is automatically reinstalled from the scratch every month
RUN \
    if [[ "${AIRFLOW_CONTAINER_CI_OPTIMISED_BUILD}" == "true" ]]; then \
        pip install \
        "https://github.com/apache/airflow/archive/${AIRFLOW_BRANCH}.tar.gz#egg=apache-airflow[${AIRFLOW_EXTRAS}]" \
        && pip uninstall --yes apache-airflow; \
    fi

# Link dumb-init for backwards compatibility (so that older images also work)
RUN ln -sf /usr/bin/dumb-init /usr/local/bin/dumb-init

# Install NPM dependencies here. The NPM dependencies don't change that often and we already have pip
# installed dependencies in case of CI optimised build, so it is ok to install NPM deps here
# Rather than after setup.py is added.
COPY airflow/www/yarn.lock airflow/www/package.json ${AIRFLOW_SOURCES}/airflow/www/

RUN yarn --cwd airflow/www install --frozen-lockfile --no-cache

# Note! We are copying everything with airflow:airflow user:group even if we use root to run the scripts
# This is fine as root user will be able to use those dirs anyway.

# Airflow sources change frequently but dependency configuration won't change that often
# We copy setup.py and other files needed to perform setup of dependencies
# So in case setup.py changes we can install latest dependencies required.
COPY setup.py ${AIRFLOW_SOURCES}/setup.py
COPY setup.cfg ${AIRFLOW_SOURCES}/setup.cfg

COPY airflow/version.py ${AIRFLOW_SOURCES}/airflow/version.py
COPY airflow/__init__.py ${AIRFLOW_SOURCES}/airflow/__init__.py
COPY airflow/bin/airflow ${AIRFLOW_SOURCES}/airflow/bin/airflow

# The goal of this line is to install the dependencies from the most current setup.py from sources
# This will be usually incremental small set of packages in CI optimized build, so it will be very fast
# In non-CI optimized build this will install all dependencies before installing sources.
RUN pip install -e ".[${AIRFLOW_EXTRAS}]"

# Copy all the www/ files we need to compile assets. Done as two separate COPY
# commands so as otherwise it copies the _contents_ of static/ in to www/
COPY airflow/www/webpack.config.js ${AIRFLOW_SOURCES}/airflow/www/
COPY airflow/www/static ${AIRFLOW_SOURCES}/airflow/www/static/

# Package JS/css for production
RUN yarn --cwd airflow/www run prod

COPY scripts/docker/entrypoint.sh /entrypoint.sh

# Copy selected subdirectories only
COPY .github/ ${AIRFLOW_SOURCES}/.github/
COPY dags/ ${AIRFLOW_SOURCES}/dags/
COPY common/ ${AIRFLOW_SOURCES}/common/
COPY licenses/ ${AIRFLOW_SOURCES}/licenses/
COPY scripts/ ${AIRFLOW_SOURCES}/scripts/
COPY docs/ ${AIRFLOW_SOURCES}/docs/
COPY tests/ ${AIRFLOW_SOURCES}/tests/
COPY airflow/ ${AIRFLOW_SOURCES}/airflow/
COPY .coveragerc .rat-excludes .flake8 pylintrc LICENSE MANIFEST.in NOTICE CHANGELOG.txt \
     .github pytest.ini \
     setup.cfg setup.py \
     ${AIRFLOW_SOURCES}/

# Needed for building images via docker-in-docker inside the docker
COPY Dockerfile ${AIRFLOW_SOURCES}/Dockerfile

# Install autocomplete for airflow
RUN register-python-argcomplete airflow >> ~/.bashrc

# Install autocomplete for Kubeclt
RUN echo "source /etc/bash_completion" >> ~/.bashrc \
    && kubectl completion bash >> ~/.bashrc

WORKDIR ${AIRFLOW_SOURCES}

# Additional python deps to install
ARG ADDITIONAL_PYTHON_DEPS=""

RUN if [[ -n "${ADDITIONAL_PYTHON_DEPS}" ]]; then \
        pip install ${ADDITIONAL_PYTHON_DEPS}; \
    fi

WORKDIR ${AIRFLOW_SOURCES}

ENV PATH="${HOME}:${PATH}"

EXPOSE 8080

ENTRYPOINT ["/usr/bin/dumb-init", "--", "/entrypoint.sh"]

CMD ["--help"]
