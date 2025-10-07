#
# (c) Copyright 2020-2025 JRCS Ltd - All Right Reserved
#
CC=gcc
ALL_FLAGS=-Wall -Wextra -Wshadow -pedantic -Wno-variadic-macros -Wnull-dereference -Wformat=2 -Wno-format-y2k
CFLAGS=-O2 $(ALL_FLAGS)
# CFLAGS=-ggdb $(ALL_FLAGS)
LDFLAGS=
#
OBJS=log_message.o udp_sock.o root_proxy.o liball.o stats.o
TARGET=root_proxy

ALL: depends depends.include $(TARGET)

install:
	strip -p root_proxy
	cp -au root_proxy ../bin

all:
	sh -c "make ALL"

depends:
	./make_depends

depends.include:
	./make_depends

-include depends
-include depends.include

clean:
	rm -f $(OBJS) $(TARGET) depends depends.include .depends.*

$(TARGET): $(OBJS)
