ARG VERSION=10.19
ARG LANGUAGE=en_GB

FROM postgres:${VERSION}

ENV LOCALE=${LANGUAGE:-en_GB}
RUN localedef -i $LOCALE -c -f UTF-8 -A /usr/share/locale/locale.alias $LOCALE.UTF-8
ENV LANG $LOCALE.utf8

ADD --chown=postgres:postgres init.sh /var/lib/postgresql/scripts/
ADD --chown=postgres:postgres postgresql.conf pg_hba.conf /var/lib/postgresql/conf/

WORKDIR /var/lib/postgresql

CMD ["--config_file=/var/lib/postgresql/conf/postgresql.conf", "--hba_file=/var/lib/postgresql/conf/pg_hba.conf"]
