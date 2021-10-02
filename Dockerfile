FROM ubuntu:focal

SHELL [ "bash", "-c" ]

RUN apt-get update -qy && \
    apt-get install -qy wget curl && \
    apt-get clean -qy

VOLUME /monero

#ARG MONERO_VERSION=v0.16.0.3
ARG MONERO_VERSION=latest
ENV MONERO_VERSION ${MONERO_VERSION}

ARG MONERO_INSTALLDIR=/usr/bin/
ENV MONERO_INSTALLDIR ${MONERO_INSTALLDIR}

ARG MONERO_CONFIG_FILE=/monero/monerod.conf
ENV MONERO_CONFIG_FILE ${MONERO_CONFIG_FILE}

ARG MONERO_FULL_URL="https://downloads.getmonero.org/cli/monero-linux-x64-${MONERO_VERSION}.tar.bz2"
ENV MONERO_FULL_URL ${MONERO_FULL_URL}

ARG MONERO_LATEST_URL="https://downloads.getmonero.org/gui/linux64"
ENV MONERO_LATEST_URL ${MONERO_LATEST_URL}

RUN cd /tmp && \
    if [[ "$MONERO_VERSION" == "latest" ]]; then \
        echo -e "\n\n >>> Downloading the latest version of monero from: $MONERO_LATEST_URL ... \n\n"; \
        wget -q -O - "$MONERO_LATEST_URL" | tar xvjf - && \
        cp -v monero-*/* ${MONERO_INSTALLDIR}; \
        ls monero-*/extras &> /dev/null && cp -v monero-*/extras/* ${MONERO_INSTALLDIR}; \
    else \
        echo -e "\n\n >>> Downloading monero version ${MONERO_VERSION} from: $MONERO_FULL_URL ... \n\n"; \
        wget -q -O - "$MONERO_FULL_URL" | tar xvjf - && \
        # wget -q -O - https://downloads.getmonero.org/cli/monero-linux-x64-${MONERO_VERSION}.tar.bz2 | tar xvjf - && \
        cp -v /tmp/monero-*/* ${MONERO_INSTALLDIR} && \
        ls monero-*/extras &> /dev/null && cp -v monero-*/extras/* ${MONERO_INSTALLDIR}; \
        rm -rf /tmp/monero-*; \
    fi

WORKDIR /monero

EXPOSE 18080
EXPOSE 18081

CMD ["sh", "-c", "monerod", "--config-file", "${MONERO_CONFIG_FILE}", "--non-interactive", "--confirm-external-bind"]


