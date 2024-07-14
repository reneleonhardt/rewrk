FROM rust:1.79-alpine AS build

WORKDIR /code

COPY . .

# https://github.com/kpcyrd/mini-docker-rust/blob/main/Dockerfile
ENV RUSTFLAGS="-C target-feature=-crt-static"

RUN apk update \
 && apk add --no-cache musl-dev openssl-dev pkgconfig ca-certificates
RUN update-ca-certificates

RUN cargo build --release
RUN strip target/release/rewrk
RUN target/release/rewrk --version
RUN target/release/rewrk -c 1 -t 1 -d 2s -h https://github.com --http2

# Copy the binary into a new container for a smaller docker image
FROM alpine:3.20 AS runtime

COPY --from=build --chown=1000:1000 /code/target/release/rewrk /
COPY --from=build /etc/ssl /etc/ssl
RUN apk update \
 && apk add --no-cache libgcc tini \
 && rm -rf /lib/apk /lib/libapk* /etc/ssl/*.cnf.dist \
 && addgroup -g 1000 -S app && adduser -u 1000 -S app -G app --home /app
RUN /rewrk -c 1 -t 1 -d 2s -h https://github.com

# Squash all layers into one
FROM scratch
COPY --from=runtime /lib /lib
COPY --from=runtime /usr/bin /usr/bin
COPY --from=runtime /usr/lib /usr/lib
COPY --from=runtime /etc/passwd /etc/group /etc/shadow /etc/
COPY --from=runtime /etc/ssl /etc/ssl
COPY --from=runtime /sbin/tini /sbin/
COPY --from=runtime /rewrk /
USER app
WORKDIR /app

ENTRYPOINT ["/sbin/tini" , "--", "/rewrk"]
