# Makefile for RISC-V toolchain; run 'make help' for usage.

RISCV    ?= $(PWD)/install
DEST     := $(abspath $(RISCV))
PATH     := $(DEST)/bin:$(PATH)

NR_CORES := $(shell nproc)

# default configure flags
fesvr-co              = --prefix=$(RISCV) --target=riscv64-unknown-linux-gnu
isa-sim-co            = --prefix=$(RISCV) --with-fesvr=$(DEST)
pk-co                 = --prefix=$(RISCV) --host=riscv64-unknown-linux-gnu CC=riscv64-unknown-linux-gnu-gcc OBJDUMP=riscv64-unknown-linux-gnu-objdump
tests-co              = --prefix=$(RISCV)/target
openocd-co            = --prefix=$(RISCV) --enable-remote-bitbang --enable-jtag_vpi --disable-werror

gnu-toolchain-co-fast = --prefix=$(RISCV) #--disable-gdb# no multilib for fast
gnu-toolchain-co      = --prefix=$(RISCV) # no multilib for fast

## gnu-toolchain-co-fast = --prefix=$(RISCV) --with-arch=rv64imac --disable-gdb # --with-abi=lp64 --disable-gdb# no multilib for fast
## gnu-toolchain-co      = --prefix=$(RISCV) --with-arch=rv64imac #--with-abi=lp64 # no multilib for fast

#ifdef SLOW
#gnu-toolchain-co      = --prefix=$(RISCV) --enable-multilib
#endif

# default make flags
fesvr-mk                = -j$(NR_CORES)
isa-sim-mk              = -j$(NR_CORES)
gnu-toolchain-libc-mk   = linux -j$(NR_CORES)
gnu-toolchain-newlib-mk = -j$(NR_CORES)
pk-mk                   = -j$(NR_CORES)
tests-mk                = -j$(NR_CORES)
openocd-mk              = -j$(NR_CORES)

# linux image
buildroot_defconfig = configs/buildroot_defconfig
linux_defconfig     = configs/linux_defconfig
busybox_defconfig   = configs/busybox.config
buildroot = buildroot

#rootfs
ROOTFS_FILES = $(shell find rootfs/ -type f)
#ROOTFS_FILES = rootfs/x.elf rootfs/gdb

SDCARDPARTITION ?= /dev/disk/by-id/usb-Generic-_SD_MMC_20120501030900000-0:0-part1

.PHONY: all
all: $(RISCV)/bin/riscv64-unknown-linux-gnu-gcc $(RISCV)/bin/riscv64-unknown-elf-gcc fesvr isa-sim pk


install-dir = $(RISCV)
$(install-dir):
	mkdir -p $@

$(RISCV)/bin/riscv64-unknown-elf-gcc: riscv-gnu-toolchain/build/Makefile
	make -C riscv-gnu-toolchain/build $(gnu-toolchain-newlib-mk)

$(RISCV)/bin/riscv64-unknown-linux-gnu-gcc: riscv-gnu-toolchain/build/Makefile
	make -C riscv-gnu-toolchain/build $(gnu-toolchain-libc-mk)

riscv-gnu-toolchain/build/Makefile: $(install-dir)
	mkdir -p riscv-gnu-toolchain/build
	#cd riscv-gnu-toolchain/riscv-binutils && patch -f -s -p1 < ../../patches/gcc_binutils.patch || true
	cd riscv-gnu-toolchain/build && ../configure $(gnu-toolchain-co)

riscv-fesvr/build/Makefile: $(RISCV)/bin/riscv64-unknown-linux-gnu-gcc
	mkdir -p $(dir $@)
	cd $(dir $@) && ../configure $(fesvr-co)

fesvr: riscv-fesvr/build/Makefile $(install-dir)
	make -C $(dir $<) $(fesvr-mk)
	make -C $(dir $<) install

riscv-isa-sim/build/Makefile: $(RISCV)/bin/riscv64-unknown-linux-gnu-gcc fesvr
	mkdir -p $(dir $@)
	cd $(dir $@) && ../configure $(isa-sim-co)

isa-sim: riscv-isa-sim/build/Makefile $(install-dir) fesvr
	make -C $(dir $<)  $(isa-sim-mk)
	make -C $(dir $<)  install

riscv-openocd/configure:
	cd riscv-openocd && autoreconf -i

riscv-openocd/build: riscv-openocd/configure
	mkdir -p $@
	cd $@ && ../configure $(openocd-co)

openocd: riscv-openocd/build $(install-dir)
	make -C $< $(openocd-mk)
	make -C $< install

tests: $(install-dir) $(RISCV)/bin/riscv64-unknown-elf-gcc
	mkdir -p riscv-tests/build
	cd riscv-tests/build && autoconf && ../configure $(tests-co)
	make -C riscv-tests/build $(tests-mk)
	make -C riscv-tests/build install


riscv-pk/build/Makefile:
	mkdir -p riscv-pk/build
	cd riscv-pk/build && ../configure $(pk-co)

.PHONY: pk
pk: riscv-pk/build/Makefile $(install-dir) $(RISCV)/bin/riscv64-unknown-linux-gnu-gcc
	make -C $(dir $<) $(pk-mk)
	make -C $(dir $<) install

# benchmark for the cache subsystem
.PHONY: cachetest
cachetest: ./rootfs/cachetest.elf

rootfs/cachetest.elf:
	cd ./cachetest/ && $(RISCV)/bin/riscv64-unknown-linux-gnu-gcc cachetest.c -o cachetest.elf
	cp ./cachetest/cachetest.elf rootfs/

# cool command-line tetris
rootfs/tetris:
	cd ./vitetris/ && make clean && ./configure CC=riscv64-unknown-linux-gnu-gcc && make
	cp ./vitetris/tetris $@

$(buildroot)/.config: $(buildroot_defconfig) $(linux_defconfig) $(busybox_defconfig)
	make -C $(buildroot) defconfig BR2_DEFCONFIG=../$(buildroot_defconfig)

vmlinux: $(buildroot)/.config $(RISCV)/bin/riscv64-unknown-elf-gcc $(RISCV)/bin/riscv64-unknown-linux-gnu-gcc $(ROOTFS_FILES)
	make -C $(buildroot)
	mkdir -p build
	cp $(buildroot)/output/images/vmlinux build/vmlinux
	cp build/vmlinux vmlinux

build/Makefile: $(RISCV)/bin/riscv64-unknown-linux-gnu-gcc
	mkdir -p build
	cd build && ../riscv-pk/configure --host=riscv64-unknown-elf CC=riscv64-unknown-linux-gnu-gcc OBJDUMP=riscv64-unknown-linux-gnu-objdump --with-payload=vmlinux --enable-logo --with-logo=../configs/logo.txt

bbl: vmlinux build/Makefile
	make -C build
	cp build/bbl bbl

bbl_binary: bbl
	riscv64-unknown-elf-objcopy -O binary bbl bbl_binary

bbl.bin: bbl
	riscv64-unknown-elf-objcopy -S -O binary --change-addresses -0x80000000 $< $@

flashtosdcard:
	test $$(sudo blockdev --getsize64 "$(SDCARDPARTITION)") -ge $$(stat --printf="%s" bbl.bin)
	sudo dd if=bbl.bin of="$(SDCARDPARTITION)" status=progress oflag=sync bs=1M
	sync

.PHONY: clean
clean:
	rm -rf vmlinux bbl riscv-pk/build/vmlinux riscv-pk/build/bbl cachetest/*.elf rootfs/tetris
	make -C $(buildroot) distclean

.PHONY: clean-all
clean-all: clean
	rm -rf riscv-fesvr/build riscv-isa-sim/build riscv-gnu-toolchain/build riscv-tests/build riscv-pk/build

.PHONY: help
help:
	@echo "usage: $(MAKE) [RISCV='<install/here>'] [tool/img] ..."
	@echo ""
	@echo "install [tool] to \$$RISCV with compiler <flag>'s"
	@echo "    where tool can be any one of:"
	@echo "        fesvr isa-sim gnu-toolchain tests pk"
	@echo ""
	@echo "build linux images for ariane"
	@echo "    build vmlinux with"
	@echo "        make vmlinux"
	@echo "    build bbl (with vmlinux) with"
	@echo "        make bbl"
	@echo ""
	@echo "There are two clean targets:"
	@echo "    Clean only buildroot"
	@echo "        make clean"
	@echo "    Clean everything (including toolchain etc)"
	@echo "        make clean-all"
	@echo ""
	@echo "defaults:"
	@echo "    RISCV='$(DEST)'"

