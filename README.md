# WireGuard HTTP/s Proxy with TinyProxy

This project provides a minimal WireGuard HTTP/s proxy using TinyProxy. It allows you to run WireGuard as a VPN tunnel and route HTTP traffic through TinyProxy. This can be used in environments where WireGuard is needed for secure tunneling, and TinyProxy is used to manage HTTP/s traffic.

## Features

- **WireGuard VPN**: Establishes secure VPN tunnels.
- **TinyProxy HTTP Proxy**: Routes HTTP/s traffic via a local proxy server.
- **Health Check**: Ensures the proxy and VPN are running correctly.
- **Custom Configurations**: Allows users to configure WireGuard tunnels and TinyProxy behavior via configuration files.

### Base image

The project uses a custom Docker image based on `linuxserver/wireguard` with TinyProxy added.
[Github Repo](https://github.com/linuxserver/docker-wireguard)
### Initial source

The repo is based on the [wireguard-http-proxy](https://github.com/noamanahmed/wireguard-http-proxy) project.


### start.sh

The ```start.sh``` script manages the lifecycle of TinyProxy and WireGuard. It ensures that both TinyProxy and WireGuard are running and handles cleanup when the container is stopped.

### healthcheck.sh

The ```healthcheck.sh``` script checks the health of the WireGuard tunnels by pinging various endpoints. If any of the tunnels are down or unreachable, the script will fail, which helps to detect issues with the setup.

### Configuration
#### Wireguard
The WireGuard configuration files should be placed in the container at ```/config/wg_confs/``` directory, or ```/conf.d/wireguard/gb_confs``` for docker compose . The start.sh script will automatically detect and load the configuration files.
#### TinyProxy
Customized TinyProxy configuration file can be placed in the container at ```/app/tinyproxy/``` directory. The start.sh script will automatically detect and load the configuration file.


# Running the Container
## Docker

You can use included docker compose example at deployment/docker-compose.yaml

Alternatively, to run the container with the default settings, use the following command:
```
docker run -d \
  --name wireguard-proxy \
  --hostname wireguard \
  --env PEERS=false \
  --env PUID=1000 \
  --env PGID=1000 \
  --cap-add NET_ADMIN \
  --cap-add SYS_MODULE \
  --volume ./conf.d/tinyproxy:/tinyproxy \
  --volume ./conf.d/wireguard:/config \
  --volume /lib/modules:/lib/modules \
  --publish 8888:8888/tcp \
  --sysctl net.ipv4.conf.all.src_valid_mark=1 \
  myimage:latest
```
This command will start the container with TinyProxy running on port 8888 and WireGuard tunnels configured via the files in /config/wg_confs/.
## Kubernetes

You can also deploy this setup on Kubernetes using the following configuration files. The example includes an ```initContainer``` to ensure the correct sysctl value is set, along with the necessary configurations for WireGuard and TinyProxy.

#### Healthcheck
Kubernetes does not support Dockerfile ```HEALTHCKECH```, so we need to use a ```livenessProbe``` to check the health of the container. The ```healthcheck.sh``` script is used to check the health of the WireGuard tunnels.

### Configuration

#### TinyProxy
The TinyProxy configuration is stored in a ConfigMap named ```tinyproxy-config```. The ConfigMap is mounted as a volume in the container at ```/app/tinyproxy``` as a ```.conf``` file.

#### WireGuard
The WireGuard configuration files are stored in a Secret named ```wireguard-config```. The Secret is mounted as a volume in the container at ```/config/wg_confs```.

# Licence
This project is licensed under the GNU General Public License v3.0 or later. See the [LICENCE](https://github.com/vst-name/httpproxy-wireguard/blob/main/LICENCE) file for more details.


This version of the `README.md` reflects that the project is licensed under the GNU General Public License v3.0 or later. If you need further details or adjustments, let me know!
