#!/usr/bin/bash

export KUBEDIR=$HOME/.kube
export CONFIGLOCAL='../configs/config'

cd $(dirname $0)

if [ ! -f $CONFIGLOCAL ]; then
	echo "../configs/config doesn't exist."
	exit	
fi

mkdir -p $KUBEDIR

if [ ! -f $KUBEDIR/config ]; then
	cp -b $CONFIGLOCAL $KUBEDIR/config
	echo "OK"
	exit	
fi


