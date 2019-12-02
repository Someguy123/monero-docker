FROM ubuntu:bionic

RUN apt-get update -qy && \
    apt-get install -qy wget curl && \
    apt-get clean -qy

VOLUME /monero

ARG MONERO_VERSION=v0.15.0.1
ENV MONERO_VERSION ${MONERO_VERSION}

ARG MONERO_INSTALLDIR=/usr/bin/
ENV MONERO_INSTALLDIR ${MONERO_INSTALLDIR}

RUN cd /tmp && wget https://dlsrc.getmonero.org/cli/monero-linux-x64-${MONERO_VERSION}.tar.bz2 && \
    tar xvf monero-linux-x64-${MONERO_VERSION}.tar.bz2 && \
    cp -v /tmp/monero-x86_64-linux-*/* ${MONERO_INSTALLDIR} && \
    rm -rf /tmp/monero-*

WORKDIR /monero

EXPOSE 18080
EXPOSE 18081

CMD ["sh", "-c", "monerod", "--config-file", "/monero/monerod.conf", "--non-interactive", "--confirm-external-bind"]


