# Copyright © 2017, Thomas Debesse
# Covered by BSD 3-Clause license
# See LICENSE.md for details

.DEFAULT_GOAL := build

ROOT_DIR := $(shell dirname $(realpath $(lastword $(MAKEFILE_LIST))))
NPROC := $(shell nproc)

ENGINE_REPO := https://github.com/DaemonEngine/Daemon.git
GAMEVM_REPO := https://github.com/Unvanquished/Unvanquished.git
ASSETS_REPO := https://github.com/UnvanquishedAssets/UnvanquishedAssets.git

ENGINE_DIR := ${ROOT_DIR}/Daemon
GAMEVM_DIR := ${ROOT_DIR}/Unvanquished
ASSETS_DIR := ${ROOT_DIR}/UnvanquishedAssets

ifeq ($(USE_PAK),)
	PAKPREFIX := test
else
	PAKPREFIX := pkg
endif

ENGINE_BUILD := ${ENGINE_DIR}/build
GAMEVM_BUILD := ${GAMEVM_DIR}/build
ASSETS_BUILD := ${ASSETS_DIR}/build/${PAKPREFIX}

ifneq ($(USE_GDB),)
	CMAKE_DEBUG_ARGS := -D'USE_BREAKPAD=OFF' -D'CMAKE_BUILD_TYPE=Debug' -D'USE_DEBUG_OPTIMIZE=OFF'
	CMAKE_GAMEVM_ARGS := -D'BUILD_GAME_NACL=OFF' -D'BUILD_GAME_NACL_NEXE=OFF' -D'BUILD_GAME_NATIVE_EXE=OFF' -D'BUILD_GAME_NATIVE_DLL=ON'

	# Hardcode that .gdbinit.txt path since “auto-load safe-path” usually prevents loading .gdbinit from current dir
	# Use another name to prevent printing useless warnings saying it will not loaded since we force it to be loaded
	GDB_COMMAND := gdb -x .gdbinit.txt -args
else
	CMAKE_DEBUG_ARGS := -D'USE_BREAKPAD=ON' -D'CMAKE_BUILD_TYPE=RelWithDebInfo'
	CMAKE_GAMEVM_ARGS := -D'BUILD_GAME_NACL=ON' -D'BUILD_GAME_NACL_NEXE=ON' -D'BUILD_GAME_NATIVE_EXE=OFF' -D'BUILD_GAME_NATIVE_DLL=OFF'
endif

ifeq ($(VM_TYPE),)
	VM_TYPE := 3
endif

ENGINE_VMTYPE_ARGS := -set vm.cgame.type ${VM_TYPE} -set vm.sgame.type ${VM_TYPE}

ENGINE_DEBUG_ARGS := -set logs.logLevel.default debug -set language en -set developer 1

EXTRA_PAKPATHS := $(shell [ -f .pakpaths ] && (sed -e 's/^/-pakpath /' .pakpaths | tr '\n' ' '))

clone-engine:
	(! [ -d '${ENGINE_DIR}' ] && git clone '${ENGINE_REPO}' '${ENGINE_DIR}') || true

clone-vms:
	(! [ -d '${GAMEVM_DIR}' ] && git clone '${GAMEVM_REPO}' '${GAMEVM_DIR}') || true

clone-assets:
	(! [ -d '${ASSETS_DIR}' ] && git clone '${ASSETS_REPO}' '${ASSETS_DIR}') || true
	make -C '${ASSETS_DIR}' clone

clone-bin: clone-engine clone-vms

clone: clone-bin clone-assets

pull-engine:
	cd '${ENGINE_DIR}' && (git remote | grep '^upstream$$' || git remote add upstream '${ENGINE_REPO}') || true
	cd '${ENGINE_DIR}' && git checkout master && git pull upstream master

pull-vms:
	cd '${GAMEVM_DIR}' && (git remote | grep '^upstream$$' || git remote add upstream '${GAMEVM_REPO}') || true
	cd '${GAMEVM_DIR}' && git checkout master && git pull upstream master

pull-assets:
	cd '${ASSETS_DIR}' && (git remote | grep '^upstream$$' || git remote add upstream '${ASSETS_REPO}') || true
	cd '${ASSETS_DIR}' && git checkout master && git pull upstream master
	make -C '${ASSETS_DIR}' pull

pull-bin: pull-engine pull-vms

pull: pull-bin pull-assets

engine:
	cmake '${ENGINE_DIR}' -B'${ENGINE_BUILD}' \
		${CMAKE_DEBUG_ARGS} \
		-D'BUILD_SERVER=ON' -D'BUILD_CLIENT=ON' -D'BUILD_TTY_CLIENT=ON' \
		-G'Unix Makefiles'
	cmake --build '${ENGINE_BUILD}' -- -j'${NPROC}'

vms:
	cmake '${GAMEVM_DIR}' -B'${GAMEVM_BUILD}' \
		${CMAKE_DEBUG_ARGS} \
		${CMAKE_GAMEVM_ARGS} \
		-D'BUILD_SERVER=OFF' -D'BUILD_CLIENT=OFF' -D'BUILD_TTY_CLIENT=OFF' \
		-D'BUILD_SGAME=ON' -D'BUILD_CGAME=ON' \
		-D'DAEMON_DIR=${ENGINE_DIR}' \
		-G'Unix Makefiles'
	cmake --build '${GAMEVM_BUILD}' -- -j'${NPROC}'

bin: engine vms

assets:
	make -C '${ASSETS_DIR}' build

maps:
	make -C '${ASSETS_DIR}' build_maps

resources:
	make -C '${ASSETS_DIR}' build_resources

textures:
	make -C '${ASSETS_DIR}' build_textures

data: assets

build: bin data

run-server:
	${GDB_COMMAND} \
	'${ENGINE_BUILD}/daemonded' \
		${ENGINE_DEBUG_ARGS} \
		${ENGINE_VMTYPE_ARGS} \
		-libpath '${GAMEVM_BUILD}' \
		-pakpath '${ASSETS_BUILD}' \
		${EXTRA_PAKPATHS} \
		${EXTRA_ARGS}

run-client:
	${GDB_COMMAND} \
	'${ENGINE_BUILD}/daemon' \
		${ENGINE_DEBUG_ARGS} \
		${ENGINE_VMTYPE_ARGS} \
		-libpath '${GAMEVM_BUILD}' \
		-pakpath '${ASSETS_BUILD}' \
		${EXTRA_PAKPATHS} \
		${EXTRA_ARGS}

run-tty:
	${GDB_COMMAND} \
	'${ENGINE_BUILD}/daemon-tty' \
		${ENGINE_DEBUG_ARGS} \
		${ENGINE_VMTYPE_ARGS} \
		-libpath '${GAMEVM_BUILD}' \
		-pakpath '${ASSETS_BUILD}' \
		${EXTRA_PAKPATHS} \
		${EXTRA_ARGS}

run: run-client

load_map:
	$(MAKE) run EXTRA_ARGS="${EXTRA_ARGS} +devmap antares"

load_game:
	$(MAKE) load_map EXTRA_ARGS="${EXTRA_ARGS} +delay 1000 bot fill 3"

it: build load_game
