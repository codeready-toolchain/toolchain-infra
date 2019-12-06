#!/usr/bin/env bash

function create_users() {
  declare -A users
  users=(
    [alkazako-crtadmin]=52787588
    [mjobanek-crtadmin]=52791559
    [xcoulon-crtadmin]=52753083
    #[nvirani-crtadmin]=
    #[tkurian-crtadmin]=
  )
  USERS=""
  for i in "${!users[@]}"; do
    USER_NAME=$i
    USER_ID_FROM_SUB_CLAIM=${users[$i]}
    USER_NAME=$USER_NAME USER_ID_FROM_SUB_CLAIM=$USER_ID_FROM_SUB_CLAIM envsubst <./config/oauth/user.yaml | oc apply -f -
    USERS+="$USER_NAME "
  done
  USERS="${USERS%%*( )}"

  # Add this users under crt-admins groups
  oc adm groups add-users crt-admins $USERS
}

create_users