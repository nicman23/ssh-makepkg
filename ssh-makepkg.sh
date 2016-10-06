#! /bin/bash
port=22
declare -a PKG
declare -a DEP
declare -a BLD
editor=/bin/true

function ipset {
  if [ -z $ipnotset ]
  then export ip=$1
    export ipnotset=false
  else echo 'Ip was parsed multiple times'
    exit 2
  fi
}

function check_installed {
  pacman -Qi $1 &> /dev/null ||
    pacman -Qsq ^$1\$ &> /dev/null ||
      pacman -Si $1 &> /dev/null ||
        return 1
}

function missing_deps {
  local miss=$(cower --format='%D' -i $1 | cut -f1 -d">")
  for i in $miss
    do check_installed $i ||
    DEP=( $i ${DEP[@]/$i} )
  done
}

function deps_build {
  local miss=$(cower --format='%D %K %M' -i $1 | cut -f1 -d">")
  for i in $miss
    do BLD=( $i ${BLD[@]/$i} )
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
    ''            ) break ;;
    *@*.*.*       ) ipset $@ ; shift ;;
    *.*.*         ) ipset $@ ; shift ;;
    *.lan			    ) ping $1 -c1 &> /dev/null && ipset $@ ; shift ;;
    -p				    ) export port=$2 ; shift 2 ;;
    -h | --help	  ) echo "$help" ; exit 0 ;;
    -e | --edit   ) export editor=$EDITOR ; shift ;;
    */PKGBUILD    ) echo wip ; exit 4 ; shift ;;
    *             ) PKG=( $1 ${PKG[@]/$1} ) ; shift 1 ;;
  esac
done

if [ -z $ipnotset ] ; then echo 'No ip was set for the remote ssh server' ; exit 2 ; fi

if [ ! -e /tmp/scp-receive ] ; then mkdir /tmp/scp-receive ; fi

for i in ${PKG[@]} ; do
  missing_deps $i ; done

for i in ${PKG[@]} ; do
  deps_build $i ; done


ssh -t $ip $(echo '-p' $port) export "EDITOR=$editor" pkg="`echo '('${PKG[@]}')'`" dep="`echo '(' ${DEP[@]} ')'`" bld="`echo '(' ${BLD[@]} ')'`" '
PATH="/usr/local/bin:/usr/local/bin:/usr/local/sbin:/usr/local/bin:/usr/bin:/usr/bin/site_perl:/usr/bin/vendor_perl:/usr/bin/core_perl"' '

function check_installed {
  pacman -Qi $1 &> /dev/null ||
    pacman -Qsq ^$1\$ &> /dev/null ||
      pacman -Si $1 &> /dev/null ||
        return 1
}

sudo -v
sudo pacman -Syu

declare -a old_DEPs

function buildpkgdeps {
  cower -fd $1 ; cd $1
  if [ -e ~/.config/aur-hooks/$1.hook ]
    then bash ~/.config/aur-hooks/$1.hook
  fi
  $EDITOR PKGBUILD ; yes \  | makepkg -fsri
  cd /tmp/build ; rm -rf $1
}

function buildpkg {
  cower -fd $1 ; cd $1
  if [ -e ~/.config/aur-hooks/$1.hook ]
    then bash ~/.config/aur-hooks/$1.hook
  fi
  $EDITOR PKGBUILD ; yes \  | makepkg -fsr
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

[ ! -e /tmp/scp ] && mkdir /tmp/scp
[ ! -e /tmp/build ] && mkdir /tmp/build
cd /tmp/build

for i in $(echo ${bld[@]}) ; do
  if [ -z "$(echo ${pkg[@]} | grep $i)" ] || [ -z "$(echo ${dep[@]} | grep $i)" ]
    then check_installed $i ;  if [ $? = 1 ]
      then built $i ; if [ ! $? = 0 ]
        then sudo pacman -U $builtat
        else buildpkgdeps $i
      fi
      old_DEPs=( $i ${old_DEPs[@]/$i} )
    fi
  fi
done

export PKGDEST="/tmp/scp"

for i in $(echo ${dep[@]}) ; do
  built $i ; if [ ! $? = 0 ]
    then sudo pacman -U $builtat ; old_DEPs=( $i ${old_DEPs[@]/$i} )
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
  n|N|no  ) exit ;;
  * ) exit ;;
esac
