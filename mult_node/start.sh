#!/bin/bash

# $1: fun
# $2: wallet dir
# $3: contract dir
# $4: number of node

function usage() {
	echo -e "Usage: $0 cmd [wallet_dir contract_dir node_num]\n"
    echo $" [ command ]"
    echo $"  - clean           : remove all data"
    echo $"  - run             : run this script and open nodes"
}

function clean() {
	rm -rf data/*
	rm -rf log/*
	rm -rf wpk/*
	rm -rf init.key
	pkill nodeos
	echo "clean successfully."
}

function check() {
	if [ $# != 4 ]
	then
		echo $#
	    usage
	    exit 1
	fi

	read -r -p "the wallet dir is $2, and the contract dir is $3, continue? [Y/n] " input

	case $input in
	    [yY][eE][sS]|[yY])
			echo "Yes"
			;;
	    [nN][oO]|[nN])
			echo "No"
			exit 0
	       		;;
	    *)
		echo "Invalid input..."
		exit 1
		;;
	esac
}

function run() {
	check $1 $2 $3 $4

	mkdir data 2>/dev/null
	mkdir log 2>/dev/null
	mkdir wpk 2>/dev/null

	rm -rf data/*
	pkill nodeos

	keosd > log/keosd.log 2>&1 &
	echo -e "\n---keosd prepared---"

	cd $2
	rm -rf ./*
	cd -

	cleos wallet create --file wpk/default.wpk
	echo -e "---default wallet created---\n"

	cleos wallet import --private-key 5KQwrPbwdL6PhXujxW37FSSQZ1JiwsST4cqQzDeyXtP79zkvFD3

	echo "----------------------"
	echo -e "\n---start node 1---\n"
	nodeos --enable-stale-production --producer-name eosio --config node1.ini \
	--config-dir conf --data-dir data/node1 \
	--max-transaction-time=1000 --delete-all-blocks > log/node1.log 2>&1 &

	echo "---create account---"
	cleos create key --file init.key

	pub_key=$(cat init.key | awk '/Public/ {print $3}')
	priv_key=$(cat init.key | awk '/Private/ {print $3}')

	cleos wallet import --private-key $priv_key
	cleos create account eosio init $pub_key $pub_key

	echo -e "\n---deploy the contract---"
	cd $3
	cleos set contract eosio ./eosio.bios
	cd -

	for((x=2;x<=$4;x++));do
		echo -e "\n----------------------"
		echo "---start node $x---"
		nodeos --producer-name node$x --config node$x.ini --config-dir conf \
	    --data-dir data/node$x --private-key $priv_key > log/node$x.log 2>&1 &
	done
}

case "$1" in
    clean)
        clean
        ;;
    run)
        run $1 $2 $3 $4
        ;;
    *)
    usage
	exit 1
esac
