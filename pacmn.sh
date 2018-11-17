#!/bin/bash

export LC_ALL=en_US.UTF-8
set -e
version="0.12.5.1"
old_version="0.12.5.0"
INSTALL_DIR="/home/paccoin"

if [ "$1" == "--testnet" ]; then
	pac_rpc_port=17111
	pac_port=17112
	is_testnet=1
else
	pac_rpc_port=7111
	pac_port=7112
	is_testnet=0
fi


echo 
echo "################################################"
echo "#                   Welcome   	             #"
echo "################################################"
echo 
echo "This script will install PAC to the latest version (${version})."
echo

local_config()
{
	echo "################################################"
	echo "#   Welcome to PAC Masternode's server setup   #"		
	echo "################################################"
	echo "" 
	read -p 'Please provide the external IP: ' ipaddr
	read -p 'Please provide masternode genkey: ' mnkey

	while [[ $ipaddr = '' ]] || [[ $ipaddr = ' ' ]]; do
		read -p 'You did not provided an external IP, please provide one: ' ipaddr
		sleep 2
	done

	while [[ $mnkey = '' ]] || [[ $mnkey = ' ' ]]; do
		read -p 'You did not provided masternode genkey, please provide one: ' mnkey
		sleep 2
	done
	
	mkdir -p $INSTALL_DIR
}

install_dependencies() 
{
	echo "###############################"
	echo "#  Installing Dependencies    #"		
	echo "###############################"
	echo ""
	echo "Running this script on Ubuntu 16.04 LTS or newer is highly recommended."

	sudo apt-get -y update
	sudo apt-get -y install git python virtualenv ufw pwgen 
}

setup_firewall()
{
	echo "###############################"
	echo "#   Setting up the Firewall   #"		
	echo "###############################"
	sudo ufw status
	sudo ufw disable
	sudo ufw allow ssh/tcp
	sudo ufw limit ssh/tcp
	sudo ufw allow $pac_port/tcp
	sudo ufw logging on
	sudo ufw --force enable
	sudo ufw status

	sudo iptables -A INPUT -p tcp --dport $pac_port -j ACCEPT
}

configure_wallet()
{
	echo "###############################"
	echo "#     Configure the wallet    #"		
	echo "###############################"
	echo ""
	echo "The .paccoincore folder will be created, if folder already exists, it will be replaced"
	if [ -d $INSTALL_DIR/.paccoincore ]; then
		if [ -e $INSTALL_DIR/.paccoincore/paccoin.conf ]; then
			read -p "The file paccoin.conf already exists and will be replaced. do you agree [y/n]:" cont
			if [ $cont = 'y' ] || [ $cont = 'yes' ] || [ $cont = 'Y' ] || [ $cont = 'Yes' ]; then
				sudo rm $INSTALL_DIR/.paccoincore/paccoin.conf
				touch $INSTALL_DIR/.paccoincore/paccoin.conf
				cd $INSTALL_DIR/.paccoincore
			fi
		fi
	else
		echo "Creating .paccoincore dir"
		mkdir -p $INSTALL_DIR/.paccoincore
		cd $INSTALL_DIR/.paccoincore
		touch paccoin.conf
	fi

	echo "Configuring the paccoin.conf"
	echo "rpcuser=$(pwgen -s 16 1)" > paccoin.conf
	echo "rpcpassword=$(pwgen -s 64 1)" >> paccoin.conf
	echo "rpcallowip=127.0.0.1" >> paccoin.conf
	echo "rpcport=$pac_rpc_port" >> paccoin.conf
	echo "externalip=$ipaddr" >> paccoin.conf
	echo "port=$pac_port" >> paccoin.conf
	echo "datadir=$INSTALL_DIR/.paccoincore" >> paccoin.conf
	echo "server=1" >> paccoin.conf
	echo "daemon=1" >> paccoin.conf
	echo "listen=1" >> paccoin.conf
	echo "testnet=$is_testnet" >> paccoin.conf
	echo "masternode=1" >> paccoin.conf
	echo "masternodeaddr=$ipaddr:$pac_port" >> paccoin.conf
	echo "masternodeprivkey=$mnkey" >> paccoin.conf
}

find_paccoin_data_dir()
{
    echo '*** Finding $PAC data-dir'
	DATA_DIR="$HOME/.paccoincore"
	if [ -e ./paccoin.conf ] && [ -e ./governance.dat ] && [ -e ./peers.dat ] && [ -d chainstate ] && [ -d blocks ] && [ -d database ]; then
	    DATA_DIR='.';
	elif [ -e $HOME/.paccoin/paccoin.conf ] ; then
	    DATA_DIR="$HOME/.paccoin" ;
	elif [ -e $HOME/.paccoincore/paccoin.conf ] ; then
	    DATA_DIR="$HOME/.paccoincore" ;
	fi

    if [ -e $DATA_DIR ] ; then
    	cd $DATA_DIR
    	rm -f banlist.dat governance.dat netfulfilled.dat budget.dat debug.log fee_estimates.dat mncache.dat mnpayments.dat peers.dat
    	cd
    fi

    CONF_PATH="$DATA_DIR/paccoin.conf"
}

stop_paccoin() {
	echo '*** Stoping any $PAC daemon running'
    INSTALL_DIR=''
    is_pacd_enabled=0

    # Check if running with systemd
    if [ $(systemctl is-active pacd.service) == "active" ] ; then
    	is_pacd_enabled=1
    	sudo systemctl stop pacd.service
    elif [ $(systemctl is-active paccoind.service) == "active" ] ; then
    	sudo systemctl stop paccoind.service
    # paccoin-cli in PATH
    elif [ ! -z $(which paccoin-cli 2>/dev/null) ] ; then
        INSTALL_DIR=$(readlink -f `which paccoin-cli`)
        INSTALL_DIR=${INSTALL_DIR%%/paccoin-cli*};
	# Check current directory
    elif [ -e ./paccoin-cli ] ; then
        INSTALL_DIR='.' ;
	# check ~/.paccoin directory
    elif [ -e $HOME/.paccoin/paccoin-cli ] ; then
        INSTALL_DIR="$HOME/.paccoin" ;
	# check ~/.paccoincore directory
    elif [ -e $HOME/.paccoincore/paccoin-cli ] ; then
        INSTALL_DIR="$HOME/.paccoincore" ;
    fi

    is_pac_running=`ps ax | grep -v grep | grep paccoind | wc -l`
	if [ $is_pac_running -eq 1 ]; then
	    if [ ! -e $INSTALL_DIR/paccoin-cli ]; then
	        killall -9 paccoind 2>/dev/null
	    else
	    	$INSTALL_DIR/paccoin-cli stop 2>&1 >/dev/null
	    fi
	fi

    INSTALL_DIR="$HOME/.paccoincore"
    sleep 5
}

check_crete_swap()
{
	echo "*** Checking if a swapfile exist"
	is_swap_on_system=`swapon -s | wc -l`
	if [ $is_swap_on_system -lt 2 ]; then
		swap_size=1024
		echo "*** Swapfile not found, creating a ${swap_size}M swapfile."
		sudo dd if=/dev/zero of=/var/swapfile bs=1M count=$swap_size
		sudo chmod 600 /var/swapfile
		sudo mkswap /var/swapfile
		sudo sed -i.bak -e '/\/var\/swapfile/d' /etc/fstab
		echo /var/swapfile none swap defaults 0 0 | sudo tee -a /etc/fstab
		sudo swapon -a
		free -h
	fi
}

download_binaries()
{
	arch=`uname -m`
	base_url="https://github.com/PACCommunity/PAC/releases/download/v${version}"
	if [ "${arch}" == "x86_64" ]; then
		tarball_name="PAC-v${version}-linux-x86_64.tar.gz"
		binary_url="${base_url}/${tarball_name}"
	elif [ "${arch}" == "x86_32" ]; then
		tarball_name="PAC-v${version}-linux-x86.tar.gz"
		binary_url="${base_url}/${tarball_name}"
	else
		echo "PAC binary distribution not available for the architecture: ${arch}"
		exit -1
	fi

	mkdir -p $INSTALL_DIR
	cd $INSTALL_DIR

	if test -e "${tarball_name}"; then
		rm -r $tarball_name
	fi
	echo "*** Downloading $tarball_name"
	echo
	wget --no-check-certificate --show-progress -q $binary_url
	if test -e "${tarball_name}"; then
		echo '*** Unpacking $PAC distribution'
		tar -xzf $tarball_name 2>/dev/null
		chmod +x paccoind
		chmod +x paccoin-cli
		echo "*** Binaries were saved to: $INSTALL_DIR"
		rm -r $tarball_name

		echo "*** Adding $INSTALL_DIR PATH to ~/.bash_aliases"
	    if [ ! -f ~/.bash_aliases ]; then touch ~/.bash_aliases ; fi
	    sed -i.bak -e '/paccoin_env/d' ~/.bash_aliases
	    echo "export PATH=$INSTALL_DIR:\$PATH ; # paccoin_env" >> ~/.bash_aliases
	    source ~/.bash_aliases
	else
		echo "There was a problem downloading the binaries, please try running again the script."
		exit -1
	fi

	if [ -e $HOME/paccoind ]; then
		rm $HOME/paccoind
		ln -s $INSTALL_DIR/paccoind $HOME/paccoind
	fi

	if [ -e $HOME/paccoin-cli ]; then
		rm $HOME/paccoin-cli
		ln -s $INSTALL_DIR/paccoin-cli $HOME/paccoin-cli
	fi

	if [ -e $HOME/paccoin-qt ]; then
		rm $HOME/paccoin-qt
		ln -s $INSTALL_DIR/paccoin-qt $HOME/paccoin-qt
	fi
}

install_sentinel()
{
	echo "###############################"
	echo "#     Running the sentinel    #"		
	echo "###############################"
	echo ""
	cron="* * * * * cd $INSTALL_DIR/sentinel && ./venv/bin/python bin/sentinel.py 2>&1 >> sentinel-cron.log"
	sentinel_conf="paccoin_conf=$INSTALL_DIR/.paccoincore/paccoin.conf"
	cd $INSTALL_DIR
	git clone "https://github.com/PACCommunity/sentinel"
	cd sentinel
	virtualenv ./venv
	./venv/bin/pip install -r requirements.txt
	venv/bin/python bin/sentinel.py
	sleep 3
	
	sed -i "/* * */c $cron" crontab.txt
	sed -i "/#paccoin_conf=/c $sentinel_conf" sentinel.conf
	crontab 'crontab.txt'
}

update_sentinel()
{
	echo "*** Updating sentinel"
	was_sentinel_found=0
	currpath=$( pwd )
	if [ -d ~/sentinel ]; then
		was_sentinel_found=1
		cd ~/sentinel
		git pull
		cd $currpath
	fi
}

backup_wallet()
{
	is_pac_running=`ps ax | grep -v grep | grep paccoind | wc -l`
	if [ $is_pac_running -gt 0 ]; then
		echo "PAC process is still running, it's not safe to continue with the update, exiting."
		echo "Please stop the daemon with: './paccoin-cli stop' or, if running through systemd: 'sudo systemctl stop pacd.service' (or paccoind.service), then run the script again."
		exit -1
	else
		currpath=$( pwd )
		echo "*** Backing up wallet.dat"
		backupsdir="pac_wallet_backups"
		mkdir -p $backupsdir
		backupfilename=wallet.dat.$(date +%F_%T)
		cp ~/.paccoincore/wallet.dat "$currpath/$backupsdir/$backupfilename"
		echo "*** wallet.dat was saved to : $currpath/$backupsdir/$backupfilename"
	fi
}

install_and_run_systemd_service()
{
	echo "*** Starting the PAC service"

	PAC_SERVICE_NAME="paccoind.service"
	if [ $is_pacd_enabled -eq 1 ]; then
		PAC_SERVICE_NAME="pacd.service"
	fi
# 	CURRENT_USER="User=$USER"
	EXEC_START_CMD="ExecStart=$INSTALL_DIR/paccoind -daemon -conf=$INSTALL_DIR/.paccoincore/paccoin.conf -datadir=$INSTALL_DIR/.paccoincore -pid=/run/paccoind/paccoind.pid"
	PAC_SERVICE_URL="https://raw.githubusercontent.com/PACCommunity/PAC/master/contrib/init/paccoind.service"
	wget --no-check-certificate --show-progress -q -O $PAC_SERVICE_NAME $PAC_SERVICE_URL 
# 	sed -i "/User=/c $CURRENT_USER" $PAC_SERVICE_NAME
	sed -i "/ExecStart=/c $EXEC_START_CMD" $PAC_SERVICE_NAME
	sudo cp $PAC_SERVICE_NAME /etc/systemd/system/$PAC_SERVICE_NAME
	chown -R paccoin: $INSTALL_DIR
	sudo systemctl enable $PAC_SERVICE_NAME
	sudo systemctl start $PAC_SERVICE_NAME
	sleep 5
	echo
	echo "*** The PAC service succefully started!"
	echo "*** Some of the available options: start, stop, restart or status."
	echo "*** Example: 'systemctl status ${PAC_SERVICE_NAME}'"
	echo
	systemctl status -n 0 --no-pager $PAC_SERVICE_NAME
	echo
	paccoin-cli getinfo
	rm $PAC_SERVICE_NAME
	echo 
	echo "==> PAC Updated!"
	echo "==> Remember to go to your cold wallet and start the masternode (cold wallet must also be on the latest version)."
}

local_config
# stop_paccoin
# find_paccoin_data_dir
install_dependencies
setup_firewall
configure_wallet
download_binaries
check_crete_swap
# update_sentinel
install_sentinel
# backup_wallet
install_and_run_systemd_service