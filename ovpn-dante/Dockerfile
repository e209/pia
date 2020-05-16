FROM alpine:latest
LABEL Description="PIA OpenVPN client + Dante (sockd) proxy" 

EXPOSE 1080/tcp 1080/udp

HEALTHCHECK --interval=10s --timeout=1s --start-period=45s --retries=1 \
  CMD nc -z $(ip -o addr show eth0| awk '{print $4}' | cut -d/ -f1) 1080 || exit 1

ENV TERM=xterm

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["start-ovpn-dante"]


# package dante-server is in 'community' now; 'main' repositories are already present in base image, 'community' and 'testing' are not
    #&& echo "http://dl-cdn.alpinelinux.org/alpine/edge/testing" >> /etc/apk/repositories \

RUN true \
    && echo "http://dl-cdn.alpinelinux.org/alpine/edge/community" >> /etc/apk/repositories \
    && apk update \
    && apk --no-cache add bash iproute2 curl jq openvpn dante-server \
    && true


COPY ./ovpn-dante/addconf /addconf/

# including entrypoint.sh and other *.sh scripts, if any
COPY ./*.sh /usr/local/bin/ 
COPY ./ovpn-dante/*.sh /usr/local/bin/ 

RUN true \
    && chmod -R a+r /addconf \
    && chmod a+x /usr/local/bin/*.sh \
    && true

