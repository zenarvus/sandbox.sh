#!/bin/sh

set -e # Exit on first error

### TERMINOLOGY & HELP ##############################

_print_help() {
	echo "Usage: $(basename "$0") [command] <args>"
	echo "=== COMMANDS ==="
	echo "- newcont <container_name> <container_type>: create a container with given name and type"
	echo "- newbox <container_name> <sandbox_name>: create a new sandbox in a given container"
	echo "- cleanbox <container_name> <sandbox_name>: remove duplicate files from the sandbox that match the rootfs"
	echo "- mexc: <container_name> <args>: execute a command in master mode"
	echo "- sexc: <container_name> <sandbox_name> <args>: execute a command in sandbox mode"
	echo "- exec <container_name> <sandbox_name> <args>: execute a command in unprivilaged mode"
	echo
	echo "You can pass BWRAP_EXTRA variable to, for example, bind some extra mount points."
	echo
	echo "=== TERMINOLOGY ==="
	echo "- container: The folder with a specific rootfs from a distro like alpine, void linux etc."
	echo "- sandbox: An overlay folder on top of the container rootfs. rootfs is mounted read-only and changes in this sandbox applied to this isolated folder."
	echo "- master-mode: The shell that directly modifies the container rootfs. It is used to install essential packages used by lot of sandboxes at once."
 	echo "- sandbox-mode: The shell that modifies the sandbox work directory. It has all the privilages to manage the sandbox (install to and delete things from it) and should not be used to launch apps."
	echo "- unprivilaged-mode: The mode where sandbox and master folders are read only and changes are only allowed in home and explicitly binded directories."
}

#### CONFIG ###############################

CONTAINER_DIR="/mnt/secure/sandbox/container"

ROOTFS_TAR_DIR="/mnt/secure/sandbox" # The directory that contains rootfs.tar.gz files

#### VARIABLES ################################
#HOST_SYSTEM_BUS="/run/dbus/system_bus_socket" # steam requires binding system_bus_socket or it will stuck at waiting for network screen. But I do not use steam so it's fine. If u wanna run steam, uncomment this and add this line to BWRAP_BUS: '--ro-bind "$HOST_SYSTEM_BUS" /run/dbus/system_bus_socket'
XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:?}" # The host XDG_RUNTIME_DIR
SANDBOX_RUNTIME_DIR="/tmp/1000" # The path of the XDG_RUNTIME_DIR inside the container that only binds essential runtime sockets from the host.

DISPLAY="${DISPLAY:-:0}"
WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-1}"

#X11_SOCKET="/tmp/.X11-unix/X${DISPLAY#:}" # Things using x11 will be keylog each other etc. It's insecure.
PULSE_SOCKET="$XDG_RUNTIME_DIR/pulse/native"
PIPEWIRE_SOCKET="$XDG_RUNTIME_DIR/pipewire-0"

#### BWRAP SETTINGS #################################
BWRAP_BASIC="--die-with-parent --unshare-pid --unshare-user --uid 1000 --gid 1000 --new-session"

BWRAP_PLUS="--dev /dev \
--dev-bind /dev/dri /dev/dri \
\
--ro-bind /sys /sys \
--proc /proc \
--tmpfs /tmp \
--tmpfs /run"

BWRAP_BUS="--dir "$SANDBOX_RUNTIME_DIR" \
--ro-bind "$PULSE_SOCKET" "$SANDBOX_RUNTIME_DIR/pulse/native" \
--ro-bind "$PIPEWIRE_SOCKET" "$SANDBOX_RUNTIME_DIR/pipewire-0" \
--ro-bind "$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY" "$SANDBOX_RUNTIME_DIR/$WAYLAND_DISPLAY" \
\
--setenv DISPLAY "$DISPLAY" \
--setenv WAYLAND_DISPLAY "$WAYLAND_DISPLAY" \
--setenv XDG_RUNTIME_DIR "$SANDBOX_RUNTIME_DIR""

BWRAP_NET="--ro-bind /etc/resolv.conf /etc/resolv.conf \
--ro-bind "$(realpath /etc/localtime)" /etc/localtime"

BWRAP_USER="--setenv USER user --setenv HOME /home/user \
--setenv XDG_CONFIG_HOME /home/user/.config \
--setenv PATH /usr/bin:/usr/sbin:/bin:/sbin"

#### CONTAINER ACTIONS ##################################

new_container() {
	echo "setting up container"

	CONTAINER_NAME="$1"

	# Do not create if the container already exists.
	if [ -d "$CONTAINER_DIR/$CONTAINER_NAME" ]; then
		echo "this container already exists"
		exit 1
	fi

	# The second argument is the rootfs type. It must be a .tar.gz file and must contain /bin/sh.
	ROOTFS_TYPE="$2"

	if [ ! -f "$ROOTFS_TAR_DIR/$ROOTFS_TYPE.tar.gz" ]; then
		echo "rootfs file does not exists"
		exit 1
	fi
	
	CONTAINER_ROOTFS_PATH="$CONTAINER_DIR/$CONTAINER_NAME/rootfs"

	mkdir -p "$CONTAINER_ROOTFS_PATH"

	echo "extracting the rootfs archive"

	# Extract the tar.gz archive
	tar -vxzf "$ROOTFS_TAR_DIR/$ROOTFS_TYPE.tar.gz" -C "$CONTAINER_ROOTFS_PATH"

	# Create essential paths for binding
	touch "$CONTAINER_ROOTFS_PATH/etc/localtime"
	mkdir -p "$CONTAINER_ROOTFS_PATH/run/dbus"
	touch "$CONTAINER_ROOTFS_PATH/run/dbus/system_bus_socket"
	
	echo "rootfs extract successful"
	
	echo "creating user"

	# create user named "user" with uid of 1000
	# this will be the user we will use instead of root
	
	# add user to /etc/passwd
	# Format: username:password:UID:GID:GECOS:home_directory:shell
	echo "user:x:1000:1000:User,,,:/home/user:/bin/sh" >> "$CONTAINER_ROOTFS_PATH/etc/passwd"
	# add user to /etc/shadow
	# Format: username:password_hash:last_change:min:max:warn:inactive:expire:reserved
	echo "user::19000:0:99999:7:::" >> "$CONTAINER_ROOTFS_PATH/etc/shadow"
	# add primary user group to /etc/group
	# Format: group_name:password:GID:user_list
	echo "user:x:1000:" >> "$CONTAINER_ROOTFS_PATH/etc/group"
	# Create home directory for user
	mkdir -p "$CONTAINER_ROOTFS_PATH/home/user"

	echo "user created"
	
	echo "container setup successful"
}

# create a sandbox in a given container
new_sandbox() {
	CONTAINER_NAME="$1"
	if [ ! -d "$CONTAINER_DIR/$CONTAINER_NAME" ]; then
		echo "this container does not exists"
		exit 1
	fi

	SANDBOX_NAME="$2"
	SANDBOX_DIR="$CONTAINER_DIR/$CONTAINER_NAME/sandbox/$SANDBOX_NAME"
	if [ -d "$SANDBOX_DIR" ]; then
		echo "this sandbox already exists"
		exit 1
	fi   

	mkdir -p "$SANDBOX_DIR/upper"
	mkdir -p "$SANDBOX_DIR/work"
	mkdir -p "$SANDBOX_DIR/home"

	echo "sandbox created"
}

clean_sandbox() {
    [ "$#" -lt 2 ] && _print_help && exit 1
    
    CONTAINER_NAME="$1"
    SANDBOX_NAME="$2"

    ROOTFS_PATH="$CONTAINER_DIR/$CONTAINER_NAME/rootfs"
    SANDBOX_UPPER="$CONTAINER_DIR/$CONTAINER_NAME/sandbox/$SANDBOX_NAME/upper"

    if [ ! -d "$ROOTFS_PATH" ] || [ ! -d "$SANDBOX_UPPER" ]; then
        echo "container or Sandbox upper directory not found."
        exit 1
    fi

    echo "Scanning for duplicate files in sandbox '$SANDBOX_NAME'..."

    # Find all regular files in the upper directory and iterate over them
    find "$SANDBOX_UPPER" -type f -print0 | while IFS= read -r -d '' FILE_UPPER; do
        # Extract the relative path of the file
        REL_PATH="${FILE_UPPER#$SANDBOX_UPPER}"
        FILE_ROOTFS="$ROOTFS_PATH$REL_PATH"

        # Check if the exact file path also exists in the lower directory (rootfs)
        if [ -f "$FILE_ROOTFS" ]; then
            # cmp -s checks if files are identical. It is much faster than hashing.
            if cmp -s "$FILE_UPPER" "$FILE_ROOTFS"; then
                echo "Removing duplicate: $REL_PATH"
                rm -f "$FILE_UPPER"
            fi
        fi
    done

	# Remove any directories that are now empty after file deletion
    find "$SANDBOX_UPPER" -type d -empty -delete 2>/dev/null || true

    echo "Cleanup complete."
}

#### EXECUTION MODES #############################

_master_bwrap() {

	# If the argument count is less than 1, exit
	[ "$#" -lt 1 ] && _print_help && exit 1

	CONTAINER_NAME="$1"; shift

	CMD="$@"
	[ "$#" -lt 1 ] && CMD="/bin/sh" # If argument count is zero, fallback to /bin/sh

	env -i bwrap \
		$BWRAP_BASIC \
		\
		--bind "$CONTAINER_DIR/$CONTAINER_NAME/rootfs" / \
		\
		$BWRAP_PLUS \
		$BWRAP_NET \
		$BWRAP_BUS \
		$BWRAP_USER \
		$BWRAP_EXTRA \
        \
        --setenv PS1 "\u@$CONTAINER_NAME:\w\: " \
		-- $CMD
}

_sandbox_bwrap() {
	# If the argument count is less than 2, exit
	[ "$#" -lt 2 ] && _print_help && exit 1

	CONTAINER_NAME="$1"; SANDBOX_NAME="$2"; shift 2

	CMD="$@"
	[ "$#" -lt 1 ] && CMD="/bin/sh" # If argument count is zero, fallback to /bin/sh

	SANDBOX_DIR="$CONTAINER_DIR/$CONTAINER_NAME/sandbox/$SANDBOX_NAME"

	env -i bwrap \
		$BWRAP_BASIC \
		\
		--overlay-src "$CONTAINER_DIR/$CONTAINER_NAME/rootfs" \
		--overlay "$SANDBOX_DIR/upper" "$SANDBOX_DIR/work" / \
		--bind "$SANDBOX_DIR/home" /home/user \
		\
		$BWRAP_PLUS \
		$BWRAP_NET \
		$BWRAP_BUS \
		$BWRAP_USER \
		$BWRAP_EXTRA \
        \
        --setenv PS1 "\u@$CONTAINER_NAME:$SANDBOX_NAME:\w\: " \
		\
		-- $CMD
}

_unprivilaged_bwrap() {
	# If the argument count is less than 2, exit
	[ "$#" -lt 2 ] && _print_help && exit 1

	CONTAINER_NAME="$1"; SANDBOX_NAME="$2"; shift 2

	CMD="$@"
	[ "$#" -lt 1 ] && CMD="/bin/sh" # If argument count is zero, fallback to /bin/sh
    
	env -i bwrap \
        $BWRAP_BASIC \
		\
        --overlay-src "$CONTAINER_DIR/$CONTAINER_NAME/rootfs" \
		--overlay-src "$CONTAINER_DIR/$CONTAINER_NAME/sandbox/$SANDBOX_NAME/upper" \
        --ro-overlay / \
        --bind "$CONTAINER_DIR/$CONTAINER_NAME/sandbox/$SANDBOX_NAME/home" /home/user \
		\
		$BWRAP_PLUS \
		$BWRAP_NET \
		$BWRAP_BUS \
		$BWRAP_USER \
		$BWRAP_EXTRA \
        \
		--cap-drop ALL \
        --setenv PS1 "\u@$CONTAINER_NAME:$SANDBOX_NAME:\w\: " \
		\
        -- $CMD
}

### START ############################

# Main script logic

# If the argument count is less than 1, exit
[ "$#" -lt 1 ] && _print_help && exit 1

COMMAND="$1"
shift

case "$COMMAND" in
newcont) new_container "$@" ;;
newbox) new_sandbox "$@" ;;
cleanbox) clean_sandbox "$@" ;;
mexc) _master_bwrap "$@" ;;
sexc) _sandbox_bwrap "$@" ;;
exec) _unprivilaged_bwrap "$@" ;;
*) _print_help; exit 1 ;;
esac
