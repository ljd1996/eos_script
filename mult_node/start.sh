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
	rm -rf key/*
	rm -rf init.key
	pkill nodeos
	pkill keosd
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

function prepare() {
	check $1 $2 $3 $4

	mkdir data 2>/dev/null
	mkdir log 2>/dev/null
	mkdir wpk 2>/dev/null
	mkdir key 2>/dev/null

	rm -rf data/*
	pkill nodeos
	pkill keosd

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
	nodeos --producer-name eosio --config node1.ini \
	--config-dir conf --data-dir data/node1 \
	--max-transaction-time=1000 --delete-all-blocks > log/node1.log 2>&1 &
}

function run() {
	prepare $1 $2 $3 $4

	echo -e "---sleep 3 s---\n"
	sleep 3

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
		tmp=$(expr $x / 5)
		name="node"
		for((i=0;i<$tmp;i++));do
			name=${name}5
		done
		if [[ $(expr $x % 5) != 0 ]]; then
			name=$name$(expr $x % 5)
		fi
		nodeos --producer-name $name --config node$x.ini --config-dir conf \
	    --data-dir data/node$x --private-key $priv_key > log/node$x.log 2>&1 &
	done
}

function run_vote() {
	prepare $1 $2 $3 $4

	echo -e "---sleep 3 s---\n"
	sleep 3

	echo "---create account---"
	cleos create key --file init.key

	pub_key=$(cat init.key | awk '/Public/ {print $3}')
	priv_key=$(cat init.key | awk '/Private/ {print $3}')

	cleos wallet import --private-key $priv_key
	cleos create account eosio init $pub_key $pub_key
	cleos create account eosio eosio.bios $pub_key $pub_key
	cleos create account eosio eosio.system $pub_key $pub_key
	cleos create account eosio eosio.bpay $pub_key $pub_key
	cleos create account eosio eosio.msig $pub_key $pub_key
	cleos create account eosio eosio.names $pub_key $pub_key
	cleos create account eosio eosio.ram $pub_key $pub_key
	cleos create account eosio eosio.ramfee $pub_key $pub_key
	cleos create account eosio eosio.saving $pub_key $pub_key
	cleos create account eosio eosio.stake $pub_key $pub_key
	cleos create account eosio eosio.token $pub_key $pub_key
	cleos create account eosio eosio.vpay $pub_key $pub_key

	echo -e "\n---create keys---"
	for((x=2;x<=$4;x++));do
		cleos create key --file key/prod$x.key
		pub_key_t=$(cat key/prod$x.key | awk '/Public/ {print $3}')
		priv_key_t=$(cat key/prod$x.key | awk '/Private/ {print $3}')
		cleos wallet import --private-key $priv_key_t
	done

	echo -e "\n---deploy the contract and create token---"
	cd $3
	# cleos set contract eosio.bios ./eosio.bios
	cleos set contract eosio.token ./eosio.token
	cleos set contract eosio.msig ./eosio.msig
	cleos set contract eosio ./eosio.system
	cd -

	cleos push action eosio.token create '["eosio", "10000000000.0000 EOS"]' -p eosio.token
	cleos push action eosio.token issue '["eosio", "10000000000.0000 EOS", "memo"]' -p eosio
	cleos push action eosio setpriv '["eosio.msig", 1]' -p eosio@active

	echo -e "\n---create producer account---"
	cleos push action eosio init '[0, "4,EOS"]' -p eosio@active

	for((x=2;x<=$4;x++));do
		pub_key_t=$(cat key/prod$x.key | awk '/Public/ {print $3}')
		priv_key_t=$(cat key/prod$x.key | awk '/Private/ {print $3}')
		# create and transfer to producer
		tmp=$(expr $x / 5)
		name="prod"
		name1="user"
		for((i=0;i<$tmp;i++));do
			name=${name}5
			name1=${name1}5
		done
		if [[ $(expr $x % 5) != 0 ]]; then
			name=$name$(expr $x % 5)
			name1=$name1$(expr $x % 5)
		fi
		echo "---${name}---${name1}---"
		echo "---${pub_key_t}---${priv_key_t}---"
		cleos system newaccount --transfer eosio $name $pub_key_t --stake-net "100000000.0000 EOS" \
	    --stake-cpu "100000000.0000 EOS" --buy-ram "20000.0000 EOS"   
		cleos transfer eosio $name "20000.0000 EOS"
		cleos system newaccount --transfer eosio $name1 $pub_key_t --stake-net "100000000.0000 EOS" \
	    --stake-cpu "100000000.0000 EOS" --buy-ram "20000.0000 EOS"   
		cleos transfer eosio $name1 "20000.0000 EOS"

		cleos system regproducer $name $pub_key_t
	done

	for((x=2;x<=$4;x++));do
		pub_key_t=$(cat key/prod$x.key | awk '/Public/ {print $3}')
		priv_key_t=$(cat key/prod$x.key | awk '/Private/ {print $3}')

		echo -e "\n----------------------"
		echo "---start node $x---"
		tmp=$(expr $x / 5)
		name="prod"
		for((i=0;i<$tmp;i++));do
			name=${name}5
		done
		if [[ $(expr $x % 5) != 0 ]]; then
			name=$name$(expr $x % 5)
		fi
		nodeos --producer-name $name --signature-provider $pub_key_t=KEY:$priv_key_t --config node$x.ini --config-dir conf \
	    --data-dir data/node$x --private-key $priv_key > log/node$x.log 2>&1 &
	done
}

function vote() {
	for((y=2;y<=$2;y++));do
		for((x=2;x<=$y;x++));do
			tmp=$(expr $x / 5)
			name="prod"
			name1="user"
			for((i=0;i<$tmp;i++));do
				name=${name}5
				name1=${name1}5
			done
			if [[ $(expr $x % 5) != 0 ]]; then
				name=$name$(expr $x % 5)
				name1=$name1$(expr $x % 5)
			fi
		done
		echo -e "${name}---${name1}\n"
		cleos system voteproducer prods $name1 $name
	done
}

case "$1" in
    clean)
        clean
        ;;
    run_vote)
        run_vote $1 $2 $3 $4
        ;;
    vote)
        vote $1 $2
        ;;
    run)
        run $1 $2 $3 $4
        ;;
    prepare)
        prepare $1 $2 $3 $4
        ;;
    *)
    usage
	exit 1
esac
