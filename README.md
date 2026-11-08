# opensourcepos-railway

Railway wrapper images for [OpenSourcePOS](https://github.com/opensourcepos/opensourcepos) 3.4.3.

- `ghcr.io/bon5co/opensourcepos-railway:3.4.3` - upstream `jekkos/opensourcepos` pinned by digest, plus an entrypoint that binds Apache to `$PORT`, provisions and persists the encryption keys on `/data`, runs migrations and sets the admin password from `ADMIN_PASSWORD`.
- `ghcr.io/bon5co/opensourcepos-railway-mariadb:11.8.2` - MariaDB with the `ospos` user and database preset.

Required variables: `MYSQL_HOST_NAME`, `MYSQL_PASSWORD`, `ADMIN_PASSWORD`. The container refuses to boot with any of them empty.
