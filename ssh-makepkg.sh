#! /bin/bash
declare -a PKG
port='-p 22'
function naming {
  if [ -z pkg_num ] ; then $pkg_num=1 ; fi
  PKG[$pkg_num]=$@
  pkg_num=$((pkg_num+1))
}

declare -a DEP
dep_num=1

function check_installed {
pacman -Qi $@ 2> /dev/null > /dev/null ; if [ ! $? = 0 ]
  then pacman -Qsq ^$@\$ 2> /dev/null > /dev/null ; if [ ! $? = 0 ]
    then pacman -Si $@ 2> /dev/null > /dev/null ; if [ ! $? = 0 ]
      then DEP[$dep_num]=$1 ; dep_num=$((dep_num+1))
    fi
  fi
fi
}

function missing_deps {
temp=$(cower --format='%D' -i $1)
for i in $temp ; do
check_installed $(echo $i | cut -f1 -d">")
done
}

if [[ -z $(echo $@) ]] ; then echo 'use -h | --help' ; exit ; fi
while true; do
  case $1 in
    '' 				) break ;;
    *@*.*.*.* 			) if [ -z $ipnotset ] ; then export ip=$1 ; export ipnotset=false ; shift ; else echo 'Ip was parsed multiple times' ; exit 2 ; fi ;;
    *.*.*.* 			) if [ -z $ipnotset ] ; then export ip=$1 ; export ipnotset=false ; shift ; else echo 'Ip was parsed multiple times' ; exit 2 ; fi ;;
    -p				) export port=$2 ; shift 2 ;;
    -h | --help			) echo 'Just write the remote machine as you would in a ssh command (-p for port) and the aur packages you want to install' ; exit 0 ;;
    *				) naming $1 ; shift 1 ;;
  esac
done

for i in $@ ; do
missing_deps $i
done

localport=$(cat /etc/ssh/sshd_config | grep Port | grep -v Gate | cut -d ' ' -f 2) ; localport=$(echo -P $localport)
export remoteuser=$USER
export packages=$(echo ${PKG[@]})
export pkgdeps=$(echo ${DEP[@]})
if [ ! -e /tmp/scp-receive ] ; then mkdir /tmp/scp-receive ; fi

ssh -t $ip $(echo '-p' $port) export localport=\"$localport\" export pkgdeps=\"$pkgdeps\" export remoteuser=\"$remoteuser\" export pkg=\"$packages\" 'export iplocal=$( echo $SSH_CLIENT )' '
export EDITOR=/bin/true
export PATH="/usr/local/bin:/usr/local/bin:/usr/local/sbin:/usr/local/bin:/usr/bin:/usr/bin/site_perl:/usr/bin/vendor_perl:/usr/bin/core_perl"

while true; do sudo -v; sleep 40; done &

sudo pacman -Syu

declare -a aDEP
export adep_num=1
function aurdeps {
if [ -z adep_num ] ; then $adep_num=1 ; fi
pacman -Qi $@ 2> /dev/null > /dev/null ; if [ ! $? = 0 ]
  then pacman -Qsq ^$@\$ 2> /dev/null > /dev/null ; if [ ! $? = 0 ]
    then pacman -Si $@ 2> /dev/null > /dev/null ; if [ ! $? = 0 ]
      then aDEP[$adep_num]=$1
      adep_num=$((adep_num+1))
    fi
  fi
fi
}
temp=$(cower --format='%D %K %M' -i $(echo $pkg $pkgdeps))
for i in $temp
  do aurdeps $(echo $i | cut -f1 -d">")
done

if [ ! -z $(echo ${aDEP[@]}) ]
  then if [ ! -e /tmp/build ] ; then mkdir /tmp/build ; fi ; cd /tmp/build
  cower -d ${aDEP[@]}
  for i in $PWD/*
    do cd $i
    yes | makepkg -sir 
  done
fi 

export PKGDEST="/tmp/scp"
iplocal=$(echo $iplocal | cut -d \  -f 1)
if [ ! -e /tmp/scp ] ; then mkdir /tmp/scp ; fi
if [ ! -e /tmp/build ] ; then mkdir /tmp/build ; fi ; cd /tmp/build
cower -d $(echo $pkg)

for i in $PWD/*
  do cd $i
  if [[ ! -z $(find /tmp/scp/ -name "*.pkg.*" | grep $i) ]]
    then echo Found previously built packages.
    else yes | makepkg -sr 
  fi
done

if [ ! -z ${aDEP[@]} ] ; then yes | sudo pacman -Rc ${aDEP[@]} ; fi

rm -rf /tmp/build/
echo Trying to scp
scp $localport /tmp/scp/* $remoteuser@$iplocal:/tmp/scp-receive ; if [ ! $? = 0 ] 
  then rm -rf /tmp/scp/* 
  else Something went wrong with scp from the remote machine's' side. Are you behind nat? Built packages are in /tmp/scp .
fi
sudo -k
'
exit
if [ -z $(ls /tmp/scp-receive/) ]
  then echo 'This should probably work... maybe'
  scp $ip:/tmp/scp/* /tmp/scp-receive/ $(echo '-P' $port) ; if [ ! $? = 0 ]
    then echo 'Dunno what is up.... packages are most likely still there.'
  fi
  ssh $ip $(echo '-P' $port) 'rm -rf /tmp/scp/*'
fi
sudo -v
sudo pacman -U /tmp/scp-receive/*
sudo -k
read -p "Delete pkgs? y/n?" choice
case "$choice" in
  y|Y|yes ) rm -rf /tmp/scp-receive/* ;;
  n|N|no ) exit ;;
  * ) exit ;;
esac

