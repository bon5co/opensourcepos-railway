# OpenSourcePOS for Railway.
# Upstream pinned by digest (jekkos/opensourcepos 3.4.3). The wrapper binds Apache to Railway's injected PORT (the
# healthcheck dials it), trusts X-Forwarded-Proto, derives the allowed hostname from RAILWAY_PUBLIC_DOMAIN, keeps the
# generated encryption/throttle keys and the uploads on the one volume at /data, waits for MariaDB, runs the
# migrations, and replaces the published default admin password (pointofsale) with ADMIN_PASSWORD on first boot.
FROM jekkos/opensourcepos@sha256:3ed42c389b661ed73e73004c1de1b6f82fff6238cf5c9674b5ba3206ccdb5f72

ENV CI_ENVIRONMENT=production \
    FORCE_HTTPS=true \
    PHP_TIMEZONE=UTC \
    MYSQL_USERNAME=ospos \
    MYSQL_DB_NAME=ospos

COPY railway-entrypoint.sh /usr/local/bin/railway-entrypoint.sh
RUN chmod 755 /usr/local/bin/railway-entrypoint.sh

ENTRYPOINT ["/usr/local/bin/railway-entrypoint.sh"]
CMD ["apache2-foreground"]
