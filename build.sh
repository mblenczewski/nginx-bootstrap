#!/bin/sh


export ROOT=$(pwd)
export SOURCES="${ROOT}/src"
export LOGS="${ROOT}/logs"
export MAKEFLAGS="-j$(nproc --all)"

export USE_LIBRESSL='true'
export NGINX_USER=root
export NGINX_GROUP=root


## Creating directory structure
[ -d "${SOURCES}" ] && rm -rf ${SOURCES}/* || mkdir ${SOURCES}
[ -d "${LOGS}" ] && rm -rf ${LOGS}/* || mkdir ${LOGS}


## Defines a package
## $1 : The name of the package variable group (e.g. MUSL, LINUX, GCC)
## $2 : The package source version
## $3 : The package source archive compression (e.g. gz, bz2, xz)
## $4 : The package source directory prefix
## $5 : The package source archive prefix. Overrides the PKG_DIR_PREFIX if defined
DEFINE () {
	local PKG_NAME=$1
	local PKG_VER=$2
	local PKG_COMPRESSION=$3
	local PKG_DIR_PREFIX=$4
	local PKG_ARCHIVE_PREFIX=$5

	local PKG_DIR=${PKG_DIR_PREFIX}${PKG_VER}
	local PKG_ARCHIVE=${PKG_ARCHIVE_PREFIX}${PKG_VER}.tar.${PKG_COMPRESSION}

	[ -n "${PKG_VER}" ] && printf -v ${PKG_NAME}_VER ${PKG_VER}
	printf -v ${PKG_NAME}_DIR ${PKG_DIR}
	printf -v ${PKG_NAME}_ARCHIVE ${PKG_ARCHIVE}

	export "${PKG_NAME}_VER" "${PKG_NAME}_DIR" "${PKG_NAME}_ARCHIVE"
}


## Extracts a package source archive, and runs the given callback function.
## $1 : Package definition variable group name (i.e. GCC, LINUX, ZLIB)
## $2 : Processing callback function, run in source directory after unzipping
## $3 : Vanity package name.
EXTRACT () {
	local PKG_VAR_GROUP_NAME=$1
	local PROCESS_FUNC=$2
	local PKG_VANITY_NAME=${3:-${PKG_VAR_GROUP_NAME}}

	local PKG_VER=${PKG_VAR_GROUP_NAME}_VER
	local PKG_VER=${!PKG_VER}
	local PKG_DIR=${PKG_VAR_GROUP_NAME}_DIR
	local PKG_DIR=${!PKG_DIR}
	local PKG_ARCHIVE=${PKG_VAR_GROUP_NAME}_ARCHIVE
	local PKG_ARCHIVE=${!PKG_ARCHIVE}

	echo "Extracting package ${PKG_VANITY_NAME} (ver. ${PKG_VER}) source: '${PKG_ARCHIVE}' -> '${PKG_DIR}'"
	pushd ${SOURCES} > /dev/null

	local STDOUT_LOG="${PKG_VANITY_NAME}.stdout.log"
	local STDERR_LOG="${PKG_VANITY_NAME}.stderr.log"

	echo "    stdout will be logged to '${STDOUT_LOG}'; stderr will be logged to '${STDERR_LOG}'"

	local TMP_OUT="${TMPDIR:-/tmp}/out.$$" TMP_ERR="${TMPDIR:-/tmp}/err.$$"
	mkfifo "${TMP_OUT}" "${TMP_ERR}"

	tar xf ${PKG_ARCHIVE} && cd ${PKG_DIR} && \
	$PROCESS_FUNC >"${TMP_OUT}" 2>"${TMP_ERR}" & \
	tee "${LOGS}/${STDOUT_LOG}" < "${TMP_OUT}" & \
	tee "${LOGS}/${STDERR_LOG}" < "${TMP_ERR}" && \
	echo "Successfully extracted and processed package ${PKG_VANITY_NAME}!" || \
	echo "Failed to extract or process package ${PKG_VANITY_NAME}!"

	cd ${SOURCES}

	rm "${TMP_OUT}" "${TMP_ERR}" > /dev/null
	popd > /dev/null
}


## Package definitions
###### NAME		VERSION		COMPRESSION	DIR_PREFIX	ARCHIVE_PREFIX
DEFINE "ZLIB"		"1.2.11" 	"gz"		"zlib-"		"zlib-"
DEFINE "PCRE"		"8.44"		"gz"		"pcre-"		"pcre-"
DEFINE "OPENSSL"	"1.1.1h"	"gz"		"openssl-"	"openssl-"
DEFINE "LIBRESSL"	"3.2.1"		"gz"		"libressl-"	"libressl-"
DEFINE "NGINX"		"1.19.0"	"gz"		"nginx-"	"nginx-"


## Downloading package sources
pushd ${SOURCES} > /dev/null
	wget http://zlib.net/${ZLIB_ARCHIVE}
	wget ftp://ftp.pcre.org/pub/pcre/${PCRE_ARCHIVE}
	wget http://www.openssl.org/source/${OPENSSL_ARCHIVE}
	wget https://ftp.openbsd.org/pub/OpenBSD/LibreSSL/${LIBRESSL_ARCHIVE}
	wget https://nginx.org/download/${NGINX_ARCHIVE}
popd > /dev/null


## Building packages
ZLIB () {
	echo "Extracted ZLIB!"
}
EXTRACT "ZLIB" ZLIB "zlib"


PCRE () {
	echo "Extracted PCRE!"
}
EXTRACT "PCRE" PCRE "pcre"


OPENSSL () {
	echo "Extracted OPENSSL!"
}
EXTRACT "OPENSSL" OPENSSL "openssl"


LIBRESSL () {
	echo "Extracted LIBRESSL!"
}
EXTRACT "LIBRESSL" LIBRESSL "libressl"


NGINX () {
	echo "Extracted NGINX!"

	local NGINX_PREFIX="/usr/local/nginx"

	local INCLUDED_MODULES=(\
		--with-http_v2_module \
		--with-http_ssl_module \
		--with-mail \
		--with-mail_ssl_module \
		--with-stream \
		--with-stream_ssl_module \
		--with-stream_ssl_preread_module \
		--with-http_gunzip_module \
		--with-http_gzip_static_module \
	)

	local EXCLUDED_MODULES=(\
		--without-http_fastcgi_module \
		--without-http_scgi_module \
		--without-http_uwsgi_module \
		--without-http_grpc_module \
		--without-http_empty_gif_module \
	)

	git clone https://github.com/openresty/headers-more-nginx-module.git "${SOURCES}/ngx_headers_more"
	pushd "${SOURCES}/ngx_headers_more" > /dev/null
		git submodule update --init
	popd > /dev/null

	git clone https://github.com/google/ngx_brotli.git "${SOURCES}/ngx_brotli"
	pushd "${SOURCES}/ngx_brotli" > /dev/null
		git submodule update --init
	popd > /dev/null

	local CUSTOM_MODULES=(\
		--add-module="${SOURCES}/ngx_headers_more" \
		--add-module="${SOURCES}/ngx_brotli" \
	)

	local WITH_SSL_LIB=$(\
		[ "${USE_LIBRESSL}" = 'true' ] \
		&& echo "--with-openssl=${SOURCES}/${LIBRESSL_DIR}" \
		|| echo "--with-openssl=${SOURCES}/${OPENSSL_DIR}" \
	)

	./configure \
		--prefix="${NGINX_PREFIX}" \
		--sbin-path="${NGINX_PREFIX}/sbin/nginx" \
		--conf-path="${NGINX_PREFIX}/conf/nginx.conf" \
		--pid-path="${NGINX_PREFIX}/logs/nginx.pid" \
		--error-log-path="${NGINX_PREFIX}/logs/error.log" \
		--http-log-path="${NGINX_PREFIX}/logs/access.log" \
		--user=${NGINX_USER} \
		--group=${NGINX_GROUP} \
		\
		${WITH_SSL_LIB} \
		--with-pcre="${SOURCES}/${PCRE_DIR}" \
		--with-pcre-jit \
		--with-zlib="${SOURCES}/${ZLIB_DIR}" \
		\
		--with-file-aio \
		--with-threads \
		--with-compat \
		\
		${INCLUDED_MODULES[@]} \
		${EXCLUDED_MODULES[@]} \
		${CUSTOM_MODULES[@]}

	make && make install

	cp ${ROOT}/nginx.service /lib/systemd/system/nginx.service

	mv ${NGINX_PREFIX}/conf/nginx.conf ${NGINX_PREFIX}/conf/nginx.conf.bak
	cp ${ROOT}/nginx.conf ${NGINX_PREFIX}/conf/nginx.conf

	[ -d "${NGINX_PREFIX}/conf/snippets" ] && rm -rf ${NGINX_PREFIX}/conf/snippets
	mkdir ${NGINX_PREFIX}/conf/snippets
	cp ${ROOT}/nginx-conf-snippets/* ${NGINX_PREFIX}/conf/snippets

	[ -d "${NGINX_PREFIX}/sites-available" ] && rm -rf ${NGINX_PREFIX}/sites-available
	mkdir ${NGINX_PREFIX}/sites-available
	cp ${ROOT}/website.conf ${NGINX_PREFIX}/sites-available
	ln -s ${NGINX_PREFIX}/sites-available ${NGINX_PREFIX}/conf/sites-available

	[ -d "${NGINX_PREFIX}/sites-enabled" ] && rm -rf ${NGINX_PREFIX}/sites-enabled
	mkdir ${NGINX_PREFIX}/sites-enabled
	ln -s ${NGINX_PREFIX}/sites-available/website.conf ${NGINX_PREFIX}/sites-enabled/website.conf
	ln -s ${NGINX_PREFIX}/sites-available ${NGINX_PREFIX}/conf/sites-enabled

	cp ${ROOT}/dhparam.pem /etc/ssl/dhparam.pem
}
EXTRACT "NGINX" NGINX "nginx"

