# TODO: adjust to CI environment
ARG baseImage="ionutbalutoiu/kube-proxy-windows-base:10.0.17763.1282"

FROM ${baseImage}

ARG k8sVersion="v1.18.3"

ADD kube-proxy.exe /k/kube-proxy/kube-proxy.exe

# When cross-building from a Linux environment with Docker buildx, the PATH is
# inherited from the environment building the image. Therefore, the Windows
# Docker image will have the PATH broken, unless we explicitly set it to
# overwrite the default behaviour.
ENV PATH "C:\Windows\system32;C:\Windows;C:\Windows\System32\Wbem;C:\Windows\System32\WindowsPowerShell\v1.0\;C:\Windows\System32\OpenSSH\;C:\Users\ContainerAdministrator\AppData\Local\Microsoft\WindowsApps;C:\utils;"
