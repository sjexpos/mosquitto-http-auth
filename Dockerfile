FROM ubuntu:bionic as build

LABEL Author="Sergio Exposito <sjexpos@gmail.com>"

RUN echo "***** Updating Ubuntu Bionic (18.04) *****" \
 && apt-get update; exit 0 && apt-get upgrade; exit 0

RUN echo "***** Installing basic libraries *****" \
&& apt-get install -y git build-essential make cmake gettext-base \
 && apt-get install -y libc-ares-dev libwebsockets-dev xsltproc docbook-xsl libcurl4-openssl-dev

 RUN cd /tmp \
  && git clone https://github.com/eclipse/mosquitto \
  && cd /tmp/mosquitto \
  && git checkout v1.6.8 \
  && make WITH_DOCS=no WITH_TLS=yes WITH_WEBSOCKETS=yes

RUN cd /tmp \
 && git clone https://github.com/jpmens/mosquitto-auth-plug \
 && cd /tmp/mosquitto-auth-plug \
 && git checkout 0.1.3 

RUN cp /tmp/mosquitto-auth-plug/config.mk.in /tmp/mosquitto-auth-plug/config.mk \
 && sed -i "/BACKEND_MYSQL ?= yes/c\BACKEND_MYSQL ?= no" /tmp/mosquitto-auth-plug/config.mk \
 && sed -i "/BACKEND_HTTP ?= no/c\BACKEND_HTTP ?= yes" /tmp/mosquitto-auth-plug/config.mk \
 && sed -i "/MOSQUITTO_SRC =/c\MOSQUITTO_SRC = /tmp/mosquitto" /tmp/mosquitto-auth-plug/config.mk \
 && sed -i '/int mosquitto_auth_unpwd_check(void \*userdata, const struct mosquitto \*client, const char \*username, const char \*password)/c\int mosquitto_auth_unpwd_check(void \*userdata, struct mosquitto \*client, const char \*username, const char \*password)' /tmp/mosquitto-auth-plug/auth-plug.c \
 && sed -i '/int mosquitto_auth_acl_check(void \*userdata, int access, const struct mosquitto \*client, const struct mosquitto_acl_msg \*msg)/c\int mosquitto_auth_acl_check(void \*userdata, int access, struct mosquitto \*client, const struct mosquitto_acl_msg \*msg)' /tmp/mosquitto-auth-plug/auth-plug.c \
 && sed -i '/int mosquitto_auth_psk_key_get(void \*userdata, const struct mosquitto \*client, const char \*hint, const char \*identity, char \*key, int max_key_len)/c\int mosquitto_auth_psk_key_get(void *userdata, struct mosquitto *client, const char *hint, const char *identity, char *key, int max_key_len)' /tmp/mosquitto-auth-plug/auth-plug.c \
 && ln -s /tmp/mosquitto/lib/libmosquitto.so.1 /tmp/mosquitto/lib/libmosquitto.so \
 && cd /tmp/mosquitto-auth-plug \
 && make








FROM ubuntu:bionic as runtime

RUN echo "***** Updating Ubuntu Bionic (18.04) *****" \
 && apt-get update; exit 0 && apt-get upgrade; exit 0

RUN echo "***** Installing basic libraries *****" \
 && apt-get install -y gettext-base libcurl4 libwebsockets8

RUN mkdir -p /opt/mosquitto

COPY --from=build /tmp/mosquitto/lib/libmosquitto.so.1 /opt/mosquitto
COPY --from=build /tmp/mosquitto/lib/cpp/libmosquittopp.so.1 /opt/mosquitto
COPY --from=build /tmp/mosquitto/client/mosquitto_pub /opt/mosquitto
COPY --from=build /tmp/mosquitto/client/mosquitto_sub /opt/mosquitto
COPY --from=build /tmp/mosquitto/src/mosquitto /opt/mosquitto
COPY --from=build /tmp/mosquitto/src/mosquitto_passwd /opt/mosquitto
COPY --from=build /tmp/mosquitto-auth-plug/auth-plug.so /opt/mosquitto

COPY <<EOF /opt/mosquitto/mosquitto.conf.template
pid_file /var/run/mosquitto.pid

persistence true
persistence_location /opt/mosquitto/

log_dest stdout
log_type all
log_timestamp true

listener 1883
listener 7777
protocol websockets

allow_anonymous false

auth_plugin /opt/mosquitto/auth-plug.so
auth_opt_backends http
auth_opt_http_ip \${API_HOST}
auth_opt_http_port \${API_PORT}
auth_opt_http_getuser_uri /api/v1/mqtt/auth
auth_opt_http_superuser_uri /api/v1/mqtt/superuser
auth_opt_http_aclcheck_uri /api/v1/mqtt/acl

EOF

RUN adduser --no-create-home --disabled-login --gecos "" mosquitto; exit 0

COPY <<EOF /opt/mosquitto/run.sh
#!/bin/sh

export LD_LIBRARY_PATH=./:/opt/mosquitto/

/opt/mosquitto/mosquitto -c /opt/mosquitto/mosquitto.conf

status=$?
echo "Status:"$status
EOF

RUN chmod 755 /opt/mosquitto/run.sh

COPY <<EOF /docker-entrypoint.sh
#!/usr/bin/env sh
set -eu

envsubst '\${API_HOST} \${API_PORT} ' < /opt/mosquitto/mosquitto.conf.template > /opt/mosquitto/mosquitto.conf

exec "\$@"
EOF

RUN chmod 755 /docker-entrypoint.sh

WORKDIR /opt/mosquitto

ENTRYPOINT ["/docker-entrypoint.sh"]

CMD ["/opt/mosquitto/run.sh"]

