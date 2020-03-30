FROM python:3.6-stretch AS builder

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

ARG NODE_VERSION="8.x"
# hadolint ignore=DL3008
RUN curl -sL "https://deb.nodesource.com/setup_${NODE_VERSION}" | bash - \
 && apt-get install --no-install-recommends -y \
      nodejs

ARG HADOLINT_VERSION=v1.17.1
RUN curl -fsSL "https://github.com/hadolint/hadolint/releases/download/${HADOLINT_VERSION}/hadolint-Linux-$(uname -m)" -o /usr/local/bin/hadolint  \
  && chmod +x /usr/local/bin/hadolint

COPY tools/install-mssql.sh /doccano/tools/install-mssql.sh
RUN /doccano/tools/install-mssql.sh --dev

COPY app/server/static/package*.json /doccano/app/server/static/
WORKDIR /doccano/app/server/static
RUN npm ci

COPY requirements.txt /
RUN pip install -r /requirements.txt \
 && pip wheel -r /requirements.txt -w /deps

COPY Dockerfile /
RUN hadolint /Dockerfile

COPY . /doccano

WORKDIR /doccano
RUN tools/ci.sh

FROM python:3.6-slim-stretch AS runtime

COPY --from=builder /doccano/tools/install-mssql.sh /doccano/tools/install-mssql.sh
RUN /doccano/tools/install-mssql.sh

RUN useradd -ms /bin/sh doccano

RUN mkdir /data \
 && chown doccano:doccano /data

COPY --from=builder /deps /deps
# hadolint ignore=DL3013
RUN pip install --no-cache-dir /deps/*.whl

COPY --from=cleaner --chown=doccano:doccano /doccano /doccano

VOLUME /data
ENV DATABASE_URL="sqlite:////data/doccano.db"

ENV DEBUG="True"
ENV SECRET_KEY="change-me-in-production"
ENV PORT="8000"
ENV WORKERS="2"
ENV GOOGLE_TRACKING_ID=""
ENV AZURE_APPINSIGHTS_IKEY=""

USER doccano
WORKDIR /doccano
EXPOSE ${PORT}

CMD ["/doccano/tools/run.sh"]
