PHP_VERSION := 7.2.15
WP_CLI_VERSION := 2.1.0

PHP_URL := http://nl1.php.net/get/php-$(PHP_VERSION).tar.xz/from/this/mirror
PHP_SOURCES := src/php-$(PHP_VERSION)

WP_CLI_URL := https://github.com/wp-cli/wp-cli/releases/download/v2.1.0/wp-cli-2.1.0.phar
WP_CLI := bin/wp

EXEC_WP_CLI := $(abspath build/php-$(PHP_VERSION)-defaults/bin/php) $(abspath $(WP_CLI))

.PHONY : all defaults wordpress

all : defaults wordpress

defaults : build/php-$(PHP_VERSION)-defaults
optimized : build/php-$(PHP_VERSION)-optimized
clang-optimized : build/php-$(PHP_VERSION)-clang-optimized

build/php-$(PHP_VERSION)-defaults : $(PHP_SOURCES)
	cd $(PHP_SOURCES) && ./configure --prefix=$(abspath $@) --with-openssl --with-mysqli --with-zlib
	$(MAKE) -C $(PHP_SOURCES) clean
	$(MAKE) -C $(PHP_SOURCES) -j$(shell nproc)
	$(MAKE) -C $(PHP_SOURCES) install

env :
	env

build/php-$(PHP_VERSION)-optimized : $(PHP_SOURCES)
	cd $(PHP_SOURCES) && \
		CFLAGS='-march=native -O2' \
		CXXFLAGS="$$CFLAGS" \
		sh -c '\
			./configure --prefix=$(abspath $@) --with-openssl --with-mysqli --with-zlib &&\
			make clean && make -j`nproc` && make install'

build/php-$(PHP_VERSION)-clang-optimized : $(PHP_SOURCES)
	cd $(PHP_SOURCES) && \
		CC=clang \
		CXX=clang++ \
		CFLAGS='-march=native -O2' \
		CXXFLAGS="$$CFLAGS" \
		sh -c '\
			./configure --prefix=$(abspath $@) --with-openssl --with-mysqli --with-zlib &&\
			make clean && make -j`nproc` && make install'

$(PHP_SOURCES) :
	rm -rf $@~
	mkdir -p $@~
	wget -O- $(PHP_URL) | tar xJf - -C $@~ --strip-components 1
	mv $@~ $@

wordpress : www/wp-config.php
	cd www && (\
		$(EXEC_WP_CLI) core is-installed || \
		$(EXEC_WP_CLI) core install \
		--url=http://localhost:5000 \
		--admin_user=admin \
		--admin_password=admin \
		--admin_email=info@example.com \
		--title=Example \
		--skip-email \
		)

www/wp-config.php : | www mysql_host
	cd www && \
		$(EXEC_WP_CLI) config create \
		--dbname=phpperf \
		--dbuser=root \
		--dbhost=$(shell cat mysql_host) \
		--dbcharset=utf8mb4 \
		--dbcollate=utf8mb4_unicode_ci \
		|| rm -f $(abspath $@)

www : | $(WP_CLI) defaults
	rm -rf $@~
	mkdir $@~
	cd $@~ && $(EXEC_WP_CLI) core download --version=5.0.3
	mv $@~ $@

mysql_host :
	docker start phpperf_mariadb >/dev/null || \
		docker run --detach --name phpperf_mariadb \
			-e MYSQL_ALLOW_EMPTY_PASSWORD=yes \
			-e MYSQL_DATABASE=phpperf mariadb:10.3
	docker inspect \
		--format '{{ range .NetworkSettings.Networks }}{{ .IPAddress }}{{ end }}' \
		phpperf_mariadb > $@~
	mv $@~ $@

$(WP_CLI) :
	mkdir -p $(dir $@)
	wget -O $@~ $(WP_CLI_URL)
	chmod +x $@~
	mv $@~ $@
