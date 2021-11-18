#!/bin/bash

COLOR_RED=`tput setaf 1`
COLOR_GREEN=`tput setaf 2`
COLOR_YELLOW=`tput setaf 3`
COLOR_BLUE=`tput setaf 4`
COLOR_MAGENTA=`tput setaf 5`
COLOR_CYAN=`tput setaf 6`
COLOR_RESET=`tput sgr0`

function echo_h1() {
  echo ""
  echo "${COLOR_YELLOW}================================================================================"
  echo "$1"
  echo "================================================================================${COLOR_RESET}"
}

function echo_h2() {
  echo ""
  echo "$1"
  echo "--------------------------------------------------------------------------------"
}

function echo_warning() {
  echo "${COLOR_RED}$1${COLOR_RESET}"
}

function echo_highlight() {
  echo "${COLOR_CYAN}$1${COLOR_RESET}"
}

#function to retrieve individual certificate
function getcert() {
    i=1
    selectCrt=$2
    echo "$1" | while read line; do
        if [[ $i == $selectCrt ]]; then
            echo $line
        fi
        if [[ "$line" == "-----END CERTIFICATE-----" ]]; then
            i=$((i+1))
        fi
    done
}

function fetchCertificates() {
    openssl s_client -servername $1 -connect $1:$2 -showcerts 2>&1 < /dev/null  | sed -ne '/BEGIN\ CERTIFICATE/,/END\ CERTIFICATE/p'
}

function showWorking() {
  # Usage: run any command in the background, capture it's PID
  #
  # somecommand >> /dev/null 2>&1 &
  # showWorking $!
  #
  PID=$1

  sp='/-\|'
  printf ' '
  while s=`ps -p $PID`; do
      printf '\b%.1s' "$sp"
      sp=${sp#?}${sp%???}
      sleep 0.1
  done
  printf '\b '
}
