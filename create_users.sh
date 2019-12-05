function create_users() {
  declare -A users
  users=(
    [alkazako-crtadmin]=52787588
    #[dpawar-crtadmin]=18c2b531-50a0-4ce9-95bb-2090db5feca1
    #[mjobanek-crtadmin]=18858c97-3bd4-43fe-9aa8-14ce22265119
    #[nvirani-crtadmin]=2be89467-f2f1-4e14-b1ae-3bf84c8cef52
    #[tkurian-crtadmin]=88b195e7-b064-41b7-8fb5-67d640c3703c
    #[xcoulon-crtadmin]=b82cedcb-1600-4d0a-a49c-0e149e626733
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