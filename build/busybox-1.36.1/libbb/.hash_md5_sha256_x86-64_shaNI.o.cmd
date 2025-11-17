cmd_libbb/hash_md5_sha256_x86-64_shaNI.o := gcc -Wp,-MD,libbb/.hash_md5_sha256_x86-64_shaNI.o.d  -std=gnu99 -Iinclude -Ilibbb  -include include/autoconf.h -D_GNU_SOURCE -DNDEBUG -D_LARGEFILE_SOURCE -D_LARGEFILE64_SOURCE -D_FILE_OFFSET_BITS=64 -DBB_VER='"1.36.1"' -Os -ffunction-sections -fdata-sections -static -Os -ffunction-sections -fdata-sections -static      -c -o libbb/hash_md5_sha256_x86-64_shaNI.o libbb/hash_md5_sha256_x86-64_shaNI.S

deps_libbb/hash_md5_sha256_x86-64_shaNI.o := \
  libbb/hash_md5_sha256_x86-64_shaNI.S \
    $(wildcard include/config/sha256/hwaccel.h) \
  /usr/aarch64-linux-gnu/include/stdc-predef.h \

libbb/hash_md5_sha256_x86-64_shaNI.o: $(deps_libbb/hash_md5_sha256_x86-64_shaNI.o)

$(deps_libbb/hash_md5_sha256_x86-64_shaNI.o):
