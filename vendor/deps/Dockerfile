ARG BASE_IMAGE=almalinux:9
FROM ${BASE_IMAGE}

COPY . /build
WORKDIR /build

CMD ["bash", "-e", "scripts/build-all.sh"]
