#!/bin/bash
#
#   SoftEther VPN client setup script for Raspberry Pi
#                              2020/04 Hideki Sakamoto
#
#     usage: sudo bash ./setup.sh [ -f config_file ]
#

#
_wdir=$(/bin/pwd)
_result=${_wdir}/result.txt
[ -e "$_result" ] && /bin/mv ${_result} ${_result}.bak

### functions ###
usage () {
  echo "Usage: $0 [-f config_file] -h"
}

abort () {
  [ -n "$1" ] && echo $1 | /usr/bin/tee -a $_result
  exit ${2:1}
}

#
msg () {
  local _opt=''
  [ "$1" = "-n" ] && _opt=$1 && shift
  eval echo $_opt \"\$$1\" | /usr/bin/tee -a $_result
}

# usage: ask message key [default [prompt]]
ask () {
  local _echo_opt=''
  [ "$1" = "-n" ] && _echo_opt=$1 && shift
  echo $_echo_opt "$1" | /usr/bin/tee -a $_result

  local _key=$2 _default=$3 _prompt=${4:-"${2}"} _val=''
  [ -n "$_default" -a "$_default" != "_blank" ] && _prompt="${_prompt}[$_default]?"
  [ "$_prompt" = "$2" ] && _prompt="${_prompt}?"
  while [ -z "$_val" ]
  do
    read -p "${_prompt} " _val
    [ -z "$_val" ] && _val="$_default"
  done
  [ "$_val" = "_blank" ] && _val=''
  [ -n "$_val" ] && echo "${_key}=\"$_val\"" >> $_result
  eval "${_key}=\"$_val\""
}

wait_enter () {
  local _d
  ask '' _d '_blank' "${_m_hit_enter:-[Hit Enter]}"
}

# usage: get_pwd key [ length ]
get_pwd () {
  _len=${2:-37}
  _chars='0123456789abcdefghijkmnpqrstuvwxyzABCDEFGHIJKLMNPQRSTUVWXYZ'
  eval $1=$(/bin/cat /dev/urandom | /usr/bin/tr -d -c $_chars | /usr/bin/fold -w $_len | /usr/bin/head -1)
}

### main ###
_locale="ja"

while getopts lf:h OPT
do
  case "$OPT" in
    f)
      _cf=$OPTARG
      [ -r $_cf ] || abort "No such file: $_cf"
      ;;
    h)
      usage
      exit
      ;;
    l)
      # XXX
      _locale=$OPTARG
      [ -r ${_wdir}/locale/${_locale}.txt ] || abort "No such locale: $1"
      ;;
  esac
done

. ${_wdir}/locale/${_locale}.txt

[ "$USER" != "root" ] && abort "$_m_no_root"

msg _m_start

# 設定の読み込み/入力
if [ -n "$_cf" ]; then
  . $_cf
fi
[ -z "$user_name" ]         && ask "$_m_ask_user_name" user_name
[ -z "$vpn_server" ]        && ask "$_m_ask_vpn_server" vpn_server
[ -z "$vpn_server_port" ]   && ask "$_m_ask_vpn_server_port" vpn_server_port "5555"
[ -z "$vpn_server_hub" ]    && ask "$_m_ask_vpn_server_hub" vpn_server_hub
[ -z "$vpn_default_route" ] && ask "$_m_ask_vpn_default_route" vpn_default_route "no"
[ -z "$vpn_device" ]        && ask "$_m_ask_vpn_device" vpn_device "tun0"
[ -z "$physical_devices" ]  && ask "$_m_ask_physical_devices" physical_devices "wlan0 eth0"
[ -z "$wol_mac" ]           && ask "$_m_ask_wol_mac" wol_mac "_blank"
if [ -n "$wol_mac" ]; then
  [ -z "$wol_ip" ]              && ask "$_m_ask_wol_ip" wol_ip
  [ -z "$remmina_remote_name" ] &&  ask "$_m_ask_remmina_remote_name" remmina_remote_name
  [ -z "$remmina_user" ]        && ask "$_m_ask_remmina_user" remmina_user
fi
[ -z "$ntp_server" ]        && ask "$_m_ask_ntp_servers" ntp_server "$_m_default_ntp_server"
[ -z "$ntp_fallback" ]      && ask "$_m_ask_ntp_fallback" ntp_fallback "$_m_default_ntp_fallback"

while [ "$vpn_connect_mode" != '1' -a "$vpn_connect_mode" != '2' -a "$vpn_connect_mode" != '3' ]
do
  ask "$_m_vpn_connect_mode" vpn_connect_mode '1'
done

[ -r ${_wdir}/locale/${_locale}_postconf.txt ] && . ${_wdir}/locale/${_locale}_postconf.txt

#ローカルアカウントの作成
/usr/sbin/useradd -m $user_name
/usr/sbin/usermod -G adm,dialout,cdrom,audio,video,plugdev,games,users,input,netdev,spi,i2c,gpio $user_name
/bin/cp -r ${_wdir}/files/setup_wlan* /home/${user_name}/
mkdir -p /home/${user_name}/.local/share/remmina
mkdir -p /home/${user_name}/.config/lxpanel/LXDE-pi/panels
/bin/chown -R ${user_name}:${user_name} /home/${user_name}
/bin/chmod -R 750 /home/${user_name}/setup_wlan
/bin/chmod -R 700 /home/${user_name}/.config
echo "$user_name ALL=(ALL) SETENV: ALL" > /etc/sudoers.d/020_${user_name}-vpnservice
echo "$user_name ALL=NOPASSWD:SETENV:/opt/vpnclient/service" >> /etc/sudoers.d/020_${user_name}-vpnservice
/bin/chown root:root /etc/sudoers.d/020_${user_name}-vpnservice
/bin/chmod 440 /etc/sudoers.d/020_${user_name}-vpnservice
ask "$_m_ask_automake_password" yn 'y' '(y/n)'
case "$yn" in
  [yY]*)
    get_pwd local_pwd 12
    echo "${user_name}:${local_pwd}" | /usr/sbin/chpasswd 
    ;;
  *)
    msg _m_set_password
    /usr/bin/passwd $user_name
esac

# ソフトのチェックとインストール
msg _m_check_soft_required
/usr/bin/apt-get update >/dev/null 2>&1

if ! /usr/bin/which wakeonlan >/dev/null 2>&1
then
  msg _m_install_wakeonlan
  apt-get install -y wakeonlan 2>&1 | /usr/bin/tee -a $_result
fi

if ! /usr/bin/which remmina >/dev/null 2>&1
then
  msg _m_install_remmina
  apt-get install -y remmina 2>&1 | /usr/bin/tee -a $_result
fi

if [ ! -d /opt/vpnclient ];then
  until /bin/ls ~/Downloads/softether-vpnclient-*-linux-arm_eabi-32bit.tar.gz 2>/dev/null
  do
    msg _m_no_softether
    wait_enter
    /usr/bin/chromium-browser --no-sandbox https://www.softether-download.com >/dev/null 2>&1
  done
  msg _m_install_softether
  /bin/tar xfC ~/Downloads/softether-vpnclient-*-linux-arm_eabi-32bit.tar.gz /opt/
  /bin/chown -R root /opt/vpnclient
  cd /opt/vpnclient
  make || abort "install SoftEther failed."
  /bin/chmod -R 700 /opt/vpnclient/vpnclient
  /bin/chmod -R 700 /opt/vpnclient/vpncmd
fi

## スクリプト類のインストール
/bin/sed -i 's/^\(autologin-user=\).*$/#\1/' /etc/lightdm/lightdm.conf
/usr/bin/install -b -o root -g root -m 0644 ${_wdir}/files/vpn_routing.enter /etc/dhcp/dhclient-enter-hooks.d/vpn_routing
/usr/bin/install -b -o root -g root -m 0644 ${_wdir}/files/vpn_routing.exit /etc/dhcp/dhclient-exit-hooks.d/vpn_routing
/usr/bin/install -b -o root -g root -m 0700 ${_wdir}/files/service /opt/vpnclient/service
/bin/sed "s/__V_SRV__/$vpn_server/; s/__VDR_YESNO__/$vpn_default_route/; s/__VDEV__/$vpn_device/; s/__PDEV__/$physical_devices/; s/__WOL_MAC__/$wol_mac/; s/__WOL_IP__/$wol_ip/" < ${_wdir}/files/service.conf.in > /opt/vpnclient/service.conf
/bin/chown root:root /opt/vpnclient/service.conf
/bin/chmod 700 /opt/vpnclient/service.conf
/bin/grep -v ^NTP /etc/systemd/timesyncd.conf | /bin/grep -v ^FallbackNTP > ${_wdir}/timesyncd.conf
echo "NTP=$ntp_server" >> ${_wdir}/timesyncd.conf
echo "FallbackNTP=$ntp_fallback" >> ${_wdir}/timesyncd.conf
/usr/bin/install -b -o root -g root -m 0644 ${_wdir}/timesyncd.conf /etc/systemd/timesyncd.conf
/bin/rm -f ${_wdir}/timesyncd.conf
/bin/rm -f /etc/ssh/ssh_host*
/usr/sbin/dpkg-reconfigure openssh-server

_remmina_pre_cmd=''
_remmina_post_cmd=''
if [ "$vpn_connect_mode" = '1' ]; then
  _remmina_pre_cmd="sudo /opt/vpnclient/service start"
  _remmina_post_cmd="sudo /opt/vpnclient/service stop"
fi
if [ -n "$remina_remote_name" ]; then
  /bin/sed "s/__REMOTE_NAME__/$remmina_remote_name/; s/__REMOTE_USER__/$remmina_user/; s#__PRE_COMMAND__#$_remmina_pre_cmd#; s#__POST_COMMAND__#$_remmina_post_cmd#; s/__REMOTE_SERVER__/$wol_ip/" < ${_wdir}/files/vpn_remote.remmina.in > /home/${user_name}/.local/share/remmina/vpn_remote.remmina
fi
/usr/bin/install -o ${user_name} -g ${user_name} -m 0644 ${_wdir}/files/panel /home/${user_name}/.config/lxpanel/LXDE-pi/panels/panel

if [ "$vpn_connect_mode" = '2' ]; then
  /usr/bin/install -b -o root -g root -m 0750 ${_wdir}/files/vpn-client.service /etc/systemd/system/
  /bin/systemctl enable vpn-client
fi

# sshd/vncの設定

ask "$_m_ask_enable_sshd" _yn 'n' '(y/N)'
case "$_yn" in
  [yY]*)
    /usr/bin/touch /boot/ssh
    ask "$_m_sshd_alert" _yn2 'y' '(Y/n)'
    case "$_yn2" in
      [nN]*)
        ;;
      *)
        /usr/bin/passwd pi
        ;;
    esac
    ;;
esac

ask "$_m_ask_enable_vnc" _yn 'n' '(y/N)'
case "$_yn" in
  [yY]*)
    msg _m_vnc_note
    wait_enter
    /usr/bin/lxterminal -e 'raspi-config'
    msg _m_vnc_note2
    wait_enter
    ;;
esac

# VPNの設定

## SoftEther VPN client
/opt/vpnclient/vpnclient start 2>&1 | /usr/bin/tee -a $_result
sleep 1

get_pwd vpn_pass

/bin/cat <<EOT > ${_wdir}/setupclient.txt
RemoteDisable
NicCreate $vpn_device
AccountCreate WFH_PI /SERVER:${vpn_server}:$vpn_server_port /HUB:$vpn_server_hub /USERNAME:$user_name /NICNAME:$vpn_device
AccountPasswordSet WFH_PI /PASSWORD:$vpn_pass /TYPE:standard
AccountStartupSet WFH_PI
EOT
/opt/vpnclient/vpncmd localhost /CLIENT /IN:${_wdir}/setupclient.txt /OUT:${_wdir}/setupclient.log
if [ $? -ne 0 ]; then
  msg _m_setup_client_failed
else
  /bin/rm -f ${_wdir}/setupclient.txt
fi
/opt/vpnclient/vpncmd localhost /CLIENT /CMD NicList | /usr/bin/tee ${_wdir}/niclist.txt
vpn_mac=$(/bin/cat ${_wdir}/niclist.txt | /bin/grep -A 3 $vpn_device | /bin/grep ^MAC | /usr/bin/awk -F\| '{print $2}')
/bin/rm -f ${_wdir}/niclist.txt

/opt/vpnclient/vpnclient stop 2>&1 | /usr/bin/tee -a $_result

## SoftEther VPN server
/bin/cat <<EOT > ${_wdir}/createuser.txt
Hub $vpn_server_hub
UserCreate $user_name /GROUP:none /REALNAME:none /NOTE:none
UserPasswordSet $user_name /PASSWORD:$vpn_pass
EOT
chmod 600 ${_wdir}/createuser.txt
ask "$_m_ask_setup_server" yn "y" "(Y/n)"
case "$yn" in
  [yY]*)
    /opt/vpnclient/vpncmd ${vpn_server}:$vpn_server_port /SERVER /IN:${_wdir}/createuser.txt /OUT:${_wdir}/createuser.log
    if [ $? -ne 0 ]; then
      msg _m_setup_vpn_server_failed
    else
      /bin/rm -f ${_wdir}/createuser.txt
    fi
    ;;
  *)
    msg _m_setup_vpn_server_note
esac

/bin/cat <<EOT > ${_wdir}/setup.config
vpn_server="$vpn_server"
vpn_server_port="$vpn_server_port"
vpn_server_hub="$vpn_server_hub"
vpn_default_route="$vpn_default_route"
vpn_device="$vpn_device"
physical_devices="$physical_devices"
remmina_remote_name="$remmina_remote_name"
vpn_connect_mode="$vpn_connect_mode"
ntp_server="$ntp_server"
ntp_fallback="$ntp_fallback"
EOT
msg _m_setup_config_note

msg _m_vpn_info
msg -n _m_vpn_mac
echo $vpn_mac | /usr/bin/tee -a $_result

_note=${_wdir}/user_note.txt

msg _m_user_note

msg _m_pi_mac_info | /usr/bin/tee $_note
msg -n _m_pi_wire | /usr/bin/tee -a $_note
/sbin/ifconfig eth0 | /bin/grep ether | /usr/bin/awk '{print $2}' | /usr/bin/tee -a $_note $_result
msg -n _m_pi_wireless | /usr/bin/tee -a $_note
/sbin/ifconfig wlan0 | /bin/grep ether | /usr/bin/awk '{print $2}' | /usr/bin/tee -a $_note $_result

msg _m_local_user_info | /usr/bin/tee -a $_note
msg -n _m_account | /usr/bin/tee -a $_note
echo $user_name | /usr/bin/tee -a $_note $_result
msg -n _m_password | /usr/bin/tee -a $_note
if [ -n "$local_pwd" ]; then
  echo $local_pwd | /usr/bin/tee -a $_note $_result
else
  msg _m_manual_input | /usr/bin/tee -a $_note
fi

msg _m_end
