#! /bin/bash
port=22
declare -a PKG
declare -a DEP
declare -a BLD
dep_num=1
pkg_num=1
editor=/bin/true

function naming {
  PKG[$pkg_num]=$1
  pkg_num=$((pkg_num+1))
}

function check_installed {
  pacman -Qi $1 2> /dev/null > /dev/null ; if [ ! $? = 0 ]
    then pacman -Qsq ^$1\$ 2> /dev/null > /dev/null ; if [ ! $? = 0 ]
      then pacman -Si $1 2> /dev/null > /dev/null ; if [ ! $? = 0 ]
        then return 1
      fi
    fi
  fi
}

function missing_deps {
  local miss=$(cower --format='%D' -i $1 | cut -f1 -d">")
  for i in $miss
    do check_installed $i ; if [ $? = 1 ]
      then export DEP="${DEP[@]} $i"
    fi
  done
}

function deps_build {
  local miss=$(cower --format='%D %K %M' -i $1 | cut -f1 -d">")
  for i in $miss
    do BLD[$dep_num]=$i ; dep_num=$((dep_num+1))
  done
}

help='Usage: (user@)host (-p 22) (-e) pkg1 pkg2 pkg3

Arguments in parenthesis can be ommited.

-p: port (defaults to 22)
-e: edit pkgbuilds (defaults to /bin/true - no editor)

Packages are to be separated by space. There is no need for them to be in order.
Dependencies are to be automatically resolved in both the remote and local machine.
In the remote machine are automatically uninstalled when not needed.

Example: nikos@1.2.3.4 -p 123 sway-git wlc-git
'


if [[ -z $(echo $@) ]] ; then echo 'use -h | --help for help' ; exit ; fi
while true; do
  case $1 in
    '' 				) break ;;
    *@*.*.* 			) if [ -z $ipnotset ] ; then export ip=$1 ; export ipnotset=false ; shift ; else echo 'Ip was parsed multiple times' ; exit 2 ; fi ;;
    *.*.* 			) if [ -z $ipnotset ] ; then export ip=$1 ; export ipnotset=false ; shift ; else echo 'Ip was parsed multiple times' ; exit 2 ; fi ;;
    -p				) export port=$2 ; shift 2 ;;
    -h | --help			) echo "$help" ; exit 0 ;;
    -e | --edit			) export editor=$EDITOR ; shift ;;
    *				) naming $1 ; shift 1 ;;
  esac
done

if [ -z $ipnotset ] ; then echo 'No ip was set for the remote ssh server' ; exit 2 ; fi


localport=$(cat /etc/ssh/sshd_config | grep Port | grep -v Gate | cut -d ' ' -f 2) ; localport=$(echo -P $localport)
export remoteuser=$USER
if [ ! -e /tmp/scp-receive ] ; then mkdir /tmp/scp-receive ; fi

for i in ${PKG[@]} ; do
  missing_deps $i ; done

for i in ${PKG[@]} ; do
  deps_build $i ; done

function_check_installed=$(type check_installed | grep -v function) ; ssh -t $ip $(echo '-p' $port) "
eval $(echo "$function_check_installed")" "
export localport=\"$localport\"" "remoteuser=$remoteuser" "EDITOR=$editor" pkg="`echo '('${PKG[@]}')'`" dep="`echo '(' ${DEP[@]} ')'`" bld="`echo '(' ${BLD[@]} ')'`" '
iplocal=$(echo $SSH_CLIENT)' '
PATH="/usr/local/bin:/usr/local/bin:/usr/local/sbin:/usr/local/bin:/usr/bin:/usr/bin/site_perl:/usr/bin/vendor_perl:/usr/bin/core_perl"' '

while true; do sudo -v; sleep 40; done &
sudo pacman -Syu

declare -a old_DEPs
dep_num=1
iplocal=$(echo $iplocal | cut -d \  -f 1)

function buildpkgdeps {
  cower -d $1 ; cd $1 ; $EDITOR PKGBUILD ; yes | makepkg -sri
  cd /tmp/build ; rm -rf $1
}

function buildpkg {
  cower -d $1 ; cd $1 ; $EDITOR PKGBUILD ; yes | makepkg -sr
  cd /tmp/build ; rm -rf $1
}

function built {
  local built=$(find /tmp/scp/ -name "*.pkg.*" | grep $1)
  if [[ ! -z $builtat ]]
    then echo Found previously built packages.
    export builtat="$built $builtat"
    else return 0
  fi
}

if [ ! -e /tmp/scp ] ; then mkdir /tmp/scp ; fi
if [ ! -e /tmp/build ] ; then mkdir /tmp/build ; fi ; cd /tmp/build

for i in $(echo ${blk[@]}) ; do
  if [ -z $(echo ${pkg[@]} | grep $i) ] || [ -z $(echo ${dep[@]} | grep $i) ]
    then check_installed $i ;  if [ $? = 1 ]
      then built $i ; if [ ! $? = 0 ]
        then sudo pacman -U $builtat
        else buildpkgdeps $i
      fi
      old_DEPs[$dep_num]=$i ; dep_num=$((dep_num+1))
    fi
  fi
done

export PKGDEST="/tmp/scp"

for i in $(echo ${dep[@]}) ; do
  built $i ; if [ ! $? = 0 ]
    then sudo pacman -U $builtat ; old_DEPs[$dep_num]=$i ; dep_num=$((dep_num+1))
    else buildpkgdeps $i
  fi
done

for i in $(echo ${pkg[@]}) ; do
  if [ -z $(echo ${dep[@]} | grep $i) ]
    then built $i ; if [ $? = 0 ]
      then buildpkg $i
    fi
    else echo $i has already been built
  fi
done

if [ ! -z ${old_DEPs[@]} ] ; then 
  yes | sudo pacman -Rc ${old_DEPs[@]} ; fi

rm -rf /tmp/build/
#echo Trying to scp
#scp $localport /tmp/scp/* $remoteuser@$iplocal:/tmp/scp-receive ; if [ $? = 0 ] 
#  then rm -rf /tmp/scp/* 
#  else echo Something went wrong with scp from the remote machine side. Are you behind nat\? Built packages are in /tmp/scp .
#fi
sudo -k
'

echo "SCP into machine to download packages"
scp $(echo '-P' $port) $ip:/tmp/scp/* /tmp/scp-receive/ ; if [ ! $? = 0 ] 
  then echo 'Dunno what is up.... packages are most likely still there.'
  else ssh $ip $(echo '-p' $port) '
    rm -rf /tmp/scp/*'
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
