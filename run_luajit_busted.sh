#!/bin/sh
# Run busted under luajit instead of plain lua5.1. Needed only for
# spec/voice/crypto_spec.lua, which requires ffi (LuaJIT-only) and
# libsodium to exercise the real encrypt/decrypt round-trip instead of
# the pending placeholder. The rest of the suite (busted's default
# lua5.1 wrapper at /usr/sbin/busted) is unaffected and should stay the
# CI-matching target for everything else.
#
# Usage: ./run_luajit_busted.sh [busted args, e.g. a spec path]

cd "$(dirname "$0")"
LUA_PATH="./deps/?.lua;./deps/?/init.lua;;" \
LUAROCKS_SYSCONFDIR='/etc/luarocks' \
exec luajit -e 'package.path="/usr/share/lua/5.1/?.lua;/usr/share/lua/5.1/?/init.lua;"..package.path;package.cpath="/usr/lib/lua/5.1/?.so;"..package.cpath;local k,l,_=pcall(require,"luarocks.loader") _=k and l.add_context("busted","2.3.0-1")' '/usr/lib/luarocks/rocks-5.1/busted/2.3.0-1/bin/busted' "$@"
