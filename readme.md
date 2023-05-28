
# spkcli.sh

## Features

* Common aliases
* Publish in container or via GitHub (requires gh cli)
* Test script (alpha)
  * Caveat: Packages with wizards will fail to install if they han't been designed with empty/defaults input
* Update script (beta)


## Usage

1. Copy the files to the root of the spksrc reposetory:

```
wget https://raw.githubusercontent.com/publicarray/spkcli/main/spkcli.sh; wget https://raw.githubusercontent.com/publicarray/spkcli/main/test; printf "SSH_HOST=\"dsm7-dev\"\nSSH_PASS=\"\"" > .env
```
Note: you may want to update your `~/.ssh/config` to include your NAS as an alias: e.g
```
Host dsm7-dev
   HostName 10.0.0.3
   User admin
```

3. Update the `.env` file

```
./spkcli [COMMAND]
    build [SPK] {ARCH}      build packages for development (x64-7.0)
    clean [SPK]             clean package
    clean-all               clean all builds and cached files in /distrib
    digest [SPK]            update digests
    lint                    run make lint
    publish [SPK] {ARCH}    build and publish for all DSM architectures
    publish-ci [SPK] true   build and publish for all supported DSM versions/architectures using GitHub Actions
    pull                    git pull & docker image pull
    run                     run container for development
    test [SPK FILE] [SPK]   run test script on NAS via ssh
    update [SPK]            check for git releases for an update
```

## Examples

### Failed test Report

```
./spkcli test packages/bazarr_x64-7.0_1.0.0-1.spk bazarr
 System Information
	Date: 2021-11-07 01:04
	Whoami: root
	Hostname: DSM7
	Architecture: kvmx64, x86_64
	Model: virtualdsm
	Firmware Version: 7.0.1-42218
	Build date: 2021/10/18 21:16:50
	Kernel: Linux DSM7 4.4.180+ #42218 SMP Mon Oct 18 19:17:55 CST 2021 x86_64 GNU/Linux synology_kvmx64_virtualdsm
	Package Center Channel: beta
	Language: def
	VAAI support: yes
	Installed Memory: 2002
Filesystem      Size  Used Avail Use% Mounted on
/dev/sdb1        18G  3.9G   14G  23% /volume1
 Running Tests
{"error":{"code":0},"results":[{"action":"upgrade","beta":false,"betaIncoming":false,"error":{"code":0},"finished":true,"installReboot":false,"installing":true,"language":"enu","last_stage":"postupgrade","package":"bazarr","packageName":"Bazarr","pid":3219,"scripts":[{"code":0,"message":"","type":"preupgrade"},{"code":0,"message":"","type":"preuninst"},{"code":0,"message":"","type":"postuninst"},{"code":0,"message":"","type":"preinst"},{"code":0,"message":"","type":"postinst"},{"code":0,"message":"","type":"postupgrade"}],"spk":"bazarr_x64-7.0_1.0.0-1.spk","stage":"installed_and_stopped","status":"stop","success":true,"username":""}],"success":true}
✅ [pass] Installed bazarr_x64-7.0_1.0.0-1.spk
✅ [pass] Install log file exists
2021/11/07 01:05:02	ERROR:root:failed to read config file /root/.config/virtualenv/virtualenv.ini because PermissionError(13, 'Permission denied')
❌ [fail] Install logfile is free of errors
2021/11/07 01:05:03	WARNING: The directory '/root/.cache/pip' or its parent directory is not owned or is not writable by the current user. The cache has been disabled. Check the permissions and owner of that directory. If executing pip with sudo, you should use sudo's -H flag.
2021/11/07 01:05:39	    Can't uninstall 'greenlet'. No files were found to uninstall.
 [ignored] Install logfile is free of warnings
✅ [pass] Embedded package icon
ℹ [info] Package has a service
✅ [pass] Package has both the firewall rule and admin port
dst.ports="6767/tcp"
✅ [pass] Admin port is included in the firewall rule
✅ [pass] Firewall rule is installed
✅ [pass] Valid json for app/config
{"action":"prepare","error":{"code":0},"stage":"prepare","success":true}
✅ [pass] Start bazarr
bazarr package is started
✅ [pass] Status bazarr
{"action":"prepare","error":{"code":0},"stage":"prepare","success":true}
✅ [pass] Stop bazarr
bazarr package is stopped
Status: [3]
✅ [pass] Status bazarr
 Package Information
	Filename: bazarr_x64-7.0_1.0.0-1.spk
	Name: bazarr
	Version: 1.0.0-1
	Display Name: Bazarr
	Admin Port: 6767
	Minimum DSM version: 7.0-41890
	Dependency Packages: python38:ffmpeg
	Install Log: "/var/log/packages/bazarr.log"
	Run Log: The log file is /volume1/@appdata/bazarr/bazarr_temp.log
removed 'bazarr_x64-7.0_1.0.0-1.spk'

[1] Test failed  😢
```
