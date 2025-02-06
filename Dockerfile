FROM alpine:latest

RUN apk add --no-cache bash curl jq coreutils

COPY rerun.sh /rerun.sh
RUN chmod +x /rerun.sh

ENTRYPOINT ["/rerun.sh"]
