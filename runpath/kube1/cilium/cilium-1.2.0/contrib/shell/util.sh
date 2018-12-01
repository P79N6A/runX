#!/bin/bash
# Copyright 2016 The Kubernetes Authors All rights reserved.
# Copyright 2018 Authors of Cilium
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

readonly  reset=$(tput sgr0)
readonly  green=$(tput bold; tput setaf 2)
readonly yellow=$(tput bold; tput setaf 3)
readonly   blue=$(tput bold; tput setaf 6)
readonly timeout=$(if [ "$(uname)" == "Darwin" ]; then echo "1"; else echo "0.1"; fi)
readonly ipv6regex='(([0-9a-fA-F]{1,4}:){7,7}[0-9a-fA-F]{1,4}|([0-9a-fA-F]{1,4}:){1,7}:|([0-9a-fA-F]{1,4}:){1,6}:[0-9a-fA-F]{1,4}|([0-9a-fA-F]{1,4}:){1,5}(:[0-9a-fA-F]{1,4}){1,2}|([0-9a-fA-F]{1,4}:){1,4}(:[0-9a-fA-F]{1,4}){1,3}|([0-9a-fA-F]{1,4}:){1,3}(:[0-9a-fA-F]{1,4}){1,4}|([0-9a-fA-F]{1,4}:){1,2}(:[0-9a-fA-F]{1,4}){1,5}|[0-9a-fA-F]{1,4}:((:[0-9a-fA-F]{1,4}){1,6})|:((:[0-9a-fA-F]{1,4}){1,7}|:)|fe80:(:[0-9a-fA-F]{0,4}){0,4}%[0-9a-zA-Z]{1,}|::(ffff(:0{1,4}){0,1}:){0,1}((25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])\.){3,3}(25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])|([0-9a-fA-F]{1,4}:){1,4}:((25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])\.){3,3}(25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9]))'

function desc() {
    maybe_first_prompt
    echo "$blue# $@$reset"
    prompt
}

function desc_rate() {
    maybe_first_prompt
    rate=30
    if [ -n "$DEMO_RUN_FAST" ]; then
      rate=1000
    fi
    echo "$blue# $@$reset" | pv -qL $rate
    prompt
}

function prompt() {
    echo -n "$yellow\$ $reset"
}

started=""
function maybe_first_prompt() {
    if [ -z "$started" ]; then
        prompt
        started=true
    fi
}

# After a `run` this variable will hold the stdout of the command that was run.
# If the command was interactive, this will likely be garbage.
DEMO_RUN_STDOUT=""

function run() {
    maybe_first_prompt
    rate=50
    if [ -n "$DEMO_RUN_FAST" ]; then
      rate=1000
    fi
    echo "$green$1$reset" | pv -qL $rate
    if [ -n "$DEMO_RUN_FAST" ]; then
      sleep 0.5
    fi
    OFILE="$(mktemp -t $(basename $0).XXXXXX)"
    script -eq -c "$1" -f "$OFILE"
    r=$?
    read -d '' -t "${timeout}" -n 10000 # clear stdin
    prompt
    if [ -z "$DEMO_AUTO_RUN" ]; then
      read -s
    fi
    DEMO_RUN_STDOUT="$(tail -n +2 $OFILE | sed 's/\r//g')"
    return $r
}

function relative() {
    for arg; do
        echo "$(realpath $(dirname $(which $0)))/$arg" | sed "s|$(realpath $(pwd))|.|"
    done
}

# Continue rebasing and progressively update the daemon/bpf.sha each time there
# is a merge conflict for it. If there are merge conflicts in other files, it
# will stop rebasing and return for user input.
#
# Expected usage:
#   $ git rebase origin/master
#   <Merge failure on daemon/bpf.sha>
#   $ rebase-bindata
#   <For each conflict, your editor opens to review the commit. Save & exit>
function rebase-bindata
{
    (
        set -x
        while ! git rebase --continue ; do
            grep -A 5 "=====" daemon/bpf.sha >daemon/bpf.sha.new
            sed -i '/^[<=>][<=>]*.*$/d' daemon/bpf.sha.new
            sed -i '/^$/d' daemon/bpf.sha.new
            mv -f daemon/bpf.sha.new daemon/bpf.sha
            make -C daemon apply-bindata
            git add daemon/bpf.sha
            if [ $(git diff --diff-filter=U | wc -l) -ne 0 ]; then
                echo "Files that need manual merge:"
                git diff --name-only --diff-filter=U
                break
            fi
        done
    )
}

trap "echo" EXIT