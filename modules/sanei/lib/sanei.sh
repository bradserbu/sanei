#!/bin/bash

# load argument loading
__IMPORT__BASE_PATH="$SCRIPT_DIR/vendor/bash-modules/main/bash-modules/src/bash-modules"
source $SCRIPT_DIR/vendor/bash-modules/main/bash-modules/src/import.sh arguments log
parse_arguments "-v|--verbose)VERBOSE;I" "-r|--reinstall)REINSTALL;B" "--skip-apt)SKIPAPT;B" "-s|--silent)SILENT;B" -- "${@:+$@}"
# parse_arguments "-n|--name)NAME;S" -- "$@" || {
#   error "Cannot parse command line."
#   exit 1
# }
# info "Hello, $NAME!"

# echo "Arguments count: ${#ARGUMENTS[@]}."
# echo "Arguments: ${ARGUMENTS[0]:+${ARGUMENTS[@]}}."

# load configuration and save to a variable
if [[ -z $CONFIG ]]; then
    ( set -o posix ; set ) >/tmp/variables.before
    for file in $SCRIPT_DIR/config/* ; do
        if [ -f "$file" ] ; then
            if [[ $VERBOSE -gt 4 ]]; then info "Loading config: $file"; fi
            source "$file"
        fi
    done

    ## load shared overrides
    # for file in $SCRIPT_DIR/.config-shared/* ; do
    #   if [ -f "$file" ] ; then
    #     if [[ $VERBOSE ]]; then echo "Loading shared config: $file"; fi
    #     source "$file"
    #   fi
    # done

    # load local overrides
    for file in /opt/sanei/.config/* ; do
        if [ -f "$file" ] ; then
            if [[ $VERBOSE -gt 4 ]]; then info "Loading local config: $file"; fi
            source "$file"
        fi
    done

    unset file
    ( set -o posix ; set ) >/tmp/variables.after

    CONFIG=$(comm --nocheck-order -13 /tmp/variables.before /tmp/variables.after)
    rm /tmp/variables.before /tmp/variables.after

    # make it an assoc array
    declare -A ConfigArr
    while IFS= read -r ConfigLine; do
        IFS='=' read -ra ThisConfig <<< "$ConfigLine"
        ThisConfigTrim=${ThisConfig[1]#"'"}
        ThisConfigTrim=${ThisConfigTrim%"'"}
        ThisConfigTrim=$(echo $ThisConfigTrim | sed "s/'\\\'//g") # unescape
        ConfigArr["${ThisConfig[0]}"]="$ThisConfigTrim"
    done <<< "$CONFIG"

    # finally add the variable added at the beginning
    ConfigArr["SCRIPT_DIR"]="${SCRIPT_DIR}"
fi

# globals
space="|    |    |    |    |    |"

export COLOR_NC='\e[0m' # No Color
export COLOR_WHITE='\e[1;37m'
export COLOR_BLACK='\e[0;30m'
export COLOR_BLUE='\e[0;34m'
export COLOR_LIGHT_BLUE='\e[1;34m'
export COLOR_GREEN='\e[0;32m'
export COLOR_LIGHT_GREEN='\e[1;32m'
export COLOR_CYAN='\e[0;36m'
export COLOR_LIGHT_CYAN='\e[1;36m'
export COLOR_RED='\e[0;31m'
export COLOR_LIGHT_RED='\e[1;31m'
export COLOR_PURPLE='\e[0;35m'
export COLOR_LIGHT_PURPLE='\e[1;35m'
export COLOR_BROWN='\e[0;33m'
export COLOR_YELLOW='\e[1;33m'
export COLOR_GRAY='\e[0;30m'
export COLOR_LIGHT_GRAY='\e[0;37m'

LIGHTGREEN=$'\033[1;32m'
LIGHTBLUE=$'\033[1;34m'
LIGHTRED=$'\033[1;31m'
GREEN=$'\033[0;32m'
BLUE=$'\033[0;34m'
RED=$'\033[0;31m'
WHITE=$'\033[0;37m'
RESET=$'\033[0;00m'
PADDING_SIZE=5

generate_help(){
    # http://www.thelinuxdaily.com/2012/09/self-documenting-scripts/
    pfx="$1"
    file="$2"
    if [ "$pfx" = "" ]; then pfx='##' ; fi
    grep "^$pfx" "$file" | sed -e "s/^$pfx//" 1>&2 # -e "s/_FILE_/$me/"
}
asksure(){
    local text=$1
    echo -n "$text (Y/N)? "
    while read -r -n 1 answer; do
      if [[ $answer = [YyNn] ]]; then
        [[ $answer = [Yy] ]] && retval=0
        [[ $answer = [Nn] ]] && retval=1
        break
      fi
    done
    echo # just a final linefeed, optics...
    return $retval
}
askbreak(){
    if [[ $SILENT -eq true ]]; then
        local text=$1
        if ! asksure "$text"; then
            exit 1
        fi
    else
        echo "$text (Y)."
    fi
}
print_config(){
    local index
    for index in ${!ConfigArr[*]}
    do
        echo "${LIGHTBLUE}$index${RESET}: ${WHITE}${ConfigArr["$index"]}${RESET}"
    done
}
is_installed(){
    local what=$1
    if [[ -e "$TEMPLATE_ROOT$SANEI_DIR/.install.$what" ]]; then
	    return 0
    fi
    return 1
}
set_installed(){
    local what=$1
    local norun=$2
    local noinfo=$3
    mkdir -p "$TEMPLATE_ROOT$SANEI_DIR"
    touch "$TEMPLATE_ROOT$SANEI_DIR/.install.$what"
    if [[ -z $norun ]]; then
        sanei_update "$what"
    fi
    if [[ -z $noinfo ]]; then
        info "Set as installed: $what"
    fi
}
rm_installed(){
    local what=$1
    if [[ -f $TEMPLATE_ROOT$SANEI_DIR/.install.$what ]]; then
        rm $TEMPLATE_ROOT$SANEI_DIR/.install.$what
    fi
}
store_memory_config(){
    local var=$1
    local def=$2
    export $var=$def
    ConfigArr["${var}"]="${def}"
}
store_config_file(){
    local var=$1
    local def=$2
    local path=$3
    mkdir -p $SCRIPT_DIR/config
    echo "$var=\"$def\"" > "${path}${var}"
    chmod 700 "${path}${var}"
    store_memory_config "$var" "$def"
}
store_local_config(){
    local var=$1
    local def=$2
    mkdir -p $TEMPLATE_ROOT$SANEI_DIR/.config
    store_config_file "$var" "$def" "$TEMPLATE_ROOT$SANEI_DIR/.config/"
}
store_shared_config(){
    local var=$1
    local def=$2
    mkdir -p $SCRIPT_DIR/config
    store_config_file "$var" "$def" "$SCRIPT_DIR/config/50-"
}
apt_install(){
    if [[ -z $SKIPAPT || $SKIPAPT -ne true ]]; then
        local packages="$1"
        local ppa="$2"
        local norecommends="$3"
        if [[ ! -z $ppa ]]; then
            add-apt-repository $(add_silent_opt) "$ppa"
            apt-get update
        fi
        if $norecommends; then
            norecommends="--no-install-recommends"
        fi
        if ! apt-get $(add_silent_opt) "$norecommends" install $packages; then
            return 1
        fi
    fi
}
is_apt_installed(){
    local package="$1"
    if (dpkg -s "$package" &>/dev/null); then
        return 0
    else
        return 1
    fi
}
create_directory_structure(){
    local filename=$1
    mkdir -p "$(dirname "$filename")"
}
backup_file(){
    local file=$1
    local backup=$2
    local padding=$3
    if [[ -z $backup ]]; then backup=$BACKUP_DIR; fi

    targetdir=$(dirname "$file")
    fullpath=$(echo "$targetdir/$(basename $file)")

    if [[ -e $fullpath || -d $fullpath || -h $fullpath ]];
	then
	    # uncomment for verbose backup
	    if [[ $VERBOSE == 3 ]]; then echo "${space:0:$padding}Backing up: $fullpath => $backup/$TIME_NOW$targetdir"; fi
	    mkdir -p "$backup/$TIME_NOW$targetdir" | sed "s/^/${space:0:$padding}/";
	    mv "$fullpath" "$backup/$TIME_NOW$fullpath" | sed "s/^/${space:0:$padding}/";
    fi
}
cleanup(){
    # TODO
    if [[ -h $target ]]; then
        rm "$target"
    fi
}
list_dirs_recursive(){
    local dir=$1
    if [[ -d $dir ]];
    then
        find -L ${dir} -mindepth 1 -depth -type d -printf "%P\n" | sed '/^$/d' | sort
    fi
}
list_dirs(){
    local dir=$1
    if [[ -d $dir ]];
    then
        find -L ${dir} -maxdepth 1 -depth -type d -printf "%P\n" | sed '/^$/d' | sort
    fi
}
list_files(){
    local dir=$1
    if [[ -d $dir ]];
    then
        find -L ${dir} -maxdepth 1 -type f -printf "%P\n" | sed '/^$/d' | sort
    fi
}
list_files_recursive(){
    local dir=$1
    if [[ -d $dir ]];
    then
        find -L ${dir} -type f -printf "%P\n" | sed '/^$/d' | sort
    fi
}
recreate_dir_structure(){
    local source=$1
    local target=$2
    if [[ -d $source ]]; then
        (
            mkdir -v -p "$target" | sed "s/^/${space:0:5}/"
            cd "$target"
            list_dirs_recursive "$source" | while read dir; do mkdir -p "$dir"; done
        )
    else
        return 1
    fi
}
list_installed(){
    local dir=$1
    list_files $TEMPLATE_ROOT$SANEI_DIR | grep ".install." | sed s/.install.//
}
link(){
    local source=$1
    local target=$2
    local padding=$3
    local newpadding=$(( $padding + 5 ))

    if [[ ! $source == *.gitignore ]]; 
    then
        if [[ $VERBOSE -ge 1 ]]; then info "${space:0:$padding}Linking: ${LIGHTGREEN}${source} ${LIGHTRED}=> ${WHITE}${target}${RESET}"; fi
        backup_file "$target" "" $newpadding
        # this shouldn't be necessary:
        if [[ -h "$target" ]]; then rm "$target"; fi
        # actual link:
        ln -nfs "$source" "$target" | sed "s/^/${space:0:$newpadding}/"
    fi
}
link_all_files(){
    local source=$1
    local target=$2
    if [[ -d $source ]]; then
        if [[ $VERBOSE == 1 ]]; then info "Linking files in directory: ${LIGHTGREEN}${source} ${LIGHTRED}=> ${WHITE}${target}${RESET}"; fi
        (cd $target; list_files "$source" | while read file; do link "$source/$file" "$target/$file" 5; done)
    fi
}
link_all_files_recursive(){
    local source=$1
    local target=$2
    if [[ -d $source ]]; then
        if [[ $VERBOSE -ge 1 ]]; then info "Linking files recursively in: ${LIGHTGREEN}${source} ${LIGHTRED}=> ${WHITE}${target}${RESET}"; fi
        recreate_dir_structure "$source" "$target"
        # (mkdir -v -p $target | sed "s/^/${space:0:5}/"; cd $target; find -L ${source} -mindepth 1 -depth -type d -printf "%P\n" | while read dir; do mkdir -p "$dir"; done)
        (
            cd $target
            list_files_recursive "$source" | while read file; do link "$source/$file" "$target/$file" 5; done
        )
    fi
}
link_all_dirs(){
    local source=$1
    local target=$2
    local padding=$3
    # non-recursive linking of folders #
    local to_link
    for to_link in $(list_dirs $source)
    do
        link $source/$to_link $target/$to_link | sed "s/^/${space:0:$padding}/"
    done
}
add_verbosity_opt(){
    local at_level=$1
    local param=$2
    if [[ -z $param ]]; then param="-v"; fi
    if [[ $VERBOSE -ge $at_level ]]; then
        echo $param
    fi
}
add_silent_opt(){
    local param=$1
    if [[ -z $param ]]; then param="-y"; fi
    if [[ $SILENT -ne true ]]; then
        echo $param
    fi
}
copy_all_files_recursive(){
    local source=$1
    local target=$2
    local padding=$3
    if [[ -d $source ]]; then
        cp $(add_verbosity_opt 1) -T -R $source $target | sed "s/^/${space:0:$padding}/"
    fi
}
fill_template(){
    local source=$1
    local target=$2
    local padding=$3
    local newpadding=$(( $padding + 5 ))
    local key

    if [[ ! $source == *.gitignore ]]; then
        if [[ $VERBOSE == 2 ]]; then info "${space:0:$padding}Copying: ${LIGHTGREEN}${source} ${LIGHTRED}=> ${WHITE}${target}${RESET}"; fi
        backup_file "$target" "" $newpadding
        cp -a "$source" "$target"

	if [[ ! -h $source ]]; then
            for key in ${!ConfigArr[@]}; do
                # debug:
	        	# echo "s/@@${key}@@/${ConfigArr[$key]}/g"
			    # escape
			    newOutput=$(echo ${ConfigArr[$key]} | sed -e 's/[\/&]/\\&/g')
		        sed -i "s/@@${key}@@/${newOutput}/g" "$target"
		        #echo "ConfigArr[$key] = ${ConfigArr[$key]}"
            done
        fi
    fi
}
fill_template_recursive(){
    local source=$1
    local target=$2
    local padding=$3
    local newpadding=$(( $padding + 5 ))
    if [[ -d $source ]]; then
        if [[ $VERBOSE -ge 1 ]]; then info "Copying & filling files recursively in: ${LIGHTGREEN}${source} ${LIGHTRED}=> ${WHITE}${target}${RESET}"; fi
        cleanup "$target"
        recreate_dir_structure "$source" "$target"
        # (mkdir -v -p $target | sed "s/^/${space:0:$newpadding}/"; cd $target; find -L ${source} -mindepth 1 -depth -type d -printf "%P\n" | while read dir; do mkdir -p "$dir"; done)
        #  find -L $source -type f -printf "%P\n"
        (
            cd $target
            # echo "$source/$file" => "$target/$file"; 
            list_files_recursive "$source" | while read file; do fill_template "$source/$file" "$target/$file" $padding; done
        )
    fi
}
enter_container(){
    local container=$1

    REAL_TEMPLATE_ROOT=$TEMPLATE_ROOT
    REAL_BACKUP_DIR=$BACKUP_DIR
    REAL_HOME_DIR=$HOME_DIR
    TEMPLATE_ROOT=/lxc/$container/rootfs
    BACKUP_DIR=$TEMPLATE_ROOT/root/.sanei-backups
    # we always want $HOME of containers to be /root
    HOME_DIR=/root
    CONTAINER_NAME=$container
    info "Entered container ${LIGHTBLUE}$CONTAINER_NAME${RESET}, with root: ${WHITE}$TEMPLATE_ROOT${RESET}."
}
exit_container(){
    TEMPLATE_ROOT=$REAL_TEMPLATE_ROOT
    BACKUP_DIR=$REAL_BACKUP_DIR
    HOME_DIR=$REAL_HOME_DIR
    info "Exited container ${LIGHTBLUE}$CONTAINER_NAME${RESET}."
    unset CONTAINER_NAME
}
is_special_module_runtime(){
    if [ -z $__SPECIAL ]; then
        error "You can't install this module this way. "
        return 1
    fi
}
generate_passphrase() {
    # http://cl4ssic4l.wordpress.com/2011/05/12/generate-strong-password-inside-bash-shell/
    local l=$1
    [ "$l" == "" ] && l=20
    tr -dc A-Za-z0-9_ < /dev/urandom | head -c ${l} | xargs
}
is_empty_config(){
    # http://stackoverflow.com/questions/228544/how-to-tell-if-a-string-is-not-defined-in-a-bash-shell-script

    local varname_to_test="$1"
    # echo "testing for empty: $varname_to_test (${!varname_to_test})"
    # if [ -z "${!varname_to_test}" ] && [ "${!varname_to_test+test}" = "test" ]; then
    if [ -z "${!varname_to_test}" ]; then
        # echo "empty"
        return 0
    else
        # echo "not empty"
        return 1
    fi
}
ask_for_config(){
    local var="$1"
    local input
    read input
    if [[ -z "$input" ]]; then
        return 1
    else
        store_shared_config "$var" "$input"
    fi
}
resolve_settings(){
    local error=false
    local var
    for var in "$@"
    do
        # echo "testing for resolve of $var"
        if is_empty_config "$var"; then
            info "You need to provide ${WHITE}${var}${RESET} first:"
            if ! ask_for_config "$var"; then
                error=true
            fi
        fi
    done
    if $error; then
        exit 1
    fi
}
# dialog:
dialog_setup_vars(){
    : ${DIALOG=dialog}
    : ${DIALOG_OK=0}
    : ${DIALOG_CANCEL=1}
    : ${DIALOG_HELP=2}
    : ${DIALOG_EXTRA=3}
    : ${DIALOG_ITEM_HELP=4}
    : ${DIALOG_ESC=255}
}
dialog_setup_tempfile(){
    tempfile=$(tempfile 2>/dev/null) || tempfile=/tmp/test$$
    trap "rm -f $tempfile" 0 1 2 5 15
}
dialog_selector_generate(){
    dialog_setup_vars
    dialog_setup_tempfile
    local title=$1
    local text=$2
    local values=$3

    DIALOG_CMD="$DIALOG --backtitle "SANEi" --title '"$(echo $title)"' --checklist '"$(echo "$text \n\nPress SPACE to toggle a value on/off.")"' 20 50 10 $values 2> $tempfile"
    eval $DIALOG_CMD
    return $?
}
# TODO: belongs to parser
source_parsed_fields(){
    local all_vars="$1"
    local output_prefix="${2:-VAR_}"
    local output_temp_path="${3:-/tmp}"

    for key in ${all_vars}; do
        field_name="${output_prefix}$(sanitize "$key")"

        # field_name="$(sanitize "$key")"
        if [[ $VERBOSE -gt 4 ]]; then 
            echo Exporting field "$field_name", with the value "$(cat "$output_temp_path/$field_name")"
        fi
        export "$field_name"="$(cat "$output_temp_path/$field_name")"
        # export "$field_name"="$(cat "$output_temp_path/$key")"
        rm "$output_temp_path/$field_name"
        # rm "$output_temp_path/$key"
    done
    # echo OPICA $PARSED_relaymail_MODULE
}
sanei_parsing_info(){
    local module="$1"
    local operation="$2"
    local var_prefix="${3:-PARSED_${module}_}"
    #echo parsing "$MODULES_DIR/$module/README.rst"
    if [[ -f "$MODULES_DIR/$module/README.rst" ]]; then
        NO_SUBSHELL=true sanei_invoke_module_script sanei parse-raw "$MODULES_DIR/$module/README.rst" "$var_prefix"
        # source_parsed_fields "${var_prefix}FIELDS_LIST" "$var_prefix"
        source_parsed_fields "$PARSED_FIELDS_LIST" "$var_prefix"

        # declare -p PARSED_FIELDS_LIST
        # echo "$var_prefix"
    fi
    if [[ -f "$MODULES_DIR/$module/$operation.sh" ]]; then
        NO_SUBSHELL=true sanei_invoke_module_script sanei parse-sh "$MODULES_DIR/$module/$operation.sh" "$var_prefix"
        source_parsed_fields "$PARSED_FIELDS_LIST" "$var_prefix"

        # declare -p PARSED_FIELDS_LIST
        # echo "$var_prefix"
    fi
    # echo OPICA $PARSED_relaymail_MODULE
}
# sanei specific functions:
sanei_invoke_module_script(){
    # $1 module
    # $2 script
    # $@ arguments
    local MODULE_DIR
    local LOCAL_MODULE_DIR
    local SHARED_MODULE_DIR
    ((INVOKED_COUNT++))
    if [[ $1 && -d $SCRIPT_DIR/modules/$1 ]]; then
        if [[ -f $SCRIPT_DIR/modules/$1/$2.sh ]]; then
            if [[ -z $NO_SUBSHELL ]]; then
            ( # start a subshell
                # locally available variables
                MODULE="$1"
                OPERATION="$2"
                MODULE_DIR="$SCRIPT_DIR/modules/$MODULE"
                LOCAL_MODULE_DIR="$SANEI_DIR/$MODULE"
                SHARED_MODULE_DIR="$COMMON_DIR/$MODULE"
                if [[ -f $MODULE_DIR/functions.sh ]]; then
                    source $MODULE_DIR/functions.sh
                fi

                # TODO: deprecated:

                if [[ -f $MODULE_DIR/dependencies.sh ]]; then
                    source $MODULE_DIR/dependencies.sh
                fi
                # new system of dependencies:
                if [[ $OPERATION != "install" ]]; then
                    # (
                    # )
                    # TODO: this is duplicated code, fix me

                    local module_for_export="${MODULE//[+.-]/}"
                    local parsed_prefix="${module_for_export^^}_" # let's uppercase

                    eval export "${parsed_prefix}ENVVAR" "_"
                    eval export "${parsed_prefix}DEPENDENCIES" "_"

                    sanei_parsing_info $module "install" "${parsed_prefix}"

                    eval _settings="\${${parsed_prefix}ENVVAR[@]}_"
                    eval _dependencies="\${${parsed_prefix}DEPENDENCIES[@]}_"

                    if [[ $_settings != "_" ]]; then
                        eval resolve_settings "\${${parsed_prefix}ENVVAR[@]}" # ${VAR_ENVVAR[@]}
                    fi
                    if [[ $_dependencies != "_" ]]; then
                        eval sanei_resolve_dependencies "\${${parsed_prefix}DEPENDENCIES[@]}" #${VAR_DEPENDENCIES[@]}
                    fi
                    unset _settings
                    unset _dependencies
                    unset module_for_export
                    unset parsed_prefix
            
                    # eval resolve_settings "\${PARSED_${MODULE}_ENVVAR[@]}" # ${VAR_ENVVAR[@]}
                    # eval sanei_resolve_dependencies "\${PARSED_${MODULE}_DEPENDENCIES[@]}" #${VAR_DEPENDENCIES[@]}
                fi

                # "" at the end as we must pass a final empty argument not to break certain scripts
                source "$MODULE_DIR/$2.sh" "${@:3:${#@}}" "";
            )
            else
                source "$SCRIPT_DIR/modules/$1/$2.sh" "${@:3:${#@}}" "";
                unset NO_SUBSHELL
            fi
        else
            if [[ $2 ]]; then
                error "No operation $2 for module $1."
            fi
            echo "Available commands are:"
            list_files "$SCRIPT_DIR/modules/$1" | grep "\.sh$" | sed s/.sh$// | sed "s/^/  /"
        fi
    else
        return 1
    fi
}
sanei_install_select(){
    local module
    dialog_selector_generate 'SELECT MODULES TO INSTALL' "Use this to mass install \n\
modules on the local system" "$(sanei_list_modules_with_status true)"
    retval=$?
    case $retval in
      $DIALOG_OK)
        for module in $(cat $tempfile); do
            if ! is_installed $(eval echo "$module"); then
                sanei_install $(eval echo "$module")
            fi
        done
        ;;
      $DIALOG_CANCEL)
        info "Cancelled."
        ;;
      $DIALOG_ESC)
        if test -s $tempfile ; then
          # cat $tempfile
          error "This shouldn't happen."
        else
          info "ESC pressed."
        fi
        ;;
    esac
}
sanei_install(){
    local module=$1

    if [[ ! -z $module ]]; then
        if [[ -d $SCRIPT_DIR/modules/$module ]]; then
            if is_installed "$module"; then
                if [[ ! $REINSTALL ]]; then
                    info "You already installed: $module. Skipping..."
                    return 1
                else
                    local re="RE"
                    rm_installed "$module"
                fi
            fi
            # ( 
            # )

            local module_for_export="${module//[+.-]/}" # interesting quirk - doesn't work with: +-.
            local parsed_prefix="${module_for_export^^}_" # let's uppercase

            eval export "${parsed_prefix}ENVVAR" "_"
            eval export "${parsed_prefix}DEPENDENCIES" "_"

            sanei_parsing_info $module "install" "${parsed_prefix}"

            eval _settings="\${${parsed_prefix}ENVVAR[@]}_"
            eval _dependencies="\${${parsed_prefix}DEPENDENCIES[@]}_"

            if [[ $_settings != "_" ]]; then
                eval resolve_settings "\${${parsed_prefix}ENVVAR[@]}" # ${VAR_ENVVAR[@]}
            fi
            if [[ $_dependencies != "_" ]]; then
                eval sanei_resolve_dependencies "\${${parsed_prefix}DEPENDENCIES[@]}" #${VAR_DEPENDENCIES[@]}
            fi
            unset _settings
            unset _dependencies
            unset module_for_export
            unset parsed_prefix

            info "${LIGHTBLUE}WILL ${re}INSTALL: ${WHITE}$module${RESET}."

            if [[ -f $SCRIPT_DIR/modules/$module/question.sh ]]; then
                askbreak "$( $SCRIPT_DIR/modules/$module/question.sh ${@:2:${#@}} )"
            else
                askbreak "Are you sure this is what you want?"
            fi

            if [[ -f $SCRIPT_DIR/modules/$module/install.sh ]]; then
                sanei_invoke_module_script "$module" install ${@:2:${#@}}
                if ! is_installed $module; then
                    set_installed $module
                fi
            else
                set_installed $module
            fi
        else
            error "Module $module does not exist."
        fi
    else
        sanei_install_select
        #error "No module provided."
    fi
}
sanei_automatic_selfupgrade(){
    if [[ -n $SANEI_AUTOMATIC_SELFPUSH ]]; then
        if [[ -n $(git status -s) ]]; then
            sanei_invoke_module_script sanei-selfupdate updateremote
        fi
    fi
    if [[ -n $SANEI_AUTOMATIC_SELFUPGRADE ]]; then
        sanei_invoke_module_script sanei-selfupdate updatelocal
    fi
}
sanei_create_module_dir(){
    subpath=$1 # optional
    if [[ ! -z $LOCAL_MODULE_DIR ]]; then
        mkdir -p "$LOCAL_MODULE_DIR$subpath"
    else
        error "Local module directory not defined."
        return 1
    fi
}
sanei_create_shared_module_dir(){
    subpath=$1 # optional
    if [[ ! -z $SHARED_MODULE_DIR ]]; then
        mkdir -p "$SHARED_MODULE_DIR$subpath"
    else
        error "Local module directory not defined."
        return 1
    fi
}
sanei_resolve_dependencies(){
    REAL_LOCAL_MODULE_DIR=$LOCAL_MODULE_DIR
    local module
    for module in "$@"
    do
        if ! is_installed "$module"; then
            if [[ $module == apt\:* ]]; then
                apt_package=$(echo "$module" | cut -c "5-")
                if ! is_apt_installed "$apt_package"; then
                    askbreak "In order to continue, apt package $apt_package needs to be installed."
                    if ! apt_install "$apt_package"; then
                        exit 1
                    fi
                fi
                # set_installed "$module"
            else
                info "In order to continue, $module needs to be installed."
                sanei_install "$module"
            fi
        fi
    done
    LOCAL_MODULE_DIR=$REAL_LOCAL_MODULE_DIR
}
sanei_update(){
    # TODO: change $TEMPLATE_ROOT for a local variable passed to the function
    # TODO: support multiple modules passed
    local module=$1

    if [[ ! -z $module && -d $SCRIPT_DIR/modules/$module ]]; then
        info "${LIGHTRED}UPDATING${RESET}: ${WHITE}${module}${RESET}."

        # TODO: add a function to do this also before invoking a module script
        store_memory_config MODULE "$module"
        store_memory_config MODULE_DIR "$SCRIPT_DIR/modules/$module"

        # /etc #
        # recursive linking #
        link_all_files_recursive $SCRIPT_DIR/modules/$module/etc $TEMPLATE_ROOT/etc $PADDING_SIZE

        # recursive copying and filling #
        fill_template_recursive $SCRIPT_DIR/modules/$module/etc-template $TEMPLATE_ROOT/etc $PADDING_SIZE

        # recursive copying #
        copy_all_files_recursive $SCRIPT_DIR/modules/$module/etc-copy $TEMPLATE_ROOT/etc $PADDING_SIZE

        # non-recursive linking of folders #
        link_all_dirs $SCRIPT_DIR/modules/$module/etc-link $TEMPLATE_ROOT/etc $PADDING_SIZE

        # others #
        # copy /usr if exists #
        copy_all_files_recursive $SCRIPT_DIR/modules/$module/usr $TEMPLATE_ROOT/usr $PADDING_SIZE

        # dotfiles
        fill_template_recursive $SCRIPT_DIR/modules/$module/root-template $TEMPLATE_ROOT$HOME_DIR $PADDING_SIZE

        if [[ -d $SCRIPT_DIR/modules/$module/root ]]; then
            if [[ "$HOME_DIR" == "/root" ]]; then
                link_all_files $SCRIPT_DIR/modules/$module/root $TEMPLATE_ROOT$HOME_DIR $PADDING_SIZE
                # link also folders #
                link_all_dirs $SCRIPT_DIR/modules/$module/root $TEMPLATE_ROOT$HOME_DIR $PADDING_SIZE
            else # if we're not using root - we don't want permissions problems
                copy_all_files_recursive $SCRIPT_DIR/modules/$module/root $TEMPLATE_ROOT$HOME_DIR $PADDING_SIZE
            fi
        fi

        if [[ -f $SCRIPT_DIR/modules/$module/post-update.sh ]]; then
            source $SCRIPT_DIR/modules/$module/post-update.sh
        fi

        if [ "$HOME_DIR" != "/root" ]; then
            if [[ "$PARENT_USERNAME" != "root" ]]; then
                chown -R "$PARENT_USERNAME:$PARENT_USERNAME" "$TEMPLATE_ROOT$HOME_DIR"
            # if logname 2&> /dev/null; then
            #     user=$(logname)
            #     # TODO: do this at the copying/linking level
            #     chown -R "$user:$user" "$TEMPLATE_ROOT$HOME_DIR"
            # elif [[ "$SUDO_USER" ]]; then
            #     user="$SUDO_USER"
            #     chown -R "$user:$user" "$TEMPLATE_ROOT$HOME_DIR"
            else
                error "Cannot find the real username (you didn't use sudo -s ?)."
            fi
        fi
    else
        error "No module provided or module ${WHITE}$module${RESET} doesn't exist."
    fi
}
sanei_updateall(){
    # TODO: change $TEMPLATE_ROOT for a local variable passed to the function
    local module
    for module in $(list_installed)
    do
        sanei_update $module
    done
}
sanei_updateall_containers(){
    # for each container that wants to have auto-updated links
    local containers=($(/usr/bin/lxc-ls -1))

    for container in ${containers[@]}
    do
        enter_container $container
            #TEMPLATE_ROOT=/lxc/$container/rootfs
            sanei_updateall
        exit_container
    done
}
sanei_all_containers_setinstalled(){
    sanei_override true true
}
sanei_override(){
    local setinstalled="$1"
    local process_all_containers="$2"
    local removeunselected="$3"
    local module

    if [[ ! -z process_all_containers ]]; then
        local containers=($(/usr/bin/lxc-ls -1))
    fi

    dialog_selector_generate 'MODULE OVERRIDE LIST' "Use this to override the installed \n\
modules on the local system" "$(sanei_list_modules_with_status true)"
    # dialog_selector_generate testa testa 'test test on'
    retval=$?
    case $retval in
      $DIALOG_OK)
        if [[ -z process_all_containers ]]; then
            if [[ -n removeunselected ]]; then
                sanei_clean_installed_modules
            fi
            for module in $(cat $tempfile); do
                    if [[ -z setinstalled ]]; then
                        set_installed $(eval echo "$module") norun noinfo # TODO FIX
                    else
                        set_installed $(eval echo "$module")
                    fi
            done
        else
            for container in ${containers[@]}
            do
                enter_container "$container"
                    if [[ -n removeunselected ]]; then
                        sanei_clean_installed_modules
                    fi
                    for module in $(cat $tempfile); do
                            if [[ -z setinstalled ]]; then
                                set_installed $(eval echo "$module") norun noinfo # TODO FIX
                            else
                                set_installed $(eval echo "$module")
                            fi
                    done
                exit_container
            done
        fi
        ;;
      $DIALOG_CANCEL)
        info "Cancelled."
        ;;
      $DIALOG_ESC)
        if test -s $tempfile ; then
          # cat $tempfile
          error "This shouldn't happen."
        else
          info "ESC pressed."
        fi
        ;;
    esac
}
sanei_list_modules(){
    list_dirs $SCRIPT_DIR/modules
}
sanei_list_modules_with_status(){
    local dialog_mode="$1"
    local module
    for module in $(sanei_list_modules); do
        if [[ $dialog_mode ]]; then
            printf "$module $(sanei_get_module_description $module) $(if is_installed $module; then printf on; else printf off; fi) "
        else
            echo $(if is_installed $module; then echo -e ${LIGHTBLUE}; else echo -e ${LIGHTRED}; fi) "$module" "${RESET}"
        fi
    done
}
sanei_clean_installed_modules(){
    local module
    for module in $(sanei_list_modules); do
        rm_installed $module
    done
}
sanei_get_module_description(){
    local module="$1"
    # TODO:
    printf "\"\""
}