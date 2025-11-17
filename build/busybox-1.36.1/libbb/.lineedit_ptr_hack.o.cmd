cmd_libbb/lineedit_ptr_hack.o := gcc -Wp,-MD,libbb/.lineedit_ptr_hack.o.d  -std=gnu99 -Iinclude -Ilibbb  -include include/autoconf.h -D_GNU_SOURCE -DNDEBUG -D_LARGEFILE_SOURCE -D_LARGEFILE64_SOURCE -D_FILE_OFFSET_BITS=64 -DBB_VER='"1.36.1"' -Os -ffunction-sections -fdata-sections -static -Os -ffunction-sections -fdata-sections -static   -DKBUILD_BASENAME='"lineedit_ptr_hack"'  -DKBUILD_MODNAME='"lineedit_ptr_hack"' -c -o libbb/lineedit_ptr_hack.o libbb/lineedit_ptr_hack.c

deps_libbb/lineedit_ptr_hack.o := \
  libbb/lineedit_ptr_hack.c \
  /usr/aarch64-linux-gnu/include/stdc-predef.h \

libbb/lineedit_ptr_hack.o: $(deps_libbb/lineedit_ptr_hack.o)

$(deps_libbb/lineedit_ptr_hack.o):
