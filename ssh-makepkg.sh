#! /bin/bash
port=22
declare -a PKG
declare -a DEP
declare -a TEMP
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
  pacman -Qi $1 &> /dev/null ; if [ ! $? = 0 ]
    then pacman -Qsq ^$1\$ &> /dev/null ; if [ ! $? = 0 ]
      then pacman -Si $1 &> /dev/null ; if [ ! $? = 0 ]
        then DEP=( $1 ${DEP[@]/%$1} ) && return 1
      fi
    fi
  fi
}

function deps_calc {
  if [ "$(echo ${TEMP[@]} | grep $@)" ]
    then break 1
  fi
  temp=$(cower --format='%D %K %M' -i $@)
  for i in $temp
    do while true
      do temp2=$(echo $i | cut -f1 -d">")
      TEMP=( $temp2 ${TEMP[@]} )
      check_installed $temp2
        if [ "$?" = 1 ]
          then deps_calc $temp2
          else break 1
        fi
      done
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
    *             ) PKG=( $1 ${PKG[@]/%$1} ) ; shift 1 ;;
  esac
done

if [ -z $ipnotset ] ; then echo 'No ip was set for the remote ssh server' ; exit 2 ; fi

if [ ! -e /tmp/scp-receive ] ; then mkdir /tmp/scp-receive ; fi

for i in ${PKG[@]} ; do
  deps_calc $i ; done



ssh -t $ip $(echo '-p' $port) export "EDITOR=$editor" "
export pkg=\"$(echo ${PKG[@]})\" " "
export dep=\"$(echo ${DEP[@]})\" " '
PATH="/usr/local/bin:/usr/local/bin:/usr/local/sbin:/usr/local/bin:/usr/bin:/usr/bin/site_perl:/usr/bin/vendor_perl:/usr/bin/core_perl"' '

declare -a old_DEPs
declare -a DEP
declare -a PKG
export PKGDEST="/tmp/scp"

for i in $dep $pkg
  do PKG=( ${PKG[@]} $i )
done

function check_installed {
  pacman -Qi $1 &> /dev/null ; if [ ! $? = 0 ]
    then pacman -Qsq ^$1\$ &> /dev/null ; if [ ! $? = 0 ]
      then pacman -Si $1 &> /dev/null ; if [ ! $? = 0 ]
        then DEP=( $1 ${DEP[@]/%$1} ) && return 1
      fi
    fi
  fi
}

function deps_calc {
  if [ "$(echo ${TEMP[@]} | grep $@)" ]
    then break 1
  fi
  temp=$(cower --format='%D %K %M' -i $@)
  for i in $temp
    do while true
      do temp2=$(echo $i | cut -f1 -d">")
      TEMP=( $temp2 ${TEMP[@]} )
      check_installed $temp2
        if [ "$?" = 1 ]
          then deps_calc $temp2
          else break 1
        fi
      done
  done
}

function Build_deps {
  cower -fd $1 ; cd $1
  if [ -e ~/.config/aur-hooks/$1.hook ]
    then bash ~/.config/aur-hooks/$1.hook
  fi
  $EDITOR PKGBUILD ; yes \  | makepkg -fsri
  old_DEPs=( $1 ${old_DEPs[@]} )
}

function Build {
  cower -fd $1 ; cd $1
  if [ -e ~/.config/aur-hooks/$1.hook ]
    then bash ~/.config/aur-hooks/$1.hook
  fi
  $EDITOR PKGBUILD ; yes \  | makepkg -fsr
}

sudo -v
sudo pacman -Syu

[ ! -e /tmp/scp ] && mkdir /tmp/scp
[ ! -e /tmp/build ] && mkdir /tmp/build
cd /tmp/build

for i in ${PKG[@]}
  do deps_calc $i
done

for i in ${DEP[@]}
 do Build_deps $i
 PKG=( ${PKG[@]/%$i} )
done

for i in ${PKG[@]} ; do
  Build $i
done

if [ ! -z "${old_DEPs[@]}" ] ; then
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
