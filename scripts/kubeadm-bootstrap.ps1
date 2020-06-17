Param(
    [parameter(Mandatory=$true)]
    [string]$CIVersion
)

$ErrorActionPreference = "Stop"

function DownloadFile($destination, $source) {
    Write-Output "Downloading $source to $destination"
    curl.exe --silent --fail -Lo $destination $source
    if (!$?) {
        Write-Error "Download $source failed"
        exit 1
    }
}

$global:KubernetesPath = "$env:SystemDrive\k"

iex "nssm stop kubelet"
Stop-Service -Force -Name Docker

DownloadFile "$global:KubernetesPath\kubelet.exe" https://capzwin.blob.core.windows.net/builds/$CIVersion/bin/windows/amd64/kubelet.exe
DownloadFile "$global:KubernetesPath\kubeadm.exe" https://capzwin.blob.core.windows.net/builds/$CIVersion/bin/windows/amd64/kubeadm.exe

Get-HnsNetwork | Remove-HnsNetwork
Get-NetAdapter -Physical | Rename-NetAdapter -NewName "Ethernet"

Start-Service -Name Docker
iex "nssm start kubelet"
