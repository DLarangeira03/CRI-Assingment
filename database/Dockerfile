FROM postgres:15

RUN apt-get update && \
    apt-get install -y aide && \
    rm -rf /var/lib/apt/lists/*

COPY aide.conf /etc/aide/aide.conf

COPY docker-entrypoint-wrapper.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/docker-entrypoint-wrapper.sh

ENTRYPOINT ["docker-entrypoint-wrapper.sh"]
CMD ["postgres"]
