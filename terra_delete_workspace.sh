#!/usr/bin/env bash

HOST=$(echo "$1" | tr '[:upper:]' '[:lower:]')
MULTISELECT=0
cur=0
WORK_DIR="" # !!! set it before use
BASE_DIR=""
AWS_DIR=""
GCP_DIR=""
TERRA=terraform
declare -a ws=()
declare -a arrToDelete=()

if [[ "$2" == "-m" ]]; then
  MULTISELECT=1
fi

function normalize_before_exit() {
  # set cursor visible, colorls to default && exit
  tput sgr0 && tput cnorm && exit 1
}

trap normalize_before_exit SIGINT

function help() {
  tput setaf 3
  echo "This script allow to destroy and delete workspace(s) from provided hosting"
  echo "Usage: bash $0 {hosting} (gcp | aws) for single workspace deletion"
  echo " bash $0 {hosting} (gcp | aws) -m for multiple workspace deletion"
  echo "use spacebar for multiple selection mode to mark workspaces that should be deleted"
  echo "Required bash version >= 4"
  echo "see https://itnext.io/upgrading-bash-on-macos-7138bd1066ba"
  echo -e "Your bash version is:\n\n$(bash --version)"
  tput sgr0
  exit 0
}

function defineBaseDirs() {
  if [[ -z "$BASE_DIR" ]]; then
    BASE_DIR="$(find ~ -type d -name '$WORK_DIR' 2>/dev/null &)"
    echo "Your base dir has been found at $(tput setaf 3) $BASE_DIR"
    tput sgr0
  fi
  AWS_DIR="$BASE_DIR/terraform/aws"
  GCP_DIR="$BASE_DIR/terraform/gcp"
}

# Draws initial menu with available workspaces
function draw_menu() {
  for i in "${ws[@]}"; do
    if [[ ${ws[$cur]} == $i ]]; then
      tput setaf 2 # Set foreground color Green
      if [[ $MULTISELECT -eq 1 ]] && [[ $(echo "${arrToDelete[@]}" | grep "$i") ]]; then
        echo " > [x] $i"
      else
        echo " > [] $i "
      fi
      tput sgr0 # Turn off all attributes
    else
      if [[ $MULTISELECT -eq 1 ]] && [[ $(echo "${arrToDelete[@]}" | grep "$i") ]]; then
        echo " [x]   $i"
      else
        echo " []   $i "
      fi
    fi
  done
}

function clear_menu() {
  for i in "${ws[@]}"; do
    tput cuu1 # Move the cursor up 1 line
  done
  tput ed # Clear from the cursor to the end of the screen
}

function start_menu() {
  tput civis # make cursor invisible
  draw_menu
  # read 1 char (not delimiter), silent
  while IFS= read -sn1 key; do
    # Check for enter/space
    if [[ "$key" == "" ]]; then break; fi

    # catch multi-char special key sequences
    read -sn 1 -t 0.0001 k1
    read -sn 1 -t 0.0001 k2
    read -sn 1 -t 0.0001 k3
    key+=${k1}${k2}${k3}

    case "$key" in
    # cursor up, left: previous item
    $'\e[A' | $'\e0A' | $'\e[D' | $'\e0D') ((cur > 0)) && ((cur--)) ;;
      # cursor down, right: next item
    $'\e[B' | $'\e0B' | $'\e[C' | $'\e0C') ((cur < ${#ws[@]} - 1)) && ((cur++)) ;;
    $'m' | $'M')
      if [[ $MULTISELECT -eq 0 ]]; then
        MULTISELECT=1
      elif [[ $MULTISELECT -eq 1 ]]; then
        MULTISELECT=0
      fi
      ;;
    $' ')
    if [[ $MULTISELECT -eq 1 ]]; then
      if ! [[ $(echo "${arrToDelete[@]}" | grep "${ws[cur]}") ]]; then
        # add element to arrToDelete if it's not there
        arrToDelete+=("${ws[cur]}")
      else
        # remove element from arrToDelete
        arrToDelete=("${arrToDelete[@]/${ws[cur]}}")
      fi
    fi
    ;;
      # q: quit
    q) echo "Aborted." && exit 1 ;;
    esac
    # Redraw menu
    clear_menu
    draw_menu
  done
  tput cnorm # make cursor normal
}

# actually destroys and deletes workspace
# $1 - workspace that should be deleted
deleteWorkspace() {
  local workspace=$1

  echo "Going to delete $workspace from $(basename "$(pwd)")"
  $TERRA workspace select "$workspace" && $TERRA destroy -auto-approve && $TERRA workspace select default && $TERRA workspace delete "$workspace" && $TERRA workspace list || echo -e "\n$(tput setaf 1) $workspace is NOT deleted, check stdout to see what's wrong $(tput sgr0)"
  exit 0
}

# prepares data for deletion
# $1 path to provider directory { $AWS_DIR | $GCP_DIR }
function deleteFromProwider() {
  echo -e "\nChanging working dir to $1\n"
  cd "$1"

  ws=($($TERRA workspace list | tail -n +2))

  if [[ ${#ws[@]} -eq 0 ]]; then
    echo "There is no active workspaces. Script will finish execution."
    exit 0
  fi

  start_menu
  # delete workspaces in loop from arrToDelete
  if [[ $MULTISELECT -eq 1 ]] && [[ ${#arrToDelete[@]} -gt 0 ]]; then
    read -rp "Workspaces $(tput bold) $(tput setaf 3) ${arrToDelete[*]} $(tput sgr0) will be deleted. Correct? (y/n): " approve
    if [[ "$(echo "$approve" | tr '[:upper:]' '[:lower:]')" == "y" ]]; then
      for workspace in "${arrToDelete[@]}"; do
        deleteWorkspace "$workspace"
      done
    else
      echo "Delete operation aborted"
      exit 1
    fi
  else # delete one selected workspace
    local wsToDelete=${ws[$cur]}
    read -rp "Workspace $(tput bold) $(tput setaf 3) $wsToDelete $(tput sgr0) will be deleted. Correct? (y/n): " approve
    if [[ "$(echo "$approve" | tr '[:upper:]' '[:lower:]')" == "y" ]]; then
      deleteWorkspace "$wsToDelete"
    else
      echo "Delete operation aborted"
      exit 1
    fi
  fi
  exit 0
}

case "$HOST" in
"-h" | "--help")
  help
  ;;
"aws")
  defineBaseDirs
  deleteFromProwider "$AWS_DIR"
  ;;
"gcp")
  defineBaseDirs
  deleteFromProwider "$GCP_DIR"
  ;;
*)
  echo -e "Wrong arguments\n"
  help
  ;;
esac
