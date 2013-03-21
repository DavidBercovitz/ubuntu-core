#!/bin/bash

# This script attempts to download the release image
# for a particular Ubuntu Core distribution and 
# architecture. 
#
# It is strongly advised to run the script in the root folder
# where you want your Ubuntu Core filesystem to be extracted to.
#
# Parameters:
#             1 - Is the Ubuntu core distribution name 
#                 e.g.: oneiric, precise, etc...
#             2 - Is the Ubuntu core architecture name
#                 e.g.: armel, or armhf (precise onwards only).

function abort()
{
  echo "Aborting..."
  exit 1
}

# First verify the script is run with sudo
# privileges.
if [ $(id -u) -ne 0 ]; then
  echo "You don't have sufficient privileges to run this script."
  abort
fi

# Verify parameters are set
if [ -z "$1" ] || [ -z "$2" ]; then
 echo "Please specify a distribution name in 1st parameter."
 echo "......... and an architecture name in 2nd parameter."
 abort
else
  DISTRIB="$1"
  ARMARCH="$2"
fi

distros=([1]=oneiric [2]=precise)
archis=([1]=armel [2]=armhf)

# Validate parameters
success_distros=false
success_archis=false
for element in $(seq 1 ${#distros[@]})
do
  if [ "${distros[$element]}" = "$DISTRIB" ]; then
    success_distros="true"
  fi  
done
for element in $(seq 1 ${#archis[@]})
do
  if [ "${archis[$element]}" = "$ARMARCH" ]; then
    success_archis="true"
  fi  
done
if [ "$success_distros" = "false" ]; then
  echo "Invalid distribution specified in parameter one!"
  abort
fi
if [ "$success_archis" = "false" ]; then
   echo "Invalid architecture specified in parameter two!"
   abort
fi

current_path=`pwd`

# Verify path where script is executed
if [ "$current_path" = "/" ]; then
  echo "Script does not allow to run in /"
  abort
fi

while true; do
  read -p "Do you wish to run this script in $current_path ?" yn
  case $yn in
    [Yy]* ) break;;
    [Nn]* ) abort;;
    * ) echo "Please answer yes or no.";;
  esac
done

# DISTNUM needs an array or something for future versions
# Today only oneiric and precise are handled.
# Hoping Canonical will continue with the precise naming
# scheme too...
DISTNUM="12.04.1"

# if an extracted filesystem is already there, wipe it out!
if [ -d "usr" ] && [ -d "etc" ]; then
  echo "An existing filesystem seems to be already present."
  while true; do
    read -p "Do you wish to wipe out everything in $current_path ?" yn
    case $yn in
      [Yy]* ) break;;
      [Nn]* ) abort;;
      * ) echo "Please answer yes or no.";;
    esac
  done
  
  echo "Cleaning up previous core filesystem..."
  rm -rf *
fi

# Verify 'wget' is installed
hash wget 2>&- || { echo >&2 "Script requires wget utility but it's not installed."; abort; }
# Verify 'head' is installed
hash head >&- || { echo >&2 "Script requires head utility but it's not installed."; abort; }
# Verify 'grep' is installed
hash grep 2>&- || { echo >&2 "Script requires grep utility but it's not installed."; abort; }

# Attempt to download the requested ubuntu core image
# If it doesn't exist, downloads the current daily image
# for the particular distribution and architecture. If not
# available, just fails.

if [ "$DISTRIB" = "oneiric" ]; then
  DISTNUM="11.10"
fi
core_image="ubuntu-core-$DISTNUM-core-$ARMARCH.tar.gz"

core_path="http://cdimage.ubuntu.com/ubuntu-core/releases/$DISTNUM/release"

echo "Trying to download $core_path/$core_image ..."
wget -q -O "$core_image" "$core_path"/"$core_image"
if [ $? -ne 0 ]; then
  echo "Requested $DISTRIB distribution for architecture $ARMARCH doesn't exist. Trying daily image..."
  core_path="http://cdimage.ubuntu.com/ubuntu-core/daily/current"
  core_image="$DISTRIB-core-$ARMARCH.tar.gz"
  echo "Trying to download $core_path/$core_image ..."
  wget -q -O "$core_image" "$core_path"/"$core_image"
  if [ $? -ne 0 ]; then
    echo "Failed to find any Ubuntu Core image for $DISTRIB distribution on $ARMARCH !!!"
    abort
  fi
fi
echo "Successfully downloaded $core_image"

# Extracting the Ubuntu Core filesystem
# in the folder where this script is run.
if [ -f "$core_image" ]; then
  echo "Extracting $core_image filesystem in $current_path"
  tar xfz "$core_image"

  # Don't keep the tarball image.
  rm "$core_image"
fi

echo "Setting up the Ubuntu Core Image for TI network..."
##
## Create a serial console on the UART.
##
echo "Setting up serial console on UART..."
sh -c "cat > etc/init/serial-auto-detect-console.conf << EOF 
# serial-auto-detect-console - starts getty on serial console
#
# This service starts a getty on the serial port given in the console kernel argument.
#

start on runlevel [23]
stop on runlevel [!23]

respawn

exec /bin/sh /bin/serial-console
EOF
"

sh -c 'cat >bin/serial-console << EOF
for arg in \$(cat /proc/cmdline)
do
    case \$arg in
        console=*)
            tty=\${arg#console=}
            tty=\${tty#/dev/}
 
            case \$tty in
                tty[a-zA-Z]* )
                    PORT=\${tty%%,*}
 
                    # check for service which do something on this port
                    if [ -f /etc/init/\$PORT.conf ];then continue;fi 
 
                    tmp=\${tty##\$PORT,}
                    SPEED=\${tmp%%n*}
                    BITS=\${tmp##\${SPEED}n}
 
                    # 8bit serial is default
                    [ -z \$BITS ] && BITS=8
                    [ 8 -eq \$BITS ] && GETTY_ARGS="\$GETTY_ARGS -8 "
 
                    [ -z \$SPEED ] && SPEED="115200,57600,38400,19200,9600"
 
                    GETTY_ARGS="\$GETTY_ARGS \$SPEED \$PORT"
                    exec /sbin/getty \$GETTY_ARGS
            esac
    esac
done
EOF
'

chmod a+x bin/serial-console

#
# Remove root password has it is not known anyway
# This is recommended to change it at first boot
# as well as create a new user.
#
echo "First user is root with no password..."
sh -c "sed -i 's/root:\*/root:/' etc/shadow"

#
# Configures the network to run inside
# your premises. Gathering information
# from your PC.
#
echo "Setting up the network for dhcp..."
sh -c "cat >etc/network/interfaces << EOF
auto lo
iface lo inet loopback
auto eth0
iface eth0 inet dhcp
EOF
"

echo "Gathering network information from your PC..."
cat /etc/resolv.conf | grep -v "#" >etc/resolv.conf

echo "http_proxy=\"$http_proxy\"" >>etc/environment
echo "https_proxy=\"$https_proxy\"" >>etc/environment
echo "ftp_proxy=\"$ftp_proxy\"" >>etc/environment
echo "no_proxy=\"$no_proxy\"" >>etc/environment

# Trying to look for a local mirror server
# Not sure this will work for everyone...
#
# grep -e '^deb\{1,\}.[^-]*ubuntu.[^-]*main' 
# => will search for lines starting with "deb" but not "deb-" like in "deb-src"
#                followed by "ubuntu" string in it but not "ubuntu-" like in "ubuntu-updates"
#                followed by "main" string in it too.
#
# head -1
# => will just display the first result
#
# grep -Po '^.*?\K(?<=http\:\/\/).*?(?=\/)'
# => will extract the substring surrounded by the 2 main strings "http://" and "/"
#
mirror_server=`cat /etc/apt/sources.list | grep -e '^deb\{1,\}.[^-]*ubuntu.[^-]*main' | head -1 | grep -Po '^.*?\K(?<=http\:\/\/).*?(?=\/)'`

archive_server=""
if [ -z "$mirror_server" ]; then
  is_local=`echo $mirror_server | grep 'ubuntu\.com'`
  if [ $is_local -eq 0 ]; then
    archive_server="/$mirror_server/distrib/"$ARMARCH"/linux/ubuntu/mirror"
  fi
fi

sh -c "echo 'deb http:/$archive_server/ports.ubuntu.com/ubuntu-ports/ "$DISTRIB" main universe multiverse restricted' > etc/apt/sources.list"
sh -c "echo 'deb-src http:/$archive_server/ports.ubuntu.com/ubuntu-ports/ "$DISTRIB" main universe multiverse restricted' >> etc/apt/sources.list"
sh -c "echo 'deb http:/$archive_server/ports.ubuntu.com/ubuntu-ports/ "$DISTRIB"-security main universe multiverse restricted' >> etc/apt/sources.list"
sh -c "echo 'deb-src http:/$archive_server/ports.ubuntu.com/ubuntu-ports/ "$DISTRIB"-security main universe multiverse restricted' >> etc/apt/sources.list"
sh -c "echo 'deb http:/$archive_server/ports.ubuntu.com/ubuntu-ports/ "$DISTRIB"-updates main universe multiverse restricted' >> etc/apt/sources.list"
sh -c "echo 'deb-src http:/$archive_server/ports.ubuntu.com/ubuntu-ports/ "$DISTRIB"-updates main universe multiverse restricted' >> etc/apt/sources.list"

echo "Congratulation, you are done!"
