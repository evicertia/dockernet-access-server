ARG VERSION="0.0.0.0"
FROM kylemanna/openvpn:latest

LABEL maintainer="Pablo Ruiz <pablo@evicertia.com"

RUN 	apk update \
	&& apk --no-cache add bash curl dnsmasq ed supervisor \
	&& mkdir -p /etc/dnsmasq.d

RUN curl -sSL https://download.docker.com/linux/static/stable/x86_64/docker-18.09.5.tgz | tar zx -C /tmp \
	&& mv /tmp/docker/docker /usr/local/bin/ \
	&& rm -rf /tmp/docker 

COPY files/dnsmasq.conf /etc/dnsmasq.conf
COPY files/supervisord.conf /etc/supervisord.conf
COPY scripts/evilogo.sh /main.sh
COPY scripts/dnssrv.sh /dnssrv.sh
COPY scripts/ovpnsrv.sh /ovpnsrv.sh
COPY scripts/on-client-connect.sh /usr/local/sbin/on-client-connect.sh

ENV 	DNS_DOMAIN="" \
	EXTRA_HOSTS="" \
	HOSTMACHINE_IP="" \
	NAMING="default" \
	NETWORK="bridge" \
	FALLBACK_DNS="gateway.docker.internal"

EXPOSE 53/udp
EXPOSE 53/tcp
VOLUME /etc/openvpn

CMD ["/main.sh", "/usr/bin/supervisord", "-c", "/etc/supervisord.conf"]
