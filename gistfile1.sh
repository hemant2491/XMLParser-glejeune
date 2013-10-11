#!/bin/sh

init_xml() {
  XML_PATH=""
  XML_FIRST_READ=1
  unset XML_ENTITY 
  unset XML_CONTENT
  unset XML_TAG_TYPE 
  unset XML_TAG_NAME 
  unset XML_ATTRIBUTES
  unset XML_COMMENT
}

read_dom () {
  local IFS XML_DONE

  if [[ $XML_TAG_TYPE = OPENCLOSE ]]; then
    XML_PATH=$(echo $XML_PATH | sed -e "s/\/$XML_TAG_NAME$//")
  fi

  IFS=\>
  read -d \< XML_ENTITY XML_CONTENT
  XML_DONE=$?
  if [[ $XML_FIRST_READ = 1 ]] ; then
    XML_FIRST_READ=0
    read -d \< XML_ENTITY XML_CONTENT
    XML_DONE=$?
  fi

  unset XML_COMMENT
  XML_TAG_TYPE=UNKNOW
  XML_TAG_NAME=${XML_ENTITY%% *}
  XML_ATTRIBUTES=${XML_ENTITY#* }

  if [[ ${XML_TAG_NAME:0:1} = "!" ]] ; then
    XML_TAG_TYPE=COMMENT
    unset XML_ATTRIBUTES
    unset XML_TAG_NAME
    XML_COMMENT=$(echo "$XML_ENTITY" | sed -e 's/!-- \(.*\) --/\1/')
  else
    [ "$XML_ATTRIBUTES" = "$XML_TAG_NAME" ] && unset XML_ATTRIBUTES

    if [[ "${XML_TAG_NAME:0:1}" = "/" ]]; then
      XML_PATH=$(echo $XML_PATH | sed -e "s/\/${XML_TAG_NAME:1}$//")
      XML_TAG_TYPE=CLOSE
    elif [[ "${XML_TAG_NAME:0:1}" = "?" ]]; then
      XML_TAG_TYPE=INSTRUCTION
      XML_TAG_NAME=${XML_TAG_NAME:1}
      unset XML_CONTENT
    else
      XML_PATH=$XML_PATH"/"$XML_TAG_NAME
      XML_TAG_TYPE=OPEN
    fi

    if [[ $XML_ATTRIBUTES ]] && [[ ${XML_ATTRIBUTES##${XML_ATTRIBUTES%%?}} = "/" ]]; then
      XML_ATTRIBUTES=${XML_ATTRIBUTES%%?}
      XML_TAG_TYPE=OPENCLOSE
    fi
  fi

  if [[ $XML_ATTRIBUTES ]] ; then
    XML_ATTRIBUTES_FOR_PARSING=$(echo $XML_ATTRIBUTES | sed -e 's/\s*=\s*/=/g')
  fi

  return $XML_DONE
}

parse_xml() {
  XML_FUNCTION=$1
  XML_FILE=$2

  init_xml
  while true; do
    read_dom
    XML_DONE=$?
    eval ${XML_FUNCTION}
    if [[ $XML_DONE = 1 ]] ; then break; fi
  done < $XML_FILE
}

get_attribute_value() {
  exec 3>&1 >/dev/tty
  local ATTRIBUT_NAME ATTRIBUT_VALUE
  ATTRIBUT_NAME=$1
  ATTRIBUT_NAME=$(echo $ATTRIBUT_NAME | tr "-" "_")

  if [[ $XML_ATTRIBUTES ]] ; then
    XML_ATTRIBUTES_FOR_PARSING=$(echo $XML_ATTRIBUTES | tr "-" "_")
  else
    XML_ATTRIBUTES_FOR_PARSING=$XML_ATTRIBUTES
  fi
  eval local echo $XML_ATTRIBUTES_FOR_PARSING

  ATTRIBUT_VALUE=$(eval echo \$$ATTRIBUT_NAME)
  exec >&3-
  echo "$ATTRIBUT_VALUE"
}

has_attribute() {
  local VALUE=$(get_attribute_value $1)
  if [[ $VALUE ]] ; then
    return 1
  else
    return 0
  fi
}

set_attribute_value() {
  local ATTRIBUT_NAME=$1
  local ATTRIBUT_NAME_VAR=$(echo $ATTRIBUT_NAME | tr "-" "_")
  local ATTRIBUT_VALUE=$2
  
  if [[ $XML_ATTRIBUTES ]] ; then
    XML_ATTRIBUTES_FOR_PARSING=$(echo $XML_ATTRIBUTES | tr "-" "_")
  else
    XML_ATTRIBUTES_FOR_PARSING=$XML_ATTRIBUTES
  fi
  eval local echo $XML_ATTRIBUTES_FOR_PARSING

  local CURRENT_ATTRIBUT_VALUE=$(eval echo \$$ATTRIBUT_NAME_VAR)

  XML_ATTRIBUTES=$(echo $XML_ATTRIBUTES | sed -e "s/${ATTRIBUT_NAME}\s*=\s*[\"' ]${CURRENT_ATTRIBUT_VALUE}[\"' ]/${ATTRIBUT_NAME}=\"${ATTRIBUT_VALUE}\"/")
}

print_entity() {
  if [[ $XML_TAG_TYPE = COMMENT ]] ; then
    printf "<!-- %s --" "$XML_COMMENT"
  elif [[ $XML_TAG_TYPE = "INSTRUCTION" ]] ; then
    printf "<?%s" "$XML_TAG_NAME"
    if [[ $XML_ATTRIBUTES ]] ; then
      printf " %s" "$XML_ATTRIBUTES"
    fi
  elif [[ $XML_TAG_TYPE = "OPENCLOSE" ]] ; then
    printf "<%s" "$XML_TAG_NAME"
    if [[ $XML_ATTRIBUTES ]] ; then
      printf " %s" "$XML_ATTRIBUTES"
    fi
    printf "/"
  elif [[ $XML_TAG_TYPE = "CLOSE" ]] ; then
    printf "<%s/" "$XML_TAG_NAME"
  else
    printf "<%s" "$XML_TAG_NAME"
    if [[ $XML_ATTRIBUTES ]] ; then
      printf " %s" "$XML_ATTRIBUTES"
    fi
  fi
  printf ">%s" "$XML_CONTENT"
}