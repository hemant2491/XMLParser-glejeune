#!/bin/sh

_init_xml() {
  local XML_FILE=${1}
  _TEMP_XML_FILE=$(mktemp)
  _XML_CONTINUE_READING=true
  cat $XML_FILE > $_TEMP_XML_FILE
  XML_PATH=""
  unset XML_ENTITY
  unset XML_CONTENT
  unset XML_TAG_TYPE
  unset XML_TAG_NAME
  unset XML_ATTRIBUTES
  unset XML_COMMENT
}

_close_xml() {
  [ -f $_TEMP_XML_FILE ] && rm -f $_TEMP_XML_FILE
}

_read_dom() {
  local XML_DATA
  local XML_TAG_NAME_FIRST_CHAR
  local XML_TAG_NAME_LENGTH
  local XML_TAG_NAME_WITHOUT_FIRST_CHAR
  local XML_LAST_CHAR_OF_ATTRIBUTES

  if [ "$XML_TAG_TYPE" = "OPENCLOSE" ]; then
    XML_PATH=$(echo $XML_PATH | sed -e "s/\/$XML_TAG_NAME$//")
  fi

  XML_DATA=$(awk 'BEGIN { RS = "<" ; FS = ">" ; OFS=">"; }
  { printf "" > F }
  NR == 1 { getline ; print $1,$2"x" }
  NR > 2 { printf "<"$0 >> F }' F=${_TEMP_XML_FILE} ${_TEMP_XML_FILE})
  if [ ! -s ${_TEMP_XML_FILE} ]; then
    _XML_CONTINUE_READING=false
  fi

  XML_ENTITY=$(echo $XML_DATA | cut -d\> -f1)
  XML_CONTENT=$(printf "$XML_DATA" | cut -d\> -f2-)
  XML_CONTENT=${XML_CONTENT%x}

  unset XML_COMMENT
  XML_TAG_TYPE="UNKNOW"
  XML_TAG_NAME=${XML_ENTITY%% *}
  XML_ATTRIBUTES=${XML_ENTITY#* }

  XML_TAG_NAME_FIRST_CHAR=$(echo $XML_TAG_NAME | awk  '{ string=substr($0, 1, 1); print string; }' )
  XML_TAG_NAME_LENGTH=${#XML_TAG_NAME}
  XML_TAG_NAME_WITHOUT_FIRST_CHAR=$(echo $XML_TAG_NAME | awk -v var=$XML_TAG_NAME_LENGTH '{ string=substr($0, 2, var - 1); print string; }' )
  if [ $XML_TAG_NAME_FIRST_CHAR = "!" ] ; then
    XML_TAG_TYPE="COMMENT"
    unset XML_ATTRIBUTES
    unset XML_TAG_NAME
    XML_COMMENT=$(echo "$XML_ENTITY" | sed -e 's/!-- \(.*\) --/\1/')
  else
    [ "$XML_ATTRIBUTES" = "$XML_TAG_NAME" ] && unset XML_ATTRIBUTES

    if [ "$XML_TAG_NAME_FIRST_CHAR" = "/" ]; then
      XML_PATH=$(echo $XML_PATH | sed -e "s/\/$XML_TAG_NAME_WITHOUT_FIRST_CHAR$//")
      XML_TAG_TYPE="CLOSE"
    elif [ "$XML_TAG_NAME_FIRST_CHAR" = "?" ]; then
      XML_TAG_TYPE="INSTRUCTION"
      XML_TAG_NAME=$XML_TAG_NAME_WITHOUT_FIRST_CHAR
    else
      XML_PATH=$XML_PATH"/"$XML_TAG_NAME
      XML_TAG_TYPE="OPEN"
    fi

    XML_LAST_CHAR_OF_ATTRIBUTES=$(echo "$XML_ATTRIBUTES"|awk '$0=$NF' FS=)
    if [ "$XML_ATTRIBUTES" != "" ] && [ "${XML_LAST_CHAR_OF_ATTRIBUTES}" = "/" ]; then
      XML_ATTRIBUTES=${XML_ATTRIBUTES%%?}
      XML_TAG_TYPE="OPENCLOSE"
    fi
  fi

  if [ "$XML_ATTRIBUTES" != "" ] ; then
    XML_ATTRIBUTES_FOR_PARSING=$(echo $XML_ATTRIBUTES | sed -e 's/\s*=\s*/=/g')
  fi
}

parse_xml() {
  local XML_FUNCTION=$1
  local XML_FILE=$2

  _init_xml ${XML_FILE}

  while ${_XML_CONTINUE_READING}; do
    _read_dom
    eval ${XML_FUNCTION}
  done

  _close_xml
}

get_attribute_value() {
  exec 3>&1 >/dev/tty
  local ATTRIBUT_NAME ATTRIBUT_VALUE
  ATTRIBUT_NAME=$1
  ATTRIBUT_NAME=$(echo $ATTRIBUT_NAME | tr "-" "_")

  if [ "$XML_ATTRIBUTES" != "" ] ; then
    XML_ATTRIBUTES_FOR_PARSING=$(echo $XML_ATTRIBUTES | tr "-" "_")
  else
    XML_ATTRIBUTES_FOR_PARSING=$XML_ATTRIBUTES
  fi
  eval local echo $XML_ATTRIBUTES_FOR_PARSING

  ATTRIBUT_VALUE=$(eval echo \$$ATTRIBUT_NAME)
  exec >&3
  echo "$ATTRIBUT_VALUE"
}

has_attribute() {
  local VALUE=$(get_attribute_value $1)
  if [ $VALUE ] ; then
    return 1
  else
    return 0
  fi
}

set_attribute_value() {
  local ATTRIBUT_NAME=$1
  local ATTRIBUT_NAME_VAR=$(echo $ATTRIBUT_NAME | tr "-" "_")
  local ATTRIBUT_VALUE=$2

  local CURRENT_ATTRIBUT_VALUE="$(get_attribute_value $ATTRIBUT_NAME)"

  XML_ATTRIBUTES=$(echo $XML_ATTRIBUTES | sed -e "s/${ATTRIBUT_NAME}=[\"' ]${CURRENT_ATTRIBUT_VALUE}[\"' ]/${ATTRIBUT_NAME}=\"${ATTRIBUT_VALUE}\"/")
}

print_entity() {
  if [ "$XML_TAG_TYPE" = "COMMENT" ] ; then
    printf "<!-- %s --" "$XML_COMMENT"
  elif [ "$XML_TAG_TYPE" = "INSTRUCTION" ] ; then
    printf "<?%s" "$XML_TAG_NAME"
    if [ "$XML_ATTRIBUTES" != "" ] ; then
      printf " %s" "$XML_ATTRIBUTES"
    fi
  elif [ "$XML_TAG_TYPE" = "OPENCLOSE" ] ; then
    printf "<%s" "$XML_TAG_NAME"
    if [ "$XML_ATTRIBUTES" != "" ] ; then
      printf " %s" "$XML_ATTRIBUTES"
    fi
    printf "/"
  elif [ "$XML_TAG_TYPE" = "CLOSE" ] ; then
    printf "<%s" "$XML_TAG_NAME"
  else
    printf "<%s" "$XML_TAG_NAME"
    if [ "$XML_ATTRIBUTES" != "" ] ; then
      printf " %s" "$XML_ATTRIBUTES"
    fi
  fi
  printf ">$XML_CONTENT"
}
