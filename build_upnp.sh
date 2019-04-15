#!/bin/sh

# run in yenten source directory
# ATTENTION: THIS WILL `rm -rf dep build` IN THE CURRENT DIRECTORY

build_usage() {
	echo "$0 [linux/win] [32/64] [version]" >&2
	exit 1
}

build_have() {
	[ -f "$1" ] || return 1
	[ "$( sha256sum -b "$1" | cut -d' ' -f1 )" = "$2" ] || return 1
	return 0 
}

build_fetch() {
	if ! build_have "$DEPS/$1" "$2"; then
		curl -Lo "$DEPS/$1" "$3" || return 1
		if ! build_have "$DEPS/$1" "$2"; then
			echo "ERROR: checksum mismatch for $1" >&2
			return 1
		fi
	fi
	return 0
}

build_posix() {
	_CMP="$( which "$CROSS-$1" )"
	if [ -z "$_CMP" ]; then
		echo "ERROR: $1 not found" >&2
		return 1
	fi
	if ! echo "$( readlink -f "$_CMP" )" | grep -q '.*-posix$'; then
		echo "ERROR: $1 is not set to posix (use 'update-alternatives --config $CROSS-$1)" >&2
		return 1
	fi
	return 0
}

build_x11() {
	[ "$OS" = linux ] || return 0
	_BASE="$( basename "$1" )"
	_NAME="$( echo "$_BASE" | sed 's/-[^-]*$//' )"
	[ -f "$DEPS/have.$_NAME" ] && return 0
	_FILE="$_BASE.tar.bz2"
	if echo "$1" | grep -q ^http; then
		_URL="$1.tar.bz2"
	else
		_URL="https://www.x.org/releases/X11R7.7/src/$1.tar.bz2"
	fi
	rm -f "$DEPS/root/lib/$_NAME.orig.a" "$DEPS/have.x11hack" || \
		return 1
	build_fetch "$_FILE" "$2" "$_URL" || return 1
	cd dep || return 1
	tar xaf "$DEPS/$_FILE" || return 1
	cd "$_BASE" || return 1
	if [ -f config.sub ]; then
		sed -i'' 's/.*-dicos\*)/-musl)os=-linux-gnu;;\n-dicos*)/' \
			config.sub || return 1
	fi
	shift 2
	LDFLAGS="-L$DEPS/root/lib -Wl,-rpath,$DEPS/root/$CROSS/lib \
		-Wl,--dynamic-linker=$DEPS/root/$CROSS/lib/libc.so" \
		CFLAGS="-I$DEPS/root/include -fPIC" ./configure --enable-static \
		--disable-shared --host=$CROSS --prefix="$DEPS/root" "$@" || \
		return 1
	$MAKE install || return 1
	touch "$DEPS/have.$_NAME" || return 1
	cd ../.. || exit 1
	return 0
}

build_exlib() {
	_HASH="$( echo "$1" | sha256sum | cut -d' ' -f1 )"
	for _OBJ in $( ar t "$1" ); do
		ar p "$1" "$_OBJ" > "$2/${_HASH}_$_OBJ" || return 1
	done
	return 0
}

[ $# -lt 3 ] && build_usage
[ ! "$1" = linux ] && [ ! "$1" = win ] && build_usage
[ ! "$2" = 32 ] && [ ! "$2" = 64 ] && build_usage
OS="$1"
BITS="$2"
VERSION="$3"

if [ "$OS" = linux ]; then
	if [ "$BITS" = 64 ]; then
		CROSS=x86_64-linux-musl
	else
		CROSS=i686-linux-musl
	fi
else
	if [ "$BITS" = 64 ]; then
		CROSS=x86_64-w64-mingw32
	else
		CROSS=i686-w64-mingw32
	fi
	build_posix gcc || exit 1
	build_posix g++ || exit 1
fi

COIN=yenten
MAKE="make -j$( nproc )"
SELF="$( readlink -f "$0" )"
BASE="$( dirname "$SELF" )"
DEPS="$HOME/.builddep/$OS.$BITS"
export PATH="$DEPS/root/bin:$PATH"
export PKG_CONFIG_PATH="$DEPS/root/lib/pkgconfig"
mkdir -p "$DEPS/root" || exit 1
rm -rf dep || exit 1
mkdir dep || exit 1

if [ "$OS" = linux ] && [ ! -f "$DEPS/have.musl" ]; then
	build_fetch musl-cross-make-0.9.7.tar.gz \
		876173e2411b5f50516723c63075655a9aac55ee3804f91adfb61f0a85af8f38 \
		https://github.com/richfelker/musl-cross-make/archive/v0.9.7.tar.gz || \
		exit 1
	cd dep || exit 1
	tar xzf "$DEPS/musl-cross-make-0.9.7.tar.gz" || exit 1
	cd musl-cross-make-0.9.7 || exit 1
	PKG_CONFIG_PATH='' TARGET=$CROSS $MAKE || exit 1
	sed -i'' 's/^OUTPUT =.*//' Makefile || exit 1
	OUTPUT="$DEPS/root" TARGET=$CROSS $MAKE install || exit 1
	touch "$DEPS/have.musl" || exit 1
	cd ../.. || exit 1
fi

if [ ! -f "$DEPS/have.db" ]; then
	build_fetch db-4.8.30.NC.tar.gz \
		12edc0df75bf9abd7f82f821795bcee50f42cb2e5f76a6a281b85732798364ef \
		http://download.oracle.com/berkeley-db/db-4.8.30.NC.tar.gz || \
		exit 1
	cd dep || exit 1
	tar xzf "$DEPS/db-4.8.30.NC.tar.gz" || exit 1
	cd db-4.8.30.NC/build_unix || exit 1
	if [ "$OS" = linux ]; then
		CFLAGS=-fPIC
		FLAGS=''
		sed -i'' 's/.*-dicos\*)/-musl);;\n-dicos*)/' \
			../dist/config.sub || exit 1
	else
		CFLAGS=''
		FLAGS=--enable-mingw
	fi
	CFLAGS="$CFLAGS" CXXFLAGS="$CFLAGS" \
		../dist/configure "--prefix=$DEPS/root" --enable-cxx \
		--host=$CROSS $FLAGS --disable-replication || exit 1
	$MAKE || exit 1
	$MAKE install_include install_lib || exit 1
	touch "$DEPS/have.db" || exit 1
	cd ../../.. || exit 1
fi

if [ ! -f "$DEPS/have.zlib" ]; then
	build_fetch zlib-1.2.11.tar.xz \
		4ff941449631ace0d4d203e3483be9dbc9da454084111f97ea0a2114e19bf066 \
		https://zlib.net/zlib-1.2.11.tar.xz || exit 1
	cd dep || exit 1
	tar xJf "$DEPS/zlib-1.2.11.tar.xz" || exit 1
	cd zlib-1.2.11 || exit 1
	if [ "$OS" = linux ]; then
		CROSS_PREFIX=''
		FLAGS=-fPIC
	else
		CROSS_PREFIX=$CROSS-
		FLAGS=''
	fi
	CFLAGS="$FLAGS -m$BITS" CXXFLAGS="$FLAGS -m$BITS" \
		CROSS_PREFIX=$CROSS_PREFIX ./configure --static \
		"--prefix=$DEPS/root" || exit 1
	$MAKE install || exit 1
	touch "$DEPS/have.zlib" || exit 1
	cd ../.. || exit 1
fi

if [ ! -f "$DEPS/have.libpng" ]; then
	build_fetch libpng-1.6.34.tar.xz \
		2f1e960d92ce3b3abd03d06dfec9637dfbd22febf107a536b44f7a47c60659f6 \
		ftp://ftp-osl.osuosl.org/pub/libpng/src/libpng16/libpng-1.6.34.tar.xz || \
		exit 1
	cd dep || exit 1
	tar xJf "$DEPS/libpng-1.6.34.tar.xz" || exit 1
	cd libpng-1.6.34 || exit 1
	FLAGS="$( [ "$OS" = linux ] && echo -fPIC )"
	CFLAGS="-I$DEPS/root/include $FLAGS" \
		CPPFLAGS="-I$DEPS/root/include $FLAGS" \
		LDFLAGS="-L$DEPS/root/lib" ./configure --enable-static \
		--disable-shared "--prefix=$DEPS/root" --host=$CROSS || exit 1
	$MAKE install || exit 1
	touch "$DEPS/have.libpng" || exit 1
	cd ../.. || exit 1
fi

if [ ! -f "$DEPS/have.boost" ]; then
	build_fetch boost_1_65_1.tar.gz \
		a13de2c8fbad635e6ba9c8f8714a0e6b4264b60a29b964b940a22554705b6b60 \
		https://downloads.sourceforge.net/project/boost/boost/1.65.1/boost_1_65_1.tar.gz || \
		exit 1
	cd dep || exit 1
	tar xzf "$DEPS/boost_1_65_1.tar.gz" || exit 1
	cd boost_1_65_1 || exit 1
	./bootstrap.sh --without-libraries=python "--prefix=$DEPS/root" || \
		exit 1
	if [ "$OS" = linux ]; then
		FLAGS="toolset=gcc address-model=$BITS"
	else
		tee tools/build/src/tools/mc.jam > /dev/null <<___
			import common ;
			import generators ;
			import feature : feature get-values ;
			import toolset : flags ;
			import type ;
			import rc ;
			feature.feature mc-compiler : $CROSS-windmc : propagated ;
			feature.set-default mc-compiler : $CROSS-windmc ;
			rule init ( )
			{
			}
			type.register MC : mc ;
			feature mc-input-encoding : ansi unicode : free ;
			feature mc-output-encoding : unicode ansi : free ;
			feature mc-set-customer-bit : no yes : free ;
			flags mc.compile MCFLAGS <mc-input-encoding>ansi : -a ;
			flags mc.compile MCFLAGS <mc-input-encoding>unicode : -u ;
			flags mc.compile MCFLAGS <mc-output-encoding>ansi : -A ;
			flags mc.compile MCFLAGS <mc-output-encoding>unicode : -U ;
			flags mc.compile MCFLAGS <mc-set-customer-bit>no : ;
			flags mc.compile MCFLAGS <mc-set-customer-bit>yes : -c ;
			generators.register-standard mc.compile.mc : MC : H RC : <mc-compiler>mc ;
			generators.register-standard mc.compile.$CROSS-windmc : MC : H RC : <mc-compiler>$CROSS-windmc ;
			actions compile.mc
			{
				mc \$(MCFLAGS) -h "\$(<[1]:DW)" -r "\$(<[2]:DW)" "\$(>:W)"
			}
			actions compile.$CROSS-windmc
			{
				windmc \$(MCFLAGS) -h "\$(<[1]:DW)" -r "\$(<[2]:DW)" "\$(>:W)"
			}
___
		[ $? = 0 ] || exit 1
		FLAGS="toolset=gcc-mingw address-model=$BITS architecture=x86 \
			binary-format=pe target-os=windows threadapi=win32 \
			mc-compiler=$CROSS-windmc"
	fi
	echo "using gcc : : $CROSS-g++ ;" | tee user-config.jam \
			> /dev/null || exit 1
	./b2 cxxflags=-fPIC cflags=-fPIC -j$( nproc ) \
		--user-config=user-config.jam $FLAGS release install || exit 1
	if [ "$OS" = linux ]; then
		find "$DEPS/root/lib" -name 'libboost_*.so*' -delete || exit 1
	fi
	touch "$DEPS/have.boost" || exit 1
	cd ../.. || exit 1
fi

if [ ! -f "$DEPS/have.openssl" ]; then
	build_fetch openssl-1.0.2p.tar.gz \
		50a98e07b1a89eb8f6a99477f262df71c6fa7bef77df4dc83025a2845c827d00 \
		https://www.openssl.org/source/openssl-1.0.2p.tar.gz || \
		exit 1
	cd dep || exit 1
	tar xzf "$DEPS/openssl-1.0.2p.tar.gz" || exit 1
	cd openssl-1.0.2p || exit 1
	if [ "$OS" = linux ]; then
		TARGET=linux-generic$BITS
		FLAGS=-fPIC
	else
		TARGET=mingw$( [ "$BITS" = 64 ] && echo 64 )
		FLAGS=''
	fi
	PREFIX=$CROSS-
	./Configure $TARGET no-shared no-dso "--prefix=$DEPS/root" $FLAGS \
		|| exit 1
	if [ "$OS" = win ]; then
		sed -i'' 's/-Wa,--noexecstack//' Makefile || exit 1
	fi
	$MAKE CC=${PREFIX}gcc RANLIB=${PREFIX}ranlib LD=${PREFIX}ld \
		MAKEDEPPROG=${PREFIX}gcc RC=${PREFIX}windres || exit 1
	make install || exit 1
	touch "$DEPS/have.openssl" || exit 1
	cd ../.. || exit 1
fi

if [ ! -f "$DEPS/have.libevent" ]; then
	build_fetch libevent-2.1.8-stable.tar.gz \
		965cc5a8bb46ce4199a47e9b2c9e1cae3b137e8356ffdad6d94d3b9069b71dc2 \
		https://github.com/libevent/libevent/releases/download/release-2.1.8-stable/libevent-2.1.8-stable.tar.gz || \
		exit 1
	cd dep || exit 1
	tar xzf "$DEPS/libevent-2.1.8-stable.tar.gz" || exit 1
	cd libevent-2.1.8-stable || exit 1
	CFLAGS="-I$DEPS/root/include" \
		LDFLAGS="-L$DEPS/root/lib" ./configure \
		"--prefix=$DEPS/root" --enable-static --disable-shared \
		--disable-samples --host=$CROSS || exit 1
	if [ "$OS" = win ]; then
		sed -i'' 's/^LIBS = .*/& -lcrypt32 -lgdi32 -luser32 -lws2_32/' \
			Makefile || exit 1
	fi
	$MAKE install || exit 1
	touch "$DEPS/have.libevent" || exit 1
	cd ../.. || exit 1
fi

if [ "$OS" = win ] && [ ! -f "$DEPS/have.qt-tools" ]; then
	build_fetch qt-everywhere-opensource-src-5.9.7.tar.xz \
		1c3852aa48b5a1310108382fb8f6185560cefc3802e81ecc099f4e62ee38516c \
		https://download.qt.io/archive/qt/5.9/5.9.7/single/qt-everywhere-opensource-src-5.9.7.tar.xz || \
		exit 1
	cd dep || exit 1
	tar xJf "$DEPS/qt-everywhere-opensource-src-5.9.7.tar.xz" || exit 1
	cd qt-everywhere-opensource-src-5.9.7 || exit 1
	./configure -confirm-license -release -opensource -nomake examples \
		-nomake tests -skip qtactiveqt -skip qtenginio \
		-skip qtlocation -skip qtmultimedia -skip qtserialport \
		-skip qtquick1 -skip qtquickcontrols -skip qtscript \
		-skip qtsensors -skip qtwebsockets -skip qtxmlpatterns \
		-skip qt3d -skip qtwebchannel -skip qtcanvas3d -skip qtwebview \
		-skip qtpurchasing -skip qtdocgallery -skip qtfeedback \
		-skip qtscript -skip qtsvg -skip qtdoc -skip qtqa \
		-prefix "$DEPS/root" -no-opengl -qt-zlib -qt-libjpeg \
		-qt-libpng -qt-freetype -qt-pcre -no-harfbuzz -qt-sqlite \
		-no-glib -qt-doubleconversion || exit 1
	$MAKE || exit 1
	$MAKE install || exit 1
	touch "$DEPS/have.qt-tools" || exit 1
	cd ../.. || exit 1
fi

if [ "$OS" = linux ] && [ ! -f "$DEPS/have.xml2" ]; then
	build_fetch libxml2-2.9.9.tar.gz \
		94fb70890143e3c6549f265cee93ec064c80a84c42ad0f23e85ee1fd6540a871 \
		ftp://xmlsoft.org/libxslt/libxml2-2.9.9.tar.gz || \
		exit 1
	cd dep || exit 1
	tar xzf "$DEPS/libxml2-2.9.9.tar.gz" || exit 1
	cd libxml2-2.9.9 || exit 1
	LDFLAGS="-Wl,--dynamic-linker=$DEPS/root/$CROSS/lib/libc.so" \
		./configure --without-python --prefix="$DEPS/root" \
		--host=$CROSS || exit 1
	$MAKE install || exit 1
	touch "$DEPS/have.xml2" || exit 1
	cd ../.. || exit 1
fi

if [ "$OS" = linux ] && [ ! -f "$DEPS/have.xslt" ]; then
	build_fetch libxslt-1.1.33.tar.gz \
		8e36605144409df979cab43d835002f63988f3dc94d5d3537c12796db90e38c8 \
		ftp://xmlsoft.org/libxslt/libxslt-1.1.33.tar.gz || \
		exit 1
	cd dep || exit 1
	tar xzf "$DEPS/libxslt-1.1.33.tar.gz" || exit 1
	cd libxslt-1.1.33 || exit 1
	LDFLAGS="-Wl,--dynamic-linker=$DEPS/root/$CROSS/lib/libc.so" \
		./configure --prefix="$DEPS/root" --host=$CROSS || exit 1
	$MAKE install-exec || exit 1
	touch "$DEPS/have.xslt" || exit 1
	cd ../.. || exit 1
fi

build_x11 proto/xproto-7.0.23 \
	ade04a0949ebe4e3ef34bb2183b1ae8e08f6f9c7571729c9db38212742ac939e || \
	exit 1
build_x11 proto/kbproto-1.0.6 \
	037cac0aeb80c4fccf44bf736d791fccb2ff7fd34c558ef8f03ac60b61085479 || \
	exit 1
build_x11 proto/inputproto-2.2 \
	de7516ab25c299740da46c0f1af02f1831c5aa93b7283f512c0f35edaac2bcb0 || \
	exit 1
build_x11 lib/xtrans-1.2.7 \
	7f811191ba70a34a9994d165ea11a239e52c527f039b6e7f5011588f075fe1a6 || \
	exit 1
build_x11 lib/libXau-1.0.7 \
	7153ba503e2362d552612d9dc2e7d7ad3106d5055e310a26ecf28addf471a489 || \
	exit 1
build_x11 https://xcb.freedesktop.org/dist/xcb-proto-1.13 \
	7b98721e669be80284e9bbfeab02d2d0d54cd11172b72271e47a2fe875e2bde1 || \
	exit 1
build_x11 https://xcb.freedesktop.org/dist/libxcb-1.13 \
	188c8752193c50ff2dbe89db4554c63df2e26a2e47b0fa415a70918b5b851daa \
	--enable-xinput --enable-xkb || exit 1
build_x11 lib/libX11-1.5.0 \
	c382efd7e92bfc3cef39a4b7f1ecf2744ba4414a705e3bc1e697f75502bd4d86 || \
	exit 1
build_x11 proto/xextproto-7.2.1 \
	7c53b105407ef3b2eb180a361bd672c1814524a600166a0a7dbbe76b97556d1a || \
	exit 1
build_x11 proto/fixesproto-5.0 \
	ba2f3f31246bdd3f2a0acf8bd3b09ba99cab965c7fb2c2c92b7dc72870e424ce || \
	exit 1
build_x11 proto/renderproto-0.11.1 \
	06735a5b92b20759204e4751ecd6064a2ad8a6246bb65b3078b862a00def2537 || \
	exit 1
build_x11 lib/libXext-1.3.1 \
	56229c617eb7bfd6dec40d2805bc4dfb883dfe80f130d99b9a2beb632165e859 || \
	exit 1
build_x11 lib/libXfixes-5.0 \
	537a2446129242737a35db40081be4bbcc126e56c03bf5f2b142b10a79cda2e3 || \
	exit 1
build_x11 lib/libXi-1.6.1 \
	f2e3627d7292ec5eff488ab58867fba14a62f06e72a8d3337ab6222c09873109 || \
	exit 1
build_x11 lib/libXrender-0.9.7 \
	f9b46b93c9bc15d5745d193835ac9ba2a2b411878fad60c504bbb8f98492bbe6 || \
	exit 1

if [ "$OS" = linux ] && [ ! -f "$DEPS/have.x11hack" ]; then
	if [ ! -f "$DEPS/root/lib/libX11.orig.a" ]; then
		mv "$DEPS/root/lib/libX11.a" "$DEPS/root/lib/libX11.orig.a" || \
			exit 1
	fi
	if [ ! -f "$DEPS/root/lib/libxcb.orig.a" ]; then
		mv "$DEPS/root/lib/libxcb.a" "$DEPS/root/lib/libxcb.orig.a" || \
			exit 1
	fi
	rm -f "$DEPS/root/lib/libX11.a" || exit 1
	mkdir dep/x11hack || exit 1
	for LIB in $( find "$DEPS/root/lib" -name 'libX*.a' ); do
		build_exlib "$LIB" dep/x11hack || exit 1
	done
	build_exlib "$DEPS/root/lib/libxcb.orig.a" dep/x11hack || exit 1
	ar rcs "$DEPS/root/lib/libX11.a" dep/x11hack/*.o || exit 1
	ranlib "$DEPS/root/lib/libX11.a" || exit 1
	cp "$DEPS/root/lib/libX11.a" "$DEPS/root/lib/libxcb.a" || exit 1
	touch "$DEPS/have.x11hack" || exit 1
fi

if [ "$OS" = linux ] && [ ! -f "$DEPS/have.xkbcommon" ]; then
	build_fetch libxkbcommon-0.8.4.tar.xz \
		60ddcff932b7fd352752d51a5c4f04f3d0403230a584df9a2e0d5ed87c486c8b \
		https://xkbcommon.org/download/libxkbcommon-0.8.4.tar.xz || \
		exit 1
	cd dep || exit 1
	tar xJf "$DEPS/libxkbcommon-0.8.4.tar.xz" || exit 1
	cd libxkbcommon-0.8.4 || exit 1
	CFLAGS="-I$DEPS/root/include -fPIC" LDFLAGS="-L$DEPS/root/lib" \
		./configure --prefix="$DEPS/root" --host=$CROSS \
		--enable-static --disable-shared || exit 1
	$MAKE install || exit 1
	touch "$DEPS/have.xkbcommon" || exit 1
	cd ../.. || exit 1
fi

if [ ! -f "$DEPS/have.qt-libs" ]; then
	build_fetch qt-everywhere-opensource-src-5.9.7.tar.xz \
		1c3852aa48b5a1310108382fb8f6185560cefc3802e81ecc099f4e62ee38516c \
		https://download.qt.io/archive/qt/5.9/5.9.7/single/qt-everywhere-opensource-src-5.9.7.tar.xz || \
		exit 1
	cd dep || exit 1
	rm -rf qt-everywhere-opensource-src-5.9.7 || exit 1
	tar xJf "$DEPS/qt-everywhere-opensource-src-5.9.7.tar.xz" || exit 1
	cd qt-everywhere-opensource-src-5.9.7 || exit 1
	if [ "$OS" = linux ]; then
		OPENSSL_LIBS=''
		CROSS_COMPILE=''
		FLAGS="-platform linux-g++-$BITS -xplatform linux-g++-$BITS \
			-qt-xcb"
		sed -i'' \
			"s/QMAKE_\(COMPILER\|CC\|CXX\) *= \(.*\)/QMAKE_\1 = $CROSS-\2/" \
			qtbase/mkspecs/common/g++-base.conf || exit 1
		echo "QMAKE_LFLAGS += \
			-Wl,--dynamic-linker=$DEPS/root/$CROSS/lib/libc.so \
			-Wl,-rpath,./lib -Wl,-rpath,$DEPS/root/$CROSS/lib \
			-Wl,-rpath-link,$DEPS/root/lib" | tee -a \
			qtbase/mkspecs/common/gcc-base-unix.conf > /dev/null || \
			exit 1
	else
		OPENSSL_LIBS='-lcrypt32 -lws2_32 -lgdi32 -luser32'
		CROSS_COMPILE=$CROSS-
		FLAGS="-platform linux-g++-64 -xplatform win32-g++ \
			-skip qttools -nomake tools"
	fi
	./configure -confirm-license -release -opensource -nomake examples \
		-nomake tests -skip qtactiveqt -skip qtenginio -skip qtlocation \
		-skip qtmultimedia -skip qtserialport -skip qtquick1 \
		-skip qtquickcontrols -skip qtscript -skip qtsensors \
		-skip qtwebsockets -skip qtxmlpatterns -skip qt3d \
		-skip qtwebchannel -skip qtcanvas3d -skip qtwebview \
		-skip qtpurchasing -skip qtdocgallery -skip qtfeedback \
		-skip qtscript -skip qtsvg -skip qtdoc -skip qtqa \
		$FLAGS -prefix "$DEPS/root" -hostprefix "$DEPS/root" -no-opengl \
		-sse2 -openssl-linked -qt-zlib -qt-libjpeg -qt-libpng \
		-qt-freetype -qt-pcre -no-harfbuzz -qt-sqlite -no-glib \
		-qt-doubleconversion -no-sse3 -no-ssse3 -no-sse4.1 -no-sse4.2 \
		-no-avx -no-avx2 -no-avx512 -no-cups -no-journald -no-syslog \
		-no-sctp -no-libproxy -no-fontconfig -no-directfb -no-icu \
		-no-eglfs -no-gbm -no-kms -no-linuxfb -no-mirclient -no-iconv \
		-no-gif -sql-sqlite -device-option CROSS_COMPILE=$CROSS_COMPILE \
		-openssl -openssl-linked -system-xkbcommon \
		OPENSSL_LIBS="-lssl -lcrypto $OPENSSL_LIBS" -L "$DEPS/root/lib" \
		-I "$DEPS/root/include" || exit 1
	$MAKE || exit 1
	$MAKE install || exit 1
	touch "$DEPS/have.qt-libs" || exit 1
	cd ../.. || exit 1
fi

if [ ! -f "$DEPS/have.protobuf" ]; then
	build_fetch protobuf-cpp-3.6.1.tar.gz \
		b3732e471a9bb7950f090fd0457ebd2536a9ba0891b7f3785919c654fe2a2529 \
		https://github.com/protocolbuffers/protobuf/releases/download/v3.6.1/protobuf-cpp-3.6.1.tar.gz || \
		exit 1
	cd dep || exit 1
	tar xzf "$DEPS/protobuf-cpp-3.6.1.tar.gz" || exit 1
	cd protobuf-3.6.1 || exit 1
	if [ "$OS" = linux ]; then
		LDFLAGS="-Wl,--dynamic-linker=$DEPS/root/$CROSS/lib/libc.so"
		FLAGS=--with-pic
	else
		LDFLAGS=''
		FLAGS=''
	fi
	LDFLAGS="$LDFLAGS" ./configure --enable-static --disable-shared \
		$FLAGS "--prefix=$DEPS/root" --host=$CROSS || exit 1
	$MAKE install || exit 1
	touch "$DEPS/have.protobuf" || exit 1
	cd ../.. || exit 1
fi

if [ "$OS" = win ] && [ ! -f "$DEPS/have.protoc" ]; then
	build_fetch protoc-3.6.1-linux-x86_64.zip \
		6003de742ea3fcf703cfec1cd4a3380fd143081a2eb0e559065563496af27807 \
		https://github.com/protocolbuffers/protobuf/releases/download/v3.6.1/protoc-3.6.1-linux-x86_64.zip || \
		exit 1
	cd dep || exit 1
	mkdir protc || exit 1
	cd protc || exit 1
	unzip "$DEPS/protoc-3.6.1-linux-x86_64.zip" || exit 1
	cp bin/protoc "$DEPS/root/bin" || exit 1
	touch "$DEPS/have.protoc" || exit 1
	cd ../.. || exit 1
fi

if [ "$OS" = linux ] && [ ! -f "$DEPS/have.klokan" ]; then
	build_fetch KlokanNotoSans-1.0.zip \
		180142466c7ec2c92adf9b840ace7f9e768c02aef7b064b675176f3dfb171487 \
		https://github.com/klokantech/klokantech-gl-fonts/releases/download/v1.0.0/ttf.zip || \
		exit 1
	mkdir -p "$DEPS/root/share/font" || exit 1
	unzip "$DEPS/KlokanNotoSans-1.0.zip" -d \
		"$DEPS/root/share/font" || exit 1
	touch "$DEPS/have.klokan" || exit 1
fi

if [ ! -f "$DEPS/have.miniupnp" ]; then
	build_fetch miniupnpc_2_1.tar.gz \
		19c5b6cf8f3fc31d5e641c797b36ecca585909c7f3685a5c1a64325340537c94 \
		https://github.com/miniupnp/miniupnp/archive/miniupnpc_2_1.tar.gz || \
		exit 1
	cd dep || exit 1
	tar xzf "$DEPS/miniupnpc_2_1.tar.gz" || exit 1
	cd miniupnp-miniupnpc_2_1/miniupnpc || exit 1
	CC=$CROSS-gcc AR=$CROSS-ar CFLAGS=-DMINIUPNP_STATICLIB $MAKE \
		libminiupnpc.a || exit 1
	cp libminiupnpc.a "$DEPS/root/lib" || exit 1
	mkdir -p "$DEPS/root/include/miniupnpc" || exit 1
	cp miniupnpc.h miniwget.h upnpcommands.h igd_desc_parse.h \
		upnpreplyparse.h upnperrors.h miniupnpctypes.h \
		portlistingparse.h upnpdev.h miniupnpc_declspec.h \
		"$DEPS/root/include/miniupnpc" || exit 1
	touch "$DEPS/have.miniupnp" || exit 1
	cd ../../.. || exit 1
fi

if [ ! -f "$DEPS/have.libqrencode" ]; then
	build_fetch libqrencode-4.0.2.tar.gz \
		43091fea4752101f0fe61a957310ead10a7cb4b81e170ce61e5baa73a6291ac2 \
		https://github.com/fukuchi/libqrencode/archive/v4.0.2.tar.gz || \
		exit 1
	cd dep || exit 1
	tar xzf "$DEPS/libqrencode-4.0.2.tar.gz" || exit 1
	cd libqrencode-4.0.2 || exit 1
	if [ "$OS" = win ]; then
		SYSTEM=Windows
	else
		SYSTEM=Linux
	fi
	cmake -DCMAKE_INSTALL_PREFIX="$DEPS/root" \
		-DCMAKE_TRY_COMPILE_TARGET_TYPE=STATIC_LIBRARY -DWITH_TOOLS=NO \
		-DCMAKE_C_COMPILER=$CROSS-gcc -DCMAKE_SYSTEM_NAME=$SYSTEM \
		-DCMAKE_CXX_COMPILER=$CROSS-g++ -DCMAKE_C_FLAGS=-fPIC . || \
		exit 1
	$MAKE || exit 1
	$MAKE install || exit 1
	touch "$DEPS/have.libqrencode" || exit 1
	cd ../.. || exit 1
fi

if [ ! -f configure ]; then
	./autogen.sh || exit 1
fi
if [ "$OS" = linux ]; then
	CFLAGS=''
	LDFLAGS="-Wl,-rpath-link,$DEPS/root/lib -Wl,-rpath,./lib \
		-Wl,--dynamic-linker=lib/libc.so"
else
	CFLAGS=-Wa,-mbig-obj
	LDFLAGS=''
fi
LDFLAGS="-L$DEPS/root/lib $LDFLAGS" \
	CXXFLAGS="-I$DEPS/root/include $CFLAGS" ./configure \
	"--prefix=$PWD/build" "--with-boost=$DEPS/root" --with-gui=qt5 \
	"--with-qt-libdir=$DEPS/root/lib" \
	"--with-qt-incdir=$DEPS/root/include" \
	"--with-qt-bindir=$DEPS/root/bin" \
	"--with-protoc-bindir=$DEPS/root/bin" --disable-tests \
	--disable-dependency-tracking --enable-upnp-default \
	--host=$CROSS || exit 1
if [ "$OS" = linux ]; then
	sed -i'' 's/-fPIE/-fPIC/g' src/qt/Makefile || exit 1
fi
rm -rf build || exit 1
make clean
$MAKE V=1 install || exit 1

find build/bin -maxdepth 1 -type f ! -name "${COIN}d*" \
	! -name "$COIN-cli*" ! -name "$COIN-tx*" ! -name "$COIN-qt*" \
	-delete || exit 1
if [ "$OS" = linux ]; then
	cd build || exit 1
	mkdir -p lib/plugins/platforms || exit 1
	for SO in Core Gui Network Widgets DBus XcbQpa; do
		cp "$DEPS/root/lib/libQt5$SO.so.5" lib || exit 1
	done
	for SO in c.so stdc++.so.6 gcc_s.so.1; do
		cp "$DEPS/root/$CROSS/lib/lib$SO" lib || exit
	done
	cp "$DEPS/root/plugins/platforms/libqxcb.so" \
		lib/plugins/platforms || exit 1
	find . -type f -exec strip -s {} \; || exit 1
	find lib -type f ! -name "libc.so" -exec chmod -x {} \; || exit 1
	mkdir font || exit 1
	cp "$DEPS/root/share/font/KlokanTechNotoSans-Regular.ttf" font || \
		exit 1
	cp "$DEPS/root/share/font/KlokanTechNotoSansCJK-Regular.otf" font || \
		exit 1
	tee ${COIN}d > /dev/null <<___
#!/bin/sh
cd "\$( dirname "\$( readlink -f "\$0" )" )"
export QT_QPA_FONTDIR="\$PWD/font"
export QT_QPA_PLATFORM_PLUGIN_PATH="\$PWD/lib/plugins"
exec "bin/\$( basename "\$0" )" "\$@"
___
	[ $? = 0 ] || exit 1
	chmod +x ${COIN}d || exit 1
	ln -s ${COIN}d $COIN-cli || exit 1
	ln -s ${COIN}d $COIN-qt || exit 1
	rm -f "$BASE/${COIN}_${VERSION}_$OS$BITS.tar.xz" || exit 1
	tar cvJf "$BASE/${COIN}_${VERSION}_$OS$BITS.tar.xz" * || exit 1
else
	cd build/bin || exit 1
	for DLL in Core Gui Network Widgets; do
		cp "$DEPS/root/bin/Qt5$DLL.dll" . || exit 1
	done
	mkdir -p plugins/platforms || exit 1
	cp "$DEPS/root/plugins/platforms/qwindows.dll" plugins/platforms || \
		exit 1
	GCCVER="$( $CROSS-g++ --version | head -n1 | sed \
		's/.*) \([0-9\.]*\) .*/\1/;s/\.0$//g' )"
	if [ "$BITS" = 64 ]; then
		cp "/usr/lib/gcc/$CROSS/$GCCVER-posix/libgcc_s_seh-1.dll" . || \
			exit 1
	else
		cp "/usr/lib/gcc/$CROSS/$GCCVER-posix/libgcc_s_sjlj-1.dll" . || \
			exit 1
	fi
	cp "/usr/lib/gcc/$CROSS/$GCCVER-posix/libstdc++-6.dll" \
		"/usr/$CROSS/lib/libwinpthread-1.dll" . || exit 1
	find . -type f -exec chmod -x {} \; || exit 1
	find . -type f -exec strip -s {} \; || exit 1
	echo '[Paths]' | tee qt.conf > /dev/null || exit 1
	echo 'Plugins = ./plugins' | tee -a qt.conf > /dev/null || exit 1
	rm -f "$BASE/${COIN}_${VERSION}_$OS$BITS.zip" || exit 1
	zip -r9 "$BASE/${COIN}_${VERSION}_$OS$BITS.zip" * || exit 1
fi