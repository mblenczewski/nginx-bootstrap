#!/bin/sh

echo "Please run this script as the root user!"
read -p "Press enter to continue..." _


NGINX_PREFIX="/usr/local/nginx"
NGINX_USER=nginx
NGINX_GROUP=nginx

groupadd $NGINX_GROUP
useradd $NGINX_USER -g $NGINX_GROUP

NGINX_INCLUDED_MODULES="--with-http_v2_module --with-http_ssl_module --with-mail --with-mail_ssl_module --with-stream --with-stream_ssl_module --with-stream_ssl_preread_module --with-http_gunzip_module --with-http_gzip_static_module"
NGINX_EXCLUDED_MODULES="--without-http_fastcgi_module --without-http_scgi_module --without-http_uwsgi_module --without-http_grpc_module --without-http_empty_gif_module"
NGINX_CUSTOM_MODULES="--add-module=../ngx_headers_more --add-module=../ngx_brotli"

SRC="sources"

# creating source directory
[ -d $SRC ] && rm -rf $SRC/* || mkdir $SRC
cd $SRC

# source package definitions
ZLIB_VER="1.2.11"
ZLIB_PKG="zlib-$ZLIB_VER"
ZLIB_ARCHIVE="$ZLIB_PKG.tar.gz"

PCRE_VER="8.44"
PCRE_PKG="pcre-$PCRE_VER"
PCRE_ARCHIVE="$PCRE_PKG.tar.gz"

LIBRESSL_VER="3.3.1"
LIBRESSL_PKG="libressl-$LIBRESSL_VER"
LIBRESSL_ARCHIVE="$LIBRESSL_PKG.tar.gz"

NGINX_VER="1.19.4"
NGINX_PKG="nginx-$NGINX_VER"
NGINX_ARCHIVE="$NGINX_PKG.tar.gz"

# fetch sources
wget http://zlib.net/${ZLIB_ARCHIVE}
wget ftp://ftp.pcre.org/pub/pcre/${PCRE_ARCHIVE}
wget https://ftp.openbsd.org/pub/OpenBSD/LibreSSL/${LIBRESSL_ARCHIVE}
wget https://nginx.org/download/${NGINX_ARCHIVE}

# fetch third-party nginx modules
git clone https://github.com/openresty/headers-more-nginx-module.git ngx_headers_more
cd ngx_headers_more
git submodule update --init
cd ..

git clone https://github.com/google/ngx_brotli.git ngx_brotli
cd ngx_brotli
git submodule update --init
cd ..

# building packages
tar xf $ZLIB_ARCHIVE
tar xf $PCRE_ARCHIVE
tar xf $LIBRESSL_ARCHIVE

tar xf $NGINX_ARCHIVE
cd $NGINX_PKG

./configure \
	--prefix=$NGINX_PREFIX \
	--sbin-path=$NGINX_PREFIX/sbin/nginx \
	--conf-path=$NGINX_PREFIX/conf/nginx.conf \
	--pid-path=$NGINX_PREFIX/logs/nginx.pid \
	--error-log-path=$NGINX_PREFIX/logs/error.log \
	--http-log-path=$NGINX_PREFIX/logs/access.log \
	--user=$NGINX_USER \
	--group=$NGINX_GROUP \
	\
	--with-openssl=../$LIBRESSL_PKG \
	--with-pcre=../$PCRE_PKG \
	--with-pcre-jit \
	--with-zlib=../$ZLIB_PKG \
	\
	--with-file-aio \
	--with-threads \
	--with-compat \
	\
	$NGINX_INCLUDED_MODULES \
	$NGINX_EXCLUDED_MODULES \
	$NGINX_CUSTOM_MODULES

make && make install

mv $NGINX_PREFIX/conf/nginx.conf $NGINX_PREFIX/conf/nginx.conf.bak
cp ../../conf/nginx.conf $NGINX_PREFIX/conf/nginx.conf

[ -d $NGINX_PREFIX/conf/snippets ] && rm -rf $NGINX_PREFIX/conf/snippets
mkdir $NGINX_PREFIX/conf/snippets
cp ../../conf/nginx-conf-snippets/* $NGINX_PREFIX/conf/snippets

[ -d $NGINX_PREFIX/sites-available ] && rm -rf $NGINX_PREFIX/sites-available
mkdir $NGINX_PREFIX/sites-available
cp ../../conf/website.conf $NGINX_PREFIX/sites-available

[ -d $NGINX_PREFIX/sites-enabled ] && rm -rf $NGINX_PREFIX/sites-enabled
mkdir $NGINX_PREFIX/sites-enabled
ln -s $NGINX_PREFIX/sites-available/website.conf $NGINX_PREFIX/sites-enabled/website.conf

cp ../../conf/dhparam.pem /etc/ssl/dhparam.pem
cd ..

