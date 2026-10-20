# Mule Community Runtime + mybestsim-integration-api-test (Studio project, Mule 4.7.0 by default).
# Build context = repository root. The application jar is built inside the image (multi-stage), no local Maven needed:
#   docker build -f mule/Dockerfile -t mybestsim-mule .
#
# Other runtime versions (the app only needs minMuleVersion 4.7.0 and a runtime built for Java 8/11/17):
#   docker build -f mule/Dockerfile --build-arg MULE_VERSION=4.9.0 -t mybestsim-mule:4.9.0 .
# Enterprise runtime (e.g. the 4.12.1 zip you downloaded): host the zip on a URL you control and pass it, with a license:
#   docker build -f mule/Dockerfile --build-arg MULE_DIST_URL=https://.../mule-ee-distribution-standalone-4.12.1.zip \
#                --build-arg MULE_DIST_DIR=mule-enterprise-standalone-4.12.1 -t mybestsim-mule:ee .
ARG JAVA_IMAGE=eclipse-temurin:17-jre

FROM maven:3.9-eclipse-temurin-17 AS build
WORKDIR /src
COPY mule/mybestsim-integration-api-test/ ./
RUN mvn -B -q -DskipTests package

FROM ${JAVA_IMAGE}

ARG MULE_VERSION=4.7.0
ARG MULE_DIST_URL=https://repository.mulesoft.org/releases/org/mule/distributions/mule-standalone/${MULE_VERSION}/mule-standalone-${MULE_VERSION}.zip
ARG MULE_DIST_DIR=mule-standalone-${MULE_VERSION}

RUN apt-get update && apt-get install -y --no-install-recommends curl unzip ca-certificates \
    && curl -fsSL -o /tmp/mule.zip "${MULE_DIST_URL}" \
    && unzip -q /tmp/mule.zip -d /opt && mv "/opt/${MULE_DIST_DIR}" /opt/mule \
    && rm /tmp/mule.zip && apt-get purge -y unzip && rm -rf /var/lib/apt/lists/* \
    && useradd -r -u 10001 -d /opt/mule mule && mkdir -p /data/incoming /data/processed /data/rejected \
    && chown -R mule /opt/mule /data

COPY --from=build /src/target/mybestsim-integration-api-test-*-mule-application.jar /opt/mule/apps/mybestsim-integration-api.jar
RUN chown mule /opt/mule/apps/mybestsim-integration-api.jar

USER mule
ENV MULE_HOME=/opt/mule \
    MYBESTSIM_DB_SSLMODE=require \
    MYBESTSIM_HTTP_PORT=8081 \
    MYBESTSIM_SOURCE_DIR=/data/incoming \
    MYBESTSIM_PROCESSED_DIR=/data/processed \
    MYBESTSIM_REJECTED_DIR=/data/rejected \
    MYBESTSIM_SCHEDULER_ENABLED=false \
    MYBESTSIM_SCHEDULER_FREQUENCY_MS=86400000
EXPOSE 8081
VOLUME ["/data"]
HEALTHCHECK --interval=30s --timeout=5s --start-period=90s --retries=3 \
  CMD curl -fs http://localhost:${MYBESTSIM_HTTP_PORT}/health || exit 1
# Secrets (MYBESTSIM_DB_*, MYBESTSIM_ADMIN_API_KEY, ...) are injected at run time by the platform.
CMD ["/opt/mule/bin/mule", "-M-Dmule.env=prod"]
