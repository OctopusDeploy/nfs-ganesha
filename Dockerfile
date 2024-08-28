# Copyright 2017 The Kubernetes Authors.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Modified from https://github.com/rootfs/nfs-ganesha-docker by Huamin Chen
#
# NOTE: This Dockerfile is maintained to support being built both on amd64 and
#       arm64 architectures.
#
# List of Fedora versions: https://en.wikipedia.org/wiki/Fedora_version_history#Version_history
ARG FEDORA_VERSION=40



FROM registry.fedoraproject.org/fedora:${FEDORA_VERSION} AS build

# Build ganesha from source, install it to /usr/local and a use multi stage build to have a smaller image
# Set NFS_V4_RECOV_ROOT to /export

# Install dependencies on separated lines to be easier to track changes using git blame
RUN dnf install -y \
	bison \
	cmake \
	dbus-devel \
	flex \
	tar \
	gcc \
	gcc-c++ \
	git \
	jemalloc-devel \
	krb5-devel \
	libblkid-devel \
	libnfsidmap-devel \
	libnsl2-devel \
	libntirpc-devel \
	libuuid-devel \
    libacl-devel \
	ninja-build \
	patch \
	userspace-rcu-devel \
	xfsprogs-devel

# Clone specific version of ganesha
# Keep version in sync with .github/workflows/docker-build.yml
ARG GANESHA_VERSION=V5.9
RUN git clone --branch ${GANESHA_VERSION} --recurse-submodules https://github.com/nfs-ganesha/nfs-ganesha

WORKDIR /nfs-ganesha

RUN mkdir -p /usr/local \
    && cmake -DCMAKE_BUILD_TYPE=Release -DBUILD_CONFIG=vfs_only \
    -DUSE_DBUS=OFF -DUSE_NFS3=OFF -DUSE_NLM=OFF -DUSE_RQUOTA=OFF -DUSE_9P=OFF -D_MSPAC_SUPPORT=OFF -DRPCBIND=OFF \
    -DUSE_RADOS_RECOV=OFF -DRADOS_URLS=OFF -DUSE_FSAL_VFS=ON -DUSE_FSAL_XFS=OFF \
    -DUSE_FSAL_PROXY_V4=OFF -DUSE_FSAL_PROXY_V3=OFF -DUSE_FSAL_LUSTRE=OFF -DUSE_FSAL_LIZARDFS=OFF \
    -DUSE_FSAL_KVSFS=OFF -DUSE_FSAL_CEPH=OFF -DUSE_FSAL_GPFS=OFF -DUSE_FSAL_PANFS=OFF -DUSE_FSAL_GLUSTER=OFF \
    -DUSE_GSS=NO -DHAVE_ACL_GET_FD_NP=ON -DHAVE_ACL_SET_FD_NP=ON \
    -DCMAKE_INSTALL_PREFIX=/usr/local src/ \
	  && make \
	  && make install
    
RUN mkdir -p /ganesha-extra \
    && mkdir -p /ganesha-extra/etc/dbus-1/system.d \
    && cp src/scripts/ganeshactl/org.ganesha.nfsd.conf /ganesha-extra/etc/dbus-1/system.d/

FROM registry.fedoraproject.org/fedora-minimal:${FEDORA_VERSION} AS run

# Install dependencies on separated lines to be easier to track changes using git blame
RUN microdnf install -y \
	dbus-x11 \
	hostname \
	jemalloc \
	libblkid \
	libnfsidmap \
	libntirpc \
	libuuid \
	nfs-utils \
	rpcbind \
	userspace-rcu \
	xfsprogs \
    && microdnf clean all

RUN mkdir -p /var/run/dbus \
    && mkdir -p /octopus

# add libs from /usr/local/lib64
RUN echo /usr/local/lib64 > /etc/ld.so.conf.d/local_libs.conf

# do not ask systemd for user IDs or groups (slows down dbus-daemon start)
RUN sed -i s/systemd// /etc/nsswitch.conf

COPY --from=build /usr/local /usr/local/
COPY --from=build /ganesha-extra /

# run ldconfig after libs have been copied
RUN ldconfig

# only expose the nfsd since for v4 only that is necessary
EXPOSE 2049/tcp

COPY ganesha.conf /etc/ganesha/ganesha.conf

ENTRYPOINT ["/usr/local/bin/ganesha.nfsd","-F","-p","/var/run/ganesha.pid","-f","/etc/ganesha/ganesha.conf"]