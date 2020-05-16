FROM alpine:latest
LABEL Description="HTTP and SOCKS proxy (3proxy) for external access" 

EXPOSE 1080/tcp 3128/tcp

HEALTHCHECK --interval=30s --timeout=1s --start-period=45s --retries=1 \
  CMD nc -z $(nslookup $OVPN_CONTAINER_NAME | awk '$1~/Address:/ && $2!~/53$/ {print $2}') 1080 && \
      nc -z $(ip -o addr show eth0| awk '{print $4}' | cut -d/ -f1) 1080 || exit 1

ENV TERM=xterm

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["start-3proxy"]


# package '3proxy' is in 'testing'; 'main' repositories are already present in base image, 'community' and 'testing' are not

RUN true \
    && echo "http://dl-cdn.alpinelinux.org/alpine/edge/community" >> /etc/apk/repositories \
    && echo "http://dl-cdn.alpinelinux.org/alpine/edge/testing" >> /etc/apk/repositories \
    && apk update \
    && apk --no-cache add bash iproute2 3proxy \
    && true


COPY ./3proxy/addconf /addconf/

# including entrypoint.sh and other *.sh scripts, if any
COPY ./*.sh /usr/local/bin/ 
COPY ./3proxy/*.sh /usr/local/bin/ 

RUN true \
    && chmod -R a+r /addconf \
    && chmod a+x /usr/local/bin/*.sh \
    && true

