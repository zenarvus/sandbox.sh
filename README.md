A simple, host-integrated, file-system-isolated bubblewrap sandbox environment.

Consider using it when:
- You do not want apps to mess with the host file-system
- You do not want apps to see your confidential files
- You want to install apps in a specific place you want

It does not provide a completely isolated sandbox, but I suppose provides enough sandboxing to run apps you partially trust. Still, do not try to install an obvious malware in it.

- TODO: Use seccomp filters

********

Usage: sandbox.sh [command] <args>
=== COMMANDS ===
- newcont <container_name> <container_type>: create a container with given name and type
- newbox <container_name> <sandbox_name>: create a new sandbox in a given container
- cleanbox <container_name> <sandbox_name>: remove duplicate files from the sandbox that match the rootfs
- mexc: <container_name> <args>: execute a command in master mode
- sexc: <container_name> <sandbox_name> <args>: execute a command in sandbox mode
- exec <container_name> <sandbox_name> <args>: execute a command in unprivilaged mode

You can pass BWRAP_EXTRA variable to, for example, bind some extra mount points.

=== TERMINOLOGY ===
- container: The folder with a specific rootfs from a distro like alpine, void linux etc.
- sandbox: An overlay folder on top of the container rootfs. rootfs is mounted read-only and changes in this sandbox applied to this isolated folder.
- master-mode: The shell that directly modifies the container rootfs. It is used to install essential packages used by lot of sandboxes at once.
- sandbox-mode: The shell that modifies the sandbox work directory. It has all the privilages to manage the sandbox (install to and delete things from it) and should not be used to launch apps.
- unprivilaged-mode: The mode where sandbox and master folders are read only and changes are only allowed in home and explicitly binded directories.
