#! /bin/bash

set -e

#Kernel building script

# Function to show an informational message
msg() {
	echo
    echo -e "\e[1;32m$*\e[0m"
    echo
}

err() {
    echo -e "\e[1;41m$*\e[0m"
    exit 1
}

cdir() {
	cd "$1" 2>/dev/null || \
		err "The directory $1 doesn't exists !"
}
rm -rf $(pwd)/AnyKernel3
rm -rf $(pwd)/clang-llvm
rm -rf $(pwd)/scripts/ufdt/libufdt
##------------------------------------------------------##
##----------Basic Informations, COMPULSORY--------------##

# The defult directory where the kernel should be placed
KERNEL_DIR="$(pwd)"
BASEDIR="$(basename "$KERNEL_DIR")"

# The name of the Kernel, to name the ZIP
ZIPNAME="RyukKernel"

# Build Author
# Take care, it should be a universal and most probably, case-sensitive
AUTHOR="Geo"

# Architecture
ARCH=arm64

# The name of the device for which the kernel is built
MODEL="Realme 5 / 5i / 5s"

# The codename of the device
DEVICE="r5x"

# The defconfig which should be used. Get it from config.gz from
# your device or check source
DEFCONFIG=vendor/RMX1911_defconfig

# Build modules. 0 = NO | 1 = YES
MODULES=0

# Specify compiler. 
# 'clang' or 'gcc'
COMPILER=clang

# Clean source prior building. 1 is NO(default) | 0 is YES
INCREMENTAL=1

# Generate a full DEFCONFIG prior building. 1 is YES | 0 is NO(default)
DEF_REG=0

# Files/artifacts
FILES=Image.gz-dtb

# Build dtbo.img (select this only if your source has support to building dtbo.img)
# 1 is YES | 0 is NO(default)
BUILD_DTBO=1

# Silence the compilation
# 1 is YES(default) | 0 is NO
SILENCE=0

# Debug purpose. Send logs on every successfull builds
# 1 is YES | 0 is NO(default)
LOG_DEBUG=0

#Check Kernel Version
KERVER=$(make kernelversion)

# Set Date 
DATE=$(TZ=GMT-8 date +"%Y%m%d-%H%M")

#Now Its time for other stuffs like cloning, exporting, etc

 clone() {
	echo " "
	if [ $COMPILER = "gcc" ]
	then
		msg "|| Cloning GCC 12.0.0 baremetal ||"
	        wget -O 64.zip https://github.com/mvaisakh/gcc-arm64/archive/1a4410a4cf49c78ab83197fdad1d2621760bdc73.zip;unzip 64.zip;mv gcc-arm64-1a4410a4cf49c78ab83197fdad1d2621760bdc73 gcc64
		wget -O 32.zip https://github.com/mvaisakh/gcc-arm/archive/c8b46a6ab60d998b5efa1d5fb6aa34af35a95bad.zip;unzip 32.zip;mv gcc-arm-c8b46a6ab60d998b5efa1d5fb6aa34af35a95bad gcc32
		GCC64_DIR=$KERNEL_DIR/gcc64
		GCC32_DIR=$KERNEL_DIR/gcc32
	fi
	
	if [ $COMPILER = "clang" ]
	then
		msg "|| Cloning Clang-13 ||"
		git clone --depth=1 https://github.com/kdrag0n/proton-clang.git clang-llvm
		# Toolchain Directory defaults to clang-llvm
		TC_DIR=$KERNEL_DIR/clang-llvm
	fi

	msg "|| Cloning Anykernel ||"
	git clone --depth 1 --no-single-branch https://github.com/cyberknight777/AnyKernel3.git -b floral
	msg "|| Cloning libufdt ||"
	git clone https://android.googlesource.com/platform/system/libufdt "$KERNEL_DIR"/scripts/ufdt/libufdt
}

##------------------------------------------------------##

exports() {
	KBUILD_BUILD_USER=$AUTHOR
	export ARCH=arm64
        export LC_ALL=C && export USE_CCACHE=1
        export KBUILD_BUILD_HOST=AverelleKernel
        export KBUILD_BUILD_USER="Geo"

	if [ $COMPILER = "clang" ]
	then
		KBUILD_COMPILER_STRING=$("$TC_DIR"/bin/clang --version | head -n 1 | perl -pe 's/\(http.*?\)//gs' | sed -e 's/  */ /g' -e 's/[[:space:]]*$//')
		PATH=$TC_DIR/bin/:$PATH
	elif [ $COMPILER = "gcc" ]
	then
		KBUILD_COMPILER_STRING=$("$GCC64_DIR"/bin/aarch64-elf-gcc --version | head -n 1)
		PATH=$GCC64_DIR/bin/:$GCC32_DIR/bin/:/usr/bin:$PATH
	fi
}

##----------------------------------------------------------##

build_kernel() {
	make clean && make mrproper
	make O=out $DEFCONFIG
	
	BUILD_START=$(date +"%s")
	
	if [ $COMPILER = "clang" ]
	then
	
	make -j$(nproc --all) O=out \
	                      ARCH=arm64 \
	                      CROSS_COMPILE=aarch64-linux-gnu- \
			      CROSS_COMPILE_ARM32=arm-linux-gnueabi- \
			      CC=clang \
			      AR=llvm-ar \
			      OBJDUMP=llvm-objdump \
			      STRIP=llvm-strip
		
	elif [ $COMPILER = "gcc" ]
	then
		MAKE+=(
			CROSS_COMPILE_ARM32=arm-eabi- \
			CROSS_COMPILE=aarch64-elf-
			LD=aarch64-elf-ld
		)
	fi

		BUILD_END=$(date +"%s")
		DIFF=$((BUILD_END - BUILD_START))

		if [ -f "$KERNEL_DIR"/out/arch/arm64/boot/$FILES ]
		then
			msg "|| Kernel successfully compiled ||"
				make -j"$PROCS" O=out \
				     "${MAKE[@]}" 2>&1 dtbs dtbo.img | tee dtbo.log
				find "$KERNEL_DIR"/out/arch/arm64/boot/dts/google -name '*.dtb' -exec cat {} + > "$KERNEL_DIR"/out/arch/arm64/boot/dtb
			fi
				gen_zip
	
}

##--------------------------------------------------------------##

gen_zip() {
	msg "|| Zipping into a flashable zip ||"
	mv "$KERNEL_DIR"/out/arch/arm64/boot/$FILES AnyKernel3/$FILES
	if [ $BUILD_DTBO = 1 ]
	then
	    mv "$KERNEL_DIR"/out/arch/arm64/boot/dtbo.img AnyKernel3/dtbo.img
	    mv "$KERNEL_DIR"/out/arch/arm64/boot/dtb AnyKernel3/dtb
	fi
	cdir AnyKernel3
	zip -r $ZIPNAME-$DEVICE-"$DATE" . -x ".git*" -x "README.md" -x "*.zip"
	if [ $MODULES = "1" ]
	then
	    cdir ../Mod
	    rm -rf system/lib/modules/placeholder
	    zip -r $ZIPNAME-$DEVICE-modules-"$DATE" . -x ".git*" -x "LICENSE.md" -x "*.zip"
	    MOD_NAME="$ZIPNAME-$DEVICE-modules-$DATE"
	    cdir ../AnyKernel3
	fi

	## Prepare a final zip variable
	ZIP_FINAL="$ZIPNAME-$DEVICE-$DATE"

	cd ..
}

clone
exports
build_kernel

##----------------*****-----------------------------##
