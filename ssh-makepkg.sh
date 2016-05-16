#! /bin/bash
declare -a PKG
declare -a DEP
declare -a BLD
dep_num=1
pkg_num=1

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
  local miss=$(cower --format='%D' -i $1)
  for i in $miss
    do check_installed $(echo $i | cut -f1 -d">") ; if [ $? = 1 ]
      then DEP[$dep_num]=$i ; dep_num=$((dep_num+1))
    fi
  done
}

function deps_build {
  local miss=$(cower --format='%D %K %M' -i $1 | cut -f1 -d">")
  for i in $miss
    do BLD[$dep_num]=$i ; dep_num=$((dep_num+1))
  done
}

if [[ -z $(echo $@) ]] ; then echo 'use -h | --help' ; exit ; fi
while true; do
  case $1 in
    '' 				) break ;;
    *@*.*.* 			) if [ -z $ipnotset ] ; then export ip=$1 ; export ipnotset=false ; shift ; else echo 'Ip was parsed multiple times' ; exit 2 ; fi ;;
    *.*.*.* 			) if [ -z $ipnotset ] ; then export ip=$1 ; export ipnotset=false ; shift ; else echo 'Ip was parsed multiple times' ; exit 2 ; fi ;;
    -p				) export port=$2 ; shift 2 ;;
    -h | --help			) echo 'Just write the remote machine as you would in a ssh command (-p for port) and the aur packages you want to install' ; exit 0 ;;
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

pkg=${PKG[@]}
dep=${DEP[@]} 
bld=${BLD[@]}

function_check_installed=$(type check_installed | grep -v function) ; ssh -t $ip $(echo '-p' $port) "eval $function_check_installed" "
export localport=\"$localport\"" "remoteuser=$remoteuser" "pkg=$pkg" "dep=$dep" "bld=$bld" '
iplocal=$(echo $SSH_CLIENT)' 'EDITOR=/bin/true' '
PATH="/usr/local/bin:/usr/local/bin:/usr/local/sbin:/usr/local/bin:/usr/bin:/usr/bin/site_perl:/usr/bin/vendor_perl:/usr/bin/core_perl"' '

while true; do sudo -v; sleep 40; done &
sudo pacman -Syu

declare -a old_DEPs
dep_num=1
iplocal=$(echo $iplocal | cut -d \  -f 1)

function buildpkg {
  cower -d $1 ; cd $1 ; yes | makepkg -sri
  cd /tmp/build ; rm -rf $1
}

function built {
  builtat=$(find /tmp/scp/ -name "*.pkg.*" | grep $1)
  if [[ ! -z $builtat ]]
    then echo Found previously built packages.
    export builtat=$builtat
    else return 0
  fi
}

if [ ! -e /tmp/scp ] ; then mkdir /tmp/scp ; fi
if [ ! -e /tmp/build ] ; then mkdir /tmp/build ; fi ; cd /tmp/build

for i in $(echo $blk) ; do
  if [ -z $(echo $pkg | grep $i) ] || [ -z $(echo $dep | grep $i) ]
    then check_installed $i ;  if [ $? = 1 ]
      then built $i ; if [ ! $? = 0 ]
        then sudo pacman -U $builtat
        else buildpkg $i
      fi
      old_DEPs[$dep_num]=$i ; dep_num=$((dep_num+1))
    fi
  fi
done

export PKGDEST="/tmp/scp"

for i in $(echo $dep) ; do
  built $i ; if [ ! $? = 0 ]
    then sudo pacman -U $builtat ; old_DEPs[$dep_num]=$i ; dep_num=$((dep_num+1))
    else buildpkg $i
  fi
done

for i in $(echo $pkg) ; do
  if [ -z $(echo $dep | grep $i) ]
    then built $i ; if [ ! $? = 0 ]
      then sudo pacman -U $builtat
      else buildpkg $i
    fi
    else echo $i has already been built
  fi
done

if [ ! -z ${old_DEPs[@]} ] ; then 
  yes | sudo pacman -Rc ${old_DEPs[@]} ; fi

rm -rf /tmp/build/
echo Trying to scp
scp $localport /tmp/scp/* $remoteuser@$iplocal:/tmp/scp-receive ; if [ $? = 0 ] 
  then rm -rf /tmp/scp/* 
  else echo Something went wrong with scp from the remote machine side. Are you behind nat\? Built packages are in /tmp/scp .
fi
sudo -k
killall -9 makepkg
'

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

