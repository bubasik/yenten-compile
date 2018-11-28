# yenten-compile

```
apt-get update
apt-get install build-essential mingw-w64 binutils-mingw-w64 python zip unzip autoconf dos2unix
git clone https://github.com/yentencoin/yenten.git
cd yenten
wget -O build.sh https://raw.githubusercontent.com/bubasik/yenten-compile/master/build.sh
dos2unix build.sh
chmod +x build.sh
update-alternatives --config i686-w64-mingw32-gcc
update-alternatives --config i686-w64-mingw32-g++
update-alternatives --config x86_64-w64-mingw32-gcc
update-alternatives --config x86_64-w64-mingw32-g++
./build.sh win 32 test
```

Big thanks to POOPMAN!!!
