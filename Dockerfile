FROM alpine:3

COPY rerun.sh /rerun.sh
RUN chmod +x /rerun.sh && \
    apk add --no-cache bash curl jq coreutils

ENTRYPOINT ["/rerun.sh"]
